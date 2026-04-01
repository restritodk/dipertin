import 'package:depertin_web/widgets/botao_suporte_flutuante.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../widgets/sidebar_menu.dart';

class FinanceiroScreen extends StatefulWidget {
  const FinanceiroScreen({super.key});

  @override
  State<FinanceiroScreen> createState() => _FinanceiroScreenState();
}

class _FinanceiroScreenState extends State<FinanceiroScreen> {
  final Color diPertinRoxo = const Color(0xFF6A1B9A);
  final Color diPertinLaranja = const Color(0xFFFF8F00);

  DateTime? _dataInicioFiltro;
  DateTime? _dataFimFiltro;

  Future<void> _escolherPeriodo() async {
    DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: _dataInicioFiltro != null && _dataFimFiltro != null
          ? DateTimeRange(start: _dataInicioFiltro!, end: _dataFimFiltro!)
          : null,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: diPertinLaranja,
              onPrimary: Colors.white,
              onSurface: diPertinRoxo,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _dataInicioFiltro = picked.start;
        _dataFimFiltro = DateTime(
          picked.end.year,
          picked.end.month,
          picked.end.day,
          23,
          59,
          59,
        );
      });
    }
  }

  // === NOVO: MODAL DE LANÇAMENTO MANUAL ===
  void _mostrarModalNovaReceita() {
    TextEditingController tituloC = TextEditingController();
    TextEditingController donoC = TextEditingController();
    TextEditingController valorC = TextEditingController();
    String categoria = 'Assinaturas';
    bool isLoading = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            Future<void> salvarReceita() async {
              if (tituloC.text.isEmpty ||
                  donoC.text.isEmpty ||
                  valorC.text.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text("Preencha todos os campos!"),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }
              setState(() => isLoading = true);

              try {
                double valor =
                    double.tryParse(valorC.text.replaceAll(',', '.')) ?? 0.0;

                // Salva na exata estrutura que o sistema já lê
                await FirebaseFirestore.instance
                    .collection('receitas_app')
                    .add({
                      'titulo_referencia': tituloC.text.trim(),
                      'nome_pagador': donoC.text.trim(),
                      'tipo_receita': categoria,
                      'valor_total': valor,
                      'data_registro': FieldValue.serverTimestamp(),
                    });

                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text("Receita registrada com sucesso!"),
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

            return AlertDialog(
              title: Text(
                "Lançar Receita Manual",
                style: TextStyle(
                  color: diPertinRoxo,
                  fontWeight: FontWeight.bold,
                ),
              ),
              content: SizedBox(
                width: 400,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        "Use isso para registrar pagamentos feitos direto via Pix/Dinheiro fora do sistema automático.",
                        style: TextStyle(color: Colors.grey, fontSize: 13),
                      ),
                      const SizedBox(height: 20),

                      TextField(
                        controller: tituloC,
                        decoration: const InputDecoration(
                          labelText: "Referência (Ex: Mensalidade VIP)",
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 15),
                      TextField(
                        controller: donoC,
                        decoration: const InputDecoration(
                          labelText:
                              "Nome de quem pagou (Ex: Lanchonete do Zé)",
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 15),

                      Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: DropdownButtonFormField<String>(
                              initialValue: categoria,
                              decoration: const InputDecoration(
                                labelText: "Categoria",
                                border: OutlineInputBorder(),
                              ),
                              items: const [
                                DropdownMenuItem(
                                  value: 'Assinaturas',
                                  child: Text("Assinatura"),
                                ),
                                DropdownMenuItem(
                                  value: 'Comissões Lojas',
                                  child: Text("Comissão Loja"),
                                ),
                                DropdownMenuItem(
                                  value: 'Taxas Entregadores',
                                  child: Text("Taxa Entregador"),
                                ),
                                DropdownMenuItem(
                                  value: 'Destaques',
                                  child: Text("Destaque/Banner"),
                                ),
                                DropdownMenuItem(
                                  value: 'Premium',
                                  child: Text("Telefone Premium"),
                                ),
                                DropdownMenuItem(
                                  value: 'Eventos',
                                  child: Text("Eventos Pagos"),
                                ),
                                DropdownMenuItem(
                                  value: 'Outros',
                                  child: Text("Outros"),
                                ),
                              ],
                              onChanged: (val) =>
                                  setState(() => categoria = val!),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            flex: 1,
                            child: TextField(
                              controller: valorC,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: "Valor (R\$)",
                                border: OutlineInputBorder(),
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
                  onPressed: isLoading ? null : salvarReceita,
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
                      : const Text("Registrar Pagamento"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<Map<String, dynamic>> _buscarDadosFinanceiros() async {
    double totalGeral = 0;
    double totalComissoes = 0;
    double totalTaxasEntrega = 0;
    double totalAssinaturas = 0;
    double totalEventos = 0;
    double totalPremium = 0;
    double totalDestaques = 0;

    List<Map<String, dynamic>> historico = [];

    var receitas = await FirebaseFirestore.instance
        .collection('receitas_app')
        .orderBy('data_registro', descending: true)
        .get();

    for (var doc in receitas.docs) {
      var d = doc.data();
      Timestamp? tsRegistro = d['data_registro'] as Timestamp?;
      if (tsRegistro == null) continue;

      DateTime dataRegistro = tsRegistro.toDate();

      if (_dataInicioFiltro != null && _dataFimFiltro != null) {
        if (dataRegistro.isBefore(_dataInicioFiltro!) ||
            dataRegistro.isAfter(_dataFimFiltro!)) {
          continue;
        }
      }

      double valor = (d['valor_total'] ?? 0).toDouble();
      String tipo = d['tipo_receita'] ?? 'Outros';

      totalGeral += valor;

      if (tipo == 'Eventos') {
        totalEventos += valor;
      } else if (tipo == 'Premium') {
        totalPremium += valor;
      } else if (tipo == 'Destaques' || tipo == 'Banners') {
        totalDestaques += valor;
      } else if (tipo == 'Comissões Lojas') {
        totalComissoes += valor;
      } else if (tipo == 'Taxas Entregadores') {
        totalTaxasEntrega += valor;
      } else if (tipo == 'Assinaturas') {
        totalAssinaturas += valor;
      }

      historico.add({
        'tipo': tipo,
        'titulo': d['titulo_referencia'] ?? 'Sem título',
        'dono': d['nome_pagador'] ?? 'Não informado',
        'valor': valor,
        'data': dataRegistro,
      });
    }

    return {
      'totalGeral': totalGeral,
      'totalComissoes': totalComissoes,
      'totalTaxasEntrega': totalTaxasEntrega,
      'totalAssinaturas': totalAssinaturas,
      'totalEventos': totalEventos,
      'totalPremium': totalPremium,
      'totalDestaques': totalDestaques,
      'historico': historico,
    };
  }

  String _formatarData(DateTime d) {
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} às ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      body: Row(
        children: [
          const SidebarMenu(rotaAtual: '/financeiro'),

          Expanded(
            child: FutureBuilder<Map<String, dynamic>>(
              future: _buscarDadosFinanceiros(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snapshot.hasData) {
                  return const Center(
                    child: Text("Erro ao carregar os dados financeiros."),
                  );
                }

                var dados = snapshot.data!;
                List<Map<String, dynamic>> historico = dados['historico'];

                return SingleChildScrollView(
                  padding: const EdgeInsets.all(40),
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
                                "Livro Caixa (Visão Global)",
                                style: TextStyle(
                                  fontSize: 32,
                                  fontWeight: FontWeight.bold,
                                  color: diPertinRoxo,
                                ),
                              ),
                              const Text(
                                "Acompanhe todas as entradas de dinheiro do aplicativo.",
                                style: TextStyle(
                                  color: Colors.grey,
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          ),
                          Row(
                            children: [
                              // === O NOVO BOTÃO VERDE ===
                              ElevatedButton.icon(
                                onPressed: _mostrarModalNovaReceita,
                                icon: const Icon(
                                  Icons.add,
                                  color: Colors.white,
                                ),
                                label: const Text(
                                  "Nova Receita",
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 20,
                                    vertical: 18,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),

                              if (_dataInicioFiltro != null)
                                TextButton.icon(
                                  onPressed: () => setState(() {
                                    _dataInicioFiltro = null;
                                    _dataFimFiltro = null;
                                  }),
                                  icon: const Icon(
                                    Icons.clear,
                                    color: Colors.red,
                                  ),
                                  label: const Text(
                                    "Limpar Filtro",
                                    style: TextStyle(
                                      color: Colors.red,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              const SizedBox(width: 10),
                              ElevatedButton.icon(
                                onPressed: _escolherPeriodo,
                                icon: const Icon(
                                  Icons.date_range,
                                  color: Colors.white,
                                ),
                                label: Text(
                                  _dataInicioFiltro != null
                                      ? "${_dataInicioFiltro!.day}/${_dataInicioFiltro!.month} até ${_dataFimFiltro!.day}/${_dataFimFiltro!.month}"
                                      : "Filtrar por Período",
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: diPertinLaranja,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 20,
                                    vertical: 18,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 30),

                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(30),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              diPertinRoxo,
                              diPertinRoxo.withOpacity(0.8),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(15),
                          boxShadow: const [
                            BoxShadow(
                              color: Colors.black12,
                              blurRadius: 10,
                              offset: Offset(0, 5),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              "Faturamento Total no Período",
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              "R\$ ${dados['totalGeral'].toStringAsFixed(2).replaceAll('.', ',')}",
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 40,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),

                      Row(
                        children: [
                          Expanded(
                            child: _cardResumo(
                              "Comissões (Lojas)",
                              dados['totalComissoes'],
                              Colors.blue,
                              Icons.storefront,
                            ),
                          ),
                          const SizedBox(width: 15),
                          Expanded(
                            child: _cardResumo(
                              "Taxas (Corridas)",
                              dados['totalTaxasEntrega'],
                              Colors.red,
                              Icons.motorcycle,
                            ),
                          ),
                          const SizedBox(width: 15),
                          Expanded(
                            child: _cardResumo(
                              "Assinaturas VIP",
                              dados['totalAssinaturas'],
                              Colors.green,
                              Icons.card_membership,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 15),

                      Row(
                        children: [
                          Expanded(
                            child: _cardResumo(
                              "Destaques & Banners",
                              dados['totalDestaques'],
                              diPertinLaranja,
                              Icons.star,
                            ),
                          ),
                          const SizedBox(width: 15),
                          Expanded(
                            child: _cardResumo(
                              "Premium (Telefones)",
                              dados['totalPremium'],
                              Colors.teal,
                              Icons.phone_forwarded,
                            ),
                          ),
                          const SizedBox(width: 15),
                          Expanded(
                            child: _cardResumo(
                              "Eventos Pagos",
                              dados['totalEventos'],
                              Colors.indigo,
                              Icons.celebration,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 40),

                      Text(
                        "Extrato de Transações",
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey[800],
                        ),
                      ),
                      const SizedBox(height: 15),

                      Card(
                        elevation: 3,
                        color: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: historico.isEmpty
                            ? const Padding(
                                padding: EdgeInsets.all(40),
                                child: Center(
                                  child: Text(
                                    "Nenhuma receita registrada neste período.",
                                    style: TextStyle(
                                      fontSize: 16,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ),
                              )
                            : ListView.separated(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: historico.length,
                                separatorBuilder: (context, index) =>
                                    const Divider(height: 1),
                                itemBuilder: (context, index) {
                                  var item = historico[index];
                                  return ListTile(
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 20,
                                      vertical: 10,
                                    ),
                                    leading: CircleAvatar(
                                      backgroundColor: Colors.green[50],
                                      child: const Icon(
                                        Icons.arrow_downward,
                                        color: Colors.green,
                                      ),
                                    ),
                                    title: Text(
                                      "${item['titulo']}",
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    subtitle: Text(
                                      "Categoria: ${item['tipo']}\nOrigem: ${item['dono']} • Registrado em: ${_formatarData(item['data'])}",
                                    ),
                                    isThreeLine: true,
                                    trailing: Text(
                                      "+ R\$ ${item['valor'].toStringAsFixed(2).replaceAll('.', ',')}",
                                      style: const TextStyle(
                                        color: Colors.green,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: const BotaoSuporteFlutuante(),
    );
  }

  Widget _cardResumo(String titulo, double valor, Color cor, IconData icone) {
    return Card(
      elevation: 2,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: cor.withOpacity(0.15),
              radius: 25,
              child: Icon(icone, color: cor, size: 25),
            ),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    titulo,
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    "R\$ ${valor.toStringAsFixed(2).replaceAll('.', ',')}",
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: cor,
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
