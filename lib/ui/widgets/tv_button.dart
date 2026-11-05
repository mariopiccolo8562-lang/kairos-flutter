import 'package:flutter/material.dart';

import 'tv_focusable.dart';

/// Pulsante per TV: bianco con testo nero quando è selezionato.
class TvButton extends StatelessWidget {
  const TvButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.autofocus = false,
    this.focusNode,
    this.selected = false,
  });

  final String label;
  final VoidCallback onPressed;
  final IconData? icon;
  final bool autofocus;
  final FocusNode? focusNode;

  /// Evidenzia il pulsante attivo in un gruppo (es. la stagione scelta).
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return TvFocusable(
      focusNode: focusNode,
      autofocus: autofocus,
      onSelect: onPressed,
      builder: (context, focused) {
        final foreground = focused ? Colors.black : Colors.white;
        final background = focused
            ? Colors.white
            : (selected ? accent.withValues(alpha: 0.35) : const Color(0x26FFFFFF));
        return AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
          decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(6)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 18, color: foreground),
                const SizedBox(width: 8),
              ],
              Text(
                label,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: foreground),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Stile dei campi di testo, ben visibili quando sono selezionati.
InputDecoration tvInputDecoration({String? label, String? hint, IconData? icon}) {
  return InputDecoration(
    labelText: label,
    hintText: hint,
    prefixIcon: icon == null ? null : Icon(icon),
    filled: true,
    fillColor: const Color(0x1AFFFFFF),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: Color(0x33FFFFFF)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: Colors.white, width: 2),
    ),
  );
}
