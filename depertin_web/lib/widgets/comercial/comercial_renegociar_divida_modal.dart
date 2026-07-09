import 'dart:async';
import 'dart:convert';

import 'package:depertin_web/models/comercial_credito.dart';
import 'package:depertin_web/models/comercial_pendencia_data.dart';
import 'package:depertin_web/services/comercial_clientes_service.dart';
import 'package:depertin_web/services/comercial_credito_service.dart';
import 'package:depertin_web/services/firebase_functions_config.dart';
import 'package:depertin_web/theme/painel_admin_theme.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

/// Abre o modal de renegociação de dívida.
/// Retorna `true` se houve pagamento ou alteração que exige atualizar pendências.
Future<bool?> mostrarRenegociarDividaModal(
  BuildContext context, {
  required String lojaId,
  required PendenciaFinanceiraCliente divida,
  required List<ComercialParcelaCliente> parcelas,
  required JurosMultaConfig configJuros,
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (_) => _RenegociarDividaModal(
      lojaId: lojaId,
      divida: divida,
      parcelas: parcelas,
      configJuros: configJuros,
    ),
  );
}

// =============================================================================
// TIPOS DE NEGOCIAÇÃO
// =============================================================================

enum TipoRenegociacao {
  avista('À vista', Icons.money_rounded, 'Pague o valor total com desconto'),
  parcelar('Parcelar', Icons.calendar_view_month_rounded,
      'Divida o valor em novas parcelas'),
  vencimento('Alterar vencimento', Icons.date_range_rounded,
      'Mude a data de vencimento'),
  desconto('Aplicar desconto', Icons.discount_rounded,
      'Conceda desconto sobre o valor'),
  isentarJuros('Isentar juros', Icons.monetization_on_outlined,
      'Remova os juros da dívida'),
  isentarMulta('Isentar multa', Icons.gpp_bad_outlined,
      'Remova a multa da dívida'),
  personalizada('Personalizada', Icons.tune_rounded,
      'Configure cada aspecto manualmente');

  const TipoRenegociacao(this.rotulo, this.icone, this.descricao);
  final String rotulo;
  final IconData icone;
  final String descricao;
}

// =============================================================================
// MODELO INTERNO DE CRONOGRAMA
// =============================================================================

class _ParcelaSimulada {
  _ParcelaSimulada({
    required this.numero,
    required this.valor,
    required this.vencimento,
  });

  final int numero;
  final double valor;
  DateTime vencimento;
}

// =============================================================================
// MODAL PRINCIPAL
// =============================================================================

class _RenegociarDividaModal extends StatefulWidget {
  const _RenegociarDividaModal({
    required this.lojaId,
    required this.divida,
    required this.parcelas,
    required this.configJuros,
  });

  final String lojaId;
  final PendenciaFinanceiraCliente divida;
  final List<ComercialParcelaCliente> parcelas;
  final JurosMultaConfig configJuros;

  @override
  State<_RenegociarDividaModal> createState() => _RenegociarDividaModalState();
}

