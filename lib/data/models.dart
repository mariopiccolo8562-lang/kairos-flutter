import '../core/json.dart';
import 'home_rules.dart';

enum MediaKind { live, movie, series }

enum AccountType { xtream, m3u }

const String uncategorizedId = '__altri';

final RegExp _yearPattern = RegExp(r'\((\d{4})\)');

/// Anno tra parentesi nel titolo, es. "Titolo (2021)".
String? yearFromTitle(String title) {
  final matches = _yearPattern.allMatches(title);
  if (matches.isEmpty) return null;
  return matches.last.group(1);
}

/// Contenuti per adulti: riconosciuti dal nome della categoria (e, per i titoli, dal nome stesso).
/// Stesse regole dell'app Kairos Pro, così il controllo genitori si comporta allo stesso modo.
final RegExp adultGroupRx = RegExp(
    r'(\bxxx\b|adult|adulti|\bporn|erotic|erotik|hentai|\b18\s*\+|\+\s*18\b|\bvm\s*18\b|for adults|\bsexy?\b|\bhot\s*club\b|playboy|brazzers|private\s*tv)',
    caseSensitive: false);
final RegExp adultNameRx = RegExp(r'(\bxxx\b|\bporn|hentai|brazzers|playboy\s*tv|\b18\s*\+)', caseSensitive: false);
bool isAdultText(String? s) => s != null && s.isNotEmpty && adultGroupRx.hasMatch(s);

/// Finto titolo che occupa una fila protetta dal controllo genitori: aprendolo si inserisce il PIN.
const String kPinItemId = '__pin__';

class Category {
  const Category({required this.id, required this.name});

  final String id;
  final String name;

  Map<String, Object?> toJson() => {'id': id, 'name': name};

  static Category fromJson(Object? json) {
    final m = asMap(json);
    return Category(id: asString(m['id']) ?? uncategorizedId, name: asString(m['name']) ?? 'Altri');
  }
}

/// Un canale, un film o una serie del catalogo.
class MediaItem {
  const MediaItem({
    required this.kind,
    required this.id,
    required this.name,
    required this.categoryId,
    this.image,
    this.backdrop,
    this.plot,
    this.genre,
    this.year,
    this.rating,
    this.added = 0,
    this.extension,
    this.epgId,
    this.number,
    this.url,
  });

  final MediaKind kind;
  final String id;
  final String name;
  final String categoryId;
  final String? image; // locandina o logo
  final String? backdrop; // immagine orizzontale grande
  final String? plot;
  final String? genre;
  final String? year;
  final double? rating; // 0–10
  final int added; // secondi epoch
  final String? extension; // contenitore del file (mkv, mp4…)
  final String? epgId;
  final int? number;
  final String? url; // indirizzo diretto (liste M3U)

  String get key => '${kind.name}:$id';

  Map<String, Object?> toJson() => {
        'k': kind.index,
        'id': id,
        'n': name,
        'c': categoryId,
        if (image != null) 'i': image,
        if (backdrop != null) 'b': backdrop,
        if (plot != null) 'p': plot,
        if (genre != null) 'g': genre,
        if (year != null) 'y': year,
        if (rating != null) 'r': rating,
        if (added != 0) 'a': added,
        if (extension != null) 'e': extension,
        if (epgId != null) 'epg': epgId,
        if (number != null) 'num': number,
        if (url != null) 'u': url,
      };

  static MediaItem fromJson(Object? json) {
    final m = asMap(json);
    final k = asInt(m['k']) ?? 0;
    return MediaItem(
      kind: (k < 0 || k >= MediaKind.values.length) ? MediaKind.live : MediaKind.values[k],
      id: asString(m['id']) ?? '',
      name: asString(m['n']) ?? '',
      categoryId: asString(m['c']) ?? uncategorizedId,
      image: asString(m['i']),
      backdrop: asString(m['b']),
      plot: asString(m['p']),
      genre: asString(m['g']),
      year: asString(m['y']),
      rating: asDouble(m['r']),
      added: asInt(m['a']) ?? 0,
      extension: asString(m['e']),
      epgId: asString(m['epg']),
      number: asInt(m['num']),
      url: asString(m['u']),
    );
  }
}

