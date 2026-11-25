import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../config.dart';
import 'github_api_exception.dart';

/// (nama file, fraksi 0..1, byte terkirim, byte total body)
typedef UploadProgressCallback = void Function(String file, double fraction, int sent, int total);

class GitHubUploader {
  GitHubUploader(this.token, this.owner, this.repo);

  final String token;
  final String owner;
  final String repo;

  static const Duration _timeout = Duration(seconds: 30);

  Map<String, String> get _headers => {
        'Authorization': 'Bearer $token',
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
        'Content-Type': 'application/json',
      };

  Uri _u(String path) => Uri.https('api.github.com', '/repos/$owner/$repo$path');

  Map<String, dynamic> _ok(http.Response r, String what) {
    if (r.statusCode >= 200 && r.statusCode < 300) {
      if (r.body.isEmpty) return <String, dynamic>{};
      return jsonDecode(r.body) as Map<String, dynamic>;
    }
    var msg = r.reasonPhrase ?? '';
    try {
      msg = (jsonDecode(r.body) as Map<String, dynamic>)['message'] as String? ?? msg;
    } catch (_) {}
    throw GitHubApiException(r.statusCode, '$what: $msg');
  }

  Future<bool> ensureRepoExists() async {
    final check = await http.get(_u(''), headers: _headers).timeout(_timeout);

    if (check.statusCode == 200) {
      debugPrint('Repo $owner/$repo sudah ada');
      return false;
    }

    if (check.statusCode != 404) {
      var msg = check.reasonPhrase ?? '';
      try {
        msg = (jsonDecode(check.body) as Map<String, dynamic>)['message'] as String? ?? msg;
      } catch (_) {}
      throw GitHubApiException(check.statusCode, 'Gagal cek repo: $msg');
    }

    debugPrint('Membuat repo baru: $owner/$repo');
    final res = await http.post(
      Uri.parse('https://api.github.com/user/repos'),
      headers: _headers,
      body: jsonEncode({
        'name': repo,
        'auto_init': true,
        'private': AppConfig.repoPrivate,
        'description': '${AppConfig.appName} - auto generated',
      }),
    ).timeout(_timeout);

    if (res.statusCode != 201) {
      var msg = res.reasonPhrase ?? '';
      try {
        msg = (jsonDecode(res.body) as Map<String, dynamic>)['message'] as String? ?? msg;
      } catch (_) {}
      throw GitHubApiException(res.statusCode, 'Gagal buat repo: $msg');
    }

    debugPrint('Repo dibuat. Menunggu 5 detik...');
    await Future<void>.delayed(const Duration(seconds: 5));

    for (var i = 0; i < 5; i++) {
      try {
        final verify = await http.get(_u(''), headers: _headers).timeout(_timeout);
        if (verify.statusCode == 200) {
          debugPrint('Repo siap digunakan');
          return true;
        }
      } catch (_) {}
      await Future<void>.delayed(const Duration(seconds: 2));
    }

    return true;
  }

  static bool _workflowsOk = false;

  /// Pastikan file workflow ada (dan terbaru) di branch default. workflow_dispatch hanya bisa
  /// memicu workflow yang ada di branch default, jadi ini dilakukan sekali per sesi aplikasi.
  Future<void> ensureWorkflows(Map<String, String> files) async {
    if (_workflowsOk) return;
    for (final e in files.entries) {
      final path = '.github/workflows/${e.key}';
      for (var attempt = 0; attempt < 4; attempt++) {
        final cur = await http.get(_u('/contents/$path'), headers: _headers).timeout(_timeout);
        String? sha;
        if (cur.statusCode == 200) {
          final body = jsonDecode(cur.body) as Map<String, dynamic>;
          sha = body['sha'] as String?;
          final existing = utf8.decode(base64.decode((body['content'] as String).replaceAll('\n', '')));
          if (existing == e.value) break;
        } else if (cur.statusCode != 404) {
          throw GitHubApiException(cur.statusCode, 'Gagal memeriksa workflow ${e.key}');
        }
        final put = await http
            .put(
              _u('/contents/$path'),
              headers: _headers,
              body: jsonEncode({
                'message': '${AppConfig.appName}: sinkron workflow ${e.key}',
                'content': base64Encode(utf8.encode(e.value)),
                if (sha != null) 'sha': sha,
              }),
            )
            .timeout(_timeout);
        if (put.statusCode == 200 || put.statusCode == 201) break;
        if (put.statusCode == 409 || put.statusCode == 422) {
          await Future<void>.delayed(Duration(milliseconds: 500 * (attempt + 1)));
          continue;
        }
        _ok(put, 'Gagal menyimpan workflow ${e.key}');
      }
    }
    _workflowsOk = true;
  }

