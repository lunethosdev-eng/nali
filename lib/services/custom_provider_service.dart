import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

@immutable
class CustomProviderConfig {
  final String id;
  final String name;
  final bool enabled;
  final int priority;
  final String kind; // music | lyrics | connector
  final String endpoint;
  final String method;
  final String queryParam;
  final String resultsPath;
  final String titlePath;
  final String artistPath;
  final String audioPath;
  final String coverPath;
  final String lyricsPath;
  final Map<String, String> headers;

  const CustomProviderConfig({
    required this.id, required this.name, required this.kind,
    this.enabled = true, this.priority = 100,
    required this.endpoint, this.method = 'GET', this.queryParam = 'q',
    this.resultsPath = 'results', this.titlePath = 'title',
    this.artistPath = 'artist', this.audioPath = 'audio_url',
    this.coverPath = 'cover_url', this.lyricsPath = 'lyrics',
    this.headers = const {},
  });

  Map<String, dynamic> toJson() => {
    'id': id, 'name': name, 'enabled': enabled, 'priority': priority, 'kind': kind, 'endpoint': endpoint,
    'method': method, 'queryParam': queryParam, 'resultsPath': resultsPath,
    'titlePath': titlePath, 'artistPath': artistPath, 'audioPath': audioPath,
    'coverPath': coverPath, 'lyricsPath': lyricsPath, 'headers': headers,
  };

  factory CustomProviderConfig.fromJson(Map<String, dynamic> json) => CustomProviderConfig(
    id: json['id'].toString(), name: json['name'].toString(),
    enabled: json['enabled'] != false, priority: (json['priority'] as num?)?.toInt() ?? 100,
    kind: json['kind'].toString(), endpoint: json['endpoint'].toString(),
    method: (json['method'] ?? 'GET').toString(),
    queryParam: (json['queryParam'] ?? 'q').toString(),
    resultsPath: (json['resultsPath'] ?? 'results').toString(),
    titlePath: (json['titlePath'] ?? 'title').toString(),
    artistPath: (json['artistPath'] ?? 'artist').toString(),
    audioPath: (json['audioPath'] ?? 'audio_url').toString(),
    coverPath: (json['coverPath'] ?? 'cover_url').toString(),
    lyricsPath: (json['lyricsPath'] ?? 'lyrics').toString(),
    headers: Map<String, String>.from(json['headers'] is Map ? json['headers'] : const {}),
  );
}

/// User-defined declarative providers. Credentials are kept in secure storage;
/// providers are data-only and cannot execute downloaded code.
class CustomProviderService extends ChangeNotifier {
  CustomProviderService._();
  static final CustomProviderService instance = CustomProviderService._();
  static const _storageKey = 'nali_custom_providers_v1';
  static const _storage = FlutterSecureStorage();
  final List<CustomProviderConfig> _providers = [];
  bool _loaded = false;
  List<CustomProviderConfig> get providers => List.unmodifiable(_providers);
  bool get hasMusicProviders => _providers.any((p) => p.enabled && p.kind == 'music');

