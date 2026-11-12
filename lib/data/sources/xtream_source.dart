import '../../core/json.dart';
import '../../core/net.dart';
import '../models.dart';
import 'content_source.dart';

/// Server Xtream Codes (player_api.php).
class XtreamSource extends ContentSource {
  XtreamSource(this.account);

  final Account account;

  String get _server => account.server ?? '';
  String get _user => account.username ?? '';
  String get _pass => account.password ?? '';

  /// Utente e password già codificati per gli indirizzi dei flussi e inizio dell'indirizzo della guida breve:
  /// l'elenco dei canali per il lettore (anche migliaia) si prepara senza ricodificarli per ogni canale.
  late final String _u = Uri.encodeComponent(_user);
  late final String _p = Uri.encodeComponent(_pass);
  late final String _epgPrefix = _api({'action': 'get_short_epg'}).toString();

  Uri _api([Map<String, String> extra = const <String, String>{}]) =>
      Uri.parse('$_server/player_api.php').replace(queryParameters: <String, String>{
        'username': _user,
        'password': _pass,
        ...extra,
      });

  @override
  bool get supportsEpg => true;

  @override
  String? get xmltvUrl => _server.isEmpty || _user.isEmpty ? null : '$_server/xmltv.php?username=$_u&password=$_p';

  /// Verifica utente e password e restituisce i dati dell'abbonamento.
  Future<AccountInfo> authenticate() async {
    final json = asMap(await fetchJson(_api(), timeout: const Duration(seconds: 20)));
    final user = asMap(json['user_info']);
    if (user.isEmpty) {
      throw const SourceException('Il server non risponde come un server Xtream: controlla l\'indirizzo');
    }
    if (asInt(user['auth']) == 0) {
      throw const SourceException('Nome utente o password non corretti');
    }
    final status = asString(user['status']);
    if (status != null && status.toLowerCase() != 'active') {
      throw SourceException('Abbonamento non attivo (stato: $status)');
    }
    return AccountInfo.fromXtream(user);
  }

  @override
  Future<Catalog> fetchCatalog() async {
    // Prima le categorie (leggere, insieme), poi i contenuti (pesanti) UNO ALLA VOLTA:
    // diretta → film → serie, ognuno convertito subito così il JSON grezzo si libera prima
    // del download successivo (tre risposte da decine di MB insieme mandano in OOM le chiavette).
    final categories = await Future.wait<Object?>([
      fetchJson(_api({'action': 'get_live_categories'})),
      fetchJson(_api({'action': 'get_vod_categories'})),
      fetchJson(_api({'action': 'get_series_categories'})),
    ]);
    const long = Duration(seconds: 90);
    final live = _parseList(await fetchJson(_api({'action': 'get_live_streams'}), timeout: long, reviver: _items(_live)));
    final movies = _parseList(await fetchJson(_api({'action': 'get_vod_streams'}), timeout: long, reviver: _items(_movie)));
    final series = _parseList(await fetchJson(_api({'action': 'get_series'}), timeout: long, reviver: _items(_series)));
    return Catalog.build(
      liveCategories: _categories(categories[0]),
      movieCategories: _categories(categories[1]),
      seriesCategories: _categories(categories[2]),
      live: live,
      movies: movies,
      series: series,
      fetchedAt: DateTime.now().millisecondsSinceEpoch,
    );
  }

  @override
  Future<MovieDetails?> movieDetails(MediaItem movie) async {
    final json = asMap(await fetchJson(_api({'action': 'get_vod_info', 'vod_id': movie.id})));
    final info = asMap(json['info']);
    if (info.isEmpty) return null;
    return MovieDetails(
      plot: asString(info['plot']) ?? asString(info['description']),
      backdrop: firstString(info['backdrop_path']),
      image: asString(info['movie_image']) ?? asString(info['cover_big']),
      cast: asString(info['cast']) ?? asString(info['actors']),
      director: asString(info['director']),
      genre: asString(info['genre']),
      year: _year(asString(info['releasedate']) ?? asString(info['release_date'])),
      rating: _rating(info),
      durationSecs: asInt(info['duration_secs']),
      trailer: asString(info['youtube_trailer']),
    );
  }

