import 'dart:math' show min;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/painel_admin_theme.dart';
import '../utils/codigo_pedido.dart';

typedef _LinhaSecao = ({String label, String valor, String? copiar});

class MonitorPedidosScreen extends StatefulWidget {
  const MonitorPedidosScreen({super.key});

  @override
  State<MonitorPedidosScreen> createState() => _MonitorPedidosScreenState();
}

class _MonitorPedidosScreenState extends State<MonitorPedidosScreen> {
  static const _ink = Color(0xFF1E1B4B);
  static const _muted = Color(0xFF64748B);
  static const _border = Color(0xFFE2E8F0);
  static const _bg = Color(0xFFF8FAFC);
  static const int _kPedidosPorPaginaMonitor = 10;

  static const _todosStatus = [
    'aguardando_pagamento',
    'pendente',
    'aceito',
    'em_preparo',
    'aguardando_entregador',
    'entregador_indo_loja',
    'saiu_entrega',
    'em_rota',
    'a_caminho',
    'entregue',
    'cancelado',
  ];

  String _filtro = 'hoje';
  String _janela = '24h';
  final _buscaC = TextEditingController();
  int _paginaMonitor = 0;

  @override
  void dispose() {
    _buscaC.dispose();
    super.dispose();
  }

  static String _uidExibicao(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return '—';
    if (s.length <= 13) return s;
    return '${s.substring(0, 4)}…${s.substring(s.length - 4)}';
  }

  _LinhaSecao _campo(String label, String valor) =>
      (label: label, valor: valor, copiar: null);

  _LinhaSecao _campoUid(String label, String? uidRaw) {
    final full = (uidRaw ?? '').trim();
    if (full.isEmpty || full == '—') {
      return (label: label, valor: '—', copiar: null);
    }
    return (label: label, valor: _uidExibicao(full), copiar: full);
  }

  _LinhaSecao _campoIdFirestore(String label, String id) {
    final full = id.trim();
    if (full.isEmpty) {
      return (label: label, valor: '—', copiar: null);
    }
    return (label: label, valor: _uidExibicao(full), copiar: full);
  }

