import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../navigation/painel_nav_controller.dart';
import '../navigation/painel_navigation_scope.dart';
import '../navigation/painel_routes.dart';
import '../theme/painel_admin_theme.dart';
import '../utils/firestore_web_safe.dart';
import 'sidebar_menu.dart';
import '../screens/dashboard_screen.dart';
import '../screens/lojas_screen.dart';
import '../screens/lojas_financeiro_dashboard_screen.dart';
import '../screens/entregadores_screen.dart';
import '../screens/central_clientes_screen.dart';
import '../screens/banners_screen.dart';
import '../screens/categorias_screen.dart';
import '../screens/admincity_cidades_screen.dart';
import '../screens/admincity_usuarios_screen.dart';
import '../screens/utilidades_screen.dart';
import '../screens/financeiro_screen.dart';
import '../screens/solicitacoes_saques_painel_screen.dart';
import '../screens/cadastro_acesso_colaboradores_screen.dart';
import '../screens/configuracoes_lojista_screen.dart';
import '../screens/atendimento_suporte_screen.dart';
import '../screens/notificacoes_screen.dart';
import '../screens/cupons_screen.dart';
import '../screens/monitor_pedidos_screen.dart';
import '../screens/centro_operacoes_screen.dart';
import '../screens/centro_operacoes_agenda_panel.dart';
import '../screens/centro_operacoes_leads_entregadores_panel.dart';
import '../screens/centro_operacoes_leads_lojistas_panel.dart';
import '../screens/centro_operacoes_marketing_dashboard_panel.dart';
import '../screens/avaliacoes_painel_screen.dart';
import '../screens/comunicados_screen.dart';
import '../screens/conteudo_legal_screen.dart';
import '../screens/lojista_pedidos_tabela_screen.dart';
import '../screens/lojista_negociacoes_encomenda_screen.dart';
import '../screens/lojista_meu_cardapio_screen.dart';
import '../screens/lojista_cupons_screen.dart';
import '../screens/lojista_pdv_screen.dart';
import '../screens/lojista_minha_carteira_screen.dart';
import '../screens/lojista_carteira_financeiro_screen.dart';
import '../screens/lojista_carteira_relatorio_screen.dart';
import '../screens/lojista_carteira_configuracao_screen.dart';
import '../screens/comercial_upsell_screen.dart';
import '../screens/lojista_comercial_dashboard_screen.dart';
import '../widgets/gestao_comercial_access_gate.dart';
import '../screens/lojista_comercial_clientes_screen.dart';
import '../screens/lojista_comercial_credito_screen.dart';
import '../screens/comercial_pendencias_screen.dart';
import '../screens/comercial_recebimentos_screen.dart';
import '../screens/comercial_historico_vendas_screen.dart';
import '../screens/comercial_configuracoes_screen.dart';
import '../screens/comercial_relatorio_screen.dart';
import '../screens/assinaturas_dashboard_screen.dart';
import '../screens/assinaturas_planos_screen.dart';
import '../screens/assinaturas_cobrancas_screen.dart';
import '../screens/assinaturas_clientes_screen.dart';
import '../screens/assinaturas_configuracoes_screen.dart';
import '../screens/assinaturas_fiscal_screen.dart';
import '../screens/assinaturas_inadimplencia_screen.dart';
import '../screens/assinaturas_relatorios_screen.dart';
import '../screens/lojista_minha_loja_screen.dart';
import '../screens/lojista_modulo_fiscal_screen.dart';
import '../screens/admin_fiscal_screen.dart';
import '../utils/admin_perfil.dart';
import '../utils/conta_bloqueio_lojista.dart';
import '../utils/lojista_painel_context.dart';
import '../services/sessao_painel_service.dart';
import 'lojista_conta_bloqueada_overlay.dart';

/// Layout persistente: menu fixo + [IndexedStack] lazy.
/// Só instancia cada tela na primeira vez que o usuário a visita.
class PainelShellScreen extends StatefulWidget {
  const PainelShellScreen({super.key, this.initialRoute = '/dashboard'});

  final String initialRoute;

  @override
  State<PainelShellScreen> createState() => _PainelShellScreenState();
}

class _PainelShellScreenState extends State<PainelShellScreen> {
  late final PainelNavController _nav;

  /// Uma entrada por aba; evita comparar com um único [SizedBox.shrink] partilhado
  /// (reutilizar a mesma instância em todos os slots do [IndexedStack] pode deixar o conteúdo em branco no web).
  late final List<bool> _tabMaterializada = List<bool>.filled(
    PainelRoutes.ordem.length,
    false,
  );

  /// Cache de widgets: uma vez criado, fica aqui para sempre (IndexedStack preserva state).
  late final List<Widget> _tabs = List<Widget>.generate(
    PainelRoutes.ordem.length,
    (i) => _PlaceholderAbaPainel(key: ValueKey<Object>('painel_ph_$i')),
  );

  @override
  void initState() {
    super.initState();
    _nav = PainelNavController(initial: widget.initialRoute);
    _materializarAba(PainelRoutes.indexOf(widget.initialRoute));
  }

