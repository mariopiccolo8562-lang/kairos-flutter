import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../app/brand.dart';
import '../app/perf.dart';
import '../core/json.dart';
import '../core/native.dart';
import '../core/net.dart' as net;
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import '../data/catalog_repository.dart';
import '../data/models.dart';
import '../data/sources/content_source.dart';
import '../data/user_store.dart';
import '../panel/panel.dart';
import 'app_updater.dart';

enum SessionStatus { starting, activation, loading, ready, error }

/// Cosa mostrare nella schermata di attivazione.
class ActivationInfo {
  const ActivationInfo({required this.status, required this.message, this.warn = false});

  /// checking | pending | locked | expired | disabled | maintenance | offline
  final String status;
  final String message;
  final bool warn;
}

/// Anteprima di un canale nel riquadro della TV in diretta.
class PreviewState {
  const PreviewState(this.key, this.status);
  const PreviewState.idle()
      : key = null,
        status = 'idle';

  /// Canale nel riquadro (null = nessuno).
  final String? key;

  /// idle | loading | playing | error
  final String status;

  bool isFor(String channelKey) => key == channelKey;
}

/// Cosa si sta guardando (per «Online ora» nel pannello).
class _Watch {
  const _Watch({required this.state, required this.title, this.channel = '', this.channelId = '', this.group = ''});

  final String state; // live | movie | series
  final String title;
  final String channel;
  final String channelId;
  final String group;

  static _Watch of(PlaybackItem item) => item.isLive
      ? _Watch(
          state: 'live',
          title: item.title,
          channel: item.title,
          channelId: item.channel?.id ?? '',
          group: item.group ?? '',
        )
      : _Watch(state: item.watchState, title: item.subtitle == null ? item.title : '${item.title} · ${item.subtitle}');
}

/// Stato dell'app. Ogni informazione ha il suo "canale" di notifica
/// (catalogo, preferiti, progressi…): una schermata si ridisegna solo
/// quando cambia ciò che mostra davvero.
///
/// L'accesso funziona come nelle altre app Kairos: la TV mostra il suo codice,
/// il fornitore la attiva dal pannello e le playlist arrivano da lì.
class AppController {
  final UserStore _store = UserStore();

  final ValueNotifier<SessionStatus> status = ValueNotifier(SessionStatus.starting);
  final ValueNotifier<ActivationInfo> activation =
      ValueNotifier(const ActivationInfo(status: 'checking', message: 'Collegamento al server…'));
  final ValueNotifier<PanelState?> panelState = ValueNotifier(null);
  final ValueNotifier<Catalog?> catalog = ValueNotifier(null);
  final ValueNotifier<String> liveFormat = ValueNotifier('ts');
  final ValueNotifier<int> favoritesRevision = ValueNotifier(0);
  final ValueNotifier<int> progressRevision = ValueNotifier(0);

  /// Avvisi da mostrare subito (es. «Disconnetti» dal pannello).
  final ValueNotifier<String?> notice = ValueNotifier(null);

  /// Anteprima del canale nel riquadro (TV in diretta).
  final ValueNotifier<PreviewState> preview = ValueNotifier(const PreviewState.idle());

  /// Cambia quando cambia la grafica (leggera o completa): l'interfaccia si ricostruisce.
  final ValueNotifier<int> uiRevision = ValueNotifier(0);

  DeviceInfo device = const DeviceInfo();
  PanelClient? _panel;
  PanelState? _state;
  PanelState? _deferredState;
  PanelPlaylist? _playlist;
  Account? _account;
  ContentSource? _source;

  Set<String> _favorites = <String>{};
  Map<String, WatchProgress> _progress = <String, WatchProgress>{};
  Set<String> _seenMessages = <String>{};
  String _playlistChoice = '';
  String _catalogSig = '';
  bool _privacyOk = false;
  int _kickSeen = 0;
  int _updSeen = 0;
  bool _bgUpdate = true;
  bool _updaterStarted = false;
  String _liteMode = 'auto';
  // controllo remoto: impostazioni imposte dal pannello (vincono su quelle scelte qui) e versione applicata
  Map<String, dynamic> _rc = const <String, dynamic>{};
  String _rcv = '';
  /// Il pannello ha imposto questa impostazione: nell'app si vede ma non si cambia.
  bool imposed(String key) => (_rc[key]?.toString() ?? '').isNotEmpty;
  /// Comando dal pannello che l'interfaccia deve eseguire (es. aprire le Impostazioni).
  final ValueNotifier<String?> remoteCmd = ValueNotifier(null);
  /// Aggiornamento dell'app (feed delle release, scaricamento in background, installazione).
  AppUpdater? _updater;
  AppUpdater get updater => _updater!;
  /// Aggiornamento in background acceso (imposto dal pannello o scelto qui).
  bool get bgUpdate => imposed('bgupd') ? _rc['bgupd'].toString() == 'on' : _bgUpdate;
  String _previewMode = 'click';
  int _previewSeq = 0;
  bool _inPlayer = false;

  /// Messaggio da mostrare se il catalogo non si è potuto caricare.
  String? startupError;

  final Map<String, (DateTime, List<EpgEntry>)> _epgCache = {};
  final Map<String, Future<MovieDetails?>> _movieDetails = {};
  final Map<String, Future<SeriesDetails?>> _seriesDetails = {};

