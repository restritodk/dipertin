import 'package:flutter/foundation.dart' show debugPrint;

import '../services/firebase_functions_config.dart' show callFirebaseFunctionSafe;

/// Serviço de pagamento para assinatura de planos.
/// Chama as Cloud Functions dedicadas que criam cobranças no Mercado Pago.
abstract final class AssinaturaPagamentoService {
  /// Cria um PIX para contratar plano.
  /// Retorna: { assinaturaId, paymentId, qrCode, qrCodeBase64, pixCopiaECola, expiresAt, status }
  static Future<Map<String, dynamic>> criarPagamentoPix({
    required String planId,
    required String lojaId,
    required String lojaNome,
    required String ownerName,
    required String ownerEmail,
    String ownerPhone = '',
    required double valor,
    required String planName,
    List<String> modulos = const [],
  }) async {
    try {
      final result = await callFirebaseFunctionSafe(
        'assinarPlanoCriarPagamentoPix',
        parameters: {
          'planId': planId,
          'lojaId': lojaId,
          'lojaNome': lojaNome,
          'ownerName': ownerName,
          'ownerEmail': ownerEmail,
          'ownerPhone': ownerPhone,
          'valor': valor,
          'planName': planName,
          'modulos': modulos,
        },
        timeout: const Duration(seconds: 60),
      );
      return result;
    } catch (e) {
      debugPrint('[AssinaturaPagamento] erro criar PIX: $e');
      rethrow;
    }
  }

  /// Consulta status do PIX da assinatura.
  /// Retorna: { status, pago, plano, assinaturaId }
  static Future<Map<String, dynamic>> consultarStatusPix({
    required String assinaturaId,
  }) async {
    try {
      final result = await callFirebaseFunctionSafe(
        'assinarPlanoConsultarStatusPix',
        parameters: {
          'assinaturaId': assinaturaId,
        },
        timeout: const Duration(seconds: 30),
      );
      return result;
    } catch (e) {
      debugPrint('[AssinaturaPagamento] erro consultar PIX: $e');
      return {'status': 'erro', 'pago': false};
    }
  }

  /// Processa pagamento com cartão de crédito.
  /// Retorna: { aprovado, assinaturaId, mp_status, mensagem }
  static Future<Map<String, dynamic>> processarCartao({
    required String planId,
    required String lojaId,
    required String lojaNome,
    required String ownerName,
    required String ownerEmail,
    String ownerPhone = '',
    required double valor,
    required String planName,
    List<String> modulos = const [],
    required String numeroCartao,
    required String nomeTitular,
    required String mesExpiracao,
    required String anoExpiracao,
    required String cvv,
    required String cpf,
    String paymentMethodId = 'visa',
    int parcelas = 1,
  }) async {
    try {
      final result = await callFirebaseFunctionSafe(
        'assinarPlanoProcessarCartao',
        parameters: {
          'planId': planId,
          'lojaId': lojaId,
          'lojaNome': lojaNome,
          'ownerName': ownerName,
          'ownerEmail': ownerEmail,
          'ownerPhone': ownerPhone,
          'valor': valor,
          'planName': planName,
          'modulos': modulos,
          'numeroCartao': numeroCartao,
          'nomeTitular': nomeTitular,
          'mesExpiracao': mesExpiracao,
          'anoExpiracao': anoExpiracao,
          'cvv': cvv,
          'cpf': cpf,
          'paymentMethodId': paymentMethodId,
          'parcelas': parcelas,
        },
        timeout: const Duration(seconds: 120),
      );
      return result;
    } catch (e) {
      debugPrint('[AssinaturaPagamento] erro cartão: $e');
      rethrow;
    }
  }

  // ── RENOVAÇÃO ──

  /// Cria um PIX para renovação de assinatura existente (bloqueada/vencida).
  static Future<Map<String, dynamic>> criarRenovacaoPix({
    required String assinaturaId,
    required String lojaId,
    required String ownerName,
    required String ownerEmail,
    String ownerPhone = '',
    required double valor,
    required String planName,
  }) async {
    try {
      final result = await callFirebaseFunctionSafe(
        'assinarPlanoRenovarPix',
        parameters: {
          'assinaturaId': assinaturaId,
          'lojaId': lojaId,
          'ownerName': ownerName,
          'ownerEmail': ownerEmail,
          'ownerPhone': ownerPhone,
          'valor': valor,
          'planName': planName,
        },
        timeout: const Duration(seconds: 60),
      );
      return result;
    } catch (e) {
      debugPrint('[AssinaturaPagamento] erro renovar PIX: $e');
      rethrow;
    }
  }

