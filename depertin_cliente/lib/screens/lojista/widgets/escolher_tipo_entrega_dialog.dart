// Arquivo: lib/screens/lojista/widgets/escolher_tipo_entrega_dialog.dart
//
// Diálogo reutilizável para o lojista escolher a categoria de entregador
// no momento de chamar a corrida. Renderiza apenas os tipos que a loja
// marcou como aceitos em `tipos_entrega_permitidos`.
//
// Decisões de design:
//   - Pré-seleciona a última escolha salva localmente (via SharedPreferences)
//     para reduzir cliques no dia-a-dia do lojista.
//   - Nunca inclui categoria fora da lista aceita pela loja (não há jeito
//     de chamar um tipo que a loja não aceita).
//   - Inclui uma descrição curta por categoria pra diminuir erros de clique.

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:depertin_cliente/constants/tipos_entrega.dart';

const Color _kDiPertinRoxo = Color(0xFF6A1B9A);
const Color _kDiPertinLaranja = Color(0xFFFF8F00);

class EscolherTipoEntregaDialog extends StatefulWidget {
  const EscolherTipoEntregaDialog({
    super.key,
    required this.tiposDisponiveis,
    this.tipoPreSelecionado,
    this.tipoAnteriorMensagem,
  });

  final List<String> tiposDisponiveis;
  final String? tipoPreSelecionado;

  /// Se preenchido, renderiza um aviso no topo sinalizando que a tentativa
  /// anterior (com `tipoAnteriorMensagem` como categoria) esgotou sem aceite.
  /// Útil no fluxo "Tentar outra categoria".
  final String? tipoAnteriorMensagem;

  static const String _kPrefsKey = 'lojista_ultimo_tipo_entrega_solicitado';

  /// Conveniência: lê a última escolha persistida localmente.
  static Future<String?> lerUltimaEscolha() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getString(_kPrefsKey);
      if (v == null || v.trim().isEmpty) return null;
      final canon = TiposEntrega.normalizarTipoSolicitado(v);
      return canon.isEmpty ? null : canon;
    } catch (_) {
      return null;
    }
  }

  static Future<void> _salvarEscolha(String tipoCanonico) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kPrefsKey, tipoCanonico);
    } catch (_) {
      // silencioso: falha de prefs não deve bloquear despacho
    }
  }

  /// Conveniência: abre o diálogo e devolve o código canônico escolhido.
  /// Retorna null se o lojista cancelar.
  static Future<String?> mostrar(
    BuildContext context, {
    required List<String> tiposDisponiveis,
    String? tipoAnteriorMensagem,
  }) async {
    final lista = TiposEntrega.normalizarLista(tiposDisponiveis);
    if (lista.isEmpty) return null;

    if (lista.length == 1) {
      await _salvarEscolha(lista.first);
      return lista.first;
    }

    final ultima = await lerUltimaEscolha();
    if (!context.mounted) return null;
    final preSel = (ultima != null && lista.contains(ultima))
        ? ultima
        : lista.first;

    final escolhido = await showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (dialogCtx) => EscolherTipoEntregaDialog(
        tiposDisponiveis: lista,
        tipoPreSelecionado: preSel,
        tipoAnteriorMensagem: tipoAnteriorMensagem,
      ),
    );
    if (escolhido != null) {
      await _salvarEscolha(escolhido);
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

  IconData _iconeParaTipo(String cod) {
    switch (cod) {
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
          Icon(Icons.delivery_dining_rounded, color: _kDiPertinRoxo),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Qual categoria chamar?',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
      content: Column(
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
          for (final tipo in widget.tiposDisponiveis) _linhaOpcao(tipo),
        ],
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
            backgroundColor: _kDiPertinLaranja,
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

  Widget _linhaOpcao(String tipo) {
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
                ? _kDiPertinRoxo.withValues(alpha: 0.08)
                : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selecionado ? _kDiPertinRoxo : Colors.grey.shade300,
              width: selecionado ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                _iconeParaTipo(tipo),
                color: selecionado ? _kDiPertinRoxo : Colors.grey.shade700,
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
                        color: selecionado ? _kDiPertinRoxo : Colors.black87,
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
                  color: selecionado ? _kDiPertinRoxo : Colors.transparent,
                  border: Border.all(
                    color: selecionado
                        ? _kDiPertinRoxo
                        : Colors.grey.shade400,
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
