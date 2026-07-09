import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../models/modulo_config_model.dart';
import '../models/plano_assinatura_model.dart';
import '../services/modulos_config_service.dart';
import '../services/modulos_planos_service.dart';
import '../services/firebase_functions_config.dart';
import '../theme/painel_admin_theme.dart';

// ============================================================
// Cores específicas do módulo (mantendo consistência com tema)
// ============================================================
const Color _textoPrimario = Color(0xFF17152A);
const Color _textoSecundario = Color(0xFF6E7894);
const Color _textoDescricao = Color(0xFF65708C);
const Color _fundoPagina = Color(0xFFF8F8FC);
const Color _bordaHeader = Color(0xFFECECF3);
const Color _bordaCard = Color(0xFFEEEAF6);
const Color _bordaInput = Color(0xFFE9E8F0);
const Color _roxoBtn = Color(0xFF7D20E8);
const Color _roxoCard = Color(0xFF6E22D9);
const Color _lilasFundo = Color(0xFFF1E9FF);
const Color _verdeStatus = Color(0xFF16A34A);
const Color _verdeFundo = Color(0xFFE8F5E9);

/// Gradiente horizontal roxo → rosa → laranja (botão principal)
final LinearGradient _gradienteBtn = LinearGradient(
  colors: [
    const Color(0xFF7D20E8),
    const Color(0xFFD62BDB),
    const Color(0xFFFF7A17),
  ],
  begin: Alignment.centerLeft,
  end: Alignment.centerRight,
);

/// Gradiente faixa superior do card
final LinearGradient _gradienteFaixa = LinearGradient(
  colors: [
    const Color(0xFF8627EF),
    const Color(0xFFDF2CD7),
    const Color(0xFFFF7B17),
  ],
  begin: Alignment.centerLeft,
  end: Alignment.centerRight,
);

// ============================================================
// TELA PRINCIPAL
// ============================================================
class AssinaturasPlanosScreen extends StatefulWidget {
  const AssinaturasPlanosScreen({super.key});

  @override
  State<AssinaturasPlanosScreen> createState() =>
      _AssinaturasPlanosScreenState();
}

class _AssinaturasPlanosScreenState extends State<AssinaturasPlanosScreen> {

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _fundoPagina,
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: ModulosPlanosService.stream(),
        builder: (context, snapshot) {
          final planos =
              snapshot.data?.docs
                  .map((d) => PlanoAssinaturaModel.fromFirestore(d))
                  .toList() ??
              [];

          final planosAtivos = planos.where((p) => p.ativo).length;
          final totalAssinaturas = planos.fold<int>(
            0,
            (s, p) => s + p.assinaturasAtivas,
          );
          final receitaMensal = planos
              .where((p) => p.ativo)
              .fold<double>(0, (s, p) => s + p.valor);
          final emAtraso = planos
              .where((p) => p.ativo)
              .fold<int>(0, (s, p) => s + (p.toleranciaDias > 0 ? 1 : 0));

          return Column(
            children: [
              _buildHeader(),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                      child: SizedBox(
                        width: constraints.maxWidth,
                        child: _buildConteudo(
                          planos: planos,
                          planosAtivos: planosAtivos,
                          totalAssinaturas: totalAssinaturas,
                          receitaMensal: receitaMensal,
                          emAtraso: emAtraso,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // ============================================================
  // HEADER
  // ============================================================
  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Linha superior: título à esquerda, perfil à direita
          Row(
            children: [
              // Título com ícone
              Expanded(
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: _lilasFundo,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      alignment: Alignment.center,
                      child: const Icon(
                        Icons.grid_view_rounded,
                        color: _roxoCard,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Flexible(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Planos e Módulos',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              color: _textoPrimario,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Cadastre os planos comerciais, defina regras de cobrança e controle a disponibilidade dos módulos DiPertin.',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 13,
                              color: _textoSecundario,
                            ),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 2,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              // Perfil + ícones
              Row(
                children: [
                  // Ajuda
                  _IconeCircular(Icons.help_outline_rounded),
                  const SizedBox(width: 8),
                  // Sino com badge
                  _SinoComBadge('3'),
                  const SizedBox(width: 12),
                  // Avatar
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFFF8F00), Color(0xFFE91E63)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      'M',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Master',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: _textoPrimario,
                        ),
                      ),
                      Text(
                        'Administrador',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 11,
                          color: _textoSecundario,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 4),
                  const Icon(
                    Icons.arrow_drop_down_rounded,
                    color: _textoSecundario,
                    size: 20,
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Linha inferior: botões
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              // Recalcular contadores
              _BotaoRecalcularContadores(
                onTap: _recalcularContadores,
              ),
              // Grupo direito
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Configurações de cobrança
                  OutlinedButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.settings_rounded, size: 16),
                    label: Text(
                      'Configurações de cobrança',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: _roxoCard,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFFD4C8F0)),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      backgroundColor: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 10),
                  // Novo plano
                  _BotaoGradiente(
                    onTap: _abrirModalCriarPlano,
                    icone: Icons.add_rounded,
                    label: 'Novo plano',
                    altura: 38,
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Borda inferior
          Container(height: 1, color: _bordaHeader),
        ],
      ),
    );
  }

  // ============================================================
  // CONTEÚDO PRINCIPAL (com scroll)
  // ============================================================
  Widget _buildConteudo({
    required List<PlanoAssinaturaModel> planos,
    required int planosAtivos,
    required int totalAssinaturas,
    required double receitaMensal,
    required int emAtraso,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // --- CARDS DE RESUMO ---
        _buildSummaryCards(
          planosAtivos: planosAtivos,
          totalAssinaturas: totalAssinaturas,
          receitaMensal: receitaMensal,
          emAtraso: emAtraso,
          totalPlanos: planos.length,
        ),

        const SizedBox(height: 20),

        // --- BARRA DE BUSCA E FILTROS ---
        _buildFilters(),

        const SizedBox(height: 20),

        // --- GRID DE CARDS ---
        _buildPlanGrid(planos),
      ],
    );
  }

  // ============================================================
  // 4. CARDS DE RESUMO
  // ============================================================
  Widget _buildSummaryCards({
    required int planosAtivos,
    required int totalAssinaturas,
    required double receitaMensal,
    required int emAtraso,
    required int totalPlanos,
  }) {
    final receitaFormatada = NumberFormat.currency(
      locale: 'pt_BR',
      symbol: 'R\$',
    ).format(receitaMensal);

    return LayoutBuilder(
      builder: (context, constraints) {
        final largura = constraints.maxWidth;
        int cols;
        if (largura > 1100) {
          cols = 4;
        } else if (largura > 700) {
          cols = 2;
        } else {
          cols = 1;
        }
        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            SizedBox(
              width: (largura - 16 * (cols - 1)) / cols,
              child: _SummaryMetricCard(
                icone: Icons.shopping_bag_outlined,
                cor: _roxoCard,
                titulo: 'Planos ativos',
                valor: '$planosAtivos',
                variacao: '$totalPlanos total',
                variacaoCor: _verdeStatus,
              ),
            ),
            SizedBox(
              width: (largura - 16 * (cols - 1)) / cols,
              child: _SummaryMetricCard(
                icone: Icons.people_alt_outlined,
                cor: _roxoCard,
                titulo: 'Assinaturas ativas',
                valor: NumberFormat('#,##0', 'pt_BR').format(totalAssinaturas),
                variacao: '$totalAssinaturas total',
                variacaoCor: _verdeStatus,
              ),
            ),
            SizedBox(
              width: (largura - 16 * (cols - 1)) / cols,
              child: _SummaryMetricCard(
                icone: Icons.attach_money_rounded,
                cor: _roxoCard,
                titulo: 'Receita mensal estimada',
                valor: receitaFormatada,
                variacao: 'Receita total dos planos ativos',
                variacaoCor: _verdeStatus,
              ),
            ),
            SizedBox(
              width: (largura - 16 * (cols - 1)) / cols,
              child: _SummaryMetricCard(
                icone: Icons.warning_amber_rounded,
                cor: PainelAdminTheme.laranja,
                titulo: 'Em atraso',
                valor: '$emAtraso cliente${emAtraso == 1 ? '' : 's'}',
                variacao: 'Planos com tolerância ativa',
                variacaoCor: const Color(0xFFDC2626),
              ),
            ),
          ],
        );
      },
    );
  }

