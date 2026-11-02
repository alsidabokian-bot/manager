import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'file_ops.dart';

/// أقصى حجم يُقرأ من ملف نصي للمعاينة (الباقي يُفتح بتطبيق آخر).
const int maxTextPreviewBytes = 512 * 1024;

class TextPreview {
  const TextPreview({this.text = '', this.truncated = false, this.binary = false, this.error});
  final String text;
  final bool truncated;
  final bool binary; // الملف ليس نصًا
  final String? error;
}

/// يقرأ بداية ملف نصي في خيط منفصل.
Future<TextPreview> readTextPreview(String path) {
  return Isolate.run(() => _readSync(path));
}

TextPreview _readSync(String path) {
  try {
    final raf = File(path).openSync();
    try {
      final len = raf.lengthSync();
      final n = len < maxTextPreviewBytes ? len : maxTextPreviewBytes;
      final bytes = raf.readSync(n);
      // الملف الثنائي يحتوي بايتات صفرية في أول 4 ك.ب
      final probe = bytes.length < 4096 ? bytes.length : 4096;
      for (var i = 0; i < probe; i++) {
        if (bytes[i] == 0) return const TextPreview(binary: true);
      }
      var text = utf8.decode(bytes, allowMalformed: true);
      final truncated = len > n;
      // القص قد يقطع حرفًا متعدد البايتات في النهاية
      if (truncated && text.endsWith('\uFFFD')) text = text.substring(0, text.length - 1);
      return TextPreview(text: text.replaceAll('\r\n', '\n'), truncated: truncated);
    } finally {
      raf.closeSync();
    }
  } on FileSystemException catch (e) {
    return TextPreview(error: fsReason(e));
  }
}
