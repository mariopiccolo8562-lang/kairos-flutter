import 'package:flutter_test/flutter_test.dart';
import 'package:kairos_plus/data/models.dart';

/// Risposta del pannello per i trailer (/api/player/trailer): video di YouTube, file diretto oppure niente.
void main() {
  test('video di YouTube', () {
    final t = TrailerRef.fromPanel(<String, dynamic>{'url': '', 'yt': 'gnOCZhluoow', 'title': 'Interstellar', 'src': 'tmdb'})!;
    expect(t.yt, 'gnOCZhluoow');
    expect(t.url, '');
    expect(t.title, 'Interstellar');
  });

  test('file diretto solo https', () {
    final t = TrailerRef.fromPanel(<String, dynamic>{'url': 'https://video.example/a.m4v', 'yt': ''})!;
    expect(t.url, 'https://video.example/a.m4v');
    expect(TrailerRef.fromPanel(<String, dynamic>{'url': 'http://video.example/a.m4v', 'yt': ''}), isNull);
  });

  test('niente trovato', () {
    expect(TrailerRef.fromPanel(<String, dynamic>{'url': '', 'yt': ''}), isNull);
    expect(TrailerRef.fromPanel(<String, dynamic>{}), isNull);
  });
}
