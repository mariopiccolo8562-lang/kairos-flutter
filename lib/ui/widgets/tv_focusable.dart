import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/perf.dart';

typedef FocusBuilder = Widget Function(BuildContext context, bool focused);

/// Base di ogni elemento selezionabile col telecomando.
///
/// Leggero apposta (un solo Focus, niente azioni e mouse): nelle file da
/// centinaia di locandine conta. Ridisegna solo sé stesso quando prende o
/// perde il focus e risponde a OK una volta per pressione (tenendolo premuto
/// non ripete). Con [autoScroll] porta l'elemento in vista nelle liste
/// normali; le file di locandine gestiscono lo scorrimento da sole.
class TvFocusable extends StatefulWidget {
  const TvFocusable({
    super.key,
    required this.builder,
    this.onSelect,
    this.onFocusChange,
    this.focusNode,
    this.autofocus = false,
    this.autoScroll = true,
    this.scrollAlignment = 0.5,
  });

  final FocusBuilder builder;
  final VoidCallback? onSelect;
  final ValueChanged<bool>? onFocusChange;
  final FocusNode? focusNode;
  final bool autofocus;
  final bool autoScroll;
  final double scrollAlignment;

  /// Tasti che valgono come «OK».
  static bool isOk(LogicalKeyboardKey key) =>
      key == LogicalKeyboardKey.select ||
      key == LogicalKeyboardKey.enter ||
      key == LogicalKeyboardKey.numpadEnter ||
      key == LogicalKeyboardKey.gameButtonA;

  @override
  State<TvFocusable> createState() => _TvFocusableState();
}

class _TvFocusableState extends State<TvFocusable> {
  bool _focused = false;

  void _handleFocusChange(bool focused) {
    if (focused != _focused) setState(() => _focused = focused);
    widget.onFocusChange?.call(focused);
    if (focused && widget.autoScroll) {
      Scrollable.ensureVisible(
        context,
        alignment: widget.scrollAlignment,
        duration: Perf.lite ? Duration.zero : const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
      );
    }
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (!TvFocusable.isOk(event.logicalKey)) return KeyEventResult.ignored;
    if (event is KeyDownEvent) {
      final onSelect = widget.onSelect;
      if (onSelect == null) return KeyEventResult.ignored;
      onSelect();
      return KeyEventResult.handled;
    }
    // ripetizioni e rilascio di OK: già gestiti dalla pressione
    return widget.onSelect == null ? KeyEventResult.ignored : KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      onFocusChange: _handleFocusChange,
      onKeyEvent: _handleKey,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onSelect,
        child: widget.builder(context, _focused),
      ),
    );
  }
}
