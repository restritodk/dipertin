import 'dart:convert';
import 'package:http/http.dart' as http;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../models/cliente_assinatura_model.dart';
import '../models/cobranca_assinatura_model.dart';
import '../utils/lojista_painel_context.dart';
import '../navigation/painel_navigation_scope.dart';
import '../widgets/assinatura_pagamento_modal.dart';

// ──────────────────────────────────────────────
//  HELPERS
// ──────────────────────────────────────────────

final _currency = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
final _date = DateFormat('dd/MM/yyyy', 'pt_BR');

String _fmtMoeda(double v) => _currency.format(v);
String _fmtData(dynamic ts) {
  if (ts == null) return '—';
  if (ts is Timestamp) return _date.format(ts.toDate());
  if (ts is DateTime) return _date.format(ts);
  return '—';
}

Color _corStatus(String status) {
  switch (status) {
    case 'ativo':
    case 'paga':
    case 'Ativa':
      return const Color(0xFF16A34A);
    case 'em_atraso':
    case 'vencida':
      return const Color(0xFFF04438);
    case 'suspenso':
    case 'bloqueada':
      return const Color(0xFFDC2626);
    case 'cancelado':
    case 'cancelada':
      return const Color(0xFF94A3B8);
    case 'vencer_em_breve':
    case 'em_aberto':
      return const Color(0xFF0EA5E9);
    case 'pagamento_pendente':
      return const Color(0xFFFF8F00);
    default:
      return const Color(0xFF64748B);
  }
}

Widget _statusBadge(String label, {Color? cor, Color? fundo}) {
  final c = cor ?? _corStatus(label);
  final f = fundo ?? c.withValues(alpha: 0.1);
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: f,
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: c.withValues(alpha: 0.2)),
    ),
    child: Text(
      label,
      style: GoogleFonts.plusJakartaSans(
        fontSize: 11.5,
        fontWeight: FontWeight.w600,
        color: c,
        height: 1.2,
      ),
    ),
  );
}

DataColumn _col(String label) => DataColumn(
      label: Text(label,
          style: GoogleFonts.plusJakartaSans(
              fontSize: 11.5, fontWeight: FontWeight.w600, color: const Color(0xFF64748B))),
    );

DataCell _cell(String text, {bool bold = false}) => DataCell(
      Text(text,
          style: GoogleFonts.plusJakartaSans(
              fontSize: 12.5, fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
              color: const Color(0xFF1A1A2E))),
    );

Widget _acaoIcon(IconData icon, String tooltip, VoidCallback onTap) {
  return Tooltip(
    message: tooltip,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 32, height: 32,
        decoration: BoxDecoration(
          color: const Color(0xFF6A1B9A).withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, size: 16, color: const Color(0xFF6A1B9A)),
      ),
    ),
  );
}

// ══════════════════════════════════════════════
//  SCREEN PRINCIPAL
// ══════════════════════════════════════════════

class LojistaMinhaLojaScreen extends StatefulWidget {
  const LojistaMinhaLojaScreen({super.key});

  @override
  State<LojistaMinhaLojaScreen> createState() => _LojistaMinhaLojaScreenState();
}

class _LojistaMinhaLojaScreenState extends State<LojistaMinhaLojaScreen> {
  @override
  Widget build(BuildContext context) {
    return LojistaUidLojaBuilder(
      builder: (ctx, authUid, uidLoja, dadosUsuario) {
        if (dadosUsuario == null || dadosUsuario.isEmpty) {
          return const Scaffold(
            backgroundColor: Color(0xFFF5F4F8),
            body: Center(child: CircularProgressIndicator(color: Color(0xFF6A1B9A))),
          );
        }
        return _ConteudoMinhaLoja(uidLoja: uidLoja, dadosUsuario: dadosUsuario);
      },
    );
  }
}

class _ConteudoMinhaLoja extends StatelessWidget {
  const _ConteudoMinhaLoja({required this.uidLoja, required this.dadosUsuario});
  final String uidLoja;
  final Map<String, dynamic> dadosUsuario;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F4F8),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header ──
              _HeaderLoja(uidLoja: uidLoja, dadosUsuario: dadosUsuario),
              const SizedBox(height: 28),

              // ── KPIs ──
              _DashboardKpis(uidLoja: uidLoja, dadosUsuario: dadosUsuario),
              const SizedBox(height: 28),

              // ── Alertas ──
              _AlertasInteligentes(uidLoja: uidLoja),
              const SizedBox(height: 28),

              // ── Conteúdo principal ──
              _buildMainContent(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMainContent(BuildContext context) {
    return LayoutBuilder(
      builder: (ctx, constraints) {
        final wide = constraints.maxWidth > 900;

        return Column(
          children: [
            // Linha 1: Resumo Assinatura + Cobranças
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: _CardAssinaturaResumo(uidLoja: uidLoja),
                ),
                if (wide) const SizedBox(width: 24),
                if (wide)
                  Expanded(
                    flex: 2,
                    child: _CardCobrancas(uidLoja: uidLoja),
                  ),
              ],
            ),
            const SizedBox(height: 24),

            // Linha 2: Extrato de Pagamentos (full width)
            _CardExtratoFinanceiro(uidLoja: uidLoja),
            const SizedBox(height: 24),

            // Linha 3: Dados Empresa + Endereço
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: _CardDadosEmpresa(uidLoja: uidLoja, dadosUsuario: dadosUsuario),
                ),
                if (wide) const SizedBox(width: 24),
                if (wide)
                  Expanded(
                    flex: 2,
                    child: _CardEndereco(uidLoja: uidLoja, dadosUsuario: dadosUsuario),
                  ),
              ],
            ),
            const SizedBox(height: 24),

            // Linha 4: Integrações + Contatos
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: _CardIntegracoes(uidLoja: uidLoja),
                ),
                if (wide) const SizedBox(width: 24),
                if (wide)
                  Expanded(
                    flex: 2,
                    child: _CardContatos(dadosUsuario: dadosUsuario),
                  ),
              ],
            ),
            const SizedBox(height: 24),

            // Linha 5: Suporte (full width)
            _CardSuporte(),

            // Mobile: seções que ficaram de fora
            if (!wide) ...[
              const SizedBox(height: 24),
              _CardCobrancas(uidLoja: uidLoja),
              const SizedBox(height: 24),
              _CardEndereco(uidLoja: uidLoja, dadosUsuario: dadosUsuario),
              const SizedBox(height: 24),
              _CardContatos(dadosUsuario: dadosUsuario),
            ],
          ],
        );
      },
    );
  }
}

// ══════════════════════════════════════════════
//  HEADER PREMIUM
// ══════════════════════════════════════════════

class _HeaderLoja extends StatelessWidget {
  const _HeaderLoja({required this.uidLoja, required this.dadosUsuario});
  final String uidLoja;
  final Map<String, dynamic> dadosUsuario;

  @override
  Widget build(BuildContext context) {
    final nomeLoja = dadosUsuario['loja_nome']?.toString() ??
        dadosUsuario['nome_loja']?.toString() ??
        dadosUsuario['nome']?.toString() ??
        'Minha Loja';
    final fotoUrl = dadosUsuario['foto']?.toString() ??
        dadosUsuario['foto_perfil']?.toString() ??
        '';
    final statusLoja = dadosUsuario['status_loja']?.toString() ?? '';
    final razaoSocial = dadosUsuario['razao_social']?.toString() ?? '';

    final statusLabel = switch (statusLoja) {
      'aprovada' || 'aprovado' => 'Loja Ativa',
      'pendente' => 'Pendente',
      'bloqueada' => 'Bloqueada',
      _ => statusLoja,
    };
    final statusCor = statusLoja == 'aprovada' || statusLoja == 'aprovado'
        ? const Color(0xFF16A34A)
        : statusLoja == 'bloqueada'
            ? const Color(0xFFDC2626)
            : const Color(0xFF0EA5E9);

    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF4A148C),
            Color(0xFF6A1B9A),
            Color(0xFF8E24AA),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF6A1B9A).withValues(alpha: 0.25),
            blurRadius: 24,
            offset: const Offset(0, 10),
            spreadRadius: -4,
          ),
        ],
      ),
      child: Row(
        children: [
          // Logo
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
              image: fotoUrl.isNotEmpty
                  ? DecorationImage(image: NetworkImage(fotoUrl), fit: BoxFit.cover)
                  : null,
            ),
            child: fotoUrl.isEmpty
                ? const Icon(Icons.store_rounded, size: 28, color: Colors.white70)
                : null,
          ),
          const SizedBox(width: 20),
          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  nomeLoja,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    height: 1.15,
                  ),
                ),
                if (razaoSocial.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    razaoSocial,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: Colors.white.withValues(alpha: 0.7),
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                _StatusRow(uidLoja: uidLoja, statusLabel: statusLabel, statusCor: statusCor),
              ],
            ),
          ),
          // Botão Editar
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
            ),
            child: IconButton(
              icon: const Icon(Icons.edit_outlined, size: 20, color: Colors.white),
              onPressed: () => context.navegarPainel('/comercial_configuracoes'),
              tooltip: 'Editar informações',
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({required this.uidLoja, required this.statusLabel, required this.statusCor});
  final String uidLoja;
  final String statusLabel;
  final Color statusCor;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('assinaturas_clientes')
          .where('store_id', isEqualTo: uidLoja)
          .snapshots(),
      builder: (ctx, snap) {
        String planName = '';
        String subStatus = '';
        Timestamp? nextBilling;

        if (snap.hasData && snap.data!.docs.isNotEmpty) {
          final a = _melhorAssinaturaModel(snap.data!)!;
          planName = a.planName;
          subStatus = a.statusExibicaoRotulo;
          nextBilling = a.nextBillingDate;
        }

        return Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            // Status loja
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: statusCor.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 6, height: 6,
                    decoration: BoxDecoration(color: statusCor, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    statusLabel,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
            // Plano
            if (planName.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF8F00).withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  planName,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white,
                  ),
                ),
              ),
            // Status assinatura
            if (subStatus.isNotEmpty)
              _statusBadge(
                subStatus,
                cor: subStatus == 'Ativo' || subStatus == 'Vence em breve'
                    ? const Color(0xFF16A34A)
                    : subStatus == 'Vencido'
                        ? const Color(0xFFF04438)
                        : const Color(0xFFFF8F00),
                fundo: Colors.white.withValues(alpha: 0.15),
              ),
            // Próxima cobrança
            if (nextBilling != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.calendar_today_rounded, size: 10, color: Colors.white.withValues(alpha: 0.7)),
                    const SizedBox(width: 4),
                    Text(
                      'Próx: ${_fmtData(nextBilling)}',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11, fontWeight: FontWeight.w500, color: Colors.white.withValues(alpha: 0.85),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════
//  HELPERS DE SELEÇÃO
// ═══════════════════════════════════════════════════════════════

/// Retorna o doc de assinatura mais relevante (ativo/em_atraso primeiro).
QueryDocumentSnapshot<Map<String, dynamic>> _melhorAssinatura(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
  // Preferir assinaturas ativas ou em atraso (não canceladas/pendentes)
  for (final doc in docs) {
    final st = doc.data()['status'] as String?;
    if (st == 'ativo' || st == 'em_atraso') return doc;
  }
  // Fallback: a primeira (mais antiga ou única)
  return docs.first;
}

/// Cria um [ClienteAssinaturaModel] a partir da melhor assinatura disponível.
ClienteAssinaturaModel? _melhorAssinaturaModel(
    QuerySnapshot<Map<String, dynamic>>? snap) {
  if (snap == null || snap.docs.isEmpty) return null;
  final doc = snap.docs.length == 1
      ? snap.docs.first
      : _melhorAssinatura(snap.docs);
  return ClienteAssinaturaModel.fromFirestore(doc);
}

// ═══════════════════════════════════════════════════════════════
//  MODAL DETALHES DA ASSINATURA
// ═══════════════════════════════════════════════════════════════

void _mostrarModalDetalhesAssinatura(BuildContext context, ClienteAssinaturaModel a) {
  showDialog(
    context: context,
    barrierDismissible: true,
    barrierColor: Colors.black.withValues(alpha: 0.5),
    builder: (ctx) {
      return Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Container(
          width: 520,
          constraints: const BoxConstraints(maxHeight: 640),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Header gradiente ──
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(28, 28, 28, 20),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF4A148C), Color(0xFF6A1B9A), Color(0xFF8E24AA)],
                  ),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.assignment_rounded, size: 22, color: Colors.white),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Resumo da Assinatura',
                              style: GoogleFonts.plusJakartaSans(
                                  fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white)),
                          if (a.planName.isNotEmpty)
                            Text(a.planName,
                                style: GoogleFonts.plusJakartaSans(
                                    fontSize: 13, fontWeight: FontWeight.w500,
                                    color: Colors.white.withValues(alpha: 0.8))),
                        ],
                      ),
                    ),
                    GestureDetector(
                      onTap: () => Navigator.of(ctx).pop(),
                      child: Container(
                        width: 32, height: 32,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.close_rounded, size: 18, color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
              // ── Body scroll ──
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(28, 20, 28, 28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Status
                      _linhaModal('Situação', a.statusExibicaoRotulo,
                          valorCor: _corStatus(a.statusExibicao)),
                      const SizedBox(height: 16),
                      // Grid 2 colunas
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: _colunaModalEsquerda(a)),
                          const SizedBox(width: 16),
                          Expanded(child: _colunaModalDireita(a)),
                        ],
                      ),
                      const SizedBox(height: 20),
                      // Informações complementares
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF5F4F8),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Informações complementares',
                                style: GoogleFonts.plusJakartaSans(
                                    fontSize: 13, fontWeight: FontWeight.w700, color: const Color(0xFF1A1A2E))),
                            const SizedBox(height: 12),
                            _infoComplementar('Loja', a.storeName.isNotEmpty ? a.storeName : '—'),
                            if (a.modulosExtras.isNotEmpty)
                              _infoComplementar('Módulos extras', a.modulosExtras.join(', ')),
                            _infoComplementar('Tolerância', '${a.toleranciaDias} ${a.toleranciaDias == 1 ? 'dia' : 'dias'}'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

Widget _colunaModalEsquerda(ClienteAssinaturaModel a) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _infoModal('Valor mensal', _fmtMoeda(a.monthlyAmount)),
      const SizedBox(height: 12),
      _infoModal('Próxima cobrança', a.nextBillingDateExibir),
      const SizedBox(height: 12),
      _infoModal('Dias restantes', a.diasAteVencimento >= 0 ? '${a.diasAteVencimento} dias' : '—'),
    ],
  );
}

