import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/billing_settings_model.dart';
import 'firebase_functions_config.dart';

/// Acesso às configurações de cobranças (`billing_settings`).
///
/// ⚠️ NUNCA passar FieldValue ou Timestamp nos parâmetros enviados
/// para a Cloud Function — isso quebra o jsonEncode do HTTP.
/// A Function usa serverTimestamp() no lado do servidor.
abstract final class BillingSettingsService {
  static const String docId = 'global';
  static const String colecao = 'billing_settings';

  static FirebaseFirestore get _db => FirebaseFirestore.instance;

  /// Stream em tempo real das configurações.
  static Stream<BillingSettings?> stream() {
    return _db.collection(colecao).doc(docId).snapshots().map((snap) {
      if (!snap.exists) return null;
      return BillingSettings.fromFirestore(snap.data() ?? {});
    });
  }

  /// Salva as configurações via Cloud Function (Admin SDK).
  /// [settings.toJson()] contém apenas tipos primitivos — sem FieldValue.
  static Future<void> salvar(BillingSettings settings) async {
    final user = FirebaseAuth.instance.currentUser;
    await callFirebaseFunctionSafe(
      'adminSalvarBillingSettings',
      parameters: {
        ...settings.toJson(),
        'updated_by': user?.email ?? user?.uid ?? 'unknown',
      },
    );
  }

  /// Cria documento inicial se não existir.
  static Future<void> criarSeNecessario() async {
    final snap = await _db.collection(colecao).doc(docId).get();
    if (!snap.exists) {
      await callFirebaseFunctionSafe(
        'adminSalvarBillingSettings',
        parameters: {
          ...const BillingSettings().toJson(),
          'updated_by': 'sistema',
        },
      );
    }
  }

  /// Gera cobranças manualmente (acionado pelo botão na UI).
  static Future<void> gerarCobrancasAutomaticas() async {
    await callFirebaseFunctionSafe('adminGerarCobrancasPorConfig');
  }
}
