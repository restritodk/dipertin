import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Serviço para gerenciar reservas transacionais de saldo da carteira.
///
/// O saldo do cliente só deve ser debitado APÓS confirmação de pagamento externo
/// (PIX/Cartão). Este serviço implementa o padrão de 3 etapas:
/// 
/// 1. RESERVAR: bloqueia saldo, não debita
/// 2. CONFIRMAR: após sucesso, debita de fato
/// 3. CANCELAR: se falha, libera saldo
class WalletReservaService {
  static final _functions = FirebaseFunctions.instance;

  /// ETAPA 1: Reserva saldo temporariamente
  /// 
  /// Chamada ANTES de processar PIX/Cartão
  /// Retorna: { reservaId, saldoDisponivel }
  static Future<Map<String, dynamic>> reservarSaldo({
    required String userId,
    required String pedidoId,
    required double valor,
  }) async {
    try {
      final callable = _functions.httpsCallable('walletReservarSaldo');
      final resultado = await callable.call({
        'uid': userId,
        'pedidoId': pedidoId,
        'valorReserva': valor,
      });

      return Map<String, dynamic>.from(resultado.data as Map);
    } on FirebaseFunctionsException catch (e) {
      throw Exception('Erro ao reservar saldo: ${e.message}');
    }
  }

  /// ETAPA 2: Confirma débito após sucesso do pagamento
  /// 
  /// Chamada APÓS PIX/Cartão ser aprovado
  /// Retorna: { saldoFinal }
  static Future<Map<String, dynamic>> confirmarDebito({
    required String userId,
    required String reservaId,
  }) async {
    try {
      final callable = _functions.httpsCallable('walletConfirmarDebito');
      final resultado = await callable.call({
        'uid': userId,
        'reservaId': reservaId,
      });

      return Map<String, dynamic>.from(resultado.data as Map);
    } on FirebaseFunctionsException catch (e) {
      throw Exception('Erro ao confirmar débito: ${e.message}');
    }
  }

  /// ETAPA 3: Cancela reserva se pagamento falhar
  /// 
  /// Chamada quando PIX/Cartão é recusado
  /// Retorna: { saldoRestaurado }
  static Future<Map<String, dynamic>> cancelarReserva({
    required String userId,
    required String reservaId,
    String motivo = 'Pagamento recusado',
  }) async {
    try {
      final callable = _functions.httpsCallable('walletCancelarReserva');
      final resultado = await callable.call({
        'uid': userId,
        'reservaId': reservaId,
        'motivo': motivo,
      });

      return Map<String, dynamic>.from(resultado.data as Map);
    } on FirebaseFunctionsException catch (e) {
      throw Exception('Erro ao cancelar reserva: ${e.message}');
    }
  }
}
