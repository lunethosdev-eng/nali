import 'package:flutter/material.dart';
import 'package:nali/services/provider_service.dart';
import 'package:nali/services/settings_service.dart';
import 'package:nali/services/spotify_service.dart';
import 'package:nali/widgets/liquid_glass.dart';
import 'package:nali/screens/custom_providers_screen.dart';
import 'package:nali/services/discord_connector_service.dart';

/// Phase 2 – Complete Settings → Proveedores section.
///
/// Rules enforced:
/// - Supabase is always on (primary backend). Switch is disabled.
/// - YouTube Music starts OFF. Only the user can turn it on.
/// - Spotify shows connection status from SpotifyService + enable toggle.
/// - SoundCloud no-key mode accepts public permalinks through official oEmbed; global search can be supplied by a custom provider.
class SettingsProvidersSection extends StatelessWidget {
  const SettingsProvidersSection({super.key});

  String t(String es, String en) =>
      SettingsService.instance.locale == 'en' ? en : es;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        ProviderService.instance,
        // SpotifyService is not a ChangeNotifier in all versions,
        // so we rebuild when ProviderService changes (toggle).
      ]),
      builder: (context, _) {
        final ps = ProviderService.instance;
        final spotify = SpotifyService.instance;
        final locale = SettingsService.instance.locale;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle(t('Proveedores musicales', 'Music providers')),
            const SizedBox(height: 8),
            Text(
              t(
                'Elige qué fuentes de música puede usar Nali. Supabase es siempre la fuente principal.',
                'Choose which music sources Nali can use. Supabase is always the primary source.',
              ),
              style: TextStyle(color: Colors.white.withOpacity(0.55), fontSize: 13),
            ),
            const SizedBox(height: 18),

            // ── SUPABASE (always on) ───────────────────────────────
            _providerCard(
              icon: Icons.cloud_done_rounded,
              iconColor: const Color(0xff6ed6b1),
              title: 'Supabase',
              subtitle: ps.statusText('supabase', locale: locale),
              value: true,
              onChanged: null, // cannot disable
              trailingLabel: t('Principal', 'Primary'),
            ),
            const SizedBox(height: 10),

            // ── YOUTUBE MUSIC (OFF by default) ─────────────────────
            _providerCard(
              icon: Icons.play_circle_outline_rounded,
              iconColor: const Color(0xffff4444),
              title: 'YouTube Music',
              subtitle: ps.statusText('youtube_music', locale: locale),
              value: ps.youtubeMusicEnabled,
              onChanged: (v) => ps.setYoutubeMusicEnabled(v),
            ),
            const SizedBox(height: 10),

            // ── SPOTIFY ────────────────────────────────────────────
            _providerCard(
              icon: Icons.library_music_rounded,
              iconColor: const Color(0xFF1DB954),
              title: 'Spotify',
              subtitle: ps.statusText('spotify', locale: locale),
              value: ps.spotifyEnabled,
              onChanged: (v) => ps.setSpotifyEnabled(v),
              extra: spotify.isLinked
                  ? Padding(
                      padding: const EdgeInsets.only(left: 16, right: 16, bottom: 12),
                      child: Row(
                        children: [
                          if (spotify.profileImage != null &&
                              spotify.profileImage!.isNotEmpty)
                            CircleAvatar(
                              radius: 12,
                              backgroundImage: NetworkImage(spotify.profileImage!),
                            )
                          else
                            const Icon(Icons.person, size: 18, color: Colors.white54),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              spotify.displayName ?? t('Cuenta conectada', 'Linked account'),
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.7),
                                fontSize: 12,
                              ),
                            ),
                          ),
                          Text(
                            t('Conectado', 'Connected'),
                            style: const TextStyle(
                              color: Color(0xFF1DB954),
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    )
                  : null,
            ),
            const SizedBox(height: 10),

            _providerCard(
              icon: Icons.library_music_rounded,
              iconColor: Colors.white,
              title: 'Apple Music / iTunes',
              subtitle: t('Búsqueda pública · avances oficiales', 'Public search · official previews'),
              value: ps.appleMusicEnabled,
              onChanged: (v) => ps.setAppleMusicEnabled(v),
            ),
            const SizedBox(height: 10),
            _providerCard(
              icon: Icons.graphic_eq_rounded,
              iconColor: const Color(0xffef5b24),
              title: 'Deezer',
              subtitle: t('Catálogo público · avances de 30 segundos', 'Public catalog · 30-second previews'),
              value: ps.deezerEnabled,
              onChanged: (v) => ps.setDeezerEnabled(v),
            ),

            // ── SOUNDCLOUD ────────────────────────────────────────
            _providerCard(
              icon: Icons.cloud_queue_rounded,
              iconColor: const Color(0xffff6a35),
              title: 'SoundCloud',
              subtitle: ps.statusText('soundcloud', locale: locale),
              value: ps.soundCloudEnabled,
              onChanged: (v) => ps.setSoundCloudEnabled(v),
            ),
            const SizedBox(height: 8),
            Text(
              t('Los enlaces públicos se abren con el reproductor oficial. La búsqueda global de SoundCloud requiere un Client ID oficial; puedes añadirlo mediante un proveedor personalizado.',
                'Public links open in the official player. Global SoundCloud search requires an official Client ID; add it through a custom provider.'),
              style: TextStyle(color: Colors.white.withOpacity(.48), fontSize: 12, height: 1.4),
            ),
            const SizedBox(height: 18),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CustomProvidersScreen())),
              icon: const Icon(Icons.extension_rounded),
              label: Text(t('Proveedores personalizados', 'Custom providers')),
              style: OutlinedButton.styleFrom(foregroundColor: Colors.white, minimumSize: const Size.fromHeight(48)),
            ),
            const SizedBox(height: 24),
            _sectionTitle(t('Conectores', 'Connectors')),
            const SizedBox(height: 10),
            AnimatedBuilder(
              animation: DiscordConnectorService.instance,
              builder: (context, _) {
                final discord = DiscordConnectorService.instance;
                return _providerCard(
                  icon: Icons.chat_bubble_outline_rounded,
                  iconColor: const Color(0xff5865F2),
                  title: 'Discord · POLIC',
                  subtitle: t('Vincula tu cuenta, personaliza tu tarjeta y sincroniza lo que escuchas.', 'Link your account, customize your card and sync what you listen to.'),
                  value: discord.syncEnabled,
                  onChanged: (v) => discord.setSyncEnabled(v),
                  extra: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: Wrap(spacing: 8, runSpacing: 8, children: [
                      OutlinedButton.icon(
                        onPressed: discord.busy ? null : () async {
                          try { await discord.connectDiscord(); }
                          catch (e) { if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString()))); }
                        },
                        icon: const Icon(Icons.link_rounded, size: 16),
                        label: Text(t('Conectar Discord', 'Connect Discord')),
                      ),
                      OutlinedButton.icon(
                        onPressed: () async {
                          try { await discord.openCustomize(); }
                          catch (e) { if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString()))); }
                        },
                        icon: const Icon(Icons.palette_outlined, size: 16),
                        label: Text(t('Personalizar tarjeta', 'Customize card')),
                      ),
                      TextButton(
                        onPressed: () async {
                          try {
                            final themes = await discord.availableThemes();
                            if (!context.mounted) return;
                            showDialog(context: context, builder: (_) => AlertDialog(
                              backgroundColor: const Color(0xff202026),
                              title: Text(t('Temas disponibles', 'Available themes'), style: const TextStyle(color: Colors.white)),
                              content: SizedBox(width: 340, child: ListView(shrinkWrap: true, children: themes.map((theme) => ListTile(
                                title: Text((theme['name'] ?? theme['label'] ?? theme['id'] ?? 'Tema').toString(), style: const TextStyle(color: Colors.white)),
                                subtitle: Text((theme['description'] ?? '').toString(), style: const TextStyle(color: Colors.white54)),
                              )).toList())),
                            ));
                          } catch (e) { if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString()))); }
                        },
                        child: Text(t('Ver temas', 'Browse themes')),
                      ),
                    ]),
                  ),
                );
              },
            ),

            const SizedBox(height: 22),
            _infoBox(
              t(
                'YouTube Music y SoundCloud solo se consultan cuando están activados. '
                'Supabase sigue siendo la fuente principal. Las descargas MP3 de Nali '
                'solo están disponibles para canciones alojadas en Supabase.',
                'YouTube Music and SoundCloud are queried only when enabled. '
                'Supabase remains the primary source. Nali MP3 downloads are '
                'available only for songs hosted in Supabase.',
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _providerCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool>? onChanged,
    String? trailingLabel,
    Widget? extra,
    bool disabled = false,
  }) {
    return LiquidGlass(
      borderRadius: BorderRadius.circular(14),
      child: Column(
        children: [
          SwitchListTile(
            secondary: Icon(icon, color: disabled ? Colors.white24 : iconColor),
            title: Text(
              title,
              style: TextStyle(
                color: disabled ? Colors.white38 : Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: Text(
              subtitle,
              style: TextStyle(
                color: Colors.white.withOpacity(disabled ? 0.3 : 0.5),
                fontSize: 12,
              ),
            ),
            value: value,
            activeColor: iconColor,
            onChanged: disabled ? null : onChanged,
          ),
          if (trailingLabel != null)
            Padding(
              padding: const EdgeInsets.only(left: 16, right: 16, bottom: 10),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: iconColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    trailingLabel,
                    style: TextStyle(
                      color: iconColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          if (extra != null) extra,
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Text(
      text,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 15,
        fontWeight: FontWeight.w700,
      ),
    );
  }

  Widget _infoBox(String message) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded, color: Colors.white54, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: Colors.white60, fontSize: 12, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}
