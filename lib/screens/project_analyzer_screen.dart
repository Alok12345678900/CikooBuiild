import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../nav.dart';
import '../services/build_controller.dart';
import '../services/build_starter.dart';
import '../services/github_api_exception.dart';
import '../services/notification_service.dart';
import '../services/session_manager.dart';
import '../theme.dart';
import '../widgets/build_progress_view.dart';

/// Analyzer Project: ZIP dianalisis lewat workflow analyzer.yml di GitHub Actions.
/// Hanya error yang ditampilkan; bila tidak ada error, build dilanjutkan otomatis.
class ProjectAnalyzerScreen extends StatefulWidget {
  const ProjectAnalyzerScreen({super.key, required this.session, required this.controller});

  final SessionManager session;
  final BuildController controller;

  @override
  State<ProjectAnalyzerScreen> createState() => _ProjectAnalyzerScreenState();
}

class _ProjectAnalyzerScreenState extends State<ProjectAnalyzerScreen> {
  String? _zipPath;
  String _mode = 'release';
  bool _deep = false;
  bool _busy = false;

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _pick() async {
    final res = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['zip']);
    if (res == null || res.files.isEmpty) return;
    setState(() => _zipPath = res.files.first.path);
  }

  Future<void> _start() async {
    final zip = _zipPath;
    if (zip == null) {
      _snack('Pilih ZIP project dulu.');
      return;
    }
    if (!widget.controller.canStartNew) {
      _snack(widget.controller.uploading
          ? 'Masih mengunggah, tunggu sampai analisis dimulai.'
          : 'Maksimal ${BuildController.maxConcurrent} proses berjalan bersamaan.');
      return;
    }

    setState(() => _busy = true);
    try {
      final warning = await BuildStarter.startAnalyzer(
        session: widget.session,
        controller: widget.controller,
        zipPath: zip,
        deep: _deep,
        mode: _mode,
      );
      _snack(warning ?? 'Analisis dimulai. Berjalan di latar belakang.');
    } on GitHubApiException catch (e) {
      _snack('Gagal: ${e.message}');
      await _notifyError(e.message);
    } catch (e) {
      final msg = e.toString().replaceFirst('Exception: ', '');
      _snack(msg);
      await _notifyError(msg);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _notifyError(String message) async {
    try {
      await NotificationService.showError(
        title: 'Analisis gagal dimulai ❌',
        body: message.length > 140 ? '${message.substring(0, 140)}...' : message,
      );
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        title: const Text('Analyzer Project'),
        backgroundColor: kBg,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: ListenableBuilder(
        listenable: Listenable.merge([widget.controller, widget.controller.upload]),
        builder: (context, _) {
          final analyzer = widget.controller.latestAnalyzer;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                'ZIP dianalisis lewat workflow analyzer.yml di GitHub Actions (flutter analyze / compile Gradle, '
                'dependency, rahasia tertanam). Hanya error yang ditampilkan. Jika tidak ada error, '
                'build langsung dilanjutkan otomatis.',
                style: TextStyle(color: kMuted, fontSize: 12),
              ),
              const SizedBox(height: 16),
              InkWell(
                onTap: _busy ? null : _pick,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    color: kInputBg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: kBorder),
                  ),
                  child: Column(
                    children: [
                      Icon(Icons.folder_zip_outlined, size: 38, color: _zipPath != null ? kRed : kMuted),
                      const SizedBox(height: 10),
                      Text(
                        _zipPath != null ? _zipPath!.split('/').last : 'Pilih ZIP project',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: _zipPath != null ? Colors.white : kMuted, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text('Mode build setelah lolos', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: _modeChip('🚀 Release', 'release')),
                  const SizedBox(width: 8),
                  Expanded(child: _modeChip('🐛 Debug', 'debug')),
                ],
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _deep,
                onChanged: _busy ? null : (v) => setState(() => _deep = v),
                activeColor: kRed,
                title: const Text('Analisis mendalam',
                    style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                subtitle: const Text('Ditambah build debug penuh (lebih lama).',
                    style: TextStyle(color: kMuted, fontSize: 11)),
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(54),
                  backgroundColor: kRed,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: (_busy || _zipPath == null) ? null : _start,
                icon: _busy
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.fact_check_outlined),
                label: Text(_busy ? 'Mengunggah... (lihat progress di bawah)' : 'Mulai Analisis'),
              ),
              const SizedBox(height: 16),
              if (widget.controller.pending != null)
                BuildProgressView(controller: widget.controller, recordId: 'pending_upload')
              else if (analyzer != null)
                BuildProgressView(controller: widget.controller, recordId: analyzer.id),
              if (analyzer != null && analyzer.isFinished && analyzer.isSuccess)
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(context).popUntil((r) => r.isFirst);
                    AppNav.tabIndex.value = AppNav.progressTab;
                  },
                  icon: const Icon(Icons.timelapse, size: 18),
                  label: const Text('Lihat progress build'),
                ),
              const SizedBox(height: 24),
            ],
          );
        },
      ),
    );
  }

  Widget _modeChip(String label, String value) {
    final selected = _mode == value;
    return GestureDetector(
      onTap: _busy ? null : () => setState(() => _mode = value),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(
          color: selected ? kRed.withOpacity(0.15) : kCard,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: selected ? kRed : kBorder),
        ),
        child: Center(
          child: Text(label,
              style: TextStyle(
                  color: selected ? kRed : kMuted,
                  fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                  fontSize: 14)),
        ),
      ),
    );
  }
}
