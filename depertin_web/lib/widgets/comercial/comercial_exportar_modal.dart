import 'package:depertin_web/services/comercial_clientes_service.dart';
import 'package:depertin_web/services/comercial_credito_service.dart';
import 'package:depertin_web/theme/painel_admin_theme.dart';
import 'package:depertin_web/utils/csv_download.dart';
import 'package:depertin_web/widgets/comercial/comercial_modal_ui.dart';
import 'package:depertin_web/widgets/dipertin_painel_feedback.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

/// Exportação CSV básica do módulo comercial.
Future<void> mostrarComercialExportarModal(
  BuildContext context, {
  required String lojaId,
}) async {
  await mostrarComercialModalShell<void>(
    context,
    maxWidth: 520,
    child: _ExportarBody(lojaId: lojaId),
  );
}

class _ExportarBody extends StatefulWidget {
  const _ExportarBody({required this.lojaId});

  final String lojaId;

  @override
  State<_ExportarBody> createState() => _ExportarBodyState();
}

class _ExportarBodyState extends State<_ExportarBody> {
  bool _exportando = false;

  Future<void> _exportar(String tipo) async {
    setState(() => _exportando = true);
    try {
      final df = DateFormat('yyyyMMdd_HHmm');
      final stamp = df.format(DateTime.now());

      switch (tipo) {
        case 'clientes':
          final clientes = await ComercialClientesService.listar(widget.lojaId);
          exportarCsv(
            filename: 'clientes_comercial_$stamp.csv',
            cabecalho: [
              'Nome',
              'CPF',
              'Telefone',
              'E-mail',
              'Limite',
              'Utilizado',
              'Disponível',
              'Status',
            ],
            linhas: clientes
                .map(
                  (c) => [
                    c.nome,
                    ComercialClientesService.formatarCpfExibicao(c.cpf),
                    c.telefone ?? '',
                    c.email ?? '',
                    c.limiteCredito,
                    c.creditoUtilizado,
                    c.creditoDisponivel,
                    c.status,
                  ],
                )
                .toList(),
          );
          break;
        case 'pendencias':
          final pend = await ComercialClientesService.carregarClientesComPendencias(widget.lojaId);
          exportarCsv(
            filename: 'pendencias_$stamp.csv',
            cabecalho: [
              'Nome',
              'CPF',
              'Telefone',
              'Total em aberto',
              'Parcelas vencidas',
              'Próximo vencimento',
            ],
            linhas: pend
                .map(
                  (p) => [
                    p.cliente.nome,
                    ComercialClientesService.formatarCpfExibicao(p.cliente.cpf),
                    p.cliente.telefone ?? '',
                    p.totalEmAberto,
                    p.parcelasVencidas,
                    p.proximoVencimento != null
                        ? DateFormat('dd/MM/yyyy').format(p.proximoVencimento!)
                        : '',
                  ],
                )
                .toList(),
          );
          break;
        case 'vendas':
          final clientes = await ComercialClientesService.listar(widget.lojaId);
          final linhas = <List<Object?>>[];
          for (final c in clientes) {
            final lanc = await ComercialClientesService.carregarLancamentosCliente(
              lojaId: widget.lojaId,
              cliente: c,
              limite: 30,
            );
            for (final l in lanc) {
              linhas.add([
                c.nome,
                l.codigoExibicao,
                ComercialClientesService.formatarDataHora(l.dataHora),
                l.formaPagamento,
                l.total,
                l.statusRotulo,
              ]);
            }
          }
          exportarCsv(
            filename: 'vendas_comercial_$stamp.csv',
            cabecalho: ['Cliente', 'Código', 'Data', 'Pagamento', 'Total', 'Status'],
            linhas: linhas,
          );
          break;
        case 'recebimentos':
          final rec = await ComercialCreditoService.listarRecebimentosLoja(widget.lojaId);
          exportarCsv(
            filename: 'recebimentos_$stamp.csv',
            cabecalho: [
              'Data',
              'Cliente ID',
              'Código venda',
              'Parcela',
              'Valor pago',
              'Forma',
            ],
            linhas: rec
                .map(
                  (r) => [
                    r['data_pagamento']?.toString() ?? '',
                    r['cliente_id'] ?? '',
                    r['codigo_venda'] ?? '',
                    r['numero_parcela'] ?? '',
                    r['valor_pago'] ?? '',
                    r['forma_pagamento'] ?? '',
                  ],
                )
                .toList(),
          );
          break;
      }

      if (!mounted) return;
      DiPertinPainelFeedback.sucesso(context, 'Relatório exportado com sucesso.');
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      DiPertinPainelFeedback.erro(context, 'Falha ao exportar: $e');
    } finally {
      if (mounted) setState(() => _exportando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ComercialModalHeader(
          titulo: 'Exportar relatório',
          subtitulo: 'Gera arquivo CSV para Excel',
          icone: Icons.file_upload_rounded,
          onFechar: () => Navigator.pop(context),
        ),
        Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _opcao('Clientes', 'Lista completa de clientes comerciais', Icons.people_outline_rounded, 'clientes'),
              _opcao('Pendências', 'Clientes com parcelas em aberto', Icons.warning_amber_rounded, 'pendencias'),
              _opcao('Vendas', 'Histórico de vendas por cliente', Icons.receipt_long_outlined, 'vendas'),
              _opcao('Recebimentos', 'Pagamentos de parcelas registrados', Icons.payments_outlined, 'recebimentos'),
              if (_exportando) ...[
                const SizedBox(height: 16),
                const Center(child: CircularProgressIndicator(color: PainelAdminTheme.roxo)),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _opcao(String titulo, String desc, IconData icon, String tipo) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: ComercialCardBranco(
        padding: EdgeInsets.zero,
        child: ListTile(
          leading: Icon(icon, color: PainelAdminTheme.roxo),
          title: Text(titulo, style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
          subtitle: Text(desc, style: GoogleFonts.plusJakartaSans(fontSize: 12)),
          trailing: const Icon(Icons.download_rounded),
          onTap: _exportando ? null : () => _exportar(tipo),
        ),
      ),
    );
  }
}
