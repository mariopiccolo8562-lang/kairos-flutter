import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/theme.dart';
import '../../core/debouncer.dart';
import '../../data/models.dart';
import '../../state/app_controller.dart';
import '../navigation.dart';
import '../widgets/cards.dart';
import '../widgets/content_row.dart';
import '../widgets/hero_header.dart';
import '../widgets/rows_view.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.entryNode});

  final FocusNode entryNode;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final ValueNotifier<HeroData?> _hero = ValueNotifier(null);
  final Debouncer _heroDebounce = Debouncer(const Duration(milliseconds: 120));

  @override
  void initState() {
    super.initState();
    final catalog = AppScope.of(context).catalog.value;
    if (catalog != null) {
      final first = catalog.recentMovies.isNotEmpty
          ? catalog.recentMovies.first
          : (catalog.recentSeries.isNotEmpty ? catalog.recentSeries.first : null);
      if (first != null) _hero.value = HeroData.fromItem(first);
    }
  }

  @override
  void dispose() {
    _heroDebounce.cancel();
    _hero.dispose();
    super.dispose();
  }

  /// L'intestazione cambia solo quando ti fermi su un titolo, non a ogni passaggio.
  void _showHero(HeroData data) {
    _heroDebounce.run(() {
      if (mounted) _hero.value = data;
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return ValueListenableBuilder<Catalog?>(
      valueListenable: app.catalog,
      builder: (context, catalog, child) {
        if (catalog == null) return const SizedBox.shrink();
        return Column(
          children: [
            HeroHeader(data: _hero),
            Expanded(
              child: ListenableBuilder(
                listenable: Listenable.merge([app.favoritesRevision, app.progressRevision]),
                builder: (context, child) => _rows(app, catalog),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _rows(AppController app, Catalog catalog) {
    final rows = <RowSpec>[];
    // il primo elemento della prima fila è il punto d'ingresso dalla barra laterale
    FocusNode? entry = widget.entryNode;
    FocusNode? takeEntry() {
      final node = entry;
      entry = null;
      return node;
    }

    void addPosterRow(String id, String title, List<MediaItem> raw) {
      final items = raw.where((x) => !app.parentalLocked(x)).toList(); // controllo genitori: in Home niente contenuti per adulti
      if (items.isEmpty) return;
      final node = takeEntry();
      rows.add(RowSpec(
        id: id,
        height: Layout.posterRowHeight,
        builder: (context, onRowFocused) => ContentRow(
          storageId: id,
          title: title,
          itemCount: items.length,
          itemExtent: Layout.posterExtent,
          height: Layout.posterRowHeight,
          onFocused: onRowFocused,
          itemBuilder: (context, i, onFocused) {
            final item = items[i];
            return PosterCard(
              key: ValueKey<String>(item.key),
              item: item,
              focusNode: i == 0 ? node : null,
              onFocused: () {
                onFocused();
                _showHero(HeroData.fromItem(item));
              },
              onSelect: () => openDetails(context, item),
            );
          },
        ),
      ));
    }

    void addChannelRow(String id, String title, List<MediaItem> rawChannels) {
      final channels = rawChannels.where((x) => !app.parentalLocked(x)).toList();
      if (channels.isEmpty) return;
      final node = takeEntry();
      rows.add(RowSpec(
        id: id,
        height: Layout.wideRowHeight,
        builder: (context, onRowFocused) => ContentRow(
          storageId: id,
          title: title,
          itemCount: channels.length,
          itemExtent: Layout.wideExtent,
          height: Layout.wideRowHeight,
          onFocused: onRowFocused,
          itemBuilder: (context, i, onFocused) {
            final channel = channels[i];
            return WideCard(
              key: ValueKey<String>(channel.key),
              title: channel.name,
              subtitle: channel.number == null ? null : 'Canale ${channel.number}',
              image: channel.image,
              isLogo: true,
              focusNode: i == 0 ? node : null,
              onFocused: () {
                onFocused();
                _showHero(HeroData.fromItem(
                  channel,
                  categoryName: catalog.categoryName(MediaKind.live, channel.categoryId),
                ));
              },
              onSelect: () => playItems(context, app.livePlaylist(channels), i),
            );
          },
        ),
      ));
    }

    final resume = app.continueWatching();
    if (resume.isNotEmpty) {
      final node = takeEntry();
      rows.add(RowSpec(
        id: 'riprendi',
        height: Layout.wideRowHeight,
        builder: (context, onRowFocused) => ContentRow(
          storageId: 'riprendi',
          title: 'Continua a guardare',
          itemCount: resume.length,
          itemExtent: Layout.wideExtent,
          height: Layout.wideRowHeight,
          onFocused: onRowFocused,
          itemBuilder: (context, i, onFocused) {
            final progress = resume[i];
            return WideCard(
              key: ValueKey<String>(progress.item.key),
              title: progress.item.title,
              subtitle: progress.item.subtitle,
              image: progress.item.image,
              progress: progress.fraction,
              focusNode: i == 0 ? node : null,
              onFocused: () {
                onFocused();
                _showHero(HeroData.fromProgress(progress));
              },
              onSelect: () => playItems(context, [app.resumable(progress.item)], 0, resumeAt: progress.position),
            );
          },
        ),
      ));
    }

    addPosterRow('lista', 'La mia lista', [
      ...app.favoriteItems(MediaKind.movie),
      ...app.favoriteItems(MediaKind.series),
    ]);
    addChannelRow('canali', 'I tuoi canali', app.favoriteItems(MediaKind.live));
    addPosterRow('film-nuovi', 'Film aggiunti di recente', catalog.recentMovies);
    addPosterRow('serie-nuove', 'Serie aggiunte di recente', catalog.recentSeries);
    if (catalog.liveCategories.isNotEmpty) {
      final first = catalog.liveCategories.first;
      addChannelRow('diretta:${first.id}', 'In diretta · ${first.name}', catalog.inCategory(MediaKind.live, first.id));
    }
    for (final category in catalog.movieCategories.take(4)) {
      addPosterRow('film:${category.id}', category.name, catalog.inCategory(MediaKind.movie, category.id));
    }
    for (final category in catalog.seriesCategories.take(2)) {
      addPosterRow('serie:${category.id}', category.name, catalog.inCategory(MediaKind.series, category.id));
    }

    if (rows.isEmpty) {
      return const Center(child: Text('Nessun contenuto disponibile', style: AppText.meta));
    }
    return RowsView(rows: rows);
  }
}
