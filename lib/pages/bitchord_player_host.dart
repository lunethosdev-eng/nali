import 'package:flutter/material.dart';
import 'package:nali/pages/music_player.dart';

/// Compatibility alias retained for older routes.
///
/// The original BitChord PlayerHost is Kotlin/Compose and is launched through
/// BitChordPlayerActivity on Android. A Flutter Web build cannot instantiate
/// that Android Activity, so this alias deliberately falls back to Nali's
/// regular player instead of drawing a separate BitChord-style imitation.
@Deprecated('Use MusicPlayer on Flutter targets; Android opens BitChordPlayerActivity natively.')
class BitChordPlayerHost extends StatelessWidget {
  const BitChordPlayerHost({super.key});

  @override
  Widget build(BuildContext context) => MusicPlayer();
}
