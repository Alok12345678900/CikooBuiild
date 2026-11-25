import 'package:flutter/material.dart';

import '../nav.dart';
import '../services/build_controller.dart';
import '../services/device_info_service.dart';
import '../services/session_manager.dart';
import '../theme.dart';
import 'build_android_screen.dart';
import 'build_flutter_screen.dart';
import 'build_webtoapk_screen.dart';
import '../services/user_store.dart';
import 'project_analyzer_screen.dart';
import 'project_customizer_screen.dart';
import '../config.dart';

class HomeTab extends StatelessWidget {
  const HomeTab({
    super.key,
    required this.session,
    required this.onLogout,
    required this.deviceInfo,
    required this.controller,
  });

  final SessionManager session;
  final VoidCallback onLogout;
  final DeviceInfoService deviceInfo;
  final BuildController controller;

  void _openBuild(BuildContext context, String type) {
    AppNav.buildType.value = type;

    Widget screen;
    switch (type) {
      case AppNav.buildAndroid:
        screen = BuildAndroidScreen(session: session, controller: controller);
        break;
      case AppNav.buildFlutter:
        screen = BuildFlutterScreen(session: session, controller: controller);
        break;
      case AppNav.buildWebToApk:
        screen = BuildWebToApkScreen(session: session, controller: controller);
        break;
      default:
        return;
    }

    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: deviceInfo,
      builder: (context, _) {
        return ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          children: [
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.asset(
                    'assets/images/logo_ciko.jpg',
                    width: 36,
                    height: 36,
                    errorBuilder: (_, __, ___) => const Icon(Icons.android, color: kRed, size: 36),
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    AppConfig.appName,
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: kGreen.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.circle, color: kGreen, size: 8),
                      SizedBox(width: 4),
                      Text('Connected', style: TextStyle(color: kGreen, fontSize: 10, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Keluar',
                  icon: const Icon(Icons.logout, size: 20, color: kMuted),
                  onPressed: onLogout,
                ),
              ],
            ),
            const SizedBox(height: 24),

            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: kCard,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: kBorder, width: 1),
              ),
              child: Row(
                children: [
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFF22222A),
                      border: Border.all(color: kRed.withOpacity(0.3), width: 2),
                    ),
                    child: const Icon(Icons.person, color: kMuted, size: 32),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Selamat Datang!', style: TextStyle(color: kMuted, fontSize: 13)),
                        const SizedBox(height: 4),
                        Text(
                          session.displayName,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.white),
                        ),
                        const SizedBox(height: 4),
                        ValueListenableBuilder<int?>(
                          valueListenable: CreditState.credit,
                          builder: (context, credit, _) => Row(
                            children: [
                              const Icon(Icons.bolt, color: kGreen, size: 14),
                              const SizedBox(width: 4),
                              Text(
                                credit == null ? 'Credit: ...' : 'Credit: $credit',
                                style: const TextStyle(color: kGreen, fontSize: 11, fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: kCard,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: kBorder, width: 1),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Informasi Perangkat', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  const SizedBox(height: 12),
                  _buildInfoRow(Icons.android, 'OS', deviceInfo.androidVersion),
                  const SizedBox(height: 8),
                  _buildInfoRow(Icons.phone_android, 'Device', '${deviceInfo.deviceBrand} ${deviceInfo.deviceModel}'),
                  const Divider(height: 24, color: kBorder),
                  Row(
                    children: [
                      Icon(
                        deviceInfo.isCharging ? Icons.battery_charging_full : Icons.battery_std,
                        color: deviceInfo.batteryLevel <= 20 ? kRed : kGreen,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      const Text('Baterai', style: TextStyle(color: kMuted, fontSize: 13)),
                      const Spacer(),
                      Text(
                        '${deviceInfo.batteryLevel}% ${deviceInfo.isCharging ? '(Charging)' : ''}',
                        style: TextStyle(
                          color: deviceInfo.batteryLevel <= 20 ? kRed : Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            const Text('Pilih Jenis Build', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
            const SizedBox(height: 16),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.1,
              children: [
                _TypeCard(
                  icon: Icons.android,
                  color: kGreen,
                  label: 'Android Studio\nBuild APK',
                  onTap: () => _openBuild(context, AppNav.buildAndroid),
                ),
                _TypeCard(
                  icon: Icons.flutter_dash,
                  color: const Color(0xFF42A5F5),
                  label: 'Flutter\nBuild APK',
                  onTap: () => _openBuild(context, AppNav.buildFlutter),
                ),
                _TypeCard(
                  icon: Icons.language,
                  color: const Color(0xFFAB47BC),
                  label: 'WebToAPK\nBuild APK',
                  onTap: () => _openBuild(context, AppNav.buildWebToApk),
                ),
                _TypeCard(
                  icon: Icons.history,
                  color: kMuted,
                  label: 'Riwayat\nBuild',
                  onTap: () => AppNav.tabIndex.value = AppNav.historyTab,
                ),
              ],
            ),
            const SizedBox(height: 24),

            const Text('Alat Project', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
            const SizedBox(height: 12),
            _ToolCard(
              icon: Icons.fact_check_outlined,
              color: const Color(0xFFFFC107),
              title: 'Analyzer Project',
              subtitle: 'Cek error lewat analyzer.yml; jika lolos, build otomatis dilanjutkan',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => ProjectAnalyzerScreen(session: session, controller: controller)),
              ),
            ),
            const SizedBox(height: 10),
            _ToolCard(
              icon: Icons.auto_fix_high,
              color: kRed,
              title: 'Ganti Icon, Nama & Domain',
              subtitle: 'Ganti icon, nama aplikasi, package, atau rename semua',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ProjectCustomizerScreen(session: session, controller: controller),
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        );
      },
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, color: kMuted, size: 20),
        const SizedBox(width: 8),
        Text(label, style: const TextStyle(color: kMuted, fontSize: 13)),
        const SizedBox(width: 16),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            textAlign: TextAlign.right,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _TypeCard extends StatelessWidget {
  const _TypeCard({
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kBorder, width: 1),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 28),
              ),
              const SizedBox(height: 12),
              Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ToolCard extends StatelessWidget {
  const _ToolCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kBorder, width: 1),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(color: color.withOpacity(0.15), shape: BoxShape.circle),
                  child: Icon(icon, color: color, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                      const SizedBox(height: 2),
                      Text(subtitle, style: const TextStyle(color: kMuted, fontSize: 11)),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: kMuted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
