import 'dart:async';

import 'package:flutter/foundation.dart';

import 'notification_service.dart';
import 'update_service.dart';
import '../config.dart';

class BackgroundUpdateChecker {
  static Timer? _timer;

  static Future<void> start({Duration interval = const Duration(hours: 6)}) async {
    _checkNow();
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) => _checkNow());
  }

  static Future<void> _checkNow() async {
    try {
      final info = await UpdateService.checkUpdate();
      if (info == null || !info.hasUpdate) return;

      await NotificationService.showUpdateAvailable(
        title: '🚀 Update Tersedia (v${info.latestVersion})',
        body: 'Versi baru ${AppConfig.appName} sudah tersedia. Ketuk untuk update.',
      );
    } catch (e) {
      debugPrint('Background update check error: $e');
    }
  }
}
