import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PermissionHelper {
  static Future<void> openSettings() async {
    try {
      await openAppSettings();
    } catch (_) {}
  }

  static const String _kAskedBattery = 'asked_battery_opt';

  /// Android 13+ butuh izin notifikasi runtime. Di bawah itu otomatis granted.
  static Future<bool> ensureNotifications() async {
    try {
      final st = await Permission.notification.status;
      if (st.isGranted) return true;
      final r = await Permission.notification.request();
      return r.isGranted;
    } catch (_) {
      return false;
    }
  }

  /// Minta pengecualian hemat baterai (sekali saja) supaya build tetap dipantau di latar belakang.
  static Future<void> requestBatteryExemptionOnce() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_kAskedBattery) ?? false) return;
      await prefs.setBool(_kAskedBattery, true);
      final st = await Permission.ignoreBatteryOptimizations.status;
      if (!st.isGranted) {
        await Permission.ignoreBatteryOptimizations.request();
      }
    } catch (_) {}
  }

  /// Android 8+: izin "Pasang aplikasi tidak dikenal" untuk aplikasi ini.
  static Future<bool> ensureInstallPackages() async {
    try {
      final st = await Permission.requestInstallPackages.status;
      if (st.isGranted) return true;
      final r = await Permission.requestInstallPackages.request();
      return r.isGranted;
    } catch (_) {
      return false;
    }
  }
}
