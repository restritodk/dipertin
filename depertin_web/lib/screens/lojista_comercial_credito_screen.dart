import 'dart:async';

import 'package:depertin_web/models/comercial_cliente.dart';
import 'package:depertin_web/models/comercial_credito.dart';
import 'package:depertin_web/models/comercial_dashboard_data.dart';
import 'package:depertin_web/services/comercial_clientes_service.dart';
import 'package:depertin_web/services/comercial_credito_service.dart';
import 'package:depertin_web/theme/painel_admin_theme.dart';
import 'package:depertin_web/utils/lojista_painel_context.dart';
import 'package:depertin_web/widgets/comercial/comercial_conceder_credito_modal.dart';
import 'package:depertin_web/widgets/comercial/comercial_exportar_modal.dart';
import 'package:depertin_web/widgets/comercial/comercial_dashboard_acoes.dart';
import 'package:depertin_web/widgets/comercial_cliente_perfil_modal.dart';
import 'package:depertin_web/widgets/comercial_cliente_recebimento_modal.dart';
import 'package:depertin_web/widgets/dipertin_painel_feedback.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

/// Tela **Crédito de Clientes** — crediário SaaS premium (mockup DiPertin).
class LojistaComercialCreditoScreen extends StatefulWidget {
  const LojistaComercialCreditoScreen({super.key});

  @override
  State<LojistaComercialCreditoScreen> createState() =>
      _LojistaComercialCreditoScreenState();
}

