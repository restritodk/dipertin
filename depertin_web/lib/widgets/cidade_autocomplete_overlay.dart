import 'dart:async';

import 'package:depertin_web/services/cidades_brasil_service.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Campo de cidade com autocomplete IBGE usando [RawAutocomplete] do Flutter.
///
/// Funciona de forma robusta dentro de diálogos (o overlay das opções usa
/// o próprio sistema do [Autocomplete], que é gerenciado pelo framework e
/// flutua corretamente por cima da UI).
class CidadeAutocompleteOverlay extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final String? hint;
  final String? helper;
  final void Function(CidadeSugestao)? onSelecionado;

  const CidadeAutocompleteOverlay({
    super.key,
    required this.controller,
    this.label = 'Cidade — UF',
    this.hint = 'Digite o nome da cidade…',
    this.helper,
    this.onSelecionado,
  });

  @override
  State<CidadeAutocompleteOverlay> createState() =>
      _CidadeAutocompleteOverlayState();
}

class _CidadeAutocompleteOverlayState extends State<CidadeAutocompleteOverlay> {
  static const Color _roxo = Color(0xFF6A1B9A);
  bool _carregando = true;
  List<CidadeSugestao> _todas = const [];

  @override
  void initState() {
    super.initState();
    _carregarIbge();
  }

  Future<void> _carregarIbge() async {
    final r = await CidadesBrasilService.todasCidades();
    if (!mounted) return;
    setState(() {
      _todas = r;
      _carregando = false;
    });
  }

  String _semAcento(String s) {
    var t = s.toLowerCase();
    const from = 'àáâãäåèéêëìíîïòóôõöùúûüçñ';
    const to = 'aaaaaaeeeeiiiiooooouuuucn';
    for (var i = 0; i < from.length; i++) {
      t = t.replaceAll(from[i], to[i]);
    }
    return t;
  }

  Iterable<CidadeSugestao> _opcoesPara(String texto) {
    final t = _semAcento(texto.trim());
    if (t.length < 2) return const [];
    final out = <CidadeSugestao>[];
    for (final c in _todas) {
      final alvo = _semAcento('${c.nome} ${c.ufSigla}');
      if (alvo.contains(t)) {
        out.add(c);
        if (out.length >= 40) break;
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    return RawAutocomplete<CidadeSugestao>(
      textEditingController: widget.controller,
      focusNode: FocusNode(),
      optionsBuilder: (tev) => _opcoesPara(tev.text),
      displayStringForOption: (s) => '${s.nome} — ${s.ufSigla}',
      onSelected: (s) {
        widget.controller.text = '${s.nome} — ${s.ufSigla}';
        widget.controller.selection = TextSelection.collapsed(
          offset: widget.controller.text.length,
        );
        widget.onSelecionado?.call(s);
      },
      fieldViewBuilder: (context, ctrl, focus, onSubmit) {
        return TextFormField(
          controller: ctrl,
          focusNode: focus,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            labelText: widget.label,
            hintText: widget.hint,
            helperText: widget.helper,
            prefixIcon: const Icon(Icons.location_city_outlined),
            suffixIcon: _carregando
                ? const Padding(
                    padding: EdgeInsets.all(14),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : null,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(12),
            clipBehavior: Clip.antiAlias,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxHeight: 280,
                maxWidth: 520,
              ),
              child: ListView.separated(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: options.length,
                separatorBuilder: (_, __) => Divider(
                  height: 1,
                  color: Colors.grey.shade100,
                ),
                itemBuilder: (ctx, i) {
                  final s = options.elementAt(i);
                  return InkWell(
                    onTap: () => onSelected(s),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.location_on_outlined,
                              color: _roxo.withOpacity(0.6), size: 18),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  s.nome,
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.grey.shade900,
                                  ),
                                ),
                                Text(
                                  s.ufNome,
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 11,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: _roxo.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              s.ufSigla,
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: _roxo,
                                letterSpacing: 0.6,
                              ),
                            ),
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
    );
  }
}
