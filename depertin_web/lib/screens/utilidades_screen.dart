import 'package:depertin_web/services/cidades_brasil_service.dart';
import 'package:depertin_web/widgets/cidade_atendida_picker.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_picker/file_picker.dart';

import '../utils/firestore_web_safe.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'dart:typed_data';

class UtilidadesScreen extends StatefulWidget {
  const UtilidadesScreen({super.key});

  @override
  State<UtilidadesScreen> createState() => _UtilidadesScreenState();
}

class _UtilidadesScreenState extends State<UtilidadesScreen> {
  final Color diPertinRoxo = const Color(0xFF6A1B9A);
  final Color diPertinLaranja = const Color(0xFFFF8F00);

  // Gradient reutilizável para o cabeçalho dos diálogos (idêntico ao AdminCity).
  static const LinearGradient _gradienteDialog = LinearGradient(
    colors: [Color(0xFF6A1B9A), Color(0xFF8E24AA), Color(0xFFAB47BC)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Cache das 5.570 cidades IBGE, carregadas uma vez no initState e usadas
  /// pelo [CidadeAtendidaPicker] em todos os pop-ups de anúncios.
  List<CidadePickerItem> _cidadesIBGE = const [];

  /// Dias de exibição inclusivos (início e fim contam no período).
  static int _diasContratados(DateTime inicio, DateTime fim) {
    final d = fim.difference(inicio).inDays + 1;
    return d < 1 ? 1 : d;
  }

  static double _valorTotalDoPeriodo({
    required double valorUnitario,
    required String modalidade,
    required int diasContratados,
  }) {
    if (valorUnitario <= 0) return 0;
    if (modalidade == 'mensal') {
      final meses = (diasContratados / 30).ceil().clamp(1, 9999);
      return valorUnitario * meses;
    }
    return valorUnitario * diasContratados;
  }

  String _fmtBrl(double v) {
    return NumberFormat.currency(locale: 'pt_BR', symbol: r'R$').format(v);
  }

  String _docIdReceitaUtilidade(String colecao, String anuncioId) {
    final c = colecao.replaceAll('/', '_');
    final a = anuncioId.replaceAll('/', '_');
    return 'util_${c}_$a';
  }
  bool _carregandoCidades = true;

  @override
  void initState() {
    super.initState();
    _carregarCidadesIBGE();
  }

  Future<void> _carregarCidadesIBGE() async {
    try {
      final todas = await CidadesBrasilService.todasCidades();
      if (!mounted) return;
      setState(() {
        _cidadesIBGE = todas
            .map((c) => CidadePickerItem(
                  label: '${c.nome} — ${c.ufSigla}',
                  nome: c.nome,
                  uf: c.ufSigla,
                  nomeNorm: _removerAcentos(
                    c.nome.toLowerCase().replaceAll(RegExp(r'\s+'), ' '),
                  ),
                  ufNorm: c.ufSigla.toLowerCase(),
                ))
            .toList()
          ..sort((a, b) => a.label.compareTo(b.label));
        _carregandoCidades = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _carregandoCidades = false);
    }
  }

  /// Converte a string salva no Firestore (ex.: "Toledo — PR" ou "toledo — pr")
  /// em um [CidadePickerItem] navegável, procurando casamento na lista IBGE.
  /// Retorna null se o campo estiver vazio ou não for encontrado.
  CidadePickerItem? _cidadePickerFromRaw(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return null;
    final partes = t.split(RegExp(r'\s*[—–\-]\s*'));
    if (partes.length < 2) return null;
    final nomeNorm = _removerAcentos(
      partes.first.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' '),
    );
    final ufNorm = partes.last.trim().toLowerCase();
    for (final c in _cidadesIBGE) {
      if (c.nomeNorm == nomeNorm && c.ufNorm == ufNorm) return c;
    }
    return null;
  }

  /// Widget padronizado para o campo "Cidade" dos pop-ups de anúncios.
  /// Sincroniza o valor selecionado com o [TextEditingController] existente
  /// (mantendo compat. com a lógica de salvamento que lê `.text.trim()`).
  Widget _campoCidadeAnuncio({
    required TextEditingController controller,
    required VoidCallback onChanged,
  }) {
    final selecionada = _cidadePickerFromRaw(controller.text);
    if (_carregandoCidades) {
      return InputDecorator(
        decoration: InputDecoration(
          labelText: 'Cidade (carregando...)',
          prefixIcon: const Icon(Icons.location_city_outlined),
          suffixIcon: const Padding(
            padding: EdgeInsets.all(12),
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        ),
        child: const SizedBox.shrink(),
      );
    }
    return CidadeAtendidaPicker(
      selecionada: selecionada,
      todas: _cidadesIBGE,
      label: 'Cidade',
      placeholder: 'Toque para selecionar',
      tituloDialog: 'Selecionar cidade do anúncio',
      descricaoDialog:
          '${_cidadesIBGE.length} cidades do Brasil. Deixe vazio para publicar em todo o país.',
      permitirLimpar: true,
      helperQuandoVazio: 'Em branco = anúncio exibido em todo o Brasil.',
      onSelecionada: (sel) {
        controller.text = sel.label;
        onChanged();
      },
      onLimpar: () {
        controller.text = '';
        onChanged();
      },
    );
  }

  /// Cabeçalho padrão (gradient roxo + ícone + título + subtítulo) usado em
  /// todos os diálogos de anúncios, inspirado no pop-up "Novo AdminCity".
  Widget _buildDialogHeader({
    required IconData icone,
    required String titulo,
    required String subtitulo,
    VoidCallback? onFechar,
  }) {
    return Container(
      decoration: const BoxDecoration(gradient: _gradienteDialog),
      padding: const EdgeInsets.fromLTRB(22, 20, 12, 20),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.18),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icone, color: Colors.white),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  titulo,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitulo,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    color: Colors.white.withOpacity(0.82),
                  ),
                ),
              ],
            ),
          ),
          if (onFechar != null)
            IconButton(
              icon: const Icon(Icons.close_rounded, color: Colors.white),
              tooltip: 'Fechar',
              onPressed: onFechar,
            ),
        ],
      ),
    );
  }

  /// Wrapper de [Dialog] com shell elegante idêntico ao "Novo AdminCity":
  /// borda arredondada, sombra, clipBehavior e largura fixa de 520 px.
  Widget _dialogElegante({
    required Widget header,
    required Widget corpo,
    required Widget rodape,
  }) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Container(
        width: 560,
        constraints: const BoxConstraints(maxHeight: 720),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.18),
              blurRadius: 30,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            header,
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 22, 24, 8),
                child: corpo,
              ),
            ),
            rodape,
          ],
        ),
      ),
    );
  }

  /// Rodapé padrão com botões Cancelar (à esquerda) e Ação primária (laranja).
  Widget _buildDialogRodape({
    required VoidCallback? onCancelar,
    required VoidCallback? onAcao,
    required String labelAcao,
    required IconData iconeAcao,
    bool isLoading = false,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 10, 24, 18),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: isLoading ? null : onCancelar,
            child: Text(
              'Cancelar',
              style: GoogleFonts.plusJakartaSans(
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade700,
              ),
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: isLoading ? null : onAcao,
            icon: isLoading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : Icon(iconeAcao, color: Colors.white, size: 18),
            label: Text(
              labelAcao,
              style: GoogleFonts.plusJakartaSans(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: diPertinLaranja,
              padding:
                  const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              elevation: 0,
            ),
          ),
        ],
      ),
    );
  }

  /// Normaliza o par "município — UF" mantendo o mesmo formato que o app
  /// espera em `LocationService.cidadeCampoCorrespondeUsuario`.
  /// Exemplos:
  ///  - `"Toledo — PR"` => `"toledo — pr"`
  ///  - `"Rondonópolis - MT"` => `"rondonopolis — mt"`
  ///  - `"Toledo"` (sem UF) => `"toledo"` (fallback, mas salva sem UF —
  ///    caso raro pois o campo exige seleção do autocomplete IBGE).
  String _normalizarCidade(String? raw) {
    if (raw == null) return '';
    final t = raw.trim();
    if (t.isEmpty) return '';
    final partes = t.split(RegExp(r'\s*[—–\-]\s*'));
    final nome = partes.isNotEmpty ? partes.first.trim() : t;
    final nomeNorm = _removerAcentos(
      nome.toLowerCase().replaceAll(RegExp(r'\s+'), ' '),
    );
    if (partes.length >= 2) {
      final uf = partes.last.trim();
      if (uf.length == 2 && RegExp(r'^[a-zA-Z]{2}$').hasMatch(uf)) {
        return '$nomeNorm — ${uf.toLowerCase()}';
      }
    }
    return nomeNorm;
  }

  /// Remove acentos para bater com `LocationService.normalizar` do app
  /// (que usa o mesmo padrão de normalização).
  String _removerAcentos(String s) {
    const com = 'áàâãäéèêëíìîïóòôõöúùûüçñÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇÑ';
    const sem = 'aaaaaeeeeiiiiooooouuuucnAAAAAEEEEIIIIOOOOOUUUUCN';
    final buf = StringBuffer();
    for (final ch in s.split('')) {
      final i = com.indexOf(ch);
      buf.write(i >= 0 ? sem[i] : ch);
    }
    return buf.toString();
  }

  /// Valida se o campo cidade está em formato válido para salvar um anúncio.
  /// Regra:
  /// - Vazio → OK (anúncio global)
  /// - Com "Município — UF" (ex.: "Toledo — PR") → OK
  /// - Qualquer outra coisa (texto digitado sem selecionar do autocomplete
  ///   IBGE) → inválido, para evitar que o app mostre o anúncio em várias
  ///   cidades homônimas pelo Brasil.
  bool _cidadeAnuncioValida(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return true;
    final partes = t.split(RegExp(r'\s*[—–\-]\s*'));
    if (partes.length < 2) return false;
    final uf = partes.last.trim();
    return uf.length == 2 && RegExp(r'^[a-zA-Z]{2}$').hasMatch(uf);
  }

  void _alertaCidadeInvalida(BuildContext ctx) {
    ScaffoldMessenger.of(ctx).showSnackBar(
      const SnackBar(
        backgroundColor: Colors.red,
        content: Text(
          'Selecione a cidade pela lista do autocomplete (ex.: "Toledo — PR"). '
          'Para anúncio em todo o Brasil, deixe o campo em branco.',
        ),
      ),
    );
  }

  /// Faz upload do arquivo no Storage e retorna a URL pública.
  Future<String> _uploadImagemUtilidade(Uint8List bytes) async {
    final ref = FirebaseStorage.instance.ref().child(
      'utilidades/${DateTime.now().millisecondsSinceEpoch}.jpg',
    );
    await ref.putData(bytes);
    return ref.getDownloadURL();
  }

  /// Widget reutilizável para seleção de foto nos dialogs de criar/editar.
  /// Mostra preview da imagem atual (bytes novos OU URL existente).
  Widget _buildCampoFotoUtilidade({
    required Uint8List? imagemBytes,
    required String? imagemUrlAtual,
    required VoidCallback onEscolher,
    VoidCallback? onRemover,
  }) {
    final temNova = imagemBytes != null;
    final temExistente =
        imagemUrlAtual != null && imagemUrlAtual.trim().isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(),
        const Text(
          "Foto (opcional):",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        InkWell(
          onTap: onEscolher,
          child: Container(
            height: 150,
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.grey),
            ),
            child: temNova
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.memory(imagemBytes, fit: BoxFit.cover),
                  )
                : temExistente
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.network(imagemUrlAtual,
                            fit: BoxFit.cover),
                      )
                    : const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add_a_photo,
                              size: 40, color: Colors.grey),
                          SizedBox(height: 5),
                          Text("Clique para anexar foto",
                              style: TextStyle(color: Colors.grey)),
                        ],
                      ),
          ),
        ),
        if ((temNova || temExistente) && onRemover != null)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: onRemover,
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              label: const Text('Remover foto',
                  style: TextStyle(color: Colors.red)),
            ),
          ),
      ],
    );
  }

  // --- FUNÇÕES DE AÇÃO RÁPIDA ---

  Future<void> _toggleAtivo(String colecao, String id, bool estadoAtual) async {
    await FirebaseFirestore.instance.collection(colecao).doc(id).update({
      'ativo': !estadoAtual,
    });
  }

  Future<void> _renovarVaga(String id, Timestamp? vencimentoAtual) async {
    DateTime dataBase = vencimentoAtual?.toDate() ?? DateTime.now();
    if (dataBase.isBefore(DateTime.now())) dataBase = DateTime.now();
    DateTime novaData = dataBase.add(const Duration(days: 7));
    await FirebaseFirestore.instance.collection('vagas').doc(id).update({
      'data_vencimento': Timestamp.fromDate(novaData),
      'ativo': true,
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Vaga renovada por +7 dias!'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Future<void> _renovarPremium(String id, Timestamp? vencimentoAtual) async {
    DateTime dataBase = vencimentoAtual?.toDate() ?? DateTime.now();
    if (dataBase.isBefore(DateTime.now())) dataBase = DateTime.now();
    final novaData = dataBase.add(const Duration(days: 30));
    final ts = Timestamp.fromDate(novaData);
    await FirebaseFirestore.instance.collection('telefones_premium').doc(id).update({
      'data_vencimento': ts,
      'data_fim': ts,
      'ativo': true,
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Premium renovado por +30 dias!'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Future<void> _renovarAchados(String id, Timestamp? vencimentoAtual) async {
    DateTime dataBase = vencimentoAtual?.toDate() ?? DateTime.now();
    if (dataBase.isBefore(DateTime.now())) dataBase = DateTime.now();
    DateTime novaData = dataBase.add(const Duration(days: 3));
    await FirebaseFirestore.instance.collection('achados').doc(id).update({
      'data_vencimento': Timestamp.fromDate(novaData),
      'ativo': true,
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Achado renovado por +3 dias!'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  void _configurarEvento(String id, Map<String, dynamic> dados) {
    TextEditingController donoC = TextEditingController(
      text: dados['nome_dono'] ?? '',
    );
    TextEditingController valorC = TextEditingController(
      text: (dados['valor_diario'] ?? '').toString(),
    );
    DateTime inicio = dados['data_inicio'] != null
        ? (dados['data_inicio'] as Timestamp).toDate()
        : DateTime.now();
    DateTime fim = dados['data_fim'] != null
        ? (dados['data_fim'] as Timestamp).toDate()
        : DateTime.now().add(const Duration(days: 7));

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(
            "Configurar Evento",
            style: TextStyle(color: diPertinRoxo, fontWeight: FontWeight.bold),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: donoC,
                  decoration: const InputDecoration(
                    labelText: "Contratante",
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 15),
                TextField(
                  controller: valorC,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: "Valor diário (R\$)",
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          DateTime? p = await showDatePicker(
                            context: context,
                            initialDate: inicio,
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2030),
                          );
                          if (p != null) setState(() => inicio = p);
                        },
                        icon: const Icon(Icons.calendar_today, size: 16),
                        label: Text("Início: ${inicio.day}/${inicio.month}"),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          DateTime? p = await showDatePicker(
                            context: context,
                            initialDate: fim,
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2030),
                          );
                          if (p != null) setState(() => fim = p);
                        },
                        icon: const Icon(Icons.event_available, size: 16),
                        label: Text("Fim: ${fim.day}/${fim.month}"),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancelar"),
            ),
            ElevatedButton(
              onPressed: () async {
                double valorDiario =
                    double.tryParse(valorC.text.replaceAll(',', '.')) ?? 0.0;
                int dias = fim.difference(inicio).inDays;
                if (dias <= 0) dias = 1; // Pelo menos 1 dia

                // 1. Atualiza o evento no app
                await FirebaseFirestore.instance
                    .collection('eventos')
                    .doc(id)
                    .update({
                      'nome_dono': donoC.text.trim(),
                      'valor_diario': valorDiario,
                      'data_inicio': Timestamp.fromDate(inicio),
                      'data_fim': Timestamp.fromDate(fim),
                      'gera_receita': valorDiario > 0,
                    });

                // 2. MÁGICA DO LIVRO CAIXA (Anota o faturamento do evento editado)
                if (valorDiario > 0) {
                  double valorTotalGerado = valorDiario * dias;
                  await FirebaseFirestore.instance
                      .collection('receitas_app')
                      .add({
                        'tipo_receita': 'Eventos',
                        'titulo_referencia':
                            dados['titulo'] ?? 'Evento Editado',
                        'nome_pagador': donoC.text.trim(),
                        'valor_total': valorTotalGerado,
                        'data_registro': FieldValue.serverTimestamp(),
                      });
                }

                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Configuração salva e registrada no caixa!',
                      ),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: diPertinLaranja,
                foregroundColor: Colors.white,
              ),
              child: const Text("Salvar"),
            ),
          ],
        ),
      ),
    );
  }

  // === NOVA FUNÇÃO: Deletar Post com Confirmação ===
  Future<void> _deletarPost(String colecao, String id) async {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          "Confirmar Exclusão",
          style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
        ),
        content: const Text(
          "Tem certeza que deseja apagar esta publicação permanentemente? Isso não pode ser desfeito.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancelar", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              // Deleta do Banco de Dados
              await FirebaseFirestore.instance
                  .collection(colecao)
                  .doc(id)
                  .delete();

              if (ctx.mounted) {
                Navigator.pop(ctx); // Fecha o Pop-up
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Publicação apagada com sucesso!'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            child: const Text("Sim, Apagar"),
          ),
        ],
      ),
    );
  }

  Widget _buildSecaoFinanceira({
    required TextEditingController valorC,
    required String modalidade,
    required DateTime dtInicio,
    required DateTime dtFim,
    required ValueChanged<String> onModalidade,
    required ValueChanged<DateTime> onInicio,
    required ValueChanged<DateTime> onFim,
    VoidCallback? onValorChanged,
  }) {
    String fmt(DateTime d) =>
        '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
    final dias = _diasContratados(dtInicio, dtFim);
    final unit = double.tryParse(valorC.text.replaceAll(',', '.')) ?? 0;
    final totalPrev =
        _valorTotalDoPeriodo(valorUnitario: unit, modalidade: modalidade, diasContratados: dias);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("Valor e Período", style: TextStyle(fontWeight: FontWeight.bold, color: diPertinRoxo, fontSize: 14)),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: valorC,
                onChanged: onValorChanged != null ? (_) => onValorChanged() : null,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: modalidade == 'diario' ? "Valor/dia (R\$)" : "Valor/mês (R\$)",
                  border: const OutlineInputBorder(),
                  prefixText: "R\$ ",
                ),
              ),
            ),
            const SizedBox(width: 10),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'diario', label: Text('Dia')),
                ButtonSegment(value: 'mensal', label: Text('Mês')),
              ],
              selected: {modalidade},
              onSelectionChanged: (v) {
                onModalidade(v.first);
                onValorChanged?.call();
              },
              style: SegmentedButton.styleFrom(
                selectedBackgroundColor: diPertinLaranja,
                selectedForegroundColor: Colors.white,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () async {
                  final p = await showDatePicker(context: context, initialDate: dtInicio, firstDate: DateTime(2024), lastDate: DateTime(2030));
                  if (p != null) {
                    onInicio(p);
                    onValorChanged?.call();
                  }
                },
                icon: const Icon(Icons.calendar_today, size: 16),
                label: Text("Início: ${fmt(dtInicio)}"),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () async {
                  final p = await showDatePicker(context: context, initialDate: dtFim, firstDate: DateTime(2024), lastDate: DateTime(2030));
                  if (p != null) {
                    onFim(p);
                    onValorChanged?.call();
                  }
                },
                icon: const Icon(Icons.event_available, size: 16),
                label: Text("Fim: ${fmt(dtFim)}"),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: diPertinRoxo.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: diPertinRoxo.withValues(alpha: 0.15)),
          ),
          child: unit <= 0
              ? Text(
                  'Informe o valor unitário para ver o total do período.',
                  style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700, height: 1.25),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Total no período',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade700,
                        letterSpacing: 0.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$dias ${dias == 1 ? 'dia' : 'dias'} × ${modalidade == 'mensal' ? 'valor mensal' : 'valor/dia'} → ${_fmtBrl(totalPrev)}',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: diPertinRoxo,
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }

  void _aplicarFinanceiro(Map<String, dynamic> upd, TextEditingController valorC, String modalidade, DateTime dtInicio, DateTime dtFim) {
    final val = double.tryParse(valorC.text.replaceAll(',', '.')) ?? 0;
    if (val <= 0) return;
    final dias = _diasContratados(dtInicio, dtFim);
    final total = _valorTotalDoPeriodo(valorUnitario: val, modalidade: modalidade, diasContratados: dias);
    if (modalidade == 'mensal') {
      upd['valor_mensal'] = val;
    } else {
      upd['valor_diario'] = val;
    }
    upd['modalidade_valor'] = modalidade;
    upd['data_inicio'] = Timestamp.fromDate(dtInicio);
    upd['data_fim'] = Timestamp.fromDate(dtFim);
    upd['data_vencimento'] = Timestamp.fromDate(dtFim);
    upd['valor_total'] = total;
    upd['qtd_dias_contratados'] = dias;
    upd['gera_receita'] = true;
  }

  /// Espelha uma linha no extrato com ID estável: ao reeditar o anúncio, substitui
  /// o valor (sem duplicar no Livro Caixa — KPI usa o doc do anúncio).
  Future<void> _sincronizarReceitaUtilidade({
    required String colecaoFirestore,
    required String anuncioDocId,
    required TextEditingController valorC,
    required String modalidade,
    required DateTime dtInicio,
    required DateTime dtFim,
    required String tipoReceita,
    required String titulo,
    required String pagador,
  }) async {
    final val = double.tryParse(valorC.text.replaceAll(',', '.')) ?? 0;
    if (val <= 0) return;
    final dias = _diasContratados(dtInicio, dtFim);
    final total =
        _valorTotalDoPeriodo(valorUnitario: val, modalidade: modalidade, diasContratados: dias);
    final rid = _docIdReceitaUtilidade(colecaoFirestore, anuncioDocId);
    await FirebaseFirestore.instance.collection('receitas_app').doc(rid).set({
      'tipo_receita': tipoReceita,
      'titulo_referencia': titulo,
      'nome_pagador': pagador,
      'valor_total': total,
      'valor_unitario': val,
      'modalidade_valor': modalidade,
      'data_inicio': Timestamp.fromDate(dtInicio),
      'data_fim': Timestamp.fromDate(dtFim),
      'qtd_dias': dias,
      'utilidade_colecao': colecaoFirestore,
      'utilidade_anuncio_id': anuncioDocId,
      'livro_caixa_manual': false,
      'data_registro': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  void _editarVaga(String id, Map<String, dynamic> dados) {
    final cargoC = TextEditingController(text: dados['cargo'] ?? '');
    final empresaC = TextEditingController(text: dados['empresa'] ?? '');
    final cidadeC = TextEditingController(text: dados['cidade'] ?? '');
    final descC = TextEditingController(text: dados['descricao'] ?? '');
    final contatoC = TextEditingController(text: dados['contato'] ?? '');
    final emailC = TextEditingController(text: dados['email'] ?? '');
    final valorC = TextEditingController(text: (dados['valor_diario'] ?? dados['valor_mensal'] ?? '').toString());
    String modalidade = dados['modalidade_valor']?.toString() ?? 'diario';
    DateTime dtInicio = dados['data_inicio'] != null ? (dados['data_inicio'] as Timestamp).toDate() : DateTime.now();
    DateTime dtFim = dados['data_fim'] != null ? (dados['data_fim'] as Timestamp).toDate() : (dados['data_vencimento'] != null ? (dados['data_vencimento'] as Timestamp).toDate() : DateTime.now().add(const Duration(days: 7)));
    Uint8List? imagemBytes;
    String? imagemUrlAtual = dados['imagem_url']?.toString();
    bool removerImagem = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDlg) {
          Future<void> escolherFoto() async {
            final result = await FilePicker.platform.pickFiles(type: FileType.image);
            if (result != null && result.files.first.bytes != null) {
              setDlg(() {
                imagemBytes = result.files.first.bytes;
                removerImagem = false;
              });
            }
          }

          Future<void> salvar() async {
            final cidadeRaw = cidadeC.text.trim();
            if (!_cidadeAnuncioValida(cidadeRaw)) {
              _alertaCidadeInvalida(context);
              return;
            }
            final upd = <String, dynamic>{
              'cargo': cargoC.text.trim(),
              'empresa': empresaC.text.trim(),
              'cidade': cidadeRaw,
              'cidade_normalizada': _normalizarCidade(cidadeRaw),
              'descricao': descC.text.trim(),
              'contato': contatoC.text.trim(),
            };
            if (emailC.text.trim().isNotEmpty) {
              upd['email'] = emailC.text.trim();
            }
            if (imagemBytes != null) {
              upd['imagem_url'] =
                  await _uploadImagemUtilidade(imagemBytes!);
            } else if (removerImagem) {
              upd['imagem_url'] = '';
            }
            _aplicarFinanceiro(upd, valorC, modalidade, dtInicio, dtFim);
            await FirebaseFirestore.instance
                .collection('vagas')
                .doc(id)
                .update(upd);
            await _sincronizarReceitaUtilidade(
              colecaoFirestore: 'vagas',
              anuncioDocId: id,
              valorC: valorC,
              modalidade: modalidade,
              dtInicio: dtInicio,
              dtFim: dtFim,
              tipoReceita: 'Vagas',
              titulo: cargoC.text,
              pagador: dados['nome_dono']?.toString() ?? '',
            );
            if (context.mounted) {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('Vaga atualizada!'),
                backgroundColor: Colors.green,
              ));
            }
          }

          return _dialogElegante(
            header: _buildDialogHeader(
              icone: Icons.work_outline_rounded,
              titulo: 'Editar Vaga',
              subtitulo: 'Atualize os dados da vaga publicada.',
            ),
            rodape: _buildDialogRodape(
              onCancelar: () => Navigator.pop(context),
              onAcao: salvar,
              labelAcao: 'Salvar alterações',
              iconeAcao: Icons.save_rounded,
            ),
            corpo: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(controller: cargoC, decoration: const InputDecoration(labelText: "Cargo da Vaga", border: OutlineInputBorder())),
                const SizedBox(height: 12),
                TextField(controller: empresaC, decoration: const InputDecoration(labelText: "Nome da Empresa", border: OutlineInputBorder())),
                const SizedBox(height: 12),
                _campoCidadeAnuncio(
                  controller: cidadeC,
                  onChanged: () => setDlg(() {}),
                ),
                const SizedBox(height: 12),
                TextField(controller: descC, maxLines: 3, decoration: const InputDecoration(labelText: "Descrição Completa", border: OutlineInputBorder())),
                const SizedBox(height: 12),
                TextField(controller: contatoC, decoration: const InputDecoration(labelText: "Telefone / Contato", border: OutlineInputBorder())),
                const SizedBox(height: 12),
                TextField(controller: emailC, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: "E-mail", prefixIcon: Icon(Icons.email_outlined), border: OutlineInputBorder())),
                const SizedBox(height: 12),
                _buildCampoFotoUtilidade(
                  imagemBytes: imagemBytes,
                  imagemUrlAtual: removerImagem ? null : imagemUrlAtual,
                  onEscolher: escolherFoto,
                  onRemover: () => setDlg(() {
                    imagemBytes = null;
                    imagemUrlAtual = null;
                    removerImagem = true;
                  }),
                ),
                const Divider(height: 24),
                _buildSecaoFinanceira(
                  valorC: valorC,
                  modalidade: modalidade,
                  dtInicio: dtInicio,
                  dtFim: dtFim,
                  onModalidade: (v) => setDlg(() => modalidade = v),
                  onInicio: (d) => setDlg(() => dtInicio = d),
                  onFim: (d) => setDlg(() => dtFim = d),
                  onValorChanged: () => setDlg(() {}),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _editarDestaque(String id, Map<String, dynamic> dados) {
    final tituloC = TextEditingController(text: dados['titulo'] ?? '');
    final categoriaC = TextEditingController(text: dados['categoria'] ?? '');
    final cidadeC = TextEditingController(text: dados['cidade'] ?? '');
    final telefoneC = TextEditingController(text: dados['telefone'] ?? '');
    final emailC = TextEditingController(text: dados['email'] ?? '');
    final valorC = TextEditingController(
        text: (dados['valor_diario'] ?? dados['valor_mensal'] ?? '').toString());
    String modalidade = dados['modalidade_valor']?.toString() ?? 'diario';
    DateTime dtInicio = dados['data_inicio'] != null
        ? (dados['data_inicio'] as Timestamp).toDate()
        : DateTime.now();
    DateTime dtFim = dados['data_fim'] != null
        ? (dados['data_fim'] as Timestamp).toDate()
        : DateTime.now().add(const Duration(days: 30));
    Uint8List? imagemBytes;
    String? imagemUrlAtual = dados['imagem_url']?.toString();
    bool removerImagem = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDlg) {
          Future<void> escolherFoto() async {
            final result = await FilePicker.platform.pickFiles(type: FileType.image);
            if (result != null && result.files.first.bytes != null) {
              setDlg(() {
                imagemBytes = result.files.first.bytes;
                removerImagem = false;
              });
            }
          }

          Future<void> salvar() async {
            final cidadeRaw = cidadeC.text.trim();
            if (!_cidadeAnuncioValida(cidadeRaw)) {
              _alertaCidadeInvalida(context);
              return;
            }
            final upd = <String, dynamic>{
              'titulo': tituloC.text.trim(),
              'categoria': categoriaC.text.trim(),
              'cidade': cidadeRaw,
              'cidade_normalizada': _normalizarCidade(cidadeRaw),
              'telefone': telefoneC.text.trim(),
            };
            if (emailC.text.trim().isNotEmpty) {
              upd['email'] = emailC.text.trim();
            }
            if (imagemBytes != null) {
              upd['imagem_url'] =
                  await _uploadImagemUtilidade(imagemBytes!);
            } else if (removerImagem) {
              upd['imagem_url'] = '';
            }
            _aplicarFinanceiro(upd, valorC, modalidade, dtInicio, dtFim);
            await FirebaseFirestore.instance
                .collection('servicos_destaque')
                .doc(id)
                .update(upd);
            await _sincronizarReceitaUtilidade(
              colecaoFirestore: 'servicos_destaque',
              anuncioDocId: id,
              valorC: valorC,
              modalidade: modalidade,
              dtInicio: dtInicio,
              dtFim: dtFim,
              tipoReceita: 'Destaques',
              titulo: tituloC.text,
              pagador: dados['nome_dono']?.toString() ?? '',
            );
            if (context.mounted) {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('Destaque atualizado!'),
                backgroundColor: Colors.green,
              ));
            }
          }

          return _dialogElegante(
            header: _buildDialogHeader(
              icone: Icons.star_rounded,
              titulo: 'Editar Destaque',
              subtitulo: 'Atualize os dados do serviço destacado.',
            ),
            rodape: _buildDialogRodape(
              onCancelar: () => Navigator.pop(context),
              onAcao: salvar,
              labelAcao: 'Salvar alterações',
              iconeAcao: Icons.save_rounded,
            ),
            corpo: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(controller: tituloC, decoration: const InputDecoration(labelText: "Título", border: OutlineInputBorder())),
                const SizedBox(height: 12),
                TextField(controller: categoriaC, decoration: const InputDecoration(labelText: "Categoria Profissional", border: OutlineInputBorder())),
                const SizedBox(height: 12),
                _campoCidadeAnuncio(
                  controller: cidadeC,
                  onChanged: () => setDlg(() {}),
                ),
                const SizedBox(height: 12),
                TextField(controller: telefoneC, decoration: const InputDecoration(labelText: "Telefone / Contato", border: OutlineInputBorder())),
                const SizedBox(height: 12),
                TextField(controller: emailC, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: "E-mail", prefixIcon: Icon(Icons.email_outlined), border: OutlineInputBorder())),
                const SizedBox(height: 12),
                _buildCampoFotoUtilidade(
                  imagemBytes: imagemBytes,
                  imagemUrlAtual: removerImagem ? null : imagemUrlAtual,
                  onEscolher: escolherFoto,
                  onRemover: () => setDlg(() {
                    imagemBytes = null;
                    imagemUrlAtual = null;
                    removerImagem = true;
                  }),
                ),
                const Divider(height: 24),
                _buildSecaoFinanceira(
                  valorC: valorC,
                  modalidade: modalidade,
                  dtInicio: dtInicio,
                  dtFim: dtFim,
                  onModalidade: (v) => setDlg(() => modalidade = v),
                  onInicio: (d) => setDlg(() => dtInicio = d),
                  onFim: (d) => setDlg(() => dtFim = d),
                  onValorChanged: () => setDlg(() {}),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _configurarPremium(String id, Map<String, dynamic> dados) {
    _configurarAnuncioFinanceiro(
      colecao: 'telefones_premium',
      id: id,
      dados: dados,
      tituloDialogo: 'Configurar Premium',
    );
  }

  void _configurarAnuncioFinanceiro({
    required String colecao,
    required String id,
    required Map<String, dynamic> dados,
    required String tituloDialogo,
  }) {
    TextEditingController donoC = TextEditingController(
      text: dados['nome_dono']?.toString() ?? '',
    );
    TextEditingController valorC = TextEditingController(
      text: (dados['valor_diario'] ?? dados['valor_mensal'] ?? '').toString(),
    );
    DateTime inicio =
        _campoFirestoreParaDateTime(dados['data_inicio']) ?? DateTime.now();
    final tsFim = _tsVencimentoAnuncio(dados);
    DateTime fim = tsFim?.toDate() ?? DateTime.now().add(const Duration(days: 30));
    bool ativo = dados['ativo'] == true;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(
            tituloDialogo,
            style: TextStyle(color: diPertinRoxo, fontWeight: FontWeight.bold),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: donoC,
                  decoration: const InputDecoration(
                    labelText: 'Contratante / pagador',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 15),
                TextField(
                  controller: valorC,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Valor diário (R\$)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Anúncio ativo no app'),
                  value: ativo,
                  activeThumbColor: Colors.green,
                  onChanged: (v) => setState(() => ativo = v),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final p = await showDatePicker(
                            context: context,
                            initialDate: inicio,
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2035),
                          );
                          if (p != null) setState(() => inicio = p);
                        },
                        icon: const Icon(Icons.calendar_today, size: 16),
                        label: Text('Início: ${inicio.day}/${inicio.month}'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final p = await showDatePicker(
                            context: context,
                            initialDate: fim,
                            firstDate: inicio,
                            lastDate: DateTime(2035),
                          );
                          if (p != null) setState(() => fim = p);
                        },
                        icon: const Icon(Icons.event_available, size: 16),
                        label: Text('Fim: ${fim.day}/${fim.month}'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () async {
                final valorDiario =
                    double.tryParse(valorC.text.replaceAll(',', '.')) ?? 0.0;
                var dias = fim.difference(inicio).inDays;
                if (dias <= 0) dias = 1;
                final tsFimNovo = Timestamp.fromDate(fim);
                final upd = <String, dynamic>{
                  'nome_dono': donoC.text.trim(),
                  'data_inicio': Timestamp.fromDate(inicio),
                  'data_fim': tsFimNovo,
                  'data_vencimento': tsFimNovo,
                  'ativo': ativo,
                  'gera_receita': valorDiario > 0,
                };
                if (valorDiario > 0) {
                  upd['valor_diario'] = valorDiario;
                  upd['valor_total'] = valorDiario * dias;
                }
                await FirebaseFirestore.instance
                    .collection(colecao)
                    .doc(id)
                    .update(upd);
                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Configuração salva!'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: diPertinLaranja,
                foregroundColor: Colors.white,
              ),
              child: const Text('Salvar'),
            ),
          ],
        ),
      ),
    );
  }

  void _editarPremium(String id, Map<String, dynamic> dados) {
    final tituloC = TextEditingController(text: dados['titulo'] ?? '');
    final telefoneC = TextEditingController(text: dados['telefone'] ?? '');
    final cidadeC = TextEditingController(text: dados['cidade'] ?? '');
    final emailC = TextEditingController(text: dados['email'] ?? '');
    final valorC = TextEditingController(text: (dados['valor_diario'] ?? dados['valor_mensal'] ?? '').toString());
    String modalidade = dados['modalidade_valor']?.toString() ?? 'diario';
    DateTime dtInicio =
        _campoFirestoreParaDateTime(dados['data_inicio']) ?? DateTime.now();
    final tsFim = _tsVencimentoAnuncio(dados);
    DateTime dtFim = tsFim?.toDate() ?? DateTime.now().add(const Duration(days: 30));
    bool ativo = dados['ativo'] == true;
    Uint8List? imagemBytes;
    String? imagemUrlAtual = dados['imagem_url']?.toString();
    bool removerImagem = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDlg) {
          Future<void> escolherFoto() async {
            final result = await FilePicker.platform.pickFiles(type: FileType.image);
            if (result != null && result.files.first.bytes != null) {
              setDlg(() {
                imagemBytes = result.files.first.bytes;
                removerImagem = false;
              });
            }
          }

          Future<void> salvar() async {
            final cidadeRaw = cidadeC.text.trim();
            if (!_cidadeAnuncioValida(cidadeRaw)) {
              _alertaCidadeInvalida(context);
              return;
            }
            final upd = <String, dynamic>{
              'titulo': tituloC.text.trim(),
              'telefone': telefoneC.text.trim(),
              'cidade': cidadeRaw,
              'cidade_normalizada': _normalizarCidade(cidadeRaw),
            };
            if (emailC.text.trim().isNotEmpty) {
              upd['email'] = emailC.text.trim();
            }
            if (imagemBytes != null) {
              upd['imagem_url'] =
                  await _uploadImagemUtilidade(imagemBytes!);
            } else if (removerImagem) {
              upd['imagem_url'] = '';
            }
            _aplicarFinanceiro(upd, valorC, modalidade, dtInicio, dtFim);
            upd['ativo'] = ativo;
            upd['data_inicio'] = Timestamp.fromDate(dtInicio);
            upd['data_fim'] = Timestamp.fromDate(dtFim);
            upd['data_vencimento'] = Timestamp.fromDate(dtFim);
            await FirebaseFirestore.instance
                .collection('telefones_premium')
                .doc(id)
                .update(upd);
            await _sincronizarReceitaUtilidade(
              colecaoFirestore: 'telefones_premium',
              anuncioDocId: id,
              valorC: valorC,
              modalidade: modalidade,
              dtInicio: dtInicio,
              dtFim: dtFim,
              tipoReceita: 'Premium',
              titulo: tituloC.text,
              pagador: dados['nome_dono']?.toString() ?? '',
            );
            if (context.mounted) {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('Premium atualizado!'),
                backgroundColor: Colors.green,
              ));
            }
          }

          return _dialogElegante(
            header: _buildDialogHeader(
              icone: Icons.workspace_premium_rounded,
              titulo: 'Editar Premium',
              subtitulo: 'Atualize os dados do número premium.',
            ),
            rodape: _buildDialogRodape(
              onCancelar: () => Navigator.pop(context),
              onAcao: salvar,
              labelAcao: 'Salvar alterações',
              iconeAcao: Icons.save_rounded,
            ),
            corpo: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(controller: tituloC, decoration: const InputDecoration(labelText: "Título", border: OutlineInputBorder())),
                const SizedBox(height: 12),
                TextField(controller: telefoneC, decoration: const InputDecoration(labelText: "Telefone / WhatsApp", border: OutlineInputBorder())),
                const SizedBox(height: 12),
                _campoCidadeAnuncio(
                  controller: cidadeC,
                  onChanged: () => setDlg(() {}),
                ),
                const SizedBox(height: 12),
                TextField(controller: emailC, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: "E-mail", prefixIcon: Icon(Icons.email_outlined), border: OutlineInputBorder())),
                const SizedBox(height: 12),
                _buildCampoFotoUtilidade(
                  imagemBytes: imagemBytes,
                  imagemUrlAtual: removerImagem ? null : imagemUrlAtual,
                  onEscolher: escolherFoto,
                  onRemover: () => setDlg(() {
                    imagemBytes = null;
                    imagemUrlAtual = null;
                    removerImagem = true;
                  }),
                ),
                const Divider(height: 24),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Anúncio ativo no app'),
                  subtitle: const Text(
                    'Desative para ocultar do app sem apagar o registro.',
                  ),
                  value: ativo,
                  activeThumbColor: Colors.green,
                  onChanged: (v) => setDlg(() => ativo = v),
                ),
                const SizedBox(height: 8),
                _buildSecaoFinanceira(
                  valorC: valorC,
                  modalidade: modalidade,
                  dtInicio: dtInicio,
                  dtFim: dtFim,
                  onModalidade: (v) => setDlg(() => modalidade = v),
                  onInicio: (d) => setDlg(() => dtInicio = d),
                  onFim: (d) => setDlg(() => dtFim = d),
                  onValorChanged: () => setDlg(() {}),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _editarEvento(String id, Map<String, dynamic> dados) {
    final tituloC = TextEditingController(text: dados['titulo'] ?? '');
    final localC = TextEditingController(text: dados['local'] ?? '');
    final cidadeC = TextEditingController(text: dados['cidade'] ?? '');
    final dataEventoC = TextEditingController(text: dados['data_evento'] ?? '');
    final descC = TextEditingController(text: dados['descricao'] ?? '');
    final linkC = TextEditingController(text: dados['link_ingresso'] ?? '');
    final emailC = TextEditingController(text: dados['email'] ?? '');
    final valorC = TextEditingController(text: (dados['valor_diario'] ?? dados['valor_mensal'] ?? '').toString());
    String modalidade = dados['modalidade_valor']?.toString() ?? 'diario';
    DateTime dtInicio = dados['data_inicio'] != null ? (dados['data_inicio'] as Timestamp).toDate() : DateTime.now();
    DateTime dtFim = dados['data_fim'] != null ? (dados['data_fim'] as Timestamp).toDate() : DateTime.now().add(const Duration(days: 7));
    Uint8List? imagemBytes;
    String? imagemUrlAtual = dados['imagem_url']?.toString();
    bool removerImagem = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDlg) {
          Future<void> escolherFoto() async {
            final result = await FilePicker.platform.pickFiles(type: FileType.image);
            if (result != null && result.files.first.bytes != null) {
              setDlg(() {
                imagemBytes = result.files.first.bytes;
                removerImagem = false;
              });
            }
          }

          Future<void> salvar() async {
            final cidadeRaw = cidadeC.text.trim();
            if (!_cidadeAnuncioValida(cidadeRaw)) {
              _alertaCidadeInvalida(context);
              return;
            }
            final upd = <String, dynamic>{
              'titulo': tituloC.text.trim(),
              'local': localC.text.trim(),
              'cidade': cidadeRaw,
              'cidade_normalizada': _normalizarCidade(cidadeRaw),
              'data_evento': dataEventoC.text.trim(),
              'descricao': descC.text.trim(),
              'link_ingresso': linkC.text.trim(),
            };
            if (emailC.text.trim().isNotEmpty) {
              upd['email'] = emailC.text.trim();
            }
            if (imagemBytes != null) {
              upd['imagem_url'] =
                  await _uploadImagemUtilidade(imagemBytes!);
            } else if (removerImagem) {
              upd['imagem_url'] = '';
            }
            _aplicarFinanceiro(upd, valorC, modalidade, dtInicio, dtFim);
            await FirebaseFirestore.instance
                .collection('eventos')
                .doc(id)
                .update(upd);
            await _sincronizarReceitaUtilidade(
              colecaoFirestore: 'eventos',
              anuncioDocId: id,
              valorC: valorC,
              modalidade: modalidade,
              dtInicio: dtInicio,
              dtFim: dtFim,
              tipoReceita: 'Eventos',
              titulo: tituloC.text,
              pagador: dados['nome_dono']?.toString() ?? '',
            );
            if (context.mounted) {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('Evento atualizado!'),
                backgroundColor: Colors.green,
              ));
            }
          }

          return _dialogElegante(
            header: _buildDialogHeader(
              icone: Icons.celebration_rounded,
              titulo: 'Editar Evento',
              subtitulo: 'Atualize os dados do evento publicado.',
            ),
            rodape: _buildDialogRodape(
              onCancelar: () => Navigator.pop(context),
              onAcao: salvar,
              labelAcao: 'Salvar alterações',
              iconeAcao: Icons.save_rounded,
            ),
            corpo: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(controller: tituloC, decoration: const InputDecoration(labelText: "Título do Evento", border: OutlineInputBorder())),
                const SizedBox(height: 12),
                TextField(controller: localC, decoration: const InputDecoration(labelText: "Local", border: OutlineInputBorder())),
                const SizedBox(height: 12),
                _campoCidadeAnuncio(
                  controller: cidadeC,
                  onChanged: () => setDlg(() {}),
                ),
                const SizedBox(height: 12),
                TextField(controller: dataEventoC, decoration: const InputDecoration(labelText: "Data do Evento (Ex: 25/Dez às 20h)", border: OutlineInputBorder())),
                const SizedBox(height: 12),
                TextField(controller: descC, maxLines: 3, decoration: const InputDecoration(labelText: "Descrição Completa", border: OutlineInputBorder())),
                const SizedBox(height: 12),
                TextField(controller: linkC, decoration: const InputDecoration(labelText: "Link do Ingresso (Opcional)", border: OutlineInputBorder())),
                const SizedBox(height: 12),
                TextField(controller: emailC, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: "E-mail", prefixIcon: Icon(Icons.email_outlined), border: OutlineInputBorder())),
                const SizedBox(height: 12),
                _buildCampoFotoUtilidade(
                  imagemBytes: imagemBytes,
                  imagemUrlAtual: removerImagem ? null : imagemUrlAtual,
                  onEscolher: escolherFoto,
                  onRemover: () => setDlg(() {
                    imagemBytes = null;
                    imagemUrlAtual = null;
                    removerImagem = true;
                  }),
                ),
                const Divider(height: 24),
                _buildSecaoFinanceira(
                  valorC: valorC,
                  modalidade: modalidade,
                  dtInicio: dtInicio,
                  dtFim: dtFim,
                  onModalidade: (v) => setDlg(() => modalidade = v),
                  onInicio: (d) => setDlg(() => dtInicio = d),
                  onFim: (d) => setDlg(() => dtFim = d),
                  onValorChanged: () => setDlg(() {}),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _editarAchado(String id, Map<String, dynamic> dados) {
    final tituloC = TextEditingController(text: dados['titulo'] ?? '');
    final localC = TextEditingController(text: dados['local'] ?? '');
    final cidadeC = TextEditingController(text: dados['cidade'] ?? '');
    final descC = TextEditingController(text: dados['descricao'] ?? '');
    final contatoC = TextEditingController(text: dados['contato'] ?? '');
    final emailC = TextEditingController(text: dados['email'] ?? '');
    final valorC = TextEditingController(text: (dados['valor_diario'] ?? dados['valor_mensal'] ?? '').toString());
    bool isPerdido = (dados['tipo'] ?? 'perdido') == 'perdido';
    String modalidade = dados['modalidade_valor']?.toString() ?? 'diario';
    DateTime dtInicio = dados['data_inicio'] != null ? (dados['data_inicio'] as Timestamp).toDate() : DateTime.now();
    DateTime dtFim = dados['data_fim'] != null ? (dados['data_fim'] as Timestamp).toDate() : (dados['data_vencimento'] != null ? (dados['data_vencimento'] as Timestamp).toDate() : DateTime.now().add(const Duration(days: 3)));
    Uint8List? imagemBytes;
    String? imagemUrlAtual = dados['imagem_url']?.toString();
    bool removerImagem = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDlg) {
          Future<void> escolherFoto() async {
            final result = await FilePicker.platform.pickFiles(type: FileType.image);
            if (result != null && result.files.first.bytes != null) {
              setDlg(() {
                imagemBytes = result.files.first.bytes;
                removerImagem = false;
              });
            }
          }

          Future<void> salvar() async {
            final cidadeRaw = cidadeC.text.trim();
            if (!_cidadeAnuncioValida(cidadeRaw)) {
              _alertaCidadeInvalida(context);
              return;
            }
            final upd = <String, dynamic>{
              'titulo': tituloC.text.trim(),
              'tipo': isPerdido ? 'perdido' : 'encontrado',
              'local': localC.text.trim(),
              'cidade': cidadeRaw,
              'cidade_normalizada': _normalizarCidade(cidadeRaw),
              'descricao': descC.text.trim(),
              'contato': contatoC.text.trim(),
            };
            if (emailC.text.trim().isNotEmpty) {
              upd['email'] = emailC.text.trim();
            }
            if (imagemBytes != null) {
              upd['imagem_url'] =
                  await _uploadImagemUtilidade(imagemBytes!);
            } else if (removerImagem) {
              upd['imagem_url'] = '';
            }
            _aplicarFinanceiro(upd, valorC, modalidade, dtInicio, dtFim);
            await FirebaseFirestore.instance
                .collection('achados')
                .doc(id)
                .update(upd);
            await _sincronizarReceitaUtilidade(
              colecaoFirestore: 'achados',
              anuncioDocId: id,
              valorC: valorC,
              modalidade: modalidade,
              dtInicio: dtInicio,
              dtFim: dtFim,
              tipoReceita: 'Achados',
              titulo: tituloC.text,
              pagador: dados['nome_dono']?.toString() ?? '',
            );
            if (context.mounted) {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('Achado atualizado!'),
                backgroundColor: Colors.green,
              ));
            }
          }

          return _dialogElegante(
            header: _buildDialogHeader(
              icone: Icons.search_rounded,
              titulo: 'Editar Achado',
              subtitulo: 'Atualize os dados do item achado/perdido.',
            ),
            rodape: _buildDialogRodape(
              onCancelar: () => Navigator.pop(context),
              onAcao: salvar,
              labelAcao: 'Salvar alterações',
              iconeAcao: Icons.save_rounded,
            ),
            corpo: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(controller: tituloC, decoration: const InputDecoration(labelText: "Título", border: OutlineInputBorder())),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: RadioListTile(title: const Text("Perdido"), value: true, groupValue: isPerdido, onChanged: (v) => setDlg(() => isPerdido = v as bool))),
                  Expanded(child: RadioListTile(title: const Text("Achado"), value: false, groupValue: isPerdido, onChanged: (v) => setDlg(() => isPerdido = v as bool))),
                ]),
                const SizedBox(height: 12),
                TextField(controller: localC, decoration: const InputDecoration(labelText: "Local", border: OutlineInputBorder())),
                const SizedBox(height: 12),
                _campoCidadeAnuncio(
                  controller: cidadeC,
                  onChanged: () => setDlg(() {}),
                ),
                const SizedBox(height: 12),
                TextField(controller: descC, maxLines: 3, decoration: const InputDecoration(labelText: "Descrição", border: OutlineInputBorder())),
                const SizedBox(height: 12),
                TextField(controller: contatoC, decoration: const InputDecoration(labelText: "Telefone / Contato", border: OutlineInputBorder())),
                const SizedBox(height: 12),
                TextField(controller: emailC, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: "E-mail", prefixIcon: Icon(Icons.email_outlined), border: OutlineInputBorder())),
                const SizedBox(height: 12),
                _buildCampoFotoUtilidade(
                  imagemBytes: imagemBytes,
                  imagemUrlAtual: removerImagem ? null : imagemUrlAtual,
                  onEscolher: escolherFoto,
                  onRemover: () => setDlg(() {
                    imagemBytes = null;
                    imagemUrlAtual = null;
                    removerImagem = true;
                  }),
                ),
                const Divider(height: 24),
                _buildSecaoFinanceira(
                  valorC: valorC,
                  modalidade: modalidade,
                  dtInicio: dtInicio,
                  dtFim: dtFim,
                  onModalidade: (v) => setDlg(() => modalidade = v),
                  onInicio: (d) => setDlg(() => dtInicio = d),
                  onFim: (d) => setDlg(() => dtFim = d),
                  onValorChanged: () => setDlg(() {}),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  String _formatarData(Timestamp? ts) {
    if (ts == null) return 'N/A';
    DateTime d = ts.toDate();
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  DateTime? _campoFirestoreParaDateTime(dynamic raw) {
    if (raw == null) return null;
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    if (raw is int) {
      if (raw > 1000000000000) {
        return DateTime.fromMillisecondsSinceEpoch(raw);
      }
      return DateTime.fromMillisecondsSinceEpoch(raw * 1000);
    }
    if (raw is num) {
      final n = raw.toInt();
      if (n > 1000000000000) {
        return DateTime.fromMillisecondsSinceEpoch(n);
      }
      return DateTime.fromMillisecondsSinceEpoch(n * 1000);
    }
    if (raw is Map) {
      final sec = raw['_seconds'] ?? raw['seconds'];
      if (sec is num) {
        return DateTime.fromMillisecondsSinceEpoch(sec.toInt() * 1000);
      }
    }
    if (raw is String && raw.trim().isNotEmpty) {
      return DateTime.tryParse(raw.trim());
    }
    return null;
  }

  /// Premium usa [data_vencimento]; demais categorias usam [data_fim].
  Timestamp? _tsVencimentoAnuncio(
    Map<String, dynamic> dados, {
    String? campoPreferido,
  }) {
    if (campoPreferido != null) {
      final dt = _campoFirestoreParaDateTime(dados[campoPreferido]);
      if (dt != null) return Timestamp.fromDate(dt);
    }
    final dtFim = _campoFirestoreParaDateTime(dados['data_fim']);
    if (dtFim != null) return Timestamp.fromDate(dtFim);
    final dtVenc = _campoFirestoreParaDateTime(dados['data_vencimento']);
    if (dtVenc != null) return Timestamp.fromDate(dtVenc);
    return null;
  }

  // --- O PODEROSO POP-UP PARA CRIAR QUALQUER POST ---
  void _mostrarFormularioNovoPost() {
    String tipoSelecionado = 'Vagas';
    bool isPerdido = true; // Apenas para Achados

    // Controladores Genéricos
    TextEditingController tituloC = TextEditingController();
    TextEditingController empresaLocalC = TextEditingController();
    TextEditingController cidadeC = TextEditingController();
    TextEditingController descC = TextEditingController();
    TextEditingController contatoC = TextEditingController();
    TextEditingController emailC = TextEditingController();
    TextEditingController dataLinkC = TextEditingController();
    TextEditingController donoC = TextEditingController();
    TextEditingController valorC = TextEditingController();
    String modalidadeValor = 'diario';
    DateTime dataInicio = DateTime.now();
    DateTime dataFim = DateTime.now().add(const Duration(days: 30));

    Uint8List? imagemBytes;
    bool isLoading = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            // Função interna para escolher a foto
            Future<void> escolherFoto() async {
              FilePickerResult? result = await FilePicker.platform.pickFiles(
                type: FileType.image,
              );
              if (result != null) {
                setState(() => imagemBytes = result.files.first.bytes);
              }
            }

            // Função interna para Salvar tudo
            Future<void> salvarPost() async {
              if (tituloC.text.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text("O Título é obrigatório!"),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }
              // Garante que a cidade foi selecionada do autocomplete IBGE
              // (ou está vazia para anúncio global). Sem UF, o filtro do
              // app não consegue distinguir cidades homônimas.
              if (!_cidadeAnuncioValida(cidadeC.text)) {
                _alertaCidadeInvalida(context);
                return;
              }
              setState(() => isLoading = true);

              try {
                double valorCobrado =
                    double.tryParse(valorC.text.replaceAll(',', '.')) ?? 0.0;
                final qtdDias = _diasContratados(dataInicio, dataFim);

                String urlImagem = '';
                if (imagemBytes != null) {
                  final ref = FirebaseStorage.instance.ref().child(
                    'utilidades/${DateTime.now().millisecondsSinceEpoch}.jpg',
                  );
                  await ref.putData(imagemBytes!);
                  urlImagem = await ref.getDownloadURL();
                }

                Map<String, dynamic> dados = {
                  'ativo': true,
                  'data_criacao': FieldValue.serverTimestamp(),
                  // Garante que todo anúncio tenha janela de publicação,
                  // mesmo quando gratuito (exigido pelo filtro do app).
                  'data_inicio': Timestamp.fromDate(dataInicio),
                  'data_fim': Timestamp.fromDate(dataFim),
                };

                if (valorCobrado > 0) {
                  dados['nome_dono'] = donoC.text.trim();
                  dados['gera_receita'] = true;
                  dados['modalidade_valor'] = modalidadeValor;
                  final valorTotalGerado = _valorTotalDoPeriodo(
                    valorUnitario: valorCobrado,
                    modalidade: modalidadeValor,
                    diasContratados: qtdDias,
                  );
                  if (modalidadeValor == 'mensal') {
                    dados['valor_mensal'] = valorCobrado;
                  } else {
                    dados['valor_diario'] = valorCobrado;
                  }
                  dados['valor_total'] = valorTotalGerado;
                  dados['qtd_dias_contratados'] = qtdDias;
                }

                // 3. Molda os dados de acordo com a categoria (Igual estava antes)
                if (emailC.text.trim().isNotEmpty) {
                  dados['email'] = emailC.text.trim();
                }

                final cidadeRaw = cidadeC.text.trim();
                final cidadeNorm = _normalizarCidade(cidadeRaw);

                DocumentReference<Map<String, dynamic>>? refAnuncio;

                if (tipoSelecionado == 'Vagas') {
                  dados.addAll({
                    'cargo': tituloC.text,
                    'empresa': empresaLocalC.text,
                    'cidade': cidadeRaw,
                    'cidade_normalizada': cidadeNorm,
                    'descricao': descC.text,
                    'contato': contatoC.text,
                    'imagem_url': urlImagem,
                    'data_vencimento': Timestamp.fromDate(
                      DateTime.now().add(const Duration(days: 7)),
                    ),
                  });
                  refAnuncio = await FirebaseFirestore.instance
                      .collection('vagas')
                      .add(dados);
                } else if (tipoSelecionado == 'Eventos') {
                  dados.addAll({
                    'titulo': tituloC.text,
                    'local': empresaLocalC.text,
                    'cidade': cidadeRaw,
                    'cidade_normalizada': cidadeNorm,
                    'data_evento': dataLinkC.text,
                    'descricao': descC.text,
                    'link_ingresso': contatoC.text,
                    'imagem_url': urlImagem,
                  });
                  dados['data_fim'] ??= Timestamp.fromDate(
                    DateTime.now().add(const Duration(days: 7)),
                  );
                  if (dados['gera_receita'] == null) {
                    dados['gera_receita'] = false;
                  }
                  refAnuncio = await FirebaseFirestore.instance
                      .collection('eventos')
                      .add(dados);
                } else if (tipoSelecionado == 'Achados') {
                  dados.addAll({
                    'titulo': tituloC.text,
                    'tipo': isPerdido ? 'perdido' : 'encontrado',
                    'local': empresaLocalC.text,
                    'cidade': cidadeRaw,
                    'cidade_normalizada': cidadeNorm,
                    'descricao': descC.text,
                    'contato': contatoC.text,
                    'imagem_url': urlImagem,
                    'resolvido': false,
                    'data_vencimento': Timestamp.fromDate(
                      DateTime.now().add(const Duration(days: 3)),
                    ),
                  });
                  refAnuncio = await FirebaseFirestore.instance
                      .collection('achados')
                      .add(dados);
                } else if (tipoSelecionado == 'Premium') {
                  dados.addAll({
                    'titulo': tituloC.text,
                    'telefone': contatoC.text,
                    'cidade': cidadeRaw,
                    'cidade_normalizada': cidadeNorm,
                    'imagem_url': urlImagem,
                    'tipo_contato': 'whatsapp',
                  });
                  dados['data_vencimento'] ??= Timestamp.fromDate(dataFim);
                  refAnuncio = await FirebaseFirestore.instance
                      .collection('telefones_premium')
                      .add(dados);
                } else if (tipoSelecionado == 'Destaques') {
                  dados.addAll({
                    'titulo': tituloC.text,
                    'categoria': empresaLocalC.text,
                    'cidade': cidadeRaw,
                    'cidade_normalizada': cidadeNorm,
                    'telefone': contatoC.text,
                    'imagem_url': urlImagem,
                  });
                  refAnuncio = await FirebaseFirestore.instance
                      .collection('servicos_destaque')
                      .add(dados);
                }

                if (valorCobrado > 0 && refAnuncio != null) {
                  await _sincronizarReceitaUtilidade(
                    colecaoFirestore: refAnuncio.parent.id,
                    anuncioDocId: refAnuncio.id,
                    valorC: valorC,
                    modalidade: modalidadeValor,
                    dtInicio: dataInicio,
                    dtFim: dataFim,
                    tipoReceita: tipoSelecionado,
                    titulo: tituloC.text,
                    pagador: donoC.text.trim(),
                  );
                }

                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        "Publicado e registrado no caixa com sucesso!",
                      ),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text("Erro ao salvar: $e"),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            }

            String subtituloCategoria() {
              switch (tipoSelecionado) {
                case 'Vagas':
                  return 'Publique uma vaga de emprego.';
                case 'Eventos':
                  return 'Divulgue um evento para a cidade.';
                case 'Achados':
                  return 'Ajude alguém a encontrar o que perdeu.';
                case 'Premium':
                  return 'Anuncie um número premium em destaque.';
                case 'Destaques':
                  return 'Destaque um serviço profissional.';
                default:
                  return 'Crie uma nova publicação no app.';
              }
            }

            IconData iconeCategoria() {
              switch (tipoSelecionado) {
                case 'Vagas':
                  return Icons.work_outline_rounded;
                case 'Eventos':
                  return Icons.celebration_rounded;
                case 'Achados':
                  return Icons.search_rounded;
                case 'Premium':
                  return Icons.workspace_premium_rounded;
                case 'Destaques':
                  return Icons.star_rounded;
                default:
                  return Icons.campaign_rounded;
              }
            }

            return _dialogElegante(
              header: _buildDialogHeader(
                icone: iconeCategoria(),
                titulo: 'Nova Publicação',
                subtitulo: subtituloCategoria(),
              ),
              rodape: _buildDialogRodape(
                onCancelar: () => Navigator.pop(context),
                onAcao: salvarPost,
                labelAcao: 'Publicar Agora',
                iconeAcao: Icons.send_rounded,
                isLoading: isLoading,
              ),
              corpo: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Seletor de Categoria
                      DropdownButtonFormField<String>(
                        initialValue: tipoSelecionado,
                        decoration: const InputDecoration(
                          labelText: "Onde deseja publicar?",
                          border: OutlineInputBorder(),
                        ),
                        items:
                            [
                                  'Destaques',
                                  'Premium',
                                  'Vagas',
                                  'Eventos',
                                  'Achados',
                                ]
                                .map(
                                  (t) => DropdownMenuItem(
                                    value: t,
                                    child: Text(t),
                                  ),
                                )
                                .toList(),
                        onChanged: (val) => setState(() {
                          tipoSelecionado = val!;
                          imagemBytes = null;
                        }),
                      ),
                      const SizedBox(height: 15),

                      // Campos Dinâmicos! Eles mudam conforme a escolha
                      TextField(
                        controller: tituloC,
                        decoration: InputDecoration(
                          labelText: tipoSelecionado == 'Vagas'
                              ? "Cargo da Vaga"
                              : "Título",
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 10),

                      if (tipoSelecionado == 'Achados')
                        Row(
                          children: [
                            Expanded(
                              child: RadioListTile(
                                title: const Text("Perdido"),
                                value: true,
                                groupValue: isPerdido,
                                onChanged: (v) =>
                                    setState(() => isPerdido = v as bool),
                              ),
                            ),
                            Expanded(
                              child: RadioListTile(
                                title: const Text("Achado"),
                                value: false,
                                groupValue: isPerdido,
                                onChanged: (v) =>
                                    setState(() => isPerdido = v as bool),
                              ),
                            ),
                          ],
                        ),

                      if ([
                        'Vagas',
                        'Eventos',
                        'Achados',
                        'Destaques',
                      ].contains(tipoSelecionado)) ...[
                        TextField(
                          controller: empresaLocalC,
                          decoration: InputDecoration(
                            labelText: tipoSelecionado == 'Vagas'
                                ? "Nome da Empresa"
                                : (tipoSelecionado == 'Destaques'
                                      ? "Categoria Profissional"
                                      : "Local"),
                            border: const OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],

                      if ([
                        'Vagas',
                        'Eventos',
                        'Achados',
                        'Premium',
                        'Destaques',
                      ].contains(tipoSelecionado)) ...[
                        _campoCidadeAnuncio(
                          controller: cidadeC,
                          onChanged: () => setState(() {}),
                        ),
                        const SizedBox(height: 10),
                      ],

                      if ([
                        'Vagas',
                        'Eventos',
                        'Achados',
                      ].contains(tipoSelecionado)) ...[
                        TextField(
                          controller: descC,
                          maxLines: 3,
                          decoration: const InputDecoration(
                            labelText: "Descrição Completa",
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],

                      if (tipoSelecionado == 'Eventos') ...[
                        TextField(
                          controller: dataLinkC,
                          decoration: const InputDecoration(
                            labelText: "Data do Evento (Ex: 25/Dez às 20h)",
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],

                      if (tipoSelecionado != 'Eventos') ...[
                        TextField(
                          controller: contatoC,
                          decoration: const InputDecoration(
                            labelText: "Telefone / Contato",
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 10),
                      ] else ...[
                        TextField(
                          controller: contatoC,
                          decoration: const InputDecoration(
                            labelText: "Link do Ingresso (Opcional)",
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],

                      TextField(
                        controller: emailC,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(
                          labelText: "E-mail",
                          hintText: "exemplo@email.com",
                          prefixIcon: Icon(Icons.email_outlined),
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 10),

                      const Divider(),
                      Text(
                        "Valor e Período",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: diPertinRoxo,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: donoC,
                        decoration: const InputDecoration(
                          labelText: "Nome do Contratante (quem paga)",
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: valorC,
                              onChanged: (_) => setState(() {}),
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                labelText: modalidadeValor == 'diario'
                                    ? "Valor por dia (R\$)"
                                    : "Valor por mês (R\$)",
                                border: const OutlineInputBorder(),
                                prefixText: "R\$ ",
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          SegmentedButton<String>(
                            segments: const [
                              ButtonSegment(value: 'diario', label: Text('Dia')),
                              ButtonSegment(value: 'mensal', label: Text('Mês')),
                            ],
                            selected: {modalidadeValor},
                            onSelectionChanged: (v) =>
                                setState(() => modalidadeValor = v.first),
                            style: SegmentedButton.styleFrom(
                              selectedBackgroundColor: diPertinLaranja,
                              selectedForegroundColor: Colors.white,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () async {
                                final p = await showDatePicker(
                                  context: context,
                                  initialDate: dataInicio,
                                  firstDate: DateTime(2024),
                                  lastDate: DateTime(2030),
                                );
                                if (p != null) setState(() => dataInicio = p);
                              },
                              icon: const Icon(Icons.calendar_today, size: 16),
                              label: Text(
                                "Início: ${dataInicio.day.toString().padLeft(2, '0')}/${dataInicio.month.toString().padLeft(2, '0')}/${dataInicio.year}",
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () async {
                                final p = await showDatePicker(
                                  context: context,
                                  initialDate: dataFim,
                                  firstDate: DateTime(2024),
                                  lastDate: DateTime(2030),
                                );
                                if (p != null) setState(() => dataFim = p);
                              },
                              icon: const Icon(Icons.event_available, size: 16),
                              label: Text(
                                "Fim: ${dataFim.day.toString().padLeft(2, '0')}/${dataFim.month.toString().padLeft(2, '0')}/${dataFim.year}",
                              ),
                            ),
                          ),
                        ],
                      ),
                      Builder(
                        builder: (_) {
                          final dias =
                              _diasContratados(dataInicio, dataFim);
                          final val =
                              double.tryParse(valorC.text.replaceAll(',', '.')) ?? 0;
                          final total = _valorTotalDoPeriodo(
                            valorUnitario: val,
                            modalidade: modalidadeValor,
                            diasContratados: dias,
                          );
                          if (val <= 0) return const SizedBox(height: 15);
                          return Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.green.shade50,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.green.shade200),
                              ),
                              child: Text(
                                modalidadeValor == 'mensal'
                                    ? '$dias dias (${(dias / 30).ceil()} mês(es)) × ${_fmtBrl(val)}/mês = ${_fmtBrl(total)}'
                                    : '$dias dias × ${_fmtBrl(val)}/dia = ${_fmtBrl(total)}',
                                style: TextStyle(
                                  color: Colors.green.shade800,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 15),

                      // BOTÃO DE UPLOAD DE FOTO (disponível para todas as
                      // categorias: Destaques, Premium, Vagas, Eventos, Achados)
                      _buildCampoFotoUtilidade(
                        imagemBytes: imagemBytes,
                        imagemUrlAtual: null,
                        onEscolher: escolherFoto,
                        onRemover: imagemBytes != null
                            ? () => setState(() => imagemBytes = null)
                            : null,
                      ),
                    ],
                  ),
            );
          },
        );
      },
    );
  }

  // --- LISTAS DAS ABAS ---

  /// Retorna (diasRestantes, cor, icone, label) com base no vencimento.
  /// diasRestantes > 0 = falta para vencer, <= 0 = já venceu.
  ({int dias, Color cor, IconData icone, String label}) _statusVencimento(
      Timestamp? tsVenc) {
    if (tsVenc == null) {
      return (dias: 999, cor: Colors.green, icone: Icons.check, label: 'Ativo');
    }
    final agora = DateTime.now();
    final venc = tsVenc.toDate();
    final diff = DateTime(venc.year, venc.month, venc.day)
        .difference(DateTime(agora.year, agora.month, agora.day))
        .inDays;

    if (diff > 3) {
      return (
        dias: diff,
        cor: const Color(0xFF16A34A),
        icone: Icons.check_circle_rounded,
        label: '$diff dias restantes',
      );
    } else if (diff > 0) {
      return (
        dias: diff,
        cor: const Color(0xFFD97706),
        icone: Icons.warning_amber_rounded,
        label: 'Vencendo em $diff dia${diff > 1 ? 's' : ''}',
      );
    } else if (diff == 0) {
      return (
        dias: 0,
        cor: const Color(0xFFDC2626),
        icone: Icons.error_rounded,
        label: 'Vence hoje!',
      );
    } else {
      final atraso = diff.abs();
      return (
        dias: diff,
        cor: const Color(0xFFDC2626),
        icone: Icons.cancel_rounded,
        label: 'Vencido há $atraso dia${atraso > 1 ? 's' : ''}',
      );
    }
  }

  Future<void> _desativarSeVencidoHa3Dias(
      String colecao, String docId, Timestamp? tsVenc, bool ativo) async {
    if (!ativo || tsVenc == null) return;
    final agora = DateTime.now();
    final venc = tsVenc.toDate();
    final diff = DateTime(venc.year, venc.month, venc.day)
        .difference(DateTime(agora.year, agora.month, agora.day))
        .inDays;
    if (diff < -3) {
      await FirebaseFirestore.instance
          .collection(colecao)
          .doc(docId)
          .update({'ativo': false});
    }
  }

  Widget _buildListaGenerica({
    required String colecao,
    required String campoTitulo,
    required String campoSubtitulo,
    String? campoDataVencimento,
    Widget Function(String id, Map<String, dynamic> dados)? botoesExtras,
  }) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection(colecao)
          .orderBy('ativo', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Center(child: Text("Nenhum registro encontrado."));
        }

        return ListView.builder(
          padding: const EdgeInsets.all(20),
          itemCount: snapshot.data!.docs.length,
          itemBuilder: (context, index) {
            final doc = snapshot.data!.docs[index];
            final dados = safeWebDocData(doc);
            bool ativo = dados['ativo'] ?? false;

            final tsVenc = _tsVencimentoAnuncio(
              dados,
              campoPreferido: campoDataVencimento,
            );
            final sv = _statusVencimento(tsVenc);

            _desativarSeVencidoHa3Dias(colecao, doc.id, tsVenc, ativo);

            final corFundo = !ativo
                ? Colors.grey[200]!
                : sv.dias < -3
                    ? Colors.red.shade50
                    : Colors.white;

            return Card(
              elevation: 2,
              color: corFundo,
              margin: const EdgeInsets.only(bottom: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: ativo && sv.dias <= 0
                    ? BorderSide(color: sv.cor.withValues(alpha: 0.4))
                    : BorderSide.none,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: ativo ? sv.cor : Colors.grey,
                      child: Icon(
                        ativo ? sv.icone : Icons.block,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            dados[campoTitulo] ?? 'Sem Título',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            dados[campoSubtitulo] ?? '',
                            style: TextStyle(
                                fontSize: 12.5, color: Colors.grey.shade700),
                          ),
                          if (campoDataVencimento != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              "Vencimento: ${_formatarData(tsVenc)}",
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade500,
                              ),
                            ),
                          ],
                          if (ativo && campoDataVencimento != null) ...[
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: sv.cor.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                    color: sv.cor.withValues(alpha: 0.3)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(sv.icone, size: 13, color: sv.cor),
                                  const SizedBox(width: 4),
                                  Text(
                                    sv.label,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: sv.cor,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (botoesExtras != null) botoesExtras(doc.id, dados),
                    const SizedBox(width: 6),
                    Switch(
                      value: ativo,
                      activeThumbColor: Colors.green,
                      onChanged: (val) => _toggleAtivo(colecao, doc.id, ativo),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                      tooltip: "Apagar permanentemente",
                      onPressed: () => _deletarPost(colecao, doc.id),
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

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 5,
      child: Scaffold(
        backgroundColor: Colors.grey[100],

        // Novo anúncio (FAB)
        floatingActionButton: FloatingActionButton.extended(
          heroTag: 'btn_utilidades', // Evita erro de animação duplicada
          onPressed: _mostrarFormularioNovoPost,
          backgroundColor: diPertinLaranja,
          icon: const Icon(Icons.add, color: Colors.white),
          label: const Text(
            "Novo Anúncio",
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),

        body: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              color: Colors.white,
              padding: const EdgeInsets.only(
                top: 30,
                left: 30,
                right: 30,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Anúncios & Utilidade Pública",
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: diPertinRoxo,
                    ),
                  ),
                  const SizedBox(height: 20),
                  TabBar(
                          labelColor: diPertinRoxo,
                          unselectedLabelColor: Colors.grey,
                          indicatorColor: diPertinLaranja,
                          indicatorWeight: 4,
                          tabs: const [
                            Tab(icon: Icon(Icons.star), text: "Destaques"),
                            Tab(
                              icon: Icon(Icons.phone_forwarded),
                              text: "Premium",
                            ),
                            Tab(icon: Icon(Icons.work), text: "Vagas"),
                            Tab(icon: Icon(Icons.celebration), text: "Eventos"),
                            Tab(icon: Icon(Icons.search_off), text: "Achados"),
                          ],
                        ),

                ],
              ),
            ),

            Expanded(
              child: TabBarView(
                      children: [
                        _buildListaGenerica(
                          colecao: 'servicos_destaque',
                          campoTitulo: 'titulo',
                          campoSubtitulo: 'cidade',
                          campoDataVencimento: 'data_fim',
                          botoesExtras: (id, dados) => IconButton(
                            icon: Icon(Icons.edit, color: diPertinRoxo, size: 20),
                            tooltip: 'Editar destaque',
                            onPressed: () => _editarDestaque(id, dados),
                          ),
                        ),
                        _buildListaGenerica(
                          colecao: 'telefones_premium',
                          campoTitulo: 'titulo',
                          campoSubtitulo: 'telefone',
                          campoDataVencimento: 'data_vencimento',
                          botoesExtras: (id, dados) => Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: Icon(Icons.edit,
                                    color: diPertinRoxo, size: 20),
                                tooltip: 'Editar premium',
                                onPressed: () => _editarPremium(id, dados),
                              ),
                              const SizedBox(width: 4),
                              ElevatedButton.icon(
                                onPressed: () => _configurarPremium(id, dados),
                                icon: const Icon(
                                  Icons.settings,
                                  color: Colors.white,
                                  size: 16,
                                ),
                                label: const Text(
                                  'Configurar',
                                  style: TextStyle(color: Colors.white),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.blue,
                                ),
                              ),
                              const SizedBox(width: 4),
                              ElevatedButton.icon(
                                onPressed: () => _renovarPremium(
                                  id,
                                  _tsVencimentoAnuncio(
                                    dados,
                                    campoPreferido: 'data_vencimento',
                                  ),
                                ),
                                icon: const Icon(
                                  Icons.add_circle,
                                  color: Colors.white,
                                  size: 16,
                                ),
                                label: const Text(
                                  '+30 Dias',
                                  style: TextStyle(color: Colors.white),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: diPertinLaranja,
                                ),
                              ),
                            ],
                          ),
                        ),
                        _buildListaGenerica(
                          colecao: 'vagas',
                          campoTitulo: 'cargo',
                          campoSubtitulo: 'empresa',
                          campoDataVencimento: 'data_vencimento',
                          botoesExtras: (id, dados) => Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: Icon(Icons.edit, color: diPertinRoxo, size: 20),
                                tooltip: 'Editar vaga',
                                onPressed: () => _editarVaga(id, dados),
                              ),
                              const SizedBox(width: 4),
                              ElevatedButton.icon(
                                onPressed: () => _renovarVaga(
                                  id,
                                  _tsVencimentoAnuncio(
                                    dados,
                                    campoPreferido: 'data_vencimento',
                                  ),
                                ),
                                icon: const Icon(
                                  Icons.add_circle,
                                  color: Colors.white,
                                  size: 16,
                                ),
                                label: const Text(
                                  "+7 Dias",
                                  style: TextStyle(color: Colors.white),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: diPertinLaranja,
                                ),
                              ),
                            ],
                          ),
                        ),
                        _buildListaGenerica(
                          colecao: 'eventos',
                          campoTitulo: 'titulo',
                          campoSubtitulo: 'nome_dono',
                          campoDataVencimento: 'data_fim',
                          botoesExtras: (id, dados) => Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: Icon(Icons.edit, color: diPertinRoxo, size: 20),
                                tooltip: 'Editar evento',
                                onPressed: () => _editarEvento(id, dados),
                              ),
                              const SizedBox(width: 4),
                              ElevatedButton.icon(
                                onPressed: () => _configurarEvento(id, dados),
                                icon: const Icon(
                                  Icons.settings,
                                  color: Colors.white,
                                  size: 16,
                                ),
                                label: const Text(
                                  "Configurar",
                                  style: TextStyle(color: Colors.white),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.blue,
                                ),
                              ),
                            ],
                          ),
                        ),
                        _buildListaGenerica(
                          colecao: 'achados',
                          campoTitulo: 'titulo',
                          campoSubtitulo: 'tipo',
                          campoDataVencimento: 'data_vencimento',
                          botoesExtras: (id, dados) => Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: Icon(Icons.edit, color: diPertinRoxo, size: 20),
                                tooltip: 'Editar achado',
                                onPressed: () => _editarAchado(id, dados),
                              ),
                              const SizedBox(width: 4),
                              ElevatedButton.icon(
                                onPressed: () => _renovarAchados(
                                  id,
                                  _tsVencimentoAnuncio(
                                    dados,
                                    campoPreferido: 'data_vencimento',
                                  ),
                                ),
                                icon: const Icon(
                                  Icons.add_circle,
                                  color: Colors.white,
                                  size: 16,
                                ),
                                label: const Text(
                                  "+3 Dias",
                                  style: TextStyle(color: Colors.white),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: diPertinLaranja,
                                ),
                              ),
                            ],
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
