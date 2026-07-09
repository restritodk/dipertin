import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../services/assinatura_gestao_comercial_refresh.dart';
import '../services/assinatura_pagamento_service.dart' as pagamento;
import '../services/firebase_functions_config.dart';
import '../theme/painel_admin_theme.dart';
import 'assinatura_confirmacao_pagamento.dart';

// ═══════════════════════════════════════════════════════════════════════════
//  AssinaturaPagamentoModal — Modal premium de pagamento (PIX + Cartão)
//  Layout: plan info à esquerda, pagamento à direita
// ═══════════════════════════════════════════════════════════════════════════

class AssinaturaPagamentoModal extends StatefulWidget {
  final Map<String, dynamic> plano;
  final String lojaId;
  final String lojaNome;
  final String ownerName;
  final String ownerEmail;
  final VoidCallback? onPagamentoAprovado;

  // Renovação
  final bool ehRenovacao;
  final String? assinaturaId;

  const AssinaturaPagamentoModal({
    super.key,
    required this.plano,
    required this.lojaId,
    required this.lojaNome,
    required this.ownerName,
    required this.ownerEmail,
    this.onPagamentoAprovado,
    this.ehRenovacao = false,
    this.assinaturaId,
  });

  static Future<void> mostrar(BuildContext context, {
    required Map<String, dynamic> plano,
    required String lojaId,
    required String lojaNome,
    required String ownerName,
    required String ownerEmail,
    VoidCallback? onPagamentoAprovado,
    bool ehRenovacao = false,
    String? assinaturaId,
  }) {
    return showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierLabel: '',
      barrierColor: Colors.black.withValues(alpha: 0.55),
      transitionDuration: const Duration(milliseconds: 280),
      pageBuilder: (ctx, anim1, anim2) => ClipRect(
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: Material(
            type: MaterialType.transparency,
            child: AssinaturaPagamentoModal(
              plano: plano,
              lojaId: lojaId,
              lojaNome: lojaNome,
              ownerName: ownerName,
              ownerEmail: ownerEmail,
              onPagamentoAprovado: onPagamentoAprovado,
              ehRenovacao: ehRenovacao,
              assinaturaId: assinaturaId,
            ),
          ),
        ),
      ),
      transitionBuilder: (ctx, anim, secAnim, child) {
        return FadeTransition(
          opacity: anim,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.93, end: 1).animate(
              CurvedAnimation(parent: anim, curve: Curves.easeOutCubic),
            ),
            child: child,
          ),
        );
      },
    );
  }

  @override
  State<AssinaturaPagamentoModal> createState() => _AssinaturaPagamentoModalState();
}

