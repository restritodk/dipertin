import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:depertin_cliente/services/firebase_functions_config.dart';
import 'package:depertin_cliente/services/location_service.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

const Color _roxo = Color(0xFF6A1B9A);
const Color _laranja = Color(0xFFFF8F00);
const Color _verdeVaga = Color(0xFF2E7D32);

class VagasScreen extends StatefulWidget {
  const VagasScreen({super.key});

  @override
  State<VagasScreen> createState() => _VagasScreenState();
}

class _VagasScreenState extends State<VagasScreen> {
  final TextEditingController _buscaCtrl = TextEditingController();
  String _termoBusca = '';

  @override
  void dispose() {
    _buscaCtrl.dispose();
    super.dispose();
  }

  List<QueryDocumentSnapshot> _filtrar(List<QueryDocumentSnapshot> docs) {
    final agora = DateTime.now();
    final limite3Dias = agora.subtract(const Duration(days: 3));

    // Cidade do usuário usada para o filtro por cidade/UF.
    final loc = context.read<LocationService>();
    final cidadeNorm = loc.cidadeNormalizada;
    final ufNorm = loc.ufNormalizado;

    var validas = docs.where((d) {
      final data = d.data() as Map<String, dynamic>;
      if (data['ativo'] != true) return false;
      final tsFim = data['data_fim'] as Timestamp?;
      final tsVenc = data['data_vencimento'] as Timestamp?;
      final venc = tsFim?.toDate() ?? tsVenc?.toDate();
      if (venc != null && venc.isBefore(limite3Dias)) return false;

      // Filtro por cidade: vazio => global; preenchido => apenas a cidade/UF.
      if (!LocationService.anuncioCidadeCorrespondeUsuario(
        cidadeNormalizada: data['cidade_normalizada']?.toString(),
        cidade: data['cidade']?.toString(),
        cidadeNormUsuario: cidadeNorm,
        ufNormUsuario: ufNorm,
        globalSeVazio: true,
      )) {
        return false;
      }
      return true;
    }).toList();

    if (_termoBusca.isEmpty) return validas;

    final termos = _termoBusca.toLowerCase().split(RegExp(r'\s+'));
    return validas.where((d) {
      final data = d.data() as Map<String, dynamic>;
      final alvo = [
        data['cargo'] ?? '',
        data['empresa'] ?? '',
        data['cidade'] ?? '',
        data['descricao'] ?? '',
      ].join(' ').toLowerCase();
      return termos.every((t) => alvo.contains(t));
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    // Reage a mudanças na cidade detectada do usuário para refiltrar.
    context.watch<LocationService>();
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F7),
      body: NestedScrollView(
        headerSliverBuilder: (_, __) => [
          SliverAppBar(
            expandedHeight: 175,
            pinned: true,
            backgroundColor: _roxo,
            iconTheme: const IconThemeData(color: Colors.white),
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF7B1FA2), Color(0xFF4A148C)],
                  ),
                ),
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 48, 20, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Vagas de Emprego',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Encontre a oportunidade certa para você',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.75),
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(56),
              child: Container(
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: TextField(
                  controller: _buscaCtrl,
                  onChanged: (v) => setState(() => _termoBusca = v.trim()),
                  textInputAction: TextInputAction.search,
                  style: const TextStyle(fontSize: 15),
                  decoration: InputDecoration(
                    hintText: 'Buscar vaga, empresa ou cidade...',
                    hintStyle: TextStyle(color: Colors.grey.shade400),
                    prefixIcon:
                        Icon(Icons.search_rounded, color: _roxo.withValues(alpha: 0.6)),
                    suffixIcon: _termoBusca.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.close, size: 20),
                            onPressed: () {
                              _buscaCtrl.clear();
                              setState(() => _termoBusca = '');
                            },
                          )
                        : null,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
        body: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('vagas')
              .where('ativo', isEqualTo: true)
              .orderBy('data_criacao', descending: true)
              .snapshots(),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator(color: _roxo),
              );
            }
            if (!snap.hasData || snap.data!.docs.isEmpty) {
              return _estadoVazio(
                Icons.work_off_rounded,
                'Nenhuma vaga disponível',
                'Novas oportunidades aparecerão aqui.',
              );
            }

            final vagas = _filtrar(snap.data!.docs);

            if (vagas.isEmpty) {
              return _estadoVazio(
                Icons.search_off_rounded,
                'Nenhuma vaga encontrada',
                'Tente buscar por outro termo ou aguarde novas publicações.',
              );
            }

            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              itemCount: vagas.length + 1,
              itemBuilder: (context, i) {
                if (i == 0) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12, left: 4),
                    child: Text(
                      '${vagas.length} vaga${vagas.length == 1 ? '' : 's'} encontrada${vagas.length == 1 ? '' : 's'}',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  );
                }

                final doc = vagas[i - 1];
                final data = doc.data() as Map<String, dynamic>;
                return _VagaCard(
                  vagaId: doc.id,
                  dados: data,
                  onTap: () => _abrirDetalhes(context, doc.id, data),
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _estadoVazio(IconData icon, String titulo, String sub) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: _roxo.withValues(alpha: 0.06),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 56, color: _roxo.withValues(alpha: 0.35)),
            ),
            const SizedBox(height: 20),
            Text(
              titulo,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Color(0xFF333333),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              sub,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade500, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  void _abrirDetalhes(
    BuildContext ctx,
    String vagaId,
    Map<String, dynamic> dados,
  ) async {
    final querCandidatar = await showModalBottomSheet<bool>(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _VagaDetalhesSheet(vagaId: vagaId, dados: dados),
    );

    if (!mounted || querCandidatar != true) return;

    final email = (dados['email'] ?? '').toString();
    final cargo = (dados['cargo'] ?? 'Vaga').toString();
    final empresa = (dados['empresa'] ?? '').toString();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _CandidaturaSheet(
          vagaId: vagaId,
          cargo: cargo,
          empresa: empresa,
          emailEmpresa: email,
        ),
      );
    });
  }
}

