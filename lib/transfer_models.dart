import 'dart:isolate';

/// ما يُفعل بملف موجود مسبقًا في الوجهة بنفس الاسم.
enum ConflictPolicy { skip, replace, keepBoth }

enum JobPhase {
  queued,
  scanning,
  awaitingDecision,
  preparing,
  copying,
  paused,
  done,
  cancelled,
  failed,
}

class TransferRequest {
  const TransferRequest({
    required this.sources,
    required this.destDir,
    required this.move,
    this.deepVerify = false,
    this.presetPolicy,
  });

  final List<String> sources;
  final String destDir;
  final bool move;

  /// مقارنة محتوى الملف المنسوخ بالأصل بايتًا ببايت (أبطأ وأدق).
  final bool deepVerify;

  /// إن وُجد لا يُسأل المستخدم عن التعارض (يُستخدم عند إعادة المحاولة).
  final ConflictPolicy? presetPolicy;
}

class TransferFailure {
  const TransferFailure(this.path, this.reason);
  final String path;
  final String reason;
}

class TransferReport {
  const TransferReport({
    required this.copied,
    required this.skipped,
    required this.failures,
    required this.bytes,
    required this.elapsedMs,
    this.abortReason,
  });

  final int copied; // عدد العناصر الناجحة
  final int skipped;
  final List<TransferFailure> failures;
  final int bytes; // الحجم المنسوخ فعليًا
  final int elapsedMs;
  final String? abortReason; // سبب إيقاف العملية بالكامل (مثل امتلاء المساحة)
}

// ---------- رسائل المحرك (الخيط المنفصل) إلى الواجهة ----------

class WorkerInit {
  const WorkerInit(this.toManager, this.request);
  final SendPort toManager;
  final TransferRequest request;
}

sealed class WorkerEvent {
  const WorkerEvent();
}

/// انتهى الفحص: الواجهة تفحص المساحة وتسأل عن التعارض ثم ترد بـ [GoCommand].
class ScanDone extends WorkerEvent {
  const ScanDone({
    required this.totalBytes,
    required this.fileCount,
    required this.conflictCount,
    required this.existingPartBytes,
  });

  final int totalBytes;
  final int fileCount;
  final int conflictCount;

  /// حجم الأجزاء المؤقتة الموجودة من محاولة سابقة (لا تحتاج مساحة جديدة).
  final int existingPartBytes;
}

class PrepareProgress extends WorkerEvent {
  const PrepareProgress(this.done, this.total);
  final int done;
  final int total;
}

class CopyProgress extends WorkerEvent {
  const CopyProgress({
    required this.doneBytes,
    required this.sessionBytes,
    required this.fileIndex,
    required this.fileCount,
    required this.currentName,
  });

  final int doneBytes; // يشمل ما أُنجز سابقًا (للنسبة)
  final int sessionBytes; // ما نُسخ فعليًا في هذه الجلسة (للسرعة)
  final int fileIndex;
  final int fileCount;
  final String currentName;
}

class Finished extends WorkerEvent {
  const Finished(this.report, this.cancelled);
  final TransferReport report;
  final bool cancelled;
}

class FatalError extends WorkerEvent {
  const FatalError(this.message);
  final String message;
}

// ---------- أوامر الواجهة إلى المحرك ----------
// النصوص: 'pause' و'resume' و'cancel'.

class GoCommand {
  const GoCommand(this.policy);
  final ConflictPolicy policy;
}
