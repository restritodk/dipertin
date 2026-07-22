import 'dart:ui' show Color;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

/// Evento do histórico da assinatura (`historico[]` no documento).
class HistoricoAssinaturaEvento {
  const HistoricoAssinaturaEvento({
    required this.tipo,
    required this.descricao,
    this.dataEm,
  });

  final String tipo;
  final String descricao;
  final Timestamp? dataEm;

  String get dataExibir {
    if (dataEm == null) return '—';
    return DateFormat('dd/MM/yyyy').format(dataEm!.toDate());
  }

  Map<String, dynamic> toMap() => {
        'tipo': tipo,
        'descricao': descricao,
        'data_em': dataEm ?? Timestamp.now(),
      };

  static HistoricoAssinaturaEvento fromMap(Map<String, dynamic> m) {
    return HistoricoAssinaturaEvento(
      tipo: m['tipo'] as String? ?? 'status',
      descricao: m['descricao'] as String? ?? '',
      dataEm: m['data_em'] is Timestamp ? m['data_em'] as Timestamp : null,
    );
  }

  static List<HistoricoAssinaturaEvento> listaFromFirestore(List<dynamic>? raw) {
    if (raw == null) return const [];
    return raw
        .whereType<Map>()
        .map((e) => HistoricoAssinaturaEvento.fromMap(Map<String, dynamic>.from(e)))
        .toList();
  }
}

/// Assinatura de módulo/plano contratada por uma loja.
/// Coleção: `assinaturas_clientes/{id}`
class ClienteAssinaturaModel {
  ClienteAssinaturaModel({
    required this.id,
    required this.storeId,
    required this.storeName,
    required this.ownerName,
    required this.phone,
    required this.email,
    this.cpfCnpj,
    required this.addressStreet,
    required this.addressCity,
    required this.addressState,
    required this.planId,
    required this.planName,
    required this.status,
    required this.monthlyAmount,
    this.nextBillingDate,
    this.lastPaymentDate,
    this.createdAt,
    this.updatedAt,
    this.blockedAt,
    this.blockReason,
    this.toleranciaDias = 3,
    this.multaPercentual = 0,
    this.jurosPercentual = 0,
    this.suspenderAposDias,
    this.gateway = 'Mercado Pago',
    this.historico = const [],
    this.modulosExtras = const [],
    // ── Campos de Cartão Recorrente (Etapa 3.2.3) ──
    this.mpPreapprovalId,
    this.tipoCobranca,
    this.cartaoLastFour,
    this.cartaoBandeira,
    this.proximaCobrancaRecorrente,
    this.autorizacaoRecorrenteAceita = false,
    this.autorizacaoRecorrenteEm,
  });

  final String id;
  final String storeId;
  final String storeName;
  final String ownerName;
  final String phone;
  final String email;
  final String? cpfCnpj;
  final String addressStreet;
  final String addressCity;
  final String addressState;
  final String planId;
  final String planName;
  /// `ativo` | `em_atraso` | `suspenso` | `cancelado` | `pagamento_pendente`
  final String status;
  final double monthlyAmount;
  final Timestamp? nextBillingDate;
  final Timestamp? lastPaymentDate;
  final Timestamp? createdAt;
  final Timestamp? updatedAt;
  final Timestamp? blockedAt;
  final String? blockReason;
  final int toleranciaDias;
  final double multaPercentual;
  final double jurosPercentual;
  /// Dias após vencimento para suspender automaticamente
  final int? suspenderAposDias;
  final String gateway;
  final List<HistoricoAssinaturaEvento> historico;
  final List<String> modulosExtras;

  // ── Campos de Cartão Recorrente (preapproval) ──
  /// ID do preapproval no Mercado Pago. Se presente, é recorrente.
  final String? mpPreapprovalId;

  /// Tipo de cobrança: 'pix' | 'cartao_avulso' | 'cartao_recorrente'
  final String? tipoCobranca;

  /// Últimos 4 dígitos do cartão salvo (não é dado sensível).
  final String? cartaoLastFour;

  /// Bandeira do cartão (visa, master, elo, etc).
  final String? cartaoBandeira;

  /// Próxima data de cobrança recorrente (pode diferir de nextBillingDate).
  final Timestamp? proximaCobrancaRecorrente;

  /// Se o lojista aceitou explicitamente a cobrança automática (LGPD).
  final bool autorizacaoRecorrenteAceita;

  /// Quando foi aceito.
  final Timestamp? autorizacaoRecorrenteEm;

  // ── Getters derivados de Cartão Recorrente ──

  /// True se a assinatura é do tipo cartão recorrente.
  bool get ehCartaoRecorrente => tipoCobranca == "cartao_recorrente";

  /// True se possui preapproval (assinatura recorrente ativa).
  bool get temPreapproval =>
      mpPreapprovalId != null && mpPreapprovalId!.isNotEmpty;

  // ── Propriedades computadas ──

