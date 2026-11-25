import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../config.dart';

const String kProgressChannelId = 'build_progress_v3';
const String kDoneChannelId = 'build_done_v3';
const String kErrorChannelId = 'build_error_v3';
const String kUpdateChannelId = 'app_update_v3';
const String kStartChannelId = 'build_start_v3';

const int kProgressNotifId = 888;
const int kDoneNotifId = 889;
const int kErrorNotifId = 890;
const int kUpdateNotifId = 891;
const int kStartNotifId = 892;

const String kPayloadBuildTab = 'tab:build'; // membuka tab Progress
const String kPayloadUpdateTab = 'app:update';

// Ikon launcher selalu ada di APK (dirujuk manifest) sehingga tidak bisa terbuang shrinker.
const String _kIcon = '@mipmap/ic_launcher';

final FlutterLocalNotificationsPlugin notifications = FlutterLocalNotificationsPlugin();

class NotificationService {
  static AndroidFlutterLocalNotificationsPlugin? get _android =>
      notifications.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  /// Dipanggil dari isolate UI (main).
  static Future<void> init({DidReceiveNotificationResponseCallback? onTap}) async {
    const initSettings = InitializationSettings(
      android: AndroidInitializationSettings(_kIcon),
    );

    await notifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: onTap,
    );

    // Hapus channel versi lama.
    for (final old in const [
      'build_progress', 'build_done', 'build_error', 'app_update',
      'build_progress_v2', 'build_done_v2', 'build_error_v2', 'app_update_v2',
    ]) {
      try {
        await _android?.deleteNotificationChannel(old);
      } catch (_) {}
    }

