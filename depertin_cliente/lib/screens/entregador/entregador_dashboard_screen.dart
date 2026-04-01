// Arquivo: lib/screens/entregador/entregador_dashboard_screen.dart

import 'dart:async'; // NOVO: Necessário para manter o GPS a ouvir em segundo plano
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:audioplayers/audioplayers.dart';
import 'entregador_mapa_screen.dart';

const Color diPertinRoxo = Color(0xFF6A1B9A);
const Color diPertinLaranja = Color(0xFFFF8F00);

class EntregadorDashboardScreen extends StatefulWidget {
  const EntregadorDashboardScreen({super.key});

  @override
  State<EntregadorDashboardScreen> createState() =>
      _EntregadorDashboardScreenState();
}

class _EntregadorDashboardScreenState extends State<EntregadorDashboardScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  late String _uid;

  // ==========================================
  // VARIÁVEIS DO ALERTA SONORO
  // ==========================================
  final AudioPlayer _audioPlayer = AudioPlayer();
  int _quantidadePedidosAntiga = 0;

  // ==========================================
  // NOVO: VARIÁVEL DO RASTREADOR GPS
  // ==========================================
  StreamSubscription<Position>? _rastreadorGps;

  @override
  void initState() {
    super.initState();
    _uid = _auth.currentUser!.uid;
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    _pararRastreioGps(); // NOVO: Desliga o GPS se fechar a tela
    super.dispose();
  }

  // ==========================================
  // FUNÇÃO: ATUALIZAR STATUS ONLINE/OFFLINE
  // ==========================================
  Future<void> _mudarStatusTrabalho(bool ficarOnline) async {
    try {
      await FirebaseFirestore.instance.collection('users').doc(_uid).update({
        'is_online': ficarOnline,
      });

      if (ficarOnline) {
        _iniciarRastreioGps(); // Liga o rastreio contínuo
      } else {
        _pararRastreioGps(); // Desliga o rastreio contínuo
      }
    } catch (e) {
      debugPrint("Erro ao mudar status: $e");
    }
  }

  // ==========================================
  // NOVO: FUNÇÕES DE RASTREIO CONTÍNUO (STREAM)
  // ==========================================
  Future<void> _iniciarRastreioGps() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Ligue o GPS do celular!")),
        );
      }
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }
    if (permission == LocationPermission.deniedForever) return;

    // Configuração de Rastreio: Alta precisão, atualiza a cada 10 metros movidos!
    const LocationSettings locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10,
    );

    // Começa a escutar o GPS continuamente
    _rastreadorGps =
        Geolocator.getPositionStream(
          locationSettings: locationSettings,
        ).listen((Position position) async {
          // Toda vez que ele andar 10 metros, envia para o Firebase
          await FirebaseFirestore.instance.collection('users').doc(_uid).update(
            {
              'latitude': position.latitude,
              'longitude': position.longitude,
              'ultima_atualizacao_gps':
                  FieldValue.serverTimestamp(), // Guarda a hora da atualização
            },
          );
          debugPrint(
            "📍 GPS Atualizado: ${position.latitude}, ${position.longitude}",
          );
        });
  }

  void _pararRastreioGps() {
    if (_rastreadorGps != null) {
      _rastreadorGps!.cancel();
      _rastreadorGps = null;
      debugPrint("🛑 Rastreador GPS Desligado.");
    }
  }

  // ==========================================
  // LÓGICA DO PEDIDO (MANTIDA E INTACTA)
  // ==========================================
  Future<void> _aceitarCorrida(String pedidoId) async {
    try {
      final user = _auth.currentUser;
      if (user != null) {
        DocumentSnapshot userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        String nomeEntregador = userDoc['nome'] ?? 'Entregador Parceiro';

        await FirebaseFirestore.instance
            .collection('pedidos')
            .doc(pedidoId)
            .update({
              'status': 'em_rota',
              'entregador_id': user.uid,
              'entregador_nome': nomeEntregador,
            });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Corrida aceita! Vá até a loja.'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Erro ao aceitar corrida.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(_uid)
          .snapshots(),
      builder: (context, snapshotUser) {
        if (snapshotUser.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: Colors.black87,
            body: Center(child: CircularProgressIndicator(color: Colors.white)),
          );
        }

        if (!snapshotUser.hasData || !snapshotUser.data!.exists) {
          return const Scaffold(
            body: Center(child: Text("Erro ao carregar seu perfil.")),
          );
        }

        var dadosEntregador = snapshotUser.data!.data() as Map<String, dynamic>;
        String statusAprovacao =
            dadosEntregador['entregador_status'] ?? 'pendente';
        bool isOnline = dadosEntregador['is_online'] ?? false;

        return Scaffold(
          backgroundColor: Colors.grey[100],
          appBar: AppBar(
            title: const Text(
              "Radar de Corridas",
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            backgroundColor: Colors.black87,
            iconTheme: const IconThemeData(color: Colors.white),
            actions: [
              if (statusAprovacao == 'aprovado')
                Row(
                  children: [
                    Text(
                      isOnline ? "ONLINE" : "OFFLINE",
                      style: TextStyle(
                        color: isOnline ? Colors.green : Colors.grey,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                    Switch(
                      value: isOnline,
                      activeThumbColor: Colors.green,
                      inactiveThumbColor: Colors.grey,
                      inactiveTrackColor: Colors.grey[300],
                      onChanged: (val) => _mudarStatusTrabalho(val),
                    ),
                  ],
                ),
            ],
          ),
          body: Builder(
            builder: (context) {
              if (statusAprovacao == 'pendente' ||
                  statusAprovacao == 'bloqueado') {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(30.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          statusAprovacao == 'bloqueado'
                              ? Icons.block
                              : Icons.access_time_filled,
                          size: 80,
                          color: statusAprovacao == 'bloqueado'
                              ? Colors.red
                              : Colors.orange,
                        ),
                        const SizedBox(height: 20),
                        Text(
                          statusAprovacao == 'bloqueado'
                              ? "Acesso Suspenso"
                              : "Em Análise",
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          statusAprovacao == 'bloqueado'
                              ? "Seu perfil de entregador foi suspenso pela administração."
                              : "Recebemos seus documentos! Nossa equipe está analisando seu cadastro. Volte mais tarde.",
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }

              if (!isOnline) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.power_settings_new,
                        size: 80,
                        color: Colors.grey[400],
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        "Você está Offline",
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.black54,
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        "Ligue a chave no topo da tela para\ncomeçar a receber corridas.",
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                );
              }

              return StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('pedidos')
                    .where('status', whereIn: ['a_caminho', 'em_rota'])
                    .snapshots(),
                builder: (context, snapshotPedidos) {
                  if (snapshotPedidos.connectionState ==
                      ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(color: Colors.black87),
                    );
                  }

                  if (!snapshotPedidos.hasData ||
                      snapshotPedidos.data!.docs.isEmpty) {
                    _quantidadePedidosAntiga =
                        0; // Zera a memória se não tem pedidos
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.radar,
                            size: 80,
                            color: diPertinLaranja.withOpacity(0.5),
                          ),
                          const SizedBox(height: 15),
                          const Text(
                            "Buscando corridas na sua região...",
                            style: TextStyle(color: Colors.grey, fontSize: 16),
                          ),
                        ],
                      ),
                    );
                  }

                  final pedidos = snapshotPedidos.data!.docs.where((doc) {
                    var data = doc.data() as Map<String, dynamic>;
                    if (data['status'] == 'em_rota' &&
                        data['entregador_id'] != _uid) {
                      return false;
                    }
                    return true;
                  }).toList();

                  // ==========================================
                  // A MÁGICA DO ALERTA ACONTECE AQUI
                  // ==========================================
                  if (pedidos.length > _quantidadePedidosAntiga) {
                    _audioPlayer.play(AssetSource('sounds/alerta.mp3'));
                  }

                  _quantidadePedidosAntiga = pedidos.length;
                  // ==========================================

                  if (pedidos.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.radar,
                            size: 80,
                            color: diPertinLaranja.withOpacity(0.5),
                          ),
                          const SizedBox(height: 15),
                          const Text(
                            "Buscando corridas na sua região...",
                            style: TextStyle(color: Colors.grey, fontSize: 16),
                          ),
                        ],
                      ),
                    );
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.all(10),
                    itemCount: pedidos.length,
                    itemBuilder: (context, index) {
                      var pedido =
                          pedidos[index].data() as Map<String, dynamic>;
                      String pedidoId = pedidos[index].id;
                      String statusAtual = pedido['status'];

                      return Card(
                        elevation: 4,
                        margin: const EdgeInsets.only(bottom: 15),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: statusAtual == 'a_caminho'
                                ? Colors.blue
                                : Colors.green,
                            width: 2,
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(15.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    statusAtual == 'a_caminho'
                                        ? "NOVA CORRIDA"
                                        : "SUA ENTREGA",
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: statusAtual == 'a_caminho'
                                          ? Colors.blue
                                          : Colors.green,
                                    ),
                                  ),
                                  Text(
                                    "R\$ ${pedido['total'].toStringAsFixed(2)}",
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                ],
                              ),
                              const Divider(),
                              Row(
                                children: [
                                  const Icon(
                                    Icons.storefront,
                                    color: Colors.grey,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 5),
                                  Expanded(
                                    child: Text(
                                      "Retirar em: ${pedido['loja_nome'] ?? 'Loja Parceira'}",
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(
                                    Icons.location_on,
                                    color: Colors.red,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 5),
                                  Expanded(
                                    child: Text(
                                      "Entregar em: ${pedido['endereco_entrega'] ?? 'Endereço não informado'}",
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 15),

                              SizedBox(
                                width: double.infinity,
                                child: statusAtual == 'a_caminho'
                                    ? ElevatedButton.icon(
                                        onPressed: () =>
                                            _aceitarCorrida(pedidoId),
                                        icon: const Icon(
                                          Icons.motorcycle,
                                          color: Colors.white,
                                        ),
                                        label: const Text(
                                          "ACEITAR CORRIDA",
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.blue,
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 12,
                                          ),
                                        ),
                                      )
                                    : ElevatedButton.icon(
                                        onPressed: () {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (context) =>
                                                  EntregadorMapaScreen(
                                                    pedidoId: pedidoId,
                                                    pedido: pedido,
                                                  ),
                                            ),
                                          );
                                        },
                                        icon: const Icon(
                                          Icons.map,
                                          color: Colors.white,
                                        ),
                                        label: const Text(
                                          "VER ROTA / FINALIZAR",
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.green,
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 12,
                                          ),
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
              );
            },
          ),
        );
      },
    );
  }
}
