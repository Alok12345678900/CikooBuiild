import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';

/// Utilitas bersama Analyzer & Customizer untuk membaca project dari file ZIP.

const List<String> _ignoredDirs = [
  '/build/',
  '/.git/',
  '/node_modules/',
  '/.dart_tool/',
  '/.gradle/',
  '/.idea/',
  '/__macosx/',
];

bool isIgnoredPath(String path) {
  final p = '/${path.toLowerCase()}';
  for (final d in _ignoredDirs) {
    if (p.contains(d)) return true;
  }
  return false;
}

bool isNamed(String path, String name) => path == name || path.endsWith('/$name');

String dirOf(String p) {
  final i = p.lastIndexOf('/');
  return i < 0 ? '' : p.substring(0, i + 1);
}

int depthOf(String p) => '/'.allMatches(p).length;

String textOf(ArchiveFile f) => utf8.decode(f.content as List<int>, allowMalformed: true);

class ProjectInfo {
  const ProjectInfo({
    required this.kind,
    required this.root,
    required this.androidRoot,
    required this.appModule,
  });

  /// flutter | android | capacitor | unknown
  final String kind;

  /// Awalan folder root project di dalam ZIP (berakhiran '/' atau kosong).
  final String root;
  final String androidRoot;

  /// Awalan modul aplikasi Android, mis. 'proj/android/app/'.
  final String appModule;
}

class ZipProject {
  ZipProject._(this.files, this.info);

  final Map<String, ArchiveFile> files;
  final ProjectInfo info;

  static ZipProject open(String zipPath) {
    final bytes = File(zipPath).readAsBytesSync();
    final archive = ZipDecoder().decodeBytes(bytes);
    final files = <String, ArchiveFile>{};
    for (final f in archive) {
      if (!f.isFile) continue;
      final name = f.name.replaceAll('\\', '/');
      if (isIgnoredPath(name)) continue;
      files[name] = f;
    }
    return ZipProject._(files, detect(files));
  }

  String? text(String path) {
    final f = files[path];
    return f == null ? null : textOf(f);
  }

  static String? _shallowest(Iterable<String> paths, bool Function(String) test) {
    String? best;
    for (final p in paths) {
      if (!test(p)) continue;
      if (best == null || depthOf(p) < depthOf(best)) best = p;
    }
    return best;
  }

  static ProjectInfo detect(Map<String, ArchiveFile> files) {
    var kind = 'unknown';
    var root = '';
    var androidRoot = '';

    final pub = _shallowest(files.keys, (p) =>
        isNamed(p, 'pubspec.yaml') && !p.contains('/ios/') && !p.contains('/android/'));
    if (pub != null) {
      kind = 'flutter';
      root = dirOf(pub);
      androidRoot = '${root}android/';
    } else {
      final st = _shallowest(files.keys,
          (p) => isNamed(p, 'settings.gradle') || isNamed(p, 'settings.gradle.kts'));
      if (st != null) {
        kind = 'android';
        root = dirOf(st);
        androidRoot = root;
      } else {
        final cap = _shallowest(files.keys,
            (p) => isNamed(p, 'capacitor.config.json') || isNamed(p, 'capacitor.config.ts'));
        if (cap != null) {
          kind = 'capacitor';
          root = dirOf(cap);
          androidRoot = '${root}android/';
        }
      }
    }

    const tail = 'src/main/AndroidManifest.xml';
    var appModule = '';
    final manifests = files.keys
        .where((p) => p.startsWith(androidRoot) && p.endsWith('/$tail'))
        .toList()
      ..sort((a, b) => depthOf(a).compareTo(depthOf(b)));
    for (final m in manifests) {
      final mod = m.substring(0, m.length - tail.length);
      final g = files['${mod}build.gradle'] ?? files['${mod}build.gradle.kts'];
      if (g == null) continue;
      final t = textOf(g);
      if (t.contains('com.android.application') || t.contains('applicationId')) {
        appModule = mod;
        break;
      }
    }
    if (appModule.isEmpty && manifests.isNotEmpty) {
      appModule = manifests.first.substring(0, manifests.first.length - tail.length);
    }

    return ProjectInfo(kind: kind, root: root, androidRoot: androidRoot, appModule: appModule);
  }

  String? appGradlePath() {
    final m = info.appModule;
    if (files.containsKey('${m}build.gradle')) return '${m}build.gradle';
    if (files.containsKey('${m}build.gradle.kts')) return '${m}build.gradle.kts';
    return null;
  }

  static String? gradleValue(String gradle, String key) {
    final m = RegExp('$key\\s*=?\\s*[\'"]([^\'"]+)[\'"]').firstMatch(gradle);
    return m?.group(1);
  }
}