  AppLifecycleListener? _lifecycle;
  StreamSubscription<PlayerEvent>? _playerSub;
  StreamSubscription<PreviewEvent>? _previewSub;

  /// Grafica leggera (scelta dall'utente o automatica sulle chiavette con poca memoria).
  bool get lite => Perf.lite;

  /// auto | on | off
  String get liteMode => switch (_rc['lite']?.toString() ?? '') { 'auto' || 'on' || 'max' || 'off' => _rc['lite'].toString(), _ => _liteMode };

  /// Anteprima dei canali attiva: 1° OK nel riquadro, 2° OK schermo intero.
  bool get previewEnabled => (imposed('preview') ? _rc['preview'].toString() : _previewMode) != 'off';
  String get deviceCode => _panel?.identity.code ?? '';
  String get appVersion => device.version.isEmpty ? '0.1' : device.version;
  Account? get account => _account;
  PanelPlaylist? get playlist => _playlist;
  bool get supportsEpg => _source?.supportsEpg ?? false;
  /// privacy già accettata, oppure il fornitore ha deciso dal pannello di non mostrarla
  bool get privacyOk => _privacyOk || _rc['privacy']?.toString() == 'skip';

  // ---------------------------------------------------------------------------
  // Avvio

  Future<void> start() async {
    // l'ultimo stato attivo e il catalogo salvato si leggono subito, in parallelo al resto
    final cachedRaw = await _store.loadPanelState();
    final cachedState = cachedRaw == null ? null : PanelState.parse(cachedRaw);
    final wasActive = cachedState?.active ?? false;
    final earlyHome = wasActive ? CatalogRepository.readHome() : null;
    final earlyCache = wasActive ? CatalogRepository.readCache() : null;

    device = await NativeBridge.device();
    _bgUpdate = await _store.loadBgUpdate();
    _updSeen = await _store.loadUpdSeen();
    _updater = AppUpdater(
      feedUrl: Brand.updateFeed,
      currentCode: device.versionCode,
      currentVersion: device.version,
      backgroundEnabled: () => bgUpdate,
      forceDays: () => switch (_rc['force']?.toString()) { 'now' => 0, '3d' => 3, '7d' => 7, _ => null },
      watching: () => _watching != null || _inPlayer,
      loadFirstSeen: _store.loadUpdFirst,
      saveFirstSeen: _store.saveUpdFirst,
    );
    final model = device.rawModel.replaceAll(RegExp(r'[^\x20-\x7E]'), '').trim();
    net.userAgent =
        'Mozilla/5.0 (Linux; Android ${device.release.isEmpty ? '9' : device.release}; ${model.isEmpty ? 'Android' : model}) KairosPlus/$appVersion';

    _liteMode = await _store.loadLiteMode();
    {
      final (rc, rcv) = await _store.loadRemote();
      try {
        _rc = rc.isEmpty ? const <String, dynamic>{} : asMap(jsonDecode(rc));
      } on FormatException {
        _rc = const <String, dynamic>{};
      }
      _rcv = rcv;
    }
    _previewMode = await _store.loadPreviewMode();
    _applyLite();

    _favorites = await _store.loadFavorites();
    _progress = await _store.loadProgress();
    liveFormat.value = await _store.loadLiveFormat();
    _seenMessages = await _store.loadSeenMessages();
    _playlistChoice = await _store.loadPlaylistChoice();
    _catalogSig = await _store.loadCatalogSignature();
    _privacyOk = await _store.loadPrivacyOk();
    _kickSeen = await _store.loadKickSeen();

    var identity = await _store.loadIdentity();
    var id = identity == null ? null : PanelIdentity(identity.$1, identity.$2);
    if (id == null || !id.isValid) {
      id = PanelIdentity.generate();
      await _store.saveIdentity(id.code, id.secret);
    }
    final saved = await _store.loadServer();
    _panel = PanelClient(
      identity: id,
      server: saved != null && saved.startsWith('https://') ? saved : kDefaultPanelUrl,
      model: device.model,
      version: appVersion,
      fallbacks: [kDefaultPanelUrl, ...kFallbackPanelUrls],
      onServerChanged: (url) => unawaited(_store.saveServer(url)),
    );

    _playerSub = NativeBridge.playerEvents.listen(_onPlayerEvent);
    _previewSub = NativeBridge.previewEvents.listen(_onPreviewEvent);
    _lifecycle = AppLifecycleListener(onResume: _onResume, onPause: _onPause);

    // partenza immediata con l'ultimo stato attivo; il pannello si ricontrolla subito dopo
    if (cachedState != null && cachedState.active) {
      await _applyState(cachedState, cache: earlyCache, home: earlyHome);
      unawaited(refreshPanel());
      return;
    }
    status.value = SessionStatus.activation;
    unawaited(_activationTick());
  }

  void _onResume() {
    _foreground = true;
    if (status.value == SessionStatus.activation) {
      unawaited(_activationTick());
    } else if (status.value == SessionStatus.ready) {
      unawaited(_beat(true));
      if (_updaterStarted) updater.onForeground();
    }
  }

  void _onPause() {
    _foreground = false;
    _activationTimer?.cancel();
  }

