// Arquivo: lib/screens/lojista/lojista_dashboard_screen.dart

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:depertin_cliente/screens/lojista/lojista_avaliacoes_screen.dart';
import 'lojista_pedidos_screen.dart';
import 'lojista_produtos_screen.dart';
import 'lojista_config_screen.dart'; // <--- NOVO ARQUIVO QUE VAMOS CRIAR

const Color diPertinLaranja = Color(0xFFFF8F00);
const Color diPertinRoxo = Color(0xFF6A1B9A);

class LojistaDashboardScreen extends StatefulWidget {
  const LojistaDashboardScreen({super.key});

  @override
  State<LojistaDashboardScreen> createState() => _LojistaDashboardScreenState();
}

class _LojistaDashboardScreenState extends State<LojistaDashboardScreen> {
  final String _uid = FirebaseAuth.instance.currentUser!.uid;
  bool _gpsAtualizado = false;
  bool _migracaoRealizada = false;

  Future<void> _migrarDadosLojista(Map<String, dynamic> dados) async {
    if (_migracaoRealizada) return;
    if (dados['loja_nome'] == null || dados['loja_nome'].toString().isEmpty) {
      String nomeAtual = dados['nome'] ?? "Minha Loja";
      try {
        await FirebaseFirestore.instance.collection('users').doc(_uid).update({
          'loja_nome': nomeAtual,
        });
        _migracaoRealizada = true;
        debugPrint("✅ Zelador: Nome migrado para loja_nome com sucesso!");
      } catch (e) {
        debugPrint("❌ Erro na migração: $e");
      }
    }
  }

  Future<void> _atualizarLocalizacaoNoBanco() async {
    if (_gpsAtualizado) return;

    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }
    if (permission == LocationPermission.deniedForever) return;

    Position position = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );

    await FirebaseFirestore.instance.collection('users').doc(_uid).update({
      'latitude': position.latitude,
      'longitude': position.longitude,
    });

    _gpsAtualizado = true;
    debugPrint(
      "📍 GPS Atualizado: ${position.latitude}, ${position.longitude}",
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text(
          "Painel do Lojista",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: diPertinLaranja,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.exit_to_app),
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
              if (context.mounted) Navigator.pop(context);
            },
          ),
        ],
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(_uid)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: diPertinLaranja),
            );
          }

          if (!snapshot.hasData || !snapshot.data!.exists) {
            return const Center(child: Text("Erro ao carregar dados."));
          }

          var dados = snapshot.data!.data() as Map<String, dynamic>;
          String status = dados['status_loja'] ?? 'pendente';

          String nomeParaExibir =
              dados['loja_nome'] ?? dados['nome'] ?? 'Lojista';

          if (status == 'aprovado') {
            _atualizarLocalizacaoNoBanco();
            _migrarDadosLojista(dados);
          }

          if (status == 'pendente' || status == 'bloqueado') {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(30.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      status == 'bloqueado'
                          ? Icons.block
                          : Icons.hourglass_empty,
                      size: 80,
                      color: status == 'bloqueado'
                          ? Colors.red
                          : diPertinLaranja,
                    ),
                    const SizedBox(height: 20),
                    Text(
                      status == 'bloqueado'
                          ? "Loja Bloqueada"
                          : "Aprovação Pendente",
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      status == 'bloqueado'
                          ? "Sua loja foi suspensa pela administração."
                          : "Sua loja está em análise. Aguarde o administrador aprovar o seu cadastro para começar a vender.",
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.grey, fontSize: 16),
                    ),
                  ],
                ),
              ),
            );
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  "Olá, $nomeParaExibir!",
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 5),
                const Text(
                  "O que você deseja gerenciar hoje?",
                  style: TextStyle(fontSize: 16, color: Colors.grey),
                ),
                const SizedBox(height: 30),

                // ==========================================
                // OS CARTÕES DE MENU
                // ==========================================
                _buildMenuCard(
                  context,
                  titulo: "Gestão de Pedidos",
                  subtitulo: "Aceite, recuse e acompanhe entregas",
                  icone: Icons.receipt_long,
                  cor: Colors.blue,
                  telaDestino: const LojistaPedidosScreen(),
                ),
                const SizedBox(height: 15),

                _buildMenuCard(
                  context,
                  titulo: "Meu Estoque",
                  subtitulo: "Cadastre e edite seus produtos",
                  icone: Icons.inventory_2,
                  cor: Colors.green,
                  telaDestino: const LojistaProdutosScreen(),
                ),
                const SizedBox(height: 15),

                // NOVO BOTÃO: CONFIGURAÇÕES DA LOJA!
                _buildMenuCard(
                  context,
                  titulo: "Configurações da Loja",
                  subtitulo: "Horários de funcionamento, nome e status",
                  icone: Icons.store_mall_directory,
                  cor: diPertinRoxo,
                  telaDestino: LojistaConfigScreen(
                    dadosAtuaisDaLoja: dados,
                  ), // <--- Passamos os dados que já temos aqui
                ),
                const SizedBox(height: 15),

                _buildMenuCard(
                  context,
                  titulo: "Avaliações de Clientes",
                  subtitulo: "Feedbacks e notas da sua loja",
                  icone: Icons.star,
                  cor: Colors.amber,
                  telaDestino: const LojistaAvaliacoesScreen(),
                ),

                const SizedBox(height: 30),

                Container(
                  padding: const EdgeInsets.all(15),
                  decoration: BoxDecoration(
                    color: diPertinLaranja.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: diPertinLaranja.withOpacity(0.3)),
                  ),
                  child: const Row(
                    children: [
                      Icon(
                        Icons.desktop_windows,
                        color: diPertinLaranja,
                        size: 30,
                      ),
                      SizedBox(width: 15),
                      Expanded(
                        child: Text(
                          "Lembrete: Acesse o Painel Web para relatórios financeiros completos.",
                          style: TextStyle(fontSize: 13, color: Colors.black87),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildMenuCard(
    BuildContext context, {
    required String titulo,
    required String subtitulo,
    required IconData icone,
    required Color cor,
    required Widget telaDestino,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => telaDestino),
          );
        },
        borderRadius: BorderRadius.circular(15),
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cor.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icone, color: cor, size: 30),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titulo,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      subtitulo,
                      style: const TextStyle(fontSize: 13, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios, color: Colors.grey, size: 16),
            ],
          ),
        ),
      ),
    );
  }
}
