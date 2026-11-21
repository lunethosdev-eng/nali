import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:nali/services/supabase_service.dart';
import 'package:nali/services/settings_service.dart';
import 'package:nali/services/provider_service.dart';
import 'package:nali/services/account_sessions_service.dart';
import 'package:nali/services/listening_history.dart';
import 'package:nali/services/spotify_service.dart';
import 'package:nali/services/player_controller.dart';
import 'package:nali/services/local_music_service.dart';
import 'package:nali/services/notification_service.dart';
import 'package:nali/services/media_audio_handler.dart';
import 'package:app_links/app_links.dart';
import 'package:nali/screens/auth_screen.dart';
import 'package:nali/screens/password_recovery_screen.dart';
import 'package:nali/screens/welcome_screen.dart';
import 'package:nali/Bottom%20NavBar/bottom_nav.dart';
import 'package:nali/pages/list.dart';
import 'package:nali/pages/album_page.dart';
import 'package:nali/pages/artist_list.dart';
import 'package:nali/pages/artist_page.dart';
import 'package:nali/pages/browse_page.dart';
import 'package:nali/pages/home_page.dart';
import 'package:nali/pages/music_list.dart';
import 'package:nali/pages/music_player.dart';
import 'package:nali/pages/radio.dart';
import 'package:nali/pages/search_page.dart';
import 'package:nali/pages/library_page.dart';
import 'package:nali/screens/profile_edit_screen.dart';
import 'package:nali/screens/admin_screen.dart';
import 'package:nali/screens/settings_screen.dart';
import 'package:nali/screens/mix_editor_screen.dart';
import 'package:nali/screens/player_layout_editor_screen.dart';
import 'package:nali/screens/playlists_screen.dart';
import 'package:nali/screens/wrap_screen.dart';
import 'package:nali/screens/local_import_screen.dart';
import 'package:nali/screens/notifications_screen.dart';
import 'package:nali/services/font_manager_service.dart';
import 'package:nali/services/nali_links.dart';
import 'package:nali/services/native_player_bridge.dart';
import 'package:nali/screens/playlist_detail_screen.dart';

final GlobalKey<NavigatorState> _naliNavigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SupabaseService.init();
  await SettingsService.instance.load();
  await ProviderService.instance.load();
  await FontManagerService.instance.applySavedFont();
  await ListeningHistory.instance.load();
  // Spotify disabled (no Premium)
  await PlayerController.instance.restoreSession();
  await LocalMusicService.instance.load();
  await NotificationService.instance.load();
  // background check for followed-artist releases
  NotificationService.instance.refreshFromFollows();
  // Android's Media3 PlaybackService owns the one native MediaSession.
  // Starting audio_service as well would create a second notification/session.
  if (!kIsWeb && (defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.macOS)) {
    await initMediaAudioService();
  }
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));
  runApp(const NaliApp());
}

class NaliApp extends StatefulWidget {
  const NaliApp({super.key});

  @override
  State<NaliApp> createState() => _NaliAppState();
}

class _NaliAppState extends State<NaliApp> {
  StreamSubscription<Uri>? _linkSubscription;
  StreamSubscription<AuthState>? _authSubscription;
  bool _recoveryRouteOpened = false;
  final Set<String> _handledLinks = <String>{};

