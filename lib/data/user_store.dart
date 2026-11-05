import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../core/json.dart';
import 'models.dart';

/// Account, preferiti, progressi e impostazioni salvati sul dispositivo.
class UserStore {
  final SharedPreferencesAsync _prefs = SharedPreferencesAsync();

  static const String _kAccount = 'account';
  static const String _kFavorites = 'favorites';
  static const String _kProgress = 'progress';
  static const String _kLiveFormat = 'live_format';

  Future<Account?> loadAccount() async {
    final raw = await _prefs.getString(_kAccount);
    if (raw == null) return null;
    try {
      return Account.fromJson(jsonDecode(raw));
    } on FormatException {
      return null;
    }
  }

  Future<void> saveAccount(Account? account) async {
    if (account == null) {
      await _prefs.remove(_kAccount);
    } else {
      await _prefs.setString(_kAccount, jsonEncode(account.toJson()));
    }
  }

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

  Future<void> clearUserData() async {
    await _prefs.remove(_kFavorites);
    await _prefs.remove(_kProgress);
  }
}
