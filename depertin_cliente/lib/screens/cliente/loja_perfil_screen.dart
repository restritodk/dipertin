// Arquivo: lib/screens/cliente/loja_perfil_screen.dart

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import 'product_details_screen.dart';
import '../../utils/loja_pausa.dart';

const Color diPertinRoxo = Color(0xFF6A1B9A);
const Color diPertinLaranja = Color(0xFFFF8F00);

class LojaPerfilScreen extends StatefulWidget {
  final Map<String, dynamic> lojistaData;
  final String lojistaId;

  const LojaPerfilScreen({
    super.key,
    required this.lojistaData,
    required this.lojistaId,
  });

  @override
  State<LojaPerfilScreen> createState() => _LojaPerfilScreenState();
}

class _LojaPerfilScreenState extends State<LojaPerfilScreen> {
  static final NumberFormat _fmtMoeda =
      NumberFormat.currency(locale: 'pt_BR', symbol: r'R$');

  Timer? _timerReavaliaPausa;
  StreamSubscription<DocumentSnapshot>? _subLoja;
  bool _lojaAberta = true;

  /// Dados atualizados do Firestore (foto_perfil, foto_capa, etc.).
  late Map<String, dynamic> _dadosLoja;

  Future<QuerySnapshot<Map<String, dynamic>>>? _cacheAvaliacoes;

  static String _urlCapa(Map<String, dynamic> m) =>
      m['foto_capa']?.toString().trim() ?? '';

  /// Mesma lógica do perfil do lojista: foto de perfil / logo da loja.
  static String _urlLogoLoja(Map<String, dynamic> m) {
    final s = m['foto_perfil']?.toString().trim() ??
        m['foto_logo']?.toString().trim() ??
        m['foto']?.toString().trim() ??
        m['imagem']?.toString().trim() ??
        '';
    return s;
  }

  @override
  void initState() {
    super.initState();
    _dadosLoja = Map<String, dynamic>.from(widget.lojistaData);
    _timerReavaliaPausa = Timer.periodic(const Duration(seconds: 45), (_) {
      if (mounted) setState(() {});
    });
    // Fase 3G.2 — perfil da loja lê `lojas_public` (só dados de fachada).
    _subLoja = FirebaseFirestore.instance
        .collection('lojas_public')
        .doc(widget.lojistaId)
        .snapshots()
        .listen((snap) {
      if (!mounted || !snap.exists) return;
      final dados = snap.data() as Map<String, dynamic>;
      final bool aberta = LojaPausa.lojaEstaAberta(dados);
      setState(() {
        _dadosLoja = dados;
        _lojaAberta = aberta;
      });
    });
  }

  @override
  void dispose() {
    _timerReavaliaPausa?.cancel();
    _subLoja?.cancel();
    super.dispose();
  }

  Future<QuerySnapshot<Map<String, dynamic>>> _futureAvaliacoes() {
    return _cacheAvaliacoes ??= FirebaseFirestore.instance
        .collection('avaliacoes')
        .where('loja_id', isEqualTo: widget.lojistaId)
        .get();
  }

