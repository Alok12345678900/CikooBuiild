import 'package:flutter/material.dart';

import '../services/google_auth_service.dart';
import '../services/storage_service.dart';
import '../theme.dart';
import 'build_progress_view.dart';
import '../config.dart';

/// Cek penyimpanan HP / kartu SD, pilihan lokasi simpan APK, dan penyimpanan cloud (Google Drive).
class StorageCard extends StatefulWidget {
  const StorageCard({super.key});

  @override
  State<StorageCard> createState() => _StorageCardState();
}

class _StorageCardState extends State<StorageCard> {
  List<StorageVolume>? _volumes;
  String _dest = 'phone';
  bool _cloud = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final v = await StorageService.volumes();
    final d = await StorageService.apkDestination();
    final c = await StorageService.cloudAuto();
    if (mounted) {
      setState(() {
        _volumes = v;
        _dest = d;
        _cloud = c;
      });
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  bool get _hasSd => _volumes?.any((v) => v.removable) ?? false;

  Future<void> _setDest(String v) async {
    if (v == 'sdcard' && !_hasSd) {
      _snack('Kartu SD tidak terdeteksi.');
      return;
    }
    await StorageService.setApkDestination(v);
    if (mounted) setState(() => _dest = v);
  }

  Future<void> _connectDrive() async {
    setState(() => _busy = true);
    try {
      final token = await GoogleAuthService.driveToken();
      _snack(token == null ? 'Izin Google Drive ditolak.' : 'Google Drive terhubung.');
    } catch (e) {
      _snack('Gagal menghubungkan Drive: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggleCloud(bool v) async {
    if (v) {
      await _connectDrive();
    }
    await StorageService.setCloudAuto(v);
    if (mounted) setState(() => _cloud = v);
  }

  Widget _volume(StorageVolume v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(v.removable ? Icons.sd_card : Icons.smartphone, size: 18, color: kMuted),
              const SizedBox(width: 8),
              Expanded(child: Text(v.name, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600))),
              Text('${formatBytes(v.free)} bebas dari ${formatBytes(v.total)}',
                  style: const TextStyle(color: kMuted, fontSize: 11)),
            ],
          ),
          const SizedBox(height: 6),
          LinearProgressIndicator(
            value: v.usedFraction,
            color: v.usedFraction > 0.9 ? kRed : kGreen,
            backgroundColor: kBorder,
            minHeight: 6,
            borderRadius: BorderRadius.circular(3),
          ),
        ],
      ),
    );
  }

  Widget _destTile(String value, String title, String subtitle, {bool enabled = true}) {
    final selected = _dest == value;
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      enabled: enabled,
      onTap: enabled ? () => _setDest(value) : null,
      leading: Icon(selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
          color: selected ? kRed : kMuted),
      title: Text(title, style: TextStyle(color: enabled ? Colors.white : kMuted, fontSize: 14)),
      subtitle: Text(subtitle, style: const TextStyle(color: kMuted, fontSize: 11)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
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
            const Text('Penyimpanan HP', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white)),
            const SizedBox(height: 8),
            if (_volumes == null)
              const Padding(padding: EdgeInsets.all(12), child: Center(child: CircularProgressIndicator(color: kRed)))
            else if (_volumes!.isEmpty)
              const Text('Info penyimpanan tidak tersedia.', style: TextStyle(color: kMuted, fontSize: 12))
            else
              for (final v in _volumes!) _volume(v),
            const Divider(color: kBorder, height: 24),
            const Text('Simpan APK di', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white)),
            _destTile('phone', 'Penyimpanan HP', 'Folder aplikasi di memori internal'),
            _destTile('sdcard', 'Kartu SD', _hasSd ? 'Folder aplikasi di kartu SD' : 'Kartu SD tidak terdeteksi',
                enabled: _hasSd),
            _destTile('download', 'Folder Download', 'Salinan otomatis ke Download/${AppConfig.folderName}'),
            const Divider(color: kBorder, height: 24),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _cloud,
              onChanged: _busy ? null : _toggleCloud,
              activeColor: kRed,
              title: const Text('Simpan ke cloud (Google Drive)',
                  style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
              subtitle: const Text('APK hasil build otomatis diunggah ke folder ${AppConfig.folderName} di Drive-mu.',
                  style: TextStyle(color: kMuted, fontSize: 11)),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _busy ? null : _connectDrive,
                icon: const Icon(Icons.cloud_done_outlined, size: 18),
                label: const Text('Hubungkan Google Drive', style: TextStyle(fontSize: 12)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
