import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:nali/services/settings_service.dart';
import 'package:nali/services/dj_service.dart';
import 'package:nali/services/supabase_service.dart';
import 'package:nali/services/native_preferences_bridge.dart';
import 'package:nali/services/notification_service.dart';
import 'package:nali/services/audio_cache_service.dart';
import 'package:nali/services/spotify_service.dart';
import 'package:nali/screens/settings_providers_section.dart';
import 'package:nali/screens/spotify_web_import_screen.dart';
import 'package:nali/screens/listen_together_screen.dart';
import 'package:nali/widgets/liquid_glass.dart';
import 'package:nali/screens/font_manager_screen.dart';
import 'package:nali/services/account_sessions_service.dart';
import 'package:nali/services/native_player_bridge.dart';
import 'package:nali/screens/account_sessions_screen.dart';

class SettingsScreen extends StatefulWidget {
  final String? category;
  const SettingsScreen({super.key, this.category});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _showListening = true;
  bool _appleCanvas = false;
  bool _spotifyCanvas = false;
  bool _externalCanvas = true;
  bool _canvasRepeat = true;
  bool _animatedCovers = true;

  @override
  void initState() {
    super.initState();
    SupabaseService.getProfile().then((profile) {
      if (mounted && profile != null) setState(() {
        _showListening = profile['show_listening'] != false;
        SettingsService.instance.profilePublic = profile['is_public'] != false;
      });
    });
    NativePreferencesBridge.instance.loadCanvasSettings().then((values) {
      if (!mounted) return;
      setState(() {
        _appleCanvas = values['appleMusic'] ?? false;
        _spotifyCanvas = values['spotify'] ?? false;
        _externalCanvas = values['external'] ?? true;
        _canvasRepeat = values['repeat'] ?? true;
        _animatedCovers = values['animatedCovers'] ?? true;
      });
    }).catchError((error) => debugPrint('Canvas preferences: $error'));
    SpotifyService.instance.load().then((_) {
      if (mounted) setState(() {});
    });
  }

  String t(String es, String en) =>
      SettingsService.instance.locale == 'en' ? en : es;

  String _spotifyErrorText() {
    final err = SpotifyService.instance.friendlyError.isNotEmpty ? SpotifyService.instance.friendlyError : (SpotifyService.instance.lastError ?? "");
    if (err == null || err.isEmpty) {
      return t(
        'No se pudo conectar. Revisa Client ID y redirect pokke://spotify-callback en Spotify Dashboard',
        'Could not connect. Check Client ID and pokke://spotify-callback in Spotify Dashboard',
      );
    }
    return err;
  }


