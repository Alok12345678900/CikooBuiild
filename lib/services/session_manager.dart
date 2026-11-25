import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';

/// Sesi pengguna: akun Google. Token GitHub berasal dari config.dart (bukan dari pengguna).
class SessionManager {
  SessionManager._(this._prefs);

  static const String kIsLogin = 'is_login';
  static const String kGoogleId = 'google_id';
  static const String kName = 'google_name';
  static const String kEmail = 'google_email';
  static const String kPhoto = 'google_photo';

  final SharedPreferences _prefs;

  static Future<SessionManager> load() async => SessionManager._(await SharedPreferences.getInstance());

  Future<String> getToken() async => AppConfig.githubToken;

  /// Pemilik repo build (dipakai sebagai "owner" oleh semua layanan GitHub).
  String get username => AppConfig.repoOwner;

  String get googleId => _prefs.getString(kGoogleId) ?? '';
  String get displayName => _prefs.getString(kName) ?? 'Pengguna';
  String get email => _prefs.getString(kEmail) ?? '';
  String get photoUrl => _prefs.getString(kPhoto) ?? '';

  /// Kunci pengguna di user.json: SHA-256 dari ID Google (email tidak disimpan di GitHub).
  String get userKey => googleId.isEmpty ? '' : sha256.convert(utf8.encode(googleId)).toString();

  /// 8 karakter pertama kunci, dipakai pada nama branch build untuk mengenali pemilik build.
  String get keyPrefix => userKey.length >= 8 ? userKey.substring(0, 8) : 'anon0000';

  Future<bool> get isLoggedIn async => (_prefs.getBool(kIsLogin) ?? false) && googleId.isNotEmpty;

  Future<void> saveGoogle({
    required String id,
    required String name,
    required String email,
    String? photo,
  }) async {
    await _prefs.setString(kGoogleId, id);
    await _prefs.setString(kName, name);
    await _prefs.setString(kEmail, email);
    await _prefs.setString(kPhoto, photo ?? '');
    await _prefs.setBool(kIsLogin, true);
  }

  Future<void> setDisplayName(String name) => _prefs.setString(kName, name);

  Future<void> logout() async {
    for (final k in [kIsLogin, kGoogleId, kName, kEmail, kPhoto]) {
      await _prefs.remove(k);
    }
  }
}
