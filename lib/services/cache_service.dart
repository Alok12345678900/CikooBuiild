import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'artifact_service.dart';
import 'build_store.dart';
import 'log_store.dart';

class CacheInfo {
  const CacheInfo({required this.temp, required this.apks, required this.logs});

  final int temp;
  final int apks;
  final int logs;

  int get total => temp + apks + logs;
}

/// Mengukur dan membersihkan cache: file sementara, APK terunduh, dan log build.
class CacheService {
  static Future<int> _size(Directory d) async {
    var total = 0;
    try {
      if (!await d.exists()) return 0;
      await for (final e in d.list(recursive: true, followLinks: false)) {
        if (e is File) {
          try {
            total += await e.length();
          } catch (_) {}
        }
      }
    } catch (_) {}
    return total;
  }

  static Future<int> _wipe(Directory d) async {
    final before = await _size(d);
    try {
      if (!await d.exists()) return 0;
      await for (final e in d.list(followLinks: false)) {
        try {
          await e.delete(recursive: true);
        } catch (_) {}
      }
    } catch (_) {}
    final after = await _size(d);
    return before > after ? before - after : 0;
  }

  static Future<CacheInfo> measure() async {
    final temp = await getTemporaryDirectory();
    var apks = 0;
    for (final d in await ArtifactService.allBuildsDirs()) {
      apks += await _size(d);
    }
    final logs = await LogStore.dir();
    return CacheInfo(temp: await _size(temp), apks: apks, logs: await _size(logs));
  }

  /// File sementara: salinan file picker, hasil ZIP customizer, sisa unduhan.
  static Future<int> clearTemp() async => _wipe(await getTemporaryDirectory());

  static Future<int> clearLogs() async {
    final freed = await _wipe(await LogStore.dir());
    final list = await BuildStore.loadHistory();
    await BuildStore.saveHistory([for (final r in list) r.logPath.isEmpty ? r : r.copyWith(logPath: '')]);
    return freed;
  }

  static Future<int> clearApks() async {
    var freed = 0;
    for (final d in await ArtifactService.allBuildsDirs()) {
      freed += await _wipe(d);
    }
    final list = await BuildStore.loadHistory();
    await BuildStore.saveHistory([
      for (final r in list)
        (r.apkPath == null || r.apkPath!.isEmpty)
            ? r
            : r.copyWith(
                apkPath: '',
                downloadState: 'none',
                downloadPercent: 0,
                apkLabel: '',
                apkIconPath: '',
                apkSize: 0,
              ),
    ]);
    return freed;
  }
}
