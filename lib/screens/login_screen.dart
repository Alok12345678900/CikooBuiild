import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../config.dart';
import '../services/google_auth_service.dart';
import '../services/session_manager.dart';
import '../services/user_store.dart';
import '../theme.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.session, required this.onLoggedIn});

  final SessionManager session;
  final VoidCallback onLoggedIn;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  String _status = '';
  bool _busy = false;

  String _friendly(Object e) {
    if (e is PlatformException) {
      final m = '${e.code} ${e.message}';
      if (m.contains('10') || m.contains('12500') || m.contains('sign_in_failed')) {
        return 'Google Sign-In belum dikonfigurasi benar (buat OAuth client Android dengan package '
            'com.ciko.build dan SHA-1 di Google Cloud Console). Detail: ${e.message}';
      }
      if (m.contains('network')) return 'Tidak ada koneksi internet.';
      return e.message ?? e.code;
    }
    return e.toString().replaceFirst('Exception: ', '');
  }

  Future<void> _signIn() async {
    if (!AppConfig.isConfigured) {
      setState(() => _status = 'Aplikasi belum dikonfigurasi: isi token GitHub dan username repo di lib/config.dart.');
      return;
    }
    setState(() {
      _busy = true;
      _status = '';
    });
    try {
      final acc = await GoogleAuthService.signIn();
      if (acc == null) {
        if (mounted) setState(() => _status = 'Masuk dibatalkan.');
        return;
      }
      final name = (acc.displayName ?? '').trim().isNotEmpty ? acc.displayName!.trim() : acc.email.split('@').first;
      await widget.session.saveGoogle(id: acc.id, name: name, email: acc.email, photo: acc.photoUrl);

      if (mounted) setState(() => _status = 'Menyiapkan akun...');
      final rec = await UserStore(AppConfig.githubToken).ensureUser(widget.session.userKey, name);
      if (rec.name != name) await widget.session.setDisplayName(rec.name);

      if (!mounted) return;
      widget.onLoggedIn();
    } catch (e) {
      await widget.session.logout();
      await GoogleAuthService.signOut();
      if (mounted) setState(() => _status = _friendly(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(28),
                  child: Image.asset('assets/images/logo_ciko.jpg', width: 104, height: 104, fit: BoxFit.cover),
                ),
                const SizedBox(height: 24),
                const Text(AppConfig.appName, style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                const Text('Build APK langsung dari HP', style: TextStyle(color: kMuted)),
                const SizedBox(height: 40),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black87,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: _busy ? null : _signIn,
                    icon: _busy
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black54))
                        : const FaIcon(FontAwesomeIcons.google, size: 18, color: Color(0xFFDB4437)),
                    label: const Text('Masuk dengan Google', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  'Pilih akun Google di HP kamu. Pengguna baru mendapat 5 credit gratis.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: kMuted, fontSize: 12),
                ),
                if (_status.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  Text(_status, textAlign: TextAlign.center, style: const TextStyle(color: kRed, fontSize: 12)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
