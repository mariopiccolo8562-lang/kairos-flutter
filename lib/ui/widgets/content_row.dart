import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme.dart';

typedef RowItemBuilder = Widget Function(BuildContext context, int index, VoidCallback onFocused);

/// Fila orizzontale stile Netflix.
///
/// Costruisce solo gli elementi visibili e, quando un elemento prende il
/// focus, scorre con un'animazione morbida per tenerlo allineato a sinistra.
/// All'ultimo elemento la freccia ▶ non fa "saltare" il focus su un'altra fila.
/// La posizione della fila resta memorizzata anche quando esce dallo schermo.
class ContentRow extends StatefulWidget {
  const ContentRow({
    super.key,
    required this.title,
    required this.itemCount,
    required this.itemExtent,
    required this.height,
    required this.itemBuilder,
    this.storageId,
    this.onFocused,
    this.horizontalPadding = Layout.pagePadding,
  });

  final String title;
  final int itemCount;
  final double itemExtent;
  final double height;
  final RowItemBuilder itemBuilder;

  /// Identificativo per ricordare lo scorrimento della fila.
  final String? storageId;
  final VoidCallback? onFocused;
  final double horizontalPadding;

  @override
  State<ContentRow> createState() => _ContentRowState();
}

class _ContentRowState extends State<ContentRow> {
  final ScrollController _scroll = ScrollController();
  int _focused = -1;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _focusItem(int index) {
    _focused = index;
    widget.onFocused?.call();
    if (!_scroll.hasClients) return;
    final max = _scroll.position.maxScrollExtent;
    final target = (index * widget.itemExtent).clamp(0.0, max).toDouble();
    if ((target - _scroll.offset).abs() < 1) return;
    _scroll.animateTo(target, duration: const Duration(milliseconds: 220), curve: Curves.easeOutCubic);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
    // fine della fila: ▶ resta qui invece di finire su una locandina di un'altra fila
    if (event.logicalKey == LogicalKeyboardKey.arrowRight && _focused >= widget.itemCount - 1) {
      return node.hasFocus ? KeyEventResult.handled : KeyEventResult.ignored;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final id = widget.storageId;
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: _onKey,
      onFocusChange: (has) {
        if (!has) _focused = -1;
      },
      child: SizedBox(
        height: widget.height,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: Layout.rowTitleHeight,
              child: Padding(
                padding: EdgeInsets.only(left: widget.horizontalPadding, right: Layout.pageRight),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.rowTitle),
                ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                key: id == null ? null : PageStorageKey<String>('fila:$id'),
                controller: _scroll,
                scrollDirection: Axis.horizontal,
                padding: EdgeInsets.only(
                  left: widget.horizontalPadding,
                  right: Layout.pageRight,
                  top: Layout.rowPadding,
                  bottom: Layout.rowPadding,
                ),
                itemExtent: widget.itemExtent,
                itemCount: widget.itemCount,
                itemBuilder: (context, index) => Align(
                  alignment: Alignment.topLeft,
                  child: widget.itemBuilder(context, index, () => _focusItem(index)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
