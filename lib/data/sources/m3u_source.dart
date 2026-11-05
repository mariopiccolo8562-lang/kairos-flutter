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
    final text = await fetchText(uri, timeout: const Duration(seconds: 60));
    final catalog = parseM3uCatalog(text);
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
  final live = <MediaItem>[];
  final movies = <MediaItem>[];
  final liveCategories = <String, Category>{};
  final movieCategories = <String, Category>{};

  String? name;
  String? logo;
  String? group;
  String? epgId;

  for (final raw in const LineSplitter().convert(text)) {
    final line = raw.trim();
    if (line.isEmpty) continue;

    if (line.startsWith('#EXTINF')) {
      final attrs = <String, String>{
        for (final m in _attributePattern.allMatches(line)) m.group(1)!.toLowerCase(): m.group(2)!.trim(),
      };
      name = _nameAfterComma(line) ?? _nonEmpty(attrs['tvg-name']);
      logo = _nonEmpty(attrs['tvg-logo']);
      group = _nonEmpty(attrs['group-title']);
      epgId = _nonEmpty(attrs['tvg-id']);
    } else if (line.startsWith('#EXTGRP:')) {
      group = _nonEmpty(line.substring(8));
    } else if (line.startsWith('#')) {
      continue;
    } else {
      final title = name ?? 'Senza nome';
      final groupName = group ?? 'Altri';
      final categoryId = 'g:$groupName';
      final isVod = _isVod(line);
      final item = MediaItem(
        kind: isVod ? MediaKind.movie : MediaKind.live,
        id: _hash(line),
        name: title,
        categoryId: categoryId,
        image: logo,
        epgId: epgId,
        url: line,
        year: isVod ? yearFromTitle(title) : null,
        number: isVod ? null : live.length + 1,
      );
      if (isVod) {
        movies.add(item);
        movieCategories.putIfAbsent(categoryId, () => Category(id: categoryId, name: groupName));
      } else {
        live.add(item);
        liveCategories.putIfAbsent(categoryId, () => Category(id: categoryId, name: groupName));
      }
      name = null;
      logo = null;
      group = null;
      epgId = null;
    }
  }

  return Catalog.build(
    liveCategories: liveCategories.values.toList(),
    movieCategories: movieCategories.values.toList(),
    seriesCategories: const <Category>[],
    live: live,
    movies: movies,
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
