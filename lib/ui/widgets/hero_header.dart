import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/brand.dart';
import '../../app/theme.dart';
import '../../core/format.dart';
import '../../data/models.dart';
import 'net_image.dart';

/// Cosa mostrare nella parte alta della pagina per l'elemento selezionato.
class HeroData {
  const HeroData({
    required this.title,
    this.meta,
    this.plot,
    this.image,
    this.backdrop,
    this.isLogo = false,
    this.item,
  });

  factory HeroData.fromItem(MediaItem item, {String? categoryName}) {
    final year = item.year;
    final rating = item.rating;
    final genre = item.genre;
    final parts = <String>[
      ?year,
      if (rating != null) '★ ${rating.toStringAsFixed(1)}',
      ?genre,
      if (item.kind == MediaKind.live && categoryName != null && categoryName.isNotEmpty) categoryName,
    ];
    return HeroData(
      title: item.name,
      meta: parts.isEmpty ? null : parts.join('  •  '),
      plot: item.plot,
      image: item.image,
      backdrop: item.backdrop,
      isLogo: item.kind == MediaKind.live,
      item: item,
    );
  }

  factory HeroData.fromProgress(WatchProgress progress) => HeroData(
        title: progress.item.title,
        meta: progress.item.subtitle,
        plot: 'Riprendi da ${formatDuration(progress.position)}',
        image: progress.item.image,
        backdrop: progress.item.image,
      );

  final String title;
  final String? meta;
  final String? plot;
  final String? image;
  final String? backdrop;
  final bool isLogo;
  final MediaItem? item;

  String get id => item?.key ?? title;
}

/// Intestazione in stile Netflix: titolo, dati e trama a sinistra, immagine
/// sfumata a destra.
///
/// Pensata per le chiavette: il testo cambia subito, l'immagine grande arriva
/// solo quando ti fermi su un titolo (e sulle chiavette con poca memoria non
/// c'è proprio), la scheda completa del film si chiede dopo un attimo di pausa.
class HeroHeader extends StatefulWidget {
  const HeroHeader({super.key, required this.data, this.height = Layout.heroHeight});

  final ValueListenable<HeroData?> data;
  final double height;

  @override
  State<HeroHeader> createState() => _HeroHeaderState();
}

class _HeroHeaderState extends State<HeroHeader> {
  HeroData? _data;
  String? _backdrop;
  MovieDetails? _details;
  Timer? _imageTimer;
  Timer? _detailsTimer;
  late final bool _lite = AppScope.of(context).lite;

  @override
  void initState() {
    super.initState();
    widget.data.addListener(_onData);
    _apply(widget.data.value, immediate: true);
  }

  @override
  void didUpdateWidget(HeroHeader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data != widget.data) {
      oldWidget.data.removeListener(_onData);
      widget.data.addListener(_onData);
      _apply(widget.data.value, immediate: true);
    }
  }

  @override
  void dispose() {
    widget.data.removeListener(_onData);
    _imageTimer?.cancel();
    _detailsTimer?.cancel();
    super.dispose();
  }

  void _onData() => _apply(widget.data.value);

  void _apply(HeroData? data, {bool immediate = false}) {
    _imageTimer?.cancel();
    _detailsTimer?.cancel();
    final changed = data?.id != _data?.id;
    _data = data;
    if (changed) {
      _details = null;
      _backdrop = null;
    }
    if (mounted && !immediate) setState(() {});
    if (data == null) return;

    // immagine grande: solo se ti fermi sul titolo
    if (!_lite && !data.isLogo) {
      final url = data.backdrop ?? data.image;
      if (url != null) {
        if (immediate) {
          _backdrop = url;
        } else {
          _imageTimer = Timer(const Duration(milliseconds: 550), () {
            if (mounted && _data?.id == data.id) setState(() => _backdrop = url);
          });
        }
      }
    }

    // trama e sfondo dei film Xtream (non sono nell'elenco): dopo una pausa più lunga
    final item = data.item;
    if (item != null && item.kind == MediaKind.movie && (item.plot == null || item.backdrop == null)) {
      _detailsTimer = Timer(const Duration(milliseconds: 900), () async {
        if (!mounted) return;
        final details = await AppScope.of(context).movieDetails(item);
        if (!mounted || details == null || _data?.id != data.id) return;
        setState(() {
          _details = details;
          if (!_lite && item.backdrop == null && details.backdrop != null) _backdrop = details.backdrop;
        });
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    return SizedBox(
      height: widget.height,
      child: RepaintBoundary(
        child: d == null ? const SizedBox.expand() : _body(d),
      ),
    );
  }

  Widget _body(HeroData d) {
    final details = _details;
    final plot = (d.plot != null && d.plot!.isNotEmpty) ? d.plot : details?.plot;
    final meta = d.meta;
    final backdrop = _backdrop;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (d.isLogo && d.image != null)
          Positioned(
            right: Layout.pageRight + 16,
            top: 28,
            bottom: 36,
            width: 220,
            child: NetImage(
              key: ValueKey<String>('logo:${d.image}'),
              url: d.image,
              title: d.title,
              fit: BoxFit.contain,
              decodeWidth: 220,
              transparentPlaceholder: true,
              fallback: false,
            ),
          )
        else if (backdrop != null)
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            width: 560,
            child: NetImage(
              key: ValueKey<String>('sfondo:$backdrop'),
              url: backdrop,
              title: d.title,
              decodeWidth: 560,
              alignment: Alignment.topCenter,
              transparentPlaceholder: true,
              fallback: false,
            ),
          ),
        const Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Brand.background, Color(0xE60B0812), Color(0x000B0812)],
                stops: [0.0, 0.45, 0.82],
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
                colors: [Brand.background, Color(0x000B0812)],
                stops: [0.0, 0.42],
              ),
            ),
          ),
        ),
        Positioned(
          left: Layout.pagePadding,
          top: Layout.safeTop + 4,
          width: 460,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(d.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppText.display),
              if (meta != null) ...[
                const SizedBox(height: 8),
                Text(meta, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.meta),
              ],
              if (plot != null && plot.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(plot, maxLines: 3, overflow: TextOverflow.ellipsis, style: AppText.body),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
