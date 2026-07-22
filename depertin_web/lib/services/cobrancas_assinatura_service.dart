import 'package:cloud_firestore/cloud_firestore.dart';

import 'firebase_functions_config.dart';

/// Acesso à coleção `assinaturas_cobrancas` e às callables de gestão.
///
/// A escrita é sempre feita via Cloud Function (Admin SDK); o painel apenas
/// lê em tempo real e dispara as ações.
abstract final class CobrancasAssinaturaService {
  static const String colecao = 'assinaturas_cobrancas';

  static FirebaseFirestore get _db => FirebaseFirestore.instance;

  /// Stream em tempo real das cobranças (mais recentes por vencimento).
  static Stream<QuerySnapshot<Map<String, dynamic>>> stream() {
    return _db
        .collection(colecao)
        .orderBy('vencimento', descending: true)
        .snapshots();
  }

  /// Gera/atualiza cobranças a partir das assinaturas contratadas.
  static Future<GerarCobrancasResultado> gerar() async {
    final resp = await callFirebaseFunctionSafe(
      'adminGerarCobrancasAssinaturas',
    );
    return GerarCobrancasResultado(
      criadas: (resp['criadas'] as num?)?.toInt() ?? 0,
      atualizadas: (resp['atualizadas'] as num?)?.toInt() ?? 0,
    );
  }

  /// Cria uma cobrança manual para uma assinatura existente.
  static Future<String> criarAvulsa({
    required String assinaturaId,
    required double valor,
    required DateTime vencimento,
    required String moduloCodigo,
  }) async {
    final resp = await callFirebaseFunctionSafe(
      'adminCriarCobrancaAvulsa',
      parameters: {
        'assinaturaId': assinaturaId,
        'valor': valor,
        'vencimento': vencimento.toIso8601String(),
        'modulo': moduloCodigo,
      },
    );
    return resp['cobrancaId'] as String? ?? '';
  }

  /// Envia cobrança por e-mail usando o SMTP do sistema (naoresponder@dipertin.com.br).
  static Future<void> enviarCobrancaEmail({
    required String cobrancaId,
    required String clienteEmail,
    required String clienteNome,
    required String fatura,
    required String planoNome,
    required String modulo,
    required String valorExibicao,
    required String vencimento,
    required String statusRotulo,
    String mensagemPersonalizada = '',
  }) async {
    await callFirebaseFunctionSafe(
      'assinaturaEnviarCobrancaEmail',
      parameters: {
        'cobrancaId': cobrancaId,
        'clienteEmail': clienteEmail,
        'clienteNome': clienteNome,
        'fatura': fatura,
        'planoNome': planoNome,
        'modulo': modulo,
        'valorExibicao': valorExibicao,
        'vencimento': vencimento,
        'statusRotulo': statusRotulo,
        if (mensagemPersonalizada.isNotEmpty)
          'mensagemPersonalizada': mensagemPersonalizada,
      },
    );
  }

  /// Ações sobre uma cobrança:
  /// marcar_paga | reabrir | cancelar | reembolsar | registrar_envio |
  /// segunda_via | excluir.
  static Future<void> atualizar({
    required String cobrancaId,
    required String acao,
    String? canal,
    String? descricao,
  }) async {
    await callFirebaseFunctionSafe(
      'adminAtualizarCobranca',
      parameters: {
        'cobrancaId': cobrancaId,
        'acao': acao,
        'canal': canal,
        if (descricao != null && descricao.isNotEmpty) 'descricao': descricao,
      },
    );
  }

  /// Envia o recibo por e-mail usando o SMTP do sistema (naoresponder@dipertin.com.br).
  static Future<void> enviarReciboEmail({
    required String cobrancaId,
    required String clienteEmail,
    required String clienteNome,
    required String fatura,
    required String planoNome,
    required String modulo,
    required String valorExibicao,
    required String vencimento,
    required String statusRotulo,
    String formaPagamento = '',
    String? dataPagamento,
    String? dataEmissao,
    required String pdfBase64,
  }) async {
    await callFirebaseFunctionSafe(
      'assinaturaEnviarReciboEmail',
      parameters: {
        'cobrancaId': cobrancaId,
        'clienteEmail': clienteEmail,
        'clienteNome': clienteNome,
        'fatura': fatura,
        'planoNome': planoNome,
        'modulo': modulo,
        'valorExibicao': valorExibicao,
        'vencimento': vencimento,
        'statusRotulo': statusRotulo,
        'formaPagamento': formaPagamento,
        if (dataPagamento != null) 'dataPagamento': dataPagamento,
        if (dataEmissao != null) 'dataEmissao': dataEmissao,
        'reciboNumero': fatura,
        'pdfBase64': pdfBase64,
      },
    );
  }

