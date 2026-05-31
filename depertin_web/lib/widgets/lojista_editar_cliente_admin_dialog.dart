import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/painel_admin_theme.dart';

/// Atualiza somente campos do perfil pessoal (cliente) — não altera dados da loja.
Future<bool> updateClientePerfilAdmin({
  required String uid,
  required Map<String, dynamic> patch,
}) async {
  if (patch.isEmpty) return true;
  final p = Map<String, dynamic>.from(patch);
  p['updated_at'] = FieldValue.serverTimestamp();
  final editor = FirebaseAuth.instance.currentUser?.uid;
  if (editor != null && editor.isNotEmpty) {
    p['editado_em'] = FieldValue.serverTimestamp();
    p['editado_por'] = editor;
  }
  await FirebaseFirestore.instance.collection('users').doc(uid).update(p);
  return true;
}

Future<bool?> showLojistaEditarClienteAdminDialog(
  BuildContext context, {
  required String lojistaId,
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => LojistaEditarClienteAdminDialog(lojistaId: lojistaId),
  );
}

class LojistaEditarClienteAdminDialog extends StatefulWidget {
  const LojistaEditarClienteAdminDialog({super.key, required this.lojistaId});

  final String lojistaId;

  @override
  State<LojistaEditarClienteAdminDialog> createState() =>
      _LojistaEditarClienteAdminDialogState();
}

