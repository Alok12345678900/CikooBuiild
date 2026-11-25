import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import '../config.dart';

class UpdateInfo {
  final String latestVersion;
  final String currentVersion;
  final String downloadUrl;
  final String desk;
  final String publishedAt;
  final bool forceUpdate;

  UpdateInfo({
    required this.latestVersion,
    required this.currentVersion,
    required this.downloadUrl,
    required this.desk,
    required this.publishedAt,
    required this.forceUpdate,
  });

  bool get hasUpdate => _compareVersion(latestVersion, currentVersion) > 0;

  static int _compareVersion(String a, String b) {
    final va = a.replaceAll(RegExp(r'[^0-9.]'), '').split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final vb = b.replaceAll(RegExp(r'[^0-9.]'), '').split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final len = va.length > vb.length ? va.length : vb.length;
    for (var i = 0; i < len; i++) {
      final x = i < va.length ? va[i] : 0;
      final y = i < vb.length ? vb[i] : 0;
      if (x != y) return x.compareTo(y);
    }
    return 0;
  }
}

class UpdateService {
  static const String repoOwner = AppConfig.updateRepoOwner;
  static const String repoName = AppConfig.updateRepoName;
  static const String branch = AppConfig.updateBranch;

  static String get _latestJsonUrl =>
      'https://raw.githubusercontent.com/$repoOwner/$repoName/$branch/latest.json';

  static const Duration _timeout = Duration(seconds: 20);

  static Future<UpdateInfo?> checkUpdate() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;

      final res = await http.get(Uri.parse(_latestJsonUrl)).timeout(_timeout);
      if (res.statusCode != 200) {
        debugPrint('Update: HTTP ${res.statusCode}');
        return null;
      }

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final latestVersion = (data['version'] as String? ?? '').replaceAll('v', '');
      final configuredUrl = (data['downloadUrl'] as String? ??
          data['apkUrl'] as String? ??
          data['url'] as String? ?? '').trim();
      final downloadUrl = await _resolveReleaseApkUrl(configuredUrl);
      final desk = data['desk'] as String? ?? '';
      final publishedAt = data['publishedAt'] as String? ?? '';
      final forceUpdate = data['forceUpdate'] as bool? ?? false;

      if (latestVersion.isEmpty || downloadUrl.isEmpty) return null;

      return UpdateInfo(
        latestVersion: latestVersion,
        currentVersion: currentVersion,
        downloadUrl: downloadUrl,
        desk: desk,
        publishedAt: publishedAt,
        forceUpdate: forceUpdate,
      );
    } catch (e) {
      debugPrint('Update check error: $e');
      return null;
    }
  }

  /// Cocokkan URL dari latest.json dengan asset APK pada GitHub Release terbaru.
  /// Jika URL tidak tersedia/tidak cocok, gunakan asset .apk dari release terbaru.
  /// latest.json tetap menjadi sumber versi, catatan rilis, dan versi minimum.
  static Future<String> _resolveReleaseApkUrl(String configuredUrl) async {
    try {
      final uri = Uri.parse(
        'https://api.github.com/repos/$repoOwner/$repoName/releases/latest',
      );
      final response = await http.get(uri, headers: const {
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
      }).timeout(_timeout);
      if (response.statusCode == 200) {
        final release = jsonDecode(response.body) as Map<String, dynamic>;
        final assets = (release['assets'] as List? ?? const [])
            .whereType<Map>()
            .toList();
        final apkAssets = assets.where((asset) {
          final name = (asset['name'] ?? '').toString().toLowerCase();
          return name.endsWith('.apk');
        }).toList();
        if (apkAssets.isNotEmpty) {
          final configuredName = configuredUrl.isEmpty
              ? ''
              : Uri.tryParse(configuredUrl)?.pathSegments.last.toLowerCase() ?? '';
          final match = apkAssets.where((asset) =>
              (asset['name'] ?? '').toString().toLowerCase() == configuredName);
          final selected = match.isNotEmpty ? match.first : apkAssets.first;
          final releaseUrl = (selected['browser_download_url'] ?? '').toString();
          if (releaseUrl.startsWith('https://')) return releaseUrl;
        }
      }
    } catch (e) {
      debugPrint('Release APK lookup error: $e');
    }
    return configuredUrl;
  }

  /// Auto-download hanya jika koneksi Wi-Fi aktif. Koneksi seluler tidak pernah
  /// memulai unduhan otomatis; pengguna tetap dapat menekan tombol unduh.
  static Future<bool> isWifiConnected() async {
    try {
      final results = await Connectivity().checkConnectivity();
      return results.contains(ConnectivityResult.wifi);
    } catch (e) {
      debugPrint('Connectivity check error: $e');
      return false;
    }
  }

  static Future<File> downloadApk({
    required String url,
    required void Function(int received, int total) onProgress,
  }) async {
    final dir = await getTemporaryDirectory();
    final filePath = '${dir.path}/ciko-update.apk';
    final existing = File(filePath);
    if (await existing.exists()) await existing.delete();
    final dio = Dio();
    await dio.download(url, filePath, onReceiveProgress: onProgress);
    return File(filePath);
  }

  static Future<void> installApk(File apk) async {
    await OpenFilex.open(apk.path);
  }
}