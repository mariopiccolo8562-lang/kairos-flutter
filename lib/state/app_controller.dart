import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../app/brand.dart';
import '../app/perf.dart';
import '../core/json.dart';
import '../core/native.dart';
import '../core/net.dart' as net;

import '../data/catalog_repository.dart';
import '../data/home_rules.dart';
import '../data/models.dart';
import '../data/sources/content_source.dart';
import '../data/user_store.dart';
import '../panel/panel.dart';
import '../ui/widgets/net_image.dart';
import 'app_updater.dart';
import 'remote_quiet.dart';

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

  /// idle | loading | playing | error | ended
  final String status;

  bool isFor(String channelKey) => key == channelKey;

  /// Il riquadro sta davvero caricando o riproducendo (con error / ended il decoder è fermo).
  bool get active => key != null && (status == 'loading' || status == 'playing');
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
  /// PIN reimpostato dal pannello durante la visione: il nuovo PIN si chiede a visione finita.
  final PinAsk _pinAsk = PinAsk();
  /// Aggiornamento dell'app (feed delle release, scaricamento in background, installazione).
  AppUpdater? _updater;
  AppUpdater get updater => _updater!;
  /// Aggiornamento in background acceso (imposto dal pannello o scelto qui).
  bool get bgUpdate => imposed('bgupd') ? _rc['bgupd'].toString() == 'on' : _bgUpdate;
  String _previewMode = 'click';
  int _previewSeq = 0;

  // ---- controllo genitori: attivo di serie con il PIN 0000; al primo avvio si chiede di sceglierne uno proprio.
  //      Il pannello può riportare il PIN a 0000 (comando «Reimposta PIN») se il cliente lo dimentica.
  bool _parental = true;
  String _pin = '';
  int _pinLater = 0;
  /// PIN già inserito in questa apertura: i contenuti protetti restano aperti fino alla chiusura.
  bool parentalUnlocked = false;
  /// Cresce quando il controllo genitori si sblocca o cambia: le pagine si ridisegnano.
  final ValueNotifier<int> parentalRevision = ValueNotifier(0);
  bool get parentalOn => _parental;
  bool get pinIsDefault => _pin.isEmpty;
  bool checkPin(String p) => p.trim() == (_pin.isEmpty ? '0000' : _pin);
  /// Va chiesto di scegliere il PIN (primo avvio o PIN reimpostato; «Più tardi» rimanda al giorno dopo).
  bool get pinAskDue => _parental && _pin.isEmpty && DateTime.now().millisecondsSinceEpoch - _pinLater > 86400000;
  Future<void> setParental(bool on) async {
    _parental = on;
    parentalUnlocked = false;
    await _store.saveParental(on);
    parentalRevision.value++;
  }
  Future<void> setPin(String pin) async {
    _pin = pin;
    _pinLater = 0;
    await _store.savePin(pin);
    await _store.savePinLater(0);
    parentalRevision.value++;
  }
  Future<void> postponePin() async {
    _pinLater = DateTime.now().millisecondsSinceEpoch;
    await _store.savePinLater(_pinLater);
  }
  void parentalUnlock() {
    parentalUnlocked = true;
    parentalRevision.value++;
  }
  bool parentalLockedCategory(MediaKind kind, String categoryId) =>
      _parental && !parentalUnlocked && (catalog.value?.isAdultCategory(kind, categoryId) ?? false);
  bool parentalLocked(MediaItem x) => _parental && !parentalUnlocked && (catalog.value?.isAdult(x) ?? false);
  bool parentalLockedPlayback(PlaybackItem it) =>
      _parental && !parentalUnlocked &&
      ((it.channel != null && (catalog.value?.isAdult(it.channel!) ?? false)) || isAdultText(it.group) || adultNameRx.hasMatch(it.title));
  bool _inPlayer = false;

  /// Messaggio da mostrare se il catalogo non si è potuto caricare.
  String? startupError;

  final Map<String, (DateTime, List<EpgEntry>)> _epgCache = {};
  final Map<String, Future<MovieDetails?>> _movieDetails = {};
  final Map<String, Future<SeriesDetails?>> _seriesDetails = {};

  AppLifecycleListener? _lifecycle;
  bool _disposed = false;
  StreamSubscription<PlayerEvent>? _playerSub;
  StreamSubscription<PreviewEvent>? _previewSub;

  /// Grafica leggera (scelta dall'utente o automatica sulle chiavette con poca memoria).
  bool get lite => Perf.lite;

  /// auto | on | off. Senza il permesso «lite» del pannello la scelta del cliente non vale (resta salvata):
  /// decide il pannello se l'ha imposta, altrimenti il rilevamento automatico.
  String get liteMode => switch (_rc['lite']?.toString() ?? '') {
        'auto' || 'on' || 'max' || 'off' => _rc['lite'].toString(),
        _ => _permLite ? _liteMode : 'auto',
      };

  /// Il cliente può cambiare la modalità leggera (permesso «lite» del pannello: assente = sì).
  bool _permLite = true;

  /// Modalità leggera bloccata nelle Impostazioni: imposta dal pannello o permesso spento («scelta dal fornitore»).
  bool get liteLocked => imposed('lite') || !_permLite;

  /// Home decisa dal pannello: categorie in primo piano (rc «home.top») e nascoste (rc «home.hide»).
  HomeRules get homeRules {
    final top = asString(_rc['home.top']) ?? '';
    final hide = asString(_rc['home.hide']) ?? '';
    final current = _homeRules;
    if (current.source == '$top\n$hide') return current;
    return _homeRules = HomeRules.parse(top, hide);
  }

  HomeRules _homeRules = HomeRules.none;

  /// Anteprima dei canali attiva: 1° OK nel riquadro, 2° OK schermo intero.
  bool get previewEnabled => (imposed('preview') ? _rc['preview'].toString() : _previewMode) != 'off';

  /// Formato dei canali in diretta imposto dal pannello (o.liveFmt: ts | hls), null = decide il cliente.
  String? get _rcLiveFormat => switch (_rc['o.liveFmt']?.toString() ?? '') { 'ts' => 'ts', 'hls' => 'm3u8', _ => null };
  /// Formato effettivo: quello del pannello se imposto, altrimenti quello scelto nelle Impostazioni.
  void _applyLiveFormat() {
    final v = _rcLiveFormat ?? _userLiveFormat;
    if (liveFormat.value != v) liveFormat.value = v;
  }
  String _userLiveFormat = 'ts';
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

    // impostazioni salvate: le richieste partono tutte insieme (una alla volta erano una ventina di andate e
    // ritorni con la parte Android, che all'avvio sulle chiavette si sentono)
    final settingsWait = (
      _store.loadBgUpdate(),
      _store.loadUpdSeen(),
      _store.loadLiteMode(),
      _store.loadRemote(),
      _store.loadPreviewMode(),
      _store.loadParental(),
      _store.loadPin(),
      _store.loadPinLater(),
      _store.loadServer(),
    ).wait;
    final userWait = (
      _store.loadFavorites(),
      _store.loadProgress(),
      _store.loadLiveFormat(),
      _store.loadSeenMessages(),
      _store.loadPlaylistChoice(),
      _store.loadCatalogSignature(),
      _store.loadPrivacyOk(),
      _store.loadKickSeen(),
      _store.loadIdentity(),
    ).wait;

    device = await NativeBridge.device();
    final (savedBg, savedUpdSeen, savedLite, savedRemote, savedPreview, savedParental, savedPin, savedPinLater, savedServer) =
        await settingsWait;
    _bgUpdate = savedBg;
    _updSeen = savedUpdSeen;
    _updater = AppUpdater(
      feedUrl: Brand.updateFeed,
      currentCode: device.versionCode,
      currentVersion: device.version,
      backgroundEnabled: () => bgUpdate,
      forceDays: () => switch (_rc['force']?.toString()) { 'now' => 0, '3d' => 3, '7d' => 7, _ => null },
      watching: () => _watching != null || _busyWatching,
      loadFirstSeen: _store.loadUpdFirst,
      saveFirstSeen: _store.saveUpdFirst,
      loadPending: _store.loadUpdPending,
      savePending: _store.saveUpdPending,
    );
    final model = device.rawModel.replaceAll(RegExp(r'[^\x20-\x7E]'), '').trim();
    net.userAgent =
        'Mozilla/5.0 (Linux; Android ${device.release.isEmpty ? '9' : device.release}; ${model.isEmpty ? 'Android' : model}) KairosPlus/$appVersion';

    _liteMode = savedLite;
    {
      final (rc, rcv) = savedRemote;
      try {
        _rc = rc.isEmpty ? const <String, dynamic>{} : asMap(jsonDecode(rc));
      } on FormatException {
        _rc = const <String, dynamic>{};
      }
      _rcv = rcv;
    }
    _previewMode = savedPreview;
    _parental = savedParental;
    _pin = savedPin;
    _pinLater = savedPinLater;
    _permLite = cachedState?.perm('lite') ?? true; // permesso dell'ultimo stato: niente cambio di grafica all'avvio
    _applyLite();

    final (savedFavorites, savedProgress, savedFormat, savedSeen, savedPlaylist, savedSig, savedPrivacy, savedKick, savedIdentity) =
        await userWait;
    _favorites = savedFavorites;
    _progress = savedProgress;
    _userLiveFormat = savedFormat;
    _applyLiveFormat();
    _seenMessages = savedSeen;
    _playlistChoice = savedPlaylist;
    _catalogSig = savedSig;
    _privacyOk = savedPrivacy;
    _kickSeen = savedKick;
    // aggiornamento trovato in un'apertura precedente (anche senza rete): se è obbligatorio e scaduto la finestra
    // che blocca l'app compare subito, prima di qualsiasi visione (non aspetta il controllo in rete)
    unawaited(updater.restore());

    var id = savedIdentity == null ? null : PanelIdentity(savedIdentity.$1, savedIdentity.$2);
    if (id == null || !id.isValid) {
      id = PanelIdentity.generate();
      await _store.saveIdentity(id.code, id.secret);
    }
    _panel = PanelClient(
      identity: id,
      server: savedServer != null && savedServer.startsWith('https://') ? savedServer : kDefaultPanelUrl,
      model: device.model,
      version: appVersion,
      fallbacks: [kDefaultPanelUrl, ...kFallbackPanelUrls],
      onServerChanged: (url) => unawaited(_store.saveServer(url)),
    );

    _playerSub = NativeBridge.playerEvents.listen(_onPlayerEvent);
    _previewSub = NativeBridge.previewEvents.listen(_onPreviewEvent);
    // presenza: «in sfondo» quando nessuna schermata dell'app è visibile (paused / hidden / detached)
    _lifecycle = AppLifecycleListener(onResume: _onResume, onShow: _onShow, onHide: _onHide, onPause: _onHide, onDetach: _onHide);
    // lavoro non urgente (tetto della cache delle immagini su disco): ad avvio finito
    Timer(const Duration(seconds: 20), _trimImages);

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
    _visibilityChanged();
    if (status.value == SessionStatus.activation) {
      unawaited(_activationTick());
    } else if (status.value == SessionStatus.ready) {
      unawaited(_beat(true));
      // di ritorno dalle impostazioni del permesso «Installa app sconosciute»: l'installazione riparte da sola
      unawaited(updater.onResumed());
      if (_updaterStarted) updater.onForeground();
    }
  }

  /// L'interfaccia è di nuovo visibile (ritorno dalla Home del televisore o da un'altra app).
  void _onShow() {
    _foreground = true;
    _visibilityChanged();
  }

  /// L'interfaccia non è più visibile: Home del televisore, altra app, oppure il lettore a schermo intero
  /// (in quel caso l'app resta in primo piano: lo decide [_visible]).
  void _onHide() {
    _foreground = false;
    _activationTimer?.cancel();
    _visibilityChanged();
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
    _applyPerms(s);
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
        unawaited(CatalogRepository.writeHome(cached, _favorites, rules: homeRules));
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

  /// Un solo scaricamento del catalogo alla volta: chi lo chiede mentre è in corso
  /// (aggiornamento in background e «Aggiorna» insieme) aspetta lo stesso Future.
  Future<Catalog>? _fetching;
  bool _refreshDeferred = false;

  Future<Catalog> _fetchShared(Account account) {
    final rules = homeRules;
    return _fetching ??= CatalogRepository.fetch(
      account,
      favorites: _favorites,
      homeTop: rules.top.join(','),
      homeHide: rules.hide.join(','),
    ).whenComplete(() {
      _fetching = null;
    });
  }

  Future<String?> _fetchAndApply() async {
    final account = _account;
    if (account == null) return 'Nessuna playlist configurata';
    try {
      final fresh = await _fetchShared(account);
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
  /// Mai durante la visione (schermo intero o riquadro): riparte alla chiusura del lettore.
  Future<void> _refreshInBackground() async {
    final account = _account;
    if (account == null) return;
    if (_busyWatching) {
      _refreshDeferred = true;
      return;
    }
    _refreshDeferred = false;
    try {
      await _fetchShared(account);
    } on Object {
      // silenzioso: il catalogo in cache resta valido
    }
  }

  /// Un lettore è attivo (schermo intero o anteprima): niente lavori di fondo.
  bool get _busyWatching => _inPlayer || preview.value.active;

  /// La visione è finita: ripartono i lavori rimandati (catalogo, APK, stato del pannello).
  Future<void> _resumeDeferred() async {
    if (_busyWatching) return;
    if (_trimDue) _trimImages();
    if (_refreshDeferred) unawaited(_refreshInBackground());
    // anche con l'aggiornamento ripristinato all'avvio senza rete: la proposta rimandata dalla visione si mostra ora
    _updater?.onPlaybackEnded();
    final deferred = _deferredState;
    if (deferred != null) {
      _deferredState = null;
      await _applyState(deferred);
    }
  }

  /// Tetto della cache su disco delle immagini (D 150 MB, le altre 250 MB): una volta per apertura,
  /// 20 s dopo l'avvio e mai durante la visione (in quel caso a visione finita).
  bool _trimDue = false;

  void _trimImages() {
    if (_disposed) return;
    if (_busyWatching) {
      _trimDue = true;
      return;
    }
    _trimDue = false;
    unawaited(NetImageCache.trimDisk(weak: Perf.weak));
  }

  /// È partita una visione: il download dell'APK in corso si ferma.
  void _onWatchStart() {
    _updater?.onPlaybackStarted();
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
  // ultime misure del lettore (banda, classi, stalli…): vanno al pannello nel battito
  Map<String, Object?> _stats = const <String, Object?>{};

  // presenza: con l'app visibile (menu o lettore) ogni battito porta vis:true; quando va in sfondo il battito
  // periodico si ferma e parte un solo battito vis:false (il pannello la mostra subito non in linea)
  bool _pulseOn = false; // dispositivo attivo: il battito periodico serve (quando l'app è visibile)
  bool _shown = true; // visibilità già comunicata al pannello
  Future<void>? _beatCall; // battito normale in viaggio
  Future<void>? _hiddenCall; // «vado in sfondo» in viaggio
  int _hiddenSeq = 0;
  Timer? _resumeTimer;

  /// Una schermata dell'app è visibile: l'interfaccia oppure il lettore a schermo intero.
  bool get _visible => _foreground || (_inPlayer && _playerVisible);

  void _startPulse() {
    if (_pulseOn) return;
    _pulseOn = true;
    _lastRegister = _clock.elapsedMilliseconds;
    _runPulse();
    Timer(const Duration(seconds: 4), () => unawaited(_beat(false)));
  }

  void _stopPulse() {
    _pulseOn = false;
    _resumeTimer?.cancel();
    _resumeTimer = null;
    _runPulse();
  }

  /// Battito periodico: gira solo con il dispositivo attivo e l'app visibile.
  void _runPulse() {
    _pulseTimer?.cancel();
    _pulseTimer = _pulseOn && _shown && !_disposed ? Timer.periodic(const Duration(seconds: 20), (_) => unawaited(_beat(false))) : null;
  }

  /// L'app è passata in sfondo o è tornata visibile (interfaccia o lettore): lo si dice subito al pannello.
  /// Il passaggio dall'interfaccia al lettore (e ritorno) non cambia nulla: l'app resta visibile.
  void _visibilityChanged() {
    final visible = _visible;
    if (_disposed || visible == _shown) return;
    _shown = visible;
    _runPulse();
    if (visible) {
      unawaited(_resumeBeat());
    } else {
      _resumeTimer?.cancel();
      _resumeTimer = null;
      final seq = ++_hiddenSeq;
      _hiddenCall = _beatHidden(_hiddenCall).whenComplete(() {
        if (seq == _hiddenSeq) _hiddenCall = null;
      });
    }
  }

  /// L'app si sta chiudendo (Esci, comando del pannello): il «vado in sfondo» parte subito e lo si aspetta al
  /// massimo un attimo, perché con l'app chiusa la richiesta si interromperebbe.
  Future<void> beforeExit() async {
    _foreground = false;
    _visibilityChanged();
    final call = _hiddenCall;
    if (call != null) await call.timeout(const Duration(milliseconds: 1500), onTimeout: () {});
  }

  /// Di nuovo visibile: battito subito (vis:true), anche se non è passato il minuto dei menu.
  /// Se il pannello chiede di aspettare (15 s dall'ultimo battito vero, HTTP 429) si riprova dopo l'attesa;
  /// se la rete non risponde o un altro battito è in viaggio, si riprova tra poco.
  Future<void> _resumeBeat([int round = 0]) async {
    _resumeTimer?.cancel();
    _resumeTimer = null;
    if (!_shown) return;
    final wait = await _beat(true);
    if (wait == 0 || !_shown || round >= 4) return;
    _resumeTimer = Timer(Duration(milliseconds: wait > 0 ? wait + 500 : 3000), () => unawaited(_resumeBeat(round + 1)));
  }

  /// Un solo battito «vado in sfondo» (vis:false, idle) con gli stessi campi di sempre, dopo quelli ancora in
  /// viaggio. Non aggiorna l'istante dell'ultimo battito: al ritorno in primo piano il battito parte subito.
  Future<void> _beatHidden(Future<void>? before) async {
    try {
      if (before != null) await before;
      final regular = _beatCall;
      if (regular != null) await regular;
      final s = _state;
      final panel = _panel;
      if (_visible || s == null || !s.active || panel == null) return;
      await panel.heartbeat(
        state: 'idle',
        screen: 'home',
        kickAck: _kickAck,
        cfg: remoteSnapshot(),
        rcv: _rcv,
        vis: false,
      );
    } on Object {
      // senza rete il pannello la vedrà comunque non in linea dopo qualche minuto
    }
  }

  /// Manda il battito se serve (solo con l'app visibile). Restituisce 0 se è partito o non serve, altrimenti
  /// i millisecondi dopo cui riprovare (limite dei 15 s, HTTP 429) oppure -1 (rete, altro battito in corso).
  Future<int> _beat(bool force) async {
    final s = _state;
    final panel = _panel;
    if (s == null || !s.active || panel == null || !_visible) return 0;
    if (_beating) return -1;
    final w = _watching;
    final sig = '${w?.state ?? 'idle'}|${w?.channelId ?? ''}|${w?.title ?? ''}';
    final now = _clock.elapsedMilliseconds;
    if (!force && sig == _lastSig && _lastBeat >= 0 && now - _lastBeat < (w == null ? 60000 : 20000)) return 0;
    // il pannello accetta al massimo un battito ogni 15 secondi
    if (_lastBeat >= 0 && now - _lastBeat < 15000) return 15000 - (now - _lastBeat);
    _beating = true;
    try {
      // il «vado in sfondo» ancora in viaggio deve arrivare prima di questo battito
      final hidden = _hiddenCall;
      if (hidden != null) {
        await hidden;
        if (!_visible) return 0;
      }
      final sentAt = _clock.elapsedMilliseconds;
      final call = panel.heartbeat(
        state: w?.state ?? 'idle',
        title: w?.title ?? '',
        channel: w?.channel ?? '',
        channelId: w?.channelId ?? '',
        group: w?.group ?? '',
        screen: w == null ? 'home' : 'player',
        kickAck: _kickAck,
        cfg: remoteSnapshot(),
        rcv: _rcv,
        stats: _stats,
        vis: true,
      );
      _beatCall = call;
      final r = await call.whenComplete(() {
        if (identical(_beatCall, call)) _beatCall = null;
      });
      if (r.status == 429) return r.wait > 0 ? r.wait * 1000 : -1;
      final j = r.body;
      if (!r.ok || j == null) return -1;
      // solo un battito accettato conta per il limite di frequenza: uno fallito o rifiutato si riprova presto
      _lastSig = sig;
      _lastBeat = sentAt;
      await _handleBeat(j);
      return 0;
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
        // «Disconnetti» dal pannello: la visione si chiude, senza avvisi al cliente
        if (_watching != null) await NativeBridge.closePlayer();
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
    // un lettore già aperto (doppio OK, comando dal pannello): niente seconda PlayerActivity
    if (items.isEmpty || _inPlayer) return null;
    final i = index < 0 ? 0 : (index >= items.length ? items.length - 1 : index);
    final item = items[i];
    _inPlayer = true; // da subito: ferma i lavori di fondo e le richieste doppie già durante il controllo del pannello
    // aggiornamento obbligatorio scaduto (anche ripristinato all'avvio, senza rete): niente visione, prima la finestra
    final upd = _updater;
    if (upd != null) {
      await upd.restored;
      if (upd.remindIfMandatory()) {
        _inPlayer = false;
        return null;
      }
    }
    final panel = _panel;
    if (panel != null && (_state?.account?.maxStreams ?? 0) > 0) {
      final block = await panel.stream(item.watchState, item.title);
      if (block != null) {
        _inPlayer = false;
        return block;
      }
    }
    // un solo video alla volta: il riquadro si chiude prima dello schermo intero
    _previewSeq++;
    preview.value = const PreviewState.idle();
    _playing = items;
    _watching = _Watch.of(item);
    _playerVisible = true;
    _onWatchStart();
    unawaited(_beat(true));
    // il video ha bisogno di memoria: si liberano le immagini non a schermo (tornano dalla cache su disco)
    PaintingBinding.instance.imageCache.clear();
    Map<String, dynamic>? result;
    try {
      result = await NativeBridge.play({
        'items': [for (final p in items) p.toPlayerJson()],
        'index': i,
        'resumeMs': resumeAt?.inMilliseconds ?? 0,
        'ua': net.userAgent,
        'lite': lite,
        'playerClass': device.playerClass,
        // permesso «resInd»: riquadro con qualità, risoluzione e FPS sui canali in diretta (assente = sì)
        'resInd': _state?.perm('resInd') ?? true,
      });
    } on PlatformException catch (e) {
      return e.message ?? 'Lettore non disponibile';
    } finally {
      _watching = null;
      _playerVisible = false;
      _inPlayer = false;
      _pinAskAfterView();
      // di solito l'interfaccia torna visibile subito; se invece l'app è finita in sfondo lo si dice al pannello
      Timer(const Duration(seconds: 2), _visibilityChanged);
    }
    final finalStats = asMap(result?['stats']);
    if (finalStats.isNotEmpty) _stats = finalStats;
    for (final raw in asList(result?['updates'])) {
      final m = asMap(raw);
      final key = asString(m['key']);
      final played = key == null ? null : _findPlaying(key);
      if (played == null) continue;
      saveProgress(played, Duration(milliseconds: asInt(m['pos']) ?? 0), Duration(milliseconds: asInt(m['dur']) ?? 0), notify: false);
    }
    _playing = const <PlaybackItem>[];
    progressRevision.value++;
    _lastBeat = -1; // si torna a «nessuna visione» subito (con le misure finali del lettore)
    unawaited(_beat(true));
    _stats = const <String, Object?>{};
    await _resumeDeferred();
    return null;
  }

  PlaybackItem? _findPlaying(String key) {
    for (final p in _playing) {
      if (p.key == key) return p;
    }
    return null;
  }

  void _onPlayerEvent(PlayerEvent e) {
    final stats = e.stats;
    if (stats.isNotEmpty) _stats = stats;
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
        // lettore non più visibile (Home del televisore durante la visione): l'app va in sfondo
        _playerVisible = false;
        _visibilityChanged();
      case 'foreground':
        _playerVisible = true;
        _visibilityChanged();
    }
  }

  // ---------------------------------------------------------------------------
  // Anteprima dei canali (riquadro della TV in diretta)

  /// Fa partire il canale nel riquadro [rect] (punti logici dello schermo).
  /// Restituisce un messaggio se il pannello non consente la visione.
  Future<String?> startPreview(PlaybackItem item, Rect rect) async {
    final seq = ++_previewSeq;
    // aggiornamento obbligatorio scaduto: niente anteprima, prima la finestra dell'aggiornamento
    final upd = _updater;
    if (upd != null) {
      await upd.restored;
      if (seq != _previewSeq || upd.remindIfMandatory()) return null;
    }
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
    _onWatchStart();
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
      'playerClass': device.playerClass,
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
    if (_inPlayer) return;
    // i lavori rimandati ripartono tra poco: se nel frattempo si apre lo schermo intero restano in attesa
    Timer(const Duration(seconds: 2), () => unawaited(_resumeDeferred()));
    if (_watching?.state != 'live') return;
    _watching = null;
    unawaited(_beat(true));
    _pinAskAfterView();
  }

  /// Visione finita con un reset del PIN in attesa: poco dopo (interfaccia di nuovo a schermo) si chiede il nuovo PIN.
  void _pinAskAfterView() {
    if (!_pinAsk.pending) return;
    Timer(const Duration(milliseconds: 1200), () {
      if (_watching != null) return; // di nuovo in visione: si aspetta la prossima fine
      if (_pinAsk.onViewEnd()) remoteCmd.value = 'pin';
    });
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
      case 'ended':
        // trasmissione finita: il riquadro si è spento da solo
        preview.value = PreviewState(e.key, 'ended');
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
    // classe D di Kairos Adaptive (≤ 1,2 GB): immagini più piccole e il tetto più basso in memoria
    Perf.weak = device.playerClass == 'D';
    // chiavette con poca memoria: meno immagini tenute in memoria (D 24 MB, grafica leggera 40 MB, le altre 80 MB)
    final imageCache = PaintingBinding.instance.imageCache;
    imageCache.maximumSize = Perf.weak ? 120 : (Perf.lite ? 160 : 250);
    imageCache.maximumSizeBytes = (Perf.weak ? 24 : (Perf.lite ? 40 : 80)) << 20;
  }

  /// Permessi del pannello che cambiano la grafica (modalità leggera): si riapplicano a ogni stato nuovo.
  void _applyPerms(PanelState s) {
    final allowed = s.perm('lite');
    if (allowed == _permLite) return;
    _permLite = allowed;
    final before = Perf.lite;
    _applyLite();
    if (Perf.lite != before) uiRevision.value++;
  }

  Future<void> setLiteMode(String mode) async {
    if (liteLocked) return; // scelta dal fornitore
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
        'o.liveFmt': liveFormat.value == 'm3u8' ? 'hls' : 'ts',
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
    _applyLiveFormat();
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
          await NetImageCache.clear();
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
        case 'pin':
          // senza avvisi sul «fornitore»: si chiede subito il nuovo PIN, come alla prima installazione (a visione finita)
          await setPin('');
          parentalUnlocked = false;
          await panel.cmdAck(id, true, 'PIN riportato a 0000');
          if (_pinAsk.onReset(watching: watching)) remoteCmd.value = 'pin';
        case 'exit':
          await panel.cmdAck(id, true, 'chiusa');
          remoteCmd.value = 'exit';
        default:
          await panel.cmdAck(id, false, 'comando non supportato');
      }
    }
  }

  Future<void> setLiveFormat(String format) async {
    if (imposed('o.liveFmt')) return; // scelto dal fornitore
    _userLiveFormat = format;
    _applyLiveFormat();
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
    _disposed = true;
    _activationTimer?.cancel();
    _stopPulse();
    net.closeClient();
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
    remoteCmd.dispose();
    _updater?.dispose();
    preview.dispose();
    uiRevision.dispose();
  }
}
