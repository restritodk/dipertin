import 'package:cloud_firestore/cloud_firestore.dart';

/// Status possíveis de um documento fiscal.
class StatusFiscal {
  static const processando = 'processando';
  static const autorizada = 'autorizada';
  static const rejeitada = 'rejeitada';
  static const cancelada = 'cancelada';
  static const cancelamentoHomologado = 'cancelamento_homologado';
  static const contingencia = 'contingencia';
  static const contingenciaResolvida = 'contingencia_resolvida';
  static const ccEnviada = 'cc_e_enviada';
  static const numeracaoInutilizada = 'numeracao_inutilizada';

  static const List<String> todos = [
    processando, autorizada, rejeitada, cancelada,
    cancelamentoHomologado, contingencia, contingenciaResolvida,
    ccEnviada, numeracaoInutilizada,
  ];
}

/// Evento de uma carta de correção (CC-e).
class CartaCorrecaoEvento {
  final int sequencia;
  final String textoCorrecao;
  final String? protocolo;
  final String? xmlUrl;
  final String? chaveAcesso;
  final Timestamp? enviadaEm;

  const CartaCorrecaoEvento({
    required this.sequencia,
    required this.textoCorrecao,
    this.protocolo,
    this.xmlUrl,
    this.chaveAcesso,
    this.enviadaEm,
  });

  Map<String, dynamic> toMap() => {
        'sequencia': sequencia,
        'texto_correcao': textoCorrecao,
        if (protocolo != null) 'protocolo': protocolo,
        if (xmlUrl != null) 'xml_url': xmlUrl,
        if (chaveAcesso != null) 'chave_acesso': chaveAcesso,
        if (enviadaEm != null) 'enviada_em': enviadaEm,
      };

  static CartaCorrecaoEvento fromMap(Map<String, dynamic> m) {
    return CartaCorrecaoEvento(
      sequencia: (m['sequencia'] as num?)?.toInt() ?? 0,
      textoCorrecao: m['texto_correcao'] as String? ?? '',
      protocolo: m['protocolo'] as String?,
      xmlUrl: m['xml_url'] as String?,
      chaveAcesso: m['chave_acesso'] as String?,
      enviadaEm: m['enviada_em'] as Timestamp?,
    );
  }
}

/// Documento fiscal emitido.
///
/// Coleção: `fiscal_documents/{id}`
class FiscalDocumentModel {
  final String id;
  final String storeId;
  final String? saleId;
  final String? customerId;
  final String documentType;
  final String provider;
  final String status;
  final String? accessKey;
  final String? protocol;
  final String? number;
  final String? series;
  final String? xmlUrl;
  final String? pdfUrl;
  final String? xmlCancelamentoUrl;
  final String? pdfCancelamentoUrl;
  final String? rejectionReason;
  final String? rejectionCode;
  final String? providerResponse;
  final String? justificativaCancelamento;
  final String? justificativaInutilizacao;
  final List<CartaCorrecaoEvento> cartasCorrecao;
  final bool emContingencia;
  final String? motivoContingencia;
  final Timestamp? resolvidoContingenciaEm;
  final Timestamp? issuedAt;
  final Timestamp? cancelledAt;
  final Timestamp? createdAt;
  final Timestamp? updatedAt;

  FiscalDocumentModel({
    required this.id,
    required this.storeId,
    this.saleId,
    this.customerId,
    required this.documentType,
    required this.provider,
    this.status = StatusFiscal.processando,
    this.accessKey,
    this.protocol,
    this.number,
    this.series,
    this.xmlUrl,
    this.pdfUrl,
    this.xmlCancelamentoUrl,
    this.pdfCancelamentoUrl,
    this.rejectionReason,
    this.rejectionCode,
    this.providerResponse,
    this.justificativaCancelamento,
    this.justificativaInutilizacao,
    this.cartasCorrecao = const [],
    this.emContingencia = false,
    this.motivoContingencia,
    this.resolvidoContingenciaEm,
    this.issuedAt,
    this.cancelledAt,
    this.createdAt,
    this.updatedAt,
  });

