import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../app/brand.dart';
import '../../app/perf.dart';

/// Immagine da internet con cache su disco e decodifica già alla misura
/// mostrata (molta meno RAM). Se manca o non si carica, mostra una
/// copertina generata con il titolo.
class NetImage extends StatelessWidget {
  const NetImage({
    super.key,
    required this.url,
    required this.title,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
    this.decodeWidth,
    this.showTitleOnFallback = true,
    this.transparentPlaceholder = false,
    this.fallback = true,
  });

  final String? url;
  final String title;
  final BoxFit fit;
  final Alignment alignment;

  /// Larghezza (in punti) a cui viene mostrata: l'immagine si decodifica a quella misura.
  final double? decodeWidth;
  final bool showTitleOnFallback;

  /// Nessun riquadro colorato mentre l'immagine arriva (sfondi grandi).
  final bool transparentPlaceholder;

  /// Copertina generata se l'immagine non c'è.
  final bool fallback;

  @override
  Widget build(BuildContext context) {
    final u = url;
    if (u == null || u.isEmpty || !(u.startsWith('http://') || u.startsWith('https://'))) {
      return fallback ? FallbackArt(title: title, showTitle: showTitleOnFallback) : const SizedBox.shrink();
    }
    final width = decodeWidth;
    final cacheWidth = width == null ? null : (width * MediaQuery.devicePixelRatioOf(context)).round();
    return CachedNetworkImage(
      imageUrl: u,
      fit: fit,
      alignment: alignment,
      memCacheWidth: cacheWidth,
      filterQuality: FilterQuality.low,
      fadeInDuration: Perf.lite ? Duration.zero : const Duration(milliseconds: 160),
      fadeOutDuration: Duration.zero,
      placeholder: (context, url) =>
          transparentPlaceholder ? const SizedBox.expand() : const ColoredBox(color: Brand.card),
      errorWidget: (context, url, error) => fallback
          ? FallbackArt(title: title, showTitle: showTitleOnFallback)
          : const SizedBox.shrink(),
    );
  }
}

/// Copertina generata: colore ricavato dal titolo, sempre uguale per lo stesso titolo.
class FallbackArt extends StatelessWidget {
  const FallbackArt({super.key, required this.title, this.showTitle = true});

  final String title;
  final bool showTitle;

  @override
  Widget build(BuildContext context) {
    var hash = 0;
    for (final unit in title.codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    final hue = (hash % 360).toDouble();
    final top = HSLColor.fromAHSL(1, hue, 0.45, 0.30).toColor();
    final bottom = HSLColor.fromAHSL(1, (hue + 35) % 360, 0.50, 0.14).toColor();
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [top, bottom],
        ),
      ),
      child: showTitle
          ? Padding(
              padding: const EdgeInsets.all(10),
              child: Align(
                alignment: Alignment.bottomLeft,
                child: Text(
                  title,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    height: 1.15,
                    color: Colors.white,
                  ),
                ),
              ),
            )
          : const SizedBox.expand(),
    );
  }
}
