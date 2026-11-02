import 'dart:io';
import 'dart:isolate';

enum FileKind { folder, image, video, audio, document, archive, apk, code, other }

class FileItem {
  const FileItem({
    required this.path,
    required this.name,
    required this.isDir,
    required this.size,
    required this.modified,
    required this.kind,
  });

  final String path;
  final String name;
  final bool isDir;
  final int size;
  final DateTime modified;
  final FileKind kind;
}

const Map<String, FileKind> _kindByExt = {
  'jpg': FileKind.image, 'jpeg': FileKind.image, 'png': FileKind.image,
  'gif': FileKind.image, 'webp': FileKind.image, 'bmp': FileKind.image,
  'heic': FileKind.image, 'svg': FileKind.image,
  'mp4': FileKind.video, 'mkv': FileKind.video, 'avi': FileKind.video,
  'mov': FileKind.video, 'webm': FileKind.video, '3gp': FileKind.video,
  'mp3': FileKind.audio, 'wav': FileKind.audio, 'm4a': FileKind.audio,
  'aac': FileKind.audio, 'ogg': FileKind.audio, 'flac': FileKind.audio,
  'pdf': FileKind.document, 'doc': FileKind.document, 'docx': FileKind.document,
  'xls': FileKind.document, 'xlsx': FileKind.document, 'ppt': FileKind.document,
  'pptx': FileKind.document, 'txt': FileKind.document, 'md': FileKind.document,
  'zip': FileKind.archive, 'rar': FileKind.archive, '7z': FileKind.archive,
  'tar': FileKind.archive, 'gz': FileKind.archive,
  'apk': FileKind.apk,
  'dart': FileKind.code, 'js': FileKind.code, 'json': FileKind.code,
  'html': FileKind.code, 'css': FileKind.code, 'xml': FileKind.code,
  'kt': FileKind.code, 'java': FileKind.code, 'py': FileKind.code,
};

FileKind kindForName(String name) {
  final i = name.lastIndexOf('.');
  if (i <= 0 || i == name.length - 1) return FileKind.other;
  return _kindByExt[name.substring(i + 1).toLowerCase()] ?? FileKind.other;
}

// صيغ الصور التي يستطيع Flutter عرضها (svg وheic تُفتح بتطبيق آخر).
const Set<String> _previewImageExt = {'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'};

// الملفات النصية التي نعرضها داخل التطبيق.
const Set<String> _previewTextExt = {
  'txt', 'md', 'json', 'xml', 'html', 'htm', 'css', 'js', 'dart', 'kt', 'java',
  'py', 'log', 'csv', 'tsv', 'yml', 'yaml', 'ini', 'conf', 'properties',
  'gradle', 'sh', 'srt', 'toml',
};

String _extOf(String name) {
  final i = name.lastIndexOf('.');
  return (i > 0 && i < name.length - 1) ? name.substring(i + 1).toLowerCase() : '';
}

bool canPreviewImage(String name) => _previewImageExt.contains(_extOf(name));

bool isTextPreviewable(String name) => _previewTextExt.contains(_extOf(name));

/// يقرأ محتويات مجلد في خيط منفصل حتى لا تتجمد الواجهة مع المجلدات الكبيرة.
/// الترتيب يتم في الواجهة حسب تفضيلات المستخدم (`sortedItems`).
Future<List<FileItem>> listDirectory(String path, {bool showHidden = false}) {
  return Isolate.run(() => _listSync(path, showHidden));
}

List<FileItem> _listSync(String path, bool showHidden) {
  final out = <FileItem>[];
  for (final e in Directory(path).listSync(followLinks: false)) {
    final name = e.path.substring(e.path.lastIndexOf('/') + 1);
    if (name.isEmpty) continue;
    if (!showHidden && name.startsWith('.')) continue;
    final FileStat st;
    try {
      st = e.statSync(); // يتبع الروابط الرمزية
    } catch (_) {
      continue;
    }
    if (st.type == FileSystemEntityType.notFound) continue;
    final isDir = st.type == FileSystemEntityType.directory;
    out.add(FileItem(
      path: e.path,
      name: name,
      isDir: isDir,
      size: isDir ? 0 : st.size,
      modified: st.modified,
      kind: isDir ? FileKind.folder : kindForName(name),
    ));
  }
  return out;
}
