import 'dart:math';
import 'comercial_cliente.dart';
import 'comercial_credito.dart';

// -----------------------------------------------------------------------------
// Configuração de juros e multa — carregada do Firestore via
// ComercialConfigService (gestao_comercial_configuracoes/{lojaId}).
// -----------------------------------------------------------------------------

/// Configuração padrão de juros e multa por atraso.
///
/// Enquanto não existir tela de Configurações Comercial, usa valores seguros
/// com cobrança desativada.
class JurosMultaConfig {
  const JurosMultaConfig({
    this.cobrarMultaPorAtraso = false,
    this.percentualMulta = 0,
    this.cobrarJurosPorAtraso = false,
    this.percentualJurosAoDia = 0,
    this.diasTolerancia = 0,
    this.aplicarJurosAposVencimento = false,
  });

  final bool cobrarMultaPorAtraso;
  final double percentualMulta; // ex: 2 → 2%
  final bool cobrarJurosPorAtraso;
  final double percentualJurosAoDia; // ex: 0.033 → 0,033% ao dia
  final int diasTolerancia;
  final bool aplicarJurosAposVencimento;

  static const padrao = JurosMultaConfig();
}

/// Resultado do cálculo de juros e multa para uma parcela vencida.
class JurosMultaResultado {
  const JurosMultaResultado({
    this.multa = 0,
    this.juros = 0,
    this.valorAtualizado = 0,
    this.diasEmAtraso = 0,
    this.config = const JurosMultaConfig(),
  });

  final double multa;
  final double juros;
  final double valorAtualizado;
  final int diasEmAtraso;
  final JurosMultaConfig config;

  bool get temEncargos => multa > 0.009 || juros > 0.009;
}

/// Calcula juros e multa para uma parcela vencida.
///
/// Regras:
/// - Se a parcela estiver em dia, vence em breve ou vence hoje:
///   não cobra juros nem multa.
/// - Se vencida: aplica multa uma única vez + juros diário conforme
///   [JurosMultaConfig].
JurosMultaResultado calcularJurosMulta(
  double valorOriginal,
  DateTime dataVencimento, [
  JurosMultaConfig config = const JurosMultaConfig(),
]) {
  final hoje = DateTime.now();
  final hojeClean = DateTime(hoje.year, hoje.month, hoje.day);
  final venc = DateTime(
    dataVencimento.year,
    dataVencimento.month,
    dataVencimento.day,
  );

  // Se não venceu, sem encargos
  if (!venc.isBefore(hojeClean)) {
    return const JurosMultaResultado(valorAtualizado: 0);
  }

  final diasAtraso = hojeClean.difference(venc).inDays - config.diasTolerancia;
  final diasEfetivos = max(0, diasAtraso);

  double multa = 0;
  double juros = 0;

  if (config.cobrarMultaPorAtraso && config.percentualMulta > 0) {
    multa = valorOriginal * (config.percentualMulta / 100);
  }

  if (config.cobrarJurosPorAtraso && config.percentualJurosAoDia > 0) {
    juros = valorOriginal * (config.percentualJurosAoDia / 100) * diasEfetivos;
  }

  final valorAtualizado = valorOriginal + multa + juros;

  return JurosMultaResultado(
    multa: _arredondar(multa),
    juros: _arredondar(juros),
    valorAtualizado: _arredondar(valorAtualizado),
    diasEmAtraso: diasEfetivos,
    config: config,
  );
}

double _arredondar(double v) => (v * 100).roundToDouble() / 100;

/// Resumo completo das pendências financeiras da loja, agrupado por cliente.
class PendenciaFinanceiraResumo {
  const PendenciaFinanceiraResumo({
    this.totalVencidas = 0,
    this.totalVenceHoje = 0,
    this.totalVence7Dias = 0,
    this.totalEmAberto = 0,
    this.totalPagoMes = 0,
    this.quantidadeVencidas = 0,
    this.quantidadeVenceHoje = 0,
    this.quantidadeVence7Dias = 0,
    this.quantidadeEmAberto = 0,
    this.variacaoPagoMes = 0,
    this.itens = const [],
    this.topDebtors = const [],
  });

