import 'fiscal_payload.dart';

/// Resultado de uma operação fiscal (emissão, cancelamento, CC-e, etc.).
class FiscalProviderResult {
  const FiscalProviderResult({
    required this.sucesso,
    this.chaveAcesso,
    this.protocolo,
    this.numero,
    this.serie,
    this.xmlUrl,
    this.pdfUrl,
    this.mensagem,
    this.erro,
    this.providerResponse,
    this.statusEnvio = 'pendente',
    this.codigoRejeicao,
    // ─── Campos estruturados de erro ───
    this.focusStatusCode,
    this.focusResponse,
    this.sefazCode,
    this.sefazMessage,
    this.validationErrors = const [],
  });

  final bool sucesso;
  final String? chaveAcesso;
  final String? protocolo;
  final String? numero;
  final String? serie;
  final String? xmlUrl;
  final String? pdfUrl;
  final String? mensagem;
  final String? erro;
  final String? providerResponse;
  final String statusEnvio;
  final String? codigoRejeicao;

  // ─── Campos estruturados de erro ───
  final int? focusStatusCode;
  final String? focusResponse;
  final String? sefazCode;
  final String? sefazMessage;
  final List<String> validationErrors;

  String? get numeroNfe => numero;

  static const pending = FiscalProviderResult(
    sucesso: false,
    statusEnvio: 'pendente',
  );

  FiscalProviderResult copyWith({
    bool? sucesso,
    String? chaveAcesso,
    String? protocolo,
    String? numero,
    String? numeroNfe,
    String? serie,
    String? xmlUrl,
    String? pdfUrl,
    String? mensagem,
    String? erro,
    String? providerResponse,
    String? statusEnvio,
    String? codigoRejeicao,
    int? focusStatusCode,
    String? focusResponse,
    String? sefazCode,
    String? sefazMessage,
    List<String>? validationErrors,
  }) {
    return FiscalProviderResult(
      sucesso: sucesso ?? this.sucesso,
      chaveAcesso: chaveAcesso ?? this.chaveAcesso,
      protocolo: protocolo ?? this.protocolo,
      numero: numeroNfe ?? numero ?? this.numero,
      serie: serie ?? this.serie,
      xmlUrl: xmlUrl ?? this.xmlUrl,
      pdfUrl: pdfUrl ?? this.pdfUrl,
      mensagem: mensagem ?? this.mensagem,
      erro: erro ?? this.erro,
      providerResponse: providerResponse ?? this.providerResponse,
      statusEnvio: statusEnvio ?? this.statusEnvio,
      codigoRejeicao: codigoRejeicao ?? this.codigoRejeicao,
      focusStatusCode: focusStatusCode ?? this.focusStatusCode,
      focusResponse: focusResponse ?? this.focusResponse,
      sefazCode: sefazCode ?? this.sefazCode,
      sefazMessage: sefazMessage ?? this.sefazMessage,
      validationErrors: validationErrors ?? this.validationErrors,
    );
  }
}

/// Informações sobre um provedor fiscal.
class FiscalProviderInfo {
  const FiscalProviderInfo({
    required this.id,
    required this.nome,
    required this.descricao,
    required this.documentosSuportados,
    this.site,
    this.temHomologacao = true,
  });

  final String id;
  final String nome;
  final String descricao;
  final List<String> documentosSuportados;
  final String? site;
  final bool temHomologacao;
}

/// Camada padrão de provedor fiscal.
///
/// Cada plataforma fiscal externa deve implementar esta interface.
abstract class FiscalProvider {
  String get id;
  String get nome;
  FiscalProviderInfo get info;
  List<String> get documentosSuportados;

  /// Emite um documento fiscal.
  Future<FiscalProviderResult> emitirNota(
    FiscalPayload payload,
    Map<String, dynamic> config,
  );

  /// Cancela uma NF-e autorizada dentro do prazo legal.
  ///
  /// [chaveAcesso] Chave de 44 dígitos da NF-e a ser cancelada.
  /// [justificativa] Motivo do cancelamento (mín. 15 caracteres).
  /// [numeroProtocolo] Protocolo de autorização da NF-e.
  /// [config] Credenciais/configurações do provedor.
  Future<FiscalProviderResult> cancelarNota({
    required String chaveAcesso,
    required String justificativa,
    required String numeroProtocolo,
    required Map<String, dynamic> config,
  });

  /// Envia uma Carta de Correção Eletrônica (CC-e).
  ///
  /// [chaveAcesso] Chave de 44 dígitos da NF-e a corrigir.
  /// [textoCorrecao] Texto da correção (máx. 1.000 caracteres).
  /// [sequencia] Número sequencial da CC-e (1, 2, 3...).
  /// [config] Credenciais/configurações do provedor.
  Future<FiscalProviderResult> enviarCartaCorrecao({
    required String chaveAcesso,
    required String textoCorrecao,
    required int sequencia,
    required Map<String, dynamic> config,
  });

  /// Inutiliza uma faixa de numeração de NF-e.
  ///
  /// [serie] Série fiscal.
  /// [numeroInicial] Primeiro número da faixa.
  /// [numeroFinal] Último número da faixa.
  /// [justificativa] Justificativa (mín. 15 caracteres).
  /// [config] Credenciais/configurações do provedor.
  Future<FiscalProviderResult> inutilizarNumeracao({
    required String serie,
    required int numeroInicial,
    required int numeroFinal,
    required String justificativa,
    required Map<String, dynamic> config,
  });

  /// Testa a conexão com o provedor usando as credenciais fornecidas.
  Future<bool> testarConexao(Map<String, dynamic> config);

  /// Valida a configuração do provedor.
  Map<String, String>? validarConfiguracao(Map<String, dynamic> config);

  /// Converte o payload padronizado para o formato específico do provedor.
  Map<String, dynamic> converterParaFormatoProvedor(
    FiscalPayload payload,
    Map<String, dynamic> config,
  );
}
