import 'package:flutter/foundation.dart';

class AppNav {
  static const int homeTab = 0;
  static const int progressTab = 1;
  static const int statusTab = 2;
  static const int historyTab = 3;
  static const int profileTab = 4;

  static const String buildAndroid = 'ANDROID';
  static const String buildFlutter = 'FLUTTER';
  static const String buildWebToApk = 'WEBTOAPK';

  static final ValueNotifier<int> tabIndex = ValueNotifier<int>(homeTab);
  static final ValueNotifier<String> buildType = ValueNotifier<String>(buildAndroid);
}
