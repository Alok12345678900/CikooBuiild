import 'package:google_sign_in/google_sign_in.dart';

import '../config.dart';

/// Masuk dengan Google: memilih akun Google yang sudah ada di HP.
class GoogleAuthService {
  static const String driveScope = 'https://www.googleapis.com/auth/drive.file';

  static final GoogleSignIn _gs = GoogleSignIn(
    scopes: const ['email', 'profile'],
    serverClientId: AppConfig.googleServerClientId.isEmpty ? null : AppConfig.googleServerClientId,
  );

  static Future<GoogleSignInAccount?> signIn() => _gs.signIn();

  /// Pulihkan sesi tanpa dialog. Mengembalikan null bila belum / tidak lagi masuk.
  static Future<GoogleSignInAccount?> silent() => _gs.signInSilently();

  static Future<void> signOut() async {
    try {
      await _gs.signOut();
    } catch (_) {}
  }

  /// Access token Google Drive (meminta izin Drive bila belum diberikan).
  static Future<String?> driveToken() async {
    final acc = _gs.currentUser ?? await _gs.signInSilently();
    if (acc == null) return null;
    final granted = await _gs.requestScopes([driveScope]);
    if (!granted) return null;
    final auth = await acc.authentication;
    return auth.accessToken;
  }
}
