import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:depertin_web/navigation/painel_routes.dart';
import 'package:depertin_web/services/saques_solicitacoes_menu_contagem.dart';
import 'package:depertin_web/utils/admin_perfil.dart';
import 'package:depertin_web/utils/firestore_web_safe.dart';
import 'package:depertin_web/utils/lojista_painel_context.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

/// Menu lateral do painel DiPertin — collapsible sidebar.
///
/// Expandido: 280 px (logo + texto + itens com rótulo).
/// Colapsado : 64 px  (só ícones + tooltips).
/// Toggle    : botão "chevron" no cabeçalho, animação 220 ms easeInOut.
class SidebarMenu extends StatefulWidget {
  const SidebarMenu({
    super.key,
    required this.rotaAtual,
    this.onNavegarPainel,
  });

  final String rotaAtual;
  final void Function(String route)? onNavegarPainel;

  static const double largura = 280;
  static const double larguraColapsada = 64;

  @override
  State<SidebarMenu> createState() => _SidebarMenuState();
}

class _SidebarMenuState extends State<SidebarMenu> {
  bool _collapsed = false;

  void _toggleColapso() => setState(() => _collapsed = !_collapsed);

  void _navegar(BuildContext context, String rota, {required bool jaAtivo}) {
    if (jaAtivo) return;
    final fn = widget.onNavegarPainel;
    if (fn != null && PainelRoutes.isShellRoute(rota)) {
      fn(rota);
    } else {
      Navigator.pushReplacementNamed(context, rota);
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return _sidebarCarregando();
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream:
          FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return _sidebarCarregando();
        }
        final doc = snap.data;
        if (doc == null || !doc.exists) {
          return _sidebarCarregando();
        }
        final dados = safeWebDocData(doc);
        if (dados.isEmpty) return _sidebarCarregando();
        final perfil = perfilAdministrativoPainel(dados);
        final lojista = perfil == 'lojista';
        final int? nivelPainel =
            lojista ? nivelAcessoPainelLojista(dados) : null;

        if (!lojista) {
          return _SidebarNovo(
            perfil: perfil,
            nivelPainelLojista: nivelPainel,
            nomeLoja: null,
            rotaAtual: widget.rotaAtual,
            collapsed: _collapsed,
            onToggleColapso: _toggleColapso,
            onTapItem: (ctx, rota, ativo) =>
                _navegar(ctx, rota, jaAtivo: ativo),
          );
        }

        final uidLoja = uidLojaEfetivo(dados, uid);
        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('users')
              .doc(uidLoja)
              .snapshots(),
          builder: (context, snapLoja) {
            String? nomeLoja;
            if (snapLoja.hasData && snapLoja.data!.exists) {
              final m = safeWebDocData(snapLoja.data!);
              if (m.isNotEmpty) {
                final s = (m['loja_nome'] ?? m['nome'] ?? '').toString().trim();
                if (s.isNotEmpty) nomeLoja = s;
              }
            }
            return _SidebarNovo(
              perfil: perfil,
              nivelPainelLojista: nivelPainel,
              nomeLoja: nomeLoja,
              rotaAtual: widget.rotaAtual,
              collapsed: _collapsed,
              onToggleColapso: _toggleColapso,
              onTapItem: (ctx, rota, ativo) =>
                  _navegar(ctx, rota, jaAtivo: ativo),
            );
          },
        );
      },
    );
  }

  Widget _sidebarCarregando() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeInOut,
      width: _collapsed ? SidebarMenu.larguraColapsada : SidebarMenu.largura,
      child: const ColoredBox(
        color: _TemaNav.fundo,
        child: Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: _TemaNav.accent,
            ),
          ),
        ),
      ),
    );
  }
}

// ——— Design system ———

class _TemaNav {
  static const Color fundo = Color(0xFF15122A);
  static const Color fundoElevado = Color(0xFF1E1B36);
  static const Color borda = Color(0xFF2D2848);
  static const Color texto = Color(0xFFF1F0F6);
  static const Color textoMuted = Color(0xFF9B97B3);
  static const Color accent = Color(0xFFFF8F00);
  static const Color accentSoft = Color(0x26FF8F00);
  static const Color hover = Color(0x14FFFFFF);
  static const Color ativoBg = Color(0x1FFFFFFF);

  static const TextStyle semSublinhado = TextStyle(
    decoration: TextDecoration.none,
    decorationThickness: 0,
  );
}

// ——— Sidebar principal ———

class _SidebarNovo extends StatelessWidget {
  const _SidebarNovo({
    required this.perfil,
    required this.nivelPainelLojista,
    this.nomeLoja,
    required this.rotaAtual,
    required this.collapsed,
    required this.onToggleColapso,
    required this.onTapItem,
  });

  final String perfil;
  /// `null` se não for lojista (master/staff). 1–3 para colaboradores/dono.
  final int? nivelPainelLojista;
  /// Nome comercial da loja (doc. do dono: `loja_nome` ou `nome`). Só lojista.
  final String? nomeLoja;
  final String rotaAtual;
  final bool collapsed;
  final VoidCallback onToggleColapso;
  final void Function(BuildContext context, String rota, bool jaAtivo) onTapItem;

