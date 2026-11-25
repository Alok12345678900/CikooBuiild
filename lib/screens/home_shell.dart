import 'package:flutter/material.dart';
import '../services/update_service.dart';
import '../widgets/update_dialog.dart';

import '../nav.dart';
import '../services/build_controller.dart';
import '../services/device_info_service.dart';
import '../config.dart';
import '../services/google_auth_service.dart';
import '../services/user_store.dart';
import '../services/notification_service.dart';
import '../services/permission_helper.dart';
import '../services/session_manager.dart';
import '../theme.dart';
import 'history_tab.dart';
import 'home_tab.dart';
import 'progress_tab.dart';
import 'settings_tab.dart';
import 'status_tab.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.session, required this.onLogout});
  final SessionManager session;
  final VoidCallback onLogout;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  late final BuildController _controller;
  final DeviceInfoService _deviceInfo = DeviceInfoService();
  bool _updatePromptShown = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = BuildController(session: widget.session);
    _controller.init();
    _deviceInfo.init();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _validateSession();
      _checkNotifications();
      _checkAppUpdate();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    _deviceInfo.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _controller.reload();
      _checkAppUpdate();
    }
  }

  /// Popup notifikasi butuh izin (Android 13+) dan channel tidak diblokir. Kalau belum,
  /// arahkan pengguna ke pengaturan aplikasi.
  Future<void> _checkNotifications() async {
    final granted = await PermissionHelper.ensureNotifications();
    final enabled = await NotificationService.areEnabled();
    if ((granted && enabled) || !mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        duration: const Duration(seconds: 10),
        backgroundColor: kCard,
        behavior: SnackBarBehavior.floating,
        content: const Text('Notifikasi dimatikan. Aktifkan agar popup build muncul di HP.'),
        action: SnackBarAction(
          label: 'Pengaturan',
          textColor: kRed,
          onPressed: PermissionHelper.openSettings,
        ),
      ));
  }

  Future<void> _checkAppUpdate() async {
    if (_updatePromptShown || !mounted) return;
    final info = await UpdateService.checkUpdate();
    if (!mounted || info == null || !info.hasUpdate) return;
    _updatePromptShown = true;
    final wifi = await UpdateService.isWifiConnected();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: !info.forceUpdate,
      builder: (_) => UpdateDialog(info: info, autoDownload: wifi),
    );
  }

  Future<void> _logout() async {
    await GoogleAuthService.signOut();
    CreditState.clear();
    await widget.session.logout();
    widget.onLogout();
  }

  /// Sesi = akun Google di HP. Kalau akunnya sudah tidak ada, minta masuk lagi.
  Future<void> _validateSession() async {
    try {
      final acc = await GoogleAuthService.silent();
      if (acc == null) {
        await _logout();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Sesi Google berakhir, silakan masuk lagi.'), backgroundColor: kRed),
          );
        }
        return;
      }
    } catch (_) {
      // offline: pertahankan sesi
    }
    try {
      await UserStore(AppConfig.githubToken).read(widget.session.userKey);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: AppNav.tabIndex,
      builder: (context, index, _) {
        return Scaffold(
          body: SafeArea(
            child: IndexedStack(
              index: index,
              children: [
                HomeTab(
                  session: widget.session,
                  onLogout: _logout,
                  deviceInfo: _deviceInfo,
                  controller: _controller,
                ),
                ProgressTab(controller: _controller),
                StatusTab(session: widget.session),
                HistoryTab(controller: _controller),
                SettingsTab(session: widget.session, onLogout: _logout, controller: _controller),
              ],
            ),
          ),
          bottomNavigationBar: ListenableBuilder(
            listenable: _controller,
            builder: (context, _) {
              return NavigationBar(
                selectedIndex: index,
                onDestinationSelected: (i) => AppNav.tabIndex.value = i,
                backgroundColor: kCard,
                indicatorColor: kRed.withOpacity(0.15),
                elevation: 0,
                height: 70,
                destinations: [
                  const NavigationDestination(
                    icon: Icon(Icons.home_outlined, color: kMuted),
                    selectedIcon: Icon(Icons.home, color: kRed),
                    label: 'Beranda',
                  ),
                  NavigationDestination(
                    icon: Badge(
                      isLabelVisible: _controller.isRunning,
                      backgroundColor: kRed,
                      child: const Icon(Icons.timelapse, color: kMuted),
                    ),
                    selectedIcon: Badge(
                      isLabelVisible: _controller.isRunning,
                      backgroundColor: kRed,
                      child: const Icon(Icons.timelapse, color: kRed),
                    ),
                    label: 'Progress',
                  ),
                  const NavigationDestination(
                    icon: Icon(Icons.dashboard_outlined, color: kMuted),
                    selectedIcon: Icon(Icons.dashboard, color: kRed),
                    label: 'Status',
                  ),
                  const NavigationDestination(
                    icon: Icon(Icons.history, color: kMuted),
                    selectedIcon: Icon(Icons.history, color: kRed),
                    label: 'Riwayat',
                  ),
                  NavigationDestination(
                    icon: const Icon(Icons.person_outline, color: kMuted),
                    selectedIcon: const Icon(Icons.person, color: kRed),
                    label: 'Profil',
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}