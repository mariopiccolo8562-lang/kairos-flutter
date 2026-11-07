import 'dart:async';
import 'dart:io' as io;
import 'dart:isolate';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:path_provider/path_provider.dart';

import '../../app/brand.dart';
import '../../app/perf.dart';

/// Cache su disco delle immagini (loghi, locandine, sfondi): 2000 voci invece delle 200 di serie
/// (un catalogo IPTV ne ha migliaia), validità 7 giorni, al massimo 4 scaricamenti insieme
/// (le chiavette e i server IPTV non reggono 10 connessioni in parallelo mentre si scorre).
/// I file stanno nella cartella cache dell'app (Android la svuota da sola se manca spazio), con un tetto
/// in byte per classe di dispositivo ([trimDisk]).
abstract final class NetImageCache {
  static const String _key = 'kairosImages';

  static final CacheManager manager = CacheManager(
    Config(
      _key,
      stalePeriod: const Duration(days: 7),
      maxNrOfCacheObjects: 2000,
      fileService: HttpFileService()..concurrentFetches = 4,
    ),
  );

  /// Svuota questa cache e quella di serie (file di versioni precedenti dell'app).
  static Future<void> clear() async {
    for (final m in [manager, DefaultCacheManager()]) {
      try {
        await m.emptyCache();
      } on Object {
        // cache già vuota o non apribile
      }
    }
  }

  /// Tetto della cache su disco: 150 MB sui dispositivi deboli (classe D), 250 MB sugli altri.
  /// La libreria conta solo i file: oltre il tetto si tolgono quelli scaricati per primi, in un isolate
  /// (l'interfaccia non aspetta). Un file tolto si riscarica solo se torna a servire.
  static Future<void> trimDisk({required bool weak}) async {
    try {
      final dir = '${(await getTemporaryDirectory()).path}${io.Platform.pathSeparator}$_key';
      final maxBytes = (weak ? 150 : 250) << 20;
      await Isolate.run(() => _trimDir(dir, maxBytes));
    } on Object {
      // la cache è solo un'accelerazione
    }
  }
}

/// Toglie i file più vecchi della cartella finché non si scende sotto i 7/8 del tetto
/// (così la pulizia non riparte a ogni avvio).
void _trimDir(String path, int maxBytes) {
  final dir = io.Directory(path);
  if (!dir.existsSync()) return;
  final files = <(int, int, io.File)>[];
  var total = 0;
  for (final entry in dir.listSync(recursive: true, followLinks: false)) {
    if (entry is! io.File) continue;
    try {
      final stat = entry.statSync();
      total += stat.size;
      files.add((stat.modified.millisecondsSinceEpoch, stat.size, entry));
    } on io.FileSystemException {
      // file sparito nel frattempo
    }
  }
  if (total <= maxBytes) return;
  files.sort((a, b) => a.$1.compareTo(b.$1));
  final target = maxBytes - (maxBytes >> 3);
  for (final (_, size, file) in files) {
    if (total <= target) break;
    try {
      file.deleteSync();
      total -= size;
    } on io.FileSystemException {
      // in uso o già tolto
    }
  }
}

/// Larghezza in pixel a cui decodificare un'immagine mostrata larga [width] punti: mai oltre la larghezza
/// dello schermo e, sui dispositivi deboli, mai oltre 1280 px (sfondi e schede a tutto schermo).
int decodePixels(BuildContext context, double width) {
  final ratio = MediaQuery.devicePixelRatioOf(context);
  var px = (width * ratio).round();
  final screen = (MediaQuery.sizeOf(context).width * ratio).round();
  if (screen > 0 && px > screen) px = screen;
  if (Perf.weak && px > 1280) px = 1280;
  return px;
}

/// Misura TMDB adatta a [px] pixel: locandine w342 (w185 sui dispositivi deboli), sfondi w780.
int tmdbWidthFor(int px) {
  if (px <= 185) return 185;
  if (px <= 342) return Perf.weak ? 185 : 342;
  return 780;
}

