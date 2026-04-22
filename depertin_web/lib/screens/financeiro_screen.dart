import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../navigation/painel_nav_controller.dart';
import '../navigation/painel_navigation_scope.dart';
import '../services/firebase_functions_config.dart';
import '../theme/painel_admin_theme.dart';
import '../utils/admin_perfil.dart';
import '../widgets/botao_suporte_flutuante.dart';

/// Filtro do extrato: entradas (lucro), saídas (despesa) ou ambos.
enum _FiltroExtratoMovimento { todos, lucro, despesa }

class FinanceiroScreen extends StatefulWidget {
  const FinanceiroScreen({super.key});

  @override
  State<FinanceiroScreen> createState() => _FinanceiroScreenState();
}

class _FinanceiroScreenState extends State<FinanceiroScreen> {
  DateTime? _dataInicioFiltro;
  DateTime? _dataFimFiltro;

  /// Página atual do extrato de receitas (0 = primeira).
  int _paginaExtrato = 0;

  _FiltroExtratoMovimento _filtroExtratoMovimento = _FiltroExtratoMovimento.todos;

  /// Future cacheado para evitar refetch desnecessário a cada rebuild.
  late Future<Map<String, dynamic>> _futureFinanceiro;

  PainelNavController? _navCtrl;

  @override
  void initState() {
    super.initState();
    _futureFinanceiro = _buscarDadosFinanceiros();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final ctrl = PainelNavigationScope.maybeOf(context);
    if (ctrl != _navCtrl) {
      _navCtrl?.removeListener(_onRotaMudou);
      _navCtrl = ctrl;
      _navCtrl?.addListener(_onRotaMudou);
    }
  }

  void _onRotaMudou() {
    if (_navCtrl?.currentRoute == '/financeiro') {
      _atualizarFinanceiro();
    }
  }

  /// Atualiza o future e opcionalmente reinicia a paginação.
  void _atualizarFinanceiro({bool resetPagina = false}) {
    setState(() {
      if (resetPagina) _paginaExtrato = 0;
      _futureFinanceiro = _buscarDadosFinanceiros();
    });
  }

  static const int _kExtratoItensPorPagina = 10;

  /// Página do histórico de estornos (0 = primeira).
  int _paginaEstornos = 0;

  static const int _kEstornosItensPorPagina = 10;

  static final NumberFormat _brl = NumberFormat.currency(
    locale: 'pt_BR',
    symbol: 'R\$',
  );

  static double _num(dynamic v) =>
      v is num ? v.toDouble() : double.tryParse('$v') ?? 0;

