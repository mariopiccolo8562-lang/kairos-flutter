import 'package:flutter/material.dart';

import '../../app/brand.dart';

/// Logo di Kairos Plus: emblema (anello con la K) e, se c'è spazio, la scritta.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 40, this.showName = true});

  final double size;
  final bool showName;

  @override
  Widget build(BuildContext context) {
    final emblem = Image.asset(
      'assets/brand/emblem.png',
      width: size,
      height: size,
      cacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).round(),
      filterQuality: FilterQuality.medium,
    );
    if (!showName) return emblem;
    final fontSize = size * 0.5;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        emblem,
        SizedBox(width: size * 0.25),
        Text(
          Brand.shortName,
          maxLines: 1,
          softWrap: false,
          style: TextStyle(color: Colors.white, fontSize: fontSize, fontWeight: FontWeight.w900, height: 1.0),
        ),
        SizedBox(width: size * 0.15),
        Container(
          padding: EdgeInsets.symmetric(horizontal: size * 0.14, vertical: size * 0.05),
          decoration: BoxDecoration(color: Brand.accentDeep, borderRadius: BorderRadius.circular(size * 0.12)),
          child: Text(
            'PLUS',
            maxLines: 1,
            softWrap: false,
            style: TextStyle(
              color: Colors.white,
              fontSize: fontSize * 0.52,
              fontWeight: FontWeight.w900,
              letterSpacing: fontSize * 0.08,
              height: 1.1,
            ),
          ),
        ),
      ],
    );
  }
}
