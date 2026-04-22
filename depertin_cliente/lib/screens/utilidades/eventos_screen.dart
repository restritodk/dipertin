// Arquivo: lib/screens/utilidades/eventos_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:depertin_cliente/screens/auth/login_screen.dart';
import 'package:depertin_cliente/screens/cliente/chat_suporte_screen.dart';
import 'package:depertin_cliente/services/location_service.dart';

const Color diPertinRoxo = Color(0xFF6A1B9A);
const Color diPertinLaranja = Color(0xFFFF8F00);

class EventosScreen extends StatefulWidget {
  const EventosScreen({super.key});

  @override
  State<EventosScreen> createState() => _EventosScreenState();
}

class _EventosScreenState extends State<EventosScreen> {
  // Lógica de Trava de Segurança e Redirecionamento
  void _falarComAdmin() {
    User? user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Faça login ou cadastre-se para anunciar seu evento!'),
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
          "Eventos & Festas",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: diPertinRoxo,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _falarComAdmin,
        backgroundColor: diPertinRoxo,
        icon: const Icon(Icons.celebration, color: Colors.white),
        label: const Text(
          "Divulgar Meu Evento",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        // Busca apenas eventos que estão ativos e ordena por data de criação
        stream: FirebaseFirestore.instance
            .collection('eventos')
            .where('ativo', isEqualTo: true)
            .orderBy('data_criacao', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.event_busy, size: 80, color: Colors.grey[300]),
                  const SizedBox(height: 20),
                  const Text(
                    "Nenhum evento programado.",
                    style: TextStyle(color: Colors.grey, fontSize: 16),
                  ),
                ],
              ),
            );
          }

          final agora = DateTime.now();
          final limite3Dias = agora.subtract(const Duration(days: 3));
          var eventos = snapshot.data!.docs.where((doc) {
            final data = doc.data() as Map<String, dynamic>;

            // Filtro por cidade: se o campo estiver vazio, trata como
            // anúncio global (aparece em qualquer cidade). Se houver cidade,
            // exibe apenas para usuários daquela cidade/UF.
            final passaCidade = LocationService.anuncioCidadeCorrespondeUsuario(
              cidadeNormalizada: data['cidade_normalizada']?.toString(),
              cidade: data['cidade']?.toString(),
              cidadeNormUsuario: cidadeNorm,
              ufNormUsuario: ufNorm,
              globalSeVazio: true,
            );
            if (!passaCidade) return false;

            final tsFim = data['data_fim'] as Timestamp?;
            final tsVenc = data['data_vencimento'] as Timestamp?;
            final venc = tsFim?.toDate() ?? tsVenc?.toDate();
            if (venc == null) return true;
            return venc.isAfter(limite3Dias);
          }).toList();

          if (eventos.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.event_busy, size: 80, color: Colors.grey[300]),
                  const SizedBox(height: 20),
                  const Text(
                    "Nenhum evento programado.",
                    style: TextStyle(color: Colors.grey, fontSize: 16),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(10),
            itemCount: eventos.length,
            itemBuilder: (context, index) {
              var evento = eventos[index].data() as Map<String, dynamic>;

              return Card(
                elevation: 3,
                margin: const EdgeInsets.only(bottom: 15),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ===============================================
                    // IMAGEM DO EVENTO (Agora clicável!)
                    // ===============================================
                    GestureDetector(
                      onTap: () {
                        // Se houver uma imagem válida, abre o "Poster" em tela cheia
                        if (evento['imagem_url'] != null &&
                            evento['imagem_url'].toString().isNotEmpty) {
                          showDialog(
                            context: context,
                            builder: (context) => Dialog(
                              backgroundColor:
                                  Colors.transparent, // Fundo transparente
                              insetPadding: const EdgeInsets.all(
                                10,
                              ), // Pequena margem da borda
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  // A imagem em tamanho natural (fit: contain)
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(15),
                                    child: Image.network(
                                      evento['imagem_url'],
                                      fit: BoxFit
                                          .contain, // Mostra a imagem inteira sem cortar
                                    ),
                                  ),
                                  // Botão X para fechar no canto superior
                                  Positioned(
                                    top: 10,
                                    right: 10,
                                    child: CircleAvatar(
                                      backgroundColor: Colors.white.withOpacity(
                                        0.5,
                                      ),
                                      child: IconButton(
                                        icon: const Icon(
                                          Icons.close,
                                          color: Colors.black,
                                        ),
                                        onPressed: () => Navigator.pop(context),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }
                      },
                      child: ClipRRect(
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(15),
                        ),
                        child:
                            evento['imagem_url'] != null &&
                                evento['imagem_url'].toString().isNotEmpty
                            ? Image.network(
                                evento['imagem_url'],
                                height: 180,
                                fit: BoxFit.cover,
                                errorBuilder: (c, e, s) => Container(
                                  height: 180,
                                  color: Colors.grey[300],
                                  child: const Icon(
                                    Icons.broken_image,
                                    size: 50,
                                    color: Colors.grey,
                                  ),
                                ),
                              )
                            : Container(
                                height: 180,
                                color: diPertinRoxo.withOpacity(0.1),
                                child: const Icon(
                                  Icons.event,
                                  size: 60,
                                  color: diPertinRoxo,
                                ),
                              ),
                      ),
                    ),

                    // --- INFORMAÇÕES DO EVENTO ---
                    Padding(
                      padding: const EdgeInsets.all(15.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            evento['titulo'] ?? 'Evento sem título',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: diPertinRoxo,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              const Icon(
                                Icons.calendar_today,
                                size: 16,
                                color: diPertinLaranja,
                              ),
                              const SizedBox(width: 5),
                              Expanded(
                                child: Text(
                                  evento['data_evento'] ?? 'Data a definir',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              const Icon(
                                Icons.location_on,
                                size: 16,
                                color: Colors.red,
                              ),
                              const SizedBox(width: 5),
                              Expanded(
                                child: Text(
                                  evento['local'] ?? 'Local não informado',
                                  style: const TextStyle(color: Colors.grey),
                                ),
                              ),
                            ],
                          ),
                          if (evento['descricao'] != null &&
                              evento['descricao'].toString().isNotEmpty) ...[
                            const SizedBox(height: 10),
                            Text(
                              evento['descricao'],
                              style: const TextStyle(fontSize: 14),
                            ),
                          ],

                          // ===============================================
                          // BOTÃO DE INGRESSO (Abre Link)
                          // ===============================================
                          if (evento['link_ingresso'] != null &&
                              evento['link_ingresso']
                                  .toString()
                                  .isNotEmpty) ...[
                            const SizedBox(height: 15),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: () async {
                                  final String link = evento['link_ingresso'];
                                  final Uri url = Uri.parse(link);

                                  try {
                                    if (await canLaunchUrl(url)) {
                                      await launchUrl(
                                        url,
                                        mode: LaunchMode.externalApplication,
                                      );
                                    } else {
                                      throw 'Could not launch $link';
                                    }
                                  } catch (e) {
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            "Não foi possível abrir o link. Verifique se é um site válido.",
                                          ),
                                          backgroundColor: Colors.red,
                                        ),
                                      );
                                    }
                                  }
                                },
                                icon: const Icon(
                                  Icons.local_activity,
                                  color: Colors.white,
                                ),
                                label: const Text(
                                  "Comprar Ingresso / Mais Info",
                                  style: TextStyle(color: Colors.white),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: diPertinLaranja,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
