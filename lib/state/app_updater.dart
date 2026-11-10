import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../core/json.dart';
import '../core/native.dart';
import '../core/net.dart' as net;

/// Versione nuova trovata nel feed degli aggiornamenti.
class UpdateInfo {
  const UpdateInfo({required this.code, required this.version, required this.url, this.mirrors});

  final int code;
  final String version;
  final String url;

  /// Domini di riserva annunciati dal feed («mirrors», vedi [feedMirrors]); null = il feed non ne parla.
  final List<String>? mirrors;
}

// Da dove arrivano il feed e l'APK (dal 10 novembre 2026 niente più pannello né GitHub negli aggiornamenti):
// 1. il dominio dei download Brand.dlBase (https://store-k.download): se non risponde si passa in fretta alla base dopo;
// 2. le riserve, con gli stessi percorsi `/get/<id>.json` e `/get/<id>.apk`: Brand.dlBase2 (variabile KAIROS_DL_BASE2
//    del repository, vuota finché non c'è un secondo dominio) e i domini che il feed annuncia in «mirrors» (l'app li
//    ricorda: un dominio di riserva comprato dopo arriva anche alle app già installate, senza una versione nuova).

/// Base dei download valida: solo https e solo il dominio (porta facoltativa), senza percorso.
final RegExp _kBase = RegExp(r'^https://[a-z0-9.-]+\.[a-z]{2,}(:\d{1,5})?$', caseSensitive: false);

String _trimBase(String base) {
  var b = base.trim();
  while (b.endsWith('/')) {
    b = b.substring(0, b.length - 1);
  }
  return b;
}

/// Basi https valide da [list], in ordine e senza doppioni, al massimo [max].
List<String> _validBases(Iterable<String> list, int max) {
  final out = <String>[];
  for (final base in list) {
    final b = _trimBase(base);
    if (_kBase.hasMatch(b) && !out.contains(b)) out.add(b);
    if (out.length >= max) break;
  }
  return out;
}

/// Basi https dei download, in ordine e senza doppioni: [dlBase] (Brand.dlBase, il dominio dedicato ai download), poi
/// le riserve [extra] (Brand.dlBase2 e i domini annunciati dal feed); al massimo 4.
List<String> downloadBases(String dlBase, [List<String> extra = const []]) => _validBases([dlBase, ...extra], 4);

/// Feed degli aggiornamenti da provare, in ordine: `/get/<id>.json` su ogni base ([downloadBases]).
List<String> updateFeeds(String dlBase, String id, [List<String> extra = const []]) =>
    [for (final b in downloadBases(dlBase, extra)) '$b/get/$id.json'];

/// APK da provare, in ordine: [url], il link del feed che ha risposto; poi lo stesso APK (`/get/<id>.apk`) sulle basi
/// successive a quella del link. Un link fuori dalle basi passa a tutte le basi.
List<String> apkUrls(String url, String dlBase, String id, [List<String> extra = const []]) {
  final out = <String>[];
  if (url.startsWith('https://')) out.add(url);
  final bases = downloadBases(dlBase, extra);
  final at = bases.indexWhere((b) => url.startsWith('$b/'));
  for (final b in at >= 0 ? bases.skip(at + 1) : bases) {
    final u = '$b/get/$id.apk';
    if (!out.contains(u)) out.add(u);
  }
  return out;
}

/// Domini di riserva annunciati dal feed («mirrors»): solo https validi, senza doppioni, al massimo 3.
/// null = il feed non ha la lista (quelli già ricordati restano); lista vuota = nessuna riserva.
List<String>? feedMirrors(Object? raw) {
  final list = asMap(raw)['mirrors'];
  if (list is! List) return null;
  return _validBases(list.whereType<String>(), 3);
}

