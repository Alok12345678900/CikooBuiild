import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'github_api_exception.dart';

class RunInfo {
  const RunInfo(this.id, this.htmlUrl);
  final int id;
  final String? htmlUrl;
}

class ArtifactInfo {
  const ArtifactInfo({
    required this.id,
    required this.name,
    required this.sizeBytes,
    required this.expired,
  });
  final int id;
  final String name;
  final int sizeBytes;
  final bool expired;
}

class BuildProgress {
  const BuildProgress({
    required this.status,
    required this.conclusion,
    required this.htmlUrl,
    required this.done,
    required this.total,
    required this.current,
    this.diagnostics = const [],
    this.jobs = const [],
    this.runNumber,
    this.branch,
    this.sha,
    this.actor,
  });

  final String status;
  final String? conclusion;
  final String? htmlUrl;
  final int done;
  final int total;
  final String current;
  final List<String> diagnostics;
  final List<Map<String, dynamic>> jobs;
  final int? runNumber;
  final String? branch;
  final String? sha;
  final String? actor;

  bool get finished => status == 'completed';

  String get finalStatus {
    if (conclusion == 'success') return 'success';
    if (conclusion == 'cancelled') return 'cancelled';
    return 'failure';
  }

  int get percent {
    if (finished) return 100;
    if (total == 0) return 0;
    return (done * 100 ~/ total).clamp(0, 99);
  }

  String get stepLabel {
    if (status == 'queued') return 'Mengantre di GitHub...';
    if (total == 0) return 'Menyiapkan runner...';
    final name = current.isEmpty ? 'Menyelesaikan' : current;
    return '$name ($done/$total)';
  }

  /// ID job yang sedang berjalan (kalau ada).
  int? get runningJobId {
    for (final j in jobs) {
      if (j['status'] == 'in_progress') return (j['id'] as num?)?.toInt();
    }
    return null;
  }

  /// ID job pertama yang gagal (kalau ada).
  int? get failedJobId {
    for (final j in jobs) {
      if (j['conclusion'] == 'failure') return (j['id'] as num?)?.toInt();
    }
    return null;
  }
}

class GitHubActions {
  GitHubActions(this.token);

  final String token;

  static const Duration _timeout = Duration(seconds: 20);

  Map<String, String> get _headers => {
        'Authorization': 'Bearer $token',
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
      };

  Uri _u(String owner, String repo, String path, [Map<String, String>? query]) =>
      Uri.https('api.github.com', '/repos/$owner/$repo$path', query);

  dynamic _ok(http.Response r, [String? what]) {
    if (r.statusCode >= 200 && r.statusCode < 300) {
      return r.body.isEmpty ? <String, dynamic>{} : jsonDecode(r.body);
    }
    var msg = r.reasonPhrase ?? '';
    try {
      msg = (jsonDecode(r.body) as Map<String, dynamic>)['message'] as String? ?? msg;
    } catch (_) {}
    throw GitHubApiException(r.statusCode, what != null ? '$what: $msg' : msg);
  }

  static int? _ms(dynamic v) {
    if (v is String) return DateTime.tryParse(v)?.millisecondsSinceEpoch;
    return null;
  }

  Future<void> triggerWorkflow(
    String owner,
    String repo,
    String workflow,
    String branch, {
    Map<String, String> inputs = const {},
  }) async {
    final body = <String, dynamic>{'ref': branch};
    if (inputs.isNotEmpty) body['inputs'] = inputs;

    GitHubApiException? last;
    for (var i = 0; i < 4; i++) {
      try {
        final res = await http
            .post(
              _u(owner, repo, '/actions/workflows/$workflow/dispatches'),
              headers: {..._headers, 'Content-Type': 'application/json'},
              body: jsonEncode(body),
            )
            .timeout(_timeout);

        if (res.statusCode == 204 || res.statusCode == 200) return;
        _ok(res, 'Gagal memicu workflow');
      } on GitHubApiException catch (e) {
        last = e;
        if (e.statusCode != 404 && e.statusCode != 422) rethrow;
      } catch (e) {
        last = GitHubApiException(0, 'Koneksi gagal: $e');
      }
      await Future<void>.delayed(const Duration(seconds: 3));
    }
    throw last ?? GitHubApiException(0, 'Gagal memicu workflow');
  }

  Future<int> latestRunId(String owner, String repo, String workflow) async {
    try {
      final r = await http.get(
        _u(owner, repo, '/actions/workflows/$workflow/runs',
            {'event': 'workflow_dispatch', 'per_page': '1'}),
        headers: _headers,
      ).timeout(_timeout);

      if (r.statusCode != 200) {
        debugPrint('latestRunId: HTTP ${r.statusCode}');
        return 0;
      }

      final body = _ok(r) as Map<String, dynamic>;
      final runs = (body['workflow_runs'] as List).cast<Map<String, dynamic>>();
      if (runs.isEmpty) return 0;
      return (runs.first['id'] as num).toInt();
    } catch (e) {
      debugPrint('latestRunId error: $e');
      return 0;
    }
  }

