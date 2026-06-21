import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';

import '../utils/produto_link.dart';
import '../utils/safe_area_insets.dart';

const Color _roxo = Color(0xFF6A1B9A);
const Color _laranja = Color(0xFFFF8F00);
const Color _ink = Color(0xFF1A1A2E);
const Color _muted = Color(0xFF64748B);
const Color _fundo = Color(0xFFF5F4F8);

/// Abre o painel elegante de compartilhamento do produto.
///
/// O botão "Compartilhar" abre a folha nativa do sistema (WhatsApp, Instagram,
/// SMS, e-mail, etc.) com a foto + mensagem + link inteligente do produto.
Future<void> mostrarCompartilharProdutoSheet(
  BuildContext context, {
  required String produtoId,
  required String nome,
  required String precoFormatado,
  required String imagemUrl,
  String? lojaNome,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _CompartilharProdutoSheet(
      produtoId: produtoId,
      nome: nome,
      precoFormatado: precoFormatado,
      imagemUrl: imagemUrl,
      lojaNome: lojaNome,
    ),
  );
}

class _CompartilharProdutoSheet extends StatefulWidget {
  const _CompartilharProdutoSheet({
    required this.produtoId,
    required this.nome,
    required this.precoFormatado,
    required this.imagemUrl,
    this.lojaNome,
  });

  final String produtoId;
  final String nome;
  final String precoFormatado;
  final String imagemUrl;
  final String? lojaNome;

  @override
  State<_CompartilharProdutoSheet> createState() =>
      _CompartilharProdutoSheetState();
}

class _CompartilharProdutoSheetState extends State<_CompartilharProdutoSheet> {
  bool _compartilhando = false;

  String get _link => ProdutoLink.gerar(widget.produtoId);

  String get _mensagem =>
      'Olha este produto: ${widget.nome}\n'
      'Valor: ${widget.precoFormatado}\n'
      'Acesse aqui: $_link';

  Future<void> _compartilhar() async {
    if (_compartilhando) return;
    setState(() => _compartilhando = true);
    try {
      final List<XFile> arquivos = [];
      // Tenta anexar a foto do produto; se falhar, compartilha só o texto.
      final url = widget.imagemUrl.trim();
      if (url.startsWith('http')) {
        try {
          final resp = await http
              .get(Uri.parse(url))
              .timeout(const Duration(seconds: 8));
          if (resp.statusCode == 200 && resp.bodyBytes.isNotEmpty) {
            final mime = resp.headers['content-type'] ?? 'image/jpeg';
            final ext = mime.contains('png') ? 'png' : 'jpg';
            arquivos.add(
              XFile.fromData(
                resp.bodyBytes,
                mimeType: mime,
                name: 'dipertin_produto.$ext',
              ),
            );
          }
        } catch (_) {
          // Sem imagem: segue só com o texto/link.
        }
      }

      final params = ShareParams(
        text: _mensagem,
        subject: 'Produto no DiPertin: ${widget.nome}',
        files: arquivos.isEmpty ? null : arquivos,
      );
      await SharePlus.instance.share(params);

      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Não foi possível compartilhar: $e'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    } finally {
      if (mounted) setState(() => _compartilhando = false);
    }
  }

  Future<void> _copiarLink() async {
    await Clipboard.setData(ClipboardData(text: _link));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Link copiado!'),
        behavior: SnackBarBehavior.floating,
        backgroundColor: _roxo,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: _fundo,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        diPertinSafeAreaBottom(context) + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: _roxo.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.ios_share_rounded, color: _roxo, size: 20),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Compartilhar produto',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: _ink,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _cardPreview(),
          const SizedBox(height: 14),
          _previewMensagem(),
          const SizedBox(height: 18),
          SizedBox(
            height: 52,
            child: FilledButton.icon(
              onPressed: _compartilhando ? null : _compartilhar,
              style: FilledButton.styleFrom(
                backgroundColor: _laranja,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                textStyle: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              icon: _compartilhando
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.send_rounded, size: 20),
              label: Text(
                _compartilhando ? 'Preparando...' : 'Compartilhar agora',
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 50,
            child: OutlinedButton.icon(
              onPressed: _compartilhando ? null : _copiarLink,
              style: OutlinedButton.styleFrom(
                foregroundColor: _roxo,
                side: BorderSide(color: _roxo.withValues(alpha: 0.4)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                textStyle: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              icon: const Icon(Icons.link_rounded, size: 20),
              label: const Text('Copiar link'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _cardPreview() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE8E6F0)),
        boxShadow: [
          BoxShadow(
            color: _roxo.withValues(alpha: 0.05),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: widget.imagemUrl.trim().startsWith('http')
                ? Image.network(
                    widget.imagemUrl,
                    width: 64,
                    height: 64,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => _placeholder(),
                  )
                : _placeholder(),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.nome,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: _ink,
                  ),
                ),
                if ((widget.lojaNome ?? '').trim().isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    widget.lojaNome!.trim(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: _muted),
                  ),
                ],
                const SizedBox(height: 4),
                Text(
                  widget.precoFormatado,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: _laranja,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _placeholder() {
    return Container(
      width: 64,
      height: 64,
      color: const Color(0xFFEDEAF5),
      child: Icon(Icons.image_outlined, color: Colors.grey.shade400, size: 26),
    );
  }

  Widget _previewMensagem() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _roxo.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _roxo.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.chat_bubble_outline_rounded,
                  size: 15, color: _muted),
              const SizedBox(width: 6),
              Text(
                'Prévia da mensagem',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: _muted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _mensagem,
            style: const TextStyle(fontSize: 13, height: 1.5, color: _ink),
          ),
        ],
      ),
    );
  }
}
