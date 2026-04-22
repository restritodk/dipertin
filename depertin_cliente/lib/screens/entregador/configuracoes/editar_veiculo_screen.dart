// Arquivo: lib/screens/entregador/configuracoes/editar_veiculo_screen.dart

import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../services/permissoes_app_service.dart';

const Color _roxo = Color(0xFF6A1B9A);
const Color _laranja = Color(0xFFFF8F00);

class EditarVeiculoScreen extends StatefulWidget {
  final String? veiculoId;

  const EditarVeiculoScreen({super.key, this.veiculoId});

  @override
  State<EditarVeiculoScreen> createState() => _EditarVeiculoScreenState();
}

class _EditarVeiculoScreenState extends State<EditarVeiculoScreen> {
  final _form = GlobalKey<FormState>();
  final _modelo = TextEditingController();
  final _placa = TextEditingController();
  String _tipo = 'moto';

  bool _carregando = true;
  bool _salvando = false;
  bool _enviandoCrlv = false;

  Map<String, dynamic>? _crlvData;

  bool get _ehNovo => widget.veiculoId == null;
  bool get _precisaDePlaca => _tipo != 'bike';
  bool get _precisaDeCrlv => _tipo != 'bike';

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  DocumentReference<Map<String, dynamic>>? _docVeiculo({String? id}) {
    final uid = _uid;
    final vid = id ?? widget.veiculoId;
    if (uid == null || vid == null) return null;
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('veiculos')
        .doc(vid);
  }

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    _modelo.dispose();
    _placa.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    if (_ehNovo) {
      setState(() => _carregando = false);
      return;
    }
    final ref = _docVeiculo();
    if (ref == null) {
      setState(() => _carregando = false);
      return;
    }
    try {
      final d = await ref.get();
      final data = d.data() ?? {};
      _modelo.text = (data['modelo'] ?? '').toString();
      _placa.text = (data['placa'] ?? '').toString();
      _tipo = (data['tipo'] ?? 'moto').toString();

      final crlvSnap = await ref.collection('documentos').doc('crlv').get();
      _crlvData = crlvSnap.data();

      // Fallback: se não existe doc CRLV na subcoleção mas existe URL legada
      // (users.url_crlv enviada no cadastro inicial), exibe como "pendente".
      if ((_crlvData == null || (_crlvData!['url'] ?? '').toString().isEmpty) &&
          _uid != null) {
        final userSnap =
            await FirebaseFirestore.instance.collection('users').doc(_uid).get();
        final urlLegada =
            (userSnap.data()?['url_crlv'] ?? '').toString().trim();
        if (urlLegada.isNotEmpty) {
          _crlvData = {
            'url': urlLegada,
            'status': 'pendente',
            'origem': 'cadastro_entregador',
          };
        }
      }
    } catch (e) {
      debugPrint('[EditarVeiculo] erro: $e');
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _salvar() async {
    if (!_form.currentState!.validate()) return;
    final uid = _uid;
    if (uid == null) return;
    setState(() => _salvando = true);
    try {
      final col = FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('veiculos');
      final ref = _ehNovo ? col.doc() : col.doc(widget.veiculoId);
      await ref.set({
        'tipo': _tipo,
        'modelo': _modelo.text.trim(),
        'placa': _precisaDePlaca
            ? _placa.text.trim().toUpperCase()
            : '',
        if (_ehNovo) ...{
          'ativo': false,
          'criado_em': FieldValue.serverTimestamp(),
        },
        'atualizado_em': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_ehNovo ? 'Veículo adicionado.' : 'Veículo atualizado.'),
        ),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro: $e')),
      );
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  Future<void> _anexarCrlv() async {
    if (_ehNovo) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Salve o veículo primeiro para anexar o CRLV.'),
        ),
      );
      return;
    }
    final uid = _uid;
    final vid = widget.veiculoId;
    if (uid == null || vid == null) return;

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

