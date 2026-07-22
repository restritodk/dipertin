import 'dart:ui' show Color;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

/// Módulo comercial ao qual a cobrança pertence. Cada módulo tem cor própria.
enum ModuloCobranca {
  gestaoComercial('gestao_comercial', 'Gestão Comercial', Color(0xFF6A1B9A),
      Color(0xFFF1E9FF)),
  pdv('pdv', 'PDV', Color(0xFFFF8F00), Color(0xFFFFF3E6)),
  gestaoEntregas('gestao_entregas', 'Gestão de Entregas', Color(0xFF16A34A),
      Color(0xFFE8F5E9)),
  financeiro('financeiro', 'Financeiro', Color(0xFF0EA5E9), Color(0xFFE6F6FE)),
  marketing('marketing', 'Marketing', Color(0xFFEC4899), Color(0xFFFDEAF4));

  const ModuloCobranca(this.codigo, this.rotulo, this.cor, this.fundo);

  final String codigo;
  final String rotulo;
  final Color cor;
  final Color fundo;

  static ModuloCobranca fromCodigo(String? c) {
    return ModuloCobranca.values.firstWhere(
      (m) => m.codigo == c,
      orElse: () => ModuloCobranca.gestaoComercial,
    );
  }
}

/// Situação de pagamento da cobrança. Cada status tem cor/fundo próprios.
enum StatusCobranca {
  emAberto('em_aberto', 'Em aberto', Color(0xFF0EA5E9), Color(0xFFE6F6FE)),
  vencida('vencida', 'Vencida', Color(0xFFF04438), Color(0xFFFEF2F2)),
  paga('paga', 'Paga', Color(0xFF16A34A), Color(0xFFE8F5E9)),
  cancelada('cancelada', 'Cancelada', Color(0xFF94A3B8), Color(0xFFF1F5F9)),
  reembolsada(
      'reembolsada', 'Reembolsada', Color(0xFFFF8F00), Color(0xFFFFF3E6));

  const StatusCobranca(this.codigo, this.rotulo, this.cor, this.fundo);

  final String codigo;
  final String rotulo;
  final Color cor;
  final Color fundo;

  static StatusCobranca fromCodigo(String? c) {
    return StatusCobranca.values.firstWhere(
      (s) => s.codigo == c,
      orElse: () => StatusCobranca.emAberto,
    );
  }
}

/// Status do pagamento via gateway (PIX/Cartão).
enum StatusPagamentoGateway {
  pendente('pendente', 'Pendente'),
  aprovado('aprovado', 'Aprovado'),
  expirado('expirado', 'Expirado'),
  cancelado('cancelado', 'Cancelado');

  const StatusPagamentoGateway(this.codigo, this.rotulo);

  final String codigo;
  final String rotulo;

  static StatusPagamentoGateway fromCodigo(String? c) {
    return StatusPagamentoGateway.values.firstWhere(
      (s) => s.codigo == c,
      orElse: () => StatusPagamentoGateway.pendente,
    );
  }
}

/// Cobrança de assinatura/módulo contratado.
/// Coleção Firestore: `assinaturas_cobrancas/{id}`
class CobrancaAssinatura {
  const CobrancaAssinatura({
    required this.id,
    required this.assinaturaId,
    required this.fatura,
    required this.clienteNome,
    required this.clienteEmail,
    required this.planoNome,
    required this.modulo,
    required this.vencimento,
    required this.valor,
    required this.status,
    // Campos de pagamento PIX
    this.mpPaymentId,
    this.mpStatus,
    this.mpQrCode,
    this.mpQrCodeBase64,
    this.mpExternalReference,
    this.pixGeradoEm,
    this.pixExpiraEm,
    this.statusPagamentoGateway,
    this.pagoEm,
  });

  final String id;
  final String assinaturaId;
  final String fatura;
  final String clienteNome;
  final String clienteEmail;
  final String planoNome;
  final ModuloCobranca modulo;
  final DateTime vencimento;
  final double valor;
  final StatusCobranca status;

  // ── Campos PIX ────────────────────────────────────────
  /// ID do pagamento no Mercado Pago.
  final String? mpPaymentId;

  /// Status do pagamento no MP (pending, approved, cancelled, etc).
  final String? mpStatus;

  /// Código PIX copia-e-cola.
  final String? mpQrCode;

  /// QR Code em base64 (para exibição como imagem).
  final String? mpQrCodeBase64;

  /// Reference externa usada na criação do PIX.
  final String? mpExternalReference;

  /// Data/hora em que o PIX foi gerado.
  final DateTime? pixGeradoEm;

  /// Data/hora em que o PIX expira.
  final DateTime? pixExpiraEm;

  /// Status do pagamento no gateway local.
  final StatusPagamentoGateway? statusPagamentoGateway;

  /// Data em que o pagamento foi confirmado.
  final DateTime? pagoEm;

  static final NumberFormat _moeda =
      NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
  static final DateFormat _data = DateFormat('dd/MM/yyyy', 'pt_BR');

