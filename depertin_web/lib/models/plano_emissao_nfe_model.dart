import 'package:cloud_firestore/cloud_firestore.dart';

/// Plano de emissão de NF-e (quantidade de notas por mês).
///
/// Coleção Firestore: `planos_emissao_nfe/{id}`
class PlanoEmissaoNfeModel {
  final String id;
  final String nome;
  final String descricao;
  final bool ativo;
  final double valor;
  final int limiteNotas; // 0 = ilimitado
  final String tipoRecorrencia; // mensal
  final int? ordem;
  final String? createdBy;
  final Timestamp? createdAt;
  final Timestamp? updatedAt;

  PlanoEmissaoNfeModel({
    required this.id,
    required this.nome,
    this.descricao = '',
    this.ativo = true,
    this.valor = 0,
    this.limiteNotas = 0,
    this.tipoRecorrencia = 'mensal',
    this.ordem,
    this.createdBy,
    this.createdAt,
    this.updatedAt,
  });

  bool get ehIlimitado => limiteNotas == 0;
  String get limiteExibir => ehIlimitado ? 'Ilimitado' : limiteNotas.toString();

  static PlanoEmissaoNfeModel fromFirestore(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};
    return PlanoEmissaoNfeModel(
      id: doc.id,
      nome: d['nome'] as String? ?? '',
      descricao: d['descricao'] as String? ?? '',
      ativo: d['ativo'] as bool? ?? true,
      valor: (d['valor'] as num?)?.toDouble() ?? 0,
      limiteNotas: (d['limite_notas'] as num?)?.toInt() ?? 0,
      tipoRecorrencia: d['tipo_recorrencia'] as String? ?? 'mensal',
      ordem: (d['ordem'] as num?)?.toInt(),
      createdBy: d['created_by'] as String?,
      createdAt: d['created_at'] as Timestamp?,
      updatedAt: d['updated_at'] as Timestamp?,
    );
  }

  Map<String, dynamic> toMap() => {
        'nome': nome,
        'descricao': descricao,
        'ativo': ativo,
        'valor': valor,
        'limite_notas': limiteNotas,
        'tipo_recorrencia': tipoRecorrencia,
        'ordem': ordem,
        'created_by': createdBy,
        'created_at': FieldValue.serverTimestamp(),
        'updated_at': FieldValue.serverTimestamp(),
      };

  Map<String, dynamic> toUpdateMap() => {
        'nome': nome,
        'descricao': descricao,
        'ativo': ativo,
        'valor': valor,
        'limite_notas': limiteNotas,
        'tipo_recorrencia': tipoRecorrencia,
        'ordem': ordem,
        'updated_at': FieldValue.serverTimestamp(),
      };
}
