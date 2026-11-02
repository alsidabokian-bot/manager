import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'transfer_models.dart';

/// محرك النسخ والنقل. يعمل بالكامل في خيط (Isolate) منفصل عن الواجهة.
///
/// المراحل:
///  1. (للنقل) محاولة إعادة التسمية الفورية، وهي ذرية ولا تنسخ بايتًا.
///  2. فحص الملفات وحساب الحجم الكلي والتعارضات، ثم ينتظر قرار الواجهة.
///  3. التجهيز: إنشاء مجلدات الوجهة وملفاتها الفارغة (`.part`) قبل نقل أي بايت.
///  4. النسخ على دفعات داخل ملف `.part`، ثم التحقق من الحجم، ثم إعادة التسمية.
///  5. (للنقل) حذف الأصل بعد اكتمال النسخة الجديدة والتحقق منها فقط.

class _Cancelled implements Exception {
  const _Cancelled();
}

/// إيقاف العملية كلها (مثل امتلاء المساحة) مع إبقاء الأجزاء المؤقتة للاستئناف.
class _Abort implements Exception {
  const _Abort(this.reason);
  final String reason;
}

class _FileOp {
  _FileOp(this.src, this.dst, this.size, this.modifiedMs, {this.conflict = false});

  final String src;
  String dst;
  int size;
  final int modifiedMs;
  final bool conflict;
  bool skip = false;
  bool failed = false;
  bool done = false;

  String get part => '$dst.part';
  String get name => p.basename(src);
}

/// نقطة دخول الخيط المنفصل.
Future<void> transferWorkerMain(WorkerInit init) async {
  final inbox = ReceivePort();
  init.toManager.send(inbox.sendPort);
  try {
    await _Worker(init.request, init.toManager, inbox).run();
  } catch (e) {
    init.toManager.send(FatalError('$e'));
  }
  inbox.close();
}

class _Worker {
  _Worker(this.req, this.out, this.inbox);

  final TransferRequest req;
  final SendPort out;
  final ReceivePort inbox;

  static const int _maxChunk = 4 * 1024 * 1024;

  final Completer<ConflictPolicy?> _go = Completer<ConflictPolicy?>();
  final Stopwatch _clock = Stopwatch()..start();
  final Stopwatch _since = Stopwatch()..start();
  final Uint8List _buf = Uint8List(_maxChunk);

  bool _paused = false;
  bool _cancelled = false;

  final List<_FileOp> _ops = [];
  final List<String> _dirs = []; // مجلدات الوجهة، الأب قبل الابن
  final List<String> _srcDirs = [];
  final List<String> _createdDirs = [];
  final Set<String> _used = {};
  final List<TransferFailure> _failures = [];

  int _copied = 0;
  int _skipped = 0;
  int _bytes = 0;
  int _session = 0;
  int _existingPart = 0;
  int _tick = 0;
  String? _abortReason;

  // ---------- التشغيل ----------

  Future<void> run() async {
    inbox.listen(_onCommand);
    try {
      if (!Directory(req.destDir).existsSync()) {
        throw const _Abort('مجلد الوجهة غير موجود');
      }
      final toCopy = _fastPath();
      await _scan(toCopy);
      if (_ops.isEmpty && _dirs.isEmpty) {
        _finish(false);
        return;
      }
      out.send(ScanDone(
        totalBytes: _ops.fold<int>(0, (a, o) => a + o.size),
        fileCount: _ops.length,
        conflictCount: _ops.where((o) => o.conflict).length,
        existingPartBytes: _existingPart,
      ));
      final policy = await _go.future;
      if (policy == null || _cancelled) throw const _Cancelled();
      _applyPolicy(policy);
      await _prepare();
      await _copyAll();
      if (req.move) _removeEmptySourceDirs();
      _finish(false);
    } on _Cancelled {
      _cleanupAfterCancel();
      _finish(true);
    } on _Abort catch (a) {
      _abortReason = a.reason;
      _finish(false);
    }
  }

  void _onCommand(dynamic m) {
    if (m == 'pause') {
      _paused = true;
    } else if (m == 'resume') {
      _paused = false;
    } else if (m == 'cancel') {
      _cancelled = true;
      if (!_go.isCompleted) _go.complete(null);
    } else if (m is GoCommand && !_go.isCompleted) {
      _go.complete(m.policy);
    }
  }

  void _check() {
    if (_cancelled) throw const _Cancelled();
  }

