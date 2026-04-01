import 'package:depertin_web/widgets/botao_suporte_flutuante.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../widgets/sidebar_menu.dart';

class AdminCityScreen extends StatefulWidget {
  const AdminCityScreen({super.key});

  @override
  State<AdminCityScreen> createState() => _AdminCityScreenState();
}

class _AdminCityScreenState extends State<AdminCityScreen> {
  final Color diPertinRoxo = const Color(0xFF6A1B9A);
  final Color diPertinLaranja = const Color(0xFFFF8F00);

  List<String> _cidadesDisponiveis = [];

  @override
  void initState() {
    super.initState();
    _carregarCidades();
  }

  Future<void> _carregarCidades() async {
    try {
      var snapshot = await FirebaseFirestore.instance.collection('users').get();
      Set<String> cidades = {};
      for (var doc in snapshot.docs) {
        var dados = doc.data();
        if (dados['cidade'] != null &&
            dados['cidade'].toString().trim().isNotEmpty) {
          String c = dados['cidade'].toString().trim();
          c = c[0].toUpperCase() + c.substring(1).toLowerCase();
          cidades.add(c);
        }
      }
      setState(() {
        _cidadesDisponiveis = cidades.toList()..sort();
      });
    } catch (e) {
      debugPrint("Erro ao buscar cidades: $e");
    }
  }

  // === MODAL PARA PROMOVER OU EDITAR UM GERENTE ===
  void _mostrarModalAdminCity({
    String? docId,
    Map<String, dynamic>? dadosAtuais,
  }) {
    bool isEditando = docId != null;

    TextEditingController emailBuscaC = TextEditingController();
    TextEditingController addCidadeC = TextEditingController();

    Map<String, dynamic>? usuarioEncontrado = isEditando ? dadosAtuais : null;
    String? usuarioId = isEditando ? docId : null;

    List<String> cidadesGerenciadas = isEditando
        ? List<String>.from(dadosAtuais?['cidades_gerenciadas'] ?? [])
        : [];

    bool isLoading = false;
    bool isBuscando = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateModal) {
            // FUNÇÃO PARA BUSCAR O USUÁRIO PELO EMAIL
            Future<void> buscarUsuario() async {
              if (emailBuscaC.text.isEmpty) return;
              setStateModal(() {
                isBuscando = true;
                usuarioEncontrado = null;
              });

              try {
                QuerySnapshot snap = await FirebaseFirestore.instance
                    .collection('users')
                    .where('email', isEqualTo: emailBuscaC.text.trim())
                    .get();

                if (snap.docs.isNotEmpty) {
                  setStateModal(() {
                    usuarioEncontrado =
                        snap.docs.first.data() as Map<String, dynamic>;
                    usuarioId = snap.docs.first.id;
                    // Se ele já for gerente, carrega as cidades dele
                    cidadesGerenciadas = List<String>.from(
                      usuarioEncontrado?['cidades_gerenciadas'] ?? [],
                    );
                  });
                } else {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          "Nenhum usuário encontrado com este e-mail no aplicativo.",
                        ),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              } catch (e) {
                debugPrint("Erro: $e");
              } finally {
                setStateModal(() => isBuscando = false);
              }
            }

            void adicionarCidade() {
              String novaCidade = addCidadeC.text.trim().toLowerCase();
              if (novaCidade.isEmpty) return;

              if (cidadesGerenciadas.length >= 5) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      "Limite máximo de 5 cidades por gerente atingido!",
                    ),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }

              if (!cidadesGerenciadas.contains(novaCidade)) {
                setStateModal(() {
                  cidadesGerenciadas.add(novaCidade);
                  addCidadeC.clear();
                });
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text("Esta cidade já está na lista!"),
                    backgroundColor: Colors.orange,
                  ),
                );
              }
            }

            void removerCidade(String cidade) {
              setStateModal(() {
                cidadesGerenciadas.remove(cidade);
              });
            }

            // FUNÇÃO PARA SALVAR A PROMOÇÃO
            Future<void> salvarGerente() async {
              if (usuarioId == null || cidadesGerenciadas.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      "Busque um usuário e adicione pelo menos 1 cidade!",
                    ),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }

              setStateModal(() => isLoading = true);

              try {
                Map<String, dynamic> dadosUpdate = {
                  'tipoUsuario': 'admin_city',
                  'cidades_gerenciadas': cidadesGerenciadas,
                  'data_atualizacao': FieldValue.serverTimestamp(),
                };

                // Se for uma promoção nova, trava para ele trocar a senha no primeiro acesso ao painel
                if (!isEditando) {
                  dadosUpdate['primeiro_acesso'] = true;
                }

                await FirebaseFirestore.instance
                    .collection('users')
                    .doc(usuarioId)
                    .update(dadosUpdate);

                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        isEditando
                            ? "Cidades atualizadas!"
                            : "Usuário promovido a Gerente com sucesso!",
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
                setStateModal(() => isLoading = false);
              }
            }

            return AlertDialog(
              title: Text(
                isEditando
                    ? "Editar Cidades do Gerente"
                    : "Promover Usuário a AdminCity",
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
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (!isEditando) ...[
                        const Text(
                          "Busque a conta do funcionário para promovê-lo:",
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: emailBuscaC,
                                decoration: const InputDecoration(
                                  labelText: "E-mail cadastrado no app",
                                  border: OutlineInputBorder(),
                                  prefixIcon: Icon(Icons.search),
                                ),
                                onSubmitted: (_) => buscarUsuario(),
                              ),
                            ),
                            const SizedBox(width: 10),
                            ElevatedButton(
                              onPressed: isBuscando ? null : buscarUsuario,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: diPertinLaranja,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 18,
                                ),
                              ),
                              child: isBuscando
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Text(
                                      "Buscar",
                                      style: TextStyle(color: Colors.white),
                                    ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                      ],

                      if (usuarioEncontrado != null) ...[
                        Container(
                          padding: const EdgeInsets.all(15),
                          decoration: BoxDecoration(
                            color: Colors.green.shade50,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.green.shade200),
                          ),
                          child: Row(
                            children: [
                              CircleAvatar(
                                backgroundColor: Colors.green,
                                child: const Icon(
                                  Icons.person,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(width: 15),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      usuarioEncontrado!['nome'] ?? 'Sem Nome',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                                    Text(
                                      "Tipo atual: ${usuarioEncontrado!['tipoUsuario'] ?? 'cliente'}",
                                      style: TextStyle(
                                        color: Colors.grey.shade700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Divider(height: 30),

                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              "Praças de Atuação (Até 5 cidades)",
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            Text(
                              "${cidadesGerenciadas.length}/5",
                              style: TextStyle(
                                color: cidadesGerenciadas.length == 5
                                    ? Colors.red
                                    : Colors.green,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),

                        Row(
                          children: [
                            Expanded(
                              child: Autocomplete<String>(
                                optionsBuilder: (TextEditingValue text) {
                                  if (text.text.isEmpty) {
                                    return _cidadesDisponiveis;
                                  }
                                  return _cidadesDisponiveis.where(
                                    (String option) => option
                                        .toLowerCase()
                                        .contains(text.text.toLowerCase()),
                                  );
                                },
                                onSelected: (String selection) {
                                  addCidadeC.text = selection;
                                  adicionarCidade();
                                },
                                fieldViewBuilder:
                                    (
                                      context,
                                      controller,
                                      focusNode,
                                      onFieldSubmitted,
                                    ) {
                                      addCidadeC = controller;
                                      return TextField(
                                        controller: controller,
                                        focusNode: focusNode,
                                        decoration: const InputDecoration(
                                          labelText: "Digite o nome da cidade",
                                          border: OutlineInputBorder(),
                                        ),
                                        onSubmitted: (_) => adicionarCidade(),
                                      );
                                    },
                              ),
                            ),
                            const SizedBox(width: 10),
                            ElevatedButton(
                              onPressed: adicionarCidade,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: diPertinLaranja,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 18,
                                ),
                              ),
                              child: const Icon(Icons.add, color: Colors.white),
                            ),
                          ],
                        ),
                        const SizedBox(height: 15),

                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: cidadesGerenciadas.map((cidade) {
                            String cidFormatada =
                                cidade[0].toUpperCase() + cidade.substring(1);
                            return Chip(
                              label: Text(
                                cidFormatada,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              backgroundColor: diPertinRoxo,
                              deleteIcon: const Icon(
                                Icons.cancel,
                                color: Colors.white,
                                size: 18,
                              ),
                              onDeleted: () => removerCidade(cidade),
                            );
                          }).toList(),
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
                if (usuarioEncontrado != null)
                  ElevatedButton(
                    onPressed: isLoading ? null : salvarGerente,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
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
                            isEditando
                                ? "Salvar Alterações"
                                : "Promover Gerente",
                          ),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  // === REBAIXAR GERENTE (VOLTA A SER CLIENTE) ===
  Future<void> _rebaixarGerente(String id, String nome) async {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          "Remover Acesso",
          style: TextStyle(color: Colors.red),
        ),
        content: Text(
          "Tem certeza que deseja remover o acesso de $nome? A conta dele não será apagada, ele apenas voltará a ser um usuário comum no aplicativo.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancelar"),
          ),
          ElevatedButton(
            onPressed: () async {
              await FirebaseFirestore.instance
                  .collection('users')
                  .doc(id)
                  .update({
                    'tipoUsuario': 'cliente',
                    'cidades_gerenciadas':
                        FieldValue.delete(), // Limpa a lista de cidades
                  });
              if (ctx.mounted) Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text("Remover Acesso"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      body: Row(
        children: [
          const SidebarMenu(rotaAtual: '/admin_city'),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  color: Colors.white,
                  padding: const EdgeInsets.all(30),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Gestão de AdminCity",
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                              color: diPertinRoxo,
                            ),
                          ),
                          const Text(
                            "Gerentes regionais com acesso limitado ao painel operacional.",
                            style: TextStyle(color: Colors.grey, fontSize: 16),
                          ),
                        ],
                      ),
                      ElevatedButton.icon(
                        onPressed: () => _mostrarModalAdminCity(),
                        icon: const Icon(Icons.person_add, color: Colors.white),
                        label: const Text(
                          "Promover Gerente",
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: diPertinLaranja,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 15,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                Expanded(
                  child: StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('users')
                        .where('tipoUsuario', isEqualTo: 'admin_city')
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                        return const Center(
                          child: Text(
                            "Nenhum gerente cadastrado ainda.",
                            style: TextStyle(color: Colors.grey, fontSize: 16),
                          ),
                        );
                      }

                      var gerentes = snapshot.data!.docs;

                      return GridView.builder(
                        padding: const EdgeInsets.all(30),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              crossAxisSpacing: 20,
                              mainAxisSpacing: 20,
                              childAspectRatio: 1.5,
                            ),
                        itemCount: gerentes.length,
                        itemBuilder: (context, index) {
                          var doc = gerentes[index];
                          var dados = doc.data() as Map<String, dynamic>;
                          List<dynamic> cidadesRAW =
                              dados['cidades_gerenciadas'] ?? [];

                          return Card(
                            elevation: 4,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(15),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Row(
                                        children: [
                                          CircleAvatar(
                                            backgroundColor: diPertinRoxo
                                                .withOpacity(0.1),
                                            child: Icon(
                                              Icons.admin_panel_settings,
                                              color: diPertinRoxo,
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                dados['nome'] ?? 'Sem Nome',
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 16,
                                                ),
                                              ),
                                              Text(
                                                dados['telefone'] ??
                                                    'Sem telefone',
                                                style: const TextStyle(
                                                  color: Colors.grey,
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                      PopupMenuButton<String>(
                                        onSelected: (value) {
                                          if (value == 'editar') {
                                            _mostrarModalAdminCity(
                                              docId: doc.id,
                                              dadosAtuais: dados,
                                            );
                                          }
                                          if (value == 'apagar') {
                                            _rebaixarGerente(
                                              doc.id,
                                              dados['nome'] ?? 'Usuário',
                                            );
                                          }
                                        },
                                        itemBuilder: (BuildContext context) => [
                                          const PopupMenuItem(
                                            value: 'editar',
                                            child: Row(
                                              children: [
                                                Icon(
                                                  Icons.edit,
                                                  color: Colors.blue,
                                                  size: 20,
                                                ),
                                                SizedBox(width: 10),
                                                Text("Editar Cidades"),
                                              ],
                                            ),
                                          ),
                                          const PopupMenuItem(
                                            value: 'apagar',
                                            child: Row(
                                              children: [
                                                Icon(
                                                  Icons.person_off,
                                                  color: Colors.red,
                                                  size: 20,
                                                ),
                                                SizedBox(width: 10),
                                                Text(
                                                  "Remover Acesso",
                                                  style: TextStyle(
                                                    color: Colors.red,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                  const Divider(height: 30),
                                  const Text(
                                    "Praças Gerenciadas:",
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Expanded(
                                    child: Wrap(
                                      spacing: 5,
                                      runSpacing: 5,
                                      children: cidadesRAW.map((c) {
                                        return Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: diPertinLaranja.withOpacity(
                                              0.2,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              5,
                                            ),
                                            border: Border.all(
                                              color: diPertinLaranja,
                                            ),
                                          ),
                                          child: Text(
                                            c.toString().toUpperCase(),
                                            style: TextStyle(
                                              color: diPertinLaranja,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 10,
                                            ),
                                          ),
                                        );
                                      }).toList(),
                                    ),
                                  ),
                                  const SizedBox(height: 5),
                                  Row(
                                    children: [
                                      const Icon(
                                        Icons.email,
                                        size: 14,
                                        color: Colors.grey,
                                      ),
                                      const SizedBox(width: 5),
                                      Text(
                                        dados['email'] ?? 'Sem email',
                                        style: const TextStyle(
                                          color: Colors.grey,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
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
      floatingActionButton: const BotaoSuporteFlutuante(),
    );
  }
}