  /// Ripete il caricamento dopo un errore.
  Future<void> retryStartup() async {
    final s = _state;
    if (s == null || !s.active) {
      status.value = SessionStatus.activation;
      unawaited(_activationTick());
      return;
    }
    _catalogSig = '';
    await _applyState(s);
  }

  // ---------------------------------------------------------------------------
  // Attivazione dal pannello

  Timer? _activationTimer;
  bool _activationBusy = false;

  Future<void> retryActivationNow() => _activationTick();

  Future<void> _activationTick() async {
    _activationTimer?.cancel();
    final panel = _panel;
    if (panel == null || _activationBusy || status.value != SessionStatus.activation) return;
    _activationBusy = true;
    PanelState? s;
    String? error;
    try {
      s = await panel.register();
    } on PanelException catch (e) {
      error = e.message;
    }
    _activationBusy = false;
    if (s != null) {
      await _onRegistered(s);
      if (status.value != SessionStatus.activation) return;
      final seconds = switch (s.status) {
        'pending' => 12, // come le altre app Kairos
        'maintenance' => 30,
        _ => 60,
      };
      _scheduleActivation(Duration(seconds: seconds));
    } else {
      activation.value = ActivationInfo(status: 'offline', message: '${error ?? 'Errore di rete'}. Riprovo tra poco…', warn: true);
      _scheduleActivation(const Duration(seconds: 8));
    }
  }

  void _scheduleActivation(Duration delay) {
    _activationTimer?.cancel();
    if (!_foreground) return;
    _activationTimer = Timer(delay, () => unawaited(_activationTick()));
  }

  /// Rilegge lo stato dal pannello e riallinea l'app.
  Future<void> refreshPanel() async {
    final panel = _panel;
    if (panel == null) return;
    _lastRegister = _clock.elapsedMilliseconds;
    try {
      final s = await panel.register();
      await _onRegistered(s);
    } on PanelException {
      // senza rete si continua con l'ultimo stato
    }
  }

  Future<void> _onRegistered(PanelState s) async {
    if (s.raw.containsKey('rc')) await _applyRemote(s.raw['rc'], asString(s.raw['rcv']) ?? '');
    if (!_updaterStarted && s.active) {
      _updaterStarted = true;
      updater.start();
    }
    final panel = _panel;
    // il pannello può indicare un nuovo indirizzo per sé stesso
    var moved = s.setting('serverUrl').trim();
    while (moved.endsWith('/')) {
      moved = moved.substring(0, moved.length - 1);
    }
    if (panel != null && moved.startsWith('https://') && moved != panel.server) {
      panel.server = moved;
      await _store.saveServer(moved);
    }

    if (s.status == 'maintenance') {
      // manutenzione: l'ultimo stato buono resta salvato, si aspetta che finisca
      _goActivation(ActivationInfo(
        status: 'maintenance',
        message: '${s.maintMsg.isEmpty ? 'Servizio in manutenzione: torna disponibile tra poco.' : s.maintMsg}\nL\'app riparte da sola appena finisce.',
        warn: true,
      ));
      return;
    }
    if (s.active) {
      await _store.savePanelState(s.raw);
      if (_watching != null) {
        // mai durante la visione: si applica quando il lettore si chiude
        _state = s;
        panelState.value = s;
        _deferredState = s;
        return;
      }
      await _applyState(s);
      return;
    }
    await _store.savePanelState(null);
    _state = s;
    panelState.value = s;
    _goActivation(_activationInfoFor(s));
  }

  void _goActivation(ActivationInfo info) {
    activation.value = info;
    if (status.value != SessionStatus.activation) {
      stopPreview(release: true);
      _stopPulse();
      if (_watching != null) unawaited(NativeBridge.closePlayer());
      status.value = SessionStatus.activation;
      _scheduleActivation(Duration(seconds: info.status == 'maintenance' ? 30 : 12));
    }
  }

  ActivationInfo _activationInfoFor(PanelState s) {
    String contact() {
      final price = s.setting('price');
      final c = s.setting('supportContact');
      return '${price.isNotEmpty ? '\nRinnovo: $price.' : ''}${c.isNotEmpty ? '\nContatto: $c' : ''}';
    }

    return switch (s.status) {
      'locked' => const ActivationInfo(
          status: 'locked',
          message: 'Questo codice è già usato da un altro dispositivo. Chiedi al tuo fornitore di sbloccarlo dal pannello.',
          warn: true,
        ),
      'expired' => ActivationInfo(
          status: 'expired',
          message: 'Abbonamento scaduto${s.expires.isEmpty ? '' : ' il ${s.expiresLabel}'}.${contact()}',
          warn: true,
        ),
      'disabled' => ActivationInfo(status: 'disabled', message: 'Abbonamento sospeso dal fornitore.${contact()}', warn: true),
      _ => const ActivationInfo(status: 'pending', message: 'In attesa di attivazione…'),
    };
  }

  /// Collega questa TV a un abbonamento già attivo con il codice a 6 cifre.
  Future<String?> linkWithPin(String pin) async {
    final panel = _panel;
    if (panel == null) return 'Server non configurato';
    final error = await panel.link(pin);
    if (error == null) await _activationTick();
    return error;
  }

  /// Codice a 6 cifre per collegare un'altra TV.
  Future<String> createLinkCode() async {
    final panel = _panel;
    if (panel == null) throw const PanelException('Server non configurato');
    return panel.linkCode();
  }