/// Legge un feed con un client suo, così un indirizzo che non risponde non tocca le connessioni del catalogo:
/// connessione al massimo 5 s (un dominio non attivo fa passare in fretta alla base successiva), risposta
/// al massimo 10 s e 256 KB. Il JSON se la risposta è 200, altrimenti null; HTML o JSON rotto: FormatException.
Future<Object?> fetchFeedJson(Uri uri) async {
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 5)
    ..userAgent = net.userAgent;
  try {
    final request = await client.getUrl(uri).timeout(const Duration(seconds: 10));
    final response = await request.close().timeout(const Duration(seconds: 10));
    if (response.statusCode != HttpStatus.ok) return null;
    final bytes = <int>[];
    await for (final chunk in response.timeout(const Duration(seconds: 10))) {
      bytes.addAll(chunk);
      if (bytes.length > 256 * 1024) return null;
    }
    return jsonDecode(utf8.decode(bytes, allowMalformed: true));
  } finally {
    client.close(force: true);
  }
}

/// Versione descritta da un feed (version, versionCode, url): null se il JSON non è valido
/// (versione non riconosciuta o APK non in https).
UpdateInfo? parseFeed(Object? raw) {
  final m = asMap(raw);
  final version = (asString(m['version']) ?? '').replaceFirst(RegExp(r'^v'), '');
  final code = asInt(m['versionCode']) ?? _semverCode(version);
  final url = asString(m['url']) ?? '';
  if (code <= 0 || !url.startsWith('https://')) return null;
  return UpdateInfo(code: code, version: version, url: url, mirrors: feedMirrors(m));
}

/// Primo feed valido nell'ordine di [feeds]: si passa al successivo solo se quello prima non risponde, risponde con
/// un errore o con un JSON non valido, così con il dominio dei download che funziona la richiesta resta una sola.
/// null = nessuno ha risposto bene (come una rete giù: si riprova più tardi).
Future<UpdateInfo?> firstFeed(List<String> feeds, Future<Object?> Function(Uri uri) fetch) async {
  for (final f in feeds) {
    try {
      final u = parseFeed(await fetch(Uri.parse(f)));
      if (u != null) return u;
    } on Object {
      // nessuna risposta, errore HTTP o risposta illeggibile: si prova il feed successivo
    }
  }
  return null;
}

int _semverCode(String v) {
  final m = RegExp(r'^(\d{1,3})\.(\d{1,2})\.(\d{1,3})$').firstMatch(v);
  if (m == null) return 0;
  return int.parse(m[1]!) * 10000 + int.parse(m[2]!) * 100 + int.parse(m[3]!);
}

/// Aggiornamento dell'app (Kairos Plus).
/// - Il feed dice qual è l'ultima versione e da dove si scarica l'APK: `/get/plus.json` del dominio dei download
///   (store-k.download) e, solo se non risponde bene, quello delle riserve ([updateFeeds]); niente pannello né GitHub.
///   Se l'APK non si scarica dal link del feed, la parte nativa prova le basi successive ([apkUrls]). I domini di
///   riserva annunciati dal feed («mirrors») si ricordano per i controlli successivi ([saveMirrors]).
/// - Aggiornamento in background (scelta del cliente o imposta dal pannello, acceso di serie): l'APK si scarica
///   e si verifica in silenzio (solo su Wi-Fi o cavo, mai durante la visione); quando è pronto si propone
///   «Installa ora» e al cliente resta solo la conferma di Android.
/// - Dal pannello: «Invia aggiornamento» (upd nel battito) o il comando «update» fanno partire subito il controllo.
class AppUpdater extends ChangeNotifier {
  AppUpdater({
    required this.feedUrls,
    required this.currentCode,
    required this.currentVersion,
    required this.backgroundEnabled,
    required this.forceDays,
    required this.watching,
    required this.loadFirstSeen,
    required this.saveFirstSeen,
    required this.loadPending,
    required this.savePending,
    this.fetchFeed,
    this.apkUrlsFor,
    this.saveMirrors,
  }) {
    _sub = NativeBridge.updateEvents.listen(_onEvent);
  }

  /// Feed da provare in ordine ([updateFeeds]), chiesti a ogni controllo: dominio dei download, poi le riserve
  /// (anche quelle annunciate dall'ultimo feed).
  final List<String> Function() feedUrls;

  /// Domini di riserva annunciati dal feed che ha risposto («mirrors»): l'app li ricorda per i controlli successivi.
  final void Function(List<String> mirrors)? saveMirrors;