class _LojistaComercialCreditoScreenState
    extends State<LojistaComercialCreditoScreen> {
  static const _fundo = Color(0xFFF5F7FA);
  static const _texto = Color(0xFF1E1B4B);
  static const _muted = Color(0xFF64748B);
  static const _borda = Color(0xFFE2E8F0);
  static const _verde = Color(0xFF16A34A);
  static const _vermelho = Color(0xFFDC2626);

  final _buscaCtrl = TextEditingController();
  final _moeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
  final _dataFmt = DateFormat('dd/MM/yyyy', 'pt_BR');

  int _abaCentral = 0;
  String _filtroStatus = 'Todos';
  String _filtroFaixa = 'Todas';
  String _ordenacao = 'Mais recentes';
  String _filtroParcelaStatus = 'Todos';
  int _pagina = 1;
  int _itensPorPagina = 5;

  Map<String, ClientePedidoResumo> _resumos = const {};
  List<ComercialParcelaCliente> _parcelas = const [];
  List<ComercialRecebimentoCliente> _recebimentos = const [];

  StreamSubscription<List<ComercialParcelaCliente>>? _subParcelas;
  StreamSubscription<List<ComercialRecebimentoCliente>>? _subReceb;
  String? _lojaIdAtiva;

  @override
  void dispose() {
    _buscaCtrl.dispose();
    _subParcelas?.cancel();
    _subReceb?.cancel();
    super.dispose();
  }

  void _ensureStreams(String lojaId) {
    if (lojaId.isEmpty || _lojaIdAtiva == lojaId) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _lojaIdAtiva != lojaId) _ligarStreams(lojaId);
    });
  }

  void _setStateSeguro(VoidCallback fn) {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(fn);
    });
  }

  void _ligarStreams(String lojaId) {
    if (_lojaIdAtiva == lojaId) return;
    _lojaIdAtiva = lojaId;
    _subParcelas?.cancel();
    _subReceb?.cancel();
    _subParcelas =
        ComercialCreditoService.streamParcelasLoja(lojaId).listen((lista) {
      _setStateSeguro(() => _parcelas = lista);
    });
    _subReceb =
        ComercialCreditoService.streamRecebimentosLoja(lojaId).listen((lista) {
      _setStateSeguro(() => _recebimentos = lista);
    });
    ComercialClientesService.carregarResumosPedidos(lojaId).then((r) {
      if (mounted && _lojaIdAtiva == lojaId) {
        _setStateSeguro(() => _resumos = r);
      }
    });
  }

  void _syncMenuComAba(int aba) {
    setState(() {
      _abaCentral = aba;
      _pagina = 1;
    });
  }

  /// Agrega limites, uso e inadimplência a partir de clientes + parcelas (tempo real).
  ComercialResumoCredito _calcularResumoCredito(
    List<ComercialCliente> comCredito,
    Map<String, double> atrasoPorCliente,
  ) {
    var limite = 0.0;
    var utilizado = 0.0;
    for (final c in comCredito) {
      limite += c.limiteCredito;
      utilizado += c.creditoUtilizado;
    }
    final valorAtraso =
        atrasoPorCliente.values.fold(0.0, (s, v) => s + v);
    final inadimplentes =
        atrasoPorCliente.values.where((v) => v > 0.009).length;

    return ComercialResumoCredito(
      limiteTotal: limite,
      creditoUtilizado: utilizado,
      creditoDisponivel: (limite - utilizado).clamp(0, double.infinity),
      clientesComCredito: comCredito.length,
      clientesInadimplentes: inadimplentes,
      valorEmAtraso: valorAtraso,
    );
  }

  Map<String, double> _atrasoPorCliente() {
    final hoje = DateTime.now();
    final hojeIni = DateTime(hoje.year, hoje.month, hoje.day);
    final map = <String, double>{};

    for (final p in _parcelas) {
      if (p.valorEmAberto <= 0.009) continue;
      final venc = DateTime(
        p.dataVencimento.year,
        p.dataVencimento.month,
        p.dataVencimento.day,
      );
      final vencida = p.status == ComercialParcelaStatus.vencido ||
          venc.isBefore(hojeIni);
      if (vencida) {
        map[p.clienteId] = (map[p.clienteId] ?? 0) + p.valorEmAberto;
      }
    }
    return map;
  }

  int _clientesAtraso30Dias(Map<String, double> atrasoMap) {
    final limite = DateTime.now().subtract(const Duration(days: 30));
    final limiteIni = DateTime(limite.year, limite.month, limite.day);
    final ids = <String>{};
    for (final p in _parcelas) {
      if (p.valorEmAberto <= 0.009) continue;
      final venc = DateTime(
        p.dataVencimento.year,
        p.dataVencimento.month,
        p.dataVencimento.day,
      );
      if (venc.isBefore(limiteIni)) ids.add(p.clienteId);
    }
    return ids.length;
  }

  double _recebimentosNoMes([DateTime? ref]) {
    final agora = ref ?? DateTime.now();
    final ini = DateTime(agora.year, agora.month, 1);
    final fim = DateTime(agora.year, agora.month + 1, 1);
    return _recebimentos
        .where((r) => !r.dataPagamento.isBefore(ini) && r.dataPagamento.isBefore(fim))
        .fold(0.0, (s, r) => s + r.valorPago);
  }

  int _novosClientesCreditoMes(List<ComercialCliente> comCredito) {
    final agora = DateTime.now();
    final ini = DateTime(agora.year, agora.month, 1);
    return comCredito.where((c) {
      final criado = c.createdAt;
      return criado != null && !criado.isBefore(ini);
    }).length;
  }

  ({DateTime? data, double valor}) _ultimaCompraCredito(String clienteId) {
    final doCliente =
        _parcelas.where((p) => p.clienteId == clienteId).toList();
    if (doCliente.isEmpty) return (data: null, valor: 0.0);

    final vendas = <String, ({DateTime? data, double total})>{};
    for (final p in doCliente) {
      final vId = p.vendaCreditoId.isNotEmpty ? p.vendaCreditoId : p.vendaId;
      if (vId.isEmpty) continue;
      final d = p.dataCompra ?? p.createdAt;
      final prev = vendas[vId];
      vendas[vId] = (
        data: d != null && (prev?.data == null || d.isAfter(prev!.data!))
            ? d
            : (prev?.data ?? d),
        total: (prev?.total ?? 0) + p.valorParcela,
      );
    }

    ({DateTime? data, double valor})? melhor;
    for (final v in vendas.values) {
      if (v.data == null) continue;
      if (melhor == null || v.data!.isAfter(melhor.data!)) {
        melhor = (data: v.data, valor: v.total);
      }
    }
    return melhor ?? (data: null, valor: 0.0);
  }

  List<ComercialCliente> _clientesComCredito(List<ComercialCliente> todos) {
    return todos
        .where(
          (c) =>
              c.creditoHabilitado ||
              c.limiteCredito > 0 ||
              c.creditoUtilizado > 0,
        )
        .toList();
  }

  List<ComercialCliente> _filtrarClientes(
    List<ComercialCliente> base, {
    Map<String, double>? atrasoPorCliente,
  }) {
    final atraso = atrasoPorCliente ?? const {};
    final q = _buscaCtrl.text.trim().toLowerCase();
    var lista = base.where((c) {
      if (q.isEmpty) return true;
      final cpf = (c.cpf ?? '').replaceAll(RegExp(r'\D'), '');
      return c.nome.toLowerCase().contains(q) ||
          (c.telefone ?? '').contains(q) ||
          cpf.contains(q.replaceAll(RegExp(r'\D'), ''));
    }).toList();

    if (_filtroStatus != 'Todos') {
      lista = lista.where((c) {
        switch (_filtroStatus) {
          case 'Ativo':
            return c.statusExibicao == 'ativo';
          case 'Com pendência':
            return (atraso[c.id] ?? 0) > 0 || c.temPendenciaAberta;
          case 'Bloqueado':
            return c.statusExibicao == 'bloqueado';
          default:
            return true;
        }
      }).toList();
    }

    if (_filtroFaixa != 'Todas') {
      lista = lista.where((c) {
        final lim = c.limiteCredito;
        switch (_filtroFaixa) {
          case 'Até R\$ 500':
            return lim <= 500;
          case 'R\$ 501 – R\$ 2.000':
            return lim > 500 && lim <= 2000;
          case 'Acima de R\$ 2.000':
            return lim > 2000;
          default:
            return true;
        }
      }).toList();
    }

    switch (_ordenacao) {
      case 'Nome A-Z':
        lista.sort((a, b) => a.nome.compareTo(b.nome));
        break;
      case 'Maior limite':
        lista.sort((a, b) => b.limiteCredito.compareTo(a.limiteCredito));
        break;
      case 'Maior utilizado':
        lista.sort((a, b) => b.creditoUtilizado.compareTo(a.creditoUtilizado));
        break;
      default:
        lista.sort((a, b) {
          final ta = a.createdAt ?? DateTime(1970);
          final tb = b.createdAt ?? DateTime(1970);
          return tb.compareTo(ta);
        });
    }
    return lista;
  }

  @override
  Widget build(BuildContext context) {
    return LojistaUidLojaBuilder(
      builder: (context, authUid, uidLoja, dadosUsuario) {
        _ensureStreams(uidLoja);
        final w = MediaQuery.sizeOf(context).width;
        final wide = w >= 1280;

        return Scaffold(
          backgroundColor: _fundo,
          body: SafeArea(
            child: StreamBuilder<List<ComercialCliente>>(
              stream: ComercialClientesService.streamClientes(uidLoja),
              builder: (context, snap) {
                final clientesRaw = snap.data ?? const [];
                final clientes = ComercialClientesService.aplicarResumosPedidos(
                  clientesRaw,
                  _resumos,
                );
                final comCredito = _clientesComCredito(clientes);
                final atrasoMap = _atrasoPorCliente();
                final resumo = _calcularResumoCredito(comCredito, atrasoMap);
                final pctUtilizado = resumo.limiteTotal > 0
                    ? (resumo.creditoUtilizado / resumo.limiteTotal * 100)
                    : 0.0;
                final pctDisponivel = resumo.limiteTotal > 0
                    ? (resumo.creditoDisponivel / resumo.limiteTotal * 100)
                    : 0.0;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _header(uidLoja),
                          const SizedBox(height: 20),
                          _kpisRow(
                            resumo: resumo,
                            pctUtilizado: pctUtilizado,
                            pctDisponivel: pctDisponivel,
                            wide: wide,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                        child: wide
                            ? Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Expanded(
                                    child: _painelCentral(
                                      uidLoja: uidLoja,
                                      clientes: clientes,
                                      comCredito: comCredito,
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  SizedBox(
                                    width: 300,
                                    child: SingleChildScrollView(
                                    child: _painelDireito(
                                      resumo: resumo,
                                      comCredito: comCredito,
                                      atrasoMap: atrasoMap,
                                    ),
                                    ),
                                  ),
                                ],
                              )
                            : SingleChildScrollView(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    SizedBox(
                                      height: 520,
                                      child: _painelCentral(
                                        uidLoja: uidLoja,
                                        clientes: clientes,
                                        comCredito: comCredito,
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    _painelDireito(
                                      resumo: resumo,
                                      comCredito: comCredito,
                                      atrasoMap: atrasoMap,
                                    ),
                                  ],
                                ),
                              ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  // ─── Header ───

  Widget _header(String lojaId) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Crédito de Clientes',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: _texto,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Gerencie o crédito dos seus clientes, limites, parcelas e recebimentos.',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: _muted,
                ),
              ),
            ],
          ),
        ),
        Wrap(
          spacing: 10,
          runSpacing: 8,
          alignment: WrapAlignment.end,
          children: [
            OutlinedButton.icon(
              onPressed: () => mostrarComercialExportarModal(context, lojaId: lojaId),
              icon: const Icon(Icons.download_rounded, size: 18),
              label: const Text('Relatório de crédito'),
              style: OutlinedButton.styleFrom(
                foregroundColor: PainelAdminTheme.roxo,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                side: BorderSide(
                  color: PainelAdminTheme.roxo.withValues(alpha: 0.35),
                ),
              ),
            ),
            FilledButton.icon(
              onPressed: () async {
                final ok = await mostrarComercialConcederCreditoModal(
                  context,
                  lojaId: lojaId,
                );
                if (ok && mounted) setState(() {});
              },
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Conceder crédito'),
              style: FilledButton.styleFrom(
                backgroundColor: PainelAdminTheme.laranja,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ─── KPIs ───

  Widget _kpisRow({
    required ComercialResumoCredito resumo,
    required double pctUtilizado,
    required double pctDisponivel,
    required bool wide,
  }) {
    final cards = [
      _kpiCard(
        icon: Icons.account_balance_wallet_outlined,
        titulo: 'Limite total concedido',
        valor: _moeda.format(resumo.limiteTotal),
        sub: resumo.limiteTotal > 0
            ? '${pctUtilizado.toStringAsFixed(1)}% já utilizado'
            : 'Nenhum limite concedido ainda',
        cor: PainelAdminTheme.roxo,
        corIcone: PainelAdminTheme.roxo.withValues(alpha: 0.12),
      ),
      _kpiCard(
        icon: Icons.people_outline_rounded,
        titulo: 'Crédito utilizado',
        valor: _moeda.format(resumo.creditoUtilizado),
        sub: '${pctUtilizado.toStringAsFixed(0)}% do limite total',
        cor: PainelAdminTheme.laranja,
        corIcone: PainelAdminTheme.laranja.withValues(alpha: 0.12),
      ),
      _kpiCard(
        icon: Icons.payments_outlined,
        titulo: 'Disponível',
        valor: _moeda.format(resumo.creditoDisponivel),
        sub: '${pctDisponivel.toStringAsFixed(0)}% do limite total',
        cor: _verde,
        corIcone: _verde.withValues(alpha: 0.12),
      ),
      _kpiCard(
        icon: Icons.warning_amber_rounded,
        titulo: 'Em atraso',
        valor: _moeda.format(resumo.valorEmAtraso),
        sub: '${resumo.clientesInadimplentes} clientes com pendências',
        cor: _vermelho,
        corIcone: _vermelho.withValues(alpha: 0.12),
      ),
      _kpiCard(
        icon: Icons.groups_outlined,
        titulo: 'Clientes com crédito',
        valor: '${resumo.clientesComCredito}',
        sub: 'Ativos no crediário',
        cor: PainelAdminTheme.roxo,
        corIcone: PainelAdminTheme.roxo.withValues(alpha: 0.12),
      ),
    ];

    if (wide) {
      return Row(
        children: [
          for (var i = 0; i < cards.length; i++) ...[
            if (i > 0) const SizedBox(width: 12),
            Expanded(child: cards[i]),
          ],
        ],
      );
    }

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: cards
          .map((c) => SizedBox(width: 220, child: c))
          .toList(),
    );
  }

  Widget _kpiCard({
    required IconData icon,
    required String titulo,
    required String valor,
    required String sub,
    required Color cor,
    required Color corIcone,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _borda),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: corIcone,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 20, color: cor),
          ),
          const SizedBox(height: 12),
          Text(
            titulo,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: _muted,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            valor,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: _texto,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            sub,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: cor == _vermelho ? _vermelho : _muted,
            ),
          ),
        ],
      ),
    );
  }

  // ─── Painel central ───

  Widget _painelCentral({
    required String uidLoja,
    required List<ComercialCliente> clientes,
    required List<ComercialCliente> comCredito,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _borda),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _abasCentrais(),
          const Divider(height: 1, color: _borda),
          if (_abaCentral <= 1) _barraFiltros(),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: _conteudoAba(
                uidLoja: uidLoja,
                clientes: clientes,
                comCredito: comCredito,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _abasCentrais() {
    const labels = [
      'Clientes com Crédito',
      'Parcelas',
      'Pendências',
      'Recebimentos',
      'Histórico de Créditos',
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            _abaItem(
              label: labels[i],
              ativo: _abaCentral == i,
              onTap: () => _syncMenuComAba(i),
            ),
        ],
      ),
    );
  }

  Widget _abaItem({
    required String label,
    required bool ativo,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: ativo ? PainelAdminTheme.roxo : Colors.transparent,
              width: 2.5,
            ),
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 13,
            fontWeight: ativo ? FontWeight.w700 : FontWeight.w500,
            color: ativo ? PainelAdminTheme.roxo : _muted,
          ),
        ),
      ),
    );
  }

  Widget _barraFiltros() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          TextField(
            controller: _buscaCtrl,
            onChanged: (_) => setState(() => _pagina = 1),
            decoration: InputDecoration(
              hintText: 'Buscar cliente por nome, telefone ou CPF…',
              hintStyle: GoogleFonts.plusJakartaSans(color: const Color(0xFF9CA3AF)),
              prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF9CA3AF)),
              filled: true,
              fillColor: _fundo,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: _borda),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: _borda),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: PainelAdminTheme.roxo, width: 2),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _filtroDrop('Status', _filtroStatus, const [
                'Todos',
                'Ativo',
                'Com pendência',
                'Bloqueado',
              ], (v) => setState(() {
                _filtroStatus = v!;
                _pagina = 1;
              })),
              _filtroDrop('Faixa de crédito', _filtroFaixa, const [
                'Todas',
                'Até R\$ 500',
                'R\$ 501 – R\$ 2.000',
                'Acima de R\$ 2.000',
              ], (v) => setState(() {
                _filtroFaixa = v!;
                _pagina = 1;
              })),
              _filtroDrop('Ordenar por', _ordenacao, const [
                'Mais recentes',
                'Nome A-Z',
                'Maior limite',
                'Maior utilizado',
              ], (v) => setState(() {
                _ordenacao = v!;
                _pagina = 1;
              })),
              TextButton.icon(
                onPressed: () {
                  setState(() {
                    _buscaCtrl.clear();
                    _filtroStatus = 'Todos';
                    _filtroFaixa = 'Todas';
                    _pagina = 1;
                  });
                },
                icon: Icon(Icons.filter_alt_off_outlined, size: 16, color: PainelAdminTheme.roxo),
                label: Text(
                  'Limpar filtros',
                  style: GoogleFonts.plusJakartaSans(
                    fontWeight: FontWeight.w700,
                    color: PainelAdminTheme.roxo,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _filtroDrop(
    String label,
    String valor,
    List<String> opcoes,
    ValueChanged<String?> onChanged,
  ) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$label:',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: _muted,
          ),
        ),
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: _fundo,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _borda),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: valor,
              isDense: true,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: _texto,
              ),
              items: opcoes
                  .map((o) => DropdownMenuItem(value: o, child: Text(o)))
                  .toList(),
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }

  Widget _conteudoAba({
    required String uidLoja,
    required List<ComercialCliente> clientes,
    required List<ComercialCliente> comCredito,
  }) {
    switch (_abaCentral) {
      case 1:
        return _abaParcelas(uidLoja, clientes);
      case 2:
        return _abaPendencias(uidLoja, clientes);
      case 3:
        return _abaRecebimentos(clientes);
      case 4:
        return _abaHistorico(clientes);
      default:
        return _abaClientesCredito(uidLoja, comCredito);
    }
  }

  // ─── Aba clientes ───

  Widget _abaClientesCredito(String lojaId, List<ComercialCliente> comCredito) {
    final atrasoMap = _atrasoPorCliente();
    final filtrados = _filtrarClientes(comCredito, atrasoPorCliente: atrasoMap);
    final total = filtrados.length;
    final inicio = ((_pagina - 1) * _itensPorPagina).clamp(0, total);
    final fim = (inicio + _itensPorPagina).clamp(0, total);
    final pagina = filtrados.sublist(inicio, fim);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SingleChildScrollView(
            child: _tabelaClientes(
              lojaId: lojaId,
              itens: pagina,
              atrasoMap: atrasoMap,
            ),
          ),
        ),
        _paginacao(total: total, inicio: inicio, fim: fim),
      ],
    );
  }

  Widget _tabelaClientes({
    required String lojaId,
    required List<ComercialCliente> itens,
    required Map<String, double> atrasoMap,
  }) {
    if (itens.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(32),
        child: Center(
          child: Text(
            'Nenhum cliente com crédito encontrado.',
            style: GoogleFonts.plusJakartaSans(color: _muted),
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: constraints.maxWidth),
            child: Table(
              columnWidths: const {
                0: FlexColumnWidth(2.4),
                1: FlexColumnWidth(1),
                2: FlexColumnWidth(0.9),
                3: FlexColumnWidth(1),
                4: FlexColumnWidth(0.9),
                5: FlexColumnWidth(1.1),
                6: FlexColumnWidth(1.1),
              },
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              children: [
                TableRow(
                  decoration: BoxDecoration(
                    color: _fundo,
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(8)),
                  ),
                  children: _ths(const [
                    'CLIENTE',
                    'LIMITE',
                    'USADO',
                    'DISPONÍVEL',
                    'EM ATRASO',
                    'ÚLTIMA COMPRA',
                    'AÇÕES',
                  ]),
                ),
                for (final c in itens)
                  TableRow(
                    decoration: const BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: _borda, width: 0.5),
                      ),
                    ),
                    children: [
                      _celCliente(c),
                      _td(_moeda.format(c.limiteCredito)),
                      _td(
                        _moeda.format(c.creditoUtilizado),
                        cor: PainelAdminTheme.laranja,
                      ),
                      _td(
                        _moeda.format(
                          c.creditoDisponivel.clamp(0, double.infinity),
                        ),
                        cor: _verde,
                      ),
                      _td(
                        _moeda.format(atrasoMap[c.id] ?? 0),
                        cor: (atrasoMap[c.id] ?? 0) > 0 ? _vermelho : _muted,
                      ),
                      _celUltimaCompra(c),
                      _celAcoes(lojaId, c),
                    ],
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  List<Widget> _ths(List<String> labels) => labels
      .map(
        (l) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Text(
            l,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
              color: _muted,
            ),
          ),
        ),
      )
      .toList();

  Widget _td(String v, {Color? cor}) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        child: Text(
          v,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: cor ?? _texto,
          ),
        ),
      );

  Widget _celCliente(ComercialCliente c) {
    final iniciais = _iniciais(c.nome);
    final tel = c.telefone ?? c.whatsapp ?? '';
    final cpf = ComercialClientesService.formatarCpfExibicao(c.cpf);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: PainelAdminTheme.roxo.withValues(alpha: 0.12),
            child: Text(
              iniciais,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: PainelAdminTheme.roxo,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  c.nome,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: _texto,
                  ),
                ),
                if (tel.isNotEmpty)
                  Text(
                    tel,
                    style: GoogleFonts.plusJakartaSans(fontSize: 11, color: _muted),
                  ),
                if (cpf.isNotEmpty)
                  Text(
                    'CPF: $cpf',
                    style: GoogleFonts.plusJakartaSans(fontSize: 11, color: _muted),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _celUltimaCompra(ComercialCliente c) {
    final cred = _ultimaCompraCredito(c.id);
    final data = cred.data ?? c.ultimaCompra;
    var valor = cred.valor;
    if (valor <= 0 && c.creditoUtilizado > 0) valor = c.creditoUtilizado;
    if (valor <= 0 && c.totalComprado > 0) valor = c.totalComprado;

    if (data == null && valor <= 0) {
      return _td('—', cor: _muted);
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            data != null ? _dataFmt.format(data) : '—',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: _texto,
            ),
          ),
          Text(
            _moeda.format(valor),
            style: GoogleFonts.plusJakartaSans(fontSize: 11, color: _muted),
          ),
        ],
      ),
    );
  }

  Widget _celAcoes(String lojaId, ComercialCliente c) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _acaoIcon(
            Icons.visibility_outlined,
            PainelAdminTheme.roxo,
            'Visualizar',
            () => _verCliente(lojaId, c),
          ),
          _acaoIcon(
            Icons.payments_outlined,
            _verde,
            'Receber',
            () => _receber(lojaId, c),
          ),
          _acaoIcon(
            Icons.add_circle_outline,
            PainelAdminTheme.laranja,
            'Crédito',
            () => _concederParaCliente(lojaId, c),
          ),
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert, color: _muted, size: 18),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            onSelected: (v) => _menuMaisOpcoes(lojaId, c, v),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'ver', child: Text('Visualizar cliente')),
              PopupMenuItem(value: 'receber', child: Text('Receber pagamento')),
              PopupMenuItem(value: 'credito', child: Text('Adicionar crédito')),
              PopupMenuItem(value: 'historico', child: Text('Histórico financeiro')),
              PopupMenuItem(value: 'parcelas', child: Text('Parcelas')),
              PopupMenuDivider(),
              PopupMenuItem(value: 'bloquear', child: Text('Bloquear crédito')),
              PopupMenuItem(value: 'remover', child: Text('Remover crédito')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _acaoIcon(
    IconData icon,
    Color cor,
    String tip,
    VoidCallback onTap,
  ) {
    return Tooltip(
      message: tip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 28,
          height: 28,
          margin: const EdgeInsets.symmetric(horizontal: 1),
          decoration: BoxDecoration(
            color: cor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 16, color: cor),
        ),
      ),
    );
  }

  // ─── Outras abas ───

  Widget _abaParcelas(String lojaId, List<ComercialCliente> clientes) {
    var lista = List<ComercialParcelaCliente>.from(_parcelas);
    if (_filtroParcelaStatus != 'Todos') {
      lista = lista.where((p) {
        switch (_filtroParcelaStatus) {
          case 'Em aberto':
            return p.status == ComercialParcelaStatus.emAberto;
          case 'Parcial':
            return p.status == ComercialParcelaStatus.parcialmentePago;
          case 'Pago':
            return p.status == ComercialParcelaStatus.pago;
          case 'Vencido':
            return p.status == ComercialParcelaStatus.vencido;
          default:
            return true;
        }
      }).toList();
    }

    final mapNome = {for (final c in clientes) c.id: c.nome};

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 8),
          child: Wrap(
            spacing: 8,
            children: [
              for (final s in ['Todos', 'Em aberto', 'Parcial', 'Pago', 'Vencido'])
                FilterChip(
                  label: Text(s),
                  selected: _filtroParcelaStatus == s,
                  onSelected: (_) => setState(() => _filtroParcelaStatus = s),
                  selectedColor: PainelAdminTheme.roxo.withValues(alpha: 0.12),
                  checkmarkColor: PainelAdminTheme.roxo,
                ),
            ],
          ),
        ),
        Expanded(
          child: lista.isEmpty
              ? Center(
                  child: Text(
                    'Nenhuma parcela encontrada.',
                    style: GoogleFonts.plusJakartaSans(color: _muted),
                  ),
                )
              : ListView.separated(
                  itemCount: lista.length,
                  separatorBuilder: (_, __) => const Divider(height: 1, color: _borda),
                  itemBuilder: (_, i) {
                    final p = lista[i];
                    final nome = mapNome[p.clienteId] ?? 'Cliente';
                    return ListTile(
                      title: Text(
                        '$nome · Parcela ${p.numeroParcela}',
                        style: GoogleFonts.plusJakartaSans(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                      subtitle: Text(
                        'Venc. ${_dataFmt.format(p.dataVencimento)} · ${p.codigoVenda}',
                        style: GoogleFonts.plusJakartaSans(fontSize: 12, color: _muted),
                      ),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            _moeda.format(p.valorEmAberto),
                            style: GoogleFonts.plusJakartaSans(
                              fontWeight: FontWeight.w700,
                              color: p.status == ComercialParcelaStatus.vencido
                                  ? _vermelho
                                  : _texto,
                            ),
                          ),
                          Text(
                            p.statusExibicao,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 11,
                              color: _muted,
                            ),
                          ),
                        ],
                      ),
                      onTap: () {
                        ComercialCliente? cli;
                        for (final c in clientes) {
                          if (c.id == p.clienteId) {
                            cli = c;
                            break;
                          }
                        }
                        if (cli != null) _receber(lojaId, cli);
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _abaPendencias(String lojaId, List<ComercialCliente> clientes) {
    final hoje = DateTime.now();
    final atrasadas = _parcelas.where((p) {
      if (p.valorEmAberto <= 0) return false;
      return p.status == ComercialParcelaStatus.vencido ||
          p.dataVencimento.isBefore(DateTime(hoje.year, hoje.month, hoje.day));
    }).toList()
      ..sort((a, b) => a.dataVencimento.compareTo(b.dataVencimento));

    final mapCli = {for (final c in clientes) c.id: c};

    return atrasadas.isEmpty
        ? Center(
            child: Text(
              'Nenhuma pendência em atraso.',
              style: GoogleFonts.plusJakartaSans(color: _muted),
            ),
          )
        : ListView.separated(
            padding: const EdgeInsets.only(top: 12),
            itemCount: atrasadas.length,
            separatorBuilder: (_, __) => const Divider(height: 1, color: _borda),
            itemBuilder: (_, i) {
              final p = atrasadas[i];
              final c = mapCli[p.clienteId];
              final dias = hoje.difference(p.dataVencimento).inDays;
              return ListTile(
                title: Text(
                  c?.nome ?? 'Cliente',
                  style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  '$dias dia(s) de atraso · Próx. venc. ${_dataFmt.format(p.dataVencimento)}',
                  style: GoogleFonts.plusJakartaSans(fontSize: 12, color: _vermelho),
                ),
                trailing: Text(
                  _moeda.format(p.valorEmAberto),
                  style: GoogleFonts.plusJakartaSans(
                    fontWeight: FontWeight.w800,
                    color: _vermelho,
                  ),
                ),
                onTap: c != null ? () => _receber(lojaId, c) : null,
              );
            },
          );
  }

  Widget _abaRecebimentos(List<ComercialCliente> clientes) {
    final mapNome = {for (final c in clientes) c.id: c.nome};
    if (_recebimentos.isEmpty) {
      return Center(
        child: Text(
          'Nenhum recebimento registrado.',
          style: GoogleFonts.plusJakartaSans(color: _muted),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.only(top: 12),
      itemCount: _recebimentos.length,
      separatorBuilder: (_, __) => const Divider(height: 1, color: _borda),
      itemBuilder: (_, i) {
        final r = _recebimentos[i];
        return ListTile(
          title: Text(
            mapNome[r.clienteId] ?? 'Cliente',
            style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
          ),
          subtitle: Text(
            '${_dataFmt.format(r.dataPagamento)} · ${r.formaPagamento}${r.usuarioNome != null ? ' · ${r.usuarioNome}' : ''}',
            style: GoogleFonts.plusJakartaSans(fontSize: 12, color: _muted),
          ),
          trailing: Text(
            _moeda.format(r.valorPago),
            style: GoogleFonts.plusJakartaSans(
              fontWeight: FontWeight.w800,
              color: _verde,
            ),
          ),
        );
      },
    );
  }

  Widget _abaHistorico(List<ComercialCliente> clientes) {
    final mapNome = {for (final c in clientes) c.id: c.nome};
    final linhas = <_LinhaHistorico>[];
    for (final r in _recebimentos) {
      linhas.add(
        _LinhaHistorico(
          data: r.dataPagamento,
          cliente: mapNome[r.clienteId] ?? 'Cliente',
          operacao: 'Recebimento parcela ${r.numeroParcela ?? ''}',
          valor: r.valorPago,
          usuario: r.usuarioNome ?? '—',
        ),
      );
    }
    linhas.sort((a, b) => b.data.compareTo(a.data));

    if (linhas.isEmpty) {
      return Center(
        child: Text(
          'Nenhum histórico de crédito ainda.',
          style: GoogleFonts.plusJakartaSans(color: _muted),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.only(top: 12),
      itemCount: linhas.length,
      separatorBuilder: (_, __) => const Divider(height: 1, color: _borda),
      itemBuilder: (_, i) {
        final h = linhas[i];
        return ListTile(
          title: Text(
            h.operacao,
            style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
          ),
          subtitle: Text(
            '${_dataFmt.format(h.data)} · ${h.cliente} · ${h.usuario}',
            style: GoogleFonts.plusJakartaSans(fontSize: 12, color: _muted),
          ),
          trailing: Text(
            _moeda.format(h.valor),
            style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
          ),
        );
      },
    );
  }

  Widget _paginacao({
    required int total,
    required int inicio,
    required int fim,
  }) {
    final paginas = (total / _itensPorPagina).ceil().clamp(1, 9999);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        children: [
          Text(
            total == 0
                ? 'Nenhum cliente'
                : 'Mostrando ${inicio + 1} a $fim de $total clientes',
            style: GoogleFonts.plusJakartaSans(fontSize: 12, color: _muted),
          ),
          const Spacer(),
          if (paginas > 1)
            Row(
              children: [
                for (var p = 1; p <= paginas && p <= 7; p++)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: InkWell(
                      onTap: () => setState(() => _pagina = p),
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        width: 28,
                        height: 28,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: _pagina == p
                              ? PainelAdminTheme.roxo
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '$p',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: _pagina == p ? Colors.white : _muted,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          const SizedBox(width: 12),
          Row(
            children: [
              Text(
                'Itens por página:',
                style: GoogleFonts.plusJakartaSans(fontSize: 12, color: _muted),
              ),
              const SizedBox(width: 6),
              DropdownButton<int>(
                value: _itensPorPagina,
                underline: const SizedBox.shrink(),
                isDense: true,
                items: const [5, 10, 25, 50]
                    .map((n) => DropdownMenuItem(value: n, child: Text('$n')))
                    .toList(),
                onChanged: (v) => setState(() {
                  _itensPorPagina = v ?? 5;
                  _pagina = 1;
                }),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─── Painel direito ───

  Widget _painelDireito({
    required ComercialResumoCredito resumo,
    required List<ComercialCliente> comCredito,
    required Map<String, double> atrasoMap,
  }) {
    final top = List<ComercialCliente>.from(comCredito)
      ..sort((a, b) {
        final cmp = b.creditoUtilizado.compareTo(a.creditoUtilizado);
        if (cmp != 0) return cmp;
        return b.totalComprado.compareTo(a.totalComprado);
      });

    final hoje = DateTime.now();
    final hojeIni = DateTime(hoje.year, hoje.month, hoje.day);
    final parcelasHoje = _parcelas.where((p) {
      if (p.valorEmAberto <= 0) return false;
      final v = DateTime(
        p.dataVencimento.year,
        p.dataVencimento.month,
        p.dataVencimento.day,
      );
      return v == hojeIni;
    }).length;

    final atraso30 = _clientesAtraso30Dias(atrasoMap);
    final recebMes = _recebimentosNoMes();
    final novosMes = _novosClientesCreditoMes(comCredito);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _cardLateral(
          titulo: 'Alertas importantes',
          icone: Icons.notifications_active_outlined,
          corTitulo: _vermelho,
          child: Column(
            children: [
              _alertaItem(
                Icons.schedule_rounded,
                '$parcelasHoje parcelas vencem hoje',
                _vermelho,
              ),
              _alertaItem(
                Icons.person_off_outlined,
                '$atraso30 clientes com atraso acima de 30 dias',
                _vermelho,
              ),
              _alertaItem(
                Icons.attach_money_rounded,
                '${_moeda.format(resumo.valorEmAtraso)} em pendências',
                PainelAdminTheme.roxo,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _cardLateral(
          titulo: 'Top clientes do crediário',
          icone: Icons.emoji_events_outlined,
          trailing: TextButton(
            onPressed: () {},
            child: Text(
              'Ver todos',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: PainelAdminTheme.roxo,
              ),
            ),
          ),
          child: Column(
            children: [
              for (var i = 0; i < top.length && i < 5; i++)
                _rankItem(
                  i + 1,
                  top[i].nome,
                  top[i].creditoUtilizado > 0
                      ? top[i].creditoUtilizado
                      : top[i].totalComprado,
                ),
              if (top.isEmpty)
                Text(
                  'Sem dados ainda.',
                  style: GoogleFonts.plusJakartaSans(fontSize: 12, color: _muted),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _cardLateral(
          titulo: 'Resumo do mês',
          icone: Icons.calendar_month_outlined,
          trailing: TextButton(
            onPressed: () => ComercialDashboardAcoes.exportarRelatorio(
              context,
              lojaId: _lojaIdAtiva ?? '',
            ),
            child: Text(
              'Ver relatório',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: PainelAdminTheme.roxo,
              ),
            ),
          ),
          child: Column(
            children: [
              _resumoLinha('Crédito concedido', _moeda.format(resumo.limiteTotal)),
              _resumoLinha('Recebimentos', _moeda.format(recebMes)),
              _resumoLinha('Inadimplência', _moeda.format(resumo.valorEmAtraso)),
              _resumoLinha('Novos clientes no crédito', '$novosMes'),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  DateFormat('MMMM/yyyy', 'pt_BR').format(DateTime.now()),
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    color: _muted,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _cardLateral({
    required String titulo,
    required IconData icone,
    required Widget child,
    Color? corTitulo,
    Widget? trailing,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _borda),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icone, size: 18, color: corTitulo ?? PainelAdminTheme.roxo),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  titulo,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: _texto,
                  ),
                ),
              ),
              if (trailing != null) trailing,
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _alertaItem(IconData icon, String texto, Color cor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: cor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              texto,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: _texto,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _rankItem(int pos, String nome, double valor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: PainelAdminTheme.roxo.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Text(
              '$pos',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: PainelAdminTheme.roxo,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              nome,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Text(
            _moeda.format(valor),
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: PainelAdminTheme.laranja,
            ),
          ),
        ],
      ),
    );
  }

  Widget _resumoLinha(String label, String valor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: GoogleFonts.plusJakartaSans(fontSize: 12, color: _muted),
            ),
          ),
          Text(
            valor,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: _texto,
            ),
          ),
        ],
      ),
    );
  }

  // ─── Ações ───

  void _verCliente(String lojaId, ComercialCliente c) {
    mostrarComercialClientePerfilModal(
      context,
      lojaId: lojaId,
      cliente: c,
      onEditar: () {},
      onNovaVenda: () {},
      onAdicionarCredito: () => _concederParaCliente(lojaId, c),
      onRegistrarRecebimento: () => _receber(lojaId, c),
    );
  }

  void _receber(String lojaId, ComercialCliente c) {
    mostrarComercialClienteRecebimentoModal(
      context,
      lojaId: lojaId,
      cliente: c,
    );
  }

  Future<void> _concederParaCliente(String lojaId, ComercialCliente c) async {
    final ok = await mostrarComercialConcederCreditoModal(
      context,
      lojaId: lojaId,
      clienteInicial: c,
    );
    if (ok && mounted) _setStateSeguro(() {});
  }

  Future<void> _menuMaisOpcoes(
    String lojaId,
    ComercialCliente c,
    String acao,
  ) async {
    switch (acao) {
      case 'ver':
        _verCliente(lojaId, c);
        break;
      case 'receber':
        _receber(lojaId, c);
        break;
      case 'credito':
        await _concederParaCliente(lojaId, c);
        break;
      case 'historico':
        ComercialDashboardAcoes.historicoVendas(context, lojaId: lojaId);
        break;
      case 'parcelas':
        _syncMenuComAba(1);
        break;
      case 'bloquear':
        await ComercialClientesService.bloquear(lojaId, c.id, bloquear: true);
        if (mounted) {
          DiPertinPainelFeedback.sucesso(context, 'Crédito bloqueado para ${c.nome}.');
        }
        break;
      case 'remover':
        await ComercialClientesService.salvar(
          lojaId: lojaId,
          cliente: c.copyWith(
            creditoHabilitado: false,
            limiteCredito: 0,
          ),
        );
        if (mounted) {
          DiPertinPainelFeedback.sucesso(context, 'Crédito removido de ${c.nome}.');
        }
        break;
    }
  }

  String _iniciais(String nome) {
    final p = nome.trim().split(' ');
    if (p.length >= 2) {
      return (p[0].substring(0, 1) + p[1].substring(0, 1)).toUpperCase();
    }
    if (nome.length >= 2) return nome.substring(0, 2).toUpperCase();
    return nome.isNotEmpty ? nome[0].toUpperCase() : '?';
  }
}

class _LinhaHistorico {
  const _LinhaHistorico({
    required this.data,
    required this.cliente,
    required this.operacao,
    required this.valor,
    required this.usuario,
  });

  final DateTime data;
  final String cliente;
  final String operacao;
  final double valor;
  final String usuario;
}
