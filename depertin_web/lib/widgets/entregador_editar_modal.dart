// Modal do painel: editar dados do entregador (cadastro, veículo, URLs de documentos).

import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/painel_admin_theme.dart';
import '../utils/admin_perfil.dart';

/// Abre o diálogo de edição; retorna `true` se salvou com sucesso.
Future<bool?> showEntregadorEditarDialog(
  BuildContext context, {
  required String entregadorId,
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => EntregadorEditarDialog(entregadorId: entregadorId),
  );
}

class EntregadorEditarDialog extends StatefulWidget {
  const EntregadorEditarDialog({super.key, required this.entregadorId});

  final String entregadorId;

  @override
  State<EntregadorEditarDialog> createState() => _EntregadorEditarDialogState();
}

class _EntregadorEditarDialogState extends State<EntregadorEditarDialog> {
  final _nome = TextEditingController();
  final _cidade = TextEditingController();
  final _telefone = TextEditingController();
  final _placa = TextEditingController();
  final _modelo = TextEditingController();

  String _veiculoTipo = 'Moto';
  static const _tiposVeiculo = <String>[
    'Bicicleta',
    'Moto',
    'Carro de Passeio',
    'Utilitário / Frete',
  ];

  bool _carregando = true;
  bool _salvando = false;
  String? _erroCarregar;

  String _urlDoc = '';
  String _urlCrlv = '';
  String _urlFotoVeiculo = '';
  // Mantém controle de arquivos recém-selecionados (ainda não salvos) para feedback.
  final Set<String> _alterados = <String>{};

  String? _veiculoAtivoId;

