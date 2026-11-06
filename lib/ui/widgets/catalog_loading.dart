import 'package:flutter/material.dart';

import '../../app/theme.dart';

/// Il catalogo completo sta arrivando (all'avvio la Home si apre prima del resto).
class CatalogLoading extends StatelessWidget {
  const CatalogLoading({super.key, this.message = 'Carico canali, film e serie…'});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 2.5)),
          const SizedBox(height: 12),
          Text(message, style: AppText.meta),
        ],
      ),
    );
  }
}
