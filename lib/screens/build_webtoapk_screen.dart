import 'dart:io';

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

class BuildWebToApkScreen extends StatefulWidget {
  const BuildWebToApkScreen({super.key, required this.session, required this.controller});
  final SessionManager session;
  final BuildController controller;

  @override
  State<BuildWebToApkScreen> createState() => _BuildWebToApkScreenState();
}

class _BuildWebToApkScreenState extends State<BuildWebToApkScreen> {
  final _webUrl = TextEditingController();
  final _appName = TextEditingController();
  String? _iconPath;
  String? _token;
  bool _busy = false;
  String _busyText = '';
  String _buildType = 'release';

  static const String _workflowName = 'web2apk.yml';

  @override
  void initState() {
    super.initState();
    _loadToken();
  }

  Future<void> _loadToken() async {
    final t = await widget.session.getToken();
    if (mounted) setState(() => _token = t);
  }

  @override
  void dispose() {
    _webUrl.dispose();
    _appName.dispose();
    super.dispose();
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg),
        backgroundColor: kCard,
        behavior: SnackBarBehavior.floating,
      ));
  }

  Future<void> _notifyError(String message) async {
    await NotificationService.showError(
      title: 'Build Gagal Dimulai ❌',
      body: message.length > 100 ? '${message.substring(0, 100)}...' : message,
    );
  }

  Future<void> _pickIcon() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
    );
    if (res == null || res.files.isEmpty) return;
    final path = res.files.first.path;
    if (path == null) return;
    setState(() => _iconPath = path);
  }

  Future<void> _start() async {
    final webUrl = _webUrl.text.trim();
    final appName = _appName.text.trim();

    if (webUrl.isEmpty || appName.isEmpty) {
      _snack('Lengkapi URL website dan nama aplikasi!');
      return;
    }
    if (_iconPath == null) {
      _snack('Pilih gambar icon aplikasi terlebih dahulu!');
      return;
    }
    if (!widget.controller.canStartNew) {
      _snack(widget.controller.uploading
          ? 'Masih mengunggah, tunggu sampai build dimulai.'
          : 'Maksimal ${BuildController.maxConcurrent} build berjalan bersamaan.');
      return;
    }

    setState(() => _busy = true);
    try {
      final warning = await BuildStarter.startWebToApk(
        session: widget.session,
        controller: widget.controller,
        iconPath: _iconPath!,
        webUrl: webUrl,
        appName: appName,
        mode: _buildType,
      );
      _snack(warning ?? 'Build WebToAPK ($_buildType) dimulai! Berjalan di latar belakang.');
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
        title: const Text('Build WebToAPK'),
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

              const Text('Mode Build', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _buildTypeChip(
                      label: '🚀 Release',
                      selected: _buildType == 'release',
                      onTap: () => setState(() => _buildType = 'release'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildTypeChip(
                      label: '🐛 Debug',
                      selected: _buildType == 'debug',
                      onTap: () => setState(() => _buildType = 'debug'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              const Text('Detail Web', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 8),
              TextField(
                controller: _webUrl,
                decoration: const InputDecoration(
                  labelText: 'URL Website',
                  prefixIcon: Icon(Icons.language),
                  hintText: 'https://example.com',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _appName,
                decoration: const InputDecoration(
                  labelText: 'Nama Aplikasi',
                  prefixIcon: Icon(Icons.apps),
                ),
              ),
              const SizedBox(height: 20),

              const Text('Icon Aplikasi', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 8),
              InkWell(
                onTap: _busy ? null : _pickIcon,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: kInputBg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: kBorder),
                  ),
                  child: Column(
                    children: [
                      if (_iconPath != null) ...[
                        ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: Image.file(
                            File(_iconPath!),
                            width: 100,
                            height: 100,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const Icon(
                              Icons.broken_image,
                              size: 60,
                              color: kMuted,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _iconPath!.split('/').last,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Ketuk untuk ganti icon',
                          style: TextStyle(fontSize: 11, color: kMuted),
                        ),
                      ] else ...[
                        const Icon(Icons.image_outlined, size: 40, color: kMuted),
                        const SizedBox(height: 12),
                        const Text(
                          'Pilih Icon dari Galeri',
                          style: TextStyle(color: kMuted, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Format: PNG / JPG (disarankan 1024x1024)',
                          style: TextStyle(fontSize: 11, color: kMuted),
                        ),
                      ],
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

  Widget _buildTypeChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
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
          child: Text(
            label,
            style: TextStyle(
              color: selected ? kRed : kMuted,
              fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              fontSize: 14,
            ),
          ),
        ),
      ),
    );
  }
}