final RegExp _tmdbPath = RegExp(r'^(https?://image\.tmdb\.org/t/p/)([^/]+)/');
final RegExp _tmdbSize = RegExp(r'^w(\d{1,5})(?:_and_h(\d{1,5})_bestv2)?$');

/// Locandine e sfondi di TMDB (image.tmdb.org/t/p/MISURA/FILE): si chiede la misura [width] invece di una
/// più grande (original, w500, w1280, w600_and_h900_bestv2…), quindi meno download e meno decodifica.
/// I tagli «bestv2» si cambiano solo se sono 2:3 (locandine: stessa inquadratura); le misure più piccole
/// o sconosciute restano come sono.
String tmdbSized(String url, int width) {
  final m = _tmdbPath.firstMatch(url);
  if (m == null) return url;
  final size = m.group(2)!;
  int? current;
  if (size == 'original') {
    current = 1 << 20;
  } else {
    final s = _tmdbSize.firstMatch(size);
    if (s != null) {
      final w = int.tryParse(s.group(1)!);
      final cut = s.group(2);
      final h = cut == null ? null : int.tryParse(cut);
      if (w != null && (cut == null || (h != null && h * 2 == w * 3))) current = w;
    }
  }
  if (current == null || current <= width) return url;
  return '${m.group(1)}w$width/${url.substring(m.end)}';
}

/// Caricamento delle immagini col telecomando: tenendo premuta una freccia (scorrimento veloce) le immagini
/// nuove aspettano che ci si fermi, invece di accodare decine di download che non servono più (la libreria
/// non sa annullarli); quelle già chieste in questa apertura (in memoria o su disco) si mostrano subito.
abstract final class ImageLoads {
  /// In pausa: si sta tenendo premuta una freccia.
  static final ValueNotifier<bool> paused = ValueNotifier<bool>(false);

  static final Set<String> _known = <String>{};
  static final Set<String> _failed = <String>{};
  static Timer? _resume;
  static bool _listening = false;

  static void _listen() {
    if (_listening) return;
    _listening = true;
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  /// Solo osservazione: il tasto prosegue come sempre (false = non gestito qui).
  static bool _onKey(KeyEvent event) {
    final key = event.logicalKey;
    if (key != LogicalKeyboardKey.arrowUp &&
        key != LogicalKeyboardKey.arrowDown &&
        key != LogicalKeyboardKey.arrowLeft &&
        key != LogicalKeyboardKey.arrowRight) {
      return false;
    }
    if (event is KeyRepeatEvent) {
      if (!paused.value) paused.value = true;
      _resume?.cancel();
      _resume = Timer(const Duration(milliseconds: 300), _go); // anche se il rilascio non arriva
    } else if (event is KeyUpEvent && paused.value) {
      _resume?.cancel();
      _resume = Timer(const Duration(milliseconds: 120), _go);
    }
    return false;
  }

  static void _go() {
    _resume = null;
    paused.value = false;
  }

  static bool _isKnown(String url) => _known.contains(url);

  static void _remember(String url) {
    if (_known.length > 4000) _known.clear();
    _known.add(url);
  }
}

/// Immagine da internet con cache su disco e decodifica già alla misura
/// mostrata (molta meno RAM). Se manca o non si carica, mostra una
/// copertina generata con il titolo.
class NetImage extends StatefulWidget {
  const NetImage({
    super.key,
    required this.url,
    required this.title,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
    this.decodeWidth,
    this.showTitleOnFallback = true,
    this.transparentPlaceholder = false,
    this.fallback = true,
  });

  final String? url;
  final String title;
  final BoxFit fit;
  final Alignment alignment;

  /// Larghezza (in punti) a cui viene mostrata: l'immagine si decodifica a quella misura.
  final double? decodeWidth;
  final bool showTitleOnFallback;

