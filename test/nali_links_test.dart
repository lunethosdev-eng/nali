import 'package:flutter_test/flutter_test.dart';
import 'package:nali/services/nali_links.dart';

void main() {
  test('content URLs use the official Nali Pages base and hash route', () {
    final link = NaliLinks.song('song-123');
    expect(link.origin, 'https://lunethosdev-eng.github.io');
    expect(link.path, '/nali/');
    expect(link.fragment, '/song/song-123');
  });

  test('lyrics links preserve the requested time range', () {
    final link = NaliLinks.lyrics('song-123', start: 12, end: 18);
    final parsed = NaliSharedLink.parse(link);
    expect(parsed?.kind, 'lyrics');
    expect(parsed?.id, 'song-123');
    expect(parsed?.start, 12);
    expect(parsed?.end, 18);
  });

  test('incoming GitHub Pages links resolve hash routes', () {
    final parsed = NaliSharedLink.parse(Uri.parse(
      'https://lunethosdev-eng.github.io/nali/#/playlist/list-456',
    ));
    expect(parsed?.kind, 'playlist');
    expect(parsed?.id, 'list-456');
  });
}
