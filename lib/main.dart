import 'package:flutter/material.dart';
import 'app_nav.dart';
import 'app_settings.dart';
import 'home_screen.dart';
import 'permission_gate.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppSettings.instance.init();
  runApp(const FileManagerApp());
}

class FileManagerApp extends StatelessWidget {
  const FileManagerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppSettings.instance,
      builder: (context, _) => MaterialApp(
        navigatorKey: navigatorKey,
        title: 'مدير الملفات',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: AppSettings.instance.themeMode,
        // واجهة عربية من اليمين لليسار
        builder: (context, child) => Directionality(
          textDirection: TextDirection.rtl,
          child: child!,
        ),
        home: const PermissionGate(child: HomeScreen()),
      ),
    );
  }
}