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

/// Grande intestazione in stile Netflix: immagine sfumata a destra,
/// titolo, dati e trama a sinistra. Cambia con una dissolvenza.
class HeroHeader extends StatelessWidget {
  const HeroHeader({super.key, required this.data, this.height = Layout.heroHeight});

  final ValueListenable<HeroData?> data;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: RepaintBoundary(
        child: ValueListenableBuilder<HeroData?>(
          valueListenable: data,
          builder: (context, value, child) => AnimatedSwitcher(
            duration: const Duration(milliseconds: 260),
            layoutBuilder: (current, previous) => Stack(
              fit: StackFit.expand,
              children: [...previous, ?current],
            ),
            child: value == null
                ? const SizedBox.expand(key: ValueKey<String>('vuoto'))
                : _HeroBody(key: ValueKey<String>(value.id), data: value),
          ),
        ),
      ),
    );
  }
}

class _HeroBody extends StatefulWidget {
  const _HeroBody({super.key, required this.data});

  final HeroData data;

  @override
  State<_HeroBody> createState() => _HeroBodyState();
}

class _HeroBodyState extends State<_HeroBody> {
  MovieDetails? _details;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    final item = widget.data.item;
    // I server Xtream non includono trama e sfondo nell'elenco dei film:
    // li chiediamo solo se l'utente si ferma sul titolo per un attimo.
    if (item != null && item.kind == MediaKind.movie && (item.plot == null || item.backdrop == null)) {
      _timer = Timer(const Duration(milliseconds: 450), () async {
        if (!mounted) return;
        final details = await AppScope.of(context).movieDetails(item);
        if (mounted && details != null) setState(() => _details = details);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    final details = _details;
    final backdrop = d.isLogo ? null : (details?.backdrop ?? d.backdrop ?? details?.image ?? d.image);
    final plot = d.plot ?? details?.plot;
    final meta = d.meta;

    return Stack(
      fit: StackFit.expand,
      children: [
        if (d.isLogo && d.image != null)
          Positioned(
            right: 56,
            top: 24,
            bottom: 40,
            width: 240,
            child: NetImage(url: d.image, title: d.title, fit: BoxFit.contain, decodeWidth: 240),
          )
        else if (backdrop != null)
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            width: 600,
            child: NetImage(
              url: backdrop,
              title: d.title,
              decodeWidth: 600,
              alignment: Alignment.topCenter,
              showTitleOnFallback: false,
            ),
          ),
        const Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Brand.background, Color(0xE60A0A0F), Color(0x000A0A0F)],
                stops: [0.0, 0.42, 0.8],
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
                stops: [0.0, 0.45],
              ),
            ),
          ),
        ),
        Positioned(
          left: Layout.pagePadding,
          top: Layout.safeTop + 6,
          width: 440,
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
