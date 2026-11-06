import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/app_scope.dart';
import '../app/brand.dart';
import '../app/theme.dart';
import '../data/models.dart';
import '../state/app_updater.dart';
import 'screens/details_screen.dart';
import 'widgets/tv_button.dart';
import 'widgets/tv_focusable.dart';
import 'widgets/tv_text_field.dart';

Future<void> openDetails(BuildContext context, MediaItem item) {
  return Navigator.of(context).push(
    PageRouteBuilder<void>(
      transitionDuration: const Duration(milliseconds: 200),
      reverseTransitionDuration: const Duration(milliseconds: 140),
      pageBuilder: (context, animation, secondaryAnimation) => DetailsScreen(item: item),
      transitionsBuilder: (context, animation, secondaryAnimation, child) =>
          FadeTransition(opacity: animation, child: child),
    ),
  );
}

/// Apre il lettore nativo a schermo intero. Se il pannello non consente la
/// visione (limite di visioni contemporanee) mostra il motivo.
Future<void> playItems(
  BuildContext context,
  List<PlaybackItem> items,
  int index, {
  Duration? resumeAt,
}) async {
  if (items.isEmpty) return;
  final app = AppScope.of(context);
  final message = await app.play(items, index, resumeAt: resumeAt);
  if (message != null && context.mounted) {
    await showTvMessage(context, title: 'Visione non disponibile', message: message);
  }
}

/// Le finestre si aprono sopra l'interfaccia: il video dell'anteprima (nativo) si ferma prima.
void _pausePreview(BuildContext context) => AppScope.of(context).stopPreview();

Widget _dialogFrame({required Widget child, double width = 440}) {
  return Dialog(
    backgroundColor: Brand.surface,
    insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: SizedBox(width: width, child: child),
    ),
  );
}

/// Finestra di conferma utilizzabile col telecomando ("Annulla" già selezionato).
Future<bool> showTvConfirm(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
}) async {
  _pausePreview(context);
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => _dialogFrame(
      width: 420,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppText.title),
          const SizedBox(height: 10),
          Text(message, style: AppText.body),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TvButton(label: 'Annulla', autofocus: true, onPressed: () => Navigator.of(context).pop(false)),
              const SizedBox(width: 12),
              TvButton(label: confirmLabel, onPressed: () => Navigator.of(context).pop(true)),
            ],
          ),
        ],
      ),
    ),
  );
  return result ?? false;
}

/// Messaggio con un solo pulsante. Il testo lungo scorre con ▲▼.
Future<void> showTvMessage(
  BuildContext context, {
  required String title,
  required String message,
  String button = 'Ok',
}) {
  _pausePreview(context);
  final scroll = ScrollController();
  return showDialog<void>(
    context: context,
    builder: (context) => _dialogFrame(
      width: 480,
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onKeyEvent: (node, event) {
          if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
          final down = event.logicalKey == LogicalKeyboardKey.arrowDown;
          final up = event.logicalKey == LogicalKeyboardKey.arrowUp;
          if ((!down && !up) || !scroll.hasClients) return KeyEventResult.ignored;
          final pos = scroll.position;
          final target = (pos.pixels + (down ? 80 : -80)).clamp(0.0, pos.maxScrollExtent).toDouble();
          scroll.animateTo(target, duration: const Duration(milliseconds: 140), curve: Curves.easeOut);
          return KeyEventResult.handled;
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: AppText.title),
            const SizedBox(height: 10),
            Flexible(
              child: SingleChildScrollView(
                controller: scroll,
                child: Text(message, style: AppText.body),
              ),
            ),
            const SizedBox(height: 20),
            Align(
              alignment: Alignment.centerRight,
              child: TvButton(label: button, autofocus: true, onPressed: () => Navigator.of(context).pop()),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Codice grande da leggere sullo schermo (es. per collegare un'altra TV).
Future<void> showTvCode(BuildContext context, {required String title, required String code, required String message}) {
  _pausePreview(context);
  return showDialog<void>(
    context: context,
    builder: (context) => _dialogFrame(
      width: 460,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppText.title),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 18),
            decoration: BoxDecoration(color: const Color(0x14FFFFFF), borderRadius: BorderRadius.circular(10)),
            child: Text(
              code,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w900, letterSpacing: 6, color: Colors.white),
            ),
          ),
          const SizedBox(height: 14),
          Text(message, style: AppText.body),
          const SizedBox(height: 20),
          Align(
            alignment: Alignment.centerRight,
            child: TvButton(label: 'Fatto', autofocus: true, onPressed: () => Navigator.of(context).pop()),
          ),
        ],
      ),
    ),
  );
}

