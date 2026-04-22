import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:depertin_web/services/carteira_lojista_extrato.dart';
import 'package:depertin_web/services/firebase_functions_config.dart';
import 'package:depertin_web/theme/painel_admin_theme.dart';
import 'package:depertin_web/utils/lojista_painel_context.dart';
import 'package:depertin_web/widgets/botao_suporte_flutuante.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

/// Snapshot agregado dos listeners do painel. Um único [StreamBuilder] evita
/// aninhar 5× `.snapshots()` — no Flutter Web (hot reload R) isso dispara
/// bugs internos do Firestore (`INTERNAL ASSERTION FAILED`).
class _CarteiraRealtime {
  DocumentSnapshot<Map<String, dynamic>>? user;
  QuerySnapshot<Map<String, dynamic>>? saques;
  QuerySnapshot<Map<String, dynamic>>? pedidosLoja;
  QuerySnapshot<Map<String, dynamic>>? pedidosLojista;
  QuerySnapshot<Map<String, dynamic>>? estornos;
}

// ─────────────────────────────────────────────────────────────────────────────
// Tela
// ─────────────────────────────────────────────────────────────────────────────
class LojistaMinhaCarteiraScreen extends StatefulWidget {
  const LojistaMinhaCarteiraScreen({super.key});

  @override
  State<LojistaMinhaCarteiraScreen> createState() =>
      _LojistaMinhaCarteiraScreenState();
}

