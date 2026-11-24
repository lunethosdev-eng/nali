import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:nali/services/nali_links.dart';
import 'package:nali/services/supabase_service.dart';
import 'package:nali/services/settings_service.dart';
import 'package:nali/services/mangadex_service.dart';
// profile theme via SettingsService
import 'package:nali/widgets/liquid_glass.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ProfileEditScreen extends StatefulWidget {
  const ProfileEditScreen({super.key});

  @override
  State<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends State<ProfileEditScreen> {
  final _displayNameCtrl = TextEditingController();
  final _usernameCtrl = TextEditingController();
  final _bioCtrl = TextEditingController();
  final _pronounsCtrl = TextEditingController();
  final _statusCtrl = TextEditingController();
  final _badgesCtrl = TextEditingController();
  final List<Map<String, String?>> _favoriteMangas = [];
  final _linkLabelCtrl = TextEditingController();
  final _linkUrlCtrl = TextEditingController();
  bool _isPublic = true;
  bool _showListening = true;
  String? _avatarUrl;
  String? _bannerUrl;
  File? _newAvatar;
  File? _newBanner;
  bool _loading = true;
  bool _saving = false;
  String _theme = 'default';
  final _picker = ImagePicker();

  final _themes = <String, List<Color>>{
    'default': [const Color(0xFF0C0C0E), const Color(0xFF1A1A1E)],
    'sunset': [const Color(0xFF2D1B0E), const Color(0xFFfc3c44)],
    'ocean': [const Color(0xFF0A1628), const Color(0xFF1B6CA8)],
    'violet': [const Color(0xFF1A0A2E), const Color(0xFF9B59B6)],
    'mint': [const Color(0xFF0A1F1A), const Color(0xFF2ECC71)],
    'gold': [const Color(0xFF1A1508), const Color(0xFFD4AF37)],
    'rose': [const Color(0xFF1A0A12), const Color(0xFFE91E63)],
    'cyber': [const Color(0xFF050510), const Color(0xFF00E5FF)],
    'ember': [const Color(0xFF1A0C05), const Color(0xFFFF6D00)],
  };
  String _effect = 'glass';
  final _effects = const ['none', 'glass', 'parallax', 'glow'];
  final _frames = const ['none', 'ring', 'neon', 'pixel', 'soft'];
  String _frame = 'none';

  String t(String es, String en) => SettingsService.instance.locale == 'en' ? en : es;

  @override
  void dispose() {
    _displayNameCtrl.dispose();
    _usernameCtrl.dispose();
    _bioCtrl.dispose();
    _pronounsCtrl.dispose();
    _statusCtrl.dispose();
    _badgesCtrl.dispose();
    _linkLabelCtrl.dispose();
    _linkUrlCtrl.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final profile = await SupabaseService.getProfile();
    if (profile != null) {
      _displayNameCtrl.text = profile['display_name'] ?? '';
      _usernameCtrl.text = profile['username'] ?? '';
      _bioCtrl.text = profile['bio'] ?? '';
      _pronounsCtrl.text = profile['pronouns'] ?? '';
      _statusCtrl.text = profile['status_text'] ?? '';
      _badgesCtrl.text = profile['badges'] ?? '';
      final mangasValue = profile['favorite_mangas'];
      final rawMangas = mangasValue is String ? mangasValue : jsonEncode(mangasValue ?? []);
      _favoriteMangas.clear();
      try {
        final decoded = jsonDecode(rawMangas);
        if (decoded is List) {
          for (final item in decoded) {
            if (item is Map && (item['title']?.toString().trim().isNotEmpty ?? false)) {
              _favoriteMangas.add({
                'id': item['id']?.toString() ?? '',
                'title': item['title'].toString(),
                'cover': item['cover']?.toString(),
              });
            }
          }
        }
      } catch (_) {}
      _linkLabelCtrl.text = profile['link_label'] ?? '';
      _linkUrlCtrl.text = profile['link_url'] ?? '';
      _isPublic = profile['is_public'] != false;
      _showListening = profile['show_listening'] != false;
      _avatarUrl = profile['avatar_url'];
      _bannerUrl = profile['banner_url'];
      _theme = profile['theme']?.toString()
          ?? SettingsService.instance.profileTheme
          ?? 'default';
      _effect = profile['effect']?.toString()
          ?? SettingsService.instance.profileEffect
          ?? 'glass';
      _frame = profile['frame']?.toString()
          ?? SettingsService.instance.profileFrame
          ?? 'none';
    }
    if (mounted) setState(() => _loading = false);
  }

  String _mangaJsonFromSelected() => jsonEncode(_favoriteMangas.take(12).map((item) => {
    'id': item['id'] ?? '',
    'title': item['title'] ?? '',
    'cover': item['cover'],
  }).toList());

  Future<void> _showMangaPicker() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => _MangaPickerDialog(
        search: (query) => MangaDexService.instance.search(query),
        selectedIds: _favoriteMangas.map((m) => m['id'] ?? '').toSet(),
        onSelect: (item) {
          if (_favoriteMangas.length >= 12 || _favoriteMangas.any((m) => m['id'] == item['id'])) return;
          setState(() => _favoriteMangas.add(item));
        },
        count: _favoriteMangas.length,
        onCountChanged: () => setState(() {}),
        strings: (es, en) => t(es, en),
      ),
    );
  }


  Future<void> _pickMedia({required bool isAvatar}) async {
    final xfile = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (xfile == null) return;
    setState(() {
      if (isAvatar) {
        _newAvatar = File(xfile.path);
      } else {
        _newBanner = File(xfile.path);
      }
    });
  }

  Future<String?> _uploadFile(File file, String folder) async {
    final userId = SupabaseService.currentUser?.id;
    if (userId == null) return null;
    final ext = file.path.split('.').last.toLowerCase();
    final path = '$folder/$userId/${DateTime.now().millisecondsSinceEpoch}.$ext';
    await SupabaseService.kokoro.storage.from('avatars').upload(
          path,
          file,
          fileOptions: const FileOptions(upsert: true),
        );
    return SupabaseService.kokoro.storage.from('avatars').getPublicUrl(path);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      String? avatar = _avatarUrl;
      String? banner = _bannerUrl;
      if (_newAvatar != null) avatar = await _uploadFile(_newAvatar!, 'avatars');
      if (_newBanner != null) banner = await _uploadFile(_newBanner!, 'banners');
      await SupabaseService.updateProfile(
        displayName: _displayNameCtrl.text.trim(),
        bio: _bioCtrl.text.trim(),
        avatarUrl: avatar,
        bannerUrl: banner,
        username: _usernameCtrl.text.trim().isEmpty ? null : _usernameCtrl.text.trim(),
        pronouns: _pronounsCtrl.text,
        statusText: _statusCtrl.text,
        badges: _badgesCtrl.text,
        isPublic: _isPublic,
        linkLabel: _linkLabelCtrl.text,
        linkUrl: _linkUrlCtrl.text,
        showListening: _showListening,
        favoriteMangas: _mangaJsonFromSelected(),
      );
      // theme column best-effort
      SettingsService.instance.profileTheme = _theme;
      SettingsService.instance.profileEffect = _effect;
      await SettingsService.instance.save();
      try {
        await SupabaseService.kokoro.from('profiles').update({
          'theme': _theme,
          'effect': _effect,
          'frame': _frame,
        }).eq('id', SupabaseService.currentUser!.id);
      } catch (_) {}
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t('Perfil guardado', 'Profile saved')), backgroundColor: const Color(0xfffc3c44)),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _shareProfile() {
    final name = _displayNameCtrl.text.trim().isEmpty ? 'Nali' : _displayNameCtrl.text.trim();
    final id = SupabaseService.currentUser?.id ?? '';
    if (id.isEmpty) return;
    NaliLinks.share('@$name', NaliLinks.profile(id),
      description: t('Mira mi perfil en Nali', 'Check my Nali profile on Nali'));
  }


  Widget _applyEffect(Widget child) {
    switch (_effect) {
      case 'glass':
        return ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            fit: StackFit.passthrough,
            children: [
              child,
              Positioned.fill(
                child: IgnorePointer(
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white.withOpacity(0.18)),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Colors.white.withOpacity(0.12),
                          Colors.white.withOpacity(0.02),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      case 'glow':
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: (_themes[_theme] ?? _themes['default']!).last
                    .withOpacity(0.55),
                blurRadius: 28,
                spreadRadius: 2,
              ),
            ],
          ),
          child: child,
        );
      case 'parallax':
        return Transform(
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.001)
            ..rotateX(-0.04)
            ..rotateY(0.03),
          alignment: Alignment.center,
          child: child,
        );
      default:
        return child;
    }
  }

  Widget _profileField(TextEditingController controller, String label, {String? hint, int maxLines = 1, TextInputType? keyboardType}) {
    return LiquidGlass(
      blur: 14, opacity: 0.08, borderRadius: BorderRadius.circular(14),
      child: TextField(
        controller: controller, maxLines: maxLines, keyboardType: keyboardType,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          labelText: label, hintText: hint,
          labelStyle: TextStyle(color: Colors.white.withOpacity(0.45)),
          hintStyle: TextStyle(color: Colors.white.withOpacity(0.25)),
          border: InputBorder.none, contentPadding: const EdgeInsets.all(14),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = _themes[_theme] ?? _themes['default']!;
    if (_loading) {
      return const Scaffold(
        backgroundColor: Color(0xFF0C0C0E),
        body: Center(child: CircularProgressIndicator(color: Color(0xfffc3c44))),
      );
    }
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [colors[1].withOpacity(0.55), colors[0], const Color(0xFF0C0C0E)],
          ),
        ),
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                  ),
                  Expanded(
                    child: Text(t('Editar perfil', 'Edit profile'),
                        style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
                  ),
                  TextButton(
                    onPressed: _shareProfile,
                    child: Text(t('Compartir', 'Share'), style: const TextStyle(color: Colors.white70)),
                  ),
                  TextButton(
                    onPressed: _saving ? null : _save,
                    child: Text(t('Guardar', 'Save'),
                        style: const TextStyle(color: Color(0xfffc3c44), fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Banner
              GestureDetector(
                onTap: () => _pickMedia(isAvatar: false),
                child: _applyEffect(Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: SizedBox(
                        height: 140,
                        width: double.infinity,
                        child: _newBanner != null
                            ? Image.file(_newBanner!, fit: BoxFit.cover)
                            : (_bannerUrl != null
                                ? Image.network(_bannerUrl!, fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => Container(color: colors[1].withOpacity(0.4)))
                                : Container(
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(colors: colors),
                                    ),
                                  )),
                      ),
                    ),
                    Positioned(
                      right: 10,
                      bottom: 10,
                      child: LiquidGlass(
                        blur: 12,
                        opacity: 0.2,
                        borderRadius: BorderRadius.circular(20),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          child: Text(t('Cambiar banner', 'Change banner'),
                              style: const TextStyle(color: Colors.white, fontSize: 12)),
                        ),
                      ),
                    ),
                  ],
                )),
              ),
              const SizedBox(height: 12),
              Center(
                child: GestureDetector(
                  onTap: () => _pickMedia(isAvatar: true),
                  child: Stack(
                    children: [
                      CircleAvatar(
                        radius: 48,
                        backgroundColor: Colors.white12,
                        backgroundImage: _newAvatar != null
                            ? FileImage(_newAvatar!)
                            : (_avatarUrl != null ? NetworkImage(_avatarUrl!) as ImageProvider : null),
                        child: (_newAvatar == null && _avatarUrl == null)
                            ? const Icon(Icons.person, size: 40, color: Colors.white38)
                            : null,
                      ),
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: const BoxDecoration(color: Color(0xfffc3c44), shape: BoxShape.circle),
                          child: const Icon(Icons.camera_alt, size: 16, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Center(
                child: Text(t('Toca para cambiar (JPG, PNG, GIF)', 'Tap to change (JPG, PNG, GIF)'),
                    style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 12)),
              ),
              const SizedBox(height: 20),
              Text(t('Tema del perfil', 'Profile theme'),
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),
              SizedBox(
                height: 44,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: _themes.entries.map((e) {
                    final selected = _theme == e.key;
                    return GestureDetector(
                      onTap: () => setState(() => _theme = e.key),
                      child: Container(
                        width: 44,
                        height: 44,
                        margin: const EdgeInsets.only(right: 10),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(colors: e.value),
                          border: Border.all(
                            color: selected ? Colors.white : Colors.transparent,
                            width: 2.5,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 18),
              Text(t('Efecto del perfil', 'Profile effect'),
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _effects.map((e) {
                  final selected = _effect == e;
                  final labels = {
                    'none': t('Ninguno', 'None'),
                    'glass': 'Glass',
                    'parallax': 'Parallax',
                    'glow': 'Glow',
                  };
                  return ChoiceChip(
                    label: Text(labels[e] ?? e),
                    selected: selected,
                    selectedColor: const Color(0xfffc3c44),
                    labelStyle: TextStyle(
                        color: selected ? Colors.white : Colors.white70,
                        fontWeight: FontWeight.w600),
                    backgroundColor: Colors.white10,
                    onSelected: (_) => setState(() => _effect = e),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              Text(t('Marco del avatar', 'Avatar frame'),
                  style: const TextStyle(
                      color: Colors.white70, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _frames.map((f) {
                  final selected = _frame == f;
                  final labels = {
                    'none': t('Ninguno', 'None'),
                    'ring': 'Ring',
                    'neon': 'Neon',
                    'pixel': 'Pixel',
                    'soft': 'Soft',
                  };
                  return ChoiceChip(
                    label: Text(labels[f] ?? f),
                    selected: selected,
                    onSelected: (_) => setState(() => _frame = f),
                    selectedColor: const Color(0xfffc3c44),
                    labelStyle: TextStyle(
                      color: selected ? Colors.white : Colors.white70,
                      fontWeight: FontWeight.w600,
                    ),
                    backgroundColor: const Color(0xFF1A1A1E),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              LiquidGlass(
                blur: 14,
                opacity: 0.08,
                borderRadius: BorderRadius.circular(14),
                child: TextField(
                  controller: _displayNameCtrl,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: t('Nombre / Nickname', 'Name / Nickname'),
                    labelStyle: TextStyle(color: Colors.white.withOpacity(0.45)),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.all(14),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              LiquidGlass(
                blur: 14,
                opacity: 0.08,
                borderRadius: BorderRadius.circular(14),
                child: TextField(
                  controller: _bioCtrl,
                  maxLines: 3,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Bio',
                    labelStyle: TextStyle(color: Colors.white.withOpacity(0.45)),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.all(14),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _profileField(_usernameCtrl, t('Nombre de usuario', 'Username'), hint: '@usuario'),
              const SizedBox(height: 12),
              _profileField(_pronounsCtrl, t('Pronombres (opcional)', 'Pronouns (optional)')),
              const SizedBox(height: 12),
              _profileField(_statusCtrl, t('Estado', 'Status'), hint: t('¿Qué estás haciendo?', 'What are you up to?')),
              const SizedBox(height: 12),
              _profileField(_badgesCtrl, t('Insignias', 'Badges'), hint: t('Separadas por comas', 'Comma separated')),
              const SizedBox(height: 12),
              Text(t('Mangas favoritos', 'Favorite manga'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: _favoriteMangas.map((m) {
                  final cover = (m['cover'] ?? '').toString();
                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        width: 88,
                        decoration: BoxDecoration(
                          color: Colors.white10,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            ClipRRect(
                              borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(12)),
                              child: AspectRatio(
                                aspectRatio: 0.7,
                                child: cover.startsWith('http')
                                    ? Image.network(
                                        cover,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) =>
                                            const ColoredBox(
                                          color: Colors.white12,
                                          child: Icon(Icons.menu_book_rounded,
                                              color: Colors.white38),
                                        ),
                                      )
                                    : const ColoredBox(
                                        color: Colors.white12,
                                        child: Icon(Icons.menu_book_rounded,
                                            color: Colors.white38),
                                      ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(6, 6, 6, 8),
                              child: Text(
                                m['title'] ?? '',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  height: 1.2,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Positioned(
                        top: -6,
                        right: -6,
                        child: Material(
                          color: const Color(0xFF2A2A2E),
                          shape: const CircleBorder(),
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: () => setState(() => _favoriteMangas
                                .removeWhere((item) => item['id'] == m['id'])),
                            child: const Padding(
                              padding: EdgeInsets.all(4),
                              child: Icon(Icons.close, size: 14, color: Colors.white70),
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _favoriteMangas.length >= 12 ? null : _showMangaPicker,
                icon: const Icon(Icons.search),
                label: Text(t('Buscar y agregar manga (${_favoriteMangas.length}/12)', 'Search and add manga (${_favoriteMangas.length}/12')),
              ),
              const SizedBox(height: 12),
              _profileField(_linkLabelCtrl, t('Etiqueta del enlace', 'Link label')),
              const SizedBox(height: 12),
              _profileField(_linkUrlCtrl, t('URL del enlace', 'Link URL'), keyboardType: TextInputType.url),
              const SizedBox(height: 8),
              LiquidGlass(blur: 12, opacity: 0.08, borderRadius: BorderRadius.circular(14), child: Column(children: [
                SwitchListTile(value: _isPublic, activeColor: const Color(0xfffc3c44), title: Text(t('Perfil público', 'Public profile'), style: const TextStyle(color: Colors.white)), onChanged: (v) => setState(() => _isPublic = v)),
                SwitchListTile(value: _showListening, activeColor: const Color(0xfffc3c44), title: Text(t('Mostrar actividad musical', 'Show listening activity'), style: const TextStyle(color: Colors.white)), onChanged: (v) => setState(() => _showListening = v)),
              ])),
              const SizedBox(height: 20),
              LiquidGlass(
                blur: 14,
                opacity: 0.08,
                borderRadius: BorderRadius.circular(14),
                child: ListTile(
                  leading: const Icon(Icons.playlist_play, color: Colors.white70),
                  title: Text(t('Mis playlists', 'My playlists'), style: const TextStyle(color: Colors.white)),
                  subtitle: Text(t('Crear y compartir', 'Create and share'),
                      style: TextStyle(color: Colors.white.withOpacity(0.45), fontSize: 12)),
                  trailing: const Icon(Icons.chevron_right, color: Colors.white38),
                  onTap: () => Navigator.pushNamed(context, '/playlists'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


class _MangaPickerDialog extends StatefulWidget {
  final Future<List<Map<String, String?>>> Function(String) search;
  final Set<String> selectedIds;
  final void Function(Map<String, String?>) onSelect;
  final int count;
  final VoidCallback onCountChanged;
  final String Function(String, String) strings;
  const _MangaPickerDialog({required this.search, required this.selectedIds, required this.onSelect, required this.count, required this.onCountChanged, required this.strings});
  @override
  State<_MangaPickerDialog> createState() => _MangaPickerDialogState();
}


class _MangaPickerDialogState extends State<_MangaPickerDialog> {
  final _query = TextEditingController();
  late Set<String> _selectedIds;
  late int _selectedCount;
  @override
  void initState() {
    super.initState();
    _selectedIds = Set<String>.from(widget.selectedIds);
    _selectedCount = widget.count;
  }
  List<Map<String, String?>> _results = [];
  bool _loading = false;
  String? _error;
  Future<void> _search() async {
    final query = _query.text.trim();
    if (query.length < 2) return;
    setState(() { _loading = true; _error = null; });
    try {
      final results = await widget.search(query);
      if (mounted) setState(() { _results = results; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _results = []; _loading = false; });
    }
  }
  @override
  void dispose() { _query.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => AlertDialog(
    backgroundColor: const Color(0xFF17171B),
    title: Text(widget.strings('Buscar mangas', 'Search manga'), style: const TextStyle(color: Colors.white)),
    content: SizedBox(width: 480, height: 420, child: Column(children: [
      Row(children: [Expanded(child: TextField(controller: _query, autofocus: true, style: const TextStyle(color: Colors.white), decoration: InputDecoration(hintText: widget.strings('Título de manga', 'Manga title'), hintStyle: const TextStyle(color: Colors.white54)), onSubmitted: (_) => _search())), IconButton(onPressed: _loading ? null : _search, icon: const Icon(Icons.search, color: Color(0xfffc3c44)))]),
      if (_loading) const Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator()),
      if (_error != null) Text(_error!, style: const TextStyle(color: Colors.redAccent)),
      Expanded(child: ListView.builder(itemCount: _results.length, itemBuilder: (_, index) {
        final item = _results[index];
        final selected = _selectedIds.contains(item['id']);
        return ListTile(dense: true, leading: item['cover'] == null ? const Icon(Icons.book_outlined, color: Colors.white54) : ClipRRect(borderRadius: BorderRadius.circular(5), child: Image.network(item['cover']!, width: 40, height: 52, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.book_outlined, color: Colors.white54))), title: Text(item['title'] ?? '', style: const TextStyle(color: Colors.white), maxLines: 2, overflow: TextOverflow.ellipsis), trailing: Icon(selected ? Icons.check_circle : Icons.add_circle_outline, color: selected ? Colors.greenAccent : Colors.white70), onTap: selected || _selectedCount >= 12 ? null : () { widget.onSelect(item); widget.onCountChanged(); setState(() { _selectedIds.add(item['id'] ?? ''); _selectedCount++; }); });
      })),
    ])),
    actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(widget.strings('Cerrar', 'Done')))],
  );
}
