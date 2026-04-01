import 'dart:typed_data';
import 'package:depertin_web/widgets/botao_suporte_flutuante.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import '../widgets/sidebar_menu.dart';

class BannersScreen extends StatefulWidget {
  const BannersScreen({super.key});

  @override
  State<BannersScreen> createState() => _BannersScreenState();
}

class _BannersScreenState extends State<BannersScreen> {
  final Color diPertinRoxo = const Color(0xFF6A1B9A);
  final Color diPertinLaranja = const Color(0xFFFF8F00);

  // === MODAL PARA CRIAR OU EDITAR BANNER ===
  void _mostrarModalBanner({
    String? bannerId,
    Map<String, dynamic>? dadosAtuais,
  }) {
    bool isEditando = bannerId != null;

    Uint8List? novaImagemBytes;

    // Simplificamos a leitura tirando o excesso de "?"
    String? imagemAtualUrl = dadosAtuais != null
        ? dadosAtuais['url_imagem']
        : null;

    TextEditingController linkC = TextEditingController(
      text: dadosAtuais != null ? dadosAtuais['link_destino'] ?? '' : '',
    );
    TextEditingController cidadeC = TextEditingController(
      text: dadosAtuais != null ? dadosAtuais['cidade'] ?? 'Todas' : 'Todas',
    );
    TextEditingController valorC = TextEditingController(
      text: dadosAtuais != null
          ? (dadosAtuais['valor']?.toString() ?? '0')
          : '0',
    );

    String tipoCobranca = dadosAtuais != null
        ? (dadosAtuais['tipo_cobranca'] ?? 'dia')
        : 'dia';

    DateTime dataInicio =
        dadosAtuais != null && dadosAtuais['data_inicio'] != null
        ? (dadosAtuais['data_inicio'] as Timestamp).toDate()
        : DateTime.now();

    DateTime dataFim = dadosAtuais != null && dadosAtuais['data_fim'] != null
        ? (dadosAtuais['data_fim'] as Timestamp).toDate()
        : DateTime.now().add(const Duration(days: 7));

    bool isLoading = false;

    showDialog(
      context: context,
      // ... o resto do código continua igual daqui para baixo
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            // Escolher nova imagem
            Future<void> escolherImagem() async {
              final ImagePicker picker = ImagePicker();
              final XFile? image = await picker.pickImage(
                source: ImageSource.gallery,
              );
              if (image != null) {
                var bytes = await image.readAsBytes();
                setState(() => novaImagemBytes = bytes);
              }
            }

            // Selecionar Datas
            Future<void> escolherData(bool isInicio) async {
              DateTime? selecionada = await showDatePicker(
                context: context,
                initialDate: isInicio ? dataInicio : dataFim,
                firstDate: DateTime(2024),
                lastDate: DateTime(2030),
              );
              if (selecionada != null) {
                setState(() {
                  if (isInicio) {
                    dataInicio = selecionada;
                  } else {
                    dataFim = selecionada;
                  }
                });
              }
            }

            // Salvar no Banco
            Future<void> salvarBanner() async {
              if (!isEditando && novaImagemBytes == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text("Escolha uma imagem para o novo banner!"),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }

              setState(() => isLoading = true);

              try {
                String urlDownload = imagemAtualUrl ?? '';

                // Se escolheu imagem nova, faz upload
                if (novaImagemBytes != null) {
                  String nomeArquivo =
                      'banner_${DateTime.now().millisecondsSinceEpoch}.jpg';
                  Reference ref = FirebaseStorage.instance.ref().child(
                    'banners_vitrine/$nomeArquivo',
                  );
                  await ref.putData(novaImagemBytes!);
                  urlDownload = await ref.getDownloadURL();
                }

                double valorConvertido =
                    double.tryParse(valorC.text.replaceAll(',', '.')) ?? 0.0;

                Map<String, dynamic> dadosSalvar = {
                  'url_imagem': urlDownload,
                  'link_destino': linkC.text.trim(),
                  'cidade': cidadeC.text.trim().toLowerCase(),
                  'valor': valorConvertido,
                  'tipo_cobranca': tipoCobranca,
                  'data_inicio': dataInicio,
                  'data_fim': dataFim,
                  'ativo': true,
                  'data_atualizacao': FieldValue.serverTimestamp(),
                };

                if (isEditando) {
                  await FirebaseFirestore.instance
                      .collection('banners')
                      .doc(bannerId)
                      .update(dadosSalvar);
                } else {
                  dadosSalvar['data_criacao'] = FieldValue.serverTimestamp();
                  await FirebaseFirestore.instance
                      .collection('banners')
                      .add(dadosSalvar);
                }

                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        isEditando ? "Banner atualizado!" : "Banner publicado!",
                      ),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text("Erro: $e"),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              } finally {
                setState(() => isLoading = false);
              }
            }

            String formatarData(DateTime data) =>
                "${data.day.toString().padLeft(2, '0')}/${data.month.toString().padLeft(2, '0')}/${data.year}";

            return AlertDialog(
              title: Text(
                isEditando ? "Editar Banner" : "Novo Banner Promocional",
                style: TextStyle(
                  color: diPertinRoxo,
                  fontWeight: FontWeight.bold,
                ),
              ),
              content: SizedBox(
                width: 500,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // ÁREA DA IMAGEM
                      GestureDetector(
                        onTap: escolherImagem,
                        child: Container(
                          height: 150,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: Colors.grey[200],
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.grey[400]!),
                          ),
                          child: novaImagemBytes != null
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: Image.memory(
                                    novaImagemBytes!,
                                    fit: BoxFit.cover,
                                  ),
                                )
                              : (imagemAtualUrl != null
                                    ? ClipRRect(
                                        borderRadius: BorderRadius.circular(10),
                                        child: Image.network(
                                          imagemAtualUrl,
                                          fit: BoxFit.cover,
                                        ),
                                      )
                                    : const Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            Icons.add_photo_alternate,
                                            size: 50,
                                            color: Colors.grey,
                                          ),
                                          SizedBox(height: 10),
                                          Text(
                                            "Clique para adicionar a imagem",
                                            style: TextStyle(
                                              color: Colors.grey,
                                            ),
                                          ),
                                        ],
                                      )),
                        ),
                      ),
                      const SizedBox(height: 15),

                      TextField(
                        controller: cidadeC,
                        decoration: const InputDecoration(
                          labelText: "Cidade (Ex: Todas, Rondonópolis)",
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 15),
                      TextField(
                        controller: linkC,
                        decoration: const InputDecoration(
                          labelText: "Link ou ID da Loja destino",
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 15),

                      // ÁREA DE DATAS
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => escolherData(true),
                              icon: const Icon(Icons.calendar_today, size: 16),
                              label: Text(
                                "Início: ${formatarData(dataInicio)}",
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => escolherData(false),
                              icon: const Icon(Icons.event_busy, size: 16),
                              label: Text("Fim: ${formatarData(dataFim)}"),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 15),

                      // ÁREA FINANCEIRA
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: tipoCobranca,
                              decoration: const InputDecoration(
                                labelText: "Cobrar por",
                                border: OutlineInputBorder(),
                              ),
                              items: const [
                                DropdownMenuItem(
                                  value: 'dia',
                                  child: Text("Por Dia"),
                                ),
                                DropdownMenuItem(
                                  value: 'hora',
                                  child: Text("Por Hora"),
                                ),
                                DropdownMenuItem(
                                  value: 'fixo',
                                  child: Text("Valor Fixo"),
                                ),
                              ],
                              onChanged: (val) =>
                                  setState(() => tipoCobranca = val!),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: valorC,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: "Valor (R\$)",
                                border: OutlineInputBorder(),
                                prefixText: "R\$ ",
                              ),
                            ),
                          ),
                        ],
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
                  onPressed: isLoading ? null : salvarBanner,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isEditando ? Colors.blue : Colors.green,
                    foregroundColor: Colors.white,
                  ),
                  child: isLoading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : Text(
                          isEditando ? "Salvar Alterações" : "Publicar Banner",
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // === APAGAR BANNER ===
  Future<void> _deletarBanner(String id, String urlImagem) async {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Apagar Banner", style: TextStyle(color: Colors.red)),
        content: const Text("Tem certeza? Ele sairá do ar imediatamente."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancelar"),
          ),
          ElevatedButton(
            onPressed: () async {
              try {
                await FirebaseFirestore.instance
                    .collection('banners')
                    .doc(id)
                    .delete();
                await FirebaseStorage.instance.refFromURL(urlImagem).delete();
              } catch (e) {
                debugPrint("Erro ao apagar: $e");
              }
              if (ctx.mounted) Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text("Apagar"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      // BOTÕES FLUTUANTES (SUPORTE + NOVO BANNER)
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // NOSSO BOTÃO DE SUPORTE
          const BotaoSuporteFlutuante(),
          const SizedBox(height: 15),

          // O BOTÃO DE NOVO BANNER
          FloatingActionButton.extended(
            heroTag: 'btn_banners',
            onPressed: () => _mostrarModalBanner(),
            backgroundColor: diPertinLaranja,
            icon: const Icon(Icons.add_photo_alternate, color: Colors.white),
            label: const Text(
              "Novo Banner",
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
      body: Row(
        children: [
          const SidebarMenu(rotaAtual: '/banners'),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  color: Colors.white,
                  padding: const EdgeInsets.all(30),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Vitrine Publicitária",
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: diPertinRoxo,
                        ),
                      ),
                      const Text(
                        "Clique em um banner para editar valores, agendamentos e datas.",
                        style: TextStyle(color: Colors.grey, fontSize: 16),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('banners')
                        .orderBy('data_criacao', descending: true)
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                        return const Center(
                          child: Text("Nenhum banner publicado na vitrine."),
                        );
                      }

                      var banners = snapshot.data!.docs;

                      return GridView.builder(
                        padding: const EdgeInsets.all(30),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              crossAxisSpacing: 20,
                              mainAxisSpacing: 20,
                              childAspectRatio: 16 / 9,
                            ),
                        itemCount: banners.length,
                        itemBuilder: (context, index) {
                          var doc = banners[index];
                          var dados = doc.data() as Map<String, dynamic>;

                          String imageUrl = dados['url_imagem'] ?? '';
                          String cidade = dados['cidade'] == 'todas'
                              ? 'Global'
                              : dados['cidade'].toString().toUpperCase();
                          String valor =
                              "R\$ ${dados['valor']?.toString() ?? '0.00'} / ${dados['tipo_cobranca'] ?? 'dia'}";

                          // MÁGICA: O Card inteiro agora é um botão para editar
                          return InkWell(
                            onTap: () => _mostrarModalBanner(
                              bannerId: doc.id,
                              dadosAtuais: dados,
                            ),
                            borderRadius: BorderRadius.circular(15),
                            child: Card(
                              elevation: 4,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(15),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  Image.network(imageUrl, fit: BoxFit.cover),
                                  Container(
                                    decoration: const BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [
                                          Colors.black87,
                                          Colors.transparent,
                                        ],
                                        begin: Alignment.bottomCenter,
                                        end: Alignment.center,
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    bottom: 15,
                                    left: 15,
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: diPertinLaranja,
                                            borderRadius: BorderRadius.circular(
                                              5,
                                            ),
                                          ),
                                          child: Text(
                                            "Local: $cidade",
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 5),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.green,
                                            borderRadius: BorderRadius.circular(
                                              5,
                                            ),
                                          ),
                                          child: Text(
                                            valor,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Positioned(
                                    top: 10,
                                    right: 10,
                                    child: CircleAvatar(
                                      backgroundColor: Colors.white,
                                      child: IconButton(
                                        icon: const Icon(
                                          Icons.delete,
                                          color: Colors.red,
                                        ),
                                        onPressed: () {
                                          _deletarBanner(doc.id, imageUrl);
                                        },
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