class _RenegociarDividaModalState extends State<_RenegociarDividaModal>
    with SingleTickerProviderStateMixin {
  late AnimationController _animCtrl;
  late Animation<double> _scaleAnim;
  late Animation<double> _fadeAnim;

  // ─── Constantes visuais ───
  static const _roxo = PainelAdminTheme.roxo;
  static const _laranja = PainelAdminTheme.laranja;
  static const _texto = Color(0xFF1E1B4B);
  static const _muted = Color(0xFF64748B);
  static const _verde = Color(0xFF16A34A);
  static const _vermelho = Color(0xFFDC2626);
  static const _fundoCard = Color(0xFFF8F9FC);
  static const _borda = Color(0xFFE2E8F0);

  final _moeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
  final _dataFmt = DateFormat('dd/MM/yyyy', 'pt_BR');

  // ─── Estado ───
  TipoRenegociacao _tipo = TipoRenegociacao.avista;
  final Set<String> _parcelasSelecionadas = {};
  String _observacao = '';
  final _obsCtrl = TextEditingController();

  // À vista - desconto é APENAS em %
  double _descontoPercentualAVista = 0;
  final _descPercentualAVistaCtrl = TextEditingController();

  // Parcelar
  int _qtdParcelasNovas = 3;
  double _entradaValor = 0;
  final _entradaCtrl = TextEditingController();
  DateTime _primeiroVencimento = DateTime.now().add(const Duration(days: 30));
  String _intervaloParcelas = 'Mensal';

  /// Retorna o menor vencimento entre as parcelas efetivamente selecionadas (em aberto).
  /// Se não houver, retorna 30 dias a partir de hoje como fallback.
  DateTime _obterPrimeiroVencimentoDasSelecionadas() {
    final abertas = _parcelasEfetivamenteSelecionadas;
    if (abertas.isEmpty) return DateTime.now().add(const Duration(days: 30));
    DateTime menor = abertas.first.dataVencimento;
    for (final p in abertas) {
      if (p.dataVencimento.isBefore(menor)) menor = p.dataVencimento;
    }
    return menor;
  }

  // Alterar vencimento
  DateTime _novoVencimento = DateTime.now().add(const Duration(days: 15));
  bool _alterarTodasParcelas = true;
  int _parcelaAlvoIndex = 0;

  // Desconto - APENAS em %
  double _descontoPercentual = 0;
  final _descPercentualCtrl = TextEditingController();

  // Juros
  String _acaoJuros = 'manter'; // manter, remover, reduzir, novo
  double _novoJurosPercentual = 0;
  final _jurosCtrl = TextEditingController();

  // Multa
  String _acaoMulta = 'manter'; // manter, remover, reduzir, personalizada
  double _novaMultaPercentual = 0;
  final _multaCtrl = TextEditingController();

  bool _salvando = false;
  String? _usuarioNome;
  late List<ComercialParcelaCliente> _parcelasLocais;

  // Intervalo em dias
  int get _intervaloDias {
    switch (_intervaloParcelas) {
      case 'Semanal':
        return 7;
      case 'Quinzenal':
        return 15;
      default:
        return 30;
    }
  }

  // ─── Cálculos ao vivo (TUDO baseado nas parcelas SELECIONADAS) ───

  /// Todas as parcelas em aberto da dívida (exclui já renegociadas/pagas).
  List<ComercialParcelaCliente> get _parcelasAbertas =>
      _parcelasLocais.where(_parcelaEstaAberta).toList();

  bool _parcelaEstaAberta(ComercialParcelaCliente p) {
    if (p.valorEmAberto <= 0.009) return false;
    final stts = p.status.toLowerCase();
    if (stts == 'pago' ||
        stts == 'cancelado' ||
        stts == 'estornado' ||
        stts == 'renegociado') {
      return false;
    }
    return true;
  }

  /// Parcelas que o lojista marcou. Só considera as que ainda estão abertas.
  List<ComercialParcelaCliente> get _parcelasEfetivamenteSelecionadas =>
      _parcelasLocais.where((p) {
        if (!_parcelasSelecionadas.contains(p.id)) return false;
        return _parcelaEstaAberta(p);
      }).toList();

  /// Total do valor original (soma do valorEmAberto) das parcelas selecionadas.
  double get _totalOriginalSelecionado {
    double total = 0;
    for (final p in _parcelasEfetivamenteSelecionadas) {
      total += p.valorEmAberto;
    }
    return _round(total);
  }

  /// Total da dívida inteira (soma das parcelas em aberto).
  double get _totalDividaInteira {
    var total = 0.0;
    for (final p in _parcelasAbertas) {
      total += p.valorEmAberto;
    }
    return _round(total);
  }

  double get _totalVencidoAtual {
    final hoje = DateTime.now();
    final hojeClean = DateTime(hoje.year, hoje.month, hoje.day);
    var total = 0.0;
    for (final p in _parcelasAbertas) {
      final venc = DateTime(
        p.dataVencimento.year,
        p.dataVencimento.month,
        p.dataVencimento.day,
      );
      if (venc.isBefore(hojeClean)) total += p.valorEmAberto;
    }
    return _round(total);
  }

  /// Juros calculados para as parcelas selecionadas.
  double get _jurosCalculados {
    if (_parcelasSelecionadas.isEmpty) return 0;
    double total = 0;
    final hoje = DateTime.now();
    final hojeClean = DateTime(hoje.year, hoje.month, hoje.day);
    for (final p in _parcelasEfetivamenteSelecionadas) {
      if (p.valorEmAberto <= 0.009) continue;
      final venc = DateTime(
          p.dataVencimento.year, p.dataVencimento.month, p.dataVencimento.day);
      if (venc.isBefore(hojeClean)) {
        final calc =
            calcularJurosMulta(p.valorEmAberto, p.dataVencimento, widget.configJuros);
        total += calc.juros;
      }
    }
    return _round(total);
  }

  /// Multa calculada para as parcelas selecionadas.
  double get _multaCalculada {
    if (_parcelasSelecionadas.isEmpty) return 0;
    double total = 0;
    final hoje = DateTime.now();
    final hojeClean = DateTime(hoje.year, hoje.month, hoje.day);
    for (final p in _parcelasEfetivamenteSelecionadas) {
      if (p.valorEmAberto <= 0.009) continue;
      final venc = DateTime(
          p.dataVencimento.year, p.dataVencimento.month, p.dataVencimento.day);
      if (venc.isBefore(hojeClean)) {
        final calc =
            calcularJurosMulta(p.valorEmAberto, p.dataVencimento, widget.configJuros);
        total += calc.multa;
      }
    }
    return _round(total);
  }

  /// Valor base da negociação = original + juros + multa das selecionadas.
  double get _valorBaseNegociacao =>
      _round(_totalOriginalSelecionado + _jurosCalculados + _multaCalculada);

  /// Juros aplicados conforme a configuração do lojista (aba "Isentar juros").
  double get _jurosAplicadosConfig {
    switch (_acaoJuros) {
      case 'remover':
        return 0;
      case 'reduzir':
        // Reduz o JUROS ORIGINAL pelo percentual
        if (_novoJurosPercentual <= 0) return _jurosCalculados;
        final reducao = _round(_jurosCalculados * (_novoJurosPercentual / 100));
        return _round((_jurosCalculados - reducao).clamp(0, double.infinity));
      case 'novo':
        // Aplica NOVOS juros como percentual do principal
        if (_novoJurosPercentual <= 0) return 0;
        return _round(_totalOriginalSelecionado * (_novoJurosPercentual / 100));
      default: // manter
        return _jurosCalculados;
    }
  }

  /// Multa aplicada conforme a configuração do lojista (aba "Isentar multa").
  double get _multaAplicadaConfig {
    switch (_acaoMulta) {
      case 'remover':
        return 0;
      case 'reduzir':
        // Reduz a MULTA ORIGINAL pelo percentual
        if (_novaMultaPercentual <= 0) return _multaCalculada;
        final reducao =
            _round(_multaCalculada * (_novaMultaPercentual / 100));
        return _round((_multaCalculada - reducao).clamp(0, double.infinity));
      case 'personalizada':
        // Aplica multa personalizada como percentual do principal
        if (_novaMultaPercentual <= 0) return 0;
        return _round(
            _totalOriginalSelecionado * (_novaMultaPercentual / 100));
      default: // manter
        return _multaCalculada;
    }
  }

  /// Valor do desconto calculado (sempre em %).
  double get _descontoCalculado {
    if (_parcelasSelecionadas.isEmpty) return 0;
    switch (_tipo) {
      case TipoRenegociacao.avista:
        if (_descontoPercentualAVista <= 0) return 0;
        final base = _valorBaseNegociacao;
        return _round(base * (_descontoPercentualAVista / 100));
      case TipoRenegociacao.desconto:
        if (_descontoPercentual <= 0) return 0;
        return _round(_valorBaseNegociacao * (_descontoPercentual / 100));
      default:
        return 0;
    }
  }

  /// Novo valor final após aplicar todas as configurações.
  double get _valorFinalNegociacao {
    if (_parcelasSelecionadas.isEmpty) return 0;
    // Base: valor original das selecionadas
    double base = _totalOriginalSelecionado;
    // Aplica juros (segundo config)
    base += _jurosAplicadosConfig;
    // Aplica multa (segundo config)
    base += _multaAplicadaConfig;
    // Aplica desconto
    base -= _descontoCalculado;
    return _round(base.clamp(0, double.infinity));
  }

  double get _valorParcelaNova {
    if (_qtdParcelasNovas <= 0 || _parcelasSelecionadas.isEmpty) return 0;
    final saldo = _valorFinalNegociacao - _entradaValor;
    if (saldo <= 0) return 0;
    return _round(saldo / _qtdParcelasNovas);
  }

  List<_ParcelaSimulada> get _cronogramaNovo {
    final lista = <_ParcelaSimulada>[];
    if (_qtdParcelasNovas <= 0 || _parcelasSelecionadas.isEmpty) return lista;

    if (_entradaValor > 0) {
      lista.add(_ParcelaSimulada(
        numero: 0,
        valor: _entradaValor,
        vencimento: _primeiroVencimento,
      ));
    }

    final saldo = _valorFinalNegociacao - _entradaValor;
    final valorBase = _round(saldo / _qtdParcelasNovas);
    var inicio = _entradaValor > 0
        ? _primeiroVencimento.add(Duration(days: _intervaloDias))
        : _primeiroVencimento;

    for (var i = 0; i < _qtdParcelasNovas; i++) {
      final valor = (i == _qtdParcelasNovas - 1)
          ? _round(saldo - valorBase * (_qtdParcelasNovas - 1))
          : valorBase;
      lista.add(_ParcelaSimulada(
        numero: i + 1,
        valor: valor,
        vencimento: inicio,
      ));
      inicio = inicio.add(Duration(days: _intervaloDias));
    }
    return lista;
  }

  /// Valida se o botão "Confirmar" pode ser habilitado.
  bool get _podeConfirmar {
    // 1. Pelo menos 1 parcela selecionada
    if (_parcelasSelecionadas.isEmpty) return false;
    // 2. Tipo de negociação selecionado (sempre tem um)
    // 3. Observação com mínimo 5 caracteres
    if (_observacao.trim().length < 5) return false;
    // 4. Validações específicas por tipo
    switch (_tipo) {
      case TipoRenegociacao.avista:
        if (_valorFinalNegociacao < 0) return false;
        return true;
      case TipoRenegociacao.parcelar:
        if (_qtdParcelasNovas < 1 || _qtdParcelasNovas > 48) return false;
        if (_valorFinalNegociacao < 0) return false;
        // Valor da entrada não pode ser maior que o valor final
        if (_entradaValor > _valorFinalNegociacao) return false;
        return true;
      case TipoRenegociacao.vencimento:
        return _novoVencimento.isAfter(DateTime.now());
      case TipoRenegociacao.desconto:
        return _descontoPercentual > 0 && _descontoPercentual <= 100;
      case TipoRenegociacao.isentarJuros:
        if (_acaoJuros == 'reduzir' || _acaoJuros == 'novo') {
          if (_novoJurosPercentual <= 0 || _novoJurosPercentual > 100) return false;
        }
        return true;
      case TipoRenegociacao.isentarMulta:
        if (_acaoMulta == 'reduzir' || _acaoMulta == 'personalizada') {
          if (_novaMultaPercentual <= 0 || _novaMultaPercentual > 100) return false;
        }
        return true;
      case TipoRenegociacao.personalizada:
        if (_valorFinalNegociacao < 0) return false;
        return true;
    }
  }

  /// Mensagem de validação mostrada no rodapé.
  String? get _mensagemValidacao {
    if (_parcelasSelecionadas.isEmpty) return 'Selecione pelo menos uma parcela.';
    if (_observacao.trim().length < 5) return 'A observação deve ter no mínimo 5 caracteres.';
    switch (_tipo) {
      case TipoRenegociacao.avista:
        if (_descontoPercentualAVista > 100) return 'Desconto não pode ultrapassar 100%.';
        return null;
      case TipoRenegociacao.parcelar:
        if (_qtdParcelasNovas < 1) return 'Informe a quantidade de parcelas.';
        if (_qtdParcelasNovas > 48) return 'Máximo de 48 parcelas permitido.';
        if (_entradaValor > _valorFinalNegociacao) return 'Entrada não pode ser maior que o valor final.';
        return null;
      case TipoRenegociacao.vencimento:
        if (!_novoVencimento.isAfter(DateTime.now())) return 'O novo vencimento deve ser no futuro.';
        return null;
      case TipoRenegociacao.desconto:
        if (_descontoPercentual <= 0) return 'Informe o percentual de desconto.';
        if (_descontoPercentual > 100) return 'Desconto não pode ultrapassar 100%.';
        return null;
      default:
        return null;
    }
  }

  @override
  void initState() {
    super.initState();
    _parcelasLocais = widget.parcelas.where(_parcelaEstaAberta).toList();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _scaleAnim =
        CurvedAnimation(parent: _animCtrl, curve: Curves.elasticOut);
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _animCtrl.forward();

    _carregarUsuario();
  }

  Future<void> _carregarUsuario() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        _usuarioNome = user.displayName ?? user.email ?? 'Sistema';
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    _obsCtrl.dispose();
    _descPercentualAVistaCtrl.dispose();
    _entradaCtrl.dispose();
    _descPercentualCtrl.dispose();
    _jurosCtrl.dispose();
    _multaCtrl.dispose();
    super.dispose();
  }

  /// Limpa estados específicos ao trocar de tipo de negociação.
  void _limparEstadoAoTrocarTipo(TipoRenegociacao novoTipo) {
    switch (novoTipo) {
      case TipoRenegociacao.avista:
        // Mantém campos do à vista, reseta outros
        _acaoJuros = 'manter';
        _acaoMulta = 'manter';
        _novoJurosPercentual = 0;
        _jurosCtrl.clear();
        _novaMultaPercentual = 0;
        _multaCtrl.clear();
        _descontoPercentual = 0;
        _descPercentualCtrl.clear();
        break;
      case TipoRenegociacao.parcelar:
        _descontoPercentualAVista = 0;
        _descPercentualAVistaCtrl.clear();
        _descontoPercentual = 0;
        _descPercentualCtrl.clear();
        _acaoJuros = 'manter';
        _acaoMulta = 'manter';
        _novoJurosPercentual = 0;
        _jurosCtrl.clear();
        _novaMultaPercentual = 0;
        _multaCtrl.clear();
        // Ao entrar em parcelar, usa a data mais antiga das parcelas selecionadas
        _primeiroVencimento = _obterPrimeiroVencimentoDasSelecionadas();
        break;
      case TipoRenegociacao.vencimento:
        _descontoPercentualAVista = 0;
        _descPercentualAVistaCtrl.clear();
        _descontoPercentual = 0;
        _descPercentualCtrl.clear();
        _acaoJuros = 'manter';
        _acaoMulta = 'manter';
        _novoJurosPercentual = 0;
        _jurosCtrl.clear();
        _novaMultaPercentual = 0;
        _multaCtrl.clear();
        break;
      case TipoRenegociacao.desconto:
        _descontoPercentualAVista = 0;
        _descPercentualAVistaCtrl.clear();
        _acaoJuros = 'manter';
        _acaoMulta = 'manter';
        _novoJurosPercentual = 0;
        _jurosCtrl.clear();
        _novaMultaPercentual = 0;
        _multaCtrl.clear();
        break;
      case TipoRenegociacao.isentarJuros:
        _acaoJuros = 'manter'; // começa em "manter", não aplicar nada
        _novoJurosPercentual = 0;
        _jurosCtrl.clear();
        _descontoPercentualAVista = 0;
        _descPercentualAVistaCtrl.clear();
        _descontoPercentual = 0;
        _descPercentualCtrl.clear();
        _acaoMulta = 'manter';
        _novaMultaPercentual = 0;
        _multaCtrl.clear();
        break;
      case TipoRenegociacao.isentarMulta:
        _acaoMulta = 'manter'; // começa em "manter", não aplicar nada
        _novaMultaPercentual = 0;
        _multaCtrl.clear();
        _descontoPercentualAVista = 0;
        _descPercentualAVistaCtrl.clear();
        _descontoPercentual = 0;
        _descPercentualCtrl.clear();
        _acaoJuros = 'manter';
        _novoJurosPercentual = 0;
        _jurosCtrl.clear();
        break;
      case TipoRenegociacao.personalizada:
        _descontoPercentualAVista = 0;
        _descPercentualAVistaCtrl.clear();
        _descontoPercentual = 0;
        _descPercentualCtrl.clear();
        break;
    }
  }

  double _round(double v) => (v * 100).roundToDouble() / 100;

  void _aplicarMascaraPercentual(
      TextEditingController ctrl, void Function(double) onValor) {
    final text = ctrl.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (text.isEmpty) {
      onValor(0);
      ctrl.value = const TextEditingValue(text: '');
      return;
    }
    final valor = int.parse(text).clamp(0, 100);
    onValor(valor.toDouble());
    final display = '$valor';
    ctrl.value = TextEditingValue(
      text: '$display%',
      selection: TextSelection.collapsed(offset: display.length),
    );
  }

  void _aplicarMascaraMoeda(
      TextEditingController ctrl, void Function(double) onValor) {
    final text = ctrl.text.replaceAll(RegExp(r'\D'), '');
    if (text.isEmpty) {
      onValor(0);
      ctrl.value = const TextEditingValue(text: '');
      return;
    }
    final valor = int.parse(text) / 100;
    onValor(valor);
    ctrl.value = TextEditingValue(
      text: _moeda.format(valor),
      selection: TextSelection.collapsed(offset: _moeda.format(valor).length),
    );
  }

  Future<void> _recarregarParcelasAbertas() async {
    try {
      final todas = await ComercialCreditoService.carregarParcelasCliente(
        widget.lojaId,
        widget.divida.clienteId,
      );
      if (!mounted) return;
      final abertas = todas.where(_parcelaEstaAberta).toList();
      setState(() {
        _parcelasLocais = abertas;
        _parcelasSelecionadas.removeWhere(
          (id) => !abertas.any((p) => p.id == id),
        );
      });
      if (abertas.isEmpty && mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      debugPrint('[RenegociarDivida] Erro ao recarregar parcelas: $e');
    }
  }

  // ─── Efetuar Pagamento ───

  Future<void> _mostrarPagamentoCrediario() async {
    final parcelasPagamento = _parcelasEfetivamenteSelecionadas.toList();

    final pagamentoOk = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (_) => _PagamentoCrediarioModal(
        lojaId: widget.lojaId,
        clienteId: widget.divida.clienteId,
        clienteNome: widget.divida.clienteNome,
        clienteCpf: widget.divida.clienteCpf,
        parcelas: parcelasPagamento,
        configJuros: widget.configJuros,
        usuarioNome: _usuarioNome ?? 'Sistema',
      ),
    );
    if (!mounted) return;
    if (pagamentoOk == true) {
      await _recarregarParcelasAbertas();
    } else {
      setState(() {});
    }
  }

  Future<void> _confirmarRenegociacao() async {
    if (!_podeConfirmar) return;

    final confirmado = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (_) => _ConfirmarRenegociacaoModal(
        clienteNome: widget.divida.clienteNome,
        valorOriginal: _totalOriginalSelecionado,
        novoValor: _valorFinalNegociacao,
        desconto: _descontoCalculado,
        juros: _jurosAplicadosConfig,
        multa: _multaAplicadaConfig,
        tipo: _tipo,
        qtdParcelas: _qtdParcelasNovas,
        valorParcela: _valorParcelaNova,
        cronograma: _cronogramaNovo,
        observacao: _observacao,
        usuarioNome: _usuarioNome,
      ),
    );

    if (confirmado != true) return;
    if (!mounted) return;

    setState(() => _salvando = true);

    try {
      await _executarRenegociacao();
      if (!mounted) return;
      await _mostrarDialogoSucesso();
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      await _mostrarDialogoErro(e.toString());
      if (!mounted) return;
      setState(() => _salvando = false);
    }
  }

  Future<void> _mostrarDialogoSucesso() async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        backgroundColor: Colors.transparent,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Ícone de sucesso animado
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        colors: [Color(0xFF10B981), Color(0xFF059669)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF10B981).withValues(alpha: 0.3),
                          blurRadius: 20,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.check_rounded,
                      color: Colors.white,
                      size: 44,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Renegociação Concluída!',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF1E1B4B),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'A dívida foi renegociada com sucesso. Todos os valores estão atualizados no sistema.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      height: 1.5,
                      color: PainelAdminTheme.textoSecundario,
                    ),
                  ),
                  const SizedBox(height: 28),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () => Navigator.pop(ctx),
                      style: FilledButton.styleFrom(
                        backgroundColor: PainelAdminTheme.roxo,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        'Fechar',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _mostrarDialogoErro(String erro) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        backgroundColor: Colors.transparent,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        colors: [Color(0xFFEF4444), Color(0xFFDC2626)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFEF4444).withValues(alpha: 0.3),
                          blurRadius: 20,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.close_rounded,
                      color: Colors.white,
                      size: 44,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Erro ao Renegociar',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF1E1B4B),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF2F2),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: const Color(0xFFFEE2E2),
                      ),
                    ),
                    child: Text(
                      erro,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        height: 1.45,
                        color: const Color(0xFF991B1B),
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () => Navigator.pop(ctx),
                      style: FilledButton.styleFrom(
                        backgroundColor: PainelAdminTheme.roxo,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        'Fechar',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _executarRenegociacao() async {
    final lojaId = widget.lojaId;
    final clienteId = widget.divida.clienteId;

    // Monta cronograma para a função (parcelamento) — datas como ISO string
    final cronogramaMap = _cronogramaNovo.map((p) => {
      'numero': p.numero,
      'valor': p.valor,
      'vencimento': p.vencimento.toIso8601String(),
    }).toList();

    // Qual desconto enviar? Depende da aba ativa
    final descontoPct = _tipo == TipoRenegociacao.avista
        ? _descontoPercentualAVista
        : _descontoPercentual;

    try {
      final result = await callFirebaseFunctionSafe(
        'renegociarDividaCallable',
        parameters: {
          'lojaId': lojaId,
          'clienteId': clienteId,
          'clienteNome': widget.divida.clienteNome,
          'parcelasIds':
              _parcelasEfetivamenteSelecionadas.map((p) => p.id).toList(),
          'observacao': _observacao.trim(),
          'tipo': _tipo.name,
          // Desconto
          'descontoPercentual': descontoPct,
          'descontoPercentualAVista': _descontoPercentualAVista,
          // Juros
          'jurosAction': _acaoJuros,
          'jurosPercentual': _novoJurosPercentual,
          // Multa
          'multaAction': _acaoMulta,
          'multaPercentual': _novaMultaPercentual,
          // Valores frontend (para auditoria/validação)
          'valorOriginalSelecionado': _totalOriginalSelecionado,
          'descontoCalculadoFrontend': _descontoCalculado,
          'jurosAplicadosFrontend': _jurosAplicadosConfig,
          'multaAplicadaFrontend': _multaAplicadaConfig,
          'novoValorFinalFrontend': _valorFinalNegociacao,
          // Parcelamento
          'qtdParcelasNovas':
              _tipo == TipoRenegociacao.parcelar ? _qtdParcelasNovas : 0,
          'entradaValor': _entradaValor,
          'primeiroVencimento': _primeiroVencimento.toIso8601String(),
          'intervaloParcelas': _intervaloParcelas,
          'cronograma': cronogramaMap,
          // Vencimento
          'novoVencimento': _tipo == TipoRenegociacao.vencimento
              ? _novoVencimento.toIso8601String()
              : null,
          'alterarTodasParcelas': _alterarTodasParcelas,
        },
        region: kFirebaseFunctionsRegion,
      );

      debugPrint('[renegociacao] Função concluída: ${result['codigo']}');
      debugPrint(
          '[renegociacao] Servidor recalculou: original=${result['valorOriginal']} final=${result['valorFinal']}');
    } on CallableHttpException catch (e) {
      debugPrint('[renegociacao] Erro da função: ${e.code} - ${e.message}');
      rethrow;
    }
  }

  // ─── Build ───

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final isMobile = w < 768;
    final maxWidth = isMobile ? w : 920.0;

    return FadeTransition(
      opacity: _fadeAnim,
      child: ScaleTransition(
        scale: _scaleAnim,
        child: Align(
          child: Container(
            constraints: BoxConstraints(
              maxWidth: maxWidth,
              maxHeight: isMobile ? double.infinity : 700,
            ),
            margin: isMobile
                ? EdgeInsets.zero
                : const EdgeInsets.symmetric(vertical: 40),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(isMobile ? 0 : 20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 40,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildHeader(isMobile),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildClienteInfo(),
                          const SizedBox(height: 16),
                          _buildResumoDivida(),
                          const SizedBox(height: 16),
                          _buildListaParcelas(),
                          const SizedBox(height: 16),
                          _buildTiposNegociacao(),
                          const SizedBox(height: 16),
                          _buildConfiguracao(),
                          const SizedBox(height: 16),
                          if (_parcelasSelecionadas.isNotEmpty) _buildSimulacaoViva(),
                          const SizedBox(height: 16),
                          _buildObservacao(),
                        ],
                      ),
                    ),
                  ),
                  _buildFooter(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(bool isMobile) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _borda, width: 0.5)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: _roxo.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.handshake_rounded, size: 24, color: _roxo),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Renegociação de Dívida',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: _texto,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Negocie débitos do cliente de forma segura mantendo todo o histórico financeiro.',
                  style: GoogleFonts.plusJakartaSans(fontSize: 12, color: _muted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.close_rounded, size: 18, color: _muted),
            ),
          ),
        ],
      ),
    );
  }

  // ─── CLIENTE INFO ───

  Widget _buildClienteInfo() {
    final cpf = ComercialClientesService.formatarCpfExibicao(widget.divida.clienteCpf);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _fundoCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _borda),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: _roxo.withValues(alpha: 0.1),
            child: Text(
              _iniciais(widget.divida.clienteNome),
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 12, fontWeight: FontWeight.w800, color: _roxo),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.divida.clienteNome,
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: _texto)),
                const SizedBox(height: 2),
                Text(
                  [if (cpf != '—') 'CPF: $cpf',
                   if (widget.divida.clienteTelefone != null && widget.divida.clienteTelefone!.isNotEmpty) 
                      widget.divida.clienteTelefone!]
                      .join(' · '),
                  style: GoogleFonts.plusJakartaSans(fontSize: 11, color: _muted),
                ),
              ],
            ),
          ),
          _buildStatusBadge(),
        ],
      ),
    );
  }

  Widget _buildStatusBadge() {
    final cor = widget.divida.status == 'vencido' ? _vermelho : _laranja;
    final label = widget.divida.statusRotulo;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cor.withValues(alpha: 0.2)),
      ),
      child: Text(
        label.toUpperCase(),
        style: GoogleFonts.plusJakartaSans(
            fontSize: 10, fontWeight: FontWeight.w800, color: cor, letterSpacing: 0.5),
      ),
    );
  }

  // ─── RESUMO DA DÍVIDA ───

  Widget _buildResumoDivida() {
    final parcelas = _parcelasAbertas;
    final primeiroVenc = parcelas.isNotEmpty ? parcelas.first.dataVencimento : null;
    final ultimoVenc = parcelas.isNotEmpty ? parcelas.last.dataVencimento : null;
    final hoje = DateTime.now();
    final diasAtraso = primeiroVenc != null && primeiroVenc.isBefore(hoje)
        ? DateTime.now().difference(primeiroVenc).inDays
        : 0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [_roxo.withValues(alpha: 0.03), _roxo.withValues(alpha: 0.08)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _roxo.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.analytics_outlined, size: 16, color: _roxo),
              const SizedBox(width: 6),
              Text('Resumo da dívida',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: _roxo)),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 16,
            runSpacing: 12,
            children: [
              _resumoMiniCard('Total em aberto', _moeda.format(_totalDividaInteira), _roxo),
              _resumoMiniCard('Total vencido',
                  _moeda.format(_totalVencidoAtual), _vermelho),
              _resumoMiniCard('Parcelas', '${parcelas.length}', _roxo),
              _resumoMiniCard('Primeiro venc.',
                  primeiroVenc != null ? _dataFmt.format(primeiroVenc) : '—', _roxo),
              _resumoMiniCard('Último venc.',
                  ultimoVenc != null ? _dataFmt.format(ultimoVenc) : '—', _roxo),
              _resumoMiniCard('Dias em atraso', '$diasAtraso', _vermelho),
              _resumoMiniCard('Juros acumul.', _moeda.format(_jurosCalculados), _laranja),
              _resumoMiniCard('Multa', _moeda.format(_multaCalculada), _laranja),
            ],
          ),
        ],
      ),
    );
  }

  Widget _resumoMiniCard(String label, String valor, Color cor) {
    return Container(
      constraints: const BoxConstraints(minWidth: 100),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _borda),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 10, fontWeight: FontWeight.w600, color: _muted)),
          const SizedBox(height: 2),
          Text(valor,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 13, fontWeight: FontWeight.w800, color: cor)),
        ],
      ),
    );
  }

  // ─── LISTA DE PARCELAS ───

  Widget _buildListaParcelas() {
    final abertas = _parcelasAbertas;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _borda),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Row(
              children: [
                Icon(Icons.receipt_long_outlined, size: 16, color: _roxo),
                const SizedBox(width: 6),
                Text('Parcelas da dívida',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: _roxo)),
                const Spacer(),
                Text(
                  '${_parcelasSelecionadas.length} de ${abertas.length} selecionadas',
                  style: GoogleFonts.plusJakartaSans(fontSize: 11, color: _muted),
                ),
                if (_parcelasSelecionadas.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => setState(() => _parcelasSelecionadas.clear()),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: _muted.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text('Limpar',
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 10, fontWeight: FontWeight.w600, color: _muted)),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const Divider(height: 1, color: _borda),
          SizedBox(
            height: 180,
            child: abertas.isEmpty
                ? _buildParcelasEmptyState()
                : ListView.separated(
                    padding: const EdgeInsets.all(8),
                    itemCount: abertas.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 4),
                    itemBuilder: (_, i) {
                      final p = abertas[i];
                      final selecionada = _parcelasSelecionadas.contains(p.id);
                      final hoje = DateTime.now();
                      final diasAtraso = p.dataVencimento.isBefore(hoje)
                          ? hoje.difference(p.dataVencimento).inDays
                          : 0;

                      return InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () {
                          setState(() {
                            if (selecionada) {
                              _parcelasSelecionadas.remove(p.id);
                            } else {
                              _parcelasSelecionadas.add(p.id);
                            }
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: selecionada
                                ? _roxo.withValues(alpha: 0.04)
                                : Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: selecionada
                                  ? _roxo.withValues(alpha: 0.2)
                                  : _borda,
                            ),
                          ),
                          child: Row(
                            children: [
                              Checkbox(
                                value: selecionada,
                                onChanged: (v) {
                                  setState(() {
                                    if (v == true) {
                                      _parcelasSelecionadas.add(p.id);
                                    } else {
                                      _parcelasSelecionadas.remove(p.id);
                                    }
                                  });
                                },
                                activeColor: _roxo,
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                                visualDensity: VisualDensity.compact,
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: _roxo.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text('#${p.numeroParcela}',
                                    style: GoogleFonts.plusJakartaSans(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: _roxo)),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Venc: ${_dataFmt.format(p.dataVencimento)}',
                                        style: GoogleFonts.plusJakartaSans(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: _texto)),
                                    Text(_moeda.format(p.valorEmAberto),
                                        style: GoogleFonts.plusJakartaSans(
                                            fontSize: 11, color: _muted)),
                                  ],
                                ),
                              ),
                              if (diasAtraso > 0)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: _vermelho.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text('${diasAtraso}d',
                                      style: GoogleFonts.plusJakartaSans(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                          color: _vermelho)),
                                )
                              else
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: _verde.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text('OK',
                                      style: GoogleFonts.plusJakartaSans(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                          color: _verde)),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  /// Estado vazio da lista de parcelas com diagnóstico.
  Widget _buildParcelasEmptyState() {
    final total = _parcelasLocais.length;
    final renegociadas = _parcelasLocais
        .where((p) => p.status.toLowerCase() == 'renegociado').toList();
    final pagas = _parcelasLocais
        .where((p) => p.status.toLowerCase() == 'pago').length;
    final outas = _parcelasLocais
        .where((p) => p.status.toLowerCase() != 'renegociado' &&
            p.status.toLowerCase() != 'pago').length;

    // Códigos de renegociação únicos
    final codigosReneg = renegociadas
        .map((p) => p.renegociadoCodigo)
        .where((c) => c != null && c.isNotEmpty)
        .toSet()
        .cast<String>()
        .toList();

    String? motivo;
    if (renegociadas.length == total) {
      motivo = 'Todas as parcelas deste cliente já foram renegociadas.';
    } else if (pagas == total) {
      motivo = 'Todas as parcelas deste cliente já foram pagas.';
    } else if (outas > 0 && outas == total) {
      motivo = 'Nenhuma parcela possui valor em aberto.';
    } else {
      motivo = 'Nenhuma parcela disponível para renegociação.';
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.info_outline_rounded, size: 28, color: _roxo.withValues(alpha: 0.4)),
            const SizedBox(height: 8),
            Text(motivo,
                textAlign: TextAlign.center,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 12, color: _muted, fontWeight: FontWeight.w500)),
            const SizedBox(height: 4),
            Text('Total: $total parcelas · ${renegociadas.length} renegociadas · $pagas pagas',
                textAlign: TextAlign.center,
                style: GoogleFonts.plusJakartaSans(fontSize: 10, color: _muted.withValues(alpha: 0.6))),
            if (codigosReneg.isNotEmpty) ...[
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => _confirmarReverter(
                        codigosReneg.length == 1 ? codigosReneg.first : null),
                    icon: Icon(Icons.undo_rounded, size: 16, color: _laranja),
                    label: Text(codigosReneg.length == 1
                        ? 'Reverter renegociação'
                        : 'Reverter renegociações',
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 12, fontWeight: FontWeight.w700, color: _laranja)),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: _laranja.withValues(alpha: 0.4)),
                      foregroundColor: _laranja,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                      elevation: 0,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _confirmarReverter(String? codigoReneg) async {
    final confirmado = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        backgroundColor: Colors.transparent,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        colors: [Color(0xFFFF8F00), Color(0xFFF57C00)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFFF8F00).withValues(alpha: 0.3),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Icon(Icons.undo_rounded, color: Colors.white, size: 34),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Reverter renegociação',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF1E1B4B),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    codigoReneg != null
                        ? 'As parcelas serão restauradas ao estado anterior (em aberto) e os registros da renegociação serão removidos.'
                        : 'Todas as renegociações deste cliente serão revertidas, restaurando as parcelas ao estado anterior.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      height: 1.5,
                      color: PainelAdminTheme.textoSecundario,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            side: const BorderSide(color: Color(0xFFE2E8F0)),
                          ),
                          child: Text('Cancelar',
                              style: GoogleFonts.plusJakartaSans(
                                  fontWeight: FontWeight.w700, fontSize: 14)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () => Navigator.pop(ctx, true),
                          icon: const Icon(Icons.undo_rounded, size: 16),
                          label: Text('Reverter',
                              style: GoogleFonts.plusJakartaSans(
                                  fontWeight: FontWeight.w700, fontSize: 14)),
                          style: FilledButton.styleFrom(
                            backgroundColor: _laranja,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 0,
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
      ),
    );
    if (confirmado != true || !mounted) return;

    final lojaId = widget.lojaId;
    final clienteId = widget.divida.clienteId;

    showDialog(
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        child: Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 32,
                  height: 32,
                  child: CircularProgressIndicator(strokeWidth: 3),
                ),
                const SizedBox(height: 16),
                Text(
                  'Revertendo...',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF1E1B4B),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      final functions = FirebaseFunctions.instanceFor(
        region: kFirebaseFunctionsRegion,
      );
      final result = await functions
          .httpsCallable('reverterRenegociacaoCallable')
          .call({
        'lojaId': lojaId,
        'clienteId': clienteId,
        'codigoReneg': codigoReneg,
      });
      final resultData = result.data;
      final revertidas = (resultData is Map ? resultData['parcelasRevertidas'] : 0) ?? 0;

      // Fecha loading
      Navigator.pop(context);
      if (!mounted) return;

      // Diálogo de sucesso premium
      await showDialog(
        context: context,
        barrierDismissible: false,
        barrierColor: Colors.black.withValues(alpha: 0.55),
        builder: (ctx) => Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
          backgroundColor: Colors.transparent,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              clipBehavior: Clip.antiAlias,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 36),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(
                          colors: [Color(0xFF10B981), Color(0xFF059669)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF10B981).withValues(alpha: 0.3),
                            blurRadius: 16,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Icon(Icons.check_rounded, color: Colors.white, size: 34),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Renegociação Revertida!',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF1E1B4B),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '$revertidas parcela(s) foram restauradas ao estado anterior com sucesso.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        height: 1.5,
                        color: PainelAdminTheme.textoSecundario,
                      ),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () => Navigator.pop(ctx),
                        style: FilledButton.styleFrom(
                          backgroundColor: PainelAdminTheme.roxo,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text('Fechar',
                            style: GoogleFonts.plusJakartaSans(
                                fontWeight: FontWeight.w700, fontSize: 14)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

      if (!mounted) return;
      // Fecha o modal de renegociação inteiro
      // Ao reabrir, os dados virão frescos do Firestore
      Navigator.of(context).pop();
    } catch (e) {
      // Fecha loading
      Navigator.pop(context);
      if (!mounted) return;

      // Diálogo de erro premium
      await showDialog(
        context: context,
        barrierDismissible: false,
        barrierColor: Colors.black.withValues(alpha: 0.55),
        builder: (ctx) => Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
          backgroundColor: Colors.transparent,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              clipBehavior: Clip.antiAlias,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 36),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(
                          colors: [Color(0xFFEF4444), Color(0xFFDC2626)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFEF4444).withValues(alpha: 0.3),
                            blurRadius: 16,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Icon(Icons.close_rounded, color: Colors.white, size: 34),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Erro ao Reverter',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF1E1B4B),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF2F2),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFFEE2E2)),
                      ),
                      child: Text(
                        e.toString(),
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          height: 1.45,
                          color: const Color(0xFF991B1B),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () => Navigator.pop(ctx),
                        style: FilledButton.styleFrom(
                          backgroundColor: PainelAdminTheme.roxo,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text('Fechar',
                            style: GoogleFonts.plusJakartaSans(
                                fontWeight: FontWeight.w700, fontSize: 14)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }
  }

  // ─── TIPOS DE NEGOCIAÇÃO ───

  Widget _buildTiposNegociacao() {
    final tipos = TipoRenegociacao.values;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.category_outlined, size: 16, color: _roxo),
            const SizedBox(width: 6),
            Text('Tipo de renegociação',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: _roxo)),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: tipos.map((t) {
            final ativo = _tipo == t;
            return InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () {
                setState(() {
                  _limparEstadoAoTrocarTipo(t);
                  _tipo = t;
                });
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: ativo
                      ? _roxo.withValues(alpha: 0.08)
                      : _fundoCard,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: ativo
                        ? _roxo.withValues(alpha: 0.3)
                        : _borda,
                    width: ativo ? 1.5 : 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(t.icone,
                        size: 16,
                        color: ativo ? _roxo : _muted),
                    const SizedBox(width: 6),
                    Text(
                      t.rotulo,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        fontWeight: ativo ? FontWeight.w700 : FontWeight.w500,
                        color: ativo ? _roxo : _muted,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  // ─── CONFIGURAÇÃO POR TIPO ───

  Widget _buildConfiguracao() {
    if (_parcelasSelecionadas.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: _fundoCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _borda),
        ),
        child: Center(
          child: Column(
            children: [
              Icon(Icons.touch_app_rounded, size: 32, color: _muted),
              const SizedBox(height: 8),
              Text('Selecione as parcelas para iniciar a negociação',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 13, color: _muted)),
            ],
          ),
        ),
      );
    }
    switch (_tipo) {
      case TipoRenegociacao.avista:
        return _configAVista();
      case TipoRenegociacao.parcelar:
        return _configParcelar();
      case TipoRenegociacao.vencimento:
        return _configVencimento();
      case TipoRenegociacao.desconto:
        return _configDesconto();
      case TipoRenegociacao.isentarJuros:
        return _configJuros();
      case TipoRenegociacao.isentarMulta:
        return _configMulta();
      case TipoRenegociacao.personalizada:
        return _configPersonalizada();
    }
  }

  Widget _sectionHeader(String titulo, IconData icone) {
    return Row(
      children: [
        Icon(icone, size: 16, color: _roxo),
        const SizedBox(width: 6),
        Text(titulo,
            style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: _roxo)),
      ],
    );
  }

  // 1. À VISTA
  Widget _configAVista() {
    return _buildConfigCard(
      children: [
        _sectionHeader('Pagamento à vista', Icons.money_rounded),
        const SizedBox(height: 12),
        _infoCampo('Valor original das parcelas selecionadas',
            _moeda.format(_totalOriginalSelecionado)),
        const SizedBox(height: 12),
        _infoCampo('Juros acumulados',
            _moeda.format(_jurosCalculados)),
        const SizedBox(height: 4),
        _infoCampo('Multa acumulada',
            _moeda.format(_multaCalculada)),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Desconto (%)',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: _texto)),
                  const SizedBox(height: 4),
                  TextField(
                    controller: _descPercentualAVistaCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onChanged: (v) => _aplicarMascaraPercentual(
                        _descPercentualAVistaCtrl, (val) {
                      setState(() => _descontoPercentualAVista = val);
                    }),
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 20, fontWeight: FontWeight.w700),
                    decoration: _inputDec(hint: '0%'),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _verde.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _verde.withValues(alpha: 0.15)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Valor final à vista',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: _muted)),
              Text(_moeda.format(_valorFinalNegociacao),
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: _verde)),
            ],
          ),
        ),
      ],
    );
  }

  // 2. PARCELAR
  Widget _configParcelar() {
    return _buildConfigCard(
      children: [
        _sectionHeader('Parcelar dívida', Icons.calendar_view_month_rounded),
        const SizedBox(height: 12),
        _infoCampo('Valor a parcelar', _moeda.format(_totalOriginalSelecionado)),
        const SizedBox(height: 12),
        Wrap(
          spacing: 16,
          runSpacing: 12,
          children: [
            _campoNumerico('Qtd. parcelas', _qtdParcelasNovas.toString(), (v) {
              final n = int.tryParse(v);
              if (n != null && n > 0 && n <= 48) {
                setState(() => _qtdParcelasNovas = n);
              }
            }),
            _campoMoeda('Valor entrada', _entradaCtrl, (v) {
              setState(() => _entradaValor = v);
            }),
            _campoData('1º vencimento', _primeiroVencimento, () async {
              final date = await showDatePicker(
                context: context,
                initialDate: _primeiroVencimento,
                firstDate: DateTime.now(),
                lastDate: DateTime.now().add(const Duration(days: 730)),
                locale: const Locale('pt', 'BR'),
              );
              if (date != null) setState(() => _primeiroVencimento = date);
            }),
            DropdownButtonFormField<String>(
              value: _intervaloParcelas,
              decoration: _inputDec(label: 'Intervalo'),
              items: ['Mensal', 'Quinzenal', 'Semanal']
                  .map((l) => DropdownMenuItem(value: l, child: Text(l)))
                  .toList(),
              onChanged: (v) => setState(() => _intervaloParcelas = v ?? 'Mensal'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _roxo.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _roxo.withValues(alpha: 0.12)),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Icon(Icons.calendar_month_rounded, size: 14, color: _roxo),
                  const SizedBox(width: 4),
                  Text('Cronograma',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: _roxo)),
                ],
              ),
              const SizedBox(height: 8),
              if (_cronogramaNovo.isEmpty)
                Text('Preencha os campos acima',
                    style: GoogleFonts.plusJakartaSans(fontSize: 11, color: _muted))
              else
                for (final p in _cronogramaNovo)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: _roxo.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            p.numero == 0 ? 'Entrada' : '#${p.numero}',
                            style: GoogleFonts.plusJakartaSans(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: _roxo),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(_dataFmt.format(p.vencimento),
                            style: GoogleFonts.plusJakartaSans(
                                fontSize: 11, color: _muted)),
                        const Spacer(),
                        Text(_moeda.format(p.valor),
                            style: GoogleFonts.plusJakartaSans(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: _texto)),
                      ],
                    ),
                  ),
            ],
          ),
        ),
      ],
    );
  }

  // 3. ALTERAR VENCIMENTO
  Widget _configVencimento() {
    final abertas = _parcelasAbertas;
    return _buildConfigCard(
      children: [
        _sectionHeader('Alterar vencimento', Icons.date_range_rounded),
        const SizedBox(height: 12),
        Text(
          'As ${_parcelasSelecionadas.length} parcela(s) selecionada(s) '
          'terão o vencimento alterado.',
          style: GoogleFonts.plusJakartaSans(fontSize: 12, color: _muted),
        ),
        const SizedBox(height: 12),
        SwitchListTile.adaptive(
          title: Text('Alterar todas as parcelas selecionadas',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 13, fontWeight: FontWeight.w600)),
          value: _alterarTodasParcelas,
          onChanged: (v) => setState(() => _alterarTodasParcelas = v),
          activeColor: _roxo,
          contentPadding: EdgeInsets.zero,
        ),
        if (!_alterarTodasParcelas && abertas.isNotEmpty)
          DropdownButtonFormField<int>(
            value: _parcelaAlvoIndex < abertas.length ? _parcelaAlvoIndex : 0,
            decoration: _inputDec(label: 'Parcela'),
            items: _parcelasEfetivamenteSelecionadas.asMap().entries.map((e) {
              return DropdownMenuItem(
                value: e.key,
                child: Text(
                    '#${e.value.numeroParcela} - ${_dataFmt.format(e.value.dataVencimento)}'),
              );
            }).toList(),
            onChanged: (v) => setState(() => _parcelaAlvoIndex = v ?? 0),
          ),
        const SizedBox(height: 12),
        _campoData('Novo vencimento', _novoVencimento, () async {
          final date = await showDatePicker(
            context: context,
            initialDate: _novoVencimento,
            firstDate: DateTime.now(),
            lastDate: DateTime.now().add(const Duration(days: 730)),
            locale: const Locale('pt', 'BR'),
          );
          if (date != null) setState(() => _novoVencimento = date);
        }),
      ],
    );
  }

  // 4. DESCONTO (apenas %)
  Widget _configDesconto() {
    final descValor = _descontoCalculado;
    final novoValor = _valorFinalNegociacao;
    final base = _totalOriginalSelecionado + _jurosCalculados + _multaCalculada;

    return _buildConfigCard(
      children: [
        _sectionHeader('Aplicar desconto', Icons.discount_rounded),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Desconto (%)',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: _texto)),
                  const SizedBox(height: 4),
                  TextField(
                    controller: _descPercentualCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onChanged: (v) => _aplicarMascaraPercentual(
                        _descPercentualCtrl, (val) {
                      setState(() => _descontoPercentual = val);
                    }),
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 20, fontWeight: FontWeight.w700),
                    decoration: _inputDec(hint: '0%'),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _linhaResumo('Valor base', _moeda.format(base)),
        _linhaResumo('Desconto', _moeda.format(descValor), cor: _vermelho),
        const Divider(height: 16),
        _linhaResumo('Novo valor', _moeda.format(novoValor), cor: _verde, bold: true),
      ],
    );
  }

  // 5. JUROS
  Widget _configJuros() {
    final original = _jurosCalculados;
    final aplicado = _jurosAplicadosConfig;

    String? detalhe;
    if (_acaoJuros == 'reduzir' && _novoJurosPercentual > 0 && original > 0) {
      final reducao = _round(original * (_novoJurosPercentual / 100));
      detalhe = 'Redução: ${_novoJurosPercentual.toStringAsFixed(0)}% de ${_moeda.format(original)} = ${_moeda.format(reducao)}';
    } else if (_acaoJuros == 'novo' && _novoJurosPercentual > 0) {
      final aplicadoCalculado = _round(_totalOriginalSelecionado * (_novoJurosPercentual / 100));
      detalhe = '${_novoJurosPercentual.toStringAsFixed(0)}% × ${_moeda.format(_totalOriginalSelecionado)} = ${_moeda.format(aplicadoCalculado)}';
    }

    return _buildConfigCard(
      children: [
        _sectionHeader('Configurar juros', Icons.monetization_on_outlined),
        const SizedBox(height: 8),
        _infoCampo('Juros originais das parcelas selecionadas',
            _moeda.format(original)),
        const SizedBox(height: 12),
        _acaoRadioGroup('acao_juros', _acaoJuros, [
          ('manter', 'Manter juros originais (${_moeda.format(original)})'),
          ('remover', 'Isentar juros (remover todos)'),
          ('reduzir', 'Reduzir juros'),
          ('novo', 'Aplicar novos juros'),
        ], (v) {
          setState(() {
            _acaoJuros = v ?? 'manter';
            _novoJurosPercentual = 0;
            _jurosCtrl.clear();
          });
        }),
        if (_acaoJuros == 'reduzir' || _acaoJuros == 'novo') ...[
          const SizedBox(height: 12),
          TextField(
            controller: _jurosCtrl,
            keyboardType: TextInputType.number,
            decoration: _inputDec(
                label: _acaoJuros == 'reduzir'
                    ? 'Percentual a reduzir (%)'
                    : 'Novo percentual de juros (%)'),
            onChanged: (v) {
              final text = v.replaceAll(RegExp(r'[^0-9]'), '');
              final pct = double.tryParse(text);
              setState(() => _novoJurosPercentual = (pct != null && pct >= 0 && pct <= 100) ? pct : 0);
            },
          ),
        ],
        if (_acaoJuros != 'manter') ...[
          const SizedBox(height: 8),
          const Divider(height: 1),
          const SizedBox(height: 8),
          if (_acaoJuros == 'remover')
            _infoCampo('Situação', 'Juros removidos — valor final: R\$ 0,00'),
          if (_acaoJuros == 'reduzir') ...[
            if (original > 0) ...[
              if (detalhe != null)
                _infoCampo('Detalhe', detalhe),
              _linhaResumo('Juros após redução', _moeda.format(aplicado),
                  cor: _laranja, bold: true),
            ] else
              _infoCampo('Aviso',
                  'Não há juros originais para reduzir. Use "Aplicar novos juros".'),
          ],
          if (_acaoJuros == 'novo') ...[
            if (_novoJurosPercentual > 0) ...[
              if (detalhe != null)
                _infoCampo('Detalhe', detalhe),
              _linhaResumo('Novos juros aplicados', _moeda.format(aplicado),
                  cor: _laranja, bold: true),
            ] else
              _infoCampo('Aviso', 'Digite o percentual para calcular os novos juros.'),
          ],
        ],
      ],
    );
  }

  // 6. MULTA
  Widget _configMulta() {
    final original = _multaCalculada;
    final aplicado = _multaAplicadaConfig;

    String? detalhe;
    if (_acaoMulta == 'reduzir' && _novaMultaPercentual > 0 && original > 0) {
      final reducao = _round(original * (_novaMultaPercentual / 100));
      detalhe = 'Redução: ${_novaMultaPercentual.toStringAsFixed(0)}% de ${_moeda.format(original)} = ${_moeda.format(reducao)}';
    } else if (_acaoMulta == 'personalizada' && _novaMultaPercentual > 0) {
      final aplicadoCalculado = _round(_totalOriginalSelecionado * (_novaMultaPercentual / 100));
      detalhe = '${_novaMultaPercentual.toStringAsFixed(0)}% × ${_moeda.format(_totalOriginalSelecionado)} = ${_moeda.format(aplicadoCalculado)}';
    }

    return _buildConfigCard(
      children: [
        _sectionHeader('Configurar multa', Icons.gpp_bad_outlined),
        const SizedBox(height: 8),
        _infoCampo('Multa original das parcelas selecionadas',
            _moeda.format(original)),
        const SizedBox(height: 12),
        _acaoRadioGroup('acao_multa', _acaoMulta, [
          ('manter', 'Manter multa original (${_moeda.format(original)})'),
          ('remover', 'Isentar multa (remover)'),
          ('reduzir', 'Reduzir multa'),
          ('personalizada', 'Aplicar nova multa'),
        ], (v) {
          setState(() {
            _acaoMulta = v ?? 'manter';
            _novaMultaPercentual = 0;
            _multaCtrl.clear();
          });
        }),
        if (_acaoMulta == 'reduzir' || _acaoMulta == 'personalizada') ...[
          const SizedBox(height: 12),
          TextField(
            controller: _multaCtrl,
            keyboardType: TextInputType.number,
            decoration: _inputDec(
                label: _acaoMulta == 'reduzir'
                    ? 'Percentual a reduzir (%)'
                    : 'Novo percentual de multa (%)'),
            onChanged: (v) {
              final text = v.replaceAll(RegExp(r'[^0-9]'), '');
              final pct = double.tryParse(text);
              setState(() => _novaMultaPercentual = (pct != null && pct >= 0 && pct <= 100) ? pct : 0);
            },
          ),
        ],
        if (_acaoMulta != 'manter') ...[
          const SizedBox(height: 8),
          const Divider(height: 1),
          const SizedBox(height: 8),
          if (_acaoMulta == 'remover')
            _infoCampo('Situação', 'Multa removida — valor final: R\$ 0,00'),
          if (_acaoMulta == 'reduzir') ...[
            if (original > 0) ...[
              if (detalhe != null)
                _infoCampo('Detalhe', detalhe),
              _linhaResumo('Multa após redução', _moeda.format(aplicado),
                  cor: _laranja, bold: true),
            ] else
              _infoCampo('Aviso',
                  'Não há multa original para reduzir. Use "Aplicar nova multa".'),
          ],
          if (_acaoMulta == 'personalizada') ...[
            if (_novaMultaPercentual > 0) ...[
              if (detalhe != null)
                _infoCampo('Detalhe', detalhe),
              _linhaResumo('Nova multa aplicada', _moeda.format(aplicado),
                  cor: _laranja, bold: true),
            ] else
              _infoCampo('Aviso', 'Digite o percentual para calcular a nova multa.'),
          ],
        ],
      ],
    );
  }

  // 7. PERSONALIZADA
  Widget _configPersonalizada() {
    return _buildConfigCard(
      children: [
        _sectionHeader('Renegociação personalizada', Icons.tune_rounded),
        const SizedBox(height: 8),
        Text(
          'Configure os juros, multa e desconto manualmente usando as abas '
          'Isentar juros, Isentar multa e Aplicar desconto.',
          style: GoogleFonts.plusJakartaSans(fontSize: 12, color: _muted),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _roxo.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              _linhaResumo('Valor original selecionado',
                  _moeda.format(_totalOriginalSelecionado)),
              _linhaResumo('Juros', _moeda.format(_jurosAplicadosConfig),
                  cor: _laranja),
              _linhaResumo('Multa', _moeda.format(_multaAplicadaConfig),
                  cor: _laranja),
              _linhaResumo('Desconto', _moeda.format(_descontoCalculado),
                  cor: _vermelho),
              const Divider(height: 12),
              _linhaResumo('Valor final', _moeda.format(_valorFinalNegociacao),
                  cor: _verde, bold: true),
            ],
          ),
        ),
      ],
    );
  }

  // ─── SIMULAÇÃO EM TEMPO REAL ───

  Widget _buildSimulacaoViva() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _verde.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _verde.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.visibility_rounded, size: 16, color: _verde),
              const SizedBox(width: 6),
              Text('Simulação em tempo real',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: _verde)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _verde.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(_tipo.rotulo,
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: _verde)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _linhaResumo('Valor original (${_parcelasSelecionadas.length} parcelas)',
              _moeda.format(_totalOriginalSelecionado)),
          // Mostra juros sempre que houver configuração na aba ativa
          if (_tipo == TipoRenegociacao.isentarJuros ||
              _tipo == TipoRenegociacao.isentarMulta ||
              _tipo == TipoRenegociacao.personalizada ||
              _jurosAplicadosConfig > 0)
            _linhaResumo('Juros', _moeda.format(_jurosAplicadosConfig),
                cor: _laranja),
          if (_tipo == TipoRenegociacao.isentarMulta ||
              _tipo == TipoRenegociacao.isentarJuros ||
              _tipo == TipoRenegociacao.personalizada ||
              _multaAplicadaConfig > 0)
            _linhaResumo('Multa', _moeda.format(_multaAplicadaConfig),
                cor: _laranja),
          if (_descontoCalculado > 0)
            _linhaResumo('Desconto', _moeda.format(_descontoCalculado),
                cor: _vermelho),
          const Divider(height: 16),
          _linhaResumo('Novo valor', _moeda.format(_valorFinalNegociacao),
              cor: _verde, bold: true),
          if (_tipo == TipoRenegociacao.parcelar && _cronogramaNovo.isNotEmpty) ...[
            const SizedBox(height: 8),
            _linhaResumo('Quantidade de parcelas', '${_qtdParcelasNovas}'),
            _linhaResumo('Valor por parcela', _moeda.format(_valorParcelaNova)),
            const SizedBox(height: 8),
            Text('Novo cronograma:',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: _texto)),
            const SizedBox(height: 4),
            for (final p in _cronogramaNovo)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: _verde.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        p.numero == 0 ? 'Entrada' : '#${p.numero}',
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: _verde),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(_dataFmt.format(p.vencimento),
                        style: GoogleFonts.plusJakartaSans(fontSize: 11, color: _muted)),
                    const Spacer(),
                    Text(_moeda.format(p.valor),
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 12, fontWeight: FontWeight.w700, color: _texto)),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }

  // ─── OBSERVAÇÃO ───

  Widget _buildObservacao() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Observação *',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _texto)),
            const SizedBox(width: 4),
            Text('(mín. 5 caracteres)',
                style: GoogleFonts.plusJakartaSans(fontSize: 10, color: _muted)),
          ],
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _obsCtrl,
          maxLines: 2,
          onChanged: (v) => setState(() => _observacao = v),
          decoration: _inputDec(
            hint: 'Ex: Cliente perdeu emprego, Acordo administrativo...',
          ),
        ),
      ],
    );
  }

  // ─── FOOTER ───

  Widget _buildFooter() {
    final pode = _podeConfirmar;
    final msg = _mensagemValidacao;

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: _borda, width: 0.5)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (msg != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded, size: 14, color: _laranja),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(msg,
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: _laranja)),
                  ),
                ],
              ),
            ),
          Row(
            children: [
              OutlinedButton(
                onPressed: _salvando ? null : () => Navigator.pop(context),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _muted,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: const BorderSide(color: _borda),
                  ),
                ),
                child: Text('Cancelar',
                    style: GoogleFonts.plusJakartaSans(
                        fontWeight: FontWeight.w700, fontSize: 14)),
              ),
              const Spacer(),
              // Botão Efetuar pagamento (laranja, só aparece com parcelas selecionadas)
              if (_parcelasSelecionadas.isNotEmpty) ...[
                OutlinedButton.icon(
                  onPressed: _salvando ? null : () => _mostrarPagamentoCrediario(),
                  icon: Icon(Icons.payments_rounded, size: 16, color: const Color(0xFF059669)),
                  label: Text(
                    'Efetuar pagamento',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 12, fontWeight: FontWeight.w700, color: const Color(0xFF059669)),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: const Color(0xFF059669).withValues(alpha: 0.4)),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                ),
                const SizedBox(width: 10),
              ],
              FilledButton.icon(
                onPressed: _salvando || !pode
                    ? null
                    : _confirmarRenegociacao,
                icon: _salvando
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.check_circle_outline, size: 18),
                label: Text(
                    _salvando ? 'Salvando...' : 'Confirmar renegociação',
                    style: GoogleFonts.plusJakartaSans(
                        fontWeight: FontWeight.w700, fontSize: 14)),
                style: FilledButton.styleFrom(
                  backgroundColor: _roxo,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: _roxo.withValues(alpha: 0.3),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─── HELPERS DE UI ───

  Widget _buildConfigCard({required List<Widget> children}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _borda),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }

  Widget _infoCampo(String label, String valor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: GoogleFonts.plusJakartaSans(
                fontSize: 11, fontWeight: FontWeight.w600, color: _muted)),
        const SizedBox(height: 4),
        Text(valor,
            style: GoogleFonts.plusJakartaSans(
                fontSize: 14, fontWeight: FontWeight.w700, color: _texto)),
      ],
    );
  }

  Widget _linhaResumo(String label, String valor,
      {Color? cor, bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style:
                  GoogleFonts.plusJakartaSans(fontSize: 12, color: _muted)),
          Text(valor,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
                  color: cor ?? _texto)),
        ],
      ),
    );
  }

  Widget _campoNumerico(
      String label, String valor, ValueChanged<String> onChange) {
    return SizedBox(
      width: 140,
      child: TextField(
        decoration: _inputDec(label: label),
        keyboardType: TextInputType.number,
        controller: TextEditingController(text: valor),
        onChanged: onChange,
        style: GoogleFonts.plusJakartaSans(
            fontSize: 14, fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _campoMoeda(String label, TextEditingController ctrl,
      ValueChanged<double> onChange) {
    return SizedBox(
      width: 160,
      child: TextField(
        decoration: _inputDec(label: label),
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        controller: ctrl,
        onChanged: (v) => _aplicarMascaraMoeda(ctrl, onChange),
        style: GoogleFonts.plusJakartaSans(
            fontSize: 14, fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _campoData(String label, DateTime data, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: InputDecorator(
        decoration: _inputDec(label: label),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.calendar_today_rounded, size: 14, color: _muted),
            const SizedBox(width: 6),
            Text(_dataFmt.format(data),
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 14, fontWeight: FontWeight.w600, color: _texto)),
          ],
        ),
      ),
    );
  }

  Widget _acaoRadioGroup(
      String group, String atual, List<(String, String)> opcoes,
      ValueChanged<String?> onChanged) {
    return Column(
      children: opcoes.map((o) {
        return RadioListTile<String>(
          value: o.$1,
          groupValue: atual,
          onChanged: onChanged,
          title: Text(o.$2,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 12, fontWeight: FontWeight.w500)),
          activeColor: _roxo,
          dense: true,
          contentPadding: EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
        );
      }).toList(),
    );
  }

  InputDecoration _inputDec({String? label, String? hint}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      hintStyle: GoogleFonts.plusJakartaSans(
          fontSize: 13, color: const Color(0xFF9CA3AF)),
      filled: true,
      fillColor: _fundoCard,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: _borda),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: _borda),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: _roxo, width: 1.5),
      ),
      labelStyle: GoogleFonts.plusJakartaSans(
          fontSize: 12, fontWeight: FontWeight.w600, color: _muted),
    );
  }

  String _iniciais(String nome) {
    final p = nome.trim().split(' ');
    if (p.length >= 2) {
      return (p[0].substring(0, 1) + p[1].substring(0, 1)).toUpperCase();
    }
    if (nome.length >= 2) return nome.substring(0, 2).toUpperCase();
    return nome.isNotEmpty ? nome[0].toUpperCase() : '?';
  }
}