  @override
  void dispose() {
    _nav.dispose();
    super.dispose();
  }

  bool _materializarAba(int i) {
    if (i < 0 || i >= _tabMaterializada.length) return false;
    final eraPlaceholder = _tabs[i] is _PlaceholderAbaPainel;
    if (_tabMaterializada[i] && !eraPlaceholder) return false;
    _tabMaterializada[i] = true;
    switch (i) {
      case 0:
        _tabs[i] = const DashboardScreen();
        break;
      case 1:
        _tabs[i] = LojasScreen();
        break;
      case 2:
        _tabs[i] = const LojasFinanceiroDashboardScreen();
        break;
      case 3:
        _tabs[i] = EntregadoresScreen();
        break;
      case 4:
        _tabs[i] = const CentralClientesScreen();
        break;
      case 5:
        _tabs[i] = BannersScreen();
        break;
      case 6:
        _tabs[i] = const CategoriasScreen();
        break;
      case 7:
        _tabs[i] = const AdminCityUsuariosScreen();
        break;
      case 8:
        _tabs[i] = const AdminCityCidadesScreen();
        break;
      case 9:
        _tabs[i] = UtilidadesScreen();
        break;
      case 10:
        _tabs[i] = FinanceiroScreen();
        break;
      case 11:
        _tabs[i] = const SolicitacoesSaquesPainelScreen();
        break;
      case 12:
        _tabs[i] = const ConfiguracoesPainelSlot();
        break;
      case 13:
        _tabs[i] = const CadastroAcessoColaboradoresScreen();
        break;
      case 14:
        _tabs[i] = AtendimentoSuporteScreen();
        break;
      case 15:
        _tabs[i] = const NotificacoesScreen();
        break;
      case 16:
        _tabs[i] = const CuponsScreen();
        break;
      case 17:
        _tabs[i] = const MonitorPedidosScreen();
        break;
      case 18:
        _tabs[i] = const CentroOperacoesCrmScreen();
        break;
      case 19:
        _tabs[i] = const PainelMarketingDashboard();
        break;
      case 20:
        _tabs[i] = const PainelLeadsLojistas();
        break;
      case 21:
        _tabs[i] = const PainelLeadsEntregadores();
        break;
      case 22:
        _tabs[i] = const PainelCentroOpsAgenda();
        break;
      case 23:
        _tabs[i] = const CentroOperacoesFreteScreen();
        break;
      case 24:
        _tabs[i] = const AvaliacoesPainelScreen();
        break;
      case 25:
        _tabs[i] = const ComunicadosScreen();
        break;
      case 26:
        _tabs[i] = const ConteudoLegalScreen();
        break;
      case 27:
        _tabs[i] = GestaoComercialAccessGate(
          semPlano: const ComercialUpsellScreen(),
          child: const LojistaPdvScreen(),
        );
        break;
      case 28:
        _tabs[i] = const LojistaPedidosTabelaScreen();
        break;
      case 29:
        _tabs[i] = const LojistaNegociacoesEncomendaScreen();
        break;
      case 30:
        _tabs[i] = const LojistaMeuCardapioScreen();
        break;
      case 31:
        _tabs[i] = const LojistaCuponsScreen();
        break;
      case 32:
        _tabs[i] = const LojistaMinhaCarteiraScreen();
        break;
      case 33:
        _tabs[i] = const LojistaCarteiraFinanceiroScreen();
        break;
      case 34:
        _tabs[i] = const LojistaCarteiraRelatorioScreen();
        break;
      case 35:
        _tabs[i] = const LojistaCarteiraConfiguracaoScreen();
        break;
      case 36:
        _tabs[i] = GestaoComercialAccessGate(
          semPlano: const ComercialUpsellScreen(),
          child: const LojistaComercialDashboardScreen(),
        );
        break;
      case 37:
        _tabs[i] = GestaoComercialAccessGate(
          semPlano: const ComercialUpsellScreen(),
          child: const LojistaMinhaLojaScreen(),
        );
        break;
      case 38:
        _tabs[i] = GestaoComercialAccessGate(
          semPlano: const ComercialUpsellScreen(),
          child: const LojistaComercialClientesScreen(),
        );
        break;
      case 39:
        _tabs[i] = GestaoComercialAccessGate(
          semPlano: const ComercialUpsellScreen(),
          child: const LojistaComercialCreditoScreen(),
        );
        break;
      case 40:
        _tabs[i] = GestaoComercialAccessGate(
          semPlano: const ComercialUpsellScreen(),
          child: const ComercialPendenciasScreen(),
        );
        break;
      case 41:
        _tabs[i] = GestaoComercialAccessGate(
          semPlano: const ComercialUpsellScreen(),
          child: const ComercialRecebimentosScreen(),
        );
        break;
      case 42:
        _tabs[i] = GestaoComercialAccessGate(
          semPlano: const ComercialUpsellScreen(),
          child: const ComercialHistoricoVendasScreen(),
        );
        break;
      case 43:
        _tabs[i] = GestaoComercialAccessGate(
          semPlano: const ComercialUpsellScreen(),
          child: const ComercialRelatorioScreen(),
        );
        break;
      case 44:
        _tabs[i] = GestaoComercialAccessGate(
          semPlano: const ComercialUpsellScreen(),
          child: const ComercialConfiguracoesScreen(),
        );
        break;
      case 45:
        _tabs[i] = const AssinaturasDashboardScreen();
        break;
      case 46:
        _tabs[i] = const AssinaturasClientesScreen();
        break;
      case 47:
        _tabs[i] = const AssinaturasPlanosScreen();
        break;
      case 48:
        _tabs[i] = const AssinaturasCobrancasScreen();
        break;
      case 49:
        _tabs[i] = const AssinaturasInadimplenciaScreen();
        break;
      case 50:
        _tabs[i] = const AssinaturasRelatoriosScreen();
        break;
      case 51:
        _tabs[i] = const AssinaturasFiscalScreen();
        break;
      case 52:
        _tabs[i] = const AssinaturasConfiguracoesScreen();
        break;
      case 53:
        _tabs[i] = const LojistaModuloFiscalScreen();
        break;
      case 54:
        _tabs[i] = const AdminFiscalScreen();
        break;
      default:
        _tabs[i] = Scaffold(
          backgroundColor: PainelAdminTheme.fundoCanvas,
          body: Center(
            child: Text(
              'Aba do painel não implementada (índice $i).',
              style: const TextStyle(color: PainelAdminTheme.textoSecundario),
            ),
          ),
        );
        break;
    }
    return eraPlaceholder;
  }

