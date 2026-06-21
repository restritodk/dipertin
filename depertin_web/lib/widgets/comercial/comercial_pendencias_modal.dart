import 'package:depertin_web/models/comercial_cliente.dart';
import 'package:depertin_web/services/comercial_clientes_service.dart';
import 'package:depertin_web/theme/painel_admin_theme.dart';
import 'package:depertin_web/widgets/comercial/comercial_modal_ui.dart';
import 'package:depertin_web/widgets/comercial_cliente_recebimento_modal.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

/// Lista clientes com pendências financeiras.
Future<void> mostrarComercialPendenciasModal(
  BuildContext context, {
  required String lojaId,
}) {
  return mostrarComercialModalShell<void>(
    context,
    maxWidth: 920,
    child: _PendenciasBody(lojaId: lojaId),
  );
}

class _PendenciasBody extends StatefulWidget {
  const _PendenciasBody({required this.lojaId});

  final String lojaId;

  @override
  State<_PendenciasBody> createState() => _PendenciasBodyState();
}

class _PendenciasBodyState extends State<_PendenciasBody> {
  final _buscaCtrl = TextEditingController();
  List<ClientePendenciaResumo> _todos = const [];
  List<ClientePendenciaResumo> _filtrados = const [];
  bool _carregando = true;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    _buscaCtrl.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    try {
      final lista =
          await ComercialClientesService.carregarClientesComPendencias(widget.lojaId);
      if (!mounted) return;
      setState(() {
        _todos = lista;
        _filtrados = lista;
        _carregando = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _carregando = false);
    }
  }

  void _filtrar(String q) {
    final query = q.trim().toLowerCase();
    final cpfQ = query.replaceAll(RegExp(r'\D'), '');
    setState(() {
      if (query.isEmpty) {
        _filtrados = _todos;
        return;
      }
      _filtrados = _todos.where((p) {
        final c = p.cliente;
        if (c.nome.toLowerCase().contains(query)) return true;
        if (cpfQ.length >= 3) {
          final cpf = (c.cpf ?? '').replaceAll(RegExp(r'\D'), '');
          if (cpf.contains(cpfQ)) return true;
        }
        return false;
      }).toList();
    });
  }

  Future<void> _abrirRecebimento(ComercialCliente cliente) async {
    await mostrarComercialClienteRecebimentoModal(
      context,
      lojaId: widget.lojaId,
      cliente: cliente,
    );
    if (!mounted) return;
    await _carregar();
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('dd/MM/yyyy', 'pt_BR');
    final maxH = MediaQuery.sizeOf(context).height * 0.88;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxH),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ComercialModalHeader(
            titulo: 'Clientes com pendências',
            subtitulo: 'Parcelas em aberto e vencidas',
            icone: Icons.warning_amber_rounded,
            onFechar: () => Navigator.pop(context),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
            child: ComercialBuscaField(
              controller: _buscaCtrl,
              hint: 'Buscar por nome ou CPF',
              onChanged: _filtrar,
            ),
          ),
          Flexible(
            child: _carregando
                ? const Center(child: CircularProgressIndicator(color: PainelAdminTheme.roxo))
                : _filtrados.isEmpty
                    ? const ComercialEstadoVazio(
                        titulo: 'Nenhuma pendência encontrada',
                        subtitulo: 'Todos os clientes estão em dia.',
                        icone: Icons.check_circle_outline_rounded,
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
                        itemCount: _filtrados.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, i) {
                          final p = _filtrados[i];
                          final c = p.cliente;
                          return ComercialCardBranco(
                            padding: const EdgeInsets.all(14),
                            child: InkWell(
                              onTap: () => _abrirRecebimento(c),
                              borderRadius: BorderRadius.circular(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              c.nome,
                                              style: GoogleFonts.plusJakartaSans(
                                                fontWeight: FontWeight.w800,
                                                fontSize: 14,
                                              ),
                                            ),
                                            Text(
                                              'CPF: ${ComercialClientesService.formatarCpfExibicao(c.cpf)} · Tel: ${c.telefone ?? '—'}',
                                              style: GoogleFonts.plusJakartaSans(
                                                fontSize: 11,
                                                color: const Color(0xFF64748B),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Text(
                                        ComercialClientesService.formatarMoeda(p.totalEmAberto),
                                        style: GoogleFonts.plusJakartaSans(
                                          fontWeight: FontWeight.w800,
                                          color: const Color(0xFFEF4444),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  Row(
                                    children: [
                                      _chip(
                                        p.parcelasVencidas > 0
                                            ? '${p.parcelasVencidas} vencida(s)'
                                            : 'Em dias',
                                        p.parcelasVencidas > 0
                                            ? const Color(0xFFEF4444)
                                            : const Color(0xFF6366F1),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Próx. venc.: ${p.proximoVencimento != null ? df.format(p.proximoVencimento!) : '—'}',
                                        style: GoogleFonts.plusJakartaSans(
                                          fontSize: 11,
                                          color: const Color(0xFF64748B),
                                        ),
                                      ),
                                      const Spacer(),
                                      FilledButton.icon(
                                        onPressed: () => _abrirRecebimento(c),
                                        style: FilledButton.styleFrom(
                                          backgroundColor: PainelAdminTheme.laranja,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 8,
                                          ),
                                        ),
                                        icon: const Icon(Icons.payments_outlined, size: 16),
                                        label: const Text('Receber'),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, Color cor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: GoogleFonts.plusJakartaSans(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: cor,
        ),
      ),
    );
  }
}
