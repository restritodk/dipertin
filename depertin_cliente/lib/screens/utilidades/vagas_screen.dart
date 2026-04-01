// Arquivo: lib/screens/vagas_screen.dart

import 'package:depertin_cliente/screens/auth/login_screen.dart';
import 'package:depertin_cliente/screens/cliente/chat_suporte_screen.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:firebase_auth/firebase_auth.dart';

const Color diPertinRoxo = Color(0xFF6A1B9A);
const Color diPertinLaranja = Color(0xFFFF8F00);

class VagasScreen extends StatefulWidget {
  const VagasScreen({super.key});

  @override
  State<VagasScreen> createState() => _VagasScreenState();
}

class _VagasScreenState extends State<VagasScreen> {
  // Função que verifica login e leva para o chat
  void _falarComAdmin() {
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

  // ==========================================
  // FUNÇÃO DETETIVE DE CONTATO (E-mail, Ligações e Zap)
  // ==========================================
  Future<void> _entrarEmContatoVaga(
    BuildContext context,
    String contato,
    String cargo,
  ) async {
    // 1. É E-MAIL?
    if (contato.contains('@')) {
      final Uri emailUrl = Uri(
        scheme: 'mailto',
        path: contato.trim(),
        query:
            'subject=${Uri.encodeComponent("Candidatura para vaga: $cargo (Via App DiPertin)")}',
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
      // Função interna para ligar
      Future<void> ligar() async {
        final Uri url = Uri.parse('tel:$numeroLimpo');
        if (await canLaunchUrl(url)) await launchUrl(url);
      }

      // Função interna para WhatsApp
      Future<void> chamarZap() async {
        String zap = numeroLimpo.startsWith('55')
            ? numeroLimpo
            : '55$numeroLimpo';
        String mensagem = Uri.encodeComponent(
          "Olá! Vi a vaga de *$cargo* no aplicativo DiPertin e gostaria de me candidatar / obter mais informações.",
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
                    "Como deseja enviar seu currículo?",
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
                  leading: const Icon(Icons.phone, color: diPertinRoxo),
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
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text(
          "Vagas de Emprego",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.green,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _falarComAdmin,
        backgroundColor: Colors.green,
        icon: const Icon(Icons.campaign, color: Colors.white),
        label: const Text(
          "Anunciar Vaga (Grátis)",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        // Mantemos a mesma busca para não dar erro de índice
        stream: FirebaseFirestore.instance
            .collection('vagas')
            .where('ativo', isEqualTo: true)
            .orderBy('data_criacao', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: Colors.green),
            );
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.work_off, size: 80, color: Colors.grey[300]),
                  const SizedBox(height: 20),
                  const Text(
                    "Nenhuma vaga disponível no momento.",
                    style: TextStyle(color: Colors.grey, fontSize: 16),
                  ),
                ],
              ),
            );
          }

          // ===== NOVO FILTRO DE VALIDADE (Esconde as vencidas) =====
          DateTime agora = DateTime.now();
          var vagasAtivasEValidas = snapshot.data!.docs.where((doc) {
            var data = doc.data() as Map<String, dynamic>;
            // Se a vaga for antiga e não tiver data de vencimento, exibe ela normalmente
            if (data['data_vencimento'] == null) return true;

            DateTime vencimento = (data['data_vencimento'] as Timestamp)
                .toDate();
            // Só retorna true se a data de vencimento for DEPOIS de agora
            return vencimento.isAfter(agora);
          }).toList();

          // Se depois do filtro não sobrar nenhuma válida:
          if (vagasAtivasEValidas.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.timer_off, size: 80, color: Colors.grey[300]),
                  const SizedBox(height: 20),
                  const Text(
                    "As vagas recentes já expiraram.",
                    style: TextStyle(color: Colors.grey, fontSize: 16),
                  ),
                ],
              ),
            );
          }
          // ==========================================================

          return ListView.builder(
            padding: const EdgeInsets.all(15),
            itemCount: vagasAtivasEValidas.length, // <-- Usa a lista filtrada
            itemBuilder: (context, index) {
              var vaga =
                  vagasAtivasEValidas[index].data() as Map<String, dynamic>;

              String cargo = vaga['cargo'] ?? 'Vaga';
              String empresa = vaga['empresa'] ?? 'Empresa não informada';
              String cidade = vaga['cidade'] ?? '';
              String descricao = vaga['descricao'] ?? '';
              String contato = vaga['contato'] ?? '';

              return Card(
                margin: const EdgeInsets.only(bottom: 15),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.all(15),
                  leading: CircleAvatar(
                    backgroundColor: Colors.green[50],
                    child: const Icon(Icons.work, color: Colors.green),
                  ),
                  title: Text(
                    cargo,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: diPertinRoxo,
                    ),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 5),
                      Text(
                        "Empresa: $empresa",
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      if (cidade.isNotEmpty)
                        Text(
                          "Cidade: ${cidade.toUpperCase()}",
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                      const SizedBox(height: 8),
                      Text(
                        descricao,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        "Toque para se candidatar 👇",
                        style: TextStyle(
                          color: Colors.green,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  onTap: () async {
                    if (contato.isEmpty) {
                      showDialog(
                        context: context,
                        builder: (c) => AlertDialog(
                          title: Text(cargo),
                          content: const Text(
                            "Esta vaga não possui informações de contato direto. Tente ir até o local da empresa.",
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(c),
                              child: const Text("Fechar"),
                            ),
                          ],
                        ),
                      );
                      return;
                    }

                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Boa sorte na sua busca! Estamos torcendo por você. 🍀',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        backgroundColor: Colors.green,
                        duration: Duration(seconds: 2),
                      ),
                    );

                    await Future.delayed(const Duration(seconds: 2));

                    if (context.mounted) {
                      // Chama o nosso detetive!
                      await _entrarEmContatoVaga(context, contato, cargo);
                    }
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}
