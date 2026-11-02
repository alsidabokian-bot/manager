import 'package:flutter/foundation.dart';

enum ClipMode { copy, move }

/// الملفات التي اختارها المستخدم للنسخ أو النقل، بانتظار «لصق» في مجلد الوجهة.
class FileClipboard extends ChangeNotifier {
  FileClipboard._();
  static final FileClipboard instance = FileClipboard._();

  List<String> _paths = const [];
  ClipMode _mode = ClipMode.copy;

  List<String> get paths => _paths;
  ClipMode get mode => _mode;
  bool get isEmpty => _paths.isEmpty;

  void set(List<String> paths, ClipMode mode) {
    _paths = List.unmodifiable(paths);
    _mode = mode;
    notifyListeners();
  }

  void clear() {
    if (_paths.isEmpty) return;
    _paths = const [];
    notifyListeners();
  }
}