  @override
  void initState() {
    super.initState();
    _listenIncomingLinks();
    _authSubscription = SupabaseService.kokoro.auth.onAuthStateChange.listen((data) {
      if (data.event == AuthChangeEvent.signedIn || data.event == AuthChangeEvent.tokenRefreshed) {
        unawaited(AccountSessionsService.instance.saveCurrent().catchError((Object e) => debugPrint('Account session save: $e')));
      }
      if (data.event == AuthChangeEvent.passwordRecovery && !_recoveryRouteOpened) {
        _recoveryRouteOpened = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final nav = _naliNavigatorKey.currentState;
          if (nav != null) nav.push(MaterialPageRoute<void>(builder: (_) => const PasswordRecoveryScreen())).then((_) => _recoveryRouteOpened = false);
        });
      }
    });
  }

  @override
  void dispose() {
    _linkSubscription?.cancel();
    _authSubscription?.cancel();
    super.dispose();
  }

  void _listenIncomingLinks() {
    if (!kIsWeb) {
      final appLinks = AppLinks();
      _linkSubscription = appLinks.uriLinkStream.listen(
        _handleIncomingUri,
        onError: (Object error) => debugPrint('Nali incoming link: $error'),
      );
      unawaited(appLinks.getInitialLink().then((uri) {
        if (uri != null) _handleIncomingUri(uri);
      }).catchError((Object error) {
        debugPrint('Nali initial link: $error');
      }));
    } else if (Uri.base.fragment.startsWith('/')) {
      // GitHub Pages Flutter routes are published in the URL fragment.
      WidgetsBinding.instance.addPostFrameCallback((_) => _handleIncomingUri(Uri.base));
    }
  }

  Future<void> _handleIncomingUri(Uri uri) async {
    if (uri.scheme == 'pokke' || uri.scheme == 'nali') {
      final handled = await SpotifyService.instance.handleIncomingLink(uri);
      if (handled) return;
    }
    final link = NaliSharedLink.parse(uri);
    if (link == null || !_handledLinks.add(uri.toString())) return;

    // Wait for the root navigator to exist (including the initial boot route).
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final navigator = _naliNavigatorKey.currentState;
      if (navigator == null) return;
      try {
        if (link.kind == 'song' || link.kind == 'lyrics') {
          var row = await SupabaseService.ukiyo
              .from('songs').select().eq('id', link.id).maybeSingle();
          row ??= await SupabaseService.ukiyo
              .from('songs').select().eq('youtube_id', link.id).maybeSingle();
          if (row == null) throw StateError('La canción ya no está disponible.');
          final song = Map<String, dynamic>.from(row);
          await PlayerController.instance.playSong(song, forceRestart: true);
          if (link.kind == 'lyrics' && link.start != null) {
            await PlayerController.instance.seekTo(Duration(seconds: link.start!));
          }
          if (NativePlayerBridge.instance.supported) {
            await NativePlayerBridge.instance.invoke('openNativePlayer');
          } else {
            navigator.pushNamed('/player', arguments: song);
          }
          return;
        }

        if (link.kind == 'playlist') {
          final row = await SupabaseService.kokoro
              .from('playlists').select().eq('id', link.id).maybeSingle();
          if (row == null) throw StateError('La playlist ya no está disponible.');
          navigator.push(MaterialPageRoute<void>(
            builder: (_) => PlaylistDetailScreen(playlist: Map<String, dynamic>.from(row)),
          ));
          return;
        }

        final label = switch (link.kind) {
          'profile' => 'El perfil compartido todavía no tiene una pantalla pública Flutter conectada.',
          'artist' => 'El identificador de artista todavía no tiene un repositorio público conectado.',
          'album' => 'El identificador de álbum todavía no tiene un repositorio público conectado.',
          _ => 'Este enlace de Nali no es compatible o está incompleto.',
        };
        ScaffoldMessenger.of(navigator.context).showSnackBar(SnackBar(content: Text(label)));
      } catch (error) {
        final context = navigator.context;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.toString().replaceFirst('Bad state: ', ''))),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: SettingsService.instance,
      builder: (context, _) => MaterialApp(
      navigatorKey: _naliNavigatorKey,
      title: 'Nali',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xfffc3c44), brightness: Brightness.light),
        fontFamily: SettingsService.instance.fontFamily,
        scaffoldBackgroundColor: const Color(0xfff5f5f7),
        appBarTheme: const AppBarTheme(backgroundColor: Colors.transparent, elevation: 0),
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xfffc3c44), brightness: Brightness.dark),
        fontFamily: SettingsService.instance.fontFamily,
        scaffoldBackgroundColor: const Color.fromARGB(255, 12, 12, 14),
        appBarTheme: const AppBarTheme(backgroundColor: Colors.transparent, elevation: 0),
      ),
      themeMode: switch (SettingsService.instance.themeModePreference) {
        'light' => ThemeMode.light,
        'system' => ThemeMode.system,
        _ => ThemeMode.dark,
      },
      debugShowCheckedModeBanner: false,
      initialRoute: '/boot',
      routes: {
        '/boot': (context) => const _BootGate(),
        '/welcome': (context) => const WelcomeScreen(),
        '/auth': (context) => const AuthScreen(),
        '/list_test': (context) => ListTest(),
        '/firstpage': (context) => FirstPage(),
        '/browse': (context) => BrowsePage(),
        '/radio': (context) => RadioPage(),
        '/library': (context) => LibraryPage(),
        '/search': (context) => SearchPage(),
        '/home': (context) => HomePage(),
        '/album': (context) => AlbumPage(),
        '/artist': (context) => ArtistPage(),
        '/artistlist': (context) => ArtistList(),
        '/musiclist': (context) => MusicList(),
        '/profile_edit': (context) => const ProfileEditScreen(),
        '/admin': (context) => const AdminScreen(),
        '/settings': (context) => const SettingsScreen(),
        '/mix': (context) => const MixEditorScreen(),
        '/player_editor': (context) => const PlayerLayoutEditorScreen(),
        '/playlists': (context) => const PlaylistsScreen(),
        '/wrap': (context) => const WrapScreen(),
        '/local_import': (context) => const LocalImportScreen(),
        '/notifications': (context) => const NotificationsScreen(),
      },
      // Full player always uses slide-up + fade (never default Material popup)
      onGenerateRoute: (settings) {
        if (settings.name == '/player') {
          final args = settings.arguments;
          final song = args is Map<String, dynamic> ? args : <String, dynamic>{};
          if (NativePlayerBridge.instance.supported) {
            return SlideUpPageRoute<void>(page: _NativePlayerHandoff(song: song));
          }
          return MusicPlayer.route(song);
        }
        return null;
      },
    ));
  }
}


