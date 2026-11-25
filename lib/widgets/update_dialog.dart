import 'package:flutter/material.dart';
import '../services/update_service.dart';
import '../theme.dart';

class UpdateDialog extends StatefulWidget {
  final UpdateInfo info;
  final bool autoDownload;
  const UpdateDialog({super.key, required this.info, this.autoDownload = false});

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  bool _autoStarted = false;
  bool _downloading = false;
  double _progress = 0;
  String _status = '';

  @override
  void initState() {
    super.initState();
    if (widget.autoDownload) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_autoStarted) {
          _autoStarted = true;
          _download();
        }
      });
    }
  }

  Future<void> _download() async {
    setState(() {
      _downloading = true;
      _progress = 0;
      _status = 'Mengunduh...';
    });

    try {
      final file = await UpdateService.downloadApk(
        url: widget.info.downloadUrl,
        onProgress: (received, total) {
          if (total > 0) {
            setState(() {
              _progress = received / total;
            });
          }
        },
      );
      if (!mounted) return;
      setState(() => _status = 'Membuka installer...');
      await UpdateService.installApk(file);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _downloading = false;
        _status = 'Gagal: ${e.toString()}';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: kCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Icon(Icons.system_update, color: kRed, size: 24),
          const SizedBox(width: 8),
          const Expanded(
            child: Text('Update Tersedia', style: TextStyle(color: Colors.white, fontSize: 18)),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _row('Versi saat ini', widget.info.currentVersion),
            _row('Versi terbaru', widget.info.latestVersion, highlight: true),
            const SizedBox(height: 12),
            const Text('Catatan rilis:', style: TextStyle(color: kMuted, fontSize: 12)),
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF09090B),
                borderRadius: BorderRadius.circular(8),
              ),
              constraints: const BoxConstraints(maxHeight: 150),
              child: SingleChildScrollView(
                child: Text(
                  widget.info.desk,
                  style: const TextStyle(fontSize: 11, color: kMuted, fontFamily: 'monospace'),
                ),
              ),
            ),
            if (_downloading) ...[
              const SizedBox(height: 16),
              LinearProgressIndicator(
                value: _progress > 0 ? _progress : null,
                color: kRed,
                backgroundColor: const Color(0xFF22222A),
              ),
              const SizedBox(height: 8),
              Text(
                _progress > 0 ? '${(_progress * 100).toStringAsFixed(0)}%' : 'Mengunduh...',
                style: const TextStyle(color: kMuted, fontSize: 12),
              ),
            ],
            if (_status.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(_status, style: const TextStyle(color: kMuted, fontSize: 11)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _downloading ? null : () => Navigator.pop(context),
          child: const Text('Nanti', style: TextStyle(color: kMuted)),
        ),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: kRed),
          onPressed: _downloading ? null : _download,
          icon: _downloading
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.download, size: 18),
          label: Text(_downloading ? 'Mengunduh...' : 'Download & Install'),
        ),
      ],
    );
  }

  Widget _row(String label, String value, {bool highlight = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: kMuted, fontSize: 12)),
          Text(
            value,
            style: TextStyle(
              color: highlight ? kRed : Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}