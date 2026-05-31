import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../constants/encomenda_negociacao_status.dart';
import '../../constants/pedido_status.dart';
import 'lojista_encomenda_detalhe_screen.dart';

/// Lista encomendas da loja (`encomendas.loja_id`).
/// Design premium DiPertin com cards, badges de status e hierarquia visual clara.
class LojistaEncomendasScreen extends StatefulWidget {
  const LojistaEncomendasScreen({super.key, required this.uidLoja});

  final String uidLoja;

  @override
  State<LojistaEncomendasScreen> createState() =>
      _LojistaEncomendasScreenState();
}

class _LojistaEncomendasScreenState extends State<LojistaEncomendasScreen> {
  static final DateFormat _fmtData = DateFormat('dd/MM/yyyy HH:mm', 'pt_BR');

  // Cores do tema DiPertin
  static const Color _roxo = Color(0xFF6A1B9A);
  static const Color _laranja = Color(0xFFFF8F00);
  static const Color _roxoClaro = Color(0xFFF3E5F5);

  String _filtroBusca = '';

  static const List<_AbaEncomendaConfig> _abas = [
    _AbaEncomendaConfig(
      tipo: _AbaEncomenda.aguardando,
      titulo: 'Aguardando',
      subtitulo: 'Aprovação',
      icon: Icons.hourglass_top,
      color: Color(0xFFFF8F00),
    ),
    _AbaEncomendaConfig(
      tipo: _AbaEncomenda.andamento,
      titulo: 'Em andamento',
      subtitulo: 'Entrada paga',
      icon: Icons.construction,
      color: Color(0xFF00897B),
    ),
    _AbaEncomendaConfig(
      tipo: _AbaEncomenda.finalizados,
      titulo: 'Finalizados',
      subtitulo: 'Entregues',
      icon: Icons.check_circle,
      color: Color(0xFF2E7D32),
    ),
    _AbaEncomendaConfig(
      tipo: _AbaEncomenda.cancelados,
      titulo: 'Cancelados',
      subtitulo: 'Encerrados',
      icon: Icons.cancel,
      color: Color(0xFFC62828),
    ),
  ];

