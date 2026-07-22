import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:depertin_web/models/comercial_cliente.dart';
import 'package:depertin_web/models/comercial_credito.dart';
import 'package:depertin_web/models/comercial_pendencia_data.dart';
import 'package:depertin_web/services/comercial_config_service.dart';
import 'package:depertin_web/utils/firestore_web_safe.dart';
import 'package:flutter/foundation.dart';

/// Serviço de agregação de pendências financeiras da Gestão Comercial.
///
/// Toda a lógica é local (não altera Firestore, não altera services existentes).
/// Consome dados de `parcelas_cliente` e `clientes_comercial` já estabelecidos.
abstract final class ComercialPendenciasService {
  static CollectionReference<Map<String, dynamic>> _parcelasCol(
    String lojaId,
  ) =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(lojaId)
          .collection('parcelas_cliente');

  static CollectionReference<Map<String, dynamic>> _clientesCol(
    String lojaId,
  ) =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(lojaId)
          .collection('clientes_comercial');

  static CollectionReference<Map<String, dynamic>> _recebimentosCol(
    String lojaId,
  ) =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(lojaId)
          .collection('recebimentos_cliente');

  /// Carga única do resumo com parcelas agrupadas por cliente.
  static Future<PendenciaFinanceiraResumo> carregarResumo(
    String lojaId,
  ) async {
    if (lojaId.isEmpty) return PendenciaFinanceiraResumo.vazio;
    return _calcularResumo(lojaId);
  }

  /// Stream em tempo real que recalcula o resumo sempre que as parcelas
  /// do cliente forem alteradas no Firestore (nova venda, pagamento, etc.).
  static Stream<PendenciaFinanceiraResumo> streamResumo(String lojaId) {
    if (lojaId.isEmpty) {
      return Stream.value(PendenciaFinanceiraResumo.vazio);
    }
    return _parcelasCol(lojaId).snapshots().asyncMap((_) async {
      return _calcularResumo(lojaId);
    });
  }

