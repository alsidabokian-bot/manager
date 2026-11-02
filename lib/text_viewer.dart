import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'file_models.dart';
import 'file_open.dart';
import 'format.dart';
import 'text_preview.dart';

/// عارض الملفات النصية (نص عادي، JSON، كود…) للقراءة والنسخ.
class TextViewerScreen extends StatefulWidget {
  const TextViewerScreen({super.key, required this.item});
  final FileItem item;

  @override
  State<TextViewerScreen> createState() => _TextViewerScreenState();
}

class _TextViewerScreenState extends State<TextViewerScreen> {
  static final RegExp _arabic = RegExp(r'[\u0600-\u06FF]');

  late final Future<TextPreview> _future = readTextPreview(widget.item.path);
  double _size = 14;
  List<String> _lines = const [];

  void _zoom(double delta) {
    setState(() => _size = (_size + delta).clamp(10.0, 26.0).toDouble());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'تصغير الخط',
            icon: const Icon(Icons.text_decrease_rounded),
            onPressed: () => _zoom(-2),
          ),
          IconButton(
            tooltip: 'تكبير الخط',
            icon: const Icon(Icons.text_increase_rounded),
            onPressed: () => _zoom(2),
          ),
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'copy') {
                final data = await _future;
                await Clipboard.setData(ClipboardData(text: data.text));
                if (!context.mounted) return;
                ScaffoldMessenger.of(context)
                  ..hideCurrentSnackBar()
                  ..showSnackBar(const SnackBar(content: Text('تم نسخ النص')));
              } else if (v == 'share') {
                await shareFilePaths(context, [widget.item.path]);
              } else if (v == 'open') {
                await openExternally(context, widget.item.path);
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'copy', child: Text('نسخ النص')),
              PopupMenuItem(value: 'share', child: Text('مشاركة')),
              PopupMenuItem(value: 'open', child: Text('فتح بتطبيق آخر')),
            ],
          ),
        ],
      ),
      body: FutureBuilder<TextPreview>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snap.data;
          if (data == null || data.error != null) {
            return _notice(
              context,
              Icons.error_outline_rounded,
              data?.error ?? 'تعذّرت قراءة الملف',
            );
          }
          if (data.binary) {
            return _notice(context, Icons.data_object_rounded, 'هذا الملف ليس نصيًا');
          }
          if (_lines.isEmpty) _lines = data.text.split('\n');
          return Column(
            children: [
              if (data.truncated)
                Container(
                  width: double.infinity,
                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.16),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Text(
                    'عُرض أول ${formatSize(maxTextPreviewBytes)} فقط من ${formatSize(widget.item.size)}. '
                    'افتح الملف بتطبيق آخر لقراءته كاملًا.',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(14),
                  itemCount: _lines.length,
                  itemBuilder: (_, i) => _line(_lines[i]),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// السطر العربي يُعرض من اليمين، والكود وبقية الأسطر من اليسار.
  Widget _line(String line) {
    final rtl = _arabic.hasMatch(line);
    return Directionality(
      textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: Text(
          line.isEmpty ? ' ' : line,
          style: TextStyle(fontFamily: 'monospace', fontSize: _size, height: 1.45),
        ),
      ),
    );
  }

  Widget _notice(BuildContext context, IconData icon, String text) {
    final muted = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: muted),
            const SizedBox(height: 12),
            Text(text, style: TextStyle(fontSize: 16, color: muted)),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              onPressed: () => openExternally(context, widget.item.path),
              icon: const Icon(Icons.open_in_new_rounded),
              label: const Text('فتح بتطبيق آخر'),
            ),
          ],
        ),
      ),
    );
  }
}
