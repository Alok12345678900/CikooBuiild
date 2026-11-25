import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'google_auth_service.dart';
import '../config.dart';

/// Simpan APK ke Google Drive (folder <folderName>) memakai akun Google yang sedang masuk.
class CloudService {
  static const String _folderName = AppConfig.folderName;

  static Future<String> _folderId(String token) async {
    final headers = {'Authorization': 'Bearer $token'};
    final q = Uri.encodeQueryComponent(
        "name='$_folderName' and mimeType='application/vnd.google-apps.folder' and trashed=false");
    final find = await http
        .get(Uri.parse('https://www.googleapis.com/drive/v3/files?q=$q&fields=files(id)'), headers: headers)
        .timeout(const Duration(seconds: 30));
    if (find.statusCode == 200) {
      final files = (jsonDecode(find.body) as Map<String, dynamic>)['files'] as List?;
      if (files != null && files.isNotEmpty) return (files.first as Map)['id'].toString();
    }
    final create = await http
        .post(
          Uri.parse('https://www.googleapis.com/drive/v3/files?fields=id'),
          headers: {...headers, 'Content-Type': 'application/json'},
          body: jsonEncode({'name': _folderName, 'mimeType': 'application/vnd.google-apps.folder'}),
        )
        .timeout(const Duration(seconds: 30));
    if (create.statusCode != 200) throw Exception('Drive: gagal membuat folder (HTTP ${create.statusCode}).');
    return (jsonDecode(create.body) as Map<String, dynamic>)['id'].toString();
  }

  /// Unggah APK; mengembalikan link Drive.
  static Future<String> uploadApk(String path, String name) async {
    final token = await GoogleAuthService.driveToken();
    if (token == null) {
      throw Exception('Google Drive belum terhubung. Berikan izin Drive di tab Profil.');
    }
    final bytes = await File(path).readAsBytes();
    final folder = await _folderId(token);
    final boundary = 'ciko${DateTime.now().millisecondsSinceEpoch}';
    final meta = jsonEncode({'name': name, 'parents': [folder]});

    final body = BytesBuilder()
      ..add(utf8.encode('--$boundary\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n$meta\r\n'))
      ..add(utf8.encode('--$boundary\r\nContent-Type: application/vnd.android.package-archive\r\n\r\n'))
      ..add(bytes)
      ..add(utf8.encode('\r\n--$boundary--'));

    final res = await http
        .post(
          Uri.parse('https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart&fields=id,webViewLink'),
          headers: {'Authorization': 'Bearer $token', 'Content-Type': 'multipart/related; boundary=$boundary'},
          body: Uint8List.fromList(body.toBytes()),
        )
        .timeout(const Duration(minutes: 10));
    if (res.statusCode != 200) throw Exception('Drive: unggah gagal (HTTP ${res.statusCode}).');
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return data['webViewLink']?.toString() ?? 'https://drive.google.com/';
  }
}
