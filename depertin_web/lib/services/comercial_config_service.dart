import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:depertin_web/models/comercial_pendencia_data.dart';

/// Carrega as configurações comerciais salvas em `gestao_comercial_configuracoes/{lojaId}`.
///
/// Converte os dados da tela "Configurações Comercial" para os modelos de
/// regras de negócio usados pelo PDV, recebimentos e pendências.
abstract final class ComercialConfigService {
  /// Carga única do [JurosMultaConfig] a partir do Firestore.
  ///
  /// Se não existir documento, retorna [JurosMultaConfig.padrao].
  static Future<JurosMultaConfig> carregarJurosMultaConfig(
    String lojaId,
  ) async {
    if (lojaId.isEmpty) return const JurosMultaConfig();
    try {
      final doc = await FirebaseFirestore.instance
          .collection('gestao_comercial_configuracoes')
          .doc(lojaId)
          .get();
      if (!doc.exists) return const JurosMultaConfig();

      final data = doc.data()!;
      final jm = data['jurosMultas'] as Map<String, dynamic>? ?? {};

      return JurosMultaConfig(
        cobrarMultaPorAtraso: jm['cobrarMulta'] == true,
        percentualMulta: (jm['percentualMulta'] as num?)?.toDouble() ?? 0,
        cobrarJurosPorAtraso: jm['cobrarJuros'] == true,
        percentualJurosAoDia:
            (jm['percentualJurosDia'] as num?)?.toDouble() ?? 0,
        diasTolerancia: (jm['diasTolerancia'] as num?)?.toInt() ?? 0,
        aplicarJurosAposVencimento: jm['aplicarJurosAoDia'] == true,
      );
    } catch (_) {
      return const JurosMultaConfig();
    }
  }

  /// Stream em tempo real do [JurosMultaConfig].
  ///
  /// Reage a alterações na tela "Configurações Comercial".
  static Stream<JurosMultaConfig> streamJurosMultaConfig(String lojaId) {
    if (lojaId.isEmpty) {
      return Stream.value(const JurosMultaConfig());
    }
    return FirebaseFirestore.instance
        .collection('gestao_comercial_configuracoes')
        .doc(lojaId)
        .snapshots()
        .map((snap) {
      if (!snap.exists) return const JurosMultaConfig();
      final data = snap.data()!;
      final jm = data['jurosMultas'] as Map<String, dynamic>? ?? {};
      return JurosMultaConfig(
        cobrarMultaPorAtraso: jm['cobrarMulta'] == true,
        percentualMulta: (jm['percentualMulta'] as num?)?.toDouble() ?? 0,
        cobrarJurosPorAtraso: jm['cobrarJuros'] == true,
        percentualJurosAoDia:
            (jm['percentualJurosDia'] as num?)?.toDouble() ?? 0,
        diasTolerancia: (jm['diasTolerancia'] as num?)?.toInt() ?? 0,
        aplicarJurosAposVencimento: jm['aplicarJurosAoDia'] == true,
      );
    });
  }
}
