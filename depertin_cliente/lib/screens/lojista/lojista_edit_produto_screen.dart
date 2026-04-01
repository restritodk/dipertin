// Arquivo: lib/screens/lojista/lojista_edit_produto_screen.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

const Color diPertinRoxo = Color(0xFF6A1B9A);
const Color diPertinLaranja = Color(0xFFFF8F00);

class LojistaEditProdutoScreen extends StatefulWidget {
  final Map<String, dynamic> produto;

  const LojistaEditProdutoScreen({super.key, required this.produto});

  @override
  State<LojistaEditProdutoScreen> createState() =>
      _LojistaEditProdutoScreenState();
}

class _LojistaEditProdutoScreenState extends State<LojistaEditProdutoScreen> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _nomeController;
  late TextEditingController _descricaoController;
  late TextEditingController _precoController;
  late TextEditingController _ofertaController;

  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    // Preenche os campos com os dados que vieram do banco!
    _nomeController = TextEditingController(text: widget.produto['nome']);
    _descricaoController = TextEditingController(
      text: widget.produto['descricao'],
    );
    _precoController = TextEditingController(
      text: widget.produto['preco']?.toString(),
    );
    _ofertaController = TextEditingController(
      text: widget.produto['oferta']?.toString() ?? '',
    );
  }

  @override
  void dispose() {
    _nomeController.dispose();
    _descricaoController.dispose();
    _precoController.dispose();
    _ofertaController.dispose();
    super.dispose();
  }

  // Função Mágica que atualiza (UPDATE) apenas os textos no Firebase
  Future<void> _salvarAlteracoes() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      // Converte vírgula para ponto (ex: 25,50 vira 25.50 para o banco entender)
      double preco = double.parse(_precoController.text.replaceAll(',', '.'));
      double? oferta = _ofertaController.text.isNotEmpty
          ? double.parse(_ofertaController.text.replaceAll(',', '.'))
          : null;

      // Pega o ID do documento e manda a ordem de UPDATE pro Firebase
      await FirebaseFirestore.instance
          .collection('produtos')
          .doc(widget.produto['id_documento'])
          .update({
            'nome': _nomeController.text.trim(),
            'descricao': _descricaoController.text.trim(),
            'preco': preco,
            'oferta': oferta,
          });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Produto atualizado com sucesso!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context); // Fecha a tela e volta para o estoque
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Erro ao atualizar produto. Verifique os valores.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          "Editar Produto",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: diPertinLaranja,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _isSaving
          ? const Center(
              child: CircularProgressIndicator(color: diPertinLaranja),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      "Altere as informações abaixo:",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Campo: NOME
                    TextFormField(
                      controller: _nomeController,
                      decoration: const InputDecoration(
                        labelText: "Nome do Produto",
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.shopping_bag),
                      ),
                      validator: (value) => value == null || value.isEmpty
                          ? 'Informe o nome'
                          : null,
                    ),
                    const SizedBox(height: 15),

                    // Campo: DESCRIÇÃO
                    TextFormField(
                      controller: _descricaoController,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: "Descrição",
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.description),
                      ),
                      validator: (value) => value == null || value.isEmpty
                          ? 'Informe a descrição'
                          : null,
                    ),
                    const SizedBox(height: 15),

                    // Row para PREÇO e OFERTA
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _precoController,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: "Preço (R\$)",
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.attach_money),
                            ),
                            validator: (value) => value == null || value.isEmpty
                                ? 'Obrigatório'
                                : null,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextFormField(
                            controller: _ofertaController,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: "Oferta (Opcional)",
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(
                                Icons.local_offer,
                                color: Colors.red,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 30),

                    // Botão SALVAR
                    ElevatedButton.icon(
                      onPressed: _salvarAlteracoes,
                      icon: const Icon(Icons.save, color: Colors.white),
                      label: const Text(
                        "SALVAR ALTERAÇÕES",
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: diPertinLaranja,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
