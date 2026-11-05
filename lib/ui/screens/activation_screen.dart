import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/brand.dart';
import '../../app/theme.dart';
import '../../state/app_controller.dart';
import '../navigation.dart';
import '../widgets/brand_mark.dart';
import '../widgets/tv_button.dart';

/// Prima schermata, come nelle altre app Kairos: mostra il codice della TV
/// e aspetta che il fornitore la attivi dal pannello (si sblocca da sola).
/// In alternativa si collega la TV a un abbonamento già attivo con il codice
/// a 6 cifre generato da un'altra TV.
class ActivationScreen extends StatefulWidget {
  const ActivationScreen({super.key});

  @override
  State<ActivationScreen> createState() => _ActivationScreenState();
}

class _ActivationScreenState extends State<ActivationScreen> {
  bool _privacyShown = false;
  bool _busy = false;
  late final AppController _app = AppScope.of(context);

  @override
  void initState() {
    super.initState();
    _app.activation.addListener(_maybeShowPrivacy);
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShowPrivacy());
  }

  @override
  void dispose() {
    _app.activation.removeListener(_maybeShowPrivacy);
    super.dispose();
  }

  /// Al primo avvio si mostrano privacy e condizioni del fornitore.
  Future<void> _maybeShowPrivacy() async {
    final app = AppScope.of(context);
    final info = app.activation.value;
    if (_privacyShown || app.privacyOk || !mounted) return;
    if (info.status == 'checking' || info.status == 'maintenance' || info.status == 'offline') return;
    _privacyShown = true;
    await _showPrivacy();
  }

  Future<void> _showPrivacy() async {
    final app = AppScope.of(context);
    final text = await app.privacyText();
    if (!mounted) return;
    await showTvMessage(context, title: 'Privacy e condizioni', message: text, button: 'Ho capito');
    await app.acceptPrivacy();
  }

  Future<void> _link() async {
    if (_busy) return;
    final app = AppScope.of(context);
    final pin = await showPinInput(
      context,
      title: 'Collega a un abbonamento attivo',
      hint: 'Sulla TV già attiva apri Impostazioni → «Collega un\'altra TV» e scrivi qui il codice a 6 cifre.',
    );
    if (pin == null || !mounted) return;
    final digits = pin.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length != 6) {
      await showTvMessage(context, title: 'Codice non valido', message: 'Il codice è di 6 cifre.');
      return;
    }
    setState(() => _busy = true);
    final error = await app.linkWithPin(digits);
    if (!mounted) return;
    setState(() => _busy = false);
    if (error != null) await showTvMessage(context, title: 'Collegamento non riuscito', message: error);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return Scaffold(
      body: ValueListenableBuilder<ActivationInfo>(
        valueListenable: app.activation,
        builder: (context, info, child) {
          final maintenance = info.status == 'maintenance';
          return Padding(
            padding: const EdgeInsets.fromLTRB(56, 40, 56, 32),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const BrandMark(size: 44),
                      const Spacer(),
                      Text(
                        maintenance ? 'Manutenzione in corso.' : 'Attiva la tua TV.',
                        style: AppText.display.copyWith(fontSize: 34),
                      ),
                      const SizedBox(height: 14),
                      const SizedBox(
                        width: 400,
                        child: Text(
                          'Comunica il codice al tuo rivenditore. Appena attiva l\'abbonamento, '
                          'l\'app si sblocca da sola: non devi scrivere niente.',
                          style: TextStyle(fontSize: 15, height: 1.4, color: Color(0xCCFFFFFF)),
                        ),
                      ),
                      const Spacer(),
                      Row(
                        children: [
                          TvButton(label: 'Privacy e condizioni', onPressed: _showPrivacy),
                          const SizedBox(width: 16),
                          Flexible(
                            child: Text(
                              '${Brand.appName} ${app.appVersion}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.small,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 32),
                SizedBox(
                  width: 380,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Brand.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0x22FFFFFF)),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'CODICE DI ATTIVAZIONE',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.4,
                              color: Color(0xB3FFFFFF),
                            ),
                          ),
                          if (!maintenance) ...[
                            const SizedBox(height: 12),
                            Container(
                              height: 80,
                              width: double.infinity,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(colors: [Color(0xFF2A1250), Color(0xFF1A0C33)]),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Brand.accent.withValues(alpha: 0.6), width: 1.5),
                              ),
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  app.deviceCode,
                                  maxLines: 1,
                                  style: const TextStyle(
                                    fontSize: 36,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 3,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(height: 16),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 10,
                                height: 10,
                                margin: const EdgeInsets.only(top: 4),
                                decoration: BoxDecoration(
                                  color: info.warn ? const Color(0xFFFF5A5F) : Brand.accent,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  _busy ? 'Collegamento in corso…' : info.message,
                                  style: const TextStyle(fontSize: 13.5, height: 1.35, color: Color(0xDDFFFFFF)),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),
                          const Divider(height: 1, color: Color(0x22FFFFFF)),
                          const SizedBox(height: 16),
                          const Text(
                            'Hai già un\'altra TV attiva con Kairos?',
                            style: TextStyle(fontSize: 13, color: Color(0xB3FFFFFF)),
                          ),
                          const SizedBox(height: 10),
                          TvButton(
                            label: 'Collega con codice a 6 cifre',
                            icon: Icons.link_rounded,
                            primary: true,
                            expand: true,
                            autofocus: true,
                            onPressed: _link,
                          ),
                          if (info.warn) ...[
                            const SizedBox(height: 10),
                            TvButton(
                              label: 'Riprova adesso',
                              icon: Icons.refresh_rounded,
                              expand: true,
                              onPressed: app.retryActivationNow,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
