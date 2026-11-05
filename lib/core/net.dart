import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Come si presenta l'app ai server.
const String kUserAgent = 'KairosPlayer/0.1 (Android TV)';

/// Errore con un messaggio già pronto da mostrare all'utente.
class SourceException implements Exception {
  const SourceException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Scarica un indirizzo come testo. Funziona anche dentro un isolate.
Future<String> fetchText(Uri uri, {Duration timeout = const Duration(seconds: 30)}) async {
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 15)
    ..idleTimeout = const Duration(seconds: 15)
    ..userAgent = kUserAgent;
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
    throw const SourceException('Server non raggiungibile: controlla indirizzo e connessione');
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
