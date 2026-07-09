/// Regra de aviso de atraso: quantos dias após o vencimento enviar.
class AtrasoRegra {
  const AtrasoRegra({required this.diasAposVencimento, this.ativo = true});

  final int diasAposVencimento;
  final bool ativo;

  Map<String, dynamic> toJson() => {
        'dias_apos_vencimento': diasAposVencimento,
        'ativo': ativo,
      };

  factory AtrasoRegra.fromJson(Map<String, dynamic> json) => AtrasoRegra(
        diasAposVencimento: (json['dias_apos_vencimento'] as num?)?.toInt() ?? 1,
        ativo: json['ativo'] as bool? ?? true,
      );
}

/// Snapshot de um plano selecionado, gravado no billing_settings.
class PlanoVinculadoSnapshot {
  const PlanoVinculadoSnapshot({
    required this.id,
    required this.nome,
    required this.valor,
    required this.ativo,
  });

  final String id;
  final String nome;
  final double valor;
  final bool ativo;

  Map<String, dynamic> toJson() => {
        'id': id,
        'nome': nome,
        'valor': valor,
        'ativo': ativo,
      };

  factory PlanoVinculadoSnapshot.fromJson(Map<String, dynamic> json) =>
      PlanoVinculadoSnapshot(
        id: json['id'] as String? ?? '',
        nome: json['nome'] as String? ?? '',
        valor: (json['valor'] as num?)?.toDouble() ?? 0,
        ativo: json['ativo'] as bool? ?? true,
      );
}

/// Modelo de configurações de cobranças (billing_settings).
/// Coleção Firestore: `billing_settings/{id}`
///
/// Por enquanto existe apenas um documento (id='global').
///
/// ⚠️ NUNCA usar FieldValue.serverTimestamp() dentro de toJson() —
/// este map é enviado via HTTP (jsonEncode) para a Cloud Function.
/// O serverTimestamp é adicionado pela Function no set/update do Firestore.
class BillingSettings {
  const BillingSettings({
    this.autoCobrancaAtivo = false,
    this.allPlans = true,
    this.selectedPlanIds = const [],
    this.selectedPlansSnapshot = const [],
    this.diaGeracao = 1,
    this.diasAntesVencimento = 5,
    this.autoEnviarEmail = true,
    this.remetente = 'naoresponder@dipertin.com.br',
    this.pagamentoConfirmadoAtivo = false,
    this.pagamentoConfirmadoEmail = true,
    this.atrasoAtivo = false,
    this.atrasoRegras = const [],
    this.cobrancaTemplateAtivo = true,
    this.pagamentoTemplateAtivo = true,
    this.atrasoTemplateAtivo = true,
    this.updatedAt,
    this.updatedBy = '',
  });

  final bool autoCobrancaAtivo;

  /// true = aplicar a todos os planos ativos
  final bool allPlans;

  /// IDs dos planos selecionados (vazio quando [allPlans] é true)
  final List<String> selectedPlanIds;

  /// Snapshot com nome, valor e ativo de cada plano selecionado
  final List<PlanoVinculadoSnapshot> selectedPlansSnapshot;

  final int diaGeracao;
  final int diasAntesVencimento;
  final bool autoEnviarEmail;
  final String remetente;
  final bool pagamentoConfirmadoAtivo;
  final bool pagamentoConfirmadoEmail;
  final bool atrasoAtivo;
  final List<AtrasoRegra> atrasoRegras;
  final bool cobrancaTemplateAtivo;
  final bool pagamentoTemplateAtivo;
  final bool atrasoTemplateAtivo;
  final DateTime? updatedAt;
  final String updatedBy;

