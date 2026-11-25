import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Penyimpanan log build lengkap (file teks) di folder aplikasi.
class LogStore {
  static Future<Directory> dir() async {
    final base = await getApplicationSupportDirectory();
    final d = Directory('${base.path}/logs');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  static Future<String> save(String id, String text) async {
    final d = await dir();
    final f = File('${d.path}/${id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_')}.log');
    await f.writeAsString(text, flush: true);
    return f.path;
  }

  static Future<String?> read(String path) async {
    if (path.isEmpty) return null;
    final f = File(path);
    if (!await f.exists()) return null;
    return f.readAsString();
  }
}
