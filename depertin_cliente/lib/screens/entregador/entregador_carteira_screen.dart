// Arquivo: lib/screens/entregador/entregador_carteira_zcreen.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

const Color diPertinRoxo = Color(0xFF6A1B9A);
const Color diPertinLaranja = Color(0xFFFF8F00);

class EntregadorCarteiraScreen extends StatefulWidget {
  const EntregadorCarteiraScreen({super.key});

  @override
  State<EntregadorCarteiraScreen> createState() =>
      _EntregadorCarteiraScreenState();
}

class _EntregadorCarteiraScreenState extends State<EntregadorCarteiraScreen> {
  final TextEditingController _chavePixController = TextEditingController();
  final TextEditingController _valorController = TextEditingController();
  // NOVOS CAMPOS!
  final TextEditingController _titularController = TextEditingController();
  final TextEditingController _bancoController = TextEditingController();

  bool _solicitando = false;

  void _abrirModalSaque(double saldoDisponivel) {
    if (saldoDisponivel <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Você não possui saldo disponível para saque."),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    _valorController.text = saldoDisponivel.toStringAsFixed(2);

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
          title: const Text(
            "Solicitar Saque (PIX)",
            style: TextStyle(color: diPertinRoxo),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  "Preencha os dados da conta que receberá o valor.",
                  style: TextStyle(fontSize: 13, color: Colors.grey),
                ),
                const SizedBox(height: 15),
                TextField(
                  controller: _titularController,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: "Nome do Titular da Conta",
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.person, color: diPertinRoxo),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _bancoController,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: "Banco (Ex: Nubank, Inter, Itaú)",
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(
                      Icons.account_balance,
                      color: diPertinRoxo,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _chavePixController,
                  decoration: const InputDecoration(
                    labelText: "Chave PIX",
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.pix, color: diPertinLaranja),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _valorController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: "Valor (R\$)",
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.attach_money, color: Colors.green),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                "Cancelar",
                style: TextStyle(color: Colors.grey),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: diPertinLaranja),
              onPressed: () => _confirmarSaque(saldoDisponivel),
              child: const Text(
                "Confirmar",
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _confirmarSaque(double saldoDisponivel) async {
    String chavePix = _chavePixController.text.trim();
    String titular = _titularController.text.trim();
    String banco = _bancoController.text.trim();
    String valorTexto = _valorController.text.trim().replaceAll(',', '.');
    double valorSolicitado = double.tryParse(valorTexto) ?? 0.0;

    if (titular.isEmpty || banco.isEmpty || chavePix.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Preencha todos os campos!"),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    if (valorSolicitado <= 0 || valorSolicitado > saldoDisponivel) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Valor inválido ou maior que o saldo."),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _solicitando = true);
    Navigator.pop(context);

    try {
      String userId = FirebaseAuth.instance.currentUser!.uid;

      // Adicionamos Banco e Titular no Firebase!
      await FirebaseFirestore.instance.collection('saques_solicitacoes').add({
        'user_id': userId,
        'tipo_usuario': 'entregador',
        'chave_pix': chavePix,
        'titular_conta': titular,
        'banco': banco,
        'valor': valorSolicitado,
        'status': 'pendente',
        'data_solicitacao': FieldValue.serverTimestamp(),
      });

      await FirebaseFirestore.instance.collection('users').doc(userId).update({
        'saldo': FieldValue.increment(-valorSolicitado),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Saque solicitado com sucesso! Aguarde o repasse."),
            backgroundColor: Colors.green,
          ),
        );
        _chavePixController.clear();
        _titularController.clear();
        _bancoController.clear();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Erro ao solicitar: $e"),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _solicitando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    String? userId = FirebaseAuth.instance.currentUser?.uid;

    if (userId == null) {
      return const Scaffold(
        body: Center(child: Text("Usuário não autenticado.")),
      );
    }

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text(
          "Minha Carteira",
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: diPertinRoxo,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Column(
        children: [
          StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance
                .collection('users')
                .doc(userId)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const SizedBox(
                  height: 150,
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (!snapshot.hasData || !snapshot.data!.exists) {
                return const SizedBox();
              }

              var userData = snapshot.data!.data() as Map<String, dynamic>;
              double saldoAtual = (userData['saldo'] ?? 0.0).toDouble();

              return Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(25),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [diPertinRoxo, Color(0xFF8E24AA)],
                        ),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.grey.withOpacity(0.5),
                            blurRadius: 10,
                            offset: const Offset(0, 5),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          const Text(
                            "Saldo Disponível",
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            "R\$ ${saldoAtual.toStringAsFixed(2)}",
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 36,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 25),
                    _solicitando
                        ? const Center(
                            child: CircularProgressIndicator(
                              color: diPertinLaranja,
                            ),
                          )
                        : ElevatedButton.icon(
                            icon: const Icon(Icons.pix, color: Colors.white),
                            label: const Padding(
                              padding: EdgeInsets.symmetric(vertical: 15),
                              child: Text(
                                "SOLICITAR SAQUE",
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: diPertinLaranja,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(15),
                              ),
                            ),
                            onPressed: () => _abrirModalSaque(saldoAtual),
                          ),
                  ],
                ),
              );
            },
          ),

          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20.0, vertical: 10.0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                "Histórico de Solicitações",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
            ),
          ),

          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('saques_solicitacoes')
                  .where('user_id', isEqualTo: userId)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(
                    child: Text(
                      "Nenhum saque solicitado ainda.",
                      style: TextStyle(color: Colors.grey),
                    ),
                  );
                }

                var docs = snapshot.data!.docs;
                docs.sort((a, b) {
                  Timestamp? tA =
                      (a.data() as Map<String, dynamic>)['data_solicitacao']
                          as Timestamp?;
                  Timestamp? tB =
                      (b.data() as Map<String, dynamic>)['data_solicitacao']
                          as Timestamp?;
                  if (tA == null) return 1;
                  if (tB == null) return -1;
                  return tB.compareTo(tA);
                });

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 15),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    var saque = docs[index].data() as Map<String, dynamic>;
                    double valor = (saque['valor'] ?? 0.0).toDouble();
                    String status = saque['status'] ?? 'pendente';
                    String chave = saque['chave_pix'] ?? '';
                    String banco = saque['banco'] ?? '';

                    String dataFormatada = 'Processando...';
                    if (saque['data_solicitacao'] != null) {
                      DateTime data = (saque['data_solicitacao'] as Timestamp)
                          .toDate();
                      dataFormatada = DateFormat(
                        'dd/MM/yyyy HH:mm',
                      ).format(data);
                    }

                    Color corStatus = Colors.orange;
                    IconData iconeStatus = Icons.access_time;
                    String textoStatus = "Pendente";

                    if (status == 'pago') {
                      corStatus = Colors.green;
                      iconeStatus = Icons.check_circle;
                      textoStatus = "Pago";
                    } else if (status == 'recusado') {
                      corStatus = Colors.red;
                      iconeStatus = Icons.cancel;
                      textoStatus = "Recusado (Devolvido)";
                    }

                    return Card(
                      elevation: 2,
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: corStatus.withOpacity(0.2),
                          child: Icon(iconeStatus, color: corStatus),
                        ),
                        title: Text(
                          "R\$ ${valor.toStringAsFixed(2)}",
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 4),
                            Text(
                              "PIX: $chave",
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (banco.isNotEmpty)
                              Text(
                                "Banco: $banco",
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey,
                                ),
                              ),
                            Text(
                              dataFormatada,
                              style: const TextStyle(
                                fontSize: 11,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: corStatus.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            textoStatus,
                            style: TextStyle(
                              color: corStatus,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
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
    );
  }
}
