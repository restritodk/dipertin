import 'dart:async';

import 'package:depertin_web/services/cidades_brasil_service.dart';
import 'package:flutter/material.dart';

/// Campo de cidade com sugestões (IBGE) ao digitar.
class CampoCidadeBrasilField extends StatefulWidget {
  final TextEditingController controller;
  final InputDecoration decoration;

  const CampoCidadeBrasilField({
    super.key,
    required this.controller,
    this.decoration = const InputDecoration(
      labelText: 'Cidade',
      hintText: 'Digite para buscar',
      border: OutlineInputBorder(),
    ),
  });

  @override
  State<CampoCidadeBrasilField> createState() => _CampoCidadeBrasilFieldState();
}

class _CampoCidadeBrasilFieldState extends State<CampoCidadeBrasilField> {
  Timer? _debounce;
  List<CidadeSugestao> _sugestoes = [];
  bool _buscando = false;
  int _req = 0;
  bool _silenciarBusca = false;

  @override
  void initState() {
    super.initState();
    unawaited(CidadesBrasilService.precarregar());
  }

  void _agendarBusca() {
    if (_silenciarBusca) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 320), _executarBusca);
  }

  Future<void> _executarBusca() async {
    if (!mounted || _silenciarBusca) return;
    final q = widget.controller.text;
    final id = ++_req;
    setState(() => _buscando = true);
    final r = await CidadesBrasilService.buscar(q);
    if (!mounted || id != _req) return;
    setState(() {
      _buscando = false;
      _sugestoes = r.toList();
    });
  }

  void _selecionar(CidadeSugestao s) {
    _debounce?.cancel();
    _silenciarBusca = true;
    widget.controller.text = '${s.nome} — ${s.ufSigla}';
    widget.controller.selection = TextSelection.collapsed(
      offset: widget.controller.text.length,
    );
    setState(() {
      _sugestoes = [];
      _buscando = false;
    });
    Future<void>.delayed(Duration.zero, () {
      if (mounted) _silenciarBusca = false;
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: widget.controller,
          textCapitalization: TextCapitalization.words,
          decoration: widget.decoration.copyWith(
            suffixIcon: _buscando
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : null,
          ),
          onChanged: (_) => _agendarBusca(),
        ),
        if (_sugestoes.isNotEmpty) ...[
          const SizedBox(height: 6),
          Material(
            elevation: 3,
            borderRadius: BorderRadius.circular(8),
            clipBehavior: Clip.antiAlias,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: ListView.builder(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: _sugestoes.length,
                itemBuilder: (context, i) {
                  final s = _sugestoes[i];
                  return ListTile(
                    dense: true,
                    title: Text(
                      s.labelLinha,
                      style: const TextStyle(fontSize: 14),
                    ),
                    onTap: () => _selecionar(s),
                  );
                },
              ),
            ),
          ),
        ],
      ],
    );
  }
}
