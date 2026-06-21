import 'dart:math' show min;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:depertin_web/constants/tipos_entrega.dart';
import 'package:depertin_web/theme/painel_admin_theme.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

/// Slugs preset em `tabela_fretes/{cidade}_{slug}` (alinha ao carrinho).
const Set<String> _kSlugsFretePresetPainel = {
  TiposEntrega.codBicicleta,
  TiposEntrega.codMoto,
  'padrao',
  TiposEntrega.codCarro,
  TiposEntrega.codCarroFrete,
};

/// Ordem estável do dropdown "Categoria / tabela" (deve coincidir com o app).
const List<String> _kFretePresetsOrdenadosPainel = <String>[
  TiposEntrega.codBicicleta,
  TiposEntrega.codMoto,
  'padrao',
  TiposEntrega.codCarro,
  TiposEntrega.codCarroFrete,
];

final RegExp _kRegexSlugFretePersonalizadoPainel = RegExp(r'^[a-z0-9_]{2,48}$');

String _suffixDocFretePainel(String docId) {
  final id = docId.toLowerCase().trim();
  if (id.isEmpty) return TiposEntrega.codMoto;
  final ordenado = _kSlugsFretePresetPainel.toList()
    ..sort((a, b) => b.length.compareTo(a.length));
  for (final slug in ordenado) {
    if (id.endsWith('_$slug')) return slug;
  }
  final i = id.lastIndexOf('_');
  if (i <= 0 || i >= id.length - 1) {
    return id;
  }
  return id.substring(i + 1);
}

String _rotuloPresetListaFretePainel(String slugPreset) {
  switch (slugPreset) {
    case TiposEntrega.codBicicleta:
      return TiposEntrega.rotulo(TiposEntrega.codBicicleta);
    case TiposEntrega.codMoto:
      return TiposEntrega.rotulo(TiposEntrega.codMoto);
    case 'padrao':
      return 'Padrão combinado (moto e bike — legado)';
    case TiposEntrega.codCarro:
      return TiposEntrega.rotulo(TiposEntrega.codCarro);
    case TiposEntrega.codCarroFrete:
      return TiposEntrega.rotulo(TiposEntrega.codCarroFrete);
    default:
      return slugPreset;
  }
}

String _campoVeiculoLegadoFretePainel({
  required bool usarPersonalizado,
  required String tipoTabelaCanon,
  required String presetOuSlugManual,
}) {
  if (usarPersonalizado) {
    final alvo =
        _rotuloPresetListaFretePainel(tipoTabelaCanon.toLowerCase());
    return 'Personalizado (${presetOuSlugManual.trim()}) — no app: $alvo';
  }
  return _rotuloPresetListaFretePainel(presetOuSlugManual);
}

