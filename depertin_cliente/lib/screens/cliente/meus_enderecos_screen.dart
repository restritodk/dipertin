// Arquivo: lib/screens/cliente/meus_enderecos_screen.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:depertin_cliente/screens/cliente/address_screen.dart';
import 'package:depertin_cliente/utils/safe_area_insets.dart';

const Color _diPertinRoxo = Color(0xFF6A1B9A);
const Color _diPertinLaranja = Color(0xFFFF8F00);
const Color _fundoTela = Color(0xFFF5F4F8);

class MeusEnderecosScreen extends StatefulWidget {
  const MeusEnderecosScreen({super.key});

  @override
  State<MeusEnderecosScreen> createState() => _MeusEnderecosScreenState();
}

class _MeusEnderecosScreenState extends State<MeusEnderecosScreen> {
  static String _formatarEnderecoMap(Map<String, dynamic> m) {
    final rua = (m['rua'] ?? '').toString().trim();
    final num = (m['numero'] ?? '').toString().trim();
    final bairro = (m['bairro'] ?? '').toString().trim();
    final cidade = (m['cidade'] ?? '').toString().trim();
    final estado = (m['estado'] ?? m['uf'] ?? '').toString().trim();
    final comp = (m['complemento'] ?? '').toString().trim();
    final buf = StringBuffer();
    if (rua.isNotEmpty) {
      buf.write(rua);
      if (num.isNotEmpty) buf.write(', $num');
    }
    if (bairro.isNotEmpty) {
      if (buf.isNotEmpty) buf.write(' — ');
      buf.write(bairro);
    }
    if (cidade.isNotEmpty) {
      if (buf.isNotEmpty) buf.write(', ');
      buf.write(cidade);
      if (estado.isNotEmpty) buf.write(' - $estado');
    }
    if (comp.isNotEmpty) {
      if (buf.isNotEmpty) buf.write('\n');
      buf.write(comp);
    }
    final s = buf.toString().trim();
    return s.isEmpty ? 'Endereço sem detalhes' : s;
  }

  /// Chave estável para comparar endereços (evita duplicata na lista vs padrão).
  static String _chaveEndereco(Map<String, dynamic> m) {
    String n(String? v) => (v ?? '').toString().trim().toLowerCase();
    return '${n(m['rua'])}|${n(m['numero'])}|${n(m['bairro'])}|${n(m['cidade'])}|'
        '${n(m['estado'] ?? m['uf'])}|${n(m['complemento'])}';
  }

  static bool _mesmoEndereco(
    Map<String, dynamic> a,
    Map<String, dynamic> b,
  ) {
    return _chaveEndereco(a) == _chaveEndereco(b);
  }

