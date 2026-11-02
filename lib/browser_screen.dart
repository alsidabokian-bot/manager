import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import 'app_settings.dart';
import 'clipboard.dart';
import 'file_dialogs.dart';
import 'file_models.dart';
import 'file_open.dart';
import 'file_ops.dart';
import 'file_search.dart';
import 'format.dart';
import 'transfer_manager.dart';
import 'transfer_models.dart';
import 'transfer_screen.dart';
import 'view_options.dart';
import 'view_prefs.dart';

/// شاشة تصفح مجلد: مسار التنقل، بحث، ترتيب، عرض قائمة أو شبكة،
/// تحديد متعدد، ونسخ ونقل وحذف وإعادة تسمية.
class FileBrowserScreen extends StatefulWidget {
  const FileBrowserScreen({
    super.key,
    required this.rootPath,
    required this.rootTitle,
  });

  final String rootPath;
  final String rootTitle;

  @override
  State<FileBrowserScreen> createState() => _FileBrowserScreenState();
}

class _FileBrowserScreenState extends State<FileBrowserScreen> {
  final ScrollController _crumbScroll = ScrollController();
  final TextEditingController _searchCtl = TextEditingController();
  late String _current;

  // محتوى المجلد، والقائمة المعروضة (بعد البحث والترتيب)
  List<FileItem>? _items;
  List<FileItem> _view = const [];
  Object? _error;
  bool _loading = true;
  bool _lastHidden = false;
  int _lastCompleted = 0;
  final Set<String> _selected = {};

  // البحث
  bool _searching = false;
  bool _deep = false; // البحث في المجلدات الفرعية
  String _query = '';
  final List<FileItem> _results = [];
  bool _searchRunning = false;
  bool _truncated = false;
  int _scanned = 0;
  int _searchGen = 0;
  FileSearch? _search;
  Timer? _debounce;

  ViewPrefs get _prefs => ViewPrefs.instance;
  bool get _showHidden => AppSettings.instance.showHidden;
  bool get _selecting => _selected.isNotEmpty;
  bool get _atRoot => p.equals(_current, widget.rootPath);
  bool get _deepActive => _searching && _deep && _query.trim().length >= 2;

  @override
  void initState() {
    super.initState();
    _current = widget.rootPath;
    _lastCompleted = TransferManager.instance.completedCount;
    _lastHidden = _showHidden;
    TransferManager.instance.addListener(_onTransfer);
    _prefs.addListener(_onPrefs);
    AppSettings.instance.addListener(_onSettings);
    _load();
  }

  @override
  void dispose() {
    TransferManager.instance.removeListener(_onTransfer);
    _prefs.removeListener(_onPrefs);
    AppSettings.instance.removeListener(_onSettings);
    _debounce?.cancel();
    _search?.cancel();
    _crumbScroll.dispose();
    _searchCtl.dispose();
    super.dispose();
  }

  void _onPrefs() {
    if (mounted) setState(_refreshView);
  }

  /// تغيير «إظهار المخفية» (من القائمة أو الإعدادات) يعيد قراءة المجلد.
  void _onSettings() {
    if (!mounted) return;
    if (_lastHidden != _showHidden) {
      _lastHidden = _showHidden;
      _afterChange();
    } else {
      setState(() {});
    }
  }

  /// بعد انتهاء أي عملية نسخ أو نقل نحدّث القائمة المعروضة.
  void _onTransfer() {
    final c = TransferManager.instance.completedCount;
    if (c != _lastCompleted) {
      _lastCompleted = c;
      if (mounted) _afterChange();
    }
  }

  /// يحدّث محتوى المجلد ونتائج البحث العميق بعد أي تغيير في الملفات.
  void _afterChange() {
    _load();
    if (_deepActive) _startDeepSearch();
  }

  // ---------- القائمة المعروضة ----------

  /// يعيد بناء القائمة المعروضة: تصفية البحث ثم الترتيب.
  /// تُستدعى داخل setState.
  void _refreshView() {
    Iterable<FileItem> base = _items ?? const <FileItem>[];
    final q = _query.trim().toLowerCase();
    if (_searching && q.isNotEmpty) {
      base = _deep
          ? _results
          : base.where((f) => f.name.toLowerCase().contains(q));
    }
    _view = sortedItems(base, _prefs);
  }

  // ---------- التحميل والتنقل ----------