Widget _colunaModalDireita(ClienteAssinaturaModel a) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _infoModal('Contratação', a.createdAtExibir),
      const SizedBox(height: 12),
      _infoModal('Gateway', a.gateway),
      const SizedBox(height: 12),
      _infoModal('Renovação', a.status == 'ativo' ? 'Automática' : '—'),
    ],
  );
}

Widget _linhaModal(String label, String value, {Color? valorCor}) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    decoration: BoxDecoration(
      color: const Color(0xFF6A1B9A).withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xFF6A1B9A).withValues(alpha: 0.1)),
    ),
    child: Row(
      children: [
        Text(label,
            style: GoogleFonts.plusJakartaSans(
                fontSize: 13, fontWeight: FontWeight.w500, color: const Color(0xFF64748B))),
        const Spacer(),
        Text(value,
            style: GoogleFonts.plusJakartaSans(
                fontSize: 14, fontWeight: FontWeight.w700, color: valorCor ?? const Color(0xFF1A1A2E))),
      ],
    ),
  );
}

Widget _infoModal(String label, String value, {Color? valorCor}) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label,
          style: GoogleFonts.plusJakartaSans(
              fontSize: 11.5, fontWeight: FontWeight.w500,
              color: const Color(0xFF64748B).withValues(alpha: 0.8))),
      const SizedBox(height: 3),
      Text(value,
          style: GoogleFonts.plusJakartaSans(
              fontSize: 14, fontWeight: FontWeight.w700, color: valorCor ?? const Color(0xFF1A1A2E))),
    ],
  );
}

Widget _infoComplementar(String label, String value) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 110,
          child: Text(label,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 12, fontWeight: FontWeight.w500,
                  color: const Color(0xFF64748B))),
        ),
        Expanded(
          child: Text(value,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 12, fontWeight: FontWeight.w600, color: const Color(0xFF1A1A2E))),
        ),
      ],
    ),
  );
}

// ═══════════════════════════════════════════════════════════════
//  MODAL HISTÓRICO DE COBRANÇAS
// ═══════════════════════════════════════════════════════════════

void _mostrarModalHistoricoCobrancas(BuildContext context, String uidLoja) {
  showDialog(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black.withValues(alpha: 0.5),
    builder: (ctx) => _ModalHistoricoCobrancas(uidLoja: uidLoja),
  );
}

class _ModalHistoricoCobrancas extends StatefulWidget {
  const _ModalHistoricoCobrancas({required this.uidLoja});
  final String uidLoja;

  @override
  State<_ModalHistoricoCobrancas> createState() => _ModalHistoricoCobrancasState();
}

class _ModalHistoricoCobrancasState extends State<_ModalHistoricoCobrancas> {
  String _filtroStatus = 'todos';
  String _busca = '';
  int _paginaAtual = 0;
  static const int _porPagina = 10;
  final _buscaController = TextEditingController();

  @override
  void dispose() {
    _buscaController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Container(
        width: 960,
        constraints: const BoxConstraints(maxHeight: 680),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
        ),
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('assinaturas_cobrancas')
              .where('store_id', isEqualTo: widget.uidLoja)
              .snapshots(),
          builder: (ctx, snap) {
            final docs = snap.data?.docs ?? [];

            var filtrados = docs.where((doc) {
              if (_filtroStatus == 'todos') return true;
              final st = doc.data()['status'] as String? ?? '';
              return st == _filtroStatus;
            }).toList();

            if (_busca.trim().isNotEmpty) {
              final q = _busca.trim().toLowerCase();
              filtrados = filtrados.where((doc) {
                final d = doc.data();
                final fatura = (d['fatura'] as String? ?? '').toLowerCase();
                final plano = (d['plan_name'] as String? ?? '').toLowerCase();
                return fatura.contains(q) || plano.contains(q);
              }).toList();
            }

            filtrados.sort((a, b) {
              final va = a.data()['vencimento'] as Timestamp?;
              final vb = b.data()['vencimento'] as Timestamp?;
              if (va == null && vb == null) return 0;
              if (va == null) return 1;
              if (vb == null) return -1;
              return vb.toDate().compareTo(va.toDate());
            });

            final totalFiltrados = filtrados.length;
            final totalPaginas = (totalFiltrados / _porPagina).ceil().clamp(1, 999);
            final inicio = _paginaAtual * _porPagina;
            final paginaDocs = filtrados.skip(inicio).take(_porPagina).toList();

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildHeader(ctx, totalFiltrados),
                _buildFiltros(),
                if (snap.hasError)
                  Padding(
                    padding: const EdgeInsets.all(40),
                    child: Center(
                      child: Text('Erro ao carregar cobranças.',
                          style: GoogleFonts.plusJakartaSans(fontSize: 14, color: const Color(0xFFF04438))),
                    ),
                  )
                else if (!snap.hasData)
                  const Padding(
                    padding: EdgeInsets.all(40),
                    child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                else if (paginaDocs.isEmpty)
                  _buildVazio()
                else
                  _buildTabela(paginaDocs),
                if (paginaDocs.isNotEmpty) _buildPaginacao(totalPaginas),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, int total) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(28, 24, 20, 16),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF4A148C), Color(0xFF6A1B9A), Color(0xFF8E24AA)],
        ),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Row(
        children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.receipt_long_rounded, size: 20, color: Colors.white),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Histórico de Cobranças',
                    style: GoogleFonts.plusJakartaSans(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white)),
                Text('$total ${total == 1 ? 'cobrança encontrada' : 'cobranças encontradas'}',
                    style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w500,
                        color: Colors.white.withValues(alpha: 0.75))),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              width: 32, height: 32,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.close_rounded, size: 18, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFiltros() {
    const filtros = [
      _FiltroOpcao('todos', 'Todas'),
      _FiltroOpcao('paga', 'Pagas'),
      _FiltroOpcao('em_aberto', 'Em aberto'),
      _FiltroOpcao('vencida', 'Vencidas'),
      _FiltroOpcao('cancelada', 'Canceladas'),
    ];

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 14, 24, 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.grey.shade200, width: 0.5)),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          ...filtros.map((f) => _PremiumFiltroChip(
            label: f.label,
            ativo: _filtroStatus == f.codigo,
            onTap: () => setState(() {
              _filtroStatus = f.codigo;
              _paginaAtual = 0;
            }),
          )),
          const Spacer(),
          SizedBox(
            width: 240,
            height: 36,
            child: TextField(
              controller: _buscaController,
              onChanged: (v) => setState(() {
                _busca = v;
                _paginaAtual = 0;
              }),
              style: GoogleFonts.plusJakartaSans(fontSize: 13, color: const Color(0xFF1A1A2E)),
              decoration: InputDecoration(
                hintText: 'Buscar fatura ou plano...',
                hintStyle: GoogleFonts.plusJakartaSans(fontSize: 12, color: const Color(0xFF94A3B8)),
                prefixIcon: Icon(Icons.search_rounded, size: 18, color: const Color(0xFF94A3B8)),
                suffixIcon: _busca.isNotEmpty
                    ? IconButton(
                        icon: Icon(Icons.close_rounded, size: 16, color: const Color(0xFF94A3B8)),
                        onPressed: () {
                          _buscaController.clear();
                          setState(() { _busca = ''; _paginaAtual = 0; });
                        },
                      )
                    : null,
                filled: true,
                fillColor: const Color(0xFFF5F4F8),
                contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabela(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    return Flexible(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
        child: DataTable(
          columnSpacing: 20,
          headingRowHeight: 40,
          dataRowMinHeight: 44,
          dataRowMaxHeight: 48,
          headingRowColor: WidgetStatePropertyAll(const Color(0xFFF5F4F8).withValues(alpha: 0.6)),
          border: TableBorder(
            horizontalInside: BorderSide(color: Colors.grey.shade200.withValues(alpha: 0.3)),
          ),
          columns: [
            _col('Fatura'),
            _col('Plano'),
            _col('Valor'),
            _col('Vencimento'),
            _col('Pagamento'),
            _col('Status'),
            _col(''),
          ],
          rows: docs.map((doc) {
            final d = doc.data();
            final fatura = d['fatura'] as String? ?? '#N/A';
            final plano = d['plan_name'] as String? ?? '—';
            final valor = (d['valor'] as num?)?.toDouble() ?? 0;
            final vencimento = d['vencimento'] as Timestamp?;
            final status = d['status'] as String? ?? '';
            final pagoEm = d['pago_em'] as Timestamp? ?? d['atualizado_em'] as Timestamp?;
            final statusInfo = StatusCobranca.fromCodigo(status);
            final isPaga = status == 'paga' || status == 'pago';

            return DataRow(cells: [
              _cell(fatura, bold: true),
              _cell(plano),
              _cell(_fmtMoeda(valor), bold: true),
              _cell(_fmtData(vencimento)),
              _cell(isPaga ? _fmtData(pagoEm) : '—'),
              DataCell(_statusBadge(statusInfo.rotulo, cor: statusInfo.cor, fundo: statusInfo.fundo)),
              DataCell(Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _acaoIcon(Icons.visibility_outlined, 'Ver detalhes', () {
                    Navigator.of(context).pop();
                    _mostrarModalDetalheCobranca(context, CobrancaAssinatura.fromFirestore(doc));
                  }),
                  if (isPaga) ...[
                    const SizedBox(width: 4),
                    _acaoIcon(Icons.download_rounded, 'Baixar recibo', () {}),
                  ],
                ],
              )),
            ]);
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildVazio() {
    return Flexible(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 60),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.receipt_long_rounded, size: 56, color: const Color(0xFFCBD5E1)),
              const SizedBox(height: 16),
              Text('Nenhuma cobrança encontrada',
                  style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w600, color: const Color(0xFF1A1A2E))),
              const SizedBox(height: 6),
              Text(_busca.isNotEmpty || _filtroStatus != 'todos'
                  ? 'Tente alterar os filtros ou a busca.'
                  : 'Você ainda não possui cobranças registradas.',
                  style: GoogleFonts.plusJakartaSans(fontSize: 13, color: const Color(0xFF64748B))),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPaginacao(int totalPaginas) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 18),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Colors.grey.shade200, width: 0.5)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left_rounded, size: 20),
            onPressed: _paginaAtual > 0 ? () => setState(() => _paginaAtual--) : null,
            style: IconButton.styleFrom(
              foregroundColor: _paginaAtual > 0 ? const Color(0xFF6A1B9A) : const Color(0xFFCBD5E1),
              backgroundColor: _paginaAtual > 0 ? const Color(0xFF6A1B9A).withValues(alpha: 0.08) : Colors.transparent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              minimumSize: const Size(36, 36),
            ),
          ),
          const SizedBox(width: 8),
          Text('${_paginaAtual + 1} de $totalPaginas',
              style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFF1A1A2E))),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.chevron_right_rounded, size: 20),
            onPressed: _paginaAtual < totalPaginas - 1 ? () => setState(() => _paginaAtual++) : null,
            style: IconButton.styleFrom(
              foregroundColor: _paginaAtual < totalPaginas - 1 ? const Color(0xFF6A1B9A) : const Color(0xFFCBD5E1),
              backgroundColor: _paginaAtual < totalPaginas - 1 ? const Color(0xFF6A1B9A).withValues(alpha: 0.08) : Colors.transparent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              minimumSize: const Size(36, 36),
            ),
          ),
        ],
      ),
    );
  }
}