class _NativePlayerHandoff extends StatefulWidget {
  final Map<String, dynamic> song;
  const _NativePlayerHandoff({required this.song});

  @override
  State<_NativePlayerHandoff> createState() => _NativePlayerHandoffState();
}

class _NativePlayerHandoffState extends State<_NativePlayerHandoff> {
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _open());
  }

  Future<void> _open() async {
    try {
      if (widget.song.isNotEmpty) {
        await PlayerController.instance.playSong(widget.song, forceRestart: true);
      }
      await NativePlayerBridge.instance.invoke<bool>('openNativePlayer');
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }


  Future<void> _retryNative() async {
    try {
      setState(() => _error = null);
      await NativePlayerBridge.instance.invoke<bool>('openNativePlayer');
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFF0C0C0E),
    body: Center(child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.music_note_rounded, color: Color(0xfffc3c44), size: 38),
        const SizedBox(height: 12),
        Text(_error == null ? 'Abriendo BitChord Now Playing…' : 'No se pudo abrir BitChord', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white54, fontSize: 12)),
          const SizedBox(height: 12),
          TextButton(
            onPressed: _retryNative,
            child: const Text('Intentar abrir BitChord de nuevo'),
          ),
        ] else ...[
          const SizedBox(height: 16),
          const CircularProgressIndicator(color: Color(0xfffc3c44)),
        ],
      ]),
    )),
  );
}

class SlideUpPageRoute<T> extends PageRouteBuilder<T> {
  final Widget page;
  SlideUpPageRoute({required this.page})
      : super(
          pageBuilder: (_, __, ___) => page,
          transitionsBuilder: (_, anim, __, child) {
            final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
            return SlideTransition(
              position: Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero).animate(curved),
              child: FadeTransition(opacity: curved, child: child),
            );
          },
          transitionDuration: const Duration(milliseconds: 380),
          reverseTransitionDuration: const Duration(milliseconds: 320),
        );
}



class _BootGate extends StatefulWidget {
  const _BootGate();
  @override
  State<_BootGate> createState() => _BootGateState();
}

class _BootGateState extends State<_BootGate> {
  String? _error;

  @override
  void initState() {
    super.initState();
    // Wait one frame so Navigator is ready
    WidgetsBinding.instance.addPostFrameCallback((_) => _go());
  }

  Future<void> _go() async {
    try {
      final p = await SharedPreferences.getInstance()
          .timeout(const Duration(seconds: 3));
      final seen = p.getBool('welcome_seen') ?? false;
      if (!mounted) return;
      if (!seen) {
        Navigator.pushReplacementNamed(context, '/welcome');
        return;
      }
      Navigator.pushReplacementNamed(
        context,
        SupabaseService.isLoggedIn ? '/firstpage' : '/auth',
      );
    } catch (e) {
      debugPrint('BootGate error: $e');
      if (!mounted) return;
      // Never stay black: fall through to auth/home
      try {
        Navigator.pushReplacementNamed(
          context,
          SupabaseService.isLoggedIn ? '/firstpage' : '/auth',
        );
      } catch (e2) {
        setState(() => _error = e2.toString());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF050507),
      body: Center(
        child: _error == null
            ? const CircularProgressIndicator(color: Color(0xfffc3c44))
            : Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Error al iniciar',
                        style: TextStyle(color: Colors.white, fontSize: 16)),
                    const SizedBox(height: 8),
                    Text(_error!,
                        style: TextStyle(color: Colors.white54, fontSize: 12),
                        textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xfffc3c44)),
                      onPressed: () {
                        Navigator.pushReplacementNamed(context, '/auth');
                      },
                      child: const Text('Ir a login',
                          style: TextStyle(color: Colors.white)),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
