import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/plano_assinatura_model.dart';

/// CRUD da coleção `modulos_planos` — planos de assinatura vendidos avulsos.
/// Staff tem acesso total; leitura liberada para autenticados.
abstract final class ModulosPlanosService {
  static const String _colecao = 'modulos_planos';

  static FirebaseFirestore get _db => FirebaseFirestore.instance;

  /// Stream em tempo real de todos os planos, ordenados por criação (mais recentes primeiro).
  static Stream<QuerySnapshot<Map<String, dynamic>>> stream() {
    return _db
        .collection(_colecao)
        .orderBy('created_at', descending: true)
        .snapshots();
  }

  /// Cria um novo plano no Firestore. Retorna o id do documento criado.
  static Future<String> criar({
    required String nome,
    String? descricao,
    bool ativo = true,
    double valor = 0,
    int duracaoDias = 30,
    int toleranciaDias = 3,
    String vencimentoPadrao = 'Todo dia 10',
    double multaPercentual = 0,
    double jurosPercentual = 0,
    List<String> modulos = const [],
    String? moduloVinculado,
    bool cobrarMulta = false,
    bool cobrarJuros = false,
    bool suspenderInadimplencia = false,
    int? suspenderAposDias,
    String tipoRecorrencia = 'Mensal',
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final ref = _db.collection(_colecao).doc();
    final plano = PlanoAssinaturaModel(
      id: ref.id,
      nome: nome,
      descricao: descricao,
      ativo: ativo,
      valor: valor,
      duracaoDias: duracaoDias,
      toleranciaDias: toleranciaDias,
      vencimentoPadrao: vencimentoPadrao,
      multaPercentual: multaPercentual,
      jurosPercentual: jurosPercentual,
      modulos: modulos,
      moduloVinculado: moduloVinculado,
      cobrarMulta: cobrarMulta,
      cobrarJuros: cobrarJuros,
      suspenderInadimplencia: suspenderInadimplencia,
      suspenderAposDias: suspenderAposDias,
      tipoRecorrencia: tipoRecorrencia,
      createdBy: uid,
    );
    await ref.set(plano.toMap());
    return ref.id;
  }

  /// Atualiza os campos de um plano existente.
  static Future<void> atualizar({
    required String id,
    String? nome,
    String? descricao,
    bool? ativo,
    double? valor,
    int? duracaoDias,
    int? toleranciaDias,
    String? vencimentoPadrao,
    double? multaPercentual,
    double? jurosPercentual,
    List<String>? modulos,
    String? moduloVinculado,
    bool? cobrarMulta,
    bool? cobrarJuros,
    bool? suspenderInadimplencia,
    int? suspenderAposDias,
    String? tipoRecorrencia,
  }) async {
    final data = <String, dynamic>{
      'updated_at': FieldValue.serverTimestamp(),
    };

    if (nome != null) data['nome'] = nome;
    if (descricao != null) data['descricao'] = descricao;
    if (ativo != null) data['ativo'] = ativo;
    if (valor != null) data['valor'] = valor;
    if (duracaoDias != null) data['duracao_dias'] = duracaoDias;
    if (toleranciaDias != null) data['tolerancia_dias'] = toleranciaDias;
    if (vencimentoPadrao != null) data['vencimento_padrao'] = vencimentoPadrao;
    if (multaPercentual != null) data['multa_percentual'] = multaPercentual;
    if (jurosPercentual != null) data['juros_percentual'] = jurosPercentual;
    if (modulos != null) data['modulos'] = modulos;
    if (moduloVinculado != null) data['modulo_vinculado'] = moduloVinculado;
    if (cobrarMulta != null) data['cobrar_multa'] = cobrarMulta;
    if (cobrarJuros != null) data['cobrar_juros'] = cobrarJuros;
    if (suspenderInadimplencia != null) {
      data['suspender_inadimplencia'] = suspenderInadimplencia;
      // Se desabilitou a suspensão, remove o campo suspender_apos_dias
      if (suspenderInadimplencia == false) {
        data['suspender_apos_dias'] = FieldValue.delete();
      }
    }
    if (suspenderAposDias != null) {
      data['suspender_apos_dias'] = suspenderAposDias;
    }
    if (tipoRecorrencia != null) data['tipo_recorrencia'] = tipoRecorrencia;

    await _db.collection(_colecao).doc(id).update(data);
  }

  /// Alterna o status ativo/inativo de um plano.
  static Future<void> toggleStatus(String id, bool ativo) async {
    await _db.collection(_colecao).doc(id).update({
      'ativo': ativo,
      'updated_at': FieldValue.serverTimestamp(),
    });
  }

  /// Exclui permanentemente um plano.
  static Future<void> excluir(String id) async {
    await _db.collection(_colecao).doc(id).delete();
  }

  /// Retorna o total de planos ativos.
  static Future<int> contarAtivos() async {
    final snap = await _db
        .collection(_colecao)
        .where('ativo', isEqualTo: true)
        .count()
        .get();
    return snap.count ?? 0;
  }

  /// Retorna o total de assinaturas ativas (soma do campo em todos os planos).
  static Future<int> somarAssinaturasAtivas() async {
    final snap = await _db.collection(_colecao).get();
    int total = 0;
    for (final doc in snap.docs) {
      total += (doc.data()['assinaturas_ativas'] as num?)?.toInt() ?? 0;
    }
    return total;
  }

  /// Retorna a receita mensal estimada (soma de valor de planos ativos).
  static Future<double> estimarReceitaMensal() async {
    final snap = await _db
        .collection(_colecao)
        .where('ativo', isEqualTo: true)
        .get();
    double total = 0;
    for (final doc in snap.docs) {
      total += (doc.data()['valor'] as num?)?.toDouble() ?? 0;
    }
    return total;
  }
}
