# CIKO BUILD

Aplikasi Android (Flutter) untuk membangun APK lewat GitHub Actions langsung dari HP.

## Fitur
- Login GitHub, pilih repository, upload ZIP project (Android Studio / Flutter) atau buat APK dari website (WebToAPK).
- Workflow bawaan di `assets/workflows/`, atau upload file `.yml` sendiri (kecuali WebToAPK). ZIP disimpan sebagai `project.zip`.
- Hingga 3 build berjalan bersamaan (satu repository satu build), dipantau di latar belakang dengan notifikasi popup.
- Tab Progress: upload dan build menyatu dalam satu kartu, log live bergaya terminal, job/step/durasi; unduh dan install APK langsung dari aplikasi.
- Riwayat: build berhasil menampilkan icon, nama aplikasi, package, versi, dan ukuran APK; build gagal menyimpan log lengkap yang bisa dibuka di terminal.
- Pengaturan: Penyimpanan & Cache (hapus cache sementara, APK terunduh, log build).
- Splash screen saat aplikasi dimulai.
- Status: statistik dan progress build semua pengguna (repository publik).
- Analyzer Project: ZIP dianalisis lewat workflow `analyzer.yml` di GitHub Actions dengan progress seperti build (latar belakang + notifikasi popup). Hanya error yang ditampilkan; bila tidak ada error, build dilanjutkan otomatis.
- Ganti Icon / Nama / Package / Rename Semua. Domain dipisah per `https://` dan `http://` (cari di semua file, ganti satu per satu atau semuanya sekaligus).
- Pembaruan aplikasi dibaca dari `latest.json` dan APK pada GitHub Release.

## Build
```
flutter pub get
flutter build apk --release --split-per-abi --target-platform android-arm,android-arm64
```
Workflow CI: `.github/workflows/build.yml`. Pastikan folder `android/app/src/main/kotlin` ikut ter-ZIP
(berisi `MainActivity` dan `CikoApplication` yang dirujuk manifest).

## Catatan
- Token GitHub tidak disimpan di source code.
- Hanya repository publik (dan repository sendiri) yang tampil di Status.

## Konfigurasi v2.0 (WAJIB sebelum build)

1. **`lib/config.dart`**: isi `githubToken`, `repoOwner`, dan `repoName`. Repo dibuat otomatis (privat) bila belum ada.
   Token fine-grained disarankan, hanya untuk repo itu (Contents + Actions: read/write). Token di dalam APK bisa diekstrak siapa pun.
   Lebih aman: `flutter build apk --dart-define=GITHUB_TOKEN=... --dart-define=REPO_OWNER=...`.
2. **Masuk dengan Google**: di Google Cloud Console buat OAuth client tipe *Android* dengan package `com.ciko.build`
   dan SHA-1 keystore yang dipakai menandatangani APK. Untuk Google Drive aktifkan *Google Drive API*.
3. Data pengguna disimpan di `user.json` pada repo itu: nama, credit, tanggal check-in terakhir (kunci = hash ID Google).
   Pengguna baru 5 credit, check-in harian +1, satu build = 1 credit.
4. Setiap build memakai branch sendiri (`b-<kunci>-<waktu>`), jadi banyak pengguna bisa build bersamaan; branch dihapus saat build selesai.
