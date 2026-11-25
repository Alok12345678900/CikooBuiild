import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../services/build_controller.dart';
import '../services/build_starter.dart';
import '../services/github_api_exception.dart';
import '../services/notification_service.dart';
import '../services/session_manager.dart';
import '../services/user_store.dart';
import '../theme.dart';
import '../widgets/build_progress_view.dart';

/// Layar build berbasis ZIP project (Android Studio & Flutter). Repo build ditentukan config.dart.
class BuildZipScreen extends StatefulWidget {
  const BuildZipScreen({
    super.key,
    required this.session,
    required this.controller,
    required this.title,
    required this.typeKey,
    required this.label,
    required this.defaultWorkflowName,
    this.initialZipPath,
  });

  final SessionManager session;
  final BuildController controller;
  final String title;
  final String typeKey;
  final String label;
  final String defaultWorkflowName;
  final String? initialZipPath;

  @override
  State<BuildZipScreen> createState() => _BuildZipScreenState();
}

class _BuildZipScreenState extends State<BuildZipScreen> {
  String? _zipPath;
  bool _busy = false;
  String _buildType = 'release';

  @override
  void initState() {
    super.initState();
    _zipPath = widget.initialZipPath;
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _notifyError(String message) async {
    try {
      await NotificationService.showError(
        title: 'Build Gagal Dimulai ❌',
        body: message.length > 140 ? '${message.substring(0, 140)}...' : message,
      );
    } catch (_) {}
  }

  Future<void> _pickZip() async {
    final res = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['zip']);
    if (res == null || res.files.isEmpty) return;
    setState(() => _zipPath = res.files.first.path);
  }

  Future<void> _start() async {
    if (_zipPath == null) {
      _snack('Pilih file ZIP project ${widget.label}!');
      return;
    }
    if (!widget.controller.canStartNew) {
      _snack(widget.controller.uploading
          ? 'Masih mengunggah, tunggu sampai build dimulai.'
          : 'Maksimal ${BuildController.maxConcurrent} build berjalan bersamaan. Tunggu salah satu selesai.');
      return;
    }

    setState(() => _busy = true);
    try {
      final warning = await BuildStarter.startZipBuild(
        session: widget.session,
        controller: widget.controller,
        type: widget.typeKey,
        zipPath: _zipPath!,
        mode: _buildType,
        label: widget.label,
        workflowName: widget.defaultWorkflowName,
      );
      _snack(warning ?? 'Build ${widget.label} ($_buildType) dimulai! Berjalan di latar belakang.');
      if (mounted) setState(() => _zipPath = null);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: kBg,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: ListenableBuilder(
        listenable: widget.controller,
        builder: (context, _) {
          final display = widget.controller.display;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (display != null) ...[
                BuildProgressView(controller: widget.controller),
                const SizedBox(height: 16),
              ],
              ValueListenableBuilder<int?>(
                valueListenable: CreditState.credit,
                builder: (context, credit, _) => Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: kCard,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: kBorder),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.bolt, color: kGreen),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Credit: ${credit ?? '...'} • 1 build = 1 credit',
                          style: const TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Text('Mode Build', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _chip('🚀 Release', _buildType == 'release', () => setState(() => _buildType = 'release')),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _chip('🐛 Debug', _buildType == 'debug', () => setState(() => _buildType = 'debug')),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const Text('File Project', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 8),
              InkWell(
                onTap: _busy ? null : _pickZip,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: kInputBg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: kBorder),
                  ),
                  child: Column(
                    children: [
                      Icon(Icons.cloud_upload_outlined, size: 40, color: _zipPath != null ? kRed : kMuted),
                      const SizedBox(height: 12),
                      Text(
                        _zipPath != null ? 'ZIP: ${_zipPath!.split('/').last}' : 'Upload ZIP Project ${widget.label}',
                        style: TextStyle(color: _zipPath != null ? Colors.white : kMuted, fontWeight: FontWeight.w600),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(56),
                  backgroundColor: kRed,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: _busy ? null : _start,
                icon: _busy
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.rocket_launch, size: 20),
                label: Text(
                  _busy ? 'Mengunggah... (lihat progress di atas)' : 'Mulai Build ${_buildType == 'release' ? 'Release' : 'Debug'}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
              const SizedBox(height: 24),
            ],
          );
        },
      ),
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
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
