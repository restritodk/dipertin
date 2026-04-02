// Arquivo: lib/screens/atendimento_suporte_screen.dart

import 'package:depertin_web/utils/admin_perfil.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../widgets/sidebar_menu.dart';

class AtendimentoSuporteScreen extends StatefulWidget {
  const AtendimentoSuporteScreen({super.key});

  @override
  State<AtendimentoSuporteScreen> createState() =>
      _AtendimentoSuporteScreenState();
}

class _AtendimentoSuporteScreenState extends State<AtendimentoSuporteScreen> {
  final Color diPertinRoxo = const Color(0xFF6A1B9A);
  final Color diPertinLaranja = const Color(0xFFFF8F00);

  String? _chamadoSelecionadoId;
  String? _chamadoSelecionadoNome;
  final TextEditingController _mensagemController = TextEditingController();

  String _tipoUsuarioLogado = 'master';
  String _cidadeLogado = '';

  @override
  void initState() {
    super.initState();
    _buscarDadosDoAdmin();
  }

  Future<void> _buscarDadosDoAdmin() async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final docSnap = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (docSnap.exists) {
        final dados = docSnap.data()!;
        setState(() {
          _tipoUsuarioLogado = perfilAdministrativo(dados);
          _cidadeLogado = (dados['cidade'] ?? '').toString().toLowerCase();
        });
      }
    }
  }

  // === ENVIAR MENSAGEM COMO ADMIN ===
  Future<void> _enviarMensagem() async {
    if (_chamadoSelecionadoId == null ||
        _mensagemController.text.trim().isEmpty) {
      return;
    }

    String texto = _mensagemController.text.trim();
    _mensagemController.clear();

    String meuId = FirebaseAuth.instance.currentUser?.uid ?? 'admin';

    try {
      // 1. Salva a mensagem na subcoleção do cliente
      await FirebaseFirestore.instance
          .collection('suporte')
          .doc(_chamadoSelecionadoId)
          .collection('mensagens')
          .add({
            'texto': texto,
            'remetente_id': meuId,
            'data_envio': FieldValue.serverTimestamp(),
          });

      // 2. Atualiza o documento principal para o cliente ver que tem novidade
      await FirebaseFirestore.instance
          .collection('suporte')
          .doc(_chamadoSelecionadoId)
          .update({
            'ultima_mensagem': "Admin: $texto",
            'data_atualizacao': FieldValue.serverTimestamp(),
            'status': 'em_atendimento', // Tira da fila de espera
          });
    } catch (e) {
      debugPrint("Erro ao enviar: $e");
    }
  }

  // === ENCERRAR O CHAMADO ===
  Future<void> _encerrarChamado() async {
    if (_chamadoSelecionadoId == null) return;

    await FirebaseFirestore.instance
        .collection('suporte')
        .doc(_chamadoSelecionadoId)
        .update({
          'status': 'encerrado',
          'ultima_mensagem': 'Atendimento encerrado pelo suporte.',
          'data_atualizacao': FieldValue.serverTimestamp(),
        });

    await FirebaseFirestore.instance
        .collection('suporte')
        .doc(_chamadoSelecionadoId)
        .collection('mensagens')
        .add({
          'texto': '--- ATENDIMENTO ENCERRADO PELO SUPORTE ---',
          'remetente_id': 'sistema',
          'data_envio': FieldValue.serverTimestamp(),
        });

    setState(() {
      _chamadoSelecionadoId = null;
      _chamadoSelecionadoNome = null;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Chamado encerrado com sucesso!"),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  // === MODAL PARA EDITAR DADOS E RESETAR SENHA ===
  Future<void> _abrirModalEditarUsuario(
    String usuarioId,
    String nomeAtual,
  ) async {
    TextEditingController nomeC = TextEditingController();
    TextEditingController cpfC = TextEditingController();
    TextEditingController telefoneC = TextEditingController();
    TextEditingController cidadeC = TextEditingController();
    String emailUsuario = '';
    bool carregando = true;

    // Busca os dados completos do usuário no banco
    var doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(usuarioId)
        .get();
    if (doc.exists) {
      var dados = doc.data() as Map<String, dynamic>;
      nomeC.text = dados['nome'] ?? '';
      cpfC.text = dados['cpf'] ?? '';
      telefoneC.text = dados['telefone'] ?? '';
      cidadeC.text = dados['cidade'] ?? '';
      emailUsuario = dados['email'] ?? '';
    }
    setState(() => carregando = false);

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          "Ficha do Usuário",
          style: TextStyle(color: diPertinRoxo, fontWeight: FontWeight.bold),
        ),
        content: carregando
            ? const SizedBox(
                height: 100,
                child: Center(child: CircularProgressIndicator()),
              )
            : SingleChildScrollView(
                child: SizedBox(
                  width: 400,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: nomeC,
                        decoration: const InputDecoration(
                          labelText: "Nome Completo",
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.person),
                        ),
                      ),
                      const SizedBox(height: 15),
                      TextField(
                        controller: cpfC,
                        decoration: const InputDecoration(
                          labelText: "CPF",
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.badge),
                        ),
                      ),
                      const SizedBox(height: 15),
                      TextField(
                        controller: telefoneC,
                        decoration: const InputDecoration(
                          labelText: "Telefone",
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.phone),
                        ),
                      ),
                      const SizedBox(height: 15),
                      TextField(
                        controller: cidadeC,
                        decoration: const InputDecoration(
                          labelText: "Cidade",
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.location_city),
                        ),
                      ),

                      const SizedBox(height: 25),
                      const Divider(),
                      const SizedBox(height: 10),

                      // BOTÃO DE RESET DE SENHA (O Firebase faz o trabalho duro!)
                      if (emailUsuario.isNotEmpty)
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              try {
                                await FirebaseAuth.instance
                                    .sendPasswordResetEmail(
                                      email: emailUsuario,
                                    );
                                if (context.mounted) {
                                  Navigator.pop(context); // Fecha o modal
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        "Link de redefinição enviado para o e-mail do usuário!",
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
                              }
                            },
                            icon: const Icon(
                              Icons.lock_reset,
                              color: Colors.red,
                            ),
                            label: const Text(
                              "Enviar Link de Reset de Senha",
                              style: TextStyle(
                                color: Colors.red,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Colors.red),
                              padding: const EdgeInsets.symmetric(vertical: 15),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancelar", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: diPertinRoxo,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
            ),
            onPressed: () async {
              // Salva todas as alterações no banco de dados de uma vez
              await FirebaseFirestore.instance
                  .collection('users')
                  .doc(usuarioId)
                  .update({
                    'nome': nomeC.text.trim(),
                    'cpf': cpfC.text.trim(),
                    'telefone': telefoneC.text.trim(),
                    'cidade': cidadeC.text.trim(),
                  });

              if (context.mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text("Perfil atualizado com sucesso!"),
                    backgroundColor: Colors.green,
                  ),
                );
              }
            },
            child: const Text("Salvar Alterações"),
          ),
        ],
      ),
    );
  }

  // === INICIAR NOVA CONVERSA COM QUALQUER USUÁRIO ===
  Future<void> _abrirModalNovaConversa() async {
    showDialog(
      context: context,
      builder: (context) {
        String busca = '';
        return StatefulBuilder(
          builder: (context, setStateModal) {
            return AlertDialog(
              title: Text(
                "Iniciar Nova Conversa",
                style: TextStyle(
                  color: diPertinRoxo,
                  fontWeight: FontWeight.bold,
                ),
              ),
              content: SizedBox(
                width: 450,
                height: 500,
                child: Column(
                  children: [
                    // Campo de pesquisa
                    TextField(
                      decoration: const InputDecoration(
                        labelText: "Buscar usuário (Nome ou E-mail)",
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (val) =>
                          setStateModal(() => busca = val.toLowerCase().trim()),
                    ),
                    const SizedBox(height: 15),

                    // Lista de Usuários
                    Expanded(
                      child: StreamBuilder<QuerySnapshot>(
                        // Traz os usuários do banco (limitado para não pesar)
                        stream: FirebaseFirestore.instance
                            .collection('users')
                            .limit(100)
                            .snapshots(),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState ==
                              ConnectionState.waiting) {
                            return const Center(
                              child: CircularProgressIndicator(),
                            );
                          }
                          if (!snapshot.hasData ||
                              snapshot.data!.docs.isEmpty) {
                            return const Center(
                              child: Text("Nenhum usuário encontrado."),
                            );
                          }

                          // Filtra a lista pela busca e pela HIERARQUIA
                          var usuariosFiltrados = snapshot.data!.docs.where((
                            doc,
                          ) {
                            var dados = doc.data() as Map<String, dynamic>;
                            String nome = (dados['nome'] ?? '').toLowerCase();
                            String email = (dados['email'] ?? '').toLowerCase();
                            String cidadeDoUsuario = (dados['cidade'] ?? '')
                                .toLowerCase();
                            String role =
                                (dados['role'] ??
                                        dados['tipoUsuario'] ??
                                        'cliente')
                                    .toString()
                                    .toLowerCase();

                            // 1. O texto pesquisado bate com o nome ou e-mail?
                            bool bateuBusca =
                                nome.contains(busca) || email.contains(busca);
                            if (!bateuBusca) return false;

                            // 2. A REGRA DE OURO DA HIERARQUIA:
                            if (_tipoUsuarioLogado == 'master') {
                              return true;
                            } else if (_tipoUsuarioLogado == 'master_city') {
                              return cidadeDoUsuario == _cidadeLogado ||
                                  role == 'master';
                            }

                            return false; // Por segurança, se não for admin, não acha nada.
                          }).toList();

                          if (usuariosFiltrados.isEmpty) {
                            return const Center(
                              child: Text("Nenhum resultado para a busca."),
                            );
                          }

                          return ListView.builder(
                            itemCount: usuariosFiltrados.length,
                            itemBuilder: (context, index) {
                              var docUser = usuariosFiltrados[index];
                              var dadosUser =
                                  docUser.data() as Map<String, dynamic>;
                              String cargo =
                                  (dadosUser['role'] ??
                                          dadosUser['tipoUsuario'] ??
                                          'cliente')
                                      .toString()
                                      .toUpperCase();

                              return Card(
                                elevation: 1,
                                child: ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: diPertinRoxo.withOpacity(
                                      0.2,
                                    ),
                                    child: Icon(
                                      Icons.person,
                                      color: diPertinRoxo,
                                    ),
                                  ),
                                  title: Text(
                                    dadosUser['nome'] ?? 'Sem Nome',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  subtitle: Text(
                                    "$cargo \n${dadosUser['email'] ?? ''}",
                                  ),
                                  isThreeLine: true,
                                  trailing: const Icon(
                                    Icons.chat_bubble_outline,
                                    color: Colors.green,
                                  ),
                                  onTap: () async {
                                    // 1. Cria ou reabre o chamado para este usuário
                                    await FirebaseFirestore.instance
                                        .collection('suporte')
                                        .doc(docUser.id)
                                        .set({
                                          'cliente_id': docUser.id,
                                          'cliente_nome':
                                              dadosUser['nome'] ?? 'Usuário',
                                          'status': 'em_atendimento',
                                          'ultima_mensagem':
                                              'Atendimento iniciado pelo Admin',
                                          'data_atualizacao':
                                              FieldValue.serverTimestamp(),
                                        }, SetOptions(merge: true));

                                    // 2. Abre o chat na tela principal
                                    if (mounted) {
                                      setState(() {
                                        _chamadoSelecionadoId = docUser.id;
                                        _chamadoSelecionadoNome =
                                            dadosUser['nome'] ?? 'Usuário';
                                      });
                                      Navigator.pop(context); // Fecha o modal
                                    }
                                  },
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
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("Cancelar"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      body: Row(
        children: [
          const SidebarMenu(rotaAtual: '/atendimento_suporte'),

          // LADO ESQUERDO: LISTA DE CHAMADOS (Largura Fixa)
          Container(
            width: 350,
            color: Colors.white,
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 15,
                  ),
                  color: diPertinRoxo,
                  width: double.infinity,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        "Fila de Atendimento",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      // O NOVO BOTÃO AQUI!
                      IconButton(
                        tooltip: "Iniciar Nova Conversa",
                        icon: const Icon(
                          Icons.add_comment,
                          color: Colors.white,
                        ),
                        onPressed: _abrirModalNovaConversa,
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('suporte')
                        .orderBy('data_atualizacao', descending: true)
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                        return const Center(
                          child: Text(
                            "Nenhum chamado aberto.",
                            style: TextStyle(color: Colors.grey),
                          ),
                        );
                      }

                      var chamados = snapshot.data!.docs;

                      return ListView.separated(
                        itemCount: chamados.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          var chamado =
                              chamados[index].data() as Map<String, dynamic>;
                          String clienteId = chamados[index].id;
                          String status = chamado['status'] ?? '';
                          bool aguardando = status == 'aguardando_admin';
                          bool isSelecionado =
                              _chamadoSelecionadoId == clienteId;

                          return ListTile(
                            tileColor: isSelecionado
                                ? Colors.purple[50]
                                : Colors.white,
                            leading: CircleAvatar(
                              backgroundColor: aguardando
                                  ? Colors.red
                                  : (status == 'encerrado'
                                        ? Colors.grey
                                        : Colors.blue),
                              child: Icon(
                                aguardando ? Icons.warning : Icons.person,
                                color: Colors.white,
                                size: 20,
                              ),
                            ),
                            title: Text(
                              chamado['cliente_nome'] ?? 'Desconhecido',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            subtitle: Text(
                              chamado['ultima_mensagem'] ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onTap: () {
                              setState(() {
                                _chamadoSelecionadoId = clienteId;
                                _chamadoSelecionadoNome =
                                    chamado['cliente_nome'] ?? 'Cliente';
                              });
                            },
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),

          // LADO DIREITO: ÁREA DO CHAT E FERRAMENTAS
          Expanded(
            child: _chamadoSelecionadoId == null
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.forum, size: 100, color: Colors.grey[300]),
                        const SizedBox(height: 20),
                        const Text(
                          "Selecione um chamado ao lado para iniciar o atendimento.",
                          style: TextStyle(color: Colors.grey, fontSize: 18),
                        ),
                      ],
                    ),
                  )
                : Column(
                    children: [
                      // CABEÇALHO DO CHAT COM BOTÕES DE AÇÃO
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 15,
                        ),
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          border: Border(
                            bottom: BorderSide(color: Colors.black12),
                          ),
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              backgroundColor: diPertinRoxo,
                              child: Text(
                                _chamadoSelecionadoNome![0].toUpperCase(),
                                style: const TextStyle(color: Colors.white),
                              ),
                            ),
                            const SizedBox(width: 15),
                            Expanded(
                              child: Text(
                                _chamadoSelecionadoNome!,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            // BOTÃO DE EDITAR PERFIL COMPLETO
                            OutlinedButton.icon(
                              onPressed: () => _abrirModalEditarUsuario(
                                _chamadoSelecionadoId!,
                                _chamadoSelecionadoNome!,
                              ),
                              icon: const Icon(
                                Icons.manage_accounts,
                                color: Colors.blue,
                              ),
                              label: const Text(
                                "Editar Perfil / Senha",
                                style: TextStyle(color: Colors.blue),
                              ),
                            ),
                            const SizedBox(width: 10),
                            // BOTÃO DE ENCERRAR
                            ElevatedButton.icon(
                              onPressed: _encerrarChamado,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                foregroundColor: Colors.white,
                              ),
                              icon: const Icon(Icons.check_circle),
                              label: const Text("Encerrar Chamado"),
                            ),
                          ],
                        ),
                      ),

                      // MENSAGENS
                      Expanded(
                        child: StreamBuilder<QuerySnapshot>(
                          stream: FirebaseFirestore.instance
                              .collection('suporte')
                              .doc(_chamadoSelecionadoId)
                              .collection('mensagens')
                              .orderBy('data_envio', descending: true)
                              .snapshots(),
                          builder: (context, snapshot) {
                            if (!snapshot.hasData) {
                              return const Center(
                                child: CircularProgressIndicator(),
                              );
                            }

                            var mensagens = snapshot.data!.docs;

                            return ListView.builder(
                              reverse: true,
                              padding: const EdgeInsets.all(20),
                              itemCount: mensagens.length,
                              itemBuilder: (context, index) {
                                var msg =
                                    mensagens[index].data()
                                        as Map<String, dynamic>;

                                if (msg['remetente_id'] == 'sistema') {
                                  return Center(
                                    child: Container(
                                      margin: const EdgeInsets.symmetric(
                                        vertical: 10,
                                      ),
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: Colors.grey[300],
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Text(
                                        msg['texto'] ?? '',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.black54,
                                        ),
                                      ),
                                    ),
                                  );
                                }

                                bool souEuAdmin =
                                    msg['remetente_id'] !=
                                    _chamadoSelecionadoId;

                                return Align(
                                  alignment: souEuAdmin
                                      ? Alignment.centerRight
                                      : Alignment.centerLeft,
                                  child: Container(
                                    margin: const EdgeInsets.only(bottom: 10),
                                    padding: const EdgeInsets.all(15),
                                    constraints: const BoxConstraints(
                                      maxWidth: 400,
                                    ),
                                    decoration: BoxDecoration(
                                      color: souEuAdmin
                                          ? diPertinRoxo
                                          : Colors.white,
                                      borderRadius: BorderRadius.circular(15),
                                      boxShadow: const [
                                        BoxShadow(
                                          color: Colors.black12,
                                          blurRadius: 5,
                                        ),
                                      ],
                                    ),
                                    child: Text(
                                      msg['texto'] ?? '',
                                      style: TextStyle(
                                        color: souEuAdmin
                                            ? Colors.white
                                            : Colors.black87,
                                        fontSize: 15,
                                      ),
                                    ),
                                  ),
                                );
                              },
                            );
                          },
                        ),
                      ),

                      // BARRA DE DIGITAÇÃO
                      Container(
                        padding: const EdgeInsets.all(20),
                        color: Colors.white,
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _mensagemController,
                                decoration: InputDecoration(
                                  hintText:
                                      "Digite a sua resposta para o cliente...",
                                  filled: true,
                                  fillColor: Colors.grey[100],
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(30),
                                    borderSide: BorderSide.none,
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 20,
                                    vertical: 15,
                                  ),
                                ),
                                onSubmitted: (_) => _enviarMensagem(),
                              ),
                            ),
                            const SizedBox(width: 15),
                            CircleAvatar(
                              radius: 25,
                              backgroundColor: diPertinLaranja,
                              child: IconButton(
                                icon: const Icon(
                                  Icons.send,
                                  color: Colors.white,
                                ),
                                onPressed: _enviarMensagem,
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
    );
  }
}
