import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'project_zip.dart';

const Set<String> _textExt = {
  'kt', 'java', 'xml', 'gradle', 'kts', 'pro', 'properties', 'json', 'dart', 'plist',
  'pbxproj', 'xcconfig', 'yaml', 'yml', 'txt', 'md', 'html', 'js', 'ts', 'toml', 'cfg',
};

const Set<String> _domainExt = {
  ..._textExt,
  'css', 'scss', 'tsx', 'jsx', 'mjs', 'cjs', 'php', 'env', 'ini', 'conf', 'svg', 'vue',
  'swift', 'm', 'h', 'cpp', 'c', 'csv', 'rc', 'sh', 'bat', 'htm', 'jsp', 'py', 'rb', 'go',
};

bool _isTextForDomain(String p) {
  final i = p.lastIndexOf('.');
  if (i < 0) return false;
  return _domainExt.contains(p.substring(i + 1).toLowerCase());
}

const Set<String> _protectedHosts = {
  'schemas.android.com', 'www.w3.org', 'schemas.microsoft.com', 'xmlns.com', 'ns.adobe.com',
  'www.apache.org', 'maven.google.com', 'dl.google.com', 'repo.maven.apache.org', 'repo1.maven.org',
  'plugins.gradle.org', 'services.gradle.org', 'jitpack.io', 'developer.android.com', 'dart.dev',
  'pub.dev', 'flutter.dev', 'storage.googleapis.com', 'maven-central.storage-download.googleapis.com',
  'xmlpull.org',
};

bool _isProtectedHost(String h) => _protectedHosts.contains(h) || h.endsWith('.gradle.org');

bool _isText(String p) {
  final i = p.lastIndexOf('.');
  if (i < 0) return false;
  return _textExt.contains(p.substring(i + 1).toLowerCase());
}

String _attrEsc(String s) =>
    s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('"', '&quot;');

String _strEsc(String s) {
  var r = s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll("'", "\\'");
  if (r.startsWith('@') || r.startsWith('?')) r = '\\$r';
  return r;
}

String _snake(String s) {
  var r = s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
  r = r.replaceAll(RegExp(r'_+'), '_').replaceAll(RegExp(r'^_|_$'), '');
  if (r.isEmpty) r = 'app';
  if (!RegExp(r'^[a-z]').hasMatch(r)) r = 'app_$r';
  return r;
}

String? _oldLabel(ZipProject zp) {
  final info = zp.info;
  final mt = zp.text('${info.appModule}src/main/AndroidManifest.xml');
  if (mt == null) return null;
  final m = RegExp(r'<application[^>]*?android:label="([^"]*)"').firstMatch(mt);
  if (m == null) return null;
  final v = m.group(1)!;
  if (v.startsWith('@string/')) {
    final key = v.substring(8);
    final strings = zp.text('${info.appModule}src/main/res/values/strings.xml');
    if (strings == null) return null;
    final s = RegExp('<string\\s+name="$key"[^>]*>([\\s\\S]*?)</string>').firstMatch(strings);
    return s?.group(1)?.replaceAll("\\'", "'").replaceAll('&amp;', '&');
  }
  return v;
}

/// Baca info dasar project untuk ditampilkan sebelum diubah.
Map<String, dynamic> scanProjectZip(String zipPath) {
  final zp = ZipProject.open(zipPath);
  final info = zp.info;
  final gradlePath = zp.appGradlePath();
  final gradle = gradlePath == null ? '' : (zp.text(gradlePath) ?? '');
  final mt = zp.text('${info.appModule}src/main/AndroidManifest.xml') ?? '';
  String? pubName;
  if (info.kind == 'flutter') {
    final pub = zp.text('${info.root}pubspec.yaml') ?? '';
    pubName = RegExp(r'^name:\s*([A-Za-z0-9_]+)', multiLine: true).firstMatch(pub)?.group(1);
  }
  return {
    'kind': info.kind,
    'appId': ZipProject.gradleValue(gradle, 'applicationId'),
    'namespace': ZipProject.gradleValue(gradle, 'namespace') ??
        RegExp(r'<manifest[^>]*?package="([^"]+)"').firstMatch(mt)?.group(1),
    'label': _oldLabel(zp),
    'pubName': pubName,
    'hasAndroid': info.appModule.isNotEmpty,
  };
}

