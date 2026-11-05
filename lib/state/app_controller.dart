import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/net.dart';
import '../data/catalog_repository.dart';
import '../data/models.dart';
import '../data/sources/content_source.dart';
import '../data/sources/xtream_source.dart';
import '../data/user_store.dart';

enum SessionStatus { starting, loggedOut, loading, ready, error }

/// Stato dell'app. Ogni informazione ha il suo "canale" di notifica
/// (catalogo, preferiti, progressi…): una schermata si ridisegna solo
/// quando cambia ciò che mostra davvero.
class AppController {
  final UserStore _store = UserStore();

  final ValueNotifier<SessionStatus> status = ValueNotifier(SessionStatus.starting);
  final ValueNotifier<Catalog?> catalog = ValueNotifier(null);
  final ValueNotifier<AccountInfo?> accountInfo = ValueNotifier(null);
  final ValueNotifier<String> liveFormat = ValueNotifier('ts');
  final ValueNotifier<int> favoritesRevision = ValueNotifier(0);
  final ValueNotifier<int> progressRevision = ValueNotifier(0);

  Set<String> _favorites = <String>{};
  Map<String, WatchProgress> _progress = <String, WatchProgress>{};
  Account? _account;
  ContentSource? _source;

  /// Messaggio da mostrare se all'avvio il catalogo non si è potuto caricare.
  String? startupError;

  final Map<String, (DateTime, List<EpgEntry>)> _epgCache = {};
  final Map<String, Future<MovieDetails?>> _movieDetails = {};
  final Map<String, Future<SeriesDetails?>> _seriesDetails = {};

  Account? get account => _account;
  bool get supportsEpg => _source?.supportsEpg ?? false;

  // ---------------------------------------------------------------------------
  // Avvio, accesso e catalogo

  Future<void> start() async {
    _favorites = await _store.loadFavorites();
    _progress = await _store.loadProgress();
    liveFormat.value = await _store.loadLiveFormat();
    final account = await _store.loadAccount();
    if (account == null) {
      status.value = SessionStatus.loggedOut;
      return;
    }
    _useAccount(account);

    // Prima la cache: l'app si apre subito con i dati dell'ultima volta.
    final cached = await CatalogRepository.readCache();
    if (cached != null && !cached.isEmpty) {
      catalog.value = cached;
      status.value = SessionStatus.ready;
      if (cached.isStale) unawaited(_refreshInBackground());
    } else {
      status.value = SessionStatus.loading;
      final error = await _fetchAndApply();
      if (error != null) {
        startupError = error;
        status.value = SessionStatus.error;
        return;
      }
      status.value = SessionStatus.ready;
    }
    unawaited(_loadAccountInfo());
  }

  Future<void> retryStartup() async {
    status.value = SessionStatus.loading;
    final error = await _fetchAndApply();
    if (error != null) {
      startupError = error;
      status.value = SessionStatus.error;
      return;
    }
    status.value = SessionStatus.ready;
    unawaited(_loadAccountInfo());
  }

  /// Restituisce null se l'accesso è riuscito, altrimenti il messaggio d'errore.
  Future<String?> login(Account account) async {
    try {
      AccountInfo? info;
      if (account.type == AccountType.xtream) {
        info = await XtreamSource(account).authenticate();
      }
      final fresh = await CatalogRepository.fetch(account);
      if (fresh.isEmpty) return 'Nessun contenuto trovato per questo account';
      await _store.saveAccount(account);
      _useAccount(account);
      accountInfo.value = info;
      catalog.value = fresh;
      startupError = null;
      status.value = SessionStatus.ready;
      return null;
    } on SourceException catch (e) {
      return e.message;
    } on Object catch (e) {
      return 'Errore inatteso: $e';
    }
  }

  /// Aggiornamento chiesto dall'utente: le novità si vedono subito.
  Future<String?> refreshCatalog() => _fetchAndApply();

  Future<void> logout() async {
    await _store.saveAccount(null);
    await _store.clearUserData();
    await CatalogRepository.clearCache();
    _account = null;
    _source = null;
    _favorites = <String>{};
    _progress = <String, WatchProgress>{};
    catalog.value = null;
    accountInfo.value = null;
    favoritesRevision.value++;
    progressRevision.value++;
    status.value = SessionStatus.loggedOut;
  }

  void _useAccount(Account account) {
    _account = account;
    _source = ContentSource.of(account);
    _epgCache.clear();
    _movieDetails.clear();
    _seriesDetails.clear();
  }

  Future<String?> _fetchAndApply() async {
    final account = _account;
    if (account == null) return 'Nessun account configurato';
    try {
      final fresh = await CatalogRepository.fetch(account);
      if (fresh.isEmpty) return 'Il server non ha restituito contenuti';
      catalog.value = fresh;
      return null;
    } on SourceException catch (e) {
      return e.message;
    } on Object catch (e) {
      return 'Errore inatteso: $e';
    }
  }

  /// Aggiorna la cache su disco senza toccare quello che l'utente sta
  /// guardando: le novità compaiono al prossimo avvio, senza salti di focus.
  Future<void> _refreshInBackground() async {
    final account = _account;
    if (account == null) return;
    try {
      await CatalogRepository.fetch(account);
    } on Object {
      // silenzioso: il catalogo in cache resta valido
    }
  }

