import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'format.dart';
import 'transfer_manager.dart';
import 'transfer_models.dart';

/// شاشة عمليات النسخ والنقل: التقدم والتحكم والتقرير الختامي.
class TransferScreen extends StatelessWidget {
  const TransferScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final manager = TransferManager.instance;
    return Scaffold(
      appBar: AppBar(title: const Text('النسخ والنقل')),
      body: ListenableBuilder(
        listenable: manager,
        builder: (context, _) {
          final jobs = manager.jobs.reversed.toList(); // الأحدث أولًا
          if (jobs.isEmpty) {
            return Center(
              child: Text(
                'لا توجد عمليات بعد',
                style: TextStyle(
                  fontSize: 16,
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            itemCount: jobs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (_, i) => _JobCard(job: jobs[i]),
          );
        },
      ),
    );
  }
}

class _JobCard extends StatelessWidget {
  const _JobCard({required this.job});
  final TransferJob job;

  @override
  Widget build(BuildContext context) {
    final manager = TransferManager.instance;
    final scheme = Theme.of(context).colorScheme;
    final muted = scheme.onSurface.withValues(alpha: 0.6);
    final phase = job.phase;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  job.isMove ? Icons.drive_file_move_rounded : Icons.copy_rounded,
                  color: scheme.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    job.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text('إلى: ${job.destName}', style: TextStyle(fontSize: 12, color: muted)),
            const SizedBox(height: 12),
            Text(_statusText(job), style: const TextStyle(fontWeight: FontWeight.w700)),
            if (_showBar(phase)) ...[
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: _barValue(job),
                  minHeight: 10,
                ),
              ),
            ],
            if (phase == JobPhase.copying || phase == JobPhase.paused) ...[
              const SizedBox(height: 10),
              Text(
                '${formatSize(job.doneBytes)} من ${formatSize(job.totalBytes)}  •  '
                '${(job.fraction * 100).toStringAsFixed(0)}%',
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 4),
              Text(
                'الملف ${job.fileIndex} من ${job.fileCount}: ${job.currentName}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: muted),
              ),
              if (phase == JobPhase.copying && job.speed > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'السرعة ${formatSize(job.speed.round())}/ث'
                    '${job.etaSeconds != null ? '  •  المتبقي ${formatDuration(job.etaSeconds!)}' : ''}',
                    style: TextStyle(fontSize: 12, color: muted),
                  ),
                ),
            ],
            if (phase == JobPhase.copying ||
                phase == JobPhase.paused ||
                phase == JobPhase.scanning ||
                phase == JobPhase.preparing ||
                phase == JobPhase.queued) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  if (phase == JobPhase.copying || phase == JobPhase.paused)
                    FilledButton.tonalIcon(
                      onPressed: phase == JobPhase.copying ? manager.pause : manager.resume,
                      icon: Icon(
                        phase == JobPhase.copying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                      ),
                      label: Text(phase == JobPhase.copying ? 'إيقاف مؤقت' : 'استئناف'),
                    ),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: () => manager.cancel(job),
                    icon: const Icon(Icons.close_rounded),
                    label: const Text('إلغاء'),
                  ),
                ],
              ),
            ],
            if (job.isFinished) _FinishedSection(job: job),
          ],
        ),
      ),
    );
  }

  static bool _showBar(JobPhase p) =>
      p == JobPhase.scanning ||
      p == JobPhase.preparing ||
      p == JobPhase.copying ||
      p == JobPhase.paused;

  /// null = شريط غير محدد (الفحص).
  static double? _barValue(TransferJob j) {
    switch (j.phase) {
      case JobPhase.scanning:
        return null;
      case JobPhase.preparing:
        return j.prepTotal == 0 ? null : j.prepDone / j.prepTotal;
      default:
        return j.fraction;
    }
  }

  static String _statusText(TransferJob j) {
    switch (j.phase) {
      case JobPhase.queued:
        return 'في الانتظار';
      case JobPhase.scanning:
        return 'جارٍ فحص الملفات…';
      case JobPhase.awaitingDecision:
        return 'بانتظار اختيارك…';
      case JobPhase.preparing:
        return j.prepTotal == 0
            ? 'جارٍ التجهيز…'
            : 'جارٍ التجهيز: ${j.prepDone} من ${j.prepTotal} ملف';
      case JobPhase.copying:
        return j.isMove ? 'جارٍ النقل' : 'جارٍ النسخ';
      case JobPhase.paused:
        return 'متوقف مؤقتًا';
      case JobPhase.done:
        return j.isMove ? 'اكتمل النقل' : 'اكتمل النسخ';
      case JobPhase.cancelled:
        return 'أُلغيت العملية';
      case JobPhase.failed:
        return 'توقفت العملية';
    }
  }
}

class _FinishedSection extends StatelessWidget {
  const _FinishedSection({required this.job});
  final TransferJob job;

  @override
  Widget build(BuildContext context) {
    final r = job.report;
    final scheme = Theme.of(context).colorScheme;
    final failures = r?.failures ?? const <TransferFailure>[];
    final canRetry = job.phase != JobPhase.cancelled &&
        (failures.isNotEmpty || job.phase == JobPhase.failed);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (job.message != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(job.message!, style: TextStyle(color: scheme.error)),
          ),
        if (r != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'نجح ${r.copied}  •  تخطٍّ ${r.skipped}  •  فشل ${failures.length}'
              '${r.bytes > 0 ? '  •  ${formatSize(r.bytes)}' : ''}'
              '  •  ${formatDuration((r.elapsedMs / 1000).round())}',
              style: const TextStyle(fontSize: 13),
            ),
          ),
        if (failures.isNotEmpty)
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text(
                'الملفات الفاشلة (${failures.length})',
                style: TextStyle(fontSize: 13, color: scheme.error),
              ),
              children: [
                for (final f in failures.take(50))
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(p.basename(f.path), maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(f.reason),
                  ),
                if (failures.length > 50)
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text('و${failures.length - 50} ملفًا آخر'),
                  ),
              ],
            ),
          ),
        if (canRetry)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: FilledButton.tonalIcon(
              onPressed: () => TransferManager.instance.retry(job),
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('إعادة محاولة الفاشل'),
            ),
          ),
      ],
    );
  }
}

/// شريط صغير يظهر أعلى الشاشات أثناء وجود عملية جارية، ويفتح شاشة التقدم.
class TransferBanner extends StatelessWidget {
  const TransferBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final manager = TransferManager.instance;
    return ListenableBuilder(
      listenable: manager,
      builder: (context, _) {
        final job = manager.current;
        if (job == null) return const SizedBox.shrink();
        final scheme = Theme.of(context).colorScheme;
        final active = job.phase == JobPhase.copying || job.phase == JobPhase.paused;
        return Material(
          color: scheme.primary.withValues(alpha: 0.16),
          child: InkWell(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const TransferScreen()),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.sync_rounded, size: 20, color: scheme.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${_TitleHelper.status(job)}  •  ${job.title}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                        ),
                      ),
                      if (active)
                        Text(
                          '${(job.fraction * 100).toStringAsFixed(0)}%',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  LinearProgressIndicator(
                    value: active ? job.fraction : null,
                    minHeight: 4,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _TitleHelper {
  static String status(TransferJob j) => _JobCard._statusText(j);
}
