import 'models.dart';

/// Nome di categoria pronto per il confronto: minuscolo, senza accenti, spazi multipli ridotti a uno
/// (come Kairos Pro: NFD e segni diacritici tolti).
String normalizeCategoryName(String value) {
  final out = StringBuffer();
  for (final rune in value.toLowerCase().runes) {
    if (rune >= 0x300 && rune <= 0x36f) continue; // segni diacritici già separati dalla lettera
    final plain = _plainLetters[rune];
    if (plain != null) {
      out.write(plain);
    } else {
      out.writeCharCode(rune);
    }
  }
  return out.toString().replaceAll(_spaces, ' ').trim();
}

final RegExp _spaces = RegExp(r'\s+');
final RegExp _separators = RegExp(r'[,;\n]+');

/// Lettere accentate (minuscole) → lettera senza accento: quelle che la forma NFD separa in lettera + segno.
final Map<int, String> _plainLetters = () {
  const groups = <String, String>{
    'a': 'àáâãäåāăą',
    'c': 'çćĉċč',
    'd': 'ď',
    'e': 'èéêëēĕėęě',
    'g': 'ĝğġģ',
    'h': 'ĥ',
    'i': 'ìíîïĩīĭį',
    'j': 'ĵ',
    'k': 'ķ',
    'l': 'ĺļľ',
    'n': 'ñńņň',
    'o': 'òóôõöōŏő',
    'r': 'ŕŗř',
    's': 'śŝşšș',
    't': 'ţťț',
    'u': 'ùúûüũūŭůűų',
    'w': 'ŵ',
    'y': 'ýÿŷ',
    'z': 'źżž',
  };
  final map = <int, String>{};
  for (final group in groups.entries) {
    for (final rune in group.value.runes) {
      map[rune] = group.key;
    }
  }
  return map;
}();

// ---------------------------------------------------------------------------
// Adulti fuori dalla Home: riconoscimento comune a tutte le app Kairos (contratto del 9 novembre 2026).

/// Il pannello vuole gli adulti fuori dalla Home: rc «adult» diverso da «on», quindi anche assente o vuoto.
bool adultHiddenFromHome(Object? rcValue) => rcValue?.toString() != 'on';

/// Nome pronto per il riconoscimento degli adulti. In Dart la forma NFKD non c'è: le lettere a larghezza piena
/// (U+FF01–U+FF5E, «ＸＸＸ») diventano quelle normali sottraendo 0xFEE0, poi come [normalizeCategoryName]
/// (minuscolo, senza accenti, spazi multipli ridotti a uno e tolti ai bordi).
String adultNormalize(String value) {
  final out = StringBuffer();
  for (final rune in value.runes) {
    out.writeCharCode(rune >= 0xFF01 && rune <= 0xFF5E ? rune - 0xFEE0 : rune);
  }
  return normalizeCategoryName(out.toString());
}

// Le due espressioni del contratto, identiche in tutte le app (stringhe «raw»: in una stringa normale «\b»
// sarebbe il carattere di backspace). Si provano sul nome già normalizzato, quindi senza maiuscole.
final RegExp _adultCategory = RegExp(
    r'(\bxxx\b|adult|\bporn|erotic|erotik|erotis|erotiq|hentai|\b18\s*\+|\+\s*18\b|\bv\.?\s*m\.?\s*18\b|\bsexy?\b|\bhot\s*club\b|playboy|brazzers|hustler|dorcel|only\s*fans|red\s*light|\bx[\s-]?rated\b|\bnsfw\b|\bmilf\b|private\s*tv|vietato ai minori)');
const String _adultTitlePattern =
    r'(\bxxx\b|\bporn|hentai|brazzers|playboy\s*tv|hustler\s*tv|dorcel|only\s*fans|\b18\s*\+|\+\s*18\b)';
