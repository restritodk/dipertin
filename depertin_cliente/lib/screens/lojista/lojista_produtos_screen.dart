import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import '../../services/location_service.dart';

const Color diPertinRoxo = Color(0xFF6A1B9A);
const Color diPertinLaranja = Color(0xFFFF8F00);

class LojistaProdutosScreen extends StatefulWidget {
  const LojistaProdutosScreen({super.key});

  @override
  State<LojistaProdutosScreen> createState() => _LojistaProdutosScreenState();
}

class _LojistaProdutosScreenState extends State<LojistaProdutosScreen> {
  final String _uid = FirebaseAuth.instance.currentUser!.uid;

  void _abrirFormularioProduto({DocumentSnapshot? produtoExistente}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: FormularioProdutoModal(
          lojistaId: _uid,
          produtoExistente: produtoExistente,
        ),
      ),
    );
  }

  Future<void> _excluirProduto(String id, List<dynamic>? urlsImagens) async {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(
          "Excluir Produto?",
          style: TextStyle(color: Colors.red),
        ),
        content: const Text("Deseja realmente apagar este item?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancelar"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              try {
                if (urlsImagens != null) {
                  for (var url in urlsImagens) {
                    if (url.toString().contains('firebasestorage')) {
                      await FirebaseStorage.instance
                          .refFromURL(url.toString())
                          .delete();
                    }
                  }
                }
                await FirebaseFirestore.instance
                    .collection('produtos')
                    .doc(id)
                    .delete();
                if (mounted) Navigator.pop(context);
              } catch (e) {
                debugPrint("Erro ao excluir: $e");
              }
            },
            child: const Text("Excluir", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text(
          "Meu Estoque",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: diPertinLaranja,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _abrirFormularioProduto(),
        backgroundColor: diPertinLaranja,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text(
          "Novo Produto",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('produtos')
            .where('lojista_id', isEqualTo: _uid)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text("Nenhum produto cadastrado."));
          }
          var produtos = snapshot.data!.docs;
          return ListView.builder(
            padding: const EdgeInsets.all(15),
            itemCount: produtos.length,
            itemBuilder: (context, index) {
              var doc = produtos[index];
              var p = doc.data() as Map<String, dynamic>;
              String urlImg = (p['imagens'] != null && p['imagens'].isNotEmpty)
                  ? p['imagens'][0]
                  : '';
              return Card(
                elevation: 2,
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
                child: ListTile(
                  onTap: () => _abrirFormularioProduto(produtoExistente: doc),
                  leading: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      urlImg,
                      width: 50,
                      height: 50,
                      fit: BoxFit.cover,
                      errorBuilder: (c, e, s) => const Icon(Icons.broken_image),
                    ),
                  ),
                  title: Text(
                    p['nome'] ?? 'Sem nome',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    "R\$ ${(p['preco'] ?? 0.0).toStringAsFixed(2)}",
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    onPressed: () => _excluirProduto(doc.id, p['imagens']),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class FormularioProdutoModal extends StatefulWidget {
  final String lojistaId;
  final DocumentSnapshot? produtoExistente;
  const FormularioProdutoModal({
    super.key,
    required this.lojistaId,
    this.produtoExistente,
  });

  @override
  State<FormularioProdutoModal> createState() => _FormularioProdutoModalState();
}

class _FormularioProdutoModalState extends State<FormularioProdutoModal> {
  final _nomeController = TextEditingController();
  final _descricaoController = TextEditingController();
  final _precoController = TextEditingController();
  final _estoqueController = TextEditingController(text: '1');
  final _prazoController = TextEditingController();

  String? _categoriaSelecionada;
  final List<File> _novasImagens = [];
  List<dynamic> _imagensAtuais = [];
  bool _salvando = false;
  String _tipoVenda = 'pronta_entrega';

  String _cidadeLoja = '';
  String _ufLoja = '';
  String _nomeLoja = '';

  @override
  void initState() {
    super.initState();
    _carregarDadosLojista();
    if (widget.produtoExistente != null) {
      var p = widget.produtoExistente!.data() as Map<String, dynamic>;
      _nomeController.text = p['nome'] ?? '';
      _descricaoController.text = p['descricao'] ?? '';
      _precoController.text = (p['preco'] ?? 0.0).toStringAsFixed(2);
      _categoriaSelecionada = p['categoria_nome'];
      _imagensAtuais = p['imagens'] ?? [];
      _tipoVenda = p['tipo_venda'] ?? 'pronta_entrega';
      _estoqueController.text = (p['estoque_qtd'] ?? 1).toString();
      _prazoController.text = p['prazo_encomenda'] ?? '';
    }
  }

  Future<void> _carregarDadosLojista() async {
    try {
      DocumentSnapshot doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.lojistaId)
          .get();
      if (doc.exists) {
        var data = doc.data() as Map<String, dynamic>;
        _cidadeLoja = (data['cidade'] ?? '').toString();
        _ufLoja = (data['uf'] ?? data['estado'] ?? '').toString();
        _nomeLoja = data['nome_loja'] ?? data['nome'] ?? 'Loja Parceira';
      }
    } catch (e) {
      debugPrint("Erro ao carregar dados do lojista: $e");
    }
  }

  // FUNÇÃO DE SUGERIR CATEGORIA (RESTAURADA)
  Future<void> _sugerirCategoria() async {
    TextEditingController sugController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(
          "Sugerir Categoria",
          style: TextStyle(color: diPertinLaranja),
        ),
        content: TextField(
          controller: sugController,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(hintText: "Ex: Veganos, Doces..."),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancelar"),
          ),
          ElevatedButton(
            onPressed: () async {
              if (sugController.text.isNotEmpty) {
                await FirebaseFirestore.instance
                    .collection('sugestoes_categorias')
                    .add({
                      'nome': sugController.text.trim(),
                      'lojista_id': widget.lojistaId,
                      'data': FieldValue.serverTimestamp(),
                    });
                if (mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Sugestão enviada! 🚀')),
                  );
                }
              }
            },
            child: const Text("Enviar"),
          ),
        ],
      ),
    );
  }

  Future<void> _pegarImagem() async {
    final pickedFiles = await ImagePicker().pickMultiImage(imageQuality: 70);
    if (pickedFiles.isNotEmpty) {
      setState(() {
        for (var file in pickedFiles) {
          if (_novasImagens.length + _imagensAtuais.length < 5) {
            _novasImagens.add(File(file.path));
          }
        }
      });
    }
  }

  Future<void> _salvar() async {
    if (_nomeController.text.isEmpty ||
        _precoController.text.isEmpty ||
        _categoriaSelecionada == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Preencha os campos obrigatórios!')),
      );
      return;
    }
    setState(() => _salvando = true);
    try {
      List<String> urlsFinais = List<String>.from(_imagensAtuais);
      for (var file in _novasImagens) {
        String path =
            'produtos/${widget.lojistaId}_${DateTime.now().millisecondsSinceEpoch}.jpg';
        TaskSnapshot task = await FirebaseStorage.instance
            .ref()
            .child(path)
            .putFile(file);
        urlsFinais.add(await task.ref.getDownloadURL());
      }

      var dados = {
        'lojista_id': widget.lojistaId,
        'loja_id': widget.lojistaId,
        'loja_nome': _nomeLoja,
        'nome': _nomeController.text.trim(),
        'descricao': _descricaoController.text.trim(),
        'preco':
            double.tryParse(_precoController.text.replaceAll(',', '.')) ?? 0.0,
        'categoria': _categoriaSelecionada,
        'categoria_nome': _categoriaSelecionada,
        'imagens': urlsFinais,
        'tipo_venda': _tipoVenda,
        'estoque_qtd': int.tryParse(_estoqueController.text) ?? 0,
        'prazo_encomenda': _prazoController.text.trim(),
        'ativo': true,
        'cidade': _cidadeLoja,
        'uf': _ufLoja,
        'cidade_normalizada': LocationService.normalizar(_cidadeLoja),
        'uf_normalizado': LocationService.extrairUf(_ufLoja) ??
            LocationService.normalizar(_ufLoja),
      };

      if (widget.produtoExistente != null) {
        await FirebaseFirestore.instance
            .collection('produtos')
            .doc(widget.produtoExistente!.id)
            .update(dados);
      } else {
        dados['data_criacao'] = FieldValue.serverTimestamp();
        await FirebaseFirestore.instance.collection('produtos').add(dados);
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      debugPrint("Erro ao salvar: $e");
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.produtoExistente != null
                  ? "Editar Produto"
                  : "Novo Produto",
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 15),

            // FOTOS
            SizedBox(
              height: 80,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  ..._imagensAtuais.asMap().entries.map(
                    (e) => _imgCard(
                      url: e.value,
                      onDel: () =>
                          setState(() => _imagensAtuais.removeAt(e.key)),
                    ),
                  ),
                  ..._novasImagens.asMap().entries.map(
                    (e) => _imgCard(
                      file: e.value,
                      onDel: () =>
                          setState(() => _novasImagens.removeAt(e.key)),
                    ),
                  ),
                  if (_imagensAtuais.length + _novasImagens.length < 5)
                    GestureDetector(
                      onTap: _pegarImagem,
                      child: Container(
                        width: 80,
                        color: Colors.grey[200],
                        child: const Icon(Icons.add_a_photo),
                      ),
                    ),
                ],
              ),
            ),

            const SizedBox(height: 15),
            TextField(
              controller: _nomeController,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: "Nome",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _descricaoController,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: "Descrição",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _precoController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: "Preço",
                prefixText: "R\$ ",
                border: OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 10),
            // TIPO DE VENDA
            Row(
              children: [
                Expanded(
                  child: RadioListTile(
                    title: const Text(
                      "Estoque",
                      style: TextStyle(fontSize: 12),
                    ),
                    value: 'pronta_entrega',
                    groupValue: _tipoVenda,
                    activeColor: diPertinLaranja,
                    onChanged: (v) => setState(() => _tipoVenda = v.toString()),
                  ),
                ),
                Expanded(
                  child: RadioListTile(
                    title: const Text(
                      "Encomenda",
                      style: TextStyle(fontSize: 12),
                    ),
                    value: 'encomenda',
                    groupValue: _tipoVenda,
                    activeColor: diPertinLaranja,
                    onChanged: (v) => setState(() => _tipoVenda = v.toString()),
                  ),
                ),
              ],
            ),
            if (_tipoVenda == 'pronta_entrega')
              TextField(
                controller: _estoqueController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: "Qtd em Estoque",
                  border: OutlineInputBorder(),
                ),
              ),
            if (_tipoVenda == 'encomenda')
              TextField(
                controller: _prazoController,
                decoration: const InputDecoration(
                  labelText: "Prazo (Ex: 2 dias)",
                  border: OutlineInputBorder(),
                ),
              ),

            const SizedBox(height: 10),
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('categorias')
                  .orderBy('nome')
                  .snapshots(),
              builder: (context, snap) {
                if (!snap.hasData) return const LinearProgressIndicator();
                return DropdownButtonFormField<String>(
                  initialValue: _categoriaSelecionada,
                  decoration: const InputDecoration(
                    labelText: "Categoria",
                    border: OutlineInputBorder(),
                  ),
                  items: snap.data!.docs
                      .map(
                        (d) => DropdownMenuItem(
                          value: d['nome'].toString(),
                          child: Text(d['nome']),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setState(() => _categoriaSelecionada = v),
                );
              },
            ),

            // BOTÃO DE SUGERIR (CONECTADO)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _sugerirCategoria,
                child: const Text(
                  "Sugerir nova categoria",
                  style: TextStyle(
                    color: diPertinRoxo,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 15),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: diPertinLaranja,
                padding: const EdgeInsets.all(15),
              ),
              onPressed: _salvando ? null : _salvar,
              child: _salvando
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text(
                      "SALVAR",
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _imgCard({String? url, File? file, required VoidCallback onDel}) {
    return Stack(
      children: [
        Container(
          margin: const EdgeInsets.only(right: 8),
          width: 80,
          height: 80,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: url != null
                ? Image.network(url, fit: BoxFit.cover)
                : Image.file(file!, fit: BoxFit.cover),
          ),
        ),
        Positioned(
          right: 0,
          child: GestureDetector(
            onTap: onDel,
            child: const CircleAvatar(
              radius: 10,
              backgroundColor: Colors.red,
              child: Icon(Icons.close, size: 12, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }
}
