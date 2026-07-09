import 'dart:ui' show Color;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

/// Módulo comercial ao qual a cobrança pertence. Cada módulo tem cor própria.
enum ModuloCobranca {
  gestaoComercial('gestao_comercial', 'Gestão Comercial', Color(0xFF6A1B9A),
      Color(0xFFF1E9FF)),
  pdv('pdv', 'PDV', Color(0xFFFF8F00), Color(0xFFFFF3E6)),
  gestaoEntregas('gestao_entregas', 'Gestão de Entregas', Color(0xFF16A34A),
      Color(0xFFE8F5E9)),
  financeiro('financeiro', 'Financeiro', Color(0xFF0EA5E9), Color(0xFFE6F6FE)),
  marketing('marketing', 'Marketing', Color(0xFFEC4899), Color(0xFFFDEAF4));

  const ModuloCobranca(this.codigo, this.rotulo, this.cor, this.fundo);

  final String codigo;
  final String rotulo;
  final Color cor;
  final Color fundo;

  static ModuloCobranca fromCodigo(String? c) {
    return ModuloCobranca.values.firstWhere(
      (m) => m.codigo == c,
      orElse: () => ModuloCobranca.gestaoComercial,
    );
  }
}

/// Situação de pagamento da cobrança. Cada status tem cor/fundo próprios.
enum StatusCobranca {
  emAberto('em_aberto', 'Em aberto', Color(0xFF0EA5E9), Color(0xFFE6F6FE)),
  vencida('vencida', 'Vencida', Color(0xFFF04438), Color(0xFFFEF2F2)),
  paga('paga', 'Paga', Color(0xFF16A34A), Color(0xFFE8F5E9)),
  cancelada('cancelada', 'Cancelada', Color(0xFF94A3B8), Color(0xFFF1F5F9)),
  reembolsada(
      'reembolsada', 'Reembolsada', Color(0xFFFF8F00), Color(0xFFFFF3E6));

  const StatusCobranca(this.codigo, this.rotulo, this.cor, this.fundo);

  final String codigo;
  final String rotulo;
  final Color cor;
  final Color fundo;

  static StatusCobranca fromCodigo(String? c) {
    return StatusCobranca.values.firstWhere(
      (s) => s.codigo == c,
      orElse: () => StatusCobranca.emAberto,
    );
  }
}

/// Cobrança de assinatura/módulo contratado.
/// Coleção Firestore: `assinaturas_cobrancas/{id}`
class CobrancaAssinatura {
  const CobrancaAssinatura({
    required this.id,
    required this.assinaturaId,
    required this.fatura,
    required this.clienteNome,
    required this.clienteEmail,
    required this.planoNome,
    required this.modulo,
    required this.vencimento,
    required this.valor,
    required this.status,
  });

  final String id;
  final String assinaturaId;
  final String fatura;
  final String clienteNome;
  final String clienteEmail;
  final String planoNome;
  final ModuloCobranca modulo;
  final DateTime vencimento;
  final double valor;
  final StatusCobranca status;

  static final NumberFormat _moeda =
      NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
  static final DateFormat _data = DateFormat('dd/MM/yyyy', 'pt_BR');

  String get valorExibicao => _moeda.format(valor);
  String get vencimentoExibicao => _data.format(vencimento);
  String get idCurto => id.length <= 8 ? id : id.substring(0, 8);

  /// Texto da situação de vencimento ("Em 2 dias" / "Venceu há 1 dia" / "Hoje").
  String get situacaoVencimento {
    if (status == StatusCobranca.paga) return 'Paga';
    if (status == StatusCobranca.cancelada) return 'Cancelada';
    if (status == StatusCobranca.reembolsada) return 'Reembolsada';
    final hoje = DateTime.now();
    final h = DateTime(hoje.year, hoje.month, hoje.day);
    final v = DateTime(vencimento.year, vencimento.month, vencimento.day);
    final dias = v.difference(h).inDays;
    if (dias == 0) return 'Vence hoje';
    if (dias > 0) return 'Em $dias ${dias == 1 ? 'dia' : 'dias'}';
    final atraso = -dias;
    return 'Venceu há $atraso ${atraso == 1 ? 'dia' : 'dias'}';
  }

  bool get situacaoVencida {
    if (status == StatusCobranca.vencida) return true;
    if (status == StatusCobranca.paga ||
        status == StatusCobranca.cancelada ||
        status == StatusCobranca.reembolsada) {
      return false;
    }
    final hoje = DateTime.now();
    final h = DateTime(hoje.year, hoje.month, hoje.day);
    final v = DateTime(vencimento.year, vencimento.month, vencimento.day);
    return v.isBefore(h);
  }

  static CobrancaAssinatura fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final d = doc.data() ?? {};
    final venc = d['vencimento'];
    return CobrancaAssinatura(
      id: doc.id,
      assinaturaId: d['assinatura_id'] as String? ?? '',
      fatura: d['fatura'] as String? ?? '#FAT-000000',
      clienteNome: d['store_name'] as String? ?? 'Loja',
      clienteEmail: d['email'] as String? ?? '',
      planoNome: d['plano_nome'] as String? ?? d['plan_name'] as String? ?? '',
      modulo: ModuloCobranca.fromCodigo(d['modulo'] as String?),
      vencimento:
          venc is Timestamp ? venc.toDate() : DateTime.now(),
      valor: (d['valor'] as num?)?.toDouble() ?? 0,
      status: StatusCobranca.fromCodigo(d['status'] as String?),
    );
  }
}