    await ensureChannels();
    await requestPermission();
  }

  /// Dipanggil dari isolate background service. Tidak meminta izin (butuh Activity).
  static Future<void> initBackground() async {
    const initSettings = InitializationSettings(
      android: AndroidInitializationSettings(_kIcon),
    );
    await notifications.initialize(initSettings);
    await ensureChannels();
  }

  /// Membuat semua channel (idempoten). Dipanggil juga sebelum tiap posting, seperti di SKARP,
  /// supaya notifikasi tidak pernah gagal karena channel belum ada (mis. di isolate service).
  static bool _channelsReady = false;

  static Future<void> ensureChannels() async {
    if (_channelsReady) return;
    final a = _android;
    if (a == null) return;
    try {
      // Progress: heads-up saat pertama muncul, update berikutnya senyap.
      await a.createNotificationChannel(const AndroidNotificationChannel(
        kProgressChannelId,
        'Progress Build',
        description: 'Progress build GitHub Actions yang sedang berjalan',
        importance: Importance.high,
        playSound: false,
        enableVibration: false,
        showBadge: false,
      ));
      await a.createNotificationChannel(const AndroidNotificationChannel(
        kStartChannelId,
        'Build Dimulai',
        description: 'Popup saat build dimulai',
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
      ));
      await a.createNotificationChannel(const AndroidNotificationChannel(
        kDoneChannelId,
        'Build Selesai',
        description: 'Popup saat build selesai atau gagal',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
      ));
      await a.createNotificationChannel(const AndroidNotificationChannel(
        kErrorChannelId,
        'Build Error',
        description: 'Popup saat build gagal dimulai atau error',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
      ));
      await a.createNotificationChannel(const AndroidNotificationChannel(
        kUpdateChannelId,
        'Update Aplikasi',
        description: 'Pemberitahuan jika ada versi baru ${AppConfig.appName}',
        importance: Importance.high,
      ));
      _channelsReady = true;
    } catch (_) {}
  }

  /// ID notifikasi hasil yang sama untuk satu build di semua isolate (UI & service),
  /// sehingga tidak muncul dobel, tapi tiap build punya notifikasi sendiri.
  static int idFor(String key) {
    var h = 0;
    for (final c in key.codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    return 2000 + (h % 90000);
  }

  /// Apakah notifikasi diizinkan sistem (izin + tidak diblokir di pengaturan).
  static Future<bool> areEnabled() async {
    try {
      return await _android?.areNotificationsEnabled() ?? true;
    } catch (_) {
      return true;
    }
  }

  static Future<void> requestPermission() async {
    await _android?.requestNotificationsPermission();
  }

  static Future<void> showProgress({
    required String title,
    required String body,
    required int percent,
    required bool indeterminate,
  }) async {
    await ensureChannels();
    return notifications.show(
      kProgressNotifId,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          kProgressChannelId,
          'Progress Build',
          channelDescription: 'Progress build GitHub Actions yang sedang berjalan',
          importance: Importance.high,
          priority: Priority.high,
          ongoing: true,
          autoCancel: false,
          onlyAlertOnce: true,
          showProgress: true,
          maxProgress: 100,
          progress: percent,
          indeterminate: indeterminate,
          playSound: false,
          enableVibration: false,
          icon: _kIcon,
          color: const Color(0xFFFF0000),
          category: AndroidNotificationCategory.progress,
          visibility: NotificationVisibility.public,
          ticker: title,
          styleInformation: BigTextStyleInformation(body),
        ),
      ),
      payload: kPayloadBuildTab,
    );
  }

  /// Progress unduhan APK (memakai ID notif yang sama dengan notifikasi foreground service).
  static Future<void> showDownloadProgress({
    required String title,
    required int percent,
  }) {
    return showProgress(
      title: title,
      body: 'Mengunduh APK... $percent%',
      percent: percent,
      indeterminate: false,
    );
  }

  static Future<void> cancelProgress() => notifications.cancel(kProgressNotifId);

  static Future<void> showStarted({
    required String title,
    required String body,
  }) async {
    await ensureChannels();
    return notifications.show(
      kStartNotifId,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          kStartChannelId,
          'Build Dimulai',
          channelDescription: 'Popup saat build dimulai',
          importance: Importance.high,
          priority: Priority.high,
          autoCancel: true,
          playSound: true,
          enableVibration: true,
          icon: _kIcon,
          color: const Color(0xFFFF0000),
          category: AndroidNotificationCategory.status,
          visibility: NotificationVisibility.public,
          ticker: title,
          styleInformation: BigTextStyleInformation(body),
        ),
      ),
      payload: kPayloadBuildTab,
    );
  }

  static Future<void> showDone({
    required String title,
    required String body,
    String? buildKey,
  }) async {
    await ensureChannels();
    return notifications.show(
      buildKey == null ? kDoneNotifId : idFor('done_$buildKey'),
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          kDoneChannelId,
          'Build Selesai',
          channelDescription: 'Popup saat build selesai atau gagal',
          importance: Importance.max,
          priority: Priority.max,
          autoCancel: true,
          onlyAlertOnce: true,
          playSound: true,
          enableVibration: true,
          icon: _kIcon,
          color: const Color(0xFFFF0000),
          category: AndroidNotificationCategory.status,
          visibility: NotificationVisibility.public,
          ticker: title,
          styleInformation: BigTextStyleInformation(body),
        ),
      ),
      payload: kPayloadBuildTab,
    );
  }

  static Future<void> showError({
    required String title,
    required String body,
    String? buildKey,
  }) async {
    await ensureChannels();
    return notifications.show(
      buildKey == null ? kErrorNotifId : idFor('error_$buildKey'),
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          kErrorChannelId,
          'Build Error',
          channelDescription: 'Popup saat build gagal dimulai atau error',
          importance: Importance.max,
          priority: Priority.max,
          autoCancel: true,
          onlyAlertOnce: true,
          playSound: true,
          enableVibration: true,
          icon: _kIcon,
          color: const Color(0xFFFF0000),
          category: AndroidNotificationCategory.error,
          visibility: NotificationVisibility.public,
          ticker: title,
          styleInformation: BigTextStyleInformation(body),
        ),
      ),
      payload: kPayloadBuildTab,
    );
  }

  static Future<void> showUpdateAvailable({
    required String title,
    required String body,
  }) async {
    await ensureChannels();
    return notifications.show(
      kUpdateNotifId,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          kUpdateChannelId,
          'Update Aplikasi',
          channelDescription: 'Pemberitahuan jika ada versi baru ${AppConfig.appName}',
          importance: Importance.high,
          priority: Priority.high,
          autoCancel: true,
          icon: _kIcon,
          color: Color(0xFF00E676),
          category: AndroidNotificationCategory.recommendation,
        ),
      ),
      payload: kPayloadUpdateTab,
    );
  }

  static Future<bool> isLaunchedFromBuildNotif() async {
    final details = await notifications.getNotificationAppLaunchDetails();
    return (details?.didNotificationLaunchApp ?? false) &&
        details?.notificationResponse?.payload == kPayloadBuildTab;
  }

}