/// Chave canônica em `tabela_fretes/{cidade}_{slug}` — sem acento, minúscula
/// (alinha ao carrinho mobile: `_chaveCidadeTabelaFrete`).
String _normalizarChaveCidadeFretePainel(String valor) {
  var s = valor.trim().toLowerCase();
  if (s.isEmpty) return s;
  if (s == 'todas as cidades') return 'todas';
  const mapa = <String, String>{
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
  final sb = StringBuffer();
  for (final r in s.runes) {
    final ch = String.fromCharCode(r);
    sb.write(mapa[ch] ?? ch);
  }
  s = sb.toString();
  final partes = s.split(RegExp(r'\s*[—–\-]\s*'));
  return partes.isNotEmpty ? partes.first.trim() : s;
}

String _rotuloCidadeFretePainel(String chave) {
  final c = chave.trim().toLowerCase();
  if (c.isEmpty) return chave;
  if (c == 'todas') return 'Todas';
  return c[0].toUpperCase() + c.substring(1);
}

String _prefixoCidadeDocFretePainel(String docId) {
  final suffix = _suffixDocFretePainel(docId);
  final id = docId.toLowerCase().trim();
  if (suffix.isNotEmpty && id.endsWith('_$suffix')) {
    return id.substring(0, id.length - suffix.length - 1);
  }
  final i = id.lastIndexOf('_');
  return i > 0 ? id.substring(0, i) : id;
}

/// Metadados só para UI — ordem deve coincidir com [TabController] (4 abas).
class _CfgFinanceSecao {
  const _CfgFinanceSecao({
    required this.rotuloNavegacao,
    required this.tituloPainel,
    required this.descricao,
    required this.icon,
  });

  final String rotuloNavegacao;
  final String tituloPainel;
  final String descricao;
  final IconData icon;
}

const List<_CfgFinanceSecao> _kCfgFinanceSecoes = [
  _CfgFinanceSecao(
    rotuloNavegacao: 'Comissões · lojistas',
    tituloPainel: 'Comissões da plataforma',
    descricao:
        'Defina percentuais ou valores fixos por cidade e periodicidade.',
    icon: Icons.storefront_rounded,
  ),
  _CfgFinanceSecao(
    rotuloNavegacao: 'Comissões · entregadores',
    tituloPainel: 'Desconto do Entregadores',
    descricao: 'Taxas por tipo de veículo e cidade para a rede de entregas.',
    icon: Icons.two_wheeler_rounded,
  ),
  _CfgFinanceSecao(
    rotuloNavegacao: 'Fretes',
    tituloPainel: 'Tabela de fretes',
    descricao:
        'Valor base, distância inclusa e valor por quilômetro adicional.',
    icon: Icons.route_rounded,
  ),
  _CfgFinanceSecao(
    rotuloNavegacao: 'Pagamentos',
    tituloPainel: 'Gateways de pagamento',
    descricao:
        'Credenciais e gateway ativo utilizados no checkout do aplicativo.',
    icon: Icons.credit_card_rounded,
  ),
];

class ConfiguracoesScreen extends StatefulWidget {
  const ConfiguracoesScreen({super.key});

  @override
  State<ConfiguracoesScreen> createState() => _ConfiguracoesScreenState();
}

class _ConfiguracoesScreenState extends State<ConfiguracoesScreen>
    with SingleTickerProviderStateMixin {
  final Color diPertinRoxo = PainelAdminTheme.roxo;
  final Color diPertinLaranja = PainelAdminTheme.laranja;

  late TabController _tabController;

  List<_OpcaoCidadeConfig> _opcoesCidadesConfig = const [
    _OpcaoCidadeConfig(rotulo: 'Todas', valorSalvar: 'todas'),
  ];

  static const double _kMaxContentWidth = 920;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
    _carregarCidadesDoBanco();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _carregarCidadesDoBanco() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('cidades_atendidas')
          .get();
      final opcoes = <_OpcaoCidadeConfig>[
        const _OpcaoCidadeConfig(rotulo: 'Todas', valorSalvar: 'todas'),
      ];
      final vistos = <String>{'todas'};
      for (final doc in snapshot.docs) {
        final dados = doc.data();
        if ((dados['ativa'] as bool?) == false) continue;
        var norm = (dados['nome_normalizada'] ?? '').toString().trim();
        if (norm.isEmpty) {
          norm = _normalizarChaveCidadeFretePainel(
            (dados['nome'] ?? '').toString(),
          );
        }
        if (norm.isEmpty || vistos.contains(norm)) continue;
        vistos.add(norm);
        final rotulo = (dados['label'] ?? dados['nome'] ?? norm)
            .toString()
            .trim();
        opcoes.add(_OpcaoCidadeConfig(rotulo: rotulo, valorSalvar: norm));
      }
      opcoes.sort((a, b) {
        if (a.valorSalvar == 'todas') return -1;
        if (b.valorSalvar == 'todas') return 1;
        return a.rotulo.compareTo(b.rotulo);
      });
      if (mounted) {
        setState(() => _opcoesCidadesConfig = opcoes);
      }
    } catch (e) {
      debugPrint('Erro ao carregar cidades_atendidas: $e');
    }
  }

  String _rotuloParaValorSalvar(String valorSalvar) {
    final v = valorSalvar.trim().toLowerCase();
    if (v.isEmpty || v == 'todas' || v == 'todas as cidades') {
      return 'Todas';
    }
    for (final o in _opcoesCidadesConfig) {
      if (o.valorSalvar == v) return o.rotulo;
    }
    return _rotuloCidadeFretePainel(v);
  }

  String _resolverValorSalvarCidade(String textoDigitado) {
    final t = textoDigitado.trim();
    if (t.isEmpty) return '';
    final low = t.toLowerCase();
    if (low == 'todas' || low == 'todas as cidades') return 'todas';
    for (final o in _opcoesCidadesConfig) {
      if (o.rotulo.toLowerCase() == low) return o.valorSalvar;
      if (o.valorSalvar == low) return o.valorSalvar;
    }
    return _normalizarChaveCidadeFretePainel(t);
  }

  List<_OpcaoCidadeConfig> _filtrarOpcoesCidade(String query) {
    final q = _normalizarChaveCidadeFretePainel(query);
    if (q.isEmpty) {
      return _opcoesCidadesConfig.take(14).toList();
    }
    return _opcoesCidadesConfig
        .where((o) {
          final rot = _normalizarChaveCidadeFretePainel(o.rotulo);
          return rot.contains(q) ||
              o.valorSalvar.contains(q) ||
              o.rotulo.toLowerCase().contains(query.trim().toLowerCase());
        })
        .take(14)
        .toList();
  }

  InputDecoration _dialogFieldDecoration(
    String label, {
    Widget? suffixIcon,
    String? prefixText,
    String? suffixText,
    String? helperText,
  }) {
    return InputDecoration(
      labelText: label,
      helperText: helperText,
      helperMaxLines: helperText != null ? 4 : null,
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
        borderSide: BorderSide(color: diPertinRoxo, width: 1.5),
      ),
      labelStyle: TextStyle(
        color: Colors.grey.shade700,
        fontWeight: FontWeight.w500,
        fontSize: 14,
      ),
      suffixIcon: suffixIcon,
      prefixText: prefixText,
      suffixText: suffixText,
    );
  }

  Widget _dialogHeader({
    required IconData icon,
    required String titulo,
    required String subtitulo,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            diPertinRoxo.withValues(alpha: 0.09),
            diPertinRoxo.withValues(alpha: 0.03),
          ],
        ),
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade200),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: diPertinRoxo.withValues(alpha: 0.12),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Icon(icon, color: diPertinRoxo, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titulo,
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    color: diPertinRoxo,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  subtitulo,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: PainelAdminTheme.textoSecundario,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // === POP-UP CRIAR / EDITAR PLANO (COMISSÃO DO APP) ===
  void _mostrarFormularioNovoPlano({
    String publicoInicial = 'lojista',
    String? docIdEditar,
    Map<String, dynamic>? dadosEditar,
  }) {
    final isEdicao = docIdEditar != null;
    String publicoAlvo =
        dadosEditar != null ? (dadosEditar['publico'] ?? publicoInicial) : publicoInicial;
    String tipoCobranca =
        dadosEditar != null ? (dadosEditar['tipo_cobranca'] ?? 'porcentagem') : 'porcentagem';
    String frequencia =
        dadosEditar != null ? (dadosEditar['frequencia'] ?? 'venda') : 'venda';
    String veiculo =
        dadosEditar != null ? (dadosEditar['veiculo'] ?? 'Todos') : 'Todos';
    final nomePlanoC = TextEditingController(
      text: dadosEditar != null ? (dadosEditar['nome'] ?? '') : '',
    );
    final valorC = TextEditingController(
      text: dadosEditar != null ? (dadosEditar['valor']?.toString() ?? '') : '',
    );
    final cidadePlanoC = TextEditingController(
      text: _rotuloParaValorSalvar(
        dadosEditar != null
            ? (dadosEditar['cidade'] ?? 'todas').toString()
            : 'todas',
      ),
    );
    var isLoading = false;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            Future<void> salvarPlano() async {
              if (nomePlanoC.text.trim().isEmpty ||
                  valorC.text.trim().isEmpty ||
                  cidadePlanoC.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text(
                      "Preencha o nome do plano e o valor.",
                    ),
                    backgroundColor: diPertinRoxo,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
                return;
              }
              setState(() => isLoading = true);
              try {
                final valor =
                    double.tryParse(valorC.text.replaceAll(',', '.')) ?? 0.0;
                final dados = <String, dynamic>{
                  'nome': nomePlanoC.text.trim(),
                  'publico': publicoAlvo,
                  'tipo_cobranca': tipoCobranca,
                  'frequencia': frequencia,
                  'valor': valor,
                  'cidade': _resolverValorSalvarCidade(cidadePlanoC.text),
                  'ativo': true,
                  if (isEdicao)
                    'data_atualizacao': FieldValue.serverTimestamp()
                  else
                    'data_criacao': FieldValue.serverTimestamp(),
                };
                if (publicoAlvo == 'entregador') {
                  dados['veiculo'] = veiculo;
                }
                if (isEdicao) {
                  await FirebaseFirestore.instance
                      .collection('planos_taxas')
                      .doc(docIdEditar)
                      .update(dados);
                } else {
                  await FirebaseFirestore.instance
                      .collection('planos_taxas')
                      .add(dados);
                }
                if (context.mounted) Navigator.pop(context);
              } catch (e) {
                debugPrint("Erro: $e");
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text("Não foi possível salvar: $e"),
                      backgroundColor: const Color(0xFFB91C1C),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              } finally {
                if (context.mounted) {
                  setState(() => isLoading = false);
                }
              }
            }

            final mq = MediaQuery.sizeOf(context);
            final dialogW = min(500.0, mq.width - 40);
            final dialogH = min(640.0, mq.height * 0.88);

            return Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              clipBehavior: Clip.antiAlias,
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 28,
              ),
              backgroundColor: Colors.white,
              elevation: 16,
              shadowColor: diPertinRoxo.withValues(alpha: 0.2),
              child: SizedBox(
                width: dialogW,
                height: dialogH,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _dialogHeader(
                      icon: isEdicao
                          ? Icons.edit_note_rounded
                          : Icons.percent_rounded,
                      titulo: isEdicao
                          ? "Editar comissão"
                          : "Nova comissão ou taxa",
                      subtitulo:
                          "Defina o público, a cidade e como o app cobra (percentual ou valor fixo).",
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(22, 20, 22, 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            DropdownButtonFormField<String>(
                              key: ValueKey<String>('dlg_pub_$publicoAlvo'),
                              initialValue: publicoAlvo,
                              decoration: _dialogFieldDecoration(
                                "Público-alvo",
                              ),
                              items: const [
                                DropdownMenuItem(
                                  value: 'lojista',
                                  child: Text("Lojistas"),
                                ),
                                DropdownMenuItem(
                                  value: 'entregador',
                                  child: Text("Entregadores"),
                                ),
                              ],
                              onChanged: (val) =>
                                  setState(() => publicoAlvo = val!),
                            ),
                            const SizedBox(height: 16),
                            TextField(
                              controller: nomePlanoC,
                              textCapitalization: TextCapitalization.words,
                              decoration: _dialogFieldDecoration(
                                "Nome identificador do plano",
                              ),
                            ),
                            const SizedBox(height: 16),
                            _CampoCidadeConfigPainel(
                              controller: cidadePlanoC,
                              opcoes: _opcoesCidadesConfig,
                              filtrar: _filtrarOpcoesCidade,
                              onAbrirLista: () async {
                                final sel = await _abrirSeletorCidadeConfig(
                                  cidadePlanoC.text.trim(),
                                );
                                if (sel != null) cidadePlanoC.text = sel;
                              },
                              decoration: _dialogFieldDecoration(
                                'Cidade',
                                helperText:
                                    'Digite para filtrar cidades cadastradas em '
                                    'AdminCity ou use «Todas» como fallback.',
                                suffixIcon: IconButton(
                                  tooltip: 'Lista completa',
                                  icon: Icon(
                                    Icons.arrow_drop_down_rounded,
                                    color: Colors.grey.shade700,
                                  ),
                                  onPressed: () async {
                                    final sel = await _abrirSeletorCidadeConfig(
                                      cidadePlanoC.text.trim(),
                                    );
                                    if (sel != null) cidadePlanoC.text = sel;
                                  },
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            if (publicoAlvo == 'entregador') ...[
                              DropdownButtonFormField<String>(
                                key: ValueKey<String>(
                                  'dlg_veic_${publicoAlvo}_$veiculo',
                                ),
                                initialValue: veiculo,
                                decoration: _dialogFieldDecoration(
                                  "Tipo de veículo",
                                ),
                                items: ['Todos', 'Moto', 'Carro', 'Bicicleta']
                                    .map(
                                      (v) => DropdownMenuItem(
                                        value: v,
                                        child: Text(v),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (val) =>
                                    setState(() => veiculo = val!),
                              ),
                              const SizedBox(height: 16),
                            ],
                            DropdownButtonFormField<String>(
                              key: ValueKey<String>('dlg_freq_$frequencia'),
                              initialValue: frequencia,
                              decoration: _dialogFieldDecoration(
                                "Frequência da cobrança",
                              ),
                              items: const [
                                DropdownMenuItem(
                                  value: 'venda',
                                  child: Text("Por venda"),
                                ),
                                DropdownMenuItem(
                                  value: 'semana',
                                  child: Text("Semanal"),
                                ),
                                DropdownMenuItem(
                                  value: 'mes',
                                  child: Text("Mensal"),
                                ),
                              ],
                              onChanged: (val) =>
                                  setState(() => frequencia = val!),
                            ),
                            const SizedBox(height: 16),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: DropdownButtonFormField<String>(
                                    key: ValueKey<String>(
                                      'dlg_tipo_$tipoCobranca',
                                    ),
                                    initialValue: tipoCobranca,
                                    decoration: _dialogFieldDecoration(
                                      "Tipo de cobrança",
                                    ),
                                    items: const [
                                      DropdownMenuItem(
                                        value: 'porcentagem',
                                        child: Text("Percentual (%)"),
                                      ),
                                      DropdownMenuItem(
                                        value: 'fixo',
                                        child: Text("Valor fixo (R\$)"),
                                      ),
                                    ],
                                    onChanged: (val) =>
                                        setState(() => tipoCobranca = val!),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: TextField(
                                    controller: valorC,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                    decoration: _dialogFieldDecoration(
                                      "Valor",
                                      prefixText: tipoCobranca == 'fixo'
                                          ? "R\$ "
                                          : null,
                                      suffixText: tipoCobranca == 'porcentagem'
                                          ? " %"
                                          : null,
                                    ),
                                  ),
                                ),
                              ],
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
                            onPressed: isLoading
                                ? null
                                : () => Navigator.pop(context),
                            child: Text(
                              "Cancelar",
                              style: TextStyle(
                                color: diPertinRoxo,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          FilledButton.icon(
                            onPressed: isLoading ? null : salvarPlano,
                            icon: isLoading
                                ? SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white.withValues(
                                        alpha: 0.9,
                                      ),
                                    ),
                                  )
                                : const Icon(Icons.check_rounded, size: 20),
                            label: Text(
                              isLoading
                                  ? "Salvando…"
                                  : isEdicao
                                      ? "Salvar alterações"
                                      : "Salvar plano",
                            ),
                            style: FilledButton.styleFrom(
                              backgroundColor: diPertinLaranja,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 22,
                                vertical: 14,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
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
        );
      },
    );
  }

  /// Lista completa de cidades cadastradas (`cidades_atendidas`).
  Future<String?> _abrirSeletorCidadeConfig(String valorAtual) async {
    final ctrlBusca = TextEditingController();
    String filtro = '';
    return showDialog<String>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDlg) {
            final opcoes = _opcoesCidadesConfig.where((c) {
              if (filtro.isEmpty) return true;
              final rot = _normalizarChaveCidadeFretePainel(c.rotulo);
              return rot.contains(filtro) ||
                  c.valorSalvar.contains(filtro) ||
                  c.rotulo.toLowerCase().contains(filtro);
            }).toList();
            return AlertDialog(
              title: const Text('Selecionar cidade'),
              content: SizedBox(
                width: min(420.0, MediaQuery.sizeOf(ctx).width - 48),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: ctrlBusca,
                      autofocus: true,
                      onChanged: (v) =>
                          setDlg(() => filtro = v.trim().toLowerCase()),
                      decoration: InputDecoration(
                        hintText: 'Buscar cidade…',
                        prefixIcon: const Icon(Icons.search_rounded),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 280),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: opcoes.length,
                        itemBuilder: (_, i) {
                          final c = opcoes[i];
                          final sel = c.rotulo == valorAtual;
                          return ListTile(
                            dense: true,
                            selected: sel,
                            title: Text(c.rotulo),
                            subtitle: c.valorSalvar == 'todas'
                                ? null
                                : Text(
                                    c.valorSalvar,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                            onTap: () => Navigator.pop(ctx, c.rotulo),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancelar'),
                ),
              ],
            );
          },
        );
      },
    );
  }


  // === FORMULÁRIO DE FRETES ===
  void _mostrarFormularioNovoFrete({
    String? docIdEditar,
    Map<String, dynamic>? dadosEditar,
  }) {
    final isEdicao = docIdEditar != null;
    final valorBaseC = TextEditingController(
      text: dadosEditar != null
          ? (dadosEditar['valor_base']?.toString() ?? '')
          : '',
    );
    final distBaseC = TextEditingController(
      text: dadosEditar != null
          ? (dadosEditar['distancia_base_km']?.toString() ?? '3')
          : '3',
    );
    final valorKmExtraC = TextEditingController(
      text: dadosEditar != null
          ? (dadosEditar['valor_km_adicional']?.toString() ?? '')
          : '',
    );
    final cidadeChaveInicial = dadosEditar != null
        ? _normalizarChaveCidadeFretePainel(
            (dadosEditar['cidade'] ?? _prefixoCidadeDocFretePainel(
              docIdEditar ?? '',
            ))
                .toString(),
          )
        : 'todas';
    final cidadeFreteC = TextEditingController(
      text: _rotuloParaValorSalvar(cidadeChaveInicial),
    );
    final slugDoDocIni =
        docIdEditar != null ? _suffixDocFretePainel(docIdEditar) : '';
    final tipoTblSalvo =
        dadosEditar?['tipo_tabela']?.toString().trim().toLowerCase();
    var usarSlugPersonalizado = docIdEditar != null &&
        slugDoDocIni.isNotEmpty &&
        !_kSlugsFretePresetPainel.contains(slugDoDocIni);
    var tipoTabelaFallback =
        (tipoTblSalvo != null &&
                _kSlugsFretePresetPainel.contains(tipoTblSalvo))
            ? tipoTblSalvo
            : (slugDoDocIni.isNotEmpty &&
                    _kSlugsFretePresetPainel.contains(slugDoDocIni)
                ? slugDoDocIni
                : TiposEntrega.codMoto);
    var presetSlug = !usarSlugPersonalizado &&
            slugDoDocIni.isNotEmpty &&
            _kSlugsFretePresetPainel.contains(slugDoDocIni)
        ? slugDoDocIni
        : ((tipoTblSalvo != null &&
                _kSlugsFretePresetPainel.contains(tipoTblSalvo))
            ? tipoTblSalvo
            : TiposEntrega.codMoto);
    final slugManualCtrl = TextEditingController(
      text: usarSlugPersonalizado ? slugDoDocIni : '',
    );
    var isLoading = false;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            Future<void> salvarFrete() async {
              if (valorBaseC.text.trim().isEmpty ||
                  distBaseC.text.trim().isEmpty ||
                  valorKmExtraC.text.trim().isEmpty ||
                  cidadeFreteC.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text(
                      "Preencha valor base, distância e valor por km extra.",
                    ),
                    backgroundColor: diPertinRoxo,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
                return;
              }

              final slugManualLimpo =
                  slugManualCtrl.text.trim().toLowerCase();

              if (usarSlugPersonalizado &&
                  !_kRegexSlugFretePersonalizadoPainel
                      .hasMatch(slugManualLimpo)) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text(
                      "Slug personalizado inválido. Use apenas letras minúsculas, números e sublinhado "
                      "(2 a 48 caracteres). Reserve palavras-preset (ex.: «moto», «bicicleta»).",
                    ),
                    backgroundColor: diPertinRoxo,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
                return;
              }

              if (usarSlugPersonalizado &&
                  _kSlugsFretePresetPainel.contains(slugManualLimpo)) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text(
                      "Esse slug é reservado para uma categoria pré-definida. "
                      "Desative «Identificador personalizado» e escolha a categoria correspondente.",
                    ),
                    backgroundColor: diPertinRoxo,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
                return;
              }

              setState(() => isLoading = true);
              try {
                final valorBase =
                    double.tryParse(valorBaseC.text.replaceAll(',', '.')) ??
                    0.0;
                final distBase =
                    double.tryParse(distBaseC.text.replaceAll(',', '.')) ?? 0.0;
                final valorKmExtra =
                    double.tryParse(valorKmExtraC.text.replaceAll(',', '.')) ??
                    0.0;

                final cidadeChave =
                    _resolverValorSalvarCidade(cidadeFreteC.text);

                if (cidadeChave.isEmpty) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: const Text('Informe a cidade da regra.'),
                        backgroundColor: diPertinRoxo,
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                  return;
                }

                final String suffixDoc =
                    usarSlugPersonalizado ? slugManualLimpo : presetSlug;
                final String tipoTabelaCanon = usarSlugPersonalizado
                    ? tipoTabelaFallback
                    : presetSlug;

                final veiculoLegado = _campoVeiculoLegadoFretePainel(
                  usarPersonalizado: usarSlugPersonalizado,
                  tipoTabelaCanon: tipoTabelaCanon,
                  presetOuSlugManual:
                      usarSlugPersonalizado ? slugManualLimpo : presetSlug,
                );

                final novoDocId = '${cidadeChave}_$suffixDoc';

                if (isEdicao) {
                  final refCol =
                      FirebaseFirestore.instance.collection('tabela_fretes');
                  final dadosAtualizados = <String, dynamic>{
                    'cidade': cidadeChave,
                    'veiculo': veiculoLegado,
                    'tipo_tabela': tipoTabelaCanon,
                    'valor_base': valorBase,
                    'distancia_base_km': distBase,
                    'valor_km_adicional': valorKmExtra,
                    'data_atualizacao': FieldValue.serverTimestamp(),
                  };

                  if (novoDocId == docIdEditar) {
                    await refCol.doc(docIdEditar).update(dadosAtualizados);
                  } else {
                    final existeNovo = await refCol.doc(novoDocId).get();
                    if (existeNovo.exists) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Já existe outra regra com o identificador $novoDocId. '
                              'Ajuste cidade ou categoria.',
                            ),
                            backgroundColor: const Color(0xFFB91C1C),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      }
                      return;
                    }
                    final batch = FirebaseFirestore.instance.batch();
                    batch.set(refCol.doc(novoDocId), dadosAtualizados);
                    batch.delete(refCol.doc(docIdEditar));
                    await batch.commit();
                  }
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          novoDocId == docIdEditar
                              ? 'Regra de frete atualizada.'
                              : 'Regra atualizada (identificador: $novoDocId).',
                        ),
                        backgroundColor: Colors.green.shade700,
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                } else {
                  final dados = <String, dynamic>{
                    'cidade': cidadeChave,
                    'veiculo': veiculoLegado,
                    'tipo_tabela': tipoTabelaCanon,
                    'valor_base': valorBase,
                    'distancia_base_km': distBase,
                    'valor_km_adicional': valorKmExtra,
                    'data_atualizacao': FieldValue.serverTimestamp(),
                  };
                  final refDoc = FirebaseFirestore.instance
                      .collection('tabela_fretes')
                      .doc(novoDocId);
                  final existe = await refDoc.get();
                  if (existe.exists) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Já existe uma regra com o mesmo identificador: $novoDocId.',
                          ),
                          backgroundColor: const Color(0xFFB91C1C),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    }
                    return;
                  }
                  await refDoc.set(dados);
                }
                if (context.mounted) Navigator.pop(context);
              } catch (e) {
                debugPrint("Erro: $e");
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text("Não foi possível salvar: $e"),
                      backgroundColor: const Color(0xFFB91C1C),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              } finally {
                if (context.mounted) {
                  setState(() => isLoading = false);
                }
              }
            }

            final mq = MediaQuery.sizeOf(context);
            final dialogW = min(500.0, mq.width - 40);
            final dialogH = min(560.0, mq.height * 0.88);

            return Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              clipBehavior: Clip.antiAlias,
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 28,
              ),
              backgroundColor: Colors.white,
              elevation: 16,
              shadowColor: diPertinRoxo.withValues(alpha: 0.2),
              child: SizedBox(
                width: dialogW,
                height: dialogH,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _dialogHeader(
                      icon: isEdicao
                          ? Icons.edit_road_rounded
                          : Icons.route_rounded,
                      titulo:
                          isEdicao ? "Editar regra de frete" : "Nova regra de frete",
                      subtitulo:
                          "Valor fixo até uma distância base e acréscimo por quilômetro extra.",
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(22, 20, 22, 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _CampoCidadeConfigPainel(
                              controller: cidadeFreteC,
                              opcoes: _opcoesCidadesConfig,
                              filtrar: _filtrarOpcoesCidade,
                              onAbrirLista: () async {
                                final sel = await _abrirSeletorCidadeConfig(
                                  cidadeFreteC.text.trim(),
                                );
                                if (sel != null) cidadeFreteC.text = sel;
                              },
                              decoration: _dialogFieldDecoration(
                                'Cidade',
                                helperText:
                                    'Digite para filtrar cidades cadastradas. '
                                    'Use «Todas» como fallback nacional.',
                                suffixIcon: IconButton(
                                  tooltip: 'Lista completa',
                                  icon: Icon(
                                    Icons.arrow_drop_down_rounded,
                                    color: Colors.grey.shade700,
                                  ),
                                  onPressed: () async {
                                    final sel = await _abrirSeletorCidadeConfig(
                                      cidadeFreteC.text.trim(),
                                    );
                                    if (sel == null || !context.mounted) {
                                      return;
                                    }
                                    cidadeFreteC.text = sel;
                                  },
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            if (isEdicao) ...[
                              Text(
                                'Identificador atual: $docIdEditar',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey.shade700,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.only(top: 6, bottom: 4),
                                child: Text(
                                  'Ao mudar cidade ou categoria, o identificador é recriado '
                                  'automaticamente (a regra antiga é substituída).',
                                  style: TextStyle(
                                    fontSize: 12,
                                    height: 1.35,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                            ],
                            SwitchListTile.adaptive(
                              contentPadding: EdgeInsets.zero,
                              title:
                                  const Text('Identificador personalizado da regra'),
                              subtitle: Text(
                                isEdicao
                                    ? 'Não é possível alternar modo ao editar.'
                                    : 'Use para várias tarifas paralelas às categorias pré-definidas '
                                        '(precisa definir quando o carrinho aplica esta linha).',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                              value: usarSlugPersonalizado,
                              onChanged: isEdicao
                                  ? null
                                  : (v) {
                                      setState(() {
                                        usarSlugPersonalizado = v;
                                        slugManualCtrl.text = '';
                                      });
                                    },
                            ),
                            if (!usarSlugPersonalizado) ...[
                              DropdownButtonFormField<String>(
                                key: ValueKey<String>('preset_${presetSlug}_$isEdicao'),
                                value: presetSlug,
                                decoration: _dialogFieldDecoration(
                                  'Categoria do frete (tabela no app)',
                                  helperText:
                                      'Bicicleta e moto têm valores separados. «Padrão» cobre '
                                      'regras antigas que uniam moto e bike.',
                                ),
                                items: [
                                  for (final s in _kFretePresetsOrdenadosPainel)
                                    DropdownMenuItem<String>(
                                      value: s,
                                      child: Text(
                                        _rotuloPresetListaFretePainel(s),
                                      ),
                                    ),
                                ],
                                onChanged: (v) {
                                  if (v != null) {
                                    setState(() => presetSlug = v);
                                  }
                                },
                              ),
                            ] else ...[
                              TextField(
                                controller: slugManualCtrl,
                                readOnly: false,
                                autocorrect: false,
                                decoration: _dialogFieldDecoration(
                                  'Slug (identificador do documento)',
                                  helperText:
                                      'Nome único sem acento. O ID fica cidade_slug '
                                      '(apenas minúsculas e _; 2 a 48 caracteres). '
                                      'Evite slug reservado tipo «moto» ou «bicicleta».',
                                ),
                              ),
                              const SizedBox(height: 12),
                              DropdownButtonFormField<String>(
                                key: ValueKey<String>(
                                  'fallback_${tipoTabelaFallback}_${presetSlug}_${usarSlugPersonalizado}_$isEdicao',
                                ),
                                value: tipoTabelaFallback,
                                decoration: _dialogFieldDecoration(
                                  'No app conta como',
                                  helperText:
                                      'Tipo canônico usado na busca pelo carrinho (cadeia de fallback). '
                                      'Ao editar, você pode só ajustar este vínculo sem mudar o slug.',
                                ),
                                items: [
                                  for (final s in _kFretePresetsOrdenadosPainel)
                                    DropdownMenuItem<String>(
                                      value: s,
                                      child: Text(_rotuloPresetListaFretePainel(s)),
                                    ),
                                ],
                                onChanged: (v) {
                                  if (v != null) {
                                    setState(() => tipoTabelaFallback = v);
                                  }
                                },
                              ),
                            ],
                            const SizedBox(height: 16),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: valorBaseC,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                    decoration: _dialogFieldDecoration(
                                      "Valor fixo base",
                                      prefixText: "R\$ ",
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: TextField(
                                    controller: distBaseC,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                    decoration: _dialogFieldDecoration(
                                      "Incluído até",
                                      suffixText: " km",
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            TextField(
                              controller: valorKmExtraC,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                decimal: true,
                              ),
                              decoration: _dialogFieldDecoration(
                                "Valor por km adicional",
                                prefixText: "+ R\$ ",
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
                            onPressed: isLoading
                                ? null
                                : () => Navigator.pop(context),
                            child: Text(
                              "Cancelar",
                              style: TextStyle(
                                color: diPertinRoxo,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          FilledButton.icon(
                            onPressed: isLoading ? null : salvarFrete,
                            icon: isLoading
                                ? SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white.withValues(
                                        alpha: 0.9,
                                      ),
                                    ),
                                  )
                                : const Icon(Icons.check_rounded, size: 20),
                            label: Text(
                              isLoading
                                  ? "Salvando…"
                                  : isEdicao
                                      ? "Salvar alterações"
                                      : "Salvar regra",
                            ),
                            style: FilledButton.styleFrom(
                              backgroundColor: diPertinLaranja,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 22,
                                vertical: 14,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
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
        );
      },
    ).whenComplete(slugManualCtrl.dispose);
  }

  Future<void> _deletarDocumento(
    String colecao,
    String id, {
    String? nomeExibicao,
  }) async {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: diPertinLaranja),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                "Remover registro",
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        content: Text(
          nomeExibicao != null && nomeExibicao.isNotEmpty
              ? "O item \"$nomeExibicao\" será removido permanentemente. Esta ação não pode ser desfeita."
              : "Este registro será removido permanentemente. Esta ação não pode ser desfeita.",
          style: const TextStyle(height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancelar"),
          ),
          FilledButton(
            onPressed: () async {
              await FirebaseFirestore.instance
                  .collection(colecao)
                  .doc(id)
                  .delete();
              if (ctx.mounted) Navigator.pop(ctx);
            },
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFB91C1C),
              foregroundColor: Colors.white,
            ),
            child: const Text("Remover"),
          ),
        ],
      ),
    );
  }

  String _labelFrequencia(Object? raw) {
    final s = raw?.toString() ?? '';
    switch (s) {
      case 'venda':
        return 'por venda';
      case 'semana':
        return 'por semana';
      case 'mes':
        return 'por mês';
      default:
        return s.isEmpty ? '—' : s;
    }
  }

  Widget _wrapConteudoCentral(Widget child) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _kMaxContentWidth),
        child: child,
      ),
    );
  }

  Widget _emptyState({
    required IconData icon,
    required String titulo,
    required String subtitulo,
    VoidCallback? onAdicionar,
    String? labelBotao,
  }) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 56, color: diPertinRoxo.withValues(alpha: 0.35)),
              const SizedBox(height: 20),
              Text(
                titulo,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: diPertinRoxo,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                subtitulo,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: PainelAdminTheme.textoSecundario,
                  height: 1.45,
                ),
              ),
              if (onAdicionar != null && labelBotao != null) ...[
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: onAdicionar,
                  icon: const Icon(Icons.add, size: 20),
                  label: Text(labelBotao),
                  style: FilledButton.styleFrom(
                    backgroundColor: diPertinLaranja,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 14,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _chipInfo(String texto, {IconData? icon}) {
    return Chip(
      avatar: icon != null
          ? Icon(icon, size: 16, color: diPertinRoxo)
          : null,
      label: Text(texto),
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      side: BorderSide(color: Colors.grey.shade300),
      backgroundColor: Colors.grey.shade50,
      labelStyle: const TextStyle(fontSize: 13),
    );
  }

  Widget _buildListaPlanos(String publico) {
    final isLojista = publico == 'lojista';
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('planos_taxas')
          .where('publico', isEqualTo: publico)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final planos = snapshot.data?.docs ?? [];
        if (planos.isEmpty) {
          return _emptyState(
            icon: isLojista ? Icons.store_outlined : Icons.two_wheeler_outlined,
            titulo: isLojista
                ? "Nenhuma comissão para lojistas"
                : "Nenhuma comissão para entregadores",
            subtitulo: isLojista
                ? "Crie regras de comissão por cidade (percentual ou valor fixo) para os lojistas."
                : "Defina taxas por veículo e cidade para os entregadores da rede.",
            onAdicionar: () => _mostrarFormularioNovoPlano(
              publicoInicial: publico,
            ),
            labelBotao: isLojista
                ? "Nova comissão (lojista)"
                : "Nova comissão (entregador)",
          );
        }
        return _wrapConteudoCentral(
          ListView.separated(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
            itemCount: planos.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final doc = planos[index];
              final dados = doc.data() as Map<String, dynamic>;
              final nome = (dados['nome'] ?? 'Sem nome').toString();
              final cidadeRaw = dados['cidade'];
              final cidade = cidadeRaw?.toString().trim().isNotEmpty == true
                  ? cidadeRaw.toString()
                  : 'todas';
              final isFixo = dados['tipo_cobranca'] == 'fixo';
              final freq = _labelFrequencia(dados['frequencia']);
              final valorResumo = isFixo
                  ? "R\$ ${dados['valor']} · $freq"
                  : "${dados['valor']}% · $freq";
              final tipoLabel =
                  isFixo ? "Valor fixo" : "Percentual";

              return Material(
                color: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: const BorderSide(color: PainelAdminTheme.dashboardBorder),
                ),
                clipBehavior: Clip.antiAlias,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 16,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: diPertinRoxo.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: diPertinRoxo.withValues(alpha: 0.12),
                          ),
                        ),
                        child: Icon(
                          isLojista ? Icons.storefront_rounded : Icons.moped_rounded,
                          color: diPertinRoxo,
                          size: 26,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              nome,
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.2,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                _chipInfo(
                                  "Local: ${cidade.toUpperCase()}",
                                  icon: Icons.place_outlined,
                                ),
                                _chipInfo(tipoLabel, icon: Icons.category_outlined),
                                _chipInfo(
                                  "Comissão: $valorResumo",
                                  icon: Icons.payments_outlined,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: "Editar plano",
                        icon: Icon(
                          Icons.edit_outlined,
                          color: diPertinRoxo,
                        ),
                        onPressed: () => _mostrarFormularioNovoPlano(
                          publicoInicial: publico,
                          docIdEditar: doc.id,
                          dadosEditar: dados,
                        ),
                      ),
                      IconButton(
                        tooltip: "Remover plano",
                        icon: Icon(
                          Icons.delete_outline_rounded,
                          color: Colors.grey.shade600,
                        ),
                        onPressed: () => _deletarDocumento(
                          'planos_taxas',
                          doc.id,
                          nomeExibicao: nome,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildListaFretes() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('tabela_fretes')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final fretes = snapshot.data?.docs ?? [];
        if (fretes.isEmpty) {
          return _emptyState(
            icon: Icons.route_outlined,
            titulo: "Nenhuma regra de frete",
            subtitulo:
                "Cadastre valores base por cidade e km adicional para o cálculo de entregas.",
            onAdicionar: _mostrarFormularioNovoFrete,
            labelBotao: "Nova regra de frete",
          );
        }
        return _wrapConteudoCentral(
          ListView.separated(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
            itemCount: fretes.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final doc = fretes[index];
              final dados = doc.data() as Map<String, dynamic>;
              final base = (dados['valor_base'] as num?)?.toDouble() ?? 0.0;
              final dist =
                  (dados['distancia_base_km'] as num?)?.toDouble() ?? 0.0;
              final extra =
                  (dados['valor_km_adicional'] as num?)?.toDouble() ?? 0.0;
              final cidade = (dados['cidade'] ?? '—').toString();
              final tipoTc =
                  (dados['tipo_tabela'] ?? '').toString().trim().toLowerCase();
              final slugDoId = _suffixDocFretePainel(doc.id);
              final rotuloNoApp = tipoTc.isNotEmpty
                  ? _rotuloPresetListaFretePainel(tipoTc)
                  : _rotuloPresetListaFretePainel(slugDoId);
              final cidadeFmt = _rotuloCidadeFretePainel(
                _normalizarChaveCidadeFretePainel(cidade),
              ).toUpperCase();
              final titulo = '$cidadeFmt · $rotuloNoApp';
              return Material(
                color: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: const BorderSide(color: PainelAdminTheme.dashboardBorder),
                ),
                clipBehavior: Clip.antiAlias,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 16,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: diPertinLaranja.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: diPertinLaranja.withValues(alpha: 0.22),
                          ),
                        ),
                        child: Icon(
                          Icons.local_shipping_outlined,
                          color: diPertinLaranja,
                          size: 26,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              titulo,
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.2,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              doc.id,
                              style: TextStyle(
                                fontSize: 12,
                                height: 1.35,
                                color: Colors.grey.shade600,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                _chipInfo(
                                  "Base: R\$ ${base.toStringAsFixed(2)} até ${dist.toStringAsFixed(0)} km",
                                  icon: Icons.flag_outlined,
                                ),
                                _chipInfo(
                                  "+ R\$ ${extra.toStringAsFixed(2)} / km extra",
                                  icon: Icons.add_road,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: "Editar regra",
                        icon: Icon(
                          Icons.edit_outlined,
                          color: diPertinLaranja,
                        ),
                        onPressed: () => _mostrarFormularioNovoFrete(
                          docIdEditar: doc.id,
                          dadosEditar: dados,
                        ),
                      ),
                      IconButton(
                        tooltip: "Remover regra",
                        icon: Icon(
                          Icons.delete_outline_rounded,
                          color: Colors.grey.shade600,
                        ),
                        onPressed: () => _deletarDocumento(
                          'tabela_fretes',
                          doc.id,
                          nomeExibicao: titulo,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildGatewaysPagamento() {
    final gatewaysDisponiveis = <Map<String, String>>[
      {
        'id': 'mercado_pago',
        'nome': 'Mercado Pago',
        'logo':
            'https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcQIGOGLllcBPYfomOl6ezt5bQvSL0fu8nQLPQ&s',
      },
      {
        'id': 'asaas',
        'nome': 'Asaas',
        'logo':
            'https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcRfgalXkdqkJg2RTrDEo7iBLEGNC1ppZTzq4g&s',
      },
      {
        'id': 'pagarme',
        'nome': 'Pagar.me',
        'logo': 'https://avatars.githubusercontent.com/u/3846050?s=280&v=4',
      },
    ];

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('gateways_pagamento')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final gatewaysSalvos = <String, Map<String, dynamic>>{};
        if (snapshot.hasData) {
          for (final doc in snapshot.data!.docs) {
            gatewaysSalvos[doc.id] = doc.data() as Map<String, dynamic>;
          }
        }

        return _wrapConteudoCentral(
          ListView.separated(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
            itemCount: gatewaysDisponiveis.length,
            separatorBuilder: (_, _) => const SizedBox(height: 20),
            itemBuilder: (context, index) {
              final gw = gatewaysDisponiveis[index];
              final dados = gatewaysSalvos[gw['id']] ?? <String, dynamic>{};
              return _GatewayConfigCard(
                gateway: gw,
                dadosIniciais: dados,
                roxo: diPertinRoxo,
                laranja: diPertinLaranja,
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildAcoesContextuaisTopo() {
    final i = _tabController.index;
    if (i == 3) {
      return Text(
        "Defina abaixo qual gateway estará ativo no app.",
        style: TextStyle(
          fontSize: 13,
          color: PainelAdminTheme.textoSecundario,
          fontWeight: FontWeight.w500,
          height: 1.35,
        ),
      );
    }
    if (i == 2) {
      return FilledButton.icon(
        onPressed: _mostrarFormularioNovoFrete,
        icon: const Icon(Icons.add_road_rounded, size: 20),
        label: const Text("Nova regra de frete"),
        style: FilledButton.styleFrom(
          backgroundColor: diPertinLaranja,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        ),
      );
    }
    if (i == 1) {
      return FilledButton.icon(
        onPressed: () =>
            _mostrarFormularioNovoPlano(publicoInicial: 'entregador'),
        icon: const Icon(Icons.percent_rounded, size: 20),
        label: const Text("Nova comissão (entregador)"),
        style: FilledButton.styleFrom(
          backgroundColor: diPertinLaranja,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        ),
      );
    }
    return FilledButton.icon(
      onPressed: () => _mostrarFormularioNovoPlano(publicoInicial: 'lojista'),
      icon: const Icon(Icons.percent_rounded, size: 20),
      label: const Text("Nova comissão (lojista)"),
      style: FilledButton.styleFrom(
        backgroundColor: diPertinLaranja,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      ),
    );
  }

  Widget _railDestino(int i) {
    final sel = _tabController.index == i;
    final m = _kCfgFinanceSecoes[i];
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _tabController.animateTo(i),
          hoverColor: diPertinRoxo.withValues(alpha: 0.05),
          splashColor: diPertinRoxo.withValues(alpha: 0.08),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.fromLTRB(10, 12, 14, 12),
            decoration: BoxDecoration(
              color: sel ? Colors.white : Colors.transparent,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: sel
                    ? diPertinRoxo.withValues(alpha: 0.28)
                    : PainelAdminTheme.dashboardBorder.withValues(alpha: 0.35),
              ),
              boxShadow: sel ? PainelAdminTheme.sombraCardSuave() : null,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  width: 3,
                  height: 38,
                  decoration: BoxDecoration(
                    color: sel ? diPertinRoxo : Colors.transparent,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(width: 12),
                Icon(
                  m.icon,
                  size: 22,
                  color: sel
                      ? diPertinRoxo
                      : PainelAdminTheme.textoSecundario,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        m.rotuloNavegacao,
                        style: TextStyle(
                          fontWeight:
                              sel ? FontWeight.w700 : FontWeight.w600,
                          fontSize: 13.5,
                          height: 1.25,
                          letterSpacing: -0.1,
                          color: sel
                              ? PainelAdminTheme.dashboardInk
                              : PainelAdminTheme.textoSecundario,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        m.descricao,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          height: 1.35,
                          color: PainelAdminTheme.textoSecundario.withValues(
                            alpha: sel ? 0.9 : 0.72,
                          ),
                        ),
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

  Widget _pillSecao(int i) {
    final sel = _tabController.index == i;
    final m = _kCfgFinanceSecoes[i];
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: () => _tabController.animateTo(i),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: sel ? diPertinRoxo.withValues(alpha: 0.11) : Colors.white,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: sel
                  ? diPertinRoxo.withValues(alpha: 0.35)
                  : PainelAdminTheme.dashboardBorder,
            ),
            boxShadow: sel
                ? [
                    BoxShadow(
                      color: diPertinRoxo.withValues(alpha: 0.08),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                m.icon,
                size: 18,
                color: sel ? diPertinRoxo : PainelAdminTheme.textoSecundario,
              ),
              const SizedBox(width: 8),
              Text(
                m.rotuloNavegacao,
                style: TextStyle(
                  fontWeight: sel ? FontWeight.w700 : FontWeight.w600,
                  fontSize: 12,
                  color: sel
                      ? PainelAdminTheme.dashboardInk
                      : PainelAdminTheme.textoSecundario,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _toolbarSecao(
    ThemeData theme,
    _CfgFinanceSecao meta, {
    required bool empilharAcao,
  }) {
    final titleBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          meta.tituloPainel,
          style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                color: PainelAdminTheme.dashboardInk,
                letterSpacing: -0.35,
              ) ??
              TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: PainelAdminTheme.dashboardInk,
                letterSpacing: -0.35,
              ),
        ),
        const SizedBox(height: 6),
        Text(
          meta.descricao,
          style: const TextStyle(
            color: PainelAdminTheme.textoSecundario,
            fontSize: 14,
            height: 1.45,
          ),
        ),
      ],
    );

    final acao = _buildAcoesContextuaisTopo();

    if (empilharAcao) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            titleBlock,
            const SizedBox(height: 16),
            acao,
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: diPertinRoxo.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(13),
              border: Border.all(
                color: diPertinRoxo.withValues(alpha: 0.12),
              ),
            ),
            child: Icon(meta.icon, color: diPertinRoxo, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(child: titleBlock),
          const SizedBox(width: 20),
          Flexible(
            child: Align(
              alignment: Alignment.topRight,
              child: acao,
            ),
          ),
        ],
      ),
    );
  }

  Widget _painelConteudoTab(Widget tabView) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FC),
        border: Border(
          top: BorderSide(color: PainelAdminTheme.dashboardBorder),
        ),
      ),
      child: tabView,
    );
  }

  Widget _conteudoAbas({required ScrollPhysics physics}) {
    return TabBarView(
      controller: _tabController,
      physics: physics,
      children: [
        _buildListaPlanos('lojista'),
        _buildListaPlanos('entregador'),
        _buildListaFretes(),
        _buildGatewaysPagamento(),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final idx = _tabController.index.clamp(0, _kCfgFinanceSecoes.length - 1);
    final meta = _kCfgFinanceSecoes[idx];

    return Scaffold(
      backgroundColor: PainelAdminTheme.fundoCanvas,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final useRail = constraints.maxWidth >= 960;
          final hPad =
              constraints.maxWidth < 520 ? 12.0 : (constraints.maxWidth < 960 ? 16.0 : 24.0);

          final tabView = _conteudoAbas(
            physics: useRail
                ? const NeverScrollableScrollPhysics()
                : const BouncingScrollPhysics(),
          );

          if (useRail) {
            final maxOuter = min(constraints.maxWidth - hPad * 2, 1240.0);
            return Padding(
              padding: EdgeInsets.fromLTRB(hPad, 20, hPad, 20),
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxOuter),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        width: 286,
                        decoration: PainelAdminTheme.dashboardCard(),
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(
                                22,
                                24,
                                22,
                                8,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'FINANCEIRO',
                                    style: theme.textTheme.labelSmall?.copyWith(
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 1.35,
                                          color: diPertinRoxo.withValues(
                                            alpha: 0.85,
                                          ),
                                          fontSize: 11,
                                        ) ??
                                        TextStyle(
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 1.35,
                                          color: diPertinRoxo.withValues(
                                            alpha: 0.85,
                                          ),
                                          fontSize: 11,
                                        ),
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    'Configurações',
                                    style: theme.textTheme.headlineSmall
                                            ?.copyWith(
                                              fontWeight: FontWeight.w800,
                                              color: PainelAdminTheme
                                                  .dashboardInk,
                                              letterSpacing: -0.55,
                                            ) ??
                                        const TextStyle(
                                          fontSize: 26,
                                          fontWeight: FontWeight.w800,
                                          color: PainelAdminTheme.dashboardInk,
                                          letterSpacing: -0.55,
                                        ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'Comissões, fretes e meios de pagamento.',
                                    style: TextStyle(
                                      fontSize: 13,
                                      height: 1.4,
                                      color: PainelAdminTheme.textoSecundario,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 8),
                            Expanded(
                              child: ListView.builder(
                                padding: const EdgeInsets.fromLTRB(
                                  12,
                                  0,
                                  12,
                                  16,
                                ),
                                itemCount: _kCfgFinanceSecoes.length,
                                itemBuilder: (context, i) => _railDestino(i),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 22),
                      Expanded(
                        child: Container(
                          decoration: PainelAdminTheme.dashboardCard(),
                          clipBehavior: Clip.antiAlias,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _toolbarSecao(
                                theme,
                                meta,
                                empilharAcao: false,
                              ),
                              Expanded(
                                child: _painelConteudoTab(tabView),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }

          return Padding(
            padding: EdgeInsets.fromLTRB(hPad, 16, hPad, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Configurações financeiras',
                  style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: PainelAdminTheme.dashboardInk,
                        letterSpacing: -0.45,
                      ) ??
                      const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: PainelAdminTheme.dashboardInk,
                      ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Escolha uma área abaixo.',
                  style: TextStyle(
                    fontSize: 13,
                    color: PainelAdminTheme.textoSecundario,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 14),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (var i = 0; i < _kCfgFinanceSecoes.length; i++)
                        Padding(
                          padding: EdgeInsets.only(
                            right: i == _kCfgFinanceSecoes.length - 1 ? 0 : 10,
                          ),
                          child: _pillSecao(i),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: Container(
                    decoration: PainelAdminTheme.dashboardCard(),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _toolbarSecao(
                          theme,
                          meta,
                          empilharAcao: true,
                        ),
                        Expanded(
                          child: _painelConteudoTab(tabView),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Cartão de gateway com controllers estáveis (evita perder texto a cada rebuild).
class _OpcaoCidadeConfig {
  final String rotulo;
  final String valorSalvar;

  const _OpcaoCidadeConfig({
    required this.rotulo,
    required this.valorSalvar,
  });
}

/// Campo de cidade com sugestões **inline** (sem overlay do Autocomplete no web).
class _CampoCidadeConfigPainel extends StatefulWidget {
  final TextEditingController controller;
  final List<_OpcaoCidadeConfig> opcoes;
  final List<_OpcaoCidadeConfig> Function(String query) filtrar;
  final Future<void> Function()? onAbrirLista;
  final InputDecoration decoration;

  const _CampoCidadeConfigPainel({
    required this.controller,
    required this.opcoes,
    required this.filtrar,
    required this.decoration,
    this.onAbrirLista,
  });

  @override
  State<_CampoCidadeConfigPainel> createState() =>
      _CampoCidadeConfigPainelState();
}

class _CampoCidadeConfigPainelState extends State<_CampoCidadeConfigPainel> {
  final FocusNode _focus = FocusNode();
  bool _mostrarSugestoes = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_aoMudarFoco);
    widget.controller.addListener(_aoMudarTexto);
  }

  @override
  void dispose() {
    _focus.removeListener(_aoMudarFoco);
    widget.controller.removeListener(_aoMudarTexto);
    _focus.dispose();
    super.dispose();
  }

  void _aoMudarFoco() {
    if (!mounted) return;
    setState(() => _mostrarSugestoes = _focus.hasFocus);
  }

  void _aoMudarTexto() {
    if (!mounted) return;
    setState(() {});
  }

  void _aplicarSugestao(_OpcaoCidadeConfig opcao) {
    widget.controller.text = opcao.rotulo;
    widget.controller.selection = TextSelection.collapsed(
      offset: opcao.rotulo.length,
    );
    setState(() => _mostrarSugestoes = false);
    _focus.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final sugestoes = widget.filtrar(widget.controller.text);
    final exibirLista =
        _mostrarSugestoes && sugestoes.isNotEmpty && widget.opcoes.length > 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: widget.controller,
          focusNode: _focus,
          textCapitalization: TextCapitalization.words,
          decoration: widget.decoration,
          onTap: () => setState(() => _mostrarSugestoes = true),
        ),
        if (exibirLista) ...[
          const SizedBox(height: 6),
          Material(
            elevation: 2,
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 176),
              child: ListView.separated(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: sugestoes.length,
                separatorBuilder: (_, _) => Divider(
                  height: 1,
                  color: Colors.grey.shade200,
                ),
                itemBuilder: (context, index) {
                  final o = sugestoes[index];
                  return ListTile(
                    dense: true,
                    visualDensity: VisualDensity.compact,
                    title: Text(
                      o.rotulo,
                      style: const TextStyle(fontSize: 14),
                    ),
                    subtitle: o.valorSalvar == 'todas'
                        ? null
                        : Text(
                            o.valorSalvar,
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade600,
                            ),
                          ),
                    onTap: () => _aplicarSugestao(o),
                  );
                },
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _GatewayConfigCard extends StatefulWidget {
  const _GatewayConfigCard({
    required this.gateway,
    required this.dadosIniciais,
    required this.roxo,
    required this.laranja,
  });

  final Map<String, String> gateway;
  final Map<String, dynamic> dadosIniciais;
  final Color roxo;
  final Color laranja;

  @override
  State<_GatewayConfigCard> createState() => _GatewayConfigCardState();
}

class _GatewayConfigCardState extends State<_GatewayConfigCard> {
  late TextEditingController _publicKey;
  late TextEditingController _accessToken;

  /// Mostra/oculta o valor digitado no campo access_token (toggle do olho).
  /// Começa oculto pra reduzir exposição em screenshots / screen sharing.
  bool _accessTokenVisivel = false;

  String get _tokenSalvoNoFirestore =>
      (widget.dadosIniciais['access_token'] ?? '').toString();

  bool get _temTokenSalvo => _tokenSalvoNoFirestore.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _publicKey = TextEditingController(
      text: (widget.dadosIniciais['public_key'] ?? '').toString(),
    );
    // Hardening (Fase 3H): o controller do access_token começa VAZIO mesmo que
    // já exista valor no Firestore, pra evitar carregar o segredo em texto
    // claro no DOM / memória da aba. Pra alterar, o master redigita; pra só
    // confirmar que existe, observa o label "(salvo)" abaixo.
    _accessToken = TextEditingController();
  }

  @override
  void didUpdateWidget(covariant _GatewayConfigCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nk = (widget.dadosIniciais['public_key'] ?? '').toString();
    final ok = (oldWidget.dadosIniciais['public_key'] ?? '').toString();
    if (nk != ok && _publicKey.text != nk) {
      _publicKey.text = nk;
    }
    // NÃO sincronizamos access_token com o Firestore — campo permanece com o
    // que o master digitou (ou vazio) até ele clicar em salvar.
  }

  @override
  void dispose() {
    _publicKey.dispose();
    _accessToken.dispose();
    super.dispose();
  }

  Future<void> _salvarEAtivar() async {
    final publicKey = _publicKey.text.trim();
    final tokenNovo = _accessToken.text.trim();

    if (publicKey.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text("Preencha a chave pública."),
          backgroundColor: widget.roxo,
        ),
      );
      return;
    }
    if (tokenNovo.isEmpty && !_temTokenSalvo) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            "Preencha o access token na primeira configuração.",
          ),
          backgroundColor: widget.roxo,
        ),
      );
      return;
    }

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (c) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 20),
            Expanded(child: Text("A gravar credenciais…")),
          ],
        ),
      ),
    );

    try {
      final batch = FirebaseFirestore.instance.batch();
      final todos = await FirebaseFirestore.instance
          .collection('gateways_pagamento')
          .get();
      for (final doc in todos.docs) {
        batch.update(doc.reference, {'ativo': false});
      }
      await batch.commit();

      // Só envia access_token se o master digitou um valor novo; caso contrário
      // usamos merge:true pra preservar o token atual no Firestore.
      final dadosParaGravar = <String, dynamic>{
        'nome': widget.gateway['nome'],
        'public_key': publicKey,
        'ativo': true,
        'data_atualizacao': FieldValue.serverTimestamp(),
      };
      if (tokenNovo.isNotEmpty) {
        dadosParaGravar['access_token'] = tokenNovo;
      }

      await FirebaseFirestore.instance
          .collection('gateways_pagamento')
          .doc(widget.gateway['id'])
          .set(dadosParaGravar, SetOptions(merge: true));

      if (mounted) {
        _accessToken.clear();
        setState(() => _accessTokenVisivel = false);
      }

      if (!mounted) return;
      Navigator.of(context).pop();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "${widget.gateway['nome']} é agora o método de pagamento ativo.",
          ),
          backgroundColor: const Color(0xFF15803D),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Erro ao gravar: $e"),
          backgroundColor: const Color(0xFFB91C1C),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final gw = widget.gateway;
    final isAtivo = widget.dadosIniciais['ativo'] == true;

    return Material(
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isAtivo ? widget.laranja : PainelAdminTheme.dashboardBorder,
          width: isAtivo ? 2 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.network(
                    gw['logo']!,
                    height: 44,
                    width: 44,
                    fit: BoxFit.cover,
                    webHtmlElementStrategy: kIsWeb
                        ? WebHtmlElementStrategy.prefer
                        : WebHtmlElementStrategy.never,
                    errorBuilder: (c, e, s) => Container(
                      height: 44,
                      width: 44,
                      color: widget.roxo.withValues(alpha: 0.08),
                      child: Icon(Icons.account_balance, color: widget.roxo),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        gw['nome']!,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "Credenciais armazenadas de forma segura no Firestore.",
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isAtivo)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: widget.roxo.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      "ATIVO NO APP",
                      style: TextStyle(
                        color: widget.roxo,
                        fontWeight: FontWeight.w800,
                        fontSize: 11,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            LayoutBuilder(
              builder: (context, c) {
                final narrow = c.maxWidth < 720;
                final campos = [
                  TextField(
                    controller: _publicKey,
                    decoration: InputDecoration(
                      labelText: "Public key (chave pública)",
                      border: const OutlineInputBorder(),
                      prefixIcon: Icon(Icons.vpn_key_outlined, color: widget.roxo),
                    ),
                  ),
                  TextField(
                    controller: _accessToken,
                    obscureText: !_accessTokenVisivel,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: InputDecoration(
                      labelText: _temTokenSalvo
                          ? "Access token (salvo)"
                          : "Access token",
                      hintText: _temTokenSalvo
                          ? "Deixe em branco para manter o token atual"
                          : null,
                      helperText: _temTokenSalvo
                          ? "Credencial protegida. Digite um novo valor só se quiser trocar."
                          : null,
                      border: const OutlineInputBorder(),
                      prefixIcon: Icon(
                        Icons.lock_outline_rounded,
                        color: widget.roxo,
                      ),
                      suffixIcon: IconButton(
                        tooltip: _accessTokenVisivel
                            ? "Ocultar token digitado"
                            : "Mostrar token digitado",
                        icon: Icon(
                          _accessTokenVisivel
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          color: Colors.grey.shade700,
                        ),
                        onPressed: () => setState(
                          () => _accessTokenVisivel = !_accessTokenVisivel,
                        ),
                      ),
                    ),
                  ),
                ];
                if (narrow) {
                  return Column(
                    children: [
                      campos[0],
                      const SizedBox(height: 14),
                      campos[1],
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: campos[0]),
                    const SizedBox(width: 14),
                    Expanded(child: campos[1]),
                  ],
                );
              },
            ),
            const SizedBox(height: 20),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: _salvarEAtivar,
                icon: const Icon(Icons.check_circle_outline_rounded, size: 20),
                label: Text(isAtivo ? "Atualizar e manter ativo" : "Salvar e ativar"),
                style: FilledButton.styleFrom(
                  backgroundColor: widget.laranja,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 14,
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
