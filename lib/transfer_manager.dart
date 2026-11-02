import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'format.dart';
import 'storage_service.dart';
import 'transfer_dialogs.dart';
import 'transfer_models.dart';
import 'transfer_worker.dart';

/// حالة عملية نسخ أو نقل واحدة (تُحدَّث من المدير فقط).
class TransferJob {
  TransferJob(this.id, this.request);

  final int id;
  final TransferRequest request;

  JobPhase phase = JobPhase.queued;
  int totalBytes = 0;
  int doneBytes = 0;
  int fileCount = 0;
  int fileIndex = 0;
  int prepDone = 0;
  int prepTotal = 0;
  int conflicts = 0;
  String currentName = '';
  double speed = 0; // بايت في الثانية
  TransferReport? report;
  String? message; // سبب الفشل
  bool cancelRequested = false;

  bool get isMove => request.move;

  bool get isFinished =>
      phase == JobPhase.done || phase == JobPhase.cancelled || phase == JobPhase.failed;
  bool get isRunning => !isFinished && phase != JobPhase.queued;

  String get title {
    final verb = request.move ? 'نقل' : 'نسخ';
    final what = request.sources.length == 1
        ? p.basename(request.sources.first)
        : '${request.sources.length} عناصر';
    return '$verb $what';
  }

  String get destName => p.basename(request.destDir);

  double get fraction {
    if (totalBytes <= 0) return 0.0;
    final f = doneBytes / totalBytes;
    return f > 1.0 ? 1.0 : f;
  }

  int? get etaSeconds {
    if (speed < 1024 || totalBytes <= doneBytes) return null;
    return ((totalBytes - doneBytes) / speed).round();
  }
}

/// يدير قائمة انتظار العمليات: عملية واحدة تعمل في كل مرة داخل خيط منفصل،
/// ويُبقي التطبيق حيًّا بخدمة أمامية مع إشعار تقدم.
class TransferManager extends ChangeNotifier {
  TransferManager._();
  static final TransferManager instance = TransferManager._();

  static const int _safetyBytes = 16 * 1024 * 1024;
  static const int _historyLimit = 8;

  final List<TransferJob> jobs = [];
  int _nextId = 1;

  /// يزداد عند انتهاء أي عملية، لتحديث قوائم الملفات المعروضة.
  int completedCount = 0;

  TransferJob? _active;
  ReceivePort? _rx;
  Isolate? _isolate;
  SendPort? _toWorker;

  bool _batteryHintShown = false;
  DateTime _lastSample = DateTime.now();
  DateTime _lastNotify = DateTime.fromMillisecondsSinceEpoch(0);
  int _lastSession = 0;
  double _speedEma = 0;

  TransferJob? get current => _active;

  /// هل هناك عملية جارية أو بالانتظار؟
  bool get hasActivity => jobs.any((j) => !j.isFinished);

  // ---------- واجهة الاستخدام ----------

  TransferJob enqueue(TransferRequest request) {
    final job = TransferJob(_nextId++, request);
    jobs.add(job);
    _trimHistory();
    notifyListeners();
    _pump();
    return job;
  }

  void pause() {
    final job = _active;
    if (job == null || job.phase != JobPhase.copying) return;
    _toWorker?.send('pause');
    job.phase = JobPhase.paused;
    job.speed = 0;
    _updateNotification(job, force: true);
    notifyListeners();
  }

  void resume() {
    final job = _active;
    if (job == null || job.phase != JobPhase.paused) return;
    _toWorker?.send('resume');
    job.phase = JobPhase.copying;
    _lastSample = DateTime.now();
    notifyListeners();
  }

  void cancel(TransferJob job) {
    if (job.phase == JobPhase.queued) {
      job.phase = JobPhase.cancelled;
      notifyListeners();
    } else if (identical(job, _active)) {
      job.cancelRequested = true;
      _toWorker?.send('cancel');
    }
  }

  /// يعيد المحاولة: الملفات التي نجحت تُتخطى، والفاشلة تكمل من جزئها المؤقت.
  void retry(TransferJob job) {
    final remaining = job.request.sources
        .where((s) => FileSystemEntity.typeSync(s, followLinks: false) != FileSystemEntityType.notFound)
        .toList();
    if (remaining.isEmpty) return;
    enqueue(TransferRequest(
      sources: remaining,
      destDir: job.request.destDir,
      move: job.request.move,
      deepVerify: job.request.deepVerify,
      presetPolicy: ConflictPolicy.skip,
    ));
  }

  // ---------- التشغيل ----------

  void _pump() {
    if (_active != null) return;
    for (final job in jobs) {
      if (job.phase == JobPhase.queued) {
        _start(job);
        return;
      }
    }
  }

  Future<void> _start(TransferJob job) async {
    _active = job;
    job.phase = JobPhase.scanning;
    _speedEma = 0;
    _lastSession = 0;
    _lastSample = DateTime.now();
    notifyListeners();

    await StorageService.startService(job.title, 'جارٍ فحص الملفات…');
    unawaited(_maybeShowBatteryHint());

    final rx = ReceivePort();
    _rx = rx;
    try {
      _isolate = await Isolate.spawn(
        transferWorkerMain,
        WorkerInit(rx.sendPort, job.request),
        onError: rx.sendPort,
        onExit: rx.sendPort,
      );
    } catch (e) {
      _fail(job, 'تعذّر تشغيل محرك النسخ: $e');
      return;
    }
    rx.listen((m) => _onMessage(job, m));
  }

