import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:depertin_web/constants/tipos_entrega.dart';
import 'package:depertin_web/utils/loja_pausa.dart';
import 'package:depertin_web/widgets/loja_pausa_motivo_dialog.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/painel_admin_theme.dart';

/// Atualiza somente configurações da loja — não altera nome pessoal, CPF nem endereço de entrega.
Future<bool> updateLojaConfiguracoesAdmin({
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

Future<bool?> showLojistaEditarLojaAdminDialog(
  BuildContext context, {
  required String lojistaId,
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => LojistaEditarLojaAdminDialog(lojistaId: lojistaId),
  );
}

class LojistaEditarLojaAdminDialog extends StatefulWidget {
  const LojistaEditarLojaAdminDialog({super.key, required this.lojistaId});

  final String lojistaId;

  @override
  State<LojistaEditarLojaAdminDialog> createState() =>
      _LojistaEditarLojaAdminDialogState();
}

class _LojistaEditarLojaAdminDialogState extends State<LojistaEditarLojaAdminDialog> {
  static const _borda = Color(0xFFE2E8F0);
  static const _muted = PainelAdminTheme.textoSecundario;

  final _nomeLoja = TextEditingController();
  final _endereco = TextEditingController();
  final _telefone = TextEditingController();
  final _cidade = TextEditingController();
  final _uf = TextEditingController();

  final Map<String, String> _nomesDias = const {
    'segunda': 'Segunda',
    'terca': 'Terça',
    'quarta': 'Quarta',
    'quinta': 'Quinta',
    'sexta': 'Sexta',
    'sabado': 'Sábado',
    'domingo': 'Domingo',
  };

  late Map<String, Map<String, dynamic>> _horarios;
  Set<String> _tiposEntrega = {};
  bool _pausadoManual = false;
  String? _pausaMotivo;
  Timestamp? _pausaVoltaAt;

  bool _carregando = true;
  bool _salvando = false;
  String? _erro;

  @override
  void initState() {
    super.initState();
    _horarios = _horariosPadrao();
    _carregar();
  }

  @override
  void dispose() {
    _nomeLoja.dispose();
    _endereco.dispose();
    _telefone.dispose();
    _cidade.dispose();
    _uf.dispose();
    super.dispose();
  }

  Map<String, Map<String, dynamic>> _horariosPadrao() => {
        'segunda': {'ativo': true, 'abre': '08:00', 'fecha': '18:00'},
        'terca': {'ativo': true, 'abre': '08:00', 'fecha': '18:00'},
        'quarta': {'ativo': true, 'abre': '08:00', 'fecha': '18:00'},
        'quinta': {'ativo': true, 'abre': '08:00', 'fecha': '18:00'},
        'sexta': {'ativo': true, 'abre': '08:00', 'fecha': '18:00'},
        'sabado': {'ativo': true, 'abre': '08:00', 'fecha': '12:00'},
        'domingo': {'ativo': false, 'abre': '08:00', 'fecha': '12:00'},
      };

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
      _nomeLoja.text =
          _str(d['loja_nome']).isNotEmpty ? _str(d['loja_nome']) : _str(d['nome_loja']);
      _endereco.text = _str(d['endereco']);
      _telefone.text = _str(d['telefone']);
      _cidade.text = _str(d['cidade']);
      _uf.text = _str(d['uf']);

      _horarios = _horariosPadrao();
      if (d['horarios'] is Map) {
        final h = Map<String, dynamic>.from(d['horarios'] as Map);
        for (final k in _horarios.keys) {
          if (h[k] is Map) {
            _horarios[k] = Map<String, dynamic>.from(h[k] as Map);
          }
        }
      }

      _tiposEntrega = TiposEntrega.lerDeDoc(d).toSet();
      _pausadoManual = LojaPausa.lojaEfetivamentePausada(d);
      _pausaMotivo = _pausadoManual ? d['pausa_motivo']?.toString() : null;
      _pausaVoltaAt = _pausadoManual && d['pausa_volta_at'] is Timestamp
          ? d['pausa_volta_at'] as Timestamp
          : null;

      setState(() => _carregando = false);
    } catch (e) {
      setState(() {
        _carregando = false;
        _erro = '$e';
      });
    }
  }

  int _minutos(String hhmm) {
    final p = hhmm.split(':');
    if (p.length < 2) return 0;
    return (int.tryParse(p[0]) ?? 0) * 60 + (int.tryParse(p[1]) ?? 0);
  }

  bool _horariosOk() {
    for (final e in _horarios.entries) {
      final c = e.value;
      if (c['ativo'] != true) continue;
      if (_minutos(c['abre'].toString()) >= _minutos(c['fecha'].toString())) {
        return false;
      }
    }
    return true;
  }

  String _normalizarCidade(String s) {
    var t = s.trim().toLowerCase();
    if (t.isEmpty) return '';
    const mapa = {
      'á': 'a', 'à': 'a', 'ã': 'a', 'â': 'a',
      'é': 'e', 'è': 'e', 'ê': 'e',
      'í': 'i', 'ì': 'i',
      'ó': 'o', 'ò': 'o', 'õ': 'o', 'ô': 'o',
      'ú': 'u', 'ù': 'u',
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
    if (_endereco.text.trim().isEmpty) {
      _snack('Informe o endereço da loja.', erro: true);
      return;
    }
    if (!_horariosOk()) {
      _snack(
        'Em algum dia ativo, abertura deve ser antes do fechamento.',
        erro: true,
      );
      return;
    }
    if (_tiposEntrega.isEmpty) {
      _snack('Selecione ao menos um tipo de entrega.', erro: true);
      return;
    }

    setState(() => _salvando = true);
    try {
      final patch = <String, dynamic>{
        'loja_nome': _nomeLoja.text.trim(),
        'endereco': _endereco.text.trim(),
        'telefone': _telefone.text.trim(),
        'horarios': _horarios,
        'tipos_entrega_permitidos':
            TiposEntrega.paraFirestore(_tiposEntrega.toList()),
        'tipos_entrega_atualizado_em': FieldValue.serverTimestamp(),
      };

      if (!_pausadoManual) {
        patch['pausado_manualmente'] = false;
        patch['pausa_motivo'] = FieldValue.delete();
        patch['pausa_volta_at'] = FieldValue.delete();
      } else {
        patch['pausado_manualmente'] = true;
        patch['pausa_motivo'] = _pausaMotivo;
        if (_pausaMotivo == PausaMotivoLoja.almoco && _pausaVoltaAt != null) {
          patch['pausa_volta_at'] = _pausaVoltaAt;
        } else {
          patch['pausa_volta_at'] = FieldValue.delete();
        }
      }

      final cid = _cidade.text.trim();
      final uf = _uf.text.trim().toUpperCase();
      if (cid.isNotEmpty) {
        patch['cidade'] = cid;
        patch['cidade_normalizada'] = _normalizarCidade(cid);
      }
      if (uf.isNotEmpty) {
        patch['uf'] = uf;
        patch['uf_normalizado'] = uf;
      }

      await updateLojaConfiguracoesAdmin(uid: widget.lojistaId, patch: patch);

      if (mounted) Navigator.pop(context, true);
    } on FirebaseException catch (e) {
      _snack(
        e.code == 'permission-denied'
            ? 'Sem permissão para salvar a loja.'
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

  Future<void> _aoMudarPausa(bool v) async {
    if (!v) {
      setState(() {
        _pausadoManual = false;
        _pausaMotivo = null;
        _pausaVoltaAt = null;
      });
      return;
    }
    final escolha = await showLojaPausaMotivoDialog(
      context,
      accent: PainelAdminTheme.roxo,
    );
    if (escolha == null || !mounted) return;
    setState(() {
      _pausadoManual = true;
      _pausaMotivo = escolha.motivo;
      _pausaVoltaAt = escolha.pausaVoltaAt;
    });
  }

  Future<void> _pickHora(String dia, bool abre) async {
    final cfg = _horarios[dia]!;
    final cur = (abre ? cfg['abre'] : cfg['fecha']).toString();
    final p = cur.split(':');
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: int.tryParse(p.isNotEmpty ? p[0] : '8') ?? 8,
        minute: int.tryParse(p.length > 1 ? p[1] : '0') ?? 0,
      ),
    );
    if (picked != null) {
      setState(() {
        cfg[abre ? 'abre' : 'fecha'] =
            '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
      });
    }
  }

  InputDecoration _dec(String label, {IconData? icon}) {
    return InputDecoration(
      labelText: label,
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

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 720,
          maxHeight: MediaQuery.sizeOf(context).height * 0.9,
        ),
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
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: PainelAdminTheme.laranja.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.storefront_rounded,
                  color: PainelAdminTheme.laranja,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Editar como Lojista',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      'Configurações da loja (painel lojista)',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12.5,
                        color: _muted,
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
        ),
        const Divider(height: 1),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: PainelAdminTheme.laranja.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: PainelAdminTheme.laranja.withValues(alpha: 0.25),
                    ),
                  ),
                  child: Text(
                    'Não altera nome pessoal, CPF, e-mail de login nem '
                    'endereço de entrega do titular.',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12.5,
                      height: 1.4,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _nomeLoja,
                  decoration: _dec('Nome da loja', icon: Icons.store_outlined),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _endereco,
                  maxLines: 2,
                  decoration: _dec(
                    'Endereço de retirada / atendimento',
                    icon: Icons.location_on_outlined,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _telefone,
                  keyboardType: TextInputType.phone,
                  decoration: _dec(
                    'Telefone / WhatsApp da loja',
                    icon: Icons.phone_outlined,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: _cidade,
                        decoration: _dec('Cidade da loja'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _uf,
                        maxLength: 2,
                        inputFormatters: [
                          LengthLimitingTextInputFormatter(2),
                          _UpperCaseFormatter(),
                        ],
                        decoration: _dec('UF'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Pausar pedidos manualmente'),
                  subtitle: Text(
                    _pausadoManual
                        ? PausaMotivoLoja.labelPt(_pausaMotivo)
                        : 'Loja aberta para novos pedidos',
                    style: const TextStyle(fontSize: 12),
                  ),
                  value: _pausadoManual,
                  activeThumbColor: PainelAdminTheme.laranja,
                  onChanged: _salvando ? null : _aoMudarPausa,
                ),
                const SizedBox(height: 16),
                Text(
                  'Tipos de entrega aceitos',
                  style: GoogleFonts.plusJakartaSans(
                    fontWeight: FontWeight.w800,
                    color: PainelAdminTheme.roxo,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: TiposEntrega.ordemCanonica.map(_chipTipo).toList(),
                ),
                const SizedBox(height: 20),
                Text(
                  'Horário de funcionamento',
                  style: GoogleFonts.plusJakartaSans(
                    fontWeight: FontWeight.w800,
                    color: PainelAdminTheme.roxo,
                  ),
                ),
                const SizedBox(height: 8),
                ..._horarios.keys.map(_linhaHorario),
              ],
            ),
          ),
        ),
        Padding(
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
                style: FilledButton.styleFrom(
                  backgroundColor: PainelAdminTheme.laranja,
                ),
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
                label: Text(_salvando ? 'Salvando…' : 'Salvar loja'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _chipTipo(String codigo) {
    final sel = _tiposEntrega.contains(codigo);
    return FilterChip(
      label: Text(TiposEntrega.rotulo(codigo)),
      selected: sel,
      onSelected: _salvando
          ? null
          : (v) {
              setState(() {
                if (v) {
                  _tiposEntrega.add(codigo);
                } else {
                  _tiposEntrega.remove(codigo);
                }
              });
            },
      selectedColor: PainelAdminTheme.laranja.withValues(alpha: 0.2),
      checkmarkColor: PainelAdminTheme.laranja,
    );
  }

  Widget _linhaHorario(String chave) {
    final cfg = _horarios[chave]!;
    final ativo = cfg['ativo'] == true;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(
              _nomesDias[chave] ?? chave,
              style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600),
            ),
          ),
          Checkbox(
            value: ativo,
            activeColor: PainelAdminTheme.roxo,
            onChanged: _salvando
                ? null
                : (v) => setState(() => cfg['ativo'] = v == true),
          ),
          if (ativo) ...[
            TextButton(
              onPressed: _salvando ? null : () => _pickHora(chave, true),
              child: Text(cfg['abre'].toString()),
            ),
            const Text('—'),
            TextButton(
              onPressed: _salvando ? null : () => _pickHora(chave, false),
              child: Text(cfg['fecha'].toString()),
            ),
          ] else
            Text(
              'Fechado',
              style: GoogleFonts.plusJakartaSans(color: _muted, fontSize: 12),
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