class _LojistaEditarClienteAdminDialogState
    extends State<LojistaEditarClienteAdminDialog> {
  static const _borda = Color(0xFFE2E8F0);

  final _nome = TextEditingController();
  final _telefone = TextEditingController();
  final _cpf = TextEditingController();
  final _email = TextEditingController();
  final _rua = TextEditingController();
  final _numero = TextEditingController();
  final _bairro = TextEditingController();
  final _cidade = TextEditingController();
  final _complemento = TextEditingController();
  final _uf = TextEditingController();

  bool _carregando = true;
  bool _salvando = false;
  bool _cpfBloqueado = false;
  String? _erro;
  String _fotoUrl = '';

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    _nome.dispose();
    _telefone.dispose();
    _cpf.dispose();
    _email.dispose();
    _rua.dispose();
    _numero.dispose();
    _bairro.dispose();
    _cidade.dispose();
    _complemento.dispose();
    _uf.dispose();
    super.dispose();
  }

  String _str(dynamic v) => v == null ? '' : v.toString().trim();

  Future<void> _carregar() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.lojistaId)
          .get();
      if (!snap.exists) {
        setState(() {
          _carregando = false;
          _erro = 'Usuário não encontrado.';
        });
        return;
      }
      final d = snap.data() ?? {};
      _nome.text = _str(d['nome']).isNotEmpty
          ? _str(d['nome'])
          : _str(d['nome_completo']);
      _telefone.text = _str(d['telefone']);
      _cpf.text = _str(d['cpf']);
      _email.text = _str(d['email']);
      _fotoUrl = _str(d['foto_perfil']);
      _cpfBloqueado = d['cpf_alteracao_bloqueada'] == true;

      final end = d['endereco_entrega_padrao'];
      if (end is Map) {
        final m = Map<String, dynamic>.from(end);
        _rua.text = _str(m['rua']);
        _numero.text = _str(m['numero']);
        _bairro.text = _str(m['bairro']);
        _cidade.text = _str(m['cidade']);
        _complemento.text = _str(m['complemento']);
        _uf.text = _str(m['uf']);
        if (_uf.text.isEmpty) _uf.text = _str(m['estado']);
      }

      setState(() => _carregando = false);
    } catch (e) {
      setState(() {
        _carregando = false;
        _erro = '$e';
      });
    }
  }

  InputDecoration _dec(String label, {IconData? icon, String? hint}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon:
          icon != null ? Icon(icon, size: 20, color: PainelAdminTheme.roxo) : null,
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: _borda),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: PainelAdminTheme.roxo, width: 1.4),
      ),
    );
  }

  Future<void> _salvar() async {
    final nomeTxt = _nome.text.trim();
    if (nomeTxt.isEmpty) {
      _snack('Informe o nome do titular.', erro: true);
      return;
    }

    setState(() => _salvando = true);
    try {
      final patch = <String, dynamic>{
        'nome': nomeTxt,
        'nome_completo': nomeTxt,
        'telefone': _telefone.text.trim(),
        'endereco_entrega_padrao': {
          'rua': _rua.text.trim(),
          'numero': _numero.text.trim(),
          'bairro': _bairro.text.trim(),
          'cidade': _cidade.text.trim(),
          'complemento': _complemento.text.trim(),
          'uf': _uf.text.trim().toUpperCase(),
        },
      };

      if (!_cpfBloqueado) {
        final cpf = _cpf.text.replaceAll(RegExp(r'\D'), '');
        if (cpf.isNotEmpty) patch['cpf'] = cpf;
      }

      await updateClientePerfilAdmin(uid: widget.lojistaId, patch: patch);

      if (mounted) Navigator.pop(context, true);
    } on FirebaseException catch (e) {
      _snack(
        e.code == 'permission-denied'
            ? 'Sem permissão para salvar o perfil.'
            : 'Erro: ${e.message ?? e.code}',
        erro: true,
      );
    } catch (e) {
      _snack('Erro ao salvar: $e', erro: true);
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  void _snack(String msg, {bool erro = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: erro ? Colors.red.shade800 : const Color(0xFF15803D),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620, maxHeight: 720),
        child: _carregando
            ? const Padding(
                padding: EdgeInsets.all(48),
                child: Center(child: CircularProgressIndicator()),
              )
            : _erro != null
                ? _buildErro()
                : _buildForm(),
      ),
    );
  }

  Widget _buildErro() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(_erro!, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }

  Widget _buildForm() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _header(
          icone: Icons.person_outline_rounded,
          titulo: 'Editar como Cliente',
          subtitulo: 'Somente dados pessoais da conta',
        ),
        const Divider(height: 1),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: PainelAdminTheme.roxo.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: PainelAdminTheme.roxo.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Text(
                    'Esta tela não altera nome da loja, endereço comercial, '
                    'horários nem tipos de entrega.',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12.5,
                      height: 1.4,
                      color: PainelAdminTheme.dashboardInk,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                if (_fotoUrl.isNotEmpty) ...[
                  Center(
                    child: CircleAvatar(
                      radius: 40,
                      backgroundImage: NetworkImage(_fotoUrl),
                      onBackgroundImageError: (_, _) {},
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Foto de perfil (alteração de imagem pelo app do titular)',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11.5,
                      color: PainelAdminTheme.textoSecundario,
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                TextField(
                  controller: _nome,
                  decoration: _dec('Nome completo', icon: Icons.badge_outlined),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _telefone,
                  keyboardType: TextInputType.phone,
                  decoration: _dec(
                    'Telefone pessoal',
                    icon: Icons.phone_outlined,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _cpf,
                  readOnly: _cpfBloqueado,
                  decoration: _dec(
                    _cpfBloqueado ? 'CPF (bloqueado)' : 'CPF',
                    icon: Icons.numbers_rounded,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _email,
                  readOnly: true,
                  decoration: _dec(
                    'E-mail (login)',
                    icon: Icons.mail_outline_rounded,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Endereço de entrega padrão',
                  style: GoogleFonts.plusJakartaSans(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    color: PainelAdminTheme.roxo,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _rua,
                  decoration: _dec('Rua', icon: Icons.signpost_outlined),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: _numero,
                        decoration: _dec('Número'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: _bairro,
                        decoration: _dec('Bairro'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _complemento,
                  decoration: _dec('Complemento'),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: _cidade,
                        decoration: _dec('Cidade'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _uf,
                        maxLength: 2,
                        textCapitalization: TextCapitalization.characters,
                        inputFormatters: [
                          LengthLimitingTextInputFormatter(2),
                          _UpperCaseFormatter(),
                        ],
                        decoration: _dec('UF'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        _footerSalvar(),
      ],
    );
  }

  Widget _header({
    required IconData icone,
    required String titulo,
    required String subtitulo,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 14),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: PainelAdminTheme.roxo.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icone, color: PainelAdminTheme.roxo),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titulo,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  subtitulo,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12.5,
                    color: PainelAdminTheme.textoSecundario,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: _salvando ? null : () => Navigator.pop(context),
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }

  Widget _footerSalvar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
      child: Row(
        children: [
          TextButton(
            onPressed: _salvando ? null : () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          const Spacer(),
          FilledButton.icon(
            onPressed: _salvando ? null : _salvar,
            style: FilledButton.styleFrom(backgroundColor: PainelAdminTheme.roxo),
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
            label: Text(_salvando ? 'Salvando…' : 'Salvar perfil'),
          ),
        ],
      ),
    );
  }
}

class _UpperCaseFormatter extends TextInputFormatter {
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
