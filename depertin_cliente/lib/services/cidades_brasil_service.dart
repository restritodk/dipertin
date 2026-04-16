import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Uma linha da lista IBGE (nome do município + UF).
class CidadeSugestao {
  final String nome;
  final String ufSigla;
  final String ufNome;

  const CidadeSugestao({
    required this.nome,
    required this.ufSigla,
    required this.ufNome,
  });

  String get labelLinha => '$nome — $ufNome';
}

Map<String, dynamic>? _ufDoJson(Map<String, dynamic> m) {
  dynamic u = m['microrregiao']?['mesorregiao']?['UF'];
  u ??= m['regiao-imediata']?['regiao-intermediaria']?['UF'];
  if (u is Map) {
    return Map<String, dynamic>.from(u);
  }
  return null;
}

List<CidadeSugestao> _parseMunicipiosJson(String body) {
  final decoded = jsonDecode(body);
  if (decoded is! List) return [];
  final out = <CidadeSugestao>[];
  for (final item in decoded) {
    if (item is! Map) continue;
    final m = Map<String, dynamic>.from(item);
    final nome = m['nome']?.toString().trim();
    if (nome == null || nome.isEmpty) continue;
    final ufMap = _ufDoJson(m);
    if (ufMap == null) continue;
    final sigla = ufMap['sigla']?.toString().trim() ?? '';
    final ufNome = ufMap['nome']?.toString().trim() ?? '';
    if (sigla.isEmpty) continue;
    out.add(
      CidadeSugestao(nome: nome, ufSigla: sigla.toUpperCase(), ufNome: ufNome),
    );
  }
  return out;
}

String _semAcentos(String s) {
  var t = s.toLowerCase();
  const from = 'àáâãäåèéêëìíîïòóôõöùúûüçñ';
  const to = 'aaaaaaeeeeiiiiooooouuuucn';
  for (var i = 0; i < from.length; i++) {
    t = t.replaceAll(from[i], to[i]);
  }
  return t;
}

/// Carrega a lista de municípios do IBGE uma vez e filtra por texto (≥3 letras).
class CidadesBrasilService {
  static List<CidadeSugestao>? _cache;
  static Future<void>? _carregando;

  static const _url =
      'https://servicodados.ibge.gov.br/api/v1/localidades/municipios';
  static const _minLetras = 3;
  static const _maxResultados = 20;

  static Future<void> precarregar() async {
    await _garantirCache();
  }

  static Future<List<CidadeSugestao>> _garantirCache() async {
    if (_cache != null) return _cache!;
    _carregando ??= _baixarEProcessar();
    await _carregando;
    _carregando = null;
    return _cache ?? [];
  }

  static Future<void> _baixarEProcessar() async {
    try {
      final resp = await http
          .get(Uri.parse(_url))
          .timeout(const Duration(seconds: 45));
      if (resp.statusCode != 200) {
        debugPrint('[CidadesBrasil] HTTP ${resp.statusCode}');
        _cache = [];
        return;
      }
      final lista = await compute(_parseMunicipiosJson, resp.body);
      lista.sort((a, b) => a.nome.compareTo(b.nome));
      _cache = lista;
    } catch (e, st) {
      debugPrint('[CidadesBrasil] Erro: $e\n$st');
      _cache = [];
    }
  }

  /// Retorna sugestões ordenadas (prefixo antes de “contém”).
  static Future<Iterable<CidadeSugestao>> buscar(String texto) async {
    final q = texto.trim();
    if (q.length < _minLetras) return const [];

    await _garantirCache();
    final todas = _cache;
    if (todas == null || todas.isEmpty) return const [];

    final qq = _semAcentos(q);
    final matches = <CidadeSugestao>[];
    for (final c in todas) {
      final n = _semAcentos(c.nome);
      if (n.startsWith(qq) || n.contains(qq)) {
        matches.add(c);
      }
    }

    int prioridade(CidadeSugestao c) {
      final n = _semAcentos(c.nome);
      if (n.startsWith(qq)) return 0;
      if (n.contains(qq)) return 1;
      return 2;
    }

    matches.sort((a, b) {
      final pa = prioridade(a);
      final pb = prioridade(b);
      if (pa != pb) return pa.compareTo(pb);
      return a.nome.compareTo(b.nome);
    });

    if (matches.length <= _maxResultados) return matches;
    return matches.take(_maxResultados);
  }
}
