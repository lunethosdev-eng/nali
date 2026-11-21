import 'dart:async';
import 'package:flutter/material.dart';
import 'package:nali/widgets/liquid_glass.dart';
import 'package:nali/widgets/compact_header.dart';
import 'package:nali/services/unified_search_service.dart';
import 'package:nali/services/player_controller.dart';
import 'package:nali/services/settings_service.dart';

class SearchPage extends StatefulWidget {
  SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _searchCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _focus = FocusNode();
  List<Map<String, dynamic>> _results = [];
  bool _searching = false;
  bool _collapsed = false;
  String? _status;
  Timer? _debounce;

  String t(String es, String en) => SettingsService.instance.locale == 'en' ? en : es;

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(() {
      final c = _scrollCtrl.offset > 40;
      if (c != _collapsed) setState(() => _collapsed = c);
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    _scrollCtrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged(String q) {
    _debounce?.cancel();
    if (q.trim().length < 3) {
      setState(() {
        _results = [];
        _status = null;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 800), () => _doSearch(q));
  }

  Future<void> _doSearch(String q) async {
    if (q.trim().isEmpty) return;
    setState(() {
      _searching = true;
      _status = t('Buscando en tus proveedores…', 'Searching your providers…');
      _results = [];
    });
    try {
      final result = await UnifiedSearchService.instance.search(
        q,
        onStatus: (status) {
          if (mounted) setState(() => _status = status);
        },
      );
      if (mounted) {
        setState(() {
          _results = result.all;
          _status = result.all.isEmpty
              ? t('No hay resultados en los proveedores activados.', 'No results from enabled providers.')
              : null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _results = [];
          _status = t('No se pudo completar la búsqueda.', 'Search could not be completed.');
        });
      }
    }
    if (mounted) setState(() => _searching = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0C0C0E),
      appBar: CompactHeader(title: t('Buscar', 'Search'), collapsed: _collapsed),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
            child: LiquidGlass(
              blur: 22,
              opacity: 0.10,
              borderRadius: BorderRadius.circular(16),
              borderWidth: 0.7,
              enableSpecular: true,
              child: TextField(
                controller: _searchCtrl,
                focusNode: _focus,
                style: const TextStyle(color: Colors.white, fontSize: 16),
                cursorColor: const Color(0xfffc3c44),
                textInputAction: TextInputAction.search,
                onChanged: (v) {
                  setState(() {});
                  _onChanged(v);
                },
                onSubmitted: _doSearch,
                decoration: InputDecoration(
                  hintText: t('Canción, artista o link de YouTube…', 'Song, artist or YouTube link…'),
                  hintStyle: TextStyle(color: Colors.white.withOpacity(0.35)),
                  prefixIcon: Icon(Icons.search, color: Colors.white.withOpacity(0.5)),
                  suffixIcon: _searchCtrl.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, color: Colors.white54, size: 20),
                          onPressed: () {
                            _searchCtrl.clear();
                            setState(() {
                              _results = [];
                              _status = null;
                            });
                          },
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
                ),
              ),
            ),
          ),
          if (_status != null) Padding(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 4),
            child: Align(alignment: Alignment.centerLeft, child: Text(_status!, style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12))),
          ),
          Expanded(
            child: _searching && _results.isEmpty
                ? Center(
                    child: Text(
                      t('Buscando en el catálogo…', 'Searching catalog…'),
                      style: TextStyle(color: Colors.white.withOpacity(0.4)),
                    ),
                  )
                : _results.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            t(
                              'Busca en Supabase y en los proveedores que hayas activado en Settings.',
                              'Search Supabase and the providers you enabled in Settings.',
                            ),
                            style: TextStyle(color: Colors.white.withOpacity(0.4), height: 1.4),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollCtrl,
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 120),
                        itemCount: _results.length,
                        itemBuilder: (ctx, i) {
                          final s = _results[i];
                          final cover = s['cover_url'];
                          final provider = (s['provider'] ?? s['source'] ?? 'supabase').toString();
                          return ListTile(
                            leading: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: cover != null
                                  ? Image.network(cover.toString(), width: 50, height: 50, fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) =>
                                          Container(width: 50, height: 50, color: Colors.white12))
                                  : Container(width: 50, height: 50, color: Colors.white12,
                                      child: const Icon(Icons.music_note, color: Colors.white24)),
                            ),
                            title: Text(s['title'] ?? '',
                                maxLines: 1, overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                            subtitle: Text(
                              '${s['artist'] ?? ''} · ${provider == 'youtube_music' ? 'YouTube Music' : provider == 'soundcloud' ? 'SoundCloud' : 'Nali'}',
                              maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: Colors.white.withOpacity(0.55))),
                            onTap: () {
                              final stream = (s['audio_url'] ?? s['stream_url'] ?? '').toString();
                              if (stream.isEmpty && provider != 'youtube_music') {
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                  content: Text(t('Esta pista no tiene un stream disponible.', 'This track has no available stream.')),
                                ));
                                return;
                              }
                              PlayerController.instance.playPlaylist(_results, startIndex: i);
                              Navigator.pushNamed(context, '/player', arguments: s);
                            },
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