  /// Dias corridos desde o vencimento (negativo = ainda não venceu)
  int get diasAposVencimento {
    if (nextBillingDate == null) return 0;
    final venc = nextBillingDate!.toDate();
    // Normaliza para meia-noite do dia do vencimento
    final vencNormalizado = DateTime(venc.year, venc.month, venc.day);
    final hoje = DateTime.now();
    final hojeNormalizado = DateTime(hoje.year, hoje.month, hoje.day);
    return hojeNormalizado.difference(vencNormalizado).inDays;
  }

  /// Dias até o próximo vencimento (negativo = já venceu)
  int get diasAteVencimento {
    if (nextBillingDate == null) return 0;
    final venc = nextBillingDate!.toDate();
    final vencNormalizado = DateTime(venc.year, venc.month, venc.day);
    final hoje = DateTime.now();
    final hojeNormalizado = DateTime(hoje.year, hoje.month, hoje.day);
    return vencNormalizado.difference(hojeNormalizado).inDays;
  }

  /// Quantos dias de tolerância já foram utilizados
  int get diasToleranciaUtilizados {
    final atraso = diasAposVencimento;
    if (atraso <= 0) return 0;
    return atraso.clamp(0, toleranciaDias);
  }

  /// True se está dentro do período de tolerância
  bool get emTolerancia => diasAposVencimento > 0 && diasAposVencimento <= toleranciaDias;

  /// Dias em atraso REAL (após tolerância)
  int get diasEmAtrasoReal {
    final atraso = diasAposVencimento;
    if (atraso <= toleranciaDias) return 0;
    return atraso - toleranciaDias;
  }

  /// Multa calculada
  double get multaCalculada {
    if (diasEmAtrasoReal <= 0) return 0;
    return monthlyAmount * (multaPercentual / 100);
  }

  /// Juros calculados (ao dia)
  double get jurosCalculados {
    if (diasEmAtrasoReal <= 0) return 0;
    return monthlyAmount * (jurosPercentual / 100) * diasEmAtrasoReal;
  }

  /// Total atualizado com multa + juros
  double get totalAtualizado {
    return monthlyAmount + multaCalculada + jurosCalculados;
  }

  /// Status de exibição dinâmico
  /// 'ativo' | 'vencer_em_breve' | 'vencido' | 'suspenso' | 'cancelado' | 'pagamento_pendente'
  String get statusExibicao {
    if (status == 'suspenso' ||
        status == 'cancelado' ||
        status == 'pagamento_pendente') {
      return status;
    }
    final dias = diasAteVencimento;
    if (dias > 7) return 'ativo';
    if (dias >= 0 && dias <= 7) return 'vencer_em_breve';
    // Venceu — verifica tolerância
    if (emTolerancia) return 'ativo';
    return 'vencido';
  }

  /// True se a assinatura deve estar bloqueada (suspender_apos_dias atingido)
  bool get deveEstarBloqueado {
    if (status == 'suspenso') return true;
    if (status == 'cancelado') return false;
    if (suspenderAposDias == null || suspenderAposDias! <= 0) return false;
    return diasAposVencimento > (toleranciaDias + suspenderAposDias!);
  }

  /// Rótulo amigável do status de exibição
  String get statusExibicaoRotulo {
    switch (statusExibicao) {
      case 'ativo':
        return 'Ativo';
      case 'vencer_em_breve':
        return 'Vence em breve';
      case 'vencido':
        return 'Vencido';
      case 'suspenso':
        return 'Suspenso';
      case 'cancelado':
        return 'Cancelado';
      case 'pagamento_pendente':
        return 'Pagamento pendente';
      default:
        return statusExibicao;
    }
  }

  /// Cor do status de exibição
  Color get statusExibicaoCor {
    switch (statusExibicao) {
      case 'vencer_em_breve':
        return const Color(0xFFFFA726);
      case 'vencido':
        return const Color(0xFFF04438);
      case 'suspenso':
        return const Color(0xFFF04438);
      case 'cancelado':
        return const Color(0xFF94A3B8);
      case 'pagamento_pendente':
        return const Color(0xFFFFA726);
      default:
        return const Color(0xFF16A34A);
    }
  }

  /// Fundo do status de exibição
  Color get statusExibicaoFundo {
    switch (statusExibicao) {
      case 'vencer_em_breve':
        return const Color(0xFFFFF8E1);
      case 'vencido':
        return const Color(0xFFFEF2F2);
      case 'suspenso':
        return const Color(0xFFFEF2F2);
      case 'cancelado':
        return const Color(0xFFF1F5F9);
      case 'pagamento_pendente':
        return const Color(0xFFFFF8E1);
      default:
        return const Color(0xFFE8F5E9);
    }
  }

  static String _formatarData(Timestamp? ts) {
    if (ts == null) return '—';
    return DateFormat('dd/MM/yyyy').format(ts.toDate());
  }

  String get nextBillingDateExibir => _formatarData(nextBillingDate);
  String get lastPaymentDateExibir => _formatarData(lastPaymentDate);
  String get createdAtExibir => _formatarData(createdAt);
  String get blockedAtExibir => _formatarData(blockedAt);

