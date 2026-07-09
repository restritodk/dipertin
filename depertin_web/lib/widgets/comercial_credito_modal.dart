import 'package:depertin_web/models/comercial_cliente.dart';
import 'package:depertin_web/services/comercial_clientes_service.dart';
import 'package:depertin_web/widgets/dipertin_painel_feedback.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

/// Modal premium para gerenciar limite de crédito do cliente.
///
/// Uso:
/// ```dart
/// await mostrarComercialCreditoModal(context, lojaId: lojaId, cliente: cliente);
/// ```
Future<void> mostrarComercialCreditoModal(
  BuildContext context, {
  required String lojaId,
  required ComercialCliente cliente,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black.withValues(alpha: 0.5),
    builder: (_) => _CreditLimitModal(
      lojaId: lojaId,
      cliente: cliente,
    ),
  );
}

// ══════════════════════════════════════════════════════════════════
// CORES REUTILIZÁVEIS
// ══════════════════════════════════════════════════════════════════

const Color _roxo = Color(0xFF6A1B9A);
const Color _roxoClaro = Color(0xFF8E24AA);
const Color _laranja = Color(0xFFFF8F00);
const Color _texto = Color(0xFF1E1B4B);
const Color _muted = Color(0xFF64748B);
const Color _borda = Color(0xFFE2E8F0);
const Color _fundo = Color(0xFFF8F9FC);
const Color _sucesso = Color(0xFF10B981);
const Color _erro = Color(0xFFEF4444);
const Color _superficieCard = Color(0xFFFFFFFF);

// ══════════════════════════════════════════════════════════════════
// CREDIT OPERATION TYPE
// ══════════════════════════════════════════════════════════════════

enum _OperacaoCredito { adicionar, diminuir }

// ══════════════════════════════════════════════════════════════════
// MODAL PRINCIPAL — Gerenciar Limite de Crédito
// ══════════════════════════════════════════════════════════════════

class _CreditLimitModal extends StatefulWidget {
  const _CreditLimitModal({
    required this.lojaId,
    required this.cliente,
  });

  final String lojaId;
  final ComercialCliente cliente;

  @override
  State<_CreditLimitModal> createState() => _CreditLimitModalState();
}

class _CreditLimitModalState extends State<_CreditLimitModal> {
  late final TextEditingController _valorCtrl;
  final _formKey = GlobalKey<FormState>();
  _OperacaoCredito _operacao = _OperacaoCredito.adicionar;
  bool _salvando = false;

  late final NumberFormat _moedaFmt;
  late final NumberFormat _moedaInputFmt;

  @override
  void initState() {
    super.initState();
    _valorCtrl = TextEditingController();
    _moedaFmt = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    _moedaInputFmt = NumberFormat.currency(locale: 'pt_BR', symbol: '');
  }

  @override
  void dispose() {
    _valorCtrl.dispose();
    super.dispose();
  }

  // ── Getters calculados ────────────────────────────────────────

  double get _limiteAtual => widget.cliente.limiteCredito;
  double get _usado => widget.cliente.creditoUtilizado;
  double get _disponivelAtual => widget.cliente.creditoDisponivel;

  double get _valorDigitado {
    final raw = _valorCtrl.text
        .replaceAll(RegExp(r'[^\d,.]'), '')
        .replaceAll(',', '.');
    return double.tryParse(raw) ?? 0;
  }

  double get _novoLimite {
    if (_valorDigitado <= 0) return _limiteAtual;
    if (_operacao == _OperacaoCredito.adicionar) {
      return _limiteAtual + _valorDigitado;
    }
    return _limiteAtual - _valorDigitado;
  }

  double get _novoDisponivel => _novoLimite - _usado;

  String? get _erroValidacao {
    if (_valorDigitado <= 0) return 'Informe um valor maior que zero.';
    if (_operacao == _OperacaoCredito.diminuir) {
      if (_novoLimite < _usado) {
        return 'Não é possível reduzir o limite abaixo do valor já '
            'utilizado pelo cliente (${_moedaFmt.format(_usado)}).';
      }
    }
    return null;
  }

  bool get _podeConfirmar => _valorDigitado > 0 && _erroValidacao == null;

  // ── Formatar valor no input ───────────────────────────────────

