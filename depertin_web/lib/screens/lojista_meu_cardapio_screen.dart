import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:depertin_web/theme/painel_admin_theme.dart';
import 'package:depertin_web/utils/lojista_painel_context.dart';
import 'package:depertin_web/widgets/botao_suporte_flutuante.dart';
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
    var ativo = d['ativo'] != false;
    var salvando = false;
    var tipo = (d['tipo_venda'] ?? 'pronta_entrega').toString();
    if (tipo != 'pronta_entrega' && tipo != 'encomenda') {
      tipo = 'pronta_entrega';
    }

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Dialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
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
                        TextField(
                          controller: catC,
                          decoration: _dec('Categoria'),
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
                                keyboardType: const TextInputType.numberWithOptions(
                                    decimal: true),
                                inputFormatters: [
                                  FilteringTextInputFormatter.allow(
                                      RegExp(r'[\d.,]')),
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
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Row(
                    children: [
                      TextButton(
                        onPressed:
                            salvando ? null : () => Navigator.pop(ctx),
                        child: const Text('Cancelar'),
                      ),
                      const Spacer(),
                      FilledButton.icon(
                        onPressed: salvando
                            ? null
                            : () async {
                                if (nomeC.text.trim().isEmpty) return;
                                final preco = double.tryParse(
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
                                    'categoria_nome': catC.text.trim(),
                                    'estoque_qtd': est,
                                    'tipo_venda': tipo,
                                    'ativo': ativo,
                                    'imagens': imgs,
                                    'lojista_id': uidLoja,
                                    'loja_id': uidLoja,
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

  Future<void> _excluir(
    BuildContext context,
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Excluir produto?'),
        content: const Text(
          'O item sai da vitrine e é removido do catálogo.',
        ),
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
      backgroundColor: PainelAdminTheme.fundoCanvas,
      floatingActionButton: const BotaoSuporteFlutuante(),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('produtos')
            .where('lojista_id', isEqualTo: uidLoja)
            .snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting &&
              !snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('Erro: ${snap.error}'));
          }

          final todos = snap.data?.docs ?? [];
          int nAtivos = 0;
          int nInativos = 0;
          for (final e in todos) {
            final p = e.data();
            if (p['ativo'] != false) {
              nAtivos++;
            } else {
              nInativos++;
            }
          }

          var docs = todos.toList();
          final q = _buscaC.text.trim().toLowerCase();
          if (q.isNotEmpty) {
            docs = docs.where((e) {
              final m = e.data();
              final nome = (m['nome'] ?? '').toString().toLowerCase();
              final cat = (m['categoria_nome'] ?? m['categoria'] ?? '')
                  .toString()
                  .toLowerCase();
              return nome.contains(q) || cat.contains(q);
            }).toList();
          }
          docs = docs.where((e) {
            return _passaVisibilidade(e.data(), _filtroVisibilidade);
          }).toList();

          docs.sort((a, b) {
            final na = (a.data()['nome'] ?? '').toString().toLowerCase();
            final nb = (b.data()['nome'] ?? '').toString().toLowerCase();
            return na.compareTo(nb);
          });

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1200),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final narrow = constraints.maxWidth < 560;
                        final busca = TextField(
                          controller: _buscaC,
                          onChanged: (_) => setState(() {}),
                          style: const TextStyle(fontSize: 13),
                          decoration: InputDecoration(
                            isDense: true,
                            hintText: 'Buscar nome ou categoria…',
                            hintStyle: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade500,
                            ),
                            prefixIcon: Icon(
                              Icons.search_rounded,
                              size: 20,
                              color: Colors.grey.shade600,
                            ),
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(
                                color: Colors.grey.shade300,
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(
                                color: _roxo,
                                width: 1.5,
                              ),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                          ),
                        );
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (narrow) ...[
                              Text(
                                'Meus produtos',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                  color: _roxo,
                                  letterSpacing: -0.5,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Preço, foto e disponibilidade na vitrine.',
                                style: TextStyle(
                                  color: Colors.grey.shade700,
                                  fontSize: 13,
                                  height: 1.35,
                                ),
                              ),
                              const SizedBox(height: 12),
                              FilledButton.icon(
                                onPressed: () => _abrirFormulario(
                                      context,
                                      uidLoja: uidLoja,
                                    ),
                                style: FilledButton.styleFrom(
                                  backgroundColor: _laranja,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 12,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                                icon: const Icon(Icons.add_rounded, size: 20),
                                label: const Text(
                                  'Novo produto',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ] else
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Meus produtos',
                                          style: GoogleFonts.plusJakartaSans(
                                            fontSize: 22,
                                            fontWeight: FontWeight.w800,
                                            color: _roxo,
                                            letterSpacing: -0.5,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Preço, foto e disponibilidade na vitrine.',
                                          style: TextStyle(
                                            color: Colors.grey.shade700,
                                            fontSize: 13,
                                            height: 1.35,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  FilledButton.icon(
                                    onPressed: () => _abrirFormulario(
                                      context,
                                      uidLoja: uidLoja,
                                    ),
                                    style: FilledButton.styleFrom(
                                      backgroundColor: _laranja,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 12,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                    ),
                                    icon: const Icon(Icons.add_rounded,
                                        size: 20),
                                    label: const Text(
                                      'Novo produto',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            const SizedBox(height: 14),
                            if (constraints.maxWidth < 720)
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  _kpiChipWrap(
                                    icon: Icons.inventory_2_outlined,
                                    label: 'Total',
                                    valor: '${todos.length}',
                                    cor: _roxo,
                                  ),
                                  _kpiChipWrap(
                                    icon: Icons.visibility_outlined,
                                    label: 'Na vitrine',
                                    valor: '$nAtivos',
                                    cor: const Color(0xFF15803D),
                                  ),
                                  _kpiChipWrap(
                                    icon: Icons.visibility_off_outlined,
                                    label: 'Ocultos',
                                    valor: '$nInativos',
                                    cor: Colors.grey.shade700,
                                  ),
                                ],
                              )
                            else
                              Row(
                                children: [
                                  _kpiChip(
                                    icon: Icons.inventory_2_outlined,
                                    label: 'Total',
                                    valor: '${todos.length}',
                                    cor: _roxo,
                                  ),
                                  const SizedBox(width: 8),
                                  _kpiChip(
                                    icon: Icons.visibility_outlined,
                                    label: 'Na vitrine',
                                    valor: '$nAtivos',
                                    cor: const Color(0xFF15803D),
                                  ),
                                  const SizedBox(width: 8),
                                  _kpiChip(
                                    icon: Icons.visibility_off_outlined,
                                    label: 'Ocultos',
                                    valor: '$nInativos',
                                    cor: Colors.grey.shade700,
                                  ),
                                ],
                              ),
                            const SizedBox(height: 12),
                            if (constraints.maxWidth >= 640)
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Expanded(
                                    flex: 5,
                                    child: _segmentoListagem(),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    flex: 4,
                                    child: busca,
                                  ),
                                  const SizedBox(width: 10),
                                  _alternarVisualizacao(),
                                ],
                              )
                            else ...[
                              _segmentoListagem(),
                              const SizedBox(height: 8),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(child: busca),
                                  const SizedBox(width: 8),
                                  _alternarVisualizacao(),
                                ],
                              ),
                            ],
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ),
              Expanded(
                child: docs.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
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
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFF1E1B4B),
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                todos.isEmpty
                                    ? 'Clientes só veem produtos que você cadastrar aqui.'
                                    : 'Ajuste a busca ou o filtro acima.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.grey.shade600,
                                  fontSize: 14,
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
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                  ),
                                  icon: const Icon(Icons.add_rounded),
                                  label: const Text('Criar primeiro produto'),
                                ),
                              ],
                            ],
                          ),
                        ),
                      )
                    : Padding(
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 100),
                        child: Center(
                          child: ConstrainedBox(
                            constraints:
                                const BoxConstraints(maxWidth: 1200),
                            child: _modoVisualizacao == _CardapioView.lista
                                ? ListView.separated(
                                    itemCount: docs.length,
                                    separatorBuilder: (_, _) =>
                                        Divider(
                                      height: 1,
                                      thickness: 1,
                                      color: Colors.grey.shade200,
                                    ),
                                    itemBuilder: (context, i) {
                                      final doc = docs[i];
                                      final p = doc.data();
                                      return _LinhaProduto(
                                        moeda: moeda,
                                        p: p,
                                        onEdit: () => _abrirFormulario(
                                          context,
                                          uidLoja: uidLoja,
                                          existente: doc,
                                        ),
                                        onDelete: () =>
                                            _excluir(context, doc),
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
                                      const gap = 12.0;
                                      return GridView.builder(
                                        gridDelegate:
                                            SliverGridDelegateWithFixedCrossAxisCount(
                                          crossAxisCount: cols,
                                          mainAxisSpacing: gap,
                                          crossAxisSpacing: gap,
                                          childAspectRatio:
                                              cols == 1 ? 1.02 : 0.88,
                                        ),
                                        itemCount: docs.length,
                                        itemBuilder: (context, i) {
                                          final doc = docs[i];
                                          final p = doc.data();
                                          return _CartaoProduto(
                                            moeda: moeda,
                                            p: p,
                                            onEdit: () => _abrirFormulario(
                                              context,
                                              uidLoja: uidLoja,
                                              existente: doc,
                                            ),
                                            onDelete: () =>
                                                _excluir(context, doc),
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
        ButtonSegment<String>(
          value: 'todos',
          label: Text('Todos'),
        ),
        ButtonSegment<String>(
          value: 'ativos',
          label: Text('Na vitrine'),
        ),
        ButtonSegment<String>(
          value: 'inativos',
          label: Text('Ocultos'),
        ),
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
          _modoVisualizacao =
              i == 0 ? _CardapioView.grade : _CardapioView.lista;
        }),
        children: const [
          Icon(Icons.grid_view_rounded, size: 20),
          Icon(Icons.view_list_rounded, size: 20),
        ],
      ),
    );
  }

  Widget _kpiChip({
    required IconData icon,
    required String label,
    required String valor,
    required Color cor,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(icon, color: cor, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    valor,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 17,
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

  /// KPI para `Wrap` (telas estreitas); mesma aparência de [_kpiChip].
  Widget _kpiChipWrap({
    required IconData icon,
    required String label,
    required String valor,
    required Color cor,
  }) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 128, maxWidth: 200),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(icon, color: cor, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    valor,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 17,
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
    required this.p,
    required this.onEdit,
    required this.onDelete,
  });

  final NumberFormat moeda;
  final Map<String, dynamic> p;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  static String _img(dynamic imagens) {
    if (imagens is List && imagens.isNotEmpty) {
      return imagens.first.toString();
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final url = _img(p['imagens']);
    final nome = p['nome']?.toString() ?? 'Sem nome';
    final cat =
        (p['categoria_nome'] ?? p['categoria'] ?? '').toString().trim();
    final preco = _precoProduto(p['preco']);
    final est = p['estoque_qtd'];
    final estStr = est != null ? '$est' : '—';
    final ativo = p['ativo'] != false;
    final tipo = (p['tipo_venda'] ?? 'pronta_entrega').toString();
    final tipoLabel =
        tipo == 'encomenda' ? 'Encomenda' : 'Pronta entrega';

    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: onEdit,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 56,
                  height: 56,
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
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            nome,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF1E1B4B),
                              height: 1.2,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: ativo
                                ? const Color(0xFF15803D)
                                    .withValues(alpha: 0.12)
                                : Colors.grey.shade200,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            ativo ? 'Vitrine' : 'Oculto',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: ativo
                                  ? const Color(0xFF15803D)
                                  : Colors.grey.shade700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        if (cat.isNotEmpty) cat,
                        tipoLabel,
                      ].join(' · '),
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          moeda.format(preco),
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: PainelAdminTheme.laranja,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          'Estoque $estStr',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Editar',
                onPressed: onEdit,
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  Icons.edit_outlined,
                  size: 20,
                  color: PainelAdminTheme.roxo,
                ),
              ),
              IconButton(
                tooltip: 'Excluir',
                onPressed: onDelete,
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  Icons.delete_outline_rounded,
                  size: 20,
                  color: Colors.red.shade700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _thumbVazio() => Container(
        color: const Color(0xFFF0EEF5),
        alignment: Alignment.center,
        child: Icon(
          Icons.restaurant_rounded,
          size: 26,
          color: PainelAdminTheme.roxo.withValues(alpha: 0.28),
        ),
      );
}

class _CartaoProduto extends StatelessWidget {
  const _CartaoProduto({
    required this.moeda,
    required this.p,
    required this.onEdit,
    required this.onDelete,
  });

  final NumberFormat moeda;
  final Map<String, dynamic> p;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  static String _img(dynamic imagens) {
    if (imagens is List && imagens.isNotEmpty) {
      return imagens.first.toString();
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final url = _img(p['imagens']);
    final nome = p['nome']?.toString() ?? 'Sem nome';
    final cat =
        (p['categoria_nome'] ?? p['categoria'] ?? '').toString().trim();
    final desc = (p['descricao'] ?? '').toString().trim();
    final preco = _precoProduto(p['preco']);
    final est = p['estoque_qtd'];
    final estStr = est != null ? '$est un.' : '—';
    final ativo = p['ativo'] != false;
    final tipo = (p['tipo_venda'] ?? 'pronta_entrega').toString();
    final tipoLabel =
        tipo == 'encomenda' ? 'Encomenda' : 'Pronta entrega';

    return Material(
      color: Colors.white,
      elevation: 0,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onEdit,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(
              aspectRatio: 1.65,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (url.isNotEmpty)
                    Image.network(
                      url,
                      fit: BoxFit.cover,
                      webHtmlElementStrategy: kIsWeb
                          ? WebHtmlElementStrategy.prefer
                          : WebHtmlElementStrategy.never,
                      errorBuilder: (_, _, _) => _semFoto(),
                    )
                  else
                    _semFoto(),
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: ativo
                            ? const Color(0xFF15803D).withValues(alpha: 0.92)
                            : Colors.grey.shade800.withValues(alpha: 0.88),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        ativo ? 'NA VITRINE' : 'OCULTO',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                  ),
                  if (cat.isNotEmpty)
                    Positioned(
                      left: 6,
                      bottom: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.45),
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
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    nome,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      height: 1.2,
                      color: const Color(0xFF1E1B4B),
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (desc.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      desc,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade600,
                        height: 1.25,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 6),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
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
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            'Estoque $estStr',
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.grey.shade600,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            tipoLabel,
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.grey.shade500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: onEdit,
                          icon: const Icon(Icons.edit_outlined, size: 16),
                          label: const Text('Editar'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: PainelAdminTheme.roxo,
                            side: BorderSide(color: Colors.grey.shade300),
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            visualDensity: VisualDensity.compact,
                            textStyle: const TextStyle(fontSize: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      IconButton(
                        tooltip: 'Excluir',
                        onPressed: onDelete,
                        visualDensity: VisualDensity.compact,
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.red.withValues(alpha: 0.08),
                          foregroundColor: Colors.red.shade700,
                          minimumSize: const Size(36, 36),
                          padding: EdgeInsets.zero,
                        ),
                        icon: const Icon(Icons.delete_outline_rounded, size: 20),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _semFoto() => Container(
        color: const Color(0xFFF0EEF5),
        child: Center(
          child: Icon(
            Icons.restaurant_rounded,
            size: 36,
            color: PainelAdminTheme.roxo.withValues(alpha: 0.25),
          ),
        ),
      );
}
