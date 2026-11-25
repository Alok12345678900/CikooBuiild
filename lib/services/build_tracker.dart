import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/build_record.dart';
import 'artifact_service.dart';
import 'build_store.dart';
import 'github_actions.dart';
import 'github_uploader.dart';
import 'log_store.dart';
import 'notification_service.dart';
import '../config.dart';
import 'user_store.dart';

/// Pemanggil 'update' ke UI. Di service = `service.invoke`, di dalam app = reload langsung.
typedef TrackerInvoke = void Function(String method, Map<String, dynamic>? args);

class BuildTracker {
  static const String _kUseService = 'use_bg_service';

  /// true = pelacak berjalan di foreground service (tetap jalan saat app ditutup).
  /// false = mode aman: pelacak berjalan di dalam aplikasi (tanpa service).
  static Future<bool> serviceEnabled() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.reload();
      return p.getBool(_kUseService) ?? true;
    } catch (_) {
      return true;
    }
  }

  static Future<void> setServiceEnabled(bool value) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kUseService, value);
  }

  static Future<void> configure() async {
    await FlutterBackgroundService().configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onBuildServiceStart,
        autoStart: false,
        autoStartOnBoot: false, // Android 15 melarang FGS dataSync dimulai dari BOOT_COMPLETED
        isForegroundMode: true,
        notificationChannelId: kProgressChannelId,
        initialNotificationTitle: AppConfig.appName,
        initialNotificationContent: 'Menyiapkan build...',
        foregroundServiceNotificationId: kProgressNotifId,
      ),
      iosConfiguration: IosConfiguration(autoStart: false),
    );
  }

  /// Memulai service bila belum jalan. Service yang sudah berjalan otomatis mengambil
  /// build baru pada siklus berikutnya (tidak perlu restart).
  static Future<void> start() async {
    final service = FlutterBackgroundService();
    if (await service.isRunning()) return;
    await service.startService();
  }
}

@pragma('vm:entry-point')
Future<void> onBuildServiceStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  bool stopped = false;
  service.on('stop').listen((_) {
    stopped = true;
  });

  try {
    await trackBuild(
      invoke: (m, a) => service.invoke(m, a),
      stopped: () => stopped,
      background: true,
    );
  } catch (e) {
    debugPrint('[BuildTracker] Fatal error: $e');
  } finally {
    try {
      service.stopSelf();
    } catch (_) {}
  }
}

/// Menyimpan riwayat secara berurutan (hindari tulis bersamaan dari callback progress).
class _Persister {
  Future<void> _chain = Future<void>.value();

  void queue(BuildRecord r) {
    _chain = _chain.then((_) => BuildStore.appendHistory(r)).catchError((_) {});
  }

  Future<void> flush() => _chain;
}

class _RecState {
  _RecState(this.rec);

  BuildRecord rec;
  int emptyRunRetries = 0;
  int errors = 0;
  int polls = 0;
  bool finishing = false;
}

