import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// Provedor de integração fiscal cadastrado pelo admin.
///
/// Coleção: `fiscal_integrations/{id}`
class FiscalIntegrationModel {
  final String id;
  final String provider;
  final String providerName;
  final String? nomeIntegracao; // nome personalizado (ex.: "Focus NFe - Fran Artesanato")
  final String environment; // sandbox | production
  final String? credentialsEncrypted;
  final String baseUrlSandbox;
  final String? baseUrlProduction;
  final List<String> supportedDocuments; // nfe, nfce, nfse, cte, mdfe
  final String status; // active | inactive | error
  final Timestamp? createdAt;
  final Timestamp? updatedAt;

  FiscalIntegrationModel({
    required this.id,
    required this.provider,
    required this.providerName,
    this.nomeIntegracao,
    this.environment = 'sandbox',
    this.credentialsEncrypted,
    this.baseUrlSandbox = '',
    this.baseUrlProduction,
    this.supportedDocuments = const [],
    this.status = 'inactive',
    this.createdAt,
    this.updatedAt,
  });

  /// Nome de exibição: prioriza nome_integracao, senão usa providerName.
  String get nomeExibicao => nomeIntegracao ?? providerName;

  bool get isAtivo => status == 'active';
  bool get isErro => status == 'error';

  static FiscalIntegrationModel fromFirestore(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};
    return FiscalIntegrationModel(
      id: doc.id,
      provider: d['provider'] as String? ?? '',
      providerName: d['provider_name'] as String? ?? '',
      nomeIntegracao: d['nome_integracao'] as String?,
      environment: d['environment'] as String? ?? 'sandbox',
      credentialsEncrypted: d['credentials_encrypted'] as String?,
      baseUrlSandbox: d['base_url_sandbox'] as String? ?? '',
      baseUrlProduction: d['base_url_production'] as String?,
      supportedDocuments:
          (d['supported_documents'] as List<dynamic>?)?.cast<String>() ?? [],
      status: d['status'] as String? ?? 'inactive',
      createdAt: d['created_at'] as Timestamp?,
      updatedAt: d['updated_at'] as Timestamp?,
    );
  }

  Map<String, dynamic> toMap() => {
        'provider': provider,
        'provider_name': providerName,
        if (nomeIntegracao != null && nomeIntegracao!.trim().isNotEmpty)
          'nome_integracao': nomeIntegracao!.trim(),
        'environment': environment,
        'credentials_encrypted': credentialsEncrypted,
        'base_url_sandbox': baseUrlSandbox,
        'base_url_production': baseUrlProduction,
        'supported_documents': supportedDocuments,
        'status': status,
        'updated_at': FieldValue.serverTimestamp(),
      };

  Map<String, dynamic> toCreateMap() => {
        ...toMap(),
        'created_at': FieldValue.serverTimestamp(),
      };
}

/// Definição de um provedor fiscal pré-cadastrado.
class ProvedorFiscalInfo {
  final String id;
  final String nome;
  final String descricao;
  final IconData icone;
  final List<String> documentosSuportados;
  final List<CampoIntegracao> campos;

  const ProvedorFiscalInfo({
    required this.id,
    required this.nome,
    required this.descricao,
    required this.icone,
    this.documentosSuportados = const [],
    this.campos = const [],
  });

