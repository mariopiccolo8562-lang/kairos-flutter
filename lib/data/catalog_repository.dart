import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:path_provider/path_provider.dart';

import '../core/net.dart' as net;
import 'home_rules.dart';
import 'models.dart';
import 'sources/content_source.dart';

/// Scarica il catalogo e lo tiene in cache su disco.
///
/// Download, lettura del JSON e raggruppamento avvengono in un isolate
/// separato: anche con decine di migliaia di titoli l'interfaccia non scatta.
///
/// Accanto al catalogo completo c'è una piccola copia con solo quello che
/// serve alla Home: all'avvio si legge in un attimo e l'app si apre subito,
/// mentre il catalogo completo arriva subito dopo.
abstract final class CatalogRepository {
  static Future<String> _dir() async => (await getApplicationSupportDirectory()).path;

  static Future<String> _cachePath() async => '${await _dir()}${Platform.pathSeparator}catalog_v2.json';

  static Future<String> _homePath() async => '${await _dir()}${Platform.pathSeparator}catalog_home_v1.json';

  /// [homeTop] e [homeHide]: Home decisa dal pannello (rc «home.top» e «home.hide»), per la copia della Home.
  static Future<Catalog> fetch(
    Account account, {
    Iterable<String> favorites = const <String>[],
    String homeTop = '',
    String homeHide = '',
  }) async {
    final path = await _cachePath();
    final homePath = await _homePath();
    final agent = net.userAgent;
    final keys = favorites.toList();
    return Isolate.run(() => _fetchAndStore(account, path, homePath, agent, keys, homeTop, homeHide));
  }

  static Future<Catalog?> readCache() async {
    final path = await _cachePath();
    return Isolate.run(() => _readCache(path));
  }

  /// La copia piccola per la Home (null se non c'è ancora).
  static Future<Catalog?> readHome() async {
    final path = await _homePath();
    return Isolate.run(() => _readCache(path));
  }

  /// Aggiorna la copia per la Home (es. con i preferiti di adesso e la Home decisa dal pannello).
  static Future<void> writeHome(Catalog catalog, Iterable<String> favorites, {HomeRules? rules}) async {
    final path = await _homePath();
    final json = catalog.homeSnapshot(favorites, rules: rules).toJson();
    await Isolate.run(() => _write(path, json));
  }

  static Future<void> clearCache() async {
    for (final path in [await _cachePath(), await _homePath()]) {
      final file = File(path);
      if (await file.exists()) await file.delete();
    }
  }
}

Future<Catalog> _fetchAndStore(
  Account account,
  String path,
  String homePath,
  String agent,
  List<String> favorites,
  String homeTop,
  String homeHide,
) async {
  // ogni isolate ha le sue variabili: il nome con cui l'app si presenta va ripassato
  net.userAgent = agent;
  try {
    final catalog = await ContentSource.of(account).fetchCatalog();
    _write(path, catalog.toJson());
    _write(homePath, catalog.homeSnapshot(favorites, rules: HomeRules.parse(homeTop, homeHide)).toJson());
    return catalog;
  } finally {
    net.closeClient(); // le connessioni dell'isolate non servono più
  }
}

void _write(String path, Map<String, Object?> json) {
  try {
    File(path).writeAsStringSync(jsonEncode(json), flush: true);
  } on FileSystemException {
    // La cache è solo un'accelerazione: se non si riesce a scriverla, pazienza.
  }
}

Catalog? _readCache(String path) {
  final file = File(path);
  if (!file.existsSync()) return null;
  try {
    return Catalog.fromJson(jsonDecode(file.readAsStringSync()));
  } on Object {
    return null; // cache rovinata o di una versione vecchia: si riscarica
  }
}