/// Inti pelacakan: memantau SEMUA build aktif (maks 3 sekaligus) dalam satu loop.
/// [background] = berjalan di isolate service (perlu init notifikasi sendiri).
Future<void> trackBuild({
  required TrackerInvoke invoke,
  required bool Function() stopped,
  required bool background,
}) async {
  if (background) {
    try {
      await NotificationService.initBackground();
    } catch (e) {
      debugPrint('[BuildTracker] initBackground gagal: $e');
    }
  }

  const token = AppConfig.githubToken;
  if (token.isEmpty) {
    debugPrint('[BuildTracker] Token kosong');
    return;
  }

  final api = GitHubActions(token);
  final states = <String, _RecState>{};
  var pendingFinish = 0;
  var idleRounds = 0;
  const maxEmptyRetries = 50;
  const maxConsecutiveErrors = 20;

  void startFinish(_RecState st, BuildRecord rec, {String? errorMessage}) {
    st.finishing = true;
    pendingFinish++;
    unawaited(() async {
      try {
        await _finish(invoke, rec, token);
        if (errorMessage != null) await _notifyError(rec, errorMessage);
      } catch (e) {
        debugPrint('[BuildTracker] finish error: $e');
      } finally {
        pendingFinish--;
      }
    }());
  }

  debugPrint('[BuildTracker] Mulai tracking');

  while (!stopped()) {
    final stored = await BuildStore.loadActive();
    final live = stored.where((r) => !r.isFinished).toList();
    final liveIds = live.map((e) => e.id).toSet();

    states.removeWhere((id, st) => !liveIds.contains(id) && !st.finishing);
    for (final r in live) {
      final st = states.putIfAbsent(r.id, () => _RecState(r));
      if (!st.finishing) st.rec = r;
    }

    if (live.isEmpty && pendingFinish == 0) {
      idleRounds++;
      if (idleRounds >= 2) break;
    } else {
      idleRounds = 0;
    }

    for (final st in states.values.toList()) {
      if (st.finishing) continue;
      var rec = st.rec;

      final deadline = DateTime.fromMillisecondsSinceEpoch(rec.startedAt)
          .add(const Duration(minutes: 60));
      if (DateTime.now().isAfter(deadline)) {
        final t = rec.copyWith(
          status: 'failure',
          step: 'Melewati batas waktu pelacakan (Timeout 60 menit)',
        );
        st.rec = t;
        startFinish(st, t, errorMessage: 'Build timeout setelah 60 menit');
        continue;
      }

      try {
        if (rec.runId == null) {
          final run = (rec.branch != null && rec.branch!.startsWith('b-'))
              ? await api.findRunByBranch(rec.owner, rec.repo, rec.workflow, rec.branch!)
              : await api.findRun(rec.owner, rec.repo, rec.workflow, rec.baselineRunId);
          if (run != null) {
            rec = rec.copyWith(runId: run.id, url: run.htmlUrl);
            st.emptyRunRetries = 0;
          } else {
            st.emptyRunRetries++;
            if (st.emptyRunRetries >= maxEmptyRetries) {
              final failed = rec.copyWith(
                status: 'failure',
                step: 'Gagal menemukan workflow run di GitHub',
              );
              st.rec = failed;
              startFinish(st, failed,
                  errorMessage: 'Workflow run tidak ditemukan setelah 5 menit');
              continue;
            }
          }
        }

        final runId = rec.runId;
        if (runId != null) {
          final p = await api.progress(rec.owner, rec.repo, runId);
          final newStatus = p.finished
              ? p.finalStatus
              : (p.status == 'queued' ? 'queued' : 'running');

          // Persen tidak pernah turun (jumlah step bertambah seiring job dimulai).
          var newPercent = rec.percent;
          if (p.finished) {
            newPercent = p.finalStatus == 'success' ? 100 : rec.percent;
          } else if (p.percent > newPercent) {
            newPercent = p.percent;
          }

          // Log berjalan: ambil tiap ~3 polling supaya hemat kuota API.
          var logTail = rec.logTail;
          if (!p.finished) {
            final jobId = p.runningJobId;
            if (jobId != null) {
              final t = await api.jobLogTail(rec.owner, rec.repo, jobId, maxBytes: 40000);
              if (t.isNotEmpty) logTail = _cap(t);
            }
          }
          if (p.finished && p.finalStatus != 'success') {
            final jobId = p.failedJobId ?? p.runningJobId;
            if (jobId != null) {
              final t = await api.jobLogTail(rec.owner, rec.repo, jobId, maxBytes: 40000);
              if (t.isNotEmpty) logTail = _cap(t);
            }
          }

          rec = rec.copyWith(
            status: newStatus,
            percent: newPercent,
            step: p.stepLabel,
            url: p.htmlUrl,
            diagnostics: p.diagnostics,
            jobs: p.jobs,
            runNumber: p.runNumber,
            branch: p.branch,
            sha: p.sha,
            actor: p.actor,
            logTail: logTail,
          );

          if (p.finished) {
            st.rec = rec;
            startFinish(st, rec);
            continue;
          }
        }

        st.rec = rec;
        await BuildStore.updateActiveIfPresent(rec);
        invoke('update', {'id': rec.id});
        st.errors = 0;
      } catch (e) {
        st.errors++;
        debugPrint('[BuildTracker] Polling error ${rec.repo} (${st.errors}/$maxConsecutiveErrors): $e');
        if (st.errors >= maxConsecutiveErrors) {
          final failed = rec.copyWith(
            status: 'failure',
            step: 'Koneksi ke GitHub terputus. Build dihentikan.',
          );
          st.rec = failed;
          startFinish(st, failed, errorMessage: 'Koneksi ke GitHub terputus selama 2 menit');
        }
      }
      st.polls++;
    }

    final liveRecs = states.values.where((s) => !s.finishing).map((s) => s.rec).toList();
    if (liveRecs.isNotEmpty) await _publishAll(liveRecs);

    // Satu build: polling cepat agar log terasa live; banyak build: lebih jarang (hemat kuota API).
    final waitSec = liveRecs.length <= 1 ? 4 : (liveRecs.length == 2 ? 6 : 8);
    await Future<void>.delayed(Duration(seconds: waitSec));
  }

  debugPrint('[BuildTracker] Selesai / dihentikan');
}