  final double totalVencidas;
  final double totalVenceHoje;
  final double totalVence7Dias;
  final double totalEmAberto;
  final double totalPagoMes;
  final int quantidadeVencidas;
  final int quantidadeVenceHoje;
  final int quantidadeVence7Dias;
  final int quantidadeEmAberto;
  final double variacaoPagoMes;
  final List<PendenciaFinanceiraCliente> itens;
  final List<TopDebtorInfo> topDebtors;

  static const vazio = PendenciaFinanceiraResumo();
}

/// Uma linha da tabela de pendências — representa UM cliente com suas parcelas
/// agrupadas.
class PendenciaFinanceiraCliente {
  PendenciaFinanceiraCliente({
    required this.clienteId,
    required this.clienteNome,
    this.clienteCpf,
    this.clienteTelefone,
    required this.parcelas,
    required this.codigoVenda,
    this.configJurosMulta = const JurosMultaConfig(),
  })  : quantidadeParcelas = parcelas.length,
        _valorUnitario = parcelas.isNotEmpty ? parcelas.first.valorParcela : 0,
        _valoresIguais = parcelas.every(
          (p) => (p.valorParcela - parcelas.first.valorParcela).abs() < 0.009),
        valorTotalEmAberto = _somarValor(parcelas),
        dataVencimentoReferencia =
            _calcularDataReferencia(parcelas),
        diasEmAberto = _calcularDias(parcelas) {
    // Calcula status e total atualizado com base nas parcelas
    final (sts, totalAtualizado, totalJuros, totalMulta) =
        _calcularStatusEValor(parcelas, configJurosMulta);
    status = sts;
    valorTotalAtualizado = totalAtualizado;
    totalJurosCalculado = totalJuros;
    totalMultaCalculada = totalMulta;
  }

  final String clienteId;
  final String clienteNome;
  final String? clienteCpf;
  final String? clienteTelefone;
  final List<ComercialParcelaCliente> parcelas;
  final String codigoVenda;
  final JurosMultaConfig configJurosMulta;

  // Campos calculados
  final double valorTotalEmAberto;
  final int quantidadeParcelas;
  final double _valorUnitario;
  final bool _valoresIguais;
  final DateTime dataVencimentoReferencia;
  late final String status;
  late final double valorTotalAtualizado;
  late final double totalJurosCalculado;
  late final double totalMultaCalculada;
  final int diasEmAberto;

  /// Rótulo da coluna "Plano contratado".
  String get planoLabel {
    if (quantidadeParcelas == 0) return '—';
    if (_valoresIguais) {
      return '${quantidadeParcelas}x de ${_moeda(_valorUnitario)}';
    }
    return '$quantidadeParcelas parcelas · ${_moeda(valorTotalEmAberto)} total';
  }

  /// Rótulo do status de exibição.
  String get statusRotulo {
    switch (status) {
      case 'vencido':
        return 'Vencido';
      case 'vence_hoje':
        return 'Vence hoje';
      case 'vence_em_breve':
        return 'Vence em breve';
      default:
        return 'Em dia';
    }
  }

  /// Constrói um [ComercialCliente] mínimo para abrir o modal de recebimento.
  ComercialCliente toComercialCliente() {
    return ComercialCliente(
      id: clienteId,
      lojaId: '',
      nome: clienteNome,
      cpf: clienteCpf,
      telefone: clienteTelefone,
    );
  }

  // ── helpers estáticos ──

  static double _somarValor(List<ComercialParcelaCliente> parcelas) {
    return parcelas.fold<double>(0, (s, p) => s + p.valorEmAberto);
  }

