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
class HomeRules {
  HomeRules._(this.source, this.top, this.hide);

  factory HomeRules.parse(String top, String hide) => HomeRules._('$top\n$hide', _split(top), _split(hide));

  /// Nessuna regola: Home ed elenchi come sempre.
  static final HomeRules none = HomeRules.parse('', '');

  /// Al massimo tante righe in primo piano nella Home.
  static const int maxTop = 10;

  /// Testo da cui sono nate le regole (per accorgersi quando il pannello le cambia).
  final String source;

  /// Schemi normalizzati, nell'ordine scelto dal fornitore.
  final List<String> top;
  final List<String> hide;

  /// Risultato per nome di categoria: (posizione dello schema in primo piano o -1, nascosta).
  final Map<String, (int, bool)> _memo = <String, (int, bool)>{};

  static List<String> _split(String value) =>
      [for (final part in value.split(_separators)) normalizeCategoryName(part)]..removeWhere((p) => p.isEmpty);

  bool get isEmpty => top.isEmpty && hide.isEmpty;

  (int, bool) _match(String name) {
    final known = _memo[name];
    if (known != null) return known;
    final n = normalizeCategoryName(name);
    final isHidden = hide.any(n.contains);
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
  bool hidden(String categoryName) => hide.isNotEmpty && _match(categoryName).$2;

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
  Set<String> hiddenIds(Catalog catalog, MediaKind kind) => hide.isEmpty
      ? const <String>{}
      : {
          for (final c in catalog.categories(kind))
            if (hidden(c.name)) c.id,
        };
}
