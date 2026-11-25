import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/build_record.dart';
import '../nav.dart';
import '../services/error_log.dart';
import '../services/build_controller.dart';
import '../screens/log_viewer_page.dart';
import '../theme.dart';
import 'terminal_log_view.dart';

const Color kAmber = Color(0xFFFFC107);

Color statusColor(BuildRecord r) {
  if (!r.isFinished) return kAmber;
  if (r.status == 'cancelled') return kMuted;
  return r.isSuccess ? kGreen : kRed;
}

/// Ubah data dinamis (hasil JSON) jadi daftar Map<String,dynamic> tanpa pernah melempar error.
List<Map<String, dynamic>> _asMapList(dynamic v) {
  if (v is! List) return const [];
  final out = <Map<String, dynamic>>[];
  for (final e in v) {
    if (e is Map) {
      out.add(e.map((k, val) => MapEntry(k.toString(), val)));
    }
  }
  return out;
}

int? _asInt(dynamic v) => v is num ? v.toInt() : null;

String formatBytes(int bytes) {
  if (bytes <= 0) return '0 B';
  const u = ['B', 'KB', 'MB', 'GB'];
  var v = bytes.toDouble();
  var i = 0;
  while (v >= 1024 && i < u.length - 1) {
    v /= 1024;
    i++;
  }
  return '${v.toStringAsFixed(i == 0 ? 0 : 1)} ${u[i]}';
}

String _two(int v) => v.toString().padLeft(2, '0');

String formatDuration(int ms) {
  final total = (ms < 0 ? 0 : ms) ~/ 1000;
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final s = total % 60;
  if (h > 0) return '${h}h ${_two(m)}m ${_two(s)}s';
  if (m > 0) return '${m}m ${_two(s)}s';
  return '${s}s';
}

String formatDateTime(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${_two(d.day)}/${_two(d.month)} ${_two(d.hour)}:${_two(d.minute)}:${_two(d.second)}';
}

/// Kartu progress build.
/// - [detailed] = false → ringkas (dipakai di layar build & riwayat)
/// - [detailed] = true  → lengkap: info run, semua job & step, durasi, log, aksi APK
/// - [recordId] kosong → tampilkan build berjalan / terakhir.
class BuildProgressView extends StatefulWidget {
  const BuildProgressView({
    super.key,
    required this.controller,
    this.recordId,
    this.detailed = false,
  });

  final BuildController controller;
  final String? recordId;
  final bool detailed;

  @override
  State<BuildProgressView> createState() => _BuildProgressViewState();
}

class _BuildProgressViewState extends State<BuildProgressView> {
  Timer? _ticker;

  BuildController get controller => widget.controller;

  BuildRecord? _record() =>
      widget.recordId == null ? controller.display : controller.byId(widget.recordId!);

