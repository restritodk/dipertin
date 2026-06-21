import 'package:flutter/material.dart';

/// Status (funil) de um lead, com rótulo e cores para a UI do painel.
class MarketingLeadStatusInfo {
  const MarketingLeadStatusInfo(
    this.codigo,
    this.label,
    this.cor,
    this.fundo,
  );

  final String codigo;
  final String label;

  /// Cor principal (texto/ícone do chip).
  final Color cor;

  /// Fundo suave do chip.
  final Color fundo;
}

/// Funil de captação de LOJISTAS.
abstract final class MarketingLeadLojistaStatus {
  static const novo = 'novo';
  static const emContato = 'em_contato';
  static const negociacao = 'negociacao';
  static const aguardandoDoc = 'aguardando_doc';
  static const aprovado = 'aprovado';
  static const convertido = 'convertido';
  static const perdido = 'perdido';

  /// Ordem do funil (esquerda -> direita).
  static const List<String> ordem = [
    novo,
    emContato,
    negociacao,
    aguardandoDoc,
    aprovado,
    convertido,
    perdido,
  ];

  static const Map<String, MarketingLeadStatusInfo> _mapa = {
    novo: MarketingLeadStatusInfo(
      novo,
      'Novo',
      Color(0xFF2563EB),
      Color(0xFFEFF6FF),
    ),
    emContato: MarketingLeadStatusInfo(
      emContato,
      'Em contato',
      Color(0xFF7C3AED),
      Color(0xFFF3E8FD),
    ),
    negociacao: MarketingLeadStatusInfo(
      negociacao,
      'Negociação',
      Color(0xFFD97706),
      Color(0xFFFFF7ED),
    ),
    aguardandoDoc: MarketingLeadStatusInfo(
      aguardandoDoc,
      'Aguardando documentação',
      Color(0xFF0891B2),
      Color(0xFFECFEFF),
    ),
    aprovado: MarketingLeadStatusInfo(
      aprovado,
      'Aprovado',
      Color(0xFF059669),
      Color(0xFFECFDF5),
    ),
    convertido: MarketingLeadStatusInfo(
      convertido,
      'Convertido',
      Color(0xFF15803D),
      Color(0xFFDCFCE7),
    ),
    perdido: MarketingLeadStatusInfo(
      perdido,
      'Perdido',
      Color(0xFFDC2626),
      Color(0xFFFEF2F2),
    ),
  };

  static MarketingLeadStatusInfo info(String? codigo) {
    return _mapa[(codigo ?? '').trim()] ?? _mapa[novo]!;
  }

  static String label(String? codigo) => info(codigo).label;
}

/// Funil de captação de ENTREGADORES.
abstract final class MarketingLeadEntregadorStatus {
  static const novo = 'novo';
  static const emAnalise = 'em_analise';
  static const aprovado = 'aprovado';
  static const reprovado = 'reprovado';
  static const convertido = 'convertido';

  static const List<String> ordem = [
    novo,
    emAnalise,
    aprovado,
    reprovado,
    convertido,
  ];

  static const Map<String, MarketingLeadStatusInfo> _mapa = {
    novo: MarketingLeadStatusInfo(
      novo,
      'Novo',
      Color(0xFF2563EB),
      Color(0xFFEFF6FF),
    ),
    emAnalise: MarketingLeadStatusInfo(
      emAnalise,
      'Em análise',
      Color(0xFFD97706),
      Color(0xFFFFF7ED),
    ),
    aprovado: MarketingLeadStatusInfo(
      aprovado,
      'Aprovado',
      Color(0xFF059669),
      Color(0xFFECFDF5),
    ),
    reprovado: MarketingLeadStatusInfo(
      reprovado,
      'Reprovado',
      Color(0xFFDC2626),
      Color(0xFFFEF2F2),
    ),
    convertido: MarketingLeadStatusInfo(
      convertido,
      'Convertido',
      Color(0xFF15803D),
      Color(0xFFDCFCE7),
    ),
  };

  static MarketingLeadStatusInfo info(String? codigo) {
    return _mapa[(codigo ?? '').trim()] ?? _mapa[novo]!;
  }

  static String label(String? codigo) => info(codigo).label;
}