  bool get isAutorizada => status == StatusFiscal.autorizada;
  bool get isRejeitada => status == StatusFiscal.rejeitada;
  bool get isCancelada =>
      status == StatusFiscal.cancelada ||
      status == StatusFiscal.cancelamentoHomologado;
  bool get isProcessando => status == StatusFiscal.processando;
  bool get isContingencia => status == StatusFiscal.contingencia;
  bool get podeCancelar =>
      isAutorizada && !isCancelada;
  bool get podeCorrigir =>
      isAutorizada && !isCancelada;

  int get totalCartasCorrecao => cartasCorrecao.length;

  static FiscalDocumentModel fromFirestore(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};
    final cartasRaw = d['cartas_correcao'] as List<dynamic>?;
    return FiscalDocumentModel(
      id: doc.id,
      storeId: d['store_id'] as String? ?? '',
      saleId: d['sale_id'] as String?,
      customerId: d['customer_id'] as String?,
      documentType: d['document_type'] as String? ?? '',
      provider: d['provider'] as String? ?? '',
      status: d['status'] as String? ?? StatusFiscal.processando,
      accessKey: d['access_key'] as String?,
      protocol: d['protocol'] as String?,
      number: d['number'] as String?,
      series: d['series'] as String?,
      xmlUrl: d['xml_url'] as String?,
      pdfUrl: d['pdf_url'] as String?,
      xmlCancelamentoUrl: d['xml_cancelamento_url'] as String?,
      pdfCancelamentoUrl: d['pdf_cancelamento_url'] as String?,
      rejectionReason: d['rejection_reason'] as String?,
      rejectionCode: d['rejection_code'] as String?,
      providerResponse: d['provider_response'] as String?,
      justificativaCancelamento: d['justificativa_cancelamento'] as String?,
      justificativaInutilizacao: d['justificativa_inutilizacao'] as String?,
      cartasCorrecao: cartasRaw != null
          ? cartasRaw
              .whereType<Map>()
              .map((e) => CartaCorrecaoEvento.fromMap(Map<String, dynamic>.from(e)))
              .toList()
          : const [],
      emContingencia: d['em_contingencia'] as bool? ?? false,
      motivoContingencia: d['motivo_contingencia'] as String?,
      resolvidoContingenciaEm: d['resolvido_contingencia_em'] as Timestamp?,
      issuedAt: d['issued_at'] as Timestamp?,
      cancelledAt: d['cancelled_at'] as Timestamp?,
      createdAt: d['created_at'] as Timestamp?,
      updatedAt: d['updated_at'] as Timestamp?,
    );
  }

  Map<String, dynamic> toMap() => {
        'store_id': storeId,
        'sale_id': saleId,
        'customer_id': customerId,
        'document_type': documentType,
        'provider': provider,
        'status': status,
        'access_key': accessKey,
        'protocol': protocol,
        'number': number,
        'series': series,
        'xml_url': xmlUrl,
        'pdf_url': pdfUrl,
        'xml_cancelamento_url': xmlCancelamentoUrl,
        'pdf_cancelamento_url': pdfCancelamentoUrl,
        'rejection_reason': rejectionReason,
        'rejection_code': rejectionCode,
        'provider_response': providerResponse,
        'justificativa_cancelamento': justificativaCancelamento,
        'justificativa_inutilizacao': justificativaInutilizacao,
        if (cartasCorrecao.isNotEmpty)
          'cartas_correcao': cartasCorrecao.map((c) => c.toMap()).toList(),
        'em_contingencia': emContingencia,
        'motivo_contingencia': motivoContingencia,
        'resolvido_contingencia_em': resolvidoContingenciaEm,
        'issued_at': issuedAt,
        'cancelled_at': cancelledAt,
        'updated_at': FieldValue.serverTimestamp(),
      };

  Map<String, dynamic> toCreateMap() => {
        ...toMap(),
        'created_at': FieldValue.serverTimestamp(),
      };
}