  @override
  Future<SeriesDetails?> seriesDetails(MediaItem series) async {
    final json = asMap(await fetchJson(_api({'action': 'get_series_info', 'series_id': series.id})));
    final info = asMap(json['info']);
    final bySeason = <int, List<Episode>>{};

    void addEpisode(Object? raw, int? fallbackSeason) {
      final m = asMap(raw);
      final id = asString(m['id']);
      if (id == null) return;
      final season = asInt(m['season']) ?? fallbackSeason ?? 1;
      final number = asInt(m['episode_num']) ?? 0;
      final epInfo = asMap(m['info']);
      (bySeason[season] ??= <Episode>[]).add(Episode(
        id: id,
        season: season,
        number: number,
        title: asString(m['title']) ?? 'Episodio $number',
        extension: asString(m['container_extension']) ?? 'mp4',
        image: asString(epInfo['movie_image']),
        plot: asString(epInfo['plot']),
        durationSecs: asInt(epInfo['duration_secs']),
      ));
    }

    // Alcuni pannelli restituiscono gli episodi come mappa per stagione,
    // altri come lista di liste: gestiamo entrambi i formati.
    final episodes = json['episodes'];
    if (episodes is Map) {
      episodes.forEach((key, value) {
        final season = asInt(key);
        for (final e in asList(value)) {
          addEpisode(e, season);
        }
      });
    } else if (episodes is List) {
      for (final group in episodes) {
        if (group is List) {
          for (final e in group) {
            addEpisode(e, null);
          }
        } else {
          addEpisode(group, null);
        }
      }
    }
    for (final list in bySeason.values) {
      list.sort((a, b) => a.number.compareTo(b.number));
    }
    final seasons = bySeason.keys.toList()..sort();
    return SeriesDetails(
      seasons: seasons,
      episodes: bySeason,
      plot: asString(info['plot']),
      backdrop: firstString(info['backdrop_path']),
      cast: asString(info['cast']),
      director: asString(info['director']),
      genre: asString(info['genre']),
      year: _year(asString(info['releaseDate']) ?? asString(info['release_date'])),
      rating: _rating(info),
      trailer: asString(info['youtube_trailer']),
    );
  }

  @override
  Future<List<EpgEntry>> shortEpg(MediaItem channel) async {
    final json = asMap(await fetchJson(
      _api({'action': 'get_short_epg', 'stream_id': channel.id, 'limit': '4'}),
      timeout: const Duration(seconds: 10),
    ));
    final result = <EpgEntry>[];
    for (final raw in asList(json['epg_listings'])) {
      final m = asMap(raw);
      final title = decodeBase64Text(asString(m['title']));
      if (title.isEmpty) continue;
      result.add(EpgEntry(
        title: title,
        description: decodeBase64Text(asString(m['description'])),
        start: _epoch(m['start_timestamp']) ?? _date(asString(m['start'])),
        end: _epoch(m['stop_timestamp']) ?? _date(asString(m['end']) ?? asString(m['stop'])),
      ));
    }
    return result;
  }

  /// Stesso indirizzo di `_api({'action': 'get_short_epg', 'stream_id': id, 'limit': '4'})`, con l'inizio già pronto.
  @override
  String? epgUrlFor(MediaItem channel) {
    final id = channel.id;
    return '$_epgPrefix&stream_id${id.isEmpty ? '' : '=${Uri.encodeQueryComponent(id)}'}&limit=4';
  }

  @override
  String urlFor(MediaItem item, {String liveFormat = 'ts'}) {
    switch (item.kind) {
      case MediaKind.live:
        return '$_server/live/$_u/$_p/${item.id}.$liveFormat';
      case MediaKind.movie:
        return '$_server/movie/$_u/$_p/${item.id}.${item.extension ?? 'mp4'}';
      case MediaKind.series:
        return '';
    }
  }

  @override
  String episodeUrl(Episode episode) => '$_server/series/$_u/$_p/${episode.id}.${episode.extension ?? 'mp4'}';

  /// Ripulisce l'indirizzo scritto dall'utente: aggiunge http:// se manca
  /// e toglie eventuali percorsi (es. /player_api.php).
  static String normalizeServer(String input) {
    var s = input.trim();
    if (s.isEmpty) return s;
    if (!s.contains('://')) s = 'http://$s';
    final uri = Uri.tryParse(s);
    if (uri == null || uri.host.isEmpty) return s;
    final port = uri.hasPort ? ':${uri.port}' : '';
    return '${uri.scheme}://${uri.host}$port';
  }

