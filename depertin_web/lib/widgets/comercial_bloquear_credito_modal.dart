import 'package:depertin_web/models/comercial_cliente.dart';
import 'package:depertin_web/services/comercial_clientes_service.dart';
import 'package:depertin_web/theme/painel_admin_theme.dart';
import 'package:depertin_web/widgets/dipertin_painel_feedback.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

/// Bloquear ou desbloquear o crédito do cliente.
///
/// Retorna `true` se a operação foi concluída com sucesso.
Future<bool?> mostrarBloquearCreditoModal(
  BuildContext context, {
  required String lojaId,
  required ComercialCliente cliente,
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (_) => _BloquearCreditoModal(
      lojaId: lojaId,
      cliente: cliente,
    ),
  );
}

// =============================================================================
// MODAL PRINCIPAL — Bloquear / Desbloquear Crédito
// =============================================================================

class _BloquearCreditoModal extends StatefulWidget {
  const _BloquearCreditoModal({
    required this.lojaId,
    required this.cliente,
  });

  final String lojaId;
  final ComercialCliente cliente;

  @override
  State<_BloquearCreditoModal> createState() => _BloquearCreditoModalState();
}

class _BloquearCreditoModalState extends State<_BloquearCreditoModal>
    with SingleTickerProviderStateMixin {
  late AnimationController _animCtrl;
  late Animation<double> _scaleAnim;
  late Animation<double> _fadeAnim;

  bool _salvando = false;

  final _moeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

  static const _roxo = PainelAdminTheme.roxo;
  static const _laranja = PainelAdminTheme.laranja;
  static const _texto = Color(0xFF1E1B4B);
  static const _muted = Color(0xFF64748B);
  static const _verde = Color(0xFF16A34A);
  static const _vermelho = Color(0xFFDC2626);
  static const _fundoCard = Color(0xFFF8F9FC);

  bool get _jaBloqueado => widget.cliente.status == 'bloqueado';
  bool get _isMobile => MediaQuery.of(context).size.width < 600;

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

  Future<void> _executar() async {
    setState(() => _salvando = true);

    try {
      await ComercialClientesService.bloquear(
        widget.lojaId,
        widget.cliente.id,
        bloquear: !_jaBloqueado,
      );

      if (!mounted) return;

      DiPertinPainelFeedback.sucesso(
        context,
        _jaBloqueado
            ? 'Crédito desbloqueado com sucesso.'
            : 'Crédito bloqueado com sucesso.',
      );

      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      DiPertinPainelFeedback.erro(
        context,
        _jaBloqueado
            ? 'Não foi possível desbloquear o crédito. Tente novamente.'
            : 'Não foi possível bloquear o crédito. Tente novamente.',
      );
      setState(() => _salvando = false);
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
              maxHeight: _isMobile ? double.infinity : 560,
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
                _alertBanner(),
                const SizedBox(height: 16),
                _clientInfoCard(),
              ],
            ),
          ),
        ),
        _footer(),
      ],
    );
  }

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
                  _alertBanner(),
                  const SizedBox(height: 16),
                  _clientInfoCard(),
                ],
              ),
            ),
          ),
          _footer(),
        ],
      ),
    );
  }

  Widget _header() {
    final cor = _jaBloqueado ? _verde : _vermelho;
    final icone = _jaBloqueado
        ? Icons.lock_open_rounded
        : Icons.lock_outline_rounded;
    final titulo = _jaBloqueado
        ? 'Desbloquear crédito do cliente'
        : 'Bloquear crédito do cliente';

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0), width: 0.5)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: cor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icone, size: 24, color: cor),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titulo,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: _texto,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _jaBloqueado
                      ? 'Restabeleça o acesso ao crediário deste cliente.'
                      : 'Impeça novas compras no crediário sem remover o limite.',
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

  Widget _alertBanner() {
    final cor = _jaBloqueado ? _verde : _vermelho;
    final mensagem = _jaBloqueado
        ? 'Tem certeza que deseja desbloquear o crédito deste cliente? '
            'Ele poderá voltar a realizar compras no crediário, respeitando o limite disponível.'
        : 'Tem certeza que deseja bloquear o crédito deste cliente? '
            'Ele não poderá realizar novas compras no crediário até que o crédito seja desbloqueado. '
            'O limite atual e o histórico de parcelas serão preservados.';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cor.withValues(alpha: 0.15)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, size: 18, color: cor),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              mensagem,
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

  Widget _clientInfoCard() {
    final cpfFormatado =
        ComercialClientesService.formatarCpfExibicao(widget.cliente.cpf);
    final limite = widget.cliente.limiteCredito;
    final usado = widget.cliente.creditoUtilizado;
    final disponivel = widget.cliente.creditoDisponivel;
    final atraso = widget.cliente.pendencias
        .where((p) => !p.paga)
        .fold<double>(0, (s, p) => s + p.valor);

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
                    if (cpfFormatado != '—')
                      Padding(
                        padding: const EdgeInsets.only(top: 1),
                        child: Text(
                          'CPF: $cpfFormatado',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 11,
                            color: _muted,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              _statusBadge(),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(height: 1),
          const SizedBox(height: 14),
          _infoLinha('Limite atual', _moeda.format(limite), _roxo),
          const SizedBox(height: 8),
          _infoLinha('Crédito usado', _moeda.format(usado), _laranja),
          const SizedBox(height: 8),
          _infoLinha('Crédito disponível', _moeda.format(disponivel),
              disponivel > 0 ? _verde : _muted),
          const SizedBox(height: 8),
          _infoLinha('Valor em aberto', _moeda.format(atraso),
              atraso > 0 ? _vermelho : _muted),
        ],
      ),
    );
  }

  Widget _statusBadge() {
    if (widget.cliente.status != 'bloqueado') return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _vermelho.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _vermelho.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.lock_rounded, size: 12, color: _vermelho),
          const SizedBox(width: 4),
          Text(
            'BLOQUEADO',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: _vermelho,
              letterSpacing: 0.5,
            ),
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

  Widget _footer() {
    final label = _jaBloqueado ? 'Confirmar desbloqueio' : 'Confirmar bloqueio';
    final cor = _jaBloqueado ? _verde : _vermelho;

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFFE2E8F0), width: 0.5)),
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: _salvando ? null : () => Navigator.pop(context),
              style: OutlinedButton.styleFrom(
                foregroundColor: _muted,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: const BorderSide(color: Color(0xFFE2E8F0)),
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
              onPressed: _salvando ? null : _executar,
              style: FilledButton.styleFrom(
                backgroundColor: cor,
                foregroundColor: Colors.white,
                disabledBackgroundColor: cor.withValues(alpha: 0.3),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
              child: _salvando
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      label,
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
// BADGE DE STATUS — Reutilizável
// =============================================================================

/// Badge visual para indicar se o crédito do cliente está bloqueado.
class CreditStatusBadge extends StatelessWidget {
  const CreditStatusBadge({
    super.key,
    required this.cliente,
    this.compact = false,
  });

  final ComercialCliente cliente;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (cliente.status != 'bloqueado') return const SizedBox.shrink();

    const vermelho = Color(0xFFDC2626);
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.lock_rounded, size: compact ? 10 : 12, color: vermelho),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              compact ? 'Bloqueado' : 'Crédito bloqueado',
              style: GoogleFonts.plusJakartaSans(
                fontSize: compact ? 10 : 11,
                fontWeight: FontWeight.w700,
                color: vermelho,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// WARNING — Exibido no PDV ao tentar vender para cliente bloqueado
// =============================================================================

/// Aviso exibido quando um cliente com crédito bloqueado tenta comprar no
/// crediário. Ideal para ser usado no PDV.
class CreditBlockedWarning extends StatelessWidget {
  const CreditBlockedWarning({super.key, this.onDesbloquear});

  final VoidCallback? onDesbloquear;

  @override
  Widget build(BuildContext context) {
    const vermelho = Color(0xFFDC2626);
    const laranja = PainelAdminTheme.laranja;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: vermelho.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: vermelho.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: vermelho.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child:
                    const Icon(Icons.lock_outline_rounded, size: 20, color: vermelho),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Crédito bloqueado',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF1E1B4B),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'O crédito deste cliente está bloqueado. Desbloqueie o crédito '
                      'para permitir novas compras no crediário.',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        color: const Color(0xFF64748B),
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (onDesbloquear != null) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: onDesbloquear,
                icon: const Icon(Icons.lock_open_rounded, size: 16),
                label: const Text('Desbloquear crédito'),
                style: FilledButton.styleFrom(
                  backgroundColor: laranja,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