  @override
  Widget build(BuildContext context) {
    final podeGestao = perfilPodeGestaoLojasEntregadoresBanners(perfil);
    final podeChefe = perfilPodeMenuChefe(perfil);
    final podeClientes = perfilPodeCentralClientes(perfil);
    final lojista = perfil == 'lojista';
    final n = nivelPainelLojista;
    final showMeuCardapio = n == null || n >= 2;
    final showCarteiraEConfig = n == null || n >= 3;

    final itens = <Widget>[];

    if (!lojista) {
      itens.add(_SecaoLabel('Principal', collapsed: collapsed));
    }
    itens.add(
      _NavRow(
        rota: '/dashboard',
        label: 'Dashboard',
        icon: Icons.dashboard,
        rotaAtual: rotaAtual,
        collapsed: collapsed,
        onTap: (c) => onTapItem(c, '/dashboard', rotaAtual == '/dashboard'),
      ),
    );

    if (podeGestao) {
      itens.add(_SecaoLabel('Operação', collapsed: collapsed));
      itens.addAll([
        _NavRow(
          rota: '/lojas',
          label: 'Lojas',
          icon: Icons.store,
          rotaAtual: rotaAtual,
          collapsed: collapsed,
          onTap: (c) => onTapItem(c, '/lojas', rotaAtual == '/lojas'),
        ),
        _NavRow(
          rota: '/entregadores',
          label: 'Entregadores',
          icon: Icons.local_shipping,
          rotaAtual: rotaAtual,
          collapsed: collapsed,
          onTap: (c) =>
              onTapItem(c, '/entregadores', rotaAtual == '/entregadores'),
        ),
        if (podeClientes)
          _NavRow(
            rota: '/clientes',
            label: 'Central de clientes',
            icon: Icons.people_alt_rounded,
            rotaAtual: rotaAtual,
            collapsed: collapsed,
            onTap: (c) =>
                onTapItem(c, '/clientes', rotaAtual == '/clientes'),
          ),
        _NavRow(
          rota: '/monitor_pedidos',
          label: 'Monitor de pedidos',
          icon: Icons.receipt,
          rotaAtual: rotaAtual,
          collapsed: collapsed,
          onTap: (c) =>
              onTapItem(c, '/monitor_pedidos', rotaAtual == '/monitor_pedidos'),
        ),
        _NavRow(
          rota: '/avaliacoes_painel',
          label: 'Avaliações',
          icon: Icons.star,
          rotaAtual: rotaAtual,
          collapsed: collapsed,
          onTap: (c) => onTapItem(
              c, '/avaliacoes_painel', rotaAtual == '/avaliacoes_painel'),
        ),
        _NavRow(
          rota: '/banners',
          label: 'Banners da vitrine',
          icon: Icons.photo,
          rotaAtual: rotaAtual,
          collapsed: collapsed,
          onTap: (c) => onTapItem(c, '/banners', rotaAtual == '/banners'),
        ),
      ]);
    }

    if (lojista) {
      itens.add(_SecaoLabel('Minha loja', collapsed: collapsed));
      itens.addAll([
        _NavRow(
          rota: '/meus_pedidos',
          label: 'Meus pedidos',
          icon: Icons.receipt,
          rotaAtual: rotaAtual,
          collapsed: collapsed,
          onTap: (c) =>
              onTapItem(c, '/meus_pedidos', rotaAtual == '/meus_pedidos'),
        ),
        if (showMeuCardapio)
          _NavRow(
            rota: '/meu_cardapio',
            label: 'Meus produtos',
            icon: Icons.inventory_2_outlined,
            rotaAtual: rotaAtual,
            collapsed: collapsed,
            onTap: (c) =>
                onTapItem(c, '/meu_cardapio', rotaAtual == '/meu_cardapio'),
          ),
        if (showCarteiraEConfig)
          _GrupoCarteira(
            rotaAtual: rotaAtual,
            collapsed: collapsed,
            onTapItem: onTapItem,
          ),
      ]);
    }

    // Gestão (master / superadmin): inclui fila de saques — só este perfil vê "Solicitações de saque".
    if (podeChefe) {
      itens.add(_SecaoLabel('Gestão', collapsed: collapsed));
      itens.addAll([
        _GrupoAdminCity(
          rotaAtual: rotaAtual,
          collapsed: collapsed,
          onTapItem: onTapItem,
        ),
        _NavRow(
          rota: '/utilidades',
          label: 'Anúncios e utilidades',
          icon: Icons.campaign,
          rotaAtual: rotaAtual,
          collapsed: collapsed,
          onTap: (c) =>
              onTapItem(c, '/utilidades', rotaAtual == '/utilidades'),
        ),
        _NavRow(
          rota: '/financeiro',
          label: 'Financeiro geral',
          icon: Icons.menu_book_outlined,
          rotaAtual: rotaAtual,
          collapsed: collapsed,
          onTap: (c) =>
              onTapItem(c, '/financeiro', rotaAtual == '/financeiro'),
        ),
        _NavRowSaquesComContador(
          rotaAtual: rotaAtual,
          collapsed: collapsed,
          onTapItem: onTapItem,
        ),
      ]);
    }

    if (podeGestao || podeChefe) {
      itens.add(_SecaoLabel('Marketing', collapsed: collapsed));
      itens.addAll([
        _NavRow(
          rota: '/notificacoes',
          label: 'Notificações push',
          icon: Icons.notifications,
          rotaAtual: rotaAtual,
          collapsed: collapsed,
          onTap: (c) =>
              onTapItem(c, '/notificacoes', rotaAtual == '/notificacoes'),
        ),
        _NavRow(
          rota: '/cupons',
          label: 'Cupons e promoções',
          icon: Icons.local_offer,
          rotaAtual: rotaAtual,
          collapsed: collapsed,
          onTap: (c) => onTapItem(c, '/cupons', rotaAtual == '/cupons'),
        ),
        _NavRow(
          rota: '/comunicados',
          label: 'Comunicados',
          icon: Icons.message,
          rotaAtual: rotaAtual,
          collapsed: collapsed,
          onTap: (c) =>
              onTapItem(c, '/comunicados', rotaAtual == '/comunicados'),
        ),
      ]);
    }

    if (showCarteiraEConfig || !lojista) {
      itens.add(_SecaoLabel('Sistema', collapsed: collapsed));
      if (lojista && showCarteiraEConfig) {
        itens.add(
          _GrupoConfiguracaoLojista(
            rotaAtual: rotaAtual,
            collapsed: collapsed,
            onTapItem: onTapItem,
          ),
        );
      } else {
        itens.add(
          _NavRow(
            rota: '/configuracoes',
            label: 'Configurações',
            icon: Icons.settings,
            rotaAtual: rotaAtual,
            collapsed: collapsed,
            onTap: (c) =>
                onTapItem(c, '/configuracoes', rotaAtual == '/configuracoes'),
          ),
        );
      }
    }

    if (podeGestao || podeChefe) {
      itens.addAll([
        _NavRow(
          rota: '/atendimento_suporte',
          label: 'Suporte',
          icon: Icons.headset_mic,
          rotaAtual: rotaAtual,
          collapsed: collapsed,
          onTap: (c) => onTapItem(
              c, '/atendimento_suporte', rotaAtual == '/atendimento_suporte'),
        ),
        _NavRow(
          rota: '/conteudo_legal',
          label: 'Conteúdo legal',
          icon: Icons.description,
          rotaAtual: rotaAtual,
          collapsed: collapsed,
          onTap: (c) =>
              onTapItem(c, '/conteudo_legal', rotaAtual == '/conteudo_legal'),
        ),
      ]);
    }

    return LayoutBuilder(
      builder: (context, c) {
        final h = c.maxHeight.isFinite && c.maxHeight > 0
            ? c.maxHeight
            : MediaQuery.sizeOf(context).height;

        return AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeInOut,
          width: collapsed
              ? SidebarMenu.larguraColapsada
              : SidebarMenu.largura,
          height: h,
          clipBehavior: Clip.hardEdge,
          decoration: const BoxDecoration(
            color: _TemaNav.fundo,
            border: Border(
              right: BorderSide(color: _TemaNav.borda, width: 1),
            ),
          ),
          child: DefaultTextStyle.merge(
            style: _TemaNav.semSublinhado,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _TopoMarca(
                  perfil: perfil,
                  nomeLoja: nomeLoja,
                  collapsed: collapsed,
                  onToggle: onToggleColapso,
                ),
                Expanded(
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: EdgeInsets.fromLTRB(
                      collapsed ? 6 : 12,
                      8,
                      collapsed ? 6 : 12,
                      16,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: itens,
                    ),
                  ),
                ),
                const Divider(height: 1, thickness: 1, color: _TemaNav.borda),
                _RodapeSair(
                  collapsed: collapsed,
                  onSair: () async {
                    final confirmar = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        title: Row(
                          children: [
                            Icon(Icons.logout_rounded,
                                color: Colors.red.shade400, size: 24),
                            const SizedBox(width: 10),
                            const Text(
                              'Sair do painel',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                        content: const Text(
                          'Tem certeza que deseja sair da sua conta?',
                          style: TextStyle(fontSize: 15),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: Text(
                              'Cancelar',
                              style: TextStyle(
                                color: Colors.grey.shade600,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          FilledButton.icon(
                            onPressed: () => Navigator.pop(ctx, true),
                            icon: const Icon(Icons.logout_rounded, size: 18),
                            label: const Text('Sair'),
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.red.shade600,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                    if (confirmar != true) return;
                    await FirebaseAuth.instance.signOut();
                    if (context.mounted) {
                      Navigator.pushReplacementNamed(context, '/login');
                    }
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ——— Cabeçalho ———

class _TopoMarca extends StatelessWidget {
  const _TopoMarca({
    required this.perfil,
    this.nomeLoja,
    required this.collapsed,
    required this.onToggle,
  });

  final String perfil;
  /// Exibido abaixo do badge (ex.: LOJISTA) quando for lojista.
  final String? nomeLoja;
  final bool collapsed;
  final VoidCallback onToggle;

  String get _badge {
    switch (perfil) {
      case 'master':
        return 'Master';
      case 'master_city':
        return 'Regional';
      case 'lojista':
        return 'Lojista';
      default:
        return perfil.isEmpty
            ? '—'
            : perfil[0].toUpperCase() + perfil.substring(1);
    }
  }

  String get _subtitulo {
    switch (perfil) {
      case 'master':
        return 'Centro de comando';
      case 'master_city':
        return 'Gestão regional';
      case 'lojista':
        return 'Painel da loja';
      default:
        return 'Painel administrativo';
    }
  }

  @override
  Widget build(BuildContext context) {
    final nomeLojaExibir = nomeLoja;

    final logo = ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Image.asset(
        'assets/logo.png',
        width: collapsed ? 38 : 44,
        height: collapsed ? 38 : 44,
        fit: BoxFit.cover,
        errorBuilder: (context, error, _) => Container(
          width: collapsed ? 38 : 44,
          height: collapsed ? 38 : 44,
          decoration: BoxDecoration(
            color: _TemaNav.borda,
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.hub_outlined,
              color: _TemaNav.textoMuted, size: 22),
        ),
      ),
    );

    // ── Colapsado ──
    if (collapsed) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(0, 16, 0, 8),
        child: Column(
          children: [
            logo,
            const SizedBox(height: 10),
            _BotaoColapso(collapsed: collapsed, onToggle: onToggle),
            const SizedBox(height: 6),
          ],
        ),
      );
    }

    // ── Expandido ──
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _TemaNav.fundoElevado,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _TemaNav.borda),
            ),
            child: Row(
              children: [
                logo,
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'DiPertin',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: _TemaNav.texto,
                          letterSpacing: -0.3,
                          decoration: TextDecoration.none,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _subtitulo,
                        style: const TextStyle(
                          fontSize: 11,
                          color: _TemaNav.textoMuted,
                          fontWeight: FontWeight.w500,
                          decoration: TextDecoration.none,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: _TemaNav.accentSoft,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: _TemaNav.accent.withValues(alpha: 0.35),
                          ),
                        ),
                        child: Text(
                          _badge.toUpperCase(),
                          style: const TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.1,
                            color: _TemaNav.accent,
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ),
                      if (perfil == 'lojista' &&
                          nomeLojaExibir != null &&
                          nomeLojaExibir.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          nomeLojaExibir,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            height: 1.25,
                            color: _TemaNav.texto,
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: _BotaoColapso(collapsed: collapsed, onToggle: onToggle),
          ),
        ],
      ),
    );
  }
}

// ——— Botão toggle expand/colapso ———

class _BotaoColapso extends StatelessWidget {
  const _BotaoColapso({required this.collapsed, required this.onToggle});

  final bool collapsed;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: collapsed ? 'Expandir menu' : 'Recolher menu',
      preferBelow: false,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onToggle,
          borderRadius: BorderRadius.circular(8),
          hoverColor: _TemaNav.hover,
          focusColor: Colors.transparent,
          highlightColor: Colors.transparent,
          child: Container(
            width: collapsed ? 40 : 34,
            height: 28,
            decoration: BoxDecoration(
              color: _TemaNav.fundoElevado,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _TemaNav.borda),
            ),
            child: Center(
              child: Icon(
                collapsed
                    ? Icons.keyboard_double_arrow_right_rounded
                    : Icons.keyboard_double_arrow_left_rounded,
                size: 16,
                color: _TemaNav.textoMuted,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ——— Rótulo de seção ———

class _SecaoLabel extends StatelessWidget {
  const _SecaoLabel(this.texto, {required this.collapsed});

  final String texto;
  final bool collapsed;

  @override
  Widget build(BuildContext context) {
    if (collapsed) {
      // Separador visual minimalista no lugar do label
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Container(height: 1, color: _TemaNav.borda),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 20, 8, 8),
      child: Text(
        texto.toUpperCase(),
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.4,
          color: _TemaNav.textoMuted,
          decoration: TextDecoration.none,
        ),
      ),
    );
  }
}

// ——— Badge numérico (pendências) ———

class _BadgeContadorNav extends StatelessWidget {
  const _BadgeContadorNav(this.n);

  final int n;

  @override
  Widget build(BuildContext context) {
    final t = n > 99 ? '99+' : '$n';
    return Container(
      constraints: const BoxConstraints(minWidth: 22),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: _TemaNav.accent,
        borderRadius: BorderRadius.circular(10),
      ),
      alignment: Alignment.center,
      child: Text(
        t,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: Color(0xFF15122A),
          decoration: TextDecoration.none,
          height: 1.1,
        ),
      ),
    );
  }
}

/// Menu "Solicitações de saque" com badge alimentado por [SaquesSolicitacoesMenuContagem].
class _NavRowSaquesComContador extends StatelessWidget {
  const _NavRowSaquesComContador({
    required this.rotaAtual,
    required this.collapsed,
    required this.onTapItem,
  });

  final String rotaAtual;
  final bool collapsed;
  final void Function(BuildContext context, String rota, bool jaAtivo) onTapItem;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: SaquesSolicitacoesMenuContagem.streamPendentes,
      builder: (context, snap) {
        final n = snap.data ?? 0;
        return _NavRow(
          rota: '/financeiro_saques',
          label: 'Solicitações de saque',
          icon: Icons.outgoing_mail,
          rotaAtual: rotaAtual,
          collapsed: collapsed,
          badgeCount: n > 0 ? n : null,
          onTap: (c) => onTapItem(
            c,
            '/financeiro_saques',
            rotaAtual == '/financeiro_saques',
          ),
        );
      },
    );
  }
}

// ——— Item de navegação ———

class _NavRow extends StatelessWidget {
  const _NavRow({
    required this.rota,
    required this.label,
    required this.icon,
    required this.rotaAtual,
    required this.collapsed,
    required this.onTap,
    this.badgeCount,
  });

  final String rota;
  final String label;
  final IconData icon;
  final String rotaAtual;
  final bool collapsed;
  final void Function(BuildContext context) onTap;

  /// Pendências a mostrar ao lado do rótulo (ex.: saques a aprovar). `null` ou `0` = sem badge.
  final int? badgeCount;

  @override
  Widget build(BuildContext context) {
    final ativo = rotaAtual == rota;
    final nBadge = badgeCount;

    if (collapsed) {
      final n = nBadge ?? 0;
      final tooltipMsg = n > 0 ? '$label — $n pendente${n == 1 ? '' : 's'}' : label;
      return Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Tooltip(
          message: tooltipMsg,
          preferBelow: false,
          waitDuration: const Duration(milliseconds: 300),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => onTap(context),
              hoverColor: _TemaNav.hover,
              focusColor: Colors.transparent,
              highlightColor: Colors.transparent,
              splashColor: _TemaNav.accent.withValues(alpha: 0.12),
              child: Ink(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: ativo ? _TemaNav.ativoBg : null,
                  border: Border.all(
                    color: ativo
                        ? _TemaNav.accent.withValues(alpha: 0.45)
                        : Colors.transparent,
                    width: 1,
                  ),
                ),
                child: SizedBox(
                  height: 44,
                  child: Center(
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Icon(
                          icon,
                          size: 22,
                          color: ativo ? _TemaNav.accent : _TemaNav.textoMuted,
                        ),
                        if (n > 0)
                          Positioned(
                            right: -6,
                            top: -6,
                            child: _BadgeContadorNav(n),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => onTap(context),
          hoverColor: _TemaNav.hover,
          focusColor: Colors.transparent,
          highlightColor: Colors.transparent,
          splashColor: _TemaNav.accent.withValues(alpha: 0.12),
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: ativo ? _TemaNav.ativoBg : null,
              border: Border.all(
                color: ativo
                    ? _TemaNav.accent.withValues(alpha: 0.45)
                    : Colors.transparent,
                width: 1,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 3,
                  height: 44,
                  margin: const EdgeInsets.only(right: 10),
                  decoration: BoxDecoration(
                    color: ativo ? _TemaNav.accent : Colors.transparent,
                    borderRadius: const BorderRadius.horizontal(
                      right: Radius.circular(3),
                    ),
                  ),
                ),
                Icon(
                  icon,
                  size: 22,
                  color: ativo ? _TemaNav.accent : _TemaNav.textoMuted,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight:
                          ativo ? FontWeight.w600 : FontWeight.w500,
                      color: ativo ? _TemaNav.texto : _TemaNav.textoMuted,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
                if (nBadge != null && nBadge > 0) ...[
                  const SizedBox(width: 6),
                  _BadgeContadorNav(nBadge),
                  const SizedBox(width: 4),
                ],
                if (ativo)
                  const Padding(
                    padding: EdgeInsets.only(right: 10),
                    child: Icon(
                      Icons.chevron_right_rounded,
                      size: 20,
                      color: _TemaNav.textoMuted,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ——— Grupo expansível: Configuração (lojista nível III) ———

class _GrupoConfiguracaoLojista extends StatefulWidget {
  const _GrupoConfiguracaoLojista({
    required this.rotaAtual,
    required this.collapsed,
    required this.onTapItem,
  });

  final String rotaAtual;
  final bool collapsed;
  final void Function(BuildContext, String, bool) onTapItem;

  @override
  State<_GrupoConfiguracaoLojista> createState() =>
      _GrupoConfiguracaoLojistaState();
}

class _GrupoConfiguracaoLojistaState extends State<_GrupoConfiguracaoLojista> {
  late bool _aberto;

  static const _rotas = ['/configuracoes', '/configuracao_cadastro_acesso'];

  bool get _qualquerAtivo => _rotas.contains(widget.rotaAtual);

  @override
  void initState() {
    super.initState();
    _aberto = _qualquerAtivo;
  }

  @override
  void didUpdateWidget(_GrupoConfiguracaoLojista old) {
    super.didUpdateWidget(old);
    if (_qualquerAtivo && !_aberto) setState(() => _aberto = true);
  }

  @override
  Widget build(BuildContext context) {
    final ativo = _qualquerAtivo;

    if (widget.collapsed) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _iconColapsadoCfg(
            Icons.settings_outlined,
            '/configuracoes',
            'Dados da loja',
          ),
          _iconColapsadoCfg(
            Icons.group_add_outlined,
            '/configuracao_cadastro_acesso',
            'Cadastro de acesso',
          ),
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () {
                if (!_aberto) {
                  setState(() => _aberto = true);
                  widget.onTapItem(context, '/configuracoes', ativo);
                } else {
                  setState(() => _aberto = !_aberto);
                }
              },
              hoverColor: _TemaNav.hover,
              focusColor: Colors.transparent,
              highlightColor: Colors.transparent,
              splashColor: _TemaNav.accent.withValues(alpha: 0.12),
              child: Ink(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: ativo ? _TemaNav.ativoBg : null,
                  border: Border.all(
                    color: ativo
                        ? _TemaNav.accent.withValues(alpha: 0.45)
                        : Colors.transparent,
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 3,
                      height: 44,
                      margin: const EdgeInsets.only(right: 10),
                      decoration: BoxDecoration(
                        color: ativo ? _TemaNav.accent : Colors.transparent,
                        borderRadius: const BorderRadius.horizontal(
                          right: Radius.circular(3),
                        ),
                      ),
                    ),
                    Icon(
                      Icons.settings_outlined,
                      size: 22,
                      color: ativo ? _TemaNav.accent : _TemaNav.textoMuted,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Configuração',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight:
                              ativo ? FontWeight.w600 : FontWeight.w500,
                          color:
                              ativo ? _TemaNav.texto : _TemaNav.textoMuted,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: AnimatedRotation(
                        turns: _aberto ? 0.5 : 0,
                        duration: const Duration(milliseconds: 200),
                        child: const Icon(
                          Icons.expand_more_rounded,
                          size: 18,
                          color: _TemaNav.textoMuted,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        AnimatedCrossFade(
          duration: const Duration(milliseconds: 200),
          crossFadeState: _aberto
              ? CrossFadeState.showFirst
              : CrossFadeState.showSecond,
          firstChild: Padding(
            padding: const EdgeInsets.only(left: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _subItemCfg(
                  context,
                  rota: '/configuracoes',
                  icon: Icons.storefront_outlined,
                  label: 'Dados da loja',
                ),
                _subItemCfg(
                  context,
                  rota: '/configuracao_cadastro_acesso',
                  icon: Icons.group_add_outlined,
                  label: 'Cadastro de Acesso',
                ),
              ],
            ),
          ),
          secondChild: const SizedBox.shrink(),
        ),
      ],
    );
  }

  Widget _subItemCfg(
    BuildContext context, {
    required String rota,
    required IconData icon,
    required String label,
  }) {
    final ativo = widget.rotaAtual == rota;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => widget.onTapItem(context, rota, ativo),
          hoverColor: _TemaNav.hover,
          focusColor: Colors.transparent,
          highlightColor: Colors.transparent,
          splashColor: _TemaNav.accent.withValues(alpha: 0.1),
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: ativo ? _TemaNav.accentSoft : null,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 10,
              ),
              child: Row(
                children: [
                  Icon(
                    icon,
                    size: 18,
                    color: ativo ? _TemaNav.accent : _TemaNav.textoMuted,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight:
                            ativo ? FontWeight.w600 : FontWeight.w500,
                        color: ativo ? _TemaNav.texto : _TemaNav.textoMuted,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ),
                  if (ativo)
                    const Icon(
                      Icons.circle,
                      size: 6,
                      color: _TemaNav.accent,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _iconColapsadoCfg(IconData icon, String rota, String tooltip) {
    final ativo = widget.rotaAtual == rota;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Tooltip(
        message: tooltip,
        preferBelow: false,
        waitDuration: const Duration(milliseconds: 300),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => widget.onTapItem(context, rota, ativo),
            hoverColor: _TemaNav.hover,
            child: Ink(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: ativo ? _TemaNav.ativoBg : null,
                border: Border.all(
                  color: ativo
                      ? _TemaNav.accent.withValues(alpha: 0.45)
                      : Colors.transparent,
                ),
              ),
              child: SizedBox(
                height: 44,
                child: Center(
                  child: Icon(
                    icon,
                    size: 22,
                    color: ativo ? _TemaNav.accent : _TemaNav.textoMuted,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ——— Grupo expansível: Carteira ———

class _GrupoCarteira extends StatefulWidget {
  const _GrupoCarteira({
    required this.rotaAtual,
    required this.collapsed,
    required this.onTapItem,
  });

  final String rotaAtual;
  final bool collapsed;
  final void Function(BuildContext, String, bool) onTapItem;

  @override
  State<_GrupoCarteira> createState() => _GrupoCarteiraState();
}

class _GrupoCarteiraState extends State<_GrupoCarteira> {
  late bool _aberto;

  static const _rotas = [
    '/carteira_loja',
    '/carteira_financeiro',
    '/carteira_relatorio',
    '/carteira_configuracao',
  ];

  bool get _qualquerAtivo => _rotas.contains(widget.rotaAtual);

  @override
  void initState() {
    super.initState();
    _aberto = _qualquerAtivo;
  }

  @override
  void didUpdateWidget(_GrupoCarteira old) {
    super.didUpdateWidget(old);
    if (_qualquerAtivo && !_aberto) setState(() => _aberto = true);
  }

  @override
  Widget build(BuildContext context) {
    final ativo = _qualquerAtivo;

    if (widget.collapsed) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _iconColapsado(
            Icons.account_balance_wallet_outlined,
            '/carteira_loja',
            'Minha carteira',
          ),
          _iconColapsado(
            Icons.bar_chart_rounded,
            '/carteira_financeiro',
            'Financeiro',
          ),
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── cabeçalho do grupo ──
        Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () {
                if (!_aberto) {
                  setState(() => _aberto = true);
                  widget.onTapItem(context, '/carteira_loja', ativo);
                } else {
                  setState(() => _aberto = !_aberto);
                }
              },
              hoverColor: _TemaNav.hover,
              focusColor: Colors.transparent,
              highlightColor: Colors.transparent,
              splashColor: _TemaNav.accent.withValues(alpha: 0.12),
              child: Ink(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: ativo ? _TemaNav.ativoBg : null,
                  border: Border.all(
                    color: ativo
                        ? _TemaNav.accent.withValues(alpha: 0.45)
                        : Colors.transparent,
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 3,
                      height: 44,
                      margin: const EdgeInsets.only(right: 10),
                      decoration: BoxDecoration(
                        color: ativo ? _TemaNav.accent : Colors.transparent,
                        borderRadius: const BorderRadius.horizontal(
                          right: Radius.circular(3),
                        ),
                      ),
                    ),
                    Icon(
                      Icons.account_balance_wallet_outlined,
                      size: 22,
                      color: ativo ? _TemaNav.accent : _TemaNav.textoMuted,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Minha carteira',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight:
                              ativo ? FontWeight.w600 : FontWeight.w500,
                          color:
                              ativo ? _TemaNav.texto : _TemaNav.textoMuted,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: AnimatedRotation(
                        turns: _aberto ? 0.5 : 0,
                        duration: const Duration(milliseconds: 200),
                        child: const Icon(
                          Icons.expand_more_rounded,
                          size: 18,
                          color: _TemaNav.textoMuted,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        // ── sub-itens ──
        AnimatedCrossFade(
          duration: const Duration(milliseconds: 200),
          crossFadeState: _aberto
              ? CrossFadeState.showFirst
              : CrossFadeState.showSecond,
          firstChild: Padding(
            padding: const EdgeInsets.only(left: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _subItem(
                  context,
                  rota: '/carteira_loja',
                  icon: Icons.account_balance_wallet_rounded,
                  label: 'Visão geral',
                ),
                _subItem(
                  context,
                  rota: '/carteira_financeiro',
                  icon: Icons.bar_chart_rounded,
                  label: 'Financeiro',
                ),
              ],
            ),
          ),
          secondChild: const SizedBox.shrink(),
        ),
      ],
    );
  }

  Widget _subItem(
    BuildContext context, {
    required String rota,
    required IconData icon,
    required String label,
  }) {
    final ativo = widget.rotaAtual == rota;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => widget.onTapItem(context, rota, ativo),
          hoverColor: _TemaNav.hover,
          focusColor: Colors.transparent,
          highlightColor: Colors.transparent,
          splashColor: _TemaNav.accent.withValues(alpha: 0.1),
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: ativo ? _TemaNav.accentSoft : null,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 10,
              ),
              child: Row(
                children: [
                  Icon(
                    icon,
                    size: 18,
                    color: ativo ? _TemaNav.accent : _TemaNav.textoMuted,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight:
                            ativo ? FontWeight.w600 : FontWeight.w500,
                        color: ativo ? _TemaNav.texto : _TemaNav.textoMuted,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ),
                  if (ativo)
                    const Icon(
                      Icons.circle,
                      size: 6,
                      color: _TemaNav.accent,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _iconColapsado(IconData icon, String rota, String tooltip) {
    final ativo = widget.rotaAtual == rota;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Tooltip(
        message: tooltip,
        preferBelow: false,
        waitDuration: const Duration(milliseconds: 300),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => widget.onTapItem(context, rota, ativo),
            hoverColor: _TemaNav.hover,
            child: Ink(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: ativo ? _TemaNav.ativoBg : null,
                border: Border.all(
                  color: ativo
                      ? _TemaNav.accent.withValues(alpha: 0.45)
                      : Colors.transparent,
                ),
              ),
              child: SizedBox(
                height: 44,
                child: Center(
                  child: Icon(
                    icon,
                    size: 22,
                    color: ativo ? _TemaNav.accent : _TemaNav.textoMuted,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ——— Rodapé / sair ———

class _RodapeSair extends StatelessWidget {
  const _RodapeSair({required this.onSair, required this.collapsed});

  final Future<void> Function() onSair;
  final bool collapsed;

  @override
  Widget build(BuildContext context) {
    if (collapsed) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(0, 8, 0, 16),
        child: Tooltip(
          message: 'Sair da conta',
          preferBelow: false,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => onSair(),
              hoverColor: const Color(0x14FF5252),
              child: SizedBox(
                height: 44,
                child: Center(
                  child: Icon(
                    Icons.logout_rounded,
                    size: 22,
                    color: Colors.red.shade300,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => onSair(),
          hoverColor: const Color(0x14FF5252),
          focusColor: Colors.transparent,
          highlightColor: Colors.transparent,
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              children: [
                Icon(
                  Icons.logout_rounded,
                  size: 22,
                  color: Colors.red.shade300,
                ),
                const SizedBox(width: 12),
                Text(
                  'Sair da conta',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Colors.red.shade200,
                    decoration: TextDecoration.none,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ================================================================
// Grupo AdminCity (colapsável) — Cadastro de Usuários / Cadastro de Cidades
// ================================================================
class _GrupoAdminCity extends StatefulWidget {
  const _GrupoAdminCity({
    required this.rotaAtual,
    required this.collapsed,
    required this.onTapItem,
  });

  final String rotaAtual;
  final bool collapsed;
  final void Function(BuildContext, String, bool) onTapItem;

  @override
  State<_GrupoAdminCity> createState() => _GrupoAdminCityState();
}

class _GrupoAdminCityState extends State<_GrupoAdminCity> {
  late bool _aberto;

  static const _rotas = ['/admincity', '/admincity_cidades'];

  bool get _qualquerAtivo => _rotas.contains(widget.rotaAtual);

  @override
  void initState() {
    super.initState();
    _aberto = _qualquerAtivo;
  }

  @override
  void didUpdateWidget(_GrupoAdminCity old) {
    super.didUpdateWidget(old);
    if (_qualquerAtivo && !_aberto) setState(() => _aberto = true);
  }

  @override
  Widget build(BuildContext context) {
    final ativo = _qualquerAtivo;

    if (widget.collapsed) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _iconColapsado(
            Icons.person_add_alt_1_rounded,
            '/admincity',
            'Cadastro de Usuários',
          ),
          _iconColapsado(
            Icons.map_rounded,
            '/admincity_cidades',
            'Cadastro de Cidades',
          ),
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () {
                if (!_aberto) {
                  setState(() => _aberto = true);
                  widget.onTapItem(context, '/admincity', ativo);
                } else {
                  setState(() => _aberto = !_aberto);
                }
              },
              hoverColor: _TemaNav.hover,
              focusColor: Colors.transparent,
              highlightColor: Colors.transparent,
              splashColor: _TemaNav.accent.withValues(alpha: 0.12),
              child: Ink(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: ativo ? _TemaNav.ativoBg : null,
                  border: Border.all(
                    color: ativo
                        ? _TemaNav.accent.withValues(alpha: 0.45)
                        : Colors.transparent,
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 3,
                      height: 44,
                      margin: const EdgeInsets.only(right: 10),
                      decoration: BoxDecoration(
                        color: ativo ? _TemaNav.accent : Colors.transparent,
                        borderRadius: const BorderRadius.horizontal(
                          right: Radius.circular(3),
                        ),
                      ),
                    ),
                    Icon(
                      Icons.supervisor_account,
                      size: 22,
                      color: ativo ? _TemaNav.accent : _TemaNav.textoMuted,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'AdminCity',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight:
                              ativo ? FontWeight.w600 : FontWeight.w500,
                          color:
                              ativo ? _TemaNav.texto : _TemaNav.textoMuted,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: AnimatedRotation(
                        turns: _aberto ? 0.5 : 0,
                        duration: const Duration(milliseconds: 200),
                        child: const Icon(
                          Icons.expand_more_rounded,
                          size: 18,
                          color: _TemaNav.textoMuted,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        AnimatedCrossFade(
          duration: const Duration(milliseconds: 200),
          crossFadeState: _aberto
              ? CrossFadeState.showFirst
              : CrossFadeState.showSecond,
          firstChild: Padding(
            padding: const EdgeInsets.only(left: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _subItemAC(
                  context,
                  rota: '/admincity',
                  icon: Icons.person_add_alt_1_rounded,
                  label: 'Cadastro de Usuários',
                ),
                _subItemAC(
                  context,
                  rota: '/admincity_cidades',
                  icon: Icons.map_rounded,
                  label: 'Cadastro de Cidades',
                ),
              ],
            ),
          ),
          secondChild: const SizedBox.shrink(),
        ),
      ],
    );
  }

  Widget _subItemAC(
    BuildContext context, {
    required String rota,
    required IconData icon,
    required String label,
  }) {
    final ativo = widget.rotaAtual == rota;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => widget.onTapItem(context, rota, ativo),
          hoverColor: _TemaNav.hover,
          focusColor: Colors.transparent,
          highlightColor: Colors.transparent,
          splashColor: _TemaNav.accent.withValues(alpha: 0.1),
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: ativo ? _TemaNav.accentSoft : null,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 10,
              ),
              child: Row(
                children: [
                  Icon(
                    icon,
                    size: 18,
                    color: ativo ? _TemaNav.accent : _TemaNav.textoMuted,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight:
                            ativo ? FontWeight.w600 : FontWeight.w500,
                        color: ativo ? _TemaNav.texto : _TemaNav.textoMuted,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ),
                  if (ativo)
                    const Icon(
                      Icons.circle,
                      size: 6,
                      color: _TemaNav.accent,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _iconColapsado(IconData icon, String rota, String tooltip) {
    final ativo = widget.rotaAtual == rota;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => widget.onTapItem(context, rota, ativo),
            hoverColor: _TemaNav.hover,
            child: Container(
              width: 48,
              height: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: ativo ? _TemaNav.ativoBg : null,
                border: Border.all(
                  color: ativo
                      ? _TemaNav.accent.withValues(alpha: 0.45)
                      : Colors.transparent,
                ),
              ),
              child: Icon(
                icon,
                size: 22,
                color: ativo ? _TemaNav.accent : _TemaNav.textoMuted,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