class Episode {
  const Episode({
    required this.id,
    required this.season,
    required this.number,
    required this.title,
    this.extension,
    this.image,
    this.plot,
    this.durationSecs,
    this.url,
  });

  final String id;
  final int season;
  final int number;
  final String title;
  final String? extension;
  final String? image;
  final String? plot;
  final int? durationSecs;
  final String? url;

  String get key => 'episode:$id';
}

class SeriesDetails {
  const SeriesDetails({
    required this.seasons,
    required this.episodes,
    this.plot,
    this.backdrop,
    this.cast,
    this.director,
    this.genre,
    this.year,
    this.rating,
  });

  final List<int> seasons;
  final Map<int, List<Episode>> episodes;
  final String? plot;
  final String? backdrop;
  final String? cast;
  final String? director;
  final String? genre;
  final String? year;
  final double? rating;
}

class MovieDetails {
  const MovieDetails({
    this.plot,
    this.backdrop,
    this.image,
    this.cast,
    this.director,
    this.genre,
    this.year,
    this.rating,
    this.durationSecs,
  });

  final String? plot;
  final String? backdrop;
  final String? image;
  final String? cast;
  final String? director;
  final String? genre;
  final String? year;
  final double? rating;
  final int? durationSecs;
}

class EpgEntry {
  const EpgEntry({required this.title, this.description, this.start, this.end});

  final String title;
  final String? description;
  final DateTime? start;
  final DateTime? end;

  double progress(DateTime now) {
    final s = start;
    final e = end;
    if (s == null || e == null || !e.isAfter(s)) return 0;
    final total = e.difference(s).inSeconds;
    final done = now.difference(s).inSeconds;
    return (done / total).clamp(0.0, 1.0).toDouble();
  }
}

/// Programma in onda adesso e quello successivo.
(EpgEntry?, EpgEntry?) currentAndNext(List<EpgEntry> list, DateTime now) {
  if (list.isEmpty) return (null, null);
  for (var i = 0; i < list.length; i++) {
    final e = list[i];
    final s = e.start;
    final end = e.end;
    if (s != null && end != null && !now.isBefore(s) && now.isBefore(end)) {
      return (e, i + 1 < list.length ? list[i + 1] : null);
    }
  }
  return (list.first, list.length > 1 ? list[1] : null);
}

class Account {
  const Account({required this.type, this.server, this.username, this.password, this.m3uUrl});

  final AccountType type;
  final String? server;
  final String? username;
  final String? password;
  final String? m3uUrl;

  Map<String, Object?> toJson() => {
        'type': type.name,
        'server': server,
        'username': username,
        'password': password,
        'm3u': m3uUrl,
      };

  static Account? fromJson(Object? json) {
    final m = asMap(json);
    final typeName = asString(m['type']);
    AccountType? type;
    for (final t in AccountType.values) {
      if (t.name == typeName) type = t;
    }
    if (type == null) return null;
    return Account(
      type: type,
      server: asString(m['server']),
      username: asString(m['username']),
      password: asString(m['password']),
      m3uUrl: asString(m['m3u']),
    );
  }
}

/// Dati dell'abbonamento restituiti da un server Xtream.
class AccountInfo {
  const AccountInfo({
    this.status,
    this.expiresAt,
    this.maxConnections,
    this.activeConnections,
    this.isTrial = false,
  });

  final String? status;
  final DateTime? expiresAt;
  final int? maxConnections;
  final int? activeConnections;
  final bool isTrial;

  static AccountInfo fromXtream(Map<String, dynamic> m) {
    final exp = asInt(m['exp_date']);
    return AccountInfo(
      status: asString(m['status']),
      expiresAt: exp == null || exp <= 0 ? null : DateTime.fromMillisecondsSinceEpoch(exp * 1000),
      maxConnections: asInt(m['max_connections']),
      activeConnections: asInt(m['active_cons']),
      isTrial: asString(m['is_trial']) == '1',
    );
  }
}

