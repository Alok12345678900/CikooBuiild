import 'package:flutter/material.dart';

import '../services/build_controller.dart';
import '../theme.dart';
import '../widgets/build_progress_view.dart';

/// Halaman detail satu build dari riwayat.
class BuildDetailPage extends StatelessWidget {
  const BuildDetailPage({super.key, required this.controller, required this.recordId});

  final BuildController controller;
  final String recordId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        title: const Text('Detail Build'),
        backgroundColor: kBg,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          BuildProgressView(controller: controller, recordId: recordId, detailed: true),
        ],
      ),
    );
  }
}