String _cap(String s, [int max = 12000]) =>
    s.length <= max ? s : s.substring(s.length - max);

Future<void> _notifyError(BuildRecord rec, String message) async {
  try {
    await NotificationService.showError(
      title: rec.isAnalyzer ? 'Analisis gagal ❌' : 'Build Gagal ❌',
      body: '${rec.typeLabel} • ${rec.repo}: $message',
      buildKey: rec.id,
    );
  } catch (e) {
    debugPrint('[BuildTracker] Gagal kirim notifikasi error: $e');
  }
}

/// Satu notifikasi progress untuk semua build yang berjalan.
Future<void> _publishAll(List<BuildRecord> recs) async {
  try {
    if (recs.length == 1) {
      final rec = recs.first;
      await NotificationService.showProgress(
        title: _label(rec),
        body:
            '${rec.step.isEmpty ? 'Menunggu runner GitHub...' : rec.step}\n${rec.percent}% • ${_fmt(rec.elapsedMs)}',
        percent: rec.percent,
        indeterminate: rec.percent == 0,
      );
      return;
    }
    final avg = recs.fold<int>(0, (a, r) => a + r.percent) ~/ recs.length;
    final lines = recs.map((r) => '• ${r.isAnalyzer ? 'Analisis' : r.typeLabel} ${r.repo}: ${r.percent}%').join('\n');
    await NotificationService.showProgress(
      title: '${recs.length} proses berjalan',
      body: lines,
      percent: avg,
      indeterminate: avg == 0,
    );
  } catch (e) {
    debugPrint('[BuildTracker] Gagal update notifikasi progress: $e');
  }
}

String _label(BuildRecord r) =>
    r.isAnalyzer ? 'Analisis • ${r.repo}' : 'Build ${r.typeLabel} • ${r.repo}';

String _fmt(int ms) {
  final s = ms ~/ 1000;
  final m = s ~/ 60;
  final sec = s % 60;
  return m > 0 ? '${m}m ${sec}s' : '${sec}s';
}

Future<void> _cancelProgressIfIdle() async {
  try {
    final a = await BuildStore.loadActive();
    if (a.where((r) => !r.isFinished).isEmpty) {
      await NotificationService.cancelProgress();
    }
  } catch (_) {}
}

Future<void> _finish(TrackerInvoke invoke, BuildRecord rec, String token) async {
  if (rec.isAnalyzer) {
    await _finishAnalyzer(invoke, rec, token);
    return;
  }
  try {
    var done = rec.copyWith(
      finishedAt: DateTime.now().millisecondsSinceEpoch,
      percent: rec.isSuccess ? 100 : rec.percent,
    );

    if (done.isSuccess && done.runId != null) {
      done = done.copyWith(
        step: 'Build selesai. Mengunduh APK...',
        downloadState: 'downloading',
        downloadPercent: 0,
        downloadError: '',
      );
    }

    debugPrint('[BuildTracker] Build selesai: ${done.status} (${done.percent}%)');

    // Build gagal: simpan log lengkap ke file supaya detailnya bisa dibaca di riwayat.
    if (done.status == 'failure' && done.runId != null) {
      final logFile = await _saveFullLog(done, token);
      if (logFile != null) done = done.copyWith(logPath: logFile);
    }

    await BuildStore.appendHistory(done);
    await BuildStore.removeActive(done.id);
    invoke('update', {'id': done.id});

    // Popup hasil build (heads-up).
    try {
      await NotificationService.showDone(
        buildKey: done.id,
        title: done.isSuccess
            ? 'Build selesai ✅'
            : (done.status == 'cancelled' ? 'Build dibatalkan' : 'Build gagal ❌'),
        body: done.isSuccess
            ? '${done.typeLabel} • ${done.repo} berhasil dibuild. Mengunduh APK...'
            : '${done.typeLabel} • ${done.repo} ${done.statusLabel.toLowerCase()}. Ketuk untuk melihat detail.',
      );
    } catch (e) {
      debugPrint('[BuildTracker] Gagal kirim notifikasi done: $e');
    }

    if (!(done.isSuccess && done.runId != null)) {
      await _deleteBranch(done);
      await _cancelProgressIfIdle();
      return;
    }

    final persister = _Persister();
    var lastPct = -10;
    try {
      final path = await ArtifactService(token).downloadApk(
        rec: done,
        onProgress: (f) {
          final pct = (f * 100).floor().clamp(0, 100);
          if (pct >= lastPct + 5) {
            lastPct = pct;
            NotificationService.showDownloadProgress(
              title: 'Unduh APK • ${done.repo}',
              percent: pct,
            ).catchError((_) {});
            persister.queue(done.copyWith(downloadPercent: pct));
            invoke('update', {'id': done.id});
          }
        },
      );
      await persister.flush();
      done = done.copyWith(
        step: 'Build selesai. APK siap diinstal.',
        apkPath: path,
        apkSize: await File(path).length(),
        downloadState: 'done',
        downloadPercent: 100,
        downloadError: '',
      );
      await BuildStore.appendHistory(done);
      await _cancelProgressIfIdle();
      try {
        await NotificationService.showDone(
          buildKey: '${done.id}_apk',
          title: 'APK siap diinstal ✅',
          body: '${done.typeLabel} • ${done.repo}. Ketuk lalu tekan Install APK.',
        );
      } catch (_) {}
    } catch (e) {
      await persister.flush();
      final msg = e.toString().replaceFirst('Exception: ', '');
      debugPrint('[BuildTracker] Unduh APK gagal: $msg');
      done = done.copyWith(
        step: 'Build selesai, tapi unduh APK gagal.',
        downloadState: 'failed',
        downloadError: msg,
      );
      await BuildStore.appendHistory(done);
      await _cancelProgressIfIdle();
      try {
        await NotificationService.showError(
          buildKey: '${done.id}_dl',
          title: 'Unduh APK gagal',
          body: '${done.typeLabel} • ${done.repo}: $msg. Buka tab Progress untuk unduh ulang.',
        );
      } catch (_) {}
    }

    await _deleteBranch(done);
    invoke('update', {'id': done.id});
  } catch (e) {
    debugPrint('[BuildTracker] Gagal finish: $e');
  }
}

