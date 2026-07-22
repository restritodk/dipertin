import 'dart:math';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

/// Status Firestore canônicos (Central de Atendimento existente).
abstract class SuporteTicketStatusWeb {
  static const waiting = 'waiting';
  static const inProgress = 'in_progress';
  static const closed = 'closed';
  static const cancelled = 'cancelled';
  static const finished = 'finished';

  static bool estaAberto(String? status) =>
      status == waiting || status == inProgress;

  static bool estaFinalizado(String? status) =>
      status == closed ||
      status == cancelled ||
      status == finished;
}

/// Etapas do fluxo automático do chat lojista (campo `lojista_chat_etapa`).
abstract class LojistaChatEtapa {
  static const naFila = 'na_fila';
  static const aguardando = 'aguardando_atendimento';
}

/// Serviço do chat lojista ↔ Central de Atendimento (`support_tickets`).
///
/// Escrita sequencial (sem batch/whereIn) para evitar INTERNAL ASSERTION
/// do SDK Firestore na web.
class SuporteLojistaChatService {
  SuporteLojistaChatService._();
  static final instance = SuporteLojistaChatService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _tickets =>
      _db.collection('support_tickets');

  static const _getServer = GetOptions(source: Source.server);

  int _protocolo() => 10000000 + Random().nextInt(90000000);

  String _mensagemAmigavel(Object e) {
    final s = '$e';
    if (s.contains('permission-denied') || s.contains('PERMISSION_DENIED')) {
      return 'Sem permissão para abrir o chamado. Faça login novamente.';
    }
    if (s.contains('INTERNAL ASSERTION') || s.contains('Unexpected state')) {
      return 'Falha temporária do Firestore no navegador. Feche o chat, '
          'atualize a página (F5) e tente novamente.';
    }
    if (s.contains('unavailable') || s.contains('network')) {
      return 'Sem conexão com o servidor. Verifique a internet e tente de novo.';
    }
    // Evita estourar modal com stack enorme
    if (s.length > 180) {
      return '${s.substring(0, 180)}…';
    }
    return s;
  }

  DocumentSnapshot<Map<String, dynamic>>? _pickAberto(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final abertos = docs
        .where((d) =>
            SuporteTicketStatusWeb.estaAberto(d.data()['status']?.toString()))
        .toList();
    if (abertos.isEmpty) return null;
    return abertos.first; // já vem orderBy created_at desc
  }

  /// Chamado aberto (waiting | in_progress) do usuário logado, se houver.
  Future<DocumentSnapshot<Map<String, dynamic>>?> buscarChamadoAberto() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;

    // Query simples (índice user_id + created_at). Filtra status no client —
    // whereIn + snapshots na web costuma disparar INTERNAL ASSERTION.
    final snap = await _tickets
        .where('user_id', isEqualTo: uid)
        .orderBy('created_at', descending: true)
        .limit(15)
        .get(_getServer);

