import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../nav.dart';
import '../services/artifact_service.dart';
import '../services/build_controller.dart';
import '../services/icon_generator.dart';
import '../services/project_customizer.dart';
import '../services/session_manager.dart';
import '../theme.dart';
import 'build_android_screen.dart';
import 'build_flutter_screen.dart';

/// Ganti icon, nama aplikasi, domain/package, atau semuanya sekaligus pada ZIP project.
class ProjectCustomizerScreen extends StatefulWidget {
  const ProjectCustomizerScreen({super.key, required this.session, required this.controller});

  final SessionManager session;
  final BuildController controller;

  @override
  State<ProjectCustomizerScreen> createState() => _ProjectCustomizerScreenState();
}

class _ProjectCustomizerScreenState extends State<ProjectCustomizerScreen> {
  final _name = TextEditingController();
  final _pkg = TextEditingController();
  final _domainFilter = TextEditingController();

  String? _zipPath;
  String? _iconPath;
  Map<dynamic, dynamic>? _scan;
  bool _scanning = false;
  bool _busy = false;
  String? _error;

  bool _doName = false;
  bool _doPkg = false;
  bool _doIcon = false;
  bool _doProject = false;
  bool _doDomain = false;

  List<Map<dynamic, dynamic>>? _domains;
  final Map<String, String> _domainMap = {};
  bool _scanningDomains = false;
  bool _showProtected = false;
  String _schemeFilter = 'all';

  String? _outPath;
  List<String> _changes = [];