final RegExp _adultTitle = RegExp(_adultTitlePattern);
// La stessa senza maiuscole, per i nomi tutti ASCII: lì normalizzare vuol dire solo passare in minuscolo (gli spazi
// multipli e ai bordi non cambiano l'esito), quindi stesso risultato senza creare testi nuovi per ogni titolo.
final RegExp _adultTitleAscii = RegExp(_adultTitlePattern, caseSensitive: false);
final RegExp _adultSwim = RegExp(r'adult\s*swim');

bool _ascii(String s) {
  for (var i = 0; i < s.length; i++) {
    if (s.codeUnitAt(i) > 0x7F) return false;
  }
  return true;
}

/// Categoria per adulti: il nome normalizzato, tolto «adult swim», contiene una parola per adulti.
bool adultCat(String name) => _adultCategory.hasMatch(adultNormalize(name).replaceAll(_adultSwim, ''));

/// Titolo o canale per adulti: solo le parole forti (un film come «Sex Education» resta dov'è).
bool adultTitle(String name) =>
    _ascii(name) ? _adultTitleAscii.hasMatch(name) : _adultTitle.hasMatch(adultNormalize(name));

/// Esito di [adultTitle] per ogni elemento, calcolato una volta sola (l'elemento non cambia mai nome).
final Expando<bool> _strongTitle = Expando<bool>('titolo per adulti');

bool _titleOf(MediaItem item) => _strongTitle[item] ??= adultTitle(item.name);

/// Film o episodio salvato in «Continua a guardare»: il titolo e la riga sotto (per gli episodi «S1 E2 · titolo»).
bool _savedTitleOf(PlaybackItem item) =>
    _strongTitle[item] ??= adultTitle(item.title) || adultTitle(item.subtitle ?? '');

/// Categorie della Home: quelle in primo piano e le solite righe di categoria.
class HomeLayout {
  const HomeLayout({required this.top, required this.live, required this.movies, required this.series});

  /// In primo piano (al massimo 10), nell'ordine degli schemi.
  final List<(MediaKind, Category)> top;

  /// Le solite righe, senza le nascoste e senza quelle già in primo piano.
  final Category? live;
  final List<Category> movies;
  final List<Category> series;
}

/// Home decisa dal fornitore (Controllo remoto del pannello): categorie in primo piano (rc «home.top») e
/// nascoste dalla Home (rc «home.hide»). Ogni voce è un nome o una parte di nome; maiuscole, accenti e spazi
/// doppi non contano. Una categoria nascosta non va mai in primo piano (come in Kairos Pro).
///
/// Con [hideAdult] (rc «adult» diverso da «on») le categorie per adulti ([adultCat]) contano come nascoste e
/// nelle righe della Home non entra nessun elemento per adulti ([blocked]).
class HomeRules {
  HomeRules._(this.source, this.top, this.hide, this.hideAdult);

  factory HomeRules.parse(String top, String hide, {bool hideAdult = false}) =>
      HomeRules._(sourceOf(top, hide, hideAdult), _split(top), _split(hide), hideAdult);

  /// Nessuna regola: Home ed elenchi come sempre.
  static final HomeRules none = HomeRules.parse('', '');

  /// Al massimo tante righe in primo piano nella Home.
  static const int maxTop = 10;

  /// Testo da cui nascono le regole (per accorgersi quando il pannello le cambia, anche solo «adult»).
  static String sourceOf(String top, String hide, bool hideAdult) => '$top\n$hide\n${hideAdult ? 'adulti fuori' : ''}';

  /// Testo da cui sono nate le regole ([sourceOf]).
  final String source;

  /// Schemi normalizzati, nell'ordine scelto dal fornitore.
  final List<String> top;
  final List<String> hide;

  /// Adulti fuori dalla Home: categorie per adulti nascoste e nessun elemento per adulti nelle righe.
  final bool hideAdult;

  /// Risultato per nome di categoria: (posizione dello schema in primo piano o -1, nascosta).
  final Map<String, (int, bool)> _memo = <String, (int, bool)>{};

  static List<String> _split(String value) =>
      [for (final part in value.split(_separators)) normalizeCategoryName(part)]..removeWhere((p) => p.isEmpty);

