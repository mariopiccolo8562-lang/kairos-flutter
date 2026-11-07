import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Come si presenta l'app ai server (pannello Kairos e server IPTV).
/// All'avvio diventa "Mozilla/5.0 (Linux; Android …; modello) KairosPlus/versione":
/// il pannello riconosce così Kairos Plus tra le app Kairos.
String userAgent = 'Mozilla/5.0 (Linux; Android) KairosPlus/0.1';

/// Errore con un messaggio già pronto da mostrare all'utente.
class SourceException implements Exception {
  const SourceException(this.message);

  final String message;

  @override
  String toString() => message;
}

HttpClient? _shared;

/// Un solo client per isolate, riusato da tutte le richieste (keep-alive): niente connessione
/// e handshake TLS nuovi a ogni chiamata. Si chiude solo con [closeClient].
HttpClient _client() => _shared ??= HttpClient()
  ..connectionTimeout = const Duration(seconds: 15)
  ..idleTimeout = const Duration(seconds: 15)
  ..maxConnectionsPerHost = 6
  ..userAgent = userAgent;

/// Chiude le connessioni aperte (chiusura dell'app, fine dell'isolate di scaricamento,
/// connessione rimasta appesa dopo un timeout). Il prossimo uso ne apre di nuove.
void closeClient({bool force = false}) {
  _shared?.close(force: force);
  _shared = null;
}

/// Scarica un indirizzo come testo. Funziona anche dentro un isolate.
Future<String> fetchText(Uri uri, {Duration timeout = const Duration(seconds: 30)}) async {
  final client = _client();
  try {
    final request = await client.getUrl(uri).timeout(timeout);
    request.headers.set(HttpHeaders.userAgentHeader, userAgent);
    final response = await request.close().timeout(timeout);
    if (response.statusCode != HttpStatus.ok) {
      await response.drain<void>();
      throw SourceException('Il server ha risposto con errore ${response.statusCode}');
    }
    return await response
        .transform(const Utf8Decoder(allowMalformed: true))
        .join()
        .timeout(const Duration(minutes: 3));
  } on SocketException {
    throw const SourceException('Server non raggiungibile: controlla la connessione');
  } on HandshakeException {
    throw const SourceException('Connessione sicura (HTTPS) non riuscita');
  } on TimeoutException {
    closeClient(force: true); // la connessione rimasta appesa non va riusata
    throw const SourceException('Il server non risponde (tempo scaduto)');
  } on HttpException catch (e) {
    throw SourceException('Errore di rete: ${e.message}');
  }
}

/// Byte iniziali tenuti da parte solo per riconoscere una risposta vuota o di soli spazi.
const int _blankProbe = 4096;

/// Scarica un indirizzo e ne legge il JSON mentre arriva, direttamente dai byte UTF-8: il testo intero
/// non sta mai in memoria (con decine di migliaia di titoli erano decine di MB, il doppio se c'è anche un
/// solo carattere non latino). [reviver], come in [JsonDecoder], riceve ogni valore appena letto: gli
/// elenchi grandi lo usano per convertire subito ogni voce, così il JSON grezzo non resta tutto in memoria.
/// Risposta vuota o di soli spazi: null, come prima.
Future<Object?> fetchJson(
  Uri uri, {
  Duration timeout = const Duration(seconds: 30),
  Object? Function(Object? key, Object? value)? reviver,
}) async {
  final client = _client();
  try {
    final request = await client.getUrl(uri).timeout(timeout);
    request.headers.set(HttpHeaders.userAgentHeader, userAgent);
    final response = await request.close().timeout(timeout);
    if (response.statusCode != HttpStatus.ok) {
      await response.drain<void>();
      throw SourceException('Il server ha risposto con errore ${response.statusCode}');
    }
    final head = <int>[];
    var small = true;
    final bytes = response.map((List<int> chunk) {
      if (small) {
        if (head.length + chunk.length <= _blankProbe) {
          head.addAll(chunk);
        } else {
          small = false;
          head.clear();
        }
      }
      return chunk;
    });
    try {
      return await bytes
          .transform(const Utf8Decoder(allowMalformed: true).fuse(JsonDecoder(reviver)))
          .single
          .timeout(const Duration(minutes: 3));
    } on FormatException {
      if (small && utf8.decode(head, allowMalformed: true).trim().isEmpty) return null;
      throw const SourceException('Il server ha inviato una risposta non valida');
    }
  } on SocketException {
    throw const SourceException('Server non raggiungibile: controlla la connessione');
  } on HandshakeException {
    throw const SourceException('Connessione sicura (HTTPS) non riuscita');
  } on TimeoutException {
    closeClient(force: true); // la connessione rimasta appesa non va riusata
    throw const SourceException('Il server non risponde (tempo scaduto)');
  } on HttpException catch (e) {
    throw SourceException('Errore di rete: ${e.message}');
  }
}

/// Risposta di una chiamata al pannello: codice HTTP e JSON (se c'è).
class JsonResponse {
  const JsonResponse(this.status, this.body);

  final int status;
  final Map<String, dynamic>? body;

  bool get ok => status >= 200 && status < 300;
}

/// POST con corpo JSON (API del pannello Kairos).
Future<JsonResponse> postJson(Uri uri, Map<String, Object?> body, {Duration timeout = const Duration(seconds: 20)}) async {
  final client = _client();
  try {
    final request = await client.postUrl(uri).timeout(timeout);
    request.headers.set(HttpHeaders.userAgentHeader, userAgent);
    request.headers.contentType = ContentType.json;
    request.add(utf8.encode(jsonEncode(body)));
    final response = await request.close().timeout(timeout);
    final text = await response.transform(const Utf8Decoder(allowMalformed: true)).join().timeout(timeout);
    Map<String, dynamic>? json;
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map<String, dynamic>) json = decoded;
    } on FormatException {
      json = null;
    }
    return JsonResponse(response.statusCode, json);
  } on SocketException {
    throw const SourceException('Impossibile raggiungere il server');
  } on HandshakeException {
    throw const SourceException('Connessione sicura (HTTPS) non riuscita');
  } on TimeoutException {
    closeClient(force: true);
    throw const SourceException('Il server non risponde (tempo scaduto)');
  } on HttpException catch (e) {
    throw SourceException('Errore di rete: ${e.message}');
  }
}
