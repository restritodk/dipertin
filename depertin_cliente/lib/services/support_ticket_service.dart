import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:depertin_cliente/constants/suporte_categorias.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

/// Status do chamado (Central de Ajuda).
abstract class SuporteTicketStatus {
  static const waiting = 'waiting';
  static const inProgress = 'in_progress';
  static const finished = 'finished';
  static const cancelled = 'cancelled';
  static const closed = 'closed';
}

class SupportTicketService {
  SupportTicketService._();
  static final SupportTicketService instance = SupportTicketService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _tickets =>
      _db.collection('support_tickets');

  /// Protocolo numérico de 8 dígitos (10000000–99999999).
  ///
  /// Não consultamos o Firestore para checar colisão: uma query por
  /// `protocol_number` seria negada pelas regras (poderia retornar ticket de
  /// outro usuário). Unicidade é probabilística (~1 em 90M por sorteio).
  int gerarProtocoloNumerico() {
    return 10000000 + Random().nextInt(90000000);
  }

  Future<Map<String, dynamic>> dadosUsuarioAtual() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw Exception('Usuário não autenticado.');
    final doc = await _db.collection('users').doc(uid).get();
    final d = doc.data() ?? {};
    final cidade = (d['cidade'] ?? '').toString().trim().toLowerCase();
    return {
      'uid': uid,
      'nome': (d['nome'] ?? 'Cliente').toString(),
      'cidade': cidade.isEmpty ? '—' : cidade,
    };
  }

  /// Cria chamado em [waiting] sem mensagens (atendimento só após "Iniciar").
  Future<String> criarTicket() async {
    final u = await dadosUsuarioAtual();
    final protocol = gerarProtocoloNumerico();
    final ref = _tickets.doc();
    await ref.set({
      'protocol_number': protocol,
      'user_id': u['uid'],
      'user_nome': u['nome'],
      'cidade': u['cidade'],
      'agent_id': null,
      'agent_nome': null,
      'status': SuporteTicketStatus.waiting,
      'queue_position': null,
      'first_message_preview': '',
      'created_at': FieldValue.serverTimestamp(),
      'updated_at': FieldValue.serverTimestamp(),
      'started_at': null,
      'finished_at': null,
      'closed_by': null,
    });
    return ref.id;
  }

  Future<void> enviarMensagemCliente({
    required String ticketId,
    required String texto,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw Exception('Não autenticado.');
    final t = texto.trim();
    if (t.isEmpty) return;

    final ticketRef = _tickets.doc(ticketId);
    final snap = await ticketRef.get();
    if (!snap.exists) throw Exception('Chamado não encontrado.');
    final st = snap.data()?['status']?.toString() ?? '';
    if (st != SuporteTicketStatus.waiting &&
        st != SuporteTicketStatus.inProgress) {
      throw Exception('Este atendimento já foi encerrado.');
    }

    final batch = _db.batch();
    final msgRef = ticketRef.collection('mensagens').doc();
    batch.set(msgRef, {
      'mensagem': t,
      'sender_id': uid,
      'sender_type': 'client',
      'is_read': false,
      'created_at': FieldValue.serverTimestamp(),
    });

    final preview = snap.data()?['first_message_preview']?.toString() ?? '';
    if (preview.isEmpty) {
      batch.update(ticketRef, {
        'first_message_preview': t.length > 120 ? '${t.substring(0, 120)}…' : t,
        'updated_at': FieldValue.serverTimestamp(),
      });
    } else {
      batch.update(ticketRef, {
        'updated_at': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }

  /// Envia um anexo (imagem ou arquivo) do **cliente** no chamado.
  ///
  /// Um dos parâmetros [arquivo] (mobile) ou [bytes] (web) deve ser informado.
  /// [legenda] é um texto opcional que aparece junto do anexo.
  ///
  /// Cria uma mensagem em `mensagens` com os campos `anexo_*` populados,
  /// mantendo `mensagem` como legenda (pode ser vazia). Retrocompatível com
  /// mensagens antigas que não têm anexo.
  Future<void> enviarAnexoCliente({
    required String ticketId,
    required String nomeArquivo,
    required String mimeType,
    required int tamanhoBytes,
    File? arquivo,
    Uint8List? bytes,
    String legenda = '',
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw Exception('Não autenticado.');
    if (arquivo == null && bytes == null) {
      throw Exception('Arquivo não informado.');
    }

    final ticketRef = _tickets.doc(ticketId);
    final snap = await ticketRef.get();
    if (!snap.exists) throw Exception('Chamado não encontrado.');
    final st = snap.data()?['status']?.toString() ?? '';
    if (st != SuporteTicketStatus.waiting &&
        st != SuporteTicketStatus.inProgress) {
      throw Exception('Este atendimento já foi encerrado.');
    }

    final tipoAnexo = mimeType.startsWith('image/') ? 'image' : 'arquivo';
    final safeNome = _sanitizarNomeArquivo(nomeArquivo);
    final ts = DateTime.now().millisecondsSinceEpoch;
    final path = 'suporte_anexos/$ticketId/${uid}_${ts}_$safeNome';
    final ref = FirebaseStorage.instance.ref(path);
    final metadata = SettableMetadata(contentType: mimeType);

    if (arquivo != null) {
      await ref.putFile(arquivo, metadata);
    } else {
      await ref.putData(bytes!, metadata);
    }
    final url = await ref.getDownloadURL();

    final legendaLimpa = legenda.trim();
    final batch = _db.batch();
    final msgRef = ticketRef.collection('mensagens').doc();
    batch.set(msgRef, {
      'mensagem': legendaLimpa,
      'sender_id': uid,
      'sender_type': 'client',
      'is_read': false,
      'created_at': FieldValue.serverTimestamp(),
      'anexo_url': url,
      'anexo_nome': nomeArquivo,
      'anexo_tipo': tipoAnexo,
      'anexo_mime': mimeType,
      'anexo_tamanho': tamanhoBytes,
    });

    final preview = snap.data()?['first_message_preview']?.toString() ?? '';
    if (preview.isEmpty) {
      final resumo = legendaLimpa.isNotEmpty
          ? legendaLimpa
          : (tipoAnexo == 'image' ? '📷 Imagem' : '📎 $nomeArquivo');
      batch.update(ticketRef, {
        'first_message_preview':
            resumo.length > 120 ? '${resumo.substring(0, 120)}…' : resumo,
        'updated_at': FieldValue.serverTimestamp(),
      });
    } else {
      batch.update(ticketRef, {
        'updated_at': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }

  String _sanitizarNomeArquivo(String nome) {
    final limpo = nome.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    if (limpo.length <= 80) return limpo;
    final ext = limpo.contains('.') ? limpo.substring(limpo.lastIndexOf('.')) : '';
    return '${limpo.substring(0, 80 - ext.length)}$ext';
  }

  /// Após o cliente enviar ao menos uma mensagem na fila, escolhe a categoria
  /// do atendimento. Grava `categoria_suporte` / `categoria_label` no ticket e
  /// registra uma mensagem com o texto de aguardo atendente.
  Future<void> registrarCategoriaSuporteCliente({
    required String ticketId,
    required String codigo,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw Exception('Não autenticado.');
    final codigoOk = SuporteCategorias.codigoValido(codigo);
    if (codigoOk == null) {
      throw Exception('Categoria inválida.');
    }

    final ticketRef = _tickets.doc(ticketId);
    final snap = await ticketRef.get();
    if (!snap.exists) throw Exception('Chamado não encontrado.');
    final st = snap.data()?['status']?.toString() ?? '';
    if (st != SuporteTicketStatus.waiting) {
      throw Exception('Só é possível escolher a categoria enquanto aguarda na fila.');
    }
    if (snap.data()?['user_id']?.toString() != uid) {
      throw Exception('Acesso negado.');
    }
    final ja = (snap.data()?['categoria_suporte'] ?? '').toString().trim();
    if (ja.isNotEmpty) return;

    final rotulo = SuporteCategorias.rotuloPorCodigo(codigoOk);
    // Texto institucional — marcado com `suporte_auto: true` para o chat
    // renderizar como balão do suporte (lado esquerdo), mesmo que, por
    // restrição das regras do Firestore, o `sender_type` seja 'client'.
    final textoCompleto =
        'Olá! Sua solicitação foi registrada na categoria $rotulo.\n'
        'Agradecemos o contato. Aguarde, por favor — em instantes um de '
        'nossos atendentes iniciará o seu atendimento.\n\n'
        'Equipe DiPertin.';

    final batch = _db.batch();
    batch.update(ticketRef, {
      'categoria_suporte': codigoOk,
      'categoria_label': rotulo,
      'updated_at': FieldValue.serverTimestamp(),
    });
    final msgRef = ticketRef.collection('mensagens').doc();
    batch.set(msgRef, {
      'mensagem': textoCompleto,
      'sender_id': uid,
      'sender_type': 'client',
      'suporte_auto': true,
      'categoria_codigo': codigoOk,
      'categoria_label': rotulo,
      'is_read': false,
      'created_at': FieldValue.serverTimestamp(),
    });
    await batch.commit();
  }

  Future<void> encerrarPeloCliente(String ticketId) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    await _tickets.doc(ticketId).update({
      'status': SuporteTicketStatus.cancelled,
      'updated_at': FieldValue.serverTimestamp(),
      'finished_at': FieldValue.serverTimestamp(),
      'closed_by': 'client',
    });
  }

  /// Chamado mais recente do usuário (1 doc) ou null se nunca abriu ticket.
  Stream<QueryDocumentSnapshot<Map<String, dynamic>>?> streamUltimoTicket() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return Stream.value(null);
    }
    return _tickets
        .where('user_id', isEqualTo: uid)
        .orderBy('created_at', descending: true)
        .limit(1)
        .snapshots()
        .map((s) => s.docs.isEmpty ? null : s.docs.first);
  }

  /// Histórico de chamados do usuário.
  Stream<QuerySnapshot<Map<String, dynamic>>> streamHistoricoUsuario() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return const Stream.empty();
    }
    return _tickets
        .where('user_id', isEqualTo: uid)
        .orderBy('created_at', descending: true)
        .limit(30)
        .snapshots();
  }

  /// Posição na fila (1 = primeiro), apenas para [waiting] e mesma cidade.
  Stream<int> streamPosicaoFila({
    required String ticketId,
    required String cidadeNormalizada,
  }) {
    return _tickets
        .where('status', isEqualTo: SuporteTicketStatus.waiting)
        .where('cidade', isEqualTo: cidadeNormalizada)
        .orderBy('created_at', descending: false)
        .snapshots()
        .map((snap) {
      final i = snap.docs.indexWhere((d) => d.id == ticketId);
      return i >= 0 ? i + 1 : 0;
    });
  }
}