  bool get isEmpty => top.isEmpty && hide.isEmpty && !hideAdult;

  (int, bool) _match(String name) {
    final known = _memo[name];
    if (known != null) return known;
    final n = normalizeCategoryName(name);
    // con gli adulti fuori dalla Home una categoria per adulti conta come nascosta (una volta per nome)
    final isHidden = hide.any(n.contains) || (hideAdult && adultCat(name));
    var rank = -1;
    if (!isHidden) {
      for (var i = 0; i < top.length; i++) {
        if (n.contains(top[i])) {
          rank = i;
          break;
        }
      }
    }
    if (_memo.length > 5000) _memo.clear();
    return _memo[name] = (rank, isHidden);
  }

  /// La categoria non compare nella Home (negli elenchi va in fondo).
  bool hidden(String categoryName) => (hide.isNotEmpty || hideAdult) && _match(categoryName).$2;

  /// Posizione del primo schema in primo piano che prende la categoria (-1 = nessuno).
  int topRank(String categoryName) => top.isEmpty ? -1 : _match(categoryName).$1;

  /// Elenchi e menu delle categorie: prima quelle in primo piano (nell'ordine degli schemi, a parità
  /// nell'ordine di prima), poi le altre come sempre, in fondo le nascoste (restano raggiungibili).
  List<Category> order(List<Category> categories) {
    if (isEmpty) return categories;
    final first = <(int, int, Category)>[];
    final middle = <Category>[];
    final last = <Category>[];
    for (var i = 0; i < categories.length; i++) {
      final c = categories[i];
      final (rank, isHidden) = _match(c.name);
      if (isHidden) {
        last.add(c);
      } else if (rank >= 0) {
        first.add((rank, i, c));
      } else {
        middle.add(c);
      }
    }
    if (first.isEmpty && last.isEmpty) return categories;
    first.sort((a, b) => a.$1 != b.$1 ? a.$1.compareTo(b.$1) : a.$2.compareTo(b.$2));
    return [for (final x in first) x.$3, ...middle, ...last];
  }

  /// Righe di categoria della Home: in primo piano (TV in diretta, film, serie; al massimo [maxTop]) e poi le
  /// solite (la prima della diretta, 4 di film, 2 di serie) saltando le nascoste e quelle già in primo piano.
  HomeLayout layout(Catalog catalog) {
    final picks = <(int, int, MediaKind, Category)>[];
    if (top.isNotEmpty) {
      var n = 0;
      for (final kind in const [MediaKind.live, MediaKind.movie, MediaKind.series]) {
        for (final c in catalog.categories(kind)) {
          final rank = topRank(c.name);
          if (rank >= 0) picks.add((rank, n, kind, c));
          n++;
        }
      }
      picks.sort((a, b) => a.$1 != b.$1 ? a.$1.compareTo(b.$1) : a.$2.compareTo(b.$2));
    }
    final chosen = [for (final p in picks.take(maxTop)) (p.$3, p.$4)];
    final taken = {for (final p in chosen) '${p.$1.name}:${p.$2.id}'};
    List<Category> usual(MediaKind kind) => [
          for (final c in catalog.categories(kind))
            if (!taken.contains('${kind.name}:${c.id}') && !hidden(c.name)) c,
        ];
    final live = usual(MediaKind.live);
    return HomeLayout(
      top: chosen,
      live: live.isEmpty ? null : live.first,
      movies: usual(MediaKind.movie).take(4).toList(),
      series: usual(MediaKind.series).take(2).toList(),
    );
  }

  /// Id delle categorie nascoste di un tipo (per togliere i loro titoli dalle righe di tutti i contenuti).
  Set<String> hiddenIds(Catalog catalog, MediaKind kind) => hide.isEmpty && !hideAdult
      ? const <String>{}
      : {
          for (final c in catalog.categories(kind))
            if (hidden(c.name)) c.id,
        };

