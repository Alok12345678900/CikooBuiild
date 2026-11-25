import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Tampilan log bergaya terminal: latar gelap, monospace, warna per jenis baris,
/// auto-scroll ke bawah (berhenti saat pengguna menggulir ke atas), kursor berkedip saat berjalan.
class TerminalLogView extends StatefulWidget {
  const TerminalLogView({
    super.key,
    required this.text,
    this.running = false,
    this.height,
    this.title = 'terminal',
    this.maxLines = 500,
  });

  final String text;
  final bool running;
  final double? height;
  final String title;
  final int maxLines;

  @override
  State<TerminalLogView> createState() => _TerminalLogViewState();
}

class _TerminalLogViewState extends State<TerminalLogView> {
  final ScrollController _scroll = ScrollController();
  bool _stick = true;
  bool _cursor = true;
  Timer? _blink;

  @override
  void initState() {
    super.initState();
    _syncBlink();
    _toBottom();
  }

  @override
  void didUpdateWidget(TerminalLogView old) {
    super.didUpdateWidget(old);
    if (old.running != widget.running) _syncBlink();
    if (old.text != widget.text && _stick) _toBottom();
  }

  void _syncBlink() {
    _blink?.cancel();
    _blink = null;
    if (widget.running) {
      _blink = Timer.periodic(const Duration(milliseconds: 550), (_) {
        if (mounted) setState(() => _cursor = !_cursor);
      });
    }
  }

  void _toBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  @override
  void dispose() {
    _blink?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  List<String> _lines() {
    final out = <String>[];
    for (final raw in widget.text.split('\n')) {
      if (raw.startsWith('##[endgroup]')) continue;
      out.add(raw.replaceFirst('##[group]', '▶ ').replaceFirst('##[error]', ''));
    }
    return out.length > widget.maxLines ? out.sublist(out.length - widget.maxLines) : out;
  }

  Color _color(String l) {
    final s = l.toLowerCase();
    final t = l.trimLeft();
    if (t.startsWith('✗') ||
        s.contains('error') ||
        s.contains('failed') ||
        s.contains('exception') ||
        s.contains('failure')) {
      return const Color(0xFFFF6B6B);
    }
    if (t.startsWith('✓')) return const Color(0xFF00E676);
    if (s.contains('warning') || s.contains('warn:')) return const Color(0xFFFFC107);
    if (t.startsWith('▶')) return const Color(0xFF4FC3F7);
    if (RegExp(r'^\[\d\d:\d\d:\d\d\] \$').hasMatch(l) || l.startsWith(r'$')) return const Color(0xFF00E676);
    return const Color(0xFFC8D1CB);
  }

  @override
  Widget build(BuildContext context) {
    final lines = _lines();
    return Container(
      height: widget.height,
      decoration: BoxDecoration(
        color: const Color(0xFF0A0E0B),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF1F2A22)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: const BoxDecoration(
              color: Color(0xFF121A14),
              borderRadius: BorderRadius.vertical(top: Radius.circular(10)),
            ),
            child: Row(
              children: [
                for (final c in const [Color(0xFFFF5F56), Color(0xFFFFBD2E), Color(0xFF27C93F)])
                  Container(
                    width: 9,
                    height: 9,
                    margin: const EdgeInsets.only(right: 5),
                    decoration: BoxDecoration(color: c, shape: BoxShape.circle),
                  ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(widget.title,
                      style: const TextStyle(color: Color(0xFF7A8A7F), fontSize: 11, fontFamily: 'monospace')),
                ),
                if (widget.running)
                  const Text('● live', style: TextStyle(color: Color(0xFF00E676), fontSize: 10)),
                IconButton(
                  tooltip: 'Salin',
                  visualDensity: VisualDensity.compact,
                  iconSize: 16,
                  icon: const Icon(Icons.copy, color: Color(0xFF7A8A7F)),
                  onPressed: () => Clipboard.setData(ClipboardData(text: widget.text)),
                ),
              ],
            ),
          ),
          Expanded(
            child: NotificationListener<ScrollNotification>(
              onNotification: (n) {
                if (n.metrics.maxScrollExtent > 0) {
                  _stick = n.metrics.pixels >= n.metrics.maxScrollExtent - 24;
                }
                return false;
              },
              child: ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.all(10),
                itemCount: lines.length,
                itemBuilder: (_, i) {
                  final last = i == lines.length - 1;
                  return Text(
                    lines[i] + (last && widget.running && _cursor ? ' ▌' : ''),
                    style: TextStyle(
                      color: _color(lines[i]),
                      fontSize: 11,
                      height: 1.35,
                      fontFamily: 'monospace',
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