class _AssinaturaPagamentoModalState extends State<AssinaturaPagamentoModal>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;

  // Estado PIX
  bool _pixCarregando = false;
  String? _pixQrCode;
  String? _pixQrCodeBase64;
  Uint8List? _pixQrCodeBytes; // cache para evitar re-decode no rebuild
  String? _pixCopiaCola;
  String? _assinaturaId;
  String? _pixStatus;
  Timer? _pollTimer;
  Timer? _pixTimer;
  int _pixTempoRestante = 300;

  // Estado Cartão
  bool _cardCarregando = false;
  final _numCtrl = TextEditingController();
  final _nomeCtrl = TextEditingController();
  final _validadeCtrl = TextEditingController();
  final _cvvCtrl = TextEditingController();
  final _cpfCtrl = TextEditingController();

  String? _cardMensagem;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _pollTimer?.cancel();
    _pixTimer?.cancel();
    _numCtrl.dispose();
    _nomeCtrl.dispose();
    _validadeCtrl.dispose();
    _cvvCtrl.dispose();
    _cpfCtrl.dispose();
    super.dispose();
  }

  // ── GERAR PIX ──
  Future<void> _gerarPix() async {
    setState(() => _pixCarregando = true);

    try {
      if (widget.ehRenovacao && widget.assinaturaId != null) {
        final result = await pagamento.AssinaturaPagamentoService.criarRenovacaoPix(
          assinaturaId: widget.assinaturaId!,
          lojaId: widget.lojaId,
          ownerName: widget.ownerName,
          ownerEmail: widget.ownerEmail,
          ownerPhone: '',
          valor: (widget.plano['valor'] as num?)?.toDouble() ?? 0,
          planName: widget.plano['nome']?.toString() ?? 'Plano',
        );
        if (!mounted) return;
        setState(() {
          _pixQrCode = result['qrCode']?.toString();
          _pixQrCodeBase64 = result['qrCodeBase64']?.toString();
          _pixQrCodeBytes = _pixQrCodeBase64 != null
              ? base64Decode(_pixQrCodeBase64!)
              : null;
          _pixCopiaCola = result['pixCopiaECola']?.toString();
          _assinaturaId = result['assinaturaId']?.toString();
          _pixStatus = 'pendente';
          _pixCarregando = false;
          _pixTempoRestante = 300;
        });
      } else {
        final result = await pagamento.AssinaturaPagamentoService.criarPagamentoPix(
          planId: widget.plano['id']?.toString() ?? '',
          lojaId: widget.lojaId,
          lojaNome: widget.lojaNome,
          ownerName: widget.ownerName,
          ownerEmail: widget.ownerEmail,
          ownerPhone: '',
          valor: (widget.plano['valor'] as num?)?.toDouble() ?? 0,
          planName: widget.plano['nome']?.toString() ?? 'Plano',
          modulos: List<String>.from(widget.plano['modulos'] as List? ?? []),
        );
        if (!mounted) return;
        setState(() {
          _pixQrCode = result['qrCode']?.toString();
          _pixQrCodeBase64 = result['qrCodeBase64']?.toString();
          _pixQrCodeBytes = _pixQrCodeBase64 != null
              ? base64Decode(_pixQrCodeBase64!)
              : null;
          _pixCopiaCola = result['pixCopiaECola']?.toString();
          _assinaturaId = result['assinaturaId']?.toString();
          _pixStatus = 'pendente';
          _pixCarregando = false;
          _pixTempoRestante = 300;
        });
      }

      _iniciarTimerExpiracao();
      _iniciarPolling();
    } catch (e) {
      if (!mounted) return;
      setState(() => _pixCarregando = false);
      _mostrarErro('Erro ao gerar PIX', e.toString());
    }
  }

  void _iniciarPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      if (_assinaturaId == null) return;
      Map<String, dynamic> status;
      if (widget.ehRenovacao) {
        status = await pagamento.AssinaturaPagamentoService.consultarStatusRenovacaoPix(
          assinaturaId: _assinaturaId!,
        );
      } else {
        status = await pagamento.AssinaturaPagamentoService.consultarStatusPix(
          assinaturaId: _assinaturaId!,
        );
      }
      if (!mounted) return;
      final st = status['status']?.toString() ?? '';
      if (st == 'ativo') {
        _pollTimer?.cancel();
        _mostrarConfirmacao(status);
      } else if (st == 'expirado') {
        _pollTimer?.cancel();
        setState(() => _pixStatus = 'expirado');
      }
    });
  }

  void _iniciarTimerExpiracao() {
    _pixTimer?.cancel();
    _pixTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) { _pixTimer?.cancel(); return; }
      setState(() => _pixTempoRestante--);
      if (_pixTempoRestante <= 0) {
        _pixTimer?.cancel();
        _pollTimer?.cancel();
        setState(() => _pixStatus = 'expirado');
      }
    });
  }

  String _formatarTempo(int segundos) {
    final min = (segundos ~/ 60).toString().padLeft(2, '0');
    final sec = (segundos % 60).toString().padLeft(2, '0');
    return '$min:$sec';
  }

  // ── PROCESSAR CARTÃO ──
  ({int mes, int ano})? _parseValidadeCartao(String valor) {
    final partes = valor.split('/');
    if (partes.length != 2) return null;
    final mes = int.tryParse(partes[0].replaceAll(RegExp(r'\D'), '')) ?? 0;
    var ano = int.tryParse(partes[1].replaceAll(RegExp(r'\D'), '')) ?? 0;
    if (mes < 1 || mes > 12 || ano <= 0) return null;
    if (ano < 100) ano += 2000;
    final fimMes = DateTime(ano, mes + 1, 0, 23, 59, 59);
    if (fimMes.isBefore(DateTime.now())) return null;
    return (mes: mes, ano: ano);
  }

  String _resolverPaymentMethodId(String numeroCartao) {
    if (numeroCartao.startsWith('4')) return 'visa';
    if (RegExp(r'^(5[1-5]|2[2-7])').hasMatch(numeroCartao)) return 'master';
    if (RegExp(r'^3[47]').hasMatch(numeroCartao)) return 'amex';
    if (RegExp(r'^(636368|438935|504175|451416|636297|5067|4576|4011)').hasMatch(numeroCartao)) {
      return 'elo';
    }
    return 'visa';
  }

  bool _cpfValido(String cpf) {
    if (cpf.length != 11 || RegExp(r'^(\d)\1{10}$').hasMatch(cpf)) return false;
    int calcDig(int ate) {
      var soma = 0;
      for (var i = 0; i < ate; i++) {
        soma += int.parse(cpf[i]) * ((ate + 1) - i);
      }
      final r = (soma * 10) % 11;
      return r == 10 ? 0 : r;
    }
    return calcDig(9) == int.parse(cpf[9]) && calcDig(10) == int.parse(cpf[10]);
  }

  Future<void> _processarCartao() async {
    final nome = _nomeCtrl.text.trim();
    final numCartao = _numCtrl.text.replaceAll(RegExp(r'\D'), '');
    final validade = _parseValidadeCartao(_validadeCtrl.text.trim());
    final cvv = _cvvCtrl.text.replaceAll(RegExp(r'\D'), '');
    final cpf = _cpfCtrl.text.replaceAll(RegExp(r'\D'), '');

    if (nome.isEmpty) return _mostrarErro('Campo obrigatório', 'Informe o nome do titular.');
    if (numCartao.length < 13) return _mostrarErro('Cartão inválido', 'Verifique o número do cartão.');
    if (validade == null) {
      return _mostrarErro(
        'Data inválida',
        'Informe a validade no formato MM/AA (ex.: 03/33) e verifique se não está vencida.',
      );
    }
    if (cvv.length < 3) return _mostrarErro('CVV inválido', 'Verifique o código de segurança.');
    if (cpf.length != 11 || !_cpfValido(cpf)) {
      return _mostrarErro('CPF inválido', 'Informe um CPF válido com 11 dígitos.');
    }

    final mesExpiracao = validade.mes.toString().padLeft(2, '0');
    final anoExpiracao = validade.ano.toString();
    final paymentMethodId = _resolverPaymentMethodId(numCartao);

    setState(() => _cardCarregando = true);

    try {
      if (widget.ehRenovacao && widget.assinaturaId != null) {
        final result = await pagamento.AssinaturaPagamentoService.processarRenovacaoCartao(
          assinaturaId: widget.assinaturaId!,
          lojaId: widget.lojaId,
          ownerName: widget.ownerName,
          ownerEmail: widget.ownerEmail,
          valor: (widget.plano['valor'] as num?)?.toDouble() ?? 0,
          planName: widget.plano['nome']?.toString() ?? 'Plano',
          numeroCartao: numCartao,
          nomeTitular: nome,
          mesExpiracao: mesExpiracao,
          anoExpiracao: anoExpiracao,
          cvv: cvv,
          cpf: cpf,
          paymentMethodId: paymentMethodId,
        );

        if (!mounted) return;
        final aprovado = result['aprovado'] == true;
        if (aprovado) {
          setState(() => _cardCarregando = false);
          _mostrarConfirmacao(result);
        } else {
          setState(() {
            _cardCarregando = false;
            _cardMensagem = result['mensagem']?.toString() ?? 'Pagamento recusado.';
          });
          _mostrarErro('Pagamento recusado', _cardMensagem!);
        }
      } else {
        final result = await pagamento.AssinaturaPagamentoService.processarCartao(
          planId: widget.plano['id']?.toString() ?? '',
          lojaId: widget.lojaId,
          lojaNome: widget.lojaNome,
          ownerName: widget.ownerName,
          ownerEmail: widget.ownerEmail,
          valor: (widget.plano['valor'] as num?)?.toDouble() ?? 0,
          planName: widget.plano['nome']?.toString() ?? 'Plano',
          modulos: List<String>.from(widget.plano['modulos'] as List? ?? []),
          numeroCartao: numCartao,
          nomeTitular: nome,
          mesExpiracao: mesExpiracao,
          anoExpiracao: anoExpiracao,
          cvv: cvv,
          cpf: cpf,
          paymentMethodId: paymentMethodId,
        );

        if (!mounted) return;
        final aprovado = result['aprovado'] == true;
        if (aprovado) {
          setState(() => _cardCarregando = false);
          _mostrarConfirmacao(result);
        } else {
          setState(() {
            _cardCarregando = false;
            _cardMensagem = result['mensagem']?.toString() ?? 'Pagamento recusado.';
          });
          _mostrarErro('Pagamento recusado', _cardMensagem!);
        }
      }
    } on CallableHttpException catch (e) {
      if (!mounted) return;
      setState(() => _cardCarregando = false);
      _mostrarErro('Erro no pagamento', mensagemCallableHttpException(e));
    } catch (e) {
      if (!mounted) return;
      setState(() => _cardCarregando = false);
      _mostrarErro('Erro no pagamento', e.toString());
    }
  }

  void _mostrarConfirmacao(Map<String, dynamic> dados) {
    _pixTimer?.cancel();
    _pollTimer?.cancel();
    AssinaturaGestaoComercialRefresh.instance.notificarPagamentoAprovado();
    Navigator.of(context).pop();
    AssinaturaConfirmacaoPagamento.mostrar(
      context,
      aprovado: true,
      planoNome: widget.plano['nome']?.toString() ?? 'Plano',
      mensagem: dados['mensagem']?.toString() ?? 'Pagamento aprovado! Seu plano já está ativo.',
      onAcessarGestao: widget.onPagamentoAprovado,
    );
  }

  void _mostrarErro(String titulo, String mensagem) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.error_outline_rounded, color: DiPertinTheme.errorRedAlt, size: 24),
            const SizedBox(width: 12),
            Text(titulo, style: GoogleFonts.plusJakartaSans(fontSize: 18, fontWeight: FontWeight.w600)),
          ],
        ),
        content: Text(mensagem, style: GoogleFonts.plusJakartaSans(fontSize: 14, color: DiPertinTheme.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('OK', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  // ── COPIAR PIX ──
  void _copiarPix() {
    if (_pixCopiaCola == null) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.content_copy_rounded, color: DiPertinTheme.primaryRoxo, size: 22),
            const SizedBox(width: 12),
            Text('Código PIX', style: GoogleFonts.plusJakartaSans(fontSize: 18, fontWeight: FontWeight.w600)),
          ],
        ),
        content: SelectableText(
          _pixCopiaCola!,
          style: GoogleFonts.plusJakartaSans(fontSize: 13, color: DiPertinTheme.textPrimary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Fechar', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600, color: DiPertinTheme.primaryRoxo)),
          ),
        ],
      ),
    );
  }

  // ── PLAN INFO (lado esquerdo) ──
  Widget _buildPlanInfo() {
    final plan = widget.plano;
    final name = plan['nome']?.toString() ?? 'Plano';
    final desc = plan['descricao']?.toString() ?? '';
    final valor = (plan['valor'] as num?)?.toDouble() ?? 0;
    final vs = NumberFormat('#,##0.00', 'pt_BR').format(valor);

    return Container(
      padding: const EdgeInsets.fromLTRB(36, 32, 24, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Badge do plano
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [DiPertinTheme.primaryRoxo.withValues(alpha: 0.10), DiPertinTheme.secondaryLaranja.withValues(alpha: 0.06)],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: DiPertinTheme.primaryRoxo.withValues(alpha: 0.12)),
            ),
            child: Text(
              'PLANO SELECIONADO',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: DiPertinTheme.primaryRoxo,
                letterSpacing: 1.2,
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Nome do plano
          Text(
            name,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: DiPertinTheme.textPrimary,
              height: 1.15,
            ),
          ),

          // Descrição
          if (desc.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              desc,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                color: DiPertinTheme.textSecondary,
                height: 1.4,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],

          const SizedBox(height: 24),

          // Preço
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                'R\$',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: DiPertinTheme.primaryRoxo,
                ),
              ),
              const SizedBox(width: 2),
              Text(
                vs,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 40,
                  fontWeight: FontWeight.w800,
                  color: DiPertinTheme.textPrimary,
                  height: 1,
                ),
              ),
              const SizedBox(width: 6),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '/mês',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: DiPertinTheme.textSecondary,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),
          Text(
            'Cobrança mensal recorrente',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              color: DiPertinTheme.textSecondary.withValues(alpha: 0.7),
            ),
          ),

          const SizedBox(height: 28),

          // Divisória sutil
          Container(height: 1, color: DiPertinTheme.borderSoft.withValues(alpha: 0.5)),

          const SizedBox(height: 24),

          // Módulos inclusos (busca em tempo real)
          Text(
            'Módulos inclusos',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: DiPertinTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 12),

          StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('modulos_planos')
                .doc(widget.plano['id']?.toString() ?? 'inexistente')
                .snapshots(),
            builder: (ctx, snapMod) {
              List<String> modulosReais = [];
              if (snapMod.hasData && snapMod.data!.exists) {
                final raw = snapMod.data!.data()?['modulos'] as List? ?? [];
                modulosReais = List<String>.from(raw);
              }

              if (modulosReais.isEmpty) {
                return Text(
                  'Este plano não possui módulos adicionais cadastrados.',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 12, color: DiPertinTheme.textSecondary),
                );
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 200),
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: modulosReais.map((mod) => _buildModuloItem(mod)).toList(),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),

          const Spacer(),

          // Selo de segurança
          Row(
            children: [
              Container(
                width: 28, height: 28,
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F5E9),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.lock_rounded, size: 16, color: Color(0xFF2E7D32)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Pagamento processado pelo Mercado Pago',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    color: DiPertinTheme.textSecondary.withValues(alpha: 0.7),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildModuloItem(String modulo) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(
            width: 20, height: 20,
            decoration: BoxDecoration(
              color: DiPertinTheme.primaryRoxo.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(Icons.check_rounded, size: 14, color: DiPertinTheme.primaryRoxo),
          ),
          const SizedBox(width: 10),
          Text(
            modulo,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: DiPertinTheme.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  // ── PAINEL DE PAGAMENTO (lado direito) ──
  Widget _buildPaymentPanel() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF9F8FC),
        borderRadius: const BorderRadius.only(
          topRight: Radius.circular(28),
          bottomRight: Radius.circular(28),
        ),
      ),
      child: Column(
        children: [
          // Header do pagamento
          Container(
            padding: const EdgeInsets.fromLTRB(28, 28, 28, 0),
            child: Row(
              children: [
                Container(
                  width: 42, height: 42,
                  decoration: BoxDecoration(
                    color: DiPertinTheme.primaryRoxo,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.credit_card_rounded, size: 22, color: Colors.white),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Pagamento',
                          style: GoogleFonts.plusJakartaSans(fontSize: 18, fontWeight: FontWeight.w700, color: DiPertinTheme.textPrimary)),
                      const SizedBox(height: 1),
                      Text(widget.plano['nome']?.toString() ?? 'Plano',
                          style: GoogleFonts.plusJakartaSans(fontSize: 12, color: DiPertinTheme.textSecondary)),
                    ],
                  ),
                ),
                // Botão fechar
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      width: 36, height: 36,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: DiPertinTheme.borderSoft),
                      ),
                      child: const Icon(Icons.close_rounded, size: 18, color: DiPertinTheme.textSecondary),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          // Abas
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: DiPertinTheme.borderSoft),
              ),
              child: TabBar(
                controller: _tabCtrl,
                labelColor: Colors.white,
                unselectedLabelColor: DiPertinTheme.textSecondary,
                indicator: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  gradient: const LinearGradient(
                    colors: [DiPertinTheme.primaryRoxo, DiPertinTheme.primaryRoxoMedio],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                labelStyle: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w600),
                unselectedLabelStyle: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w500),
                tabs: const [
                  Tab(text: 'PIX'),
                  Tab(text: 'Cartão'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),

          // Conteúdo
          Expanded(
            child: TabBarView(
              controller: _tabCtrl,
              children: [
                _buildPixTab(),
                _buildCardTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════
  //  TAB PIX
  // ═══════════════════════════════════════════════════
  Widget _buildPixTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          if (_pixCarregando)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: CircularProgressIndicator(),
            )
          else if (_pixStatus == 'expirado')
            _buildPixExpirado()
          else if (_pixQrCode == null)
            _buildPixInicial()
          else ...[
            _buildPixQrCode(),
            const SizedBox(height: 16),
            _buildPixStatus(),
            const SizedBox(height: 16),
            _buildPixCopiaCola(),
          ],
        ],
      ),
    );
  }

  Widget _buildPixInicial() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64, height: 64,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: DiPertinTheme.primaryRoxo.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Image.network(
              'https://logopng.com.br/logos/mercado-pago-62.png',
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => const Icon(Icons.pix_rounded, size: 32, color: DiPertinTheme.primaryRoxo),
            ),
          ),
          const SizedBox(height: 16),
          Text('Pague com PIX', style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text('Use o QR Code para pagar com qualquer banco.',
              style: GoogleFonts.plusJakartaSans(fontSize: 12, color: DiPertinTheme.textSecondary)),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity, height: 48,
            child: _BotaoGradiente(
              label: 'Gerar QR Code PIX',
              onTap: _gerarPix,
            ),
          ),
          const SizedBox(height: 12),
          _buildLockText(),
        ],
      ),
    );
  }

  Widget _buildPixExpirado() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56, height: 56,
            decoration: BoxDecoration(
              color: DiPertinTheme.errorRedAlt.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.timer_off_rounded, size: 28, color: DiPertinTheme.errorRedAlt),
          ),
          const SizedBox(height: 16),
          Text('PIX expirado', style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text('O tempo de pagamento expirou.',
              style: GoogleFonts.plusJakartaSans(fontSize: 12, color: DiPertinTheme.textSecondary)),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity, height: 48,
            child: _BotaoGradiente(label: 'Gerar novo PIX', onTap: _gerarPix),
          ),
        ],
      ),
    );
  }

  Widget _buildPixQrCode() {
    return RepaintBoundary(
      child: Container(
        width: 180, height: 180,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: DiPertinTheme.borderSoft),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 12, offset: const Offset(0, 4)),
          ],
        ),
        child: _pixQrCodeBytes != null
            ? Image.memory(
                _pixQrCodeBytes!,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => const Icon(Icons.qr_code_rounded, size: 100, color: DiPertinTheme.primaryRoxo),
              )
            : const Icon(Icons.qr_code_rounded, size: 100, color: DiPertinTheme.primaryRoxo),
      ),
    );
  }

  Widget _buildPixStatus() {
    final tempo = _formatarTempo(_pixTempoRestante);
    final isUrgente = _pixTempoRestante <= 60;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isUrgente
            ? DiPertinTheme.errorRedAlt.withValues(alpha: 0.08)
            : DiPertinTheme.secondaryLaranja.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isUrgente
              ? DiPertinTheme.errorRedAlt.withValues(alpha: 0.15)
              : DiPertinTheme.secondaryLaranja.withValues(alpha: 0.15),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 14, height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: isUrgente ? DiPertinTheme.errorRedAlt : DiPertinTheme.secondaryLaranja,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'Aguardando pagamento',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: isUrgente ? DiPertinTheme.errorRedAlt : DiPertinTheme.secondaryLaranja,
            ),
          ),
          Container(
            margin: const EdgeInsets.only(left: 10),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: isUrgente
                  ? DiPertinTheme.errorRedAlt.withValues(alpha: 0.12)
                  : Colors.white.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              tempo,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                fontFeatures: const [FontFeature.tabularFigures()],
                color: isUrgente ? DiPertinTheme.errorRedAlt : DiPertinTheme.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPixCopiaCola() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: DiPertinTheme.borderSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Código PIX', style: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.w600, color: DiPertinTheme.textSecondary)),
              const Spacer(),
              GestureDetector(
                onTap: _copiarPix,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.copy_rounded, size: 13, color: DiPertinTheme.primaryRoxo),
                    const SizedBox(width: 4),
                    Text('Copiar', style: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.w600, color: DiPertinTheme.primaryRoxo)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _pixCopiaCola ?? '',
            style: GoogleFonts.plusJakartaSans(fontSize: 10, color: DiPertinTheme.textPrimary),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildLockText() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.lock_outline_rounded, size: 11, color: DiPertinTheme.textSecondary.withValues(alpha: 0.5)),
        const SizedBox(width: 4),
        Text('Processado pelo Mercado Pago',
            style: GoogleFonts.plusJakartaSans(fontSize: 10, color: DiPertinTheme.textSecondary.withValues(alpha: 0.5))),
      ],
    );
  }

  // ═══════════════════════════════════════════════════
  //  TAB CARTÃO
  // ═══════════════════════════════════════════════════
  Widget _buildCardTab() {
    if (_cardCarregando) {
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Número do cartão
          _buildFieldLabel('Número do cartão'),
          const SizedBox(height: 6),
          TextField(
            controller: _numCtrl,
            keyboardType: TextInputType.number,
            decoration: _inputDeco('0000 0000 0000 0000', Icons.credit_card_rounded),
            maxLength: 19,
            onChanged: (v) {
              final digits = v.replaceAll(RegExp(r'\D'), '');
              if (digits.length != v.length) {
                final buf = StringBuffer();
                for (var i = 0; i < digits.length; i++) {
                  if (i > 0 && i % 4 == 0) buf.write(' ');
                  buf.write(digits[i]);
                }
                _numCtrl.value = TextEditingValue(
                  text: buf.toString(),
                  selection: TextSelection.collapsed(offset: buf.length),
                );
              }
            },
          ),
          const SizedBox(height: 14),

          // Validade + CVV
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildFieldLabel('Validade'),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _validadeCtrl,
                      keyboardType: TextInputType.number,
                      decoration: _inputDeco('MM/AA', Icons.calendar_today_rounded),
                      maxLength: 5,
                      onChanged: (v) {
                        final digits = v.replaceAll(RegExp(r'\D'), '');
                        final limited = digits.length > 4
                            ? digits.substring(0, 4)
                            : digits;
                        final buf = StringBuffer();
                        for (var i = 0; i < limited.length; i++) {
                          if (i == 2) buf.write('/');
                          buf.write(limited[i]);
                        }
                        final formatted = buf.toString();
                        if (formatted != v) {
                          _validadeCtrl.value = TextEditingValue(
                            text: formatted,
                            selection: TextSelection.collapsed(
                              offset: formatted.length,
                            ),
                          );
                        }
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildFieldLabel('CVV'),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _cvvCtrl,
                      keyboardType: TextInputType.number,
                      obscureText: true,
                      obscuringCharacter: '*',
                      decoration: _inputDeco('123', Icons.security_rounded),
                      maxLength: 4,
                      onChanged: (v) {
                        final digits = v.replaceAll(RegExp(r'\D'), '');
                        if (digits != v) {
                          _cvvCtrl.value = TextEditingValue(
                            text: digits,
                            selection: TextSelection.collapsed(
                              offset: digits.length,
                            ),
                          );
                        }
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Nome do titular
          _buildFieldLabel('Nome do titular'),
          const SizedBox(height: 6),
          TextField(
            controller: _nomeCtrl,
            textCapitalization: TextCapitalization.characters,
            decoration: _inputDeco('Nome como está no cartão', Icons.person_rounded),
            maxLength: 40,
          ),
          const SizedBox(height: 14),

          // CPF
          _buildFieldLabel('CPF do titular'),
          const SizedBox(height: 6),
          TextField(
            controller: _cpfCtrl,
            keyboardType: TextInputType.number,
            decoration: _inputDeco('000.000.000-00', Icons.badge_rounded),
            maxLength: 14,
            onChanged: (v) {
              final digits = v.replaceAll(RegExp(r'\D'), '');
              if (digits.length != v.length) {
                var buf = '';
                for (var i = 0; i < digits.length; i++) {
                  if (i == 3 || i == 6) buf += '.';
                  if (i == 9) buf += '-';
                  buf += digits[i];
                }
                _cpfCtrl.value = TextEditingValue(
                  text: buf,
                  selection: TextSelection.collapsed(offset: buf.length),
                );
              }
            },
          ),
          const SizedBox(height: 20),

          // Botão pagar
          SizedBox(
            width: double.infinity, height: 50,
            child: _BotaoGradiente(
              label: 'Pagar R\$ ${NumberFormat('#,##0.00', 'pt_BR').format((widget.plano['valor'] as num?)?.toDouble() ?? 0)}',
              onTap: _processarCartao,
            ),
          ),
          const SizedBox(height: 8),
          _buildLockText(),
        ],
      ),
    );
  }

  Widget _buildFieldLabel(String label) {
    return Text(label, style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w600, color: DiPertinTheme.textPrimary));
  }

  InputDecoration _inputDeco(String hint, IconData icon) {
    return InputDecoration(
      hintText: hint,
      hintStyle: GoogleFonts.plusJakartaSans(fontSize: 12, color: DiPertinTheme.textSecondary.withValues(alpha: 0.5)),
      prefixIcon: Icon(icon, size: 16, color: DiPertinTheme.textSecondary.withValues(alpha: 0.6)),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: DiPertinTheme.borderSoft),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: DiPertinTheme.borderSoft),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: DiPertinTheme.primaryRoxo, width: 1.5),
      ),
      counterText: '',
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final modalWidth = (screenSize.width * 0.88).clamp(680.0, 960.0);
    final modalHeight = (screenSize.height * 0.80).clamp(560.0, 720.0);

    return Center(
      child: Container(
        width: modalWidth,
        constraints: BoxConstraints(maxHeight: modalHeight),
        margin: const EdgeInsets.symmetric(horizontal: 32),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 80, offset: const Offset(0, 30)),
            BoxShadow(color: DiPertinTheme.primaryRoxo.withValues(alpha: 0.08), blurRadius: 60, offset: const Offset(0, 15)),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white,
                  const Color(0xFFFDFBFF),
                  Colors.white,
                ],
              ),
            ),
            child: LayoutBuilder(
              builder: (_, constraints) {
                final useSplit = constraints.maxWidth > 680;
                if (useSplit) {
                  return Row(
                    children: [
                      // Lado esquerdo — Plan Info
                      SizedBox(
                        width: constraints.maxWidth * 0.42,
                        child: _buildPlanInfo(),
                      ),
                      // Divisória vertical
                      Container(width: 1, color: DiPertinTheme.borderSoft.withValues(alpha: 0.5)),
                      // Lado direito — Pagamento
                      Expanded(child: _buildPaymentPanel()),
                    ],
                  );
                }
                // Layout empilhado para telas menores
                return Column(
                  children: [
                    SizedBox(
                      height: 240,
                      child: _buildPlanInfo(),
                    ),
                    const Divider(height: 1, color: DiPertinTheme.borderSoft),
                    Expanded(child: _buildPaymentPanel()),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  Botão Gradiente Reutilizável
// ═══════════════════════════════════════════════════════════════════════════
class _BotaoGradiente extends StatefulWidget {
  final String label;
  final VoidCallback onTap;

  const _BotaoGradiente({required this.label, required this.onTap});

  @override
  State<_BotaoGradiente> createState() => _BotaoGradienteState();
}

class _BotaoGradienteState extends State<_BotaoGradiente> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          transform: _hover ? (Matrix4.diagonal3Values(1.02, 1.02, 1)) : Matrix4.identity(),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: const LinearGradient(
              colors: [
                DiPertinTheme.primaryRoxoEscuro,
                DiPertinTheme.primaryRoxo,
                DiPertinTheme.secondaryLaranja,
              ],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            boxShadow: _hover
                ? [BoxShadow(color: DiPertinTheme.primaryRoxo.withValues(alpha: 0.35), blurRadius: 16, spreadRadius: 1)]
                : [BoxShadow(color: DiPertinTheme.primaryRoxo.withValues(alpha: 0.15), blurRadius: 10, offset: const Offset(0, 4))],
          ),
          child: Center(
            child: Text(
              widget.label,
              style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }
}
