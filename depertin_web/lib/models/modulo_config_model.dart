import 'package:cloud_firestore/cloud_firestore.dart';

/// Módulo configurável no painel Gestão de Assinaturas → Configurações.
/// Coleção: `assinaturas_modulos/{id}`
class ModuloConfigModel {
  ModuloConfigModel({
    required this.id,
    required this.nome,
    required this.codigo,
    this.descricao = '',
    this.ativo = true,
    this.contratavel = true,
    this.icone = 'widgets',
    this.createdBy,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String nome;
  final String codigo;
  final String descricao;
  final bool ativo;
  final bool contratavel;
  final String icone;
  final String? createdBy;
  final Timestamp? createdAt;
  final Timestamp? updatedAt;

  Map<String, dynamic> toMap() => {
        'nome': nome,
        'codigo': codigo,
        'descricao': descricao,
        'ativo': ativo,
        'contratavel': contratavel,
        'icone': icone,
        'created_by': createdBy,
        'created_at': createdAt ?? FieldValue.serverTimestamp(),
        'updated_at': FieldValue.serverTimestamp(),
      };

  Map<String, dynamic> toUpdateMap() => {
        'nome': nome,
        'codigo': codigo,
        'descricao': descricao,
        'ativo': ativo,
        'contratavel': contratavel,
        'icone': icone,
        'updated_at': FieldValue.serverTimestamp(),
      };

  static ModuloConfigModel fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final d = doc.data() ?? {};
    return ModuloConfigModel(
      id: doc.id,
      nome: d['nome'] as String? ?? '',
      codigo: d['codigo'] as String? ?? '',
      descricao: d['descricao'] as String? ?? '',
      ativo: d['ativo'] as bool? ?? true,
      contratavel: d['contratavel'] as bool? ?? true,
      icone: d['icone'] as String? ?? 'widgets',
      createdBy: d['created_by'] as String?,
      createdAt: d['created_at'] as Timestamp?,
      updatedAt: d['updated_at'] as Timestamp?,
    );
  }
}
