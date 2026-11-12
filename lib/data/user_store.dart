import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../core/json.dart';
import 'models.dart';

/// Dati salvati sul dispositivo: identità per il pannello, ultimo stato,
/// preferiti, progressi e impostazioni.
class UserStore {
  final SharedPreferencesAsync _prefs = SharedPreferencesAsync();

  static const String _kCode = 'panel_code';
  static const String _kSecret = 'panel_secret';
  static const String _kServer = 'panel_server';
  static const String _kState = 'panel_state';
  static const String _kPlaylist = 'playlist_choice';
  static const String _kCatalogSig = 'catalog_sig';
  static const String _kSeenMessages = 'seen_messages';
  static const String _kPrivacyOk = 'privacy_ok';
  static const String _kKickSeen = 'kick_seen';
  static const String _kFavorites = 'favorites';
  static const String _kProgress = 'progress';
  static const String _kLiveFormat = 'live_format';
  static const String _kLiteMode = 'lite_mode';
  static const String _kRc = 'rc_json';
  static const String _kRcv = 'rc_ver';
  static const String _kPreviewMode = 'preview_mode';
  static const String _kBgUpdate = 'bg_update';
  static const String _kParental = 'parental_on';
  static const String _kPin = 'parental_pin';
  static const String _kPinLater = 'parental_pin_later';
  static const String _kUpdSeen = 'upd_seen';
  static const String _kUpdFirst = 'upd_first';
  static const String _kUpdPending = 'upd_pending';
  static const String _kDlMirrors = 'dl_mirrors';

  // ---------------------------------------------------------------------------
  // Pannello

  Future<(String, String)?> loadIdentity() async {
    final code = await _prefs.getString(_kCode);
    final secret = await _prefs.getString(_kSecret);
    if (code == null || secret == null || code.isEmpty || secret.isEmpty) return null;
    return (code, secret);
  }

  Future<void> saveIdentity(String code, String secret) async {
    await _prefs.setString(_kCode, code);
    await _prefs.setString(_kSecret, secret);
  }

  Future<String?> loadServer() => _prefs.getString(_kServer);

  Future<void> saveServer(String url) => _prefs.setString(_kServer, url);

  /// Ultimo stato attivo ricevuto dal pannello: l'app parte subito anche senza rete.
  Future<Map<String, dynamic>?> loadPanelState() async {
    final raw = await _prefs.getString(_kState);
    if (raw == null || raw.isEmpty) return null;
    try {
      final m = asMap(jsonDecode(raw));
      return m.isEmpty ? null : m;
    } on FormatException {
      return null;
    }
  }

  Future<void> savePanelState(Map<String, dynamic>? state) async {
    if (state == null) {
      await _prefs.remove(_kState);
    } else {
      await _prefs.setString(_kState, jsonEncode(state));
    }
  }

  Future<String> loadPlaylistChoice() async => await _prefs.getString(_kPlaylist) ?? '';

  Future<void> savePlaylistChoice(String id) => _prefs.setString(_kPlaylist, id);

  Future<String> loadCatalogSignature() async => await _prefs.getString(_kCatalogSig) ?? '';

  Future<void> saveCatalogSignature(String sig) => _prefs.setString(_kCatalogSig, sig);

  Future<Set<String>> loadSeenMessages() async => (await _prefs.getStringList(_kSeenMessages))?.toSet() ?? <String>{};

  Future<void> saveSeenMessages(Set<String> ids) => _prefs.setStringList(_kSeenMessages, ids.toList());

  Future<bool> loadPrivacyOk() async => await _prefs.getBool(_kPrivacyOk) ?? false;

  Future<void> savePrivacyOk() => _prefs.setBool(_kPrivacyOk, true);

  Future<int> loadKickSeen() async => await _prefs.getInt(_kKickSeen) ?? 0;

  Future<void> saveKickSeen(int value) => _prefs.setInt(_kKickSeen, value);

  // ---------------------------------------------------------------------------
  // Preferiti, progressi, impostazioni

  Future<Set<String>> loadFavorites() async {
    final list = await _prefs.getStringList(_kFavorites);
    return list == null ? <String>{} : list.toSet();
  }

  Future<void> saveFavorites(Set<String> keys) => _prefs.setStringList(_kFavorites, keys.toList());

  Future<Map<String, WatchProgress>> loadProgress() async {
    final raw = await _prefs.getString(_kProgress);
    final result = <String, WatchProgress>{};
    if (raw == null) return result;
    try {
      for (final entry in asList(jsonDecode(raw))) {
        final progress = WatchProgress.fromJson(entry);
        if (progress != null) result[progress.item.key] = progress;
      }
    } on FormatException {
      // dati rovinati: si riparte da zero
    }
    return result;
  }

