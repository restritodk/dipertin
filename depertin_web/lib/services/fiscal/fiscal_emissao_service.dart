import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../models/cliente_assinatura_model.dart';
import '../../models/fiscal_document_model.dart';
import '../../models/store_fiscal_settings_model.dart';
import '../lojista_integracao_service.dart';
import '../fiscal_integrations_service.dart';
import 'fiscal_payload.dart';
import 'fiscal_provider.dart';
import 'fiscal_provider_service.dart';
import 'fiscal_validator.dart';
import 'fiscal_xml_builder.dart';
import 'fiscal_series_service.dart';
import 'fiscal_contingencia_service.dart';
import 'fiscal_erro_translator.dart';
import 'fiscal_audit_service.dart';
import 'fiscal_cancelamento_service.dart';
import 'fiscal_carta_correcao_service.dart';
import 'fiscal_inutilizacao_service.dart';

/// Resultado completo de uma operação de emissão fiscal.
class FiscalEmissaoResult {
  const FiscalEmissaoResult({
    required this.sucesso,
    this.chaveAcesso,
    this.protocolo,
    this.numero,
    this.serie,
    this.xmlGerado,
    this.xmlUrl,
    this.pdfUrl,
    this.statusFinal,
    this.mensagem,
    this.erro,
    this.errosValidacao = const [],
    this.avisosValidacao = const [],
    this.documentoId,
    this.providerResponse,
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
  final String? xmlGerado;
  final String? xmlUrl;
  final String? pdfUrl;
  final String? statusFinal;
  final String? mensagem;
  final String? erro;
  final List<ValidationError> errosValidacao;
  final List<ValidationWarning> avisosValidacao;
  final String? documentoId;
  final String? providerResponse;
  final String? codigoRejeicao;

  // ─── Campos estruturados de erro ───
  final int? focusStatusCode;
  final String? focusResponse;
  final String? sefazCode;
  final String? sefazMessage;
  final List<String> validationErrors;

  static const pendente = FiscalEmissaoResult(sucesso: false);

  FiscalProviderResult toProviderResult() => FiscalProviderResult(
        sucesso: sucesso,
        chaveAcesso: chaveAcesso,
        protocolo: protocolo,
        numero: numero,
        serie: serie,
        xmlUrl: xmlUrl,
        pdfUrl: pdfUrl,
        mensagem: mensagem,
        erro: erro,
        statusEnvio: statusFinal ?? 'pendente',
        providerResponse: providerResponse,
        codigoRejeicao: codigoRejeicao,
        focusStatusCode: focusStatusCode,
        focusResponse: focusResponse,
        sefazCode: sefazCode,
        sefazMessage: sefazMessage,
        validationErrors: validationErrors,
      );
}

/// Orquestra o fluxo de emissão fiscal com validação + XML + API externa.
class FiscalEmissaoService {
  FiscalEmissaoService._();

  static final FiscalEmissaoService _instance = FiscalEmissaoService._();
  static FiscalEmissaoService get instance => _instance;

  final FiscalProviderService _providerService = FiscalProviderService.instance;

  /// Emite uma NF-e com validação completa, geração de XML e envio ao provedor.
  Future<FiscalEmissaoResult> emitirNotaCompleta({
    required String lojaId,
    required FiscalPayload payload,
    bool homologacao = false,
    bool emitirNfce = false,
    String? integrationId,
    Map<String, dynamic>? storeSettingsData,
  }) async {
    try {
      // ─── 1. Validar ───
      final validacao = FiscalValidator.validarParaEmissao(payload);
      if (!validacao.valido) {
        return FiscalEmissaoResult(
          sucesso: false,
          erro: 'Erros de validação: ${validacao.erros.length} campo(s) com problema',
          errosValidacao: validacao.erros,
          avisosValidacao: validacao.avisos,
        );
      }

      // ─── 2. Config da loja — SEMPRE QUERY FRESCA primeiro, depois fallback para cache ───
      // Estratégia: tenta query Firestore primeiro. Se falhar e storeSettingsData tiver dados, usa como fallback.
      StoreFiscalSettingsModel? storeSettings;
      String? origemConfig;

      // 2a. Tenta query FRESCA no Firestore
      try {
        storeSettings = await FiscalIntegrationsService.buscarSettingsPorStore(lojaId);
        if (storeSettings != null && storeSettings.companyTaxData != null && storeSettings.companyTaxData!.isNotEmpty) {
          origemConfig = 'FIRESTORE_QUERY_FRESCA';
          debugPrint('[FiscalEmissaoService] Config carregada via query FRESCA do Firestore');
        } else {
          storeSettings = null; // força fallback
        }
      } catch (e) {
        debugPrint('[FiscalEmissaoService] Erro ao buscar settings via Firestore: $e');
        storeSettings = null;
      }

      // 2b. Fallback: se query Firestore não achou company_tax_data, usa storeSettingsData do caller
      if (storeSettings == null && storeSettingsData != null) {
        storeSettings = _settingsDoMap(storeSettingsData);
        if (storeSettings.companyTaxData != null && storeSettings.companyTaxData!.isNotEmpty) {
          origemConfig = 'CALLER_STORE_SETTINGS_DATA';
          debugPrint('[FiscalEmissaoService] Config carregada via storeSettingsData do caller (fallback)');
        } else {
          storeSettings = null;
        }
      }

      // 2c. Log diagnóstico detalhado
      debugPrint('[FiscalEmissaoService] ═══ DIAGNÓSTICO CONFIG FISCAL ═══');
      debugPrint('[FiscalEmissaoService] lojaId=$lojaId');
      debugPrint('[FiscalEmissaoService] integrationId=$integrationId');
      debugPrint('[FiscalEmissaoService] origemConfig=$origemConfig');
      debugPrint('[FiscalEmissaoService] storeSettings encontrado=${storeSettings != null}');
      if (storeSettings != null) {
        debugPrint('[FiscalEmissaoService] storeSettings.integrationId="${storeSettings.integrationId}"');
        debugPrint('[FiscalEmissaoService] storeSettings.companyTaxData presente=${storeSettings.companyTaxData != null && storeSettings.companyTaxData!.isNotEmpty}');
        debugPrint('[FiscalEmissaoService] storeSettings.companyTaxData keys=${storeSettings.companyTaxData?.keys.join(', ') ?? '(null)'}');
        final tax = storeSettings.companyTaxData ?? {};
        debugPrint('[FiscalEmissaoService] razao_social="${tax['razao_social'] ?? tax['razaoSocial'] ?? tax['nome'] ?? '(vazio)'}"');
        debugPrint('[FiscalEmissaoService] cnpj="${tax['cnpj'] ?? '(vazio)'}"');
        debugPrint('[FiscalEmissaoService] ie="${tax['ie'] ?? tax['inscricao_estadual'] ?? '(vazio)'}"');
        debugPrint('[FiscalEmissaoService] logradouro="${tax['logradouro'] ?? tax['endereco_logradouro'] ?? '(vazio)'}"');
        debugPrint('[FiscalEmissaoService] numero="${tax['numero'] ?? tax['endereco_numero'] ?? '(vazio)'}"');
        debugPrint('[FiscalEmissaoService] bairro="${tax['bairro'] ?? tax['endereco_bairro'] ?? '(vazio)'}"');
        debugPrint('[FiscalEmissaoService] cidade="${tax['cidade'] ?? tax['endereco_cidade'] ?? '(vazio)'}"');
        debugPrint('[FiscalEmissaoService] uf="${tax['uf'] ?? tax['endereco_uf'] ?? '(vazio)'}"');
        debugPrint('[FiscalEmissaoService] cep="${tax['cep'] ?? tax['endereco_cep'] ?? '(vazio)'}"');
        debugPrint('[FiscalEmissaoService] crt="${tax['crt'] ?? tax['regime_tributario_codigo'] ?? '(vazio)'}"');
        debugPrint('[FiscalEmissaoService] regime_tributario="${tax['regime_tributario'] ?? '(vazio)'}"');
        debugPrint('[FiscalEmissaoService] cnae="${tax['cnae'] ?? '(vazio)'}"');
        debugPrint('[FiscalEmissaoService] codigo_cidade="${tax['codigo_cidade'] ?? tax['ibge_cidade'] ?? '(vazio)'}"');
      } else {
        debugPrint('[FiscalEmissaoService] storeSettings NULO. storeSettingsData presente=${storeSettingsData != null}');
        if (storeSettingsData != null) {
          debugPrint('[FiscalEmissaoService] storeSettingsData keys=${storeSettingsData.keys.join(', ')}');
          debugPrint('[FiscalEmissaoService] company_tax_data em storeSettingsData=${storeSettingsData['company_tax_data'] != null}');
        }
      }
      debugPrint('[FiscalEmissaoService] ════════════════════════════════');

      if (storeSettings == null) {
        return FiscalEmissaoResult(sucesso: false, erro: 'Loja sem configuração fiscal. Verifique se os dados fiscais foram cadastrados no Painel Admin.', errosValidacao: validacao.erros, avisosValidacao: validacao.avisos);
      }

      // ─── Extrai emitente e valida ───
      final taxData = storeSettings.companyTaxData ?? {};
      final emitente = _extrairEmitente(taxData);
      if (emitente == null) {
        debugPrint('[FiscalEmissaoService] ⚠️ _extrairEmitente retornou NULL');
        debugPrint('[FiscalEmissaoService] taxData keys=${taxData.keys.join(', ')}');
        debugPrint('[FiscalEmissaoService] razao_social="${_str(taxData, ['razao_social', 'razaoSocial', 'nome'])}"');
        debugPrint('[FiscalEmissaoService] cnpj (digitos)="${_digitos(_str(taxData, ['cnpj', 'cpf_cnpj']))}"');
        debugPrint('[FiscalEmissaoService] ie="${_str(taxData, ['ie', 'inscricao_estadual'])}"');
        return FiscalEmissaoResult(sucesso: false, erro: 'CNPJ/IE do emitente não configurados. Verifique company_tax_data no Firestore.');
      }

      // ─── 3. Integracao ───
      Map<String, dynamic>? integrationDoc =
          await _buscarIntegracao(storeSettings.integrationId);

      // Fallback: se não achou em fiscal_integrations (lojista não tem permissão),
      // usa integration_data desnormalizado em store_fiscal_settings
      if (integrationDoc == null && storeSettingsData != null) {
        final integrationData = storeSettingsData['integration_data']
            as Map<String, dynamic>?;
        if (integrationData != null && integrationData.isNotEmpty) {
          debugPrint('[FiscalEmissaoService] Usando integration_data '
              'desnormalizado: provider=${integrationData['provider']}');
          integrationDoc = integrationData;
        }
      }

      if (integrationDoc == null) {
        debugPrint('[FiscalEmissaoService] Integração NÃO ENCONTRADA para '
            'integrationId="${storeSettings.integrationId}"');
        return FiscalEmissaoResult(sucesso: false, erro: 'Integração fiscal não encontrada.', errosValidacao: validacao.erros, avisosValidacao: validacao.avisos);
      }
      debugPrint('[FiscalEmissaoService] Integração ENCONTRADA: '
          'provider=${integrationDoc['provider']}, '
          'provider_name=${integrationDoc['provider_name']}');

      // ─── 4. Provider ───
      final config = _providerService.extrairConfig(
        integrationDoc,
        integrationId: storeSettings.integrationId,
      );
      config['store_id'] = lojaId;

      // Passa lojista_integration_id e certificate_id para o provider (Focus NFe)
      final lojistaIntegId = storeSettingsData?['lojista_integration_id'] as String?;
      if (lojistaIntegId != null && lojistaIntegId.isNotEmpty) {
        config['lojista_integration_id'] = lojistaIntegId;
      }
      final certId = storeSettingsData?['certificate_id'] as String?;
      if (certId != null && certId.isNotEmpty) {
        config['certificate_id'] = certId;
      }

      // Passa ie_isento (Inscrição Estadual dispensada) da company_tax_data
      final comTaxData = storeSettingsData?['company_tax_data'] as Map<String, dynamic>?;
      if (comTaxData != null && comTaxData['ie_isento'] == true) {
        config['ie_isento'] = true;
      }

      final provider = _providerService.resolverDeIntegracao(integrationDoc);
      if (provider == null) {
        return FiscalEmissaoResult(sucesso: false, erro: 'Provedor fiscal não encontrado.', errosValidacao: validacao.erros, avisosValidacao: validacao.avisos);
      }

      // ─── 5. Limite ───
      final limiteOk = await _verificarLimiteEmissao(lojaId);
      if (!limiteOk) {
        return FiscalEmissaoResult(sucesso: false, erro: 'Limite mensal atingido.', errosValidacao: validacao.erros, avisosValidacao: validacao.avisos);
      }

      // ─── 6. Contingencia ───
      final emContingencia = await FiscalContingenciaService.estaEmContingencia(lojaId);

      // ─── 7. Numeracao ───
      String serieUsar = payload.serie ?? '1';
      int numeroUsar = 0;
      if (!emContingencia) {
        try {
          final n = await FiscalSeriesService.reservarProximoNumero(
            storeId: lojaId,
            documentType: payload.tipoDocumento.codigo,
            serie: serieUsar,
            ambiente: homologacao ? 'sandbox' : 'production',
          );
          serieUsar = n.serie;
          numeroUsar = n.numero;
        } catch (_) {}
      }

      // ─── 8. XML ───
      final p2 = FiscalPayload(
        tipoDocumento: payload.tipoDocumento, emitente: payload.emitente,
        destinatario: payload.destinatario, itens: payload.itens,
        totais: payload.totais, pagamento: payload.pagamento,
        serie: serieUsar, numero: numeroUsar > 0 ? numeroUsar.toString() : null,
        naturezaOperacao: payload.naturezaOperacao, cfop: payload.cfop,
        finalidade: payload.finalidade, tipoOperacao: payload.tipoOperacao,
        indicadorPresenca: payload.indicadorPresenca,
        informacoesAdicionais: payload.informacoesAdicionais,
        pedidoId: payload.pedidoId, vendaId: payload.vendaId,
        clienteId: payload.clienteId, configuracoesExtras: payload.configuracoesExtras,
      );
      final xmlGerado = FiscalXmlBuilder.gerarXmlNFeApenas(payload: p2, homologacao: homologacao, emitirNfce: emitirNfce);

      // ─── 9. Config final ───
      final cfg = Map<String, dynamic>.from(config);
      // Força o ambiente (homologacao/producao) conforme a flag passada
      cfg['environment'] = homologacao ? 'sandbox' : 'producao';

      // ─── 10. Emitir via Cloud Function ───
      // A chamada à API externa é feita pelo backend (Cloud Function fiscalEmitirNFe).
      // O token/api_key nunca transita no frontend.
      final resultado = await provider.emitirNota(p2, cfg);

      // ─── 11. Persistir ───
      FiscalDocumentModel? docModel;
      String? msgFinal;
      String? codRej;
      ({String titulo, String descricao}) traducao = (
        titulo: resultado.mensagem ?? (resultado.sucesso ? 'NF-e emitida' : 'Erro'),
        descricao: resultado.erro ?? '',
      );
      if (!resultado.sucesso) {
        codRej = FiscalErroTranslator.extrairCodigoRejeicao(resultado.erro);
        traducao = FiscalErroTranslator.traduzir(codRej, mensagemOriginal: resultado.erro);
      }

      if (resultado.sucesso) {
        if (!emContingencia && numeroUsar > 0) {
          try {
            await FiscalSeriesService.confirmarNumeracao(
              storeId: lojaId, numero: int.tryParse(resultado.numero ?? '') ?? numeroUsar,
              documentType: payload.tipoDocumento.codigo, serie: resultado.serie ?? serieUsar,
            );
          } catch (e) {
            debugPrint('[FiscalEmissaoService] Erro ao confirmar numeração: $e');
          }
        }
        docModel = FiscalDocumentModel(
          id: '', storeId: lojaId, customerId: p2.clienteId,
          documentType: p2.tipoDocumento.codigo, provider: provider.id,
          status: emContingencia ? StatusFiscal.contingencia : StatusFiscal.autorizada,
          accessKey: resultado.chaveAcesso, protocol: resultado.protocolo,
          number: resultado.numero ?? (numeroUsar > 0 ? numeroUsar.toString() : null),
          series: resultado.serie ?? serieUsar,
          xmlUrl: resultado.xmlUrl, pdfUrl: resultado.pdfUrl,
          providerResponse: resultado.providerResponse,
          emContingencia: emContingencia, motivoContingencia: emContingencia ? 'SEFAZ offline' : null,
          issuedAt: Timestamp.now(), createdAt: Timestamp.now(), updatedAt: Timestamp.now(),
        );
        try {
          // FONTE ÚNICA DE VERDADE: fiscal_documents
          // NOTA: O caller (ex: FiscalEmissaoModal) é responsável por atualizar
          // users/{storeId}/notas_fiscais com os dados pós-emissão.
          await FiscalIntegrationsService.registrarDocumento(docModel);
        } catch (e) {
          debugPrint('[FiscalEmissaoService] Erro ao salvar documento em fiscal_documents: $e');
        }
        try {
          await _atualizarContagemEmissao(lojaId);
        } catch (e) {
          debugPrint('[FiscalEmissaoService] Erro ao atualizar contagem: $e');
        }
        msgFinal = 'NF-e emitida${emContingencia ? " em contingência" : ""}.';
        FiscalAuditService.registrar(lojaId: lojaId, acao: FiscalAuditService.acaoEmissao,
          descricao: 'NF-e ${resultado.numero ?? ""} emitida${emContingencia ? " em contingência" : ""}',
          documentoId: docModel.id, chaveAcesso: resultado.chaveAcesso, provedor: provider.id);
      } else {
        docModel = FiscalDocumentModel(
          id: '', storeId: lojaId, customerId: p2.clienteId,
          documentType: p2.tipoDocumento.codigo, provider: provider.id,
          status: StatusFiscal.rejeitada, accessKey: resultado.chaveAcesso,
          number: numeroUsar > 0 ? numeroUsar.toString() : null, series: serieUsar,
          rejectionReason: resultado.erro, rejectionCode: codRej,
          providerResponse: resultado.providerResponse,
          createdAt: Timestamp.now(), updatedAt: Timestamp.now(),
        );
        try {
          await FiscalIntegrationsService.registrarDocumento(docModel);
          // NOTA: o modal (FiscalEmissaoModal) já atualiza users/{storeId}/notas_fiscais
        } catch (e) {
          debugPrint('[FiscalEmissaoService] Erro ao salvar documento rejeitado: $e');
        }
        msgFinal = traducao.titulo;
        FiscalAuditService.registrar(lojaId: lojaId, acao: 'emissao_rejeitada',
          descricao: 'Rejeitada: ${traducao.titulo}', documentoId: docModel.id, provedor: provider.id);
      }

      return FiscalEmissaoResult(
        sucesso: resultado.sucesso, chaveAcesso: resultado.chaveAcesso,
        protocolo: resultado.protocolo,
        numero: resultado.numero ?? (numeroUsar > 0 ? numeroUsar.toString() : null),
        serie: resultado.serie ?? serieUsar, xmlGerado: xmlGerado,
        xmlUrl: resultado.xmlUrl, pdfUrl: resultado.pdfUrl,
        statusFinal: emContingencia ? StatusFiscal.contingencia
            : resultado.sucesso ? StatusFiscal.autorizada : StatusFiscal.rejeitada,
        mensagem: msgFinal, erro: resultado.erro,
        errosValidacao: validacao.erros, avisosValidacao: validacao.avisos,
        documentoId: docModel.id.isNotEmpty ? docModel.id : null,
        providerResponse: resultado.providerResponse, codigoRejeicao: codRej,
        // ─── Campos estruturados de erro ───
        focusStatusCode: resultado.focusStatusCode,
        focusResponse: resultado.focusResponse,
        sefazCode: resultado.sefazCode,
        sefazMessage: resultado.sefazMessage,
        validationErrors: resultado.validationErrors,
      );
    } catch (e) {
      return FiscalEmissaoResult(sucesso: false, erro: 'Erro interno na emissão: $e');
    }
  }

  /// Emite NF-e de assinatura a partir dos dados do [ClienteAssinaturaModel].
  Future<FiscalEmissaoResult> emitirNotaAssinatura({
    required ClienteAssinaturaModel cliente,
    required String tipoDocumento,
    String? valorPersonalizado,
  }) async {
    try {
      final storeId = cliente.storeId;
      final valor = valorPersonalizado != null
          ? double.tryParse(valorPersonalizado) ?? cliente.monthlyAmount
          : cliente.monthlyAmount;

      // ─── 1. Dados fiscais da loja ───
      // Busca FRESCA no Firestore (fonte única de verdade)
      final settingsSnap = await FirebaseFirestore.instance
          .collection('store_fiscal_settings')
          .where('store_id', isEqualTo: storeId)
          .limit(1)
          .get();
      final settingsData = settingsSnap.docs.isNotEmpty ? settingsSnap.docs.first.data() : null;

      // Log detalhado do que foi encontrado
      debugPrint('[FiscalEmissaoService] emitirNotaAssinatura ═══ DIAGNÓSTICO ═══');
      debugPrint('[FiscalEmissaoService] storeId=$storeId');
      debugPrint('[FiscalEmissaoService] store_fiscal_settings encontrado=${settingsData != null}');
      if (settingsData != null) {
        debugPrint('[FiscalEmissaoService] settings keys=${settingsData.keys.join(', ')}');
        debugPrint('[FiscalEmissaoService] company_tax_data presente=${settingsData.containsKey('company_tax_data')}');
        final rawTax = settingsData['company_tax_data'];
        debugPrint('[FiscalEmissaoService] company_tax_data tipo=${rawTax.runtimeType}');
      }
      debugPrint('[FiscalEmissaoService] ════════════════════════════════════');

      // Estratégia: tenta company_tax_data primeiro, depois top-level fields, depois fallback
      Map<String, dynamic> taxData = {};
      if (settingsData != null) {
        final rawTax = settingsData['company_tax_data'];
        if (rawTax is Map<String, dynamic> && rawTax.isNotEmpty) {
          taxData = rawTax;
          debugPrint('[FiscalEmissaoService] Usando company_tax_data (submap)');
        } else {
          // Fallback: tenta campos no top-level do documento
          final topLevelTax = <String, dynamic>{};
          for (final chave in ['cnpj', 'razao_social', 'nome_fantasia', 'ie',
              'inscricao_estadual', 'regime_tributario', 'cnae', 'crt',
              'logradouro', 'numero', 'bairro', 'cidade', 'uf', 'cep',
              'codigo_cidade', 'telefone', 'email_fiscal']) {
            if (settingsData[chave] is String && (settingsData[chave] as String).isNotEmpty) {
              topLevelTax[chave] = settingsData[chave];
            }
          }
          if (topLevelTax.isNotEmpty) {
            taxData = topLevelTax;
            debugPrint('[FiscalEmissaoService] Fallback: usando campos top-level. Encontrados: ${topLevelTax.keys.join(', ')}');
          } else {
            debugPrint('[FiscalEmissaoService] company_tax_data VAZIO e sem campos top-level. Dados completos: $settingsData');
          }
        }
      }

      if (taxData.isEmpty) {
        return FiscalEmissaoResult(sucesso: false,
          erro: 'Dados fiscais não configurados. Verifique se a loja tem company_tax_data em store_fiscal_settings.');
      }

      final emit = _extrairEmitente(taxData);
      if (emit == null) {
        debugPrint('[FiscalEmissaoService] ⚠️ emitirNotaAssinatura: _extrairEmitente retornou NULL');
        debugPrint('[FiscalEmissaoService] taxData keys=${taxData.keys.join(', ')}');
        debugPrint('[FiscalEmissaoService] razao_social="${taxData['razao_social'] ?? taxData['razaoSocial'] ?? taxData['nome'] ?? '(vazio)'}"');
        debugPrint('[FiscalEmissaoService] cnpj="${taxData['cnpj'] ?? '(vazio)'}"');
        debugPrint('[FiscalEmissaoService] ie="${taxData['ie'] ?? taxData['inscricao_estadual'] ?? '(vazio)'}"');
        return FiscalEmissaoResult(sucesso: false,
          erro: 'CNPJ/IE do emitente não configurados. Verifique company_tax_data no Firestore (campos: cnpj, razao_social, ie).');
      }

      // ─── 2. Destinatario ───
      final dest = FiscalDestinatario(
        nome: cliente.ownerName,
        cpfCnpj: _digitos(cliente.cpfCnpj ?? ''),
        ie: null,
        email: cliente.email,
        telefone: _digitos(cliente.phone),
        logradouro: cliente.addressStreet.isNotEmpty ? cliente.addressStreet : 'Nao informado',
        numero: 'S/N',
        complemento: null,
        bairro: 'Centro',
        cidade: cliente.addressCity.isNotEmpty ? cliente.addressCity : 'Nao informado',
        uf: cliente.addressState.isNotEmpty ? cliente.addressState : 'MT',
        cep: _digitos(''),
      );

      // ─── 3. Item ───
      final item = FiscalItem(
        descricao: 'Assinatura ${cliente.planName}',
        quantidade: 1,
        valorUnitario: valor,
        valorTotal: valor,
        ncm: '99999999',
        cfop: '5102',
        codigoProduto: 'ASS-${cliente.planId}',
        cstIcms: '40',
      );

      // ─── 4. Totais ───
      final totais = FiscalTotais(
        baseCalculoIcms: 0,
        valorIcms: 0,
        valorProdutos: valor,
        valorFrete: 0,
        valorDesconto: 0,
        valorTotal: valor,
      );

      // ─── 5. Pagamento ───
      final pag = FiscalPagamento(
        formaPagamento: 'outros',
        valorPago: valor,
      );

      // ─── 6. Payload ───
      final payload = FiscalPayload(
        tipoDocumento: TipoDocumentoFiscal.fromCodigo(tipoDocumento),
        emitente: emit,
        destinatario: dest,
        itens: [item],
        totais: totais,
        pagamento: pag,
        naturezaOperacao: 'Venda de assinatura',
        cfop: '5102',
        informacoesAdicionais: 'Assinatura ${cliente.planName} - DiPertin',
        clienteId: cliente.id,
      );

      final nfeEnv = settingsData?['nfe_settings'] as Map<String, dynamic>?;
      final envStr = nfeEnv?['environment'] as String? ?? 'sandbox';
      final integracaoId = settingsData?['integration_id'] as String? ?? '';

      final resultado = await emitirNotaCompleta(
        lojaId: storeId, payload: payload,
        homologacao: envStr == 'sandbox',
        emitirNfce: tipoDocumento == 'nfce',
        integrationId: integracaoId,
        storeSettingsData: settingsData,
      );

      // ─── Pós-emissão: persiste em users/{storeId}/notas_fiscais ───
      // O emitirNotaCompleta salva em fiscal_documents, mas o módulo do lojista
      // também lê de users/{storeId}/notas_fiscais para manter compatibilidade.
      if (resultado.sucesso) {
        try {
          await FirebaseFirestore.instance
              .collection('users')
              .doc(storeId)
              .collection('notas_fiscais')
              .add({
            'store_id': storeId,
            'situacao': 'emitida',
            'numero_nfe': resultado.numero ?? '',
            'chave_acesso': resultado.chaveAcesso ?? '',
            'protocolo': resultado.protocolo ?? '',
            'serie': resultado.serie ?? '',
            'data_emissao': Timestamp.now(),
            'data_criacao': Timestamp.now(),
            'emitente_cnpj': emit.cnpj,
            'emitente_razao': emit.razaoSocial,
            'cliente_nome': dest.nome,
            'cliente_cpf_cnpj': dest.cpfCnpj,
            'valor_total': payload.totais.valorTotal,
            'logs': [{
              'evento': 'emitida',
              'data': Timestamp.now(),
              'descricao': 'NF-e emitida via assinatura — Chave: ${resultado.chaveAcesso ?? "N/A"}',
            }],
          });
        } catch (e) {
          debugPrint('[FiscalEmissaoService] Erro ao salvar em users/{storeId}/notas_fiscais (assinatura): $e');
        }
      }

      return resultado;
    } catch (e) {
      return FiscalEmissaoResult(sucesso: false, erro: 'Erro ao preparar nota de assinatura: $e');
    }
  }

  /// Cancela NF-e.
  Future<FiscalEmissaoResult> cancelarNota({
    required String storeId, required String fiscalDocumentId,
    required String accessKey, required String protocol,
    required String justificativa,
  }) async {
    final r = await FiscalCancelamentoService.cancelarNota(
      storeId: storeId, fiscalDocumentId: fiscalDocumentId,
      justificativa: justificativa, accessKey: accessKey, protocol: protocol,
    );
    return FiscalEmissaoResult(sucesso: r.sucesso, chaveAcesso: r.chaveAcesso,
      protocolo: r.protocolo, numero: r.numero, erro: r.erro, mensagem: r.mensagem,
      statusFinal: r.sucesso ? StatusFiscal.cancelada : StatusFiscal.rejeitada,
      providerResponse: r.providerResponse);
  }

  /// Envia CC-e.
  Future<FiscalEmissaoResult> enviarCartaCorrecao({
    required String storeId, required String fiscalDocumentId,
    required String textoCorrecao,
  }) async {
    final r = await FiscalCartaCorrecaoService.enviarCartaCorrecao(
      storeId: storeId, fiscalDocumentId: fiscalDocumentId, textoCorrecao: textoCorrecao,
    );
    return FiscalEmissaoResult(sucesso: r.sucesso, chaveAcesso: r.chaveAcesso,
      protocolo: r.protocolo, erro: r.erro, mensagem: r.mensagem,
      statusFinal: r.sucesso ? StatusFiscal.ccEnviada : StatusFiscal.rejeitada,
      providerResponse: r.providerResponse);
  }

  /// Inutiliza numeracao.
  Future<FiscalEmissaoResult> inutilizarNumeracao({
    required String storeId, required String serie,
    required int numeroInicial, required int numeroFinal,
    required String justificativa,
  }) async {
    final r = await FiscalInutilizacaoService.inutilizar(
      storeId: storeId, serie: serie, numeroInicial: numeroInicial,
      numeroFinal: numeroFinal, justificativa: justificativa,
    );
    return FiscalEmissaoResult(sucesso: r.sucesso, chaveAcesso: r.chaveAcesso,
      protocolo: r.protocolo, erro: r.erro, mensagem: r.mensagem,
      statusFinal: r.sucesso ? StatusFiscal.numeracaoInutilizada : StatusFiscal.rejeitada,
      providerResponse: r.providerResponse);
  }

  static ValidationResult validarDados(FiscalPayload payload) =>
      FiscalValidator.validarParaEmissao(payload);

  // ─── Helpers privados ───

  FiscalEmitente? _extrairEmitente(Map<String, dynamic> d) {
    final razao = _str(d, ['razao_social', 'razaoSocial', 'nome', 'name']);
    final cnpj = _digitos(_str(d, ['cnpj', 'cpf_cnpj']));
    final ie = _str(d, ['ie', 'inscricao_estadual']);
    if (razao.isEmpty || cnpj.isEmpty || ie.isEmpty) return null;
    return FiscalEmitente(
      razaoSocial: razao, nomeFantasia: _str(d, ['nome_fantasia', 'nomeFantasia', 'nome', 'name']),
      cnpj: cnpj, ie: ie,
      im: _strOrNull(d, ['im', 'inscricao_municipal']),
      crt: _strOrNull(d, ['crt', 'regime_tributario_codigo']),
      regimeTributario: _strOrNull(d, ['regime_tributario']),
      logradouro: _str(d, ['logradouro', 'endereco_logradouro']),
      numero: _str(d, ['numero', 'endereco_numero']),
      complemento: _strOrNull(d, ['complemento', 'endereco_complemento']),
      bairro: _str(d, ['bairro', 'endereco_bairro']),
      cidade: _str(d, ['cidade', 'endereco_cidade', 'municipio']),
      uf: _str(d, ['uf', 'endereco_uf', 'estado']),
      cep: _digitos(_str(d, ['cep', 'endereco_cep'])),
      telefone: _strOrNull(d, ['telefone', 'celular', 'phone']),
      emailFiscal: _strOrNull(d, ['email_fiscal', 'email']),
      codigoCidade: _strOrNull(d, ['codigo_cidade', 'codigoCidade', 'ibge_cidade']),
    );
  }

  /// Obtém configuração fiscal da loja com estratégia de fallback.
  ///
  /// 1. Tenta query FRESCA no Firestore (fonte única de verdade).
  /// 2. Fallback: usa [storeSettingsData] se passado e company_tax_data presente.
  /// 3. NUNCA usa cache sem verificar se tem dados válidos.
  // ignore: unused_element
  Future<StoreFiscalSettingsModel?> _obterConfiguracaoLoja(
    String lojaId, String? integrationId, [Map<String, dynamic>? storeSettingsData,
  ]) async {
    // 1. Query fresca no Firestore
    try {
      final fresh = await FiscalIntegrationsService.buscarSettingsPorStore(lojaId);
      if (fresh != null && fresh.companyTaxData != null && fresh.companyTaxData!.isNotEmpty) {
        debugPrint('[FiscalEmissaoService] _obterConfiguracaoLoja: DADOS FRESCOS do Firestore');
        return fresh;
      }
    } catch (_) {}

    // 2. Fallback para dados do caller
    if (storeSettingsData != null) {
      final fallback = _settingsDoMap(storeSettingsData);
      if (fallback.companyTaxData != null && fallback.companyTaxData!.isNotEmpty) {
        debugPrint('[FiscalEmissaoService] _obterConfiguracaoLoja: FALLBACK para dados do caller');
        return fallback;
      }
    }
    return null;
  }

  /// Constrói [StoreFiscalSettingsModel] diretamente de um Map sem fake DocSnapshot.
  StoreFiscalSettingsModel _settingsDoMap(Map<String, dynamic> data) {
    return StoreFiscalSettingsModel(
      id: data['id'] as String? ?? '',
      storeId: data['store_id'] as String? ?? '',
      integrationId: data['integration_id'] as String? ?? '',
      enableNfe: data['enable_nfe'] as bool? ?? false,
      enableNfce: data['enable_nfce'] as bool? ?? false,
      enableNfse: data['enable_nfse'] as bool? ?? false,
      companyTaxData: data['company_tax_data'] as Map<String, dynamic>?,
      certificateDataEncrypted: data['certificate_data_encrypted'] as String?,
      nfeSettings: data['nfe_settings'] as Map<String, dynamic>?,
      nfceSettings: data['nfce_settings'] as Map<String, dynamic>?,
      nfseSettings: data['nfse_settings'] as Map<String, dynamic>?,
      webhookUrl: data['webhook_url'] as String?,
      status: data['status'] as String? ?? 'active',
      createdAt: data['created_at'] as Timestamp?,
      updatedAt: data['updated_at'] as Timestamp?,
    );
  }

  Future<Map<String, dynamic>?> _buscarIntegracao(String integrationId) async {
    if (integrationId.isEmpty) return null;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('fiscal_integrations')
          .doc(integrationId)
          .get();
      if (doc.exists) return doc.data();
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<bool> _verificarLimiteEmissao(String storeId) async {
    try {
      final i = await LojistaIntegracaoService.buscarIntegracaoPorStore(storeId);
      return i != null && i.notasRestantes > 0;
    } catch (_) { return false; }
  }

  Future<void> _atualizarContagemEmissao(String storeId) async {
    await LojistaIntegracaoService.registrarEmissao(storeId);
  }

  String _str(Map<String, dynamic> d, List<String> chaves) {
    for (final c in chaves) { final v = d[c]; if (v is String && v.isNotEmpty) return v; }
    return '';
  }

  String? _strOrNull(Map<String, dynamic> d, List<String> chaves) {
    for (final c in chaves) { final v = d[c]; if (v is String && v.isNotEmpty) return v; }
    return null;
  }

  String _digitos(String s) => s.replaceAll(RegExp(r'\D'), '');
}
