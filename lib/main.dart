import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'nav.dart';
import 'screens/home_shell.dart';
import 'screens/login_screen.dart';
import 'screens/splash_screen.dart';
import 'services/background_update_checker.dart';
import 'services/error_log.dart';
import 'services/build_tracker.dart';
import 'services/notification_service.dart';
import 'services/session_manager.dart';
import 'theme.dart';
import 'config.dart';

void _onNotificationTap(NotificationResponse response) {
  if (response.payload == kPayloadBuildTab) {
    AppNav.tabIndex.value = AppNav.progressTab;
  } else if (response.payload == kPayloadUpdateTab) {
    AppNav.tabIndex.value = AppNav.profileTab;
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Error tampilan / async dicatat, tidak membuat aplikasi force close.
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    ErrorLog.record(details.exception, details.stack);
  };
  ui.PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    ErrorLog.record(error, stack);
    return true;
  };
  ErrorWidget.builder = (FlutterErrorDetails details) {
    ErrorLog.record(details.exception, details.stack);
    return Container(
      padding: const EdgeInsets.all(12),
      color: const Color(0xFF2A1010),
      child: Text(
        'Tampilan ini gagal dimuat:\n${details.exceptionAsString()}',
        style: const TextStyle(color: Colors.white70, fontSize: 11),
      ),
    );
  };
  runApp(const CikoApp());
}

class CikoApp extends StatefulWidget {
  const CikoApp({super.key});

  @override
  State<CikoApp> createState() => _CikoAppState();
}

class _CikoAppState extends State<CikoApp> {
  final ValueNotifier<String> _status = ValueNotifier<String>('Memulai...');
  SessionManager? _session;
  bool _loggedIn = false;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  @override
  void dispose() {
    _status.dispose();
    super.dispose();
  }

  /// Persiapan awal (ditampilkan sebagai splash). Minimal tampil 1,8 detik supaya tidak berkedip.
  Future<void> _boot() async {
    final started = DateTime.now();

    _status.value = 'Memuat pengaturan...';
    await ErrorLog.init();

    _status.value = 'Menyiapkan notifikasi...';
    try {
      await NotificationService.init(onTap: _onNotificationTap);
    } catch (e, st) {
      debugPrint('Notification init skipped: $e\n$st');
    }

    _status.value = 'Menyiapkan layanan latar belakang...';
    try {
      await BuildTracker.configure();
    } catch (e, st) {
      debugPrint('BuildTracker skipped: $e\n$st');
    }
    try {
      await BackgroundUpdateChecker.start();
    } catch (e) {
      debugPrint('Update checker skipped: $e');
    }

    _status.value = 'Memeriksa sesi...';
    final session = await SessionManager.load();
    final isLoggedIn = await session.isLoggedIn;

    try {
      if (await NotificationService.isLaunchedFromBuildNotif()) {
        AppNav.tabIndex.value = AppNav.progressTab;
      }
    } catch (e) {
      debugPrint('Launch details unavailable: $e');
    }

    _status.value = 'Siap';
    final elapsed = DateTime.now().difference(started);
    const minimum = Duration(milliseconds: 1800);
    if (elapsed < minimum) await Future<void>.delayed(minimum - elapsed);
    if (!mounted) return;
    setState(() {
      _session = session;
      _loggedIn = isLoggedIn;
      _ready = true;
    });
  }

  void _handleLogin() => setState(() => _loggedIn = true);

  void _handleLogout() {
    AppNav.tabIndex.value = AppNav.homeTab;
    AppNav.buildType.value = AppNav.buildAndroid;
    setState(() => _loggedIn = false);
  }

  @override
  Widget build(BuildContext context) {
    final Widget page;
    if (!_ready) {
      page = SplashScreen(key: const ValueKey('Splash'), status: _status);
    } else if (_loggedIn) {
      page = HomeShell(
        key: const ValueKey('HomeShell'),
        session: _session!,
        onLogout: _handleLogout,
      );
    } else {
      page = LoginScreen(
        key: const ValueKey('LoginScreen'),
        session: _session!,
        onLoggedIn: _handleLogin,
      );
    }

    return MaterialApp(
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: AnimatedSwitcher(duration: const Duration(milliseconds: 500), child: page),
    );
  }
}
