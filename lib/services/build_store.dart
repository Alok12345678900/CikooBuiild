import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/build_record.dart';

class BuildStore {
  static const String _kCurrent = 'current_build';
  static const String _kHistory = 'build_history';
  static const int _maxHistory = 50;

  /// Hanya N riwayat teratas yang menyimpan detail job/step + log (hemat penyimpanan).
  static const int _keepDetailFor = 8;

  static Future<SharedPreferences> _fresh() async {
    final p = await SharedPreferences.getInstance();
    await p.reload();
    return p;
  }

  // Tiap build aktif disimpan di key sendiri (active_build_<id>) sehingga UI dan service
  // latar belakang tidak saling menimpa saat banyak build berjalan bersamaan.
  static const String _kActivePrefix = 'active_build_';

  static Future<List<BuildRecord>> loadActive() async {
    final p = await _fresh();

    // Migrasi dari format lama (satu build).
    final legacy = p.getString(_kCurrent);
    if (legacy != null) {
      try {
        final r = BuildRecord.fromJson(jsonDecode(legacy) as Map<String, dynamic>);
        if (!r.isFinished) await p.setString('$_kActivePrefix${r.id}', legacy);
      } catch (_) {}
      await p.remove(_kCurrent);
    }

    final out = <BuildRecord>[];
    for (final k in p.getKeys().toList()) {
      if (!k.startsWith(_kActivePrefix)) continue;
      final raw = p.getString(k);
      if (raw == null) continue;
      try {
        out.add(BuildRecord.fromJson(jsonDecode(raw) as Map<String, dynamic>));
      } catch (_) {
        await p.remove(k);
      }
    }
    out.sort((a, b) => a.startedAt.compareTo(b.startedAt));
    return out;
  }

  static Future<void> upsertActive(BuildRecord r) async {
    final p = await SharedPreferences.getInstance();
    await p.setString('$_kActivePrefix${r.id}', jsonEncode(r.toJson()));
  }

  /// Dipakai tracker: hanya memperbarui kalau build masih aktif (tidak menghidupkan lagi
  /// build yang sudah dibatalkan / selesai).
  static Future<void> updateActiveIfPresent(BuildRecord r) async {
    final p = await _fresh();
    final key = '$_kActivePrefix${r.id}';
    if (p.containsKey(key)) {
      await p.setString(key, jsonEncode(r.toJson()));
    }
  }

  static Future<void> removeActive(String id) async {
    final p = await SharedPreferences.getInstance();
    await p.remove('$_kActivePrefix$id');
  }

  static Future<List<BuildRecord>> loadHistory() async {
    final raw = (await _fresh()).getString(_kHistory);
    if (raw == null) return [];
    try {
      final list = (jsonDecode(raw) as List)
          .map((e) => BuildRecord.fromJson(e as Map<String, dynamic>))
          .toList();
      list.sort((a, b) => b.startedAt.compareTo(a.startedAt));
      return list;
    } catch (_) {
      return [];
    }
  }

  /// Menyimpan / memperbarui riwayat. Record dengan id sama akan diganti.
  static Future<void> appendHistory(BuildRecord r) async {
    final list = await loadHistory();
    list.removeWhere((e) => e.id == r.id);
    list.add(r);
    list.sort((a, b) => b.startedAt.compareTo(a.startedAt));

    final trimmed = <BuildRecord>[];
    for (var i = 0; i < list.length && i < _maxHistory; i++) {
      final item = list[i];
      trimmed.add(i < _keepDetailFor ? item : item.copyWith(jobs: const [], logTail: '', uploadLog: ''));
    }

    final p = await SharedPreferences.getInstance();
    await p.setString(
      _kHistory,
      jsonEncode(trimmed.map((e) => e.toJson()).toList()),
    );
  }


  /// Menimpa seluruh riwayat (dipakai saat membersihkan cache).
  static Future<void> saveHistory(List<BuildRecord> list) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kHistory, jsonEncode(list.map((e) => e.toJson()).toList()));
  }
}
