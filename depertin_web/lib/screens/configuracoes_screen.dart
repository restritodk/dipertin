import 'dart:math' show min;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:depertin_web/theme/painel_admin_theme.dart';
import 'package:depertin_web/widgets/botao_suporte_flutuante.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

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

  List<String> _cidadesSugeridas = ['Todas'];

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
      var snapshot = await FirebaseFirestore.instance.collection('users').get();
      Set<String> cidadesUnicas = {'Todas'};
      for (var doc in snapshot.docs) {
        var dados = doc.data();
        if (dados['cidade'] != null &&
            dados['cidade'].toString().trim().isNotEmpty) {
          String cidade = dados['cidade'].toString().trim();
          String cidadeFormatada =
              cidade[0].toUpperCase() + cidade.substring(1).toLowerCase();
          cidadesUnicas.add(cidadeFormatada);
        }
      }
      setState(() {
        _cidadesSugeridas = cidadesUnicas.toList();
        _cidadesSugeridas.sort();
        _cidadesSugeridas.remove('Todas');
        _cidadesSugeridas.insert(0, 'Todas');
      });
    } catch (e) {
      debugPrint("Erro: $e");
    }
  }

  InputDecoration _dialogFieldDecoration(
    String label, {
    Widget? suffixIcon,
    String? prefixText,
    String? suffixText,
  }) {
    return InputDecoration(
      labelText: label,
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
    final cidadeInicial = dadosEditar != null
        ? _capitalizar(dadosEditar['cidade']?.toString() ?? 'Todas')
        : 'Todas';
    String cidadeSelecionada = cidadeInicial;
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
                  cidadeSelecionada.isEmpty) {
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
                  'cidade': cidadeSelecionada.trim().toLowerCase(),
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
                            Autocomplete<String>(
                              initialValue:
                                  TextEditingValue(text: cidadeInicial),
                              optionsBuilder: (TextEditingValue text) {
                                if (text.text.isEmpty) {
                                  return _cidadesSugeridas;
                                }
                                return _cidadesSugeridas.where(
                                  (String option) => option
                                      .toLowerCase()
                                      .contains(text.text.toLowerCase()),
                                );
                              },
                              onSelected: (String selection) =>
                                  cidadeSelecionada = selection,
                              fieldViewBuilder: (
                                context,
                                controller,
                                focusNode,
                                onFieldSubmitted,
                              ) {
                                controller.addListener(
                                  () => cidadeSelecionada = controller.text,
                                );
                                return TextField(
                                  controller: controller,
                                  focusNode: focusNode,
                                  decoration: _dialogFieldDecoration(
                                    "Cidade",
                                    suffixIcon: Icon(
                                      Icons.search_rounded,
                                      color: Colors.grey.shade600,
                                      size: 22,
                                    ),
                                  ),
                                );
                              },
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
    final cidadeInicial = dadosEditar != null
        ? _capitalizar(dadosEditar['cidade']?.toString() ?? 'Todas')
        : 'Todas';
    String cidadeSelecionada = cidadeInicial;
    String veiculo =
        dadosEditar != null ? (dadosEditar['veiculo'] ?? 'Padrão (Moto/Bike)') : 'Padrão (Moto/Bike)';
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
                  cidadeSelecionada.isEmpty) {
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

                final dados = <String, dynamic>{
                  'cidade': cidadeSelecionada.trim().toLowerCase(),
                  'veiculo': veiculo,
                  'valor_base': valorBase,
                  'distancia_base_km': distBase,
                  'valor_km_adicional': valorKmExtra,
                  'data_atualizacao': FieldValue.serverTimestamp(),
                };
                if (isEdicao) {
                  await FirebaseFirestore.instance
                      .collection('tabela_fretes')
                      .doc(docIdEditar)
                      .update(dados);
                } else {
                  final docId =
                      "${cidadeSelecionada.trim().toLowerCase()}_${veiculo.contains('Carro') ? 'carro' : 'padrao'}";
                  await FirebaseFirestore.instance
                      .collection('tabela_fretes')
                      .doc(docId)
                      .set(dados);
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
                          "Valor fixo até uma distância base e acréscimo por quilómetro extra.",
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(22, 20, 22, 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Autocomplete<String>(
                              initialValue:
                                  TextEditingValue(text: cidadeInicial),
                              optionsBuilder: (TextEditingValue text) {
                                if (text.text.isEmpty) {
                                  return _cidadesSugeridas;
                                }
                                return _cidadesSugeridas.where(
                                  (String option) => option
                                      .toLowerCase()
                                      .contains(text.text.toLowerCase()),
                                );
                              },
                              onSelected: (String selection) =>
                                  cidadeSelecionada = selection,
                              fieldViewBuilder: (
                                context,
                                controller,
                                focusNode,
                                onFieldSubmitted,
                              ) {
                                controller.addListener(
                                  () => cidadeSelecionada = controller.text,
                                );
                                return TextField(
                                  controller: controller,
                                  focusNode: focusNode,
                                  decoration: _dialogFieldDecoration(
                                    "Cidade",
                                    suffixIcon: Icon(
                                      Icons.search_rounded,
                                      color: Colors.grey.shade600,
                                      size: 22,
                                    ),
                                  ),
                                );
                              },
                            ),
                            const SizedBox(height: 16),
                            DropdownButtonFormField<String>(
                              key: ValueKey<String>('dlg_frete_veic_$veiculo'),
                              initialValue: veiculo,
                              decoration: _dialogFieldDecoration(
                                "Categoria do frete",
                              ),
                              items: const [
                                DropdownMenuItem(
                                  value: 'Padrão (Moto/Bike)',
                                  child: Text("Padrão (moto / bike)"),
                                ),
                                DropdownMenuItem(
                                  value: 'Cargas Maiores (Carro)',
                                  child: Text("Cargas maiores (carro)"),
                                ),
                              ],
                              onChanged: (val) =>
                                  setState(() => veiculo = val!),
                            ),
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
    );
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

  String _capitalizar(String s) {
    if (s.isEmpty) return s;
    return s[0].toUpperCase() + s.substring(1);
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
                  side: BorderSide(color: Colors.grey.shade200),
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
              final veiculo = (dados['veiculo'] ?? '—').toString();
              final cidade = (dados['cidade'] ?? '—').toString();
              final titulo = "$veiculo · ${cidade.toUpperCase()}";

              return Material(
                color: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: Colors.grey.shade200),
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
          color: Colors.grey.shade600,
          fontWeight: FontWeight.w500,
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: PainelAdminTheme.fundoCanvas,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: Colors.white,
            elevation: 0,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    final narrow = constraints.maxWidth < 720;
                    final tituloCol = Column(
                      crossAxisAlignment: narrow
                          ? CrossAxisAlignment.center
                          : CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Configurações financeiras",
                          textAlign: narrow ? TextAlign.center : TextAlign.start,
                          style: theme.textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: diPertinRoxo,
                                letterSpacing: -0.5,
                              ) ??
                              TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.w800,
                                color: diPertinRoxo,
                                letterSpacing: -0.5,
                              ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          "Taxas por cidade, fretes e gateways de pagamento — tudo num só lugar.",
                          textAlign: narrow ? TextAlign.center : TextAlign.start,
                          style: const TextStyle(
                            color: PainelAdminTheme.textoSecundario,
                            fontSize: 15,
                            height: 1.4,
                          ),
                        ),
                      ],
                    );
                    final acao = Align(
                      alignment: narrow
                          ? Alignment.center
                          : Alignment.topRight,
                      child: _buildAcoesContextuaisTopo(),
                    );
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(28, 28, 28, 0),
                      child: narrow
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                tituloCol,
                                const SizedBox(height: 16),
                                acao,
                              ],
                            )
                          : Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(child: tituloCol),
                                const SizedBox(width: 24),
                                Flexible(child: acao),
                              ],
                            ),
                    );
                  },
                ),
                const SizedBox(height: 8),
                TabBar(
                  controller: _tabController,
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  labelColor: diPertinRoxo,
                  unselectedLabelColor: PainelAdminTheme.textoSecundario,
                  indicatorColor: diPertinLaranja,
                  indicatorWeight: 3,
                  labelStyle: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                  unselectedLabelStyle: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                  tabs: const [
                    Tab(
                      icon: Icon(Icons.storefront_rounded),
                      height: 72,
                      text: "Comissões da Plataforma",
                    ),
                    Tab(
                      icon: Icon(Icons.two_wheeler_rounded),
                      height: 72,
                      text: "Desconto do Entregadores",
                    ),
                    Tab(
                      icon: Icon(Icons.route_rounded),
                      height: 72,
                      text: "Tabela de fretes",
                    ),
                    Tab(
                      icon: Icon(Icons.credit_card_rounded),
                      height: 72,
                      text: "Pagamentos",
                    ),
                  ],
                ),
                Divider(height: 1, color: Colors.grey.shade200),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildListaPlanos('lojista'),
                _buildListaPlanos('entregador'),
                _buildListaFretes(),
                _buildGatewaysPagamento(),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: const BotaoSuporteFlutuante(),
    );
  }
}

/// Cartão de gateway com controllers estáveis (evita perder texto a cada rebuild).
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
          color: isAtivo ? widget.laranja : Colors.grey.shade200,
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
