import 'dart:ui' show Color;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

/// Situação de envio de uma nota fiscal.
enum SituacaoNfe {
  enviada('enviada', 'Enviada', Color(0xFF16A34A), Color(0xFFE8F5E9)),
  pendente('pendente', 'Pendente', Color(0xFFF59E0B), Color(0xFFFFF8E1)),
  erro('erro', 'Erro no envio', Color(0xFFDC2626), Color(0xFFFEF2F2)),
  reenviada('reenviada', 'Reenviada', Color(0xFF2563EB), Color(0xFFE6F0FF)),
  cancelada('cancelada', 'Cancelada', Color(0xFF94A3B8), Color(0xFFF1F5F9));

  const SituacaoNfe(this.codigo, this.rotulo, this.cor, this.fundo);
  final String codigo;
  final String rotulo;
  final Color cor;
  final Color fundo;

  static SituacaoNfe fromCodigo(String? c) {
    return SituacaoNfe.values.firstWhere(
      (s) => s.codigo == c,
      orElse: () => SituacaoNfe.pendente,
    );
  }
}

/// Nota fiscal emitida para um cliente.
class NotaFiscalModel {
  NotaFiscalModel({
    required this.id,
    required this.clienteAssinaturaId,
    required this.clienteStoreId,
    required this.clienteStoreName,
    required this.clienteCpfCnpj,
    required this.clienteEmail,
    this.numeroNfe,
    required this.situacao,
    required this.valor,
    this.dataEmissao,
    this.dataEnvio,
    this.xmlUrl,
    this.danfeUrl,
    this.motivoErro,
    this.tentativas = 0,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String clienteAssinaturaId;
  final String clienteStoreId;
  final String clienteStoreName;
  final String clienteCpfCnpj;
  final String clienteEmail;
  final String? numeroNfe;
  final SituacaoNfe situacao;
  final double valor;
  final Timestamp? dataEmissao;
  final Timestamp? dataEnvio;
  final String? xmlUrl;
  final String? danfeUrl;
  final String? motivoErro;
  final int tentativas;
  final Timestamp? createdAt;
  final Timestamp? updatedAt;

  String get numeroNfeExibir => numeroNfe != null ? '#$numeroNfe' : '—';
  String get dataEmissaoExibir =>
      dataEmissao != null ? DateFormat('dd/MM/yyyy').format(dataEmissao!.toDate()) : '—';
  String get dataEnvioExibir =>
      dataEnvio != null ? DateFormat('dd/MM/yyyy').format(dataEnvio!.toDate()) : '—';

  Map<String, dynamic> toMap() => {
        'cliente_assinatura_id': clienteAssinaturaId,
        'cliente_store_id': clienteStoreId,
        'cliente_store_name': clienteStoreName,
        'cliente_cpf_cnpj': clienteCpfCnpj,
        'cliente_email': clienteEmail,
        'numero_nfe': numeroNfe,
        'situacao': situacao.codigo,
        'valor': valor,
        'data_emissao': dataEmissao ?? FieldValue.serverTimestamp(),
        'data_envio': dataEnvio ?? FieldValue.serverTimestamp(),
        'xml_url': xmlUrl,
        'danfe_url': danfeUrl,
        'motivo_erro': motivoErro,
        'tentativas': tentativas,
        'created_at': createdAt ?? FieldValue.serverTimestamp(),
        'updated_at': updatedAt ?? FieldValue.serverTimestamp(),
      };

  static NotaFiscalModel fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};
    return NotaFiscalModel(
      id: doc.id,
      clienteAssinaturaId: d['cliente_assinatura_id'] as String? ?? '',
      clienteStoreId: d['cliente_store_id'] as String? ?? '',
      clienteStoreName: d['cliente_store_name'] as String? ?? '',
      clienteCpfCnpj: d['cliente_cpf_cnpj'] as String? ?? '',
      clienteEmail: d['cliente_email'] as String? ?? '',
      numeroNfe: d['numero_nfe'] as String?,
      situacao: SituacaoNfe.fromCodigo(d['situacao'] as String?),
      valor: (d['valor'] as num?)?.toDouble() ?? 0,
      dataEmissao: d['data_emissao'] as Timestamp?,
      dataEnvio: d['data_envio'] as Timestamp?,
      xmlUrl: d['xml_url'] as String?,
      danfeUrl: d['danfe_url'] as String?,
      motivoErro: d['motivo_erro'] as String?,
      tentativas: (d['tentativas'] as num?)?.toInt() ?? 0,
      createdAt: d['created_at'] as Timestamp?,
      updatedAt: d['updated_at'] as Timestamp?,
    );
  }
}
