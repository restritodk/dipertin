// ignore_for_file: use_build_context_synchronously

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../services/firebase_functions_config.dart';
import '../utils/admin_perfil.dart';
import '../utils/firestore_web_safe.dart';

/// Central de Clientes — design exclusivo, fora do tema padrão laranja do painel.
///
/// Acesso restrito a `role == 'master'`. Permite:
///   - Listar todos os clientes cadastrados;
///   - Buscar por nome, CPF ou e-mail;
///   - Abrir um painel completo (financeiro, pedidos, dados);
///   - Editar dados básicos do cliente;
///   - Excluir conta (hard delete via Cloud Function).
class CentralClientesScreen extends StatefulWidget {
  const CentralClientesScreen({super.key});

  @override
  State<CentralClientesScreen> createState() => _CentralClientesScreenState();
}

class _CentralClientesScreenState extends State<CentralClientesScreen> {
  final TextEditingController _busca = TextEditingController();
  String _termo = '';
  Timer? _debounce;

  @override
  void dispose() {
    _busca.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onChangeBusca(String s) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 220), () {
      if (!mounted) return;
      setState(() => _termo = s.trim());
    });
  }

  String _normalizar(String s) {
    final lower = s.toLowerCase();
    const acentos = 'áàâãäéèêëíìîïóòôõöúùûüçñ';
    const limpos = 'aaaaaeeeeiiiiooooouuuucn';
    var out = lower;
    for (var i = 0; i < acentos.length; i++) {
      out = out.replaceAll(acentos[i], limpos[i]);
    }
    return out;
  }

  String _soDigitos(String s) => s.replaceAll(RegExp(r'\D'), '');

  /// Lê todos os pedidos e devolve, por cliente_id, a contagem total e o
  /// total gasto considerando apenas pedidos efetivamente concluídos.
  Map<String, _AgregadoPedidos> _calcularAgregadoPorCliente(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final out = <String, _AgregadoPedidos>{};
    for (final d in docs) {
      final m = safeWebDocData(d);
      if (m.isEmpty) continue;
      final cid = (m['cliente_id'] ?? '').toString();
      if (cid.isEmpty) continue;
      final status = (m['status'] ?? '').toString().toLowerCase();
      final total = _toNum(m['valor_total_pago_cliente']) ??
          _toNum(m['total']) ??
          _toNum(m['valor_total']) ??
          0;
      final atual = out[cid] ?? _AgregadoPedidos();
      atual.contagem += 1;
      if (status == 'entregue' ||
          status == 'concluido' ||
          status == 'concluído') {
        atual.totalGasto += total;
      }
      out[cid] = atual;
    }
    return out;
  }

  /// Soma o saldo de carteira de todos os lojistas cadastrados.
  double _somarSaldoLojistas(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    var total = 0.0;
    for (final d in docs) {
      final m = safeWebDocData(d);
      if (m.isEmpty) continue;
      final v = m['saldo'];
      if (v is num) total += v.toDouble();
    }
    return total;
  }

  bool _matchCliente(_ClienteResumo c, String termo) {
    if (termo.isEmpty) return true;
    final t = _normalizar(termo);
    final tDig = _soDigitos(termo);

    if (_normalizar(c.nome).contains(t)) return true;
    if (_normalizar(c.email).contains(t)) return true;
    if (tDig.isNotEmpty && _soDigitos(c.cpf).contains(tDig)) return true;
    if (tDig.isNotEmpty && _soDigitos(c.telefone).contains(tDig)) return true;
    return false;
  }

  Future<bool> _verificarPermissaoMaster() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return false;
    final snap = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .get();
    if (!snap.exists) return false;
    final dados = safeWebDocData(snap);
    final perfil = perfilAdministrativoPainel(dados);
    return perfilPodeCentralClientes(perfil);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _verificarPermissaoMaster(),
      builder: (context, permSnap) {
        if (permSnap.connectionState != ConnectionState.done) {
          return const _ColoredScaffold(
            child: Center(
              child: CircularProgressIndicator(color: _CCTheme.primary),
            ),
          );
        }
        if (permSnap.data != true) {
          return const _ColoredScaffold(child: _AcessoNegado());
        }
        return _ColoredScaffold(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            // Stream 1 — Clientes
            stream: FirebaseFirestore.instance
                .collection('users')
                .where('role', isEqualTo: 'cliente')
                .snapshots(),
            builder: (context, clientesSnap) {
              if (clientesSnap.hasError) {
                return _ErroCarga(mensagem: clientesSnap.error.toString());
              }
              return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                // Stream 2 — Pedidos (para contagem/total em tempo real por cliente)
                stream: FirebaseFirestore.instance
                    .collection('pedidos')
                    .snapshots(),
                builder: (context, pedidosSnap) {
                  return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    // Stream 3 — Lojistas (para KPI Saldo em carteira)
                    stream: FirebaseFirestore.instance
                        .collection('users')
                        .where('role', isEqualTo: 'lojista')
                        .snapshots(),
                    builder: (context, lojistasSnap) {
                      // Agregação dos pedidos por cliente_id (em tempo real).
                      final agregado = _calcularAgregadoPorCliente(
                        pedidosSnap.data?.docs ?? const [],
                      );

                      // Soma dos saldos de TODOS os lojistas.
                      final saldoTotalLojistas = _somarSaldoLojistas(
                        lojistasSnap.data?.docs ?? const [],
                      );

                      // Monta lista de clientes enriquecida com dados em tempo real.
                      final clientes = <_ClienteResumo>[];
                      for (final d in clientesSnap.data?.docs ?? const []) {
                        final raw = safeWebDocData(d);
                        if (raw.isEmpty) continue;
                        final base = _ClienteResumo.fromMap(d.id, raw);
                        final ag = agregado[d.id];
                        clientes.add(
                          base.comAgregado(
                            totalPedidos: ag?.contagem ?? 0,
                            totalGasto: ag?.totalGasto ?? 0,
                          ),
                        );
                      }
                      clientes.sort((a, b) {
                        final ta =
                            a.criadoEm?.millisecondsSinceEpoch ?? 0;
                        final tb =
                            b.criadoEm?.millisecondsSinceEpoch ?? 0;
                        return tb.compareTo(ta);
                      });
                      final filtrados = clientes
                          .where((c) => _matchCliente(c, _termo))
                          .toList();

                      final carregando =
                          clientesSnap.connectionState ==
                              ConnectionState.waiting;

                      return SingleChildScrollView(
                        padding:
                            const EdgeInsets.fromLTRB(28, 24, 28, 36),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _Header(total: clientes.length),
                            const SizedBox(height: 22),
                            _LinhaKpis(
                              clientes: clientes,
                              saldoTotalLojistas: saldoTotalLojistas,
                            ),
                            const SizedBox(height: 22),
                            _BarraBusca(
                              controller: _busca,
                              onChange: _onChangeBusca,
                              totalFiltrados: filtrados.length,
                              total: clientes.length,
                            ),
                            const SizedBox(height: 16),
                            _CardTabela(
                              clientes: filtrados,
                              carregando: carregando,
                              onAbrir: _abrirDetalhe,
                              onEditar: _abrirEdicao,
                              onExcluir: _confirmarExclusao,
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              );
            },
          ),
        );
      },
    );
  }

  void _abrirDetalhe(_ClienteResumo c) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black54,
      builder: (ctx) => _DialogDetalheCliente(
        cliente: c,
        onEditar: () {
          Navigator.of(ctx).pop();
          _abrirEdicao(c);
        },
        onExcluir: () {
          Navigator.of(ctx).pop();
          _confirmarExclusao(c);
        },
      ),
    );
  }

  void _abrirEdicao(_ClienteResumo c) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _DialogEditarCliente(cliente: c),
    );
  }

  Future<void> _confirmarExclusao(_ClienteResumo c) async {
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _DialogConfirmExclusao(cliente: c),
    );
    if (ok != true) return;

    final messenger = ScaffoldMessenger.maybeOf(context);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: SizedBox(
          width: 56,
          height: 56,
          child: CircularProgressIndicator(color: _CCTheme.danger),
        ),
      ),
    );
    try {
      final res = await callFirebaseFunctionSafe(
        'excluirClienteAdminMaster',
        parameters: {'uid': c.uid},
        timeout: const Duration(seconds: 90),
      );
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
      messenger?.showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF1A8754),
          content: Text(
            res['alreadyDeleted'] == true
                ? 'Cliente já estava removido. Limpeza concluída.'
                : 'Cliente excluído com sucesso.',
          ),
        ),
      );
    } on CallableHttpException catch (e) {
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
      messenger?.showSnackBar(
        SnackBar(
          backgroundColor: _CCTheme.danger,
          content: Text('Erro: ${e.message}'),
        ),
      );
    } catch (e) {
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
      messenger?.showSnackBar(
        SnackBar(
          backgroundColor: _CCTheme.danger,
          content: Text('Falha ao excluir: $e'),
        ),
      );
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// THEME EXCLUSIVO DA CENTRAL
// ─────────────────────────────────────────────────────────────────────────────

class _CCTheme {
  static const Color canvas = Color(0xFFF5F4F9);
  static const Color surface = Colors.white;
  static const Color surfaceElev = Color(0xFFFAF9FD);
  static const Color borderSoft = Color(0xFFE7E5EE);
  static const Color textPrimary = Color(0xFF1B1733);
  static const Color textSecondary = Color(0xFF615E78);
  static const Color textMuted = Color(0xFF93909F);

  static const Color primary = Color(0xFF6A1B9A); // roxo DiPertin
  static const Color primaryDeep = Color(0xFF42127A);
  static const Color emerald = Color(0xFF1A8754);
  static const Color emeraldSoft = Color(0xFFE2F4EA);
  static const Color sky = Color(0xFF1F6FEB);
  static const Color skySoft = Color(0xFFE3EEFF);
  static const Color amber = Color(0xFFD97706);
  static const Color amberSoft = Color(0xFFFFF1DC);
  static const Color danger = Color(0xFFD9342B);
  static const Color dangerSoft = Color(0xFFFCE4E2);

  static List<BoxShadow> sombraCard = const [
    BoxShadow(
      color: Color(0x1416114A),
      blurRadius: 18,
      offset: Offset(0, 6),
    ),
  ];
}

class _ColoredScaffold extends StatelessWidget {
  const _ColoredScaffold({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    // Material + DefaultTextStyle.merge garantem que nenhum Text herde o
    // sublinhado amarelo do tema raiz do Flutter Web (link/scaffold padrão).
    return Material(
      color: _CCTheme.canvas,
      child: DefaultTextStyle.merge(
        style: const TextStyle(
          decoration: TextDecoration.none,
          decorationThickness: 0,
          color: _CCTheme.textPrimary,
        ),
        child: child,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// HEADER + KPIs + BUSCA
// ─────────────────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header({required this.total});
  final int total;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 26),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [_CCTheme.primaryDeep, _CCTheme.primary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Color(0x336A1B9A),
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withValues(alpha: 0.32)),
            ),
            child: const Icon(
              Icons.people_alt_rounded,
              color: Colors.white,
              size: 30,
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text(
                  'Central de Clientes',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Gestão completa dos consumidores cadastrados na plataforma',
                  style: TextStyle(
                    color: Color(0xFFE7DCF4),
                    fontSize: 13.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.32)),
            ),
            child: Row(
              children: [
                const Icon(Icons.shield_moon_rounded,
                    color: Colors.white, size: 16),
                const SizedBox(width: 8),
                Text(
                  'Acesso MASTER',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.95),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LinhaKpis extends StatelessWidget {
  const _LinhaKpis({
    required this.clientes,
    required this.saldoTotalLojistas,
  });
  final List<_ClienteResumo> clientes;
  final double saldoTotalLojistas;

  @override
  Widget build(BuildContext context) {
    final total = clientes.length;
    // "Compradores ativos" = clientes que já realizaram ao menos 1 pedido
    // (qualquer status), em tempo real.
    final comPedidos =
        clientes.where((c) => (c.totalPedidos ?? 0) > 0).length;
    final novos30d = _novosUltimosDias(clientes, 30);

    return LayoutBuilder(
      builder: (context, c) {
        final wide = c.maxWidth >= 1100;
        final children = [
          _KpiCard(
            icone: Icons.groups_2_rounded,
            cor: _CCTheme.primary,
            corSoft: const Color(0xFFEFE5F8),
            titulo: 'Clientes cadastrados',
            valor: total.toString(),
            sub: 'Total acumulado',
          ),
          _KpiCard(
            icone: Icons.shopping_bag_rounded,
            cor: _CCTheme.emerald,
            corSoft: _CCTheme.emeraldSoft,
            titulo: 'Compradores ativos',
            valor: comPedidos.toString(),
            sub: 'Já realizaram ao menos 1 pedido',
          ),
          _KpiCard(
            icone: Icons.fiber_new_rounded,
            cor: _CCTheme.sky,
            corSoft: _CCTheme.skySoft,
            titulo: 'Novos (30 dias)',
            valor: novos30d.toString(),
            sub: 'Cadastros recentes',
          ),
          _KpiCard(
            icone: Icons.account_balance_wallet_rounded,
            cor: _CCTheme.amber,
            corSoft: _CCTheme.amberSoft,
            titulo: 'Saldo em carteira',
            valor: _formatadorReal.format(saldoTotalLojistas),
            sub: 'Soma das carteiras dos lojistas',
          ),
        ];

        if (wide) {
          return Row(
            children: [
              for (var i = 0; i < children.length; i++) ...[
                Expanded(child: children[i]),
                if (i != children.length - 1) const SizedBox(width: 14),
              ],
            ],
          );
        }
        return Wrap(
          spacing: 14,
          runSpacing: 14,
          children: [
            for (final w in children)
              SizedBox(
                width: (c.maxWidth - 14) / 2,
                child: w,
              ),
          ],
        );
      },
    );
  }

  int _novosUltimosDias(List<_ClienteResumo> all, int dias) {
    final corte =
        DateTime.now().subtract(Duration(days: dias)).millisecondsSinceEpoch;
    return all
        .where((c) =>
            (c.criadoEm?.millisecondsSinceEpoch ?? 0) >= corte)
        .length;
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.icone,
    required this.cor,
    required this.corSoft,
    required this.titulo,
    required this.valor,
    required this.sub,
  });
  final IconData icone;
  final Color cor;
  final Color corSoft;
  final String titulo;
  final String valor;
  final String sub;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _CCTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _CCTheme.borderSoft),
        boxShadow: _CCTheme.sombraCard,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: corSoft,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icone, color: cor, size: 22),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: corSoft,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'KPI',
                  style: TextStyle(
                    color: cor,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.1,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            titulo,
            style: const TextStyle(
              color: _CCTheme.textSecondary,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            valor,
            style: const TextStyle(
              color: _CCTheme.textPrimary,
              fontSize: 24,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            sub,
            style: const TextStyle(
              color: _CCTheme.textMuted,
              fontSize: 11.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _BarraBusca extends StatelessWidget {
  const _BarraBusca({
    required this.controller,
    required this.onChange,
    required this.totalFiltrados,
    required this.total,
  });
  final TextEditingController controller;
  final void Function(String) onChange;
  final int totalFiltrados;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
      decoration: BoxDecoration(
        color: _CCTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _CCTheme.borderSoft),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: const Color(0xFFEFE5F8),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.search_rounded,
                color: _CCTheme.primary, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChange,
              style: const TextStyle(
                color: _CCTheme.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
              decoration: const InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 10),
                border: InputBorder.none,
                hintText: 'Buscar por nome, CPF ou e-mail...',
                hintStyle: TextStyle(
                  color: _CCTheme.textMuted,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
          if (controller.text.isNotEmpty)
            IconButton(
              tooltip: 'Limpar busca',
              onPressed: () {
                controller.clear();
                onChange('');
              },
              icon: const Icon(Icons.close_rounded,
                  color: _CCTheme.textMuted, size: 20),
            ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: _CCTheme.surfaceElev,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _CCTheme.borderSoft),
            ),
            child: Text(
              '$totalFiltrados de $total',
              style: const TextStyle(
                color: _CCTheme.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TABELA
// ─────────────────────────────────────────────────────────────────────────────

class _CardTabela extends StatefulWidget {
  const _CardTabela({
    required this.clientes,
    required this.carregando,
    required this.onAbrir,
    required this.onEditar,
    required this.onExcluir,
  });
  final List<_ClienteResumo> clientes;
  final bool carregando;
  final void Function(_ClienteResumo) onAbrir;
  final void Function(_ClienteResumo) onEditar;
  final void Function(_ClienteResumo) onExcluir;

  @override
  State<_CardTabela> createState() => _CardTabelaState();
}

class _CardTabelaState extends State<_CardTabela> {
  static const int _itensPorPagina = 10;
  int _paginaAtual = 0;

  @override
  void didUpdateWidget(covariant _CardTabela oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Se a lista filtrada mudou e a página atual ficou fora dos limites,
    // volta para a primeira página.
    final totalPaginas = _totalPaginas(widget.clientes.length);
    if (_paginaAtual >= totalPaginas) {
      _paginaAtual = totalPaginas == 0 ? 0 : totalPaginas - 1;
    }
  }

  int _totalPaginas(int total) {
    if (total == 0) return 0;
    return (total / _itensPorPagina).ceil();
  }

  List<_ClienteResumo> _pagina() {
    final inicio = _paginaAtual * _itensPorPagina;
    if (inicio >= widget.clientes.length) return const [];
    final fim = (inicio + _itensPorPagina).clamp(0, widget.clientes.length);
    return widget.clientes.sublist(inicio, fim);
  }

  @override
  Widget build(BuildContext context) {
    final clientesPagina = _pagina();
    final totalPaginas = _totalPaginas(widget.clientes.length);

    return Container(
      decoration: BoxDecoration(
        color: _CCTheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _CCTheme.borderSoft),
        boxShadow: _CCTheme.sombraCard,
      ),
      clipBehavior: Clip.hardEdge,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
            decoration: const BoxDecoration(
              color: _CCTheme.surfaceElev,
              border: Border(
                bottom: BorderSide(color: _CCTheme.borderSoft, width: 1),
              ),
            ),
            child: Row(
              children: const [
                _ColCabecalho(largura: 2.6, texto: 'CLIENTE'),
                _ColCabecalho(largura: 2.0, texto: 'CONTATO'),
                _ColCabecalho(largura: 1.4, texto: 'CIDADE / UF'),
                _ColCabecalho(
                  largura: 1.0,
                  texto: 'PEDIDOS',
                  alignmentEnd: true,
                ),
                _ColCabecalho(
                  largura: 1.4,
                  texto: 'TOTAL GASTO',
                  alignmentEnd: true,
                ),
                _ColCabecalho(largura: 1.2, texto: 'CADASTRADO'),
                SizedBox(width: 140),
              ],
            ),
          ),
          if (widget.carregando && widget.clientes.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 80),
              child: Center(
                child: CircularProgressIndicator(color: _CCTheme.primary),
              ),
            )
          else if (widget.clientes.isEmpty)
            const _EstadoVazio()
          else ...[
            ListView.separated(
              physics: const NeverScrollableScrollPhysics(),
              shrinkWrap: true,
              itemCount: clientesPagina.length,
              separatorBuilder: (_, __) => const Divider(
                height: 1,
                thickness: 1,
                color: _CCTheme.borderSoft,
              ),
              itemBuilder: (ctx, i) {
                final c = clientesPagina[i];
                return _LinhaCliente(
                  cliente: c,
                  onAbrir: () => widget.onAbrir(c),
                  onEditar: () => widget.onEditar(c),
                  onExcluir: () => widget.onExcluir(c),
                );
              },
            ),
            _RodapePaginacao(
              paginaAtual: _paginaAtual,
              totalPaginas: totalPaginas,
              totalItens: widget.clientes.length,
              itensPorPagina: _itensPorPagina,
              onAnterior: _paginaAtual > 0
                  ? () => setState(() => _paginaAtual -= 1)
                  : null,
              onProximo: _paginaAtual < totalPaginas - 1
                  ? () => setState(() => _paginaAtual += 1)
                  : null,
              onIrPara: (p) => setState(() => _paginaAtual = p),
            ),
          ],
        ],
      ),
    );
  }
}

class _RodapePaginacao extends StatelessWidget {
  const _RodapePaginacao({
    required this.paginaAtual,
    required this.totalPaginas,
    required this.totalItens,
    required this.itensPorPagina,
    required this.onAnterior,
    required this.onProximo,
    required this.onIrPara,
  });
  final int paginaAtual;
  final int totalPaginas;
  final int totalItens;
  final int itensPorPagina;
  final VoidCallback? onAnterior;
  final VoidCallback? onProximo;
  final void Function(int) onIrPara;

  @override
  Widget build(BuildContext context) {
    if (totalPaginas <= 1) {
      return Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
        decoration: const BoxDecoration(
          color: _CCTheme.surfaceElev,
          border: Border(
            top: BorderSide(color: _CCTheme.borderSoft, width: 1),
          ),
        ),
        child: Text(
          totalItens == 0
              ? 'Nenhum cliente para exibir'
              : 'Exibindo $totalItens de $totalItens',
          style: const TextStyle(
            color: _CCTheme.textMuted,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }
    final inicio = paginaAtual * itensPorPagina + 1;
    final fim =
        ((paginaAtual + 1) * itensPorPagina).clamp(0, totalItens);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: const BoxDecoration(
        color: _CCTheme.surfaceElev,
        border: Border(
          top: BorderSide(color: _CCTheme.borderSoft, width: 1),
        ),
      ),
      child: Row(
        children: [
          Text(
            'Exibindo $inicio–$fim de $totalItens',
            style: const TextStyle(
              color: _CCTheme.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const Spacer(),
          _BotaoNavPag(
            icone: Icons.chevron_left_rounded,
            tooltip: 'Página anterior',
            onTap: onAnterior,
          ),
          const SizedBox(width: 6),
          ..._numerosPaginas().map((p) {
            if (p == -1) {
              return const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  '…',
                  style: TextStyle(
                    color: _CCTheme.textMuted,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              );
            }
            final ativo = p == paginaAtual;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: ativo ? null : () => onIrPara(p),
                child: Container(
                  width: 32,
                  height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: ativo
                        ? _CCTheme.primary
                        : _CCTheme.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: ativo
                          ? _CCTheme.primary
                          : _CCTheme.borderSoft,
                    ),
                  ),
                  child: Text(
                    '${p + 1}',
                    style: TextStyle(
                      color:
                          ativo ? Colors.white : _CCTheme.textPrimary,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            );
          }),
          const SizedBox(width: 6),
          _BotaoNavPag(
            icone: Icons.chevron_right_rounded,
            tooltip: 'Próxima página',
            onTap: onProximo,
          ),
        ],
      ),
    );
  }

  /// Lista compacta de números de páginas a exibir, com -1 como
  /// separador "…". Mantém início, fim e janelinha em torno da atual.
  List<int> _numerosPaginas() {
    if (totalPaginas <= 7) {
      return [for (var i = 0; i < totalPaginas; i++) i];
    }
    final out = <int>[0];
    final inicioJanela = (paginaAtual - 1).clamp(1, totalPaginas - 2);
    final fimJanela = (paginaAtual + 1).clamp(1, totalPaginas - 2);
    if (inicioJanela > 1) out.add(-1);
    for (var i = inicioJanela; i <= fimJanela; i++) {
      out.add(i);
    }
    if (fimJanela < totalPaginas - 2) out.add(-1);
    out.add(totalPaginas - 1);
    return out;
  }
}

class _BotaoNavPag extends StatelessWidget {
  const _BotaoNavPag({
    required this.icone,
    required this.tooltip,
    required this.onTap,
  });
  final IconData icone;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final habilitado = onTap != null;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: habilitado
                ? _CCTheme.surface
                : _CCTheme.surfaceElev,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _CCTheme.borderSoft),
          ),
          child: Icon(
            icone,
            size: 18,
            color: habilitado
                ? _CCTheme.textPrimary
                : _CCTheme.textMuted,
          ),
        ),
      ),
    );
  }
}

class _ColCabecalho extends StatelessWidget {
  const _ColCabecalho({
    required this.largura,
    required this.texto,
    this.alignmentEnd = false,
  });
  final double largura;
  final String texto;
  final bool alignmentEnd;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: (largura * 10).round(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Align(
          alignment: alignmentEnd
              ? Alignment.centerRight
              : Alignment.centerLeft,
          child: Text(
            texto,
            style: const TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.1,
              color: _CCTheme.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}

class _LinhaCliente extends StatefulWidget {
  const _LinhaCliente({
    required this.cliente,
    required this.onAbrir,
    required this.onEditar,
    required this.onExcluir,
  });
  final _ClienteResumo cliente;
  final VoidCallback onAbrir;
  final VoidCallback onEditar;
  final VoidCallback onExcluir;

  @override
  State<_LinhaCliente> createState() => _LinhaClienteState();
}

class _LinhaClienteState extends State<_LinhaCliente> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.cliente;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onAbrir,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          color: _hover ? _CCTheme.surfaceElev : _CCTheme.surface,
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
          child: Row(
            children: [
              Expanded(
                flex: 26,
                child: Row(
                  children: [
                    _AvatarCliente(nome: c.nome, fotoUrl: c.fotoUrl),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            c.nomeOuFallback,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: _CCTheme.textPrimary,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (c.cpf.isNotEmpty)
                            Text(
                              'CPF: ${c.cpfFormatado}',
                              style: const TextStyle(
                                color: _CCTheme.textMuted,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                flex: 20,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        c.email.isEmpty ? '—' : c.email,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _CCTheme.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        c.telefone.isEmpty ? '—' : c.telefoneFormatado,
                        style: const TextStyle(
                          color: _CCTheme.textMuted,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                flex: 14,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    c.cidadeUf,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _CCTheme.textSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
              Expanded(
                flex: 10,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: _PedidosBadge(c: c),
                ),
              ),
              Expanded(
                flex: 14,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    _formatadorReal.format(c.totalGasto ?? 0),
                    style: const TextStyle(
                      color: _CCTheme.textPrimary,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              Expanded(
                flex: 12,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    c.criadoEmFormatado,
                    style: const TextStyle(
                      color: _CCTheme.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
              SizedBox(
                width: 140,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    _IconAcao(
                      icone: Icons.visibility_rounded,
                      tooltip: 'Ver detalhes',
                      cor: _CCTheme.sky,
                      corSoft: _CCTheme.skySoft,
                      onTap: widget.onAbrir,
                    ),
                    const SizedBox(width: 6),
                    _IconAcao(
                      icone: Icons.edit_rounded,
                      tooltip: 'Editar',
                      cor: _CCTheme.amber,
                      corSoft: _CCTheme.amberSoft,
                      onTap: widget.onEditar,
                    ),
                    const SizedBox(width: 6),
                    _IconAcao(
                      icone: Icons.delete_outline_rounded,
                      tooltip: 'Excluir do banco',
                      cor: _CCTheme.danger,
                      corSoft: _CCTheme.dangerSoft,
                      onTap: widget.onExcluir,
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
}

class _PedidosBadge extends StatelessWidget {
  const _PedidosBadge({required this.c});
  final _ClienteResumo c;
  @override
  Widget build(BuildContext context) {
    final n = c.totalPedidos ?? 0;
    final ativo = n > 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: ativo ? _CCTheme.emeraldSoft : const Color(0xFFEEEDF2),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        n.toString(),
        style: TextStyle(
          color: ativo ? _CCTheme.emerald : _CCTheme.textMuted,
          fontSize: 12.5,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _IconAcao extends StatefulWidget {
  const _IconAcao({
    required this.icone,
    required this.tooltip,
    required this.cor,
    required this.corSoft,
    required this.onTap,
  });
  final IconData icone;
  final String tooltip;
  final Color cor;
  final Color corSoft;
  final VoidCallback onTap;
  @override
  State<_IconAcao> createState() => _IconAcaoState();
}

class _IconAcaoState extends State<_IconAcao> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      preferBelow: false,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () {
            widget.onTap();
          },
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: _hover ? widget.cor : widget.corSoft,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(
              widget.icone,
              size: 16,
              color: _hover ? Colors.white : widget.cor,
            ),
          ),
        ),
      ),
    );
  }
}

class _AvatarCliente extends StatelessWidget {
  const _AvatarCliente({required this.nome, required this.fotoUrl});
  final String nome;
  final String? fotoUrl;
  @override
  Widget build(BuildContext context) {
    final iniciais = _gerarIniciais(nome);
    final url = fotoUrl ?? '';
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [_CCTheme.primary, _CCTheme.primaryDeep],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: ClipOval(
        child: url.isEmpty
            ? Center(
                child: Text(
                  iniciais,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
              )
            : Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Center(
                  child: Text(
                    iniciais,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
      ),
    );
  }

  String _gerarIniciais(String nome) {
    final parts = nome.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }
}

class _EstadoVazio extends StatelessWidget {
  const _EstadoVazio();
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 80, horizontal: 20),
      child: Column(
        children: [
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              color: _CCTheme.surfaceElev,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(
              Icons.search_off_rounded,
              color: _CCTheme.textMuted,
              size: 36,
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'Nenhum cliente encontrado',
            style: TextStyle(
              color: _CCTheme.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Ajuste os filtros ou aguarde novos cadastros para visualizá-los aqui.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _CCTheme.textMuted,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _AcessoNegado extends StatelessWidget {
  const _AcessoNegado();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 460),
        padding: const EdgeInsets.fromLTRB(28, 32, 28, 28),
        decoration: BoxDecoration(
          color: _CCTheme.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _CCTheme.borderSoft),
          boxShadow: _CCTheme.sombraCard,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 70,
              height: 70,
              decoration: BoxDecoration(
                color: _CCTheme.dangerSoft,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(
                Icons.shield_rounded,
                color: _CCTheme.danger,
                size: 36,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Acesso restrito',
              style: TextStyle(
                color: _CCTheme.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Esta área é exclusiva para administradores com perfil MASTER.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _CCTheme.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErroCarga extends StatelessWidget {
  const _ErroCarga({required this.mensagem});
  final String mensagem;
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: _CCTheme.dangerSoft,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _CCTheme.danger.withValues(alpha: 0.4)),
          ),
          child: Text(
            'Erro ao carregar clientes:\n$mensagem',
            style: const TextStyle(
              color: _CCTheme.danger,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// MODEL — RESUMO DE CLIENTE
// ─────────────────────────────────────────────────────────────────────────────

final NumberFormat _formatadorReal = NumberFormat.currency(
  locale: 'pt_BR',
  symbol: 'R\$',
);
final DateFormat _formatoData = DateFormat('dd/MM/yyyy', 'pt_BR');

class _ClienteResumo {
  _ClienteResumo({
    required this.uid,
    required this.nome,
    required this.email,
    required this.telefone,
    required this.cpf,
    required this.cidade,
    required this.uf,
    required this.fotoUrl,
    required this.criadoEm,
    required this.saldo,
    required this.totalPedidos,
    required this.totalGasto,
    required this.bloqueado,
    required this.dadosBrutos,
  });

  final String uid;
  final String nome;
  final String email;
  final String telefone;
  final String cpf;
  final String cidade;
  final String uf;
  final String? fotoUrl;
  final DateTime? criadoEm;
  final double? saldo;
  final int? totalPedidos;
  final double? totalGasto;
  final bool bloqueado;
  final Map<String, dynamic> dadosBrutos;

  String get nomeOuFallback => nome.isEmpty ? '(sem nome)' : nome;

  String get cidadeUf {
    if (cidade.isEmpty && uf.isEmpty) return '—';
    if (uf.isEmpty) return cidade;
    if (cidade.isEmpty) return uf;
    return '$cidade • $uf';
  }

  String get criadoEmFormatado =>
      criadoEm == null ? '—' : _formatoData.format(criadoEm!);

  String get cpfFormatado {
    final d = cpf.replaceAll(RegExp(r'\D'), '');
    if (d.length != 11) return cpf;
    return '${d.substring(0, 3)}.${d.substring(3, 6)}.${d.substring(6, 9)}-${d.substring(9)}';
  }

  String get telefoneFormatado {
    final d = telefone.replaceAll(RegExp(r'\D'), '');
    if (d.length == 11) {
      return '(${d.substring(0, 2)}) ${d.substring(2, 7)}-${d.substring(7)}';
    }
    if (d.length == 10) {
      return '(${d.substring(0, 2)}) ${d.substring(2, 6)}-${d.substring(6)}';
    }
    return telefone;
  }

  /// Cria uma cópia substituindo apenas a contagem de pedidos e o total gasto
  /// — usado para enriquecer o resumo com dados em tempo real vindos da
  /// coleção `pedidos`.
  _ClienteResumo comAgregado({
    required int totalPedidos,
    required double totalGasto,
  }) {
    return _ClienteResumo(
      uid: uid,
      nome: nome,
      email: email,
      telefone: telefone,
      cpf: cpf,
      cidade: cidade,
      uf: uf,
      fotoUrl: fotoUrl,
      criadoEm: criadoEm,
      saldo: saldo,
      totalPedidos: totalPedidos,
      totalGasto: totalGasto,
      bloqueado: bloqueado,
      dadosBrutos: dadosBrutos,
    );
  }

  factory _ClienteResumo.fromMap(String uid, Map<String, dynamic> m) {
    DateTime? criado;
    final raw = m['criado_em'] ?? m['createdAt'] ?? m['created_at'];
    if (raw is Timestamp) criado = raw.toDate();

    return _ClienteResumo(
      uid: uid,
      nome: (m['nome'] ?? m['nome_completo'] ?? m['displayName'] ?? '')
          .toString()
          .trim(),
      email: (m['email'] ?? '').toString().trim(),
      telefone: (m['telefone'] ?? m['phone'] ?? '').toString().trim(),
      cpf: (m['cpf'] ?? '').toString().trim(),
      cidade: (m['cidade'] ?? '').toString().trim(),
      uf: (m['uf'] ?? m['estado'] ?? '').toString().trim(),
      fotoUrl: (m['foto_url'] ?? m['photoUrl'] ?? '').toString().isNotEmpty
          ? (m['foto_url'] ?? m['photoUrl']).toString()
          : null,
      criadoEm: criado,
      saldo: (m['saldo'] is num) ? (m['saldo'] as num).toDouble() : null,
      totalPedidos: (m['total_pedidos'] is num)
          ? (m['total_pedidos'] as num).toInt()
          : null,
      totalGasto: (m['total_gasto'] is num)
          ? (m['total_gasto'] as num).toDouble()
          : null,
      bloqueado: (m['conta_bloqueada'] == true) ||
          (m['bloqueado'] == true) ||
          (m['ativo'] == false),
      dadosBrutos: m,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// DIALOG DETALHE — vista 360°: dados, financeiro, pedidos
// ─────────────────────────────────────────────────────────────────────────────

class _DialogDetalheCliente extends StatelessWidget {
  const _DialogDetalheCliente({
    required this.cliente,
    required this.onEditar,
    required this.onExcluir,
  });
  final _ClienteResumo cliente;
  final VoidCallback onEditar;
  final VoidCallback onExcluir;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 36, vertical: 36),
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1100, maxHeight: 800),
        child: Container(
          decoration: BoxDecoration(
            color: _CCTheme.canvas,
            borderRadius: BorderRadius.circular(22),
            boxShadow: const [
              BoxShadow(
                color: Color(0x4015103A),
                blurRadius: 36,
                offset: Offset(0, 16),
              ),
            ],
          ),
          clipBehavior: Clip.hardEdge,
          child: Column(
            children: [
              _CabecalhoDetalhe(
                cliente: cliente,
                onEditar: onEditar,
                onExcluir: onExcluir,
                onFechar: () => Navigator.of(context).pop(),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 22, 24, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _BlocoFinanceiroCliente(cliente: cliente),
                      const SizedBox(height: 18),
                      _BlocoLayoutDuplo(cliente: cliente),
                      const SizedBox(height: 18),
                      _BlocoPedidosCliente(cliente: cliente),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CabecalhoDetalhe extends StatelessWidget {
  const _CabecalhoDetalhe({
    required this.cliente,
    required this.onEditar,
    required this.onExcluir,
    required this.onFechar,
  });
  final _ClienteResumo cliente;
  final VoidCallback onEditar;
  final VoidCallback onExcluir;
  final VoidCallback onFechar;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 22, 18, 22),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [_CCTheme.primaryDeep, _CCTheme.primary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _AvatarGrande(nome: cliente.nome, fotoUrl: cliente.fotoUrl),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  cliente.nomeOuFallback,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 10,
                  runSpacing: 6,
                  children: [
                    _ChipInfo(
                      icone: Icons.email_rounded,
                      texto: cliente.email.isEmpty ? '—' : cliente.email,
                    ),
                    _ChipInfo(
                      icone: Icons.phone_rounded,
                      texto: cliente.telefone.isEmpty
                          ? '—'
                          : cliente.telefoneFormatado,
                    ),
                    if (cliente.cpf.isNotEmpty)
                      _ChipInfo(
                        icone: Icons.fingerprint_rounded,
                        texto: cliente.cpfFormatado,
                      ),
                    _ChipInfo(
                      icone: Icons.place_rounded,
                      texto: cliente.cidadeUf,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _BotaoCabecalho(
            icone: Icons.edit_rounded,
            label: 'Editar',
            onTap: onEditar,
          ),
          const SizedBox(width: 8),
          _BotaoCabecalho(
            icone: Icons.delete_outline_rounded,
            label: 'Excluir',
            destrutivo: true,
            onTap: onExcluir,
          ),
          const SizedBox(width: 12),
          IconButton(
            tooltip: 'Fechar',
            onPressed: onFechar,
            icon: const Icon(Icons.close_rounded, color: Colors.white),
          ),
        ],
      ),
    );
  }
}

class _AvatarGrande extends StatelessWidget {
  const _AvatarGrande({required this.nome, required this.fotoUrl});
  final String nome;
  final String? fotoUrl;
  @override
  Widget build(BuildContext context) {
    final iniciais = _gerarIniciais(nome);
    return Container(
      width: 70,
      height: 70,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.45), width: 2),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: (fotoUrl ?? '').isNotEmpty
            ? Image.network(
                fotoUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _fallbackIniciais(iniciais),
              )
            : _fallbackIniciais(iniciais),
      ),
    );
  }

  Widget _fallbackIniciais(String s) {
    return Center(
      child: Text(
        s,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 24,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  String _gerarIniciais(String nome) {
    final parts = nome.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }
}

class _ChipInfo extends StatelessWidget {
  const _ChipInfo({required this.icone, required this.texto});
  final IconData icone;
  final String texto;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.32)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icone, color: Colors.white, size: 13),
          const SizedBox(width: 6),
          Text(
            texto,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _BotaoCabecalho extends StatelessWidget {
  const _BotaoCabecalho({
    required this.icone,
    required this.label,
    required this.onTap,
    this.destrutivo = false,
  });
  final IconData icone;
  final String label;
  final VoidCallback onTap;
  final bool destrutivo;
  @override
  Widget build(BuildContext context) {
    final cor = destrutivo ? const Color(0xFFFFB4B0) : Colors.white;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: destrutivo
              ? Colors.white.withValues(alpha: 0.10)
              : Colors.white.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: destrutivo
                ? const Color(0xFFFFB4B0).withValues(alpha: 0.5)
                : Colors.white.withValues(alpha: 0.32),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icone, color: cor, size: 15),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: cor,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Bloco financeiro: KPIs derivados dos pedidos ────────────────────────────

class _BlocoFinanceiroCliente extends StatelessWidget {
  const _BlocoFinanceiroCliente({required this.cliente});
  final _ClienteResumo cliente;
  @override
  Widget build(BuildContext context) {
    // Stream do user para refletir saldo em tempo real (em vez do snapshot
    // estático recebido via _ClienteResumo).
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(cliente.uid)
          .snapshots(),
      builder: (context, userSnap) {
        final saldoTempoReal = (() {
          final d = userSnap.data;
          if (d == null || !d.exists) return cliente.saldo ?? 0;
          final m = safeWebDocData(d);
          final v = m['saldo'];
          if (v is num) return v.toDouble();
          return cliente.saldo ?? 0;
        })();

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('pedidos')
              .where('cliente_id', isEqualTo: cliente.uid)
              .snapshots(),
          builder: (context, snap) {
        if (snap.hasError) {
          return _BoxAlerta(
            cor: _CCTheme.danger,
            corSoft: _CCTheme.dangerSoft,
            texto: 'Erro ao carregar pedidos: ${snap.error}',
          );
        }
        final docs = snap.data?.docs ?? const [];
        var concluidos = 0;
        var cancelados = 0;
        var emAndamento = 0;
        double totalGasto = 0;
        double ticketMedio = 0;
        double maiorPedido = 0;
        DateTime? ultimoPedido;

        for (final d in docs) {
          final raw = safeWebDocData(d);
          if (raw.isEmpty) continue;
          final st = (raw['status'] ?? '').toString().toLowerCase();
          final total = _toNum(raw['valor_total_pago_cliente']) ??
              _toNum(raw['total']) ??
              _toNum(raw['valor_total']) ??
              0;
          final criado = raw['criado_em'];
          final dt = (criado is Timestamp) ? criado.toDate() : null;

          if (st == 'entregue' || st == 'concluido' || st == 'concluído') {
            concluidos += 1;
            totalGasto += total;
            if (total > maiorPedido) maiorPedido = total;
            if (dt != null && (ultimoPedido == null || dt.isAfter(ultimoPedido))) {
              ultimoPedido = dt;
            }
          } else if (st == 'cancelado' ||
              st == 'recusado' ||
              st == 'estornado' ||
              st == 'pix_expirado') {
            cancelados += 1;
          } else {
            emAndamento += 1;
          }
        }
        if (concluidos > 0) ticketMedio = totalGasto / concluidos;

        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: _CCTheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _CCTheme.borderSoft),
            boxShadow: _CCTheme.sombraCard,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _TituloBloco(
                icone: Icons.payments_rounded,
                titulo: 'Resumo financeiro',
                sub: 'Visão consolidada dos pedidos do cliente',
              ),
              const SizedBox(height: 16),
              LayoutBuilder(builder: (ctx, c) {
                final cards = [
                  _MiniKpi(
                    label: 'Total gasto',
                    valor: _formatadorReal.format(totalGasto),
                    cor: _CCTheme.emerald,
                    corSoft: _CCTheme.emeraldSoft,
                    icone: Icons.trending_up_rounded,
                  ),
                  _MiniKpi(
                    label: 'Ticket médio',
                    valor: _formatadorReal.format(ticketMedio),
                    cor: _CCTheme.sky,
                    corSoft: _CCTheme.skySoft,
                    icone: Icons.equalizer_rounded,
                  ),
                  _MiniKpi(
                    label: 'Maior pedido',
                    valor: _formatadorReal.format(maiorPedido),
                    cor: _CCTheme.primary,
                    corSoft: const Color(0xFFEFE5F8),
                    icone: Icons.star_rounded,
                  ),
                  _MiniKpi(
                    label: 'Saldo carteira',
                    valor: _formatadorReal.format(saldoTempoReal),
                    cor: _CCTheme.amber,
                    corSoft: _CCTheme.amberSoft,
                    icone: Icons.account_balance_wallet_rounded,
                  ),
                ];
                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final card in cards)
                      SizedBox(width: (c.maxWidth - 36) / 4, child: card),
                  ],
                );
              }),
              const SizedBox(height: 16),
              Row(
                children: [
                  _BadgeStatusFin(
                    cor: _CCTheme.emerald,
                    corSoft: _CCTheme.emeraldSoft,
                    label: 'Concluídos',
                    valor: concluidos,
                  ),
                  const SizedBox(width: 10),
                  _BadgeStatusFin(
                    cor: _CCTheme.amber,
                    corSoft: _CCTheme.amberSoft,
                    label: 'Em andamento',
                    valor: emAndamento,
                  ),
                  const SizedBox(width: 10),
                  _BadgeStatusFin(
                    cor: _CCTheme.danger,
                    corSoft: _CCTheme.dangerSoft,
                    label: 'Cancelados',
                    valor: cancelados,
                  ),
                  const Spacer(),
                  if (ultimoPedido != null)
                    Text(
                      'Último pedido: ${DateFormat('dd/MM/yyyy', 'pt_BR').format(ultimoPedido)}',
                      style: const TextStyle(
                        color: _CCTheme.textMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                ],
              ),
            ],
          ),
        );
          },
        );
      },
    );
  }
}

class _MiniKpi extends StatelessWidget {
  const _MiniKpi({
    required this.label,
    required this.valor,
    required this.cor,
    required this.corSoft,
    required this.icone,
  });
  final String label;
  final String valor;
  final Color cor;
  final Color corSoft;
  final IconData icone;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _CCTheme.surfaceElev,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _CCTheme.borderSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: corSoft,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icone, color: cor, size: 16),
              ),
              const Spacer(),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            label,
            style: const TextStyle(
              color: _CCTheme.textMuted,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            valor,
            style: const TextStyle(
              color: _CCTheme.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _BadgeStatusFin extends StatelessWidget {
  const _BadgeStatusFin({
    required this.cor,
    required this.corSoft,
    required this.label,
    required this.valor,
  });
  final Color cor;
  final Color corSoft;
  final String label;
  final int valor;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: corSoft,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: cor,
              borderRadius: BorderRadius.circular(7),
            ),
            child: Center(
              child: Text(
                valor.toString(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: cor,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _BlocoLayoutDuplo extends StatelessWidget {
  const _BlocoLayoutDuplo({required this.cliente});
  final _ClienteResumo cliente;
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (ctx, c) {
      final wide = c.maxWidth >= 800;
      final esquerda = _BlocoDadosPessoais(cliente: cliente);
      final direita = _BlocoEnderecos(cliente: cliente);

      if (wide) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: esquerda),
            const SizedBox(width: 14),
            Expanded(child: direita),
          ],
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          esquerda,
          const SizedBox(height: 14),
          direita,
        ],
      );
    });
  }
}

class _BlocoDadosPessoais extends StatelessWidget {
  const _BlocoDadosPessoais({required this.cliente});
  final _ClienteResumo cliente;
  @override
  Widget build(BuildContext context) {
    final m = cliente.dadosBrutos;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _CCTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _CCTheme.borderSoft),
        boxShadow: _CCTheme.sombraCard,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _TituloBloco(
            icone: Icons.badge_rounded,
            titulo: 'Dados pessoais',
            sub: 'Informações cadastrais',
          ),
          const SizedBox(height: 14),
          _LinhaInfo(label: 'Nome', valor: cliente.nomeOuFallback),
          _LinhaInfo(label: 'E-mail', valor: cliente.email.isEmpty ? '—' : cliente.email),
          _LinhaInfo(label: 'Telefone', valor: cliente.telefone.isEmpty ? '—' : cliente.telefoneFormatado),
          _LinhaInfo(label: 'CPF', valor: cliente.cpf.isEmpty ? '—' : cliente.cpfFormatado),
          _LinhaInfo(label: 'Cidade / UF', valor: cliente.cidadeUf),
          _LinhaInfo(label: 'Cadastro', valor: cliente.criadoEmFormatado),
          _LinhaInfo(
            label: 'UID',
            valor: cliente.uid,
            copiavel: true,
          ),
          _LinhaInfo(
            label: 'Status',
            valor: cliente.bloqueado ? 'Bloqueado' : 'Ativo',
            corValor: cliente.bloqueado ? _CCTheme.danger : _CCTheme.emerald,
          ),
          _LinhaInfo(
            label: 'Provedor login',
            valor: (m['provider_login'] ?? m['providerId'] ?? 'email/senha')
                .toString(),
          ),
        ],
      ),
    );
  }
}

class _BlocoEnderecos extends StatelessWidget {
  const _BlocoEnderecos({required this.cliente});
  final _ClienteResumo cliente;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _CCTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _CCTheme.borderSoft),
        boxShadow: _CCTheme.sombraCard,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _TituloBloco(
            icone: Icons.location_on_rounded,
            titulo: 'Endereços salvos',
            sub: 'Locais utilizados em entregas',
          ),
          const SizedBox(height: 12),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('users')
                .doc(cliente.uid)
                .collection('enderecos')
                .snapshots(),
            builder: (context, snap) {
              if (snap.hasError) {
                return Text('Erro: ${snap.error}',
                    style: const TextStyle(color: _CCTheme.danger));
              }
              final docs = snap.data?.docs ?? const [];
              if (snap.connectionState == ConnectionState.waiting &&
                  docs.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: CircularProgressIndicator(color: _CCTheme.primary),
                  ),
                );
              }
              if (docs.isEmpty) {
                return _vazioEnderecos();
              }
              return Column(
                children: [
                  for (final d in docs)
                    _CardEndereco(dados: safeWebDocData(d)),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _vazioEnderecos() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Center(
        child: Column(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: _CCTheme.surfaceElev,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.map_rounded,
                  color: _CCTheme.textMuted, size: 24),
            ),
            const SizedBox(height: 8),
            const Text(
              'Nenhum endereço cadastrado.',
              style: TextStyle(
                color: _CCTheme.textMuted,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CardEndereco extends StatelessWidget {
  const _CardEndereco({required this.dados});
  final Map<String, dynamic> dados;
  @override
  Widget build(BuildContext context) {
    final apelido = (dados['apelido'] ?? dados['nome'] ?? 'Endereço').toString();
    final rua = (dados['rua'] ?? dados['logradouro'] ?? '').toString();
    final numero = (dados['numero'] ?? '').toString();
    final bairro = (dados['bairro'] ?? '').toString();
    final cidade = (dados['cidade'] ?? '').toString();
    final uf = (dados['uf'] ?? dados['estado'] ?? '').toString();
    final cep = (dados['cep'] ?? '').toString();
    final compl = (dados['complemento'] ?? '').toString();
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _CCTheme.surfaceElev,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _CCTheme.borderSoft),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFFEFE5F8),
              borderRadius: BorderRadius.circular(9),
            ),
            child: const Icon(Icons.home_rounded,
                color: _CCTheme.primary, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  apelido,
                  style: const TextStyle(
                    color: _CCTheme.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$rua${numero.isNotEmpty ? ', $numero' : ''}'
                  '${compl.isNotEmpty ? ' — $compl' : ''}',
                  style: const TextStyle(
                    color: _CCTheme.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  '$bairro${bairro.isNotEmpty && cidade.isNotEmpty ? ' • ' : ''}$cidade${uf.isNotEmpty ? ' / $uf' : ''}'
                  '${cep.isNotEmpty ? ' • CEP $cep' : ''}',
                  style: const TextStyle(
                    color: _CCTheme.textMuted,
                    fontSize: 11.5,
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
}

class _BlocoPedidosCliente extends StatelessWidget {
  const _BlocoPedidosCliente({required this.cliente});
  final _ClienteResumo cliente;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
      decoration: BoxDecoration(
        color: _CCTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _CCTheme.borderSoft),
        boxShadow: _CCTheme.sombraCard,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _TituloBloco(
            icone: Icons.list_alt_rounded,
            titulo: 'Histórico de pedidos',
            sub: 'Todos os pedidos realizados pelo cliente',
          ),
          const SizedBox(height: 12),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('pedidos')
                .where('cliente_id', isEqualTo: cliente.uid)
                .snapshots(),
            builder: (context, snap) {
              if (snap.hasError) {
                return Text('Erro: ${snap.error}',
                    style: const TextStyle(color: _CCTheme.danger));
              }
              final docs = snap.data?.docs ?? const [];
              if (snap.connectionState == ConnectionState.waiting &&
                  docs.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 30),
                  child: Center(
                    child: CircularProgressIndicator(color: _CCTheme.primary),
                  ),
                );
              }
              if (docs.isEmpty) {
                return _vazio();
              }
              final pedidos = docs.map((d) {
                final m = safeWebDocData(d);
                return _ResumoPedido(
                  id: d.id,
                  loja: (m['loja_nome'] ?? m['nome_loja'] ?? '').toString(),
                  status: (m['status'] ?? '').toString(),
                  total: _toNum(m['valor_total_pago_cliente']) ??
                      _toNum(m['total']) ??
                      _toNum(m['valor_total']) ??
                      0,
                  criado: m['criado_em'] is Timestamp
                      ? (m['criado_em'] as Timestamp).toDate()
                      : null,
                  pagamento: (m['forma_pagamento'] ?? m['pagamento_tipo'] ?? '')
                      .toString(),
                );
              }).toList()
                ..sort((a, b) {
                  final ta = a.criado?.millisecondsSinceEpoch ?? 0;
                  final tb = b.criado?.millisecondsSinceEpoch ?? 0;
                  return tb.compareTo(ta);
                });

              return Column(
                children: [
                  for (final p in pedidos.take(50)) _LinhaPedido(p: p),
                  if (pedidos.length > 50)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'Exibindo os 50 mais recentes de ${pedidos.length}',
                        style: const TextStyle(
                          color: _CCTheme.textMuted,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _vazio() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: Column(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: _CCTheme.surfaceElev,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(Icons.receipt_long_rounded,
                  color: _CCTheme.textMuted, size: 28),
            ),
            const SizedBox(height: 8),
            const Text(
              'Este cliente ainda não realizou pedidos.',
              style: TextStyle(
                color: _CCTheme.textMuted,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResumoPedido {
  _ResumoPedido({
    required this.id,
    required this.loja,
    required this.status,
    required this.total,
    required this.criado,
    required this.pagamento,
  });
  final String id;
  final String loja;
  final String status;
  final double total;
  final DateTime? criado;
  final String pagamento;
}

class _LinhaPedido extends StatelessWidget {
  const _LinhaPedido({required this.p});
  final _ResumoPedido p;

  static const Map<String, _ConfStatus> _mapaStatus = {
    'aguardando_pagamento': _ConfStatus(_CCTheme.amber, _CCTheme.amberSoft, 'Aguardando pagamento'),
    'pago': _ConfStatus(_CCTheme.emerald, _CCTheme.emeraldSoft, 'Pago'),
    'em_preparo': _ConfStatus(_CCTheme.sky, _CCTheme.skySoft, 'Em preparo'),
    'aguardando_entregador': _ConfStatus(_CCTheme.sky, _CCTheme.skySoft, 'Buscando entregador'),
    'pronto_para_entrega': _ConfStatus(_CCTheme.sky, _CCTheme.skySoft, 'Pronto'),
    'a_caminho': _ConfStatus(_CCTheme.primary, Color(0xFFEFE5F8), 'A caminho'),
    'saiu_para_entrega': _ConfStatus(_CCTheme.primary, Color(0xFFEFE5F8), 'Saiu p/ entrega'),
    'entregue': _ConfStatus(_CCTheme.emerald, _CCTheme.emeraldSoft, 'Entregue'),
    'cancelado': _ConfStatus(_CCTheme.danger, _CCTheme.dangerSoft, 'Cancelado'),
    'recusado': _ConfStatus(_CCTheme.danger, _CCTheme.dangerSoft, 'Recusado'),
    'estornado': _ConfStatus(_CCTheme.textMuted, Color(0xFFEEEDF2), 'Estornado'),
    'pix_expirado': _ConfStatus(_CCTheme.textMuted, Color(0xFFEEEDF2), 'PIX expirado'),
  };

  @override
  Widget build(BuildContext context) {
    final cfg = _mapaStatus[p.status.toLowerCase()] ??
        const _ConfStatus(_CCTheme.textSecondary, Color(0xFFEEEDF2), '—');
    final dataFmt = p.criado == null
        ? '—'
        : DateFormat('dd/MM/yyyy HH:mm', 'pt_BR').format(p.criado!);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: _CCTheme.surfaceElev,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _CCTheme.borderSoft),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: cfg.soft,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.receipt_long_rounded, color: cfg.solid, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p.loja.isEmpty ? 'Pedido #${p.id.substring(0, 6)}' : p.loja,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _CCTheme.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  '#${p.id.substring(0, p.id.length < 8 ? p.id.length : 8)} • $dataFmt',
                  style: const TextStyle(
                    color: _CCTheme.textMuted,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: cfg.soft,
                borderRadius: BorderRadius.circular(20),
              ),
              alignment: Alignment.center,
              child: Text(
                cfg.label,
                style: TextStyle(
                  color: cfg.solid,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                p.pagamento.isEmpty ? '—' : p.pagamento.toUpperCase(),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: _CCTheme.textSecondary,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                ),
              ),
            ),
          ),
          SizedBox(
            width: 100,
            child: Text(
              _formatadorReal.format(p.total),
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: _CCTheme.textPrimary,
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConfStatus {
  const _ConfStatus(this.solid, this.soft, this.label);
  final Color solid;
  final Color soft;
  final String label;
}

class _LinhaInfo extends StatelessWidget {
  const _LinhaInfo({
    required this.label,
    required this.valor,
    this.copiavel = false,
    this.corValor,
  });
  final String label;
  final String valor;
  final bool copiavel;
  final Color? corValor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(
                color: _CCTheme.textMuted,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
              ),
            ),
          ),
          Expanded(
            child: Text(
              valor,
              style: TextStyle(
                color: corValor ?? _CCTheme.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (copiavel)
            InkWell(
              onTap: () {
                Clipboard.setData(ClipboardData(text: valor));
                ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                  const SnackBar(
                    content: Text('Copiado para a área de transferência'),
                    backgroundColor: _CCTheme.primary,
                    duration: Duration(seconds: 2),
                  ),
                );
              },
              borderRadius: BorderRadius.circular(6),
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.copy_rounded,
                    color: _CCTheme.textMuted, size: 14),
              ),
            ),
        ],
      ),
    );
  }
}

class _TituloBloco extends StatelessWidget {
  const _TituloBloco({
    required this.icone,
    required this.titulo,
    required this.sub,
  });
  final IconData icone;
  final String titulo;
  final String sub;
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: const Color(0xFFEFE5F8),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icone, color: _CCTheme.primary, size: 20),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              titulo,
              style: const TextStyle(
                color: _CCTheme.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(
              sub,
              style: const TextStyle(
                color: _CCTheme.textMuted,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _BoxAlerta extends StatelessWidget {
  const _BoxAlerta({
    required this.cor,
    required this.corSoft,
    required this.texto,
  });
  final Color cor;
  final Color corSoft;
  final String texto;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: corSoft,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        texto,
        style: TextStyle(color: cor, fontWeight: FontWeight.w600),
      ),
    );
  }
}

double? _toNum(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString().replaceAll(',', '.'));
}

/// Acumulador interno usado para agregar pedidos por cliente.
class _AgregadoPedidos {
  int contagem = 0;
  double totalGasto = 0;
}

// ─────────────────────────────────────────────────────────────────────────────
// DIALOG EDITAR
// ─────────────────────────────────────────────────────────────────────────────

class _DialogEditarCliente extends StatefulWidget {
  const _DialogEditarCliente({required this.cliente});
  final _ClienteResumo cliente;
  @override
  State<_DialogEditarCliente> createState() => _DialogEditarClienteState();
}

class _DialogEditarClienteState extends State<_DialogEditarCliente> {
  late final TextEditingController _nome;
  late final TextEditingController _telefone;
  late final TextEditingController _cpf;
  late final TextEditingController _cidade;
  late final TextEditingController _uf;
  late bool _bloqueado;
  bool _salvando = false;

  @override
  void initState() {
    super.initState();
    _nome = TextEditingController(text: widget.cliente.nome);
    _telefone = TextEditingController(text: widget.cliente.telefone);
    _cpf = TextEditingController(text: widget.cliente.cpf);
    _cidade = TextEditingController(text: widget.cliente.cidade);
    _uf = TextEditingController(text: widget.cliente.uf);
    _bloqueado = widget.cliente.bloqueado;
  }

  @override
  void dispose() {
    _nome.dispose();
    _telefone.dispose();
    _cpf.dispose();
    _cidade.dispose();
    _uf.dispose();
    super.dispose();
  }

  Future<void> _salvar() async {
    setState(() => _salvando = true);
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.cliente.uid)
          .set({
        'nome': _nome.text.trim(),
        'telefone': _telefone.text.trim(),
        'cpf': _cpf.text.trim(),
        'cidade': _cidade.text.trim(),
        'uf': _uf.text.trim().toUpperCase(),
        'conta_bloqueada': _bloqueado,
        'editado_em': FieldValue.serverTimestamp(),
        'editado_por': FirebaseAuth.instance.currentUser?.uid,
      }, SetOptions(merge: true));

      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          backgroundColor: _CCTheme.emerald,
          content: Text('Dados do cliente atualizados.'),
        ),
      );
    } catch (e) {
      setState(() => _salvando = false);
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          backgroundColor: _CCTheme.danger,
          content: Text('Erro ao salvar: $e'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 36, vertical: 36),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Container(
          decoration: BoxDecoration(
            color: _CCTheme.surface,
            borderRadius: BorderRadius.circular(20),
          ),
          clipBehavior: Clip.hardEdge,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [_CCTheme.primaryDeep, _CCTheme.primary],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.edit_rounded,
                          color: Colors.white, size: 20),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Text(
                        'Editar cliente',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed:
                          _salvando ? null : () => Navigator.of(context).pop(),
                      icon:
                          const Icon(Icons.close_rounded, color: Colors.white),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _CampoEdit(label: 'Nome completo', controller: _nome),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _CampoEdit(
                            label: 'Telefone',
                            controller: _telefone,
                            tipo: TextInputType.phone,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _CampoEdit(
                            label: 'CPF',
                            controller: _cpf,
                            tipo: TextInputType.number,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: _CampoEdit(
                              label: 'Cidade', controller: _cidade),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 1,
                          child: _CampoEdit(
                            label: 'UF',
                            controller: _uf,
                            maxLength: 2,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      activeThumbColor: _CCTheme.danger,
                      title: const Text(
                        'Conta bloqueada',
                        style: TextStyle(
                          color: _CCTheme.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      subtitle: const Text(
                        'Impede o cliente de fazer login e novos pedidos.',
                        style: TextStyle(
                          color: _CCTheme.textMuted,
                          fontSize: 12,
                        ),
                      ),
                      value: _bloqueado,
                      onChanged: _salvando
                          ? null
                          : (v) => setState(() => _bloqueado = v),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: _salvando
                              ? null
                              : () => Navigator.of(context).pop(),
                          child: const Text('Cancelar'),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.icon(
                          onPressed: _salvando ? null : _salvar,
                          style: FilledButton.styleFrom(
                            backgroundColor: _CCTheme.primary,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 22, vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          icon: _salvando
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.save_rounded, size: 18),
                          label: Text(_salvando ? 'Salvando...' : 'Salvar alterações'),
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
}

class _CampoEdit extends StatelessWidget {
  const _CampoEdit({
    required this.label,
    required this.controller,
    this.tipo,
    this.maxLength,
  });
  final String label;
  final TextEditingController controller;
  final TextInputType? tipo;
  final int? maxLength;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6, left: 4),
          child: Text(
            label,
            style: const TextStyle(
              color: _CCTheme.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
            ),
          ),
        ),
        TextField(
          controller: controller,
          keyboardType: tipo,
          maxLength: maxLength,
          decoration: InputDecoration(
            counterText: '',
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            filled: true,
            fillColor: _CCTheme.surfaceElev,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: _CCTheme.borderSoft),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: _CCTheme.borderSoft),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: _CCTheme.primary, width: 2),
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// DIALOG CONFIRMAR EXCLUSÃO
// ─────────────────────────────────────────────────────────────────────────────

class _DialogConfirmExclusao extends StatefulWidget {
  const _DialogConfirmExclusao({required this.cliente});
  final _ClienteResumo cliente;
  @override
  State<_DialogConfirmExclusao> createState() => _DialogConfirmExclusaoState();
}

class _DialogConfirmExclusaoState extends State<_DialogConfirmExclusao> {
  final TextEditingController _confirma = TextEditingController();
  static const _palavraChave = 'EXCLUIR';

  @override
  void dispose() {
    _confirma.dispose();
    super.dispose();
  }

  bool get _podeConfirmar =>
      _confirma.text.trim().toUpperCase() == _palavraChave;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 36, vertical: 36),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Container(
          decoration: BoxDecoration(
            color: _CCTheme.surface,
            borderRadius: BorderRadius.circular(20),
          ),
          clipBehavior: Clip.hardEdge,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(22),
                decoration: const BoxDecoration(
                  color: _CCTheme.dangerSoft,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: _CCTheme.danger,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.warning_amber_rounded,
                          color: Colors.white, size: 24),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Text(
                        'Excluir cliente do banco',
                        style: TextStyle(
                          color: _CCTheme.danger,
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(22),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text.rich(
                      TextSpan(
                        text: 'Esta ação irá REMOVER PERMANENTEMENTE a conta de ',
                        style: const TextStyle(
                          color: _CCTheme.textSecondary,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w500,
                          height: 1.45,
                        ),
                        children: [
                          TextSpan(
                            text: widget.cliente.nomeOuFallback,
                            style: const TextStyle(
                              color: _CCTheme.textPrimary,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const TextSpan(
                            text:
                                ' do Firestore e do Firebase Authentication.\n\n',
                          ),
                          const TextSpan(
                            text:
                                'O histórico de pedidos antigos será mantido para fins fiscais, '
                                'mas o cliente não poderá mais fazer login. '
                                'A operação é IRREVERSÍVEL.',
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _CCTheme.dangerSoft,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.shield_rounded,
                              color: _CCTheme.danger, size: 18),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Para confirmar, digite a palavra "$_palavraChave" abaixo.',
                              style: const TextStyle(
                                color: _CCTheme.danger,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _confirma,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: 'Digite EXCLUIR',
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 14),
                        filled: true,
                        fillColor: _CCTheme.surfaceElev,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(
                              color: _CCTheme.borderSoft),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(
                              color: _CCTheme.borderSoft),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(
                              color: _CCTheme.danger, width: 2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 22),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(false),
                          child: const Text('Cancelar'),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.icon(
                          onPressed: _podeConfirmar
                              ? () => Navigator.of(context).pop(true)
                              : null,
                          style: FilledButton.styleFrom(
                            backgroundColor: _CCTheme.danger,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 22, vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          icon: const Icon(Icons.delete_forever_rounded,
                              size: 18),
                          label: const Text('Excluir definitivamente'),
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
}
