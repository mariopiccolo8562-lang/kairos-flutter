import 'dart:convert';
import 'dart:math';

import '../core/json.dart';
import '../core/net.dart';
import '../data/models.dart';
import '../data/trend_match.dart';
import '../data/sources/xtream_source.dart';

/// Indirizzo del pannello Kairos (lo stesso di Kairos Pro, Kairos TV e Kairos Lite).
/// Il pannello può indicarne uno nuovo (Impostazioni → server): l'app lo ricorda.
const String kDefaultPanelUrl = 'https://panel-kairos.com';

/// Indirizzo di riserva: se il dominio non è raggiungibile (es. bloccato dalla rete)
/// si prova questo, e l'app ricorda quello che funziona.
const List<String> kFallbackPanelUrls = ['https://kairos-panel.mariopiccolo8562.workers.dev'];

/// Errore del pannello con un messaggio già pronto per l'utente.
class PanelException implements Exception {
  const PanelException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Codice di attivazione del dispositivo (KX12-AB34, come le altre app Kairos)
/// e segreto legato al dispositivo: insieme identificano la TV nel pannello.
class PanelIdentity {
  const PanelIdentity(this.code, this.secret);

  final String code;
  final String secret;

  static const String _alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

  factory PanelIdentity.generate() {
    final r = Random.secure();
    String ch() => _alphabet[r.nextInt(_alphabet.length)];
    final code = 'KX${ch()}${ch()}-${ch()}${ch()}${ch()}${ch()}';
    final bytes = List<int>.generate(32, (_) => r.nextInt(256));
    final secret = base64Url.encode(bytes).replaceAll('=', '');
    return PanelIdentity(code, secret);
  }

  static final RegExp codePattern = RegExp(r'^KX[A-Z0-9]{2}-[A-Z0-9]{4}$');
  static final RegExp secretPattern = RegExp(r'^[A-Za-z0-9_-]{32,100}$');

  bool get isValid => codePattern.hasMatch(code) && secretPattern.hasMatch(secret);
}

/// Playlist assegnata dal pannello (Xtream oppure M3U).
class PanelPlaylist {
  const PanelPlaylist({
    required this.id,
    required this.name,
    required this.type,
    this.url = '',
    this.host = '',
    this.username = '',
    this.password = '',
  });

  final String id;
  final String name;
  final String type; // xtream | m3u
  final String url;
  final String host;
  final String username;
  final String password;

  bool get isXtream => type == 'xtream' && host.isNotEmpty && username.isNotEmpty;

  static PanelPlaylist fromJson(Object? json) {
    final m = asMap(json);
    return PanelPlaylist(
      id: asString(m['id']) ?? '',
      name: asString(m['name']) ?? 'Playlist',
      type: asString(m['type']) ?? 'm3u',
      url: asString(m['url']) ?? '',
      host: asString(m['host']) ?? '',
      username: asString(m['username']) ?? '',
      password: asString(m['password']) ?? '',
    );
  }

  /// Account da usare per scaricare i contenuti. Un link M3U di un server Xtream
  /// (get.php?username=…) diventa un account Xtream: categorie e guida TV più ricche.
  Account? toAccount() {
    if (isXtream) {
      return Account(
        type: AccountType.xtream,
        server: XtreamSource.normalizeServer(host),
        username: username,
        password: password,
      );
    }
    final link = _fixUrl(url);
    if (link.isEmpty) return null;
    return XtreamSource.accountFromM3uUrl(link) ?? Account(type: AccountType.m3u, m3uUrl: link);
  }

  /// Firma senza il server: se il pannello cambia solo il DNS la lista non si riscarica da capo.
  String get signature => '$id|$type|$username|$password|${isXtream ? '' : _pathOf(url)}';

  static String _fixUrl(String u) {
    final t = u.trim();
    if (t.isEmpty) return t;
    return t.startsWith('http://') || t.startsWith('https://') ? t : 'http://$t';
  }

  static String _pathOf(String u) {
    final uri = Uri.tryParse(_fixUrl(u));
    if (uri == null) return u;
    return '${uri.path}?${uri.query}';
  }
}

class PanelMessage {
  const PanelMessage({required this.id, required this.title, required this.body});

