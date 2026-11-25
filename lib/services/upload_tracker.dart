import 'dart:async';

import 'package:flutter/foundation.dart';

/// Status tahap UPLOAD ke GitHub (ZIP, workflow, commit, trigger), dipisah dari progress BUILD.
class UploadTracker extends ChangeNotifier {
  String title = '';
  List<String> steps = [];
  int current = -1;

  /// 0..1 untuk tahap yang sedang berjalan; null = tahap tanpa persen (indeterminate).
  double? stepFraction;
  String detail = '';
  String? error;
  bool done = false;

  Timer? _hideTimer;
  int _lastNotifyMs = 0;
  int _lastLoggedPct = -10;

  /// Info proses (type, owner, repo, mode, workflow) untuk kartu progress gabungan.
  Map<String, String> meta = const {};

  /// Log upload bergaya terminal.
  final List<String> logLines = [];

  void log(String line) {
    final t = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    logLines.add('[${two(t.hour)}:${two(t.minute)}:${two(t.second)}] $line');
    if (logLines.length > 200) logLines.removeAt(0);
  }

  bool get visible => steps.isNotEmpty;
  bool get active => visible && error == null && !done;

  /// Persen keseluruhan upload (0..1).
  double get overall {
    if (steps.isEmpty) return 0;
    if (done) return 1;
    if (current < 0) return 0;
    final f = stepFraction ?? 0;
    return ((current + f) / steps.length).clamp(0.0, 1.0);
  }

  void begin(String title, List<String> steps, {Map<String, String>? meta}) {
    _hideTimer?.cancel();
    this.meta = meta ?? const {};
    logLines.clear();
    _lastLoggedPct = -10;
    this.title = title;
    this.steps = List<String>.from(steps);
    current = -1;
    stepFraction = null;
    detail = '';
    error = null;
    done = false;
    log('\$ ciko upload $title');
    notifyListeners();
  }

  void startStep(int index, {String detail = '', bool withPercent = false}) {
    current = index;
    stepFraction = withPercent ? 0 : null;
    this.detail = detail;
    _lastLoggedPct = -10;
    if (index >= 0 && index < steps.length) {
      log('\$ ${steps[index]}${detail.isEmpty ? '' : ' — $detail'}');
    }
    notifyListeners();
  }

  /// Update persen tahap berjalan (dibatasi supaya UI tidak dibanjiri rebuild).
  void setFraction(double fraction, String detail) {
    stepFraction = fraction.clamp(0.0, 1.0);
    this.detail = detail;
    final pct = (stepFraction! * 100).floor();
    if (pct >= _lastLoggedPct + 10) {
      _lastLoggedPct = pct;
      log('  $detail ($pct%)');
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastNotifyMs >= 120 || fraction >= 1.0) {
      _lastNotifyMs = now;
      notifyListeners();
    }
  }

  void complete() {
    done = true;
    current = steps.length;
    stepFraction = 1;
    detail = 'Upload selesai, build dimulai';
    log('✓ Upload selesai, memicu workflow');
    notifyListeners();
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 5), dismiss);
  }

  void fail(String message) {
    error = message;
    log('✗ $message');
    notifyListeners();
  }

  void dismiss() {
    _hideTimer?.cancel();
    logLines.clear();
    steps = [];
    current = -1;
    stepFraction = null;
    detail = '';
    error = null;
    done = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }
}
