import 'package:flutter/material.dart';

import '../services/build_controller.dart';
import '../services/log_store.dart';
import '../theme.dart';
import '../widgets/terminal_log_view.dart';

/// Log lengkap build (terminal layar penuh).
class LogViewerPage extends StatefulWidget {
  const LogViewerPage({super.key, required this.controller, required this.recordId});

  final BuildController controller;
  final String recordId;

  @override
  State<LogViewerPage> createState() => _LogViewerPageState();
}

class _LogViewerPageState extends State<LogViewerPage> {
  String? _text;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final rec = widget.controller.byId(widget.recordId);
    if (rec == null) {
      setState(() => _error = 'Data build tidak ditemukan.');
      return;
    }
    try {
      final path = await widget.controller.loadLog(rec);
      final text = await LogStore.read(path);
      if (mounted) setState(() => _text = text ?? '');
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        title: const Text('Log Build'),
        backgroundColor: kBg,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(_error!, style: const TextStyle(color: kRed), textAlign: TextAlign.center),
              ),
            )
          : _text == null
              ? const Center(child: CircularProgressIndicator(color: kRed))
              : Padding(
                  padding: const EdgeInsets.all(12),
                  child: TerminalLogView(text: _text!, title: 'log build', maxLines: 5000),
                ),
    );
  }
}