  Future<RunInfo?> findRun(
    String owner,
    String repo,
    String workflow,
    int baseline,
  ) async {
    final r = await http
        .get(
          _u(owner, repo, '/actions/workflows/$workflow/runs',
              {'event': 'workflow_dispatch', 'per_page': '10'}),
          headers: _headers,
        )
        .timeout(_timeout);

    final body = _ok(r) as Map<String, dynamic>;
    final runs = (body['workflow_runs'] as List).cast<Map<String, dynamic>>();

    RunInfo? best;
    for (final m in runs) {
      final id = (m['id'] as num).toInt();
      if (id > baseline && (best == null || id < best.id)) {
        best = RunInfo(id, m['html_url'] as String?);
      }
    }
    return best;
  }

  /// Run milik branch build tertentu (satu branch = satu build).
  Future<RunInfo?> findRunByBranch(String owner, String repo, String workflow, String branch) async {
    final r = await http
        .get(
          _u(owner, repo, '/actions/workflows/$workflow/runs',
              {'branch': branch, 'event': 'workflow_dispatch', 'per_page': '5'}),
          headers: _headers,
        )
        .timeout(_timeout);
    final body = _ok(r) as Map<String, dynamic>;
    final runs = (body['workflow_runs'] as List).cast<Map<String, dynamic>>();
    if (runs.isEmpty) return null;
    return RunInfo((runs.first['id'] as num).toInt(), runs.first['html_url'] as String?);
  }

  Future<void> deleteBranch(String owner, String repo, String branch) async {
    final res = await http
        .delete(_u(owner, repo, '/git/refs/heads/$branch'), headers: _headers)
        .timeout(_timeout);
    if (res.statusCode == 204 || res.statusCode == 404 || res.statusCode == 422) return;
    _ok(res, 'Gagal menghapus branch');
  }

  Future<void> triggerWorkflowWithInputs(
    String owner,
    String repo,
    String workflow,
    String branch,
    Map<String, String> inputs,
  ) async {
    await triggerWorkflow(owner, repo, workflow, branch, inputs: inputs);
  }

  Future<bool> waitForWorkflowReady(
    String owner,
    String repo,
    String workflow, {
    int maxRetries = 12,
  }) async {
    for (var i = 0; i < maxRetries; i++) {
      try {
        final res = await http.get(
          _u(owner, repo, '/actions/workflows/$workflow'),
          headers: _headers,
        ).timeout(_timeout);

        if (res.statusCode == 200) {
          debugPrint('Workflow $workflow siap (percobaan ${i + 1})');
          return true;
        }
        debugPrint('Workflow belum siap (percobaan ${i + 1}/$maxRetries): ${res.statusCode}');
      } catch (e) {
        debugPrint('Error cek workflow: $e');
      }
      await Future<void>.delayed(const Duration(seconds: 5));
    }
    return false;
  }

  /// Progress lengkap: status run, semua job, semua step (dengan waktu mulai/selesai).
  Future<BuildProgress> progress(String owner, String repo, int runId) async {
    final runJson = _ok(
      await http
          .get(_u(owner, repo, '/actions/runs/$runId'), headers: _headers)
          .timeout(_timeout),
    ) as Map<String, dynamic>;

    final status = runJson['status'] as String? ?? 'queued';
    var total = 0;
    var done = 0;
    var current = '';
    final diagnostics = <String>[];
    final jobsOut = <Map<String, dynamic>>[];

    if (status != 'queued') {
      final jobsJson = _ok(
        await http
            .get(
              _u(owner, repo, '/actions/runs/$runId/jobs', {'per_page': '30'}),
              headers: _headers,
            )
            .timeout(_timeout),
      ) as Map<String, dynamic>;

      for (final job in (jobsJson['jobs'] as List).cast<Map<String, dynamic>>()) {
        final jobName = job['name'] as String? ?? 'Job';
        final jobConclusion = job['conclusion'] as String?;

        if (jobConclusion == 'failure' || jobConclusion == 'cancelled') {
          diagnostics.add(
            'JOB GAGAL: $jobName (${(jobConclusion ?? 'unknown').toUpperCase()})',
          );
          final jobUrl = job['html_url'] as String?;
          if (jobUrl != null) diagnostics.add('Detail job: $jobUrl');
        }

        final stepsOut = <Map<String, dynamic>>[];
        for (final step
            in ((job['steps'] as List?) ?? const []).cast<Map<String, dynamic>>()) {
          total++;
          final st = step['status'] as String?;
          if (st == 'completed') {
            done++;
            if (step['conclusion'] == 'failure') {
              diagnostics.add('STEP ERROR: $jobName / ${step['name'] ?? 'Step'}');
            }
          } else if (st == 'in_progress' && current.isEmpty) {
            current = step['name'] as String? ?? '';
          }
          stepsOut.add({
            'n': (step['number'] as num?)?.toInt() ?? total,
            'name': step['name'] as String? ?? 'Step',
            'status': st ?? 'queued',
            'conclusion': step['conclusion'] as String?,
            'start': _ms(step['started_at']),
            'end': _ms(step['completed_at']),
          });
        }

        jobsOut.add({
          'id': (job['id'] as num?)?.toInt(),
          'name': jobName,
          'status': job['status'] as String? ?? 'queued',
          'conclusion': jobConclusion,
          'start': _ms(job['started_at']),
          'end': _ms(job['completed_at']),
          'runner': job['runner_name'] as String?,
          'url': job['html_url'] as String?,
          'steps': stepsOut,
        });
      }
    }

    final sha = runJson['head_sha'] as String?;
    final actorMap = runJson['actor'];

    return BuildProgress(
      status: status,
      conclusion: runJson['conclusion'] as String?,
      htmlUrl: runJson['html_url'] as String?,
      done: done,
      total: total,
      current: current,
      diagnostics: diagnostics,
      jobs: jobsOut,
      runNumber: (runJson['run_number'] as num?)?.toInt(),
      branch: runJson['head_branch'] as String?,
      sha: (sha != null && sha.length >= 7) ? sha.substring(0, 7) : sha,
      actor: actorMap is Map ? actorMap['login'] as String? : null,
    );
  }

