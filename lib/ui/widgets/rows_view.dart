import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Una fila della pagina: altezza fissa nota in anticipo, così sappiamo
/// sempre dove si trova senza misurarla. [id] la identifica anche se
/// cambia posizione (es. compare «Continua a guardare»): il focus non salta.
class RowSpec {
  const RowSpec({required this.id, required this.height, required this.builder});

  final String id;
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
  late Map<String, int> _indexById = _computeIndex();
  String? _focusedRow;

  List<double> _computeOffsets() {
    final result = <double>[];
    var acc = 0.0;
    for (final row in widget.rows) {
      result.add(acc);
      acc += row.height;
    }
    return result;
  }

  Map<String, int> _computeIndex() => {for (var i = 0; i < widget.rows.length; i++) widget.rows[i].id: i};

  @override
  void didUpdateWidget(RowsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final before = _focusedRow == null ? null : _offsetOf(_focusedRow!);
    _offsets = _computeOffsets();
    _indexById = _computeIndex();
    final focused = _focusedRow;
    if (focused == null) return;
    final after = _offsetOf(focused);
    // una fila è comparsa o sparita sopra quella attuale: la pagina la segue senza scatti
    if (before != null && after != null && before != after) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scroll.hasClients) return;
        _scroll.jumpTo(after.clamp(0.0, _scroll.position.maxScrollExtent).toDouble());
      });
    }
  }

  double? _offsetOf(String id) {
    final i = _indexById[id];
    return i == null || i >= _offsets.length ? null : _offsets[i];
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _focusRow(int index) {
    if (index >= widget.rows.length) return;
    _focusedRow = widget.rows[index].id;
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
          findChildIndexCallback: (key) => key is ValueKey<String> ? _indexById[key.value] : null,
          itemBuilder: (context, index) {
            final row = widget.rows[index];
            return SizedBox(
              key: ValueKey<String>(row.id),
              height: row.height,
              child: row.builder(context, () => _focusRow(index)),
            );
          },
        );
      },
    );
  }
}
