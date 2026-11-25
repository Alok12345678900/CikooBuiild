import 'dart:io';

import 'package:flutter/material.dart';
import '../models/build_record.dart';
import '../services/build_controller.dart';
import '../theme.dart';
import '../widgets/build_progress_view.dart';
import 'build_detail_page.dart';

class HistoryTab extends StatefulWidget {
  const HistoryTab({super.key, required this.controller});

  final BuildController controller;

  @override
  State<HistoryTab> createState() => _HistoryTabState();
}

class _HistoryTabState extends State<HistoryTab> {
  int _filter = 0;

  Widget _leading(BuildRecord r) {
    if (r.hasApk && r.apkIconPath.isNotEmpty && File(r.apkIconPath).existsSync()) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.file(File(r.apkIconPath), width: 44, height: 44, fit: BoxFit.cover),
      );
    }
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(color: statusColor(r).withOpacity(0.15), shape: BoxShape.circle),
      child: Icon(
        r.isSuccess ? Icons.check : (r.status == 'cancelled' ? Icons.block : Icons.close),
        color: statusColor(r),
        size: 22,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final runningList = widget.controller.active.reversed.toList();
        final allItems = widget.controller.history;

        final items = allItems.where((r) {
          if (_filter == 1) return r.isSuccess;
          if (_filter == 2) return !r.isSuccess;
          return true;
        }).toList();

        final total = allItems.length;
        final success = allItems.where((r) => r.isSuccess).length;
        final failed = total - success;

        return RefreshIndicator(
          onRefresh: widget.controller.reload,
          color: kRed,
          backgroundColor: kCard,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                'Riwayat Build',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),

              for (final r in runningList) ...[
                BuildProgressView(controller: widget.controller, recordId: r.id),
                const SizedBox(height: 8),
              ],

              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildFilterChip('Semua', 0),
                    const SizedBox(width: 8),
                    _buildFilterChip('Berhasil', 1),
                    const SizedBox(width: 8),
                    _buildFilterChip('Gagal', 2),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              if (items.isEmpty && runningList.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 48),
                  child: Center(
                    child: Text('Belum ada riwayat build', style: TextStyle(color: kMuted)),
                  ),
                ),

              for (final r in items)
                Card(
                  color: kCard,
                  margin: const EdgeInsets.only(bottom: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: const BorderSide(color: kBorder, width: 1),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => BuildDetailPage(
                          controller: widget.controller,
                          recordId: r.id,
                        ),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          _leading(r),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  r.hasApk && r.apkLabel.isNotEmpty ? r.apkLabel : '${r.typeLabel} Build',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  r.hasApk
                                      ? [
                                          if (r.apkPackage.isNotEmpty) r.apkPackage else r.repo,
                                          if (r.apkSize > 0) formatBytes(r.apkSize),
                                        ].join(' • ')
                                      : '${r.repo} • ${r.typeLabel}',
                                  style: const TextStyle(color: kMuted, fontSize: 12),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  '${r.hasApk && r.apkVersion.isNotEmpty ? 'v${r.apkVersion} • ' : ''}${timeAgo(r.finishedAt ?? r.startedAt)} • ${formatDuration(r.elapsedMs)}',
                                  style: const TextStyle(color: kMuted, fontSize: 11),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (r.status == 'failure')
                                  Padding(
                                    padding: const EdgeInsets.only(top: 3),
                                    child: Text(
                                      r.analysisErrors.isNotEmpty
                                          ? '${r.analysisErrors.first['title']}'
                                          : (r.diagnostics.isNotEmpty ? r.diagnostics.first : r.step),
                                      style: const TextStyle(color: kRed, fontSize: 11),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          Icon(
                            r.hasApk ? Icons.download_done : Icons.chevron_right,
                            color: r.hasApk ? kGreen : kMuted,
                            size: 20,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

              if (allItems.isNotEmpty) ...[
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: kCard,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: kBorder),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.bar_chart, color: Colors.white, size: 20),
                          SizedBox(width: 8),
                          Text('Total Build', style: TextStyle(fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _buildStatRow('Total Build', total, Colors.white),
                      const SizedBox(height: 8),
                      _buildStatRow('Berhasil', success, kGreen),
                      const SizedBox(height: 8),
                      _buildStatRow('Gagal', failed, kRed),
                    ],
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildFilterChip(String label, int index) {
    final selected = _filter == index;
    return GestureDetector(
      onTap: () => setState(() => _filter = index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? kRed : kCard,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? kRed : kBorder),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : kMuted,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  Widget _buildStatRow(String label, int value, Color color) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: kMuted, fontSize: 13)),
        Text(
          value.toString(),
          style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 14),
        ),
      ],
    );
  }
}