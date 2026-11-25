import 'package:flutter/material.dart';

import '../nav.dart';
import '../services/build_controller.dart';
import '../services/session_manager.dart';
import 'build_zip_screen.dart';

class BuildFlutterScreen extends StatelessWidget {
  const BuildFlutterScreen({super.key, required this.session, required this.controller, this.initialZipPath});
  final SessionManager session;
  final BuildController controller;
  final String? initialZipPath;

  @override
  Widget build(BuildContext context) {
    return BuildZipScreen(
      session: session,
      controller: controller,
      title: 'Build Flutter',
      typeKey: AppNav.buildFlutter,
      label: 'Flutter',
      initialZipPath: initialZipPath,
      defaultWorkflowName: 'build_flutter.yml',
    );
  }
}
