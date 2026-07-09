import 'package:depertin_web/models/comercial_cliente.dart';
import 'package:depertin_web/services/comercial_clientes_service.dart';
import 'package:depertin_web/theme/painel_admin_theme.dart';
import 'package:depertin_web/widgets/dipertin_painel_feedback.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

/// Abre o modal principal para remover crédito do cliente.
Future<bool?> mostrarRemoverCreditoModal(
  BuildContext context, {
  required String lojaId,
  required ComercialCliente cliente,
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (_) => _RemoverCreditoModal(
      lojaId: lojaId,
      cliente: cliente,
    ),
  );
}

// =============================================================================
// MODAL PRINCIPAL — Remover Crédito
// =============================================================================

class _RemoverCreditoModal extends StatefulWidget {
  const _RemoverCreditoModal({
    required this.lojaId,
    required this.cliente,
  });

  final String lojaId;
  final ComercialCliente cliente;

  @override
  State<_RemoverCreditoModal> createState() => _RemoverCreditoModalState();
}

class _RemoverCreditoModalState extends State<_RemoverCreditoModal>
    with SingleTickerProviderStateMixin {
  late AnimationController _animCtrl;
  late Animation<double> _scaleAnim;
  late Animation<double> _fadeAnim;

  final _valorCtrl = TextEditingController();
  final _moeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

  double _valorRemover = 0;
  String? _erro;

  bool get _isMobile =>
      MediaQuery.of(context).size.width < 600;

  // Cores
  static const _roxo = PainelAdminTheme.roxo;
  static const _laranja = PainelAdminTheme.laranja;
  static const _fundoCard = Color(0xFFF8F9FC);
  static const _texto = Color(0xFF1E1B4B);
  static const _muted = Color(0xFF64748B);
  static const _verde = Color(0xFF16A34A);
  static const _vermelho = Color(0xFFDC2626);

  // Dados do cliente
  double get _limiteAtual => widget.cliente.limiteCredito;
  double get _creditoUsado => widget.cliente.creditoUtilizado;
  double get _creditoDisponivel =>
      (_limiteAtual - _creditoUsado).clamp(0, double.infinity);
  double get _novoLimite => (_limiteAtual - _valorRemover).clamp(0, double.infinity);
  double get _novoDisponivel => (_novoLimite - _creditoUsado).clamp(0, double.infinity);

  bool get _podeConfirmar =>
      _valorRemover > 0 &&
      _novoLimite >= _creditoUsado &&
      _novoLimite >= 0;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _scaleAnim = CurvedAnimation(
      parent: _animCtrl,
      curve: Curves.elasticOut,
    );
    _fadeAnim = CurvedAnimation(
      parent: _animCtrl,
      curve: Curves.easeOut,
    );
    _animCtrl.forward();
  }

  @override
  void dispose() {
    _valorCtrl.dispose();
    _animCtrl.dispose();
    super.dispose();
  }

  void _formatarValor(String v) {
    final digits = v.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) {
      setState(() {
        _valorRemover = 0;
        _erro = null;
      });
      return;
    }
    final valorEmCentavos = int.parse(digits);
    final valor = valorEmCentavos / 100;
    final msg = _validarValor(valor);

    // Atualiza o campo com a máscara
    _valorCtrl.value = TextEditingValue(
      text: _moeda.format(valor),
      selection: TextSelection.collapsed(offset: _moeda.format(valor).length),
    );

    setState(() {
      _valorRemover = valor;
      _erro = msg;
    });
  }

  String? _validarValor(double valor) {
    if (valor <= 0) return 'Informe um valor maior que zero.';
    if (valor > _limiteAtual) {
      return 'O valor não pode ser maior que o limite atual (${_moeda.format(_limiteAtual)}).';
    }
    final novoLimite = _limiteAtual - valor;
    if (novoLimite < _creditoUsado) {
      final minimo = _limiteAtual - _creditoUsado;
      return 'Não é possível remover esse valor, pois o novo limite '
          'ficaria abaixo do crédito já utilizado pelo cliente.\n'
          'Valor máximo permitido: ${_moeda.format(minimo)}';
    }
    return null;
  }

  Future<void> _confirmarRemocao() async {
    // Abre modal de confirmação POR CIMA do primeiro modal
    // (não pop() antes — senão o contexto é destruído)
    final confirmado = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (_) => _RemoverCreditoConfirmModal(
        cliente: widget.cliente,
        valorRemover: _valorRemover,
        limiteAtual: _limiteAtual,
        novoLimite: _novoLimite,
        creditoUsado: _creditoUsado,
        novoDisponivel: _novoDisponivel,
      ),
    );

    if (confirmado != true) return;
    if (!mounted) return;

    try {
      await ComercialClientesService.atualizarLimiteCredito(
        widget.lojaId,
        widget.cliente.id,
        _novoLimite,
      );

      if (!mounted) return;

      DiPertinPainelFeedback.sucesso(
        context,
        'Limite de crédito reduzido com sucesso.',
      );

      // Só pop() após tudo — contexto ainda válido
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      DiPertinPainelFeedback.erro(
        context,
        'Não foi possível remover o crédito. Tente novamente.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final maxWidth = _isMobile ? w : 520.0;

    return FadeTransition(
      opacity: _fadeAnim,
      child: ScaleTransition(
        scale: _scaleAnim,
        child: Align(
            child: Container(
              constraints: BoxConstraints(
                maxWidth: maxWidth,
                maxHeight: _isMobile ? double.infinity : 640,
              ),
              margin: _isMobile
                  ? EdgeInsets.zero
                  : const EdgeInsets.symmetric(vertical: 40),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(_isMobile ? 0 : 20),
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
                child: _isMobile ? _buildMobile() : _buildDesktop(),
              ),
            ),
        ),
      ),
    );
  }

  // ─── Desktop ───

  Widget _buildDesktop() {
    return Column(
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
                _clientInfoCard(),
                const SizedBox(height: 16),
                _valueInput(),
                const SizedBox(height: 16),
                _previewCard(),
              ],
            ),
          ),
        ),
        _footer(),
      ],
    );
  }

  // ─── Mobile ───

  Widget _buildMobile() {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _clientInfoCard(),
                  const SizedBox(height: 16),
                  _valueInput(),
                  const SizedBox(height: 16),
                  _previewCard(),
                ],
              ),
            ),
          ),
          _footer(),
        ],
      ),
    );
  }

  // ─── Header ───

  Widget _header() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: const Color(0xFFE2E8F0), width: 0.5)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: _vermelho.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.remove_circle_outline_rounded,
                size: 22, color: _vermelho),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Remover crédito do cliente',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: _texto,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Reduza o limite de crédito disponível deste cliente com segurança.',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    color: _muted,
                  ),
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
              child: Icon(Icons.close_rounded, size: 18, color: _muted),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Card de informações do cliente ───

  Widget _clientInfoCard() {
    final cpfFormatado = ComercialClientesService.formatarCpfExibicao(widget.cliente.cpf);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _fundoCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: _roxo.withValues(alpha: 0.1),
                child: Text(
                  _iniciais(widget.cliente.nome),
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: _roxo,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.cliente.nome,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: _texto,
                      ),
                    ),
                    if (cpfFormatado != '—' || (widget.cliente.telefone != null && widget.cliente.telefone!.isNotEmpty))
                      Text(
                        [
                          if (cpfFormatado != '—') 'CPF: $cpfFormatado',
                          if (widget.cliente.telefone != null && widget.cliente.telefone!.isNotEmpty)
                            widget.cliente.telefone!,
                        ].join(' · '),
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 11,
                          color: _muted,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(height: 1),
          const SizedBox(height: 14),
          _infoLinha('Limite atual', _moeda.format(_limiteAtual), _roxo),
          const SizedBox(height: 8),
          _infoLinha('Crédito usado', _moeda.format(_creditoUsado), _laranja),
          const SizedBox(height: 8),
          _infoLinha(
            'Crédito disponível',
            _moeda.format(_creditoDisponivel),
            _creditoDisponivel > 0 ? _verde : _muted,
          ),
        ],
      ),
    );
  }

  Widget _infoLinha(String label, String valor, Color cor) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: _muted,
          ),
        ),
        Text(
          valor,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: cor,
          ),
        ),
      ],
    );
  }

  // ─── Campo de valor ───

  Widget _valueInput() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Valor a remover do limite',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: _texto,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _erro != null ? _vermelho : const Color(0xFFE2E8F0),
              width: _erro != null ? 1.5 : 1,
            ),
          ),
          child: TextField(
            controller: _valorCtrl,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onChanged: _formatarValor,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: _texto,
              letterSpacing: -0.5,
            ),
            decoration: InputDecoration(
              hintText: 'R\$ 0,00',
              hintStyle: GoogleFonts.plusJakartaSans(
                color: const Color(0xFFCBD5E1),
                fontSize: 24,
                fontWeight: FontWeight.w800,
              ),
              prefix: Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Text(
                  'R\$',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: _muted,
                  ),
                ),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
            ),
          ),
        ),
        if (_erro != null) ...[
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.error_outline_rounded, size: 14, color: _vermelho),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  _erro!,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: _vermelho,
                    height: 1.3,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  // ─── Preview ───

  Widget _previewCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _roxo.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _roxo.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.preview_rounded, size: 16, color: _roxo),
              const SizedBox(width: 6),
              Text(
                'Prévia da alteração',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: _roxo,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _previaLinha('Limite atual', _moeda.format(_limiteAtual), _texto),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(Icons.remove_rounded, size: 14, color: _vermelho),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  'Valor a remover',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: _muted,
                  ),
                ),
              ),
              Text(
                _moeda.format(_valorRemover),
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: _vermelho,
                ),
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 6),
            child: Divider(height: 1),
          ),
          _previaLinha('Novo limite', _moeda.format(_novoLimite), _roxo),
          const SizedBox(height: 6),
          _previaLinha('Crédito usado', _moeda.format(_creditoUsado), _laranja),
          const SizedBox(height: 6),
          _previaLinha('Disponível após alteração',
              _moeda.format(_novoDisponivel),
              _novoDisponivel > 0 ? _verde : _muted),
        ],
      ),
    );
  }

  Widget _previaLinha(String label, String valor, Color cor) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: _muted,
          ),
        ),
        Text(
          valor,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: cor,
          ),
        ),
      ],
    );
  }

  // ─── Footer ───

  Widget _footer() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: const Color(0xFFE2E8F0), width: 0.5),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => Navigator.pop(context),
              style: OutlinedButton.styleFrom(
                foregroundColor: _muted,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: const Color(0xFFE2E8F0)),
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
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: FilledButton(
              onPressed: _podeConfirmar ? _confirmarRemocao : null,
              style: FilledButton.styleFrom(
                backgroundColor: _vermelho,
                foregroundColor: Colors.white,
                disabledBackgroundColor: _vermelho.withValues(alpha: 0.3),
                disabledForegroundColor: Colors.white.withValues(alpha: 0.5),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
              child: Text(
                'Confirmar remoção',
                style: GoogleFonts.plusJakartaSans(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
            ),
          ),
        ],
      ),
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

