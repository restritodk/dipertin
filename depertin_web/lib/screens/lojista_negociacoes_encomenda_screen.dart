import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../navigation/painel_navigation_scope.dart';
import '../theme/painel_admin_theme.dart';
import '../utils/encomenda_painel_helpers.dart';
import '../utils/lojista_painel_context.dart';
import 'lojista_encomenda_detalhe_painel_screen.dart';

/// Central de negociações — inbox mestre/detalhe (Zendesk / WhatsApp Web).
class LojistaNegociacoesEncomendaScreen extends StatefulWidget {
  const LojistaNegociacoesEncomendaScreen({super.key});

  @override
  State<LojistaNegociacoesEncomendaScreen> createState() =>
      _LojistaNegociacoesEncomendaScreenState();
}

class _LojistaNegociacoesEncomendaScreenState
    extends State<LojistaNegociacoesEncomendaScreen> {
  final _buscaClienteC = TextEditingController();
  final _buscaCodigoC = TextEditingController();

  FiltroEncomendaRapido _filtroRapido = FiltroEncomendaRapido.todas;
  String _periodo = 'tudo';
  String? _selecionadaId;

  FiltroEncomendaRapido get _filtroAtivo =>
      _filtroRapido == FiltroEncomendaRapido.canceladas
          ? FiltroEncomendaRapido.todas
          : _filtroRapido;

  @override
  void dispose() {
    _buscaClienteC.dispose();
    _buscaCodigoC.dispose();
    super.dispose();
  }

  void _garantirSelecao(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> filtrados,
  ) {
    if (filtrados.isEmpty) {
      if (_selecionadaId != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _selecionadaId = null);
        });
      }
      return;
    }
    final ids = filtrados.map((d) => d.id).toSet();
    if (_selecionadaId == null || !ids.contains(_selecionadaId)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _selecionadaId = filtrados.first.id);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return LojistaUidLojaBuilder(
      builder: (context, authUid, uidLoja, dadosUsuario) {
        if (uidLoja.isEmpty) {
          return _layoutErro(
            'Não foi possível identificar a loja. Faça login novamente.',
          );
        }
        return _corpo(uidLoja);
      },
    );
  }

  Widget _corpo(String uidLoja) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('encomendas')
          .where('loja_id', isEqualTo: uidLoja)
          .snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return const Center(
            child: CircularProgressIndicator(color: PainelAdminTheme.roxo),
          );
        }
        if (snap.hasError) {
          return _layoutErro('Não foi possível carregar: ${snap.error}');
        }

        final docsBrutos = [...?snap.data?.docs];
        final docs = filtrarEncomendasVisiveisLojista(docsBrutos);
        docs.sort((a, b) {
          final ta = a.data()['atualizado_em'];
          final tb = b.data()['atualizado_em'];
          if (ta is Timestamp && tb is Timestamp) {
            return tb.compareTo(ta);
          }
          return 0;
        });

        final ids = docs.map((d) => d.id).toSet();

        return StreamBuilder<Map<String, String>>(
          stream: streamStatusPedidosEncomenda(
            uidLoja: uidLoja,
            encomendaIds: ids,
          ),
          builder: (context, pedSnap) {
            final statusPedidos = pedSnap.data ?? {};
            final buckets = contarBuckets(docs, statusPedidos);
            final filtrados = _aplicarFiltros(docs, statusPedidos);
            _garantirSelecao(filtrados);

            if (filtrados.isEmpty) {
              return ColoredBox(
                color: PainelAdminTheme.fundoCanvas,
                child: Column(
                  children: [
                    _toolbarLista(buckets, 0, docs.length),
                    Expanded(child: _emptyState()),
                  ],
                ),
              );
            }

            return ColoredBox(
              color: PainelAdminTheme.fundoCanvas,
              child: LayoutBuilder(
                builder: (context, c) {
                  final estreito = c.maxWidth < 820;
                  if (estreito) {
                    return Column(
                      children: [
                        SizedBox(
                          height: 220,
                          child: _colunaLista(filtrados, statusPedidos, buckets, docs.length),
                        ),
                        const Divider(height: 1),
                        Expanded(
                          child: _painelDetalhe(uidLoja, statusPedidos),
                        ),
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        width: 300,
                        child: _colunaLista(
                          filtrados,
                          statusPedidos,
                          buckets,
                          docs.length,
                        ),
                      ),
                      Container(width: 1, color: Colors.grey.shade300),
                      Expanded(
                        child: _painelDetalhe(uidLoja, statusPedidos),
                      ),
                    ],
                  );
                },
              ),
            );
          },
        );
      },
    );
  }

  Widget _colunaLista(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    Map<String, String> statusPedidos,
    Map<FiltroEncomendaRapido, int> buckets,
    int totalDocs,
  ) {
    return ColoredBox(
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _toolbarLista(buckets, docs.length, totalDocs),
          Expanded(
            child: ListView.builder(
              itemCount: docs.length,
              itemBuilder: (context, i) {
                final doc = docs[i];
                return _itemListaInbox(
                  doc,
                  doc.id == _selecionadaId,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _toolbarLista(
    Map<FiltroEncomendaRapido, int> buckets,
    int filtradas,
    int total,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [PainelAdminTheme.roxo, Color(0xFF8E24AA)],
            ),
          ),
          child: Row(
            children: [
              const Icon(Icons.handshake_outlined, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Central de Encomendas',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
              ),
              if (total > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    filtradas == total ? '$total' : '$filtradas/$total',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
          child: Column(
            children: [
              TextField(
                controller: _buscaClienteC,
                onChanged: (_) => setState(() {}),
                style: const TextStyle(fontSize: 12),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Buscar cliente…',
                  prefixIcon: const Icon(Icons.search, size: 16),
                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _buscaCodigoC,
                      onChanged: (_) => setState(() {}),
                      style: const TextStyle(fontSize: 12),
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: 'Código',
                        prefixIcon: const Icon(Icons.tag, size: 15),
                        contentPadding: const EdgeInsets.symmetric(vertical: 8),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: DropdownButtonFormField<FiltroEncomendaRapido>(
                      initialValue: _filtroAtivo,
                      isDense: true,
                      isExpanded: true,
                      decoration: InputDecoration(
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 6,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      items: filtrosEncomendaPainelLojista
                          .map(
                            (f) => DropdownMenuItem(
                              value: f,
                              child: Text(
                                '${f.rotulo} (${buckets[f] ?? 0})',
                                style: const TextStyle(fontSize: 11),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (v) {
                        if (v != null) setState(() => _filtroRapido = v);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerRight,
                child: DropdownButton<String>(
                  value: _periodo,
                  isDense: true,
                  underline: const SizedBox.shrink(),
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                  items: const [
                    DropdownMenuItem(value: 'tudo', child: Text('Todo período')),
                    DropdownMenuItem(value: 'hoje', child: Text('Hoje')),
                    DropdownMenuItem(value: '7d', child: Text('7 dias')),
                    DropdownMenuItem(value: '30d', child: Text('30 dias')),
                  ],
                  onChanged: (v) => setState(() => _periodo = v ?? 'tudo'),
                ),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: Colors.grey.shade200),
      ],
    );
  }

  Widget _itemListaInbox(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
    bool selecionado,
  ) {
    final m = doc.data();
    final st = (m['status_negociacao'] ?? '').toString();
    final badge = badgeEncomenda(st);
    final produto = produtoPrincipalNome(m) ?? 'Encomenda';
    final nomeCli = (m['cliente_nome_snapshot'] ?? 'Cliente').toString();
    final atualizado = timestampParaDate(m['atualizado_em']);
    final quando = tempoRelativoAtualizacao(atualizado)
        .replaceFirst('Atualizado ', '');
    final temAcaoLoja = lojaPrecisaAgirEncomenda(st);

    return Material(
      color: selecionado
          ? PainelAdminTheme.roxo.withValues(alpha: 0.07)
          : (temAcaoLoja
              ? PainelAdminTheme.laranja.withValues(alpha: 0.04)
              : Colors.white),
      child: InkWell(
        onTap: () => setState(() => _selecionadaId = doc.id),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: selecionado
                    ? PainelAdminTheme.roxo
                    : (temAcaoLoja
                        ? PainelAdminTheme.laranja
                        : Colors.transparent),
                width: 3,
              ),
              bottom: BorderSide(color: Colors.grey.shade100),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    codigoEncomendaExibir(doc.id),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'monospace',
                      color: selecionado
                          ? PainelAdminTheme.roxo
                          : Colors.grey.shade600,
                    ),
                  ),
                  const Spacer(),
                  if (quando.isNotEmpty)
                    Text(
                      quando,
                      style: TextStyle(fontSize: 9.5, color: Colors.grey.shade500),
                    ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                nomeCli,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: PainelAdminTheme.dashboardInk,
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      produto,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                    ),
                  ),
                  Container(
                    width: 7,
                    height: 7,
                    margin: const EdgeInsets.only(left: 4, right: 4),
                    decoration: BoxDecoration(
                      color: badge.cor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  Flexible(
                    child: Text(
                      badge.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: badge.cor,
                      ),
                    ),
                  ),
                ],
              ),
              if (temAcaoLoja) ...[
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: PainelAdminTheme.laranja.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'Aguardando sua ação',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      color: PainelAdminTheme.laranja,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _painelDetalhe(
    String uidLoja,
    Map<String, String> statusPedidos,
  ) {
    if (_selecionadaId == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.mark_chat_unread_outlined,
                size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 8),
            Text(
              'Selecione uma negociação',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
            ),
          ],
        ),
      );
    }
    return LojistaEncomendaDetalhePainelScreen(
      key: ValueKey(_selecionadaId),
      encomendaId: _selecionadaId!,
      uidLoja: uidLoja,
      embedded: true,
      statusPedidos: statusPedidos,
    );
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _aplicarFiltros(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    Map<String, String> statusPedidos,
  ) {
    final buscaCli = _buscaClienteC.text.trim().toLowerCase();
    final buscaCod = _buscaCodigoC.text.trim().toUpperCase();
    final agora = DateTime.now();

    return docs.where((doc) {
      if (_filtroAtivo != FiltroEncomendaRapido.todas) {
        final bucket = bucketEncomendaDoc(doc, statusPedidos);
        if (bucket != _filtroAtivo) return false;
      }

      final data = doc.data();
      if (buscaCli.isNotEmpty) {
        final nome = (data['cliente_nome_snapshot'] ?? '')
            .toString()
            .toLowerCase();
        if (!nome.contains(buscaCli)) return false;
      }
      if (buscaCod.isNotEmpty) {
        final cod = codigoEncomendaExibir(doc.id).toUpperCase();
        if (!cod.contains(buscaCod) &&
            !doc.id.toUpperCase().contains(buscaCod)) {
          return false;
        }
      }

      if (_periodo != 'tudo') {
        final criado = timestampParaDate(data['criado_em']);
        if (criado == null) return false;
        switch (_periodo) {
          case 'hoje':
            if (!_mesmoDia(criado, agora)) return false;
          case '7d':
            if (agora.difference(criado).inDays > 7) return false;
          case '30d':
            if (agora.difference(criado).inDays > 30) return false;
        }
      }
      return true;
    }).toList();
  }

  bool _mesmoDia(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  Widget _emptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox_outlined, size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text(
              'Nenhuma negociação encontrada',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 16,
                color: PainelAdminTheme.dashboardInk,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Solicitações sob encomenda aparecerão aqui.',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () => context.navegarPainel('/meus_pedidos'),
              icon: const Icon(Icons.receipt_long_outlined, size: 16),
              label: const Text('Meus pedidos'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _layoutErro(String mensagem) {
    return Center(child: Text(mensagem));
  }
}
