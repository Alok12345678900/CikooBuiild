import 'package:flutter/material.dart';

import '../services/build_controller.dart';
import '../services/cache_service.dart';
import '../theme.dart';
import 'build_progress_view.dart';

/// Kartu penyimpanan: ukuran cache dan tombol hapus.
class CacheCard extends StatefulWidget {
  const CacheCard({super.key, this.controller});

  final BuildController? controller;

  @override
  State<CacheCard> createState() => _CacheCardState();
}

class _CacheCardState extends State<CacheCard> {
  CacheInfo? _info;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final info = await CacheService.measure();
    if (mounted) setState(() => _info = info);
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<bool> _confirm(String title, String body) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kCard,
        title: Text(title, style: const TextStyle(color: Colors.white, fontSize: 16)),
        content: Text(body, style: const TextStyle(color: kMuted, fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: kRed),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _run(Future<int> Function() job, String label) async {
    if (widget.controller?.isRunning == true || widget.controller?.uploading == true) {
      _snack('Tunggu build / upload selesai sebelum menghapus cache.');
      return;
    }
    setState(() => _busy = true);
    try {
      final freed = await job();
      await widget.controller?.reload();
      await _refresh();
      _snack('$label dihapus (${formatBytes(freed)} dibebaskan)');
    } catch (e) {
      _snack('Gagal menghapus: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clearAll() async {
    if (!await _confirm('Hapus semua cache?',
        'Cache sementara, APK terunduh, dan log build akan dihapus. Riwayat build tetap ada, tetapi APK harus diunduh ulang dari GitHub.')) {
      return;
    }
    await _run(() async {
      final a = await CacheService.clearTemp();
      final b = await CacheService.clearApks();
      final c = await CacheService.clearLogs();
      return a + b + c;
    }, 'Semua cache');
  }

  Widget _row(String title, String subtitle, int bytes, VoidCallback onClear) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(title, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle, style: const TextStyle(color: kMuted, fontSize: 11)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(formatBytes(bytes), style: const TextStyle(color: kGreen, fontSize: 12, fontWeight: FontWeight.bold)),
          IconButton(
            tooltip: 'Hapus',
            icon: const Icon(Icons.delete_outline, color: kRed),
            onPressed: (_busy || bytes == 0) ? null : onClear,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final info = _info;
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
            Row(
              children: [
                const Expanded(
                  child: Text('Penyimpanan & Cache',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white)),
                ),
                if (info != null)
                  Text(formatBytes(info.total), style: const TextStyle(color: kMuted, fontSize: 12)),
              ],
            ),
            const SizedBox(height: 4),
            if (info == null)
              const Padding(
                padding: EdgeInsets.all(12),
                child: Center(child: CircularProgressIndicator(color: kRed)),
              )
            else ...[
              _row('Cache sementara', 'Salinan file pilihan, hasil ZIP customizer, sisa unduhan', info.temp,
                  () => _run(CacheService.clearTemp, 'Cache sementara')),
              _row('APK terunduh', 'Hasil build yang disimpan di aplikasi', info.apks, () async {
                if (await _confirm('Hapus APK terunduh?', 'APK harus diunduh ulang dari GitHub bila dibutuhkan.')) {
                  await _run(CacheService.clearApks, 'APK terunduh');
                }
              }),
              _row('Log build', 'Log lengkap build yang gagal', info.logs,
                  () => _run(CacheService.clearLogs, 'Log build')),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: kRed, padding: const EdgeInsets.symmetric(vertical: 12)),
                  onPressed: (_busy || info.total == 0) ? null : _clearAll,
                  icon: _busy
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.cleaning_services_outlined, size: 18),
                  label: const Text('Hapus semua cache'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
