// Arquivo: lib/screens/entregador/entregador_mapa_screen.dart

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';

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
        String uid = FirebaseAuth.instance.currentUser!.uid;
        double valorFrete = (widget.pedido['taxa_entrega'] ?? 0.0).toDouble();

        // 1. Atualiza o pedido
        await FirebaseFirestore.instance
            .collection('pedidos')
            .doc(widget.pedidoId)
            .update({
              'status': 'entregue',
              'data_entregue': FieldValue.serverTimestamp(),
            });

        // 2. Saldo do Entregador (Você já tem isso)
        if (valorFrete > 0) {
          await FirebaseFirestore.instance.collection('users').doc(uid).update({
            'saldo': FieldValue.increment(valorFrete),
          });
        }

        // 3. NOVO: Saldo do Lojista (O valor dos produtos)
        double valorProdutos = (widget.pedido['total_produtos'] ?? 0.0)
            .toDouble();
        String lojistaId = widget.pedido['loja_id'] ?? '';

        if (valorProdutos > 0 && lojistaId.isNotEmpty) {
          await FirebaseFirestore.instance
              .collection('users')
              .doc(lojistaId)
              .update({'saldo': FieldValue.increment(valorProdutos)});
        }

        if (mounted) {
          Navigator.pop(dialogContext); // Fecha o dialog
          Navigator.pop(context); // Volta pro Radar
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Entrega Finalizada! O dinheiro já está na sua carteira. 💰',
              ),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
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
    String lojaNome = widget.pedido['loja_nome'] ?? 'Loja';
    String lojaEndereco =
        widget.pedido['loja_endereco'] ?? 'Endereço não informado';
    String clienteEndereco =
        widget.pedido['endereco_entrega'] ?? 'Endereço não informado';
    double taxa = (widget.pedido['taxa_entrega'] ?? 0.0).toDouble();

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text(
          "Rota de Entrega",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
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
                        icon: const Icon(Icons.navigation, color: Colors.white),
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
                        icon: const Icon(Icons.navigation, color: Colors.white),
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
                          side: const BorderSide(color: diPertinRoxo, width: 2),
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

            // BOTÃO FINALIZAR
            SizedBox(
              height: 55,
              child: ElevatedButton(
                onPressed: _mostrarDialogoToken,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                ),
                child: const Text(
                  "CHEGUEI! FINALIZAR ENTREGA",
                  style: TextStyle(
                    fontSize: 16,
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
  }
}
