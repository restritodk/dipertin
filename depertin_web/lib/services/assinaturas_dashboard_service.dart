import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/assinaturas_dashboard_resumo.dart';
import '../models/cliente_assinatura_model.dart';
import '../models/plano_assinatura_model.dart';
import 'assinaturas_clientes_service.dart';
import 'modulos_planos_service.dart';

/// Agrega KPIs do dashboard a partir de `modulos_planos` e `assinaturas_clientes`.
abstract final class AssinaturasDashboardService {
  static Stream<AssinaturasDashboardResumo> streamResumo() {
    return Stream.multi((controller) {
      QuerySnapshot<Map<String, dynamic>>? planos;
      QuerySnapshot<Map<String, dynamic>>? clientes;

      void emitir() {
        if (planos == null || clientes == null) return;
        controller.add(_calcular(planos!, clientes!));
      }

      final subPlanos = ModulosPlanosService.stream().listen(
        (snap) {
          planos = snap;
          emitir();
        },
        onError: controller.addError,
      );

      final subClientes = AssinaturasClientesService.stream().listen(
        (snap) {
          clientes = snap;
          emitir();
        },
        onError: controller.addError,
      );

      controller.onCancel = () {
        subPlanos.cancel();
        subClientes.cancel();
      };
    });
  }

  static AssinaturasDashboardResumo _calcular(
    QuerySnapshot<Map<String, dynamic>> planosSnap,
    QuerySnapshot<Map<String, dynamic>> clientesSnap,
  ) {
    final planosAtivos = planosSnap.docs
        .map(PlanoAssinaturaModel.fromFirestore)
        .where((p) => p.ativo)
        .length;

    final clientes = clientesSnap.docs
        .map(ClienteAssinaturaModel.fromFirestore)
        .toList();

    final contratantes = clientes
        .where((c) => c.status == 'ativo' || c.status == 'em_atraso')
        .map((c) => c.storeId)
        .where((id) => id.isNotEmpty)
        .toSet()
        .length;

    final receita = clientes
        .where((c) => c.status == 'ativo' || c.status == 'em_atraso')
        .fold<double>(0, (total, c) => total + c.monthlyAmount);

    final inadimplentes =
        clientes.where((c) => c.status == 'em_atraso').length;

    final valorInad = clientes
        .where((c) => c.status == 'em_atraso')
        .fold<double>(0, (total, c) => total + c.monthlyAmount);

    final ativos = clientes.where((c) => c.status == 'ativo').length;
    final suspensos = clientes.where((c) => c.status == 'suspenso').length;
    final cancelados = clientes.where((c) => c.status == 'cancelado').length;
    final total = clientes.length;
    final taxaAdimplencia = total > 0 ? ((ativos / total) * 100).round() : 100;

    final pendencias = clientes
        .where((c) => c.status == 'em_atraso')
        .take(4)
        .toList();

    return AssinaturasDashboardResumo(
      planosAtivos: planosAtivos,
      lojasContratantes: contratantes,
      receitaMensal: receita,
      inadimplentes: inadimplentes,
      valorInadimplencia: valorInad,
      totalAssinaturas: total,
      assinaturasAtivas: ativos,
      assinaturasSuspensas: suspensos,
      assinaturasCanceladas: cancelados,
      taxaAdimplencia: taxaAdimplencia,
      ultimasAssinaturas: clientes.take(6).toList(),
      pendenciasInadimplencia: pendencias,
    );
  }
}
