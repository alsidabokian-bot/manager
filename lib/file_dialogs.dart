import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'file_models.dart';
import 'transfer_models.dart';

/// حوار إدخال اسم (مجلد جديد / إعادة تسمية) مع تحقق فوري.
/// [validator] يُرجع نص الخطأ أو null. النتيجة: الاسم أو null عند الإلغاء.
Future<String?> askName(
  BuildContext context, {
  required String title,
  required String okLabel,
  required String? Function(String name) validator,
  String initial = '',
  bool selectBaseOnly = false,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _NameDialog(
      title: title,
      okLabel: okLabel,
      validator: validator,
      initial: initial,
      selectBaseOnly: selectBaseOnly,
    ),
  );
}

class _NameDialog extends StatefulWidget {
  const _NameDialog({
    required this.title,
    required this.okLabel,
    required this.validator,
    required this.initial,
    required this.selectBaseOnly,
  });

  final String title;
  final String okLabel;
  final String? Function(String) validator;
  final String initial;
  final bool selectBaseOnly;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final TextEditingController _c;
  String? _error;

  @override
  void initState() {
    super.initState();
    _c = TextEditingController(text: widget.initial);
    if (widget.initial.isNotEmpty) {
      // عند إعادة تسمية ملف نحدد الاسم دون الامتداد
      final dot = widget.initial.lastIndexOf('.');
      final end = (widget.selectBaseOnly && dot > 0) ? dot : widget.initial.length;
      _c.selection = TextSelection(baseOffset: 0, extentOffset: end);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _c.text.trim();
    final err = widget.validator(name);
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    Navigator.pop(context, name);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _c,
        autofocus: true,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _submit(),
        onChanged: (v) {
          final t = v.trim();
          setState(() => _error = t.isEmpty ? null : widget.validator(t));
        },
        decoration: InputDecoration(errorText: _error, hintText: 'الاسم'),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
        FilledButton(onPressed: _submit, child: Text(widget.okLabel)),
      ],
    );
  }
}

/// تأكيد الحذف النهائي.
Future<bool> confirmDelete(BuildContext context, List<FileItem> items) async {
  final dirs = items.where((i) => i.isDir).length;
  final files = items.length - dirs;
  final String what;
  if (items.length == 1) {
    what = '«${items.first.name}»';
  } else {
    final parts = <String>[
      if (dirs > 0) '$dirs مجلد',
      if (files > 0) '$files ملف',
    ];
    what = '${items.length} عناصر (${parts.join(' و')})';
  }
  final error = Theme.of(context).colorScheme.error;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('حذف نهائي؟'),
      content: Text(
        'سيُحذف $what نهائيًا${dirs > 0 ? ' مع كل محتويات المجلدات' : ''}. '
        'لا يمكن التراجع عن هذا الإجراء.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: error),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('حذف'),
        ),
      ],
    ),
  );
  return ok ?? false;
}

/// يعرض حوار انتظار غير قابل للإغلاق طوال تنفيذ [task].
Future<T> runWithProgress<T>(
  BuildContext context,
  String message,
  Future<T> Function() task,
) async {
  final nav = Navigator.of(context);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(
          children: [
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            const SizedBox(width: 18),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    ),
  );
  try {
    return await task();
  } finally {
    nav.pop();
  }
}

/// يعرض أسباب فشل عدة عناصر.
Future<void> showFailures(
  BuildContext context,
  String title,
  List<TransferFailure> failures,
) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final f in failures.take(15))
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(p.basename(f.path), maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(f.reason),
              ),
            if (failures.length > 15)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text('و${failures.length - 15} عنصرًا آخر'),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إغلاق')),
      ],
    ),
  );
}