  /// Gera o mapa para enviar via HTTP (jsonEncode) para a Cloud Function
  /// OU diretamente para o Firestore (SetOptions.merge).
  /// NUNCA retorna FieldValue ou Timestamp — apenas tipos primitivos.
  Map<String, dynamic> toJson() => {
        'auto_cobranca_ativo': autoCobrancaAtivo,
        'all_plans': allPlans,
        'selected_plan_ids': selectedPlanIds,
        'selected_plans_snapshot':
            selectedPlansSnapshot.map((p) => p.toJson()).toList(),
        'dia_geracao': diaGeracao,
        'dias_antes_vencimento': diasAntesVencimento,
        'auto_enviar_email': autoEnviarEmail,
        'remetente': remetente,
        'pagamento_confirmado_ativo': pagamentoConfirmadoAtivo,
        'pagamento_confirmado_email': pagamentoConfirmadoEmail,
        'atraso_ativo': atrasoAtivo,
        'atraso_regras': atrasoRegras.map((r) => r.toJson()).toList(),
        'cobranca_template_ativo': cobrancaTemplateAtivo,
        'pagamento_template_ativo': pagamentoTemplateAtivo,
        'atraso_template_ativo': atrasoTemplateAtivo,
        'updated_at': updatedAt?.toIso8601String(),
        'updated_by': updatedBy,
      };

  /// Constrói a partir de dados do Firestore (via snapshot).
  factory BillingSettings.fromFirestore(Map<String, dynamic> json) {
    final regrasRaw = json['atraso_regras'] as List<dynamic>?;
    final plansSnapshotRaw = json['selected_plans_snapshot'] as List<dynamic>?;
    final planIdsRaw = json['selected_plan_ids'] as List<dynamic>?;
    return BillingSettings(
      autoCobrancaAtivo: json['auto_cobranca_ativo'] as bool? ?? false,
      allPlans: json['all_plans'] as bool? ?? true,
      selectedPlanIds:
          planIdsRaw?.map((e) => e.toString()).toList() ?? const [],
      selectedPlansSnapshot: plansSnapshotRaw != null
          ? plansSnapshotRaw
              .map((e) =>
                  PlanoVinculadoSnapshot.fromJson(e as Map<String, dynamic>))
              .toList()
          : const [],
      diaGeracao: (json['dia_geracao'] as num?)?.toInt() ?? 1,
      diasAntesVencimento:
          (json['dias_antes_vencimento'] as num?)?.toInt() ?? 5,
      autoEnviarEmail: json['auto_enviar_email'] as bool? ?? true,
      remetente: json['remetente'] as String? ?? 'naoresponder@dipertin.com.br',
      pagamentoConfirmadoAtivo:
          json['pagamento_confirmado_ativo'] as bool? ?? false,
      pagamentoConfirmadoEmail:
          json['pagamento_confirmado_email'] as bool? ?? true,
      atrasoAtivo: json['atraso_ativo'] as bool? ?? false,
      atrasoRegras: regrasRaw != null
          ? regrasRaw
              .map((e) => AtrasoRegra.fromJson(e as Map<String, dynamic>))
              .toList()
          : const [],
      cobrancaTemplateAtivo: json['cobranca_template_ativo'] as bool? ?? true,
      pagamentoTemplateAtivo:
          json['pagamento_template_ativo'] as bool? ?? true,
      atrasoTemplateAtivo: json['atraso_template_ativo'] as bool? ?? true,
      updatedAt: _parseTimestamp(json['updated_at']),
      updatedBy: json['updated_by'] as String? ?? '',
    );
  }

