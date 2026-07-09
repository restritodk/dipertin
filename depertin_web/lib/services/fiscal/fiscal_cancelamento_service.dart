import 'package:cloud_firestore/cloud_firestore.dart';

import '../../models/fiscal_document_model.dart';
import '../fiscal_integrations_service.dart';
import 'fiscal_provider.dart';
import 'fiscal_provider_service.dart';
import 'fiscal_erro_translator.dart';
import 'fiscal_audit_service.dart';

/// Serviço de cancelamento de NF-e.
///
/// Fluxo:
/// 1. Validar prazo legal (24h da autorização)
/// 2. Validar justificativa (mín. 15 caracteres)
/// 3. Buscar configuração e provedor
/// 4. Chamar API do provedor para cancelar
/// 5. Salvar XML/PDF de cancelamento
/// 6. Atualizar status para Cancelada
abstract final class FiscalCancelamentoService {
  /// Prazo máximo para cancelamento em horas (24h = prazo legal).
  static const int prazoMaximoHoras = 24;

  /// Cancela uma NF-e autorizada.
  ///
  /// Retorna [FiscalProviderResult] com os detalhes do cancelamento.
  static Future<FiscalProviderResult> cancelarNota({
    required String storeId,
    required String fiscalDocumentId,
    required String justificativa,
    required String? accessKey,
    required String? protocol,
    Map<String, dynamic>? storeSettingsData,
  }) async {
    try {
      // ─── 1. Validar justificativa ───
      if (justificativa.trim().length < 15) {
        return FiscalProviderResult(
          sucesso: false,
          erro: 'A justificativa deve ter no mínimo 15 caracteres.',
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
      if (doc.isCancelada) {
        return FiscalProviderResult(
          sucesso: false,
          erro: 'Esta NF-e já está cancelada.',
          statusEnvio: 'erro',
        );
      }
      if (!doc.podeCancelar) {
        return FiscalProviderResult(
          sucesso: false,
          erro: 'Apenas NF-e autorizadas podem ser canceladas.',
          statusEnvio: 'erro',
        );
      }

      // ─── 3. Validar prazo legal ───
      if (doc.issuedAt != null) {
        final horasDesdeEmissao =
            DateTime.now().difference(doc.issuedAt!.toDate()).inHours;
        if (horasDesdeEmissao > prazoMaximoHoras) {
          return FiscalProviderResult(
            sucesso: false,
            erro: 'Prazo legal de cancelamento excedido ($prazoMaximoHoras horas). '
                'Para cancelar, é necessário solicitar via administrativo.',
            statusEnvio: 'erro',
          );
        }
      }

      // ─── 4. Buscar integração e provedor ───
      final settings = storeSettingsData != null
          ? storeSettingsData
          : await _buscarSettings(storeId);
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
      final provider = providerService.resolverDeIntegracao(integrationDoc.data()!);
      if (provider == null) {
        return FiscalProviderResult(
          sucesso: false,
          erro: 'Provedor fiscal não encontrado.',
          statusEnvio: 'erro',
        );
      }

      // ─── 5. Chamar API do provedor para cancelar ───
      final result = await provider.cancelarNota(
        chaveAcesso: accessKey ?? '',
        justificativa: justificativa,
        numeroProtocolo: protocol ?? '',
        config: config,
      );

      // ─── 6. Atualizar Firestore ───
      if (result.sucesso) {
        await FiscalIntegrationsService.atualizarStatusDocumento(
          fiscalDocumentId,
          StatusFiscal.cancelada,
          rejectionReason: 'Cancelamento: $justificativa',
        );

        // Campos extras de cancelamento
        await FirebaseFirestore.instance
            .collection('fiscal_documents')
            .doc(fiscalDocumentId)
            .update({
          'justificativa_cancelamento': justificativa,
          'cancelled_at': FieldValue.serverTimestamp(),
          if (result.xmlUrl != null) 'xml_cancelamento_url': result.xmlUrl,
          if (result.pdfUrl != null) 'pdf_cancelamento_url': result.pdfUrl,
        });

        // Registra auditoria
        FiscalAuditService.registrar(
          lojaId: storeId,
          acao: 'cancelamento_nfe',
          descricao: 'NF-e ${doc.number ?? ""} cancelada: $justificativa',
          documentoId: fiscalDocumentId,
          chaveAcesso: accessKey,
          provedor: provider.id,
        );
      }

      return result;
    } catch (e) {
      return FiscalProviderResult(
        sucesso: false,
        erro: 'Erro ao cancelar NF-e: $e',
        statusEnvio: 'erro',
      );
    }
  }

  /// Busca settings da loja.
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

  /// Mensagem amigável para erros de cancelamento.
  static String mensagemErroAmigavel(FiscalProviderResult result) {
    if (result.erro == null) return 'Erro desconhecido ao cancelar.';

    final codigo = FiscalErroTranslator.extrairCodigoRejeicao(result.erro);
    final traducao = FiscalErroTranslator.traduzir(codigo, mensagemOriginal: result.erro);
    return '${traducao.titulo}: ${traducao.descricao}';
  }
}