  Future<void> _load() async {
    final path = _current;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await listDirectory(path, showHidden: _showHidden);
      if (!mounted || path != _current) return; // المستخدم انتقل لمجلد آخر
      setState(() {
        _items = items;
        _loading = false;
        if (!_deepActive) {
          // نُسقط من التحديد ما لم يعد موجودًا
          final existing = items.map((i) => i.path).toSet();
          _selected.removeWhere((s) => !existing.contains(s));
        }
        _refreshView();
      });
    } catch (e) {
      if (!mounted || path != _current) return;
      setState(() {
        _items = null;
        _view = const [];
        _error = e;
        _loading = false;
      });
    }
  }

  void _open(String path) {
    _resetSearch();
    _selected.clear();
    _current = path;
    _items = null;
    _view = const [];
    _load();
  }

  void _goUp() => _open(p.dirname(_current));

  void _snack(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  // ---------- البحث ----------

  void _startSearch() => setState(() => _searching = true);

  /// يعيد حالة البحث للأصل (دون setState).
  void _resetSearch() {
    _searching = false;
    _query = '';
    _searchCtl.clear();
    _stopDeepSearch();
    _results.clear();
    _scanned = 0;
    _truncated = false;
  }

  void _exitSearch() {
    setState(() {
      _resetSearch();
      _refreshView();
    });
  }

  void _onQueryChanged(String v) {
    setState(() {
      _query = v;
      if (_deep) {
        _results.clear();
        _truncated = false;
      }
      _refreshView();
    });
    _debounce?.cancel();
    if (_deep) _debounce = Timer(const Duration(milliseconds: 400), _startDeepSearch);
  }

  void _toggleDeep() {
    setState(() {
      _deep = !_deep;
      _results.clear();
      _truncated = false;
      _scanned = 0;
      if (!_deep) _stopDeepSearch();
      _refreshView();
    });
    if (_deep) _startDeepSearch();
  }

  void _stopDeepSearch() {
    _debounce?.cancel();
    _searchGen++;
    _search?.cancel();
    _search = null;
    _searchRunning = false;
  }

  Future<void> _startDeepSearch() async {
    _stopDeepSearch();
    final q = _query.trim();
    if (!_deep || q.length < 2) {
      if (mounted) {
        setState(() {
          _results.clear();
          _refreshView();
        });
      }
      return;
    }
    setState(() {
      _results.clear();
      _searchRunning = true;
      _truncated = false;
      _scanned = 0;
      _refreshView();
    });
    final gen = _searchGen;
    final s = await FileSearch.start(
      root: _current,
      query: q,
      showHidden: _showHidden,
      onBatch: (b) {
        if (!mounted || gen != _searchGen) return;
        setState(() {
          _results.addAll(b.items);
          _scanned = b.scannedDirs;
          if (b.done) {
            _searchRunning = false;
            _truncated = b.truncated;
          }
          _refreshView();
        });
      },
    );
    if (!mounted || gen != _searchGen) {
      s.cancel(); // انتهى هذا البحث أثناء تشغيل الخيط
      return;
    }
    _search = s;
  }

  // ---------- التحديد ----------

  void _toggle(FileItem f) {
    setState(() {
      if (!_selected.remove(f.path)) _selected.add(f.path);
    });
  }

  void _clearSelection() => setState(_selected.clear);

  void _selectAll() => setState(() => _selected.addAll(_view.map((i) => i.path)));

  List<FileItem> _selectedItems() =>
      _view.where((i) => _selected.contains(i.path)).toList();

  // ---------- العمليات ----------

  void _toClipboard(ClipMode mode) {
    final items = _selectedItems();
    if (items.isEmpty) return;
    FileClipboard.instance.set(items.map((i) => i.path).toList(), mode);
    _clearSelection();
    final what = items.length == 1 ? items.first.name : '${items.length} عناصر';
    _snack('جاهز ${mode == ClipMode.copy ? 'للنسخ' : 'للنقل'}: $what. افتح مجلد الوجهة ثم اضغط «لصق هنا»');
  }

  void _paste() {
    final clip = FileClipboard.instance;
    TransferManager.instance.enqueue(TransferRequest(
      sources: List.of(clip.paths),
      destDir: _current,
      move: clip.mode == ClipMode.move,
      deepVerify: AppSettings.instance.deepVerify,
    ));
    clip.clear();
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const TransferScreen()),
    );
  }

  Future<void> _shareSelected() async {
    final items = _selectedItems();
    final files = items.where((i) => !i.isDir).toList();
    if (files.isEmpty) {
      _snack('لا يمكن مشاركة المجلدات، حدّد ملفات');
      return;
    }
    final skipped = items.length - files.length;
    _clearSelection();
    await shareFilePaths(context, files.map((f) => f.path).toList());
    if (skipped > 0 && mounted) _snack('تُجوهل $skipped مجلد (المجلدات لا تُشارك)');
  }

  Future<void> _deleteSelected() async {
    final items = _selectedItems();
    if (items.isEmpty) return;
    if (!await confirmDelete(context, items) || !mounted) return;
    final failures = await runWithProgress(
      context,
      'جارٍ الحذف…',
      () => deletePaths(items.map((i) => i.path).toList()),
    );
    if (!mounted) return;
    _clearSelection();
    _afterChange();
    if (failures.isEmpty) {
      _snack(items.length == 1 ? 'تم الحذف' : 'تم حذف ${items.length} عناصر');
    } else {
      await showFailures(context, 'تعذّر حذف ${failures.length} عنصر', failures);
    }
  }

  Future<void> _renameSelected() async {
    final items = _selectedItems();
    if (items.length != 1) return;
    final f = items.first;
    final dir = p.dirname(f.path);
    final name = await askName(
      context,
      title: 'إعادة تسمية',
      okLabel: 'حفظ',
      initial: f.name,
      selectBaseOnly: !f.isDir,
      validator: (n) => validateNameIn(dir, n, oldName: f.name),
    );
    if (name == null || name == f.name || !mounted) return;
    final err = renameEntry(f.path, name);
    if (err != null) {
      _snack(err);
      return;
    }
    _clearSelection();
    _afterChange();
  }

  Future<void> _newFolder() async {
    final name = await askName(
      context,
      title: 'مجلد جديد',
      okLabel: 'إنشاء',
      validator: (n) => validateNameIn(_current, n),
    );
    if (name == null || !mounted) return;
    final err = createFolder(_current, name);
    if (err != null) {
      _snack(err);
      return;
    }
    _snack('تم إنشاء المجلد');
    _afterChange();
  }

  // ---------- مسار التنقل ----------

  List<({String label, String path})> _crumbs() {
    final crumbs = [(label: widget.rootTitle, path: widget.rootPath)];
    final rel = p.relative(_current, from: widget.rootPath);
    if (rel != '.') {
      var acc = widget.rootPath;
      for (final part in p.split(rel)) {
        acc = p.join(acc, part);
        crumbs.add((label: part, path: acc));
      }
    }
    return crumbs;
  }

  Widget _breadcrumbs() {
    final crumbs = _crumbs();
    final scheme = Theme.of(context).colorScheme;
    // نُبقي آخر مجلد ظاهرًا (في الواجهة العربية نهاية التمرير هي اليسار)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_crumbScroll.hasClients) {
        _crumbScroll.jumpTo(_crumbScroll.position.maxScrollExtent);
      }
    });
    return SizedBox(
      height: 44,
      child: ListView.separated(
        controller: _crumbScroll,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: crumbs.length,
        separatorBuilder: (_, __) => Icon(
          Icons.chevron_left_rounded,
          size: 20,
          color: scheme.onSurface.withValues(alpha: 0.4),
        ),
        itemBuilder: (_, i) {
          final c = crumbs[i];
          final last = i == crumbs.length - 1;
          return Center(
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: last ? null : () => _open(c.path),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Text(
                  c.label,
                  style: TextStyle(
                    fontWeight: last ? FontWeight.w800 : FontWeight.w500,
                    color: last ? scheme.primary : scheme.onSurface,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ---------- أشرطة التطبيق ----------

  PreferredSizeWidget _normalBar() {
    return AppBar(
      title: Text(
        _atRoot ? widget.rootTitle : p.basename(_current),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      actions: [
        IconButton(
          tooltip: 'بحث',
          icon: const Icon(Icons.search_rounded),
          onPressed: _startSearch,
        ),
        IconButton(
          tooltip: 'العرض والترتيب',
          icon: const Icon(Icons.tune_rounded),
          onPressed: () => showViewOptions(context),
        ),
        IconButton(
          tooltip: 'النسخ والنقل',
          icon: const Icon(Icons.swap_vert_rounded),
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const TransferScreen()),
          ),
        ),
        PopupMenuButton<String>(
          onSelected: (v) {
            switch (v) {
              case 'hidden':
                AppSettings.instance.setShowHidden(!_showHidden);
              case 'all':
                _selectAll();
              case 'refresh':
                _afterChange();
            }
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'all', child: Text('تحديد الكل')),
            const PopupMenuItem(value: 'refresh', child: Text('تحديث')),
            CheckedPopupMenuItem(
              value: 'hidden',
              checked: _showHidden,
              child: const Text('إظهار الملفات المخفية'),
            ),
          ],
        ),
      ],
    );
  }

  PreferredSizeWidget _searchBar() {
    final scheme = Theme.of(context).colorScheme;
    return AppBar(
      leading: BackButton(onPressed: _exitSearch),
      title: TextField(
        controller: _searchCtl,
        autofocus: true,
        onChanged: _onQueryChanged,
        style: const TextStyle(fontSize: 16),
        decoration: InputDecoration(
          hintText: _deep ? 'ابحث في هذا المجلد وما بداخله…' : 'ابحث في هذا المجلد…',
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          filled: false,
        ),
      ),
      actions: [
        if (_query.isNotEmpty)
          IconButton(
            tooltip: 'مسح',
            icon: const Icon(Icons.close_rounded),
            onPressed: () {
              _searchCtl.clear();
              _onQueryChanged('');
            },
          ),
        IconButton(
          tooltip: 'البحث في المجلدات الفرعية',
          icon: Icon(
            Icons.account_tree_rounded,
            color: _deep ? scheme.primary : null,
          ),
          onPressed: _toggleDeep,
        ),
        IconButton(
          tooltip: 'العرض والترتيب',
          icon: const Icon(Icons.tune_rounded),
          onPressed: () => showViewOptions(context),
        ),
      ],
    );
  }

  PreferredSizeWidget _selectionBar() {
    return AppBar(
      leading: IconButton(
        tooltip: 'إلغاء التحديد',
        icon: const Icon(Icons.close_rounded),
        onPressed: _clearSelection,
      ),
      title: Text('${_selected.length} محدد'),
      actions: [
        IconButton(
          tooltip: 'نسخ',
          icon: const Icon(Icons.copy_rounded),
          onPressed: () => _toClipboard(ClipMode.copy),
        ),
        IconButton(
          tooltip: 'نقل',
          icon: const Icon(Icons.drive_file_move_rounded),
          onPressed: () => _toClipboard(ClipMode.move),
        ),
        IconButton(
          tooltip: 'حذف',
          icon: const Icon(Icons.delete_rounded),
          onPressed: _deleteSelected,
        ),
        PopupMenuButton<String>(
          onSelected: (v) {
            switch (v) {
              case 'all':
                _selectAll();
              case 'share':
                _shareSelected();
              case 'open':
                openExternally(context, _selectedItems().first.path);
              case 'rename':
                _renameSelected();
              case 'details':
                _showDetails(_selectedItems().first);
            }
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'all', child: Text('تحديد الكل')),
            const PopupMenuItem(value: 'share', child: Text('مشاركة')),
            if (_selected.length == 1) ...[
              if (!_selectedItems().first.isDir)
                const PopupMenuItem(value: 'open', child: Text('فتح بتطبيق آخر')),
              const PopupMenuItem(value: 'rename', child: Text('إعادة تسمية')),
              const PopupMenuItem(value: 'details', child: Text('تفاصيل')),
            ],
          ],
        ),
      ],
    );
  }

  PreferredSizeWidget _bar() {
    if (_selecting) return _selectionBar();
    if (_searching) return _searchBar();
    return _normalBar();
  }

  // ---------- الهيكل ----------

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _atRoot && !_selecting && !_searching,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_selecting) {
          _clearSelection();
        } else if (_searching) {
          _exitSearch();
        } else {
          _goUp();
        }
      },
      child: Scaffold(
        appBar: _bar(),
        body: Column(
          children: [
            const TransferBanner(),
            _breadcrumbs(),
            const Divider(height: 1),
            if (_deepActive) _searchStatus(),
            Expanded(child: _body()),
          ],
        ),
        floatingActionButton: (_selecting || _searching)
            ? null
            : FloatingActionButton(
                tooltip: 'مجلد جديد',
                onPressed: _newFolder,
                child: const Icon(Icons.create_new_folder_rounded),
              ),
        bottomNavigationBar: _selecting ? null : _pasteBar(),
      ),
    );
  }

  Widget _searchStatus() {
    final muted = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7);
    final text = _searchRunning
        ? 'جارٍ البحث…  ${_results.length} نتيجة  •  فُحص $_scanned مجلد'
        : '${_results.length} نتيجة${_truncated ? ' (أول ${FileSearch.maxResults} فقط، حدّد البحث أكثر)' : ''}';
    return Column(
      children: [
        if (_searchRunning) const LinearProgressIndicator(minHeight: 3),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
          child: Row(
            children: [
              Expanded(child: Text(text, style: TextStyle(fontSize: 12, color: muted))),
              if (_searchRunning)
                TextButton(
                  onPressed: () => setState(_stopDeepSearch),
                  child: const Text('إيقاف'),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _pasteBar() {
    return ListenableBuilder(
      listenable: FileClipboard.instance,
      builder: (context, _) {
        final clip = FileClipboard.instance;
        if (clip.isEmpty) return const SizedBox.shrink();
        final move = clip.mode == ClipMode.move;
        return Material(
          color: Theme.of(context).colorScheme.surfaceContainerHigh,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'إلغاء',
                    icon: const Icon(Icons.close_rounded),
                    onPressed: clip.clear,
                  ),
                  Expanded(
                    child: Text(
                      '${clip.paths.length} عنصر جاهز ${move ? 'للنقل' : 'للنسخ'}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: _paste,
                    icon: const Icon(Icons.content_paste_go_rounded),
                    label: const Text('لصق هنا'),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ---------- المحتوى ----------

  Widget _body() {
    if (_loading && _items == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return _Message(
        icon: Icons.error_outline_rounded,
        text: 'تعذّرت قراءة هذا المجلد',
        action: TextButton(onPressed: _load, child: const Text('إعادة المحاولة')),
      );
    }
    if (_searching && _deep && _query.trim().isNotEmpty && _query.trim().length < 2) {
      return const _Message(
        icon: Icons.search_rounded,
        text: 'اكتب حرفين على الأقل للبحث في المجلدات الفرعية',
      );
    }
    if (_view.isEmpty) {
      if (_searching && _query.trim().isNotEmpty) {
        if (_searchRunning) return const SizedBox.shrink();
        return const _Message(icon: Icons.search_off_rounded, text: 'لا توجد نتائج');
      }
      return const _Message(icon: Icons.folder_open_rounded, text: 'المجلد فارغ');
    }
    final grid = _prefs.mode == ViewMode.grid;
    return RefreshIndicator(
      onRefresh: _load,
      child: grid
          ? GridView.builder(
              key: ValueKey('g$_current'),
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 140,
                childAspectRatio: 0.82,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
              ),
              itemCount: _view.length,
              itemBuilder: (_, i) => _gridTile(_view[i]),
            )
          : ListView.builder(
              key: ValueKey('l$_current'), // يعيد التمرير للأعلى عند تغيير المجلد
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(bottom: 88), // مساحة للزر العائم
              itemCount: _view.length,
              itemBuilder: (_, i) => _listTile(_view[i]),
            ),
    );
  }

  void _onTap(FileItem f) {
    if (_selecting) {
      _toggle(f);
    } else if (f.isDir) {
      _open(f.path);
    } else {
      openItem(context, f, _view);
    }
  }

  Widget _listTile(FileItem f) {
    final scheme = Theme.of(context).colorScheme;
    final color = _kindColor(f.kind);
    final selected = _selected.contains(f.path);
    final meta = f.isDir
        ? formatDate(f.modified)
        : '${formatSize(f.size)}  •  ${formatDate(f.modified)}';
    // في نتائج البحث العميق نعرض مكان العنصر
    final showPlace = _deepActive && p.dirname(f.path) != _current;
    final place = showPlace ? p.relative(p.dirname(f.path), from: widget.rootPath) : '';
    return ListTile(
      selected: selected,
      selectedTileColor: scheme.primary.withValues(alpha: 0.14),
      isThreeLine: showPlace,
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: selected ? scheme.primary : color.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(
          selected ? Icons.check_rounded : _kindIcon(f.kind),
          color: selected ? scheme.onPrimary : color,
        ),
      ),
      title: Text(f.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        showPlace ? '$place\n$meta' : meta,
        maxLines: showPlace ? 2 : 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 12),
      ),
      trailing: _selecting
          ? Checkbox(value: selected, onChanged: (_) => _toggle(f))
          : (f.isDir ? const Icon(Icons.chevron_left_rounded) : null),
      onTap: () => _onTap(f),
      onLongPress: () => _toggle(f),
    );
  }

  Widget _gridTile(FileItem f) {
    final scheme = Theme.of(context).colorScheme;
    final color = _kindColor(f.kind);
    final selected = _selected.contains(f.path);

    Widget bigIcon() => Center(
          child: Icon(_kindIcon(f.kind), size: 44, color: color),
        );

    // الصور تُعرض مصغّرة بدل الأيقونة (بدقة منخفضة لتوفير الذاكرة)
    final preview = f.kind == FileKind.image
        ? Image.file(
            File(f.path),
            cacheWidth: 300,
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
            gaplessPlayback: true,
            errorBuilder: (_, __, ___) => bigIcon(),
          )
        : bigIcon();

    return Material(
      color: selected
          ? scheme.primary.withValues(alpha: 0.22)
          : scheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _onTap(f),
        onLongPress: () => _toggle(f),
        child: Stack(
          children: [
            Column(
              children: [
                Expanded(
                  child: Container(
                    width: double.infinity,
                    color: color.withValues(alpha: 0.10),
                    child: preview,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
                  child: Text(
                    f.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12, height: 1.25),
                  ),
                ),
              ],
            ),
            if (selected)
              PositionedDirectional(
                top: 6,
                end: 6,
                child: CircleAvatar(
                  radius: 12,
                  backgroundColor: scheme.primary,
                  child: Icon(Icons.check_rounded, size: 16, color: scheme.onPrimary),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showDetails(FileItem f) {
    Widget row(String k, String v) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(k, style: const TextStyle(fontSize: 12, color: Colors.grey)),
              SelectableText(v),
            ],
          ),
        );
    final parent = p.dirname(f.path);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تفاصيل'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              row('الاسم', f.name),
              row('النوع', _kindName(f.kind)),
              if (!f.isDir) row('الحجم', '${formatSize(f.size)} (${f.size} بايت)'),
              row('آخر تعديل', formatDate(f.modified)),
              row('المسار', f.path),
            ],
          ),
        ),
        actions: [
          if (parent != _current)
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                _open(parent); // «إظهار في المجلد» لنتائج البحث
              },
              child: const Text('إظهار في المجلد'),
            ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إغلاق')),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text, this.action});
  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: muted),
            const SizedBox(height: 12),
            Text(text, textAlign: TextAlign.center, style: TextStyle(fontSize: 16, color: muted)),
            if (action != null) action!,
          ],
        ),
      ),
    );
  }
}

IconData _kindIcon(FileKind k) {
  switch (k) {
    case FileKind.folder:
      return Icons.folder_rounded;
    case FileKind.image:
      return Icons.image_rounded;
    case FileKind.video:
      return Icons.movie_rounded;
    case FileKind.audio:
      return Icons.music_note_rounded;
    case FileKind.document:
      return Icons.description_rounded;
    case FileKind.archive:
      return Icons.folder_zip_rounded;
    case FileKind.apk:
      return Icons.android_rounded;
    case FileKind.code:
      return Icons.code_rounded;
    case FileKind.other:
      return Icons.insert_drive_file_rounded;
  }
}

Color _kindColor(FileKind k) {
  switch (k) {
    case FileKind.folder:
      return const Color(0xFFFFB74D);
    case FileKind.image:
      return const Color(0xFF26A69A);
    case FileKind.video:
      return const Color(0xFFEF5350);
    case FileKind.audio:
      return const Color(0xFFAB47BC);
    case FileKind.document:
      return const Color(0xFF42A5F5);
    case FileKind.archive:
      return const Color(0xFF8D6E63);
    case FileKind.apk:
      return const Color(0xFF66BB6A);
    case FileKind.code:
      return const Color(0xFF5C6BC0);
    case FileKind.other:
      return const Color(0xFF90A4AE);
  }
}

String _kindName(FileKind k) {
  switch (k) {
    case FileKind.folder:
      return 'مجلد';
    case FileKind.image:
      return 'صورة';
    case FileKind.video:
      return 'فيديو';
    case FileKind.audio:
      return 'صوت';
    case FileKind.document:
      return 'مستند';
    case FileKind.archive:
      return 'ملف مضغوط';
    case FileKind.apk:
      return 'تطبيق أندرويد';
    case FileKind.code:
      return 'كود';
    case FileKind.other:
      return 'ملف';
  }
}
