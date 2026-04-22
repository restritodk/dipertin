// Arquivo: lib/screens/entregador/configuracoes/gerenciar_veiculos_screen.dart
//
// Implementação definitiva (Fase 3): lista de veículos com seed do legado,
// alternância de veículo ativo e CRUD.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'editar_veiculo_screen.dart';

const Color _roxo = Color(0xFF6A1B9A);
const Color _laranja = Color(0xFFFF8F00);

class GerenciarVeiculosScreen extends StatefulWidget {
  const GerenciarVeiculosScreen({super.key});

  @override
  State<GerenciarVeiculosScreen> createState() =>
      _GerenciarVeiculosScreenState();
}

class _GerenciarVeiculosScreenState extends State<GerenciarVeiculosScreen> {
  final _fs = FirebaseFirestore.instance;
  bool _seedVerificado = false;

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  CollectionReference<Map<String, dynamic>>? get _veiculosRef {
    final uid = _uid;
    if (uid == null) return null;
    return _fs.collection('users').doc(uid).collection('veiculos');
  }

  @override
  void initState() {
    super.initState();
    _garantirSeed();
  }

  /// Se o entregador não tem veículos cadastrados mas tem `veiculoTipo` legado,
  /// semeia o primeiro doc a partir dele (placa, modelo e CRLV também).
  Future<void> _garantirSeed() async {
    final uid = _uid;
    if (uid == null) return;
    try {
      final userDoc = await _fs.collection('users').doc(uid).get();
      final d = userDoc.data() ?? {};
      final tipoLegado = (d['veiculoTipo'] ?? '').toString().trim();
      final placaLegada = (d['placa_veiculo'] ?? d['placa'] ?? '')
          .toString()
          .trim()
          .toUpperCase();
      final modeloLegado = (d['veiculoModelo'] ?? d['modelo_veiculo'] ?? '')
          .toString()
          .trim();
      final urlCrlvLegado = (d['url_crlv'] ?? '').toString().trim();
      final veiculoAtivoId = (d['veiculo_ativo_id'] ?? '').toString().trim();
      final veiculos = await _veiculosRef!.limit(1).get();
      if (veiculos.docs.isEmpty && tipoLegado.isNotEmpty) {
        final ref = _veiculosRef!.doc();
        await ref.set({
          'tipo': _normalizarTipo(tipoLegado),
          'modelo': modeloLegado,
          'placa': placaLegada,
          'ativo': true,
          'seed_from_legacy': true,
          'criado_em': FieldValue.serverTimestamp(),
          'atualizado_em': FieldValue.serverTimestamp(),
        });
        if (veiculoAtivoId.isEmpty) {
          await _fs.collection('users').doc(uid).set({
            'veiculo_ativo_id': ref.id,
          }, SetOptions(merge: true));
        }
        if (urlCrlvLegado.isNotEmpty) {
          await ref.collection('documentos').doc('crlv').set({
            'url': urlCrlvLegado,
            'status': 'pendente',
            'origem': 'seed_cadastro_antigo',
            'atualizado_em': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        }
      }
    } catch (e) {
      debugPrint('[Veiculos] seed falhou: $e');
    } finally {
      if (mounted) setState(() => _seedVerificado = true);
    }
  }

  String _normalizarTipo(String raw) {
    final v = raw.toLowerCase().trim();
    if (v.startsWith('mot')) return 'moto';
    if (v.startsWith('car')) return 'carro';
    if (v.startsWith('bic') || v.startsWith('bik')) return 'bike';
    return v;
  }

  Future<void> _ativar(String veiculoId) async {
    final uid = _uid;
    if (uid == null) return;
    try {
      final snaps = await _veiculosRef!.get();
      final batch = _fs.batch();
      String? tipoAtivo;
      for (final d in snaps.docs) {
        final ativo = d.id == veiculoId;
        batch.update(d.reference, {
          'ativo': ativo,
          'atualizado_em': FieldValue.serverTimestamp(),
        });
        if (ativo) {
          tipoAtivo = (d.data()['tipo'] ?? '').toString();
        }
      }
      batch.set(_fs.collection('users').doc(uid), {
        'veiculo_ativo_id': veiculoId,
        if (tipoAtivo != null && tipoAtivo.isNotEmpty)
          'veiculoTipo': _tipoParaPainel(tipoAtivo),
      }, SetOptions(merge: true));
      await batch.commit();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Veículo ativo atualizado.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro: $e')),
      );
    }
  }

  String _tipoParaPainel(String codigo) {
    switch (codigo.toLowerCase()) {
      case 'moto':
        return 'Moto';
      case 'carro':
        return 'Carro';
      case 'bike':
        return 'Bicicleta';
      default:
        return codigo;
    }
  }

  @override
  Widget build(BuildContext context) {
    final ref = _veiculosRef;
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F7),
      appBar: AppBar(
        title: const Text(
          'Meus veículos',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: _roxo,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const EditarVeiculoScreen(),
            ),
          );
        },
        backgroundColor: _laranja,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Adicionar veículo'),
      ),
      body: ref == null
          ? const Center(child: Text('Você precisa estar autenticado.'))
          : !_seedVerificado
              ? const Center(child: CircularProgressIndicator(color: _laranja))
              : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: ref.orderBy('criado_em').snapshots(),
                  builder: (context, snap) {
                    if (snap.connectionState == ConnectionState.waiting) {
                      return const Center(
                        child: CircularProgressIndicator(color: _laranja),
                      );
                    }
                    final docs = snap.data?.docs ?? [];
                    if (docs.isEmpty) {
                      return const _VazioEstado();
                    }
                    return ListView.builder(
                      padding: const EdgeInsets.only(
                        top: 12,
                        bottom: 96,
                      ),
                      itemCount: docs.length,
                      itemBuilder: (context, i) {
                        final d = docs[i];
                        final data = d.data();
                        final ativo = data['ativo'] == true;
                        return _CardVeiculo(
                          id: d.id,
                          tipo: (data['tipo'] ?? '').toString(),
                          modelo: (data['modelo'] ?? '').toString(),
                          placa: (data['placa'] ?? '').toString(),
                          ativo: ativo,
                          onEditar: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) =>
                                    EditarVeiculoScreen(veiculoId: d.id),
                              ),
                            );
                          },
                          onAtivar: ativo ? null : () => _ativar(d.id),
                        );
                      },
                    );
                  },
                ),
    );
  }
}

