import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

const Color _roxo = Color(0xFF6A1B9A);
const Color _laranja = Color(0xFFFF8F00);

/// Busca o role do usuário logado no Firestore.
Future<String> _obterRoleUsuario() async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return 'cliente';
  try {
    final snap =
        await FirebaseFirestore.instance.collection('users').doc(uid).get();
    if (!snap.exists) return 'cliente';
    final d = snap.data() ?? {};
    return (d['role'] ?? d['tipoUsuario'] ?? 'cliente').toString().toLowerCase();
  } catch (_) {
    return 'cliente';
  }
}

/// Filtra se o comunicado é visível para o role informado.
bool _comunicadoVisivelParaRole(Map<String, dynamic> d, String role) {
  final publico = (d['publico_alvo'] ?? 'todos').toString();
  if (publico == 'todos') return true;
  return publico == role;
}

/// Verifica se o comunicado está ativo e não expirado.
bool _comunicadoValido(Map<String, dynamic> d) {
  if (d['ativo'] != true) return false;
  final exp = d['data_expiracao'] as Timestamp?;
  if (exp != null && exp.toDate().isBefore(DateTime.now())) return false;
  return true;
}

class ComunicadosAppScreen extends StatefulWidget {
  const ComunicadosAppScreen({super.key});

  @override
  State<ComunicadosAppScreen> createState() => _ComunicadosAppScreenState();
}

class _ComunicadosAppScreenState extends State<ComunicadosAppScreen> {
  Set<String> _lidos = {};
  String _role = 'cliente';
  bool _roleCarregado = false;

  @override
  void initState() {
    super.initState();
    _carregarDados();
  }

  Future<void> _carregarDados() async {
    final role = await _obterRoleUsuario();

    final prefs = await SharedPreferences.getInstance();
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final lista = prefs.getStringList('comunicados_lidos_$uid') ?? [];

    if (mounted) {
      setState(() {
        _role = role;
        _lidos = lista.toSet();
        _roleCarregado = true;
      });
    }
  }