  @override
  void initState() {
    super.initState();
    // Detik berjalan untuk durasi build yang sedang aktif.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      final r = _record();
      if (mounted && r != null && !r.isFinished) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg),
        backgroundColor: error ? kRed : kCard,
        behavior: SnackBarBehavior.floating,
      ));
  }

  Future<void> _guard(Future<void> Function() action, {String? success}) async {
    try {
      await action();
      if (success != null) _snack(success);
    } catch (e) {
      _snack(e.toString().replaceFirst('Exception: ', ''), error: true);
    }
  }

  Future<void> _confirmCancel(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Batalkan Build?', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Build yang sedang berjalan akan dihentikan secara paksa di GitHub Actions.',
          style: TextStyle(color: kMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Tidak', style: TextStyle(color: kMuted)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: kRed),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Ya, Batalkan', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _guard(() => controller.cancelBuild(id), success: 'Build berhasil dibatalkan');
    }
  }

  void _openDetailTab() {
    Navigator.of(context).popUntil((route) => route.isFirst);
    AppNav.tabIndex.value = AppNav.progressTab;
  }

  Future<void> _openUrl(String? url) async {
    if (url == null || url.isEmpty) return;
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final r = _record();

        if (r == null) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text('Belum ada riwayat build.', style: TextStyle(color: kMuted, fontSize: 14)),
            ),
          );
        }

        final color = statusColor(r);
        final progress = (r.percent / 100).clamp(0.0, 1.0);

        return Card(
          color: kCard,
          margin: const EdgeInsets.only(bottom: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: kBorder),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _header(r, color),
                const SizedBox(height: 4),
                Text(
                  '${r.typeLabel}${r.mode.isEmpty ? '' : ' • ${r.mode}'} • ${r.owner}/${r.repo}',
                  style: const TextStyle(color: kMuted, fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 20),

                Center(
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: 120,
                        height: 120,
                        child: CircularProgressIndicator(
                          value: r.isFinished ? (r.isSuccess ? 1.0 : progress) : (r.percent == 0 ? null : progress),
                          strokeWidth: 8,
                          backgroundColor: kBorder,
                          valueColor: AlwaysStoppedAnimation<Color>(color),
                          strokeCap: StrokeCap.round,
                        ),
                      ),
                      Text(
                        '${r.percent}%',
                        style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                Center(
                  child: Text(
                    r.step.isEmpty ? 'Menunggu runner GitHub...' : r.step,
                    style: const TextStyle(color: kMuted, fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 6),
                Center(
                  child: Text(
                    'Durasi ${formatDuration(r.elapsedMs)}',
                    style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),

                if (!r.isFinished) ...[
                  const SizedBox(height: 10),
                  Center(
                    child: Text(
                      r.status == 'uploading'
                          ? 'Upload berjalan di aplikasi — jangan tutup sampai build dimulai.'
                          : 'Berjalan di latar belakang — aman ditutup, notifikasi akan muncul saat selesai.',
                      style: TextStyle(color: kMuted, fontSize: 11),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],

                ..._apkSection(r),
                ..._analysisSection(r),
                ..._uploadSection(r),
                ..._failureSection(r),

                if (r.url != null && r.url!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Center(
                    child: TextButton.icon(
                      onPressed: () => _openUrl(r.url),
                      icon: const Icon(Icons.open_in_new, size: 16, color: kMuted),
                      label: const Text('Buka di GitHub', style: TextStyle(color: kMuted, fontSize: 12)),
                    ),
                  ),
                ],

                if (!widget.detailed) ...[
                  if (!r.isFinished) ..._logSection(r, height: 170),
                  const SizedBox(height: 4),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _openDetailTab,
                      icon: const Icon(Icons.timelapse, size: 18),
                      label: const Text('Lihat progress lengkap'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: kBorder),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                ] else ...[
                  const SizedBox(height: 16),
                  ..._safe('info', () => [_infoSection(r)]),
                  ..._safe('job', () => _jobsSection(r)),
                  ..._safe('log', () => _logSection(r)),
                  ..._safe('diagnosis', () => _diagnosticsSection(r)),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  /// Jalankan pembuat widget; kalau melempar error, tampilkan pesan kecil dan catat.
  List<Widget> _safe(String name, List<Widget> Function() build) {
    try {
      return build();
    } catch (e, st) {
      ErrorLog.record('Bagian "$name": $e', st);
      return [
        const SizedBox(height: 12),
        Text(
          'Bagian $name tidak bisa ditampilkan.',
          style: const TextStyle(color: kMuted, fontSize: 12),
        ),
      ];
    }
  }

  Widget _header(BuildRecord r, Color color) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(
            r.status == 'uploading'
                ? 'Mengunggah ke GitHub...'
                : r.id == 'pending_upload'
                    ? 'Upload gagal'
                    : r.isAnalyzer
                ? (r.isFinished ? (r.isSuccess ? 'Analisis lolos' : 'Analisis menemukan error') : 'Sedang menganalisis...')
                : (r.isFinished ? 'Build ${r.statusLabel}' : 'Sedang Build...'),
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
          ),
        ),
        if (!r.isFinished)
          TextButton.icon(
            onPressed: r.runId == null ? null : () => _confirmCancel(r.id),
            icon: const Icon(Icons.stop_circle_outlined, color: kRed, size: 18),
            label: const Text('Batal', style: TextStyle(color: kRed, fontSize: 12)),
            style: TextButton.styleFrom(
              side: const BorderSide(color: kRed, width: 1),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            ),
          )
        else
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              r.statusLabel.toUpperCase(),
              style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12),
            ),
          ),
      ],
    );
  }

  List<Widget> _apkSection(BuildRecord r) {
    if (!r.isSuccess || r.isAnalyzer) return const [];

    final manual = controller.downloading && controller.downloadingId == r.id;
    final bg = r.isDownloading;
    final pct = manual ? (controller.downloadProgress * 100).round() : r.downloadPercent;

    final widgets = <Widget>[const SizedBox(height: 16)];

    if (manual || bg) {
      widgets.addAll([
        LinearProgressIndicator(
          value: pct > 0 ? pct / 100 : null,
          color: kRed,
          backgroundColor: kBorder,
          minHeight: 5,
        ),
        const SizedBox(height: 6),
        Text(
          manual ? 'Mengunduh APK... $pct%' : 'Mengunduh APK di latar belakang... $pct%',
          style: const TextStyle(color: kMuted, fontSize: 11),
          textAlign: TextAlign.center,
        ),
      ]);
      return widgets;
    }

    if (r.hasApk) {
      widgets.addAll([
        _apkInfoCard(r),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: kGreen,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => _guard(() => controller.installApk(r)),
            icon: const Icon(Icons.system_update_alt, color: Colors.black),
            label: const Text('Install APK',
                style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => _guard(() async {
              final where = await controller.saveToDownloads(r);
              _snack('Tersimpan di $where');
            }),
            icon: const Icon(Icons.download_done, size: 18),
            label: const Text('Simpan ke folder Download'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: kBorder),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
      ]);
      return widgets;
    }

    // Belum ada APK: unduhan gagal / belum pernah / artifact baru siap.
    if (r.downloadState == 'failed' && r.downloadError.isNotEmpty) {
      widgets.addAll([
        Text(
          r.downloadError,
          style: const TextStyle(color: kRed, fontSize: 12),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
      ]);
    }
    widgets.add(
      SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: kRed,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onPressed: r.runId == null
              ? null
              : () => _guard(() => controller.downloadApk(r), success: 'APK siap diinstal'),
          icon: const Icon(Icons.download, color: Colors.white),
          label: Text(
            r.downloadState == 'failed' ? 'Unduh ulang APK' : 'Unduh APK',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ),
      ),
    );
    return widgets;
  }

  /// Hasil analyzer: hanya error yang ditampilkan; bila tidak ada error, build dilanjutkan otomatis.
  List<Widget> _analysisSection(BuildRecord r) {
    if (!r.isAnalyzer || !r.isFinished || r.status == 'cancelled') return const [];
    final errors = r.analysisErrors;

    if (errors.isEmpty) {
      return [
        const SizedBox(height: 14),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: kGreen.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: kGreen.withOpacity(0.5)),
          ),
          child: const Text(
            'Tidak ada error. Build dilanjutkan otomatis — pantau di tab Progress.',
            style: TextStyle(color: kGreen, fontSize: 12),
          ),
        ),
      ];
    }

    final shown = errors.take(50).toList();
    return [
      const SizedBox(height: 14),
      Row(
        children: [
          Expanded(
            child: Text('Ditemukan ${errors.length} error',
                style: const TextStyle(color: kRed, fontWeight: FontWeight.bold, fontSize: 14)),
          ),
          TextButton.icon(
            onPressed: () async {
              final b = StringBuffer();
              for (final e in errors) {
                b.writeln('[ERROR] ${e['title']}');
                if (e['file'] != null) b.writeln('  ${e['file']}${e['line'] == null ? '' : ':${e['line']}'}');
                if ('${e['detail'] ?? ''}'.isNotEmpty) b.writeln('  ${e['detail']}');
                b.writeln();
              }
              await Clipboard.setData(ClipboardData(text: b.toString()));
              _snack('Laporan error disalin');
            },
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('Salin', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
      for (final e in shown)
        Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: kRed.withOpacity(0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: kRed.withOpacity(0.4)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${e['title']}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12)),
              if (e['file'] != null)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text('${e['file']}${e['line'] == null ? '' : ':${e['line']}'}',
                      style: const TextStyle(color: kRed, fontSize: 11, fontFamily: 'monospace')),
                ),
              if ('${e['detail'] ?? ''}'.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('${e['detail']}', style: const TextStyle(color: kMuted, fontSize: 11)),
                ),
            ],
          ),
        ),
      if (errors.length > shown.length)
        Text('+${errors.length - shown.length} error lainnya', style: const TextStyle(color: kMuted, fontSize: 11)),
    ];
  }

  Widget _infoSection(BuildRecord r) {
    final rows = <MapEntry<String, String>>[
      MapEntry('Repository', '${r.owner}/${r.repo}'),
      MapEntry('Jenis', '${r.typeLabel}${r.mode.isEmpty ? '' : ' • ${r.mode}'}'),
      MapEntry('Workflow', '${r.workflow} (${r.customWorkflow ? 'kustom' : 'bawaan'})'),
      if (r.runNumber != null) MapEntry('Run', '#${r.runNumber}'),
      if (r.branch != null && r.branch!.isNotEmpty)
        MapEntry('Branch', r.sha == null ? r.branch! : '${r.branch} • ${r.sha}'),
      if (r.actor != null && r.actor!.isNotEmpty) MapEntry('Dipicu oleh', r.actor!),
      MapEntry('Mulai', formatDateTime(r.startedAt)),
      if (r.finishedAt != null) MapEntry('Selesai', formatDateTime(r.finishedAt!)),
      MapEntry('Durasi', formatDuration(r.elapsedMs)),
      if (r.apkLabel.isNotEmpty) MapEntry('Nama aplikasi', r.apkLabel),
      if (r.apkPackage.isNotEmpty) MapEntry('Package', r.apkPackage),
      if (r.apkVersion.isNotEmpty) MapEntry('Versi', r.apkVersion),
      if (r.apkSize > 0) MapEntry('Ukuran APK', formatBytes(r.apkSize)),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Detail Build',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: kInputBg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: kBorder),
          ),
          child: Column(
            children: [
              for (final e in rows)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 92,
                        child: Text(e.key, style: const TextStyle(color: kMuted, fontSize: 12)),
                      ),
                      Expanded(
                        child: Text(
                          e.value,
                          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  List<Widget> _jobsSection(BuildRecord r) {
    if (r.jobs.isEmpty) {
      return [
        const SizedBox(height: 16),
        const Text('Job & Step',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
        const SizedBox(height: 8),
        Text(
          r.isFinished ? 'Detail job tidak tersedia.' : 'Menunggu runner GitHub memulai job...',
          style: const TextStyle(color: kMuted, fontSize: 12),
        ),
      ];
    }

    return [
      const SizedBox(height: 16),
      const Text('Job & Step',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
      const SizedBox(height: 8),
      for (final job in r.jobs) _jobTile(r, job),
    ];
  }

  Widget _jobTile(BuildRecord r, Map<String, dynamic> job) {
    final status = job['status']?.toString() ?? 'queued';
    final conclusion = job['conclusion']?.toString();
    final steps = _asMapList(job['steps']);
    final start = _asInt(job['start']);
    final end = _asInt(job['end']);
    final now = DateTime.now().millisecondsSinceEpoch;
    final dur = start == null ? null : (end ?? now) - start;
    final runner = job['runner']?.toString();
    final doneCount = steps.where((s) => s['status'] == 'completed').length;

    final open = status == 'in_progress' || conclusion == 'failure';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: kInputBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: kBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          key: ValueKey<String>('job_${r.id}_${job['id']}'),
          initiallyExpanded: open,
          tilePadding: const EdgeInsets.symmetric(horizontal: 12),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
          iconColor: kMuted,
          collapsedIconColor: kMuted,
          leading: _stateIcon(status, conclusion),
          title: Text(
            job['name']?.toString() ?? 'Job',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
          ),
          subtitle: Text(
            [
              '$doneCount/${steps.length} step',
              if (dur != null) formatDuration(dur),
              if (runner != null && runner.isNotEmpty) runner,
            ].join(' • '),
            style: const TextStyle(color: kMuted, fontSize: 11),
          ),
          children: [
            for (final s in steps) _stepRow(s, now),
            if (job['url'] is String)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => _openUrl(job['url'] as String?),
                  child: const Text('Buka log lengkap job di GitHub', style: TextStyle(fontSize: 11)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _stepRow(Map<String, dynamic> s, int now) {
    final status = s['status']?.toString() ?? 'queued';
    final conclusion = s['conclusion']?.toString();
    final start = _asInt(s['start']);
    final end = _asInt(s['end']);
    final dur = start == null ? null : (end ?? now) - start;

    Color nameColor = Colors.white70;
    if (status == 'in_progress') nameColor = kAmber;
    if (conclusion == 'failure') nameColor = kRed;
    if (status == 'queued' || status == 'pending') nameColor = kMuted;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          _stateIcon(status, conclusion, size: 16),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              s['name']?.toString() ?? 'Step',
              style: TextStyle(color: nameColor, fontSize: 12),
            ),
          ),
          if (dur != null && dur >= 0)
            Text(formatDuration(dur), style: const TextStyle(color: kMuted, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _stateIcon(String status, String? conclusion, {double size = 20}) {
    if (status == 'in_progress') {
      return SizedBox(
        width: size,
        height: size,
        child: const CircularProgressIndicator(strokeWidth: 2, color: kAmber),
      );
    }
    if (status == 'completed') {
      switch (conclusion) {
        case 'success':
          return Icon(Icons.check_circle, color: kGreen, size: size);
        case 'failure':
        case 'timed_out':
          return Icon(Icons.cancel, color: kRed, size: size);
        case 'skipped':
          return Icon(Icons.remove_circle_outline, color: kMuted, size: size);
        case 'cancelled':
          return Icon(Icons.block, color: kMuted, size: size);
        default:
          return Icon(Icons.help_outline, color: kMuted, size: size);
      }
    }
    return Icon(Icons.radio_button_unchecked, color: kMuted, size: size);
  }

  /// Terminal gabungan: log upload di atas, log build live di bawah.
  List<Widget> _logSection(BuildRecord r, {double height = 300}) {
    final isPending = r.id == 'pending_upload';
    final up = isPending ? controller.upload.logLines.join('\n') : r.uploadLog;
    final build = r.logTail;
    final jobs = _jobLines(r);
    final text = [
      if (up.isNotEmpty) up,
      if (jobs.isNotEmpty) ...[if (up.isNotEmpty) '', jobs],
      if (build.isNotEmpty) ...['', '\$ log — ${r.workflow}', build],
    ].join('\n');
    if (text.trim().isEmpty) return const [];
    return [
      const SizedBox(height: 14),
      if (widget.detailed)
        const Text('Terminal',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
      if (widget.detailed) const SizedBox(height: 8),
      TerminalLogView(
        text: text,
        running: !r.isFinished,
        height: height,
        title: isPending ? 'upload' : '${r.typeLabel.toLowerCase()} • ${r.repo}',
      ),
    ];
  }

  /// Detail job & step (ikon status + durasi) untuk terminal.
  String _jobLines(BuildRecord r) {
    final b = StringBuffer();
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final job in r.jobs) {
      final runner = job['runner']?.toString() ?? '';
      b.writeln('\$ job: ${job['name']}${runner.isEmpty ? '' : ' (runner: $runner)'}');
      for (final s in _asMapList(job['steps'])) {
        final status = s['status']?.toString() ?? 'queued';
        final conclusion = s['conclusion']?.toString();
        final start = _asInt(s['start']);
        final end = _asInt(s['end']);
        final dur = start == null ? '' : ' (${formatDuration((end ?? now) - start)})';
        final String icon;
        if (status == 'completed') {
          icon = conclusion == 'success' ? '✓' : (conclusion == 'skipped' ? '-' : '✗');
        } else if (status == 'in_progress') {
          icon = '▶';
        } else {
          icon = '·';
        }
        b.writeln('  $icon ${s['name']}$dur');
      }
    }
    return b.toString().trimRight();
  }

  void _openFullLog(BuildRecord r) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => LogViewerPage(controller: controller, recordId: r.id)),
    );
  }

  /// Tahap upload: langsung (saat mengunggah) atau ringkasan (setelah build dimulai).
  List<Widget> _uploadSection(BuildRecord r) {
    if (r.id == 'pending_upload') {
      final u = controller.upload;
      final failed = u.error != null;
      return [
        const SizedBox(height: 14),
        for (var i = 0; i < u.steps.length; i++)
          _uploadRow(
            u.steps[i],
            i < u.current || u.done ? 'done' : (i == u.current ? (failed ? 'fail' : 'active') : 'wait'),
            i == u.current && !failed ? u.detail : '',
          ),
        if (failed) ...[
          const SizedBox(height: 8),
          Text(u.error!, style: const TextStyle(color: kRed, fontSize: 12)),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: controller.dismissPending,
              child: const Text('Tutup', style: TextStyle(color: kMuted, fontSize: 12)),
            ),
          ),
        ],
      ];
    }
    if (r.uploadSteps.isNotEmpty && widget.detailed) {
      return [
        const SizedBox(height: 14),
        Text('Upload selesai (${r.uploadSteps.length} tahap)',
            style: const TextStyle(color: kGreen, fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        for (final s in r.uploadSteps) _uploadRow(s, 'done', ''),
      ];
    }
    return const [];
  }

  Widget _uploadRow(String label, String state, String detail) {
    Widget icon;
    switch (state) {
      case 'done':
        icon = const Icon(Icons.check_circle, color: kGreen, size: 16);
        break;
      case 'fail':
        icon = const Icon(Icons.cancel, color: kRed, size: 16);
        break;
      case 'active':
        icon = const SizedBox(
            width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: kAmber));
        break;
      default:
        icon = const Icon(Icons.radio_button_unchecked, color: kMuted, size: 16);
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(width: 18, child: Center(child: icon)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(label,
                style: TextStyle(
                    color: state == 'active' ? Colors.white : (state == 'done' ? Colors.white70 : kMuted),
                    fontSize: 12)),
          ),
          if (detail.isNotEmpty)
            Flexible(
              child: Text(detail,
                  style: const TextStyle(color: kMuted, fontSize: 11),
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end),
            ),
        ],
      ),
    );
  }

  /// Build gagal: ringkasan error + tombol log lengkap.
  List<Widget> _failureSection(BuildRecord r) {
    if (r.status != 'failure' || r.isAnalyzer || r.id == 'pending_upload') return const [];
    final lines = r.diagnostics.isNotEmpty ? r.diagnostics.take(4).toList() : [r.step];
    return [
      const SizedBox(height: 14),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: kRed.withOpacity(0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: kRed.withOpacity(0.4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Detail error',
                style: TextStyle(color: kRed, fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 6),
            for (final l in lines)
              Text(l, style: const TextStyle(color: Colors.white70, fontSize: 12)),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => _openFullLog(r),
              icon: const Icon(Icons.terminal, size: 16),
              label: Text(r.logPath.isNotEmpty ? 'Buka log lengkap' : 'Muat log lengkap'),
              style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: kRed)),
            ),
          ],
        ),
      ),
    ];
  }

  /// Kartu info APK: icon, nama aplikasi, package, versi, ukuran.
  Widget _apkInfoCard(BuildRecord r) {
    final hasIcon = r.apkIconPath.isNotEmpty && File(r.apkIconPath).existsSync();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: kInputBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kBorder),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: hasIcon
                ? Image.file(File(r.apkIconPath), width: 52, height: 52, fit: BoxFit.cover)
                : Container(
                    width: 52,
                    height: 52,
                    color: kBorder,
                    child: const Icon(Icons.android, color: kGreen, size: 28),
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(r.apkLabel.isEmpty ? r.repo : r.apkLabel,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                    overflow: TextOverflow.ellipsis),
                if (r.apkPackage.isNotEmpty)
                  Text(r.apkPackage, style: const TextStyle(color: kMuted, fontSize: 11), overflow: TextOverflow.ellipsis),
                Text(
                  [
                    if (r.apkVersion.isNotEmpty) 'v${r.apkVersion}',
                    if (r.apkSize > 0) formatBytes(r.apkSize),
                  ].join(' • '),
                  style: const TextStyle(color: kGreen, fontSize: 11, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _diagnosticsSection(BuildRecord r) {
    if (r.diagnostics.isEmpty) return const [];
    return [
      const SizedBox(height: 16),
      const Text('Diagnosis',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
      const SizedBox(height: 8),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: kRed.withOpacity(0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: kRed.withOpacity(0.4)),
        ),
        child: Text(
          r.diagnostics.join('\n'),
          style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: Colors.white70, height: 1.4),
        ),
      ),
    ];
  }
}
