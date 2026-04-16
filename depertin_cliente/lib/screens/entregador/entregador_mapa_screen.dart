// Arquivo: lib/screens/entregador/entregador_mapa_screen.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:depertin_cliente/constants/pedido_status.dart';

// NOVO: Importando a tela de chat que já criamos!
import '../cliente/chat_pedido_screen.dart';

const Color diPertinRoxo = Color(0xFF6A1B9A);
const Color diPertinLaranja = Color(0xFFFF8F00);

class EntregadorMapaScreen extends StatefulWidget {
  final String pedidoId;
  final Map<String, dynamic> pedido;

  const EntregadorMapaScreen({
    super.key,
    required this.pedidoId,
    required this.pedido,
  });

  @override
  State<EntregadorMapaScreen> createState() => _EntregadorMapaScreenState();
}

class _EntregadorMapaScreenState extends State<EntregadorMapaScreen> {
  final TextEditingController _tokenController = TextEditingController();
  bool _validando = false;

  // Função para abrir o Waze ou Google Maps
  Future<void> _abrirGPS(String endereco) async {
    final query = Uri.encodeComponent(endereco);
    final url = Uri.parse(
      "https://www.google.com/maps/search/?api=1&query=$query?q=$query",
    );

    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não foi possível abrir o GPS.')),
        );
      }
    }
  }

  // Pop-up para digitar o token e finalizar a corrida
  void _mostrarDialogoToken() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
          title: const Text(
            "Finalizar Entrega",
            style: TextStyle(color: diPertinRoxo, fontWeight: FontWeight.bold),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "Peça o Token de 6 dígitos para o cliente para confirmar a entrega.",
              ),
              const SizedBox(height: 15),
              TextField(
                controller: _tokenController,
                keyboardType:
                    TextInputType.text, // Atualizado para aceitar letras também
                textCapitalization: TextCapitalization.characters,
                maxLength: 6,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 24,
                  letterSpacing: 5,
                  fontWeight: FontWeight.bold,
                ),
                decoration: InputDecoration(
                  hintText: "000000",
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                _tokenController.clear();
                Navigator.pop(context);
              },
              child: const Text(
                "Cancelar",
                style: TextStyle(color: Colors.grey),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
              onPressed: _validando ? null : () => _validarEFinalizar(context),
              child: _validando
                  ? const SizedBox(
                      width: 15,
                      height: 15,
                      child: CircularProgressIndicator(color: Colors.white),
                    )
                  : const Text(
                      "CONFIRMAR",
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _marcarSaiuParaEntrega() async {
    try {
      await FirebaseFirestore.instance
          .collection('pedidos')
          .doc(widget.pedidoId)
          .update({'status': PedidoStatus.saiuEntrega});
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null && uid.isNotEmpty) {
        await FirebaseFirestore.instance.collection('users').doc(uid).set({
          'entregador_operacao_status': 'INDO_PARA_CLIENTE',
          'entregador_corridas_pendentes': 0,
          'entregador_estado_operacao_atualizado_em':
              FieldValue.serverTimestamp(),
          'entregador_estado_operacao_origem': 'marcarSaiuParaEntrega',
          'entregador_estado_operacao_pedido_id': widget.pedidoId,
        }, SetOptions(merge: true));
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Status: a caminho do cliente.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _validarEFinalizar(BuildContext dialogContext) async {
    setState(() => _validando = true);
    String tokenDigitado = _tokenController.text.trim();

    // Lógica para pegar o token real ou gerar o fallback das 6 letras
    String tokenReal = widget.pedido['token_entrega']?.toString() ?? '';
    if (tokenReal.isEmpty && widget.pedidoId.length >= 6) {
      tokenReal = widget.pedidoId
          .substring(widget.pedidoId.length - 6)
          .toUpperCase();
    }

    if (tokenDigitado.isEmpty || tokenDigitado.length < 6) {
      ScaffoldMessenger.of(dialogContext).showSnackBar(
        const SnackBar(
          content: Text('Digite o token completo.'),
          backgroundColor: Colors.red,
        ),
      );
      setState(() => _validando = false);
      return;
    }

    // Comparamos em letras maiúsculas para não dar erro se o cliente ou motoboy usar minúsculas
    if (tokenDigitado.toUpperCase() == tokenReal.toUpperCase()) {
      try {
        await FirebaseFirestore.instance
            .collection('pedidos')
            .doc(widget.pedidoId)
            .update({
              'status': 'entregue',
              'data_entregue': FieldValue.serverTimestamp(),
            });
        final uid = FirebaseAuth.instance.currentUser?.uid;
        if (uid != null && uid.isNotEmpty) {
          await FirebaseFirestore.instance.collection('users').doc(uid).set({
            'entregador_operacao_status': 'DISPONIVEL',
            'entregador_corridas_pendentes': 0,
            'entregador_estado_operacao_atualizado_em':
                FieldValue.serverTimestamp(),
            'entregador_estado_operacao_origem': 'finalizarEntrega',
            'entregador_estado_operacao_pedido_id': widget.pedidoId,
          }, SetOptions(merge: true));
        }

        if (mounted) {
          Navigator.pop(dialogContext);
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Entrega finalizada! O saldo será creditado automaticamente.',
              ),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        debugPrint('[ENTREGA] Erro ao finalizar: $e');
        ScaffoldMessenger.of(dialogContext).showSnackBar(
          SnackBar(content: Text('Erro: $e'), backgroundColor: Colors.red),
        );
      }
    } else {
      ScaffoldMessenger.of(dialogContext).showSnackBar(
        const SnackBar(
          content: Text('Token Inválido! Tente novamente.'),
          backgroundColor: Colors.red,
        ),
      );
    }
    setState(() => _validando = false);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('pedidos')
          .doc(widget.pedidoId)
          .snapshots(),
      builder: (context, snap) {
        final pedido = snap.hasData && snap.data!.exists
            ? snap.data!.data() ?? widget.pedido
            : widget.pedido;

        String lojaNome = pedido['loja_nome'] ?? 'Loja';
        String lojaEndereco =
            pedido['loja_endereco'] ?? 'Endereço não informado';
        String clienteEndereco =
            pedido['endereco_entrega'] ?? 'Endereço não informado';
        double taxa = (pedido['taxa_entrega'] ?? 0.0).toDouble();
        final statusAtual = pedido['status']?.toString() ?? '';
        final podeFinalizar =
            statusAtual == PedidoStatus.saiuEntrega ||
            statusAtual == PedidoStatus.emRota;
        final mostrarSaiuLoja = statusAtual == PedidoStatus.entregadorIndoLoja;

        return Scaffold(
          backgroundColor: Colors.grey[100],
          appBar: AppBar(
            title: const Text(
              "Rota de Entrega",
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            backgroundColor: diPertinRoxo,
            iconTheme: const IconThemeData(color: Colors.white),
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // CARD DA LOJA (COLETA)
                Card(
                  elevation: 4,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(15),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.storefront, color: diPertinLaranja),
                            SizedBox(width: 8),
                            Text(
                              "1. COLETA NA LOJA",
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                        const Divider(),
                        Text(
                          lojaNome,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          lojaEndereco,
                          style: const TextStyle(color: Colors.black87),
                        ),
                        const SizedBox(height: 15),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: () => _abrirGPS(lojaEndereco),
                            icon: const Icon(
                              Icons.navigation,
                              color: Colors.white,
                            ),
                            label: const Text(
                              "NAVEGAR PARA A LOJA",
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // CARD DO CLIENTE (ENTREGA)
                Card(
                  elevation: 4,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(15),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.person_pin_circle, color: diPertinRoxo),
                            SizedBox(width: 8),
                            Text(
                              "2. ENTREGA AO CLIENTE",
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                        const Divider(),
                        Text(
                          clienteEndereco,
                          style: const TextStyle(
                            fontSize: 16,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 15),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: () => _abrirGPS(clienteEndereco),
                            icon: const Icon(
                              Icons.navigation,
                              color: Colors.white,
                            ),
                            label: const Text(
                              "NAVEGAR PARA O CLIENTE",
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: diPertinRoxo,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),

                        // ==========================================
                        // NOVO: BOTÃO DE CHAT (O ELO PERDIDO!)
                        // ==========================================
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => ChatPedidoScreen(
                                    pedidoId: widget.pedidoId,
                                    lojaId: widget.pedido['loja_id'] ?? '',
                                    lojaNome: "Chat do Pedido",
                                  ),
                                ),
                              );
                            },
                            icon: const Icon(
                              Icons.chat_bubble_outline,
                              color: diPertinRoxo,
                            ),
                            label: const Text(
                              "FALAR NO CHAT DO PEDIDO",
                              style: TextStyle(
                                color: diPertinRoxo,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(
                                color: diPertinRoxo,
                                width: 2,
                              ),
                            ),
                          ),
                        ),
                        // ==========================================
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 30),

                // VALOR A RECEBER
                Center(
                  child: Text(
                    "Seu ganho: R\$ ${taxa.toStringAsFixed(2)}",
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                if (mostrarSaiuLoja) ...[
                  SizedBox(
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _marcarSaiuParaEntrega,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: diPertinLaranja,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                        ),
                      ),
                      child: const Text(
                        'SAÍ DA LOJA — INDIR AO CLIENTE',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

                // BOTÃO FINALIZAR
                SizedBox(
                  height: 55,
                  child: ElevatedButton(
                    onPressed: podeFinalizar ? _mostrarDialogoToken : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      disabledBackgroundColor: Colors.grey.shade400,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                    ),
                    child: Text(
                      podeFinalizar
                          ? 'CHEGUEI! FINALIZAR ENTREGA'
                          : 'Retire o pedido na loja e toque em "Saí da loja" antes.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
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
  }
}
