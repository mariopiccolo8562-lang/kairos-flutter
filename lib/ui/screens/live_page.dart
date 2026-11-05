import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/brand.dart';
import '../../app/theme.dart';
import '../../core/debouncer.dart';
import '../../core/format.dart';
import '../../data/models.dart';
import '../../state/app_controller.dart';
import '../navigation.dart';
import '../widgets/cards.dart';
import '../widgets/net_image.dart';
import '../widgets/tv_button.dart';
import '../widgets/tv_focusable.dart';

const String _favoritesId = '__preferiti';
const String _allId = '__tutti';

/// TV in diretta: categorie, canali e scheda del canale con la guida TV.
class LivePage extends StatefulWidget {
  const LivePage({super.key, required this.entryNode});

  final FocusNode entryNode;

  @override
  State<LivePage> createState() => _LivePageState();
}

class _LivePageState extends State<LivePage> {
  String? _categoryId;
  final ValueNotifier<MediaItem?> _focusedChannel = ValueNotifier(null);
  final Debouncer _categoryDebounce = Debouncer(const Duration(milliseconds: 220));
  final Debouncer _channelDebounce = Debouncer(const Duration(milliseconds: 120));

  @override
  void dispose() {
    _categoryDebounce.cancel();
    _channelDebounce.cancel();
    _focusedChannel.dispose();
    super.dispose();
  }

  List<Category> _categories(AppController app, Catalog catalog) => [
        if (app.favoriteItems(MediaKind.live).isNotEmpty) const Category(id: _favoritesId, name: 'Preferiti'),
        const Category(id: _allId, name: 'Tutti i canali'),
        ...catalog.liveCategories,
      ];

  List<MediaItem> _channels(AppController app, Catalog catalog, String id) {
    if (id == _favoritesId) return app.favoriteItems(MediaKind.live);
    if (id == _allId) return catalog.live;
    return catalog.inCategory(MediaKind.live, id);
  }

  /// Scorrendo le categorie la lista dei canali si aggiorna quando ti fermi.
  void _previewCategory(String id) {
    _categoryDebounce.run(() {
      if (mounted && id != _categoryId) setState(() => _categoryId = id);
    });
  }

