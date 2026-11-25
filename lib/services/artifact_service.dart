import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import '../models/build_record.dart';
import 'github_actions.dart';
import 'permission_helper.dart';
import 'storage_service.dart';
import '../config.dart';

/// Mengunduh artifact build dari GitHub (ZIP), mengekstrak APK-nya,
/// lalu menyimpannya di penyimpanan aplikasi supaya bisa langsung diinstal.
class ArtifactService {
  ArtifactService(this.token);

  final String token;

  static const MethodChannel _channel = MethodChannel('ciko/files');

  /// Folder penyimpanan APK sesuai pilihan pengguna (HP atau kartu SD).
  static Future<Directory> buildsDir() async {
    Directory base = await getApplicationSupportDirectory();
    if (await StorageService.apkDestination() == 'sdcard') {
      final sd = await StorageService.sdCardAppDir();
      if (sd != null) base = sd;
    }
    final dir = Directory('${base.path}/builds');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Semua lokasi yang mungkin berisi APK (HP dan kartu SD), untuk pengukuran / pembersihan.
  static Future<List<Directory>> allBuildsDirs() async {
    final out = <Directory>[];
    final base = await getApplicationSupportDirectory();
    out.add(Directory('${base.path}/builds'));
    final sd = await StorageService.sdCardAppDir();
    if (sd != null) out.add(Directory('${sd.path}/builds'));
    return out;
  }

  static String _safe(String s) => s.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');

  ArtifactInfo? _pickArtifact(List<ArtifactInfo> list) {
    final usable = list.where((a) => !a.expired).toList();
    if (usable.isEmpty) return null;
    const hints = ['apk', 'android', 'flutter', 'web2apk', 'release', 'debug', 'build'];
    for (final a in usable) {
      final n = a.name.toLowerCase();
      if (hints.any(n.contains)) return a;
    }
    return usable.first;
  }

  /// Unduh artifact run [rec] → ekstrak APK → kembalikan path APK di perangkat.
  Future<String> downloadApk({
    required BuildRecord rec,
    void Function(double fraction)? onProgress,
  }) async {
    final runId = rec.runId;
    if (runId == null) throw Exception('Run ID build tidak diketahui.');

    final api = GitHubActions(token);
    final artifacts = await api.listArtifacts(rec.owner, rec.repo, runId);
    if (artifacts.isEmpty) {
      throw Exception('Artifact tidak ditemukan. Pastikan workflow mengunggah APK dengan upload-artifact.');
    }
    final artifact = _pickArtifact(artifacts);
    if (artifact == null) {
      throw Exception('Artifact sudah kedaluwarsa di GitHub (masa simpan habis).');
    }

    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(minutes: 10),
    ));

