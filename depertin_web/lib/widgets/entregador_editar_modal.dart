// Modal do painel: editar dados do entregador (cadastro, veículo, URLs de documentos).

import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
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
  static const _tiposVeiculo = ['Moto', 'Carro', 'Bicicleta'];

  bool _carregando = true;
  bool _salvando = false;
  String? _erroCarregar;

  String _urlDoc = '';
  String _urlCrlv = '';
  String _urlFotoVeiculo = '';

  String? _veiculoAtivoId;

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
          final vt = _str(d['veiculoTipo']);
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
            if (tipoCodigo == 'carro') {
              _veiculoTipo = 'Carro';
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
      case 'Carro':
        return 'carro';
      case 'Bicicleta':
        return 'bike';
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
      });
      mostrarSnackPainel(context, mensagem: 'Arquivo selecionado. Salve para gravar.');
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

  Widget _secTitulo(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8, top: 4),
        child: Text(
          t,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: PainelAdminTheme.roxo,
            letterSpacing: 0.4,
          ),
        ),
      );

  Widget _campo({
    required String label,
    required TextEditingController c,
    int maxLines = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: c,
        maxLines: maxLines,
        decoration: InputDecoration(
          labelText: label,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          isDense: true,
        ),
      ),
    );
  }

  Widget _linhaDoc(String titulo, String url, VoidCallback onTrocar) {
    return Container(
      padding: const EdgeInsets.all(10),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titulo,
                    style: GoogleFonts.plusJakartaSans(
                        fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 4),
                Text(
                  url.isEmpty ? 'Nenhum arquivo' : 'Arquivo definido (URL salva ao gravar)',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    color: PainelAdminTheme.textoSecundario,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          OutlinedButton.icon(
            onPressed: onTrocar,
            icon: const Icon(Icons.upload_file_rounded, size: 18),
            label: const Text('Trocar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 720),
        child: _carregando
            ? const Padding(
                padding: EdgeInsets.all(48),
                child: Center(child: CircularProgressIndicator()),
              )
            : _erroCarregar != null
                ? Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_erroCarregar!,
                            style: const TextStyle(color: Colors.red)),
                        const SizedBox(height: 16),
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Fechar'),
                        ),
                      ],
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 18, 8, 8),
                        child: Row(
                          children: [
                            Icon(Icons.edit_rounded,
                                color: PainelAdminTheme.roxo, size: 26),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Editar entregador',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            IconButton(
                              onPressed: _salvando
                                  ? null
                                  : () => Navigator.pop(context),
                              icon: const Icon(Icons.close_rounded),
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1),
                      Expanded(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _secTitulo('DADOS GERAIS'),
                              _campo(label: 'Nome', c: _nome),
                              _campo(label: 'Cidade', c: _cidade),
                              _campo(label: 'Telefone', c: _telefone),
                              _secTitulo('VEÍCULO'),
                              DropdownButtonFormField<String>(
                                value: _veiculoTipo,
                                decoration: InputDecoration(
                                  labelText: 'Tipo de veículo',
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  isDense: true,
                                ),
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
                              ),
                              const SizedBox(height: 10),
                              _campo(label: 'Modelo', c: _modelo),
                              if (_veiculoTipo != 'Bicicleta')
                                _campo(label: 'Placa', c: _placa),
                              _secTitulo('DOCUMENTOS'),
                              Text(
                                'Envie PDF ou imagem (máx. 20 MB). Use Salvar para gravar no cadastro.',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 11.5,
                                  color: PainelAdminTheme.textoSecundario,
                                  height: 1.35,
                                ),
                              ),
                              const SizedBox(height: 8),
                              _linhaDoc(
                                'CNH / documento pessoal',
                                _urlDoc,
                                () => _trocarDoc('doc'),
                              ),
                              if (_veiculoTipo != 'Bicicleta')
                                _linhaDoc(
                                  'CRLV',
                                  _urlCrlv,
                                  () => _trocarDoc('crlv'),
                                ),
                              _linhaDoc(
                                'Foto do veículo',
                                _urlFotoVeiculo,
                                () => _trocarDoc('foto'),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const Divider(height: 1),
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            TextButton(
                              onPressed:
                                  _salvando ? null : () => Navigator.pop(context),
                              child: const Text('Cancelar'),
                            ),
                            const Spacer(),
                            FilledButton(
                              onPressed: _salvando ? null : _salvar,
                              style: FilledButton.styleFrom(
                                backgroundColor: PainelAdminTheme.laranja,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 20, vertical: 12),
                              ),
                              child: _salvando
                                  ? Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Text(
                                          'Salvando…',
                                          style: GoogleFonts.plusJakartaSans(
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ],
                                    )
                                  : Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.save_rounded, size: 20),
                                        const SizedBox(width: 8),
                                        Text(
                                          'Salvar alterações',
                                          style: GoogleFonts.plusJakartaSans(
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ],
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
}
