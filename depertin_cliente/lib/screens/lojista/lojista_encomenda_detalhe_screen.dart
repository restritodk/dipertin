import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../constants/encomenda_negociacao_status.dart';
import '../../utils/codigo_pedido.dart';
import '../../services/firebase_functions_config.dart';
import '../../utils/safe_area_insets.dart';
import '../cliente/chat_pedido_screen.dart';

/// Painel da loja para uma encomenda: aceitar, enviar proposta, responder contraproposta.
class LojistaEncomendaDetalheScreen extends StatefulWidget {
  const LojistaEncomendaDetalheScreen({
    super.key,
    required this.encomendaId,
    required this.uidLoja,
  });

  final String encomendaId;
  final String uidLoja;

  @override
  State<LojistaEncomendaDetalheScreen> createState() =>
      _LojistaEncomendaDetalheScreenState();
}

class _LojistaEncomendaDetalheScreenState
    extends State<LojistaEncomendaDetalheScreen> {
  bool _processando = false;

  static final NumberFormat _moeda = NumberFormat.currency(
    locale: 'pt_BR',
    symbol: r'R$',
  );
  static final DateFormat _dataHora = DateFormat('dd/MM/yyyy HH:mm', 'pt_BR');

  static const Color _roxo = Color(0xFF6A1B9A);
  static const Color _laranja = Color(0xFFFF8F00);
  static const Color _fundo = Color(0xFFF6F3F8);
  static const Color _roxoClaro = Color(0xFFF3E5F5);
  static const Color _laranjaClaro = Color(0xFFFFF3E0);

  double? _parseMoedaFlexivel(String texto) {
    var limpo = texto
        .replaceAll('R\$', '')
        .replaceAll(RegExp(r'\s+'), '')
        .trim();
    if (limpo.isEmpty) return null;
    if (limpo.contains(',') && limpo.contains('.')) {
      limpo = limpo.replaceAll('.', '').replaceAll(',', '.');
    } else {
      limpo = limpo.replaceAll(',', '.');
    }
    return double.tryParse(limpo);
  }

  String _valorCampo(double valor) {
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

  Future<void> _callableNome(String nome, Map<String, dynamic> payload) async {
    setState(() => _processando = true);
    try {
      final callable = appFirebaseFunctions.httpsCallable(
        nome,
        options: HttpsCallableOptions(timeout: const Duration(seconds: 90)),
      );
      await callable.call(payload);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Salvo com sucesso.')));
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(mensagemFirebaseFunctionsException(e)),
          backgroundColor: Colors.red.shade800,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _processando = false);
    }
  }

  Future<void> _aceitarNegociacao() async {
    await _callableNome('encomendaLojaAceitarNegociacao', {
      'encomendaId': widget.encomendaId,
    });
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
    final ok =
        await showDialog<bool>(
          context: context,
          barrierColor: Colors.black.withOpacity(0.42),
          builder: (ctx) => StatefulBuilder(
            builder: (ctx, setDialogState) {
              return Dialog(
                insetPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 22,
                ),
                backgroundColor: Colors.transparent,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final largura = constraints.maxWidth > 460
                        ? 460.0
                        : constraints.maxWidth;
                    return Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: largura,
                          maxHeight: MediaQuery.of(context).size.height * 0.88,
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(28),
                          child: Material(
                            color: Colors.white,
                            child: SingleChildScrollView(
                              padding: EdgeInsets.only(
                                bottom: MediaQuery.of(ctx).viewInsets.bottom,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.fromLTRB(
                                      20,
                                      20,
                                      20,
                                      18,
                                    ),
                                    decoration: const BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [_roxo, Color(0xFF8E24AA)],
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(11),
                                          decoration: BoxDecoration(
                                            color: Colors.white.withOpacity(
                                              0.16,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              16,
                                            ),
                                          ),
                                          child: const Icon(
                                            Icons.request_quote_outlined,
                                            color: Colors.white,
                                            size: 26,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        const Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                'Enviar proposta',
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 20,
                                                  fontWeight: FontWeight.w900,
                                                ),
                                              ),
                                              SizedBox(height: 4),
                                              Text(
                                                'Negocie só o valor do produto. O frete é cobrado à parte no pagamento final.',
                                                style: TextStyle(
                                                  color: Colors.white70,
                                                  fontSize: 12,
                                                  height: 1.25,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.all(18),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(14),
                                          decoration: BoxDecoration(
                                            color: _laranjaClaro,
                                            borderRadius: BorderRadius.circular(
                                              18,
                                            ),
                                            border: Border.all(
                                              color: _laranja.withOpacity(0.20),
                                            ),
                                          ),
                                          child: Row(
                                            children: [
                                              const Icon(
                                                Icons.inventory_2_outlined,
                                                color: _laranja,
                                              ),
                                              const SizedBox(width: 10),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    const Text(
                                                      'Valor exato dos produtos',
                                                      style: TextStyle(
                                                        fontSize: 12,
                                                        fontWeight:
                                                            FontWeight.w800,
                                                        color: Colors.black54,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 2),
                                                    Text(
                                                      totalItens > 0
                                                          ? _moeda.format(
                                                              totalItens,
                                                            )
                                                          : 'Informe o total manualmente',
                                                      style: const TextStyle(
                                                        color: _laranja,
                                                        fontSize: 19,
                                                        fontWeight:
                                                            FontWeight.w900,
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
                                          keyboardType:
                                              const TextInputType.numberWithOptions(
                                                decimal: true,
                                              ),
                                          decoration: InputDecoration(
                                            labelText:
                                                'Valor do produto (proposta)',
                                            helperText:
                                                'Só o produto — frete é cobrado no pagamento final.',
                                            prefixText: 'R\$ ',
                                            filled: true,
                                            fillColor: const Color(0xFFF7F4FA),
                                            border: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(16),
                                              borderSide: BorderSide.none,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 12),
                                        TextField(
                                          controller: entCtrl,
                                          autofocus: true,
                                          keyboardType:
                                              const TextInputType.numberWithOptions(
                                                decimal: true,
                                              ),
                                          decoration: InputDecoration(
                                            labelText: 'Valor da entrada',
                                            hintText: 'Ex.: 50,00',
                                            prefixText: 'R\$ ',
                                            filled: true,
                                            fillColor: const Color(0xFFF7F4FA),
                                            border: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(16),
                                              borderSide: BorderSide.none,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 16),
                                        const Text(
                                          'Como deseja receber a entrada?',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w900,
                                            color: Colors.black87,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Wrap(
                                          spacing: 8,
                                          runSpacing: 8,
                                          children: [
                                            FilterChip(
                                              selected: aceitaPix,
                                              avatar: const Icon(
                                                Icons.pix,
                                                size: 18,
                                              ),
                                              label: const Text('Pix'),
                                              selectedColor: _roxoClaro,
                                              checkmarkColor: _roxo,
                                              onSelected: (v) => setDialogState(
                                                () => aceitaPix = v,
                                              ),
                                            ),
                                            FilterChip(
                                              selected: aceitaCartao,
                                              avatar: const Icon(
                                                Icons.credit_card,
                                                size: 18,
                                              ),
                                              label: const Text('Cartão'),
                                              selectedColor: _roxoClaro,
                                              checkmarkColor: _roxo,
                                              onSelected: (v) => setDialogState(
                                                () => aceitaCartao = v,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          'Essa informação aparecerá para o cliente entender as condições da negociação.',
                                          style: TextStyle(
                                            color: Colors.grey.shade600,
                                            fontSize: 12,
                                            height: 1.35,
                                          ),
                                        ),
                                        const SizedBox(height: 14),
                                        TextField(
                                          controller: obsCtrl,
                                          maxLines: 3,
                                          decoration: InputDecoration(
                                            labelText:
                                                'Observações para o cliente',
                                            hintText:
                                                'Ex.: prazo de produção, detalhes do material ou condição combinada.',
                                            filled: true,
                                            fillColor: const Color(0xFFF7F4FA),
                                            border: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(16),
                                              borderSide: BorderSide.none,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 18),
                                        Row(
                                          children: [
                                            Expanded(
                                              child: TextButton(
                                                onPressed: () =>
                                                    Navigator.pop(ctx, false),
                                                style: TextButton.styleFrom(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        vertical: 13,
                                                      ),
                                                ),
                                                child: const Text('Cancelar'),
                                              ),
                                            ),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: FilledButton.icon(
                                                onPressed: () {
                                                  if (!aceitaPix &&
                                                      !aceitaCartao) {
                                                    ScaffoldMessenger.of(
                                                      context,
                                                    ).showSnackBar(
                                                      const SnackBar(
                                                        content: Text(
                                                          'Selecione Pix, cartão ou os dois.',
                                                        ),
                                                      ),
                                                    );
                                                    return;
                                                  }
                                                  Navigator.pop(ctx, true);
                                                },
                                                icon: const Icon(Icons.send),
                                                label: const Text('Enviar'),
                                                style: FilledButton.styleFrom(
                                                  backgroundColor: _laranja,
                                                  foregroundColor: Colors.white,
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        vertical: 13,
                                                      ),
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          14,
                                                        ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ) ??
        false;
    if (!ok || !mounted) return;
    final total = _parseMoedaFlexivel(totalCtrl.text);
    final ent = _parseMoedaFlexivel(entCtrl.text);
    if (total == null || ent == null || total <= 0 || ent <= 0 || ent > total) {
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

  bool _chatSomenteLeituraEncomenda(String status) {
    return EncomendaNegociacaoStatus.encerradaDefinitivamente(status) ||
        status == EncomendaNegociacaoStatus.saldoFinalAguardandoPgto ||
        status == EncomendaNegociacaoStatus.emExecucaoLogistica;
  }

  String _motivoChatSomenteLeitura(String status) {
    if (EncomendaNegociacaoStatus.encerradaDefinitivamente(status)) {
      return 'Encomenda cancelada ou encerrada. O chat está somente leitura.';
    }
    return 'Encomenda finalizada. O chat está disponível apenas para consulta.';
  }

  void _abrirChat(Map<String, dynamic> m) {
    final nomeCliente = _texto(m, [
      'cliente_nome_snapshot',
      'cliente_nome',
      'nome_cliente',
    ], fallback: 'Cliente');
    final status = (m['status_negociacao'] ?? '').toString();
    final somenteLeitura = _chatSomenteLeituraEncomenda(status);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatPedidoScreen(
          pedidoId: widget.encomendaId,
          lojaId: widget.uidLoja,
          lojaNome: nomeCliente,
          tituloOverride: nomeCliente,
          subtituloOverride: 'Encomenda #${_idCurto(widget.encomendaId)}',
          colecaoRaiz: 'encomendas',
          remetenteTipo: 'loja',
          somenteLeitura: somenteLeitura,
          motivoSomenteLeitura: somenteLeitura
              ? _motivoChatSomenteLeitura(status)
              : null,
        ),
      ),
    );
  }

  static String _idCurto(String id) {
    if (id.length <= 6) return id.toUpperCase();
    return id.substring(0, 6).toUpperCase();
  }

  static double? _numero(Map<String, dynamic> m, String campo) {
    final v = m[campo];
    if (v is num) return v.toDouble();
    return null;
  }

  static String _texto(
    Map<String, dynamic> m,
    List<String> campos, {
    String fallback = '-',
  }) {
    for (final campo in campos) {
      final valor = (m[campo] ?? '').toString().trim();
      if (valor.isNotEmpty && valor != 'null') return valor;
    }
    return fallback;
  }

  String _formatarData(dynamic valor) {
    if (valor is Timestamp) return _dataHora.format(valor.toDate());
    if (valor is DateTime) return _dataHora.format(valor);
    return '-';
  }

  List<String> _formasPagamentoEntrada(Map<String, dynamic> m) {
    final raw = m['formas_pagamento_entrada_loja'];
    if (raw is! List) return const [];
    return raw
        .map((e) => e.toString().trim().toLowerCase())
        .where((e) => e == 'pix' || e == 'cartao')
        .toSet()
        .toList();
  }

  String _formasPagamentoTexto(Map<String, dynamic> m) {
    final formas = _formasPagamentoEntrada(m);
    if (formas.isEmpty) return 'A definir';
    if (formas.contains('pix') && formas.contains('cartao')) {
      return 'Pix ou cartão';
    }
    if (formas.contains('pix')) return 'Pix';
    return 'Cartão';
  }

  List<Map<String, dynamic>> _listaMapas(dynamic raw) {
    final lista = raw is List ? raw : const [];
    return lista
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  String _codigoNumericoCurto(String id) {
    final apenasNumeros = id.replaceAll(RegExp(r'[^0-9]'), '');
    if (apenasNumeros.length >= 6) {
      return apenasNumeros.substring(apenasNumeros.length - 6);
    }
    if (apenasNumeros.length >= 3) return apenasNumeros;

    var hash = 0;
    for (final unidade in id.codeUnits) {
      hash = (hash * 31 + unidade) & 0x7fffffff;
    }
    return (100000 + (hash % 900000)).toString();
  }

  String _textoHistoricoAmigavel(String texto) {
    return texto.replaceAllMapped(
      RegExp(r'\b[Pp]edido\s+([A-Za-z0-9_-]{6,})'),
      (match) => 'pedido nº ${_codigoNumericoCurto(match.group(1)!)}',
    );
  }

  _StatusVisual _statusVisual(String status) {
    switch (status) {
      case EncomendaNegociacaoStatus.aguardandoNegociacao:
        return _StatusVisual(
          label: 'Nova solicitação',
          descricao: 'Revise os itens e aceite iniciar a conversa.',
          icon: Icons.hourglass_top,
          color: Colors.blueGrey.shade700,
          background: Colors.blueGrey.shade50,
        );
      case EncomendaNegociacaoStatus.negociacaoEmAndamento:
        return _StatusVisual(
          label: 'Em negociação',
          descricao: 'Envie uma proposta com total, entrada e observações.',
          icon: Icons.handshake,
          color: Colors.blue.shade700,
          background: Colors.blue.shade50,
        );
      case EncomendaNegociacaoStatus.propostaEnviada:
        return _StatusVisual(
          label: 'Proposta enviada',
          descricao: 'Aguardando o cliente aceitar, pagar ou contrapor.',
          icon: Icons.outgoing_mail,
          color: _laranja,
          background: _laranjaClaro,
        );
      case EncomendaNegociacaoStatus.aguardandoRespostaLojaContraproposta:
        return _StatusVisual(
          label: 'Contraproposta recebida',
          descricao:
              'O cliente sugeriu uma nova entrada. Responda para avançar.',
          icon: Icons.mark_chat_unread,
          color: Colors.deepOrange.shade700,
          background: Colors.orange.shade50,
        );
      case EncomendaNegociacaoStatus.propostaAceitaPendenteEntrada:
        return _StatusVisual(
          label: 'Entrada a gerar',
          descricao: 'Proposta aceita. O cliente precisa finalizar a entrada.',
          icon: Icons.payments,
          color: Colors.deepOrange.shade700,
          background: Colors.deepOrange.shade50,
        );
      case EncomendaNegociacaoStatus.entradaAguardandoPagamento:
        return _StatusVisual(
          label: 'Entrada pendente',
          descricao: 'A cobrança da entrada foi criada e aguarda pagamento.',
          icon: Icons.credit_card,
          color: Colors.deepOrange.shade700,
          background: Colors.deepOrange.shade50,
        );
      case EncomendaNegociacaoStatus.entradaPagaEmProducao:
        return _StatusVisual(
          label: 'Em produção',
          descricao:
              'Entrada paga. Produza e gere a cobrança do saldo ao concluir.',
          icon: Icons.construction,
          color: Colors.teal.shade700,
          background: Colors.teal.shade50,
        );
      case EncomendaNegociacaoStatus.saldoFinalAguardandoPgto:
        return _StatusVisual(
          label: 'Saldo aguardando pagamento',
          descricao: 'A cobrança final foi gerada para o cliente.',
          icon: Icons.request_quote,
          color: Colors.deepOrange.shade700,
          background: Colors.deepOrange.shade50,
        );
      case EncomendaNegociacaoStatus.emExecucaoLogistica:
        return _StatusVisual(
          label: 'Em entrega',
          descricao: 'Saldo pago. A encomenda entrou no fluxo de entrega.',
          icon: Icons.local_shipping,
          color: Colors.green.shade700,
          background: Colors.green.shade50,
        );
      case EncomendaNegociacaoStatus.encerradaRecusadaLoja:
      case EncomendaNegociacaoStatus.encerradaCanceladaCliente:
      case EncomendaNegociacaoStatus.encerradaCanceladaLoja:
        return _StatusVisual(
          label: EncomendaNegociacaoStatus.rotuloPt(status),
          descricao: 'Esta negociação foi encerrada.',
          icon: Icons.cancel,
          color: Colors.red.shade700,
          background: Colors.red.shade50,
        );
      default:
        return _StatusVisual(
          label: EncomendaNegociacaoStatus.rotuloPt(status),
          descricao: 'Acompanhe os detalhes da encomenda.',
          icon: Icons.info,
          color: Colors.grey.shade700,
          background: Colors.grey.shade100,
        );
    }
  }

  bool _temAcaoDaLoja(String status) {
    return status == EncomendaNegociacaoStatus.aguardandoNegociacao ||
        status == EncomendaNegociacaoStatus.negociacaoEmAndamento ||
        status ==
            EncomendaNegociacaoStatus.aguardandoRespostaLojaContraproposta ||
        status == EncomendaNegociacaoStatus.entradaPagaEmProducao;
  }

  Widget _surface({
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(16),
  }) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.black.withOpacity(0.05)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.045),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _sectionTitle(String titulo, IconData icon) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: _roxoClaro,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: _roxo, size: 18),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            titulo,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: Color(0xFF24172D),
            ),
          ),
        ),
      ],
    );
  }

  Widget _statusChip(_StatusVisual visual, {bool compacto = false}) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compacto ? 10 : 12,
        vertical: compacto ? 7 : 9,
      ),
      decoration: BoxDecoration(
        color: visual.background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: visual.color.withOpacity(0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(visual.icon, size: compacto ? 14 : 16, color: visual.color),
          const SizedBox(width: 6),
          Text(
            visual.label,
            style: TextStyle(
              color: visual.color,
              fontWeight: FontWeight.w800,
              fontSize: compacto ? 11 : 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(
    Map<String, dynamic> m,
    String status,
    _StatusVisual visual,
  ) {
    final atualizado = _formatarData(m['atualizado_em']);
    final criado = _formatarData(m['criado_em']);
    final nomeCliente = _texto(m, [
      'cliente_nome_snapshot',
      'cliente_nome',
      'nome_cliente',
    ], fallback: 'Cliente');
    final precisaAcao = _temAcaoDaLoja(status);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_roxo, Color(0xFF8E24AA)],
        ),
        boxShadow: [
          BoxShadow(
            color: _roxo.withOpacity(0.24),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: _statusChip(visual)),
              if (precisaAcao)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: _laranja,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.notifications_active,
                        color: Colors.white,
                        size: 14,
                      ),
                      SizedBox(width: 5),
                      Text(
                        'Ação',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            'Encomenda #${_idCurto(widget.encomendaId)}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 25,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Cliente: $nomeCliente',
            style: TextStyle(
              color: Colors.white.withOpacity(0.9),
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            visual.descricao,
            style: TextStyle(
              color: Colors.white.withOpacity(0.86),
              height: 1.35,
            ),
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _miniPill(Icons.schedule, 'Criada $criado'),
              _miniPill(Icons.update, 'Atualizada $atualizado'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _miniPill(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withOpacity(0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 14),
          const SizedBox(width: 6),
          Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  static String? _telefoneDoMapa(Map<String, dynamic> m) {
    for (final campo in const [
      'cliente_telefone_snapshot',
      'cliente_telefone',
      'telefone_cliente',
      'telefone',
    ]) {
      final valor = (m[campo] ?? '').toString().trim();
      if (valor.isNotEmpty && valor != 'null') return valor;
    }
    return null;
  }

  static String? _telefoneDoPerfil(Map<String, dynamic> dados) {
    for (final campo in const [
      'telefone',
      'whatsapp',
      'celular',
      'phone',
      'telefone_contato',
    ]) {
      final valor = (dados[campo] ?? '').toString().trim();
      if (valor.isNotEmpty) return valor;
    }
    return null;
  }

  Future<void> _abrirWhatsAppCliente(String telefone) async {
    var numero = telefone.replaceAll(RegExp(r'[^0-9]'), '');
    if (numero.isEmpty) return;
    if (!numero.startsWith('55') && numero.length >= 10) {
      numero = '55$numero';
    }
    final urls = <Uri>[
      Uri.parse('https://wa.me/$numero'),
      Uri.parse('https://api.whatsapp.com/send?phone=$numero'),
    ];
    for (final uri in urls) {
      try {
        if (await launchUrl(uri, mode: LaunchMode.externalApplication)) {
          return;
        }
      } catch (_) {}
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Não foi possível abrir o WhatsApp.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Widget _infoTileTelefoneWhatsapp({
    required String telefone,
  }) {
    final corTel = Colors.green.shade700;
    final podeAbrir = telefone.replaceAll(RegExp(r'[^0-9]'), '').length >= 10;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: podeAbrir ? () => _abrirWhatsAppCliente(telefone) : null,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: corTel.withOpacity(0.07),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: corTel.withOpacity(0.12)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.phone, size: 19, color: corTel),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Telefone',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      telefone,
                      style: const TextStyle(
                        color: Color(0xFF24172D),
                        fontWeight: FontWeight.w800,
                        height: 1.25,
                      ),
                    ),
                    if (podeAbrir) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Toque para conversar no WhatsApp',
                        style: TextStyle(
                          color: corTel,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (podeAbrir)
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF25D366).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.chat,
                    color: Color(0xFF25D366),
                    size: 22,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTelefoneClienteTile(Map<String, dynamic> m) {
    final telefoneDoc = _telefoneDoMapa(m);
    if (telefoneDoc != null) {
      return _infoTileTelefoneWhatsapp(telefone: telefoneDoc);
    }

    final clienteId = (m['cliente_id'] ?? '').toString().trim();
    if (clienteId.isEmpty) {
      return _infoTile(
        icon: Icons.phone,
        label: 'Telefone',
        value: 'Não informado',
        color: Colors.green.shade700,
      );
    }

    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: FirebaseFirestore.instance
          .collection('users')
          .doc(clienteId)
          .get(),
      builder: (context, snap) {
        String? telefone;
        if (snap.hasData && snap.data!.exists) {
          telefone = _telefoneDoPerfil(snap.data!.data() ?? {});
        }
        if (telefone == null || telefone.isEmpty) {
          return _infoTile(
            icon: Icons.phone,
            label: 'Telefone',
            value: 'Não informado',
            color: Colors.green.shade700,
          );
        }
        return _infoTileTelefoneWhatsapp(telefone: telefone);
      },
    );
  }

  Widget _infoTile({
    required IconData icon,
    required String label,
    required String value,
    Color color = _roxo,
  }) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: color.withOpacity(0.07),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.12)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 19, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value.isEmpty ? '-' : value,
                  style: const TextStyle(
                    color: Color(0xFF24172D),
                    fontWeight: FontWeight.w800,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _valorCard(String label, String value, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withOpacity(0.16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: Colors.grey.shade700,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 19,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildClienteEntrega(Map<String, dynamic> m) {
    final nomeCliente = _texto(m, [
      'cliente_nome_snapshot',
      'cliente_nome',
      'nome_cliente',
    ], fallback: 'Cliente');
    final endereco = _texto(m, ['endereco_entrega'], fallback: '-');
    final tipoEntrega = _texto(m, ['tipo_entrega'], fallback: 'entrega');
    final taxa = _numero(m, 'taxa_entrega_snapshot') ?? 0;
    final tipoRotulo = tipoEntrega == 'retirada'
        ? 'Retirada no balcão'
        : 'Entrega';

    return _surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('Cliente e entrega', Icons.person_pin_circle),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, c) {
              final largo = c.maxWidth >= 620;
              final w = largo ? (c.maxWidth - 12) / 2 : c.maxWidth;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  SizedBox(
                    width: w,
                    child: _infoTile(
                      icon: Icons.person,
                      label: 'Cliente',
                      value: nomeCliente,
                      color: Colors.blue.shade700,
                    ),
                  ),
                  SizedBox(
                    width: w,
                    child: _buildTelefoneClienteTile(m),
                  ),
                  SizedBox(
                    width: w,
                    child: _infoTile(
                      icon: tipoEntrega == 'retirada'
                          ? Icons.storefront
                          : Icons.location_on,
                      label: tipoRotulo,
                      value: endereco,
                      color: _laranja,
                    ),
                  ),
                  SizedBox(
                    width: w,
                    child: _infoTile(
                      icon: Icons.delivery_dining,
                      label: 'Taxa de entrega',
                      value: _moeda.format(taxa),
                      color: _roxo,
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _processando ? null : () => _abrirChat(m),
              icon: const Icon(Icons.chat_bubble_outline),
              label: const Text('Abrir chat da encomenda'),
              style: OutlinedButton.styleFrom(
                foregroundColor: _roxo,
                side: BorderSide(color: _roxo.withOpacity(0.35)),
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFinanceiro(Map<String, dynamic> m) {
    final st = (m['status_negociacao'] ?? '').toString();
    final valorCatalogo = _numero(m, 'valor_catalogo_referencia');
    final totalRef = _numero(m, 'valor_total_referencia');
    final entradaRef = _numero(m, 'valor_entrada_loja');
    final entradaCliente = _numero(m, 'entrada_contraproposta_cliente');
    final tipoEntrega = _texto(m, ['tipo_entrega'], fallback: 'entrega');
    final frete = tipoEntrega == 'retirada'
        ? 0.0
        : (_numero(m, 'taxa_entrega_snapshot') ?? 0);

    // Entrada já paga (produção em diante).
    final entradaPaga =
        st == EncomendaNegociacaoStatus.entradaPagaEmProducao ||
        st == EncomendaNegociacaoStatus.saldoFinalAguardandoPgto ||
        st == EncomendaNegociacaoStatus.emExecucaoLogistica;
    final totalmentePago = st == EncomendaNegociacaoStatus.emExecucaoLogistica;

    // Valor total da encomenda = valor negociado + frete.
    final totalEncomenda = totalRef != null ? totalRef + frete : null;
    // Restante a pagar pelo cliente = total da encomenda - entrada paga.
    final restanteAPagar = (totalRef != null && entradaRef != null)
        ? ((totalRef + frete) - entradaRef).clamp(0, double.infinity).toDouble()
        : null;

    final textoPagamentoEntrada = (entradaPaga && entradaRef != null)
        ? 'Entrada paga: ${_moeda.format(entradaRef)}'
        : _formasPagamentoTexto(m);

    return _surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('Resumo financeiro', Icons.payments_outlined),
          const SizedBox(height: 14),
          if (totalmentePago) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.green.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.verified, color: Colors.green.shade700, size: 26),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Pagamento concluído',
                          style: TextStyle(
                            color: Colors.green.shade900,
                            fontWeight: FontWeight.w900,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Totalmente pago — entrada e saldo recebidos.',
                          style: TextStyle(
                            color: Colors.green.shade800,
                            fontWeight: FontWeight.w600,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
          ],
          LayoutBuilder(
            builder: (context, c) {
              final largura = c.maxWidth >= 560
                  ? (c.maxWidth - 12) / 2
                  : c.maxWidth;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  SizedBox(
                    width: largura,
                    child: _valorCard(
                      'Valor de catálogo',
                      valorCatalogo != null
                          ? _moeda.format(valorCatalogo)
                          : '-',
                      Colors.blueGrey.shade700,
                      Icons.receipt_long,
                    ),
                  ),
                  SizedBox(
                    width: largura,
                    child: _valorCard(
                      'Produto negociado',
                      totalRef != null ? _moeda.format(totalRef) : 'A definir',
                      _laranja,
                      Icons.price_check,
                    ),
                  ),
                  if (frete > 0)
                    SizedBox(
                      width: largura,
                      child: _valorCard(
                        'Frete',
                        _moeda.format(frete),
                        Colors.blue.shade700,
                        Icons.delivery_dining,
                      ),
                    ),
                  if (totalEncomenda != null)
                    SizedBox(
                      width: largura,
                      child: _valorCard(
                        'Total da encomenda (com frete)',
                        _moeda.format(totalEncomenda),
                        Colors.deepPurple.shade700,
                        Icons.summarize,
                      ),
                    ),
                  SizedBox(
                    width: largura,
                    child: _valorCard(
                      'Entrada da loja',
                      entradaRef != null
                          ? _moeda.format(entradaRef)
                          : 'A definir',
                      _roxo,
                      Icons.account_balance_wallet,
                    ),
                  ),
                  SizedBox(
                    width: largura,
                    child: _valorCard(
                      'Pagamento da entrada',
                      textoPagamentoEntrada,
                      Colors.indigo.shade700,
                      Icons.payments_outlined,
                    ),
                  ),
                  if (!totalmentePago)
                    SizedBox(
                      width: largura,
                      child: _valorCard(
                        'Valor restante a pagar pelo cliente',
                        restanteAPagar != null
                            ? _moeda.format(restanteAPagar)
                            : 'A definir',
                        Colors.teal.shade700,
                        Icons.savings,
                      ),
                    ),
                  if (entradaCliente != null && entradaCliente > 0)
                    SizedBox(
                      width: c.maxWidth,
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.orange.shade200),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.priority_high,
                              color: Colors.orange.shade800,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Contraproposta do cliente: entrada de ${_moeda.format(entradaCliente)}',
                                style: TextStyle(
                                  color: Colors.orange.shade900,
                                  fontWeight: FontWeight.w800,
                                  height: 1.3,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          if (entradaPaga && totalRef != null && entradaRef != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.green.shade100),
              ),
              child: Text(
                'Na entrega, o recebimento líquido da loja inclui a entrada já '
                'paga (sem taxa da plataforma) + o restante do produto após a '
                'taxa. O frete vai ao entregador (após taxa).',
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.35,
                  color: Colors.green.shade900,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMensagens(Map<String, dynamic> m) {
    final msgCliente = (m['mensagem_cliente'] ?? '').toString().trim();
    final obsLoja = (m['observacoes_loja'] ?? '').toString().trim();
    final msgContra = (m['mensagem_contraproposta_cliente'] ?? '')
        .toString()
        .trim();

    if (msgCliente.isEmpty && obsLoja.isEmpty && msgContra.isEmpty) {
      return _surface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle('Mensagens e observações', Icons.notes),
            const SizedBox(height: 12),
            Text(
              'Nenhuma observação registrada ainda. Use o chat ou a proposta para alinhar os detalhes com o cliente.',
              style: TextStyle(color: Colors.grey.shade700, height: 1.35),
            ),
          ],
        ),
      );
    }

    return _surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('Mensagens e observações', Icons.notes),
          const SizedBox(height: 14),
          if (msgCliente.isNotEmpty)
            _messageBox(
              title: 'Pedido do cliente',
              text: msgCliente,
              icon: Icons.chat_outlined,
              color: Colors.blue.shade700,
            ),
          if (obsLoja.isNotEmpty) ...[
            if (msgCliente.isNotEmpty) const SizedBox(height: 10),
            _messageBox(
              title: 'Observações enviadas pela loja',
              text: obsLoja,
              icon: Icons.storefront,
              color: _roxo,
            ),
          ],
          if (msgContra.isNotEmpty) ...[
            if (msgCliente.isNotEmpty || obsLoja.isNotEmpty)
              const SizedBox(height: 10),
            _messageBox(
              title: 'Mensagem da contraproposta',
              text: msgContra,
              icon: Icons.swap_horiz,
              color: _laranja,
            ),
          ],
        ],
      ),
    );
  }

  Widget _messageBox({
    required String title,
    required String text,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.07),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.13)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  text,
                  style: const TextStyle(
                    height: 1.36,
                    color: Color(0xFF2C2430),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItens(Map<String, dynamic> m) {
    final itens = _listaMapas(m['itens']);
    return _surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('Itens da encomenda', Icons.inventory_2_outlined),
          const SizedBox(height: 14),
          if (itens.isEmpty)
            Text(
              'Nenhum item encontrado nesta encomenda.',
              style: TextStyle(color: Colors.grey.shade700),
            )
          else
            ...List.generate(itens.length, (i) {
              final it = itens[i];
              return Padding(
                padding: EdgeInsets.only(
                  bottom: i == itens.length - 1 ? 0 : 10,
                ),
                child: _itemTile(it),
              );
            }),
        ],
      ),
    );
  }

  Widget _itemTile(Map<String, dynamic> it) {
    final nome = _texto(it, ['nome', 'titulo'], fallback: 'Produto');
    final imagem = _texto(it, ['imagem', 'foto', 'image'], fallback: '');
    final quantidade = (it['quantidade'] is num)
        ? (it['quantidade'] as num).toInt()
        : 1;
    final preco = (it['preco_ref'] is num)
        ? (it['preco_ref'] as num).toDouble()
        : ((it['preco'] is num) ? (it['preco'] as num).toDouble() : 0.0);
    final subtotal = preco * quantidade;
    final variacoes = it['variacoes'] is Map
        ? Map<String, dynamic>.from(it['variacoes'] as Map)
        : <String, dynamic>{};
    final cor = (variacoes['cor'] ?? '').toString().trim();
    final tamanho = (variacoes['tamanho'] ?? '').toString().trim();
    final resumo = (it['variacoes_resumo'] ?? '').toString().trim();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFAFB),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: imagem.isNotEmpty
                ? Image.network(
                    imagem,
                    width: 58,
                    height: 58,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _itemPlaceholder(),
                  )
                : _itemPlaceholder(),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  nome,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF24172D),
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  '$quantidade x ${_moeda.format(preco)}',
                  style: TextStyle(
                    color: Colors.grey.shade700,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (cor.isNotEmpty ||
                    tamanho.isNotEmpty ||
                    resumo.isNotEmpty) ...[
                  const SizedBox(height: 7),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      if (cor.isNotEmpty) _tagItem('Cor: $cor', Icons.palette),
                      if (tamanho.isNotEmpty)
                        _tagItem('Tamanho: $tamanho', Icons.straighten),
                      if (cor.isEmpty && tamanho.isEmpty && resumo.isNotEmpty)
                        _tagItem(resumo, Icons.tune),
                      _tagItem(
                        _texto(it, ['tipo_venda'], fallback: '').isEmpty
                            ? (it['eh_encomenda'] == true
                                  ? 'Sob encomenda'
                                  : 'Produto normal')
                            : _texto(it, ['tipo_venda']),
                        Icons.inventory_2_outlined,
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _moeda.format(subtotal),
            style: const TextStyle(
              color: _laranja,
              fontWeight: FontWeight.w900,
              fontSize: 15,
            ),
          ),
        ],
      ),
    );
  }

  Widget _tagItem(String texto, IconData icon) {
    if (texto.trim().isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _roxo.withOpacity(0.08),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: _roxo),
          const SizedBox(width: 4),
          Text(
            texto,
            style: const TextStyle(
              color: _roxo,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _itemPlaceholder() {
    return Container(
      width: 58,
      height: 58,
      color: _roxoClaro,
      child: const Icon(Icons.shopping_bag_outlined, color: _roxo),
    );
  }

  Widget _buildHistorico(Map<String, dynamic> m) {
    final historico = _listaMapas(m['historico']);
    return _surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('Linha do tempo', Icons.timeline),
          const SizedBox(height: 14),
          if (historico.isEmpty)
            Text(
              'O histórico aparecerá conforme a negociação avançar.',
              style: TextStyle(color: Colors.grey.shade700),
            )
          else
            ...List.generate(historico.length, (i) {
              final h = historico[i];
              final texto = _textoHistoricoAmigavel(
                _texto(h, ['texto'], fallback: 'Atualização'),
              );
              final tipo = _texto(h, ['tipo'], fallback: 'evento');
              final quando = _formatarData(h['em']);
              final ultimo = i == historico.length - 1;
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Column(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: const BoxDecoration(
                          color: _laranja,
                          shape: BoxShape.circle,
                        ),
                      ),
                      if (!ultimo)
                        Container(
                          width: 2,
                          height: 42,
                          color: _laranja.withOpacity(0.22),
                        ),
                    ],
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(bottom: ultimo ? 0 : 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            texto,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF24172D),
                              height: 1.25,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '$quando - ${tipo.replaceAll('_', ' ')}',
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            }),
        ],
      ),
    );
  }

  Widget _buildDadosTecnicos(Map<String, dynamic> m) {
    final pedidoEntrada = _texto(m, ['pedido_entrada_id'], fallback: '');
    final pedidoSaldo = _texto(m, ['pedido_saldo_final_id'], fallback: '');
    final status = (m['status_negociacao'] ?? '').toString();
    final statusRotulo = EncomendaNegociacaoStatus.rotuloPt(status);
    return _surface(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('Informações de acompanhamento', Icons.fact_check),
          const SizedBox(height: 12),
          _referenciaTile(
            icon: Icons.confirmation_number_outlined,
            label: 'Código da encomenda',
            value: '#${_idCurto(widget.encomendaId)}',
            detail: 'Use este código para identificar esta negociação.',
            technicalValue: widget.encomendaId,
            color: _roxo,
          ),
          if (pedidoEntrada.isNotEmpty)
            _referenciaTile(
              icon: Icons.payments_outlined,
              label: 'Pagamento da entrada',
              value: 'Cobrança ${CodigoPedido.gerar(pedidoEntrada)}',
              detail:
                  'Pedido criado para o cliente pagar o valor inicial combinado.',
              technicalValue: pedidoEntrada,
              color: _laranja,
            ),
          if (pedidoSaldo.isNotEmpty)
            _referenciaTile(
              icon: Icons.request_quote_outlined,
              label: 'Pagamento do saldo',
              value: 'Cobrança ${CodigoPedido.gerar(pedidoSaldo)}',
              detail:
                  'Pedido criado para o cliente pagar o restante da encomenda.',
              technicalValue: pedidoSaldo,
              color: Colors.teal.shade700,
            ),
          _referenciaTile(
            icon: Icons.flag_outlined,
            label: 'Situação atual',
            value: statusRotulo,
            detail: _statusVisual(status).descricao,
            technicalValue: status,
            color: Colors.blueGrey.shade700,
            ultimo: true,
          ),
        ],
      ),
    );
  }

  Widget _referenciaTile({
    required IconData icon,
    required String label,
    required String value,
    required String detail,
    required String technicalValue,
    required Color color,
    bool ultimo = false,
  }) {
    return Padding(
      padding: EdgeInsets.only(bottom: ultimo ? 0 : 10),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: color.withOpacity(0.07),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.13)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: color,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    value,
                    style: const TextStyle(
                      color: Color(0xFF24172D),
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    detail,
                    style: TextStyle(
                      color: Colors.grey.shade700,
                      fontSize: 12,
                      height: 1.3,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (technicalValue.isNotEmpty &&
                      technicalValue != value.replaceFirst('#', '')) ...[
                    const SizedBox(height: 6),
                    Text(
                      'ID completo: $technicalValue',
                      style: TextStyle(
                        color: Colors.grey.shade500,
                        fontSize: 11,
                        height: 1.25,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAcoes(
    String st, {
    required double? totalRef,
    required Map<String, dynamic> encomenda,
    required bool compacto,
  }) {
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
        _primaryButton(
          label: 'Aceitar iniciar negociação',
          icon: Icons.handshake,
          color: _laranja,
          onPressed: _processando ? null : _aceitarNegociacao,
        ),
      );
    }
    if (podePropor) {
      botoes.add(
        _primaryButton(
          label: 'Enviar proposta ao cliente',
          icon: Icons.outgoing_mail,
          color: _roxo,
          onPressed: _processando
              ? null
              : () => _dialogEnviarProposta(encomenda),
        ),
      );
    }
    if (emContra) {
      botoes.addAll([
        _primaryButton(
          label: 'Aceitar contraproposta',
          icon: Icons.check_circle,
          color: Colors.green.shade700,
          onPressed: _processando
              ? null
              : () => _dialogResponderContra(decisao: 'aceitar'),
        ),
        _primaryButton(
          label: 'Enviar nova proposta',
          icon: Icons.swap_horiz,
          color: _roxo,
          onPressed: _processando
              ? null
              : () => _dialogResponderContra(
                  decisao: 'contrapor',
                  totalAtual: totalRef,
                ),
        ),
        _outlineDangerButton(
          label: 'Encerrar negociação',
          onPressed: _processando
              ? null
              : () => _dialogResponderContra(decisao: 'recusar'),
        ),
      ]);
    }
    if (podeGerarSaldo) {
      botoes.add(
        _primaryButton(
          label: 'Gerar cobrança do saldo',
          icon: Icons.request_quote,
          color: _roxo,
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
        _outlineDangerButton(
          label: 'Cancelar negociação',
          onPressed: (podeCancelar && !_processando)
              ? _confirmarCancelarNegociacaoLoja
              : null,
        ),
      );
    }

    return _surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('Próxima ação', Icons.touch_app_outlined),
          const SizedBox(height: 12),
          if (botoes.isEmpty)
            Text(
              'Não há ação disponível para este status no momento.',
              style: TextStyle(color: Colors.grey.shade700, height: 1.35),
            )
          else
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: botoes
                  .map(
                    (b) => SizedBox(
                      width: compacto ? double.infinity : 260,
                      child: b,
                    ),
                  )
                  .toList(),
            ),
          if (!encerrada && !podeCancelar && !emContra) ...[
            const SizedBox(height: 10),
            Text(
              'Após o pagamento da entrada, o cancelamento por aqui fica indisponível.',
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _primaryButton({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback? onPressed,
  }) {
    return FilledButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: FilledButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontWeight: FontWeight.w800),
      ),
    );
  }

  Widget _outlineDangerButton({
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontWeight: FontWeight.w800),
      ),
    );
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
    final ok =
        await showDialog<bool>(
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
    final novaEnt = double.tryParse(entCtrl.text.replaceAll(',', '.').trim());
    if (novoTotal == null ||
        novaEnt == null ||
        novoTotal <= 0 ||
        novaEnt <= 0 ||
        novaEnt > novoTotal) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Valores inválidos.')));
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
    final ok =
        await showDialog<bool>(
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
      backgroundColor: _fundo,
      appBar: AppBar(
        backgroundColor: _roxo,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: Text('Encomenda #${_idCurto(widget.encomendaId)}'),
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: ref.snapshots(),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Erro ao carregar encomenda: ${snap.error}',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          if (!snap.hasData || !snap.data!.exists) {
            return const Center(child: CircularProgressIndicator());
          }
          final m = snap.data!.data() ?? {};
          if (m['loja_id']?.toString() != widget.uidLoja) {
            return const Center(
              child: Text('Esta encomenda não pertence à sua loja.'),
            );
          }

          final st = (m['status_negociacao'] ?? '').toString();
          final visual = _statusVisual(st);
          final totalRef = _numero(m, 'valor_total_referencia');

          return LayoutBuilder(
            builder: (context, constraints) {
              final compacto = constraints.maxWidth < 700;
              final maxWidth = compacto ? double.infinity : 920.0;
              return SafeArea(
                top: false,
                minimum: EdgeInsets.zero,
                child: SingleChildScrollView(
                padding: diPertinScrollPaddingInner(
                  context,
                  left: 16,
                  top: 16,
                  right: 16,
                  extraBottom: 28,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: maxWidth),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildHeader(m, st, visual),
                        const SizedBox(height: 14),
                        _buildAcoes(
                          st,
                          totalRef: totalRef,
                          encomenda: m,
                          compacto: compacto,
                        ),
                        const SizedBox(height: 14),
                        _buildClienteEntrega(m),
                        const SizedBox(height: 14),
                        _buildFinanceiro(m),
                        const SizedBox(height: 14),
                        _buildMensagens(m),
                        const SizedBox(height: 14),
                        _buildItens(m),
                        const SizedBox(height: 14),
                        _buildHistorico(m),
                        const SizedBox(height: 14),
                        _buildDadosTecnicos(m),
                      ],
                    ),
                  ),
                ),
              ),
              );
            },
          );
        },
      ),
    );
  }
}

class _StatusVisual {
  const _StatusVisual({
    required this.label,
    required this.descricao,
    required this.icon,
    required this.color,
    required this.background,
  });

  final String label;
  final String descricao;
  final IconData icon;
  final Color color;
  final Color background;
}
