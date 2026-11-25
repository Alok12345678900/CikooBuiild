import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class StorageVolume {
  const StorageVolume({
    required this.name,
    required this.total,
    required this.free,
    required this.removable,
    required this.path,
  });

  final String name;
  final int total;
  final int free;
  final bool removable;
  final String path;

  int get used => total - free;
  double get usedFraction => total <= 0 ? 0 : (used / total).clamp(0.0, 1.0);
}

/// Info penyimpanan HP / kartu SD dan pilihan lokasi simpan APK.
class StorageService {
  static const MethodChannel _channel = MethodChannel('ciko/files');
  static const String _kDest = 'apk_storage'; // phone | sdcard | download
  static const String _kCloud = 'cloud_auto';

  static Future<List<StorageVolume>> volumes() async {
    try {
      final raw = await _channel.invokeListMethod<Map<dynamic, dynamic>>('getStorageInfo');
      return [
        for (final m in raw ?? const <Map<dynamic, dynamic>>[])
          StorageVolume(
            name: m['name']?.toString() ?? 'Penyimpanan',
            total: (m['total'] as num?)?.toInt() ?? 0,
            free: (m['free'] as num?)?.toInt() ?? 0,
            removable: m['removable'] == true,
            path: m['path']?.toString() ?? '',
          ),
      ];
    } catch (_) {
      return const [];
    }
  }

  static Future<String> apkDestination() async {
    final p = await SharedPreferences.getInstance();
    await p.reload();
    return p.getString(_kDest) ?? 'phone';
  }

  static Future<void> setApkDestination(String v) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kDest, v);
  }

  static Future<bool> cloudAuto() async {
    final p = await SharedPreferences.getInstance();
    await p.reload();
    return p.getBool(_kCloud) ?? false;
  }

  static Future<void> setCloudAuto(bool v) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kCloud, v);
  }

  /// Folder aplikasi di kartu SD (null bila tidak ada kartu SD).
  static Future<Directory?> sdCardAppDir() async {
    try {
      final dirs = await getExternalStorageDirectories();
      if (dirs == null || dirs.length < 2) return null;
      return dirs[1];
    } catch (_) {
      return null;
    }
  }
}