  Future<void> _onMessage(TransferJob job, dynamic m) async {
    if (job.isFinished) return;
    if (m is SendPort) {
      _toWorker = m;
      if (job.cancelRequested) m.send('cancel'); // أُلغيت قبل جاهزية المحرك
    } else if (m is ScanDone) {
      await _onScanDone(job, m);
    } else if (m is PrepareProgress) {
      job.phase = JobPhase.preparing;
      job.prepDone = m.done;
      job.prepTotal = m.total;
      _updateNotification(job);
      notifyListeners();
    } else if (m is CopyProgress) {
      _onProgress(job, m);
    } else if (m is Finished) {
      _complete(job, m);
    } else if (m is FatalError) {
      _fail(job, m.message);
    } else if (m is List) {
      _fail(job, 'توقف المحرك: ${m.isNotEmpty ? m.first : ''}');
    } else if (m == null) {
      _fail(job, 'توقف المحرك بشكل غير متوقع');
    }
  }

  Future<void> _onScanDone(TransferJob job, ScanDone m) async {
    job.totalBytes = m.totalBytes;
    job.fileCount = m.fileCount;
    job.conflicts = m.conflictCount;
    notifyListeners();

    // فحص المساحة قبل نقل أي بايت
    final needed = m.totalBytes - m.existingPartBytes;
    final space = await StorageService.diskSpace(job.request.destDir);
    if (job.isFinished) return;
    if (space != null && needed > 0 && needed + _safetyBytes > space.free) {
      job.message = 'المساحة لا تكفي: المطلوب ${formatSize(needed)} والمتاح ${formatSize(space.free)}';
      _toWorker?.send('cancel');
      return;
    }

    var policy = job.request.presetPolicy;
    if (policy == null) {
      if (m.conflictCount > 0) {
        job.phase = JobPhase.awaitingDecision;
        notifyListeners();
        policy = await askConflictPolicy(m.conflictCount);
      } else {
        policy = ConflictPolicy.keepBoth;
      }
    }
    if (job.isFinished) return;
    if (policy == null) {
      _toWorker?.send('cancel');
      return;
    }
    job.phase = JobPhase.preparing;
    _toWorker?.send(GoCommand(policy));
    notifyListeners();
  }

  void _onProgress(TransferJob job, CopyProgress m) {
    if (job.phase != JobPhase.paused) job.phase = JobPhase.copying;
    job.doneBytes = m.doneBytes;
    job.fileIndex = m.fileIndex + 1;
    job.currentName = m.currentName;

    final now = DateTime.now();
    final dt = now.difference(_lastSample).inMilliseconds;
    if (dt >= 400) {
      final inst = (m.sessionBytes - _lastSession) * 1000 / dt;
      _speedEma = _speedEma == 0 ? inst : 0.7 * _speedEma + 0.3 * inst;
      _lastSample = now;
      _lastSession = m.sessionBytes;
    }
    if (job.phase == JobPhase.copying) job.speed = _speedEma;
    _updateNotification(job);
    notifyListeners();
  }

  void _complete(TransferJob job, Finished m) {
    job.report = m.report;
    if (!m.cancelled) {
      final abort = m.report.abortReason;
      job.phase = abort != null ? JobPhase.failed : JobPhase.done;
      if (abort != null) job.message = abort;
    } else {
      // إلغاء بسبب نقص المساحة يُعدّ فشلًا لا إلغاءً من المستخدم
      job.phase = job.message != null ? JobPhase.failed : JobPhase.cancelled;
    }
    job.speed = 0;
    _finishJob(job);
  }

  void _fail(TransferJob job, String message) {
    if (job.isFinished) return;
    job.message = message;
    job.phase = JobPhase.failed;
    job.speed = 0;
    _isolate?.kill(priority: Isolate.immediate);
    _finishJob(job);
  }

  void _finishJob(TransferJob job) {
    _rx?.close();
    _rx = null;
    _isolate = null;
    _toWorker = null;
    _active = null;
    completedCount++;
    _trimHistory();
    if (!jobs.any((j) => j.phase == JobPhase.queued)) {
      unawaited(StorageService.stopService());
    }
    notifyListeners();
    _pump();
  }

  void _trimHistory() {
    final finished = jobs.where((j) => j.isFinished).toList();
    final excess = finished.length - _historyLimit;
    if (excess > 0) {
      for (final j in finished.take(excess)) {
        jobs.remove(j);
      }
    }
  }

  // ---------- الإشعار والبطارية ----------

  void _updateNotification(TransferJob job, {bool force = false}) {
    final now = DateTime.now();
    if (!force && now.difference(_lastNotify).inMilliseconds < 1000) return;
    _lastNotify = now;

    final String text;
    int progress = -1;
    switch (job.phase) {
      case JobPhase.preparing:
        text = 'جارٍ التجهيز…';
      case JobPhase.paused:
        text = 'متوقف مؤقتًا';
        progress = (job.fraction * 100).round();
      case JobPhase.copying:
        progress = (job.fraction * 100).round();
        final speed = job.speed > 0 ? '  •  ${formatSize(job.speed.round())}/ث' : '';
        text = '$progress%$speed  •  ${job.currentName}';
      default:
        text = 'جارٍ فحص الملفات…';
    }
    unawaited(StorageService.updateNotification(job.title, text, progress));
  }

  Future<void> _maybeShowBatteryHint() async {
    if (_batteryHintShown) return;
    _batteryHintShown = true;
    if (await StorageService.isIgnoringBatteryOptimizations()) return;
    await showBatteryHint();
  }
}