  bool get canLinkTv {
    final s = _state;
    return s != null && s.active && (s.account?.primary ?? true) && s.perm('link');
  }

  Future<String> privacyText() async {
    final panel = _panel;
    final text = panel == null ? '' : await panel.privacyText(_state);
    return text.isNotEmpty
        ? text
        : 'Usando l\'app accetti le condizioni del servizio del tuo fornitore. L\'app è solo un lettore: i contenuti arrivano dalle playlist assegnate dal fornitore.';
  }

  Future<void> acceptPrivacy() async {
    _privacyOk = true;
    await _store.savePrivacyOk();
  }

  List<PanelMessage> unseenMessages() => [
        for (final m in _state?.messages ?? const <PanelMessage>[])
          if (m.id.isNotEmpty && !_seenMessages.contains(m.id)) m,
      ];

  Future<void> markMessagesSeen(Iterable<PanelMessage> messages) async {
    _seenMessages.addAll([for (final m in messages) m.id]);
    await _store.saveSeenMessages(_seenMessages);
  }

  // ---------------------------------------------------------------------------
  // Playlist e catalogo

  List<PanelPlaylist> get playlists => [
        for (final p in _state?.playlists ?? const <PanelPlaylist>[])
          if (p.toAccount() != null) p,
      ];

  bool get canSwitchPlaylist => (_state?.perm('plSwitch') ?? false) && playlists.length > 1;

  PanelPlaylist? _choosePlaylist(PanelState s) {
    final all = [for (final p in s.playlists) if (p.toAccount() != null) p];
    if (all.isEmpty) return null;
    PanelPlaylist? find(String id) {
      for (final p in all) {
        if (p.id == id) return p;
      }
      return null;
    }

    if (_playlistChoice.isNotEmpty && s.perm('plSwitch')) {
      final chosen = find(_playlistChoice);
      if (chosen != null) return chosen;
    }
    return find(s.account?.plDefault ?? '') ?? all.first;
  }

  Future<void> choosePlaylist(String id) async {
    _playlistChoice = id;
    await _store.savePlaylistChoice(id);
    final s = _state;
    if (s != null && s.active) await _applyState(s);
  }

  Future<void> _applyState(PanelState s, {Future<Catalog?>? cache, Future<Catalog?>? home}) async {
    _state = s;
    panelState.value = s;
    final pl = _choosePlaylist(s);
    final account = pl?.toAccount();
    if (pl == null || account == null) {
      startupError = 'Nessuna playlist assegnata a questo dispositivo: chiedi al tuo fornitore di aggiungerla dal pannello.';
      status.value = SessionStatus.error;
      _startPulse();
      return;
    }
    final sig = pl.signature;
    final sameList = sig == _catalogSig;
    _playlist = pl;
    _useAccount(account);
    _startPulse();

    // stesso elenco (al massimo è cambiato il DNS): il catalogo resta quello che c'è
    if (sameList && catalog.value != null) {
      if (status.value != SessionStatus.ready) status.value = SessionStatus.ready;
      return;
    }
    if (sameList) {
      // all'avvio prima la Home (copia piccola, si legge in un attimo), poi tutto il catalogo
      final quick = home == null ? null : await home;
      if (quick != null && !quick.isEmpty && catalog.value == null) {
        catalog.value = quick;
        status.value = SessionStatus.ready;
      }
      final cached = await (cache ?? CatalogRepository.readCache());
      if (cached != null && !cached.isEmpty) {
        catalog.value = cached;
        status.value = SessionStatus.ready;
        unawaited(CatalogRepository.writeHome(cached, _favorites));
        if (cached.isStale) unawaited(_refreshInBackground());
        return;
      }
    }
    // niente cache valida: si scarica (se la Home è già a schermo, senza schermata di caricamento)
    if (catalog.value == null) status.value = SessionStatus.loading;
    final error = await _fetchAndApply();
    if (error != null) {
      startupError = error;
      status.value = SessionStatus.error;
      return;
    }
    _catalogSig = sig;
    await _store.saveCatalogSignature(sig);
    status.value = SessionStatus.ready;
  }

  void _useAccount(Account account) {
    final previous = _account;
    _account = account;
    _source = ContentSource.of(account);
    if (previous == null ||
        previous.server != account.server ||
        previous.username != account.username ||
        previous.m3uUrl != account.m3uUrl) {
      _epgCache.clear();
      _movieDetails.clear();
      _seriesDetails.clear();
    }
  }

  /// Aggiornamento chiesto dall'utente: le novità si vedono subito.
  Future<String?> refreshCatalog() => _fetchAndApply();

  Future<String?> _fetchAndApply() async {
    final account = _account;
    if (account == null) return 'Nessuna playlist configurata';
    try {
      final fresh = await CatalogRepository.fetch(account, favorites: _favorites);
      if (fresh.isEmpty) return 'La playlist non contiene contenuti';
      catalog.value = fresh;
      return null;
    } on net.SourceException catch (e) {
      return e.message;
    } on Object catch (e) {
      return 'Errore inatteso: $e';
    }
  }

  /// Aggiorna la cache su disco senza toccare quello che l'utente sta
  /// guardando: le novità compaiono al prossimo avvio, senza salti di focus.
  Future<void> _refreshInBackground() async {
    final account = _account;
    if (account == null) return;
    try {
      await CatalogRepository.fetch(account, favorites: _favorites);
    } on Object {
      // silenzioso: il catalogo in cache resta valido
    }
  }

