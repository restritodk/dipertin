import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'policy_scroll_page.dart';

/// Quebra o texto do painel em seções quando cada título começa com `## ` na linha.
List<PolicySection> parseConteudoLegalEmSecoes(String conteudo) {
  final trimmed = conteudo.trim();
  if (trimmed.isEmpty) return [];

  final sections = <PolicySection>[];
  String? secTitle;
  final buf = StringBuffer();

  void flush() {
    final body = buf.toString().trim();
    buf.clear();
    if (secTitle == null && body.isEmpty) return;
    sections.add(PolicySection(
      titulo: secTitle,
      corpo: body.isEmpty ? ' ' : body,
    ));
    secTitle = null;
  }

  for (final rawLine in trimmed.split('\n')) {
    final m = RegExp(r'^##\s+(.+)$').firstMatch(rawLine);
    if (m != null) {
      flush();
      secTitle = m.group(1)!.trim();
    } else {
      if (buf.isNotEmpty) buf.writeln();
      buf.write(rawLine);
    }
  }
  flush();

  if (sections.isEmpty) {
    return [PolicySection(titulo: null, corpo: trimmed)];
  }
  return sections;
}

String? _campoTexto(dynamic v) {
  if (v == null) return null;
  if (v is String) return v;
  return v.toString();
}

DocumentSnapshot<Map<String, dynamic>>? _mergeServidorECache({
  required AsyncSnapshot<DocumentSnapshot<Map<String, dynamic>>> futServidor,
  required AsyncSnapshot<DocumentSnapshot<Map<String, dynamic>>> streamSnap,
}) {
  if (streamSnap.hasData) {
    final d = streamSnap.data!;
    if (!d.metadata.isFromCache) return d;
  }
  if (futServidor.connectionState == ConnectionState.done &&
      futServidor.hasData &&
      futServidor.data != null &&
      futServidor.data!.exists) {
    return futServidor.data;
  }
  if (streamSnap.hasData && streamSnap.data!.exists) {
    return streamSnap.data;
  }
  return null;
}

/// Documento em [conteudo_legal] com fallback para o texto embutido no app.
///
/// Força leitura do servidor ao abrir (evita cache offline antigo) e mantém
/// [snapshots] para refletir publicações feitas no painel web.
class PolicyRemotePage extends StatefulWidget {
  const PolicyRemotePage({
    super.key,
    required this.docId,
    required this.tituloPadrao,
    required this.secoesPadrao,
    this.rodape,
  });

  final String docId;
  final String tituloPadrao;
  final List<PolicySection> secoesPadrao;
  final String? rodape;

  @override
  State<PolicyRemotePage> createState() => _PolicyRemotePageState();
}

class _PolicyRemotePageState extends State<PolicyRemotePage> {
  late Future<DocumentSnapshot<Map<String, dynamic>>> _leituraServidor;
  late Stream<DocumentSnapshot<Map<String, dynamic>>> _stream;

  DocumentReference<Map<String, dynamic>> get _doc => FirebaseFirestore.instance
      .collection('conteudo_legal')
      .doc(widget.docId);

  @override
  void initState() {
    super.initState();
    _ligarLeituras();
  }

  void _ligarLeituras() {
    _leituraServidor = _doc.get(const GetOptions(source: Source.server));
    _stream = _doc.snapshots();
  }

  void _atualizarDoServidor() {
    setState(_ligarLeituras);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: _leituraServidor,
      builder: (context, futSnap) {
        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: _stream,
          builder: (context, streamSnap) {
            if (streamSnap.hasError) {
              debugPrint(
                '[conteudo_legal/${widget.docId}] stream: ${streamSnap.error}',
              );
            }
            if (futSnap.hasError) {
              debugPrint(
                '[conteudo_legal/${widget.docId}] servidor: ${futSnap.error}',
              );
            }

            var title = widget.tituloPadrao;
            var sections = widget.secoesPadrao;
            String? ultima;

            final merged = _mergeServidorECache(
              futServidor: futSnap,
              streamSnap: streamSnap,
            );

            if (merged != null && merged.exists) {
              final d = merged.data();
              if (d != null) {
                final c = _campoTexto(d['conteudo'])?.trim();
                if (c != null && c.isNotEmpty) {
                  final parsed = parseConteudoLegalEmSecoes(c);
                  if (parsed.isNotEmpty) {
                    sections = parsed;
                  }
                }
                final t = _campoTexto(d['titulo'])?.trim();
                if (t != null && t.isNotEmpty) title = t;
                final ts = d['data_atualizacao'];
                if (ts is Timestamp) {
                  ultima =
                      DateFormat("d 'de' MMMM 'de' y", 'pt_BR').format(ts.toDate());
                }
              }
            }

            return PolicyScrollPage(
              title: title,
              sections: sections,
              rodape: widget.rodape,
              ultimaAtualizacao: ultima,
              actions: [
                IconButton(
                  tooltip: 'Atualizar texto publicado',
                  onPressed: _atualizarDoServidor,
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
