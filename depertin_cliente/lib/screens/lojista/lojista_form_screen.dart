// Arquivo: lib/screens/lojista/lojista_form_screen.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_picker/file_picker.dart';

const Color diPertinRoxo = Color(0xFF6A1B9A);
const Color diPertinLaranja = Color(0xFFFF8F00);

class LojistaFormScreen extends StatefulWidget {
  const LojistaFormScreen({super.key});

  @override
  State<LojistaFormScreen> createState() => _LojistaFormScreenState();
}

class _LojistaFormScreenState extends State<LojistaFormScreen> {
  final _nomeLojaController = TextEditingController();
  final _documentoController = TextEditingController();

  String _tipoPessoa = 'CPF'; // CPF (Autônomo) ou CNPJ (Empresa)

  // Variáveis para salvar cada arquivo
  File? _arqDocPessoal;
  File? _arqCNPJ;
  File? _arqEndereco;
  File? _arqVitrine;

  bool _isLoading = false;

  // Variáveis para a mágica da recusa
  bool _carregandoInicial = true;
  String? _statusAtual;
  String? _motivoRecusa;

  @override
  void initState() {
    super.initState();
    _buscarDadosIniciais();
  }

  // === LÊ SE O CADASTRO FOI RECUSADO PARA AVISAR O LOJISTA ===
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
              _statusAtual = dados['status_loja'];
              _motivoRecusa = dados['motivo_recusa'];

              // Se ele já tinha preenchido antes, carrega os textos para facilitar a correção!
              if (dados['loja_nome'] != null) {
                _nomeLojaController.text = dados['loja_nome'];
              }
              if (dados['loja_documento'] != null) {
                _documentoController.text = dados['loja_documento'];
              }
              if (dados['loja_tipo_documento'] != null) {
                _tipoPessoa = dados['loja_tipo_documento'];
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
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf'],
    );

