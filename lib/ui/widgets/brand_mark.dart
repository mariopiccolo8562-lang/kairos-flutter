import 'package:flutter/material.dart';

import '../../app/brand.dart';

/// Il nome dell'app scritto come logo.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.fontSize = 28});

  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Text(
      Brand.appName.toUpperCase(),
      maxLines: 1,
      softWrap: false,
      style: TextStyle(
        color: Brand.accent,
        fontSize: fontSize,
        fontWeight: FontWeight.w900,
        letterSpacing: fontSize * 0.12,
      ),
    );
  }
}
