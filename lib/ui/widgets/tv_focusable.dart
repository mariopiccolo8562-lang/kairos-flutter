import 'package:flutter/material.dart';

typedef FocusBuilder = Widget Function(BuildContext context, bool focused);

/// Base di ogni elemento selezionabile col telecomando.
///
/// Ridisegna solo sé stesso quando prende o perde il focus e risponde
/// al tasto OK. Con [autoScroll] porta l'elemento in vista nelle liste
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
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return FocusableActionDetector(
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      onFocusChange: _handleFocusChange,
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (intent) {
            widget.onSelect?.call();
            return null;
          },
        ),
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onSelect,
        child: widget.builder(context, _focused),
      ),
    );
  }
}
