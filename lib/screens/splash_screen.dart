import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../theme.dart';
import '../config.dart';

/// Layar pembuka saat aplikasi dimulai: logo, nama, progress, dan status persiapan.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, required this.status});

  final ValueListenable<String> status;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _glow = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat(reverse: true);

  String _version = '';

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((p) {
      if (mounted) setState(() => _version = 'v${p.version}');
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _glow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      body: SizedBox.expand(
        child: Stack(
          children: [
            // Logo + nama tepat di tengah layar.
            Center(
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.0, end: 1.0),
                duration: const Duration(milliseconds: 800),
                curve: Curves.easeOutCubic,
                builder: (context, t, child) => Opacity(
                  opacity: t,
                  child: Transform.scale(scale: 0.85 + 0.15 * t, child: child),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    AnimatedBuilder(
                      animation: _glow,
                      builder: (context, child) => Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(30),
                          boxShadow: [
                            BoxShadow(
                              color: kRed.withOpacity(0.15 + 0.25 * _glow.value),
                              blurRadius: 24 + 20 * _glow.value,
                              spreadRadius: 2 + 4 * _glow.value,
                            ),
                          ],
                        ),
                        child: child,
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(28),
                        child: Image.asset('assets/images/logo_ciko.jpg', width: 112, height: 112, fit: BoxFit.cover),
                      ),
                    ),
                    const SizedBox(height: 28),
                    const Text(AppConfig.appName,
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 0.5)),
                    const SizedBox(height: 6),
                    const Text('Build APK via GitHub Actions',
                        textAlign: TextAlign.center, style: TextStyle(color: kMuted, fontSize: 13)),
                  ],
                ),
              ),
            ),
            // Progress, status, dan versi di bagian bawah.
            Align(
              alignment: Alignment.bottomCenter,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 190,
                        child: LinearProgressIndicator(
                          color: kRed,
                          backgroundColor: kBorder,
                          minHeight: 4,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(height: 14),
                      ValueListenableBuilder<String>(
                        valueListenable: widget.status,
                        builder: (context, text, _) => AnimatedSwitcher(
                          duration: const Duration(milliseconds: 250),
                          child: Text(text, key: ValueKey(text), style: const TextStyle(color: kMuted, fontSize: 12)),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(_version, style: const TextStyle(color: kMuted, fontSize: 11)),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