  static const List<ProvedorFiscalInfo> provedores = [
    ProvedorFiscalInfo(
      id: 'focus_nfe',
      nome: 'Focus NFe',
      descricao: 'API fiscal para emissão de NF-e, NFC-e, NFS-e, CT-e e MDF-e.',
      icone: Icons.description_rounded,
      documentosSuportados: ['nfe', 'nfce', 'nfse', 'cte', 'mdfe'],
      campos: [
        CampoIntegracao(chave: 'api_key', label: 'Token / API Key', tipo: CampoIntegracaoTipo.senha),
        CampoIntegracao(chave: 'environment', label: 'Ambiente', tipo: CampoIntegracaoTipo.selecao, opcoes: ['Homologação', 'Produção']),
        CampoIntegracao(chave: 'status', label: 'Status', tipo: CampoIntegracaoTipo.selecao, opcoes: ['Ativo', 'Inativo']),
      ],
    ),
    ProvedorFiscalInfo(
      id: 'nuvem_fiscal',
      nome: 'Nuvem Fiscal',
      descricao: 'API REST para automação comercial e documentos fiscais.',
      icone: Icons.cloud_rounded,
      documentosSuportados: ['nfe', 'nfce', 'nfse', 'cte', 'mdfe'],
      campos: [
        CampoIntegracao(chave: 'client_id', label: 'Client ID', tipo: CampoIntegracaoTipo.texto),
        CampoIntegracao(chave: 'client_secret', label: 'Client Secret', tipo: CampoIntegracaoTipo.senha),
        CampoIntegracao(chave: 'environment', label: 'Ambiente', tipo: CampoIntegracaoTipo.selecao, opcoes: ['Homologação', 'Produção']),
        CampoIntegracao(chave: 'status', label: 'Status', tipo: CampoIntegracaoTipo.selecao, opcoes: ['Ativo', 'Inativo']),
      ],
    ),
    ProvedorFiscalInfo(
      id: 'plug_notas',
      nome: 'PlugNotas / TecnoSpeed',
      descricao: 'API para emissão de NF-e, NFC-e e NFS-e.',
      icone: Icons.electric_bolt_rounded,
      documentosSuportados: ['nfe', 'nfce', 'nfse'],
      campos: [
        CampoIntegracao(chave: 'api_key', label: 'API Key', tipo: CampoIntegracaoTipo.senha),
        CampoIntegracao(chave: 'environment', label: 'Ambiente', tipo: CampoIntegracaoTipo.selecao, opcoes: ['Homologação', 'Produção']),
        CampoIntegracao(chave: 'status', label: 'Status', tipo: CampoIntegracaoTipo.selecao, opcoes: ['Ativo', 'Inativo']),
      ],
    ),
    ProvedorFiscalInfo(
      id: 'webmania_br',
      nome: 'WebmaniaBR',
      descricao: 'API REST para emissão de NF-e e NFC-e.',
      icone: Icons.web_rounded,
      documentosSuportados: ['nfe', 'nfce'],
      campos: [
        CampoIntegracao(chave: 'consumer_key', label: 'Consumer Key', tipo: CampoIntegracaoTipo.senha),
        CampoIntegracao(chave: 'consumer_secret', label: 'Consumer Secret', tipo: CampoIntegracaoTipo.senha),
        CampoIntegracao(chave: 'access_token', label: 'Access Token', tipo: CampoIntegracaoTipo.senha),
        CampoIntegracao(chave: 'access_token_secret', label: 'Access Token Secret', tipo: CampoIntegracaoTipo.senha),
        CampoIntegracao(chave: 'environment', label: 'Ambiente', tipo: CampoIntegracaoTipo.selecao, opcoes: ['Homologação', 'Produção']),
        CampoIntegracao(chave: 'status', label: 'Status', tipo: CampoIntegracaoTipo.selecao, opcoes: ['Ativo', 'Inativo']),
      ],
    ),
    ProvedorFiscalInfo(
      id: 'enotas',
      nome: 'Enotas',
      descricao: 'Plataforma para emissão de notas fiscais de serviço.',
      icone: Icons.receipt_long_rounded,
      documentosSuportados: ['nfse'],
      campos: [
        CampoIntegracao(chave: 'api_key', label: 'API Key', tipo: CampoIntegracaoTipo.senha),
        CampoIntegracao(chave: 'environment', label: 'Ambiente', tipo: CampoIntegracaoTipo.selecao, opcoes: ['Homologação', 'Produção']),
        CampoIntegracao(chave: 'status', label: 'Status', tipo: CampoIntegracaoTipo.selecao, opcoes: ['Ativo', 'Inativo']),
      ],
    ),
    ProvedorFiscalInfo(
      id: 'arquivei',
      nome: 'Arquivei',
      descricao: 'Consulta, armazenamento e gestão de documentos fiscais.',
      icone: Icons.archive_rounded,
      documentosSuportados: ['nfe', 'nfce', 'nfse'],
      campos: [
        CampoIntegracao(chave: 'api_id', label: 'API ID', tipo: CampoIntegracaoTipo.texto),
        CampoIntegracao(chave: 'api_key', label: 'API Key', tipo: CampoIntegracaoTipo.senha),
        CampoIntegracao(chave: 'environment', label: 'Ambiente', tipo: CampoIntegracaoTipo.selecao, opcoes: ['Homologação', 'Produção']),
        CampoIntegracao(chave: 'status', label: 'Status', tipo: CampoIntegracaoTipo.selecao, opcoes: ['Ativo', 'Inativo']),
      ],
    ),
    ProvedorFiscalInfo(
      id: 'personalizado',
      nome: 'Outro / Conexão personalizada',
      descricao: 'Configure manualmente qualquer outro provedor fiscal.',
      icone: Icons.settings_ethernet_rounded,
      documentosSuportados: ['nfe', 'nfce', 'nfse', 'cte', 'mdfe'],
      campos: [
        CampoIntegracao(chave: 'nome_integracao', label: 'Nome da integração', tipo: CampoIntegracaoTipo.texto),
        CampoIntegracao(chave: 'base_url_homologacao', label: 'Base URL homologação', tipo: CampoIntegracaoTipo.texto),
        CampoIntegracao(chave: 'base_url_producao', label: 'Base URL produção', tipo: CampoIntegracaoTipo.texto),
        CampoIntegracao(chave: 'metodo_auth', label: 'Método de autenticação', tipo: CampoIntegracaoTipo.selecao, opcoes: ['Bearer Token', 'Basic Auth', 'API Key', 'OAuth2']),
        CampoIntegracao(chave: 'api_key_header', label: 'Header da API Key', tipo: CampoIntegracaoTipo.texto),
        CampoIntegracao(chave: 'token', label: 'Token', tipo: CampoIntegracaoTipo.senha),
        CampoIntegracao(chave: 'client_id', label: 'Client ID', tipo: CampoIntegracaoTipo.texto),
        CampoIntegracao(chave: 'client_secret', label: 'Client Secret', tipo: CampoIntegracaoTipo.senha),
        CampoIntegracao(chave: 'usuario', label: 'Usuário', tipo: CampoIntegracaoTipo.texto),
        CampoIntegracao(chave: 'senha', label: 'Senha', tipo: CampoIntegracaoTipo.senha),
        CampoIntegracao(chave: 'endpoint_emissao', label: 'Endpoint de emissão', tipo: CampoIntegracaoTipo.texto),
        CampoIntegracao(chave: 'endpoint_consulta', label: 'Endpoint de consulta', tipo: CampoIntegracaoTipo.texto),
        CampoIntegracao(chave: 'endpoint_cancelamento', label: 'Endpoint de cancelamento', tipo: CampoIntegracaoTipo.texto),
        CampoIntegracao(chave: 'endpoint_inutilizacao', label: 'Endpoint de inutilização', tipo: CampoIntegracaoTipo.texto),
        CampoIntegracao(chave: 'endpoint_webhook', label: 'Endpoint de webhook', tipo: CampoIntegracaoTipo.texto),
        CampoIntegracao(chave: 'status', label: 'Status', tipo: CampoIntegracaoTipo.selecao, opcoes: ['Ativo', 'Inativo']),
      ],
    ),
  ];
}