  final String id;
  final String title;
  final String body;
}

/// Account del cliente: connessioni, limite di visioni, modalità delle playlist.
class PanelAccount {
  const PanelAccount({
    this.primary = true,
    this.maxConn = 1,
    this.conns = 0,
    this.maxStreams = 0,
    this.plMode = 'merge',
    this.plDefault = '',
  });

  final bool primary;
  final int maxConn;
  final int conns;
  final int maxStreams;
  final String plMode; // merge | split
  final String plDefault;

  static PanelAccount? fromJson(Object? json) {
    if (json is! Map) return null;
    final m = asMap(json);
    return PanelAccount(
      primary: m['primary'] != false,
      maxConn: asInt(m['maxConn']) ?? 1,
      conns: asList(m['conns']).length,
      maxStreams: asInt(m['maxStreams']) ?? 0,
      plMode: asString(m['plMode']) == 'split' ? 'split' : 'merge',
      plDefault: asString(m['plDefault']) ?? '',
    );
  }
}

/// Stato del dispositivo restituito da /api/player/register.
class PanelState {
  const PanelState({
    required this.status,
    this.name = '',
    this.expires = '',
    this.settings = const <String, dynamic>{},
    this.playlists = const <PanelPlaylist>[],
    this.messages = const <PanelMessage>[],
    this.account,
    this.perms,
    this.maintMsg = '',
    this.raw = const <String, dynamic>{},
  });

  /// active | pending | locked | expired | disabled | maintenance
  final String status;
  final String name;
  final String expires; // AAAA-MM-GG oppure vuoto (senza scadenza)
  final Map<String, dynamic> settings;
  final List<PanelPlaylist> playlists;
  final List<PanelMessage> messages;
  final PanelAccount? account;
  final Map<String, dynamic>? perms;
  final String maintMsg;
  final Map<String, dynamic> raw;

  bool get active => status == 'active';

  /// Le funzioni sono consentite se il pannello non le spegne.
  bool perm(String key) => perms?[key] != false;

  String setting(String key) => asString(settings[key]) ?? '';

  /// Permessi spenti, nella forma usata dal battito per accorgersi dei cambiamenti.
  String offPerms() {
    final p = perms;
    if (p == null) return '';
    final off = [for (final e in p.entries) if (e.value == false) e.key]..sort();
    return off.join(',');
  }

  static PanelState parse(Map<String, dynamic> j) {
    return PanelState(
      status: asString(j['status']) ?? 'pending',
      name: asString(j['name']) ?? '',
      expires: asString(j['expires']) ?? '',
      settings: asMap(j['settings']),
      playlists: [for (final p in asList(j['playlists'])) PanelPlaylist.fromJson(p)],
      messages: [
        for (final raw in asList(j['messages']))
          PanelMessage(
            id: asString(asMap(raw)['id']) ?? '',
            title: asString(asMap(raw)['title']) ?? '',
            body: asString(asMap(raw)['body']) ?? '',
          ),
      ],
      account: PanelAccount.fromJson(j['account']),
      perms: j['perms'] is Map ? asMap(j['perms']) : null,
      maintMsg: asString(j['maintMsg']) ?? '',
      raw: j,
    );
  }

  static const PanelState locked = PanelState(status: 'locked');

  /// Scadenza leggibile: 05/11/2026.
  String get expiresLabel {
    final d = DateTime.tryParse(expires);
    if (d == null) return expires;
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)}/${d.year}';
  }
}

/// Risposta del pannello a un battito.
class BeatReply {
  const BeatReply(this.status, this.body, {this.wait = 0});

  /// Pannello non raggiungibile.
  static const BeatReply failed = BeatReply(0, null);

  /// Codice HTTP (0 = nessuna risposta).
  final int status;

  /// Dati del battito accettato (solo con HTTP 200).
  final Map<String, dynamic>? body;

  /// Con HTTP 429: secondi da aspettare prima del prossimo battito (0 = non indicati).
  final int wait;

  bool get ok => status == 200 && body != null;
}

/// API del pannello per i dispositivi (/api/player/…), le stesse delle altre app Kairos.
class PanelClient {
  PanelClient({
    required this.identity,
    required this.server,
    required this.model,
    required this.version,
    this.fallbacks = const <String>[],
    this.onServerChanged,
  });