  /// Con OK sulla categoria si entra subito nei canali.
  void _openCategory(String id) {
    _categoryDebounce.cancel();
    setState(() => _categoryId = id);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.entryNode.context != null) widget.entryNode.requestFocus();
    });
  }

  void _play(AppController app, List<MediaItem> channels, MediaItem channel) {
    final index = channels.indexWhere((c) => c.key == channel.key);
    playItems(context, app.livePlaylist(channels), index < 0 ? 0 : index);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return ValueListenableBuilder<Catalog?>(
      valueListenable: app.catalog,
      builder: (context, catalog, child) {
        if (catalog == null) return const SizedBox.shrink();
        return ValueListenableBuilder<int>(
          valueListenable: app.favoritesRevision,
          builder: (context, revision, child) {
            final categories = _categories(app, catalog);
            final selectedId = _categoryId ??
                (catalog.liveCategories.isNotEmpty ? catalog.liveCategories.first.id : _allId);
            final channels = _channels(app, catalog, selectedId);
            return Padding(
              padding: const EdgeInsets.fromLTRB(Layout.pagePadding, Layout.safeTop, Layout.pagePadding, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('TV in diretta', style: AppText.title),
                  const SizedBox(height: 12),
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          width: 190,
                          child: _CategoryList(
                            categories: categories,
                            selectedId: selectedId,
                            onFocused: _previewCategory,
                            onSelected: _openCategory,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: channels.isEmpty
                              ? const Center(child: Text('Nessun canale in questa categoria', style: AppText.meta))
                              : _ChannelList(
                                  key: ValueKey<String>(selectedId),
                                  channels: channels,
                                  entryNode: widget.entryNode,
                                  onFocused: (channel) => _channelDebounce.run(() {
                                    if (mounted) _focusedChannel.value = channel;
                                  }),
                                  onSelected: (channel) => _play(app, channels, channel),
                                ),
                        ),
                        const SizedBox(width: 14),
                        SizedBox(
                          width: 250,
                          child: _ChannelInfo(
                            channel: _focusedChannel,
                            onPlay: (channel) => _play(app, channels, channel),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _CategoryList extends StatelessWidget {
  const _CategoryList({
    required this.categories,
    required this.selectedId,
    required this.onFocused,
    required this.onSelected,
  });

  final List<Category> categories;
  final String selectedId;
  final ValueChanged<String> onFocused;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: categories.length,
      itemExtent: 44,
      itemBuilder: (context, index) {
        final category = categories[index];
        final selected = category.id == selectedId;
        return TvFocusable(
          onFocusChange: (focused) {
            if (focused) onFocused(category.id);
          },
          onSelect: () => onSelected(category.id),
          builder: (context, focused) => Container(
            margin: const EdgeInsets.only(bottom: 4),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.centerLeft,
            decoration: BoxDecoration(
              color: focused ? Colors.white : (selected ? const Color(0x26FFFFFF) : Colors.transparent),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              category.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                fontWeight: selected || focused ? FontWeight.w700 : FontWeight.w500,
                color: focused ? Colors.black : (selected ? Colors.white : const Color(0xB3FFFFFF)),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ChannelList extends StatelessWidget {
  const _ChannelList({
    super.key,
    required this.channels,
    required this.entryNode,
    required this.onFocused,
    required this.onSelected,
  });

  final List<MediaItem> channels;
  final FocusNode entryNode;
  final ValueChanged<MediaItem> onFocused;
  final ValueChanged<MediaItem> onSelected;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: channels.length,
      itemExtent: 50,
      itemBuilder: (context, index) {
        final channel = channels[index];
        return TvFocusable(
          focusNode: index == 0 ? entryNode : null,
          scrollAlignment: 0.4,
          onFocusChange: (focused) {
            if (focused) onFocused(channel);
          },
          onSelect: () => onSelected(channel),
          builder: (context, focused) => Container(
            margin: const EdgeInsets.only(bottom: 4),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: focused ? Colors.white : const Color(0x0FFFFFFF),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 34,
                  child: Text(
                    channel.number?.toString() ?? '',
                    textAlign: TextAlign.right,
                    style: TextStyle(fontSize: 12, color: focused ? Colors.black54 : Colors.white38),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 44,
                  height: 30,
                  child: NetImage(
                    url: channel.image,
                    title: channel.name,
                    fit: BoxFit.contain,
                    decodeWidth: 44,
                    showTitleOnFallback: false,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    channel.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: focused ? FontWeight.w700 : FontWeight.w500,
                      color: focused ? Colors.black : Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Scheda del canale selezionato: logo, programma in onda e successivo.
class _ChannelInfo extends StatefulWidget {
  const _ChannelInfo({required this.channel, required this.onPlay});

  final ValueListenable<MediaItem?> channel;
  final ValueChanged<MediaItem> onPlay;

  @override
  State<_ChannelInfo> createState() => _ChannelInfoState();
}

class _ChannelInfoState extends State<_ChannelInfo> {
  Timer? _timer;
  List<EpgEntry>? _epg;

  @override
  void initState() {
    super.initState();
    widget.channel.addListener(_onChannelChanged);
  }

  @override
  void dispose() {
    widget.channel.removeListener(_onChannelChanged);
    _timer?.cancel();
    super.dispose();
  }

  void _onChannelChanged() {
    _timer?.cancel();
    setState(() => _epg = null);
    final channel = widget.channel.value;
    if (channel == null) return;
    final app = AppScope.of(context);
    if (!app.supportsEpg) return;
    // La guida si chiede solo se ti fermi sul canale: niente richieste a raffica.
    _timer = Timer(const Duration(milliseconds: 450), () async {
      final list = await app.epgFor(channel);
      if (!mounted || widget.channel.value?.key != channel.key) return;
      setState(() => _epg = list);
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final channel = widget.channel.value;
    if (channel == null) {
      return const Center(
        child: Text('Scegli un canale\nper vedere la guida', textAlign: TextAlign.center, style: AppText.meta),
      );
    }
    final now = DateTime.now();
    final epg = _epg;
    final (current, next) = currentAndNext(epg ?? const <EpgEntry>[], now);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Brand.surface, borderRadius: BorderRadius.circular(10)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 80,
            width: double.infinity,
            child: NetImage(url: channel.image, title: channel.name, fit: BoxFit.contain, decodeWidth: 220),
          ),
          const SizedBox(height: 12),
          Text(channel.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppText.rowTitle),
          if (channel.number != null) Text('Canale ${channel.number}', style: AppText.small),
          const SizedBox(height: 12),
          if (current != null) _EpgLine(label: 'ORA', entry: current, now: now, showProgress: true),
          if (next != null) ...[
            const SizedBox(height: 10),
            _EpgLine(label: 'DOPO', entry: next, now: now),
          ],
          if (app.supportsEpg && epg == null) const Text('Carico la guida…', style: AppText.small),
          if (epg != null && current == null) const Text('Guida TV non disponibile', style: AppText.small),
          const Spacer(),
          TvButton(icon: Icons.play_arrow_rounded, label: 'Guarda', onPressed: () => widget.onPlay(channel)),
          const SizedBox(height: 8),
          ValueListenableBuilder<int>(
            valueListenable: app.favoritesRevision,
            builder: (context, revision, child) {
              final favorite = app.isFavorite(channel);
              return TvButton(
                icon: favorite ? Icons.star_rounded : Icons.star_border_rounded,
                label: favorite ? 'Nei preferiti' : 'Aggiungi ai preferiti',
                onPressed: () => app.toggleFavorite(channel),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _EpgLine extends StatelessWidget {
  const _EpgLine({required this.label, required this.entry, required this.now, this.showProgress = false});

  final String label;
  final EpgEntry entry;
  final DateTime now;
  final bool showProgress;

  @override
  Widget build(BuildContext context) {
    final start = entry.start;
    final end = entry.end;
    final time = start == null ? '' : (end == null ? formatClock(start) : '${formatClock(start)} – ${formatClock(end)}');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            TagLabel(label),
            const SizedBox(width: 6),
            Text(time, style: AppText.small),
          ],
        ),
        const SizedBox(height: 4),
        Text(entry.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppText.body),
        if (showProgress) ...[
          const SizedBox(height: 6),
          ProgressBar(value: entry.progress(now)),
        ],
      ],
    );
  }
}
