import 'dart:convert';

import '../../core/net.dart';
import '../models.dart';
import 'content_source.dart';

/// Lista M3U / M3U Plus da un indirizzo web.
class M3uSource extends ContentSource {
  const M3uSource(this.url);

  final String url;

  @override
  Future<Catalog> fetchCatalog() async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw const SourceException('Link M3U non valido');
    }
    // riga per riga mentre arriva: il testo intero della lista (decine di MB) non sta mai in memoria
    final parser = M3uParser();
    await fetchLines(uri, parser.add, timeout: const Duration(seconds: 60));
    final catalog = parser.build();
    if (catalog.isEmpty) throw const SourceException('La lista M3U non contiene contenuti');
    return catalog;
  }

  @override
  String urlFor(MediaItem item, {String liveFormat = 'ts'}) => item.url ?? '';
}

final RegExp _attributePattern = RegExp(r'([\w-]+)="([^"]*)"');

/// Legge una lista M3U. I contenuti on demand (indirizzi con /movie/ o
/// /series/, oppure file .mp4/.mkv) finiscono nei Film, il resto nei canali.
Catalog parseM3uCatalog(String text) {
  final parser = M3uParser();
  for (final raw in const LineSplitter().convert(text)) {
    parser.add(raw);
  }
  return parser.build();
}

/// Lettura di una lista M3U una riga alla volta (anche mentre arriva dalla rete), con le regole di
/// [parseM3uCatalog].
class M3uParser {
  final List<MediaItem> _live = <MediaItem>[];
  final List<MediaItem> _movies = <MediaItem>[];
  final Map<String, Category> _liveCategories = <String, Category>{};
  final Map<String, Category> _movieCategories = <String, Category>{};

  String? _name;
  String? _logo;
  String? _group;
  String? _epgId;

  void add(String raw) {
    final line = raw.trim();
    if (line.isEmpty) return;

    if (line.startsWith('#EXTINF')) {
      final attrs = <String, String>{
        for (final m in _attributePattern.allMatches(line)) m.group(1)!.toLowerCase(): m.group(2)!.trim(),
      };
      _name = _nameAfterComma(line) ?? _nonEmpty(attrs['tvg-name']);
      _logo = _nonEmpty(attrs['tvg-logo']);
      _group = _nonEmpty(attrs['group-title']);
      _epgId = _nonEmpty(attrs['tvg-id']);
    } else if (line.startsWith('#EXTGRP:')) {
      _group = _nonEmpty(line.substring(8));
    } else if (line.startsWith('#')) {
      return;
    } else {
      final title = _name ?? 'Senza nome';
      final groupName = _group ?? 'Altri';
      final categoryId = 'g:$groupName';
      final isVod = _isVod(line);
      final item = MediaItem(
        kind: isVod ? MediaKind.movie : MediaKind.live,
        id: _hash(line),
        name: title,
        categoryId: categoryId,
        image: _logo,
        epgId: _epgId,
        url: line,
        year: isVod ? yearFromTitle(title) : null,
        number: isVod ? null : _live.length + 1,
      );
      if (isVod) {
        _movies.add(item);
        _movieCategories.putIfAbsent(categoryId, () => Category(id: categoryId, name: groupName));
      } else {
        _live.add(item);
        _liveCategories.putIfAbsent(categoryId, () => Category(id: categoryId, name: groupName));
      }
      _name = null;
      _logo = null;
      _group = null;
      _epgId = null;
    }
  }

  Catalog build() => Catalog.build(
        liveCategories: _liveCategories.values.toList(),
        movieCategories: _movieCategories.values.toList(),
        seriesCategories: const <Category>[],
        live: _live,
        movies: _movies,
        series: const <MediaItem>[],
        fetchedAt: DateTime.now().millisecondsSinceEpoch,
      );
}

bool _isVod(String url) {
  if (url.contains('/movie/') || url.contains('/series/')) return true;
  final path = (Uri.tryParse(url)?.path ?? url).toLowerCase();
  return path.endsWith('.mp4') || path.endsWith('.mkv') || path.endsWith('.avi') || path.endsWith('.mov');
}

String? _nonEmpty(String? value) {
  final v = value?.trim();
  return v == null || v.isEmpty ? null : v;
}

/// Il nome è dopo la prima virgola fuori dalle virgolette.
String? _nameAfterComma(String line) {
  var inQuotes = false;
  for (var i = 0; i < line.length; i++) {
    final c = line[i];
    if (c == '"') {
      inQuotes = !inQuotes;
    } else if (c == ',' && !inQuotes) {
      return _nonEmpty(line.substring(i + 1));
    }
  }
  return null;
}

/// Identificativo stabile (FNV-1a) ricavato dall'indirizzo: preferiti e
/// progressi restano validi anche se la lista cambia ordine.
String _hash(String value) {
  var h = 0x811c9dc5;
  for (final c in value.codeUnits) {
    h ^= c;
    h = (h * 0x01000193) & 0xFFFFFFFF;
  }
  return h.toRadixString(16);
}
