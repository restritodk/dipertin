import 'package:depertin_web/widgets/botao_suporte_flutuante.dart';
import 'package:depertin_web/widgets/campo_cidade_brasil_field.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:typed_data';

class UtilidadesScreen extends StatefulWidget {
  const UtilidadesScreen({super.key});

  @override
  State<UtilidadesScreen> createState() => _UtilidadesScreenState();
}

class _UtilidadesScreenState extends State<UtilidadesScreen> {
  final Color diPertinRoxo = const Color(0xFF6A1B9A);
  final Color diPertinLaranja = const Color(0xFFFF8F00);

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
  }) {
    String fmt(DateTime d) =>
        '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
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
              onSelectionChanged: (v) => onModalidade(v.first),
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
                  if (p != null) onInicio(p);
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
                  if (p != null) onFim(p);
                },
                icon: const Icon(Icons.event_available, size: 16),
                label: Text("Fim: ${fmt(dtFim)}"),
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _aplicarFinanceiro(Map<String, dynamic> upd, TextEditingController valorC, String modalidade, DateTime dtInicio, DateTime dtFim) {
    final val = double.tryParse(valorC.text.replaceAll(',', '.')) ?? 0;
    if (val <= 0) return;
    int dias = dtFim.difference(dtInicio).inDays;
    if (dias <= 0) dias = 1;
    double total;
    if (modalidade == 'mensal') {
      final meses = (dias / 30).ceil().clamp(1, 9999);
      total = val * meses;
      upd['valor_mensal'] = val;
    } else {
      total = val * dias;
      upd['valor_diario'] = val;
    }
    upd['modalidade_valor'] = modalidade;
    upd['data_inicio'] = Timestamp.fromDate(dtInicio);
    upd['data_fim'] = Timestamp.fromDate(dtFim);
    upd['valor_total'] = total;
    upd['gera_receita'] = true;
  }

  Future<void> _registrarReceitaSeValor(TextEditingController valorC, String modalidade, DateTime dtInicio, DateTime dtFim, String tipo, String titulo, String pagador) async {
    final val = double.tryParse(valorC.text.replaceAll(',', '.')) ?? 0;
    if (val <= 0) return;
    int dias = dtFim.difference(dtInicio).inDays;
    if (dias <= 0) dias = 1;
    double total;
    if (modalidade == 'mensal') {
      total = val * (dias / 30).ceil().clamp(1, 9999);
    } else {
      total = val * dias;
    }
    await FirebaseFirestore.instance.collection('receitas_app').add({
      'tipo_receita': tipo,
      'titulo_referencia': titulo,
      'nome_pagador': pagador,
      'valor_total': total,
      'valor_unitario': val,
      'modalidade_valor': modalidade,
      'data_inicio': Timestamp.fromDate(dtInicio),
      'data_fim': Timestamp.fromDate(dtFim),
      'qtd_dias': dias,
      'data_registro': FieldValue.serverTimestamp(),
    });
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

          return AlertDialog(
          title: Text("Editar Vaga", style: TextStyle(color: diPertinRoxo, fontWeight: FontWeight.bold)),
          content: SizedBox(
            width: 500,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(controller: cargoC, decoration: const InputDecoration(labelText: "Cargo da Vaga", border: OutlineInputBorder())),
                  const SizedBox(height: 12),
                  TextField(controller: empresaC, decoration: const InputDecoration(labelText: "Nome da Empresa", border: OutlineInputBorder())),
                  const SizedBox(height: 12),
                  CampoCidadeBrasilField(controller: cidadeC, decoration: const InputDecoration(labelText: "Cidade (deixe vazio para todo o Brasil)", hintText: "Digite e selecione da lista (ex.: Toledo — PR)", helperText: "Selecione pela lista para salvar com UF.", border: OutlineInputBorder())),
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
                  _buildSecaoFinanceira(valorC: valorC, modalidade: modalidade, dtInicio: dtInicio, dtFim: dtFim, onModalidade: (v) => setDlg(() => modalidade = v), onInicio: (d) => setDlg(() => dtInicio = d), onFim: (d) => setDlg(() => dtFim = d)),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancelar")),
            ElevatedButton(
              onPressed: () async {
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
                if (emailC.text.trim().isNotEmpty) upd['email'] = emailC.text.trim();
                if (imagemBytes != null) {
                  upd['imagem_url'] = await _uploadImagemUtilidade(imagemBytes!);
                } else if (removerImagem) {
                  upd['imagem_url'] = '';
                }
                _aplicarFinanceiro(upd, valorC, modalidade, dtInicio, dtFim);
                await FirebaseFirestore.instance.collection('vagas').doc(id).update(upd);
                await _registrarReceitaSeValor(valorC, modalidade, dtInicio, dtFim, 'Vagas', cargoC.text, dados['nome_dono'] ?? '');
                if (context.mounted) { Navigator.pop(context); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Vaga atualizada!'), backgroundColor: Colors.green)); }
              },
              style: ElevatedButton.styleFrom(backgroundColor: diPertinLaranja, foregroundColor: Colors.white),
              child: const Text("Salvar"),
            ),
          ],
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

          return AlertDialog(
          title: Text(
            "Editar Destaque",
            style: TextStyle(color: diPertinRoxo, fontWeight: FontWeight.bold),
          ),
          content: SizedBox(
            width: 500,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(controller: tituloC, decoration: const InputDecoration(labelText: "Título", border: OutlineInputBorder())),
                  const SizedBox(height: 12),
                  TextField(controller: categoriaC, decoration: const InputDecoration(labelText: "Categoria Profissional", border: OutlineInputBorder())),
                  const SizedBox(height: 12),
                  CampoCidadeBrasilField(controller: cidadeC, decoration: const InputDecoration(labelText: "Cidade (deixe vazio para todo o Brasil)", hintText: "Digite e selecione da lista (ex.: Toledo — PR)", helperText: "Selecione pela lista para salvar com UF.", border: OutlineInputBorder())),
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
                  _buildSecaoFinanceira(valorC: valorC, modalidade: modalidade, dtInicio: dtInicio, dtFim: dtFim, onModalidade: (v) => setDlg(() => modalidade = v), onInicio: (d) => setDlg(() => dtInicio = d), onFim: (d) => setDlg(() => dtFim = d)),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancelar")),
            ElevatedButton(
              onPressed: () async {
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
                if (emailC.text.trim().isNotEmpty) upd['email'] = emailC.text.trim();
                if (imagemBytes != null) {
                  upd['imagem_url'] = await _uploadImagemUtilidade(imagemBytes!);
                } else if (removerImagem) {
                  upd['imagem_url'] = '';
                }
                _aplicarFinanceiro(upd, valorC, modalidade, dtInicio, dtFim);
                await FirebaseFirestore.instance.collection('servicos_destaque').doc(id).update(upd);
                await _registrarReceitaSeValor(valorC, modalidade, dtInicio, dtFim, 'Destaques', tituloC.text, dados['nome_dono'] ?? '');
                if (context.mounted) { Navigator.pop(context); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Destaque atualizado!'), backgroundColor: Colors.green)); }
              },
              style: ElevatedButton.styleFrom(backgroundColor: diPertinLaranja, foregroundColor: Colors.white),
              child: const Text("Salvar"),
            ),
          ],
        );
        },
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
    DateTime dtInicio = dados['data_inicio'] != null ? (dados['data_inicio'] as Timestamp).toDate() : DateTime.now();
    DateTime dtFim = dados['data_fim'] != null ? (dados['data_fim'] as Timestamp).toDate() : (dados['data_vencimento'] != null ? (dados['data_vencimento'] as Timestamp).toDate() : DateTime.now().add(const Duration(days: 30)));
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

          return AlertDialog(
          title: Text("Editar Premium", style: TextStyle(color: diPertinRoxo, fontWeight: FontWeight.bold)),
          content: SizedBox(
            width: 500,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(controller: tituloC, decoration: const InputDecoration(labelText: "Título", border: OutlineInputBorder())),
                  const SizedBox(height: 12),
                  TextField(controller: telefoneC, decoration: const InputDecoration(labelText: "Telefone / WhatsApp", border: OutlineInputBorder())),
                  const SizedBox(height: 12),
                  CampoCidadeBrasilField(controller: cidadeC, decoration: const InputDecoration(labelText: "Cidade (deixe vazio para todo o Brasil)", hintText: "Digite e selecione da lista (ex.: Toledo — PR)", helperText: "Selecione pela lista para salvar com UF.", border: OutlineInputBorder())),
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
                  _buildSecaoFinanceira(valorC: valorC, modalidade: modalidade, dtInicio: dtInicio, dtFim: dtFim, onModalidade: (v) => setDlg(() => modalidade = v), onInicio: (d) => setDlg(() => dtInicio = d), onFim: (d) => setDlg(() => dtFim = d)),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancelar")),
            ElevatedButton(
              onPressed: () async {
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
                if (emailC.text.trim().isNotEmpty) upd['email'] = emailC.text.trim();
                if (imagemBytes != null) {
                  upd['imagem_url'] = await _uploadImagemUtilidade(imagemBytes!);
                } else if (removerImagem) {
                  upd['imagem_url'] = '';
                }
                _aplicarFinanceiro(upd, valorC, modalidade, dtInicio, dtFim);
                await FirebaseFirestore.instance.collection('telefones_premium').doc(id).update(upd);
                await _registrarReceitaSeValor(valorC, modalidade, dtInicio, dtFim, 'Premium', tituloC.text, dados['nome_dono'] ?? '');
                if (context.mounted) { Navigator.pop(context); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Premium atualizado!'), backgroundColor: Colors.green)); }
              },
              style: ElevatedButton.styleFrom(backgroundColor: diPertinLaranja, foregroundColor: Colors.white),
              child: const Text("Salvar"),
            ),
          ],
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

          return AlertDialog(
          title: Text("Editar Evento", style: TextStyle(color: diPertinRoxo, fontWeight: FontWeight.bold)),
          content: SizedBox(
            width: 500,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(controller: tituloC, decoration: const InputDecoration(labelText: "Título do Evento", border: OutlineInputBorder())),
                  const SizedBox(height: 12),
                  TextField(controller: localC, decoration: const InputDecoration(labelText: "Local", border: OutlineInputBorder())),
                  const SizedBox(height: 12),
                  CampoCidadeBrasilField(controller: cidadeC, decoration: const InputDecoration(labelText: "Cidade (deixe vazio para todo o Brasil)", hintText: "Digite e selecione da lista (ex.: Toledo — PR)", helperText: "Selecione pela lista para salvar com UF.", border: OutlineInputBorder())),
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
                  _buildSecaoFinanceira(valorC: valorC, modalidade: modalidade, dtInicio: dtInicio, dtFim: dtFim, onModalidade: (v) => setDlg(() => modalidade = v), onInicio: (d) => setDlg(() => dtInicio = d), onFim: (d) => setDlg(() => dtFim = d)),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancelar")),
            ElevatedButton(
              onPressed: () async {
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
                if (emailC.text.trim().isNotEmpty) upd['email'] = emailC.text.trim();
                if (imagemBytes != null) {
                  upd['imagem_url'] = await _uploadImagemUtilidade(imagemBytes!);
                } else if (removerImagem) {
                  upd['imagem_url'] = '';
                }
                _aplicarFinanceiro(upd, valorC, modalidade, dtInicio, dtFim);
                await FirebaseFirestore.instance.collection('eventos').doc(id).update(upd);
                await _registrarReceitaSeValor(valorC, modalidade, dtInicio, dtFim, 'Eventos', tituloC.text, dados['nome_dono'] ?? '');
                if (context.mounted) { Navigator.pop(context); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Evento atualizado!'), backgroundColor: Colors.green)); }
              },
              style: ElevatedButton.styleFrom(backgroundColor: diPertinLaranja, foregroundColor: Colors.white),
              child: const Text("Salvar"),
            ),
          ],
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

          return AlertDialog(
          title: Text("Editar Achado", style: TextStyle(color: diPertinRoxo, fontWeight: FontWeight.bold)),
          content: SizedBox(
            width: 500,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
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
                  CampoCidadeBrasilField(controller: cidadeC, decoration: const InputDecoration(labelText: "Cidade (deixe vazio para todo o Brasil)", hintText: "Digite e selecione da lista (ex.: Toledo — PR)", helperText: "Selecione pela lista para salvar com UF.", border: OutlineInputBorder())),
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
                  _buildSecaoFinanceira(valorC: valorC, modalidade: modalidade, dtInicio: dtInicio, dtFim: dtFim, onModalidade: (v) => setDlg(() => modalidade = v), onInicio: (d) => setDlg(() => dtInicio = d), onFim: (d) => setDlg(() => dtFim = d)),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancelar")),
            ElevatedButton(
              onPressed: () async {
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
                if (emailC.text.trim().isNotEmpty) upd['email'] = emailC.text.trim();
                if (imagemBytes != null) {
                  upd['imagem_url'] = await _uploadImagemUtilidade(imagemBytes!);
                } else if (removerImagem) {
                  upd['imagem_url'] = '';
                }
                _aplicarFinanceiro(upd, valorC, modalidade, dtInicio, dtFim);
                await FirebaseFirestore.instance.collection('achados').doc(id).update(upd);
                await _registrarReceitaSeValor(valorC, modalidade, dtInicio, dtFim, 'Achados', tituloC.text, dados['nome_dono'] ?? '');
                if (context.mounted) { Navigator.pop(context); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Achado atualizado!'), backgroundColor: Colors.green)); }
              },
              style: ElevatedButton.styleFrom(backgroundColor: diPertinLaranja, foregroundColor: Colors.white),
              child: const Text("Salvar"),
            ),
          ],
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
                int qtdDias = dataFim.difference(dataInicio).inDays;
                if (qtdDias <= 0) qtdDias = 1;

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

                  double valorTotalGerado;
                  if (modalidadeValor == 'mensal') {
                    dados['valor_mensal'] = valorCobrado;
                    final meses = (qtdDias / 30).ceil().clamp(1, 9999);
                    valorTotalGerado = valorCobrado * meses;
                  } else {
                    dados['valor_diario'] = valorCobrado;
                    valorTotalGerado = valorCobrado * qtdDias;
                  }
                  dados['valor_total'] = valorTotalGerado;

                  await FirebaseFirestore.instance
                      .collection('receitas_app')
                      .add({
                        'tipo_receita': tipoSelecionado,
                        'titulo_referencia': tituloC.text,
                        'nome_pagador': donoC.text.trim(),
                        'valor_total': valorTotalGerado,
                        'valor_unitario': valorCobrado,
                        'modalidade_valor': modalidadeValor,
                        'data_inicio': Timestamp.fromDate(dataInicio),
                        'data_fim': Timestamp.fromDate(dataFim),
                        'qtd_dias': qtdDias,
                        'data_registro': FieldValue.serverTimestamp(),
                      });
                }

                // 3. Molda os dados de acordo com a categoria (Igual estava antes)
                if (emailC.text.trim().isNotEmpty) {
                  dados['email'] = emailC.text.trim();
                }

                final cidadeRaw = cidadeC.text.trim();
                final cidadeNorm = _normalizarCidade(cidadeRaw);

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
                  await FirebaseFirestore.instance
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
                  await FirebaseFirestore.instance
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
                  await FirebaseFirestore.instance
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
                  await FirebaseFirestore.instance
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
                  await FirebaseFirestore.instance
                      .collection('servicos_destaque')
                      .add(dados);
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

            return AlertDialog(
              title: Text(
                "Nova Publicação",
                style: TextStyle(
                  color: diPertinRoxo,
                  fontWeight: FontWeight.bold,
                ),
              ),
              content: SizedBox(
                width: 500,
                child: SingleChildScrollView(
                  child: Column(
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
                        'Achados',
                        'Premium',
                        'Destaques',
                      ].contains(tipoSelecionado)) ...[
                        CampoCidadeBrasilField(
                          controller: cidadeC,
                          decoration: const InputDecoration(
                            labelText: "Cidade (deixe vazio para todo o Brasil)",
                            hintText:
                                "Digite e selecione da lista (ex.: Toledo — PR)",
                            helperText:
                                "Selecione pela lista para salvar com UF.",
                            border: OutlineInputBorder(),
                          ),
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
                          final dias = dataFim.difference(dataInicio).inDays.clamp(1, 99999);
                          final val = double.tryParse(valorC.text.replaceAll(',', '.')) ?? 0;
                          double total;
                          if (modalidadeValor == 'mensal') {
                            final meses = (dias / 30).ceil().clamp(1, 9999);
                            total = val * meses;
                          } else {
                            total = val * dias;
                          }
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
                                    ? "$dias dias (${(dias / 30).ceil()} mês(es)) × R\$ ${val.toStringAsFixed(2)}/mês = R\$ ${total.toStringAsFixed(2)}"
                                    : "$dias dias × R\$ ${val.toStringAsFixed(2)}/dia = R\$ ${total.toStringAsFixed(2)}",
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
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("Cancelar"),
                ),
                ElevatedButton(
                  onPressed: isLoading ? null : salvarPost,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: diPertinLaranja,
                    foregroundColor: Colors.white,
                  ),
                  child: isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text("Publicar Agora"),
                ),
              ],
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
    return StreamBuilder<QuerySnapshot>(
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
            var doc = snapshot.data!.docs[index];
            var dados = doc.data() as Map<String, dynamic>;
            bool ativo = dados['ativo'] ?? false;

            final tsVenc = campoDataVencimento != null
                ? dados[campoDataVencimento] as Timestamp?
                : null;
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

        // A MÁGICA ENTRA AQUI! O BOTÃO FLUTUANTE DE CRIAR POST + SUPORTE
        floatingActionButton: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // NOSSO BOTÃO DE SUPORTE NO TOPO
            const BotaoSuporteFlutuante(),
            const SizedBox(height: 15), // Espaçamento entre os botões
            // O BOTÃO DE NOVO ANÚNCIO (Que você já tinha)
            FloatingActionButton.extended(
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
          ],
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
                          botoesExtras: (id, dados) => IconButton(
                            icon: Icon(Icons.edit, color: diPertinRoxo, size: 20),
                            tooltip: 'Editar premium',
                            onPressed: () => _editarPremium(id, dados),
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
                                  dados['data_vencimento'] as Timestamp?,
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
                                  dados['data_vencimento'] as Timestamp?,
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
