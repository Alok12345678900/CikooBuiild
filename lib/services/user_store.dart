import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config.dart';
import 'github_uploader.dart';

class UserRecord {
  const UserRecord({required this.name, required this.credit, required this.lastCheckIn});

  final String name;
  final int credit;
  final String lastCheckIn;
}

class InsufficientCreditException implements Exception {
  InsufficientCreditException(this.credit);
  final int credit;

  @override
  String toString() =>
      'Credit tidak cukup (sisa $credit). Lakukan check-in harian di tab Profil untuk menambah credit.';
}

class AlreadyCheckedInException implements Exception {
  @override
  String toString() => 'Check-in hari ini sudah dilakukan. Kembali lagi besok.';
}

/// Credit pengguna yang sedang masuk (dipakai UI).
class CreditState {
  static final ValueNotifier<int?> credit = ValueNotifier<int?>(null);
  static final ValueNotifier<String> lastCheckIn = ValueNotifier<String>('');
  static final ValueNotifier<String> today = ValueNotifier<String>('');

  static void set(UserRecord r, {String? serverToday}) {
    credit.value = r.credit;
    lastCheckIn.value = r.lastCheckIn;
    if (serverToday != null) today.value = serverToday;
  }

  static void clear() {
    credit.value = null;
    lastCheckIn.value = '';
  }
}

class _Snapshot {
  _Snapshot(this.users, this.sha, this.today);
  final Map<String, dynamic> users;
  final String? sha;
  final String today;
}

class _Out<T> {
  _Out(this.value, {required this.write});
  final T value;
  final bool write;
}

/// Data pengguna di GitHub (user.json): hanya nama, credit, dan tanggal check-in terakhir.
/// Update memakai SHA file (optimistic locking) dengan percobaan ulang saat bentrok.
class UserStore {
  UserStore(this.token);

  final String token;

  static const int _maxTries = 6;

  Map<String, String> get _headers => {
        'Authorization': 'Bearer $token',
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
      };

  Uri get _fileUri => Uri.https(
        'api.github.com',
        '/repos/${AppConfig.repoOwner}/${AppConfig.repoName}/contents/${AppConfig.usersFile}',
      );

  static String _ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Tanggal hari ini menurut server GitHub (tidak bisa dimanipulasi lewat jam HP).
  String _today(http.Response res) {
    try {
      final d = res.headers['date'];
      if (d != null) return _ymd(HttpDate.parse(d).toUtc());
    } catch (_) {}
    return _ymd(DateTime.now().toUtc());
  }

  Future<_Snapshot> _load() async {
    var res = await http.get(_fileUri, headers: _headers).timeout(const Duration(seconds: 20));

    if (res.statusCode == 404) {
      final repo = await http
          .get(Uri.https('api.github.com', '/repos/${AppConfig.repoOwner}/${AppConfig.repoName}'),
              headers: _headers)
          .timeout(const Duration(seconds: 20));
      if (repo.statusCode == 404) {
        await GitHubUploader(token, AppConfig.repoOwner, AppConfig.repoName).ensureRepoExists();
        res = await http.get(_fileUri, headers: _headers).timeout(const Duration(seconds: 20));
      }
    }

    final today = _today(res);
    if (res.statusCode == 404) return _Snapshot(<String, dynamic>{}, null, today);
    if (res.statusCode == 401 || res.statusCode == 403) {
      throw Exception('Token GitHub di config.dart tidak valid atau tidak punya izin (HTTP ${res.statusCode}).');
    }
    if (res.statusCode != 200) {
      throw Exception('Gagal membaca data pengguna (HTTP ${res.statusCode}).');
    }

    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final raw = utf8.decode(base64.decode((body['content'] as String).replaceAll('\n', '')));
    final users = <String, dynamic>{};
    if (raw.trim().isNotEmpty) {
      final data = jsonDecode(raw);
      if (data is Map && data['users'] is Map) {
        users.addAll(Map<String, dynamic>.from(data['users'] as Map));
      }
    }
    return _Snapshot(users, body['sha'] as String?, today);
  }

  Future<T> _mutate<T>(String message, _Out<T> Function(Map<String, dynamic> users, String today) fn) async {
    for (var i = 0; i < _maxTries; i++) {
      final snap = await _load();
      final out = fn(snap.users, snap.today);
      if (!out.write) return out.value;

      final content = base64.encode(utf8.encode(const JsonEncoder.withIndent('  ').convert({'users': snap.users})));
      final res = await http
          .put(
            _fileUri,
            headers: {..._headers, 'Content-Type': 'application/json'},
            body: jsonEncode({'message': message, 'content': content, if (snap.sha != null) 'sha': snap.sha}),
          )
          .timeout(const Duration(seconds: 25));

      if (res.statusCode == 200 || res.statusCode == 201) return out.value;
      if (res.statusCode == 409 || res.statusCode == 422) {
        await Future<void>.delayed(Duration(milliseconds: 400 + i * 350));
        continue;
      }
      throw Exception('Gagal menyimpan data pengguna (HTTP ${res.statusCode}).');
    }
    throw Exception('Gagal menyimpan data pengguna: terlalu banyak bentrok, coba lagi.');
  }