// ---------------------------------------------------------------------------
// CARD DE VAGA
// ---------------------------------------------------------------------------
class _VagaCard extends StatelessWidget {
  final String vagaId;
  final Map<String, dynamic> dados;
  final VoidCallback onTap;

  const _VagaCard({
    required this.vagaId,
    required this.dados,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cargo = dados['cargo'] ?? 'Vaga';
    final empresa = dados['empresa'] ?? '';
    final cidade = dados['cidade'] ?? '';
    final descricao = dados['descricao'] ?? '';
    final imagemUrl = (dados['imagem_url'] ?? '').toString();

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        elevation: 0,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFEEEEEE)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: imagemUrl.isNotEmpty
                          ? Image.network(
                              imagemUrl,
                              width: 48,
                              height: 48,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => _iconePadraoVaga(),
                            )
                          : _iconePadraoVaga(),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            cargo,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF1A1A2E),
                              letterSpacing: -0.2,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (empresa.isNotEmpty) ...[
                            const SizedBox(height: 3),
                            Text(
                              empresa,
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey.shade700,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ],
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: Colors.grey.shade400,
                    ),
                  ],
                ),
                if (cidade.isNotEmpty || descricao.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Divider(height: 1),
                  const SizedBox(height: 12),
                ],
                if (cidade.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Icon(
                          Icons.location_on_outlined,
                          size: 16,
                          color: _laranja.withValues(alpha: 0.8),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            cidade,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (descricao.isNotEmpty)
                  Text(
                    descricao,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13.5,
                      color: Colors.grey.shade600,
                      height: 1.4,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _iconePadraoVaga() {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: _verdeVaga.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(
        Icons.work_rounded,
        color: _verdeVaga.withValues(alpha: 0.7),
        size: 24,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// SHEET DE DETALHES DA VAGA
// ---------------------------------------------------------------------------
class _VagaDetalhesSheet extends StatelessWidget {
  final String vagaId;
  final Map<String, dynamic> dados;

  const _VagaDetalhesSheet({required this.vagaId, required this.dados});

  @override
  Widget build(BuildContext context) {
    final cargo = dados['cargo'] ?? 'Vaga';
    final empresa = dados['empresa'] ?? 'Empresa não informada';
    final cidade = dados['cidade'] ?? '';
    final descricao = dados['descricao'] ?? 'Sem descrição disponível.';
    final contato = dados['contato'] ?? '';
    final imagemUrl = (dados['imagem_url'] ?? '').toString();

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (_, controller) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            Expanded(
              child: ListView(
                controller: controller,
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
                children: [
                  if (imagemUrl.isNotEmpty)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Image.network(
                        imagemUrl,
                        width: double.infinity,
                        height: 200,
                        fit: BoxFit.cover,
                        loadingBuilder: (c, child, progress) {
                          if (progress == null) return child;
                          return Container(
                            height: 200,
                            color: Colors.grey.shade100,
                            alignment: Alignment.center,
                            child: CircularProgressIndicator(
                              color: _verdeVaga,
                              value: progress.expectedTotalBytes != null
                                  ? progress.cumulativeBytesLoaded /
                                      progress.expectedTotalBytes!
                                  : null,
                            ),
                          );
                        },
                        errorBuilder: (_, __, ___) => _cabecalhoIconePadrao(),
                      ),
                    )
                  else
                    _cabecalhoIconePadrao(),
                  const SizedBox(height: 18),
                  Text(
                    cargo,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF1A1A2E),
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Icon(Icons.business_rounded,
                          size: 18, color: Colors.grey.shade500),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          empresa,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (cidade.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(Icons.location_on_outlined,
                            size: 18, color: _laranja.withValues(alpha: 0.8)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            cidade,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 24),
                  const Text(
                    'Descrição da vaga',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1A1A2E),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFAF9FC),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFECE9F1)),
                    ),
                    child: Text(
                      descricao,
                      style: const TextStyle(
                        fontSize: 14.5,
                        color: Color(0xFF444444),
                        height: 1.6,
                      ),
                    ),
                  ),
                  if (contato.isNotEmpty) ...[
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Icon(Icons.phone_outlined,
                            size: 18, color: Colors.grey.shade500),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            contato,
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton.icon(
                      onPressed: () => Navigator.pop(context, true),
                      icon: const Icon(Icons.send_rounded, size: 20),
                      label: const Text(
                        'Candidatar-se',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _verdeVaga,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 2,
                        shadowColor: _verdeVaga.withValues(alpha: 0.3),
                      ),
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

  Widget _cabecalhoIconePadrao() {
    return Container(
      width: 60,
      height: 60,
      decoration: BoxDecoration(
        color: _verdeVaga.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Icon(
        Icons.work_rounded,
        color: _verdeVaga.withValues(alpha: 0.7),
        size: 30,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// SHEET DE CANDIDATURA
// ---------------------------------------------------------------------------
class _CandidaturaSheet extends StatefulWidget {
  final String vagaId;
  final String cargo;
  final String empresa;
  final String emailEmpresa;

  const _CandidaturaSheet({
    required this.vagaId,
    required this.cargo,
    required this.empresa,
    required this.emailEmpresa,
  });

  @override
  State<_CandidaturaSheet> createState() => _CandidaturaSheetState();
}

class _CandidaturaSheetState extends State<_CandidaturaSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nomeCtrl = TextEditingController();
  final _telefoneCtrl = TextEditingController();
  String? _nomeArquivo;
  Uint8List? _bytesArquivo;
  bool _enviando = false;

  @override
  void initState() {
    super.initState();
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      _nomeCtrl.text = user.displayName ?? '';
    }
  }

  @override
  void dispose() {
    _nomeCtrl.dispose();
    _telefoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _escolherCurriculo() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'doc', 'docx'],
      withData: true,
    );
    if (result != null && result.files.first.bytes != null) {
      setState(() {
        _nomeArquivo = result.files.first.name;
        _bytesArquivo = result.files.first.bytes;
      });
    }
  }

  Future<void> _enviar() async {
    if (!_formKey.currentState!.validate()) return;
    if (_bytesArquivo == null) {
      _mostrarErroEnvio(context, 'Anexe seu currículo para continuar.');
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _mostrarErroEnvio(context, 'Faça login para enviar sua candidatura.');
      return;
    }

    setState(() => _enviando = true);

    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (!userDoc.exists) {
        if (!mounted) return;
        setState(() => _enviando = false);
        _mostrarErroEnvio(
          context,
          'Você precisa ter cadastro completo na plataforma para se candidatar.',
        );
        return;
      }
      final uid = user.uid;
      final ts = DateTime.now().millisecondsSinceEpoch;
      final ext = _nomeArquivo?.split('.').last ?? 'pdf';
      final storagePath = 'candidaturas/${widget.vagaId}/${uid}_$ts.$ext';

      // 1) Upload do currículo
      String urlCurriculo;
      try {
        final ref = FirebaseStorage.instance.ref().child(storagePath);
        await ref.putData(
          _bytesArquivo!,
          SettableMetadata(contentType: _mimeType(ext)),
        );
        urlCurriculo = await ref.getDownloadURL();
      } catch (e) {
        if (!mounted) return;
        setState(() => _enviando = false);
        _mostrarErroEnvio(
          context,
          'Erro ao enviar o currículo.\n$e',
        );
        return;
      }

      // 2) Salvar candidatura no Firestore
      await FirebaseFirestore.instance.collection('candidaturas').add({
        'vagaId': widget.vagaId,
        'cargo': widget.cargo,
        'empresa': widget.empresa,
        'emailEmpresa': widget.emailEmpresa,
        'nomeCompleto': _nomeCtrl.text.trim(),
        'telefone': _telefoneCtrl.text.trim(),
        'urlCurriculo': urlCurriculo,
        'nomeArquivo': _nomeArquivo ?? 'curriculo.$ext',
        'uid': uid,
        'email_enviado': false,
        'data_envio': FieldValue.serverTimestamp(),
      });

      // 3) Enviar e-mail via Cloud Function
      try {
        final callable = appFirebaseFunctions.httpsCallable(
          'enviarCandidaturaVaga',
          options: HttpsCallableOptions(
            timeout: const Duration(seconds: 60),
          ),
        );
        await callable.call(<String, dynamic>{
          'vagaId': widget.vagaId,
          'cargo': widget.cargo,
          'empresa': widget.empresa,
          'emailEmpresa': widget.emailEmpresa,
          'nomeCompleto': _nomeCtrl.text.trim(),
          'telefone': _telefoneCtrl.text.trim(),
          'urlCurriculo': urlCurriculo,
          'nomeArquivo': _nomeArquivo ?? 'curriculo.$ext',
        });
      } catch (_) {
        // E-mail best-effort; candidatura já salva no Firestore.
      }

      if (!mounted) return;
      Navigator.pop(context);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _mostrarSucessoEnvio(context);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _enviando = false);
      _mostrarErroEnvio(
        context,
        'Não foi possível enviar sua candidatura.\n$e',
      );
    } finally {
      if (mounted && _enviando) setState(() => _enviando = false);
    }
  }

  String _mimeType(String ext) {
    switch (ext.toLowerCase()) {
      case 'pdf':
        return 'application/pdf';
      case 'doc':
        return 'application/msword';
      case 'docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      default:
        return 'application/octet-stream';
    }
  }

  void _mostrarSucessoEnvio(BuildContext ctx) {
    showGeneralDialog(
      context: ctx,
      barrierDismissible: true,
      barrierLabel: 'fechar',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 350),
      pageBuilder: (_, __, ___) => const SizedBox.shrink(),
      transitionBuilder: (dCtx, anim, _, __) {
        final curved =
            CurvedAnimation(parent: anim, curve: Curves.easeOutBack);
        return ScaleTransition(
          scale: curved,
          child: FadeTransition(
            opacity: anim,
            child: Center(
              child: Material(
                color: Colors.transparent,
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 32),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 28, vertical: 36),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: _verdeVaga.withValues(alpha: 0.15),
                        blurRadius: 40,
                        spreadRadius: 4,
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: [
                              Colors.green.shade400,
                              Colors.green.shade700,
                            ],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: _verdeVaga.withValues(alpha: 0.3),
                              blurRadius: 20,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.check_rounded,
                          size: 44,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        'Candidatura Enviada!',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF2E7D32),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Seu currículo foi enviado para a empresa.\nBoa sorte!',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey.shade600,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton(
                          onPressed: () => Navigator.of(dCtx).pop(),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _verdeVaga,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: const Text(
                            'Fechar',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _mostrarErroEnvio(BuildContext ctx, String mensagem) {
    showGeneralDialog(
      context: ctx,
      barrierDismissible: true,
      barrierLabel: 'fechar',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 350),
      pageBuilder: (_, __, ___) => const SizedBox.shrink(),
      transitionBuilder: (dCtx, anim, _, __) {
        final curved =
            CurvedAnimation(parent: anim, curve: Curves.easeOutBack);
        return ScaleTransition(
          scale: curved,
          child: FadeTransition(
            opacity: anim,
            child: Center(
              child: Material(
                color: Colors.transparent,
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 32),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 28, vertical: 36),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.red.withValues(alpha: 0.15),
                        blurRadius: 40,
                        spreadRadius: 4,
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: [
                              Colors.red.shade400,
                              Colors.red.shade700,
                            ],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.red.withValues(alpha: 0.3),
                              blurRadius: 20,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.close_rounded,
                          size: 44,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        'Envio não realizado',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFFC62828),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        mensagem,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey.shade600,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton(
                          onPressed: () => Navigator.of(dCtx).pop(),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFC62828),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: const Text(
                            'Tentar novamente',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return DraggableScrollableSheet(
      initialChildSize: 0.82,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (_, controller) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            Expanded(
              child: Form(
                key: _formKey,
                child: ListView(
                  controller: controller,
                  padding: EdgeInsets.fromLTRB(24, 20, 24, 24 + bottomInset),
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: _roxo.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(Icons.description_outlined,
                              color: _roxo.withValues(alpha: 0.7), size: 22),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Candidatura',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF1A1A2E),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                widget.cargo,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.grey.shade600,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      widget.empresa,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade500,
                      ),
                    ),
                    const SizedBox(height: 24),
                    TextFormField(
                      controller: _nomeCtrl,
                      textCapitalization: TextCapitalization.words,
                      validator: (v) =>
                          (v == null || v.trim().length < 3) ? 'Informe seu nome completo' : null,
                      decoration: _inputDeco(
                        label: 'Nome completo',
                        icon: Icons.person_outlined,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _telefoneCtrl,
                      keyboardType: TextInputType.phone,
                      validator: (v) =>
                          (v == null || v.trim().length < 8) ? 'Informe um telefone válido' : null,
                      decoration: _inputDeco(
                        label: 'Telefone',
                        icon: Icons.phone_outlined,
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Currículo',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1A1A2E),
                      ),
                    ),
                    const SizedBox(height: 10),
                    InkWell(
                      onTap: _escolherCurriculo,
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 20,
                        ),
                        decoration: BoxDecoration(
                          color: _nomeArquivo != null
                              ? _verdeVaga.withValues(alpha: 0.05)
                              : const Color(0xFFFAF9FC),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: _nomeArquivo != null
                                ? _verdeVaga.withValues(alpha: 0.3)
                                : const Color(0xFFDDD8E4),
                            width: 1.5,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              _nomeArquivo != null
                                  ? Icons.check_circle_rounded
                                  : Icons.upload_file_rounded,
                              color: _nomeArquivo != null
                                  ? _verdeVaga
                                  : _roxo.withValues(alpha: 0.5),
                              size: 28,
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _nomeArquivo ?? 'Anexar currículo',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: _nomeArquivo != null
                                          ? _verdeVaga
                                          : const Color(0xFF666666),
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    _nomeArquivo != null
                                        ? 'Toque para trocar o arquivo'
                                        : 'PDF, DOC ou DOCX',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (_nomeArquivo != null)
                              IconButton(
                                icon: Icon(Icons.close,
                                    size: 20, color: Colors.grey.shade500),
                                onPressed: () => setState(() {
                                  _nomeArquivo = null;
                                  _bytesArquivo = null;
                                }),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),
                    Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 52,
                            child: OutlinedButton(
                              onPressed:
                                  _enviando ? null : () => Navigator.pop(context),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.grey.shade700,
                                side: BorderSide(color: Colors.grey.shade300),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              child: const Text(
                                'Cancelar',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          flex: 2,
                          child: SizedBox(
                            height: 52,
                            child: ElevatedButton.icon(
                              onPressed: _enviando ? null : _enviar,
                              icon: _enviando
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(Icons.send_rounded, size: 18),
                              label: Text(
                                _enviando ? 'Enviando...' : 'Enviar',
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _verdeVaga,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                elevation: 2,
                                shadowColor: _verdeVaga.withValues(alpha: 0.3),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _inputDeco({required String label, required IconData icon}) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, size: 20),
      filled: true,
      fillColor: const Color(0xFFFAF9FC),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFDDD8E4)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFDDD8E4)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _roxo, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    );
  }
}
