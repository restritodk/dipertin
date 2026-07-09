import 'package:cloud_firestore/cloud_firestore.dart';

/// Controle de série e numeração de NF-e por loja.
///
/// Coleção: `fiscal_series/{id}`
/// Cada loja tem um documento por série fiscal.
class FiscalSerieModel {
  final String id;
  final String storeId;
  final String serie;
  final String documentType;
  final int proximoNumero;
  final int ultimoNumeroUtilizado;
  final String ambiente;
  final bool ativa;
  final Timestamp? createdAt;
  final Timestamp? updatedAt;

  FiscalSerieModel({
    required this.id,
    required this.storeId,
    required this.serie,
    this.documentType = 'nfe',
    this.proximoNumero = 1,
    this.ultimoNumeroUtilizado = 0,
    this.ambiente = 'sandbox',
    this.ativa = true,
    this.createdAt,
    this.updatedAt,
  });

  static FiscalSerieModel fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};
    return FiscalSerieModel(
      id: doc.id,
      storeId: d['store_id'] as String? ?? '',
      serie: d['serie'] as String? ?? '1',
      documentType: d['document_type'] as String? ?? 'nfe',
      proximoNumero: (d['proximo_numero'] as num?)?.toInt() ?? 1,
      ultimoNumeroUtilizado: (d['ultimo_numero_utilizado'] as num?)?.toInt() ?? 0,
      ambiente: d['ambiente'] as String? ?? 'sandbox',
      ativa: d['ativa'] as bool? ?? true,
      createdAt: d['created_at'] as Timestamp?,
      updatedAt: d['updated_at'] as Timestamp?,
    );
  }

  Map<String, dynamic> toMap() => {
        'store_id': storeId,
        'serie': serie,
        'document_type': documentType,
        'proximo_numero': proximoNumero,
        'ultimo_numero_utilizado': ultimoNumeroUtilizado,
        'ambiente': ambiente,
        'ativa': ativa,
        'updated_at': FieldValue.serverTimestamp(),
      };

  Map<String, dynamic> toCreateMap() => {
        ...toMap(),
        'created_at': FieldValue.serverTimestamp(),
      };
}
