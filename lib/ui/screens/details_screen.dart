import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/brand.dart';
import '../../app/theme.dart';
import '../../core/format.dart';
import '../../data/models.dart';
import '../../state/app_controller.dart';
import '../navigation.dart';
import '../widgets/cards.dart';
import '../widgets/content_row.dart';
import '../widgets/net_image.dart';
import '../widgets/tv_button.dart';

/// Scheda di un film o di una serie: sfondo grande, trama, pulsanti ed episodi.
class DetailsScreen extends StatefulWidget {
  const DetailsScreen({super.key, required this.item});

  final MediaItem item;

  @override
  State<DetailsScreen> createState() => _DetailsScreenState();
}

class _DetailsScreenState extends State<DetailsScreen> {
  late final AppController _app;
  late final Future<MovieDetails?> _movie;
  late final Future<SeriesDetails?> _series;
  int _seasonIndex = 0;

  /// Trailer trovato (della linea o cercato dal pannello): il pulsante compare solo quando c'è.
  TrailerRef? _trailer;

  bool get _isSeries => widget.item.kind == MediaKind.series;

  /// Cerca il trailer in sottofondo, quando la scheda del server è arrivata (anche se è vuota).
  Future<void> _findTrailer() async {
    String? year = widget.item.year;
    String? line;
    try {
      if (_isSeries) {
        final d = await _series;
        year ??= d?.year;
        line = d?.trailer;
      } else {
        final d = await _movie;
        year ??= d?.year;
        line = d?.trailer;
      }
    } on Object {
      line = null;
    }
    final found = await _app.trailerFor(widget.item, year: year, lineValue: line);
    if (found != null && mounted) setState(() => _trailer = found);
  }

