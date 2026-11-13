import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'json.dart';

/// Dati del dispositivo letti dalla parte Android.
class DeviceInfo {
  const DeviceInfo({
    this.model = 'Android',
    this.rawModel = '',
    this.release = '',
    this.sdk = 0,
    this.lowRam = false,
    this.totalMemMb = 0,
    this.version = '',
    this.versionCode = 0,
    this.nativePlayerClass = '',
  });

  final String model; // es. "Amazon AFTMM"
  final String rawModel; // es. "AFTMM"
  final String release; // es. "9"
  final int sdk;
  final bool lowRam;
  final int totalMemMb;
  final String version; // versione dell'app, es. "0.1.7"
  final int versionCode; // numero di versione (cresce a ogni compilazione)
  final String nativePlayerClass; // D | N | O calcolata da Android (vuota con le versioni native vecchie)

  /// Grafica leggera in automatico: chiavette con poca memoria e tutte le Fire TV
  /// (modelli «AFT…»), dove conta la velocità più degli effetti.
  bool get isLite => lowRam || (totalMemMb > 0 && totalMemMb < 1800) || rawModel.toUpperCase().startsWith('AFT');

  /// Classe del dispositivo per il lettore (Kairos Adaptive), separata dalla grafica leggera:
  /// D = debole (≤ 1,2 GB o Android < 7), O = ottimo (≥ 2 GB e Android ≥ 9), N = il resto.
  String get playerClass {
    if (nativePlayerClass == 'D' || nativePlayerClass == 'N' || nativePlayerClass == 'O') return nativePlayerClass;
    if (lowRam || (sdk > 0 && sdk < 24) || (totalMemMb > 0 && totalMemMb <= 1228)) return 'D';
    if (totalMemMb >= 1900 && sdk >= 28) return 'O';
    return 'N';
  }

  static DeviceInfo fromMap(Object? raw) {
    final m = asMap(raw);
    return DeviceInfo(
      model: asString(m['model']) ?? 'Android',
      rawModel: asString(m['rawModel']) ?? '',
      release: asString(m['release']) ?? '',
      sdk: asInt(m['sdk']) ?? 0,
      lowRam: m['lowRam'] == true,
      totalMemMb: asInt(m['totalMemMb']) ?? 0,
      version: asString(m['version']) ?? '',
      versionCode: asInt(m['versionCode']) ?? 0,
      nativePlayerClass: asString(m['playerClass']) ?? '',
    );
  }
}

/// Evento del lettore nativo (canale in onda, posizione di visione…).
class PlayerEvent {
  const PlayerEvent(this.type, this.data);

  final String type; // playing | progress | stats | stall | error | background | foreground
  final Map<String, dynamic> data;

  String get key => asString(data['key']) ?? '';
  int get index => asInt(data['index']) ?? 0;
  bool get live => data['live'] == true;
  int get position => asInt(data['pos']) ?? 0;
  int get duration => asInt(data['dur']) ?? 0;

  /// Misure di rete del lettore (bw, line, dev, fill, ttff, stallMs, fmt, drop…), per il pannello.
  Map<String, dynamic> get stats => asMap(data['stats']);
}

/// Stato dell'anteprima di un canale (riquadro della TV in diretta).
class PreviewEvent {
  const PreviewEvent(this.key, this.state);

  final String key;
  final String state; // loading | playing | error | ended | stopped
}

/// Ponte con la parte Android: informazioni sul dispositivo, lettore nativo e anteprima.
abstract final class NativeBridge {
  static const MethodChannel _channel = MethodChannel('kairos/native');
  static final StreamController<PlayerEvent> _events = StreamController<PlayerEvent>.broadcast();
  static final StreamController<PreviewEvent> _previewEvents = StreamController<PreviewEvent>.broadcast();
  static final StreamController<Map<String, dynamic>> _updateEvents = StreamController<Map<String, dynamic>>.broadcast();
  static bool _listening = false;

