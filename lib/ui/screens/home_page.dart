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
    final app = AppScope.of(context);
    final catalog = app.catalog.value;
    if (catalog != null) {
      // titolo in evidenza all'apertura: il primo film (o serie) aggiunto di recente che non è di una categoria
      // nascosta dal pannello (rc «home.hide») né, con gli adulti fuori dalla Home, per adulti; se lo erano tutti,
      // il primo titolo delle righe della Home
      final first = app.homeRules.heroPick(catalog);
      if (first != null) {
        _hero.value = HeroData.fromItem(
          first,
          categoryName: first.kind == MediaKind.live ? catalog.categoryName(MediaKind.live, first.categoryId) : null,
        );
      }
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
                listenable: Listenable.merge([app.favoritesRevision, app.progressRevision, app.trendRevision]),
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
    // Home decisa dal pannello: categorie in primo piano (home.top) e nascoste (home.hide); senza regole come sempre.
    // Adulti fuori dalla Home (rc «adult» diverso da «on»): le categorie per adulti contano come nascoste e in
    // nessuna riga entra un elemento per adulti (categoria per adulti o nascosta, titolo per adulti)
    final rules = app.homeRules;
    final home = rules.layout(catalog);
    final hiddenMovies = rules.hiddenIds(catalog, MediaKind.movie);
    final hiddenSeries = rules.hiddenIds(catalog, MediaKind.series);
    // controllo genitori: in Home niente contenuti protetti; con gli adulti fuori dalla Home neanche quelli per adulti
    bool show(MediaItem x) => !app.parentalLocked(x) && !rules.blocked(catalog, x);
    // il primo elemento della prima fila è il punto d'ingresso dalla barra laterale
    FocusNode? entry = widget.entryNode;
    FocusNode? takeEntry() {
      final node = entry;
      entry = null;
      return node;
    }

    void addPosterRow(String id, String title, List<MediaItem> raw) {
      final items = raw.where(show).toList();
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
      final channels = rawChannels.where(show).toList();
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

    // con gli adulti fuori dalla Home anche qui niente film ed episodi per adulti
    final resume = rules.resume(catalog, app.continueWatching());
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

    // categorie in primo piano subito dopo «Continua a guardare», prima di tutte le altre righe
    for (final (kind, category) in home.top) {
      if (kind == MediaKind.live) {
        addChannelRow('diretta:${category.id}', 'In diretta · ${category.name}', catalog.inCategory(MediaKind.live, category.id));
      } else {
        final prefix = kind == MediaKind.movie ? 'film' : 'serie';
        addPosterRow('$prefix:${category.id}', category.name, catalog.inCategory(kind, category.id));
      }
    }

    // di tendenza questa settimana (classifica del pannello), solo i titoli che la linea ha, senza le categorie nascoste
    if (app.trendRows) {
      addPosterRow('tendenza-film', 'Film di tendenza questa settimana', [
        for (final item in app.trending(catalog, MediaKind.movie))
          if (!hiddenMovies.contains(item.categoryId)) item,
      ]);
      addPosterRow('tendenza-serie', 'Serie di tendenza questa settimana', [
        for (final item in app.trending(catalog, MediaKind.series))
          if (!hiddenSeries.contains(item.categoryId)) item,
      ]);
    }

    addPosterRow('lista', 'La mia lista', [
      ...app.favoriteItems(MediaKind.movie),
      ...app.favoriteItems(MediaKind.series),
    ]);
    addChannelRow('canali', 'I tuoi canali', app.favoriteItems(MediaKind.live));
    // novità senza i titoli delle categorie nascoste
    addPosterRow('film-nuovi', 'Film aggiunti di recente', [
      for (final item in catalog.recentMovies)
        if (!hiddenMovies.contains(item.categoryId)) item,
    ]);
    addPosterRow('serie-nuove', 'Serie aggiunte di recente', [
      for (final item in catalog.recentSeries)
        if (!hiddenSeries.contains(item.categoryId)) item,
    ]);
    // le solite righe di categoria (stesso numero di sempre) senza le nascoste e senza quelle già in primo piano
    final live = home.live;
    if (live != null) {
      addChannelRow('diretta:${live.id}', 'In diretta · ${live.name}', catalog.inCategory(MediaKind.live, live.id));
    }
    for (final category in home.movies) {
      addPosterRow('film:${category.id}', category.name, catalog.inCategory(MediaKind.movie, category.id));
    }
    for (final category in home.series) {
      addPosterRow('serie:${category.id}', category.name, catalog.inCategory(MediaKind.series, category.id));
    }

    if (rows.isEmpty) {
      return const Center(child: Text('Nessun contenuto disponibile', style: AppText.meta));
    }
    return RowsView(rows: rows);
  }
}
