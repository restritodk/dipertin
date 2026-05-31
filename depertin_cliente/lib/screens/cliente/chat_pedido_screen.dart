// Arquivo: lib/screens/cliente/chat_pedido_screen.dart

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:photo_view/photo_view.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart'
    as video_platform;

const Color diPertinRoxo = Color(0xFF6A1B9A);
const Color diPertinLaranja = Color(0xFFFF8F00);

/// Chat simples da subcoleção `pedidos/{id}/mensagens`.
///
/// Reutilizado pelos dois lados:
/// - Cliente: abre pelo card em "Meus pedidos".
/// - Lojista: abre pelo card em "Gestão de pedidos".
///
/// Quando o pedido vai para `entregue`/`cancelado`, a caixa de texto some e a
/// conversa fica em modo leitura (as rules do Firestore já bloqueiam novos
/// `create` nessa subcoleção nesse estado).
class ChatPedidoScreen extends StatefulWidget {
  final String pedidoId;
  final String lojaId;
  final String lojaNome;

  /// Título principal no AppBar (default = `lojaNome`, mantido para uso atual
  /// do cliente). Lojista passa o nome do cliente.
  final String? tituloOverride;

  /// Subtítulo no AppBar (default = "Pedido #XXXXX").
  final String? subtituloOverride;

  /// Quando true, abre a conversa apenas para consulta: não envia mensagens
  /// e carrega o histórico uma vez, sem receber novas atualizações em tempo real.
  final bool somenteLeitura;

  final String? motivoSomenteLeitura;

  /// Coleção raiz que hospeda a conversa.
  /// Pedidos usam `pedidos/{id}/mensagens`; encomendas usam
  /// `encomendas/{id}/mensagens`.
  final String colecaoRaiz;

  /// Papel de quem abriu a conversa (`cliente` ou `loja`). Quando informado,
  /// o alinhamento das bolhas usa o papel real da mensagem, não apenas o UID.
  final String? remetenteTipo;

  const ChatPedidoScreen({
    super.key,
    required this.pedidoId,
    required this.lojaId,
    required this.lojaNome,
    this.tituloOverride,
    this.subtituloOverride,
    this.somenteLeitura = false,
    this.motivoSomenteLeitura,
    this.colecaoRaiz = 'pedidos',
    this.remetenteTipo,
  });

  /// Chave local usada para marcar "lido até" por pedido + usuário. O valor é
  /// um timestamp em ms. Contadores do card do pedido usam isso para mostrar
  /// o badge de mensagens novas.
  static String chaveLidoAte(String pedidoId, String uid) {
    return 'chat_pedido_lido_ate_${pedidoId}_$uid';
  }

  /// Lê "lido até" deste pedido para este usuário. `0` quando ainda não leu.
  static Future<int> lidoAteMs(String pedidoId, String uid) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getInt(chaveLidoAte(pedidoId, uid)) ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// Marca como lido no momento atual do dispositivo.
  static Future<void> marcarLidoAgora(String pedidoId, String uid) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
        chaveLidoAte(pedidoId, uid),
        DateTime.now().millisecondsSinceEpoch,
      );
    } catch (_) {
      // best-effort — badge é apenas visual, sem persistência crítica.
    }
  }

  @override
  State<ChatPedidoScreen> createState() => _ChatPedidoScreenState();
}

class _ChatPedidoScreenState extends State<ChatPedidoScreen> {
  final TextEditingController _mensagemController = TextEditingController();
  final String _meuId = FirebaseAuth.instance.currentUser?.uid ?? '';
  bool _enviandoAnexo = false;

  @override
  void initState() {
    super.initState();
    // Marca "lido até agora" ao abrir, e repete sempre que chegar mensagem
    // nova (via _atualizarLidoAte na stream das mensagens).
    _atualizarLidoAte();
  }

  @override
  void dispose() {
    // Ao sair, atualiza novamente para cobrir mensagens lidas durante a sessão.
    _atualizarLidoAte();
    _mensagemController.dispose();
    super.dispose();
  }

  Future<void> _atualizarLidoAte() async {
    if (_meuId.isEmpty) return;
    await ChatPedidoScreen.marcarLidoAgora(widget.pedidoId, _meuId);
  }