/// Selesai menganalisis: baca laporan analyzer.yml, tampilkan hanya error,
/// dan bila tidak ada error lanjutkan otomatis ke build.
Future<void> _finishAnalyzer(TrackerInvoke invoke, BuildRecord rec, String token) async {
  try {
    final chain = rec.chain;
    var done = rec.copyWith(finishedAt: DateTime.now().millisecondsSinceEpoch, chain: const {});

    if (rec.status == 'cancelled') {
      await _deleteBranch(rec);
      await BuildStore.appendHistory(done);
      await BuildStore.removeActive(done.id);
      invoke('update', {'id': done.id});
      await _cancelProgressIfIdle();
      return;
    }

    var errors = <Map<String, dynamic>>[];
    var steps = <Map<String, dynamic>>[];
    var kind = '';
    String? failure;

    if (rec.isSuccess && rec.runId != null) {
      try {
        final text = await ArtifactService(token).fetchTextFile(
          owner: rec.owner,
          repo: rec.repo,
          runId: rec.runId!,
          artifactNameContains: 'analyzer-report',
          fileName: 'analysis-report.json',
        );
        if (text == null) {
          failure = 'Laporan analisis tidak ditemukan di artifact workflow.';
        } else {
          final data = jsonDecode(text);
          if (data is Map) {
            kind = data['kind']?.toString() ?? '';
            if (data['steps'] is List) {
              steps = (data['steps'] as List)
                  .whereType<Map>()
                  .map((m) => m.map((k, v) => MapEntry(k.toString(), v)))
                  .toList();
            }
            if (data['findings'] is List) {
              errors = (data['findings'] as List)
                  .whereType<Map>()
                  .where((m) => m['sev'] == 'error')
                  .take(100)
                  .map((m) => m.map((k, v) => MapEntry(k.toString(), v)))
                  .toList();
            }
          } else {
            failure = 'Format laporan analisis tidak valid.';
          }
        }
      } catch (e) {
        failure = 'Gagal membaca laporan analisis: ${e.toString().replaceFirst('Exception: ', '')}';
      }
    } else {
      failure = 'Workflow analyzer gagal berjalan di GitHub Actions.';
    }

    if (failure != null) {
      errors = [
        {
          'sev': 'error',
          'title': failure,
          'detail': rec.logTail.isEmpty ? '' : _cap(rec.logTail, 1500),
          'file': null,
          'line': null,
        }
      ];
    }

    final hasErrors = errors.isNotEmpty;
    final proceed = !hasErrors && chain.isNotEmpty;
    done = done.copyWith(
      status: hasErrors ? 'failure' : 'success',
      percent: hasErrors ? done.percent : 100,
      step: hasErrors
          ? 'Ditemukan ${errors.length} error'
          : (proceed ? 'Tidak ada error. Melanjutkan build...' : 'Tidak ada error.'),
      analysis: {'kind': kind, 'steps': steps, 'findings': errors},
    );

    await BuildStore.appendHistory(done);
    await BuildStore.removeActive(done.id);
    invoke('update', {'id': done.id});

    try {
      await NotificationService.showDone(
        buildKey: done.id,
        title: hasErrors ? 'Analisis menemukan error ❌' : 'Analisis lolos ✅',
        body: hasErrors
            ? '${done.repo}: ${errors.length} error. Ketuk untuk melihat detailnya.'
            : '${done.repo}: tidak ada error.${proceed ? ' Build dilanjutkan otomatis.' : ''}',
      );
    } catch (_) {}

    if (proceed) {
      await _chainBuild(invoke, done, chain, kind, token);
    } else {
      await _deleteBranch(rec);
    }
    await _cancelProgressIfIdle();
  } catch (e) {
    debugPrint('[BuildTracker] Gagal finish analyzer: $e');
  }
}