class CampoIntegracao {
  final String chave;
  final String label;
  final CampoIntegracaoTipo tipo;
  final List<String> opcoes;

  const CampoIntegracao({
    required this.chave,
    required this.label,
    this.tipo = CampoIntegracaoTipo.texto,
    this.opcoes = const [],
  });
}

enum CampoIntegracaoTipo { texto, senha, selecao }

/// Provedor e seus dados de configuração para exibição.
enum ProvedorFiscal {
  focusNfe,
  nuvemFiscal,
  plugNotas,
  webmaniaBr,
  enotas,
  arquivei,
  personalizado;

  String get nome {
    switch (this) {
      case ProvedorFiscal.focusNfe:
        return 'Focus NFe';
      case ProvedorFiscal.nuvemFiscal:
        return 'Nuvem Fiscal';
      case ProvedorFiscal.plugNotas:
        return 'PlugNotas / TecnoSpeed';
      case ProvedorFiscal.webmaniaBr:
        return 'WebmaniaBR';
      case ProvedorFiscal.enotas:
        return 'Enotas';
      case ProvedorFiscal.arquivei:
        return 'Arquivei';
      case ProvedorFiscal.personalizado:
        return 'Outro / Conexão personalizada';
    }
  }

  String get descricao {
    switch (this) {
      case ProvedorFiscal.focusNfe:
        return 'API fiscal para emissão de NF-e, NFC-e, NFS-e, CT-e e MDF-e.';
      case ProvedorFiscal.nuvemFiscal:
        return 'API REST para automação comercial e documentos fiscais.';
      case ProvedorFiscal.plugNotas:
        return 'API para emissão de NF-e, NFC-e e NFS-e.';
      case ProvedorFiscal.webmaniaBr:
        return 'API REST para emissão de NF-e e NFC-e.';
      case ProvedorFiscal.enotas:
        return 'Plataforma para emissão de notas fiscais de serviço.';
      case ProvedorFiscal.arquivei:
        return 'Consulta, armazenamento e gestão de documentos fiscais.';
      case ProvedorFiscal.personalizado:
        return 'Configure manualmente qualquer outro provedor fiscal.';
    }
  }

  String get providerId {
    switch (this) {
      case ProvedorFiscal.focusNfe:
        return 'focus_nfe';
      case ProvedorFiscal.nuvemFiscal:
        return 'nuvem_fiscal';
      case ProvedorFiscal.plugNotas:
        return 'plug_notas';
      case ProvedorFiscal.webmaniaBr:
        return 'webmania_br';
      case ProvedorFiscal.enotas:
        return 'enotas';
      case ProvedorFiscal.arquivei:
        return 'arquivei';
      case ProvedorFiscal.personalizado:
        return 'personalizado';
    }
  }
}