  /// DNS cifrato (voce «sdns» del pannello): accende ([on]) o spegne l'interfaccia locale che porta le domande DNS dentro
  /// una connessione protetta. Risponde lo stato: off | asking | on | denied | error | other; vuoto se non disponibile.
  static Future<String> dns(bool on) async {
    try {
      return (await _channel.invokeMethod<Object?>(on ? 'dnsStart' : 'dnsStop'))?.toString() ?? '';
    } on Object {
      return '';
    }
  }

  /// Rete del dispositivo per «Online ora» del pannello: {type: wifi|eth|mobile|none, rssi: dBm (solo Wi-Fi)}.
  static Future<Map<String, dynamic>> netInfo() async {
    try {
      return asMap(await _channel.invokeMethod<Object?>('netInfo'));
    } on Object {
      return const <String, dynamic>{};
    }
  }

  /// Stato attuale del DNS cifrato (vedi [dns]).
  static Future<String> dnsState() async {
    try {
      return (await _channel.invokeMethod<Object?>('dnsState'))?.toString() ?? '';
    } on Object {
      return '';
    }
  }

  /// Eventi dell'anteprima (il video è partito, errore, fermata).
  static Stream<PreviewEvent> get previewEvents {
    _listen();
    return _previewEvents.stream;
  }

  /// Eventi del lettore mentre è aperto.
  /// Eventi dell'aggiornamento dell'app (ready, failed, progress, perm, installer, error, busy).
  static Stream<Map<String, dynamic>> get updateEvents {
    _listen();
    return _updateEvents.stream;
  }

  static Stream<PlayerEvent> get playerEvents {
    _listen();
    return _events.stream;
  }

  static void _listen() {
    if (_listening) return;
    _listening = true;
    _channel.setMethodCallHandler((call) async {
      final raw = call.arguments;
      if (raw is! String) return null;
      try {
        final m = asMap(jsonDecode(raw));
        if (call.method == 'playerEvent') {
          _events.add(PlayerEvent(asString(m['type']) ?? '', m));
        } else if (call.method == 'previewEvent') {
          _previewEvents.add(PreviewEvent(asString(m['key']) ?? '', asString(m['state']) ?? ''));
        } else if (call.method == 'updateEvent') {
          _updateEvents.add(m);
        }
      } on FormatException {
        // evento rovinato: si ignora
      }
      return null;
    });
  }

  /// Stato dell'aggiornamento [code]: ready (APK già scaricato e verificato), metered, busy, canInstall.
  static Future<Map<String, dynamic>> updateStatus(int code) async {
    _listen();
    try {
      return asMap(await _channel.invokeMethod<Object?>('updateStatus', {'code': code}));
    } on Object {
      return const <String, dynamic>{};
    }
  }

  /// Scarica e verifica l'APK in background (evento ready | failed); se [url] non riesce, prova [alts] in ordine.
  static Future<void> updatePrefetch(String url, int code, {List<String> alts = const []}) async {
    _listen();
    try {
      await _channel.invokeMethod<Object?>('updatePrefetch', {'url': url, 'code': code, 'alts': alts});
    } on Object catch (e) {
      debugPrint('Scaricamento aggiornamento non partito: $e');
    }
  }

  /// È partita la visione: il download in background dell'APK si interrompe (evento deferred).
  static Future<void> updateCancel() async {
    try {
      await _channel.invokeMethod<Object?>('updateCancel');
    } on Object {
      // nessun download in corso
    }
  }

  /// Installa: subito se l'APK è pronto, altrimenti lo scarica (eventi progress; se [url] non riesce, da [alts]) e apre
  /// l'installer.
  static Future<void> updateInstall(String url, int code, {List<String> alts = const []}) async {
    _listen();
    try {
      await _channel.invokeMethod<Object?>('updateInstall', {'url': url, 'code': code, 'alts': alts});
    } on Object catch (e) {
      debugPrint('Installazione non partita: $e');
    }
  }

  static Future<DeviceInfo> device() async {
    _listen();
    try {
      return DeviceInfo.fromMap(await _channel.invokeMethod<Object?>('device'));
    } on Object catch (e) {
      debugPrint('Informazioni dispositivo non disponibili: $e');
      return const DeviceInfo();
    }
  }

