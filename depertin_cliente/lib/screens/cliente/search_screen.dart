import 'dart:async';

import 'package:depertin_cliente/screens/utilidades/achados_screen.dart';
import 'package:depertin_cliente/screens/utilidades/eventos_screen.dart';
import 'package:depertin_cliente/screens/utilidades/vagas_screen.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'chat_suporte_screen.dart';
import '../auth/login_screen.dart';
import '../../services/location_service.dart';
import '../../utils/safe_area_insets.dart';

const Color diPertinRoxo = Color(0xFF6A1B9A);
const Color diPertinLaranja = Color(0xFFFF8F00);
const Color _fundoTela = Color(0xFFF5F4F8);
const Color _textoPrimario = Color(0xFF1A1A2E);
const Color _textoMuted = Color(0xFF64748B);

class _SugestaoItem {
  final String titulo;
  final String? subtitulo;
  final IconData icone;
  final Color cor;
  final VoidCallback acao;
  _SugestaoItem({
    required this.titulo,
    this.subtitulo,
    required this.icone,
    required this.cor,
    required this.acao,
  });
}

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  String _buscaNome = "";
  bool _modoPesquisaServico = false;
  List<_SugestaoItem> _sugestoes = [];
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounceTimer;
  bool _aguardandoDebounce = false;

  bool get _temPesquisaAtiva => _searchController.text.isNotEmpty;

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onBuscaChanged(String val) {
    _debounceTimer?.cancel();
    if (val.trim().isEmpty) {
      setState(() {
        _aguardandoDebounce = false;
        _buscaNome = "";
        _modoPesquisaServico = false;
        _sugestoes = [];
      });
      return;
    }
    setState(() => _aguardandoDebounce = true);
    _debounceTimer = Timer(const Duration(milliseconds: 200), () {
      if (!mounted) return;
      setState(() {
        _buscaNome = val.toLowerCase();
        _modoPesquisaServico = false;
        _aguardandoDebounce = false;
        _sugestoes = _gerarSugestoes(val.toLowerCase());
      });
    });
  }

  List<_SugestaoItem> _gerarSugestoes(String termo) {
    final lista = <_SugestaoItem>[];

    // Sugestões de categorias de serviço
    if (_termoMatch(termo, ['vaga', 'emprego', 'trabalho', 'contratar'])) {
      lista.add(_SugestaoItem(
        titulo: 'Vagas de emprego',
        subtitulo: 'Oportunidades na sua região',
        icone: Icons.work_rounded,
        cor: const Color(0xFF059669),
        acao: () {
          Navigator.push(context,
            MaterialPageRoute(builder: (_) => const VagasScreen()));
        },
      ));
    }
    if (_termoMatch(termo, ['evento', 'festa', 'show', 'rolar', 'balada'])) {
      lista.add(_SugestaoItem(
        titulo: 'Eventos e festas',
        subtitulo: 'O que vai rolar na cidade',
        icone: Icons.celebration_rounded,
        cor: diPertinRoxo,
        acao: () {
          Navigator.push(context,
            MaterialPageRoute(builder: (_) => const EventosScreen()));
        },
      ));
    }
    if (_termoMatch(termo, ['achado', 'perdido', 'objeto', 'documento', 'pet', 'animal'])) {
      lista.add(_SugestaoItem(
        titulo: 'Achados e perdidos',
        subtitulo: 'Documentos, pets e objetos',
        icone: Icons.manage_search_rounded,
        cor: diPertinLaranja,
        acao: () {
          Navigator.push(context,
            MaterialPageRoute(builder: (_) => const AchadosScreen()));
        },
      ));
    }
    if (_termoMatch(termo, ['polícia', 'policia', '190', 'segurança'])) {
      lista.add(_SugestaoItem(
        titulo: 'Polícia — 190',
        subtitulo: 'Emergência policial',
        icone: Icons.local_police,
        cor: Colors.blueGrey,
        acao: () => _abrirContato('190', 'ligacao'),
      ));
    }
    if (_termoMatch(termo, ['samu', '192', 'ambulância', 'urgencia', 'emergencia médica'])) {
      lista.add(_SugestaoItem(
        titulo: 'SAMU — 192',
        subtitulo: 'Atendimento médico de urgência',
        icone: Icons.medical_services,
        cor: Colors.red,
        acao: () => _abrirContato('192', 'ligacao'),
      ));
    }
    if (_termoMatch(termo, ['bombeiro', '193', 'fogo', 'incêndio', 'incendio', 'resgate'])) {
      lista.add(_SugestaoItem(
        titulo: 'Bombeiros — 193',
        subtitulo: 'Incêndios e resgates',
        icone: Icons.fire_truck,
        cor: Colors.orange,
        acao: () => _abrirContato('193', 'ligacao'),
      ));
    }
    if (_termoMatch(termo, ['serviço', 'servico', 'profissional', 'prestador', 'destaque'])) {
      lista.add(_SugestaoItem(
        titulo: 'Serviços em destaque',
        subtitulo: 'Profissionais com anúncio ativo',
        icone: Icons.star_rounded,
        cor: diPertinRoxo,
        acao: () => _rolarParaSecao('servicos'),
      ));
    }
    if (_termoMatch(termo, ['disk', 'telefone', 'acesso', 'ligar', 'contato'])) {
      lista.add(_SugestaoItem(
        titulo: 'Acesso rápido',
        subtitulo: 'Telefones em destaque na região',
        icone: Icons.phone_in_talk_rounded,
        cor: const Color(0xFF0891B2),
        acao: () => _rolarParaSecao('acesso'),
      ));
    }

    // Sempre oferece a opção "Pesquisar por…"
    lista.add(_SugestaoItem(
      titulo: 'Pesquisar por "$termo"',
      subtitulo: 'Ver todos os resultados de serviços',
      icone: Icons.search_rounded,
      cor: diPertinLaranja,
      acao: () {
        setState(() {
          _modoPesquisaServico = true;
        });
      },
    ));

    return lista;
  }

  static bool _termoMatch(String termo, List<String> palavras) {
    return palavras.any((p) => termo.contains(p));
  }

  void _rolarParaSecao(String secao) {
    setState(() {
      _modoPesquisaServico = false;
      _sugestoes = [];
      _searchController.clear();
      _buscaNome = '';
    });
  }

  /// Ex.: "SÃO PAULO" → "São Paulo"
  static String _formatarNomeCidade(String? raw) {
    if (raw == null || raw.trim().isEmpty) return '';
    return raw
        .trim()
        .split(RegExp(r'\s+'))
        .map((w) {
          if (w.isEmpty) return w;
          if (w.length == 1) return w.toUpperCase();
          return '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}';
        })
        .join(' ');
  }

  // ==========================================
  // FUNÇÃO MESTRA DE CONTATO (WhatsApp / Ligação)
  // ==========================================
  Future<void> _abrirContato(
    String telefoneBruto,
    String tipoContato, {
    String? nomeProfissional,
  }) async {
    String numeroLimpo = telefoneBruto.replaceAll(RegExp(r'[^0-9]'), '');

    Future<void> ligar() async {
      final Uri url = Uri.parse('tel:$numeroLimpo');
      if (await canLaunchUrl(url)) await launchUrl(url);
    }

    Future<void> chamarZap() async {
      String zap = numeroLimpo.startsWith('55')
          ? numeroLimpo
          : '55$numeroLimpo';

      String saudacao =
          (nomeProfissional != null && nomeProfissional.isNotEmpty)
          ? "Olá $nomeProfissional! "
          : "Olá! ";
      String texto = Uri.encodeComponent(
        "${saudacao}Vi seu destaque no app DiPertin e gostaria de mais informações sobre o seu serviço.",
      );

      final Uri url = Uri.parse('https://wa.me/$zap?text=$texto');

      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      }
    }

    if (tipoContato == 'whatsapp') {
      await chamarZap();
    } else if (tipoContato == 'ligacao') {
      await ligar();
    } else {
      if (mounted) {
        showModalBottomSheet(
          context: context,
          backgroundColor: Colors.transparent,
          builder: (context) => Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 18),
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const Text(
                      'Como deseja entrar em contato?',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                        color: Color(0xFF1E1B4B),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: Material(
                            color: const Color(
                              0xFF25D366,
                            ).withValues(alpha: 0.08),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: InkWell(
                              onTap: () {
                                Navigator.pop(context);
                                chamarZap();
                              },
                              borderRadius: BorderRadius.circular(14),
                              child: const Padding(
                                padding: EdgeInsets.symmetric(vertical: 18),
                                child: Column(
                                  children: [
                                    Icon(
                                      Icons.wechat,
                                      color: Color(0xFF25D366),
                                      size: 28,
                                    ),
                                    SizedBox(height: 6),
                                    Text(
                                      'WhatsApp',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13,
                                        color: Color(0xFF25D366),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Material(
                            color: diPertinRoxo.withValues(alpha: 0.08),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: InkWell(
                              onTap: () {
                                Navigator.pop(context);
                                ligar();
                              },
                              borderRadius: BorderRadius.circular(14),
                              child: const Padding(
                                padding: EdgeInsets.symmetric(vertical: 18),
                                child: Column(
                                  children: [
                                    Icon(
                                      Icons.phone_rounded,
                                      color: diPertinRoxo,
                                      size: 28,
                                    ),
                                    SizedBox(height: 6),
                                    Text(
                                      'Ligar',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13,
                                        color: diPertinRoxo,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
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
      }
    }
  }

  void _falarComSuporteParaAnunciar() {
    User? user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Faça login ou cadastre-se para anunciar!'),
          backgroundColor: diPertinLaranja,
        ),
      );
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const LoginScreen()),
      );
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const ChatSuporteScreen()),
      );
    }
  }

  void _limparFiltros() {
    _debounceTimer?.cancel();
    setState(() {
      _buscaNome = "";
      _aguardandoDebounce = false;
      _modoPesquisaServico = false;
      _sugestoes = [];
      _searchController.clear();
      FocusScope.of(context).unfocus();
    });
  }

  @override
  Widget build(BuildContext context) {
    context.watch<LocationService>();

    return Scaffold(
      backgroundColor: _fundoTela,
      body: Column(
        children: [
          _buildHeader(),
          if (_sugestoes.isNotEmpty && !_modoPesquisaServico)
            _buildSugestoesOverlay(),
          Expanded(
            child: _aguardandoDebounce
                ? _buildBuscandoDebounce()
                : _modoPesquisaServico
                ? _buildResultadosServicos()
                : _buildGuiaDaCidade(),
          ),
        ],
      ),
    );
  }

  Widget _buildBuscandoDebounce() {
    return Center(
      child: Padding(
        padding: diPertinScrollPaddingTabShell(context, top: 40, extraBottom: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: diPertinRoxo,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Buscando…',
              style: TextStyle(
                color: _textoMuted,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSugestoesOverlay() {
    return Container(
      width: double.infinity,
      color: Colors.white,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(height: 1, color: Colors.grey.shade100),
          ..._sugestoes.map((sug) => InkWell(
            onTap: sug.acao,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: sug.cor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(sug.icone, color: sug.cor, size: 18),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          sug.titulo,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: _textoPrimario,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (sug.subtitulo != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            sug.subtitulo!,
                            style: TextStyle(
                              fontSize: 11.5,
                              color: _textoMuted,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded, size: 18, color: Colors.grey[400]),
                ],
              ),
            ),
          )),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final loc = context.read<LocationService>();
    final cidadeExibicao = loc.cidadeExibicao;
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF6A1B9A), Color(0xFF7B1FA2)],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Buscar / Serviços',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 22,
                        letterSpacing: -0.5,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.my_location,
                      color: loc.detectandoCidade
                          ? Colors.white38
                          : Colors.white,
                      size: 22,
                    ),
                    tooltip: 'Atualizar cidade pelo GPS',
                    onPressed: loc.detectandoCidade
                        ? null
                        : () => loc.detectarCidade(),
                  ),
                  if (cidadeExibicao.isNotEmpty)
                    Flexible(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.place,
                              color: Colors.white70,
                              size: 14,
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                cidadeExibicao,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: TextField(
                  controller: _searchController,
                  autofocus: false,
                  onChanged: _onBuscaChanged,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: _textoPrimario,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Serviços, vagas, eventos…',
                    hintStyle: TextStyle(
                      color: Colors.grey[400],
                      fontWeight: FontWeight.w400,
                      fontSize: 14,
                    ),
                    prefixIcon: Icon(
                      Icons.search_rounded,
                      color: Colors.grey[500],
                      size: 22,
                    ),
                    suffixIcon: _aguardandoDebounce
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: diPertinLaranja,
                              ),
                            ),
                          )
                        : _temPesquisaAtiva
                        ? IconButton(
                            icon: Icon(
                              Icons.close_rounded,
                              color: Colors.grey[500],
                              size: 20,
                            ),
                            tooltip: 'Limpar busca',
                            onPressed: _limparFiltros,
                          )
                        : null,
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(vertical: 14),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(
                        color: diPertinLaranja,
                        width: 1.5,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSkeletonCarrossel({double height = 124, int count = 3}) {
    return SizedBox(
      height: height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        itemCount: count,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (_, _) => Container(
          width: 185,
          decoration: BoxDecoration(
            color: Colors.grey.shade200,
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }

  // ==========================================
  // WIDGET: O GUIA DA CIDADE
  // ==========================================
  Widget _sectionTitle(String title, IconData icon, {String? subtitle}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: diPertinRoxo.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: diPertinRoxo, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: _textoPrimario,
                    letterSpacing: -0.3,
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: _textoMuted,
                      height: 1.4,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGuiaDaCidade() {
    final loc = context.read<LocationService>();
    final cidadeNorm = loc.cidadeNormalizada;
    final ufNorm = loc.ufNormalizado;

    return SingleChildScrollView(
      padding: diPertinScrollPaddingTabShell(context, top: 18, extraBottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(
            'Serviços em destaque',
            Icons.star_rounded,
            subtitle: 'Profissionais com anúncio ativo na região',
          ),
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('servicos_destaque')
                .where('ativo', isEqualTo: true)
                .snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return _buildSkeletonCarrossel();
              }

              final agora = DateTime.now();
              final anunciosValidos = snapshot.data!.docs.where((doc) {
                final data = doc.data() as Map<String, dynamic>;
                if (data['data_inicio'] == null || data['data_fim'] == null) {
                  return false;
                }
                final inicio = (data['data_inicio'] as Timestamp).toDate();
                final vencimento = (data['data_fim'] as Timestamp).toDate();

                final passaCidade =
                    LocationService.anuncioCidadeCorrespondeUsuario(
                      cidadeNormalizada: data['cidade_normalizada']?.toString(),
                      cidade: data['cidade']?.toString(),
                      cidadeNormUsuario: cidadeNorm,
                      ufNormUsuario: ufNorm,
                      globalSeVazio: true,
                    );

                return agora.isAfter(inicio) &&
                    agora.isBefore(vencimento) &&
                    passaCidade;
              }).toList();

              anunciosValidos.sort((a, b) {
                final dataA = a.data() as Map<String, dynamic>;
                final dataB = b.data() as Map<String, dynamic>;
                final timeA = dataA['data_criacao'] as Timestamp?;
                final timeB = dataB['data_criacao'] as Timestamp?;
                if (timeA == null || timeB == null) return 0;
                return timeB.compareTo(timeA);
              });

              if (anunciosValidos.isEmpty) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Nenhum destaque na sua cidade no momento.',
                      style: TextStyle(color: Colors.grey[700], fontSize: 13),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 120,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [_buildBannerAnuncieAqui()],
                      ),
                    ),
                  ],
                );
              }

              return SizedBox(
                height: 130,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: anunciosValidos.length + 1,
                  itemBuilder: (context, i) {
                    if (i == anunciosValidos.length) {
                      return _buildBannerAnuncieAqui();
                    }

                    final ad =
                        anunciosValidos[i].data() as Map<String, dynamic>;
                    final cidadeCard = _formatarNomeCidade(
                      ad['cidade']?.toString(),
                    );
                    final imagemUrl = (ad['imagem_url'] ?? '').toString();

                    return Container(
                      width: 185,
                      margin: const EdgeInsets.only(right: 10),
                      child: Material(
                        color: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: BorderSide(color: Colors.grey.shade200),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () => _abrirContato(
                            ad['telefone'] ?? '',
                            'whatsapp',
                            nomeProfissional: ad['titulo'],
                          ),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (imagemUrl.isNotEmpty) ...[
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(8),
                                        child: Image.network(
                                          imagemUrl,
                                          width: 36,
                                          height: 36,
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, _, _) =>
                                              const SizedBox.shrink(),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                    ],
                                    Expanded(
                                      child: Text(
                                        ad['titulo'] ?? 'Profissional',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 14,
                                          color: Color(0xFF1E1B4B),
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: diPertinLaranja.withValues(
                                      alpha: 0.1,
                                    ),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    ad['categoria'] ?? 'Geral',
                                    style: const TextStyle(
                                      fontSize: 10.5,
                                      color: diPertinLaranja,
                                      fontWeight: FontWeight.w700,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (cidadeCard.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.place,
                                        size: 11,
                                        color: Colors.grey[400],
                                      ),
                                      const SizedBox(width: 2),
                                      Expanded(
                                        child: Text(
                                          cidadeCard,
                                          style: TextStyle(
                                            fontSize: 10.5,
                                            color: Colors.grey[500],
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                                const Spacer(),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(
                                      0xFF25D366,
                                    ).withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.chat_rounded,
                                        color: Color(0xFF25D366),
                                        size: 14,
                                      ),
                                      SizedBox(width: 4),
                                      Text(
                                        'Chamar',
                                        style: TextStyle(
                                          color: Color(0xFF25D366),
                                          fontWeight: FontWeight.w700,
                                          fontSize: 11.5,
                                        ),
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
                  },
                ),
              );
            },
          ),

          const SizedBox(height: 28),

          _sectionTitle(
            'Emergência',
            Icons.emergency_rounded,
            subtitle: 'Ligações nacionais gratuitas',
          ),
          Row(
            children: [
              Expanded(
                child: _buildEmergenciaBotao(
                  titulo: 'Polícia',
                  numero: '190',
                  icone: Icons.local_police,
                  cor: Colors.blueGrey,
                  descricao:
                      'Use quando precisar de presença policial: crimes em '
                      'andamento, risco à segurança ou situações que exijam '
                      'apoio da polícia. Ligação gratuita.',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildEmergenciaBotao(
                  titulo: 'SAMU',
                  numero: '192',
                  icone: Icons.medical_services,
                  cor: Colors.red,
                  descricao:
                      'Serviço de atendimento móvel de urgência. Em emergência '
                      'médica, acidentes com vítimas ou quando precisar de '
                      'ambulância.',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildEmergenciaBotao(
                  titulo: 'Bombeiros',
                  numero: '193',
                  icone: Icons.fire_truck,
                  cor: Colors.orange,
                  descricao:
                      'Incêndios, acidentes com vítimas, resgates e situações '
                      'com risco à vida. Informe o endereço com clareza ao '
                      'atender a ligação.',
                ),
              ),
            ],
          ),

          const SizedBox(height: 28),

          _sectionTitle(
            'Acesso rápido',
            Icons.phone_in_talk_rounded,
            subtitle: 'Parceiros com telefone em destaque na região',
          ),
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('telefones_premium')
                .where('ativo', isEqualTo: true)
                .snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return GridView.builder(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    childAspectRatio: 2.2,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                  ),
                  itemCount: 4,
                  itemBuilder: (_, _) => Container(
                    decoration: BoxDecoration(
                      color: Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                );
              }

              DateTime agora = DateTime.now();
              var telefonesValidos = snapshot.data!.docs.where((doc) {
                var data = doc.data() as Map<String, dynamic>;
                if (data['data_inicio'] == null ||
                    data['data_vencimento'] == null) {
                  return false;
                }
                DateTime inicio = (data['data_inicio'] as Timestamp).toDate();
                DateTime vencimento = (data['data_vencimento'] as Timestamp)
                    .toDate();

                bool passaCidade =
                    LocationService.anuncioCidadeCorrespondeUsuario(
                      cidadeNormalizada: data['cidade_normalizada']?.toString(),
                      cidade: data['cidade']?.toString(),
                      cidadeNormUsuario: cidadeNorm,
                      ufNormUsuario: ufNorm,
                      globalSeVazio: true,
                    );

                return agora.isAfter(inicio) &&
                    agora.isBefore(vencimento) &&
                    passaCidade;
              }).toList();

              if (telefonesValidos.isEmpty) {
                return Text(
                  'Nenhum parceiro de acesso rápido ativo no momento.',
                  style: TextStyle(color: Colors.grey[700], fontSize: 13),
                );
              }

              return GridView.builder(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  childAspectRatio: 2.2,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                ),
                itemCount: telefonesValidos.length + 1,
                itemBuilder: (context, i) {
                  if (i == telefonesValidos.length) {
                    return _buildBotaoAnuncieTelefone();
                  }

                  var tel = telefonesValidos[i].data() as Map<String, dynamic>;
                  final telImg = (tel['imagem_url'] ?? '').toString();
                  return Material(
                    color: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: BorderSide(color: Colors.grey.shade200),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => _abrirContato(
                        tel['telefone'] ?? '',
                        tel['tipo_contato'] ?? 'ligacao',
                      ),
                      borderRadius: BorderRadius.circular(14),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        child: Row(
                          children: [
                            telImg.isNotEmpty
                                ? ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: Image.network(
                                      telImg,
                                      width: 32,
                                      height: 32,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, _, _) => Container(
                                        width: 32,
                                        height: 32,
                                        decoration: BoxDecoration(
                                          color: diPertinRoxo.withValues(
                                            alpha: 0.08,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                        child: const Icon(
                                          Icons.phone_forwarded_rounded,
                                          color: diPertinRoxo,
                                          size: 16,
                                        ),
                                      ),
                                    ),
                                  )
                                : Container(
                                    width: 32,
                                    height: 32,
                                    decoration: BoxDecoration(
                                      color: diPertinRoxo.withValues(
                                        alpha: 0.08,
                                      ),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Icon(
                                      Icons.phone_forwarded_rounded,
                                      color: diPertinRoxo,
                                      size: 16,
                                    ),
                                  ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    tel['titulo'] ?? '',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF1E1B4B),
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 1),
                                  Text(
                                    tel['telefone'] ?? '',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: diPertinRoxo,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),

          const SizedBox(height: 28),

          _sectionTitle(
            'Utilidade pública',
            Icons.apps_rounded,
            subtitle: 'Vagas, eventos e achados na cidade',
          ),

          _buildUtilidadeItem(
            'Vagas de emprego',
            'Oportunidades na sua região',
            Icons.work_rounded,
            const Color(0xFF059669),
            () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const VagasScreen()),
              );
            },
          ),

          _buildUtilidadeItem(
            'Eventos e festas',
            'O que vai rolar na cidade',
            Icons.celebration_rounded,
            diPertinRoxo,
            () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const EventosScreen()),
              );
            },
          ),

          _buildUtilidadeItem(
            'Achados e perdidos',
            'Documentos, pets e objetos',
            Icons.manage_search_rounded,
            diPertinLaranja,
            () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const AchadosScreen()),
              );
            },
          ),

          const SizedBox(height: 30),
        ],
      ),
    );
  }

  Widget _buildBannerAnuncieAqui() {
    return Container(
      width: 185,
      margin: const EdgeInsets.only(right: 10),
      child: Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: diPertinLaranja.withValues(alpha: 0.3),
            width: 1.5,
            strokeAlign: BorderSide.strokeAlignInside,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: _falarComSuporteParaAnunciar,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: diPertinLaranja.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.campaign_rounded,
                    color: diPertinLaranja,
                    size: 20,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Anuncie aqui',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13.5,
                    color: diPertinLaranja,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Fale com o suporte',
                  style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBotaoAnuncieTelefone() {
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: const Color(0xFF059669).withValues(alpha: 0.3),
          width: 1.5,
          strokeAlign: BorderSide.strokeAlignInside,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _falarComSuporteParaAnunciar,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: const Color(0xFF059669).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.add_call,
                  color: Color(0xFF059669),
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      'Seu disk aqui',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF059669),
                      ),
                    ),
                    Text(
                      'Patrocinar espaço',
                      style: TextStyle(fontSize: 10, color: Colors.grey[500]),
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

  void _mostrarInfoEmergencia({
    required String titulo,
    required String numero,
    required IconData icone,
    required Color cor,
    required String descricao,
  }) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 20),
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Center(
                    child: Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: cor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Icon(icone, color: cor, size: 32),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    titulo,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF1E1B4B),
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 60),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: cor.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      numero,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 4,
                        color: cor,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Número nacional de referência',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    descricao,
                    style: TextStyle(
                      fontSize: 14.5,
                      height: 1.5,
                      color: Colors.grey[700],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.info_outline_rounded,
                          size: 16,
                          color: Colors.amber.shade800,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Em emergência real, mantenha a calma e informe o local com clareza.',
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.35,
                              color: Colors.amber.shade900,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(ctx),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            side: BorderSide(color: Colors.grey.shade300),
                          ),
                          child: Text(
                            'Fechar',
                            style: TextStyle(
                              color: Colors.grey[700],
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: FilledButton.icon(
                          onPressed: () {
                            Navigator.pop(ctx);
                            _abrirContato(numero, 'ligacao');
                          },
                          icon: const Icon(
                            Icons.phone_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                          label: const Text(
                            'Ligar agora',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                          style: FilledButton.styleFrom(
                            backgroundColor: cor,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmergenciaBotao({
    required String titulo,
    required String numero,
    required IconData icone,
    required Color cor,
    required String descricao,
  }) {
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _mostrarInfoEmergencia(
          titulo: titulo,
          numero: numero,
          icone: icone,
          cor: cor,
          descricao: descricao,
        ),
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: cor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icone, color: cor, size: 22),
              ),
              const SizedBox(height: 8),
              Text(
                titulo,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1E1B4B),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 2),
              Text(
                numero,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: cor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUtilidadeItem(
    String titulo,
    String subtitulo,
    IconData icone,
    Color cor,
    VoidCallback onTap,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: Colors.grey.shade200),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: cor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icone, color: cor, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        titulo,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14.5,
                          color: Color(0xFF1E1B4B),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitulo,
                        style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: Colors.grey[400],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ==========================================
  // WIDGET: RESULTADOS DA BUSCA (SERVIÇOS)
  // ==========================================
  Widget _buildResultadosServicos() {
    final loc = context.read<LocationService>();
    final cidadeNorm = loc.cidadeNormalizada;
    final ufNorm = loc.ufNormalizado;
    final termo = _buscaNome;

    return SingleChildScrollView(
      padding: diPertinScrollPaddingTabShell(context, top: 8, extraBottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Row(
              children: [
                Icon(Icons.search_rounded, size: 18, color: _textoMuted),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Resultados para: "$termo"',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: _textoPrimario,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          // Vagas
          _buildSecaoResultado(
            tituloSecao: 'Vagas de emprego',
            iconeSecao: Icons.work_rounded,
            corSecao: const Color(0xFF059669),
            colecao: 'vagas',
            camposBusca: ['cargo', 'empresa', 'descricao'],
            cidadeNorm: cidadeNorm,
            ufNorm: ufNorm,
            aoClicar: (dados) => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const VagasScreen())),
          ),
          const SizedBox(height: 16),
          // Eventos
          _buildSecaoResultado(
            tituloSecao: 'Eventos e festas',
            iconeSecao: Icons.celebration_rounded,
            corSecao: diPertinRoxo,
            colecao: 'eventos',
            camposBusca: ['titulo', 'descricao', 'local'],
            cidadeNorm: cidadeNorm,
            ufNorm: ufNorm,
            aoClicar: (dados) => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const EventosScreen())),
          ),
          const SizedBox(height: 16),
          // Achados
          _buildSecaoResultado(
            tituloSecao: 'Achados e perdidos',
            iconeSecao: Icons.manage_search_rounded,
            corSecao: diPertinLaranja,
            colecao: 'achados',
            camposBusca: ['titulo', 'tipo', 'descricao'],
            cidadeNorm: cidadeNorm,
            ufNorm: ufNorm,
            aoClicar: (dados) => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const AchadosScreen())),
          ),
          const SizedBox(height: 16),
          // Serviços em destaque
          _buildSecaoResultado(
            tituloSecao: 'Serviços em destaque',
            iconeSecao: Icons.star_rounded,
            corSecao: diPertinRoxo,
            colecao: 'servicos_destaque',
            camposBusca: ['titulo', 'categoria', 'descricao'],
            cidadeNorm: cidadeNorm,
            ufNorm: ufNorm,
            aoClicar: (dados) {
              final tel = dados['telefone']?.toString() ?? '';
              if (tel.isNotEmpty) _abrirContato(tel, 'whatsapp');
            },
          ),
          const SizedBox(height: 16),
          // Telefones premium
          _buildSecaoResultado(
            tituloSecao: 'Acesso rápido',
            iconeSecao: Icons.phone_in_talk_rounded,
            corSecao: const Color(0xFF0891B2),
            colecao: 'telefones_premium',
            camposBusca: ['titulo', 'telefone'],
            cidadeNorm: cidadeNorm,
            ufNorm: ufNorm,
            aoClicar: (dados) {
              final tel = dados['telefone']?.toString() ?? '';
              final tipo = dados['tipo_contato']?.toString() ?? 'ligacao';
              if (tel.isNotEmpty) _abrirContato(tel, tipo);
            },
          ),
          const SizedBox(height: 24),
          // Empty state geral (se todas as seções estiverem vazias)
          _buildServicoEmptyState(),
        ],
      ),
    );
  }

  Widget _buildSecaoResultado({
    required String tituloSecao,
    required IconData iconeSecao,
    required Color corSecao,
    required String colecao,
    required List<String> camposBusca,
    required String cidadeNorm,
    required String ufNorm,
    required void Function(Map<String, dynamic> dados) aoClicar,
  }) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection(colecao)
          .where('ativo', isEqualTo: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();

        final agora = DateTime.now();
        final limite3Dias = agora.subtract(const Duration(days: 3));
        final docs = snapshot.data!.docs.where((doc) {
          final d = doc.data() as Map<String, dynamic>;

          // Filtro por cidade
          if (!LocationService.anuncioCidadeCorrespondeUsuario(
            cidadeNormalizada: d['cidade_normalizada']?.toString(),
            cidade: d['cidade']?.toString(),
            cidadeNormUsuario: cidadeNorm,
            ufNormUsuario: ufNorm,
            globalSeVazio: true,
          )) {
            return false;
          }

          // Filtro por vigência
          final tsFim = d['data_fim'] as Timestamp?;
          final tsVenc = d['data_vencimento'] as Timestamp?;
          final tsInicio = d['data_inicio'] as Timestamp?;
          final venc = tsFim?.toDate() ?? tsVenc?.toDate();
          if (tsInicio != null && agora.isBefore(tsInicio.toDate())) {
            return false;
          }
          if (venc != null && venc.isBefore(limite3Dias)) {
            return false;
          }

          // Filtro específico para achados
          if (colecao == 'achados' && d['resolvido'] == true) {
            return false;
          }

          // Filtro por termo de busca
          if (_buscaNome.isEmpty) {
            return false;
          }
          final alvo = camposBusca
              .map((c) => d[c]?.toString() ?? '')
              .join(' ')
              .toLowerCase();
          return alvo.contains(_buscaNome);
        }).toList();

        if (docs.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 16, bottom: 8),
              child: Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: corSecao.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(iconeSecao, color: corSecao, size: 15),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    tituloSecao,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: corSecao,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${docs.length}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: _textoMuted,
                    ),
                  ),
                ],
              ),
            ),
            ...docs.take(5).map((doc) {
              final d = doc.data() as Map<String, dynamic>;
              final titulo = d['titulo'] ?? d['cargo'] ?? d['nome'] ?? '';
              final subtitulo = d['descricao'] ?? d['empresa'] ?? d['telefone'] ?? '';
              String img = '';
              if (colecao == 'servicos_destaque' || colecao == 'telefones_premium') {
                img = (d['imagem_url'] ?? '').toString();
              }

              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: InkWell(
                  onTap: () => aoClicar(d),
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    child: Row(
                      children: [
                        if (img.isNotEmpty)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(img, width: 36, height: 36,
                              fit: BoxFit.cover,
                              errorBuilder: (_,_,_) => const SizedBox.shrink()),
                          )
                        else
                          Container(
                            width: 36, height: 36,
                            decoration: BoxDecoration(
                              color: corSecao.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(iconeSecao, color: corSecao, size: 18),
                          ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                titulo.toString(),
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: _textoPrimario,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 1),
                              Text(
                                subtitulo.toString(),
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: _textoMuted,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        Icon(Icons.chevron_right_rounded, size: 18, color: Colors.grey[400]),
                      ],
                    ),
                  ),
                ),
              );
            }),
            if (docs.length > 5)
              Padding(
                padding: const EdgeInsets.only(left: 16, top: 4),
                child: TextButton.icon(
                  onPressed: () => _navegarColecao(colecao),
                  icon: Icon(Icons.open_in_new_rounded, size: 14, color: corSecao),
                  label: Text(
                    'Ver todos em $tituloSecao',
                    style: TextStyle(fontSize: 12, color: corSecao, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            const Divider(height: 20, indent: 16, endIndent: 16),
          ],
        );
      },
    );
  }

  void _navegarColecao(String colecao) {
    switch (colecao) {
      case 'vagas':
        Navigator.push(context, MaterialPageRoute(builder: (_) => const VagasScreen()));
        break;
      case 'eventos':
        Navigator.push(context, MaterialPageRoute(builder: (_) => const EventosScreen()));
        break;
      case 'achados':
        Navigator.push(context, MaterialPageRoute(builder: (_) => const AchadosScreen()));
        break;
    }
  }

  Widget _buildServicoEmptyState() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collectionGroup('__não_existe__')
          .snapshots(),
      builder: (context, snapshot) {
        // Verifica se há pelo menos um StreamBuilder com dados >0
        // Se todas as seções ficaram vazias, exibe empty state
        return FutureBuilder<bool>(
          future: Future.delayed(const Duration(milliseconds: 800), () {
            // Sempre exibe após delay para dar tempo aos StreamBuilders carregarem
            return true;
          }),
          builder: (context, futureSnapshot) {
            if (!futureSnapshot.hasData) return const SizedBox.shrink();
            return Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 30),
                child: Column(
                  children: [
                    Container(
                      width: 64, height: 64,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Icon(Icons.search_off_rounded, size: 32, color: Colors.grey[400]),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Nenhum serviço encontrado',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: Color(0xFF64748B)),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Tente buscar por outro termo.',
                      style: TextStyle(fontSize: 13, color: _textoMuted),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
