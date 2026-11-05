import 'package:flutter/widgets.dart';

import '../state/app_controller.dart';

/// Rende disponibile l'AppController a tutta l'app.
///
/// Non crea dipendenze di ricostruzione: ogni schermata ascolta solo
/// i dati che le servono (catalogo, preferiti, progressi…), così un
/// cambiamento non ridisegna tutto.
class AppScope extends InheritedWidget {
  const AppScope({super.key, required this.controller, required super.child});

  final AppController controller;

  static AppController of(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope non trovato sopra questo widget');
    return scope!.controller;
  }

  @override
  bool updateShouldNotify(AppScope oldWidget) => controller != oldWidget.controller;
}