    return _pickAberto(snap.docs);
  }

  /// Stream do chamado aberto — query simples + filtro local.
  Stream<DocumentSnapshot<Map<String, dynamic>>?> streamChamadoAberto() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return Stream.value(null);

    return _tickets
        .where('user_id', isEqualTo: uid)
        .orderBy('created_at', descending: true)
        .limit(15)
        .snapshots()
        .map((snap) => _pickAberto(snap.docs));
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> streamMensagens(String ticketId) {
    return _tickets
        .doc(ticketId)
        .collection('mensagens')
        .orderBy('created_at', descending: false)
        .snapshots();
  }

  Future<Map<String, dynamic>> _dadosLojista({
    required String lojaId,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('Não autenticado.');

    final doc = await _db.collection('users').doc(lojaId).get(_getServer);
    final d = doc.data() ?? {};
    final lojaNome = (d['loja_nome'] ??
            d['nome_loja'] ??
            d['nome_fantasia'] ??
            d['razao_social'] ??
            d['nome'] ??
            'Minha loja')
        .toString()
        .trim();
    final responsavel = (d['nome'] ??
            d['nome_completo'] ??
            d['responsavel'] ??
            user.displayName ??
            'Lojista')
        .toString()
        .trim();
    final cidade = (d['cidade'] ?? d['cidade_normalizada'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    final email = (user.email ?? d['email'] ?? '').toString().trim();
    final telefone =
        (d['telefone'] ?? d['phone'] ?? d['celular'] ?? '').toString().trim();
    final documento = (d['cnpj'] ??
            d['loja_documento'] ??
            d['cpf_cnpj'] ??
            d['documento'] ??
            '')
        .toString()
        .trim();

    return {
      'uid': user.uid,
      'loja_id': lojaId,
      'loja_nome': lojaNome.isEmpty ? 'Minha loja' : lojaNome,
      'responsavel': responsavel.isEmpty ? 'Lojista' : responsavel,
      'cidade': cidade.isEmpty ? '—' : cidade,
      'email': email,
      'telefone': telefone,
      'documento': documento,
    };
  }

  /// Envia mensagem do lojista; cria o chamado na 1ª mensagem e dispara autos.
  Future<void> enviarMensagemLojista({
    required String texto,
    required String lojaId,
  }) async {
    final t = texto.trim();
    if (t.isEmpty) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw Exception('Não autenticado.');

    try {
      final aberto = await buscarChamadoAberto();
      if (aberto != null && aberto.exists) {
        await _enviarEmChamadoExistente(
          ticketId: aberto.id,
          ticketData: aberto.data()!,
          texto: t,
          uid: uid,
        );
        return;
      }

      await _criarChamadoComPrimeiraMensagem(
        texto: t,
        lojaId: lojaId,
        uid: uid,
      );
    } catch (e) {
      throw Exception(_mensagemAmigavel(e));
    }
  }

  Future<void> _criarChamadoComPrimeiraMensagem({
    required String texto,
    required String lojaId,
    required String uid,
  }) async {
    final u = await _dadosLojista(lojaId: lojaId);
    final lojaNome = u['loja_nome'] as String;
    final ticketRef = _tickets.doc();
    final agora = Timestamp.now();

    // Escrita sequencial (web-safe). Campos do create respeitam hasOnly das rules.
    await ticketRef.set({
      'protocol_number': _protocolo(),
      'user_id': uid,
      'user_nome': lojaNome,
      'cidade': u['cidade'],
      'solicitante_uid': uid,
      'solicitante_nome': u['responsavel'],
      'solicitante_perfil': 'lojista',
      'solicitante_email': u['email'],
      'solicitante_telefone': u['telefone'],
      'solicitante_documento': u['documento'],
      'solicitante_loja_nome': lojaNome,
      'solicitante_cidade': u['cidade'],
      'agent_id': null,
      'agent_nome': null,
      'status': SuporteTicketStatusWeb.waiting,
      'queue_position': null,
      'first_message_preview':
          texto.length > 120 ? '${texto.substring(0, 120)}…' : texto,
      'created_at': agora,
      'updated_at': agora,
      'started_at': null,
      'finished_at': null,
      'closed_by': null,
    });

    await ticketRef.collection('mensagens').add({
      'mensagem': texto,
      'sender_id': uid,
      'sender_type': 'client',
      'is_read': false,
      'created_at': agora,
    });

    await ticketRef.collection('mensagens').add({
      'mensagem':
          'Olá $lojaNome,\n\nSeja bem-vindo ao suporte do DiPertin.\n\n'
          'Escreva abaixo o assunto desejado.',
      'sender_id': uid,
      'sender_type': 'client',
      'suporte_auto': true,
      'is_system': true,
      'is_read': true,
      'created_at': Timestamp.fromMillisecondsSinceEpoch(
        agora.millisecondsSinceEpoch + 1,
      ),
    });

    // Update separado — categoria libera «Iniciar atendimento» no admin.
    await ticketRef.update({
      'categoria_suporte': 'ajuda',
      'categoria_label': 'Suporte painel lojista',
      'lojista_chat_etapa': LojistaChatEtapa.naFila,
      'updated_at': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _enviarEmChamadoExistente({
    required String ticketId,
    required Map<String, dynamic> ticketData,
    required String texto,
    required String uid,
  }) async {
    final status = ticketData['status']?.toString() ?? '';
    if (!SuporteTicketStatusWeb.estaAberto(status)) {
      throw Exception('Este atendimento já foi encerrado.');
    }

    final ticketRef = _tickets.doc(ticketId);
    final etapa = (ticketData['lojista_chat_etapa'] ?? '').toString();
    final lojaNome = (ticketData['solicitante_loja_nome'] ??
            ticketData['user_nome'] ??
            'loja')
        .toString();
    final agora = Timestamp.now();

    await ticketRef.collection('mensagens').add({
      'mensagem': texto,
      'sender_id': uid,
      'sender_type': 'client',
      'is_read': false,
      'created_at': agora,
    });

    final updates = <String, dynamic>{
      'updated_at': FieldValue.serverTimestamp(),
    };
    final preview = (ticketData['first_message_preview'] ?? '').toString();
    if (preview.isEmpty) {
      updates['first_message_preview'] =
          texto.length > 120 ? '${texto.substring(0, 120)}…' : texto;
    }

    if (etapa == LojistaChatEtapa.naFila &&
        status == SuporteTicketStatusWeb.waiting) {
      await ticketRef.collection('mensagens').add({
        'mensagem':
            'Perfeito $lojaNome.\n\nRecebemos sua solicitação.\n\n'
            'Aguarde um momento que um de nossos atendentes irá responder você.',
        'sender_id': uid,
        'sender_type': 'client',
        'suporte_auto': true,
        'is_system': true,
        'is_read': true,
        'created_at': Timestamp.fromMillisecondsSinceEpoch(
          agora.millisecondsSinceEpoch + 1,
        ),
      });
      updates['lojista_chat_etapa'] = LojistaChatEtapa.aguardando;
    }

    await ticketRef.update(updates);
  }

  /// Envia anexo (imagem/PDF) do lojista. Cria o chamado se ainda não existir.
  Future<void> enviarAnexoLojista({
    required String lojaId,
    required Uint8List bytes,
    required String nomeArquivo,
    required String mimeType,
    int? tamanhoBytes,
    String legenda = '',
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw Exception('Não autenticado.');

    final mime = mimeType.trim().isEmpty
        ? _inferirMime(nomeArquivo)
        : mimeType.trim();
    if (!_mimePermitido(mime)) {
      throw Exception(
        'Tipo de arquivo não permitido. Envie imagem (JPG, PNG, WEBP, GIF) ou PDF.',
      );
    }
    final tamanho = tamanhoBytes ?? bytes.length;
    if (tamanho > 20 * 1024 * 1024) {
      throw Exception('Arquivo maior que 20 MB não é permitido.');
    }

    try {
      var aberto = await buscarChamadoAberto();
      var criadoAgora = false;

      if (aberto == null || !aberto.exists) {
        final preview = legenda.trim().isNotEmpty
            ? legenda.trim()
            : (mime.startsWith('image/') ? '📷 Imagem' : '📎 $nomeArquivo');
        await _criarChamadoComPrimeiraMensagem(
          texto: preview,
          lojaId: lojaId,
          uid: uid,
        );
        aberto = await buscarChamadoAberto();
        criadoAgora = true;
        if (aberto == null || !aberto.exists) {
          throw Exception('Não foi possível abrir o chamado.');
        }
      }

      final ticketId = aberto.id;
      final ticketData = aberto.data()!;
      final status = ticketData['status']?.toString() ?? '';
      if (!SuporteTicketStatusWeb.estaAberto(status)) {
        throw Exception('Este atendimento já foi encerrado.');
      }

      final tipoAnexo = mime.startsWith('image/') ? 'image' : 'arquivo';
      final safeNome = _sanitizarNome(nomeArquivo);
      final ts = DateTime.now().millisecondsSinceEpoch;
      final path = 'suporte_anexos/$ticketId/${uid}_${ts}_$safeNome';
      final storageRef = FirebaseStorage.instance.ref(path);
      await storageRef.putData(bytes, SettableMetadata(contentType: mime));
      final url = await storageRef.getDownloadURL();

      final ticketRef = _tickets.doc(ticketId);
      final agora = Timestamp.now();
      final legendaLimpa = legenda.trim();

      await ticketRef.collection('mensagens').add({
        'mensagem': legendaLimpa,
        'sender_id': uid,
        'sender_type': 'client',
        'is_read': false,
        'created_at': agora,
        'anexo_url': url,
        'anexo_nome': nomeArquivo,
        'anexo_tipo': tipoAnexo,
        'anexo_mime': mime,
        'anexo_tamanho': tamanho,
      });

      final updates = <String, dynamic>{
        'updated_at': FieldValue.serverTimestamp(),
      };
      final etapa = (ticketData['lojista_chat_etapa'] ?? '').toString();

      // 2ª interação (não na criação) → confirma assunto
      if (!criadoAgora &&
          etapa == LojistaChatEtapa.naFila &&
          status == SuporteTicketStatusWeb.waiting) {
        final lojaNome = (ticketData['solicitante_loja_nome'] ??
                ticketData['user_nome'] ??
                'loja')
            .toString();
        await ticketRef.collection('mensagens').add({
          'mensagem':
              'Perfeito $lojaNome.\n\nRecebemos sua solicitação.\n\n'
              'Aguarde um momento que um de nossos atendentes irá responder você.',
          'sender_id': uid,
          'sender_type': 'client',
          'suporte_auto': true,
          'is_system': true,
          'is_read': true,
          'created_at': Timestamp.fromMillisecondsSinceEpoch(
            agora.millisecondsSinceEpoch + 1,
          ),
        });
        updates['lojista_chat_etapa'] = LojistaChatEtapa.aguardando;
      }

      await ticketRef.update(updates);
    } catch (e) {
      throw Exception(_mensagemAmigavel(e));
    }
  }

  bool _mimePermitido(String mime) {
    final m = mime.toLowerCase();
    return m.startsWith('image/') || m == 'application/pdf';
  }

  String _inferirMime(String nome) {
    final n = nome.toLowerCase();
    if (n.endsWith('.png')) return 'image/png';
    if (n.endsWith('.jpg') || n.endsWith('.jpeg')) return 'image/jpeg';
    if (n.endsWith('.webp')) return 'image/webp';
    if (n.endsWith('.gif')) return 'image/gif';
    if (n.endsWith('.pdf')) return 'application/pdf';
    return 'application/octet-stream';
  }

  String _sanitizarNome(String nome) {
    final limpo = nome.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    if (limpo.length <= 80) return limpo;
    final ext =
        limpo.contains('.') ? limpo.substring(limpo.lastIndexOf('.')) : '';
    return '${limpo.substring(0, 80 - ext.length)}$ext';
  }

  Future<void> encerrarPeloLojista({
    required String ticketId,
    required String lojaNome,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw Exception('Não autenticado.');

    try {
      final ticketRef = _tickets.doc(ticketId);
      final snap = await ticketRef.get(_getServer);
      if (!snap.exists) throw Exception('Chamado não encontrado.');
      final st = snap.data()?['status']?.toString() ?? '';
      if (!SuporteTicketStatusWeb.estaAberto(st)) return;

      await ticketRef.collection('mensagens').add({
        'mensagem': 'O lojista encerrou o atendimento.',
        'sender_id': uid,
        'sender_type': 'client',
        'suporte_auto': true,
        'is_system': true,
        'is_read': false,
        'created_at': Timestamp.now(),
      });

      await ticketRef.update({
        'status': SuporteTicketStatusWeb.cancelled,
        'finished_at': FieldValue.serverTimestamp(),
        'closed_by': 'client',
        'updated_at': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      throw Exception(_mensagemAmigavel(e));
    }
  }

  static ({String label, int cor, String emoji}) statusVisual({
    required String? status,
    required String? etapa,
  }) {
    if (SuporteTicketStatusWeb.estaFinalizado(status)) {
      return (label: 'Finalizado', cor: 0xFF64748B, emoji: '⚫');
    }
    if (status == SuporteTicketStatusWeb.inProgress) {
      return (label: 'Em Atendimento', cor: 0xFF16A34A, emoji: '🟢');
    }
    if (etapa == LojistaChatEtapa.aguardando) {
      return (
        label: 'Aguardando Atendimento',
        cor: 0xFFFF8F00,
        emoji: '🟡'
      );
    }
    return (label: 'Na fila', cor: 0xFFFF8F00, emoji: '🟠');
  }
}
