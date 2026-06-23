// Leitura do histórico de um protocolo (somente conversa encerrada ou antiga).
// REESTILIZADO — UI moderna mantendo 100% da lógica original.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

const Color _roxo = Color(0xFF6A1B9A);
const Color _laranja = Color(0xFFFF8F00);

class SuporteHistoricoConversaScreen extends StatelessWidget {
  const SuporteHistoricoConversaScreen({super.key, required this.ticketId});

  final String ticketId;

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F7),
      appBar: AppBar(
        title: const Text('Conversa do protocolo'),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF7B1FA2),
                Color(0xFF6A1B9A),
                Color(0xFF4A148C),
              ],
            ),
          ),
        ),
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
      body: SafeArea(
        top: false,
        bottom: true,
        left: true,
        right: true,
        child: uid == null
            ? const Center(child: Text('Faça login.'))
            : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance
                    .collection('support_tickets')
                    .doc(ticketId)
                    .snapshots(),
                builder: (context, snap) {
                  if (!snap.hasData) {
                    return const Center(
                      child: CircularProgressIndicator(color: _roxo),
                    );
                  }
                  final doc = snap.data!;
                  if (!doc.exists) {
                    return const Center(child: Text('Chamado não encontrado.'));
                  }
                  final d = doc.data()!;
                  if (d['user_id']?.toString() != uid) {
                    return const Center(
                      child: Text('Você não tem acesso a este chamado.'),
                    );
                  }
                  final protocolo =
                      (d['protocol_number'] ?? '').toString().padLeft(8, '0');
                  final st = d['status']?.toString() ?? '';

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // --- Card do protocolo ---
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 14, 12, 6),
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.grey.shade200),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.04),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 16,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: _roxo.withValues(alpha: 0.08),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: const Icon(
                                        Icons.verified_outlined,
                                        size: 22,
                                        color: _roxo,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Protocolo $protocolo',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 16,
                                              color: Color(0xFF1A1A2E),
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 3,
                                            ),
                                            decoration: BoxDecoration(
                                              color: _corStatusHistorico(st)
                                                  .withValues(alpha: 0.12),
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                              border: Border.all(
                                                color: _corStatusHistorico(st)
                                                    .withValues(alpha: 0.25),
                                              ),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(
                                                  _iconeStatusHistorico(st),
                                                  size: 12,
                                                  color:
                                                      _corStatusHistorico(st),
                                                ),
                                                const SizedBox(width: 4),
                                                Text(
                                                  _rotuloStatus(st),
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w700,
                                                    color:
                                                        _corStatusHistorico(st),
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
                                const SizedBox(height: 10),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade50,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(Icons.lock_outline_rounded,
                                          size: 14, color: Colors.grey.shade500),
                                      const SizedBox(width: 6),
                                      Text(
                                        'Somente leitura — histórico da conversa.',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontStyle: FontStyle.italic,
                                          color: Colors.grey.shade600,
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
                      // --- Lista de mensagens ---
                      Expanded(
                        child: Container(
                          margin: const EdgeInsets.fromLTRB(8, 4, 8, 10),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.04),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: StreamBuilder<
                              QuerySnapshot<Map<String, dynamic>>>(
                            stream: FirebaseFirestore.instance
                                .collection('support_tickets')
                                .doc(ticketId)
                                .collection('mensagens')
                                .orderBy('created_at', descending: true)
                                .snapshots(),
                            builder: (context, snapMsg) {
                              if (!snapMsg.hasData) {
                                return const Center(
                                  child: CircularProgressIndicator(
                                    color: _roxo,
                                  ),
                                );
                              }
                              final msgs = snapMsg.data!.docs;
                              if (msgs.isEmpty) {
                                return const Center(
                                  child: Padding(
                                    padding: EdgeInsets.all(24),
                                    child: Text(
                                      'Nenhuma mensagem neste chamado.',
                                      style: TextStyle(color: Colors.black54),
                                    ),
                                  ),
                                );
                              }
                              return ListView.builder(
                                reverse: true,
                                padding: const EdgeInsets.fromLTRB(
                                    14, 16, 14, 24),
                                itemCount: msgs.length,
                                itemBuilder: (context, index) {
                                  final msg = msgs[index].data();
                                  final tipo =
                                      msg['sender_type']?.toString() ?? '';
                                  final texto =
                                      msg['mensagem']?.toString() ?? '';

                                  final createdAt = msg['created_at'];
                                  String horario = '';
                                  if (createdAt is Timestamp) {
                                    final dt = createdAt.toDate();
                                    horario =
                                        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
                                  }

                                  if (tipo == 'system') {
                                    return Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 8,
                                      ),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Container(
                                              height: 1,
                                              color: Colors.grey.shade200,
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 6,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.grey.shade100,
                                              borderRadius:
                                                  BorderRadius.circular(14),
                                            ),
                                            child: Text(
                                              texto,
                                              textAlign: TextAlign.center,
                                              style: TextStyle(
                                                fontSize: 11.5,
                                                fontWeight: FontWeight.w600,
                                                color: Colors.grey.shade700,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Container(
                                              height: 1,
                                              color: Colors.grey.shade200,
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  }
                                  final suporteAuto =
                                      msg['suporte_auto'] == true;
                                  final souCliente =
                                      tipo == 'client' && !suporteAuto;

                                  return Padding(
                                    padding: EdgeInsets.only(
                                      left: souCliente ? 48 : 8,
                                      right: souCliente ? 8 : 48,
                                      bottom: 6,
                                    ),
                                    child: Column(
                                      crossAxisAlignment: souCliente
                                          ? CrossAxisAlignment.end
                                          : CrossAxisAlignment.start,
                                      children: [
                                        if (suporteAuto)
                                          Padding(
                                            padding:
                                                const EdgeInsets.only(bottom: 4, left: 4),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Container(
                                                  width: 18,
                                                  height: 18,
                                                  decoration: BoxDecoration(
                                                    color: _laranja
                                                        .withValues(alpha: 0.15),
                                                    borderRadius:
                                                        BorderRadius.circular(6),
                                                  ),
                                                  child: const Icon(
                                                    Icons.support_agent_rounded,
                                                    size: 11,
                                                    color: _laranja,
                                                  ),
                                                ),
                                                const SizedBox(width: 5),
                                                Text(
                                                  'DiPertin',
                                                  style: TextStyle(
                                                    color: _laranja,
                                                    fontSize: 10.5,
                                                    fontWeight: FontWeight.w700,
                                                    letterSpacing: 0.3,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 14,
                                            vertical: 10,
                                          ),
                                          constraints: BoxConstraints(
                                            maxWidth:
                                                MediaQuery.sizeOf(context).width *
                                                    0.78,
                                          ),
                                          decoration: BoxDecoration(
                                            color: souCliente
                                                ? _roxo
                                                : Colors.white,
                                            borderRadius: BorderRadius.only(
                                              topLeft:
                                                  const Radius.circular(18),
                                              topRight:
                                                  const Radius.circular(18),
                                              bottomLeft: souCliente
                                                  ? const Radius.circular(18)
                                                  : const Radius.circular(4),
                                              bottomRight: souCliente
                                                  ? const Radius.circular(4)
                                                  : const Radius.circular(18),
                                            ),
                                            boxShadow: [
                                              BoxShadow(
                                                color: (souCliente
                                                        ? _roxo
                                                        : Colors.black)
                                                    .withValues(
                                                  alpha: souCliente ? 0.15 : 0.06,
                                                ),
                                                blurRadius: 8,
                                                offset: const Offset(0, 2),
                                              ),
                                            ],
                                          ),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              _bolhaConteudoHistorico(
                                                context,
                                                msg,
                                                texto,
                                                souCliente,
                                              ),
                                              const SizedBox(height: 2),
                                              if (horario.isNotEmpty)
                                                Align(
                                                  alignment:
                                                      Alignment.bottomRight,
                                                  child: Text(
                                                    horario,
                                                    style: TextStyle(
                                                      fontSize: 10,
                                                      color: souCliente
                                                          ? Colors.white
                                                              .withValues(alpha: 0.65)
                                                          : Colors.grey.shade500,
                                                    ),
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              );
                            },
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
      ),
    );
  }

  Widget _bolhaConteudoHistorico(
    BuildContext context,
    Map<String, dynamic> msg,
    String texto,
    bool souCliente,
  ) {
    final corTexto = souCliente ? Colors.white : const Color(0xFF1A1A2E);
    final url = (msg['anexo_url'] ?? '').toString();
    if (url.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Text(
          texto,
          style: TextStyle(
            color: corTexto,
            fontSize: 15,
            height: 1.35,
          ),
        ),
      );
    }
    final tipo = (msg['anexo_tipo'] ?? '').toString();
    final nome = (msg['anexo_nome'] ?? 'arquivo').toString();
    final tamanho = (msg['anexo_tamanho'] is num)
        ? (msg['anexo_tamanho'] as num).toInt()
        : 0;

    final anexoCorFundo = souCliente
        ? Colors.white.withValues(alpha: 0.18)
        : _roxo.withValues(alpha: 0.06);
    final anexoIconCor = souCliente ? Colors.white : _roxo;
    final anexoTextSecundario =
        souCliente ? Colors.white70 : Colors.grey.shade600;

    Widget anexo;
    if (tipo == 'image') {
      anexo = GestureDetector(
        onTap: () async {
          final uri = Uri.tryParse(url);
          if (uri == null) return;
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        },
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxHeight: 240,
              minWidth: 160,
            ),
            child: Image.network(
              url,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                height: 120,
                width: 160,
                color: Colors.black.withValues(alpha: 0.25),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.broken_image_outlined,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ),
      );
    } else {
      anexo = InkWell(
        onTap: () async {
          final uri = Uri.tryParse(url);
          if (uri == null) return;
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        },
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: anexoCorFundo,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.insert_drive_file_outlined,
                  color: anexoIconCor, size: 30),
              const SizedBox(width: 10),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      nome,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: corTexto,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      tamanho > 0
                          ? '${_formatarTamanhoHistorico(tamanho)} • toque para abrir'
                          : 'Toque para abrir',
                      style: TextStyle(
                        color: anexoTextSecundario,
                        fontSize: 11,
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        anexo,
        if (texto.trim().isNotEmpty) ...[
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              texto,
              style: TextStyle(
                color: corTexto,
                fontSize: 15,
                height: 1.35,
              ),
            ),
          ),
        ],
      ],
    );
  }

  static String _formatarTamanhoHistorico(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  static IconData _iconeStatusHistorico(String s) {
    switch (s) {
      case 'waiting':
        return Icons.access_time_rounded;
      case 'in_progress':
        return Icons.support_agent_rounded;
      case 'finished':
      case 'closed':
        return Icons.check_circle_rounded;
      case 'cancelled':
        return Icons.cancel_outlined;
      default:
        return Icons.chat_bubble_outline_rounded;
    }
  }

  static Color _corStatusHistorico(String s) {
    switch (s) {
      case 'waiting':
        return _laranja;
      case 'in_progress':
        return const Color(0xFF2563EB);
      case 'finished':
      case 'closed':
        return const Color(0xFF16A34A);
      case 'cancelled':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  static String _rotuloStatus(String s) {
    switch (s) {
      case 'waiting':
        return 'Aguardando';
      case 'in_progress':
        return 'Em atendimento';
      case 'cancelled':
        return 'Encerrado por você';
      case 'closed':
        return 'Encerrado pelo suporte';
      case 'finished':
        return 'Finalizado';
      default:
        return s;
    }
  }
}
