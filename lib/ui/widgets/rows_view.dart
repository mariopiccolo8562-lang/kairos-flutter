import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Una fila della pagina: altezza fissa nota in anticipo, così sappiamo
/// sempre dove si trova senza misurarla.
class RowSpec {
  const RowSpec({required this.height, required this.builder});

  final double height;
  final Widget Function(BuildContext context, VoidCallback onRowFocused) builder;
}

/// Elenco verticale di file. Quando una fila prende il focus, la pagina
/// scorre per portarla in alto, come nelle app TV di Netflix.
class RowsView extends StatefulWidget {
  const RowsView({super.key, required this.rows});

  final List<RowSpec> rows;

  @override
  State<RowsView> createState() => _RowsViewState();
}

class _RowsViewState extends State<RowsView> {
  final ScrollController _scroll = ScrollController();
  late List<double> _offsets = _computeOffsets();

  List<double> _computeOffsets() {
    final result = <double>[];
    var acc = 0.0;
    for (final row in widget.rows) {
      result.add(acc);
      acc += row.height;
    }
    return result;
  }

  @override
  void didUpdateWidget(RowsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _offsets = _computeOffsets();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _focusRow(int index) {
    if (!_scroll.hasClients || index >= _offsets.length) return;
    final target = _offsets[index].clamp(0.0, _scroll.position.maxScrollExtent).toDouble();
    if ((target - _scroll.offset).abs() < 1) return;
    _scroll.animateTo(target, duration: const Duration(milliseconds: 260), curve: Curves.easeOutCubic);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Spazio in fondo: anche l'ultima fila può salire in cima.
        final last = widget.rows.isEmpty ? 0.0 : widget.rows.last.height;
        final bottom = math.max(0.0, constraints.maxHeight - last);
        return ListView.builder(
          controller: _scroll,
          padding: EdgeInsets.only(bottom: bottom),
          itemCount: widget.rows.length,
          itemBuilder: (context, index) {
            final row = widget.rows[index];
            return SizedBox(height: row.height, child: row.builder(context, () => _focusRow(index)));
          },
        );
      },
    );
  }
}