  /// Lettura di un feed (le prove la sostituiscono); null = rete ([fetchFeedJson]).
  final Future<Object?> Function(Uri uri)? fetchFeed;

  /// APK da provare per il link del feed, in ordine ([apkUrls]); null = solo il link del feed.
  final List<String> Function(String url)? apkUrlsFor;

  final int currentCode;
  final String currentVersion;

  /// Aggiornamento in background acceso (preferenza del cliente o imposta dal pannello).
  final bool Function() backgroundEnabled;

  /// Aggiornamento obbligatorio deciso dal pannello: giorni di grazia dal primo avviso, null = il cliente può rimandare.
  final int? Function() forceDays;

  /// Visione in corso: niente download non richiesti e niente finestre.
  final bool Function() watching;

  /// Primo avviso salvato ("codice:millisecondi") e suo salvataggio.
  final Future<String> Function() loadFirstSeen;
  final Future<void> Function(String) saveFirstSeen;
  String _first = '';

  /// Versione trovata dall'ultimo controllo in rete, salvata su disco (JSON; vuoto = nessuna) e suo salvataggio.
  final Future<String> Function() loadPending;
  final Future<void> Function(String) savePending;

  /// Finisce quando la versione salvata è tornata in memoria all'avvio ([restore]): chi apre un video lo aspetta
  /// (solo letture locali, niente rete), così un aggiornamento obbligatorio non si scavalca nei primi istanti.
  Future<void> restored = Future<void>.value();

  /// La finestra dell'aggiornamento è aperta (una sola alla volta, per questa apertura dell'app).
  bool dialogOpen = false;

  /// Una proposta arrivata durante la visione: si mostra appena si torna in un menu.
  bool _offerLater = false;

  /// Mancava il permesso «Installa app sconosciute»: al ritorno l'installazione riparte da sola.
  bool _permWait = false;

  StreamSubscription<Map<String, dynamic>>? _sub;
  Timer? _timer;
  bool _disposed = false;
  DateTime? _lastCheck;
  bool _checking = false;
  int _failed = 0;
  int _offeredCode = 0;

  /// Versione nuova trovata e non ancora installata.
  UpdateInfo? pending;

  /// L'APK di [pending] è già scaricato e verificato.
  bool ready = false;

  /// Avanzamento del download richiesto dal cliente (0-100), -1 se fermo.
  int progress = -1;

  /// Ultimo esito da mostrare (es. errore del download).
  String? message;

  /// La versione da proporre al cliente: l'interfaccia mostra la finestra e poi rimette null.
  final ValueNotifier<UpdateInfo?> offer = ValueNotifier(null);

  /// Primo avviso al cliente di [u]: da lì contano i giorni di grazia.
  Future<int> _firstSeen(UpdateInfo u) async {
    if (_first.isEmpty) _first = await loadFirstSeen();
    final parts = _first.split(':');
    if (parts.length == 2 && int.tryParse(parts[0]) == u.code) return int.tryParse(parts[1]) ?? DateTime.now().millisecondsSinceEpoch;
    final now = DateTime.now().millisecondsSinceEpoch;
    _first = '${u.code}:$now';
    await saveFirstSeen(_first);
    return now;
  }

  /// L'app va bloccata: termine scaduto e APK già scaricato e verificato (mai per un problema di rete).
  bool get mustUpdate {
    final u = pending;
    final days = forceDays();
    if (u == null || days == null || !ready) return false;
    final parts = _first.split(':');
    if (parts.length != 2 || int.tryParse(parts[0]) != u.code) return false;
    final first = int.tryParse(parts[1]) ?? 0;
    return DateTime.now().millisecondsSinceEpoch - first >= days * 86400000;
  }

  /// All'avvio, anche senza rete: la versione trovata l'ultima volta torna in memoria e la parte Android dice se il
  /// suo APK è già scaricato e verificato. Un aggiornamento obbligatorio scaduto blocca così l'app subito, prima di
  /// qualsiasi visione, senza aspettare il controllo in rete; una versione già pronta si propone subito.
  Future<void> restore() => restored = _restore();

