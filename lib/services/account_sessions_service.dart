import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'supabase_service.dart';

/// Keeps refresh tokens only in platform secure storage; never in SharedPreferences.
class AccountSessionsService {
  AccountSessionsService._();
  static final instance = AccountSessionsService._();
  static const _storage = FlutterSecureStorage();
  static const _key = 'nali_saved_account_sessions_v1';

  Future<List<Map<String, String>>> list() async {
    final raw = await _storage.read(key: _key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      final accounts = <Map<String, String>>[];
      for (final entry in decoded) {
        if (entry is! Map) continue;
        final account = entry.map<String, String>((key, value) => MapEntry(key.toString(), value.toString()));
        if ((account['email'] ?? '').isNotEmpty && (account['refreshToken'] ?? '').isNotEmpty) accounts.add(account);
      }
      return accounts;
    } catch (_) { return []; }
  }

  Future<void> saveCurrent() async {
    final session = SupabaseService.kokoro.auth.currentSession;
    final user = session?.user;
    final refresh = session?.refreshToken;
    if (user == null || refresh == null || refresh.isEmpty) return;
    final entries = await list();
    entries.removeWhere((e) => e['userId'] == user.id);
    entries.add({'userId': user.id, 'email': user.email ?? '', 'refreshToken': refresh});
    await _storage.write(key: _key, value: jsonEncode(entries));
  }

  Future<void> switchTo(String refreshToken) async {
    await saveCurrent();
    await SupabaseService.kokoro.auth.setSession(refreshToken);
    await saveCurrent();
  }

  Future<void> remove(String userId) async {
    final entries = await list();
    entries.removeWhere((e) => e['userId'] == userId);
    await _storage.write(key: _key, value: jsonEncode(entries));
  }

  Future<void> clear() => _storage.delete(key: _key);
}
