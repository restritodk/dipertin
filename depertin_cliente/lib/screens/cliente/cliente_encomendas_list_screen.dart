import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../constants/encomenda_negociacao_status.dart';
import '../../utils/safe_area_insets.dart';
import '../../widgets/dipertin_safe_bottom_panel.dart';
import 'cliente_encomenda_detalhe_screen.dart';

enum _FiltroEncomendas { ativas, todas, encerradas }

class _StatusVisual {
  final String rotulo;
  final String descricao;
  final Color cor;
  final Color fundo;
  final IconData icone;

  const _StatusVisual({
    required this.rotulo,
    required this.descricao,
    required this.cor,
    required this.fundo,
    required this.icone,
  });
}

/// Lista encomendas do cliente autenticado (`encomendas.cliente_id`).
class ClienteEncomendasListScreen extends StatefulWidget {
  const ClienteEncomendasListScreen({super.key});

  @override
  State<ClienteEncomendasListScreen> createState() =>
      _ClienteEncomendasListScreenState();
}

class _ClienteEncomendasListScreenState
    extends State<ClienteEncomendasListScreen> {
  _FiltroEncomendas _filtro = _FiltroEncomendas.ativas;
  bool _entradaAnimada = false;

  static final DateFormat _fmtData = DateFormat('dd/MM/yyyy HH:mm', 'pt_BR');
  static final NumberFormat _moeda = NumberFormat.currency(
    locale: 'pt_BR',
    symbol: r'R$',
  );

  static const Color _roxo = Color(0xFF6A1B9A);
  static const Color _laranja = Color(0xFFFF8F00);
  static const Color _fundoTela = Color(0xFFF5F4F8);
  static const Color _textoPrimario = Color(0xFF1A1A2E);
  static const Color _textoMuted = Color(0xFF64748B);
  static const Color _bordaCampo = Color(0xFFE0DEE8);
  static const Color _verdeStatus = Color(0xFF2E7D32);
  static const Color _vermelhoStatus = Color(0xFFC62828);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _entradaAnimada = true);
    });
  }

  BoxDecoration _decorCartaoPro({bool destacado = false}) {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      boxShadow: [
        BoxShadow(
          color: _roxo.withValues(alpha: 0.06),
          blurRadius: 20,
          offset: const Offset(0, 6),
        ),
      ],
      border: Border.all(
        color: destacado
            ? _roxo.withValues(alpha: 0.15)
            : _bordaCampo,
      ),
    );
  }

  static String _statusDe(Map<String, dynamic> m) {
    return (m['status_negociacao'] ?? '').toString();
  }

  static bool _aguardandoPagamento(String st) {
    return st == EncomendaNegociacaoStatus.entradaAguardandoPagamento ||
        st == EncomendaNegociacaoStatus.saldoFinalAguardandoPgto ||
        st == EncomendaNegociacaoStatus.propostaAceitaPendenteEntrada;
  }

  static bool _emNegociacao(String st) {
    if (EncomendaNegociacaoStatus.encerradaDefinitivamente(st)) return false;
    if (_aguardandoPagamento(st)) return false;
    if (st == EncomendaNegociacaoStatus.entradaPagaEmProducao ||
        st == EncomendaNegociacaoStatus.emExecucaoLogistica) {
      return false;
    }
    return true;
  }

  static bool _emProducaoOuEntrega(String st) {
    return st == EncomendaNegociacaoStatus.entradaPagaEmProducao ||
        st == EncomendaNegociacaoStatus.emExecucaoLogistica;
  }

  static ({int negociacao, int aguardandoPagamento, int producaoEntrega})
  _calcularKpis(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    var negociacao = 0;
    var aguardandoPag = 0;
    var producaoEntrega = 0;
    for (final d in docs) {
      final st = _statusDe(d.data());
      if (_emNegociacao(st)) negociacao++;
      if (_aguardandoPagamento(st)) aguardandoPag++;
      if (_emProducaoOuEntrega(st)) producaoEntrega++;
    }
    return (
      negociacao: negociacao,
      aguardandoPagamento: aguardandoPag,
      producaoEntrega: producaoEntrega,
    );
  }

  static int _contarAtivas(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    return docs
        .where(
          (d) => !EncomendaNegociacaoStatus.encerradaDefinitivamente(
            _statusDe(d.data()),
          ),
        )
        .length;
  }

  static int _contarEncerradas(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    return docs
        .where(
          (d) => EncomendaNegociacaoStatus.encerradaDefinitivamente(
            _statusDe(d.data()),
          ),
        )
        .length;
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _filtrarDocs(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    switch (_filtro) {
      case _FiltroEncomendas.ativas:
        return docs
            .where(
              (d) => !EncomendaNegociacaoStatus.encerradaDefinitivamente(
                _statusDe(d.data()),
              ),
            )
            .toList();
      case _FiltroEncomendas.encerradas:
        return docs
            .where(
              (d) => EncomendaNegociacaoStatus.encerradaDefinitivamente(
                _statusDe(d.data()),
              ),
            )
            .toList();
      case _FiltroEncomendas.todas:
        return docs;
    }
  }

  _StatusVisual _statusVisual(String st) {
    switch (st) {
      case EncomendaNegociacaoStatus.aguardandoNegociacao:
      case EncomendaNegociacaoStatus.negociacaoEmAndamento:
      case EncomendaNegociacaoStatus.aguardandoRespostaLojaContraproposta:
        return _StatusVisual(
          rotulo: EncomendaNegociacaoStatus.rotuloPt(st),
          descricao: 'A loja está analisando sua solicitação.',
          cor: _roxo,
          fundo: const Color(0xFFF3E5F5),
          icone: Icons.handshake_rounded,
        );
      case EncomendaNegociacaoStatus.propostaEnviada:
      case EncomendaNegociacaoStatus.propostaAceitaPendenteEntrada:
        return _StatusVisual(
          rotulo: EncomendaNegociacaoStatus.rotuloPt(st),
          descricao: 'Revise a proposta e conclua a entrada.',
          cor: _laranja,
          fundo: const Color(0xFFFFF3E0),
          icone: Icons.payments_rounded,
        );
      case EncomendaNegociacaoStatus.entradaAguardandoPagamento:
        return _StatusVisual(
          rotulo: 'Entrada pendente',
          descricao: 'A entrada precisa ser paga para iniciar a produção.',
          cor: _laranja,
          fundo: const Color(0xFFFFF3E0),
          icone: Icons.pix_rounded,
        );
      case EncomendaNegociacaoStatus.entradaPagaEmProducao:
        return _StatusVisual(
          rotulo: 'Em produção',
          descricao: 'Entrada paga. A loja está preparando sua encomenda.',
          cor: _roxo,
          fundo: const Color(0xFFF3E5F5),
          icone: Icons.inventory_2_rounded,
        );
      case EncomendaNegociacaoStatus.saldoFinalAguardandoPgto:
        return _StatusVisual(
          rotulo: 'Saldo liberado',
          descricao: 'A loja liberou o pagamento do saldo restante.',
          cor: _laranja,
          fundo: const Color(0xFFFFF3E0),
          icone: Icons.account_balance_wallet_rounded,
        );
      case EncomendaNegociacaoStatus.emExecucaoLogistica:
        return _StatusVisual(
          rotulo: 'Em andamento',
          descricao: 'Saldo pago. Acompanhe a entrega em Meus pedidos.',
          cor: _verdeStatus,
          fundo: const Color(0xFFE8F5E9),
          icone: Icons.local_shipping_rounded,
        );
      case EncomendaNegociacaoStatus.encerradaRecusadaLoja:
      case EncomendaNegociacaoStatus.encerradaCanceladaCliente:
      case EncomendaNegociacaoStatus.encerradaCanceladaLoja:
        return _StatusVisual(
          rotulo: EncomendaNegociacaoStatus.rotuloPt(st),
          descricao: 'Esta negociação foi encerrada.',
          cor: _vermelhoStatus,
          fundo: const Color(0xFFFFEBEE),
          icone: Icons.cancel_outlined,
        );
      default:
        return _StatusVisual(
          rotulo: EncomendaNegociacaoStatus.rotuloPt(st),
          descricao: 'Toque para ver os detalhes da negociação.',
          cor: _textoMuted,
          fundo: const Color(0xFFF5F4F8),
          icone: Icons.receipt_long_rounded,
        );
    }
  }

  double _num(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 0;
  }

  String _textoItens(Map<String, dynamic> m) {
    final itens = m['itens'];
    if (itens is! List || itens.isEmpty) return 'Itens da encomenda';
    final nomes = itens
        .whereType<Map>()
        .map((e) => (e['nome'] ?? '').toString().trim())
        .where((e) => e.isNotEmpty)
        .take(2)
        .toList();
    if (nomes.isEmpty) return '${itens.length} item(ns) sob encomenda';
    final extra = itens.length > nomes.length
        ? ' +${itens.length - nomes.length}'
        : '';
    return '${nomes.join(', ')}$extra';
  }

  String _dataTexto(dynamic ts) {
    if (ts is Timestamp) return _fmtData.format(ts.toDate());
    return 'Atualizado recentemente';
  }

  String _lojaNome(Map<String, dynamic> m) {
    final nome = (m['loja_nome_snapshot'] ?? m['loja_nome'] ?? m['nome_loja'] ?? '')
        .toString()
        .trim();
    return nome.isEmpty ? 'Loja' : nome;
  }

  void _mostrarComoFuncionaEncomenda() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: _fundoTela,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(20, 12, 20, 20 + diPertinSafeAreaBottom(ctx)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: _bordaCampo,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Como funciona a encomenda',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: _textoPrimario,
              ),
            ),
            const SizedBox(height: 14),
            _passoOrientacao(
              numero: 1,
              titulo: 'Escolha na vitrine',
              subtitulo: 'Produtos com selo Encomenda — valor a combinar.',
            ),
            _passoOrientacao(
              numero: 2,
              titulo: 'Negocie com a loja',
              subtitulo: 'A loja envia proposta com total, entrada e prazo.',
            ),
            _passoOrientacao(
              numero: 3,
              titulo: 'Pague entrada e saldo',
              subtitulo: 'Dois pagamentos: entrada (produção) e saldo (entrega).',
            ),
            _passoOrientacao(
              numero: 4,
              titulo: 'Acompanhe aqui',
              subtitulo: 'Status, chat e pagamentos ficam nesta lista.',
            ),
          ],
        ),
      ),
    );
  }

  Widget _passoOrientacao({
    required int numero,
    required String titulo,
    required String subtitulo,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _roxo.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Text(
              '$numero',
              style: const TextStyle(
                color: _roxo,
                fontWeight: FontWeight.w800,
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titulo,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: _textoPrimario,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitulo,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: _textoMuted,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniHeroKpis({
    required int negociacao,
    required int aguardandoPagamento,
    required int producaoEntrega,
  }) {
    Widget kpi(String rotulo, int valor, {Color? corValor}) {
      return Expanded(
        child: Column(
          children: [
            Text(
              '$valor',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: corValor ?? Colors.white,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              rotulo,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: Colors.white.withValues(alpha: 0.82),
                height: 1.25,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF4A148C), _roxo, Color(0xFF8E24AA)],
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: _roxo.withValues(alpha: 0.22),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Resumo das encomendas',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              TextButton(
                onPressed: _mostrarComoFuncionaEncomenda,
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text(
                  'Como funciona',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              kpi('Em negociação', negociacao),
              Container(
                width: 1,
                height: 36,
                color: Colors.white.withValues(alpha: 0.22),
              ),
              kpi(
                'Aguard. pagamento',
                aguardandoPagamento,
                corValor: aguardandoPagamento > 0 ? _laranja : Colors.white,
              ),
              Container(
                width: 1,
                height: 36,
                color: Colors.white.withValues(alpha: 0.22),
              ),
              kpi(
                'Produção/entrega',
                producaoEntrega,
                corValor: const Color(0xFFA5D6A7),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chipFiltro({
    required String rotulo,
    required int contagem,
    required bool selecionado,
    required VoidCallback onTap,
  }) {
    return Material(
      color: selecionado
          ? _laranja.withValues(alpha: 0.12)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selecionado
                  ? _laranja.withValues(alpha: 0.55)
                  : _roxo.withValues(alpha: 0.2),
              width: selecionado ? 1.5 : 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                selecionado
                    ? Icons.check_circle_rounded
                    : Icons.circle_outlined,
                size: 15,
                color: selecionado ? _laranja : _textoMuted,
              ),
              const SizedBox(height: 4),
              Text(
                rotulo,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  color: selecionado ? _laranja : _textoPrimario,
                ),
              ),
              Text(
                '($contagem)',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: selecionado ? _laranja : _textoMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFiltrosChips({
    required int qtdAtivas,
    required int qtdTodos,
    required int qtdEncerradas,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: _decorCartaoPro(),
        child: Row(
          children: [
            Expanded(
              child: _chipFiltro(
                rotulo: 'Ativas',
                contagem: qtdAtivas,
                selecionado: _filtro == _FiltroEncomendas.ativas,
                onTap: () => setState(() => _filtro = _FiltroEncomendas.ativas),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _chipFiltro(
                rotulo: 'Todas',
                contagem: qtdTodos,
                selecionado: _filtro == _FiltroEncomendas.todas,
                onTap: () => setState(() => _filtro = _FiltroEncomendas.todas),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _chipFiltro(
                rotulo: 'Encerradas',
                contagem: qtdEncerradas,
                selecionado: _filtro == _FiltroEncomendas.encerradas,
                onTap: () =>
                    setState(() => _filtro = _FiltroEncomendas.encerradas),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSkeletonCarregamento() {
    Widget cardSkeleton() {
      return Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: _decorCartaoPro(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 52,
              decoration: BoxDecoration(
                color: _bordaCampo,
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            const SizedBox(height: 14),
            Container(
              height: 14,
              width: double.infinity,
              decoration: BoxDecoration(
                color: _bordaCampo,
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            const SizedBox(height: 8),
            Container(
              height: 36,
              decoration: BoxDecoration(
                color: _bordaCampo,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ],
        ),
      );
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [for (var i = 0; i < 3; i++) cardSkeleton()],
    );
  }

  Widget _buildErroCarregamento() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Container(
          padding: const EdgeInsets.all(22),
          decoration: _decorCartaoPro(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.cloud_off_outlined,
                size: 48,
                color: _vermelhoStatus.withValues(alpha: 0.85),
              ),
              const SizedBox(height: 14),
              const Text(
                'Não foi possível carregar',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: _textoPrimario,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Verifique a conexão e tente novamente.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.4,
                  color: _textoMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeroVazio() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF4A148C), _roxo, Color(0xFF8E24AA)],
        ),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  _laranja.withValues(alpha: 0.2),
                  Colors.transparent,
                ],
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.12),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Icon(
              Icons.handshake_outlined,
              size: 52,
              color: _laranja.withValues(alpha: 0.9),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyNunca() {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeroVazio(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 22, 20, 16),
                  child: Column(
                    children: [
                      const Text(
                        'Nenhuma encomenda ainda',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: _textoPrimario,
                          letterSpacing: -0.4,
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Produtos sob medida com valor a combinar com a loja. '
                        'Tudo o que você solicitar aparecerá aqui.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 15,
                          height: 1.45,
                          color: _textoMuted,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF3E0),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: _laranja.withValues(alpha: 0.25),
                          ),
                        ),
                        child: const Text(
                          'Encomenda · valor a combinar com a loja',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: _laranja,
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                        decoration: _decorCartaoPro(),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text(
                              'Como funciona',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: _textoPrimario,
                              ),
                            ),
                            _passoOrientacao(
                              numero: 1,
                              titulo: 'Escolha na vitrine',
                              subtitulo:
                                  'Produtos com selo Encomenda na loja.',
                            ),
                            _passoOrientacao(
                              numero: 2,
                              titulo: 'Negocie com a loja',
                              subtitulo:
                                  'Proposta com total, entrada e prazo.',
                            ),
                            _passoOrientacao(
                              numero: 3,
                              titulo: 'Pague e acompanhe',
                              subtitulo:
                                  'Entrada, produção, saldo e entrega.',
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        DiPertinSafeBottomPanel(
          child: SizedBox(
            height: 52,
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => Navigator.of(context).pushNamed('/home'),
              icon: const Icon(Icons.storefront_outlined),
              label: const Text(
                'Explorar vitrine',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: _laranja,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyFiltro({
    required int qtdTodos,
    required int qtdEncerradas,
  }) {
    final irEncerradas = _filtro == _FiltroEncomendas.ativas && qtdEncerradas > 0;
    final irTodas = _filtro == _FiltroEncomendas.ativas && qtdEncerradas == 0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 32, 20, 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(28),
            decoration: _decorCartaoPro(),
            child: Column(
              children: [
                Icon(
                  _filtro == _FiltroEncomendas.encerradas
                      ? Icons.archive_outlined
                      : Icons.check_circle_outline,
                  size: 64,
                  color: _filtro == _FiltroEncomendas.encerradas
                      ? _textoMuted
                      : _verdeStatus.withValues(alpha: 0.85),
                ),
                const SizedBox(height: 16),
                Text(
                  _filtro == _FiltroEncomendas.encerradas
                      ? 'Nenhuma encomenda encerrada'
                      : 'Nenhuma encomenda ativa',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: _textoPrimario,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  _filtro == _FiltroEncomendas.encerradas
                      ? 'Negociações canceladas ou recusadas aparecerão aqui.'
                      : irEncerradas
                      ? 'Suas negociações ativas foram concluídas. '
                            'Veja o histórico em Encerradas ou Todas.'
                      : 'Quando você solicitar uma encomenda, ela aparecerá em Ativas.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1.45,
                    color: _textoMuted,
                  ),
                ),
                if (irEncerradas || irTodas) ...[
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: _chipFiltro(
                      rotulo: irEncerradas ? 'Encerradas' : 'Todas',
                      contagem: irEncerradas ? qtdEncerradas : qtdTodos,
                      selecionado: false,
                      onTap: () => setState(() {
                        _filtro = irEncerradas
                            ? _FiltroEncomendas.encerradas
                            : _FiltroEncomendas.todas;
                      }),
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

  Widget _infoPill({
    required IconData icon,
    required String rotulo,
    required String valor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: _fundoTela,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _bordaCampo),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: _roxo),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              '$rotulo: $valor',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: _textoPrimario,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCard(
    BuildContext context,
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final m = doc.data();
    final st = _statusDe(m);
    final visual = _statusVisual(st);
    final loja = _lojaNome(m);
    final total = _num(m['valor_total_referencia']);
    final entrada = _num(m['valor_entrada_loja']);
    final restante = total > 0 && entrada > 0
        ? (total - entrada).clamp(0, total)
        : 0;
    final codigo = doc.id.length > 6
        ? doc.id.substring(doc.id.length - 6).toUpperCase()
        : doc.id.toUpperCase();

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          Navigator.push<void>(
            context,
            MaterialPageRoute<void>(
              builder: (_) => ClienteEncomendaDetalheScreen(encomendaId: doc.id),
            ),
          );
        },
        child: Container(
          decoration: _decorCartaoPro(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: visual.fundo,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(16),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: visual.cor.withValues(alpha: 0.13),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(visual.icone, color: visual.cor, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            visual.rotulo,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: visual.cor,
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            visual.descricao,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: _textoMuted,
                              fontSize: 12,
                              height: 1.25,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right_rounded, color: _roxo),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            loja,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: _textoPrimario,
                            ),
                          ),
                        ),
                        Text(
                          '#$codigo',
                          style: const TextStyle(
                            color: _textoMuted,
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _textoItens(m),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _textoMuted,
                        height: 1.35,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (total > 0)
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _infoPill(
                            icon: Icons.receipt_long_rounded,
                            rotulo: 'Total',
                            valor: _moeda.format(total),
                          ),
                          if (entrada > 0)
                            _infoPill(
                              icon: Icons.payments_rounded,
                              rotulo: 'Entrada',
                              valor: _moeda.format(entrada),
                            ),
                          if (restante > 0)
                            _infoPill(
                              icon: Icons.account_balance_wallet_rounded,
                              rotulo: 'Saldo',
                              valor: _moeda.format(restante),
                            ),
                        ],
                      )
                    else
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF3E0),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: _laranja.withValues(alpha: 0.25),
                          ),
                        ),
                        child: const Text(
                          'Valor a combinar com a loja',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: _laranja,
                          ),
                        ),
                      ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Icon(
                          Icons.update_rounded,
                          size: 16,
                          color: _textoMuted,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            _dataTexto(m['atualizado_em']),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: _textoMuted,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const Text(
                          'Ver detalhes',
                          style: TextStyle(
                            color: _roxo,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
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
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return Scaffold(
      backgroundColor: _fundoTela,
      appBar: AppBar(
        backgroundColor: _roxo,
        foregroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Minhas encomendas',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 18,
                letterSpacing: -0.3,
              ),
            ),
            Text(
              'Negociação, entrada e saldo',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Colors.white70,
                height: 1.2,
              ),
            ),
          ],
        ),
      ),
      body: uid == null
          ? const Center(child: Text('Faça login para ver suas encomendas.'))
          : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('encomendas')
                  .where('cliente_id', isEqualTo: uid)
                  .orderBy('atualizado_em', descending: true)
                  .limit(50)
                  .snapshots(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting &&
                    !snap.hasData) {
                  return _buildSkeletonCarregamento();
                }
                if (snap.hasError) {
                  return _buildErroCarregamento();
                }
                if (!snap.hasData) {
                  return _buildSkeletonCarregamento();
                }

                final docs = snap.data!.docs;
                final kpis = _calcularKpis(docs);
                final qtdAtivas = _contarAtivas(docs);
                final qtdEncerradas = _contarEncerradas(docs);
                final filtrados = _filtrarDocs(docs);

                return AnimatedOpacity(
                  opacity: _entradaAnimada ? 1 : 0,
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOut,
                  child: RefreshIndicator(
                    color: _laranja,
                    onRefresh: () async {
                      await FirebaseFirestore.instance
                          .collection('encomendas')
                          .where('cliente_id', isEqualTo: uid)
                          .orderBy('atualizado_em', descending: true)
                          .limit(50)
                          .get(const GetOptions(source: Source.server));
                    },
                    child: CustomScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      slivers: [
                        if (docs.isNotEmpty) ...[
                          SliverToBoxAdapter(
                            child: _buildMiniHeroKpis(
                              negociacao: kpis.negociacao,
                              aguardandoPagamento: kpis.aguardandoPagamento,
                              producaoEntrega: kpis.producaoEntrega,
                            ),
                          ),
                          SliverToBoxAdapter(
                            child: _buildFiltrosChips(
                              qtdAtivas: qtdAtivas,
                              qtdTodos: docs.length,
                              qtdEncerradas: qtdEncerradas,
                            ),
                          ),
                        ],
                        if (docs.isEmpty)
                          SliverFillRemaining(
                            hasScrollBody: false,
                            child: _buildEmptyNunca(),
                          )
                        else if (filtrados.isEmpty)
                          SliverFillRemaining(
                            hasScrollBody: false,
                            child: _buildEmptyFiltro(
                              qtdTodos: docs.length,
                              qtdEncerradas: qtdEncerradas,
                            ),
                          )
                        else
                          SliverPadding(
                            padding: EdgeInsets.fromLTRB(
                              16,
                              4,
                              16,
                              24 + diPertinSafeAreaBottom(context),
                            ),
                            sliver: SliverList.separated(
                              itemCount: filtrados.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: 12),
                              itemBuilder: (context, i) {
                                return _buildCard(context, filtrados[i]);
                              },
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
