import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/theme.dart';
import '../../core/debouncer.dart';
import '../../data/models.dart';
import '../../state/app_controller.dart';
import '../navigation.dart';
import '../widgets/cards.dart';
import '../widgets/catalog_loading.dart';
import '../widgets/content_row.dart';
import '../widgets/hero_header.dart';
import '../widgets/rows_view.dart';

/// Pagina Film o Serie TV: una fila per categoria, costruite solo quando servono.
class BrowsePage extends StatefulWidget {
  const BrowsePage({super.key, required this.kind, required this.entryNode});

  final MediaKind kind;
  final FocusNode entryNode;

  @override
  State<BrowsePage> createState() => _BrowsePageState();
}

class _BrowsePageState extends State<BrowsePage> {
  final ValueNotifier<HeroData?> _hero = ValueNotifier(null);
  final Debouncer _heroDebounce = Debouncer(const Duration(milliseconds: 120));

  @override
  void initState() {
    super.initState();
    final catalog = AppScope.of(context).catalog.value;
    final items = catalog?.items(widget.kind) ?? const <MediaItem>[];
    if (items.isNotEmpty) _hero.value = HeroData.fromItem(items.first);
  }

  @override
  void dispose() {
    _heroDebounce.cancel();
    _hero.dispose();
    super.dispose();
  }

  void _showHero(MediaItem item) {
    _heroDebounce.run(() {
      if (mounted) _hero.value = HeroData.fromItem(item);
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return ValueListenableBuilder<Catalog?>(
      valueListenable: app.catalog,
      builder: (context, catalog, child) {
        if (catalog == null) return const SizedBox.shrink();
        if (catalog.partial) {
          return CatalogLoading(message: widget.kind == MediaKind.movie ? 'Carico i film…' : 'Carico le serie…');
        }
        return Column(
          children: [
            HeroHeader(data: _hero),
            Expanded(
              child: ValueListenableBuilder<int>(
                valueListenable: app.favoritesRevision,
                builder: (context, revision, child) => _rows(app, catalog),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _rows(AppController app, Catalog catalog) {
    final rows = <RowSpec>[];
    FocusNode? entry = widget.entryNode;
    final prefix = widget.kind == MediaKind.movie ? 'film' : 'serie';

    void addRow(String id, String title, List<MediaItem> items) {
      if (items.isEmpty) return;
      final node = entry;
      entry = null;
      rows.add(RowSpec(
        id: id,
        height: Layout.posterRowHeight,
        builder: (context, onRowFocused) => ContentRow(
          storageId: '$prefix:$id',
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
                _showHero(item);
              },
              onSelect: () => openDetails(context, item),
            );
          },
        ),
      ));
    }

    addRow('lista', 'La mia lista', app.favoriteItems(widget.kind));
    for (final category in catalog.categories(widget.kind)) {
      addRow('cat:${category.id}', category.name, catalog.inCategory(widget.kind, category.id));
    }

    if (rows.isEmpty) {
      return const Center(child: Text('Nessun contenuto in questa sezione', style: AppText.meta));
    }
    return RowsView(rows: rows);
  }
}