  final PanelIdentity identity;
  String server;
  final String model;
  final String version;

  /// Indirizzi di riserva provati quando il server attuale non risponde.
  final List<String> fallbacks;

  /// Chiamato quando l'app passa a un altro indirizzo che funziona.
  final void Function(String server)? onServerChanged;

  /// Versione mostrata nel pannello (Utenti online): «plus 0.1.7».
  String get ver {
    final v = 'plus ${version.isEmpty ? '0' : version}';
    return v.length > 20 ? v.substring(0, 20) : v;
  }

  String get _base => _trim(server);

  static String _trim(String url) => url.endsWith('/') ? url.substring(0, url.length - 1) : url;

  Map<String, Object?> _auth() => {'code': identity.code, 'secret': identity.secret};

  Future<JsonResponse> _post(
    String path,
    Map<String, Object?> body, {
    Duration timeout = const Duration(seconds: 20),
    bool useFallbacks = true,
  }) async {
    if (_base.isEmpty) throw const PanelException('Server non configurato');
    final servers = <String>[
      server,
      if (useFallbacks)
        for (final f in fallbacks)
          if (_trim(f) != _base) f,
    ];
    PanelException? lastError;
    JsonResponse? lastPage;
    for (final candidate in servers) {
      try {
        final r = await postJson(Uri.parse('${_trim(candidate)}$path'), body, timeout: timeout);
        // una pagina che non è del pannello (rete che blocca il dominio, protezioni): si prova il prossimo
        if (r.body == null) {
          lastPage = r;
          continue;
        }
        if (_trim(candidate) != _base) {
          // il server di prima non risponde, questo sì: da ora si usa lui
          server = _trim(candidate);
          onServerChanged?.call(server);
        }
        return r;
      } on SourceException catch (e) {
        lastError = PanelException(e.message);
      } on FormatException {
        lastError = const PanelException('Indirizzo del server non valido');
      }
    }
    if (lastPage != null) return lastPage;
    throw lastError ?? const PanelException('Impossibile raggiungere il server');
  }

  Future<PanelState> register() async {
    final r = await _post('/api/player/register', {..._auth(), 'model': model, 'ver': ver});
    final j = r.body;
    if (j == null) throw PanelException('Il server ha risposto con una pagina non valida (HTTP ${r.status})');
    if (r.status == 403 && asString(j['status']) == 'locked') return PanelState.locked;
    if (r.status == 429) throw const PanelException('Troppe richieste: riprovo tra poco');
    if (r.status >= 400) throw PanelException(asString(j['error']) ?? 'Errore del server (HTTP ${r.status})');
    return PanelState.parse(j);
  }

  /// Collega questa TV a un abbonamento già attivo: null = fatto, altrimenti l'errore.
  Future<String?> link(String pin) async {
    try {
      final r = await _post('/api/player/link', {..._auth(), 'pin': pin});
      final error = asString(r.body?['error']);
      if (r.ok && r.body != null && error == null) return null;
      return error ?? 'Codice non valido o scaduto';
    } on PanelException catch (e) {
      return e.message;
    }
  }

  /// Codice a 6 cifre per collegare un'altra TV a questo abbonamento.
  Future<String> linkCode() async {
    final r = await _post('/api/player/linkcode', _auth());
    final pin = asString(r.body?['pin']);
    if (r.status >= 400 || pin == null) {
      throw PanelException(asString(r.body?['error']) ?? 'Non è stato possibile creare il codice');
    }
    return pin;
  }

