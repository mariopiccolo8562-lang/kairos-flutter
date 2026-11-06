import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'tv_button.dart';
import 'tv_focusable.dart';

/// Campo di testo pensato per il telecomando.
///
/// - Le frecce ci passano sopra senza aprire la tastiera (niente tastiera che
///   compare da sola e "ruba" il telecomando).
/// - OK apre la tastiera; mentre si scrive ▲▼ escono dal campo, ◀▶ muovono il cursore.
/// - Invio sulla tastiera o Indietro chiudono la scrittura e restano sul campo.
class TvTextField extends StatefulWidget {
  const TvTextField({
    super.key,
    required this.controller,
    this.focusNode,
    this.hint,
    this.icon,
    this.keyboardType,
    this.textInputAction,
    this.onChanged,
    this.onSubmitted,
    this.autofocus = false,
    this.openOnStart = false,
    this.maxLength,
    this.style,
    this.textAlign = TextAlign.start,
  });

  final TextEditingController controller;
  final FocusNode? focusNode;
  final String? hint;
  final IconData? icon;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool autofocus;

  /// Apre subito la tastiera (es. finestra per il codice a 6 cifre).
  final bool openOnStart;
  final int? maxLength;
  final TextStyle? style;
  final TextAlign textAlign;

  /// True se [node] è un campo mentre si scrive (le frecce ◀▶ muovono il cursore).
  static bool isEditing(FocusNode? node) => node != null && _TvTextFieldState._byInner[node] != null;

  /// Indietro mentre si scrive: si chiude la scrittura restando sul campo.
  /// Restituisce true se il tasto è stato usato così.
  static bool handleBack() {
    final focused = FocusManager.instance.primaryFocus;
    final state = focused == null ? null : _TvTextFieldState._byInner[focused];
    if (state == null) return false;
    state._stopEditing();
    return true;
  }

  @override
  State<TvTextField> createState() => _TvTextFieldState();
}

class _TvTextFieldState extends State<TvTextField> {
  static final Expando<_TvTextFieldState> _byInner = Expando<_TvTextFieldState>();

  late final FocusNode _outer = widget.focusNode ?? FocusNode(debugLabel: 'campo');
  final FocusNode _inner = FocusNode(debugLabel: 'scrittura', skipTraversal: true, canRequestFocus: false);
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    _byInner[_inner] = this;
    _inner.addListener(_onInnerFocus);
    if (widget.openOnStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _startEditing();
      });
    }
  }

  @override
  void dispose() {
    _inner.removeListener(_onInnerFocus);
    _inner.dispose();
    if (widget.focusNode == null) _outer.dispose();
    super.dispose();
  }

  void _onInnerFocus() {
    if (!_inner.hasFocus && _editing) {
      _inner.canRequestFocus = false;
      if (mounted) setState(() => _editing = false);
    }
  }

  void _startEditing() {
    _inner.canRequestFocus = true;
    setState(() => _editing = true);
    if (_inner.hasFocus) {
      // già nel campo (tastiera chiusa con Indietro): la si riapre
      SystemChannels.textInput.invokeMethod<void>('TextInput.show');
    } else {
      _inner.requestFocus();
    }
  }

  void _stopEditing() {
    _outer.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    return TvFocusable(
      focusNode: _outer,
      autofocus: widget.autofocus,
      onSelect: _startEditing,
      builder: (context, focused) => Shortcuts(
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.arrowDown): DirectionalFocusIntent(TraversalDirection.down, ignoreTextFields: false),
          SingleActivator(LogicalKeyboardKey.arrowUp): DirectionalFocusIntent(TraversalDirection.up, ignoreTextFields: false),
        },
        child: IgnorePointer(
          ignoring: !_editing,
          child: TextField(
            focusNode: _inner,
            controller: widget.controller,
            keyboardType: widget.keyboardType,
            textInputAction: widget.textInputAction ?? TextInputAction.done,
            maxLength: widget.maxLength,
            textAlign: widget.textAlign,
            style: widget.style ?? const TextStyle(fontSize: 18, color: Colors.white),
            onChanged: widget.onChanged,
            onSubmitted: (value) {
              widget.onSubmitted?.call(value);
              if (mounted) _stopEditing();
            },
            decoration: tvInputDecoration(hint: widget.hint, icon: widget.icon, focused: focused && !_editing, editing: _editing),
          ),
        ),
      ),
    );
  }
}