  Future<void> load() async {
    if (_loaded) return;
    try {
      final raw = await _storage.read(key: _storageKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          _providers
            ..clear()
            ..addAll(decoded.whereType<Map>().map((m) => CustomProviderConfig.fromJson(Map<String, dynamic>.from(m))));
        }
      }
    } catch (e) { debugPrint('Custom providers load: $e'); }
    _loaded = true;
    notifyListeners();
  }

  Future<void> saveProvider(CustomProviderConfig config) async {
    if (!config.endpoint.startsWith('https://')) {
      throw ArgumentError('Los endpoints personalizados deben usar HTTPS.');
    }
    if (!{'music', 'lyrics', 'connector'}.contains(config.kind)) {
      throw ArgumentError('Tipo de proveedor no válido.');
    }
    final index = _providers.indexWhere((p) => p.id == config.id);
    if (index < 0) _providers.add(config); else _providers[index] = config;
    await _persist();
  }

  Future<void> remove(String id) async {
    _providers.removeWhere((p) => p.id == id);
    await _persist();
  }

  Future<void> _persist() async {
    await _storage.write(key: _storageKey, value: jsonEncode(_providers.map((p) => p.toJson()).toList()));
    notifyListeners();
  }

  dynamic _path(dynamic root, String path) {
    dynamic value = root;
    for (final part in path.split('.').where((p) => p.isNotEmpty)) {
      if (value is Map) value = value[part];
      else if (value is List) {
        final index = int.tryParse(part);
        value = index != null && index >= 0 && index < value.length ? value[index] : null;
      } else return null;
    }
    return value;
  }

  Future<List<Map<String, dynamic>>> searchMusic(String query, {int limit = 12}) async {
    await load();
    final output = <Map<String, dynamic>>[];
    for (final provider in _providers.where((p) => p.enabled && p.kind == 'music').toList()..sort((a, b) => a.priority.compareTo(b.priority))) {
      if (output.length >= limit) break;
      try {
        final base = Uri.parse(provider.endpoint);
        final uri = provider.method == 'GET'
            ? base.replace(queryParameters: {...base.queryParameters, provider.queryParam: query})
            : base;
        final response = provider.method == 'POST'
            ? await http.post(uri, headers: {'Content-Type': 'application/json', ...provider.headers}, body: jsonEncode({provider.queryParam: query})).timeout(const Duration(seconds: 12))
            : await http.get(uri, headers: provider.headers).timeout(const Duration(seconds: 12));
        if (response.statusCode < 200 || response.statusCode >= 300) continue;
        final payload = jsonDecode(response.body);
        final rows = _path(payload, provider.resultsPath);
        if (rows is! List) continue;
        for (final row in rows) {
          if (row is! Map) continue;
          final title = _path(row, provider.titlePath)?.toString() ?? '';
          final artist = _path(row, provider.artistPath)?.toString() ?? provider.name;
          final audio = _path(row, provider.audioPath)?.toString() ?? '';
          if (title.isEmpty || !audio.startsWith('https://')) continue;
          final cover = _path(row, provider.coverPath)?.toString();
          output.add({
            'id': 'custom:${provider.id}:${row['id'] ?? title}',
            'provider': 'custom:${provider.id}', 'source': 'custom:${provider.id}',
            'title': title, 'artist': artist, 'audio_url': audio,
            'cover_url': cover, 'downloadable': false,
          });
          if (output.length >= limit) break;
        }
      } catch (e) { debugPrint('Custom provider ${provider.name}: $e'); }
    }
    return output;
  }

  Future<String> runConnector(String id) async {
    await load();
    CustomProviderConfig? provider;
    for (final item in _providers) {
      if (item.id == id && item.kind == 'connector' && item.enabled) { provider = item; break; }
    }
    if (provider == null) throw StateError('El conector no existe o está desactivado.');
    final uri = Uri.parse(provider.endpoint);
    final response = provider.method == 'POST'
        ? await http.post(uri, headers: {'Content-Type': 'application/json', ...provider.headers}, body: '{}').timeout(const Duration(seconds: 15))
        : await http.get(uri, headers: provider.headers).timeout(const Duration(seconds: 15));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('HTTP ${response.statusCode}: ${response.body.substring(0, response.body.length > 400 ? 400 : response.body.length)}');
    }
    return response.body;
  }

  Future<void> setEnabled(String id, bool enabled) async {
    final index = _providers.indexWhere((p) => p.id == id);
    if (index < 0) return;
    final old = _providers[index];
    _providers[index] = CustomProviderConfig(
      id: old.id, name: old.name, kind: old.kind, endpoint: old.endpoint,
      enabled: enabled, priority: old.priority, method: old.method,
      queryParam: old.queryParam, resultsPath: old.resultsPath, titlePath: old.titlePath,
      artistPath: old.artistPath, audioPath: old.audioPath, coverPath: old.coverPath,
      lyricsPath: old.lyricsPath, headers: old.headers,
    );
    await _persist();
  }

  Future<String?> fetchLyrics({required String title, required String artist}) async {
    await load();
    for (final provider in _providers.where((p) => p.enabled && p.kind == 'lyrics').toList()..sort((a, b) => a.priority.compareTo(b.priority))) {
      try {
        final endpoint = provider.endpoint
            .replaceAll('{title}', Uri.encodeComponent(title))
            .replaceAll('{artist}', Uri.encodeComponent(artist));
        final uri = Uri.parse(endpoint);
        final response = provider.method == 'POST'
            ? await http.post(uri, headers: {'Content-Type': 'application/json', ...provider.headers}, body: jsonEncode({'title': title, 'artist': artist})).timeout(const Duration(seconds: 12))
            : await http.get(uri, headers: provider.headers).timeout(const Duration(seconds: 12));
        if (response.statusCode < 200 || response.statusCode >= 300) continue;
        final payload = jsonDecode(response.body);
        final lyrics = _path(payload, provider.lyricsPath)?.toString();
        if (lyrics != null && lyrics.trim().length >= 12) return lyrics;
      } catch (e) { debugPrint('Custom lyrics provider ${provider.name}: $e'); }
    }
    return null;
  }
}
