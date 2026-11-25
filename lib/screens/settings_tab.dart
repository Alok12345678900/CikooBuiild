import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/build_controller.dart';
import '../services/build_tracker.dart';
import '../widgets/cache_card.dart';
import '../widgets/profile_card.dart';
import '../widgets/storage_card.dart';
import '../services/session_manager.dart';
import '../services/update_service.dart';
import '../theme.dart';
import '../widgets/contact_icons.dart';
import '../widgets/update_dialog.dart';
import '../config.dart';

class SettingsTab extends StatefulWidget {
  const SettingsTab({super.key, required this.session, required this.onLogout, this.controller});
  final SessionManager session;
  final VoidCallback onLogout;

  final BuildController? controller;

  @override
  State<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<SettingsTab> {

  bool _autoUpdateEnabled = true;
  bool _useBgService = true;
  bool _checkingUpdate = false;
  String _currentVersion = '-';
  UpdateInfo? _pendingUpdate;

  static const String _kAutoUpdateKey = 'auto_update_enabled';

  @override
  void initState() {
    super.initState();
    _loadAutoUpdateSetting();
    _loadServiceSetting();
    _loadVersionAndCheck();
  }

  Future<void> _loadServiceSetting() async {
    final v = await BuildTracker.serviceEnabled();
    if (mounted) setState(() => _useBgService = v);
  }

  Future<void> _toggleBgService(bool value) async {
    await BuildTracker.setServiceEnabled(value);
    if (mounted) setState(() => _useBgService = value);
  }

  Future<void> _loadAutoUpdateSetting() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _autoUpdateEnabled = prefs.getBool(_kAutoUpdateKey) ?? true;
    });
  }

  Future<void> _toggleAutoUpdate(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kAutoUpdateKey, value);
    setState(() => _autoUpdateEnabled = value);
  }

  Future<void> _loadVersionAndCheck() async {
    final info = await PackageInfo.fromPlatform();
    setState(() => _currentVersion = info.version);

    if (!_autoUpdateEnabled) return;

    setState(() => _checkingUpdate = true);
    final update = await UpdateService.checkUpdate();
    setState(() {
      _checkingUpdate = false;
      _pendingUpdate = (update != null && update.hasUpdate) ? update : null;
    });

    if (_pendingUpdate != null && mounted) {
      _showUpdateDialog(_pendingUpdate!);
    }
  }

  Future<void> _manualCheckUpdate() async {
    setState(() => _checkingUpdate = true);
    final update = await UpdateService.checkUpdate();
    setState(() => _checkingUpdate = false);

    if (!mounted) return;
    if (update == null) {
      _snack('Gagal cek update. Coba lagi nanti.');
    } else if (!update.hasUpdate) {
      _snack('Aplikasi sudah versi terbaru (v${update.currentVersion})');
    } else {
      _showUpdateDialog(update);
    }
  }

  void _showUpdateDialog(UpdateInfo info) {
    showDialog(
      context: context,
      builder: (_) => UpdateDialog(info: info),
    );
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        backgroundColor: kCard,
      ));
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Profil', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),

        ProfileCard(session: widget.session),
        const SizedBox(height: 20),
        const StorageCard(),
        const SizedBox(height: 20),

        Card(
          color: kCard,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: kBorder),
          ),
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.info_outline, color: kMuted),
                title: const Text('Versi Aplikasi'),
                subtitle: Text(
                  _checkingUpdate ? 'Memeriksa update...' : '${AppConfig.appName} v$_currentVersion',
                ),
                trailing: _checkingUpdate
                    ? const SizedBox(
                        width: 20, height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: kRed),
                      )
                    : IconButton(
                        icon: Icon(
                          _pendingUpdate != null ? Icons.system_update : Icons.refresh,
                          color: _pendingUpdate != null ? kRed : kMuted,
                        ),
                        onPressed: _manualCheckUpdate,
                        tooltip: 'Cek update',
                      ),
              ),
              if (_pendingUpdate != null) ...[
                const Divider(height: 1, color: kBorder),
                ListTile(
                  leading: const Icon(Icons.new_releases, color: kRed),
                  title: const Text('Update Tersedia', style: TextStyle(color: kRed)),
                  subtitle: Text('Versi ${_pendingUpdate!.latestVersion} siap diunduh'),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: kMuted),
                  onTap: () => _showUpdateDialog(_pendingUpdate!),
                ),
              ],
              const Divider(height: 1, color: kBorder),
              SwitchListTile(
                secondary: const Icon(Icons.autorenew, color: kMuted),
                title: const Text('Update Otomatis'),
                subtitle: const Text('Cek update di latar belakang & tampilkan notifikasi'),
                value: _autoUpdateEnabled,
                activeColor: kRed,
                onChanged: _toggleAutoUpdate,
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        CacheCard(controller: widget.controller),
        const SizedBox(height: 20),

        Card(
          color: kCard,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: kBorder),
          ),
          child: SwitchListTile(
            value: _useBgService,
            onChanged: _toggleBgService,
            activeColor: kRed,
            title: const Text(
              'Pelacak build di latar belakang',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
            ),
            subtitle: Text(
              _useBgService
                  ? 'Aktif: build tetap dipantau walau aplikasi ditutup (foreground service).'
                  : 'Mode aman: build dipantau selama aplikasi terbuka. Matikan ini jika aplikasi force close saat build.',
              style: const TextStyle(color: kMuted, fontSize: 11),
            ),
          ),
        ),
        const SizedBox(height: 20),

        Card(
          color: kCard,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: kBorder),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Tim Support',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Ketuk ikon untuk menghubungi',
                  style: TextStyle(fontSize: 11, color: kMuted),
                ),
                const SizedBox(height: 12),
                _teamRow(AppConfig.supportName,
                    telegram: AppConfig.supportTelegramUrl,
                    whatsapp: AppConfig.supportWhatsappUrl,
                    github: AppConfig.supportGithubUrl),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),

        Card(
          color: kCard,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: kBorder),
          ),
          child: const Column(
            children: [
              ListTile(
                leading: Icon(Icons.storage, color: kMuted),
                title: Text('Riwayat Build'),
                subtitle: Text('Disimpan permanen di perangkat'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(50),
            foregroundColor: kRed,
            side: const BorderSide(color: kRed),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onPressed: widget.onLogout,
          icon: const Icon(Icons.logout),
          label: const Text('Keluar dari GitHub', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _teamRow(String name, {String? telegram, String? whatsapp, String? github}) {
    return Row(
      children: [
        Expanded(
          child: Text(
            name,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white),
          ),
        ),
        ContactIcons(github: github, whatsapp: whatsapp, telegram: telegram),
      ],
    );
  }
}
