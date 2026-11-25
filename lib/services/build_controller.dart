import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_background_service/flutter_background_service.dart';

import '../models/build_record.dart';
import 'apk_info_service.dart';
import 'artifact_service.dart';
import 'cloud_service.dart';
import 'storage_service.dart';
import 'build_store.dart';
import 'build_tracker.dart';
import 'github_actions.dart';
import 'log_store.dart';
import 'notification_service.dart';
import 'session_manager.dart';
import 'upload_tracker.dart';

class BuildController extends ChangeNotifier {
  BuildController({required this.session});

  final SessionManager session;

  /// Progress UPLOAD (ZIP/workflow/trigger) — terpisah dari progress build.
  final UploadTracker upload = UploadTracker();

  /// Maksimal build yang boleh berjalan bersamaan.
  static const int maxConcurrent = 3;

  /// Proses upload yang sedang berjalan (belum jadi build); ditampilkan menyatu dengan progress build.
  BuildRecord? pending;
  bool _enriching = false;

  List<BuildRecord> active = [];
  List<BuildRecord> history = [];
  StreamSubscription<dynamic>? _sub;
  Timer? _healTimer;

  // Mode aman: pelacak berjalan di dalam app (tanpa foreground service).
  bool _inApp = false;
  bool _inAppStop = false;
  final Set<String> _prevActiveIds = {};

  // Unduhan manual dari UI (tombol Unduh / Unduh ulang)
  bool downloading = false;
  double downloadProgress = 0;
  String? downloadingId;

  /// Analisis terbaru (aktif atau selesai) untuk ditampilkan di layar Analyzer.
  BuildRecord? get latestAnalyzer {
    for (final r in active.reversed) {
      if (r.isAnalyzer) return r;
    }
    for (final r in history) {
      if (r.isAnalyzer) return r;
    }
    return null;
  }

  BuildRecord? get current => active.isEmpty ? null : active.first;
  int get activeCount => active.where((r) => !r.isFinished).length;
  bool get isRunning => activeCount > 0;
  bool get uploading => pending != null && pending!.status == 'uploading';
  bool get canStartNew => activeCount < maxConcurrent && !uploading;

  /// Satu repo hanya boleh punya satu build aktif (upload project.zip menimpa file yang sama).
  bool repoBusy(String owner, String repo) => active.any((r) =>
      !r.isFinished &&
      r.owner.toLowerCase() == owner.toLowerCase() &&
      r.repo.toLowerCase() == repo.toLowerCase());

  /// Yang ditampilkan di kartu progress: build aktif terbaru, kalau tidak ada maka build terakhir.
  BuildRecord? get display =>
      pending ?? (active.isNotEmpty ? active.last : (history.isEmpty ? null : history.first));

  BuildRecord? byId(String id) {
    if (id == 'pending_upload') return pending;
    for (final a in active) {
      if (a.id == id) return a;
    }
    for (final h in history) {
      if (h.id == id) return h;
    }
    return null;
  }

  Future<void> init() async {
    upload.addListener(_onUploadChanged);
    await reload();
    _sub = FlutterBackgroundService().on('update').listen((_) => reload());
  }

  Future<void> reload() async {
    active = await BuildStore.loadActive();
    history = await BuildStore.loadHistory();
    notifyListeners();
    await _notifyIfJustFinished();
    unawaited(_enrichApks());
    _syncHealTimer();

    if (isRunning) {
      await _ensureTracking();
      return;
    }

    // Unduhan latar belakang yang terhenti (service sudah mati) ditandai gagal supaya bisa diulang.
    if (!downloading && !_inApp) {
      final stuck = history.where((r) => r.downloadState == 'downloading').toList();
      if (stuck.isNotEmpty) {
        var serviceRunning = false;
        try {
          serviceRunning = await FlutterBackgroundService().isRunning();
        } catch (_) {}
        if (!serviceRunning) {
          for (final r in stuck) {
            await BuildStore.appendHistory(r.copyWith(
              downloadState: 'failed',
              downloadError: 'Unduhan terhenti. Ketuk "Unduh ulang".',
            ));
          }
          history = await BuildStore.loadHistory();
          notifyListeners();
        }
      }
    }
  }

