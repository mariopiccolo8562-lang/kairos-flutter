import 'package:flutter/material.dart';

import '../../app/theme.dart';

typedef RowItemBuilder = Widget Function(BuildContext context, int index, VoidCallback onFocused);

/// Fila orizzontale stile Netflix.
///
/// Costruisce solo gli elementi visibili e, quando un elemento prende il
/// focus, scorre con un'animazione morbida per tenerlo allineato a sinistra.
class ContentRow extends StatefulWidget {
  const ContentRow({
    super.key,
    required this.title,
    required this.itemCount,
    required this.itemExtent,
    required this.height,
    required this.itemBuilder,
    this.onFocused,
    this.horizontalPadding = Layout.pagePadding,
  });

  final String title;
  final int itemCount;
  final double itemExtent;
  final double height;
  final RowItemBuilder itemBuilder;
  final VoidCallback? onFocused;
  final double horizontalPadding;

  @override
  State<ContentRow> createState() => _ContentRowState();
}

class _ContentRowState extends State<ContentRow> {
  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _focusItem(int index) {
    widget.onFocused?.call();
    if (!_scroll.hasClients) return;
    final max = _scroll.position.maxScrollExtent;
    final target = (index * widget.itemExtent).clamp(0.0, max).toDouble();
    if ((target - _scroll.offset).abs() < 1) return;
    _scroll.animateTo(target, duration: const Duration(milliseconds: 220), curve: Curves.easeOutCubic);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: Layout.rowTitleHeight,
            child: Padding(
              padding: EdgeInsets.only(left: widget.horizontalPadding),
              child: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.rowTitle),
            ),
          ),
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.symmetric(horizontal: widget.horizontalPadding, vertical: Layout.rowPadding),
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
    );
  }
}