  /// Con gli adulti fuori dalla Home: l'elemento (film, serie, canale) non entra in nessuna riga della Home, perché
  /// la sua categoria è per adulti o nascosta, oppure il suo nome è un titolo per adulti. Senza filtro: mai.
  /// La categoria si valuta una volta per nome, il titolo una volta per elemento (solo per quelli delle righe).
  bool blocked(Catalog catalog, MediaItem item) =>
      hideAdult && (hidden(catalog.categoryName(item.kind, item.categoryId)) || _titleOf(item));

  /// Esito per nome di serie, per catalogo: gli episodi salvati in «Continua a guardare» hanno solo il nome della serie.
  final Expando<Map<String, bool>> _seriesByName = Expando<Map<String, bool>>('serie per nome');

  /// «Continua a guardare» senza i film e gli episodi per adulti (con gli adulti fuori dalla Home; altrimenti
  /// [entries] così com'è). Il film si cerca nel catalogo per chiave, l'episodio dalla sua serie, per nome (una sola
  /// passata sulle serie per i nomi nuovi, poi in memoria per questo catalogo). Un titolo che la copia veloce della
  /// Home non ha resta fuori finché arriva il catalogo completo; uno che non c'è più nel catalogo completo resta se il
  /// suo titolo non è per adulti.
  List<WatchProgress> resume(Catalog catalog, List<WatchProgress> entries) {
    if (!hideAdult || entries.isEmpty) return entries;
    final byName = _seriesByName[catalog] ??= <String, bool>{};
    final missing = <String>{
      for (final p in entries)
        if (p.item.kind == MediaKind.series && !byName.containsKey(p.item.title)) p.item.title,
    };
    if (missing.isNotEmpty) {
      final found = <String, bool>{};
      for (final s in catalog.series) {
        if (!missing.contains(s.name)) continue;
        // più serie con lo stesso nome: basta una per adulti
        found[s.name] = (found[s.name] ?? false) || blocked(catalog, s);
      }
      for (final name in missing) {
        byName[name] = found[name] ?? catalog.partial;
      }
    }
    bool out(PlaybackItem saved) {
      if (_savedTitleOf(saved)) return true;
      if (saved.kind == MediaKind.series) return byName[saved.title] ?? catalog.partial;
      final item = catalog.byKey(saved.key);
      return item == null ? catalog.partial : blocked(catalog, item);
    }

    return [for (final p in entries) if (!out(p.item)) p];
  }

  /// Titolo in evidenza all'apertura della Home: il primo film (poi la prima serie) aggiunto di recente che non è di
  /// una categoria nascosta e, con gli adulti fuori dalla Home, non è per adulti. Se i recenti erano tutti fuori per
  /// questo, il primo titolo che resta nelle righe di categoria della Home (prima film e serie, poi canali): il
  /// riquadro in evidenza non resta vuoto.
  MediaItem? heroPick(Catalog catalog) {
    var skipped = false;
    for (final kind in const [MediaKind.movie, MediaKind.series]) {
      for (final item in kind == MediaKind.movie ? catalog.recentMovies : catalog.recentSeries) {
        if (hidden(catalog.categoryName(kind, item.categoryId)) || blocked(catalog, item)) {
          skipped = true;
          continue;
        }
        return item;
      }
    }
    if (!hideAdult || !skipped) return null;
    final home = layout(catalog);
    final live = home.live;
    final rows = <List<MediaItem>>[
      for (final (kind, c) in home.top)
        if (kind != MediaKind.live) catalog.inCategory(kind, c.id),
      for (final c in home.movies) catalog.inCategory(MediaKind.movie, c.id),
      for (final c in home.series) catalog.inCategory(MediaKind.series, c.id),
      for (final (kind, c) in home.top)
        if (kind == MediaKind.live) catalog.inCategory(kind, c.id),
      if (live != null) catalog.inCategory(MediaKind.live, live.id),
    ];
    for (final row in rows) {
      for (final item in row) {
        if (!blocked(catalog, item)) return item;
      }
    }
    return null;
  }
}
