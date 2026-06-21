import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:depertin_web/constants/pedido_status.dart';
import 'package:depertin_web/constants/tipos_entrega.dart';
import 'package:depertin_web/services/firebase_functions_config.dart';
import 'package:depertin_web/services/sessao_painel_service.dart';
import 'package:depertin_web/theme/painel_admin_theme.dart';
import 'package:depertin_web/utils/codigo_pedido.dart';
import 'package:depertin_web/utils/csv_download.dart';
import 'package:depertin_web/utils/lojista_painel_context.dart';
import 'package:depertin_web/utils/pedido_recibo_pdf.dart';
import 'package:depertin_web/widgets/chamar_entregador_modal.dart';
import 'package:depertin_web/widgets/escolher_tipo_entrega_dialog.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

// --- Constantes de status (espelham `PedidoStatus` do app mobile) ---
const String _kPendente = 'pendente';
const String _kNovo = 'novo';
const String _kAguardandoPagamento = 'aguardando_pagamento';
const String _kEncomendaEntradaPaga = 'encomenda_entrada_paga';
const String _kAceito = 'aceito';
const String _kEmPreparo = 'em_preparo';
const String _kPreparando = 'preparando';
const String _kPronto = 'pronto';
const String _kAguardandoEntregador = 'aguardando_entregador';
const String _kEntregadorIndoLoja = 'entregador_indo_loja';
const String _kSaiuEntrega = 'saiu_entrega';
const String _kEmRota = 'em_rota';
const String _kACaminho = 'a_caminho';
const String _kEntregue = 'entregue';
const String _kCancelado = 'cancelado';

/// Tela "Meus pedidos" do lojista — Data Grid profissional (estilo SaaS).
class LojistaPedidosTabelaScreen extends StatefulWidget {
  const LojistaPedidosTabelaScreen({super.key});

  @override
  State<LojistaPedidosTabelaScreen> createState() =>
      _LojistaPedidosTabelaScreenState();
}