class _RemoverCreditoConfirmModal extends StatefulWidget {
  const _RemoverCreditoConfirmModal({
    required this.cliente,
    required this.valorRemover,
    required this.limiteAtual,
    required this.novoLimite,
    required this.creditoUsado,
    required this.novoDisponivel,
  });

  final ComercialCliente cliente;
  final double valorRemover;
  final double limiteAtual;
  final double novoLimite;
  final double creditoUsado;
  final double novoDisponivel;

  @override
  State<_RemoverCreditoConfirmModal> createState() =>
      _RemoverCreditoConfirmModalState();
}

class _RemoverCreditoConfirmModalState
    extends State<_RemoverCreditoConfirmModal>
    with SingleTickerProviderStateMixin {
  late AnimationController _animCtrl;
  late Animation<double> _scaleAnim;
  late Animation<double> _fadeAnim;

  final _moeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

  static const _roxo = PainelAdminTheme.roxo;
  static const _laranja = PainelAdminTheme.laranja;
  static const _texto = Color(0xFF1E1B4B);
  static const _muted = Color(0xFF64748B);
  static const _verde = Color(0xFF16A34A);
  static const _vermelho = Color(0xFFDC2626);
  static const _fundoCard = Color(0xFFF8F9FC);

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _scaleAnim = CurvedAnimation(
      parent: _animCtrl,
      curve: Curves.elasticOut,
    );
    _fadeAnim = CurvedAnimation(
      parent: _animCtrl,
      curve: Curves.easeOut,
    );
    _animCtrl.forward();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnim,
      child: ScaleTransition(
        scale: _scaleAnim,
        child: AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
          contentPadding: EdgeInsets.zero,
          content: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeader(),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildAlert(),
                        const SizedBox(height: 16),
                        _buildSummary(),
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
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: const Color(0xFFE2E8F0), width: 0.5),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: _vermelho.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(Icons.warning_amber_rounded,
                size: 24, color: _vermelho),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Confirmar remoção de crédito',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: _texto,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Essa ação afetará o limite disponível para novas compras.',
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
    );
  }

  Widget _buildAlert() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _vermelho.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _vermelho.withValues(alpha: 0.15)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, size: 18, color: _vermelho),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Você está prestes a reduzir o limite de crédito '
              'de ${widget.cliente.nome}. Esta ação afetará o '
              'limite disponível para novas compras.',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                color: _texto,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummary() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _fundoCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
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
                  widget.cliente.nome.isNotEmpty
                      ? widget.cliente.nome.substring(0, 1).toUpperCase()
                      : '?',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: _roxo,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                widget.cliente.nome,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: _texto,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(height: 1),
          const SizedBox(height: 14),
          _resumoLinha('Limite atual', _moeda.format(widget.limiteAtual), _roxo),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.remove_rounded, size: 14, color: _vermelho),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  'Valor removido',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: _muted,
                  ),
                ),
              ),
              Text(
                _moeda.format(widget.valorRemover),
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: _vermelho,
                ),
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Divider(height: 1),
          ),
          _resumoLinha('Novo limite', _moeda.format(widget.novoLimite), _roxo),
          const SizedBox(height: 8),
          _resumoLinha('Crédito usado', _moeda.format(widget.creditoUsado), _laranja),
          const SizedBox(height: 8),
          _resumoLinha(
            'Novo disponível',
            _moeda.format(widget.novoDisponivel),
            widget.novoDisponivel > 0 ? _verde : _muted,
          ),
        ],
      ),
    );
  }

  Widget _resumoLinha(String label, String valor, Color cor) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: _muted,
          ),
        ),
        Text(
          valor,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: cor,
          ),
        ),
      ],
    );
  }

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: const Color(0xFFE2E8F0), width: 0.5),
        ),
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
                  side: BorderSide(color: const Color(0xFFE2E8F0)),
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
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: FilledButton(
              onPressed: () {
                Navigator.pop(context, true);
              },
              style: FilledButton.styleFrom(
                backgroundColor: _vermelho,
                foregroundColor: Colors.white,
                disabledBackgroundColor: _vermelho.withValues(alpha: 0.3),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
                    child: Text(
                      'Confirmar',
                      style: GoogleFonts.plusJakartaSans(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
