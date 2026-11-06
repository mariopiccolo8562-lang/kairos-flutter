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
  });

  final String model; // es. "Amazon AFTMM"
  final String rawModel; // es. "AFTMM"
  final String release; // es. "9"
  final int sdk;
  final bool lowRam;
  final int totalMemMb;
  final String version; // versione dell'app, es. "0.1.7"

  /// Grafica leggera in automatico: chiavette con poca memoria e tutte le Fire TV
  /// (modelli «AFT…»), dove conta la velocità più degli effetti.
  bool get isLite => lowRam || (totalMemMb > 0 && totalMemMb < 1800) || rawModel.toUpperCase().startsWith('AFT');

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
    );
  }
}

/// Evento del lettore nativo (canale in onda, posizione di visione…).
class PlayerEvent {
  const PlayerEvent(this.type, this.data);

  final String type; // playing | progress | background | foreground
  final Map<String, dynamic> data;

  String get key => asString(data['key']) ?? '';
  int get index => asInt(data['index']) ?? 0;
  bool get live => data['live'] == true;
  int get position => asInt(data['pos']) ?? 0;
  int get duration => asInt(data['dur']) ?? 0;
}

/// Stato dell'anteprima di un canale (riquadro della TV in diretta).
class PreviewEvent {
  const PreviewEvent(this.key, this.state);

  final String key;
  final String state; // loading | playing | error | stopped
}

/// Ponte con la parte Android: informazioni sul dispositivo, lettore nativo e anteprima.
abstract final class NativeBridge {
  static const MethodChannel _channel = MethodChannel('kairos/native');
  static final StreamController<PlayerEvent> _events = StreamController<PlayerEvent>.broadcast();
  static final StreamController<PreviewEvent> _previewEvents = StreamController<PreviewEvent>.broadcast();
  static bool _listening = false;

  /// Eventi dell'anteprima (il video è partito, errore, fermata).
  static Stream<PreviewEvent> get previewEvents {
    _listen();
    return _previewEvents.stream;
  }

  /// Eventi del lettore mentre è aperto.
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
        }
      } on FormatException {
        // evento rovinato: si ignora
      }
      return null;
    });
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

  /// Fa partire un canale nel riquadro dell'anteprima ([data]: key, url, alt, x, y, w, h, ua, lite).
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

  static Future<void> closePlayer() async {
    try {
      await _channel.invokeMethod<Object?>('closePlayer');
    } on Object {
      // nessun lettore aperto
    }
  }
}
