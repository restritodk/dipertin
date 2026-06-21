import 'dart:math' show Random;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../constants/cupom_tipos.dart';
import '../../widgets/dipertin_date_picker.dart';
import '../../widgets/dipertin_scroll_body.dart';

const Color _roxo = Color(0xFF6A1B9A);
const Color _laranja = Color(0xFFFF8F00);

/// Gestão de cupons da loja no app mobile (nível II+).
class LojistaCuponsScreen extends StatefulWidget {
  const LojistaCuponsScreen({super.key, required this.uidLoja});

  final String uidLoja;

  @override
  State<LojistaCuponsScreen> createState() => _LojistaCuponsScreenState();
}

class _LojistaCuponsScreenState extends State<LojistaCuponsScreen> {
  final _buscaC = TextEditingController();
  String _filtro = 'todos';

  @override
  void dispose() {
    _buscaC.dispose();
    super.dispose();
  }

  String _gerarCodigo() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final r = Random();
    return List.generate(8, (_) => chars[r.nextInt(chars.length)]).join();
  }

  DateTime? _dataCivilCupom(dynamic ts) {
    if (ts is! Timestamp) return null;
    final d = ts.toDate();
    return dataSomenteLocal(d);
  }

  bool _cupomAguardandoInicio(Map<String, dynamic> c) {
    final inicio = _dataCivilCupom(c['validade_inicio']);
    if (inicio == null) return false;
    return inicio.isAfter(dataSomenteLocal(DateTime.now()));
  }

  bool _cupomExpirado(Map<String, dynamic> c) {
    final fim = _dataCivilCupom(c['validade']);
    if (fim == null) return false;
    return fim.isBefore(dataSomenteLocal(DateTime.now()));
  }

  bool _cupomVigenteParaCliente(Map<String, dynamic> c) {
    return c['ativo'] == true &&
        !_cupomExpirado(c) &&
        !_cupomAguardandoInicio(c);
  }

  String? _textoVigenciaCupom(Map<String, dynamic> c) {
    final inicio = _dataCivilCupom(c['validade_inicio']);
    final fim = _dataCivilCupom(c['validade']);
    if (inicio == null && fim == null) return null;
    final fmt = DateFormat('dd/MM/yyyy', 'pt_BR');
    if (inicio != null && fim != null) {
      return 'Vigência: ${fmt.format(inicio)} — ${fmt.format(fim)}';
    }
    if (inicio != null) return 'Início: ${fmt.format(inicio)}';
    return 'Término: ${fmt.format(fim!)}';
  }

  bool _passaFiltro(Map<String, dynamic> c) {
    final ativo = c['ativo'] == true;
    final expirado = _cupomExpirado(c);
    final aguardando = _cupomAguardandoInicio(c);
    switch (_filtro) {
      case 'ativos':
        return _cupomVigenteParaCliente(c);
      case 'inativos':
        return !ativo && !expirado && !aguardando;
      case 'expirados':
        return expirado;
      default:
        return true;
    }
  }

  Future<bool> _codigoJaExiste(String codigo, {String? ignorarId}) async {
    final snap = await FirebaseFirestore.instance
        .collection('cupons')
        .where('loja_id', isEqualTo: widget.uidLoja)
        .where('escopo', isEqualTo: CupomTipos.escopoLoja)
        .where('codigo', isEqualTo: codigo.toUpperCase())
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return false;
    if (ignorarId != null && snap.docs.first.id == ignorarId) return false;
    return true;
  }

  Future<void> _abrirFormulario({String? docId, Map<String, dynamic>? dados}) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (ctx) => _LojistaCupomFormPage(
          uidLoja: widget.uidLoja,
          docId: docId,
          dados: dados,
          gerarCodigo: _gerarCodigo,
          codigoJaExiste: _codigoJaExiste,
        ),
      ),
    );
  }

  Future<void> _confirmarExcluir(String id, String nome) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir cupom?'),
        content: Text('O cupom "$nome" será removido permanentemente.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await FirebaseFirestore.instance.collection('cupons').doc(id).delete();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F4F8),
      appBar: AppBar(
        title: const Text('Cupons & promoções'),
        backgroundColor: _roxo,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _abrirFormulario(),
        backgroundColor: _laranja,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Novo cupom'),
      ),
      body: DiPertinScrollBody(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _heroBanner(),
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('cupons')
                  .where('loja_id', isEqualTo: widget.uidLoja)
                  .where('escopo', isEqualTo: CupomTipos.escopoLoja)
                  .snapshots(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.all(48),
                    child: Center(
                      child: CircularProgressIndicator(color: _roxo),
                    ),
                  );
                }
                final docs = snap.data?.docs ?? [];
                final q = _buscaC.text.trim().toLowerCase();
                final filtrados = docs.where((d) {
                  final data = d.data();
                  if (!_passaFiltro(data)) return false;
                  if (q.isEmpty) return true;
                  final cod = (data['codigo'] ?? '').toString().toLowerCase();
                  final nome = (data['nome'] ?? '').toString().toLowerCase();
                  return cod.contains(q) || nome.contains(q);
                }).toList()
                  ..sort((a, b) {
                    final ta = a.data()['data_criacao'];
                    final tb = b.data()['data_criacao'];
                    if (ta is Timestamp && tb is Timestamp) {
                      return tb.compareTo(ta);
                    }
                    return 0;
                  });

                final ativos = docs
                    .where((d) => _cupomVigenteParaCliente(d.data()))
                    .length;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _kpiRow(total: docs.length, ativos: ativos),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _buscaC,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        hintText: 'Buscar por nome ou código',
                        prefixIcon: const Icon(Icons.search_rounded),
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: ['todos', 'ativos', 'inativos', 'expirados']
                            .map(
                              (f) => Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: ChoiceChip(
                                  label: Text(
                                    f[0].toUpperCase() + f.substring(1),
                                  ),
                                  selected: _filtro == f,
                                  onSelected: (_) =>
                                      setState(() => _filtro = f),
                                  selectedColor:
                                      _laranja.withValues(alpha: 0.22),
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (filtrados.isEmpty)
                      _estadoVazio()
                    else
                      ...filtrados.map(
                        (d) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _cupomCard(d.id, d.data()),
                        ),
                      ),
                    const SizedBox(height: 80),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _heroBanner() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          colors: [Color(0xFF4A148C), _roxo, Color(0xFF8E24AA)],
        ),
        boxShadow: [
          BoxShadow(
            color: _roxo.withValues(alpha: 0.25),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Promoções da sua loja',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'O desconto é sempre da loja. A comissão da plataforma incide '
                  'sobre o valor que o cliente paga.',
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: Colors.white.withValues(alpha: 0.9),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Icon(
            Icons.loyalty_rounded,
            color: Colors.white.withValues(alpha: 0.9),
            size: 36,
          ),
        ],
      ),
    );
  }

  Widget _kpiRow({required int total, required int ativos}) {
    return Row(
      children: [
        Expanded(child: _kpiTile('Total', '$total', Icons.inventory_2_outlined)),
        const SizedBox(width: 10),
        Expanded(
          child: _kpiTile('Ativos', '$ativos', Icons.bolt_rounded, _laranja),
        ),
      ],
    );
  }

  Widget _kpiTile(String label, String valor, IconData icon, [Color? cor]) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Icon(icon, color: cor ?? _roxo, size: 20),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
              Text(
                valor,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1A1A2E),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _estadoVazio() {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          Icon(Icons.local_offer_outlined, size: 44, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          const Text(
            'Nenhum cupom encontrado',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
          ),
          const SizedBox(height: 6),
          Text(
            'Crie seu primeiro cupom para atrair mais clientes.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  Widget _cupomCard(String id, Map<String, dynamic> c) {
    final nome = (c['nome'] ?? 'Sem nome').toString();
    final codigo = (c['codigo'] ?? '').toString();
    final tipo = (c['tipo'] ?? CupomTipos.porcentagem).toString();
    final ativo = c['ativo'] == true;
    final expirado = _cupomExpirado(c);
    final aguardando = _cupomAguardandoInicio(c);
    final vigente = _cupomVigenteParaCliente(c);
    final usos = (c['usos_atual'] as num?)?.toInt() ?? 0;
    final limite = (c['limite_usos'] as num?)?.toInt() ?? 0;
    final progresso = limite > 0 ? (usos / limite).clamp(0.0, 1.0) : null;

    final statusCor = vigente
        ? const Color(0xFF2E7D32)
        : (aguardando ? _laranja : Colors.grey);
    final statusTxt = vigente
        ? 'Ativo'
        : (expirado
            ? 'Expirado'
            : (aguardando ? 'Aguardando início' : 'Inativo'));
    final vigenciaTxt = _textoVigenciaCupom(c);

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _abrirFormulario(docId: id, dados: c),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: _roxo.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      codigo,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        color: _roxo,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusCor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      statusTxt,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: statusCor,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                nome,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1A1A2E),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${CupomTipos.rotuloTipo(tipo)} · ${CupomTipos.resumoValor(c)}',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
              ),
              if (vigenciaTxt != null) ...[
                const SizedBox(height: 4),
                Text(
                  vigenciaTxt,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
              if (progresso != null) ...[
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progresso,
                    minHeight: 5,
                    backgroundColor: Colors.grey.shade200,
                    color: _laranja,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$usos / $limite utilizações',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
              ],
              const SizedBox(height: 10),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: () => _abrirFormulario(docId: id, dados: c),
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('Editar'),
                  ),
                  TextButton.icon(
                    onPressed: () async {
                      await FirebaseFirestore.instance
                          .collection('cupons')
                          .doc(id)
                          .update({'ativo': !ativo});
                    },
                    icon: Icon(
                      ativo
                          ? Icons.pause_circle_outline
                          : Icons.play_arrow_rounded,
                      size: 18,
                    ),
                    label: Text(ativo ? 'Desativar' : 'Ativar'),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => _confirmarExcluir(id, nome),
                    icon: Icon(Icons.delete_outline, color: Colors.red.shade400),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LojistaCupomFormPage extends StatefulWidget {
  const _LojistaCupomFormPage({
    required this.uidLoja,
    required this.gerarCodigo,
    required this.codigoJaExiste,
    this.docId,
    this.dados,
  });

  final String uidLoja;
  final String? docId;
  final Map<String, dynamic>? dados;
  final String Function() gerarCodigo;
  final Future<bool> Function(String codigo, {String? ignorarId}) codigoJaExiste;

  @override
  State<_LojistaCupomFormPage> createState() => _LojistaCupomFormPageState();
}

class _LojistaCupomFormPageState extends State<_LojistaCupomFormPage> {
  late final TextEditingController _nomeC;
  late final TextEditingController _codigoC;
  late final TextEditingController _valorC;
  late final TextEditingController _limiteC;
  late final TextEditingController _limiteClienteC;
  late final TextEditingController _raioC;

  late String _tipo;
  late String _freteMod;
  late DateTime? _inicio;
  late DateTime? _fim;
  late bool _ativo;
  bool _salvando = false;

  bool get _isEdit => widget.docId != null;
  bool get _precisaValor => _tipo != CupomTipos.freteGratis;

  @override
  void initState() {
    super.initState();
    final d = widget.dados;
    _nomeC = TextEditingController(text: _isEdit ? (d!['nome'] ?? '').toString() : '');
    _codigoC = TextEditingController(
      text: _isEdit ? (d!['codigo'] ?? '').toString() : widget.gerarCodigo(),
    );
    _valorC = TextEditingController(
      text: _isEdit && d!['valor'] != null ? d['valor'].toString() : '',
    );
    _limiteC = TextEditingController(
      text: _isEdit ? (d!['limite_usos']?.toString() ?? '') : '',
    );
    _limiteClienteC = TextEditingController(
      text: _isEdit ? (d!['limite_por_usuario']?.toString() ?? '1') : '1',
    );
    _raioC = TextEditingController(
      text: _isEdit ? (d!['frete_gratis_raio_km']?.toString() ?? '5') : '5',
    );
    _tipo = _isEdit
        ? (d!['tipo'] ?? CupomTipos.porcentagem).toString()
        : CupomTipos.porcentagem;
    _freteMod = _isEdit
        ? (d!['frete_gratis_modalidade'] ?? CupomTipos.freteSemLimite).toString()
        : CupomTipos.freteSemLimite;
    _inicio = _isEdit && d!['validade_inicio'] is Timestamp
        ? dataSomenteLocal((d['validade_inicio'] as Timestamp).toDate())
        : dataSomenteLocal(DateTime.now());
    _fim = _isEdit && d!['validade'] is Timestamp
        ? dataSomenteLocal((d['validade'] as Timestamp).toDate())
        : dataSomenteLocal(DateTime.now()).add(const Duration(days: 30));
    _ativo = _isEdit ? (d!['ativo'] ?? true) : true;
  }

  @override
  void dispose() {
    _nomeC.dispose();
    _codigoC.dispose();
    _valorC.dispose();
    _limiteC.dispose();
    _limiteClienteC.dispose();
    _raioC.dispose();
    super.dispose();
  }

  InputDecoration _dec(String label, {String? hint}) => InputDecoration(
        labelText: label,
        hintText: hint,
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      );

  Future<void> _salvar() async {
    final nome = _nomeC.text.trim();
    final codigo = _codigoC.text.trim().toUpperCase();
    if (nome.isEmpty || codigo.isEmpty) {
      _snack('Informe nome e código.');
      return;
    }
    if (_precisaValor && _valorC.text.trim().isEmpty) {
      _snack('Informe o valor do desconto.');
      return;
    }
    if (_fim == null) {
      _snack('Informe a data de término.');
      return;
    }
    if (_tipo == CupomTipos.freteGratis &&
        _freteMod == CupomTipos.freteRaioKm) {
      final raio = double.tryParse(_raioC.text.replaceAll(',', '.'));
      if (raio == null || raio <= 0) {
        _snack('Informe o raio máximo em km.');
        return;
      }
    }

    setState(() => _salvando = true);
    try {
      if (await widget.codigoJaExiste(codigo, ignorarId: widget.docId)) {
        _snack('Este código já está em uso.');
        return;
      }

      final authUid = FirebaseAuth.instance.currentUser?.uid ?? '';
      final payload = <String, dynamic>{
        'nome': nome,
        'codigo': codigo,
        'tipo': _tipo,
        'valor': _precisaValor
            ? (double.tryParse(_valorC.text.replaceAll(',', '.')) ?? 0)
            : 0,
        'limite_usos': int.tryParse(_limiteC.text.trim()) ?? 0,
        'limite_por_usuario': int.tryParse(_limiteClienteC.text.trim()) ?? 1,
        'ativo': _ativo,
        'escopo': CupomTipos.escopoLoja,
        'loja_id': widget.uidLoja,
        'criado_por_uid': _isEdit
            ? (widget.dados!['criado_por_uid'] ?? authUid)
            : authUid,
        if (_inicio != null)
          'validade_inicio': Timestamp.fromDate(dataSomenteLocal(_inicio!)),
        'validade': Timestamp.fromDate(dataSomenteLocal(_fim!)),
        if (_tipo == CupomTipos.freteGratis) ...{
          'frete_gratis_modalidade': _freteMod,
          if (_freteMod == CupomTipos.freteRaioKm)
            'frete_gratis_raio_km':
                double.tryParse(_raioC.text.replaceAll(',', '.')) ?? 0,
        },
        'data_atualizacao': FieldValue.serverTimestamp(),
      };

      final col = FirebaseFirestore.instance.collection('cupons');
      if (_isEdit) {
        await col.doc(widget.docId).update(payload);
      } else {
        payload['usos_atual'] = 0;
        payload['data_criacao'] = FieldValue.serverTimestamp();
        await col.add(payload);
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      _snack('Erro ao salvar: $e');
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  static const _duracaoVigenciaPadrao = Duration(days: 30);

  void _aoMudarInicioVigencia(DateTime d) {
    final inicio = dataSomenteLocal(d);
    final fimMax = dataSomenteLocal(
      DateTime.now().add(const Duration(days: 365 * 3)),
    );
    var fim = inicio.add(_duracaoVigenciaPadrao);
    if (fim.isAfter(fimMax)) fim = fimMax;
    setState(() {
      _inicio = inicio;
      _fim = fim;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F4F8),
      appBar: AppBar(
        title: Text(_isEdit ? 'Editar cupom' : 'Novo cupom'),
        backgroundColor: _roxo,
        foregroundColor: Colors.white,
      ),
      body: DiPertinScrollBody(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(controller: _nomeC, decoration: _dec('Nome do cupom')),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _codigoC,
                    decoration: _dec('Código'),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
                      _UpperCaseTextFormatter(),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  onPressed: () => setState(() => _codigoC.text = widget.gerarCodigo()),
                  icon: const Icon(Icons.autorenew_rounded),
                ),
              ],
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _tipo,
              decoration: _dec('Tipo de cupom'),
              items: const [
                DropdownMenuItem(
                  value: CupomTipos.porcentagem,
                  child: Text('Desconto percentual (%)'),
                ),
                DropdownMenuItem(
                  value: CupomTipos.fixo,
                  child: Text('Desconto em valor (R\$)'),
                ),
                DropdownMenuItem(
                  value: CupomTipos.freteGratis,
                  child: Text('Frete grátis'),
                ),
              ],
              onChanged: (v) => setState(() => _tipo = v!),
            ),
            if (_precisaValor) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _valorC,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: _dec(
                  _tipo == CupomTipos.porcentagem ? 'Desconto (%)' : 'Desconto (R\$)',
                ),
              ),
            ],
            if (_tipo == CupomTipos.freteGratis) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _freteMod,
                decoration: _dec('Modalidade do frete grátis'),
                items: const [
                  DropdownMenuItem(
                    value: CupomTipos.freteSemLimite,
                    child: Text('Sem limite de distância'),
                  ),
                  DropdownMenuItem(
                    value: CupomTipos.freteRaioKm,
                    child: Text('Raio máximo (km)'),
                  ),
                ],
                onChanged: (v) => setState(() => _freteMod = v!),
              ),
              if (_freteMod == CupomTipos.freteRaioKm) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _raioC,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: _dec('Distância máxima (km)', hint: 'Ex.: 5'),
                ),
              ],
              const SizedBox(height: 8),
              Text(
                'O custo do frete será da loja. Entregador e plataforma '
                'recebem normalmente sobre o frete.',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _limiteC,
              keyboardType: TextInputType.number,
              decoration: _dec('Máximo de utilizações', hint: '0 = ilimitado'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _limiteClienteC,
              keyboardType: TextInputType.number,
              decoration: _dec('Limite por cliente'),
            ),
            const SizedBox(height: 16),
            const Text(
              'Período de vigência',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: Color(0xFF1A1A2E),
              ),
            ),
            const SizedBox(height: 8),
            DiPertinDateField(
              label: 'Início da vigência',
              tituloPicker: 'Quando o cupom começa',
              subtituloPicker:
                  'Clientes só poderão usar a partir desta data.',
              data: _inicio,
              dataMinima: DateTime.now().subtract(const Duration(days: 1)),
              dataMaxima: DateTime.now().add(const Duration(days: 365 * 3)),
              onChanged: _aoMudarInicioVigencia,
            ),
            const SizedBox(height: 10),
            DiPertinDateField(
              label: 'Término da vigência',
              tituloPicker: 'Quando o cupom expira',
              subtituloPicker: 'Após esta data o código deixa de funcionar.',
              data: _fim,
              destaque: true,
              dataMinima: _inicio ??
                  DateTime.now().subtract(const Duration(days: 1)),
              dataMaxima: DateTime.now().add(const Duration(days: 365 * 3)),
              onChanged: (d) => setState(() => _fim = dataSomenteLocal(d)),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              value: _ativo,
              onChanged: (v) => setState(() => _ativo = v),
              title: const Text('Cupom ativo'),
              subtitle: Text(
                _ativo
                    ? 'Disponível para clientes no app'
                    : 'Oculto até reativar',
              ),
              activeThumbColor: _laranja,
            ),
            const SizedBox(height: 24),
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
                  : const Icon(Icons.check_rounded),
              label: Text(_salvando ? 'Salvando…' : 'Salvar cupom'),
              style: FilledButton.styleFrom(
                backgroundColor: _roxo,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
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
