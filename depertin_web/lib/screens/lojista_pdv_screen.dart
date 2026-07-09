import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../navigation/painel_nav_controller.dart';
import '../navigation/painel_navigation_scope.dart';
import '../theme/painel_admin_theme.dart';
import '../utils/firestore_web_safe.dart';
import '../utils/lojista_painel_context.dart';
import '../utils/pedido_recibo_pdf.dart';
import '../utils/codigo_pedido.dart';
import '../services/comercial_clientes_service.dart';
import '../services/comercial_credito_service.dart';
import '../services/firebase_functions_config.dart';
import '../models/comercial_cliente.dart';

/// Modelo local para itens do carrinho no PDV
class PdvItem {
  final String id;
  final String nome;
  final double preco;
  final String? imagem;
  int quantidade;

  PdvItem({
    required this.id,
    required this.nome,
    required this.preco,
    this.imagem,
    this.quantidade = 1,
  });

  double get subtotal => preco * quantidade;

  Map<String, dynamic> toMap() => {
    'produto_id': id,
    'nome': nome,
    'preco': preco,
    'quantidade': quantidade,
    'valor_total': subtotal,
  };
}

/// Módulo de PDV (Ponto de Venda) profissional do DiPertin.
/// Focado em agilidade, visual premium e experiência de operador.
class LojistaPdvScreen extends StatefulWidget {
  const LojistaPdvScreen({super.key});

  @override
  State<LojistaPdvScreen> createState() => _LojistaPdvScreenState();
}

class _LojistaPdvScreenState extends State<LojistaPdvScreen> {
  final TextEditingController _buscaController = TextEditingController();
  final FocusNode _buscaFocus = FocusNode();
  final FocusNode _atalhosFocus = FocusNode();
  PainelNavController? _navController;
  
  // Estado da venda
  final List<PdvItem> _carrinho = [];
  String _categoriaSelecionada = 'Todos';
  double _descontoValor = 0;
  bool _descontoPorcentagem = false;
  String? _descontoMotivo;
  Map<String, dynamic>? _clienteSelecionado;
  String? _observacaoVenda;
  bool _mostrarCalculadora = false;
  Offset _posicaoCalculadora = const Offset(100, 300);
  
  // Dados de contexto
  String? _uidLoja;
  Map<String, dynamic>? _dadosLoja;
  Map<String, dynamic>? _sessaoCaixa;
  String? _idSessaoCaixa;
  bool get _caixaAberto => _sessaoCaixa != null;
  DateTime _ultimaAtualizacao = DateTime.now();
  bool _processandoVenda = false;
  bool _criandoCobrancaPix = false;

  @override
  void initState() {
    super.initState();
    _buscaFocus.addListener(_onBuscaFocusChanged);
    _carregarDadosIniciais();
    _iniciarRelogio();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _vincularNavegacaoPainel();
      _reativarAtalhosTeclado();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _vincularNavegacaoPainel();
  }

  @override
  void dispose() {
    _navController?.removeListener(_onRotaPainelAlterada);
    _buscaFocus.removeListener(_onBuscaFocusChanged);
    _buscaFocus.dispose();
    _atalhosFocus.dispose();
    _buscaController.dispose();
    super.dispose();
  }

  void _vincularNavegacaoPainel() {
    final nav = PainelNavigationScope.maybeOf(context);
    if (identical(nav, _navController)) return;
    _navController?.removeListener(_onRotaPainelAlterada);
    _navController = nav;
    _navController?.addListener(_onRotaPainelAlterada);
    if (_navController?.currentRoute == '/pdv') {
      _reativarAtalhosTeclado();
    }
  }

  void _onRotaPainelAlterada() {
    if (_navController?.currentRoute == '/pdv') {
      _reativarAtalhosTeclado();
    }
  }

  void _onBuscaFocusChanged() {
    if (!_buscaFocus.hasFocus) {
      _reativarAtalhosTeclado();
    }
  }