  @override
  void initState() {
    super.initState();
    _app = AppScope.of(context);
    _movie = _isSeries ? Future<MovieDetails?>.value(null) : _app.movieDetails(widget.item);
    _series = _isSeries ? _app.seriesDetails(widget.item) : Future<SeriesDetails?>.value(null);
    _findTrailer();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _isSeries
          ? FutureBuilder<SeriesDetails?>(
              future: _series,
              builder: (context, snapshot) => _layout(
                context,
                series: snapshot.data,
                loading: snapshot.connectionState != ConnectionState.done,
              ),
            )
          : FutureBuilder<MovieDetails?>(
              future: _movie,
              builder: (context, snapshot) => _layout(
                context,
                movie: snapshot.data,
                loading: snapshot.connectionState != ConnectionState.done,
              ),
            ),
    );
  }

  Widget _layout(BuildContext context, {MovieDetails? movie, SeriesDetails? series, required bool loading}) {
    final item = widget.item;
    final backdrop = series?.backdrop ?? movie?.backdrop ?? item.backdrop ?? movie?.image ?? item.image;
    final itemPlot = item.plot;
    final plot = (itemPlot != null && itemPlot.isNotEmpty) ? itemPlot : (movie?.plot ?? series?.plot);
    final year = item.year ?? movie?.year ?? series?.year;
    final rating = item.rating ?? movie?.rating ?? series?.rating;
    final genre = item.genre ?? movie?.genre ?? series?.genre;
    final runtime = formatRuntime(movie?.durationSecs);
    final meta = <String>[
      ?year,
      if (rating != null) '★ ${rating.toStringAsFixed(1)}',
      if (runtime.isNotEmpty) runtime,
      ?genre,
    ].join('  •  ');
    final cast = movie?.cast ?? series?.cast;
    final director = movie?.director ?? series?.director;
    final credits = <String>[
      if (director != null) 'Regia: $director',
      if (cast != null) 'Cast: $cast',
    ].join('   ');

    return Stack(
      fit: StackFit.expand,
      children: [
        if (backdrop != null)
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            width: 700,
            child: NetImage(
              url: backdrop,
              title: item.name,
              decodeWidth: 700,
              alignment: Alignment.topCenter,
              showTitleOnFallback: false,
            ),
          ),
        const Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Brand.background, Color(0xF00A0A0F), Color(0x660A0A0F), Color(0x000A0A0F)],
                stops: [0.0, 0.38, 0.68, 1.0],
              ),
            ),
          ),
        ),
        const Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [Brand.background, Color(0x000A0A0F)],
                stops: [0.0, 0.5],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(48, 30, 48, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 540,
                child: Text(item.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppText.display),
              ),
              if (meta.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(meta, style: AppText.meta),
              ],
              if (plot != null) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: 540,
                  child: Text(
                    plot,
                    maxLines: _isSeries ? 2 : 5,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.body,
                  ),
                ),
              ],
              if (credits.isNotEmpty) ...[
                const SizedBox(height: 8),
                SizedBox(
                  width: 540,
                  child: Text(
                    credits,
                    maxLines: _isSeries ? 1 : 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.small,
                  ),
                ),
              ],
              const SizedBox(height: 18),
              _actions(series, loading),
              if (_isSeries) ...[
                const SizedBox(height: 14),
                Expanded(child: _episodes(series, loading)),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _actions(SeriesDetails? series, bool loading) {
    final item = widget.item;
    return ListenableBuilder(
      listenable: Listenable.merge([_app.favoritesRevision, _app.progressRevision]),
      builder: (context, child) {
        final favorite = _app.isFavorite(item);
        final buttons = <Widget>[];
        if (_isSeries) {
          final target = _nextEpisode(series);
          final progress = target == null ? null : _app.progressFor(target.key);
          final label = target == null
              ? (loading ? 'Caricamento…' : 'Nessun episodio')
              : '${progress != null ? 'Riprendi' : 'Guarda'} S${target.season} E${target.number}';
          buttons.add(TvButton(
            autofocus: true,
            icon: Icons.play_arrow_rounded,
            label: label,
            onPressed: () {
              if (series != null && target != null) {
                _playEpisode(context, series, target, resume: progress?.position);
              }
            },
          ));
        } else {
          final progress = _app.progressFor(item.key);
          buttons.add(TvButton(
            autofocus: true,
            icon: Icons.play_arrow_rounded,
            label: progress != null ? 'Riprendi da ${formatDuration(progress.position)}' : 'Riproduci',
            onPressed: () => playItems(context, [_app.playbackForMovie(item)], 0, resumeAt: progress?.position),
          ));
          if (progress != null) {
            buttons.add(TvButton(
              icon: Icons.replay_rounded,
              label: 'Dall\'inizio',
              onPressed: () => playItems(context, [_app.playbackForMovie(item)], 0),
            ));
          }
        }
        final trailer = _trailer;
        if (trailer != null) {
          buttons.add(TvButton(
            icon: Icons.movie_outlined,
            label: 'Trailer',
            onPressed: () => _app.openTrailer(trailer, item.name),
          ));
        }
        buttons.add(TvButton(
          icon: favorite ? Icons.check_rounded : Icons.add_rounded,
          label: favorite ? 'Nella mia lista' : 'La mia lista',
          onPressed: () => _app.toggleFavorite(item),
        ));
        return Wrap(spacing: 12, runSpacing: 12, children: buttons);
      },
    );
  }

  /// L'episodio da cui ripartire: l'ultimo guardato, altrimenti il primo.
  Episode? _nextEpisode(SeriesDetails? series) {
    if (series == null || series.seasons.isEmpty) return null;
    Episode? best;
    var bestTime = -1;
    for (final season in series.seasons) {
      for (final episode in series.episodes[season] ?? const <Episode>[]) {
        final progress = _app.progressFor(episode.key);
        if (progress != null && progress.updatedAt > bestTime) {
          best = episode;
          bestTime = progress.updatedAt;
        }
      }
    }
    if (best != null) return best;
    final first = series.episodes[series.seasons.first];
    return first == null || first.isEmpty ? null : first.first;
  }

  void _playEpisode(BuildContext context, SeriesDetails series, Episode episode, {Duration? resume}) {
    final list = series.episodes[episode.season] ?? <Episode>[episode];
    final index = list.indexWhere((e) => e.id == episode.id);
    playItems(
      context,
      [for (final e in list) _app.playbackForEpisode(widget.item, e)],
      index < 0 ? 0 : index,
      resumeAt: resume,
    );
  }

  Widget _episodes(SeriesDetails? series, bool loading) {
    if (series == null) {
      return Align(
        alignment: Alignment.topLeft,
        child: loading
            ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5))
            : const Text('Episodi non disponibili', style: AppText.meta),
      );
    }
    if (series.seasons.isEmpty) {
      return const Align(alignment: Alignment.topLeft, child: Text('Nessun episodio', style: AppText.meta));
    }
    final seasonIndex = math.min(_seasonIndex, series.seasons.length - 1);
    final season = series.seasons[seasonIndex];
    final episodes = series.episodes[season] ?? const <Episode>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (series.seasons.length > 1)
          SizedBox(
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: series.seasons.length,
              separatorBuilder: (context, index) => const SizedBox(width: 10),
              itemBuilder: (context, index) => Center(
                child: TvButton(
                  label: 'Stagione ${series.seasons[index]}',
                  selected: index == seasonIndex,
                  onPressed: () => setState(() => _seasonIndex = index),
                ),
              ),
            ),
          ),
        Expanded(
          child: Align(
            alignment: Alignment.topLeft,
            child: ListenableBuilder(
              listenable: _app.progressRevision,
              builder: (context, child) => ContentRow(
                key: ValueKey<int>(season),
                storageId: 'episodi:${widget.item.id}:$season',
                title: 'Episodi · Stagione $season',
                itemCount: episodes.length,
                itemExtent: Layout.wideExtent,
                height: Layout.wideRowHeight,
                horizontalPadding: 0,
                itemBuilder: (context, index, onFocused) {
                  final episode = episodes[index];
                  final runtime = formatRuntime(episode.durationSecs);
                  final progress = _app.progressFor(episode.key);
                  return WideCard(
                    key: ValueKey<String>(episode.key),
                    title: 'E${episode.number} · ${episode.title}',
                    subtitle: runtime.isEmpty ? null : runtime,
                    image: episode.image ?? widget.item.backdrop ?? widget.item.image,
                    progress: progress?.fraction,
                    onFocused: onFocused,
                    onSelect: () => _playEpisode(context, series, episode, resume: progress?.position),
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}
