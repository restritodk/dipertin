/// Módulo Fiscal — Camada de Provedores e Serviços Fiscais.
///
/// Fornece a estrutura completa para integração com APIs fiscais externas.
///
/// ## Arquitetura
/// ```
/// FiscalPayload (padrão DiPertin)
///     ↓
/// FiscalValidator (validação completa)
///     ↓
/// FiscalXmlBuilder (geração do XML NF-e padrão SEFAZ)
///     ↓
/// FiscalEmissaoService (orquestrador central)
///     ├── FiscalSeriesService (controle de numeração)
///     ├── FiscalContingenciaService (estado de contingência)
///     ├── FiscalCancelamentoService (cancelamento de NF-e)
///     ├── FiscalCartaCorrecaoService (CC-e)
///     ├── FiscalInutilizacaoService (inutilização)
///     ├── FiscalErroTranslator (mensagens amigáveis)
///     ├── FiscalEmailService (envio de DANFE/XML)
///     └── FiscalAuditService (logs de auditoria)
///     ↓
/// FiscalProvider (interface abstrata)
///     ├── FocusNFeProvider | NuvemFiscalProvider | PlugNotasProvider
///     ├── WebmaniaProvider | EnotasProvider | CustomFiscalProvider
///     ↓
/// API Fiscal Externa (SEFAZ)
/// ```
///
/// ## Segurança
/// Credenciais (API Keys, tokens, senhas de certificados A1) são
/// criptografadas via [FiscalCryptoUtil] e NUNCA expostas ao lojista.
/// Todas as operações são registradas em [FiscalAuditService].
export 'fiscal_payload.dart';
export 'fiscal_provider.dart';
export 'fiscal_provider_service.dart';
export 'fiscal_emissao_service.dart';
export 'fiscal_validator.dart';
export 'fiscal_xml_builder.dart';
export 'fiscal_crypto_util.dart';
export 'fiscal_serie_model.dart';
export 'fiscal_series_service.dart';
export 'fiscal_contingencia_service.dart';
export 'fiscal_cancelamento_service.dart';
export 'fiscal_carta_correcao_service.dart';
export 'fiscal_inutilizacao_service.dart';
export 'fiscal_erro_translator.dart';
export 'fiscal_email_service.dart';
export 'fiscal_audit_service.dart';
