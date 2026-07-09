import 'package:cloud_firestore/cloud_firestore.dart';

import '../../models/fiscal_document_model.dart';

import 'fiscal_provider.dart';
import 'fiscal_provider_service.dart';
import 'fiscal_audit_service.dart';

/// Serviço de Carta de Correção Eletrônica (CC-e).
///
/// A CC-e permite corrigir informações permitidas pela legislação
/// (Art. 7º do Protocolo ICMS 85/2007) em NF-e já autorizadas.
///
/// Limite: até 20 CC-e por NF-e.
abstract final class FiscalCartaCorrecaoService {
  /// Limite máximo de CC-e por NF-e.
  static const int maxCartasPorNfe = 20;

  /// Tamanho máximo do texto da correção.
  static const int maxTextoCorrecao = 1000;

  /// Envia uma Carta de Correção Eletrônica (CC-e).
  static Future<FiscalProviderResult> enviarCartaCorrecao({
    required String storeId,
    required String fiscalDocumentId,
    required String textoCorrecao,
    Map<String, dynamic>? storeSettingsData,
  }) async {
    try {
      // ─── 1. Validar texto ───
      final texto = textoCorrecao.trim();
      if (texto.isEmpty) {
        return FiscalProviderResult(
          sucesso: false,
          erro: 'O texto da correção é obrigatório.',
          statusEnvio: 'erro',
        );
      }
      if (texto.length > maxTextoCorrecao) {
        return FiscalProviderResult(
          sucesso: false,
          erro: 'O texto da correção deve ter no máximo $maxTextoCorrecao caracteres.',
          statusEnvio: 'erro',
        );
      }

      // ─── 2. Buscar documento ───
      final docSnap = await FirebaseFirestore.instance
          .collection('fiscal_documents')
          .doc(fiscalDocumentId)
          .get();
      if (!docSnap.exists) {
        return FiscalProviderResult(
          sucesso: false,
          erro: 'Documento fiscal não encontrado.',
          statusEnvio: 'erro',
        );
      }

      final doc = FiscalDocumentModel.fromFirestore(docSnap);
      if (!doc.podeCorrigir) {
        return FiscalProviderResult(
          sucesso: false,
          erro: 'Apenas NF-e autorizadas podem receber Carta de Correção.',
          statusEnvio: 'erro',
        );
      }

      // ─── 3. Verificar limite de CC-e ───
      final sequencia = doc.totalCartasCorrecao + 1;
      if (sequencia > maxCartasPorNfe) {
        return FiscalProviderResult(
          sucesso: false,
          erro: 'Limite de $maxCartasPorNfe Cartas de Correção atingido para esta NF-e.',
          statusEnvio: 'erro',
        );
      }

      // ─── 4. Buscar integração e provedor ───
      final settings = storeSettingsData ??
          await _buscarSettings(storeId);
      if (settings == null) {
        return FiscalProviderResult(
          sucesso: false,
          erro: 'Configuração fiscal da loja não encontrada.',
          statusEnvio: 'erro',
        );
      }

      final integrationId = settings['integration_id'] as String?;
      if (integrationId == null || integrationId.isEmpty) {
        return FiscalProviderResult(
          sucesso: false,
          erro: 'Integração fiscal não configurada.',
          statusEnvio: 'erro',
        );
      }

      final integrationDoc = await FirebaseFirestore.instance
          .collection('fiscal_integrations')
          .doc(integrationId)
          .get();
      if (!integrationDoc.exists) {
        return FiscalProviderResult(
          sucesso: false,
          erro: 'Integração fiscal não encontrada.',
          statusEnvio: 'erro',
        );
      }

      final providerService = FiscalProviderService.instance;
      final config = providerService.extrairConfig(integrationDoc.data()!);
      final provider =
          providerService.resolverDeIntegracao(integrationDoc.data()!);
      if (provider == null) {
        return FiscalProviderResult(
          sucesso: false,
          erro: 'Provedor fiscal não encontrado.',
          statusEnvio: 'erro',
        );
      }

      // ─── 5. Chamar API do provedor ───
      final result = await provider.enviarCartaCorrecao(
        chaveAcesso: doc.accessKey ?? '',
        textoCorrecao: texto,
        sequencia: sequencia,
        config: config,
      );

      // ─── 6. Atualizar Firestore ───
      if (result.sucesso) {
        final cartas = doc.cartasCorrecao.toList();
        cartas.add(CartaCorrecaoEvento(
          sequencia: sequencia,
          textoCorrecao: texto,
          protocolo: result.protocolo ?? result.chaveAcesso,
          xmlUrl: result.xmlUrl,
          chaveAcesso: doc.accessKey,
          enviadaEm: Timestamp.now(),
        ));

        await FirebaseFirestore.instance
            .collection('fiscal_documents')
            .doc(fiscalDocumentId)
            .update({
          'cartas_correcao': cartas.map((c) => c.toMap()).toList(),
          'status': StatusFiscal.ccEnviada,
          'updated_at': FieldValue.serverTimestamp(),
        });

        // Auditoria
        FiscalAuditService.registrar(
          lojaId: storeId,
          acao: 'carta_correcao',
          descricao: 'CC-e #$sequencia enviada para NF-e ${doc.number ?? ""}',
          documentoId: fiscalDocumentId,
          chaveAcesso: doc.accessKey,
          provedor: provider.id,
        );
      }

      return result;
    } catch (e) {
      return FiscalProviderResult(
        sucesso: false,
        erro: 'Erro ao enviar CC-e: $e',
        statusEnvio: 'erro',
      );
    }
  }

  /// Gera o texto padrão de uma CC-e.
  static String gerarTextoPadrao(String campoCorrigido, String valorAntigo, String valorNovo) {
    return 'Onde se lê "$valorAntigo" no campo "$campoCorrigido", leia-se "$valorNovo".';
  }

  /// Verifica se um campo pode ser corrigido via CC-e (Art. 7º).
  static bool campoPodeSerCorrigido(String campo) {
    const permitidos = [
      'emitente.endereco.logradouro',
      'emitente.endereco.numero',
      'emitente.endereco.bairro',
      'emitente.endereco.cidade',
      'emitente.endereco.uf',
      'emitente.endereco.cep',
      'destinatario.endereco.logradouro',
      'destinatario.endereco.numero',
      'destinatario.endereco.bairro',
      'destinatario.endereco.cidade',
      'destinatario.endereco.uf',
      'destinatario.endereco.cep',
      'destinatario.nome',
      'produto.descricao',
      'produto.ncm',
      'produto.cfop',
      'produto.unidade_comercial',
      'informacoes_adicionais',
      'natureza_operacao',
      'transporte',
      'carta_correcao',
    ];
    return permitidos.contains(campo);
  }

  /// Campos que NÃO podem ser corrigidos via CC-e.
  static bool campoProibido(String campo) {
    const proibidos = [
      'emitente.cnpj',
      'emitente.ie',
      'emitente.razao_social',
      'destinatario.cpf_cnpj',
      'valores',
      'impostos',
      'data_emissao',
      'numero_nfe',
      'serie',
      'chave_acesso',
    ];
    return proibidos.contains(campo);
  }

  static Future<Map<String, dynamic>?> _buscarSettings(String storeId) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('store_fiscal_settings')
          .where('store_id', isEqualTo: storeId)
          .limit(1)
          .get();
      if (snap.docs.isNotEmpty) return snap.docs.first.data();
    } catch (_) {}
    return null;
  }
}
