import 'package:flutter/material.dart';
import 'package:nali/services/notification_service.dart';
import 'package:nali/services/player_controller.dart';
import 'package:nali/services/settings_service.dart';
import 'package:nali/widgets/liquid_glass.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  bool _refreshing = false;

  String t(String es, String en) =>
      SettingsService.instance.locale == 'en' ? en : es;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    await NotificationService.instance.load();
    await _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _refreshing = true);
    await NotificationService.instance.refreshFromFollows();
    if (mounted) setState(() => _refreshing = false);
  }

  Widget _fallbackCover(Map<String, dynamic> n) {
    final isChat = n['type'] == 'chat';
    return Container(
      width: 52,
      height: 52,
      color: const Color(0xFF1A1A1E),
      child: Icon(
        isChat ? Icons.chat_bubble_outline_rounded : Icons.album_outlined,
        color: const Color(0xfffc3c44).withOpacity(0.85),
        size: 24,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: NotificationService.instance,
      builder: (context, _) {
        final items = NotificationService.instance.items;
        return Scaffold(
          backgroundColor: const Color(0xFF0C0C0E),
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            title: Text(t('Notificaciones', 'Notifications')),
            actions: [
              if (items.isNotEmpty) ...[
                TextButton(
                  onPressed: () => NotificationService.instance.markAllRead(),
                  child: Text(t('Leer todo', 'Read all'),
                      style: const TextStyle(color: Colors.white70)),
                ),
                TextButton(
                  onPressed: () async {
                    await NotificationService.instance.clear();
                    if (mounted) setState(() {});
                  },
                  child: Text(t('Borrar todo', 'Clear all'),
                      style: const TextStyle(color: Color(0xfffc3c44))),
                ),
              ],
              IconButton(
                onPressed: _refreshing ? null : _refresh,
                icon: _refreshing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white54),
                      )
                    : const Icon(Icons.refresh),
              ),
            ],
          ),
          body: items.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      t(
                        'Cuando un artista que sigues tenga canciones nuevas en el catálogo, aparecerán aquí.',
                        'When an artist you follow has new tracks in the catalog, they show up here.',
                      ),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: Colors.white.withOpacity(0.45), height: 1.4),
                    ),
                  ),
                )
              : RefreshIndicator(
                  color: const Color(0xfffc3c44),
                  onRefresh: _refresh,
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 40),
                    itemCount: items.length,
                    itemBuilder: (ctx, i) {
                      final n = items[i];
                      final read = n['read'] == true;
                      final song = n['song'];
                      final cover = song is Map
                          ? (song['cover_url'] ??
                                  song['artwork_url'] ??
                                  song['thumbnail_url'] ??
                                  '')
                              .toString()
                          : '';
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: LiquidGlass(
                          blur: 18,
                          opacity: read ? 0.05 : 0.14,
                          borderRadius: BorderRadius.circular(16),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            leading: ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: cover.startsWith('http')
                                  ? Image.network(
                                      cover,
                                      width: 52,
                                      height: 52,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) =>
                                          _fallbackCover(n),
                                    )
                                  : _fallbackCover(n),
                            ),
                            title: Text(
                              n['title'] ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight:
                                    read ? FontWeight.w500 : FontWeight.w700,
                                fontSize: 15,
                              ),
                            ),
                            subtitle: Text(
                              n['body'] ?? '',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.55),
                                height: 1.25,
                              ),
                            ),
                            trailing: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                if (!read)
                                  Container(
                                    width: 8,
                                    height: 8,
                                    margin: const EdgeInsets.only(bottom: 6),
                                    decoration: const BoxDecoration(
                                      color: Color(0xfffc3c44),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                Icon(
                                  n['type'] == 'chat'
                                      ? Icons.chat_bubble_outline_rounded
                                      : Icons.album_outlined,
                                  size: 16,
                                  color: Colors.white38,
                                ),
                              ],
                            ),
                            onTap: () async {
                              await NotificationService.instance
                                  .markRead(n['id']?.toString() ?? '');
                              if (song is Map<String, dynamic>) {
                                await PlayerController.instance
                                    .playSong(Map<String, dynamic>.from(song));
                              }
                            },
                          ),
                        ),
                      );
                    },
                  ),
                ),
        );
      },
    );
  }
}
