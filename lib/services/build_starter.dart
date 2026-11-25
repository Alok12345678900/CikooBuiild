import 'dart:io';

import 'package:flutter/services.dart';

import '../config.dart';
import '../models/build_record.dart';
import 'build_controller.dart';
import 'github_actions.dart';
import 'github_api_exception.dart';
import 'github_uploader.dart';
import 'permission_helper.dart';
import 'session_manager.dart';
import 'upload_tracker.dart';
import 'user_store.dart';

/// Memulai build / analisis. Semua pengguna memakai satu repo (config.dart); tiap build memakai
/// branch sendiri sehingga tidak ada antrean dan tidak saling menimpa.
class BuildStarter {
  static const List<String> _workflowFiles = [
    'analyzer.yml',
    'build_android.yml',
    'build_flutter.yml',
    'web2apk.yml',
  ];

  static String _mb(num bytes) => (bytes / (1024 * 1024)).toStringAsFixed(1);

  static Future<Map<String, String>> _workflowAssets() async => {
        for (final f in _workflowFiles) f: await rootBundle.loadString('assets/workflows/$f'),
      };

  /// Cek konfigurasi, login, dan credit sebelum mulai.
  static Future<UserRecord?> _preflight(SessionManager session, {required bool needCredit}) async {
    if (!AppConfig.isConfigured) {
      throw Exception('Aplikasi belum dikonfigurasi: isi token GitHub dan username repo di lib/config.dart.');
    }
    if (session.userKey.isEmpty) throw Exception('Silakan masuk dengan Google dulu.');
    final rec = await UserStore(AppConfig.githubToken).read(session.userKey);
    if (rec == null) throw Exception('Data pengguna tidak ditemukan. Keluar lalu masuk lagi.');
    if (needCredit && rec.credit < AppConfig.buildCost) throw InsufficientCreditException(rec.credit);
    return rec;
  }

  static Future<String?> _permissions() async {
    String? warning;
    if (!await PermissionHelper.ensureNotifications()) {
      warning = 'Izin notifikasi ditolak: popup progress tidak akan muncul.';
    }
    await PermissionHelper.requestBatteryExemptionOnce();
    return warning;
  }

  static String _newBranch(SessionManager s) => 'b-${s.keyPrefix}-${DateTime.now().millisecondsSinceEpoch}';

  /// Build Android Studio / Flutter dari ZIP.
  static Future<String?> startZipBuild({
    required SessionManager session,
    required BuildController controller,
    required String type,
    required String zipPath,
    required String mode,
    required String label,
    required String workflowName,
  }) async {
    const owner = AppConfig.repoOwner;
    const repo = AppConfig.repoName;
    final up = controller.upload;
    final branch = _newBranch(session);

    up.begin('$label • ${session.displayName}', const [
      'Memeriksa izin & credit',
      'Menyiapkan repository',
      'Mengunggah project.zip',
      'Membuat branch build',
      'Menunggu workflow siap',
      'Memicu build',
    ], meta: {
      'type': type,
      'owner': owner,
      'repo': repo,
      'mode': mode,
      'workflow': workflowName,
    });

    try {
      up.startStep(0, detail: 'Memeriksa izin dan credit...');
      final warning = await _permissions();
      final user = await _preflight(session, needCredit: true);
      up.startStep(0, detail: 'Credit: ${user?.credit ?? 0}');

      up.startStep(1, detail: '$owner/$repo');
      const token = AppConfig.githubToken;
      final uploader = GitHubUploader(token, owner, repo);
      await uploader.ensureRepoExists();
      await uploader.ensureWorkflows(await _workflowAssets());

      final zipSize = await File(zipPath).length();
      up.startStep(2, detail: '0.0 / ${_mb(zipSize)} MB', withPercent: true);
      await uploader.uploadZipToBranch(
        zipPath: zipPath,
        branch: branch,
        onFileProgress: (file, f, sent, total) =>
            up.setFraction(f, '${_mb(zipSize * f)} / ${_mb(zipSize)} MB'),
        onFilesDone: () => up.startStep(3, detail: branch),
      );

      up.startStep(4, detail: workflowName);
      final actions = GitHubActions(token);
      if (!await actions.waitForWorkflowReady(owner, repo, workflowName)) {
        throw GitHubApiException(404, 'Workflow $workflowName tidak terdeteksi di GitHub. Coba lagi sebentar lagi.');
      }

      up.startStep(5, detail: mode);
      await _spendAndTrigger(session, actions, workflowName, branch, {'build_type': mode});

      up.complete();
      await controller.begin(BuildRecord(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        type: type,
        owner: owner,
        repo: repo,
        workflow: workflowName,
        startedAt: DateTime.now().millisecondsSinceEpoch,
        branch: branch,
        step: 'Menunggu runner GitHub...',
        mode: mode,
      ));
      return warning;
    } catch (e) {
      up.fail(e.toString().replaceFirst('Exception: ', ''));
      await _cleanup(branch);
      rethrow;
    }
  }

