// Arquivo: lib/widgets/escolher_tipo_entrega_dialog.dart
//
// Diálogo (web) para o lojista escolher categoria de entregador no clique
// de "Solicitar entregador". Espelha o widget mobile em
// `depertin_cliente/lib/screens/lojista/widgets/escolher_tipo_entrega_dialog.dart`,
// mas sem `shared_preferences` — a "última escolha" é mantida apenas em
// memória durante a sessão atual do painel.

import 'package:flutter/material.dart';

import 'package:depertin_web/constants/tipos_entrega.dart';

const Color _kRoxo = Color(0xFF6A1B9A);
const Color _kLaranja = Color(0xFFFF8F00);

class EscolherTipoEntregaDialog extends StatefulWidget {
  const EscolherTipoEntregaDialog({
    super.key,
    required this.tiposDisponiveis,
    this.tipoPreSelecionado,
    this.tipoAnteriorMensagem,
  });

  final List<String> tiposDisponiveis;
  final String? tipoPreSelecionado;
  final String? tipoAnteriorMensagem;

  static String? _ultimaEscolhaSessao;

  static Future<String?> mostrar(
    BuildContext context, {
    required List<String> tiposDisponiveis,
    String? tipoAnteriorMensagem,
  }) async {
    final lista = TiposEntrega.normalizarLista(tiposDisponiveis);
    if (lista.isEmpty) return null;
    if (lista.length == 1) {
      _ultimaEscolhaSessao = lista.first;
      return lista.first;
    }

    final pre = (_ultimaEscolhaSessao != null &&
            lista.contains(_ultimaEscolhaSessao))
        ? _ultimaEscolhaSessao
        : lista.first;

    final escolhido = await showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (_) => EscolherTipoEntregaDialog(
        tiposDisponiveis: lista,
        tipoPreSelecionado: pre,
        tipoAnteriorMensagem: tipoAnteriorMensagem,
      ),
    );
    if (escolhido != null) {
      _ultimaEscolhaSessao = escolhido;
    }
    return escolhido;
  }

  @override
  State<EscolherTipoEntregaDialog> createState() =>
      _EscolherTipoEntregaDialogState();
}

class _EscolherTipoEntregaDialogState extends State<EscolherTipoEntregaDialog> {
  late String _selecionado;

  @override
  void initState() {
    super.initState();
    _selecionado = widget.tipoPreSelecionado ?? widget.tiposDisponiveis.first;
  }

  IconData _icone(String c) {
    switch (c) {
      case TiposEntrega.codBicicleta:
        return Icons.directions_bike_rounded;
      case TiposEntrega.codMoto:
        return Icons.two_wheeler_rounded;
      case TiposEntrega.codCarro:
        return Icons.directions_car_rounded;
      case TiposEntrega.codCarroFrete:
        return Icons.local_shipping_rounded;
      default:
        return Icons.delivery_dining_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      title: Row(
        children: const [
          Icon(Icons.delivery_dining_rounded, color: _kRoxo),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Qual categoria chamar?',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.tipoAnteriorMensagem != null &&
                widget.tipoAnteriorMensagem!.trim().isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF8E1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFF1D583)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.info_outline_rounded,
                      size: 18,
                      color: Color(0xFFC28400),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.tipoAnteriorMensagem!.trim(),
                        style: const TextStyle(fontSize: 12.5, height: 1.35),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
            const Text(
              'Sua loja aceita mais de um tipo. Escolha quem chamar para esta '
              'corrida — só entregadores da categoria selecionada receberão a '
              'oferta.',
              style: TextStyle(fontSize: 13, height: 1.35),
            ),
            const SizedBox(height: 14),
            for (final t in widget.tiposDisponiveis) _opcao(t),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(
            'Cancelar',
            style: TextStyle(color: Colors.black54),
          ),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.of(context).pop(_selecionado),
          style: FilledButton.styleFrom(
            backgroundColor: _kLaranja,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          ),
          icon: const Icon(Icons.send_rounded, size: 18),
          label: const Text(
            'Chamar entregador',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }

  Widget _opcao(String tipo) {
    final selecionado = tipo == _selecionado;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => setState(() => _selecionado = tipo),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: selecionado
                ? _kRoxo.withValues(alpha: 0.08)
                : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selecionado ? _kRoxo : Colors.grey.shade300,
              width: selecionado ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                _icone(tipo),
                color: selecionado ? _kRoxo : Colors.grey.shade700,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      TiposEntrega.rotulo(tipo),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: selecionado ? _kRoxo : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      TiposEntrega.descricaoCurta(tipo),
                      style: TextStyle(
                        fontSize: 11.5,
                        color: Colors.grey.shade700,
                        height: 1.3,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selecionado ? _kRoxo : Colors.transparent,
                  border: Border.all(
                    color: selecionado ? _kRoxo : Colors.grey.shade400,
                    width: 2,
                  ),
                ),
                child: selecionado
                    ? const Icon(
                        Icons.check_rounded,
                        size: 14,
                        color: Colors.white,
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