  Future<void> _marcarComoLido(String docId) async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    _lidos.add(docId);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('comunicados_lidos_$uid', _lidos.toList());
    if (mounted) setState(() {});
  }

  IconData _icone(String tipo) {
    switch (tipo) {
      case 'aviso':
        return Icons.warning_amber_rounded;
      case 'promo':
        return Icons.local_offer_rounded;
      case 'manutencao':
        return Icons.build_rounded;
      default:
        return Icons.info_rounded;
    }
  }

  Color _cor(String tipo) {
    switch (tipo) {
      case 'aviso':
        return const Color(0xFFB45309);
      case 'promo':
        return const Color(0xFF15803D);
      case 'manutencao':
        return const Color(0xFFB91C1C);
      default:
        return const Color(0xFF1D4ED8);
    }
  }

  String _labelTipo(String tipo) {
    switch (tipo) {
      case 'aviso':
        return 'Aviso';
      case 'promo':
        return 'Promoção';
      case 'manutencao':
        return 'Manutenção';
      default:
        return 'Informação';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F3FA),
      appBar: AppBar(
        backgroundColor: _roxo,
        foregroundColor: Colors.white,
        title: const Text(
          'Comunicados',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        elevation: 0,
      ),
      body: !_roleCarregado
          ? const Center(child: CircularProgressIndicator(color: _roxo))
          : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('comunicados')
                  .snapshots(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting &&
                    !snap.hasData) {
                  return const Center(
                      child: CircularProgressIndicator(color: _roxo));
                }

                final docs = (snap.data?.docs ?? []).where((doc) {
                  final d = doc.data();
                  if (!_comunicadoValido(d)) return false;
                  return _comunicadoVisivelParaRole(d, _role);
                }).toList();

                docs.sort((a, b) {
                  final tsA = a.data()['data_criacao'] as Timestamp?;
                  final tsB = b.data()['data_criacao'] as Timestamp?;
                  if (tsA == null && tsB == null) return 0;
                  if (tsA == null) return 1;
                  if (tsB == null) return -1;
                  return tsB.compareTo(tsA);
                });

                if (docs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.mark_email_read_rounded,
                            size: 56, color: _roxo.withValues(alpha: 0.3)),
                        const SizedBox(height: 16),
                        Text(
                          'Nenhum comunicado no momento',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Você será avisado quando houver novidades',
                          style: TextStyle(
                              fontSize: 13, color: Colors.grey.shade500),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    final doc = docs[i];
                    final d = doc.data();
                    final tipo = (d['tipo'] ?? 'info') as String;
                    final titulo = (d['titulo'] ?? '') as String;
                    final mensagem = (d['mensagem'] ?? '') as String;
                    final ts = d['data_criacao'] as Timestamp?;
                    final data = ts != null
                        ? DateFormat('dd/MM/yyyy').format(ts.toDate())
                        : '';
                    final lido = _lidos.contains(doc.id);
                    final cor = _cor(tipo);

                    return GestureDetector(
                      onTap: () {
                        if (!lido) _marcarComoLido(doc.id);
                        _abrirDetalhe(context, tipo, titulo, mensagem, data);
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: lido
                                ? Colors.grey.shade200
                                : cor.withValues(alpha: 0.4),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.04),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: cor.withValues(
                                      alpha: lido ? 0.06 : 0.12),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(_icone(tipo),
                                    color: lido ? Colors.grey : cor, size: 22),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        if (!lido)
                                          Container(
                                            width: 8,
                                            height: 8,
                                            margin: const EdgeInsets.only(
                                                right: 6),
                                            decoration: const BoxDecoration(
                                              color: _laranja,
                                              shape: BoxShape.circle,
                                            ),
                                          ),
                                        Expanded(
                                          child: Text(
                                            titulo,
                                            style: TextStyle(
                                              fontWeight: lido
                                                  ? FontWeight.w600
                                                  : FontWeight.w700,
                                              fontSize: 15,
                                              color: lido
                                                  ? Colors.grey.shade600
                                                  : const Color(0xFF1A1A2E),
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 3),
                                          decoration: BoxDecoration(
                                            color:
                                                cor.withValues(alpha: 0.1),
                                            borderRadius:
                                                BorderRadius.circular(20),
                                          ),
                                          child: Text(
                                            _labelTipo(tipo),
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w700,
                                              color: cor,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      mensagem,
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: Colors.grey.shade600,
                                        height: 1.4,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      data,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey.shade400,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
    );
  }

  void _abrirDetalhe(
    BuildContext context,
    String tipo,
    String titulo,
    String mensagem,
    String data,
  ) {
    final cor = _cor(tipo);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(ctx).height * 0.7,
        ),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 10),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: cor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(_icone(tipo), color: cor, size: 26),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          titulo,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1A1A2E),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${_labelTipo(tipo)} • $data',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Divider(height: 1, color: Colors.grey.shade200),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Text(
                  mensagem,
                  style: const TextStyle(
                    fontSize: 15,
                    color: Color(0xFF333333),
                    height: 1.6,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

/// Conta comunicados não lidos para exibir badge.
Future<int> contarComunicadosNaoLidos() async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return 0;

  final role = await _obterRoleUsuario();
  final prefs = await SharedPreferences.getInstance();
  final lidos = (prefs.getStringList('comunicados_lidos_$uid') ?? []).toSet();

  final snap = await FirebaseFirestore.instance
      .collection('comunicados')
      .get();

  int count = 0;
  for (final doc in snap.docs) {
    final d = doc.data();
    if (!_comunicadoValido(d)) continue;
    if (!_comunicadoVisivelParaRole(d, role)) continue;
    if (!lidos.contains(doc.id)) count++;
  }
  return count;
}

/// Modal que exibe comunicados não lidos ao abrir o app.
Future<void> mostrarComunicadosNaoLidos(BuildContext context) async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return;

  final role = await _obterRoleUsuario();
  final prefs = await SharedPreferences.getInstance();
  final lidos = (prefs.getStringList('comunicados_lidos_$uid') ?? []).toSet();

  final snap = await FirebaseFirestore.instance
      .collection('comunicados')
      .get();

  final naoLidos = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
  for (final doc in snap.docs) {
    final d = doc.data();
    if (!_comunicadoValido(d)) continue;
    if (!_comunicadoVisivelParaRole(d, role)) continue;
    if (!lidos.contains(doc.id)) naoLidos.add(doc);
  }

  naoLidos.sort((a, b) {
    final tsA = a.data()['data_criacao'] as Timestamp?;
    final tsB = b.data()['data_criacao'] as Timestamp?;
    if (tsA == null && tsB == null) return 0;
    if (tsA == null) return 1;
    if (tsB == null) return -1;
    return tsB.compareTo(tsA);
  });

  if (naoLidos.isEmpty || !context.mounted) return;

  IconData icone(String tipo) {
    switch (tipo) {
      case 'aviso':
        return Icons.warning_amber_rounded;
      case 'promo':
        return Icons.local_offer_rounded;
      case 'manutencao':
        return Icons.build_rounded;
      default:
        return Icons.info_rounded;
    }
  }

  Color cor(String tipo) {
    switch (tipo) {
      case 'aviso':
        return const Color(0xFFB45309);
      case 'promo':
        return const Color(0xFF15803D);
      case 'manutencao':
        return const Color(0xFFB91C1C);
      default:
        return const Color(0xFF1D4ED8);
    }
  }

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    isDismissible: true,
    builder: (ctx) {
      return Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(ctx).height * 0.65,
        ),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 10),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _roxo.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.campaign_rounded,
                        color: _roxo, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Novos comunicados',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1A1A2E),
                          ),
                        ),
                        Text(
                          '${naoLidos.length} ${naoLidos.length == 1 ? 'comunicado não lido' : 'comunicados não lidos'}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text(
                      'Fechar',
                      style: TextStyle(
                        color: _roxo,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: Colors.grey.shade200),
            Flexible(
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 8),
                shrinkWrap: true,
                itemCount: naoLidos.length,
                separatorBuilder: (_, __) => Divider(
                    height: 1,
                    indent: 16,
                    endIndent: 16,
                    color: Colors.grey.shade100),
                itemBuilder: (_, i) {
                  final d = naoLidos[i].data();
                  final tipo = (d['tipo'] ?? 'info') as String;
                  final titulo = (d['titulo'] ?? '') as String;
                  final mensagem = (d['mensagem'] ?? '') as String;
                  final c = cor(tipo);

                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 4),
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: c.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(icone(tipo), color: c, size: 20),
                    ),
                    title: Text(
                      titulo,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: Color(0xFF1A1A2E),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      mensagem,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      );
    },
  );

  final novosLidos = lidos.toList();
  for (final doc in naoLidos) {
    novosLidos.add(doc.id);
  }
  await prefs.setStringList('comunicados_lidos_$uid', novosLidos);
}