  /// Se l'utente incolla il link M3U di un server Xtream (get.php?username=…)
  /// ricaviamo server, utente e password: con le API i dati sono molto più ricchi.
  static Account? accountFromM3uUrl(String url) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || uri.host.isEmpty || !uri.path.endsWith('get.php')) return null;
    final user = uri.queryParameters['username'];
    final pass = uri.queryParameters['password'];
    if (user == null || pass == null || user.isEmpty || pass.isEmpty) return null;
    final port = uri.hasPort ? ':${uri.port}' : '';
    return Account(
      type: AccountType.xtream,
      server: '${uri.scheme}://${uri.host}$port',
      username: user,
      password: pass,
    );
  }

  static List<Category> _categories(Object? json) {
    final result = <Category>[];
    for (final raw in asList(json)) {
      final m = asMap(raw);
      final id = asString(m['category_id']);
      if (id == null) continue;
      result.add(Category(id: id, name: asString(m['category_name']) ?? 'Senza nome'));
    }
    return result;
  }

  /// Elenchi grandi (decine di migliaia di voci): ogni voce, appena letta, diventa un [MediaItem] (o null se
  /// non è valida), così il JSON grezzo dell'elenco non resta mai tutto in memoria. Le voci sono gli oggetti
  /// dentro un elenco; tutti gli altri valori restano come sono.
  static Object? Function(Object? key, Object? value) _items(MediaItem? Function(Map<String, dynamic>) parse) =>
      (key, value) => key is int && value is Map<String, dynamic> ? parse(value) : value;

  /// Le voci già convertite da [_items], nell'ordine del server (quelle non valide sono saltate).
  static List<MediaItem> _parseList(Object? json) {
    final result = <MediaItem>[];
    for (final raw in asList(json)) {
      if (raw is MediaItem) result.add(raw);
    }
    return result;
  }

  static MediaItem? _live(Map<String, dynamic> m) {
    final id = asString(m['stream_id']);
    final name = asString(m['name']);
    if (id == null || name == null) return null;
    return MediaItem(
      kind: MediaKind.live,
      id: id,
      name: name,
      categoryId: asString(m['category_id']) ?? uncategorizedId,
      image: asString(m['stream_icon']),
      epgId: asString(m['epg_channel_id']),
      number: asInt(m['num']),
      added: asInt(m['added']) ?? 0,
    );
  }

  static MediaItem? _movie(Map<String, dynamic> m) {
    final id = asString(m['stream_id']);
    final name = asString(m['name']);
    if (id == null || name == null) return null;
    return MediaItem(
      kind: MediaKind.movie,
      id: id,
      name: name,
      categoryId: asString(m['category_id']) ?? uncategorizedId,
      image: asString(m['stream_icon']),
      plot: asString(m['plot']),
      genre: asString(m['genre']),
      rating: _rating(m),
      year: asString(m['year']) ?? yearFromTitle(name),
      added: asInt(m['added']) ?? 0,
      extension: asString(m['container_extension']) ?? 'mp4',
    );
  }

  static MediaItem? _series(Map<String, dynamic> m) {
    final id = asString(m['series_id']);
    final name = asString(m['name']);
    if (id == null || name == null) return null;
    return MediaItem(
      kind: MediaKind.series,
      id: id,
      name: name,
      categoryId: asString(m['category_id']) ?? uncategorizedId,
      image: asString(m['cover']),
      backdrop: firstString(m['backdrop_path']),
      plot: asString(m['plot']),
      genre: asString(m['genre']),
      rating: _rating(m),
      year: _year(asString(m['releaseDate']) ?? asString(m['release_date'])) ?? yearFromTitle(name),
      added: asInt(m['last_modified']) ?? 0,
    );
  }

  static double? _rating(Map<String, dynamic> m) {
    final r = asDouble(m['rating']);
    if (r != null && r > 0) return r > 10 ? r / 10 : r;
    final r5 = asDouble(m['rating_5based']);
    if (r5 != null && r5 > 0) return r5 * 2;
    return null;
  }

  static String? _year(String? date) => date != null && date.length >= 4 ? date.substring(0, 4) : null;

  static DateTime? _epoch(Object? value) {
    final s = asInt(value);
    return s == null || s <= 0 ? null : DateTime.fromMillisecondsSinceEpoch(s * 1000);
  }

  static DateTime? _date(String? value) => value == null ? null : DateTime.tryParse(value.replaceFirst(' ', 'T'));
}
