import 'dart:async';
import 'package:battery_plus/battery_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';

class DeviceInfoService extends ChangeNotifier {
  final Battery _battery = Battery();
  final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();

  int _batteryLevel = 0;
  bool _isCharging = false;
  String _androidVersion = '-';
  String _deviceModel = '-';
  String _deviceBrand = '-';
  StreamSubscription<BatteryState>? _batterySub;
  Timer? _batteryTimer;

  int get batteryLevel => _batteryLevel;
  bool get isCharging => _isCharging;
  String get androidVersion => _androidVersion;
  String get deviceModel => _deviceModel;
  String get deviceBrand => _deviceBrand;

  Future<void> init() async {
    // 1. Ambil info perangkat (Android)
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        final androidInfo = await _deviceInfo.androidInfo;
        _androidVersion = 'Android ${androidInfo.version.release} (API ${androidInfo.version.sdkInt})';
        _deviceModel = androidInfo.model;
        _deviceBrand = androidInfo.brand;
      } else if (defaultTargetPlatform == TargetPlatform.iOS) {
        final iosInfo = await _deviceInfo.iosInfo;
        _androidVersion = 'iOS ${iosInfo.systemVersion}';
        _deviceModel = iosInfo.utsname.machine;
        _deviceBrand = 'Apple';
      } else {
        _androidVersion = 'Unknown OS';
        _deviceModel = 'Unknown Device';
        _deviceBrand = '-';
      }
    } catch (e) {
      _androidVersion = 'Gagal baca OS';
      _deviceModel = 'Gagal baca device';
    }

    // 2. Ambil level baterai awal
    try {
      _batteryLevel = await _battery.batteryLevel;
      final state = await _battery.batteryState;
      _isCharging = state == BatteryState.charging || state == BatteryState.full;
    } catch (e) {
      _batteryLevel = 0;
      _isCharging = false;
    }

    // 3. Pantau perubahan status baterai secara real-time
    _batterySub = _battery.onBatteryStateChanged.listen((state) async {
      try {
        _batteryLevel = await _battery.batteryLevel;
        _isCharging = state == BatteryState.charging || state == BatteryState.full;
        notifyListeners();
      } catch (_) {}
    });

    // 4. Pantau perubahan level baterai secara berkala
    _batteryTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      try {
        final newLevel = await _battery.batteryLevel;
        if (newLevel != _batteryLevel) {
          _batteryLevel = newLevel;
          notifyListeners();
        }
      } catch (_) {}
    });

    notifyListeners();
  }

  @override
  void dispose() {
    _batterySub?.cancel();
    _batteryTimer?.cancel();
    super.dispose();
  }
}