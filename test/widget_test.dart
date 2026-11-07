import 'package:flutter_test/flutter_test.dart';
import 'package:kairos_plus/app/perf.dart';
import 'package:kairos_plus/core/json.dart';
import 'package:kairos_plus/data/home_rules.dart';
import 'package:kairos_plus/data/models.dart';
import 'package:kairos_plus/data/sources/m3u_source.dart';
import 'package:kairos_plus/data/sources/xtream_source.dart';
import 'package:kairos_plus/panel/panel.dart';
import 'package:kairos_plus/ui/widgets/net_image.dart';

void main() {
  group('Immagini', () {
    test('TMDB: misura più piccola adatta alla vista, il resto resta com\'è', () {
      const base = 'https://image.tmdb.org/t/p/';
      expect(tmdbSized('${base}original/a.jpg', 342), '${base}w342/a.jpg');
      expect(tmdbSized('${base}w600_and_h900_bestv2/a.jpg', 342), '${base}w342/a.jpg');
      expect(tmdbSized('${base}w1280/b.jpg', 780), '${base}w780/b.jpg');
      expect(tmdbSized('http://image.tmdb.org/t/p/w500/c.png', 185), 'http://image.tmdb.org/t/p/w185/c.png');
      // già piccole, tagli non 2:3, misure sconosciute e altri server: invariati
      expect(tmdbSized('${base}w185/a.jpg', 342), '${base}w185/a.jpg');
      expect(tmdbSized('${base}w1920_and_h800_multi_faces/b.jpg', 780), '${base}w1920_and_h800_multi_faces/b.jpg');
      expect(tmdbSized('${base}h632/p.jpg', 185), '${base}h632/p.jpg');
      expect(tmdbSized('http://server.example/w500/a.jpg', 185), 'http://server.example/w500/a.jpg');
    });

    test('TMDB: locandine w342 (w185 sui dispositivi deboli), sfondi w780', () {
      final before = Perf.weak;
      try {
        Perf.weak = false;
        expect([tmdbWidthFor(88), tmdbWidthFor(224), tmdbWidthFor(1120)], [185, 342, 780]);
        Perf.weak = true;
        expect([tmdbWidthFor(88), tmdbWidthFor(224), tmdbWidthFor(1120)], [185, 185, 780]);
      } finally {
        Perf.weak = before;
      }
    });
  });

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

  test('la copia per la Home ha le stesse file della Home ed è parziale', () {
    final movies = [
      for (var i = 0; i < 300; i++)
        MediaItem(kind: MediaKind.movie, id: 'm$i', name: 'Film $i', categoryId: 'c${i % 6}', added: i),
    ];
    final catalog = Catalog.build(
      liveCategories: const [Category(id: 'l', name: 'Italia')],
      movieCategories: [for (var c = 0; c < 6; c++) Category(id: 'c$c', name: 'Categoria $c')],
      seriesCategories: const [],
      live: const [MediaItem(kind: MediaKind.live, id: '1', name: 'Rai 1', categoryId: 'l')],
      movies: movies,
      series: const [],
      fetchedAt: 1,
    );
    final home = catalog.homeSnapshot(const ['movie:m5']);
    expect(home.partial, isTrue);
    expect(catalog.partial, isFalse);
    expect(home.movies.length, lessThan(catalog.movies.length));
    expect([for (final m in home.recentMovies) m.key], [for (final m in catalog.recentMovies) m.key]);
    expect([for (final c in home.movieCategories.take(4)) c.id], [for (final c in catalog.movieCategories.take(4)) c.id]);
    expect(home.byKey('movie:m5'), isNotNull);
    final copy = Catalog.fromJson(home.toJson());
    expect(copy.partial, isTrue);
    expect(copy.live.single.name, 'Rai 1');
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

  group('Home decisa dal pannello', () {
    test('nomi confrontati senza maiuscole, accenti e spazi doppi', () {
      expect(normalizeCategoryName('  Prime   VIDÉO  '), 'prime video');
      expect(normalizeCategoryName('Çinéma Française'), 'cinema francaise');
      expect(normalizeCategoryName('Cine\u0301ma'), 'cinema'); // accento già separato dalla lettera
    });

    test('voci separate da virgola, punto e virgola o a capo; nascosta vince su primo piano', () {
      final rules = HomeRules.parse('Sport, Prime Video;\nNetflix,, ', 'adult, xxx, 18+');
      expect(rules.top, ['sport', 'prime video', 'netflix']);
      expect(rules.hide, ['adult', 'xxx', '18+']);
      expect(rules.topRank('IT | SKY SPORT HD'), 0);
      expect(rules.topRank('Prime  Vidéo'), 1);
      expect(rules.topRank('Netflix Adult'), -1);
      expect(rules.hidden('Film per ADULTI'), isTrue);
      expect(rules.hidden('VM 18+'), isTrue);
      expect(rules.hidden('Commedia'), isFalse);
      expect(HomeRules.parse('', ' , ').isEmpty, isTrue);
    });

    test('elenchi: prima in primo piano (ordine delle voci), poi le altre, in fondo le nascoste', () {
      const cats = [
        Category(id: 'a', name: 'Cinema'),
        Category(id: 'b', name: 'XXX Hot'),
        Category(id: 'c', name: 'Netflix Serie'),
        Category(id: 'd', name: 'Sport 1'),
        Category(id: 'e', name: 'Documentari'),
        Category(id: 'f', name: 'Sport 2'),
        Category(id: 'g', name: 'Prime Video'),
      ];
      final ordered = HomeRules.parse('sport, prime video, netflix', 'xxx').order(cats);
      expect([for (final c in ordered) c.id], ['d', 'f', 'g', 'c', 'a', 'e', 'b']);
      expect(identical(HomeRules.none.order(cats), cats), isTrue);
    });

    test('righe della Home: primo piano, poi le solite senza nascoste e senza doppioni', () {
      MediaItem movie(String cat) => MediaItem(kind: MediaKind.movie, id: 'm$cat', name: 'Film $cat', categoryId: cat, added: cat.codeUnitAt(1));
      final catalog = Catalog.build(
        liveCategories: const [Category(id: 'l1', name: 'Intrattenimento'), Category(id: 'l2', name: 'SKY SPORT')],
        movieCategories: const [
          Category(id: 'c1', name: 'Azione'),
          Category(id: 'c2', name: 'Adulti XXX'),
          Category(id: 'c3', name: 'Commedia'),
          Category(id: 'c4', name: 'Netflix'),
          Category(id: 'c5', name: 'Horror'),
          Category(id: 'c6', name: 'Drammatico'),
        ],
        seriesCategories: const [],
        live: const [
          MediaItem(kind: MediaKind.live, id: '1', name: 'Rai 1', categoryId: 'l1'),
          MediaItem(kind: MediaKind.live, id: '2', name: 'Sky Sport 1', categoryId: 'l2'),
        ],
        movies: [for (final c in ['c1', 'c2', 'c3', 'c4', 'c5', 'c6']) movie(c)],
        series: const [],
        fetchedAt: 1,
      );
      final rules = HomeRules.parse('netflix, sport', 'xxx');
      final home = rules.layout(catalog);
      expect(home.top.map((e) => '${e.$1.name}:${e.$2.id}').toList(), ['movie:c4', 'live:l2']);
      expect(home.live?.id, 'l1');
      expect([for (final c in home.movies) c.id], ['c1', 'c3', 'c5', 'c6']);
      expect(rules.hiddenIds(catalog, MediaKind.movie), {'c2'});

      final usual = HomeRules.none.layout(catalog);
      expect(usual.top, isEmpty);
      expect(usual.live?.id, 'l1');
      expect([for (final c in usual.movies) c.id], ['c1', 'c2', 'c3', 'c4']);

      // la copia veloce della Home ha anche le categorie in primo piano
      final quick = catalog.homeSnapshot(const [], rules: rules);
      expect(quick.byKey('movie:mc4'), isNotNull);
      expect(quick.byKey('live:2'), isNotNull);
      expect(rules.layout(quick).top.map((e) => e.$2.id).toList(), ['c4', 'l2']);
    });
  });
}
