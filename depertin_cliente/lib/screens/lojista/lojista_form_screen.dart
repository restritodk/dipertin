// Arquivo: lib/screens/lojista/lojista_form_screen.dart

import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_multi_formatter/flutter_multi_formatter.dart';
import 'package:intl/intl.dart';

import '../../constants/lojista_motivo_recusa.dart';
import '../../services/permissoes_app_service.dart';
import '../../utils/cpf_perfil_usuario.dart';
import '../../widgets/dipertin_scroll_body.dart';

const Color _diPertinRoxo = Color(0xFF6A1B9A);
const Color _diPertinLaranja = Color(0xFFFF8F00);
const Color _fundoTela = Color(0xFFF5F4F8);
const Color _textoPrimario = Color(0xFF1A1A2E);
const Color _textoMuted = Color(0xFF64748B);
const Color _erroCampo = Color(0xFFD32F2F);
const Color _sucessoCampo = Color(0xFF2E7D32);
const Color _fundoSucessoCampo = Color(0xFFE8F5E9);
const Color _fundoErroCampo = Color(0xFFFFEBEE);

enum _EstadoValidacaoDocumento { neutro, valido, invalido }

class LojistaFormScreen extends StatefulWidget {
  const LojistaFormScreen({super.key});

  @override
  State<LojistaFormScreen> createState() => _LojistaFormScreenState();
}

