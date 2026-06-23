// Central de Ajuda — support_tickets + mensagens em tempo real

import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:depertin_cliente/constants/suporte_categorias.dart';
import 'package:depertin_cliente/screens/cliente/suporte_historico_conversa_screen.dart';
import 'package:depertin_cliente/services/support_ticket_service.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

const Color diPertinRoxo = Color(0xFF6A1B9A);
const Color diPertinLaranja = Color(0xFFFF8F00);

class ChatSuporteScreen extends StatefulWidget {
  const ChatSuporteScreen({super.key});

  @override
  State<ChatSuporteScreen> createState() => _ChatSuporteScreenState();
}

class _ChatSuporteScreenState extends State<ChatSuporteScreen> {
  final TextEditingController _mensagemController = TextEditingController();
  final SupportTicketService _svc = SupportTicketService.instance;

  bool _criandoTicket = false;
  bool _enviando = false;
  bool _enviandoAnexo = false;
  bool _salvandoCategoria = false;
  String? _ticketIdRastreado;

  /// Avaliação acabou de ser enviada (reforço visual antes do stream autorizado).
  final Set<String> _ticketIdComAvaliacaoEnviada = {};

  final ScrollController _scrollMensagens = ScrollController();
  int _ultimaContagemMensagens = 0;

  // ---------------------------------------------------------------------------
  // CACHE DE STREAMS — os StreamBuilder só devem subscrever UMA VEZ por ticket.
  // Sem este cache, cada setState do formulário (ex.: _enviando=true) rebuildava
  // o build(), criava um novo Stream, e o StreamBuilder voltava ao estado
  // `waiting` — causando o efeito de "piscar spinner" e o teclado sumir.
  // ---------------------------------------------------------------------------
  late final Stream<QueryDocumentSnapshot<Map<String, dynamic>>?>
      _streamUltimoTicket;
  final Map<String, Stream<QuerySnapshot<Map<String, dynamic>>>>
      _streamsMensagens = {};
  final Map<String, Stream<QuerySnapshot<Map<String, dynamic>>>>
      _streamsAvaliacaoTicket = {};

  /// Buffer das mensagens já carregadas — evita que o ListView seja
  /// substituído pelo spinner em atualizações subsequentes (quando o Firestore
  /// emite `ConnectionState.waiting` num re-subscribe pontual).
  final Map<String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>
      _bufferMensagens = {};

  // Estado da avaliação inline (quando o atendimento é encerrado pelo suporte).
  final TextEditingController _comentarioAvaliacao = TextEditingController();
  int _estrelasAvaliacao = 5;
  bool _enviandoAvaliacao = false;
  String? _ticketAvaliacaoVinculado;

  Stream<QuerySnapshot<Map<String, dynamic>>> _streamMensagensDe(
    String ticketId,
  ) {
    return _streamsMensagens.putIfAbsent(
      ticketId,
      () => FirebaseFirestore.instance
          .collection('support_tickets')
          .doc(ticketId)
          .collection('mensagens')
          .orderBy('created_at', descending: false)
          .snapshots(),
    );
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _streamAvaliacaoDe({
    required String ticketId,
    required String uid,
  }) {
    final chave = '$ticketId|$uid';
    return _streamsAvaliacaoTicket.putIfAbsent(
      chave,
      () => FirebaseFirestore.instance
          .collection('support_ratings')
          .where('ticket_id', isEqualTo: ticketId)
          .where('user_id', isEqualTo: uid)
          .limit(1)
          .snapshots(),
    );
  }

  @override
  void initState() {
    super.initState();
    _streamUltimoTicket = _svc.streamUltimoTicket();
  }

  @override
  void dispose() {
    _mensagemController.dispose();
    _scrollMensagens.dispose();
    _comentarioAvaliacao.dispose();
    super.dispose();
  }

  void _sincronizarAvaliacaoInline(String ticketId) {
    if (_ticketAvaliacaoVinculado != ticketId) {
      _ticketAvaliacaoVinculado = ticketId;
      _estrelasAvaliacao = 5;
      _comentarioAvaliacao.clear();
      _enviandoAvaliacao = false;
    }
  }

  void _agendarAutoScroll(int qtd) {
    if (qtd == _ultimaContagemMensagens) return;
    _ultimaContagemMensagens = qtd;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollMensagens.hasClients) return;
      final max = _scrollMensagens.position.maxScrollExtent;
      _scrollMensagens.animateTo(
        max,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  void _abrirConversaHistorico(BuildContext context, String ticketId) {
    Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (ctx) => SuporteHistoricoConversaScreen(ticketId: ticketId),
      ),
    );
  }

