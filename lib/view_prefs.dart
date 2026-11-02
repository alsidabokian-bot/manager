import 'dart:collection';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'file_models.dart';

enum SortField { name, size, date, type }

enum ViewMode { list, grid }

/// تفضيلات الترتيب وطريقة العرض (تسري على كل المجلدات).
class ViewPrefs extends ChangeNotifier {
  ViewPrefs._();
  static final ViewPrefs instance = ViewPrefs._();

  SharedPreferences? _store;
  SortField _sortField = SortField.name;
  bool _ascending = true;
  bool _foldersFirst = true;
  ViewMode _mode = ViewMode.list;

  SortField get sortField => _sortField;
  bool get ascending => _ascending;
  bool get foldersFirst => _foldersFirst;
  ViewMode get mode => _mode;

  /// يقرأ التفضيلات المحفوظة ويبدأ حفظ أي تغيير (يُستدعى مرة عند الإقلاع).
  void attach(SharedPreferences p) {
    _store = p;
    _sortField = SortField.values.firstWhere(
      (e) => e.name == p.getString('sort_field'),
      orElse: () => SortField.name,
    );
    _ascending = p.getBool('sort_ascending') ?? true;
    _foldersFirst = p.getBool('folders_first') ?? true;
    _mode = ViewMode.values.firstWhere(
      (e) => e.name == p.getString('view_mode'),
      orElse: () => ViewMode.list,
    );
  }

  void setSortField(SortField v) {
    if (v == _sortField) return;
    _sortField = v;
    _store?.setString('sort_field', v.name);
    notifyListeners();
  }

  void setAscending(bool v) {
    if (v == _ascending) return;
    _ascending = v;
    _store?.setBool('sort_ascending', v);
    notifyListeners();
  }

  void setFoldersFirst(bool v) {
    if (v == _foldersFirst) return;
    _foldersFirst = v;
    _store?.setBool('folders_first', v);
    notifyListeners();
  }

  void setMode(ViewMode v) {
    if (v == _mode) return;
    _mode = v;
    _store?.setString('view_mode', v.name);
    notifyListeners();
  }
}

/// يرتّب العناصر حسب [prefs]. الأسماء بترتيب «طبيعي»: file2 قبل file10.
List<FileItem> sortedItems(Iterable<FileItem> items, ViewPrefs prefs) {
  final list = items.toList();
  // نحسب مفتاح الاسم مرة واحدة لكل عنصر بدل كل مقارنة
  final keys = HashMap<FileItem, List<String>>.identity();
  List<String> keyOf(FileItem f) =>
      keys.putIfAbsent(f, () => _chunks(f.name.toLowerCase()));

  final field = prefs.sortField;
  final asc = prefs.ascending;
  final foldersFirst = prefs.foldersFirst;

  int cmp(FileItem a, FileItem b) {
    if (foldersFirst && a.isDir != b.isDir) return a.isDir ? -1 : 1;
    var r = 0;
    switch (field) {
      case SortField.name:
        r = _natural(keyOf(a), keyOf(b));
      case SortField.size:
        r = a.size.compareTo(b.size);
      case SortField.date:
        r = a.modified.compareTo(b.modified);
      case SortField.type:
        r = _ext(a).compareTo(_ext(b));
    }
    if (r == 0) r = _natural(keyOf(a), keyOf(b));
    return asc ? r : -r;
  }

  list.sort(cmp);
  return list;
}

final RegExp _chunkRe = RegExp(r'\d+|\D+');

List<String> _chunks(String s) => _chunkRe.allMatches(s).map((m) => m[0]!).toList();

int _natural(List<String> a, List<String> b) {
  final n = a.length < b.length ? a.length : b.length;
  for (var i = 0; i < n; i++) {
    final x = a[i];
    final y = b[i];
    final dx = int.tryParse(x);
    final dy = int.tryParse(y);
    final r = (dx != null && dy != null) ? dx.compareTo(dy) : x.compareTo(y);
    if (r != 0) return r;
  }
  return a.length.compareTo(b.length);
}

String _ext(FileItem f) {
  if (f.isDir) return '';
  final i = f.name.lastIndexOf('.');
  return i > 0 ? f.name.substring(i + 1).toLowerCase() : '';
}
