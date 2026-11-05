import 'package:flutter/material.dart';

import 'brand.dart';

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: Brand.accent,
    brightness: Brightness.dark,
  ).copyWith(primary: Brand.accent, secondary: Brand.accentDeep, surface: Brand.surface);

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: Brand.background,
    // Su TV niente effetti "touch": il focus è gestito dai nostri componenti.
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    hoverColor: Colors.transparent,
    focusColor: Colors.transparent,
    textSelectionTheme: const TextSelectionThemeData(
      cursorColor: Brand.accent,
      selectionColor: Color(0x66A855F7),
      selectionHandleColor: Brand.accent,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: Brand.accent),
  );
}

/// Misure pensate per lo schermo TV "logico": Fire TV e Android TV usano
/// densità 2.0, quindi un televisore Full HD vale 960×540 punti.
/// I margini tengono testi e pulsanti lontani dai bordi (TV che tagliano l'immagine).
abstract final class Layout {
  static const double railWidth = 72;
  static const double railExpandedWidth = 220;
  static const double pagePadding = 32;
  static const double pageRight = 40;
  static const double safeTop = 24;
  static const double safeBottom = 20;

  static const double posterWidth = 112;
  static const double posterHeight = 168;
  static const double posterExtent = 128;

  static const double wideWidth = 192;
  static const double wideHeight = 108;
  static const double wideExtent = 208;
  static const double wideCardHeight = wideHeight + 6 + 18 + 16;

  static const double rowTitleHeight = 26;
  static const double rowPadding = 12;
  static const double posterRowHeight = rowTitleHeight + posterHeight + rowPadding * 2;
  static const double wideRowHeight = rowTitleHeight + wideCardHeight + rowPadding * 2;

  static const double heroHeight = 188;
}

abstract final class AppText {
  static const TextStyle display = TextStyle(
    fontSize: 30,
    fontWeight: FontWeight.w800,
    height: 1.1,
    color: Colors.white,
  );
  static const TextStyle title = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w700,
    height: 1.2,
    color: Colors.white,
  );
  static const TextStyle rowTitle = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w700,
    height: 1.2,
    color: Colors.white,
  );
  static const TextStyle body = TextStyle(
    fontSize: 13,
    height: 1.35,
    color: Color(0xDDFFFFFF),
  );
  static const TextStyle meta = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w600,
    height: 1.25,
    color: Color(0xB3FFFFFF),
  );
  static const TextStyle small = TextStyle(
    fontSize: 11,
    height: 1.25,
    color: Color(0x99FFFFFF),
  );
}
