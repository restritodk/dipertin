// Modal do painel: visualizar e editar dados do lojista (espelha o padrão do entregador).

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/painel_admin_theme.dart';

Future<bool?> showLojistaEditarDialog(
  BuildContext context, {
  required String lojistaId,
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => LojistaEditarDialog(lojistaId: lojistaId),
  );
}

class LojistaEditarDialog extends StatefulWidget {
  const LojistaEditarDialog({super.key, required this.lojistaId});

  final String lojistaId;

  @override
  State<LojistaEditarDialog> createState() => _LojistaEditarDialogState();
}

class _LojistaEditarDialogState extends State<LojistaEditarDialog> {
  static const _corBorda = Color(0xFFE2E8F0);
  static const _corSurface = Color(0xFFF8FAFC);

  final _nomeTitular = TextEditingController();
  final _nomeLoja = TextEditingController();
  final _telefone = TextEditingController();
  final _emailDisplay = TextEditingController();
  final _documentoFiscal = TextEditingController();
  final _categoria = TextEditingController();
  final _descricao = TextEditingController();
  final _endereco = TextEditingController();
  final _cidade = TextEditingController();
  final _uf = TextEditingController();
  final _cep = TextEditingController();

  bool _carregando = true;
  bool _salvando = false;
  String? _erroCarregar;

  String _statusLoja = '';
  String _tipoDoc = '';
  String _uidResumo = '';
  String _planoResumo = '';
  String _urlDocPessoal = '';
  String _urlCnpj = '';
  String _urlEndereco = '';
  String _urlVitrine = '';