class _FiltroOpcao {
  final String codigo;
  final String label;
  const _FiltroOpcao(this.codigo, this.label);
}

class _PremiumFiltroChip extends StatelessWidget {
  const _PremiumFiltroChip({required this.label, required this.ativo, required this.onTap});
  final String label;
  final bool ativo;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: ativo ? const Color(0xFF6A1B9A) : const Color(0xFFF5F4F8),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: ativo ? const Color(0xFF6A1B9A) : const Color(0xFFE2E8F0),
          ),
        ),
        child: Text(label,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: ativo ? Colors.white : const Color(0xFF64748B),
            )),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
//  MODAL DETALHE DA COBRANÇA
// ═══════════════════════════════════════════════════════════════

void _mostrarModalDetalheCobranca(BuildContext context, CobrancaAssinatura c) {
  showDialog(
    context: context,
    barrierDismissible: true,
    barrierColor: Colors.black.withValues(alpha: 0.5),
    builder: (ctx) {
      return Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Container(
          width: 420,
          constraints: const BoxConstraints(maxHeight: 560),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(24, 22, 18, 16),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft, end: Alignment.bottomRight,
                    colors: [Color(0xFF4A148C), Color(0xFF6A1B9A), Color(0xFF8E24AA)],
                  ),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 38, height: 38,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.receipt_rounded, size: 18, color: Colors.white),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Detalhe da Cobrança',
                              style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white)),
                          Text(c.fatura,
                              style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w500,
                                  color: Colors.white.withValues(alpha: 0.75))),
                        ],
                      ),
                    ),
                    GestureDetector(
                      onTap: () => Navigator.of(ctx).pop(),
                      child: Container(
                        width: 30, height: 30,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.close_rounded, size: 16, color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
              // Body
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _linhaModal('Fatura', c.fatura),
                      const SizedBox(height: 14),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _infoModal('Plano', c.planoNome),
                              const SizedBox(height: 12),
                              _infoModal('Valor', c.valorExibicao),
                            ],
                          )),
                          const SizedBox(width: 16),
                          Expanded(child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _infoModal('Vencimento', c.vencimentoExibicao),
                              const SizedBox(height: 12),
                              _infoModal('Status', c.status.rotulo,
                                  valorCor: c.status.cor),
                            ],
                          )),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF5F4F8),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Cliente',
                                style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w700, color: const Color(0xFF1A1A2E))),
                            const SizedBox(height: 8),
                            _infoComplementar('Nome', c.clienteNome),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

// ══════════════════════════════════════════════
//  PremiumDashboardCard (altura fixa 170px)
// ══════════════════════════════════════════════

class PremiumDashboardCard extends StatefulWidget {
  const PremiumDashboardCard({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.value,
    this.subtitle,
    this.secondaryText,
    this.badge,
    this.badgeColor,
    this.onTap,
  });
  final IconData icon;
  final Color iconColor;
  final String title;
  final String value;
  final String? subtitle;
  final String? secondaryText;
  final String? badge;
  final Color? badgeColor;
  final VoidCallback? onTap;

  @override
  State<PremiumDashboardCard> createState() => _PremiumDashboardCardState();
}

class _PremiumDashboardCardState extends State<PremiumDashboardCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.iconColor;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
          transform: _hover ? Matrix4.translationValues(0, -2.5, 0) : Matrix4.identity(),
          height: 170,
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: _hover ? c.withValues(alpha: 0.15) : Colors.grey.shade200.withValues(alpha: 0.7),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: _hover ? 0.07 : 0.03),
                blurRadius: _hover ? 18 : 8,
                offset: Offset(0, _hover ? 6 : 3),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Linha: ícone + badge
              Row(
                children: [
                  Container(
                    width: 34, height: 34,
                    decoration: BoxDecoration(
                      color: c.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(widget.icon, size: 17, color: c),
                  ),
                  const Spacer(),
                  if (widget.badge != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: (widget.badgeColor ?? const Color(0xFF16A34A)).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(widget.badge!,
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 10, fontWeight: FontWeight.w700,
                              color: widget.badgeColor ?? const Color(0xFF16A34A),
                              letterSpacing: 0.3)),
                    ),
                ],
              ),
              const Spacer(),
              // Valor
              Text(widget.value,
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 21, fontWeight: FontWeight.w800,
                      color: const Color(0xFF1A1A2E), height: 1.1),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 4),
              // Título
              Text(widget.title,
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 11.5, fontWeight: FontWeight.w500,
                      color: const Color(0xFF64748B), height: 1.2),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              // Secondary / subtitle
              if (widget.secondaryText != null || widget.subtitle != null) ...[
                const SizedBox(height: 2),
                Text(widget.secondaryText ?? widget.subtitle!,
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 11, fontWeight: FontWeight.w600,
                        color: c.withValues(alpha: 0.8)),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _DashboardKpis extends StatelessWidget {
  const _DashboardKpis({required this.uidLoja, required this.dadosUsuario});
  final String uidLoja;
  final Map<String, dynamic> dadosUsuario;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('assinaturas_clientes')
          .where('store_id', isEqualTo: uidLoja)
          .snapshots(),
      builder: (ctx, snap) {
        String statusAss = '—';
        String planName = '—';
        double monthlyAmount = 0;
        Timestamp? nextBilling;

        if (snap.hasData && snap.data!.docs.isNotEmpty) {
          final a = _melhorAssinaturaModel(snap.data!)!;
          planName = a.planName;
          monthlyAmount = a.monthlyAmount;
          statusAss = a.statusExibicaoRotulo;
          nextBilling = a.nextBillingDate;
        }

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('assinaturas_cobrancas')
              .where('store_id', isEqualTo: uidLoja)
              .snapshots(),
          builder: (ctx2, snap2) {
            double totalPago = 0;

            if (snap2.hasData) {
              for (final doc in snap2.data!.docs) {
                final d = doc.data();
                final st = d['status'] as String?;
                final v = (d['valor'] as num?)?.toDouble() ?? 0;
                if (st == 'paga' || st == 'pago') {
                  totalPago += v;
                }
              }
            }

            return LayoutBuilder(
              builder: (ctx3, constraints) {
                final cols = constraints.maxWidth > 1100
                    ? 4
                    : constraints.maxWidth > 700
                        ? 2
                        : 1;
                final spacing = 20.0;
                final totalSpacing = spacing * (cols - 1);
                final cardWidth = (constraints.maxWidth - totalSpacing) / cols;

                return Wrap(
                  spacing: spacing,
                  runSpacing: spacing,
                  children: [
                    SizedBox(
                      width: cardWidth,
                      child: PremiumDashboardCard(
                        icon: Icons.verified_rounded,
                        iconColor: const Color(0xFF16A34A),
                        title: 'Assinatura',
                        value: statusAss == '—' ? '—' : statusAss,
                        subtitle: 'Plano: $planName',
                        badge: statusAss == 'Ativo' || statusAss == 'Vence em breve' ? 'Ativa' : null,
                      ),
                    ),
                    SizedBox(
                      width: cardWidth,
                      child: PremiumDashboardCard(
                        icon: Icons.payments_rounded,
                        iconColor: const Color(0xFF6A1B9A),
                        title: 'Total pago até hoje',
                        value: _fmtMoeda(totalPago),
                      ),
                    ),
                    SizedBox(
                      width: cardWidth,
                      child: PremiumDashboardCard(
                        icon: Icons.account_balance_wallet_rounded,
                        iconColor: const Color(0xFFFF8F00),
                        title: 'Plano atual',
                        value: _fmtMoeda(monthlyAmount),
                        subtitle: planName,
                      ),
                    ),
                    SizedBox(
                      width: cardWidth,
                      child: PremiumDashboardCard(
                        icon: Icons.calendar_today_rounded,
                        iconColor: const Color(0xFF0EA5E9),
                        title: 'Próxima cobrança',
                        value: _fmtData(nextBilling),
                        secondaryText: monthlyAmount > 0 ? _fmtMoeda(monthlyAmount) : null,
                      ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }
}

// ══════════════════════════════════════════════
//  ALERTAS INTELIGENTES
// ══════════════════════════════════════════════

class _AlertasInteligentes extends StatelessWidget {
  const _AlertasInteligentes({required this.uidLoja});
  final String uidLoja;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('assinaturas_clientes')
          .where('store_id', isEqualTo: uidLoja)
          .snapshots(),
      builder: (ctx, snap) {
        final a = _melhorAssinaturaModel(snap.data);
        if (a == null) return const SizedBox.shrink();
        final alertas = <Widget>[];

        if (a.diasAteVencimento <= 5 && a.diasAteVencimento >= 0) {
          alertas.add(_alertaItem(
            Icons.info_rounded, const Color(0xFFFF8F00), const Color(0xFFFFF3E6),
            'Plano vence em ${a.diasAteVencimento} ${a.diasAteVencimento == 1 ? 'dia' : 'dias'}',
          ));
        }
        if (a.diasAposVencimento > 0) {
          alertas.add(_alertaItem(
            Icons.warning_rounded, const Color(0xFFF04438), const Color(0xFFFEF2F2),
            'Pagamento venceu há ${a.diasAposVencimento} ${a.diasAposVencimento == 1 ? 'dia' : 'dias'}',
          ));
        }

        if (alertas.isEmpty) return const SizedBox.shrink();

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.orange.shade100.withValues(alpha: 0.5)),
          ),
          child: Row(
            children: [
              Icon(Icons.notifications_active_rounded, size: 18, color: const Color(0xFFFF8F00)),
              const SizedBox(width: 12),
              Expanded(child: Wrap(spacing: 8, runSpacing: 8, children: alertas)),
            ],
          ),
        );
      },
    );
  }

  Widget _alertaItem(IconData icon, Color cor, Color fundo, String texto) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: fundo, borderRadius: BorderRadius.circular(8)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: cor),
          const SizedBox(width: 6),
          Text(texto, style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w500, color: cor)),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════
//  WRAPPER DE CARD (limpo, estilo referência)
// ══════════════════════════════════════════════

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.icon, required this.child, this.action});
  final String title;
  final IconData icon;
  final Widget child;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200.withValues(alpha: 0.8)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 16, 12),
            child: Row(
              children: [
                Icon(icon, size: 18, color: const Color(0xFF6A1B9A).withValues(alpha: 0.7)),
                const SizedBox(width: 10),
                Text(
                  title,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF1A1A2E),
                  ),
                ),
                const Spacer(),
                if (action != null) action!,
              ],
            ),
          ),
          // Body
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: child,
          ),
        ],
      ),
    );
  }
}

