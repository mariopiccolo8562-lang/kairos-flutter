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

HttpClient _client() => HttpClient()
  ..connectionTimeout = const Duration(seconds: 15)
  ..idleTimeout = const Duration(seconds: 15)
  ..userAgent = userAgent;

/// Scarica un indirizzo come testo. Funziona anche dentro un isolate.
Future<String> fetchText(Uri uri, {Duration timeout = const Duration(seconds: 30)}) async {
  final client = _client();
  try {
    final request = await client.getUrl(uri).timeout(timeout);
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
    throw const SourceException('Il server non risponde (tempo scaduto)');
  } on HttpException catch (e) {
    throw SourceException('Errore di rete: ${e.message}');
  } finally {
    client.close(force: true);
  }
}

Future<Object?> fetchJson(Uri uri, {Duration timeout = const Duration(seconds: 30)}) async {
  final text = await fetchText(uri, timeout: timeout);
  if (text.trim().isEmpty) return null;
  try {
    return jsonDecode(text);
  } on FormatException {
    throw const SourceException('Il server ha inviato una risposta non valida');
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
    throw const SourceException('Il server non risponde (tempo scaduto)');
  } on HttpException catch (e) {
    throw SourceException('Errore di rete: ${e.message}');
  } finally {
    client.close(force: true);
  }
}
