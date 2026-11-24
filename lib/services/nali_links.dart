import 'package:share_plus/share_plus.dart';

/// Canonical public URLs for Nali content. The downloads/landing page is kept
/// separate and must never be used as the target of a content share.
class NaliLinks {
  NaliLinks._();

  static const String appBaseUrl =
      'https://lunethosdev-eng.github.io/nali/';
  static const String downloadsUrl =
      'https://lunethosdev-eng.github.io/okipokkeX/index.html#experience';

  static Uri content(String kind, String id,
      {Map<String, String>? queryParameters}) {
    final safeKind = kind.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '');
    final safeId = id.trim();
    if (safeKind.isEmpty || safeId.isEmpty) {
      throw ArgumentError('A content type and real content ID are required.');
    }
    final route = '/$safeKind/${Uri.encodeComponent(safeId)}';
    final query = queryParameters == null || queryParameters.isEmpty
        ? ''
        : Uri(queryParameters: queryParameters).query;
    // Parse the completed URL so already-escaped path segments are not
    // escaped a second time by Uri.replace(fragment: ...).
    return Uri.parse('$appBaseUrl#$route${query.isEmpty ? '' : '?$query'}');
  }

  static Uri song(String id) => content('song', id);
  static Uri playlist(String id) => content('playlist', id);
  static Uri profile(String id) => content('profile', id);
  static Uri artist(String id) => content('artist', id);
  static Uri album(String id) => content('album', id);
  static Uri lyrics(String songId, {int? start, int? end}) => content(
        'lyrics',
        songId,
        queryParameters: {
          if (start != null) 'start': '$start',
          if (end != null) 'end': '$end',
        },
      );

  static String message(String title, Uri link, {String? description}) {
    final prefix = description == null || description.trim().isEmpty
        ? title
        : '${description.trim()}\n$title';
    return '$prefix\n$link';
  }

  /// share_plus 10.x API (Share.share). SharePlus/ShareParams is 12.x-only
  /// and broke Windows CI with the newer C++ plugin headers.
  static Future<void> share(String title, Uri link,
      {String? description}) async {
    await Share.share(
      message(title, link, description: description),
      subject: title,
    );
  }
}

class NaliSharedLink {
  const NaliSharedLink({
    required this.kind,
    required this.id,
    this.start,
    this.end,
  });

  final String kind;
  final String id;
  final int? start;
  final int? end;

  static NaliSharedLink? parse(Uri incoming) {
    Uri route = incoming;

    // GitHub Pages uses a project subdirectory and Flutter hash routes.
    if (incoming.host == 'lunethosdev-eng.github.io' &&
        incoming.path.startsWith('/nali/') &&
        incoming.fragment.startsWith('/')) {
      route = Uri.parse(incoming.fragment);
    } else if (incoming.scheme == 'pokke' || incoming.scheme == 'nali') {
      final segments = incoming.pathSegments;
      final rawKind = incoming.host == 'share'
          ? segments.isNotEmpty
              ? segments.first
              : ''
          : incoming.host;
      final kind = rawKind == 'user'
          ? 'profile'
          : rawKind == 'track'
              ? 'song'
              : rawKind;
      final id = incoming.host == 'share'
          ? segments.length > 1
              ? segments[1]
              : ''
          : segments.isNotEmpty
              ? segments.first
              : '';
      if (kind.isEmpty || id.isEmpty) return null;
      return NaliSharedLink(kind: kind, id: id);
    }

    final segments =
        route.pathSegments.where((part) => part.isNotEmpty).toList();
    if (segments.length < 2) return null;
    final kind = segments[0].toLowerCase();
    const supported = {
      'song',
      'playlist',
      'profile',
      'artist',
      'album',
      'lyrics',
    };
    if (!supported.contains(kind)) return null;
    return NaliSharedLink(
      kind: kind,
      id: segments[1],
      start: int.tryParse(route.queryParameters['start'] ?? ''),
      end: int.tryParse(route.queryParameters['end'] ?? ''),
    );
  }
}
