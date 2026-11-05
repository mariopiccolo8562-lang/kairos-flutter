import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../state/app_controller.dart';
import '../ui/screens/bootstrap_screen.dart';
import 'app_scope.dart';
import 'brand.dart';
import 'theme.dart';

class KairosPlusApp extends StatefulWidget {
  const KairosPlusApp({super.key});

  @override
  State<KairosPlusApp> createState() => _KairosPlusAppState();
}

class _KairosPlusAppState extends State<KairosPlusApp> {
  final AppController _controller = AppController();

  @override
  void initState() {
    super.initState();
    _controller.start();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      controller: _controller,
      child: MaterialApp(
        title: Brand.appName,
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        // Il tasto centrale (OK) del telecomando invia "select": equivale a un clic.
        shortcuts: <ShortcutActivator, Intent>{
          ...WidgetsApp.defaultShortcuts,
          const SingleActivator(LogicalKeyboardKey.select): const ActivateIntent(),
        },
        builder: (context, child) {
          // Misure fisse da TV: la dimensione del testo di sistema non deve
          // ingrandire le scritte (testi tagliati, elementi sovrapposti).
          final media = MediaQuery.of(context);
          return MediaQuery(
            data: media.copyWith(textScaler: TextScaler.noScaling),
            child: FocusTraversalGroup(
              policy: ReadingOrderTraversalPolicy(requestFocusCallback: _moveFocusOnly),
              child: child ?? const SizedBox.shrink(),
            ),
          );
        },
        home: const BootstrapScreen(),
      ),
    );
  }
}

/// Con le frecce Flutter sposterebbe il focus e farebbe "saltare" le liste.
/// Qui spostiamo solo il focus: lo scorrimento animato lo gestiscono le
/// liste stesse (file di locandine, menu, elenchi canali).
void _moveFocusOnly(
  FocusNode node, {
  ScrollPositionAlignmentPolicy? alignmentPolicy,
  double? alignment,
  Duration? duration,
  Curve? curve,
}) {
  node.requestFocus();
}