  UserRecord _rec(Map<dynamic, dynamic> m) => UserRecord(
        name: m['name']?.toString() ?? 'Pengguna',
        credit: (m['credit'] as num?)?.toInt() ?? 0,
        lastCheckIn: m['lastCheckIn']?.toString() ?? '',
      );

  /// Buat pengguna baru (credit awal) bila belum ada.
  Future<UserRecord> ensureUser(String key, String name) async {
    String today = '';
    final r = await _mutate<UserRecord>('Ciko: pengguna', (users, t) {
      today = t;
      final cur = users[key];
      if (cur is Map) return _Out(_rec(cur), write: false);
      users[key] = {'name': name, 'credit': AppConfig.startCredits, 'lastCheckIn': ''};
      return _Out(UserRecord(name: name, credit: AppConfig.startCredits, lastCheckIn: ''), write: true);
    });
    CreditState.set(r, serverToday: today);
    return r;
  }

  Future<UserRecord?> read(String key) async {
    final snap = await _load();
    final cur = snap.users[key];
    if (cur is! Map) return null;
    final r = _rec(cur);
    CreditState.set(r, serverToday: snap.today);
    return r;
  }

  Future<UserRecord> checkIn(String key) async {
    String today = '';
    final r = await _mutate<UserRecord>('Ciko: check-in', (users, t) {
      today = t;
      final cur = users[key];
      if (cur is! Map) throw Exception('Data pengguna tidak ditemukan. Masuk ulang.');
      final rec = _rec(cur);
      if (rec.lastCheckIn == t) throw AlreadyCheckedInException();
      final next = UserRecord(name: rec.name, credit: rec.credit + AppConfig.dailyCheckInCredits, lastCheckIn: t);
      users[key] = {'name': next.name, 'credit': next.credit, 'lastCheckIn': next.lastCheckIn};
      return _Out(next, write: true);
    });
    CreditState.set(r, serverToday: today);
    return r;
  }

  Future<UserRecord> spend(String key, int amount) async {
    final r = await _mutate<UserRecord>('Ciko: credit', (users, t) {
      final cur = users[key];
      if (cur is! Map) throw Exception('Data pengguna tidak ditemukan. Masuk ulang.');
      final rec = _rec(cur);
      if (rec.credit < amount) throw InsufficientCreditException(rec.credit);
      final next = UserRecord(name: rec.name, credit: rec.credit - amount, lastCheckIn: rec.lastCheckIn);
      users[key] = {'name': next.name, 'credit': next.credit, 'lastCheckIn': next.lastCheckIn};
      return _Out(next, write: true);
    });
    CreditState.set(r);
    return r;
  }

  Future<void> refund(String key, int amount) async {
    try {
      final r = await _mutate<UserRecord>('Ciko: credit', (users, t) {
        final cur = users[key];
        if (cur is! Map) return _Out(const UserRecord(name: '', credit: 0, lastCheckIn: ''), write: false);
        final rec = _rec(cur);
        final next = UserRecord(name: rec.name, credit: rec.credit + amount, lastCheckIn: rec.lastCheckIn);
        users[key] = {'name': next.name, 'credit': next.credit, 'lastCheckIn': next.lastCheckIn};
        return _Out(next, write: true);
      });
      if (r.name.isNotEmpty) CreditState.set(r);
    } catch (e) {
      debugPrint('Refund credit gagal: $e');
    }
  }

  Future<void> rename(String key, String name) async {
    await _mutate<bool>('Ciko: profil', (users, t) {
      final cur = users[key];
      if (cur is! Map) return _Out(false, write: false);
      users[key] = {'name': name, 'credit': (cur['credit'] as num?)?.toInt() ?? 0, 'lastCheckIn': cur['lastCheckIn'] ?? ''};
      return _Out(true, write: true);
    });
  }

  /// Peta kunci → nama (untuk tab Status).
  Future<Map<String, String>> names() async {
    final snap = await _load();
    return {
      for (final e in snap.users.entries)
        e.key: (e.value is Map ? (e.value['name']?.toString() ?? 'Pengguna') : 'Pengguna'),
    };
  }
}
