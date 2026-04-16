// Arquivo: lib/screens/lojista/lojista_novos_produtos_screen.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import '../../services/location_service.dart';
import '../../services/permissoes_app_service.dart';

const Color diPertinLaranja = Color(0xFFFF8F00);

class LojistaNovosProdutosScreen extends StatefulWidget {
  const LojistaNovosProdutosScreen({super.key});

  @override
  State<LojistaNovosProdutosScreen> createState() =>
      _LojistaNovosProdutosScreenState();
}

class _LojistaNovosProdutosScreenState
    extends State<LojistaNovosProdutosScreen> {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _nomeController = TextEditingController();
  final TextEditingController _descricaoController = TextEditingController();
  final TextEditingController _precoController = TextEditingController();
  final TextEditingController _ofertaController = TextEditingController();

  // NOVO: Variáveis para a Categoria
  String? _categoriaSelecionada;
  final List<String> _categoriasDisponiveis = [
    "Comida",
    "Bebidas",
    "Roupas",
    "Casa",
    "Móveis",
    "Eletro",
    "Farmácia",
    "Serviços",
  ];

  File? _imagemSelecionada;
  bool _isLoading = false;

  final ImagePicker _picker = ImagePicker();

  Future<void> _escolherImagem() async {
    final ResultadoPermissao pr =
        await PermissoesAppService.garantirGaleriaFotos();
    if (!mounted) return;
    if (pr != ResultadoPermissao.concedida) {
      PermissoesFeedback.galeria(context, pr);
      return;
    }
    final XFile? imagemMovel = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 70,
    );
    if (imagemMovel != null) {
      setState(() {
        _imagemSelecionada = File(imagemMovel.path);
      });
    }
  }

  Future<void> _salvarProduto() async {
    if (!_formKey.currentState!.validate()) return;

    // NOVO: Validação para garantir que o lojista escolha a categoria
    if (_categoriaSelecionada == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selecione uma categoria para o produto!'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (_imagemSelecionada == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Por favor, adicione uma imagem do produto.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception("Usuário não logado");

      DocumentSnapshot userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      var userData = userDoc.data() as Map<String, dynamic>? ?? {};
      String nomeLoja = userData['nome_loja'] ?? userData['nome'] ?? 'Loja Parceira';
      String cidadeLoja = (userData['cidade'] ?? '').toString();

      // 1. Fazer Upload da Imagem para o Firebase Storage
      String nomeArquivo = '${DateTime.now().millisecondsSinceEpoch}.jpg';
      Reference pastaImagens = FirebaseStorage.instance.ref().child(
        'produtos/${user.uid}/$nomeArquivo',
      );
      UploadTask uploadTask = pastaImagens.putFile(_imagemSelecionada!);
      TaskSnapshot snapshot = await uploadTask;
      String urlImagem = await snapshot.ref.getDownloadURL();

      // Formata os preços trocando vírgula por ponto
      double preco = double.parse(_precoController.text.replaceAll(',', '.'));
      double? oferta = _ofertaController.text.isNotEmpty
          ? double.parse(_ofertaController.text.replaceAll(',', '.'))
          : null;

      String ufLoja = (userData['uf'] ?? userData['estado'] ?? '').toString();

      await FirebaseFirestore.instance.collection('produtos').add({
        'lojista_id': user.uid,
        'loja_id': user.uid,
        'loja_nome': nomeLoja,
        'nome': _nomeController.text.trim(),
        'descricao': _descricaoController.text.trim(),
        'categoria': _categoriaSelecionada,
        'categoria_nome': _categoriaSelecionada,
        'preco': preco,
        'oferta': oferta,
        'imagens': [urlImagem],
        'ativo': true,
        'cidade': cidadeLoja,
        'uf': ufLoja,
        'cidade_normalizada': LocationService.normalizar(cidadeLoja),
        'uf_normalizado': LocationService.extrairUf(ufLoja) ??
            LocationService.normalizar(ufLoja),
        'data_cadastro': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Produto cadastrado com sucesso!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context); // Volta para a tela de estoque
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao salvar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _nomeController.dispose();
    _descricaoController.dispose();
    _precoController.dispose();
    _ofertaController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          "Novo Produto",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: diPertinLaranja,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _isLoading
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
                    // Área da Foto do Produto
                    GestureDetector(
                      onTap: _escolherImagem,
                      child: Container(
                        height: 180,
                        decoration: BoxDecoration(
                          color: Colors.grey[200],
                          borderRadius: BorderRadius.circular(15),
                          border: Border.all(color: Colors.grey[400]!),
                        ),
                        child: _imagemSelecionada != null
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(15),
                                child: Image.file(
                                  _imagemSelecionada!,
                                  fit: BoxFit.cover,
                                ),
                              )
                            : const Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.add_a_photo,
                                    size: 50,
                                    color: Colors.grey,
                                  ),
                                  SizedBox(height: 10),
                                  Text(
                                    "Toque para adicionar foto",
                                    style: TextStyle(color: Colors.grey),
                                  ),
                                ],
                              ),
                      ),
                    ),
                    const SizedBox(height: 20),

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

                    TextFormField(
                      controller: _descricaoController,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: "Descrição (Ingredientes, tamanho, etc)",
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.description),
                      ),
                      validator: (value) => value == null || value.isEmpty
                          ? 'Informe a descrição'
                          : null,
                    ),
                    const SizedBox(height: 15),

                    // ==========================================
                    // NOVO: DROPDOWN DE CATEGORIA
                    // ==========================================
                    DropdownButtonFormField<String>(
                      decoration: const InputDecoration(
                        labelText: "Categoria (Departamento)",
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(
                          Icons.category,
                          color: diPertinLaranja,
                        ),
                      ),
                      initialValue: _categoriaSelecionada,
                      items: _categoriasDisponiveis.map((String categoria) {
                        return DropdownMenuItem<String>(
                          value: categoria,
                          child: Text(categoria),
                        );
                      }).toList(),
                      onChanged: (String? novoValor) {
                        setState(() {
                          _categoriaSelecionada = novoValor;
                        });
                      },
                      validator: (value) =>
                          value == null ? 'Escolha uma categoria' : null,
                    ),
                    const SizedBox(height: 15),

                    // ==========================================
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

                    ElevatedButton.icon(
                      onPressed: _salvarProduto,
                      icon: const Icon(Icons.save, color: Colors.white),
                      label: const Text(
                        "CADASTRAR PRODUTO",
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