  static Future<PendenciaFinanceiraResumo> _calcularResumo(
    String lojaId,
  ) async {
    try {
      final config =
          await ComercialConfigService.carregarJurosMultaConfig(lojaId);
      final [
        parcelasSnap,
        clientesSnap,
        recebSnap,
        recebSnapPassado,
      ] = await Future.wait([
        _parcelasCol(lojaId).get(),
        _clientesCol(lojaId).get(),
        // 3. Recebimentos do mês
        _recebimentosCol(lojaId)
            .where('data_pagamento',
                isGreaterThanOrEqualTo:
                    Timestamp.fromDate(_inicioMes()))
            .get(),
        // 4. Recebimentos do mês anterior (variação)
        _recebimentosCol(lojaId)
            .where('data_pagamento',
                isGreaterThanOrEqualTo:
                    Timestamp.fromDate(_inicioMesPassado()))
            .where('data_pagamento',
                isLessThanOrEqualTo:
                    Timestamp.fromDate(_fimMesPassado()))
            .get(),
      ]);

      final parcelas = parcelasSnap.docs
          .map((d) =>
              ComercialParcelaCliente.fromDoc(d.id, safeWebDocData(d)))
          .toList();
      final mapaClientes = <String, ComercialCliente>{};
      for (final d in clientesSnap.docs) {
        final c = ComercialCliente.fromDoc(d.id, lojaId, safeWebDocData(d));
        mapaClientes[c.id] = c;
      }

      var totalPagoMes = 0.0;
      for (final d in recebSnap.docs) {
        final m = safeWebDocData(d);
        totalPagoMes += ((m['valor_pago'] as num?)?.toDouble() ?? 0);
      }
      var totalPagoMesPassado = 0.0;
      for (final d in recebSnapPassado.docs) {
        final m = safeWebDocData(d);
        totalPagoMesPassado += ((m['valor_pago'] as num?)?.toDouble() ?? 0);
      }

      // 5. Agregar totais gerais e agrupar parcelas por cliente
      final hoje = DateTime.now();
      final hojeClean = DateTime(hoje.year, hoje.month, hoje.day);
      final daqui7 = hojeClean.add(const Duration(days: 7));

      var totalVencidas = 0.0;
      var totalVenceHoje = 0.0;
      var totalVence7Dias = 0.0;
      var totalEmAbertoGeral = 0.0;
      var qtdVencidas = 0;
      var qtdVenceHoje = 0;
      var qtdVence7Dias = 0;
      var qtdEmAberto = 0;

      final parcelasPorCliente = <String, List<ComercialParcelaCliente>>{};
      final debtMap = <String, double>{};

      for (final p in parcelas) {
        final st = p.status.toLowerCase();
        if (st == 'pago' || st == 'cancelado' || st == 'estornado') continue;
        if (p.valorEmAberto <= 0.009) continue;
        final venc = DateTime(
          p.dataVencimento.year,
          p.dataVencimento.month,
          p.dataVencimento.day,
        );
        totalEmAbertoGeral += p.valorEmAberto;
        qtdEmAberto++;
        if (venc.isBefore(hojeClean)) {
          totalVencidas += p.valorEmAberto;
          qtdVencidas++;
        } else if (venc.isAtSameMomentAs(hojeClean)) {
          totalVenceHoje += p.valorEmAberto;
          qtdVenceHoje++;
        } else if (venc.isBefore(daqui7) || venc.isAtSameMomentAs(daqui7)) {
          totalVence7Dias += p.valorEmAberto;
          qtdVence7Dias++;
        }
        parcelasPorCliente.putIfAbsent(p.clienteId, () => []).add(p);
        debtMap.update(
          p.clienteId,
          (v) => v + p.valorEmAberto,
          ifAbsent: () => p.valorEmAberto,
        );
      }

      // 6. Criar um PendenciaFinanceiraCliente por cliente
      final itens = <PendenciaFinanceiraCliente>[];
      for (final entry in parcelasPorCliente.entries) {
        final c = mapaClientes[entry.key];
        final parcelasCli = entry.value;
        final codigo = parcelasCli
            .map((p) => p.codigoVenda)
            .firstWhere((s) => s.isNotEmpty, orElse: () => '');
        itens.add(PendenciaFinanceiraCliente(
          clienteId: entry.key,
          clienteNome:
              c?.nome ?? 'Cliente #${entry.key.substring(0, 6)}',
          clienteCpf: c?.cpf,
          clienteTelefone: c?.telefone,
          clienteWhatsApp: (c?.whatsapp != null && c!.whatsapp!.trim().isNotEmpty)
              ? c.whatsapp
              : c?.telefone,
          clienteEmail: c?.email,
          parcelas: parcelasCli,
          codigoVenda: codigo,
          configJurosMulta: config,
        ));
      }

      itens.sort((a, b) {
        final prioA = _prioridadeStatus(a.status);
        final prioB = _prioridadeStatus(b.status);
        if (prioA != prioB) return prioA.compareTo(prioB);
        return a.dataVencimentoReferencia
            .compareTo(b.dataVencimentoReferencia);
      });

      // 7. Top debtors
      final topEntries = debtMap.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      final topDebtors = topEntries.take(5).map((e) {
        final c = mapaClientes[e.key];
        return TopDebtorInfo(
          clienteId: e.key,
          nome: c?.nome ?? 'Cliente',
          valorDevido: e.value,
          telefone: c?.telefone,
        );
      }).toList();

      final variacao = totalPagoMesPassado > 0
          ? ((totalPagoMes - totalPagoMesPassado) / totalPagoMesPassado) * 100
          : (totalPagoMes > 0 ? 100.0 : 0.0);

      return PendenciaFinanceiraResumo(
        totalVencidas: _round(totalVencidas),
        totalVenceHoje: _round(totalVenceHoje),
        totalVence7Dias: _round(totalVence7Dias),
        totalEmAberto: _round(totalEmAbertoGeral),
        totalPagoMes: _round(totalPagoMes),
        quantidadeVencidas: qtdVencidas,
        quantidadeVenceHoje: qtdVenceHoje,
        quantidadeVence7Dias: qtdVence7Dias,
        quantidadeEmAberto: qtdEmAberto,
        variacaoPagoMes: _round(variacao),
        itens: itens,
        topDebtors: topDebtors,
      );
    } catch (e, stack) {
      debugPrint('[PendenciasService] Erro ao calcular resumo: $e\n$stack');
      return PendenciaFinanceiraResumo.vazio;
    }
  }

  static DateTime _inicioMes() =>
      DateTime(DateTime.now().year, DateTime.now().month, 1);
  static DateTime _inicioMesPassado() =>
      DateTime(DateTime.now().year, DateTime.now().month - 1, 1);
  static DateTime _fimMesPassado() =>
      DateTime(DateTime.now().year, DateTime.now().month, 1)
          .subtract(const Duration(days: 1));

  static int _prioridadeStatus(String status) {
    switch (status) {
      case 'vencido':
        return 0;
      case 'vence_hoje':
        return 1;
      case 'em_aberto':
        return 2;
      case 'parcialmente_pago':
        return 3;
      case 'pago':
        return 4;
      default:
        return 5;
    }
  }

  static double _round(double v) => (v * 100).roundToDouble() / 100;

  static String formatarMoeda(double v) {
    return 'R\$ ${v.toStringAsFixed(2).replaceAll('.', ',')}';
  }

  static String formatarPercentual(double v) {
    final sinal = v >= 0 ? '+' : '';
    return '$sinal${v.toStringAsFixed(1)}%';
  }

  static String formatarData(DateTime d) {
    return '${d.day.toString().padLeft(2, '0')}/'
        '${d.month.toString().padLeft(2, '0')}/'
        '${d.year}';
  }
}
