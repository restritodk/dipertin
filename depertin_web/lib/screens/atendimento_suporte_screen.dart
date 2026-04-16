// Atendimento / suporte — support_tickets (protocolo, fila, chat em tempo real)

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:depertin_web/utils/admin_perfil.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

const _kWaiting = 'waiting';
const _kInProgress = 'in_progress';
const _kClosed = 'closed';
const _kHistoricoStatuses = ['closed', 'finished', 'cancelled'];

String statusLegivelSuporte(String st) {
  switch (st.trim().toLowerCase()) {
    case 'closed':
      return 'Encerrado';
    case 'finished':
      return 'Finalizado';
    case 'cancelled':
      return 'Cancelado';
    case 'waiting':
      return 'Na fila';
    case 'in_progress':
      return 'Em atendimento';
    default:
      return st.isEmpty ? '—' : st;
  }
}

String iniciaisNomeSuporte(String nome) {
  final partes = nome
      .trim()
      .split(RegExp(r'\s+'))
      .where((s) => s.isNotEmpty)
      .toList();
  if (partes.isEmpty) return '?';
  if (partes.length == 1) {
    return partes[0].substring(0, 1).toUpperCase();
  }
  return (partes[0].substring(0, 1) + partes[partes.length - 1].substring(0, 1))
      .toUpperCase();
}

class AtendimentoSuporteScreen extends StatefulWidget {
  const AtendimentoSuporteScreen({super.key});

  @override
  State<AtendimentoSuporteScreen> createState() =>
      _AtendimentoSuporteScreenState();
}

class _AtendimentoSuporteScreenState extends State<AtendimentoSuporteScreen> {
  final Color diPertinRoxo = const Color(0xFF6A1B9A);
  final Color diPertinLaranja = const Color(0xFFFF8F00);

  String? _selecionadoId;
  String? _selecionadoNome;
  final TextEditingController _mensagemController = TextEditingController();

  String _tipoUsuarioLogado = 'master';
  String _cidadeLogado = '';

  @override
  void initState() {
    super.initState();
    _buscarDadosDoAdmin();
  }

  @override
  void dispose() {
    _mensagemController.dispose();
    super.dispose();
  }