  /// CallbackShortcuts exige foco na subárvore do PDV; ao trocar de aba o foco fica no menu.
  void _reativarAtalhosTeclado() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_navController != null && _navController!.currentRoute != '/pdv') {
        return;
      }
      if (_isInputFocused()) return;
      if (!_atalhosFocus.hasFocus) {
        _atalhosFocus.requestFocus();
      }
    });
  }

  void _iniciarRelogio() {
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted) {
        setState(() => _ultimaAtualizacao = DateTime.now());
        _iniciarRelogio();
      }
    });
  }

  Future<void> _carregarDadosIniciais() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final docUser = await FirebaseFirestore.instance.collection('users').doc(uid).get();
    final dadosUser = safeWebDocData(docUser);
    final lid = uidLojaEfetivo(dadosUser, uid);
    setState(() => _uidLoja = lid);
    if (lid != uid) {
      final docLoja = await FirebaseFirestore.instance.collection('users').doc(lid).get();
      setState(() => _dadosLoja = safeWebDocData(docLoja));
    } else {
      setState(() => _dadosLoja = dadosUser);
    }
    
    // Buscar sessão de caixa aberta para esta loja neste terminal
    await _buscarSessaoCaixaAtiva(lid);

    final pendente = PdvClientePendente.consumir();
    if (pendente != null && mounted) {
      setState(() => _clienteSelecionado = pendente);
    }
  }

  Future<void> _buscarSessaoCaixaAtiva(String lojaId) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('sessoes_caixa')
          .where('loja_id', isEqualTo: lojaId)
          .where('status', isEqualTo: 'aberto')
          .where('terminal', isEqualTo: 'Terminal 01') // Por enquanto fixo como Terminal 01
          .limit(1)
          .get();
      
      if (snap.docs.isNotEmpty) {
        setState(() {
          _idSessaoCaixa = snap.docs.first.id;
          _sessaoCaixa = snap.docs.first.data();
        });
      } else {
        setState(() {
          _idSessaoCaixa = null;
          _sessaoCaixa = null;
        });
      }
    } catch (e) {
      print('Erro ao buscar sessão de caixa: $e');
    }
  }

  bool _isInputFocused() {
    final primary = FocusManager.instance.primaryFocus;
    if (primary == null) return false;
    // Se o foco atual for em um campo editável (EditableText)
    final widgetStr = primary.context?.widget.runtimeType.toString() ?? '';
    return widgetStr.contains('EditableText') || primary.context?.widget is EditableText;
  }

  Future<void> _abrirModalCliente() async {
    final resultado = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => _ModalSelecionarCliente(lojaId: _uidLoja),
    );

    if (resultado != null) {
      setState(() {
        _clienteSelecionado = resultado;
      });
    }
    _reativarAtalhosTeclado();
  }

  // --- Lógica de Negócio ---

  double get _subtotalVenda => _carrinho.fold(0, (sum, item) => sum + item.subtotal);
  
  double get _valorDescontoCalculado {
    if (_descontoPorcentagem) {
      return _subtotalVenda * (_descontoValor / 100);
    }
    return _descontoValor;
  }

  double get _totalVenda => (_subtotalVenda - _valorDescontoCalculado).clamp(0, double.infinity);

  void _adicionarAoCarrinho(Map<String, dynamic> prod, String id) {
    setState(() {
      final preco = (prod['precoOferta'] ?? prod['precoOriginal'] ?? prod['preco'] ?? 0.0).toDouble();
      final index = _carrinho.indexWhere((item) => item.id == id);
      if (index >= 0) {
        _carrinho[index].quantidade++;
      } else {
        String? img;
        if (prod['imagemUrl'] != null) {
          img = prod['imagemUrl'].toString();
        } else if (prod['imagens'] is List && (prod['imagens'] as List).isNotEmpty) {
          img = prod['imagens'][0].toString();
        }

        _carrinho.add(PdvItem(
          id: id,
          nome: prod['nome'] ?? 'Produto sem nome',
          preco: preco,
          imagem: img,
        ));
      }
    });
  }

  void _resetarVendaCompleta() {
    setState(() {
      _carrinho.clear();
      _descontoValor = 0;
      _descontoPorcentagem = false;
      _descontoMotivo = null;
      _clienteSelecionado = null;
      _observacaoVenda = null;
    });
  }

  void _removerDoCarrinho(int index) {
    setState(() {
      _carrinho.removeAt(index);
      if (_carrinho.isEmpty) {
        _descontoValor = 0;
        _descontoPorcentagem = false;
        _descontoMotivo = null;
        _clienteSelecionado = null;
        _observacaoVenda = null;
      }
    });
  }

  void _ajustarQuantidade(int index, int delta) {
    setState(() {
      _carrinho[index].quantidade = (_carrinho[index].quantidade + delta).clamp(1, 999);
    });
  }

  Future<void> _abrirCaixaFlow() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => const _ModalAbrirCaixaPasso1(),
    );

    if (result == null) return;

    final valorInicial = result['valor'] as double;
    final observacao = result['observacao'] as String;

    final confirmado = await showDialog<bool>(
      context: context,
      builder: (ctx) => _ModalAbrirCaixaPasso2(
        valor: valorInicial,
        observacao: observacao,
        dadosLoja: _dadosLoja,
      ),
    );

    if (confirmado != true) return;

    setState(() => _processandoVenda = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      final docRef = await FirebaseFirestore.instance.collection('sessoes_caixa').add({
        'loja_id': _uidLoja,
        'operador_id': user?.uid,
        'operador_nome': _dadosLoja?['nome_fantasia'] ?? _dadosLoja?['nome'],
        'terminal': 'Terminal 01',
        'data_abertura': FieldValue.serverTimestamp(),
        'status': 'aberto',
        'valor_inicial': valorInicial,
        'observacao_abertura': observacao,
        'vendas_dinheiro': 0,
        'vendas_pix': 0,
        'vendas_credito': 0,
        'vendas_debito': 0,
        'total_vendido': 0,
      });

      final newDoc = await docRef.get();
      setState(() {
        _idSessaoCaixa = docRef.id;
        _sessaoCaixa = newDoc.data();
        _processandoVenda = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Caixa aberto com sucesso!')),
        );
      }
    } catch (e) {
      setState(() => _processandoVenda = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao abrir caixa: $e')),
        );
      }
    }
  }

  Future<void> _fecharCaixaFlow() async {
    if (_idSessaoCaixa == null) return;

    setState(() => _processandoVenda = true);

    try {
      // 1. Buscar resumo de vendas
      final dataAbertura = _sessaoCaixa?['data_abertura'] as Timestamp;
      
      final snap = await FirebaseFirestore.instance
          .collection('pedidos')
          .where('loja_id', isEqualTo: _uidLoja)
          .where('status', isEqualTo: 'entregue')
          .where('origem', isEqualTo: 'pdv_web')
          .where('data_pedido', isGreaterThanOrEqualTo: dataAbertura)
          .get();

      double d = 0, p = 0, cc = 0, cd = 0, total = 0;
      for (final doc in snap.docs) {
        final data = doc.data();
        final v = (data['total'] ?? 0.0) as double;
        final f = data['forma_pagamento']?.toString().toLowerCase() ?? '';
        
        if (f.contains('dinheiro')) d += v;
        else if (f.contains('pix')) p += v;
        else if (f.contains('crédito') || f.contains('credito')) cc += v;
        else if (f.contains('débito') || f.contains('debito')) cd += v;
        
        total += v;
      }

      setState(() => _processandoVenda = false);

      final result = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (ctx) => _ModalFecharCaixa(
          idSessao: _idSessaoCaixa!,
          sessao: _sessaoCaixa!,
          resumo: {
            'dinheiro': d,
            'pix': p,
            'credito': cc,
            'debito': cd,
            'total': total,
          },
        ),
      );

      if (result == null) return;

      // 2. Gravar fechamento
      setState(() => _processandoVenda = true);
      
      final valorInformado = result['valor_encontrado'] as double;
      final diferenca = result['diferenca'] as double;

      await FirebaseFirestore.instance.collection('sessoes_caixa').doc(_idSessaoCaixa).update({
        'status': 'fechado',
        'data_fechamento': FieldValue.serverTimestamp(),
        'vendas_dinheiro': d,
        'vendas_pix': p,
        'vendas_credito': cc,
        'vendas_debito': cd,
        'total_vendido': total,
        'valor_final_informado': valorInformado,
        'diferenca': diferenca,
      });

      setState(() {
        _idSessaoCaixa = null;
        _sessaoCaixa = null;
        _processandoVenda = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Caixa fechado com sucesso!')),
        );
      }

    } catch (e) {
      setState(() => _processandoVenda = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao fechar caixa: $e')),
        );
      }
    }
  }

  Future<void> _finalizarVenda() async {
    try {
    if (_carrinho.isEmpty) return;
    if (!_caixaAberto) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('🔴 Abra o caixa antes de finalizar uma venda.')),
      );
      return;
    }

    // Atualiza dados de crédito do cliente comercial (se houver)
    Map<String, dynamic>? clientePgto = _clienteSelecionado;
    if (clientePgto != null &&
        clientePgto['origem'] == 'clientes_comercial' &&
        _uidLoja != null) {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(_uidLoja)
          .collection('clientes_comercial')
          .doc(clientePgto['id']?.toString())
          .get();
      if (snap.exists) {
        final c = ComercialCliente.fromDoc(
          snap.id,
          _uidLoja!,
          safeWebDocData(snap),
        );
        clientePgto = c.toPdvMap();
        if (mounted) setState(() => _clienteSelecionado = clientePgto);
      }
    }

    // Modal de escolha da forma de pagamento profissional e elegante
    final formaPgto = await showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => _ModalSelecionarPagamento(
        totalVenda: _totalVenda,
        clienteCredito: clientePgto,
      ),
    );

    if (formaPgto == null) return;

    _ConfigCreditoPdv? configCredito;
    if (formaPgto == 'Crédito do cliente') {
      if (clientePgto == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Selecione um cliente com crédito habilitado (F3).'),
          ),
        );
        return;
      }
      configCredito = await showDialog<_ConfigCreditoPdv>(
        context: context,
        builder: (ctx) => _ModalConfigCreditoCliente(
          totalVenda: _totalVenda,
          cliente: clientePgto!,
        ),
      );
      if (configCredito == null) return;
    }

    double? valorRecebido;
    double? troco;

    if (formaPgto == 'Dinheiro') {
      final resultadoDinheiro = await showDialog<_ResultadoDinheiro>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => _ModalTrocoDinheiro(totalVenda: _totalVenda),
      );
      if (resultadoDinheiro == null) return; // Cancela se o usuário fechar/voltar
      valorRecebido = resultadoDinheiro.valorRecebido;
      troco = resultadoDinheiro.troco;
    }

    // ─── FLUXO PIX ──────────────────────────────────────────────
    bool pixConfirmado = false;
    _DadosCobrancaPix? dadosCobranca;
    _ResultadoPagamentoPix? resultadoPix;

    if (formaPgto == 'PIX') {
      if (_uidLoja == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('❌ Erro: loja não identificada.')),
        );
        return;
      }

      // Guarda anti-duplicidade: só criar uma cobrança por vez
      if (_criandoCobrancaPix) return;
      _criandoCobrancaPix = true;

      setState(() => _processandoVenda = true);
      try {
        // 1. Criar cobrança PIX no backend
        final vendaId = FirebaseFirestore.instance.collection('gestao_comercial_vendas').doc().id;
        final result = await callFirebaseFunctionSafe('gestaoComercialCriarPagamentoPix', region: 'southamerica-east1', parameters: {
          'lojaId': _uidLoja,
          'vendaId': vendaId,
          'valor': _totalVenda,
          'itens': _carrinho.map((e) => {
            'id': e.id,
            'nome': e.nome,
            'preco': e.preco,
            'quantidade': e.quantidade,
          }).toList(),
          'clienteId': _clienteSelecionado?['id'] ?? null,
          'clienteNome': _clienteSelecionado?['nome'] ?? null,
          'operadorId': FirebaseAuth.instance.currentUser?.uid ?? '',
          'origem': 'pdv_gestao_comercial',
        });

        // LOG TEMPORARIO — requisito #10
        final pixCopiaECola = result['pixCopiaECola']?.toString() ?? '';
        print('PIX COPIA E COLA RECEBIDO: $pixCopiaECola');
        print('PIX startsWith 000201: ${pixCopiaECola.startsWith('000201')}');
        print('PIX contains 6304 CRC: ${RegExp(r'6304[0-9A-Fa-f]{4}$').hasMatch(pixCopiaECola)}');

        dadosCobranca = _DadosCobrancaPix(
          cobrancaId: result['cobrancaId'],
          paymentId: result['paymentId'],
          qrCodeBase64: result['qrCodeBase64'],
          pixCopiaECola: pixCopiaECola,
          expiresAt: DateTime.parse(result['expiresAt']),
          status: result['status'],
          vendaId: vendaId,
          valor: _totalVenda,
        );

        // 2. Abrir modal PIX premium
        final pixResult = await showDialog<_ResultadoPagamentoPix>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => _ModalPagamentoPix(
            dadosCobranca: dadosCobranca!,
            clienteNome: _clienteSelecionado?['nome'],
            operadorNome: FirebaseAuth.instance.currentUser?.displayName ?? 'Operador',
            uidLoja: _uidLoja!,
          ),
        );

        if (pixResult == null) {
          _criandoCobrancaPix = false;
          setState(() => _processandoVenda = false);
          return;
        }

        resultadoPix = pixResult;
        pixConfirmado = pixResult.pago;
        valorRecebido = pixResult.valorRecebido;

        if (!pixConfirmado) {
          _criandoCobrancaPix = false;
          setState(() => _processandoVenda = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('❌ Pagamento PIX não confirmado.')),
          );
          return;
        }

        // 3. Mostrar modal de confirmação premium
        final r = resultadoPix!;
        final dc = dadosCobranca!;
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => _ModalConfirmacaoPix(
            valorRecebido: r.valorRecebido,
            clienteNome: _clienteSelecionado?['nome'] ?? 'Cliente PDV',
            codigoVenda: r.codigoVenda,
            formaPagamento: 'PIX',
            dataHora: r.dataHora,
            operadorNome: FirebaseAuth.instance.currentUser?.displayName ?? 'Operador',
            gateway: 'Mercado Pago',
            vendaId: dc.vendaId,
            uidLoja: _uidLoja!,
            dadosLoja: _dadosLoja,
          ),
        );

        // 4. Limpar carrinho e finalizar
        if (mounted) {
          setState(() {
            _carrinho.clear();
            _descontoValor = 0;
            _descontoPorcentagem = false;
            _descontoMotivo = null;
            _clienteSelecionado = null;
            _observacaoVenda = null;
            _processandoVenda = false;
            _criandoCobrancaPix = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('✅ PIX recebido! Venda finalizada com sucesso!')),
          );
        }
        return; // PIX finalizado — sai do fluxo padrão
      } catch (e) {
        _criandoCobrancaPix = false;
        setState(() => _processandoVenda = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('❌ Erro no pagamento PIX: $e')),
          );
        }
        return;
      }
    }

    setState(() => _processandoVenda = true);

    try {
      final db = FirebaseFirestore.instance;
      final batch = db.batch();
      final pedidoRef = db.collection('pedidos').doc();
      final pedidoId = pedidoRef.id;
      final codigo = CodigoPedido.gerar(pedidoId);

      // 1. Criar o documento do pedido enriquecido
      final dadosPedido = {
        'loja_id': _uidLoja,
        'loja_nome': _dadosLoja?['nome_fantasia'] ?? _dadosLoja?['nome'],
        'loja_endereco': _dadosLoja?['endereco'],
        'loja_telefone': _dadosLoja?['telefone'],
        'cliente_id': _clienteSelecionado?['id'] ?? 'venda_balcao',
        'cliente_nome': _clienteSelecionado?['nome'] ?? 'Cliente PDV',
        if (_clienteSelecionado?['telefone'] != null) 'cliente_telefone': _clienteSelecionado!['telefone'],
        if (_clienteSelecionado?['cpf'] != null) 'cliente_cpf': _clienteSelecionado!['cpf'],
        'status': 'entregue',
        'tipo_entrega': 'retirada',
        'forma_pagamento': formaPgto,
        if (valorRecebido != null) 'valor_recebido': valorRecebido,
        if (troco != null) 'troco': troco,
        'subtotal': _subtotalVenda,
        'desconto': _valorDescontoCalculado,
        'desconto_tipo': _descontoPorcentagem ? 'porcentagem' : 'reais',
        'desconto_valor': _descontoValor,
        'desconto_total_calculado': _valorDescontoCalculado,
        if (_descontoMotivo != null) 'desconto_motivo': _descontoMotivo,
        if (_observacaoVenda != null) 'observacao': _observacaoVenda,
        'total': _totalVenda,
        if (formaPgto == 'Crédito do cliente' && configCredito != null) ...{
          'pagamento_credito_loja': true,
          'quantidade_parcelas_credito': configCredito.parcelas,
          'valor_entrada_credito': configCredito.entrada,
        },
        'data_pedido': FieldValue.serverTimestamp(),
        'codigo_pedido': codigo,
        'origem': 'pdv_web',
        'sessao_caixa_id': _idSessaoCaixa,
        'itens': _carrinho.map((e) => e.toMap()).toList(),
      };

      batch.set(pedidoRef, dadosPedido);

      // Crédito antes do pedido: se falhar, nada é gravado e o estoque não muda.
      if (formaPgto == 'Crédito do cliente' &&
          configCredito != null &&
          _uidLoja != null &&
          _clienteSelecionado != null) {
        await ComercialCreditoService.criarVendaCreditoDoPdv(
          lojaId: _uidLoja!,
          clienteId: _clienteSelecionado!['id'].toString(),
          pedidoId: pedidoId,
          codigoPedido: codigo,
          valorTotal: _totalVenda,
          quantidadeParcelas: configCredito.parcelas,
          valorEntrada: configCredito.entrada,
          diaVencimentoCredito:
              _clienteSelecionado!['dia_vencimento_credito'] as int?,
        );
      }

      // Pedido só após pagamento/crédito OK. Baixa de estoque via Cloud Function
      // (baixarEstoquePedidoOnCreate) quando status = entregue.
      await batch.commit();

      // Hook: replicar venda para o histórico (gestao_comercial_vendas)
      if (_uidLoja != null) {
        final isCredito = formaPgto == 'Crédito do cliente';
        final valorEntrada =
            (isCredito && configCredito != null) ? configCredito.entrada : 0.0;
        await db.collection('gestao_comercial_vendas').doc(pedidoId).set({
          'loja_id': _uidLoja,
          'codigo_venda': codigo,
          'cliente_id': _clienteSelecionado?['id'] ?? 'venda_balcao',
          'cliente_nome': _clienteSelecionado?['nome'] ?? 'Cliente PDV',
          'cliente_documento': _clienteSelecionado?['cpf'] ?? '',
          'cliente_telefone': _clienteSelecionado?['telefone'] ?? '',
          'cliente_email': _clienteSelecionado?['email'] ?? '',
          'itens': _carrinho.map((e) => e.toMap()).toList(),
          'quantidade_itens':
              _carrinho.fold<int>(0, (s, e) => s + e.quantidade),
          'forma_pagamento': formaPgto,
          'valor_total': _totalVenda,
          'valor_pago': isCredito ? valorEntrada : _totalVenda,
          'valor_pendente':
              isCredito ? (_totalVenda - valorEntrada) : 0.0,
          'desconto_total': _valorDescontoCalculado,
          'juros_total': 0.0,
          'multa_total': 0.0,
          'status': isCredito ? 'pendente' : 'pago',
          'operador_id': FirebaseAuth.instance.currentUser?.uid,
          'operador_nome':
              FirebaseAuth.instance.currentUser?.displayName ?? '',
          'caixa_id': _idSessaoCaixa,
          if (isCredito && configCredito != null)
            'parcelas': configCredito.parcelas,
          'data_venda': FieldValue.serverTimestamp(),
          'created_at': FieldValue.serverTimestamp(),
          'updated_at': FieldValue.serverTimestamp(),
        });
      }

      if (mounted) {
        setState(() {
          _carrinho.clear();
          _descontoValor = 0;
          _descontoPorcentagem = false;
          _descontoMotivo = null;
          _clienteSelecionado = null;
          _observacaoVenda = null;
          _processandoVenda = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ Venda finalizada com sucesso!')),
        );

        // Perguntar sobre impressão do recibo
        final imprimir = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text('Venda Concluída'),
            content: const Text('Deseja imprimir o comprovante de venda para o cliente?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Não')),
              FilledButton.icon(
                onPressed: () => Navigator.pop(ctx, true),
                icon: const Icon(Icons.print_rounded),
                label: const Text('Sim, Imprimir'),
              ),
            ],
          ),
        );

        if (imprimir == true) {
          await PedidoReciboPdf.imprimir(
            pedidoId: pedidoId,
            codigoPedido: codigo,
            pedido: dadosPedido,
            dadosLoja: _dadosLoja,
            nomeClienteFallback: 'Cliente PDV',
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _processandoVenda = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Erro ao finalizar venda: $e')),
        );
      }
    }
    } finally {
      _reativarAtalhosTeclado();
    }
  }

  // --- Modais ---

  Future<void> _abrirModalDesconto() async {
    final resultado = await showDialog<_ResultadoDesconto>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => _ModalDescontoPdv(
        subtotal: _subtotalVenda,
        valorAtual: _descontoValor,
        porcentagemAtual: _descontoPorcentagem,
        motivoAtual: _descontoMotivo,
      ),
    );

    if (resultado != null) {
      setState(() {
        _descontoValor = resultado.valor;
        _descontoPorcentagem = resultado.tipo == 'porcentagem';
        _descontoMotivo = resultado.motivo;
      });
    }
    _reativarAtalhosTeclado();
  }

  Future<void> _abrirModalObservacao() async {
    final resultado = await showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => _ModalObservacaoPdv(observacaoInicial: _observacaoVenda),
    );

    if (resultado != null) {
      setState(() {
        _observacaoVenda = resultado.trim().isEmpty ? null : resultado.trim();
      });
    }
    _reativarAtalhosTeclado();
  }

  // --- UI Principal ---

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final size = MediaQuery.of(context).size;
    final isDesktop = size.width > 1200;

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.f2): () {
          if (!_isInputFocused()) {
            _buscaFocus.requestFocus();
          }
        },
        const SingleActivator(LogicalKeyboardKey.f3): () {
          if (!_isInputFocused()) {
            _abrirModalCliente();
          }
        },
        const SingleActivator(LogicalKeyboardKey.f4): () {
          if (!_isInputFocused()) {
            _abrirModalDesconto();
          }
        },
        const SingleActivator(LogicalKeyboardKey.f5): () {
          if (!_isInputFocused()) {
            _finalizarVenda();
          }
        },
        const SingleActivator(LogicalKeyboardKey.f6): () {
          if (!_isInputFocused()) {
            _abrirModalObservacao();
          }
        },
        const SingleActivator(LogicalKeyboardKey.f7): () {
          if (!_isInputFocused()) {
            setState(() => _mostrarCalculadora = !_mostrarCalculadora);
          }
        },
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (_mostrarCalculadora) {
            setState(() => _mostrarCalculadora = false);
          }
        },
      },
      child: Focus(
        focusNode: _atalhosFocus,
        autofocus: true,
        child: Scaffold(
          backgroundColor: const Color(0xFFF8F9FC),
          body: Stack(
            children: [
              Column(
                children: [
                  _buildHeader(textTheme),
                  Expanded(
                    child: Row(
                      children: [
                        // Catálogo de Produtos
                        Expanded(
                          flex: 7,
                          child: _buildMainSection(textTheme),
                        ),
                        
                        // Painel de Checkout Lateral
                        Container(
                          width: isDesktop ? 420 : 380,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.04),
                                blurRadius: 20,
                                offset: const Offset(-10, 0),
                              ),
                            ],
                          ),
                          child: _buildCheckoutPanel(textTheme),
                        ),
                      ],
                    ),
                  ),
                  _buildFooterShortcuts(textTheme),
                ],
              ),
              if (_mostrarCalculadora)
                Positioned(
                  left: _posicaoCalculadora.dx,
                  top: _posicaoCalculadora.dy,
                  child: GestureDetector(
                    onPanUpdate: (details) {
                      setState(() {
                        _posicaoCalculadora += details.delta;
                      });
                    },
                    child: _ModalCalculadora(
                      onClose: () => setState(() => _mostrarCalculadora = false),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(TextTheme textTheme) {
    final df = DateFormat('dd/MM/yyyy HH:mm:ss');
    final moeda = NumberFormat.currency(locale: 'pt_BR', symbol: r'R$');
    
    return Container(
      height: 72,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFF0F0F0))),
      ),
      child: Row(
        children: [
          Image.asset('assets/logo.png', height: 40, errorBuilder: (_, __, ___) => const Icon(Icons.storefront, color: PainelAdminTheme.roxo)),
          const SizedBox(width: 16),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Olá, ${_dadosLoja?['nome_fantasia'] ?? _dadosLoja?['nome'] ?? 'Operador'}! 👋',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: PainelAdminTheme.roxo,
                ),
              ),
              Row(
                children: [
                  Text(
                    'Ponto de Venda DiPertin • Terminal 01',
                    style: textTheme.bodySmall?.copyWith(color: Colors.grey.shade600),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: _caixaAberto ? Colors.green.withValues(alpha: 0.1) : Colors.red.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      _caixaAberto ? '🟢 Caixa Aberto' : '🔴 Caixa Fechado',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: _caixaAberto ? Colors.green.shade700 : Colors.red.shade700,
                      ),
                    ),
                  ),
                  if (_caixaAberto) ...[
                    const SizedBox(width: 12),
                    Text(
                      'Valor inicial: ${moeda.format(_sessaoCaixa?['valor_inicial'] ?? 0)}',
                      style: textTheme.bodySmall?.copyWith(color: Colors.grey.shade700, fontWeight: FontWeight.bold),
                    ),
                  ],
                ],
              ),
            ],
          ),
          const Spacer(),
          
          _buildHeaderAction(
            icon: Icons.point_of_sale_rounded,
            label: _caixaAberto ? 'Fechar Caixa' : 'Abrir Caixa',
            color: _caixaAberto ? Colors.orange.shade800 : Colors.green.shade700,
            onTap: _caixaAberto ? _fecharCaixaFlow : _abrirCaixaFlow,
          ),
          const SizedBox(width: 12),
          _buildHeaderAction(
            icon: Icons.move_to_inbox_rounded,
            label: 'Abrir Gaveta',
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Gaveta aberta com sucesso')),
              );
            },
          ),
          const VerticalDivider(indent: 20, endIndent: 20, width: 40),
          
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(
                children: [
                  Container(width: 8, height: 8, decoration: const BoxDecoration(color: Colors.green, shape: BoxShape.circle)),
                  const SizedBox(width: 8),
                  const Text('Online', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                ],
              ),
              Text(df.format(_ultimaAtualizacao), style: GoogleFonts.jetBrainsMono(fontSize: 12, color: Colors.grey.shade600)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMainSection(TextTheme textTheme) {
    return _uidLoja == null
        ? const Center(child: CircularProgressIndicator())
        : StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('produtos')
                .where('lojista_id', isEqualTo: _uidLoja)
                .snapshots(),
            builder: (context, snap) {
              final todosDocs = snap.data?.docs ?? [];

              // Extrair categorias dinâmicas
              final cats = <String>{'Todos'};
              for (final d in todosDocs) {
                final p = d.data() as Map;
                final c = (p['categoria_nome'] ?? p['categoria'] ?? '').toString().trim();
                if (c.isNotEmpty) cats.add(c);
              }

              // Filtro Local (Busca + Categoria)
              var docs = todosDocs;
              if (_categoriaSelecionada != 'Todos') {
                docs = docs.where((d) {
                  final p = d.data() as Map;
                  return (p['categoria_nome'] ?? p['categoria'] ?? '') == _categoriaSelecionada;
                }).toList();
              }
              if (_buscaController.text.isNotEmpty) {
                final b = _buscaController.text.toLowerCase();
                docs = docs.where((d) {
                  final m = d.data() as Map;
                  final nome = (m['nome'] ?? '').toString().toLowerCase();
                  final sku = (m['sku'] ?? '').toString().toLowerCase();
                  final codigo = (m['codigo_barras'] ?? '').toString().toLowerCase();
                  return nome.contains(b) || sku.contains(b) || codigo.contains(b);
                }).toList();
              }

              return Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Barra de Busca Profissional
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            height: 56,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              boxShadow: PainelAdminTheme.sombraCardSuave(),
                            ),
                            child: TextField(
                              controller: _buscaController,
                              focusNode: _buscaFocus,
                              onChanged: (v) => setState(() {}),
                              decoration: InputDecoration(
                                hintText: 'Buscar produto por nome, código ou SKU... (F2)',
                                prefixIcon: const Icon(Icons.search_rounded, color: PainelAdminTheme.roxo),
                                suffixIcon: _buscaController.text.isNotEmpty
                                    ? IconButton(
                                        onPressed: () => setState(() => _buscaController.clear()),
                                        icon: const Icon(Icons.close))
                                    : Container(
                                        margin: const EdgeInsets.all(10),
                                        padding: const EdgeInsets.symmetric(horizontal: 8),
                                        decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(6)),
                                        child: const Center(widthFactor: 1, child: Text('F2', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
                                      ),
                                border: InputBorder.none,
                                contentPadding: const EdgeInsets.symmetric(vertical: 18),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        _buildModernIconButton(Icons.qr_code_scanner_rounded, onTap: () {}),
                        const SizedBox(width: 12),
                        _buildModernIconButton(Icons.add_rounded, label: 'Novo Produto', color: PainelAdminTheme.laranja, onTap: () {}),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Filtros de Categoria (Dinâmicos)
                    _buildCategoryFilters(cats.toList()),
                    const SizedBox(height: 24),

                    // Catálogo em Grid
                    Expanded(
                      child: snap.hasError
                          ? Center(child: Text('Erro: ${snap.error}'))
                          : (snap.connectionState == ConnectionState.waiting && !snap.hasData)
                              ? const Center(child: CircularProgressIndicator())
                              : docs.isEmpty
                                  ? _buildEmptyState()
                                  : GridView.builder(
                                      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                                        maxCrossAxisExtent: 220,
                                        childAspectRatio: 0.75,
                                        crossAxisSpacing: 20,
                                        mainAxisSpacing: 20,
                                      ),
                                      itemCount: docs.length,
                                      itemBuilder: (context, index) {
                                        final d = docs[index];
                                        return _buildProductCard(d.data() as Map<String, dynamic>, d.id);
                                      },
                                    ),
                    ),
                  ],
                ),
              );
            },
          );
  }

  Widget _buildCategoryFilters(List<String> categories) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: categories.map((c) {
          final sel = _categoriaSelecionada == c;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(c),
              selected: sel,
              onSelected: (v) {
                setState(() => _categoriaSelecionada = c);
              },
              selectedColor: PainelAdminTheme.roxo,
              labelStyle: TextStyle(
                color: sel ? Colors.white : Colors.black,
                fontWeight: sel ? FontWeight.bold : FontWeight.normal,
              ),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              backgroundColor: Colors.white,
              elevation: sel ? 4 : 0,
              side: BorderSide(color: sel ? PainelAdminTheme.roxo : Colors.grey.shade200),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildCheckoutPanel(TextTheme textTheme) {
    return Column(
      children: [
        // Cabeçalho da Venda
        Padding(
          padding: const EdgeInsets.all(24.0),
          child: Row(
            children: [
              Text('Venda atual', style: GoogleFonts.plusJakartaSans(fontSize: 20, fontWeight: FontWeight.w800)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: PainelAdminTheme.roxo.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(20)),
                child: Text('${_carrinho.length} itens', style: const TextStyle(color: PainelAdminTheme.roxo, fontWeight: FontWeight.bold, fontSize: 12)),
              ),
            ],
          ),
        ),

        // Cliente Selecionado (F3)
        if (_clienteSelecionado != null)
          Container(
            margin: const EdgeInsets.only(left: 24, right: 24, bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: PainelAdminTheme.roxo.withOpacity(0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: PainelAdminTheme.roxo.withOpacity(0.15)),
            ),
            child: Row(
              children: [
                const Icon(Icons.person_outline_rounded, size: 18, color: PainelAdminTheme.roxo),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'CLIENTE',
                        style: GoogleFonts.plusJakartaSans(fontSize: 10, fontWeight: FontWeight.w800, color: PainelAdminTheme.roxo, letterSpacing: 0.5),
                      ),
                      Text(
                        _clienteSelecionado!['nome'] ?? 'Cliente sem nome',
                        style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.bold, color: const Color(0xFF1E1B4B)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  icon: const Icon(Icons.close_rounded, size: 16, color: Colors.grey),
                  onPressed: () => setState(() => _clienteSelecionado = null),
                ),
              ],
            ),
          ),

        // Observação da Venda (F6)
        if (_observacaoVenda != null && _observacaoVenda!.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(left: 24, right: 24, bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFBEB),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFFEF3C7)),
            ),
            child: Row(
              children: [
                const Icon(Icons.note_alt_outlined, size: 18, color: Color(0xFFD97706)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'OBSERVAÇÃO',
                        style: GoogleFonts.plusJakartaSans(fontSize: 10, fontWeight: FontWeight.w800, color: const Color(0xFFB45309), letterSpacing: 0.5),
                      ),
                      Text(
                        _observacaoVenda!,
                        style: GoogleFonts.plusJakartaSans(fontSize: 12, color: const Color(0xFF78350F), fontWeight: FontWeight.w500),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  icon: const Icon(Icons.close_rounded, size: 16, color: Colors.grey),
                  onPressed: () => setState(() => _observacaoVenda = null),
                ),
              ],
            ),
          ),
        
        // Lista de Itens
        Expanded(
          child: _carrinho.isEmpty 
            ? _buildEmptyCart(textTheme)
            : ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: _carrinho.length,
                separatorBuilder: (_, __) => Divider(color: Colors.grey.shade100, height: 1),
                itemBuilder: (context, index) => _buildCartItem(_carrinho[index], index),
              ),
        ),
        
        // Resumo e Botões
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: Colors.grey.shade100)),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 15, offset: const Offset(0, -5))],
          ),
          child: Column(
            children: [
              _buildValueRow('Subtotal', _subtotalVenda),
              _buildValueRow('Desconto', -_valorDescontoCalculado, isDiscount: true),
              if (_descontoMotivo != null && _descontoMotivo!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 6),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      const Icon(Icons.info_outline_rounded, size: 12, color: Colors.grey),
                      const SizedBox(width: 4),
                      Text(
                        'Motivo: $_descontoMotivo',
                        style: GoogleFonts.plusJakartaSans(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 12),
              InkWell(
                onTap: _abrirModalDesconto,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                  decoration: BoxDecoration(border: Border.all(color: PainelAdminTheme.roxo.withValues(alpha: 0.2)), borderRadius: BorderRadius.circular(8)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(Icons.local_offer_outlined, size: 14, color: PainelAdminTheme.roxo),
                      SizedBox(width: 8),
                      Text('Adicionar desconto (F4)', style: TextStyle(color: PainelAdminTheme.roxo, fontWeight: FontWeight.w600, fontSize: 12)),
                    ],
                  ),
                ),
              ),
              const Divider(height: 40),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Total', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  Text(
                    NumberFormat.currency(locale: 'pt_BR', symbol: r'R$').format(_totalVenda),
                    style: GoogleFonts.plusJakartaSans(fontSize: 32, fontWeight: FontWeight.w800, color: PainelAdminTheme.roxo),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              
              // Botão Finalizar
              SizedBox(
                width: double.infinity,
                height: 60,
                child: FilledButton(
                  onPressed: (_carrinho.isEmpty || _processandoVenda || !_caixaAberto) ? null : _finalizarVenda,
                  style: FilledButton.styleFrom(
                    backgroundColor: PainelAdminTheme.laranja,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  child: _processandoVenda 
                    ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(!_caixaAberto ? 'Caixa Fechado' : 'Finalizar venda', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                          if (_caixaAberto) ...[
                            const SizedBox(width: 12),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(4)),
                              child: const Text('F5', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ],
                      ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: _buildSecondaryBtn('Pagamento parcial', Icons.payments_outlined, () {})),
                  const SizedBox(width: 12),
                  Expanded(child: _buildSecondaryBtn('Cancelar', Icons.close_rounded, _resetarVendaCompleta, isDanger: true)),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFooterShortcuts(TextTheme textTheme) {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      color: const Color(0xFF1A1A2E),
      child: Row(
        children: [
          _buildShortcut('F3', 'Clientes', Icons.person_search_rounded),
          _buildShortcut('F4', 'Desconto', Icons.local_offer_rounded),
          _buildShortcut('F6', 'Observação', Icons.note_alt_rounded),
          _buildShortcut('F7', 'Calculadora', Icons.calculate_rounded),
          const Spacer(),
          Text('PDV DiPertin Local v1.0', style: GoogleFonts.plusJakartaSans(color: Colors.white24, fontSize: 11, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  // --- Widgets Auxiliares ---

  Widget _buildHeaderAction({required IconData icon, required String label, Color? color, VoidCallback? onTap}) {
    final c = color ?? Colors.black87;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: c.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: c.withValues(alpha: 0.1)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: c),
            const SizedBox(width: 8),
            Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c)),
          ],
        ),
      ),
    );
  }

  Widget _buildModernIconButton(IconData icon, {String? label, Color? color, VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: color ?? Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: color == null ? PainelAdminTheme.sombraCardSuave() : null,
        ),
        child: Row(
          children: [
            Icon(icon, size: 24, color: color == null ? PainelAdminTheme.roxo : Colors.white),
            if (label != null) ...[
              const SizedBox(width: 8),
              Text(label, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildProductCard(Map<String, dynamic> prod, String id) {
    final preco = (prod['precoOferta'] ?? prod['precoOriginal'] ?? prod['preco'] ?? 0.0).toDouble();
    
    String? url;
    if (prod['imagemUrl'] != null && prod['imagemUrl'].toString().isNotEmpty) {
      url = prod['imagemUrl'].toString();
    } else if (prod['imagens'] is List && (prod['imagens'] as List).isNotEmpty) {
      url = prod['imagens'][0].toString();
    }

    return InkWell(
      onTap: () => _adicionarAoCarrinho(prod, id),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                children: [
                  Container(
                    margin: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8F9FC),
                      borderRadius: BorderRadius.circular(12),
                      image: url != null ? DecorationImage(image: NetworkImage(url), fit: BoxFit.cover) : null,
                    ),
                    child: url == null ? const Center(child: Icon(Icons.image_outlined, color: Colors.grey)) : null,
                  ),
                  if (prod['usa_variacoes'] == true)
                    Positioned(
                      top: 12,
                      right: 12,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(color: Colors.blue, shape: BoxShape.circle),
                        child: const Icon(Icons.tune, size: 12, color: Colors.white),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    prod['nome'] ?? 'Sem nome',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold, fontSize: 13, color: const Color(0xFF1E1B4B)),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    NumberFormat.currency(locale: 'pt_BR', symbol: r'R$').format(preco),
                    style: const TextStyle(color: PainelAdminTheme.laranja, fontWeight: FontWeight.w800, fontSize: 16),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.inventory_2_outlined, size: 11, color: Colors.grey.shade400),
                      const SizedBox(width: 4),
                      Text(
                        'Estoque: ${prod['estoque_qtd'] ?? 0}',
                        style: TextStyle(color: Colors.grey.shade500, fontSize: 11, fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCartItem(PdvItem item, int index) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFFF8F9FC),
              borderRadius: BorderRadius.circular(8),
              image: (item.imagem != null && item.imagem!.isNotEmpty) ? DecorationImage(image: NetworkImage(item.imagem!), fit: BoxFit.cover) : null,
            ),
            child: (item.imagem == null || item.imagem!.isEmpty) ? const Icon(Icons.image_outlined, size: 20, color: Colors.grey) : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.nome, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(NumberFormat.currency(locale: 'pt_BR', symbol: r'R$').format(item.preco), style: TextStyle(color: Colors.grey.shade600, fontSize: 11)),
              ],
            ),
          ),
          Row(
            children: [
              _buildQtyAction(Icons.remove, () => _ajustarQuantidade(index, -1)),
              SizedBox(width: 32, child: Center(child: Text('${item.quantidade}', style: const TextStyle(fontWeight: FontWeight.bold)))),
              _buildQtyAction(Icons.add, () => _ajustarQuantidade(index, 1)),
              const SizedBox(width: 8),
              IconButton(onPressed: () => _removerDoCarrinho(index), icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQtyAction(IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(color: const Color(0xFFF8F9FC), borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.grey.shade200)),
        child: Icon(icon, size: 14, color: PainelAdminTheme.roxo),
      ),
    );
  }

  Widget _buildValueRow(String label, double value, {bool isDiscount = false}) {
    final style = TextStyle(
      color: isDiscount ? Colors.green : Colors.grey.shade600,
      fontWeight: isDiscount ? FontWeight.bold : FontWeight.normal,
      fontSize: 14,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: style),
          Text(NumberFormat.currency(locale: 'pt_BR', symbol: r'R$').format(value), style: style.copyWith(color: isDiscount ? Colors.green : Colors.black87)),
        ],
      ),
    );
  }

  Widget _buildSecondaryBtn(String label, IconData icon, VoidCallback onTap, {bool isDanger = false}) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 16),
      label: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
      style: OutlinedButton.styleFrom(
        foregroundColor: isDanger ? Colors.red : Colors.black87,
        side: BorderSide(color: isDanger ? Colors.red.withValues(alpha: 0.3) : Colors.grey.shade300),
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Widget _buildShortcut(String key, String label, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(right: 32),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(4)),
            child: Text(key, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 8),
          Icon(icon, size: 16, color: Colors.white54),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildEmptyCart(TextTheme textTheme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.shopping_basket_outlined, size: 64, color: Colors.grey.shade100),
          const SizedBox(height: 16),
          Text('Nenhum item na venda', style: TextStyle(color: Colors.grey.shade400, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.search_off_rounded, size: 64, color: Colors.grey),
          const SizedBox(height: 16),
          Text('Nenhum produto encontrado', style: TextStyle(color: Colors.grey.shade600, fontWeight: FontWeight.bold)),
          Text('Tente mudar os filtros ou a busca.', style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
        ],
      ),
    );
  }
}

