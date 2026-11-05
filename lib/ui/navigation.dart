import 'package:flutter/material.dart';

import '../app/brand.dart';
import '../app/theme.dart';
import '../data/models.dart';
import 'player/player_screen.dart';
import 'screens/details_screen.dart';
import 'widgets/tv_button.dart';

Future<void> openDetails(BuildContext context, MediaItem item) {
  return Navigator.of(context).push(
    PageRouteBuilder<void>(
      transitionDuration: const Duration(milliseconds: 220),
      reverseTransitionDuration: const Duration(milliseconds: 160),
      pageBuilder: (context, animation, secondaryAnimation) => DetailsScreen(item: item),
      transitionsBuilder: (context, animation, secondaryAnimation, child) =>
          FadeTransition(opacity: animation, child: child),
    ),
  );
}

Future<void> playItems(
  BuildContext context,
  List<PlaybackItem> items,
  int index, {
  Duration? resumeAt,
}) {
  if (items.isEmpty) return Future<void>.value();
  return Navigator.of(context).push(
    PageRouteBuilder<void>(
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
      pageBuilder: (context, animation, secondaryAnimation) =>
          PlayerScreen(items: items, initialIndex: index, resumeAt: resumeAt),
    ),
  );
}

/// Finestra di conferma utilizzabile col telecomando ("Annulla" già selezionato).
Future<bool> showTvConfirm(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => Dialog(
      backgroundColor: Brand.surface,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppText.title),
              const SizedBox(height: 10),
              Text(message, style: AppText.body),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TvButton(label: 'Annulla', autofocus: true, onPressed: () => Navigator.of(context).pop(false)),
                  const SizedBox(width: 12),
                  TvButton(label: confirmLabel, onPressed: () => Navigator.of(context).pop(true)),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
  return result ?? false;
}
