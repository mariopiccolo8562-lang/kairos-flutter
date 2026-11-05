import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/theme.dart';
import '../../state/app_controller.dart';
import '../shell/main_shell.dart';
import '../widgets/brand_mark.dart';
import '../widgets/tv_button.dart';
import 'login_screen.dart';

/// Decide cosa mostrare in base allo stato: avvio, accesso, errore o app.
class BootstrapScreen extends StatelessWidget {
  const BootstrapScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return ValueListenableBuilder<SessionStatus>(
      valueListenable: app.status,
      builder: (context, status, child) => switch (status) {
        SessionStatus.starting => const SplashView(),
        SessionStatus.loading => const SplashView(message: 'Carico il catalogo…'),
        SessionStatus.loggedOut => const LoginScreen(),
        SessionStatus.error => _StartupError(
            message: app.startupError ?? 'Errore sconosciuto',
            onRetry: app.retryStartup,
            onLogout: app.logout,
          ),
        SessionStatus.ready => const MainShell(),
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
            const BrandMark(fontSize: 44),
            const SizedBox(height: 28),
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
  const _StartupError({required this.message, required this.onRetry, required this.onLogout});

  final String message;
  final Future<void> Function() onRetry;
  final Future<void> Function() onLogout;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const BrandMark(fontSize: 32),
              const SizedBox(height: 24),
              const Icon(Icons.cloud_off_rounded, size: 48, color: Colors.white54),
              const SizedBox(height: 12),
              const Text('Non riesco a caricare il catalogo', style: AppText.title),
              const SizedBox(height: 8),
              Text(message, textAlign: TextAlign.center, style: AppText.body),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TvButton(icon: Icons.refresh_rounded, label: 'Riprova', autofocus: true, onPressed: onRetry),
                  const SizedBox(width: 12),
                  TvButton(icon: Icons.logout_rounded, label: 'Cambia account', onPressed: onLogout),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
