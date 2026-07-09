import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:depertin_web/theme/painel_admin_theme.dart';
import 'package:depertin_web/utils/lojista_painel_context.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

double _precoProduto(dynamic v) {
  if (v == null) return 0;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString()) ?? 0;
}

enum _CardapioView { grade, lista }

/// Catálogo da loja — layout em grelha, cartões e resumo visual.
class LojistaMeuCardapioScreen extends StatefulWidget {
  const LojistaMeuCardapioScreen({super.key});

  @override
  State<LojistaMeuCardapioScreen> createState() =>
      _LojistaMeuCardapioScreenState();
}

class _LojistaMeuCardapioScreenState extends State<LojistaMeuCardapioScreen> {
  static const _roxo = PainelAdminTheme.roxo;
  static const _laranja = PainelAdminTheme.laranja;

  final _buscaC = TextEditingController();

  /// todos | ativos | inativos
  String _filtroVisibilidade = 'todos';

  _CardapioView _modoVisualizacao = _CardapioView.lista;

  String _filtroCategoria = 'todas';
  String _filtroTipoVenda = 'todos';
  String _ordenacao = 'nome_az';

  @override
  void dispose() {
    _buscaC.dispose();
    super.dispose();
  }

  static String _primeiraImagem(dynamic imagens) {
    if (imagens is List && imagens.isNotEmpty) {
      return imagens.first.toString();
    }
    return '';
  }

  bool _passaVisibilidade(Map<String, dynamic> p, String filtro) {
    final ativo = p['ativo'] != false;
    switch (filtro) {
      case 'ativos':
        return ativo;
      case 'inativos':
        return !ativo;
      default:
        return true;
    }
  }

