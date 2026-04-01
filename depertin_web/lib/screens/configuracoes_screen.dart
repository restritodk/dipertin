import 'package:depertin_web/widgets/botao_suporte_flutuante.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../widgets/sidebar_menu.dart';
// import 'package:http/http.dart' as http;
// import 'dart:convert';

class ConfiguracoesScreen extends StatefulWidget {
  const ConfiguracoesScreen({super.key});

  @override
  State<ConfiguracoesScreen> createState() => _ConfiguracoesScreenState();
}

class _ConfiguracoesScreenState extends State<ConfiguracoesScreen> {
  final Color diPertinRoxo = const Color(0xFF6A1B9A);
  final Color diPertinLaranja = const Color(0xFFFF8F00);

  List<String> _cidadesSugeridas = ['Todas'];

  @override
  void initState() {
    super.initState();
    _carregarCidadesDoBanco();
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

  // === POP-UP PARA CRIAR NOVO PLANO (COMISSÃO DO APP) ===
  void _mostrarFormularioNovoPlano() {
    String publicoAlvo = 'lojista';
    String tipoCobranca = 'porcentagem';
    String frequencia = 'venda';
    String veiculo = 'Todos';
    TextEditingController nomePlanoC = TextEditingController();
    TextEditingController valorC = TextEditingController();
    String cidadeSelecionada = 'Todas';
    bool isLoading = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            Future<void> salvarPlano() async {
              if (nomePlanoC.text.isEmpty ||
                  valorC.text.isEmpty ||
                  cidadeSelecionada.isEmpty) {
                return;
              }
              setState(() => isLoading = true);
              try {
                double valor =
                    double.tryParse(valorC.text.replaceAll(',', '.')) ?? 0.0;
                Map<String, dynamic> dados = {
                  'nome': nomePlanoC.text.trim(),
                  'publico': publicoAlvo,
                  'tipo_cobranca': tipoCobranca,
                  'frequencia': frequencia,
                  'valor': valor,
                  'cidade': cidadeSelecionada.trim().toLowerCase(),
                  'ativo': true,
                  'data_criacao': FieldValue.serverTimestamp(),
                };
                if (publicoAlvo == 'entregador') dados['veiculo'] = veiculo;
                await FirebaseFirestore.instance
                    .collection('planos_taxas')
                    .add(dados);
                if (context.mounted) {
                  Navigator.pop(context);
                }
              } catch (e) {
                debugPrint("Erro: $e");
              } finally {
                setState(() => isLoading = false);
              }
            }

            return AlertDialog(
              title: Text(
                "Criar Plano/Taxa (Ganhos do App)",
                style: TextStyle(
                  color: diPertinRoxo,
                  fontWeight: FontWeight.bold,
                ),
              ),
              content: SizedBox(
                width: 450,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      DropdownButtonFormField<String>(
                        initialValue: publicoAlvo,
                        decoration: const InputDecoration(
                          labelText: "Para quem é este plano?",
                          border: OutlineInputBorder(),
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
                        onChanged: (val) => setState(() => publicoAlvo = val!),
                      ),
                      const SizedBox(height: 15),
                      TextField(
                        controller: nomePlanoC,
                        decoration: const InputDecoration(
                          labelText: "Nome do Plano",
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 15),
                      Autocomplete<String>(
                        initialValue: const TextEditingValue(text: 'Todas'),
                        optionsBuilder: (TextEditingValue text) {
                          if (text.text.isEmpty) return _cidadesSugeridas;
                          return _cidadesSugeridas.where(
                            (String option) => option.toLowerCase().contains(
                              text.text.toLowerCase(),
                            ),
                          );
                        },
                        onSelected: (String selection) =>
                            cidadeSelecionada = selection,
                        fieldViewBuilder:
                            (context, controller, focusNode, onFieldSubmitted) {
                              controller.addListener(
                                () => cidadeSelecionada = controller.text,
                              );
                              return TextField(
                                controller: controller,
                                focusNode: focusNode,
                                decoration: const InputDecoration(
                                  labelText: "Cidade Específica",
                                  border: OutlineInputBorder(),
                                  suffixIcon: Icon(Icons.search),
                                ),
                              );
                            },
                      ),
                      const SizedBox(height: 15),
                      if (publicoAlvo == 'entregador') ...[
                        DropdownButtonFormField<String>(
                          initialValue: veiculo,
                          decoration: const InputDecoration(
                            labelText: "Tipo de Veículo",
                            border: OutlineInputBorder(),
                          ),
                          items: ['Todos', 'Moto', 'Carro', 'Bicicleta']
                              .map(
                                (v) =>
                                    DropdownMenuItem(value: v, child: Text(v)),
                              )
                              .toList(),
                          onChanged: (val) => setState(() => veiculo = val!),
                        ),
                        const SizedBox(height: 15),
                      ],
                      DropdownButtonFormField<String>(
                        initialValue: frequencia,
                        decoration: const InputDecoration(
                          labelText: "Frequência da Cobrança",
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'venda',
                            child: Text("Por Venda"),
                          ),
                          DropdownMenuItem(
                            value: 'semana',
                            child: Text("Semanalmente"),
                          ),
                          DropdownMenuItem(
                            value: 'mes',
                            child: Text("Mensalmente"),
                          ),
                        ],
                        onChanged: (val) => setState(() => frequencia = val!),
                      ),
                      const SizedBox(height: 15),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: tipoCobranca,
                              decoration: const InputDecoration(
                                labelText: "Tipo de Cobrança",
                                border: OutlineInputBorder(),
                              ),
                              items: const [
                                DropdownMenuItem(
                                  value: 'porcentagem',
                                  child: Text("Porcentagem (%)"),
                                ),
                                DropdownMenuItem(
                                  value: 'fixo',
                                  child: Text("Valor Fixo (R\$)"),
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
                              decoration: InputDecoration(
                                labelText: "Valor",
                                border: const OutlineInputBorder(),
                                prefixText: tipoCobranca == 'fixo'
                                    ? "R\$ "
                                    : null,
                                suffixText: tipoCobranca == 'porcentagem'
                                    ? "%"
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
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("Cancelar"),
                ),
                ElevatedButton(
                  onPressed: isLoading ? null : salvarPlano,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: diPertinLaranja,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text("Salvar Plano"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // === FORMULÁRIO DE FRETES ===
  void _mostrarFormularioNovoFrete() {
    TextEditingController valorBaseC = TextEditingController();
    TextEditingController distBaseC = TextEditingController(text: '3');
    TextEditingController valorKmExtraC = TextEditingController();
    String cidadeSelecionada = 'Todas';
    String veiculo = 'Padrão (Moto/Bike)';
    bool isLoading = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            Future<void> salvarFrete() async {
              if (valorBaseC.text.isEmpty ||
                  distBaseC.text.isEmpty ||
                  valorKmExtraC.text.isEmpty ||
                  cidadeSelecionada.isEmpty) {
                return;
              }
              setState(() => isLoading = true);
              try {
                double valorBase =
                    double.tryParse(valorBaseC.text.replaceAll(',', '.')) ??
                    0.0;
                double distBase =
                    double.tryParse(distBaseC.text.replaceAll(',', '.')) ?? 0.0;
                double valorKmExtra =
                    double.tryParse(valorKmExtraC.text.replaceAll(',', '.')) ??
                    0.0;

                Map<String, dynamic> dados = {
                  'cidade': cidadeSelecionada.trim().toLowerCase(),
                  'veiculo': veiculo,
                  'valor_base': valorBase,
                  'distancia_base_km': distBase,
                  'valor_km_adicional': valorKmExtra,
                  'data_atualizacao': FieldValue.serverTimestamp(),
                };
                String docId =
                    "${cidadeSelecionada.trim().toLowerCase()}_${veiculo.contains('Carro') ? 'carro' : 'padrao'}";
                await FirebaseFirestore.instance
                    .collection('tabela_fretes')
                    .doc(docId)
                    .set(dados);
                if (context.mounted) Navigator.pop(context);
              } catch (e) {
                debugPrint("Erro: $e");
              } finally {
                setState(() => isLoading = false);
              }
            }

            return AlertDialog(
              title: Text(
                "Nova Regra de Frete",
                style: TextStyle(
                  color: diPertinRoxo,
                  fontWeight: FontWeight.bold,
                ),
              ),
              content: SizedBox(
                width: 450,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Autocomplete<String>(
                        initialValue: const TextEditingValue(text: 'Todas'),
                        optionsBuilder: (TextEditingValue text) {
                          if (text.text.isEmpty) return _cidadesSugeridas;
                          return _cidadesSugeridas.where(
                            (String option) => option.toLowerCase().contains(
                              text.text.toLowerCase(),
                            ),
                          );
                        },
                        onSelected: (String selection) =>
                            cidadeSelecionada = selection,
                        fieldViewBuilder:
                            (context, controller, focusNode, onFieldSubmitted) {
                              controller.addListener(
                                () => cidadeSelecionada = controller.text,
                              );
                              return TextField(
                                controller: controller,
                                focusNode: focusNode,
                                decoration: const InputDecoration(
                                  labelText: "Cidade Específica",
                                  border: OutlineInputBorder(),
                                  suffixIcon: Icon(Icons.search),
                                ),
                              );
                            },
                      ),
                      const SizedBox(height: 15),
                      DropdownButtonFormField<String>(
                        initialValue: veiculo,
                        decoration: const InputDecoration(
                          labelText: "Categoria do Frete",
                          border: OutlineInputBorder(),
                        ),
                        items: ['Padrão (Moto/Bike)', 'Cargas Maiores (Carro)']
                            .map(
                              (v) => DropdownMenuItem(value: v, child: Text(v)),
                            )
                            .toList(),
                        onChanged: (val) => setState(() => veiculo = val!),
                      ),
                      const SizedBox(height: 15),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: valorBaseC,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: "Valor Fixo Base",
                                border: OutlineInputBorder(),
                                prefixText: "R\$ ",
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: distBaseC,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: "Até quantos KM?",
                                border: OutlineInputBorder(),
                                suffixText: " km",
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 15),
                      TextField(
                        controller: valorKmExtraC,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: "Valor por KM Adicional",
                          border: OutlineInputBorder(),
                          prefixText: "+ R\$ ",
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
                  onPressed: isLoading ? null : salvarFrete,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: diPertinLaranja,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text("Salvar Matemática"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _deletarDocumento(String colecao, String id) async {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          "Apagar Registro",
          style: TextStyle(color: Colors.red),
        ),
        content: const Text("Tem certeza? Esta ação não pode ser desfeita."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancelar"),
          ),
          ElevatedButton(
            onPressed: () async {
              await FirebaseFirestore.instance
                  .collection(colecao)
                  .doc(id)
                  .delete();
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

  Widget _buildListaPlanos(String publico) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('planos_taxas')
          .where('publico', isEqualTo: publico)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        var planos = snapshot.data!.docs;
        return ListView.builder(
          padding: const EdgeInsets.all(20),
          itemCount: planos.length,
          itemBuilder: (context, index) {
            var dados = planos[index].data() as Map<String, dynamic>;
            bool isFixo = dados['tipo_cobranca'] == 'fixo';
            String valorTexto = isFixo
                ? "R\$ ${dados['valor']} por ${dados['frequencia']}"
                : "${dados['valor']}% por ${dados['frequencia']}";
            return Card(
              child: ListTile(
                leading: CircleAvatar(
                  child: Icon(
                    publico == 'lojista' ? Icons.store : Icons.motorcycle,
                  ),
                ),
                title: Text(
                  dados['nome'] ?? 'Sem Nome',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  "Local: ${dados['cidade'].toString().toUpperCase()}\nComissão: $valorTexto",
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  onPressed: () =>
                      _deletarDocumento('planos_taxas', planos[index].id),
                ),
              ),
            );
          },
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
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        var fretes = snapshot.data!.docs;
        return ListView.builder(
          padding: const EdgeInsets.all(20),
          itemCount: fretes.length,
          itemBuilder: (context, index) {
            var dados = fretes[index].data() as Map<String, dynamic>;
            double base = (dados['valor_base'] as num?)?.toDouble() ?? 0.0;
            double dist =
                (dados['distancia_base_km'] as num?)?.toDouble() ?? 0.0;
            double extra =
                (dados['valor_km_adicional'] as num?)?.toDouble() ?? 0.0;
            return Card(
              child: ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Colors.green,
                  child: Icon(Icons.map, color: Colors.white),
                ),
                title: Text(
                  "${dados['veiculo']} - ${dados['cidade'].toString().toUpperCase()}",
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  "R\$ ${base.toStringAsFixed(2)} (Até ${dist}km) + R\$ ${extra.toStringAsFixed(2)}/km extra",
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  onPressed: () =>
                      _deletarDocumento('tabela_fretes', fretes[index].id),
                ),
              ),
            );
          },
        );
      },
    );
  }

  // === NOVO: WIDGET DE INTEGRAÇÕES (GATEWAYS) ===
  Widget _buildGatewaysPagamento() {
    // Definimos os gateways disponíveis no DiPertin
    List<Map<String, String>> gatewaysDisponiveis = [
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
      // Vamos ler as configurações salvas no banco
      stream: FirebaseFirestore.instance
          .collection('gateways_pagamento')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        // Mapeia o que já está salvo no banco
        Map<String, Map<String, dynamic>> gatewaysSalvos = {};
        if (snapshot.hasData) {
          for (var doc in snapshot.data!.docs) {
            gatewaysSalvos[doc.id] = doc.data() as Map<String, dynamic>;
          }
        }

        return ListView.builder(
          padding: const EdgeInsets.all(30),
          itemCount: gatewaysDisponiveis.length,
          itemBuilder: (context, index) {
            var gw = gatewaysDisponiveis[index];
            var dados = gatewaysSalvos[gw['id']] ?? {};

            bool isAtivo = dados['ativo'] ?? false;
            TextEditingController publicKeyC = TextEditingController(
              text: dados['public_key'] ?? '',
            );
            TextEditingController accessTokenC = TextEditingController(
              text: dados['access_token'] ?? '',
            );

            return Card(
              elevation: isAtivo ? 8 : 2, // Fica "saltado" se estiver ativo
              margin: const EdgeInsets.only(bottom: 25),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
                side: BorderSide(
                  color: isAtivo ? Colors.green : Colors.transparent,
                  width: 2,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(25),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Image.network(
                              gw['logo']!,
                              height: 40,
                              width: 40,
                              errorBuilder: (c, e, s) =>
                                  const Icon(Icons.account_balance, size: 40),
                            ),
                            const SizedBox(width: 15),
                            Text(
                              gw['nome']!,
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        if (isAtivo)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.green,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Text(
                              "INTEGRAÇÃO ATIVA",
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const Divider(height: 30),

                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: publicKeyC,
                            decoration: const InputDecoration(
                              labelText: "Public Key (Chave Pública)",
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.vpn_key),
                            ),
                          ),
                        ),
                        const SizedBox(width: 15),
                        Expanded(
                          child: TextField(
                            controller: accessTokenC,
                            obscureText: true, // Esconde o token sensível
                            decoration: const InputDecoration(
                              labelText: "Access Token (Token Privado)",
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.lock),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        // BOTÃO DE SALVAR E ATIVAR
                        ElevatedButton.icon(
                          onPressed: () async {
                            if (publicKeyC.text.trim().isEmpty ||
                                accessTokenC.text.trim().isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    "Preencha as duas chaves para ativar!",
                                  ),
                                  backgroundColor: Colors.red,
                                ),
                              );
                              return;
                            }

                            // ABRIR O AVISO DE CARREGAMENTO
                            showDialog(
                              context: context,
                              barrierDismissible: false,
                              builder: (c) => const AlertDialog(
                                content: Row(
                                  children: [
                                    CircularProgressIndicator(),
                                    SizedBox(width: 20),
                                    Text("Salvando credenciais no sistema..."),
                                  ],
                                ),
                              ),
                            );

                            try {
                              // Desativa todos os gateways primeiro
                              var batch = FirebaseFirestore.instance.batch();
                              var todos = await FirebaseFirestore.instance
                                  .collection('gateways_pagamento')
                                  .get();
                              for (var doc in todos.docs) {
                                batch.update(doc.reference, {'ativo': false});
                              }
                              await batch.commit();

                              // Salva e ativa o que foi clicado
                              await FirebaseFirestore.instance
                                  .collection('gateways_pagamento')
                                  .doc(gw['id'])
                                  .set({
                                    'nome': gw['nome'],
                                    'public_key': publicKeyC.text.trim(),
                                    'access_token': accessTokenC.text.trim(),
                                    'ativo': true,
                                    'data_atualizacao':
                                        FieldValue.serverTimestamp(),
                                  });

                              // FECHAR O AVISO DE CARREGAMENTO
                              if (context.mounted) Navigator.pop(context);

                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      "${gw['nome']} agora é o método de pagamento oficial do app!",
                                    ),
                                    backgroundColor: Colors.green,
                                  ),
                                );
                              }
                            } catch (e) {
                              // FECHAR O AVISO DE CARREGAMENTO EM CASO DE ERRO NO FIREBASE
                              if (context.mounted) Navigator.pop(context);

                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      "Erro ao salvar no banco de dados: $e",
                                    ),
                                    backgroundColor: Colors.red,
                                  ),
                                );
                              }
                            }
                          },
                          icon: const Icon(
                            Icons.check_circle,
                            color: Colors.white,
                          ),
                          label: Text(
                            isAtivo ? "Atualizar Chaves" : "Salvar e Ativar",
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isAtivo
                                ? Colors.blue
                                : Colors.green,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 15,
                            ),
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
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4, // <--- Agora são 4 abas!
      child: Scaffold(
        backgroundColor: Colors.grey[100],
        body: Row(
          children: [
            const SidebarMenu(rotaAtual: '/configuracoes'),

            Expanded(
              child: Column(
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
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "Configurações Financeiras",
                                  style: TextStyle(
                                    fontSize: 28,
                                    fontWeight: FontWeight.bold,
                                    color: diPertinRoxo,
                                  ),
                                ),
                                const Text(
                                  "Gerencie comissões, planos e métodos de pagamento.",
                                  style: TextStyle(
                                    color: Colors.grey,
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                            Row(
                              children: [
                                ElevatedButton.icon(
                                  onPressed: _mostrarFormularioNovoFrete,
                                  icon: const Icon(
                                    Icons.map,
                                    color: Colors.white,
                                  ),
                                  label: const Text(
                                    "Nova Regra de Frete",
                                    style: TextStyle(color: Colors.white),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.green,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                ElevatedButton.icon(
                                  onPressed: _mostrarFormularioNovoPlano,
                                  icon: const Icon(
                                    Icons.percent,
                                    color: Colors.white,
                                  ),
                                  label: const Text(
                                    "Criar Comissão/Plano",
                                    style: TextStyle(color: Colors.white),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: diPertinLaranja,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        TabBar(
                          labelColor: diPertinRoxo,
                          unselectedLabelColor: Colors.grey,
                          indicatorColor: diPertinLaranja,
                          tabs: [
                            Tab(
                              icon: Icon(Icons.store),
                              text: "Comissões Lojistas",
                            ),
                            Tab(
                              icon: Icon(Icons.motorcycle),
                              text: "Comissões Entregadores",
                            ),
                            Tab(
                              icon: Icon(Icons.map),
                              text: "Tabela de Fretes",
                            ),
                            Tab(
                              icon: Icon(Icons.credit_card),
                              text: "Integrações Pagamentos",
                            ), // <--- A nova aba
                          ],
                        ),
                      ],
                    ),
                  ),

                  Expanded(
                    child: TabBarView(
                      children: [
                        _buildListaPlanos('lojista'),
                        _buildListaPlanos('entregador'),
                        _buildListaFretes(),
                        _buildGatewaysPagamento(), // <--- Tela dos Gateways
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        floatingActionButton: const BotaoSuporteFlutuante(),
      ),
    );
  }
}