  /// Buat branch baru khusus satu build berisi project.zip. Branch terpisah membuat banyak
  /// pengguna bisa build bersamaan tanpa saling menimpa.
  Future<String> uploadZipToBranch({
    required String zipPath,
    required String branch,
    UploadProgressCallback? onFileProgress,
    VoidCallback? onFilesDone,
  }) {
    return _uploadInternal(
      {'project.zip': zipPath},
      '${AppConfig.appName}: project.zip ($branch)',
      onFileProgress: onFileProgress,
      onFilesDone: onFilesDone,
      newBranch: branch,
    );
  }

  /// WebToAPK: branch build berisi icon.png.
  Future<String> uploadIconToBranch({
    required String iconPath,
    required String branch,
    UploadProgressCallback? onFileProgress,
    VoidCallback? onFilesDone,
  }) {
    return _uploadInternal(
      {'icon.png': iconPath},
      '${AppConfig.appName}: icon.png ($branch)',
      onFileProgress: onFileProgress,
      onFilesDone: onFilesDone,
      newBranch: branch,
    );
  }

  static const String _blobPrefix = '{"content":"';
  static const String _blobSuffix = '","encoding":"base64"}';

  /// Body JSON blob dialirkan per potongan (base64 per 192 KB) → hemat RAM dan
  /// progress kirim akurat. Potongan kelipatan 3 byte agar padding base64 hanya di akhir.
  Stream<List<int>> _blobBody(File file) async* {
    yield ascii.encode(_blobPrefix);
    final raf = await file.open();
    try {
      const chunk = 3 * 64 * 1024;
      while (true) {
        final b = BytesBuilder(copy: false);
        while (b.length < chunk) {
          final d = await raf.read(chunk - b.length);
          if (d.isEmpty) break;
          b.add(d);
        }
        if (b.isEmpty) break;
        final bytes = b.takeBytes();
        yield ascii.encode(base64Encode(bytes));
        if (bytes.length < chunk) break;
      }
    } finally {
      await raf.close();
    }
    yield ascii.encode(_blobSuffix);
  }