// =============================================================================
// MODAL DE CONFIRMAÇÃO
// =============================================================================

class _ConfirmarRenegociacaoModal extends StatelessWidget {
  _ConfirmarRenegociacaoModal({
    required this.clienteNome,
    required this.valorOriginal,
    required this.novoValor,
    required this.desconto,
    required this.juros,
    required this.multa,
    required this.tipo,
    required this.qtdParcelas,
    required this.valorParcela,
    required this.cronograma,
    required this.observacao,
    required this.usuarioNome,
  });

  final String clienteNome;
  final double valorOriginal;
  final double novoValor;
  final double desconto;
  final double juros;
  final double multa;
  final TipoRenegociacao tipo;
  final int qtdParcelas;
  final double valorParcela;
  final List<_ParcelaSimulada> cronograma;
  final String observacao;
  final String? usuarioNome;

  final _moeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
  final _dataFmt = DateFormat('dd/MM/yyyy', 'pt_BR');

  static const _roxo = PainelAdminTheme.roxo;
  static const _laranja = PainelAdminTheme.laranja;
  static const _texto = Color(0xFF1E1B4B);
  static const _muted = Color(0xFF64748B);
  static const _verde = Color(0xFF16A34A);
  static const _vermelho = Color(0xFFDC2626);
  static const _borda = Color(0xFFE2E8F0);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      contentPadding: EdgeInsets.zero,
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _alertBox(),
                    const SizedBox(height: 16),
                    _summaryBox(),
                    if (observacao.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _obsBox(),
                    ],
                  ],
                ),
              ),
            ),
            _footer(context),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _borda, width: 0.5)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: _verde.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.check_circle_outline_rounded,
                size: 24, color: _verde),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Confirmar renegociação',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: _texto)),
              Text('Você confirma esta renegociação?',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 12, color: _muted)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _alertBox() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _roxo.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _roxo.withValues(alpha: 0.12)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, size: 18, color: _roxo),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Ao confirmar, as parcelas selecionadas serão marcadas como '
              'renegociadas e uma nova negociação do tipo "${tipo.rotulo}" '
              'será registrada. O histórico original será preservado.',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 12, color: _texto, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryBox() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _borda),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: _roxo.withValues(alpha: 0.1),
                child: Text(
                  clienteNome.isNotEmpty ? clienteNome[0].toUpperCase() : '?',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: _roxo),
                ),
              ),
              const SizedBox(width: 8),
              Text(clienteNome,
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: _texto)),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(height: 1),
          const SizedBox(height: 14),
          _row('Valor original', _moeda.format(valorOriginal)),
          if (desconto > 0)
            _row('Desconto', _moeda.format(desconto), cor: _vermelho),
          if (juros > 0) _row('Juros', _moeda.format(juros), cor: _laranja),
          if (multa > 0) _row('Multa', _moeda.format(multa), cor: _laranja),
          const Divider(height: 16),
          _row('Novo valor', _moeda.format(novoValor), cor: _verde, bold: true),
          const SizedBox(height: 8),
          if (tipo == TipoRenegociacao.parcelar) ...[
            _row('Quantidade de parcelas', '$qtdParcelas'),
            _row('Valor de cada parcela', _moeda.format(valorParcela)),
            const SizedBox(height: 8),
            Text('Novo cronograma:',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: _muted)),
            const SizedBox(height: 4),
            for (final p in cronograma)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 1),
                child: Text(
                  '  ${p.numero == 0 ? 'Entrada' : 'Parcela ${p.numero}'}: '
                  '${_moeda.format(p.valor)} em ${_dataFmt.format(p.vencimento)}',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 11, color: _muted),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _obsBox() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _borda),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.notes_rounded, size: 14, color: _muted),
          const SizedBox(width: 6),
          Expanded(
            child: Text(observacao,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 12, color: _texto, fontStyle: FontStyle.italic)),
          ),
        ],
      ),
    );
  }

  Widget _row(String label, String valor, {Color? cor, bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: GoogleFonts.plusJakartaSans(fontSize: 12, color: _muted)),
          Text(valor,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
                  color: cor ?? _texto)),
        ],
      ),
    );
  }

  Widget _footer(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: _borda, width: 0.5)),
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => Navigator.pop(context, false),
              style: OutlinedButton.styleFrom(
                foregroundColor: _muted,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: const BorderSide(color: _borda),
                ),
              ),
              child: Text('Voltar',
                  style: GoogleFonts.plusJakartaSans(
                      fontWeight: FontWeight.w700, fontSize: 14)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: FilledButton(
              onPressed: () => Navigator.pop(context, true),
              style: FilledButton.styleFrom(
                backgroundColor: _roxo,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
              child: Text('Confirmar',
                  style: GoogleFonts.plusJakartaSans(
                      fontWeight: FontWeight.w700, fontSize: 14)),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════
// MODAL DE PAGAMENTO CREDIÁRIO
// ═══════════════════════════════════════════

enum _FormaPagamentoCrediario { dinheiro, pix, cartaoCredito, cartaoDebito }

/// Modal premium para efetuar pagamento de parcelas do crediário.
class _PagamentoCrediarioModal extends StatefulWidget {
  const _PagamentoCrediarioModal({
    required this.lojaId,
    required this.clienteId,
    required this.clienteNome,
    required this.clienteCpf,
    required this.parcelas,
    required this.configJuros,
    required this.usuarioNome,
  });

  final String lojaId;
  final String clienteId;
  final String clienteNome;
  final String? clienteCpf;
  final List<ComercialParcelaCliente> parcelas;
  final JurosMultaConfig configJuros;
  final String usuarioNome;

  @override
  State<_PagamentoCrediarioModal> createState() =>
      _PagamentoCrediarioModalState();
}

class _PagamentoCrediarioModalState
    extends State<_PagamentoCrediarioModal> {
  // ─── Cores ───
  static const _roxo = Color(0xFF6A1B9A);
  static const _laranja = Color(0xFFFF8F00);
  static const _texto = Color(0xFF1A1A2E);
  static const _muted = Color(0xFF64748B);
  static const _borda = Color(0xFFE2E8F0);
  static const _fundoCard = Color(0xFFFAFAFE);

  // ─── Controllers ───
  final _moeda = NumberFormat.currency(symbol: 'R\$', decimalDigits: 2);

  // ─── Estado ───
  _FormaPagamentoCrediario _forma = _FormaPagamentoCrediario.dinheiro;
  bool _salvando = false;

  // Dinheiro
  final _dinheiroCtl = TextEditingController();
  double _troco = 0;

  // Pix
  String _pixCopiaCola = '';
  String _pixQrCodeBase64 = '';
  String _pixTransacaoId = '';
  bool _pixGerado = false;
  bool _pixCarregando = false;
  String _pixStatus = ''; // 'aguardando' | 'expirado' | 'confirmado'
  Timer? _pixPollTimer;
  Timer? _pixCountdownTimer;
  int _pixSegundosRestantes = 300; // 5 minutos em segundos
  bool _pixExpirado = false;

  /// Segundos desde a criação da cobrança (compatível web: ms/iso/map Timestamp).
  int _segundosDesdeCriacaoPix(Map<String, dynamic> data) {
    final agoraMs = DateTime.now().millisecondsSinceEpoch;
    final ms = data['criado_em_ms'];
    if (ms is num) {
      return ((agoraMs - ms.toInt()) / 1000).floor();
    }
    final iso = data['criado_em_iso'];
    if (iso is String) {
      final dt = DateTime.tryParse(iso);
      if (dt != null) {
        return ((agoraMs - dt.millisecondsSinceEpoch) / 1000).floor();
      }
    }
    final criadoEm = data['criado_em'];
    if (criadoEm is Map && criadoEm['_seconds'] != null) {
      final criadoMs = (criadoEm['_seconds'] as num).toInt() * 1000 +
          ((criadoEm['_nanoseconds'] as num?)?.toInt() ?? 0) ~/ 1000000;
      return ((agoraMs - criadoMs) / 1000).floor();
    }
    return 0;
  }

  // Cartão
  final _nsuCtl = TextEditingController();
  final _cardNumeroCtl = TextEditingController();
  final _cardValidadeCtl = TextEditingController();
  final _cardCvvCtl = TextEditingController();
  final _cardNomeCtl = TextEditingController();

  // ─── Computed ───

  double get _totalOriginal =>
      widget.parcelas.fold(0.0, (s, p) => s + p.valorEmAberto);

  double get _diasAtrasoMedio {
    if (widget.parcelas.isEmpty) return 0;
    final hoje = DateTime.now();
    double total = 0;
    for (final p in widget.parcelas) {
      final venc = p.dataVencimento;
      if (venc.isBefore(hoje)) {
        total += hoje.difference(venc).inDays;
      }
    }
    return widget.parcelas.length > 0 ? total / widget.parcelas.length : 0;
  }

  double get _jurosCalculados {
    final dias = _diasAtrasoMedio;
    if (dias <= 0 || !widget.configJuros.cobrarJurosPorAtraso) return 0;
    final taxa = widget.configJuros.percentualJurosAoDia / 100;
    final tolerancia = widget.configJuros.diasTolerancia;
    double total = 0;
    for (final p in widget.parcelas) {
      final venc = p.dataVencimento;
      final diasAtraso = DateTime.now().difference(venc).inDays;
      final d = diasAtraso > tolerancia ? diasAtraso - tolerancia : 0;
      total += p.valorEmAberto * (taxa * d);
    }
    return total;
  }

  double get _multaCalculada {
    if (!widget.configJuros.cobrarMultaPorAtraso) return 0;
    final perc = widget.configJuros.percentualMulta / 100;
    double total = 0;
    for (final p in widget.parcelas) {
      final venc = p.dataVencimento;
      if (DateTime.now().difference(venc).inDays > 0) {
        total += p.valorEmAberto * perc;
      }
    }
    return total;
  }

  double get _valorFinal => _totalOriginal + _jurosCalculados + _multaCalculada;

  double get _valorRecebido {
    final t = _dinheiroCtl.text.trim();
    if (t.isEmpty) return 0;
    final normalizado = t.replaceAll(',', '.').replaceAll(RegExp(r'[^\d.]'), '');
    final valor = double.tryParse(normalizado);
    if (valor == null || !valor.isFinite) return 0;
    return valor;
  }

  @override
  void initState() {
    super.initState();
    _dinheiroCtl.addListener(() => setState(() {
          _troco = _valorRecebido - _valorFinal;
          if (_troco < 0) _troco = 0;
        }));
  }

  @override
  void dispose() {
    _dinheiroCtl.dispose();
    _nsuCtl.dispose();
    _cardNumeroCtl.dispose();
    _cardValidadeCtl.dispose();
    _cardCvvCtl.dispose();
    _cardNomeCtl.dispose();
    _pixPollTimer?.cancel();
    _pixCountdownTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      backgroundColor: Colors.transparent,
      child: Container(
        width: 820,
        constraints: const BoxConstraints(maxHeight: 800),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 40,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(28, 0, 28, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildResumoCliente(),
                    const SizedBox(height: 20),
                    _buildCardsResumo(),
                    const SizedBox(height: 24),
                    _buildFormasPagamento(),
                    const SizedBox(height: 20),
                    _buildFormularioForma(),
                  ],
                ),
              ),
            ),
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  // ─── HEADER ───

  Widget _buildHeader() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [_roxo, Color(0xFF8E24AA)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(28, 20, 20, 20),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.payments_rounded, color: Colors.white, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Efetuar Pagamento',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: Colors.white)),
                Text('Crediário · ${widget.parcelas.length} parcela(s)',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                        color: Colors.white.withValues(alpha: 0.85))),
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close_rounded, color: Colors.white, size: 22),
            tooltip: 'Fechar',
          ),
        ],
      ),
    );
  }

  // ─── RESUMO CLIENTE ───

  Widget _buildResumoCliente() {
    return Container(
      margin: const EdgeInsets.only(top: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _fundoCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _borda),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: _roxo.withValues(alpha: 0.1),
            child: Text(
              (widget.clienteNome.isNotEmpty
                      ? widget.clienteNome[0]
                      : '?')
                  .toUpperCase(),
              style: GoogleFonts.plusJakartaSans(
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                  color: _roxo),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.clienteNome,
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: _texto)),
                if (widget.clienteCpf != null &&
                    widget.clienteCpf!.isNotEmpty)
                  Text('CPF: ${widget.clienteCpf}',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 13, color: _muted)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── CARDS RESUMO ───

  Widget _buildCardsResumo() {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Row(
          children: [
            _cardValor('Valor Original', _moeda.format(_totalOriginal),
                Icons.receipt_long_rounded, _roxo),
            const SizedBox(width: 6),
            _cardValor('Juros + Multa',
                _moeda.format(_jurosCalculados + _multaCalculada),
                Icons.trending_up_rounded, _laranja),
            const SizedBox(width: 6),
            _cardValor('Valor Final', _moeda.format(_valorFinal),
                Icons.check_circle_outline, const Color(0xFF059669)),
          ],
        );
      },
    );
  }

  Widget _cardValor(String label, String valor, IconData icon, Color cor) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cor.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cor.withValues(alpha: 0.15)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 16, color: cor),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(label,
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 11, color: cor, fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(valor,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: cor)),
          ],
        ),
      ),
    );
  }

  // ─── FORMAS DE PAGAMENTO ───

  Widget _buildFormasPagamento() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Forma de pagamento',
            style: GoogleFonts.plusJakartaSans(
                fontSize: 14, fontWeight: FontWeight.w700, color: _texto)),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _borda),
          ),
          clipBehavior: Clip.antiAlias,
          child: Row(
            children: [
              Expanded(child: _opcaoForma(
                icon: Icons.monetization_on_outlined,
                label: 'Dinheiro',
                forma: _FormaPagamentoCrediario.dinheiro,
              )),
              _separadorVertical(),
              Expanded(child: _opcaoForma(
                icon: Icons.pix_rounded,
                label: 'Pix',
                forma: _FormaPagamentoCrediario.pix,
              )),
              _separadorVertical(),
              Expanded(child: _opcaoForma(
                icon: Icons.credit_card_outlined,
                label: 'Cartão\nCrédito',
                forma: _FormaPagamentoCrediario.cartaoCredito,
              )),
              _separadorVertical(),
              Expanded(child: _opcaoForma(
                icon: Icons.credit_score_outlined,
                label: 'Cartão\nDébito',
                forma: _FormaPagamentoCrediario.cartaoDebito,
              )),
            ],
          ),
        ),
      ],
    );
  }

  Widget _separadorVertical() {
    return Container(
      width: 1,
      height: 48,
      color: const Color(0xFFECECEC),
    );
  }

  Widget _opcaoForma({
    required IconData icon,
    required String label,
    required _FormaPagamentoCrediario forma,
  }) {
    final selecionado = _forma == forma;
    final corIcone = selecionado ? _roxo : _muted;
    final corTexto = selecionado ? _roxo : _muted;
    final bgCor = selecionado ? _roxo.withValues(alpha: 0.07) : Colors.transparent;
    final borderCor = selecionado ? _roxo : Colors.transparent;

    return InkWell(
        onTap: () {
          setState(() {
            _forma = forma;
            _troco = 0;
          });
        },
        borderRadius: BorderRadius.circular(14),
        splashColor: _roxo.withValues(alpha: 0.08),
        highlightColor: _roxo.withValues(alpha: 0.04),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeInOut,
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          decoration: BoxDecoration(
            color: bgCor,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: borderCor,
              width: 1.2,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                transitionBuilder: (child, anim) => ScaleTransition(
                  scale: anim,
                  child: child,
                ),
                child: Icon(icon, key: ValueKey(selecionado), size: 20, color: corIcone),
              ),
              const SizedBox(height: 4),
              Text(label,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    fontWeight: selecionado ? FontWeight.w700 : FontWeight.w600,
                    color: corTexto,
                  ),
                  textAlign: TextAlign.center),
            ],
          ),
        ),
    );
  }

  // ─── FORMULÁRIO DA FORMA SELECIONADA ───

  Widget _buildFormularioForma() {
    switch (_forma) {
      case _FormaPagamentoCrediario.dinheiro:
        return _buildFormDinheiro();
      case _FormaPagamentoCrediario.pix:
        return _buildFormPix();
      case _FormaPagamentoCrediario.cartaoCredito:
      case _FormaPagamentoCrediario.cartaoDebito:
        return _buildFormCartao();
    }
  }

  // ─── DINHEIRO ───

  Widget _buildFormDinheiro() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _fundoCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _borda),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.monetization_on_rounded, size: 18, color: const Color(0xFF059669)),
              const SizedBox(width: 8),
              Text('Pagamento em Dinheiro',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: _texto)),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _buildCampoMonetario(
                  label: 'Valor a pagar',
                  controller: null,
                  valor: _valorFinal,
                  readOnly: true,
                  prefix: const Icon(Icons.arrow_downward_rounded,
                      size: 16, color: _muted),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildCampoDinheiro(),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildCampoMonetario(
                  label: 'Troco',
                  controller: null,
                  valor: _troco,
                  readOnly: true,
                  prefix: const Icon(Icons.swap_horiz_rounded,
                      size: 16, color: Color(0xFF059669)),
                  corValor: const Color(0xFF059669),
                ),
              ),
            ],
          ),
          if (_valorRecebido > 0 && _valorRecebido < _valorFinal)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded,
                      size: 16, color: _laranja),
                  const SizedBox(width: 6),
                  Text(
                    'Valor recebido insuficiente. Faltam ${_moeda.format(_valorFinal - _valorRecebido)}',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        color: _laranja,
                        fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ─── PIX ───

  Widget _buildFormPix() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _fundoCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _borda),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.pix_rounded, size: 18, color: const Color(0xFF059669)),
              const SizedBox(width: 8),
              Text('Pagamento via Pix',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: _texto)),
              const Spacer(),
              Text(_moeda.format(_valorFinal),
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: _roxo)),
            ],
          ),
          const SizedBox(height: 20),
          if (_pixGerado) ...[
            // QR Code real vindo da API — NUNCA é limpo durante os 5 min
            // Mesmo após expirar, preservamos para o usuário consultar
            RepaintBoundary(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Center(
                    child: Container(
                      width: 220,
                      height: 220,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: _borda, width: 1.5),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 20,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(15),
                        child: _pixQrCodeBase64.isNotEmpty
                            ? Image.memory(
                                base64Decode(_pixQrCodeBase64),
                                fit: BoxFit.contain,
                                width: 220,
                                height: 220,
                                gaplessPlayback: true,
                                errorBuilder: (context, error, stackTrace) =>
                                    _buildQrErrorFallback(),
                              )
                            : _buildQrErrorFallback(),
                      ),
                    ),
                  ),
                if (_pixExpirado)
                  Container(
                    width: 220,
                    height: 220,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.40),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.timer_off_rounded,
                            size: 36, color: Colors.white),
                        const SizedBox(height: 6),
                        Text('Expirado',
                            style: GoogleFonts.plusJakartaSans(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: Colors.white)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
            const SizedBox(height: 20),
            // Copia e cola completo
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _borda),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('Código Pix copia e cola',
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 11,
                              color: _muted,
                              fontWeight: FontWeight.w600)),
                      const Spacer(),
                      InkWell(
                        onTap: () {
                          Clipboard.setData(
                              ClipboardData(text: _pixCopiaCola));
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: const Text('Código Pix copiado!'),
                              duration: const Duration(seconds: 2),
                              behavior: SnackBarBehavior.floating,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                            ),
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: _roxo.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.copy_rounded,
                                  size: 14, color: _roxo),
                              const SizedBox(width: 4),
                              Text('Copiar',
                                  style: GoogleFonts.plusJakartaSans(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: _roxo)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SelectableText(_pixCopiaCola,
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          color: _texto,
                          fontWeight: FontWeight.w500,
                          height: 1.4)),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // Status — muda conforme o estado
            if (!_pixExpirado) ...[
              // Aguardando pagamento
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFFF3E0), Color(0xFFFFF8E1)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: _laranja.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: _laranja.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.hourglass_top_rounded,
                          size: 18, color: _laranja),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Aguardando pagamento...',
                              style: GoogleFonts.plusJakartaSans(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: _laranja)),
                          const SizedBox(height: 2),
                          Text(
                            'Escaneie o QR Code com seu banco ou copie o código Pix.',
                            style: GoogleFonts.plusJakartaSans(
                                fontSize: 11,
                                color: _laranja.withValues(alpha: 0.8)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // Contador regressivo
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: _pixSegundosRestantes <= 60
                        ? const Color(0xFFFFF3E0)
                        : const Color(0xFFF0FDF4),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _pixSegundosRestantes <= 60
                            ? Icons.timer_off_rounded
                            : Icons.timer_outlined,
                        size: 14,
                        color: _pixSegundosRestantes <= 60
                            ? _laranja
                            : const Color(0xFF059669),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _formatarContagem(_pixSegundosRestantes),
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: _pixSegundosRestantes <= 60
                              ? _laranja
                              : const Color(0xFF059669),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ] else ...[
              // Expirado / recusado
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: const Color(0xFFFECACA)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEE2E2),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.timer_off_rounded,
                          size: 18, color: Color(0xFFDC2626)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Cobrança expirada',
                              style: GoogleFonts.plusJakartaSans(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFFDC2626))),
                          const SizedBox(height: 2),
                          Text(
                            'O tempo para pagamento acabou. Gere uma nova cobrança.',
                            style: GoogleFonts.plusJakartaSans(
                                fontSize: 11,
                                color: const Color(0xFFDC2626)
                                    .withValues(alpha: 0.8)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // Botão gerar nova cobrança
              Center(
                child: SizedBox(
                  width: 280,
                  child: FilledButton.icon(
                    onPressed: _pixCarregando ? null : _gerarPix,
                    icon: _pixCarregando
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.refresh_rounded, size: 20),
                    label: Text(
                        _pixCarregando ? 'Gerando...' : 'Gerar nova cobrança Pix',
                        style: GoogleFonts.plusJakartaSans(
                            fontWeight: FontWeight.w700, fontSize: 14)),
                    style: FilledButton.styleFrom(
                      backgroundColor: _roxo,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 0,
                    ),
                  ),
                ),
              ),
            ],
          ] else if (!_pixGerado) ...[
            // Botão gerar Pix
            Center(
              child: SizedBox(
                width: 280,
                child: FilledButton.icon(
                  onPressed: _pixCarregando ? null : _gerarPix,
                  icon: _pixCarregando
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.pix_rounded, size: 20),
                  label: Text(
                      _pixCarregando ? 'Gerando...' : 'Gerar cobrança Pix',
                      style: GoogleFonts.plusJakartaSans(
                          fontWeight: FontWeight.w700, fontSize: 14)),
                  style: FilledButton.styleFrom(
                    backgroundColor: _roxo,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Center(
              child: Text(
                'O QR Code será exibido para pagamento via Pix',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 12, color: _muted),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Fallback quando a imagem QR não está disponível
  Widget _buildQrErrorFallback() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.qr_code_2_rounded,
              size: 80, color: _texto.withValues(alpha: 0.1)),
          const SizedBox(height: 8),
          Text(_pixCopiaCola.isNotEmpty ? 'Use o código copia e cola' : 'QR indisponível',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 11, color: _muted)),
        ],
      ),
    );
  }

  /// Reinicia o estado do PIX para permitir gerar uma nova cobrança.
  void _reiniciarEstadoPix() {
    _pixPollTimer?.cancel();
    _pixCountdownTimer?.cancel();
    _pixCopiaCola = '';
    _pixQrCodeBase64 = '';
    _pixTransacaoId = '';
    _pixGerado = false;
    _pixCarregando = true;
    _pixStatus = '';
    _pixExpirado = false;
    _pixSegundosRestantes = 300;
  }

  /// Formata segundos no formato MM:SS
  String _formatarContagem(int segundos) {
    if (segundos <= 0) return '00:00';
    final min = (segundos ~/ 60).toString().padLeft(2, '0');
    final sec = (segundos % 60).toString().padLeft(2, '0');
    return '$min:$sec';
  }

  Future<void> _gerarPix() async {
    // Reinicia estado PIX para gerar nova cobrança
    _reiniciarEstadoPix();

    // Valida CPF antes de chamar o backend
    final cpfCliente = (widget.clienteCpf ?? '').replaceAll(RegExp(r'\D'), '');
    final temCpf = cpfCliente.length == 11;

    if (!temCpf) {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        barrierColor: Colors.black.withValues(alpha: 0.55),
        builder: (ctx) => Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            width: 400,
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF3E0),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.warning_amber_rounded,
                      size: 32, color: _laranja),
                ),
                const SizedBox(height: 20),
                Text('CPF necessário',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: _texto)),
                const SizedBox(height: 10),
                Text(
                  'Para gerar uma cobrança Pix, o cliente precisa ter um CPF cadastrado. '
                  'Cadastre o CPF do cliente antes de continuar.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 13, color: _muted, height: 1.5),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: FilledButton.styleFrom(
                    backgroundColor: _roxo,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 44),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Entendi', style: TextStyle(fontSize: 14)),
                ),
              ],
            ),
          ),
        ),
      );
      setState(() => _pixCarregando = false);
      return;
    }

    try {
      final data = await callFirebaseFunctionSafe(
        'gerarCobrancaPixCrediario',
        region: kFirebaseFunctionsRegionSouth,
        parameters: {
          'lojaId': widget.lojaId,
          'clienteId': widget.clienteId,
          'clienteNome': widget.clienteNome,
          'clienteCpf': cpfCliente,
          'valor': _valorFinal,
          'descricao':
              'Pagamento crediário - ${widget.parcelas.length} parcela(s)',
          'parcelasIds': widget.parcelas.map((p) => p.id).toList(),
          'valorOriginal': _totalOriginal,
          'jurosCobrados': _jurosCalculados,
          'multaCobrada': _multaCalculada,
        },
      );

      int segundosRestantes = 300;
      final segundosDesde = _segundosDesdeCriacaoPix(data);
      if (segundosDesde > 0) {
        segundosRestantes = 300 - segundosDesde;
        if (segundosRestantes < 0) segundosRestantes = 0;
      }

      setState(() {
        _pixCopiaCola = data['copia_cola'] ?? '';
        _pixQrCodeBase64 = data['qr_code'] ?? '';
        _pixTransacaoId = data['payment_id']?.toString() ?? data['mp_payment_id']?.toString() ?? data['id'] ?? '';
        _pixGerado = true;
        _pixStatus = 'aguardando';
        _pixExpirado = false;
        _pixSegundosRestantes = segundosRestantes;
      });

      // Inicia contador regressivo visível
      _iniciarCountdownPix();

      // Primeira consulta rápida + polling
      _iniciarPollingPix(data['id']?.toString() ?? '');
      Future<void>.delayed(const Duration(seconds: 2), () {
        if (!mounted || _pixStatus == 'confirmado') return;
        _consultarPixUmaVez(data['id']?.toString() ?? '');
      });
    } catch (e) {
      if (!mounted) return;

      // Detecta erro específico de CPF obrigatório
      final msg = e.toString();
      if (msg.contains('CPF_OBRIGATORIO')) {
        await _mostrarErroPagamento(
            'O cliente não possui CPF cadastrado. Cadastre o CPF para gerar a cobrança Pix.');
      } else {
        await _mostrarErroPagamento('Erro ao gerar Pix: $e');
      }
    } finally {
      if (mounted) setState(() => _pixCarregando = false);
    }
  }

  /// Inicia contador regressivo visível de 5 minutos
  void _iniciarCountdownPix() {
    _pixCountdownTimer?.cancel();
    _pixCountdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        if (_pixSegundosRestantes > 0) {
          _pixSegundosRestantes--;
        }
      });
      // Quando o tempo acaba, para o countdown
      if (_pixSegundosRestantes <= 0) {
        _pixCountdownTimer?.cancel();
      }
    });
  }

  void _iniciarPollingPix(String cobrancaId) {
    _pixPollTimer?.cancel();
    _pixPollTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
      if (_pixExpirado || _pixStatus == 'confirmado') {
        timer.cancel();
        return;
      }
      await _consultarPixUmaVez(cobrancaId, timer: timer);
    });
  }

  Future<void> _consultarPixUmaVez(String cobrancaId, {Timer? timer}) async {
    if (!mounted || _pixExpirado || _pixStatus == 'confirmado') return;
    if (cobrancaId.isEmpty) return;

    try {
      final data = await callFirebaseFunctionSafe(
        'consultarCobrancaPixCrediario',
        region: kFirebaseFunctionsRegionSouth,
        parameters: {'cobrancaId': cobrancaId},
      );
      final status = data['status'] as String? ?? 'aguardando';
      final segundosDesdeCriacao = _segundosDesdeCriacaoPix(data);
      if (segundosDesdeCriacao > 0 && mounted) {
        final restante = 300 - segundosDesdeCriacao;
        if (restante > 0) {
          setState(() => _pixSegundosRestantes = restante);
        }
      }

      if (status == 'aprovado' || status == 'confirmado') {
        timer?.cancel();
        _pixPollTimer?.cancel();
        _pixCountdownTimer?.cancel();
        if (!mounted) return;
        setState(() {
          _pixStatus = 'confirmado';
          _salvando = true;
        });
        await _confirmarPagamentoComDados({
          'forma': 'pix',
          'cobrancaId': cobrancaId,
          'transacaoId': data['transacaoId']?.toString() ?? _pixTransacaoId,
        });
        return;
      }

      if (segundosDesdeCriacao >= 300) {
        timer?.cancel();
        _pixPollTimer?.cancel();
        _pixCountdownTimer?.cancel();
        if (!mounted) return;
        setState(() {
          _pixExpirado = true;
          _pixStatus = 'expirado';
        });
        final ehRecusado = status == 'recusado' || status == 'cancelado';
        await _mostrarErroPagamento(
          ehRecusado
              ? 'Cobrança Pix recusada. Clique em "Gerar cobrança Pix" para tentar novamente.'
              : 'Tempo limite excedido. O Pix não foi pago dentro dos 5 minutos.',
        );
      }
    } catch (e) {
      debugPrint('[PIX crediário] Erro polling: $e');
    }
  }

  // ─── CARTÃO ───

  Widget _buildFormCartao() {
    final isCredito = _forma == _FormaPagamentoCrediario.cartaoCredito;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _fundoCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _borda),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(isCredito ? Icons.credit_card_rounded : Icons.credit_score_rounded,
                  size: 18, color: _roxo),
              const SizedBox(width: 8),
              Text(isCredito ? 'Cartão de Crédito' : 'Cartão de Débito',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: _texto)),
              const Spacer(),
              Text(_moeda.format(_valorFinal),
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: _roxo)),
            ],
          ),
          const SizedBox(height: 20),
          // Nome do titular
          _buildCampoTexto(
            label: 'Nome do titular',
            controller: _cardNomeCtl,
            hint: 'Como está no cartão',
            prefix: Icons.person_outline_rounded,
          ),
          const SizedBox(height: 14),
          // Número do cartão
          _buildCampoTexto(
            label: 'Número do cartão',
            controller: _cardNumeroCtl,
            hint: '0000 0000 0000 0000',
            prefix: Icons.credit_card_rounded,
            inputType: TextInputType.number,
            maxLength: 19,
          ),
          const SizedBox(height: 14),
          // Validade e CVV lado a lado
          IntrinsicHeight(
            child: Row(
              children: [
                Expanded(
                  child: _buildCampoTexto(
                    label: 'Validade (MM/AA)',
                    controller: _cardValidadeCtl,
                    hint: 'MM/AA',
                    prefix: Icons.calendar_today_rounded,
                    inputType: TextInputType.number,
                    maxLength: 5,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: _buildCampoTexto(
                    label: 'CVV',
                    controller: _cardCvvCtl,
                    hint: 'Código de segurança',
                    prefix: Icons.lock_outline_rounded,
                    inputType: TextInputType.number,
                    maxLength: 4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF3E0),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline_rounded,
                    size: 16, color: _laranja),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isCredito
                        ? 'Pagamento único (sem parcelamento). Cobrança via gateway configurado.'
                        : 'Cartão de débito será processado como pagamento único.',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 12, color: _laranja, fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── FOOTER ───

  Widget _buildFooter() {
    final podeConfirmar = switch (_forma) {
      _FormaPagamentoCrediario.dinheiro =>
        _valorRecebido >= _valorFinal && _valorFinal > 0,
      _FormaPagamentoCrediario.pix => false, // PIX confirma via polling/webhook
      _FormaPagamentoCrediario.cartaoCredito ||
      _FormaPagamentoCrediario.cartaoDebito =>
        _valorFinal > 0 && _cardNumeroCtl.text.trim().length >= 13,
    };

    // Para PIX em estado aguardando, mostra status em vez do botão confirmar
    final isPixAguardando =
        _forma == _FormaPagamentoCrediario.pix && _pixGerado && _pixStatus == 'aguardando';

    return Container(
      padding: const EdgeInsets.fromLTRB(28, 14, 28, 18),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: _borda, width: 0.5)),
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: _salvando ? null : () => Navigator.pop(context),
              style: OutlinedButton.styleFrom(
                foregroundColor: _muted,
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: const BorderSide(color: _borda),
                ),
              ),
              child: Text('Fechar',
                  style: GoogleFonts.plusJakartaSans(
                      fontWeight: FontWeight.w700, fontSize: 14)),
            ),
          ),
          const Spacer(),
          if (isPixAguardando) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF3E0),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _laranja.withValues(alpha: 0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: _laranja),
                  ),
                  const SizedBox(width: 8),
                  Text('Aguardando pagamento...',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: _laranja)),
                ],
              ),
            ),
          ] else ...[
            FilledButton.icon(
              onPressed: _salvando || !podeConfirmar ? null : _confirmarPagamento,
              icon: _salvando
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.check_circle_outline, size: 18),
              label: Text(
                  _salvando ? 'Processando...' : 'Confirmar Pagamento',
                  style: GoogleFonts.plusJakartaSans(
                      fontWeight: FontWeight.w700, fontSize: 14)),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF059669),
                foregroundColor: Colors.white,
                disabledBackgroundColor:
                    const Color(0xFF059669).withValues(alpha: 0.3),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ─── CONFIRMAR ───

  Future<void> _confirmarPagamento() async {
    if (_salvando) return;

    // Cartão de crédito: processa via gateway (não vai direto para efetuarPagamento)
    if (_forma == _FormaPagamentoCrediario.cartaoCredito) {
      await _processarCartaoCredito();
      return;
    }

    // Cartão de débito: confirmação manual (sem gateway)
    if (_forma == _FormaPagamentoCrediario.cartaoDebito) {
      final confirmado = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        barrierColor: Colors.black.withValues(alpha: 0.55),
        builder: (_) => _ConfirmarPagamentoCrediario(
          clienteNome: widget.clienteNome,
          valor: _valorFinal,
          forma: 'Cartão de Débito',
          troco: null,
        ),
      );
      if (confirmado != true) return;
      await _confirmarPagamentoComDados({
        'forma': 'cartao_debito',
        'valorRecebido': _valorFinal,
        'troco': 0,
        'nsu': _nsuCtl.text.trim(),
      });
      return;
    }

    // Confirmação extra para dinheiro
    if (_forma == _FormaPagamentoCrediario.dinheiro) {
      final confirmado = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        barrierColor: Colors.black.withValues(alpha: 0.55),
        builder: (_) => _ConfirmarPagamentoCrediario(
          clienteNome: widget.clienteNome,
          valor: _valorFinal,
          forma: 'Dinheiro',
          troco: _troco,
        ),
      );
      if (confirmado != true) return;

      await _confirmarPagamentoComDados({
        'forma': 'dinheiro',
        'valorRecebido': _valorRecebido,
        'troco': _troco,
      });
      return;
    }

    // PIX: já está em andamento via polling, não deve chegar aqui
    await _mostrarErroPagamento('Aguardando confirmação do PIX via webhook.');
  }

  /// Processa pagamento com cartão de crédito via gateway ativo.
  /// Cobrança única (sem parcelamento), à vista.
  Future<void> _processarCartaoCredito() async {
    // Valida campos obrigatórios do cartão
    final numero = _cardNumeroCtl.text.trim().replaceAll(RegExp(r'\s+'), '');
    final validade = _cardValidadeCtl.text.trim();
    final cvv = _cardCvvCtl.text.trim();
    final nome = _cardNomeCtl.text.trim();

    if (numero.length < 13) {
      _mostrarErroPagamento('Número do cartão inválido.');
      return;
    }
    if (validade.length < 4) {
      _mostrarErroPagamento('Data de validade inválida.');
      return;
    }
    if (cvv.length < 3) {
      _mostrarErroPagamento('CVV inválido.');
      return;
    }
    if (nome.isEmpty) {
      _mostrarErroPagamento('Nome do titular é obrigatório.');
      return;
    }

    // Confirmação
    final confirmado = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (_) => _ConfirmarPagamentoCrediario(
        clienteNome: widget.clienteNome,
        valor: _valorFinal,
        forma: 'Cartão de Crédito',
        troco: null,
      ),
    );
    if (confirmado != true) return;

    setState(() => _salvando = true);

    try {
      // Parse validade MM/AA ou MM/AAAA
      String mes = '', ano = '';
      final valParts = validade.split(RegExp(r'[/\s-]'));
      if (valParts.length >= 2) {
        mes = valParts[0].padLeft(2, '0');
        ano = valParts[1].length == 2 ? '20' + valParts[1] : valParts[1];
      } else if (validade.length >= 4) {
        mes = validade.substring(0, 2);
        ano = validade.length >= 5
            ? (validade.substring(3).length == 2
                ? '20' + validade.substring(3)
                : validade.substring(3))
            : '';
      }

      final cpfCliente = (widget.clienteCpf ?? '').replaceAll(RegExp(r'\D'), '');
      final parcelasIds = widget.parcelas.map((p) => p.id).toList();

      final data = await callFirebaseFunctionSafe(
        'processarPagamentoCartaoCrediario',
        region: kFirebaseFunctionsRegionSouth,
        parameters: {
          'lojaId': widget.lojaId,
          'clienteId': widget.clienteId,
          'clienteNome': widget.clienteNome,
          'clienteCpf': cpfCliente,
          'valor': _valorFinal,
          'cardNumber': numero,
          'cardExpiryMonth': mes,
          'cardExpiryYear': ano,
          'cardCvv': cvv,
          'cardHolderName': nome,
          'descricao':
              'Pagamento crediário - ${widget.parcelas.length} parcela(s)',
          'parcelasIds': parcelasIds,
          'valorOriginal': _totalOriginal,
          'jurosCobrados': _jurosCalculados,
          'multaCobrada': _multaCalculada,
          'usuarioNome': widget.usuarioNome,
        },
      );
      final aprovado = data['aprovado'] == true;

      if (!mounted) return;
      setState(() => _salvando = false);

      if (aprovado) {
        // Pagamento aprovado → muestra comprovante
        data['forma'] = 'cartao_credito';
        data['transacaoId'] = data['payment_id'] ?? data['transacaoId'] ?? '';
        data['nsu'] = data['authorizationCode'] ?? '';
        await _mostrarComprovante(data);
        if (!mounted) return;
        Navigator.pop(context, true); // fecha modal de pagamento
      } else {
        // Recusado
        final motivo = data['statusDetail'] ?? data['mensagem'] ?? 'Transação recusada';
        await _mostrarErroPagamento(
          'Pagamento recusado: $motivo',
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _salvando = false);
      await _mostrarErroPagamento('Erro ao processar cartão: $e');
    }
  }

  Future<void> _confirmarPagamentoComDados(
      Map<String, dynamic> dadosPagamento) async {
    final parcelasIds = widget.parcelas.map((p) => p.id).toList();

    setState(() => _salvando = true);

    try {
      final data = await callFirebaseFunctionSafe(
        'efetuarPagamentoCrediario',
        region: kFirebaseFunctionsRegionSouth,
        parameters: {
          'lojaId': widget.lojaId,
          'clienteId': widget.clienteId,
          'parcelasIds': parcelasIds,
          'valorPago': _valorFinal,
          'valorOriginal': _totalOriginal,
          'jurosCobrados': _jurosCalculados,
          'multaCobrada': _multaCalculada,
          'dadosPagamento': dadosPagamento,
          'usuarioNome': widget.usuarioNome,
        },
      );
      data['transacaoId'] = dadosPagamento['transacaoId'];
      data['nsu'] = dadosPagamento['nsu'];
      data['forma'] = dadosPagamento['forma'];

      if (!mounted) return;
      setState(() => _salvando = false);

      await _mostrarComprovante(data);
      if (!mounted) return;
      Navigator.pop(context, true);
    } on CallableHttpException catch (e) {
      if (!mounted) return;
      setState(() => _salvando = false);
      await _mostrarErroPagamento(mensagemCallableHttpException(e));
    } catch (e) {
      if (!mounted) return;
      setState(() => _salvando = false);
      await _mostrarErroPagamento('Erro ao confirmar pagamento: $e');
    }
  }

  Future<void> _mostrarComprovante(Map<String, dynamic> data) async {
    final now = DateTime.now();
    final df = DateFormat('dd/MM/yyyy HH:mm');

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 100, vertical: 40),
        backgroundColor: Colors.transparent,
        child: Container(
          width: 480,
          constraints: const BoxConstraints(maxHeight: 600),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 30,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header verde
              Container(
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF059669), Color(0xFF34D399)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(20),
                    topRight: Radius.circular(20),
                  ),
                ),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.25),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.check_rounded,
                          color: Colors.white, size: 36),
                    ),
                    const SizedBox(height: 14),
                    Text('Pagamento Confirmado',
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: Colors.white)),
                    Text(df.format(now),
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 13,
                            color: Colors.white.withValues(alpha: 0.85))),
                  ],
                ),
              ),
              // Corpo
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _linhaComp('Cliente', widget.clienteNome),
                    if (widget.clienteCpf != null)
                      _linhaComp('CPF', widget.clienteCpf!),
                    const Divider(height: 20),
                    _linhaComp('Valor pago', _moeda.format(_valorFinal)),
                    _linhaComp('Forma',
                        switch (_forma) {
                          _FormaPagamentoCrediario.dinheiro => 'Dinheiro',
                          _FormaPagamentoCrediario.pix => 'Pix',
                          _FormaPagamentoCrediario.cartaoCredito =>
                            'Cartão de Crédito',
                          _FormaPagamentoCrediario.cartaoDebito =>
                            'Cartão de Débito',
                        }),
                    _linhaComp('Parcelas',
                        '${widget.parcelas.length} parcela(s)'),
                    if (data['protocolo'] != null)
                      _linhaComp('Protocolo', data['protocolo'].toString()),
                    if (data['forma'] == 'pix' && data['transacaoId'] != null &&
                        data['transacaoId'].toString().isNotEmpty)
                      _linhaComp('Transação Pix', data['transacaoId'].toString()),
                    if ((data['forma'] == 'cartao_credito' ||
                            data['forma'] == 'cartao_debito') &&
                        data['nsu'] != null &&
                        data['nsu'].toString().isNotEmpty)
                      _linhaComp('NSU', data['nsu'].toString()),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: () => Navigator.pop(ctx),
                            icon: const Icon(Icons.close_rounded, size: 18),
                            label: Text('Fechar',
                                style: GoogleFonts.plusJakartaSans(
                                    fontWeight: FontWeight.w700)),
                            style: FilledButton.styleFrom(
                              backgroundColor: _laranja,
                              foregroundColor: Colors.white,
                              padding:
                                  const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 0,
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
    );
  }

  Widget _linhaComp(String label, String valor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 13, color: _muted)),
          Text(valor,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: _texto)),
        ],
      ),
    );
  }

  Future<void> _mostrarErroPagamento(String mensagem) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          width: 400,
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: const BoxDecoration(
                  color: Color(0xFFFEF2F2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.error_outline_rounded,
                    color: Color(0xFFDC2626), size: 32),
              ),
              const SizedBox(height: 16),
              Text('Erro no Pagamento',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: _texto)),
              const SizedBox(height: 8),
              Text(mensagem,
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 13, color: _muted),
                  textAlign: TextAlign.center),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: FilledButton.styleFrom(
                    backgroundColor: _laranja,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: Text('Fechar',
                      style: GoogleFonts.plusJakartaSans(
                          fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── CAMPOS ───

  Widget _buildCampoMonetario({
    required String label,
    required TextEditingController? controller,
    double? valor,
    bool readOnly = false,
    Widget? prefix,
    Color corValor = const Color(0xFF1A1A2E),
  }) {
    final display = controller != null
        ? TextField(
            controller: controller,
            readOnly: readOnly,
            decoration: InputDecoration(
              labelText: label,
              labelStyle: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: _muted),
              prefixIcon: prefix,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: _borda),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: _borda),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: _roxo, width: 1.5),
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              filled: true,
              fillColor: Colors.white,
            ),
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onChanged: (_) => setState(() {}),
          )
        : TextField(
            readOnly: true,
            decoration: InputDecoration(
              labelText: label,
              labelStyle: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: _muted),
              prefixIcon: prefix,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: _borda),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: _borda),
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              filled: true,
              fillColor: _fundoCard,
            ),
            controller: TextEditingController(text: _moeda.format(valor ?? 0)),
            style: GoogleFonts.plusJakartaSans(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: corValor),
          );

    return display;
  }

  /// Campo específico para "Valor recebido" em Dinheiro.
  /// Aceita números decimais (vírgula ou ponto). "20" = R$ 20,00.
  Widget _buildCampoDinheiro() {
    return TextField(
      controller: _dinheiroCtl,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: 'Valor recebido (R\$)',
        labelStyle: GoogleFonts.plusJakartaSans(
            fontSize: 13, fontWeight: FontWeight.w600, color: _muted),
        prefixIcon: const Icon(Icons.payments_rounded,
            size: 16, color: _roxo),
        hintText: '0,00',
        hintStyle: GoogleFonts.plusJakartaSans(fontSize: 14, color: _muted.withValues(alpha: 0.5)),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: _borda),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: _borda),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _roxo, width: 1.5),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        filled: true,
        fillColor: Colors.white,
      ),
      style: GoogleFonts.plusJakartaSans(
          fontSize: 18, fontWeight: FontWeight.w800, color: _roxo),
      onChanged: (_) => setState(() {}),
    );
  }

  Widget _buildCampoTexto({
    required String label,
    required TextEditingController controller,
    String? hint,
    IconData? prefix,
    TextInputType? inputType,
    int? maxLength,
  }) {
    return TextField(
      controller: controller,
      keyboardType: inputType,
      maxLength: maxLength,
      decoration: InputDecoration(
        counterText: maxLength != null ? '' : null,
        labelText: label,
        hintText: hint,
        labelStyle: GoogleFonts.plusJakartaSans(
            fontSize: 13, fontWeight: FontWeight.w600, color: _muted),
        hintStyle: GoogleFonts.plusJakartaSans(fontSize: 13, color: _muted),
        prefixIcon: prefix != null ? Icon(prefix, size: 18) : null,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: _borda),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: _borda),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _roxo, width: 1.5),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        filled: true,
        fillColor: Colors.white,
      ),
    );
  }
}

