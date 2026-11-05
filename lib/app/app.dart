import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../state/app_controller.dart';
import '../ui/screens/bootstrap_screen.dart';
import 'app_scope.dart';
import 'brand.dart';
import 'theme.dart';

class StreamingApp extends StatefulWidget {
  const StreamingApp({super.key});

  @override
  State<StreamingApp> createState() => _StreamingAppState();
}

class _StreamingAppState extends State<StreamingApp> {
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
        builder: (context, child) => FocusTraversalGroup(
          policy: ReadingOrderTraversalPolicy(requestFocusCallback: _moveFocusOnly),
          child: child ?? const SizedBox.shrink(),
        ),
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