  Future<void> _gate() async {
    while (_paused && !_cancelled) {
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    _check();
  }

  // ---------- 1) المسار السريع والتحقق الأولي ----------

  /// يتحقق من كل مصدر، وفي النقل يجرّب إعادة التسمية الفورية.
  /// يُرجع المصادر التي تحتاج نسخًا فعليًا.
  List<String> _fastPath() {
    final list = <String>[];
    for (final src in req.sources) {
      final type = FileSystemEntity.typeSync(src, followLinks: false);
      if (type == FileSystemEntityType.notFound) {
        _failures.add(TransferFailure(src, 'المصدر غير موجود'));
        continue;
      }
      if (type == FileSystemEntityType.directory &&
          (p.isWithin(src, req.destDir) || p.equals(src, req.destDir))) {
        _failures.add(TransferFailure(src, 'لا يمكن وضع مجلد داخل نفسه'));
        continue;
      }
      if (!req.move) {
        list.add(src);
        continue;
      }
      if (p.equals(p.dirname(src), req.destDir)) {
        _skipped++; // النقل إلى نفس المجلد لا يغيّر شيئًا
        continue;
      }
      final dst = p.join(req.destDir, p.basename(src));
      if (FileSystemEntity.typeSync(dst, followLinks: false) !=
          FileSystemEntityType.notFound) {
        list.add(src); // تعارض: يُعالج بقرار المستخدم
        continue;
      }
      try {
        if (type == FileSystemEntityType.directory) {
          Directory(src).renameSync(dst);
        } else {
          File(src).renameSync(dst);
        }
        _copied++;
      } on FileSystemException {
        list.add(src); // قرص مختلف أو سبب آخر: ننسخ ثم نحذف الأصل
      }
    }
    return list;
  }

  // ---------- 2) الفحص ----------

  Future<void> _scan(List<String> sources) async {
    for (final src in sources) {
      _check();
      final type = FileSystemEntity.typeSync(src, followLinks: false);
      final name = p.basename(src);
      var dst = p.join(req.destDir, name);
      if (p.equals(dst, src)) dst = _unique(req.destDir, name); // نسخ داخل نفس المجلد
      if (type == FileSystemEntityType.directory) {
        if (FileSystemEntity.typeSync(dst, followLinks: false) ==
            FileSystemEntityType.file) {
          _failures.add(TransferFailure(src, 'يوجد ملف بنفس اسم هذا المجلد في الوجهة'));
          continue;
        }
        await _walkDir(src, dst);
      } else if (type == FileSystemEntityType.file) {
        _addFile(src, dst);
      } else if (type == FileSystemEntityType.link) {
        _skipped++;
      }
    }
  }

  Future<void> _walkDir(String src, String dst) async {
    _dirs.add(dst);
    _srcDirs.add(src);
    final List<FileSystemEntity> children;
    try {
      children = Directory(src).listSync(followLinks: false);
    } on FileSystemException catch (e) {
      _failures.add(TransferFailure(src, _reason(e)));
      return;
    }
    for (final c in children) {
      // نتيح للخيط معالجة أمر الإلغاء أثناء فحص المجلدات الضخمة
      if (++_tick % 300 == 0) {
        await Future<void>.delayed(Duration.zero);
        _check();
      }
      final cdst = p.join(dst, p.basename(c.path));
      if (c is Link) {
        _skipped++;
      } else if (c is Directory) {
        if (FileSystemEntity.typeSync(cdst, followLinks: false) ==
            FileSystemEntityType.file) {
          _failures.add(TransferFailure(c.path, 'يوجد ملف بنفس اسم هذا المجلد في الوجهة'));
        } else {
          await _walkDir(c.path, cdst);
        }
      } else {
        _addFile(c.path, cdst);
      }
    }
  }

  void _addFile(String src, String dst) {
    final st = FileStat.statSync(src);
    if (st.type == FileSystemEntityType.notFound) {
      _failures.add(TransferFailure(src, 'الملف غير موجود'));
      return;
    }
    final existing = FileSystemEntity.typeSync(dst, followLinks: false);
    if (existing == FileSystemEntityType.directory) {
      _failures.add(TransferFailure(src, 'يوجد مجلد بنفس اسم هذا الملف في الوجهة'));
      return;
    }
    final part = File('$dst.part');
    if (part.existsSync()) {
      final l = part.lengthSync();
      if (l < st.size) _existingPart += l;
    }
    _ops.add(_FileOp(
      src,
      dst,
      st.size,
      st.modified.millisecondsSinceEpoch,
      conflict: existing != FileSystemEntityType.notFound,
    ));
  }

  // ---------- أسماء بلا تعارض ----------

  /// اسم غير مستخدم: `name (1).ext` ثم `(2)` وهكذا.
  /// لا نعدّ ملف `.part` موجودًا حتى يجد الاستئناف جزأه القديم بالاسم نفسه.
  String _unique(String dir, String name) {
    final dot = name.lastIndexOf('.');
    final base = dot > 0 ? name.substring(0, dot) : name;
    final ext = dot > 0 ? name.substring(dot) : '';
    var i = 1;
    String cand;
    do {
      cand = p.join(dir, '$base ($i)$ext');
      i++;
    } while (_used.contains(cand) ||
        FileSystemEntity.typeSync(cand, followLinks: false) !=
            FileSystemEntityType.notFound);
    _used.add(cand);
    return cand;
  }

  void _applyPolicy(ConflictPolicy policy) {
    for (final op in _ops) {
      if (!op.conflict) continue;
      switch (policy) {
        case ConflictPolicy.skip:
          op.skip = true;
          _skipped++;
        case ConflictPolicy.replace:
          break;
        case ConflictPolicy.keepBoth:
          op.dst = _unique(p.dirname(op.dst), p.basename(op.dst));
      }
    }
  }

  // ---------- 3) التجهيز: إنشاء المجلدات والملفات الفارغة ----------

  Future<void> _prepare() async {
    final active = _ops.where((o) => !o.skip).toList();
    out.send(PrepareProgress(0, active.length));

    for (final d in _dirs) {
      if (Directory(d).existsSync()) continue;
      try {
        Directory(d).createSync(recursive: true);
        _createdDirs.add(d);
      } on FileSystemException catch (e) {
        throw _Abort('تعذّر إنشاء المجلد ${p.basename(d)}: ${_reason(e)}');
      }
    }

    var n = 0;
    for (final op in active) {
      try {
        final f = File(op.part);
        if (!f.existsSync()) f.createSync(); // لا نمسح جزءًا قديمًا قابلًا للاستئناف
      } on FileSystemException catch (e) {
        if (_noSpace(e)) throw const _Abort('المساحة ممتلئة');
        op.failed = true;
        _failures.add(TransferFailure(op.src, 'تعذّر تجهيز الملف: ${_reason(e)}'));
      }
      if (++n % 50 == 0 || n == active.length) {
        out.send(PrepareProgress(n, active.length));
        await Future<void>.delayed(Duration.zero);
        _check();
      }
    }
  }

  // ---------- 4) النسخ ----------

  Future<void> _copyAll() async {
    final todo = _ops.where((o) => !o.skip && !o.failed).toList();
    var doneBefore = 0;
    for (var i = 0; i < todo.length; i++) {
      final op = todo[i];
      _check();
      _report(doneBefore, op.name, i, todo.length, force: true);
      try {
        await _copyFile(op, i, todo.length, doneBefore);
        op.done = true;
        _copied++;
        _bytes += op.size;
        if (req.move) _deleteSource(op);
      } on _Cancelled {
        rethrow;
      } on _Abort {
        rethrow;
      } on FileSystemException catch (e) {
        if (_noSpace(e)) throw const _Abort('المساحة ممتلئة أثناء النسخ');
        _failures.add(TransferFailure(op.src, _reason(e)));
      } catch (e) {
        _failures.add(TransferFailure(op.src, '$e'));
      }
      doneBefore += op.size;
    }
  }

  Future<void> _copyFile(_FileOp op, int index, int count, int doneBefore) async {
    final src = File(op.src);
    final before = await src.stat();
    if (before.type == FileSystemEntityType.notFound) {
      throw FileSystemException('الملف المصدر لم يعد موجودًا', op.src);
    }
    op.size = before.size; // قد يتغير الحجم بين الفحص والنسخ
    final part = File(op.part);

    // الاستئناف: نكمل جزءًا قديمًا فقط إذا طابق بدايته ونهايته الأصل.
    var offset = 0;
    if (await part.exists()) {
      final len = await part.length();
      if (len > 0 && len <= op.size && await _edgesMatch(src, part, len)) {
        offset = len;
      }
    }

    if (offset < op.size) {
      final chunk = op.size > 256 * 1024 * 1024 ? _maxChunk : _maxChunk ~/ 2;
      final inp = await src.open();
      final outFile = await part.open(mode: offset > 0 ? FileMode.append : FileMode.write);
      try {
        if (offset > 0) await inp.setPosition(offset);
        var pos = offset;
        while (pos < op.size) {
          await _gate();
          final want = math.min(chunk, op.size - pos);
          final n = await inp.readInto(_buf, 0, want);
          if (n <= 0) break;
          await outFile.writeFrom(_buf, 0, n);
          pos += n;
          _session += n;
          _report(doneBefore + pos, op.name, index, count);
        }
        await outFile.flush();
      } finally {
        await inp.close();
        await outFile.close();
      }
    }

    // التحقق قبل اعتماد الملف
    final written = await part.length();
    if (written != op.size) {
      throw FileSystemException('حجم الملف المنسوخ لا يطابق الأصل', op.dst);
    }
    final after = await src.stat();
    if (after.size != before.size || after.modified != before.modified) {
      throw FileSystemException('تغيّر الملف الأصلي أثناء النسخ', op.src);
    }
    if (req.deepVerify) await _compareFull(src, part, op.size);

    await part.rename(op.dst); // يستبدل الملف الموجود ذريًا عند سياسة الاستبدال
    try {
      await File(op.dst).setLastModified(before.modified);
    } catch (_) {}
  }

  void _report(int done, String name, int idx, int count, {bool force = false}) {
    if (!force && _since.elapsedMilliseconds < 250) return;
    _since.reset();
    out.send(CopyProgress(
      doneBytes: done,
      sessionBytes: _session,
      fileIndex: idx,
      fileCount: count,
      currentName: name,
    ));
  }

  // ---------- التحقق ----------

  /// يقارن أول 64 ك.ب وآخر 1 م.ب من الجزء القديم بالأصل قبل استئنافه.
  Future<bool> _edgesMatch(File a, File b, int len) async {
    final head = math.min(len, 64 * 1024);
    final tail = math.min(len, 1024 * 1024);
    return await _rangeEqual(a, b, 0, head) &&
        await _rangeEqual(a, b, len - tail, tail);
  }

  Future<bool> _rangeEqual(File a, File b, int start, int n) async {
    final ra = await a.open();
    final rb = await b.open();
    try {
      await ra.setPosition(start);
      await rb.setPosition(start);
      final x = await ra.read(n);
      final y = await rb.read(n);
      if (x.length != y.length) return false;
      for (var i = 0; i < x.length; i++) {
        if (x[i] != y[i]) return false;
      }
      return true;
    } finally {
      await ra.close();
      await rb.close();
    }
  }

  /// مقارنة كاملة بايتًا ببايت (للتحقق العميق).
  Future<void> _compareFull(File a, File b, int size) async {
    final ra = await a.open();
    final rb = await b.open();
    try {
      var pos = 0;
      while (pos < size) {
        await _gate();
        final n = math.min(1024 * 1024, size - pos);
        final x = await ra.read(n);
        final y = await rb.read(n);
        if (x.length != y.length) throw FileSystemException('فشل التحقق العميق', b.path);
        for (var i = 0; i < x.length; i++) {
          if (x[i] != y[i]) throw FileSystemException('فشل التحقق العميق', b.path);
        }
        pos += n;
      }
    } finally {
      await ra.close();
      await rb.close();
    }
  }

  // ---------- 5) النقل: حذف الأصل بعد النجاح فقط ----------

  void _deleteSource(_FileOp op) {
    try {
      File(op.src).deleteSync();
    } on FileSystemException catch (e) {
      _failures.add(TransferFailure(op.src, 'نُسخ الملف لكن تعذّر حذف الأصل: ${_reason(e)}'));
    }
  }

  /// يحذف مجلدات المصدر الفارغة فقط، فأي مجلد فيه ملف متخطّى أو فاشل يبقى.
  void _removeEmptySourceDirs() {
    final dirs = [..._srcDirs]..sort((a, b) => b.length.compareTo(a.length));
    for (final d in dirs) {
      try {
        Directory(d).deleteSync();
      } catch (_) {}
    }
  }

  // ---------- الإلغاء والإنهاء ----------

  void _cleanupAfterCancel() {
    for (final op in _ops) {
      if (op.done) continue;
      try {
        final f = File(op.part);
        if (f.existsSync()) f.deleteSync();
      } catch (_) {}
    }
    final dirs = [..._createdDirs]..sort((a, b) => b.length.compareTo(a.length));
    for (final d in dirs) {
      try {
        Directory(d).deleteSync(); // غير تكراري: لا يحذف إلا الفارغ
      } catch (_) {}
    }
  }

  void _finish(bool cancelled) {
    out.send(Finished(
      TransferReport(
        copied: _copied,
        skipped: _skipped,
        failures: List.of(_failures),
        bytes: _bytes,
        elapsedMs: _clock.elapsedMilliseconds,
        abortReason: _abortReason,
      ),
      cancelled,
    ));
  }

  // ---------- الأخطاء ----------

  bool _noSpace(FileSystemException e) => e.osError?.errorCode == 28;

  String _reason(FileSystemException e) {
    switch (e.osError?.errorCode) {
      case 28:
        return 'المساحة ممتلئة';
      case 13:
      case 1:
        return 'لا توجد صلاحية';
      case 2:
        return 'الملف غير موجود';
      case 30:
        return 'التخزين للقراءة فقط';
      case 36:
        return 'اسم الملف طويل جدًا';
    }
    final m = e.osError?.message ?? e.message;
    return m.isEmpty ? 'خطأ غير معروف' : m;
  }
}
