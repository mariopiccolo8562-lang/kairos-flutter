import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/theme.dart';
import '../../state/app_controller.dart';
import '../shell/main_shell.dart';
import '../widgets/brand_mark.dart';
import '../widgets/tv_button.dart';
import 'activation_screen.dart';

/// Decide cosa mostrare in base allo stato: avvio, attivazione, caricamento, errore o app.
class BootstrapScreen extends StatelessWidget {
  const BootstrapScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    // la grafica (leggera o completa) cambiata dalle Impostazioni ricostruisce l'interfaccia
    return ListenableBuilder(
      listenable: Listenable.merge([app.status, app.uiRevision]),
      builder: (context, child) => switch (app.status.value) {
        SessionStatus.starting => const SplashView(),
        SessionStatus.loading => const SplashView(message: 'Carico canali, film e serie…'),
        SessionStatus.activation => const ActivationScreen(),
        SessionStatus.error => _StartupError(
            message: app.startupError ?? 'Errore sconosciuto',
            onRetry: app.retryStartup,
          ),
        SessionStatus.ready => MainShell(key: ValueKey<int>(app.uiRevision.value)),
      },
    );
  }
}

class SplashView extends StatelessWidget {
  const SplashView({super.key, this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    final text = message;
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const BrandMark(size: 64),
            const SizedBox(height: 30),
            const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 3)),
            if (text != null) ...[
              const SizedBox(height: 14),
              Text(text, style: AppText.meta),
            ],
          ],
        ),
      ),
    );
  }
}

class _StartupError extends StatelessWidget {
  const _StartupError({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SizedBox(
          width: 560,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const BrandMark(size: 48),
              const SizedBox(height: 24),
              const Icon(Icons.cloud_off_rounded, size: 48, color: Colors.white54),
              const SizedBox(height: 12),
              const Text('Non riesco a caricare i contenuti', style: AppText.title),
              const SizedBox(height: 8),
              Text(message, textAlign: TextAlign.center, style: AppText.body),
              const SizedBox(height: 24),
              TvButton(icon: Icons.refresh_rounded, label: 'Riprova', autofocus: true, onPressed: onRetry),
            ],
          ),
        ),
      ),
    );
  }
}
