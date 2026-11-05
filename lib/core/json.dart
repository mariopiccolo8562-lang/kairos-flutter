import 'dart:convert';

/// Lettura "tollerante" del JSON dei server IPTV: lo stesso campo può
/// arrivare come numero, stringa, lista o null a seconda del pannello.

String? asString(Object? value) {
  if (value == null) return null;
  final s = value.toString().trim();
  return s.isEmpty || s == 'null' ? null : s;
}

int? asInt(Object? value) {
  if (value is int) return value;
  if (value is double) return value.toInt();
  if (value is String) {
    final t = value.trim();
    return int.tryParse(t) ?? double.tryParse(t)?.toInt();
  }
  return null;
}

double? asDouble(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value.trim().replaceAll(',', '.'));
  return null;
}

Map<String, dynamic> asMap(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return value.map((key, v) => MapEntry(key.toString(), v));
  }
  return <String, dynamic>{};
}

List<dynamic> asList(Object? value) => value is List ? value : const <dynamic>[];

/// Primo valore utile di un campo che può essere stringa o lista di stringhe.
String? firstString(Object? value) {
  if (value is List) {
    for (final v in value) {
      final s = asString(v);
      if (s != null) return s;
    }
    return null;
  }
  return asString(value);
}

/// I testi della guida TV Xtream arrivano codificati in base64.
String decodeBase64Text(String? value) {
  if (value == null || value.isEmpty) return '';
  try {
    var t = value.trim();
    final missing = t.length % 4;
    if (missing != 0) t = t.padRight(t.length + (4 - missing), '=');
    return utf8.decode(base64.decode(t), allowMalformed: true).trim();
  } on FormatException {
    return value;
  }
}
