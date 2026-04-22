// Arquivo: lib/widgets/chat_pedido_botao.dart
//
// Botão reutilizável para abrir o chat do pedido com badge de
// mensagens não lidas. Funciona tanto no card "Meus pedidos" do
// cliente quanto no card "Gestão de pedidos" do lojista.
//
// O controle de "lido" é local (SharedPreferences), já que a
// coleção `pedidos/{id}/mensagens` não guarda marcação por
// usuário — isso evita alterar regras e mantém o badge como
// sinalização visual por dispositivo.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:depertin_cliente/screens/cliente/chat_pedido_screen.dart';

const Color _roxo = Color(0xFF6A1B9A);
const Color _laranja = Color(0xFFFF8F00);

class ChatPedidoBotao extends StatefulWidget {
  const ChatPedidoBotao({
    super.key,
    required this.pedidoId,
    required this.lojaId,
    required this.lojaNome,
    this.tituloOverride,
    this.subtituloOverride,
    this.rotuloAtivo = 'Chat',
    this.rotuloEncerrado = 'Ver conversa',
    this.encerrado = false,
    this.compact = false,
  });

  final String pedidoId;
  final String lojaId;
  final String lojaNome;

  /// Título a ser exibido no AppBar do chat (ex.: "Cliente — João Silva"
  /// quando aberto pelo lojista, ou nome da loja quando aberto pelo cliente).
  final String? tituloOverride;
  final String? subtituloOverride;

  /// Rótulos do botão quando o chat está ativo/encerrado.
  final String rotuloAtivo;
  final String rotuloEncerrado;

  /// Se `true`, o botão abre apenas em modo leitura (pedido entregue/cancelado).
  final bool encerrado;

  /// Se `true`, usa layout reduzido (texto menor, ícone menor) para caber ao
  /// lado de outros botões de ação no mesmo card.
  final bool compact;

  @override
  State<ChatPedidoBotao> createState() => _ChatPedidoBotaoState();
}

class _ChatPedidoBotaoState extends State<ChatPedidoBotao> {
  late final String _meuUid = FirebaseAuth.instance.currentUser?.uid ?? '';
  int _lidoAteMs = 0;
  bool _carregouLido = false;

  @override
  void initState() {
    super.initState();
    _carregarLido();
  }

  Future<void> _carregarLido() async {
    if (_meuUid.isEmpty) {
      setState(() => _carregouLido = true);
      return;
    }
    final ms = await ChatPedidoScreen.lidoAteMs(widget.pedidoId, _meuUid);
    if (!mounted) return;
    setState(() {
      _lidoAteMs = ms;
      _carregouLido = true;
    });
  }

  Future<void> _abrirChat() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatPedidoScreen(
          pedidoId: widget.pedidoId,
          lojaId: widget.lojaId,
          lojaNome: widget.lojaNome,
          tituloOverride: widget.tituloOverride,
          subtituloOverride: widget.subtituloOverride,
        ),
      ),
    );
    // Ao voltar, recarrega para o badge zerar imediatamente.
    if (!mounted) return;
    await _carregarLido();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _streamMensagens() {
    return FirebaseFirestore.instance
        .collection('pedidos')
        .doc(widget.pedidoId)
        .collection('mensagens')
        .orderBy('data_envio', descending: true)
        .limit(50)
        .snapshots();
  }

  int _contarNaoLidas(QuerySnapshot<Map<String, dynamic>> snap) {
    if (_meuUid.isEmpty) return 0;
    final corteMs = _lidoAteMs;
    var total = 0;
    for (final doc in snap.docs) {
      final d = doc.data();
      final remetente = (d['remetente_id'] ?? '').toString();
      if (remetente == _meuUid) continue;
      final ts = d['data_envio'];
      if (ts is! Timestamp) continue;
      if (ts.millisecondsSinceEpoch > corteMs) total++;
    }
    return total;
  }

  @override
  Widget build(BuildContext context) {
    // Em chats encerrados não queremos contar não-lidas (não virão mais).
    if (widget.encerrado) {
      return _construirBotao(naoLidas: 0, encerrado: true);
    }

    if (!_carregouLido) {
      return _construirBotao(naoLidas: 0, encerrado: false);
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _streamMensagens(),
      builder: (context, snap) {
        final naoLidas = snap.hasData ? _contarNaoLidas(snap.data!) : 0;
        return _construirBotao(naoLidas: naoLidas, encerrado: false);
      },
    );
  }

  Widget _construirBotao({required int naoLidas, required bool encerrado}) {
    final rotulo = encerrado ? widget.rotuloEncerrado : widget.rotuloAtivo;
    final icone = encerrado
        ? Icons.history_edu_outlined
        : Icons.chat_outlined;
    final cor = encerrado ? Colors.grey.shade700 : _roxo;

    final conteudo = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icone, color: cor, size: widget.compact ? 18 : 20),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            rotulo,
            style: TextStyle(
              color: cor,
              fontWeight: FontWeight.w600,
              fontSize: widget.compact ? 13 : 14,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (naoLidas > 0) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: _laranja,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              naoLidas > 9 ? '9+' : '$naoLidas',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                height: 1.1,
              ),
            ),
          ),
        ],
      ],
    );

    return SizedBox(
      height: widget.compact ? 42 : 48,
      width: double.infinity,
      child: OutlinedButton(
        onPressed: _abrirChat,
        style: OutlinedButton.styleFrom(
          side: BorderSide(
            color: cor.withValues(alpha: 0.6),
            width: 1.2,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: EdgeInsets.symmetric(
            horizontal: widget.compact ? 10 : 14,
          ),
        ),
        child: conteudo,
      ),
    );
  }
}
