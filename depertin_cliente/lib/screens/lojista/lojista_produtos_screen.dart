import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../services/location_service.dart';
import '../../services/permissoes_app_service.dart';

const Color diPertinRoxo = Color(0xFF6A1B9A);
const Color diPertinLaranja = Color(0xFFFF8F00);

class LojistaProdutosScreen extends StatefulWidget {
  const LojistaProdutosScreen({super.key, this.uidLoja});

  final String? uidLoja;

  @override
  State<LojistaProdutosScreen> createState() => _LojistaProdutosScreenState();
}

class _LojistaProdutosScreenState extends State<LojistaProdutosScreen> {
  late final String _uid = widget.uidLoja ?? FirebaseAuth.instance.currentUser!.uid;
  final TextEditingController _buscaController = TextEditingController();

  late final Stream<QuerySnapshot> _streamProdutos = FirebaseFirestore.instance
      .collection('produtos')
      .where('lojista_id', isEqualTo: _uid)
      .snapshots();

  @override
  void dispose() {
    _buscaController.dispose();
    super.dispose();
  }

  void _abrirFormularioProduto({DocumentSnapshot? produtoExistente}) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
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
    final bool? confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.delete_outline, color: Colors.red),
            SizedBox(width: 8),
            Text('Excluir produto?'),
          ],
        ),
        content: const Text(
          'Esta ação não pode ser desfeita. As fotos no armazenamento também serão removidas.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (confirmar != true) return;

    try {
      if (urlsImagens != null) {
        for (final url in urlsImagens) {
          if (url.toString().contains('firebasestorage')) {
            await FirebaseStorage.instance.refFromURL(url.toString()).delete();
          }
        }
      }
      await FirebaseFirestore.instance.collection('produtos').doc(id).delete();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Produto removido.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Erro ao excluir: $e');
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Não foi possível excluir: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  List<QueryDocumentSnapshot> _filtrarEOrdenar(
    List<QueryDocumentSnapshot> docs,
    String busca,
  ) {
    var lista = docs.toList();
    if (busca.trim().isNotEmpty) {
      final q = busca.trim().toLowerCase();
      lista = lista.where((d) {
        final m = d.data() as Map<String, dynamic>;
        final nome = (m['nome'] ?? '').toString().toLowerCase();
        final cat = (m['categoria_nome'] ?? m['categoria'] ?? '')
            .toString()
            .toLowerCase();
        return nome.contains(q) || cat.contains(q);
      }).toList();
    }
    lista.sort((a, b) {
      final na = ((a.data() as Map)['nome'] ?? '').toString().toLowerCase();
      final nb = ((b.data() as Map)['nome'] ?? '').toString().toLowerCase();
      return na.compareTo(nb);
    });
    return lista;
  }

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat.currency(locale: 'pt_BR', symbol: r'R$');

    return Scaffold(
      backgroundColor: const Color(0xFFF5F4F8),
      appBar: AppBar(
        title: const Text(
          'Meu estoque',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            letterSpacing: -0.3,
          ),
        ),
        backgroundColor: diPertinLaranja,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        surfaceTintColor: Colors.transparent,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _abrirFormularioProduto(),
        backgroundColor: diPertinRoxo,
        foregroundColor: Colors.white,
        elevation: 4,
        icon: const Icon(Icons.add_rounded),
        label: const Text(
          'Novo produto',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: diPertinLaranja,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: TextField(
                controller: _buscaController,
                onChanged: (_) => setState(() {}),
                style: const TextStyle(color: Color(0xFF1A1A2E)),
                decoration: InputDecoration(
                  hintText: 'Buscar por nome ou categoria…',
                  hintStyle: TextStyle(color: Colors.grey.shade600),
                  prefixIcon: Icon(
                    Icons.search_rounded,
                    color: Colors.grey.shade700,
                  ),
                  suffixIcon: _buscaController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded),
                          onPressed: () {
                            _buscaController.clear();
                            setState(() {});
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _streamProdutos,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting &&
                    !snapshot.hasData) {
                  return const Center(
                    child: CircularProgressIndicator(color: diPertinLaranja),
                  );
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Não foi possível carregar o estoque.\n${snapshot.error}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                  );
                }

                final todos = snapshot.data?.docs ?? [];
                final filtrados = _filtrarEOrdenar(
                  todos,
                  _buscaController.text,
                );

                if (todos.isEmpty) {
                  return _EstadoVazioEstoque(
                    onAdicionar: () => _abrirFormularioProduto(),
                  );
                }

                if (filtrados.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.search_off_rounded,
                            size: 56,
                            color: Colors.grey.shade400,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Nenhum produto encontrado',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: Colors.grey.shade800,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Tente outro termo ou limpe a busca.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                      child: Row(
                        children: [
                          Text(
                            '${filtrados.length} ${filtrados.length == 1 ? 'produto' : 'produtos'}',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey.shade700,
                            ),
                          ),
                          if (todos.length != filtrados.length) ...[
                            Text(
                              ' · filtrado de ${todos.length}',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade500,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                        itemCount: filtrados.length,
                        itemBuilder: (context, index) {
                          final doc = filtrados[index];
                          final p = doc.data() as Map<String, dynamic>;
                          final urlImg =
                              (p['imagens'] != null &&
                                  (p['imagens'] as List).isNotEmpty)
                              ? (p['imagens'] as List).first.toString()
                              : '';
                          final bool ativo = p['ativo'] != false;
                          final double preco = (p['preco'] ?? 0.0) is num
                              ? (p['preco'] as num).toDouble()
                              : 0.0;
                          final String tipoVenda =
                              (p['tipo_venda'] ?? 'pronta_entrega').toString();
                          final int estoque = (p['estoque_qtd'] ?? 0) is num
                              ? (p['estoque_qtd'] as num).toInt()
                              : int.tryParse('${p['estoque_qtd']}') ?? 0;
                          final String? categoria =
                              p['categoria_nome']?.toString() ??
                              p['categoria']?.toString();

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Material(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              clipBehavior: Clip.antiAlias,
                              elevation: 1,
                              shadowColor: Colors.black.withValues(alpha: 0.06),
                              child: InkWell(
                                onTap: () => _abrirFormularioProduto(
                                  produtoExistente: doc,
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(12),
                                        child: urlImg.isNotEmpty
                                            ? Image.network(
                                                urlImg,
                                                width: 72,
                                                height: 72,
                                                fit: BoxFit.cover,
                                                errorBuilder: (_, _, _) =>
                                                    _thumbPlaceholder(),
                                              )
                                            : SizedBox(
                                                width: 72,
                                                height: 72,
                                                child: _thumbPlaceholder(),
                                              ),
                                      ),
                                      const SizedBox(width: 14),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    p['nome'] ?? 'Sem nome',
                                                    maxLines: 2,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.w800,
                                                      fontSize: 16,
                                                      height: 1.2,
                                                      color: ativo
                                                          ? const Color(
                                                              0xFF1A1A2E,
                                                            )
                                                          : Colors.grey,
                                                    ),
                                                  ),
                                                ),
                                                if (!ativo)
                                                  Container(
                                                    margin:
                                                        const EdgeInsets.only(
                                                          left: 6,
                                                        ),
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 8,
                                                          vertical: 2,
                                                        ),
                                                    decoration: BoxDecoration(
                                                      color:
                                                          Colors.grey.shade200,
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            8,
                                                          ),
                                                    ),
                                                    child: Text(
                                                      'Inativo',
                                                      style: TextStyle(
                                                        fontSize: 10,
                                                        fontWeight:
                                                            FontWeight.w700,
                                                        color: Colors
                                                            .grey
                                                            .shade700,
                                                      ),
                                                    ),
                                                  ),
                                              ],
                                            ),
                                            const SizedBox(height: 6),
                                            Wrap(
                                              spacing: 6,
                                              runSpacing: 4,
                                              children: [
                                                if (categoria != null &&
                                                    categoria.isNotEmpty)
                                                  _MiniChip(
                                                    label: categoria,
                                                    icon: Icons.label_outline,
                                                  ),
                                                if (tipoVenda == 'encomenda')
                                                  const _MiniChip(
                                                    label: 'Encomenda',
                                                    icon: Icons.schedule,
                                                    corFundo: Color(0xFFFFF3E0),
                                                    corTexto: diPertinLaranja,
                                                  )
                                                else if (estoque <= 0)
                                                  const _MiniChip(
                                                    label: 'Sem estoque',
                                                    icon: Icons
                                                        .inventory_2_outlined,
                                                    corFundo: Color(0xFFFFEBEE),
                                                    corTexto: Colors.red,
                                                  )
                                                else
                                                  _MiniChip(
                                                    label: 'Estoque: $estoque',
                                                    icon: Icons
                                                        .inventory_2_outlined,
                                                    corFundo: const Color(
                                                      0xFFE8F5E9,
                                                    ),
                                                    corTexto:
                                                        Colors.green.shade800,
                                                  ),
                                              ],
                                            ),
                                            const SizedBox(height: 8),
                                            Text(
                                              fmt.format(preco),
                                              style: const TextStyle(
                                                fontSize: 18,
                                                fontWeight: FontWeight.w800,
                                                color: diPertinLaranja,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          IconButton(
                                            tooltip: 'Editar',
                                            icon: Icon(
                                              Icons.edit_outlined,
                                              color: diPertinRoxo.withValues(
                                                alpha: 0.9,
                                              ),
                                            ),
                                            onPressed: () =>
                                                _abrirFormularioProduto(
                                                  produtoExistente: doc,
                                                ),
                                          ),
                                          IconButton(
                                            tooltip: 'Excluir',
                                            icon: const Icon(
                                              Icons.delete_outline,
                                              color: Colors.red,
                                            ),
                                            onPressed: () => _excluirProduto(
                                              doc.id,
                                              p['imagens'] is List
                                                  ? List<dynamic>.from(
                                                      p['imagens'] as List,
                                                    )
                                                  : null,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _thumbPlaceholder() {
    return Container(
      color: const Color(0xFFEDEAF2),
      alignment: Alignment.center,
      child: Icon(
        Icons.image_not_supported_outlined,
        color: Colors.grey.shade400,
        size: 28,
      ),
    );
  }
}

class _MiniChip extends StatelessWidget {
  const _MiniChip({
    required this.label,
    required this.icon,
    this.corFundo = const Color(0xFFF0EBF5),
    this.corTexto = diPertinRoxo,
  });

  final String label;
  final IconData icon;
  final Color corFundo;
  final Color corTexto;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: corFundo,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: corTexto),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: corTexto,
            ),
          ),
        ],
      ),
    );
  }
}

