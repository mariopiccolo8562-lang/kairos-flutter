import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
const double _categoryExtent = 44;
const double _channelExtent = 50;

/// TV in diretta: categorie, canali e scheda del canale con la guida TV.
///
/// Le frecce ◀▶ passano da una colonna all'altra tornando sempre al punto
/// giusto (la categoria scelta, l'ultimo canale visto), senza salti.
class LivePage extends StatefulWidget {
  const LivePage({super.key, required this.entryNode});

  final FocusNode entryNode;

  @override
  State<LivePage> createState() => _LivePageState();
}

class _LivePageState extends State<LivePage> {
  String? _categoryId;
  GlobalKey<_ChannelListState> _channelsKey = GlobalKey<_ChannelListState>();
  final GlobalKey<_CategoryListState> _categoriesKey = GlobalKey<_CategoryListState>();
  final FocusNode _watchNode = FocusNode(debugLabel: 'guarda');
  final ValueNotifier<MediaItem?> _focusedChannel = ValueNotifier(null);
  final Debouncer _categoryDebounce = Debouncer(const Duration(milliseconds: 220));
  final Debouncer _channelDebounce = Debouncer(const Duration(milliseconds: 120));

  @override
  void dispose() {
    _categoryDebounce.cancel();
    _channelDebounce.cancel();
    _focusedChannel.dispose();
    _watchNode.dispose();
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

  void _setCategory(String id) {
    if (id == _categoryId) return;
    setState(() {
      _categoryId = id;
      _channelsKey = GlobalKey<_ChannelListState>();
    });
  }

  /// Scorrendo le categorie la lista dei canali si aggiorna quando ti fermi.
  void _previewCategory(String id) {
    _categoryDebounce.run(() {
      if (mounted) _setCategory(id);
    });
  }

  /// Con OK sulla categoria si entra subito nei canali.
  void _openCategory(String id) {
    _categoryDebounce.cancel();
    _setCategory(id);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusChannels();
    });
  }

  void _focusChannels() {
    final list = _channelsKey.currentState;
    if (list != null) list.focusRemembered();
  }

  void _focusCategories() => _categoriesKey.currentState?.focusSelected();

  void _play(AppController app, List<MediaItem> channels, MediaItem channel) {
    final index = channels.indexWhere((c) => c.key == channel.key);
    playItems(context, app.livePlaylist(channels), index < 0 ? 0 : index);
  }

  Widget _column({required Widget child, VoidCallback? onLeft, VoidCallback? onRight}) {
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
        if (event.logicalKey == LogicalKeyboardKey.arrowLeft && onLeft != null) {
          onLeft();
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowRight && onRight != null) {
          onRight();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return Focus(
      // ingresso dalla barra laterale: si va sui canali
      focusNode: widget.entryNode,
      skipTraversal: true,
      onFocusChange: (focused) {
        if (focused && widget.entryNode.hasPrimaryFocus) _focusChannels();
      },
      child: ValueListenableBuilder<Catalog?>(
        valueListenable: app.catalog,
        builder: (context, catalog, child) {
          if (catalog == null) return const SizedBox.shrink();
          return ValueListenableBuilder<int>(
            valueListenable: app.favoritesRevision,
            builder: (context, revision, child) {
              final categories = _categories(app, catalog);
              var selectedId = _categoryId ??
                  (catalog.liveCategories.isNotEmpty ? catalog.liveCategories.first.id : _allId);
              if (!categories.any((c) => c.id == selectedId)) selectedId = _allId;
              final channels = _channels(app, catalog, selectedId);
              return Padding(
                padding: const EdgeInsets.fromLTRB(Layout.pagePadding, Layout.safeTop, Layout.pageRight, Layout.safeBottom),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        const Text('TV in diretta', style: AppText.title),
                        const SizedBox(width: 14),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: Text('${channels.length} canali', style: AppText.meta),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(
                            width: 190,
                            child: _column(
                              onRight: _focusChannels,
                              child: _CategoryList(
                                key: _categoriesKey,
                                categories: categories,
                                selectedId: selectedId,
                                onFocused: _previewCategory,
                                onSelected: _openCategory,
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: channels.isEmpty
                                ? const Center(child: Text('Nessun canale in questa categoria', style: AppText.meta))
                                : _column(
                                    onLeft: _focusCategories,
                                    onRight: () => _watchNode.requestFocus(),
                                    child: _ChannelList(
                                      key: _channelsKey,
                                      channels: channels,
                                      onFocused: (channel) => _channelDebounce.run(() {
                                        if (mounted) _focusedChannel.value = channel;
                                      }),
                                      onSelected: (channel) => _play(app, channels, channel),
                                    ),
                                  ),
                          ),
                          const SizedBox(width: 14),
                          SizedBox(
                            width: 240,
                            child: _column(
                              onLeft: _focusChannels,
                              onRight: () {},
                              child: _ChannelInfo(
                                channel: _focusedChannel,
                                watchNode: _watchNode,
                                onPlay: (channel) => _play(app, channels, channel),
                              ),
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
      ),
    );
  }
}

class _CategoryList extends StatefulWidget {
  const _CategoryList({
    super.key,
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
  State<_CategoryList> createState() => _CategoryListState();
}

class _CategoryListState extends State<_CategoryList> {
  final ScrollController _scroll = ScrollController();
  final Map<String, FocusNode> _nodes = {};

  FocusNode _node(String id) => _nodes.putIfAbsent(id, () => FocusNode(debugLabel: 'categoria-$id'));

  @override
  void dispose() {
    for (final node in _nodes.values) {
      node.dispose();
    }
    _scroll.dispose();
    super.dispose();
  }

  /// Torna sulla categoria scelta (anche se è fuori dallo schermo).
  void focusSelected() {
    if (widget.categories.isEmpty) return;
    final i = widget.categories.indexWhere((c) => c.id == widget.selectedId);
    final index = i < 0 ? 0 : i;
    final id = widget.categories[index].id;
    final node = _nodes[id];
    if (node != null && node.context != null) {
      node.requestFocus();
      return;
    }
    if (_scroll.hasClients) {
      final pos = _scroll.position;
      _scroll.jumpTo((index * _categoryExtent - pos.viewportDimension * 0.4).clamp(0.0, pos.maxScrollExtent).toDouble());
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _nodes[id]?.requestFocus();
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      controller: _scroll,
      itemCount: widget.categories.length,
      itemExtent: _categoryExtent,
      itemBuilder: (context, index) {
        final category = widget.categories[index];
        final selected = category.id == widget.selectedId;
        return TvFocusable(
          focusNode: _node(category.id),
          scrollAlignment: 0.4,
          onFocusChange: (focused) {
            if (focused) widget.onFocused(category.id);
          },
          onSelect: () => widget.onSelected(category.id),
          builder: (context, focused) => Container(
            margin: const EdgeInsets.only(bottom: 4),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.centerLeft,
            decoration: BoxDecoration(
              color: focused ? Colors.white : (selected ? Brand.accent.withValues(alpha: 0.28) : Colors.transparent),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              category.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                height: 1.2,
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

class _ChannelList extends StatefulWidget {
  const _ChannelList({
    super.key,
    required this.channels,
    required this.onFocused,
    required this.onSelected,
  });

  final List<MediaItem> channels;
  final ValueChanged<MediaItem> onFocused;
  final ValueChanged<MediaItem> onSelected;

  @override
  State<_ChannelList> createState() => _ChannelListState();
}

class _ChannelListState extends State<_ChannelList> {
  final ScrollController _scroll = ScrollController();
  final Map<int, FocusNode> _nodes = {};
  int _last = 0;

  FocusNode _node(int index) => _nodes.putIfAbsent(index, () => FocusNode(debugLabel: 'canale-$index'));

  @override
  void dispose() {
    for (final node in _nodes.values) {
      node.dispose();
    }
    _scroll.dispose();
    super.dispose();
  }

  /// Torna sull'ultimo canale selezionato in questa lista.
  void focusRemembered() {
    if (widget.channels.isEmpty) return;
    final index = _last.clamp(0, widget.channels.length - 1);
    final node = _nodes[index];
    if (node != null && node.context != null) {
      node.requestFocus();
      return;
    }
    if (_scroll.hasClients) {
      final pos = _scroll.position;
      _scroll.jumpTo((index * _channelExtent - pos.viewportDimension * 0.4).clamp(0.0, pos.maxScrollExtent).toDouble());
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _nodes[index]?.requestFocus();
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      controller: _scroll,
      itemCount: widget.channels.length,
      itemExtent: _channelExtent,
      itemBuilder: (context, index) {
        final channel = widget.channels[index];
        return TvFocusable(
          focusNode: _node(index),
          scrollAlignment: 0.4,
          onFocusChange: (focused) {
            if (focused) {
              _last = index;
              widget.onFocused(channel);
            }
          },
          onSelect: () => widget.onSelected(channel),
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
                  width: 36,
                  child: Text(
                    channel.number?.toString() ?? '',
                    textAlign: TextAlign.right,
                    maxLines: 1,
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
                    transparentPlaceholder: true,
                    fallback: false,
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
                      height: 1.2,
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
  const _ChannelInfo({required this.channel, required this.watchNode, required this.onPlay});

  final ValueListenable<MediaItem?> channel;
  final FocusNode watchNode;
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
            height: 70,
            width: double.infinity,
            child: NetImage(
              url: channel.image,
              title: channel.name,
              fit: BoxFit.contain,
              decodeWidth: 200,
              transparentPlaceholder: true,
              showTitleOnFallback: false,
            ),
          ),
          const SizedBox(height: 10),
          Text(channel.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppText.rowTitle),
          if (channel.number != null) Text('Canale ${channel.number}', style: AppText.small),
          const SizedBox(height: 10),
          Expanded(
            child: ClipRect(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (current != null) _EpgLine(label: 'ORA', entry: current, now: now, showProgress: true),
                  if (next != null) ...[
                    const SizedBox(height: 10),
                    _EpgLine(label: 'DOPO', entry: next, now: now),
                  ],
                  if (app.supportsEpg && epg == null) const Text('Carico la guida…', style: AppText.small),
                  if (epg != null && current == null) const Text('Guida TV non disponibile', style: AppText.small),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          TvButton(
            focusNode: widget.watchNode,
            icon: Icons.play_arrow_rounded,
            label: 'Guarda',
            expand: true,
            onPressed: () => widget.onPlay(channel),
          ),
          const SizedBox(height: 8),
          ValueListenableBuilder<int>(
            valueListenable: app.favoritesRevision,
            builder: (context, revision, child) {
              final favorite = app.isFavorite(channel);
              return TvButton(
                icon: favorite ? Icons.star_rounded : Icons.star_border_rounded,
                label: favorite ? 'Nei preferiti' : 'Aggiungi ai preferiti',
                expand: true,
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
            Expanded(child: Text(time, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.small)),
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