  // ═══════════════════════════════════════════════════════════
  // PIX DE COBRANÇA RECORRENTE (painel lojista)
  // ═══════════════════════════════════════════════════════════

  /// Gera PIX para pagar uma cobrança existente.
  ///
  /// Chama a Cloud Function [assinaturaCobrancaGerarPix].
  /// Retorna os dados do PIX (QR Code, copia-e-colá, expiração).
  ///
  /// Se já existir PIX válido para esta cobrança, retorna o existente.
  static Future<GerarPixCobrancaResultado> gerarPixCobranca(
    String cobrancaId,
  ) async {
    final resp = await callFirebaseFunctionSafe(
      'assinaturaCobrancaGerarPix',
      parameters: {
        'cobrancaId': cobrancaId,
      },
    );
    return GerarPixCobrancaResultado.fromJson(
      Map<String, dynamic>.from(resp),
    );
  }

  /// Consulta o status do PIX de uma cobrança.
  ///
  /// Chama a Cloud Function [assinaturaCobrancaConsultarStatusPix].
  /// Se o pagamento for aprovado, a assinatura será renovada automaticamente.
  ///
  /// Retorna o status atual do pagamento.
  static Future<ConsultarStatusPixResultado> consultarStatusPixCobranca(
    String cobrancaId,
  ) async {
    final resp = await callFirebaseFunctionSafe(
      'assinaturaCobrancaConsultarStatusPix',
      parameters: {
        'cobrancaId': cobrancaId,
      },
    );
    return ConsultarStatusPixResultado.fromJson(
      Map<String, dynamic>.from(resp),
    );
  }
}

class GerarCobrancasResultado {
  const GerarCobrancasResultado({
    required this.criadas,
    required this.atualizadas,
  });

  final int criadas;
  final int atualizadas;

  int get total => criadas + atualizadas;
}

/// Resultado da geração de PIX para uma cobrança.
class GerarPixCobrancaResultado {
  const GerarPixCobrancaResultado({
    required this.qrCode,
    required this.qrCodeBase64,
    required this.pixCopiaECola,
    required this.expiresAt,
    required this.paymentId,
    required this.status,
    this.reutilizado = false,
  });

  /// Código PIX copia-e-cola.
  final String qrCode;

  /// QR Code em base64 (para exibição como imagem).
  final String qrCodeBase64;

  /// Mesmo que qrCode (para compatibilidade).
  final String pixCopiaECola;

  /// Data/hora de expiração do PIX.
  final String expiresAt;

  /// ID do pagamento no Mercado Pago.
  final String paymentId;

  /// Status do pagamento no MP.
  final String status;

  /// True se o PIX retornado já existia (não foi gerado novo).
  final bool reutilizado;

  factory GerarPixCobrancaResultado.fromJson(Map<String, dynamic> json) {
    return GerarPixCobrancaResultado(
      qrCode: json['qrCode'] as String? ?? '',
      qrCodeBase64: json['qrCodeBase64'] as String? ?? '',
      pixCopiaECola: json['pixCopiaECola'] as String? ?? json['qrCode'] as String? ?? '',
      expiresAt: json['expiresAt'] as String? ?? '',
      paymentId: json['paymentId'] as String? ?? '',
      status: json['status'] as String? ?? 'pending',
      reutilizado: json['reutilizado'] as bool? ?? false,
    );
  }
}

/// Resultado da consulta de status do PIX.
class ConsultarStatusPixResultado {
  const ConsultarStatusPixResultado({
    required this.status,
    required this.pago,
    required this.message,
  });

  /// Status: "paga", "pendente", "expirado", "cancelado", etc.
  final String status;

  /// True se o pagamento foi aprovado.
  final bool pago;

  /// Mensagem descritiva do status.
  final String message;

  factory ConsultarStatusPixResultado.fromJson(Map<String, dynamic> json) {
    return ConsultarStatusPixResultado(
      status: json['status'] as String? ?? 'desconhecido',
      pago: json['pago'] as bool? ?? false,
      message: json['message'] as String? ?? '',
    );
  }
}