// ═══════════════════════════════════════════
// CONFIRMAÇÃO DE PAGAMENTO
// ═══════════════════════════════════════════

class _ConfirmarPagamentoCrediario extends StatelessWidget {
  final String clienteNome;
  final double valor;
  final String forma;
  final double? troco;

  const _ConfirmarPagamentoCrediario({
    required this.clienteNome,
    required this.valor,
    required this.forma,
    this.troco,
  });

  @override
  Widget build(BuildContext context) {
    const roxo = Color(0xFF6A1B9A);
    const texto = Color(0xFF1A1A2E);
    const muted = Color(0xFF64748B);
    final moeda = NumberFormat.currency(symbol: 'R\$', decimalDigits: 2);

    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 420,
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 30,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: roxo.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.payments_rounded,
                  color: roxo, size: 32),
            ),
            const SizedBox(height: 16),
            Text('Confirmar Pagamento',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: texto)),
            const SizedBox(height: 20),
            _linhaConfirmacao('Cliente', clienteNome),
            _linhaConfirmacao('Valor', moeda.format(valor)),
            _linhaConfirmacao('Forma', forma),
            if (troco != null && troco! > 0)
              _linhaConfirmacao('Troco', moeda.format(troco!)),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, false),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: muted,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                    ),
                    child: Text('Cancelar',
                        style: GoogleFonts.plusJakartaSans(
                            fontWeight: FontWeight.w700)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF059669),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    child: Text('Confirmar',
                        style: GoogleFonts.plusJakartaSans(
                            fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _linhaConfirmacao(String label, String valor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 14, color: Color(0xFF64748B))),
          Text(valor,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1A1A2E))),
        ],
      ),
    );
  }
}
