import 'package:cloud_firestore/cloud_firestore.dart';

/// Plano de assinatura vendido avulso (`modulos_planos/{id}`).
/// Gerido pelo staff no painel Gestão de Assinaturas → Planos e Módulos.
class PlanoAssinaturaModel {
  PlanoAssinaturaModel({
    required this.id,
    required this.nome,
    this.descricao,
    this.ativo = true,
    this.valor = 0,
    this.duracaoDias = 30,
    this.assinaturasAtivas = 0,
    this.toleranciaDias = 3,
    this.vencimentoPadrao = 'Todo dia 10',
    this.multaPercentual = 0,
    this.jurosPercentual = 0,
    this.modulos = const [],
    this.moduloVinculado,
    this.cobrarMulta = false,
    this.cobrarJuros = false,
    this.suspenderInadimplencia = false,
    this.suspenderAposDias,
    this.tipoRecorrencia = 'Mensal',
    this.createdBy,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String nome;
  final String? descricao;
  final bool ativo;
  final double valor;
  final int duracaoDias;
  final int assinaturasAtivas;
  final int toleranciaDias;
  final String vencimentoPadrao;
  final double multaPercentual;
  final double jurosPercentual;
  final List<String> modulos;
  final String? moduloVinculado;
  final bool cobrarMulta;
  final bool cobrarJuros;
  final bool suspenderInadimplencia;
  final int? suspenderAposDias;
  final String tipoRecorrencia;
  final String? createdBy;
  final Timestamp? createdAt;
  final Timestamp? updatedAt;

  Map<String, dynamic> toMap() => {
        'nome': nome,
        'descricao': descricao,
        'ativo': ativo,
        'valor': valor,
        'duracao_dias': duracaoDias,
        'assinaturas_ativas': assinaturasAtivas,
        'tolerancia_dias': toleranciaDias,
        'vencimento_padrao': vencimentoPadrao,
        'multa_percentual': multaPercentual,
        'juros_percentual': jurosPercentual,
        'modulos': modulos,
        'modulo_vinculado': moduloVinculado,
        'cobrar_multa': cobrarMulta,
        'cobrar_juros': cobrarJuros,
        'suspender_inadimplencia': suspenderInadimplencia,
        'suspender_apos_dias': suspenderAposDias,
        'tipo_recorrencia': tipoRecorrencia,
        'created_by': createdBy,
        'created_at': createdAt ?? FieldValue.serverTimestamp(),
        'updated_at': FieldValue.serverTimestamp(),
      };

  Map<String, dynamic> toUpdateMap() => {
        'nome': nome,
        'descricao': descricao,
        'ativo': ativo,
        'valor': valor,
        'duracao_dias': duracaoDias,
        'assinaturas_ativas': assinaturasAtivas,
        'tolerancia_dias': toleranciaDias,
        'vencimento_padrao': vencimentoPadrao,
        'multa_percentual': multaPercentual,
        'juros_percentual': jurosPercentual,
        'modulos': modulos,
        'modulo_vinculado': moduloVinculado,
        'cobrar_multa': cobrarMulta,
        'cobrar_juros': cobrarJuros,
        'suspender_inadimplencia': suspenderInadimplencia,
        'suspender_apos_dias': suspenderAposDias,
        'tipo_recorrencia': tipoRecorrencia,
        'updated_at': FieldValue.serverTimestamp(),
      };

  static PlanoAssinaturaModel fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final d = doc.data() ?? {};
    return PlanoAssinaturaModel(
      id: doc.id,
      nome: d['nome'] as String? ?? '',
      descricao: d['descricao'] as String?,
      ativo: d['ativo'] as bool? ?? true,
      valor: (d['valor'] as num?)?.toDouble() ?? 0,
      duracaoDias: (d['duracao_dias'] as num?)?.toInt() ?? 30,
      assinaturasAtivas: (d['assinaturas_ativas'] as num?)?.toInt() ?? 0,
      toleranciaDias: (d['tolerancia_dias'] as num?)?.toInt() ?? 3,
      vencimentoPadrao: d['vencimento_padrao'] as String? ?? 'Todo dia 10',
      multaPercentual: (d['multa_percentual'] as num?)?.toDouble() ?? 0,
      jurosPercentual: (d['juros_percentual'] as num?)?.toDouble() ?? 0,
      modulos: List<String>.from(d['modulos'] as List? ?? []),
      moduloVinculado: d['modulo_vinculado'] as String?,
      cobrarMulta: d['cobrar_multa'] as bool? ?? false,
      cobrarJuros: d['cobrar_juros'] as bool? ?? false,
      suspenderInadimplencia: d['suspender_inadimplencia'] as bool? ?? false,
      suspenderAposDias: (d['suspender_apos_dias'] as num?)?.toInt(),
      tipoRecorrencia: d['tipo_recorrencia'] as String? ?? 'Mensal',
      createdBy: d['created_by'] as String?,
      createdAt: d['created_at'] as Timestamp?,
      updatedAt: d['updated_at'] as Timestamp?,
    );
  }
}
