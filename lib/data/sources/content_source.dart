import '../models.dart';
import 'demo_source.dart';
import 'm3u_source.dart';
import 'xtream_source.dart';

/// Da dove arrivano i contenuti. L'interfaccia non sa (e non deve sapere)
/// se dietro c'è un server Xtream, una lista M3U o la demo.
abstract class ContentSource {
  const ContentSource();

  factory ContentSource.of(Account account) => switch (account.type) {
        AccountType.xtream => XtreamSource(account),
        AccountType.m3u => M3uSource(account.m3uUrl ?? ''),
        AccountType.demo => const DemoSource(),
      };

  Future<Catalog> fetchCatalog();

  Future<MovieDetails?> movieDetails(MediaItem movie) async => null;

  Future<SeriesDetails?> seriesDetails(MediaItem series) async => null;

  Future<List<EpgEntry>> shortEpg(MediaItem channel) async => const <EpgEntry>[];

  bool get supportsEpg => false;

  String urlFor(MediaItem item, {String liveFormat = 'ts'});

  String episodeUrl(Episode episode) => episode.url ?? '';
}
