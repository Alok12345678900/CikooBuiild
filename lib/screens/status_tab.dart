import 'dart:async';

import 'package:flutter/material.dart';

import '../nav.dart';
import '../services/global_status_service.dart';
import '../services/session_manager.dart';
import '../theme.dart';
import '../config.dart';

const Color _kAmber = Color(0xFFFFC107);
const Color _kBlue = Color(0xFF42A5F5);

/// Status build SEMUA pengguna app: nama GitHub + berhasil / gagal / antrian / berjalan.
class StatusTab extends StatefulWidget {
  const StatusTab({super.key, required this.session});
  final SessionManager session;

  @override
  State<StatusTab> createState() => _StatusTabState();
}

class _StatusTabState extends State<StatusTab> {
  GlobalStatusService? _service;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final token = await widget.session.getToken();
    if (token.isEmpty || !mounted) return;
    final svc = GlobalStatusService(token: token);
    svc.addListener(() {
      if (mounted) setState(() {});
    });
    setState(() => _service = svc);

    // Progress build pengguna lain diperbarui otomatis saat tab Status sedang dibuka.
    _timer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (AppNav.tabIndex.value == AppNav.statusTab && !svc.loading && svc.hasActive) {
        svc.refreshActive();
      }
    });
    await svc.load();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _service?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final svc = _service;
    final me = widget.session.displayName.toLowerCase();

    return RefreshIndicator(
      onRefresh: () async => svc?.load(),
      color: kRed,
      backgroundColor: kCard,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Status Build', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(
            svc == null
                ? 'Memuat...'
                : 'Semua pengguna ${AppConfig.appName} • ${svc.users.length} pengguna',
            style: const TextStyle(color: kMuted, fontSize: 12),
          ),
          const SizedBox(height: 16),

          if (svc == null)
            const Padding(
              padding: EdgeInsets.only(top: 48),
              child: Center(child: CircularProgressIndicator(color: kRed)),
            )
          else ...[
            _totals(svc),
            const SizedBox(height: 12),
            if (svc.loading) ...[
              LinearProgressIndicator(
                value: svc.totalRepos == 0 ? null : svc.doneRepos / svc.totalRepos,
                color: kRed,
                backgroundColor: kBorder,
                minHeight: 4,
              ),
              const SizedBox(height: 6),
              Text(
                svc.totalRepos == 0
                    ? svc.phase
                    : '${svc.phase} ${svc.doneRepos}/${svc.totalRepos}',
                style: const TextStyle(color: kMuted, fontSize: 11),
              ),
              const SizedBox(height: 12),
            ],
            if (svc.error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(svc.error!, style: const TextStyle(color: kRed, fontSize: 12)),
              ),
            for (final u in svc.users) _userCard(u, u.login.toLowerCase() == me),
            if (!svc.loading && svc.users.isEmpty && svc.error == null)
              const Padding(
                padding: EdgeInsets.only(top: 32),
                child: Center(
                  child: Text(
                    'Belum ada data build pengguna.',
                    style: TextStyle(color: kMuted, fontSize: 13),
                  ),
                ),
              ),
            if (svc.updatedAt != null)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  '100 build terbaru dari semua pengguna. Tarik ke bawah untuk memuat ulang.',
                  style: TextStyle(color: kMuted, fontSize: 10),
                  textAlign: TextAlign.center,
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _totals(GlobalStatusService s) {
    return Card(
      color: kCard,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: kBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _stat('Berhasil', s.totalSuccess, kGreen),
            _stat('Gagal', s.totalFailure, kRed),
            _stat('Antrian', s.totalQueued, _kAmber),
            _stat('Berjalan', s.totalRunning, _kBlue),
          ],
        ),
      ),
    );
  }

  Widget _stat(String label, int n, Color color) {
    return Column(
      children: [
        Text('$n', style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 22)),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(color: kMuted, fontSize: 11)),
      ],
    );
  }

  Widget _userCard(UserBuildStats u, bool mine) {
    return Card(
      color: kCard,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: mine ? kRed.withOpacity(0.6) : kBorder),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: null,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.person, size: 18, color: Colors.white),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      u.login,
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (mine)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: kRed.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text('Kamu', style: TextStyle(color: kRed, fontSize: 10)),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _chip('Berhasil', u.success, kGreen),
                  _chip('Gagal', u.failure, kRed),
                  _chip('Antrian', u.queued, _kAmber),
                  _chip('Berjalan', u.running, _kBlue),
                ],
              ),
              for (final run in u.active) _activeRow(run),
            ],
          ),
        ),
      ),
    );
  }

  /// Progress build yang sedang berjalan / antri milik pengguna ini.
  Widget _activeRow(ActiveRun run) {
    final color = run.queued ? _kAmber : _kBlue;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  run.name,
                  style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(run.queued ? 'Antri' : '${run.percent}%',
                  style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 6),
          LinearProgressIndicator(
            value: run.queued ? null : run.percent / 100,
            color: color,
            backgroundColor: kBorder,
            minHeight: 5,
            borderRadius: BorderRadius.circular(3),
          ),
          const SizedBox(height: 4),
          Text(run.step, style: const TextStyle(color: kMuted, fontSize: 10), overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }

  Widget _chip(String label, int n, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(n > 0 ? 0.15 : 0.05),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '$label $n',
        style: TextStyle(
          color: n > 0 ? color : kMuted,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