// --- MODAIS PROFISSIONAIS DE CAIXA ---

class _ModalAbrirCaixaPasso1 extends StatefulWidget {
  const _ModalAbrirCaixaPasso1();

  @override
  State<_ModalAbrirCaixaPasso1> createState() => _ModalAbrirCaixaPasso1State();
}

class _ModalAbrirCaixaPasso1State extends State<_ModalAbrirCaixaPasso1> {
  final _valorController = TextEditingController();
  final _obsController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Column(
        children: [
          Icon(Icons.lock_open_rounded, size: 48, color: Colors.green.shade700),
          const SizedBox(height: 16),
          const Text('Abertura de Caixa', textAlign: TextAlign.center),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Informe o valor inicial disponível no caixa.',
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 24),
          const Text('Valor inicial:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          const SizedBox(height: 8),
          TextField(
            controller: _valorController,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            decoration: InputDecoration(
              prefixText: r'R$ ',
              hintText: '0,00',
              filled: true,
              fillColor: Colors.grey.shade50,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 16),
          const Text('Observação (opcional):', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          const SizedBox(height: 8),
          TextField(
            controller: _obsController,
            maxLines: 2,
            decoration: InputDecoration(
              hintText: 'Ex: Troco inicial em moedas...',
              filled: true,
              fillColor: Colors.grey.shade50,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar', style: TextStyle(color: Colors.grey)),
        ),
        FilledButton(
          onPressed: () {
            final v = double.tryParse(_valorController.text.replaceAll(',', '.')) ?? 0;
            if (v <= 0 && _valorController.text.isEmpty) return;
            Navigator.pop(context, {
              'valor': v,
              'observacao': _obsController.text.trim(),
            });
          },
          style: FilledButton.styleFrom(
            backgroundColor: PainelAdminTheme.roxo,
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
          ),
          child: const Text('Continuar'),
        ),
      ],
    );
  }
}

class _ModalAbrirCaixaPasso2 extends StatelessWidget {
  final double valor;
  final String observacao;
  final Map<String, dynamic>? dadosLoja;

  const _ModalAbrirCaixaPasso2({
    required this.valor,
    required this.observacao,
    this.dadosLoja,
  });

  @override
  Widget build(BuildContext context) {
    final moeda = NumberFormat.currency(locale: 'pt_BR', symbol: r'R$');
    final dataHora = DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now());

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('Confirmar abertura do caixa', textAlign: TextAlign.center),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          RichText(
            textAlign: TextAlign.center,
            text: TextSpan(
              style: const TextStyle(color: Colors.black87, fontSize: 16, height: 1.5),
              children: [
                const TextSpan(text: 'Você está abrindo o caixa com o valor inicial de '),
                TextSpan(
                  text: moeda.format(valor),
                  style: const TextStyle(fontWeight: FontWeight.bold, color: PainelAdminTheme.roxo),
                ),
                const TextSpan(text: '.\n\nDeseja continuar?'),
              ],
            ),
          ),
          const SizedBox(height: 32),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(12)),
            child: Column(
              children: [
                _rowInfo('Valor informado:', moeda.format(valor)),
                _rowInfo('Data/Hora:', dataHora),
                _rowInfo('Operador:', dadosLoja?['nome_fantasia'] ?? dadosLoja?['nome'] ?? 'Operador'),
              ],
            ),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Voltar')),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          style: FilledButton.styleFrom(backgroundColor: Colors.green.shade700),
          child: const Text('Confirmar abertura'),
        ),
      ],
    );
  }

  Widget _rowInfo(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        ],
      ),
    );
  }
}