  Future<void> _escolherPeriodo() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: _dataInicioFiltro != null && _dataFimFiltro != null
          ? DateTimeRange(start: _dataInicioFiltro!, end: _dataFimFiltro!)
          : null,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.42),
      helpText: 'Filtrar por período',
      cancelText: 'Cancelar',
      confirmText: 'Aplicar',
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        final maxW = math.min(520.0, mq.size.width - 40);
        final maxH = (mq.size.height * 0.88).clamp(420.0, 720.0);
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: PainelAdminTheme.laranja,
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: PainelAdminTheme.dashboardInk,
              secondary: PainelAdminTheme.roxo,
            ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(
                foregroundColor: PainelAdminTheme.roxo,
                textStyle: GoogleFonts.plusJakartaSans(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
            ),
            filledButtonTheme: FilledButtonThemeData(
              style: FilledButton.styleFrom(
                backgroundColor: PainelAdminTheme.laranja,
                foregroundColor: Colors.white,
                textStyle: GoogleFonts.plusJakartaSans(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            dialogTheme: DialogThemeData(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              elevation: 0,
              backgroundColor: Colors.white,
            ),
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: maxW,
                maxHeight: maxH,
              ),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: PainelAdminTheme.dashboardBorder),
                  boxShadow: PainelAdminTheme.sombraCardSuave(),
                ),
                clipBehavior: Clip.antiAlias,
                child: child!,
              ),
            ),
          ),
        );
      },
    );

    if (picked != null) {
      _dataInicioFiltro = picked.start;
      _dataFimFiltro = DateTime(
        picked.end.year,
        picked.end.month,
        picked.end.day,
        23,
        59,
        59,
      );
      _atualizarFinanceiro(resetPagina: true);
    }
  }

  void _mostrarModalNovaReceita() {
    final tituloC = TextEditingController();
    final donoC = TextEditingController();
    final valorC = TextEditingController();
    String categoria = 'Assinaturas';
    bool isLoading = false;

    InputDecoration fieldDeco(String label, {String? hint}) {
      return InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: GoogleFonts.plusJakartaSans(
          fontWeight: FontWeight.w600,
          fontSize: 13,
          color: PainelAdminTheme.textoSecundario,
        ),
        floatingLabelStyle: GoogleFonts.plusJakartaSans(
          fontWeight: FontWeight.w700,
          color: PainelAdminTheme.roxo,
        ),
        filled: true,
        fillColor: const Color(0xFFF8FAFC),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide:
              const BorderSide(color: PainelAdminTheme.roxo, width: 1.6),
        ),
      );
    }

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setS) {
            Future<void> salvarReceita() async {
              if (tituloC.text.isEmpty ||
                  donoC.text.isEmpty ||
                  valorC.text.isEmpty) {
                mostrarSnackPainel(context,
                    erro: true, mensagem: 'Preencha todos os campos.');
                return;
              }
              setS(() => isLoading = true);

              try {
                final valor =
                    double.tryParse(valorC.text.replaceAll(',', '.')) ?? 0.0;

                await FirebaseFirestore.instance
                    .collection('receitas_app')
                    .add({
                  'titulo_referencia': tituloC.text.trim(),
                  'nome_pagador': donoC.text.trim(),
                  'tipo_receita': categoria,
                  'valor_total': valor,
                  'data_registro': FieldValue.serverTimestamp(),
                });

                if (context.mounted) {
                  Navigator.pop(context);
                  _atualizarFinanceiro(resetPagina: true);
                  mostrarSnackPainel(context,
                      mensagem: 'Receita registrada com sucesso!');
                }
              } catch (e) {
                if (context.mounted) {
                  mostrarSnackPainel(context,
                      erro: true, mensagem: 'Erro: $e');
                }
              } finally {
                setS(() => isLoading = false);
              }
            }

            final maxH = MediaQuery.sizeOf(context).height * 0.9;
            return Dialog(
              backgroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: 480, maxHeight: maxH),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(22, 20, 8, 12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: PainelAdminTheme.roxo.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color:
                                    PainelAdminTheme.roxo.withValues(alpha: 0.15),
                              ),
                            ),
                            child: Icon(
                              Icons.add_card_outlined,
                              color: PainelAdminTheme.roxo,
                              size: 26,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Lançar receita manual',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 19,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -0.3,
                                    color: PainelAdminTheme.dashboardInk,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'PIX ou dinheiro fora do fluxo automático.',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 13,
                                    height: 1.35,
                                    color: PainelAdminTheme.textoSecundario,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.pop(context),
                            icon: Icon(
                              Icons.close_rounded,
                              color: PainelAdminTheme.textoSecundario,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1, color: Color(0xFFE2E8F0)),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(22, 18, 22, 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            TextField(
                              controller: tituloC,
                              style: GoogleFonts.plusJakartaSans(fontSize: 14),
                              decoration: fieldDeco(
                                'Referência',
                                hint: 'Ex.: Mensalidade VIP',
                              ),
                            ),
                            const SizedBox(height: 14),
                            TextField(
                              controller: donoC,
                              style: GoogleFonts.plusJakartaSans(fontSize: 14),
                              decoration: fieldDeco(
                                'Pagador',
                                hint: 'Ex.: Lanchonete do Zé',
                              ),
                            ),
                            const SizedBox(height: 14),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  flex: 3,
                                  child: DropdownButtonFormField<String>(
                                    // ignore: deprecated_member_use
                                    value: categoria,
                                    decoration: fieldDeco('Categoria'),
                                    dropdownColor: Colors.white,
                                    borderRadius: BorderRadius.circular(12),
                                    items: const [
                                      DropdownMenuItem(
                                        value: 'Assinaturas',
                                        child: Text('Assinatura'),
                                      ),
                                      DropdownMenuItem(
                                        value: 'Comissões Lojas',
                                        child: Text('Comissão loja'),
                                      ),
                                      DropdownMenuItem(
                                        value: 'Taxas Entregadores',
                                        child: Text('Taxa entregador'),
                                      ),
                                      DropdownMenuItem(
                                        value: 'Destaques',
                                        child: Text('Destaque / banner'),
                                      ),
                                      DropdownMenuItem(
                                        value: 'Premium',
                                        child: Text('Telefone premium'),
                                      ),
                                      DropdownMenuItem(
                                        value: 'Eventos',
                                        child: Text('Eventos pagos'),
                                      ),
                                      DropdownMenuItem(
                                        value: 'Outros',
                                        child: Text('Outros'),
                                      ),
                                    ],
                                    onChanged: (val) {
                                      if (val != null) {
                                        setS(() => categoria = val);
                                      }
                                    },
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  flex: 2,
                                  child: TextField(
                                    controller: valorC,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                            decimal: true),
                                    style:
                                        GoogleFonts.plusJakartaSans(fontSize: 14),
                                    decoration: fieldDeco(
                                      'Valor',
                                      hint: '0,00',
                                    ).copyWith(prefixText: 'R\$ '),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const Divider(height: 1, color: Color(0xFFE2E8F0)),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed:
                                  isLoading ? null : () => Navigator.pop(context),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: PainelAdminTheme.roxo,
                                side: BorderSide(
                                  color: PainelAdminTheme.roxo
                                      .withValues(alpha: 0.35),
                                ),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: Text(
                                'Cancelar',
                                style: GoogleFonts.plusJakartaSans(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: FilledButton.icon(
                              onPressed: isLoading ? null : salvarReceita,
                              icon: isLoading
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(Icons.check_rounded, size: 20),
                              label: Text(
                                isLoading ? 'Salvando…' : 'Registrar',
                                style: GoogleFonts.plusJakartaSans(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                ),
                              ),
                              style: FilledButton.styleFrom(
                                backgroundColor: PainelAdminTheme.roxo,
                                foregroundColor: Colors.white,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
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
        );
      },
    );
  }

  void _mostrarModalNovaDespesa() {
    final tituloC = TextEditingController();
    final beneficiarioC = TextEditingController();
    final valorC = TextEditingController();
    String categoria = 'Outros';
    bool isLoading = false;

    InputDecoration fieldDeco(String label, {String? hint}) {
      return InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: GoogleFonts.plusJakartaSans(
          fontWeight: FontWeight.w600,
          fontSize: 13,
          color: PainelAdminTheme.textoSecundario,
        ),
        floatingLabelStyle: GoogleFonts.plusJakartaSans(
          fontWeight: FontWeight.w700,
          color: PainelAdminTheme.roxo,
        ),
        filled: true,
        fillColor: const Color(0xFFF8FAFC),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide:
              const BorderSide(color: PainelAdminTheme.roxo, width: 1.6),
        ),
      );
    }

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setS) {
            Future<void> salvarDespesa() async {
              if (tituloC.text.isEmpty ||
                  beneficiarioC.text.isEmpty ||
                  valorC.text.isEmpty) {
                mostrarSnackPainel(context,
                    erro: true, mensagem: 'Preencha todos os campos.');
                return;
              }
              setS(() => isLoading = true);

              try {
                final valor =
                    double.tryParse(valorC.text.replaceAll(',', '.')) ?? 0.0;

                await FirebaseFirestore.instance
                    .collection('despesas_app')
                    .add({
                  'titulo_referencia': tituloC.text.trim(),
                  'nome_beneficiario': beneficiarioC.text.trim(),
                  'tipo_despesa': categoria,
                  'valor_total': valor,
                  'data_registro': FieldValue.serverTimestamp(),
                });

                if (context.mounted) {
                  Navigator.pop(context);
                  _atualizarFinanceiro();
                  mostrarSnackPainel(context,
                      mensagem: 'Saída registrada com sucesso!');
                }
              } catch (e) {
                if (context.mounted) {
                  mostrarSnackPainel(context,
                      erro: true, mensagem: 'Erro: $e');
                }
              } finally {
                setS(() => isLoading = false);
              }
            }

            final maxH = MediaQuery.sizeOf(context).height * 0.9;
            return Dialog(
              backgroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: 480, maxHeight: maxH),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(22, 20, 8, 12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(0xFF334155)
                                  .withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: const Color(0xFF334155)
                                    .withValues(alpha: 0.2),
                              ),
                            ),
                            child: const Icon(
                              Icons.trending_down_rounded,
                              color: Color(0xFF334155),
                              size: 26,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Registrar saída',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 19,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -0.3,
                                    color: PainelAdminTheme.dashboardInk,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Despesas e pagamentos fora do fluxo de receitas.',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 13,
                                    height: 1.35,
                                    color: PainelAdminTheme.textoSecundario,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.pop(context),
                            icon: Icon(
                              Icons.close_rounded,
                              color: PainelAdminTheme.textoSecundario,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1, color: Color(0xFFE2E8F0)),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(22, 18, 22, 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            TextField(
                              controller: tituloC,
                              style: GoogleFonts.plusJakartaSans(fontSize: 14),
                              decoration: fieldDeco(
                                'Referência',
                                hint: 'Ex.: Hospedagem servidor',
                              ),
                            ),
                            const SizedBox(height: 14),
                            TextField(
                              controller: beneficiarioC,
                              style: GoogleFonts.plusJakartaSans(fontSize: 14),
                              decoration: fieldDeco(
                                'Beneficiário / fornecedor',
                                hint: 'Ex.: AWS, contador',
                              ),
                            ),
                            const SizedBox(height: 14),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  flex: 3,
                                  child: DropdownButtonFormField<String>(
                                    // ignore: deprecated_member_use
                                    value: categoria,
                                    decoration: fieldDeco('Categoria'),
                                    dropdownColor: Colors.white,
                                    borderRadius: BorderRadius.circular(12),
                                    items: const [
                                      DropdownMenuItem(
                                        value: 'Infraestrutura',
                                        child: Text('Infraestrutura'),
                                      ),
                                      DropdownMenuItem(
                                        value: 'Marketing',
                                        child: Text('Marketing'),
                                      ),
                                      DropdownMenuItem(
                                        value: 'Impostos',
                                        child: Text('Impostos'),
                                      ),
                                      DropdownMenuItem(
                                        value: 'Pessoal',
                                        child: Text('Pessoal'),
                                      ),
                                      DropdownMenuItem(
                                        value: 'Repasses',
                                        child: Text('Repasses'),
                                      ),
                                      DropdownMenuItem(
                                        value: 'Outros',
                                        child: Text('Outros'),
                                      ),
                                    ],
                                    onChanged: (val) {
                                      if (val != null) {
                                        setS(() => categoria = val);
                                      }
                                    },
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  flex: 2,
                                  child: TextField(
                                    controller: valorC,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                            decimal: true),
                                    style:
                                        GoogleFonts.plusJakartaSans(fontSize: 14),
                                    decoration: fieldDeco(
                                      'Valor',
                                      hint: '0,00',
                                    ).copyWith(prefixText: 'R\$ '),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const Divider(height: 1, color: Color(0xFFE2E8F0)),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed:
                                  isLoading ? null : () => Navigator.pop(context),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: PainelAdminTheme.roxo,
                                side: BorderSide(
                                  color: PainelAdminTheme.roxo
                                      .withValues(alpha: 0.35),
                                ),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: Text(
                                'Cancelar',
                                style: GoogleFonts.plusJakartaSans(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: FilledButton.icon(
                              onPressed: isLoading ? null : salvarDespesa,
                              icon: isLoading
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(Icons.check_rounded, size: 20),
                              label: Text(
                                isLoading ? 'Salvando…' : 'Registrar',
                                style: GoogleFonts.plusJakartaSans(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                ),
                              ),
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF334155),
                                foregroundColor: Colors.white,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
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
        );
      },
    );
  }

  bool _dentroFiltro(DateTime dt) {
    if (_dataInicioFiltro == null || _dataFimFiltro == null) return true;
    return !dt.isBefore(_dataInicioFiltro!) && !dt.isAfter(_dataFimFiltro!);
  }

  /// Extrai o valor total de um documento de anúncio/publicidade.
  /// Tenta `valor_total` primeiro; se não existir, calcula a partir de
  /// `valor_diario`/`valor_mensal`/`valor` + período + modalidade.
  double _extrairValorDoc(Map<String, dynamic> d) {
    final vt = _num(d['valor_total']);
    if (vt > 0) return vt;

    final tsInicio = d['data_inicio'] as Timestamp?;
    final tsFim = (d['data_fim'] ?? d['data_vencimento']) as Timestamp?;
    int dias = 1;
    if (tsInicio != null && tsFim != null) {
      dias = tsFim.toDate().difference(tsInicio.toDate()).inDays;
      if (dias <= 0) dias = 1;
    }

    final modalidade = (d['modalidade_valor'] ?? d['tipo_cobranca'] ?? 'diario').toString();

    final vMensal = _num(d['valor_mensal']);
    if (vMensal > 0) {
      final meses = (dias / 30).ceil().clamp(1, 9999);
      return vMensal * meses;
    }

    final vDiario = _num(d['valor_diario']);
    if (vDiario > 0) return vDiario * dias;

    final vBase = _num(d['valor']);
    if (vBase <= 0) return 0;

    switch (modalidade) {
      case 'fixo':
        return vBase;
      case 'mensal':
        final meses = (dias / 30).ceil().clamp(1, 9999);
        return vBase * meses;
      case 'hora':
        final horas = dias * 24;
        return vBase * horas;
      case 'dia':
      case 'diario':
      default:
        return vBase * dias;
    }
  }

  Future<Map<String, dynamic>> _buscarDadosFinanceiros() async {
    double totalComissoes = 0;
    double totalTaxasEntrega = 0;
    double totalEventos = 0;
    double totalPremium = 0;
    double totalDestaques = 0;
    double totalVagas = 0;

    final historico = <Map<String, dynamic>>[];
    double totalSaidas = 0;

    // ── 1. Comissões e Taxas de corrida ──
    // Fonte primária: pedidos entregues com campos financeiros calculados.
    // Fonte secundária: receitas_app (entradas manuais ou legado).
    try {
      final pedidosSnap = await FirebaseFirestore.instance
          .collection('pedidos')
          .where('status', isEqualTo: 'entregue')
          .get();

      for (final doc in pedidosSnap.docs) {
        final d = doc.data();
        final ts = (d['data_entregue'] ?? d['data_pedido'] ?? d['data_entrega'] ?? d['data_criacao']) as Timestamp?;
        if (ts != null && !_dentroFiltro(ts.toDate())) continue;

        totalComissoes += _num(d['taxa_plataforma']);
        totalTaxasEntrega += _num(d['taxa_entregador']);
      }
    } catch (_) {}

    // Leitura única de receitas_app (usada para KPIs de comissões/taxas + extrato)
    final receitasSnap = await FirebaseFirestore.instance
        .collection('receitas_app')
        .orderBy('data_registro', descending: true)
        .get();

    for (final doc in receitasSnap.docs) {
      final d = doc.data();
      final tsR = d['data_registro'] as Timestamp?;
      if (tsR == null) continue;
      if (!_dentroFiltro(tsR.toDate())) continue;

      final valor = _num(d['valor_total']);
      if (valor <= 0) continue;
      final tipo = (d['tipo_receita'] ?? '') as String;

      if (tipo == 'Comissões Lojas') {
        totalComissoes += valor;
      } else if (tipo == 'Taxas Entregadores') {
        totalTaxasEntrega += valor;
      }

      historico.add({
        'movimento': 'lucro',
        'tipo': tipo,
        'titulo': d['titulo_referencia'] ?? 'Sem título',
        'dono': d['nome_pagador'] ?? 'Não informado',
        'valor': valor,
        'data': tsR.toDate(),
      });
    }

    // ── 2. Destaques — servicos_destaque (ativos com valor) ──
    final destaquesSnap = await FirebaseFirestore.instance
        .collection('servicos_destaque')
        .where('ativo', isEqualTo: true)
        .get();

    for (final doc in destaquesSnap.docs) {
      final d = doc.data();
      final v = _extrairValorDoc(d);
      if (v <= 0) continue;
      final tsI = (d['data_inicio'] ?? d['data_criacao']) as Timestamp?;
      if (tsI != null && !_dentroFiltro(tsI.toDate())) continue;
      totalDestaques += v;
    }

    // ── 3. Banners — coleção banners (ativos) ──
    final bannersSnap = await FirebaseFirestore.instance
        .collection('banners')
        .where('ativo', isEqualTo: true)
        .get();

    for (final doc in bannersSnap.docs) {
      final d = doc.data();
      final v = _extrairValorDoc(d);
      if (v <= 0) continue;
      final tsI = (d['data_inicio'] ?? d['data_criacao']) as Timestamp?;
      if (tsI != null && !_dentroFiltro(tsI.toDate())) continue;
      totalDestaques += v;
    }

    // ── 4. Premium — telefones_premium (ativos com valor) ──
    final premiumSnap = await FirebaseFirestore.instance
        .collection('telefones_premium')
        .where('ativo', isEqualTo: true)
        .get();

    for (final doc in premiumSnap.docs) {
      final d = doc.data();
      final v = _extrairValorDoc(d);
      if (v <= 0) continue;
      final tsI = (d['data_inicio'] ?? d['data_criacao']) as Timestamp?;
      if (tsI != null && !_dentroFiltro(tsI.toDate())) continue;
      totalPremium += v;
    }

    // ── 5. Eventos pagos — coleção eventos (ativos com valor) ──
    final eventosSnap = await FirebaseFirestore.instance
        .collection('eventos')
        .where('ativo', isEqualTo: true)
        .get();

    for (final doc in eventosSnap.docs) {
      final d = doc.data();
      final v = _extrairValorDoc(d);
      if (v <= 0) continue;
      final tsI = (d['data_inicio'] ?? d['data_criacao']) as Timestamp?;
      if (tsI != null && !_dentroFiltro(tsI.toDate())) continue;
      totalEventos += v;
    }

    // ── 5b. Vagas — coleção vagas (ativos com valor) ──
    final vagasSnap = await FirebaseFirestore.instance
        .collection('vagas')
        .where('ativo', isEqualTo: true)
        .get();

    for (final doc in vagasSnap.docs) {
      final d = doc.data();
      final v = _extrairValorDoc(d);
      if (v <= 0) continue;
      final tsI = (d['data_inicio'] ?? d['data_criacao']) as Timestamp?;
      if (tsI != null && !_dentroFiltro(tsI.toDate())) continue;
      totalVagas += v;
    }

    // ── 6. Despesas — coleção despesas_app ──
    try {
      final despesasSnap = await FirebaseFirestore.instance
          .collection('despesas_app')
          .orderBy('data_registro', descending: true)
          .get();

      for (final doc in despesasSnap.docs) {
        final d = doc.data();
        final tsRegistro = d['data_registro'] as Timestamp?;
        if (tsRegistro == null) continue;
        final dataRegistro = tsRegistro.toDate();
        if (!_dentroFiltro(dataRegistro)) continue;

        final valor = _num(d['valor_total']);
        totalSaidas += valor;
        historico.add({
          'movimento': 'despesa',
          'tipo': d['tipo_despesa'] ?? 'Outros',
          'titulo': d['titulo_referencia'] ?? 'Sem título',
          'dono': d['nome_beneficiario'] ?? 'Não informado',
          'valor': valor,
          'data': dataRegistro,
        });
      }
    } catch (_) {
      totalSaidas = 0;
    }

    historico.sort(
      (a, b) => (b['data'] as DateTime).compareTo(a['data'] as DateTime),
    );

    final totalGeral =
        totalComissoes + totalTaxasEntrega + totalDestaques + totalPremium + totalEventos + totalVagas;

    return {
      'totalGeral': totalGeral,
      'totalSaidas': totalSaidas,
      'totalComissoes': totalComissoes,
      'totalTaxasEntrega': totalTaxasEntrega,
      'totalEventos': totalEventos,
      'totalPremium': totalPremium,
      'totalDestaques': totalDestaques,
      'totalVagas': totalVagas,
      'historico': historico,
    };
  }

  String _formatarData(DateTime d) {
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} · ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  String _rotuloCategoria(String tipo) {
    switch (tipo) {
      case 'Comissões Lojas':
        return 'Comissões (lojas)';
      case 'Taxas Entregadores':
        return 'Taxas (corridas)';
      case 'Assinaturas':
        return 'Assinaturas VIP';
      case 'Destaques':
      case 'Banners':
        return 'Destaques / banners';
      case 'Premium':
        return 'Premium (telefones)';
      case 'Eventos':
        return 'Eventos pagos';
      default:
        return tipo.toString();
    }
  }

  String _rotuloCategoriaLinha(Map<String, dynamic> item) {
    final m = item['movimento'] as String? ?? 'lucro';
    if (m == 'despesa') {
      return item['tipo'] as String? ?? 'Despesa';
    }
    return _rotuloCategoria(item['tipo'] as String);
  }

  List<Map<String, dynamic>> _filtrarHistoricoExtrato(
    List<Map<String, dynamic>> todos,
  ) {
    switch (_filtroExtratoMovimento) {
      case _FiltroExtratoMovimento.todos:
        return List<Map<String, dynamic>>.from(todos);
      case _FiltroExtratoMovimento.lucro:
        return todos
            .where((e) => (e['movimento'] as String? ?? 'lucro') == 'lucro')
            .toList();
      case _FiltroExtratoMovimento.despesa:
        return todos.where((e) => e['movimento'] == 'despesa').toList();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PainelAdminTheme.fundoCanvas,
      floatingActionButton: const BotaoSuporteFlutuante(),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _futureFinanceiro,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(
              child: CircularProgressIndicator(
                color: PainelAdminTheme.roxo,
                strokeWidth: 2.5,
              ),
            );
          }
          if (!snapshot.hasData) {
            return Center(
              child: Text(
                'Erro ao carregar os dados financeiros.',
                style: GoogleFonts.plusJakartaSans(
                  color: const Color(0xFFDC2626),
                ),
              ),
            );
          }

          final dados = snapshot.data!;
          final historicoCompleto =
              dados['historico'] as List<Map<String, dynamic>>;
          final historico = _filtrarHistoricoExtrato(historicoCompleto);

          return LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 88),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1200),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildHeader(context),
                        const SizedBox(height: 22),
                        LayoutBuilder(
                          builder: (context, c) {
                            final wide = c.maxWidth >= 900;
                            if (wide) {
                              return Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SizedBox(
                                    width: 280,
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        _cardTotalPeriodo(
                                          dados['totalGeral'] as double,
                                          dados['totalSaidas'] as double,
                                        ),
                                        const SizedBox(height: 14),
                                        _cardTotalSaidas(
                                          dados['totalSaidas'] as double,
                                        ),
                                        const SizedBox(height: 14),
                                        _cardLiquido(
                                          dados['totalGeral'] as double,
                                          dados['totalSaidas'] as double,
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 20),
                                  Expanded(
                                    child: _gridKpis(dados, crossAxisCount: 3),
                                  ),
                                ],
                              );
                            }
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _cardTotalPeriodo(
                                  dados['totalGeral'] as double,
                                  dados['totalSaidas'] as double,
                                ),
                                const SizedBox(height: 14),
                                _cardTotalSaidas(
                                  dados['totalSaidas'] as double,
                                ),
                                const SizedBox(height: 14),
                                _cardLiquido(
                                  dados['totalGeral'] as double,
                                  dados['totalSaidas'] as double,
                                ),
                                const SizedBox(height: 16),
                                _gridKpis(dados, crossAxisCount: 2),
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 28),
                        _buildExtratoHeader(
                          totalFiltrado: historico.length,
                          totalSemFiltro: historicoCompleto.length,
                        ),
                        const SizedBox(height: 12),
                        _buildExtratoLista(
                          historico,
                          totalSemFiltro: historicoCompleto.length,
                        ),
                        const SizedBox(height: 28),
                        _bannerSolicitacoesSaques(context),
                        const SizedBox(height: 36),
                        _buildEstornosSection(),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final periodoChip = _dataInicioFiltro != null && _dataFimFiltro != null
        ? '${_dataInicioFiltro!.day.toString().padLeft(2, '0')}/${_dataInicioFiltro!.month.toString().padLeft(2, '0')} – ${_dataFimFiltro!.day.toString().padLeft(2, '0')}/${_dataFimFiltro!.month.toString().padLeft(2, '0')}/${_dataFimFiltro!.year}'
        : null;

    return Container(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Color(0xFFE2E8F0)),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, c) {
          final narrow = c.maxWidth < 720;
          if (narrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _tituloHeader(),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _headerActions(periodoChip),
                ),
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _tituloHeader()),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                alignment: WrapAlignment.end,
                children: _headerActions(periodoChip),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _tituloHeader() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: PainelAdminTheme.roxo.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(
            Icons.account_balance_wallet_outlined,
            color: PainelAdminTheme.roxo,
            size: 28,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Livro caixa (visão global)',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: PainelAdminTheme.dashboardInk,
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Entradas e saídas registradas no aplicativo.',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  height: 1.4,
                  color: PainelAdminTheme.textoSecundario,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  List<Widget> _headerActions(String? periodoChip) {
    return [
      FilledButton.tonalIcon(
        onPressed: _mostrarModalNovaReceita,
        icon: const Icon(Icons.add_rounded, size: 20),
        label: Text(
          'Nova receita',
          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
        ),
        style: FilledButton.styleFrom(
          foregroundColor: PainelAdminTheme.roxo,
          backgroundColor: PainelAdminTheme.roxo.withValues(alpha: 0.12),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      FilledButton.tonalIcon(
        onPressed: _mostrarModalNovaDespesa,
        icon: const Icon(Icons.trending_down_rounded, size: 20),
        label: Text(
          'Registrar saída',
          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
        ),
        style: FilledButton.styleFrom(
          foregroundColor: const Color(0xFF334155),
          backgroundColor: const Color(0xFF334155).withValues(alpha: 0.1),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      FilledButton.icon(
        onPressed: _escolherPeriodo,
        icon: const Icon(Icons.date_range_rounded, size: 20),
        label: Text(
          periodoChip ?? 'Filtrar período',
          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
        ),
        style: FilledButton.styleFrom(
          backgroundColor: PainelAdminTheme.laranja,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      if (_dataInicioFiltro != null)
        TextButton.icon(
          onPressed: () {
            _dataInicioFiltro = null;
            _dataFimFiltro = null;
            _atualizarFinanceiro(resetPagina: true);
          },
          icon: Icon(Icons.clear_rounded, size: 18, color: Colors.red.shade700),
          label: Text(
            'Limpar filtro',
            style: GoogleFonts.plusJakartaSans(
              fontWeight: FontWeight.w600,
              color: Colors.red.shade700,
            ),
          ),
        ),
    ];
  }

  Widget _cardTotalPeriodo(double entradas, double saidas) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            PainelAdminTheme.roxo,
            PainelAdminTheme.roxoEscuro,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: PainelAdminTheme.sombraCardSuave(),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'Faturamento',
            style: GoogleFonts.plusJakartaSans(
              color: Colors.white.withValues(alpha: 0.85),
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Entradas Efetuadas no Período.',
            style: GoogleFonts.plusJakartaSans(
              color: Colors.white.withValues(alpha: 0.65),
              fontSize: 10.5,
              fontWeight: FontWeight.w500,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _brl.format(entradas),
            style: GoogleFonts.plusJakartaSans(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
              height: 1.1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _cardTotalSaidas(double total) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            Color(0xFF334155),
            Color(0xFF1E293B),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: PainelAdminTheme.sombraCardSuave(),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'Despesas',
            style: GoogleFonts.plusJakartaSans(
              color: Colors.white.withValues(alpha: 0.88),
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Pagamentos Efetuados no Período.',
            style: GoogleFonts.plusJakartaSans(
              color: Colors.white.withValues(alpha: 0.65),
              fontSize: 10.5,
              fontWeight: FontWeight.w500,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _brl.format(total),
            style: GoogleFonts.plusJakartaSans(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
              height: 1.1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _cardLiquido(double entradas, double saidas) {
    final liquido = entradas - saidas;
    final positivo = liquido >= 0;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: positivo
              ? [const Color(0xFF059669), const Color(0xFF047857)]
              : [const Color(0xFFDC2626), const Color(0xFFB91C1C)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: PainelAdminTheme.sombraCardSuave(),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Icon(
                positivo
                    ? Icons.trending_up_rounded
                    : Icons.trending_down_rounded,
                color: Colors.white.withValues(alpha: 0.85),
                size: 16,
              ),
              const SizedBox(width: 6),
              Text(
                'Resultado Líquido',
                style: GoogleFonts.plusJakartaSans(
                  color: Colors.white.withValues(alpha: 0.88),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            'Faturamento − Despesas',
            style: GoogleFonts.plusJakartaSans(
              color: Colors.white.withValues(alpha: 0.65),
              fontSize: 10.5,
              fontWeight: FontWeight.w500,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _brl.format(liquido),
            style: GoogleFonts.plusJakartaSans(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
              height: 1.1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _gridKpis(Map<String, dynamic> dados, {required int crossAxisCount}) {
    final itens = <_KpiItem>[
      _KpiItem(
        'Comissões (lojas)',
        dados['totalComissoes'] as double,
        const Color(0xFF2563EB),
        Icons.storefront_outlined,
      ),
      _KpiItem(
        'Taxas (corridas)',
        dados['totalTaxasEntrega'] as double,
        const Color(0xFFDC2626),
        Icons.two_wheeler_outlined,
      ),
      _KpiItem(
        'Destaques & banners',
        dados['totalDestaques'] as double,
        PainelAdminTheme.laranja,
        Icons.star_outline_rounded,
      ),
      _KpiItem(
        'Premium (telefones)',
        dados['totalPremium'] as double,
        const Color(0xFF0D9488),
        Icons.phone_forwarded_outlined,
      ),
      _KpiItem(
        'Eventos pagos',
        dados['totalEventos'] as double,
        PainelAdminTheme.roxoEscuro,
        Icons.celebration_outlined,
      ),
      _KpiItem(
        'Vagas',
        (dados['totalVagas'] as double?) ?? 0,
        const Color(0xFF059669),
        Icons.work_outline_rounded,
      ),
    ];

    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: crossAxisCount,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: crossAxisCount >= 3 ? 2.15 : 1.85,
      children: itens.map((e) => _kpiCard(e)).toList(),
    );
  }

  Widget _kpiCard(_KpiItem e) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: PainelAdminTheme.dashboardCard(),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: e.accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(e.icon, color: e.accent, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  e.titulo,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: PainelAdminTheme.textoSecundario,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _brl.format(e.valor),
                  textAlign: TextAlign.right,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: PainelAdminTheme.dashboardInk,
                    letterSpacing: -0.2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExtratoHeader({
    required int totalFiltrado,
    required int totalSemFiltro,
  }) {
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Text(
        '$totalFiltrado ${totalFiltrado == 1 ? 'lançamento' : 'lançamentos'}',
        style: GoogleFonts.plusJakartaSans(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: PainelAdminTheme.textoSecundario,
        ),
      ),
    );

    final filtro = SegmentedButton<_FiltroExtratoMovimento>(
      showSelectedIcon: false,
      segments: [
        ButtonSegment(
          value: _FiltroExtratoMovimento.todos,
          label: Text(
            'Todos',
            style: GoogleFonts.plusJakartaSans(
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ),
        ButtonSegment(
          value: _FiltroExtratoMovimento.lucro,
          label: Text(
            'Lucro',
            style: GoogleFonts.plusJakartaSans(
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ),
        ButtonSegment(
          value: _FiltroExtratoMovimento.despesa,
          label: Text(
            'Despesas',
            style: GoogleFonts.plusJakartaSans(
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ),
      ],
      selected: {_filtroExtratoMovimento},
      onSelectionChanged: (Set<_FiltroExtratoMovimento> next) {
        setState(() {
          _filtroExtratoMovimento = next.first;
          _paginaExtrato = 0;
        });
      },
      style: SegmentedButton.styleFrom(
        selectedBackgroundColor: PainelAdminTheme.roxo.withValues(alpha: 0.12),
        selectedForegroundColor: PainelAdminTheme.roxo,
        foregroundColor: PainelAdminTheme.textoSecundario,
        side: const BorderSide(color: Color(0xFFE2E8F0)),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        visualDensity: VisualDensity.compact,
      ),
    );

    return LayoutBuilder(
      builder: (context, c) {
        final narrow = c.maxWidth < 720;
        final titulo = Text(
          'Extrato financeiro',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: PainelAdminTheme.dashboardInk,
          ),
        );

        if (narrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  titulo,
                  const SizedBox(width: 10),
                  chip,
                ],
              ),
              if (totalSemFiltro != totalFiltrado) ...[
                const SizedBox(height: 6),
                Text(
                  'de $totalSemFiltro no período',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    color: PainelAdminTheme.textoSecundario,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: filtro,
                ),
              ),
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            titulo,
            const SizedBox(width: 10),
            chip,
            if (totalSemFiltro != totalFiltrado) ...[
              const SizedBox(width: 8),
              Text(
                'de $totalSemFiltro no período',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  color: PainelAdminTheme.textoSecundario,
                ),
              ),
            ],
            const Spacer(),
            filtro,
          ],
        );
      },
    );
  }

  Widget _buildExtratoLista(
    List<Map<String, dynamic>> historico, {
    required int totalSemFiltro,
  }) {
    if (totalSemFiltro == 0) {
      if (_paginaExtrato != 0) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _paginaExtrato = 0);
        });
      }
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
        decoration: PainelAdminTheme.dashboardCard(),
        child: Center(
          child: Text(
            _dataInicioFiltro != null
                ? 'Nenhum lançamento neste período.'
                : 'Nenhum lançamento registrado.',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 14,
              color: PainelAdminTheme.textoSecundario,
            ),
          ),
        ),
      );
    }

    if (historico.isEmpty) {
      if (_paginaExtrato != 0) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _paginaExtrato = 0);
        });
      }
      String msg;
      switch (_filtroExtratoMovimento) {
        case _FiltroExtratoMovimento.lucro:
          msg = 'Nenhuma entrada (lucro) com o filtro atual.';
          break;
        case _FiltroExtratoMovimento.despesa:
          msg = 'Nenhuma despesa com o filtro atual.';
          break;
        case _FiltroExtratoMovimento.todos:
          msg = 'Nenhum lançamento.';
          break;
      }
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
        decoration: PainelAdminTheme.dashboardCard(),
        child: Center(
          child: Text(
            msg,
            textAlign: TextAlign.center,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 14,
              color: PainelAdminTheme.textoSecundario,
            ),
          ),
        ),
      );
    }

    final total = historico.length;
    final totalPaginas = (total + _kExtratoItensPorPagina - 1) ~/ _kExtratoItensPorPagina;
    final maxPagina = totalPaginas > 0 ? totalPaginas - 1 : 0;
    final pagina = _paginaExtrato.clamp(0, maxPagina);
    if (pagina != _paginaExtrato) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() => _paginaExtrato = pagina);
        }
      });
    }

    final inicio = pagina * _kExtratoItensPorPagina;
    final fim = math.min(inicio + _kExtratoItensPorPagina, total);
    final paginaItens = historico.sublist(inicio, fim);

    Widget tabela = Container(
      decoration: PainelAdminTheme.dashboardCard(),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: const BoxDecoration(
              color: Color(0xFFF8FAFC),
              border: Border(
                bottom: BorderSide(color: Color(0xFFE2E8F0)),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  flex: 5,
                  child: Text(
                    'Descrição',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                      color: PainelAdminTheme.textoSecundario,
                    ),
                  ),
                ),
                SizedBox(
                  width: 120,
                  child: Text(
                    'Categoria',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                      color: PainelAdminTheme.textoSecundario,
                    ),
                  ),
                ),
                SizedBox(
                  width: 130,
                  child: Text(
                    'Valor',
                    textAlign: TextAlign.right,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                      color: PainelAdminTheme.textoSecundario,
                    ),
                  ),
                ),
              ],
            ),
          ),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: paginaItens.length,
            separatorBuilder: (_, _) => const Divider(height: 1, thickness: 0.5),
            itemBuilder: (context, index) {
              final item = paginaItens[index];
              final movimento = item['movimento'] as String? ?? 'lucro';
              final isDespesa = movimento == 'despesa';
              final corMov = isDespesa
                  ? const Color(0xFFDC2626)
                  : const Color(0xFF059669);
              final icone = isDespesa
                  ? Icons.north_east_rounded
                  : Icons.south_west_rounded;
              final prefixoValor = isDespesa ? '- ' : '+ ';
              final zebra = index.isEven;
              return Material(
                color: zebra
                    ? const Color(0xFFFAFBFC)
                    : Colors.white,
                child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Icon(
                            icone,
                            size: 18,
                            color: corMov,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 5,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${item['titulo']}',
                                style: GoogleFonts.plusJakartaSans(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                  color: PainelAdminTheme.dashboardInk,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${item['dono']} · ${_formatarData(item['data'] as DateTime)}',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 12,
                                  height: 1.35,
                                  color: PainelAdminTheme.textoSecundario,
                                ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(
                          width: 120,
                          child: Text(
                            _rotuloCategoriaLinha(item),
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: PainelAdminTheme.textoSecundario,
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 130,
                          child: Text(
                            '$prefixoValor${_brl.format(item['valor'] as double)}',
                            textAlign: TextAlign.right,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: corMov,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
            },
          ),
          if (totalPaginas > 1)
            _buildPaginacaoLista(
              paginaAtual: pagina,
              totalPaginas: totalPaginas,
              totalItens: total,
              indiceInicioExibido: inicio + 1,
              indiceFimExibido: fim,
              onAnterior: pagina > 0
                  ? () => setState(() => _paginaExtrato = pagina - 1)
                  : null,
              onProxima: pagina < totalPaginas - 1
                  ? () => setState(() => _paginaExtrato = pagina + 1)
                  : null,
            ),
        ],
      ),
    );

    return LayoutBuilder(
      builder: (context, c) {
        if (c.maxWidth < 640) {
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: c.maxWidth < 400 ? 520 : 600),
              child: tabela,
            ),
          );
        }
        return tabela;
      },
    );
  }

  /// Barra de paginação reutilizável (extrato e histórico de estornos).
  Widget _buildPaginacaoLista({
    required int paginaAtual,
    required int totalPaginas,
    required int totalItens,
    required int indiceInicioExibido,
    required int indiceFimExibido,
    required VoidCallback? onAnterior,
    required VoidCallback? onProxima,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: const BoxDecoration(
        color: Color(0xFFF8FAFC),
        border: Border(
          top: BorderSide(color: Color(0xFFE2E8F0)),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, c) {
          final narrow = c.maxWidth < 520;
          final textoFaixa = GoogleFonts.plusJakartaSans(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: PainelAdminTheme.textoSecundario,
          );
          final textoPagina = GoogleFonts.plusJakartaSans(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: PainelAdminTheme.dashboardInk,
          );

          final botoes = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton.icon(
                onPressed: onAnterior,
                icon: const Icon(Icons.chevron_left_rounded, size: 20),
                label: Text(
                  'Anterior',
                  style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
                ),
                style: TextButton.styleFrom(
                  foregroundColor: PainelAdminTheme.roxo,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                ),
              ),
              const SizedBox(width: 4),
              TextButton.icon(
                onPressed: onProxima,
                icon: const Icon(Icons.chevron_right_rounded, size: 20),
                label: Text(
                  'Próxima',
                  style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
                ),
                style: TextButton.styleFrom(
                  foregroundColor: PainelAdminTheme.roxo,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                ),
              ),
            ],
          );

          final faixa = Text(
            'Exibindo $indiceInicioExibido–$indiceFimExibido de $totalItens',
            style: textoFaixa,
            textAlign: TextAlign.center,
          );
          final paginaTxt = Text(
            'Página ${paginaAtual + 1} de $totalPaginas',
            style: textoPagina,
            textAlign: TextAlign.center,
          );

          if (narrow) {
            return Column(
              children: [
                faixa,
                const SizedBox(height: 4),
                paginaTxt,
                const SizedBox(height: 10),
                botoes,
              ],
            );
          }

          return Row(
            children: [
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: faixa,
                ),
              ),
              botoes,
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: paginaTxt,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Atalho para a fila dedicada de saques (menu Gestão → Solicitações de saque).
  Widget _bannerSolicitacoesSaques(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('saques_solicitacoes')
          .where('status', isEqualTo: 'pendente')
          .snapshots(),
      builder: (context, snap) {
        final n = snap.data?.docs.length ?? 0;
        final roxo = PainelAdminTheme.roxo;
        return Material(
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: roxo.withValues(alpha: 0.2)),
          ),
          child: InkWell(
            onTap: () {
              PainelNavigationScope.maybeOf(context)
                  ?.navigateTo('/financeiro_saques');
            },
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  Icon(Icons.outgoing_mail, color: roxo, size: 28),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Solicitações de saque (lojistas e entregadores)',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: PainelAdminTheme.dashboardInk,
                          ),
                        ),
                        Text(
                          n > 0
                              ? '$n solicitação(ões) aguardando transferência PIX.'
                              : 'Nenhuma solicitação pendente no momento.',
                          style: TextStyle(
                            fontSize: 13,
                            color: PainelAdminTheme.textoSecundario,
                          ),
                        ),
                      ],
                    ),
                  ),
                  FilledButton.tonal(
                    onPressed: () {
                      PainelNavigationScope.maybeOf(context)
                          ?.navigateTo('/financeiro_saques');
                    },
                    child: const Text('Abrir fila'),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ─── Seção de Estornos ─────────────────────────────────────────────────────

  TextEditingController _ctrlLojaPesquisa = TextEditingController();
  late final _ctrlEstornoValor = TextEditingController();
  late final _ctrlEstornoMotivo = TextEditingController();

  String? _lojaUidSelecionado;
  List<Map<String, dynamic>> _lojasCache = [];
  bool _lojasCacheCarregado = false;

  String? _pedidoIdSelecionado;
  double? _pedidoValorSelecionado;
  List<Map<String, dynamic>> _pedidosLojaCache = [];
  bool _pedidosLojaCarregando = false;
  TextEditingController _ctrlPedidoPesquisa = TextEditingController();

  Future<void> _carregarPedidosDaLoja(String lojaUid) async {
    setState(() {
      _pedidosLojaCarregando = true;
      _pedidosLojaCache = [];
      _pedidoIdSelecionado = null;
      _pedidoValorSelecionado = null;
      _ctrlEstornoValor.clear();
    });
    try {
      final idsJaAdicionados = <String>{};
      final lista = <Map<String, dynamic>>[];

      Future<void> buscar(String campo) async {
        final snap = await FirebaseFirestore.instance
            .collection('pedidos')
            .where(campo, isEqualTo: lojaUid)
            .get();
        for (final doc in snap.docs) {
          if (idsJaAdicionados.contains(doc.id)) continue;
          final d = doc.data();
          final status = (d['status'] ?? '') as String;
          if (status != 'entregue') continue;
          final forma = (d['forma_pagamento'] ?? '').toString();
          if (forma != 'PIX' && forma != 'Cartão') continue;
          idsJaAdicionados.add(doc.id);
          final ts = (d['data_pedido'] ?? d['data_entregue'] ?? d['data_criacao']) as Timestamp?;
          final clienteNome = (d['cliente_nome'] ?? d['cliente_nome_exibicao'] ?? '') as String;
          final clienteId = (d['cliente_id'] ?? '') as String;
          final total = _num(d['total_produtos'] ?? d['subtotal'] ?? d['total'] ?? 0);
          final formaPgto = (d['forma_pagamento'] ?? '') as String;
          final totalPedido = _num(d['total'] ?? d['total_produtos'] ?? d['subtotal'] ?? 0);
          lista.add({
            'id': doc.id,
            'status': status,
            'cliente': clienteNome,
            'cliente_id': clienteId,
            'total': total,
            'total_pedido': totalPedido,
            'forma_pagamento': formaPgto,
            'data': ts?.toDate(),
          });
        }
      }

      await Future.wait([buscar('loja_id'), buscar('lojista_id')]);

      lista.sort((a, b) {
        final da = a['data'] as DateTime?;
        final db = b['data'] as DateTime?;
        if (da == null && db == null) return 0;
        if (da == null) return 1;
        if (db == null) return -1;
        return db.compareTo(da);
      });

      if (mounted) {
        setState(() {
          _pedidosLojaCache = lista;
          _pedidosLojaCarregando = false;
        });
      }
      _resolverNomesClientesPedidos(lista);
    } catch (_) {
      if (mounted) setState(() => _pedidosLojaCarregando = false);
    }
  }

  final Map<String, String> _cacheNomesClientes = {};

  Future<void> _resolverNomesClientesPedidos(List<Map<String, dynamic>> pedidos) async {
    final idsParaBuscar = <String>{};
    for (final p in pedidos) {
      final cid = (p['cliente_id'] ?? '') as String;
      final nome = (p['cliente'] ?? '') as String;
      if (cid.isNotEmpty && nome.isEmpty && !_cacheNomesClientes.containsKey(cid)) {
        idsParaBuscar.add(cid);
      }
    }
    if (idsParaBuscar.isEmpty) return;

    for (final uid in idsParaBuscar) {
      try {
        final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
        if (!mounted) return;
        final d = doc.data();
        _cacheNomesClientes[uid] = d?['nome']?.toString() ??
            d?['nome_completo']?.toString() ??
            d?['nome_exibicao']?.toString() ?? 'Cliente';
      } catch (_) {
        _cacheNomesClientes[uid] = 'Cliente';
      }
    }

    if (!mounted) return;
    for (final p in _pedidosLojaCache) {
      final cid = (p['cliente_id'] ?? '') as String;
      if (cid.isNotEmpty && ((p['cliente'] ?? '') as String).isEmpty) {
        p['cliente'] = _cacheNomesClientes[cid] ?? 'Cliente';
      }
    }
    setState(() {});
  }

  List<Map<String, dynamic>> _filtrarPedidos(String query) {
    if (query.isEmpty) return _pedidosLojaCache.take(30).toList();
    final q = query.toLowerCase();
    return _pedidosLojaCache.where((p) {
      return (p['id'] as String).toLowerCase().contains(q) ||
          (p['cliente'] as String).toLowerCase().contains(q) ||
          (p['status'] as String).toLowerCase().contains(q);
    }).take(30).toList();
  }

  Future<void> _carregarLojasSeNecessario() async {
    if (_lojasCacheCarregado) return;
    _lojasCacheCarregado = true;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .where('role', isEqualTo: 'lojista')
          .get();
      _lojasCache = snap.docs.map((doc) {
        final d = doc.data();
        return {
          'uid': doc.id,
          'nome': d['nome_loja'] ?? d['nome_fantasia'] ?? d['nomeFantasia'] ?? d['loja_nome'] ?? d['nome'] ?? doc.id,
          'cidade': d['cidade'] ?? d['endereco_cidade'] ?? '',
        };
      }).toList();
      _lojasCache.sort((a, b) =>
          (a['nome'] as String).toLowerCase().compareTo((b['nome'] as String).toLowerCase()));
    } catch (_) {}
  }

  List<Map<String, dynamic>> _filtrarLojas(String query) {
    if (query.isEmpty) return _lojasCache.take(20).toList();
    final q = query.toLowerCase();
    return _lojasCache.where((l) {
      return (l['nome'] as String).toLowerCase().contains(q) ||
          (l['cidade'] as String).toLowerCase().contains(q) ||
          (l['uid'] as String).toLowerCase().contains(q);
    }).take(20).toList();
  }

  @override
  void dispose() {
    _navCtrl?.removeListener(_onRotaMudou);
    _ctrlEstornoValor.dispose();
    _ctrlEstornoMotivo.dispose();
    super.dispose();
  }

  Future<void> _processarEstorno(BuildContext ctx) async {
    final lojaId = _lojaUidSelecionado ?? _ctrlLojaPesquisa.text.trim();
    final valor = double.tryParse(
      _ctrlEstornoValor.text.trim().replaceAll(',', '.'),
    );
    final motivo = _ctrlEstornoMotivo.text.trim();

    if (lojaId.isEmpty || valor == null || valor <= 0 || motivo.isEmpty) {
      ScaffoldMessenger.of(ctx).showSnackBar(
        const SnackBar(
          content: Text('Preencha todos os campos corretamente.'),
          backgroundColor: Color(0xFFDC2626),
        ),
      );
      return;
    }

    final pedidoId = _pedidoIdSelecionado ?? _ctrlPedidoPesquisa.text.trim();
    final nomeLoja = _lojasCache
        .where((l) => l['uid'] == lojaId)
        .map((l) => l['nome'] as String)
        .firstOrNull;
    final pedidoCache = _pedidoIdSelecionado != null
        ? _pedidosLojaCache.where((p) => p['id'] == _pedidoIdSelecionado).firstOrNull
        : null;
    final nomeCliente = (pedidoCache?['cliente'] as String?) ?? '';
    final formaPgto = (pedidoCache?['forma_pagamento'] as String?) ?? '';
    final valorPagamento = pedidoCache != null ? (pedidoCache['total_pedido'] as double?) ?? 0.0 : 0.0;
    final idCurto = pedidoId.isNotEmpty
        ? '#${pedidoId.substring(0, pedidoId.length.clamp(0, 5)).toUpperCase()}'
        : '';
    final parcial = _pedidoValorSelecionado != null && valor < _pedidoValorSelecionado!;

    final confirmar = await showDialog<bool>(
      context: ctx,
      builder: (c) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        titlePadding: EdgeInsets.zero,
        contentPadding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
        actionsPadding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
        title: Container(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
          decoration: const BoxDecoration(
            color: Color(0xFFFEF2F2),
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFDC2626).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.replay_rounded, color: Color(0xFFDC2626), size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Confirmar Estorno',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 16, fontWeight: FontWeight.w800, color: const Color(0xFF1E1B4B),
                      ),
                    ),
                    Text(
                      'Esta ação debitará o saldo da loja',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12, color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 16),
            if (nomeCliente.isNotEmpty)
              _linhaResumoEstorno(Icons.person_outline_rounded, 'Cliente', nomeCliente),
            if (nomeLoja != null)
              _linhaResumoEstorno(Icons.store_rounded, 'Loja', nomeLoja),
            if (idCurto.isNotEmpty)
              _linhaResumoEstorno(Icons.receipt_long_rounded, 'Pedido', idCurto),
            if (formaPgto.isNotEmpty)
              _linhaResumoEstorno(Icons.payment_rounded, 'Pagamento', formaPgto),
            if (valorPagamento > 0)
              _linhaResumoEstorno(Icons.monetization_on_outlined, 'Valor do pedido',
                  'R\$ ${valorPagamento.toStringAsFixed(2)}'),
            const Divider(height: 24),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFDC2626).withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.currency_exchange_rounded, color: Color(0xFFDC2626), size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          parcial ? 'Estorno parcial' : 'Valor do estorno',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 11, fontWeight: FontWeight.w600, color: const Color(0xFFDC2626),
                          ),
                        ),
                        Text(
                          'R\$ ${valor.toStringAsFixed(2)}',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 20, fontWeight: FontWeight.w800, color: const Color(0xFFDC2626),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (parcial)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF3C7),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'PARCIAL',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 10, fontWeight: FontWeight.w800, color: const Color(0xFFF59E0B),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _linhaResumoEstorno(Icons.edit_note_rounded, 'Motivo', motivo),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF3B82F6).withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.account_balance_rounded, color: Color(0xFF3B82F6), size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'O estorno será processado automaticamente via Mercado Pago e o valor devolvido à conta do cliente.',
                      style: GoogleFonts.plusJakartaSans(fontSize: 11, color: const Color(0xFF1E40AF)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text(
              'Cancelar',
              style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600, color: Colors.grey.shade600),
            ),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(c, true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
            icon: const Icon(Icons.replay_rounded, size: 16),
            label: Text(
              'Confirmar estorno',
              style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );

    if (confirmar != true) return;

    if (!ctx.mounted) return;
    _mostrarEstornoLoading(ctx);

    try {
      final resultado = await callFirebaseFunctionSafe(
        'processarEstornoPainel',
        parameters: {
          'lojaId': lojaId,
          'pedidoId': pedidoId,
          'valor': valor,
          'motivo': motivo,
        },
        timeout: const Duration(seconds: 30),
      );

      if (!ctx.mounted) return;
      Navigator.of(ctx).pop();

      setState(() {
        _ctrlLojaPesquisa.clear();
        _ctrlEstornoValor.clear();
        _ctrlEstornoMotivo.clear();
        _ctrlPedidoPesquisa.clear();
        _lojaUidSelecionado = null;
        _pedidoIdSelecionado = null;
        _pedidoValorSelecionado = null;
        _pedidosLojaCache = [];
      });

      if (ctx.mounted) {
        _mostrarEstornoSucesso(ctx, valor, idCurto, resultado);
      }
    } catch (e) {
      if (ctx.mounted) Navigator.of(ctx).pop();

      final mensagem = e is CallableHttpException
          ? e.message
          : e.toString().replaceAll('Exception: ', '');

      if (ctx.mounted) {
        _mostrarEstornoErro(ctx, mensagem);
      }
    }
  }

  void _mostrarEstornoLoading(BuildContext ctx) {
    showDialog(
      context: ctx,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 16),
              SizedBox(
                width: 56, height: 56,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  color: PainelAdminTheme.roxo,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Processando estorno...',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 16, fontWeight: FontWeight.w700, color: const Color(0xFF1E1B4B),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Comunicando com o Mercado Pago',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12, color: Colors.grey.shade500,
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  void _mostrarEstornoSucesso(
    BuildContext ctx,
    double valor,
    String idCurto,
    Map<String, dynamic> resultado,
  ) {
    final clienteNotificado = resultado['cliente_notificado'] == true;
    showDialog(
      context: ctx,
      builder: (c) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        titlePadding: EdgeInsets.zero,
        contentPadding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
        actionsPadding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
        title: Container(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
          decoration: const BoxDecoration(
            color: Color(0xFFF0FDF4),
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF16A34A).withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_rounded, color: Color(0xFF16A34A), size: 32),
              ),
              const SizedBox(height: 12),
              Text(
                'Estorno realizado!',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 18, fontWeight: FontWeight.w800, color: const Color(0xFF16A34A),
                ),
              ),
            ],
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF0FDF4),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF16A34A).withValues(alpha: 0.3)),
              ),
              child: Column(
                children: [
                  Text(
                    'R\$ ${valor.toStringAsFixed(2)}',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 24, fontWeight: FontWeight.w800, color: const Color(0xFF16A34A),
                    ),
                  ),
                  if (idCurto.isNotEmpty)
                    Text(
                      'Pedido $idCurto',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12, color: Colors.grey.shade600,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _linhaResumoEstorno(
              Icons.account_balance_rounded,
              'Mercado Pago',
              'Estorno processado com sucesso',
            ),
            _linhaResumoEstorno(
              Icons.notifications_active_rounded,
              'Notificação',
              clienteNotificado ? 'Cliente notificado' : 'Cliente sem token FCM',
            ),
            if (resultado['mp_refund_status'] != null)
              _linhaResumoEstorno(
                Icons.info_outline_rounded,
                'Status MP',
                '${resultado['mp_refund_status']}',
              ),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(c),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF16A34A),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            child: Text(
              'Fechar',
              style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  void _mostrarEstornoErro(BuildContext ctx, String mensagem) {
    showDialog(
      context: ctx,
      builder: (c) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        titlePadding: EdgeInsets.zero,
        contentPadding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
        actionsPadding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
        title: Container(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
          decoration: const BoxDecoration(
            color: Color(0xFFFEF2F2),
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFDC2626).withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close_rounded, color: Color(0xFFDC2626), size: 32),
              ),
              const SizedBox(height: 12),
              Text(
                'Erro no estorno',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 18, fontWeight: FontWeight.w800, color: const Color(0xFFDC2626),
                ),
              ),
            ],
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFDC2626).withValues(alpha: 0.3)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.error_outline_rounded, color: Color(0xFFDC2626), size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      mensagem,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFFDC2626),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(c),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            child: Text(
              'Fechar',
              style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEstornosSection() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('estornos')
          .orderBy('data_estorno', descending: true)
          .limit(200)
          .snapshots(),
      builder: (context, snap) {
        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty && _paginaEstornos != 0) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _paginaEstornos = 0);
          });
        }

        final total = docs.length;
        final totalPaginas = total == 0
            ? 0
            : (total + _kEstornosItensPorPagina - 1) ~/
                _kEstornosItensPorPagina;
        final maxPagina = totalPaginas > 0 ? totalPaginas - 1 : 0;
        final pagina = _paginaEstornos.clamp(0, maxPagina);
        if (pagina != _paginaEstornos) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _paginaEstornos = pagina);
          });
        }

        final inicio = total == 0 ? 0 : pagina * _kEstornosItensPorPagina;
        final fim = math.min(inicio + _kEstornosItensPorPagina, total);
        final docsPagina =
            total == 0 ? <QueryDocumentSnapshot<Map<String, dynamic>>>[] : docs.sublist(inicio, fim);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Cabeçalho da seção
            Container(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFDC2626).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.replay_rounded,
                      color: Color(0xFFDC2626),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Estornos',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF1E1B4B),
                          ),
                        ),
                        Text(
                          'Reembolsos processados ao cliente, debitados do saldo do lojista',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Formulário para novo estorno
            Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              elevation: 0,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFDC2626).withValues(alpha: 0.3)),
                ),
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.add_circle_outline_rounded,
                            color: Color(0xFFDC2626), size: 18),
                        const SizedBox(width: 8),
                        Text(
                          'Processar novo estorno',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF1E1B4B),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    LayoutBuilder(
                      builder: (ctx, c) {
                        final wide = c.maxWidth >= 700;
                        final buscaLoja = _buildBuscaLojaAutocomplete();
                        final campoPedido = _buildBuscaPedidoAutocomplete();
                        final campoValor = _campoEstorno(
                          controller: _ctrlEstornoValor,
                          label: 'Valor do estorno (R\$)',
                          icon: Icons.attach_money_rounded,
                        );
                        final campoMotivo = _campoEstorno(
                          controller: _ctrlEstornoMotivo,
                          label: 'Motivo',
                          icon: Icons.edit_note_rounded,
                        );
                        if (wide) {
                          return Column(
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(child: buscaLoja),
                                  const SizedBox(width: 12),
                                  Expanded(child: campoPedido),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(child: campoValor),
                                  const SizedBox(width: 12),
                                  Expanded(child: campoMotivo),
                                ],
                              ),
                            ],
                          );
                        }
                        return Column(
                          children: [
                            buscaLoja,
                            const SizedBox(height: 12),
                            campoPedido,
                            const SizedBox(height: 12),
                            campoValor,
                            const SizedBox(height: 12),
                            campoMotivo,
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF3C7),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.5)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.warning_amber_rounded,
                              color: Color(0xFFF59E0B), size: 16),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'O valor informado será debitado imediatamente do saldo disponível do lojista.',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 11,
                                color: const Color(0xFF92400E),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton.icon(
                        onPressed: () => _processarEstorno(context),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFDC2626),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 12,
                          ),
                        ),
                        icon: const Icon(Icons.replay_rounded, size: 16),
                        label: Text(
                          'Processar estorno',
                          style: GoogleFonts.plusJakartaSans(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Histórico de estornos
            if (docs.isNotEmpty) ...[
              const SizedBox(height: 20),
              Text(
                'Histórico de estornos',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF1E1B4B),
                ),
              ),
              const SizedBox(height: 12),
              ...docsPagina.map((doc) {
                final d = doc.data();
                final ts = d['data_estorno'];
                final dt = ts is Timestamp ? ts.toDate() : DateTime.now();
                final fmt = DateFormat('dd/MM/yyyy HH:mm');
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFDC2626).withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.replay_rounded,
                            color: Color(0xFFDC2626), size: 18),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              d['motivo']?.toString() ?? 'Estorno',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: const Color(0xFF1E1B4B),
                              ),
                            ),
                            Text(
                              'Loja: ${d['loja_id'] ?? '—'}'
                              '${(d['pedido_id'] ?? '').toString().isNotEmpty ? ' · Pedido: ${d['pedido_id']?.toString().substring(0, math.min(8, d['pedido_id'].toString().length))}' : ''}'
                              ' · ${fmt.format(dt)}',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 11,
                                color: Colors.grey.shade500,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        '- ${_brl.format(_num(d['valor']))}',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFFDC2626),
                        ),
                      ),
                    ],
                  ),
                );
              }),
              if (totalPaginas > 1)
                _buildPaginacaoLista(
                  paginaAtual: pagina,
                  totalPaginas: totalPaginas,
                  totalItens: total,
                  indiceInicioExibido: total == 0 ? 0 : inicio + 1,
                  indiceFimExibido: fim,
                  onAnterior: pagina > 0
                      ? () => setState(() => _paginaEstornos = pagina - 1)
                      : null,
                  onProxima: pagina < totalPaginas - 1
                      ? () => setState(() => _paginaEstornos = pagina + 1)
                      : null,
                ),
            ],
          ],
        );
      },
    );
  }

  Widget _buildBuscaLojaAutocomplete() {
    _carregarLojasSeNecessario();

    final campo = Autocomplete<Map<String, dynamic>>(
      displayStringForOption: (loja) => loja['nome'] as String,
      fieldViewBuilder: (context, controller, focusNode, onSubmit) {
        if (_lojaUidSelecionado != null && controller.text.isEmpty) {
          final sel = _lojasCache
              .where((l) => l['uid'] == _lojaUidSelecionado)
              .firstOrNull;
          if (sel != null) controller.text = sel['nome'] as String;
        }
        _ctrlLojaPesquisa = controller;
        return TextField(
          controller: controller,
          focusNode: focusNode,
          onSubmitted: (_) => onSubmit(),
          decoration: InputDecoration(
            labelText: 'Buscar loja por nome',
            hintText: 'Digite o nome da loja...',
            prefixIcon: const Icon(Icons.store_rounded, size: 18),
            suffixIcon: _lojaUidSelecionado != null
                ? IconButton(
                    icon: const Icon(Icons.close_rounded, size: 18),
                    onPressed: () {
                      controller.clear();
                      setState(() {
                        _lojaUidSelecionado = null;
                        _pedidosLojaCache = [];
                        _pedidoIdSelecionado = null;
                        _pedidoValorSelecionado = null;
                        _ctrlPedidoPesquisa.clear();
                        _ctrlEstornoValor.clear();
                      });
                    },
                  )
                : null,
            filled: true,
            fillColor: const Color(0xFFF8F7FC),
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(
                color: _lojaUidSelecionado != null
                    ? const Color(0xFF16A34A)
                    : Colors.grey.shade300,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFF7C3AED), width: 1.5),
            ),
            labelStyle: GoogleFonts.plusJakartaSans(fontSize: 13),
            hintStyle: GoogleFonts.plusJakartaSans(
                fontSize: 12.5, color: Colors.grey.shade400),
          ),
          style: GoogleFonts.plusJakartaSans(fontSize: 13),
        );
      },
      optionsBuilder: (textEditingValue) {
        if (!_lojasCacheCarregado) return [];
        return _filtrarLojas(textEditingValue.text);
      },
      optionsViewBuilder: (context, onSelected, options) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 6,
            borderRadius: BorderRadius.circular(12),
            clipBehavior: Clip.antiAlias,
            color: Colors.white,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 280, maxWidth: 420),
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 6),
                shrinkWrap: true,
                itemCount: options.length,
                separatorBuilder: (_, __) =>
                    const Divider(height: 1, indent: 14, endIndent: 14),
                itemBuilder: (context, index) {
                  final loja = options.elementAt(index);
                  final nome = loja['nome'] as String;
                  final cidade = loja['cidade'] as String;
                  final uid = loja['uid'] as String;
                  return InkWell(
                    onTap: () => onSelected(loja),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      child: Row(
                        children: [
                          Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              color: PainelAdminTheme.roxo.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(Icons.storefront_rounded,
                                size: 17, color: PainelAdminTheme.roxo),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  nome,
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: const Color(0xFF1E1B4B),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (cidade.isNotEmpty)
                                  Text(
                                    cidade,
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 11,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              uid.length > 8
                                  ? '${uid.substring(0, 8)}…'
                                  : uid,
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey.shade500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
      onSelected: (loja) {
        final uid = loja['uid'] as String;
        setState(() => _lojaUidSelecionado = uid);
        _carregarPedidosDaLoja(uid);
      },
    );

    if (_lojaUidSelecionado != null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          campo,
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Row(
              children: [
                const Icon(Icons.check_circle_rounded,
                    size: 13, color: Color(0xFF16A34A)),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    'UID: $_lojaUidSelecionado',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF16A34A),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return campo;
  }

  Widget _buildBuscaPedidoAutocomplete() {
    if (_lojaUidSelecionado == null) {
      return _campoEstorno(
        controller: _ctrlPedidoPesquisa,
        label: 'Selecione uma loja primeiro',
        icon: Icons.receipt_long_rounded,
        enabled: false,
      );
    }

    if (_pedidosLojaCarregando) {
      return Container(
        height: 48,
        decoration: BoxDecoration(
          color: const Color(0xFFF8F7FC),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Row(
          children: [
            const SizedBox(width: 12),
            const Icon(Icons.receipt_long_rounded, size: 18, color: Colors.grey),
            const SizedBox(width: 12),
            SizedBox(
              width: 16, height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: PainelAdminTheme.roxo,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'Carregando pedidos...',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13, color: Colors.grey.shade500,
              ),
            ),
          ],
        ),
      );
    }

    if (_pedidosLojaCache.isEmpty) {
      return _campoEstorno(
        controller: _ctrlPedidoPesquisa,
        label: 'Nenhum pedido encontrado',
        icon: Icons.receipt_long_rounded,
        enabled: false,
      );
    }

    String _labelStatus(String s) {
      switch (s) {
        case 'entregue': return 'Entregue';
        case 'pendente': return 'Pendente';
        case 'em_preparo': return 'Preparando';
        case 'cancelado': return 'Cancelado';
        case 'aguardando_pagamento': return 'Aguard. Pgto';
        case 'aguardando_entregador': return 'Aguard. Entregador';
        case 'saiu_para_entrega': return 'Em rota';
        default: return s.replaceAll('_', ' ');
      }
    }

    Color _corStatus(String s) {
      switch (s) {
        case 'entregue': return const Color(0xFF16A34A);
        case 'cancelado': return const Color(0xFFDC2626);
        case 'pendente': return const Color(0xFFF59E0B);
        case 'em_preparo': return const Color(0xFF2563EB);
        case 'saiu_para_entrega': return const Color(0xFF7C3AED);
        default: return Colors.grey;
      }
    }

    final campo = Autocomplete<Map<String, dynamic>>(
      displayStringForOption: (p) => '#${(p['id'] as String).substring(0, (p['id'] as String).length.clamp(0, 5)).toUpperCase()}',
      fieldViewBuilder: (context, controller, focusNode, onSubmit) {
        if (_pedidoIdSelecionado != null && controller.text.isEmpty) {
          final id = _pedidoIdSelecionado!;
          controller.text = '#${id.substring(0, id.length.clamp(0, 5)).toUpperCase()}';
        }
        _ctrlPedidoPesquisa = controller;
        return TextField(
          controller: controller,
          focusNode: focusNode,
          onSubmitted: (_) => onSubmit(),
          decoration: InputDecoration(
            labelText: 'Buscar pedido (${_pedidosLojaCache.length} pedidos)',
            hintText: 'Digite ID, nome do cliente ou status...',
            prefixIcon: const Icon(Icons.receipt_long_rounded, size: 18),
            suffixIcon: _pedidoIdSelecionado != null
                ? IconButton(
                    icon: const Icon(Icons.close_rounded, size: 18),
                    onPressed: () {
                      controller.clear();
                      setState(() {
                        _pedidoIdSelecionado = null;
                        _pedidoValorSelecionado = null;
                        _ctrlEstornoValor.clear();
                      });
                    },
                  )
                : null,
            filled: true,
            fillColor: const Color(0xFFF8F7FC),
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(
                color: _pedidoIdSelecionado != null
                    ? const Color(0xFF16A34A)
                    : Colors.grey.shade300,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFF7C3AED), width: 1.5),
            ),
            labelStyle: GoogleFonts.plusJakartaSans(fontSize: 13),
            hintStyle: GoogleFonts.plusJakartaSans(
                fontSize: 12.5, color: Colors.grey.shade400),
          ),
          style: GoogleFonts.plusJakartaSans(fontSize: 13),
        );
      },
      optionsBuilder: (textEditingValue) {
        return _filtrarPedidos(textEditingValue.text);
      },
      optionsViewBuilder: (context, onSelected, options) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 6,
            borderRadius: BorderRadius.circular(12),
            clipBehavior: Clip.antiAlias,
            color: Colors.white,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320, maxWidth: 480),
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 6),
                shrinkWrap: true,
                itemCount: options.length,
                separatorBuilder: (_, __) =>
                    const Divider(height: 1, indent: 14, endIndent: 14),
                itemBuilder: (context, index) {
                  final ped = options.elementAt(index);
                  final id = ped['id'] as String;
                  final status = ped['status'] as String;
                  final cliente = ped['cliente'] as String;
                  final total = ped['total'] as double;
                  final data = ped['data'] as DateTime?;
                  final dataFmt = data != null
                      ? DateFormat('dd/MM/yy HH:mm').format(data)
                      : '';
                  return InkWell(
                    onTap: () => onSelected(ped),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      child: Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: _corStatus(status).withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(Icons.receipt_long_rounded,
                                size: 17, color: _corStatus(status)),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      '#${id.substring(0, id.length.clamp(0, 5)).toUpperCase()}',
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: const Color(0xFF1E1B4B),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: _corStatus(status).withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        _labelStatus(status),
                                        style: GoogleFonts.plusJakartaSans(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                          color: _corStatus(status),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${cliente.isNotEmpty ? cliente : 'Cliente'} • $dataFmt',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 11,
                                    color: Colors.grey.shade600,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'R\$ ${total.toStringAsFixed(2)}',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF1E1B4B),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
      onSelected: (ped) {
        final total = ped['total'] as double;
        setState(() {
          _pedidoIdSelecionado = ped['id'] as String;
          _pedidoValorSelecionado = total;
          _ctrlEstornoValor.text = total.toStringAsFixed(2);
        });
      },
    );

    if (_pedidoIdSelecionado != null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          campo,
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Row(
              children: [
                const Icon(Icons.check_circle_rounded,
                    size: 13, color: Color(0xFF16A34A)),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    'Pedido: $_pedidoIdSelecionado • Valor: R\$ ${_pedidoValorSelecionado?.toStringAsFixed(2) ?? '0.00'}',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF16A34A),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return campo;
  }

  Widget _linhaResumoEstorno(IconData icon, String label, String valor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: Colors.grey.shade500),
          const SizedBox(width: 8),
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              valor,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12.5, fontWeight: FontWeight.w700, color: const Color(0xFF1E1B4B),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _campoEstorno({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool enabled = true,
  }) {
    return TextField(
      controller: controller,
      enabled: enabled,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 18),
        filled: true,
        fillColor: const Color(0xFFF8F7FC),
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFF7C3AED), width: 1.5),
        ),
        labelStyle: GoogleFonts.plusJakartaSans(fontSize: 13),
      ),
      style: GoogleFonts.plusJakartaSans(fontSize: 13),
    );
  }

}

class _KpiItem {
  _KpiItem(this.titulo, this.valor, this.accent, this.icon);
  final String titulo;
  final double valor;
  final Color accent;
  final IconData icon;
}
