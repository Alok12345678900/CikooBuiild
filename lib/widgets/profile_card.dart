import 'package:flutter/material.dart';

import '../config.dart';
import '../services/session_manager.dart';
import '../services/user_store.dart';
import '../theme.dart';

/// Profil akun Google: nama (bisa diubah), credit, dan check-in harian.
class ProfileCard extends StatefulWidget {
  const ProfileCard({super.key, required this.session});

  final SessionManager session;

  @override
  State<ProfileCard> createState() => _ProfileCardState();
}

class _ProfileCardState extends State<ProfileCard> {
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      await UserStore(AppConfig.githubToken).read(widget.session.userKey);
    } catch (_) {}
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg), backgroundColor: error ? kRed : kCard));
  }

  bool get _checkedToday {
    final t = CreditState.today.value;
    return t.isNotEmpty && CreditState.lastCheckIn.value == t;
  }

  Future<void> _checkIn() async {
    setState(() => _busy = true);
    try {
      final r = await UserStore(AppConfig.githubToken).checkIn(widget.session.userKey);
      _snack('Check-in berhasil! Credit sekarang ${r.credit}.');
    } catch (e) {
      _snack(e.toString().replaceFirst('Exception: ', ''), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _editName() async {
    final ctl = TextEditingController(text: widget.session.displayName);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kCard,
        title: const Text('Ubah nama profil', style: TextStyle(color: Colors.white, fontSize: 16)),
        content: TextField(
          controller: ctl,
          autofocus: true,
          maxLength: 32,
          decoration: const InputDecoration(hintText: 'Nama tampilan'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctl.text.trim()), child: const Text('Simpan')),
        ],
      ),
    );
    ctl.dispose();
    if (name == null || name.isEmpty || name == widget.session.displayName) return;

    setState(() => _busy = true);
    try {
      await UserStore(AppConfig.githubToken).rename(widget.session.userKey, name);
      await widget.session.setDisplayName(name);
      _snack('Nama profil diperbarui.');
    } catch (e) {
      _snack(e.toString().replaceFirst('Exception: ', ''), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    return Card(
      color: kCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: kBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 30,
                  backgroundColor: kBorder,
                  backgroundImage: s.photoUrl.isEmpty ? null : NetworkImage(s.photoUrl),
                  child: s.photoUrl.isEmpty ? const Icon(Icons.person, color: kMuted, size: 30) : null,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(s.displayName,
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 17),
                                overflow: TextOverflow.ellipsis),
                          ),
                          IconButton(
                            tooltip: 'Ubah nama',
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.edit_outlined, size: 18, color: kMuted),
                            onPressed: _busy ? null : _editName,
                          ),
                        ],
                      ),
                      Text(s.email, style: const TextStyle(color: kMuted, fontSize: 12), overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ListenableBuilder(
              listenable: Listenable.merge([CreditState.credit, CreditState.lastCheckIn, CreditState.today]),
              builder: (context, _) {
                final credit = CreditState.credit.value;
                final done = _checkedToday;
                return Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: kGreen.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.bolt, color: kGreen),
                          const SizedBox(width: 6),
                          Text(credit == null ? '...' : '$credit',
                              style: const TextStyle(color: kGreen, fontWeight: FontWeight.bold, fontSize: 20)),
                          const SizedBox(width: 6),
                          const Text('credit', style: TextStyle(color: kGreen, fontSize: 12)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: done ? kBorder : kRed,
                          padding: const EdgeInsets.symmetric(vertical: 13),
                        ),
                        onPressed: (_busy || done) ? null : _checkIn,
                        icon: _busy
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : Icon(done ? Icons.check : Icons.event_available, size: 18),
                        label: Text(done ? 'Sudah check-in hari ini' : 'Check-in harian (+${AppConfig.dailyCheckInCredits})'),
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 8),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('1 build = 1 credit • pengguna baru mendapat 5 credit',
                  style: TextStyle(color: kMuted, fontSize: 11)),
            ),
          ],
        ),
      ),
    );
  }
}