  /// Battito per «Online ora» e per i comandi del pannello (Disconnetti, cambi…).
  /// [stats]: misure del lettore (Kairos Adaptive, sezione 9): bw, line, dev, fill, ttff, stallMs, fmt, drop, net.
  /// [vis]: true = l'app è in primo piano (menu o visione); false = è appena andata in sfondo
  /// (il pannello la mostra subito non in linea e quel battito non conta per il limite dei 15 secondi).
  Future<BeatReply> heartbeat({
    required String state,
    String title = '',
    String channel = '',
    String channelId = '',
    String group = '',
    String screen = '',
    int kickAck = 0,
    Map<String, Object?> cfg = const {},
    String rcv = '',
    Map<String, Object?> stats = const {},
    bool vis = true,
    String sdns = '',
  }) async {
    try {
      final r = await _post('/api/player/heartbeat', {
        ..._auth(),
        'vis': vis,
        'state': state,
        'title': title,
        'ch': channel,
        'chId': channelId,
        'group': group,
        'pl': '',
        'prof': '',
        'ver': ver,
        'ui': '',
        'model': model,
        'screen': screen.length > 20 ? screen.substring(0, 20) : screen,
        'net': {'type': asString(stats['net']) ?? ''},
        'vpn': 'off',
        if (sdns.isNotEmpty) 'sdns': sdns, // DNS cifrato: stato, solo se il pannello lo ha acceso
        'cfg': cfg, // controllo remoto: impostazioni attuali dell'app
        'rcv': rcv, // configurazione del pannello applicata
        if (stats.isNotEmpty) 'stats': stats, // banda, classi, stalli, formato del lettore
        if (kickAck > 0) 'kickAck': kickAck,
      });
      // troppi battiti (meno di 15 s dall'ultimo): il pannello dice quanti secondi aspettare
      if (r.status == 429) return BeatReply(429, null, wait: asInt(r.body?['wait']) ?? 0);
      return BeatReply(r.status, r.status == 200 ? r.body : null);
    } on PanelException {
      return BeatReply.failed;
    }
  }

  /// Conferma al pannello di un comando del controllo remoto.
  Future<void> cmdAck(int id, bool ok, String info) async {
    try {
      await _post('/api/player/cmd', {..._auth(), 'id': id, 'ok': ok, 'info': info.length > 200 ? info.substring(0, 200) : info});
    } on PanelException {
      // il pannello lo rimanderà se serve
    }
  }

  /// Limite di visioni contemporanee: null = si può guardare, altrimenti il messaggio.
  /// Come le altre app Kairos: risposta entro 2,5 secondi, nel dubbio si guarda.
  Future<String?> stream(String state, String title) async {
    try {
      final r = await _post(
        '/api/player/stream',
        {..._auth(), 'state': state, 'title': title},
        timeout: const Duration(milliseconds: 2500),
        useFallbacks: false,
      );
      final j = r.body;
      if (j == null) return null;
      if (j['ok'] == false) return asString(j['error']) ?? 'Limite di visioni contemporanee raggiunto';
      if (r.status == 403) return asString(j['error']);
      return null;
    } on Object {
      return null;
    }
  }

  /// Classifica dei titoli di tendenza della settimana (/api/player/trending); null se non arriva.
  Future<TrendList?> trending() async {
    if (_base.isEmpty) return null;
    try {
      final text = await fetchText(Uri.parse('$_base/api/player/trending'), timeout: const Duration(seconds: 8));
      if (text.length > 200000) return null;
      return TrendList.parse(jsonDecode(text));
    } on Object {
      return null;
    }
  }

  /// Testo «Privacy e condizioni»: quello del pannello, altrimenti la pagina pubblica /privacy.
  Future<String> privacyText(PanelState? state) async {
    final t = state?.setting('privacy') ?? '';
    if (t.trim().isNotEmpty) return t.trim();
    try {
      final html = await fetchText(Uri.parse('$_base/privacy'), timeout: const Duration(seconds: 12));
      return _htmlToText(html);
    } on Object {
      return '';
    }
  }

  static String _htmlToText(String html) {
    var s = html.replaceAll(RegExp(r'<(head|style|script)[\s\S]*?</\1>', caseSensitive: false), '');
    s = s.replaceAll(RegExp(r'<(br|/p|/div|/h\d|/li)[^>]*>', caseSensitive: false), '\n');
    s = s.replaceAll(RegExp(r'<[^>]+>'), '');
    s = s
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&egrave;', 'è')
        .replaceAll('&agrave;', 'à')
        .replaceAll('&ograve;', 'ò')
        .replaceAll('&ugrave;', 'ù')
        .replaceAll('&igrave;', 'ì')
        .replaceAll('&eacute;', 'é');
    s = s.replaceAll(RegExp(r'[ \t]+'), ' ').replaceAll(RegExp(r'\n\s*\n\s*\n+'), '\n\n');
    return s.trim();
  }
}
