// Arquivo: lib/screens/entregador/configuracoes/meus_documentos_screen.dart

import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../services/permissoes_app_service.dart';

const Color _roxo = Color(0xFF6A1B9A);
const Color _laranja = Color(0xFFFF8F00);

/// Lista os documentos "do motorista" (CNH).
/// Documentos do veículo (CRLV) vivem em `users/{uid}/veiculos/{vid}/documentos`.
class MeusDocumentosScreen extends StatefulWidget {
  const MeusDocumentosScreen({super.key});

  @override
  State<MeusDocumentosScreen> createState() => _MeusDocumentosScreenState();
}

class _MeusDocumentosScreenState extends State<MeusDocumentosScreen> {
  bool _enviando = false;

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  DocumentReference<Map<String, dynamic>>? _docCnh() {
    final uid = _uid;
    if (uid == null) return null;
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('documentos')
        .doc('cnh');
  }

  Future<void> _anexarCnh() async {
    final uid = _uid;
    final ref = _docCnh();
    if (uid == null || ref == null) return;

    final pr = await PermissoesAppService.garantirLeituraArquivosAnexos();
    if (!mounted) return;
    if (pr != ResultadoPermissao.concedida) {
      PermissoesFeedback.arquivosAnexos(context, pr);
      return;
    }
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf'],
    );
    if (result == null || result.files.single.path == null) return;

    setState(() => _enviando = true);
    try {
      final file = File(result.files.single.path!);
      final ext = file.path.split('.').last.toLowerCase();
      final ts = DateTime.now().millisecondsSinceEpoch;
      final storageRef = FirebaseStorage.instance
          .ref()
          .child('documentos_entregadores/$uid/cnh_$ts.$ext');
      final snap = await storageRef.putFile(file);
      final url = await snap.ref.getDownloadURL();

      await ref.set({
        'url': url,
        'status': 'pendente',
        'motivo_reprovacao': FieldValue.delete(),
        'atualizado_em': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('CNH enviada. Aguarde a aprovação da equipe.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao enviar: $e')),
      );
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ref = _docCnh();
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F7),
      appBar: AppBar(
        title: const Text(
          'Meus documentos',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: _roxo,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: ref == null
          ? const Center(child: Text('Você precisa estar autenticado.'))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  stream: FirebaseFirestore.instance
                      .collection('users')
                      .doc(_uid)
                      .snapshots(),
                  builder: (context, userSnap) {
                    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                      stream: ref.snapshots(),
                      builder: (context, snap) {
                        Map<String, dynamic>? data = snap.data?.data();

                        // Fallback: se ainda não existe na subcoleção, mostra o
                        // documento enviado no cadastro inicial (users.url_doc_pessoal).
                        if (data == null || (data['url'] ?? '').toString().isEmpty) {
                          final userData = userSnap.data?.data();
                          final urlLegado =
                              (userData?['url_doc_pessoal'] ?? '').toString();
                          if (urlLegado.isNotEmpty) {
                            data = {
                              'url': urlLegado,
                              'status': 'pendente',
                              'origem': 'cadastro_entregador',
                            };
                          }
                        }

                        return _CardDocumento(
                          titulo: 'CNH (Carteira Nacional de Habilitação)',
                          descricao:
                              'Usada para identificação e autorização de direção. Atualize assim que mudar sua habilitação.',
                          data: data,
                          enviando: _enviando,
                          onAnexar: _anexarCnh,
                        );
                      },
                    );
                  },
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _roxo.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline, color: _roxo, size: 18),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Documentos do veículo (CRLV) ficam na tela do próprio veículo, em Configurações > Veículo.',
                          style:
                              TextStyle(color: Colors.black54, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class _CardDocumento extends StatelessWidget {
  final String titulo;
  final String descricao;
  final Map<String, dynamic>? data;
  final bool enviando;
  final VoidCallback onAnexar;

  const _CardDocumento({
    required this.titulo,
    required this.descricao,
    required this.data,
    required this.enviando,
    required this.onAnexar,
  });

  @override
  Widget build(BuildContext context) {
    final status = (data?['status'] ?? '').toString();
    final motivo = (data?['motivo_reprovacao'] ?? '').toString();
    final url = (data?['url'] ?? '').toString();

    Color cor;
    IconData icone;
    String rotulo;
    switch (status.toLowerCase()) {
      case 'aprovado':
        cor = Colors.green;
        icone = Icons.check_circle;
        rotulo = 'Aprovado';
        break;
      case 'reprovado':
      case 'recusado':
        cor = Colors.red;
        icone = Icons.cancel;
        rotulo = 'Reprovado';
        break;
      case 'pendente':
        cor = Colors.orange;
        icone = Icons.schedule;
        rotulo = 'Em análise';
        break;
      default:
        cor = Colors.grey;
        icone = Icons.upload_file;
        rotulo = 'Não enviado';
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            titulo,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: _roxo,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            descricao,
            style: const TextStyle(color: Colors.black54, fontSize: 12),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: cor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: cor.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Icon(icone, color: cor),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        rotulo,
                        style: TextStyle(
                          color: cor,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (motivo.isNotEmpty)
                        Text(
                          'Motivo: $motivo',
                          style: TextStyle(color: cor, fontSize: 12),
                        ),
                    ],
                  ),
                ),
                ElevatedButton(
                  onPressed: enviando ? null : onAnexar,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _laranja,
                    foregroundColor: Colors.white,
                  ),
                  child: enviando
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : Text(url.isEmpty ? 'Anexar' : 'Trocar'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
