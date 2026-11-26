import 'package:flutter/material.dart';
import 'package:nali/services/settings_service.dart';

/// Full-screen editor for playlist defaults (density, numbers, handles, sort, privacy).
class PlaylistDefaultsScreen extends StatefulWidget {
  const PlaylistDefaultsScreen({super.key});

  @override
  State<PlaylistDefaultsScreen> createState() => _PlaylistDefaultsScreenState();
}

class _PlaylistDefaultsScreenState extends State<PlaylistDefaultsScreen> {
  String t(String es, String en) =>
      SettingsService.instance.locale == 'en' ? en : es;

  @override
  Widget build(BuildContext context) {
    final s = SettingsService.instance;
    return Scaffold(
      backgroundColor: const Color(0xff0c0c0e),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: Text(t('Defaults de playlist', 'Playlist defaults')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(t('Listo', 'Done'),
                style: const TextStyle(
                    color: Color(0xfffc3c44), fontWeight: FontWeight.w700)),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: s,
        builder: (context, _) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
            children: [
              Text(t('Layout de lista', 'List layout'),
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              Row(
                children: [
                  for (final o in [
                    ('compact', t('Compacta', 'Compact')),
                    ('comfortable', t('Cómoda', 'Comfortable')),
                    ('large', t('Grande', 'Large')),
                  ])
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: ChoiceChip(
                          label: Center(child: Text(o.$2)),
                          selected: s.playlistListLayout == o.$1,
                          selectedColor: const Color(0xfffc3c44),
                          labelStyle: TextStyle(
                            color: s.playlistListLayout == o.$1
                                ? Colors.white
                                : Colors.white70,
                          ),
                          backgroundColor: Colors.white10,
                          onSelected: (_) => s.setString('pl_list_layout', o.$1),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(t('Numeración', 'Numbering'),
                    style: const TextStyle(color: Colors.white)),
                subtitle: Text(
                    t('Muestra #1, #2… en el detalle',
                        'Show #1, #2… on detail'),
                    style: const TextStyle(color: Colors.white54, fontSize: 12)),
                value: s.playlistShowNumbers,
                activeColor: const Color(0xfffc3c44),
                onChanged: (v) => s.setFlag('pl_numbers', v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(t('Asas de arrastre', 'Drag handles'),
                    style: const TextStyle(color: Colors.white)),
                subtitle: Text(
                    t('Permite reordenar canciones', 'Allow reordering tracks'),
                    style: const TextStyle(color: Colors.white54, fontSize: 12)),
                value: s.playlistDragHandles,
                activeColor: const Color(0xfffc3c44),
                onChanged: (v) => s.setFlag('pl_drag', v),
              ),
              const SizedBox(height: 12),
              Text(t('Orden por defecto', 'Default sort'),
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              for (final o in [
                ('manual', t('Manual', 'Manual')),
                ('title', t('Título', 'Title')),
                ('artist', t('Artista', 'Artist')),
                ('recent', t('Recientes', 'Recent')),
              ])
                RadioListTile<String>(
                  value: o.$1,
                  groupValue: s.playlistDefaultSort,
                  activeColor: const Color(0xfffc3c44),
                  title: Text(o.$2, style: const TextStyle(color: Colors.white)),
                  onChanged: (v) {
                    if (v != null) s.setString('pl_sort', v);
                  },
                ),
              const SizedBox(height: 8),
              Text(t('Privacidad por defecto', 'Default privacy'),
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w700)),
              for (final o in [
                ('private', t('Privada', 'Private')),
                ('public', t('Pública', 'Public')),
              ])
                RadioListTile<String>(
                  value: o.$1,
                  groupValue: s.playlistDefaultPrivacy,
                  activeColor: const Color(0xfffc3c44),
                  title: Text(o.$2, style: const TextStyle(color: Colors.white)),
                  onChanged: (v) {
                    if (v != null) s.setString('pl_privacy', v);
                  },
                ),
            ],
          );
        },
      ),
    );
  }
}
