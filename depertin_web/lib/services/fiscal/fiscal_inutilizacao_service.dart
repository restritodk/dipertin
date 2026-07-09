import 'package:cloud_firestore/cloud_firestore.dart';

import '../../models/fiscal_document_model.dart';
import 'fiscal_provider.dart';
import 'fiscal_provider_service.dart';
import 'fiscal_audit_service.dart';

/// Serviço de inutilização de numeração de NF-e.
///
/// A inutilização é usada quando há quebra na sequência de numeração
/// (ex.: nota cancelada antes da autorização, nota gerada mas não emitida).
/// O protocolo de inutilização comprova para a SEFAZ que a numeração
/// foi oficialmente inutilizada.
abstract final class FiscalInutilizacaoService {
  /// Número máximo de faixa inutilizável por vez (SEFAZ recomenda até 999).
  static const int maxFaixaPorVez = 999;

  /// Inutiliza uma faixa de numeração de NF-e.
  ///
  /// [serie] Série fiscal (ex: "1", "2").
  /// [numeroInicial] Primeiro número da faixa a inutilizar.
  /// [numeroFinal] Último número da faixa a inutilizar (pode ser igual ao inicial).
  /// [justificativa] Motivo (mín. 15 caracteres).
  /// [storeId] ID da loja para registro no histórico.
  static Future<FiscalProviderResult> inutilizar({
    required String storeId,
    required String serie,
    required int numeroInicial,
    required int numeroFinal,
    required String justificativa,
  }) async {
    try {
      // ─── 1. Validações ───
      if (justificativa.trim().length < 15) {
        return FiscalProviderResult(
          sucesso: false,
          erro: 'A justificativa deve ter no mínimo 15 caracteres.',
          statusEnvio: 'erro',
        );
      }

      if (numeroInicial <= 0 || numeroFinal <= 0) {
        return FiscalProviderResult(
          sucesso: false,
          erro: 'Os números devem ser maiores que zero.',
          statusEnvio: 'erro',
        );
      }

      if (numeroFinal < numeroInicial) {
        return FiscalProviderResult(
          sucesso: false,
          erro: 'O número final deve ser maior ou igual ao inicial.',
          statusEnvio: 'erro',
        );
      }

      final faixa = numeroFinal - numeroInicial + 1;
      if (faixa > maxFaixaPorVez) {
        return FiscalProviderResult(
          sucesso: false,
          erro: 'A faixa máxima por inutilização é de $maxFaixaPorVez números.',
          statusEnvio: 'erro',
        );
      }

      // ─── 2. Buscar configuração e provedor ───
      final settings = await _buscarSettings(storeId);
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

      // ─── 3. Chamar API do provedor ───
      final result = await provider.inutilizarNumeracao(
        serie: serie,
        numeroInicial: numeroInicial,
        numeroFinal: numeroFinal,
        justificativa: justificativa,
        config: config,
      );

      // ─── 4. Registrar no Firestore ───
      if (result.sucesso) {
        // Cria um documento de inutilização na coleção
        await FirebaseFirestore.instance
            .collection('fiscal_documents')
            .add({
          'store_id': storeId,
          'document_type': 'nfe',
          'provider': provider.id,
          'status': StatusFiscal.numeracaoInutilizada,
          'series': serie,
          'number': '$numeroInicial-$numeroFinal',
          'protocol': result.protocolo,
          'provider_response': result.providerResponse,
          'justificativa_inutilizacao': justificativa,
          'created_at': FieldValue.serverTimestamp(),
          'updated_at': FieldValue.serverTimestamp(),
        });

        // Auditoria
        FiscalAuditService.registrar(
          lojaId: storeId,
          acao: 'inutilizacao_numeracao',
          descricao:
              'Numeração Série $serie: $numeroInicial-$numeroFinal inutilizada: $justificativa',
          documentoId: '',
          chaveAcesso: result.chaveAcesso,
          provedor: provider.id,
        );
      }

      return result;
    } catch (e) {
      return FiscalProviderResult(
        sucesso: false,
        erro: 'Erro ao inutilizar numeração: $e',
        statusEnvio: 'erro',
      );
    }
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