class _CardVeiculo extends StatelessWidget {
  final String id;
  final String tipo;
  final String modelo;
  final String placa;
  final bool ativo;
  final VoidCallback onEditar;
  final VoidCallback? onAtivar;

  const _CardVeiculo({
    required this.id,
    required this.tipo,
    required this.modelo,
    required this.placa,
    required this.ativo,
    required this.onEditar,
    required this.onAtivar,
  });

  IconData get _icone {
    switch (tipo) {
      case 'moto':
        return Icons.two_wheeler_rounded;
      case 'carro':
        return Icons.directions_car_rounded;
      case 'bike':
        return Icons.directions_bike_rounded;
      default:
        return Icons.local_shipping_rounded;
    }
  }

  String get _rotuloTipo {
    switch (tipo) {
      case 'moto':
        return 'Moto';
      case 'carro':
        return 'Carro';
      case 'bike':
        return 'Bike';
      default:
        return tipo;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            ListTile(
              leading: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: _roxo.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(_icone, color: _roxo),
              ),
              title: Row(
                children: [
                  Text(
                    _rotuloTipo,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  if (ativo)
                    Container(
                      margin: const EdgeInsets.only(left: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text(
                        'ATIVO',
                        style: TextStyle(
                          color: Colors.green,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),
              subtitle: Text(
                [
                  if (modelo.isNotEmpty) modelo,
                  if (placa.isNotEmpty) placa.toUpperCase(),
                  if (modelo.isEmpty && placa.isEmpty)
                    'Complete modelo e placa',
                ].join(' • '),
                style: const TextStyle(color: Colors.black54, fontSize: 12),
              ),
              trailing: IconButton(
                icon: const Icon(Icons.edit_outlined, color: _roxo),
                onPressed: onEditar,
              ),
            ),
            if (!ativo)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.check_circle_outline),
                    onPressed: onAtivar,
                    label: const Text('Definir como ativo'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _laranja,
                      side: const BorderSide(color: _laranja),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _VazioEstado extends StatelessWidget {
  const _VazioEstado();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.two_wheeler_rounded,
              size: 56,
              color: _roxo.withValues(alpha: 0.35),
            ),
            const SizedBox(height: 12),
            const Text(
              'Nenhum veículo cadastrado',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: _roxo,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Toque em "Adicionar veículo" para começar.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black54, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}