class _ModalFecharCaixa extends StatefulWidget {
  final String idSessao;
  final Map<String, dynamic> sessao;
  final Map<String, double> resumo;

  const _ModalFecharCaixa({
    required this.idSessao,
    required this.sessao,
    required this.resumo,
  });

  @override
  State<_ModalFecharCaixa> createState() => _ModalFecharCaixaState();
}

class _ModalFecharCaixaState extends State<_ModalFecharCaixa> {
  final _encontradoController = TextEditingController();
  double _encontrado = 0;

  @override
  Widget build(BuildContext context) {
    final moeda = NumberFormat.currency(locale: 'pt_BR', symbol: r'R$');
    final valorInicial = (widget.sessao['valor_inicial'] ?? 0.0) as double;
    final vendasDinheiro = widget.resumo['dinheiro'] ?? 0.0;
    final totalEsperado = valorInicial + vendasDinheiro;
    final diferenca = _encontrado - totalEsperado;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 800),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.lock_clock_rounded, size: 32, color: Colors.orange.shade800),
                    const SizedBox(width: 16),
                    const Text('Fechamento de Caixa', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                    const Spacer(),
                    IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
                  ],
                ),
                const Divider(height: 48),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Esquerda: Dados e Resumo
                    Expanded(
                      flex: 5,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _secaoTitulo('DADOS DA ABERTURA'),
                          _infoItem('Valor inicial', moeda.format(valorInicial)),
                          _infoItem('Aberto em', _formatarData(widget.sessao['data_abertura'])),
                          _infoItem('Operador', widget.sessao['operador_nome'] ?? 'N/A'),
                          
                          const SizedBox(height: 32),
                          _secaoTitulo('RESUMO DE VENDAS'),
                          _infoItem('Dinheiro', moeda.format(vendasDinheiro)),
                          _infoItem('PIX', moeda.format(widget.resumo['pix'] ?? 0)),
                          _infoItem('Cartão Crédito', moeda.format(widget.resumo['credito'] ?? 0)),
                          _infoItem('Cartão Débito', moeda.format(widget.resumo['debito'] ?? 0)),
                          
                          const SizedBox(height: 32),
                          _secaoTitulo('TOTAIS'),
                          _infoItem('Valor Inicial', moeda.format(valorInicial)),
                          _infoItem('Total em Dinheiro', moeda.format(vendasDinheiro)),
                          const Divider(),
                          _infoItem('Total esperado no caixa', moeda.format(totalEsperado), highlight: true),
                        ],
                      ),
                    ),
                    const SizedBox(width: 48),
                    // Direita: Conferência
                    Expanded(
                      flex: 4,
                      child: Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.grey.shade100)),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _secaoTitulo('CONFERÊNCIA'),
                            const Text('Valor encontrado no caixa:', style: TextStyle(fontWeight: FontWeight.bold)),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _encontradoController,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: PainelAdminTheme.roxo),
                              decoration: InputDecoration(
                                prefixText: r'R$ ',
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                filled: true,
                                fillColor: Colors.white,
                              ),
                              onChanged: (v) => setState(() => _encontrado = double.tryParse(v.replaceAll(',', '.')) ?? 0),
                            ),
                            const SizedBox(height: 32),
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: diferenca == 0 ? Colors.green.shade50 : (diferenca < 0 ? Colors.red.shade50 : Colors.blue.shade50),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(diferenca >= 0 ? 'Sobra:' : 'Diferença:', style: const TextStyle(fontWeight: FontWeight.bold)),
                                  Text(
                                    moeda.format(diferenca),
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: diferenca == 0 ? Colors.green.shade700 : (diferenca < 0 ? Colors.red.shade700 : Colors.blue.shade700),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 48),
                            SizedBox(
                              width: double.infinity,
                              height: 56,
                              child: FilledButton(
                                onPressed: () => _confirmarFechamento(context),
                                style: FilledButton.styleFrom(backgroundColor: Colors.orange.shade900, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                                child: const Text('Fechar Caixa', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                              ),
                            ),
                            const SizedBox(height: 16),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: () {}, // TODO: Implementar impressão de fechamento
                                icon: const Icon(Icons.print_rounded),
                                label: const Text('Imprimir fechamento'),
                                style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _confirmarFechamento(BuildContext context) async {
    final sim = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar fechamento'),
        content: const Text('Deseja realmente fechar o caixa?\n\nApós o fechamento não será possível realizar novas vendas até uma nova abertura.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Fechar Caixa'), style: FilledButton.styleFrom(backgroundColor: Colors.red)),
        ],
      ),
    );

    if (sim == true) {
      if (context.mounted) {
        Navigator.pop(context, {
          'valor_encontrado': _encontrado,
          'diferenca': _encontrado - ((widget.sessao['valor_inicial'] ?? 0) + (widget.resumo['dinheiro'] ?? 0)),
        });
      }
    }
  }

  Widget _secaoTitulo(String t) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Text(t, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.grey, letterSpacing: 1.1)),
    );
  }

  Widget _infoItem(String label, String value, {bool highlight = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: highlight ? 15 : 14, fontWeight: highlight ? FontWeight.bold : FontWeight.normal)),
          Text(value, style: TextStyle(fontSize: highlight ? 18 : 14, fontWeight: FontWeight.bold, color: highlight ? PainelAdminTheme.roxo : Colors.black87)),
        ],
      ),
    );
  }

  String _formatarData(dynamic d) {
    if (d is Timestamp) return DateFormat('dd/MM/yyyy HH:mm').format(d.toDate());
    return 'N/A';
  }
}

class _PaymentMethodData {
  final String label;
  final IconData icon;
  final String subtitle;
  final Color primaryColor;
  final Color bgIconColor;

  const _PaymentMethodData({
    required this.label,
    required this.icon,
    required this.subtitle,
    required this.primaryColor,
    required this.bgIconColor,
  });
}

// ═══════════════════════════════════════════════════════════════════════════════
// FLUXO PIX — Modelos, Modal PIX e Modal de Confirmação
// ═══════════════════════════════════════════════════════════════════════════════

class _DadosCobrancaPix {
  final String cobrancaId;
  final String paymentId;
  final String qrCodeBase64;
  final String pixCopiaECola;
  final DateTime expiresAt;
  final String status;
  final String vendaId;
  final double valor;

  const _DadosCobrancaPix({
    required this.cobrancaId,
    required this.paymentId,
    required this.qrCodeBase64,
    required this.pixCopiaECola,
    required this.expiresAt,
    required this.status,
    required this.vendaId,
    required this.valor,
  });
}

class _ResultadoPagamentoPix {
  final bool pago;
  final double valorRecebido;
  final String codigoVenda;
  final DateTime dataHora;

  const _ResultadoPagamentoPix({
    required this.pago,
    required this.valorRecebido,
    required this.codigoVenda,
    required this.dataHora,
  });
}

/// Widget que exibe o QR Code PIX gerado EXCLUSIVAMENTE a partir do pixCopiaECola.
/// Nunca usa chavePix, CPF, telefone ou montagem manual de BR Code.
class _PixQrCodeWidget extends StatelessWidget {
  final String pixCopiaECola;
  final double size;
  final bool exibir;

  const _PixQrCodeWidget({
    required this.pixCopiaECola,
    required this.size,
    required this.exibir,
  });

  @override
  Widget build(BuildContext context) {
    if (!exibir) return const SizedBox.shrink();
    final qrSize = size - 24;
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: pixCopiaECola.isNotEmpty
          ? ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: QrImageView(
                data: pixCopiaECola,
                version: QrVersions.auto,
                size: qrSize,
                backgroundColor: Colors.white,
                eyeStyle: const QrEyeStyle(
                  eyeShape: QrEyeShape.square,
                  color: Colors.black,
                ),
                dataModuleStyle: const QrDataModuleStyle(
                  dataModuleShape: QrDataModuleShape.square,
                  color: Colors.black,
                ),
                key: const ValueKey('pix_qrcode_from_copia_cola'),
              ),
            )
          : const Center(child: Icon(Icons.qr_code_rounded, size: 80, color: Colors.grey)),
    );
  }
}

/// Modal premium de pagamento PIX
class _ModalPagamentoPix extends StatefulWidget {
  final _DadosCobrancaPix dadosCobranca;
  final String? clienteNome;
  final String operadorNome;
  final String uidLoja;

  const _ModalPagamentoPix({
    required this.dadosCobranca,
    this.clienteNome,
    required this.operadorNome,
    required this.uidLoja,
  });

  @override
  State<_ModalPagamentoPix> createState() => _ModalPagamentoPixState();
}

class _ModalPagamentoPixState extends State<_ModalPagamentoPix> {
  late Timer _countdownTimer;
  late Duration _tempoRestante;

  // ─── Armazenamento estatico (muda apenas via initState) ─────
  late final String _pixCopiaECola;
  late final double _valor;
  late final DateTime _expiresAt;
  late final String _cobrancaId;

  // ─── Firestore listener para status em tempo real ─────────
  StreamSubscription<DocumentSnapshot>? _cobrancaSubscription;
  Timer? _pollBackendTimer;

  // ─── Estados dinamicos (setState minimo) ───────────────────
  bool _copiado = false;
  bool _verificando = false;
  bool _finalizado = false;
  String _statusAtual = 'aguardando_pagamento';
  String? _mensagemStatus;

  // ─── Timer display usa ValueNotifier para rebuild isolado ──
  late final ValueNotifier<String> _timerDisplay;