  Future<void> _loadAccountInfo() async {
    final account = _account;
    if (account == null || account.type != AccountType.xtream) return;
    try {
      accountInfo.value = await XtreamSource(account).authenticate();
    } on Object {
      // informazioni facoltative
    }
  }

  // ---------------------------------------------------------------------------
  // Preferiti

  bool isFavorite(MediaItem item) => _favorites.contains(item.key);

  void toggleFavorite(MediaItem item) {
    if (!_favorites.remove(item.key)) _favorites.add(item.key);
    favoritesRevision.value++;
    unawaited(_store.saveFavorites(_favorites));
  }

  List<MediaItem> favoriteItems(MediaKind kind) {
    final c = catalog.value;
    if (c == null) return const <MediaItem>[];
    final result = <MediaItem>[];
    for (final key in _favorites) {
      final item = c.byKey(key);
      if (item != null && item.kind == kind) result.add(item);
    }
    return result;
  }

  // ---------------------------------------------------------------------------
  // Progressi ("Continua a guardare")

  WatchProgress? progressFor(String key) => _progress[key];

  List<WatchProgress> continueWatching() =>
      _progress.values.toList()..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  /// [notify] a false durante la riproduzione: si salva su disco senza
  /// ridisegnare le schermate sotto al player.
  void saveProgress(PlaybackItem item, Duration position, Duration duration, {bool notify = true}) {
    if (item.isLive || duration.inSeconds < 60) return;
    final fraction = position.inMilliseconds / duration.inMilliseconds;
    if (fraction > 0.95 || position.inSeconds < 15) {
      _progress.remove(item.key); // finito o appena iniziato
    } else {
      _progress[item.key] = WatchProgress(
        item: item,
        positionMs: position.inMilliseconds,
        durationMs: duration.inMilliseconds,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );
    }
    if (_progress.length > 40) {
      final keep = continueWatching().take(40).toList();
      _progress = {for (final p in keep) p.item.key: p};
    }
    unawaited(_store.saveProgress(_progress.values));
    if (notify) progressRevision.value++;
  }

  // ---------------------------------------------------------------------------
  // Dettagli e guida TV (con cache in memoria)

  Future<MovieDetails?> movieDetails(MediaItem movie) {
    final source = _source;
    if (source == null) return Future<MovieDetails?>.value(null);
    return _movieDetails.putIfAbsent(movie.id, () async {
      try {
        return await source.movieDetails(movie);
      } on Object {
        _movieDetails.remove(movie.id); // si riproverà la prossima volta
        return null;
      }
    });
  }

  Future<SeriesDetails?> seriesDetails(MediaItem series) {
    final source = _source;
    if (source == null) return Future<SeriesDetails?>.value(null);
    return _seriesDetails.putIfAbsent(series.id, () async {
      try {
        return await source.seriesDetails(series);
      } on Object {
        _seriesDetails.remove(series.id);
        return null;
      }
    });
  }

  Future<List<EpgEntry>> epgFor(MediaItem channel) async {
    final source = _source;
    if (source == null || !source.supportsEpg) return const <EpgEntry>[];
    final now = DateTime.now();
    final cached = _epgCache[channel.id];
    if (cached != null && now.difference(cached.$1) < const Duration(minutes: 5)) return cached.$2;
    try {
      final list = await source.shortEpg(channel);
      _epgCache[channel.id] = (now, list);
      return list;
    } on Object {
      return const <EpgEntry>[];
    }
  }

  // ---------------------------------------------------------------------------
  // Riproduzione

  Future<void> setLiveFormat(String format) async {
    liveFormat.value = format;
    await _store.saveLiveFormat(format);
  }

  String urlFor(MediaItem item) => _source?.urlFor(item, liveFormat: liveFormat.value) ?? '';

  PlaybackItem playbackForChannel(MediaItem channel) => PlaybackItem(
        key: channel.key,
        title: channel.name,
        subtitle: channel.number == null ? null : 'Canale ${channel.number}',
        url: urlFor(channel),
        image: channel.image,
        isLive: true,
        channel: channel,
      );

  List<PlaybackItem> livePlaylist(List<MediaItem> channels) =>
      [for (final c in channels) playbackForChannel(c)];

  PlaybackItem playbackForMovie(MediaItem movie) => PlaybackItem(
        key: movie.key,
        title: movie.name,
        subtitle: movie.year,
        url: urlFor(movie),
        image: movie.backdrop ?? movie.image,
      );

  PlaybackItem playbackForEpisode(MediaItem series, Episode episode) => PlaybackItem(
        key: episode.key,
        title: series.name,
        subtitle: 'S${episode.season} E${episode.number} · ${episode.title}',
        url: _source?.episodeUrl(episode) ?? '',
        image: episode.image ?? series.backdrop ?? series.image,
      );

  void dispose() {
    status.dispose();
    catalog.dispose();
    accountInfo.dispose();
    liveFormat.dispose();
    favoritesRevision.dispose();
    progressRevision.dispose();
  }
}