  String _str(dynamic v) => v == null ? '' : v.toString().trim();

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    _nomeTitular.dispose();
    _nomeLoja.dispose();
    _telefone.dispose();
    _emailDisplay.dispose();
    _documentoFiscal.dispose();
    _categoria.dispose();
    _descricao.dispose();
    _endereco.dispose();
    _cidade.dispose();
    _uf.dispose();
    _cep.dispose();
    super.dispose();
  }

  Future<void> _abrirUrl(String url) async {
    final u = url.trim();
    if (u.isEmpty) return;
    final uri = Uri.tryParse(u);
    if (uri == null) return;
    await launchUrl(uri, webOnlyWindowName: '_blank');
  }

  Future<void> _carregar() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.lojistaId)
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
      if (!mounted) return;
      setState(() {
        final nome0 = _str(d['nome']);
        _nomeTitular.text =
            nome0.isNotEmpty ? nome0 : _str(d['nome_completo']);
        if (_nomeTitular.text.isEmpty) {
          _nomeTitular.text = _str(d['displayName']);
        }
        final ln = _str(d['loja_nome']);
        _nomeLoja.text = ln.isNotEmpty ? ln : _str(d['nome_loja']);
        _telefone.text = _str(d['telefone']);
        if (_telefone.text.isEmpty) {
          _telefone.text = _str(d['whatsapp']);
        }
        _emailDisplay.text = _str(d['email']);
        final tipo = _str(d['loja_tipo_documento']).toUpperCase();
        _tipoDoc = tipo.isNotEmpty ? tipo : '—';
        if (tipo == 'CPF') {
          _documentoFiscal.text = _str(d['cpf']);
        } else {
          _documentoFiscal.text = _str(d['cnpj']);
        }
        if (_documentoFiscal.text.isEmpty) {
          _documentoFiscal.text = _str(d['cpf']);
          if (_documentoFiscal.text.isEmpty) {
            _documentoFiscal.text = _str(d['cnpj']);
          }
        }
        _categoria.text = _str(d['categoria']);
        _descricao.text = _str(d['descricao']);
        _endereco.text = _str(d['endereco']);
        _cidade.text = _str(d['cidade']);
        _uf.text = _str(d['uf']);
        if (_uf.text.isEmpty) {
          _uf.text = _str(d['estado']);
        }
        _cep.text = _str(d['cep']);

        _statusLoja = _str(d['status_loja']);
        _uidResumo = widget.lojistaId;
        final pid = d['plano_taxa_id'];
        _planoResumo = pid == null ? '—' : pid.toString();

        _urlDocPessoal = _str(d['loja_url_doc_pessoal']);
        _urlCnpj = _str(d['loja_url_cnpj']);
        _urlEndereco = _str(d['loja_url_endereco']);
        _urlVitrine = _str(d['loja_url_vitrine']);

        _carregando = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _carregando = false;
          _erroCarregar = '$e';
        });
      }
    }
  }

  InputDecoration _decoracaoCampo({
    required String label,
    IconData? iconePrefix,
    bool readOnly = false,
  }) {
    return InputDecoration(
      labelText: label,
      prefixIcon: iconePrefix != null
          ? Icon(iconePrefix, size: 20, color: PainelAdminTheme.roxo)
          : null,
      filled: true,
      fillColor:
          readOnly ? _corSurface : Colors.white,
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
    TextInputType? keyboardType,
    IconData? icone,
    int maxLines = 1,
    bool readOnly = false,
    List<TextInputFormatter>? formatters,
  }) {
    return TextField(
      controller: c,
      keyboardType: keyboardType,
      maxLines: maxLines,
      readOnly: readOnly,
      inputFormatters: formatters,
      decoration: _decoracaoCampo(
        label: label,
        iconePrefix: icone,
        readOnly: readOnly,
      ),
      style: GoogleFonts.plusJakartaSans(fontSize: 13.5),
    );
  }

  Widget _linhaInfoReadonly({
    required String rotulo,
    required String valor,
    IconData? icone,
  }) {
    final v = valor.trim();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icone != null) ...[
            Icon(icone, size: 18, color: PainelAdminTheme.textoSecundario),
            const SizedBox(width: 10),
          ],
          Expanded(
            flex: 2,
            child: Text(
              rotulo,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: PainelAdminTheme.textoSecundario,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: SelectableText(
              v.isEmpty ? '—' : v,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                color: PainelAdminTheme.dashboardInk,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _linkDocumento(String titulo, String url) {
    final tem = url.trim().isNotEmpty;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(
            Icons.description_outlined,
            size: 18,
            color: tem ? const Color(0xFF3B82F6) : PainelAdminTheme.textoSecundario,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              titulo,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          TextButton(
            onPressed: tem ? () => _abrirUrl(url) : null,
            child: Text(tem ? 'Abrir' : '—'),
          ),
        ],
      ),
    );
  }

  String _normalizarCidadeSimples(String s) {
    var t = s.trim().toLowerCase();
    if (t.isEmpty) return '';
    const mapa = {
      'á': 'a', 'à': 'a', 'ã': 'a', 'â': 'a', 'ä': 'a',
      'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
      'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i',
      'ó': 'o', 'ò': 'o', 'õ': 'o', 'ô': 'o', 'ö': 'o',
      'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u',
      'ç': 'c',
    };
    final buf = StringBuffer();
    for (final r in t.runes) {
      final ch = String.fromCharCode(r);
      buf.write(mapa[ch] ?? ch);
    }
    return buf.toString();
  }

  Future<void> _salvar() async {
    setState(() => _salvando = true);
    try {
      final cidadeTrim = _cidade.text.trim();
      final ufTrim = _uf.text.trim().toUpperCase();
      final patch = <String, dynamic>{
        'nome': _nomeTitular.text.trim(),
        'nome_completo': _nomeTitular.text.trim(),
        'loja_nome': _nomeLoja.text.trim(),
        'nome_loja': _nomeLoja.text.trim(),
        'telefone': _telefone.text.trim(),
        'categoria': _categoria.text.trim(),
        'descricao': _descricao.text.trim(),
        'endereco': _endereco.text.trim(),
        'cidade': cidadeTrim,
        'uf': ufTrim,
        'cep': _cep.text.trim(),
      };

      final tipo = _tipoDoc.toUpperCase();
      if (tipo == 'CPF') {
        patch['cpf'] = _documentoFiscal.text.trim();
      } else if (tipo == 'CNPJ') {
        patch['cnpj'] = _documentoFiscal.text.trim();
      } else {
        final docTxt = _documentoFiscal.text.trim();
        if (docTxt.isNotEmpty) {
          patch['cpf'] = docTxt;
        }
      }

      if (cidadeTrim.isNotEmpty) {
        patch['cidade_normalizada'] = _normalizarCidadeSimples(cidadeTrim);
      }
      if (ufTrim.isNotEmpty) {
        patch['uf_normalizado'] = ufTrim;
      }

      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.lojistaId)
          .update(patch);

      if (mounted) {
        Navigator.pop(context, true);
      }
    } on FirebaseException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e.code == 'permission-denied'
                  ? 'Sem permissão para salvar.'
                  : 'Erro: ${e.message ?? e.code}',
            ),
            backgroundColor: Colors.red.shade800,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao salvar: $e'),
            backgroundColor: Colors.red.shade800,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680, maxHeight: 760),
        child: _carregando
            ? _buildCarregando()
            : _erroCarregar != null
                ? _buildErro()
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

  Widget _buildErro() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline_rounded, color: Colors.red.shade700, size: 32),
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
    final sub = <String>[
      if (_nomeLoja.text.trim().isNotEmpty) _nomeLoja.text.trim(),
      if (_cidade.text.trim().isNotEmpty) _cidade.text.trim(),
    ].join(' · ');

    String uidCurto = _uidResumo;
    if (uidCurto.length > 14) {
      uidCurto =
          '${uidCurto.substring(0, 8)}…${uidCurto.substring(uidCurto.length - 4)}';
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
                  Icons.storefront_rounded,
                  color: PainelAdminTheme.roxo,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Editar loja',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: PainelAdminTheme.dashboardInk,
                      ),
                    ),
                    if (sub.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        sub,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 12.5,
                          color: PainelAdminTheme.textoSecundario,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Fechar',
                onPressed: _salvando ? null : () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
        ),
        const Divider(height: 1, color: _corBorda),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _tituloSecao('REGISTRO'),
                _cartaoSecao(
                  child: Column(
                    children: [
                      _linhaInfoReadonly(
                        rotulo: 'UID',
                        valor: uidCurto,
                        icone: Icons.fingerprint_rounded,
                      ),
                      _linhaInfoReadonly(
                        rotulo: 'E-mail (login)',
                        valor: _emailDisplay.text,
                        icone: Icons.mail_outline_rounded,
                      ),
                      _linhaInfoReadonly(
                        rotulo: 'Status da loja',
                        valor: _statusLoja,
                        icone: Icons.flag_outlined,
                      ),
                      _linhaInfoReadonly(
                        rotulo: 'Tipo de documento',
                        valor: _tipoDoc,
                        icone: Icons.badge_outlined,
                      ),
                      _linhaInfoReadonly(
                        rotulo: 'Plano / taxa (ID)',
                        valor: _planoResumo,
                        icone: Icons.account_balance_wallet_outlined,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                _tituloSecao('TITULAR'),
                _cartaoSecao(
                  child: Column(
                    children: [
                      _campo(
                        label: 'Nome do responsável',
                        c: _nomeTitular,
                        icone: Icons.person_outline_rounded,
                      ),
                      const SizedBox(height: 12),
                      _campo(
                        label: 'Documento (CPF ou CNPJ)',
                        c: _documentoFiscal,
                        icone: Icons.numbers_rounded,
                        keyboardType: TextInputType.text,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                _tituloSecao('LOJA'),
                _cartaoSecao(
                  child: Column(
                    children: [
                      _campo(
                        label: 'Nome da loja',
                        c: _nomeLoja,
                        icone: Icons.store_outlined,
                      ),
                      const SizedBox(height: 12),
                      _campo(
                        label: 'Telefone / WhatsApp',
                        c: _telefone,
                        icone: Icons.phone_outlined,
                        keyboardType: TextInputType.phone,
                      ),
                      const SizedBox(height: 12),
                      _campo(
                        label: 'Categoria',
                        c: _categoria,
                        icone: Icons.category_outlined,
                      ),
                      const SizedBox(height: 12),
                      _campo(
                        label: 'Descrição',
                        c: _descricao,
                        icone: Icons.notes_outlined,
                        maxLines: 4,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                _tituloSecao('LOCALIZAÇÃO'),
                _cartaoSecao(
                  child: Column(
                    children: [
                      _campo(
                        label: 'Endereço completo',
                        c: _endereco,
                        icone: Icons.location_on_outlined,
                        maxLines: 3,
                      ),
                      const SizedBox(height: 12),
                      LayoutBuilder(
                        builder: (context, c) {
                          final largo = c.maxWidth >= 400;
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
                                  label: 'UF',
                                  c: _uf,
                                  icone: Icons.flag_rounded,
                                  formatters: <TextInputFormatter>[
                                    LengthLimitingTextInputFormatter(2),
                                    UpperCaseTxt(),
                                  ],
                                ),
                              ],
                            );
                          }
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                flex: 3,
                                child: _campo(
                                  label: 'Cidade',
                                  c: _cidade,
                                  icone: Icons.location_city_rounded,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _campo(
                                  label: 'UF',
                                  c: _uf,
                                  icone: Icons.flag_rounded,
                                  formatters: <TextInputFormatter>[
                                    LengthLimitingTextInputFormatter(2),
                                    UpperCaseTxt(),
                                  ],
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 12),
                      _campo(
                        label: 'CEP',
                        c: _cep,
                        icone: Icons.markunread_mailbox_outlined,
                        keyboardType: TextInputType.text,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                _tituloSecao('DOCUMENTOS ENVIADOS'),
                _cartaoSecao(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Atalhos para os arquivos do cadastro. Para substituir arquivos, use Documentos no menu da lista.',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 11.5,
                          color: PainelAdminTheme.textoSecundario,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _linkDocumento('Documento pessoal', _urlDocPessoal),
                      if (_tipoDoc.toUpperCase() == 'CPF')
                        _linkDocumento('Foto da vitrine / local', _urlVitrine)
                      else
                        _linkDocumento('CNPJ / contrato social', _urlCnpj),
                      _linkDocumento('Comprovante de endereço', _urlEndereco),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const Divider(height: 1, color: _corBorda),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
          child: Row(
            children: [
              TextButton(
                onPressed: _salvando ? null : () => Navigator.pop(context),
                style: TextButton.styleFrom(
                  foregroundColor: PainelAdminTheme.roxo,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
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

class UpperCaseTxt extends TextInputFormatter {
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
