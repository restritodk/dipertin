import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:depertin_web/theme/painel_admin_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class CategoriasScreen extends StatefulWidget {
  const CategoriasScreen({super.key});

  @override
  State<CategoriasScreen> createState() => _CategoriasScreenState();
}

class _CategoriasScreenState extends State<CategoriasScreen> {
  static const _roxo = PainelAdminTheme.roxo;
  static const _laranja = PainelAdminTheme.laranja;

  final _buscaCtrl = TextEditingController();

  @override
  void dispose() {
    _buscaCtrl.dispose();
    super.dispose();
  }

  InputDecoration _dec(String label, {String? hint}) => InputDecoration(
    labelText: label,
    hintText: hint,
    filled: true,
    fillColor: const Color(0xFFF8F7FC),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: Colors.grey.shade300),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: Colors.grey.shade300),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: _roxo, width: 1.5),
    ),
  );

  String _slug(String texto) {
    var t = texto.trim().toLowerCase();
    const mapa = {
      'á': 'a',
      'à': 'a',
      'ã': 'a',
      'â': 'a',
      'ä': 'a',
      'é': 'e',
      'è': 'e',
      'ê': 'e',
      'ë': 'e',
      'í': 'i',
      'ì': 'i',
      'î': 'i',
      'ï': 'i',
      'ó': 'o',
      'ò': 'o',
      'õ': 'o',
      'ô': 'o',
      'ö': 'o',
      'ú': 'u',
      'ù': 'u',
      'û': 'u',
      'ü': 'u',
      'ç': 'c',
    };
    final buf = StringBuffer();
    for (final r in t.runes) {
      final ch = String.fromCharCode(r);
      buf.write(mapa[ch] ?? ch);
    }
    t = buf
        .toString()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    return t.isEmpty ? 'categoria' : t;
  }

  List<String> _sinonimos(String texto) {
    return texto
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();
  }

  String _iconeCodigoPorTipo(String tipo) {
    switch (tipo) {
      case 'servico':
        return 'servico';
      case 'ambos':
        return 'produto_servico';
      case 'produto':
      default:
        return 'produto';
    }
  }

  IconData _iconeVisualPorTipo(String tipo) {
    switch (tipo) {
      case 'servico':
        return Icons.home_repair_service_rounded;
      case 'ambos':
        return Icons.hub_rounded;
      case 'produto':
      default:
        return Icons.inventory_2_rounded;
    }
  }

  String _rotuloIconePorTipo(String tipo) {
    switch (tipo) {
      case 'servico':
        return 'Ícone automático: serviço';
      case 'ambos':
        return 'Ícone automático: produto + serviço';
      case 'produto':
      default:
        return 'Ícone automático: produto';
    }
  }

  String _rotuloTipo(String tipo) {
    switch (tipo) {
      case 'servico':
        return 'Serviço';
      case 'ambos':
        return 'Produto e serviço';
      case 'produto':
      default:
        return 'Produto';
    }
  }

  Future<bool> _abrirFormulario({
    String? docId,
    Map<String, dynamic>? dados,
    String? sugestaoNome,
  }) async {
    final isEdit = docId != null;
    final nomeC = TextEditingController(
      text: dados?['nome']?.toString() ?? sugestaoNome ?? '',
    );
    final slugC = TextEditingController(text: dados?['slug']?.toString() ?? '');
    final grupoC = TextEditingController(
      text: dados?['grupo']?.toString() ?? '',
    );
    final imagemC = TextEditingController(
      text: dados?['imagem']?.toString() ?? '',
    );
    final ordemC = TextEditingController(
      text: dados?['ordem'] != null ? dados!['ordem'].toString() : '100',
    );
    final sinonimosC = TextEditingController(
      text: (dados?['sinonimos'] is List)
          ? (dados!['sinonimos'] as List).join(', ')
          : '',
    );
    var ativo = dados?['ativo'] != false;
    var destaque = dados?['destaque'] == true;
    var tipo = (dados?['tipo'] ?? 'produto').toString();
    if (!['produto', 'servico', 'ambos'].contains(tipo)) tipo = 'produto';
    var salvando = false;

    final salvo = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          Future<void> salvar() async {
            final nome = nomeC.text.trim();
            if (nome.isEmpty) {
              ScaffoldMessenger.of(ctx).showSnackBar(
                const SnackBar(content: Text('Informe o nome da categoria.')),
              );
              return;
            }
            setS(() => salvando = true);
            try {
              final slug = slugC.text.trim().isEmpty
                  ? _slug(nome)
                  : _slug(slugC.text);
              final patch = <String, dynamic>{
                'nome': nome,
                'slug': slug,
                'grupo': grupoC.text.trim(),
                'imagem': imagemC.text.trim(),
                'icone': _iconeCodigoPorTipo(tipo),
                'ordem': int.tryParse(ordemC.text.trim()) ?? 100,
                'sinonimos': _sinonimos(sinonimosC.text),
                'ativo': ativo,
                'destaque': destaque,
                'tipo': tipo,
                'atualizada_em': FieldValue.serverTimestamp(),
              };
              final col = FirebaseFirestore.instance.collection('categorias');
              if (isEdit) {
                await col.doc(docId).update(patch);
              } else {
                patch['criada_em'] = FieldValue.serverTimestamp();
                await col.doc(slug).set(patch);
              }
              if (ctx.mounted) Navigator.pop(ctx, true);
            } catch (e) {
              if (ctx.mounted) {
                ScaffoldMessenger.of(
                  ctx,
                ).showSnackBar(SnackBar(content: Text('Erro: $e')));
              }
            } finally {
              if (ctx.mounted) setS(() => salvando = false);
            }
          }

          return Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
            ),
            clipBehavior: Clip.antiAlias,
            backgroundColor: Colors.white,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          _roxo.withValues(alpha: 0.10),
                          _laranja.withValues(alpha: 0.05),
                        ],
                      ),
                      border: Border(
                        bottom: BorderSide(color: Colors.grey.shade200),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(_iconeVisualPorTipo(tipo), color: _roxo),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            isEdit ? 'Editar categoria' : 'Nova categoria',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: _roxo,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: salvando
                              ? null
                              : () => Navigator.pop(ctx, false),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                  ),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(22, 18, 22, 10),
                      child: Column(
                        children: [
                          TextField(
                            controller: nomeC,
                            decoration: _dec('Nome *'),
                            onChanged: (v) {
                              if (!isEdit && slugC.text.trim().isEmpty) {
                                setS(() {});
                              }
                            },
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: slugC,
                            decoration: _dec('Slug', hint: _slug(nomeC.text)),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: grupoC,
                                  decoration: _dec(
                                    'Grupo',
                                    hint: 'Ex.: Moda, Mercado, Casa',
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              SizedBox(
                                width: 140,
                                child: TextField(
                                  controller: ordemC,
                                  keyboardType: TextInputType.number,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly,
                                  ],
                                  decoration: _dec('Ordem'),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String>(
                            initialValue: tipo,
                            decoration: _dec('Tipo'),
                            items: const [
                              DropdownMenuItem(
                                value: 'produto',
                                child: Text('Produto'),
                              ),
                              DropdownMenuItem(
                                value: 'servico',
                                child: Text('Serviço'),
                              ),
                              DropdownMenuItem(
                                value: 'ambos',
                                child: Text('Produto e serviço'),
                              ),
                            ],
                            onChanged: (v) => setS(() => tipo = v ?? 'produto'),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: imagemC,
                            decoration: _dec('Imagem URL'),
                          ),
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: _roxo.withValues(alpha: 0.06),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: _roxo.withValues(alpha: 0.12),
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(_iconeVisualPorTipo(tipo), color: _roxo),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    _rotuloIconePorTipo(tipo),
                                    style: const TextStyle(
                                      color: PainelAdminTheme.dashboardInk,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: sinonimosC,
                            decoration: _dec(
                              'Sinônimos',
                              hint: 'moda, vestuário, roupa',
                            ),
                          ),
                          const SizedBox(height: 8),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            value: ativo,
                            onChanged: (v) => setS(() => ativo = v),
                            title: const Text('Categoria ativa'),
                          ),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            value: destaque,
                            onChanged: (v) => setS(() => destaque = v),
                            title: const Text('Mostrar em destaque no Buscar'),
                            subtitle: const Text(
                              'Use para as categorias principais do app.',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: salvando
                              ? null
                              : () => Navigator.pop(ctx, false),
                          child: const Text('Cancelar'),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.icon(
                          onPressed: salvando ? null : salvar,
                          icon: salvando
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.check_rounded),
                          label: Text(salvando ? 'Salvando...' : 'Salvar'),
                          style: FilledButton.styleFrom(
                            backgroundColor: _laranja,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    return salvo == true;
  }

  Future<void> _aprovarSugestao(
    String sugestaoId,
    Map<String, dynamic> dados,
  ) async {
    final salvo = await _abrirFormulario(
      sugestaoNome: dados['nome']?.toString() ?? '',
    );
    if (!salvo) return;
    await FirebaseFirestore.instance
        .collection('sugestoes_categorias')
        .doc(sugestaoId)
        .update({
          'status': 'aprovada',
          'analisada_em': FieldValue.serverTimestamp(),
        });
  }

  Future<void> _recusarSugestao(String sugestaoId) async {
    await FirebaseFirestore.instance
        .collection('sugestoes_categorias')
        .doc(sugestaoId)
        .update({
          'status': 'recusada',
          'analisada_em': FieldValue.serverTimestamp(),
        });
  }

  bool _sugestaoPendente(Map<String, dynamic> dados) {
    final status = (dados['status'] ?? '').toString().trim().toLowerCase();
    return status.isEmpty || status == 'pendente';
  }

  DateTime _dataSugestao(Map<String, dynamic> dados) {
    final raw = dados['data'] ?? dados['criada_em'] ?? dados['created_at'];
    if (raw is Timestamp) return raw.toDate();
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  Future<String> _nomeLojaSugestao(String lojistaId) async {
    if (lojistaId.trim().isEmpty) return 'Loja não identificada';
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(lojistaId)
          .get();
      final dados = snap.data() ?? {};
      final nome =
          (dados['loja_nome'] ??
                  dados['nome_loja'] ??
                  dados['nome_fantasia'] ??
                  dados['nome'] ??
                  '')
              .toString()
              .trim();
      return nome.isEmpty ? 'Loja sem nome cadastrado' : nome;
    } catch (_) {
      return 'Loja não identificada';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PainelAdminTheme.fundoCanvas,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: Colors.white,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 28, 28, 20),
              child: Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Categorias',
                          style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            color: _roxo,
                          ),
                        ),
                        SizedBox(height: 6),
                        Text(
                          'Gerencie categorias oficiais e sugestões enviadas pelos lojistas.',
                          style: TextStyle(
                            color: PainelAdminTheme.textoSecundario,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: 280,
                    child: TextField(
                      controller: _buscaCtrl,
                      onChanged: (_) => setState(() {}),
                      decoration: _dec(
                        'Buscar categoria',
                      ).copyWith(prefixIcon: const Icon(Icons.search_rounded)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    onPressed: _abrirFormulario,
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Nova categoria'),
                    style: FilledButton.styleFrom(
                      backgroundColor: _laranja,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 14,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Divider(height: 1, color: Colors.grey.shade200),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(flex: 3, child: _buildCategorias()),
                VerticalDivider(width: 1, color: Colors.grey.shade200),
                SizedBox(width: 360, child: _buildSugestoes()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategorias() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('categorias').snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        var docs = snap.data?.docs ?? [];
        final busca = _buscaCtrl.text.trim().toLowerCase();
        if (busca.isNotEmpty) {
          docs = docs.where((d) {
            final m = d.data();
            final txt = [
              m['nome'],
              m['slug'],
              m['grupo'],
              ...(m['sinonimos'] is List ? m['sinonimos'] as List : const []),
            ].join(' ').toLowerCase();
            return txt.contains(busca);
          }).toList();
        }
        if (docs.isEmpty) {
          return Center(
            child: Text(
              'Nenhuma categoria encontrada.',
              style: TextStyle(color: Colors.grey.shade700),
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(24),
          itemCount: docs.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, i) {
            final doc = docs[i];
            final d = doc.data();
            final ativo = d['ativo'] != false;
            final destaque = d['destaque'] == true;
            return Container(
              padding: const EdgeInsets.all(16),
              decoration: PainelAdminTheme.dashboardCard(),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: ativo
                        ? _roxo.withValues(alpha: 0.10)
                        : Colors.grey.shade200,
                    foregroundColor: ativo ? _roxo : Colors.grey,
                    child: Icon(
                      _iconeVisualPorTipo((d['tipo'] ?? 'produto').toString()),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          d['nome']?.toString() ?? 'Categoria',
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                            color: PainelAdminTheme.dashboardInk,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _rotuloTipo((d['tipo'] ?? 'produto').toString()),
                          style: const TextStyle(
                            color: PainelAdminTheme.textoSecundario,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (destaque)
                    const _ChipInfo(
                      texto: 'Destaque',
                      cor: _laranja,
                      icone: Icons.star_rounded,
                    ),
                  const SizedBox(width: 8),
                  _ChipInfo(
                    texto: ativo ? 'Ativa' : 'Inativa',
                    cor: ativo ? Colors.green : Colors.grey,
                    icone: ativo ? Icons.check_circle : Icons.pause_circle,
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: 'Editar',
                    onPressed: () => _abrirFormulario(docId: doc.id, dados: d),
                    icon: const Icon(Icons.edit_outlined),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildSugestoes() {
    return Container(
      color: Colors.white,
      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('sugestoes_categorias')
            .snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting &&
              !snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs =
              (snap.data?.docs ?? [])
                  .where((d) => _sugestaoPendente(d.data()))
                  .toList()
                ..sort((a, b) {
                  final da = _dataSugestao(a.data());
                  final db = _dataSugestao(b.data());
                  return db.compareTo(da);
                });
          final pendentes = docs.take(50).toList();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(18, 20, 18, 8),
                child: Text(
                  'Sugestões pendentes',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: _roxo,
                  ),
                ),
              ),
              Expanded(
                child: pendentes.isEmpty
                    ? Center(
                        child: Text(
                          'Sem sugestões pendentes.',
                          style: TextStyle(color: Colors.grey.shade700),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(18),
                        itemCount: pendentes.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, i) {
                          final doc = pendentes[i];
                          final d = doc.data();
                          return Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8F7FC),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: Colors.grey.shade200),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  d['nome']?.toString() ?? 'Sugestão',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                FutureBuilder<String>(
                                  future: _nomeLojaSugestao(
                                    (d['lojista_id'] ?? '').toString(),
                                  ),
                                  builder: (context, lojaSnap) {
                                    return Text(
                                      'Loja: ${lojaSnap.data ?? 'Carregando...'}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: Colors.grey.shade700,
                                        fontSize: 12,
                                      ),
                                    );
                                  },
                                ),
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    Expanded(
                                      child: OutlinedButton(
                                        onPressed: () =>
                                            _recusarSugestao(doc.id),
                                        child: const Text('Recusar'),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: FilledButton(
                                        onPressed: () =>
                                            _aprovarSugestao(doc.id, d),
                                        style: FilledButton.styleFrom(
                                          backgroundColor: _laranja,
                                          foregroundColor: Colors.white,
                                        ),
                                        child: const Text('Aprovar'),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ChipInfo extends StatelessWidget {
  final String texto;
  final Color cor;
  final IconData icone;

  const _ChipInfo({
    required this.texto,
    required this.cor,
    required this.icone,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: cor.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icone, size: 14, color: cor),
          const SizedBox(width: 4),
          Text(
            texto,
            style: TextStyle(
              color: cor,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