/// Linha de informação label + valor
class _InfoLinha extends StatelessWidget {
  const _InfoLinha({required this.label, required this.value, this.color});
  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                color: const Color(0xFF64748B).withValues(alpha: 0.8),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: color ?? const Color(0xFF1A1A2E),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════
//  CARD 1: RESUMO DA ASSINATURA
// ══════════════════════════════════════════════

class _CardAssinaturaResumo extends StatelessWidget {
  const _CardAssinaturaResumo({required this.uidLoja});
  final String uidLoja;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('assinaturas_clientes')
          .where('store_id', isEqualTo: uidLoja)
          .snapshots(),
      builder: (ctx, snap) {
        final a = _melhorAssinaturaModel(snap.data);
        if (snap.hasData && snap.data!.docs.isEmpty) return _vazio();
        if (a == null) return _skeleton();

        return _SectionCard(
          title: 'Resumo da Assinatura',
          icon: Icons.assignment_rounded,
          action: TextButton(
            onPressed: () => _mostrarModalDetalhesAssinatura(context, a),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text('Ver detalhes',
                style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w600, color: const Color(0xFF6A1B9A))),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _InfoLinha(label: 'Plano', value: a.planName),
              _InfoLinha(label: 'Valor mensal', value: _fmtMoeda(a.monthlyAmount)),
              _InfoLinha(
                label: 'Situação',
                value: a.statusExibicaoRotulo,
                color: _corStatus(a.statusExibicao),
              ),
              _InfoLinha(label: 'Próxima cobrança', value: a.nextBillingDateExibir),
              _InfoLinha(label: 'Contratação', value: a.createdAtExibir),
              _InfoLinha(label: 'Pagamento', value: a.gateway),
              _InfoLinha(
                label: 'Renovação',
                value: a.statusExibicao == 'ativo' ? 'Automática' : '—',
              ),
              if ((a.statusExibicao == 'ativo' || a.statusExibicao == 'vencer_em_breve') && a.diasAteVencimento >= 0)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: _statusBadge(
                    a.diasAteVencimento > 7 ? 'Em dia' : 'Vence em ${a.diasAteVencimento} ${a.diasAteVencimento == 1 ? 'dia' : 'dias'}',
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _skeleton() {
    return _SectionCard(
      title: 'Resumo da Assinatura',
      icon: Icons.assignment_rounded,
      child: const SizedBox(height: 120, child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
    );
  }

  Widget _vazio() {
    return _SectionCard(
      title: 'Resumo da Assinatura',
      icon: Icons.assignment_rounded,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Center(child: Text('Nenhuma assinatura encontrada.',
            style: GoogleFonts.plusJakartaSans(fontSize: 13, color: const Color(0xFF64748B)))),
      ),
    );
  }
}

// ══════════════════════════════════════════════
//  CARD 2: COBRANÇAS
// ══════════════════════════════════════════════

class _CardCobrancas extends StatelessWidget {
  const _CardCobrancas({required this.uidLoja});
  final String uidLoja;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('assinaturas_cobrancas')
          .where('store_id', isEqualTo: uidLoja)
          .snapshots(),
      builder: (ctx, snap) {
        if (snap.hasError) {
          return _cardVazio();
        }

        final docs = snap.data?.docs ?? [];
        int total = 0;
        double pago = 0;
        double pendente = 0;
        Timestamp? ultimoPgto;
        Timestamp? proxVenc;

        for (final doc in docs) {
          final d = doc.data();
          final st = d['status'] as String?;
          final v = (d['valor'] as num?)?.toDouble() ?? 0;

          if (st == 'paga' || st == 'pago') {
            total++;
            pago += v;
            final pgto = d['atualizado_em'] as Timestamp? ?? d['pago_em'] as Timestamp?;
            if (pgto != null && (ultimoPgto == null || pgto.toDate().isAfter(ultimoPgto.toDate()))) {
              ultimoPgto = pgto;
            }
          } else if (st == 'em_aberto' || st == 'vencida') {
            pendente += v;
            final venc = d['vencimento'] as Timestamp?;
            if (venc != null && (proxVenc == null || venc.toDate().isBefore(proxVenc.toDate()))) {
              proxVenc = venc;
            }
          }
        }

        // Contar faturas pendentes por tipo
        int qtdVencidas = 0;
        int qtdAberto = 0;
        for (final doc in docs) {
          final st = doc.data()['status'] as String? ?? '';
          if (st == 'vencida') qtdVencidas++;
          if (st == 'em_aberto') qtdAberto++;
        }
        final subtipoPendente = pendente > 0
            ? (qtdVencidas > 0 && qtdAberto > 0
                ? 'Pendente'
                : qtdVencidas > 0
                    ? 'Vencida${qtdVencidas > 1 ? 's' : ''}'
                    : 'A vencer')
            : '';

        return _SectionCard(
          title: 'Cobranças',
          icon: Icons.receipt_long_rounded,
          action: TextButton(
            onPressed: docs.isEmpty ? null : () => _mostrarModalHistoricoCobrancas(context, uidLoja),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text('Ver todas',
                style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w600,
                    color: docs.isEmpty ? const Color(0xFF94A3B8) : const Color(0xFF6A1B9A))),
          ),
          child: docs.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text('Nenhuma cobrança encontrada.',
                        style: GoogleFonts.plusJakartaSans(fontSize: 13, color: const Color(0xFF64748B))),
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _InfoLinha(label: 'Total de faturas', value: '$total'),
                    _InfoLinha(label: 'Total pago', value: _fmtMoeda(pago)),
                    _InfoLinha(
                      label: 'Pendente',
                      value: pendente > 0 && subtipoPendente.isNotEmpty
                          ? '${_fmtMoeda(pendente)} $subtipoPendente'
                          : _fmtMoeda(pendente),
                      color: pendente > 0 ? const Color(0xFFF04438) : null,
                    ),
                    _InfoLinha(label: 'Próximo vencimento', value: _fmtData(proxVenc)),
                    _InfoLinha(label: 'Último pagamento', value: _fmtData(ultimoPgto)),
                  ],
                ),
        );
      },
    );
  }

  Widget _cardVazio() {
    return _SectionCard(
      title: 'Cobranças',
      icon: Icons.receipt_long_rounded,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text('Erro ao carregar cobranças.',
              style: GoogleFonts.plusJakartaSans(fontSize: 13, color: const Color(0xFF64748B))),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════
//  CARD 3: EXTRATO FINANCEIRO
//  Mostra faturas existentes + próxima cobrança
// ══════════════════════════════════════════════

class _CardExtratoFinanceiro extends StatelessWidget {
  const _CardExtratoFinanceiro({required this.uidLoja});
  final String uidLoja;

  @override
  Widget build(BuildContext context) {
    // Stream da assinatura ativa (para next billing)
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('assinaturas_clientes')
          .where('store_id', isEqualTo: uidLoja)
          .where('status', whereIn: ['ativo', 'em_atraso'])
          .limit(1)
          .snapshots(),
      builder: (ctx, snapAss) {
        ClienteAssinaturaModel? assinatura;
        if (snapAss.hasData && snapAss.data!.docs.isNotEmpty) {
          assinatura = ClienteAssinaturaModel.fromFirestore(snapAss.data!.docs.first);
        }

        // Stream das cobranças
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('assinaturas_cobrancas')
              .where('store_id', isEqualTo: uidLoja)
              .orderBy('vencimento', descending: true)
              .limit(15)
              .snapshots(),
          builder: (ctx2, snap2) {
            final docs = snap2.data?.docs ?? [];
            final temInvoice = docs.isNotEmpty;
            final temProxima = assinatura != null && assinatura.nextBillingDate != null;

            // Se não tem nada, mostra vazio
            if (!temInvoice && !temProxima) {
              return _SectionCard(
                title: 'Extrato de Pagamentos',
                icon: Icons.account_balance_rounded,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  child: Center(
                    child: Text('Nenhum pagamento registrado.',
                        style: GoogleFonts.plusJakartaSans(fontSize: 13, color: const Color(0xFF64748B))),
                  ),
                ),
              );
            }

            return _SectionCard(
              title: 'Extrato de Pagamentos',
              icon: Icons.account_balance_rounded,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ─── Próxima cobrança (se houver assinatura ativa) ───
                  if (temProxima) ...[
                    _buildProximaCobranca(context, assinatura),
                    if (temInvoice) const SizedBox(height: 20),
                  ],

                  // ─── Faturas existentes ───
                  if (temInvoice)
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        columnSpacing: 28,
                        headingRowHeight: 42,
                        dataRowMinHeight: 44,
                        dataRowMaxHeight: 48,
                        headingRowColor: WidgetStatePropertyAll(const Color(0xFFF5F4F8).withValues(alpha: 0.6)),
                        border: TableBorder(
                          horizontalInside: BorderSide(color: Colors.grey.shade200.withValues(alpha: 0.3)),
                        ),
                        columns: [
                          _col('Data'),
                          _col('Fatura'),
                          _col('Valor'),
                          _col('Vencimento'),
                          _col('Status'),
                        ],
                        rows: docs.map((doc) {
                          final d = doc.data();
                          final fatura = d['fatura'] as String? ?? '#N/A';
                          final valor = (d['valor'] as num?)?.toDouble() ?? 0;
                          final status = d['status'] as String? ?? '';
                          final vencimento = d['vencimento'] as Timestamp?;
                          final statusLabel = StatusCobranca.fromCodigo(status).rotulo;
                          return DataRow(cells: [
                            _cell(_fmtData(vencimento)),
                            _cell(fatura, bold: true),
                            _cell(_fmtMoeda(valor), bold: true),
                            _cell(_fmtData(vencimento)),
                            DataCell(_statusBadge(statusLabel)),
                          ]);
                        }).toList(),
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ─── Bloco premium da próxima cobrança ───
  Widget _buildProximaCobranca(BuildContext context, ClienteAssinaturaModel a) {
    final data = a.nextBillingDateExibir;
    final valor = _fmtMoeda(a.monthlyAmount);
    final diasRestantes = a.diasAteVencimento;
    final diasTexto = diasRestantes > 0
        ? 'Vence em $diasRestantes ${diasRestantes == 1 ? 'dia' : 'dias'}'
        : diasRestantes == 0
            ? 'Vence hoje'
            : 'Vencido há ${-diasRestantes} ${-diasRestantes == 1 ? 'dia' : 'dias'}';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF6A1B9A).withValues(alpha: 0.04),
            const Color(0xFFFF8F00).withValues(alpha: 0.03),
          ],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF6A1B9A).withValues(alpha: 0.12)),
      ),
      child: Row(
        children: [
          // Ícone
          Container(
            width: 42, height: 42,
            decoration: BoxDecoration(
              color: const Color(0xFF6A1B9A).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.receipt_long_rounded, size: 20, color: Color(0xFF6A1B9A)),
          ),
          const SizedBox(width: 14),
          // Informações
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Próxima cobrança',
                    style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w700, color: const Color(0xFF1A1A2E))),
                const SizedBox(height: 4),
                Text('$valor · $data · ${a.planName}',
                    style: GoogleFonts.plusJakartaSans(fontSize: 12, color: const Color(0xFF64748B))),
                const SizedBox(height: 2),
                Text(diasTexto,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11, fontWeight: FontWeight.w600,
                      color: diasRestantes > 0
                          ? const Color(0xFFFF8F00)
                          : const Color(0xFFF04438),
                    )),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Status + botão
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              _statusBadge('A vencer'),
              const SizedBox(height: 8),
              SizedBox(
                height: 34,
                child: TextButton.icon(
                  onPressed: () => _abrirPagamentoAntecipado(context, a),
                  icon: const Icon(Icons.pix_rounded, size: 16, color: Colors.white),
                  label: Text('Pagar antecipado',
                      style: GoogleFonts.plusJakartaSans(fontSize: 11.5, fontWeight: FontWeight.w600, color: Colors.white)),
                  style: TextButton.styleFrom(
                    backgroundColor: const Color(0xFF6A1B9A),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _abrirPagamentoAntecipado(BuildContext context, ClienteAssinaturaModel a) {
    AssinaturaPagamentoModal.mostrar(
      context,
      plano: {
        'id': a.planId,
        'nome': a.planName,
        'valor': a.monthlyAmount,
        'descricao': 'Renovação antecipada · ${a.planName}',
        'modulos': <String>[],
      },
      lojaId: a.storeId,
      lojaNome: a.storeName,
      ownerName: a.ownerName,
      ownerEmail: a.email,
      ehRenovacao: true,
      assinaturaId: a.id,
    );
  }

  DataColumn _col(String label) => DataColumn(
        label: Text(label,
            style: GoogleFonts.plusJakartaSans(fontSize: 11.5, fontWeight: FontWeight.w700, color: const Color(0xFF64748B))),
      );

  DataCell _cell(String text, {bool bold = false}) => DataCell(
        Text(text,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12.5,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
              color: const Color(0xFF1A1A2E),
            )),
      );
}

// ══════════════════════════════════════════════
//  CARD 4: DADOS DA EMPRESA (com fallback fiscal)
// ══════════════════════════════════════════════

class _CardDadosEmpresa extends StatelessWidget {
  const _CardDadosEmpresa({required this.uidLoja, required this.dadosUsuario});
  final String uidLoja;
  final Map<String, dynamic> dadosUsuario;

  String _extrair(String key, Map<String, dynamic>? fiscalTax,
      {List<String> aliases = const [], String fb = '—'}) {
    // 1. Tenta no dadosUsuario
    for (final k in [key, ...aliases]) {
      final v = dadosUsuario[k]?.toString();
      if (v != null && v.trim().isNotEmpty) return v.trim();
    }
    // 2. Fallback fiscal company_tax_data
    if (fiscalTax != null) {
      for (final k in [key, ...aliases]) {
        final v = fiscalTax[k]?.toString();
        if (v != null && v.trim().isNotEmpty) return v.trim();
      }
    }
    return fb;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('store_fiscal_settings')
          .doc(uidLoja)
          .snapshots(),
      builder: (ctx, snapFiscal) {
        final fiscalData = snapFiscal.hasData && snapFiscal.data!.exists
            ? snapFiscal.data!.data()
            : null;
        final fiscalTax = fiscalData?['company_tax_data'] as Map<String, dynamic>?;

        return _SectionCard(
          title: 'Dados da Empresa',
          icon: Icons.business_rounded,
          action: TextButton(
            onPressed: () => _mostrarModalEditarEmpresa(context, uidLoja, dadosUsuario, fiscalTax),
            style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
            child: Text('Editar', style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w600, color: const Color(0xFF6A1B9A))),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _InfoLinha(label: 'Nome Fantasia',
                  value: _extrair('loja_nome', fiscalTax, aliases: ['nome_loja', 'nome', 'nome_fantasia'])),
              _InfoLinha(label: 'Razão Social',
                  value: _extrair('razao_social', fiscalTax)),
              _InfoLinha(label: 'CNPJ / CPF',
                  value: _extrair('cnpj', fiscalTax, aliases: ['cpf', 'cpf_cnpj', 'documento'])),
              _InfoLinha(label: 'Inscrição Estadual',
                  value: _extrair('inscricao_estadual', fiscalTax, aliases: ['ie'])),
              _InfoLinha(label: 'Inscrição Municipal',
                  value: _extrair('inscricao_municipal', fiscalTax, aliases: ['im'])),
              _InfoLinha(label: 'Regime Tributário',
                  value: _extrair('regime_tributario', fiscalTax)),
              _InfoLinha(label: 'CNAE',
                  value: _extrair('cnae', fiscalTax)),
              _InfoLinha(label: 'Telefone',
                  value: _extrair('telefone', fiscalTax)),
              _InfoLinha(label: 'WhatsApp',
                  value: _extrair('whatsapp', fiscalTax, aliases: ['celular'])),
              _InfoLinha(label: 'E-mail',
                  value: _extrair('email', fiscalTax, aliases: ['email_fiscal'])),
              _InfoLinha(label: 'Site',
                  value: _extrair('site', fiscalTax)),
            ],
          ),
        );
      },
    );
  }
}