  String _normalizarBusca(String texto) {
    final semAcento = texto
        .toLowerCase()
        .replaceAll(RegExp('[áàâãä]'), 'a')
        .replaceAll(RegExp('[éèêë]'), 'e')
        .replaceAll(RegExp('[íìîï]'), 'i')
        .replaceAll(RegExp('[óòôõö]'), 'o')
        .replaceAll(RegExp('[úùûü]'), 'u')
        .replaceAll('ç', 'c');
    return semAcento.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  String _somenteDigitos(String texto) {
    return texto.replaceAll(RegExp(r'\D'), '');
  }

  String _campo(Map<String, dynamic> data, List<String> campos) {
    for (final campo in campos) {
      final valor = (data[campo] ?? '').toString().trim();
      if (valor.isNotEmpty && valor != 'null') return valor;
    }
    return '';
  }

  bool _docCombinaFiltro(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
    String filtro,
  ) {
    final busca = _normalizarBusca(filtro);
    if (busca.isEmpty) return true;

    final data = doc.data();
    final digitosBusca = _somenteDigitos(busca);
    final textos = <String>[
      doc.id,
      _campo(data, ['cliente_nome_snapshot', 'cliente_nome', 'nome_cliente']),
      _campo(data, ['cliente_cpf', 'cpf_cliente', 'cpf', 'cpf_digitos']),
      _campo(data, ['pedido_entrada_id']),
      _campo(data, ['pedido_saldo_final_id']),
      _campo(data, ['status_negociacao']),
    ];

    final textoNormalizado = _normalizarBusca(textos.join(' '));
    if (textoNormalizado.contains(busca)) return true;

    if (digitosBusca.isEmpty) return false;
    final digitosDocumento = _somenteDigitos(textos.join(' '));
    return digitosDocumento.contains(digitosBusca);
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _filtrarDocs(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    return docs.where((doc) => _docCombinaFiltro(doc, _filtroBusca)).toList();
  }

  bool _pedidoVinculadoEntregue(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
    Map<String, String> statusPedidos,
  ) {
    final data = doc.data();
    final pedidoLogistica = (data['pedido_logistica_id'] ?? '').toString();
    final pedidoSaldo = (data['pedido_saldo_final_id'] ?? '').toString();
    final ids = <String>[
      if (pedidoLogistica.trim().isNotEmpty) pedidoLogistica.trim(),
      if (pedidoSaldo.trim().isNotEmpty) pedidoSaldo.trim(),
    ];
    return ids.any((id) => statusPedidos[id] == PedidoStatus.entregue);
  }

  _AbaEncomenda _abaDoDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
    Map<String, String> statusPedidos,
  ) {
    final st = (doc.data()['status_negociacao'] ?? '').toString();
    if (EncomendaNegociacaoStatus.encerradaDefinitivamente(st)) {
      return _AbaEncomenda.cancelados;
    }
    if (_pedidoVinculadoEntregue(doc, statusPedidos)) {
      return _AbaEncomenda.finalizados;
    }
    if (st == EncomendaNegociacaoStatus.entradaPagaEmProducao ||
        st == EncomendaNegociacaoStatus.saldoFinalAguardandoPgto ||
        st == EncomendaNegociacaoStatus.emExecucaoLogistica) {
      return _AbaEncomenda.andamento;
    }
    return _AbaEncomenda.aguardando;
  }

  Map<_AbaEncomenda, List<QueryDocumentSnapshot<Map<String, dynamic>>>>
  _agruparPorAba(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    Map<String, String> statusPedidos,
  ) {
    final grupos = {
      for (final aba in _AbaEncomenda.values)
        aba: <QueryDocumentSnapshot<Map<String, dynamic>>>[],
    };
    for (final doc in docs) {
      grupos[_abaDoDoc(doc, statusPedidos)]!.add(doc);
    }
    return grupos;
  }

  Stream<Map<String, String>> _streamStatusPedidosVinculados(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final ids = docs.map((doc) => doc.id).toSet();
    if (ids.isEmpty) {
      return Stream<Map<String, String>>.value(<String, String>{});
    }

    return FirebaseFirestore.instance
        .collection('pedidos')
        .where('loja_id', isEqualTo: widget.uidLoja)
        .where('tipo_compra', isEqualTo: 'encomenda')
        .snapshots()
        .map((snap) {
          final status = <String, String>{};
          for (final pedido in snap.docs) {
            final data = pedido.data();
            final encId = (data['encomenda_id'] ?? '').toString().trim();
            if (!ids.contains(encId)) continue;
            final st = (data['status'] ?? '').toString();
            status[pedido.id] = st;
            if (encId.isNotEmpty) {
              final atual = status['enc:$encId'];
              if (atual != PedidoStatus.entregue) {
                status['enc:$encId'] = st;
              }
            }
          }
          return status;
        });
  }

  Future<void> _abrirFiltroBusca() async {
    final controller = TextEditingController(text: _filtroBusca);
    final resultado = await showDialog<String>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.38),
      builder: (ctx) {
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 18,
            vertical: 24,
          ),
          backgroundColor: Colors.transparent,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final largura = constraints.maxWidth > 430
                  ? 430.0
                  : constraints.maxWidth;
              return Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: largura,
                    maxHeight: MediaQuery.of(context).size.height * 0.82,
                  ),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(26),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.18),
                          blurRadius: 28,
                          offset: const Offset(0, 14),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(26),
                      child: SingleChildScrollView(
                        padding: EdgeInsets.only(
                          bottom: MediaQuery.of(ctx).viewInsets.bottom,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Container(
                              padding: const EdgeInsets.fromLTRB(
                                20,
                                20,
                                20,
                                18,
                              ),
                              decoration: const BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [_roxo, Color(0xFF8E24AA)],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.16),
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: const Icon(
                                      Icons.manage_search,
                                      color: Colors.white,
                                      size: 26,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  const Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Pesquisar encomenda',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 19,
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                        SizedBox(height: 3),
                                        Text(
                                          'Encontre uma encomenda rapidamente',
                                          style: TextStyle(
                                            color: Colors.white70,
                                            fontSize: 12,
                                            height: 1.25,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.all(18),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  TextField(
                                    controller: controller,
                                    autofocus: true,
                                    textInputAction: TextInputAction.search,
                                    decoration: InputDecoration(
                                      labelText:
                                          'Nome, CPF ou código do pedido',
                                      hintText: 'Ex.: Maria, 123456 ou CPF',
                                      prefixIcon: const Icon(Icons.search),
                                      filled: true,
                                      fillColor: const Color(0xFFF7F4FA),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(16),
                                        borderSide: BorderSide.none,
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(16),
                                        borderSide: const BorderSide(
                                          color: _roxo,
                                          width: 2,
                                        ),
                                      ),
                                    ),
                                    onSubmitted: (_) => Navigator.pop(
                                      ctx,
                                      controller.text.trim(),
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: const [
                                      _FiltroDicaChip(
                                        icon: Icons.person_outline,
                                        texto: 'Nome do cliente',
                                      ),
                                      _FiltroDicaChip(
                                        icon: Icons.badge_outlined,
                                        texto: 'CPF',
                                      ),
                                      _FiltroDicaChip(
                                        icon:
                                            Icons.confirmation_number_outlined,
                                        texto: 'Código',
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    'A busca considera as encomendas carregadas na tela e aceita nomes com ou sem acento, CPF com ou sem máscara e códigos parciais.',
                                    style: TextStyle(
                                      color: Colors.grey.shade600,
                                      fontSize: 12,
                                      height: 1.35,
                                    ),
                                  ),
                                  const SizedBox(height: 18),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: TextButton(
                                          onPressed: () =>
                                              Navigator.pop(ctx, ''),
                                          style: TextButton.styleFrom(
                                            foregroundColor:
                                                Colors.grey.shade700,
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 13,
                                            ),
                                          ),
                                          child: const Text('Limpar'),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: FilledButton.icon(
                                          onPressed: () => Navigator.pop(
                                            ctx,
                                            controller.text.trim(),
                                          ),
                                          icon: const Icon(Icons.search),
                                          label: const Text('Aplicar'),
                                          style: FilledButton.styleFrom(
                                            backgroundColor: _laranja,
                                            foregroundColor: Colors.white,
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 13,
                                            ),
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(14),
                                            ),
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
                ),
              );
            },
          ),
        );
      },
    );

    if (!mounted || resultado == null) return;
    setState(() => _filtroBusca = resultado.trim());
  }

  /// Widget de badge de status colorido
  Widget _buildStatusBadge(String status) {
    Color bgColor;
    Color textColor = Colors.white;
    IconData icon;
    String label;

    switch (status) {
      case EncomendaNegociacaoStatus.aguardandoNegociacao:
        bgColor = Colors.grey.shade600;
        icon = Icons.hourglass_empty;
        label = 'Aguardando loja';
        break;
      case EncomendaNegociacaoStatus.negociacaoEmAndamento:
        bgColor = Colors.blue;
        icon = Icons.swap_horiz;
        label = 'Em negociação';
        break;
      case EncomendaNegociacaoStatus.propostaEnviada:
        bgColor = _laranja;
        icon = Icons.check_circle;
        label = 'Proposta enviada';
        break;
      case EncomendaNegociacaoStatus.aguardandoRespostaLojaContraproposta:
        bgColor = Colors.orange;
        icon = Icons.hourglass_top;
        label = 'Contraproposta do cliente';
        break;
      case EncomendaNegociacaoStatus.propostaAceitaPendenteEntrada:
        bgColor = Colors.deepOrange;
        icon = Icons.payment;
        label = 'Aguardando entrada';
        break;
      case EncomendaNegociacaoStatus.entradaAguardandoPagamento:
        bgColor = Colors.deepOrange;
        icon = Icons.credit_card;
        label = 'Entrada pendente';
        break;
      case EncomendaNegociacaoStatus.entradaPagaEmProducao:
        bgColor = Colors.teal;
        icon = Icons.build;
        label = 'Em produção';
        break;
      case EncomendaNegociacaoStatus.saldoFinalAguardandoPgto:
        bgColor = Colors.deepOrange;
        icon = Icons.shopping_cart_checkout;
        label = 'Saldo pendente';
        break;
      case EncomendaNegociacaoStatus.emExecucaoLogistica:
        bgColor = Colors.green;
        icon = Icons.local_shipping;
        label = 'Em entrega';
        break;
      case EncomendaNegociacaoStatus.encerradaRecusadaLoja:
        bgColor = Colors.red.shade700;
        icon = Icons.close;
        label = 'Recusada';
        break;
      case EncomendaNegociacaoStatus.encerradaCanceladaCliente:
        bgColor = Colors.red.shade600;
        icon = Icons.cancel;
        label = 'Cancelada pelo cliente';
        break;
      case EncomendaNegociacaoStatus.encerradaCanceladaLoja:
        bgColor = Colors.red.shade700;
        icon = Icons.cancel;
        label = 'Cancelada pela loja';
        break;
      default:
        bgColor = Colors.grey.shade500;
        icon = Icons.info;
        label = status;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: bgColor.withOpacity(0.3),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: textColor, size: 14),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: textColor,
              fontWeight: FontWeight.w600,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  /// Card de encomenda na lista
  Widget _buildEncomendaCard(
    BuildContext context,
    DocumentSnapshot doc,
    Map<String, dynamic> data,
  ) {
    final st = (data['status_negociacao'] ?? '').toString();
    final atualizado = data['atualizado_em'];
    String quando = '';
    if (atualizado is Timestamp) {
      quando = _fmtData.format(atualizado.toDate());
    }
    final nomeCli = (data['cliente_nome_snapshot'] ?? 'Cliente').toString();
    final totalRef = (data['valor_total_referencia'] is num)
        ? (data['valor_total_referencia'] as num).toDouble()
        : null;
    final itensCount = (data['itens'] is List)
        ? (data['itens'] as List).length
        : 0;

    // Determina se há ação pendente da loja
    final temAcaoLoja =
        st == EncomendaNegociacaoStatus.aguardandoNegociacao ||
        st == EncomendaNegociacaoStatus.aguardandoRespostaLojaContraproposta ||
        st == EncomendaNegociacaoStatus.entradaPagaEmProducao;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: temAcaoLoja ? _laranja.withOpacity(0.4) : Colors.grey.shade200,
          width: temAcaoLoja ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: temAcaoLoja
                ? _laranja.withOpacity(0.1)
                : Colors.grey.withOpacity(0.06),
            blurRadius: temAcaoLoja ? 8 : 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            Navigator.push<void>(
              context,
              MaterialPageRoute<void>(
                builder: (_) => LojistaEncomendaDetalheScreen(
                  encomendaId: doc.id,
                  uidLoja: widget.uidLoja,
                ),
              ),
            );
          },
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Linha superior: nome do cliente + badge
                Row(
                  children: [
                    // Avatar do cliente
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: _roxoClaro,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(Icons.person, color: _roxo, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            nomeCli,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                              color: Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 2),
                          if (quando.isNotEmpty)
                            Text(
                              'Atualizado $quando',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey.shade600,
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    _buildStatusBadge(st),
                  ],
                ),

                const SizedBox(height: 12),

                // Linha de informações: total e itens
                Row(
                  children: [
                    // Total
                    if (totalRef != null && totalRef > 0)
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: _laranja.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Total',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: _laranja.withOpacity(0.8),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              Text(
                                NumberFormat.currency(
                                  locale: 'pt_BR',
                                  symbol: r'R$',
                                ).format(totalRef),
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: _laranja,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                    if (totalRef != null && totalRef > 0)
                      const SizedBox(width: 8),

                    // Itens
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: _roxoClaro,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Itens',
                              style: TextStyle(
                                fontSize: 10,
                                color: _roxo.withOpacity(0.8),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            Text(
                              '$itensCount ${itensCount == 1 ? "produto" : "produtos"}',
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: _roxo,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),

                // Indicador de ação pendente
                if (temAcaoLoja) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: _laranja.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: _laranja.withOpacity(0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.notifications_active,
                          size: 14,
                          color: _laranja,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Ação necessária',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: _laranja,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Header com busca e resumo geral.
  Widget _buildHeaderComContagem(int total, int filtrados) {
    final filtroAtivo = _filtroBusca.trim().isNotEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          const Text(
            'Negociações',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: Colors.black87,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: _roxo,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '$total',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
          const Spacer(),
          IconButton.filledTonal(
            tooltip: 'Filtrar por cliente, CPF ou código',
            onPressed: _abrirFiltroBusca,
            style: IconButton.styleFrom(
              backgroundColor: filtroAtivo ? _laranja : _roxoClaro,
              foregroundColor: filtroAtivo ? Colors.white : _roxo,
            ),
            icon: Icon(filtroAtivo ? Icons.filter_alt : Icons.search),
          ),
          if (filtroAtivo) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              decoration: BoxDecoration(
                color: _laranja.withOpacity(0.12),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: _laranja.withOpacity(0.25)),
              ),
              child: Text(
                '$filtrados/$total',
                style: const TextStyle(
                  color: _laranja,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFiltroVazio() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(22),
              decoration: const BoxDecoration(
                color: _roxoClaro,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.search_off, color: _roxo, size: 44),
            ),
            const SizedBox(height: 18),
            const Text(
              'Nenhuma encomenda encontrada',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Tente buscar por outro nome, CPF ou código do pedido.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600, height: 1.35),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => setState(() => _filtroBusca = ''),
              icon: const Icon(Icons.close),
              label: const Text('Limpar filtro'),
              style: FilledButton.styleFrom(
                backgroundColor: _roxo,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tabLabel(_AbaEncomendaConfig config, int count) {
    return Tab(
      height: 58,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(config.icon, size: 16),
              const SizedBox(width: 5),
              Text(config.titulo, maxLines: 1, overflow: TextOverflow.ellipsis),
              if (count > 0) ...[
                const SizedBox(width: 5),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: config.color,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    count > 99 ? '99+' : '$count',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 2),
          Text(
            config.subtitulo,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  Widget _buildAbaLista(
    _AbaEncomendaConfig config,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    if (docs.isEmpty) {
      return _buildAbaVazia(config);
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: docs.length,
      separatorBuilder: (_, __) => const SizedBox(height: 4),
      itemBuilder: (context, i) {
        final doc = docs[i];
        final m = doc.data();
        return _buildEncomendaCard(context, doc, m);
      },
    );
  }

  Widget _buildAbaVazia(_AbaEncomendaConfig config) {
    String texto;
    switch (config.tipo) {
      case _AbaEncomenda.aguardando:
        texto = 'Nenhuma encomenda aguardando aprovação no momento.';
        break;
      case _AbaEncomenda.andamento:
        texto =
            'Quando o cliente pagar a entrada aceita, a encomenda aparece aqui.';
        break;
      case _AbaEncomenda.finalizados:
        texto = 'Pedidos entregues e confirmados pelo código aparecerão aqui.';
        break;
      case _AbaEncomenda.cancelados:
        texto = 'Encomendas canceladas ou encerradas aparecerão aqui.';
        break;
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: config.color.withOpacity(0.10),
                shape: BoxShape.circle,
              ),
              child: Icon(config.icon, color: config.color, size: 44),
            ),
            const SizedBox(height: 18),
            Text(
              config.titulo,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              texto,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600, height: 1.35),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: _abas.length,
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F5F5),
        appBar: AppBar(
          backgroundColor: _roxo,
          foregroundColor: Colors.white,
          elevation: 0,
          title: const Text(
            'Pedidos de nova encomenda',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          centerTitle: true,
        ),
        body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('encomendas')
              .where('loja_id', isEqualTo: widget.uidLoja)
              .orderBy('atualizado_em', descending: true)
              .limit(80)
              .snapshots(),
          builder: (context, snap) {
            if (snap.hasError) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: 48,
                      color: Colors.grey.shade400,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Erro ao carregar: ${snap.error}',
                      style: TextStyle(color: Colors.grey.shade600),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              );
            }
            if (!snap.hasData) {
              return const Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(_roxo),
                ),
              );
            }
            final docs = snap.data!.docs;

            if (docs.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: _roxoClaro,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.handshake,
                        size: 48,
                        color: _roxo.withOpacity(0.6),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Nenhuma negociação de encomenda',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Quando um cliente solicitar uma encomenda,\nela aparecerá aqui.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade500,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              );
            }

            return StreamBuilder<Map<String, String>>(
              stream: _streamStatusPedidosVinculados(docs),
              builder: (context, pedidosSnap) {
                final statusPedidos = pedidosSnap.data ?? <String, String>{};

                final docsFiltrados = _filtrarDocs(docs);
                final grupos = _agruparPorAba(docsFiltrados, statusPedidos);
                final gruposTotais = _agruparPorAba(docs, statusPedidos);

                return Column(
                  children: [
                    _buildHeaderComContagem(docs.length, docsFiltrados.length),
                    if (_filtroBusca.trim().isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: _laranja.withOpacity(0.22),
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.filter_alt,
                                color: _laranja,
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Filtro: "$_filtroBusca"',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.black87,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              TextButton(
                                onPressed: () =>
                                    setState(() => _filtroBusca = ''),
                                style: TextButton.styleFrom(
                                  foregroundColor: Colors.red.shade700,
                                  visualDensity: VisualDensity.compact,
                                ),
                                child: const Text('Limpar'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 14,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(18),
                        child: TabBar(
                          isScrollable: true,
                          labelColor: _roxo,
                          unselectedLabelColor: Colors.grey.shade600,
                          indicatorColor: _laranja,
                          indicatorWeight: 3,
                          labelStyle: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 12,
                          ),
                          tabs: [
                            for (final config in _abas)
                              _tabLabel(
                                config,
                                gruposTotais[config.tipo]?.length ?? 0,
                              ),
                          ],
                        ),
                      ),
                    ),
                    Expanded(
                      child: docsFiltrados.isEmpty
                          ? _buildFiltroVazio()
                          : TabBarView(
                              children: [
                                for (final config in _abas)
                                  _buildAbaLista(
                                    config,
                                    grupos[config.tipo] ?? const [],
                                  ),
                              ],
                            ),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _FiltroDicaChip extends StatelessWidget {
  const _FiltroDicaChip({required this.icon, required this.texto});

  final IconData icon;
  final String texto;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFF3E5F5),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFE1BEE7)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: const Color(0xFF6A1B9A)),
          const SizedBox(width: 5),
          Text(
            texto,
            style: const TextStyle(
              color: Color(0xFF6A1B9A),
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

enum _AbaEncomenda { aguardando, andamento, finalizados, cancelados }

class _AbaEncomendaConfig {
  const _AbaEncomendaConfig({
    required this.tipo,
    required this.titulo,
    required this.subtitulo,
    required this.icon,
    required this.color,
  });

  final _AbaEncomenda tipo;
  final String titulo;
  final String subtitulo;
  final IconData icon;
  final Color color;
}