  /// Penjaga: selama ada build aktif, pastikan pelacak (service / dalam app) hidup.
  void _syncHealTimer() {
    if (isRunning) {
      _healTimer ??= Timer.periodic(const Duration(seconds: 10), (_) => _ensureTracking());
    } else {
      _healTimer?.cancel();
      _healTimer = null;
    }
  }

  Future<void> _ensureTracking() async {
    if (!isRunning) return;
    if (await BuildTracker.serviceEnabled()) {
      var running = false;
      try {
        running = await FlutterBackgroundService().isRunning();
      } catch (_) {}
      if (!running) await _startServiceSafely();
    } else if (!_inApp) {
      unawaited(_runInApp());
    }
  }

  void _onUploadChanged() {
    final u = upload;
    if (!u.visible || u.done) {
      if (pending != null) {
        pending = null;
        notifyListeners();
      }
      return;
    }
    final m = u.meta;
    final label = (u.current >= 0 && u.current < u.steps.length) ? u.steps[u.current] : 'Menyiapkan...';
    pending = BuildRecord(
      id: 'pending_upload',
      type: m['type'] ?? 'ANDROID',
      owner: m['owner'] ?? '',
      repo: m['repo'] ?? '',
      workflow: m['workflow'] ?? '',
      startedAt: pending?.startedAt ?? DateTime.now().millisecondsSinceEpoch,
      status: u.error != null ? 'failure' : 'uploading',
      percent: (u.overall * 100).round().clamp(0, 99),
      step: u.error ?? '$label${u.detail.isEmpty ? '' : ' • ${u.detail}'}',
      mode: m['mode'] ?? '',
    );
    notifyListeners();
  }

  void dismissPending() => upload.dismiss();

  /// Baca nama, icon, versi, dan ukuran APK riwayat yang belum punya info tersebut.
  Future<void> _enrichApks() async {
    if (_enriching) return;
    _enriching = true;
    try {
      var changed = false;
      for (final r in history.take(30)) {
        if (!r.hasApk || r.apkLabel.isNotEmpty) continue;
        final f = File(r.apkPath!);
        if (!await f.exists()) continue;
        final info = await ApkInfoService.read(r.apkPath!, r.id);
        await BuildStore.appendHistory(r.copyWith(
          apkLabel: info.label.isEmpty ? r.repo : info.label,
          apkPackage: info.package,
          apkVersion: info.version,
          apkIconPath: info.iconPath,
          apkSize: await f.length(),
        ));
        changed = true;
      }
      if (changed) {
        history = await BuildStore.loadHistory();
        notifyListeners();
      }
      await _publishApks();
    } catch (e) {
      debugPrint('Baca info APK gagal: $e');
    } finally {
      _enriching = false;
    }
  }

  String _apkName(BuildRecord r) {
    final base = (r.apkLabel.isEmpty ? r.repo : r.apkLabel).replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');
    final ver = (r.apkVersion.isEmpty ? r.id : r.apkVersion).replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');
    return '${base}_$ver.apk';
  }

  /// Sesuai pengaturan profil: salin APK ke folder Download publik dan/atau unggah ke Google Drive.
  Future<void> _publishApks() async {
    final dest = await StorageService.apkDestination();
    final cloud = await StorageService.cloudAuto();
    if (dest != 'download' && !cloud) return;

    var changed = false;
    for (final r in history.take(10)) {
      if (!r.hasApk || r.apkLabel.isEmpty) continue;
      var rec = r;
      if (dest == 'download' && rec.publicPath.isEmpty) {
        try {
          rec = rec.copyWith(publicPath: await ArtifactService.saveToDownloads(rec.apkPath!, _apkName(rec)));
        } catch (e) {
          rec = rec.copyWith(publicPath: '!${e.toString().replaceFirst('Exception: ', '')}');
        }
      }
      if (cloud && rec.cloudLink.isEmpty) {
        try {
          rec = rec.copyWith(cloudLink: await CloudService.uploadApk(rec.apkPath!, _apkName(rec)));
        } catch (e) {
          rec = rec.copyWith(cloudLink: '!${e.toString().replaceFirst('Exception: ', '')}');
        }
      }
      if (!identical(rec, r)) {
        await BuildStore.appendHistory(rec);
        changed = true;
      }
    }
    if (changed) {
      history = await BuildStore.loadHistory();
      notifyListeners();
    }
  }

