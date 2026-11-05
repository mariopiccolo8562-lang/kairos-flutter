import 'package:flutter/material.dart';

import '../../app/brand.dart';
import '../../app/theme.dart';
import '../../data/models.dart';
import 'net_image.dart';
import 'tv_focusable.dart';

const BorderRadius _radius = BorderRadius.all(Radius.circular(8));

BoxDecoration _focusBorder(bool focused) => BoxDecoration(
      borderRadius: _radius,
      border: focused ? Border.all(color: Colors.white, width: 2.5) : null,
    );

/// Locandina verticale per film e serie.
class PosterCard extends StatelessWidget {
  const PosterCard({
    super.key,
    required this.item,
    required this.onSelect,
    this.onFocused,
    this.focusNode,
  });

  final MediaItem item;
  final VoidCallback onSelect;
  final VoidCallback? onFocused;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    return TvFocusable(
      focusNode: focusNode,
      autoScroll: false,
      onSelect: onSelect,
      onFocusChange: (focused) {
        if (focused) onFocused?.call();
      },
      // l'immagine sta in un livello suo: l'ingrandimento sposta il livello senza ridisegnarla
      builder: (context, focused) => AnimatedScale(
        scale: focused ? 1.1 : 1.0,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOutCubic,
        child: Container(
          width: Layout.posterWidth,
          height: Layout.posterHeight,
          foregroundDecoration: _focusBorder(focused),
          child: RepaintBoundary(
            child: ClipRRect(
              borderRadius: _radius,
              child: ColoredBox(
                color: Brand.card,
                child: SizedBox.expand(
                  child: NetImage(url: item.image, title: item.name, decodeWidth: Layout.posterWidth),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Riquadro orizzontale: canali, "continua a guardare", episodi.
class WideCard extends StatelessWidget {
  const WideCard({
    super.key,
    required this.title,
    required this.onSelect,
    this.subtitle,
    this.image,
    this.isLogo = false,
    this.progress,
    this.onFocused,
    this.focusNode,
  });

  final String title;
  final String? subtitle;
  final String? image;
  final bool isLogo;
  final double? progress;
  final VoidCallback onSelect;
  final VoidCallback? onFocused;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final value = progress;
    final sub = subtitle;
    return TvFocusable(
      focusNode: focusNode,
      autoScroll: false,
      onSelect: onSelect,
      onFocusChange: (focused) {
        if (focused) onFocused?.call();
      },
      builder: (context, focused) => SizedBox(
        width: Layout.wideWidth,
        height: Layout.wideCardHeight,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AnimatedScale(
              scale: focused ? 1.06 : 1.0,
              duration: const Duration(milliseconds: 140),
              curve: Curves.easeOutCubic,
              child: Container(
                width: Layout.wideWidth,
                height: Layout.wideHeight,
                foregroundDecoration: _focusBorder(focused),
                child: RepaintBoundary(
                  child: ClipRRect(
                    borderRadius: _radius,
                    child: ColoredBox(
                      color: Brand.card,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (isLogo && image != null)
                            Padding(
                              padding: const EdgeInsets.all(16),
                              child: NetImage(url: image, title: title, fit: BoxFit.contain, decodeWidth: 160),
                            )
                          else
                            NetImage(url: image, title: title, decodeWidth: Layout.wideWidth),
                          if (value != null)
                            Positioned(left: 0, right: 0, bottom: 0, child: ProgressBar(value: value)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            SizedBox(
              height: 18,
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.25,
                  fontWeight: focused ? FontWeight.w700 : FontWeight.w500,
                  color: focused ? Colors.white : const Color(0xB3FFFFFF),
                ),
              ),
            ),
            if (sub != null)
              SizedBox(
                height: 16,
                child: Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.small),
              ),
          ],
        ),
      ),
    );
  }
}

/// Barra sottile di avanzamento (film iniziati, programma in onda).
class ProgressBar extends StatelessWidget {
  const ProgressBar({super.key, required this.value, this.height = 3});

  final double value;
  final double height;

  @override
  Widget build(BuildContext context) {
    final v = value.isNaN ? 0.0 : value.clamp(0.0, 1.0).toDouble();
    return SizedBox(
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: Color(0x55FFFFFF)),
          FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: v,
            child: const ColoredBox(color: Brand.accent),
          ),
        ],
      ),
    );
  }
}

/// Etichetta piccola (es. "ORA", "DOPO" nella guida TV).
class TagLabel extends StatelessWidget {
  const TagLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: Brand.accent, borderRadius: BorderRadius.circular(4)),
      child: Text(
        text,
        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, height: 1.2, color: Colors.black),
      ),
    );
  }
}