/// Quello che il lettore deve riprodurre.
class PlaybackItem {
  const PlaybackItem({
    required this.key,
    required this.title,
    required this.url,
    this.subtitle,
    this.image,
    this.isLive = false,
    this.kind = MediaKind.movie,
    this.channel,
    this.altUrls = const <String>[],
    this.epgUrl,
    this.group,
  });

  final String key;
  final String title;
  final String url;
  final String? subtitle;
  final String? image;
  final bool isLive;
  final MediaKind kind;

  /// Solo per i canali: numero, guida TV, categoria.
  final MediaItem? channel;

  /// Indirizzi alternativi (es. lo stesso canale in HLS e in MPEG-TS).
  final List<String> altUrls;
  final String? epgUrl;
  final String? group;

  /// Stato per il pannello (Online ora): live, movie, series.
  String get watchState => switch (kind) {
        MediaKind.live => 'live',
        MediaKind.movie => 'movie',
        MediaKind.series => 'series',
      };

  /// Dati per il lettore nativo.
  Map<String, Object?> toPlayerJson() => {
        'key': key,
        'title': title,
        'sub': subtitle ?? '',
        'url': url,
        'alt': altUrls,
        'live': isLive,
        'kind': watchState,
        'num': channel?.number ?? 0,
        'epg': epgUrl ?? '',
        'group': group ?? '',
        'chId': channel?.id ?? '',
      };

  Map<String, Object?> toJson() => {
        'key': key,
        'title': title,
        'url': url,
        'kind': kind.index,
        if (subtitle != null) 'subtitle': subtitle,
        if (image != null) 'image': image,
      };

  static PlaybackItem? fromJson(Object? json) {
    final m = asMap(json);
    final key = asString(m['key']);
    final title = asString(m['title']);
    final url = asString(m['url']);
    if (key == null || title == null || url == null) return null;
    final k = asInt(m['kind']);
    return PlaybackItem(
      key: key,
      title: title,
      url: url,
      subtitle: asString(m['subtitle']),
      image: asString(m['image']),
      kind: k != null && k >= 0 && k < MediaKind.values.length
          ? MediaKind.values[k]
          : (key.startsWith('episode:') ? MediaKind.series : MediaKind.movie),
    );
  }
}

/// Punto in cui l'utente ha interrotto un film o un episodio.
class WatchProgress {
  const WatchProgress({
    required this.item,
    required this.positionMs,
    required this.durationMs,
    required this.updatedAt,
  });

  final PlaybackItem item;
  final int positionMs;
  final int durationMs;
  final int updatedAt;

  Duration get position => Duration(milliseconds: positionMs);

  double get fraction => durationMs <= 0 ? 0 : (positionMs / durationMs).clamp(0.0, 1.0).toDouble();

  Map<String, Object?> toJson() => {
        'item': item.toJson(),
        'pos': positionMs,
        'dur': durationMs,
        'at': updatedAt,
      };

  static WatchProgress? fromJson(Object? json) {
    final m = asMap(json);
    final item = PlaybackItem.fromJson(m['item']);
    if (item == null) return null;
    return WatchProgress(
      item: item,
      positionMs: asInt(m['pos']) ?? 0,
      durationMs: asInt(m['dur']) ?? 0,
      updatedAt: asInt(m['at']) ?? 0,
    );
  }
}

/// L'intero catalogo, già diviso per categorie e pronto per la ricerca.
///
/// Viene costruito in un isolate separato: con decine di migliaia di titoli
/// raggruppare e ordinare richiede tempo, e l'interfaccia non deve aspettare.
class Catalog {
  Catalog._(
    this._byKey,
    this._liveKeys,
    this._movieKeys,
    this._seriesKeys, {
    required this.liveCategories,
    required this.movieCategories,
    required this.seriesCategories,
    required this.live,
    required this.movies,
    required this.series,
    required this.liveByCategory,
    required this.moviesByCategory,
    required this.seriesByCategory,
    required this.recentMovies,
    required this.recentSeries,
    required this.fetchedAt,
    this.partial = false,
  });