    setState(() => _enviandoCrlv = true);
    try {
      final file = File(result.files.single.path!);
      final ext = file.path.split('.').last.toLowerCase();
      final ts = DateTime.now().millisecondsSinceEpoch;
      final storageRef = FirebaseStorage.instance
          .ref()
          .child('documentos_entregadores/$uid/crlv_${vid}_$ts.$ext');
      final snap = await storageRef.putFile(file);
      final url = await snap.ref.getDownloadURL();

      final docRef = FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('veiculos')
          .doc(vid)
          .collection('documentos')
          .doc('crlv');
      await docRef.set({
        'url': url,
        'status': 'pendente',
        'motivo_reprovacao': FieldValue.delete(),
        'atualizado_em': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      final fresh = await docRef.get();
      if (!mounted) return;
      setState(() => _crlvData = fresh.data());
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('CRLV enviado. Aguarde a aprovação da equipe.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao enviar: $e')),
      );
    } finally {
      if (mounted) setState(() => _enviandoCrlv = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F7),
      appBar: AppBar(
        title: Text(
          _ehNovo ? 'Adicionar veículo' : 'Editar veículo',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: _roxo,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator(color: _laranja))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Card(
                      titulo: 'Dados do veículo',
                      children: [
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Expanded(
                              child: _Chip(
                                icone: Icons.two_wheeler_rounded,
                                rotulo: 'Moto',
                                selecionado: _tipo == 'moto',
                                onTap: () => setState(() => _tipo = 'moto'),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: _Chip(
                                icone: Icons.directions_car_rounded,
                                rotulo: 'Carro',
                                selecionado: _tipo == 'carro',
                                onTap: () => setState(() => _tipo = 'carro'),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: _Chip(
                                icone: Icons.directions_bike_rounded,
                                rotulo: 'Bike',
                                selecionado: _tipo == 'bike',
                                onTap: () => setState(() {
                                  _tipo = 'bike';
                                  _placa.clear();
                                }),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _modelo,
                          decoration: InputDecoration(
                            labelText: 'Modelo',
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? 'Informe o modelo'
                              : null,
                        ),
                        if (_precisaDePlaca) ...[
                          const SizedBox(height: 10),
                          TextFormField(
                            controller: _placa,
                            textCapitalization: TextCapitalization.characters,
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                RegExp(r'[A-Za-z0-9-]'),
                              ),
                              LengthLimitingTextInputFormatter(8),
                            ],
                            decoration: InputDecoration(
                              labelText: 'Placa',
                              hintText: 'AAA0000 ou AAA0A00',
                              filled: true,
                              fillColor: Colors.white,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            validator: (v) {
                              if (!_precisaDePlaca) return null;
                              final raw = (v ?? '').replaceAll('-', '').trim();
                              if (raw.length < 7) return 'Placa inválida';
                              return null;
                            },
                          ),
                        ],
                      ],
                    ),
                    if (!_ehNovo && _precisaDeCrlv) ...[
                      const SizedBox(height: 12),
                      _Card(
                        titulo: 'Documento do veículo (CRLV)',
                        children: [
                          _CrlvCard(
                            data: _crlvData,
                            enviando: _enviandoCrlv,
                            onAnexar: _anexarCrlv,
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 24),
                    SizedBox(
                      height: 48,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _laranja,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        onPressed: _salvando ? null : _salvar,
                        child: _salvando
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2.5,
                                ),
                              )
                            : Text(
                                _ehNovo ? 'Adicionar' : 'Salvar alterações',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

class _Card extends StatelessWidget {
  final String titulo;
  final List<Widget> children;
  const _Card({required this.titulo, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              titulo,
              style: const TextStyle(color: _roxo, fontWeight: FontWeight.bold),
            ),
          ),
          ...children,
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final IconData icone;
  final String rotulo;
  final bool selecionado;
  final VoidCallback onTap;

  const _Chip({
    required this.icone,
    required this.rotulo,
    required this.selecionado,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selecionado
              ? _laranja.withValues(alpha: 0.15)
              : Colors.grey.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selecionado ? _laranja : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Column(
          children: [
            Icon(icone, color: selecionado ? _laranja : Colors.black54),
            const SizedBox(height: 4),
            Text(
              rotulo,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: selecionado ? _laranja : Colors.black54,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CrlvCard extends StatelessWidget {
  final Map<String, dynamic>? data;
  final bool enviando;
  final VoidCallback onAnexar;

  const _CrlvCard({
    required this.data,
    required this.enviando,
    required this.onAnexar,
  });

  @override
  Widget build(BuildContext context) {
    final status = (data?['status'] ?? '').toString();
    final motivo = (data?['motivo_reprovacao'] ?? '').toString();
    final url = (data?['url'] ?? '').toString();
    final _StatusVisual sv = _resolverStatus(status);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: sv.cor.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: sv.cor.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(sv.icone, color: sv.cor),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  sv.rotulo,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: sv.cor,
                  ),
                ),
                if (motivo.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Motivo: $motivo',
                    style: TextStyle(color: sv.cor, fontSize: 12),
                  ),
                ],
                if (url.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 2),
                    child: Text(
                      'Nenhum arquivo enviado.',
                      style: TextStyle(fontSize: 12, color: Colors.black54),
                    ),
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
    );
  }

  _StatusVisual _resolverStatus(String status) {
    switch (status.toLowerCase()) {
      case 'aprovado':
        return const _StatusVisual(
          rotulo: 'Aprovado',
          cor: Colors.green,
          icone: Icons.check_circle,
        );
      case 'reprovado':
      case 'recusado':
        return const _StatusVisual(
          rotulo: 'Reprovado',
          cor: Colors.red,
          icone: Icons.cancel,
        );
      case 'pendente':
        return const _StatusVisual(
          rotulo: 'Em análise',
          cor: Colors.orange,
          icone: Icons.schedule,
        );
      default:
        return const _StatusVisual(
          rotulo: 'Não enviado',
          cor: Colors.grey,
          icone: Icons.upload_file,
        );
    }
  }
}

class _StatusVisual {
  final String rotulo;
  final Color cor;
  final IconData icone;
  const _StatusVisual({
    required this.rotulo,
    required this.cor,
    required this.icone,
  });
}
