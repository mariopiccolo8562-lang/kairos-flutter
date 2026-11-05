import 'package:flutter_test/flutter_test.dart';
import 'package:streaming_tv/core/json.dart';
import 'package:streaming_tv/data/models.dart';
import 'package:streaming_tv/data/sources/demo_source.dart';
import 'package:streaming_tv/data/sources/m3u_source.dart';
import 'package:streaming_tv/data/sources/xtream_source.dart';

void main() {
  group('Lista M3U', () {
    test('divide canali e film per categoria', () {
      const text = '#EXTM3U\n'
          '#EXTINF:-1 tvg-id="rai1" tvg-logo="http://x/l.png" group-title="Italia",Rai 1\n'
          'http://srv/live/u/p/1.ts\n'
          '#EXTINF:-1 group-title="Film",Titolo, con virgola (2021)\n'
          'http://srv/movie/u/p/10.mkv\n';
      final catalog = parseM3uCatalog(text);
      expect(catalog.live.single.name, 'Rai 1');
      expect(catalog.live.single.image, 'http://x/l.png');
      expect(catalog.liveCategories.single.name, 'Italia');
      expect(catalog.movies.single.name, 'Titolo, con virgola (2021)');
      expect(catalog.movies.single.year, '2021');
    });

    test('lo stesso indirizzo produce sempre lo stesso identificativo', () {
      const text = '#EXTM3U\n#EXTINF:-1,Uno\nhttp://a/1.ts\n';
      expect(parseM3uCatalog(text).live.single.id, parseM3uCatalog(text).live.single.id);
    });
  });

  group('Xtream', () {
    test('ripulisce l\'indirizzo del server', () {
      expect(XtreamSource.normalizeServer('esempio.com:8080/'), 'http://esempio.com:8080');
      expect(XtreamSource.normalizeServer('https://esempio.com:8443/player_api.php'), 'https://esempio.com:8443');
    });

    test('ricava l\'account dal link M3U di un server Xtream', () {
      final account = XtreamSource.accountFromM3uUrl(
        'http://esempio.com:8080/get.php?username=mario&password=segreta&type=m3u_plus',
      );
      expect(account?.type, AccountType.xtream);
      expect(account?.server, 'http://esempio.com:8080');
      expect(account?.username, 'mario');
      expect(account?.password, 'segreta');
    });
  });

  test('decodifica i testi base64 della guida TV', () {
    expect(decodeBase64Text('Q2lhbw=='), 'Ciao');
    expect(decodeBase64Text('Q2lhbw'), 'Ciao');
  });

  test('il catalogo si salva e si rilegge identico', () {
    final catalog = buildDemoCatalog();
    final copy = Catalog.fromJson(catalog.toJson());
    expect(copy.movies.length, catalog.movies.length);
    expect(copy.series.length, catalog.series.length);
    expect(copy.live.first.url, catalog.live.first.url);
    expect(copy.search(MediaKind.movie, 'sintel').single.name, 'Sintel');
  });
}