  Future<void> _abrirFormulario(
    BuildContext context, {
    required String uidLoja,
    DocumentSnapshot<Map<String, dynamic>>? existente,
  }) async {
    final isEdit = existente != null;
    final d = existente?.data() ?? {};
    final nomeC = TextEditingController(text: d['nome']?.toString() ?? '');
    final precoC = TextEditingController(
      text: d['preco'] != null ? d['preco'].toString() : '',
    );
    final descC = TextEditingController(text: d['descricao']?.toString() ?? '');
    final catC = TextEditingController(
      text: (d['categoria_nome'] ?? d['categoria'] ?? '').toString(),
    );
    final estC = TextEditingController(
      text: d['estoque_qtd'] != null ? '${d['estoque_qtd']}' : '0',
    );
    final imgC = TextEditingController(text: _primeiraImagem(d['imagens']));
    final ncmC =
        TextEditingController(text: d['ncm']?.toString() ?? '');
    final cstC = TextEditingController(
      text: (d['cst_icms'] ?? d['csosn'] ?? '400').toString(),
    );
    var ativo = d['ativo'] != false;
    var salvando = false;
    var tipo = (d['tipo_venda'] ?? 'pronta_entrega').toString();
    if (tipo != 'pronta_entrega' && tipo != 'encomenda') {
      tipo = 'pronta_entrega';
    }
    var requerVeiculoGrande =
        d['requer_veiculo_grande'] == true || d['carga_maior'] == true;
    var isOfertaEspecial = d['is_oferta_especial'] == true;
    String? categoriaSelecionada = catC.text.trim().isEmpty
        ? null
        : catC.text.trim();

    Future<void> sugerirCategoria() async {
      final ctrl = TextEditingController();
      final nome = await showDialog<String>(
        context: context,
        builder: (dialogCtx) => AlertDialog(
          title: const Text('Sugerir categoria'),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              hintText: 'Ex.: Moda fitness, autopeças...',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => Navigator.pop(dialogCtx, ctrl.text.trim()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogCtx, ctrl.text.trim()),
              child: const Text('Enviar'),
            ),
          ],
        ),
      );
      ctrl.dispose();
      if (nome == null || nome.trim().length < 2) return;
      await FirebaseFirestore.instance.collection('sugestoes_categorias').add({
        'nome': nome.trim(),
        'lojista_id': uidLoja,
        'status': 'pendente',
        'origem': 'painel_lojista_produto',
        'data': FieldValue.serverTimestamp(),
        'criada_em': FieldValue.serverTimestamp(),
      });
      if (context.mounted) {
        await showDialog<void>(
          context: context,
          builder: (dialogCtx) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            title: const Row(
              children: [
                Icon(Icons.check_circle_rounded, color: Color(0xFF15803D)),
                SizedBox(width: 10),
                Expanded(child: Text('Sugestão enviada')),
              ],
            ),
            content: Text(
              'A categoria "${nome.trim()}" foi enviada para análise. '
              'Assim que for aprovada, ela ficará disponível no cadastro de produtos.',
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(dialogCtx),
                child: const Text('Entendi'),
              ),
            ],
          ),
        );
      }
    }

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        _roxo.withValues(alpha: 0.12),
                        _laranja.withValues(alpha: 0.06),
                      ],
                    ),
                    border: Border(
                      bottom: BorderSide(color: Colors.grey.shade200),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: _roxo.withValues(alpha: 0.12),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Icon(
                          isEdit ? Icons.edit_note_rounded : Icons.add_rounded,
                          color: _roxo,
                          size: 26,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isEdit ? 'Editar produto' : 'Novo produto',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                color: const Color(0xFF1E1B4B),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Os clientes veem estes dados na vitrine do app.',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey.shade700,
                                height: 1.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(22, 18, 22, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _secForm('Informações'),
                        const SizedBox(height: 10),
                        TextField(
                          controller: nomeC,
                          decoration: _dec('Nome do produto *'),
                        ),
                        const SizedBox(height: 12),
                        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                          stream: FirebaseFirestore.instance
                              .collection('categorias')
                              .where('ativo', isEqualTo: true)
                              .snapshots(),
                          builder: (context, catSnap) {
                            if (!catSnap.hasData) {
                              return const LinearProgressIndicator();
                            }
                            final cats = catSnap.data!.docs.toList()
                              ..sort((a, b) {
                                final ma = a.data();
                                final mb = b.data();
                                final oa =
                                    (ma['ordem'] as num?)?.toInt() ?? 999;
                                final ob =
                                    (mb['ordem'] as num?)?.toInt() ?? 999;
                                if (oa != ob) return oa.compareTo(ob);
                                return (ma['nome'] ?? '').toString().compareTo(
                                  (mb['nome'] ?? '').toString(),
                                );
                              });
                            final valores = cats
                                .map(
                                  (e) => (e.data()['nome'] ?? '')
                                      .toString()
                                      .trim(),
                                )
                                .where((e) => e.isNotEmpty)
                                .toSet()
                                .toList();
                            final valorAtual =
                                valores.contains(categoriaSelecionada)
                                ? categoriaSelecionada
                                : null;
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                DropdownButtonFormField<String>(
                                  initialValue: valorAtual,
                                  isExpanded: true,
                                  decoration: _dec('Categoria oficial'),
                                  items: valores
                                      .map(
                                        (nome) => DropdownMenuItem(
                                          value: nome,
                                          child: Text(nome),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: (v) => setS(() {
                                    categoriaSelecionada = v;
                                    catC.text = v ?? '';
                                  }),
                                ),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: TextButton.icon(
                                    onPressed: sugerirCategoria,
                                    icon: const Icon(
                                      Icons.lightbulb_outline,
                                      size: 18,
                                    ),
                                    label: const Text('Sugerir categoria'),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: descC,
                          maxLines: 2,
                          decoration: _dec('Descrição (opcional)'),
                        ),
                        const SizedBox(height: 20),
                        _secForm('Preço e estoque'),
                        const SizedBox(height: 10),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: TextField(
                                controller: precoC,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                inputFormatters: [
                                  FilteringTextInputFormatter.allow(
                                    RegExp(r'[\d.,]'),
                                  ),
                                ],
                                decoration: _dec('Preço (R\$) *'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextField(
                                controller: estC,
                                keyboardType: TextInputType.number,
                                decoration: _dec('Estoque'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue: tipo,
                          decoration: _dec('Tipo de venda'),
                          items: const [
                            DropdownMenuItem(
                              value: 'pronta_entrega',
                              child: Text('Pronta entrega'),
                            ),
                            DropdownMenuItem(
                              value: 'encomenda',
                              child: Text('Encomenda'),
                            ),
                          ],
                          onChanged: (v) =>
                              setS(() => tipo = v ?? 'pronta_entrega'),
                        ),
                        const SizedBox(height: 20),
                        _secForm('Imagem e visibilidade'),
                        const SizedBox(height: 10),
                        TextField(
                          controller: imgC,
                          decoration: _dec('URL da foto').copyWith(
                            helperText: 'Link público (ex.: Firebase Storage)',
                          ),
                        ),
                        const SizedBox(height: 8),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Mostrar na vitrine'),
                          subtitle: Text(
                            'Desligado = oculto para clientes',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                          ),
                          value: ativo,
                          activeThumbColor: _laranja,
                          onChanged: (v) => setS(() => ativo = v),
                        ),
                        const SizedBox(height: 8),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Oferta especial'),
                          subtitle: Text(
                            'Ativo = aparece na seção "Ofertas especiais" da vitrine',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                          ),
                          value: isOfertaEspecial,
                          activeThumbColor: _laranja,
                          onChanged: (v) => setS(() => isOfertaEspecial = v),
                        ),
                        const SizedBox(height: 20),
                        _secForm('Logística de entrega'),
                        const SizedBox(height: 4),
                        Container(
                          margin: const EdgeInsets.only(top: 8),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF0F7FF),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFBFDBFE)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(
                                    Icons.info_outline,
                                    size: 18,
                                    color: Color(0xFF1D4ED8),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'A logística mudou: configure na loja',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        color: const Color(0xFF1E3A8A),
                                        fontSize: 13.5,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Agora o tipo de veículo usado para entregar é configurado '
                                'uma única vez no perfil da sua loja (Configurações da loja → '
                                'Tipos de entrega aceitos), e vale para TODOS os produtos. '
                                'Essa configuração define a tabela de frete e quais entregadores '
                                'serão convocados.',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: const Color(0xFF1E3A8A),
                                  height: 1.4,
                                ),
                              ),
                              if (requerVeiculoGrande) ...[
                                const SizedBox(height: 10),
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: _laranja.withValues(alpha: 0.08),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: _laranja.withValues(alpha: 0.35),
                                    ),
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Icon(
                                        Icons.local_shipping_rounded,
                                        size: 18,
                                        color: _laranja,
                                      ),
                                      const SizedBox(width: 8),
                                      const Expanded(
                                        child: Text(
                                          'Este produto foi marcado como "volumoso/carga maior" '
                                          'no modelo antigo. Esse dado ainda é lido como '
                                          'fallback de segurança enquanto você não define os '
                                          'Tipos de entrega da loja. Recomendamos configurar a '
                                          'loja inteira em Configurações.',
                                          style: TextStyle(
                                            fontSize: 11.5,
                                            height: 1.35,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        _secForm('Informações fiscais (NF-e)'),
                        const SizedBox(height: 10),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: TextField(
                                controller: ncmC,
                                decoration: _dec('NCM (8 dígitos)').copyWith(
                                  helperText: 'Ex.: 64041900',
                                ),
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                  LengthLimitingTextInputFormatter(8),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextField(
                                controller: cstC,
                                decoration:
                                    _dec('CST ICMS / CSOSN').copyWith(
                                  helperText: 'Ex.: 400 (SN) ou 000',
                                ),
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                  LengthLimitingTextInputFormatter(4),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Row(
                    children: [
                      TextButton(
                        onPressed: salvando ? null : () => Navigator.pop(ctx),
                        child: const Text('Cancelar'),
                      ),
                      const Spacer(),
                      FilledButton.icon(
                        onPressed: salvando
                            ? null
                            : () async {
                                if (nomeC.text.trim().isEmpty ||
                                    categoriaSelecionada == null ||
                                    categoriaSelecionada!.isEmpty) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Informe nome e categoria oficial.',
                                      ),
                                      backgroundColor: Colors.orange,
                                    ),
                                  );
                                  return;
                                }
                                final preco =
                                    double.tryParse(
                                      precoC.text.replaceAll(',', '.'),
                                    ) ??
                                    0;
                                final est = int.tryParse(estC.text) ?? 0;
                                final imgs = <String>[];
                                if (imgC.text.trim().isNotEmpty) {
                                  imgs.add(imgC.text.trim());
                                }
                                setS(() => salvando = true);
                                try {
                                  final payload = <String, dynamic>{
                                    'nome': nomeC.text.trim(),
                                    'preco': preco,
                                    'descricao': descC.text.trim(),
                                    'categoria': categoriaSelecionada!.trim(),
                                    'categoria_nome': categoriaSelecionada!
                                        .trim(),
                                    'estoque_qtd': est,
                                    'tipo_venda': tipo,
                                    'ativo': ativo,
                                    'is_oferta_especial': isOfertaEspecial,
                                    'imagens': imgs,
                                    'lojista_id': uidLoja,
                                    'loja_id': uidLoja,
                                    'requer_veiculo_grande':
                                        requerVeiculoGrande,
                                    'ncm': ncmC.text.trim(),
                                    'cst_icms': cstC.text.trim().isNotEmpty
                                        ? cstC.text.trim()
                                        : '400',
                                    'updated_at': FieldValue.serverTimestamp(),
                                  };
                                  if (!isEdit) {
                                    payload['created_at'] =
                                        FieldValue.serverTimestamp();
                                    await FirebaseFirestore.instance
                                        .collection('produtos')
                                        .add(payload);
                                  } else {
                                    await existente.reference.update(payload);
                                  }
                                  if (ctx.mounted) Navigator.pop(ctx);
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Alterações salvas.'),
                                        backgroundColor: Color(0xFF15803D),
                                      ),
                                    );
                                  }
                                } catch (e) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('Erro: $e'),
                                        backgroundColor: Colors.red,
                                      ),
                                    );
                                  }
                                } finally {
                                  setS(() => salvando = false);
                                }
                              },
                        style: FilledButton.styleFrom(
                          backgroundColor: _laranja,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 22,
                            vertical: 14,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        icon: salvando
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.check_rounded, size: 20),
                        label: Text(salvando ? 'Salvando…' : 'Salvar'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static Widget _secForm(String t) => Text(
    t,
    style: GoogleFonts.plusJakartaSans(
      fontSize: 13,
      fontWeight: FontWeight.w700,
      color: _roxo,
      letterSpacing: 0.2,
    ),
  );

  static InputDecoration _dec(String label) => InputDecoration(
    labelText: label,
    filled: true,
    fillColor: const Color(0xFFF8F7FC),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: Colors.grey.shade300),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: _roxo, width: 1.5),
    ),
  );

  InputDecoration _inputDecorationFiltro(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: Colors.grey,
      ),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      filled: true,
      fillColor: const Color(0xFFF8F9FC),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: Colors.grey.shade200),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: Colors.grey.shade200),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: _roxo, width: 1.5),
      ),
    );
  }

  Future<void> _alternarVisibilidade(
    BuildContext context,
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    final data = doc.data() ?? {};
    final atual = data['ativo'] != false;
    try {
      await doc.reference.update({'ativo': !atual});
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              atual ? 'Produto ocultado da vitrine.' : 'Produto ativado na vitrine!',
            ),
            backgroundColor: const Color(0xFF15803D),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _excluir(
    BuildContext context,
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Excluir produto?'),
        content: const Text('O item sai da vitrine e é removido do catálogo.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await doc.reference.delete();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Produto removido.'),
            backgroundColor: Color(0xFF15803D),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final moeda = NumberFormat.currency(locale: 'pt_BR', symbol: r'R$');

    return LojistaUidLojaBuilder(
      builder: (context, authUid, uidLoja, dados) {
        if (dados != null && !painelMostrarMeusProdutos(dados)) {
          return painelLojistaSemPermissaoScaffold(
            mensagem:
                'Sua conta não tem permissão para gerenciar produtos no painel.',
          );
        }

        return Scaffold(
          backgroundColor: const Color(0xFFF8F9FC),
          body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('produtos')
                .where('lojista_id', isEqualTo: uidLoja)
                .snapshots(),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting &&
                  !snap.hasData) {
                return const Center(
                  child: CircularProgressIndicator(
                    color: PainelAdminTheme.roxo,
                  ),
                );
              }
              if (snap.hasError) {
                return Center(child: Text('Erro: ${snap.error}'));
              }

              final todos = snap.data?.docs ?? [];
              int nAtivos = 0;
              int nInativos = 0;

              final categoriasDisponiveis = <String>{};
              for (final doc in todos) {
                final p = doc.data();
                if (p['ativo'] != false) {
                  nAtivos++;
                } else {
                  nInativos++;
                }
                final cat = (p['categoria_nome'] ?? p['categoria'] ?? '')
                    .toString()
                    .trim();
                if (cat.isNotEmpty) {
                  categoriasDisponiveis.add(cat);
                }
              }
              final listaCategorias = categoriasDisponiveis.toList()..sort();

              var docs = todos.toList();
              final q = _buscaC.text.trim().toLowerCase();
              if (q.isNotEmpty) {
                docs = docs.where((e) {
                  final m = e.data();
                  final nome = (m['nome'] ?? '').toString().toLowerCase();
                  final cat = (m['categoria_nome'] ?? m['categoria'] ?? '')
                      .toString()
                      .toLowerCase();
                  final desc = (m['descricao'] ?? '').toString().toLowerCase();
                  return nome.contains(q) ||
                      cat.contains(q) ||
                      desc.contains(q);
                }).toList();
              }

              docs = docs.where((e) {
                return _passaVisibilidade(e.data(), _filtroVisibilidade);
              }).toList();

              if (_filtroCategoria != 'todas') {
                docs = docs.where((e) {
                  final m = e.data();
                  final cat = (m['categoria_nome'] ?? m['categoria'] ?? '')
                      .toString()
                      .trim();
                  return cat == _filtroCategoria;
                }).toList();
              }

              if (_filtroTipoVenda != 'todos') {
                docs = docs.where((e) {
                  final m = e.data();
                  final tipo = (m['tipo_venda'] ?? 'pronta_entrega').toString();
                  return tipo == _filtroTipoVenda;
                }).toList();
              }

              docs.sort((a, b) {
                final ma = a.data();
                final mb = b.data();

                switch (_ordenacao) {
                  case 'nome_za':
                    final na = (ma['nome'] ?? '').toString().toLowerCase();
                    final nb = (mb['nome'] ?? '').toString().toLowerCase();
                    return nb.compareTo(na);
                  case 'preco_menor':
                    final pa = _precoProduto(ma['preco']);
                    final pb = _precoProduto(mb['preco']);
                    return pa.compareTo(pb);
                  case 'preco_maior':
                    final pa = _precoProduto(ma['preco']);
                    final pb = _precoProduto(mb['preco']);
                    return pb.compareTo(pa);
                  case 'estoque_menor':
                    final ea = ma['estoque_qtd'] is num
                        ? (ma['estoque_qtd'] as num).toInt()
                        : 0;
                    final eb = mb['estoque_qtd'] is num
                        ? (mb['estoque_qtd'] as num).toInt()
                        : 0;
                    return ea.compareTo(eb);
                  case 'estoque_desc':
                    final ea = ma['estoque_qtd'] is num
                        ? (ma['estoque_qtd'] as num).toInt()
                        : 0;
                    final eb = mb['estoque_qtd'] is num
                        ? (mb['estoque_qtd'] as num).toInt()
                        : 0;
                    return eb.compareTo(ea);
                  case 'nome_az':
                  default:
                    final na = (ma['nome'] ?? '').toString().toLowerCase();
                    final nb = (mb['nome'] ?? '').toString().toLowerCase();
                    return na.compareTo(nb);
                }
              });

              return CustomScrollView(
                slivers: [
                  // Cabeçalho modernizado SaaS
                  SliverToBoxAdapter(
                    child: Container(
                      width: double.infinity,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        border: Border(
                          bottom: BorderSide(color: Color(0xFFE2E8F0)),
                        ),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 24,
                      ),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 1200),
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final narrow = constraints.maxWidth < 640;
                              final headerContent = Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: _roxo.withValues(alpha: 0.08),
                                          borderRadius:
                                              BorderRadius.circular(20),
                                        ),
                                        child: Text(
                                          'CATÁLOGO & VITRINE',
                                          style: GoogleFonts.plusJakartaSans(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w800,
                                            color: _roxo,
                                            letterSpacing: 0.5,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Meus produtos',
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 26,
                                      fontWeight: FontWeight.w900,
                                      color: const Color(0xFF1E1B4B),
                                      letterSpacing: -0.5,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'Gerencie os produtos da sua loja, ajuste preços, controle o estoque e configure o que é exibido para entrega rápida ou sob encomenda.',
                                    style: TextStyle(
                                      color: Colors.grey.shade500,
                                      fontSize: 13,
                                      height: 1.45,
                                    ),
                                  ),
                                ],
                              );

                              final btnNovo = FilledButton.icon(
                                onPressed: () => _abrirFormulario(
                                  context,
                                  uidLoja: uidLoja,
                                ),
                                style: FilledButton.styleFrom(
                                  backgroundColor: _laranja,
                                  foregroundColor: Colors.white,
                                  elevation: 2,
                                  shadowColor: _laranja.withValues(alpha: 0.3),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 20,
                                    vertical: 16,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                icon: const Icon(
                                  Icons.add_rounded,
                                  size: 20,
                                ),
                                label: Text(
                                  'Novo produto',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 13.5,
                                    letterSpacing: 0.1,
                                  ),
                                ),
                              );

                              if (narrow) {
                                return Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    headerContent,
                                    const SizedBox(height: 16),
                                    btnNovo,
                                  ],
                                );
                              }

                              return Row(
                                children: [
                                  Expanded(child: headerContent),
                                  const SizedBox(width: 24),
                                  btnNovo,
                                ],
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ),

                  // Cards de métricas (KPIs) de alta fidelidade
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 1200),
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              if (constraints.maxWidth < 720) {
                                return Wrap(
                                  spacing: 12,
                                  runSpacing: 12,
                                  children: [
                                    _kpiCardWrap(
                                      icon: Icons.inventory_2_outlined,
                                      label: 'Total de produtos',
                                      valor: '${todos.length}',
                                      cor: _roxo,
                                      corFundo: _roxo.withValues(alpha: 0.08),
                                      subtitulo: 'Cadastrados na loja',
                                    ),
                                    _kpiCardWrap(
                                      icon: Icons.visibility_outlined,
                                      label: 'Na vitrine',
                                      valor: '$nAtivos',
                                      cor: const Color(0xFF15803D),
                                      corFundo: const Color(0xFF15803D)
                                          .withValues(alpha: 0.08),
                                      subtitulo: 'Disponíveis no app',
                                    ),
                                    _kpiCardWrap(
                                      icon: Icons.visibility_off_outlined,
                                      label: 'Ocultos',
                                      valor: '$nInativos',
                                      cor: Colors.grey.shade700,
                                      corFundo: Colors.grey.shade100,
                                      subtitulo: 'Salvos como rascunho',
                                    ),
                                  ],
                                );
                              }
                              return Row(
                                children: [
                                  _kpiCard(
                                    icon: Icons.inventory_2_outlined,
                                    label: 'Total de produtos',
                                    valor: '${todos.length}',
                                    cor: _roxo,
                                    corFundo: _roxo.withValues(alpha: 0.08),
                                    subtitulo: 'Cadastrados na loja',
                                  ),
                                  const SizedBox(width: 12),
                                  _kpiCard(
                                    icon: Icons.visibility_outlined,
                                    label: 'Na vitrine',
                                    valor: '$nAtivos',
                                    cor: const Color(0xFF15803D),
                                    corFundo: const Color(0xFF15803D)
                                        .withValues(alpha: 0.08),
                                    subtitulo: 'Disponíveis no app',
                                  ),
                                  const SizedBox(width: 12),
                                  _kpiCard(
                                    icon: Icons.visibility_off_outlined,
                                    label: 'Ocultos',
                                    valor: '$nInativos',
                                    cor: Colors.grey.shade700,
                                    corFundo: Colors.grey.shade100,
                                    subtitulo: 'Salvos como rascunho',
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ),

                  // Barra de busca avançada estilo Shopify/Mercado Libre
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 1200),
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFFE2E8F0)),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.01),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                final isNarrow = constraints.maxWidth < 900;

                                final campoBusca = TextField(
                                  controller: _buscaC,
                                  onChanged: (_) => setState(() {}),
                                  style: const TextStyle(fontSize: 13),
                                  decoration: InputDecoration(
                                    isDense: true,
                                    hintText: 'Buscar nome ou descrição...',
                                    hintStyle: TextStyle(
                                      fontSize: 13,
                                      color: Colors.grey.shade400,
                                    ),
                                    prefixIcon: Icon(
                                      Icons.search_rounded,
                                      size: 18,
                                      color: Colors.grey.shade500,
                                    ),
                                    filled: true,
                                    fillColor: const Color(0xFFF8F9FC),
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 10,
                                    ),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      borderSide: BorderSide(
                                        color: Colors.grey.shade200,
                                      ),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      borderSide: BorderSide(
                                        color: Colors.grey.shade200,
                                      ),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      borderSide: const BorderSide(
                                        color: _roxo,
                                        width: 1.5,
                                      ),
                                    ),
                                  ),
                                );

                                final dropCategoria =
                                    DropdownButtonFormField<String>(
                                      value: _filtroCategoria,
                                      isDense: true,
                                      decoration:
                                          _inputDecorationFiltro('Categoria'),
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 12,
                                        color: Colors.black87,
                                        fontWeight: FontWeight.w600,
                                      ),
                                      items: [
                                        const DropdownMenuItem(
                                          value: 'todas',
                                          child: Text('Todas as categorias'),
                                        ),
                                        ...listaCategorias.map(
                                          (c) => DropdownMenuItem(
                                            value: c,
                                            child: Text(c),
                                          ),
                                        ),
                                      ],
                                      onChanged: (v) {
                                        if (v != null) {
                                          setState(() => _filtroCategoria = v);
                                        }
                                      },
                                    );

                                final dropTipoVenda =
                                    DropdownButtonFormField<String>(
                                      value: _filtroTipoVenda,
                                      isDense: true,
                                      decoration: _inputDecorationFiltro('Tipo'),
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 12,
                                        color: Colors.black87,
                                        fontWeight: FontWeight.w600,
                                      ),
                                      items: const [
                                        DropdownMenuItem(
                                          value: 'todos',
                                          child: Text('Todos os tipos'),
                                        ),
                                        DropdownMenuItem(
                                          value: 'pronta_entrega',
                                          child: Text('Pronta entrega'),
                                        ),
                                        DropdownMenuItem(
                                          value: 'encomenda',
                                          child: Text('Encomenda'),
                                        ),
                                      ],
                                      onChanged: (v) {
                                        if (v != null) {
                                          setState(() => _filtroTipoVenda = v);
                                        }
                                      },
                                    );

                                final dropOrdenacao =
                                    DropdownButtonFormField<String>(
                                      value: _ordenacao,
                                      isDense: true,
                                      decoration:
                                          _inputDecorationFiltro('Ordenar por'),
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 12,
                                        color: Colors.black87,
                                        fontWeight: FontWeight.w600,
                                      ),
                                      items: const [
                                        DropdownMenuItem(
                                          value: 'nome_az',
                                          child: Text('Nome (A-Z)'),
                                        ),
                                        DropdownMenuItem(
                                          value: 'nome_za',
                                          child: Text('Nome (Z-A)'),
                                        ),
                                        DropdownMenuItem(
                                          value: 'preco_menor',
                                          child: Text('Menor Preço'),
                                        ),
                                        DropdownMenuItem(
                                          value: 'preco_maior',
                                          child: Text('Maior Preço'),
                                        ),
                                        DropdownMenuItem(
                                          value: 'estoque_menor',
                                          child: Text('Estoque (Crescente)'),
                                        ),
                                        DropdownMenuItem(
                                          value: 'estoque_maior',
                                          child: Text('Estoque (Decrescente)'),
                                        ),
                                      ],
                                      onChanged: (v) {
                                        if (v != null) {
                                          setState(() => _ordenacao = v);
                                        }
                                      },
                                    );

                                if (isNarrow) {
                                  return Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      campoBusca,
                                      const SizedBox(height: 10),
                                      _segmentoListagem(),
                                      const SizedBox(height: 10),
                                      Row(
                                        children: [
                                          Expanded(child: dropCategoria),
                                          const SizedBox(width: 8),
                                          Expanded(child: dropTipoVenda),
                                        ],
                                      ),
                                      const SizedBox(height: 10),
                                      Row(
                                        children: [
                                          Expanded(child: dropOrdenacao),
                                          const SizedBox(width: 10),
                                          _alternarVisualizacao(),
                                        ],
                                      ),
                                    ],
                                  );
                                }

                                return Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(flex: 3, child: campoBusca),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          flex: 2,
                                          child: _segmentoListagem(),
                                        ),
                                        const SizedBox(width: 12),
                                        _alternarVisualizacao(),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    Row(
                                      children: [
                                        Expanded(child: dropCategoria),
                                        const SizedBox(width: 10),
                                        Expanded(child: dropTipoVenda),
                                        const SizedBox(width: 10),
                                        Expanded(child: dropOrdenacao),
                                      ],
                                    ),
                                  ],
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                  // Listagem de produtos (Cards premium)
                  if (docs.isEmpty)
                    SliverToBoxAdapter(
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.all(48),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(22),
                                decoration: BoxDecoration(
                                  color: _roxo.withValues(alpha: 0.08),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.restaurant_menu_rounded,
                                  size: 48,
                                  color: _roxo.withValues(alpha: 0.65),
                                ),
                              ),
                              const SizedBox(height: 20),
                              Text(
                                todos.isEmpty
                                    ? 'Comece adicionando o primeiro item'
                                    : 'Nenhum produto neste filtro',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: const Color(0xFF1E1B4B),
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                todos.isEmpty
                                    ? 'Clientes só veem produtos que você cadastrar aqui.'
                                    : 'Ajuste a busca ou os filtros acima.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.grey.shade500,
                                  fontSize: 13.5,
                                ),
                              ),
                              if (todos.isEmpty) ...[
                                const SizedBox(height: 24),
                                FilledButton.icon(
                                  onPressed: () => _abrirFormulario(
                                    context,
                                    uidLoja: uidLoja,
                                  ),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: _laranja,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 24,
                                      vertical: 14,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  icon: const Icon(Icons.add_rounded),
                                  label: const Text(
                                    'Criar primeiro produto',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 100),
                      sliver: SliverToBoxAdapter(
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 1200),
                            child: _modoVisualizacao == _CardapioView.lista
                                ? ListView.builder(
                                    shrinkWrap: true,
                                    physics: const NeverScrollableScrollPhysics(),
                                    itemCount: docs.length,
                                    itemBuilder: (context, i) {
                                      final doc = docs[i];
                                      return _LinhaProduto(
                                        moeda: moeda,
                                        doc: doc,
                                        onEdit: () => _abrirFormulario(
                                          context,
                                          uidLoja: uidLoja,
                                          existente: doc,
                                        ),
                                        onDelete: () => _excluir(context, doc),
                                        onAlternarAtivo: () =>
                                            _alternarVisibilidade(context, doc),
                                      );
                                    },
                                  )
                                : LayoutBuilder(
                                    builder: (context, c) {
                                      final cols = c.maxWidth >= 1100
                                          ? 3
                                          : c.maxWidth >= 720
                                              ? 2
                                              : 1;
                                      final gap = c.maxWidth >= 720 ? 16.0 : 12.0;
                                      return GridView.builder(
                                        shrinkWrap: true,
                                        physics: const NeverScrollableScrollPhysics(),
                                        gridDelegate:
                                            SliverGridDelegateWithFixedCrossAxisCount(
                                              crossAxisCount: cols,
                                              mainAxisSpacing: gap,
                                              crossAxisSpacing: gap,
                                              childAspectRatio: cols == 1
                                                  ? 1.05
                                                  : 0.78,
                                            ),
                                        itemCount: docs.length,
                                        itemBuilder: (context, i) {
                                          final doc = docs[i];
                                          return _CartaoProduto(
                                            moeda: moeda,
                                            doc: doc,
                                            onEdit: () => _abrirFormulario(
                                              context,
                                              uidLoja: uidLoja,
                                              existente: doc,
                                            ),
                                            onDelete: () => _excluir(context, doc),
                                            onAlternarAtivo: () =>
                                                _alternarVisibilidade(context, doc),
                                          );
                                        },
                                      );
                                    },
                                  ),
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  /// Filtro da listagem (Todos / Na vitrine / Ocultos).
  Widget _segmentoListagem() {
    final btn = SegmentedButton<String>(
      segments: const [
        ButtonSegment<String>(value: 'todos', label: Text('Todos')),
        ButtonSegment<String>(value: 'ativos', label: Text('Na vitrine')),
        ButtonSegment<String>(value: 'inativos', label: Text('Ocultos')),
      ],
      selected: {_filtroVisibilidade},
      showSelectedIcon: false,
      emptySelectionAllowed: false,
      onSelectionChanged: (Set<String> s) {
        if (s.isEmpty) return;
        setState(() => _filtroVisibilidade = s.first);
      },
      style: SegmentedButton.styleFrom(
        backgroundColor: Colors.grey.shade100,
        foregroundColor: Colors.grey.shade800,
        selectedForegroundColor: _roxo,
        selectedBackgroundColor: _laranja.withValues(alpha: 0.22),
        side: BorderSide(color: Colors.grey.shade300),
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        return Align(
          alignment: Alignment.centerLeft,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: constraints.maxWidth),
              child: btn,
            ),
          ),
        );
      },
    );
  }

  /// Grade (ícones em grelha) ou lista (linhas compactas).
  Widget _alternarVisualizacao() {
    return Tooltip(
      message: 'Modo de visualização',
      child: ToggleButtons(
        borderRadius: BorderRadius.circular(10),
        selectedBorderColor: _laranja.withValues(alpha: 0.55),
        fillColor: _laranja.withValues(alpha: 0.18),
        selectedColor: _roxo,
        color: Colors.grey.shade600,
        borderColor: Colors.grey.shade300,
        constraints: const BoxConstraints(minHeight: 36, minWidth: 42),
        isSelected: [
          _modoVisualizacao == _CardapioView.grade,
          _modoVisualizacao == _CardapioView.lista,
        ],
        onPressed: (i) => setState(() {
          _modoVisualizacao = i == 0
              ? _CardapioView.grade
              : _CardapioView.lista;
        }),
        children: const [
          Icon(Icons.grid_view_rounded, size: 20),
          Icon(Icons.view_list_rounded, size: 20),
        ],
      ),
    );
  }

  Widget _kpiCard({
    required IconData icon,
    required String label,
    required String valor,
    required Color cor,
    required Color corFundo,
    required String subtitulo,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFF1F5F9)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: corFundo,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: cor, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: Colors.grey.shade500,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.2,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    valor,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF1E1B4B),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitulo,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade400,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// KPI para `Wrap` (telas estreitas)
  Widget _kpiCardWrap({
    required IconData icon,
    required String label,
    required String valor,
    required Color cor,
    required Color corFundo,
    required String subtitulo,
  }) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 160, maxWidth: 220),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFF1F5F9)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: corFundo,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: cor, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade500,
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 1),
                  Text(
                    valor,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF1E1B4B),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Uma linha compacta para o modo lista.