  Future<void> _importSpotifyWithPicker(BuildContext context) async {
    String t(String es, String en) =>
        SettingsService.instance.locale == 'en' ? en : es;
    final lists = await SpotifyService.instance.fetchPlaylists();
    if (!mounted) return;
    if (lists.isEmpty) {
      final err = SpotifyService.instance.friendlyError.isNotEmpty ? SpotifyService.instance.friendlyError : (SpotifyService.instance.lastError ?? "");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            err != null && err.isNotEmpty
                ? err
                : t(
                    'No hay playlists (¿permisos? vuelve a Conectar)',
                    'No playlists (permissions? reconnect)',
                  ),
          ),
          backgroundColor: const Color(0xFF3A1A1A),
        ),
      );
      return;
    }
    final selected = <String>{};
    var includeLiked = true;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF121214),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSt) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      t('Elige playlists a importar', 'Pick playlists to import'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 8),
                    CheckboxListTile(
                      value: includeLiked,
                      activeColor: const Color(0xFF1DB954),
                      title: Text(t('Liked Songs', 'Liked Songs'),
                          style: const TextStyle(color: Colors.white)),
                      onChanged: (v) => setSt(() => includeLiked = v ?? true),
                    ),
                    SizedBox(
                      height: MediaQuery.of(ctx).size.height * 0.45,
                      child: ListView.builder(
                        itemCount: lists.length,
                        itemBuilder: (_, i) {
                          final pl = lists[i];
                          final id = (pl['id'] ?? '').toString();
                          final name = (pl['name'] ?? 'Playlist').toString();
                          final total = pl['tracks']?['total'];
                          final checked = selected.contains(id);
                          return CheckboxListTile(
                            value: checked,
                            activeColor: const Color(0xFF1DB954),
                            title: Text(name,
                                style: const TextStyle(color: Colors.white)),
                            subtitle: total != null
                                ? Text(
                                    '$total tracks',
                                    style: TextStyle(
                                        color: Colors.white.withOpacity(0.45),
                                        fontSize: 12),
                                  )
                                : null,
                            onChanged: (v) {
                              setSt(() {
                                if (v == true) {
                                  selected.add(id);
                                } else {
                                  selected.remove(id);
                                }
                              });
                            },
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1DB954),
                          foregroundColor: Colors.black,
                        ),
                        onPressed: () => Navigator.pop(ctx, true),
                        child: Text(
                          t('Importar seleccionadas', 'Import selected'),
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
    if (ok != true || !mounted) return;
    if (selected.isEmpty && !includeLiked) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t('No elegiste ninguna', 'None selected'))),
      );
      return;
    }
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1E),
        content: Row(
          children: [
            const CircularProgressIndicator(color: Color(0xFF1DB954)),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                t('Importando Spotify…', 'Importing Spotify…'),
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
    try {
      final n = await SpotifyService.instance.importSelectedPlaylists(
        selected.toList(),
        includeLiked: includeLiked,
      );
      if (context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              t('Importadas: $n playlists', 'Imported: $n playlists'),
            ),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = SettingsService.instance;
    return AnimatedBuilder(
      animation: s,
      builder: (context, _) {
        if (widget.category == null) return _buildCategoryDashboard(s);
        return Scaffold(
          backgroundColor: const Color(0xff0c0c0e),
          appBar: AppBar(
            title: Text(_categoryTitle(widget.category!)),
            foregroundColor: Colors.white,
            backgroundColor: Colors.transparent,
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
            children: [
              if (widget.category == 'appearance') ...[
              // ── IDIOMA ────────────────────────────────────────
              _section(t('Tema de la aplicación', 'App theme')),
              LiquidGlass(borderRadius: BorderRadius.circular(14), child: Column(children: [
                RadioListTile<String>(value: 'dark', groupValue: s.themeModePreference, activeColor: const Color(0xfffc3c44), title: Text(t('Oscuro', 'Dark'), style: const TextStyle(color: Colors.white)), onChanged: (v) => s.setThemeModePreference(v!)),
                RadioListTile<String>(value: 'light', groupValue: s.themeModePreference, activeColor: const Color(0xfffc3c44), title: Text(t('Claro', 'Light'), style: const TextStyle(color: Colors.white)), onChanged: (v) => s.setThemeModePreference(v!)),
                RadioListTile<String>(value: 'system', groupValue: s.themeModePreference, activeColor: const Color(0xfffc3c44), title: Text(t('Automático (sistema)', 'System automatic'), style: const TextStyle(color: Colors.white)), onChanged: (v) => s.setThemeModePreference(v!)),
              ])),
              _section(t('Idioma', 'Language')),

              LiquidGlass(
                borderRadius: BorderRadius.circular(14),
                child: Column(
                  children: [
                    RadioListTile<String>(
                      value: 'es',
                      groupValue: s.locale,
                      activeColor: const Color(0xfffc3c44),
                      title: const Text('Español',
                          style: TextStyle(color: Colors.white)),
                      onChanged: (v) async {
                        s.locale = v!;
                        await s.save();
                      },
                    ),
                    RadioListTile<String>(
                      value: 'en',
                      groupValue: s.locale,
                      activeColor: const Color(0xfffc3c44),
                      title: const Text('English',
                          style: TextStyle(color: Colors.white)),
                      onChanged: (v) async {
                        s.locale = v!;
                        await s.save();
                      },
                    ),
                  ],
                ),
              ),

              // ── APARIENCIA RÁPIDA ─────────────────────────────
              _section(t('Apariencia rápida', 'Quick appearance')),
              LiquidGlass(
                borderRadius: BorderRadius.circular(14),
                child: Column(
                  children: [
                    SwitchListTile(
                      activeColor: const Color(0xfffc3c44),
                      title: Text(t('Liquid Glass', 'Liquid Glass'),
                          style: const TextStyle(color: Colors.white)),
                      value: s.liquidGlassEnabled,
                      onChanged: (v) => s.setFlag('ui_liquid_glass', v),
                    ),
                    if (s.liquidGlassEnabled) ...[
                      ListTile(
                        title: Text(t('Opacidad', 'Opacity'),
                            style: const TextStyle(color: Colors.white70)),
                        subtitle: Slider(
                          value: s.glassOpacity.clamp(0.04, 0.4),
                          min: 0.04,
                          max: 0.4,
                          activeColor: const Color(0xfffc3c44),
                          onChanged: (v) {
                            s.glassOpacity = v;
                            s.save();
                          },
                        ),
                      ),
                      ListTile(
                        title: Text(t('Blur', 'Blur'),
                            style: const TextStyle(color: Colors.white70)),
                        subtitle: Slider(
                          value: s.glassBlur.clamp(8, 40),
                          min: 8,
                          max: 40,
                          activeColor: const Color(0xfffc3c44),
                          onChanged: (v) {
                            s.glassBlur = v;
                            s.save();
                          },
                        ),
                      ),
                    ],
                    SwitchListTile(
                      activeColor: const Color(0xfffc3c44),
                      title: Text(t('Tema AMOLED', 'AMOLED theme'),
                          style: const TextStyle(color: Colors.white)),
                      value: s.amoled,
                      onChanged: (v) => s.setFlag('ui_amoled', v),
                    ),
                    SwitchListTile(
                      activeColor: const Color(0xfffc3c44),
                      title: Text(t('Reducir animaciones', 'Reduce animations'),
                          style: const TextStyle(color: Colors.white)),
                      value: s.reduceAnimations,
                      onChanged: (v) => s.setFlag('ui_reduce_anim', v),
                    ),
                    SwitchListTile(
                      activeColor: const Color(0xfffc3c44),
                      title: Text(t('Mini player', 'Mini player'),
                          style: const TextStyle(color: Colors.white)),
                      value: s.showMiniPlayer,
                      onChanged: (v) => s.setFlag('ui_mini_player', v),
                    ),
                    SwitchListTile(
                      activeColor: const Color(0xfffc3c44),
                      title: Text(t('Mini player circular al hacer scroll', 'Collapse mini player on scroll'),
                          style: const TextStyle(color: Colors.white)),
                      subtitle: Text(t('Se convierte en un círculo compacto.', 'Turns into a compact floating circle.'),
                          style: TextStyle(color: Colors.white.withOpacity(0.45), fontSize: 12)),
                      value: s.miniPlayerCollapseOnScroll,
                      onChanged: (v) async { s.miniPlayerCollapseOnScroll = v; await s.save(); },
                    ),
                    ListTile(
                      title: Text(t('Posición del mini player', 'Mini player position'),
                          style: const TextStyle(color: Colors.white)),
                      trailing: SegmentedButton<String>(
                        segments: [
                          ButtonSegment(value: 'left', label: Text(t('Izquierda', 'Left'))),
                          ButtonSegment(value: 'right', label: Text(t('Derecha', 'Right'))),
                        ],
                        selected: {s.miniPlayerCollapsedSide},
                        onSelectionChanged: (v) async { s.miniPlayerCollapsedSide = v.first; await s.save(); },
                      ),
                    ),
                    SwitchListTile(
                      activeColor: const Color(0xfffc3c44),
                      title: Text(t('Letras sincronizadas en mini player', 'Synced lyrics in mini player'),
                          style: const TextStyle(color: Colors.white)),
                      subtitle: Text(t('Muestra la línea actual del karaoke.', 'Shows the current karaoke line.'),
                          style: TextStyle(color: Colors.white.withOpacity(0.45), fontSize: 12)),
                      value: s.miniPlayerShowLyrics,
                      onChanged: (v) async { s.miniPlayerShowLyrics = v; await s.save(); },
                    ),
                  ],
                ),
              ),

              // ── TYPOGRAPHY ────────────────────────────────────
              _section(t('Tipografía', 'Typography')),
              LiquidGlass(
                borderRadius: BorderRadius.circular(14),
                child: ListTile(
                  leading: const Icon(Icons.font_download_outlined, color: Colors.white70),
                  title: Text(t('Fuentes', 'Fonts'), style: const TextStyle(color: Colors.white)),
                  subtitle: Text(t('Elige o importa tu propia tipografía', 'Choose or import your own typeface'), style: TextStyle(color: Colors.white.withOpacity(0.45), fontSize: 12)),
                  trailing: const Icon(Icons.chevron_right, color: Colors.white38),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FontManagerScreen())),
                ),
              ),
              _section(t('Fondo de Home', 'Home background')),
              LiquidGlass(borderRadius: BorderRadius.circular(14), child: Column(children: [
                if (!kIsWeb && s.homeBackgroundPath != null && File(s.homeBackgroundPath!).existsSync())
                  ClipRRect(borderRadius: BorderRadius.circular(10), child: Image.file(File(s.homeBackgroundPath!), height: 110, width: double.infinity, fit: BoxFit.cover)),
                ListTile(leading: const Icon(Icons.wallpaper_rounded, color: Colors.white70), title: Text(t('Seleccionar imagen', 'Choose image'), style: const TextStyle(color: Colors.white)), onTap: _pickHomeBackground),
                if (s.homeBackgroundPath != null)
                  ListTile(leading: const Icon(Icons.delete_outline_rounded, color: Colors.white70), title: Text(t('Quitar fondo', 'Remove background'), style: const TextStyle(color: Colors.white)), onTap: _clearHomeBackground),
              ])),
              _incompleteNote(t('El modo oscuro sigue siendo el tema global actual. El modo claro global todavía requiere una migración visual de todas las pantallas.', 'Dark mode remains the current global theme. A global light theme still requires a visual migration of all screens.')),
              ],
              if (widget.category == 'playback') ...[
              // ── PLAYBACK ──────────────────────────────────────
              _section(t('Reproducción', 'Playback')),
              LiquidGlass(
                borderRadius: BorderRadius.circular(14),
                child: Column(
                  children: [
                    SwitchListTile(
                      activeColor: const Color(0xfffc3c44),
                      title: Text(t('Crossfade entre canciones', 'Crossfade between songs'),
                          style: const TextStyle(color: Colors.white)),
                      value: s.crossfade,
                      onChanged: (v) => s.setFlag('play_crossfade', v),
                    ),
                    if (s.crossfade)
                      ListTile(
                        title: Text(
                            t('Duración (${s.crossfadeSeconds.round()}s)',
                                'Duration (${s.crossfadeSeconds.round()}s)'),
                            style: const TextStyle(color: Colors.white70)),
                        subtitle: Slider(
                          value: s.crossfadeSeconds.clamp(2, 12),
                          min: 2,
                          max: 12,
                          activeColor: const Color(0xfffc3c44),
                          onChanged: (v) {
                            s.crossfadeSeconds = v;
                            s.save();
                          },
                        ),
                      ),
                    SwitchListTile(
                      activeColor: const Color(0xfffc3c44),
                      title: Text(t('Karaoke', 'Karaoke'),
                          style: const TextStyle(color: Colors.white)),
                      value: s.karaokeOn,
                      onChanged: (v) => s.setFlag('play_karaoke', v),
                    ),
                  ],
                ),
              ),

              ],
              if (widget.category == 'dj') ...[
                _section(t('DJ / MAI Radio', 'DJ / MAI Radio')),
                const _DjSettingsPanel(),
                ListTile(
                  leading: const Icon(Icons.radio_rounded, color: Color(0xff5CE1C5)),
                  title: Text(t('Abrir MAI Radio', 'Open MAI Radio'), style: const TextStyle(color: Colors.white)),
                  subtitle: Text(t('Pantalla dedicada con blob y voz', 'Dedicated blob + voice screen'), style: const TextStyle(color: Colors.white54, fontSize: 12)),
                  onTap: () => Navigator.of(context).pushNamed('/dj'),
                ),
                _incompleteNote(t(
                  'Coloca los MP3 en assets/dj/nugget_dj/ (welcome, pause, skip, …) y haz rebuild. Más DJs = más carpetas bajo assets/dj/.',
                  'Put MP3s in assets/dj/nugget_dj/ (welcome, pause, skip, …) and rebuild. More DJs = more folders under assets/dj/.',
                )),
              ],
              if (widget.category == 'canvas') ...[
                _section(t('Canvas y portadas animadas', 'Canvas and animated covers')),
                LiquidGlass(borderRadius: BorderRadius.circular(14), child: Column(children: [
                  _canvasSwitch('appleMusic', t('Canvas de Apple Music', 'Apple Music Canvas'), _appleCanvas),
                  _canvasSwitch('spotify', t('Canvas de Spotify', 'Spotify Canvas'), _spotifyCanvas),
                  _canvasSwitch('external', t('Fuentes externas', 'External sources'), _externalCanvas),
                  _canvasSwitch('repeat', t('Repetir Canvas', 'Repeat Canvas'), _canvasRepeat),
                  _canvasSwitch('animatedCovers', t('Portadas animadas', 'Animated covers'), _animatedCovers),
                ])),
                _incompleteNote(t('Las preferencias se guardan en este dispositivo. La reproducción de Canvas depende de la fuente y de las capacidades de la plataforma.', 'Preferences are saved on this device. Canvas playback depends on source and platform capabilities.')),
              ],
              if (widget.category == 'library') ...[
              // ── CACHE ─────────────────────────────────────────
              _section(t('Almacenamiento', 'Storage')),
              LiquidGlass(
                borderRadius: BorderRadius.circular(14),
                child: ListTile(
                  leading: const Icon(Icons.sd_storage_outlined, color: Colors.white70),
                  title: Text(t('Caché de audio', 'Audio cache'),
                      style: const TextStyle(color: Colors.white)),
                  subtitle: FutureBuilder<int>(
                    future: AudioCacheService.instance.cachedSongCount(),
                    builder: (_, snap) {
                      final n = snap.data ?? 0;
                      return Text(
                        t('$n canciones en caché', '$n songs cached'),
                        style: TextStyle(
                            color: Colors.white.withOpacity(0.45), fontSize: 12),
                      );
                    },
                  ),
                ),
              ),

              // ── SPOTIFY ───────────────────────────────────────
                                          _section(t('Cuentas vinculadas', 'Linked accounts')),
              LiquidGlass(
                borderRadius: BorderRadius.circular(14),
                child: ListTile(
                  leading: const Icon(Icons.library_music, color: Color(0xFF1DB954)),
                  title: Text(t('Spotify (Web)', 'Spotify (Web)'),
                      style: const TextStyle(color: Colors.white)),
                  subtitle: Text(
                    t(
                      'Sin API · inicia sesión en un navegador in-app, extrae playlists y las busca en Pokke.',
                      'No API · sign in via in-app browser, extract playlists, match in Pokke.',
                    ),
                    style: TextStyle(color: Colors.white.withOpacity(0.45), fontSize: 12),
                  ),
                  trailing: const Icon(Icons.chevron_right, color: Colors.white38),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const SpotifyWebImportScreen()),
                    );
                  },
                ),
              ),
              const SizedBox(height: 10),
              LiquidGlass(
                borderRadius: BorderRadius.circular(14),
                child: ListTile(
                  leading: const Icon(Icons.headphones, color: Color(0xfffc3c44)),
                  title: Text(t('Escuchar juntos', 'Listen together'),
                      style: const TextStyle(color: Colors.white)),
                  subtitle: Text(
                    t('Beta · salas con código y sesión dual',
                        'Beta · room codes and dual session'),
                    style: TextStyle(color: Colors.white.withOpacity(0.45), fontSize: 12),
                  ),
                  trailing: const Icon(Icons.chevron_right, color: Colors.white38),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const ListenTogetherScreen()),
                    );
                  },
                ),
              ),

              ],
              if (widget.category == 'advanced') ...[
              // ── PERFORMANCE / ACCESSIBILITY / PIP ─────────────
              _section(t('Rendimiento y accesibilidad', 'Performance & accessibility')),
              LiquidGlass(
                borderRadius: BorderRadius.circular(14),
                child: Column(children: [
                  ListTile(
                    title: Text(t('Perfil de rendimiento', 'Performance profile'), style: const TextStyle(color: Colors.white)),
                    subtitle: Text(
                      t('Bajo reduce blur y efectos; Alto permite más efectos y caché.', 'Low reduces blur and effects; High allows more effects and cache.'),
                      style: TextStyle(color: Colors.white.withOpacity(0.48), fontSize: 12),
                    ),
                    trailing: DropdownButton<String>(
                      value: s.performanceProfile,
                      dropdownColor: const Color(0xff202024),
                      style: const TextStyle(color: Colors.white),
                      underline: const SizedBox.shrink(),
                      items: [
                        DropdownMenuItem(value: 'low', child: Text(t('Bajo', 'Low'))),
                        DropdownMenuItem(value: 'balanced', child: Text(t('Equilibrado', 'Balanced'))),
                        DropdownMenuItem(value: 'high', child: Text(t('Alto', 'High'))),
                      ],
                      onChanged: (value) { if (value != null) s.setPerformanceProfile(value); },
                    ),
                  ),
                  const Divider(height: 1, color: Colors.white10),
                  ListTile(
                    title: Text(t('Tamaño del texto', 'Text size'), style: const TextStyle(color: Colors.white)),
                    subtitle: Slider(
                      value: s.textScale.clamp(0.85, 1.35).toDouble(), min: 0.85, max: 1.35, divisions: 10,
                      activeColor: const Color(0xfffc3c44),
                      label: '${(s.textScale * 100).round()}%',
                      onChanged: (value) { s.textScale = value; s.save(); },
                    ),
                    trailing: Text('${(s.textScale * 100).round()}%', style: const TextStyle(color: Colors.white70)),
                  ),
                  const Divider(height: 1, color: Colors.white10),
                  ListTile(
                    leading: const Icon(Icons.keyboard_outlined, color: Colors.white70),
                    title: Text(t('Atajos de teclado', 'Keyboard shortcuts'), style: const TextStyle(color: Colors.white)),
                    subtitle: Text('Espacio: reproducir/pausar · Ctrl + ←/→: anterior/siguiente · Shift + ←/→: ±10 s', style: TextStyle(color: Colors.white.withOpacity(0.48), fontSize: 11)),
                  ),
                  if (kIsWeb) ...[
                    const Divider(height: 1, color: Colors.white10),
                    ListTile(
                      leading: const Icon(Icons.picture_in_picture_alt_rounded, color: Colors.white70),
                      title: Text('Picture in Picture', style: const TextStyle(color: Colors.white)),
                      subtitle: Text(t('El navegador no ofrece una ventana PiP genérica para un reproductor de audio Flutter. No se activa una ventana de vídeo falsa.', 'Browsers do not provide generic Picture-in-Picture for a Flutter audio player. Nali will not create a fake video window.'), style: TextStyle(color: Colors.white.withOpacity(0.48), fontSize: 12)),
                    ),
                  ],
                  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) ...[
                    const Divider(height: 1, color: Colors.white10),
                    SwitchListTile(
                      activeColor: const Color(0xfffc3c44),
                      title: Text(t('Picture in Picture', 'Picture in Picture'), style: const TextStyle(color: Colors.white)),
                      subtitle: Text(t('Al salir de la app, el reproductor nativo puede quedarse en una ventana flotante.', 'When leaving the app, the native player can remain in a floating window.'), style: TextStyle(color: Colors.white.withOpacity(0.48), fontSize: 12)),
                      value: s.pictureInPictureEnabled,
                      onChanged: (value) async {
                        await s.setPictureInPictureEnabled(value);
                        await NativePlayerBridge.instance.invoke<bool>('setPipEnabled', {'enabled': value});
                      },
                    ),
                  ],
                ]),
              ),
              const SizedBox(height: 14),
              // ── EDITORES ──────────────────────────────────────
              _section(t('Estudio', 'Studio')),
              Text(
                t(
                  'Cada editor abre una pantalla completa para diseñar esa parte de la app. No son interruptores sueltos.',
                  'Each editor opens a full screen to design that part of the app. Not loose toggles.',
                ),
                style: TextStyle(
                    color: Colors.white.withOpacity(0.42), fontSize: 12, height: 1.35),
              ),
              const SizedBox(height: 12),
              _editorCard(
                icon: Icons.graphic_eq_rounded,
                color: const Color(0xFF2EE6A6),
                title: t('Editor de Mezcla', 'Mix Editor'),
                subtitle: t(
                  'Combina dos canciones con timeline, punto de corte y crossfade real.',
                  'Blend two tracks with timeline, cut point and real crossfade.',
                ),
                where: t(
                  'También desde el menú ⋮ del player → Combinar.',
                  'Also from player ⋮ menu → Blend.',
                ),
                onTap: () => Navigator.pushNamed(context, '/mix'),
              ),
              _editorCard(
                icon: Icons.queue_music_rounded,
                color: const Color(0xFF6C8CFF),
                title: t('Playlists · defaults', 'Playlists · defaults'),
                subtitle: t(
                  'Densidad de lista, numeración, asas, orden y privacidad por defecto.',
                  'List density, numbers, handles, sort and default privacy.',
                ),
                where: t(
                  'Afecta todas las playlists nuevas y la vista de detalle.',
                  'Affects new playlists and the detail view.',
                ),
                onTap: () => _openPlaylistDefaults(),
              ),

              ],
              if (widget.category == 'account') ...[
              // ── ACCOUNT ───────────────────────────────────────
              _section(t('Cuenta', 'Account')),
              LiquidGlass(
                borderRadius: BorderRadius.circular(14),
                child: Column(
                  children: [
                    ListTile(
                      leading:
                          const Icon(Icons.person_outline, color: Colors.white70),
                      title: Text(t('Editar perfil', 'Edit profile'),
                          style: const TextStyle(color: Colors.white)),
                      trailing:
                          const Icon(Icons.chevron_right, color: Colors.white38),
                      onTap: () => Navigator.pushNamed(context, '/profile_edit'),
                    ),
                    ListTile(
                      leading: const Icon(Icons.admin_panel_settings_outlined,
                          color: Colors.white70),
                      title: Text(t('Admin', 'Admin'),
                          style: const TextStyle(color: Colors.white)),
                      trailing:
                          const Icon(Icons.chevron_right, color: Colors.white38),
                      onTap: () => Navigator.pushNamed(context, '/admin'),
                    ),
                    ListTile(
                      leading: const Icon(Icons.email_outlined, color: Colors.white70),
                      title: Text(SupabaseService.currentUser?.email ?? t('Sin sesión', 'Signed out'), style: const TextStyle(color: Colors.white)),
                      subtitle: Text(t('Correo de la cuenta actual', 'Current account email'), style: const TextStyle(color: Colors.white54, fontSize: 12)),
                    ),
                    ListTile(
                      leading: const Icon(Icons.lock_reset_rounded, color: Colors.white70),
                      title: Text(t('¿Olvidaste tu contraseña?', 'Forgot your password?'), style: const TextStyle(color: Colors.white)),
                      trailing: const Icon(Icons.chevron_right, color: Colors.white38),
                      onTap: _showPasswordRecovery,
                    ),
                    ListTile(
                      leading: const Icon(Icons.switch_account_outlined, color: Colors.white70),
                      title: Text(t('Administrar cuentas', 'Manage accounts'), style: const TextStyle(color: Colors.white)),
                      subtitle: Text(t('Guardar sesiones y cambiar de cuenta', 'Save sessions and switch accounts'), style: const TextStyle(color: Colors.white54, fontSize: 12)),
                      trailing: const Icon(Icons.chevron_right, color: Colors.white38),
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AccountSessionsScreen())),
                    ),
                    ListTile(
                      leading: const Icon(Icons.delete_forever_outlined, color: Color(0xffff7777)),
                      title: Text(t('Eliminar cuenta', 'Delete account'), style: const TextStyle(color: Color(0xffff7777))),
                      subtitle: Text(t('Requiere una Edge Function protegida', 'Requires a protected Edge Function'), style: const TextStyle(color: Colors.white54, fontSize: 12)),
                      onTap: _confirmAccountDeletion,
                    ),
                    ListTile(
                      leading: const Icon(Icons.logout_rounded, color: Color(0xffff7777)),
                      title: Text(t('Cerrar sesión', 'Sign out'), style: const TextStyle(color: Color(0xffff7777))),
                      onTap: _confirmSignOut,
                    ),
                  ],
                ),
              ),
              _incompleteNote(t('La recuperación de contraseña y el cierre de sesión ya están conectados. Cambio entre varias cuentas y eliminación de cuenta siguen pendientes de un flujo seguro de backend.', 'Password recovery and sign-out are connected. Multi-account switching and account deletion still require a secure backend flow.')),
              ],
              if (widget.category == 'privacy') ...[
                _section(t('Privacidad del perfil', 'Profile privacy')),
                LiquidGlass(borderRadius: BorderRadius.circular(14), child: Column(children: [
                  SwitchListTile(
                    activeColor: const Color(0xfffc3c44),
                    title: Text(t('Perfil público', 'Public profile'), style: const TextStyle(color: Colors.white)),
                    subtitle: Text(t('Controla si tu perfil puede mostrarse públicamente.', 'Controls whether your profile can be viewed publicly.'), style: const TextStyle(color: Colors.white54, fontSize: 12)),
                    value: s.profilePublic,
                    onChanged: (value) async {
                      final old = s.profilePublic;
                      setState(() => s.profilePublic = value);
                      try { await SupabaseService.updateProfileVisibility(value); await s.setFlag('priv_profile_public', value); }
                      catch (error) { if (mounted) setState(() => s.profilePublic = old); if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error'))); }
                    },
                  ),
                  SwitchListTile(
                    activeColor: const Color(0xfffc3c44),
                    title: Text(t('Mostrar actividad musical', 'Show listening activity'), style: const TextStyle(color: Colors.white)),
                    subtitle: Text(t('Permite mostrar la canción actual en tu perfil.', 'Allows your current track to appear on your profile.'), style: const TextStyle(color: Colors.white54, fontSize: 12)),
                    value: _showListening, onChanged: _setListeningVisibility,
                  ),
                  SwitchListTile(
                    activeColor: const Color(0xfffc3c44),
                    title: Text(t('Historial local', 'Local listening history'), style: const TextStyle(color: Colors.white)),
                    value: s.historyLocal, onChanged: (value) => s.setFlag('priv_history_local', value),
                  ),
                ])),
                _incompleteNote(t('Los controles de ubicación y permisos sociales requieren todavía una integración de consentimiento; no se comparte ubicación desde esta pantalla.', 'Location and social-consent controls still need integration; this screen does not share location.')),
              ],
              if (widget.category == 'personalization') ...[
                _section(t('Personalización del perfil', 'Profile personalization')),
                _editorCard(icon: Icons.person_rounded, color: const Color(0xfffc3c44), title: t('Editar perfil', 'Edit profile'), subtitle: t('Avatar, banner, biografía y apariencia básica.', 'Avatar, banner, biography and basic appearance.'), where: t('Editor Flutter existente', 'Existing Flutter editor'), onTap: () => Navigator.pushNamed(context, '/profile_edit')),
                _incompleteNote(t('El perfil nativo de Nali ya contiene mangas favoritos, GIF, emblemas, pronombres, enlaces y nameplates. Su migración a la única interfaz Flutter sigue pendiente.', 'Nali native profile already contains favorite manga, GIFs, badges, pronouns, links and nameplates. Porting them into the single Flutter UI remains pending.')),
              ],
              if (widget.category == 'lyrics') ...[
                _section(t('Catálogo musical', 'Music catalog')),
                const SettingsProvidersSection(),
                const SizedBox(height: 20),
                _section(t('Proveedores de letras', 'Lyrics providers')),
                _incompleteNote(t('Los proveedores de letras personalizados se consultan primero por prioridad y después Nali usa LRCLIB como alternativa. Las claves y headers se guardan en almacenamiento seguro del dispositivo.', 'Custom lyrics providers are queried by priority first, then Nali falls back to LRCLIB. API keys and headers are stored in the device secure storage.')),
              ],
              if (widget.category == 'social') ...[
                _section(t('Funciones sociales', 'Social features')),
                LiquidGlass(borderRadius: BorderRadius.circular(14), child: ListTile(leading: const Icon(Icons.headphones_rounded, color: Color(0xfffc3c44)), title: Text(t('Escuchar juntos', 'Listen together'), style: const TextStyle(color: Colors.white)), subtitle: Text(t('Salas de escucha compartida.', 'Shared listening rooms.'), style: const TextStyle(color: Colors.white54, fontSize: 12)), trailing: const Icon(Icons.chevron_right, color: Colors.white38), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ListenTogetherScreen())))),
                _incompleteNote(t('Chat, mapa de amigos e historias están integrados en la navegación Android nativa de Nali. Activa Chats experimentales para acceder; el chat refresca la conversación abierta cada 3.5 s. La integración Flutter separada aún no está disponible.', 'Chat, friends map and stories are integrated in Nali’s native Android navigation. Enable Experimental Chats to access them; the open chat refreshes every 3.5 s. A separate Flutter integration is not available yet.')),
              ],
              if (widget.category == 'notifications') ...[
              _section(t('Notificaciones', 'Notifications')),
              LiquidGlass(
                borderRadius: BorderRadius.circular(14),
                child: Column(
                  children: [
                    SwitchListTile(
                      activeColor: const Color(0xfffc3c44),
                      title: Text(t('Sonido de notificación', 'Notification sound'),
                          style: const TextStyle(color: Colors.white)),
                      value: s.notificationSoundEnabled,
                      onChanged: (v) async {
                        s.notificationSoundEnabled = v;
                        await s.save();
                      },
                    ),
                    ...['none', 'message', 'joyous', 'bubble', 'twinkle', 'marimba', 'chime'].map((id) {
                      final labels = NotificationService.soundLabels[id] ?? {'es': id, 'en': id};
                      final label = s.locale == 'en' ? labels['en']! : labels['es']!;
                      return RadioListTile<String>(
                        value: id,
                        groupValue: s.notificationSound,
                        activeColor: const Color(0xfffc3c44),
                        title: Text(label, style: const TextStyle(color: Colors.white)),
                        secondary: id == 'none'
                            ? null
                            : IconButton(
                                icon: const Icon(Icons.play_arrow, color: Colors.white54),
                                onPressed: () => NotificationService.instance.previewSound(id),
                              ),
                        onChanged: (v) async {
                          if (v == null) return;
                          s.notificationSound = v;
                          await s.save();
                          if (v != 'none') {
                            await NotificationService.instance.previewSound(v);
                          }
                        },
                      );
                    }),
                  ],
                ),
              ),

              ],
              if (widget.category == 'advanced') ...[
              // ── BETA ─────────────────────────────────────────
              _section(t('Beta / experimental', 'Beta / experimental')),
              LiquidGlass(
                borderRadius: BorderRadius.circular(14),
                child: Column(
                  children: [
                    SwitchListTile(
                      activeColor: const Color(0xfffc3c44),
                      title: Text(t('IA (traducir / karaoke)', 'AI (translate / karaoke)'),
                          style: const TextStyle(color: Colors.white)),
                      subtitle: Text(
                        t('Traducción de letras y sync de karaoke',
                            'Lyrics translation & karaoke sync'),
                        style: TextStyle(color: Colors.white.withOpacity(0.45), fontSize: 12),
                      ),
                      value: s.flag('beta_ai', def: true),
                      onChanged: (v) => s.setFlag('beta_ai', v),
                    ),
                    SwitchListTile(
                      activeColor: const Color(0xfffc3c44),
                      title: Text(t('Nav colapsa al scroll', 'Collapse nav on scroll'),
                          style: const TextStyle(color: Colors.white)),
                      subtitle: Text(
                        t('Home+Library cortos y Search se separa',
                            'Short Home+Library, Search peels off'),
                        style: TextStyle(color: Colors.white.withOpacity(0.45), fontSize: 12),
                      ),
                      value: s.flag('beta_nav_collapse', def: true),
                      onChanged: (v) => s.setFlag('beta_nav_collapse', v),
                    ),
                    SwitchListTile(
                      activeColor: const Color(0xfffc3c44),
                      title: Text(t('Dismiss con blur', 'Blur dismiss'),
                          style: const TextStyle(color: Colors.white)),
                      subtitle: Text(
                        t('Al bajar el full player se ve el home',
                            'Pulling down full player reveals home'),
                        style: TextStyle(color: Colors.white.withOpacity(0.45), fontSize: 12),
                      ),
                      value: s.flag('beta_player_blur', def: true),
                      onChanged: (v) => s.setFlag('beta_player_blur', v),
                    ),
                    SwitchListTile(
                      activeColor: const Color(0xfffc3c44),
                      title: Text(t('Cola inteligente', 'Smart queue'),
                          style: const TextStyle(color: Colors.white)),
                      value: s.flag('beta_smart_queue', def: true),
                      onChanged: (v) => s.setFlag('beta_smart_queue', v),
                    ),
                    SwitchListTile(
                      activeColor: const Color(0xfffc3c44),
                      title: Text(t('Etiquetas del nav', 'Nav labels'),
                          style: const TextStyle(color: Colors.white)),
                      value: s.flag('nav_labels', def: true),
                      onChanged: (v) => s.setFlag('nav_labels', v),
                    ),
                  ],
                ),
              ),
              _incompleteNote(t('La eliminación de cuenta no se activa hasta disponer de una Edge Function protegida que valide el JWT, borre Auth y gestione datos asociados. No se ejecuta ninguna eliminación desde el cliente.', 'Account deletion remains disabled until a protected Edge Function validates the JWT, deletes Auth and handles associated data. No deletion is run from the client.')),

              ],
              const SizedBox(height: 24),
              Center(
                child: Text('nali · 1.0.0',
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.25), fontSize: 12)),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _pickHomeBackground() async {
    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t('El fondo local está disponible en Android e iOS.', 'Local backgrounds are available on Android and iOS.'))));
      return;
    }
    try {
      final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 90);
      if (picked == null) return;
      final directory = await getApplicationDocumentsDirectory();
      final extension = picked.path.split('.').last.toLowerCase();
      final safeExtension = const {'jpg', 'jpeg', 'png', 'webp'}.contains(extension) ? extension : 'jpg';
      final destination = File('${directory.path}/nali_home_background.$safeExtension');
      await File(picked.path).copy(destination.path);
      await SettingsService.instance.setHomeBackgroundPath(destination.path);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t('Fondo de Home actualizado.', 'Home background updated.'))));
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
    }
  }

  Future<void> _clearHomeBackground() async {
    final oldPath = SettingsService.instance.homeBackgroundPath;
    await SettingsService.instance.setHomeBackgroundPath(null);
    if (oldPath != null) {
      try {
        final directory = await getApplicationDocumentsDirectory();
        if (oldPath.startsWith('${directory.path}/nali_home_background.')) {
          final oldFile = File(oldPath);
          if (await oldFile.exists()) await oldFile.delete();
        }
      } catch (_) {}
    }
  }

  Widget _canvasSwitch(String key, String title, bool value) => SwitchListTile(
    activeColor: const Color(0xfffc3c44),
    title: Text(title, style: const TextStyle(color: Colors.white)),
    value: value,
    onChanged: (enabled) async {
      final old = value;
      setState(() {
        switch (key) {
          case 'appleMusic': _appleCanvas = enabled; break;
          case 'spotify': _spotifyCanvas = enabled; break;
          case 'external': _externalCanvas = enabled; break;
          case 'repeat': _canvasRepeat = enabled; break;
          case 'animatedCovers': _animatedCovers = enabled; break;
        }
      });
      try { await NativePreferencesBridge.instance.setCanvasSetting(key, enabled); }
      catch (error) {
        if (mounted) setState(() {
          switch (key) {
            case 'appleMusic': _appleCanvas = old; break;
            case 'spotify': _spotifyCanvas = old; break;
            case 'external': _externalCanvas = old; break;
            case 'repeat': _canvasRepeat = old; break;
            case 'animatedCovers': _animatedCovers = old; break;
          }
        });
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
      }
    },
  );

  String _categoryTitle(String id) => switch (id) {
    'account' => t('Cuenta', 'Account'), 'appearance' => t('Apariencia', 'Appearance'),
    'privacy' => t('Privacidad', 'Privacy'), 'personalization' => t('Personalización', 'Personalization'),
    'playback' => t('Reproducción', 'Playback'), 'lyrics' => t('Letras', 'Lyrics'),
    'library' => t('Biblioteca', 'Library'), 'notifications' => t('Notificaciones', 'Notifications'),
    'social' => t('Social', 'Social'), 'dj' => t('DJ / MAI Radio', 'DJ / MAI Radio'), 'canvas' => t('Canvas', 'Canvas'), 'advanced' => t('Ajustes avanzados', 'Advanced settings'),
    _ => t('Ajustes', 'Settings'),
  };

  Widget _buildCategoryDashboard(SettingsService s) {
    final items = <(String, IconData, String, Color)>[
      ('account', Icons.manage_accounts_outlined, t('Sesión, correo y seguridad', 'Session, email and security'), const Color(0xff8da7ff)),
      ('appearance', Icons.palette_outlined, t('Idioma, efectos y tipografía', 'Language, effects and typography'), const Color(0xffd6a0ff)),
      ('privacy', Icons.shield_outlined, t('Visibilidad y actividad compartida', 'Visibility and shared activity'), const Color(0xff6ed6b1)),
      ('personalization', Icons.person_pin_circle_outlined, t('Perfil y presentación', 'Profile and presentation'), const Color(0xffffa477)),
      ('playback', Icons.graphic_eq_rounded, t('Crossfade y karaoke', 'Crossfade and karaoke'), const Color(0xfffc3c44)),
      ('lyrics', Icons.lyrics_outlined, t('Letras y proveedores', 'Lyrics and providers'), const Color(0xff7fc9ee)),
      ('library', Icons.library_music_outlined, t('Caché, importación y playlists', 'Cache, imports and playlists'), const Color(0xffa7c77a)),
      ('notifications', Icons.notifications_none_rounded, t('Sonidos y alertas', 'Sounds and alerts'), const Color(0xffffca70)),
      ('social', Icons.people_outline_rounded, t('Escucha compartida y comunidad', 'Shared listening and community'), const Color(0xff7fc4c9)),
      ('dj', Icons.podcasts_rounded, t('MAI Radio / DJ de voz', 'MAI Radio / voice DJ'), const Color(0xff5CE1C5)),
      ('canvas', Icons.movie_outlined, t('Apple Music, Spotify y portadas animadas', 'Apple Music, Spotify and animated covers'), const Color(0xffb0a0ff)),
      ('advanced', Icons.tune_rounded, t('Funciones beta y herramientas', 'Beta features and tools'), const Color(0xffb0a0ff)),
    ];
    return Scaffold(
      backgroundColor: const Color(0xff0c0c0e),
      appBar: AppBar(title: Text(t('Ajustes', 'Settings')), foregroundColor: Colors.white, backgroundColor: Colors.transparent),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 36), children: [
        Text(t('Todo en su sitio.', 'Everything in its place.'), style: const TextStyle(color: Colors.white, fontSize: 23, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        Text(t('Cada categoría abre sus propios controles.', 'Each category opens its own controls.'), style: const TextStyle(color: Colors.white54, fontSize: 13)),
        const SizedBox(height: 18),
        for (final item in items)
          _editorCard(
            icon: item.$2,
            color: item.$4,
            title: _categoryTitle(item.$1),
            subtitle: item.$3,
            where: '',
            onTap: () {
              Navigator.of(context).push(
                PageRouteBuilder<void>(
                  transitionDuration: const Duration(milliseconds: 380),
                  reverseTransitionDuration:
                      const Duration(milliseconds: 300),
                  pageBuilder: (_, __, ___) =>
                      SettingsScreen(category: item.$1),
                  transitionsBuilder: (context, anim, secondary, child) {
                    final curved = CurvedAnimation(
                      parent: anim,
                      curve: Curves.easeOutCubic,
                      reverseCurve: Curves.easeInCubic,
                    );
                    return FadeTransition(
                      opacity: curved,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0.06, 0.04),
                          end: Offset.zero,
                        ).animate(curved),
                        child: ScaleTransition(
                          scale: Tween<double>(begin: 0.96, end: 1)
                              .animate(curved),
                          child: child,
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          ),
      ]),
    );
  }

  Widget _incompleteNote(String message) => Container(
    margin: const EdgeInsets.only(top: 12), padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: Colors.white.withOpacity(0.035), borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.white12)),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [const Icon(Icons.info_outline_rounded, color: Colors.white54, size: 19), const SizedBox(width: 10), Expanded(child: Text(message, style: const TextStyle(color: Colors.white60, fontSize: 12, height: 1.4)))]),
  );

  Future<void> _setListeningVisibility(bool value) async {
    final old = _showListening; setState(() => _showListening = value);
    try { await SupabaseService.updateListeningVisibility(value); }
    catch (error) { if (mounted) setState(() => _showListening = old); if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error'))); }
  }

  Future<void> _confirmAccountDeletion() async {
    final user = SupabaseService.currentUser;
    if (user == null || user.email == null) return;
    final confirm = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: Text(t('Eliminar cuenta permanentemente', 'Delete account permanently')),
      content: Text(t('Esta acción no se puede deshacer. Se verificará tu contraseña y el servidor procesará la eliminación. Si la función no está desplegada, no se eliminará nada.', 'This cannot be undone. Your password will be verified and the server will process deletion. If the function is not deployed, nothing will be deleted.')),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('Cancelar', 'Cancel'))), TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t('Continuar', 'Continue')))],
    ));
    if (confirm != true || !mounted) return;
    final password = TextEditingController();
    final pin = TextEditingController();
    final entered = await showDialog<List<String>>(context: context, builder: (ctx) => AlertDialog(
      title: Text(t('Verificar identidad', 'Verify identity')),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: password, obscureText: true, decoration: InputDecoration(labelText: t('Contraseña actual', 'Current password'))),
        if (user.email!.toLowerCase() == SupabaseService.reservedEmail) TextField(controller: pin, obscureText: true, decoration: InputDecoration(labelText: t('PIN de seguridad', 'Security PIN'))),
      ]),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t('Cancelar', 'Cancel'))), TextButton(onPressed: () => Navigator.pop(ctx, [password.text, pin.text]), child: Text(t('Verificar', 'Verify')))],
    ));
    password.dispose();
    pin.dispose();
    if (entered == null || entered[0].isEmpty) return;
    try {
      await SupabaseService.signIn(email: user.email!, password: entered[0], pin: entered.length > 1 && entered[1].isNotEmpty ? entered[1] : null);
      await SupabaseService.deleteCurrentAccount();
      await AccountSessionsService.instance.clear();
      if (mounted) Navigator.of(context).pushNamedAndRemoveUntil('/welcome', (_) => false);
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se pudo completar la eliminación: $e'))); }
  }


  Future<void> _showPasswordRecovery() async {
    final controller = TextEditingController(text: SupabaseService.currentUser?.email ?? '');
    final email = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xff19191e),
      title: Text(t('Restablecer contraseña', 'Reset password'), style: const TextStyle(color: Colors.white)),
      content: TextField(controller: controller, keyboardType: TextInputType.emailAddress, autofocus: true, style: const TextStyle(color: Colors.white), decoration: InputDecoration(labelText: t('Correo electrónico', 'Email address'), labelStyle: const TextStyle(color: Colors.white60))),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t('Cancelar', 'Cancel'))), TextButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()), child: Text(t('Enviar enlace', 'Send link')))],
    ));
    controller.dispose(); if (email == null || email.isEmpty) return;
    try { await SupabaseService.sendPasswordRecovery(email); if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t('Si la cuenta existe, recibirás un correo con el enlace seguro. No compartas ese enlace.', 'If the account exists, you will receive a secure recovery link. Do not share it.')))); }
    catch (error) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error'))); }
  }

  Future<void> _confirmSignOut() async {
    final confirmed = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xff19191e), title: Text(t('Cerrar sesión', 'Sign out'), style: const TextStyle(color: Colors.white)),
      content: Text(t('¿Quieres cerrar la sesión de esta cuenta en este dispositivo?', 'Do you want to sign out of this account on this device?'), style: const TextStyle(color: Colors.white70)),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('Cancelar', 'Cancel'))), TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t('Cerrar sesión', 'Sign out'), style: const TextStyle(color: Color(0xffff7777))))],
    ));
    if (confirmed != true) return;
    try { await SupabaseService.signOut(); if (mounted) Navigator.of(context).pushNamedAndRemoveUntil('/welcome', (route) => false); }
    catch (error) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error'))); }
  }

  void _openPlaylistDefaults() {
    Navigator.pushNamed(context, '/playlist_defaults');
  }

  Widget _editorCard({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required String where,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: const Color(0xFF141418),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withOpacity(0.08)),
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white.withOpacity(0.08)),
                  ),
                  child: Icon(icon, color: Colors.white70, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 15)),
                      const SizedBox(height: 3),
                      Text(subtitle,
                          style: TextStyle(
                              color: Colors.white.withOpacity(0.55),
                              fontSize: 12,
                              height: 1.3)),
                      const SizedBox(height: 4),
                      Text(where,
                          style: TextStyle(
                              color: Colors.white.withOpacity(0.35),
                              fontSize: 11,
                              fontWeight: FontWeight.w500)),
                    ],
                  ),
                ),
                Icon(Icons.arrow_forward_ios_rounded,
                    size: 16, color: Colors.white.withOpacity(0.35)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _section(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 22, 4, 10),
      child: Text(title,
          style: TextStyle(
            color: Colors.white.withOpacity(0.5),
            fontSize: 13,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
          )),
    );
  }
}