  /// Apre il lettore nativo. Restituisce il risultato alla chiusura
  /// (posizioni di visione) oppure null.
  static Future<Map<String, dynamic>?> play(Map<String, Object?> data) async {
    _listen();
    final result = await _channel.invokeMethod<String>('play', jsonEncode(data));
    if (result == null || result.isEmpty) return null;
    try {
      return asMap(jsonDecode(result));
    } on FormatException {
      return null;
    }
  }

  /// Guida XMLTV di riserva (parte Android, Guide.kt): chiede di leggerla in sottofondo dalle [sources], in ordine, per i
  /// [channels] (coppie: id della guida, nome). Risponde none | busy | fresh | wait | player | started; vuoto se non c'è.
  static Future<String> guideBuild({
    required List<String> sources,
    required List<List<String>> channels,
    required String ua,
    bool force = false,
  }) async {
    try {
      final r = await _channel.invokeMethod<Object?>('guideBuild', {'sources': sources, 'channels': channels, 'ua': ua, 'force': force});
      return r?.toString() ?? '';
    } on Object {
      return '';
    }
  }

  /// Dopo la visione: fa ripartire la lettura della guida rimasta in sospeso (il lettore la interrompe).
  static Future<void> guideResume() async {
    try {
      await _channel.invokeMethod<Object?>('guideResume');
    } on Object {
      // parte Android non disponibile: niente da riprendere
    }
  }

  /// Programmi da adesso in poi di un canale, dalla guida XMLTV già letta (vuoto se non c'è): t, d, s, e (millisecondi).
  static Future<List<Map<String, dynamic>>> guideQuery(String epg, String name, {int limit = 4}) async {
    try {
      final r = await _channel.invokeMethod<Object?>('guideQuery', {'epg': epg, 'name': name, 'limit': limit});
      return [for (final raw in asList(r)) asMap(raw)];
    } on Object {
      return const <Map<String, dynamic>>[];
    }
  }

  /// Trailer di YouTube dentro l'app ([yt]: codice o link del video). false se il video non è valido.
  static Future<bool> openTrailer(String yt, String title) async {
    try {
      return (await _channel.invokeMethod<Object?>('trailer', {'yt': yt, 'title': title})) == true;
    } on Object {
      return false;
    }
  }

  /// Fa partire un canale nel riquadro dell'anteprima ([data]: key, url, alt, x, y, w, h, ua, playerClass).
  static Future<void> previewShow(Map<String, Object?> data) async {
    _listen();
    try {
      await _channel.invokeMethod<Object?>('previewShow', jsonEncode(data));
    } on Object catch (e) {
      debugPrint('Anteprima non disponibile: $e');
    }
  }

  /// Sposta il riquadro (stessi campi di posizione di [previewShow]).
  static Future<void> previewMove(Map<String, Object?> rect) async {
    try {
      await _channel.invokeMethod<Object?>('previewMove', jsonEncode(rect));
    } on Object {
      // nessun riquadro aperto
    }
  }

  static Future<void> previewStop({bool release = false}) async {
    try {
      await _channel.invokeMethod<Object?>(release ? 'previewRelease' : 'previewStop');
    } on Object {
      // nessun riquadro aperto
    }
  }

  /// «Chiedi il permesso» dal pannello: true se Android permette già di installare gli aggiornamenti,
  /// altrimenti apre la schermata «Installa app sconosciute» (nessuna app può attivarlo da sola)
  static Future<bool> openInstallPerm() async {
    try {
      return await _channel.invokeMethod<bool>('openInstallPerm') ?? false;
    } on Object {
      return false;
    }
  }

  static Future<void> closePlayer() async {
    try {
      await _channel.invokeMethod<Object?>('closePlayer');
    } on Object {
      // nessun lettore aperto
    }
  }

  /// Riquadro della qualità cambiato dal pannello con il lettore aperto ([box]: `resInd`, `resTag`, come all'apertura):
  /// true se il lettore aperto l'ha ricevuto.
  static Future<bool> playerBox(Map<String, bool> box) async {
    try {
      return await _channel.invokeMethod<bool>('playerBox', jsonEncode(box)) ?? false;
    } on Object {
      return false; // nessun lettore aperto
    }
  }
}