  @override
  void dispose() {
    _name.dispose();
    _pkg.dispose();
    _domainFilter.dispose();
    super.dispose();
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg), backgroundColor: error ? kRed : kCard));
  }

  Future<void> _pickZip() async {
    final res = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['zip']);
    if (res == null || res.files.isEmpty || res.files.first.path == null) return;
    final path = res.files.first.path!;
    setState(() {
      _zipPath = path;
      _scan = null;
      _scanning = true;
      _outPath = null;
      _changes = [];
      _error = null;
      _domains = null;
      _domainMap.clear();
      _doDomain = false;
    });
    try {
      final scan = await runScanInIsolate(path);
      if (!mounted) return;
      setState(() {
        _scan = scan;
        if (_name.text.isEmpty && scan['label'] != null) _name.text = scan['label'].toString();
        if (_pkg.text.isEmpty) {
          final id = scan['appId'] ?? scan['namespace'];
          if (id != null) _pkg.text = id.toString();
        }
      });
    } catch (e) {
      if (mounted) setState(() => _error = 'ZIP tidak bisa dibaca: $e');
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _findDomains() async {
    final zip = _zipPath;
    if (zip == null) return;
    setState(() => _scanningDomains = true);
    try {
      final raw = await runDomainScanInIsolate(zip);
      if (!mounted) return;
      setState(() => _domains = raw.whereType<Map>().toList());
    } catch (e) {
      if (mounted) setState(() => _error = 'Gagal mencari domain: $e');
    } finally {
      if (mounted) setState(() => _scanningDomains = false);
    }
  }

  Future<String?> _askDomain({required String title, required String info}) async {
    final ctl = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kCard,
        title: Text(title, style: const TextStyle(color: Colors.white, fontSize: 15)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(info, style: const TextStyle(color: kMuted, fontSize: 12)),
            const SizedBox(height: 12),
            TextField(
              controller: ctl,
              autofocus: true,
              autocorrect: false,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(hintText: 'domain.baru'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, ''), child: const Text('Hapus')),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctl.text.trim()), child: const Text('Simpan')),
        ],
      ),
    );
    ctl.dispose();
    return result;
  }

  Future<void> _editDomain(String key) async {
    final result = await _askDomain(
      title: key,
      info: 'Diganti hanya pada URL dengan skema dan domain yang sama persis, di semua file. '
          'Tulis domain baru; skema lama dipertahankan. Tulis https://domain.baru untuk sekaligus mengganti skema.',
    );
    if (result == null) return;
    setState(() {
      if (result.isEmpty) {
        _domainMap.remove(key);
      } else {
        _domainMap[key] = result;
      }
      _doDomain = _domainMap.isNotEmpty;
    });
  }

  /// Rename semua domain sekaligus untuk skema tertentu (https / http / semua), memakai filter yang aktif.
  Future<void> _bulk(String scheme) async {
    final all = _domains;
    if (all == null) return;
    final q = _domainFilter.text.trim().toLowerCase();
    final targets = all
        .where((d) =>
            d['protected'] != true &&
            (scheme == 'all' || d['scheme'] == scheme) &&
            (q.isEmpty || d['host'].toString().contains(q)))
        .toList();
    if (targets.isEmpty) {
      _snack('Tidak ada domain untuk diganti.', error: true);
      return;
    }
    final label = scheme == 'all' ? 'domain' : scheme.toUpperCase();
    final result = await _askDomain(
      title: 'Ganti semua $label (${targets.length})',
      info: '${targets.length} domain akan diganti dengan satu domain baru di semua file. '
          'Domain sistem tidak ikut diganti.',
    );
    if (result == null || result.isEmpty) return;
    setState(() {
      for (final d in targets) {
        _domainMap[d['key'].toString()] = result;
      }
      _doDomain = true;
    });
  }

  Widget _schemeBadge(String scheme) {
    final c = scheme == 'https' ? kGreen : const Color(0xFFFFC107);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: c.withOpacity(0.15), borderRadius: BorderRadius.circular(6)),
      child: Text(scheme.toUpperCase(), style: TextStyle(color: c, fontSize: 9, fontWeight: FontWeight.bold)),
    );
  }

  Widget _domainRow(Map<dynamic, dynamic> d) {
    final key = d['key'].toString();
    final target = _domainMap[key];
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      onTap: _busy ? null : () => _editDomain(key),
      title: Row(
        children: [
          _schemeBadge(d['scheme'].toString()),
          const SizedBox(width: 8),
          Expanded(child: Text(d['host'].toString(), style: const TextStyle(color: Colors.white, fontSize: 13))),
        ],
      ),
      subtitle: Text(
        target == null
            ? '${d['count']} kemunculan di ${d['files']} file'
            : '→ $target   (${d['count']} kemunculan di ${d['files']} file)',
        style: TextStyle(color: target == null ? kMuted : kGreen, fontSize: 11),
      ),
      trailing: Icon(target == null ? Icons.edit_outlined : Icons.check_circle,
          size: 18, color: target == null ? kMuted : kGreen),
    );
  }

  Widget _domainList() {
    final all = _domains;
    if (all == null) {
      return Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          onPressed: (_busy || _scanningDomains || _zipPath == null) ? null : _findDomains,
          icon: _scanningDomains
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: kRed))
              : const Icon(Icons.travel_explore, size: 18),
          label: Text(_scanningDomains ? 'Mencari...' : 'Cari domain di semua file'),
        ),
      );
    }
    final q = _domainFilter.text.trim().toLowerCase();
    bool match(Map<dynamic, dynamic> d) =>
        (_schemeFilter == 'all' || d['scheme'] == _schemeFilter) &&
        (q.isEmpty || d['host'].toString().contains(q));
    final normal = all.where((d) => d['protected'] != true && match(d)).toList();
    final system = all.where((d) => d['protected'] == true && match(d)).toList();
    final nHttps = all.where((d) => d['scheme'] == 'https').length;
    final nHttp = all.where((d) => d['scheme'] == 'http').length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Ditemukan ${all.length} domain ($nHttps https, $nHttp http)',
            style: const TextStyle(color: kMuted, fontSize: 11)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            for (final f in const [['all', 'Semua'], ['https', 'HTTPS'], ['http', 'HTTP']])
              ChoiceChip(
                label: Text(f[1], style: const TextStyle(fontSize: 12)),
                selected: _schemeFilter == f[0],
                onSelected: (_) => setState(() => _schemeFilter = f[0]),
              ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _domainFilter,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(hintText: 'Filter domain', prefixIcon: Icon(Icons.search, size: 18)),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            OutlinedButton(onPressed: _busy ? null : () => _bulk('https'), child: const Text('Ganti semua HTTPS', style: TextStyle(fontSize: 11))),
            OutlinedButton(onPressed: _busy ? null : () => _bulk('http'), child: const Text('Ganti semua HTTP', style: TextStyle(fontSize: 11))),
            OutlinedButton(onPressed: _busy ? null : () => _bulk('all'), child: const Text('Ganti semua domain', style: TextStyle(fontSize: 11))),
            if (_domainMap.isNotEmpty)
              TextButton(
                onPressed: _busy ? null : () => setState(() {
                  _domainMap.clear();
                  _doDomain = false;
                }),
                child: const Text('Hapus pilihan', style: TextStyle(fontSize: 11)),
              ),
          ],
        ),
        const SizedBox(height: 6),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 320),
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final d in normal) _domainRow(d),
              if (normal.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(8),
                  child: Text('Tidak ada domain cocok.', style: TextStyle(color: kMuted, fontSize: 12)),
                ),
            ],
          ),
        ),
        if (system.isNotEmpty)
          TextButton(
            onPressed: () => setState(() => _showProtected = !_showProtected),
            child: Text(
              _showProtected ? 'Sembunyikan domain sistem' : 'Tampilkan domain sistem (${system.length}) — jangan diubah kecuali yakin',
              style: const TextStyle(fontSize: 11),
            ),
          ),
        if (_showProtected)
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 200),
            child: ListView(shrinkWrap: true, children: [for (final d in system) _domainRow(d)]),
          ),
      ],
    );
  }

  Future<void> _pickIcon() async {
    final res = await FilePicker.platform.pickFiles(type: FileType.image);
    if (res == null || res.files.isEmpty || res.files.first.path == null) return;
    setState(() {
      _iconPath = res.files.first.path;
      _doIcon = true;
    });
  }

  void _renameAll() {
    setState(() {
      _doName = true;
      _doPkg = true;
      _doIcon = _iconPath != null;
      _doProject = true;
      _doDomain = _domainMap.isNotEmpty;
    });
    _snack('Rename semua aktif: nama, package, icon (bila dipilih), nama project, dan domain (bila sudah diisi).');
  }

  Future<void> _apply() async {
    final zip = _zipPath;
    if (zip == null) {
      _snack('Pilih ZIP project dulu.', error: true);
      return;
    }
    if (!(_doName || _doPkg || _doIcon || _doProject || _doDomain)) {
      _snack('Pilih minimal satu perubahan.', error: true);
      return;
    }
    if (_doName && _name.text.trim().isEmpty) {
      _snack('Nama aplikasi masih kosong.', error: true);
      return;
    }
    if (_doPkg && _pkg.text.trim().isEmpty) {
      _snack('Package masih kosong.', error: true);
      return;
    }
    if (_doDomain && _domainMap.isEmpty) {
      _snack('Cari domain lalu isi domain pengganti dulu.', error: true);
      return;
    }
    if (_doIcon && _iconPath == null) {
      _snack('Pilih gambar icon dulu.', error: true);
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
      _outPath = null;
      _changes = [];
    });

    try {
      Map<String, dynamic>? icons;
      if (_doIcon) {
        final bytes = await File(_iconPath!).readAsBytes();
        icons = await IconGenerator.generate(bytes);
      }

      final dir = await getTemporaryDirectory();
      final outDir = Directory('${dir.path}/ciko_custom');
      if (!await outDir.exists()) await outDir.create(recursive: true);
      final base = zip.split('/').last.replaceAll(RegExp(r'\.zip$', caseSensitive: false), '');
      final out = '${outDir.path}/${base}_custom.zip';

      final result = await runCustomizeInIsolate({
        'zip': zip,
        'out': out,
        'newName': _doName ? _name.text.trim() : null,
        'newPackage': _doPkg ? _pkg.text.trim() : null,
        'renameProject': _doProject,
        'domainMap': _doDomain ? Map<String, String>.from(_domainMap) : <String, String>{},
        'icons': icons,
      });

      if (!mounted) return;
      if (result['ok'] == true) {
        setState(() {
          _outPath = result['out'].toString();
          _changes = (result['changes'] as List).map((e) => e.toString()).toList();
        });
        _snack('Selesai! ZIP baru siap.');
      } else {
        setState(() => _error = result['error']?.toString() ?? 'Gagal menerapkan perubahan');
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Gagal: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveDownload() async {
    final out = _outPath;
    if (out == null) return;
    try {
      final where = await ArtifactService.saveToDownloads(
        out,
        out.split('/').last,
        mime: 'application/zip',
      );
      _snack('Tersimpan di $where');
    } catch (e) {
      _snack(e.toString().replaceFirst('Exception: ', ''), error: true);
    }
  }

  void _openBuild() {
    final out = _outPath;
    if (out == null) return;
    final flutter = _scan?['kind'] == 'flutter';
    AppNav.buildType.value = flutter ? AppNav.buildFlutter : AppNav.buildAndroid;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => flutter
            ? BuildFlutterScreen(session: widget.session, controller: widget.controller, initialZipPath: out)
            : BuildAndroidScreen(session: widget.session, controller: widget.controller, initialZipPath: out),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scan = _scan;
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        title: const Text('Ganti Icon, Nama & Domain'),
        backgroundColor: kBg,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          InkWell(
            onTap: (_busy || _scanning) ? null : _pickZip,
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
                  Icon(Icons.folder_zip_outlined, size: 36, color: _zipPath != null ? kRed : kMuted),
                  const SizedBox(height: 8),
                  Text(
                    _zipPath != null ? _zipPath!.split('/').last : 'Pilih ZIP project',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: _zipPath != null ? Colors.white : kMuted, fontWeight: FontWeight.w600),
                  ),
                  if (_scanning) ...[
                    const SizedBox(height: 10),
                    const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: kRed)),
                  ],
                ],
              ),
            ),
          ),
          if (scan != null) ...[
            const SizedBox(height: 10),
            Text(
              'Terdeteksi: ${scan['kind']} • package ${scan['appId'] ?? scan['namespace'] ?? '-'} • nama "${scan['label'] ?? '-'}"',
              style: const TextStyle(color: kMuted, fontSize: 11),
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: (_busy || scan == null) ? null : _renameAll,
              icon: const Icon(Icons.auto_fix_high, size: 18),
              label: const Text('Rename Semua'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: kRed),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          const SizedBox(height: 16),
          _section(
            title: 'Nama aplikasi',
            value: _doName,
            onChanged: (v) => setState(() => _doName = v),
            child: TextField(
              controller: _name,
              enabled: _doName,
              decoration: const InputDecoration(hintText: 'Nama yang tampil di HP'),
            ),
          ),
          _section(
            title: 'Package',
            subtitle: 'applicationId / namespace + folder sumber Kotlin/Java',
            value: _doPkg,
            onChanged: (v) => setState(() => _doPkg = v),
            child: TextField(
              controller: _pkg,
              enabled: _doPkg,
              autocorrect: false,
              decoration: const InputDecoration(hintText: 'com.nama.aplikasi'),
            ),
          ),
          _section(
            title: 'Domain',
            subtitle: 'Cari di semua file yang berisi http:// atau https://, lalu ganti domainnya',
            value: _doDomain,
            onChanged: (v) => setState(() => _doDomain = v),
            child: _domainList(),
          ),
          _section(
            title: 'Icon aplikasi',
            value: _doIcon,
            onChanged: (v) => setState(() => _doIcon = v),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _iconPath == null ? 'Belum ada gambar (PNG/JPG, disarankan 512×512+)' : _iconPath!.split('/').last,
                    style: const TextStyle(color: kMuted, fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                OutlinedButton(onPressed: _busy ? null : _pickIcon, child: const Text('Pilih')),
              ],
            ),
          ),
          _section(
            title: 'Rename project (nama internal)',
            subtitle: 'pubspec name, rootProject.name, dan nama folder ZIP',
            value: _doProject,
            onChanged: (v) => setState(() => _doProject = v),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54), backgroundColor: kRed),
            onPressed: (_busy || _zipPath == null) ? null : _apply,
            icon: _busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.check),
            label: Text(_busy ? 'Menerapkan...' : 'Terapkan Perubahan'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: kRed, fontSize: 12)),
          ],
          if (_outPath != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: kCard,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: kGreen.withOpacity(0.5)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Hasil', style: TextStyle(color: kGreen, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  for (final c in _changes)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text('• $c', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                    ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _saveDownload,
                          icon: const Icon(Icons.download, size: 18),
                          label: const Text('Simpan ZIP'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(backgroundColor: kGreen, foregroundColor: Colors.black),
                          onPressed: _openBuild,
                          icon: const Icon(Icons.rocket_launch, size: 18),
                          label: const Text('Build'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _section({
    required String title,
    String? subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    Widget? child,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: value ? kRed.withOpacity(0.6) : kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
                    if (subtitle != null)
                      Text(subtitle, style: const TextStyle(color: kMuted, fontSize: 11)),
                  ],
                ),
              ),
              Switch(value: value, onChanged: _busy ? null : onChanged, activeColor: kRed),
            ],
          ),
          if (child != null) ...[
            const SizedBox(height: 8),
            child,
          ],
        ],
      ),
    );
  }
}
