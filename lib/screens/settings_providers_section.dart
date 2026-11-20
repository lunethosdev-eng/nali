import 'package:flutter/material.dart';
import 'package:nali/services/provider_service.dart';
import 'package:nali/services/settings_service.dart';
import 'package:nali/widgets/liquid_glass.dart';

/// Phase 1 – Settings → Proveedores section.
///
/// Rules:
/// - Supabase is always on (primary backend). Cannot be disabled.
/// - YouTube Music starts OFF and only activates when the user turns the switch on.
/// - Spotify toggle is prepared (real connection handled in later phases).
class SettingsProvidersSection extends StatelessWidget {
  const SettingsProvidersSection({super.key});

  String t(String es, String en) =>
      SettingsService.instance.locale == 'en' ? en : es;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: ProviderService.instance,
      builder: (context, _) {
        final ps = ProviderService.instance;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle(t('Proveedores musicales', 'Music providers')),
            const SizedBox(height: 8),
            Text(
              t(
                'Controla qué fuentes de música puede usar Nali. Supabase es siempre la fuente principal.',
                'Control which music sources Nali can use. Supabase is always the primary source.',
              ),
              style: TextStyle(color: Colors.white.withOpacity(0.55), fontSize: 13),
            ),
            const SizedBox(height: 16),

            // ── Supabase (always on) ───────────────────────────────
            LiquidGlass(
              borderRadius: BorderRadius.circular(14),
              child: ListTile(
                leading: const Icon(Icons.cloud_done_rounded, color: Color(0xff6ed6b1)),
                title: Text(
                  'Supabase',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  t(
                    'Servidor principal de Nali · siempre activo',
                    'Nali primary server · always active',
                  ),
                  style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12),
                ),
                trailing: Switch(
                  value: true,
                  activeColor: const Color(0xff6ed6b1),
                  onChanged: null, // Cannot be disabled
                ),
              ),
            ),
            const SizedBox(height: 10),

            // ── YouTube Music (OFF by default) ─────────────────────
            LiquidGlass(
              borderRadius: BorderRadius.circular(14),
              child: SwitchListTile(
                secondary: const Icon(Icons.play_circle_outline_rounded, color: Color(0xffff4444)),
                title: const Text(
                  'YouTube Music',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  ps.youtubeMusicEnabled
                      ? t('Activo · resultados incluidos en búsqueda', 'Active · results included in search')
                      : t('Desactivado · no se consulta su catálogo', 'Disabled · catalog is not queried'),
                  style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12),
                ),
                value: ps.youtubeMusicEnabled,
                activeColor: const Color(0xffff4444),
                onChanged: (v) => ps.setYoutubeMusicEnabled(v),
              ),
            ),
            const SizedBox(height: 10),

            // ── Spotify (prepared) ─────────────────────────────────
            LiquidGlass(
              borderRadius: BorderRadius.circular(14),
              child: SwitchListTile(
                secondary: const Icon(Icons.library_music_rounded, color: Color(0xFF1DB954)),
                title: const Text(
                  'Spotify',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  t(
                    'Integración preparada · conexión real en fases posteriores',
                    'Prepared · real connection in later phases',
                  ),
                  style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12),
                ),
                value: ps.spotifyEnabled,
                activeColor: const Color(0xFF1DB954),
                onChanged: (v) => ps.setSpotifyEnabled(v),
              ),
            ),
            const SizedBox(height: 10),

            // ── SoundCloud (future) ────────────────────────────────
            LiquidGlass(
              borderRadius: BorderRadius.circular(14),
              child: ListTile(
                leading: Icon(Icons.cloud_queue_rounded, color: Colors.white.withOpacity(0.35)),
                title: Text(
                  'SoundCloud',
                  style: TextStyle(color: Colors.white.withOpacity(0.45), fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  t('Próximamente', 'Coming soon'),
                  style: TextStyle(color: Colors.white.withOpacity(0.35), fontSize: 12),
                ),
                trailing: Switch(
                  value: false,
                  onChanged: null,
                ),
              ),
            ),

            const SizedBox(height: 20),
            _infoBox(
              t(
                'YouTube Music solo se utiliza cuando está activado. Supabase sigue siendo la fuente predeterminada en todo momento.',
                'YouTube Music is only used when enabled. Supabase remains the default source at all times.',
              ),
            ),
          ],
        );
      },
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
