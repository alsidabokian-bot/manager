import 'dart:io';

import 'package:flutter/material.dart';

import 'file_models.dart';
import 'file_open.dart';
import 'format.dart';

/// عارض الصور: تمرير بين صور المجلد، وتكبير بالقرص أو النقر المزدوج.
class ImageViewerScreen extends StatefulWidget {
  const ImageViewerScreen({
    super.key,
    required this.images,
    required this.initialIndex,
  });

  final List<FileItem> images;
  final int initialIndex;

  @override
  State<ImageViewerScreen> createState() => _ImageViewerScreenState();
}

class _ImageViewerScreenState extends State<ImageViewerScreen> {
  late final PageController _pages;
  late int _index;
  bool _bars = true;
  bool _zoomed = false;

  FileItem get _current => widget.images[_index];

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _pages = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          PageView.builder(
            controller: _pages,
            // أثناء التكبير يخصَّص السحب لتحريك الصورة لا للتنقل بين الصور
            physics: _zoomed ? const NeverScrollableScrollPhysics() : const PageScrollPhysics(),
            itemCount: widget.images.length,
            onPageChanged: (i) => setState(() {
              _index = i;
              _zoomed = false;
            }),
            itemBuilder: (_, i) => _ZoomPage(
              key: ValueKey(widget.images[i].path),
              item: widget.images[i],
              onTap: () => setState(() => _bars = !_bars),
              onZoom: (z) {
                if (z != _zoomed) setState(() => _zoomed = z);
              },
            ),
          ),
          PositionedDirectional(
            top: 0,
            start: 0,
            end: 0,
            child: AnimatedOpacity(
              opacity: _bars ? 1 : 0,
              duration: const Duration(milliseconds: 180),
              child: IgnorePointer(ignoring: !_bars, child: _topBar()),
            ),
          ),
        ],
      ),
    );
  }

  Widget _topBar() {
    final f = _current;
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xCC000000), Color(0x00000000)],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 16),
          child: Row(
            children: [
              BackButton(color: Colors.white, onPressed: () => Navigator.of(context).pop()),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      f.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      '${_index + 1} / ${widget.images.length}  •  ${formatSize(f.size)}',
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'مشاركة',
                icon: const Icon(Icons.share_rounded, color: Colors.white),
                onPressed: () => shareFilePaths(context, [f.path]),
              ),
              IconButton(
                tooltip: 'فتح بتطبيق آخر',
                icon: const Icon(Icons.open_in_new_rounded, color: Colors.white),
                onPressed: () => openExternally(context, f.path),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ZoomPage extends StatefulWidget {
  const _ZoomPage({
    super.key,
    required this.item,
    required this.onTap,
    required this.onZoom,
  });

  final FileItem item;
  final VoidCallback onTap;
  final ValueChanged<bool> onZoom;

  @override
  State<_ZoomPage> createState() => _ZoomPageState();
}

class _ZoomPageState extends State<_ZoomPage> {
  final TransformationController _tc = TransformationController();
  Offset _tapPos = Offset.zero;

  @override
  void dispose() {
    _tc.dispose();
    super.dispose();
  }

  bool get _isZoomed => _tc.value.getMaxScaleOnAxis() > 1.05;

  /// النقر المزدوج: يكبّر 2.5 مرة حول موضع اللمس، أو يعيد الحجم الأصلي.
  void _onDoubleTap() {
    if (_isZoomed) {
      _tc.value = Matrix4.identity();
    } else {
      const s = 2.5;
      final tx = -_tapPos.dx * (s - 1);
      final ty = -_tapPos.dy * (s - 1);
      _tc.value = Matrix4(
        s, 0, 0, 0, //
        0, s, 0, 0, //
        0, 0, 1, 0, //
        tx, ty, 0, 1,
      );
    }
    widget.onZoom(_isZoomed);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onDoubleTapDown: (d) => _tapPos = d.localPosition,
      onDoubleTap: _onDoubleTap,
      child: InteractiveViewer(
        transformationController: _tc,
        minScale: 1,
        maxScale: 6,
        onInteractionEnd: (_) => widget.onZoom(_isZoomed),
        child: Image.file(
          File(widget.item.path),
          fit: BoxFit.contain,
          width: double.infinity,
          height: double.infinity,
          cacheWidth: 2400, // يحدّ استهلاك الذاكرة مع الصور الكبيرة
          errorBuilder: (_, __, ___) => const Center(
            child: Text(
              'تعذّر عرض هذه الصورة',
              style: TextStyle(color: Colors.white70),
            ),
          ),
        ),
      ),
    );
  }
}