  factory Catalog.build({
    required List<Category> liveCategories,
    required List<Category> movieCategories,
    required List<Category> seriesCategories,
    required List<MediaItem> live,
    required List<MediaItem> movies,
    required List<MediaItem> series,
    required int fetchedAt,
    bool partial = false,
  }) {
    final liveGroups = _group(live);
    final movieGroups = _group(movies);
    final seriesGroups = _group(series);
    final byKey = <String, MediaItem>{};
    for (final item in live) {
      byKey[item.key] = item;
    }
    for (final item in movies) {
      byKey[item.key] = item;
    }
    for (final item in series) {
      byKey[item.key] = item;
    }
    return Catalog._(
      byKey,
      _searchKeys(live),
      _searchKeys(movies),
      _searchKeys(series),
      liveCategories: _withGroups(liveCategories, liveGroups),
      movieCategories: _withGroups(movieCategories, movieGroups),
      seriesCategories: _withGroups(seriesCategories, seriesGroups),
      live: live,
      movies: movies,
      series: series,
      liveByCategory: liveGroups,
      moviesByCategory: movieGroups,
      seriesByCategory: seriesGroups,
      recentMovies: _recent(movies, 40),
      recentSeries: _recent(series, 40),
      fetchedAt: fetchedAt,
      partial: partial,
    );
  }

  /// Solo una parte del catalogo (quella della Home, per aprire subito l'app):
  /// il resto sta arrivando.
  final bool partial;

  /// Piccola parte del catalogo per aprire subito la Home all'avvio (novità,
  /// categorie della Home, preferiti); il catalogo completo arriva subito dopo.
  /// [rules]: Home decisa dal pannello (categorie in primo piano e nascoste).
  Catalog homeSnapshot(Iterable<String> favoriteKeys, {HomeRules? rules}) {
    const perCategory = 80;
    final keys = <String>{};
    void addAll(Iterable<MediaItem> items) {
      for (final item in items) {
        keys.add(item.key);
      }
    }

    addAll(recentMovies);
    addAll(recentSeries);
    final home = (rules ?? HomeRules.none).layout(this);
    for (final (kind, c) in home.top) {
      addAll(inCategory(kind, c.id).take(perCategory));
    }
    final firstLive = home.live;
    if (firstLive != null) addAll(inCategory(MediaKind.live, firstLive.id).take(perCategory));
    for (final c in home.movies) {
      addAll(inCategory(MediaKind.movie, c.id).take(perCategory));
    }
    for (final c in home.series) {
      addAll(inCategory(MediaKind.series, c.id).take(perCategory));
    }
    for (final key in favoriteKeys) {
      if (_byKey.containsKey(key)) keys.add(key);
    }
    List<MediaItem> pick(List<MediaItem> items) => [
          for (final item in items)
            if (keys.contains(item.key)) item,
        ];
    return Catalog.build(
      liveCategories: liveCategories,
      movieCategories: movieCategories,
      seriesCategories: seriesCategories,
      live: pick(live),
      movies: pick(movies),
      series: pick(series),
      fetchedAt: fetchedAt,
      partial: true,
    );
  }

  final List<Category> liveCategories;
  final List<Category> movieCategories;
  final List<Category> seriesCategories;
  final List<MediaItem> live;
  final List<MediaItem> movies;
  final List<MediaItem> series;
  final Map<String, List<MediaItem>> liveByCategory;
  final Map<String, List<MediaItem>> moviesByCategory;
  final Map<String, List<MediaItem>> seriesByCategory;
  final List<MediaItem> recentMovies;
  final List<MediaItem> recentSeries;
  final int fetchedAt; // millisecondi epoch
  final Map<String, MediaItem> _byKey;
  final List<String> _liveKeys;
  final List<String> _movieKeys;
  final List<String> _seriesKeys;

  bool get isEmpty => live.isEmpty && movies.isEmpty && series.isEmpty;

  bool get isStale =>
      DateTime.now().millisecondsSinceEpoch - fetchedAt > const Duration(hours: 12).inMilliseconds;

  List<MediaItem> items(MediaKind kind) => switch (kind) {
        MediaKind.live => live,
        MediaKind.movie => movies,
        MediaKind.series => series,
      };

  List<Category> categories(MediaKind kind) => switch (kind) {
        MediaKind.live => liveCategories,
        MediaKind.movie => movieCategories,
        MediaKind.series => seriesCategories,
      };

