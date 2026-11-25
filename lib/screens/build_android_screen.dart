import 'package:flutter/material.dart';

import '../nav.dart';
import '../services/build_controller.dart';
import '../services/session_manager.dart';
import 'build_zip_screen.dart';

class BuildAndroidScreen extends StatelessWidget {
  const BuildAndroidScreen({super.key, required this.session, required this.controller, this.initialZipPath});
  final SessionManager session;
  final BuildController controller;
  final String? initialZipPath;

  @override
  Widget build(BuildContext context) {
    return BuildZipScreen(
      session: session,
      controller: controller,
      title: 'Build Android Studio',
      typeKey: AppNav.buildAndroid,
      label: 'Android',
      initialZipPath: initialZipPath,
      defaultWorkflowName: 'build_android.yml',
    );
  }
}