class _LojistaPedidosTabelaScreenState
    extends State<LojistaPedidosTabelaScreen> {
  static const _roxo = PainelAdminTheme.roxo;
  static const _laranja = PainelAdminTheme.laranja;

  final _buscaC = TextEditingController();
  String _filtro = 'ativos'; // ativos | entregue | cancelado | todos
  String _periodo = 'tudo'; // tudo | hoje | 7d | 30d
  String _sortKey = 'data'; // data | total
  bool _sortAsc = false;
  bool _ocupado = false;

  final Map<String, String> _nomesCliente = {};

  @override
  void dispose() {
    _buscaC.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Helpers de status
  // ---------------------------------------------------------------------------
  String _labelStatus(String s) {
    switch (s) {
      case _kPendente:
      case _kNovo:
        return 'Novo';
      case _kAguardandoPagamento:
        return 'Aguardando Pagamento';
      case _kEncomendaEntradaPaga:
        return 'Encomenda';
      case _kAceito:
        return 'Aceito';
      case _kEmPreparo:
      case _kPreparando:
        return 'Preparando';
      case _kPronto:
        return 'Pronto';
      case _kAguardandoEntregador:
      case _kEntregadorIndoLoja:
        return 'Buscando entregador';
      case _kSaiuEntrega:
      case _kEmRota:
      case _kACaminho:
        return 'Saiu para entrega';
      case _kEntregue:
        return 'Entregue';
      case _kCancelado:
        return 'Cancelado';
      default:
        return s.isEmpty ? '—' : s;
    }
  }

  Color _corStatus(String s) {
    switch (s) {
      case _kPendente:
      case _kNovo:
        return _laranja;
      case _kAguardandoPagamento:
        return const Color(0xFFD97706);
      case _kEncomendaEntradaPaga:
        return const Color(0xFFB7791F);
      case _kAceito:
        return const Color(0xFF1D4ED8);
      case _kEmPreparo:
      case _kPreparando:
      case _kPronto:
        return _roxo;
      case _kAguardandoEntregador:
      case _kEntregadorIndoLoja:
      case _kSaiuEntrega:
      case _kEmRota:
      case _kACaminho:
        return const Color(0xFF0891B2);
      case _kEntregue:
        return const Color(0xFF15803D);
      case _kCancelado:
        return const Color(0xFFB91C1C);
      default:
        return _roxo;
    }
  }

  bool _passaFiltro(String status) {
    switch (_filtro) {
      case 'ativos':
        return status != _kEntregue && status != _kCancelado;
      case 'entregue':
        return status == _kEntregue;
      case 'cancelado':
        return status == _kCancelado;
      default:
        return true;
    }
  }

  bool _passaPeriodo(Timestamp? ts) {
    if (_periodo == 'tudo' || ts == null) return true;
    final agora = DateTime.now();
    final data = ts.toDate();
    switch (_periodo) {
      case 'hoje':
        return data.year == agora.year &&
            data.month == agora.month &&
            data.day == agora.day;
      case '7d':
        return data.isAfter(agora.subtract(const Duration(days: 7)));
      case '30d':
        return data.isAfter(agora.subtract(const Duration(days: 30)));
      default:
        return true;
    }
  }

  double _num(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }

  int _getEtapa(String status) {
    switch (status) {
      case _kPendente:
      case _kNovo:
      case _kAguardandoPagamento:
      case _kEncomendaEntradaPaga:
        return 1;
      case _kAceito:
        return 2;
      case _kEmPreparo:
      case _kPreparando:
      case _kPronto:
        return 3;
      case _kAguardandoEntregador:
      case _kEntregadorIndoLoja:
      case _kSaiuEntrega:
      case _kEmRota:
      case _kACaminho:
      case _kEntregue:
        return 4;
      default:
        return 1;
    }
  }

  void _resolverNomesCliente(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    for (final d in docs) {
      final data = d.data();
      final id = data['cliente_id']?.toString().trim();
      if (id == null || id.isEmpty) continue;
      final nome = (data['cliente_nome'] ?? '').toString().trim();
      _nomesCliente[id] = nome.isNotEmpty ? nome : 'Cliente';
    }
  }

  void _snack(String msg, {bool ok = true}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: ok ? Colors.green.shade700 : Colors.red.shade700,
      ),
    );
  }

  BuildContext get _ctxDialogo =>
      SessaoPainelService.navigatorKey.currentContext ?? context;

  Future<void> _mostrarDialogoFeedback({
    required String titulo,
    required String mensagem,
    required bool sucesso,
  }) async {
    final cor = sucesso ? const Color(0xFF15803D) : Colors.red.shade700;
    final icone = sucesso ? Icons.check_circle_outline : Icons.error_outline;
    await showDialog<void>(
      context: _ctxDialogo,
      useRootNavigator: true,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: cor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(icone, color: cor, size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        titulo,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1A1A2E),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  mensagem,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.45,
                    color: Colors.grey.shade700,
                  ),
                ),
                const SizedBox(height: 22),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: sucesso ? cor : _roxo,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Entendi'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return LojistaUidLojaBuilder(
      builder: (context, authUid, uidLoja, dadosUsuario) {
        return Scaffold(
          backgroundColor: const Color(0xFFF4F5F7),
          body: Column(
            children: [
              _buildHeader(uidLoja),
              _buildTabs(uidLoja),
              Expanded(child: _buildConteudo(uidLoja, dadosUsuario)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(String uidLoja) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB), width: 1)),
      ),
      child: LayoutBuilder(
        builder: (context, c) {
          final compacto = c.maxWidth < 720;
          final busca = SizedBox(
            width: compacto ? double.infinity : 280,
            child: TextField(
              controller: _buscaC,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Buscar pedido ou cliente...',
                hintStyle: TextStyle(color: Colors.grey.shade400),
                prefixIcon:
                    Icon(Icons.search, color: Colors.grey.shade400, size: 20),
                filled: true,
                fillColor: const Color(0xFFF4F5F7),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                isDense: true,
              ),
            ),
          );

          final controles = [
            _buildPeriodoFiltro(),
            const SizedBox(width: 8),
            _buildBotaoExportar(uidLoja),
          ];

          if (compacto) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(Icons.receipt_long_outlined,
                        color: _roxo, size: 26),
                    const SizedBox(width: 10),
                    const Text(
                      'Pedidos',
                      style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF1A1A2E)),
                    ),
                    const Spacer(),
                    _buildOnlineIndicator(),
                  ],
                ),
                const SizedBox(height: 12),
                busca,
                const SizedBox(height: 12),
                Row(children: controles),
              ],
            );
          }

          return Row(
            children: [
              const Icon(Icons.receipt_long_outlined, color: _roxo, size: 28),
              const SizedBox(width: 12),
              const Text(
                'Pedidos',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1A1A2E),
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(width: 12),
              _buildOnlineIndicator(),
              const Spacer(),
              busca,
              const SizedBox(width: 12),
              ...controles,
            ],
          );
        },
      ),
    );
  }

  Widget _buildOnlineIndicator() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.green.shade200),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
                color: Colors.green, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text('Online',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.green.shade700)),
        ],
      ),
    );
  }

  Widget _buildPeriodoFiltro() {
    String label() {
      switch (_periodo) {
        case 'hoje':
          return 'Hoje';
        case '7d':
          return '7 dias';
        case '30d':
          return '30 dias';
        default:
          return 'Período';
      }
    }

    return PopupMenuButton<String>(
      tooltip: 'Filtrar por período',
      onSelected: (v) => setState(() => _periodo = v),
      itemBuilder: (_) => const [
        PopupMenuItem(value: 'hoje', child: Text('Hoje')),
        PopupMenuItem(value: '7d', child: Text('Últimos 7 dias')),
        PopupMenuItem(value: '30d', child: Text('Últimos 30 dias')),
        PopupMenuItem(value: 'tudo', child: Text('Todo o período')),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFF4F5F7),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFE5E7EB)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.calendar_today_outlined,
                size: 16, color: Colors.grey.shade600),
            const SizedBox(width: 8),
            Text(label(),
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade700)),
            const SizedBox(width: 4),
            Icon(Icons.keyboard_arrow_down,
                size: 18, color: Colors.grey.shade600),
          ],
        ),
      ),
    );
  }

  Widget _buildBotaoExportar(String uidLoja) {
    return Tooltip(
      message: 'Exportar lista (CSV/Excel)',
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _exportarCsv(uidLoja),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFFF4F5F7),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),
          child: Icon(Icons.download_outlined,
              size: 20, color: Colors.grey.shade700),
        ),
      ),
    );
  }

  Widget _buildTabs(String uidLoja) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('pedidos')
          .where('loja_id', isEqualTo: uidLoja)
          .snapshots(),
      builder: (context, snap) {
        int emAndamento = 0, entregues = 0, cancelados = 0, todos = 0;
        if (snap.hasData) {
          for (final doc in snap.data!.docs) {
            final d = doc.data();
            if (!PedidoStatusWeb.visivelNaListaLojista(d)) continue;
            final status = d['status']?.toString() ?? '';
            todos++;
            if (status == _kEntregue) {
              entregues++;
            } else if (status == _kCancelado) {
              cancelados++;
            } else {
              emAndamento++;
            }
          }
        }
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            border:
                Border(bottom: BorderSide(color: Color(0xFFE5E7EB), width: 1)),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: [
                _tabItem('Em Andamento', emAndamento, 'ativos'),
                _tabItem('Entregues', entregues, 'entregue'),
                _tabItem('Cancelados', cancelados, 'cancelado'),
                _tabItem('Todos', todos, 'todos'),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _tabItem(String label, int count, String filtro) {
    final isActive = _filtro == filtro;
    return InkWell(
      onTap: () => setState(() => _filtro = filtro),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
                color: isActive ? _roxo : Colors.transparent, width: 2),
          ),
        ),
        child: Row(
          children: [
            Text(label,
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                    color: isActive ? _roxo : Colors.grey.shade600)),
            if (count > 0) ...[
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: isActive
                      ? _roxo.withValues(alpha: 0.12)
                      : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text('$count',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: isActive ? _roxo : Colors.grey.shade600)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildConteudo(String uidLoja, Map<String, dynamic>? dadosLoja) {
    final moeda = NumberFormat.currency(locale: 'pt_BR', symbol: r'R$');
    final fmtData = DateFormat('dd/MM/yyyy • HH:mm');

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('pedidos')
          .where('loja_id', isEqualTo: uidLoja)
          .snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return const Center(child: CircularProgressIndicator(color: _roxo));
        }
        if (snap.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Erro ao carregar pedidos: ${snap.error}'),
            ),
          );
        }

        final docs = snap.data?.docs ?? [];
        _resolverNomesCliente(docs);

        final filtrados = docs.where((doc) {
          final d = doc.data();
          if (!PedidoStatusWeb.visivelNaListaLojista(d)) return false;
          final st = d['status']?.toString() ?? _kPendente;
          if (!_passaFiltro(st)) return false;
          final ts = d['data_pedido'];
          if (!_passaPeriodo(ts is Timestamp ? ts : null)) return false;
          final q = _buscaC.text.trim().toLowerCase();
          if (q.isEmpty) return true;
          final codigo = CodigoPedido.exibir(doc.id, d).toLowerCase();
          if (codigo.contains(q)) return true;
          if (doc.id.toLowerCase().contains(q)) return true;
          final cid = d['cliente_id']?.toString() ?? '';
          final nome = _nomesCliente[cid]?.toLowerCase() ?? '';
          if (nome.contains(q)) return true;
          return false;
        }).toList();

        filtrados.sort((a, b) {
          int cmp;
          if (_sortKey == 'total') {
            cmp = _num(a.data()['total']).compareTo(_num(b.data()['total']));
          } else {
            final ta = a.data()['data_pedido'];
            final tb = b.data()['data_pedido'];
            if (ta is Timestamp && tb is Timestamp) {
              cmp = ta.compareTo(tb);
            } else {
              cmp = 0;
            }
          }
          return _sortAsc ? cmp : -cmp;
        });

        if (filtrados.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.receipt_long_outlined,
                    size: 64, color: Colors.grey.shade300),
                const SizedBox(height: 16),
                Text(
                  docs.isEmpty
                      ? 'Nenhum pedido ainda'
                      : 'Nenhum pedido neste filtro',
                  style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
                ),
              ],
            ),
          );
        }

        return LayoutBuilder(
          builder: (context, c) {
            if (c.maxWidth < 820) {
              return _buildCards(filtrados, moeda, fmtData, uidLoja, dadosLoja);
            }
            return _buildDataTable(
                filtrados, moeda, fmtData, uidLoja, dadosLoja);
          },
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Tabela (desktop)
  // ---------------------------------------------------------------------------
  Widget _buildDataTable(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    NumberFormat moeda,
    DateFormat fmtData,
    String uidLoja,
    Map<String, dynamic>? dadosLoja,
  ) {
    return Container(
      margin: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              color: Color(0xFFF9FAFB),
              borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
              border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB))),
            ),
            child: Row(
              children: [
                _th('Pedido', flex: 20, sortKey: 'data'),
                _th('Cliente', flex: 22),
                _th('Status', flex: 16),
                _th('Etapa', flex: 16),
                _th('Pagamento', flex: 13),
                _th('Entrega', flex: 13),
                _th('Total', flex: 12, sortKey: 'total'),
                const SizedBox(width: 44),
              ],
            ),
          ),
          Expanded(
            child: ListView.separated(
              itemCount: docs.length,
              separatorBuilder: (_, _) =>
                  const Divider(height: 1, color: Color(0xFFEEF0F3)),
              itemBuilder: (context, i) =>
                  _buildRow(docs[i], moeda, fmtData, uidLoja, dadosLoja),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: Color(0xFFEEF0F3))),
            ),
            child: Row(
              children: [
                Text(
                  'Mostrando ${docs.length} pedido${docs.length == 1 ? '' : 's'}',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _th(String text, {int flex = 1, String? sortKey}) {
    final ativo = sortKey != null && _sortKey == sortKey;
    final child = Row(
      children: [
        Text(text,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: ativo ? _roxo : Colors.grey.shade600,
                letterSpacing: 0.3)),
        if (sortKey != null) ...[
          const SizedBox(width: 4),
          Icon(
            ativo
                ? (_sortAsc ? Icons.arrow_upward : Icons.arrow_downward)
                : Icons.unfold_more,
            size: 13,
            color: ativo ? _roxo : Colors.grey.shade400,
          ),
        ],
      ],
    );
    if (sortKey == null) {
      return Expanded(flex: flex, child: child);
    }
    return Expanded(
      flex: flex,
      child: InkWell(
        onTap: () => setState(() {
          if (_sortKey == sortKey) {
            _sortAsc = !_sortAsc;
          } else {
            _sortKey = sortKey;
            _sortAsc = false;
          }
        }),
        child: child,
      ),
    );
  }

  Widget _buildRow(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
    NumberFormat moeda,
    DateFormat fmtData,
    String uidLoja,
    Map<String, dynamic>? dadosLoja,
  ) {
    final d = doc.data();
    final status = d['status']?.toString() ?? _kPendente;
    final ts = d['data_pedido'];
    final dataStr = ts is Timestamp ? fmtData.format(ts.toDate()) : '—';
    final total = _num(d['total']);
    final forma = d['forma_pagamento']?.toString() ?? '—';
    final isRetirada = d['tipo_entrega']?.toString() == 'retirada';
    final prazo = d['prazo_estimado']?.toString() ?? '20-30 min';
    final cid = d['cliente_id']?.toString() ?? '';
    final nomeCliente = _nomesCliente[cid] ?? 'Cliente';
    final codigo = CodigoPedido.exibir(doc.id, d);

    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: () => _abrirDetalhe(doc.id, nomeCliente, uidLoja, dadosLoja),
        hoverColor: const Color(0xFFF9FAFB),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              // Pedido
              Expanded(
                flex: 20,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(codigo,
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1A1A2E))),
                    const SizedBox(height: 2),
                    Text(dataStr,
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey.shade500)),
                  ],
                ),
              ),
              // Cliente
              Expanded(
                flex: 22,
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 15,
                      backgroundColor: _roxo.withValues(alpha: 0.1),
                      child: Text(
                        nomeCliente.isNotEmpty
                            ? nomeCliente[0].toUpperCase()
                            : '?',
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: _roxo),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(nomeCliente,
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis),
                    ),
                  ],
                ),
              ),
              // Status
              Expanded(flex: 16, child: _statusBadge(status)),
              // Etapa
              Expanded(flex: 16, child: _stepperEtapa(_getEtapa(status))),
              // Pagamento
              Expanded(flex: 13, child: _pagamentoBadge(forma)),
              // Entrega
              Expanded(
                flex: 13,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                            isRetirada
                                ? Icons.storefront_outlined
                                : Icons.delivery_dining,
                            size: 16,
                            color: isRetirada ? _laranja : _roxo),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(isRetirada ? 'Retirada' : 'Entrega',
                              style: TextStyle(
                                  fontSize: 12, color: Colors.grey.shade700),
                              overflow: TextOverflow.ellipsis),
                        ),
                      ],
                    ),
                    if (!isRetirada)
                      Text(prazo,
                          style: TextStyle(
                              fontSize: 11, color: Colors.grey.shade500)),
                  ],
                ),
              ),
              // Total
              Expanded(
                flex: 12,
                child: Text(moeda.format(total),
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: _laranja)),
              ),
              // Ações
              SizedBox(
                width: 44,
                child: _buildActionsMenu(doc, status, uidLoja, dadosLoja),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusBadge(String status) {
    final cor = _corStatus(status);
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: cor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          _labelStatus(status),
          style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w700, color: cor),
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
        ),
      ),
    );
  }

  Widget _stepperEtapa(int etapaAtual) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = 1; i <= 4; i++) ...[
          if (i > 1)
            Container(
              width: 10,
              height: 2,
              color: i <= etapaAtual ? _roxo : Colors.grey.shade300,
            ),
          Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              color: i <= etapaAtual ? _roxo : Colors.grey.shade200,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: i < etapaAtual
                  ? const Icon(Icons.check, size: 11, color: Colors.white)
                  : Text(
                      '$i',
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: i <= etapaAtual
                              ? Colors.white
                              : Colors.grey.shade500),
                    ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _pagamentoBadge(String forma) {
    IconData icon;
    Color cor;
    String label;
    switch (forma.toLowerCase()) {
      case 'pix':
        icon = Icons.pix;
        cor = const Color(0xFF0F9D8C);
        label = 'PIX';
        break;
      case 'credito':
      case 'cartao_credito':
        icon = Icons.credit_card;
        cor = Colors.blue.shade700;
        label = 'Crédito';
        break;
      case 'debito':
      case 'cartao_debito':
        icon = Icons.credit_card_outlined;
        cor = Colors.indigo;
        label = 'Débito';
        break;
      case 'dinheiro':
        icon = Icons.payments_outlined;
        cor = Colors.green.shade700;
        label = 'Dinheiro';
        break;
      case 'vale':
        icon = Icons.card_giftcard;
        cor = Colors.deepPurple;
        label = 'Vale';
        break;
      default:
        icon = Icons.payments_outlined;
        cor = Colors.grey.shade600;
        label = forma.isEmpty ? '—' : forma;
    }
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
            color: cor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: cor),
            const SizedBox(width: 4),
            Flexible(
              child: Text(label,
                  style: TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w600, color: cor),
                  overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Cards (mobile/tablet)
  // ---------------------------------------------------------------------------
  Widget _buildCards(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    NumberFormat moeda,
    DateFormat fmtData,
    String uidLoja,
    Map<String, dynamic>? dadosLoja,
  ) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: docs.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, i) =>
          _buildCard(docs[i], moeda, fmtData, uidLoja, dadosLoja),
    );
  }

  Widget _buildCard(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
    NumberFormat moeda,
    DateFormat fmtData,
    String uidLoja,
    Map<String, dynamic>? dadosLoja,
  ) {
    final d = doc.data();
    final status = d['status']?.toString() ?? _kPendente;
    final ts = d['data_pedido'];
    final dataStr = ts is Timestamp ? fmtData.format(ts.toDate()) : '—';
    final total = _num(d['total']);
    final forma = d['forma_pagamento']?.toString() ?? '—';
    final isRetirada = d['tipo_entrega']?.toString() == 'retirada';
    final prazo = d['prazo_estimado']?.toString() ?? '20-30 min';
    final cid = d['cliente_id']?.toString() ?? '';
    final nomeCliente = _nomesCliente[cid] ?? 'Cliente';
    final codigo = CodigoPedido.exibir(doc.id, d);

    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: InkWell(
        onTap: () => _abrirDetalhe(doc.id, nomeCliente, uidLoja, dadosLoja),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: _roxo.withValues(alpha: 0.1),
                    child: Text(
                        nomeCliente.isNotEmpty
                            ? nomeCliente[0].toUpperCase()
                            : '?',
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: _roxo)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(nomeCliente,
                            style: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w700),
                            overflow: TextOverflow.ellipsis),
                        Text('$codigo • $dataStr',
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey.shade500)),
                      ],
                    ),
                  ),
                  _buildActionsMenu(doc, status, uidLoja, dadosLoja),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _statusBadge(status),
                  const Spacer(),
                  Text(moeda.format(total),
                      style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: _laranja)),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  _pagamentoBadge(forma),
                  const SizedBox(width: 8),
                  Icon(
                      isRetirada
                          ? Icons.storefront_outlined
                          : Icons.delivery_dining,
                      size: 15,
                      color: Colors.grey.shade500),
                  const SizedBox(width: 4),
                  Text(isRetirada ? 'Retirada' : prazo,
                      style: TextStyle(
                          fontSize: 12, color: Colors.grey.shade600)),
                  const Spacer(),
                  _stepperEtapa(_getEtapa(status)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Menu de ações (visibilidade por status)
  // ---------------------------------------------------------------------------
  Widget _buildActionsMenu(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
    String status,
    String uidLoja,
    Map<String, dynamic>? dadosLoja,
  ) {
    final d = doc.data();
    final isRetirada = d['tipo_entrega']?.toString() == 'retirada';
    final temTelefone =
        (d['cliente_telefone'] ?? d['cliente_fone'] ?? '').toString().trim().isNotEmpty;
    // Pagamento ainda não identificado: lojista não pode aceitar.
    final isAguardandoPagamento = status == _kAguardandoPagamento;
    // Pagamento confirmado e pedido novo para a loja.
    final isNovo = status == _kPendente || status == _kNovo;

    final items = <PopupMenuEntry<String>>[
      _menuItem('detalhes', Icons.visibility_outlined, 'Ver detalhes'),
    ];

    if (isAguardandoPagamento) {
      // Apenas "Ver detalhes" (acima) e "Cancelar pedido" (abaixo).
      // "Aceitar pedido" só aparece após a confirmação do pagamento.
    } else if (isNovo) {
      items.add(_menuItem(
          'aceitar', Icons.check_circle_outline, 'Aceitar pedido',
          cor: Colors.green.shade700));
    } else {
      if (status == _kAceito) {
        items.add(_menuItem('preparo', Icons.restaurant_outlined,
            'Iniciar preparo',
            cor: _laranja));
      } else if (status == _kEmPreparo || status == _kPreparando) {
        if (isRetirada) {
          items.add(_menuItem('pronto', Icons.inventory_2_outlined,
              'Marcar como pronto',
              cor: _roxo));
        } else {
          items.add(_menuItem('chamar_entregador', Icons.delivery_dining,
              'Chamar entregador',
              cor: const Color(0xFF0891B2)));
        }
      } else if (status == _kPronto) {
        if (isRetirada) {
          items.add(_menuItem('confirmar_entrega',
              Icons.task_alt_outlined, 'Confirmar entrega',
              cor: Colors.green.shade700));
        } else {
          items.add(_menuItem('acompanhar', Icons.delivery_dining,
              'Acompanhar entregador',
              cor: const Color(0xFF0891B2)));
        }
      } else if (status == _kAguardandoEntregador ||
          status == _kEntregadorIndoLoja ||
          status == _kSaiuEntrega ||
          status == _kEmRota ||
          status == _kACaminho) {
        if (!isRetirada) {
          items.add(_menuItem('acompanhar', Icons.delivery_dining,
              'Acompanhar entregador',
              cor: const Color(0xFF0891B2)));
        }
      }

      if (status != _kCancelado) {
        items.add(_menuItem('imprimir', Icons.print_outlined, 'Imprimir pedido'));
        if (temTelefone) {
          items.add(_menuItem(
              'contato', Icons.chat_outlined, 'Entrar em contato'));
        }
      }
    }

    if (_podeLojistaCancelarPedido(status, d)) {
      items.add(const PopupMenuDivider());
      items.add(_menuItem('cancelar', Icons.cancel_outlined, 'Cancelar pedido',
          cor: Colors.red.shade700));
    }

    return PopupMenuButton<String>(
      icon: Icon(Icons.more_vert, color: Colors.grey.shade600, size: 20),
      tooltip: 'Ações',
      position: PopupMenuPosition.under,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      itemBuilder: (_) => items,
      onSelected: (v) => _handleAction(v, doc, uidLoja, dadosLoja),
    );
  }

  PopupMenuItem<String> _menuItem(String value, IconData icon, String label,
      {Color? cor}) {
    return PopupMenuItem<String>(
      value: value,
      height: 44,
      child: Row(
        children: [
          Icon(icon, size: 18, color: cor ?? Colors.grey.shade700),
          const SizedBox(width: 12),
          Text(label,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: cor ?? const Color(0xFF1A1A2E))),
        ],
      ),
    );
  }

  void _handleAction(
    String action,
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
    String uidLoja,
    Map<String, dynamic>? dadosLoja,
  ) {
    final id = doc.id;
    final d = doc.data();
    final cid = d['cliente_id']?.toString() ?? '';
    final nomeCliente = _nomesCliente[cid] ?? 'Cliente';

    switch (action) {
      case 'detalhes':
        _abrirDetalhe(id, nomeCliente, uidLoja, dadosLoja);
        break;
      case 'aceitar':
        _confirmarEAgir(
          titulo: 'Aceitar pedido?',
          mensagem: 'Deseja aceitar este pedido e iniciar o atendimento?',
          icone: Icons.check_circle_outline,
          cor: Colors.green.shade700,
          acao: () => _acaoAceitarPedido(id),
        );
        break;
      case 'preparo':
        _confirmarEAgir(
          titulo: 'Iniciar preparo?',
          mensagem: 'Confirma que deseja iniciar o preparo deste pedido?',
          icone: Icons.restaurant_outlined,
          cor: _laranja,
          acao: () => _acaoIniciarPreparo(id),
        );
        break;
      case 'pronto':
        _acaoMarcarPronto(id);
        break;
      case 'chamar_entregador':
        _confirmarEAgir(
          titulo: 'Chamar entregador?',
          mensagem:
              'Será criada uma solicitação de entrega e os entregadores '
              'serão notificados. Deseja continuar?',
          icone: Icons.delivery_dining,
          cor: const Color(0xFF0891B2),
          acao: () => _acaoChamarEntregador(id, uidLoja, nomeCliente),
        );
        break;
      case 'acompanhar':
        _acaoAcompanharEntregador(id, uidLoja, nomeCliente);
        break;
      case 'confirmar_entrega':
        _acaoConfirmarEntregaRetirada(id);
        break;
      case 'imprimir':
        _confirmarEAgir(
          titulo: 'Imprimir pedido?',
          mensagem: 'Deseja gerar a impressão deste pedido?',
          icone: Icons.print_outlined,
          cor: _roxo,
          acao: () => _imprimirPedido(id, d, dadosLoja, nomeCliente),
        );
        break;
      case 'contato':
        _entrarEmContato(d);
        break;
      case 'cancelar':
        _acaoCancelar(id, d);
        break;
    }
  }

  // ---------------------------------------------------------------------------
  // Handlers do fluxo
  // ---------------------------------------------------------------------------
  /// Exibe um diálogo de confirmação (Sim/Não) e só executa [acao] no "Sim".
  Future<void> _confirmarEAgir({
    required String titulo,
    required String mensagem,
    required Future<void> Function() acao,
    IconData? icone,
    Color? cor,
  }) async {
    final ok = await showDialog<bool>(
      context: _ctxDialogo,
      useRootNavigator: true,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    if (icone != null) ...[
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: (cor ?? _roxo).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(icone, color: cor ?? _roxo, size: 22),
                      ),
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      child: Text(
                        titulo,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1A1A2E),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  mensagem,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.45,
                    color: Colors.grey.shade700,
                  ),
                ),
                const SizedBox(height: 22),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Não'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: cor ?? _roxo,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Sim'),
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
    if (ok == true) {
      await acao();
    }
  }

  Future<void> _atualizarStatus(String pedidoId, String novoStatus) async {
    await FirebaseFirestore.instance
        .collection('pedidos')
        .doc(pedidoId)
        .update({'status': novoStatus});
  }

  Future<void> _executar(Future<void> Function() op) async {
    if (_ocupado) return;
    _ocupado = true;
    try {
      await op();
    } finally {
      _ocupado = false;
    }
  }

  Future<void> _acaoAceitarPedido(String pedidoId) => _executar(() async {
        try {
          await _atualizarStatus(pedidoId, _kAceito);
          _snack('Pedido aceito com sucesso!');
        } catch (e) {
          _snack('Erro ao aceitar: $e', ok: false);
        }
      });

  Future<void> _acaoIniciarPreparo(String pedidoId) => _executar(() async {
        try {
          await _atualizarStatus(pedidoId, _kEmPreparo);
          _snack('Preparo iniciado.');
        } catch (e) {
          _snack('Erro ao iniciar preparo: $e', ok: false);
        }
      });

  Future<void> _acaoMarcarPronto(String pedidoId) => _executar(() async {
        try {
          await _atualizarStatus(pedidoId, _kPronto);
          _snack('Pedido pronto para retirada.');
        } catch (e) {
          _snack('Erro: $e', ok: false);
        }
      });

  /// Lê os tipos de entrega aceitos pela loja (lojas_public → users).
  Future<List<String>> _tiposAceitosLoja(String uidLoja) async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? uidLoja;
    try {
      final pub = await FirebaseFirestore.instance
          .collection('lojas_public')
          .doc(uid)
          .get();
      final tiposPub = TiposEntrega.lerDeDoc(pub.data());
      if (tiposPub.isNotEmpty) return tiposPub;
    } catch (_) {/* ignora */}
    try {
      final priv =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();
      return TiposEntrega.lerDeDoc(priv.data());
    } catch (_) {
      return const <String>[];
    }
  }

  /// "Chamar entregador" — reaproveita a rotina de despacho existente:
  /// escolhe categoria → `lojistaSolicitarDespachoEntregador` → modal de
  /// acompanhamento. O backend coloca o pedido em `aguardando_entregador`.
  Future<void> _acaoChamarEntregador(
    String pedidoId,
    String uidLoja,
    String nomeCliente,
  ) =>
      _executar(() async {
        try {
          final snap = await FirebaseFirestore.instance
              .collection('pedidos')
              .doc(pedidoId)
              .get();
          if (!snap.exists || !mounted) return;
          final d = snap.data()!;
          final taxa = _num(d['taxa_entrega']);

          final aceitos = await _tiposAceitosLoja(uidLoja);
          String? tipo;
          if (aceitos.length == 1) {
            tipo = aceitos.first;
          } else if (aceitos.length > 1) {
            if (!mounted) return;
            tipo = await EscolherTipoEntregaDialog.mostrar(
              context,
              tiposDisponiveis: aceitos,
            );
            if (tipo == null) return; // cancelou
          }

          if (!mounted) return;
          // Abre o modal de acompanhamento IMEDIATAMENTE. O próprio modal faz a
          // solicitação de despacho (`jaSolicitou: false`) usando a categoria
          // escolhida, exibindo "Procurando..." ou o card de erro — assim o
          // modal sempre aparece ao clicar em "Chamar entregador".
          await ChamarEntregadorModal.mostrar(
            context: context,
            pedidoId: pedidoId,
            uidLoja: uidLoja,
            nomeCliente: nomeCliente,
            tipoEntrega: tipo == null ? 'Entrega' : TiposEntrega.rotulo(tipo),
            valorCorrida: taxa > 0 ? taxa : null,
            onCancelar: () => _snack('Solicitação cancelada.'),
            onConcluir: () => _snack('Pedido entregue com sucesso!'),
            jaSolicitou: false,
            tipoSolicitado: tipo,
          );
        } catch (e) {
          _snack('Erro ao chamar entregador: $e', ok: false);
        }
      });

  /// Reabre o modal de acompanhamento (já solicitado anteriormente).
  Future<void> _acaoAcompanharEntregador(
    String pedidoId,
    String uidLoja,
    String nomeCliente,
  ) =>
      _executar(() async {
        final snap = await FirebaseFirestore.instance
            .collection('pedidos')
            .doc(pedidoId)
            .get();
        if (!snap.exists || !mounted) return;
        final d = snap.data()!;
        final taxa = _num(d['taxa_entrega']);
        await ChamarEntregadorModal.mostrar(
          context: context,
          pedidoId: pedidoId,
          uidLoja: uidLoja,
          nomeCliente: nomeCliente,
          tipoEntrega: 'Entrega',
          valorCorrida: taxa > 0 ? taxa : null,
          onCancelar: () => _snack('Solicitação cancelada.'),
          onConcluir: () => _snack('Pedido entregue com sucesso!'),
          jaSolicitou: true,
        );
      });

  /// Confirmação de entrega APENAS para "retirada no balcão".
  /// Usa a callable `lojistaConfirmarRetiradaBalcao` (a rule do Firestore
  /// bloqueia o lojista de gravar `entregue` direto).
  Future<void> _acaoConfirmarEntregaRetirada(String pedidoId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Confirmar entrega?'),
        content: const Text(
            'Confirmar que o cliente retirou o pedido? O pedido será finalizado como "Entregue".'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Confirmar')),
        ],
      ),
    );
    if (ok != true) return;

    await _executar(() async {
      try {
        await callFirebaseFunctionSafe(
          'lojistaConfirmarRetiradaBalcao',
          parameters: <String, dynamic>{'pedidoId': pedidoId},
        );
        _snack('Entrega confirmada! Pedido concluído.');
      } on CallableHttpException catch (e) {
        _snack(mensagemCallableHttpException(e), ok: false);
      } catch (e) {
        _snack('Erro ao confirmar entrega: $e', ok: false);
      }
    });
  }

  /// Lojista pode cancelar antes de chamar entregador (entrega ou retirada).
  bool _podeLojistaCancelarPedido(String status, Map<String, dynamic> d) {
    if (status == _kCancelado || status == _kEntregue) return false;
    final entregadorId = d['entregador_id']?.toString().trim() ?? '';
    if (entregadorId.isNotEmpty) return false;
    const posDespacho = {
      _kAguardandoEntregador,
      _kEntregadorIndoLoja,
      _kSaiuEntrega,
      _kEmRota,
      _kACaminho,
    };
    if (posDespacho.contains(status)) return false;
    if (status == _kPronto && d['tipo_entrega']?.toString() != 'retirada') {
      return false;
    }
    return true;
  }

  /// PIX/cartão confirmados exigem estorno via gateway (callable existente).
  bool _exigeEstornoAoCancelar(Map<String, dynamic> d, String status) {
    if (status == _kAguardandoPagamento) return false;
    final mp = d['mp_payment_id']?.toString().trim() ?? '';
    if (mp.isNotEmpty) return true;
    final fp = (d['forma_pagamento'] ?? d['metodo_pagamento'] ?? '')
        .toString()
        .toLowerCase();
    return fp.contains('pix') ||
        fp.contains('cart') ||
        fp.contains('credito') ||
        fp.contains('crédito') ||
        fp.contains('debito') ||
        fp.contains('débito');
  }

  Future<({String motivo, String? observacao})?> _mostrarDialogoCancelarPedido({
    required bool exigeEstorno,
  }) async {
    final motivos = const [
      'Produto indisponível',
      'Loja não consegue preparar',
      'Erro no pedido',
      'Cliente solicitou',
      'Outro',
    ];
    var motivoSel = motivos.first;
    final obsC = TextEditingController();

    final ok = await showDialog<bool>(
      context: _ctxDialogo,
      useRootNavigator: true,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => Dialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(Icons.cancel_outlined,
                            color: Colors.red.shade700, size: 24),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Cancelar pedido',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1A1A2E),
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Fechar',
                        onPressed: () => Navigator.pop(ctx, false),
                        icon: const Icon(Icons.close, size: 20),
                        color: Colors.grey.shade500,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: exigeEstorno
                          ? Colors.amber.shade50
                          : Colors.red.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: exigeEstorno
                            ? Colors.amber.shade200
                            : Colors.red.shade100,
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          exigeEstorno
                              ? Icons.info_outline
                              : Icons.warning_amber_rounded,
                          size: 20,
                          color: exigeEstorno
                              ? Colors.amber.shade800
                              : Colors.red.shade700,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            exigeEstorno
                                ? 'Tem certeza que deseja cancelar este pedido? Como o pagamento já foi confirmado, será solicitado o estorno automático ao cliente.'
                                : 'Tem certeza que deseja cancelar este pedido? Esta ação não pode ser desfeita.',
                            style: TextStyle(
                              fontSize: 13.5,
                              height: 1.45,
                              color: Colors.grey.shade800,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'Motivo do cancelamento',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  ...motivos.map(
                    (m) => RadioListTile<String>(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(m, style: const TextStyle(fontSize: 13)),
                      value: m,
                      groupValue: motivoSel,
                      activeColor: _roxo,
                      onChanged: (v) {
                        if (v != null) setLocal(() => motivoSel = v);
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: obsC,
                    maxLines: 3,
                    decoration: InputDecoration(
                      labelText: 'Observação (opcional)',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      filled: true,
                      fillColor: const Color(0xFFF4F5F7),
                    ),
                  ),
                  const SizedBox(height: 22),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Voltar'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.red.shade700,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          onPressed: () => Navigator.pop(ctx, true),
                          child: Text(
                            exigeEstorno
                                ? 'Confirmar cancelamento e estorno'
                                : 'Confirmar cancelamento',
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

    if (ok != true) {
      obsC.dispose();
      return null;
    }
    final obs = obsC.text.trim();
    obsC.dispose();
    return (motivo: motivoSel, observacao: obs.isEmpty ? null : obs);
  }

  Future<void> _acaoCancelar(
    String pedidoId,
    Map<String, dynamic> pedido,
  ) async {
    final status = pedido['status']?.toString() ?? _kPendente;
    if (!_podeLojistaCancelarPedido(status, pedido)) {
      await _mostrarDialogoFeedback(
        titulo: 'Cancelamento indisponível',
        mensagem: 'Este pedido não pode ser cancelado nesta etapa.',
        sucesso: false,
      );
      return;
    }

    final exigeEstorno = _exigeEstornoAoCancelar(pedido, status);
    final dados = await _mostrarDialogoCancelarPedido(exigeEstorno: exigeEstorno);
    if (dados == null) return;

    await _executar(() async {
      try {
        if (exigeEstorno) {
          final resp = await callFirebaseFunctionSafe(
            'lojistaCancelarPedidoComEstorno',
            parameters: <String, dynamic>{
              'pedidoId': pedidoId,
              'motivo': dados.motivo,
              if (dados.observacao != null) 'observacao': dados.observacao,
            },
          );
          final msg = resp['mensagem']?.toString();
          await _mostrarDialogoFeedback(
            titulo: 'Pedido cancelado',
            mensagem: msg ??
                (resp['estornoProcessado'] == true
                    ? 'Pedido cancelado e estorno solicitado ao cliente.'
                    : 'Pedido cancelado. Estorno em processamento.'),
            sucesso: true,
          );
        } else {
          await FirebaseFirestore.instance
              .collection('pedidos')
              .doc(pedidoId)
              .update({
            'status': _kCancelado,
            'cancelado_motivo': PedidoStatusWeb.canceladoMotivoLojistaRecusou,
            'cancelado_em': FieldValue.serverTimestamp(),
          });
          await _mostrarDialogoFeedback(
            titulo: 'Pedido cancelado',
            mensagem: 'O pedido foi cancelado com sucesso.',
            sucesso: true,
          );
        }
      } on CallableHttpException catch (e) {
        await _mostrarDialogoFeedback(
          titulo: 'Não foi possível cancelar',
          mensagem: mensagemCallableHttpException(e),
          sucesso: false,
        );
      } catch (e) {
        await _mostrarDialogoFeedback(
          titulo: 'Erro ao cancelar',
          mensagem: e.toString(),
          sucesso: false,
        );
      }
    });
  }

  Future<void> _imprimirPedido(
    String pedidoId,
    Map<String, dynamic> pedido,
    Map<String, dynamic>? dadosLoja,
    String nomeCliente,
  ) async {
    try {
      await PedidoReciboPdf.imprimir(
        pedidoId: pedidoId,
        codigoPedido: CodigoPedido.exibir(pedidoId, pedido),
        pedido: pedido,
        dadosLoja: dadosLoja,
        nomeClienteFallback: nomeCliente,
      );
    } catch (e) {
      _snack('Erro ao imprimir: $e', ok: false);
    }
  }

  Future<void> _entrarEmContato(Map<String, dynamic> pedido) async {
    final telefone =
        (pedido['cliente_telefone'] ?? pedido['cliente_fone'] ?? '')
            .toString()
            .replaceAll(RegExp(r'\D'), '');
    if (telefone.isEmpty) {
      _snack('Telefone do cliente não disponível.', ok: false);
      return;
    }
    final numero = telefone.startsWith('55') ? telefone : '55$telefone';
    final uri = Uri.parse('https://wa.me/$numero');
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok) _snack('Não foi possível abrir o WhatsApp.', ok: false);
    } catch (_) {
      _snack('Não foi possível abrir o contato.', ok: false);
    }
  }

  // ---------------------------------------------------------------------------
  // Modal de detalhes
  // ---------------------------------------------------------------------------
  void _abrirDetalhe(
    String pedidoId,
    String nomeCliente,
    String uidLoja,
    Map<String, dynamic>? dadosLoja,
  ) {
    showDialog<void>(
      context: context,
      builder: (ctx) => _PedidoDetalheDialog(
        pedidoId: pedidoId,
        nomeClienteFallback: nomeCliente,
        labelStatus: _labelStatus,
        corStatus: _corStatus,
        onImprimir: (d) =>
            _imprimirPedido(pedidoId, d, dadosLoja, nomeCliente),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Exportar CSV
  // ---------------------------------------------------------------------------
  Future<void> _exportarCsv(String uidLoja) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('pedidos')
          .where('loja_id', isEqualTo: uidLoja)
          .get();
      final fmt = DateFormat('dd/MM/yyyy HH:mm');
      final linhas = <List<Object?>>[];
      final docs = snap.docs.where((doc) {
        final d = doc.data();
        if (!PedidoStatusWeb.visivelNaListaLojista(d)) return false;
        final st = d['status']?.toString() ?? _kPendente;
        if (!_passaFiltro(st)) return false;
        final ts = d['data_pedido'];
        return _passaPeriodo(ts is Timestamp ? ts : null);
      }).toList();

      for (final doc in docs) {
        final d = doc.data();
        final ts = d['data_pedido'];
        final cid = d['cliente_id']?.toString() ?? '';
        linhas.add([
          CodigoPedido.exibir(doc.id, d),
          ts is Timestamp ? fmt.format(ts.toDate()) : '',
          (d['cliente_nome'] ?? _nomesCliente[cid] ?? '').toString(),
          _labelStatus(d['status']?.toString() ?? ''),
          (d['forma_pagamento'] ?? '').toString(),
          d['tipo_entrega']?.toString() == 'retirada' ? 'Retirada' : 'Entrega',
          _num(d['total']).toStringAsFixed(2),
        ]);
      }

      exportarCsv(
        cabecalho: const [
          'Pedido',
          'Data',
          'Cliente',
          'Status',
          'Pagamento',
          'Entrega',
          'Total',
        ],
        linhas: linhas,
        filename:
            'pedidos_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.csv',
      );
      _snack('Exportados ${linhas.length} pedidos.');
    } catch (e) {
      _snack('Erro ao exportar: $e', ok: false);
    }
  }
}

// =============================================================================
// Modal de detalhes do pedido (live via StreamBuilder)
// =============================================================================
class _PedidoDetalheDialog extends StatelessWidget {
  const _PedidoDetalheDialog({
    required this.pedidoId,
    required this.nomeClienteFallback,
    required this.labelStatus,
    required this.corStatus,
    required this.onImprimir,
  });

  final String pedidoId;
  final String nomeClienteFallback;
  final String Function(String) labelStatus;
  final Color Function(String) corStatus;
  final void Function(Map<String, dynamic>) onImprimir;

  static const _roxo = PainelAdminTheme.roxo;

  double _num(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }

  String _formaPagamento(String forma) {
    switch (forma.toLowerCase()) {
      case 'pix':
        return 'PIX';
      case 'credito':
      case 'cartao_credito':
        return 'Cartão de Crédito';
      case 'debito':
      case 'cartao_debito':
        return 'Cartão de Débito';
      case 'dinheiro':
        return 'Dinheiro';
      default:
        return forma.isEmpty ? '—' : forma;
    }
  }

  @override
  Widget build(BuildContext context) {
    final moeda = NumberFormat.currency(locale: 'pt_BR', symbol: r'R$');
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 580, maxHeight: 720),
        child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('pedidos')
              .doc(pedidoId)
              .snapshots(),
          builder: (context, snap) {
            if (!snap.hasData) {
              return const SizedBox(
                height: 200,
                child: Center(child: CircularProgressIndicator(color: _roxo)),
              );
            }
            if (!snap.data!.exists) {
              return const SizedBox(
                height: 200,
                child: Center(child: Text('Pedido não encontrado.')),
              );
            }
            final d = snap.data!.data()!;
            final status = d['status']?.toString() ?? 'pendente';
            final ts = d['data_pedido'];
            final dataStr = ts is Timestamp
                ? DateFormat('dd/MM/yyyy • HH:mm').format(ts.toDate())
                : '—';
            final isRetirada = d['tipo_entrega']?.toString() == 'retirada';
            final itens = d['itens'] as List? ?? [];
            final sub = _num(d['subtotal']);
            final taxa = _num(d['taxa_entrega']);
            final desc = _num(d['desconto_saldo']) +
                _num(d['desconto_cupom']) +
                _num(d['desconto']);
            final total = _num(d['total']);
            final forma = _formaPagamento(d['forma_pagamento']?.toString() ?? '');
            final endereco = d['endereco_entrega']?.toString() ?? '—';
            final nomeCliente = (d['cliente_nome'] ?? '').toString().isNotEmpty
                ? d['cliente_nome'].toString()
                : nomeClienteFallback;
            final telefone =
                (d['cliente_telefone'] ?? d['cliente_fone'] ?? '—').toString();
            final obs = d['observacao']?.toString() ?? '';
            final entregadorNome = d['entregador_nome']?.toString() ?? '';
            final cor = corStatus(status);
            final codigo = CodigoPedido.exibir(pedidoId, d);

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header fixo
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 16, 0),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                            color: cor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12)),
                        child: Icon(Icons.receipt_long, color: cor, size: 26),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(codigo,
                                style: const TextStyle(
                                    fontSize: 19,
                                    fontWeight: FontWeight.w800)),
                            Text(dataStr,
                                style: TextStyle(
                                    fontSize: 13, color: Colors.grey.shade600)),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                            color: cor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(20)),
                        child: Text(labelStatus(status),
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: cor)),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 24),
                // Conteúdo rolável
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _secao('Dados do Cliente'),
                        _linha(Icons.person_outline, 'Nome', nomeCliente),
                        _linha(Icons.phone_outlined, 'Telefone', telefone),
                        if (!isRetirada)
                          _linha(Icons.location_on_outlined, 'Endereço',
                              endereco),
                        if (obs.isNotEmpty)
                          _linha(Icons.sticky_note_2_outlined, 'Observações',
                              obs),
                        const SizedBox(height: 18),
                        _secao('Produtos (${itens.length})'),
                        ...itens.map((raw) {
                          if (raw is! Map) return const SizedBox();
                          final m = Map<String, dynamic>.from(raw);
                          final qRaw = m['quantidade'] ?? 1;
                          final qn = qRaw is num
                              ? qRaw.toDouble()
                              : double.tryParse('$qRaw') ?? 1;
                          final qDisp = (qn - qn.round()).abs() < 0.001
                              ? qn.round().toString()
                              : qn.toStringAsFixed(1);
                          final nome = m['nome']?.toString() ?? '?';
                          final pu = _num(
                              m['preco'] ?? m['preco_unitario'] ?? m['valor']);
                          final comps =
                              (m['complementos'] ?? m['complemento'] ?? '')
                                  .toString();
                          final obsItem =
                              (m['observacao'] ?? m['obs'] ?? '').toString();
                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                                color: Colors.grey.shade50,
                                borderRadius: BorderRadius.circular(10)),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text('${qDisp}x',
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w800,
                                            color: _roxo)),
                                    const SizedBox(width: 8),
                                    Expanded(
                                        child: Text(nome,
                                            style: const TextStyle(
                                                fontWeight: FontWeight.w600))),
                                    Text(moeda.format(pu * qn),
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w700)),
                                  ],
                                ),
                                if (comps.trim().isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(comps,
                                        style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey.shade600)),
                                  ),
                                if (obsItem.trim().isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text('Obs: $obsItem',
                                        style: TextStyle(
                                            fontSize: 12,
                                            fontStyle: FontStyle.italic,
                                            color: Colors.grey.shade600)),
                                  ),
                              ],
                            ),
                          );
                        }),
                        const SizedBox(height: 10),
                        _secao('Resumo Financeiro'),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                              color: Colors.grey.shade50,
                              borderRadius: BorderRadius.circular(12)),
                          child: Column(
                            children: [
                              _finance('Subtotal', moeda.format(sub)),
                              if (!isRetirada && taxa > 0)
                                _finance('Taxa de entrega', moeda.format(taxa)),
                              if (desc > 0)
                                _finance('Desconto', '- ${moeda.format(desc)}',
                                    cor: Colors.green.shade700),
                              const Divider(height: 20),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text('TOTAL',
                                      style: TextStyle(
                                          fontSize: 17,
                                          fontWeight: FontWeight.w800)),
                                  Text(moeda.format(total),
                                      style: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w800,
                                          color: Color(0xFFE65100))),
                                ],
                              ),
                              _finance('Forma de pagamento', forma),
                            ],
                          ),
                        ),
                        const SizedBox(height: 18),
                        _secao('Dados da Entrega'),
                        _linha(
                            isRetirada
                                ? Icons.storefront_outlined
                                : Icons.delivery_dining,
                            'Tipo',
                            isRetirada
                                ? 'Retirada no balcão'
                                : 'Entrega em domicílio'),
                        if (!isRetirada)
                          _linha(Icons.location_on_outlined, 'Endereço',
                              endereco),
                        if (entregadorNome.isNotEmpty)
                          _linha(Icons.sports_motorsports_outlined,
                              'Entregador', entregadorNome),
                      ],
                    ),
                  ),
                ),
                // Rodapé com ações
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => onImprimir(d),
                          icon: const Icon(Icons.print_outlined, size: 18),
                          label: const Text('Imprimir'),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            foregroundColor: _roxo,
                            side: const BorderSide(color: _roxo),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: () => Navigator.pop(context),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            backgroundColor: _roxo,
                          ),
                          child: const Text('Fechar'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _secao(String titulo) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(titulo,
            style: const TextStyle(
                fontSize: 14, fontWeight: FontWeight.w800, color: _roxo)),
      );

  Widget _linha(IconData icon, String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: Colors.grey.shade600),
            const SizedBox(width: 10),
            SizedBox(
                width: 90,
                child: Text('$label:',
                    style: TextStyle(
                        fontSize: 13, color: Colors.grey.shade600))),
            Expanded(
                child: SelectableText(value,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600))),
          ],
        ),
      );

  Widget _finance(String label, String value, {Color? cor}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style:
                    TextStyle(fontSize: 14, color: cor ?? Colors.grey.shade700)),
            Text(value,
                style: TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w600, color: cor)),
          ],
        ),
      );
}