/// Scelta da un elenco (es. la playlist da usare). Restituisce l'indice scelto.
Future<int?> showTvChoice(BuildContext context, {required String title, required List<String> options, int selected = -1}) {
  _pausePreview(context);
  return showDialog<int>(
    context: context,
    builder: (context) => _dialogFrame(
      width: 420,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppText.title),
          const SizedBox(height: 14),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: options.length,
              itemBuilder: (context, i) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: TvFocusable(
                  autofocus: i == (selected < 0 ? 0 : selected),
                  onSelect: () => Navigator.of(context).pop(i),
                  builder: (context, focused) => Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                    decoration: BoxDecoration(
                      color: focused ? Colors.white : const Color(0x14FFFFFF),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            options[i],
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: focused ? Colors.black : Colors.white,
                            ),
                          ),
                        ),
                        if (i == selected)
                          Icon(Icons.check_rounded, size: 20, color: focused ? Colors.black : Brand.accent),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

/// Richiesta del codice a 6 cifre: la tastiera numerica si apre subito.
Future<String?> showPinInput(BuildContext context, {required String title, required String hint}) {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (context) {
      void submit() => Navigator.of(context).pop(controller.text.trim());
      return _dialogFrame(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: AppText.title),
            const SizedBox(height: 8),
            Text(hint, style: AppText.body),
            const SizedBox(height: 16),
            TvTextField(
              controller: controller,
              autofocus: true,
              openOnStart: true,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
              maxLength: 6,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: 8, color: Colors.white),
              hint: '······',
              onSubmitted: (value) {
                if (value.trim().length == 6) submit();
              },
            ),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TvButton(label: 'Annulla', onPressed: () => Navigator.of(context).pop()),
                const SizedBox(width: 12),
                TvButton(label: 'Collega', primary: true, onPressed: submit),
              ],
            ),
          ],
        ),
      );
    },
  );
}

/// Propone la versione nuova dell'app: «Installa ora» se l'APK è già scaricato in background,
/// altrimenti «Aggiorna ora» con l'avanzamento del download. Android chiede poi la sua conferma.
Future<void> showUpdateDialog(BuildContext context, AppUpdater updater) async {
  final u = updater.pending;
  if (u == null) return;
  _pausePreview(context);
  final ready = updater.ready;
  final go = await showTvConfirm(
    context,
    title: ready ? 'Aggiornamento ${u.version} pronto' : 'Nuova versione ${u.version}',
    message: ready
        ? 'La versione nuova di Kairos Plus è già scaricata e verificata: premi Installa e conferma nella schermata di Android. Ci vuole meno di un minuto.'
        : 'Contiene miglioramenti e correzioni. Il download richiede pochi secondi, poi conferma l\'installazione nella schermata di Android.',
    confirmLabel: ready ? 'Installa ora' : 'Aggiorna ora',
  );
  if (!go || !context.mounted) return;
  await updater.install();
  if (ready || !context.mounted) return;
  // download richiesto dal cliente: avanzamento fino all'apertura dell'installer (o all'errore)
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => ListenableBuilder(
      listenable: updater,
      builder: (context, child) {
        final p = updater.progress;
        final done = p < 0;
        return PopScope(
          canPop: done,
          child: _dialogFrame(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Aggiornamento', style: AppText.title),
                const SizedBox(height: 14),
                LinearProgressIndicator(value: done ? null : p / 100, color: Brand.accent, backgroundColor: Brand.card),
                const SizedBox(height: 10),
                Text(done ? (updater.message ?? '') : 'Download $p%', style: AppText.body),
                if (done) ...[
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [TvButton(label: 'Ok', autofocus: true, onPressed: () => Navigator.of(context).pop())],
                  ),
                ],
              ],
            ),
          ),
        );
      },
    ),
  );
}
