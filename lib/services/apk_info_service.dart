import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';

import 'artifact_service.dart';

class ApkInfo {
  const ApkInfo({this.label = '', this.package = '', this.version = '', this.iconPath = ''});

  final String label;
  final String package;
  final String version;
  final String iconPath;
}

/// Membaca nama aplikasi, package, versi, dan icon dari file APK (lewat PackageManager Android).
class ApkInfoService {
  static const MethodChannel _channel = MethodChannel('ciko/files');

  static Future<ApkInfo> read(String apkPath, String id) async {
    try {
      final m = await _channel.invokeMapMethod<String, dynamic>('readApkInfo', {'path': apkPath});
      if (m == null) return const ApkInfo();

      var iconPath = '';
      final icon = m['icon'];
      if (icon is Uint8List && icon.isNotEmpty) {
        final dir = await ArtifactService.buildsDir();
        final f = File('${dir.path}/${id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_')}_icon.png');
        await f.writeAsBytes(icon, flush: true);
        iconPath = f.path;
      }

      final vName = m['versionName']?.toString() ?? '';
      final vCode = m['versionCode']?.toString() ?? '';
      return ApkInfo(
        label: m['label']?.toString() ?? '',
        package: m['package']?.toString() ?? '',
        version: vName.isEmpty ? (vCode.isEmpty ? '' : vCode) : (vCode.isEmpty ? vName : '$vName ($vCode)'),
        iconPath: iconPath,
      );
    } catch (_) {
      return const ApkInfo();
    }
  }
}