    // 1) Minta lokasi unduhan (302) memakai token. Lokasi tujuan sudah bertanda tangan,
    //    jadi tidak boleh membawa header Authorization saat diunduh.
    final res = await dio.get<dynamic>(
      'https://api.github.com/repos/${rec.owner}/${rec.repo}/actions/artifacts/${artifact.id}/zip',
      options: Options(
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/vnd.github+json',
          'X-GitHub-Api-Version': '2022-11-28',
        },
        followRedirects: false,
        responseType: ResponseType.plain,
        validateStatus: (s) => s != null && s >= 200 && s < 400,
      ),
    );
    final location = res.headers.value('location');
    if (location == null || location.isEmpty) {
      throw Exception('GitHub tidak memberi lokasi unduhan artifact.');
    }

    // 2) Unduh ZIP artifact.
    final tmp = await getTemporaryDirectory();
    final zipFile = File('${tmp.path}/artifact_${_safe(rec.id)}.zip');
    if (await zipFile.exists()) await zipFile.delete();

    await dio.download(
      location,
      zipFile.path,
      onReceiveProgress: (received, total) {
        final t = total > 0 ? total : artifact.sizeBytes;
        if (t > 0 && onProgress != null) {
          onProgress((received / t).clamp(0.0, 1.0));
        }
      },
    );

    // 3) Ekstrak APK dari ZIP.
    try {
      final bytes = await zipFile.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);

      ArchiveFile? best;
      for (final f in archive) {
        if (!f.isFile) continue;
        final lower = f.name.toLowerCase();
        if (!lower.endsWith('.apk')) continue;
        if (lower.contains('androidtest')) continue;
        if (best == null) {
          best = f;
        } else if (best.name.toLowerCase().contains('unsigned') && !lower.contains('unsigned')) {
          best = f;
        }
      }
      if (best == null) {
        throw Exception('Artifact tidak berisi file .apk.');
      }

      final dir = await buildsDir();
      final baseName = best.name.split('/').last;
      final outName = '${_safe(rec.repo)}_${_safe(rec.id)}_${_safe(baseName)}';
      final out = File('${dir.path}/$outName');
      await out.writeAsBytes(best.content as List<int>, flush: true);

      onProgress?.call(1.0);
      return out.path;
    } finally {
      try {
        if (await zipFile.exists()) await zipFile.delete();
      } catch (_) {}
    }
  }

  /// Unduh artifact (ZIP) lalu baca satu file teks di dalamnya tanpa menyimpannya ke disk.
  /// Mengembalikan null bila artifact / file tidak ada.
  Future<String?> fetchTextFile({
    required String owner,
    required String repo,
    required int runId,
    required String artifactNameContains,
    required String fileName,
  }) async {
    final artifacts = await GitHubActions(token).listArtifacts(owner, repo, runId);
    ArtifactInfo? target;
    for (final a in artifacts) {
      if (!a.expired && a.name.contains(artifactNameContains)) target = a;
    }
    if (target == null) return null;

    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(minutes: 2),
    ));
    final res = await dio.get<dynamic>(
      'https://api.github.com/repos/$owner/$repo/actions/artifacts/${target.id}/zip',
      options: Options(
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/vnd.github+json',
          'X-GitHub-Api-Version': '2022-11-28',
        },
        followRedirects: false,
        responseType: ResponseType.plain,
        validateStatus: (s) => s != null && s >= 200 && s < 400,
      ),
    );
    final location = res.headers.value('location');
    if (location == null || location.isEmpty) return null;

    final bin = await dio.get<List<int>>(
      location,
      options: Options(responseType: ResponseType.bytes),
    );
    final bytes = bin.data;
    if (bytes == null) return null;

    final archive = ZipDecoder().decodeBytes(bytes);
    for (final f in archive) {
      if (f.isFile && f.name.split('/').last == fileName) {
        return utf8.decode(f.content as List<int>, allowMalformed: true);
      }
    }
    return null;
  }

  /// Buka installer sistem untuk APK.
  static Future<void> install(String apkPath) async {
    final file = File(apkPath);
    if (!await file.exists()) {
      throw Exception('File APK tidak ditemukan. Unduh ulang dari GitHub.');
    }
    final ok = await PermissionHelper.ensureInstallPackages();
    if (!ok) {
      throw Exception(
        'Izin "Pasang aplikasi tidak dikenal" untuk ${AppConfig.appName} belum diberikan.',
      );
    }
    final result = await OpenFilex.open(
      apkPath,
      type: 'application/vnd.android.package-archive',
    );
    if (result.type != ResultType.done) {
      throw Exception('Gagal membuka installer: ${result.message}');
    }
  }

  /// Salin APK ke folder publik Download/<folderName>.
  static Future<String> saveToDownloads(
    String apkPath,
    String fileName, {
    String mime = 'application/vnd.android.package-archive',
  }) async {
    try {
      final saved = await _channel.invokeMethod<String>('saveToDownloads', {
        'path': apkPath,
        'name': fileName,
        'mime': mime,
        'folder': AppConfig.folderName,
      });
      return saved ?? 'Download/${AppConfig.folderName}/$fileName';
    } on PlatformException catch (e) {
      debugPrint('saveToDownloads error: ${e.message}');
      throw Exception(e.message ?? 'Gagal menyimpan ke Download');
    }
  }
}