  static const _corBorda = Color(0xFFE2E8F0);
  static const _corSurface = Color(0xFFF8FAFC);

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    _nome.dispose();
    _cidade.dispose();
    _telefone.dispose();
    _placa.dispose();
    _modelo.dispose();
    super.dispose();
  }

  String _str(dynamic v) => v == null ? '' : v.toString().trim();

  String _urlFoto(Map<String, dynamic> d) {
    final a = _str(d['url_foto_veículo']);
    if (a.isNotEmpty) return a;
    return _str(d['url_foto_veiculo']);
  }

  String _placaDeDados(Map<String, dynamic> d) {
    for (final k in ['placa_veiculo', 'placa', 'placaVeiculo']) {
      final s = _str(d[k]);
      if (s.isNotEmpty) return s.toUpperCase();
    }
    return '';
  }

  Future<void> _carregar() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.entregadorId)
          .get();
      if (!snap.exists) {
        if (mounted) {
          setState(() {
            _carregando = false;
            _erroCarregar = 'Usuário não encontrado.';
          });
        }
        return;
      }
      final d = snap.data() ?? {};
      if (mounted) {
        setState(() {
          final nome0 = _str(d['nome']);
          _nome.text =
              nome0.isNotEmpty ? nome0 : _str(d['nome_completo']);
          if (_nome.text.isEmpty) {
            _nome.text = _str(d['displayName']);
          }
          _cidade.text = _str(d['cidade']);
          final tel0 = _str(d['telefone']);
          _telefone.text =
              tel0.isNotEmpty ? tel0 : _str(d['telefone_celular']);
          var vt = _str(d['veiculoTipo']);
          // Compatibilidade legada: 'Carro' → 'Carro de Passeio'
          if (vt == 'Carro') vt = 'Carro de Passeio';
          _veiculoTipo = vt.isNotEmpty ? vt : 'Moto';
          if (!_tiposVeiculo.contains(_veiculoTipo)) {
            _veiculoTipo = 'Moto';
          }
          _placa.text = _placaDeDados(d);
          _modelo.text = _str(d['veiculoModelo']);
          _urlDoc = _str(d['url_doc_pessoal']);
          _urlCrlv = _str(d['url_crlv']);
          _urlFotoVeiculo = _urlFoto(d);
          _veiculoAtivoId = _str(d['veiculo_ativo_id']).isEmpty
              ? null
              : _str(d['veiculo_ativo_id']);
          _carregando = false;
        });
      }

      // Se existe veículo ativo na subcoleção, preferir placa/modelo/tipo de lá.
      final vid = _veiculoAtivoId;
      if (vid != null) {
        final vSnap = await FirebaseFirestore.instance
            .collection('users')
            .doc(widget.entregadorId)
            .collection('veiculos')
            .doc(vid)
            .get();
        if (vSnap.exists && mounted) {
          final v = vSnap.data() ?? {};
          setState(() {
            final tipoCodigo = _str(v['tipo']).toLowerCase();
            if (tipoCodigo == 'carro_frete') {
              _veiculoTipo = 'Utilitário / Frete';
            } else if (tipoCodigo == 'carro') {
              _veiculoTipo = 'Carro de Passeio';
            } else if (tipoCodigo == 'bike') {
              _veiculoTipo = 'Bicicleta';
            } else {
              _veiculoTipo = 'Moto';
            }
            final pm = _str(v['modelo']);
            final pp = _str(v['placa']);
            if (pm.isNotEmpty) _modelo.text = pm;
            if (pp.isNotEmpty) _placa.text = pp.toUpperCase();
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _carregando = false;
          _erroCarregar = '$e';
        });
      }
    }
  }

  String _tipoCodigoSubcolecao(String painel) {
    switch (painel) {
      case 'Bicicleta':
        return 'bike';
      case 'Moto':
        return 'moto';
      case 'Carro de Passeio':
        return 'carro';
      case 'Utilitário / Frete':
        return 'carro_frete';
      default:
        return 'moto';
    }
  }

  String _mimeFromExt(String ext) {
    switch (ext.toLowerCase()) {
      case 'pdf':
        return 'application/pdf';
      case 'png':
        return 'image/png';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'webp':
        return 'image/webp';
      default:
        return 'application/octet-stream';
    }
  }

  Future<String?> _pickAndUpload({
    required String prefix,
  }) async {
    final r = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'pdf', 'webp'],
      withData: true,
    );
    if (r == null || r.files.isEmpty) return null;
    final f = r.files.single;
    final Uint8List? bytes = f.bytes;
    if (bytes == null) {
      if (mounted) {
        mostrarSnackPainel(context,
            erro: true,
            mensagem:
                'Não foi possível ler o arquivo (tente outro navegador ou formato).');
      }
      return null;
    }
    if (bytes.length > 20 * 1024 * 1024) {
      if (mounted) {
        mostrarSnackPainel(context,
            erro: true, mensagem: 'Arquivo maior que 20 MB.');
      }
      return null;
    }
    final ext = (f.extension ?? 'bin').toLowerCase();
    final nomeArquivo =
        'painel_${prefix}_${DateTime.now().millisecondsSinceEpoch}.$ext';
    final ref = FirebaseStorage.instance
        .ref()
        .child('documentos_entregadores/${widget.entregadorId}/$nomeArquivo');
    await ref.putData(bytes, SettableMetadata(contentType: _mimeFromExt(ext)));
    return ref.getDownloadURL();
  }

  Future<void> _trocarDoc(String chave) async {
    final prefix = chave == 'doc'
        ? 'cnh_rg'
        : chave == 'crlv'
            ? 'crlv'
            : 'foto_veiculo';
    try {
      final url = await _pickAndUpload(prefix: prefix);
      if (url == null || !mounted) return;
      setState(() {
        if (chave == 'doc') {
          _urlDoc = url;
        } else if (chave == 'crlv') {
          _urlCrlv = url;
        } else {
          _urlFotoVeiculo = url;
        }
        _alterados.add(chave);
      });
      mostrarSnackPainel(context,
          mensagem: 'Arquivo selecionado. Clique em "Salvar alterações" para gravar.');
    } catch (e) {
      if (mounted) {
        mostrarSnackPainel(context,
            erro: true, mensagem: 'Upload falhou: $e');
      }
    }
  }

  Future<void> _salvar() async {
    final nome = _nome.text.trim();
    if (nome.isEmpty) {
      mostrarSnackPainel(context, erro: true, mensagem: 'Informe o nome.');
      return;
    }
    final placaNorm =
        _placa.text.replaceAll('-', '').replaceAll(' ', '').trim().toUpperCase();
    if (_veiculoTipo != 'Bicicleta' && placaNorm.isNotEmpty) {
      final ok = RegExp(r'^[A-Z]{3}[0-9][A-Z0-9][0-9]{2}$').hasMatch(placaNorm);
      if (!ok) {
        mostrarSnackPainel(context,
            erro: true,
            mensagem: 'Placa inválida (use Mercosul ABC1D23 ou antiga ABC1234).');
        return;
      }
    }

    setState(() => _salvando = true);
    try {
      final uid = widget.entregadorId;
      final ref = FirebaseFirestore.instance.collection('users').doc(uid);
      final update = <String, dynamic>{
        'nome': nome,
        'cidade': _cidade.text.trim(),
        'telefone': _telefone.text.trim(),
        'veiculoTipo': _veiculoTipo,
        'veiculoModelo': _modelo.text.trim(),
        'placa_veiculo': _veiculoTipo == 'Bicicleta' ? '' : placaNorm,
        'placa': _veiculoTipo == 'Bicicleta' ? '' : placaNorm,
        'url_doc_pessoal': _urlDoc,
        'url_crlv': _veiculoTipo == 'Bicicleta' ? '' : _urlCrlv,
        'url_foto_veículo': _urlFotoVeiculo,
      };
      await ref.update(update);

      final vid = _veiculoAtivoId;
      if (vid != null && vid.isNotEmpty) {
        await ref.collection('veiculos').doc(vid).set({
          'tipo': _tipoCodigoSubcolecao(_veiculoTipo),
          'modelo': _modelo.text.trim(),
          'placa': _veiculoTipo == 'Bicicleta' ? '' : placaNorm,
          'atualizado_em': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        if (_veiculoTipo != 'Bicicleta' && _urlCrlv.isNotEmpty) {
          await ref
              .collection('veiculos')
              .doc(vid)
              .collection('documentos')
              .doc('crlv')
              .set({
            'url': _urlCrlv,
            'status': 'pendente',
            'atualizado_em': FieldValue.serverTimestamp(),
            'origem': 'painel_web',
          }, SetOptions(merge: true));
        }
      }

      if (_urlDoc.isNotEmpty) {
        await ref.collection('documentos').doc('cnh').set({
          'url': _urlDoc,
          'status': 'pendente',
          'atualizado_em': FieldValue.serverTimestamp(),
          'origem': 'painel_web',
        }, SetOptions(merge: true));
      }

      if (mounted) {
        mostrarSnackPainel(context, mensagem: 'Dados do entregador atualizados.');
        Navigator.of(context).pop(true);
      }
    } on FirebaseException catch (e) {
      if (mounted) {
        final det = (e.message != null && e.message!.trim().isNotEmpty)
            ? e.message!.trim()
            : e.code;
        mostrarSnackPainel(context,
            erro: true,
            mensagem: e.code == 'permission-denied' ? 'Sem permissão.' : det);
      }
    } catch (e) {
      if (mounted) {
        mostrarSnackPainel(
            context, erro: true, mensagem: 'Erro: ${e.toString()}');
      }
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  // ---------- Componentes de UI ----------

  InputDecoration _decoracaoCampo({
    required String label,
    String? prefix,
    IconData? iconePrefix,
  }) {
    return InputDecoration(
      labelText: label,
      prefixText: prefix,
      prefixIcon: iconePrefix == null
          ? null
          : Icon(iconePrefix,
              size: 18, color: PainelAdminTheme.textoSecundario),
      isDense: true,
      filled: true,
      fillColor: Colors.white,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      labelStyle: GoogleFonts.plusJakartaSans(
        fontSize: 13,
        color: PainelAdminTheme.textoSecundario,
      ),
      floatingLabelStyle: GoogleFonts.plusJakartaSans(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: PainelAdminTheme.roxo,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: _corBorda),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: PainelAdminTheme.roxo, width: 1.4),
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: _corBorda),
      ),
    );
  }

  Widget _tituloSecao(String texto) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, top: 4),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 14,
            decoration: BoxDecoration(
              color: PainelAdminTheme.roxo,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            texto,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              color: PainelAdminTheme.roxo,
              letterSpacing: 0.6,
            ),
          ),
        ],
      ),
    );
  }

  Widget _cartaoSecao({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _corBorda),
      ),
      child: child,
    );
  }

  Widget _campo({
    required String label,
    required TextEditingController c,
    List<TextInputFormatter>? formatters,
    TextInputType? keyboardType,
    IconData? icone,
  }) {
    return TextField(
      controller: c,
      inputFormatters: formatters,
      keyboardType: keyboardType,
      decoration: _decoracaoCampo(label: label, iconePrefix: icone),
      style: GoogleFonts.plusJakartaSans(fontSize: 13.5),
    );
  }

  Widget _dropdownVeiculo() {
    return DropdownButtonFormField<String>(
      value: _veiculoTipo,
      decoration: _decoracaoCampo(
        label: 'Categoria do veículo',
        iconePrefix: Icons.two_wheeler_rounded,
      ),
      style: GoogleFonts.plusJakartaSans(
        fontSize: 13.5,
        color: PainelAdminTheme.dashboardInk,
      ),
      icon: Icon(Icons.expand_more_rounded,
          color: PainelAdminTheme.textoSecundario),
      items: _tiposVeiculo
          .map((e) => DropdownMenuItem(
                value: e,
                child: Text(e),
              ))
          .toList(),
      onChanged: (v) {
        if (v != null) {
          setState(() => _veiculoTipo = v);
        }
      },
    );
  }

  Widget _linhaDoc({
    required String chave,
    required String titulo,
    required String url,
    required VoidCallback onTrocar,
  }) {
    final temArquivo = url.trim().isNotEmpty;
    final foiAlterado = _alterados.contains(chave);
    final ehPdf = url.toLowerCase().contains('.pdf');

    return Container(
      padding: const EdgeInsets.all(10),
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        color: _corSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _corBorda),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _thumbDoc(url: url, temArquivo: temArquivo, ehPdf: ehPdf),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        titulo,
                        style: GoogleFonts.plusJakartaSans(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: PainelAdminTheme.dashboardInk,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (foiAlterado) _pillStatus(
                      cor: const Color(0xFF059669),
                      fundo: const Color(0xFFD1FAE5),
                      texto: 'Novo',
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  !temArquivo
                      ? 'Nenhum arquivo enviado'
                      : foiAlterado
                          ? 'Arquivo selecionado — salve para enviar'
                          : 'Arquivo cadastrado',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11.5,
                    color: PainelAdminTheme.textoSecundario,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          OutlinedButton.icon(
            onPressed: onTrocar,
            icon: Icon(
              temArquivo
                  ? Icons.swap_horiz_rounded
                  : Icons.upload_file_rounded,
              size: 16,
            ),
            label: Text(temArquivo ? 'Trocar' : 'Enviar'),
            style: OutlinedButton.styleFrom(
              foregroundColor: PainelAdminTheme.roxo,
              side: BorderSide(
                color: PainelAdminTheme.roxo.withValues(alpha: 0.35),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              minimumSize: const Size(0, 34),
              visualDensity: VisualDensity.compact,
              textStyle: GoogleFonts.plusJakartaSans(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _thumbDoc({
    required String url,
    required bool temArquivo,
    required bool ehPdf,
  }) {
    Widget conteudo;
    if (!temArquivo) {
      conteudo = Icon(
        Icons.insert_drive_file_outlined,
        color: PainelAdminTheme.textoSecundario.withValues(alpha: 0.6),
        size: 24,
      );
    } else if (ehPdf) {
      conteudo = Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.picture_as_pdf_rounded,
              color: PainelAdminTheme.roxo, size: 24),
          const SizedBox(height: 2),
          Text('PDF',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: PainelAdminTheme.roxo,
              )),
        ],
      );
    } else {
      conteudo = ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(
          url,
          width: 48,
          height: 48,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) =>
              Icon(Icons.broken_image_rounded,
                  color: PainelAdminTheme.textoSecundario, size: 22),
        ),
      );
    }

    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _corBorda),
      ),
      alignment: Alignment.center,
      child: conteudo,
    );
  }

  Widget _pillStatus({
    required Color cor,
    required Color fundo,
    required String texto,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: fundo,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        texto,
        style: GoogleFonts.plusJakartaSans(
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          color: cor,
        ),
      ),
    );
  }

  // ---------- Build ----------

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding:
          const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 740),
        child: _carregando
            ? _buildCarregando()
            : _erroCarregar != null
                ? _buildErroCarregar()
                : _buildFormulario(),
      ),
    );
  }

  Widget _buildCarregando() {
    return const Padding(
      padding: EdgeInsets.all(56),
      child: Center(
        child: SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(strokeWidth: 2.6),
        ),
      ),
    );
  }

  Widget _buildErroCarregar() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline_rounded,
              color: Colors.red.shade700, size: 32),
          const SizedBox(height: 10),
          Text(
            _erroCarregar!,
            textAlign: TextAlign.center,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              color: PainelAdminTheme.dashboardInk,
            ),
          ),
          const SizedBox(height: 16),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }

  Widget _buildFormulario() {
    final nomeSubtitulo = _nome.text.trim();
    final cidadeSubtitulo = _cidade.text.trim();
    final metaHeader = <String>[
      if (nomeSubtitulo.isNotEmpty) nomeSubtitulo,
      if (cidadeSubtitulo.isNotEmpty) cidadeSubtitulo,
    ].join(' · ');

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 10, 14),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: PainelAdminTheme.roxo.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.edit_rounded,
                  color: PainelAdminTheme.roxo,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Editar entregador',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: PainelAdminTheme.dashboardInk,
                      ),
                    ),
                    if (metaHeader.isNotEmpty) const SizedBox(height: 2),
                    if (metaHeader.isNotEmpty)
                      Text(
                        metaHeader,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 12.5,
                          color: PainelAdminTheme.textoSecundario,
                        ),
                      ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Fechar',
                onPressed:
                    _salvando ? null : () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
        ),
        const Divider(height: 1, color: _corBorda),

        // Corpo
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Seção: Dados gerais
                _tituloSecao('DADOS GERAIS'),
                _cartaoSecao(
                  child: Column(
                    children: [
                      _campo(
                        label: 'Nome',
                        c: _nome,
                        icone: Icons.person_outline_rounded,
                      ),
                      const SizedBox(height: 12),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final largo = constraints.maxWidth >= 420;
                          if (!largo) {
                            return Column(
                              children: [
                                _campo(
                                  label: 'Cidade',
                                  c: _cidade,
                                  icone: Icons.location_city_rounded,
                                ),
                                const SizedBox(height: 12),
                                _campo(
                                  label: 'Telefone',
                                  c: _telefone,
                                  icone: Icons.phone_outlined,
                                  keyboardType: TextInputType.phone,
                                ),
                              ],
                            );
                          }
                          return Row(
                            children: [
                              Expanded(
                                child: _campo(
                                  label: 'Cidade',
                                  c: _cidade,
                                  icone: Icons.location_city_rounded,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _campo(
                                  label: 'Telefone',
                                  c: _telefone,
                                  icone: Icons.phone_outlined,
                                  keyboardType: TextInputType.phone,
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 18),

                // Seção: Veículo
                _tituloSecao('VEÍCULO'),
                _cartaoSecao(
                  child: Column(
                    children: [
                      _dropdownVeiculo(),
                      const SizedBox(height: 12),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final largo = constraints.maxWidth >= 420;
                          final campos = [
                            _campo(
                              label: 'Modelo',
                              c: _modelo,
                              icone: Icons.local_shipping_outlined,
                            ),
                            if (_veiculoTipo != 'Bicicleta')
                              _campo(
                                label: 'Placa',
                                c: _placa,
                                icone: Icons.confirmation_number_outlined,
                                formatters: [
                                  LengthLimitingTextInputFormatter(7),
                                  FilteringTextInputFormatter.allow(
                                    RegExp(r'[A-Za-z0-9]'),
                                  ),
                                  _UpperCaseTextFormatter(),
                                ],
                              ),
                          ];
                          if (!largo || campos.length < 2) {
                            return Column(
                              children: [
                                for (int i = 0; i < campos.length; i++) ...[
                                  if (i > 0) const SizedBox(height: 12),
                                  campos[i],
                                ],
                              ],
                            );
                          }
                          return Row(
                            children: [
                              Expanded(child: campos[0]),
                              const SizedBox(width: 12),
                              Expanded(child: campos[1]),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 18),

                // Seção: Documentos
                _tituloSecao('DOCUMENTOS'),
                _cartaoSecao(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.info_outline_rounded,
                              size: 16,
                              color: PainelAdminTheme.textoSecundario),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'PDF ou imagem (máx. 20 MB). Os arquivos só serão gravados ao clicar em "Salvar alterações".',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 11.5,
                                color: PainelAdminTheme.textoSecundario,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                      _linhaDoc(
                        chave: 'doc',
                        titulo: 'CNH / Documento pessoal',
                        url: _urlDoc,
                        onTrocar: () => _trocarDoc('doc'),
                      ),
                      if (_veiculoTipo != 'Bicicleta')
                        _linhaDoc(
                          chave: 'crlv',
                          titulo: 'CRLV do veículo',
                          url: _urlCrlv,
                          onTrocar: () => _trocarDoc('crlv'),
                        ),
                      _linhaDoc(
                        chave: 'foto',
                        titulo: 'Foto do veículo',
                        url: _urlFotoVeiculo,
                        onTrocar: () => _trocarDoc('foto'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),

        const Divider(height: 1, color: _corBorda),
        // Rodapé
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
          child: Row(
            children: [
              TextButton(
                onPressed:
                    _salvando ? null : () => Navigator.pop(context),
                style: TextButton.styleFrom(
                  foregroundColor: PainelAdminTheme.roxo,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                  textStyle: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                child: const Text('Cancelar'),
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: _salvando ? null : _salvar,
                icon: _salvando
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.save_rounded, size: 18),
                label: Text(
                  _salvando ? 'Salvando…' : 'Salvar alterações',
                  style: GoogleFonts.plusJakartaSans(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: PainelAdminTheme.laranja,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 18, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return TextEditingValue(
      text: newValue.text.toUpperCase(),
      selection: newValue.selection,
    );
  }
}
