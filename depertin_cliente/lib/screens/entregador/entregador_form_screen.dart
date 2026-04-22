// Arquivo: lib/screens/entregador/entregador_form_screen.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_picker/file_picker.dart';

import '../../services/permissoes_app_service.dart';

const Color diPertinRoxo = Color(0xFF6A1B9A);
const Color diPertinLaranja = Color(0xFFFF8F00);

class EntregadorFormScreen extends StatefulWidget {
  const EntregadorFormScreen({super.key});

  @override
  State<EntregadorFormScreen> createState() => _EntregadorFormScreenState();
}

class _EntregadorFormScreenState extends State<EntregadorFormScreen> {
  String _veiculoSelecionado = 'Moto';
  File? _arqDocPessoal;
  File? _arqCRLV;
  File? _arqFotoVeiculo;

  // URLs já enviados anteriormente (para reenvio sem precisar anexar de novo)
  String? _urlDocPessoalAtual;
  String? _urlCrlvAtual;
  String? _urlFotoVeiculoAtual;

  final _modeloController = TextEditingController();
  final _placaController = TextEditingController();

  bool _isLoading = false;
  bool _carregandoInicial = true;
  String? _statusAtual;
  String? _motivoRecusa;

  final List<String> _tiposVeiculo = ['Moto', 'Carro', 'Bicicleta'];

  bool get _precisaPlaca => _veiculoSelecionado != 'Bicicleta';

  @override
  void initState() {
    super.initState();
    _buscarDadosIniciais();
  }

  @override
  void dispose() {
    _modeloController.dispose();
    _placaController.dispose();
    super.dispose();
  }