  Future<void> _abrirWhatsApp(String? telefone) async {
    if (telefone == null || telefone.isEmpty) return;

    String numeroLimpo = telefone.replaceAll(RegExp(r'[^0-9]'), '');

    if (!numeroLimpo.startsWith('55') && numeroLimpo.length >= 10) {
      numeroLimpo = '55$numeroLimpo';
    }

    final Uri url = Uri.parse('https://wa.me/$numeroLimpo');

    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Não foi possível abrir o WhatsApp.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  double _precoExibir(Map<String, dynamic> p) {
    final double? precoOriginal = (p['preco'] as num?)?.toDouble();
    final double? precoOferta = (p['oferta'] as num?)?.toDouble();
    final bool temOferta = precoOferta != null &&
        precoOriginal != null &&
        precoOferta < precoOriginal;
    return temOferta ? precoOferta : (precoOriginal ?? precoOferta ?? 0.0);
  }

  bool _temOferta(Map<String, dynamic> p) {
    final double? precoOriginal = (p['preco'] as num?)?.toDouble();
    final double? precoOferta = (p['oferta'] as num?)?.toDouble();
    return precoOferta != null &&
        precoOriginal != null &&
        precoOferta < precoOriginal;
  }

  @override
  Widget build(BuildContext context) {
    final m = _dadosLoja;
    final String urlCapa = _urlCapa(m);
    final String urlLogo = _urlLogoLoja(m);
    // Capa larga: foto_capa; se não houver, usa a mesma imagem do perfil (Meu perfil).
    final String urlHero = urlCapa.isNotEmpty ? urlCapa : urlLogo;
    // Evita logo duplicada: o hero já mostra a foto quando não há capa.
    final bool mostrarAvatarCirculo =
        urlLogo.isNotEmpty && urlCapa.isNotEmpty;
    final String nomeLoja = m['loja_nome']?.toString() ??
        m['nome']?.toString() ??
        'Loja parceira';
    final String descricaoLoja =
        m['descricao']?.toString() ?? 'Sempre perto de você.';
    final String? telefone = m['telefone']?.toString();

    return Scaffold(
      backgroundColor: const Color(0xFFF5F4F8),
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        slivers: [
          SliverAppBar(
            pinned: true,
            stretch: true,
            elevation: 0,
            backgroundColor: diPertinRoxo,
            foregroundColor: Colors.white,
            expandedHeight: 232,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              tooltip: 'Voltar',
              onPressed: () => Navigator.of(context).maybePop(),
            ),
            flexibleSpace: FlexibleSpaceBar(
              stretchModes: const [StretchMode.zoomBackground],
              background: Stack(
                fit: StackFit.expand,
                children: [
                  if (urlHero.isNotEmpty)
                    Image.network(
                      urlHero,
                      fit: BoxFit.cover,
                      errorBuilder: (context, _, _) => _capaPlaceholder(),
                    )
                  else
                    _capaPlaceholder(),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.35),
                          Colors.black.withValues(alpha: 0.65),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 20,
                    bottom: 20,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        if (mostrarAvatarCirculo)
                          Container(
                            padding: const EdgeInsets.all(3),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.2),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: ClipOval(
                              child: Image.network(
                                urlLogo,
                                width: 80,
                                height: 80,
                                fit: BoxFit.cover,
                                errorBuilder:
                                    (context, error, stackTrace) =>
                                        _logoPlaceholderAvatar(),
                              ),
                            ),
                          ),
                        if (mostrarAvatarCirculo) const SizedBox(width: 14),
                        if (!mostrarAvatarCirculo && urlLogo.isEmpty)
                          Container(
                            padding: const EdgeInsets.all(3),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.2),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: _logoPlaceholderAvatar(),
                          ),
                        if (!mostrarAvatarCirculo && urlLogo.isEmpty)
                          const SizedBox(width: 14),
                        Flexible(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                nomeLoja,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                  height: 1.15,
                                  letterSpacing: -0.4,
                                  shadows: [
                                    Shadow(
                                      color: Colors.black54,
                                      blurRadius: 8,
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
                ],
              ),
            ),
          ),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    future: _futureAvaliacoes(),
                    builder: (context, snap) {
                      if (snap.connectionState == ConnectionState.waiting) {
                        return Row(
                          children: [
                            Expanded(
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: _chipStatusLoja(),
                              ),
                            ),
                            SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: diPertinLaranja.withValues(alpha: 0.8),
                              ),
                            ),
                          ],
                        );
                      }
                      final docs = snap.data?.docs ?? [];
                      double media = 0;
                      if (docs.isNotEmpty) {
                        double soma = 0;
                        for (final d in docs) {
                          final m = d.data();
                          soma += (m['nota'] ?? m['estrelas'] ?? 5) as num;
                        }
                        media = soma / docs.length;
                      }
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: _chipStatusLoja(),
                            ),
                          ),
                          if (docs.isEmpty)
                            Row(
                              children: [
                                Icon(
                                  Icons.star_outline_rounded,
                                  size: 22,
                                  color: Colors.grey.shade500,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'Sem avaliações ainda',
                                  style: TextStyle(
                                    color: Colors.grey.shade600,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            )
                          else
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.amber.shade50,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: Colors.amber.shade200,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.star_rounded,
                                    size: 20,
                                    color: Colors.amber.shade800,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    media.toStringAsFixed(1),
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 15,
                                      color: Colors.grey.shade900,
                                    ),
                                  ),
                                  Text(
                                    ' · ${docs.length} aval.',
                                    style: TextStyle(
                                      color: Colors.grey.shade700,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  Text(
                    descricaoLoja,
                    style: TextStyle(
                      fontSize: 15,
                      height: 1.5,
                      color: Colors.grey.shade800,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 22),
                  Text(
                    'Informações',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _InfoCard(
                    icon: Icons.place_outlined,
                    titulo: 'Onde estamos',
                    child: Text(
                      _dadosLoja['endereco']?.toString() ??
                          'Endereço não informado.',
                      style: TextStyle(
                        fontSize: 15,
                        height: 1.45,
                        color: Colors.grey.shade900,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  StreamBuilder<DocumentSnapshot>(
                    // Fase 3G.2 — lê `lojas_public`.
                    stream: FirebaseFirestore.instance
                        .collection('lojas_public')
                        .doc(widget.lojistaId)
                        .snapshots(),
                    builder: (context, snapshot) {
                      String statusLoja = 'Verificando…';
                      Color corChip = Colors.grey.shade700;
                      Color bgChip = Colors.grey.shade100;

                      if (snapshot.hasData && snapshot.data!.exists) {
                        final dados =
                            snapshot.data!.data() as Map<String, dynamic>;
                        final bool aberta = LojaPausa.lojaEstaAberta(dados);
                        if (aberta) {
                          statusLoja = 'Aberta para pedidos';
                          corChip = const Color(0xFF1B5E20);
                          bgChip = const Color(0xFFE8F5E9);
                        } else {
                          final motivo = LojaPausa.textoMotivoPublico(dados);
                          statusLoja = motivo.isNotEmpty
                              ? motivo
                              : 'Fechada no momento';
                          corChip = const Color(0xFFB71C1C);
                          bgChip = const Color(0xFFFFEBEE);
                        }
                      }

                      return _InfoCard(
                        icon: Icons.schedule_rounded,
                        titulo: 'Atendimento',
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: bgChip,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                statusLoja,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: corChip,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 10),
                  Material(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: telefone != null && telefone.isNotEmpty
                          ? () => _abrirWhatsApp(telefone)
                          : null,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: const Color(0xFFE8F5E9),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                Icons.chat_rounded,
                                color: Colors.green.shade700,
                                size: 22,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'WhatsApp',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.grey.shade600,
                                      letterSpacing: 0.2,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    telefone != null && telefone.isNotEmpty
                                        ? telefone
                                        : 'Telefone não informado',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                      color: telefone != null &&
                                              telefone.isNotEmpty
                                          ? diPertinRoxo
                                          : Colors.grey.shade500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (telefone != null && telefone.isNotEmpty)
                              Icon(
                                Icons.open_in_new_rounded,
                                size: 20,
                                color: Colors.grey.shade500,
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (telefone != null && telefone.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: () => _abrirWhatsApp(telefone),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF25D366),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 0,
                      ),
                      icon: const Icon(Icons.chat_rounded, size: 22),
                      label: const Text(
                        'Conversar no WhatsApp',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 28),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: diPertinLaranja.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.grid_view_rounded,
                          color: diPertinLaranja,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Produtos desta loja',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                          color: Colors.grey.shade900,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Toque em um item para ver detalhes e adicionar ao carrinho.',
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.35,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),

          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
            sliver: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('produtos')
                  .where('ativo', isEqualTo: true)
                  .where('lojista_id', isEqualTo: widget.lojistaId)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 40),
                      child: Center(
                        child: CircularProgressIndicator(color: diPertinLaranja),
                      ),
                    ),
                  );
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return SliverToBoxAdapter(
                    child: _EmptyProdutos(),
                  );
                }

                final produtos = snapshot.data!.docs;
                return SliverGrid(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 0.72,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final doc = produtos[index];
                      var p = doc.data()! as Map<String, dynamic>;
                      p = Map<String, dynamic>.from(p);
                      p['id'] = doc.id;
                      p['id_documento'] = doc.id;
                      p['lojista_id'] = widget.lojistaId;
                      p['loja_id'] = widget.lojistaId;
                      p['loja_nome_vitrine'] = nomeLoja;
                      p['loja_aberta'] = _lojaAberta;

                      final String img = (p['imagens'] != null &&
                              p['imagens'] is List &&
                              (p['imagens'] as List).isNotEmpty)
                          ? (p['imagens'] as List).first.toString()
                          : '';

                      final double precoFinal = _precoExibir(p);
                      final bool oferta = _temOferta(p);
                      final double? precoOriginal =
                          (p['preco'] as num?)?.toDouble();

                      return Material(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        clipBehavior: Clip.antiAlias,
                        elevation: 0,
                        shadowColor: Colors.transparent,
                        child: InkWell(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute<void>(
                                builder: (context) =>
                                    ProductDetailsScreen(produto: p),
                              ),
                            );
                          },
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    img.isNotEmpty
                                        ? Image.network(
                                            img,
                                            fit: BoxFit.cover,
                                            errorBuilder: (context, _, _) =>
                                                _thumbErro(),
                                          )
                                        : _thumbErro(),
                                    if (!_lojaAberta)
                                      Positioned.fill(
                                        child: DecoratedBox(
                                          decoration: BoxDecoration(
                                            color: Colors.white
                                                .withValues(alpha: 0.42),
                                          ),
                                        ),
                                      ),
                                    if (!_lojaAberta)
                                      Positioned(
                                        top: 8,
                                        right: 8,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.black
                                                .withValues(alpha: 0.62),
                                            borderRadius:
                                                BorderRadius.circular(10),
                                          ),
                                          child: const Text(
                                            'Fechada',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 10,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                      ),
                                    if (oferta && _lojaAberta)
                                      Positioned(
                                        top: 8,
                                        left: 8,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: diPertinLaranja,
                                            borderRadius:
                                                BorderRadius.circular(8),
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.black
                                                    .withValues(alpha: 0.2),
                                                blurRadius: 6,
                                              ),
                                            ],
                                          ),
                                          child: const Text(
                                            'Oferta',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 11,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  10,
                                  10,
                                  10,
                                  12,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      p['nome']?.toString() ?? 'Produto',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13.5,
                                        height: 1.25,
                                        color: Color(0xFF1A1A2E),
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    if (oferta &&
                                        precoOriginal != null &&
                                        precoOriginal > precoFinal)
                                      Text(
                                        _fmtMoeda.format(precoOriginal),
                                        style: TextStyle(
                                          fontSize: 11,
                                          decoration:
                                              TextDecoration.lineThrough,
                                          color: Colors.grey.shade500,
                                        ),
                                      ),
                                    Text(
                                      _fmtMoeda.format(precoFinal),
                                      style: const TextStyle(
                                        color: diPertinLaranja,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 15,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                    childCount: produtos.length,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _chipStatusLoja() {
    return StreamBuilder<DocumentSnapshot>(
      // Fase 3G.2 — lê `lojas_public`.
      stream: FirebaseFirestore.instance
          .collection('lojas_public')
          .doc(widget.lojistaId)
          .snapshots(),
      builder: (context, snapshot) {
        bool aberta = true;
        String rotuloFechada = 'Fechada';
        if (snapshot.hasData && snapshot.data!.exists) {
          final dados = snapshot.data!.data() as Map<String, dynamic>;
          aberta = LojaPausa.lojaEstaAberta(dados);
          if (!aberta) {
            final t = LojaPausa.textoMotivoPublico(dados);
            if (t.isNotEmpty) rotuloFechada = t;
          }
        }
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: aberta
                ? const Color(0xFFE8F5E9)
                : const Color(0xFFFFEBEE),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: aberta
                  ? const Color(0xFFC8E6C9)
                  : const Color(0xFFFFCDD2),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                aberta ? Icons.check_circle_rounded : Icons.store_mall_directory,
                size: 18,
                color: aberta
                    ? const Color(0xFF2E7D32)
                    : const Color(0xFFC62828),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  aberta ? 'Aberta' : rotuloFechada,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    color: aberta
                        ? const Color(0xFF1B5E20)
                        : const Color(0xFFB71C1C),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _logoPlaceholderAvatar() {
    return Container(
      width: 80,
      height: 80,
      color: const Color(0xFFF0EAF5),
      alignment: Alignment.center,
      child: const Icon(
        Icons.storefront_rounded,
        size: 38,
        color: diPertinRoxo,
      ),
    );
  }

  Widget _capaPlaceholder() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF7B1FA2),
            diPertinRoxo,
          ],
        ),
      ),
      child: Center(
        child: Icon(
          Icons.storefront_rounded,
          size: 88,
          color: Colors.white.withValues(alpha: 0.35),
        ),
      ),
    );
  }

  Widget _thumbErro() {
    return ColoredBox(
      color: const Color(0xFFEDE7F0),
      child: Icon(
        Icons.image_not_supported_outlined,
        color: Colors.grey.shade400,
        size: 40,
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.icon,
    required this.titulo,
    required this.child,
  });

  final IconData icon;
  final String titulo;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE8E6ED)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: diPertinLaranja.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: diPertinLaranja, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titulo.toUpperCase(),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                    color: Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 8),
                child,
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyProdutos extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE8E6ED)),
      ),
      child: Column(
        children: [
          Icon(
            Icons.inventory_2_outlined,
            size: 48,
            color: Colors.grey.shade400,
          ),
          const SizedBox(height: 12),
          Text(
            'Nenhum produto ativo',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 16,
              color: Colors.grey.shade800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Quando a loja publicar itens, eles aparecerão aqui em destaque.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.grey.shade600,
              height: 1.45,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}
