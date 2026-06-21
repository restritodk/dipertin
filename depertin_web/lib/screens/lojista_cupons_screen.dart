import 'dart:math' show min, Random;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:depertin_web/constants/cupom_tipos.dart';
import 'package:depertin_web/theme/painel_admin_theme.dart';
import 'package:depertin_web/utils/lojista_painel_context.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../widgets/dipertin_date_picker.dart';

/// Gestão de cupons da loja — criar, editar e acompanhar promoções.
class LojistaCuponsScreen extends StatefulWidget {
  const LojistaCuponsScreen({super.key});

  @override
  State<LojistaCuponsScreen> createState() => _LojistaCuponsScreenState();
}

class _LojistaCuponsScreenState extends State<LojistaCuponsScreen> {
  static const _roxo = PainelAdminTheme.roxo;
  static const _laranja = PainelAdminTheme.laranja;

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

  InputDecoration _dec(String label, {String? hint}) => InputDecoration(
        labelText: label,
        hintText: hint,
        filled: true,
        fillColor: const Color(0xFFF8F7FC),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _roxo, width: 1.5),
        ),
        labelStyle: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600),
      );

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

  Future<bool> _codigoJaExiste(
    String codigo, {
    required String uidLoja,
    String? ignorarId,
  }) async {
    final snap = await FirebaseFirestore.instance
        .collection('cupons')
        .where('loja_id', isEqualTo: uidLoja)
        .where('escopo', isEqualTo: CupomTipos.escopoLoja)
        .where('codigo', isEqualTo: codigo.toUpperCase())
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return false;
    if (ignorarId != null && snap.docs.first.id == ignorarId) return false;
    return true;
  }

  void _abrirFormulario({
    required String uidLoja,
    String? docId,
    Map<String, dynamic>? dados,
  }) {
    final isEdit = docId != null;
    final nomeC = TextEditingController(
      text: isEdit ? (dados!['nome'] ?? '').toString() : '',
    );
    final codigoC = TextEditingController(
      text: isEdit ? (dados!['codigo'] ?? '').toString() : _gerarCodigo(),
    );
    final valorC = TextEditingController(
      text: isEdit && dados!['valor'] != null
          ? dados['valor'].toString()
          : '',
    );
    final limiteC = TextEditingController(
      text: isEdit ? (dados!['limite_usos']?.toString() ?? '') : '',
    );
    final limiteClienteC = TextEditingController(
      text: isEdit
          ? (dados!['limite_por_usuario']?.toString() ?? '1')
          : '1',
    );
    final raioC = TextEditingController(
      text: isEdit
          ? (dados!['frete_gratis_raio_km']?.toString() ?? '')
          : '5',
    );

    String tipo =
        isEdit ? (dados!['tipo'] ?? CupomTipos.porcentagem).toString() : CupomTipos.porcentagem;
    String freteMod = isEdit
        ? (dados!['frete_gratis_modalidade'] ?? CupomTipos.freteSemLimite)
            .toString()
        : CupomTipos.freteSemLimite;
    DateTime? inicio = isEdit && dados!['validade_inicio'] is Timestamp
        ? dataSomenteLocal((dados['validade_inicio'] as Timestamp).toDate())
        : dataSomenteLocal(DateTime.now());
    DateTime? fim = isEdit && dados!['validade'] is Timestamp
        ? dataSomenteLocal((dados['validade'] as Timestamp).toDate())
        : dataSomenteLocal(DateTime.now()).add(const Duration(days: 30));
    bool ativo = isEdit ? (dados!['ativo'] ?? true) : true;
    var loading = false;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.48),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          final mq = MediaQuery.sizeOf(ctx);
          final w = min(520.0, mq.width - 32);
          final precisaValor = tipo != CupomTipos.freteGratis;

          Future<void> salvar() async {
            final nome = nomeC.text.trim();
            final codigo = codigoC.text.trim().toUpperCase();
            if (nome.isEmpty || codigo.isEmpty) {
              ScaffoldMessenger.of(ctx).showSnackBar(
                const SnackBar(content: Text('Informe nome e código.')),
              );
              return;
            }
            if (precisaValor && valorC.text.trim().isEmpty) {
              ScaffoldMessenger.of(ctx).showSnackBar(
                const SnackBar(content: Text('Informe o valor do desconto.')),
              );
              return;
            }
            if (fim == null) {
              ScaffoldMessenger.of(ctx).showSnackBar(
                const SnackBar(content: Text('Informe a data de término.')),
              );
              return;
            }
            if (tipo == CupomTipos.freteGratis &&
                freteMod == CupomTipos.freteRaioKm) {
              final raio = double.tryParse(raioC.text.replaceAll(',', '.'));
              if (raio == null || raio <= 0) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(
                    content: Text('Informe o raio máximo em km.'),
                  ),
                );
                return;
              }
            }

            setS(() => loading = true);
            try {
              if (await _codigoJaExiste(
                codigo,
                uidLoja: uidLoja,
                ignorarId: docId,
              )) {
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(
                      content: Text('Este código já está em uso.'),
                    ),
                  );
                }
                return;
              }

              final authUid = FirebaseAuth.instance.currentUser?.uid ?? '';
              final payload = <String, dynamic>{
                'nome': nome,
                'codigo': codigo,
                'tipo': tipo,
                'valor': precisaValor
                    ? (double.tryParse(valorC.text.replaceAll(',', '.')) ?? 0)
                    : 0,
                'limite_usos': int.tryParse(limiteC.text.trim()) ?? 0,
                'limite_por_usuario':
                    int.tryParse(limiteClienteC.text.trim()) ?? 1,
                'ativo': ativo,
                'escopo': CupomTipos.escopoLoja,
                'loja_id': uidLoja,
                'criado_por_uid': isEdit
                    ? (dados!['criado_por_uid'] ?? authUid)
                    : authUid,
                if (inicio != null)
                  'validade_inicio': Timestamp.fromDate(dataSomenteLocal(inicio!)),
                'validade': Timestamp.fromDate(dataSomenteLocal(fim!)),
                if (tipo == CupomTipos.freteGratis) ...{
                  'frete_gratis_modalidade': freteMod,
                  if (freteMod == CupomTipos.freteRaioKm)
                    'frete_gratis_raio_km':
                        double.tryParse(raioC.text.replaceAll(',', '.')) ?? 0,
                },
                'data_atualizacao': FieldValue.serverTimestamp(),
              };

              final col = FirebaseFirestore.instance.collection('cupons');
              if (isEdit) {
                await col.doc(docId).update(payload);
              } else {
                payload['usos_atual'] = 0;
                payload['data_criacao'] = FieldValue.serverTimestamp();
                await col.add(payload);
              }
              if (ctx.mounted) Navigator.pop(ctx);
            } catch (e) {
              if (ctx.mounted) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  SnackBar(content: Text('Erro ao salvar: $e')),
                );
              }
            } finally {
              if (ctx.mounted) setS(() => loading = false);
            }
          }

          return Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
            ),
            clipBehavior: Clip.antiAlias,
            child: SizedBox(
              width: w,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          _roxo.withValues(alpha: 0.12),
                          _laranja.withValues(alpha: 0.06),
                        ],
                      ),
                      border: Border(
                        bottom: BorderSide(color: Colors.grey.shade200),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: _roxo.withValues(alpha: 0.12),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.local_offer_rounded,
                            color: _roxo,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            isEdit ? 'Editar cupom' : 'Novo cupom',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: _roxo,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(22, 20, 22, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TextField(
                            controller: nomeC,
                            decoration: _dec('Nome do cupom',
                                hint: 'Ex.: Black Friday da loja'),
                          ),
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: codigoC,
                                  decoration: _dec('Código'),
                                  inputFormatters: [
                                    FilteringTextInputFormatter.allow(
                                      RegExp(r'[A-Za-z0-9]'),
                                    ),
                                    UpperCaseTextFormatter(),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              IconButton.filledTonal(
                                tooltip: 'Gerar código',
                                onPressed: () =>
                                    setS(() => codigoC.text = _gerarCodigo()),
                                icon: const Icon(Icons.autorenew_rounded),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          DropdownButtonFormField<String>(
                            value: tipo,
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
                            onChanged: (v) => setS(() => tipo = v!),
                          ),
                          if (precisaValor) ...[
                            const SizedBox(height: 14),
                            TextField(
                              controller: valorC,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                decimal: true,
                              ),
                              decoration: _dec(
                                tipo == CupomTipos.porcentagem
                                    ? 'Desconto (%)'
                                    : 'Desconto (R\$)',
                              ),
                            ),
                          ],
                          if (tipo == CupomTipos.freteGratis) ...[
                            const SizedBox(height: 14),
                            DropdownButtonFormField<String>(
                              value: freteMod,
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
                              onChanged: (v) => setS(() => freteMod = v!),
                            ),
                            if (freteMod == CupomTipos.freteRaioKm) ...[
                              const SizedBox(height: 14),
                              TextField(
                                controller: raioC,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                  decimal: true,
                                ),
                                decoration: _dec('Distância máxima (km)',
                                    hint: 'Ex.: 5'),
                              ),
                            ],
                            const SizedBox(height: 8),
                            Text(
                              'O custo do frete será assumido pela sua loja. '
                              'Entregador e plataforma recebem normalmente sobre o frete.',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 12,
                                height: 1.4,
                                color: Colors.grey.shade700,
                              ),
                            ),
                          ],
                          const SizedBox(height: 14),
                          TextField(
                            controller: limiteC,
                            keyboardType: TextInputType.number,
                            decoration: _dec('Máximo de utilizações',
                                hint: '0 = ilimitado'),
                          ),
                          const SizedBox(height: 14),
                          TextField(
                            controller: limiteClienteC,
                            keyboardType: TextInputType.number,
                            decoration: _dec('Limite por cliente'),
                          ),
                          const SizedBox(height: 14),
                          DiPertinDateField(
                            label: 'Início da vigência',
                            tituloPicker: 'Quando o cupom começa',
                            subtituloPicker:
                                'Clientes só poderão usar a partir desta data.',
                            data: inicio,
                            dataMinima: DateTime.now()
                                .subtract(const Duration(days: 1)),
                            dataMaxima: DateTime.now()
                                .add(const Duration(days: 365 * 3)),
                            onChanged: (d) => setS(() {
                              inicio = d;
                              if (fim != null && fim!.isBefore(d)) fim = d;
                            }),
                          ),
                          const SizedBox(height: 10),
                          DiPertinDateField(
                            label: 'Término da vigência',
                            tituloPicker: 'Quando o cupom expira',
                            subtituloPicker:
                                'Após esta data o código deixa de funcionar.',
                            data: fim,
                            destaque: true,
                            obrigatorio: true,
                            dataMinima: inicio ??
                                DateTime.now()
                                    .subtract(const Duration(days: 1)),
                            dataMaxima: DateTime.now()
                                .add(const Duration(days: 365 * 3)),
                            onChanged: (d) => setS(() => fim = d),
                          ),
                          const SizedBox(height: 8),
                          SwitchListTile(
                            value: ativo,
                            onChanged: (v) => setS(() => ativo = v),
                            title: const Text('Cupom ativo'),
                            subtitle: Text(
                              ativo
                                  ? 'Disponível para clientes no app'
                                  : 'Oculto até reativar',
                            ),
                            activeThumbColor: _laranja,
                            contentPadding: EdgeInsets.zero,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed:
                              loading ? null : () => Navigator.pop(ctx),
                          child: const Text('Cancelar'),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.icon(
                          onPressed: loading ? null : salvar,
                          icon: loading
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.check_rounded),
                          label: Text(loading ? 'Salvando…' : 'Salvar'),
                          style: FilledButton.styleFrom(
                            backgroundColor: _roxo,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _confirmarExcluir(String id, String nome) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir cupom?'),
        content: Text(
          'O cupom "$nome" será removido permanentemente.',
        ),
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
    if (ok != true) return;
    await FirebaseFirestore.instance.collection('cupons').doc(id).delete();
  }

  @override
  Widget build(BuildContext context) {
    final authUid = FirebaseAuth.instance.currentUser?.uid;
    if (authUid == null) return const SizedBox.shrink();

    return LojistaUidLojaBuilder(
      builder: (context, authUid, uidLoja, dadosUsuario) {
        if (dadosUsuario != null && !painelMostrarMeusProdutos(dadosUsuario)) {
          return painelLojistaSemPermissaoScaffold(
            mensagem:
                'Seu nível de acesso não permite gerenciar cupons da loja.',
          );
        }
        return Scaffold(
          backgroundColor: PainelAdminTheme.fundoCanvas,
          body: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: _hero(uidLoja)),
              StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance
                    .collection('cupons')
                    .where('loja_id', isEqualTo: uidLoja)
                    .where('escopo', isEqualTo: CupomTipos.escopoLoja)
                    .snapshots(),
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const SliverFillRemaining(
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

                  return SliverPadding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
                    sliver: SliverList(
                      delegate: SliverChildListDelegate([
                        _kpiRow(total: docs.length, ativos: ativos),
                        const SizedBox(height: 16),
                        _toolbar(uidLoja),
                        const SizedBox(height: 16),
                        if (filtrados.isEmpty)
                          _estadoVazio()
                        else
                          ...filtrados.map(
                            (d) => Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _cupomCard(
                                d.id,
                                d.data(),
                                uidLoja: uidLoja,
                              ),
                            ),
                          ),
                      ]),
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _hero(String uidLoja) {
    return Container(
      margin: const EdgeInsets.fromLTRB(24, 24, 24, 20),
      padding: const EdgeInsets.fromLTRB(28, 28, 28, 24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF4A148C), _roxo, Color(0xFF8E24AA)],
        ),
        boxShadow: [
          BoxShadow(
            color: _roxo.withValues(alpha: 0.28),
            blurRadius: 32,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Cupons & Promoções',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Crie descontos exclusivos para sua loja. O custo do cupom '
                  'é sempre da loja — a comissão da plataforma incide sobre '
                  'o valor que o cliente efetivamente paga.',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    height: 1.45,
                    color: Colors.white.withValues(alpha: 0.9),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.loyalty_rounded,
              color: Colors.white,
              size: 36,
            ),
          ),
        ],
      ),
    );
  }

  Widget _kpiRow({required int total, required int ativos}) {
    return Row(
      children: [
        Expanded(
          child: _kpiTile('Total', '$total', Icons.inventory_2_outlined),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _kpiTile('Ativos', '$ativos', Icons.bolt_rounded, _laranja),
        ),
      ],
    );
  }

  Widget _kpiTile(String label, String valor, IconData icon, [Color? cor]) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE8ECF1)),
      ),
      child: Row(
        children: [
          Icon(icon, color: cor ?? _roxo, size: 22),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  color: PainelAdminTheme.textoSecundario,
                ),
              ),
              Text(
                valor,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: PainelAdminTheme.dashboardInk,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _toolbar(String uidLoja) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 280,
          child: TextField(
            controller: _buscaC,
            onChanged: (_) => setState(() {}),
            decoration: _dec('Buscar por nome ou código').copyWith(
              prefixIcon: const Icon(Icons.search_rounded, size: 20),
            ),
          ),
        ),
        ...['todos', 'ativos', 'inativos', 'expirados'].map(
          (f) => ChoiceChip(
            label: Text(f[0].toUpperCase() + f.substring(1)),
            selected: _filtro == f,
            onSelected: (_) => setState(() => _filtro = f),
            selectedColor: _laranja.withValues(alpha: 0.22),
            labelStyle: GoogleFonts.plusJakartaSans(
              fontWeight: _filtro == f ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
        FilledButton.icon(
          onPressed: () => _abrirFormulario(uidLoja: uidLoja),
          icon: const Icon(Icons.add_rounded),
          label: const Text('Novo cupom'),
          style: FilledButton.styleFrom(backgroundColor: _roxo),
        ),
      ],
    );
  }

  Widget _estadoVazio() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(40),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          Icon(Icons.local_offer_outlined, size: 48, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          Text(
            'Nenhum cupom encontrado',
            style: GoogleFonts.plusJakartaSans(
              fontWeight: FontWeight.w700,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Crie seu primeiro cupom para atrair mais clientes.',
            style: GoogleFonts.plusJakartaSans(
              color: PainelAdminTheme.textoSecundario,
            ),
          ),
        ],
      ),
    );
  }

  Widget _cupomCard(
    String id,
    Map<String, dynamic> c, {
    required String uidLoja,
  }) {
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

    Color statusCor = vigente
        ? const Color(0xFF2E7D32)
        : (aguardando ? _laranja : Colors.grey);
    String statusTxt = vigente
        ? 'Ativo'
        : (expirado
            ? 'Expirado'
            : (aguardando ? 'Aguardando início' : 'Inativo'));

    return Material(
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
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
                    style: GoogleFonts.jetBrainsMono(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: _roxo,
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
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: statusCor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              nome,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: PainelAdminTheme.dashboardInk,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '${CupomTipos.rotuloTipo(tipo)} · ${CupomTipos.resumoValor(c)}',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                color: PainelAdminTheme.textoSecundario,
              ),
            ),
            if (_textoVigenciaCupom(c) != null) ...[
              const SizedBox(height: 4),
              Text(
                _textoVigenciaCupom(c)!,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  color: PainelAdminTheme.textoSecundario,
                ),
              ),
            ],
            if (progresso != null) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progresso,
                  minHeight: 6,
                  backgroundColor: Colors.grey.shade200,
                  color: _laranja,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '$usos / $limite utilizações',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 11,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
            const SizedBox(height: 14),
            Row(
              children: [
                TextButton.icon(
                  onPressed: () => _abrirFormulario(
                    uidLoja: uidLoja,
                    docId: id,
                    dados: c,
                  ),
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
                    ativo ? Icons.pause_circle_outline : Icons.play_arrow_rounded,
                    size: 18,
                  ),
                  label: Text(ativo ? 'Desativar' : 'Ativar'),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Excluir',
                  onPressed: () => _confirmarExcluir(id, nome),
                  icon: Icon(Icons.delete_outline, color: Colors.red.shade400),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class UpperCaseTextFormatter extends TextInputFormatter {
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