// ══════════════════════════════════════════════
//  CARD 5: ENDEREÇO (com fallback fiscal)
// ══════════════════════════════════════════════

class _CardEndereco extends StatelessWidget {
  const _CardEndereco({required this.uidLoja, required this.dadosUsuario});
  final String uidLoja;
  final Map<String, dynamic> dadosUsuario;

  String _extrair(String key, Map<String, dynamic>? fiscalTax,
      {List<String> aliases = const [], String fb = '—'}) {
    for (final k in [key, ...aliases]) {
      final v = dadosUsuario[k]?.toString();
      if (v != null && v.trim().isNotEmpty) return v.trim();
    }
    if (fiscalTax != null) {
      for (final k in [key, ...aliases]) {
        final v = fiscalTax[k]?.toString();
        if (v != null && v.trim().isNotEmpty) return v.trim();
      }
    }
    return fb;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('store_fiscal_settings')
          .doc(uidLoja)
          .snapshots(),
      builder: (ctx, snapFiscal) {
        final fiscalData = snapFiscal.hasData && snapFiscal.data!.exists
            ? snapFiscal.data!.data()
            : null;
        final fiscalTax = fiscalData?['company_tax_data'] as Map<String, dynamic>?;

        return _SectionCard(
          title: 'Endereço',
          icon: Icons.location_on_rounded,
          action: TextButton(
            onPressed: () => _mostrarModalEditarEndereco(context, uidLoja, dadosUsuario, fiscalTax),
            style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
            child: Text('Editar', style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w600, color: const Color(0xFF6A1B9A))),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _InfoLinha(label: 'CEP',
                  value: _extrair('cep', fiscalTax, aliases: ['endereco_cep', 'cep_fiscal'])),
              _InfoLinha(label: 'Rua',
                  value: _extrair('endereco', fiscalTax, aliases: ['logradouro', 'address_street', 'rua'])),
              _InfoLinha(label: 'Número',
                  value: _extrair('numero', fiscalTax, aliases: ['endereco_numero', 'num'])),
              _InfoLinha(label: 'Complemento',
                  value: _extrair('complemento', fiscalTax, aliases: ['endereco_complemento'])),
              _InfoLinha(label: 'Bairro',
                  value: _extrair('bairro', fiscalTax, aliases: ['endereco_bairro'])),
              _InfoLinha(label: 'Cidade',
                  value: _extrair('cidade', fiscalTax, aliases: ['address_city', 'cidade_normalizada', 'municipio'])),
              _InfoLinha(label: 'Estado',
                  value: _extrair('uf', fiscalTax, aliases: ['estado', 'address_state'])),
              _InfoLinha(label: 'País', value: 'Brasil'),
            ],
          ),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════
//  MODAIS DE EDIÇÃO PREMIUM
// ═══════════════════════════════════════════════════════════════

void _mostrarModalEditarEmpresa(
  BuildContext context,
  String uidLoja,
  Map<String, dynamic> dadosUsuario,
  Map<String, dynamic>? fiscalTax,
) {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => _ModalEditarEmpresa(
      uidLoja: uidLoja,
      dadosUsuario: dadosUsuario,
      fiscalTax: fiscalTax,
    ),
  );
}

void _mostrarModalEditarEndereco(
  BuildContext context,
  String uidLoja,
  Map<String, dynamic> dadosUsuario,
  Map<String, dynamic>? fiscalTax,
) {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => _ModalEditarEndereco(
      uidLoja: uidLoja,
      dadosUsuario: dadosUsuario,
      fiscalTax: fiscalTax,
    ),
  );
}

/// Modal premium para editar Dados da Empresa
class _ModalEditarEmpresa extends StatefulWidget {
  final String uidLoja;
  final Map<String, dynamic> dadosUsuario;
  final Map<String, dynamic>? fiscalTax;

  const _ModalEditarEmpresa({
    required this.uidLoja,
    required this.dadosUsuario,
    this.fiscalTax,
  });

  @override
  State<_ModalEditarEmpresa> createState() => _ModalEditarEmpresaState();
}

class _ModalEditarEmpresaState extends State<_ModalEditarEmpresa> {
  late final TextEditingController _nomeFantasiaC;
  late final TextEditingController _razaoSocialC;
  late final TextEditingController _cnpjCpfC;
  late final TextEditingController _ieC;
  late final TextEditingController _imC;
  late final TextEditingController _regimeTributarioC;
  late final TextEditingController _cnaeC;
  late final TextEditingController _telefoneC;
  late final TextEditingController _whatsappC;
  late final TextEditingController _emailC;
  late final TextEditingController _siteC;

  bool _salvando = false;

  static const _roxo = Color(0xFF6A1B9A);