  Future<void> _restore() async {
    if (currentCode <= 0) return;
    try {
      final m = asMap(jsonDecode(await loadPending()));
      final code = asInt(m['code']) ?? 0;
      final url = asString(m['url']) ?? '';
      if (code > 0 && code <= currentCode) {
        await savePending(''); // già installata
        return;
      }
      if (pending != null || code <= 0 || !url.startsWith('https://')) return;
      final u = UpdateInfo(code: code, version: asString(m['version']) ?? '', url: url);
      await _firstSeen(u);
      final st = await NativeBridge.updateStatus(code);
      if (_disposed || pending != null) return; // nel frattempo ha risposto il controllo in rete
      pending = u;
      ready = st['ready'] == true;
      notifyListeners();
      if (ready) _maybeOffer();
    } on Object {
      // nessuna versione salvata (o illeggibile): vale il controllo in rete
    }
  }

  /// Aggiornamento obbligatorio scaduto: niente visione, e la finestra che blocca l'app si ripropone.
  bool remindIfMandatory() {
    final u = pending;
    if (u == null || !mustUpdate) return false;
    _offeredCode = u.code;
    if (identical(offer.value, u)) offer.value = null;
    offer.value = u;
    return true;
  }

  /// L'app torna in primo piano: se mancava il permesso «Installa app sconosciute» e ora c'è, l'installazione
  /// chiesta con «Installa ora» riparte da sola.
  Future<void> onResumed() async {
    final u = pending;
    if (!_permWait || u == null) return;
    _permWait = false;
    final st = await NativeBridge.updateStatus(u.code);
    if (_disposed || !identical(pending, u)) return;
    if (st['canInstall'] == true) {
      await install();
    } else {
      _permWait = true; // ancora senza permesso: si riprova al prossimo ritorno
    }
  }

  /// Controllo periodico: all'avvio e poi ogni ora.
  void start() {
    _timer?.cancel();
    Timer(const Duration(seconds: 25), () => unawaited(check()));
    _timer = Timer.periodic(const Duration(hours: 1), (_) => unawaited(check()));
  }

  /// L'app torna in primo piano: nuovo controllo se l'ultimo è vecchio di oltre 10 minuti; una versione già
  /// trovata si ripropone.
  void onForeground() {
    _offeredCode = 0;
    final last = _lastCheck;
    if (last == null || DateTime.now().difference(last) > const Duration(minutes: 10)) {
      unawaited(check());
    } else {
      _maybeOffer();
    }
  }

  /// È partita la visione (schermo intero o anteprima): un download in background in corso si ferma,
  /// così non ruba banda al video; riparte con [onPlaybackEnded].
  void onPlaybackStarted() {
    if (pending != null && !ready) unawaited(NativeBridge.updateCancel());
  }

  /// La visione è finita: il download rimandato riparte (se le condizioni lo permettono).
  void onPlaybackEnded() {
    if (pending == null || watching()) return;
    // proposta arrivata durante la visione: si mostra ora che si è tornati in un menu (non va persa)
    if (_offerLater) _maybeOffer();
    if (ready || _checking) return;
    if (backgroundEnabled() && _failed < 3) unawaited(check());
  }

  /// Il pannello ha chiesto l'aggiornamento: controllo subito e scaricamento anche su rete a consumo.
  /// Restituisce l'esito da confermare al pannello.
  Future<String> fromPanel() async {
    final u = await check(force: true);
    if (u == null) return 'già aggiornata ($currentVersion)';
    if (watching()) return 'versione ${u.version}: proposta a fine visione';
    return ready ? 'versione ${u.version} pronta: proposta al cliente' : 'versione ${u.version} in scaricamento';
  }

