// Arquivo: lib/screens/utilidades/achados_screen.dart

import 'package:depertin_cliente/screens/auth/login_screen.dart';
import 'package:depertin_cliente/screens/cliente/chat_suporte_screen.dart';
import 'package:depertin_cliente/services/location_service.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

const Color diPertinLaranja = Color(0xFFFF8F00);
const Color diPertinRoxo = Color(0xFF6A1B9A);

class AchadosScreen extends StatefulWidget {
  const AchadosScreen({super.key});

  @override
  State<AchadosScreen> createState() => _AchadosScreenState();
}

class _AchadosScreenState extends State<AchadosScreen> {
  // Lógica de Trava de Segurança e Redirecionamento
  void _falarComAdmin() {
    User? user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Faça login para anunciar um item!'),
          backgroundColor: Colors.red,
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

  // ==========================================
  // FUNÇÃO DETETIVE DE CONTATO (E-mail, Ligações e Zap)
  // ==========================================
  Future<void> _entrarEmContato(
    BuildContext context,
    String contato,
    String item,
    String tipo,
  ) async {
    // 1. É E-MAIL?
    if (contato.contains('@')) {
      final Uri emailUrl = Uri(
        scheme: 'mailto',
        path: contato.trim(),
        query:
            'subject=${Uri.encodeComponent("Sobre o item $tipo: $item (Via App DiPertin)")}',
      );
      try {
        if (await canLaunchUrl(emailUrl)) {
          await launchUrl(emailUrl);
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Nenhum aplicativo de e-mail encontrado."),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
      return;
    }

    // 2. É NÚMERO DE TELEFONE / WHATSAPP?
    String numeroLimpo = contato.replaceAll(RegExp(r'[^0-9]'), '');
    if (numeroLimpo.isNotEmpty) {
      Future<void> ligar() async {
        final Uri url = Uri.parse('tel:$numeroLimpo');
        if (await canLaunchUrl(url)) await launchUrl(url);
      }

      Future<void> chamarZap() async {
        String zap = numeroLimpo.startsWith('55')
            ? numeroLimpo
            : '55$numeroLimpo';
        String mensagem = Uri.encodeComponent(
          "Olá! Vi seu anúncio sobre o item $tipo (*$item*) no aplicativo DiPertin e gostaria de ajudar.",
        );
        final Uri url = Uri.parse('https://wa.me/$zap?text=$mensagem');
        if (await canLaunchUrl(url)) {
          await launchUrl(url, mode: LaunchMode.externalApplication);
        }
      }

      // Mostra o Menu Inferior para o usuário escolher
      if (context.mounted) {
        showModalBottomSheet(
          context: context,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          builder: (context) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Padding(
                  padding: EdgeInsets.all(15.0),
                  child: Text(
                    "Como deseja falar com a pessoa?",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.wechat, color: Colors.green),
                  title: const Text("Enviar no WhatsApp"),
                  subtitle: const Text("Abre com mensagem pronta"),
                  onTap: () {
                    Navigator.pop(context);
                    chamarZap();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.phone, color: diPertinLaranja),
                  title: const Text("Fazer uma Ligação"),
                  onTap: () {
                    Navigator.pop(context);
                    ligar();
                  },
                ),
              ],
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Reage a mudanças na cidade detectada do usuário para refiltrar.
    context.watch<LocationService>();
    final loc = context.read<LocationService>();
    final cidadeNorm = loc.cidadeNormalizada;
    final ufNorm = loc.ufNormalizado;

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text(
          "Achados e Perdidos",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: diPertinLaranja,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _falarComAdmin,
        backgroundColor: diPertinLaranja,
        icon: const Icon(Icons.campaign, color: Colors.white),
        label: const Text(
          "Anunciar Item",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('achados')
            .where('ativo', isEqualTo: true)
            .where('resolvido', isEqualTo: false)
            .orderBy('data_criacao', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: diPertinLaranja),
            );
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return _buildListaVazia(); // Movi a UI vazia para não poluir
          }

          final agora = DateTime.now();
          final limite3Dias = agora.subtract(const Duration(days: 3));
          var itens = snapshot.data!.docs.where((doc) {
            var data = doc.data() as Map<String, dynamic>;

            // Filtro por cidade: vazio => global; preenchido => apenas
            // para usuários da cidade/UF correspondente. Usa o helper que
            // prefere o campo com UF (evita match de cidades homônimas).
            if (!LocationService.anuncioCidadeCorrespondeUsuario(
              cidadeNormalizada: data['cidade_normalizada']?.toString(),
              cidade: data['cidade']?.toString(),
              cidadeNormUsuario: cidadeNorm,
              ufNormUsuario: ufNorm,
              globalSeVazio: true,
            )) {
              return false;
            }

            final tsFim = data['data_fim'] as Timestamp?;
            final tsVenc = data['data_vencimento'] as Timestamp?;
            final venc = tsFim?.toDate() ?? tsVenc?.toDate();
            if (venc == null) return true;
            return venc.isAfter(limite3Dias);
          }).toList();

          if (itens.isEmpty) {
            return _buildListaVazia();
          }

          return ListView.builder(
            padding: const EdgeInsets.all(15),
            itemCount: itens.length,
            itemBuilder: (context, index) {
              var item = itens[index].data() as Map<String, dynamic>;

              String titulo = item['titulo'] ?? '';
              String tipo = (item['tipo'] ?? 'Perdido')
                  .toString()
                  .toLowerCase(); // perdido ou encontrado
              bool isPerdido = tipo == 'perdido';

              // Ajustado para o nome correto salvo pelo nosso painel (imagem_url)
              String imagem = item['imagem_url'] ?? '';
              String contato = item['contato'] ?? '';

              return Card(
                margin: const EdgeInsets.only(bottom: 15),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(15),
                  onTap: () async {
                    if (contato.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text("O anunciante não deixou contato."),
                          backgroundColor: Colors.orange,
                        ),
                      );
                      return;
                    }
                    await _entrarEmContato(
                      context,
                      contato,
                      titulo,
                      isPerdido ? 'Perdido' : 'Encontrado',
                    );
                  },
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // SE TIVER FOTO, MOSTRA A FOTO GRANDE E CLICÁVEL!
                      if (imagem.isNotEmpty)
                        GestureDetector(
                          onTap: () {
                            // Abre a imagem em tela cheia
                            showDialog(
                              context: context,
                              builder: (context) => Dialog(
                                backgroundColor: Colors.transparent,
                                insetPadding: const EdgeInsets.all(10),
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(15),
                                      child: Image.network(
                                        imagem,
                                        fit:
                                            BoxFit.contain, // Mostra sem cortar
                                      ),
                                    ),
                                    Positioned(
                                      top: 10,
                                      right: 10,
                                      child: CircleAvatar(
                                        backgroundColor: Colors.white
                                            .withOpacity(0.5),
                                        child: IconButton(
                                          icon: const Icon(
                                            Icons.close,
                                            color: Colors.black,
                                          ),
                                          onPressed: () =>
                                              Navigator.pop(context),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                          child: ClipRRect(
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(15),
                            ),
                            child: Image.network(
                              imagem,
                              height: 200,
                              fit: BoxFit.cover,
                              errorBuilder: (c, e, s) => Container(
                                height: 100,
                                color: Colors.grey[200],
                                child: const Icon(
                                  Icons.broken_image,
                                  color: Colors.grey,
                                ),
                              ),
                            ),
                          ),
                        ),

                      ListTile(
                        contentPadding: const EdgeInsets.all(15),
                        leading: CircleAvatar(
                          backgroundColor: isPerdido
                              ? Colors.red[50]
                              : Colors.green[50],
                          child: Icon(
                            isPerdido
                                ? Icons.warning_amber
                                : Icons.check_circle_outline,
                            color: isPerdido ? Colors.red : Colors.green,
                          ),
                        ),
                        title: Text(
                          "${isPerdido ? 'PERDIDO' : 'ACHADO'}: $titulo",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: isPerdido ? Colors.red : Colors.green,
                          ),
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 5),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (item['local'] != null &&
                                  item['local'].toString().isNotEmpty)
                                Text(
                                  "Visto em: ${item['local']} - ${item['cidade']}",
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              const SizedBox(height: 5),
                              Text(item['descricao'] ?? ''),
                              const SizedBox(height: 12),

                              // Instrução de toque
                              Row(
                                children: [
                                  Icon(
                                    Icons.touch_app,
                                    size: 14,
                                    color: isPerdido
                                        ? Colors.red
                                        : Colors.green,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    "Toque para entrar em contato",
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                      color: isPerdido
                                          ? Colors.red
                                          : Colors.green,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
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
    );
  }

  Widget _buildListaVazia() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search_off, size: 80, color: Colors.grey[300]),
          const SizedBox(height: 20),
          const Text(
            "Nenhum item recente anunciado.",
            style: TextStyle(color: Colors.grey, fontSize: 16),
          ),
        ],
      ),
    );
  }
}