  @override
  void initState() {
    super.initState();
    _nomeFantasiaC = TextEditingController(text: _extrair('loja_nome', aliases: ['nome_loja', 'nome', 'nome_fantasia']));
    _razaoSocialC = TextEditingController(text: _extrair('razao_social'));
    _cnpjCpfC = TextEditingController(
        text: _mascaraCpfCnpjValor(_extrair('cnpj', aliases: ['cpf', 'cpf_cnpj', 'documento'])));
    _ieC = TextEditingController(text: _extrair('inscricao_estadual', aliases: ['ie']));
    _imC = TextEditingController(text: _extrair('inscricao_municipal', aliases: ['im']));
    _regimeTributarioC = TextEditingController(text: _extrair('regime_tributario'));
    _cnaeC = TextEditingController(text: _extrair('cnae'));
    _telefoneC = TextEditingController(
        text: _mascaraTelefoneValor(_extrair('telefone')));
    _whatsappC = TextEditingController(
        text: _mascaraTelefoneValor(_extrair('whatsapp', aliases: ['celular'])));
    _emailC = TextEditingController(text: _extrair('email', aliases: ['email_fiscal']));
    _siteC = TextEditingController(text: _extrair('site'));
  }

  String _extrair(String key, {List<String> aliases = const [], String fb = ''}) {
    for (final k in [key, ...aliases]) {
      final v = widget.dadosUsuario[k]?.toString();
      if (v != null && v.trim().isNotEmpty) return v.trim();
    }
    if (widget.fiscalTax != null) {
      for (final k in [key, ...aliases]) {
        final v = widget.fiscalTax![k]?.toString();
        if (v != null && v.trim().isNotEmpty) return v.trim();
      }
    }
    return fb;
  }

  @override
  void dispose() {
    _nomeFantasiaC.dispose();
    _razaoSocialC.dispose();
    _cnpjCpfC.dispose();
    _ieC.dispose();
    _imC.dispose();
    _regimeTributarioC.dispose();
    _cnaeC.dispose();
    _telefoneC.dispose();
    _whatsappC.dispose();
    _emailC.dispose();
    _siteC.dispose();
    super.dispose();
  }

  Future<void> _salvar() async {
    setState(() => _salvando = true);
    try {
      final firestore = FirebaseFirestore.instance;

      await firestore.collection('users').doc(widget.uidLoja).update({
        'loja_nome': _nomeFantasiaC.text.trim(),
        'razao_social': _razaoSocialC.text.trim(),
        'cnpj': _soDigitos(_cnpjCpfC.text),
        'cpf': _soDigitos(_cnpjCpfC.text),
        'inscricao_estadual': _ieC.text.trim(),
        'inscricao_municipal': _imC.text.trim(),
        'regime_tributario': _regimeTributarioC.text.trim(),
        'cnae': _cnaeC.text.trim(),
        'telefone': _soDigitos(_telefoneC.text),
        'whatsapp': _soDigitos(_whatsappC.text),
        'email': _emailC.text.trim(),
        'site': _siteC.text.trim(),
        'updated_at': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      Navigator.of(context).pop();
      _mostrarResultadoDialog(context, 'Dados da empresa salvos com sucesso!', isError: false);
    } catch (e) {
      if (!mounted) return;
      setState(() => _salvando = false);
      _mostrarResultadoDialog(context, 'Erro ao salvar: $e', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 700),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(24, 22, 24, 16),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [_roxo, Color(0xFF8E24AA)],
                  begin: Alignment.centerLeft, end: Alignment.centerRight,
                ),
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.business_rounded, color: Colors.white, size: 20),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Editar Dados da Empresa',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 17, fontWeight: FontWeight.w700, color: Colors.white)),
                        const SizedBox(height: 2),
                        Text('Preencha as informações da sua empresa',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 12, color: Colors.white.withValues(alpha: 0.75))),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white, size: 22),
                    onPressed: () => Navigator.of(context).pop(),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),
            // Body (scrollable)
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _CampoModalWidget(label: 'Nome Fantasia', icon: Icons.store_rounded, controller: _nomeFantasiaC),
                    const SizedBox(height: 14),
                    _CampoModalWidget(label: 'Razão Social', icon: Icons.description_outlined, controller: _razaoSocialC),
                    const SizedBox(height: 14),
                    _CampoModalWidget(
                      label: 'CNPJ / CPF',
                      icon: Icons.assignment_ind_rounded,
                      controller: _cnpjCpfC,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        _CpfCnpjInputFormatter(),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(child: _CampoModalWidget(label: 'Inscrição Estadual', icon: Icons.numbers_rounded, controller: _ieC)),
                        const SizedBox(width: 12),
                        Expanded(child: _CampoModalWidget(label: 'Inscrição Municipal', icon: Icons.numbers_rounded, controller: _imC)),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(child: _CampoModalWidget(label: 'Regime Tributário', icon: Icons.account_balance_rounded, controller: _regimeTributarioC)),
                        const SizedBox(width: 12),
                        Expanded(child: _CampoModalWidget(label: 'CNAE', icon: Icons.qr_code_rounded, controller: _cnaeC)),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(child: _CampoModalWidget(
                          label: 'Telefone',
                          icon: Icons.phone_rounded,
                          controller: _telefoneC,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            _PhoneInputFormatter(),
                          ],
                        )),
                        const SizedBox(width: 12),
                        Expanded(child: _CampoModalWidget(
                          label: 'WhatsApp',
                          icon: Icons.chat_rounded,
                          controller: _whatsappC,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            _PhoneInputFormatter(),
                          ],
                        )),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _CampoModalWidget(label: 'E-mail', icon: Icons.email_rounded, controller: _emailC),
                    const SizedBox(height: 14),
                    _CampoModalWidget(label: 'Site', icon: Icons.language_rounded, controller: _siteC),
                  ],
                ),
              ),
            ),
            // Footer
            Container(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: Colors.grey.shade200)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: _salvando ? null : () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _roxo,
                      side: BorderSide(color: _roxo.withValues(alpha: 0.3)),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text('Cancelar',
                      style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(width: 12),
                  _salvando
                      ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5))
                      : ElevatedButton(
                          onPressed: _salvar,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _roxo,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            elevation: 0,
                          ),
                          child: Text('Salvar alterações',
                            style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w700)),
                        ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Modal premium para editar Endereço
class _ModalEditarEndereco extends StatefulWidget {
  final String uidLoja;
  final Map<String, dynamic> dadosUsuario;
  final Map<String, dynamic>? fiscalTax;

  const _ModalEditarEndereco({
    required this.uidLoja,
    required this.dadosUsuario,
    this.fiscalTax,
  });

  @override
  State<_ModalEditarEndereco> createState() => _ModalEditarEnderecoState();
}

class _ModalEditarEnderecoState extends State<_ModalEditarEndereco> {
  late final TextEditingController _cepC;
  late final TextEditingController _ruaC;
  late final TextEditingController _numeroC;
  late final TextEditingController _complementoC;
  late final TextEditingController _bairroC;
  late final TextEditingController _cidadeC;
  late final TextEditingController _estadoC;
  late final TextEditingController _paisC;

  bool _salvando = false;
  bool _buscandoCep = false;

  static const _roxo = Color(0xFF6A1B9A);

  @override
  void initState() {
    super.initState();
    _cepC = TextEditingController(text: _extrair('cep', aliases: ['endereco_cep', 'cep_fiscal']));
    _ruaC = TextEditingController(text: _extrair('endereco', aliases: ['logradouro', 'address_street', 'rua']));
    _numeroC = TextEditingController(text: _extrair('numero', aliases: ['endereco_numero', 'num']));
    _complementoC = TextEditingController(text: _extrair('complemento', aliases: ['endereco_complemento']));
    _bairroC = TextEditingController(text: _extrair('bairro', aliases: ['endereco_bairro']));
    _cidadeC = TextEditingController(text: _extrair('cidade', aliases: ['address_city', 'cidade_normalizada', 'municipio']));
    _estadoC = TextEditingController(text: _extrair('uf', aliases: ['estado', 'address_state']));
    _paisC = TextEditingController(text: 'Brasil');

    // Listener de CEP: máscara + busca automática
    _cepC.addListener(_onCepAlterado);
  }

  void _onCepAlterado() {
    final text = _cepC.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (text.length > 8) return;

    // Aplica máscara 00000-000
    final masked = text.length <= 5
        ? text
        : '${text.substring(0, 5)}-${text.substring(5)}';
    if (_cepC.text != masked) {
      _cepC.text = masked;
      _cepC.selection = TextSelection.collapsed(offset: masked.length);
    }

    // Dispara busca quando tiver 8 dígitos
    if (text.length == 8) {
      _buscarCepPorApi(text);
    }
  }

  Future<void> _buscarCepPorApi(String cep) async {
    if (_buscandoCep) return;
    setState(() => _buscandoCep = true);
    try {
      final response = await http.get(
        Uri.parse('https://viacep.com.br/ws/$cep/json/'),
        headers: {'Accept': 'application/json'},
      );
      if (response.statusCode != 200) throw Exception('Erro HTTP ${response.statusCode}');

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (data.containsKey('erro') && data['erro'] == true) {
        if (!mounted) return;
        setState(() => _buscandoCep = false);
        _mostrarResultadoDialog(context, 'CEP não encontrado. Verifique o número digitado.', isError: true);
        return;
      }

      final logradouro = (data['logradouro'] as String?)?.trim() ?? '';
      final bairro = (data['bairro'] as String?)?.trim() ?? '';
      final cidade = (data['localidade'] as String?)?.trim() ?? '';
      final estado = (data['uf'] as String?)?.trim() ?? '';

      if (!mounted) return;
      setState(() => _buscandoCep = false);

      if (logradouro.isNotEmpty) _ruaC.text = logradouro;
      if (bairro.isNotEmpty) _bairroC.text = bairro;
      if (cidade.isNotEmpty) _cidadeC.text = cidade;
      if (estado.isNotEmpty) _estadoC.text = estado;
      _paisC.text = 'Brasil';
    } catch (_) {
      if (!mounted) return;
      setState(() => _buscandoCep = false);
      _mostrarResultadoDialog(context, 'Não foi possível consultar o CEP. Tente novamente.', isError: true);
    }
  }

  String _extrair(String key, {List<String> aliases = const [], String fb = ''}) {
    for (final k in [key, ...aliases]) {
      final v = widget.dadosUsuario[k]?.toString();
      if (v != null && v.trim().isNotEmpty) return v.trim();
    }
    if (widget.fiscalTax != null) {
      for (final k in [key, ...aliases]) {
        final v = widget.fiscalTax![k]?.toString();
        if (v != null && v.trim().isNotEmpty) return v.trim();
      }
    }
    return fb;
  }

  @override
  void dispose() {
    _cepC.removeListener(_onCepAlterado);
    _cepC.dispose();
    _ruaC.dispose();
    _numeroC.dispose();
    _complementoC.dispose();
    _bairroC.dispose();
    _cidadeC.dispose();
    _estadoC.dispose();
    _paisC.dispose();
    super.dispose();
  }