  /// Legge il feed; se c'è una versione nuova la scarica in background (quando è il caso) e la propone.
  /// [manual]: il cliente ha premuto «Controlla»: si propone subito, anche senza download in background.
  Future<UpdateInfo?> check({bool force = false, bool manual = false}) async {
    if (_checking || currentCode <= 0) return pending;
    _checking = true;
    try {
      // dominio dei download, poi le riserve solo se non risponde con un feed valido
      final found = await firstFeed(feedUrls(), fetchFeed ?? fetchFeedJson);
      if (found == null) {
        if (manual) message = 'Impossibile controllare gli aggiornamenti adesso';
        notifyListeners();
        return pending;
      }
      _lastCheck = DateTime.now();
      final mirrors = found.mirrors;
      if (mirrors != null) saveMirrors?.call(mirrors);
      final version = found.version;
      final code = found.code;
      final url = found.url; // l'APK si scarica da qui (dalla base del feed che ha risposto)
      if (code <= currentCode) {
        pending = null;
        ready = false;
        unawaited(savePending(''));
        if (manual) message = 'Hai già l\'ultima versione ($currentVersion)';
        notifyListeners();
        return null;
      }
      final u = UpdateInfo(code: code, version: version, url: url);
      if (pending?.code != code) {
        ready = false;
        _failed = 0;
        _offeredCode = 0;
      }
      pending = u;
      message = null;
      // su disco: al prossimo avvio (anche senza rete) l'aggiornamento è noto subito
      unawaited(savePending(jsonEncode({'code': code, 'version': version, 'url': url})));
      await _firstSeen(u);
      final st = await NativeBridge.updateStatus(code);
      ready = st['ready'] == true;
      final metered = st['metered'] == true;
      // mai durante la visione: il download riparte da onPlaybackEnded quando il lettore si chiude
      if (!ready && !manual && (backgroundEnabled() || force) && (force || !metered) && !watching() && _failed < 3) {
        await NativeBridge.updatePrefetch(url, code, alts: _alts(url)); // l'esito arriva con l'evento ready | failed | deferred
      } else {
        _maybeOffer(manual: manual);
      }
      notifyListeners();
      return u;
    } finally {
      _checking = false;
    }
  }

  /// Installa la versione trovata: subito se è già scaricata, altrimenti download con avanzamento.
  Future<void> install() async {
    final u = pending;
    if (u == null) return;
    message = null;
    progress = ready ? 100 : 0;
    notifyListeners();
    await NativeBridge.updateInstall(u.url, u.code, alts: _alts(u.url));
  }

  /// Dove riprovare l'APK se il link del feed non riesce: lo stesso APK sulle basi successive.
  List<String> _alts(String url) => [
    for (final u in apkUrlsFor?.call(url) ?? const <String>[])
      if (u != url) u,
  ];

  void _maybeOffer({bool manual = false}) {
    final u = pending;
    if (u == null) return;
    // durante la visione la finestra resterebbe nascosta dietro il lettore: si mostra al ritorno in un menu
    if (watching()) {
      _offerLater = true;
      return;
    }
    _offerLater = false;
    if (!manual && !mustUpdate && _offeredCode == u.code) return;
    _offeredCode = u.code;
    offer.value = u;
  }

  void _onEvent(Map<String, dynamic> e) {
    final type = asString(e['type']) ?? '';
    switch (type) {
      case 'ready':
        if (asInt(e['code']) == pending?.code) {
          ready = true;
          _offeredCode = 0;
          _maybeOffer();
        }
      case 'failed':
        _failed++; // si riprova al prossimo controllo (al massimo tre volte per versione)
        _maybeOffer(); // intanto il cliente può scaricarla a mano
      case 'deferred':
        break; // interrotto dalla visione: non conta come errore, riparte a fine visione
      case 'progress':
        progress = asInt(e['p']) ?? progress;
      case 'installer':
        progress = -1;
        message = 'Conferma l\'installazione nella schermata di Android';
      case 'perm':
        progress = -1;
        _permWait = true; // al ritorno dalle impostazioni l'installazione riparte da sola
        message = 'Manca il permesso «Installa app sconosciute»: attivalo per Kairos Plus nelle impostazioni che si '
            'sono aperte, poi torna qui e l\'installazione riparte da sola';
      case 'error':
        progress = -1;
        message = 'Aggiornamento non riuscito: ${asString(e['msg']) ?? 'errore'}';
      case 'busy':
        message = 'Download già in corso';
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _sub?.cancel();
    offer.dispose();
    super.dispose();
  }
}
