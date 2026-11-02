import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'view_prefs.dart';

/// إعدادات التطبيق المحفوظة. تُستدعى `init()` مرة واحدة في `main()`.
/// (الترتيب وطريقة العرض تحفظها [ViewPrefs] في نفس المخزن.)
class AppSettings extends ChangeNotifier {
  AppSettings._();
  static final AppSettings instance = AppSettings._();

  SharedPreferences? _p;
  bool _showHidden = false;
  bool _deepVerify = false;
  ThemeMode _themeMode = ThemeMode.dark;

  bool get showHidden => _showHidden;

  /// مقارنة كل بايت بعد نسخ كل ملف (أبطأ وأدق).
  bool get deepVerify => _deepVerify;
  ThemeMode get themeMode => _themeMode;

  Future<void> init() async {
    try {
      final p = await SharedPreferences.getInstance();
      _p = p;
      _showHidden = p.getBool('show_hidden') ?? false;
      _deepVerify = p.getBool('deep_verify') ?? false;
      _themeMode = ThemeMode.values.firstWhere(
        (m) => m.name == p.getString('theme_mode'),
        orElse: () => ThemeMode.dark,
      );
      ViewPrefs.instance.attach(p);
    } catch (_) {
      // إن تعذّرت القراءة نستخدم القيم الافتراضية ولا يتوقف التطبيق.
    }
  }

  void setShowHidden(bool v) {
    if (v == _showHidden) return;
    _showHidden = v;
    _p?.setBool('show_hidden', v);
    notifyListeners();
  }

  void setDeepVerify(bool v) {
    if (v == _deepVerify) return;
    _deepVerify = v;
    _p?.setBool('deep_verify', v);
    notifyListeners();
  }

  void setThemeMode(ThemeMode m) {
    if (m == _themeMode) return;
    _themeMode = m;
    _p?.setString('theme_mode', m.name);
    notifyListeners();
  }
}
