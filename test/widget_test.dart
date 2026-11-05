import 'package:flutter_test/flutter_test.dart';
import 'package:kairos_plus/core/json.dart';
import 'package:kairos_plus/data/models.dart';
import 'package:kairos_plus/data/sources/m3u_source.dart';
import 'package:kairos_plus/data/sources/xtream_source.dart';
import 'package:kairos_plus/panel/panel.dart';

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

    test('indirizzo della guida breve per il lettore', () {
      const account = Account(type: AccountType.xtream, server: 'http://srv:80', username: 'u', password: 'p');
      const channel = MediaItem(kind: MediaKind.live, id: '42', name: 'Canale', categoryId: '1');
      final url = XtreamSource(account).epgUrlFor(channel);
      expect(url, contains('action=get_short_epg'));
      expect(url, contains('stream_id=42'));
    });
  });

  test('decodifica i testi base64 della guida TV', () {
    expect(decodeBase64Text('Q2lhbw=='), 'Ciao');
    expect(decodeBase64Text('Q2lhbw'), 'Ciao');
  });

  test('il catalogo si salva e si rilegge identico', () {
    final catalog = Catalog.build(
      liveCategories: const [Category(id: '1', name: 'Italia')],
      movieCategories: const [Category(id: '2', name: 'Azione')],
      seriesCategories: const [],
      live: const [
        MediaItem(kind: MediaKind.live, id: '10', name: 'Rai 1', categoryId: '1', number: 1, url: 'http://a/10.ts'),
      ],
      movies: const [
        MediaItem(kind: MediaKind.movie, id: '20', name: 'Sintel', categoryId: '2', year: '2010', added: 5),
        MediaItem(kind: MediaKind.movie, id: '21', name: 'Tears of Steel', categoryId: '2', added: 9),
      ],
      series: const [],
      fetchedAt: 1,
    );
    final copy = Catalog.fromJson(catalog.toJson());
    expect(copy.movies.length, 2);
    expect(copy.live.single.url, 'http://a/10.ts');
    expect(copy.live.single.number, 1);
    expect(copy.search(MediaKind.movie, 'sintel').single.name, 'Sintel');
    expect(copy.recentMovies.first.name, 'Tears of Steel');
  });

  group('Pannello Kairos', () {
    test('il codice della TV ha il formato delle altre app Kairos', () {
      for (var i = 0; i < 50; i++) {
        final id = PanelIdentity.generate();
        expect(id.isValid, isTrue, reason: '${id.code} / ${id.secret}');
      }
    });

    test('legge lo stato attivo con le playlist', () {
      final s = PanelState.parse({
        'status': 'active',
        'name': 'Mario',
        'expires': '2027-01-31',
        'settings': {'serverUrl': 'https://nuovo.example', 'price': '22 €'},
        'playlists': [
          {'id': 'a', 'name': 'Principale', 'type': 'xtream', 'host': 'srv.example:8080', 'username': 'u', 'password': 'p'},
          {'id': 'b', 'name': 'Lista', 'type': 'm3u', 'url': 'http://x.example/get.php?username=k&password=z&type=m3u_plus'},
          {'id': 'c', 'name': 'Altra', 'type': 'm3u', 'url': 'liste.example/tv.m3u'},
        ],
        'messages': [
          {'id': 7, 'title': 'Avviso', 'body': 'Ciao'},
        ],
        'account': {'primary': true, 'maxConn': 2, 'conns': [{}, {}], 'maxStreams': 1, 'plMode': 'split', 'plDefault': 'b'},
        'perms': {'link': false},
      });
      expect(s.active, isTrue);
      expect(s.expiresLabel, '31/01/2027');
      expect(s.setting('serverUrl'), 'https://nuovo.example');
      expect(s.perm('link'), isFalse);
      expect(s.perm('plSwitch'), isTrue);
      expect(s.offPerms(), 'link');
      expect(s.messages.single.id, '7');
      expect(s.account?.conns, 2);
      expect(s.account?.plMode, 'split');

      final xtream = s.playlists[0].toAccount();
      expect(xtream?.type, AccountType.xtream);
      expect(xtream?.server, 'http://srv.example:8080');

      // un link M3U di un server Xtream diventa un account Xtream (categorie e guida TV)
      final fromLink = s.playlists[1].toAccount();
      expect(fromLink?.type, AccountType.xtream);
      expect(fromLink?.username, 'k');

      final m3u = s.playlists[2].toAccount();
      expect(m3u?.type, AccountType.m3u);
      expect(m3u?.m3uUrl, 'http://liste.example/tv.m3u');
    });

    test('la firma della playlist non cambia se cambia solo il DNS', () {
      const a = PanelPlaylist(id: '1', name: 'X', type: 'xtream', host: 'vecchio.example', username: 'u', password: 'p');
      const b = PanelPlaylist(id: '1', name: 'X', type: 'xtream', host: 'nuovo.example', username: 'u', password: 'p');
      expect(a.signature, b.signature);
    });
  });

  test('elemento del lettore con i dati del canale', () {
    const channel = MediaItem(kind: MediaKind.live, id: '5', name: 'Rai 2', categoryId: '1', number: 2);
    const item = PlaybackItem(
      key: 'live:5',
      title: 'Rai 2',
      url: 'http://s/live/u/p/5.ts',
      isLive: true,
      kind: MediaKind.live,
      channel: channel,
      altUrls: ['http://s/live/u/p/5.m3u8'],
      epgUrl: 'http://s/player_api.php?action=get_short_epg&stream_id=5',
    );
    final json = item.toPlayerJson();
    expect(json['num'], 2);
    expect(json['live'], isTrue);
    expect(json['kind'], 'live');
    expect(json['alt'], ['http://s/live/u/p/5.m3u8']);
    expect(PlaybackItem.fromJson(item.toJson())?.kind, MediaKind.live);
  });
}