  /// Unggah manual satu APK ke Google Drive. Mengembalikan link.
  Future<String> uploadToDrive(BuildRecord rec) async {
    final path = rec.apkPath;
    if (path == null || path.isEmpty) throw Exception('APK belum diunduh.');
    final link = await CloudService.uploadApk(path, _apkName(rec));
    await BuildStore.appendHistory(rec.copyWith(cloudLink: link));
    await reload();
    return link;
  }

  /// Pastikan log lengkap ada di perangkat (unduh dari GitHub bila perlu). Mengembalikan path file.
  Future<String> loadLog(BuildRecord rec) async {
    if (rec.logPath.isNotEmpty && await File(rec.logPath).exists()) return rec.logPath;
    final token = await session.getToken();
    if (token.isEmpty) throw Exception('Token tidak ditemukan, silakan login ulang.');

    int? jobId;
    for (final j in rec.jobs) {
      if (j['conclusion'] == 'failure') {
        jobId = (j['id'] as num?)?.toInt();
        break;
      }
    }
    jobId ??= rec.jobs.isEmpty ? null : (rec.jobs.last['id'] as num?)?.toInt();
    if (jobId == null) throw Exception('Detail job tidak tersedia untuk riwayat ini.');

    final text = await GitHubActions(token).jobLogTail(rec.owner, rec.repo, jobId, maxBytes: 400000);
    if (text.isEmpty) throw Exception('Log tidak tersedia di GitHub (mungkin sudah kedaluwarsa).');
    final path = await LogStore.save(rec.id, text);
    await BuildStore.appendHistory(rec.copyWith(logPath: path));
    await reload();
    return path;
  }

  /// Cadangan: kalau build baru saja selesai dan app terbuka, pastikan popup hasil muncul.
  /// ID notifikasi sama dengan yang dipakai service, jadi tidak muncul dobel.
  Future<void> _notifyIfJustFinished() async {
    final nowIds = active.where((r) => !r.isFinished).map((r) => r.id).toSet();
    final gone = _prevActiveIds.difference(nowIds);
    _prevActiveIds
      ..clear()
      ..addAll(nowIds);

    for (final id in gone) {
      final r = byId(id);
      if (r == null || !r.isFinished || r.isAnalyzer) continue;
      try {
        if (r.isSuccess) {
          await NotificationService.showDone(
            buildKey: r.id,
            title: 'Build selesai ✅',
            body: '${r.typeLabel} • ${r.repo} berhasil dibuild.',
          );
        } else if (r.status == 'cancelled') {
          // dibatalkan pengguna: tanpa popup
        } else {
          await NotificationService.showDone(
            buildKey: r.id,
            title: 'Build gagal ❌',
            body: '${r.typeLabel} • ${r.repo} gagal. Ketuk untuk melihat detail.',
          );
        }
      } catch (e) {
        debugPrint('Notifikasi hasil gagal: $e');
      }
    }
  }

  /// Android 12+ melarang memulai foreground service dari latar belakang (bisa membuat app
  /// force close). Jadi service hanya dimulai saat app tampil di depan; kalau tidak,
  /// otomatis dimulai begitu app dibuka lagi (lihat [reload]).
  Future<void> _startServiceSafely() async {
    final state = WidgetsBinding.instance.lifecycleState;
    if (state != null && state != AppLifecycleState.resumed) return;
    try {
      await BuildTracker.start();
    } catch (e) {
      debugPrint('Gagal memulai service pelacak: $e');
    }
  }

  Future<void> _runInApp() async {
    if (_inApp) return;
    _inApp = true;
    _inAppStop = false;
    try {
      await trackBuild(
        invoke: (m, a) {
          if (m == 'update') unawaited(reload());
        },
        stopped: () => _inAppStop,
        background: false,
      );
    } catch (e) {
      debugPrint('Pelacak dalam app berhenti: $e');
    } finally {
      _inApp = false;
      await reload();
    }
  }

