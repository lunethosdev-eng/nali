import 'package:flutter/material.dart';
import 'package:nali/widgets/compact_header.dart';
import 'package:nali/widgets/liquid_glass.dart';
import 'package:nali/services/listening_history.dart';
import 'package:nali/services/settings_service.dart';
import 'package:nali/services/local_music_service.dart';
import 'package:nali/services/notification_service.dart';
import 'package:nali/services/player_controller.dart';

class LibraryPage extends StatefulWidget {
  LibraryPage({super.key});

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  final _scrollCtrl = ScrollController();
  bool _collapsed = false;
  bool _loading = true;
  List<Map<String, dynamic>> _recent = [];

  String t(String es, String en) =>
      SettingsService.instance.locale == 'en' ? en : es;

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(() {
      final c = _scrollCtrl.offset > 40;
      if (c != _collapsed) setState(() => _collapsed = c);
    });
    _load();
    LocalMusicService.instance.load();
    NotificationService.instance.load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      if (!SettingsService.instance.flag('priv_history_local', def: true)) {
        if (mounted) setState(() => _recent = []);
      } else {
        final rows = await ListeningHistory.instance.recent(limit: 50);
        if (mounted) setState(() => _recent = rows);
      }
    } catch (_) {
      if (mounted) setState(() => _recent = []);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  Widget _libraryCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    Color accent = const Color(0xfffc3c44),
    String? count,
  }) {
    return LiquidGlass(
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: accent.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Icon(icon, color: accent, size: 22),
                  ),
                  const Spacer(),
                  if (count != null)
                    Text(count,
                        style: TextStyle(
                            color: Colors.white.withOpacity(0.48),
                            fontWeight: FontWeight.w700,
                            fontSize: 12)),
                  const Icon(Icons.arrow_outward_rounded,
                      color: Colors.white38, size: 16),
                ],
              ),
              const SizedBox(height: 18),
              Text(title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 3),
              Text(subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.48), fontSize: 11)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _shortcuts(BuildContext context, int localCount, int unread) {
    final width = MediaQuery.sizeOf(context).width;
    final columns = width >= 720 ? 4 : 2;
    final cards = <Widget>[
      _libraryCard(
        icon: Icons.queue_music_rounded,
        title: t('Playlists', 'Playlists'),
        subtitle: t('Tus colecciones y mezclas', 'Your collections and mixes'),
        onTap: () => Navigator.pushNamed(context, '/playlists'),
      ),
      _libraryCard(
        icon: Icons.person_rounded,
        title: t('Artistas', 'Artists'),
        subtitle: t('Artistas guardados y seguidos', 'Saved and followed artists'),
        accent: const Color(0xffa78bfa),
        onTap: () => Navigator.pushNamed(context, '/artistlist'),
      ),
      _libraryCard(
        icon: Icons.folder_copy_rounded,
        title: t('Música local', 'Local music'),
        subtitle: t('Archivos de este dispositivo', 'Files on this device'),
        accent: const Color(0xff6ed6b1),
        count: localCount > 0 ? '$localCount' : null,
        onTap: () => Navigator.pushNamed(context, '/local_import'),
      ),
      _libraryCard(
        icon: Icons.notifications_active_rounded,
        title: t('Notificaciones', 'Notifications'),
        subtitle: t('Novedades y actividad', 'Updates and activity'),
        accent: const Color(0xffffb86b),
        count: unread > 0 ? '$unread' : null,
        onTap: () => Navigator.pushNamed(context, '/notifications'),
      ),
    ];
    return GridView.count(
      crossAxisCount: columns,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: width >= 720 ? 1.35 : 1.22,
      children: cards,
    );
  }

  Widget _recentList() {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 26),
        child: Center(child: CircularProgressIndicator(color: Color(0xfffc3c44))),
      );
    }
    if (_recent.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.035),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withOpacity(0.07)),
        ),
        child: Column(children: [
          const Icon(Icons.history_rounded, color: Colors.white38, size: 30),
          const SizedBox(height: 10),
          Text(t('Tu historial aparecerá aquí', 'Your listening history will appear here'),
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
          const SizedBox(height: 5),
          Text(t('Reproduce música para llenar tu biblioteca.', 'Play music to start filling your library.'),
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withOpacity(0.45), fontSize: 12)),
        ]),
      );
    }
    final grid = SettingsService.instance.libraryGrid;
    if (grid) {
      final width = MediaQuery.sizeOf(context).width;
      return GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: _recent.length.clamp(0, 24),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: width >= 720 ? 4 : 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 0.82,
        ),
        itemBuilder: (_, i) {
          final song = _recent[i];
          final cover = song['cover_url'];
          return GestureDetector(
            onTap: () => PlayerController.instance.playSong(song),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: SizedBox.expand(
                    child: cover != null
                        ? Image.network(cover.toString(), fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const ColoredBox(color: Colors.white10))
                        : const ColoredBox(color: Colors.white10),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(song['title'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12)),
              Text(song['artist'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.white.withOpacity(0.48), fontSize: 11)),
            ]),
          );
        },
      );
    }
    return Column(
      children: _recent.take(30).map((song) {
        final cover = song['cover_url'];
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(vertical: 2),
          leading: ClipRRect(
            borderRadius: BorderRadius.circular(9),
            child: cover != null
                ? Image.network(cover.toString(), width: 50, height: 50, fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox(width: 50, height: 50, child: ColoredBox(color: Colors.white10)))
                : const SizedBox(width: 50, height: 50, child: ColoredBox(color: Colors.white10)),
          ),
          title: Text(song['title'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
          subtitle: Text(song['artist'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(color: Colors.white.withOpacity(0.48), fontSize: 12)),
          trailing: IconButton(
            icon: const Icon(Icons.play_circle_fill_rounded, color: Colors.white70, size: 28),
            onPressed: () => PlayerController.instance.playSong(song),
          ),
          onTap: () => PlayerController.instance.playSong(song),
        );
      }).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SettingsService.instance.amoled
          ? Colors.black
          : const Color(0xFF0C0C0E),
      appBar: CompactHeader(title: t('Biblioteca', 'Library'), collapsed: _collapsed),
      body: RefreshIndicator(
        color: const Color(0xfffc3c44),
        onRefresh: _load,
        child: AnimatedBuilder(
          animation: Listenable.merge([
            LocalMusicService.instance,
            NotificationService.instance,
            SettingsService.instance,
          ]),
          builder: (context, _) {
            final localCount = LocalMusicService.instance.tracks.length;
            final unread = NotificationService.instance.unread;
            final shortcuts = _shortcuts(context, localCount, unread);
            final recents = _recentList();
            final recentsFirst = SettingsService.instance.libraryRecentsFirst;
            return SingleChildScrollView(
              controller: _scrollCtrl,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 140),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(2, 4, 2, 18),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(t('Tu colección', 'Your collection'),
                          style: const TextStyle(color: Colors.white, fontSize: 25, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 5),
                      Text(t('Todo lo que guardas, sigues y escuchas.', 'Everything you save, follow and listen to.'),
                          style: TextStyle(color: Colors.white.withOpacity(0.48), fontSize: 13)),
                    ]),
                  ),
                  if (recentsFirst) ...[
                    _sectionTitle(t('Escuchado recientemente', 'Recently played')),
                    recents,
                    const SizedBox(height: 24),
                  ],
                  _sectionTitle(t('Tu biblioteca', 'Your library')),
                  shortcuts,
                  const SizedBox(height: 24),
                  if (!recentsFirst) ...[
                    _sectionTitle(t('Escuchado recientemente', 'Recently played')),
                    recents,
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _sectionTitle(String title) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(title, style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w800)),
      );
}
