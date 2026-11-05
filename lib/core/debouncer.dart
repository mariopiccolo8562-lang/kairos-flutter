import 'dart:async';

import 'package:flutter/foundation.dart';

/// Esegue un'azione solo quando gli eventi si fermano per [delay].
/// Serve a non fare lavoro inutile mentre l'utente scorre veloce col telecomando.
class Debouncer {
  Debouncer(this.delay);

  final Duration delay;
  Timer? _timer;

  void run(VoidCallback action) {
    _timer?.cancel();
    _timer = Timer(delay, action);
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
  }
}