  Future<void> cancelRun(String owner, String repo, int runId) async {
    final res = await http
        .post(
          _u(owner, repo, '/actions/runs/$runId/cancel'),
          headers: _headers,
        )
        .timeout(_timeout);

    if (res.statusCode == 202) return;
    _ok(res, 'Gagal membatalkan build');
  }

  static final RegExp _ansi = RegExp(r'\x1B\[[0-9;?]*[A-Za-z]');
  static final RegExp _timestamp =
      RegExp(r'^\uFEFF?\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?Z ?', multiLine: true);

  /// Ambil bagian akhir log sebuah job (teks bersih, tanpa timestamp/warna ANSI).
  /// Mengembalikan string kosong kalau log belum tersedia.
  Future<String> jobLogTail(
    String owner,
    String repo,
    int jobId, {
    int maxBytes = 24000,
  }) async {
    final client = http.Client();
    try {
      final req = http.Request('GET', _u(owner, repo, '/actions/jobs/$jobId/logs'))
        ..followRedirects = false
        ..headers.addAll(_headers);
      final streamed = await client.send(req).timeout(_timeout);
      final location = streamed.headers['location'];
      final code = streamed.statusCode;
      await streamed.stream.drain<void>();

      if (code < 300 || code >= 400 || location == null || location.isEmpty) {
        return '';
      }

      // Lokasi redirect = URL bertanda tangan (tanpa header Authorization).
      final r = await http
          .get(Uri.parse(location), headers: {'Range': 'bytes=-$maxBytes'})
          .timeout(const Duration(seconds: 30));
      if (r.statusCode != 200 && r.statusCode != 206) return '';

      var bytes = r.bodyBytes;
      var partial = r.statusCode == 206;
      if (bytes.length > maxBytes) {
        bytes = bytes.sublist(bytes.length - maxBytes);
        partial = true;
      }
      var text = utf8.decode(bytes, allowMalformed: true);
      if (partial) {
        final nl = text.indexOf('\n');
        if (nl >= 0 && nl < text.length - 1) text = text.substring(nl + 1);
      }
      text = text.replaceAll(_ansi, '').replaceAll(_timestamp, '');
      return text.trimRight();
    } catch (e) {
      debugPrint('jobLogTail error: $e');
      return '';
    } finally {
      client.close();
    }
  }

  /// Daftar artifact dari sebuah run.
  Future<List<ArtifactInfo>> listArtifacts(String owner, String repo, int runId) async {
    final res = await http
        .get(
          _u(owner, repo, '/actions/runs/$runId/artifacts', {'per_page': '30'}),
          headers: _headers,
        )
        .timeout(_timeout);
    final data = _ok(res, 'Gagal mengambil artifact') as Map<String, dynamic>;
    final list = (data['artifacts'] as List?) ?? const [];
    return list.map((e) {
      final m = e as Map<String, dynamic>;
      return ArtifactInfo(
        id: (m['id'] as num).toInt(),
        name: m['name'] as String? ?? 'artifact',
        sizeBytes: (m['size_in_bytes'] as num?)?.toInt() ?? 0,
        expired: m['expired'] as bool? ?? false,
      );
    }).toList();
  }
}