  /// WebToAPK: icon + URL website → APK.
  static Future<String?> startWebToApk({
    required SessionManager session,
    required BuildController controller,
    required String iconPath,
    required String webUrl,
    required String appName,
    required String mode,
  }) async {
    const owner = AppConfig.repoOwner;
    const repo = AppConfig.repoName;
    const workflowName = 'web2apk.yml';
    final up = controller.upload;
    final branch = _newBranch(session);

    up.begin('WebToAPK • ${session.displayName}', const [
      'Memeriksa izin & credit',
      'Menyiapkan repository',
      'Mengunggah icon',
      'Membuat branch build',
      'Menunggu workflow siap',
      'Memicu build',
    ], meta: {
      'type': 'WEBTOAPK',
      'owner': owner,
      'repo': repo,
      'mode': mode,
      'workflow': workflowName,
    });

    try {
      up.startStep(0, detail: 'Memeriksa izin dan credit...');
      final warning = await _permissions();
      final user = await _preflight(session, needCredit: true);
      up.startStep(0, detail: 'Credit: ${user?.credit ?? 0}');

      up.startStep(1, detail: '$owner/$repo');
      const token = AppConfig.githubToken;
      final uploader = GitHubUploader(token, owner, repo);
      await uploader.ensureRepoExists();
      await uploader.ensureWorkflows(await _workflowAssets());

      up.startStep(2, detail: 'icon.png', withPercent: true);
      await uploader.uploadIconToBranch(
        iconPath: iconPath,
        branch: branch,
        onFileProgress: (file, f, sent, total) => up.setFraction(f, '${(f * 100).round()}%'),
        onFilesDone: () => up.startStep(3, detail: branch),
      );

      up.startStep(4, detail: workflowName);
      final actions = GitHubActions(token);
      if (!await actions.waitForWorkflowReady(owner, repo, workflowName)) {
        throw GitHubApiException(404, 'Workflow web2apk.yml tidak terdeteksi di GitHub. Coba lagi sebentar lagi.');
      }

      up.startStep(5, detail: mode);
      await _spendAndTrigger(session, actions, workflowName, branch, {
        'web_url': webUrl,
        'app_name': appName,
        'icon_path': 'icon.png',
        'build_type': mode,
      });

      up.complete();
      await controller.begin(BuildRecord(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        type: 'WEBTOAPK',
        owner: owner,
        repo: repo,
        workflow: workflowName,
        startedAt: DateTime.now().millisecondsSinceEpoch,
        branch: branch,
        step: 'Menunggu runner GitHub...',
        mode: mode,
      ));
      return warning;
    } catch (e) {
      up.fail(e.toString().replaceFirst('Exception: ', ''));
      await _cleanup(branch);
      rethrow;
    }
  }