  static DateTime _calcularDataReferencia(
    List<ComercialParcelaCliente> parcelas,
  ) {
    final hoje = DateTime.now();
    final hojeClean = DateTime(hoje.year, hoje.month, hoje.day);
    DateTime? vencidaAntiga;
    DateTime? futuraProxima;
    for (final p in parcelas) {
      if (p.valorEmAberto <= 0.009) continue;
      final venc = DateTime(
        p.dataVencimento.year,
        p.dataVencimento.month,
        p.dataVencimento.day,
      );
      if (venc.isBefore(hojeClean)) {
        if (vencidaAntiga == null || venc.isBefore(vencidaAntiga)) {
          vencidaAntiga = venc;
        }
      } else {
        if (futuraProxima == null || venc.isBefore(futuraProxima)) {
          futuraProxima = venc;
        }
      }
    }
    return vencidaAntiga ?? futuraProxima ?? parcelas.first.dataVencimento;
  }

  /// Prioridade: Vencido > Vence hoje > Vence em breve > Em dia.
  static (String, double, double, double) _calcularStatusEValor(
    List<ComercialParcelaCliente> parcelas,
    JurosMultaConfig config,
  ) {
    final hoje = DateTime.now();
    final hojeClean = DateTime(hoje.year, hoje.month, hoje.day);
    var temVencida = false;
    var temVenceHoje = false;
    var temVenceBreve = false; // ≤ 4 dias
    double totalAtualizado = 0;
    double totalJuros = 0;
    double totalMulta = 0;

    for (final p in parcelas) {
      if (p.valorEmAberto <= 0.009) continue;
      final venc = DateTime(
        p.dataVencimento.year,
        p.dataVencimento.month,
        p.dataVencimento.day,
      );
      final diff = venc.difference(hojeClean).inDays;

      if (venc.isBefore(hojeClean)) {
        temVencida = true;
        // Aplica juros/multa apenas em vencidas
        final calc = calcularJurosMulta(p.valorEmAberto, p.dataVencimento, config);
        totalAtualizado += calc.valorAtualizado;
        totalJuros += calc.juros;
        totalMulta += calc.multa;
      } else {
        totalAtualizado += p.valorEmAberto;
        if (venc.isAtSameMomentAs(hojeClean)) {
          temVenceHoje = true;
        } else if (diff <= 4) {
          temVenceBreve = true;
        }
      }
    }

    String status;
    if (temVencida) {
      status = ComercialParcelaStatus.vencido;
    } else if (temVenceHoje) {
      status = 'vence_hoje';
    } else if (temVenceBreve) {
      status = 'vence_em_breve';
    } else {
      status = 'em_dia';
    }

    return (
      status,
      _round(totalAtualizado),
      _round(totalJuros),
      _round(totalMulta),
    );
  }

  static int _calcularDias(List<ComercialParcelaCliente> parcelas) {
    final hoje = DateTime.now();
    final hojeClean = DateTime(hoje.year, hoje.month, hoje.day);
    int maxDias = 0;
    for (final p in parcelas) {
      if (p.valorEmAberto <= 0.009) continue;
      final venc = DateTime(
        p.dataVencimento.year,
        p.dataVencimento.month,
        p.dataVencimento.day,
      );
      if (venc.isBefore(hojeClean)) {
        final diff = hojeClean.difference(venc).inDays;
        if (diff > maxDias) maxDias = diff;
      }
    }
    return maxDias;
  }

  static double _round(double v) => (v * 100).roundToDouble() / 100;
  static String _moeda(double v) =>
      'R\$ ${v.toStringAsFixed(2).replaceAll('.', ',')}';
}

/// Top devedor para o card lateral.
class TopDebtorInfo {
  const TopDebtorInfo({
    required this.clienteId,
    required this.nome,
    required this.valorDevido,
    this.telefone,
  });
  final String clienteId;
  final String nome;
  final double valorDevido;
  final String? telefone;
}
