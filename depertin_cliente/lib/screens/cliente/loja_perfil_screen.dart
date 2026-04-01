// Arquivo: lib/screens/cliente/loja_perfil_screen.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart'; // Para abrir o WhatsApp
import 'product_details_screen.dart'; // Importante para clicar no produto e abrir os detalhes

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
  // Função helper para abrir o WhatsApp da loja
  Future<void> _abrirWhatsApp(String? telefone) async {
    if (telefone == null || telefone.isEmpty) return;

    String numeroLimpo = telefone.replaceAll(RegExp(r'[^0-9]'), '');

    if (!numeroLimpo.startsWith('55') && numeroLimpo.length >= 10) {
      numeroLimpo = '55$numeroLimpo';
    }

    final Uri url = Uri.parse("https://wa.me/$numeroLimpo");

    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Não conseguimos abrir o WhatsApp da loja."),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // === BUSCA DAS FOTOS NO BANCO ===
    String urlCapa = widget.lojistaData['foto_capa'] ?? '';
    String urlLogo =
        widget.lojistaData['foto_logo'] ?? widget.lojistaData['imagem'] ?? '';
    String nomeLoja =
        widget.lojistaData['loja_nome'] ??
        widget.lojistaData['nome'] ??
        'Loja Parceira';
    String descricaoLoja =
        widget.lojistaData['descricao'] ?? 'Sempre perto de você!';

    return Scaffold(
      backgroundColor: Colors.grey[100],
      body: CustomScrollView(
        slivers: [
          // 1. CABEÇALHO COM CAPA E LOGO
          SliverAppBar(
            expandedHeight: 220,
            pinned: true,
            backgroundColor: diPertinRoxo,
            iconTheme: const IconThemeData(color: Colors.white),
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  urlCapa.isNotEmpty
                      ? Image.network(urlCapa, fit: BoxFit.cover)
                      : Container(
                          color: diPertinRoxo.withOpacity(0.5),
                          child: const Icon(
                            Icons.store,
                            size: 80,
                            color: Colors.white24,
                          ),
                        ),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.center,
                        colors: [Colors.black54, Colors.transparent],
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 15,
                    left: 20,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: CircleAvatar(
                        radius: 45,
                        backgroundColor: Colors.grey[200],
                        backgroundImage: urlLogo.isNotEmpty
                            ? NetworkImage(urlLogo)
                            : null,
                        child: urlLogo.isEmpty
                            ? const Icon(
                                Icons.storefront,
                                size: 40,
                                color: diPertinRoxo,
                              )
                            : null,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 2. CONTEÚDO SCROLLÁVEL
          SliverList(
            delegate: SliverChildListDelegate([
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 15, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      nomeLoja,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      descricaoLoja,
                      style: const TextStyle(fontSize: 14, color: Colors.grey),
                    ),

                    const SizedBox(height: 30),
                    const Divider(),
                    const SizedBox(height: 20),

                    // == CARDS DE INFORMAÇÕES ==
                    _buildInfoCard(
                      icon: Icons.location_on_outlined,
                      title: "Onde estamos",
                      content:
                          widget.lojistaData['endereco'] ??
                          'Endereço não informado.',
                    ),
                    const SizedBox(height: 15),

                    StreamBuilder<DocumentSnapshot>(
                      stream: FirebaseFirestore.instance
                          .collection('users')
                          .doc(widget.lojistaId)
                          .snapshots(),
                      builder: (context, snapshot) {
                        String statusLoja = 'Aguardando status...';
                        Color corStatus = Colors.grey;

                        if (snapshot.hasData && snapshot.data!.exists) {
                          var dados =
                              snapshot.data!.data() as Map<String, dynamic>;
                          bool aberta = dados['loja_aberta'] ?? true;
                          if (dados['pausado_manualmente'] == true) {
                            aberta = false;
                          }

                          statusLoja = aberta
                              ? "Aberta Agora"
                              : "Fechada no Momento";
                          corStatus = aberta ? Colors.green : Colors.red;
                        }

                        return _buildInfoCard(
                          icon: Icons.access_time,
                          title: "Horário de atendimento",
                          content: statusLoja,
                          contentColor: corStatus,
                        );
                      },
                    ),
                    const SizedBox(height: 15),

                    GestureDetector(
                      onTap: () =>
                          _abrirWhatsApp(widget.lojistaData['telefone']),
                      child: _buildInfoCard(
                        icon: Icons.phone_android,
                        title: "Fale conosco",
                        content:
                            widget.lojistaData['telefone'] ??
                            'Sem telefone cadastrado.',
                        contentColor: diPertinRoxo,
                        trailing: const Icon(
                          Icons.arrow_forward_ios,
                          size: 14,
                          color: diPertinRoxo,
                        ),
                      ),
                    ),

                    const SizedBox(height: 30),
                    const Divider(),
                    const SizedBox(height: 15),

                    // ==========================================
                    // LISTA DE PRODUTOS DA LOJA (A SUA GRADE)
                    // ==========================================
                    const Text(
                      "Produtos desta loja",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 15),

                    StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance
                          .collection('produtos')
                          .where('ativo', isEqualTo: true)
                          .where('lojista_id', isEqualTo: widget.lojistaId)
                          .snapshots(),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const Center(
                            child: CircularProgressIndicator(
                              color: diPertinLaranja,
                            ),
                          );
                        }
                        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                          return const Center(
                            child: Padding(
                              padding: EdgeInsets.all(20.0),
                              child: Text(
                                "Esta loja ainda não possui produtos ativos.",
                                style: TextStyle(color: Colors.grey),
                              ),
                            ),
                          );
                        }

                        var produtos = snapshot.data!.docs;

                        return GridView.builder(
                          shrinkWrap:
                              true, // Importante para funcionar dentro da Column
                          physics:
                              const NeverScrollableScrollPhysics(), // Desativa a rolagem interna da grade
                          padding: EdgeInsets.zero,
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                childAspectRatio: 0.75,
                                crossAxisSpacing: 15,
                                mainAxisSpacing: 15,
                              ),
                          itemCount: produtos.length,
                          itemBuilder: (context, index) {
                            var p =
                                produtos[index].data() as Map<String, dynamic>;
                            p['id'] = produtos[index].id;

                            // Mantém a compatibilidade com a vitrine ao passar o produto para a tela de detalhes
                            p['id_documento'] = produtos[index].id;
                            p['lojista_id'] = widget.lojistaId;
                            p['loja_nome_vitrine'] = nomeLoja;

                            String img =
                                (p['imagens'] != null &&
                                    p['imagens'].isNotEmpty)
                                ? p['imagens'][0]
                                : '';

                            return GestureDetector(
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) =>
                                      ProductDetailsScreen(produto: p),
                                ),
                              ),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(15),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.05),
                                      blurRadius: 5,
                                    ),
                                  ],
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: ClipRRect(
                                        borderRadius:
                                            const BorderRadius.vertical(
                                              top: Radius.circular(15),
                                            ),
                                        child: Image.network(
                                          img.isNotEmpty
                                              ? img
                                              : 'https://via.placeholder.com/150',
                                          width: double.infinity,
                                          fit: BoxFit.cover,
                                          errorBuilder: (c, e, s) => Container(
                                            color: Colors.grey[200],
                                            child: const Icon(
                                              Icons.broken_image,
                                              color: Colors.grey,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.all(10.0),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            p['nome'] ?? '',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 13,
                                            ),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            "R\$ ${(p['oferta'] ?? p['preco'] ?? 0.0).toStringAsFixed(2)}",
                                            style: const TextStyle(
                                              color: diPertinLaranja,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 14,
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
                        );
                      },
                    ),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard({
    required IconData icon,
    required String title,
    required String content,
    Color contentColor = Colors.black87,
    Widget? trailing,
  }) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: diPertinLaranja, size: 22),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  content,
                  style: TextStyle(
                    fontSize: 15,
                    color: contentColor,
                    fontWeight: FontWeight.w500,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}