class _EstadoVazioEstoque extends StatelessWidget {
  const _EstadoVazioEstoque({required this.onAdicionar});

  final VoidCallback onAdicionar;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Icon(
                Icons.inventory_2_outlined,
                size: 64,
                color: diPertinLaranja.withValues(alpha: 0.85),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Seu estoque está vazio',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: Color(0xFF1A1A2E),
                letterSpacing: -0.4,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Cadastre produtos com fotos, preço e categoria para aparecerem na vitrine do app.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                height: 1.45,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 28),
            FilledButton.icon(
              onPressed: onAdicionar,
              style: FilledButton.styleFrom(
                backgroundColor: diPertinRoxo,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: const Icon(Icons.add_rounded),
              label: const Text(
                'Cadastrar primeiro produto',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class FormularioProdutoModal extends StatefulWidget {
  const FormularioProdutoModal({
    super.key,
    required this.lojistaId,
    this.produtoExistente,
  });

  final String lojistaId;
  final DocumentSnapshot? produtoExistente;

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

  InputDecoration _fieldDecoration(String label, {String? hint}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      filled: true,
      fillColor: const Color(0xFFF8F7FA),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: diPertinLaranja, width: 2),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _carregarDadosLojista();
    if (widget.produtoExistente != null) {
      final p = widget.produtoExistente!.data() as Map<String, dynamic>;
      _nomeController.text = p['nome'] ?? '';
      _descricaoController.text = p['descricao'] ?? '';
      _precoController.text = (p['preco'] ?? 0.0).toStringAsFixed(2);
      _categoriaSelecionada = p['categoria_nome']?.toString();
      _imagensAtuais = List<dynamic>.from(p['imagens'] ?? []);
      _tipoVenda = p['tipo_venda'] ?? 'pronta_entrega';
      _estoqueController.text = (p['estoque_qtd'] ?? 1).toString();
      _prazoController.text = p['prazo_encomenda'] ?? '';
    }
  }

  @override
  void dispose() {
    _nomeController.dispose();
    _descricaoController.dispose();
    _precoController.dispose();
    _estoqueController.dispose();
    _prazoController.dispose();
    super.dispose();
  }

  Future<void> _carregarDadosLojista() async {
    try {
      final DocumentSnapshot doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.lojistaId)
          .get();
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        _cidadeLoja = (data['cidade'] ?? '').toString();
        _ufLoja = (data['uf'] ?? data['estado'] ?? '').toString();
        _nomeLoja =
            data['loja_nome'] ?? data['nome_loja'] ?? data['nome'] ?? 'Loja';
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Erro ao carregar dados do lojista: $e');
      }
    }
  }

  Future<void> _sugerirCategoria() async {
    final String? nomeSugestao = await showDialog<String>(
      context: context,
      builder: (ctx) => const _SugerirCategoriaDialog(),
    );
    if (nomeSugestao == null || nomeSugestao.isEmpty) return;

    await FirebaseFirestore.instance.collection('sugestoes_categorias').add({
      'nome': nomeSugestao,
      'lojista_id': widget.lojistaId,
      'data': FieldValue.serverTimestamp(),
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sugestão enviada. Obrigado!'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Future<void> _pegarImagem() async {
    final ResultadoPermissao pr =
        await PermissoesAppService.garantirGaleriaFotos();
    if (!mounted) return;
    if (pr != ResultadoPermissao.concedida) {
      PermissoesFeedback.galeria(context, pr);
      return;
    }
    final pickedFiles = await ImagePicker().pickMultiImage(imageQuality: 70);
    if (pickedFiles.isNotEmpty) {
      setState(() {
        for (final file in pickedFiles) {
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
        const SnackBar(
          content: Text('Preencha nome, preço e categoria.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    setState(() => _salvando = true);
    try {
      final List<String> urlsFinais = List<String>.from(
        _imagensAtuais.map((e) => e.toString()),
      );
      for (final file in _novasImagens) {
        final String path =
            'produtos/${widget.lojistaId}_${DateTime.now().millisecondsSinceEpoch}.jpg';
        final TaskSnapshot task = await FirebaseStorage.instance
            .ref()
            .child(path)
            .putFile(file);
        urlsFinais.add(await task.ref.getDownloadURL());
      }

      final dados = <String, dynamic>{
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
        'uf_normalizado':
            LocationService.extrairUf(_ufLoja) ??
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
      if (kDebugMode) {
        debugPrint('Erro ao salvar: $e');
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao salvar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.92,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 10),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    widget.produtoExistente != null
                        ? 'Editar produto'
                        : 'Novo produto',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF1A1A2E),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Fotos nítidas e informações corretas ajudam nas vendas.',
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 20),
                  _secaoTitulo('Fotos', Icons.photo_library_outlined),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 88,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        ..._imagensAtuais.asMap().entries.map(
                          (e) => _imgCard(
                            url: e.value.toString(),
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
                          Material(
                            color: const Color(0xFFF0EBF5),
                            borderRadius: BorderRadius.circular(12),
                            child: InkWell(
                              onTap: _pegarImagem,
                              borderRadius: BorderRadius.circular(12),
                              child: const SizedBox(
                                width: 88,
                                height: 88,
                                child: Icon(
                                  Icons.add_photo_alternate_outlined,
                                  color: diPertinRoxo,
                                  size: 32,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  _secaoTitulo('Informações', Icons.edit_note_outlined),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _nomeController,
                    textCapitalization: TextCapitalization.words,
                    decoration: _fieldDecoration('Nome do produto *'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _descricaoController,
                    textCapitalization: TextCapitalization.sentences,
                    maxLines: 3,
                    decoration: _fieldDecoration(
                      'Descrição',
                      hint: 'Opcional — ingredientes, tamanho…',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _precoController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[\d.,]')),
                    ],
                    decoration: _fieldDecoration(
                      'Preço *',
                    ).copyWith(prefixText: 'R\$ '),
                  ),
                  const SizedBox(height: 16),
                  _secaoTitulo('Tipo de venda', Icons.local_shipping_outlined),
                  const SizedBox(height: 8),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(
                        value: 'pronta_entrega',
                        label: Text('Estoque'),
                        icon: Icon(Icons.inventory_2_outlined, size: 18),
                      ),
                      ButtonSegment(
                        value: 'encomenda',
                        label: Text('Encomenda'),
                        icon: Icon(Icons.schedule, size: 18),
                      ),
                    ],
                    selected: {_tipoVenda},
                    onSelectionChanged: (s) =>
                        setState(() => _tipoVenda = s.first),
                    style: ButtonStyle(
                      visualDensity: VisualDensity.compact,
                      foregroundColor: WidgetStateProperty.resolveWith((
                        states,
                      ) {
                        if (states.contains(WidgetState.selected)) {
                          return Colors.white;
                        }
                        return diPertinRoxo;
                      }),
                      backgroundColor: WidgetStateProperty.resolveWith((
                        states,
                      ) {
                        if (states.contains(WidgetState.selected)) {
                          return diPertinLaranja;
                        }
                        return const Color(0xFFF5F4F8);
                      }),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_tipoVenda == 'pronta_entrega')
                    TextField(
                      controller: _estoqueController,
                      keyboardType: TextInputType.number,
                      decoration: _fieldDecoration('Quantidade em estoque'),
                    ),
                  if (_tipoVenda == 'encomenda')
                    TextField(
                      controller: _prazoController,
                      decoration: _fieldDecoration(
                        'Prazo de produção',
                        hint: 'Ex.: 2 dias úteis',
                      ),
                    ),
                  const SizedBox(height: 20),
                  _secaoTitulo('Categoria', Icons.category_outlined),
                  const SizedBox(height: 10),
                  StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('categorias')
                        .orderBy('nome')
                        .snapshots(),
                    builder: (context, snap) {
                      if (!snap.hasData) {
                        return const LinearProgressIndicator(
                          color: diPertinLaranja,
                        );
                      }
                      return DropdownButtonFormField<String>(
                        key: ValueKey(_categoriaSelecionada),
                        initialValue: _categoriaSelecionada,
                        isExpanded: true,
                        decoration: _fieldDecoration('Selecione *'),
                        items: snap.data!.docs
                            .map(
                              (d) => DropdownMenuItem(
                                value: d['nome'].toString(),
                                child: Text(d['nome'].toString()),
                              ),
                            )
                            .toList(),
                        onChanged: (v) =>
                            setState(() => _categoriaSelecionada = v),
                      );
                    },
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: _sugerirCategoria,
                      icon: const Icon(Icons.lightbulb_outline, size: 18),
                      label: const Text('Sugerir nova categoria'),
                      style: TextButton.styleFrom(
                        foregroundColor: diPertinRoxo,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _salvando ? null : _salvar,
                    style: FilledButton.styleFrom(
                      backgroundColor: diPertinLaranja,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: _salvando
                        ? const SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            'Salvar produto',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _secaoTitulo(String titulo, IconData icone) {
    return Row(
      children: [
        Icon(icone, size: 20, color: diPertinRoxo),
        const SizedBox(width: 8),
        Text(
          titulo,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: Color(0xFF1A1A2E),
          ),
        ),
      ],
    );
  }

  Widget _imgCard({String? url, File? file, required VoidCallback onDel}) {
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: 88,
              height: 88,
              child: url != null
                  ? Image.network(
                      url,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Container(
                        color: Colors.grey.shade200,
                        child: const Icon(Icons.broken_image_outlined),
                      ),
                    )
                  : Image.file(file!, fit: BoxFit.cover),
            ),
          ),
          Positioned(
            top: -6,
            right: -6,
            child: Material(
              color: Colors.red,
              shape: const CircleBorder(),
              child: InkWell(
                onTap: onDel,
                customBorder: const CircleBorder(),
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.close, size: 16, color: Colors.white),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Dialog interno com ciclo de vida próprio para o TextEditingController,
// evitando o `_dependents.isEmpty` assertion que acontecia ao dar dispose
// no controller logo após Navigator.pop.
class _SugerirCategoriaDialog extends StatefulWidget {
  const _SugerirCategoriaDialog();

  @override
  State<_SugerirCategoriaDialog> createState() =>
      _SugerirCategoriaDialogState();
}

class _SugerirCategoriaDialogState extends State<_SugerirCategoriaDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _enviar() {
    final texto = _controller.text.trim();
    if (texto.isEmpty) return;
    Navigator.pop(context, texto);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text(
        'Sugerir categoria',
        style: TextStyle(color: diPertinLaranja),
      ),
      content: TextField(
        controller: _controller,
        textCapitalization: TextCapitalization.words,
        autofocus: true,
        onSubmitted: (_) => _enviar(),
        decoration: const InputDecoration(
          hintText: 'Ex.: Veganos, doces…',
          border: OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _enviar,
          child: const Text('Enviar'),
        ),
      ],
    );
  }
}
