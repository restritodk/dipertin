import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

/// Evita `Unsupported operation: Int64 accessor not supported by dart2js` ao
/// usar dados do [HttpsCallable] ou [DocumentSnapshot.data] no Flutter Web.
Map<String, dynamic> sanitizeMapForWeb(Map<String, dynamic> input) {
  if (!kIsWeb) return input;
  return _mapFromEntriesSafe(input);
}

/// Lê [DocumentSnapshot.data] de forma segura no Flutter Web (dart2js).
/// Se [data()] lançar Int64 durante a conversão JS→Dart, retorna mapa vazio.
Map<String, dynamic> safeWebDocData(
  DocumentSnapshot<Map<String, dynamic>> snap,
) {
  if (!snap.exists) return {};
  try {
    final raw = snap.data();
    if (raw == null) return {};
    if (!kIsWeb) return raw;
    return _mapFromEntriesSafe(raw);
  } catch (_) {
    return {};
  }
}

Map<String, dynamic> _mapFromEntriesSafe(Map input) {
  final out = <String, dynamic>{};
  for (final k in input.keys) {
    final key = k.toString();
    dynamic v;
    try {
      v = input[k];
    } catch (_) {
      continue;
    }
    try {
      out[key] = _sanitizeValue(v);
    } catch (_) {
      try {
        out[key] = int.parse(v.toString());
      } catch (_) {
        out[key] = v.toString();
      }
    }
  }
  return out;
}

dynamic _sanitizeValue(dynamic v) {
  if (v == null) return null;
  if (v is bool || v is String) return v;
  if (v is Timestamp) return v;
  if (v is GeoPoint) return v;
  if (v is Map) {
    return _mapFromEntriesSafe(v);
  }
  if (v is List) {
    final out = <dynamic>[];
    for (var i = 0; i < v.length; i++) {
      try {
        out.add(_sanitizeValue(v[i]));
      } catch (_) {
        try {
          out.add(int.parse(v[i].toString()));
        } catch (_) {
          out.add(v[i].toString());
        }
      }
    }
    return out;
  }
  final t = v.runtimeType.toString();
  if (t.contains('Int64')) {
    return int.parse(v.toString());
  }
  if (v is int || v is double) return v;
  return v;
}

/// Resposta do callable pode trazer números como Int64 no web — não use [Map.from]
/// no mapa bruto antes de sanitizar.
Map<String, dynamic> sanitizeCallableMapForWeb(dynamic raw) {
  if (raw is! Map) return {};
  if (!kIsWeb) {
    return Map<String, dynamic>.from(raw);
  }
  return _mapFromEntriesSafe(raw);
}