  Future<void> saveProgress(Iterable<WatchProgress> entries) =>
      _prefs.setString(_kProgress, jsonEncode([for (final e in entries) e.toJson()]));

  Future<String> loadLiveFormat() async => await _prefs.getString(_kLiveFormat) ?? 'ts';

  Future<void> saveLiveFormat(String format) => _prefs.setString(_kLiveFormat, format);

  /// Guida XMLTV esterna messa dal cliente (vuoto = nessuna).
  Future<String> loadExternalEpg() async => await _prefs.getString('epg_external') ?? '';

  Future<void> saveExternalEpg(String url) => _prefs.setString('epg_external', url);

  /// Grafica leggera: auto | on | off
  Future<String> loadLiteMode() async => await _prefs.getString(_kLiteMode) ?? 'auto';

  /// Controllo remoto: impostazioni imposte dal pannello e versione applicata.
  Future<(String, String)> loadRemote() async => (await _prefs.getString(_kRc) ?? '', await _prefs.getString(_kRcv) ?? '');

  Future<void> saveRemote(String rc, String rcv) async {
    await _prefs.setString(_kRc, rc);
    await _prefs.setString(_kRcv, rcv);
  }

  Future<void> saveLiteMode(String mode) => _prefs.setString(_kLiteMode, mode);

  /// Aggiornamento in background: la versione nuova si scarica da sola (acceso di serie).
  Future<bool> loadBgUpdate() async => await _prefs.getBool(_kBgUpdate) ?? true;

  Future<void> saveBgUpdate(bool on) => _prefs.setBool(_kBgUpdate, on);

  /// Controllo genitori: attivo di serie; PIN vuoto = quello iniziale (0000); ultimo rinvio della scelta del PIN.
  Future<bool> loadParental() async => await _prefs.getBool(_kParental) ?? true;
  Future<void> saveParental(bool on) => _prefs.setBool(_kParental, on);
  Future<String> loadPin() async => await _prefs.getString(_kPin) ?? '';
  Future<void> savePin(String pin) => _prefs.setString(_kPin, pin);
  Future<int> loadPinLater() async => await _prefs.getInt(_kPinLater) ?? 0;
  Future<void> savePinLater(int t) => _prefs.setInt(_kPinLater, t);

  /// Ultima richiesta «Invia aggiornamento» del pannello già gestita.
  Future<int> loadUpdSeen() async => await _prefs.getInt(_kUpdSeen) ?? 0;

  Future<void> saveUpdSeen(int value) => _prefs.setInt(_kUpdSeen, value);

  /// Primo avviso al cliente di una versione: "codice:millisecondi" (da lì contano i giorni dell'aggiornamento obbligatorio).
  Future<String> loadUpdFirst() async => await _prefs.getString(_kUpdFirst) ?? '';

  Future<void> saveUpdFirst(String value) => _prefs.setString(_kUpdFirst, value);

  /// Versione nuova trovata dall'ultimo controllo in rete (JSON con codice, versione e indirizzo; vuoto = nessuna):
  /// si ripristina all'avvio, così un aggiornamento obbligatorio blocca l'app subito, anche senza rete.
  Future<String> loadUpdPending() async => await _prefs.getString(_kUpdPending) ?? '';

  Future<void> saveUpdPending(String value) =>
      value.isEmpty ? _prefs.remove(_kUpdPending) : _prefs.setString(_kUpdPending, value);

  /// Domini di riserva per gli aggiornamenti annunciati dal feed («mirrors», vedi feedMirrors), uno per riga.
  Future<List<String>> loadDlMirrors() async => [
        for (final s in (await _prefs.getString(_kDlMirrors) ?? '').split('\n'))
          if (s.trim().isNotEmpty) s.trim(),
      ];

  Future<void> saveDlMirrors(List<String> value) =>
      value.isEmpty ? _prefs.remove(_kDlMirrors) : _prefs.setString(_kDlMirrors, value.join('\n'));

  /// Anteprima dei canali: click (1° OK riquadro, 2° OK schermo intero) | off
  Future<String> loadPreviewMode() async => await _prefs.getString(_kPreviewMode) ?? 'click';

  Future<void> savePreviewMode(String mode) => _prefs.setString(_kPreviewMode, mode);

  /// Cambio di abbonamento o di playlist: preferiti e progressi non valgono più.
  Future<void> clearUserData() async {
    await _prefs.remove(_kFavorites);
    await _prefs.remove(_kProgress);
  }
}