/// Memulai build otomatis setelah analisis lolos, di branch yang sama (ZIP sudah ada).
/// Credit dipotong di sini dan dikembalikan bila pemicuan gagal.
Future<void> _chainBuild(
  TrackerInvoke invoke,
  BuildRecord analyzer,
  Map<String, dynamic> chain,
  String kind,
  String token,
) async {
  Future<void> fail(String title, String body) async {
    try {
      await NotificationService.showError(buildKey: '${analyzer.id}_chain', title: title, body: body);
    } catch (_) {}
    await _deleteBranch(analyzer);
  }

  final pick = chain[kind];
  if (pick is! Map) {
    await fail('Build tidak dilanjutkan',
        'Jenis project "${kind.isEmpty ? 'tidak dikenali' : kind}" belum didukung untuk build otomatis.');
    return;
  }

  final name = pick['name'].toString();
  final mode = chain['mode']?.toString() ?? 'release';
  final userKey = chain['userKey']?.toString() ?? '';
  final users = UserStore(token);
  var spent = false;

  try {
    if (userKey.isNotEmpty) {
      await users.spend(userKey, AppConfig.buildCost);
      spent = true;
    }

    final api = GitHubActions(token);
    final branch = analyzer.branch ?? '';
    await api.triggerWorkflow(analyzer.owner, analyzer.repo, name, branch, inputs: {'build_type': mode});

    final build = BuildRecord(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      type: kind == 'flutter' ? 'FLUTTER' : 'ANDROID',
      owner: analyzer.owner,
      repo: analyzer.repo,
      workflow: name,
      startedAt: DateTime.now().millisecondsSinceEpoch,
      branch: branch,
      step: 'Menunggu runner GitHub...',
      mode: mode,
    );
    await BuildStore.upsertActive(build);
    invoke('update', {'id': build.id});

    try {
      await NotificationService.showStarted(
        title: 'Build dimulai 🚀',
        body: '${build.typeLabel} ($mode). Analisis lolos, build dilanjutkan otomatis.',
      );
    } catch (_) {}
  } on InsufficientCreditException catch (e) {
    await fail('Build tidak dilanjutkan', e.toString());
  } catch (e) {
    if (spent) await users.refund(userKey, AppConfig.buildCost);
    final msg = e.toString().replaceFirst('Exception: ', '');
    debugPrint('[BuildTracker] Gagal melanjutkan build: $msg');
    await fail('Gagal melanjutkan build', msg);
  }
}

/// Branch build dihapus setelah selesai supaya repo tidak penuh.
Future<void> _deleteBranch(BuildRecord rec) async {
  final b = rec.branch;
  if (b == null || !b.startsWith('b-')) return;
  try {
    await GitHubActions(AppConfig.githubToken).deleteBranch(rec.owner, rec.repo, b);
  } catch (e) {
    debugPrint('[BuildTracker] Hapus branch gagal: $e');
  }
}

Future<String?> _saveFullLog(BuildRecord rec, String token) async {
  try {
    int? jobId;
    for (final j in rec.jobs) {
      if (j['conclusion'] == 'failure') {
        jobId = (j['id'] as num?)?.toInt();
        break;
      }
    }
    jobId ??= rec.jobs.isEmpty ? null : (rec.jobs.last['id'] as num?)?.toInt();
    if (jobId == null) return null;
    final text = await GitHubActions(token).jobLogTail(rec.owner, rec.repo, jobId, maxBytes: 400000);
    if (text.isEmpty) return null;
    return await LogStore.save(rec.id, text);
  } catch (e) {
    debugPrint('[BuildTracker] Gagal simpan log: $e');
    return null;
  }
}
