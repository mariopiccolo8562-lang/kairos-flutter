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
  AppController _controller = AppController();
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _controller.start();
    _controller.remoteCmd.addListener(_onRemoteCmd);
  }

  /// Comandi del pannello che riguardano tutta l'app: riavvio (ricrea tutto, come riaprirla) e chiusura.
  void _onRemoteCmd() {
    final cmd = _controller.remoteCmd.value;
    if (cmd == 'reload') {
      _controller.remoteCmd.value = null;
      final old = _controller;
      old.remoteCmd.removeListener(_onRemoteCmd);
      setState(() {
        _controller = AppController();
        _generation++;
      });
      _controller.start();
      _controller.remoteCmd.addListener(_onRemoteCmd);
      old.dispose();
    } else if (cmd == 'exit') {
      _controller.remoteCmd.value = null;
      _controller.beforeExit().whenComplete(SystemNavigator.pop);
    }
  }

  @override
  void dispose() {
    _controller.remoteCmd.removeListener(_onRemoteCmd);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      key: ValueKey<int>(_generation),
      controller: _controller,
      child: MaterialApp(
        title: Brand.appName,
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        shortcuts: _shortcuts,
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

/// Il tasto centrale (OK) del telecomando invia "select": equivale a un clic.
/// Tenendolo premuto non deve ripetere il clic (si aprirebbero più schede una
/// sopra l'altra): OK, Invio e Spazio valgono una volta sola per pressione.
final Map<ShortcutActivator, Intent> _shortcuts = () {
  final activate = <LogicalKeyboardKey>{
    LogicalKeyboardKey.select,
    LogicalKeyboardKey.enter,
    LogicalKeyboardKey.numpadEnter,
    LogicalKeyboardKey.gameButtonA,
    LogicalKeyboardKey.space,
  };
  final map = <ShortcutActivator, Intent>{};
  WidgetsApp.defaultShortcuts.forEach((activator, intent) {
    if (activator is SingleActivator && activate.contains(activator.trigger)) return;
    map[activator] = intent;
  });
  for (final key in activate) {
    map[SingleActivator(key, includeRepeats: false)] = const ActivateIntent();
  }
  return map;
}();

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