  /// Constrói a partir de resposta da Cloud Function (JSON puro).
  factory BillingSettings.fromCloudFunction(Map<String, dynamic> json) {
    final regrasRaw = json['atraso_regras'] as List<dynamic>?;
    final plansSnapshotRaw = json['selected_plans_snapshot'] as List<dynamic>?;
    final planIdsRaw = json['selected_plan_ids'] as List<dynamic>?;
    return BillingSettings(
      autoCobrancaAtivo: json['auto_cobranca_ativo'] as bool? ?? false,
      allPlans: json['all_plans'] as bool? ?? true,
      selectedPlanIds:
          planIdsRaw?.map((e) => e.toString()).toList() ?? const [],
      selectedPlansSnapshot: plansSnapshotRaw != null
          ? plansSnapshotRaw
              .map((e) =>
                  PlanoVinculadoSnapshot.fromJson(e as Map<String, dynamic>))
              .toList()
          : const [],
      diaGeracao: (json['dia_geracao'] as num?)?.toInt() ?? 1,
      diasAntesVencimento:
          (json['dias_antes_vencimento'] as num?)?.toInt() ?? 5,
      autoEnviarEmail: json['auto_enviar_email'] as bool? ?? true,
      remetente: json['remetente'] as String? ?? 'naoresponder@dipertin.com.br',
      pagamentoConfirmadoAtivo:
          json['pagamento_confirmado_ativo'] as bool? ?? false,
      pagamentoConfirmadoEmail:
          json['pagamento_confirmado_email'] as bool? ?? true,
      atrasoAtivo: json['atraso_ativo'] as bool? ?? false,
      atrasoRegras: regrasRaw != null
          ? regrasRaw
              .map((e) => AtrasoRegra.fromJson(e as Map<String, dynamic>))
              .toList()
          : const [],
      cobrancaTemplateAtivo: json['cobranca_template_ativo'] as bool? ?? true,
      pagamentoTemplateAtivo:
          json['pagamento_template_ativo'] as bool? ?? true,
      atrasoTemplateAtivo: json['atraso_template_ativo'] as bool? ?? true,
      updatedAt: _parseTimestamp(json['updated_at']),
      updatedBy: json['updated_by'] as String? ?? '',
    );
  }

  static DateTime? _parseTimestamp(dynamic v) {
    if (v == null) return null;
    if (v is String) return DateTime.tryParse(v);
    if (v.runtimeType.toString().contains('Timestamp')) {
      return (v as dynamic).toDate() as DateTime?;
    }
    return null;
  }

  BillingSettings copyWith({
    bool? autoCobrancaAtivo,
    bool? allPlans,
    List<String>? selectedPlanIds,
    List<PlanoVinculadoSnapshot>? selectedPlansSnapshot,
    int? diaGeracao,
    int? diasAntesVencimento,
    bool? autoEnviarEmail,
    String? remetente,
    bool? pagamentoConfirmadoAtivo,
    bool? pagamentoConfirmadoEmail,
    bool? atrasoAtivo,
    List<AtrasoRegra>? atrasoRegras,
    bool? cobrancaTemplateAtivo,
    bool? pagamentoTemplateAtivo,
    bool? atrasoTemplateAtivo,
    String? updatedBy,
  }) =>
      BillingSettings(
        autoCobrancaAtivo: autoCobrancaAtivo ?? this.autoCobrancaAtivo,
        allPlans: allPlans ?? this.allPlans,
        selectedPlanIds: selectedPlanIds ?? this.selectedPlanIds,
        selectedPlansSnapshot:
            selectedPlansSnapshot ?? this.selectedPlansSnapshot,
        diaGeracao: diaGeracao ?? this.diaGeracao,
        diasAntesVencimento: diasAntesVencimento ?? this.diasAntesVencimento,
        autoEnviarEmail: autoEnviarEmail ?? this.autoEnviarEmail,
        remetente: remetente ?? this.remetente,
        pagamentoConfirmadoAtivo:
            pagamentoConfirmadoAtivo ?? this.pagamentoConfirmadoAtivo,
        pagamentoConfirmadoEmail:
            pagamentoConfirmadoEmail ?? this.pagamentoConfirmadoEmail,
        atrasoAtivo: atrasoAtivo ?? this.atrasoAtivo,
        atrasoRegras: atrasoRegras ?? this.atrasoRegras,
        cobrancaTemplateAtivo:
            cobrancaTemplateAtivo ?? this.cobrancaTemplateAtivo,
        pagamentoTemplateAtivo:
            pagamentoTemplateAtivo ?? this.pagamentoTemplateAtivo,
        atrasoTemplateAtivo:
            atrasoTemplateAtivo ?? this.atrasoTemplateAtivo,
        updatedBy: updatedBy ?? this.updatedBy,
      );
}
