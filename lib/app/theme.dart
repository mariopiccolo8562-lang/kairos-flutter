import 'package:flutter/material.dart';

import 'brand.dart';

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: Brand.accent,
    brightness: Brightness.dark,
  ).copyWith(primary: Brand.accent, surface: Brand.surface);

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: Brand.background,
    // Su TV niente effetti "touch": il focus è gestito dai nostri componenti.
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    hoverColor: Colors.transparent,
    focusColor: Colors.transparent,
  );
}

/// Misure pensate per lo schermo TV "logico": Fire TV e Android TV usano
/// densità 2.0, quindi un televisore Full HD vale 960×540 punti.
abstract final class Layout {
  static const double railWidth = 64;
  static const double railExpandedWidth = 210;
  static const double pagePadding = 28;
  static const double safeTop = 22;

  static const double posterWidth = 112;
  static const double posterHeight = 168;
  static const double posterExtent = 128;

  static const double wideWidth = 192;
  static const double wideHeight = 108;
  static const double wideExtent = 208;
  static const double wideCardHeight = wideHeight + 6 + 18 + 15;

  static const double rowTitleHeight = 24;
  static const double rowPadding = 12;
  static const double posterRowHeight = rowTitleHeight + posterHeight + rowPadding * 2;
  static const double wideRowHeight = rowTitleHeight + wideCardHeight + rowPadding * 2;

  static const double heroHeight = 196;
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
    color: Colors.white,
  );
  static const TextStyle rowTitle = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w700,
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
    color: Color(0xB3FFFFFF),
  );
  static const TextStyle small = TextStyle(
    fontSize: 11,
    color: Color(0x99FFFFFF),
  );
}
