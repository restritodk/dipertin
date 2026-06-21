import 'dart:convert';

import 'package:depertin_web/models/comercial_cliente.dart';
import 'package:depertin_web/services/comercial_clientes_service.dart';
import 'package:depertin_web/theme/painel_admin_theme.dart';
import 'package:depertin_web/widgets/dipertin_date_picker.dart';
import 'package:depertin_web/widgets/dipertin_painel_feedback.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

/// Modal premium (~900px) para cadastro/edição de cliente comercial.
Future<ComercialCliente?> mostrarComercialClienteFormModal(
  BuildContext context, {
  required String lojaId,
  ComercialCliente? cliente,
}) {
  return showDialog<ComercialCliente>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    builder: (ctx) => _ComercialClienteFormModal(
      lojaId: lojaId,
      cliente: cliente,
    ),
  );
}

class _ComercialClienteFormModal extends StatefulWidget {
  const _ComercialClienteFormModal({
    required this.lojaId,
    this.cliente,
  });

  final String lojaId;
  final ComercialCliente? cliente;

  @override
  State<_ComercialClienteFormModal> createState() => _ComercialClienteFormModalState();
}

class _ComercialClienteFormModalState extends State<_ComercialClienteFormModal>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  final _formKey = GlobalKey<FormState>();
  bool _salvando = false;

  late final TextEditingController _nome;
  late final TextEditingController _telefone;
  late final TextEditingController _whatsapp;
  late final TextEditingController _cpf;
  late final TextEditingController _rg;
  late final TextEditingController _email;
  late final TextEditingController _dataNascimentoCtrl;
  late final TextEditingController _cep;
  late final TextEditingController _rua;
  late final TextEditingController _numero;
  late final TextEditingController _complemento;
  late final TextEditingController _bairro;
  late final TextEditingController _cidade;
  late final TextEditingController _estado;
  late final TextEditingController _limite;
  late final TextEditingController _diaVenc;
  late final TextEditingController _obsCredito;
  late final TextEditingController _observacoes;

  DateTime? _dataNascimento;
  bool _creditoHabilitado = false;
  bool _buscandoCep = false;
  String? _ultimoCepBuscado;
  final _numeroFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
    final c = widget.cliente;
    _nome = TextEditingController(text: c?.nome ?? '');
    _telefone = TextEditingController(
      text: _maskTelefone((c?.telefone ?? '').replaceAll(RegExp(r'\D'), '')),
    );
    _whatsapp = TextEditingController(
      text: _maskTelefone((c?.whatsapp ?? '').replaceAll(RegExp(r'\D'), '')),
    );
    _cpf = TextEditingController(text: _maskCpf(c?.cpf ?? ''));
    _rg = TextEditingController(text: c?.rg ?? '');
    _email = TextEditingController(text: c?.email ?? '');
    _dataNascimento = c?.dataNascimento;
    _dataNascimentoCtrl = TextEditingController(
      text: _dataNascimento != null
          ? DateFormat('dd/MM/yyyy', 'pt_BR').format(_dataNascimento!)
          : '',
    );
    _cep = TextEditingController(text: _maskCep((c?.cep ?? '').replaceAll(RegExp(r'\D'), '')));
    _rua = TextEditingController(text: c?.rua ?? '');
    _numero = TextEditingController(text: c?.numero ?? '');
    _complemento = TextEditingController(text: c?.complemento ?? '');
    _bairro = TextEditingController(text: c?.bairro ?? '');
    _cidade = TextEditingController(text: c?.cidade ?? '');
    _estado = TextEditingController(text: c?.estado ?? '');
    _limite = TextEditingController(
      text: c != null && c.limiteCredito > 0
          ? c.limiteCredito.toStringAsFixed(2).replaceAll('.', ',')
          : '',
    );
    _diaVenc = TextEditingController(
      text: c?.diaVencimentoCredito?.toString() ?? '',
    );
    _obsCredito = TextEditingController(text: c?.observacaoCredito ?? '');
    _observacoes = TextEditingController(text: c?.observacoes ?? '');
    _creditoHabilitado = c?.creditoHabilitado ?? false;
  }

  static final _dataNascimentoMin = DateTime(1900, 1, 1);

  @override
  void dispose() {
    _tabs.dispose();
    _nome.dispose();
    _telefone.dispose();
    _whatsapp.dispose();
    _cpf.dispose();
    _rg.dispose();
    _email.dispose();
    _dataNascimentoCtrl.dispose();
    _cep.dispose();
    _rua.dispose();
    _numero.dispose();
    _complemento.dispose();
    _bairro.dispose();
    _cidade.dispose();
    _estado.dispose();
    _limite.dispose();
    _diaVenc.dispose();
    _obsCredito.dispose();
    _observacoes.dispose();
    _numeroFocus.dispose();
    super.dispose();
  }

  static String _maskTelefone(String digits) {
    if (digits.isEmpty) return '';
    if (digits.length <= 2) return '($digits';
    if (digits.length <= 6) {
      return '(${digits.substring(0, 2)}) ${digits.substring(2)}';
    }
    if (digits.length <= 10) {
      return '(${digits.substring(0, 2)}) ${digits.substring(2, 6)}-${digits.substring(6)}';
    }
    final d = digits.substring(0, 11);
    return '(${d.substring(0, 2)}) ${d.substring(2, 7)}-${d.substring(7)}';
  }

  static String _maskCep(String digits) {
    if (digits.length <= 5) return digits;
    return '${digits.substring(0, 5)}-${digits.substring(5, digits.length.clamp(0, 8))}';
  }

  static DateTime? _parseDataBr(String texto) {
    final t = texto.trim();
    if (t.isEmpty) return null;
    final m = RegExp(r'^(\d{2})/(\d{2})/(\d{4})$').firstMatch(t);
    if (m == null) return null;
    final dia = int.tryParse(m.group(1)!);
    final mes = int.tryParse(m.group(2)!);
    final ano = int.tryParse(m.group(3)!);
    if (dia == null || mes == null || ano == null) return null;
    if (mes < 1 || mes > 12 || dia < 1 || dia > 31 || ano < 1900) return null;
    try {
      final dt = DateTime(ano, mes, dia);
      if (dt.day != dia || dt.month != mes || dt.year != ano) return null;
      final hoje = DateTime.now();
      final limite = DateTime(hoje.year, hoje.month, hoje.day);
      if (dt.isBefore(_dataNascimentoMin) || dt.isAfter(limite)) return null;
      return dt;
    } catch (_) {
      return null;
    }
  }

  void _aplicarDataNascimento(DateTime? d) {
    setState(() {
      _dataNascimento = d == null ? null : dataSomenteLocal(d);
      _dataNascimentoCtrl.text = _dataNascimento == null
          ? ''
          : DateFormat('dd/MM/yyyy', 'pt_BR').format(_dataNascimento!);
    });
  }

  Future<void> _abrirPickerNascimento() async {
    final d = await showDiPertinDatePicker(
      context,
      titulo: 'Data de nascimento',
      dataInicial: _dataNascimento ?? DateTime(1990, 1, 1),
      dataMinima: _dataNascimentoMin,
      dataMaxima: DateTime.now(),
      mostrarAtalhosRapidos: false,
    );
    if (d != null) _aplicarDataNascimento(d);
  }

  Future<void> _buscarPorCep({bool silencioso = false}) async {
    final cep = _cep.text.replaceAll(RegExp(r'\D'), '');
    if (cep.length != 8) {
      if (!silencioso && mounted) {
        DiPertinPainelFeedback.aviso(
          context,
          'Digite um CEP válido com 8 dígitos.',
        );
      }
      return;
    }
    if (_buscandoCep || _ultimoCepBuscado == cep) return;
    _ultimoCepBuscado = cep;
    setState(() => _buscandoCep = true);
    try {
      final res = await http
          .get(Uri.parse('https://viacep.com.br/ws/$cep/json/'))
          .timeout(const Duration(seconds: 12));
      if (!mounted) return;
      if (res.statusCode != 200) throw Exception('status ${res.statusCode}');
      final data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      if (data['erro'] == true || data['erro'] == 'true') {
        if (!silencioso) {
          DiPertinPainelFeedback.aviso(
            context,
            'CEP não encontrado. Confira ou digite manualmente.',
          );
        }
        return;
      }
      setState(() {
        _cep.text = _maskCep(cep);
        final rua = (data['logradouro'] ?? '').toString().trim();
        final bairro = (data['bairro'] ?? '').toString().trim();
        final cidade = (data['localidade'] ?? '').toString().trim();
        final uf = (data['uf'] ?? '').toString().trim().toUpperCase();
        if (rua.isNotEmpty) _rua.text = rua;
        if (bairro.isNotEmpty) _bairro.text = bairro;
        if (cidade.isNotEmpty) _cidade.text = cidade;
        if (uf.isNotEmpty) _estado.text = uf;
      });
      if (!silencioso && mounted) {
        DiPertinPainelFeedback.sucesso(
          context,
          'Endereço encontrado. Informe o número.',
        );
      }
      _numeroFocus.requestFocus();
    } catch (_) {
      _ultimoCepBuscado = null;
      if (!silencioso && mounted) {
        DiPertinPainelFeedback.erro(
          context,
          'Não foi possível buscar o CEP. Verifique a conexão ou digite manualmente.',
        );
      }
    } finally {
      if (mounted) setState(() => _buscandoCep = false);
    }
  }

  static String _maskCpf(String raw) {
    final d = raw.replaceAll(RegExp(r'\D'), '');
    if (d.length <= 3) return d;
    if (d.length <= 6) return '${d.substring(0, 3)}.${d.substring(3)}';
    if (d.length <= 9) {
      return '${d.substring(0, 3)}.${d.substring(3, 6)}.${d.substring(6)}';
    }
    return '${d.substring(0, 3)}.${d.substring(3, 6)}.${d.substring(6, 9)}-${d.substring(9, d.length.clamp(0, 11))}';
  }

  double _parseMoeda(String s) {
    final t = s.trim().replaceAll(RegExp(r'[^\d,.-]'), '').replaceAll('.', '').replaceAll(',', '.');
    return double.tryParse(t) ?? 0;
  }

  Future<void> _salvar() async {
    if (_nome.text.trim().isEmpty) {
      _tabs.animateTo(0);
      DiPertinPainelFeedback.aviso(
        context,
        'Informe o nome completo do cliente.',
      );
      return;
    }

    setState(() => _salvando = true);
    try {
      final base = widget.cliente;
      final cliente = ComercialCliente(
        id: base?.id ?? '',
        lojaId: widget.lojaId,
        nome: _nome.text.trim(),
        telefone: _telefone.text.replaceAll(RegExp(r'\D'), ''),
        whatsapp: _whatsapp.text.replaceAll(RegExp(r'\D'), ''),
        cpf: _cpf.text.replaceAll(RegExp(r'\D'), ''),
        rg: _rg.text.trim(),
        email: _email.text.trim(),
        dataNascimento: _parseDataBr(_dataNascimentoCtrl.text) ?? _dataNascimento,
        cep: _cep.text.replaceAll(RegExp(r'\D'), ''),
        rua: _rua.text.trim(),
        numero: _numero.text.trim(),
        complemento: _complemento.text.trim(),
        bairro: _bairro.text.trim(),
        cidade: _cidade.text.trim(),
        estado: _estado.text.trim(),
        creditoHabilitado: _creditoHabilitado,
        limiteCredito: _parseMoeda(_limite.text),
        creditoUtilizado: base?.creditoUtilizado ?? 0,
        diaVencimentoCredito: int.tryParse(_diaVenc.text.trim()),
        observacaoCredito: _obsCredito.text.trim(),
        status: base?.status ?? 'ativo',
        observacoes: _observacoes.text.trim(),
        cashback: base?.cashback ?? 0,
        pendencias: base?.pendencias ?? const [],
        vip: base?.vip ?? false,
        createdAt: base?.createdAt,
        updatedAt: base?.updatedAt,
        totalComprado: base?.totalComprado ?? 0,
        ultimaCompra: base?.ultimaCompra,
      );

      final docId = base?.id.trim();
      final id = await ComercialClientesService.salvar(
        lojaId: widget.lojaId,
        cliente: cliente,
        id: docId != null && docId.isNotEmpty ? docId : null,
      );

      if (!mounted) return;
      Navigator.pop(
        context,
        cliente.copyWith(id: id),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _salvando = false);
      DiPertinPainelFeedback.erro(context, 'Erro ao salvar: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final editando = widget.cliente != null;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(28, 24, 16, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            editando ? 'Editar cliente' : 'Novo cliente',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF1E1B4B),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Cadastre dados, endereço e crédito comercial',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 13,
                              color: PainelAdminTheme.textoSecundario,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              TabBar(
                controller: _tabs,
                isScrollable: true,
                labelColor: PainelAdminTheme.roxo,
                unselectedLabelColor: PainelAdminTheme.textoSecundario,
                indicatorColor: PainelAdminTheme.roxo,
                indicatorWeight: 3,
                labelStyle: GoogleFonts.plusJakartaSans(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
                tabs: const [
                  Tab(text: 'Dados básicos'),
                  Tab(text: 'Endereço'),
                  Tab(text: 'Crédito'),
                  Tab(text: 'Observações'),
                ],
              ),
              Flexible(
                child: Form(
                  key: _formKey,
                  child: TabBarView(
                    controller: _tabs,
                    children: [
                      _abaScroll([
                        _row2(
                          _campo('Nome completo *', _nome),
                          _campo(
                            'Telefone',
                            _telefone,
                            keyboard: TextInputType.phone,
                            inputFormatters: [_TelefoneFormatter()],
                          ),
                        ),
                        _row2(
                          _campo(
                            'WhatsApp',
                            _whatsapp,
                            keyboard: TextInputType.phone,
                            inputFormatters: [_TelefoneFormatter()],
                          ),
                          _campo('CPF', _cpf, inputFormatters: [_CpfFormatter()]),
                        ),
                        _row2(
                          _campo('RG', _rg),
                          _campoDataNascimento(),
                        ),
                        _campo('E-mail', _email, keyboard: TextInputType.emailAddress),
                      ]),
                      _abaScroll([
                        _row2(
                          _campoCep(),
                          _campo('Rua', _rua),
                        ),
                        _row2(
                          _campo('Número', _numero, focusNode: _numeroFocus),
                          _campo('Complemento', _complemento),
                        ),
                        _row2(
                          _campo('Bairro', _bairro),
                          _campo('Cidade', _cidade),
                        ),
                        _campo('Estado (UF)', _estado),
                      ]),
                      _abaScroll([
                        SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            'Habilitar crédito',
                            style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600),
                          ),
                          subtitle: const Text('Permite vendas a prazo / fiado'),
                          value: _creditoHabilitado,
                          activeTrackColor: PainelAdminTheme.roxo,
                          onChanged: (v) => setState(() => _creditoHabilitado = v),
                        ),
                        const SizedBox(height: 8),
                        _row2(
                          _campo(
                            'Limite de crédito',
                            _limite,
                            prefix: 'R\$ ',
                            enabled: _creditoHabilitado,
                          ),
                          _campo(
                            'Dia vencimento',
                            _diaVenc,
                            keyboard: TextInputType.number,
                            enabled: _creditoHabilitado,
                            hint: '1–28',
                          ),
                        ),
                        _campoMultiline('Observação crédito', _obsCredito, enabled: _creditoHabilitado),
                      ]),
                      _abaScroll([
                        _campoMultiline('Observações internas', _observacoes, maxLines: 8),
                      ]),
                    ],
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    OutlinedButton(
                      onPressed: _salvando ? null : () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        side: const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                      child: Text(
                        'Cancelar',
                        style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(width: 12),
                    FilledButton.icon(
                      onPressed: _salvando ? null : _salvar,
                      icon: _salvando
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.save_outlined, size: 18),
                      label: Text(
                        'Salvar cliente',
                        style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: PainelAdminTheme.roxo,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _abaScroll(List<Widget> children) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }

  Widget _row2(Widget a, Widget b) {
    return LayoutBuilder(
      builder: (context, c) {
        if (c.maxWidth < 560) {
          return Column(children: [a, const SizedBox(height: 12), b]);
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: a),
            const SizedBox(width: 16),
            Expanded(child: b),
          ],
        );
      },
    );
  }

  Widget _campoDataNascimento() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Data nascimento',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: PainelAdminTheme.textoSecundario,
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: _dataNascimentoCtrl,
          keyboardType: TextInputType.number,
          inputFormatters: [_DataBrFormatter()],
          onChanged: (v) {
            if (v.length == 10) {
              final parsed = _parseDataBr(v);
              if (parsed != null) _dataNascimento = parsed;
            } else if (v.trim().isEmpty) {
              _dataNascimento = null;
            }
          },
          decoration: InputDecoration(
            hintText: 'dd/mm/aaaa',
            hintStyle: GoogleFonts.plusJakartaSans(color: const Color(0xFF9CA3AF)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: PainelAdminTheme.roxo, width: 2),
            ),
            suffixIcon: IconButton(
              tooltip: 'Abrir calendário',
              onPressed: _abrirPickerNascimento,
              icon: const Icon(Icons.calendar_today_rounded, size: 18),
            ),
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _campoCep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'CEP',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: PainelAdminTheme.textoSecundario,
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: _cep,
          keyboardType: TextInputType.number,
          inputFormatters: [_CepFormatter()],
          onChanged: (v) {
            final digits = v.replaceAll(RegExp(r'\D'), '');
            if (digits.length == 8) {
              _buscarPorCep(silencioso: true);
            } else {
              _ultimoCepBuscado = null;
            }
          },
          decoration: InputDecoration(
            hintText: '00000-000',
            hintStyle: GoogleFonts.plusJakartaSans(color: const Color(0xFF9CA3AF)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: PainelAdminTheme.roxo, width: 2),
            ),
            suffixIcon: _buscandoCep
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : IconButton(
                    tooltip: 'Buscar CEP',
                    onPressed: () => _buscarPorCep(),
                    icon: const Icon(Icons.search_rounded, size: 20),
                  ),
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _campo(
    String label,
    TextEditingController ctrl, {
    TextInputType? keyboard,
    List<TextInputFormatter>? inputFormatters,
    String? prefix,
    String? hint,
    bool enabled = true,
    FocusNode? focusNode,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: PainelAdminTheme.textoSecundario,
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: ctrl,
          enabled: enabled,
          focusNode: focusNode,
          keyboardType: keyboard,
          inputFormatters: inputFormatters,
          decoration: InputDecoration(
            hintText: hint,
            prefixText: prefix,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: PainelAdminTheme.roxo, width: 2),
            ),
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _campoMultiline(
    String label,
    TextEditingController ctrl, {
    int maxLines = 4,
    bool enabled = true,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: PainelAdminTheme.textoSecundario,
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: ctrl,
          enabled: enabled,
          maxLines: maxLines,
          decoration: InputDecoration(
            contentPadding: const EdgeInsets.all(14),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: PainelAdminTheme.roxo, width: 2),
            ),
          ),
        ),
      ],
    );
  }
}

