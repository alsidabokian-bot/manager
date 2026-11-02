import 'package:flutter/material.dart';
import 'app_nav.dart';
import 'storage_service.dart';
import 'transfer_models.dart';

BuildContext? get _overlayContext => navigatorKey.currentState?.overlay?.context;

/// يسأل المستخدم مرة واحدة عن كل الملفات المتعارضة. null = إلغاء العملية.
Future<ConflictPolicy?> askConflictPolicy(int count) async {
  final ctx = _overlayContext;
  if (ctx == null) return ConflictPolicy.keepBoth; // الخيار الذي لا يتلف شيئًا
  return showDialog<ConflictPolicy>(
    context: ctx,
    barrierDismissible: false,
    builder: (c) => AlertDialog(
      title: Text('يوجد $count ملف بنفس الاسم'),
      content: const Text('ماذا تريد أن تفعل بالملفات الموجودة مسبقًا في الوجهة؟'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c),
          child: const Text('إلغاء العملية'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(c, ConflictPolicy.skip),
          child: const Text('تخطٍّ'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(c, ConflictPolicy.keepBoth),
          child: const Text('إبقاء الاثنين'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(c, ConflictPolicy.replace),
          child: const Text('استبدال'),
        ),
      ],
    ),
  );
}

/// تنبيه مرة لكل جلسة: بعض الأجهزة توقف التطبيق في الخلفية لتوفير البطارية.
Future<void> showBatteryHint() async {
  final ctx = _overlayContext;
  if (ctx == null) return;
  final go = await showDialog<bool>(
    context: ctx,
    builder: (c) => AlertDialog(
      title: const Text('لضمان عدم توقف النسخ'),
      content: const Text(
        'بعض الهواتف توقف التطبيقات في الخلفية لتوفير البطارية، فقد يتوقف نسخ '
        'الملفات الكبيرة إذا خرجت من التطبيق. استثنِ «مدير الملفات» من تحسين البطارية.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('لاحقًا')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('فتح الإعداد')),
      ],
    ),
  );
  if (go == true) await StorageService.requestIgnoreBatteryOptimizations();
}