  /// Abre uma bottom sheet listando os chamados anteriores do usuário.
  /// Permite acessar o histórico mesmo quando existe um chamado em curso.
  Future<void> _abrirHistoricoChamados() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.65,
          minChildSize: 0.45,
          maxChildSize: 0.92,
          expand: false,
          builder: (context, scrollController) {
            return Column(
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: diPertinRoxo.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.history_rounded,
                            color: diPertinRoxo, size: 20),
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        'Histórico de atendimentos',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 17,
                          color: Color(0xFF1A1A2E),
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, thickness: 0.5),
                Expanded(
                  child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: _svc.streamHistoricoUsuario(),
                    builder: (context, snap) {
                      if (!snap.hasData) {
                        return const Center(
                          child: CircularProgressIndicator(
                            color: diPertinRoxo,
                          ),
                        );
                      }
                      final docs = snap.data!.docs;
                      if (docs.isEmpty) {
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              'Você ainda não tem chamados anteriores.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.grey[600]),
                            ),
                          ),
                        );
                      }
                      return ListView.separated(
                        controller: scrollController,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        itemCount: docs.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 2),
                        itemBuilder: (context, i) {
                          final d = docs[i];
                          final x = d.data();
                          final p = (x['protocol_number'] ?? '')
                              .toString()
                              .padLeft(8, '0');
                          final s = x['status']?.toString() ?? '';
                          return Container(
                            margin: const EdgeInsets.symmetric(vertical: 2),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 4,
                              ),
                              leading: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: _corStatus(s).withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(
                                  _iconeStatus(s),
                                  color: _corStatus(s),
                                  size: 20,
                                ),
                              ),
                              title: Text(
                                'Protocolo $p',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                  color: Color(0xFF1A1A2E),
                                ),
                              ),
                              subtitle: Text(
                                _labelStatus(s),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                ),
                              ),
                              trailing: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: Colors.grey[100],
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(
                                  Icons.chevron_right_rounded,
                                  size: 18,
                                  color: Colors.black38,
                                ),
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              onTap: () {
                                Navigator.pop(ctx);
                                _abrirConversaHistorico(context, d.id);
                              },
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  IconData _iconeStatus(String s) {
    switch (s) {
      case SuporteTicketStatus.waiting:
        return Icons.hourglass_top;
      case SuporteTicketStatus.inProgress:
        return Icons.support_agent;
      case SuporteTicketStatus.finished:
      case SuporteTicketStatus.closed:
        return Icons.check_circle_outline;
      case SuporteTicketStatus.cancelled:
        return Icons.cancel_outlined;
      default:
        return Icons.chat_bubble_outline;
    }
  }

  Color _corStatus(String s) {
    switch (s) {
      case SuporteTicketStatus.waiting:
        return Colors.amber[700]!;
      case SuporteTicketStatus.inProgress:
        return diPertinRoxo;
      case SuporteTicketStatus.finished:
      case SuporteTicketStatus.closed:
        return Colors.green[700]!;
      case SuporteTicketStatus.cancelled:
        return Colors.red[600]!;
      default:
        return Colors.grey[600]!;
    }
  }

  void _sincronizarRastreioTicket(String ticketId) {
    if (_ticketIdRastreado != ticketId) {
      _ticketIdRastreado = ticketId;
    }
  }

  Future<void> _iniciarAtendimento() async {
    if (_criandoTicket) return;
    setState(() => _criandoTicket = true);
    try {
      await _svc.criarTicket();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Não foi possível abrir o chamado: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _criandoTicket = false);
    }
  }

  Future<void> _enviarMensagem(String ticketId) async {
    final texto = _mensagemController.text.trim();
    if (texto.isEmpty || _enviando) return;
    setState(() => _enviando = true);
    _mensagemController.clear();
    try {
      await _svc.enviarMensagemCliente(ticketId: ticketId, texto: texto);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao enviar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  Future<void> _abrirSheetAnexo(String ticketId) async {
    if (_enviandoAnexo || _enviando) return;
    final escolha = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      backgroundColor: Colors.white,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 14,
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: diPertinRoxo.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.attach_file_rounded,
                        color: diPertinRoxo,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      'Enviar anexo',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1A1A2E),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, thickness: 0.5),
              const SizedBox(height: 4),
              _anexoOpcao(
                ctx: ctx,
                icone: Icons.photo_camera_outlined,
                titulo: 'Tirar foto',
                subtitulo: 'Use a câmera do celular',
                valor: 'camera',
              ),
              _anexoOpcao(
                ctx: ctx,
                icone: Icons.photo_library_outlined,
                titulo: 'Galeria de fotos',
                subtitulo: 'Escolha uma imagem salva',
                valor: 'galeria',
              ),
              _anexoOpcao(
                ctx: ctx,
                icone: Icons.insert_drive_file_outlined,
                titulo: 'Arquivo',
                subtitulo: 'PDF, DOC, planilhas e mais',
                valor: 'arquivo',
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || escolha == null) return;

    if (escolha == 'camera' || escolha == 'galeria') {
      await _enviarImagem(
        ticketId: ticketId,
        source: escolha == 'camera' ? ImageSource.camera : ImageSource.gallery,
      );
    } else if (escolha == 'arquivo') {
      await _enviarArquivo(ticketId);
    }
  }

  Future<void> _enviarImagem({
    required String ticketId,
    required ImageSource source,
  }) async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: source,
        imageQuality: 80,
        maxWidth: 1920,
      );
      if (picked == null || !mounted) return;

      final file = File(picked.path);
      final tamanho = await file.length();
      if (tamanho > 20 * 1024 * 1024) {
        _mostrarErro('Imagem maior que 20 MB não é permitida.');
        return;
      }
      final nome = picked.name.isNotEmpty
          ? picked.name
          : 'imagem_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final mime = _inferirMime(nome, 'image/jpeg');

      setState(() => _enviandoAnexo = true);
      await _svc.enviarAnexoCliente(
        ticketId: ticketId,
        nomeArquivo: nome,
        mimeType: mime,
        tamanhoBytes: tamanho,
        arquivo: file,
      );
    } catch (e) {
      _mostrarErro('Erro ao enviar imagem: $e');
    } finally {
      if (mounted) setState(() => _enviandoAnexo = false);
    }
  }

  Future<void> _enviarArquivo(String ticketId) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        withData: false,
        allowMultiple: false,
      );
      if (result == null || result.files.isEmpty || !mounted) return;
      final picked = result.files.single;
      final caminho = picked.path;
      if (caminho == null) {
        _mostrarErro('Não foi possível ler o arquivo.');
        return;
      }
      final file = File(caminho);
      final tamanho = picked.size;
      if (tamanho > 20 * 1024 * 1024) {
        _mostrarErro('Arquivo maior que 20 MB não é permitido.');
        return;
      }
      final mime = _inferirMime(picked.name, 'application/octet-stream');

      setState(() => _enviandoAnexo = true);
      await _svc.enviarAnexoCliente(
        ticketId: ticketId,
        nomeArquivo: picked.name,
        mimeType: mime,
        tamanhoBytes: tamanho,
        arquivo: file,
      );
    } catch (e) {
      _mostrarErro('Erro ao enviar arquivo: $e');
    } finally {
      if (mounted) setState(() => _enviandoAnexo = false);
    }
  }

  void _mostrarErro(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red),
    );
  }

  /// Renderiza o conteúdo da bolha: anexo (imagem ou cartão de arquivo) +
  /// legenda/texto. Mantém retrocompatibilidade: sem anexo, só mostra o texto.
  Widget _construirConteudoMensagem(
    Map<String, dynamic> msg,
    String texto,
    bool ehCliente,
  ) {
    final corTexto = ehCliente ? Colors.white : const Color(0xFF1A1A2E);
    final url = (msg['anexo_url'] ?? '').toString();
    if (url.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        child: Text(
          texto,
          style: TextStyle(color: corTexto, fontSize: 15),
        ),
      );
    }
    final tipo = (msg['anexo_tipo'] ?? '').toString();
    final nome = (msg['anexo_nome'] ?? 'arquivo').toString();
    final tamanho = (msg['anexo_tamanho'] is num)
        ? (msg['anexo_tamanho'] as num).toInt()
        : 0;

    final anexoCorFundo = ehCliente
        ? Colors.white.withValues(alpha: 0.18)
        : diPertinRoxo.withValues(alpha: 0.06);
    final anexoIconCor = ehCliente ? Colors.white : diPertinRoxo;
    final anexoTextSecundario = ehCliente ? Colors.white70 : Colors.grey.shade600;

    Widget anexoWidget;
    if (tipo == 'image') {
      anexoWidget = GestureDetector(
        onTap: () => _abrirVisualizadorImagem(url, nome),
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
              loadingBuilder: (ctx, child, progress) {
                if (progress == null) return child;
                return Container(
                  height: 160,
                  width: 160,
                  color: Colors.black.withValues(alpha: 0.15),
                  alignment: Alignment.center,
                  child: const CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                );
              },
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
      anexoWidget = InkWell(
        onTap: () => _abrirLinkExterno(url),
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
                          ? '${_formatarTamanho(tamanho)} • toque para abrir'
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
        anexoWidget,
        if (texto.trim().isNotEmpty) ...[
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              texto,
              style: TextStyle(color: corTexto, fontSize: 15),
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _abrirLinkExterno(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      _mostrarErro('Não foi possível abrir o anexo.');
    }
  }

  void _abrirVisualizadorImagem(String url, String nome) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _VisualizadorImagem(url: url, titulo: nome),
        fullscreenDialog: true,
      ),
    );
  }

  String _formatarTamanho(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String _inferirMime(String nome, String fallback) {
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
    return fallback;
  }

  Future<void> _encerrarPeloCliente(String ticketId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Encerrar atendimento?'),
        content: const Text(
          'Você pode abrir um novo chamado depois, se precisar.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Encerrar', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await _svc.encerrarPeloCliente(ticketId);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _detectarInicioAgente(String ticketId, Map<String, dynamic> d) {
    // O aviso "{agente} iniciou seu atendimento" já chega ao cliente pelo
    // push FCM (inclusive com o nome do atendente), então não precisamos
    // duplicar com um snackbar em foreground.
    _sincronizarRastreioTicket(ticketId);
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F7),
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.support_agent, color: Colors.white, size: 24),
            SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Central de Ajuda',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                  Text(
                    'Atendimento ao cliente',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
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
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
        actions: [
          if (user != null)
            IconButton(
              tooltip: 'Histórico de atendimentos',
              icon: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.history, color: Colors.white, size: 20),
              ),
              onPressed: _abrirHistoricoChamados,
            ),
        ],
      ),
      body: user == null
          ? const Center(child: Text('Faça login para usar o suporte.'))
          : StreamBuilder<QueryDocumentSnapshot<Map<String, dynamic>>?>(
              // Stream cacheado em initState → não é recriado a cada setState,
              // então o teclado não se fecha e a UI não pisca entre envios.
              stream: _streamUltimoTicket,
              builder: (context, snapTicket) {
                // Só mostra spinner de tela inteira na PRIMEIRA subscrição.
                // Depois, mantém a UI anterior enquanto o snapshot chega.
                if (!snapTicket.hasData &&
                    snapTicket.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(color: diPertinRoxo),
                  );
                }

                final doc = snapTicket.data;
                if (doc == null) {
                  return _painelInicial();
                }

                final d = doc.data();
                final st = d['status']?.toString() ?? '';

                if (st == SuporteTicketStatus.waiting ||
                    st == SuporteTicketStatus.inProgress) {
                  return _corpoChat(doc: doc, dados: d);
                }

                return _corpoFinalizadoComChat(doc: doc, dados: d);
              },
            ),
    );
  }

  Widget _corpoChat({
    required QueryDocumentSnapshot<Map<String, dynamic>> doc,
    required Map<String, dynamic> dados,
  }) {
    final ticketId = doc.id;
    _detectarInicioAgente(ticketId, dados);

    final protocolo =
        (dados['protocol_number'] ?? '').toString().padLeft(8, '0');
    final cidade = dados['cidade']?.toString() ?? '—';
    final st = dados['status']?.toString() ?? '';

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _streamMensagensDe(ticketId),
      builder: (context, snapMsg) {
        // Mantém o buffer anterior enquanto o snapshot novo não chega —
        // evita o flash do spinner que tirava o foco do teclado.
        if (snapMsg.hasData) {
          _bufferMensagens[ticketId] = snapMsg.data!.docs;
        }
        final msgs = _bufferMensagens[ticketId] ??
            <QueryDocumentSnapshot<Map<String, dynamic>>>[];
        final primeiraCarga =
            !snapMsg.hasData && _bufferMensagens[ticketId] == null;
        final aguardandoCategoria =
            _aguardandoEscolhaCategoria(st, dados, msgs);

        if (!primeiraCarga) _agendarAutoScroll(msgs.length);

        return Column(
          children: [
            _cabecalhoProtocolo(
              protocolo: protocolo,
              status: st,
              encerrado: false,
              agentNome: dados['agent_nome']?.toString(),
              onEncerrar: () => _encerrarPeloCliente(ticketId),
            ),
            if (st == SuporteTicketStatus.waiting)
              _faixaFila(ticketId: ticketId, cidade: cidade),
            Expanded(
              child: primeiraCarga
                  ? const Center(
                      child: CircularProgressIndicator(color: diPertinRoxo),
                    )
                  : (msgs.isEmpty && !aguardandoCategoria)
                      ? const Center(
                          child: Text(
                            'Descreva sua dúvida ou problema abaixo.',
                            style: TextStyle(
                              color: Colors.grey,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        )
                      // O painel de categorias é inserido como último item do
                      // ListView para que ele ROLE junto com as mensagens.
                      // Antes ele ficava fora do Expanded como item fixo do
                      // Column e, ao abrir o teclado, estourava a altura
                      // disponível (overflow amarelo/preto).
                      : ListView.builder(
                          controller: _scrollMensagens,
                          padding: const EdgeInsets.all(15),
                          itemCount:
                              msgs.length + (aguardandoCategoria ? 1 : 0),
                          itemBuilder: (context, index) {
                            if (aguardandoCategoria && index == msgs.length) {
                              return Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: _painelEscolhaCategoria(
                                  ticketId: ticketId,
                                ),
                              );
                            }
                            final msg = msgs[index].data();
                            return _construirLinhaMensagem(msg);
                          },
                        ),
            ),
            _rodapeDigitacao(
              ticketId: ticketId,
              status: st,
            ),
          ],
        );
      },
    );
  }

  /// Renderiza uma linha da timeline: 'system' (pill cinza centralizada),
  /// saudação automática do suporte (laranja à esquerda, sem efeito triangular)
  /// ou balões do cliente/atendente.
  Widget _construirLinhaMensagem(Map<String, dynamic> msg) {
    final tipo = msg['sender_type']?.toString() ?? '';
    final texto = msg['mensagem']?.toString() ?? '';
    final suporteAuto = msg['suporte_auto'] == true;

    final createdAt = msg['created_at'];
    String horario = '';
    if (createdAt is Timestamp) {
      final dt = createdAt.toDate();
      horario = '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }

    if (tipo == 'system') {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 24),
        child: Row(
          children: [
            Expanded(
              child: Container(
                height: 1,
                color: Colors.grey.shade200,
              ),
            ),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.grey.shade200),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 14,
                    color: Colors.grey.shade500,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    texto,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
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

    final ehCliente = tipo == 'client' && !suporteAuto;

    return Padding(
      padding: EdgeInsets.only(
        left: ehCliente ? 48 : 14,
        right: ehCliente ? 14 : 48,
        bottom: 6,
      ),
      child: Column(
        crossAxisAlignment:
            ehCliente ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (suporteAuto)
            Padding(
              padding: const EdgeInsets.only(bottom: 4, left: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      color: diPertinLaranja.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Icon(
                      Icons.support_agent_rounded,
                      size: 11,
                      color: diPertinLaranja,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    'DiPertin',
                    style: TextStyle(
                      color: diPertinLaranja,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
            ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.78,
            ),
            decoration: BoxDecoration(
              color: ehCliente ? diPertinRoxo : Colors.white,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(18),
                topRight: const Radius.circular(18),
                bottomLeft: Radius.circular(ehCliente ? 18 : 4),
                bottomRight: Radius.circular(ehCliente ? 4 : 18),
              ),
              boxShadow: [
                BoxShadow(
                  color: (ehCliente ? diPertinRoxo : Colors.black)
                      .withValues(alpha: ehCliente ? 0.15 : 0.06),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _construirConteudoMensagem(
                  msg,
                  texto,
                  ehCliente,
                ),
                const SizedBox(height: 2),
                Align(
                  alignment: Alignment.bottomRight,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (horario.isNotEmpty)
                        Text(
                          horario,
                          style: TextStyle(
                            fontSize: 10,
                            color: ehCliente
                                ? Colors.white.withValues(alpha: 0.65)
                                : Colors.grey.shade500,
                          ),
                        ),
                      if (ehCliente) ...[
                        const SizedBox(width: 3),
                        Icon(
                          Icons.done_all_rounded,
                          size: 13,
                          color: Colors.white.withValues(alpha: 0.55),
                        ),
                      ],
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

  /// Escolha de categoria aparece **apenas no primeiro atendimento**:
  /// ticket ainda em fila (waiting), sem categoria escolhida, sem `started_at`
  /// (nunca foi iniciado/reaberto) e com pelo menos uma mensagem do cliente.
  bool _aguardandoEscolhaCategoria(
    String statusTicket,
    Map<String, dynamic> dadosTicket,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> mensagens,
  ) {
    if (statusTicket != SuporteTicketStatus.waiting) return false;
    final cat = (dadosTicket['categoria_suporte'] ?? '').toString().trim();
    if (cat.isNotEmpty) return false;
    // Tickets reabertos já passaram por um agente — não exibir categoria.
    if (dadosTicket['started_at'] != null) return false;
    final rawReabertura = dadosTicket['reabertura_count'];
    final reaberturaCount = rawReabertura is num ? rawReabertura.toInt() : 0;
    if (reaberturaCount > 0) return false;
    for (final d in mensagens) {
      if ((d.data()['sender_type'] ?? '').toString() == 'client') {
        return true;
      }
    }
    return false;
  }

  Widget _painelEscolhaCategoria({required String ticketId}) {
    final opcoes = SuporteCategorias.opcoes;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: diPertinRoxo.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.tune_rounded,
                      size: 16,
                      color: diPertinRoxo,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Qual o assunto?',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14.5,
                            color: Color(0xFF1A1A2E),
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Selecione para direcionar seu chamado.',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: Colors.black54,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            const Divider(height: 1, thickness: 0.5),
            for (var i = 0; i < opcoes.length; i++) ...[
              _itemCategoriaCompacto(
                opcao: opcoes[i],
                habilitado: true,
                onTap: () =>
                    _onEscolherCategoria(ticketId, opcoes[i].codigo),
              ),
              if (i < opcoes.length - 1)
                const Divider(height: 1, thickness: 0.5, indent: 56),
            ],
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }

  Widget _itemCategoriaCompacto({
    required SuporteCategoriaOpcao opcao,
    required bool habilitado,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: habilitado ? onTap : null,
        borderRadius: BorderRadius.circular(0),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: diPertinRoxo.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(opcao.icone, size: 18, color: diPertinRoxo),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      opcao.rotulo,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1A1A2E),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      opcao.descricao,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: Colors.black38,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _onEscolherCategoria(String ticketId, String codigo) async {
    // Guarda reativa já evita duplo toque. Não fazemos setState para não
    // rebuildar a tela inteira (evita fechar o teclado / piscar spinner).
    // O painel desaparece sozinho quando o snapshot traz `categoria_suporte`.
    if (_salvandoCategoria) return;
    _salvandoCategoria = true;
    try {
      await _svc.registrarCategoriaSuporteCliente(
        ticketId: ticketId,
        codigo: codigo,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Não foi possível registrar a categoria: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      _salvandoCategoria = false;
    }
  }

  /// Renderiza o chat já encerrado mantendo as mensagens visíveis na mesma
  /// tela. O rodapé de digitação é substituído por:
  /// - um cartão de avaliação inline (somente quando o atendimento foi
  ///   efetivamente iniciado por um atendente e encerrado de forma normal
  ///   — `closed` ou `finished` com `started_at` preenchido);
  /// - o botão "Iniciar novo atendimento".
  ///
  /// Se o cliente cancelou antes de qualquer atendente ter iniciado a
  /// conversa, o convite de avaliação não aparece.
  Widget _corpoFinalizadoComChat({
    required QueryDocumentSnapshot<Map<String, dynamic>> doc,
    required Map<String, dynamic> dados,
  }) {
    final ticketId = doc.id;
    _sincronizarAvaliacaoInline(ticketId);

    final protocolo =
        (dados['protocol_number'] ?? '').toString().padLeft(8, '0');
    final st = dados['status']?.toString() ?? '';
    final atendidoPorAgente = dados['started_at'] != null ||
        (dados['agent_id']?.toString().isNotEmpty ?? false);

    // Convidamos a avaliar sempre que o suporte efetivamente atendeu — mesmo
    // quando o encerramento partiu do próprio cliente (status=cancelled).
    // Só suprimimos o cartão quando nunca houve atendente (ex.: cliente
    // cancelou ainda na fila, sem interação).
    final podeAvaliar = atendidoPorAgente &&
        (st == SuporteTicketStatus.closed ||
            st == SuporteTicketStatus.finished ||
            st == SuporteTicketStatus.cancelled);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _streamMensagensDe(ticketId),
      builder: (context, snapMsg) {
        if (snapMsg.hasData) {
          _bufferMensagens[ticketId] = snapMsg.data!.docs;
        }
        final msgs = _bufferMensagens[ticketId] ??
            <QueryDocumentSnapshot<Map<String, dynamic>>>[];
        final primeiraCarga =
            !snapMsg.hasData && _bufferMensagens[ticketId] == null;

        if (!primeiraCarga) _agendarAutoScroll(msgs.length);

        // Itens "extra" que são exibidos depois das mensagens. Eles ficam
        // DENTRO do ListView (viram itens rolantes), não no rodapé fixo —
        // assim, quando o teclado abrir para escrever o comentário da
        // avaliação, tudo rola naturalmente sem estourar a altura da tela.
        // O único elemento fixo no rodapé é o botão "Iniciar novo
        // atendimento".
        final extras = <Widget>[];
        if (podeAvaliar) {
          extras.add(_cartaoAvaliacaoOuAgradecimento(
            ticketId: ticketId,
            protocolo: protocolo,
          ));
        }
        extras.add(_secaoHistoricoRodape());

        return Column(
          children: [
            _cabecalhoProtocolo(
              protocolo: protocolo,
              status: st,
              encerrado: true,
              agentNome: dados['agent_nome']?.toString(),
            ),
            _faixaAtendimentoEncerrado(st),
            Expanded(
              child: primeiraCarga
                  ? const Center(
                      child: CircularProgressIndicator(color: diPertinRoxo),
                    )
                  : ListView.builder(
                      controller: _scrollMensagens,
                      padding: const EdgeInsets.all(15),
                      itemCount: msgs.length + extras.length,
                      itemBuilder: (context, index) {
                        if (index < msgs.length) {
                          final msg = msgs[index].data();
                          return _construirLinhaMensagem(msg);
                        }
                        final extraIndex = index - msgs.length;
                        return Padding(
                          padding: EdgeInsets.only(
                            top: extraIndex == 0 ? 8 : 10,
                          ),
                          child: extras[extraIndex],
                        );
                      },
                    ),
            ),
            _rodapeNovoAtendimento(),
          ],
        );
      },
    );
  }

  /// Banner fino que substitui o rodapé de digitação indicando que o chamado
  /// está encerrado e explicando o motivo.
  Widget _faixaAtendimentoEncerrado(String status) {
    IconData icone;
    String texto;
    Color cor;

    switch (status) {
      case SuporteTicketStatus.cancelled:
        icone = Icons.cancel_outlined;
        texto = 'Você encerrou este atendimento.';
        cor = Colors.orange;
      case SuporteTicketStatus.closed:
        icone = Icons.check_circle_outline;
        texto = 'Este atendimento foi encerrado pelo suporte.';
        cor = const Color(0xFF16A34A);
      case SuporteTicketStatus.finished:
        icone = Icons.check_circle_outline;
        texto = 'Atendimento finalizado.';
        cor = const Color(0xFF16A34A);
      default:
        icone = Icons.info_outline;
        texto = 'Atendimento encerrado.';
        cor = Colors.grey;
    }

    return Container(
      width: double.infinity,
      color: cor.withValues(alpha: 0.05),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: cor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(icone, size: 16, color: cor),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              texto,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                color: cor.withValues(alpha: 0.9),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Cartão de avaliação do atendimento (ou mensagem de agradecimento, caso
  /// já tenha sido avaliado). Usado como ITEM do ListView de mensagens na
  /// tela de atendimento encerrado — assim rola com o conteúdo e não gera
  /// overflow quando o teclado abre para escrever o comentário.
  Widget _cartaoAvaliacaoOuAgradecimento({
    required String ticketId,
    required String protocolo,
  }) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const SizedBox.shrink();
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _streamAvaliacaoDe(ticketId: ticketId, uid: uid),
      builder: (context, snap) {
        final jaAvaliou = _ticketIdComAvaliacaoEnviada.contains(ticketId) ||
            (snap.hasData && snap.data!.docs.isNotEmpty);
        return jaAvaliou
            ? _cartaoAgradecimentoAvaliacao()
            : _cartaoAvaliacaoInline(
                ticketId: ticketId,
                protocolo: protocolo,
              );
      },
    );
  }

  /// Rodapé fixo na tela de atendimento encerrado: apenas o botão de
  /// iniciar novo atendimento. Avaliação e histórico são exibidos como
  /// itens rolantes da lista de mensagens (ver `_corpoFinalizadoComChat`).
  Widget _rodapeNovoAtendimento() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(color: Colors.grey.shade200),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: SizedBox(
            height: 48,
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _criandoTicket ? null : _iniciarAtendimento,
              style: ElevatedButton.styleFrom(
                backgroundColor: diPertinLaranja,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: _criandoTicket
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.add_comment_rounded, size: 20),
              label: const Text(
                'Iniciar novo atendimento',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14.5,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _cartaoAgradecimentoAvaliacao() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4),
        border: Border.all(color: const Color(0xFF22C55E).withValues(alpha: 0.2)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: const Color(0xFF22C55E).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.check_circle_rounded,
                color: Color(0xFF16A34A), size: 20),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Obrigado pela avaliação! Sua opinião nos ajuda a melhorar.',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: Color(0xFF166534),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _cartaoAvaliacaoInline({
    required String ticketId,
    required String protocolo,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: diPertinRoxo.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: diPertinLaranja.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.star_rate_rounded,
                    color: diPertinLaranja, size: 20),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Como foi o atendimento?',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14.5,
                        color: Color(0xFF1A1A2E),
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Sua opinião é muito importante para nós.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(5, (i) {
              final n = i + 1;
              final ativa = n <= _estrelasAvaliacao;
              return GestureDetector(
                onTap: _enviandoAvaliacao
                    ? null
                    : () => setState(() => _estrelasAvaliacao = n),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: ativa
                        ? diPertinLaranja.withValues(alpha: 0.1)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    ativa ? Icons.star_rounded : Icons.star_border_rounded,
                    color: ativa ? diPertinLaranja : Colors.grey.shade300,
                    size: 34,
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _comentarioAvaliacao,
            enabled: !_enviandoAvaliacao,
            maxLines: 2,
            maxLength: 240,
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Deixe um comentário (opcional)',
              hintStyle: TextStyle(
                color: Colors.grey.shade400,
                fontSize: 13,
              ),
              counterText: '',
              filled: true,
              fillColor: Colors.grey.shade50,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey.shade200),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey.shade200),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: diPertinRoxo, width: 1.5),
              ),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: ElevatedButton.icon(
              onPressed: _enviandoAvaliacao
                  ? null
                  : () => _enviarAvaliacaoInline(
                        ticketId: ticketId,
                      ),
              style: ElevatedButton.styleFrom(
                backgroundColor: diPertinRoxo,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: _enviandoAvaliacao
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.send_rounded, size: 18),
              label: const Text(
                'Enviar avaliação',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _enviarAvaliacaoInline({required String ticketId}) async {
    if (_enviandoAvaliacao) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    setState(() => _enviandoAvaliacao = true);
    try {
      await FirebaseFirestore.instance.collection('support_ratings').add({
        'ticket_id': ticketId,
        'user_id': uid,
        'rating': _estrelasAvaliacao,
        'comment': _comentarioAvaliacao.text.trim(),
        'created_at': FieldValue.serverTimestamp(),
      });
      if (!mounted) return;
      setState(() {
        _ticketIdComAvaliacaoEnviada.add(ticketId);
        _comentarioAvaliacao.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Obrigado pela avaliação!'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Não foi possível enviar a avaliação: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _enviandoAvaliacao = false);
    }
  }

  /// Card compacto mostrando os últimos atendimentos (até 3) e um link para
  /// abrir o histórico completo. Usado no rodapé da tela de atendimento
  /// encerrado, para que o cliente não fique sem acesso ao histórico.
  Widget _secaoHistoricoRodape() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _svc.streamHistoricoUsuario(),
      builder: (context, snap) {
        if (!snap.hasData) return const SizedBox.shrink();
        final docs = snap.data!.docs;
        if (docs.length <= 1) return const SizedBox.shrink();
        final anteriores = docs.skip(1).take(3).toList();
        if (anteriores.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 8, 6),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: diPertinRoxo.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.history_rounded,
                            size: 16, color: diPertinRoxo),
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Atendimentos anteriores',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13.5,
                            color: Color(0xFF1A1A2E),
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: _abrirHistoricoChamados,
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          minimumSize: const Size(0, 32),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text(
                          'Ver todos',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: diPertinLaranja,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, thickness: 0.5),
                for (var i = 0; i < anteriores.length; i++) ...[
                  _linhaHistoricoCompacta(anteriores[i]),
                  if (i < anteriores.length - 1)
                    const Divider(height: 1, indent: 52),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _linhaHistoricoCompacta(
    QueryDocumentSnapshot<Map<String, dynamic>> d,
  ) {
    final x = d.data();
    final p = (x['protocol_number'] ?? '').toString().padLeft(8, '0');
    final s = x['status']?.toString() ?? '';
    return InkWell(
      onTap: () => _abrirConversaHistorico(context, d.id),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _corStatus(s).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                _iconeStatus(s),
                color: _corStatus(s),
                size: 18,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Protocolo $p',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1A1A2E),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _labelStatus(s),
                    style: TextStyle(
                      fontSize: 11.5,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.chevron_right_rounded,
                size: 16,
                color: Colors.black38,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _painelInicial() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // --- Hero card ---
          Container(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF7B1FA2),
                  Color(0xFF6A1B9A),
                  Color(0xFF4A148C),
                ],
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: diPertinRoxo.withValues(alpha: 0.3),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: Column(
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.headset_mic_rounded,
                      color: Colors.white,
                      size: 32,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Central de Ajuda',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Estamos prontos para ajudar!\nSua solicitação será atendida em breve.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 14,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed:
                          _criandoTicket ? null : _iniciarAtendimento,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: diPertinRoxo,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: _criandoTicket
                          ? const SizedBox(
                              height: 22,
                              width: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: diPertinRoxo,
                              ),
                            )
                          : const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.add_comment_rounded, size: 20),
                                SizedBox(width: 8),
                                Text(
                                  'Iniciar atendimento',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),

          // --- Como funciona ---
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.shade100),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.info_outline_rounded,
                        color: diPertinRoxo, size: 18),
                    SizedBox(width: 8),
                    Text(
                      'Como funciona',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: Color(0xFF1A1A2E),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _stepItem(
                  icon: Icons.description_outlined,
                  titulo: 'Abra um chamado',
                  descricao: 'Descreva seu problema ou dúvida.',
                ),
                const SizedBox(height: 8),
                _stepItem(
                  icon: Icons.people_alt_outlined,
                  titulo: 'Aguarde na fila',
                  descricao: 'Acompanhe sua posição em tempo real.',
                ),
                const SizedBox(height: 8),
                _stepItem(
                  icon: Icons.chat_outlined,
                  titulo: 'Converse com a equipe',
                  descricao: 'Atendimento ágil pelo chat.',
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // --- Histórico recente ---
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: diPertinRoxo.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.history_rounded,
                  size: 16,
                  color: diPertinRoxo,
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'Histórico recente',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: Color(0xFF1A1A2E),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _svc.streamHistoricoUsuario(),
            builder: (context, snap) {
              if (!snap.hasData || snap.data!.docs.isEmpty) {
                return Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade100),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.inbox_rounded,
                          size: 18, color: Colors.grey.shade400),
                      const SizedBox(width: 8),
                      Text(
                        'Nenhum chamado anterior',
                        style: TextStyle(
                          color: Colors.grey.shade500,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                );
              }
              return Column(
                children: snap.data!.docs.map((doc) {
                  final x = doc.data();
                  final p = (x['protocol_number'] ?? '').toString().padLeft(
                    8,
                    '0',
                  );
                  final s = x['status']?.toString() ?? '';
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade100),
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 2,
                      ),
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: _corStatus(s).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          _iconeStatus(s),
                          color: _corStatus(s),
                          size: 20,
                        ),
                      ),
                      title: Text(
                        'Protocolo $p',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13.5,
                          color: Color(0xFF1A1A2E),
                        ),
                      ),
                      subtitle: Text(
                        _labelStatus(s),
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      trailing: Container(
                        padding: const EdgeInsets.all(4),
 decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.chevron_right_rounded,
                          size: 18,
                          color: Colors.black38,
                        ),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      onTap: () =>
                          _abrirConversaHistorico(context, doc.id),
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _stepItem({
    required IconData icon,
    required String titulo,
    required String descricao,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: diPertinRoxo.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 18, color: diPertinRoxo),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                titulo,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13.5,
                  color: Color(0xFF1A1A2E),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                descricao,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _labelStatus(String s) {
    switch (s) {
      case SuporteTicketStatus.waiting:
        return 'Aguardando';
      case SuporteTicketStatus.inProgress:
        return 'Em atendimento';
      case SuporteTicketStatus.finished:
        return 'Finalizado';
      case SuporteTicketStatus.cancelled:
        return 'Encerrado por você';
      case SuporteTicketStatus.closed:
        return 'Encerrado pelo suporte';
      default:
        return s;
    }
  }

  Widget _cabecalhoProtocolo({
    required String protocolo,
    required String status,
    required bool encerrado,
    String? agentNome,
    VoidCallback? onEncerrar,
  }) {
    final isWaiting = status == SuporteTicketStatus.waiting;

    Color badgeCor;
    IconData badgeIcon;
    String badgeTexto;
    if (encerrado) {
      badgeCor = const Color(0xFF16A34A);
      badgeIcon = Icons.check_circle_rounded;
      badgeTexto = 'Finalizado';
    } else if (isWaiting) {
      badgeCor = diPertinLaranja;
      badgeIcon = Icons.access_time_rounded;
      badgeTexto = 'Aguardando';
    } else {
      badgeCor = const Color(0xFF2563EB);
      badgeIcon = Icons.support_agent_rounded;
      badgeTexto = agentNome != null && agentNome.isNotEmpty
          ? agentNome
          : 'Em atendimento';
    }

    return Container(
      padding: EdgeInsets.zero,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade200),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: diPertinRoxo.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.verified_outlined,
                color: diPertinRoxo,
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'Protocolo #$protocolo',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: Color(0xFF1A1A2E),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: badgeCor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: badgeCor.withValues(alpha: 0.25),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              badgeIcon,
                              size: 12,
                              color: badgeCor,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              badgeTexto,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: badgeCor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    encerrado
                        ? 'Esta conversa foi encerrada.'
                        : isWaiting
                            ? 'Seu chamado está na fila de espera.'
                            : 'Atendente disponível para ajudar.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
            if (onEncerrar != null && !encerrado) ...[
              const SizedBox(width: 8),
              Container(
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: IconButton(
                  tooltip: 'Encerrar atendimento',
                  icon: const Icon(
                    Icons.close_rounded,
                    size: 20,
                    color: Colors.red,
                  ),
                  onPressed: onEncerrar,
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _faixaFila({required String ticketId, required String cidade}) {
    return StreamBuilder<int>(
      stream: _svc.streamPosicaoFila(
        ticketId: ticketId,
        cidadeNormalizada: cidade,
      ),
      builder: (context, snap) {
        final pos = snap.data ?? 0;
        final emFila = pos > 0;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: diPertinLaranja.withValues(alpha: 0.07),
            border: Border(
              bottom: BorderSide(color: diPertinLaranja.withValues(alpha: 0.15)),
            ),
          ),
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 400),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: emFila
                      ? diPertinLaranja.withValues(alpha: 0.15)
                      : diPertinLaranja.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  emFila ? Icons.people_alt_rounded : Icons.hourglass_bottom_rounded,
                  color: diPertinLaranja,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      emFila
                          ? 'Você é o $posº na fila'
                          : 'Na fila de espera',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1A1A2E),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      emFila
                          ? 'Aguarde enquanto um atendente fica disponível.'
                          : 'Em breve um atendente irá atender você.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              if (emFila)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: diPertinLaranja.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: diPertinLaranja,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '$pos',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: diPertinLaranja,
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
  }

  Widget _rodapeDigitacao({
    required String ticketId,
    required String status,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(color: Colors.grey.shade200),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Container(
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(24),
              ),
              child: IconButton(
                tooltip: 'Anexar',
                icon: _enviandoAnexo
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: diPertinRoxo,
                        ),
                      )
                    : Icon(
                        Icons.add_circle_outline_rounded,
                        color: diPertinRoxo.withValues(alpha: 0.7),
                        size: 26,
                      ),
                onPressed: (_enviandoAnexo || _enviando)
                    ? null
                    : () => _abrirSheetAnexo(ticketId),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Container(
                constraints: const BoxConstraints(maxHeight: 120),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: TextField(
                  controller: _mensagemController,
                  maxLines: null,
                  textInputAction: TextInputAction.send,
                  decoration: InputDecoration(
                    hintText: status == SuporteTicketStatus.waiting
                        ? 'Descreva seu problema...'
                        : 'Digite sua mensagem...',
                    hintStyle: TextStyle(
                      color: Colors.grey.shade400,
                      fontSize: 14.5,
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 12,
                    ),
                  ),
                  textCapitalization: TextCapitalization.sentences,
                  onSubmitted: (_) => _enviarMensagem(ticketId),
                ),
              ),
            ),
            const SizedBox(width: 6),
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              decoration: BoxDecoration(
                color: _mensagemController.text.trim().isNotEmpty || _enviando
                    ? diPertinRoxo
                    : diPertinRoxo.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: _enviando
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.send_rounded, color: Colors.white),
                onPressed:
                    _enviando ? null : () => _enviarMensagem(ticketId),
                visualDensity: VisualDensity.comfortable,
              ),
            ),
          ],
        ),
      ),
    );
  }
  Widget _anexoOpcao({
    required BuildContext ctx,
    required IconData icone,
    required String titulo,
    required String subtitulo,
    required String valor,
  }) {
    return InkWell(
      onTap: () => Navigator.pop(ctx, valor),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: diPertinRoxo.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icone, color: diPertinRoxo, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    titulo,
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1A1A2E),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitulo,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.chevron_right_rounded,
                size: 16,
                color: Colors.grey.shade400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VisualizadorImagem extends StatelessWidget {
  const _VisualizadorImagem({required this.url, required this.titulo});
  final String url;
  final String titulo;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          titulo,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 14),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.open_in_new),
            tooltip: 'Abrir no navegador',
            onPressed: () async {
              final uri = Uri.tryParse(url);
              if (uri == null) return;
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            },
          ),
        ],
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 4,
          child: Image.network(
            url,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const Icon(
              Icons.broken_image_outlined,
              color: Colors.white,
              size: 64,
            ),
          ),
        ),
      ),
    );
  }
}