  Future<void> _buscarDadosDoAdmin() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final docSnap =
          await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      if (docSnap.exists) {
        final dados = docSnap.data()!;
        setState(() {
          _tipoUsuarioLogado = perfilAdministrativo(dados);
          _cidadeLogado =
              (dados['cidade'] ?? '').toString().trim().toLowerCase();
        });
      }
    }
  }

  Query<Map<String, dynamic>> _queryFila() {
    Query<Map<String, dynamic>> q = FirebaseFirestore.instance
        .collection('support_tickets')
        .where('status', isEqualTo: _kWaiting);
    if (_tipoUsuarioLogado == 'master_city') {
      q = q.where('cidade', isEqualTo: _cidadeLogado.isEmpty ? '—' : _cidadeLogado);
    }
    return q.orderBy('created_at', descending: false);
  }

  Query<Map<String, dynamic>> _queryAndamento() {
    Query<Map<String, dynamic>> q = FirebaseFirestore.instance
        .collection('support_tickets')
        .where('status', isEqualTo: _kInProgress);
    if (_tipoUsuarioLogado == 'master_city') {
      q = q.where('cidade', isEqualTo: _cidadeLogado.isEmpty ? '—' : _cidadeLogado);
    }
    return q.orderBy('updated_at', descending: true);
  }

  /// Chamados encerrados (leitura / pesquisa no painel).
  Query<Map<String, dynamic>> _queryHistorico() {
    Query<Map<String, dynamic>> q = FirebaseFirestore.instance
        .collection('support_tickets')
        .where('status', whereIn: _kHistoricoStatuses);
    if (_tipoUsuarioLogado == 'master_city') {
      q = q.where('cidade', isEqualTo: _cidadeLogado.isEmpty ? '—' : _cidadeLogado);
    }
    return q.orderBy('updated_at', descending: true).limit(400);
  }

  String _fmtHora(dynamic t) {
    if (t is! Timestamp) return '—';
    final d = t.toDate();
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    final hh = d.hour.toString().padLeft(2, '0');
    final min = d.minute.toString().padLeft(2, '0');
    return '$dd/$mm ${d.year} $hh:$min';
  }

  String _tempoEspera(dynamic t) {
    if (t is! Timestamp) return '—';
    final diff = DateTime.now().difference(t.toDate());
    final m = diff.inMinutes;
    if (m < 2) return 'agora';
    if (m < 60) return '$m min';
    return '${diff.inHours} h';
  }

  int _posicaoNaFila(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> filaDocs,
    String id,
  ) {
    final i = filaDocs.indexWhere((e) => e.id == id);
    return i >= 0 ? i + 1 : 0;
  }

  Future<void> _iniciarAtendimentoPainel() async {
    final id = _selecionadoId;
    if (id == null) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final nomeAdmin = await _nomeAtendente(user.uid);

    final ref =
        FirebaseFirestore.instance.collection('support_tickets').doc(id);
    try {
      await FirebaseFirestore.instance.runTransaction((tx) async {
        final s = await tx.get(ref);
        if (!s.exists) {
          throw Exception('Chamado não encontrado.');
        }
        final d = s.data()!;
        if (d['status'] != _kWaiting) {
          throw Exception('Este chamado já foi assumido ou não está na fila.');
        }
        if (d['agent_id'] != null) {
          throw Exception('Outro atendente já iniciou este chamado.');
        }
        tx.update(ref, {
          'status': _kInProgress,
          'agent_id': user.uid,
          'agent_nome': nomeAdmin,
          'started_at': FieldValue.serverTimestamp(),
          'updated_at': FieldValue.serverTimestamp(),
        });
      });

      await ref.collection('mensagens').add({
        'mensagem': '$nomeAdmin iniciou seu atendimento.',
        'sender_id': user.uid,
        'sender_type': 'system',
        'is_read': false,
        'created_at': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        mostrarSnackPainel(context, mensagem: 'Atendimento iniciado com sucesso.');
      }
    } catch (e) {
      if (mounted) {
        mostrarSnackPainel(context, mensagem: '$e', erro: true);
      }
    }
  }

  Future<String> _nomeAtendente(String uid) async {
    final doc =
        await FirebaseFirestore.instance.collection('users').doc(uid).get();
    final n = doc.data()?['nome'];
    if (n != null && n.toString().trim().isNotEmpty) return n.toString().trim();
    return 'Atendente';
  }

  Future<void> _enviarMensagem() async {
    final id = _selecionadoId;
    if (id == null || _mensagemController.text.trim().isEmpty) return;
    final texto = _mensagemController.text.trim();
    _mensagemController.clear();

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final ticketRef =
        FirebaseFirestore.instance.collection('support_tickets').doc(id);
    final snap = await ticketRef.get();
    if (!snap.exists) return;
    final d = snap.data()!;
    if (d['status'] != _kInProgress || d['agent_id'] != uid) {
      if (mounted) {
        mostrarSnackPainel(
          context,
          mensagem:
              'Só o atendente responsável pode enviar mensagens neste chamado.',
          erro: true,
        );
      }
      return;
    }

    try {
      await ticketRef.collection('mensagens').add({
        'mensagem': texto,
        'sender_id': uid,
        'sender_type': 'agent',
        'is_read': false,
        'created_at': FieldValue.serverTimestamp(),
      });
      await ticketRef.update({
        'updated_at': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      if (mounted) {
        mostrarSnackPainel(context, mensagem: 'Erro ao enviar: $e', erro: true);
      }
    }
  }

  Future<void> _encerrarChamado() async {
    final id = _selecionadoId;
    if (id == null) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final ref =
        FirebaseFirestore.instance.collection('support_tickets').doc(id);
    try {
      // Mensagem de sistema ANTES de fechar o ticket: as regras exigem
      // status in_progress para criar mensagem de staff.
      final batch = FirebaseFirestore.instance.batch();
      final msgRef = ref.collection('mensagens').doc();
      batch.set(msgRef, {
        'mensagem': '--- Atendimento encerrado pelo suporte ---',
        'sender_id': uid,
        'sender_type': 'system',
        'is_read': false,
        'created_at': FieldValue.serverTimestamp(),
      });
      batch.update(ref, {
        'status': _kClosed,
        'finished_at': FieldValue.serverTimestamp(),
        'closed_by': 'support',
        'updated_at': FieldValue.serverTimestamp(),
      });
      await batch.commit();
      setState(() {
        _selecionadoId = null;
        _selecionadoNome = null;
      });
      if (mounted) {
        mostrarSnackPainel(context, mensagem: 'Chamado encerrado.');
      }
    } catch (e) {
      if (mounted) {
        mostrarSnackPainel(context, mensagem: 'Erro: $e', erro: true);
      }
    }
  }

  Future<void> _abrirModalEditarUsuario(String usuarioId) async {
    final nomeC = TextEditingController();
    final cpfC = TextEditingController();
    final telefoneC = TextEditingController();
    final cidadeC = TextEditingController();
    String emailUsuario = '';
    var carregando = true;

    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(usuarioId)
        .get();
    if (doc.exists) {
      final dados = doc.data() as Map<String, dynamic>;
      nomeC.text = dados['nome'] ?? '';
      cpfC.text = dados['cpf'] ?? '';
      telefoneC.text = dados['telefone'] ?? '';
      cidadeC.text = dados['cidade'] ?? '';
      emailUsuario = dados['email'] ?? '';
    }
    carregando = false;

    if (!mounted) return;

    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Ficha do usuário',
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
                          labelText: 'Nome completo',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.person),
                        ),
                      ),
                      const SizedBox(height: 15),
                      TextField(
                        controller: cpfC,
                        decoration: const InputDecoration(
                          labelText: 'CPF',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.badge),
                        ),
                      ),
                      const SizedBox(height: 15),
                      TextField(
                        controller: telefoneC,
                        decoration: const InputDecoration(
                          labelText: 'Telefone',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.phone),
                        ),
                      ),
                      const SizedBox(height: 15),
                      TextField(
                        controller: cidadeC,
                        decoration: const InputDecoration(
                          labelText: 'Cidade',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.location_city),
                        ),
                      ),
                      const SizedBox(height: 25),
                      const Divider(),
                      if (emailUsuario.isNotEmpty)
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              try {
                                await FirebaseAuth.instance
                                    .sendPasswordResetEmail(email: emailUsuario);
                                if (context.mounted) {
                                  Navigator.pop(context);
                                  mostrarSnackPainel(
                                    context,
                                    mensagem:
                                        'Link de redefinição enviado para o e-mail do usuário.',
                                  );
                                }
                              } catch (e) {
                                if (context.mounted) {
                                  mostrarSnackPainel(
                                    context,
                                    mensagem: 'Erro: $e',
                                    erro: true,
                                  );
                                }
                              }
                            },
                            icon: const Icon(Icons.lock_reset, color: Colors.red),
                            label: const Text(
                              'Enviar link de reset de senha',
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
            child: const Text('Cancelar', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: diPertinRoxo,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
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
                mostrarSnackPainel(context, mensagem: 'Perfil atualizado.');
              }
            },
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F7),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 400,
            child: ColunaFilaSuporte(
                    diPertinRoxo: diPertinRoxo,
                    diPertinLaranja: diPertinLaranja,
                    queryFila: _queryFila(),
                    queryAndamento: _queryAndamento(),
                    queryHistorico: _queryHistorico(),
                    selecionadoId: _selecionadoId,
                    onSelect: (doc) {
                      final m = doc.data();
                      setState(() {
                        _selecionadoId = doc.id;
                        _selecionadoNome =
                            m['user_nome']?.toString() ?? 'Cliente';
                      });
                    },
                    fmtHora: _fmtHora,
                    tempoEspera: _tempoEspera,
                    posicaoNaFila: _posicaoNaFila,
                  ),
          ),
          Expanded(child: _painelChat(uid)),
        ],
      ),
    );
  }

  Widget _painelChat(String? uidMeu) {
    if (_selecionadoId == null) {
      return Container(
        color: const Color(0xFFF5F5F7),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(28),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: diPertinRoxo.withValues(alpha: 0.08),
                          blurRadius: 24,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Icon(
                      Icons.chat_bubble_outline_rounded,
                      size: 56,
                      color: diPertinRoxo.withValues(alpha: 0.45),
                    ),
                  ),
                  const SizedBox(height: 28),
                  Text(
                    'Nenhum chamado selecionado',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: Colors.grey.shade900,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Escolha um ticket na fila de espera, em atendimento ou no histórico para ver a conversa e responder ao cliente.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.45,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('support_tickets')
          .doc(_selecionadoId)
          .snapshots(),
      builder: (context, snap) {
        if (!snap.hasData || !snap.data!.exists) {
          return const Center(child: CircularProgressIndicator());
        }
        final d = snap.data!.data()!;
        final st = d['status']?.toString() ?? '';
        final agentId = d['agent_id']?.toString();
        final userClienteId = d['user_id']?.toString();
        final protocolo =
            (d['protocol_number'] ?? '').toString().padLeft(8, '0');
        final preview =
            (d['first_message_preview'] ?? '').toString().trim().isEmpty
                ? '(sem prévia)'
                : d['first_message_preview'].toString();

        final possoResponder =
            st == _kInProgress && uidMeu != null && agentId == uidMeu;
        final aguardando = st == _kWaiting;
        final emAndamento = st == _kInProgress;
        final encerrado = st == _kClosed ||
            st == 'finished' ||
            st == 'cancelled';

        return Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(bottom: BorderSide(color: Colors.black12)),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: diPertinRoxo,
                    child: Text(
                      (_selecionadoNome ?? 'C').substring(0, 1).toUpperCase(),
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _selecionadoNome ?? 'Cliente',
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'Protocolo $protocolo · $preview',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.black54,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  if (userClienteId != null)
                    OutlinedButton.icon(
                      onPressed: () => _abrirModalEditarUsuario(userClienteId),
                      icon: const Icon(Icons.manage_accounts, color: Colors.blue),
                      label: const Text(
                        'Editar perfil',
                        style: TextStyle(color: Colors.blue),
                      ),
                    ),
                  const SizedBox(width: 8),
                  if (aguardando)
                    ElevatedButton.icon(
                      onPressed: _iniciarAtendimentoPainel,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: diPertinLaranja,
                        foregroundColor: Colors.white,
                      ),
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Iniciar atendimento'),
                    ),
                  if (emAndamento) ...[
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: _encerrarChamado,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                      ),
                      icon: const Icon(Icons.check_circle),
                      label: const Text('Finalizar atendimento'),
                    ),
                  ],
                ],
              ),
            ),
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance
                    .collection('support_tickets')
                    .doc(_selecionadoId)
                    .collection('mensagens')
                    .orderBy('created_at', descending: true)
                    .snapshots(),
                builder: (context, snapMsg) {
                  if (!snapMsg.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final msgs = snapMsg.data!.docs;
                  return ListView.builder(
                    reverse: true,
                    padding: const EdgeInsets.all(20),
                    itemCount: msgs.length,
                    itemBuilder: (context, index) {
                      final msg = msgs[index].data();
                      final tipo = msg['sender_type']?.toString() ?? '';
                      final texto = msg['mensagem']?.toString() ?? '';
                      if (tipo == 'system') {
                        return Center(
                          child: Container(
                            margin: const EdgeInsets.symmetric(vertical: 10),
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.grey[300],
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              texto,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.black54,
                              ),
                            ),
                          ),
                        );
                      }
                      final ehCliente = tipo == 'client';
                      final alinhamento = ehCliente
                          ? Alignment.centerLeft
                          : Alignment.centerRight;
                      final bg = ehCliente ? Colors.grey[200]! : diPertinRoxo;
                      final fg = ehCliente ? Colors.black87 : Colors.white;
                      return Align(
                        alignment: alinhamento,
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(14),
                          constraints: const BoxConstraints(maxWidth: 420),
                          decoration: BoxDecoration(
                            color: bg,
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: const [
                              BoxShadow(color: Colors.black12, blurRadius: 4),
                            ],
                          ),
                          child: Text(
                            texto,
                            style: TextStyle(color: fg, fontSize: 15),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            Container(
              padding: const EdgeInsets.all(16),
              color: Colors.white,
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _mensagemController,
                      enabled: possoResponder,
                      decoration: InputDecoration(
                        hintText: encerrado
                            ? 'Chamado encerrado (somente leitura).'
                            : possoResponder
                                ? 'Resposta ao cliente...'
                                : aguardando
                                    ? 'Inicie o atendimento para responder.'
                                    : 'Apenas o atendente responsável pode enviar mensagens.',
                        filled: true,
                        fillColor: Colors.grey[100],
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(28),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 14,
                        ),
                      ),
                      onSubmitted: (_) {
                        if (possoResponder) _enviarMensagem();
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  CircleAvatar(
                    radius: 26,
                    backgroundColor:
                        possoResponder ? diPertinLaranja : Colors.grey,
                    child: IconButton(
                      icon: const Icon(Icons.send, color: Colors.white),
                      onPressed: possoResponder ? _enviarMensagem : null,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Fila, andamento e histórico com filtros (nome, protocolo, data).
class ColunaFilaSuporte extends StatefulWidget {
  const ColunaFilaSuporte({
    super.key,
    required this.diPertinRoxo,
    required this.diPertinLaranja,
    required this.queryFila,
    required this.queryAndamento,
    required this.queryHistorico,
    required this.selecionadoId,
    required this.onSelect,
    required this.fmtHora,
    required this.tempoEspera,
    required this.posicaoNaFila,
  });

  final Color diPertinRoxo;
  final Color diPertinLaranja;
  final Query<Map<String, dynamic>> queryFila;
  final Query<Map<String, dynamic>> queryAndamento;
  final Query<Map<String, dynamic>> queryHistorico;
  final String? selecionadoId;
  final void Function(QueryDocumentSnapshot<Map<String, dynamic>> doc) onSelect;
  final String Function(dynamic t) fmtHora;
  final String Function(dynamic t) tempoEspera;
  final int Function(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> filaDocs,
    String id,
  ) posicaoNaFila;

  @override
  State<ColunaFilaSuporte> createState() => _ColunaFilaSuporteState();
}

class _ColunaFilaSuporteState extends State<ColunaFilaSuporte> {
  final TextEditingController _filtroNome = TextEditingController();
  final TextEditingController _filtroProtocolo = TextEditingController();
  DateTime? _dataDe;
  DateTime? _dataAte;

  @override
  void dispose() {
    _filtroNome.dispose();
    _filtroProtocolo.dispose();
    super.dispose();
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _aplicarFiltrosHistorico(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final nome = _filtroNome.text.toLowerCase().trim();
    final proto = _filtroProtocolo.text.replaceAll(RegExp(r'\D'), '');
    return docs.where((doc) {
      final m = doc.data();
      if (nome.isNotEmpty) {
        final n = (m['user_nome'] ?? '').toString().toLowerCase();
        if (!n.contains(nome)) return false;
      }
      if (proto.isNotEmpty) {
        final p =
            (m['protocol_number'] ?? '').toString().replaceAll(RegExp(r'\D'), '');
        if (!p.contains(proto)) return false;
      }
      final cr = m['created_at'];
      if (cr is Timestamp) {
        final cd = cr.toDate();
        final cDia = DateTime(cd.year, cd.month, cd.day);
        if (_dataDe != null) {
          final d0 = DateTime(_dataDe!.year, _dataDe!.month, _dataDe!.day);
          if (cDia.isBefore(d0)) return false;
        }
        if (_dataAte != null) {
          final d1 = DateTime(_dataAte!.year, _dataAte!.month, _dataAte!.day);
          if (cDia.isAfter(d1)) return false;
        }
      }
      return true;
    }).toList();
  }

  String _fmtDataCurta(DateTime? d) {
    if (d == null) return '—';
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  Future<void> _pickData({required bool inicio}) async {
    final now = DateTime.now();
    final first = DateTime(now.year - 2);
    final last = DateTime(now.year + 1);
    final initial = inicio ? (_dataDe ?? now) : (_dataAte ?? now);
    final r = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: last,
    );
    if (r == null) return;
    setState(() {
      if (inicio) {
        _dataDe = r;
      } else {
        _dataAte = r;
      }
    });
  }

  static const Color _azulAndamento = Color(0xFF1565C0);
  static const Color _verdeHistorico = Color(0xFF00897B);

  OutlineInputBorder _inputOutline() {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: Colors.grey.shade300),
    );
  }

  Widget _cabecalhoPrincipal() {
    final rx = widget.diPertinRoxo;
    final topo = Color.lerp(rx, Colors.black, 0.14)!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [topo, rx],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: rx.withValues(alpha: 0.28),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(
            Icons.headset_mic_rounded,
            color: Colors.white.withValues(alpha: 0.92),
            size: 24,
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Central de atendimento',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _cabecalhoSecao(String titulo, Color accent, IconData icon) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFF3F2F7),
          borderRadius: BorderRadius.circular(10),
          border: Border(
            left: BorderSide(color: accent, width: 4),
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: accent),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                titulo,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: Color(0xFF2D2848),
                  letterSpacing: -0.1,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyEstado(String mensagem, {IconData icon = Icons.inbox_outlined}) {
    return Container(
      constraints: const BoxConstraints(minHeight: 76),
      margin: const EdgeInsets.symmetric(horizontal: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Icon(icon, size: 26, color: Colors.grey.shade400),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              mensagem,
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 13,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _cardFiltros() {
    final rx = widget.diPertinRoxo;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 12,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.tune_rounded, size: 20, color: rx),
                const SizedBox(width: 8),
                Text(
                  'Filtros do histórico',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: rx,
                    letterSpacing: -0.2,
                  ),
                ),
                const Spacer(),
                OutlinedButton(
                  onPressed: () => setState(() {
                    _dataDe = null;
                    _dataAte = null;
                    _filtroNome.clear();
                    _filtroProtocolo.clear();
                  }),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: rx,
                    side: BorderSide(color: rx.withValues(alpha: 0.45)),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    visualDensity: VisualDensity.compact,
                  ),
                  child: const Text('Limpar'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _filtroNome,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'Nome do cliente',
                isDense: true,
                filled: true,
                fillColor: const Color(0xFFF8F8FA),
                border: _inputOutline(),
                enabledBorder: _inputOutline(),
                focusedBorder: _inputOutline().copyWith(
                  borderSide: BorderSide(color: rx, width: 1.2),
                ),
                prefixIcon: Icon(Icons.person_search_rounded, size: 20, color: Colors.grey.shade600),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _filtroProtocolo,
              onChanged: (_) => setState(() {}),
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Protocolo (número)',
                isDense: true,
                filled: true,
                fillColor: const Color(0xFFF8F8FA),
                border: _inputOutline(),
                enabledBorder: _inputOutline(),
                focusedBorder: _inputOutline().copyWith(
                  borderSide: BorderSide(color: rx, width: 1.2),
                ),
                prefixIcon: Icon(Icons.tag_rounded, size: 20, color: Colors.grey.shade600),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _pickData(inicio: true),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      side: BorderSide(color: Colors.grey.shade300),
                    ),
                    child: Text(
                      'De: ${_fmtDataCurta(_dataDe)}',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade800),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _pickData(inicio: false),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      side: BorderSide(color: Colors.grey.shade300),
                    ),
                    child: Text(
                      'Até: ${_fmtDataCurta(_dataAte)}',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade800),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _loaderSecao() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Center(
        child: SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            color: widget.diPertinRoxo,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.07),
            blurRadius: 16,
            offset: const Offset(4, 0),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _cabecalhoPrincipal(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _cabecalhoSecao(
                    'Fila de espera',
                    widget.diPertinLaranja,
                    Icons.schedule_rounded,
                  ),
                  StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: widget.queryFila.snapshots(),
                    builder: (context, snap) {
                      if (snap.connectionState == ConnectionState.waiting) {
                        return _loaderSecao();
                      }
                      final docs = snap.data?.docs ?? [];
                      if (docs.isEmpty) {
                        return _emptyEstado(
                          'Nenhum cliente aguardando no momento.',
                          icon: Icons.hourglass_empty_rounded,
                        );
                      }
                      return Column(
                        children: docs.map((doc) {
                          final m = doc.data();
                          final pos = widget.posicaoNaFila(docs, doc.id);
                          final sel = widget.selecionadoId == doc.id;
                          return _tile(
                            nome: m['user_nome']?.toString() ?? 'Cliente',
                            protocolo: (m['protocol_number'] ?? '')
                                .toString()
                                .padLeft(8, '0'),
                            subtitulo:
                                '${widget.fmtHora(m['created_at'])} · espera ${widget.tempoEspera(m['created_at'])} · #$pos na fila',
                            preview: (m['first_message_preview'] ?? '')
                                .toString(),
                            selecionado: sel,
                            onTap: () => widget.onSelect(doc),
                          );
                        }).toList(),
                      );
                    },
                  ),
                  _cabecalhoSecao(
                    'Em atendimento',
                    _azulAndamento,
                    Icons.support_agent_rounded,
                  ),
                  StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: widget.queryAndamento.snapshots(),
                    builder: (context, snap) {
                      if (snap.connectionState == ConnectionState.waiting) {
                        return _loaderSecao();
                      }
                      final docs = snap.data?.docs ?? [];
                      if (docs.isEmpty) {
                        return _emptyEstado(
                          'Nenhum atendimento em curso.',
                          icon: Icons.assignment_ind_outlined,
                        );
                      }
                      return Column(
                        children: docs.map((doc) {
                          final m = doc.data();
                          final sel = widget.selecionadoId == doc.id;
                          final agente = m['agent_nome']?.toString() ?? '—';
                          return _tile(
                            nome: m['user_nome']?.toString() ?? 'Cliente',
                            protocolo: (m['protocol_number'] ?? '')
                                .toString()
                                .padLeft(8, '0'),
                            subtitulo: 'Atendente: $agente',
                            preview: (m['first_message_preview'] ?? '')
                                .toString(),
                            selecionado: sel,
                            onTap: () => widget.onSelect(doc),
                          );
                        }).toList(),
                      );
                    },
                  ),
                  _cabecalhoSecao(
                    'Histórico de atendimentos',
                    _verdeHistorico,
                    Icons.history_rounded,
                  ),
                  _cardFiltros(),
                  StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: widget.queryHistorico.snapshots(),
                    builder: (context, snap) {
                      if (snap.connectionState == ConnectionState.waiting) {
                        return _loaderSecao();
                      }
                      final raw = snap.data?.docs ?? [];
                      final docs = _aplicarFiltrosHistorico(raw);
                      if (raw.isEmpty) {
                        return _emptyEstado(
                          'Nenhum registro no histórico ainda.',
                          icon: Icons.folder_open_outlined,
                        );
                      }
                      if (docs.isEmpty) {
                        return _emptyEstado(
                          'Nenhum resultado com os filtros atuais.',
                          icon: Icons.search_off_rounded,
                        );
                      }
                      return Column(
                        children: docs.map((doc) {
                          final m = doc.data();
                          final sel = widget.selecionadoId == doc.id;
                          final st = m['status']?.toString() ?? '';
                          return _tile(
                            nome: m['user_nome']?.toString() ?? 'Cliente',
                            protocolo: (m['protocol_number'] ?? '')
                                .toString()
                                .padLeft(8, '0'),
                            subtitulo:
                                '${widget.fmtHora(m['created_at'])} · ${statusLegivelSuporte(st)}',
                            preview: (m['first_message_preview'] ?? '')
                                .toString(),
                            selecionado: sel,
                            onTap: () => widget.onSelect(doc),
                          );
                        }).toList(),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tile({
    required String nome,
    required String protocolo,
    required String subtitulo,
    required String preview,
    required bool selecionado,
    required VoidCallback onTap,
  }) {
    final rx = widget.diPertinRoxo;
    final iniciais = iniciaisNomeSuporte(nome);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          splashColor: rx.withValues(alpha: 0.08),
          hoverColor: rx.withValues(alpha: 0.04),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: selecionado
                  ? rx.withValues(alpha: 0.09)
                  : const Color(0xFFFAFAFC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selecionado
                    ? rx.withValues(alpha: 0.5)
                    : const Color(0xFFE8E6EF),
                width: selecionado ? 1.5 : 1,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: rx.withValues(alpha: 0.14),
                  child: Text(
                    iniciais,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: rx,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        nome,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          letterSpacing: -0.1,
                          color: Color(0xFF1E1B2E),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Protocolo $protocolo',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade700,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        subtitulo,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade600,
                          height: 1.25,
                        ),
                      ),
                      if (preview.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          preview,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.3,
                            color: Colors.grey.shade800,
                          ),
                        ),
                      ],
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
}
