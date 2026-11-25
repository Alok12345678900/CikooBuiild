import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

/// Deretan ikon kontak (GitHub, WhatsApp, Telegram). Tap ikon langsung membuka URL-nya.
/// Nilai boleh berupa 't.me/xxx' atau 'https://...'.
class ContactIcons extends StatelessWidget {
  const ContactIcons({super.key, this.github, this.whatsapp, this.telegram});

  final String? github;
  final String? whatsapp;
  final String? telegram;

  static String _url(String v) => v.startsWith('http') ? v : 'https://$v';

  Future<void> _open(BuildContext context, String value) async {
    try {
      final ok = await launchUrl(Uri.parse(_url(value)), mode: LaunchMode.externalApplication);
      if (!ok && context.mounted) _fail(context);
    } catch (_) {
      if (context.mounted) _fail(context);
    }
  }

  void _fail(BuildContext context) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Tidak bisa membuka tautan')));
  }

  Widget _btn(BuildContext context, IconData icon, Color color, String tip, String value) {
    return Tooltip(
      message: tip,
      child: InkResponse(
        onTap: () => _open(context, value),
        radius: 26,
        child: Container(
          width: 44,
          height: 44,
          margin: const EdgeInsets.only(left: 10),
          decoration: BoxDecoration(
            color: color.withOpacity(0.14),
            shape: BoxShape.circle,
            border: Border.all(color: color.withOpacity(0.5)),
          ),
          child: Center(child: FaIcon(icon, color: color, size: 20)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (github != null)
          _btn(context, FontAwesomeIcons.github, Colors.white, 'GitHub', github!),
        if (whatsapp != null)
          _btn(context, FontAwesomeIcons.whatsapp, const Color(0xFF25D366), 'WhatsApp', whatsapp!),
        if (telegram != null)
          _btn(context, FontAwesomeIcons.telegram, const Color(0xFF29B6F6), 'Telegram', telegram!),
      ],
    );
  }
}