  Future<void> _abrirNovoEndereco() async {
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => const AddressScreen(
          modoCadastroLista: true,
        ),
      ),
    );
  }

  Future<void> _abrirEditarPadrao(Map<String, dynamic> padrao) async {
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => AddressScreen(
          modoCadastroLista: true,
          dadosIniciais: Map<String, dynamic>.from(padrao),
          apenasAtualizarPerfilPadrao: true,
        ),
      ),
    );
  }

  Future<void> _abrirEditarDocumento(
    String docId,
    Map<String, dynamic> dados, {
    required bool ehPadraoAtual,
  }) async {
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => AddressScreen(
          modoCadastroLista: true,
          enderecoDocumentId: docId,
          dadosIniciais: Map<String, dynamic>.from(dados),
          tornarPadraoInicial: ehPadraoAtual,
        ),
      ),
    );
  }

  Future<void> _confirmarRemoverPadrao(String uid) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Remover endereço padrão?'),
        content: const Text(
          'O endereço principal deixará de ser usado nas entregas até você definir outro.',
          style: TextStyle(height: 1.35),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remover'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'endereco_entrega_padrao': FieldValue.delete(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Endereço padrão removido.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Não foi possível remover: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _confirmarExcluirDocumento(
    String uid,
    String docId,
    Map<String, dynamic> dados,
    Map<String, dynamic>? padrao,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Excluir endereço?'),
        content: const Text(
          'Esta ação não pode ser desfeita.',
          style: TextStyle(height: 1.35),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('enderecos')
          .doc(docId)
          .delete();

      if (padrao != null && _mesmoEndereco(dados, padrao)) {
        await FirebaseFirestore.instance.collection('users').doc(uid).update({
          'endereco_entrega_padrao': FieldValue.delete(),
        });
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Endereço excluído.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Não foi possível excluir: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  /// Define o endereço [dados] como principal (campo `endereco_entrega_padrao`).
  /// Preserva o principal anterior na lista, caso ele só existisse no perfil.
  Future<void> _definirComoPrincipal(
    String uid,
    Map<String, dynamic> dados, {
    required List<Map<String, dynamic>> docsAtuais,
    Map<String, dynamic>? padraoAtual,
  }) async {
    try {
      final docRef = FirebaseFirestore.instance.collection('users').doc(uid);

      final precisaPreservarAnterior = padraoAtual != null &&
          (padraoAtual['rua'] ?? '').toString().trim().isNotEmpty &&
          !_mesmoEndereco(padraoAtual, dados) &&
          !docsAtuais.any((m) => _mesmoEndereco(m, padraoAtual));

      if (precisaPreservarAnterior) {
        await docRef.collection('enderecos').add({
          'cep': (padraoAtual['cep'] ?? '').toString().trim(),
          'rua': (padraoAtual['rua'] ?? '').toString().trim(),
          'numero': (padraoAtual['numero'] ?? '').toString().trim(),
          'bairro': (padraoAtual['bairro'] ?? '').toString().trim(),
          'cidade':
              (padraoAtual['cidade'] ?? '').toString().trim().toLowerCase(),
          'estado': (padraoAtual['estado'] ?? padraoAtual['uf'] ?? '')
              .toString()
              .trim()
              .toUpperCase(),
          'complemento': (padraoAtual['complemento'] ?? '').toString().trim(),
          'criado_em': FieldValue.serverTimestamp(),
          'data_atualizacao': FieldValue.serverTimestamp(),
        });
      }

      final estadoUf = (dados['estado'] ?? dados['uf'] ?? '')
          .toString()
          .trim()
          .toUpperCase();
      final cidade = (dados['cidade'] ?? '').toString().trim();

      final Map<String, dynamic> mapaPadrao = {
        'cep': (dados['cep'] ?? '').toString().trim(),
        'rua': (dados['rua'] ?? '').toString().trim(),
        'numero': (dados['numero'] ?? '').toString().trim(),
        'bairro': (dados['bairro'] ?? '').toString().trim(),
        'cidade': cidade.toLowerCase(),
        'estado': estadoUf,
        'complemento': (dados['complemento'] ?? '').toString().trim(),
        'data_atualizacao': FieldValue.serverTimestamp(),
      };

      // Só entrega padrão — não sobrescreve cidade/UF do perfil (vitrine = GPS).
      await docRef.update({
        'endereco_entrega_padrao': mapaPadrao,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Endereço definido como principal.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Não foi possível definir como principal: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Widget _cardEndereco({
    required String titulo,
    required String subtitulo,
    required IconData icone,
    required bool destaque,
    VoidCallback? onTap,
    VoidCallback? onTornarPrincipal,
    VoidCallback? onExcluir,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: destaque
              ? _diPertinLaranja.withValues(alpha: 0.45)
              : const Color(0xFFE8E6ED),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: (destaque ? _diPertinLaranja : _diPertinRoxo)
                        .withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    icone,
                    color: destaque ? _diPertinLaranja : _diPertinRoxo,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              titulo,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 15,
                                color: Color(0xFF1A1A2E),
                              ),
                            ),
                          ),
                          if (destaque) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: _diPertinLaranja.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text(
                                'Principal',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: _diPertinLaranja,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        subtitulo,
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.4,
                          color: Colors.grey.shade800,
                        ),
                      ),
                    ],
                  ),
                ),
                if (onTornarPrincipal != null || onExcluir != null)
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (onTornarPrincipal != null)
                        IconButton(
                          tooltip: 'Tornar principal',
                          onPressed: onTornarPrincipal,
                          icon: const Icon(Icons.star_border_rounded),
                          color: _diPertinLaranja,
                        ),
                      if (onExcluir != null)
                        IconButton(
                          tooltip: 'Excluir',
                          onPressed: onExcluir,
                          icon: const Icon(Icons.delete_outline_rounded),
                          color: Colors.red.shade700,
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final User? user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: _fundoTela,
      appBar: AppBar(
        title: const Text(
          'Meus endereços',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            letterSpacing: -0.2,
          ),
        ),
        backgroundColor: _diPertinRoxo,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      floatingActionButton: user == null
          ? null
          : FloatingActionButton.extended(
              onPressed: _abrirNovoEndereco,
              backgroundColor: _diPertinLaranja,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add_rounded),
              label: const Text(
                'Adicionar endereço',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
      body: user == null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Faça login para ver seus endereços.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey.shade700, height: 1.4),
                ),
              ),
            )
          : StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .doc(user.uid)
                  .snapshots(),
              builder: (context, userSnap) {
                if (userSnap.connectionState == ConnectionState.waiting &&
                    !userSnap.hasData) {
                  return const Center(
                    child: CircularProgressIndicator(color: _diPertinRoxo),
                  );
                }

                Map<String, dynamic>? padrao;
                if (userSnap.hasData &&
                    userSnap.data!.exists &&
                    userSnap.data!.data() != null) {
                  final d = userSnap.data!.data() as Map<String, dynamic>;
                  final ep = d['endereco_entrega_padrao'];
                  if (ep is Map) {
                    padrao = Map<String, dynamic>.from(ep);
                  }
                }

                return StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('users')
                      .doc(user.uid)
                      .collection('enderecos')
                      .orderBy('criado_em', descending: true)
                      .snapshots(),
                  builder: (context, endSnap) {
                    if (endSnap.hasError) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            'Erro ao carregar lista: ${endSnap.error}',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      );
                    }
                    if (endSnap.connectionState == ConnectionState.waiting &&
                        !endSnap.hasData) {
                      return const Center(
                        child: CircularProgressIndicator(color: _diPertinRoxo),
                      );
                    }

                    final docs = endSnap.data?.docs ?? [];
                    final temPadrao = padrao != null &&
                        (padrao['rua'] ?? '').toString().trim().isNotEmpty;
                    final Map<String, dynamic>? enderecoPadrao =
                        temPadrao ? padrao : null;

                    final docsData = docs
                        .map((d) => (
                              id: d.id,
                              data: Map<String, dynamic>.from(d.data()! as Map),
                            ))
                        .toList();

                    // Índice do doc que corresponde ao principal (se houver).
                    int idxPrincipal = -1;
                    if (enderecoPadrao != null) {
                      for (var i = 0; i < docsData.length; i++) {
                        if (_mesmoEndereco(docsData[i].data, enderecoPadrao)) {
                          idxPrincipal = i;
                          break;
                        }
                      }
                    }

                    final List<
                        ({
                          String? id,
                          Map<String, dynamic> data,
                          bool principal
                        })> itens = [];
                    // Principal "legado": existe só no perfil, sem doc na lista.
                    if (enderecoPadrao != null && idxPrincipal == -1) {
                      itens.add((id: null, data: enderecoPadrao, principal: true));
                    }
                    for (var i = 0; i < docsData.length; i++) {
                      itens.add((
                        id: docsData[i].id,
                        data: docsData[i].data,
                        principal: i == idxPrincipal,
                      ));
                    }
                    // Principal sempre primeiro.
                    itens.sort(
                      (a, b) => (b.principal ? 1 : 0) - (a.principal ? 1 : 0),
                    );

                    final vazio = itens.isEmpty;

                    if (vazio) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.location_off_outlined,
                                size: 72,
                                color: _diPertinRoxo.withValues(alpha: 0.35),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Nenhum endereço salvo',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.grey.shade800,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Toque em “Adicionar endereço” para cadastrar onde entregamos seus pedidos.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.grey.shade600,
                                  height: 1.45,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }

                    return ListView(
                      padding: diPertinScrollPadding(
                        context,
                        left: 16,
                        right: 16,
                        top: 16,
                        extraBottom: 24,
                      ),
                      children: [
                        Text(
                          'Endereços cadastrados',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Colors.grey.shade800,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Toque em um endereço para editar. Use a estrela para definir o principal (usado nas entregas) e a lixeira para excluir.',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade600,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 16),
                        ...itens.map((item) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _cardEndereco(
                              titulo: item.principal
                                  ? 'Padrão de entrega'
                                  : 'Endereço',
                              subtitulo: _formatarEnderecoMap(item.data),
                              icone: item.principal
                                  ? Icons.star_rounded
                                  : Icons.place_outlined,
                              destaque: item.principal,
                              onTap: item.id == null
                                  ? () => _abrirEditarPadrao(item.data)
                                  : () => _abrirEditarDocumento(
                                        item.id!,
                                        item.data,
                                        ehPadraoAtual: item.principal,
                                      ),
                              // Só endereços não-principais podem virar principal.
                              onTornarPrincipal: item.principal
                                  ? null
                                  : () => _definirComoPrincipal(
                                        user.uid,
                                        item.data,
                                        docsAtuais: docsData
                                            .map((e) => e.data)
                                            .toList(),
                                        padraoAtual: enderecoPadrao,
                                      ),
                              onExcluir: item.id == null
                                  ? () => _confirmarRemoverPadrao(user.uid)
                                  : () => _confirmarExcluirDocumento(
                                        user.uid,
                                        item.id!,
                                        item.data,
                                        enderecoPadrao,
                                      ),
                            ),
                          );
                        }),
                      ],
                    );
                  },
                );
              },
            ),
    );
  }
}