/// Terapkan perubahan lalu tulis ZIP baru. Berjalan di isolate.
/// Argumen: zip, out, newName?, newPackage?, renameProject, icons? (Map<String,Uint8List>).
Map<String, dynamic> customizeProjectZip(Map<String, dynamic> a) {
  final zipPath = a['zip'] as String;
  final outPath = a['out'] as String;
  final newName = (a['newName'] as String?)?.trim();
  final newPkg = (a['newPackage'] as String?)?.trim();
  final renameProject = a['renameProject'] == true;
  final iconsRaw = a['icons'];
  final icons = iconsRaw is Map ? iconsRaw.map((k, v) => MapEntry(k.toString(), v as Uint8List)) : null;

  final changes = <String>[];
  final zp = ZipProject.open(zipPath);
  final info = zp.info;
  final files = zp.files;

  if (info.kind == 'unknown') {
    return {'ok': false, 'error': 'Project tidak dikenali (butuh pubspec.yaml / settings.gradle).'};
  }

  final texts = <String, String>{};
  final dirty = <String>{};
  final renames = <String, String>{};
  final deletes = <String>{};
  final extras = <String, List<int>>{};

  String? readText(String path) {
    final c = texts[path];
    if (c != null) return c;
    final f = files[path];
    if (f == null) return null;
    final t = textOf(f);
    texts[path] = t;
    return t;
  }

  void writeText(String path, String t) {
    texts[path] = t;
    dirty.add(path);
  }

  final gradlePath = zp.appGradlePath();
  final gradle = gradlePath == null ? '' : (zp.text(gradlePath) ?? '');
  final manifestPath = '${info.appModule}src/main/AndroidManifest.xml';
  final manifestText = zp.text(manifestPath) ?? '';
  final appId = ZipProject.gradleValue(gradle, 'applicationId');
  final ns = ZipProject.gradleValue(gradle, 'namespace');
  final manifestPkg = RegExp(r'<manifest[^>]*?package="([^"]+)"').firstMatch(manifestText)?.group(1);
  final oldNs = ns ?? appId ?? manifestPkg;
  final oldAppId = appId ?? oldNs;
  final oldLabel = _oldLabel(zp);

  if (newPkg != null && newPkg.isNotEmpty) {
    if (!RegExp(r'^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$').hasMatch(newPkg)) {
      return {
        'ok': false,
        'error': 'Package "$newPkg" tidak valid. Contoh: com.nama.aplikasi (huruf kecil, minimal 2 bagian).'
      };
    }
    if (oldNs == null || oldAppId == null) {
      return {'ok': false, 'error': 'Package lama tidak terdeteksi di build.gradle / AndroidManifest.xml.'};
    }
    final tokens = <String>{oldNs, oldAppId}.where((t) => t != newPkg).toList()
      ..sort((x, y) => y.length.compareTo(x.length));
    var replacedFiles = 0;
    if (tokens.isNotEmpty) {
      final regs = tokens
          .map((t) => RegExp('(?<![A-Za-z0-9_.])${RegExp.escape(t)}(?![A-Za-z0-9_])'))
          .toList();
      for (final path in files.keys.toList()) {
        if (!_isText(path) || files[path]!.size > 3000000) continue;
        final t = readText(path);
        if (t == null) continue;
        var r = t;
        for (final re in regs) {
          r = r.replaceAll(re, newPkg);
        }
        if (r != t) {
          writeText(path, r);
          replacedFiles++;
        }
      }
      // Pindahkan folder sumber Kotlin/Java sesuai namespace.
      final oldDir = oldNs.replaceAll('.', '/');
      final newDir = newPkg.replaceAll('.', '/');
      final moveRe = RegExp('^((?:.*?/)?src/[^/]+/(?:java|kotlin)/)${RegExp.escape(oldDir)}/(.*)\$');
      var moved = 0;
      for (final path in files.keys) {
        final m = moveRe.firstMatch(path);
        if (m != null) {
          renames[path] = '${m.group(1)}$newDir/${m.group(2)}';
          moved++;
        }
      }
      changes.add('Package $oldNs → $newPkg ($replacedFiles file diperbarui, $moved file sumber dipindah)');
      if (oldAppId != oldNs) changes.add('applicationId $oldAppId → $newPkg');
    } else {
      changes.add('Package sudah $newPkg (tidak ada perubahan)');
    }
  }

  if (newName != null && newName.isNotEmpty) {
    var touched = 0;
    final manifests = files.keys
        .where((p) => p.startsWith(info.androidRoot) && p.endsWith('AndroidManifest.xml'))
        .toList();
    for (final p in manifests) {
      final t = readText(p);
      if (t == null) continue;
      var r = t;
      if (oldLabel != null && !oldLabel.startsWith('@')) {
        r = r.replaceAll('android:label="${_attrEsc(oldLabel)}"', 'android:label="${_attrEsc(newName)}"');
      }
      if (p == manifestPath && !RegExp(r'<application[^>]*?android:label=').hasMatch(r)) {
        r = r.replaceFirst('<application', '<application android:label="${_attrEsc(newName)}"');
      }
      if (r != t) {
        writeText(p, r);
        touched++;
      }
    }
    final stringsFiles = files.keys
        .where((p) => p.startsWith(info.appModule) && RegExp(r'/res/values[^/]*/strings\.xml$').hasMatch(p))
        .toList();
    for (final p in stringsFiles) {
      final t = readText(p);
      if (t == null) continue;
      var r = t.replaceAllMapped(
        RegExp(r'(<string\s+name="app_name"[^>]*>)[\s\S]*?(</string>)'),
        (m) => '${m[1]}${_strEsc(newName)}${m[2]}',
      );
      if (oldLabel != null && oldLabel.isNotEmpty && !oldLabel.startsWith('@')) {
        r = r.replaceAll(
          RegExp('>\\s*${RegExp.escape(oldLabel)}\\s*</string>'),
          '>${_strEsc(newName)}</string>',
        );
      }
      if (r != t) {
        writeText(p, r);
        touched++;
      }
    }
    for (final p in files.keys.where((p) => isNamed(p, 'capacitor.config.json') || isNamed(p, 'capacitor.config.ts')).toList()) {
      final t = readText(p);
      if (t == null) continue;
      final r = p.endsWith('.json')
          ? t.replaceAllMapped(RegExp(r'("appName"\s*:\s*")[^"]*(")'), (m) => '${m[1]}${newName.replaceAll('"', '\\"')}${m[2]}')
          : t.replaceAllMapped(RegExp(r'''(appName\s*:\s*['"])[^'"]*(['"])'''), (m) => '${m[1]}$newName${m[2]}');
      if (r != t) {
        writeText(p, r);
        touched++;
      }
    }
    changes.add('Nama aplikasi ${oldLabel == null ? '' : '"$oldLabel" '}→ "$newName" ($touched file diperbarui)');
  }

  final domainRaw = a['domainMap'];
  final domainMap = domainRaw is Map
      ? domainRaw.map((k, v) => MapEntry(k.toString().toLowerCase(), v.toString()))
      : <String, String>{};
  if (domainMap.isNotEmpty) {
    final rules = <_DomainRule>[];
    for (final e in domainMap.entries) {
      final sep = e.key.indexOf('://');
      if (sep < 0) continue;
      final oldScheme = e.key.substring(0, sep);
      final oldHost = e.key.substring(sep + 3);
      var nv = e.value.trim();
      String? scheme;
      final sm = RegExp(r'^(https?)://', caseSensitive: false).firstMatch(nv);
      if (sm != null) {
        scheme = sm.group(1)!.toLowerCase();
        nv = nv.substring(sm.end);
      }
      nv = nv.replaceAll(RegExp(r'/+$'), '');
      if (nv.isEmpty || RegExp(r'[\s/]').hasMatch(nv)) {
        return {'ok': false, 'error': 'Domain baru untuk ${e.key} tidak valid: "${e.value}"'};
      }
      if (nv.toLowerCase() == oldHost && (scheme == null || scheme == oldScheme)) continue;
      rules.add(_DomainRule(
        e.key,
        nv,
        scheme,
        RegExp('($oldScheme://)${RegExp.escape(oldHost)}(?![A-Za-z0-9\\-]|\\.[A-Za-z0-9])', caseSensitive: false),
      ));
    }
    for (final path in files.keys.toList()) {
      if (!_isTextForDomain(path) || files[path]!.size > 3000000) continue;
      final t = readText(path);
      if (t == null) continue;
      var r = t;
      for (final rule in rules) {
        if (!rule.re.hasMatch(r)) continue;
        rule.count += rule.re.allMatches(r).length;
        rule.files.add(path);
        r = r.replaceAllMapped(rule.re, (m) {
          final sc = rule.scheme != null ? '${rule.scheme}://' : m.group(1)!;
          return '$sc${rule.newHost}';
        });
      }
      if (r != t) writeText(path, r);
    }
    for (final rule in rules) {
      changes.add('Domain ${rule.oldHost} → ${rule.scheme == null ? '' : '${rule.scheme}://'}${rule.newHost} (${rule.count} kemunculan di ${rule.files.length} file)');
    }
    if (rules.isEmpty) changes.add('Domain: tidak ada perubahan');
  }

  String? oldRootPrefix;
  String? newRootPrefix;
  if (renameProject) {
    final base = (newName != null && newName.isNotEmpty) ? newName : 'app';
    if (info.kind == 'flutter') {
      final pubPath = '${info.root}pubspec.yaml';
      final pub = readText(pubPath);
      final oldPub = pub == null
          ? null
          : RegExp(r'^name:\s*([A-Za-z0-9_]+)', multiLine: true).firstMatch(pub)?.group(1);
      final newPub = _snake(base);
      if (pub != null && oldPub != null && oldPub != newPub) {
        writeText(pubPath, pub.replaceFirst(RegExp(r'^name:\s*[A-Za-z0-9_]+', multiLine: true), 'name: $newPub'));
        var n = 0;
        for (final p in files.keys.toList()) {
          if (!p.endsWith('.dart')) continue;
          final t = readText(p);
          if (t == null) continue;
          final r = t.replaceAll('package:$oldPub/', 'package:$newPub/');
          if (r != t) {
            writeText(p, r);
            n++;
          }
        }
        changes.add('Nama package Flutter $oldPub → $newPub ($n file Dart diperbarui)');
      }
    }
    for (final p in files.keys.where((p) => p.startsWith(info.androidRoot) && (isNamed(p, 'settings.gradle') || isNamed(p, 'settings.gradle.kts'))).toList()) {
      final t = readText(p);
      if (t == null) continue;
      final safe = base.replaceAll(RegExp(r'[^A-Za-z0-9_\- ]'), '').trim();
      final r = t.replaceAllMapped(
        RegExp(r'''rootProject\.name\s*=\s*["'][^"']*["']'''),
        (m) => 'rootProject.name = "$safe"',
      );
      if (r != t) {
        writeText(p, r);
        changes.add('rootProject.name → "$safe"');
      }
    }
    // Folder paling atas di dalam ZIP.
    if (info.root.isNotEmpty && info.root.split('/').where((e) => e.isNotEmpty).length == 1) {
      final folder = base.replaceAll(RegExp(r'[^A-Za-z0-9_\-]+'), '_');
      if (folder.isNotEmpty && '$folder/' != info.root) {
        oldRootPrefix = info.root;
        newRootPrefix = '$folder/';
        changes.add('Folder project ${info.root.replaceAll('/', '')} → $folder');
      }
    }
  }

  if (icons != null && icons.isNotEmpty) {
    if (info.appModule.isEmpty) {
      return {'ok': false, 'error': 'Modul Android tidak ditemukan, icon tidak bisa diganti.'};
    }
    final resBase = '${info.appModule}src/main/res/';
    final iconRef = RegExp(r'android:icon="@(mipmap|drawable)/([A-Za-z0-9_]+)"').firstMatch(manifestText);
    final roundRef = RegExp(r'android:roundIcon="@(mipmap|drawable)/([A-Za-z0-9_]+)"').firstMatch(manifestText);
    final iconType = iconRef?.group(1) ?? 'mipmap';
    final iconName = iconRef?.group(2) ?? 'ic_launcher';
    final roundType = roundRef?.group(1) ?? 'mipmap';
    final roundName = roundRef?.group(2) ?? 'ic_launcher_round';
    final hasRound = roundRef != null ||
        files.keys.any((p) => p.startsWith(resBase) && RegExp('/ic_launcher_round\\.').hasMatch(p));

    void removeRaster(String name, {bool xmlToo = false}) {
      final ext = xmlToo ? 'png|webp|jpg|jpeg|xml' : 'png|webp|jpg|jpeg';
      final re = RegExp('^${RegExp.escape(resBase)}(?:mipmap|drawable)[^/]*/${RegExp.escape(name)}\\.($ext)\$');
      for (final p in files.keys) {
        if (re.hasMatch(p)) deletes.add(p);
      }
    }

    const dens = ['mdpi', 'hdpi', 'xhdpi', 'xxhdpi', 'xxxhdpi'];
    var written = 0;

    removeRaster(iconName);
    for (final d in dens) {
      final b = icons['legacy_$d'];
      if (b != null) {
        extras['$resBase$iconType-$d/$iconName.png'] = b;
        written++;
      }
    }
    if (hasRound) {
      removeRaster(roundName);
      for (final d in dens) {
        final b = icons['round_$d'];
        if (b != null) {
          extras['$resBase$roundType-$d/$roundName.png'] = b;
          written++;
        }
      }
    }

    // Adaptive icon: ganti layer foreground.
    final adaptivePath = files.keys.firstWhere(
      (p) => p.startsWith(resBase) && RegExp('/(?:mipmap|drawable)[^/]*/${RegExp.escape(iconName)}\\.xml\$').hasMatch(p),
      orElse: () => '',
    );
    if (adaptivePath.isNotEmpty) {
      final xml = readText(adaptivePath) ?? '';
      final fg = RegExp(r'<foreground[\s\S]*?android:drawable="@(mipmap|drawable)/([A-Za-z0-9_]+)"').firstMatch(xml);
      if (fg != null && fg.group(2) != iconName) {
        final fgType = fg.group(1)!;
        final fgName = fg.group(2)!;
        removeRaster(fgName, xmlToo: true);
        for (final d in dens) {
          final b = icons['fg_$d'];
          if (b != null) {
            extras['$resBase$fgType-$d/$fgName.png'] = b;
            written++;
          }
        }
        changes.add('Adaptive icon: foreground "$fgName" diganti');
      }
    }
    changes.add('Icon diganti ($written file PNG ditulis, semua kepadatan layar)');
  }

  if (changes.isEmpty) {
    return {'ok': false, 'error': 'Tidak ada perubahan yang diminta.'};
  }

  final oldPre = oldRootPrefix;
  final newPre = newRootPrefix;
  String finalName(String n) {
    var x = renames[n] ?? n;
    if (oldPre != null && newPre != null && x.startsWith(oldPre)) {
      x = newPre + x.substring(oldPre.length);
    }
    return x;
  }

  final out = Archive();
  for (final e in files.entries) {
    final path = e.key;
    if (deletes.contains(path)) continue;
    final target = finalName(path);
    if (dirty.contains(path)) {
      final bytes = utf8.encode(texts[path]!);
      out.addFile(ArchiveFile(target, bytes.length, bytes));
    } else if (target != path) {
      final bytes = e.value.content as List<int>;
      out.addFile(ArchiveFile(target, bytes.length, bytes));
    } else {
      out.addFile(e.value);
    }
  }
  for (final e in extras.entries) {
    out.addFile(ArchiveFile(finalName(e.key), e.value.length, e.value));
  }

  final enc = ZipEncoder().encode(out);
  if (enc == null) return {'ok': false, 'error': 'Gagal membuat ZIP hasil.'};
  File(outPath).writeAsBytesSync(enc, flush: true);

  return {'ok': true, 'changes': changes, 'out': outPath, 'size': enc.length};
}

Future<Map<dynamic, dynamic>> runScanInIsolate(String zipPath) {
  return Isolate.run<Map<dynamic, dynamic>>(() => scanProjectZip(zipPath));
}

Future<Map<dynamic, dynamic>> runCustomizeInIsolate(Map<String, dynamic> args) {
  return Isolate.run<Map<dynamic, dynamic>>(() => customizeProjectZip(args));
}

class _DomainRule {
  _DomainRule(this.oldHost, this.newHost, this.scheme, this.re);

  final String oldHost;
  final String newHost;
  final String? scheme;
  final RegExp re;
  int count = 0;
  final Set<String> files = {};
}

/// Cari semua domain pada URL http:// atau https:// di seluruh file teks project.
List<Map<String, dynamic>> scanDomainsInZip(String zipPath) {
  final zp = ZipProject.open(zipPath);
  final re = RegExp(r'(https?)://([A-Za-z0-9][A-Za-z0-9.\-]*)', caseSensitive: false);
  final counts = <String, int>{};
  final fileSets = <String, Set<String>>{};

  for (final e in zp.files.entries) {
    final p = e.key;
    if (!_isTextForDomain(p) || e.value.size > 3000000) continue;
    final t = textOf(e.value);
    for (final m in re.allMatches(t)) {
      final scheme = m.group(1)!.toLowerCase();
      final host = m.group(2)!.toLowerCase().replaceAll(RegExp(r'[.\-]+$'), '');
      if (host.isEmpty || (!host.contains('.') && host != 'localhost')) continue;
      final key = '$scheme://$host';
      counts[key] = (counts[key] ?? 0) + 1;
      (fileSets[key] ??= <String>{}).add(p);
    }
  }

  final out = <Map<String, dynamic>>[];
  for (final e in counts.entries) {
    final sep = e.key.indexOf('://');
    final host = e.key.substring(sep + 3);
    out.add(<String, dynamic>{
      'key': e.key,
      'scheme': e.key.substring(0, sep),
      'host': host,
      'count': e.value,
      'files': fileSets[e.key]!.length,
      'protected': _isProtectedHost(host),
    });
  }
  out.sort((x, y) => (y['count'] as int).compareTo(x['count'] as int));
  return out;
}

Future<List<dynamic>> runDomainScanInIsolate(String zipPath) {
  return Isolate.run<List<dynamic>>(() => scanDomainsInZip(zipPath));
}