class _DjSettingsPanel extends StatefulWidget {
  const _DjSettingsPanel();
  @override
  State<_DjSettingsPanel> createState() => _DjSettingsPanelState();
}

class _DjSettingsPanelState extends State<_DjSettingsPanel> {
  bool _ready = false;
  bool _enabled = false;
  String _active = 'nugget_dj';
  String _placement = 'none';
  List<String> _djs = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final d = DjService.instance;
    await d.init();
    if (!mounted) return;
    setState(() {
      _enabled = d.enabled;
      _active = d.activeId;
      _placement = d.placement;
      _djs = d.availableDjs;
      _ready = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator(color: Color(0xff5CE1C5))),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile(
          title: const Text('Activar DJ de voz', style: TextStyle(color: Colors.white)),
          subtitle: const Text('Clips al pausar, saltar, shuffle…',
              style: TextStyle(color: Colors.white54, fontSize: 12)),
          value: _enabled,
          activeColor: const Color(0xff5CE1C5),
          onChanged: (v) async {
            await DjService.instance.setEnabled(v);
            setState(() => _enabled = v);
          },
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Text('Dónde mostrar MAI Radio',
              style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600)),
        ),
        RadioListTile<String>(
          value: 'none',
          groupValue: _placement,
          activeColor: const Color(0xff5CE1C5),
          title: const Text('Solo desde Ajustes', style: TextStyle(color: Colors.white)),
          subtitle: const Text('Abrir con el botón de abajo', style: TextStyle(color: Colors.white54, fontSize: 12)),
          onChanged: (v) async {
            if (v == null) return;
            await DjService.instance.setPlacement(v);
            setState(() => _placement = v);
          },
        ),
        RadioListTile<String>(
          value: 'home',
          groupValue: _placement,
          activeColor: const Color(0xff5CE1C5),
          title: const Text('Como tarjeta en Home', style: TextStyle(color: Colors.white)),
          subtitle: const Text('Aparece como una “canción” / atajo', style: TextStyle(color: Colors.white54, fontSize: 12)),
          onChanged: (v) async {
            if (v == null) return;
            await DjService.instance.setPlacement(v);
            setState(() => _placement = v);
          },
        ),
        RadioListTile<String>(
          value: 'nav',
          groupValue: _placement,
          activeColor: const Color(0xff5CE1C5),
          title: const Text('En el nav inferior', style: TextStyle(color: Colors.white)),
          subtitle: const Text('Sustituye un slot (requiere rebuild de nav)', style: TextStyle(color: Colors.white54, fontSize: 12)),
          onChanged: (v) async {
            if (v == null) return;
            await DjService.instance.setPlacement(v);
            setState(() => _placement = v);
          },
        ),
        if (_djs.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text('Voice pack', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600)),
          ),
          ..._djs.map((id) => RadioListTile<String>(
                value: id,
                groupValue: _active,
                activeColor: const Color(0xff5CE1C5),
                title: Text(id.replaceAll('_', ' '),
                    style: const TextStyle(color: Colors.white)),
                onChanged: (v) async {
                  if (v == null) return;
                  await DjService.instance.setActiveDj(v);
                  setState(() => _active = v);
                },
              )),
        ],
      ],
    );
  }
}
