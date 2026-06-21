import 'package:depertin_web/navigation/painel_navigation_scope.dart';
import 'package:depertin_web/widgets/comercial/comercial_busca_cliente_modal.dart';
import 'package:depertin_web/widgets/comercial/comercial_conceder_credito_modal.dart';
import 'package:depertin_web/widgets/comercial/comercial_exportar_modal.dart';
import 'package:depertin_web/widgets/comercial/comercial_historico_vendas_modal.dart';
import 'package:depertin_web/widgets/comercial/comercial_pendencias_modal.dart';
import 'package:depertin_web/widgets/comercial_cliente_form_modal.dart';
import 'package:depertin_web/widgets/comercial_cliente_recebimento_modal.dart';
import 'package:depertin_web/widgets/dipertin_painel_feedback.dart';
import 'package:flutter/material.dart';

/// Ações rápidas do Dashboard Comercial.
abstract final class ComercialDashboardAcoes {
  static void novaVenda(BuildContext context) {
    context.navegarPainel('/pdv');
  }

  static Future<bool> novoCliente(
    BuildContext context, {
    required String lojaId,
  }) async {
    final r = await mostrarComercialClienteFormModal(context, lojaId: lojaId);
    return r != null;
  }

  static Future<bool> concederCredito(
    BuildContext context, {
    required String lojaId,
  }) =>
      mostrarComercialConcederCreditoModal(context, lojaId: lojaId);

  static Future<void> verPendencias(
    BuildContext context, {
    required String lojaId,
  }) =>
      mostrarComercialPendenciasModal(context, lojaId: lojaId);

  static Future<bool> receberPagamento(
    BuildContext context, {
    required String lojaId,
  }) async {
    final cliente = await mostrarComercialBuscaClienteModal(
      context,
      lojaId: lojaId,
      titulo: 'Receber pagamento',
      subtitulo: 'Selecione o cliente',
      icone: Icons.payments_rounded,
    );
    if (cliente == null || !context.mounted) return false;

    await mostrarComercialClienteRecebimentoModal(
      context,
      lojaId: lojaId,
      cliente: cliente,
    );
    return true;
  }

  static void relatorios(BuildContext context) {
    DiPertinPainelFeedback.info(context, 'Relatórios comerciais em breve.');
  }

  static Future<void> historicoVendas(
    BuildContext context, {
    required String lojaId,
  }) =>
      mostrarComercialHistoricoVendasModal(context, lojaId: lojaId);

  static Future<void> exportarRelatorio(
    BuildContext context, {
    required String lojaId,
  }) =>
      mostrarComercialExportarModal(context, lojaId: lojaId);
}