  /// Consulta status do PIX de renovação.
  static Future<Map<String, dynamic>> consultarStatusRenovacaoPix({
    required String assinaturaId,
  }) async {
    try {
      final result = await callFirebaseFunctionSafe(
        'assinarPlanoRenovarConsultarStatusPix',
        parameters: {
          'assinaturaId': assinaturaId,
        },
        timeout: const Duration(seconds: 30),
      );
      return result;
    } catch (e) {
      debugPrint('[AssinaturaPagamento] erro consultar renovação PIX: $e');
      return {
        'success': false,
        'payment_status': 'erro',
        'approved': false,
        'pago': false,
        'status': 'erro',
      };
    }
  }

  /// Processa pagamento com cartão para renovar assinatura existente.
  static Future<Map<String, dynamic>> processarRenovacaoCartao({
    required String assinaturaId,
    required String lojaId,
    required String ownerName,
    required String ownerEmail,
    String ownerPhone = '',
    required double valor,
    required String planName,
    required String numeroCartao,
    required String nomeTitular,
    required String mesExpiracao,
    required String anoExpiracao,
    required String cvv,
    required String cpf,
    String paymentMethodId = 'visa',
    int parcelas = 1,
  }) async {
    try {
      final result = await callFirebaseFunctionSafe(
        'assinarPlanoRenovarCartao',
        parameters: {
          'assinaturaId': assinaturaId,
          'lojaId': lojaId,
          'ownerName': ownerName,
          'ownerEmail': ownerEmail,
          'ownerPhone': ownerPhone,
          'valor': valor,
          'planName': planName,
          'numeroCartao': numeroCartao,
          'nomeTitular': nomeTitular,
          'mesExpiracao': mesExpiracao,
          'anoExpiracao': anoExpiracao,
          'cvv': cvv,
          'cpf': cpf,
          'paymentMethodId': paymentMethodId,
          'parcelas': parcelas,
        },
        timeout: const Duration(seconds: 120),
      );
      return result;
    } catch (e) {
      debugPrint('[AssinaturaPagamento] erro renovar cartão: $e');
      rethrow;
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // CARTÃO RECORRENTE (Etapa 3.2.1) — Preapproval Mercado Pago
  // ═══════════════════════════════════════════════════════════════

  /// Cria assinatura recorrente via cartão de crédito (preapproval).
  ///
  /// Chama a Cloud Function [assinarPlanoCriarCartaoRecorrente].
  /// O lojista deve ter aceito explicitamente a cobrança automática.
  ///
  /// Retorna: { preapprovalId, status, paymentMethodId, lastFour,
  ///           bandeira, nextBillingDate, valor }
  ///
  /// IMPORTANTE: Não salva dados sensíveis do cartão.
  /// Apenas tokeniza no backend via MP.
  static Future<Map<String, dynamic>> criarCartaoRecorrente({
    required String planId,
    required String planName,
    required double valor,
    required String lojaId,
    required String lojaNome,
    required String ownerName,
    required String ownerEmail,
    required String numeroCartao,
    required String nomeTitular,
    required String mesExpiracao,
    required String anoExpiracao,
    required String cvv,
    required String cpf,
    String paymentMethodId = 'visa',
    List<String> modulos = const [],
  }) async {
    try {
      final result = await callFirebaseFunctionSafe(
        'assinarPlanoCriarCartaoRecorrente',
        parameters: {
          'planId': planId,
          'planName': planName,
          'valor': valor,
          'lojaId': lojaId,
          'lojaNome': lojaNome,
          'ownerName': ownerName,
          'ownerEmail': ownerEmail,
          'ownerPhone': '',
          'numeroCartao': numeroCartao,
          'nomeTitular': nomeTitular,
          'mesExpiracao': mesExpiracao,
          'anoExpiracao': anoExpiracao,
          'cvv': cvv,
          'cpf': cpf,
          'paymentMethodId': paymentMethodId,
          'modulos': modulos,
          'aceitoRecorrencia': true,  // Frontend garante aceite
        },
        timeout: const Duration(seconds: 90),
      );
      return result;
    } catch (e) {
      debugPrint('[AssinaturaPagamento] erro criar cartão recorrente: $e');
      rethrow;
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // CANCELAR CARTÃO RECORRENTE (Etapa 3.4.3)
  // ═══════════════════════════════════════════════════════════════

  /// Cancela a cobrança recorrente no cartão (preapproval) do lojista.
  ///
  /// NÃO cancela o plano inteiro. Apenas desativa a recorrência automática.
  /// Chama a Cloud Function [cancelarAssinaturaCartaoRecorrente].
  ///
  /// Retorna: { ok, preapprovalId, status, message }
  static Future<Map<String, dynamic>> cancelarCartaoRecorrente() async {
    try {
      final result = await callFirebaseFunctionSafe(
        'cancelarAssinaturaCartaoRecorrente',
        // O storeId é inferido do request.auth.uid no backend
        timeout: const Duration(seconds: 60),
      );
      return result;
    } catch (e) {
      debugPrint('[AssinaturaPagamento] erro cancelar cartão recorrente: $e');
      rethrow;
    }
  }
}
