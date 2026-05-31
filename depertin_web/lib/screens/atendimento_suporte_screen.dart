// Atendimento / suporte — support_tickets (protocolo, fila, chat em tempo real)

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:depertin_web/constants/suporte_categorias.dart';
import 'package:depertin_web/theme/painel_admin_theme.dart';
import 'package:depertin_web/utils/admin_perfil.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

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

/// Sufixo nos cards da fila/lista: categoria já escolhida ou pendente.
String _legendaCategoriaNaLista(Map<String, dynamic> m) {
  final lab = (m['categoria_label'] ?? '').toString().trim();
  if (lab.isNotEmpty) return ' · $lab';
  final prev = (m['first_message_preview'] ?? '').toString().trim();
  if (prev.isNotEmpty) return ' · categoria pendente';
  return '';
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

String _rotuloPerfilSolicitante(String perfil) {
  switch (perfil.trim().toLowerCase()) {
    case 'lojista':
      return 'Lojista';
    case 'entregador':
      return 'Entregador';
    case 'cliente':
    default:
      return 'Cliente';
  }
}

IconData _iconePerfilSolicitante(String perfil) {
  switch (perfil.trim().toLowerCase()) {
    case 'lojista':
      return Icons.storefront_rounded;
    case 'entregador':
      return Icons.delivery_dining_rounded;
    case 'cliente':
    default:
      return Icons.person_rounded;
  }
}

Color _corPerfilSolicitante(String perfil) {
  switch (perfil.trim().toLowerCase()) {
    case 'lojista':
      return PainelAdminTheme.roxo;
    case 'entregador':
      return const Color(0xFF0F766E);
    case 'cliente':
    default:
      return PainelAdminTheme.laranja;
  }
}

class AtendimentoSuporteScreen extends StatefulWidget {
  const AtendimentoSuporteScreen({super.key});

  @override
  State<AtendimentoSuporteScreen> createState() =>
      _AtendimentoSuporteScreenState();
}

class _AtendimentoSuporteScreenState extends State<AtendimentoSuporteScreen> {
  static const Color diPertinRoxo = PainelAdminTheme.roxo;
  static const Color diPertinLaranja = PainelAdminTheme.laranja;

  String? _selecionadoId;
  String? _selecionadoNome;
  final TextEditingController _mensagemController = TextEditingController();
  bool _enviandoAnexo = false;

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
      final docSnap = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (docSnap.exists) {
        final dados = docSnap.data()!;
        setState(() {
          _tipoUsuarioLogado = perfilAdministrativo(dados);
          _cidadeLogado = (dados['cidade'] ?? '')
              .toString()
              .trim()
              .toLowerCase();
        });
      }
    }
  }

  Query<Map<String, dynamic>> _queryFila() {
    Query<Map<String, dynamic>> q = FirebaseFirestore.instance
        .collection('support_tickets')
        .where('status', isEqualTo: _kWaiting);
    if (_tipoUsuarioLogado == 'master_city') {
      q = q.where(
        'cidade',
        isEqualTo: _cidadeLogado.isEmpty ? '—' : _cidadeLogado,
      );
    }
    return q.orderBy('created_at', descending: false);
  }

  Query<Map<String, dynamic>> _queryAndamento() {
    Query<Map<String, dynamic>> q = FirebaseFirestore.instance
        .collection('support_tickets')
        .where('status', isEqualTo: _kInProgress);
    if (_tipoUsuarioLogado == 'master_city') {
      q = q.where(
        'cidade',
        isEqualTo: _cidadeLogado.isEmpty ? '—' : _cidadeLogado,
      );
    }
    return q.orderBy('updated_at', descending: true);
  }

  /// Chamados encerrados (leitura / pesquisa no painel).
  Query<Map<String, dynamic>> _queryHistorico() {
    Query<Map<String, dynamic>> q = FirebaseFirestore.instance
        .collection('support_tickets')
        .where('status', whereIn: _kHistoricoStatuses);
    if (_tipoUsuarioLogado == 'master_city') {
      q = q.where(
        'cidade',
        isEqualTo: _cidadeLogado.isEmpty ? '—' : _cidadeLogado,
      );
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

    final ref = FirebaseFirestore.instance
        .collection('support_tickets')
        .doc(id);
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
        final cat = (d['categoria_suporte'] ?? '').toString().trim();
        final prev = (d['first_message_preview'] ?? '').toString().trim();
        if (cat.isEmpty && prev.isNotEmpty) {
          throw Exception(
            'Categoria ainda não registrada: peça ao cliente para escolher na '
            'Central de Ajuda ou defina pelo botão «Definir categoria» no painel.',
          );
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
        mostrarSnackPainel(
          context,
          mensagem: 'Atendimento iniciado com sucesso.',
        );
      }
    } catch (e) {
      if (mounted) {
        mostrarSnackPainel(context, mensagem: '$e', erro: true);
      }
    }
  }

  Future<void> _definirCategoriaPeloPainel() async {
    final id = _selecionadoId;
    if (id == null) return;

    var codigoEscolhido = SuporteCategorias.opcoes.first.codigo;

    final confirmado = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setLocal) {
            return AlertDialog(
              title: const Text('Definir categoria'),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Este chamado tem mensagem do cliente, mas a categoria '
                      'ainda não foi registrada (fluxo normal da Central de Ajuda '
                      'no app). Defina a categoria aqui para liberar '
                      '«Iniciar atendimento».',
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.45,
                        color: PainelAdminTheme.textoSecundario,
                      ),
                    ),
                    const SizedBox(height: 18),
                    InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Categoria',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          isExpanded: true,
                          value: codigoEscolhido,
                          items: [
                            for (final o in SuporteCategorias.opcoes)
                              DropdownMenuItem<String>(
                                value: o.codigo,
                                child: Text(o.rotulo),
                              ),
                          ],
                          onChanged: (v) {
                            if (v != null) {
                              setLocal(() => codigoEscolhido = v);
                            }
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  style: FilledButton.styleFrom(
                    backgroundColor: PainelAdminTheme.laranja,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Salvar'),
                ),
              ],
            );
          },
        );
      },
    );

    if (confirmado != true || !mounted) return;

    final codigoOk = SuporteCategorias.codigoValido(codigoEscolhido);
    if (codigoOk == null) return;

    try {
      await FirebaseFirestore.instance
          .collection('support_tickets')
          .doc(id)
          .update({
            'categoria_suporte': codigoOk,
            'categoria_label': SuporteCategorias.rotuloPorCodigo(codigoOk),
            'updated_at': FieldValue.serverTimestamp(),
          });
      if (mounted) {
        mostrarSnackPainel(
          context,
          mensagem: 'Categoria registrada. Você já pode iniciar o atendimento.',
        );
      }
    } catch (e) {
      if (mounted) {
        mostrarSnackPainel(context, mensagem: '$e', erro: true);
      }
    }
  }

  Future<String> _nomeAtendente(String uid) async {
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .get();
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

    final ticketRef = FirebaseFirestore.instance
        .collection('support_tickets')
        .doc(id);
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
      await ticketRef.update({'updated_at': FieldValue.serverTimestamp()});
    } catch (e) {
      if (mounted) {
        mostrarSnackPainel(context, mensagem: 'Erro ao enviar: $e', erro: true);
      }
    }
  }

  /// Upload de anexo pelo atendente. Abre o FilePicker, sobe em
  /// `suporte_anexos/{ticketId}` e cria a mensagem com os campos `anexo_*`.
  Future<void> _enviarAnexo() async {
    final id = _selecionadoId;
    if (id == null || _enviandoAnexo) return;

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final ticketRef = FirebaseFirestore.instance
        .collection('support_tickets')
        .doc(id);
    final snap = await ticketRef.get();
    if (!snap.exists) return;
    final d = snap.data()!;
    if (d['status'] != _kInProgress || d['agent_id'] != uid) {
      if (mounted) {
        mostrarSnackPainel(
          context,
          mensagem:
              'Só o atendente responsável pode enviar anexos neste chamado.',
          erro: true,
        );
      }
      return;
    }

    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        withData: true,
        allowMultiple: false,
      );
    } catch (e) {
      if (mounted) {
        mostrarSnackPainel(
          context,
          mensagem: 'Erro ao abrir seletor de arquivos: $e',
          erro: true,
        );
      }
      return;
    }
    if (result == null || result.files.isEmpty) return;
    final picked = result.files.single;
    final bytes = picked.bytes;
    if (bytes == null) {
      if (mounted) {
        mostrarSnackPainel(
          context,
          mensagem: 'Não foi possível ler o arquivo.',
          erro: true,
        );
      }
      return;
    }
    if (picked.size > 20 * 1024 * 1024) {
      if (mounted) {
        mostrarSnackPainel(
          context,
          mensagem: 'Arquivo maior que 20 MB não é permitido.',
          erro: true,
        );
      }
      return;
    }

    final mime = _inferirMimeSuporte(picked.name);
    final tipoAnexo = mime.startsWith('image/') ? 'image' : 'arquivo';
    final safeNome = _sanitizarNomeSuporte(picked.name);
    final ts = DateTime.now().millisecondsSinceEpoch;
    final path = 'suporte_anexos/$id/${uid}_${ts}_$safeNome';

    setState(() => _enviandoAnexo = true);
    try {
      final ref = FirebaseStorage.instance.ref(path);
      await ref.putData(bytes, SettableMetadata(contentType: mime));
      final url = await ref.getDownloadURL();

      await ticketRef.collection('mensagens').add({
        'mensagem': '',
        'sender_id': uid,
        'sender_type': 'agent',
        'is_read': false,
        'created_at': FieldValue.serverTimestamp(),
        'anexo_url': url,
        'anexo_nome': picked.name,
        'anexo_tipo': tipoAnexo,
        'anexo_mime': mime,
        'anexo_tamanho': picked.size,
      });
      await ticketRef.update({'updated_at': FieldValue.serverTimestamp()});
    } catch (e) {
      if (mounted) {
        mostrarSnackPainel(
          context,
          mensagem: 'Erro ao enviar anexo: $e',
          erro: true,
        );
      }
    } finally {
      if (mounted) setState(() => _enviandoAnexo = false);
    }
  }

  String _inferirMimeSuporte(String nome) {
    final n = nome.toLowerCase();
    if (n.endsWith('.png')) return 'image/png';
    if (n.endsWith('.jpg') || n.endsWith('.jpeg')) return 'image/jpeg';
    if (n.endsWith('.webp')) return 'image/webp';
    if (n.endsWith('.gif')) return 'image/gif';
    if (n.endsWith('.pdf')) return 'application/pdf';
    if (n.endsWith('.doc')) return 'application/msword';
    if (n.endsWith('.docx')) {
      return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
    }
    if (n.endsWith('.xls')) return 'application/vnd.ms-excel';
    if (n.endsWith('.xlsx')) {
      return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
    }
    if (n.endsWith('.txt')) return 'text/plain';
    if (n.endsWith('.zip')) return 'application/zip';
    return 'application/octet-stream';
  }

  String _sanitizarNomeSuporte(String nome) {
    final limpo = nome.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    if (limpo.length <= 80) return limpo;
    final ext = limpo.contains('.')
        ? limpo.substring(limpo.lastIndexOf('.'))
        : '';
    return '${limpo.substring(0, 80 - ext.length)}$ext';
  }

  String _formatarTamanhoSuporte(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Widget _bolhaConteudoSuporte(
    Map<String, dynamic> msg,
    String texto,
    Color fg,
  ) {
    final url = (msg['anexo_url'] ?? '').toString();
    if (url.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(4),
        child: Text(texto, style: TextStyle(color: fg, fontSize: 15)),
      );
    }
    final tipo = (msg['anexo_tipo'] ?? '').toString();
    final nome = (msg['anexo_nome'] ?? 'arquivo').toString();
    final tamanho = (msg['anexo_tamanho'] is num)
        ? (msg['anexo_tamanho'] as num).toInt()
        : 0;

    Widget anexoWidget;
    if (tipo == 'image') {
      anexoWidget = GestureDetector(
        onTap: () => _abrirAnexoSuporte(url),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 260, minWidth: 200),
            child: Image.network(
              url,
              fit: BoxFit.cover,
              loadingBuilder: (ctx, child, progress) {
                if (progress == null) return child;
                return Container(
                  height: 180,
                  width: 200,
                  color: Colors.black.withValues(alpha: 0.08),
                  alignment: Alignment.center,
                  child: const CircularProgressIndicator(strokeWidth: 2),
                );
              },
              errorBuilder: (_, _, _) => Container(
                height: 140,
                width: 200,
                color: Colors.black.withValues(alpha: 0.15),
                alignment: Alignment.center,
                child: Icon(Icons.broken_image_outlined, color: fg),
              ),
            ),
          ),
        ),
      );
    } else {
      final corFundo = fg == Colors.white
          ? Colors.white.withValues(alpha: 0.18)
          : Colors.grey[300]!;
      anexoWidget = InkWell(
        onTap: () => _abrirAnexoSuporte(url),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: corFundo,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.insert_drive_file_outlined, color: fg, size: 30),
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
                      style: TextStyle(color: fg, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      tamanho > 0
                          ? '${_formatarTamanhoSuporte(tamanho)} • clique para abrir'
                          : 'Clique para abrir',
                      style: TextStyle(
                        color: fg.withValues(alpha: 0.75),
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
        anexoWidget,
        if (texto.trim().isNotEmpty) ...[
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(texto, style: TextStyle(color: fg, fontSize: 15)),
          ),
        ],
      ],
    );
  }

  /// Banner exibido ao atendente (somente quando o ticket está encerrado)
  /// com a avaliação que o cliente deixou em `support_ratings`. Caso o
  /// cliente ainda não tenha avaliado, mostra um aviso discreto "Aguardando
  /// avaliação do cliente".
  Widget _bannerAvaliacaoCliente(String ticketId) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('support_ratings')
          .where('ticket_id', isEqualTo: ticketId)
          .limit(1)
          .snapshots(),
      builder: (context, snap) {
        final temAvaliacao = snap.hasData && snap.data!.docs.isNotEmpty;
        if (!temAvaliacao) {
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Colors.amber.shade50,
            child: Row(
              children: [
                Icon(
                  Icons.hourglass_bottom,
                  size: 16,
                  color: Colors.amber[800],
                ),
                const SizedBox(width: 8),
                Text(
                  'Aguardando avaliação do cliente…',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.amber[900],
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          );
        }
        final dados = snap.data!.docs.first.data();
        final rating = (dados['rating'] is num)
            ? (dados['rating'] as num).toInt()
            : 0;
        final comentario = (dados['comment'] ?? '').toString().trim();
        final criadoEm = dados['created_at'];
        final quando = criadoEm is Timestamp ? _fmtHora(criadoEm) : '';
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFF6F0FB),
            border: Border(
              bottom: BorderSide(color: diPertinRoxo.withValues(alpha: 0.15)),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.reviews, size: 18, color: diPertinRoxo),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Avaliação do cliente',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            color: diPertinRoxo,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Row(
                          children: List.generate(5, (i) {
                            final ativa = i < rating;
                            return Icon(
                              ativa
                                  ? Icons.star_rounded
                                  : Icons.star_border_rounded,
                              color: diPertinLaranja,
                              size: 18,
                            );
                          }),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '$rating/5',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.black87,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (quando.isNotEmpty) ...[
                          const SizedBox(width: 10),
                          Text(
                            '· $quando',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (comentario.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        '"$comentario"',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontStyle: FontStyle.italic,
                          color: Colors.grey[800],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _chipStatusSuporte(
    BuildContext context, {
    required bool aguardando,
    required bool emAndamento,
    required bool encerrado,
  }) {
    late String rotulo;
    late Color bg;
    late Color fg;
    late IconData ic;
    if (aguardando) {
      rotulo = 'Na fila';
      ic = Icons.schedule_rounded;
      bg = PainelAdminTheme.laranja.withValues(alpha: 0.14);
      fg = const Color(0xFFB45309);
    } else if (emAndamento) {
      rotulo = 'Em atendimento';
      ic = Icons.headset_mic_rounded;
      bg = const Color(0xFFDBEAFE);
      fg = const Color(0xFF1D4ED8);
    } else if (encerrado) {
      rotulo = 'Encerrado';
      ic = Icons.check_circle_outline_rounded;
      bg = const Color(0xFFD1FAE5);
      fg = const Color(0xFF047857);
    } else {
      rotulo = 'Status';
      ic = Icons.info_outline_rounded;
      bg = Colors.grey.shade200;
      fg = Colors.grey.shade800;
    }
    return Chip(
      avatar: Icon(ic, size: 16, color: fg),
      label: Text(
        rotulo,
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: fg),
      ),
      backgroundColor: bg,
      side: BorderSide.none,
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: 8),
    );
  }

  Widget _chipPerfilSolicitante(String perfil) {
    final cor = _corPerfilSolicitante(perfil);
    return Chip(
      avatar: Icon(_iconePerfilSolicitante(perfil), size: 16, color: cor),
      label: Text(
        _rotuloPerfilSolicitante(perfil),
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: cor),
      ),
      backgroundColor: cor.withValues(alpha: 0.10),
      side: BorderSide.none,
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: 8),
    );
  }

  Widget _resumoSolicitanteSuporte({
    required String perfil,
    required String email,
    required String telefone,
    required String documento,
    required String lojaNome,
    required String cidade,
  }) {
    final itens = <Widget>[
      if (email.isNotEmpty) _miniDadoSolicitante(Icons.email_outlined, email),
      if (telefone.isNotEmpty)
        _miniDadoSolicitante(Icons.phone_outlined, telefone),
      if (documento.isNotEmpty)
        _miniDadoSolicitante(
          Icons.badge_outlined,
          perfil == 'lojista' ? 'Documento: $documento' : 'CPF: $documento',
        ),
      if (perfil == 'lojista' && lojaNome.isNotEmpty)
        _miniDadoSolicitante(Icons.storefront_outlined, lojaNome),
      if (cidade.isNotEmpty && cidade != '—')
        _miniDadoSolicitante(Icons.location_city_outlined, cidade),
    ];
    if (itens.isEmpty) return const SizedBox.shrink();
    return Wrap(spacing: 8, runSpacing: 8, children: itens);
  }

  Widget _miniDadoSolicitante(IconData icon, String texto) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: PainelAdminTheme.fundoCanvas,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: PainelAdminTheme.dashboardBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: PainelAdminTheme.textoSecundario),
          const SizedBox(width: 5),
          Text(
            texto,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: PainelAdminTheme.textoSecundario,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _abrirAnexoSuporte(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      if (mounted) {
        mostrarSnackPainel(
          context,
          mensagem: 'Não foi possível abrir o anexo.',
          erro: true,
        );
      }
    }
  }

  Future<void> _reabrirChamado() async {
    final id = _selecionadoId;
    if (id == null) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final confirma = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reabrir atendimento'),
        content: const Text(
          'Deseja reabrir este chamado? O cliente voltará a receber '
          'mensagens suas neste atendimento.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.replay),
            label: const Text('Reabrir'),
          ),
        ],
      ),
    );
    if (confirma != true) return;

    final ref = FirebaseFirestore.instance
        .collection('support_tickets')
        .doc(id);

    try {
      // 1) Assume a titularidade como atendente e muda status para in_progress.
      //    (faz isso antes para que a regra de criação de mensagem system/agent
      //    com `status == in_progress && agent_id == request.auth.uid` passe).
      final meuDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      final meuNome = (meuDoc.data()?['nome'] ?? '').toString().trim();

      await ref.update({
        'status': _kInProgress,
        'agent_id': uid,
        'agent_nome': meuNome.isEmpty ? 'Atendente' : meuNome,
        'finished_at': null,
        'closed_by': null,
        'reabertura_count': FieldValue.increment(1),
        'reaberto_em': FieldValue.serverTimestamp(),
        'updated_at': FieldValue.serverTimestamp(),
      });

      // 2) Registra a mensagem de sistema sinalizando a reabertura.
      await ref.collection('mensagens').add({
        'mensagem': '--- Atendimento reaberto pelo suporte ---',
        'sender_id': uid,
        'sender_type': 'system',
        'is_read': false,
        'created_at': FieldValue.serverTimestamp(),
      });

      setState(() => _selecionadoId = id);
      if (mounted) {
        mostrarSnackPainel(context, mensagem: 'Atendimento reaberto.');
      }
    } catch (e) {
      if (mounted) {
        mostrarSnackPainel(
          context,
          mensagem: 'Erro ao reabrir: $e',
          erro: true,
        );
      }
    }
  }

  Future<void> _encerrarChamado() async {
    final id = _selecionadoId;
    if (id == null) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final ref = FirebaseFirestore.instance
        .collection('support_tickets')
        .doc(id);
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
                                    .sendPasswordResetEmail(
                                      email: emailUsuario,
                                    );
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
                            icon: const Icon(
                              Icons.lock_reset,
                              color: Colors.red,
                            ),
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

    Widget listaTickets() {
      return ColunaFilaSuporte(
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
            _selecionadoNome = m['user_nome']?.toString() ?? 'Cliente';
          });
        },
        fmtHora: _fmtHora,
        tempoEspera: _tempoEspera,
        posicaoNaFila: _posicaoNaFila,
      );
    }

    Widget conversa() {
      return DecoratedBox(
        decoration: PainelAdminTheme.dashboardCard(),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: _painelChat(uid),
        ),
      );
    }

    return Scaffold(
      backgroundColor: PainelAdminTheme.fundoCanvas,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final estreito = constraints.maxWidth < 1000;
            final pad = estreito ? 12.0 : 22.0;
            if (estreito) {
              return Padding(
                padding: EdgeInsets.all(pad),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(height: 340, child: listaTickets()),
                    const SizedBox(height: 14),
                    Expanded(child: conversa()),
                  ],
                ),
              );
            }
            return Padding(
              padding: EdgeInsets.all(pad),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(width: 392, child: listaTickets()),
                  const SizedBox(width: 22),
                  Expanded(child: conversa()),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _painelChat(String? uidMeu) {
    if (_selecionadoId == null) {
      return Container(
        color: Colors.white,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Padding(
              padding: const EdgeInsets.all(36),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(26),
                    decoration: BoxDecoration(
                      color: PainelAdminTheme.roxo.withValues(alpha: 0.06),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: PainelAdminTheme.roxo.withValues(alpha: 0.12),
                      ),
                    ),
                    child: Icon(
                      Icons.forum_outlined,
                      size: 52,
                      color: PainelAdminTheme.roxo.withValues(alpha: 0.55),
                    ),
                  ),
                  const SizedBox(height: 26),
                  Text(
                    'Selecione um protocolo',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: PainelAdminTheme.dashboardInk,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.4,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Na coluna ao lado, escolha um chamado na fila, em atendimento '
                    'ou no histórico para visualizar a conversa e responder ao cliente.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      height: 1.5,
                      color: PainelAdminTheme.textoSecundario,
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
        final protocolo = (d['protocol_number'] ?? '').toString().padLeft(
          8,
          '0',
        );
        final preview =
            (d['first_message_preview'] ?? '').toString().trim().isEmpty
            ? '(sem prévia)'
            : d['first_message_preview'].toString();
        final perfilSolicitante = (d['solicitante_perfil'] ?? 'cliente')
            .toString();
        final nomeSolicitante = (d['solicitante_nome'] ?? d['user_nome'] ?? '')
            .toString()
            .trim();
        final emailSolicitante = (d['solicitante_email'] ?? '')
            .toString()
            .trim();
        final telefoneSolicitante = (d['solicitante_telefone'] ?? '')
            .toString()
            .trim();
        final documentoSolicitante = (d['solicitante_documento'] ?? '')
            .toString()
            .trim();
        final lojaSolicitante = (d['solicitante_loja_nome'] ?? '')
            .toString()
            .trim();
        final cidadeSolicitante = (d['solicitante_cidade'] ?? d['cidade'] ?? '')
            .toString()
            .trim();

        final possoResponder =
            st == _kInProgress && uidMeu != null && agentId == uidMeu;
        final aguardando = st == _kWaiting;
        final emAndamento = st == _kInProgress;
        final encerrado =
            st == _kClosed || st == 'finished' || st == 'cancelled';

        final nomeTopo = nomeSolicitante.isNotEmpty
            ? nomeSolicitante
            : (_selecionadoNome ?? '').trim();
        final letraAvatar = nomeTopo.isEmpty
            ? 'C'
            : nomeTopo.substring(0, 1).toUpperCase();

        return Column(
          children: [
            Material(
              color: Colors.white,
              elevation: 0,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: PainelAdminTheme.dashboardBorder),
                  ),
                  gradient: LinearGradient(
                    colors: [
                      Colors.white,
                      PainelAdminTheme.fundoCanvas.withValues(alpha: 0.35),
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CircleAvatar(
                          radius: 22,
                          backgroundColor: PainelAdminTheme.roxo.withValues(
                            alpha: 0.12,
                          ),
                          child: Text(
                            letraAvatar,
                            style: const TextStyle(
                              color: PainelAdminTheme.roxo,
                              fontWeight: FontWeight.w800,
                              fontSize: 18,
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                nomeTopo.isEmpty ? 'Cliente' : nomeTopo,
                                style: Theme.of(context).textTheme.titleLarge
                                    ?.copyWith(
                                      fontWeight: FontWeight.w800,
                                      color: PainelAdminTheme.dashboardInk,
                                      letterSpacing: -0.3,
                                    ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Protocolo $protocolo',
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      fontWeight: FontWeight.w600,
                                      color: PainelAdminTheme.textoSecundario,
                                    ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                preview,
                                style: Theme.of(context).textTheme.bodySmall,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  _chipStatusSuporte(
                                    context,
                                    aguardando: aguardando,
                                    emAndamento: emAndamento,
                                    encerrado: encerrado,
                                  ),
                                  _chipPerfilSolicitante(perfilSolicitante),
                                  if ((d['categoria_label'] ?? '')
                                      .toString()
                                      .trim()
                                      .isNotEmpty)
                                    Chip(
                                      avatar: Icon(
                                        Icons.category_outlined,
                                        size: 16,
                                        color: PainelAdminTheme.roxo,
                                      ),
                                      label: Text(
                                        d['categoria_label'].toString(),
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      backgroundColor: PainelAdminTheme.roxo
                                          .withValues(alpha: 0.08),
                                      side: BorderSide.none,
                                      visualDensity: VisualDensity.compact,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                      ),
                                    )
                                  else if (aguardando &&
                                      preview != '(sem prévia)')
                                    Chip(
                                      avatar: Icon(
                                        Icons.hourglass_top_rounded,
                                        size: 16,
                                        color: Colors.orange.shade800,
                                      ),
                                      label: Text(
                                        'Categoria pendente no app',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.orange.shade900,
                                        ),
                                      ),
                                      backgroundColor: Colors.orange.shade50,
                                      side: BorderSide.none,
                                      visualDensity: VisualDensity.compact,
                                    ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              _resumoSolicitanteSuporte(
                                perfil: perfilSolicitante,
                                email: emailSolicitante,
                                telefone: telefoneSolicitante,
                                documento: documentoSolicitante,
                                lojaNome: lojaSolicitante,
                                cidade: cidadeSolicitante,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    if (aguardando &&
                        (d['categoria_suporte'] ?? '')
                            .toString()
                            .trim()
                            .isEmpty &&
                        preview != '(sem prévia)')
                      Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.orange.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.orange.shade200),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  Icons.info_outline_rounded,
                                  color: Colors.orange.shade900,
                                  size: 22,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Categoria obrigatória antes de iniciar',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 13,
                                          color: Colors.orange.shade900,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        'No app, o cliente deve escolher uma '
                                        'categoria na Central de Ajuda depois '
                                        'da primeira mensagem. Enquanto isso não '
                                        'ocorre, «Iniciar» permanece desabilitado. '
                                        'Use «Definir categoria» se precisar '
                                        'assumir o chamado agora.',
                                        style: TextStyle(
                                          fontSize: 12.5,
                                          height: 1.4,
                                          color: Colors.brown.shade800,
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
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      alignment: WrapAlignment.start,
                      children: [
                        if (userClienteId != null)
                          OutlinedButton.icon(
                            onPressed: () =>
                                _abrirModalEditarUsuario(userClienteId),
                            icon: const Icon(
                              Icons.manage_accounts_outlined,
                              size: 18,
                            ),
                            label: const Text('Ficha do solicitante'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: PainelAdminTheme.roxo,
                              side: BorderSide(
                                color: PainelAdminTheme.roxo.withValues(
                                  alpha: 0.35,
                                ),
                              ),
                            ),
                          ),
                        if (aguardando &&
                            (d['categoria_suporte'] ?? '')
                                .toString()
                                .trim()
                                .isEmpty &&
                            preview != '(sem prévia)')
                          OutlinedButton.icon(
                            onPressed: _definirCategoriaPeloPainel,
                            icon: const Icon(Icons.category_outlined, size: 20),
                            label: const Text('Definir categoria'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: PainelAdminTheme.roxo,
                              side: BorderSide(
                                color: PainelAdminTheme.roxo.withValues(
                                  alpha: 0.45,
                                ),
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                            ),
                          ),
                        if (aguardando)
                          Tooltip(
                            message:
                                (d['categoria_suporte'] ?? '')
                                        .toString()
                                        .trim()
                                        .isEmpty &&
                                    preview != '(sem prévia)'
                                ? 'O cliente precisa registrar a categoria no '
                                      'app depois da primeira mensagem, ou use '
                                      '«Definir categoria» ao lado.'
                                : '',
                            child: FilledButton.icon(
                              onPressed:
                                  (d['categoria_suporte'] ?? '')
                                          .toString()
                                          .trim()
                                          .isEmpty &&
                                      preview != '(sem prévia)'
                                  ? null
                                  : _iniciarAtendimentoPainel,
                              icon: const Icon(
                                Icons.play_arrow_rounded,
                                size: 20,
                              ),
                              label: const Text('Iniciar atendimento'),
                              style: FilledButton.styleFrom(
                                backgroundColor: PainelAdminTheme.laranja,
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ),
                        if (emAndamento)
                          FilledButton.icon(
                            onPressed: _encerrarChamado,
                            icon: const Icon(Icons.task_alt_rounded, size: 20),
                            label: const Text('Finalizar'),
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF047857),
                              foregroundColor: Colors.white,
                            ),
                          ),
                        if (encerrado)
                          FilledButton.icon(
                            onPressed: _reabrirChamado,
                            icon: const Icon(Icons.replay_rounded, size: 20),
                            label: const Text('Reabrir'),
                            style: FilledButton.styleFrom(
                              backgroundColor: PainelAdminTheme.laranja,
                              foregroundColor: Colors.white,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            if (encerrado) _bannerAvaliacaoCliente(_selecionadoId!),
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
                  return Container(
                    color: PainelAdminTheme.fundoCanvas.withValues(alpha: 0.5),
                    child: ListView.builder(
                      reverse: true,
                      padding: const EdgeInsets.fromLTRB(18, 16, 18, 20),
                      itemCount: msgs.length,
                      itemBuilder: (context, index) {
                        final msg = msgs[index].data();
                        final tipo = msg['sender_type']?.toString() ?? '';
                        final texto = msg['mensagem']?.toString() ?? '';
                        final suporteAuto = msg['suporte_auto'] == true;
                        if (tipo == 'system' || suporteAuto) {
                          return Center(
                            child: Container(
                              margin: const EdgeInsets.symmetric(vertical: 10),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              constraints: const BoxConstraints(maxWidth: 520),
                              decoration: BoxDecoration(
                                color: suporteAuto
                                    ? diPertinLaranja.withValues(alpha: 0.12)
                                    : Colors.grey[300],
                                borderRadius: BorderRadius.circular(10),
                                border: suporteAuto
                                    ? Border.all(
                                        color: diPertinLaranja.withValues(
                                          alpha: 0.5,
                                        ),
                                      )
                                    : null,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (suporteAuto)
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 6),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.support_agent,
                                            size: 14,
                                            color: diPertinLaranja,
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            'Mensagem automática · Central de Ajuda',
                                            style: TextStyle(
                                              color: diPertinLaranja,
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  Text(
                                    texto,
                                    style: TextStyle(
                                      fontSize: suporteAuto ? 13 : 12,
                                      fontWeight: suporteAuto
                                          ? FontWeight.w500
                                          : FontWeight.bold,
                                      color: suporteAuto
                                          ? Colors.black87
                                          : Colors.black54,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }
                        final ehCliente = tipo == 'client';
                        final alinhamento = ehCliente
                            ? Alignment.centerLeft
                            : Alignment.centerRight;
                        final bg = ehCliente ? Colors.white : diPertinRoxo;
                        final fg = ehCliente
                            ? PainelAdminTheme.dashboardInk
                            : Colors.white;
                        return Align(
                          alignment: alinhamento,
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(12),
                            constraints: const BoxConstraints(maxWidth: 440),
                            decoration: BoxDecoration(
                              color: bg,
                              borderRadius: BorderRadius.circular(14),
                              border: ehCliente
                                  ? Border.all(
                                      color: PainelAdminTheme.dashboardBorder,
                                    )
                                  : null,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.05),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: _bolhaConteudoSuporte(msg, texto, fg),
                          ),
                        );
                      },
                    ),
                  );
                },
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 16),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border(
                  top: BorderSide(color: PainelAdminTheme.dashboardBorder),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  IconButton(
                    tooltip: 'Anexar arquivo',
                    style: IconButton.styleFrom(
                      foregroundColor: possoResponder
                          ? PainelAdminTheme.roxo
                          : Colors.grey,
                    ),
                    icon: _enviandoAnexo
                        ? SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: diPertinRoxo,
                            ),
                          )
                        : Icon(
                            Icons.attach_file,
                            color: possoResponder ? diPertinRoxo : Colors.grey,
                          ),
                    onPressed: possoResponder && !_enviandoAnexo
                        ? _enviarAnexo
                        : null,
                  ),
                  Expanded(
                    child: TextField(
                      controller: _mensagemController,
                      enabled: possoResponder && !_enviandoAnexo,
                      minLines: 1,
                      maxLines: 5,
                      decoration: InputDecoration(
                        hintText: encerrado
                            ? 'Chamado encerrado (somente leitura).'
                            : possoResponder
                            ? 'Digite sua resposta ao cliente…'
                            : aguardando
                            ? 'Inicie o atendimento para responder.'
                            : 'Apenas o atendente responsável pode enviar mensagens.',
                        filled: true,
                        fillColor: PainelAdminTheme.fundoCanvas.withValues(
                          alpha: 0.65,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(
                            color: PainelAdminTheme.dashboardBorder,
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(
                            color: PainelAdminTheme.dashboardBorder,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(
                            color: PainelAdminTheme.roxo,
                            width: 1.5,
                          ),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 14,
                        ),
                      ),
                      onSubmitted: (_) {
                        if (possoResponder) _enviarMensagem();
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  FilledButton(
                    onPressed: possoResponder ? _enviarMensagem : null,
                    style: FilledButton.styleFrom(
                      backgroundColor: PainelAdminTheme.laranja,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 22,
                        vertical: 14,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Icon(Icons.send_rounded, size: 22),
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
  )
  posicaoNaFila;

  @override
  State<ColunaFilaSuporte> createState() => _ColunaFilaSuporteState();
}

class _ColunaFilaSuporteState extends State<ColunaFilaSuporte>
    with SingleTickerProviderStateMixin {
  final TextEditingController _filtroNome = TextEditingController();
  final TextEditingController _filtroProtocolo = TextEditingController();
  DateTime? _dataDe;
  DateTime? _dataAte;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
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
        final p = (m['protocol_number'] ?? '').toString().replaceAll(
          RegExp(r'\D'),
          '',
        );
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

  OutlineInputBorder _inputOutline() {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: Colors.grey.shade300),
    );
  }

  Widget _cabecalhoPainelTickets() {
    final rx = widget.diPertinRoxo;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: rx.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: rx.withValues(alpha: 0.15)),
            ),
            child: Icon(Icons.support_agent_rounded, color: rx, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Central de atendimento',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: PainelAdminTheme.dashboardInk,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'Fila, chamados ativos e histórico em um só lugar.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: PainelAdminTheme.textoSecundario,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _corpoListaFila() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: widget.queryFila.snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return _loaderSecao();
        }
        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) {
          return SingleChildScrollView(
            padding: const EdgeInsets.only(top: 8),
            child: _emptyEstado(
              'Nenhum cliente aguardando no momento.',
              icon: Icons.hourglass_empty_rounded,
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 16),
          itemCount: docs.length,
          itemBuilder: (context, i) {
            final doc = docs[i];
            final m = doc.data();
            final pos = widget.posicaoNaFila(docs, doc.id);
            final sel = widget.selecionadoId == doc.id;
            return _tile(
              nome: m['user_nome']?.toString() ?? 'Cliente',
              protocolo: (m['protocol_number'] ?? '').toString().padLeft(
                8,
                '0',
              ),
              subtitulo:
                  '${widget.fmtHora(m['created_at'])} · espera ${widget.tempoEspera(m['created_at'])} · #$pos na fila${_legendaCategoriaNaLista(m)}',
              preview: (m['first_message_preview'] ?? '').toString(),
              selecionado: sel,
              onTap: () => widget.onSelect(doc),
            );
          },
        );
      },
    );
  }

  Widget _corpoListaAndamento() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: widget.queryAndamento.snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return _loaderSecao();
        }
        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) {
          return SingleChildScrollView(
            padding: const EdgeInsets.only(top: 8),
            child: _emptyEstado(
              'Nenhum atendimento em curso.',
              icon: Icons.assignment_ind_outlined,
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 16),
          itemCount: docs.length,
          itemBuilder: (context, i) {
            final doc = docs[i];
            final m = doc.data();
            final sel = widget.selecionadoId == doc.id;
            final agente = m['agent_nome']?.toString() ?? '—';
            return _tile(
              nome: m['user_nome']?.toString() ?? 'Cliente',
              protocolo: (m['protocol_number'] ?? '').toString().padLeft(
                8,
                '0',
              ),
              subtitulo: 'Atendente: $agente${_legendaCategoriaNaLista(m)}',
              preview: (m['first_message_preview'] ?? '').toString(),
              selecionado: sel,
              onTap: () => widget.onSelect(doc),
            );
          },
        );
      },
    );
  }

  Widget _corpoListaHistorico() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
          child: _cardFiltros(),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: widget.queryHistorico.snapshots(),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return _loaderSecao();
              }
              final raw = snap.data?.docs ?? [];
              final docs = _aplicarFiltrosHistorico(raw);
              if (raw.isEmpty) {
                return SingleChildScrollView(
                  padding: const EdgeInsets.only(top: 8),
                  child: _emptyEstado(
                    'Nenhum registro no histórico ainda.',
                    icon: Icons.folder_open_outlined,
                  ),
                );
              }
              if (docs.isEmpty) {
                return SingleChildScrollView(
                  padding: const EdgeInsets.only(top: 8),
                  child: _emptyEstado(
                    'Nenhum resultado com os filtros atuais.',
                    icon: Icons.search_off_rounded,
                  ),
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
                itemCount: docs.length,
                itemBuilder: (context, i) {
                  final doc = docs[i];
                  final m = doc.data();
                  final sel = widget.selecionadoId == doc.id;
                  final st = m['status']?.toString() ?? '';
                  return _tile(
                    nome: m['user_nome']?.toString() ?? 'Cliente',
                    protocolo: (m['protocol_number'] ?? '').toString().padLeft(
                      8,
                      '0',
                    ),
                    subtitulo:
                        '${widget.fmtHora(m['created_at'])} · ${statusLegivelSuporte(st)}${_legendaCategoriaNaLista(m)}',
                    preview: (m['first_message_preview'] ?? '').toString(),
                    selecionado: sel,
                    onTap: () => widget.onSelect(doc),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _emptyEstado(String mensagem, {IconData icon = Icons.inbox_outlined}) {
    return Container(
      constraints: const BoxConstraints(minHeight: 76),
      margin: const EdgeInsets.symmetric(horizontal: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: PainelAdminTheme.fundoCanvas.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: PainelAdminTheme.dashboardBorder),
      ),
      child: Row(
        children: [
          Icon(icon, size: 26, color: PainelAdminTheme.textoSecundario),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              mensagem,
              style: TextStyle(
                color: PainelAdminTheme.textoSecundario,
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
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
                prefixIcon: Icon(
                  Icons.person_search_rounded,
                  size: 20,
                  color: Colors.grey.shade600,
                ),
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
                prefixIcon: Icon(
                  Icons.tag_rounded,
                  size: 20,
                  color: Colors.grey.shade600,
                ),
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
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade800,
                      ),
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
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade800,
                      ),
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
    final rx = widget.diPertinRoxo;
    return Container(
      decoration: PainelAdminTheme.dashboardCard(),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _cabecalhoPainelTickets(),
          Material(
            color: Colors.white,
            child: TabBar(
              controller: _tabController,
              indicatorColor: rx,
              indicatorWeight: 3,
              labelColor: rx,
              unselectedLabelColor: PainelAdminTheme.textoSecundario,
              labelStyle: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
              tabs: const [
                Tab(text: 'Fila'),
                Tab(text: 'Em curso'),
                Tab(text: 'Histórico'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _corpoListaFila(),
                _corpoListaAndamento(),
                _corpoListaHistorico(),
              ],
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