  Future<void> begin(BuildRecord input) async {
    var rec = input;
    if (upload.visible && upload.logLines.isNotEmpty && rec.uploadLog.isEmpty) {
      rec = rec.copyWith(
        uploadLog: upload.logLines.join('\n'),
        uploadSteps: List<String>.from(upload.steps),
      );
    }
    pending = null;
    await BuildStore.upsertActive(rec);
    active = [...active.where((r) => r.id != rec.id), rec];
    _prevActiveIds.add(rec.id);
    notifyListeners();
    _syncHealTimer();

    // Popup langsung dari UI (pasti muncul, tidak bergantung pada service).
    try {
      await NotificationService.showStarted(
        title: rec.isAnalyzer ? 'Analisis dimulai 🔍' : 'Build dimulai 🚀',
        body: rec.isAnalyzer
            ? 'Memeriksa ${rec.repo} dengan analyzer.yml. Jika tidak ada error, build dilanjutkan otomatis.'
            : '${rec.typeLabel} • ${rec.repo}${rec.mode.isEmpty ? '' : ' (${rec.mode})'}. Pantau di tab Progress.',
      );
    } catch (e) {
      debugPrint('Notifikasi mulai gagal: $e');
    }

    await _ensureTracking();
  }

  /// Membatalkan salah satu build yang sedang berjalan.
  Future<void> cancelBuild(String id) async {
    BuildRecord? rec;
    for (final r in active) {
      if (r.id == id) rec = r;
    }
    if (rec == null || rec.isFinished || rec.runId == null) return;

    try {
      final token = await session.getToken();
      if (token.isEmpty) {
        throw Exception('Token tidak ditemukan, silakan login ulang.');
      }

      final api = GitHubActions(token);
      await api.cancelRun(rec.owner, rec.repo, rec.runId!);

      final cancelled = rec.copyWith(
        status: 'cancelled',
        step: 'Dibatalkan oleh pengguna',
        finishedAt: DateTime.now().millisecondsSinceEpoch,
      );

      await BuildStore.appendHistory(cancelled);
      await BuildStore.removeActive(id);
      _prevActiveIds.remove(id);
      await reload();
    } catch (e) {
      debugPrint('Gagal membatalkan build: $e');
      rethrow;
    }
  }

  /// Unduh artifact build → ekstrak APK ke penyimpanan aplikasi.
  Future<void> downloadApk(BuildRecord rec) async {
    if (downloading) return;
    downloading = true;
    downloadingId = rec.id;
    downloadProgress = 0;
    notifyListeners();

    var lastNotified = 0.0;
    try {
      final token = await session.getToken();
      if (token.isEmpty) throw Exception('Token tidak ditemukan, silakan login ulang.');

      final path = await ArtifactService(token).downloadApk(
        rec: rec,
        onProgress: (f) {
          downloadProgress = f;
          if (f - lastNotified >= 0.01 || f >= 1.0) {
            lastNotified = f;
            notifyListeners();
          }
        },
      );
      await BuildStore.appendHistory(rec.copyWith(
        apkPath: path,
        downloadState: 'done',
        downloadPercent: 100,
        downloadError: '',
      ));
    } catch (e) {
      final msg = e.toString().replaceFirst('Exception: ', '');
      await BuildStore.appendHistory(rec.copyWith(
        downloadState: 'failed',
        downloadError: msg,
      ));
      downloading = false;
      downloadingId = null;
      await reload();
      rethrow;
    }

    downloading = false;
    downloadingId = null;
    await reload();
  }

  Future<void> installApk(BuildRecord rec) async {
    final path = rec.apkPath;
    if (path == null || path.isEmpty) {
      throw Exception('APK belum diunduh.');
    }
    await ArtifactService.install(path);
  }

  /// Simpan APK ke folder publik Download/<folderName>. Mengembalikan lokasi file.
  Future<String> saveToDownloads(BuildRecord rec) async {
    final path = rec.apkPath;
    if (path == null || path.isEmpty) {
      throw Exception('APK belum diunduh.');
    }
    final name = '${rec.repo}_${rec.typeLabel.replaceAll(' ', '')}_${rec.mode.isEmpty ? 'build' : rec.mode}_${rec.runNumber ?? rec.id}.apk';
    return ArtifactService.saveToDownloads(path, name);
  }

  @override
  void dispose() {
    upload.removeListener(_onUploadChanged);
    _sub?.cancel();
    _healTimer?.cancel();
    upload.dispose();
    super.dispose();
  }
}
