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

  /// [homeTop], [homeHide] e [hideAdult]: Home decisa dal pannello (rc «home.top», «home.hide» e «adult»), per la
  /// copia della Home, che nell'isolate segue le stesse regole della Home. [favorites] e [seriesNames]: vedi
  /// [Catalog.homeSnapshot].
  static Future<Catalog> fetch(
    Account account, {
    Iterable<String> favorites = const <String>[],
    String homeTop = '',
    String homeHide = '',
    bool hideAdult = false,
    Set<String> seriesNames = const <String>{},
  }) async {
    final path = await _cachePath();
    final homePath = await _homePath();
    final agent = net.userAgent;
    final keys = favorites.toList();
    final names = Set<String>.of(seriesNames);
    final hs = hideSepNames;
    return Isolate.run(() {
      hideSepNames = hs; // l'isolato non vede le variabili dell'app
      return _fetchAndStore(account, path, homePath, agent, keys, homeTop, homeHide, hideAdult, names);
    });
  }

  static Future<Catalog?> readCache() async {
    final path = await _cachePath();
    return Isolate.run(() => readCatalogFile(path));
  }

  /// La copia piccola per la Home (null se non c'è ancora).
  static Future<Catalog?> readHome() async {
    final path = await _homePath();
    return Isolate.run(() => readCatalogFile(path));
  }

  /// Aggiorna la copia per la Home (es. con i preferiti di adesso e la Home decisa dal pannello).
  static Future<void> writeHome(
    Catalog catalog,
    Iterable<String> favorites, {
    HomeRules? rules,
    Set<String> seriesNames = const <String>{},
  }) async {
    final path = await _homePath();
    final json = catalog.homeSnapshot(favorites, rules: rules, seriesNames: seriesNames).toCacheJson();
    await Isolate.run(() => writeCatalogFile(path, json));
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
  bool hideAdult,
  Set<String> seriesNames,
) async {
  // ogni isolate ha le sue variabili: il nome con cui l'app si presenta va ripassato
  net.userAgent = agent;
  try {
    final catalog = await ContentSource.of(account).fetchCatalog();
    writeCatalogFile(path, catalog.toCacheJson());
    final rules = HomeRules.parse(homeTop, homeHide, hideAdult: hideAdult);
    writeCatalogFile(homePath, catalog.homeSnapshot(favorites, rules: rules, seriesNames: seriesNames).toCacheJson());
    return catalog;
  } finally {
    net.closeClient(); // le connessioni dell'isolate non servono più
  }
}

/// Scrive la cache ([Catalog.toCacheJson]) in UTF-8 direttamente su file, a pezzi da 64 KB: niente testo
/// intero né mappe di tutte le voci in memoria (ogni voce si converte quando tocca a lei). Prima in un file
/// accanto e poi al suo posto: un'app chiusa a metà scrittura non lascia una cache rovinata.
void writeCatalogFile(String path, Map<String, Object?> json) {
  final part = File('$path.part');
  try {
    final out = part.openSync(mode: FileMode.write);
    try {
      JsonUtf8Encoder(null, _encodeItem, 1 << 16).startChunkedConversion(_FileBytes(out)).add(json);
      out.flushSync();
    } finally {
      out.closeSync();
    }
    part.renameSync(path);
  } on FileSystemException {
    // La cache è solo un'accelerazione: se non si riesce a scriverla, pazienza.
  }
}

Object? _encodeItem(dynamic value) => value is MediaItem ? value.toJson() : value;

/// I pezzi di JSON già in byte vanno subito sul file.
class _FileBytes implements Sink<List<int>> {
  _FileBytes(this._file);

  final RandomAccessFile _file;

  @override
  void add(List<int> data) => _file.writeFromSync(data);

  @override
  void close() {}
}

/// Legge la cache dai byte (niente testo intermedio); le voci diventano [MediaItem] mentre si legge.
Catalog? readCatalogFile(String path) {
  final file = File(path);
  if (!file.existsSync()) return null;
  try {
    return Catalog.fromJson(const Utf8Decoder().fuse(const JsonDecoder(_cacheItem)).convert(file.readAsBytesSync()));
  } on Object {
    return null; // cache rovinata o di una versione vecchia: si riscarica
  }
}

/// Le voci della cache sono gli oggetti con «k» (il tipo) dentro un elenco; categorie e il resto restano mappe.
Object? _cacheItem(Object? key, Object? value) =>
    key is int && value is Map<String, dynamic> && value.containsKey('k') ? MediaItem.fromJson(value) : value;
