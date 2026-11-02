import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;

import 'transfer_models.dart';

/// سبب مقروء لخطأ نظام الملفات.
String fsReason(FileSystemException e) {
  switch (e.osError?.errorCode) {
    case 28:
      return 'المساحة ممتلئة';
    case 13:
    case 1:
      return 'لا توجد صلاحية';
    case 2:
      return 'العنصر غير موجود';
    case 30:
      return 'التخزين للقراءة فقط';
    case 36:
      return 'الاسم طويل جدًا';
    case 39:
      return 'المجلد غير فارغ';
  }
  final m = e.osError?.message ?? e.message;
  return m.isEmpty ? 'خطأ غير معروف' : m;
}

/// يتحقق من صلاحية الاسم نفسه. يُرجع نص الخطأ أو null.
String? validateName(String name) {
  if (name.isEmpty) return 'اكتب اسمًا';
  if (name == '.' || name == '..') return 'اسم غير صالح';
  if (name.contains('/') || name.contains('\u0000')) return 'الاسم لا يمكن أن يحتوي على /';
  // رموز ترفضها أنظمة FAT وبطاقات الذاكرة، فنمنعها لسلامة النقل لاحقًا
  if (RegExp(r'[\\:*?"<>|]').hasMatch(name)) return 'الاسم يحتوي على رمز غير مسموح';
  if (utf8.encode(name).length > 255) return 'الاسم طويل جدًا';
  return null;
}

/// يتحقق من الاسم داخل مجلد: لا يوجد عنصر آخر بالاسم نفسه.
/// [oldName] هو الاسم الحالي عند إعادة التسمية (يُسمح بتغيير حالة الأحرف فقط).
String? validateNameIn(String dir, String name, {String? oldName}) {
  final base = validateName(name);
  if (base != null) return base;
  if (oldName != null && name == oldName) return null;
  final sameIgnoringCase = oldName != null && name.toLowerCase() == oldName.toLowerCase();
  if (!sameIgnoringCase &&
      FileSystemEntity.typeSync(p.join(dir, name), followLinks: false) !=
          FileSystemEntityType.notFound) {
    return 'يوجد عنصر بهذا الاسم في المجلد';
  }
  return null;
}

/// يعيد تسمية ملف أو مجلد. يُرجع نص الخطأ أو null عند النجاح.
String? renameEntry(String path, String newName) {
  final oldName = p.basename(path);
  if (newName == oldName) return null;
  final err = validateNameIn(p.dirname(path), newName, oldName: oldName);
  if (err != null) return err;
  final target = p.join(p.dirname(path), newName);
  try {
    if (FileSystemEntity.typeSync(path, followLinks: false) == FileSystemEntityType.directory) {
      Directory(path).renameSync(target);
    } else {
      File(path).renameSync(target);
    }
    return null;
  } on FileSystemException catch (e) {
    return fsReason(e);
  }
}

/// ينشئ مجلدًا جديدًا. يُرجع نص الخطأ أو null عند النجاح.
String? createFolder(String dir, String name) {
  final err = validateNameIn(dir, name);
  if (err != null) return err;
  try {
    Directory(p.join(dir, name)).createSync();
    return null;
  } on FileSystemException catch (e) {
    return fsReason(e);
  }
}

/// يحذف العناصر نهائيًا في خيط منفصل (المجلدات الكبيرة لا تجمّد الواجهة).
/// فشل عنصر لا يوقف الباقي، ويُرجع قائمة الفاشل مع الأسباب.
Future<List<TransferFailure>> deletePaths(List<String> paths) {
  return Isolate.run(() => _deleteSync(paths));
}

List<TransferFailure> _deleteSync(List<String> paths) {
  final failures = <TransferFailure>[];
  for (final path in paths) {
    try {
      final type = FileSystemEntity.typeSync(path, followLinks: false);
      if (type == FileSystemEntityType.notFound) continue;
      if (type == FileSystemEntityType.directory) {
        Directory(path).deleteSync(recursive: true);
      } else {
        File(path).deleteSync(); // يشمل الرابط الرمزي (يحذف الرابط لا هدفه)
      }
    } on FileSystemException catch (e) {
      failures.add(TransferFailure(path, fsReason(e)));
    }
  }
  return failures;
}
