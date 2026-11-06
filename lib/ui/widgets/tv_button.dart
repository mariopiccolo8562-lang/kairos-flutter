import 'package:flutter/material.dart';

import '../../app/brand.dart';
import '../../app/perf.dart';
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
    this.primary = false,
    this.expand = false,
  });

  final String label;
  final VoidCallback onPressed;
  final IconData? icon;
  final bool autofocus;
  final FocusNode? focusNode;

  /// Evidenzia il pulsante attivo in un gruppo (es. la stagione scelta).
  final bool selected;

  /// Pulsante principale (colore del marchio quando non è selezionato).
  final bool primary;

  /// Occupa tutta la larghezza disponibile.
  final bool expand;

  @override
  Widget build(BuildContext context) {
    return TvFocusable(
      focusNode: focusNode,
      autofocus: autofocus,
      onSelect: onPressed,
      builder: (context, focused) {
        final foreground = focused ? Colors.black : Colors.white;
        final background = focused
            ? Colors.white
            : (primary
                ? Brand.accentDeep
                : (selected ? Brand.accent.withValues(alpha: 0.35) : const Color(0x26FFFFFF)));
        return AnimatedContainer(
          duration: Perf.quick,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
          decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(6)),
          child: Row(
            mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 18, color: foreground),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, height: 1.2, color: foreground),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Stile dei campi di testo: bordo bianco quando sono selezionati, viola mentre si scrive.
InputDecoration tvInputDecoration({String? label, String? hint, IconData? icon, bool focused = false, bool editing = false}) {
  final color = editing ? Brand.accent : Colors.white;
  return InputDecoration(
    labelText: label,
    hintText: hint,
    hintStyle: const TextStyle(color: Color(0x80FFFFFF)),
    prefixIcon: icon == null ? null : Icon(icon, color: focused || editing ? Colors.white : const Color(0x99FFFFFF)),
    filled: true,
    fillColor: focused || editing ? const Color(0x26FFFFFF) : const Color(0x14FFFFFF),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    counterText: '',
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: focused ? BorderSide(color: color, width: 2) : const BorderSide(color: Color(0x33FFFFFF)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: color, width: 2),
    ),
  );
}