  // ---------------------------------------------------------------------------
  // Battito verso il pannello (Online ora, Disconnetti, cambi dal pannello)

  final Stopwatch _clock = Stopwatch()..start();
  Timer? _pulseTimer;
  bool _foreground = true;
  bool _playerVisible = false;
  _Watch? _watching;
  List<PlaybackItem> _playing = const <PlaybackItem>[];
  int _lastBeat = -1;
  int _lastRegister = 0;
  String _lastSig = '';
  int _kickAck = 0;
  String _pv = '';
  bool _beating = false;

  void _startPulse() {
    if (_pulseTimer != null) return;
    _lastRegister = _clock.elapsedMilliseconds;
    _pulseTimer = Timer.periodic(const Duration(seconds: 20), (_) => unawaited(_beat(false)));
    Timer(const Duration(seconds: 4), () => unawaited(_beat(false)));
  }

  void _stopPulse() {
    _pulseTimer?.cancel();
    _pulseTimer = null;
  }

  Future<void> _beat(bool force) async {
    final s = _state;
    final panel = _panel;
    if (s == null || !s.active || panel == null || _beating) return;
    final w = _watching;
    if (!_foreground && (w == null || !_playerVisible)) return;
    final sig = '${w?.state ?? 'idle'}|${w?.channelId ?? ''}|${w?.title ?? ''}';
    final now = _clock.elapsedMilliseconds;
    if (!force && sig == _lastSig && _lastBeat >= 0 && now - _lastBeat < (w == null ? 60000 : 20000)) return;
    // il pannello accetta al massimo un battito ogni 15 secondi
    if (_lastBeat >= 0 && now - _lastBeat < 15000) return;
    _lastSig = sig;
    _lastBeat = now;
    _beating = true;
    try {
      final j = await panel.heartbeat(
        state: w?.state ?? 'idle',
        title: w?.title ?? '',
        channel: w?.channel ?? '',
        channelId: w?.channelId ?? '',
        group: w?.group ?? '',
        screen: w == null ? 'home' : 'player',
        kickAck: _kickAck,
        cfg: remoteSnapshot(),
        rcv: _rcv,
      );
      if (j != null) await _handleBeat(j);
    } finally {
      _beating = false;
    }
  }

  Future<void> _handleBeat(Map<String, dynamic> j) async {
    if (j.containsKey('rc')) await _applyRemote(j['rc'], asString(j['rcv']) ?? '');
    // «Invia aggiornamento» dal pannello (o aggiornamento automatico scelto dal fornitore)
    final upd = asInt(j['upd']) ?? 0;
    if (upd > 0 && upd != _updSeen) {
      _updSeen = upd;
      await _store.saveUpdSeen(upd);
      unawaited(updater.fromPanel());
    }
    final cmds = j['cmds'];
    if (cmds is List && cmds.isNotEmpty) unawaited(_runRemote(cmds));
    final kick = asInt(j['kick']) ?? 0;
    if (kick > 0) {
      _kickAck = kick;
      if (kick != _kickSeen) {
        _kickSeen = kick;
        unawaited(_store.saveKickSeen(kick));
        stopPreview(release: true);
        if (_watching != null) await NativeBridge.closePlayer();
        notice.value = 'Il tuo fornitore ha chiuso la visione su questo dispositivo.';
      }
    }
    final s = _state;
    if (s == null) return;
    var changed = false;
    final acc = s.account;
    final ms = asInt(j['ms']);
    if (ms != null && acc != null && ms != acc.maxStreams) changed = true;
    final pm = asString(j['pm']) ?? '';
    if (pm.isNotEmpty && acc != null && pm.split('|').take(2).join('|') != '${acc.plMode}|${acc.plDefault}') {
      changed = true;
    }
    if (j.containsKey('ph')) {
      var off = '';
      try {
        final keys = asMap(jsonDecode(asString(j['ph']) ?? '{}')).keys.toList()..sort();
        off = keys.join(',');
      } on FormatException {
        off = '';
      }
      if (off != s.offPerms()) changed = true;
    }
    final pv = asString(j['pv']) ?? '';
    if (pv.isNotEmpty) {
      if (_pv.isNotEmpty && pv != _pv) changed = true;
      _pv = pv;
    }
    if (asInt(j['mt']) == 1) changed = true; // manutenzione accesa dal pannello
    final unseen = asInt(j['unseen']) ?? -1;
    if (unseen > unseenMessages().length) changed = true;
    if (changed || _clock.elapsedMilliseconds - _lastRegister > 20 * 60000) await refreshPanel();
  }

  // ---------------------------------------------------------------------------
  // Riproduzione (lettore nativo)

