import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:path_provider/path_provider.dart';

import 'models.dart';
import 'sources/content_source.dart';

/// Scarica il catalogo e lo tiene in cache su disco.
///
/// Download, lettura del JSON e raggruppamento avvengono in un isolate
/// separato: anche con decine di migliaia di titoli l'interfaccia non scatta.
abstract final class CatalogRepository {
  static Future<String> _cachePath() async {
    final dir = await getApplicationSupportDirectory();
    return '${dir.path}${Platform.pathSeparator}catalog_v1.json';
  }

  static Future<Catalog> fetch(Account account) async {
    final path = await _cachePath();
    return Isolate.run(() => _fetchAndStore(account, path));
  }

  static Future<Catalog?> readCache() async {
    final path = await _cachePath();
    return Isolate.run(() => _readCache(path));
  }

  static Future<void> clearCache() async {
    final file = File(await _cachePath());
    if (await file.exists()) await file.delete();
  }
}

Future<Catalog> _fetchAndStore(Account account, String path) async {
  final catalog = await ContentSource.of(account).fetchCatalog();
  try {
    File(path).writeAsStringSync(jsonEncode(catalog.toJson()), flush: true);
  } on FileSystemException {
    // La cache è solo un'accelerazione: se non si riesce a scriverla, pazienza.
  }
  return catalog;
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
