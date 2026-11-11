import 'dart:convert';
import 'dart:io' as io;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kairos_plus/app/brand.dart';
import 'package:kairos_plus/app/perf.dart';
import 'package:kairos_plus/core/json.dart';
import 'package:kairos_plus/core/net.dart' as net;
import 'package:kairos_plus/data/catalog_repository.dart';
import 'package:kairos_plus/data/home_rules.dart';
import 'package:kairos_plus/data/models.dart';
import 'package:kairos_plus/data/sources/m3u_source.dart';
import 'package:kairos_plus/data/sources/xtream_source.dart';
import 'package:kairos_plus/panel/panel.dart';
import 'package:kairos_plus/state/app_updater.dart';
import 'package:kairos_plus/state/remote_quiet.dart';
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

  group('Rete e cache del catalogo', () {
    late io.HttpServer server;
    // azione Xtream (o percorso) → corpo della risposta (testo) oppure codice HTTP di errore
    final routes = <String, Object>{};

    setUpAll(() async {
      io.HttpOverrides.global = null; // client HTTP vero verso il server locale di prova
      server = await io.HttpServer.bind(io.InternetAddress.loopbackIPv4, 0);
      server.listen((request) {
        final body = routes[request.uri.queryParameters['action'] ?? request.uri.path];
        if (body is int) {
          request.response.statusCode = body;
        } else if (body is String) {
          request.response.add(utf8.encode(body));
        }
        request.response.close();
      });
    });

    tearDownAll(() async {
      net.closeClient(force: true);
      await server.close(force: true);
    });

    Uri at(String path) => Uri.parse('http://127.0.0.1:${server.port}$path');

    test('JSON letto mentre arriva: vuoto e spazi valgono null, il resto come prima', () async {
      routes['/vuota'] = '';
      routes['/spazi'] = ' \n\t ';
      routes['/ok'] = '{"a":[1,2.5,"è",null,true]}';
      routes['/rotta'] = '{"a":';
      routes['/errore'] = 404;
      expect(await net.fetchJson(at('/vuota')), isNull);
      expect(await net.fetchJson(at('/spazi')), isNull);
      expect(await net.fetchJson(at('/ok')), {
        'a': [1, 2.5, 'è', null, true],
      });
      await expectLater(net.fetchJson(at('/rotta')), throwsA(isA<net.SourceException>()));
      await expectLater(net.fetchJson(at('/errore')), throwsA(isA<net.SourceException>()));
    });

    test('catalogo Xtream: ogni voce convertita mentre arriva, con gli stessi dati di prima', () async {
      routes['get_live_categories'] = '[{"category_id":"1","category_name":"Italia"}]';
      routes['get_vod_categories'] = '[{"category_id":2,"category_name":"Azione"}]';
      routes['get_series_categories'] = '[]';
      routes['get_live_streams'] =
          '[{"num":1,"name":"Rai 1","stream_id":10,"stream_icon":"http://x/r1.png","epg_channel_id":"rai1",'
          '"category_id":"1","added":"1700000000","category_ids":[1]},'
          '{"name":"senza id"},"rotto",{"num":2,"name":"Rai 2","stream_id":"11","category_id":null}]';
      routes['get_vod_streams'] =
          '[{"name":"Film (2021)","stream_id":20,"category_id":"2","rating":"7.5","container_extension":"mkv"},'
          '{"name":"Altro","stream_id":21,"category_id":"2","rating_5based":4,"year":"2019"}]';
      routes['get_series'] = '';
      final account = Account(
        type: AccountType.xtream,
        server: 'http://127.0.0.1:${server.port}',
        username: 'u',
        password: 'p',
      );
      final catalog = await XtreamSource(account).fetchCatalog();
      expect([for (final c in catalog.live) '${c.id}|${c.name}|${c.categoryId}|${c.number}|${c.epgId}|${c.added}'], [
        '10|Rai 1|1|1|rai1|1700000000',
        '11|Rai 2|$uncategorizedId|2|null|0',
      ]);
      expect(catalog.live.first.image, 'http://x/r1.png');
      final film = catalog.movies.first;
      expect([film.name, film.year, film.rating, film.extension], ['Film (2021)', '2021', 7.5, 'mkv']);
      final other = catalog.movies.last;
      expect([other.year, other.rating, other.extension], ['2019', 8.0, 'mp4']);
      expect(catalog.series, isEmpty);
      expect(catalog.categoryName(MediaKind.live, '1'), 'Italia');
      expect(catalog.categoryName(MediaKind.movie, '2'), 'Azione');
      expect(catalog.categoryName(MediaKind.live, uncategorizedId), 'Altri');
      expect(catalog.categoryName(MediaKind.live, 'nessuna'), '');
    });

    test('lista M3U letta riga per riga mentre arriva: stesso catalogo del testo intero', () async {
      const text = '\uFEFF#EXTM3U\r\n'
          '#EXTINF:-1 tvg-id="rai1" tvg-logo="http://x/l.png" group-title="Italia",Rai 1\r\n'
          'http://srv/live/u/p/1.ts\r\n'
          '\r\n'
          '#EXTINF:-1,Canale senza gruppo è\n'
          '#EXTGRP:Sport\n'
          'http://srv/live/u/p/2.ts\n'
          '#EXTINF:-1 group-title="Film",Titolo, con virgola (2021)\r'
          'http://srv/movie/u/p/10.mkv';
      routes['/lista.m3u'] = text;
      final streamed = await M3uSource(at('/lista.m3u').toString()).fetchCatalog();
      final whole = parseM3uCatalog(text);
      Map<String, Object?> body(Catalog c) => {...c.toJson()}..remove('t');
      expect(jsonEncode(body(streamed)), jsonEncode(body(whole)));
      expect([for (final c in streamed.live) c.name], ['Rai 1', 'Canale senza gruppo è']);
      expect(streamed.live.last.categoryId, 'g:Sport');
      expect(streamed.movies.single.year, '2021');
    });

    test('la cache su file si scrive in UTF-8 a pezzi e si rilegge identica', () {
      final dir = io.Directory.systemTemp.createTempSync('kairos_test');
      try {
        final catalog = Catalog.build(
          liveCategories: const [Category(id: '1', name: 'Italia')],
          movieCategories: const [Category(id: '2', name: 'Azione «è»')],
          seriesCategories: const [],
          live: [
            for (var i = 0; i < 3000; i++)
              MediaItem(kind: MediaKind.live, id: '$i', name: 'Canale $i ✓', categoryId: '1', number: i, image: 'http://x/$i.png'),
          ],
          movies: const [
            MediaItem(
              kind: MediaKind.movie,
              id: '20',
              name: 'Sintel',
              categoryId: '2',
              year: '2010',
              rating: 7.5,
              added: 5,
              plot: 'Trama "tra virgolette"\ne a capo',
            ),
          ],
          series: const [],
          fetchedAt: 42,
        );
        final path = '${dir.path}${io.Platform.pathSeparator}catalogo.json';
        writeCatalogFile(path, catalog.toCacheJson());
        expect(io.File(path).readAsBytesSync(), utf8.encode(jsonEncode(catalog.toJson())));
        expect(io.File('$path.part').existsSync(), isFalse);
        final copy = readCatalogFile(path);
        if (copy == null) fail('cache non riletta');
        expect(jsonEncode(copy.toJson()), jsonEncode(catalog.toJson()));
        expect(copy.categoryName(MediaKind.movie, '2'), 'Azione «è»');
        expect(readCatalogFile('${dir.path}${io.Platform.pathSeparator}manca.json'), isNull);
        io.File(path).writeAsStringSync('{"l":[{"k":0');
        expect(readCatalogFile(path), isNull);
      } finally {
        dir.deleteSync(recursive: true);
      }
    });

    test('contenuti per adulti: stesso esito, calcolato una volta per voce', () {
      final catalog = Catalog.build(
        liveCategories: const [Category(id: 'a', name: 'XXX Adulti'), Category(id: 'b', name: 'Italia')],
        movieCategories: const [],
        seriesCategories: const [],
        live: const [
          MediaItem(kind: MediaKind.live, id: '1', name: 'Canale', categoryId: 'a'),
          MediaItem(kind: MediaKind.live, id: '2', name: 'Brazzers TV', categoryId: 'b'),
          MediaItem(kind: MediaKind.live, id: '3', name: 'Rai 1', categoryId: 'b'),
        ],
        movies: const [],
        series: const [],
        fetchedAt: 1,
      );
      for (var round = 0; round < 2; round++) {
        expect([for (final c in catalog.live) catalog.isAdult(c)], [true, true, false]);
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

    test('indirizzi dei flussi e della guida breve identici a quelli costruiti ogni volta da Uri', () {
      const accounts = [
        Account(type: AccountType.xtream, server: 'http://srv:80', username: 'u', password: 'p'),
        Account(type: AccountType.xtream, server: 'https://srv.example:8443', username: 'mario rossi', password: 'p@ss/w+rd&x=1 è'),
        Account(type: AccountType.xtream, server: 'http://srv.example', username: 'u', password: ''),
      ];
      for (final account in accounts) {
        final source = XtreamSource(account);
        final u = Uri.encodeComponent(account.username ?? '');
        final p = Uri.encodeComponent(account.password ?? '');
        for (final id in ['42', 'a b', '']) {
          final channel = MediaItem(kind: MediaKind.live, id: id, name: 'Canale', categoryId: '1');
          final expected = Uri.parse('${account.server}/player_api.php').replace(queryParameters: {
            'username': account.username ?? '',
            'password': account.password ?? '',
            'action': 'get_short_epg',
            'stream_id': id,
            'limit': '4',
          }).toString();
          expect(source.epgUrlFor(channel), expected);
          expect(source.urlFor(channel, liveFormat: 'm3u8'), '${account.server}/live/$u/$p/$id.m3u8');
        }
        const movie = MediaItem(kind: MediaKind.movie, id: '7', name: 'Film', categoryId: '2', extension: 'mkv');
        expect(source.urlFor(movie), '${account.server}/movie/$u/$p/7.mkv');
        const episode = Episode(id: '9', season: 1, number: 2, title: 'Ep', extension: 'mp4');
        expect(source.episodeUrl(episode), '${account.server}/series/$u/$p/9.mp4');
      }
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

  group('Aggiornamento dell\'app', () {
    const channel = MethodChannel('kairos/native');
    final calls = <String>[];
    final args = <String, Object?>{}; // argomenti dell'ultima chiamata di ogni metodo
    var status = <String, Object?>{'ready': true, 'canInstall': true};

    setUpAll(() {
      TestWidgetsFlutterBinding.ensureInitialized(); // canale verso Android simulato
    });

    setUp(() {
      calls.clear();
      args.clear();
      status = <String, Object?>{'ready': true, 'canInstall': true};
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        args[call.method] = call.arguments;
        return call.method == 'updateStatus' ? status : null;
      });
    });

    const saved = '{"code":21,"version":"0.1.21","url":"https://example.org/kairos-plus.apk"}';

    AppUpdater updater({String pending = saved, String first = '21:0', int? days = 0, bool Function()? watching}) => AppUpdater(
          feedUrls: () => const ['https://example.org/kairos-plus.json'],
          currentCode: 20,
          currentVersion: '0.1.20',
          backgroundEnabled: () => true,
          forceDays: () => days,
          watching: watching ?? (() => false),
          loadFirstSeen: () async => first,
          saveFirstSeen: (_) async {},
          loadPending: () async => pending,
          savePending: (_) async {},
        );

    test('obbligatorio e scaduto: noto subito all\'avvio, senza rete, e si ripropone a ogni tentativo di visione', () async {
      final u = updater();
      await u.restore();
      expect(u.pending?.code, 21);
      expect(u.ready, isTrue);
      expect(u.mustUpdate, isTrue);
      expect(u.offer.value?.code, 21);
      u.offer.value = null; // la finestra l'ha presa
      expect(u.remindIfMandatory(), isTrue);
      expect(u.offer.value?.code, 21);
      u.dispose();
    });

    test('non obbligatorio: proposto all\'avvio, ma la visione non si ferma', () async {
      final u = updater(days: null);
      await u.restore();
      expect(u.mustUpdate, isFalse);
      expect(u.offer.value?.code, 21);
      u.offer.value = null;
      expect(u.remindIfMandatory(), isFalse);
      u.dispose();
    });

    test('proposta arrivata durante la visione: si mostra al ritorno in un menu', () async {
      var watching = true;
      final u = updater(days: null, first: '', watching: () => watching);
      await u.restore();
      expect(u.offer.value, isNull);
      watching = false;
      u.onPlaybackEnded();
      expect(u.offer.value?.code, 21);
      u.dispose();
    });

    test('Android 12+, si installa da sola all\'uscita: nessuna proposta (obbligatorio sì, dopo 3 giorni torna)', () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      status = <String, Object?>{'ready': true, 'canInstall': true, 'quiet': true};
      final q = updater(days: null, first: '21:$now');
      await q.restore();
      expect(q.quiet, isTrue);
      expect(q.offer.value, isNull);
      expect(await q.fromPanel(), contains('si installa da sola'));
      q.dispose();
      final must = updater(days: 0, first: '21:$now');
      await must.restore();
      expect(must.mustUpdate, isTrue);
      expect(must.offer.value?.code, 21);
      must.dispose();
      final old = updater(days: null, first: '21:${now - 4 * 86400000}');
      await old.restore();
      expect(old.offer.value?.code, 21);
      old.dispose();
      status = <String, Object?>{'ready': true, 'canInstall': true, 'quiet': false, 'quietBlocked': true};
      final blocked = updater(days: null, first: '21:$now');
      await blocked.restore();
      expect(blocked.offer.value?.code, 21);
      expect(blocked.message, contains('Blocco automatico'));
      blocked.dispose();
    });

    test('versione salvata già installata o APK non ancora scaricato: nessun blocco', () async {
      final old = updater(pending: '{"code":20,"version":"0.1.20","url":"https://example.org/a.apk"}');
      await old.restore();
      expect(old.pending, isNull);
      old.dispose();
      status = <String, Object?>{'ready': false, 'canInstall': true};
      final notReady = updater();
      await notReady.restore();
      expect(notReady.pending?.code, 21);
      expect(notReady.mustUpdate, isFalse);
      expect(notReady.offer.value, isNull);
      notReady.dispose();
    });

    const dlFeed = 'https://store-k.download/get/plus.json';
    const dlApk = 'https://store-k.download/get/plus.apk';
    const res = 'https://riserva-k.download';
    const res2 = 'https://riserva2-k.download';
    const resFeed = '$res/get/plus.json';
    const resApk = '$res/get/plus.apk';
    const res2Apk = '$res2/get/plus.apk';

    AppUpdater checker({
      required List<String> Function() feeds,
      required Future<Object?> Function(Uri uri) fetch,
      List<String> Function(String url)? apks,
      void Function(List<String>)? keep,
      String pending = '',
    }) =>
        AppUpdater(
          feedUrls: feeds,
          fetchFeed: fetch,
          apkUrlsFor: apks,
          saveMirrors: keep,
          currentCode: 20,
          currentVersion: '0.1.20',
          backgroundEnabled: () => true,
          forceDays: () => null,
          watching: () => false,
          loadFirstSeen: () async => '',
          saveFirstSeen: (_) async {},
          loadPending: () async => pending,
          savePending: (_) async {},
        );

    test('feed: il dominio dei download, poi le riserve; niente pannello né GitHub', () {
      expect(Brand.dlBase, 'https://store-k.download');
      expect(updateFeeds(Brand.dlBase, 'plus'), [dlFeed]);
      expect(updateFeeds('https://store-k.download/', 'plus'), [dlFeed]);
      // riserva compilata vuota, doppioni e barre finali si saltano
      expect(updateFeeds(Brand.dlBase, 'plus', ['', '$res/', 'https://store-k.download']), [dlFeed, resFeed]);
      // solo https e solo il dominio: http, percorsi e indirizzi senza schema si scartano
      expect(updateFeeds('http://store-k.download', 'plus', ['$res/x', 'riserva-k.download', res2]), ['$res2/get/plus.json']);
      expect(updateFeeds('', 'plus'), isEmpty);
      // al massimo 4 basi
      expect(downloadBases(Brand.dlBase, ['https://a-k.download', 'https://b-k.download', 'https://c-k.download', 'https://d-k.download']),
          ['https://store-k.download', 'https://a-k.download', 'https://b-k.download', 'https://c-k.download']);
      final all = updateFeeds(Brand.dlBase, 'plus', [Brand.dlBase2, res]).join(' ');
      expect(all, isNot(contains('panel-kairos.com')));
      expect(all, isNot(contains('github.com')));
    });

    test('APK: link del feed, poi le basi successive; un link fuori dalle basi passa a tutte', () {
      const extra = [res, res2];
      expect(apkUrls(dlApk, Brand.dlBase, 'plus'), [dlApk]);
      expect(apkUrls(dlApk, Brand.dlBase, 'plus', extra), [dlApk, resApk, res2Apk]);
      // feed dalla riserva (dominio dei download giù): il dominio dei download non si riprova
      expect(apkUrls(resApk, Brand.dlBase, 'plus', extra), [resApk, res2Apk]);
      // link fuori dalle basi: il suo link, poi tutte le basi
      const other = 'https://cdn.example.org/kairos-plus.apk';
      expect(apkUrls(other, Brand.dlBase, 'plus', extra), [other, dlApk, resApk, res2Apk]);
      expect(apkUrls('http://store-k.download/get/plus.apk', Brand.dlBase, 'plus'), [dlApk]);
    });

    test('«mirrors» del feed: solo https validi, senza doppioni, al massimo 3; senza lista restano quelli ricordati', () {
      expect(
        feedMirrors(<String, Object?>{
          'mirrors': [Brand.dlBase, '$res/', 'http://x-k.download', res, 5, 'https://a-k.download', 'https://b-k.download'],
        }),
        [Brand.dlBase, res, 'https://a-k.download'],
      );
      expect(feedMirrors(<String, Object?>{'mirrors': <Object?>[]}), isEmpty);
      expect(feedMirrors(<String, Object?>{'version': '0.1.24'}), isNull);
      expect(feedMirrors(<String, Object?>{'mirrors': res}), isNull);
      expect(parseFeed(<String, Object?>{'version': '0.1.24', 'versionCode': 24, 'url': dlApk, 'mirrors': [res]})?.mirrors, [res]);
      expect(parseFeed(<String, Object?>{'version': '0.1.24', 'versionCode': 24, 'url': dlApk})?.mirrors, isNull);
    });

    test('feed: dominio dei download non attivo, parcheggiato o con un JSON non valido → la riserva', () async {
      final failures = <Future<Object?> Function()>[
        () async => throw const io.SocketException('Failed host lookup: store-k.download'),
        () async => throw const FormatException('<!DOCTYPE html>'), // pagina parcheggiata
        () async => throw const net.SourceException('Il server ha risposto con errore 502'),
        () async => null, // risposta diversa da 200
        () async => <String, Object?>{'error': 'non disponibile'},
        () async => <String, Object?>{'version': '0.1.24', 'versionCode': 24, 'url': 'http://store-k.download/get/plus.apk'},
      ];
      for (final fail in failures) {
        final asked = <String>[];
        final u = await firstFeed(updateFeeds(Brand.dlBase, 'plus', [res]), (uri) async {
          asked.add('$uri');
          if ('$uri' == resFeed) return <String, Object?>{'version': '0.1.24', 'versionCode': 24, 'url': resApk};
          return fail();
        });
        expect(u?.url, resApk);
        expect(asked, [dlFeed, resFeed]);
      }
    });

    test('feed: con il dominio dei download che risponde le riserve non si chiedono', () async {
      final asked = <String>[];
      final u = await firstFeed(updateFeeds(Brand.dlBase, 'plus', [res]), (uri) async {
        asked.add('$uri');
        return <String, Object?>{'version': '0.1.24', 'versionCode': 24, 'url': dlApk};
      });
      expect(u?.code, 24);
      expect(u?.url, dlApk);
      expect(asked, [dlFeed]); // nessun controllo in più del solito
    });

    test('feed: nessuno risponde → nessuna versione, come una rete giù', () async {
      final u = await firstFeed(updateFeeds(Brand.dlBase, 'plus', [res]), (_) async {
        throw const net.SourceException('Il server ha risposto con errore 404');
      });
      expect(u, isNull);
    });

    test('controllo: dominio dei download giù, versione dalla riserva; la parte nativa riceve le basi successive', () async {
      status = <String, Object?>{'ready': false, 'canInstall': true, 'metered': false};
      const extra = [res, res2];
      final asked = <String>[];
      final u = checker(
        feeds: () => updateFeeds(Brand.dlBase, 'plus', extra),
        fetch: (uri) async {
          asked.add('$uri');
          if (uri.host == 'store-k.download') throw const io.SocketException('Failed host lookup: store-k.download');
          return <String, Object?>{'version': '0.1.21', 'versionCode': 21, 'url': resApk};
        },
        apks: (url) => apkUrls(url, Brand.dlBase, 'plus', extra),
      );
      final found = await u.check();
      expect(found?.url, resApk);
      expect(asked, [dlFeed, resFeed]);
      expect(args['updatePrefetch'], {
        'url': resApk,
        'code': 21,
        'alts': [res2Apk],
      });
      await u.install();
      expect(args['updateInstall'], {
        'url': resApk,
        'code': 21,
        'alts': [res2Apk],
      });
      u.dispose();
    });

    test('controllo: senza riserve il feed è uno solo e l\'APK si scarica solo dal suo link', () async {
      status = <String, Object?>{'ready': false, 'canInstall': true, 'metered': false};
      final asked = <String>[];
      final u = checker(
        feeds: () => updateFeeds(Brand.dlBase, 'plus', const ['']),
        fetch: (uri) async {
          asked.add('$uri');
          return <String, Object?>{'version': '0.1.21', 'versionCode': 21, 'url': dlApk};
        },
        apks: (url) => apkUrls(url, Brand.dlBase, 'plus', const ['']),
      );
      final found = await u.check();
      expect(found?.code, 21);
      expect(asked, [dlFeed]);
      expect(calls, ['updateStatus', 'updatePrefetch']);
      expect(args['updatePrefetch'], {'url': dlApk, 'code': 21, 'alts': <String>[]});
      u.dispose();
    });

    test('controllo: i domini di riserva annunciati dal feed si ricordano e valgono dal controllo dopo', () async {
      var mirrors = <String>[];
      final kept = <List<String>>[];
      final asked = <String>[];
      var dlDown = false;
      final u = checker(
        feeds: () => updateFeeds(Brand.dlBase, 'plus', mirrors),
        fetch: (uri) async {
          asked.add('$uri');
          if (dlDown && uri.host == 'store-k.download') throw const io.SocketException('Failed host lookup: store-k.download');
          return <String, Object?>{
            'version': '0.1.21',
            'versionCode': 21,
            'url': 'https://${uri.host}/get/plus.apk',
            if (uri.host == 'store-k.download') 'mirrors': [Brand.dlBase, res],
          };
        },
        keep: (m) {
          kept.add(m);
          mirrors = m;
        },
      );
      await u.check();
      expect(asked, [dlFeed]);
      expect(kept, [
        [Brand.dlBase, res],
      ]);
      // il dominio dei download si spegne: la riserva imparata dal feed risponde
      dlDown = true;
      asked.clear();
      final found = await u.check(force: true);
      expect(asked, [dlFeed, resFeed]);
      expect(found?.url, resApk);
      expect(kept.length, 1); // il feed della riserva non ha la lista: quelli ricordati restano
      u.dispose();
    });

    test('controllo: feed non valido ovunque → la versione trovata prima resta, niente «già aggiornata»', () async {
      final v = checker(
        feeds: () => const [dlFeed, resFeed],
        fetch: (_) async => <String, Object?>{},
        pending: saved,
      );
      await v.restore();
      expect(await v.check(manual: true), isNotNull);
      expect(v.pending?.code, 21);
      expect(v.message, 'Impossibile controllare gli aggiornamenti adesso');
      v.dispose();
    });

    test('senza il permesso «Installa app sconosciute»: lo dice e al ritorno l\'installazione riparte', () async {
      final u = updater();
      await u.restore();
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
        'kairos/native',
        const StandardMethodCodec().encodeMethodCall(const MethodCall('updateEvent', '{"type":"perm"}')),
        null,
      );
      await Future<void>.delayed(Duration.zero);
      expect(u.message, contains('Installa app sconosciute'));
      calls.clear();
      await u.onResumed();
      expect(calls, ['updateStatus', 'updateInstall']);
      u.dispose();
    });
  });

  group('Feed degli aggiornamenti dalla rete', () {
    late io.HttpServer server;
    final routes = <String, Object>{};

    setUpAll(() async {
      io.HttpOverrides.global = null; // client HTTP vero verso il server locale di prova
      server = await io.HttpServer.bind(io.InternetAddress.loopbackIPv4, 0);
      server.listen((request) {
        final body = routes[request.uri.path];
        if (body is int) {
          request.response.statusCode = body;
        } else if (body is String) {
          request.response.add(utf8.encode(body));
        }
        request.response.close();
      });
    });

    tearDownAll(() async {
      await server.close(force: true);
    });

    String at(String path) => 'http://127.0.0.1:${server.port}$path';

    test('vale solo una risposta 200 con il JSON del feed: HTML parcheggiato, JSON rotto o errore → base successiva', () async {
      routes['/ok'] = '{"version":"0.1.24","versionCode":24,"url":"https://store-k.download/get/plus.apk"}';
      routes['/parcheggiato'] = '<!DOCTYPE html><html><body>Questo dominio è in vendita</body></html>';
      routes['/rotto'] = '{"version":';
      routes['/campi'] = '{"version":"0.1.24"}';
      routes['/errore'] = 502;
      expect(parseFeed(await fetchFeedJson(Uri.parse(at('/ok'))))?.code, 24);
      await expectLater(fetchFeedJson(Uri.parse(at('/parcheggiato'))), throwsA(isA<FormatException>()));
      await expectLater(fetchFeedJson(Uri.parse(at('/rotto'))), throwsA(isA<FormatException>()));
      expect(parseFeed(await fetchFeedJson(Uri.parse(at('/campi')))), isNull);
      expect(await fetchFeedJson(Uri.parse(at('/errore'))), isNull);
      final u = await firstFeed([at('/parcheggiato'), at('/rotto'), at('/campi'), at('/errore'), at('/ok')], fetchFeedJson);
      expect(u?.url, 'https://store-k.download/get/plus.apk');
    });

    test('indirizzo che non risponde (connessione rifiutata): si passa subito al successivo', () async {
      routes['/ok'] = '{"version":"0.1.24","versionCode":24,"url":"https://store-k.download/get/plus.apk"}';
      final closed = await io.ServerSocket.bind(io.InternetAddress.loopbackIPv4, 0);
      final port = closed.port;
      await closed.close();
      final watch = Stopwatch()..start();
      final u = await firstFeed(['http://127.0.0.1:$port/get/plus.json', at('/ok')], fetchFeedJson);
      expect(u?.code, 24);
      expect(watch.elapsed, lessThan(const Duration(seconds: 5)));
    });
  });

  group('Controlli a distanza senza avvisi', () {
    test('reset del PIN nei menu: si chiede subito il nuovo PIN, niente in attesa', () {
      final p = PinAsk();
      expect(p.onReset(watching: false), isTrue);
      expect(p.pending, isFalse);
      expect(p.onViewEnd(), isFalse);
    });

    test('reset del PIN durante la visione: il nuovo PIN si chiede a visione finita, una volta sola', () {
      final p = PinAsk();
      expect(p.onReset(watching: true), isFalse);
      expect(p.pending, isTrue);
      expect(p.onViewEnd(), isTrue);
      expect(p.onViewEnd(), isFalse);
    });

    test('nessun avviso sul «fornitore» per «Disconnetti», reset del PIN e permesso', () {
      final sources = [
        'lib/state/app_controller.dart',
        'lib/ui/shell/main_shell.dart',
        'android/app/src/main/kotlin/com/kairos/plus/MainActivity.kt',
      ].map((f) => io.File(f).readAsStringSync()).join('\n');
      expect(sources, isNot(contains('ha chiuso la visione')));
      expect(sources, isNot(contains('ha reimpostato il PIN')));
      expect(sources, isNot(contains('Visione interrotta')));
      expect(sources, contains('per gli aggiornamenti dell\'app'));
    });
  });
}
