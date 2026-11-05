import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/theme.dart';
import '../../core/debouncer.dart';
import '../../data/models.dart';
import '../../state/app_controller.dart';
import '../navigation.dart';
import '../widgets/cards.dart';
import '../widgets/content_row.dart';
import '../widgets/rows_view.dart';
import '../widgets/tv_text_field.dart';

/// Ricerca su canali, film e serie. Gli indici di ricerca sono già pronti
/// nel catalogo, quindi anche con decine di migliaia di titoli è immediata.
class SearchPage extends StatefulWidget {
  const SearchPage({super.key, required this.entryNode});

  final FocusNode entryNode;

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final TextEditingController _text = TextEditingController();
  final Debouncer _debounce = Debouncer(const Duration(milliseconds: 350));
  String _term = '';

  @override
  void dispose() {
    _debounce.cancel();
    _text.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce.run(() {
      if (mounted) setState(() => _term = value.trim());
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: Layout.safeTop),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: Layout.pagePadding, right: Layout.pageRight),
            child: TvTextField(
              focusNode: widget.entryNode,
              controller: _text,
              textInputAction: TextInputAction.search,
              onChanged: _onChanged,
              onSubmitted: (value) {
                _debounce.cancel();
                setState(() => _term = value.trim());
              },
              hint: 'Cerca film, serie e canali (premi OK per scrivere)',
              icon: Icons.search_rounded,
            ),
          ),
          const SizedBox(height: 14),
          Expanded(child: _results(app)),
        ],
      ),
    );
  }

  Widget _results(AppController app) {
    final catalog = app.catalog.value;
    if (catalog == null) return const SizedBox.shrink();
    if (_term.length < 2) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: Layout.pagePadding),
        child: Text('Premi OK sul campo e scrivi almeno 2 lettere. Con ▼ passi ai risultati.', style: AppText.meta),
      );
    }

    final channels = catalog.search(MediaKind.live, _term);
    final movies = catalog.search(MediaKind.movie, _term);
    final series = catalog.search(MediaKind.series, _term);
    final rows = <RowSpec>[];

    if (channels.isNotEmpty) {
      rows.add(RowSpec(
        id: 'canali',
        height: Layout.wideRowHeight,
        builder: (context, onRowFocused) => ContentRow(
          title: 'Canali (${channels.length})',
          itemCount: channels.length,
          itemExtent: Layout.wideExtent,
          height: Layout.wideRowHeight,
          onFocused: onRowFocused,
          itemBuilder: (context, i, onFocused) => WideCard(
            title: channels[i].name,
            image: channels[i].image,
            isLogo: true,
            onFocused: onFocused,
            onSelect: () => playItems(context, app.livePlaylist(channels), i),
          ),
        ),
      ));
    }

    void addPosters(String id, String title, List<MediaItem> items) {
      if (items.isEmpty) return;
      rows.add(RowSpec(
        id: id,
        height: Layout.posterRowHeight,
        builder: (context, onRowFocused) => ContentRow(
          title: '$title (${items.length})',
          itemCount: items.length,
          itemExtent: Layout.posterExtent,
          height: Layout.posterRowHeight,
          onFocused: onRowFocused,
          itemBuilder: (context, i, onFocused) => PosterCard(
            item: items[i],
            onFocused: onFocused,
            onSelect: () => openDetails(context, items[i]),
          ),
        ),
      ));
    }

    addPosters('film', 'Film', movies);
    addPosters('serie', 'Serie TV', series);

    if (rows.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: Layout.pagePadding),
        child: Text('Nessun risultato per «$_term»', style: AppText.meta),
      );
    }
    return RowsView(key: ValueKey<String>(_term), rows: rows);
  }
}
