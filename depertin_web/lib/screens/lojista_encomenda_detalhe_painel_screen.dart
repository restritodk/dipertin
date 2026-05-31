import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../constants/encomenda_negociacao_status.dart';
import '../services/firebase_functions_config.dart';
import '../theme/painel_admin_theme.dart';
import 'package:flutter/services.dart';

/// Detalhe da encomenda no painel web — mesmas callables do app mobile.
class LojistaEncomendaDetalhePainelScreen extends StatefulWidget {
  const LojistaEncomendaDetalhePainelScreen({
    super.key,
    required this.encomendaId,
    required this.uidLoja,
  });

  final String encomendaId;
  final String uidLoja;

  @override
  State<LojistaEncomendaDetalhePainelScreen> createState() =>
      _LojistaEncomendaDetalhePainelScreenState();
}

class _LojistaEncomendaDetalhePainelScreenState
    extends State<LojistaEncomendaDetalhePainelScreen> {
  bool _processando = false;

  static final NumberFormat _moeda =
      NumberFormat.currency(locale: 'pt_BR', symbol: r'R$');

  Future<void> _callableNome(String nome, Map<String, dynamic> payload) async {
    setState(() => _processando = true);
    try {
      await callFirebaseFunctionSafe(
        nome,
        parameters: payload,
        timeout: const Duration(seconds: 90),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Salvo com sucesso.'),
          backgroundColor: Colors.green.shade700,
        ),
      );
    } on CallableHttpException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(mensagemCallableHttpException(e)),
          backgroundColor: Colors.red.shade700,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    } finally {
      if (mounted) setState(() => _processando = false);
    }
  }

  Future<void> _aceitarNegociacao() async {
    await _callableNome('encomendaLojaAceitarNegociacao', {
      'encomendaId': widget.encomendaId,
    });
  }

  Future<void> _dialogEnviarProposta() async {
    final totalCtrl = TextEditingController();
    final entCtrl = TextEditingController();
    final obsCtrl = TextEditingController();
    final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Enviar proposta'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: totalCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Valor do produto (proposta)',
                      helperText:
                          'Só o produto — o frete é cobrado no pagamento final.',
                    ),
                  ),
                  TextField(
                    controller: entCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Valor da entrada (produto)',
                    ),
                  ),
                  TextField(
                    controller: obsCtrl,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Observações para o cliente (opcional)',
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Enviar'),
              ),
            ],
          ),
        ) ??
        false;
    if (!ok || !mounted) return;
    final total = double.tryParse(
      totalCtrl.text.replaceAll(',', '.').trim(),
    );
    final ent = double.tryParse(
      entCtrl.text.replaceAll(',', '.').trim(),
    );
    if (total == null ||
        ent == null ||
        total <= 0 ||
        ent <= 0 ||
        ent > total) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Informe total e entrada válidos.')),
      );
      return;
    }
    await _callableNome('encomendaLojaEnviarProposta', {
      'encomendaId': widget.encomendaId,
      'valor_total_referencia': total,
      'valor_entrada_loja': ent,
      'observacoes_loja': obsCtrl.text.trim(),
    });
  }

  Future<void> _dialogResponderContra({
    required String decisao,
    double? totalAtual,
  }) async {
    if (decisao == 'recusar') {
      await _callableNome('encomendaLojaResponderContraproposta', {
        'encomendaId': widget.encomendaId,
        'decisao': 'recusar',
      });
      return;
    }
    if (decisao == 'aceitar') {
      await _callableNome('encomendaLojaResponderContraproposta', {
        'encomendaId': widget.encomendaId,
        'decisao': 'aceitar',
      });
      return;
    }
    final totalCtrl = TextEditingController(
      text: totalAtual != null && totalAtual > 0 ? totalAtual.toString() : '',
    );
    final entCtrl = TextEditingController();
    final obsCtrl = TextEditingController();
    final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Nova proposta'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: totalCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(labelText: 'Novo total'),
                  ),
                  TextField(
                    controller: entCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Nova entrada',
                    ),
                  ),
                  TextField(
                    controller: obsCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Observações (opcional)',
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Enviar'),
              ),
            ],
          ),
        ) ??
        false;
    if (!ok || !mounted) return;
    final novoTotal = double.tryParse(
      totalCtrl.text.replaceAll(',', '.').trim(),
    );
    final novaEnt = double.tryParse(
      entCtrl.text.replaceAll(',', '.').trim(),
    );
    if (novoTotal == null ||
        novaEnt == null ||
        novoTotal <= 0 ||
        novaEnt <= 0 ||
        novaEnt > novoTotal) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Valores inválidos.')),
      );
      return;
    }
    await _callableNome('encomendaLojaResponderContraproposta', {
      'encomendaId': widget.encomendaId,
      'decisao': 'contrapor',
      'valor_total_referencia': novoTotal,
      'valor_entrada_loja': novaEnt,
      'observacoes_loja': obsCtrl.text.trim(),
    });
  }

  Future<void> _confirmarCancelarNegociacaoLoja() async {
    final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Cancelar negociação'),
            content: const Text(
              'Tem certeza? O cliente será avisado e qualquer cobrança da entrada '
              'ainda não paga será cancelada.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Voltar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.red.shade700,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Cancelar negociação'),
              ),
            ],
          ),
        ) ??
        false;
    if (!ok || !mounted) return;
    await _callableNome('encomendaLojaCancelarNegociacao', {
      'encomendaId': widget.encomendaId,
    });
  }

  @override
  Widget build(BuildContext context) {
    final ref = FirebaseFirestore.instance
        .collection('encomendas')
        .doc(widget.encomendaId);

    return Scaffold(
      backgroundColor: PainelAdminTheme.fundoCanvas,
      appBar: AppBar(
        backgroundColor: PainelAdminTheme.roxo,
        foregroundColor: Colors.white,
        title: const Text('Detalhe da encomenda'),
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: ref.snapshots(),
        builder: (context, snap) {
          if (!snap.hasData || !snap.data!.exists) {
            return const Center(
              child: CircularProgressIndicator(color: PainelAdminTheme.roxo),
            );
          }
          final m = snap.data!.data() ?? {};
          if (m['loja_id']?.toString() != widget.uidLoja) {
            return const Center(
              child: Text('Esta encomenda não pertence à sua loja.'),
            );
          }

          final st = (m['status_negociacao'] ?? '').toString();
          final totalRef =
              (m['valor_total_referencia'] is num)
                  ? (m['valor_total_referencia'] as num).toDouble()
                  : null;
          final entradaRef =
              (m['valor_entrada_loja'] is num)
                  ? (m['valor_entrada_loja'] as num).toDouble()
                  : null;
          final entradaCli =
              (m['entrada_contraproposta_cliente'] is num)
                  ? (m['entrada_contraproposta_cliente'] as num).toDouble()
                  : null;
          final msgContra =
              (m['mensagem_contraproposta_cliente'] ?? '').toString();
          final msgCliente = (m['mensagem_cliente'] ?? '').toString();

          final nomeCliente = (m['cliente_nome_snapshot'] ??
                  m['cliente_nome'] ??
                  '-')
              .toString();
          final telefoneCliente = (m['cliente_telefone_snapshot'] ??
                  m['cliente_telefone'] ??
                  '')
              .toString()
              .trim();
          final tipoEntrega = (m['tipo_entrega'] ?? 'entrega').toString();
          final frete = tipoEntrega == 'retirada'
              ? 0.0
              : ((m['taxa_entrega_snapshot'] is num)
                  ? (m['taxa_entrega_snapshot'] as num).toDouble()
                  : 0.0);
          final entradaPaga =
              st == EncomendaNegociacaoStatus.entradaPagaEmProducao ||
                  st == EncomendaNegociacaoStatus.saldoFinalAguardandoPgto ||
                  st == EncomendaNegociacaoStatus.emExecucaoLogistica;
          final totalmentePago =
              st == EncomendaNegociacaoStatus.emExecucaoLogistica;
          final restanteAPagar = (totalRef != null && entradaRef != null)
              ? (((totalRef + frete) - entradaRef)
                  .clamp(0, double.infinity)
                  .toDouble())
              : null;

          final podeAceitarInicio =
              st == EncomendaNegociacaoStatus.aguardandoNegociacao;
          final podePropor =
              st == EncomendaNegociacaoStatus.negociacaoEmAndamento;
          final emContra = st ==
              EncomendaNegociacaoStatus.aguardandoRespostaLojaContraproposta;

          return Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Material(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      child: Padding(
                        padding: const EdgeInsets.all(22),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              EncomendaNegociacaoStatus.rotuloPt(st),
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                color: PainelAdminTheme.roxo,
                              ),
                            ),
                            const SizedBox(height: 16),
                            SelectableText(
                              widget.encomendaId,
                              style: TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 12,
                                color: Colors.grey.shade700,
                              ),
                            ),
                            // Informações rápidas: cliente e contato
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade50,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.grey.shade200),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                                    'Cliente: $nomeCliente',
                                    style: const TextStyle(fontWeight: FontWeight.w700),
                                  ),
                                  const SizedBox(height: 6),
                                  Row(
                                    children: [
                                      Icon(Icons.phone, size: 15, color: Colors.green.shade700),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Telefone do cliente: ${telefoneCliente.isEmpty ? "Não informado" : telefoneCliente}',
                                        style: TextStyle(
                                          color: Colors.green.shade800,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text('Entrega: ${(m['endereco_entrega'] ?? '-').toString()}'),
                                  const SizedBox(height: 8),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      TextButton.icon(
                                        onPressed: () {
                                          Clipboard.setData(ClipboardData(text: widget.encomendaId));
                                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ID da encomenda copiado.')));
                                        },
                                        icon: const Icon(Icons.copy),
                                        label: const Text('Copiar ID'),
                                      ),
                                      const SizedBox(width: 8),
                                      TextButton.icon(
                                        onPressed: () {
                                          Clipboard.setData(ClipboardData(text: 'Abra o chat no app e pesquise pelo ID: ${widget.encomendaId}'));
                                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Texto de instrução copiado para área de transferência.')));
                                        },
                                        icon: const Icon(Icons.chat_bubble_outline),
                                        label: const Text('Instruções de Chat'),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                            if (msgCliente.isNotEmpty) ...[
                              Text(
                                'Pedido do cliente',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: Colors.grey.shade800,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(msgCliente),
                              const SizedBox(height: 16),
                            ],
                            if (totalRef != null && totalRef > 0)
                              Text(
                                'Produto negociado: ${_moeda.format(totalRef)}',
                              ),
                            if (frete > 0)
                              Text('Frete (cobrado no pagamento final): ${_moeda.format(frete)}'),
                            if (totalRef != null && totalRef > 0)
                              Text(
                                'Total da encomenda (com frete): ${_moeda.format(totalRef + frete)}',
                                style: const TextStyle(fontWeight: FontWeight.w700),
                              ),
                            if (entradaRef != null && entradaRef > 0)
                              Text(
                                entradaPaga
                                    ? 'Pagamento da entrada: ${_moeda.format(entradaRef)} (paga)'
                                    : 'Entrada combinada: ${_moeda.format(entradaRef)}',
                              ),
                            if (!totalmentePago && restanteAPagar != null)
                              Text(
                                'Valor restante a pagar pelo cliente: ${_moeda.format(restanteAPagar)}',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: Colors.teal.shade800,
                                ),
                              ),
                            if (totalmentePago)
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Row(
                                  children: [
                                    Icon(Icons.verified,
                                        color: Colors.green.shade700, size: 18),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Pagamento concluído — Totalmente pago',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        color: Colors.green.shade800,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            if (entradaPaga &&
                                totalRef != null &&
                                entradaRef != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 10),
                                child: Text(
                                  'Na entrega, o líquido da loja inclui a entrada '
                                  'já paga (sem taxa) + o restante do produto após '
                                  'a taxa da plataforma.',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    height: 1.35,
                                    color: Colors.green.shade900,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            if (entradaCli != null && entradaCli > 0) ...[
                              const SizedBox(height: 12),
                              Text(
                                'Cliente contrapôs entrada: '
                                '${_moeda.format(entradaCli)}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              if (msgContra.isNotEmpty) Text(msgContra),
                            ],
                            const SizedBox(height: 20),
                            const Text(
                              'Itens',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 15,
                              ),
                            ),
                            const SizedBox(height: 8),
                            ...(m['itens'] is List ? (m['itens'] as List) : [])
                                .map<Widget>((raw) {
                              if (raw is! Map) return const SizedBox.shrink();
                              final it = Map<String, dynamic>.from(raw);
                              final nome = (it['nome'] ?? '').toString();
                              final q = (it['quantidade'] is num)
                                  ? (it['quantidade'] as num).toInt()
                                  : 1;
                              final preco = (it['preco_ref'] is num)
                                  ? (it['preco_ref'] as num).toDouble()
                                  : 0.0;
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Row(
                                  children: [
                                    Expanded(child: Text(nome)),
                                    Text('$q × ${_moeda.format(preco)}'),
                                  ],
                                ),
                              );
                            }),
                            if (st ==
                                EncomendaNegociacaoStatus.saldoFinalAguardandoPgto)
                              Padding(
                                padding: const EdgeInsets.only(top: 16),
                                child: Container(
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: Colors.blue.shade50,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: Colors.blue.shade200,
                                    ),
                                  ),
                                  child: Text(
                                    'Aguardando o cliente pagar o saldo no aplicativo.',
                                    style: TextStyle(
                                      height: 1.35,
                                      color: Colors.grey.shade900,
                                    ),
                                  ),
                                ),
                              ),
                            if (st ==
                                EncomendaNegociacaoStatus.emExecucaoLogistica)
                              Padding(
                                padding: const EdgeInsets.only(top: 16),
                                child: Container(
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: Colors.green.shade50,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: Colors.green.shade200,
                                    ),
                                  ),
                                  child: Text(
                                    'Saldo pago. Acompanhe a entrega em «Meus pedidos».',
                                    style: TextStyle(
                                      height: 1.35,
                                      color: Colors.grey.shade900,
                                    ),
                                  ),
                                ),
                              ),
                            const SizedBox(height: 24),
                            if (podeAceitarInicio)
                              FilledButton(
                                onPressed:
                                    _processando ? null : _aceitarNegociacao,
                                style: FilledButton.styleFrom(
                                  backgroundColor: PainelAdminTheme.laranja,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 16,
                                  ),
                                ),
                                child: const Text('Aceitar iniciar negociação'),
                              ),
                            if (podePropor) ...[
                              const SizedBox(height: 10),
                              FilledButton(
                                onPressed: _processando
                                    ? null
                                    : _dialogEnviarProposta,
                                style: FilledButton.styleFrom(
                                  backgroundColor: PainelAdminTheme.roxo,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 16,
                                  ),
                                ),
                                child: const Text('Enviar proposta ao cliente'),
                              ),
                            ],
                            if (emContra) ...[
                              const SizedBox(height: 10),
                              OutlinedButton(
                                onPressed: _processando
                                    ? null
                                    : () => _dialogResponderContra(
                                          decisao: 'aceitar',
                                        ),
                                child: const Text(
                                  'Aceitar contraproposta do cliente',
                                ),
                              ),
                              const SizedBox(height: 8),
                              FilledButton(
                                onPressed: _processando
                                    ? null
                                    : () => _dialogResponderContra(
                                          decisao: 'contrapor',
                                          totalAtual: totalRef,
                                        ),
                                style: FilledButton.styleFrom(
                                  backgroundColor: PainelAdminTheme.roxo,
                                  foregroundColor: Colors.white,
                                ),
                                child: const Text('Enviar nova proposta'),
                              ),
                              const SizedBox(height: 8),
                              TextButton(
                                onPressed: _processando
                                    ? null
                                    : () => _dialogResponderContra(
                                          decisao: 'recusar',
                                        ),
                                child: Text(
                                  'Encerrar negociação',
                                  style: TextStyle(
                                    color: Colors.red.shade700,
                                  ),
                                ),
                              ),
                            ],
                            if (st ==
                                EncomendaNegociacaoStatus.entradaPagaEmProducao) ...[
                              const SizedBox(height: 16),
                              FilledButton(
                                onPressed: _processando
                                    ? null
                                    : () => _callableNome(
                                          'encomendaLojaCriarPedidoSaldoFinal',
                                          {'encomendaId': widget.encomendaId},
                                        ),
                                style: FilledButton.styleFrom(
                                  backgroundColor: PainelAdminTheme.roxo,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 16,
                                  ),
                                ),
                                child: const Text('Gerar cobrança do saldo'),
                              ),
                            ],
                            if (!EncomendaNegociacaoStatus.encerradaDefinitivamente(
                                  st,
                                ) &&
                                !emContra) ...[
                              const SizedBox(height: 16),
                              Builder(
                                builder: (context) {
                                  final podeCancelar =
                                      EncomendaNegociacaoStatus
                                          .podeCancelarNegociacaoAntesPagamentoEntrada(
                                            st,
                                          );
                                  return Column(
                                    children: [
                                      Align(
                                        alignment: Alignment.center,
                                        child: TextButton(
                                          onPressed:
                                              (podeCancelar && !_processando)
                                                  ? _confirmarCancelarNegociacaoLoja
                                                  : null,
                                          child: Text(
                                            'Cancelar negociação',
                                            style: TextStyle(
                                              color: podeCancelar
                                                  ? Colors.red.shade700
                                                  : Colors.grey.shade400,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      ),
                                      if (!podeCancelar)
                                        Padding(
                                          padding: const EdgeInsets.only(top: 4),
                                          child: Text(
                                            'Após o pagamento da entrada o cancelamento '
                                            'por aqui fica indisponível.',
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              fontSize: 12,
                                              height: 1.35,
                                              color: Colors.grey.shade600,
                                            ),
                                          ),
                                        ),
                                    ],
                                  );
                                },
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