  void _formatarInput() {
    final raw = _valorCtrl.text.replaceAll(RegExp(r'[^\d]'), '');
    if (raw.isEmpty) {
      _valorCtrl.value = TextEditingValue(
        text: '',
        selection: TextSelection.collapsed(offset: 0),
      );
      return;
    }
    final cents = int.tryParse(raw) ?? 0;
    final reais = cents / 100;
    final fmt = _moedaInputFmt.format(reais).trim();
    _valorCtrl.value = TextEditingValue(
      text: fmt,
      selection: TextSelection.collapsed(offset: fmt.length),
    );
  }

  // ── Confirmar e abrir modal de confirmação ────────────────────

  Future<void> _confirmar() async {
    if (!_podeConfirmar) return;

    final confirmou = await _CreditConfirmationModal.mostrar(
      context,
      cliente: widget.cliente,
      operacao: _operacao,
      valor: _valorDigitado,
      limiteAtual: _limiteAtual,
      novoLimite: _novoLimite,
      moedaFmt: _moedaFmt,
    );
    if (confirmou != true || !mounted) return;

    setState(() => _salvando = true);
    try {
      await ComercialClientesService.atualizarLimiteCredito(
        widget.lojaId,
        widget.cliente.id,
        _novoLimite,
      );
      if (!mounted) return;
      // Exibe o toast antes de fechar o dialog (contexto do dialog
      // perde acesso ao overlay após o pop).
      DiPertinPainelFeedback.sucesso(
        context,
        'Limite de crédito atualizado com sucesso.',
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _salvando = false);
      DiPertinPainelFeedback.erro(
        context,
        'Não foi possível atualizar o limite de crédito. Tente novamente.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      backgroundColor: _superficieCard,
      elevation: 0,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 640),
        child: Form(
          key: _formKey,
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(24),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              children: [
                // Conteúdo scrollável
                SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(28, 24, 28, 28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildHeader(),
                      const SizedBox(height: 20),
                      _buildClienteInfo(),
                      const SizedBox(height: 24),
                      _buildOperacaoSelector(),
                      const SizedBox(height: 20),
                      _buildValorField(),
                      const SizedBox(height: 24),
                      _buildPrevia(),
                      const SizedBox(height: 28),
                      _buildBotoes(),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),

                // Loading overlay
                if (_salvando)
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: const Center(
                      child: SizedBox(
                        width: 40,
                        height: 40,
                        child: CircularProgressIndicator(
                          strokeWidth: 3,
                          color: _roxo,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────

  Widget _buildHeader() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [_roxo, _roxoClaro],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: _roxo.withValues(alpha: 0.25),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: const Icon(Icons.account_balance_wallet_rounded,
              color: Colors.white, size: 24),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Gerenciar limite de crédito',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: _texto,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Adicione ou reduza o limite de crédito deste cliente.',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  color: _muted,
                ),
              ),
            ],
          ),
        ),
        Container(
          margin: const EdgeInsets.only(left: 8),
          child: Material(
            color: _fundo,
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              onTap: () => Navigator.of(context).pop(),
              borderRadius: BorderRadius.circular(10),
              child: const Padding(
                padding: EdgeInsets.all(8),
                child: Icon(Icons.close_rounded, size: 20, color: _muted),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── Informações do cliente ────────────────────────────────────

  Widget _buildClienteInfo() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F3FF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _roxo.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Nome + CPF
          Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: _roxo.withValues(alpha: 0.12),
                child: Text(
                  widget.cliente.nome.isNotEmpty
                      ? widget.cliente.nome
                          .trim()
                          .split(RegExp(r'\s+'))
                          .map((e) => e[0])
                          .take(2)
                          .join()
                          .toUpperCase()
                      : 'C',
                  style: GoogleFonts.plusJakartaSans(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    color: _roxo,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.cliente.nome,
                      style: GoogleFonts.plusJakartaSans(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                        color: _texto,
                      ),
                    ),
                    if (widget.cliente.cpf != null &&
                        widget.cliente.cpf!.isNotEmpty)
                      Text(
                        ComercialClientesService.formatarCpfExibicao(
                            widget.cliente.cpf),
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          color: _muted,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Cards de resumo
          Row(
            children: [
              _buildInfoCard(
                label: 'Limite atual',
                value: _moedaFmt.format(_limiteAtual),
                cor: _roxo,
              ),
              const SizedBox(width: 10),
              _buildInfoCard(
                label: 'Valor usado',
                value: _moedaFmt.format(_usado),
                cor: _usado > 0 ? _laranja : _muted,
              ),
              const SizedBox(width: 10),
              _buildInfoCard(
                label: 'Disponível',
                value: _moedaFmt.format(_disponivelAtual),
                cor: _disponivelAtual >= 0 ? _sucesso : _erro,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard({
    required String label,
    required String value,
    required Color cor,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _borda.withValues(alpha: 0.6)),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: GoogleFonts.plusJakartaSans(
                fontWeight: FontWeight.w800,
                fontSize: 15,
                color: cor,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: _muted,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  // ── Seletor de operação ───────────────────────────────────────

  Widget _buildOperacaoSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Tipo de movimentação',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: _texto,
          ),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: _fundo,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _borda),
          ),
          child: Row(
            children: [
              _OperacaoTab(
                label: 'Adicionar limite',
                icon: Icons.add_circle_outline_rounded,
                selecionado: _operacao == _OperacaoCredito.adicionar,
                onTap: () => setState(() => _operacao = _OperacaoCredito.adicionar),
              ),
              const SizedBox(width: 4),
              _OperacaoTab(
                label: 'Diminuir limite',
                icon: Icons.remove_circle_outline_rounded,
                selecionado: _operacao == _OperacaoCredito.diminuir,
                onTap: () => setState(() => _operacao = _OperacaoCredito.diminuir),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Campo de valor ────────────────────────────────────────────

  Widget _buildValorField() {
    final erro = _erroValidacao;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Valor da alteração',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: _texto,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: erro != null ? _erro.withValues(alpha: 0.5) : _borda,
              width: erro != null ? 1.5 : 1,
            ),
          ),
          child: TextFormField(
            controller: _valorCtrl,
            onChanged: (_) {
              _formatarInput();
              setState(() {});
            },
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: GoogleFonts.plusJakartaSans(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: _texto,
              letterSpacing: -0.5,
            ),
            decoration: InputDecoration(
              hintText: 'R\$ 0,00',
              hintStyle: GoogleFonts.plusJakartaSans(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                color: _borda,
              ),
              border: InputBorder.none,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
              prefix: Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text(
                  _operacao == _OperacaoCredito.adicionar ? '+' : '−',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: _operacao == _OperacaoCredito.adicionar
                        ? _sucesso
                        : _erro,
                  ),
                ),
              ),
            ),
          ),
        ),
        if (erro != null) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.info_outline_rounded,
                  size: 14, color: _erro.withValues(alpha: 0.8)),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  erro,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    color: _erro,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  // ── Prévia ────────────────────────────────────────────────────

  Widget _buildPrevia() {
    if (_valorDigitado <= 0) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _operacao == _OperacaoCredito.adicionar
              ? _sucesso.withValues(alpha: 0.3)
              : _laranja.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                _operacao == _OperacaoCredito.adicionar
                    ? Icons.trending_up_rounded
                    : Icons.trending_down_rounded,
                size: 18,
                color: _operacao == _OperacaoCredito.adicionar
                    ? _sucesso
                    : _laranja,
              ),
              const SizedBox(width: 8),
              Text(
                'Prévia da alteração',
                style: GoogleFonts.plusJakartaSans(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: _texto,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _previaLinha('Limite atual', _moedaFmt.format(_limiteAtual)),
          _previaLinha(
            'Valor da alteração',
            '${_operacao == _OperacaoCredito.adicionar ? '+' : '−'} ${_moedaFmt.format(_valorDigitado)}',
            corValor: _operacao == _OperacaoCredito.adicionar
                ? _sucesso
                : _erro,
          ),
          const Divider(height: 24),
          _previaLinha(
            'Novo limite',
            _moedaFmt.format(_novoLimite),
            bold: true,
            corValor: _roxo,
          ),
          const SizedBox(height: 6),
          _previaLinha(
            'Disponível após alteração',
            _moedaFmt.format(_novoDisponivel),
            corValor: _novoDisponivel >= 0 ? _sucesso : _erro,
          ),
        ],
      ),
    );
  }

  Widget _previaLinha(
    String label,
    String valor, {
    bool bold = false,
    Color? corValor,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              color: _muted,
            ),
          ),
          Text(
            valor,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 14,
              fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
              color: corValor ?? _texto,
            ),
          ),
        ],
      ),
    );
  }

