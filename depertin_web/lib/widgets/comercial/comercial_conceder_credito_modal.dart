import 'package:depertin_web/models/comercial_cliente.dart';
import 'package:depertin_web/services/comercial_clientes_service.dart';
import 'package:depertin_web/services/comercial_credito_service.dart';
import 'package:depertin_web/widgets/comercial/comercial_busca_cliente_modal.dart';
import 'package:depertin_web/widgets/comercial/comercial_modal_ui.dart';
import 'package:depertin_web/widgets/dipertin_painel_feedback.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

/// Conceder crédito: busca cliente → confirma novo limite.
Future<bool> mostrarComercialConcederCreditoModal(
  BuildContext context, {
  required String lojaId,
  ComercialCliente? clienteInicial,
}) async {
  final cliente = clienteInicial ??
      await mostrarComercialBuscaClienteModal(
        context,
        lojaId: lojaId,
        titulo: 'Conceder crédito',
        subtitulo: 'Selecione o cliente para aumentar o limite',
        icone: Icons.wallet_rounded,
      );
  if (cliente == null || !context.mounted) return false;

  final ok = await mostrarComercialModalShell<bool>(
    context,
    child: _ConcederCreditoForm(lojaId: lojaId, cliente: cliente),
    maxWidth: 560,
  );
  return ok == true;
}

class _ConcederCreditoForm extends StatefulWidget {
  const _ConcederCreditoForm({
    required this.lojaId,
    required this.cliente,
  });

  final String lojaId;
  final ComercialCliente cliente;

  @override
  State<_ConcederCreditoForm> createState() => _ConcederCreditoFormState();
}

class _ConcederCreditoFormState extends State<_ConcederCreditoForm> {
  final _valorCtrl = TextEditingController();
  final _obsCtrl = TextEditingController();
  bool _salvando = false;
  late ComercialCliente _cliente;

  @override
  void initState() {
    super.initState();
    _cliente = widget.cliente;
  }

  @override
  void dispose() {
    _valorCtrl.dispose();
    _obsCtrl.dispose();
    super.dispose();
  }

  double _parseValor(String s) {
    final t = s.trim().replaceAll(RegExp(r'[^\d,.-]'), '');
    if (t.contains(',')) {
      return double.tryParse(t.replaceAll('.', '').replaceAll(',', '.')) ?? 0;
    }
    return double.tryParse(t) ?? 0;
  }

  Future<void> _confirmar() async {
    final valor = _parseValor(_valorCtrl.text);
    if (valor <= 0) {
      DiPertinPainelFeedback.erro(context, 'Informe um valor válido.');
      return;
    }
    setState(() => _salvando = true);
    try {
      _cliente = await ComercialCreditoService.concederLimiteAdicional(
        lojaId: widget.lojaId,
        cliente: _cliente,
        valorAdicionar: valor,
        observacao: _obsCtrl.text.trim().isEmpty ? null : _obsCtrl.text.trim(),
      );
      if (!mounted) return;
      DiPertinPainelFeedback.sucesso(context, 'Limite de crédito atualizado.');
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      DiPertinPainelFeedback.erro(context, '$e');
      setState(() => _salvando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final disp = _cliente.creditoDisponivel;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ComercialModalHeader(
          titulo: 'Conceder crédito',
          subtitulo: _cliente.nome,
          icone: Icons.wallet_rounded,
          onFechar: () => Navigator.pop(context),
        ),
        Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ComercialCardBranco(
                child: Column(
                  children: [
                    _linha('CPF', ComercialClientesService.formatarCpfExibicao(_cliente.cpf)),
                    _linha('Limite total', ComercialClientesService.formatarMoeda(_cliente.limiteCredito)),
                    _linha('Utilizado', ComercialClientesService.formatarMoeda(_cliente.creditoUtilizado)),
                    _linha(
                      'Disponível',
                      ComercialClientesService.formatarMoeda(disp),
                      destaque: true,
                      cor: disp < 0 ? const Color(0xFFEF4444) : const Color(0xFF10B981),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Adicionar ao limite total',
                style: GoogleFonts.plusJakartaSans(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: const Color(0xFF64748B),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _valorCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d,.]'))],
                decoration: InputDecoration(
                  prefixText: 'R\$ ',
                  hintText: '0,00',
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _obsCtrl,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: 'Observação (opcional)',
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 20),
              ComercialModalFooterActions(
                labelSecundario: 'Cancelar',
                onSecundario: _salvando ? null : () => Navigator.pop(context),
                labelPrimario: 'Confirmar crédito',
                onPrimario: _confirmar,
                carregando: _salvando,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _linha(String label, String valor, {bool destaque = false, Color? cor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                color: const Color(0xFF64748B),
              ),
            ),
          ),
          Text(
            valor,
            style: GoogleFonts.plusJakartaSans(
              fontSize: destaque ? 15 : 13,
              fontWeight: FontWeight.w800,
              color: cor ?? const Color(0xFF1E1B4B),
            ),
          ),
        ],
      ),
    );
  }
}
