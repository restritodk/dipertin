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

  void _editarVaga(String id, Map<String, dynamic> dados) {
    final cargoC = TextEditingController(text: dados['cargo'] ?? '');
    final empresaC = TextEditingController(text: dados['empresa'] ?? '');
    final cidadeC = TextEditingController(text: dados['cidade'] ?? '');
    final descC = TextEditingController(text: dados['descricao'] ?? '');
    final contatoC = TextEditingController(text: dados['contato'] ?? '');
    final emailC = TextEditingController(text: dados['email'] ?? '');

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          "Editar Vaga",
          style: TextStyle(color: diPertinRoxo, fontWeight: FontWeight.bold),
        ),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: cargoC,
                  decoration: const InputDecoration(
                    labelText: "Cargo da Vaga",
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: empresaC,
                  decoration: const InputDecoration(
                    labelText: "Nome da Empresa",
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                CampoCidadeBrasilField(
                  controller: cidadeC,
                  decoration: const InputDecoration(
                    labelText: "Cidade",
                    hintText: "Digite para buscar o município",
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descC,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: "Descrição Completa",
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: contatoC,
                  decoration: const InputDecoration(
                    labelText: "Telefone / Contato",
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
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
            onPressed: () async {
              final atualizacao = <String, dynamic>{
                'cargo': cargoC.text.trim(),
                'empresa': empresaC.text.trim(),
                'cidade': cidadeC.text.trim(),
                'descricao': descC.text.trim(),
                'contato': contatoC.text.trim(),
              };
              if (emailC.text.trim().isNotEmpty) {
                atualizacao['email'] = emailC.text.trim();
              }
              await FirebaseFirestore.instance
                  .collection('vagas')
                  .doc(id)
                  .update(atualizacao);
              if (context.mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Vaga atualizada com sucesso!'),
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
    );
  }

  void _editarDestaque(String id, Map<String, dynamic> dados) {
    final tituloC = TextEditingController(text: dados['titulo'] ?? '');
    final categoriaC = TextEditingController(text: dados['categoria'] ?? '');
    final cidadeC = TextEditingController(text: dados['cidade'] ?? '');
    final telefoneC = TextEditingController(text: dados['telefone'] ?? '');
    final emailC = TextEditingController(text: dados['email'] ?? '');

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
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
                TextField(
                  controller: tituloC,
                  decoration: const InputDecoration(
                    labelText: "Título",
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: categoriaC,
                  decoration: const InputDecoration(
                    labelText: "Categoria Profissional",
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                CampoCidadeBrasilField(
                  controller: cidadeC,
                  decoration: const InputDecoration(
                    labelText: "Cidade",
                    hintText: "Digite para buscar o município",
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: telefoneC,
                  decoration: const InputDecoration(
                    labelText: "Telefone / Contato",
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: emailC,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: "E-mail",
                    prefixIcon: Icon(Icons.email_outlined),
                    border: OutlineInputBorder(),
                  ),
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
            onPressed: () async {
              final upd = <String, dynamic>{
                'titulo': tituloC.text.trim(),
                'categoria': categoriaC.text.trim(),
                'cidade': cidadeC.text.trim(),
                'telefone': telefoneC.text.trim(),
              };
              if (emailC.text.trim().isNotEmpty) {
                upd['email'] = emailC.text.trim();
              }
              await FirebaseFirestore.instance
                  .collection('servicos_destaque')
                  .doc(id)
                  .update(upd);
              if (context.mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Destaque atualizado com sucesso!'),
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
    );
  }

  void _editarPremium(String id, Map<String, dynamic> dados) {
    final tituloC = TextEditingController(text: dados['titulo'] ?? '');
    final telefoneC = TextEditingController(text: dados['telefone'] ?? '');
    final cidadeC = TextEditingController(text: dados['cidade'] ?? '');
    final emailC = TextEditingController(text: dados['email'] ?? '');

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          "Editar Premium",
          style: TextStyle(color: diPertinRoxo, fontWeight: FontWeight.bold),
        ),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: tituloC,
                  decoration: const InputDecoration(
                    labelText: "Título",
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: telefoneC,
                  decoration: const InputDecoration(
                    labelText: "Telefone / WhatsApp",
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                CampoCidadeBrasilField(
                  controller: cidadeC,
                  decoration: const InputDecoration(
                    labelText: "Cidade",
                    hintText: "Digite para buscar o município",
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: emailC,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: "E-mail",
                    prefixIcon: Icon(Icons.email_outlined),
                    border: OutlineInputBorder(),
                  ),
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
            onPressed: () async {
              final upd = <String, dynamic>{
                'titulo': tituloC.text.trim(),
                'telefone': telefoneC.text.trim(),
                'cidade': cidadeC.text.trim(),
              };
              if (emailC.text.trim().isNotEmpty) {
                upd['email'] = emailC.text.trim();
              }
              await FirebaseFirestore.instance
                  .collection('telefones_premium')
                  .doc(id)
                  .update(upd);
              if (context.mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Premium atualizado com sucesso!'),
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
    );
  }

  void _editarEvento(String id, Map<String, dynamic> dados) {
    final tituloC = TextEditingController(text: dados['titulo'] ?? '');
    final localC = TextEditingController(text: dados['local'] ?? '');
    final dataEventoC = TextEditingController(text: dados['data_evento'] ?? '');
    final descC = TextEditingController(text: dados['descricao'] ?? '');
    final linkC = TextEditingController(text: dados['link_ingresso'] ?? '');
    final emailC = TextEditingController(text: dados['email'] ?? '');

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          "Editar Evento",
          style: TextStyle(color: diPertinRoxo, fontWeight: FontWeight.bold),
        ),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: tituloC,
                  decoration: const InputDecoration(
                    labelText: "Título do Evento",
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: localC,
                  decoration: const InputDecoration(
                    labelText: "Local",
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: dataEventoC,
                  decoration: const InputDecoration(
                    labelText: "Data do Evento (Ex: 25/Dez às 20h)",
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descC,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: "Descrição Completa",
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: linkC,
                  decoration: const InputDecoration(
                    labelText: "Link do Ingresso (Opcional)",
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: emailC,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: "E-mail",
                    prefixIcon: Icon(Icons.email_outlined),
                    border: OutlineInputBorder(),
                  ),
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
            onPressed: () async {
              final upd = <String, dynamic>{
                'titulo': tituloC.text.trim(),
                'local': localC.text.trim(),
                'data_evento': dataEventoC.text.trim(),
                'descricao': descC.text.trim(),
                'link_ingresso': linkC.text.trim(),
              };
              if (emailC.text.trim().isNotEmpty) {
                upd['email'] = emailC.text.trim();
              }
              await FirebaseFirestore.instance
                  .collection('eventos')
                  .doc(id)
                  .update(upd);
              if (context.mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Evento atualizado com sucesso!'),
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
    );
  }

  void _editarAchado(String id, Map<String, dynamic> dados) {
    final tituloC = TextEditingController(text: dados['titulo'] ?? '');
    final localC = TextEditingController(text: dados['local'] ?? '');
    final cidadeC = TextEditingController(text: dados['cidade'] ?? '');
    final descC = TextEditingController(text: dados['descricao'] ?? '');
    final contatoC = TextEditingController(text: dados['contato'] ?? '');
    final emailC = TextEditingController(text: dados['email'] ?? '');
    bool isPerdido = (dados['tipo'] ?? 'perdido') == 'perdido';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(
            "Editar Achado",
            style: TextStyle(color: diPertinRoxo, fontWeight: FontWeight.bold),
          ),
          content: SizedBox(
            width: 500,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: tituloC,
                    decoration: const InputDecoration(
                      labelText: "Título",
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: RadioListTile(
                          title: const Text("Perdido"),
                          value: true,
                          groupValue: isPerdido,
                          onChanged: (v) =>
                              setDialogState(() => isPerdido = v as bool),
                        ),
                      ),
                      Expanded(
                        child: RadioListTile(
                          title: const Text("Achado"),
                          value: false,
                          groupValue: isPerdido,
                          onChanged: (v) =>
                              setDialogState(() => isPerdido = v as bool),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: localC,
                    decoration: const InputDecoration(
                      labelText: "Local",
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  CampoCidadeBrasilField(
                    controller: cidadeC,
                    decoration: const InputDecoration(
                      labelText: "Cidade",
                      hintText: "Digite para buscar o município",
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: descC,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: "Descrição",
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: contatoC,
                    decoration: const InputDecoration(
                      labelText: "Telefone / Contato",
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: emailC,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: "E-mail",
                      prefixIcon: Icon(Icons.email_outlined),
                      border: OutlineInputBorder(),
                    ),
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
              onPressed: () async {
                final upd = <String, dynamic>{
                  'titulo': tituloC.text.trim(),
                  'tipo': isPerdido ? 'perdido' : 'encontrado',
                  'local': localC.text.trim(),
                  'cidade': cidadeC.text.trim(),
                  'descricao': descC.text.trim(),
                  'contato': contatoC.text.trim(),
                };
                if (emailC.text.trim().isNotEmpty) {
                  upd['email'] = emailC.text.trim();
                }
                await FirebaseFirestore.instance
                    .collection('achados')
                    .doc(id)
                    .update(upd);
                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Achado atualizado com sucesso!'),
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
    TextEditingController diasC = TextEditingController(text: "30");

    Uint8List? imagemBytes; // Arquivo de imagem para a Web
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
              setState(() => isLoading = true);

              try {
                double valorCobrado =
                    double.tryParse(valorC.text.replaceAll(',', '.')) ?? 0.0;
                int qtdDias = int.tryParse(diasC.text) ?? 30;
                DateTime dataCalculadaFim = DateTime.now().add(
                  Duration(days: qtdDias),
                );

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
                };

                // === A MÁGICA DO LIVRO CAIXA ENTRA AQUI ===
                if (valorCobrado > 0) {
                  dados['valor_diario'] = valorCobrado;
                  dados['nome_dono'] = donoC.text.trim();
                  dados['gera_receita'] = true;

                  // 1. Calcula o Total que o cliente pagou (Dias x Valor)
                  double valorTotalGerado = valorCobrado * qtdDias;

                  // 2. Salva no nosso Livro Caixa permanente (Coleção 'receitas_app')
                  await FirebaseFirestore.instance
                      .collection('receitas_app')
                      .add({
                        'tipo_receita':
                            tipoSelecionado, // Destaque, Premium, Evento...
                        'titulo_referencia': tituloC.text,
                        'nome_pagador': donoC.text.trim(),
                        'valor_total': valorTotalGerado,
                        'data_registro': FieldValue.serverTimestamp(),
                      });
                }
                // ==========================================

                // 3. Molda os dados de acordo com a categoria (Igual estava antes)
                if (emailC.text.trim().isNotEmpty) {
                  dados['email'] = emailC.text.trim();
                }

                if (tipoSelecionado == 'Vagas') {
                  dados.addAll({
                    'cargo': tituloC.text,
                    'empresa': empresaLocalC.text,
                    'cidade': cidadeC.text,
                    'descricao': descC.text,
                    'contato': contatoC.text,
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
                    'data_evento': dataLinkC.text,
                    'descricao': descC.text,
                    'link_ingresso': contatoC.text,
                    'imagem_url': urlImagem,
                    'data_fim': Timestamp.fromDate(
                      DateTime.now().add(const Duration(days: 7)),
                    ),
                  });
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
                    'cidade': cidadeC.text,
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
                    'cidade': cidadeC.text,
                    'tipo_contato': 'whatsapp',
                    'data_inicio': FieldValue.serverTimestamp(),
                    'data_vencimento': Timestamp.fromDate(dataCalculadaFim),
                  });
                  await FirebaseFirestore.instance
                      .collection('telefones_premium')
                      .add(dados);
                } else if (tipoSelecionado == 'Destaques') {
                  dados.addAll({
                    'titulo': tituloC.text,
                    'categoria': empresaLocalC.text,
                    'cidade': cidadeC.text,
                    'telefone': contatoC.text,
                    'data_inicio': FieldValue.serverTimestamp(),
                    'data_fim': Timestamp.fromDate(dataCalculadaFim),
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
                            labelText: "Cidade",
                            hintText: "Digite para buscar o município",
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

                      // === NOVOS CAMPOS DE COBRANÇA E TEMPO ===
                      if ([
                        'Eventos',
                        'Premium',
                        'Destaques',
                      ].contains(tipoSelecionado)) ...[
                        const Divider(),
                        const Text(
                          "Configuração e Cobrança",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.green,
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: donoC,
                          decoration: const InputDecoration(
                            labelText: "Nome do Cliente/Contratante",
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: diasC,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  labelText: "Qtd. de Dias",
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextField(
                                controller: valorC,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  labelText: "Valor diário (R\$)",
                                  border: OutlineInputBorder(),
                                  prefixText: "R\$ ",
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 15),
                      ],

                      // BOTÃO DE UPLOAD DE FOTO (Apenas para Eventos e Achados)
                      if (['Eventos', 'Achados'].contains(tipoSelecionado)) ...[
                        const Divider(),
                        const Text(
                          "Foto Principal:",
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 10),
                        InkWell(
                          onTap: escolherFoto,
                          child: Container(
                            height: 150,
                            width: double.infinity,
                            decoration: BoxDecoration(
                              color: Colors.grey[200],
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.grey),
                            ),
                            child: imagemBytes != null
                                ? ClipRRect(
                                    borderRadius: BorderRadius.circular(10),
                                    child: Image.memory(
                                      imagemBytes!,
                                      fit: BoxFit.cover,
                                    ),
                                  )
                                : const Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.add_a_photo,
                                        size: 40,
                                        color: Colors.grey,
                                      ),
                                      SizedBox(height: 5),
                                      Text(
                                        "Clique para anexar foto",
                                        style: TextStyle(color: Colors.grey),
                                      ),
                                    ],
                                  ),
                          ),
                        ),
                      ],
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

            bool estaVencido = false;
            if (campoDataVencimento != null &&
                dados[campoDataVencimento] != null) {
              DateTime venc = (dados[campoDataVencimento] as Timestamp)
                  .toDate();
              if (venc.isBefore(DateTime.now())) estaVencido = true;
            }

            return Card(
              elevation: 2,
              color: ativo ? Colors.white : Colors.grey[200],
              margin: const EdgeInsets.only(bottom: 10),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: ativo
                      ? (estaVencido ? Colors.orange : Colors.green)
                      : Colors.red,
                  child: Icon(
                    ativo
                        ? (estaVencido ? Icons.timer_off : Icons.check)
                        : Icons.block,
                    color: Colors.white,
                  ),
                ),
                title: Text(
                  dados[campoTitulo] ?? 'Sem Título',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(dados[campoSubtitulo] ?? ''),
                    if (campoDataVencimento != null)
                      Text(
                        "Vencimento: ${_formatarData(dados[campoDataVencimento])}",
                        style: TextStyle(
                          color: estaVencido ? Colors.red : Colors.grey,
                          fontWeight: estaVencido ? FontWeight.bold : null,
                        ),
                      ),
                  ],
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (botoesExtras != null) botoesExtras(doc.id, dados),
                    const SizedBox(width: 10),
                    // Botão de Ativar / Desativar
                    Switch(
                      value: ativo,
                      activeThumbColor: Colors.green,
                      onChanged: (val) => _toggleAtivo(colecao, doc.id, ativo),
                    ),
                    const SizedBox(width: 5),
                    // === NOVO BOTÃO DE DELETAR ===
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
