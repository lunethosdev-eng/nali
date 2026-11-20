/// Simple identifier for music providers used across Nali.
enum MusicProviderId {
  supabase,
  youtubeMusic,
  spotify,
  soundCloud,
}

extension MusicProviderIdX on MusicProviderId {
  String get id {
    switch (this) {
      case MusicProviderId.supabase:
        return 'supabase';
      case MusicProviderId.youtubeMusic:
        return 'youtube_music';
      case MusicProviderId.spotify:
        return 'spotify';
      case MusicProviderId.soundCloud:
        return 'soundcloud';
    }
  }

  String displayName({String locale = 'es'}) {
    final en = locale == 'en';
    switch (this) {
      case MusicProviderId.supabase:
        return 'Supabase';
      case MusicProviderId.youtubeMusic:
        return 'YouTube Music';
      case MusicProviderId.spotify:
        return 'Spotify';
      case MusicProviderId.soundCloud:
        return 'SoundCloud';
    }
  }
}
