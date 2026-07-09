import '../models/cliente_assinatura_model.dart';

/// KPIs agregados do dashboard de Gestão de Assinaturas.
class AssinaturasDashboardResumo {
  const AssinaturasDashboardResumo({
    required this.planosAtivos,
    required this.lojasContratantes,
    required this.receitaMensal,
    required this.inadimplentes,
    required this.valorInadimplencia,
    required this.totalAssinaturas,
    required this.assinaturasAtivas,
    required this.assinaturasSuspensas,
    required this.assinaturasCanceladas,
    required this.taxaAdimplencia,
    this.ultimasAssinaturas = const [],
    this.pendenciasInadimplencia = const [],
  });

  /// Planos ativos em `modulos_planos` (mesma métrica da tela Planos e Módulos).
  final int planosAtivos;
  final int lojasContratantes;
  final double receitaMensal;
  final int inadimplentes;
  final double valorInadimplencia;
  final int totalAssinaturas;
  final int assinaturasAtivas;
  final int assinaturasSuspensas;
  final int assinaturasCanceladas;
  /// Percentual de assinaturas com status `ativo` sobre o total.
  final int taxaAdimplencia;
  final List<ClienteAssinaturaModel> ultimasAssinaturas;
  final List<ClienteAssinaturaModel> pendenciasInadimplencia;

  static AssinaturasDashboardResumo vazio() => const AssinaturasDashboardResumo(
        planosAtivos: 0,
        lojasContratantes: 0,
        receitaMensal: 0,
        inadimplentes: 0,
        valorInadimplencia: 0,
        totalAssinaturas: 0,
        assinaturasAtivas: 0,
        assinaturasSuspensas: 0,
        assinaturasCanceladas: 0,
        taxaAdimplencia: 100,
      );

  /// Reconstrói com defaults — evita crash após hot reload com instância antiga.
  static AssinaturasDashboardResumo? tentarNormalizar(Object? raw) {
    if (raw is! AssinaturasDashboardResumo) return null;
    try {
      // Lê campos novos; instâncias pré-hot-reload lançam TypeError aqui.
      final _ = raw.taxaAdimplencia + raw.totalAssinaturas;
      return raw;
    } catch (_) {
      return null;
    }
  }
}
