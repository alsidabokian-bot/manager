import 'package:flutter/material.dart';

import 'app_settings.dart';
import 'storage_service.dart';
import 'theme.dart';
import 'view_options.dart';

/// شاشة الإعدادات: المظهر والعرض والنسخ والأذونات.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with WidgetsBindingObserver {
  bool? _hasAccess;
  bool? _batteryOk;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshStatus();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// نعيد فحص الأذونات عند العودة من إعدادات النظام.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshStatus();
  }

  Future<void> _refreshStatus() async {
    final access = await StorageService.hasAccess();
    final battery = await StorageService.isIgnoringBatteryOptimizations();
    if (!mounted) return;
    setState(() {
      _hasAccess = access;
      _batteryOk = battery;
    });
  }

  @override
  Widget build(BuildContext context) {
    final settings = AppSettings.instance;
    return Scaffold(
      appBar: AppBar(title: const Text('الإعدادات')),
      body: ListenableBuilder(
        listenable: settings,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            const _SectionTitle('المظهر'),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<ThemeMode>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(
                        value: ThemeMode.system,
                        label: Text('تلقائي'),
                        icon: Icon(Icons.brightness_auto_rounded),
                      ),
                      ButtonSegment(
                        value: ThemeMode.light,
                        label: Text('فاتح'),
                        icon: Icon(Icons.light_mode_rounded),
                      ),
                      ButtonSegment(
                        value: ThemeMode.dark,
                        label: Text('داكن'),
                        icon: Icon(Icons.dark_mode_rounded),
                      ),
                    ],
                    selected: {settings.themeMode},
                    onSelectionChanged: (s) => settings.setThemeMode(s.first),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            const _SectionTitle('العرض'),
            Card(
              child: Column(
                children: [
                  SwitchListTile(
                    secondary: const _TileIcon(Icons.visibility_rounded),
                    title: const Text('إظهار الملفات المخفية'),
                    subtitle: const Text('الملفات التي يبدأ اسمها بنقطة'),
                    value: settings.showHidden,
                    onChanged: settings.setShowHidden,
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const _TileIcon(Icons.tune_rounded),
                    title: const Text('العرض والترتيب'),
                    subtitle: const Text('قائمة أو شبكة، وطريقة الترتيب (يُحفظ تلقائيًا)'),
                    onTap: () => showViewOptions(context),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            const _SectionTitle('النسخ والنقل'),
            Card(
              child: Column(
                children: [
                  SwitchListTile(
                    secondary: const _TileIcon(Icons.verified_rounded),
                    title: const Text('التحقق العميق بعد النسخ'),
                    subtitle: const Text(
                      'يقارن كل بايت من الملف المنسوخ بالأصل. أدق لكنه يضاعف زمن النسخ تقريبًا. '
                      'التحقق من الحجم يتم دائمًا.',
                    ),
                    value: settings.deepVerify,
                    onChanged: settings.setDeepVerify,
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const _TileIcon(Icons.battery_saver_rounded),
                    title: const Text('تحسين البطارية'),
                    subtitle: Text(
                      _batteryOk == null
                          ? 'جارٍ الفحص…'
                          : _batteryOk!
                              ? 'التطبيق مستثنى، فلن يوقفه النظام أثناء النسخ'
                              : 'غير مستثنى: قد يوقف بعض الهواتف النسخ في الخلفية',
                    ),
                    trailing: (_batteryOk ?? true)
                        ? const Icon(Icons.check_circle_rounded, color: Color(0xFF2EC4A6))
                        : const Icon(Icons.chevron_left_rounded),
                    onTap: (_batteryOk ?? true)
                        ? null
                        : StorageService.requestIgnoreBatteryOptimizations,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            const _SectionTitle('الأذونات'),
            Card(
              child: ListTile(
                leading: const _TileIcon(Icons.folder_special_rounded),
                title: const Text('الوصول إلى كل الملفات'),
                subtitle: Text(
                  _hasAccess == null
                      ? 'جارٍ الفحص…'
                      : _hasAccess!
                          ? 'ممنوح'
                          : 'غير ممنوح: اضغط لفتح إعدادات النظام',
                ),
                trailing: (_hasAccess ?? true)
                    ? const Icon(Icons.check_circle_rounded, color: Color(0xFF2EC4A6))
                    : const Icon(Icons.chevron_left_rounded),
                onTap: (_hasAccess ?? true) ? null : StorageService.requestAccess,
              ),
            ),
            const SizedBox(height: 28),
            Center(
              child: Text(
                'مدير الملفات  •  الإصدار 1.0.0',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.5),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 10),
      child: Text(
        text,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _TileIcon extends StatelessWidget {
  const _TileIcon(this.icon);
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.14),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: AppTheme.primary, size: 22),
    );
  }
}