  /// Assinaturas canceladas não entram na listagem operacional do painel admin.
  bool get ehCancelada => status == 'cancelado';

  /// Checkout/pagamento ainda não concluído — não entra na listagem principal.
  bool get ehPagamentoPendente => status == 'pagamento_pendente';

  /// Listagem principal: ativas, em atraso, suspensas ou vencidas (não canceladas).
  bool get entraListagemPrincipalAdmin =>
      !ehCancelada && !ehPagamentoPendente;

  /// KPI “Clientes ativos” — somente status `ativo`.
  bool get contaComoClienteAtivoKpi => status == 'ativo';

  /// KPI receita recorrente — ativos + em atraso.
  bool get contaReceitaRecorrenteKpi =>
      status == 'ativo' || status == 'em_atraso';

  /// KPI “Planos ativos” / contratos em operação (exclui cancelado e pendente).
  bool get contaComoPlanoOperacionalKpi => entraListagemPrincipalAdmin;

  String get statusRotulo {
    switch (status) {
      case 'ativo':
        return 'Ativo';
      case 'em_atraso':
        return 'Em atraso';
      case 'suspenso':
        return 'Suspenso';
      case 'cancelado':
        return 'Cancelado';
      case 'pagamento_pendente':
        return 'Pagamento pendente';
      default:
        return status;
    }
  }

  Map<String, dynamic> toMap({String? createdBy}) => {
        'store_id': storeId,
        'store_name': storeName,
        'owner_name': ownerName,
        'phone': phone,
        'email': email,
        if (cpfCnpj != null) 'cpf_cnpj': cpfCnpj,
        'address_street': addressStreet,
        'address_city': addressCity,
        'address_state': addressState,
        'plan_id': planId,
        'plan_name': planName,
        'status': status,
        'monthly_amount': monthlyAmount,
        'next_billing_date': nextBillingDate,
        'last_payment_date': lastPaymentDate,
        'tolerancia_dias': toleranciaDias,
        'multa_percentual': multaPercentual,
        'juros_percentual': jurosPercentual,
        'suspender_apos_dias': suspenderAposDias,
        'gateway': gateway,
        'modulos_extras': modulosExtras,
        'historico': historico.map((h) => h.toMap()).toList(),
        if (createdBy != null) 'created_by': createdBy,
        'created_at': FieldValue.serverTimestamp(),
        'updated_at': FieldValue.serverTimestamp(),
      };

  static ClienteAssinaturaModel fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final d = doc.data() ?? {};
    return ClienteAssinaturaModel(
      id: doc.id,
      storeId: d['store_id'] as String? ?? '',
      storeName: d['store_name'] as String? ?? '',
      ownerName: d['owner_name'] as String? ?? '',
      phone: d['phone'] as String? ?? '',
      email: d['email'] as String? ?? '',
      cpfCnpj: d['cpf_cnpj'] as String?,
      addressStreet: d['address_street'] as String? ?? '',
      addressCity: d['address_city'] as String? ?? '',
      addressState: d['address_state'] as String? ?? '',
      planId: d['plan_id'] as String? ?? '',
      planName: d['plan_name'] as String? ?? '',
      status: d['status'] as String? ?? 'ativo',
      monthlyAmount: (d['monthly_amount'] as num?)?.toDouble() ?? 0,
      nextBillingDate: d['next_billing_date'] as Timestamp?,
      lastPaymentDate: d['last_payment_date'] as Timestamp?,
      createdAt: d['created_at'] as Timestamp?,
      updatedAt: d['updated_at'] as Timestamp?,
      blockedAt: d['blocked_at'] as Timestamp?,
      blockReason: d['block_reason'] as String?,
      toleranciaDias: (d['tolerancia_dias'] as num?)?.toInt() ?? 3,
      multaPercentual: (d['multa_percentual'] as num?)?.toDouble() ?? 0,
      jurosPercentual: (d['juros_percentual'] as num?)?.toDouble() ?? 0,
      suspenderAposDias: (d['suspender_apos_dias'] as num?)?.toInt(),
      gateway: d['gateway'] as String? ?? 'Mercado Pago',
      historico: HistoricoAssinaturaEvento.listaFromFirestore(
        d['historico'] as List<dynamic>?,
      ),
      modulosExtras:
          (d['modulos_extras'] as List<dynamic>?)?.cast<String>() ?? const [],
      // Cartão recorrente (campos opcionais — compatibilidade)
      mpPreapprovalId: d['mp_preapproval_id'] as String?,
      tipoCobranca: d['tipo_cobranca'] as String?,
      cartaoLastFour: d['cartao_last_four'] as String?,
      cartaoBandeira: d['cartao_bandeira'] as String?,
      proximaCobrancaRecorrente: d['proxima_cobranca_recorrente'] as Timestamp?,
      autorizacaoRecorrenteAceita:
          d['autorizacao_recorrente_aceita'] as bool? ?? false,
      autorizacaoRecorrenteEm: d['autorizacao_recorrente_em'] as Timestamp?,
    );
  }
}