  @override
  void initState() {
    super.initState();

    // Congela dados da cobranca — nunca mais muda
    _pixCopiaECola = widget.dadosCobranca.pixCopiaECola;
    _valor = widget.dadosCobranca.valor;
    _expiresAt = widget.dadosCobranca.expiresAt;
    _cobrancaId = widget.dadosCobranca.cobrancaId;
    _statusAtual = widget.dadosCobranca.status;
    _tempoRestante = _expiresAt.difference(DateTime.now());

    print('[PDV-PIX] Modal aberto: cobranca=$_cobrancaId, status=$_statusAtual');
    print('[PDV-PIX] pixCopiaECola exibido: $_pixCopiaECola');
    print('[PDV-PIX] startsWith 000201: ${_pixCopiaECola.startsWith('000201')}');
    print('[PDV-PIX] endsWith 6304+CRC: ${RegExp(r'6304[0-9A-Fa-f]{4}$').hasMatch(_pixCopiaECola)}');

    // Inicializa display do timer
    _timerDisplay = ValueNotifier<String>(_formatarTempo(_tempoRestante));

    // ─── FIRESTORE LISTENER: escuta mudancas de status em tempo real ───
    _iniciarFirestoreListener();

    // ─── POLLING BACKEND: confirma pagamento via MP a cada 3s ───
    _iniciarPollingBackend();

    // ─── Countdown timer — so atualiza _timerDisplay, nunca reconstroi QR Code ───
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final restante = _expiresAt.difference(DateTime.now());
      if (restante.isNegative) {
        // Tempo esgotou — se ainda esta aguardando, marca como expirado
        if (!_finalizado && (_statusAtual == 'aguardando_pagamento' || _statusAtual == 'aguardando')) {
          _countdownTimer.cancel();
          _finalizado = true;
          _timerDisplay.value = '00:00';
          setState(() {
            _tempoRestante = Duration.zero;
            _statusAtual = 'expirado';
          });
          print('[PDV-PIX] Cobranca $_cobrancaId expirada pelo timer local (5min sem pagamento)');
        }
      } else {
        _tempoRestante = restante;
        _timerDisplay.value = _formatarTempo(restante);
      }
    });
  }

  /// Consulta o backend (MP + Firestore) automaticamente enquanto aguarda PIX.
  void _iniciarPollingBackend() {
    Future<void>.delayed(const Duration(seconds: 2), () {
      if (!mounted || _finalizado) return;
      _consultarStatusBackend(mostrarSnackSePendente: false);
    });

    _pollBackendTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!mounted || _finalizado) return;
      if (_statusAtual != 'aguardando_pagamento' && _statusAtual != 'aguardando') return;
      _consultarStatusBackend(mostrarSnackSePendente: false);
    });
  }

  void _aplicarStatusPago(Map<String, dynamic> result) {
    final pagamento = result['pagamento'] as Map<String, dynamic>?;
    final valorRecebido = (result['valorRecebido'] as num?)?.toDouble() ?? _valor;
    final dataHora = pagamento?['dataHora'] != null
        ? DateTime.tryParse(pagamento!['dataHora'] as String) ?? DateTime.now()
        : DateTime.now();
    final codigoVenda = pagamento?['codigoVenda'] as String? ?? '';

    _finalizado = true;
    _countdownTimer.cancel();
    _pollBackendTimer?.cancel();
    _cobrancaSubscription?.cancel();

    Navigator.of(context).pop(_ResultadoPagamentoPix(
      pago: true,
      valorRecebido: valorRecebido,
      codigoVenda: codigoVenda,
      dataHora: dataHora,
    ));
  }

  Future<void> _consultarStatusBackend({required bool mostrarSnackSePendente}) async {
    if (_verificando || _finalizado) return;
    _verificando = true;

    try {
      final result = await callFirebaseFunctionSafe(
        'gestaoComercialConsultarStatusPix',
        region: 'southamerica-east1',
        parameters: {'cobrancaId': _cobrancaId},
      );
      if (!mounted || _finalizado) return;

      final status = result['status'] as String? ?? 'aguardando_pagamento';
      print('[PDV-PIX] Poll backend status: $status');

      if (status == 'pago') {
        _aplicarStatusPago(result);
        return;
      }

      if (status == 'expirado' || status == 'cancelado' || status == 'recusado' || status == 'estornado') {
        _finalizado = true;
        _countdownTimer.cancel();
        _pollBackendTimer?.cancel();
        _cobrancaSubscription?.cancel();
        setState(() {
          _statusAtual = status;
          _mensagemStatus = null;
        });
        return;
      }

      if (status != _statusAtual) {
        setState(() {
          _statusAtual = status;
          _mensagemStatus = null;
        });
      }

      if (mostrarSnackSePendente &&
          (status == 'aguardando_pagamento' || status == 'aguardando')) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Pagamento ainda nao identificado. Aguarde alguns instantes.'),
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      print('[PDV-PIX] Erro poll backend: $e');
      if (mounted && mostrarSnackSePendente) {
        setState(() => _mensagemStatus = 'Erro ao verificar pagamento: $e');
      }
    } finally {
      if (mounted) _verificando = false;
    }
  }

  /// Inicia listener do Firestore para detectar mudancas de status
  /// vindas do webhook ou da funcao checkPdvPixPaymentStatus.
  void _iniciarFirestoreListener() {
    _cobrancaSubscription = FirebaseFirestore.instance
        .collection('gestao_comercial_cobrancas')
        .doc(_cobrancaId)
        .snapshots()
        .listen((snapshot) {
      if (!mounted || _finalizado) return;
      if (!snapshot.exists) return;

      final data = snapshot.data();
      if (data == null) return;

      final novoStatus = data['status'] as String? ?? 'aguardando_pagamento';
      final statusAntigo = _statusAtual;

      if (novoStatus != statusAntigo) {
        print('[PDV-PIX] Status alterado via Firestore: $statusAntigo -> $novoStatus');

        if (novoStatus == 'pago') {
          // Pagamento confirmado pelo webhook/backend — fechar modal.
          _aplicarStatusPago({
            'valorRecebido': (data['valorRecebido'] as num?)?.toDouble() ?? _valor,
            'pagamento': {
              'codigoVenda': '',
              'dataHora': DateTime.now().toIso8601String(),
            },
          });
          return;
        }

        if (novoStatus == 'expirado' || novoStatus == 'cancelado' || novoStatus == 'recusado' || novoStatus == 'estornado') {
          _finalizado = true;
          _countdownTimer.cancel();
          _pollBackendTimer?.cancel();
          _cobrancaSubscription?.cancel();
        }

        setState(() {
          _statusAtual = novoStatus;
          _mensagemStatus = null;
        });
      }
    }, onError: (error) {
      print('[PDV-PIX] Erro no Firestore listener: $error');
      setState(() {
        _mensagemStatus = 'Erro ao monitorar pagamento: $error';
      });
    });
  }

  @override
  void dispose() {
    _countdownTimer.cancel();
    _pollBackendTimer?.cancel();
    _cobrancaSubscription?.cancel();
    _timerDisplay.dispose();
    super.dispose();
  }

  /// Botao "Verificar pagamento" — NUNCA cancela a cobranca.
  /// Apenas consulta o backend e atualiza o status se o pagamento foi confirmado.
  Future<void> _verificarStatus() async {
    if (_verificando) return;
    setState(() {
      _mensagemStatus = null;
    });

    print('[PDV-PIX] Verificando status da cobranca $_cobrancaId (manual)...');
    await _consultarStatusBackend(mostrarSnackSePendente: true);
  }

  /// Cancela cobranca PIX — so com confirmacao do operador.
  Future<void> _cancelarCobranca() async {
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Cancelar cobranca PIX?'),
        content: const Text('O QR Code nao sera mais valido e o cliente nao podera pagar.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Nao')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sim, cancelar'),
          ),
        ],
      ),
    );

    if (confirmado != true) return;
    if (!mounted) return;

    print('[PDV-PIX] Cancelando cobranca $_cobrancaId manualmente...');

    try {
      await FirebaseFirestore.instance
          .collection('gestao_comercial_cobrancas')
          .doc(_cobrancaId)
          .update({'status': 'cancelado', 'cancelledAt': FieldValue.serverTimestamp(), 'updatedAt': FieldValue.serverTimestamp()});
    } catch (_) {}

    _finalizado = true;
    _countdownTimer.cancel();
    _cobrancaSubscription?.cancel();
    if (mounted) {
      Navigator.of(context).pop(_ResultadoPagamentoPix(
        pago: false,
        valorRecebido: 0,
        codigoVenda: '',
        dataHora: DateTime.now(),
      ));
    }
  }

  void _copiarCodigoPix() {
    Clipboard.setData(ClipboardData(text: _pixCopiaECola));
    setState(() => _copiado = true);
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) setState(() => _copiado = false);
    });
  }

  String _formatarTempo(Duration d) {
    if (d.isNegative) return '00:00';
    final minutos = d.inMinutes.toString().padLeft(2, '0');
    final segundos = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutos:$segundos';
  }

  Color _corStatus(String status) {
    switch (status) {
      case 'aguardando_pagamento':
      case 'aguardando':
        return PainelAdminTheme.roxo;
      case 'pago':
        return const Color(0xFF22C55E);
      case 'rejected':
      case 'cancelled':
      case 'cancelado':
      case 'recusado':
      case 'refunded':
      case 'estornado':
        return Colors.red;
      case 'expirado':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  String _rotuloStatus(String status) {
    switch (status) {
      case 'aguardando_pagamento':
      case 'aguardando':
        return 'Aguardando pagamento';
      case 'pago':
        return 'Pagamento aprovado';
      case 'rejected':
      case 'recusado':
        return 'Pagamento recusado';
      case 'cancelled':
      case 'cancelado':
        return 'Cancelado';
      case 'refunded':
      case 'estornado':
        return 'Estornado';
      case 'expirado':
        return 'PIX expirado';
      default:
        return status;
    }
  }

  @override
  Widget build(BuildContext context) {
    final f = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    final size = MediaQuery.of(context).size;
    final isMobile = size.width < 600;
    final qrSize = isMobile ? 200.0 : 260.0;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      elevation: 16,
      shadowColor: Colors.black38,
      insetPadding: EdgeInsets.symmetric(
        horizontal: isMobile ? 16 : 40,
        vertical: 24,
      ),
      child: Container(
        width: isMobile ? null : 480,
        padding: EdgeInsets.all(isMobile ? 20 : 28),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ─── HEADER ─────────────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF32BCAD).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.pix_rounded, color: Color(0xFF32BCAD), size: 28),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Pagamento via PIX',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF1A1A2E),
                      ),
                    ),
                    Text(
                      _statusAtual == 'pago'
                          ? 'Pagamento confirmado!'
                          : 'Aguardando o cliente realizar o pagamento.',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        color: const Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            SizedBox(height: isMobile ? 16 : 20),

            // ─── CARD DE VALOR E STATUS ─────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    PainelAdminTheme.roxo,
                    PainelAdminTheme.roxo.withOpacity(0.85),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: PainelAdminTheme.roxo.withOpacity(0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Text(
                    'Total a pagar',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      color: Colors.white70,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    f.format(_valor),
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: (_statusAtual == 'aguardando_pagamento' || _statusAtual == 'aguardando')
                                ? Colors.yellow
                                : _corStatus(_statusAtual),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _rotuloStatus(_statusAtual),
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: isMobile ? 16 : 20),

            // ─── QR CODE FIXO (widget isolado, nunca reconstroi) ────
            // QR Code permanece visivel em todos os estados exceto 'pago'
            if (_statusAtual != 'pago')
              _PixQrCodeWidget(
                pixCopiaECola: _pixCopiaECola,
                size: qrSize,
                exibir: true,
              ),

            if (_statusAtual == 'aguardando_pagamento' || _statusAtual == 'aguardando') ...[
              const SizedBox(height: 12),

              // ─── CODIGO COPIA E COLA ──
              if (_pixCopiaECola.isNotEmpty) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Text(
                    _pixCopiaECola,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      color: const Color(0xFF1A1A2E),
                      letterSpacing: 0.5,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  height: 40,
                  child: OutlinedButton.icon(
                    onPressed: _copiarCodigoPix,
                    icon: Icon(_copiado ? Icons.check_rounded : Icons.copy_rounded, size: 18),
                    label: Text(_copiado ? 'Copiado!' : 'Copiar codigo PIX'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: PainelAdminTheme.roxo,
                      side: BorderSide(color: PainelAdminTheme.roxo.withOpacity(0.3)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Escaneie o QR Code ou copie o codigo para pagar.',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    color: const Color(0xFF94A3B8),
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ],

            if (_statusAtual == 'pago') ...[
              Container(
                width: qrSize,
                height: qrSize,
                decoration: BoxDecoration(
                  color: const Color(0xFF22C55E).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Center(
                  child: Icon(Icons.check_circle_rounded, color: Color(0xFF22C55E), size: 80),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Pagamento confirmado!',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF22C55E),
                ),
              ),
            ],

            SizedBox(height: isMobile ? 12 : 16),

            // ─── TEMPO RESTANTE (ValueNotifier — rebuild isolado) ──
            if (_statusAtual == 'aguardando_pagamento' || _statusAtual == 'aguardando') ...[
              ValueListenableBuilder<String>(
                valueListenable: _timerDisplay,
                builder: (context, display, _) {
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.access_time_rounded, size: 16, color: Color(0xFF64748B)),
                      const SizedBox(width: 6),
                      Text(
                        'Expira em $display',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          color: _tempoRestante.inMinutes < 1 ? Colors.red : const Color(0xFF64748B),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 8),
            ],

            if (_statusAtual == 'expirado') ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'PIX expirado. O tempo para pagamento terminou.',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    color: Colors.orange.shade800,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 12),
            ],

            if (_statusAtual == 'cancelado') ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Cobranca cancelada.',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    color: Colors.red.shade700,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 12),
            ],

            // ─── MENSAGEM DE ERRO ───────────────────────────
            if (_mensagemStatus != null) ...[
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _mensagemStatus!,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    color: Colors.red.shade700,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 8),
            ],

            // ─── RODAPE ──────────────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (_statusAtual == 'aguardando_pagamento' || _statusAtual == 'aguardando')
                  SizedBox(
                    height: 40,
                    child: TextButton(
                      onPressed: _verificando ? null : _verificarStatus,
                      child: _verificando
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(
                              'Verificar pagamento',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 13,
                                color: PainelAdminTheme.roxo,
                              ),
                            ),
                    ),
                  )
                else
                  const Spacer(),
                SizedBox(
                  height: 40,
                  child: (_statusAtual == 'aguardando_pagamento' || _statusAtual == 'aguardando')
                      ? OutlinedButton(
                          onPressed: _cancelarCobranca,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red.shade400,
                            side: BorderSide(color: Colors.red.shade200),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          child: Text(
                            'Cancelar cobranca',
                            style: GoogleFonts.plusJakartaSans(fontSize: 13),
                          ),
                        )
                      : FilledButton(
                          onPressed: () {
                            Navigator.of(context).pop(_ResultadoPagamentoPix(
                              pago: false,
                              valorRecebido: 0,
                              codigoVenda: '',
                              dataHora: DateTime.now(),
                            ));
                          },
                          style: FilledButton.styleFrom(
                            backgroundColor: PainelAdminTheme.roxo,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          child: Text(
                            _statusAtual == 'pago' ? 'Continuar' : 'Fechar',
                            style: GoogleFonts.plusJakartaSans(fontSize: 13),
                          ),
                        ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Modal premium de confirmação de pagamento PIX
class _ModalConfirmacaoPix extends StatelessWidget {
  final double valorRecebido;
  final String clienteNome;
  final String codigoVenda;
  final String formaPagamento;
  final DateTime dataHora;
  final String operadorNome;
  final String gateway;
  final String vendaId;
  final String uidLoja;
  final Map<String, dynamic>? dadosLoja;

  const _ModalConfirmacaoPix({
    required this.valorRecebido,
    required this.clienteNome,
    required this.codigoVenda,
    required this.formaPagamento,
    required this.dataHora,
    required this.operadorNome,
    required this.gateway,
    required this.vendaId,
    required this.uidLoja,
    this.dadosLoja,
  });

  Future<void> _imprimirComprovante(BuildContext context) async {
    try {
      final db = FirebaseFirestore.instance;
      final vendaSnap = await db.collection('gestao_comercial_vendas').doc(vendaId).get();
      if (!vendaSnap.exists) return;
      final vendaData = vendaSnap.data() ?? {};

      // Montar dados compatíveis com PedidoReciboPdf
      final pedidoDados = <String, dynamic>{
        'codigo_pedido': codigoVenda,
        'cliente_nome': clienteNome,
        'forma_pagamento': 'PIX - $gateway',
        'total': valorRecebido,
        'valor_recebido': valorRecebido,
        'itens': vendaData['itens'] as List<dynamic>? ?? [],
        'data_pedido': Timestamp.fromDate(dataHora),
        'loja_nome': dadosLoja?['nome_fantasia'] ?? dadosLoja?['nome'] ?? '',
        'loja_endereco': dadosLoja?['endereco'] ?? '',
        'loja_telefone': dadosLoja?['telefone'] ?? '',
      };

      await PedidoReciboPdf.imprimir(
        pedidoId: vendaId,
        codigoPedido: codigoVenda,
        pedido: pedidoDados,
        dadosLoja: dadosLoja,
        nomeClienteFallback: clienteNome,
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Erro ao imprimir: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final f = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    final df = DateFormat('dd/MM/yyyy HH:mm', 'pt_BR');
    final size = MediaQuery.of(context).size;
    final isMobile = size.width < 600;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      elevation: 16,
      shadowColor: Colors.black38,
      insetPadding: EdgeInsets.symmetric(
        horizontal: isMobile ? 16 : 40,
        vertical: 24,
      ),
      child: Container(
        width: isMobile ? null : 420,
        padding: EdgeInsets.all(isMobile ? 20 : 28),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ─── ÍCONE DE SUCESSO ─────────────────────────
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF22C55E).withOpacity(0.1),
              ),
              child: const Icon(Icons.check_circle_rounded, color: Color(0xFF22C55E), size: 48),
            ),
            const SizedBox(height: 16),

            // ─── TÍTULO ──────────────────────────────────
            Text(
              'Pagamento recebido',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF1A1A2E),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'O PIX foi confirmado com sucesso.',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 14,
                color: const Color(0xFF64748B),
              ),
            ),
            const SizedBox(height: 20),

            // ─── CARD DE RESUMO ──────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                children: [
                  _linhaResumo('Valor recebido', f.format(valorRecebido),
                      cor: const Color(0xFF22C55E), bold: true, fontSize: 18),
                  const Divider(height: 16),
                  _linhaResumo('Cliente', clienteNome),
                  if (codigoVenda.isNotEmpty)
                    _linhaResumo('Código da venda', codigoVenda),
                  _linhaResumo('Forma de pagamento', 'PIX'),
                  _linhaResumo('Data e hora', df.format(dataHora)),
                  _linhaResumo('Operador', operadorNome),
                  _linhaResumo('Gateway', gateway),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // ─── BOTÕES ──────────────────────────────────
            SizedBox(
              width: double.infinity,
              height: 44,
              child: FilledButton.icon(
                onPressed: () => _imprimirComprovante(context),
                icon: const Icon(Icons.print_rounded, size: 18),
                label: Text(
                  'Imprimir comprovante',
                  style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: PainelAdminTheme.roxo,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: OutlinedButton.icon(
                onPressed: () => Navigator.of(context).pop('nova_venda'),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: Text(
                  'Nova venda',
                  style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: PainelAdminTheme.roxo,
                  side: BorderSide(color: PainelAdminTheme.roxo.withOpacity(0.3)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: TextButton(
                onPressed: () => Navigator.of(context).pop('ver_venda'),
                child: Text(
                  'Ver venda',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    color: const Color(0xFF64748B),
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _linhaResumo(String label, String valor,
      {Color? cor, bool bold = false, double fontSize = 13}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              color: const Color(0xFF64748B),
            ),
          ),
          Text(
            valor,
            style: GoogleFonts.plusJakartaSans(
              fontSize: fontSize,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
              color: cor ?? const Color(0xFF1A1A2E),
            ),
          ),
        ],
      ),
    );
  }
}

class _ModalSelecionarPagamento extends StatelessWidget {
  final double totalVenda;
  final Map<String, dynamic>? clienteCredito;

  const _ModalSelecionarPagamento({
    required this.totalVenda,
    this.clienteCredito,
  });

  bool get _podeCreditoCliente {
    final c = clienteCredito;
    if (c == null) return false;
    if (c['credito_habilitado'] != true) return false;
    final disp = (c['credito_disponivel'] as num?)?.toDouble() ??
        (((c['limite_credito'] as num?)?.toDouble() ?? 0) -
            ((c['credito_utilizado'] as num?)?.toDouble() ?? 0));
    return disp >= totalVenda - 0.009;
  }

  @override
  Widget build(BuildContext context) {
    final f = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

    final metodos = [
      const _PaymentMethodData(
        label: 'Dinheiro',
        icon: Icons.money_rounded,
        subtitle: 'Pagamento físico em cédulas ou moedas',
        primaryColor: Color(0xFF10B981),
        bgIconColor: Color(0xFFECFDF5),
      ),
      const _PaymentMethodData(
        label: 'PIX',
        icon: Icons.pix_rounded,
        subtitle: 'Transferência instantânea via QR Code/Chave',
        primaryColor: Color(0xFF32BCAD),
        bgIconColor: Color(0xFFEAF9F8),
      ),
      const _PaymentMethodData(
        label: 'Cartão de Crédito',
        icon: Icons.credit_card_rounded,
        subtitle: 'Visa, Mastercard, Elo, Hipercard, etc.',
        primaryColor: Color(0xFF3F51B5),
        bgIconColor: Color(0xFFE8EAF6),
      ),
      const _PaymentMethodData(
        label: 'Cartão de Débito',
        icon: Icons.credit_card_outlined,
        subtitle: 'Débito em conta à vista',
        primaryColor: Color(0xFF2196F3),
        bgIconColor: Color(0xFFE3F2FD),
      ),
      const _PaymentMethodData(
        label: 'Carteira DiPertin',
        icon: Icons.account_balance_wallet_rounded,
        subtitle: 'Saldo digital interno da conta cliente',
        primaryColor: Color(0xFF6A1B9A),
        bgIconColor: Color(0xFFF3E8FF),
      ),
      const _PaymentMethodData(
        label: 'Vale Alimentação/Refeição',
        icon: Icons.confirmation_number_rounded,
        subtitle: 'Alelo, Sodexo, VR, Ticket, etc.',
        primaryColor: Color(0xFFE91E63),
        bgIconColor: Color(0xFFFCE4EC),
      ),
      const _PaymentMethodData(
        label: 'Transferência Bancária',
        icon: Icons.sync_alt_rounded,
        subtitle: 'TED, DOC ou depósito identificado',
        primaryColor: Color(0xFFE65100),
        bgIconColor: Color(0xFFFFF3E0),
      ),
    ];

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      elevation: 12,
      shadowColor: Colors.black26,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 480),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Cabeçalho do Modal
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: PainelAdminTheme.roxo.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.payment_rounded, color: PainelAdminTheme.roxo, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Forma de Pagamento',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF1E1B4B),
                        ),
                      ),
                      Text(
                        'Selecione o método para finalizar a venda',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          color: PainelAdminTheme.textoSecundario,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded, color: PainelAdminTheme.textoSecundario),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Banner do Valor Total
            Container(
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF6A1B9A), Color(0xFF8E24AA)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF6A1B9A).withOpacity(0.25),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'TOTAL A PAGAR',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: Colors.white.withOpacity(0.8),
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        f.format(totalVenda),
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Frente de Caixa',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            if (_podeCreditoCliente) ...[
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF3E0),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: PainelAdminTheme.laranja.withOpacity(0.4)),
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => Navigator.pop(context, 'Crédito do cliente'),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: PainelAdminTheme.laranja.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.account_balance_wallet_rounded,
                                color: PainelAdminTheme.laranja),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Crédito do cliente',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 15,
                                  ),
                                ),
                                Text(
                                  '${clienteCredito!['nome']} · Disp. ${f.format((clienteCredito!['credito_disponivel'] as num?)?.toDouble() ?? 0)}',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 12,
                                    color: PainelAdminTheme.textoSecundario,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right_rounded),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],

            // Lista de Métodos de Pagamento
            Flexible(
              child: Container(
                constraints: const BoxConstraints(maxHeight: 380),
                child: ListView.builder(
                  shrinkWrap: true,
                  physics: const BouncingScrollPhysics(),
                  itemCount: metodos.length,
                  itemBuilder: (context, index) {
                    final m = metodos[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFFE8E4F0)),
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () => Navigator.pop(context, m.label),
                            hoverColor: PainelAdminTheme.roxo.withOpacity(0.04),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                              child: Row(
                                children: [
                                  // Container do Ícone
                                  Container(
                                    width: 44,
                                    height: 44,
                                    decoration: BoxDecoration(
                                      color: m.bgIconColor,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Icon(m.icon, color: m.primaryColor, size: 22),
                                  ),
                                  const SizedBox(width: 14),

                                  // Textos
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          m.label,
                                          style: GoogleFonts.plusJakartaSans(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w700,
                                            color: const Color(0xFF1E1B4B),
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          m.subtitle,
                                          style: GoogleFonts.plusJakartaSans(
                                            fontSize: 11,
                                            color: PainelAdminTheme.textoSecundario,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),

                                  // Chevron Direito Sutil
                                  const Icon(
                                    Icons.chevron_right_rounded,
                                    color: Color(0xFFC7D2FE),
                                    size: 20,
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
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResultadoDinheiro {
  final double valorRecebido;
  final double troco;

  _ResultadoDinheiro({required this.valorRecebido, required this.troco});
}

class _ModalTrocoDinheiro extends StatefulWidget {
  final double totalVenda;

  const _ModalTrocoDinheiro({required this.totalVenda});

  @override
  State<_ModalTrocoDinheiro> createState() => _ModalTrocoDinheiroState();
}

class _ModalTrocoDinheiroState extends State<_ModalTrocoDinheiro> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  double _recebido = 0.0;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final text = _controller.text.replaceAll(',', '.');
      setState(() {
        _recebido = double.tryParse(text) ?? 0.0;
      });
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _finalizar() {
    if (_recebido >= widget.totalVenda) {
      Navigator.pop(
        context,
        _ResultadoDinheiro(
          valorRecebido: _recebido,
          troco: _recebido - widget.totalVenda,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    final troco = _recebido - widget.totalVenda;
    final podeFinalizar = _recebido >= widget.totalVenda;

    const corEsmeralda = Color(0xFF10B981);
    const corEsmeraldaLight = Color(0xFFECFDF5);
    const corEsmeraldaTexto = Color(0xFF047857);
    const corEsmeraldaEscuro = Color(0xFF065F46);

    // Calcular notas rápidas sugeridas
    final sugestoes = <double>[];
    sugestoes.add(widget.totalVenda); // Valor exato

    // Sugerir próximas cédulas padrão
    for (final cedula in [10.0, 20.0, 50.0, 100.0, 200.0]) {
      if (cedula > widget.totalVenda && sugestoes.length < 4) {
        sugestoes.add(cedula);
      }
    }

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      elevation: 12,
      shadowColor: Colors.black26,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 440),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Cabeçalho
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: corEsmeralda.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.attach_money_rounded, color: corEsmeralda, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Recebimento em Dinheiro',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF1E1B4B),
                        ),
                      ),
                      Text(
                        'Registre o valor pago pelo cliente',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          color: PainelAdminTheme.textoSecundario,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded, color: PainelAdminTheme.textoSecundario),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Card Resumo de Cobrança
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF8F9FC),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE8E4F0)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Valor da Venda:',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF4B5563),
                    ),
                  ),
                  Text(
                    fmt.format(widget.totalVenda),
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF1E1B4B),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Campo de Input do Valor Recebido
            Text(
              'VALOR RECEBIDO',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF4B5563),
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _controller,
              focusNode: _focusNode,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: GoogleFonts.plusJakartaSans(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF1E1B4B),
              ),
              decoration: InputDecoration(
                prefixText: r'R$ ',
                prefixStyle: GoogleFonts.plusJakartaSans(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF6B7280),
                ),
                hintText: '0,00',
                hintStyle: const TextStyle(color: Color(0xFF9CA3AF)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: Color(0xFFE8E4F0), width: 1.5),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: Color(0xFFE8E4F0), width: 1.5),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: corEsmeralda, width: 2),
                ),
              ),
              onSubmitted: (_) => _finalizar(),
            ),
            const SizedBox(height: 16),

            // Atalhos de Notas Rápidas
            Text(
              'ATALHOS DE VALORES',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF6B7280),
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: sugestoes.map((valor) {
                final ehExato = valor == widget.totalVenda;
                return InkWell(
                  onTap: () {
                    _controller.text = valor.toStringAsFixed(2).replaceAll('.', ',');
                    _controller.selection = TextSelection.fromPosition(
                      TextPosition(offset: _controller.text.length),
                    );
                  },
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: ehExato ? corEsmeraldaLight : const Color(0xFFF3F4F6),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: ehExato ? corEsmeralda.withOpacity(0.3) : const Color(0xFFE5E7EB),
                      ),
                    ),
                    child: Text(
                      ehExato ? 'Valor Exato' : fmt.format(valor),
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: ehExato ? corEsmeraldaTexto : const Color(0xFF374151),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 24),

            // Card do Troco Dinâmico
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: !podeFinalizar
                    ? const Color(0xFFFEF2F2)
                    : (troco > 0 ? corEsmeraldaLight : const Color(0xFFECFDF5)),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: !podeFinalizar
                      ? const Color(0xFFFCA5A5)
                      : (troco > 0 ? corEsmeralda.withOpacity(0.3) : const Color(0xFFA7F3D0)),
                ),
              ),
              child: Column(
                children: [
                  Text(
                    !podeFinalizar ? 'FALTA RECEBER' : (troco > 0 ? 'TROCO DO CLIENTE' : 'SEM TROCO'),
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: !podeFinalizar
                          ? Colors.red.shade700
                          : (troco > 0 ? corEsmeraldaTexto : corEsmeraldaEscuro),
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    !podeFinalizar ? fmt.format(widget.totalVenda - _recebido) : fmt.format(troco),
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                      color: !podeFinalizar
                          ? Colors.red.shade800
                          : (troco > 0 ? corEsmeraldaTexto : corEsmeraldaEscuro),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Botões de Ação
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      side: const BorderSide(color: Color(0xFFE5E7EB)),
                    ),
                    child: Text(
                      'Voltar',
                      style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: podeFinalizar ? _finalizar : null,
                    style: FilledButton.styleFrom(
                      backgroundColor: corEsmeralda,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text(
                      'Concluir (F5)',
                      style: GoogleFonts.plusJakartaSans(
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ConfigCreditoPdv {
  const _ConfigCreditoPdv({required this.parcelas, required this.entrada});
  final int parcelas;
  final double entrada;
}

class _ModalConfigCreditoCliente extends StatefulWidget {
  const _ModalConfigCreditoCliente({
    required this.totalVenda,
    required this.cliente,
  });

  final double totalVenda;
  final Map<String, dynamic> cliente;

  @override
  State<_ModalConfigCreditoCliente> createState() =>
      _ModalConfigCreditoClienteState();
}

class _ModalConfigCreditoClienteState extends State<_ModalConfigCreditoCliente> {
  int _parcelas = 1;
  final _entradaCtrl = TextEditingController(text: '0');

  @override
  void dispose() {
    _entradaCtrl.dispose();
    super.dispose();
  }

  double _parseEntrada() {
    final t = _entradaCtrl.text.trim().replaceAll(RegExp(r'[^\d,.]'), '');
    if (t.contains(',')) {
      return double.tryParse(t.replaceAll('.', '').replaceAll(',', '.')) ?? 0;
    }
    return double.tryParse(t) ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    final f = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    final disp = (widget.cliente['credito_disponivel'] as num?)?.toDouble() ??
        (((widget.cliente['limite_credito'] as num?)?.toDouble() ?? 0) -
            ((widget.cliente['credito_utilizado'] as num?)?.toDouble() ?? 0));
    final entrada = _parseEntrada();
    final financiado = (widget.totalVenda - entrada).clamp(0, double.infinity);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Venda no crediário',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: PainelAdminTheme.roxo,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Cliente: ${widget.cliente['nome']}\nLimite disponível: ${f.format(disp)}',
                style: GoogleFonts.plusJakartaSans(fontSize: 13, height: 1.4),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<int>(
                value: _parcelas,
                decoration: InputDecoration(
                  labelText: 'Quantidade de parcelas',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                items: List.generate(
                  12,
                  (i) => DropdownMenuItem(value: i + 1, child: Text('${i + 1}x')),
                ),
                onChanged: (v) => setState(() => _parcelas = v ?? 1),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _entradaCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Entrada (opcional)',
                  prefixText: 'R\$ ',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              Text(
                'Valor financiado: ${f.format(financiado)} · ${f.format(financiado / _parcelas)}/parcela',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: PainelAdminTheme.textoSecundario,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancelar'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: FilledButton(
                      onPressed: () {
                        if (financiado > disp + 0.009) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Financiado (${f.format(financiado)}) excede limite (${f.format(disp)}).',
                              ),
                            ),
                          );
                          return;
                        }
                        Navigator.pop(
                          context,
                          _ConfigCreditoPdv(
                            parcelas: _parcelas,
                            entrada: entrada,
                          ),
                        );
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor: PainelAdminTheme.laranja,
                      ),
                      child: const Text('Confirmar'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModalSelecionarCliente extends StatefulWidget {
  const _ModalSelecionarCliente({this.lojaId});

  final String? lojaId;

  @override
  State<_ModalSelecionarCliente> createState() => _ModalSelecionarClienteState();
}

class _ModalSelecionarClienteState extends State<_ModalSelecionarCliente> {
  bool _modoCriacao = false;
  bool _buscando = false;
  String? _termoBuscado;
  List<ComercialCliente> _resultadosComercial = const [];
  List<Map<String, dynamic>> _resultadosUsers = const [];
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();

  static const _limiteResultados = 30;

  // Campos para cadastro de novo cliente
  final _formKey = GlobalKey<FormState>();
  String _novoNome = '';
  String _novoTelefone = '';
  String _novoCpf = '';
  bool _salvandoNovo = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  String _getInitials(String name) {
    if (name.isEmpty) return 'C';
    final parts = name.trim().split(' ');
    if (parts.length > 1) {
      return (parts[0][0] + parts[1][0]).toUpperCase();
    }
    return parts[0][0].toUpperCase();
  }

  Future<void> _executarBusca() async {
    final termo = _searchController.text.trim();
    if (termo.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Digite o nome ou CPF do cliente.')),
      );
      return;
    }

    final cpfBusca = termo.replaceAll(RegExp(r'\D'), '');
    if (termo.length < 2 && cpfBusca.length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Digite ao menos 2 letras do nome ou 3 dígitos do CPF.'),
        ),
      );
      return;
    }

    setState(() {
      _buscando = true;
      _termoBuscado = termo;
      _resultadosComercial = const [];
      _resultadosUsers = const [];
    });

    try {
      if (widget.lojaId != null && widget.lojaId!.isNotEmpty) {
        final lista = await ComercialClientesService.buscarPorNomeOuCpf(
          widget.lojaId!,
          termo,
          limite: _limiteResultados,
        );
        if (!mounted) return;
        setState(() {
          _resultadosComercial = lista;
          _buscando = false;
        });
      } else {
        final lista = await _buscarUsersPorNomeOuCpf(termo);
        if (!mounted) return;
        setState(() {
          _resultadosUsers = lista;
          _buscando = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _buscando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao buscar cliente: $e')),
      );
    }
  }

  Future<List<Map<String, dynamic>>> _buscarUsersPorNomeOuCpf(String termo) async {
    final cpfBusca = termo.replaceAll(RegExp(r'\D'), '');
    final nomeBusca = termo.toLowerCase().trim();

    final snap = await FirebaseFirestore.instance
        .collection('users')
        .where('role', isEqualTo: 'cliente')
        .get();

    final resultados = <Map<String, dynamic>>[];
    for (final doc in snap.docs) {
      final data = doc.data();
      final nome =
          (data['nome'] ?? data['nome_completo'] ?? '').toString().toLowerCase();
      final cpf = (data['cpf'] ?? '').toString().replaceAll(RegExp(r'\D'), '');

      final matchNome = nomeBusca.length >= 2 && nome.contains(nomeBusca);
      final matchCpf =
          cpfBusca.length >= 3 && cpf.isNotEmpty && cpf.contains(cpfBusca);

      if (matchNome || matchCpf) {
        resultados.add({
          'id': doc.id,
          'nome': data['nome'] ?? data['nome_completo'] ?? 'Cliente',
          'telefone': data['telefone'] ?? data['fone'] ?? '',
          'cpf': data['cpf'] ?? '',
        });
        if (resultados.length >= _limiteResultados) break;
      }
    }
    return resultados;
  }

  Future<void> _salvarNovoCliente() async {
    if (!_formKey.currentState!.validate()) return;
    _formKey.currentState!.save();

    setState(() => _salvandoNovo = true);

    try {
      final docRef = await FirebaseFirestore.instance.collection('users').add({
        'nome': _novoNome,
        'telefone': _novoTelefone,
        'cpf': _novoCpf,
        'role': 'cliente',
        'tipoUsuario': 'cliente',
        'criado_em': FieldValue.serverTimestamp(),
        'origem_cadastro': 'pdv_web',
      });

      if (mounted) {
        Navigator.pop(context, {
          'id': docRef.id,
          'nome': _novoNome,
          'telefone': _novoTelefone,
          'cpf': _novoCpf,
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _salvandoNovo = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao salvar cliente: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      elevation: 12,
      shadowColor: Colors.black26,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 460),
        padding: const EdgeInsets.all(24),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: _modoCriacao ? _buildCriacaoForm() : _buildSelecaoList(),
        ),
      ),
    );
  }

  Widget _buildSelecaoList() {
    return Column(
      key: const ValueKey('selecao_list'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Cabeçalho
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: PainelAdminTheme.roxo.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.person_search_rounded, color: PainelAdminTheme.roxo, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Selecionar Cliente',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF1E1B4B),
                    ),
                  ),
                  Text(
                    'Digite nome ou CPF e pressione Enter',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      color: PainelAdminTheme.textoSecundario,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close_rounded, color: PainelAdminTheme.textoSecundario),
            ),
          ],
        ),
        const SizedBox(height: 20),

        // Campo de Busca
        TextField(
          controller: _searchController,
          focusNode: _searchFocus,
          autofocus: true,
          textInputAction: TextInputAction.search,
          style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w600),
          decoration: InputDecoration(
            hintText: 'Nome ou CPF do cliente...',
            hintStyle: const TextStyle(color: Color(0xFF9CA3AF)),
            prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF9CA3AF)),
            suffixIcon: IconButton(
              tooltip: 'Buscar (Enter)',
              onPressed: _buscando ? null : _executarBusca,
              icon: const Icon(Icons.keyboard_return_rounded, color: PainelAdminTheme.roxo),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFFE8E4F0), width: 1.5),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFFE8E4F0), width: 1.5),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: PainelAdminTheme.roxo, width: 2),
            ),
          ),
          onSubmitted: (_) => _executarBusca(),
        ),
        const SizedBox(height: 16),

        Flexible(
          child: Container(
            constraints: const BoxConstraints(maxHeight: 300),
            child: _buildAreaResultadosBusca(),
          ),
        ),
        const SizedBox(height: 16),

        // Botão cadastrar
        SizedBox(
          width: double.infinity,
          height: 46,
          child: OutlinedButton.icon(
            onPressed: () => setState(() => _modoCriacao = true),
            icon: const Icon(Icons.add_circle_outline_rounded, color: PainelAdminTheme.roxo, size: 18),
            label: Text(
              'Novo cliente',
              style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold, color: PainelAdminTheme.roxo),
            ),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: PainelAdminTheme.roxo, width: 1.5),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAreaResultadosBusca() {
    if (_buscando) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: CircularProgressIndicator(color: PainelAdminTheme.roxo),
        ),
      );
    }

    if (_termoBuscado == null) {
      return _emptyClientes(idle: true);
    }

    if (widget.lojaId != null && widget.lojaId!.isNotEmpty) {
      if (_resultadosComercial.isEmpty) {
        return _emptyClientes(idle: false);
      }
      return ListView.builder(
        shrinkWrap: true,
        physics: const BouncingScrollPhysics(),
        itemCount: _resultadosComercial.length,
        itemBuilder: (context, index) {
          final c = _resultadosComercial[index];
          return _clienteTile(
            nome: c.nome,
            fone: c.telefone ?? '—',
            cpf: c.cpf ?? '—',
            onTap: () => Navigator.pop(context, c.toPdvMap()),
            extra: c.creditoHabilitado
                ? 'Crédito: ${NumberFormat.currency(locale: 'pt_BR', symbol: r'R$').format(c.creditoDisponivel)}'
                : null,
          );
        },
      );
    }

    if (_resultadosUsers.isEmpty) {
      return _emptyClientes(idle: false);
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const BouncingScrollPhysics(),
      itemCount: _resultadosUsers.length,
      itemBuilder: (context, index) {
        final data = _resultadosUsers[index];
        return _clienteTile(
          nome: data['nome']?.toString() ?? 'Cliente',
          fone: data['telefone']?.toString() ?? '—',
          cpf: data['cpf']?.toString() ?? '—',
          onTap: () => Navigator.pop(context, data),
        );
      },
    );
  }

  Widget _emptyClientes({required bool idle}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              idle ? Icons.search_rounded : Icons.person_off_outlined,
              size: 48,
              color: Colors.grey.shade300,
            ),
            const SizedBox(height: 12),
            Text(
              idle
                  ? 'Digite o nome ou CPF e pressione Enter'
                  : 'Nenhum cliente encontrado para "$_termoBuscado"',
              textAlign: TextAlign.center,
              style: GoogleFonts.plusJakartaSans(
                color: Colors.grey.shade400,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _clienteTile({
    required String nome,
    required String fone,
    required String cpf,
    required VoidCallback onTap,
    String? extra,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE8E4F0)),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            hoverColor: PainelAdminTheme.roxo.withOpacity(0.04),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: PainelAdminTheme.roxo.withOpacity(0.08),
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      _getInitials(nome),
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
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
                          nome,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF1E1B4B),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (extra != null)
                          Text(
                            extra,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: PainelAdminTheme.laranja,
                            ),
                          ),
                        Row(
                          children: [
                            if (fone != 'Sem telefone' && fone != '—') ...[
                              const Icon(Icons.phone_outlined, size: 10, color: Colors.grey),
                              const SizedBox(width: 4),
                              Text(fone, style: const TextStyle(fontSize: 10, color: Colors.grey)),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded, color: Color(0xFFC7D2FE), size: 18),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCriacaoForm() {
    return Form(
      key: _formKey,
      child: Column(
        key: const ValueKey('criacao_form'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: PainelAdminTheme.laranja.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.person_add_rounded, color: PainelAdminTheme.laranja, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Cadastrar Cliente',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF1E1B4B),
                      ),
                    ),
                    Text(
                      'Insira os dados do novo cliente',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        color: PainelAdminTheme.textoSecundario,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => setState(() => _modoCriacao = false),
                icon: const Icon(Icons.close_rounded, color: PainelAdminTheme.textoSecundario),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Nome
          Text(
            'NOME COMPLETO *',
            style: GoogleFonts.plusJakartaSans(fontSize: 10, fontWeight: FontWeight.w800, color: const Color(0xFF4B5563), letterSpacing: 0.5),
          ),
          const SizedBox(height: 6),
          TextFormField(
            autofocus: true,
            style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w600),
            decoration: InputDecoration(
              hintText: 'Ex: João Silva',
              hintStyle: const TextStyle(color: Color(0xFF9CA3AF)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
            validator: (v) => (v == null || v.trim().isEmpty) ? 'Nome é obrigatório' : null,
            onSaved: (v) => _novoNome = v?.trim() ?? '',
          ),
          const SizedBox(height: 16),

          // Telefone
          Text(
            'TELEFONE',
            style: GoogleFonts.plusJakartaSans(fontSize: 10, fontWeight: FontWeight.w800, color: const Color(0xFF4B5563), letterSpacing: 0.5),
          ),
          const SizedBox(height: 6),
          TextFormField(
            keyboardType: TextInputType.phone,
            style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w600),
            decoration: InputDecoration(
              hintText: '(00) 00000-0000',
              hintStyle: const TextStyle(color: Color(0xFF9CA3AF)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onSaved: (v) => _novoTelefone = v?.trim() ?? '',
          ),
          const SizedBox(height: 16),

          // CPF
          Text(
            'CPF',
            style: GoogleFonts.plusJakartaSans(fontSize: 10, fontWeight: FontWeight.w800, color: const Color(0xFF4B5563), letterSpacing: 0.5),
          ),
          const SizedBox(height: 6),
          TextFormField(
            keyboardType: TextInputType.number,
            style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w600),
            decoration: InputDecoration(
              hintText: '000.000.000-00',
              hintStyle: const TextStyle(color: Color(0xFF9CA3AF)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onSaved: (v) => _novoCpf = v?.trim() ?? '',
          ),
          const SizedBox(height: 24),

          // Ações do Form
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => setState(() => _modoCriacao = false),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    side: const BorderSide(color: Color(0xFFE5E7EB)),
                  ),
                  child: Text('Voltar', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _salvandoNovo ? null : _salvarNovoCliente,
                  style: FilledButton.styleFrom(
                    backgroundColor: PainelAdminTheme.roxo,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _salvandoNovo
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : Text('Salvar', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700, color: Colors.white)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ResultadoDesconto {
  final String tipo; // 'reais' | 'porcentagem'
  final double valor;
  final String? motivo;

  _ResultadoDesconto({required this.tipo, required this.valor, this.motivo});
}

class _ModalDescontoPdv extends StatefulWidget {
  final double subtotal;
  final double valorAtual;
  final bool porcentagemAtual;
  final String? motivoAtual;

  const _ModalDescontoPdv({
    required this.subtotal,
    required this.valorAtual,
    required this.porcentagemAtual,
    this.motivoAtual,
  });

  @override
  State<_ModalDescontoPdv> createState() => _ModalDescontoPdvState();
}

class _ModalDescontoPdvState extends State<_ModalDescontoPdv> {
  late bool _porcentagem;
  late double _valor;
  String _motivo = '';
  final _valorController = TextEditingController();
  final _motivoController = TextEditingController();
  String? _erroValidacao;

  @override
  void initState() {
    super.initState();
    _porcentagem = widget.porcentagemAtual;
    _valor = widget.valorAtual;
    _motivo = widget.motivoAtual ?? '';
    if (_valor > 0) {
      _valorController.text = _valor.toStringAsFixed(2).replaceAll('.', ',');
    }
    _motivoController.text = _motivo;
  }

  @override
  void dispose() {
    _valorController.dispose();
    _motivoController.dispose();
    super.dispose();
  }

  void _validarEAplicar() {
    final text = _valorController.text.replaceAll(',', '.').trim();
    if (text.isEmpty) {
      // Limpar desconto
      Navigator.pop(context, _ResultadoDesconto(tipo: 'reais', valor: 0, motivo: null));
      return;
    }

    final val = double.tryParse(text);
    if (val == null || val < 0) {
      setState(() => _erroValidacao = 'Valor inválido');
      return;
    }

    if (_porcentagem) {
      if (val > 100) {
        setState(() => _erroValidacao = 'O desconto não pode exceder 100%');
        return;
      }
    } else {
      if (val > widget.subtotal) {
        setState(() => _erroValidacao = 'O desconto não pode ser maior que o subtotal');
        return;
      }
    }

    Navigator.pop(
      context,
      _ResultadoDesconto(
        tipo: _porcentagem ? 'porcentagem' : 'reais',
        valor: val,
        motivo: _motivoController.text.trim().isEmpty ? null : _motivoController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      elevation: 12,
      shadowColor: Colors.black26,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 400),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: PainelAdminTheme.roxo.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.local_offer_rounded, color: PainelAdminTheme.roxo, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Aplicar Desconto',
                        style: GoogleFonts.plusJakartaSans(fontSize: 18, fontWeight: FontWeight.w800, color: const Color(0xFF1E1B4B)),
                      ),
                      Text(
                        'Insira o desconto em Reais ou %',
                        style: GoogleFonts.plusJakartaSans(fontSize: 12, color: PainelAdminTheme.textoSecundario, fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded, color: PainelAdminTheme.textoSecundario),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Seleção de Tipo
            Row(
              children: [
                Expanded(
                  child: ChoiceChip(
                    label: Center(child: Text(r'R$ Reais', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold))),
                    selected: !_porcentagem,
                    selectedColor: PainelAdminTheme.roxo.withOpacity(0.15),
                    onSelected: (val) {
                      setState(() {
                        _porcentagem = false;
                        _erroValidacao = null;
                      });
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ChoiceChip(
                    label: Center(child: Text('% Porcentagem', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold))),
                    selected: _porcentagem,
                    selectedColor: PainelAdminTheme.roxo.withOpacity(0.15),
                    onSelected: (val) {
                      setState(() {
                        _porcentagem = true;
                        _erroValidacao = null;
                      });
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Valor
            Text(
              _porcentagem ? 'PORCENTAGEM (%)' : 'VALOR (R\$)',
              style: GoogleFonts.plusJakartaSans(fontSize: 10, fontWeight: FontWeight.w800, color: const Color(0xFF4B5563), letterSpacing: 0.5),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _valorController,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: GoogleFonts.plusJakartaSans(fontSize: 15, fontWeight: FontWeight.w600),
              decoration: InputDecoration(
                hintText: _porcentagem ? '10%' : '0,00',
                hintStyle: const TextStyle(color: Color(0xFF9CA3AF)),
                prefixIcon: Icon(_porcentagem ? Icons.percent_rounded : Icons.attach_money_rounded, color: const Color(0xFF9CA3AF)),
                errorText: _erroValidacao,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onChanged: (_) {
                if (_erroValidacao != null) {
                  setState(() => _erroValidacao = null);
                }
              },
            ),
            const SizedBox(height: 16),

            // Motivo
            Text(
              'MOTIVO DO DESCONTO (OPCIONAL)',
              style: GoogleFonts.plusJakartaSans(fontSize: 10, fontWeight: FontWeight.w800, color: const Color(0xFF4B5563), letterSpacing: 0.5),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _motivoController,
              textCapitalization: TextCapitalization.sentences,
              style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w600),
              decoration: InputDecoration(
                hintText: 'Ex: Cliente fiel, cupom físico, parceria...',
                hintStyle: const TextStyle(color: Color(0xFF9CA3AF)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 24),

            // Ações
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      side: const BorderSide(color: Color(0xFFE5E7EB)),
                    ),
                    child: Text('Cancelar', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _validarEAplicar,
                    style: FilledButton.styleFrom(
                      backgroundColor: PainelAdminTheme.roxo,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text('Aplicar', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700, color: Colors.white)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ModalObservacaoPdv extends StatefulWidget {
  final String? observacaoInicial;

  const _ModalObservacaoPdv({this.observacaoInicial});

  @override
  State<_ModalObservacaoPdv> createState() => _ModalObservacaoPdvState();
}

class _ModalObservacaoPdvState extends State<_ModalObservacaoPdv> {
  final _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    _controller.text = widget.observacaoInicial ?? '';
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      elevation: 12,
      shadowColor: Colors.black26,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 400),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFBEB),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.note_alt_rounded, color: Color(0xFFD97706), size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Observação da Venda',
                        style: GoogleFonts.plusJakartaSans(fontSize: 18, fontWeight: FontWeight.w800, color: const Color(0xFF1E1B4B)),
                      ),
                      Text(
                        'Insira notas específicas sobre o pedido',
                        style: GoogleFonts.plusJakartaSans(fontSize: 12, color: PainelAdminTheme.textoSecundario, fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded, color: PainelAdminTheme.textoSecundario),
                ),
              ],
            ),
            const SizedBox(height: 20),

            Text(
              'NOTAS DA VENDA',
              style: GoogleFonts.plusJakartaSans(fontSize: 10, fontWeight: FontWeight.w800, color: const Color(0xFF4B5563), letterSpacing: 0.5),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _controller,
              maxLines: 4,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w600),
              decoration: InputDecoration(
                hintText: 'Ex: cliente pediu embalagem para presente',
                hintStyle: const TextStyle(color: Color(0xFF9CA3AF)),
                contentPadding: const EdgeInsets.all(16),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
            const SizedBox(height: 24),

            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      side: const BorderSide(color: Color(0xFFE5E7EB)),
                    ),
                    child: Text('Cancelar', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context, _controller.text),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFD97706),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text('Salvar', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700, color: Colors.white)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ModalCalculadora extends StatefulWidget {
  final VoidCallback onClose;

  const _ModalCalculadora({required this.onClose});

  @override
  State<_ModalCalculadora> createState() => _ModalCalculadoraState();
}

class _ModalCalculadoraState extends State<_ModalCalculadora> {
  String _display = '0';
  double? _operandoAnterior;
  String? _operador;
  bool _limparTela = false;

  void _pressionarNumero(String digito) {
    setState(() {
      if (_display == '0' || _limparTela) {
        _display = digito;
        _limparTela = false;
      } else {
        _display += digito;
      }
    });
  }

  void _pressionarC() {
    setState(() {
      _display = '0';
      _operandoAnterior = null;
      _operador = null;
      _limparTela = false;
    });
  }

  void _pressionarOperador(String operador) {
    final v = double.tryParse(_display) ?? 0.0;
    setState(() {
      _operandoAnterior = v;
      _operador = operador;
      _limparTela = true;
    });
  }

  void _pressionarIgual() {
    if (_operandoAnterior == null || _operador == null) return;
    final v2 = double.tryParse(_display) ?? 0.0;
    double resultado = 0.0;

    switch (_operador) {
      case '+':
        resultado = _operandoAnterior! + v2;
        break;
      case '-':
        resultado = _operandoAnterior! - v2;
        break;
      case '×':
        resultado = _operandoAnterior! * v2;
        break;
      case '÷':
        resultado = v2 == 0 ? 0.0 : _operandoAnterior! / v2;
        break;
    }

    setState(() {
      if (resultado % 1 == 0) {
        _display = resultado.toInt().toString();
      } else {
        _display = resultado.toStringAsFixed(4);
        while (_display.endsWith('0')) {
          _display = _display.substring(0, _display.length - 1);
        }
        if (_display.endsWith('.')) {
          _display = _display.substring(0, _display.length - 1);
        }
      }
      _operandoAnterior = null;
      _operador = null;
      _limparTela = true;
    });
  }

  void _pressionarApagar() {
    setState(() {
      if (_display.length > 1) {
        _display = _display.substring(0, _display.length - 1);
      } else {
        _display = '0';
      }
    });
  }

  void _pressionarPorcentagem() {
    final v = double.tryParse(_display) ?? 0.0;
    setState(() {
      final res = v / 100.0;
      _display = res.toString();
    });
  }

  Widget _buildBotao(String texto, {Color? corFundo, Color? corTexto, VoidCallback? onTap}) {
    final bg = corFundo ?? const Color(0xFFF3F4F6);
    final fg = corTexto ?? const Color(0xFF1F2937);

    return Container(
      width: 48,
      height: 48,
      margin: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 1, offset: Offset(0, 1))],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Center(
            child: Text(
              texto,
              style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.bold, color: fg),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const bgHeader = Color(0xFF1E1B4B);
    const bgBody = Color(0xFF2E2A5D);

    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is! KeyUpEvent) {
          final key = event.logicalKey;
          final char = event.character;

          // Verificar números
          if (key == LogicalKeyboardKey.digit0 || key == LogicalKeyboardKey.numpad0) {
            _pressionarNumero('0');
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.digit1 || key == LogicalKeyboardKey.numpad1) {
            _pressionarNumero('1');
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.digit2 || key == LogicalKeyboardKey.numpad2) {
            _pressionarNumero('2');
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.digit3 || key == LogicalKeyboardKey.numpad3) {
            _pressionarNumero('3');
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.digit4 || key == LogicalKeyboardKey.numpad4) {
            _pressionarNumero('4');
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.digit5 || key == LogicalKeyboardKey.numpad5) {
            if (HardwareKeyboard.instance.isShiftPressed || char == '%') {
              _pressionarPorcentagem();
            } else {
              _pressionarNumero('5');
            }
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.digit6 || key == LogicalKeyboardKey.numpad6) {
            _pressionarNumero('6');
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.digit7 || key == LogicalKeyboardKey.numpad7) {
            _pressionarNumero('7');
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.digit8 || key == LogicalKeyboardKey.numpad8) {
            if (HardwareKeyboard.instance.isShiftPressed || char == '*') {
              _pressionarOperador('×');
            } else {
              _pressionarNumero('8');
            }
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.digit9 || key == LogicalKeyboardKey.numpad9) {
            _pressionarNumero('9');
            return KeyEventResult.handled;
          }

          // Separador decimal (ponto ou vírgula)
          if (key == LogicalKeyboardKey.comma || key == LogicalKeyboardKey.period || key == LogicalKeyboardKey.numpadDecimal || char == ',' || char == '.') {
            if (!_display.contains(',')) {
              setState(() => _display += ',');
            }
            return KeyEventResult.handled;
          }

          // Backspace (apagar último dígito)
          if (key == LogicalKeyboardKey.backspace) {
            _pressionarApagar();
            return KeyEventResult.handled;
          }

          // Tecla C ou Delete (limpar tudo)
          if (key == LogicalKeyboardKey.keyC || key == LogicalKeyboardKey.delete || char == 'c' || char == 'C') {
            _pressionarC();
            return KeyEventResult.handled;
          }

          // Tecla ESC para fechar
          if (key == LogicalKeyboardKey.escape) {
            widget.onClose();
            return KeyEventResult.handled;
          }

          // Operadores por caractere (altamente compatível)
          if (char == '+') {
            _pressionarOperador('+');
            return KeyEventResult.handled;
          }
          if (char == '-') {
            _pressionarOperador('-');
            return KeyEventResult.handled;
          }
          if (char == '*' || char == 'x' || char == 'X') {
            _pressionarOperador('×');
            return KeyEventResult.handled;
          }
          if (char == '/') {
            _pressionarOperador('÷');
            return KeyEventResult.handled;
          }
          if (char == '%') {
            _pressionarPorcentagem();
            return KeyEventResult.handled;
          }

          // Igual / Calcular (= ou Enter)
          if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter || char == '=') {
            _pressionarIgual();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: Container(
        width: 250,
        height: 410,
        decoration: BoxDecoration(
          color: bgBody,
          borderRadius: BorderRadius.circular(20),
          boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 20, offset: Offset(0, 8))],
        ),
        child: Column(
          children: [
          // Barra de Titulo
          Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: const BoxDecoration(
              color: bgHeader,
              borderRadius: BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20)),
            ),
            child: Row(
              children: [
                const Icon(Icons.calculate_rounded, color: Colors.white70, size: 16),
                const SizedBox(width: 8),
                Text('Calculadora', style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                const Spacer(),
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: widget.onClose,
                  icon: const Icon(Icons.close_rounded, color: Colors.white60, size: 16),
                ),
              ],
            ),
          ),

          // Display
          Container(
            height: 60,
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: bgHeader.withOpacity(0.4),
            alignment: Alignment.bottomRight,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              reverse: true,
              child: Text(
                _display,
                style: GoogleFonts.shareTechMono(fontSize: 28, color: const Color(0xFF22C55E), letterSpacing: 1),
              ),
            ),
          ),

          // Teclado
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                children: [
                  Row(
                    children: [
                      _buildBotao('C', corFundo: Colors.red.shade900, corTexto: Colors.white, onTap: _pressionarC),
                      _buildBotao('%', onTap: _pressionarPorcentagem),
                      _buildBotao('⌫', onTap: _pressionarApagar),
                      _buildBotao('÷', corFundo: PainelAdminTheme.roxo, corTexto: Colors.white, onTap: () => _pressionarOperador('÷')),
                    ],
                  ),
                  Row(
                    children: [
                      _buildBotao('7', onTap: () => _pressionarNumero('7')),
                      _buildBotao('8', onTap: () => _pressionarNumero('8')),
                      _buildBotao('9', onTap: () => _pressionarNumero('9')),
                      _buildBotao('×', corFundo: PainelAdminTheme.roxo, corTexto: Colors.white, onTap: () => _pressionarOperador('×')),
                    ],
                  ),
                  Row(
                    children: [
                      _buildBotao('4', onTap: () => _pressionarNumero('4')),
                      _buildBotao('5', onTap: () => _pressionarNumero('5')),
                      _buildBotao('6', onTap: () => _pressionarNumero('6')),
                      _buildBotao('-', corFundo: PainelAdminTheme.roxo, corTexto: Colors.white, onTap: () => _pressionarOperador('-')),
                    ],
                  ),
                  Row(
                    children: [
                      _buildBotao('1', onTap: () => _pressionarNumero('1')),
                      _buildBotao('2', onTap: () => _pressionarNumero('2')),
                      _buildBotao('3', onTap: () => _pressionarNumero('3')),
                      _buildBotao('+', corFundo: PainelAdminTheme.roxo, corTexto: Colors.white, onTap: () => _pressionarOperador('+')),
                    ],
                  ),
                  Row(
                    children: [
                      _buildBotao('0', onTap: () => _pressionarNumero('0')),
                      _buildBotao(',', onTap: () {
                        if (!_display.contains(',')) {
                          setState(() => _display += ',');
                        }
                      }),
                      // Botão de igual expandido para preencher espaço
                      Expanded(
                        child: Container(
                          height: 48,
                          margin: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: PainelAdminTheme.laranja,
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 1, offset: Offset(0, 1))],
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(10),
                              onTap: _pressionarIgual,
                              child: const Center(
                                child: Text('=', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
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
          ),
        ],
      ),
    ),
   );
  }
}