  /// Apre il lettore. Restituisce un messaggio se la visione non è consentita.
  Future<String?> play(List<PlaybackItem> items, int index, {Duration? resumeAt}) async {
    if (items.isEmpty) return null;
    final i = index < 0 ? 0 : (index >= items.length ? items.length - 1 : index);
    final item = items[i];
    final panel = _panel;
    if (panel != null && (_state?.account?.maxStreams ?? 0) > 0) {
      final block = await panel.stream(item.watchState, item.title);
      if (block != null) return block;
    }
    // un solo video alla volta: il riquadro si chiude prima dello schermo intero
    _previewSeq++;
    preview.value = const PreviewState.idle();
    _inPlayer = true;
    _playing = items;
    _watching = _Watch.of(item);
    _playerVisible = true;
    unawaited(_beat(true));
    Map<String, dynamic>? result;
    try {
      result = await NativeBridge.play({
        'items': [for (final p in items) p.toPlayerJson()],
        'index': i,
        'resumeMs': resumeAt?.inMilliseconds ?? 0,
        'ua': net.userAgent,
        'lite': lite,
      });
    } on PlatformException catch (e) {
      return e.message ?? 'Lettore non disponibile';
    } finally {
      _watching = null;
      _playerVisible = false;
      _inPlayer = false;
    }
    for (final raw in asList(result?['updates'])) {
      final m = asMap(raw);
      final key = asString(m['key']);
      final played = key == null ? null : _findPlaying(key);
      if (played == null) continue;
      saveProgress(played, Duration(milliseconds: asInt(m['pos']) ?? 0), Duration(milliseconds: asInt(m['dur']) ?? 0), notify: false);
    }
    _playing = const <PlaybackItem>[];
    progressRevision.value++;
    _lastBeat = -1; // si torna a «nessuna visione» subito
    unawaited(_beat(true));
    final deferred = _deferredState;
    if (deferred != null) {
      _deferredState = null;
      await _applyState(deferred);
    }
    return null;
  }

  PlaybackItem? _findPlaying(String key) {
    for (final p in _playing) {
      if (p.key == key) return p;
    }
    return null;
  }

  void _onPlayerEvent(PlayerEvent e) {
    switch (e.type) {
      case 'playing':
        {
          final item = _findPlaying(e.key);
          if (item != null) {
            _watching = _Watch.of(item);
            unawaited(_beat(true));
          }
        }
      case 'progress':
        {
          final item = _findPlaying(e.key);
          if (item != null && e.duration > 0) {
            saveProgress(item, Duration(milliseconds: e.position), Duration(milliseconds: e.duration), notify: false);
          }
        }
      case 'background':
        _playerVisible = false;
      case 'foreground':
        _playerVisible = true;
    }
  }

  // ---------------------------------------------------------------------------
  // Anteprima dei canali (riquadro della TV in diretta)

  /// Fa partire il canale nel riquadro [rect] (punti logici dello schermo).
  /// Restituisce un messaggio se il pannello non consente la visione.
  Future<String?> startPreview(PlaybackItem item, Rect rect) async {
    final seq = ++_previewSeq;
    preview.value = PreviewState(item.key, 'loading');
    final panel = _panel;
    // come nelle altre app Kairos l'anteprima è una visione come le altre (limite del pannello)
    if (panel != null && (_state?.account?.maxStreams ?? 0) > 0) {
      final block = await panel.stream('live', item.title);
      if (seq != _previewSeq) return null; // nel frattempo si è passati ad altro
      if (block != null) {
        preview.value = const PreviewState.idle();
        return block;
      }
    }
    if (seq != _previewSeq) return null;
    _watching = _Watch.of(item);
    unawaited(_beat(true));
    await NativeBridge.previewShow({
      'key': item.key,
      'url': item.url,
      'alt': item.altUrls,
      'x': rect.left,
      'y': rect.top,
      'w': rect.width,
      'h': rect.height,
      'ua': net.userAgent,
      'lite': lite,
    });
    return null;
  }

  /// Ferma l'anteprima. [release] libera anche il decoder (si esce dalla TV in diretta).
  void stopPreview({bool release = false}) {
    _previewSeq++;
    final active = preview.value.key != null;
    if (active || release) unawaited(NativeBridge.previewStop(release: release));
    if (active) {
      preview.value = const PreviewState.idle();
      _clearPreviewWatch();
    }
  }

  void _clearPreviewWatch() {
    if (_inPlayer || _watching?.state != 'live') return;
    _watching = null;
    unawaited(_beat(true));
  }

  void _onPreviewEvent(PreviewEvent e) {
    final current = preview.value;
    if (current.key == null || current.key != e.key) return;
    switch (e.state) {
      case 'loading':
        preview.value = PreviewState(e.key, 'loading');
      case 'playing':
        preview.value = PreviewState(e.key, 'playing');
      case 'error':
        preview.value = PreviewState(e.key, 'error');
        _clearPreviewWatch();
      case 'stopped':
        preview.value = const PreviewState.idle();
        _clearPreviewWatch();
    }
  }

  Future<void> setPreviewMode(String mode) async {
    _previewMode = mode;
    await _store.savePreviewMode(mode);
    if (mode == 'off') stopPreview(release: true);
  }

  // ---------------------------------------------------------------------------
  // Grafica leggera

  void _applyLite() {
    final mode = liteMode;
    Perf.lite = mode == 'on' || mode == 'max' || (mode == 'auto' && device.isLite);
    // chiavette con poca memoria: meno immagini tenute in memoria
    final imageCache = PaintingBinding.instance.imageCache;
    imageCache.maximumSize = Perf.lite ? 160 : 250;
    imageCache.maximumSizeBytes = (Perf.lite ? 40 : 80) << 20;
  }