  // === MÁGICA: LÊ SE O CADASTRO FOI RECUSADO PARA AVISAR O USUÁRIO ===
  Future<void> _buscarDadosIniciais() async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        DocumentSnapshot doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        if (doc.exists) {
          var dados = doc.data() as Map<String, dynamic>;

          // Tenta buscar o veículo ativo da subcoleção (fonte mais nova)
          String? modeloAtivo;
          String? placaAtiva;
          try {
            final ativoQ = await FirebaseFirestore.instance
                .collection('users')
                .doc(user.uid)
                .collection('veiculos')
                .where('ativo', isEqualTo: true)
                .limit(1)
                .get();
            if (ativoQ.docs.isNotEmpty) {
              final v = ativoQ.docs.first.data();
              modeloAtivo = (v['modelo'] ?? '').toString();
              placaAtiva = (v['placa'] ?? '').toString();
            }
          } catch (_) {}

          if (mounted) {
            setState(() {
              _statusAtual = dados['entregador_status'];
              _motivoRecusa = dados['motivo_recusa'];
              if (dados['veiculoTipo'] != null &&
                  _tiposVeiculo.contains(dados['veiculoTipo'])) {
                _veiculoSelecionado = dados['veiculoTipo'];
              }
              _modeloController.text = (modeloAtivo?.isNotEmpty ?? false)
                  ? modeloAtivo!
                  : (dados['veiculoModelo'] ?? '').toString();
              _placaController.text = ((placaAtiva?.isNotEmpty ?? false)
                      ? placaAtiva!
                      : (dados['placa_veiculo'] ?? '').toString())
                  .toUpperCase();
              _urlDocPessoalAtual =
                  (dados['url_doc_pessoal'] ?? '').toString().isNotEmpty
                      ? dados['url_doc_pessoal'].toString()
                      : null;
              _urlCrlvAtual = (dados['url_crlv'] ?? '').toString().isNotEmpty
                  ? dados['url_crlv'].toString()
                  : null;
              _urlFotoVeiculoAtual =
                  (dados['url_foto_veículo'] ?? '').toString().isNotEmpty
                      ? dados['url_foto_veículo'].toString()
                      : null;
            });
          }
        }
      } catch (e) {
        debugPrint("Erro ao buscar dados: $e");
      }
    }
    if (mounted) {
      setState(() => _carregandoInicial = false);
    }
  }

  Future<void> _escolherArquivo(int tipoDocumento) async {
    final ResultadoPermissao pr =
        await PermissoesAppService.garantirLeituraArquivosAnexos();
    if (!mounted) return;
    if (pr != ResultadoPermissao.concedida) {
      PermissoesFeedback.arquivosAnexos(context, pr);
      return;
    }
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf'],
    );
    if (result != null) {
      setState(() {
        File arquivo = File(result.files.single.path!);
        if (tipoDocumento == 1) _arqDocPessoal = arquivo;
        if (tipoDocumento == 2) _arqCRLV = arquivo;
        if (tipoDocumento == 3) _arqFotoVeiculo = arquivo;
      });
    }
  }

  Future<String> _fazerUpload(File arquivo, String nomeBase, String uid) async {
    // Descobre se o arquivo é .pdf, .jpg, .png...
    String extensao = arquivo.path.split('.').last.toLowerCase();
    String nomeArquivoComExtensao =
        '$nomeBase.$extensao'; // Ex: doc_pessoal_12345.pdf

    final ref = FirebaseStorage.instance.ref().child(
      'documentos_entregadores/$uid/$nomeArquivoComExtensao',
    );
    TaskSnapshot uploadTask = await ref.putFile(arquivo);
    return await uploadTask.ref.getDownloadURL();
  }

  Future<void> _enviarSolicitacao() async {
    // Validação de documentos (permite reaproveitar URL anterior em reenvio)
    final temDocPessoal = _arqDocPessoal != null ||
        (_urlDocPessoalAtual != null && _urlDocPessoalAtual!.isNotEmpty);
    final temFotoVeiculo = _arqFotoVeiculo != null ||
        (_urlFotoVeiculoAtual != null && _urlFotoVeiculoAtual!.isNotEmpty);
    final temCrlv = _veiculoSelecionado == 'Bicicleta' ||
        _arqCRLV != null ||
        (_urlCrlvAtual != null && _urlCrlvAtual!.isNotEmpty);

    if (!temDocPessoal || !temFotoVeiculo || !temCrlv) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Anexe todos os documentos obrigatórios.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Validação de placa (quando não é bicicleta)
    final placaNormalizada = _placaController.text
        .replaceAll('-', '')
        .replaceAll(' ', '')
        .trim()
        .toUpperCase();
    if (_precisaPlaca) {
      final okPlaca = RegExp(r'^[A-Z]{3}[0-9][A-Z0-9][0-9]{2}$')
          .hasMatch(placaNormalizada);
      if (!okPlaca) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('Informe a placa do veículo (ex.: ABC1D23 ou ABC1234).'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
    }

    setState(() => _isLoading = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        String urlDocPessoal = _urlDocPessoalAtual ?? '';
        if (_arqDocPessoal != null) {
          urlDocPessoal = await _fazerUpload(
            _arqDocPessoal!,
            'doc_pessoal_${DateTime.now().millisecondsSinceEpoch}',
            user.uid,
          );
        }

        String urlFotoVeiculo = _urlFotoVeiculoAtual ?? '';
        if (_arqFotoVeiculo != null) {
          urlFotoVeiculo = await _fazerUpload(
            _arqFotoVeiculo!,
            'foto_veiculo_${DateTime.now().millisecondsSinceEpoch}',
            user.uid,
          );
        }

        String urlCRLV = _urlCrlvAtual ?? '';
        if (_veiculoSelecionado != 'Bicicleta' && _arqCRLV != null) {
          urlCRLV = await _fazerUpload(
            _arqCRLV!,
            'crlv_${DateTime.now().millisecondsSinceEpoch}',
            user.uid,
          );
        }
        if (_veiculoSelecionado == 'Bicicleta') {
          urlCRLV = '';
        }

        // === Atualiza o doc principal (campos planos — painel web) ===
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .update({
          'role': 'entregador',
          'entregador_status': 'pendente',
          'veiculoTipo': _veiculoSelecionado,
          'veiculoModelo': _modeloController.text.trim(),
          'placa_veiculo': _precisaPlaca ? placaNormalizada : '',
          'url_doc_pessoal': urlDocPessoal,
          'url_foto_veículo': urlFotoVeiculo,
          'url_crlv': urlCRLV,
          'motivo_recusa': FieldValue.delete(),
          'data_solicitacao_entregador': FieldValue.serverTimestamp(),
        });

        // === Semeia veículo ativo em users/{uid}/veiculos ===
        await _garantirVeiculoAtivoNaSubcolecao(
          uid: user.uid,
          tipoLabel: _veiculoSelecionado,
          modelo: _modeloController.text.trim(),
          placa: _precisaPlaca ? placaNormalizada : '',
          urlCrlv: urlCRLV,
        );

        // === Semeia CNH em users/{uid}/documentos/cnh ===
        if (urlDocPessoal.isNotEmpty) {
          await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .collection('documentos')
              .doc('cnh')
              .set({
            'url': urlDocPessoal,
            'status': 'pendente',
            'motivo_reprovacao': FieldValue.delete(),
            'origem': 'cadastro_entregador',
            'atualizado_em': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Solicitação reenviada com sucesso! Aguarde a nova análise.',
              ),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.pop(context);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Erro ao enviar. Tente novamente.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _tipoCodigo(String label) {
    switch (label) {
      case 'Moto':
        return 'moto';
      case 'Carro':
        return 'carro';
      case 'Bicicleta':
        return 'bike';
      default:
        return label.toLowerCase();
    }
  }

  Future<void> _garantirVeiculoAtivoNaSubcolecao({
    required String uid,
    required String tipoLabel,
    required String modelo,
    required String placa,
    required String urlCrlv,
  }) async {
    final col = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('veiculos');
    final ativos = await col.where('ativo', isEqualTo: true).limit(1).get();
    final DocumentReference<Map<String, dynamic>> vRef = ativos.docs.isNotEmpty
        ? ativos.docs.first.reference
        : col.doc();
    final ehNovo = ativos.docs.isEmpty;

    await vRef.set({
      'tipo': _tipoCodigo(tipoLabel),
      'modelo': modelo,
      'placa': placa,
      'ativo': true,
      'seed_from_cadastro': true,
      if (ehNovo) 'criado_em': FieldValue.serverTimestamp(),
      'atualizado_em': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await FirebaseFirestore.instance.collection('users').doc(uid).set({
      'veiculo_ativo_id': vRef.id,
    }, SetOptions(merge: true));

    if (urlCrlv.isNotEmpty) {
      await vRef.collection('documentos').doc('crlv').set({
        'url': urlCrlv,
        'status': 'pendente',
        'motivo_reprovacao': FieldValue.delete(),
        'origem': 'cadastro_entregador',
        'atualizado_em': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
  }

  Widget _botaoUploadCustomizado({
    required String titulo,
    required File? arquivo,
    required int tipoID,
    String? urlExistente,
  }) {
    final bool jaEnviado = arquivo == null &&
        urlExistente != null &&
        urlExistente.isNotEmpty;
    final bool novoAnexado = arquivo != null;
    final bool verde = novoAnexado || jaEnviado;
    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: verde ? Colors.green : Colors.grey[400]!,
        ),
      ),
      child: Row(
        children: [
          Icon(
            verde ? Icons.check_circle : Icons.upload_file,
            color: verde ? Colors.green : diPertinRoxo,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              novoAnexado
                  ? "Arquivo Anexado"
                  : jaEnviado
                      ? "Já enviado — toque em Trocar para atualizar"
                      : titulo,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: verde ? Colors.green : Colors.black87,
                fontSize: 13,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () => _escolherArquivo(tipoID),
            style: ElevatedButton.styleFrom(
              backgroundColor: verde ? Colors.grey : diPertinLaranja,
            ),
            child: Text(
              verde ? "Trocar" : "Anexar",
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          "Ser Entregador",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.black87,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _carregandoInicial
          ? const Center(
              child: CircularProgressIndicator(color: diPertinLaranja),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // === ALERTA DE CADASTRO RECUSADO ===
                  if (_statusAtual == 'bloqueado' &&
                      _motivoRecusa != null &&
                      _motivoRecusa!.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.all(15),
                      margin: const EdgeInsets.only(bottom: 20),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        border: Border.all(color: Colors.red),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.error_outline, color: Colors.red),
                              SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  "Cadastro Recusado",
                                  style: TextStyle(
                                    color: Colors.red,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          Divider(color: Colors.red.shade200),
                          Text(
                            "Motivo: $_motivoRecusa",
                            style: TextStyle(color: Colors.red.shade900),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            "Por favor, corrija as informações abaixo e anexe os documentos novamente para uma nova análise.",
                            style: TextStyle(
                              color: Colors.red.shade700,
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),

                  const Icon(
                    Icons.two_wheeler,
                    size: 60,
                    color: diPertinLaranja,
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    "Trabalhe com o DiPertin",
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),

                  const Text(
                    "Tipo de Veículo",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 5),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _veiculoSelecionado,
                        isExpanded: true,
                        items: _tiposVeiculo
                            .map(
                              (String veiculo) => DropdownMenuItem<String>(
                                value: veiculo,
                                child: Text(veiculo),
                              ),
                            )
                            .toList(),
                        onChanged: (String? novoValor) {
                          setState(() {
                            _veiculoSelecionado = novoValor!;
                            if (_veiculoSelecionado == 'Bicicleta') {
                              _placaController.clear();
                              _arqCRLV = null;
                              _urlCrlvAtual = null;
                            }
                          });
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),

                  TextField(
                    controller: _modeloController,
                    decoration: InputDecoration(
                      labelText: _veiculoSelecionado == 'Bicicleta'
                          ? 'Modelo (opcional)'
                          : 'Modelo do veículo',
                      hintText: _veiculoSelecionado == 'Bicicleta'
                          ? 'Ex.: Caloi 10'
                          : 'Ex.: Honda CG 160',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),

                  if (_precisaPlaca) ...[
                    const SizedBox(height: 10),
                    TextField(
                      controller: _placaController,
                      textCapitalization: TextCapitalization.characters,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                          RegExp(r'[A-Za-z0-9-]'),
                        ),
                        LengthLimitingTextInputFormatter(8),
                      ],
                      decoration: InputDecoration(
                        labelText: 'Placa do veículo',
                        hintText: 'ABC1D23 (Mercosul) ou ABC1234',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ],

                  const SizedBox(height: 20),

                  const Text(
                    "Documentação Obrigatória",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 10),

                  _botaoUploadCustomizado(
                    titulo: _veiculoSelecionado == 'Bicicleta'
                        ? "Documento de Identidade (RG/CNH)"
                        : "CNH Válida",
                    arquivo: _arqDocPessoal,
                    tipoID: 1,
                    urlExistente: _urlDocPessoalAtual,
                  ),
                  if (_veiculoSelecionado != 'Bicicleta')
                    _botaoUploadCustomizado(
                      titulo: "Documento do Veículo (CRLV)",
                      arquivo: _arqCRLV,
                      tipoID: 2,
                      urlExistente: _urlCrlvAtual,
                    ),
                  _botaoUploadCustomizado(
                    titulo: _veiculoSelecionado == 'Bicicleta'
                        ? "Foto da Bicicleta em bom estado"
                        : "Foto do Veículo (Placa Visível)",
                    arquivo: _arqFotoVeiculo,
                    tipoID: 3,
                    urlExistente: _urlFotoVeiculoAtual,
                  ),

                  const SizedBox(height: 20),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: diPertinLaranja,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                    ),
                    onPressed: _isLoading ? null : _enviarSolicitacao,
                    child: _isLoading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text(
                            'ENVIAR PARA ANÁLISE',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                  ),
                ],
              ),
            ),
    );
  }
}
