import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:depertin_web/services/suporte_lojista_chat_service.dart';
import 'package:depertin_web/theme/painel_admin_theme.dart';
import 'package:depertin_web/widgets/dipertin_feedback_premium_modal.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

/// Abre o modal premium de suporte do lojista (chat em tempo real).
Future<void> abrirSuporteLojistaChatModal({
  required BuildContext context,
  required String lojaId,
  String? lojaNome,
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Fechar suporte',
    barrierColor: Colors.black.withValues(alpha: 0.55),
    transitionDuration: const Duration(milliseconds: 320),
    pageBuilder: (ctx, anim, sec) {
      return Align(
        alignment: Alignment.centerRight,
        child: _SuporteLojistaChatModal(
          lojaId: lojaId,
          lojaNome: lojaNome,
        ),
      );
    },
    transitionBuilder: (ctx, anim, sec, child) {
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0.08, 0.04),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
}

class _SuporteLojistaChatModal extends StatefulWidget {
  const _SuporteLojistaChatModal({
    required this.lojaId,
    this.lojaNome,
  });

  final String lojaId;
  final String? lojaNome;

  @override
  State<_SuporteLojistaChatModal> createState() =>
      _SuporteLojistaChatModalState();
}

class _SuporteLojistaChatModalState extends State<_SuporteLojistaChatModal> {
  final _svc = SuporteLojistaChatService.instance;
  final _textoCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _horaFmt = DateFormat('HH:mm', 'pt_BR');

  String? _ticketId;
  Map<String, dynamic>? _ticketData;
  StreamSubscription? _ticketSub;
  bool _enviando = false;
  bool _enviandoAnexo = false;
  bool _carregando = true;

  @override
  void initState() {
    super.initState();
    _iniciarStream();
  }

  @override
  void dispose() {
    _ticketSub?.cancel();
    _textoCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _iniciarStream() {
    _ticketSub?.cancel();
    _ticketSub = _svc.streamChamadoAberto().listen((doc) async {
      if (!mounted) return;
      if (doc == null || !doc.exists) {
        // Chamado saiu da fila (finalizado) — manter conversa se já estávamos nela
        if (_ticketId != null) {
          try {
            final d = await FirebaseFirestore.instance
                .collection('support_tickets')
                .doc(_ticketId)
                .get();
            if (!mounted) return;
            if (d.exists) {
              setState(() {
                _ticketData = d.data();
                _carregando = false;
              });
              return;
            }
          } catch (_) {}
        }
        setState(() {
          _ticketId = null;
          _ticketData = null;
          _carregando = false;
        });
        return;
      }
      setState(() {
        _carregando = false;
        _ticketId = doc.id;
        _ticketData = doc.data();
      });
    }, onError: (_) {
      if (!mounted) return;
      setState(() => _carregando = false);
    });
  }

  void _scrollParaFim() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollCtrl.hasClients) return;
      _scrollCtrl.animateTo(
        _scrollCtrl.position.maxScrollExtent + 80,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _enviar() async {
    final texto = _textoCtrl.text.trim();
    if (texto.isEmpty || _enviando) return;

    final status = _ticketData?['status']?.toString();
    if (SuporteTicketStatusWeb.estaFinalizado(status)) {
      await mostrarDiPertinFeedbackPremium(
        context,
        sucesso: false,
        titulo: 'Atendimento encerrado',
        mensagem:
            'Este chamado já foi finalizado. Feche e abra novamente para iniciar um novo.',
      );
      return;
    }

    setState(() => _enviando = true);
    _textoCtrl.clear();

    // Pausa o listener durante a escrita — evita INTERNAL ASSERTION do SDK web.
    await _ticketSub?.cancel();
    _ticketSub = null;

    try {
      await _svc.enviarMensagemLojista(
        texto: texto,
        lojaId: widget.lojaId,
      );
      // Recarrega chamado aberto sem whereIn
      final aberto = await _svc.buscarChamadoAberto();
      if (mounted) {
        setState(() {
          if (aberto != null && aberto.exists) {
            _ticketId = aberto.id;
            _ticketData = aberto.data();
          }
        });
      }
      _scrollParaFim();
    } catch (e) {
      if (mounted) {
        final msg = '$e'.replaceFirst(RegExp(r'^Exception:\s*'), '');
        await mostrarDiPertinFeedbackPremium(
          context,
          sucesso: false,
          titulo: 'Não foi possível enviar',
          mensagem: msg,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _enviando = false);
        _iniciarStream();
      }
    }
  }

  Future<void> _anexarArquivo() async {
    if (_enviando || _enviandoAnexo) return;
    final status = _ticketData?['status']?.toString();
    if (SuporteTicketStatusWeb.estaFinalizado(status)) {
      await mostrarDiPertinFeedbackPremium(
        context,
        sucesso: false,
        titulo: 'Atendimento encerrado',
        mensagem: 'Não é possível enviar arquivos em um chamado finalizado.',
      );
      return;
    }

    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        withData: true,
        allowMultiple: false,
        type: FileType.custom,
        allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp', 'gif', 'pdf'],
      );
    } catch (e) {
      if (!mounted) return;
      await mostrarDiPertinFeedbackPremium(
        context,
        sucesso: false,
        titulo: 'Seletor de arquivos',
        mensagem: 'Não foi possível abrir o seletor: $e',
      );
      return;
    }
    if (result == null || result.files.isEmpty) return;
    final picked = result.files.single;
    final bytes = picked.bytes;
    if (bytes == null) {
      if (!mounted) return;
      await mostrarDiPertinFeedbackPremium(
        context,
        sucesso: false,
        titulo: 'Arquivo inválido',
        mensagem: 'Não foi possível ler o arquivo selecionado.',
      );
      return;
    }

    setState(() => _enviandoAnexo = true);
    await _ticketSub?.cancel();
    _ticketSub = null;

    try {
      await _svc.enviarAnexoLojista(
        lojaId: widget.lojaId,
        bytes: bytes,
        nomeArquivo: picked.name,
        mimeType: picked.extension == 'pdf'
            ? 'application/pdf'
            : (picked.extension == 'png'
                ? 'image/png'
                : picked.extension == 'webp'
                    ? 'image/webp'
                    : picked.extension == 'gif'
                        ? 'image/gif'
                        : 'image/jpeg'),
        tamanhoBytes: picked.size,
        legenda: _textoCtrl.text.trim(),
      );
      _textoCtrl.clear();
      final aberto = await _svc.buscarChamadoAberto();
      if (mounted) {
        setState(() {
          if (aberto != null && aberto.exists) {
            _ticketId = aberto.id;
            _ticketData = aberto.data();
          }
        });
      }
      _scrollParaFim();
    } catch (e) {
      if (mounted) {
        final msg = '$e'.replaceFirst(RegExp(r'^Exception:\s*'), '');
        await mostrarDiPertinFeedbackPremium(
          context,
          sucesso: false,
          titulo: 'Não foi possível enviar o arquivo',
          mensagem: msg,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _enviandoAnexo = false);
        _iniciarStream();
      }
    }
  }

  Future<void> _abrirAnexo(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (!mounted) return;
      await mostrarDiPertinFeedbackPremium(
        context,
        sucesso: false,
        titulo: 'Anexo',
        mensagem: 'Não foi possível abrir o arquivo.',
      );
    }
  }

  String _fmtTamanho(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Future<void> _encerrar() async {
    final id = _ticketId;
    if (id == null) return;

    final ok = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Encerrar atendimento?',
          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800),
        ),
        content: Text(
          'Deseja realmente finalizar este atendimento?',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 14,
            color: const Color(0xFF64748B),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: PainelAdminTheme.roxo,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Finalizar'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    try {
      final nome = (_ticketData?['solicitante_loja_nome'] ??
              widget.lojaNome ??
              'loja')
          .toString();
      await _svc.encerrarPeloLojista(ticketId: id, lojaNome: nome);
      if (!mounted) return;
      await mostrarDiPertinFeedbackPremium(
        context,
        sucesso: true,
        titulo: 'Atendimento encerrado',
        mensagem: 'O chamado foi finalizado com sucesso.',
      );
    } catch (e) {
      if (!mounted) return;
      await mostrarDiPertinFeedbackPremium(
        context,
        sucesso: false,
        titulo: 'Erro ao encerrar',
        mensagem: '$e',
      );
    }
  }

  void _fechar() => Navigator.of(context).pop();

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final maxH = size.height * 0.82;
    final maxW = size.width < 520 ? size.width - 24.0 : 460.0;

    final status = _ticketData?['status']?.toString();
    final etapa = _ticketData?['lojista_chat_etapa']?.toString();
    final visual = SuporteLojistaChatService.statusVisual(
      status: status,
      etapa: etapa,
    );
    final aberto = SuporteTicketStatusWeb.estaAberto(status);
    final finalizado = SuporteTicketStatusWeb.estaFinalizado(status);

    return Material(
      color: Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxW, maxHeight: maxH),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: PainelAdminTheme.roxo.withValues(alpha: 0.22),
                  blurRadius: 32,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                _buildHeader(visual),
                Expanded(child: _buildBody(finalizado)),
                if (!finalizado || _ticketId == null)
                  _buildComposer(podeEnviar: _ticketId == null || aberto),
                if (aberto) _buildEncerrarBar(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(({String label, int cor, String emoji}) visual) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 14, 8, 14),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF6A1B9A), Color(0xFF8E24AA)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.support_agent_rounded,
                color: Colors.white, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '💬 Suporte DiPertin',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Atendimento em tempo real',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    color: Colors.white.withValues(alpha: 0.88),
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: Color(visual.cor),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${visual.emoji} ${visual.label}',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Fechar',
            onPressed: _fechar,
            icon: const Icon(Icons.close_rounded, color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(bool finalizado) {
    if (_carregando) {
      return const Center(
        child: CircularProgressIndicator(color: PainelAdminTheme.roxo),
      );
    }

    if (_ticketId == null) {
      return _buildEmptyWelcome();
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _svc.streamMensagens(_ticketId!),
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(
            child: Text(
              'Erro ao carregar mensagens.',
              style: GoogleFonts.plusJakartaSans(color: const Color(0xFF64748B)),
            ),
          );
        }
        if (!snap.hasData) {
          return const Center(
            child: CircularProgressIndicator(color: PainelAdminTheme.roxo),
          );
        }

        final docs = snap.data!.docs;
        _scrollParaFim();

        if (docs.isEmpty) {
          return _buildEmptyWelcome();
        }

        return ListView.builder(
          controller: _scrollCtrl,
          padding: const EdgeInsets.fromLTRB(14, 16, 14, 12),
          itemCount: docs.length + (finalizado ? 1 : 0),
          itemBuilder: (context, i) {
            if (finalizado && i == docs.length) {
              return Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  'Este atendimento foi finalizado.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    color: const Color(0xFF94A3B8),
                  ),
                ),
              );
            }
            final data = docs[i].data();
            return _bolha(data);
          },
        );
      },
    );
  }

  Widget _buildEmptyWelcome() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    PainelAdminTheme.roxo.withValues(alpha: 0.15),
                    PainelAdminTheme.laranja.withValues(alpha: 0.12),
                  ],
                ),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.waving_hand_rounded,
                  color: PainelAdminTheme.roxo, size: 32),
            ),
            const SizedBox(height: 18),
            Text(
              'Olá!',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF1A1A2E),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Como podemos ajudá-lo hoje?',
              textAlign: TextAlign.center,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF1A1A2E),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Escreva sua primeira mensagem.',
              textAlign: TextAlign.center,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                color: const Color(0xFF64748B),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bolha(Map<String, dynamic> data) {
    final tipo = (data['sender_type'] ?? '').toString();
    final auto = data['suporte_auto'] == true || data['is_system'] == true;
    final isSystem = tipo == 'system' || auto;
    final isClient = tipo == 'client' && !auto;
    final texto = (data['mensagem'] ?? '').toString();
    final ts = data['created_at'];
    final hora = ts is Timestamp ? _horaFmt.format(ts.toDate()) : '';

    if (isSystem) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Align(
          alignment: Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 340),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFF3E8FF),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE9D5FF)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Suporte DiPertin',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: PainelAdminTheme.roxo,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    texto,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      height: 1.4,
                      color: const Color(0xFF1A1A2E),
                    ),
                  ),
                  if (hora.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      hora,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 9,
                        color: const Color(0xFF94A3B8),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
    }

    final agent = tipo == 'agent';
    final anexoUrl = (data['anexo_url'] ?? '').toString();
    final anexoTipo = (data['anexo_tipo'] ?? '').toString();
    final anexoNome = (data['anexo_nome'] ?? 'arquivo').toString();
    final anexoTam = (data['anexo_tamanho'] is num)
        ? (data['anexo_tamanho'] as num).toInt()
        : 0;
    final fg = isClient ? Colors.white : const Color(0xFF1A1A2E);
    final fgMuted =
        isClient ? Colors.white.withValues(alpha: 0.75) : const Color(0xFF94A3B8);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Align(
        alignment: isClient ? Alignment.centerRight : Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              gradient: isClient
                  ? const LinearGradient(
                      colors: [Color(0xFF6A1B9A), Color(0xFF8E24AA)],
                    )
                  : null,
              color: isClient ? null : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16),
                topRight: const Radius.circular(16),
                bottomLeft: Radius.circular(isClient ? 16 : 4),
                bottomRight: Radius.circular(isClient ? 4 : 16),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (agent)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      'Atendente',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: PainelAdminTheme.roxo,
                      ),
                    ),
                  ),
                if (anexoUrl.isNotEmpty) ...[
                  if (anexoTipo == 'image')
                    GestureDetector(
                      onTap: () => _abrirAnexo(anexoUrl),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            maxHeight: 200,
                            maxWidth: 280,
                          ),
                          child: Image.network(
                            anexoUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => Container(
                              height: 100,
                              color: Colors.black26,
                              alignment: Alignment.center,
                              child: Icon(Icons.broken_image_outlined,
                                  color: fg),
                            ),
                          ),
                        ),
                      ),
                    )
                  else
                    Material(
                      color: isClient
                          ? Colors.white.withValues(alpha: 0.15)
                          : Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () => _abrirAnexo(anexoUrl),
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.picture_as_pdf_rounded,
                                color: isClient
                                    ? Colors.white
                                    : const Color(0xFFDC2626),
                                size: 28,
                              ),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      anexoNome,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: fg,
                                      ),
                                    ),
                                    if (anexoTam > 0)
                                      Text(
                                        _fmtTamanho(anexoTam),
                                        style: GoogleFonts.plusJakartaSans(
                                          fontSize: 10,
                                          color: fgMuted,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 6),
                              Icon(Icons.open_in_new_rounded,
                                  size: 16, color: fgMuted),
                            ],
                          ),
                        ),
                      ),
                    ),
                  if (texto.isNotEmpty) const SizedBox(height: 8),
                ],
                if (texto.isNotEmpty)
                  Text(
                    texto,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      height: 1.4,
                      color: fg,
                    ),
                  ),
                if (hora.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    hora,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 9,
                      color: fgMuted,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildComposer({required bool podeEnviar}) {
    final ocupado = _enviando || _enviandoAnexo;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFFEEEAF6))),
        color: Color(0xFFFAFAFC),
      ),
      child: Row(
        children: [
          // Clipe — anexar imagem/PDF
          Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: podeEnviar && !ocupado ? _anexarArquivo : null,
              child: Container(
                width: 44,
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: _enviandoAnexo
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: PainelAdminTheme.roxo,
                        ),
                      )
                    : Icon(
                        Icons.attach_file_rounded,
                        color: podeEnviar && !ocupado
                            ? PainelAdminTheme.roxo
                            : const Color(0xFFCBD5E1),
                        size: 22,
                      ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _textoCtrl,
              enabled: podeEnviar && !ocupado,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _enviar(),
              style: GoogleFonts.plusJakartaSans(fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Digite sua mensagem...',
                hintStyle: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  color: const Color(0xFF94A3B8),
                ),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(
                    color: PainelAdminTheme.roxo,
                    width: 1.5,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Material(
            color: PainelAdminTheme.roxo,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: podeEnviar && !ocupado ? _enviar : null,
              child: SizedBox(
                width: 48,
                height: 48,
                child: _enviando
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.send_rounded, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEncerrarBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: _encerrar,
          icon: const Icon(Icons.call_end_rounded, size: 16),
          label: Text(
            'Encerrar atendimento',
            style: GoogleFonts.plusJakartaSans(
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFFDC2626),
            side: const BorderSide(color: Color(0xFFFECACA)),
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ),
    );
  }
}