  Future<void> setLiteMode(String mode) async {
    final before = Perf.lite;
    _liteMode = mode;
    await _store.saveLiteMode(mode);
    _applyLite();
    if (Perf.lite != before) uiRevision.value++;
  }

  // ---------------------------------------------------------------------------
  // Controllo remoto dal pannello: impostazioni imposte (rc) e comandi (cmds)

  /// Impostazioni attuali dell'app, con le stesse chiavi del pannello.
  Map<String, Object?> remoteSnapshot() => {
        'lite': liteMode,
        'liteOn': Perf.lite ? 'on' : 'off',
        'preview': previewEnabled ? 'click' : 'off',
        'bgupd': bgUpdate ? 'on' : 'off',
      };

  /// Aggiornamento in background: scelta del cliente (se il pannello non l'ha imposta).
  Future<void> setBgUpdate(bool on) async {
    _bgUpdate = on;
    await _store.saveBgUpdate(on);
    uiRevision.value++;
  }

  Future<void> _applyRemote(Object? rc, String rcv) async {
    Map<String, dynamic> next;
    try {
      next = rc is String ? (rc.isEmpty ? const <String, dynamic>{} : asMap(jsonDecode(rc))) : asMap(rc);
    } on FormatException {
      next = const <String, dynamic>{};
    }
    final raw = jsonEncode(next);
    if (raw == jsonEncode(_rc) && rcv == _rcv) return;
    final before = Perf.lite;
    final previewBefore = previewEnabled;
    _rc = next;
    _rcv = rcv;
    await _store.saveRemote(raw, rcv);
    _applyLite();
    if (!previewEnabled && previewBefore) stopPreview(release: true);
    uiRevision.value++;
    if (_updaterStarted) updater.onForeground(); // es. aggiornamento appena reso obbligatorio dal pannello
    if (Perf.lite != before) uiRevision.value++;
  }

  Future<void> _runRemote(List<dynamic> cmds) async {
    final panel = _panel;
    if (panel == null) return;
    for (final raw in cmds) {
      final c = asMap(raw);
      final id = asInt(c['id']) ?? 0;
      final cmd = asString(c['c']) ?? '';
      if (id <= 0) continue;
      final watching = _watching != null;
      switch (cmd) {
        case 'reload':
          await panel.cmdAck(id, true, 'riavvio');
          remoteCmd.value = 'reload';
        case 'cache':
          await CatalogRepository.clearCache();
          try {
            await DefaultCacheManager().emptyCache();
          } on Object {
            // cache già vuota
          }
          PaintingBinding.instance.imageCache.clear();
          await panel.cmdAck(id, true, 'cache svuotata');
          remoteCmd.value = 'reload';
        case 'sync':
          if (watching) {
            await panel.cmdAck(id, false, 'visione in corso: rimandato');
          } else {
            unawaited(_fetchAndApply());
            await panel.cmdAck(id, true, 'catalogo in aggiornamento');
          }
        case 'settings':
          if (watching) await NativeBridge.closePlayer();
          remoteCmd.value = 'settings';
          await panel.cmdAck(id, true, 'impostazioni aperte');
        case 'update':
          await panel.cmdAck(id, true, await updater.fromPanel());
        case 'perm':
          if (watching) {
            await panel.cmdAck(id, false, 'visione in corso: rimandato');
          } else {
            final had = await NativeBridge.openInstallPerm();
            await panel.cmdAck(id, true, had ? 'permesso già concesso' : 'schermata del permesso aperta sulla TV');
          }
        case 'exit':
          await panel.cmdAck(id, true, 'chiusa');
          remoteCmd.value = 'exit';
        default:
          await panel.cmdAck(id, false, 'comando non supportato');
      }
    }
  }

  Future<void> setLiveFormat(String format) async {
    liveFormat.value = format;
    await _store.saveLiveFormat(format);
  }

  String urlFor(MediaItem item) => _source?.urlFor(item, liveFormat: liveFormat.value) ?? '';

  /// Indirizzo salvato (es. «Continua a guardare») riportato al server e all'utente attuali:
  /// se il pannello cambia DNS o credenziali la visione riparte lo stesso.
  String currentUrl(String url) {
    final acc = _account;
    if (acc == null || acc.type != AccountType.xtream) return url;
    final uri = Uri.tryParse(url);
    if (uri == null || uri.pathSegments.length < 4) return url;
    final kind = uri.pathSegments.first;
    if (kind != 'live' && kind != 'movie' && kind != 'series') return url;
    final u = Uri.encodeComponent(acc.username ?? '');
    final p = Uri.encodeComponent(acc.password ?? '');
    return '${acc.server}/$kind/$u/$p/${uri.pathSegments.last}';
  }

  PlaybackItem playbackForChannel(MediaItem channel) {
    final url = urlFor(channel);
    final alt = <String>[];
    if (_account?.type == AccountType.xtream) {
      final other = liveFormat.value == 'm3u8' ? 'ts' : 'm3u8';
      final second = _source?.urlFor(channel, liveFormat: other) ?? '';
      if (second.isNotEmpty && second != url) alt.add(second);
    }
    final cat = catalog.value?.categoryName(MediaKind.live, channel.categoryId) ?? '';
    return PlaybackItem(
      key: channel.key,
      title: channel.name,
      subtitle: cat.isEmpty ? null : cat,
      url: url,
      image: channel.image,
      isLive: true,
      kind: MediaKind.live,
      channel: channel,
      altUrls: alt,
      epgUrl: _source?.epgUrlFor(channel),
      group: cat,
    );
  }