  Widget _conteudoPainel(
    BuildContext context,
    Map<String, dynamic>? dados,
    Map<String, dynamic>? dadosBloqueio,
  ) {
    return ListenableBuilder(
      listenable: _nav,
      builder: (context, _) {
        final idx = PainelRoutes.indexOf(_nav.currentRoute);
        if (_materializarAba(idx)) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() {});
          });
        }

        final bloqueado =
            dadosBloqueio != null &&
            perfilAdministrativo(dadosBloqueio) == 'lojista' &&
            ContaBloqueioLojistaHelper.estaBloqueadoParaOperacoes(
              dadosBloqueio,
            );

        return PainelNavigationScope(
          notifier: _nav,
          child: ColoredBox(
            color: PainelAdminTheme.fundoCanvas,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SidebarMenu(
                      rotaAtual: _nav.currentRoute,
                      onNavegarPainel: _nav.navigateTo,
                    ),
                    Expanded(
                      child: Material(
                        color: PainelAdminTheme.fundoCanvas,
                        clipBehavior: Clip.none,
                        child: IndexedStack(
                          index: idx,
                          sizing: StackFit.expand,
                          children: _tabs
                              .map((tab) => SizedBox.expand(child: tab))
                              .toList(),
                        ),
                      ),
                    ),
                  ],
                ),
                if (bloqueado)
                  Positioned.fill(
                    child: LojistaContaBloqueadaOverlayWeb(
                      dadosUsuario: dadosBloqueio,
                      onSair: () async {
                        await FirebaseAuth.instance.signOut();
                        if (context.mounted) {
                          Navigator.pushReplacementNamed(context, '/login');
                        }
                      },
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return const SizedBox.shrink();
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .snapshots(),
      builder: (context, userSnap) {
        // Detecção REATIVA e GLOBAL de sessão expirada: se o token expirou/foi
        // revogado, este stream (ativo em toda rota do painel) erra com
        // `permission-denied`. Aciona o fluxo profissional uma única vez em vez
        // de propagar o erro técnico para as telas.
        if (userSnap.hasError &&
            SessaoPainelService.ehErroSessaoExpirada(userSnap.error)) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            SessaoPainelService.tratarSessaoExpirada();
          });
          return const SizedBox.shrink();
        }
        Map<String, dynamic>? dados;
        if (userSnap.hasData && userSnap.data!.exists) {
          final raw = safeWebDocData(userSnap.data!);
          dados = raw.isNotEmpty ? raw : null;
        }
        if (dados != null && perfilAdministrativo(dados) == 'lojista') {
          final n = nivelAcessoPainelLojista(dados);
          final r = sanearRotaPainelLojista(_nav.currentRoute, n);
          if (r != _nav.currentRoute) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              _nav.navigateTo(r);
            });
          }
        }

        final lid = uidLojaEfetivo(dados, uid);
        if (lid == uid) {
          return _conteudoPainel(context, dados, dados);
        }
        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('users')
              .doc(lid)
              .snapshots(),
          builder: (context, ownerSnap) {
            Map<String, dynamic>? ownerD;
            if (ownerSnap.data != null && ownerSnap.data!.exists) {
              final raw = safeWebDocData(ownerSnap.data!);
              ownerD = raw.isNotEmpty ? raw : null;
            }
            return _conteudoPainel(context, dados, ownerD ?? dados);
          },
        );
      },
    );
  }
}

/// Ocupa o espaço da aba até a tela ser materializada (evita altura 0 com [SizedBox.shrink]).
class _PlaceholderAbaPainel extends StatelessWidget {
  const _PlaceholderAbaPainel({super.key});

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Colors.transparent,
      child: SizedBox.expand(),
    );
  }
}
