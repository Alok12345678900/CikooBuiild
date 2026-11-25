import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Mencatat error tak terduga supaya tidak hilang diam-diam. Ditampilkan di tab Progress
/// (bisa disalin) sehingga penyebab crash tampilan mudah dilacak.
class ErrorLog {
  static const String _k = 'last_error_log';

  static final ValueNotifier<String?> last = ValueNotifier<String?>(null);
  static String _lastSeen = '';

  static const MethodChannel _channel = MethodChannel('ciko/files');

  /// true bila crash native terakhir terkait foreground service → mode latar belakang
  /// dimatikan otomatis (pelacak jalan di dalam app).
  static bool autoDisabledService = false;

  static Future<void> init() async {
    try {
      final p = await SharedPreferences.getInstance();
      last.value = p.getString(_k);
    } catch (_) {}

    // Crash native sesi sebelumnya (force close) — dicatat oleh CikoApplication.
    try {
      final crash = await _channel.invokeMethod<String>('getLastCrash');
      if (crash != null && crash.trim().isNotEmpty) {
        final text = 'CRASH NATIVE (sesi sebelumnya)\n$crash';
        last.value = text;
        final p = await SharedPreferences.getInstance();
        await p.setString(_k, text);
        await _channel.invokeMethod<void>('clearLastCrash');

        final lower = crash.toLowerCase();
        if (lower.contains('foregroundservice') ||
            lower.contains('startforeground') ||
            lower.contains('backgroundservice') ||
            lower.contains('flutter_background_service')) {
          await p.setBool('use_bg_service', false);
          autoDisabledService = true;
        }
      }
    } catch (_) {}
  }

  static void record(Object error, StackTrace? stack) {
    final lines = (stack?.toString() ?? '').split('\n').take(10).join('\n');
    final text = '${DateTime.now().toIso8601String()}\n$error\n$lines';
    final key = error.toString();
    if (key == _lastSeen) return; // hindari tulis berulang tiap frame
    _lastSeen = key;
    debugPrint('[ErrorLog] $text');
    // Jangan ubah state saat fase build berlangsung.
    Future<void>.microtask(() async {
      last.value = text;
      try {
        final p = await SharedPreferences.getInstance();
        await p.setString(_k, text);
      } catch (_) {}
    });
  }

  static Future<void> clear() async {
    _lastSeen = '';
    last.value = null;
    try {
      final p = await SharedPreferences.getInstance();
      await p.remove(_k);
    } catch (_) {}
  }
}