  Future<void> _enviarMensagem() async {
    if (widget.somenteLeitura) return;
    String texto = _mensagemController.text.trim();
    if (texto.isEmpty) return;

    _mensagemController.clear();

    await FirebaseFirestore.instance
        .collection(widget.colecaoRaiz)
        .doc(widget.pedidoId)
        .collection('mensagens')
        .add({
          'texto': texto,
          'remetente_id': _meuId,
          if (_meuTipoChat.isNotEmpty) 'remetente_tipo': _meuTipoChat,
          'data_envio': FieldValue.serverTimestamp(),
        });

    // Logo após enviar minha própria mensagem, atualizo "lido até" para evitar
    // badge indevido na minha caixa.
    await _atualizarLidoAte();
  }

  String _inferirMime(String nome, String fallback) {
    final n = nome.toLowerCase();
    if (n.endsWith('.jpg') || n.endsWith('.jpeg')) return 'image/jpeg';
    if (n.endsWith('.png')) return 'image/png';
    if (n.endsWith('.gif')) return 'image/gif';
    if (n.endsWith('.webp')) return 'image/webp';
    if (n.endsWith('.mp4')) return 'video/mp4';
    if (n.endsWith('.mov')) return 'video/quicktime';
    if (n.endsWith('.webm')) return 'video/webm';
    if (n.endsWith('.mkv')) return 'video/x-matroska';
    return fallback;
  }

  String _sanitizarNomeArquivo(String nome) {
    final limpo = nome.trim().replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');
    if (limpo.isEmpty) return 'anexo';
    return limpo.length > 80 ? limpo.substring(limpo.length - 80) : limpo;
  }