class _LojistaMinhaCarteiraScreenState
    extends State<LojistaMinhaCarteiraScreen> {
  static const _roxo = PainelAdminTheme.roxo;
  static const _laranja = PainelAdminTheme.laranja;
  static const _verde = Color(0xFF15803D);
  static const _cinzaFundo = Color(0xFFF4F3F8);

  bool _mostrarSaldo = true;
  String _filtroExtrato = 'todos'; // todos | entradas | saidas

  final _valorC = TextEditingController();
  final _chavePixC = TextEditingController();
  final _titularC = TextEditingController();
  final _bancoC = TextEditingController();

  /// Snapshot atual (sem [StreamBuilder] — hot reload `r` re-subscreve mal a streams).
  _CarteiraRealtime _carteiraLive = _CarteiraRealtime();
  Object? _carteiraErro;
  final List<StreamSubscription<dynamic>> _carteiraSubs = [];
  String? _carteiraStreamUid;

  void _pararListenersCarteira() {
    for (final s in _carteiraSubs) {
      s.cancel();
    }
    _carteiraSubs.clear();
    _carteiraStreamUid = null;
    _carteiraLive = _CarteiraRealtime();
    _carteiraErro = null;
  }

  void _garantirListenersCarteira(String uid) {
    if (_carteiraStreamUid == uid && _carteiraSubs.isNotEmpty) return;
    _pararListenersCarteira();
    _carteiraStreamUid = uid;

    void emitErroPerfil(Object e, StackTrace st) {
      _carteiraErro = e;
      if (mounted) setState(() {});
    }

    void ignorarErroStream(String nome, Object e, [StackTrace? st]) {
      debugPrint('[MinhaCarteira] stream $nome: $e ${st ?? ''}');
    }

    void atualizar(void Function() fn) {
      fn();
      _carteiraErro = null;
      if (mounted) setState(() {});
    }

    _carteiraSubs.addAll([
      FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .snapshots()
          .listen(
            (s) {
              final d = s.data();
              if (s.exists && d != null && !d.containsKey('saldo')) {
                FirebaseFirestore.instance
                    .collection('users')
                    .doc(uid)
                    .set(
                      {'saldo': 0},
                      SetOptions(merge: true),
                    )
                    .catchError(
                      (Object e, StackTrace st) => debugPrint(
                        '[MinhaCarteira] init saldo: $e',
                      ),
                    );
              }
              atualizar(() => _carteiraLive.user = s);
            },
            onError: emitErroPerfil,
          ),
      FirebaseFirestore.instance
          .collection('saques_solicitacoes')
          .where('user_id', isEqualTo: uid)
          .snapshots()
          .listen(
            (s) => atualizar(() => _carteiraLive.saques = s),
            onError: (e, st) =>
                ignorarErroStream('saques_solicitacoes', e, st),
          ),
      FirebaseFirestore.instance
          .collection('pedidos')
          .where('loja_id', isEqualTo: uid)
          .snapshots()
          .listen(
            (s) => atualizar(() => _carteiraLive.pedidosLoja = s),
            onError: (e, st) => ignorarErroStream('pedidos_loja_id', e, st),
          ),
      FirebaseFirestore.instance
          .collection('pedidos')
          .where('lojista_id', isEqualTo: uid)
          .snapshots()
          .listen(
            (s) => atualizar(() => _carteiraLive.pedidosLojista = s),
            onError: (e, st) =>
                ignorarErroStream('pedidos_lojista_id', e, st),
          ),
      FirebaseFirestore.instance
          .collection('estornos')
          .where('loja_id', isEqualTo: uid)
          .snapshots()
          .listen(
            (s) => atualizar(() => _carteiraLive.estornos = s),
            onError: (e, st) => ignorarErroStream('estornos', e, st),
          ),
    ]);
  }

  @override
  void dispose() {
    _pararListenersCarteira();
    _valorC.dispose();
    _chavePixC.dispose();
    _titularC.dispose();
    _bancoC.dispose();
    super.dispose();
  }

  // ── helpers ──────────────────────────────────────────────────────────────
  static double _num(dynamic v) => CarteiraLojistaExtrato.numDyn(v);

  /// Mesmo arredondamento que [saque_solicitar.js] `roundMoney`.
  static double _roundMoney(double v) => (v * 100).round() / 100.0;

  static String _nomeMes(int m) {
    const n = [
      '',
      'Janeiro', 'Fevereiro', 'Março',
      'Abril', 'Maio', 'Junho',
      'Julho', 'Agosto', 'Setembro',
      'Outubro', 'Novembro', 'Dezembro',
    ];
    return n[m];
  }

  /// Nome sugerido para o campo "titular" no PIX (perfil Firestore / Auth).
  static String _titularSugestaoDePerfil(
    Map<String, dynamic>? ud, [
    String? authDisplayName,
  ]) {
    if (ud != null) {
      for (final k in [
        'nome_completo',
        'nome',
        'nome_titular',
        'display_name',
      ]) {
        final v = ud[k]?.toString().trim();
        if (v != null && v.isNotEmpty) return v;
      }
    }
    final a = authDisplayName?.trim();
    if (a != null && a.isNotEmpty) return a;
    return '';
  }

  /// Titular da chave salva ou, se não houver, o mesmo do perfil.
  static String _titularParaChaveSalva(
    Map<String, dynamic> dataChave,
    Map<String, dynamic>? perfilUsuario, [
    String? authDisplayName,
  ]) {
    for (final k in ['titular_conta', 'titular', 'nome_titular']) {
      final v = dataChave[k]?.toString().trim();
      if (v != null && v.isNotEmpty) return v;
    }
    return _titularSugestaoDePerfil(perfilUsuario, authDisplayName);
  }

  static bool _mesmoMes(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month;

  /// Pop-up compacto após saque concluído (largura máx. fixa — evita faixa larga no web).
  Future<void> _mostrarDialogoSaqueSucesso(
    BuildContext context,
    double valor,
  ) async {
    if (!context.mounted) return;
    final valorFmt =
        NumberFormat.currency(locale: 'pt_BR', symbol: r'R$').format(valor);
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel:
          MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      transitionDuration: const Duration(milliseconds: 280),
      pageBuilder: (ctx, animation, secondaryAnimation) {
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 300),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Material(
                color: Colors.white,
                elevation: 10,
                shadowColor: Colors.black.withValues(alpha: 0.14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: Colors.grey.shade200),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: const Color(0xFF15803D).withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.check_rounded,
                          color: Color(0xFF15803D),
                          size: 26,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'Solicitação de saque',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2,
                          color: const Color(0xFF1E1B4B),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Parabéns! Sua solicitação de saque no $valorFmt foi efetuada com sucesso.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.4,
                          color: Colors.grey.shade700,
                        ),
                      ),
                      const SizedBox(height: 18),
                      Center(
                        child: FilledButton(
                          onPressed: () => Navigator.of(ctx).pop(),
                          style: FilledButton.styleFrom(
                            backgroundColor: _verde,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 28,
                              vertical: 11,
                            ),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: const Text(
                            'Entendi',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
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
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.94, end: 1.0).animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  static InputDecoration _dec(String label, {IconData? icon}) =>
      InputDecoration(
        labelText: label,
        prefixIcon: icon != null ? Icon(icon, size: 18) : null,
        filled: true,
        fillColor: const Color(0xFFF8F7FC),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _roxo, width: 1.5),
        ),
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      );

  // ── dialog transferência ─────────────────────────────────────────────────
  Future<void> _abrirTransferencia(
    BuildContext context, {
    required String uid,
    required double saldoDisponivel,
    required NumberFormat moeda,
    Map<String, dynamic>? dadosUsuario,
  }) async {
    _valorC.clear();
    _chavePixC.clear();
    _titularC.clear();
    _bancoC.clear();
    _titularC.text = _titularSugestaoDePerfil(
      dadosUsuario,
      FirebaseAuth.instance.currentUser?.displayName,
    );
    String? chavePixDocIdTransferencia;
    /// Evita `.snapshots()` no modal — no Flutter Web, Esc pode derrubar o SDK Firestore.
    var chavesPixReloadKey = 0;

    if (saldoDisponivel <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sem saldo disponível para transferência.'),
          backgroundColor: Color(0xFFB91C1C),
        ),
      );
      return;
    }

    await showDialog<void>(
      context: context,
      // true: Esc / clique fora alinham com a rota do barrier (evita assert com overlay do Dropdown).
      barrierDismissible: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
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
                          color: _verde.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.pix, color: _verde, size: 22),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Transferência PIX',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                                color: const Color(0xFF1E1B4B),
                              ),
                            ),
                            Text(
                              'Saldo: ${moeda.format(saldoDisponivel)}',
                              style: TextStyle(
                                fontSize: 12,
                                color: _verde,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _valorC,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[\d.,]')),
                    ],
                    decoration: _dec(
                      'Valor',
                      icon: Icons.attach_money_rounded,
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () {
                        _valorC.text = _roundMoney(saldoDisponivel)
                            .toStringAsFixed(2)
                            .replaceAll('.', ',');
                        setS(() {});
                      },
                      icon: const Icon(Icons.bolt_rounded, size: 14),
                      label: const Text('Usar tudo'),
                      style: TextButton.styleFrom(
                        foregroundColor: _laranja,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 2,
                        ),
                        textStyle: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
                  FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    key: ValueKey<int>(chavesPixReloadKey),
                    future: FirebaseFirestore.instance
                        .collection('users')
                        .doc(uid)
                        .collection('chaves_pix')
                        .orderBy('criado_em', descending: true)
                        .get(),
                    builder: (context, snap) {
                      if (snap.connectionState == ConnectionState.waiting &&
                          !snap.hasData) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: _roxo,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                'Carregando chaves…',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ),
                        );
                      }
                      if (snap.hasError) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'Não foi possível carregar as chaves salvas.',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.red.shade700,
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _chavePixC,
                              decoration: _dec(
                                'Chave PIX (CPF, e-mail, tel ou aleatória)',
                                icon: Icons.pix,
                              ),
                            ),
                          ],
                        );
                      }
                      final docs = snap.data?.docs ?? [];
                      if (docs.isEmpty) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: _roxo.withValues(alpha: 0.06),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: _roxo.withValues(alpha: 0.2),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Nenhuma chave PIX salva.',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                      color: Colors.grey.shade800,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'Cadastre uma chave para reutilizar nas próximas transferências.',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  TextButton.icon(
                                    onPressed: () async {
                                      await _abrirCadastroChavePix(
                                        context,
                                        uid: uid,
                                      );
                                      chavesPixReloadKey++;
                                      setS(() {});
                                    },
                                    icon: const Icon(
                                      Icons.add_circle_outline,
                                      size: 18,
                                    ),
                                    label: const Text('Cadastrar chave PIX'),
                                    style: TextButton.styleFrom(
                                      foregroundColor: _roxo,
                                      textStyle: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _chavePixC,
                              decoration: _dec(
                                'Chave PIX (CPF, e-mail, tel ou aleatória)',
                                icon: Icons.pix,
                              ),
                            ),
                          ],
                        );
                      }

                      String? docIdSelecionado;
                      if (chavePixDocIdTransferencia != null &&
                          docs.any((d) => d.id == chavePixDocIdTransferencia)) {
                        docIdSelecionado = chavePixDocIdTransferencia;
                      } else {
                        final alvo = _chavePixC.text.trim();
                        if (alvo.isNotEmpty) {
                          for (final d in docs) {
                            final ch = (d.data()['chave'] ?? '').toString();
                            if (ch == alvo) {
                              docIdSelecionado = d.id;
                              chavePixDocIdTransferencia = d.id;
                              break;
                            }
                          }
                        }
                      }

                      // Lista com Radio (sem rota de overlay do Dropdown) — Esc não conflita com o pop.
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.pix, size: 18, color: Colors.grey.shade700),
                              const SizedBox(width: 8),
                              Text(
                                'Chave PIX',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.grey.shade700,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 220),
                            child: Material(
                              color: const Color(0xFFF8F7FC),
                              borderRadius: BorderRadius.circular(12),
                              child: ListView.separated(
                                shrinkWrap: true,
                                padding: const EdgeInsets.symmetric(vertical: 4),
                                itemCount: docs.length,
                                separatorBuilder: (context, index) =>
                                    Divider(
                                  height: 1,
                                  color: Colors.grey.shade200,
                                ),
                                itemBuilder: (context, i) {
                                  final d = docs[i];
                                  final data = d.data();
                                  final ap =
                                      (data['apelido'] ?? '').toString().trim();
                                  final ch =
                                      (data['chave'] ?? '').toString();
                                  final label =
                                      ap.isNotEmpty ? '$ap · $ch' : ch;
                                  final sel = docIdSelecionado == d.id;
                                  return Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      onTap: () {
                                        chavePixDocIdTransferencia = d.id;
                                        _chavePixC.text = ch;
                                        _titularC.text = _titularParaChaveSalva(
                                          data,
                                          dadosUsuario,
                                          FirebaseAuth.instance.currentUser
                                              ?.displayName,
                                        );
                                        setS(() {});
                                      },
                                      borderRadius: BorderRadius.circular(8),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 10,
                                        ),
                                        child: Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Icon(
                                              sel
                                                  ? Icons.radio_button_checked
                                                  : Icons.radio_button_off,
                                              color: sel
                                                  ? _roxo
                                                  : Colors.grey.shade400,
                                              size: 20,
                                            ),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: Text(
                                                label,
                                                maxLines: 3,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  fontWeight: sel
                                                      ? FontWeight.w700
                                                      : FontWeight.w400,
                                                  color: Colors.grey.shade800,
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
                            ),
                          ),
                          if (docIdSelecionado == null)
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(
                                'Selecione uma chave acima.',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _titularC,
                    textCapitalization: TextCapitalization.words,
                    decoration: _dec(
                      'Nome do titular',
                      icon: Icons.person_outline_rounded,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _bancoC,
                    textCapitalization: TextCapitalization.words,
                    decoration: _dec(
                      'Banco (opcional)',
                      icon: Icons.account_balance_outlined,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _laranja.withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: _laranja.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.info_outline_rounded,
                          size: 15,
                          color: _laranja,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'O saldo é reservado imediatamente. A equipe DiPertin processa o PIX em até 24 h úteis.',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade700,
                              height: 1.35,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(ctx),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text('Cancelar'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: _verde,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: () async {
                            final raw = _valorC.text.replaceAll(',', '.');
                            final v = _roundMoney(double.tryParse(raw) ?? 0);
                            final chave = _chavePixC.text.trim();
                            final titular = _titularC.text.trim();
                            if (v <= 0 || v > saldoDisponivel) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Valor inválido ou maior que o saldo.',
                                  ),
                                  backgroundColor: Color(0xFFB91C1C),
                                ),
                              );
                              return;
                            }
                            if (chave.isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Selecione uma chave na lista ou digite a chave PIX.',
                                  ),
                                  backgroundColor: Color(0xFFB91C1C),
                                ),
                              );
                              return;
                            }
                            if (titular.isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Informe o nome do titular da conta PIX.',
                                  ),
                                  backgroundColor: Color(0xFFB91C1C),
                                ),
                              );
                              return;
                            }
                            try {
                              await callFirebaseFunctionSafe(
                                'solicitarSaque',
                                parameters: {
                                  'tipo_usuario': 'lojista',
                                  'valor': v,
                                  'chave_pix': chave,
                                  'titular_conta': titular,
                                  'banco': _bancoC.text.trim(),
                                },
                              );
                              if (ctx.mounted) Navigator.pop(ctx);
                              if (context.mounted) {
                                await _mostrarDialogoSaqueSucesso(context, v);
                              }
                            } on FirebaseFunctionsException catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(e.message ?? e.code),
                                    backgroundColor: const Color(0xFFB91C1C),
                                  ),
                                );
                              }
                            } on CallableHttpException catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(e.message),
                                    backgroundColor: const Color(0xFFB91C1C),
                                  ),
                                );
                              }
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Erro: $e'),
                                    backgroundColor: Colors.red,
                                  ),
                                );
                              }
                            }
                          },
                          icon: const Icon(Icons.send_rounded, size: 16),
                          label: const Text(
                            'Transferir',
                            style: TextStyle(fontWeight: FontWeight.w700),
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
  }

  // ── Chaves PIX (Visão geral → botão PIX) ─────────────────────────────────
  Future<void> _abrirCadastroChavePix(
    BuildContext context, {
    required String uid,
  }) async {
    final apelidoC = TextEditingController();
    final chaveC = TextEditingController();
    try {
      await showDialog<void>(
        context: context,
        builder: (ctx) => Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Padding(
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
                          color: _roxo.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.pix, color: _roxo, size: 22),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Cadastrar chave PIX',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF1E1B4B),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: apelidoC,
                    decoration: _dec('Apelido (opcional)', icon: Icons.label_outline),
                    textCapitalization: TextCapitalization.sentences,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: chaveC,
                    decoration: _dec(
                      'Chave (CPF, e-mail, telefone ou aleatória)',
                      icon: Icons.key_outlined,
                    ),
                    keyboardType: TextInputType.text,
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(ctx),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text('Cancelar'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: _roxo,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: () async {
                            final chave = chaveC.text.trim();
                            if (chave.isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Informe a chave PIX.'),
                                  backgroundColor: Color(0xFFB91C1C),
                                ),
                              );
                              return;
                            }
                            try {
                              await FirebaseFirestore.instance
                                  .collection('users')
                                  .doc(uid)
                                  .collection('chaves_pix')
                                  .add({
                                'chave': chave,
                                'apelido': apelidoC.text.trim(),
                                'criado_em': FieldValue.serverTimestamp(),
                              });
                              if (ctx.mounted) Navigator.pop(ctx);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Chave PIX salva.'),
                                    backgroundColor: _verde,
                                  ),
                                );
                              }
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Erro: $e'),
                                    backgroundColor: Colors.red,
                                  ),
                                );
                              }
                            }
                          },
                          icon: const Icon(Icons.save_outlined, size: 18),
                          label: const Text(
                            'Salvar',
                            style: TextStyle(fontWeight: FontWeight.w700),
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
    } finally {
      apelidoC.dispose();
      chaveC.dispose();
    }
  }

  Future<void> _abrirModalChavesPix(
    BuildContext context, {
    required String uid,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420, maxHeight: 520),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 12, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: _roxo.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.pix, color: _roxo, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Minhas chaves PIX',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF1E1B4B),
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close),
                      tooltip: 'Fechar',
                    ),
                  ],
                ),
                Text(
                  'Cadastre chaves para agilizar ao solicitar transferência.',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: FirebaseFirestore.instance
                        .collection('users')
                        .doc(uid)
                        .collection('chaves_pix')
                        .orderBy('criado_em', descending: true)
                        .snapshots(),
                    builder: (context, snap) {
                      if (snap.hasError) {
                        return Center(
                          child: Text(
                            'Erro ao carregar: ${snap.error}',
                            textAlign: TextAlign.center,
                          ),
                        );
                      }
                      if (!snap.hasData) {
                        return const Center(
                          child: CircularProgressIndicator(color: _roxo),
                        );
                      }
                      final docs = snap.data!.docs;
                      if (docs.isEmpty) {
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(
                              'Nenhuma chave cadastrada.\nToque abaixo para adicionar.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.grey.shade600),
                            ),
                          ),
                        );
                      }
                      return ListView.separated(
                        padding: EdgeInsets.zero,
                        itemCount: docs.length,
                        separatorBuilder: (context, index) =>
                            Divider(height: 1, color: Colors.grey.shade200),
                        itemBuilder: (context, i) {
                          final d = docs[i].data();
                          final apelido =
                              (d['apelido'] ?? '').toString().trim();
                          final chave = (d['chave'] ?? '').toString();
                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 4,
                            ),
                            title: Text(
                              apelido.isNotEmpty ? apelido : 'Chave PIX',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              chave,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade700,
                              ),
                            ),
                            trailing: IconButton(
                              icon: Icon(
                                Icons.delete_outline,
                                color: Colors.grey.shade600,
                              ),
                              tooltip: 'Remover',
                              onPressed: () async {
                                final ok = await showDialog<bool>(
                                  context: context,
                                  builder: (c) => AlertDialog(
                                    title: const Text('Remover chave?'),
                                    content: const Text(
                                      'Esta ação não pode ser desfeita.',
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(c, false),
                                        child: const Text('Cancelar'),
                                      ),
                                      FilledButton(
                                        onPressed: () =>
                                            Navigator.pop(c, true),
                                        style: FilledButton.styleFrom(
                                          backgroundColor: const Color(
                                            0xFFB91C1C,
                                          ),
                                        ),
                                        child: const Text('Remover'),
                                      ),
                                    ],
                                  ),
                                );
                                if (ok != true) return;
                                try {
                                  await docs[i].reference.delete();
                                } catch (e) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('Erro: $e'),
                                        backgroundColor: Colors.red,
                                      ),
                                    );
                                  }
                                }
                              },
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: _roxo,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () async {
                    await _abrirCadastroChavePix(context, uid: uid);
                  },
                  icon: const Icon(Icons.add, size: 20),
                  label: const Text(
                    'Cadastrar chave PIX',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Build principal ──────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final authUid = FirebaseAuth.instance.currentUser?.uid;
    if (authUid == null) {
      return const Scaffold(
        body: Center(child: Text('Não autenticado.')),
      );
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(authUid)
          .snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return const Scaffold(
            backgroundColor: _cinzaFundo,
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final d = snap.data?.data();
        final uid = uidLojaEfetivo(d, authUid);
        if (d != null && !painelMostrarAreaCarteiraEConfig(d)) {
          return painelLojistaSemPermissaoScaffold(
            mensagem:
                'Sua conta não tem permissão para a carteira neste painel.',
          );
        }

    final moeda = NumberFormat.currency(locale: 'pt_BR', symbol: r'R$');

    _garantirListenersCarteira(uid);

    if (_carteiraErro != null) {
      return Scaffold(
        backgroundColor: _cinzaFundo,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Erro ao carregar dados.\n$_carteiraErro',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    if (_carteiraLive.user == null) {
      return Scaffold(
        backgroundColor: _cinzaFundo,
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    final live = _carteiraLive;

    return Scaffold(
      backgroundColor: _cinzaFundo,
      floatingActionButton: const BotaoSuporteFlutuante(),
      body: LayoutBuilder(
        builder: (context, c) {
          // ── dados usuário ──
          final ud = live.user!.data();
          final nomeLoja = (ud?['loja_nome'] ?? ud?['nome'] ?? 'Lojista')
              .toString();
          // Saldo do Firestore (atualizado pela CF e pelos saques)
          double saldoFirestore = 0;
          if (ud != null) {
            final r = ud['saldo'];
            saldoFirestore =
                r is num ? r.toDouble() : double.tryParse('$r') ?? 0;
          }

          // ── dados saques ──
          final saqDocs = live.saques?.docs ?? [];
          double somaSaquesDebitados = 0; // todos exceto recusado
          double somaPendente = 0;
          double somaPago = 0;
          int qPendente = 0;
          for (final d in saqDocs) {
            final s = d.data();
            final st = s['status']?.toString() ?? 'pendente';
            final v = _num(s['valor']);
            if (st != 'recusado') somaSaquesDebitados += v;
            if (st == 'pendente') {
              somaPendente += v;
              qPendente++;
            }
            if (st == 'pago') somaPago += v;
          }

          // ── dados estornos ──
          final estornoDocs = live.estornos?.docs ?? [];
          double somaEstornos = 0;
          for (final d in estornoDocs) {
            final op = d.data()['tipo_operacao']?.toString() ?? '';
            if (op == 'credito_saque_recusado') continue;
            somaEstornos += _num(d.data()['valor']);
          }

          // ── dados pedidos (mescla loja_id + lojista_id) ──
          final seenIds = <String>{};
          final pedDocs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
          for (final d in [
            ...(live.pedidosLoja?.docs ?? []),
            ...(live.pedidosLojista?.docs ?? []),
          ]) {
            if (seenIds.add(d.id)) pedDocs.add(d);
          }

          double totalCreditado = 0;
          int qEntregues = 0;
          for (final d in pedDocs) {
            final st = d.data()['status']?.toString() ?? '';
            if (st == 'entregue' ||
                st == 'concluido' ||
                st == 'finalizado') {
              totalCreditado += CarteiraLojistaExtrato.creditoLoja(d.data());
              qEntregues++;
            }
          }

          // ── Conferência: soma pedidos entregues − saques − estornos (informativo).
          final saldoComputado = _roundMoney(math.max(
            0.0,
            totalCreditado - somaSaquesDebitados - somaEstornos,
          ));
          // Saque usa só `users.saldo` (Cloud Function solicitarSaque) — não misturar com a conferência.
          final saldoConta = _roundMoney(saldoFirestore);

          final lancamentos = CarteiraLojistaExtrato.buildLancamentos(
            saqDocs,
            pedDocs,
            estornoDocs,
          );
          final filtrados = lancamentos.where((l) {
            if (_filtroExtrato == 'entradas') return l.entrada;
            if (_filtroExtrato == 'saidas') return !l.entrada;
            return true;
          }).toList();

          final wide = c.maxWidth >= 860;

          final painelEsq = _painelEsquerdo(
            context,
            uid: uid,
            moeda: moeda,
            saldoConta: saldoConta,
            saldoConferencia: saldoComputado,
            nomeLoja: nomeLoja,
            dadosUsuario: ud,
            somaPendente: somaPendente,
            qPendente: qPendente,
            somaPago: somaPago,
            totalCreditado: totalCreditado,
            qEntregues: qEntregues,
          );

          if (wide) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 340,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(
                      16,
                      16,
                      8,
                      80,
                    ),
                    child: painelEsq,
                  ),
                ),
                Expanded(
                  child: _painelExtrato(context, filtrados, moeda),
                ),
              ],
            );
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                painelEsq,
                const SizedBox(height: 16),
                _extratoHeader(filtrados, moeda),
                const SizedBox(height: 8),
                if (filtrados.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(32),
                    child: Center(
                      child: Text(
                        'Nenhum lançamento ainda.',
                        style: TextStyle(
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ),
                  )
                else
                  ..._extratoItensFlat(context, filtrados, moeda),
              ],
            ),
          );
        },
      ),
    );
      },
    );
  }

  // ── Painel esquerdo ───────────────────────────────────────────────────────
  Widget _painelEsquerdo(
    BuildContext context, {
    required String uid,
    required NumberFormat moeda,
    required double saldoConta,
    required double saldoConferencia,
    required String nomeLoja,
    required Map<String, dynamic>? dadosUsuario,
    required double somaPendente,
    required int qPendente,
    required double somaPago,
    required double totalCreditado,
    required int qEntregues,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _cartaoVirtual(
          moeda,
          saldoConta,
          nomeLoja,
          saldoConferencia: saldoConferencia,
        ),
        const SizedBox(height: 12),
        _acoesRapidas(
          context,
          uid: uid,
          moeda: moeda,
          saldoDisponivelSaque: saldoConta,
          dadosUsuario: dadosUsuario,
        ),
        const SizedBox(height: 12),
        _kpiGrid(
          moeda: moeda,
          somaPendente: somaPendente,
          qPendente: qPendente,
          somaPago: somaPago,
          totalCreditado: totalCreditado,
          qEntregues: qEntregues,
        ),
        const SizedBox(height: 12),
        _painelComoFunciona(),
      ],
    );
  }

  // ── Cartão visual ─────────────────────────────────────────────────────────
  Widget _cartaoVirtual(
    NumberFormat moeda,
    double saldoConta,
    String nome, {
    required double saldoConferencia,
  }) {
    return Container(
      height: 192,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF312E81), _roxo, Color(0xFF6D28D9)],
          stops: [0.0, 0.5, 1.0],
        ),
        boxShadow: [
          BoxShadow(
            color: _roxo.withValues(alpha: 0.38),
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -50,
            top: -50,
            child: _bolha(200, 0.06),
          ),
          Positioned(
            right: 30,
            bottom: -55,
            child: _bolha(150, 0.04),
          ),
          Positioned(
            left: -25,
            bottom: 10,
            child: _bolha(110, 0.03),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'DiPertin',
                        style: GoogleFonts.plusJakartaSans(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      'CARTEIRA LOJISTA',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.6),
                        fontSize: 8,
                        letterSpacing: 1.6,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                Text(
                  'SALDO DISPONÍVEL',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.65),
                    fontSize: 9,
                    letterSpacing: 1.6,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Flexible(
                      child: _mostrarSaldo
                          ? Text(
                              moeda.format(saldoConta),
                              style: GoogleFonts.plusJakartaSans(
                                color: Colors.white,
                                fontSize: 26,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.5,
                              ),
                              overflow: TextOverflow.ellipsis,
                            )
                          : Text(
                              '• • • • •',
                              style: GoogleFonts.plusJakartaSans(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 5,
                              ),
                            ),
                    ),
                    const SizedBox(width: 10),
                    GestureDetector(
                      onTap: () =>
                          setState(() => _mostrarSaldo = !_mostrarSaldo),
                      child: Icon(
                        _mostrarSaldo
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        color: Colors.white.withValues(alpha: 0.7),
                        size: 20,
                      ),
                    ),
                  ],
                ),
                if (nome.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    nome.toUpperCase(),
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 10,
                      letterSpacing: 1.3,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                if (_mostrarSaldo &&
                    saldoConferencia > saldoConta + 0.01) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Conferência (pedidos): ${moeda.format(saldoConferencia)} — o saque PIX usa só o saldo já creditado na conta.',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.55),
                      fontSize: 9,
                      height: 1.35,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _bolha(double size, double opacity) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: opacity),
        ),
      );

  // ── Ações rápidas ─────────────────────────────────────────────────────────
  Widget _acoesRapidas(
    BuildContext context, {
    required String uid,
    required NumberFormat moeda,
    required double saldoDisponivelSaque,
    required Map<String, dynamic>? dadosUsuario,
  }) {
    return Row(
      children: [
        Expanded(
          child: _acaoBotao(
            icon: Icons.send_rounded,
            label: 'Transferir',
            cor: _verde,
            onTap: () => _abrirTransferencia(
              context,
              uid: uid,
              saldoDisponivel: saldoDisponivelSaque,
              moeda: moeda,
              dadosUsuario: dadosUsuario,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _acaoBotao(
            icon: Icons.pix,
            label: 'PIX',
            cor: _roxo,
            onTap: () => _abrirModalChavesPix(context, uid: uid),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _acaoBotao(
            icon: Icons.receipt_long_outlined,
            label: 'Extrato',
            cor: _laranja,
            onTap: () =>
                setState(() => _filtroExtrato = 'todos'),
          ),
        ),
      ],
    );
  }

  Widget _acaoBotao({
    required IconData icon,
    required String label,
    required Color cor,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: cor.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: cor, size: 20),
              ),
              const SizedBox(height: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Colors.grey.shade700,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── KPIs ─────────────────────────────────────────────────────────────────
  Widget _kpiGrid({
    required NumberFormat moeda,
    required double somaPendente,
    required int qPendente,
    required double somaPago,
    required double totalCreditado,
    required int qEntregues,
  }) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _kpiCard(
                icon: Icons.hourglass_top_rounded,
                label: 'Em análise',
                valor: moeda.format(somaPendente),
                sub: '$qPendente pendente(s)',
                cor: _laranja,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _kpiCard(
                icon: Icons.check_circle_outline_rounded,
                label: 'Transferido',
                valor: moeda.format(somaPago),
                sub: 'PIX realizados',
                cor: _verde,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _kpiCard(
                icon: Icons.local_shipping_outlined,
                label: 'Pedidos entregues',
                valor: qEntregues.toString(),
                sub: 'Geraram crédito',
                cor: _roxo,
                valorGrande: true,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _kpiCard(
                icon: Icons.trending_up_rounded,
                label: 'Total creditado',
                valor: moeda.format(totalCreditado),
                sub: 'Acumulado histórico',
                cor: const Color(0xFF7C3AED),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _kpiCard({
    required IconData icon,
    required String label,
    required String valor,
    required String sub,
    required Color cor,
    bool valorGrande = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: cor, size: 15),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 10.5,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            valor,
            style: GoogleFonts.plusJakartaSans(
              fontSize: valorGrande ? 22 : 15,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF1E1B4B),
              height: 1.1,
            ),
          ),
          Text(
            sub,
            style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }

  // ── Como funciona ─────────────────────────────────────────────────────────
  Widget _painelComoFunciona() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline_rounded, color: _roxo, size: 16),
              const SizedBox(width: 6),
              Text(
                'Como funciona',
                style: GoogleFonts.plusJakartaSans(
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                  color: _roxo,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _bullet(
            'O crédito entra na carteira quando o pedido for marcado como entregue.',
          ),
          _bullet(
            'Ao solicitar transferência, o valor é reservado e o PIX é processado em até 24 h úteis.',
          ),
          _bullet(
            'Acompanhe cada movimentação no extrato ao lado.',
          ),
        ],
      ),
    );
  }

  Widget _bullet(String texto) => Padding(
        padding: const EdgeInsets.only(bottom: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '•  ',
              style: TextStyle(color: Colors.grey.shade500, height: 1.4),
            ),
            Expanded(
              child: Text(
                texto,
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.4,
                  color: Colors.grey.shade700,
                ),
              ),
            ),
          ],
        ),
      );

  // ── Painel extrato (wide) ─────────────────────────────────────────────────
  Widget _painelExtrato(
    BuildContext context,
    List<CarteiraLancamento> filtrados,
    NumberFormat moeda,
  ) {
    return Container(
      margin: const EdgeInsets.fromLTRB(0, 16, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: _extratoHeader(filtrados, moeda),
          ),
          Divider(height: 1, thickness: 1, color: Colors.grey.shade100),
          Expanded(
            child: filtrados.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.receipt_long_outlined,
                          size: 52,
                          color: Colors.grey.shade300,
                        ),
                        const SizedBox(height: 14),
                        Text(
                          'Nenhum lançamento',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Colors.grey.shade500,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Seus créditos e saídas aparecem aqui.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade400,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 6, 12, 80),
                    itemCount: filtrados.length,
                    itemBuilder: (context, i) {
                      final l = filtrados[i];
                      final showHeader = i == 0 ||
                          !_mesmoMes(filtrados[i - 1].data, l.data);
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (showHeader) _mesHeader(l.data),
                          _itemLancamento(context, l, moeda),
                        ],
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  // ── Extrato header ────────────────────────────────────────────────────────
  Widget _extratoHeader(List<CarteiraLancamento> filtrados, NumberFormat moeda) {
    double somaEntradas = 0;
    double somaSaidas = 0;
    for (final l in filtrados) {
      if (l.entrada) {
        somaEntradas += l.valor;
      } else {
        somaSaidas += l.valor;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Text(
              'Extrato',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF1E1B4B),
              ),
            ),
            const Spacer(),
            _segmentoExtrato(),
          ],
        ),
        if (filtrados.isNotEmpty) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              _miniStat(
                '+ ${moeda.format(somaEntradas)}',
                'Entradas',
                _verde,
              ),
              const SizedBox(width: 16),
              _miniStat(
                '- ${moeda.format(somaSaidas)}',
                'Saídas',
                _laranja,
              ),
              const SizedBox(width: 16),
              _miniStat(
                '${filtrados.length}',
                'Lançamentos',
                _roxo,
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _miniStat(String valor, String label, Color cor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          valor,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: cor,
          ),
        ),
        Text(
          label,
          style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
        ),
      ],
    );
  }

  Widget _segmentoExtrato() {
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: SegmentedButton<String>(
        segments: const [
          ButtonSegment(value: 'todos', label: Text('Todos')),
          ButtonSegment(value: 'entradas', label: Text('Entradas')),
          ButtonSegment(value: 'saidas', label: Text('Saídas')),
        ],
        selected: {_filtroExtrato},
        showSelectedIcon: false,
        emptySelectionAllowed: false,
        onSelectionChanged: (s) {
          if (s.isEmpty) return;
          setState(() => _filtroExtrato = s.first);
        },
        style: SegmentedButton.styleFrom(
          backgroundColor: Colors.grey.shade100,
          foregroundColor: Colors.grey.shade700,
          selectedForegroundColor: _roxo,
          selectedBackgroundColor: _laranja.withValues(alpha: 0.2),
          side: BorderSide(color: Colors.grey.shade300),
          visualDensity: VisualDensity.compact,
          textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  // ── Mês separador ─────────────────────────────────────────────────────────
  Widget _mesHeader(DateTime dt) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 14, 0, 6),
      child: Row(
        children: [
          Text(
            '${_nomeMes(dt.month)} ${dt.year}',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Colors.grey.shade400,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Divider(thickness: 1, color: Colors.grey.shade200),
          ),
        ],
      ),
    );
  }

  static String _rotuloMotivoRecusaCodigo(String? codigo) {
    switch (codigo) {
      case 'titular_incompativel':
        return 'O titular da conta informada não é o mesmo responsável pela loja.';
      case 'saque_indisponivel_momento':
        return 'Solicitação de saque indisponível no momento';
      case 'banco_recusou':
        return 'O seu banco recusou o recebimento do saque.';
      case 'outros':
        return 'Outros';
      default:
        if (codigo == null || codigo.trim().isEmpty) return '—';
        return codigo;
    }
  }

  Widget _linhaDetExtrato(String rotulo, String valor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(
              rotulo,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade700,
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(valor, style: const TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }

  Future<void> _mostrarDetalheLancamento(
    BuildContext context,
    CarteiraLancamento l,
  ) async {
    final moeda = NumberFormat.currency(locale: 'pt_BR', symbol: r'R$');
    final db = FirebaseFirestore.instance;
    try {
      if (l.refPedidoId != null) {
        final doc = await db.collection('pedidos').doc(l.refPedidoId).get();
        if (!context.mounted) return;
        if (!doc.exists) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Pedido não encontrado.')),
          );
          return;
        }
        final p = doc.data()!;
        // Fase 3G.3 — `cliente_nome` e `entregador_nome`/`entregador_telefone`
        // são denormalizados no pedido. A rule de `users` agora bloqueia o
        // lojista de ler `users/{cliente_id}` ou `users/{entregador_id}`, então
        // confiamos nos campos do próprio pedido (backfill + triggers mantêm
        // atualizados). Para pedidos legados sem denormalização, mostramos
        // placeholder em vez de falhar.
        var nomeCliente = p['cliente_nome']?.toString().trim() ?? '';
        if (nomeCliente.isEmpty) {
          nomeCliente = '—';
        }
        final fp = p['forma_pagamento']?.toString() ?? '—';
        var entNome = p['entregador_nome']?.toString().trim() ?? '';
        final entId = p['entregador_id']?.toString().trim() ?? '';
        var entTel = p['entregador_telefone']?.toString().trim() ?? '';
        final dp = p['data_pedido'];
        var dPed = l.data;
        if (dp is Timestamp) dPed = dp.toDate();
        final isRetirada = p['tipo_entrega']?.toString() == 'retirada';
        String entreguePor;
        if (isRetirada) {
          entreguePor = 'Retirada na loja';
        } else if (entNome.isNotEmpty && entTel.isNotEmpty) {
          entreguePor = '$entNome, $entTel';
        } else if (entNome.isNotEmpty) {
          entreguePor = '$entNome (telefone não informado)';
        } else if (entTel.isNotEmpty) {
          entreguePor = entTel;
        } else if (entId.isNotEmpty) {
          entreguePor = 'A definir';
        } else {
          entreguePor = '—';
        }
        final vProd = CarteiraLojistaExtrato.valorProdutosPedido(p);
        final vFrete = _num(p['taxa_entrega']);
        final totalPago = _num(p['total']);
        final totalCarteira = CarteiraLojistaExtrato.creditoLoja(p);
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Detalhes da venda'),
            content: SingleChildScrollView(
              child: SizedBox(
                width: 420,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _linhaDetExtrato(
                      'Nome do produto',
                      CarteiraLojistaExtrato.nomesProdutoDetalheLinha(p),
                    ),
                    _linhaDetExtrato('Nome do cliente', nomeCliente),
                    _linhaDetExtrato('Forma de pagamento', fp),
                    _linhaDetExtrato(
                      'Data e hora',
                      DateFormat('dd/MM/yyyy HH:mm').format(dPed),
                    ),
                    _linhaDetExtrato('Entregue por', entreguePor),
                    const Divider(height: 20),
                    _linhaDetExtrato(
                      'Valor do produto',
                      moeda.format(vProd),
                    ),
                    _linhaDetExtrato(
                      'Valor do frete',
                      moeda.format(vFrete),
                    ),
                    _linhaDetExtrato(
                      'Total pago',
                      moeda.format(totalPago),
                    ),
                    _linhaDetExtrato(
                      'Total carteira',
                      moeda.format(totalCarteira),
                    ),
                    const SizedBox(height: 8),
                    SelectableText(
                      'Pedido: ${doc.id}',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade500,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Fechar'),
              ),
            ],
          ),
        );
        return;
      }

      if (l.refSaqueId != null) {
        final doc =
            await db.collection('saques_solicitacoes').doc(l.refSaqueId).get();
        if (!context.mounted) return;
        if (!doc.exists) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Solicitação não encontrada.')),
          );
          return;
        }
        final d = doc.data()!;
        final ts = d['data_solicitacao'];
        final ds = ts is Timestamp
            ? DateFormat('dd/MM/yyyy HH:mm').format(ts.toDate())
            : '—';
        final status = d['status']?.toString() ?? '—';
        final chave = d['chave_pix']?.toString() ?? '—';
        final titular = d['titular_conta']?.toString() ?? '—';
        final banco = d['banco']?.toString().trim();
        final v = _num(d['valor']);
        final motivoR = d['motivo_recusa_texto']?.toString();
        final codR = d['motivo_recusa_codigo']?.toString();
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Solicitação de saque PIX'),
            content: SingleChildScrollView(
              child: SizedBox(
                width: 400,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _linhaDetExtrato('Valor solicitado', moeda.format(v)),
                    _linhaDetExtrato('Status', status),
                    _linhaDetExtrato('Data da solicitação', ds),
                    _linhaDetExtrato('Chave PIX', chave),
                    _linhaDetExtrato('Titular', titular),
                    if (banco != null && banco.isNotEmpty)
                      _linhaDetExtrato('Banco', banco),
                    if (status == 'recusado' &&
                        ((motivoR != null && motivoR.isNotEmpty) ||
                            (codR != null && codR.isNotEmpty))) ...[
                      const Divider(height: 20),
                      if (codR != null && codR.isNotEmpty)
                        _linhaDetExtrato(
                          'Motivo da recusa (categoria)',
                          _rotuloMotivoRecusaCodigo(codR),
                        ),
                      if (motivoR != null && motivoR.isNotEmpty)
                        _linhaDetExtrato('Motivo informado', motivoR),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Fechar'),
              ),
            ],
          ),
        );
        return;
      }

      if (l.refEstornoId != null) {
        final doc = await db.collection('estornos').doc(l.refEstornoId).get();
        if (!context.mounted) return;
        if (!doc.exists) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Registo não encontrado.')),
          );
          return;
        }
        final e = doc.data()!;
        final tipoOp = e['tipo_operacao']?.toString() ?? '';
        final ts = e['data_estorno'];
        final dStr = ts is Timestamp
            ? DateFormat('dd/MM/yyyy HH:mm').format(ts.toDate())
            : '—';

        if (tipoOp == 'credito_saque_recusado') {
          final saqueId = e['saque_solicitacao_id']?.toString() ?? '';
          final motivo = e['motivo']?.toString() ?? '—';
          final cod = e['motivo_codigo']?.toString();
          DocumentSnapshot<Map<String, dynamic>>? saqueSnap;
          if (saqueId.isNotEmpty) {
            saqueSnap = await db
                .collection('saques_solicitacoes')
                .doc(saqueId)
                .get();
          }
          if (!context.mounted) return;

          final children = <Widget>[
            _linhaDetExtrato(
              'Valor creditado',
              moeda.format(_num(e['valor'])),
            ),
            _linhaDetExtrato('Data do estorno', dStr),
            if (cod != null && cod.isNotEmpty)
              _linhaDetExtrato(
                'Motivo (categoria)',
                _rotuloMotivoRecusaCodigo(cod),
              ),
            _linhaDetExtrato('Motivo', motivo),
            const Divider(height: 20),
            const Text(
              'Solicitação de saque original',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
          ];

          if (saqueSnap != null && saqueSnap.exists) {
            final sd = saqueSnap.data()!;
            final sTs = sd['data_solicitacao'];
            final sdStr = sTs is Timestamp
                ? DateFormat('dd/MM/yyyy HH:mm').format(sTs.toDate())
                : '—';
            children.addAll([
              _linhaDetExtrato('Valor', moeda.format(_num(sd['valor']))),
              _linhaDetExtrato('Data', sdStr),
              _linhaDetExtrato('Chave PIX', sd['chave_pix']?.toString() ?? '—'),
              _linhaDetExtrato(
                'Titular',
                sd['titular_conta']?.toString() ?? '—',
              ),
              if ((sd['banco']?.toString().trim() ?? '').isNotEmpty)
                _linhaDetExtrato('Banco', sd['banco']!.toString().trim()),
            ]);
          } else {
            children.add(
              Text(
                saqueId.isEmpty
                    ? 'Sem referência ao pedido de saque.'
                    : 'Não foi possível carregar o pedido de saque ($saqueId).',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
              ),
            );
          }

          await showDialog<void>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Estorno de saque PIX'),
              content: SingleChildScrollView(
                child: SizedBox(
                  width: 420,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: children,
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Fechar'),
                ),
              ],
            ),
          );
          return;
        }

        final pedidoId = e['pedido_id']?.toString() ?? '';
        final motivo = e['motivo']?.toString() ?? '—';
        final valor = _num(e['valor']);
        final children = <Widget>[
          _linhaDetExtrato('Valor descontado', moeda.format(valor)),
          _linhaDetExtrato('Data', dStr),
          _linhaDetExtrato('Motivo', motivo),
        ];
        if (pedidoId.isNotEmpty) {
          children.add(_linhaDetExtrato('Pedido (referência)', pedidoId));
          final pSnap = await db.collection('pedidos').doc(pedidoId).get();
          if (!context.mounted) return;
          if (pSnap.exists) {
            final p = pSnap.data()!;
            // Fase 3G.3 — lê do próprio pedido (denormalizado); a rule
            // bloqueia leitura cruzada em `users`.
            var nomeCliente = p['cliente_nome']?.toString().trim() ?? '';
            if (nomeCliente.isEmpty) nomeCliente = '—';
            children.add(const Divider(height: 20));
            children.add(
              const Text(
                'Resumo do pedido',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            );
            children.add(const SizedBox(height: 8));
            children.add(
              _linhaDetExtrato(
                'Cliente',
                nomeCliente.isEmpty ? '—' : nomeCliente,
              ),
            );
            children.add(
              _linhaDetExtrato(
                'Forma de pagamento',
                p['forma_pagamento']?.toString() ?? '—',
              ),
            );
            children.add(
              _linhaDetExtrato(
                'Total do pedido',
                moeda.format(_num(p['total'])),
              ),
            );
          }
        }
        if (!context.mounted) return;
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Estorno ao cliente'),
            content: SingleChildScrollView(
              child: SizedBox(
                width: 400,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: children,
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Fechar'),
              ),
            ],
          ),
        );
      }
    } catch (e, st) {
      debugPrint('_mostrarDetalheLancamento: $e\n$st');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao abrir detalhes: $e')),
        );
      }
    }
  }

  // ── Item lançamento ───────────────────────────────────────────────────────
  Widget _itemLancamento(
    BuildContext context,
    CarteiraLancamento l,
    NumberFormat moeda,
  ) {
    final bool recusado = l.status == 'recusado';
    final bool estornado = l.status == 'estornado';
    final bool pendente = l.status == 'pendente';
    final Color corBase = l.entrada ? _verde : (estornado ? const Color(0xFFDC2626) : _laranja);
    final Color corIcone = recusado ? Colors.grey.shade400 : corBase;
    final Color corValor = recusado
        ? Colors.grey.shade400
        : (l.entrada ? _verde : (estornado ? const Color(0xFFDC2626) : const Color(0xFF1E1B4B)));

    String labelStatus;
    Color corStatus;
    switch (l.status) {
      case 'pago':
        labelStatus = 'Pago';
        corStatus = _verde;
        break;
      case 'recusado':
        labelStatus = 'Recusado';
        corStatus = const Color(0xFFB91C1C);
        break;
      case 'concluido':
        labelStatus = 'Creditado';
        corStatus = _verde;
        break;
      case 'estornado':
        labelStatus = 'Estornado';
        corStatus = const Color(0xFFDC2626);
        break;
      case 'estorno_pix_credito':
        labelStatus = 'Crédito';
        corStatus = _verde;
        break;
      default:
        labelStatus = 'Em análise';
        corStatus = _laranja;
    }

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: l.temDetalhe
            ? () async {
                await _mostrarDetalheLancamento(context, l);
              }
            : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: corIcone.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  estornado
                      ? Icons.replay_rounded
                      : (l.entrada
                          ? Icons.arrow_downward_rounded
                          : Icons.arrow_upward_rounded),
                  color: corIcone,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l.titulo,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1E1B4B),
                      ),
                    ),
                    if (l.banco != null && l.banco!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Banco: ${l.banco}',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade700,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    Text(
                      l.subtitulo,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade500,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${l.entrada ? '+' : '-'} ${moeda.format(l.valor)}',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: corValor,
                      decoration: recusado ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: corStatus.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            if (pendente)
                              Padding(
                                padding: const EdgeInsets.only(right: 3),
                                child: Container(
                                  width: 5,
                                  height: 5,
                                  decoration: BoxDecoration(
                                    color: corStatus,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                            Text(
                              labelStatus,
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                color: corStatus,
                                letterSpacing: 0.2,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        DateFormat('dd/MM').format(l.data),
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.grey.shade400,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Itens planos para narrow ──────────────────────────────────────────────
  List<Widget> _extratoItensFlat(
    BuildContext context,
    List<CarteiraLancamento> filtrados,
    NumberFormat moeda,
  ) {
    final widgets = <Widget>[];
    for (int i = 0; i < filtrados.length; i++) {
      final l = filtrados[i];
      if (i == 0 || !_mesmoMes(filtrados[i - 1].data, l.data)) {
        widgets.add(_mesHeader(l.data));
      }
      widgets.add(
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.grey.shade100),
          ),
          margin: const EdgeInsets.only(bottom: 4),
          child: _itemLancamento(context, l, moeda),
        ),
      );
    }
    return widgets;
  }
}