class _CpfFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    final mascarado = _ComercialClienteFormModalState._maskCpf(digits);
    return TextEditingValue(
      text: mascarado,
      selection: TextSelection.collapsed(offset: mascarado.length),
    );
  }
}

class _TelefoneFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    final limitado = digits.length > 11 ? digits.substring(0, 11) : digits;
    final mascarado =
        _ComercialClienteFormModalState._maskTelefone(limitado);
    return TextEditingValue(
      text: mascarado,
      selection: TextSelection.collapsed(offset: mascarado.length),
    );
  }
}

class _CepFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    final limitado = digits.length > 8 ? digits.substring(0, 8) : digits;
    final mascarado = _ComercialClienteFormModalState._maskCep(limitado);
    return TextEditingValue(
      text: mascarado,
      selection: TextSelection.collapsed(offset: mascarado.length),
    );
  }
}

class _DataBrFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    final limitado = digits.length > 8 ? digits.substring(0, 8) : digits;
    final buf = StringBuffer();
    for (var i = 0; i < limitado.length; i++) {
      if (i == 2 || i == 4) buf.write('/');
      buf.write(limitado[i]);
    }
    final mascarado = buf.toString();
    return TextEditingValue(
      text: mascarado,
      selection: TextSelection.collapsed(offset: mascarado.length),
    );
  }
}