  /// Nessun riquadro colorato mentre l'immagine arriva (sfondi grandi).
  final bool transparentPlaceholder;

  /// Copertina generata se l'immagine non c'è.
  final bool fallback;

  @override
  State<NetImage> createState() => _NetImageState();
}

class _NetImageState extends State<NetImage> {
  /// Alla prima costruzione era in corso uno scorrimento veloce: si carica quando finisce.
  bool? _waiting;

  @override
  void initState() {
    super.initState();
    ImageLoads._listen();
  }

  @override
  void dispose() {
    ImageLoads.paused.removeListener(_onPausedChanged);
    super.dispose();
  }

  void _onPausedChanged() {
    if (ImageLoads.paused.value) return;
    ImageLoads.paused.removeListener(_onPausedChanged);
    if (mounted && _waiting == true) setState(() => _waiting = false);
  }

  Widget _placeholder() =>
      widget.transparentPlaceholder ? const SizedBox.expand() : const ColoredBox(color: Brand.card);

  Widget _fallback() =>
      widget.fallback ? FallbackArt(title: widget.title, showTitle: widget.showTitleOnFallback) : const SizedBox.shrink();

  /// [original]: indirizzo di partenza se [url] è la misura ridotta di TMDB (se questa non si carica).
  Widget _image(String url, int? cacheWidth, String? original) {
    return CachedNetworkImage(
      imageUrl: url,
      cacheManager: NetImageCache.manager,
      fit: widget.fit,
      alignment: widget.alignment,
      memCacheWidth: cacheWidth,
      filterQuality: FilterQuality.low,
      fadeInDuration: Perf.lite ? Duration.zero : const Duration(milliseconds: 160),
      fadeOutDuration: Duration.zero,
      placeholder: (context, _) => _placeholder(),
      errorWidget: (context, failed, error) {
        if (original == null) return _fallback();
        ImageLoads._failed.add(failed); // la prossima volta direttamente l'indirizzo di partenza
        ImageLoads._remember(original);
        return _image(original, cacheWidth, null);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final u = widget.url;
    if (u == null || u.isEmpty || !(u.startsWith('http://') || u.startsWith('https://'))) {
      return _fallback();
    }
    final width = widget.decodeWidth;
    final cacheWidth = width == null ? null : decodePixels(context, width);
    var src = cacheWidth == null ? u : tmdbSized(u, tmdbWidthFor(cacheWidth));
    if (src != u && ImageLoads._failed.contains(src)) src = u;
    var waiting = _waiting;
    if (waiting == null) {
      waiting = ImageLoads.paused.value && !ImageLoads._isKnown(src);
      _waiting = waiting;
      if (waiting) ImageLoads.paused.addListener(_onPausedChanged);
    }
    if (waiting) return _placeholder();
    ImageLoads._remember(src);
    return _image(src, cacheWidth, src == u ? null : u);
  }
}

/// Copertina generata: colore ricavato dal titolo, sempre uguale per lo stesso titolo.
class FallbackArt extends StatelessWidget {
  const FallbackArt({super.key, required this.title, this.showTitle = true});

  final String title;
  final bool showTitle;

  @override
  Widget build(BuildContext context) {
    var hash = 0;
    for (final unit in title.codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    final hue = (hash % 360).toDouble();
    final top = HSLColor.fromAHSL(1, hue, 0.45, 0.30).toColor();
    final bottom = HSLColor.fromAHSL(1, (hue + 35) % 360, 0.50, 0.14).toColor();
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [top, bottom],
        ),
      ),
      child: showTitle
          ? Padding(
              padding: const EdgeInsets.all(10),
              child: Align(
                alignment: Alignment.bottomLeft,
                child: Text(
                  title,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    height: 1.15,
                    color: Colors.white,
                  ),
                ),
              ),
            )
          : const SizedBox.expand(),
    );
  }
}