  // ── Botões ────────────────────────────────────────────────────

  Widget _buildBotoes() {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: () => Navigator.of(context).pop(),
            style: OutlinedButton.styleFrom(
              foregroundColor: _muted,
              side: BorderSide(color: _borda),
              padding: const EdgeInsets.symmetric(vertical: 15),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: Text(
              'Cancelar',
              style: GoogleFonts.plusJakartaSans(
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          flex: 2,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: _podeConfirmar
                  ? const LinearGradient(
                      colors: [_roxo, _roxoClaro],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    )
                  : null,
              color: _podeConfirmar ? null : _borda,
              boxShadow: _podeConfirmar
                  ? [
                      BoxShadow(
                        color: _roxo.withValues(alpha: 0.25),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : [],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _podeConfirmar ? _confirmar : null,
                borderRadius: BorderRadius.circular(14),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  child: Center(
                    child: Text(
                      'Confirmar alteração',
                      style: GoogleFonts.plusJakartaSans(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════
// OPERAÇÃO TAB
// ══════════════════════════════════════════════════════════════════

class _OperacaoTab extends StatelessWidget {
  const _OperacaoTab({
    required this.label,
    required this.icon,
    required this.selecionado,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selecionado;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: selecionado ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(11),
            boxShadow: selecionado
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : [],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color: selecionado ? _roxo : _muted,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: selecionado ? _roxo : _muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
// MODAL DE CONFIRMAÇÃO
// ══════════════════════════════════════════════════════════════════

class _CreditConfirmationModal extends StatelessWidget {
  const _CreditConfirmationModal({
    required this.cliente,
    required this.operacao,
    required this.valor,
    required this.limiteAtual,
    required this.novoLimite,
    required this.moedaFmt,
  });

  final ComercialCliente cliente;
  final _OperacaoCredito operacao;
  final double valor;
  final double limiteAtual;
  final double novoLimite;
  final NumberFormat moedaFmt;

  static Future<bool?> mostrar(
    BuildContext context, {
    required ComercialCliente cliente,
    required _OperacaoCredito operacao,
    required double valor,
    required double limiteAtual,
    required double novoLimite,
    required NumberFormat moedaFmt,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (_) => _CreditConfirmationModal(
        cliente: cliente,
        operacao: operacao,
        valor: valor,
        limiteAtual: limiteAtual,
        novoLimite: novoLimite,
        moedaFmt: moedaFmt,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final labelOperacao =
        operacao == _OperacaoCredito.adicionar ? 'adição' : 'redução';

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      backgroundColor: _superficieCard,
      elevation: 0,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: _laranja.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.warning_amber_rounded,
                        color: _laranja, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      'Confirmar alteração de crédito',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: _texto,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Você está prestes a alterar o limite de crédito deste cliente.',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  color: _muted,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 22),

              // Resumo
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F3FF),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: _roxo.withValues(alpha: 0.10)),
                ),
                child: Column(
                  children: [
                    _resumoLinha(
                      'Cliente',
                      cliente.nome,
                      boldLabel: true,
                    ),
                    const SizedBox(height: 10),
                    _resumoLinha(
                      'Limite atual',
                      moedaFmt.format(limiteAtual),
                    ),
                    const SizedBox(height: 10),
                    _resumoLinha(
                      'Alteração ($labelOperacao)',
                      '${operacao == _OperacaoCredito.adicionar ? '+' : '−'} ${moedaFmt.format(valor)}',
                      corValor: operacao == _OperacaoCredito.adicionar
                          ? _sucesso
                          : _erro,
                      bold: true,
                    ),
                    const Divider(height: 22),
                    _resumoLinha(
                      'Novo limite',
                      moedaFmt.format(novoLimite),
                      corValor: _roxo,
                      bold: true,
                      fontSize: 18,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Botões
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _muted,
                        side: BorderSide(color: _borda),
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: Text(
                        'Voltar',
                        style: GoogleFonts.plusJakartaSans(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    flex: 2,
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        gradient: const LinearGradient(
                          colors: [_roxo, _roxoClaro],
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: _roxo.withValues(alpha: 0.25),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () => Navigator.of(context).pop(true),
                          borderRadius: BorderRadius.circular(14),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 15),
                            child: Center(
                              child: Text(
                                'Confirmar',
                                style: GoogleFonts.plusJakartaSans(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                  color: Colors.white,
                                ),
                              ),
                            ),
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
    );
  }

  Widget _resumoLinha(
    String label,
    String valor, {
    Color? corValor,
    bool bold = false,
    bool boldLabel = false,
    double fontSize = 14,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 13,
            fontWeight: boldLabel ? FontWeight.w700 : FontWeight.w500,
            color: _muted,
          ),
        ),
        Text(
          valor,
          style: GoogleFonts.plusJakartaSans(
            fontSize: fontSize,
            fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
            color: corValor ?? _texto,
          ),
        ),
      ],
    );
  }
}