class _LojistaFormScreenState extends State<LojistaFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nomeLojaController = TextEditingController();
  final _documentoController = TextEditingController();

  String _tipoPessoa = 'CPF';

  File? _arqDocPessoal;
  File? _arqCNPJ;
  File? _arqEndereco;
  File? _arqVitrine;

  bool _isLoading = false;
  String? _mensagemEnvio;

  bool _carregandoInicial = true;
  bool _entradaAnimada = false;
  String? _statusAtual;
  String? _motivoRecusa;
  String? _motivoRecusaCodigo;
  DateTime? _bloqueioCadastroAte;

  String? _erroCampoNome;
  String? _erroCampoDocumento;
  String? _erroDocPessoal;
  String? _erroCnpj;
  String? _erroVitrine;
  String? _erroEndereco;

  @override
  void initState() {
    super.initState();
    _buscarDadosIniciais();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _entradaAnimada = true);
    });
  }

  @override
  void dispose() {
    _nomeLojaController.dispose();
    _documentoController.dispose();
    super.dispose();
  }

  Future<void> _buscarDadosIniciais() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        if (doc.exists) {
          final dados = doc.data() as Map<String, dynamic>;
          if (mounted) {
            setState(() {
              _statusAtual = dados['status_loja'];
              _motivoRecusa = dados['motivo_recusa'];
              _motivoRecusaCodigo =
                  LojistaMotivoRecusa.codigoDoDocumento(dados);
              _bloqueioCadastroAte =
                  LojistaMotivoRecusa.bloqueioCadastroAte(dados);

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
        debugPrint('Erro ao buscar dados: $e');
      }
    }
    if (mounted) {
      setState(() => _carregandoInicial = false);
    }
  }

  bool get _nomeLojaPreenchido => _nomeLojaController.text.trim().isNotEmpty;

  bool get _documentoValido {
    final doc = _documentoController.text;
    if (_tipoPessoa == 'CPF') {
      return CpfPerfilUsuario.cpfValido(doc);
    }
    return CpfPerfilUsuario.cnpjValido(doc);
  }

  int get _tamanhoDigitosDocumento => _tipoPessoa == 'CPF' ? 11 : 14;

  _EstadoValidacaoDocumento get _estadoDocumento {
    final digitos =
        CpfPerfilUsuario.somenteDigitos(_documentoController.text);
    if (digitos.isEmpty) return _EstadoValidacaoDocumento.neutro;
    if (_documentoValido) return _EstadoValidacaoDocumento.valido;
    if (digitos.length >= _tamanhoDigitosDocumento) {
      return _EstadoValidacaoDocumento.invalido;
    }
    return _EstadoValidacaoDocumento.neutro;
  }

  bool get _dadosLojaOk => _nomeLojaPreenchido && _documentoValido;

  bool get _documentosOk {
    if (_arqDocPessoal == null || _arqEndereco == null) return false;
    if (_tipoPessoa == 'CNPJ') return _arqCNPJ != null;
    return _arqVitrine != null;
  }

  bool get _podeEnviar => _dadosLojaOk && _documentosOk && !_isLoading;

  InputDecoration _decorCampo(
    String label,
    IconData icon, {
    String? helperText,
  }) {
    return InputDecoration(
      labelText: label,
      helperText: helperText,
      helperStyle: TextStyle(
        color: Colors.grey.shade600,
        fontSize: 12,
        height: 1.25,
      ),
      prefixIcon: Icon(
        icon,
        color: _diPertinRoxo.withValues(alpha: 0.88),
        size: 22,
      ),
      filled: true,
      fillColor: const Color(0xFFF9F8FC),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      labelStyle: TextStyle(
        color: Colors.grey.shade700,
        fontWeight: FontWeight.w500,
        fontSize: 14,
      ),
      floatingLabelStyle: const TextStyle(
        color: _diPertinRoxo,
        fontWeight: FontWeight.w700,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFE0DEE8)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _diPertinLaranja, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _erroCampo, width: 1.5),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _erroCampo, width: 2),
      ),
      errorStyle: const TextStyle(
        color: _erroCampo,
        fontSize: 12.5,
        fontWeight: FontWeight.w500,
        height: 1.2,
      ),
    );
  }

  InputDecoration _decorCampoDocumento() {
    final estado = _estadoDocumento;
    final label =
        _tipoPessoa == 'CPF' ? 'Número do CPF' : 'Número do CNPJ';

    Color borda = const Color(0xFFE0DEE8);
    Color bordaFoco = _diPertinLaranja;
    Color fundo = const Color(0xFFF9F8FC);
    Color icone = _diPertinRoxo.withValues(alpha: 0.88);
    Color rotuloFlutuante = _diPertinRoxo;
    String? ajuda;
    Widget? sufixo;

    if (estado == _EstadoValidacaoDocumento.valido) {
      borda = _sucessoCampo;
      bordaFoco = _sucessoCampo;
      fundo = _fundoSucessoCampo;
      icone = _sucessoCampo;
      rotuloFlutuante = _sucessoCampo;
      ajuda = 'Documento válido';
      sufixo = const Icon(
        Icons.check_circle_rounded,
        color: _sucessoCampo,
        size: 22,
      );
    } else if (estado == _EstadoValidacaoDocumento.invalido) {
      borda = _erroCampo;
      bordaFoco = _erroCampo;
      fundo = _fundoErroCampo;
      icone = _erroCampo;
      rotuloFlutuante = _erroCampo;
      ajuda = _tipoPessoa == 'CPF'
          ? 'CPF inválido — confira os dígitos'
          : 'CNPJ inválido — confira os dígitos';
      sufixo = const Icon(
        Icons.error_outline_rounded,
        color: _erroCampo,
        size: 22,
      );
    }

    return InputDecoration(
      labelText: label,
      helperText: ajuda,
      helperStyle: TextStyle(
        color: estado == _EstadoValidacaoDocumento.valido
            ? _sucessoCampo
            : (estado == _EstadoValidacaoDocumento.invalido
                ? _erroCampo
                : Colors.grey.shade600),
        fontSize: 12,
        fontWeight: FontWeight.w600,
        height: 1.25,
      ),
      prefixIcon: Icon(Icons.badge_outlined, color: icone, size: 22),
      suffixIcon: sufixo,
      filled: true,
      fillColor: fundo,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      labelStyle: TextStyle(
        color: Colors.grey.shade700,
        fontWeight: FontWeight.w500,
        fontSize: 14,
      ),
      floatingLabelStyle: TextStyle(
        color: rotuloFlutuante,
        fontWeight: FontWeight.w700,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: borda,
          width: estado == _EstadoValidacaoDocumento.neutro ? 1 : 1.5,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: bordaFoco, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _erroCampo, width: 1.5),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _erroCampo, width: 2),
      ),
      errorStyle: const TextStyle(
        color: _erroCampo,
        fontSize: 12.5,
        fontWeight: FontWeight.w500,
        height: 1.2,
      ),
    );
  }

  Widget _caixaSecao({
    required String titulo,
    required IconData icone,
    required Widget child,
    String? subtitulo,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: _diPertinRoxo.withValues(alpha: 0.07),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icone, color: _diPertinRoxo, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  titulo,
                  style: const TextStyle(
                    color: _textoPrimario,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
            ],
          ),
          if (subtitulo != null) ...[
            const SizedBox(height: 6),
            Text(
              subtitulo,
              style: const TextStyle(
                color: _textoMuted,
                fontSize: 13,
                height: 1.35,
              ),
            ),
          ],
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  Widget _itemChecklist(String rotulo, bool concluido) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(
            concluido
                ? Icons.check_circle_rounded
                : Icons.radio_button_unchecked_rounded,
            size: 18,
            color: concluido ? Colors.green.shade700 : Colors.grey.shade400,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              rotulo,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: concluido ? Colors.green.shade800 : _textoMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _barraEtapas() {
    final etapaDados = _dadosLojaOk;
    final etapaDocs = _documentosOk;

    Widget bolha(String rotulo, bool ativo, bool concluido) {
      final cor = concluido
          ? Colors.green.shade700
          : (ativo ? _diPertinRoxo : Colors.grey.shade300);
      return Expanded(
        child: Column(
          children: [
            Container(
              height: 4,
              decoration: BoxDecoration(
                color: cor,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              rotulo,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: concluido
                    ? Colors.green.shade800
                    : (ativo ? _diPertinRoxo : _textoMuted),
              ),
            ),
          ],
        ),
      );
    }

    return Row(
      children: [
        bolha('Dados da loja', true, etapaDados),
        const SizedBox(width: 10),
        bolha('Documentos', etapaDados, etapaDocs),
      ],
    );
  }

  String? _validarCampoNome(String? valor) {
    if (_erroCampoNome != null) return _erroCampoNome;
    if ((valor ?? '').trim().isEmpty) {
      return 'Informe o nome fantasia da loja';
    }
    return null;
  }

  String? _validarCampoDocumento(String? valor) {
    if (_erroCampoDocumento != null) return _erroCampoDocumento;
    final texto = (valor ?? '').trim();
    if (texto.isEmpty) {
      return _tipoPessoa == 'CPF'
          ? 'Informe o número do CPF'
          : 'Informe o número do CNPJ';
    }
    if (_tipoPessoa == 'CPF') {
      if (!CpfPerfilUsuario.cpfValido(texto)) {
        return 'CPF inválido. Confira os 11 dígitos.';
      }
    } else if (!CpfPerfilUsuario.cnpjValido(texto)) {
      return 'CNPJ inválido. Confira os 14 dígitos.';
    }
    return null;
  }

  String _nomeArquivoCurto(File arquivo) {
    final nome = arquivo.path.split(Platform.pathSeparator).last;
    if (nome.length <= 28) return nome;
    return '${nome.substring(0, 12)}…${nome.substring(nome.length - 10)}';
  }

  bool _ehPdf(File arquivo) =>
      arquivo.path.split('.').last.toLowerCase() == 'pdf';

  Future<void> _escolherArquivo(int tipoDocumento) async {
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

    if (result != null) {
      setState(() {
        final arquivo = File(result.files.single.path!);
        if (tipoDocumento == 1) {
          _arqDocPessoal = arquivo;
          _erroDocPessoal = null;
        } else if (tipoDocumento == 2) {
          _arqCNPJ = arquivo;
          _erroCnpj = null;
        } else if (tipoDocumento == 3) {
          _arqEndereco = arquivo;
          _erroEndereco = null;
        } else if (tipoDocumento == 4) {
          _arqVitrine = arquivo;
          _erroVitrine = null;
        }
      });
    }
  }

  Future<String> _fazerUpload(
    File arquivo,
    String nomeBase,
    String uid,
  ) async {
    final extensao = arquivo.path.split('.').last.toLowerCase();
    final nomeArquivoComExtensao = '$nomeBase.$extensao';

    final ref = FirebaseStorage.instance.ref().child(
      'documentos_lojistas/$uid/$nomeArquivoComExtensao',
    );
    final uploadTask = await ref.putFile(arquivo);
    return uploadTask.ref.getDownloadURL();
  }

  bool _validarAnexos() {
    var ok = true;
    String? docPessoal;
    String? cnpj;
    String? vitrine;
    String? endereco;

    if (_arqDocPessoal == null) {
      docPessoal = 'Anexe RG ou CNH legível.';
      ok = false;
    }
    if (_tipoPessoa == 'CNPJ' && _arqCNPJ == null) {
      cnpj = 'Anexe o cartão CNPJ ou contrato social.';
      ok = false;
    }
    if (_tipoPessoa == 'CPF' && _arqVitrine == null) {
      vitrine =
          'Anexe foto da vitrine ou local de venda/preparo.';
      ok = false;
    }
    if (_arqEndereco == null) {
      endereco = 'Anexe comprovante de endereço.';
      ok = false;
    }

    setState(() {
      _erroDocPessoal = docPessoal;
      _erroCnpj = cnpj;
      _erroVitrine = vitrine;
      _erroEndereco = endereco;
    });
    return ok;
  }

  Future<void> _enviarSolicitacao() async {
    setState(() {
      _erroCampoNome = null;
      _erroCampoDocumento = null;
    });

    final formOk = _formKey.currentState?.validate() ?? false;
    final anexosOk = _validarAnexos();
    if (!formOk || !anexosOk) return;

    setState(() {
      _isLoading = true;
      _mensagemEnvio = 'Enviando documento 1 de 4…';
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        if (mounted) {
          setState(() => _mensagemEnvio = 'Enviando documento 1 de 4…');
        }
        final urlDocPessoal = await _fazerUpload(
          _arqDocPessoal!,
          'doc_pessoal_${DateTime.now().millisecondsSinceEpoch}',
          user.uid,
        );

        if (mounted) {
          setState(() => _mensagemEnvio = 'Enviando documento 2 de 4…');
        }
        final urlEndereco = await _fazerUpload(
          _arqEndereco!,
          'comprovante_endereco_${DateTime.now().millisecondsSinceEpoch}',
          user.uid,
        );

        var urlCNPJ = '';
        var urlVitrine = '';

        if (_tipoPessoa == 'CNPJ') {
          if (mounted) {
            setState(() => _mensagemEnvio = 'Enviando documento 3 de 4…');
          }
          urlCNPJ = await _fazerUpload(
            _arqCNPJ!,
            'cnpj_${DateTime.now().millisecondsSinceEpoch}',
            user.uid,
          );
        }

        if (_tipoPessoa == 'CPF' && _arqVitrine != null) {
          if (mounted) {
            setState(() => _mensagemEnvio = 'Enviando documento 3 de 4…');
          }
          urlVitrine = await _fazerUpload(
            _arqVitrine!,
            'foto_vitrine_${DateTime.now().millisecondsSinceEpoch}',
            user.uid,
          );
        }

        if (mounted) {
          setState(() => _mensagemEnvio = 'Finalizando solicitação…');
        }

        await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
          'tipo': 'lojista',
          'role': 'lojista',
          'status_loja': 'pendente',
          'loja_nome': _nomeLojaController.text.trim(),
          'loja_tipo_documento': _tipoPessoa,
          'loja_documento': _documentoController.text.trim(),
          'loja_url_doc_pessoal': urlDocPessoal,
          'loja_url_endereco': urlEndereco,
          'loja_url_cnpj': urlCNPJ,
          'loja_url_vitrine': urlVitrine,
          'motivo_recusa': FieldValue.delete(),
          'motivo_recusa_codigo': FieldValue.delete(),
          'motivo_recusa_descricao': FieldValue.delete(),
          'recusa_cadastro': FieldValue.delete(),
          'data_recusa': FieldValue.delete(),
          'bloqueio_cadastro_ate': FieldValue.delete(),
          'status_documentacao': FieldValue.delete(),
          'data_solicitacao_loja': FieldValue.serverTimestamp(),
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Solicitação reenviada com sucesso! Aguarde a nova análise.',
              ),
              backgroundColor: Colors.green,
              behavior: SnackBarBehavior.floating,
            ),
          );
          Navigator.pop(context);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Erro ao enviar solicitação.'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _mensagemEnvio = null;
        });
      }
    }
  }

  Widget _opcaoTipoNegocio({
    required String valor,
    required String titulo,
    required String subtitulo,
    required IconData icone,
  }) {
    final selecionado = _tipoPessoa == valor;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _isLoading
            ? null
            : () {
                setState(() {
                  _tipoPessoa = valor;
                  _documentoController.clear();
                  _erroCampoDocumento = null;
                  if (valor == 'CPF') {
                    _arqCNPJ = null;
                    _erroCnpj = null;
                  } else {
                    _arqVitrine = null;
                    _erroVitrine = null;
                  }
                });
              },
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: selecionado
                ? _diPertinLaranja.withValues(alpha: 0.08)
                : const Color(0xFFF9F8FC),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selecionado ? _diPertinLaranja : const Color(0xFFE0DEE8),
              width: selecionado ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                icone,
                color: selecionado ? _diPertinLaranja : _textoMuted,
                size: 22,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titulo,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        color: selecionado ? _textoPrimario : _textoMuted,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitulo,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.3,
                        color: selecionado
                            ? _textoMuted
                            : Colors.grey.shade500,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                selecionado
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_off_rounded,
                color: selecionado ? _diPertinLaranja : Colors.grey.shade400,
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _cardUpload({
    required String titulo,
    required String dica,
    required File? arquivo,
    required int tipoID,
    String? erro,
  }) {
    final arquivoAnexado = arquivo;
    final anexado = arquivoAnexado != null;
    final ehPdf = anexado && _ehPdf(arquivoAnexado);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: anexado
              ? Colors.green.shade50
              : const Color(0xFFF9F8FC),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: erro != null
                  ? _erroCampo
                  : (anexado
                      ? Colors.green.shade300
                      : const Color(0xFFE0DEE8)),
              width: erro != null || anexado ? 1.5 : 1,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: _isLoading ? null : () => _escolherArquivo(tipoID),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 56),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: anexado
                            ? Colors.green.shade100
                            : _diPertinRoxo.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        anexado
                            ? (ehPdf
                                ? Icons.picture_as_pdf_rounded
                                : Icons.image_rounded)
                            : Icons.upload_file_rounded,
                        color: anexado ? Colors.green.shade700 : _diPertinRoxo,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            titulo,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13.5,
                              color: anexado
                                  ? Colors.green.shade900
                                  : _textoPrimario,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            anexado
                                ? _nomeArquivoCurto(arquivoAnexado)
                                : dica,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.3,
                              color: anexado
                                  ? Colors.green.shade800
                                  : _textoMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      anexado ? 'Trocar' : 'Anexar',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        color: anexado ? _textoMuted : _diPertinLaranja,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (erro != null) ...[
          const SizedBox(height: 6),
          Text(
            erro,
            style: const TextStyle(
              color: _erroCampo,
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
              height: 1.2,
            ),
          ),
        ],
        const SizedBox(height: 10),
      ],
    );
  }

  Widget _buildAlertaRecusa() {
    if (_statusAtual != 'bloqueada' ||
        _motivoRecusa == null ||
        _motivoRecusa!.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        border: Border.all(color: Colors.red.shade200),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.error_outline_rounded, color: Colors.red.shade700),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Cadastro recusado',
                  style: TextStyle(
                    color: Colors.red.shade800,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (_motivoRecusaCodigo != null)
            Text(
              'Classificação: ${LojistaMotivoRecusa.rotulo(_motivoRecusaCodigo!)}',
              style: TextStyle(
                color: Colors.red.shade900,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          if (_motivoRecusaCodigo != null) const SizedBox(height: 6),
          Text(
            _motivoRecusa!,
            style: TextStyle(
              color: Colors.red.shade900,
              fontSize: 13.5,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Corrija os dados abaixo e anexe documentos legíveis para uma nova análise.',
            style: TextStyle(
              color: Colors.red.shade700,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: _diPertinRoxo.withValues(alpha: 0.07),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  _diPertinRoxo.withValues(alpha: 0.12),
                  _diPertinLaranja.withValues(alpha: 0.15),
                ],
              ),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.storefront_rounded,
              size: 36,
              color: _diPertinLaranja,
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'Ser lojista no DiPertin',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: _textoPrimario,
              letterSpacing: -0.5,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Venda para clientes da sua cidade pelo app. '
            'Análise gratuita — envie os documentos abaixo.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: _textoMuted,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 18),
          _barraEtapas(),
        ],
      ),
    );
  }

  Widget _buildFormulario() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildAlertaRecusa(),
          _buildHeroCard(),
          const SizedBox(height: 18),
          _caixaSecao(
            titulo: 'Sua loja',
            icone: Icons.business_rounded,
            subtitulo: 'Como sua loja aparecerá para os clientes',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _nomeLojaController,
                  textCapitalization: TextCapitalization.words,
                  enabled: !_isLoading,
                  onChanged: (_) => setState(() {}),
                  validator: _validarCampoNome,
                  decoration: _decorCampo(
                    'Nome da loja (fantasia)',
                    Icons.store_mall_directory_outlined,
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Tipo de negócio',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13.5,
                    color: _textoPrimario,
                  ),
                ),
                const SizedBox(height: 8),
                _opcaoTipoNegocio(
                  valor: 'CPF',
                  titulo: 'Autônomo (CPF)',
                  subtitulo: 'Vende sozinho — exige foto da vitrine',
                  icone: Icons.person_outline_rounded,
                ),
                const SizedBox(height: 8),
                _opcaoTipoNegocio(
                  valor: 'CNPJ',
                  titulo: 'Empresa (CNPJ)',
                  subtitulo: 'Pessoa jurídica — exige cartão CNPJ',
                  icone: Icons.apartment_rounded,
                ),
                const SizedBox(height: 18),
                TextFormField(
                  key: ValueKey<String>('doc_$_tipoPessoa'),
                  controller: _documentoController,
                  enabled: !_isLoading,
                  onChanged: (_) {
                    setState(() {
                      _erroCampoDocumento = null;
                    });
                  },
                  validator: _validarCampoDocumento,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    if (_tipoPessoa == 'CPF')
                      MaskedInputFormatter('000.000.000-00')
                    else
                      MaskedInputFormatter('00.000.000/0000-00'),
                  ],
                  decoration: _decorCampoDocumento(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _caixaSecao(
            titulo: 'Documentos',
            icone: Icons.folder_open_rounded,
            subtitulo: 'JPG, PNG ou PDF — fotos legíveis e bem iluminadas',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _cardUpload(
                  titulo: 'Documento de identidade',
                  dica: 'RG ou CNH (frente e verso, se aplicável)',
                  arquivo: _arqDocPessoal,
                  tipoID: 1,
                  erro: _erroDocPessoal,
                ),
                if (_tipoPessoa == 'CNPJ')
                  _cardUpload(
                    titulo: 'Cartão CNPJ / Contrato social',
                    dica: 'Documento da empresa legível',
                    arquivo: _arqCNPJ,
                    tipoID: 2,
                    erro: _erroCnpj,
                  ),
                if (_tipoPessoa == 'CPF')
                  _cardUpload(
                    titulo: 'Foto da vitrine / local de venda',
                    dica: 'Comprove onde você vende ou prepara',
                    arquivo: _arqVitrine,
                    tipoID: 4,
                    erro: _erroVitrine,
                  ),
                _cardUpload(
                  titulo: 'Comprovante de endereço',
                  dica: 'Loja ou residência (últimos 90 dias)',
                  arquivo: _arqEndereco,
                  tipoID: 3,
                  erro: _erroEndereco,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE8E6ED)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Antes de enviar',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    color: _textoPrimario,
                  ),
                ),
                const SizedBox(height: 10),
                _itemChecklist(
                  'Nome da loja preenchido',
                  _nomeLojaPreenchido,
                ),
                _itemChecklist(
                  _tipoPessoa == 'CPF' ? 'CPF válido' : 'CNPJ válido',
                  _documentoValido,
                ),
                _itemChecklist(
                  'Todos os anexos obrigatórios',
                  _documentosOk,
                ),
                const SizedBox(height: 14),
                SizedBox(
                  height: 52,
                  child: FilledButton(
                    onPressed: _podeEnviar ? _enviarSolicitacao : null,
                    style: FilledButton.styleFrom(
                      backgroundColor: _diPertinLaranja,
                      disabledBackgroundColor:
                          _diPertinLaranja.withValues(alpha: 0.35),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isLoading
                        ? Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Flexible(
                                child: Text(
                                  _mensagemEnvio ?? 'Enviando…',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ],
                          )
                        : const Text(
                            'Enviar para análise',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.lock_outline_rounded,
                      size: 14,
                      color: Colors.grey.shade500,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        'Seus documentos são analisados com segurança pela equipe DiPertin.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: Colors.grey.shade600,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBloqueioNovaSolicitacao(DateTime dataLiberacao) {
    final formato = DateFormat("dd 'de' MMMM 'de' y", 'pt_BR');
    final dataFormatada = formato.format(dataLiberacao);
    final motivo = (_motivoRecusa ?? '').trim();
    final rotulo = _motivoRecusaCodigo != null
        ? LojistaMotivoRecusa.rotulo(_motivoRecusaCodigo!)
        : null;

    return DiPertinScrollBody(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      child: AnimatedOpacity(
        opacity: _entradaAnimada ? 1 : 0,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: _diPertinRoxo.withValues(alpha: 0.07),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    color: _diPertinRoxo.withValues(alpha: 0.08),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.lock_clock_rounded,
                    size: 56,
                    color: _diPertinRoxo,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Solicitação temporariamente indisponível',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: _diPertinRoxo,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Você poderá solicitar uma nova análise a partir de '
                '$dataFormatada.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  color: Colors.grey.shade700,
                  height: 1.5,
                ),
              ),
              if (rotulo != null || motivo.isNotEmpty) ...[
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    border: Border.all(color: Colors.red.shade200),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.info_outline_rounded,
                            color: Colors.red.shade700,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Motivo informado',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: Colors.red.shade700,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                      if (rotulo != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Classificação: $rotulo',
                          style: TextStyle(
                            color: Colors.red.shade900,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                      ],
                      if (motivo.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          motivo,
                          style: TextStyle(
                            color: Colors.red.shade900,
                            fontSize: 13.5,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 24),
              SizedBox(
                height: 52,
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _diPertinRoxo,
                    side: const BorderSide(color: _diPertinRoxo),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Voltar',
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
    );
  }

  @override
  Widget build(BuildContext context) {
    final bloqueioAte = _bloqueioCadastroAte;
    final bloqueado =
        bloqueioAte != null && bloqueioAte.isAfter(DateTime.now());

    return PopScope(
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        backgroundColor: _fundoTela,
        appBar: AppBar(
          title: const SizedBox.shrink(),
          backgroundColor: _diPertinRoxo,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
          iconTheme: const IconThemeData(color: Colors.white),
        ),
        body: _carregandoInicial
            ? const Center(
                child: CircularProgressIndicator(color: _diPertinLaranja),
              )
            : bloqueado
                ? _buildBloqueioNovaSolicitacao(bloqueioAte)
                : DiPertinScrollBody(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                    child: AnimatedOpacity(
                      opacity: _entradaAnimada ? 1 : 0,
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOut,
                      child: _buildFormulario(),
                    ),
                  ),
      ),
    );
  }
}