  void _mostrarErro(String mensagem) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(mensagem), backgroundColor: Colors.red.shade800),
    );
  }

  Future<void> _abrirOpcoesAnexo() async {
    if (widget.somenteLeitura || _enviandoAnexo) return;
    final escolha = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 6, 18, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Enviar anexo',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Text(
                'Envie fotos ou vídeos para acompanhar a encomenda.',
                style: TextStyle(color: Colors.grey.shade700),
              ),
              const SizedBox(height: 12),
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFFF3E5F5),
                  foregroundColor: diPertinRoxo,
                  child: Icon(Icons.photo_library),
                ),
                title: const Text('Fotos'),
                subtitle: const Text('Selecione até 50 imagens por vez'),
                onTap: () => Navigator.pop(ctx, 'imagens'),
              ),
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFFFFF3E0),
                  foregroundColor: diPertinLaranja,
                  child: Icon(Icons.videocam),
                ),
                title: const Text('Vídeo'),
                subtitle: const Text('Selecione 1 vídeo por vez'),
                onTap: () => Navigator.pop(ctx, 'video'),
              ),
            ],
          ),
        ),
      ),
    );

    if (!mounted || escolha == null) return;
    if (escolha == 'imagens') {
      await _selecionarEEnviarImagens();
    } else if (escolha == 'video') {
      await _selecionarEEnviarVideo();
    }
  }

  Future<void> _selecionarEEnviarImagens() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: true,
        withData: true,
      );
      if (result == null || result.files.isEmpty || !mounted) return;
      final arquivos = result.files.take(50).toList();
      if (result.files.length > 50) {
        _mostrarErro('Você pode enviar no máximo 50 imagens por vez.');
      }
      await _enviarAnexos(arquivos, tipo: 'imagem');
    } catch (e) {
      _mostrarErro('Erro ao selecionar imagens: $e');
    }
  }

  Future<void> _selecionarEEnviarVideo() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.video,
        allowMultiple: false,
        withData: true,
      );
      if (result == null || result.files.isEmpty || !mounted) return;
      await _enviarAnexos([result.files.single], tipo: 'video');
    } catch (e) {
      _mostrarErro('Erro ao selecionar vídeo: $e');
    }
  }

  Future<void> _enviarAnexos(
    List<PlatformFile> arquivos, {
    required String tipo,
  }) async {
    if (widget.somenteLeitura || arquivos.isEmpty) return;
    final uid = _meuId;
    if (uid.isEmpty) {
      _mostrarErro('Faça login novamente para enviar anexos.');
      return;
    }

    final limite = tipo == 'video' ? 80 * 1024 * 1024 : 20 * 1024 * 1024;
    final anexos = <Map<String, dynamic>>[];
    setState(() => _enviandoAnexo = true);
    try {
      for (final arquivo in arquivos) {
        final bytes = arquivo.bytes;
        if (bytes == null) {
          throw Exception('Não foi possível ler ${arquivo.name}.');
        }
        if (arquivo.size > limite) {
          throw Exception(
            tipo == 'video'
                ? 'Vídeo maior que 80 MB não é permitido.'
                : 'Imagem maior que 20 MB não é permitida.',
          );
        }
        final nome = arquivo.name.isNotEmpty
            ? arquivo.name
            : '${tipo}_${DateTime.now().millisecondsSinceEpoch}';
        final mime = _inferirMime(
          nome,
          tipo == 'video' ? 'video/mp4' : 'image/jpeg',
        );
        final path =
            'chat_anexos/${widget.colecaoRaiz}/${widget.pedidoId}/$uid/${DateTime.now().millisecondsSinceEpoch}_${_sanitizarNomeArquivo(nome)}';
        final ref = FirebaseStorage.instance.ref(path);
        final task = await ref.putData(
          Uint8List.fromList(bytes),
          SettableMetadata(contentType: mime),
        );
        final url = await task.ref.getDownloadURL();
        anexos.add({
          'url': url,
          'path': path,
          'nome': nome,
          'tipo': tipo,
          'mime': mime,
          'tamanho': arquivo.size,
        });
      }

      await FirebaseFirestore.instance
          .collection(widget.colecaoRaiz)
          .doc(widget.pedidoId)
          .collection('mensagens')
          .add({
            'texto': tipo == 'video' ? 'Enviou um vídeo' : 'Enviou imagem',
            'remetente_id': uid,
            if (_meuTipoChat.isNotEmpty) 'remetente_tipo': _meuTipoChat,
            'data_envio': FieldValue.serverTimestamp(),
            'anexos': anexos,
            'anexo_tipo': tipo == 'video' ? 'video' : 'image',
          });

      await _atualizarLidoAte();
    } catch (e) {
      _mostrarErro('Erro ao enviar anexo: $e');
    } finally {
      if (mounted) setState(() => _enviandoAnexo = false);
    }
  }

  static bool _chatEncerrado(String? status) {
    final s = status ?? '';
    return s == 'entregue' || s == 'cancelado';
  }

  static bool _chatEncerradoEncomenda(String? status) {
    final s = status ?? '';
    return s == 'encerrada_recusada_loja' ||
        s == 'encerrada_cancelada_cliente' ||
        s == 'encerrada_cancelada_loja' ||
        s == 'em_execucao_logistica';
  }

  bool get _ehEncomenda => widget.colecaoRaiz == 'encomendas';

  String get _meuTipoChat {
    final tipo = widget.remetenteTipo?.trim().toLowerCase();
    if (tipo == 'cliente' || tipo == 'loja') return tipo!;
    return '';
  }

  String _tipoMensagem(Map<String, dynamic> msg) {
    final tipo = (msg['remetente_tipo'] ?? msg['sender_type'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    if (tipo == 'cliente' || tipo == 'loja') return tipo;
    if (_ehEncomenda && msg['remetente_id'] == widget.lojaId) return 'loja';
    return '';
  }

  bool _mensagemEhMinha(Map<String, dynamic> msg) {
    final meuTipo = _meuTipoChat;
    final tipoMsg = _tipoMensagem(msg);
    if (meuTipo.isNotEmpty && tipoMsg.isNotEmpty) {
      return meuTipo == tipoMsg;
    }
    return msg['remetente_id'] == _meuId;
  }

  Query<Map<String, dynamic>> get _mensagensQuery => FirebaseFirestore.instance
      .collection(widget.colecaoRaiz)
      .doc(widget.pedidoId)
      .collection('mensagens')
      .orderBy('data_envio', descending: true);

  List<Map<String, dynamic>> _anexosDaMensagem(Map<String, dynamic> msg) {
    final raw = msg['anexos'];
    if (raw is List) {
      return raw
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    final url = (msg['anexo_url'] ?? '').toString().trim();
    if (url.isEmpty) return const <Map<String, dynamic>>[];
    return [
      {
        'url': url,
        'nome': (msg['anexo_nome'] ?? 'Anexo').toString(),
        'tipo': (msg['anexo_tipo'] ?? 'arquivo').toString(),
        'mime': (msg['anexo_mime'] ?? '').toString(),
      },
    ];
  }

  Future<void> _abrirAnexoExterno(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) {
      _mostrarErro('Não foi possível abrir o anexo.');
      return;
    }
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok) _mostrarErro('Não foi possível abrir o anexo.');
  }

  Future<void> _abrirImagemModal(String url) async {
    if (url.trim().isEmpty) {
      _mostrarErro('Imagem indisponível.');
      return;
    }
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.92),
      builder: (ctx) => Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: Stack(
          children: [
            PhotoView(
              imageProvider: NetworkImage(url),
              minScale: PhotoViewComputedScale.contained,
              maxScale: PhotoViewComputedScale.covered * 4,
              backgroundDecoration: const BoxDecoration(color: Colors.black),
              loadingBuilder: (_, _) => const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
              errorBuilder: (_, _, _) => const Center(
                child: Text(
                  'Não foi possível carregar a imagem.',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ),
            Positioned(
              top: 18,
              right: 12,
              child: SafeArea(
                child: CircleAvatar(
                  backgroundColor: Colors.black54,
                  child: IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.of(ctx).pop(),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _abrirVideoModal(String url, String nome, String mime) async {
    if (url.trim().isEmpty) {
      _mostrarErro('Vídeo indisponível.');
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.black,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => _VideoChatModal(url: url, nome: nome, mime: mime),
    );
  }

  Widget _buildAnexosMensagem(List<Map<String, dynamic>> anexos, bool souEu) {
    if (anexos.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: anexos.map((anexo) {
          final url = (anexo['url'] ?? '').toString();
          final tipo = (anexo['tipo'] ?? '').toString().toLowerCase();
          final mime = (anexo['mime'] ?? '').toString().toLowerCase();
          final nome = (anexo['nome'] ?? 'Anexo').toString();
          final ehImagem =
              tipo == 'imagem' || tipo == 'image' || mime.startsWith('image/');
          final ehVideo = tipo == 'video' || mime.startsWith('video/');

          if (ehImagem) {
            return InkWell(
              onTap: () => _abrirImagemModal(url),
              borderRadius: BorderRadius.circular(14),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Image.network(
                  url,
                  width: 150,
                  height: 150,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => _anexoFallback(
                    Icons.broken_image_outlined,
                    'Imagem indisponível',
                    souEu,
                  ),
                ),
              ),
            );
          }

          return InkWell(
            onTap: () => ehVideo
                ? _abrirVideoModal(url, nome, mime)
                : _abrirAnexoExterno(url),
            borderRadius: BorderRadius.circular(14),
            child: ehVideo
                ? _videoPreviewCard(souEu)
                : Container(
                    width: 190,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: souEu
                          ? Colors.white.withValues(alpha: 0.14)
                          : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: souEu
                            ? Colors.white.withValues(alpha: 0.22)
                            : Colors.grey.shade200,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.attach_file_rounded,
                          color: souEu ? Colors.white : diPertinRoxo,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            nome,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: souEu ? Colors.white : Colors.black87,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
          );
        }).toList(),
      ),
    );
  }

  Widget _videoPreviewCard(bool souEu) {
    return Container(
      width: 210,
      height: 138,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: souEu
              ? [
                  Colors.white.withValues(alpha: 0.24),
                  Colors.white.withValues(alpha: 0.10),
                ]
              : [const Color(0xFF2D1545), const Color(0xFF6A1B9A)],
        ),
        border: Border.all(
          color: souEu
              ? Colors.white.withValues(alpha: 0.24)
              : Colors.black.withValues(alpha: 0.06),
        ),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: Icon(
              Icons.movie_creation_outlined,
              size: 84,
              color: Colors.white.withValues(alpha: 0.14),
            ),
          ),
          Center(
            child: Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: diPertinLaranja,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.24),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: const Icon(
                Icons.play_arrow_rounded,
                color: Colors.white,
                size: 38,
              ),
            ),
          ),
          const Positioned(
            left: 12,
            right: 12,
            bottom: 10,
            child: Text(
              'Toque para assistir',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                shadows: [Shadow(color: Colors.black54, blurRadius: 6)],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _anexoFallback(IconData icon, String texto, bool souEu) {
    return Container(
      width: 150,
      height: 150,
      color: souEu ? Colors.white24 : Colors.grey.shade100,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: souEu ? Colors.white : Colors.grey.shade600),
          const SizedBox(height: 8),
          Text(
            texto,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: souEu ? Colors.white : Colors.grey.shade700,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _avisoSomenteLeitura(String texto) {
    return Material(
      color: Colors.amber.shade50,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Icon(Icons.info_outline, color: Colors.amber.shade900),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                texto,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey.shade900,
                  height: 1.3,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildListaMensagens({
    required AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>> snapshot,
    required bool encerrado,
  }) {
    if (snapshot.hasData && mounted) {
      _atualizarLidoAte();
    }

    if (snapshot.connectionState == ConnectionState.waiting) {
      return const Center(
        child: CircularProgressIndicator(color: diPertinRoxo),
      );
    }

    if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.chat_bubble_outline, size: 60, color: Colors.grey[400]),
            const SizedBox(height: 10),
            const Text(
              "Nenhuma mensagem ainda.",
              style: TextStyle(color: Colors.grey),
            ),
            Text(
              encerrado
                  ? 'Nenhuma conversa foi registrada neste pedido.'
                  : 'Envie uma mensagem para iniciar.',
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ],
        ),
      );
    }

    final mensagens = snapshot.data!.docs;

    return ListView.builder(
      reverse: true,
      padding: const EdgeInsets.all(15),
      itemCount: mensagens.length,
      itemBuilder: (context, index) {
        final msg = mensagens[index].data();
        final souEu = _mensagemEhMinha(msg);
        final texto = (msg['texto'] ?? '').toString().trim();
        final anexos = _anexosDaMensagem(msg);

        return Align(
          alignment: souEu ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.82,
            ),
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
            decoration: BoxDecoration(
              color: souEu ? diPertinRoxo : Colors.white,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(15),
                topRight: const Radius.circular(15),
                bottomLeft: Radius.circular(souEu ? 15 : 0),
                bottomRight: Radius.circular(souEu ? 0 : 15),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 5,
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildAnexosMensagem(anexos, souEu),
                if (texto.isNotEmpty)
                  Text(
                    texto,
                    style: TextStyle(
                      color: souEu ? Colors.white : Colors.black87,
                      fontSize: 15,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final tituloPrincipal = widget.tituloOverride?.trim().isNotEmpty == true
        ? widget.tituloOverride!.trim()
        : widget.lojaNome;
    final subtituloPadrao =
        "Pedido #${widget.pedidoId.substring(0, widget.pedidoId.length >= 5 ? 5 : widget.pedidoId.length).toUpperCase()}";
    final subtitulo = widget.subtituloOverride?.trim().isNotEmpty == true
        ? widget.subtituloOverride!.trim()
        : subtituloPadrao;

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tituloPrincipal,
              style: const TextStyle(fontSize: 18, color: Colors.white),
            ),
            Text(
              subtitulo,
              style: const TextStyle(fontSize: 12, color: Colors.white70),
            ),
          ],
        ),
        backgroundColor: diPertinRoxo,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection(widget.colecaoRaiz)
            .doc(widget.pedidoId)
            .snapshots(),
        builder: (context, pedidoSnap) {
          final dataPai = pedidoSnap.data?.data();
          final st = _ehEncomenda
              ? (dataPai == null
                    ? null
                    : dataPai['status_negociacao']?.toString())
              : (dataPai == null ? null : dataPai['status']?.toString());
          final encerrado =
              widget.somenteLeitura ||
              (_ehEncomenda ? _chatEncerradoEncomenda(st) : _chatEncerrado(st));
          final aviso = widget.somenteLeitura
              ? (widget.motivoSomenteLeitura ??
                    'Esta conversa está somente leitura.')
              : _ehEncomenda
              ? 'Encomenda encerrada. O chat está somente leitura.'
              : (st == 'cancelado'
                    ? 'Pedido cancelado. O chat está somente leitura.'
                    : 'Pedido entregue. O chat está somente leitura.');

          return Column(
            children: [
              if (encerrado) _avisoSomenteLeitura(aviso),
              Expanded(
                child: widget.somenteLeitura
                    ? FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
                        future: _mensagensQuery.get(),
                        builder: (context, snapshot) => _buildListaMensagens(
                          snapshot: snapshot,
                          encerrado: encerrado,
                        ),
                      )
                    : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                        stream: _mensagensQuery.snapshots(),
                        builder: (context, snapshot) => _buildListaMensagens(
                          snapshot: snapshot,
                          encerrado: encerrado,
                        ),
                      ),
              ),

              if (!encerrado)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 10,
                  ),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black12,
                        blurRadius: 10,
                        offset: Offset(0, -5),
                      ),
                    ],
                  ),
                  child: SafeArea(
                    child: Row(
                      children: [
                        IconButton(
                          tooltip: 'Enviar foto ou vídeo',
                          onPressed: _enviandoAnexo ? null : _abrirOpcoesAnexo,
                          icon: _enviandoAnexo
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.4,
                                    color: diPertinRoxo,
                                  ),
                                )
                              : const Icon(
                                  Icons.attach_file_rounded,
                                  color: diPertinRoxo,
                                ),
                        ),
                        Expanded(
                          child: TextField(
                            controller: _mensagemController,
                            decoration: InputDecoration(
                              hintText: "Digite sua mensagem...",
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 10,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(25),
                                borderSide: BorderSide(
                                  color: Colors.grey[300]!,
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(25),
                                borderSide: BorderSide(
                                  color: Colors.grey[300]!,
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(25),
                                borderSide: const BorderSide(
                                  color: diPertinRoxo,
                                ),
                              ),
                              filled: true,
                              fillColor: Colors.grey[50],
                            ),
                            textCapitalization: TextCapitalization.sentences,
                          ),
                        ),
                        const SizedBox(width: 10),
                        CircleAvatar(
                          radius: 25,
                          backgroundColor: diPertinLaranja,
                          child: IconButton(
                            icon: const Icon(Icons.send, color: Colors.white),
                            onPressed: _enviarMensagem,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _VideoChatModal extends StatefulWidget {
  final String url;
  final String nome;
  final String mime;

  const _VideoChatModal({
    required this.url,
    required this.nome,
    required this.mime,
  });

  @override
  State<_VideoChatModal> createState() => _VideoChatModalState();
}

class _VideoChatModalState extends State<_VideoChatModal> {
  late final VideoPlayerController _controller;
  late final Future<void> _init;
  Object? _erro;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(
      Uri.parse(widget.url),
      formatHint: _formatHint(),
      viewType: video_platform.VideoViewType.platformView,
    );
    _init = _controller
        .initialize()
        .then((_) {
          if (!mounted) return;
          setState(() {});
          _controller.play();
        })
        .catchError((e) {
          _erro = e;
          debugPrint('Erro ao carregar vídeo do chat: $e');
          if (mounted) setState(() {});
          throw e;
        });
    _controller.addListener(() {
      if (mounted) setState(() {});
    });
  }

  VideoFormat? _formatHint() {
    final nome = widget.nome.toLowerCase();
    final mime = widget.mime.toLowerCase();
    if (mime.contains('mpegurl') ||
        mime.contains('m3u8') ||
        nome.endsWith('.m3u8')) {
      return VideoFormat.hls;
    }
    return VideoFormat.other;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _tempo(Duration d) {
    final minutos = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final segundos = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutos:$segundos';
  }

  @override
  Widget build(BuildContext context) {
    final nome = widget.nome.trim().isEmpty ? 'Vídeo' : widget.nome.trim();
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.82,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    nome,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close, color: Colors.white),
                ),
              ],
            ),
          ),
          Expanded(
            child: FutureBuilder<void>(
              future: _init,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  );
                }
                if (snap.hasError ||
                    _erro != null ||
                    _controller.value.hasError ||
                    !_controller.value.isInitialized) {
                  final detalhe =
                      _controller.value.errorDescription ??
                      _erro?.toString() ??
                      'Formato não suportado pelo player interno.';
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.video_file_outlined,
                            color: Colors.white70,
                            size: 54,
                          ),
                          const SizedBox(height: 14),
                          const Text(
                            'Não foi possível carregar o vídeo no app.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            detalhe,
                            textAlign: TextAlign.center,
                            maxLines: 4,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white60),
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            'Feche esta tela e abra o vídeo novamente após reiniciar o app.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.white70),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                return Center(
                  child: AspectRatio(
                    aspectRatio: _controller.value.aspectRatio,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        VideoPlayer(_controller),
                        IconButton(
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.black54,
                            foregroundColor: Colors.white,
                            fixedSize: const Size(64, 64),
                          ),
                          iconSize: 42,
                          icon: Icon(
                            _controller.value.isPlaying
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                          ),
                          onPressed: () {
                            if (_controller.value.isPlaying) {
                              _controller.pause();
                            } else {
                              _controller.play();
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          if (_controller.value.isInitialized)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 18),
              child: Row(
                children: [
                  Text(
                    _tempo(_controller.value.position),
                    style: const TextStyle(color: Colors.white70),
                  ),
                  Expanded(
                    child: VideoProgressIndicator(
                      _controller,
                      allowScrubbing: true,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      colors: const VideoProgressColors(
                        playedColor: diPertinLaranja,
                        bufferedColor: Colors.white38,
                        backgroundColor: Colors.white12,
                      ),
                    ),
                  ),
                  Text(
                    _tempo(_controller.value.duration),
                    style: const TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
