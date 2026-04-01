import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../widgets/sidebar_menu.dart';
import '../widgets/botao_suporte_flutuante.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final Color diPertinRoxo = const Color(0xFF6A1B9A);
  final Color diPertinLaranja = const Color(0xFFFF8F00);

  // Variáveis Operacionais (Pendências)
  int _lojasPendentes = 0;
  int _entregadoresPendentes = 0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _carregarPendencias();
  }

  // === 1. BUSCA AS PENDÊNCIAS RÁPIDAS ===
  Future<void> _carregarPendencias() async {
    try {
      var db = FirebaseFirestore.instance;
      var lojasP = await db
          .collection('users')
          .where('role', isEqualTo: 'lojista')
          .where('status_loja', isEqualTo: 'pendente')
          .count()
          .get();
      var entregadoresP = await db
          .collection('users')
          .where('role', isEqualTo: 'entregador')
          .where('entregador_status', isEqualTo: 'pendente')
          .count()
          .get();

      if (mounted) {
        setState(() {
          _lojasPendentes = lojasP.count ?? 0;
          _entregadoresPendentes = entregadoresP.count ?? 0;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // === 2. STREAM PARA OS CARDS DE RANKING (Do seu código) ===
  Stream<QuerySnapshot> getUsuariosStream(String? tipo) {
    if (tipo == null) {
      return FirebaseFirestore.instance.collection('users').snapshots();
    }
    // Suportando 'role' ou 'tipoUsuario' dependendo de como está no seu banco
    return FirebaseFirestore.instance
        .collection('users')
        .where('role', isEqualTo: tipo)
        .snapshots();
  }

  // === 3. BUSCA CIDADES PARA O RANKING (Do seu código) ===
  Future<List<String>> getCidadesCadastradas(String? tipo) async {
    try {
      Query query = FirebaseFirestore.instance.collection('users');
      if (tipo != null) query = query.where('role', isEqualTo: tipo);

      QuerySnapshot snapshot = await query.get(
        const GetOptions(source: Source.server),
      );
      Set<String> cidades = {};

      for (var doc in snapshot.docs) {
        try {
          Map<String, dynamic>? dados = doc.data() as Map<String, dynamic>?;
          if (dados != null) {
            String? nomeCidade =
                dados['cidade']?.toString() ?? dados['Cidade']?.toString();
            if (nomeCidade != null && nomeCidade.trim().isNotEmpty) {
              String cidFormatada = nomeCidade.trim();
              cidFormatada =
                  cidFormatada[0].toUpperCase() +
                  cidFormatada.substring(1).toLowerCase();
              cidades.add(cidFormatada);
            }
          }
        } catch (e) {}
      }
      return cidades.toList()..sort();
    } catch (e) {
      return [];
    }
  }

  // === WIDGET: CARD DE PENDÊNCIA (Operacional) ===
  Widget _buildPendenciaCard(
    String title,
    int count,
    IconData icon,
    Color color,
    String rota,
  ) {
    return Expanded(
      child: InkWell(
        onTap: () => Navigator.pushReplacementNamed(context, rota),
        borderRadius: BorderRadius.circular(15),
        child: Card(
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: color.withOpacity(0.15),
                  radius: 25,
                  child: Icon(icon, color: color),
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: Colors.grey,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        count.toString(),
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: color,
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

  // === WIDGET: CARD DE RANKING (Do seu código) ===
  Widget _cardContadorRanking(String titulo, String? tipo, Color cor) {
    return Expanded(
      child: StreamBuilder<QuerySnapshot>(
        stream: getUsuariosStream(tipo),
        builder: (context, snapshot) {
          String total = snapshot.hasData
              ? snapshot.data!.docs.length.toString()
              : "...";
          return InkWell(
            onTap: () => _dialogSelecionarCidade(titulo, tipo),
            child: Card(
              elevation: 4,
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: cor, width: 5)),
                ),
                child: Column(
                  children: [
                    Text(
                      titulo,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      total,
                      style: TextStyle(
                        fontSize: 30,
                        color: cor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 5),
                    const Text(
                      "Ver Ranking",
                      style: TextStyle(fontSize: 10, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // === DIÁLOGOS DE RANKING (Do seu código) ===
  void _dialogSelecionarCidade(String titulo, String? tipo) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );
    List<String> cidades = await getCidadesCadastradas(tipo);
    if (!mounted) return;
    Navigator.pop(context);

    final tipoBusca = tipo ?? 'cliente';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          "Filtrar $titulo",
          style: TextStyle(color: diPertinRoxo, fontWeight: FontWeight.bold),
        ),
        content: SizedBox(
          width: 350,
          height: 150,
          child: cidades.isEmpty
              ? const Text("Nenhuma cidade encontrada.")
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("Selecione a cidade para ver o ranking:"),
                    const SizedBox(height: 20),
                    DropdownMenu<String>(
                      width: 320,
                      menuHeight: 250,
                      enableFilter: true,
                      requestFocusOnTap: true,
                      label: const Text('Pesquisar...'),
                      leadingIcon: const Icon(Icons.search),
                      inputDecorationTheme: InputDecorationTheme(
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      dropdownMenuEntries: cidades
                          .map(
                            (String c) =>
                                DropdownMenuEntry<String>(value: c, label: c),
                          )
                          .toList(),
                      onSelected: (String? selecionada) {
                        if (selecionada != null) {
                          Navigator.pop(context);
                          _mostrarRanking(selecionada, tipoBusca);
                        }
                      },
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
      ),
    );
  }

  void _mostrarRanking(String cidade, String tipo) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(
            "Ranking de ${tipo.toUpperCase()}S - $cidade",
            style: TextStyle(color: diPertinRoxo, fontWeight: FontWeight.bold),
          ),
          content: SizedBox(
            width: 800,
            height: 500,
            child: FutureBuilder<QuerySnapshot>(
              future: FirebaseFirestore.instance
                  .collection('users')
                  .where('role', isEqualTo: tipo)
                  .get(const GetOptions(source: Source.server)),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(
                    child: Text("Nenhum usuário cadastrado."),
                  );
                }

                List<QueryDocumentSnapshot> usuarios = snapshot.data!.docs
                    .where((doc) {
                      try {
                        Map<String, dynamic> dados =
                            doc.data() as Map<String, dynamic>;
                        String? nomeCid = dados['cidade'] ?? dados['Cidade'];
                        if (nomeCid != null) {
                          return nomeCid.trim().toLowerCase() ==
                              cidade.toLowerCase();
                        }
                      } catch (e) {}
                      return false;
                    })
                    .toList();

                if (usuarios.isEmpty) {
                  return const Center(
                    child: Text("Nenhum usuário encontrado nesta cidade."),
                  );
                }

                usuarios.sort((a, b) {
                  int sA = 0, sB = 0;
                  try {
                    sA = a.get('totalConcluido');
                  } catch (e) {}
                  try {
                    sB = b.get('totalConcluido');
                  } catch (e) {}
                  return sB.compareTo(sA);
                });

                List<QueryDocumentSnapshot> top10 = usuarios.take(10).toList();
                List<QueryDocumentSnapshot> piores = usuarios
                    .where((doc) {
                      int s = 0;
                      try {
                        s = doc.get('totalConcluido');
                      } catch (e) {}
                      return s == 0;
                    })
                    .take(5)
                    .toList();

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Card(
                        color: Colors.green[50],
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                "🏆 Top 10 Concluídos",
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green,
                                ),
                              ),
                              const Divider(),
                              Expanded(
                                child: ListView.builder(
                                  itemCount: top10.length,
                                  itemBuilder: (context, index) {
                                    String nome = 'Sem Nome';
                                    int atv = 0;
                                    try {
                                      nome = top10[index].get('nome');
                                    } catch (e) {}
                                    try {
                                      atv = top10[index].get('totalConcluido');
                                    } catch (e) {}
                                    return ListTile(
                                      leading: CircleAvatar(
                                        child: Text("${index + 1}"),
                                      ),
                                      title: Text(nome),
                                      subtitle: Text("Atividades: $atv"),
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: Card(
                        color: Colors.red[50],
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                "⚠️ Top 5 Inativos",
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.red,
                                ),
                              ),
                              const Divider(),
                              Expanded(
                                child: ListView.builder(
                                  itemCount: piores.length,
                                  itemBuilder: (context, index) {
                                    String nome = 'Sem Nome';
                                    try {
                                      nome = piores[index].get('nome');
                                    } catch (e) {}
                                    return ListTile(
                                      leading: const Icon(
                                        Icons.warning,
                                        color: Colors.red,
                                      ),
                                      title: Text(nome),
                                      subtitle: const Text("Zero atividades"),
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Fechar"),
            ),
          ],
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
          const SidebarMenu(rotaAtual: '/dashboard'),

          Expanded(
            child: _isLoading
                ? Center(child: CircularProgressIndicator(color: diPertinRoxo))
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(40),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Painel SuperAdmin",
                          style: TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                            color: diPertinRoxo,
                          ),
                        ),
                        const Text(
                          "Bem-vindo ao centro de comando do DiPertin.",
                          style: TextStyle(fontSize: 16, color: Colors.grey),
                        ),
                        const SizedBox(height: 30),

                        // === SEÇÃO 1: AVISOS E PENDÊNCIAS ===
                        if (_lojasPendentes > 0 ||
                            _entregadoresPendentes > 0) ...[
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: Colors.orange[50],
                              borderRadius: BorderRadius.circular(15),
                              border: Border.all(color: Colors.orange[200]!),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.warning_amber_rounded,
                                  color: Colors.orange,
                                  size: 40,
                                ),
                                const SizedBox(width: 20),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        "Atenção Requerida!",
                                        style: TextStyle(
                                          color: Colors.orange,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 18,
                                        ),
                                      ),
                                      Text(
                                        "Existem aprovações pendentes aguardando sua análise para entrarem no aplicativo.",
                                        style: TextStyle(
                                          color: Colors.orange[800],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 15),
                          Row(
                            children: [
                              if (_lojasPendentes > 0)
                                _buildPendenciaCard(
                                  "Lojas Pendentes",
                                  _lojasPendentes,
                                  Icons.store,
                                  Colors.red,
                                  '/lojas',
                                ),
                              if (_lojasPendentes > 0 &&
                                  _entregadoresPendentes > 0)
                                const SizedBox(width: 20),
                              if (_entregadoresPendentes > 0)
                                _buildPendenciaCard(
                                  "Entregadores Pendentes",
                                  _entregadoresPendentes,
                                  Icons.motorcycle,
                                  Colors.red,
                                  '/entregadores',
                                ),
                            ],
                          ),
                          const SizedBox(height: 40),
                        ],

                        // === SEÇÃO 2: RANKINGS E DESEMPENHO ===
                        const Text(
                          "Desempenho e Rankings",
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 15),
                        Row(
                          children: [
                            _cardContadorRanking(
                              "Total Usuários",
                              null,
                              Colors.blue,
                            ),
                            const SizedBox(width: 15),
                            _cardContadorRanking(
                              "Clientes",
                              "cliente",
                              Colors.green,
                            ),
                            const SizedBox(width: 15),
                            _cardContadorRanking(
                              "Lojistas",
                              "lojista",
                              diPertinLaranja,
                            ),
                            const SizedBox(width: 15),
                            _cardContadorRanking(
                              "Entregadores",
                              "entregador",
                              Colors.red,
                            ),
                          ],
                        ),
                        const SizedBox(height: 40),

                        // === SEÇÃO 3: VISÃO FINANCEIRA ===
                        const Text(
                          "Módulo Financeiro",
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 15),
                        InkWell(
                          onTap: () => Navigator.pushReplacementNamed(
                            context,
                            '/financeiro',
                          ),
                          child: Card(
                            elevation: 4,
                            color: Colors.green[50],
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Container(
                              padding: const EdgeInsets.all(20),
                              decoration: const BoxDecoration(
                                border: Border(
                                  top: BorderSide(
                                    color: Colors.green,
                                    width: 5,
                                  ),
                                ),
                              ),
                              child: const Row(
                                children: [
                                  Icon(
                                    Icons.monetization_on,
                                    color: Colors.green,
                                    size: 40,
                                  ),
                                  SizedBox(width: 20),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          "Visão Financeira",
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 18,
                                            color: Colors.green,
                                          ),
                                        ),
                                        SizedBox(height: 5),
                                        Text(
                                          "Gerencie receitas de Destaques, Vitrine, Telefones Premium e Assinaturas.",
                                          style: TextStyle(
                                            color: Colors.black87,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Icon(
                                    Icons.arrow_forward_ios,
                                    color: Colors.green,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 50),
                      ],
                    ),
                  ),
          ),
        ],
      ),
      floatingActionButton: const BotaoSuporteFlutuante(),
    );
  }
}
