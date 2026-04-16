// Arquivo: lib/screens/entregador/entregador_form_screen.dart

import 'dart:io';
import 'package:flutter/material.dart';
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

  bool _isLoading = false;
  bool _carregandoInicial = true;
  String? _statusAtual;
  String? _motivoRecusa;

  final List<String> _tiposVeiculo = ['Moto', 'Carro', 'Bicicleta'];

  @override
  void initState() {
    super.initState();
    _buscarDadosIniciais();
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
          if (mounted) {
            setState(() {
              _statusAtual = dados['entregador_status'];
              _motivoRecusa = dados['motivo_recusa'];
              if (dados['veiculoTipo'] != null &&
                  _tiposVeiculo.contains(dados['veiculoTipo'])) {
                _veiculoSelecionado = dados['veiculoTipo'];
              }
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
    if (_arqDocPessoal == null ||
        _arqFotoVeiculo == null ||
        (_veiculoSelecionado != 'Bicicleta' && _arqCRLV == null)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Anexe todos os documentos obrigatórios.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        String urlDocPessoal = await _fazerUpload(
          _arqDocPessoal!,
          'doc_pessoal_${DateTime.now().millisecondsSinceEpoch}',
          user.uid,
        );
        String urlFotoVeiculo = await _fazerUpload(
          _arqFotoVeiculo!,
          'foto_veiculo_${DateTime.now().millisecondsSinceEpoch}',
          user.uid,
        );
        String urlCRLV = "";
        if (_veiculoSelecionado != 'Bicicleta') {
          urlCRLV = await _fazerUpload(
            _arqCRLV!,
            'crlv_${DateTime.now().millisecondsSinceEpoch}',
            user.uid,
          );
        }

        // === ATUALIZA OS DADOS NO BANCO ===
        await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
          'role': 'entregador',
          'entregador_status': 'pendente', // Volta para a fila de análise!
          'veiculoTipo':
              _veiculoSelecionado, // Ajustado para o nome exato que o painel web lê
          'url_doc_pessoal': urlDocPessoal,
          'url_foto_veículo':
              urlFotoVeiculo, // Ajustado para o nome exato que o painel web lê
          'url_crlv': urlCRLV,
          'motivo_recusa':
              FieldValue.delete(), // Apaga o motivo da recusa antiga!
          'data_solicitacao_entregador': FieldValue.serverTimestamp(),
        });

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

  Widget _botaoUploadCustomizado({
    required String titulo,
    required File? arquivo,
    required int tipoID,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: arquivo != null ? Colors.green : Colors.grey[400]!,
        ),
      ),
      child: Row(
        children: [
          Icon(
            arquivo != null ? Icons.check_circle : Icons.upload_file,
            color: arquivo != null ? Colors.green : diPertinRoxo,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              arquivo != null ? "Arquivo Anexado" : titulo,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: arquivo != null ? Colors.green : Colors.black87,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () => _escolherArquivo(tipoID),
            style: ElevatedButton.styleFrom(
              backgroundColor: arquivo != null ? Colors.grey : diPertinLaranja,
            ),
            child: Text(
              arquivo != null ? "Trocar" : "Anexar",
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
                            _arqCRLV = null;
                            _arqDocPessoal = null;
                            _arqFotoVeiculo = null;
                          });
                        },
                      ),
                    ),
                  ),
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
                  ),
                  if (_veiculoSelecionado != 'Bicicleta')
                    _botaoUploadCustomizado(
                      titulo: "Documento do Veículo (CRLV)",
                      arquivo: _arqCRLV,
                      tipoID: 2,
                    ),
                  _botaoUploadCustomizado(
                    titulo: _veiculoSelecionado == 'Bicicleta'
                        ? "Foto da Bicicleta em bom estado"
                        : "Foto do Veículo (Placa Visível)",
                    arquivo: _arqFotoVeiculo,
                    tipoID: 3,
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
