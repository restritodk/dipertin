// Arquivo: lib/screens/cliente/checkout_pagamento_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_multi_formatter/flutter_multi_formatter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

const Color diPertinRoxo = Color(0xFF6A1B9A);
const Color diPertinLaranja = Color(0xFFFF8F00);

class CheckoutPagamentoScreen extends StatefulWidget {
  final double valorTotal;
  final String metodoPreSelecionado;
  final VoidCallback onPagamentoAprovado;

  const CheckoutPagamentoScreen({
    super.key,
    required this.valorTotal,
    required this.metodoPreSelecionado,
    required this.onPagamentoAprovado,
  });

  @override
  State<CheckoutPagamentoScreen> createState() =>
      _CheckoutPagamentoScreenState();
}

class _CheckoutPagamentoScreenState extends State<CheckoutPagamentoScreen> {
  late String _metodoAtual;
  bool _isProcessando = false;

  // Variáveis para o PIX Real
  bool _pixGerado = false;
  String _pixCopiaECola = "";
  String _pixQrCodeBase64 = "";

  // Controladores do Cartão
  final TextEditingController _numCartaoC = TextEditingController();
  final TextEditingController _nomeTitularC = TextEditingController();
  final TextEditingController _validadeC = TextEditingController();
  final TextEditingController _cvvC = TextEditingController();

  // Bandeira do cartão
  String? _bandeiraCartao;

  @override
  void initState() {
    super.initState();
    _metodoAtual = widget.metodoPreSelecionado == 'Cartão' ? 'Cartão' : 'PIX';
  }

  // === BUSCA O TOKEN DO MERCADO PAGO NO FIREBASE ===
  Future<String?> _getAccessToken() async {
    try {
      var doc = await FirebaseFirestore.instance
          .collection('gateways_pagamento')
          .doc('mercado_pago')
          .get();
      if (doc.exists && doc.data()?['ativo'] == true) {
        return doc.data()?['access_token'];
      }
    } catch (e) {
      debugPrint("Erro ao buscar chave: $e");
    }
    return null;
  }

