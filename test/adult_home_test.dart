import 'dart:convert';
import 'dart:io' as io;

import 'package:flutter_test/flutter_test.dart';
import 'package:kairos_plus/data/home_rules.dart';
import 'package:kairos_plus/data/models.dart';

/// Adulti fuori dalla Home (contratto comune di tutte le app Kairos, 9 novembre 2026).
/// `adult_vectors.json` è la copia esatta di `vectors.json` del contratto: 94 esempi, stesso esito in ogni app.
void main() {
  group('Riconoscimento degli adulti (esempi del contratto)', () {
    final vectors = jsonDecode(io.File('test/adult_vectors.json').readAsStringSync()) as Map<String, dynamic>;
    List<String> examples(String key) => [for (final s in vectors[key] as List<dynamic>) s as String];
    final catTrue = examples('cat_true');
    final catFalse = examples('cat_false');
    final titleTrue = examples('title_true');
    final titleFalse = examples('title_false');

    test('ci sono tutti i 94 esempi', () {
      expect(catTrue.length + catFalse.length + titleTrue.length + titleFalse.length, 94);
    });

    test('categorie per adulti riconosciute', () {
      for (final s in catTrue) {
        expect(adultCat(s), isTrue, reason: 'categoria per adulti non riconosciuta: «$s»');
      }
    });

    test('categorie normali lasciate stare', () {
      for (final s in catFalse) {
        expect(adultCat(s), isFalse, reason: 'categoria presa per adulti per sbaglio: «$s»');
      }
    });

    test('titoli per adulti riconosciuti (solo parole forti)', () {
      for (final s in titleTrue) {
        expect(adultTitle(s), isTrue, reason: 'titolo per adulti non riconosciuto: «$s»');
      }
    });

    test('titoli normali lasciati stare', () {
      for (final s in titleFalse) {
        expect(adultTitle(s), isFalse, reason: 'titolo preso per adulti per sbaglio: «$s»');
      }
    });

    test('titoli: stesso esito con la normalizzazione completa (nomi non ASCII) e in maiuscolo', () {
      // l'accento combinante in coda rende il nome non ASCII (via completa) e la normalizzazione lo toglie
      for (final s in titleTrue) {
        expect(adultTitle('$ś'), isTrue, reason: '«$s» con un accento in coda');
        expect(adultTitle(s.toUpperCase()), isTrue, reason: '«$s» in maiuscolo');
      }
      for (final s in titleFalse) {
        expect(adultTitle('$ś'), isFalse, reason: '«$s» con un accento in coda');
        expect(adultTitle(s.toUpperCase()), isFalse, reason: '«$s» in maiuscolo');
      }
      expect(adultTitle('Pornô Star'), isTrue);
      expect(adultTitle('Éducation sexuelle'), isFalse);
      expect(adultTitle('  PLAYBOY\t\tTV  '), isTrue);
    });

    test('normalizzazione: larghezza piena, accenti, maiuscole e spazi', () {
      expect(adultNormalize('ＸＸＸ'), 'xxx');
      expect(adultNormalize('  Érotique   HD '), 'erotique hd');
      expect(adultNormalize('Ｆｉｌｍ　＋１８'), 'film +18');
      expect(adultCat('Ｆｉｌｍ　＋１８'), isTrue);
      expect(adultTitle('ＢＲＡＺＺＥＲＳ １'), isTrue);
      expect(adultCat('Adult Swim'), isFalse);
      expect(adultCat('ADULT SWIM + XXX'), isTrue); // «adult swim» tolto, resta «xxx»
      expect(adultCat('Per adulti +18'), isTrue);
    });

    test('rc «adult»: filtro attivo se non è «on», anche assente o vuoto', () {
      expect(adultHiddenFromHome(null), isTrue);
      expect(adultHiddenFromHome(''), isTrue);
      expect(adultHiddenFromHome('off'), isTrue);
      expect(adultHiddenFromHome('on'), isFalse);
    });
  });

  group('Regole della Home con e senza «adult»', () {
    MediaItem movie(String id, String name, String cat, int added) =>
        MediaItem(kind: MediaKind.movie, id: id, name: name, categoryId: cat, added: added);
    MediaItem series(String id, String name, String cat, int added) =>
        MediaItem(kind: MediaKind.series, id: id, name: name, categoryId: cat, added: added);

    Catalog sample() => Catalog.build(
          liveCategories: const [Category(id: 'l1', name: 'Per adulti +18'), Category(id: 'l2', name: 'Intrattenimento')],
          movieCategories: const [
            Category(id: 'c1', name: '+18'),
            Category(id: 'c2', name: 'Azione'),
            Category(id: 'c3', name: 'ＸＸＸ'),
            Category(id: 'c4', name: 'Commedia'),
            Category(id: 'c5', name: 'Horror'),
            Category(id: 'c6', name: 'Drammatico'),
            Category(id: 'c7', name: 'Documentari'),
          ],
          seriesCategories: const [Category(id: 's1', name: 'Hot Club'), Category(id: 's2', name: 'Serie TV')],
          live: const [
            MediaItem(kind: MediaKind.live, id: '1', name: 'Canale notte', categoryId: 'l1'),
            MediaItem(kind: MediaKind.live, id: '2', name: 'Brazzers TV', categoryId: 'l2'),
            MediaItem(kind: MediaKind.live, id: '3', name: 'Rai 1', categoryId: 'l2'),
          ],
          movies: [
            movie('m1', 'Notte rossa', 'c1', 90),
            movie('m2', 'Film 18+', 'c2', 80),
            movie('m3', 'Senza titolo', 'c3', 70),
            movie('m4', 'Sexy Beast', 'c4', 60),
            movie('m5', 'Inseguimento', 'c2', 50),
            movie('m6', 'Paura', 'c5', 40),
            movie('m7', 'Lacrime', 'c6', 30),
            movie('m8', 'Pianeta', 'c7', 20),
          ],
          series: [
            series('t1', 'Notti calde', 's1', 99),
            series('t2', 'Hentai Heaven', 's2', 98),
            series('t3', 'Sex Education', 's2', 10),
          ],
          fetchedAt: 1,
        );

    List<String> keys(Iterable<MediaItem> items) => [for (final x in items) x.key];

    test('senza regole e con «adult» = «on»: tutto come prima', () {
      final on = HomeRules.parse('', '');
      expect(on.isEmpty, isTrue);
      expect(on.hidden('Per adulti +18'), isFalse);
      const cats = [Category(id: 'a', name: 'Cinema'), Category(id: 'b', name: '+18')];
      expect(identical(on.order(cats), cats), isTrue);
      final catalog = sample();
      final home = on.layout(catalog);
      expect(home.live?.id, 'l1');
      expect([for (final c in home.movies) c.id], ['c1', 'c2', 'c3', 'c4']);
      expect([for (final c in home.series) c.id], ['s1', 's2']);
      expect(on.blocked(catalog, catalog.movies.first), isFalse);
      expect(on.heroPick(catalog)?.key, 'movie:m1'); // il riquadro come prima: il film più recente
      final entries = [WatchProgress(item: _saved('movie:m1', 'Notte rossa', MediaKind.movie), positionMs: 1, durationMs: 9, updatedAt: 1)];
      expect(identical(on.resume(catalog, entries), entries), isTrue);
    });

    test('adulti fuori: le categorie per adulti contano come nascoste e vanno in fondo agli elenchi', () {
      final rules = HomeRules.parse('', '', hideAdult: true);
      expect(rules.isEmpty, isFalse);
      expect(rules.hidden('Per adulti +18'), isTrue);
      expect(rules.hidden('ＸＸＸ'), isTrue);
      expect(rules.hidden('Adult Swim'), isFalse);
      expect(rules.hidden('Intrattenimento'), isFalse);
      const cats = [
        Category(id: 'a', name: 'Cinema'),
        Category(id: 'b', name: '+18'),
        Category(id: 'c', name: 'Sport'),
        Category(id: 'd', name: 'Film erotici'),
        Category(id: 'e', name: 'Kids'),
      ];
      expect([for (final c in rules.order(cats)) c.id], ['a', 'c', 'e', 'b', 'd']);
      // in primo piano mai una categoria per adulti, anche se lo schema la prenderebbe
      final top = HomeRules.parse('film', '', hideAdult: true);
      expect(top.topRank('Film +18'), -1);
      expect(top.topRank('Film HD'), 0);
      // la lista «home.hide» continua a valere insieme al riconoscimento
      final both = HomeRules.parse('', 'sport', hideAdult: true);
      expect(both.hidden('Sport'), isTrue);
      expect(both.hidden('Hot Club'), isTrue);
      expect(HomeRules.sourceOf('a', 'b', true), isNot(HomeRules.sourceOf('a', 'b', false)));
    });

    test('righe di categoria della Home senza categorie per adulti', () {
      final catalog = sample();
      final rules = HomeRules.parse('', '', hideAdult: true);
      final home = rules.layout(catalog);
      expect(home.live?.id, 'l2');
      expect([for (final c in home.movies) c.id], ['c2', 'c4', 'c5', 'c6']);
      expect([for (final c in home.series) c.id], ['s2']);
      expect(rules.hiddenIds(catalog, MediaKind.movie), {'c1', 'c3'});
      expect(rules.hiddenIds(catalog, MediaKind.series), {'s1'});
      // categorie in primo piano: quella per adulti non entra anche se lo schema la prende
      final top = HomeRules.parse('adulti, intratt', '', hideAdult: true).layout(catalog);
      expect([for (final p in top.top) p.$2.id], ['l2']);
      final topOn = HomeRules.parse('adulti, intratt', '').layout(catalog);
      expect([for (final p in topOn.top) p.$2.id], ['l1', 'l2']); // «on»: come prima
    });

    test('elementi: categoria per adulti o nascosta, oppure titolo per adulti', () {
      final catalog = sample();
      final rules = HomeRules.parse('', 'horror', hideAdult: true);
      bool blocked(String key) => rules.blocked(catalog, catalog.byKey(key)!);
      expect(blocked('movie:m1'), isTrue); // categoria «+18»
      expect(blocked('movie:m2'), isTrue); // titolo «Film 18+» in «Azione»
      expect(blocked('movie:m3'), isTrue); // categoria «ＸＸＸ»
      expect(blocked('movie:m4'), isFalse); // «Sexy Beast»: titolo normale
      expect(blocked('movie:m5'), isFalse);
      expect(blocked('movie:m6'), isTrue); // categoria nascosta dalla lista «home.hide»
      expect(blocked('live:1'), isTrue);
      expect(blocked('live:2'), isTrue); // «Brazzers TV» in una categoria normale
      expect(blocked('live:3'), isFalse);
      expect(blocked('series:t1'), isTrue);
      expect(blocked('series:t2'), isTrue);
      expect(blocked('series:t3'), isFalse); // «Sex Education» resta
      // righe della Home come le filtra la pagina: aggiunti di recente senza adulti
      expect(keys(catalog.recentMovies.where((x) => !rules.blocked(catalog, x))), ['movie:m4', 'movie:m5', 'movie:m7', 'movie:m8']);
      expect(keys(catalog.recentSeries.where((x) => !rules.blocked(catalog, x))), ['series:t3']);
      // stesso esito alla seconda richiesta (titolo calcolato una volta per elemento)
      expect(blocked('movie:m2'), isTrue);
    });

    test('riquadro in evidenza: mai un titolo per adulti, e non resta vuoto', () {
      final catalog = sample();
      expect(HomeRules.parse('', '', hideAdult: true).heroPick(catalog)?.key, 'movie:m4');
      // solo titoli per adulti fra i recenti: si sceglie fra quelli delle righe della Home
      final onlyAdult = Catalog.build(
        liveCategories: const [Category(id: 'l', name: 'Intrattenimento')],
        movieCategories: const [Category(id: 'x', name: 'XXX')],
        seriesCategories: const [],
        live: const [
          MediaItem(kind: MediaKind.live, id: '1', name: 'XXX Private', categoryId: 'l'),
          MediaItem(kind: MediaKind.live, id: '2', name: 'Rai 2', categoryId: 'l'),
        ],
        movies: [movie('a', 'Uno', 'x', 2), movie('b', 'Due', 'x', 1)],
        series: const [],
        fetchedAt: 1,
      );
      expect(HomeRules.parse('', '', hideAdult: true).heroPick(onlyAdult)?.key, 'live:2');
      expect(HomeRules.parse('', '').heroPick(onlyAdult)?.key, 'movie:a'); // «on»: come prima
      // nessun recente da scartare: come prima (niente riquadro senza film né serie)
      final liveOnly = Catalog.build(
        liveCategories: const [Category(id: 'l', name: 'Intrattenimento')],
        movieCategories: const [],
        seriesCategories: const [],
        live: const [MediaItem(kind: MediaKind.live, id: '2', name: 'Rai 2', categoryId: 'l')],
        movies: const [],
        series: const [],
        fetchedAt: 1,
      );
      expect(HomeRules.parse('', '', hideAdult: true).heroPick(liveOnly), isNull);
      // «home.hide» senza filtro: come prima, salta solo le categorie nascoste
      expect(HomeRules.parse('', '+18').heroPick(catalog)?.key, 'movie:m2');
    });

    test('«Continua a guardare»: niente film né episodi per adulti', () {
      final catalog = sample();
      final rules = HomeRules.parse('', '', hideAdult: true);
      WatchProgress p(String key, String title, MediaKind kind, {String? subtitle}) =>
          WatchProgress(item: _saved(key, title, kind, subtitle: subtitle), positionMs: 1, durationMs: 9, updatedAt: 1);
      final entries = [
        p('movie:m1', 'Notte rossa', MediaKind.movie), // categoria per adulti
        p('movie:m5', 'Inseguimento', MediaKind.movie),
        p('episode:91', 'Notti calde', MediaKind.series, subtitle: 'S1 E2 · Primo'), // serie in «Hot Club»
        p('episode:92', 'Sex Education', MediaKind.series, subtitle: 'S1 E1 · Pilota'),
        p('episode:93', 'Sex Education', MediaKind.series, subtitle: 'S1 E3 · Brazzers'), // episodio con titolo forte
        p('movie:zz', 'XXX Private', MediaKind.movie), // non più nel catalogo, titolo per adulti
        p('movie:yy', 'Vecchio film', MediaKind.movie), // non più nel catalogo, titolo normale
        p('episode:94', 'Serie sparita', MediaKind.series, subtitle: 'S2 E1 · Ritorno'),
      ];
      expect([for (final e in rules.resume(catalog, entries)) e.item.key], ['movie:m5', 'episode:92', 'movie:yy', 'episode:94']);
      // copia veloce della Home: ciò che non contiene resta fuori finché arriva il catalogo completo
      final quick = catalog.homeSnapshot(const ['movie:m5'], rules: rules, seriesNames: const {'Sex Education', 'Notti calde'});
      expect(quick.partial, isTrue);
      expect(quick.byKey('series:t3'), isNotNull);
      expect([for (final e in rules.resume(quick, entries)) e.item.key], ['movie:m5', 'episode:92']);
      // la serie di un episodio salvato entra nella copia anche se non è in nessuna riga della Home
      final many = Catalog.build(
        liveCategories: const [],
        movieCategories: const [],
        seriesCategories: [for (var c = 0; c < 4; c++) Category(id: 'k$c', name: 'Gruppo $c')],
        live: const [],
        movies: const [],
        series: [for (var i = 0; i < 300; i++) series('v$i', 'Serie $i', 'k${i % 4}', i)],
        fetchedAt: 1,
      );
      expect(many.homeSnapshot(const [], rules: rules).byKey('series:v10'), isNull);
      expect(many.homeSnapshot(const [], rules: rules, seriesNames: const {'Serie 10'}).byKey('series:v10'), isNotNull);
    });

    test('copia veloce della Home calcolata con le stesse regole (anche nell\'isolate)', () {
      final catalog = sample();
      final rules = HomeRules.parse('', '', hideAdult: true);
      final quick = catalog.homeSnapshot(const [], rules: rules);
      final full = rules.layout(catalog);
      final copy = rules.layout(quick);
      expect([for (final c in copy.movies) c.id], [for (final c in full.movies) c.id]);
      expect([for (final c in copy.series) c.id], [for (final c in full.series) c.id]);
      expect(copy.live?.id, full.live?.id);
      expect(rules.heroPick(quick)?.key, rules.heroPick(catalog)?.key);
      // stesse regole rilette dai testi che riceve l'isolate
      final again = HomeRules.parse(rules.top.join(','), rules.hide.join(','), hideAdult: rules.hideAdult);
      expect(again.source, rules.source);
    });
  });
}

PlaybackItem _saved(String key, String title, MediaKind kind, {String? subtitle}) =>
    PlaybackItem(key: key, title: title, url: 'http://srv/x', subtitle: subtitle, kind: kind);