  Future<void> _salvar() async {
    setState(() => _salvando = true);
    try {
      final firestore = FirebaseFirestore.instance;

      await firestore.collection('users').doc(widget.uidLoja).update({
        'endereco': _ruaC.text.trim(),
        'cidade': _cidadeC.text.trim(),
        'cidade_normalizada': _cidadeC.text.trim(),
        'uf': _estadoC.text.trim(),
        'uf_normalizado': _estadoC.text.trim(),
        'cep': _cepC.text.trim(),
        'numero': _numeroC.text.trim(),
        'complemento': _complementoC.text.trim(),
        'bairro': _bairroC.text.trim(),
        'endereco_numero': _numeroC.text.trim(),
        'endereco_complemento': _complementoC.text.trim(),
        'endereco_bairro': _bairroC.text.trim(),
        'endereco_cep': _cepC.text.trim(),
        'updated_at': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      Navigator.of(context).pop();
      _mostrarResultadoDialog(context, 'Endereço salvo com sucesso!', isError: false);
    } catch (e) {
      if (!mounted) return;
      setState(() => _salvando = false);
      _mostrarResultadoDialog(context, 'Erro ao salvar: $e', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 580, maxHeight: 650),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(24, 22, 24, 16),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [_roxo, Color(0xFF8E24AA)],
                  begin: Alignment.centerLeft, end: Alignment.centerRight,
                ),
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.location_on_rounded, color: Colors.white, size: 20),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Editar Endereço',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 17, fontWeight: FontWeight.w700, color: Colors.white)),
                        const SizedBox(height: 2),
                        Text('Atualize o endereço da sua loja',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 12, color: Colors.white.withValues(alpha: 0.75))),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white, size: 22),
                    onPressed: () => Navigator.of(context).pop(),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),
            // Body
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _CampoModalWidget(
                      label: 'CEP',
                      icon: Icons.mail_outline_rounded,
                      controller: _cepC,
                      suffix: _buscandoCep
                          ? const Padding(
                              padding: EdgeInsets.only(left: 4),
                              child: SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            )
                          : null,
                    ),
                    const SizedBox(height: 14),
                    _CampoModalWidget(label: 'Rua / Logradouro', icon: Icons.signpost_rounded, controller: _ruaC),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(flex: 2, child: _CampoModalWidget(label: 'Número', icon: Icons.tag_rounded, controller: _numeroC)),
                        const SizedBox(width: 12),
                        Expanded(flex: 3, child: _CampoModalWidget(label: 'Complemento', icon: Icons.add_home_rounded, controller: _complementoC)),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _CampoModalWidget(label: 'Bairro', icon: Icons.map_rounded, controller: _bairroC),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(flex: 3, child: _CampoModalWidget(label: 'Cidade', icon: Icons.location_city_rounded, controller: _cidadeC)),
                        const SizedBox(width: 12),
                        Expanded(child: _CampoModalWidget(label: 'Estado', icon: Icons.map_rounded, controller: _estadoC)),
                        const SizedBox(width: 12),
                        Expanded(child: _CampoModalWidget(label: 'País', icon: Icons.public_rounded, controller: _paisC)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            // Footer
            Container(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: Colors.grey.shade200)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: _salvando ? null : () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _roxo,
                      side: BorderSide(color: _roxo.withValues(alpha: 0.3)),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text('Cancelar',
                      style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(width: 12),
                  _salvando
                      ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5))
                      : ElevatedButton(
                          onPressed: _salvar,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _roxo,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            elevation: 0,
                          ),
                          child: Text('Salvar alterações',
                            style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w700)),
                        ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Campo de formulário premium com foco (borda roxa apenas no foco)
class _CampoModalWidget extends StatefulWidget {
  final String label;
  final IconData icon;
  final TextEditingController controller;
  final Widget? suffix;
  final List<TextInputFormatter>? inputFormatters;

  const _CampoModalWidget({
    required this.label,
    required this.icon,
    required this.controller,
    this.suffix,
    this.inputFormatters,
  });

  @override
  State<_CampoModalWidget> createState() => _CampoModalWidgetState();
}

class _CampoModalWidgetState extends State<_CampoModalWidget> {
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const roxo = Color(0xFF6A1B9A);
    const ink = Color(0xFF1A1A2E);
    const cinzaBorda = Color(0xFFE5E7EB);
    final focusBorda = roxo.withValues(alpha: 0.6);

    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: widget.controller,
            focusNode: _focusNode,
            inputFormatters: widget.inputFormatters,
            style: GoogleFonts.plusJakartaSans(
                fontSize: 14, color: ink, fontWeight: FontWeight.w500),
            decoration: InputDecoration(
              labelText: widget.label,
              floatingLabelBehavior: FloatingLabelBehavior.always,
              prefixIcon: Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Icon(widget.icon, size: 18,
                    color: roxo.withValues(alpha: 0.4)),
              ),
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 14),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: cinzaBorda, width: 1.2),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: focusBorda, width: 1.5),
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: cinzaBorda, width: 1.2),
              ),
              labelStyle: GoogleFonts.plusJakartaSans(
                  fontSize: 11,
                  color: roxo.withValues(alpha: 0.6),
                  fontWeight: FontWeight.w600),
            ),
          ),
        ),
        if (widget.suffix != null) widget.suffix!,
      ],
    );
  }
}

// ═══════════════════════════════════════════════
//  MASK FORMATTERS (CPF/CNPJ + Telefone/WhatsApp)
// ═══════════════════════════════════════════════

/// Formata CPF (000.000.000-00) ou CNPJ (00.000.000/0000-00)
class _CpfCnpjInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue old, TextEditingValue next) {
    final digits = next.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return TextEditingValue.empty;
    if (digits.length > 14) return old;

    final masked = _mascaraCpfCnpj(digits);
    return TextEditingValue(
      text: masked,
      selection: TextSelection.collapsed(offset: masked.length),
    );
  }
}

/// Formata telefone fixo/celular: (XX) XXXX-XXXX ou (XX) XXXXX-XXXX
class _PhoneInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue old, TextEditingValue next) {
    final digits = next.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return TextEditingValue.empty;
    if (digits.length > 11) return old;

    final masked = _mascaraTelefone(digits);
    return TextEditingValue(
      text: masked,
      selection: TextSelection.collapsed(offset: masked.length),
    );
  }
}

/// Aplica máscara CPF ou CNPJ conforme a quantidade de dígitos
String _mascaraCpfCnpj(String digits) {
  final buf = StringBuffer();
  for (int i = 0; i < digits.length; i++) {
    if (i == 3 || i == 6) buf.write('.');
    if (i == 9 && digits.length <= 11) buf.write('-');
    if (i == 12) buf.write('-');
    if (i == 8 && digits.length > 11) buf.write('/');
    buf.write(digits[i]);
  }
  return buf.toString();
}

/// Aplica máscara de telefone: (XX) XXXX-XXXX ou (XX) XXXXX-XXXX
String _mascaraTelefone(String digits) {
  final buf = StringBuffer();
  for (int i = 0; i < digits.length; i++) {
    if (i == 0) buf.write('(');
    if (i == 2) buf.write(') ');
    final dashPos = digits.length > 10 ? 7 : 6;
    if (i == dashPos) buf.write('-');
    buf.write(digits[i]);
  }
  return buf.toString();
}

/// Remove tudo que não é dígito
String _soDigitos(String v) => v.replaceAll(RegExp(r'[^0-9]'), '');

/// Aplica máscara a um valor já carregado (initState)
String _mascaraCpfCnpjValor(String raw) {
  final d = _soDigitos(raw);
  if (d.isEmpty) return raw;
  return _mascaraCpfCnpj(d);
}

/// Aplica máscara de telefone a um valor já carregado (initState)
String _mascaraTelefoneValor(String raw) {
  final d = _soDigitos(raw);
  if (d.isEmpty) return raw;
  return _mascaraTelefone(d);
}

/// Modal premium de resultado — compacto, elegante, centralizado
void _mostrarResultadoDialog(BuildContext context, String mensagem, {bool isError = false}) {
  showDialog(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    builder: (ctx) => Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.0, end: 1.0),
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutBack,
          builder: (context, scale, child) {
            return Transform.scale(
              scale: scale,
              child: child,
            );
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.12),
                  blurRadius: 32,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Ícone
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: isError
                        ? const Color(0xFFFEF2F2)
                        : const Color(0xFFF0FDF4),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isError
                        ? Icons.error_outline_rounded
                        : Icons.check_circle_outline_rounded,
                    size: 30,
                    color: isError
                        ? const Color(0xFFDC2626)
                        : const Color(0xFF16A34A),
                  ),
                ),
                const SizedBox(height: 18),
                // Título
                Text(
                  isError ? 'Erro' : 'Alterações salvas',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF1A1A2E),
                  ),
                ),
                const SizedBox(height: 8),
                // Mensagem
                Text(
                  isError
                      ? mensagem
                      : 'As informações foram atualizadas com sucesso.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    color: const Color(0xFF64748B),
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 24),
                // Botão
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6A1B9A),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    child: Text(
                      'Entendi',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 15, fontWeight: FontWeight.w700),
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

// ══════════════════════════════════════════════
//  CARD 6: INTEGRAÇÕES (premium)
// ══════════════════════════════════════════════

