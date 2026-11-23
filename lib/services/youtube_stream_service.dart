import 'package:flutter/foundation.dart';
import 'package:nali/services/supabase_service.dart';

class YoutubeResolvedStream {
  const YoutubeResolvedStream({
    required this.url,
    this.durationSeconds,
    this.mimeType,
    this.bitrate,
  });

  final String url;
  final int? durationSeconds;
  final String? mimeType;
  final int? bitrate;
}

/// Resolves a YouTube Music video to a short-lived InnerTube audio URL.
/// The URL is requested only when playback starts; search remains metadata-only.
class YoutubeStreamService {
  YoutubeStreamService._();
  static final YoutubeStreamService instance = YoutubeStreamService._();

  Future<String> resolve(String videoId) async =>
      (await resolveDetailed(videoId)).url;

  Future<YoutubeResolvedStream> resolveDetailed(String videoId) async {
    final id = videoId.trim();
    if (!RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(id)) {
      throw ArgumentError('Invalid YouTube video ID');
    }
    final response = await SupabaseService.kokoro.functions.invoke(
      'youtube-music-stream',
      body: {'videoId': id},
    ).timeout(const Duration(seconds: 45));
    final payload = response.data;
    final url = payload is Map ? (payload['audio_url'] ?? '').toString() : '';
    if (!url.startsWith('https://') || !url.contains('googlevideo.com')) {
      final detail = payload is Map ? payload['detail']?.toString() : null;
      throw StateError(detail?.isNotEmpty == true
          ? 'InnerTube stream unavailable: $detail'
          : 'InnerTube did not return an audio stream');
    }
    final rawDuration = payload is Map ? payload['duration_seconds'] : null;
    final duration = rawDuration is num
        ? rawDuration.round()
        : int.tryParse(rawDuration?.toString() ?? '');
    final rawBitrate = payload is Map ? payload['bitrate'] : null;
    final bitrate = rawBitrate is num
        ? rawBitrate.round()
        : int.tryParse(rawBitrate?.toString() ?? '');
    final mime = payload is Map ? payload['mime_type']?.toString() : null;
    debugPrint('YouTube Music InnerTube stream resolved for $id');
    return YoutubeResolvedStream(
      url: url,
      durationSeconds: duration != null && duration > 0 ? duration : null,
      mimeType: mime?.isNotEmpty == true ? mime : null,
      bitrate: bitrate,
    );
  }
}
