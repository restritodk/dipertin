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
import '../screens/entregadores_screen.dart';
import '../screens/banners_screen.dart';
import '../screens/admin_city_screen.dart';
import '../screens/utilidades_screen.dart';
import '../screens/financeiro_screen.dart';
import '../screens/solicitacoes_saques_painel_screen.dart';
import '../screens/cadastro_acesso_colaboradores_screen.dart';
import '../screens/configuracoes_lojista_screen.dart';
import '../screens/atendimento_suporte_screen.dart';
import '../screens/notificacoes_screen.dart';
import '../screens/cupons_screen.dart';
import '../screens/monitor_pedidos_screen.dart';
import '../screens/avaliacoes_painel_screen.dart';
import '../screens/comunicados_screen.dart';
import '../screens/conteudo_legal_screen.dart';
import '../screens/lojista_meus_pedidos_screen.dart';
import '../screens/lojista_meu_cardapio_screen.dart';
import '../screens/lojista_minha_carteira_screen.dart';
import '../screens/lojista_carteira_financeiro_screen.dart';
import '../screens/lojista_carteira_relatorio_screen.dart';
import '../screens/lojista_carteira_configuracao_screen.dart';
import '../utils/admin_perfil.dart';
import '../utils/conta_bloqueio_lojista.dart';
import '../utils/lojista_painel_context.dart';
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
  late final List<bool> _tabMaterializada =
      List<bool>.filled(PainelRoutes.ordem.length, false);

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

  void _materializarAba(int i) {
    if (i < 0 || i >= _tabMaterializada.length) return;
    if (_tabMaterializada[i]) return;
    _tabMaterializada[i] = true;
    switch (i) {
      case 0:
        _tabs[i] = const DashboardScreen();
        break;
      case 1:
        _tabs[i] = LojasScreen();
        break;
      case 2:
        _tabs[i] = EntregadoresScreen();
        break;
      case 3:
        _tabs[i] = BannersScreen();
        break;
      case 4:
        _tabs[i] = AdminCityScreen();
        break;
      case 5:
        _tabs[i] = UtilidadesScreen();
        break;
      case 6:
        _tabs[i] = FinanceiroScreen();
        break;
      case 7:
        _tabs[i] = const SolicitacoesSaquesPainelScreen();
        break;
      case 8:
        _tabs[i] = const ConfiguracoesPainelSlot();
        break;
      case 9:
        _tabs[i] = const CadastroAcessoColaboradoresScreen();
        break;
      case 10:
        _tabs[i] = AtendimentoSuporteScreen();
        break;
      case 11:
        _tabs[i] = const NotificacoesScreen();
        break;
      case 12:
        _tabs[i] = const CuponsScreen();
        break;
      case 13:
        _tabs[i] = const MonitorPedidosScreen();
        break;
      case 14:
        _tabs[i] = const AvaliacoesPainelScreen();
        break;
      case 15:
        _tabs[i] = const ComunicadosScreen();
        break;
      case 16:
        _tabs[i] = const ConteudoLegalScreen();
        break;
      case 17:
        _tabs[i] = const LojistaMeusPedidosScreen();
        break;
      case 18:
        _tabs[i] = const LojistaMeuCardapioScreen();
        break;
      case 19:
        _tabs[i] = const LojistaMinhaCarteiraScreen();
        break;
      case 20:
        _tabs[i] = const LojistaCarteiraFinanceiroScreen();
        break;
      case 21:
        _tabs[i] = const LojistaCarteiraRelatorioScreen();
        break;
      case 22:
        _tabs[i] = const LojistaCarteiraConfiguracaoScreen();
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
        _materializarAba(idx);

        final bloqueado = dadosBloqueio != null &&
            perfilAdministrativo(dadosBloqueio) == 'lojista' &&
            ContaBloqueioLojistaHelper.estaBloqueadoParaOperacoes(dadosBloqueio);

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
                      child: IndexedStack(
                        index: idx,
                        sizing: StackFit.expand,
                        children: List<Widget>.from(_tabs),
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
      stream:
          FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
      builder: (context, userSnap) {
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
