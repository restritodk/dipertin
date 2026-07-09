import 'fiscal_provider.dart';
import 'providers/focus_nfe_provider.dart';
import 'providers/nuvem_fiscal_provider.dart';
import 'providers/plug_notas_provider.dart';
import 'providers/webmania_provider.dart';
import 'providers/custom_fiscal_provider.dart';
import 'providers/enotas_provider.dart';

/// Registry e resolução de provedores fiscais.
///
/// Centraliza todos os provedores disponíveis e resolve
/// qual provider usar com base no ID da integração.
class FiscalProviderService {
  FiscalProviderService._();

  static final FiscalProviderService _instance = FiscalProviderService._();

  /// Instância singleton.
  static FiscalProviderService get instance => _instance;

  /// Registry interno de provedores.
  final Map<String, FiscalProvider> _providers = {};

  /// Inicializa o registry com todos os provedores disponíveis.
  void inicializar() {
    if (_providers.isNotEmpty) return;

    final lista = <FiscalProvider>[
      FocusNFeProvider(),
      NuvemFiscalProvider(),
      PlugNotasProvider(),
      WebmaniaProvider(),
      EnotasProvider(),
      CustomFiscalProvider(),
    ];

    for (final p in lista) {
      _providers[p.id] = p;
    }
  }

  /// Retorna o provedor pelo ID.
  ///
  /// Lança [StateError] se o registry não foi inicializado.
  FiscalProvider? obterProvider(String id) {
    inicializar();
    return _providers[id];
  }

  /// Retorna todos os provedores registrados.
  List<FiscalProvider> listarProviders() {
    inicializar();
    return _providers.values.toList();
  }

  /// Retorna as informações de todos os provedores registrados.
  List<FiscalProviderInfo> listarInfos() {
    inicializar();
    return _providers.values.map((p) => p.info).toList();
  }

  /// Resolve o provedor com base nos dados da integração Firestore.
  ///
  /// [integrationData] é o map do documento `fiscal_integrations/{id}`.
  FiscalProvider? resolverDeIntegracao(Map<String, dynamic> integrationData) {
    inicializar();
    final providerId = integrationData['provider'] as String?;
    if (providerId == null || providerId.isEmpty) return null;
    return _providers[providerId];
  }

  /// Resolve o provedor pelo nome armazenado (ex: 'Focus NFe').
  FiscalProvider? resolverPorNome(String nomeProvedor) {
    inicializar();
    // Tenta match exato primeiro
    for (final p in _providers.values) {
      if (p.nome == nomeProvedor) return p;
    }
    // Tenta match parcial (case insensitive)
    final lower = nomeProvedor.toLowerCase();
    for (final p in _providers.values) {
      if (p.nome.toLowerCase().contains(lower) ||
          p.id.toLowerCase().contains(lower)) {
        return p;
      }
    }
    return null;
  }

  /// Valida se um documento fiscal é suportado por um provedor.
  bool providerSuportaDocumento(String providerId, String tipoDocumento) {
    final p = obterProvider(providerId);
    if (p == null) return false;
    return p.documentosSuportados.contains(tipoDocumento);
  }

  /// Obtém ou cria a configuração do provedor a partir dos dados da integração.
  Map<String, dynamic> extrairConfig(
    Map<String, dynamic> integrationData, {
    String? integrationId,
  }) {
    return {
      'integration_id': integrationId ?? integrationData['id'] as String? ?? '',
      'api_key': integrationData['credentials_encrypted'] ?? '',
      'client_id': integrationData['client_id'] ?? '',
      'client_secret': integrationData['client_secret'] ?? '',
      'consumer_key': integrationData['consumer_key'] ?? '',
      'consumer_secret': integrationData['consumer_secret'] ?? '',
      'access_token': integrationData['access_token'] ?? '',
      'access_token_secret': integrationData['access_token_secret'] ?? '',
      'base_url_sandbox': integrationData['base_url_sandbox'] ?? '',
      'base_url_production': integrationData['base_url_production'] ?? '',
      // Enotas: ID da empresa na plataforma
      'empresa_id': integrationData['empresa_id'] ?? '',
      // Custom: endpoints e metodo de autenticacao
      'endpoint_emissao': integrationData['endpoint_emissao'] ?? '',
      'endpoint_cancelamento': integrationData['endpoint_cancelamento'] ?? '',
      'metodo_autenticacao': integrationData['metodo_autenticacao'] ?? '',
    };
  }
}