  // === MÁGICA REAL: COMUNICAÇÃO COM O MERCADO PAGO ===
  Future<void> _processarPagamento() async {
    if (_metodoAtual == 'Cartão') {
      if (_numCartaoC.text.isEmpty ||
          _nomeTitularC.text.isEmpty ||
          _validadeC.text.isEmpty ||
          _cvvC.text.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Preencha todos os dados do cartão!"),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
      // Aqui entrará a tokenização do Cartão no futuro
      setState(() => _isProcessando = true);
      await Future.delayed(
        const Duration(seconds: 3),
      ); // Simulação para o cartão por enquanto
      setState(() => _isProcessando = false);
      widget.onPagamentoAprovado();
      return;
    }

    // === GERAÇÃO OFICIAL DE PIX NO MERCADO PAGO ===
    setState(() => _isProcessando = true);

    String? token = await _getAccessToken();
    if (token == null) {
      setState(() => _isProcessando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Erro: O Gateway de pagamento não está ativo no painel.",
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    User? user = FirebaseAuth.instance.currentUser;
    String emailCliente =
        user?.email ?? "cliente@depertin.com"; // O Mercado Pago exige um email

    try {
      var url = Uri.parse('https://api.mercadopago.com/v1/payments');
      var response = await http.post(
        url,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
          'X-Idempotency-Key': DateTime.now().millisecondsSinceEpoch
              .toString(), // Garante que não cobra duplicado
        },
        body: jsonEncode({
          "transaction_amount": widget.valorTotal,
          "description": "Pedido DiPertin",
          "payment_method_id": "pix",
          "payer": {"email": emailCliente},
        }),
      );

      var dados = jsonDecode(response.body);

      if (response.statusCode == 200 || response.statusCode == 201) {
        setState(() {
          _pixCopiaECola =
              dados['point_of_interaction']['transaction_data']['qr_code'];
          _pixQrCodeBase64 =
              dados['point_of_interaction']['transaction_data']['qr_code_base64'];
          _pixGerado = true;
          _isProcessando = false;
        });
      } else {
        setState(() => _isProcessando = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              "Erro do provedor: ${dados['message'] ?? 'Falha ao gerar PIX'}",
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      setState(() => _isProcessando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Erro de conexão: $e"),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text(
          "Pagamento Seguro",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: diPertinRoxo,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Column(
        children: [
          // CABEÇALHO DO VALOR
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(25),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(bottom: BorderSide(color: Colors.black12)),
            ),
            child: Column(
              children: [
                const Text(
                  "Total a pagar",
                  style: TextStyle(color: Colors.grey, fontSize: 16),
                ),
                const SizedBox(height: 5),
                Text(
                  "R\$ ${widget.valorTotal.toStringAsFixed(2)}",
                  style: const TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: diPertinLaranja,
                  ),
                ),
              ],
            ),
          ),

          // SELETOR SÓ APARECE SE O PIX AINDA NÃO FOI GERADO
          if (!_pixGerado)
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _metodoAtual = 'PIX'),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        decoration: BoxDecoration(
                          color: _metodoAtual == 'PIX'
                              ? Colors.green
                              : Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: _metodoAtual == 'PIX'
                                ? Colors.green
                                : Colors.grey.shade300,
                          ),
                        ),
                        child: Column(
                          children: [
                            Icon(
                              Icons.qr_code,
                              color: _metodoAtual == 'PIX'
                                  ? Colors.white
                                  : Colors.grey,
                              size: 28,
                            ),
                            const SizedBox(height: 5),
                            Text(
                              "PIX",
                              style: TextStyle(
                                color: _metodoAtual == 'PIX'
                                    ? Colors.white
                                    : Colors.grey,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 15),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _metodoAtual = 'Cartão'),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        decoration: BoxDecoration(
                          color: _metodoAtual == 'Cartão'
                              ? diPertinRoxo
                              : Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: _metodoAtual == 'Cartão'
                                ? diPertinRoxo
                                : Colors.grey.shade300,
                          ),
                        ),
                        child: Column(
                          children: [
                            Icon(
                              Icons.credit_card,
                              color: _metodoAtual == 'Cartão'
                                  ? Colors.white
                                  : Colors.grey,
                              size: 28,
                            ),
                            const SizedBox(height: 5),
                            Text(
                              "Cartão",
                              style: TextStyle(
                                color: _metodoAtual == 'Cartão'
                                    ? Colors.white
                                    : Colors.grey,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // ÁREA DINÂMICA
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: _pixGerado
                  ? _buildPixGeradoOficial()
                  : (_metodoAtual == 'PIX'
                        ? _buildAbaPix()
                        : _buildAbaCartao()),
            ),
          ),
        ],
      ),
      bottomNavigationBar: _pixGerado
          ? null // Se gerou o pix, tira o botão de baixo para o usuário focar em pagar
          : Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 10,
                    offset: Offset(0, -5),
                  ),
                ],
              ),
              child: SizedBox(
                height: 55,
                child: ElevatedButton(
                  onPressed: _isProcessando ? null : _processarPagamento,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _metodoAtual == 'PIX'
                        ? Colors.green
                        : diPertinLaranja,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                  ),
                  child: _isProcessando
                      ? const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            ),
                            SizedBox(width: 15),
                            Text(
                              "Processando...",
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        )
                      : Text(
                          _metodoAtual == 'PIX'
                              ? "GERAR CÓDIGO PIX"
                              : "PAGAR R\$ ${widget.valorTotal.toStringAsFixed(2)}",
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                ),
              ),
            ),
    );
  }

  // === VISUAL DA ABA PIX (INICIAL) ===
  Widget _buildAbaPix() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.green.shade200),
      ),
      child: const Column(
        children: [
          Icon(Icons.pix, size: 60, color: Colors.green),
          SizedBox(height: 15),
          Text(
            "Pagamento Rápido e Seguro",
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          SizedBox(height: 10),
          Text(
            "Ao clicar no botão abaixo, vamos conectar com o Mercado Pago e gerar um código Copia e Cola exclusivo para o seu pedido.",
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey, fontSize: 14),
          ),
        ],
      ),
    );
  }

  // === VISUAL DO PIX GERADO E PRONTO PARA PAGAR ===
  Widget _buildPixGeradoOficial() {
    return Column(
      children: [
        const Text(
          "Pague via PIX para confirmar",
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        const Text(
          "O seu pedido só será enviado para a loja após o pagamento.",
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey),
        ),
        const SizedBox(height: 20),

        // MOSTRA O QR CODE REAL (Se houver tela grande ou for pagar com outro celular)
        if (_pixQrCodeBase64.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Image.memory(
              base64Decode(_pixQrCodeBase64),
              width: 180,
              height: 180,
            ),
          ),

        const SizedBox(height: 20),

        // BOTÃO COPIA E COLA
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            color: Colors.green.shade50,
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: Colors.green.shade200),
          ),
          child: Column(
            children: [
              const Text(
                "Pix Copia e Cola",
                style: TextStyle(
                  color: Colors.green,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              ElevatedButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: _pixCopiaECola));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text("Código PIX copiado!"),
                      backgroundColor: Colors.green,
                    ),
                  );
                },
                icon: const Icon(Icons.copy, color: Colors.white),
                label: const Text(
                  "Copiar Código",
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 30,
                    vertical: 12,
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 30),

        // BOTÃO PARA CONFIRMAR O PEDIDO APÓS PAGAR
        SizedBox(
          width: double.infinity,
          height: 55,
          child: ElevatedButton(
            onPressed: () {
              // Neste MVP, deixamos o cliente avisar que pagou.
              // No futuro, podemos colocar um ouvinte automático (Webhook).
              widget.onPagamentoAprovado();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: diPertinRoxo,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
            ),
            child: const Text(
              "JÁ REALIZEI O PAGAMENTO",
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ],
    );
  }

  // === VISUAL DA ABA CARTÃO (AGORA COM FORMATAÇÃO E BANDEIRA) ===
  Widget _buildAbaCartao() {
    // Retorna a imagem da bandeira baseada na detecção do pacote (Agora usando Strings!)
    Widget iconeBandeira = const Icon(Icons.credit_card, color: diPertinRoxo);
    if (_bandeiraCartao == 'Visa') {
      iconeBandeira = Image.network(
        'https://www.visa.com/api/image-proxy?path=%2Fcontent%2Fdam%2Fvisa%2Fheader%2FVectorBlue.png',
        width: 30,
      );
    } else if (_bandeiraCartao == 'Mastercard') {
      iconeBandeira = Image.network(
        'https://www.mastercard.com/adobe/dynamicmedia/deliver/dm-aid--e81464e9-325f-4fe7-b7b3-6697e9719bd7/mastercard.png?preferwebp=true&quality=82',
        width: 30,
      );
    } else if (_bandeiraCartao == 'American Express') {
      iconeBandeira = Image.network(
        'https://www.aexp-static.com/cdaas/one/statics/axp-static-assets/1.8.0/package/dist/img/logos/dls-logo-bluebox-solid.svg',
        width: 30,
      );
    } else if (_bandeiraCartao == 'Elo') {
      iconeBandeira = Image.network(
        'https://media.elo.com.br/strapi-hml/principal_brand_bw_desk_66cc99bc42.png',
        width: 30,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Dados do Cartão de Crédito",
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 15),

        // Campo Número do Cartão com Formatação Automática
        TextFormField(
          controller: _numCartaoC,
          keyboardType: TextInputType.number,
          inputFormatters: [CreditCardNumberInputFormatter()],
          onChanged: (valor) {
            // Detecta a bandeira automaticamente enquanto o cliente digita!
            setState(() {
              _bandeiraCartao = getCardSystemData(valor)?.system;
            });
          },
          decoration: InputDecoration(
            labelText: "Número do Cartão",
            hintText: "0000 0000 0000 0000",
            prefixIcon: Padding(
              padding: const EdgeInsets.all(12.0),
              child: iconeBandeira,
            ),
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
          ),
        ),
        const SizedBox(height: 15),

        TextFormField(
          controller: _nomeTitularC,
          textCapitalization: TextCapitalization.characters,
          decoration: InputDecoration(
            labelText: "Nome impresso no Cartão",
            prefixIcon: const Icon(Icons.person_outline, color: diPertinRoxo),
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
          ),
        ),
        const SizedBox(height: 15),

        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _validadeC,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  CreditCardExpirationDateFormatter(),
                ], // Coloca a barra MM/AA
                decoration: InputDecoration(
                  labelText: "Validade",
                  hintText: "MM/AA",
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 15),
            Expanded(
              child: TextFormField(
                controller: _cvvC,
                keyboardType: TextInputType.number,
                obscureText: true,
                inputFormatters: [
                  CreditCardCvcInputFormatter(),
                ], // Limita a 3 ou 4 dígitos
                decoration: InputDecoration(
                  labelText: "CVV",
                  hintText: "123",
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 20),

        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.lock, size: 14, color: Colors.green),
            const SizedBox(width: 5),
            Text(
              "Ambiente 100% seguro",
              style: TextStyle(
                fontSize: 12,
                color: Colors.green.shade700,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
