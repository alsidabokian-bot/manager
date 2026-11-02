import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'file_models.dart';

/// دفعة نتائج من البحث في المجلدات الفرعية.
class SearchBatch {
  const SearchBatch({
    required this.items,
    required this.done,
    required this.truncated,
    required this.scannedDirs,
  });

  final List<FileItem> items;
  final bool done;
  final bool truncated; // بلغنا الحد الأقصى للنتائج
  final int scannedDirs;
}

class _SearchArgs {
  const _SearchArgs(this.out, this.root, this.query, this.showHidden, this.limit);
  final SendPort out;
  final String root;
  final String query;
  final bool showHidden;
  final int limit;
}

/// بحث بالاسم داخل مجلد وكل مجلداته الفرعية، في خيط منفصل قابل للإلغاء.
class FileSearch {
  FileSearch._(this._isolate, this._port);

  final Isolate _isolate;
  final ReceivePort _port;
  bool _closed = false;

  static const int maxResults = 2000;

  static Future<FileSearch> start({
    required String root,
    required String query,
    required bool showHidden,
    required void Function(SearchBatch) onBatch,
  }) async {
    final port = ReceivePort();
    final isolate = await Isolate.spawn(
      _searchMain,
      _SearchArgs(port.sendPort, root, query, showHidden, maxResults),
    );
    final search = FileSearch._(isolate, port);
    port.listen((m) {
      if (m is SearchBatch && !search._closed) {
        onBatch(m);
        if (m.done) search.cancel();
      }
    });
    return search;
  }

  void cancel() {
    if (_closed) return;
    _closed = true;
    _isolate.kill(priority: Isolate.immediate);
    _port.close();
  }
}

void _searchMain(_SearchArgs a) {
  final q = a.query.toLowerCase();
  final stack = <String>[a.root];
  var batch = <FileItem>[];
  var found = 0;
  var dirs = 0;
  final sw = Stopwatch()..start();

  void flush({bool done = false, bool truncated = false}) {
    a.out.send(SearchBatch(
      items: batch,
      done: done,
      truncated: truncated,
      scannedDirs: dirs,
    ));
    batch = <FileItem>[];
    sw.reset();
  }

  while (stack.isNotEmpty) {
    final dir = stack.removeLast();
    final List<FileSystemEntity> children;
    try {
      children = Directory(dir).listSync(followLinks: false);
    } catch (_) {
      continue; // مجلد محمي أو غير قابل للقراءة
    }
    dirs++;
    for (final e in children) {
      final name = e.path.substring(e.path.lastIndexOf('/') + 1);
      if (!a.showHidden && name.startsWith('.')) continue;
      if (e is Link) continue; // نتجنب الحلقات
      final isDir = e is Directory;
      if (isDir) stack.add(e.path);
      if (!name.toLowerCase().contains(q)) continue;
      final FileStat st;
      try {
        st = e.statSync();
      } catch (_) {
        continue;
      }
      batch.add(FileItem(
        path: e.path,
        name: name,
        isDir: isDir,
        size: isDir ? 0 : st.size,
        modified: st.modified,
        kind: isDir ? FileKind.folder : kindForName(name),
      ));
      found++;
      if (found >= a.limit) {
        flush(done: true, truncated: true);
        return;
      }
      if (batch.length >= 40) flush();
    }
    if (sw.elapsedMilliseconds > 300) flush(); // تقدّم دوري حتى بلا نتائج
  }
  flush(done: true);
}