  String get valorExibicao => _moeda.format(valor);
  String get vencimentoExibicao => _data.format(vencimento);
  String get idCurto => id.length <= 8 ? id : id.substring(0, 8);

  /// Texto da situação de vencimento ("Em 2 dias" / "Venceu há 1 dia" / "Hoje").
  String get situacaoVencimento {
    if (status == StatusCobranca.paga) return 'Paga';
    if (status == StatusCobranca.cancelada) return 'Cancelada';
    if (status == StatusCobranca.reembolsada) return 'Reembolsada';
    final hoje = DateTime.now();
    final h = DateTime(hoje.year, hoje.month, hoje.day);
    final v = DateTime(vencimento.year, vencimento.month, vencimento.day);
    final dias = v.difference(h).inDays;
    if (dias == 0) return 'Vence hoje';
    if (dias > 0) return 'Em $dias ${dias == 1 ? 'dia' : 'dias'}';
    final atraso = -dias;
    return 'Venceu há $atraso ${atraso == 1 ? 'dia' : 'dias'}';
  }

  bool get situacaoVencida {
    if (status == StatusCobranca.vencida) return true;
    if (status == StatusCobranca.paga ||
        status == StatusCobranca.cancelada ||
        status == StatusCobranca.reembolsada) {
      return false;
    }
    final hoje = DateTime.now();
    final h = DateTime(hoje.year, hoje.month, hoje.day);
    final v = DateTime(vencimento.year, vencimento.month, vencimento.day);
    return v.isBefore(h);
  }

  // ── Getters derivados PIX ───────────────────────────────

  /// True se tem PIX gerado.
  bool get temPixGerado => mpPaymentId != null && mpPaymentId!.isNotEmpty;

  /// True se o PIX ainda está válido (não expirou).
  bool get pixValido {
    if (!temPixGerado) return false;
    if (pixExpiraEm == null) return true; // Se não tem expiração, considera válido
    return pixExpiraEm!.isAfter(DateTime.now());
  }

  /// True se o pagamento PIX foi aprovado.
  bool get pixAprovado =>
      mpStatus == 'approved' || mpStatus == 'authorized';

  /// True se pode gerar novo PIX (cobrança em aberto/vencida sem PIX válido).
  bool get podeGerarPix =>
      (status == StatusCobranca.emAberto || status == StatusCobranca.vencida) &&
      (!temPixGerado || !pixValido);

  /// Data de expiração do PIX formatada.
  String? get pixExpiraEmExibicao {
    if (pixExpiraEm == null) return null;
    return _data.format(pixExpiraEm!);
  }

  /// Tempo restante para expiração do PIX.
  String? get pixTempoRestante {
    if (pixExpiraEm == null) return null;
    final agora = DateTime.now();
    if (pixExpiraEm!.isBefore(agora)) return 'Expirado';
    final diff = pixExpiraEm!.difference(agora);
    if (diff.inMinutes < 60) {
      return '${diff.inMinutes} min';
    }
    final horas = diff.inHours;
    final minutos = diff.inMinutes % 60;
    return '${horas}h ${minutos}m';
  }

  static CobrancaAssinatura fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final d = doc.data() ?? {};

    // Parse de data genérico (Timestamp, Date, String ISO)
    DateTime? parseData(dynamic v) {
      if (v == null) return null;
      if (v is Timestamp) return v.toDate();
      if (v is DateTime) return v;
      if (v is String) return DateTime.tryParse(v);
      return null;
    }

    final venc = d['vencimento'];
    final pixExpira = parseData(d['pix_expira_em']);
    final pixGerado = parseData(d['pix_gerado_em']);
    final pagoEm = parseData(d['pago_em']);

    return CobrancaAssinatura(
      id: doc.id,
      assinaturaId: d['assinatura_id'] as String? ?? '',
      fatura: d['fatura'] as String? ?? '#FAT-000000',
      clienteNome: d['store_name'] as String? ?? 'Loja',
      clienteEmail: d['email'] as String? ?? '',
      planoNome: d['plano_nome'] as String? ?? d['plan_name'] as String? ?? '',
      modulo: ModuloCobranca.fromCodigo(d['modulo'] as String?),
      vencimento:
          venc is Timestamp ? venc.toDate() : DateTime.now(),
      valor: (d['valor'] as num?)?.toDouble() ?? 0,
      status: StatusCobranca.fromCodigo(d['status'] as String?),
      // Campos PIX
      mpPaymentId: d['mp_payment_id'] as String?,
      mpStatus: d['mp_status'] as String?,
      mpQrCode: d['mp_qr_code'] as String?,
      mpQrCodeBase64: d['mp_qr_code_base64'] as String?,
      mpExternalReference: d['mp_external_reference'] as String?,
      pixGeradoEm: pixGerado,
      pixExpiraEm: pixExpira,
      statusPagamentoGateway:
          StatusPagamentoGateway.fromCodigo(d['status_pagamento_gateway'] as String?),
      pagoEm: pagoEm,
    );
  }
}
