import 'package:flutter/material.dart';
import 'storage_service.dart';
import 'theme.dart';

/// يعرض [child] فقط بعد منح إذن الوصول إلى الملفات.
/// يعيد الفحص تلقائيًا عند عودة المستخدم من إعدادات النظام.
class PermissionGate extends StatefulWidget {
  const PermissionGate({super.key, required this.child});
  final Widget child;

  @override
  State<PermissionGate> createState() => _PermissionGateState();
}

class _PermissionGateState extends State<PermissionGate>
    with WidgetsBindingObserver {
  bool? _granted;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  Future<void> _check() async {
    final ok = await StorageService.hasAccess();
    if (mounted && ok != _granted) setState(() => _granted = ok);
  }

  @override
  Widget build(BuildContext context) {
    if (_granted == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_granted!) return widget.child;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 120,
                height: 120,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: AppTheme.primaryGradient,
                ),
                child: const Icon(Icons.folder_open_rounded,
                    size: 60, color: Colors.white),
              ),
              const SizedBox(height: 28),
              const Text(
                'نحتاج إذن الوصول إلى الملفات',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 12),
              Text(
                'لعرض ملفاتك وإدارتها يحتاج التطبيق إلى إذن الوصول إلى كل الملفات. '
                'سيفتح زر المنح إعدادات النظام: فعّل الإذن ثم ارجع إلى التطبيق.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.6,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(height: 32),
              FilledButton.icon(
                onPressed: StorageService.requestAccess,
                icon: const Icon(Icons.lock_open_rounded),
                label: const Text('منح الإذن'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(56),
                  textStyle:
                      const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
