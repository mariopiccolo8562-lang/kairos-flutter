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
  static const String _kPreviewMode = 'preview_mode';

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

  /// Grafica leggera: auto | on | off
  Future<String> loadLiteMode() async => await _prefs.getString(_kLiteMode) ?? 'auto';

  Future<void> saveLiteMode(String mode) => _prefs.setString(_kLiteMode, mode);

  /// Anteprima dei canali: click (1° OK riquadro, 2° OK schermo intero) | off
  Future<String> loadPreviewMode() async => await _prefs.getString(_kPreviewMode) ?? 'click';

  Future<void> savePreviewMode(String mode) => _prefs.setString(_kPreviewMode, mode);

  /// Cambio di abbonamento o di playlist: preferiti e progressi non valgono più.
  Future<void> clearUserData() async {
    await _prefs.remove(_kFavorites);
    await _prefs.remove(_kProgress);
  }
}