  /// Analyzer: upload ZIP, jalankan analyzer.yml; bila tidak ada error, tracker otomatis
  /// melanjutkan ke build di branch yang sama (credit dipotong saat build dimulai).
  static Future<String?> startAnalyzer({
    required SessionManager session,
    required BuildController controller,
    required String zipPath,
    required bool deep,
    required String mode,
  }) async {
    const owner = AppConfig.repoOwner;
    const repo = AppConfig.repoName;
    const workflowName = 'analyzer.yml';
    final up = controller.upload;
    final branch = _newBranch(session);

    up.begin('Analyzer • ${session.displayName}', const [
      'Memeriksa izin & credit',
      'Menyiapkan repository',
      'Mengunggah project.zip',
      'Membuat branch analisis',
      'Menunggu workflow siap',
      'Memicu analisis',
    ], meta: {
      'type': 'ANALYZER',
      'owner': owner,
      'repo': repo,
      'mode': deep ? 'mendalam' : 'standar',
      'workflow': workflowName,
    });

    try {
      up.startStep(0, detail: 'Memeriksa izin dan credit...');
      final warning = await _permissions();
      final user = await _preflight(session, needCredit: true);
      up.startStep(0, detail: 'Credit: ${user?.credit ?? 0}');

      up.startStep(1, detail: '$owner/$repo');
      const token = AppConfig.githubToken;
      final uploader = GitHubUploader(token, owner, repo);
      await uploader.ensureRepoExists();
      await uploader.ensureWorkflows(await _workflowAssets());

      final zipSize = await File(zipPath).length();
      up.startStep(2, detail: '0.0 / ${_mb(zipSize)} MB', withPercent: true);
      await uploader.uploadZipToBranch(
        zipPath: zipPath,
        branch: branch,
        onFileProgress: (file, f, sent, total) =>
            up.setFraction(f, '${_mb(zipSize * f)} / ${_mb(zipSize)} MB'),
        onFilesDone: () => up.startStep(3, detail: branch),
      );

      up.startStep(4, detail: workflowName);
      final actions = GitHubActions(token);
      if (!await actions.waitForWorkflowReady(owner, repo, workflowName)) {
        throw GitHubApiException(404, 'Workflow analyzer.yml tidak terdeteksi di GitHub. Coba lagi sebentar lagi.');
      }

      up.startStep(5, detail: deep ? 'mendalam' : 'standar');
      await actions.triggerWorkflow(owner, repo, workflowName, branch, inputs: {'deep': deep ? 'true' : 'false'});

      up.complete();
      await controller.begin(BuildRecord(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        type: 'ANALYZER',
        owner: owner,
        repo: repo,
        workflow: workflowName,
        startedAt: DateTime.now().millisecondsSinceEpoch,
        branch: branch,
        step: 'Menunggu runner GitHub...',
        mode: deep ? 'mendalam' : 'standar',
        chain: {
          'mode': mode,
          'userKey': session.userKey,
          'flutter': {'name': 'build_flutter.yml'},
          'android': {'name': 'build_android.yml'},
        },
      ));
      return warning;
    } catch (e) {
      up.fail(e.toString().replaceFirst('Exception: ', ''));
      await _cleanup(branch);
      rethrow;
    }
  }

  /// Potong credit lalu picu workflow; credit dikembalikan bila pemicuan gagal.
  static Future<void> _spendAndTrigger(
    SessionManager session,
    GitHubActions actions,
    String workflow,
    String branch,
    Map<String, String> inputs,
  ) async {
    final users = UserStore(AppConfig.githubToken);
    await users.spend(session.userKey, AppConfig.buildCost);
    try {
      await actions.triggerWorkflow(AppConfig.repoOwner, AppConfig.repoName, workflow, branch, inputs: inputs);
    } catch (e) {
      await users.refund(session.userKey, AppConfig.buildCost);
      rethrow;
    }
  }

  static Future<void> _cleanup(String branch) async {
    try {
      await GitHubActions(AppConfig.githubToken).deleteBranch(AppConfig.repoOwner, AppConfig.repoName, branch);
    } catch (_) {}
  }
}