  // ============================================================
  // 5. BARRA DE BUSCA E FILTROS
  // ============================================================
  Widget _buildFilters() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final larga = constraints.maxWidth > 900;
        if (larga) {
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                // Busca
                SizedBox(
                  width: 340,
                  height: 46,
                  child: TextField(
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      color: _textoPrimario,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Buscar plano por nome...',
                      hintStyle: GoogleFonts.plusJakartaSans(
                        fontSize: 14,
                        color: _textoSecundario,
                      ),
                      prefixIcon: const Icon(
                        Icons.search_rounded,
                        color: _textoSecundario,
                        size: 20,
                      ),
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(
                        vertical: 12,
                        horizontal: 14,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: _bordaInput),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: _bordaInput),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(
                          color: _roxoCard,
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                _FiltroDropdown(label: 'Status', valor: 'Todos', largura: 196),
                const SizedBox(width: 16),
                _FiltroDropdown(label: 'Duração', valor: 'Todos', largura: 196),
                const SizedBox(width: 16),
                _FiltroDropdown(
                  label: 'Ordenar por',
                  valor: 'Mais recentes',
                  largura: 196,
                ),
                const SizedBox(width: 16),
                OutlinedButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.filter_alt_outlined, size: 16),
                  label: Text(
                    'Limpar filtros',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: _roxoCard,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFFD4C8F0)),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    minimumSize: const Size(0, 40),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    backgroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          );
        } else {
          // Versão empilhada para telas menores
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: double.infinity,
                height: 46,
                child: TextField(
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    color: _textoPrimario,
                  ),
                  decoration: _inputBusca(),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _FiltroDropdownCompact(label: 'Status', valor: 'Todos'),
                  _FiltroDropdownCompact(label: 'Duração', valor: 'Todos'),
                  _FiltroDropdownCompact(
                    label: 'Ordenar por',
                    valor: 'Mais recentes',
                  ),
                  OutlinedButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.filter_alt_outlined, size: 16),
                    label: Text(
                      'Limpar filtros',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: _roxoCard,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFFD4C8F0)),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      minimumSize: const Size(0, 40),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      backgroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            ],
          );
        }
      },
    );
  }

  InputDecoration _inputBusca() {
    return InputDecoration(
      hintText: 'Buscar plano por nome...',
      hintStyle: GoogleFonts.plusJakartaSans(
        fontSize: 14,
        color: _textoSecundario,
      ),
      prefixIcon: const Icon(
        Icons.search_rounded,
        color: _textoSecundario,
        size: 20,
      ),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: _bordaInput),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: _bordaInput),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: _roxoCard, width: 1.5),
      ),
    );
  }

  // ============================================================
  // 6. GRID DE CARDS DE PLANOS + 8. CARD CRIAR NOVO PLANO
  // ============================================================
  Widget _buildPlanGrid(List<PlanoAssinaturaModel> planos) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final largura = constraints.maxWidth;
        int cols;
        if (largura > 1100) {
          cols = 3;
        } else if (largura > 720) {
          cols = 2;
        } else {
          cols = 1;
        }
        final cardWidth = (largura - 16 * (cols - 1)) / cols;
        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            // Cards de planos
            for (final plano in planos)
              SizedBox(
                width: cardWidth,
                child: _PlanCard(
                  plano: plano,
                  onEditar: () => _abrirModalEditarPlano(plano),
                  onToggleAtivo: () => _confirmarTogglePlano(plano),
                  onDeletar: () => _confirmarExcluirPlano(plano),
                ),
              ),
            // Card "Criar novo plano"
            SizedBox(
              width: cardWidth,
              child: _CriarNovoPlanoCard(onTap: _abrirModalCriarPlano),
            ),
          ],
        );
      },
    );
  }

  // ============================================================
  // MODAIS
  // ============================================================
  @override
  void didUpdateWidget(AssinaturasPlanosScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Abre modais no pós-build
  }

  void _abrirModalCriarPlano() {
    showDialog(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (_) => const _CreatePlanDialog(),
    );
  }

  void _abrirModalEditarPlano(PlanoAssinaturaModel plano) {
    showDialog(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (_) => _EditPlanDialog(plano: plano),
    );
  }

  Future<void> _confirmarTogglePlano(PlanoAssinaturaModel plano) async {
    final confirmado = await _confirmarAcao(
      context: context,
      icone: plano.ativo ? Icons.block_flipped : Icons.check_circle_outline,
      corIcone: plano.ativo ? const Color(0xFFD97706) : const Color(0xFF16A34A),
      titulo: plano.ativo ? 'Bloquear plano?' : 'Ativar plano?',
      mensagem: plano.ativo
          ? 'O plano "${plano.nome}" será desativado. Clientes ativos continuarão até o fim do período contratado, mas não será possível novas contratações.'
          : 'O plano "${plano.nome}" será reativado e ficará disponível para novas contratações.',
      textoConfirmar: plano.ativo ? 'Sim, bloquear' : 'Sim, ativar',
    );
    if (!confirmado || !mounted) return;
    try {
      await ModulosPlanosService.toggleStatus(plano.id, !plano.ativo);
      if (mounted) {
        _sucessoDialog(
          context: context,
          titulo: plano.ativo ? 'Plano bloqueado' : 'Plano ativado',
          subtitulo:
              'O plano "${plano.nome}" foi ${plano.ativo ? 'bloqueado' : 'ativado'} com sucesso.',
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _confirmarExcluirPlano(PlanoAssinaturaModel plano) async {
    final confirmado = await _confirmarAcao(
      context: context,
      icone: Icons.delete_outline_rounded,
      corIcone: const Color(0xFFDC2626),
      titulo: 'Deletar plano?',
      mensagem:
          'O plano "${plano.nome}" será permanentemente removido. '
          'Esta ação não pode ser desfeita.',
      textoConfirmar: 'Sim, deletar',
    );
    if (!confirmado || !mounted) return;
    try {
      await ModulosPlanosService.excluir(plano.id);
      if (mounted) {
        _sucessoDialog(
          context: context,
          titulo: 'Plano deletado',
          subtitulo: 'O plano "${plano.nome}" foi removido permanentemente.',
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  bool _recalculando = false;

  Future<void> _recalcularContadores() async {
    if (_recalculando) return;
    setState(() => _recalculando = true);
    try {
      final result = await callFirebaseFunctionSafe(
        'adminRecalcularContadoresAssinaturas',
        parameters: {},
        timeout: const Duration(seconds: 120),
      );
      if (mounted) {
        final processados = result['planosProcessados'] ?? result['planos'] ?? 0;
        _sucessoDialog(
          context: context,
          titulo: 'Contadores recalculados',
          subtitulo: '$processados plano(s) atualizado(s).',
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao recalcular contadores: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _recalculando = false);
    }
  }
}

// ============================================================
// COMPONENTES REUTILIZÁVEIS
// ============================================================

// --- ICONE CIRCULAR ---
class _IconeCircular extends StatelessWidget {
  final IconData icone;
  const _IconeCircular(this.icone);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: _fundoPagina,
        borderRadius: BorderRadius.circular(16),
      ),
      alignment: Alignment.center,
      child: Icon(icone, size: 18, color: _textoSecundario),
    );
  }
}

// --- SINO COM BADGE ---
class _SinoComBadge extends StatelessWidget {
  final String badge;
  const _SinoComBadge(this.badge);

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const _IconeCircular(Icons.notifications_outlined),
        Positioned(
          top: 2,
          right: 2,
          child: Container(
            width: 16,
            height: 16,
            decoration: const BoxDecoration(
              color: _roxoCard,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              badge,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// --- BOTÃO RECALCULAR CONTADORES ---
class _BotaoRecalcularContadores extends StatelessWidget {
  final VoidCallback onTap;
  const _BotaoRecalcularContadores({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: const Icon(Icons.refresh_rounded, size: 16),
      label: Text(
        'Recalcular contadores',
        style: GoogleFonts.plusJakartaSans(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: PainelAdminTheme.roxo,
        ),
      ),
      style: OutlinedButton.styleFrom(
        side: const BorderSide(color: Color(0xFFD4C8F0)),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        backgroundColor: Colors.white,
      ),
    );
  }
}

// --- BOTÃO GRADIENTE ---
class _BotaoGradiente extends StatelessWidget {
  final VoidCallback onTap;
  final IconData icone;
  final String label;
  final double? altura;
  const _BotaoGradiente({
    required this.onTap,
    required this.icone,
    required this.label,
    this.altura,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          height: altura ?? 38,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            gradient: _gradienteBtn,
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: _roxoBtn.withValues(alpha: 0.3),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icone, size: 18, color: Colors.white),
              const SizedBox(width: 6),
              Text(
                label,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// --- SUMMARY METRIC CARD ---
class _SummaryMetricCard extends StatelessWidget {
  final IconData icone;
  final Color cor;
  final String titulo;
  final String valor;
  final String variacao;
  final Color variacaoCor;

  const _SummaryMetricCard({
    required this.icone,
    required this.cor,
    required this.titulo,
    required this.valor,
    required this.variacao,
    required this.variacaoCor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 114,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFF0EFF5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: cor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: Icon(icone, color: cor, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  titulo,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    color: _textoSecundario,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  valor,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: _textoPrimario,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  variacao,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: variacaoCor,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// --- FILTRO DROPDOWN ---
class _FiltroDropdown extends StatelessWidget {
  final String label;
  final String valor;
  final double largura;
  const _FiltroDropdown({
    required this.label,
    required this.valor,
    required this.largura,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: largura,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: _textoSecundario,
            ),
          ),
          const SizedBox(height: 4),
          Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _bordaInput),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    valor,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      color: _textoPrimario,
                    ),
                  ),
                ),
                const Icon(
                  Icons.arrow_drop_down_rounded,
                  color: _textoSecundario,
                  size: 20,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// --- FILTRO DROPDOWN COMPACT (MOBILE) ---
class _FiltroDropdownCompact extends StatelessWidget {
  final String label;
  final String valor;
  const _FiltroDropdownCompact({required this.label, required this.valor});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 160,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: _textoSecundario,
            ),
          ),
          const SizedBox(height: 4),
          Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _bordaInput),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    valor,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      color: _textoPrimario,
                    ),
                  ),
                ),
                const Icon(
                  Icons.arrow_drop_down_rounded,
                  color: _textoSecundario,
                  size: 20,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// --- PLAN STATUS BADGE ---
class _PlanStatusBadge extends StatelessWidget {
  final bool ativo;
  const _PlanStatusBadge({required this.ativo});

  @override
  Widget build(BuildContext context) {
    final bg = ativo ? _verdeFundo : const Color(0xFFF0EDF5);
    final cor = ativo ? _verdeStatus : const Color(0xFF6E7894);
    final texto = ativo ? 'Ativo' : 'Inativo';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: cor, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(
            texto,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: cor,
            ),
          ),
        ],
      ),
    );
  }
}

// --- MODULE CHIP ---
class _ModuleChip extends StatelessWidget {
  final String label;
  const _ModuleChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: _lilasFundo,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: GoogleFonts.plusJakartaSans(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: _roxoCard,
        ),
      ),
    );
  }
}

// --- PLAN CARD ---
class _PlanCard extends StatelessWidget {
  final PlanoAssinaturaModel plano;
  final VoidCallback onEditar;
  final VoidCallback onToggleAtivo;
  final VoidCallback onDeletar;

  const _PlanCard({
    required this.plano,
    required this.onEditar,
    required this.onToggleAtivo,
    required this.onDeletar,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 420,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _bordaCard),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Faixa gradiente
          Container(
            height: 4,
            decoration: BoxDecoration(gradient: _gradienteFaixa),
          ),
          // Conteúdo
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Linha título + badge
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          plano.nome,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: _textoPrimario,
                          ),
                        ),
                      ),
                      _PlanStatusBadge(ativo: plano.ativo),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Descrição (max 2 linhas)
                  Text(
                    plano.descricao ?? '',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      color: _textoDescricao,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Valor
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'R\$ ${plano.valor.toStringAsFixed(2).replaceAll('.', ',')}',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: _roxoCard,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 3),
                        child: Text(
                          '/ mês',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 13,
                            color: _textoSecundario,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Divider(color: Color(0xFFEEEAF6), height: 1),
                  const SizedBox(height: 12),
                  // Grid de informações (2 colunas)
                  Row(
                    children: [
                      Expanded(
                        child: _InfoLinha(
                          icone: Icons.schedule_rounded,
                          label: 'Duração',
                          valor: '${plano.duracaoDias} dias',
                        ),
                      ),
                      Expanded(
                        child: _InfoLinha(
                          icone: Icons.people_outline_rounded,
                          label: 'Assinaturas ativas',
                          valor: '${plano.assinaturasAtivas}',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: _InfoLinha(
                          icone: Icons.hourglass_bottom_rounded,
                          label: 'Tolerância',
                          valor: '${plano.toleranciaDias} dias',
                        ),
                      ),
                      Expanded(
                        child: _InfoLinha(
                          icone: Icons.calendar_today_rounded,
                          label: 'Vencimento',
                          valor: plano.vencimentoPadrao,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  _InfoLinha(
                    icone: Icons.monetization_on_outlined,
                    label: 'Multa',
                    valor: '${plano.multaPercentual}% após vencimento',
                  ),
                  const SizedBox(height: 6),
                  _InfoLinha(
                    icone: Icons.trending_up_rounded,
                    label: 'Juros',
                    valor: '${plano.jurosPercentual}% ao dia',
                  ),
                  const SizedBox(height: 12),
                  // Chips
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: plano.modulos
                        .map((m) => _ModuleChip(label: m))
                        .toList(),
                  ),
                  const Spacer(),
                  // Rodapé: botão ver detalhes + três pontos
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {},
                          icon: const Icon(
                            Icons.remove_red_eye_outlined,
                            size: 16,
                          ),
                          label: Text(
                            'Ver detalhes',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: _roxoCard,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Color(0xFFD4C8F0)),
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            minimumSize: const Size(120, 38),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            backgroundColor: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      PopupMenuButton<String>(
                        offset: const Offset(0, 40),
                        color: Colors.white,
                        surfaceTintColor: Colors.transparent,
                        elevation: 8,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                          side: const BorderSide(color: Color(0xFFEEEAF6)),
                        ),
                        shadowColor: Colors.black.withValues(alpha: 0.12),
                        onSelected: (value) {
                          if (value == 'editar') onEditar();
                          if (value == 'toggle') onToggleAtivo();
                          if (value == 'deletar') onDeletar();
                        },
                        itemBuilder: (_) => [
                          _menuItemPop(
                            Icons.edit_outlined,
                            'Editar',
                            _textoPrimario,
                            'editar',
                          ),
                          const PopupMenuDivider(),
                          _menuItemPop(
                            plano.ativo
                                ? Icons.block_flipped
                                : Icons.check_circle_outline,
                            plano.ativo ? 'Bloquear' : 'Ativar',
                            plano.ativo
                                ? const Color(0xFFD97706)
                                : const Color(0xFF16A34A),
                            'toggle',
                          ),
                          const PopupMenuDivider(),
                          _menuItemPop(
                            Icons.delete_outline_rounded,
                            'Deletar',
                            const Color(0xFFDC2626),
                            'deletar',
                          ),
                        ],
                        child: SizedBox(
                          width: 38,
                          height: 38,
                          child: OutlinedButton(
                            onPressed: null,
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Color(0xFFD4C8F0)),
                              padding: EdgeInsets.zero,
                              minimumSize: const Size(38, 38),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              backgroundColor: Colors.white,
                            ),
                            child: const Icon(
                              Icons.more_horiz_rounded,
                              size: 18,
                              color: _roxoCard,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static PopupMenuItem<String> _menuItemPop(
    IconData icone,
    String label,
    Color cor,
    String value,
  ) {
    return PopupMenuItem<String>(
      value: value,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Icon(icone, size: 17, color: cor),
          const SizedBox(width: 10),
          Text(
            label,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: cor,
            ),
          ),
        ],
      ),
    );
  }
}

// --- INFO LINHA (para grid interno do card) ---
class _InfoLinha extends StatelessWidget {
  final IconData icone;
  final String label;
  final String valor;
  const _InfoLinha({
    required this.icone,
    required this.label,
    required this.valor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        children: [
          Icon(icone, size: 13, color: _textoSecundario),
          const SizedBox(width: 4),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 11,
                  color: _textoSecundario,
                  height: 1.3,
                ),
                children: [
                  TextSpan(text: '$label: '),
                  TextSpan(
                    text: valor,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: _textoPrimario,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// FUNÇÕES DE CONFIRMAÇÃO PREMIUM
// ============================================================

Future<bool> _confirmarAcao({
  required BuildContext context,
  required IconData icone,
  required Color corIcone,
  required String titulo,
  required String mensagem,
  required String textoConfirmar,
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black.withValues(alpha: 0.5),
    useRootNavigator: true,
    builder: (ctx) => Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 80),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Container(
        width: 400,
        padding: const EdgeInsets.fromLTRB(32, 32, 32, 24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: corIcone.withValues(alpha: 0.12),
              ),
              child: Icon(icone, size: 36, color: corIcone),
            ),
            const SizedBox(height: 20),
            Text(
              titulo,
              textAlign: TextAlign.center,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: _textoPrimario,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              mensagem,
              textAlign: TextAlign.center,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 14,
                color: _textoSecundario,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 28),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(ctx).pop(false),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFFE0DEE8)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      'Voltar',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: _textoSecundario,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Material(
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => Navigator.of(ctx).pop(true),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [corIcone, corIcone.withValues(alpha: 0.8)],
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Center(
                          child: Text(
                            textoConfirmar,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
  return result ?? false;
}

Future<void> _sucessoDialog({
  required BuildContext context,
  required String titulo,
  required String subtitulo,
}) async {
  await showDialog(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black.withValues(alpha: 0.5),
    useRootNavigator: true,
    builder: (ctx) => Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 80),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Container(
        width: 400,
        padding: const EdgeInsets.fromLTRB(32, 32, 32, 24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [Color(0xFF7D20E8), Color(0xFFD62BDB)],
                ),
              ),
              child: const Icon(
                Icons.check_rounded,
                size: 36,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              titulo,
              textAlign: TextAlign.center,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: _textoPrimario,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitulo,
              textAlign: TextAlign.center,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 14,
                color: _textoSecundario,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),
            Material(
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => Navigator.of(ctx).pop(),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [
                        Color(0xFF7D20E8),
                        Color(0xFFD62BDB),
                        Color(0xFFFF7A17),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Text(
                      'OK',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

// --- CARD "CRIAR NOVO PLANO" ---
class _CriarNovoPlanoCard extends StatelessWidget {
  final VoidCallback onTap;
  const _CriarNovoPlanoCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 420,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFFD4C8F0),
          width: 1.5,
          strokeAlign: BorderSide.strokeAlignInside,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: CustomPaint(
            painter: _DashedBorderPainter(color: const Color(0xFFC4B5E0)),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: _lilasFundo,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.note_add_outlined,
                      color: _roxoCard,
                      size: 28,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Criar novo plano',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: _textoPrimario,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      'Adicione um novo plano ou módulo para disponibilizar aos seus clientes.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        color: _textoSecundario,
                        height: 1.4,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  _BotaoGradiente(
                    onTap: onTap,
                    icone: Icons.add_rounded,
                    label: 'Novo plano',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// --- PAINTER PARA BORDA TRACEJADA ---
class _DashedBorderPainter extends CustomPainter {
  final Color color;
  _DashedBorderPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(0, 0, size.width, size.height),
          const Radius.circular(12),
        ),
      );
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter old) => old.color != color;
}

// ============================================================
// 9. MODAL "NOVO PLANO"
// ============================================================
class _CreatePlanDialog extends StatefulWidget {
  const _CreatePlanDialog();

  @override
  State<_CreatePlanDialog> createState() => _CreatePlanDialogState();
}

class _CreatePlanDialogState extends State<_CreatePlanDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nomeCtrl = TextEditingController();
  final _descricaoCtrl = TextEditingController();
  final _valorCtrl = TextEditingController();
  final _duracaoCtrl = TextEditingController(text: '30');
  final _toleranciaCtrl = TextEditingController(text: '3');
  final _multaCtrl = TextEditingController(text: '2');
  final _jurosCtrl = TextEditingController(text: '0,033');
  final _suspenderAposCtrl = TextEditingController(text: '15');
  final Set<String> _modulosSelecionados = {};
  bool _cobrarMulta = true;
  bool _cobrarJuros = true;
  bool _suspenderAutomatico = true;
  final String _tipoRecorrencia = 'Mensal';
  final String _statusInicial = 'Ativo';
  final String _jurosPeriodo = 'Ao dia';
  bool _salvando = false;

  @override
  void dispose() {
    _nomeCtrl.dispose();
    _descricaoCtrl.dispose();
    _valorCtrl.dispose();
    _duracaoCtrl.dispose();
    _toleranciaCtrl.dispose();
    _multaCtrl.dispose();
    _jurosCtrl.dispose();
    _suspenderAposCtrl.dispose();
    super.dispose();
  }

  Future<void> _salvar() async {
    if (!_formKey.currentState!.validate()) return;
    if (_modulosSelecionados.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selecione pelo menos um módulo vinculado.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    setState(() => _salvando = true);
    try {
      await ModulosPlanosService.criar(
        nome: _nomeCtrl.text.trim(),
        descricao: _descricaoCtrl.text.trim(),
        ativo: _statusInicial == 'Ativo',
        valor:
            double.tryParse(_valorCtrl.text.trim().replaceAll(',', '.')) ?? 0,
        duracaoDias: int.tryParse(_duracaoCtrl.text.trim()) ?? 30,
        toleranciaDias: int.tryParse(_toleranciaCtrl.text.trim()) ?? 3,
        multaPercentual: _cobrarMulta
            ? double.tryParse(_multaCtrl.text.trim().replaceAll(',', '.')) ?? 0
            : 0,
        jurosPercentual: _cobrarJuros
            ? double.tryParse(_jurosCtrl.text.trim().replaceAll(',', '.')) ?? 0
            : 0,
        modulos: _modulosSelecionados.toList(),
        moduloVinculado: _modulosSelecionados.first,
        cobrarMulta: _cobrarMulta,
        cobrarJuros: _cobrarJuros,
        suspenderInadimplencia: _suspenderAutomatico,
        suspenderAposDias: _suspenderAutomatico
            ? int.tryParse(_suspenderAposCtrl.text.trim())
            : null,
        tipoRecorrencia: _tipoRecorrencia,
      );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() => _salvando = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao criar plano: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 760,
        constraints: const BoxConstraints(maxHeight: 680),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            // Header fixo
            Container(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Color(0xFFEEEAF6))),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Criar novo plano',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: _textoPrimario,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Configure o valor, validade e regras de cobrança deste plano.',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 13,
                            color: _textoSecundario,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(
                      Icons.close_rounded,
                      color: _textoSecundario,
                    ),
                  ),
                ],
              ),
            ),
            // Conteúdo com scroll
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Grid campos principais
                      _campo(
                        label: 'Nome do plano *',
                        dica: 'Ex.: PDV Básico',
                        controller: _nomeCtrl,
                      ),
                      const SizedBox(height: 16),
                      _campo(
                        label: 'Descrição curta',
                        dica: 'Breve descrição do plano',
                        maxLines: 2,
                        controller: _descricaoCtrl,
                      ),
                      const SizedBox(height: 16),
                      _ModulosMultiSelect(
                        selecionados: _modulosSelecionados,
                        onChanged: (v) => setState(() => _modulosSelecionados
                          ..clear()
                          ..addAll(v)),
                      ),
                      const SizedBox(height: 12),
                      _dropdownField(
                        label: 'Status inicial',
                        valor: _statusInicial,
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: _campo(
                              label: 'Valor mensal *',
                              dica: 'R\$ 0,00',
                              prefix: 'R\$',
                              controller: _valorCtrl,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: _campo(
                              label: 'Duração (dias) *',
                              dica: '30',
                              controller: _duracaoCtrl,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: _dropdownField(
                              label: 'Tipo de recorrência',
                              valor: _tipoRecorrencia,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: _campo(
                              label: 'Tolerância (dias)',
                              dica: '3',
                              controller: _toleranciaCtrl,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      // Seção Multa e juros
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8F5FF),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFE8DFF5)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Multa e juros por atraso',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: _textoPrimario,
                              ),
                            ),
                            const SizedBox(height: 16),
                            _switchRow(
                              label: 'Cobrar multa após o vencimento',
                              valor: _cobrarMulta,
                              onChanged: (v) =>
                                  setState(() => _cobrarMulta = v),
                            ),
                            if (_cobrarMulta) ...[
                              const SizedBox(height: 10),
                              _campo(
                                label: 'Percentual da multa',
                                dica: '2%',
                                prefix: '%',
                                controller: _multaCtrl,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Cobrado uma única vez após o vencimento.',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 12,
                                  color: _textoSecundario,
                                ),
                              ),
                            ],
                            const SizedBox(height: 16),
                            _switchRow(
                              label: 'Cobrar juros por atraso',
                              valor: _cobrarJuros,
                              onChanged: (v) =>
                                  setState(() => _cobrarJuros = v),
                            ),
                            if (_cobrarJuros) ...[
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Expanded(
                                    child: _campo(
                                      label: 'Percentual de juros',
                                      dica: '0,033%',
                                      prefix: '%',
                                      controller: _jurosCtrl,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: _dropdownField(
                                      label: 'Período',
                                      valor: _jurosPeriodo,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Calculado automaticamente sobre o valor total da fatura a cada período de atraso.',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 12,
                                  color: _textoSecundario,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      // Seção Regras de acesso
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8F5FF),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFE8DFF5)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Regras de acesso',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: _textoPrimario,
                              ),
                            ),
                            const SizedBox(height: 16),
                            _switchRow(
                              label:
                                  'Suspender módulo automaticamente por inadimplência',
                              valor: _suspenderAutomatico,
                              onChanged: (v) =>
                                  setState(() => _suspenderAutomatico = v),
                            ),
                            if (_suspenderAutomatico) ...[
                              const SizedBox(height: 10),
                              _campo(
                                label: 'Suspender após quantos dias?',
                                dica: '15',
                                controller: _suspenderAposCtrl,
                              ),
                            ],
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFF8E6),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: const Color(0xFFFFE8B0),
                                ),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(
                                    Icons.info_outline_rounded,
                                    size: 16,
                                    color: Color(0xFFD97706),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'A suspensão afeta apenas o módulo contratado. O cliente continuará utilizando normalmente os recursos principais do DiPertin.',
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 12,
                                        color: const Color(0xFF92400E),
                                        height: 1.4,
                                      ),
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
              ),
            ),
            // Footer fixo
            Container(
              padding: const EdgeInsets.fromLTRB(24, 14, 24, 16),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Color(0xFFEEEAF6))),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(
                      'Cancelar',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: _textoSecundario,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  _BotaoGradiente(
                    onTap: () {
                      if (!_salvando) _salvar();
                    },
                    icone: Icons.check_rounded,
                    label: _salvando ? 'Salvando...' : 'Criar plano',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _campo({
    required String label,
    String? dica,
    int? maxLines,
    String? prefix,
    TextEditingController? controller,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: _textoSecundario,
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          maxLines: maxLines ?? 1,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 14,
            color: _textoPrimario,
          ),
          decoration: InputDecoration(
            hintText: dica,
            hintStyle: GoogleFonts.plusJakartaSans(
              fontSize: 14,
              color: _textoSecundario.withValues(alpha: 0.6),
            ),
            prefixText: prefix != null ? '$prefix ' : null,
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(
              vertical: 12,
              horizontal: 14,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: _bordaInput),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: _bordaInput),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: _roxoCard, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }

  Widget _dropdownField({required String label, required String valor}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: _textoSecundario,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _bordaInput),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  valor,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    color: _textoPrimario,
                  ),
                ),
              ),
              const Icon(
                Icons.arrow_drop_down_rounded,
                color: _textoSecundario,
                size: 22,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _switchRow({
    required String label,
    required bool valor,
    required ValueChanged<bool> onChanged,
  }) {
    return Row(
      children: [
        SizedBox(
          height: 24,
          child: Switch.adaptive(
            value: valor,
            onChanged: onChanged,
            activeTrackColor: _roxoCard.withValues(alpha: 0.4),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              color: _textoPrimario,
            ),
          ),
        ),
      ],
    );
  }
}

// ============================================================
// 9.5. MODAL EDITAR PLANO
// ============================================================
class _EditPlanDialog extends StatefulWidget {
  final PlanoAssinaturaModel plano;
  const _EditPlanDialog({required this.plano});

  @override
  State<_EditPlanDialog> createState() => _EditPlanDialogState();
}

class _EditPlanDialogState extends State<_EditPlanDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nomeCtrl;
  late final TextEditingController _descricaoCtrl;
  late final TextEditingController _valorCtrl;
  late final TextEditingController _duracaoCtrl;
  late final TextEditingController _toleranciaCtrl;
  late final TextEditingController _multaCtrl;
  late final TextEditingController _jurosCtrl;
  late final TextEditingController _suspenderAposCtrl;
  final Set<String> _modulosSelecionados = {};
  late bool _cobrarMulta;
  late bool _cobrarJuros;
  late bool _suspenderAutomatico;
  bool _salvando = false;

  @override
  void initState() {
    super.initState();
    _nomeCtrl = TextEditingController(text: widget.plano.nome);
    _descricaoCtrl = TextEditingController(text: widget.plano.descricao ?? '');
    _valorCtrl = TextEditingController(
      text: widget.plano.valor.toStringAsFixed(2).replaceAll('.', ','),
    );
    _duracaoCtrl = TextEditingController(text: '${widget.plano.duracaoDias}');
    _toleranciaCtrl = TextEditingController(
      text: '${widget.plano.toleranciaDias}',
    );
    _multaCtrl = TextEditingController(
      text: widget.plano.multaPercentual
          .toStringAsFixed(1)
          .replaceAll('.', ','),
    );
    _jurosCtrl = TextEditingController(
      text: widget.plano.jurosPercentual
          .toStringAsFixed(3)
          .replaceAll('.', ','),
    );
    _suspenderAposCtrl = TextEditingController(
      text: '${widget.plano.suspenderAposDias ?? 15}',
    );
    _modulosSelecionados
      ..clear()
      ..addAll(widget.plano.modulos);
    // Compatibilidade com planos antigos que só tinham moduloVinculado
    if (_modulosSelecionados.isEmpty &&
        widget.plano.moduloVinculado != null) {
      _modulosSelecionados.add(widget.plano.moduloVinculado!);
    }
    _cobrarMulta = widget.plano.cobrarMulta;
    _cobrarJuros = widget.plano.cobrarJuros;
    _suspenderAutomatico = widget.plano.suspenderInadimplencia;
  }

  @override
  void dispose() {
    _nomeCtrl.dispose();
    _descricaoCtrl.dispose();
    _valorCtrl.dispose();
    _duracaoCtrl.dispose();
    _toleranciaCtrl.dispose();
    _multaCtrl.dispose();
    _jurosCtrl.dispose();
    _suspenderAposCtrl.dispose();
    super.dispose();
  }

  Future<void> _salvar() async {
    if (!_formKey.currentState!.validate()) return;
    if (_modulosSelecionados.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selecione pelo menos um módulo vinculado.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    setState(() => _salvando = true);
    try {
      await ModulosPlanosService.atualizar(
        id: widget.plano.id,
        nome: _nomeCtrl.text.trim(),
        descricao: _descricaoCtrl.text.trim(),
        valor:
            double.tryParse(_valorCtrl.text.trim().replaceAll(',', '.')) ?? 0,
        duracaoDias: int.tryParse(_duracaoCtrl.text.trim()) ?? 30,
        toleranciaDias: int.tryParse(_toleranciaCtrl.text.trim()) ?? 3,
        multaPercentual: _cobrarMulta
            ? double.tryParse(_multaCtrl.text.trim().replaceAll(',', '.')) ?? 0
            : 0,
        jurosPercentual: _cobrarJuros
            ? double.tryParse(_jurosCtrl.text.trim().replaceAll(',', '.')) ?? 0
            : 0,
        modulos: _modulosSelecionados.toList(),
        moduloVinculado: _modulosSelecionados.first,
        cobrarMulta: _cobrarMulta,
        cobrarJuros: _cobrarJuros,
        suspenderInadimplencia: _suspenderAutomatico,
        suspenderAposDias: _suspenderAutomatico
            ? int.tryParse(_suspenderAposCtrl.text.trim())
            : null,
      );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() => _salvando = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao atualizar plano: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 760,
        constraints: const BoxConstraints(maxHeight: 680),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            // Header fixo
            Container(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Color(0xFFEEEAF6))),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Editar plano',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: _textoPrimario,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Altere as configurações do plano ${widget.plano.nome}.',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 13,
                            color: _textoSecundario,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(
                      Icons.close_rounded,
                      color: _textoSecundario,
                    ),
                  ),
                ],
              ),
            ),
            // Conteúdo com scroll
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _campo(
                        label: 'Nome do plano *',
                        dica: 'Ex.: PDV Básico',
                        controller: _nomeCtrl,
                      ),
                      const SizedBox(height: 16),
                      _campo(
                        label: 'Descrição curta',
                        dica: 'Breve descrição do plano',
                        maxLines: 2,
                        controller: _descricaoCtrl,
                      ),
                      const SizedBox(height: 16),
                      _ModulosMultiSelect(
                        selecionados: _modulosSelecionados,
                        onChanged: (v) => setState(() => _modulosSelecionados
                          ..clear()
                          ..addAll(v)),
                      ),
                      const SizedBox(height: 12),
                      _campo(
                        label: 'Status',
                        dica: 'Ativo',
                        controller: TextEditingController(
                          text: widget.plano.ativo ? 'Ativo' : 'Inativo',
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: _campo(
                              label: 'Valor mensal *',
                              dica: 'R\$ 0,00',
                              prefix: 'R\$',
                              controller: _valorCtrl,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: _campo(
                              label: 'Duração (dias) *',
                              dica: '30',
                              controller: _duracaoCtrl,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: _campo(
                              label: 'Tipo de recorrência',
                              dica: 'Mensal',
                              controller: TextEditingController(
                                text: widget.plano.tipoRecorrencia,
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: _campo(
                              label: 'Tolerância (dias)',
                              dica: '3',
                              controller: _toleranciaCtrl,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      // Seção Multa e juros
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8F5FF),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFE8DFF5)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Multa e juros por atraso',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: _textoPrimario,
                              ),
                            ),
                            const SizedBox(height: 16),
                            _switchRow(
                              label: 'Cobrar multa após o vencimento',
                              valor: _cobrarMulta,
                              onChanged: (v) =>
                                  setState(() => _cobrarMulta = v),
                            ),
                            if (_cobrarMulta) ...[
                              const SizedBox(height: 10),
                              _campo(
                                label: 'Percentual da multa',
                                dica: '2%',
                                prefix: '%',
                                controller: _multaCtrl,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Cobrado uma única vez após o vencimento.',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 12,
                                  color: _textoSecundario,
                                ),
                              ),
                            ],
                            const SizedBox(height: 16),
                            _switchRow(
                              label: 'Cobrar juros por atraso',
                              valor: _cobrarJuros,
                              onChanged: (v) =>
                                  setState(() => _cobrarJuros = v),
                            ),
                            if (_cobrarJuros) ...[
                              const SizedBox(height: 10),
                              _campo(
                                label: 'Percentual de juros',
                                dica: '0,033%',
                                prefix: '%',
                                controller: _jurosCtrl,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Calculado automaticamente sobre o valor total da fatura a cada período de atraso.',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 12,
                                  color: _textoSecundario,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      // Seção Regras de acesso
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8F5FF),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFE8DFF5)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Regras de acesso',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: _textoPrimario,
                              ),
                            ),
                            const SizedBox(height: 16),
                            _switchRow(
                              label:
                                  'Suspender módulo automaticamente por inadimplência',
                              valor: _suspenderAutomatico,
                              onChanged: (v) =>
                                  setState(() => _suspenderAutomatico = v),
                            ),
                            if (_suspenderAutomatico) ...[
                              const SizedBox(height: 10),
                              _campo(
                                label: 'Suspender após quantos dias?',
                                dica: '15',
                                controller: _suspenderAposCtrl,
                              ),
                            ],
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFF8E6),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: const Color(0xFFFFE8B0),
                                ),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(
                                    Icons.info_outline_rounded,
                                    size: 16,
                                    color: Color(0xFFD97706),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'A suspensão afeta apenas o módulo contratado. O cliente continuará utilizando normalmente os recursos principais do DiPertin.',
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 12,
                                        color: const Color(0xFF92400E),
                                        height: 1.4,
                                      ),
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
              ),
            ),
            // Footer fixo
            Container(
              padding: const EdgeInsets.fromLTRB(24, 14, 24, 16),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Color(0xFFEEEAF6))),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(
                      'Cancelar',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: _textoSecundario,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  _BotaoGradiente(
                    onTap: () {
                      if (!_salvando) _salvar();
                    },
                    icone: Icons.check_rounded,
                    label: _salvando ? 'Salvando...' : 'Salvar alterações',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _campo({
    required String label,
    String? dica,
    int? maxLines,
    String? prefix,
    TextEditingController? controller,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: _textoSecundario,
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          maxLines: maxLines ?? 1,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 14,
            color: _textoPrimario,
          ),
          decoration: InputDecoration(
            hintText: dica,
            hintStyle: GoogleFonts.plusJakartaSans(
              fontSize: 14,
              color: _textoSecundario.withValues(alpha: 0.6),
            ),
            prefixText: prefix != null ? '$prefix ' : null,
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(
              vertical: 12,
              horizontal: 14,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: _bordaInput),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: _bordaInput),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: _roxoCard, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }

  Widget _switchRow({
    required String label,
    required bool valor,
    required ValueChanged<bool> onChanged,
  }) {
    return Row(
      children: [
        SizedBox(
          height: 24,
          child: Switch.adaptive(
            value: valor,
            onChanged: onChanged,
            activeTrackColor: _roxoCard.withValues(alpha: 0.4),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              color: _textoPrimario,
            ),
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  _ModulosMultiSelect — multi-select de módulos como chips + busca
// ═══════════════════════════════════════════════════════════════════════════
class _ModulosMultiSelect extends StatefulWidget {
  final Set<String> selecionados;
  final ValueChanged<Set<String>> onChanged;

  const _ModulosMultiSelect({
    required this.selecionados,
    required this.onChanged,
  });

  @override
  State<_ModulosMultiSelect> createState() => _ModulosMultiSelectState();
}

class _ModulosMultiSelectState extends State<_ModulosMultiSelect> {
  final _searchCtrl = TextEditingController();
  bool _dropdownAberto = false;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: ModulosConfigService.stream(),
      builder: (context, snapshot) {
        final todosModulos =
            snapshot.data?.docs
                .map((d) => ModuloConfigModel.fromFirestore(d))
                .where((m) => m.ativo)
                .toList() ??
            [];

        final selecionados = widget.selecionados;
        final disponiveis =
            todosModulos.where((m) => !selecionados.contains(m.nome)).toList();

        final termo = _searchCtrl.text.trim().toLowerCase();
        final filtrados = termo.isEmpty
            ? disponiveis
            : disponiveis
                .where((m) => m.nome.toLowerCase().contains(termo))
                .toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Módulos vinculados *',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: _textoSecundario,
              ),
            ),
            const SizedBox(height: 6),
            // Área dos chips selecionados
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: selecionados.isEmpty
                      ? Colors.red.withValues(alpha: 0.4)
                      : _bordaInput,
                ),
              ),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  ...selecionados.map(
                    (mod) => Chip(
                      label: Text(mod, style: const TextStyle(fontSize: 12)),
                      deleteIcon: const Icon(Icons.close_rounded, size: 16),
                      onDeleted: () {
                        final nova = Set<String>.from(selecionados)
                          ..remove(mod);
                        widget.onChanged(nova);
                      },
                      backgroundColor: _roxoCard.withValues(alpha: 0.08),
                      side: BorderSide(
                        color: _roxoCard.withValues(alpha: 0.2),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      labelStyle: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        color: _textoPrimario,
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                  ActionChip(
                    label: const Text('+ Adicionar módulo'),
                    onPressed: () =>
                        setState(() => _dropdownAberto = !_dropdownAberto),
                    backgroundColor: _roxoCard.withValues(alpha: 0.04),
                    side: BorderSide(
                      color: _roxoCard.withValues(alpha: 0.15),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    labelStyle: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      color: _roxoCard,
                      fontWeight: FontWeight.w600,
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
            // Painel de seleção (aberto/fechado)
            if (_dropdownAberto) ...[
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _bordaInput),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Campo de busca
                    TextField(
                      controller: _searchCtrl,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        hintText: 'Buscar módulos...',
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 8,
                          horizontal: 10,
                        ),
                        prefixIcon:
                            const Icon(Icons.search_rounded, size: 18),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: const BorderSide(color: _bordaInput),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: const BorderSide(color: _bordaInput),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    // Lista de módulos disponíveis
                    if (filtrados.isNotEmpty)
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 200),
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: filtrados.length,
                          separatorBuilder: (_, __) =>
                              const Divider(height: 1),
                          itemBuilder: (_, idx) {
                            final m = filtrados[idx];
                            return InkWell(
                              onTap: () {
                                final nova = Set<String>.from(selecionados)
                                  ..add(m.nome);
                                widget.onChanged(nova);
                                _searchCtrl.clear();
                                setState(() => _dropdownAberto = false);
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 10,
                                  horizontal: 8,
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.check_circle_outline_rounded,
                                      size: 18,
                                      color: _roxoCard,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        m.nome,
                                        style: GoogleFonts.plusJakartaSans(
                                          fontSize: 13,
                                          color: _textoPrimario,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                    if (m.descricao.isNotEmpty)
                                      Flexible(
                                        child: Text(
                                          m.descricao,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: GoogleFonts.plusJakartaSans(
                                            fontSize: 11,
                                            color: _textoSecundario,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      )
                    else
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Text(
                          disponiveis.isEmpty && termo.isEmpty
                              ? 'Todos os módulos já foram selecionados'
                              : 'Nenhum módulo encontrado',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 13,
                            color: _textoSecundario,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                  ],
                ),
              ),
            ],
            if (snapshot.hasError)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Erro ao carregar módulos',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    color: Colors.red,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
