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

      // 2c. Log diagnóstico sanitizado (sem CPF/CNPJ/e-mail completos)
      debugPrint('[FiscalEmissaoService] ═══ DIAGNÓSTICO CONFIG FISCAL ═══');
      debugPrint('[FiscalEmissaoService] lojaId=$lojaId');
      debugPrint('[FiscalEmissaoService] integrationId=$integrationId');
      debugPrint('[FiscalEmissaoService] origemConfig=$origemConfig');
      debugPrint('[FiscalEmissaoService] storeSettings encontrado=${storeSettings != null}');
      if (storeSettings != null) {
        debugPrint('[FiscalEmissaoService] storeSettings.integrationId="${storeSettings.integrationId}"');
        debugPrint('[FiscalEmissaoService] storeSettings.companyTaxData presente=${storeSettings.companyTaxData != null && storeSettings.companyTaxData!.isNotEmpty}');
        final tax = storeSettings.companyTaxData ?? {};
        debugPrint('[FiscalEmissaoService] razao_social presente=${_str(tax, ['razao_social', 'razaoSocial', 'nome']).isNotEmpty}');
        debugPrint('[FiscalEmissaoService] cnpj presente=${_str(tax, ['cnpj', 'cpf_cnpj']).isNotEmpty}');
        debugPrint('[FiscalEmissaoService] ie presente=${_str(tax, ['ie', 'inscricao_estadual']).isNotEmpty}');
        debugPrint('[FiscalEmissaoService] crt="${tax['crt'] ?? tax['regime_tributario_codigo'] ?? '(vazio)'}"');
        debugPrint('[FiscalEmissaoService] regime_tributario="${tax['regime_tributario'] ?? '(vazio)'}"');
        debugPrint('[FiscalEmissaoService] cnae presente=${_str(tax, ['cnae']).isNotEmpty}');
        debugPrint('[FiscalEmissaoService] codigo_cidade presente=${_str(tax, ['codigo_cidade', 'ibge_cidade']).isNotEmpty}');
        debugPrint('[FiscalEmissaoService] logradouro presente=${_str(tax, ['logradouro', 'endereco_logradouro']).isNotEmpty}');
        debugPrint('[FiscalEmissaoService] cidade presente=${_str(tax, ['cidade', 'endereco_cidade', 'municipio']).isNotEmpty}');
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
      // Diagnóstico da configuração da loja
      final integId = storeSettings.integrationId;

      if (integId.isEmpty) {
        debugPrint('[FiscalEmissaoService] integration_id AUSENTE');
        return FiscalEmissaoResult(
          sucesso: false,
          erro: 'Loja sem integração fiscal vinculada. ' +
              'Solicite ao administrador que vincule uma integração.',
          errosValidacao: validacao.erros,
          avisosValidacao: validacao.avisos,
        );
      }

      final removidaEm = storeSettingsData?['integration_removida_em'];
      if (removidaEm != null) {
        debugPrint('[FiscalEmissaoService] integration_removida_em PRESENTE');
        return FiscalEmissaoResult(
          sucesso: false,
          erro: 'Integração fiscal removida. ' +
              'Solicite reparo do vínculo ou nova integração.',
          errosValidacao: validacao.erros,
          avisosValidacao: validacao.avisos,
        );
      }

      final integrationData = storeSettingsData?['integration_data'] as Map<String, dynamic>?;
      if (integrationData == null || integrationData.isEmpty) {
        debugPrint('[FiscalEmissaoService] integration_data AUSENTE');
        return FiscalEmissaoResult(
          sucesso: false,
          erro: 'Dados da integração não propagados. ' +
              'Execute reparo do vínculo ou salve a integração novamente.',
          errosValidacao: validacao.erros,
          avisosValidacao: validacao.avisos,
        );
      }

      final providerStr = integrationData['provider'] as String?;
      if (providerStr == null || providerStr.isEmpty) {
        debugPrint('[FiscalEmissaoService] provider AUSENTE');
        return FiscalEmissaoResult(
          sucesso: false,
          erro: 'Provedor fiscal não configurado.',
          errosValidacao: validacao.erros,
          avisosValidacao: validacao.avisos,
        );
      }

      final integStatus = (integrationData['status'] as String? ?? '').toLowerCase().trim();
      if (integStatus == 'inactive') {
        debugPrint('[FiscalEmissaoService] Integração INATIVA');
        return FiscalEmissaoResult(
          sucesso: false,
          erro: 'Integração fiscal inativa. Ative-a no Painel Admin.',
          errosValidacao: validacao.erros,
          avisosValidacao: validacao.avisos,
        );
      }

      debugPrint('[FiscalEmissaoService] Integração OK: '
          'provider=$providerStr, status=$integStatus');

      // ─── 4. Provider ───
      final config = _providerService.extrairConfig(
        integrationData,
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
      final comTaxData =
          (storeSettingsData?['company_tax_data'] as Map<String, dynamic>?) ??
              storeSettings.companyTaxData;
      if (comTaxData != null &&
          (comTaxData['ie_isento'] == true ||
              resolverIeIsentoEmitente(comTaxData))) {
        config['ie_isento'] = true;
      } else if (payload.emitente.ieIsento) {
        config['ie_isento'] = true;
      }

      final provider = _providerService.resolverDeIntegracao(integrationData);
      if (provider == null) {
        return FiscalEmissaoResult(sucesso: false, erro: 'Provedor fiscal não encontrado.', errosValidacao: validacao.erros, avisosValidacao: validacao.avisos);
      }

      // ─── 5. Limite ───
      final limiteOk = await _verificarLimiteEmissao(lojaId);
      if (!limiteOk) {
        return FiscalEmissaoResult(
          sucesso: false,
          erro:
              'Você atingiu o limite de emissões do seu plano. Aguarde a renovação do plano ou faça um upgrade para continuar emitindo NF-e.',
          errosValidacao: validacao.erros,
          avisosValidacao: validacao.avisos,
        );
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

      // ─── 11. Persistência EXCLUSIVA pelo backend ───
      // Toda criação/atualização de fiscal_documents, fiscal_emission_operations,
      // saldo_notas e notificações é feita pela Cloud Function via Admin SDK.
      // O frontend NUNCA escreve diretamente nessas coleções.
      String? msgFinal;
      String? codRej;
      ({String titulo, String descricao}) traducao = (
        titulo: resultado.mensagem ?? (resultado.sucesso ? 'NF-e emitida' : 'Erro'),
        descricao: resultado.erro ?? '',
      );
      if (!resultado.sucesso) {
        codRej = resultado.sefazCode?.trim().isNotEmpty == true
            ? resultado.sefazCode!.trim()
            : FiscalErroTranslator.extrairCodigoRejeicao(
                [
                  resultado.erro,
                  resultado.sefazMessage,
                  resultado.mensagem,
                  ...resultado.validationErrors,
                  resultado.focusResponse,
                ].whereType<String>().join(' | '),
              );
        traducao = FiscalErroTranslator.traduzir(
          codRej,
          mensagemOriginal: resultado.sefazMessage ?? resultado.erro,
        );
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
        msgFinal = 'NF-e emitida${emContingencia ? " em contingência" : ""}.';
      } else {
        msgFinal = codRej != null
            ? 'Rejeição SEFAZ $codRej: ${traducao.titulo}'
            : traducao.titulo;
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
        // documentoId é gerado pelo backend (Admin SDK) — frontend não persiste mais
        documentoId: null,
        providerResponse: resultado.providerResponse, codigoRejeicao: codRej,
        // ─── Campos estruturados de erro ───
        focusStatusCode: resultado.focusStatusCode,
        focusResponse: resultado.focusResponse,
        sefazCode: resultado.sefazCode ?? codRej,
        sefazMessage: resultado.sefazMessage ??
            (codRej != null ? traducao.descricao : resultado.erro),
        validationErrors: () {
          final lista = <String>[...resultado.validationErrors];
          final codigo = codRej;
          if (codigo != null && codigo.isNotEmpty) {
            final msg = 'Rejeição SEFAZ $codigo: ${traducao.titulo}';
            if (!lista.any((e) => e.contains(codigo))) lista.insert(0, msg);
          } else if (lista.isEmpty && msgFinal != null) {
            lista.add(msgFinal);
          }
          return lista;
        }(),
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
            debugPrint('[FiscalEmissaoService] company_tax_data VAZIO e sem campos top-level. Dados presentes: keys=${settingsData.keys.join(', ')}');
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
    final ieIsento = resolverIeIsentoEmitente(d);
    if (razao.isEmpty || cnpj.isEmpty) return null;
    if (!ieIsento && ie.isEmpty) return null;
    return FiscalEmitente(
      razaoSocial: razao, nomeFantasia: _str(d, ['nome_fantasia', 'nomeFantasia', 'nome', 'name']),
      cnpj: cnpj, ie: ie, ieIsento: ieIsento,
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
  ///
  /// SEGURANÇA: certificate_data_encrypted não é mais lido de store_fiscal_settings.
  /// Certificado é buscado diretamente de fiscal_certificates quando necessário.
  StoreFiscalSettingsModel _settingsDoMap(Map<String, dynamic> data) {
    return StoreFiscalSettingsModel(
      id: data['id'] as String? ?? '',
      storeId: data['store_id'] as String? ?? '',
      integrationId: data['integration_id'] as String? ?? '',
      enableNfe: data['enable_nfe'] as bool? ?? false,
      enableNfce: data['enable_nfce'] as bool? ?? false,
      enableNfse: data['enable_nfse'] as bool? ?? false,
      companyTaxData: data['company_tax_data'] as Map<String, dynamic>?,
      // certificate_data_encrypted não é mais lido de store_fiscal_settings
      nfeSettings: data['nfe_settings'] as Map<String, dynamic>?,
      nfceSettings: data['nfce_settings'] as Map<String, dynamic>?,
      nfseSettings: data['nfse_settings'] as Map<String, dynamic>?,
      webhookUrl: data['webhook_url'] as String?,
      status: data['status'] as String? ?? 'active',
      createdAt: data['created_at'] as Timestamp?,
      updatedAt: data['updated_at'] as Timestamp?,
    );
  }

  Future<bool> _verificarLimiteEmissao(String storeId) async {
    try {
      final i = await LojistaIntegracaoService.buscarIntegracaoPorStore(storeId);
      // Sem integração admin: não bloqueia aqui (backend valida GC/assinatura).
      if (i == null) return true;
      if (i.ehIlimitado) return true;
      return !i.semVagaParaNovaEmissao;
    } catch (_) {
      // Fail-open: a API é a autoridade final do saldo.
      return true;
    }
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
