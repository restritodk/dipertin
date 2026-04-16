import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:depertin_web/theme/painel_admin_theme.dart';
import 'package:depertin_web/widgets/botao_suporte_flutuante.dart';
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

  final _termosTituloC = TextEditingController();
  final _termosConteudoC = TextEditingController();
  final _privacidadeTituloC = TextEditingController();
  final _privacidadeConteudoC = TextEditingController();

  bool _salvandoTermos = false;
  bool _salvandoPrivacidade = false;
  bool _carregado = false;

  String _termosUltimaAtualizacao = '';
  String _privacidadeUltimaAtualizacao = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _carregarConteudo();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _termosTituloC.dispose();
    _termosConteudoC.dispose();
    _privacidadeTituloC.dispose();
    _privacidadeConteudoC.dispose();
    super.dispose();
  }

  Future<void> _carregarConteudo() async {
    try {
      final col = FirebaseFirestore.instance.collection('conteudo_legal');
      final termos = await col.doc('termos').get();
      final privacidade = await col.doc('privacidade').get();

      if (termos.exists) {
        final d = termos.data()!;
        _termosTituloC.text = d['titulo'] ?? 'Termos de Uso';
        _termosConteudoC.text = d['conteudo'] ?? '';
        final ts = d['data_atualizacao'] as Timestamp?;
        if (ts != null) {
          _termosUltimaAtualizacao =
              DateFormat('dd/MM/yyyy HH:mm').format(ts.toDate());
        }
      } else {
        _termosTituloC.text = 'Termos de Uso';
      }

      if (privacidade.exists) {
        final d = privacidade.data()!;
        _privacidadeTituloC.text = d['titulo'] ?? 'Política de Privacidade';
        _privacidadeConteudoC.text = d['conteudo'] ?? '';
        final ts = d['data_atualizacao'] as Timestamp?;
        if (ts != null) {
          _privacidadeUltimaAtualizacao =
              DateFormat('dd/MM/yyyy HH:mm').format(ts.toDate());
        }
      } else {
        _privacidadeTituloC.text = 'Política de Privacidade';
      }

      if (mounted) setState(() => _carregado = true);
    } catch (e) {
      if (mounted) setState(() => _carregado = true);
    }
  }

  Future<void> _salvarTermos() async {
    setState(() => _salvandoTermos = true);
    try {
      await FirebaseFirestore.instance
          .collection('conteudo_legal')
          .doc('termos')
          .set({
        'titulo': _termosTituloC.text.trim(),
        'conteudo': _termosConteudoC.text.trim(),
        'data_atualizacao': FieldValue.serverTimestamp(),
      });
      final now = DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now());
      if (mounted) {
        setState(() => _termosUltimaAtualizacao = now);
        _snack('Termos de Uso salvos com sucesso!');
      }
    } catch (e) {
      if (mounted) _snack('Erro ao salvar: $e', erro: true);
    } finally {
      if (mounted) setState(() => _salvandoTermos = false);
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
        _snack('Política de Privacidade salva com sucesso!');
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
                        'Edite os Termos de Uso e a Política de Privacidade exibidos no app.',
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
                        icon: Icon(Icons.description_outlined),
                        height: 72,
                        text: 'Termos de Uso'),
                    Tab(
                        icon: Icon(Icons.privacy_tip_outlined),
                        height: 72,
                        text: 'Política de Privacidade'),
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
                        tituloC: _termosTituloC,
                        conteudoC: _termosConteudoC,
                        ultimaAtualizacao: _termosUltimaAtualizacao,
                        onSalvar: _salvarTermos,
                        salvando: _salvandoTermos,
                        placeholder:
                            'Digite aqui o texto completo dos Termos de Uso...\n\n'
                            '1. Aceitação dos Termos\n\n'
                            '2. Uso da Plataforma\n\n'
                            '3. Responsabilidades\n\n'
                            '4. Disposições Gerais',
                      ),
                      _buildEditor(
                        tituloC: _privacidadeTituloC,
                        conteudoC: _privacidadeConteudoC,
                        ultimaAtualizacao: _privacidadeUltimaAtualizacao,
                        onSalvar: _salvarPrivacidade,
                        salvando: _salvandoPrivacidade,
                        placeholder:
                            'Digite aqui o texto completo da Política de Privacidade...\n\n'
                            '1. Dados Coletados\n\n'
                            '2. Uso dos Dados\n\n'
                            '3. Compartilhamento\n\n'
                            '4. Seus Direitos',
                      ),
                    ],
                  ),
          ),
        ],
      ),
      floatingActionButton: const BotaoSuporteFlutuante(),
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
