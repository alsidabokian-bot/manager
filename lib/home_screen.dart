import 'dart:io';
import 'package:flutter/material.dart';
import 'browser_screen.dart';
import 'format.dart';
import 'settings_screen.dart';
import 'storage_service.dart';
import 'theme.dart';
import 'transfer_screen.dart';

/// الشاشة الرئيسية: التخزين الداخلي ووصول سريع للمجلدات الشائعة.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Map<String, String> _roots = const {};
  DiskSpace? _space;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final roots = await StorageService.roots();
    final space = await StorageService.diskSpace(roots['internal'] ?? '/');
    if (!mounted) return;
    setState(() {
      _roots = roots;
      _space = space;
    });
  }

  void _open(String? path, String title) {
    if (path == null) return;
    if (!Directory(path).existsSync()) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('هذا المجلد غير موجود على جهازك')));
      return;
    }
    Navigator.of(context)
        .push(MaterialPageRoute<void>(
          builder: (_) => FileBrowserScreen(rootPath: path, rootTitle: title),
        ))
        .then((_) => _load()); // تحديث المساحة بعد العودة
  }

  @override
  Widget build(BuildContext context) {
    final quick = <_Quick>[
      _Quick('التنزيلات', Icons.download_rounded, const Color(0xFF42A5F5), 'downloads'),
      _Quick('الصور', Icons.image_rounded, const Color(0xFF26A69A), 'pictures'),
      _Quick('الكاميرا', Icons.photo_camera_rounded, const Color(0xFFEF5350), 'dcim'),
      _Quick('المستندات', Icons.description_rounded, const Color(0xFFFFB74D), 'documents'),
      _Quick('الموسيقى', Icons.music_note_rounded, const Color(0xFFAB47BC), 'music'),
      _Quick('الفيديو', Icons.movie_rounded, const Color(0xFFFF7043), 'movies'),
    ];
    return Scaffold(
      appBar: AppBar(
        title: const Text('مدير الملفات'),
        actions: [
          IconButton(
            tooltip: 'النسخ والنقل',
            icon: const Icon(Icons.swap_vert_rounded),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const TransferScreen()),
            ),
          ),
          IconButton(
            tooltip: 'الإعدادات',
            icon: const Icon(Icons.settings_rounded),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            const ClipRRect(
              borderRadius: BorderRadius.all(Radius.circular(16)),
              child: TransferBanner(),
            ),
            _StorageCard(
              space: _space,
              onTap: () => _open(_roots['internal'], 'التخزين الداخلي'),
            ),
            const SizedBox(height: 24),
            const Padding(
              padding: EdgeInsets.only(bottom: 12, right: 4),
              child: Text(
                'وصول سريع',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
            ),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 2.3,
              children: [
                for (final q in quick)
                  _QuickTile(q: q, onTap: () => _open(_roots[q.key], q.title)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Quick {
  const _Quick(this.title, this.icon, this.color, this.key);
  final String title;
  final IconData icon;
  final Color color;
  final String key;
}

class _QuickTile extends StatelessWidget {
  const _QuickTile({required this.q, required this.onTap});
  final _Quick q;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: q.color.withValues(alpha: 0.16),
                  shape: BoxShape.circle,
                ),
                child: Icon(q.icon, color: q.color, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  q.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StorageCard extends StatelessWidget {
  const _StorageCard({required this.space, required this.onTap});
  final DiskSpace? space;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = space;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(28),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            gradient: AppTheme.primaryGradient,
            borderRadius: BorderRadius.circular(28),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.smartphone_rounded, color: Colors.white, size: 26),
                  SizedBox(width: 10),
                  Text(
                    'التخزين الداخلي',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: s?.usedFraction ?? 0,
                  minHeight: 10,
                  backgroundColor: Colors.white.withValues(alpha: 0.25),
                  valueColor: const AlwaysStoppedAnimation(Colors.white),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                s == null
                    ? 'جارٍ قراءة المساحة...'
                    : 'مستخدم ${formatSize(s.used)} من ${formatSize(s.total)}  •  متاح ${formatSize(s.free)}',
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