  Future<String> _uploadBinaryBlob(
    String name,
    File file,
    UploadProgressCallback? onProgress,
  ) async {
    final n = await file.length();
    final b64Len = 4 * ((n + 2) ~/ 3);
    final total = _blobPrefix.length + b64Len + _blobSuffix.length;

    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      sendTimeout: const Duration(minutes: 20),
      receiveTimeout: const Duration(minutes: 5),
    ));

    final headers = Map<String, dynamic>.from(_headers)..remove('Content-Type');
    headers[Headers.contentLengthHeader] = total;

    try {
      final res = await dio.post<dynamic>(
        'https://api.github.com/repos/$owner/$repo/git/blobs',
        data: _blobBody(file),
        options: Options(
          headers: headers,
          contentType: Headers.jsonContentType,
          responseType: ResponseType.json,
          validateStatus: (_) => true,
        ),
        onSendProgress: (sent, _) {
          onProgress?.call(name, (sent / total).clamp(0.0, 1.0), sent, total);
        },
      );

      final code = res.statusCode ?? 0;
      final data = res.data;
      if (code == 201 && data is Map && data['sha'] is String) {
        onProgress?.call(name, 1.0, total, total);
        return data['sha'] as String;
      }
      var msg = '';
      if (data is Map && data['message'] != null) msg = data['message'].toString();
      throw GitHubApiException(code, 'Gagal upload $name: ${msg.isEmpty ? 'HTTP $code' : msg}');
    } on DioException catch (e) {
      throw GitHubApiException(0, 'Koneksi putus saat upload $name: ${e.message ?? e.type.name}');
    }
  }

  Future<String> _uploadInternal(
    Map<String, String> files,
    String commitMessage, {
    Map<String, String> textFiles = const {},
    UploadProgressCallback? onFileProgress,
    VoidCallback? onFilesDone,
    String? newBranch,
  }) async {
    final repoInfo = _ok(
      await http.get(_u(''), headers: _headers).timeout(_timeout),
      'Repo tidak ditemukan',
    );
    final branch = repoInfo['default_branch'] as String? ?? 'main';

    final http.Response refRes =
        await http.get(_u('/git/refs/heads/$branch'), headers: _headers).timeout(_timeout);
    if (refRes.statusCode == 404 || refRes.statusCode == 409) {
      throw GitHubApiException(
        refRes.statusCode,
        'Repository masih kosong (belum ada commit). Buat 1 commit dulu, mis. tambah README.',
      );
    }
    final ref = _ok(refRes, 'Gagal ambil commit HEAD');
    final headSha = (ref['object'] as Map<String, dynamic>)['sha'] as String;

    final headCommit = _ok(
      await http.get(_u('/git/commits/$headSha'), headers: _headers).timeout(_timeout),
      'Gagal ambil commit',
    );
    final baseTreeSha = (headCommit['tree'] as Map<String, dynamic>)['sha'] as String;

    final tree = <Map<String, String>>[];

    // File biner (ZIP, icon) — dengan progress byte.
    for (final entry in files.entries) {
      final file = File(entry.value);
      if (!await file.exists()) {
        throw GitHubApiException(404, 'File tidak ditemukan: ${entry.value}');
      }
      final length = await file.length();
      if (length > 100 * 1024 * 1024) {
        throw GitHubApiException(413, 'File ${entry.key} melebihi 100MB (batas GitHub)');
      }
      final sha = await _uploadBinaryBlob(entry.key, file, onFileProgress);
      tree.add({'path': entry.key, 'mode': '100644', 'type': 'blob', 'sha': sha});
    }

    onFilesDone?.call();

    // File teks (workflow .yml)
    for (final entry in textFiles.entries) {
      final blob = _ok(
        await http.post(
          _u('/git/blobs'),
          headers: _headers,
          body: jsonEncode({'content': entry.value, 'encoding': 'utf-8'}),
        ).timeout(_timeout),
        'Gagal upload ${entry.key}',
      );
      tree.add({'path': entry.key, 'mode': '100644', 'type': 'blob', 'sha': blob['sha'] as String});
    }

    final newTree = _ok(
      await http.post(
        _u('/git/trees'),
        headers: _headers,
        body: jsonEncode({'base_tree': baseTreeSha, 'tree': tree}),
      ).timeout(_timeout),
      'Gagal membuat tree',
    );

    final newCommit = _ok(
      await http.post(
        _u('/git/commits'),
        headers: _headers,
        body: jsonEncode({
          'message': commitMessage,
          'tree': newTree['sha'],
          'parents': [headSha],
        }),
      ).timeout(_timeout),
      'Gagal membuat commit',
    );

    if (newBranch != null) {
      _ok(
        await http.post(
          _u('/git/refs'),
          headers: _headers,
          body: jsonEncode({'ref': 'refs/heads/$newBranch', 'sha': newCommit['sha']}),
        ).timeout(_timeout),
        'Gagal membuat branch build',
      );
      return newBranch;
    }

    _ok(
      await http.patch(
        _u('/git/refs/heads/$branch'),
        headers: _headers,
        body: jsonEncode({'sha': newCommit['sha'], 'force': false}),
      ).timeout(_timeout),
      'Gagal push ke repository',
    );

    return branch;
  }
}
