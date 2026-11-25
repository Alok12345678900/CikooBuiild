// =====================================================================
//  KONFIGURASI APLIKASI  —  semua yang perlu di-rename ada di file ini
// =====================================================================
//
//  Cara rename cepat:
//   1. Ubah nilai di bagian "1. IDENTITAS APP" dan "2. KONTAK SUPPORT".
//   2. Ubah akun GitHub di bagian "3. BACKEND GITHUB".
//   3. Isi token lewat --dart-define (JANGAN ditulis di file ini), lihat bagian 3.
//
//  Yang TIDAK bisa diatur dari sini (ada di luar kode Dart):
//   - Nama yang tampil di HP / launcher : android/app/src/main/AndroidManifest.xml
//                                          (android:label="...")
//   - Package / applicationId           : android/app/build.gradle (namespace & applicationId)
//                                          + nama folder android/app/src/main/kotlin/...
//                                          + baris `package` di MainActivity.kt & CikoApplication.kt
//   - Nama project pubspec              : pubspec.yaml (name & description)
//   - Logo & ikon launcher              : assets/images/logo_ciko.jpg
//                                          + android/app/src/main/res/mipmap-* & drawable-nodpi
//   - Keystore penandatangan APK        : ciko-release.jks (alias, password di android/app/build.gradle)

class AppConfig {
  AppConfig._();

  // -------------------------------------------------------------------
  // 1. IDENTITAS APP
  // -------------------------------------------------------------------

  /// Nama app yang tampil di splash, login, beranda, notifikasi, dan pesan-pesan di dalam app.
  static const String appName = 'CIKO BUILD';

  /// Nama folder hasil build di Download HP dan di Google Drive.
  /// (Download/<folderName>/nama.apk).
  static const String folderName = 'CikoBuild';

  // -------------------------------------------------------------------
  // 2. KONTAK SUPPORT  (kartu "Tim Support" di tab Pengaturan)
  // -------------------------------------------------------------------
  // Isi cukup username / nomor, tidak perlu link lengkap.

  /// Nama yang tampil di kartu Tim Support.
  static const String supportName = 'CIKO';

  /// Username GitHub (tanpa @).
  static const String supportGithub = 'cikobug';

  /// Username Telegram (tanpa @).
  static const String supportTelegram = 'cikobug';

  /// Nomor WhatsApp, format internasional tanpa + atau spasi (62 = Indonesia).
  static const String supportWhatsapp = '6281226749903';

  /// Link siap pakai untuk ikon kontak. Jangan diubah, ikut nilai di atas.
  static const String supportGithubUrl = 'github.com/$supportGithub';
  static const String supportTelegramUrl = 't.me/$supportTelegram';
  static const String supportWhatsappUrl = 'wa.me/$supportWhatsapp';

  // -------------------------------------------------------------------
  // 3. BACKEND GITHUB
  // -------------------------------------------------------------------
  // Semua build berjalan di GitHub Actions milik akun di bawah ini.
  //
  // TOKEN: dipakai semua pengguna app, jadi buat token fine-grained yang HANYA punya
  // akses ke repo data di bawah (Contents + Actions: read/write), bukan token akun utama.
  // Token yang ditanam di APK bisa diekstrak siapa saja, jadi jangan tulis di sini dan
  // jangan commit. Masukkan saat build:
  //
  //   flutter build apk --dart-define=GITHUB_TOKEN=ghp_xxx
  //
  // (opsional: --dart-define=REPO_OWNER=akun --dart-define=REPO_NAME=repo)

  /// Token GitHub. Dibaca dari --dart-define=GITHUB_TOKEN, sengaja dikosongkan di kode.
  static const String githubToken = String.fromEnvironment('GITHUB_TOKEN', defaultValue: '');

  /// Akun GitHub (username / organisasi) pemilik repo backend.
  static const String repoOwner = String.fromEnvironment('REPO_OWNER', defaultValue: 'cikobug');

  /// Repo tempat semua build berjalan + menyimpan ZIP project dan data pengguna.
  /// Dibuat otomatis oleh app bila belum ada. Sebaiknya privat.
  static const String repoName = String.fromEnvironment('REPO_NAME', defaultValue: 'ciko-build-data');
  static const bool repoPrivate = true;

  /// File data pengguna di dalam repo (nama + credit + tanggal check-in terakhir).
  static const String usersFile = 'user.json';

  // -------------------------------------------------------------------
  // 4. UPDATE APP
  // -------------------------------------------------------------------
  // App mengecek https://raw.githubusercontent.com/<owner>/<repo>/<branch>/latest.json
  // Repo ini harus PUBLIK dan dibuat manual.

  static const String updateRepoOwner = repoOwner;
  static const String updateRepoName = 'ciko-build-update';
  static const String updateBranch = 'main';

  // -------------------------------------------------------------------
  // 5. CREDIT
  // -------------------------------------------------------------------

  /// Credit awal pengguna baru.
  static const int startCredits = 5;

  /// Credit gratis tiap check-in harian.
  static const int dailyCheckInCredits = 1;

  /// Credit yang terpakai untuk satu kali build.
  static const int buildCost = 1;

  // -------------------------------------------------------------------
  // 6. LOGIN GOOGLE (opsional)
  // -------------------------------------------------------------------

  /// Web client ID OAuth Google untuk google_sign_in. Kosongkan bila tidak dipakai.
  /// Isi lewat --dart-define=GOOGLE_SERVER_CLIENT_ID=xxx
  static const String googleServerClientId =
      String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID', defaultValue: '');

  // -------------------------------------------------------------------

  /// True bila token & owner sudah terisi (login akan ditolak kalau false).
  static bool get isConfigured =>
      !githubToken.startsWith('ISI_') && !repoOwner.startsWith('ISI_') && githubToken.isNotEmpty;
}
