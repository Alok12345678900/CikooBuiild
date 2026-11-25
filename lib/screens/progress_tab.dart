import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/build_record.dart';
import '../services/build_controller.dart';
import '../services/error_log.dart';
import '../theme.dart';
import '../widgets/build_progress_view.dart';

/// Tab Progress: detail penuh build yang berjalan (maks 3 sekaligus) atau yang terakhir.
class ProgressTab extends StatefulWidget {
  const ProgressTab({super.key, required this.controller});

  final BuildController controller;

  @override
  State<ProgressTab> createState() => _ProgressTabState();
}

class _ProgressTabState extends State<ProgressTab> {
  String? _selectedId;

  BuildController get controller => widget.controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([controller, controller.upload]),
      builder: (context, _) {
        final running = [
          if (controller.pending != null) controller.pending!,
          ...controller.active.where((r) => !r.isFinished).toList().reversed,
        ];
        final uploading = controller.upload.visible;

        // Build yang dipilih: pilihan pengguna kalau masih aktif, kalau tidak yang terbaru.
        String? shownId;
        if (running.isNotEmpty) {
          shownId = running.any((r) => r.id == _selectedId) ? _selectedId : running.first.id;
        }
        final hasAnything = running.isNotEmpty || controller.history.isNotEmpty;

        return RefreshIndicator(
          onRefresh: controller.reload,
          color: kRed,
          backgroundColor: kCard,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              const Text('Progress Build', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(
                running.isEmpty
                    ? 'Detail build terakhir'
                    : '${running.length} build berjalan (maks ${BuildController.maxConcurrent}) • diperbarui otomatis',
                style: const TextStyle(color: kMuted, fontSize: 12),
              ),
              const SizedBox(height: 16),
              const _ErrorReport(),

              if (running.length > 1) ...[
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final r in running) ...[
                        _chip(r, selected: r.id == shownId),
                        const SizedBox(width: 8),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],

              if (shownId != null)
                BuildProgressView(controller: controller, recordId: shownId, detailed: true)
              else if (hasAnything)
                BuildProgressView(controller: controller, detailed: true)
              else if (!uploading)
                const Padding(
                  padding: EdgeInsets.only(top: 64),
                  child: Column(
                    children: [
                      Icon(Icons.timelapse, size: 56, color: kMuted),
                      SizedBox(height: 12),
                      Text('Belum ada build', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                      SizedBox(height: 4),
                      Text(
                        'Mulai build dari tab Beranda, progress lengkapnya muncul di sini.',
                        style: TextStyle(color: kMuted, fontSize: 12),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _chip(BuildRecord r, {required bool selected}) {
    return ChoiceChip(
      selected: selected,
      onSelected: (_) => setState(() => _selectedId = r.id),
      selectedColor: kRed.withOpacity(0.2),
      backgroundColor: kCard,
      side: BorderSide(color: selected ? kRed : kBorder),
      label: Text(
        '${r.id == 'pending_upload' ? 'Upload' : r.typeLabel} • ${r.repo} ${r.percent}%',
        style: TextStyle(color: selected ? kRed : Colors.white70, fontSize: 12),
      ),
    );
  }
}

/// Menampilkan error tampilan terakhir (kalau ada) supaya penyebab masalah bisa disalin.
class _ErrorReport extends StatelessWidget {
  const _ErrorReport();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String?>(
      valueListenable: ErrorLog.last,
      builder: (context, text, _) {
        if (text == null || text.isEmpty) return const SizedBox.shrink();
        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: kRed.withOpacity(0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: kRed.withOpacity(0.4)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                ErrorLog.autoDisabledService
                    ? 'Crash terdeteksi — mode latar belakang dimatikan otomatis'
                    : 'Laporan error terakhir',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const SizedBox(height: 6),
              Text(
                text,
                maxLines: 16,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white70, fontSize: 10, fontFamily: 'monospace'),
              ),
              Row(
                children: [
                  TextButton(
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: text));
                      if (context.mounted) {
                        ScaffoldMessenger.of(context)
                          ..hideCurrentSnackBar()
                          ..showSnackBar(const SnackBar(content: Text('Laporan error disalin')));
                      }
                    },
                    child: const Text('Salin', style: TextStyle(fontSize: 12)),
                  ),
                  TextButton(
                    onPressed: ErrorLog.clear,
                    child: const Text('Tutup', style: TextStyle(color: kMuted, fontSize: 12)),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
