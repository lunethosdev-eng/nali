import 'package:flutter/foundation.dart';
import 'package:nali/services/supabase_service.dart';

/// Resolves a YouTube Music video to a short-lived InnerTube audio URL.
/// The URL is requested only when playback starts; search remains metadata-only.
class YoutubeStreamService {
  YoutubeStreamService._();
  static final YoutubeStreamService instance = YoutubeStreamService._();

  Future<String> resolve(String videoId) async {
    final id = videoId.trim();
    if (!RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(id)) {
      throw ArgumentError('Invalid YouTube video ID');
    }
    final response = await SupabaseService.kokoro.functions.invoke(
      'youtube-music-stream',
      body: {'videoId': id},
    ).timeout(const Duration(seconds: 30));
    final payload = response.data;
    final url = payload is Map ? (payload['audio_url'] ?? '').toString() : '';
    if (!url.startsWith('https://') || !url.contains('googlevideo.com')) {
      final detail = payload is Map ? payload['detail']?.toString() : null;
      throw StateError(detail?.isNotEmpty == true
          ? 'InnerTube stream unavailable: $detail'
          : 'InnerTube did not return an audio stream');
    }
    debugPrint('YouTube Music InnerTube stream resolved for $id');
    return url;
  }
}
