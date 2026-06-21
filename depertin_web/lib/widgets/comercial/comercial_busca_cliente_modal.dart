import 'package:depertin_web/models/comercial_cliente.dart';
import 'package:depertin_web/services/comercial_clientes_service.dart';
import 'package:depertin_web/theme/painel_admin_theme.dart';
import 'package:depertin_web/widgets/comercial/comercial_modal_ui.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Modal de busca e seleção de cliente comercial.
Future<ComercialCliente?> mostrarComercialBuscaClienteModal(
  BuildContext context, {
  required String lojaId,
  required String titulo,
  String? subtitulo,
  IconData? icone,
}) async {
  return mostrarComercialModalShell<ComercialCliente>(
    context,
    child: _BuscaClienteBody(
      lojaId: lojaId,
      titulo: titulo,
      subtitulo: subtitulo,
      icone: icone,
    ),
  );
}

class _BuscaClienteBody extends StatefulWidget {
  const _BuscaClienteBody({
    required this.lojaId,
    required this.titulo,
    this.subtitulo,
    this.icone,
  });

  final String lojaId;
  final String titulo;
  final String? subtitulo;
  final IconData? icone;

  @override
  State<_BuscaClienteBody> createState() => _BuscaClienteBodyState();
}

class _BuscaClienteBodyState extends State<_BuscaClienteBody> {
  final _buscaCtrl = TextEditingController();
  List<ComercialCliente> _todos = const [];
  List<ComercialCliente> _filtrados = const [];
  bool _carregando = true;
  String? _erro;

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
      final lista = await ComercialClientesService.listar(widget.lojaId);
      if (!mounted) return;
      setState(() {
        _todos = lista;
        _filtrados = ComercialClientesService.filtrarClientesBusca(lista, '');
        _carregando = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _erro = 'Não foi possível carregar os clientes.';
        _carregando = false;
      });
    }
  }

  void _filtrar(String q) {
    setState(() {
      _filtrados = ComercialClientesService.filtrarClientesBusca(_todos, q);
    });
  }

  @override
  Widget build(BuildContext context) {
    final maxH = MediaQuery.sizeOf(context).height * 0.88;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxH),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ComercialModalHeader(
            titulo: widget.titulo,
            subtitulo: widget.subtitulo,
            icone: widget.icone,
            onFechar: () => Navigator.pop(context),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
            child: ComercialBuscaField(
              controller: _buscaCtrl,
              hint: 'Buscar cliente por nome ou CPF',
              onChanged: _filtrar,
            ),
          ),
          Flexible(
            child: _carregando
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: CircularProgressIndicator(color: PainelAdminTheme.roxo),
                    ),
                  )
                : _erro != null
                    ? ComercialEstadoVazio(titulo: _erro!)
                    : _filtrados.isEmpty
                        ? const ComercialEstadoVazio(
                            titulo: 'Nenhum cliente encontrado',
                            subtitulo: 'Tente outro nome ou CPF.',
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
                            itemCount: _filtrados.length,
                            separatorBuilder: (_, _) => const SizedBox(height: 8),
                            itemBuilder: (context, i) {
                              final c = _filtrados[i];
                              return _ClienteTile(
                                cliente: c,
                                onTap: () => Navigator.pop(context, c),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}

class _ClienteTile extends StatelessWidget {
  const _ClienteTile({required this.cliente, required this.onTap});

  final ComercialCliente cliente;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: PainelAdminTheme.roxo.withValues(alpha: 0.12),
                child: Text(
                  cliente.nome.isNotEmpty ? cliente.nome[0].toUpperCase() : 'C',
                  style: GoogleFonts.plusJakartaSans(
                    fontWeight: FontWeight.w800,
                    color: PainelAdminTheme.roxo,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      cliente.nome,
                      style: GoogleFonts.plusJakartaSans(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      'CPF: ${ComercialClientesService.formatarCpfExibicao(cliente.cpf)}',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        color: const Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: PainelAdminTheme.roxo.withValues(alpha: 0.45),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