  List<PlaybackItem> livePlaylist(List<MediaItem> channels) => [for (final c in channels) playbackForChannel(c)];

  PlaybackItem playbackForMovie(MediaItem movie) => PlaybackItem(
        key: movie.key,
        title: movie.name,
        subtitle: movie.year,
        url: urlFor(movie),
        image: movie.backdrop ?? movie.image,
        kind: MediaKind.movie,
      );

  PlaybackItem playbackForEpisode(MediaItem series, Episode episode) => PlaybackItem(
        key: episode.key,
        title: series.name,
        subtitle: 'S${episode.season} E${episode.number} · ${episode.title}',
        url: _source?.episodeUrl(episode) ?? '',
        image: episode.image ?? series.backdrop ?? series.image,
        kind: MediaKind.series,
      );

  /// Elemento di «Continua a guardare» pronto da riprodurre con l'indirizzo attuale.
  PlaybackItem resumable(PlaybackItem saved) => PlaybackItem(
        key: saved.key,
        title: saved.title,
        subtitle: saved.subtitle,
        url: currentUrl(saved.url),
        image: saved.image,
        kind: saved.kind,
      );

  // ---------------------------------------------------------------------------
  // Preferiti

  bool isFavorite(MediaItem item) => _favorites.contains(item.key);

  void toggleFavorite(MediaItem item) {
    if (!_favorites.remove(item.key)) _favorites.add(item.key);
    favoritesRevision.value++;
    unawaited(_store.saveFavorites(_favorites));
  }

  List<MediaItem> favoriteItems(MediaKind kind) {
    final c = catalog.value;
    if (c == null) return const <MediaItem>[];
    final result = <MediaItem>[];
    for (final key in _favorites) {
      final item = c.byKey(key);
      if (item != null && item.kind == kind) result.add(item);
    }
    return result;
  }

  // ---------------------------------------------------------------------------
  // Progressi ("Continua a guardare")

  WatchProgress? progressFor(String key) => _progress[key];

  List<WatchProgress> continueWatching() =>
      _progress.values.toList()..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  /// [notify] a false durante la riproduzione: si salva su disco senza
  /// ridisegnare le schermate sotto al lettore.
  void saveProgress(PlaybackItem item, Duration position, Duration duration, {bool notify = true}) {
    if (item.isLive || duration.inSeconds < 60) return;
    final fraction = position.inMilliseconds / duration.inMilliseconds;
    if (fraction > 0.95 || position.inSeconds < 15) {
      _progress.remove(item.key); // finito o appena iniziato
    } else {
      _progress[item.key] = WatchProgress(
        item: PlaybackItem(
          key: item.key,
          title: item.title,
          subtitle: item.subtitle,
          url: item.url,
          image: item.image,
          kind: item.kind,
        ),
        positionMs: position.inMilliseconds,
        durationMs: duration.inMilliseconds,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );
    }
    if (_progress.length > 40) {
      final keep = continueWatching().take(40).toList();
      _progress = {for (final p in keep) p.item.key: p};
    }
    unawaited(_store.saveProgress(_progress.values));
    if (notify) progressRevision.value++;
  }

  // ---------------------------------------------------------------------------
  // Dettagli e guida TV (con cache in memoria)

  Future<MovieDetails?> movieDetails(MediaItem movie) {
    final source = _source;
    if (source == null) return Future<MovieDetails?>.value(null);
    return _movieDetails.putIfAbsent(movie.id, () async {
      try {
        return await source.movieDetails(movie);
      } on Object {
        _movieDetails.remove(movie.id); // si riproverà la prossima volta
        return null;
      }
    });
  }

  Future<SeriesDetails?> seriesDetails(MediaItem series) {
    final source = _source;
    if (source == null) return Future<SeriesDetails?>.value(null);
    return _seriesDetails.putIfAbsent(series.id, () async {
      try {
        return await source.seriesDetails(series);
      } on Object {
        _seriesDetails.remove(series.id);
        return null;
      }
    });
  }

  Future<List<EpgEntry>> epgFor(MediaItem channel) async {
    final source = _source;
    if (source == null || !source.supportsEpg) return const <EpgEntry>[];
    final now = DateTime.now();
    final cached = _epgCache[channel.id];
    if (cached != null && now.difference(cached.$1) < const Duration(minutes: 5)) return cached.$2;
    try {
      final list = await source.shortEpg(channel);
      _epgCache[channel.id] = (now, list);
      return list;
    } on Object {
      return const <EpgEntry>[];
    }
  }

  void dispose() {
    _activationTimer?.cancel();
    _stopPulse();
    _lifecycle?.dispose();
    unawaited(_playerSub?.cancel());
    unawaited(_previewSub?.cancel());
    status.dispose();
    activation.dispose();
    panelState.dispose();
    catalog.dispose();
    liveFormat.dispose();
    favoritesRevision.dispose();
    progressRevision.dispose();
    notice.dispose();
    remoteCmd.dispose();
    _updater?.dispose();
    preview.dispose();
    uiRevision.dispose();
  }
}
