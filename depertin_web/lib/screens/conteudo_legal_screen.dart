import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:depertin_cliente/constants/conteudo_legal_padrao.dart';
import 'package:depertin_web/theme/painel_admin_theme.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class ConteudoLegalScreen extends StatefulWidget {
  const ConteudoLegalScreen({super.key});

  @override
  State<ConteudoLegalScreen> createState() => _ConteudoLegalScreenState();
}

class _ConteudoLegalScreenState extends State<ConteudoLegalScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  static const _roxo = PainelAdminTheme.roxo;
  static const _laranja = PainelAdminTheme.laranja;

  final _usoTituloC = TextEditingController();
  final _usoConteudoC = TextEditingController();
  final _compraTituloC = TextEditingController();
  final _compraConteudoC = TextEditingController();
  final _privacidadeTituloC = TextEditingController();
  final _privacidadeConteudoC = TextEditingController();

  bool _salvandoUso = false;
  bool _salvandoCompra = false;
  bool _salvandoPrivacidade = false;
  bool _carregado = false;

  String _usoUltimaAtualizacao = '';
  String _compraUltimaAtualizacao = '';
  String _privacidadeUltimaAtualizacao = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _carregarConteudo();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _usoTituloC.dispose();
    _usoConteudoC.dispose();
    _compraTituloC.dispose();
    _compraConteudoC.dispose();
    _privacidadeTituloC.dispose();
    _privacidadeConteudoC.dispose();
    super.dispose();
  }

  static String _tituloOuPadrao(Map<String, dynamic>? d, String padrao) {
    final v = d?['titulo'];
    if (v is String && v.trim().isNotEmpty) return v.trim();
    return padrao;
  }

  static String _conteudoOuPadrao(Map<String, dynamic>? d, String padraoConteudo) {
    final v = d?['conteudo'];
    if (v is String && v.trim().isNotEmpty) return v;
    return padraoConteudo;
  }

  static String? _formatTs(Map<String, dynamic>? d) {
    final ts = d?['data_atualizacao'];
    if (ts is Timestamp) {
      return DateFormat('dd/MM/yyyy HH:mm').format(ts.toDate());
    }
    return null;
  }

  void _aplicarPadraoLocalCompleto() {
    _usoTituloC.text = ConteudoLegalPadrao.tituloUsoPadrao;
    _usoConteudoC.text = ConteudoLegalPadrao.textoFirestoreUso();
    _compraTituloC.text = ConteudoLegalPadrao.tituloCompraPadrao;
    _compraConteudoC.text = ConteudoLegalPadrao.textoFirestoreCompra();
    _privacidadeTituloC.text = ConteudoLegalPadrao.tituloPrivacidadePadrao;
    _privacidadeConteudoC.text =
        ConteudoLegalPadrao.textoFirestorePrivacidade();
    _usoUltimaAtualizacao = '';
    _compraUltimaAtualizacao = '';
    _privacidadeUltimaAtualizacao = '';
  }

  Future<void> _carregarConteudo() async {
    try {
      final col = FirebaseFirestore.instance.collection('conteudo_legal');
      final uso = await col.doc('termos').get();
      final compra = await col.doc('compra').get();
      final privacidade = await col.doc('privacidade').get();

      final usoD = uso.data();
      _usoTituloC.text =
          _tituloOuPadrao(usoD, ConteudoLegalPadrao.tituloUsoPadrao);
      _usoConteudoC.text = _conteudoOuPadrao(
        usoD,
        ConteudoLegalPadrao.textoFirestoreUso(),
      );
      _usoUltimaAtualizacao = _formatTs(usoD) ?? '';

      final compraD = compra.data();
      _compraTituloC.text =
          _tituloOuPadrao(compraD, ConteudoLegalPadrao.tituloCompraPadrao);
      _compraConteudoC.text = _conteudoOuPadrao(
        compraD,
        ConteudoLegalPadrao.textoFirestoreCompra(),
      );
      _compraUltimaAtualizacao = _formatTs(compraD) ?? '';

      final privD = privacidade.data();
      _privacidadeTituloC.text = _tituloOuPadrao(
        privD,
        ConteudoLegalPadrao.tituloPrivacidadePadrao,
      );
      _privacidadeConteudoC.text = _conteudoOuPadrao(
        privD,
        ConteudoLegalPadrao.textoFirestorePrivacidade(),
      );
      _privacidadeUltimaAtualizacao = _formatTs(privD) ?? '';

      if (mounted) setState(() => _carregado = true);
    } catch (e) {
      _aplicarPadraoLocalCompleto();
      if (mounted) {
        setState(() => _carregado = true);
        _snack(
          'Não foi possível ler o Firestore ($e). Exibindo texto padrão do app — '
          'salve para publicar.',
          erro: true,
        );
      }
    }
  }

  Future<void> _salvarUso() async {
    setState(() => _salvandoUso = true);
    try {
      await FirebaseFirestore.instance
          .collection('conteudo_legal')
          .doc('termos')
          .set({
        'titulo': _usoTituloC.text.trim(),
        'conteudo': _usoConteudoC.text.trim(),
        'data_atualizacao': FieldValue.serverTimestamp(),
      });
      final now = DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now());
      if (mounted) {
        setState(() => _usoUltimaAtualizacao = now);
        _snack('Política de uso salva com sucesso!');
      }
    } catch (e) {
      if (mounted) _snack('Erro ao salvar: $e', erro: true);
    } finally {
      if (mounted) setState(() => _salvandoUso = false);
    }
  }

  Future<void> _salvarCompra() async {
    setState(() => _salvandoCompra = true);
    try {
      await FirebaseFirestore.instance
          .collection('conteudo_legal')
          .doc('compra')
          .set({
        'titulo': _compraTituloC.text.trim(),
        'conteudo': _compraConteudoC.text.trim(),
        'data_atualizacao': FieldValue.serverTimestamp(),
      });
      final now = DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now());
      if (mounted) {
        setState(() => _compraUltimaAtualizacao = now);
        _snack('Política de compra salva com sucesso!');
      }
    } catch (e) {
      if (mounted) _snack('Erro ao salvar: $e', erro: true);
    } finally {
      if (mounted) setState(() => _salvandoCompra = false);
    }
  }

  Future<void> _salvarPrivacidade() async {
    setState(() => _salvandoPrivacidade = true);
    try {
      await FirebaseFirestore.instance
          .collection('conteudo_legal')
          .doc('privacidade')
          .set({
        'titulo': _privacidadeTituloC.text.trim(),
        'conteudo': _privacidadeConteudoC.text.trim(),
        'data_atualizacao': FieldValue.serverTimestamp(),
      });
      final now = DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now());
      if (mounted) {
        setState(() => _privacidadeUltimaAtualizacao = now);
        _snack('Política de privacidade salva com sucesso!');
      }
    } catch (e) {
      if (mounted) _snack('Erro ao salvar: $e', erro: true);
    } finally {
      if (mounted) setState(() => _salvandoPrivacidade = false);
    }
  }

  void _snack(String msg, {bool erro = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor:
          erro ? const Color(0xFFB91C1C) : const Color(0xFF15803D),
      behavior: SnackBarBehavior.floating,
    ));
  }

  static const _hintSecoes =
      'Opcional: inicie linhas com ## e um espaço para título de capítulo '
      '(ex.: ## I — Objeto). O app exibirá cada bloco como uma seção.';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PainelAdminTheme.fundoCanvas,
      body: Column(
        children: [
          Material(
            color: Colors.white,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(28, 28, 28, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text(
                        'Conteúdo Legal',
                        style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            color: _roxo,
                            letterSpacing: -0.5),
                      ),
                      SizedBox(height: 6),
                      Text(
                        'Os três documentos abaixo são os mesmos do app (Política e privacidade). '
                        'Se o Firestore ainda não tiver texto, carregamos automaticamente a versão '
                        'igual à do aplicativo; salve cada aba para publicar. Depois disso, o app '
                        'atualiza em tempo real quando você salvar aqui.',
                        style: TextStyle(
                            color: PainelAdminTheme.textoSecundario,
                            fontSize: 15),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                TabBar(
                  controller: _tabController,
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  labelColor: _roxo,
                  unselectedLabelColor: PainelAdminTheme.textoSecundario,
                  indicatorColor: _laranja,
                  indicatorWeight: 3,
                  labelStyle: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 13),
                  unselectedLabelStyle: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 13),
                  tabs: const [
                    Tab(
                        icon: Icon(Icons.gavel_outlined),
                        height: 72,
                        text: 'Política de uso'),
                    Tab(
                        icon: Icon(Icons.shopping_bag_outlined),
                        height: 72,
                        text: 'Política de compra'),
                    Tab(
                        icon: Icon(Icons.privacy_tip_outlined),
                        height: 72,
                        text: 'Política de privacidade'),
                  ],
                ),
                Divider(height: 1, color: Colors.grey.shade200),
              ],
            ),
          ),
          Expanded(
            child: !_carregado
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(
                    controller: _tabController,
                    children: [
                      _buildEditor(
                        tituloC: _usoTituloC,
                        conteudoC: _usoConteudoC,
                        ultimaAtualizacao: _usoUltimaAtualizacao,
                        onSalvar: _salvarUso,
                        salvando: _salvandoUso,
                        placeholder:
                            '$_hintSecoes\n\n'
                            'Texto integral da Política de uso…',
                      ),
                      _buildEditor(
                        tituloC: _compraTituloC,
                        conteudoC: _compraConteudoC,
                        ultimaAtualizacao: _compraUltimaAtualizacao,
                        onSalvar: _salvarCompra,
                        salvando: _salvandoCompra,
                        placeholder:
                            '$_hintSecoes\n\n'
                            'Texto integral da Política de compra…',
                      ),
                      _buildEditor(
                        tituloC: _privacidadeTituloC,
                        conteudoC: _privacidadeConteudoC,
                        ultimaAtualizacao: _privacidadeUltimaAtualizacao,
                        onSalvar: _salvarPrivacidade,
                        salvando: _salvandoPrivacidade,
                        placeholder:
                            '$_hintSecoes\n\n'
                            'Texto integral da Política de privacidade…',
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEditor({
    required TextEditingController tituloC,
    required TextEditingController conteudoC,
    required String ultimaAtualizacao,
    required VoidCallback onSalvar,
    required bool salvando,
    required String placeholder,
  }) {
    final dec = InputDecoration(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300)),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _roxo, width: 1.5)),
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (ultimaAtualizacao.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Row(
                    children: [
                      Icon(Icons.history_rounded,
                          size: 15, color: Colors.grey.shade500),
                      const SizedBox(width: 6),
                      Text(
                        'Última atualização: $ultimaAtualizacao',
                        style: TextStyle(
                            fontSize: 13, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
              TextField(
                controller: tituloC,
                decoration: dec.copyWith(
                  labelText: 'Título do documento',
                  prefixIcon: Icon(Icons.title_rounded,
                      color: _roxo, size: 20),
                ),
                style: const TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 15),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: conteudoC,
                maxLines: 30,
                onChanged: (_) => setState(() {}),
                decoration: dec.copyWith(
                  labelText: 'Conteúdo',
                  hintText: placeholder,
                  alignLabelWithHint: true,
                ),
                style: const TextStyle(
                    fontSize: 14, height: 1.6, fontFamily: 'monospace'),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    '${conteudoC.text.length} caracteres',
                    style: TextStyle(
                        fontSize: 12, color: Colors.grey.shade500),
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: salvando ? null : onSalvar,
                    icon: salvando
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.save_rounded, size: 20),
                    label: Text(salvando ? 'Salvando…' : 'Salvar alterações'),
                    style: FilledButton.styleFrom(
                      backgroundColor: _laranja,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
