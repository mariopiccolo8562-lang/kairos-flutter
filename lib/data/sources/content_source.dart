import '../models.dart';
import 'm3u_source.dart';
import 'xtream_source.dart';

/// Da dove arrivano i contenuti. L'interfaccia non sa (e non deve sapere)
/// se dietro c'è un server Xtream o una lista M3U.
abstract class ContentSource {
  const ContentSource();

  factory ContentSource.of(Account account) => switch (account.type) {
        AccountType.xtream => XtreamSource(account),
        AccountType.m3u => M3uSource(account.m3uUrl ?? ''),
      };

  Future<Catalog> fetchCatalog();

  Future<MovieDetails?> movieDetails(MediaItem movie) async => null;

  Future<SeriesDetails?> seriesDetails(MediaItem series) async => null;

  Future<List<EpgEntry>> shortEpg(MediaItem channel) async => const <EpgEntry>[];

  bool get supportsEpg => false;

  /// Indirizzo della guida breve di un canale, letto dal lettore nativo.
  String? epgUrlFor(MediaItem channel) => null;

  String urlFor(MediaItem item, {String liveFormat = 'ts'});

  String episodeUrl(Episode episode) => episode.url ?? '';
}
