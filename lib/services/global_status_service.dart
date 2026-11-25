import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config.dart';
import 'github_actions.dart';
import 'user_store.dart';

/// Build milik pengguna yang sedang berjalan / mengantre.
class ActiveRun {
  const ActiveRun({
    required this.repo,
    required this.name,
    required this.percent,
    required this.step,
    required this.queued,
  });

  final String repo;
  final String name;
  final int percent;
  final String step;
  final bool queued;
}

class UserBuildStats {
  UserBuildStats(this.login);

  final String login;
  int success = 0;
  int failure = 0;
  int queued = 0;
  int running = 0;
  List<ActiveRun> active = [];

  int get total => success + failure + queued + running;
}

/// Status build SEMUA pengguna. Semua build berjalan di satu repo (config.dart), jadi cukup
/// membaca run terbaru repo itu; pemilik tiap run dikenali dari nama branch (b-<kunci>-<waktu>).
class GlobalStatusService extends ChangeNotifier {
  GlobalStatusService({required this.token});

  final String token;

  bool loading = false;
  String? error;
  String phase = '';
  int doneRepos = 0;
  int totalRepos = 0;
  DateTime? updatedAt;
  List<UserBuildStats> users = [];
  bool _disposed = false;

  int get totalSuccess => users.fold(0, (a, u) => a + u.success);
  int get totalFailure => users.fold(0, (a, u) => a + u.failure);
  int get totalQueued => users.fold(0, (a, u) => a + u.queued);
  int get totalRunning => users.fold(0, (a, u) => a + u.running);
  bool get hasActive => users.any((u) => u.active.isNotEmpty);

  Map<String, String> get _headers => {
        'Authorization': 'Bearer $token',
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
      };

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  Future<void> load() async {
    if (loading) return;
    loading = true;
    error = null;
    phase = 'Memuat status build semua pengguna...';
    _notify();
    try {
      await _fetch();
      updatedAt = DateTime.now();
    } catch (e) {
      error = e.toString().replaceFirst('Exception: ', '');
    } finally {
      loading = false;
      phase = '';
      _notify();
    }
  }

  /// Muat ulang ringan (dipanggil berkala saat tab Status dibuka).
  Future<void> refreshActive() async {
    if (loading) return;
    try {
      await _fetch();
      updatedAt = DateTime.now();
      _notify();
    } catch (_) {}
  }

  Future<void> _fetch() async {
    if (!AppConfig.isConfigured) {
      throw Exception('Aplikasi belum dikonfigurasi (config.dart).');
    }
    final names = await UserStore(token).names();
    final uri = Uri.https(
      'api.github.com',
      '/repos/${AppConfig.repoOwner}/${AppConfig.repoName}/actions/runs',
      {'event': 'workflow_dispatch', 'per_page': '100'},
    );
    final res = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 25));
    if (res.statusCode == 404) {
      users = [];
      return;
    }
    if (res.statusCode != 200) throw Exception('Gagal memuat status (HTTP ${res.statusCode}).');

    final runs = ((jsonDecode(res.body) as Map<String, dynamic>)['workflow_runs'] as List?) ?? const [];

    String nameFor(String? branch) {
      final m = RegExp(r'^b-([0-9a-f]{8})-').firstMatch(branch ?? '');
      if (m == null) return 'Lainnya';
      for (final e in names.entries) {
        if (e.key.startsWith(m.group(1)!)) return e.value;
      }
      return 'Pengguna';
    }

    final map = <String, UserBuildStats>{};
    final activeJobs = <MapEntry<UserBuildStats, Map<String, dynamic>>>[];
    totalRepos = runs.length;
    doneRepos = runs.length;

    for (final r in runs) {
      if (r is! Map<String, dynamic>) continue;
      final u = map.putIfAbsent(nameFor(r['head_branch'] as String?), () => UserBuildStats(nameFor(r['head_branch'] as String?)));
      final status = r['status'] as String? ?? '';
      final conclusion = r['conclusion'] as String?;
      if (status == 'in_progress') {
        u.running++;
        activeJobs.add(MapEntry(u, r));
      } else if (status == 'completed') {
        if (conclusion == 'success') {
          u.success++;
        } else if (conclusion == 'failure' || conclusion == 'timed_out') {
          u.failure++;
        }
      } else {
        u.queued++;
        activeJobs.add(MapEntry(u, r));
      }
    }

    for (final u in map.values) {
      u.active = [];
    }
    final api = GitHubActions(token);
    var next = 0;
    final limited = activeJobs.take(15).toList();
    Future<void> worker() async {
      while (true) {
        final i = next++;
        if (i >= limited.length) return;
        final u = limited[i].key;
        final r = limited[i].value;
        final name = (r['name'] ?? 'Build').toString();
        if (r['status'] != 'in_progress') {
          u.active.add(ActiveRun(repo: '', name: name, percent: 0, step: 'Mengantre di GitHub', queued: true));
          continue;
        }
        try {
          final p = await api.progress(AppConfig.repoOwner, AppConfig.repoName, (r['id'] as num).toInt());
          u.active.add(ActiveRun(repo: '', name: name, percent: p.percent, step: p.stepLabel, queued: false));
        } catch (_) {
          u.active.add(ActiveRun(repo: '', name: name, percent: 0, step: 'Berjalan', queued: false));
        }
      }
    }

    await Future.wait(List.generate(3, (_) => worker()));
    users = map.values.where((u) => u.total > 0).toList()..sort((a, b) => b.total.compareTo(a.total));
  }
}