class _LinhaProduto extends StatelessWidget {
  const _LinhaProduto({
    required this.moeda,
    required this.doc,
    required this.onEdit,
    required this.onDelete,
    required this.onAlternarAtivo,
  });

  final NumberFormat moeda;
  final DocumentSnapshot<Map<String, dynamic>> doc;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onAlternarAtivo;

  static String _img(dynamic imagens) {
    if (imagens is List && imagens.isNotEmpty) {
      return imagens.first.toString();
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final p = doc.data() ?? {};
    final url = _img(p['imagens']);
    final nome = p['nome']?.toString() ?? 'Sem nome';
    final cat = (p['categoria_nome'] ?? p['categoria'] ?? '').toString().trim();
    final preco = _precoProduto(p['preco']);
    final est = p['estoque_qtd'];
    final estNum = est is num ? est.toInt() : null;
    final ativo = p['ativo'] != false;
    final tipo = (p['tipo_venda'] ?? 'pronta_entrega').toString();
    final tipoLabel = tipo == 'encomenda' ? 'Encomenda' : 'Pronta entrega';
    final requerVeiculoGrande =
        p['requer_veiculo_grande'] == true || p['carga_maior'] == true;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFFE2E8F0),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onEdit,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Imagem do produto com sombra interna e bordas premium
                  Container(
                    width: 76,
                    height: 76,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFF1F5F9)),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(9),
                      child: url.isNotEmpty
                          ? Image.network(
                              url,
                              fit: BoxFit.cover,
                              webHtmlElementStrategy: kIsWeb
                                  ? WebHtmlElementStrategy.prefer
                                  : WebHtmlElementStrategy.never,
                              errorBuilder: (_, _, _) => _thumbVazio(),
                            )
                          : _thumbVazio(),
                    ),
                  ),
                  const SizedBox(width: 16),
                  // Conteúdo central (Detalhes do produto)
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Título do Produto
                        Text(
                          nome,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF1E1B4B),
                            height: 1.25,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 6),
                        // Row de badges estilizados
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            // Badge de Status de Visibilidade (Vitrine/Oculto)
                            _badge(
                              texto: ativo ? 'Vitrine' : 'Oculto',
                              corTexto: ativo
                                  ? const Color(0xFF15803D)
                                  : Colors.grey.shade700,
                              corFundo: ativo
                                  ? const Color(0xFF15803D)
                                      .withValues(alpha: 0.1)
                                  : Colors.grey.shade100,
                            ),
                            // Badge de Categoria
                            if (cat.isNotEmpty)
                              _badge(
                                texto: cat,
                                corTexto: PainelAdminTheme.roxo,
                                corFundo: PainelAdminTheme.roxo
                                    .withValues(alpha: 0.08),
                              ),
                            // Badge do Tipo de Venda (Encomenda/Pronta Entrega)
                            _badge(
                              texto: tipoLabel,
                              corTexto: tipo == 'encomenda'
                                  ? const Color(0xFF0369A1)
                                  : const Color(0xFF0D9488),
                              corFundo: tipo == 'encomenda'
                                  ? const Color(0xFF0369A1)
                                      .withValues(alpha: 0.08)
                                  : const Color(0xFF0D9488)
                                      .withValues(alpha: 0.08),
                            ),
                            // Badge Requer Veículo Grande
                            if (requerVeiculoGrande)
                              _badge(
                                texto: 'Carga Maior',
                                icone: Icons.local_shipping_outlined,
                                corTexto: PainelAdminTheme.laranja,
                                corFundo: PainelAdminTheme.laranja
                                    .withValues(alpha: 0.1),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  // Área Financeira & Estoque
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Preço
                      Text(
                        moeda.format(preco),
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 16.5,
                          fontWeight: FontWeight.w800,
                          color: PainelAdminTheme.laranja,
                        ),
                      ),
                      const SizedBox(height: 4),
                      // Controle de Estoque de forma visual
                      if (estNum == null)
                        Text(
                          'Estoque ilimitado',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade500,
                            fontWeight: FontWeight.w500,
                          ),
                        )
                      else if (estNum == 0)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'Sem estoque',
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.red.shade700,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        )
                      else if (estNum <= 3)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.amber.shade50,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'Apenas $estNum un.',
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.amber.shade800,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        )
                      else
                        Text(
                          'Estoque: $estNum un.',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade600,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: 8),
                  // Menu de Contexto (⋮) para as ações
                  PopupMenuButton<String>(
                    icon:
                        const Icon(Icons.more_vert_rounded, color: Colors.grey),
                    tooltip: 'Ações do produto',
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    onSelected: (val) async {
                      if (val == 'edit') {
                        onEdit();
                      } else if (val == 'delete') {
                        onDelete();
                      } else if (val == 'toggle_vis') {
                        onAlternarAtivo();
                      } else if (val == 'copy_link') {
                        final link =
                            'https://www.dipertin.com.br/p/?produto=${doc.id}';
                        await Clipboard.setData(ClipboardData(text: link));
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Link do produto copiado!'),
                              backgroundColor: Color(0xFF15803D),
                            ),
                          );
                        }
                      }
                    },
                    itemBuilder: (ctx) => [
                      PopupMenuItem(
                        value: 'edit',
                        child: Row(
                          children: [
                            Icon(
                              Icons.edit_outlined,
                              size: 16,
                              color: PainelAdminTheme.roxo,
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              'Editar produto',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'toggle_vis',
                        child: Row(
                          children: [
                            Icon(
                              ativo
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                              size: 16,
                              color: Colors.grey.shade700,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              ativo
                                  ? 'Ocultar da vitrine'
                                  : 'Mostrar na vitrine',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'copy_link',
                        child: Row(
                          children: [
                            Icon(
                              Icons.link_rounded,
                              size: 16,
                              color: Colors.blue,
                            ),
                            SizedBox(width: 8),
                            Text(
                              'Copiar link',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const PopupMenuDivider(height: 1),
                      PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(
                              Icons.delete_outline_rounded,
                              size: 16,
                              color: Colors.red.shade700,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Excluir produto',
                              style: TextStyle(
                                color: Colors.red.shade700,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _badge({
    required String texto,
    IconData? icone,
    required Color corTexto,
    required Color corFundo,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: corFundo,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icone != null) ...[
            Icon(icone, size: 11, color: corTexto),
            const SizedBox(width: 3),
          ],
          Text(
            texto,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: corTexto,
              letterSpacing: 0.1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _thumbVazio() => Container(
        color: const Color(0xFFF0EEF5),
        alignment: Alignment.center,
        child: Icon(
          Icons.restaurant_rounded,
          size: 32,
          color: PainelAdminTheme.roxo.withValues(alpha: 0.28),
        ),
      );
}

class _CartaoProduto extends StatelessWidget {
  const _CartaoProduto({
    required this.moeda,
    required this.doc,
    required this.onEdit,
    required this.onDelete,
    required this.onAlternarAtivo,
  });

  final NumberFormat moeda;
  final DocumentSnapshot<Map<String, dynamic>> doc;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onAlternarAtivo;

  static String _img(dynamic imagens) {
    if (imagens is List && imagens.isNotEmpty) {
      return imagens.first.toString();
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final p = doc.data() ?? {};
    final url = _img(p['imagens']);
    final nome = p['nome']?.toString() ?? 'Sem nome';
    final cat = (p['categoria_nome'] ?? p['categoria'] ?? '').toString().trim();
    final desc = (p['descricao'] ?? '').toString().trim();
    final preco = _precoProduto(p['preco']);
    final est = p['estoque_qtd'];
    final estNum = est is num ? est.toInt() : null;
    final ativo = p['ativo'] != false;
    final tipo = (p['tipo_venda'] ?? 'pronta_entrega').toString();
    final tipoLabel = tipo == 'encomenda' ? 'Encomenda' : 'Pronta entrega';
    final requerVeiculoGrande =
        p['requer_veiculo_grande'] == true || p['carga_maior'] == true;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onEdit,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Área da imagem do produto
              AspectRatio(
                aspectRatio: 1.6,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    url.isNotEmpty
                        ? Image.network(
                            url,
                            fit: BoxFit.cover,
                            webHtmlElementStrategy: kIsWeb
                                ? WebHtmlElementStrategy.prefer
                                : WebHtmlElementStrategy.never,
                            errorBuilder: (_, _, _) => _semFoto(),
                          )
                        : _semFoto(),
                    // Badge de Status (Vitrine/Oculto) no topo direito
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: ativo
                              ? const Color(0xFF15803D).withValues(alpha: 0.9)
                              : Colors.grey.shade800.withValues(alpha: 0.85),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          ativo ? 'VITRINE' : 'OCULTO',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                    ),
                    // Menu ⋮ no topo esquerdo para ações rápidas no modo grade
                    Positioned(
                      top: 8,
                      left: 8,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.45),
                          shape: BoxShape.circle,
                        ),
                        child: PopupMenuButton<String>(
                          icon: const Icon(
                            Icons.more_vert_rounded,
                            color: Colors.white,
                            size: 18,
                          ),
                          tooltip: 'Ações',
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          onSelected: (val) async {
                            if (val == 'edit') {
                              onEdit();
                            } else if (val == 'delete') {
                              onDelete();
                            } else if (val == 'toggle_vis') {
                              onAlternarAtivo();
                            } else if (val == 'copy_link') {
                              final link =
                                  'https://www.dipertin.com.br/p/?produto=${doc.id}';
                              await Clipboard.setData(
                                ClipboardData(text: link),
                              );
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Link do produto copiado!'),
                                    backgroundColor: Color(0xFF15803D),
                                  ),
                                );
                              }
                            }
                          },
                          itemBuilder: (ctx) => [
                            PopupMenuItem(
                              value: 'edit',
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.edit_outlined,
                                    size: 16,
                                    color: PainelAdminTheme.roxo,
                                  ),
                                  const SizedBox(width: 8),
                                  const Text(
                                    'Editar produto',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            PopupMenuItem(
                              value: 'toggle_vis',
                              child: Row(
                                children: [
                                  Icon(
                                    ativo
                                        ? Icons.visibility_off_outlined
                                        : Icons.visibility_outlined,
                                    size: 16,
                                    color: Colors.grey.shade700,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    ativo
                                        ? 'Ocultar da vitrine'
                                        : 'Mostrar na vitrine',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'copy_link',
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.link_rounded,
                                    size: 16,
                                    color: Colors.blue,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Copiar link',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const PopupMenuDivider(),
                            PopupMenuItem(
                              value: 'recusar',
                              onTap: onDelete,
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.delete_outline_rounded,
                                    size: 16,
                                    color: Colors.red.shade700,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Excluir produto',
                                    style: TextStyle(
                                      color: Colors.red.shade700,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    // Categoria no canto inferior esquerdo
                    if (cat.isNotEmpty)
                      Positioned(
                        left: 8,
                        bottom: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            cat,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              // Conteúdo textual e financeiro
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Nome do Produto
                    Text(
                      nome,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        height: 1.25,
                        color: const Color(0xFF1E1B4B),
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    // Descrição curta
                    if (desc.isNotEmpty) ...[
                      Text(
                        desc,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: Colors.grey.shade500,
                          height: 1.3,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                    ],
                    // Badges extras (Tipo de Venda + Veículo)
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: [
                        _badgeMini(
                          texto: tipoLabel,
                          cor: tipo == 'encomenda'
                              ? const Color(0xFF0369A1)
                              : const Color(0xFF0D9488),
                        ),
                        if (requerVeiculoGrande)
                          _badgeMini(
                            texto: 'Carga Maior',
                            cor: PainelAdminTheme.laranja,
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    // Preço & Controle de Estoque
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(
                          moeda.format(preco),
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: PainelAdminTheme.laranja,
                          ),
                        ),
                        const Spacer(),
                        if (estNum == null)
                          Text(
                            'Ilimitado',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade500,
                              fontWeight: FontWeight.w600,
                            ),
                          )
                        else if (estNum == 0)
                          Text(
                            'Sem estoque',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.red.shade700,
                              fontWeight: FontWeight.w800,
                            ),
                          )
                        else if (estNum <= 3)
                          Text(
                            'Apenas $estNum un.',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.amber.shade800,
                              fontWeight: FontWeight.w800,
                            ),
                          )
                        else
                          Text(
                            '$estNum un.',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade600,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _badgeMini({required String texto, required Color cor}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        texto,
        style: TextStyle(
          fontSize: 9.5,
          fontWeight: FontWeight.w800,
          color: cor,
        ),
      ),
    );
  }

  Widget _semFoto() => Container(
        color: const Color(0xFFF0EEF5),
        child: Center(
          child: Icon(
            Icons.restaurant_rounded,
            size: 32,
            color: PainelAdminTheme.roxo.withValues(alpha: 0.25),
          ),
        ),
      );
}