  void _copiarTexto(String texto) {
    Clipboard.setData(ClipboardData(text: texto));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Copiado para a área de transferência'),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 2),
      ),
    );
  }

  static DateTime? _paraDateTime(dynamic raw) {
    if (raw is Timestamp) return raw.toDate();
    return null;
  }

  /// Carimbo da Fase B: `operacao_status_em.{status}`.
  static DateTime? _timestampStatusMap(
    Map<String, dynamic> d,
    String statusKey,
  ) {
    final m = d['operacao_status_em'];
    if (m is! Map) return null;
    return _paraDateTime(m[statusKey]);
  }

  static String _duracaoLegivel(Duration diff) {
    if (diff.inSeconds < 0) return '—';
    final sec = diff.inSeconds;
    if (sec < 60) return '$sec s';
    final min = diff.inMinutes;
    if (min < 60) return '$min min';
    final h = diff.inHours;
    final m = diff.inMinutes.remainder(60);
    if (m == 0) return '$h h';
    return '$h h $m min';
  }

  static String? _deltaLegivel(DateTime? inicio, DateTime? fim) {
    if (inicio == null || fim == null) return null;
    final diff = fim.difference(inicio);
    if (diff.inSeconds < 0) return null;
    return _duracaoLegivel(diff);
  }

  /// Eventos com carimbo no Firestore (Fase A + mapa operacao_status_em — Fase B).
  List<({String label, DateTime t})> _eventosTimelineOperacional(
    Map<String, dynamic> d,
  ) {
    final eventos = <({String label, DateTime t})>[];

    final opMap = d['operacao_status_em'];
    if (opMap is Map) {
      for (final e in opMap.entries) {
        final dt = _paraDateTime(e.value);
        if (dt != null) {
          final sk = e.key.toString();
          eventos.add((label: 'Status: ${_labelStatus(sk)}', t: dt));
        }
      }
    }

    void adicionar(String label, dynamic raw) {
      final dt = _paraDateTime(raw);
      if (dt != null) eventos.add((label: label, t: dt));
    }

    adicionar('Pedido registrado', d['data_pedido']);
    adicionar('Tipo de entrega solicitado', d['tipo_entrega_solicitado_em']);
    adicionar('Início da busca por entregador', d['busca_entregador_inicio']);
    adicionar('Entregador aceitou a corrida', d['entregador_aceito_em']);

    final tok = _paraDateTime(d['entrega_token_validado_em']);
    final ent = _paraDateTime(d['data_entregue']);
    if (tok != null && ent != null) {
      final diffSec = (tok.difference(ent).inSeconds).abs();
      if (diffSec <= 2) {
        adicionar('Conclusão da entrega (código validado)', tok);
      } else {
        adicionar('Código de entrega validado', tok);
        adicionar('Registro data_entregue', ent);
      }
    } else if (tok != null) {
      adicionar('Conclusão da entrega (código validado)', tok);
    } else if (ent != null) {
      adicionar('Pedido marcado como entregue', ent);
    }

    eventos.sort((a, b) => a.t.compareTo(b.t));
    return eventos;
  }

  List<_LinhaSecao> _camposDuracaoDerivada(Map<String, dynamic> d) {
    final tPedido = _paraDateTime(d['data_pedido']);
    final tBusca = _paraDateTime(d['busca_entregador_inicio']);
    final tAceite = _paraDateTime(d['entregador_aceito_em']);
    final tok = _paraDateTime(d['entrega_token_validado_em']);
    final ent = _paraDateTime(d['data_entregue']);
    final tFim = tok ?? ent;

    final out = <_LinhaSecao>[];
    final buscaAceite = _deltaLegivel(tBusca, tAceite);
    if (buscaAceite != null) {
      out.add(_campo('Da busca ao aceite do entregador', buscaAceite));
    }

    final tIndoLoja = _timestampStatusMap(d, 'entregador_indo_loja');
    var tSaiuLoja = _timestampStatusMap(d, 'saiu_entrega');
    tSaiuLoja ??= _timestampStatusMap(d, 'em_rota');
    tSaiuLoja ??= _timestampStatusMap(d, 'a_caminho');
    final naLoja = _deltaLegivel(tIndoLoja, tSaiuLoja);
    if (naLoja != null) {
      out.add(_campo('Na loja (chegada → saiu com pedido)', naLoja));
    }

    final tPronto = _timestampStatusMap(d, 'pronto');
    final prontoBusca = _deltaLegivel(tPronto, tBusca);
    if (prontoBusca != null) {
      out.add(
        _campo('Do “pronto” ao início da busca de entregador', prontoBusca),
      );
    }

    final aceiteFim = _deltaLegivel(tAceite, tFim);
    if (aceiteFim != null) {
      out.add(_campo('Do aceite à conclusão da entrega', aceiteFim));
    }
    final pedidoFim = _deltaLegivel(tPedido, tFim);
    if (pedidoFim != null) {
      out.add(_campo('Do registro do pedido à conclusão', pedidoFim));
    }
    return out;
  }

  List<_LinhaSecao> _camposDespachoResumo(Map<String, dynamic> d) {
    final out = <_LinhaSecao>[];
    String? str(dynamic v) {
      final s = v?.toString().trim();
      if (s == null || s.isEmpty) return null;
      return s;
    }

    final est = str(d['despacho_oferta_estado']);
    if (est != null) out.add(_campo('Estado da oferta', est));

    final seq = d['despacho_oferta_seq'];
    if (seq != null && '$seq'.isNotEmpty && '$seq' != '0') {
      out.add(_campo('Sequência da oferta', '$seq'));
    }

    final rec = d['despacho_recusados'];
    if (rec is List && rec.isNotEmpty) {
      out.add(_campo('Recusas à oferta (qtd)', '${rec.length}'));
    }
    final bloq = d['despacho_bloqueados'];
    if (bloq is List && bloq.isNotEmpty) {
      out.add(_campo('Bloqueados na busca (qtd)', '${bloq.length}'));
    }
    final fila = d['despacho_fila_ids'];
    if (fila is List && fila.isNotEmpty) {
      out.add(_campo('Tamanho da fila (snapshot)', '${fila.length}'));
    }

    final raio = d['busca_raio_km'];
    if (raio != null && '$raio'.isNotEmpty) {
      out.add(_campo('Raio da busca (km)', '$raio'));
    }

    final macro = str(d['despacho_macro_ciclo_atual']);
    if (macro != null) out.add(_campo('Macro ciclo (despacho)', macro));

    final msg = str(d['despacho_msg_busca_entregador']);
    if (msg != null) out.add(_campo('Mensagem da busca', msg));

    final autoEnc = d['despacho_auto_encerrada_sem_entregador'];
    if (autoEnc == true) {
      out.add(_campo('Busca encerrada sem entregador', 'Sim'));
    }

    for (final e in [
      ('Redespacho pela loja', d['despacho_redespacho_loja_em']),
      ('Redespacho (entregador)', d['despacho_redespacho_entregador_em']),
    ]) {
      final dt = _paraDateTime(e.$2);
      if (dt != null) {
        out.add(_campo(e.$1, DateFormat('dd/MM/yyyy  HH:mm:ss').format(dt)));
      }
    }

    final tipo = str(d['tipo_entrega_solicitado']);
    if (tipo != null) {
      out.add(_campo('Tipo de entrega (valor no doc)', tipo));
    }
    return out;
  }

  Widget _secaoTimelineOperacional(List<({String label, DateTime t})> eventos) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.timeline_rounded,
              size: 18,
              color: PainelAdminTheme.roxo,
            ),
            const SizedBox(width: 8),
            const Text(
              'Linha do tempo operacional',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: _ink,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: _bg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _border),
          ),
          child: Column(
            children: [
              if (eventos.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(14),
                  child: Text(
                    'Nenhum carimbo além do necessário neste registro.',
                    style: TextStyle(
                      fontSize: 12,
                      color: _muted,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                )
              else
                for (int i = 0; i < eventos.length; i++) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Icon(
                            Icons.circle,
                            size: 8,
                            color: PainelAdminTheme.roxo,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                eventos[i].label,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: _ink,
                                  fontWeight: FontWeight.w700,
                                  height: 1.35,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                DateFormat(
                                  'dd/MM/yyyy  HH:mm:ss',
                                ).format(eventos[i].t),
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: _muted,
                                  fontWeight: FontWeight.w600,
                                  fontFeatures: [FontFeature.tabularFigures()],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (i < eventos.length - 1)
                    Divider(height: 1, color: _border.withValues(alpha: 0.6)),
                ],
            ],
          ),
        ),
      ],
    );
  }

  String _labelStatus(String s) => switch (s) {
    'aguardando_pagamento' => 'Aguard. pgto',
    'pendente' => 'Pendente',
    'encomenda_entrada_paga' => 'Enc. entrada paga',
    'aceito' => 'Aceito',
    'em_preparo' => 'Preparando',
    'aguardando_entregador' => 'Aguard. coleta',
    'entregador_indo_loja' => 'Em coleta',
    'saiu_entrega' || 'em_rota' || 'a_caminho' => 'Em rota',
    'entregue' => 'Entregue',
    'cancelado' => 'Cancelado',
    _ => s,
  };

  Color _corStatus(String s) => switch (s) {
    'aguardando_pagamento' => const Color(0xFF64748B),
    'pendente' => const Color(0xFFD97706),
    'encomenda_entrada_paga' => const Color(0xFFB7791F),
    'aceito' => const Color(0xFF2563EB),
    'em_preparo' => PainelAdminTheme.roxo,
    'aguardando_entregador' => const Color(0xFF0EA5E9),
    'entregador_indo_loja' => const Color(0xFF0891B2),
    'saiu_entrega' || 'em_rota' || 'a_caminho' => const Color(0xFF059669),
    'entregue' => const Color(0xFF16A34A),
    'cancelado' => const Color(0xFFDC2626),
    _ => _muted,
  };

  IconData _iconeStatus(String s) => switch (s) {
    'aguardando_pagamento' => Icons.payments_outlined,
    'pendente' => Icons.schedule_rounded,
    'encomenda_entrada_paga' => Icons.inventory_2_outlined,
    'aceito' => Icons.thumb_up_alt_outlined,
    'em_preparo' => Icons.restaurant_rounded,
    'aguardando_entregador' => Icons.inventory_2_outlined,
    'entregador_indo_loja' => Icons.directions_bike_outlined,
    'saiu_entrega' || 'em_rota' || 'a_caminho' => Icons.delivery_dining_rounded,
    'entregue' => Icons.check_circle_rounded,
    'cancelado' => Icons.cancel_rounded,
    _ => Icons.circle_outlined,
  };

  bool _isFinal(String s) => s == 'entregue' || s == 'cancelado';

  bool _passaFiltro(String s) {
    if (_filtro == 'hoje' || _filtro == 'todos') return true;
    if (_filtro == 'coleta') {
      return s == 'aguardando_entregador' || s == 'entregador_indo_loja';
    }
    if (_filtro == 'rota') {
      return s == 'saiu_entrega' || s == 'em_rota' || s == 'a_caminho';
    }
    return s == _filtro;
  }

  bool _passaFiltroHoje(Timestamp? ts) {
    if (_filtro != 'hoje') return true;
    if (ts == null) return false;
    final dt = ts.toDate();
    final agora = DateTime.now();
    return dt.year == agora.year &&
        dt.month == agora.month &&
        dt.day == agora.day;
  }

  bool _passaJanela(Timestamp? ts) {
    if (_janela == 'todos' || ts == null) return _janela == 'todos';
    final diff = DateTime.now().difference(ts.toDate());
    if (_janela == '24h') return diff.inHours <= 24;
    if (_janela == '7d') return diff.inDays <= 7;
    return true;
  }

  bool _passaBusca(QueryDocumentSnapshot doc, Map<String, dynamic> d) {
    final q = _buscaC.text.trim().toLowerCase();
    if (q.isEmpty) return true;
    return [
      doc.id,
      d['loja_nome'],
      d['cliente_nome'],
      d['cliente_id'],
      d['cidade'],
      d['forma_pagamento'],
      d['endereco_entrega'],
      d['entregador_nome'],
      d['entregador_id'],
      d['status'],
    ].map((v) => (v ?? '').toString().toLowerCase()).join(' ').contains(q);
  }

  int _contar(List<QueryDocumentSnapshot> docs, bool Function(String) test) =>
      docs
          .where(
            (d) => test(
              (d.data() as Map<String, dynamic>)['status']?.toString() ?? '',
            ),
          )
          .length;

  Widget _barraPaginacaoMonitor({
    required int total,
    required int paginaIdx,
    required int ultimoIndicePagina,
  }) {
    final inicio = paginaIdx * _kPedidosPorPaginaMonitor;
    final ultimoItem = total == 0
        ? 0
        : min(inicio + _kPedidosPorPaginaMonitor, total);
    final primeiroRotulo = total == 0 ? 0 : inicio + 1;

    return Material(
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: _border),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Text(
                total == 0
                    ? 'Nenhum pedido na página'
                    : 'Mostrando $primeiroRotulo–$ultimoItem de $total',
                style: const TextStyle(
                  fontSize: 13,
                  color: _muted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Text(
              '${paginaIdx + 1} / ${ultimoIndicePagina + 1}',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: _ink,
              ),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'Página anterior',
              onPressed: paginaIdx > 0
                  ? () => setState(() => _paginaMonitor = paginaIdx - 1)
                  : null,
              icon: Icon(
                Icons.chevron_left_rounded,
                color: paginaIdx > 0 ? PainelAdminTheme.roxo : _muted,
              ),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'Próxima página',
              onPressed: paginaIdx < ultimoIndicePagina
                  ? () => setState(() => _paginaMonitor = paginaIdx + 1)
                  : null,
              icon: Icon(
                Icons.chevron_right_rounded,
                color: paginaIdx < ultimoIndicePagina
                    ? PainelAdminTheme.roxo
                    : _muted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('pedidos')
            .orderBy('data_pedido', descending: true)
            .limit(500)
            .snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting &&
              !snap.hasData) {
            return Center(
              child: CircularProgressIndicator(color: PainelAdminTheme.roxo),
            );
          }

          final todos = (snap.data?.docs ?? []).where((doc) {
            final d = doc.data() as Map<String, dynamic>;
            final st = d['status']?.toString() ?? '';
            return _todosStatus.contains(st) &&
                _passaJanela(d['data_pedido'] as Timestamp?);
          }).toList();

          final filtrados = todos.where((doc) {
            final d = doc.data() as Map<String, dynamic>;
            final st = d['status']?.toString() ?? '';
            return _passaFiltro(st) &&
                _passaFiltroHoje(d['data_pedido'] as Timestamp?) &&
                _passaBusca(doc, d);
          }).toList();

          final totalLista = filtrados.length;
          final ultimoIndicePagina = totalLista == 0
              ? 0
              : (totalLista - 1) ~/ _kPedidosPorPaginaMonitor;
          final paginaEfetiva = _paginaMonitor.clamp(0, ultimoIndicePagina);
          if (paginaEfetiva != _paginaMonitor) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                setState(() => _paginaMonitor = paginaEfetiva);
              }
            });
          }
          final inicio = paginaEfetiva * _kPedidosPorPaginaMonitor;
          final filtradosPagina = filtrados.sublist(
            inicio,
            min(inicio + _kPedidosPorPaginaMonitor, totalLista),
          );

          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: _header()),
              SliverToBoxAdapter(child: _kpis(todos)),
              if (filtrados.isEmpty)
                SliverFillRemaining(child: _vazio())
              else ...[
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
                  sliver: SliverList.separated(
                    itemCount: filtradosPagina.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (_, i) => _card(filtradosPagina[i]),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
                    child: _barraPaginacaoMonitor(
                      total: totalLista,
                      paginaIdx: paginaEfetiva,
                      ultimoIndicePagina: ultimoIndicePagina,
                    ),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _header() {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: _border)),
      ),
      padding: const EdgeInsets.fromLTRB(28, 28, 28, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Monitor de Pedidos',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        color: _ink,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Central de investigação operacional — dados ao vivo',
                      style: TextStyle(fontSize: 14, color: _muted),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFECFDF5),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: const Color(0xFFA7F3D0)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: Color(0xFF16A34A),
                        shape: BoxShape.circle,
                      ),
                      child: SizedBox(width: 8, height: 8),
                    ),
                    SizedBox(width: 7),
                    Text(
                      'Ao vivo',
                      style: TextStyle(
                        color: Color(0xFF16A34A),
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _bg,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: _border),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _buscaC,
                    onChanged: (_) => setState(() => _paginaMonitor = 0),
                    style: const TextStyle(fontSize: 14),
                    decoration: InputDecoration(
                      hintText:
                          'Pesquisar pedido, loja, cliente, cidade, endereço...',
                      hintStyle: const TextStyle(
                        color: Color(0xFF94A3B8),
                        fontSize: 14,
                      ),
                      prefixIcon: const Icon(
                        Icons.search_rounded,
                        color: Color(0xFF94A3B8),
                      ),
                      filled: true,
                      fillColor: Colors.white,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 14),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: _border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: _border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(
                          color: PainelAdminTheme.roxo,
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: _border),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _janelaBtn('24h', '24 h'),
                      _janelaBtn('7d', '7 dias'),
                      _janelaBtn('todos', 'Tudo'),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _chip('hoje', 'Hoje'),
                _chip('todos', 'Todos'),
                _chip('pendente', 'Pendente'),
                _chip('encomenda_entrada_paga', 'Enc. entrada paga'),
                _chip('aceito', 'Aceito'),
                _chip('em_preparo', 'Preparando'),
                _chip('coleta', 'Pronto / coleta'),
                _chip('rota', 'Em rota'),
                _chip('entregue', 'Entregue'),
                _chip('cancelado', 'Cancelado'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _janelaBtn(String val, String label) {
    final ativo = _janela == val;
    return Material(
      color: ativo ? PainelAdminTheme.roxo : Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => setState(() {
          _janela = val;
          _paginaMonitor = 0;
        }),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: ativo ? Colors.white : _muted,
            ),
          ),
        ),
      ),
    );
  }

  Widget _chip(String val, String label) {
    final ativo = _filtro == val;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: ativo ? PainelAdminTheme.roxo : _bg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: ativo ? PainelAdminTheme.roxo : const Color(0xFFE2E8F0),
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => setState(() {
            _filtro = val;
            _paginaMonitor = 0;
          }),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: ativo ? Colors.white : const Color(0xFF475569),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _kpis(List<QueryDocumentSnapshot> docs) {
    final ativos = _contar(docs, (s) => !_isFinal(s));
    final pendentes = _contar(docs, (s) => s == 'pendente');
    final prep = _contar(docs, (s) => s == 'em_preparo');
    final coleta = _contar(
      docs,
      (s) => s == 'aguardando_entregador' || s == 'entregador_indo_loja',
    );
    final rota = _contar(
      docs,
      (s) => s == 'saiu_entrega' || s == 'em_rota' || s == 'a_caminho',
    );
    final entregues = _contar(docs, (s) => s == 'entregue');
    final cancelados = _contar(docs, (s) => s == 'cancelado');
    final encProd = _contar(docs, (s) => s == 'encomenda_entrada_paga');

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 14),
      child: Wrap(
        spacing: 14,
        runSpacing: 14,
        children: [
          _kpi(
            'Ativos',
            '$ativos',
            Icons.insights_rounded,
            PainelAdminTheme.roxo,
          ),
          _kpi(
            'Pendentes',
            '$pendentes',
            Icons.schedule_rounded,
            const Color(0xFFD97706),
          ),
          _kpi(
            'Enc. produção',
            '$encProd',
            Icons.inventory_2_outlined,
            const Color(0xFFB7791F),
          ),
          _kpi(
            'Preparando',
            '$prep',
            Icons.restaurant_rounded,
            PainelAdminTheme.roxo,
          ),
          _kpi(
            'Coleta',
            '$coleta',
            Icons.inventory_2_outlined,
            const Color(0xFF0891B2),
          ),
          _kpi(
            'Em rota',
            '$rota',
            Icons.delivery_dining_rounded,
            const Color(0xFF059669),
          ),
          _kpi(
            'Entregues',
            '$entregues',
            Icons.check_circle_rounded,
            const Color(0xFF16A34A),
          ),
          _kpi(
            'Cancelados',
            '$cancelados',
            Icons.cancel_rounded,
            const Color(0xFFDC2626),
          ),
        ],
      ),
    );
  }

  Widget _kpi(String label, String valor, IconData icon, Color cor) {
    return Container(
      width: 178,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.055),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: cor.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 20, color: cor),
              ),
              const Spacer(),
              Text(
                valor,
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  color: cor,
                  height: 1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: _muted,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 4,
              value: (int.tryParse(valor) ?? 0) > 0 ? 1 : 0.08,
              backgroundColor: cor.withValues(alpha: 0.08),
              valueColor: AlwaysStoppedAnimation<Color>(
                cor.withValues(alpha: 0.55),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _vazio() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.inbox_rounded,
            size: 56,
            color: _muted.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 14),
          const Text(
            'Nenhum pedido encontrado',
            style: TextStyle(
              fontSize: 16,
              color: _muted,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Ajuste os filtros, janela de tempo ou busca.',
            style: TextStyle(fontSize: 13, color: _muted),
          ),
        ],
      ),
    );
  }

  Widget _card(QueryDocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    final st = d['status']?.toString() ?? '';
    final cor = _corStatus(st);
    final total = _num(d['total']);
    final prods = _num(d['total_produtos']) > 0
        ? _num(d['total_produtos'])
        : _num(d['subtotal']);
    final frete = _num(d['taxa_entrega']);
    final forma = d['forma_pagamento']?.toString() ?? '—';
    final ts = d['data_pedido'] as Timestamp?;
    final dtStr = ts != null
        ? DateFormat('dd/MM/yy  HH:mm').format(ts.toDate())
        : '—';
    final loja = d['loja_nome']?.toString() ?? 'Loja';
    final cliente =
        d['cliente_nome']?.toString() ?? d['cliente_id']?.toString() ?? '—';
    final cidade = d['cidade']?.toString() ?? '';
    final endereco = d['endereco_entrega']?.toString() ?? '';
    final entregador =
        d['entregador_nome']?.toString() ??
        (d['entregador_id'] != null ? '(${d['entregador_id']})' : '—');
    final itens =
        ((d['itens'] as List?) ?? (d['items'] as List?) ?? const []).length;
    final codigoPedido = CodigoPedido.exibir(doc.id, d);
    final tipoCompra = (d['tipo_compra'] ?? d['tipo_venda'] ?? '')
        .toString()
        .trim();
    final faseEncomenda = (d['encomenda_fase_financeira'] ?? '')
        .toString()
        .trim();
    final tipoResumo = [
      if (tipoCompra == 'encomenda') 'Encomenda',
      if (faseEncomenda == 'entrada') 'entrada',
      if (faseEncomenda == 'saldo_final') 'saldo final',
    ].join(' — ');

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.045),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => _detalhe(doc),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: cor.withValues(alpha: 0.11),
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(color: cor.withValues(alpha: 0.18)),
                  ),
                  child: Icon(_iconeStatus(st), size: 22, color: cor),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  codigoPedido,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 15,
                                    color: _ink,
                                    letterSpacing: -0.2,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  '$loja • $cliente',
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF334155),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          _statusPill(st, cor),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _tag(Icons.calendar_today_rounded, dtStr),
                          if (cidade.isNotEmpty)
                            _tag(Icons.location_on_outlined, cidade),
                          _tag(Icons.shopping_bag_outlined, '$itens item(s)'),
                          _tag(Icons.credit_card_outlined, forma),
                          _tag(Icons.two_wheeler_rounded, entregador),
                          if (tipoResumo.isNotEmpty)
                            _tag(Icons.inventory_2_outlined, tipoResumo),
                        ],
                      ),
                      if (endereco.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 9,
                          ),
                          decoration: BoxDecoration(
                            color: _bg,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: _border),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.place_outlined,
                                size: 16,
                                color: _muted,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  endereco,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: _muted,
                                    height: 1.3,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          _valorBoxCompacto('Produtos', prods),
                          const SizedBox(width: 8),
                          _valorBoxCompacto('Frete', frete),
                          const SizedBox(width: 8),
                          _valorBoxCompacto('Total', total, destaque: true),
                          const Spacer(),
                          FilledButton.icon(
                            onPressed: () => _detalhe(doc),
                            icon: const Icon(
                              Icons.manage_search_rounded,
                              size: 18,
                            ),
                            label: const Text('Investigar'),
                            style: FilledButton.styleFrom(
                              backgroundColor: PainelAdminTheme.roxo,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 13,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
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
      ),
    );
  }

  Widget _statusPill(String status, Color cor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: cor.withValues(alpha: 0.22)),
      ),
      child: Text(
        _labelStatus(status),
        style: TextStyle(
          color: cor,
          fontWeight: FontWeight.w800,
          fontSize: 11.5,
        ),
      ),
    );
  }

  Widget _tag(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: _muted),
        const SizedBox(width: 5),
        Text(
          text,
          style: const TextStyle(fontSize: 12, color: Color(0xFF475569)),
        ),
      ],
    );
  }

  Widget _valorBoxCompacto(
    String label,
    double valor, {
    bool destaque = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: destaque ? PainelAdminTheme.roxo.withValues(alpha: 0.06) : _bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: destaque
              ? PainelAdminTheme.roxo.withValues(alpha: 0.15)
              : _border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 9,
              color: _muted,
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            'R\$ ${valor.toStringAsFixed(2)}',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: destaque ? PainelAdminTheme.roxo : _ink,
            ),
          ),
        ],
      ),
    );
  }

  void _detalhe(QueryDocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    final st = d['status']?.toString() ?? '';
    final ts = d['data_pedido'] as Timestamp?;
    final codigoPedido = CodigoPedido.exibir(doc.id, d);
    final entregadorNome = d['entregador_nome']?.toString() ?? '—';
    final entregadorId = d['entregador_id']?.toString() ?? '—';
    final itens = (d['itens'] as List?) ?? (d['items'] as List?) ?? [];
    final latConclusao = _coordGps(d['entrega_conclusao_latitude']);
    final lonConclusao = _coordGps(d['entrega_conclusao_longitude']);
    final eventosTimeline = _eventosTimelineOperacional(d);
    final camposDur = _camposDuracaoDerivada(d);
    final camposDesp = _camposDespachoResumo(d);

    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720, maxHeight: 850),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header com título e botão de fechar
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      PainelAdminTheme.roxo,
                      PainelAdminTheme.roxo.withValues(alpha: 0.8),
                    ],
                  ),
                ),
                padding: const EdgeInsets.fromLTRB(24, 20, 16, 20),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.manage_search_rounded,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Investigação do Pedido',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            codigoPedido,
                            style: const TextStyle(
                              fontSize: 13,
                              color: Colors.white70,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(
                        Icons.close_rounded,
                        color: Colors.white,
                      ),
                      tooltip: 'Fechar',
                    ),
                  ],
                ),
              ),

              // Conteúdo scrollável
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
                  children: [
                    // Seção: Informações do Pedido
                    _secaoInfo(
                      titulo: 'Pedido',
                      icone: Icons.receipt_long_rounded,
                      campos: [
                        _campo('Código', codigoPedido),
                        _campo('Status', _labelStatus(st)),
                        _campo(
                          'Data / Hora',
                          ts != null
                              ? DateFormat(
                                  'dd/MM/yyyy  HH:mm:ss',
                                ).format(ts.toDate())
                              : '—',
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    _secaoTimelineOperacional(eventosTimeline),
                    const SizedBox(height: 20),

                    _secaoInfo(
                      titulo: 'Durações (derivadas dos carimbos)',
                      icone: Icons.timer_outlined,
                      campos: camposDur.isNotEmpty
                          ? camposDur
                          : [
                              _campo(
                                'Intervalos',
                                'Carimbos insuficientes (ex.: falta início da busca, aceite ou conclusão).',
                              ),
                            ],
                    ),
                    const SizedBox(height: 20),

                    _secaoInfo(
                      titulo: 'Despacho / fila',
                      icone: Icons.alt_route_rounded,
                      campos: camposDesp.isNotEmpty
                          ? camposDesp
                          : [
                              _campo(
                                'Registro',
                                'Sem dados de fila ou despacho neste documento.',
                              ),
                            ],
                    ),
                    const SizedBox(height: 20),

                    // Seção: Loja
                    _secaoInfo(
                      titulo: 'Loja',
                      icone: Icons.store_rounded,
                      campos: [
                        _campo('Loja', d['loja_nome']?.toString() ?? '—'),
                        _campoUid(
                          'UID (interno)',
                          (d['loja_id'] ?? d['lojista_id'])?.toString(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Seção: Cliente
                    _secaoInfo(
                      titulo: 'Cliente',
                      icone: Icons.person_rounded,
                      campos: [
                        _campo('Nome', d['cliente_nome']?.toString() ?? '—'),
                        _campoUid('UID (interno)', d['cliente_id']?.toString()),
                        _campo('Cidade', d['cidade']?.toString() ?? '—'),
                        _campo(
                          'Endereço',
                          d['endereco_entrega']?.toString() ?? '—',
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Seção: Entregador
                    _secaoInfo(
                      titulo: 'Entregador',
                      icone: Icons.two_wheeler_rounded,
                      campos: [
                        _campo('Nome', entregadorNome),
                        _campoUid('UID (interno)', entregadorId),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Seção: Produtos (com fotos)
                    if (itens.isNotEmpty) ...[
                      _secaoTituloSimples('Produtos Comprados'),
                      const SizedBox(height: 12),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            for (int i = 0; i < itens.length; i++)
                              Padding(
                                padding: EdgeInsets.only(
                                  right: i < itens.length - 1 ? 12 : 0,
                                ),
                                child: _cartaoProduto(
                                  itens[i] as Map<String, dynamic>,
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],

                    // Seção: Resumo Financeiro
                    _secaoInfo(
                      titulo: 'Resumo Financeiro',
                      icone: Icons.credit_card_rounded,
                      campos: [
                        _campo(
                          'Forma de Pagamento',
                          d['forma_pagamento']?.toString() ?? '—',
                        ),
                        _campo(
                          'Produtos',
                          'R\$ ${_num(d['total_produtos'] ?? d['subtotal']).toStringAsFixed(2)}',
                        ),
                        _campo(
                          'Frete',
                          'R\$ ${_num(d['taxa_entrega']).toStringAsFixed(2)}',
                        ),
                        _campo(
                          'Total',
                          'R\$ ${_num(d['total']).toStringAsFixed(2)}',
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Seção: Detalhes Adicionais
                    _secaoInfo(
                      titulo: 'Detalhes Adicionais',
                      icone: Icons.info_rounded,
                      campos: [
                        _campo(
                          'Token de Entrega',
                          d['token_entrega']?.toString() ?? '—',
                        ),
                        _campoIdFirestore('ID do pedido (Firestore)', doc.id),
                      ],
                    ),
                    if (latConclusao != null && lonConclusao != null) ...[
                      const SizedBox(height: 20),
                      _secaoLocalConclusaoGps(d, latConclusao, lonConclusao),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static double? _coordGps(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  Future<void> _abrirMapaConclusao(double lat, double lon) async {
    final u = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=$lat,$lon',
    );
    if (await canLaunchUrl(u)) {
      await launchUrl(u, mode: LaunchMode.externalApplication);
    }
  }

  Widget _secaoLocalConclusaoGps(
    Map<String, dynamic> d,
    double lat,
    double lon,
  ) {
    final prec = d['entrega_conclusao_precisao_m'];
    final temPrec = prec != null && _num(prec) > 0;
    final precStr = temPrec ? '${_num(prec).round()} m (aprox.)' : '—';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _secaoInfo(
          titulo: 'Local da conclusão (GPS)',
          icone: Icons.pin_drop_rounded,
          campos: [
            _campo('Latitude', lat.toStringAsFixed(6)),
            _campo('Longitude', lon.toStringAsFixed(6)),
            _campo('Precisão do aparelho', precStr),
          ],
        ),
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => _abrirMapaConclusao(lat, lon),
            icon: const Icon(Icons.map_rounded, size: 20),
            label: const Text('Abrir no mapa'),
            style: TextButton.styleFrom(foregroundColor: PainelAdminTheme.roxo),
          ),
        ),
      ],
    );
  }

  Widget _secaoTituloSimples(String titulo) {
    return Row(
      children: [
        Icon(
          Icons.shopping_bag_rounded,
          size: 18,
          color: PainelAdminTheme.roxo,
        ),
        const SizedBox(width: 8),
        Text(
          titulo,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: _ink,
          ),
        ),
      ],
    );
  }

  Widget _secaoInfo({
    required String titulo,
    required IconData icone,
    required List<_LinhaSecao> campos,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icone, size: 18, color: PainelAdminTheme.roxo),
            const SizedBox(width: 8),
            Text(
              titulo,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: _ink,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: _bg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _border),
          ),
          child: Column(
            children: [
              for (int i = 0; i < campos.length; i++) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 11,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 118,
                        child: Text(
                          campos[i].label,
                          style: const TextStyle(
                            fontSize: 12,
                            color: _muted,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: SelectableText(
                          campos[i].valor,
                          style: const TextStyle(
                            fontSize: 12,
                            color: _ink,
                            fontWeight: FontWeight.w600,
                            height: 1.4,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                      if (campos[i].copiar != null &&
                          campos[i].copiar!.isNotEmpty)
                        IconButton(
                          onPressed: () => _copiarTexto(campos[i].copiar!),
                          icon: const Icon(
                            Icons.content_copy_rounded,
                            size: 18,
                          ),
                          color: PainelAdminTheme.roxo,
                          tooltip: 'Copiar ID completo',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 34,
                            minHeight: 34,
                          ),
                          visualDensity: VisualDensity.compact,
                        ),
                    ],
                  ),
                ),
                if (i < campos.length - 1)
                  Divider(height: 1, color: _border.withValues(alpha: 0.6)),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _cartaoProduto(Map<String, dynamic> item) {
    final nome = item['nome']?.toString() ?? 'Produto';
    final imagem = item['imagem']?.toString() ?? item['foto_url']?.toString();
    final preco = _num(item['preco'] ?? item['valor']);
    final quantidade = item['quantidade']?.toString() ?? '1';

    return Container(
      width: 140,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Imagem do produto
          Container(
            height: 100,
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(10),
                topRight: Radius.circular(10),
              ),
              color: _bg,
              image: imagem != null && imagem.isNotEmpty
                  ? DecorationImage(
                      image: NetworkImage(imagem),
                      fit: BoxFit.cover,
                    )
                  : null,
            ),
            child: imagem == null || imagem.isEmpty
                ? const Center(
                    child: Icon(
                      Icons.image_not_supported_rounded,
                      color: _muted,
                      size: 28,
                    ),
                  )
                : null,
          ),
          Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  nome,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: _ink,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Qty: $quantidade',
                  style: const TextStyle(
                    fontSize: 10,
                    color: _muted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'R\$ ${preco.toStringAsFixed(2)}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: PainelAdminTheme.roxo,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  double _num(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }
}