class _CardIntegracoes extends StatelessWidget {
  const _CardIntegracoes({required this.uidLoja});
  final String uidLoja;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('lojista_integracao')
          .where('store_id', isEqualTo: uidLoja)
          .snapshots(),
      builder: (ctx, snapLojista) {
        final docs = snapLojista.data?.docs ?? [];

        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('store_fiscal_settings')
              .doc(uidLoja)
              .snapshots(),
          builder: (ctx, snapFiscal) {
            final fiscalData = snapFiscal.hasData && snapFiscal.data!.exists
                ? snapFiscal.data!.data()
                : null;
            final integData = fiscalData?['integration_data'] as Map<String, dynamic>?;

            final hasIntegration = docs.isNotEmpty;

            return _SectionCard(
              title: 'Integrações',
              icon: Icons.integration_instructions_rounded,
              child: hasIntegration
                  ? Column(
                      children: docs.asMap().entries.map((entry) {
                        final doc = entry.value;
                        final d = doc.data();
                        final idx = entry.key;

                        final planoNome = d['plano_nome']?.toString() ?? 'Plano de emissão';
                        final status = d['status']?.toString() ?? 'ativa';
                        final notasEmitidas = (d['notas_emitidas'] as num?)?.toInt() ?? 0;
                        final limiteMensal = (d['limite_mensal'] as num?)?.toInt() ?? 0;
                        final cicloRef = d['ciclo_ref']?.toString() ?? '';
                        final ultSync = d['updated_at'] as Timestamp?;

                        final providerName = integData?['provider_name']?.toString() ?? planoNome;
                        final environment = integData?['environment']?.toString() ?? 'production';
                        final documentosEnabled = integData?['supported_documents'] as List<dynamic>? ?? [];

                        final restantes = limiteMensal > 0 ? limiteMensal - notasEmitidas : -1;

                        final statusLabel = status == 'ativa'
                            ? 'Ativa'
                            : status == 'suspensa'
                                ? 'Suspensa'
                                : 'Bloqueada';
                        final statusCor = status == 'ativa'
                            ? const Color(0xFF16A34A)
                            : status == 'suspensa'
                                ? const Color(0xFFEAB308)
                                : const Color(0xFFDC2626);
                        final statusFundo = status == 'ativa'
                            ? const Color(0xFFF0FDF4)
                            : status == 'suspensa'
                                ? const Color(0xFFFEFCE8)
                                : const Color(0xFFFEF2F2);

                        final ambienteLabel = environment == 'production' ? 'Produção' : 'Homologação';

                        return Padding(
                          padding: EdgeInsets.only(bottom: idx < docs.length - 1 ? 12 : 0),
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.grey.shade200),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.03),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Header do card
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 38,
                                        height: 38,
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF6A1B9A).withValues(alpha: 0.08),
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        child: Icon(
                                          _iconeIntegracao(providerName),
                                          size: 18,
                                          color: const Color(0xFF6A1B9A),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(providerName,
                                                style: GoogleFonts.plusJakartaSans(
                                                    fontSize: 14, fontWeight: FontWeight.w700,
                                                    color: const Color(0xFF1A1A2E))),
                                            if (planoNome != providerName)
                                              Text(planoNome,
                                                  style: GoogleFonts.plusJakartaSans(
                                                      fontSize: 11,
                                                      color: const Color(0xFF64748B))),
                                          ],
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: statusFundo,
                                          borderRadius: BorderRadius.circular(20),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Container(
                                              width: 7,
                                              height: 7,
                                              decoration: BoxDecoration(
                                                color: statusCor,
                                                shape: BoxShape.circle,
                                              ),
                                            ),
                                            const SizedBox(width: 5),
                                            Text(statusLabel,
                                                style: GoogleFonts.plusJakartaSans(
                                                    fontSize: 11, fontWeight: FontWeight.w600,
                                                    color: statusCor)),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                // Detalhes
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                                  child: Column(
                                    children: [
                                      _linhaInfo('Ambiente', ambienteLabel),
                                      _linhaInfo('Ciclo', cicloRef.isNotEmpty ? cicloRef : '—'),
                                      _linhaInfo('Última sincronização', _fmtData(ultSync)),
                                      _linhaInfo('Documentos', _docsLabel(documentosEnabled)),
                                      if (limiteMensal > 0) ...[
                                        _linhaInfo('Emitidas', '$notasEmitidas notas'),
                                        _linhaInfo('Disponível', '$restantes notas'),
                                      ] else ...[
                                        _linhaInfo('Emitidas', '$notasEmitidas notas'),
                                        _linhaInfo('Plano', 'Ilimitado'),
                                      ],
                                    ],
                                  ),
                                ),
                                // Botão Ver detalhes
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                                  child: Align(
                                    alignment: Alignment.centerRight,
                                    child: TextButton(
                                      onPressed: () => _mostrarModalDetalhesIntegracao(
                                        context,
                                        uidLoja: uidLoja,
                                        dadosLojista: d,
                                        integData: integData,
                                      ),
                                      style: TextButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                        minimumSize: Size.zero,
                                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                        foregroundColor: const Color(0xFF6A1B9A),
                                      ),
                                      child: Text('Ver detalhes',
                                          style: GoogleFonts.plusJakartaSans(
                                              fontSize: 12, fontWeight: FontWeight.w600)),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    )
                  // Empty state premium
                  : _buildEmptyState(context),
            );
          },
        );
      },
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: const Color(0xFF6A1B9A).withValues(alpha: 0.06),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.receipt_long_rounded,
              size: 28,
              color: const Color(0xFF6A1B9A).withValues(alpha: 0.4),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Nenhuma integração fiscal configurada',
            textAlign: TextAlign.center,
            style: GoogleFonts.plusJakartaSans(
                fontSize: 15, fontWeight: FontWeight.w700,
                color: const Color(0xFF1A1A2E)),
          ),
          const SizedBox(height: 8),
          Text(
            'Sua loja ainda não possui uma integração para emissão de documentos fiscais.',
            textAlign: TextAlign.center,
            style: GoogleFonts.plusJakartaSans(
                fontSize: 13, color: const Color(0xFF64748B), height: 1.4),
          ),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            icon: const Icon(Icons.support_agent_rounded, size: 16),
            label: Text('Solicitar configuração',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 13, fontWeight: FontWeight.w600)),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF6A1B9A),
              side: const BorderSide(color: Color(0xFF6A1B9A), width: 1.5),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () {
              _mostrarResultadoDialog(
                context,
                'A configuração da integração fiscal deve ser solicitada ao administrador do sistema.',
                isError: false,
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _linhaInfo(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(label,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 12, color: const Color(0xFF64748B))),
          ),
          Expanded(
            child: Text(value,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 12, fontWeight: FontWeight.w600,
                    color: const Color(0xFF1A1A2E))),
          ),
        ],
      ),
    );
  }

  IconData _iconeIntegracao(String nome) {
    final n = nome.toLowerCase();
    if (n.contains('focus')) return Icons.bolt_rounded;
    if (n.contains('nuvem')) return Icons.cloud_rounded;
    if (n.contains('plug') || n.contains('notas')) return Icons.receipt_rounded;
    if (n.contains('webmania')) return Icons.web_rounded;
    if (n.contains('enotas')) return Icons.description_rounded;
    if (n.contains('arquivei')) return Icons.archive_rounded;
    return Icons.link_rounded;
  }

  String _docsLabel(List<dynamic> docs) {
    if (docs.isEmpty) return '—';
    final map = {'nfe': 'NF-e', 'nfce': 'NFC-e', 'nfse': 'NFS-e', 'cte': 'CT-e', 'mdfe': 'MDF-e'};
    return docs.map((d) => map[d.toString()] ?? d.toString()).join(', ');
  }
}

/// Modal premium com detalhes completos da integração
void _mostrarModalDetalhesIntegracao(
  BuildContext context, {
  required String uidLoja,
  required Map<String, dynamic> dadosLojista,
  required Map<String, dynamic>? integData,
}) {
  final planoNome = dadosLojista['plano_nome']?.toString() ?? '—';
  final limiteMensal = (dadosLojista['limite_mensal'] as num?)?.toInt() ?? 0;
  final notasEmitidas = (dadosLojista['notas_emitidas'] as num?)?.toInt() ?? 0;
  final restantes = limiteMensal > 0 ? limiteMensal - notasEmitidas : -1;
  final status = dadosLojista['status']?.toString() ?? 'ativa';
  final criadoEm = dadosLojista['created_at'] as Timestamp?;
  final ultAtualizacao = dadosLojista['updated_at'] as Timestamp?;
  final cicloRef = dadosLojista['ciclo_ref']?.toString() ?? '—';
  final proximaRenovacao = dadosLojista['proxima_renovacao'] as Timestamp?;

  final providerName = integData?['provider_name']?.toString() ?? planoNome;
  final environment = integData?['environment']?.toString() ?? 'production';

  showDialog(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    builder: (ctx) => Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 680),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 32,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.fromLTRB(24, 20, 20, 16),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF6A1B9A), Color(0xFF8E24AA)],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.integration_instructions_rounded,
                          color: Colors.white, size: 20),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(providerName,
                              style: GoogleFonts.plusJakartaSans(
                                  fontSize: 16, fontWeight: FontWeight.w700,
                                  color: Colors.white)),
                          const SizedBox(height: 2),
                          Text(planoNome != providerName ? planoNome : '',
                              style: GoogleFonts.plusJakartaSans(
                                  fontSize: 12,
                                  color: Colors.white.withValues(alpha: 0.75))),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded,
                          color: Colors.white, size: 22),
                      onPressed: () => Navigator.of(ctx).pop(),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
              ),
              // Body
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _infoDetalhe('Provedor', providerName),
                      _infoDetalhe('Plano', planoNome),
                      _infoDetalhe('Ambiente',
                          environment == 'production' ? 'Produção' : 'Homologação (Sandbox)'),
                      _infoDetalhe('Ciclo de referência', cicloRef),
                      _infoDetalhe('Status', status == 'ativa'
                          ? 'Ativa'
                          : status == 'suspensa'
                              ? 'Suspensa'
                              : 'Bloqueada'),
                      _infoDetalhe('Data de criação', _fmtData(criadoEm)),
                      _infoDetalhe('Última atualização', _fmtData(ultAtualizacao)),
                      _infoDetalhe('Próxima renovação', _fmtData(proximaRenovacao)),
                      const Divider(height: 24),
                      _infoDetalhe('Total emitido', '$notasEmitidas documentos'),
                      if (limiteMensal > 0) ...[
                        _infoDetalhe('Limite do plano', '$limiteMensal notas/mês'),
                        _infoDetalhe('Disponível', '$restantes notas'),
                      ] else ...[
                        _infoDetalhe('Plano', 'Ilimitado'),
                      ],
                    ],
                  ),
                ),
              ),
              // Footer
              Container(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
                decoration: BoxDecoration(
                  border: Border(
                      top: BorderSide(color: Colors.grey.shade200)),
                ),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6A1B9A),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                    child: Text('Fechar',
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 14, fontWeight: FontWeight.w700)),
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

Widget _infoDetalhe(String label, String value) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 140,
          child: Text(label,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 12.5, color: const Color(0xFF64748B))),
        ),
        Expanded(
          child: Text(value,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 13, fontWeight: FontWeight.w600,
                  color: const Color(0xFF1A1A2E))),
        ),
      ],
    ),
  );
}

// ══════════════════════════════════════════════
//  CARD 7: SEGURANÇA
// ══════════════════════════════════════════════

class _CardSeguranca extends StatelessWidget {
  const _CardSeguranca({required this.uidLoja});
  final String uidLoja;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('users').doc(uidLoja).snapshots(),
      builder: (ctx, snap) {
        final d = snap.data?.data() ?? {};
        final ultimoAcesso = d['ultimo_login'] as Timestamp?;

        return _SectionCard(
          title: 'Segurança',
          icon: Icons.security_rounded,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _InfoLinha(label: 'Último acesso', value: _fmtData(ultimoAcesso)),
              _InfoLinha(label: 'Autenticação 2 fatores', value: 'Desativado'),
              _InfoLinha(label: 'Sessões ativas', value: '1'),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                icon: const Icon(Icons.lock_rounded, size: 14),
                label: Text('Alterar senha', style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w600)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF6A1B9A),
                  side: const BorderSide(color: Color(0xFF6A1B9A), width: 1.5),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  minimumSize: Size.zero,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () {
                  // TODO: Alterar senha
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

// ══════════════════════════════════════════════
//  CARD 8: CONTATOS
// ══════════════════════════════════════════════

class _CardContatos extends StatelessWidget {
  const _CardContatos({required this.dadosUsuario});
  final Map<String, dynamic> dadosUsuario;

  String _v(String key, {String fb = '—'}) {
    final v = dadosUsuario[key]?.toString();
    return (v != null && v.trim().isNotEmpty) ? v.trim() : fb;
  }

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'Contatos',
      icon: Icons.contacts_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _InfoLinha(label: 'Responsável', value: _v('owner_name', fb: _v('nome', fb: _v('nome_completo')))),
          _InfoLinha(label: 'Telefone', value: _v('telefone')),
          _InfoLinha(label: 'E-mail', value: _v('email')),
          _InfoLinha(label: 'WhatsApp', value: _v('whatsapp', fb: _v('celular'))),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════
//  CARD 9: SUPORTE
// ══════════════════════════════════════════════

class _CardSuporte extends StatelessWidget {
  const _CardSuporte();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF6A1B9A).withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF6A1B9A).withValues(alpha: 0.1)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Precisa de ajuda?',
                    style: GoogleFonts.plusJakartaSans(fontSize: 15, fontWeight: FontWeight.w700, color: const Color(0xFF1A1A2E))),
                const SizedBox(height: 4),
                Text('Conte com nossa equipe para resolver qualquer questão.',
                    style: GoogleFonts.plusJakartaSans(fontSize: 13, color: const Color(0xFF64748B))),
              ],
            ),
          ),
          const SizedBox(width: 16),
          FilledButton.icon(
            icon: const Icon(Icons.headset_mic_rounded, size: 16),
            label: Text('Abrir chamado', style: GoogleFonts.plusJakartaSans(fontSize: 12.5, fontWeight: FontWeight.w600)),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF6A1B9A),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => context.navegarPainel('/atendimento_suporte'),
          ),
        ],
      ),
    );
  }
}
