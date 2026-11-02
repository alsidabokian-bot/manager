import 'package:flutter/material.dart';
import 'view_prefs.dart';

/// ورقة سفلية لاختيار طريقة العرض والترتيب.
Future<void> showViewOptions(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _ViewOptionsSheet(),
  );
}

class _ViewOptionsSheet extends StatelessWidget {
  const _ViewOptionsSheet();

  static const _fieldNames = {
    SortField.name: 'الاسم',
    SortField.size: 'الحجم',
    SortField.date: 'التاريخ',
    SortField.type: 'النوع',
  };

  @override
  Widget build(BuildContext context) {
    final prefs = ViewPrefs.instance;
    return SafeArea(
      child: ListenableBuilder(
        listenable: prefs,
        builder: (context, _) => SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const _Title('طريقة العرض'),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<ViewMode>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(
                      value: ViewMode.list,
                      label: Text('قائمة'),
                      icon: Icon(Icons.view_list_rounded),
                    ),
                    ButtonSegment(
                      value: ViewMode.grid,
                      label: Text('شبكة'),
                      icon: Icon(Icons.grid_view_rounded),
                    ),
                  ],
                  selected: {prefs.mode},
                  onSelectionChanged: (s) => prefs.setMode(s.first),
                ),
              ),
              const SizedBox(height: 20),
              const _Title('الترتيب حسب'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final f in SortField.values)
                    ChoiceChip(
                      label: Text(_fieldNames[f]!),
                      selected: prefs.sortField == f,
                      onSelected: (_) => prefs.setSortField(f),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<bool>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(
                      value: true,
                      label: Text('تصاعدي'),
                      icon: Icon(Icons.arrow_upward_rounded),
                    ),
                    ButtonSegment(
                      value: false,
                      label: Text('تنازلي'),
                      icon: Icon(Icons.arrow_downward_rounded),
                    ),
                  ],
                  selected: {prefs.ascending},
                  onSelectionChanged: (s) => prefs.setAscending(s.first),
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('المجلدات أولًا'),
                value: prefs.foldersFirst,
                onChanged: prefs.setFoldersFirst,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Title extends StatelessWidget {
  const _Title(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(text, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
    );
  }
}
