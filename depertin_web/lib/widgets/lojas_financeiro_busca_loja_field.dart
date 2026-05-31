import 'package:depertin_web/services/admin_lojas_financeiro_service.dart';
import 'package:depertin_web/theme/painel_admin_theme.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Campo de busca de loja com autocomplete (nome ≥3 letras, CPF/CNPJ).
class LojasFinanceiroBuscaLojaField extends StatefulWidget {
  const LojasFinanceiroBuscaLojaField({
    super.key,
    required this.catalogo,
    required this.controller,
    required this.lojaIdSelecionada,
    required this.onLojaSelecionada,
    this.onSubmitted,
  });

  final List<LojaCatalogoItem> catalogo;
  final TextEditingController controller;
  final String? lojaIdSelecionada;
  final void Function(LojaCatalogoItem? loja) onLojaSelecionada;
  final VoidCallback? onSubmitted;

  @override
  State<LojasFinanceiroBuscaLojaField> createState() =>
      _LojasFinanceiroBuscaLojaFieldState();
}

class _LojasFinanceiroBuscaLojaFieldState
    extends State<LojasFinanceiroBuscaLojaField> {
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextoMudou);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextoMudou);
    _focus.dispose();
    super.dispose();
  }

  void _onTextoMudou() {
    if (mounted) setState(() {});
  }

  Iterable<LojaCatalogoItem> _opcoes(TextEditingValue value) {
    return AdminLojasFinanceiroService.filtrarCatalogoLojas(
      widget.catalogo,
      value.text,
    );
  }

  @override
  Widget build(BuildContext context) {
    return RawAutocomplete<LojaCatalogoItem>(
      textEditingController: widget.controller,
      focusNode: _focus,
      displayStringForOption: (l) => l.nome,
      optionsBuilder: (value) => _opcoes(value),
      onSelected: (loja) => widget.onLojaSelecionada(loja),
      optionsViewBuilder: (context, onSelected, options) {
        if (options.isEmpty) return const SizedBox.shrink();
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 10,
            shadowColor: Colors.black.withValues(alpha: 0.12),
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              constraints: const BoxConstraints(maxHeight: 280, minWidth: 320),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: PainelAdminTheme.dashboardBorder),
              ),
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 6),
                shrinkWrap: true,
                itemCount: options.length,
                separatorBuilder: (_, __) => Divider(
                  height: 1,
                  color: Colors.grey.shade200,
                ),
                itemBuilder: (context, index) {
                  final loja = options.elementAt(index);
                  final selecionada = widget.lojaIdSelecionada == loja.id;
                  return InkWell(
                    onTap: () => onSelected(loja),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 18,
                            backgroundColor: selecionada
                                ? PainelAdminTheme.roxo.withValues(alpha: 0.15)
                                : Colors.grey.shade100,
                            child: Icon(
                              Icons.storefront_outlined,
                              size: 18,
                              color: selecionada
                                  ? PainelAdminTheme.roxo
                                  : Colors.grey.shade600,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  loja.nome,
                                  style: GoogleFonts.plusJakartaSans(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13.5,
                                    color: PainelAdminTheme.dashboardInk,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  loja.rotuloDocumento,
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 11.5,
                                    color: PainelAdminTheme.textoSecundario,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (selecionada)
                            const Icon(
                              Icons.check_circle,
                              size: 18,
                              color: PainelAdminTheme.roxo,
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
      fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
        return TextField(
          controller: controller,
          focusNode: focusNode,
          onSubmitted: (_) => onFieldSubmitted(),
          decoration: InputDecoration(
            labelText: 'Buscar loja',
            hintText: 'Nome, CPF ou CNPJ…',
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: controller.text.isNotEmpty ||
                    widget.lojaIdSelecionada != null
                ? IconButton(
                    tooltip: 'Limpar busca',
                    icon: const Icon(Icons.close_rounded, size: 20),
                    onPressed: () {
                      controller.clear();
                      widget.onLojaSelecionada(null);
                    },
                  )
                : null,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(
                color: PainelAdminTheme.roxo,
                width: 1.5,
              ),
            ),
            isDense: true,
          ),
        );
      },
    );
  }
}