    if (result != null) {
      setState(() {
        File arquivo = File(result.files.single.path!);
        if (tipoDocumento == 1) _arqDocPessoal = arquivo;
        if (tipoDocumento == 2) _arqCNPJ = arquivo;
        if (tipoDocumento == 3) _arqEndereco = arquivo;
        if (tipoDocumento == 4) _arqVitrine = arquivo;
      });
    }
  }

  // === UPLOAD INTELIGENTE: GUARDA A EXTENSÃO DO ARQUIVO (.pdf ou .jpg) ===
  Future<String> _fazerUpload(File arquivo, String nomeBase, String uid) async {
    // Descobre se o arquivo é .pdf, .jpg, .png...
    String extensao = arquivo.path.split('.').last.toLowerCase();
    String nomeArquivoComExtensao = '$nomeBase.$extensao'; // Ex: cnpj_12345.pdf

    final ref = FirebaseStorage.instance.ref().child(
      'documentos_lojistas/$uid/$nomeArquivoComExtensao',
    );
    TaskSnapshot uploadTask = await ref.putFile(arquivo);
    return await uploadTask.ref.getDownloadURL();
  }

  Future<void> _enviarSolicitacao() async {
    // Validações de texto
    if (_nomeLojaController.text.isEmpty || _documentoController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Preencha o nome da loja e o documento.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Validações de anexos
    if (_arqDocPessoal == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Anexe o seu documento pessoal (RG/CNH).'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    if (_tipoPessoa == 'CNPJ' && _arqCNPJ == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Anexe o Cartão CNPJ ou Contrato Social.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    if (_tipoPessoa == 'CPF' && _arqVitrine == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Anexe uma foto que comprove sua venda (vitrine, local de preparo, etc).',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    if (_arqEndereco == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Anexe o comprovante de endereço.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        // Faz o upload de todos os arquivos anexados
        String urlDocPessoal = await _fazerUpload(
          _arqDocPessoal!,
          'doc_pessoal_${DateTime.now().millisecondsSinceEpoch}',
          user.uid,
        );
        String urlEndereco = await _fazerUpload(
          _arqEndereco!,
          'comprovante_endereco_${DateTime.now().millisecondsSinceEpoch}',
          user.uid,
        );

        String urlCNPJ = "";
        String urlVitrine = "";

        if (_tipoPessoa == 'CNPJ') {
          urlCNPJ = await _fazerUpload(
            _arqCNPJ!,
            'cnpj_${DateTime.now().millisecondsSinceEpoch}',
            user.uid,
          );
        }

        if (_tipoPessoa == 'CPF' && _arqVitrine != null) {
          urlVitrine = await _fazerUpload(
            _arqVitrine!,
            'foto_vitrine_${DateTime.now().millisecondsSinceEpoch}',
            user.uid,
          );
        }

        // === ATUALIZA OS DADOS NO BANCO ===
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .update({
              'tipo': 'lojista',
              'role': 'lojista',
              'status_loja': 'pendente', // Volta para a fila de análise!
              'loja_nome': _nomeLojaController.text.trim(),
              'loja_tipo_documento': _tipoPessoa,
              'loja_documento': _documentoController.text.trim(),
              'loja_url_doc_pessoal': urlDocPessoal,
              'loja_url_endereco': urlEndereco,
              'loja_url_cnpj': urlCNPJ,
              'loja_url_vitrine': urlVitrine,
              'motivo_recusa':
                  FieldValue.delete(), // Apaga o motivo da recusa antiga!
              'data_solicitacao_loja': FieldValue.serverTimestamp(),
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
          // Retorna suavemente para o perfil
          Navigator.pop(context);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Erro ao enviar solicitação.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // Helper para criar os botões bonitos de anexo
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
                fontSize: 13,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () => _escolherArquivo(tipoID),
            style: ElevatedButton.styleFrom(
              backgroundColor: arquivo != null ? Colors.grey : diPertinLaranja,
              minimumSize: const Size(80, 36),
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
          "Ser Lojista",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: diPertinRoxo,
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
                  if (_statusAtual == 'bloqueada' &&
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
                    Icons.storefront,
                    size: 60,
                    color: diPertinLaranja,
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    "Traga sua loja para o DiPertin",
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: diPertinRoxo,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 30),

                  TextField(
                    controller: _nomeLojaController,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Nome da Loja (Fantasia)',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.business),
                    ),
                  ),
                  const SizedBox(height: 20),

                  const Text(
                    "Tipo de Negócio",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      Expanded(
                        child: RadioListTile<String>(
                          contentPadding: EdgeInsets.zero,
                          title: const Text(
                            "Autônomo (CPF)",
                            style: TextStyle(fontSize: 13),
                          ),
                          value: 'CPF',
                          groupValue: _tipoPessoa,
                          activeColor: diPertinLaranja,
                          onChanged: (value) {
                            setState(() {
                              _tipoPessoa = value!;
                              _arqCNPJ = null;
                            });
                          },
                        ),
                      ),
                      Expanded(
                        child: RadioListTile<String>(
                          contentPadding: EdgeInsets.zero,
                          title: const Text(
                            "Empresa (CNPJ)",
                            style: TextStyle(fontSize: 13),
                          ),
                          value: 'CNPJ',
                          groupValue: _tipoPessoa,
                          activeColor: diPertinLaranja,
                          onChanged: (value) {
                            setState(() {
                              _tipoPessoa = value!;
                              _arqVitrine = null;
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  TextField(
                    controller: _documentoController,
                    decoration: InputDecoration(
                      labelText: _tipoPessoa == 'CPF'
                          ? 'Número do CPF'
                          : 'Número do CNPJ',
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.description),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 30),

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
                    titulo: "Doc. de Identidade (RG ou CNH)",
                    arquivo: _arqDocPessoal,
                    tipoID: 1,
                  ),

                  if (_tipoPessoa == 'CNPJ')
                    _botaoUploadCustomizado(
                      titulo: "Cartão CNPJ / Contrato Social",
                      arquivo: _arqCNPJ,
                      tipoID: 2,
                    ),

                  if (_tipoPessoa == 'CPF')
                    _botaoUploadCustomizado(
                      titulo: "Foto da Vitrine / Local de Venda",
                      arquivo: _arqVitrine,
                      tipoID: 4,
                    ),

                  _botaoUploadCustomizado(
                    titulo: "Comprovante de Endereço (Loja ou Residência)",
                    arquivo: _arqEndereco,
                    tipoID: 3,
                  ),

                  const SizedBox(height: 30),

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
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                  ),
                ],
              ),
            ),
    );
  }
}