  List<MediaItem> inCategory(MediaKind kind, String categoryId) {
    final groups = switch (kind) {
      MediaKind.live => liveByCategory,
      MediaKind.movie => moviesByCategory,
      MediaKind.series => seriesByCategory,
    };
    return groups[categoryId] ?? const <MediaItem>[];
  }

  final Map<String, bool> _adultCat = <String, bool>{};
  /// Categoria per adulti (dal nome): il controllo genitori la protegge con il PIN.
  bool isAdultCategory(MediaKind kind, String categoryId) =>
      _adultCat.putIfAbsent('${kind.name}|$categoryId', () => isAdultText(categoryName(kind, categoryId)));
  /// Titolo o canale per adulti: categoria per adulti, oppure nome esplicito.
  bool isAdult(MediaItem x) => isAdultCategory(x.kind, x.categoryId) || adultNameRx.hasMatch(x.name);

  String categoryName(MediaKind kind, String categoryId) {
    for (final c in categories(kind)) {
      if (c.id == categoryId) return c.name;
    }
    return '';
  }

  MediaItem? byKey(String key) => _byKey[key];

  List<MediaItem> search(MediaKind kind, String query, {int limit = 60}) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const <MediaItem>[];
    final keys = switch (kind) {
      MediaKind.live => _liveKeys,
      MediaKind.movie => _movieKeys,
      MediaKind.series => _seriesKeys,
    };
    final source = items(kind);
    final result = <MediaItem>[];
    for (var i = 0; i < keys.length && result.length < limit; i++) {
      if (keys[i].contains(q)) result.add(source[i]);
    }
    return result;
  }

  Map<String, Object?> toJson() => {
        'v': 1,
        't': fetchedAt,
        if (partial) 'partial': 1,
        'lc': [for (final c in liveCategories) c.toJson()],
        'mc': [for (final c in movieCategories) c.toJson()],
        'sc': [for (final c in seriesCategories) c.toJson()],
        'l': [for (final i in live) i.toJson()],
        'm': [for (final i in movies) i.toJson()],
        's': [for (final i in series) i.toJson()],
      };

  static Catalog fromJson(Object? json) {
    final m = asMap(json);
    List<Category> cats(String key) => [for (final c in asList(m[key])) Category.fromJson(c)];
    List<MediaItem> list(String key) => [for (final i in asList(m[key])) MediaItem.fromJson(i)];
    return Catalog.build(
      liveCategories: cats('lc'),
      movieCategories: cats('mc'),
      seriesCategories: cats('sc'),
      live: list('l'),
      movies: list('m'),
      series: list('s'),
      fetchedAt: asInt(m['t']) ?? 0,
      partial: asInt(m['partial']) == 1,
    );
  }

  static Map<String, List<MediaItem>> _group(List<MediaItem> items) {
    final map = <String, List<MediaItem>>{};
    for (final item in items) {
      (map[item.categoryId] ??= <MediaItem>[]).add(item);
    }
    return map;
  }

  /// Tiene solo le categorie con contenuti e aggiunge quelle mancanti.
  static List<Category> _withGroups(List<Category> categories, Map<String, List<MediaItem>> groups) {
    final seen = <String>{};
    final result = <Category>[];
    for (final c in categories) {
      if (groups.containsKey(c.id) && seen.add(c.id)) result.add(c);
    }
    for (final id in groups.keys) {
      if (seen.add(id)) result.add(Category(id: id, name: 'Altri'));
    }
    return result;
  }

  static List<MediaItem> _recent(List<MediaItem> items, int count) {
    if (items.isEmpty) return const <MediaItem>[];
    var hasDates = false;
    for (final item in items) {
      if (item.added != 0) {
        hasDates = true;
        break;
      }
    }
    if (!hasDates) return items.take(count).toList();
    final sorted = List<MediaItem>.of(items)..sort((a, b) => b.added.compareTo(a.added));
    return sorted.take(count).toList();
  }

  static List<String> _searchKeys(List<MediaItem> items) => [for (final i in items) i.name.toLowerCase()];
}
