import 'package:flutter/material.dart';
import 'file_models.dart';
import 'image_viewer.dart';
import 'storage_service.dart';
import 'text_viewer.dart';

/// يفتح العنصر بالطريقة المناسبة: معاينة داخلية للصور والنصوص،
/// وتطبيق آخر لبقية الأنواع (فيديو، صوت، PDF، APK وغيرها).
Future<void> openItem(BuildContext context, FileItem f, List<FileItem> siblings) async {
  final nav = Navigator.of(context);
  if (canPreviewImage(f.name)) {
    final images = siblings.where((x) => !x.isDir && canPreviewImage(x.name)).toList();
    final i = images.indexWhere((x) => x.path == f.path);
    await nav.push(MaterialPageRoute<void>(
      builder: (_) => ImageViewerScreen(images: images, initialIndex: i < 0 ? 0 : i),
    ));
    return;
  }
  if (isTextPreviewable(f.name)) {
    await nav.push(MaterialPageRoute<void>(builder: (_) => TextViewerScreen(item: f)));
    return;
  }
  if (context.mounted) await openExternally(context, f.path);
}

/// يفتح الملف بتطبيق آخر ويعرض سبب الفشل إن لم يوجد تطبيق مناسب.
Future<void> openExternally(BuildContext context, String path) async {
  final err = await StorageService.openFile(path);
  if (err != null && context.mounted) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(err)));
  }
}

/// يشارك ملفات ويعرض سبب الفشل إن حدث.
Future<void> shareFilePaths(BuildContext context, List<String> paths) async {
  final err = await StorageService.shareFiles(paths);
  if (err != null && context.mounted) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(err)));
  }
}
