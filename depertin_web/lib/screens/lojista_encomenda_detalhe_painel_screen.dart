import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../utils/encomenda_painel_helpers.dart';
import '../constants/encomenda_negociacao_status.dart';
import '../services/firebase_functions_config.dart';
import '../widgets/encomenda_inbox_ui.dart';
import '../theme/painel_admin_theme.dart';

/// Detalhe da encomenda no painel web — mesmas callables do app mobile.
class LojistaEncomendaDetalhePainelScreen extends StatefulWidget {
  const LojistaEncomendaDetalhePainelScreen({
    super.key,
    required this.encomendaId,
    required this.uidLoja,
    this.embedded = false,
    this.onFechar,
    this.statusPedidos = const {},
  });

  final String encomendaId;
  final String uidLoja;
  final bool embedded;
  final VoidCallback? onFechar;
  final Map<String, String> statusPedidos;

  @override
  State<LojistaEncomendaDetalhePainelScreen> createState() =>
      _LojistaEncomendaDetalhePainelScreenState();
}

class _LojistaEncomendaDetalhePainelScreenState
    extends State<LojistaEncomendaDetalhePainelScreen> {
  bool _processando = false;
  final _chatController = TextEditingController();
  bool _enviandoChat = false;

  @override
  void dispose() {
    _chatController.dispose();
    super.dispose();
  }

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

  static double? _numero(Map<String, dynamic> m, String campo) {
    final v = m[campo];
    if (v is num) return v.toDouble();
    return null;
  }

  static List<Map<String, dynamic>> _listaMapas(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  static double? _parseMoedaFlexivel(String texto) {
    final limpo = texto.trim().replaceAll(RegExp(r'[^\d,.-]'), '');
    if (limpo.isEmpty) return null;
    if (limpo.contains(',') && limpo.contains('.')) {
      return double.tryParse(limpo.replaceAll('.', '').replaceAll(',', '.'));
    }
    if (limpo.contains(',')) {
      return double.tryParse(limpo.replaceAll(',', '.'));
    }
    return double.tryParse(limpo);
  }

  static String _valorCampo(double valor) {
    return valor.toStringAsFixed(2).replaceAll('.', ',');
  }

  double _totalExatoItens(Map<String, dynamic> m) {
    final itens = _listaMapas(m['itens']);
    var total = 0.0;
    for (final item in itens) {
      final preco = _numero(item, 'preco_ref') ?? _numero(item, 'preco') ?? 0;
      final qtd = _numero(item, 'quantidade') ?? 1;
      total += preco * qtd;
    }
    if (total > 0) return total;
    return _numero(m, 'valor_catalogo_referencia') ?? 0;
  }

  Future<void> _dialogEnviarProposta(Map<String, dynamic> encomenda) async {
    final totalItens = _totalExatoItens(encomenda);
    final totalCtrl = TextEditingController(
      text: totalItens > 0 ? _valorCampo(totalItens) : '',
    );
    final entCtrl = TextEditingController();
    final obsCtrl = TextEditingController();
    var aceitaPix = true;
    var aceitaCartao = true;
    final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => StatefulBuilder(
            builder: (ctx, setDialogState) => AlertDialog(
            title: const Text('Enviar proposta'),
              content: SizedBox(
                width: 420,
                child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: PainelAdminTheme.laranja.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: PainelAdminTheme.laranja.withValues(alpha: 0.2),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.inventory_2_outlined,
                              color: PainelAdminTheme.laranja,
                              size: 22,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Valor exato dos produtos',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.grey.shade700,
                                    ),
                                  ),
                                  Text(
                                    totalItens > 0
                                        ? _moeda.format(totalItens)
                                        : 'Informe o total manualmente',
                                    style: TextStyle(
                                      color: PainelAdminTheme.laranja,
                                      fontSize: 18,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                  TextField(
                    controller: totalCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Valor do produto (proposta)',
                      helperText:
                              'Só o produto — frete é cobrado no pagamento final.',
                          prefixText: 'R\$ ',
                    ),
                  ),
                      const SizedBox(height: 10),
                  TextField(
                    controller: entCtrl,
                        autofocus: true,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                          labelText: 'Valor da entrada',
                          hintText: 'Ex.: 50,00',
                          prefixText: 'R\$ ',
                        ),
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        'Como deseja receber a entrada?',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          FilterChip(
                            selected: aceitaPix,
                            avatar: const Icon(Icons.pix, size: 18),
                            label: const Text('Pix'),
                            selectedColor:
                                PainelAdminTheme.roxo.withValues(alpha: 0.12),
                            checkmarkColor: PainelAdminTheme.roxo,
                            onSelected: (v) =>
                                setDialogState(() => aceitaPix = v),
                          ),
                          FilterChip(
                            selected: aceitaCartao,
                            avatar: const Icon(Icons.credit_card, size: 18),
                            label: const Text('Cartão'),
                            selectedColor:
                                PainelAdminTheme.roxo.withValues(alpha: 0.12),
                            checkmarkColor: PainelAdminTheme.roxo,
                            onSelected: (v) =>
                                setDialogState(() => aceitaCartao = v),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                  TextField(
                    controller: obsCtrl,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Observações para o cliente (opcional)',
                          hintText:
                              'Ex.: prazo de produção, material ou condição combinada.',
                    ),
                  ),
                ],
                  ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar'),
              ),
                FilledButton.icon(
                  onPressed: () {
                    if (!aceitaPix && !aceitaCartao) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Selecione Pix, cartão ou os dois.'),
                        ),
                      );
                      return;
                    }
                    Navigator.pop(ctx, true);
                  },
                  icon: const Icon(Icons.send),
                  label: const Text('Enviar'),
                  style: FilledButton.styleFrom(
                    backgroundColor: PainelAdminTheme.laranja,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ) ??
        false;
    if (!ok || !mounted) return;
    final total = _parseMoedaFlexivel(totalCtrl.text);
    final ent = _parseMoedaFlexivel(entCtrl.text);
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
      'formas_pagamento_entrada_loja': [
        if (aceitaPix) 'pix',
        if (aceitaCartao) 'cartao',
      ],
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
      text: totalAtual != null && totalAtual > 0
          ? _valorCampo(totalAtual)
          : '',
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
    final novoTotal = _parseMoedaFlexivel(totalCtrl.text);
    final novaEnt = _parseMoedaFlexivel(entCtrl.text);
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

    return widget.embedded
        ? _corpoDetalhe(ref)
        : Scaffold(
      backgroundColor: PainelAdminTheme.fundoCanvas,
      appBar: AppBar(
        backgroundColor: PainelAdminTheme.roxo,
        foregroundColor: Colors.white,
        title: const Text('Detalhe da encomenda'),
      ),
            body: _corpoDetalhe(ref),
          );
  }

  Widget _corpoDetalhe(
    DocumentReference<Map<String, dynamic>> ref,
  ) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
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

        if (!widget.embedded) {
          return Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: _montarConteudoLegacy(context, m),
              ),
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _headerInbox(context, m),
            EncomendaTimelineBar(
              passos: timelineCompactaEncomenda(
                m,
                widget.statusPedidos,
                encomendaId: widget.encomendaId,
              ),
            ),
            Expanded(child: _layoutInboxCentral(context, m)),
          ],
        );
      },
    );
  }

  Widget _headerInbox(BuildContext context, Map<String, dynamic> m) {
          final st = (m['status_negociacao'] ?? '').toString();
    final badge = badgeEncomenda(st);
    final nome = (m['cliente_nome_snapshot'] ?? 'Cliente').toString();
    final produto = produtoPrincipalNome(m) ?? 'Encomenda personalizada';

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            PainelAdminTheme.roxo,
            Color(0xFF8E24AA),
          ],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
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
                      codigoEncomendaExibir(widget.encomendaId),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6,
                        color: Colors.white.withValues(alpha: 0.85),
                        fontFamily: 'monospace',
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      nome,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      produto,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: Colors.white.withValues(alpha: 0.88),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.24),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(badge.icone, size: 13, color: Colors.white),
                    const SizedBox(width: 5),
                    Text(
                      badge.label,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              if (widget.onFechar != null)
                IconButton(
                  onPressed: widget.onFechar,
                  icon: const Icon(Icons.close, color: Colors.white70, size: 20),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _painelProximaAcao(Map<String, dynamic> m, String st) {
    final totalRef = (m['valor_total_referencia'] is num)
                  ? (m['valor_total_referencia'] as num).toDouble()
                  : null;
    final podeAceitarInicio =
        st == EncomendaNegociacaoStatus.aguardandoNegociacao;
    final podePropor = st == EncomendaNegociacaoStatus.negociacaoEmAndamento;
    final emContra =
        st == EncomendaNegociacaoStatus.aguardandoRespostaLojaContraproposta;
    final podeGerarSaldo =
        st == EncomendaNegociacaoStatus.entradaPagaEmProducao;
    final podeCancelar =
        EncomendaNegociacaoStatus.podeCancelarNegociacaoAntesPagamentoEntrada(
          st,
        );
    final encerrada = EncomendaNegociacaoStatus.encerradaDefinitivamente(st);

    final botoes = <Widget>[];
    if (podeAceitarInicio) {
      botoes.add(
        _botaoAcaoPrimario(
          label: 'Aceitar iniciar negociação',
          icon: Icons.handshake,
          cor: PainelAdminTheme.laranja,
          onPressed: _processando ? null : _aceitarNegociacao,
        ),
      );
    }
    if (podePropor) {
      botoes.add(
        _botaoAcaoPrimario(
          label: 'Enviar proposta ao cliente',
          icon: Icons.outgoing_mail,
          cor: PainelAdminTheme.roxo,
          onPressed: _processando
              ? null
              : () => _dialogEnviarProposta(m),
        ),
      );
    }
    if (emContra) {
      botoes.addAll([
        _botaoAcaoPrimario(
          label: 'Aceitar contraproposta',
          icon: Icons.check_circle,
          cor: Colors.green.shade700,
          onPressed: _processando
              ? null
              : () => _dialogResponderContra(decisao: 'aceitar'),
        ),
        _botaoAcaoPrimario(
          label: 'Enviar nova proposta',
          icon: Icons.swap_horiz,
          cor: PainelAdminTheme.roxo,
          onPressed: _processando
              ? null
              : () => _dialogResponderContra(
                    decisao: 'contrapor',
                    totalAtual: totalRef,
                  ),
        ),
        _botaoAcaoPerigo(
          label: 'Encerrar negociação',
          onPressed: _processando
              ? null
              : () => _dialogResponderContra(decisao: 'recusar'),
        ),
      ]);
    }
    if (podeGerarSaldo) {
      botoes.add(
        _botaoAcaoPrimario(
          label: 'Gerar cobrança do saldo',
          icon: Icons.request_quote,
          cor: PainelAdminTheme.roxo,
          onPressed: _processando
              ? null
              : () => _callableNome('encomendaLojaCriarPedidoSaldoFinal', {
                    'encomendaId': widget.encomendaId,
                  }),
        ),
      );
    }
    if (!encerrada && !emContra) {
      botoes.add(
        _botaoAcaoPerigo(
          label: 'Cancelar negociação',
          onPressed: (podeCancelar && !_processando)
              ? _confirmarCancelarNegociacaoLoja
              : null,
        ),
      );
    }

    if (botoes.isEmpty && encerrada) return const SizedBox.shrink();

    final destaque = lojaPrecisaAgirEncomenda(st);

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: destaque
                ? PainelAdminTheme.laranja.withValues(alpha: 0.45)
                : Colors.grey.shade200,
            width: destaque ? 2 : 1,
          ),
          boxShadow: [
            if (destaque)
              BoxShadow(
                color: PainelAdminTheme.laranja.withValues(alpha: 0.12),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  Icons.touch_app_outlined,
                  size: 18,
                  color: destaque
                      ? PainelAdminTheme.laranja
                      : PainelAdminTheme.roxo,
                ),
                const SizedBox(width: 8),
                Text(
                  'Próxima ação',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: PainelAdminTheme.dashboardInk,
                  ),
                ),
                if (destaque) ...[
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: PainelAdminTheme.laranja.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'Sua vez',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: PainelAdminTheme.laranja,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            if (botoes.isEmpty)
              Text(
                'Não há ação disponível para este status no momento.',
                style: TextStyle(color: Colors.grey.shade700, height: 1.35),
              )
            else
              LayoutBuilder(
                builder: (context, c) {
                  final largura = c.maxWidth < 520 ? c.maxWidth : 280.0;
                  return Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: botoes
                        .map((b) => SizedBox(width: largura, child: b))
                        .toList(),
                  );
                },
              ),
            if (!encerrada && !podeCancelar && !emContra) ...[
              const SizedBox(height: 10),
              Text(
                'Após o pagamento da entrada, o cancelamento por aqui fica indisponível.',
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontSize: 11.5,
                  height: 1.35,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _botaoAcaoPrimario({
    required String label,
    required IconData icon,
    required Color cor,
    required VoidCallback? onPressed,
  }) {
    return FilledButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: FilledButton.styleFrom(
        backgroundColor: cor,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
      ),
    );
  }

  Widget _botaoAcaoPerigo({
    required String label,
    required VoidCallback? onPressed,
  }) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.cancel_outlined, size: 18),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: onPressed == null
            ? Colors.grey.shade400
            : Colors.red.shade700,
        side: BorderSide(
          color: onPressed == null ? Colors.grey.shade300 : Colors.red.shade200,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
      ),
    );
  }

  Widget _layoutInboxCentral(BuildContext context, Map<String, dynamic> m) {
    final st = (m['status_negociacao'] ?? '').toString();
    final ctx = _dadosPainel(m);

    return ColoredBox(
      color: const Color(0xFFF0F2F5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
            child: LayoutBuilder(
              builder: (context, c) {
                final empilhar = c.maxWidth < 720;
                final cards = [
                  EncomendaInboxMiniCard(
                    icone: Icons.person_outline,
                    titulo: 'CLIENTE',
                    corIcone: PainelAdminTheme.roxo,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          ctx.nomeCliente,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        if (ctx.telefone.isNotEmpty)
                          Text(ctx.telefone, style: TextStyle(color: Colors.green.shade700)),
                        Text(
                          ctx.endereco,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ),
                  EncomendaInboxMiniCard(
                    icone: Icons.flag_outlined,
                    titulo: 'STATUS',
                    corIcone: PainelAdminTheme.laranja,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          EncomendaNegociacaoStatus.rotuloPt(st),
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        if (ctx.atualizado != null)
                          Text(
                            tempoRelativoAtualizacao(ctx.atualizado),
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade600,
                            ),
                          ),
                      ],
                    ),
                  ),
                  EncomendaInboxMiniCard(
                    icone: Icons.payments_outlined,
                    titulo: 'FINANCEIRO',
                    corIcone: const Color(0xFF0D9488),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (ctx.totalRef != null)
                          Text('Negociado: ${_moeda.format(ctx.totalRef!)}'),
                        if (ctx.entradaRef != null)
                          Text(
                            ctx.entradaPaga
                                ? 'Entrada paga: ${_moeda.format(ctx.entradaRef!)}'
                                : 'Entrada: ${_moeda.format(ctx.entradaRef!)}',
                          ),
                        if (ctx.restante != null && ctx.restante! > 0)
                          Text(
                            'Restante: ${_moeda.format(ctx.restante!)}',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        if (ctx.frete > 0)
                          Text(
                            'Frete: ${_moeda.format(ctx.frete)}',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade600,
                            ),
                          ),
                      ],
                    ),
                  ),
                ];
                if (empilhar) {
                  return Column(
                    children: [
                      for (var i = 0; i < cards.length; i++) ...[
                        if (i > 0) const SizedBox(height: 6),
                        cards[i],
                      ],
                    ],
                  );
                }
                return IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < cards.length; i++) ...[
                        if (i > 0) const SizedBox(width: 8),
                        Expanded(child: cards[i]),
                      ],
                    ],
                  ),
                );
              },
            ),
          ),
          _painelProximaAcao(m, st),
          if (st == EncomendaNegociacaoStatus.saldoFinalAguardandoPgto)
            _faixaAviso('Aguardando pagamento do saldo pelo cliente.', Colors.blue),
          if (st == EncomendaNegociacaoStatus.emExecucaoLogistica)
            _faixaAviso('Saldo pago — acompanhe em Meus pedidos.', Colors.green),
          Expanded(
            child: LayoutBuilder(
              builder: (context, c) {
                if (c.maxWidth < 640) {
                  return Column(
                    children: [
                      Expanded(child: _painelChatWhatsApp(st)),
                      _colunaLateral(m, st, altura: 200),
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: _painelChatWhatsApp(st)),
                    Container(width: 1, color: Colors.grey.shade300),
                    SizedBox(width: 260, child: _colunaLateral(m, st)),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _faixaAviso(String texto, MaterialColor cor) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(10, 0, 10, 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: cor.shade50,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: cor.shade200),
      ),
      child: Text(texto, style: TextStyle(fontSize: 11.5, color: cor.shade900)),
    );
  }

  Widget _colunaLateral(
    Map<String, dynamic> m,
    String st, {
    double? altura,
  }) {
    final msgCliente = (m['mensagem_cliente'] ?? '').toString();
    final obs = (m['observacoes_loja'] ?? '').toString();
    final child = ColoredBox(
      color: Colors.white,
      child: ListView(
        padding: const EdgeInsets.all(10),
        children: [
          Text(
            'ITENS',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: Colors.grey.shade600,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 6),
          ..._linhasItens(m),
          const SizedBox(height: 10),
          if (msgCliente.isNotEmpty) ...[
            Text(
              'PEDIDO DO CLIENTE',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 4),
            Text(msgCliente, style: const TextStyle(fontSize: 12, height: 1.3)),
            const SizedBox(height: 10),
          ],
          if (obs.isNotEmpty) ...[
            Text(
              'OBS. LOJA',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 4),
            Text(obs, style: const TextStyle(fontSize: 12, height: 1.3)),
            const SizedBox(height: 10),
          ],
          _historicoCompacto(m),
        ],
      ),
    );
    if (altura != null) return SizedBox(height: altura, child: child);
    return child;
  }

  List<Widget> _linhasItens(Map<String, dynamic> m) {
    final itens = m['itens'];
    if (itens is! List || itens.isEmpty) {
      return [
        Text('—', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
      ];
    }
    return itens.map<Widget>((raw) {
      if (raw is! Map) return const SizedBox.shrink();
      final it = Map<String, dynamic>.from(raw);
      final nome = (it['nome'] ?? '').toString();
      final q = (it['quantidade'] is num) ? (it['quantidade'] as num).toInt() : 1;
      final preco = (it['preco_ref'] is num)
          ? (it['preco_ref'] as num).toDouble()
          : 0.0;
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          children: [
            Expanded(
              child: Text(
                nome,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12),
              ),
            ),
            Text(
              '$q× ${_moeda.format(preco)}',
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      );
    }).toList();
  }

  Widget _historicoCompacto(Map<String, dynamic> m) {
    final historico = m['historico'];
    if (historico is! List || historico.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'HISTÓRICO',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            color: Colors.grey.shade600,
          ),
        ),
        const SizedBox(height: 4),
        ...historico.reversed.take(8).map<Widget>((raw) {
          if (raw is! Map) return const SizedBox.shrink();
          final ev = Map<String, dynamic>.from(raw);
          final tipo = (ev['tipo'] ?? ev['evento'] ?? 'evento').toString();
          final quando = timestampParaDate(ev['em'] ?? ev['criado_em']);
          final fmt = quando != null
              ? DateFormat('dd/MM HH:mm', 'pt_BR').format(quando)
              : '';
          return Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              fmt.isEmpty ? tipo : '$fmt · $tipo',
              style: TextStyle(fontSize: 10.5, color: Colors.grey.shade700),
            ),
          );
        }),
      ],
    );
  }

  Widget _painelChatWhatsApp(String statusNegociacao) {
    final ref = FirebaseFirestore.instance
        .collection('encomendas')
        .doc(widget.encomendaId)
        .collection('mensagens')
        .orderBy('data_envio', descending: false)
        .limit(100);

    final chatEncerrado =
        EncomendaNegociacaoStatus.encerradaDefinitivamente(statusNegociacao) ||
            statusNegociacao == EncomendaNegociacaoStatus.emExecucaoLogistica;

    return ColoredBox(
      color: const Color(0xFFE8EDE8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            color: Colors.white,
            child: Row(
              children: [
                Icon(Icons.forum_outlined, size: 16, color: PainelAdminTheme.roxo),
                const SizedBox(width: 6),
                const Text(
                  'Conversa',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                ),
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: ref.snapshots(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting &&
                    !snap.hasData) {
                  return const Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  );
                }
                final docs = snap.data?.docs ?? [];
                if (docs.isEmpty) {
                  return Center(
                    child: Text(
                      'Inicie a conversa com o cliente',
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                    ),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  itemCount: docs.length,
                  itemBuilder: (context, i) {
                    final msg = docs[i].data();
                    final texto =
                        (msg['texto'] ?? msg['mensagem'] ?? '').toString();
                    final loja = msg['remetente_loja'] == true ||
                        (msg['sender_type'] ?? '').toString() == 'loja' ||
                        (msg['remetente_tipo'] ?? '').toString() == 'loja';
                    return Align(
                      alignment:
                          loja ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 7,
                        ),
                        constraints: const BoxConstraints(maxWidth: 340),
                        decoration: BoxDecoration(
                          color: loja
                              ? const Color(0xFFD9FDD3)
                              : Colors.white,
                          borderRadius: BorderRadius.only(
                            topLeft: const Radius.circular(10),
                            topRight: const Radius.circular(10),
                            bottomLeft: Radius.circular(loja ? 10 : 2),
                            bottomRight: Radius.circular(loja ? 2 : 10),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.04),
                              blurRadius: 2,
                              offset: const Offset(0, 1),
                            ),
                          ],
                        ),
                        child: Text(texto, style: const TextStyle(fontSize: 13)),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          if (!chatEncerrado)
            Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _chatController,
                      style: const TextStyle(fontSize: 13),
                      decoration: InputDecoration(
                        hintText: 'Mensagem…',
                        isDense: true,
                        filled: true,
                        fillColor: const Color(0xFFF0F2F5),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onSubmitted: (_) => _enviarMensagemChat(statusNegociacao),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Material(
                    color: PainelAdminTheme.roxo,
                    shape: const CircleBorder(),
                    child: InkWell(
                      onTap: _enviandoChat
                          ? null
                          : () => _enviarMensagemChat(statusNegociacao),
                      customBorder: const CircleBorder(),
                      child: SizedBox(
                        width: 40,
                        height: 40,
                        child: Center(
                          child: _enviandoChat
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(
                                  Icons.send_rounded,
                                  color: Colors.white,
                                  size: 18,
                                ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  _DadosPainelEncomenda _dadosPainel(Map<String, dynamic> m) {
    final st = (m['status_negociacao'] ?? '').toString();
    final totalRef = (m['valor_total_referencia'] is num)
        ? (m['valor_total_referencia'] as num).toDouble()
        : null;
    final entradaRef = (m['valor_entrada_loja'] is num)
                  ? (m['valor_entrada_loja'] as num).toDouble()
                  : null;
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
    final restante = (totalRef != null && entradaRef != null)
        ? (((totalRef + frete) - entradaRef)
            .clamp(0, double.infinity)
            .toDouble())
        : null;

    return _DadosPainelEncomenda(
      nomeCliente:
          (m['cliente_nome_snapshot'] ?? m['cliente_nome'] ?? '-').toString(),
      telefone: (m['cliente_telefone_snapshot'] ?? m['cliente_telefone'] ?? '')
          .toString()
          .trim(),
      endereco: (m['endereco_entrega'] ?? '—').toString(),
      totalRef: totalRef,
      entradaRef: entradaRef,
      frete: frete,
      entradaPaga: entradaPaga,
      restante: restante,
      atualizado: timestampParaDate(m['atualizado_em']),
    );
  }

  Widget _montarConteudoLegacy(BuildContext context, Map<String, dynamic> m) {
    final st = (m['status_negociacao'] ?? '').toString();
    final totalRef = (m['valor_total_referencia'] is num)
        ? (m['valor_total_referencia'] as num).toDouble()
        : null;
    final entradaRef = (m['valor_entrada_loja'] is num)
        ? (m['valor_entrada_loja'] as num).toDouble()
        : null;
    final entradaCli = (m['entrada_contraproposta_cliente'] is num)
                  ? (m['entrada_contraproposta_cliente'] as num).toDouble()
                  : null;
    final msgContra = (m['mensagem_contraproposta_cliente'] ?? '').toString();
          final msgCliente = (m['mensagem_cliente'] ?? '').toString();

    final nomeCliente =
        (m['cliente_nome_snapshot'] ?? m['cliente_nome'] ?? '-').toString();
    final telefoneCliente =
        (m['cliente_telefone_snapshot'] ?? m['cliente_telefone'] ?? '')
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
    final totalmentePago = st == EncomendaNegociacaoStatus.emExecucaoLogistica;
          final restanteAPagar = (totalRef != null && entradaRef != null)
              ? (((totalRef + frete) - entradaRef)
                  .clamp(0, double.infinity)
                  .toDouble())
              : null;

          final podeAceitarInicio =
              st == EncomendaNegociacaoStatus.aguardandoNegociacao;
    final podePropor = st == EncomendaNegociacaoStatus.negociacaoEmAndamento;
    final emContra =
        st == EncomendaNegociacaoStatus.aguardandoRespostaLojaContraproposta;

    return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
        const SizedBox(height: 16),
        _secaoCard(
          titulo: 'Resumo',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              EncomendaNegociacaoStatus.rotuloPt(st),
                              style: const TextStyle(
                  fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: PainelAdminTheme.roxo,
                              ),
                            ),
              const SizedBox(height: 8),
              Text(
                codigoEncomendaExibir(widget.encomendaId),
                              style: TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 12,
                                color: Colors.grey.shade700,
                              ),
                            ),
            ],
          ),
        ),
        _secaoCard(
          titulo: 'Cliente',
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                nomeCliente,
                                    style: const TextStyle(fontWeight: FontWeight.w700),
                                  ),
                                  const SizedBox(height: 6),
                                  Row(
                                    children: [
                                      Icon(Icons.phone, size: 15, color: Colors.green.shade700),
                                      const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      telefoneCliente.isEmpty
                          ? 'Telefone não informado'
                          : telefoneCliente,
                                        style: TextStyle(
                                          color: Colors.green.shade800,
                                          fontWeight: FontWeight.w600,
                      ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text('Entrega: ${(m['endereco_entrega'] ?? '-').toString()}'),
            ],
          ),
        ),
        _secaoTimelineProgresso(m),
        _secaoHistorico(m),
        _secaoCard(
          titulo: 'Financeiro',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
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
                const SizedBox(height: 12),
                            ],
                            if (totalRef != null && totalRef > 0)
                Text('Produto negociado: ${_moeda.format(totalRef)}'),
              if (frete > 0)
                              Text(
                  'Frete (cobrado no pagamento final): ${_moeda.format(frete)}',
                              ),
                            if (totalRef != null && totalRef > 0)
                              Text(
                  'Total da encomenda (com frete): '
                  '${_moeda.format(totalRef + frete)}',
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
                  'Valor restante a pagar: ${_moeda.format(restanteAPagar)}',
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
                        'Pagamento concluído',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        color: Colors.green.shade800,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            if (entradaCli != null && entradaCli > 0) ...[
                              const SizedBox(height: 12),
                              Text(
                  'Cliente contrapôs entrada: ${_moeda.format(entradaCli)}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                              ),
                              if (msgContra.isNotEmpty) Text(msgContra),
                            ],
            ],
          ),
        ),
        _secaoCard(
          titulo: 'Itens da encomenda',
          child: Column(
            children: [
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
                final img = (it['imagem'] ?? it['foto'] ?? '').toString();
                              return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                                child: Row(
                                  children: [
                      if (img.isNotEmpty)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(
                            img,
                            width: 48,
                            height: 48,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => _itemPlaceholder(),
                          ),
                        )
                      else
                        _itemPlaceholder(),
                      const SizedBox(width: 10),
                                    Expanded(child: Text(nome)),
                                    Text('$q × ${_moeda.format(preco)}'),
                                  ],
                                ),
                              );
                            }),
            ],
          ),
        ),
        _secaoChat(context, st),
        if (st == EncomendaNegociacaoStatus.saldoFinalAguardandoPgto)
          _aviso(
            'Aguardando o cliente pagar o saldo no aplicativo.',
            Colors.blue,
          ),
        if (st == EncomendaNegociacaoStatus.emExecucaoLogistica)
          _aviso(
            'Saldo pago. Acompanhe a entrega em «Meus pedidos».',
            Colors.green,
          ),
        _secaoAcoes(
          st: st,
          emContra: emContra,
          podeAceitarInicio: podeAceitarInicio,
          podePropor: podePropor,
          totalRef: totalRef,
          encomenda: m,
        ),
      ],
    );
  }

  Widget _itemPlaceholder() {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(Icons.inventory_2_outlined, color: Colors.grey.shade400),
    );
  }

  Widget _secaoCard({required String titulo, required Widget child}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                titulo,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 12),
              child,
            ],
          ),
        ),
      ),
    );
  }

  Widget _aviso(String texto, MaterialColor cor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
                                child: Container(
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
          color: cor.shade50,
                                    borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cor.shade200),
        ),
        child: Text(texto, style: TextStyle(color: Colors.grey.shade900)),
      ),
    );
  }

  Widget _secaoTimelineProgresso(Map<String, dynamic> m) {
    final passos = timelineCompactaEncomenda(
      m,
      widget.statusPedidos,
      encomendaId: widget.encomendaId,
    );
    return _secaoCard(
      titulo: 'Progresso da negociação',
      child: Row(
        children: [
          for (var i = 0; i < passos.length; i++) ...[
            if (i > 0)
              Expanded(
                child: Container(
                  height: 2,
                  margin: const EdgeInsets.only(bottom: 18),
                  color: passos[i].concluido && passos[i - 1].concluido
                      ? PainelAdminTheme.roxo.withValues(alpha: 0.35)
                      : Colors.grey.shade200,
                ),
              ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  passos[i].concluido
                      ? Icons.check_circle
                      : Icons.circle_outlined,
                  size: 18,
                  color: passos[i].concluido
                      ? PainelAdminTheme.roxo
                      : Colors.grey.shade400,
                ),
                const SizedBox(height: 4),
                SizedBox(
                  width: 56,
                                  child: Text(
                    passos[i].rotulo,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w600,
                      height: 1.15,
                      color: passos[i].concluido
                          ? PainelAdminTheme.roxo
                          : Colors.grey.shade500,
                                    ),
                                  ),
                                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _secaoHistorico(Map<String, dynamic> m) {
    final historico = m['historico'];
    if (historico is! List || historico.isEmpty) {
      return const SizedBox.shrink();
    }
    return _secaoCard(
      titulo: 'Linha do tempo',
      child: Column(
        children: historico.reversed.take(12).map<Widget>((raw) {
          if (raw is! Map) return const SizedBox.shrink();
          final ev = Map<String, dynamic>.from(raw);
          final tipo = (ev['tipo'] ?? ev['evento'] ?? '').toString();
          final quando = timestampParaDate(ev['em'] ?? ev['criado_em']);
          final fmt = quando != null
              ? DateFormat('dd/MM/yyyy HH:mm', 'pt_BR').format(quando)
              : '';
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.circle, size: 8, color: PainelAdminTheme.roxo),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tipo.isEmpty ? 'Evento' : tipo,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      if (fmt.isNotEmpty)
                        Text(
                          fmt,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Future<void> _enviarMensagemChat(String statusNegociacao) async {
    if (EncomendaNegociacaoStatus.encerradaDefinitivamente(statusNegociacao) ||
        statusNegociacao == EncomendaNegociacaoStatus.emExecucaoLogistica) {
      return;
    }
    final texto = _chatController.text.trim();
    if (texto.isEmpty) return;
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.isEmpty) return;

    setState(() => _enviandoChat = true);
    _chatController.clear();
    try {
      await FirebaseFirestore.instance
          .collection('encomendas')
          .doc(widget.encomendaId)
          .collection('mensagens')
          .add({
        'texto': texto,
        'remetente_id': uid,
        'remetente_tipo': 'loja',
        'data_envio': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao enviar mensagem: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _enviandoChat = false);
    }
  }

  Widget _secaoChat(BuildContext context, String statusNegociacao) {
    final ref = FirebaseFirestore.instance
        .collection('encomendas')
        .doc(widget.encomendaId)
        .collection('mensagens')
        .orderBy('data_envio', descending: false)
        .limit(80);

    final chatEncerrado =
        EncomendaNegociacaoStatus.encerradaDefinitivamente(statusNegociacao) ||
            statusNegociacao == EncomendaNegociacaoStatus.emExecucaoLogistica;

    return _secaoCard(
      titulo: 'Chat da negociação',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: ref.snapshots(),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting &&
                  !snap.hasData) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(12),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                );
              }
              final docs = snap.data?.docs ?? [];
              if (docs.isEmpty) {
                return Text(
                  'Nenhuma mensagem ainda. Envie a primeira mensagem abaixo.',
                  style: TextStyle(color: Colors.grey.shade600, height: 1.35),
                );
              }
              return Column(
                children: docs.map((doc) {
                  final msg = doc.data();
                  final texto =
                      (msg['texto'] ?? msg['mensagem'] ?? '').toString();
                  final remetente =
                      (msg['remetente_nome'] ?? msg['sender_name'] ?? 'Cliente')
                          .toString();
                  final loja = msg['remetente_loja'] == true ||
                      (msg['sender_type'] ?? '').toString() == 'loja' ||
                      (msg['remetente_tipo'] ?? '').toString() == 'loja';
                  return Align(
                    alignment:
                        loja ? Alignment.centerRight : Alignment.centerLeft,
                                child: Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      constraints: const BoxConstraints(maxWidth: 320),
                                  decoration: BoxDecoration(
                        color: loja
                            ? PainelAdminTheme.roxo.withValues(alpha: 0.1)
                            : Colors.grey.shade100,
                                    borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            loja ? 'Loja' : remetente,
                                    style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: loja
                                  ? PainelAdminTheme.roxo
                                  : Colors.grey.shade700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(texto),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              );
            },
          ),
          if (!chatEncerrado) ...[
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: _chatController,
                    minLines: 1,
                    maxLines: 3,
                    decoration: InputDecoration(
                      hintText: 'Escreva uma mensagem…',
                      isDense: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onSubmitted: (_) => _enviarMensagemChat(statusNegociacao),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: _enviandoChat
                      ? null
                      : () => _enviarMensagemChat(statusNegociacao),
                  icon: _enviandoChat
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send_rounded),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _secaoAcoes({
    required String st,
    required bool emContra,
    required bool podeAceitarInicio,
    required bool podePropor,
    required double? totalRef,
    required Map<String, dynamic> encomenda,
  }) {
    return _secaoCard(
      titulo: 'Próxima ação',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
                            if (podeAceitarInicio)
            FilledButton.icon(
              onPressed: _processando ? null : _aceitarNegociacao,
              icon: const Icon(Icons.handshake),
              label: const Text('Aceitar iniciar negociação'),
                                style: FilledButton.styleFrom(
                                  backgroundColor: PainelAdminTheme.laranja,
                                  foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                                  ),
                              ),
                            if (podePropor) ...[
            const SizedBox(height: 8),
            FilledButton.icon(
                                onPressed: _processando
                                    ? null
                  : () => _dialogEnviarProposta(encomenda),
              icon: const Icon(Icons.outgoing_mail),
              label: const Text('Enviar proposta ao cliente'),
                                style: FilledButton.styleFrom(
                                  backgroundColor: PainelAdminTheme.roxo,
                                  foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                                  ),
                              ),
                            ],
                            if (emContra) ...[
                              OutlinedButton(
                                onPressed: _processando
                                    ? null
                  : () => _dialogResponderContra(decisao: 'aceitar'),
              child: const Text('Aceitar contraproposta'),
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
                  : () => _dialogResponderContra(decisao: 'recusar'),
                                child: Text(
                                  'Encerrar negociação',
                style: TextStyle(color: Colors.red.shade700),
                                ),
                              ),
                            ],
          if (st == EncomendaNegociacaoStatus.entradaPagaEmProducao) ...[
            const SizedBox(height: 8),
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
                padding: const EdgeInsets.symmetric(vertical: 14),
                                ),
                                child: const Text('Gerar cobrança do saldo'),
                              ),
                            ],
          if (!EncomendaNegociacaoStatus.encerradaDefinitivamente(st) &&
                                !emContra) ...[
            const SizedBox(height: 12),
                              Builder(
                                builder: (context) {
                                  final podeCancelar =
                                      EncomendaNegociacaoStatus
                        .podeCancelarNegociacaoAntesPagamentoEntrada(st);
                return TextButton(
                  onPressed: (podeCancelar && !_processando)
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
                                  );
                                },
                              ),
                            ],
                          ],
      ),
    );
  }
}

class _DadosPainelEncomenda {
  const _DadosPainelEncomenda({
    required this.nomeCliente,
    required this.telefone,
    required this.endereco,
    required this.totalRef,
    required this.entradaRef,
    required this.frete,
    required this.entradaPaga,
    required this.restante,
    required this.atualizado,
  });

  final String nomeCliente;
  final String telefone;
  final String endereco;
  final double? totalRef;
  final double? entradaRef;
  final double frete;
  final bool entradaPaga;
  final double? restante;
  final DateTime? atualizado;
}
