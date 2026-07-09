import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:depertin_web/navigation/painel_routes.dart';
import 'package:depertin_web/services/saques_solicitacoes_menu_contagem.dart';
import 'package:depertin_web/utils/admin_perfil.dart';
import 'package:depertin_web/utils/firestore_web_safe.dart';
import 'package:depertin_web/utils/lojista_painel_context.dart';
import 'package:depertin_web/models/cliente_assinatura_model.dart';
import 'package:depertin_web/services/assinatura_gestao_comercial_service.dart';
import 'package:depertin_web/services/assinatura_gestao_comercial_refresh.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:depertin_web/navigation/painel_navigation_scope.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:flutter/material.dart';

/// Menu lateral do painel DiPertin — collapsible sidebar.
///
/// Expandido: 280 px (logo + texto + itens com rótulo).
/// Colapsado : 64 px  (só ícones + tooltips).
/// Toggle    : botão "chevron" no cabeçalho, animação 280 ms easeInOutCubic.
class SidebarMenu extends StatefulWidget {
  const SidebarMenu({super.key, required this.rotaAtual, this.onNavegarPainel});

  final String rotaAtual;
  final void Function(String route)? onNavegarPainel;

  static const double largura = 280;
  static const double larguraColapsada = 64;
  static const Duration duracaoAnimacao = Duration(milliseconds: 280);
  static const Curve curvaAnimacao = Curves.easeInOutCubic;

  @override
  State<SidebarMenu> createState() => _SidebarMenuState();
}

class _SidebarMenuState extends State<SidebarMenu> {
  bool _collapsed = false;

  /// Evita layout expandido enquanto a largura ainda está animando (overflow).
  bool _conteudoExpandido = true;

  bool get _layoutCompacto => _collapsed || !_conteudoExpandido;

  void _toggleColapso() {
    if (_collapsed) {
      setState(() {
        _collapsed = false;
        _conteudoExpandido = false;
      });
      Future.delayed(SidebarMenu.duracaoAnimacao, () {
        if (mounted && !_collapsed) {
          setState(() => _conteudoExpandido = true);
        }
      });
      return;
    }

    setState(() => _conteudoExpandido = false);
    Future.delayed(const Duration(milliseconds: 90), () {
      if (mounted && !_conteudoExpandido) {
        setState(() => _collapsed = true);
      }
    });
  }

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
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .snapshots(),
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
        final int? nivelPainel = lojista
            ? nivelAcessoPainelLojista(dados)
            : null;

        if (!lojista) {
          return _SidebarNovo(
            perfil: perfil,
            nivelPainelLojista: nivelPainel,
            nomeLoja: null,
            rotaAtual: widget.rotaAtual,
            collapsed: _collapsed,
            conteudoCompacto: _layoutCompacto,
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
              conteudoCompacto: _layoutCompacto,
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
      duration: SidebarMenu.duracaoAnimacao,
      curve: SidebarMenu.curvaAnimacao,
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
  // Fundo - Roxo vibrante (igual ao app mobile)
  static const Color fundoTopo = Color(0xFF6A1B9A); // roxo principal (topo)
  static const Color fundoBase = Color(0xFF4A148C); // roxo profundo (base do gradiente)
  static const Color fundo = Color(0xFF6A1B9A); // compat: usos como cor sólida
  static const Color fundoElevado = Color(0x24FFFFFF); // cartão "vidro" sobre o roxo
  static const Color borda = Color(0x33FFFFFF); // separadores translúcidos

  // Texto
  static const Color texto = Color(0xFFFFFFFF);
  static const Color textoMuted = Color(0xFFE6D6F7); // lilás claro legível no roxo

  // Accent - Laranja (mesmo do app mobile)
  static const Color accent = Color(0xFFFF8F00);
  static const Color accentSoft = Color(0x33FFB74D); // laranja suave

  // Cor ativa - destaque claro que "salta" sobre o roxo vibrante
  static const Color ativoCor = Color(0xFFFFFFFF);

  // Interações
  static const Color hover = Color(0x1FFFFFFF);
  static const Color ativoBg = Color(0x2BFFFFFF);

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
    required this.conteudoCompacto,
    required this.onToggleColapso,
    required this.onTapItem,
  });

  final String perfil;

  /// `null` se não for lojista (master/staff). 1–3 para colaboradores/dono.
  final int? nivelPainelLojista;

  /// Nome comercial da loja (doc. do dono: `loja_nome` ou `nome`). Só lojista.
  final String? nomeLoja;
  final String rotaAtual;

  /// Largura animada do sidebar (estado do toggle).
  final bool collapsed;

  /// Layout compacto (ícones) — pode permanecer true durante a animação de abertura.
  final bool conteudoCompacto;
  final VoidCallback onToggleColapso;
  final void Function(BuildContext context, String rota, bool jaAtivo)
  onTapItem;

  @override
  Widget build(BuildContext context) {
    final compacto = conteudoCompacto;
    final podeGestao = perfilPodeGestaoLojasEntregadoresBanners(perfil);
    final podeChefe = perfilPodeMenuChefe(perfil);
    final podeClientes = perfilPodeCentralClientes(perfil);
    final lojista = perfil == 'lojista';
    final n = nivelPainelLojista;
    final showMeuCardapio = n == null || n >= 2;
    final showCarteiraEConfig = n == null || n >= 3;

    final itens = <Widget>[];

    if (!lojista) {
      itens.add(_SecaoLabel('Principal', collapsed: compacto));
    }
    itens.add(
      _NavRow(
        rota: '/dashboard',
        label: 'Dashboard',
        icon: Icons.dashboard,
        rotaAtual: rotaAtual,
        collapsed: compacto,
        onTap: (c) => onTapItem(c, '/dashboard', rotaAtual == '/dashboard'),
      ),
    );

    if (podeGestao) {
      itens.add(_SecaoLabel('Operação', collapsed: compacto));
      itens.addAll([
        _GrupoLojasPainel(
          rotaAtual: rotaAtual,
          collapsed: compacto,
          onTapItem: onTapItem,
        ),
        _NavRow(
          rota: '/entregadores',
          label: 'Entregadores',
          icon: Icons.local_shipping,
          rotaAtual: rotaAtual,
          collapsed: compacto,
          onTap: (c) =>
              onTapItem(c, '/entregadores', rotaAtual == '/entregadores'),
        ),
        if (podeClientes)
          _NavRow(
            rota: '/clientes',
            label: 'Central de clientes',
            icon: Icons.people_alt_rounded,
            rotaAtual: rotaAtual,
            collapsed: compacto,
            onTap: (c) => onTapItem(c, '/clientes', rotaAtual == '/clientes'),
          ),
        _NavRow(
          rota: '/monitor_pedidos',
          label: 'Monitor de pedidos',
          icon: Icons.receipt,
          rotaAtual: rotaAtual,
          collapsed: compacto,
          onTap: (c) =>
              onTapItem(c, '/monitor_pedidos', rotaAtual == '/monitor_pedidos'),
        ),
        _GrupoCentroOperacoesPainel(
          rotaAtual: rotaAtual,
          collapsed: compacto,
          onTapItem: onTapItem,
        ),
        _NavRow(
          rota: '/avaliacoes_painel',
          label: 'Avaliações',
          icon: Icons.star,
          rotaAtual: rotaAtual,
          collapsed: compacto,
          onTap: (c) => onTapItem(
            c,
            '/avaliacoes_painel',
            rotaAtual == '/avaliacoes_painel',
          ),
        ),
        _NavRow(
          rota: '/banners',
          label: 'Banners da vitrine',
          icon: Icons.photo,
          rotaAtual: rotaAtual,
          collapsed: compacto,
          onTap: (c) => onTapItem(c, '/banners', rotaAtual == '/banners'),
        ),
        _NavRow(
          rota: '/categorias',
          label: 'Categorias',
          icon: Icons.category_rounded,
          rotaAtual: rotaAtual,
          collapsed: compacto,
          onTap: (c) => onTapItem(c, '/categorias', rotaAtual == '/categorias'),
        ),
      ]);
    }

    if (lojista) {
      itens.addAll([
        _GrupoGestaoComercial(
          rotaAtual: rotaAtual,
          collapsed: compacto,
          onTapItem: onTapItem,
        ),
        _NavRow(
          rota: '/meus_pedidos',
          label: 'Meus pedidos',
          icon: Icons.receipt,
          rotaAtual: rotaAtual,
          collapsed: compacto,
          onTap: (c) =>
              onTapItem(c, '/meus_pedidos', rotaAtual == '/meus_pedidos'),
        ),
        _NavRow(
          rota: '/negociacoes_encomenda',
          label: 'Negociações de encomenda',
          icon: Icons.handshake_outlined,
          rotaAtual: rotaAtual,
          collapsed: compacto,
          onTap: (c) => onTapItem(
            c,
            '/negociacoes_encomenda',
            rotaAtual == '/negociacoes_encomenda',
          ),
        ),
        if (showMeuCardapio)
          _NavRow(
            rota: '/meu_cardapio',
            label: 'Meus produtos',
            icon: Icons.inventory_2_outlined,
            rotaAtual: rotaAtual,
            collapsed: compacto,
            onTap: (c) =>
                onTapItem(c, '/meu_cardapio', rotaAtual == '/meu_cardapio'),
          ),
        if (showMeuCardapio)
          _NavRow(
            rota: '/meus_cupons',
            label: 'Cupons & promoções',
            icon: Icons.local_offer_outlined,
            rotaAtual: rotaAtual,
            collapsed: compacto,
            onTap: (c) =>
                onTapItem(c, '/meus_cupons', rotaAtual == '/meus_cupons'),
          ),
        if (showCarteiraEConfig)
          _GrupoCarteira(
            rotaAtual: rotaAtual,
            collapsed: compacto,
            onTapItem: onTapItem,
          ),
      ]);
    }

    // Gestão (master / superadmin): inclui fila de saques — só este perfil vê "Solicitações de saque".
    if (podeChefe) {
      itens.add(_SecaoLabel('Gestão', collapsed: compacto));
      itens.addAll([
        _GrupoAdminCity(
          rotaAtual: rotaAtual,
          collapsed: compacto,
          onTapItem: onTapItem,
        ),
        _GrupoAssinaturas(
          rotaAtual: rotaAtual,
          collapsed: compacto,
          onTapItem: onTapItem,
        ),
        _NavRow(
          rota: '/utilidades',
          label: 'Anúncios e utilidades',
          icon: Icons.campaign,
          rotaAtual: rotaAtual,
          collapsed: compacto,
          onTap: (c) => onTapItem(c, '/utilidades', rotaAtual == '/utilidades'),
        ),
        _NavRow(
          rota: '/financeiro',
          label: 'Financeiro geral',
          icon: Icons.menu_book_outlined,
          rotaAtual: rotaAtual,
          collapsed: compacto,
          onTap: (c) => onTapItem(c, '/financeiro', rotaAtual == '/financeiro'),
        ),
        _NavRowSaquesComContador(
          rotaAtual: rotaAtual,
          collapsed: compacto,
          onTapItem: onTapItem,
        ),
      ]);
    }

    if (podeGestao || podeChefe) {
      itens.add(_SecaoLabel('Marketing', collapsed: compacto));
      itens.addAll([
        _NavRow(
          rota: '/notificacoes',
          label: 'Notificações push',
          icon: Icons.notifications,
          rotaAtual: rotaAtual,
          collapsed: compacto,
          onTap: (c) =>
              onTapItem(c, '/notificacoes', rotaAtual == '/notificacoes'),
        ),
        _NavRow(
          rota: '/cupons',
          label: 'Cupons e promoções',
          icon: Icons.local_offer,
          rotaAtual: rotaAtual,
          collapsed: compacto,
          onTap: (c) => onTapItem(c, '/cupons', rotaAtual == '/cupons'),
        ),
        _NavRow(
          rota: '/comunicados',
          label: 'Comunicados',
          icon: Icons.message,
          rotaAtual: rotaAtual,
          collapsed: compacto,
          onTap: (c) =>
              onTapItem(c, '/comunicados', rotaAtual == '/comunicados'),
        ),
      ]);
    }

    if (showCarteiraEConfig || !lojista) {
      itens.add(_SecaoLabel('Sistema', collapsed: compacto));
      if (lojista && showCarteiraEConfig) {
        itens.add(
          _GrupoConfiguracaoLojista(
            rotaAtual: rotaAtual,
            collapsed: compacto,
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
            collapsed: compacto,
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
          collapsed: compacto,
          onTap: (c) => onTapItem(
            c,
            '/atendimento_suporte',
            rotaAtual == '/atendimento_suporte',
          ),
        ),
        _NavRow(
          rota: '/conteudo_legal',
          label: 'Conteúdo legal',
          icon: Icons.description,
          rotaAtual: rotaAtual,
          collapsed: compacto,
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
          duration: SidebarMenu.duracaoAnimacao,
          curve: SidebarMenu.curvaAnimacao,
          width: collapsed ? SidebarMenu.larguraColapsada : SidebarMenu.largura,
          height: h,
          clipBehavior: Clip.hardEdge,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [_TemaNav.fundoTopo, _TemaNav.fundoBase],
            ),
            border: Border(right: BorderSide(color: _TemaNav.borda, width: 1)),
          ),
          child: LayoutBuilder(
            builder: (context, inner) {
              final layoutCompacto = compacto ||
                  inner.maxWidth < SidebarMenu.larguraColapsada + 48;

              return DefaultTextStyle.merge(
                style: _TemaNav.semSublinhado,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _TopoMarca(
                      perfil: perfil,
                      nomeLoja: nomeLoja,
                      collapsed: layoutCompacto,
                      menuRecolhido: collapsed,
                      onToggle: onToggleColapso,
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: EdgeInsets.fromLTRB(
                          layoutCompacto ? 6 : 12,
                          8,
                          layoutCompacto ? 6 : 12,
                          16,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: itens,
                        ),
                      ),
                    ),
                    const Divider(height: 1, thickness: 1, color: _TemaNav.borda),
                    if (lojista) _SeccaoPlano(collapsed: layoutCompacto),
                    _RodapeUsuario(
                      perfil: perfil,
                      collapsed: layoutCompacto,
                      nomeLoja: lojista ? nomeLoja : null,
                    ),
                    _RodapeSair(
                      collapsed: layoutCompacto,
                      onSair: () async {
                    final confirmar = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        title: Row(
                          children: [
                            Icon(
                              Icons.logout_rounded,
                              color: Colors.red.shade400,
                              size: 24,
                            ),
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
          );
            },
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
    required this.menuRecolhido,
    required this.onToggle,
  });

  final String perfil;

  /// Exibido abaixo do badge (ex.: LOJISTA) quando for lojista.
  final String? nomeLoja;

  /// Layout compacto (logo + ícones).
  final bool collapsed;

  /// Estado real do toggle (ícone chevron).
  final bool menuRecolhido;
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
            gradient: LinearGradient(
              colors: [const Color(0xFF4A148C), const Color(0xFF6A1B9A)],
            ),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(
            Icons.hub_outlined,
            color: _TemaNav.accent,
            size: 22,
          ),
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
            _BotaoColapso(collapsed: menuRecolhido, onToggle: onToggle),
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
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: _TemaNav.accent.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: _TemaNav.accent.withValues(alpha: 0.38),
                          ),
                        ),
                        child: Text(
                          _badge,
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.3,
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
            child: _BotaoColapso(collapsed: menuRecolhido, onToggle: onToggle),
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
  final void Function(BuildContext context, String rota, bool jaAtivo)
  onTapItem;

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
      final tooltipMsg = n > 0
          ? '$label — $n pendente${n == 1 ? '' : 's'}'
          : label;
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
                  gradient: ativo
                      ? LinearGradient(
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                          colors: [
                            _TemaNav.ativoCor.withValues(alpha: 0.4),
                            _TemaNav.ativoCor.withValues(alpha: 0.15),
                          ],
                          stops: const [0.0, 1.0],
                        )
                      : null,
                  border: Border.all(
                    color: ativo
                        ? _TemaNav.ativoCor.withValues(alpha: 0.5)
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
                          color: ativo ? _TemaNav.ativoCor : _TemaNav.textoMuted,
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
              gradient: ativo
                  ? LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        _TemaNav.accent.withValues(alpha: 0.24),
                        _TemaNav.ativoBg,
                      ],
                      stops: const [0.0, 0.42],
                    )
                  : null,
              border: Border.all(
                color: ativo
                    ? _TemaNav.accent.withValues(alpha: 0.4)
                    : Colors.transparent,
                width: 1,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 4,
                  height: 44,
                  margin: const EdgeInsets.only(right: 10),
                  decoration: BoxDecoration(
                    gradient: ativo
                        ? LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              _TemaNav.ativoCor,
                              _TemaNav.ativoCor.withValues(alpha: 0.6),
                            ],
                          )
                        : null,
                    color: ativo ? null : Colors.transparent,
                    borderRadius: const BorderRadius.horizontal(
                      right: Radius.circular(4),
                    ),
                  ),
                ),
                Icon(
                  icon,
                  size: 22,
                  color: ativo ? _TemaNav.ativoCor : _TemaNav.textoMuted,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: ativo ? FontWeight.w600 : FontWeight.w500,
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

// ——— Grupo expansível: Lojas (admin) ———

class _GrupoLojasPainel extends StatefulWidget {
  const _GrupoLojasPainel({
    required this.rotaAtual,
    required this.collapsed,
    required this.onTapItem,
  });

  final String rotaAtual;
  final bool collapsed;
  final void Function(BuildContext, String, bool) onTapItem;

  @override
  State<_GrupoLojasPainel> createState() => _GrupoLojasPainelState();
}

class _GrupoLojasPainelState extends State<_GrupoLojasPainel> {
  late bool _aberto;

  static const _rotas = ['/lojas', '/lojas_financeiro'];

  bool get _qualquerAtivo => _rotas.contains(widget.rotaAtual);

  @override
  void initState() {
    super.initState();
    _aberto = _qualquerAtivo;
  }

  @override
  void didUpdateWidget(_GrupoLojasPainel old) {
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
          _iconColapsado(Icons.store_outlined, '/lojas', 'Gestão de lojas'),
          _iconColapsado(
            Icons.account_balance_wallet_outlined,
            '/lojas_financeiro',
            'Financeiro das Lojas',
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
                  widget.onTapItem(context, '/lojas', ativo);
                } else {
                  setState(() => _aberto = !_aberto);
                }
              },
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
                      Icons.store_outlined,
                      size: 22,
                      color: ativo ? _TemaNav.ativoCor : _TemaNav.textoMuted,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Lojas',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: ativo ? FontWeight.w600 : FontWeight.w500,
                          color: ativo ? _TemaNav.texto : _TemaNav.textoMuted,
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
                _subItemLoja(
                  context,
                  rota: '/lojas',
                  icon: Icons.store_mall_directory_outlined,
                  label: 'Gestão de lojas',
                ),
                _subItemLoja(
                  context,
                  rota: '/lojas_financeiro',
                  icon: Icons.account_balance_wallet_outlined,
                  label: 'Financeiro das Lojas',
                ),
              ],
            ),
          ),
          secondChild: const SizedBox.shrink(),
        ),
      ],
    );
  }

  Widget _subItemLoja(
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
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: ativo ? _TemaNav.accentSoft : null,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              child: Row(
                children: [
                  Icon(
                    icon,
                    size: 18,
                    color: ativo ? _TemaNav.ativoCor : _TemaNav.textoMuted,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: ativo ? FontWeight.w600 : FontWeight.w500,
                        color: ativo ? _TemaNav.texto : _TemaNav.textoMuted,
                      ),
                    ),
                  ),
                  if (ativo)
                    const Icon(Icons.circle, size: 6, color: _TemaNav.accent),
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
              ),
              child: SizedBox(
                height: 44,
                width: double.infinity,
                child: Icon(
                  icon,
                  size: 22,
                  color: ativo ? _TemaNav.ativoCor : _TemaNav.textoMuted,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ——— Grupo expansível: Centro de operações (staff) ———

class _GrupoCentroOperacoesPainel extends StatefulWidget {
  const _GrupoCentroOperacoesPainel({
    required this.rotaAtual,
    required this.collapsed,
    required this.onTapItem,
  });

  final String rotaAtual;
  final bool collapsed;
  final void Function(BuildContext, String, bool) onTapItem;

  @override
  State<_GrupoCentroOperacoesPainel> createState() =>
      _GrupoCentroOperacoesPainelState();
}

class _GrupoCentroOperacoesPainelState extends State<_GrupoCentroOperacoesPainel> {
  late bool _aberto;

  static const _rotas = PainelRoutes.centroOperacoesRotas;

  bool get _qualquerAtivo => _rotas.contains(widget.rotaAtual);

  @override
  void initState() {
    super.initState();
    _aberto = _qualquerAtivo;
  }

  @override
  void didUpdateWidget(_GrupoCentroOperacoesPainel old) {
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
            Icons.auto_graph_rounded,
            '/centro_operacoes_crm',
            'CRM & campanhas',
          ),
          _iconColapsado(
            Icons.insights_rounded,
            '/centro_operacoes_marketing',
            'Painel de Marketing',
          ),
          _iconColapsado(
            Icons.storefront_rounded,
            '/centro_operacoes_leads_lojistas',
            'Leads de lojistas',
          ),
          _iconColapsado(
            Icons.delivery_dining_rounded,
            '/centro_operacoes_leads_entregadores',
            'Leads de entregadores',
          ),
          _iconColapsado(
            Icons.calendar_month_rounded,
            '/centro_operacoes_agenda',
            'Agenda',
          ),
          _iconColapsado(
            Icons.calculate_outlined,
            '/centro_operacoes_frete',
            'Simulador de frete',
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
                  widget.onTapItem(
                    context,
                    '/centro_operacoes_crm',
                    ativo,
                  );
                } else {
                  setState(() => _aberto = !_aberto);
                }
              },
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
                      Icons.hub_outlined,
                      size: 22,
                      color: ativo ? _TemaNav.ativoCor : _TemaNav.textoMuted,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Centro de operações',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: ativo ? FontWeight.w600 : FontWeight.w500,
                          color: ativo ? _TemaNav.texto : _TemaNav.textoMuted,
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
                _subItem(
                  rota: '/centro_operacoes_crm',
                  icon: Icons.auto_graph_rounded,
                  label: 'CRM & campanhas',
                ),
                _subItem(
                  rota: '/centro_operacoes_marketing',
                  icon: Icons.insights_rounded,
                  label: 'Painel de Marketing',
                ),
                _subItem(
                  rota: '/centro_operacoes_leads_lojistas',
                  icon: Icons.storefront_rounded,
                  label: 'Leads de lojistas',
                ),
                _subItem(
                  rota: '/centro_operacoes_leads_entregadores',
                  icon: Icons.delivery_dining_rounded,
                  label: 'Leads de entregadores',
                ),
                _subItem(
                  rota: '/centro_operacoes_agenda',
                  icon: Icons.calendar_month_rounded,
                  label: 'Agenda',
                ),
                _subItem(
                  rota: '/centro_operacoes_frete',
                  icon: Icons.calculate_outlined,
                  label: 'Simulador de frete',
                ),
              ],
            ),
          ),
          secondChild: const SizedBox.shrink(),
        ),
      ],
    );
  }

  Widget _subItem({
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
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: ativo ? _TemaNav.accentSoft : null,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              child: Row(
                children: [
                  Icon(
                    icon,
                    size: 18,
                    color: ativo ? _TemaNav.ativoCor : _TemaNav.textoMuted,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: ativo ? FontWeight.w600 : FontWeight.w500,
                        color: ativo ? _TemaNav.texto : _TemaNav.textoMuted,
                      ),
                    ),
                  ),
                  if (ativo)
                    const Icon(Icons.circle, size: 6, color: _TemaNav.accent),
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
              ),
              child: SizedBox(
                height: 44,
                width: double.infinity,
                child: Icon(
                  icon,
                  size: 22,
                  color: ativo ? _TemaNav.ativoCor : _TemaNav.textoMuted,
                ),
              ),
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
                      color: ativo ? _TemaNav.ativoCor : _TemaNav.textoMuted,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Configuração',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: ativo ? FontWeight.w600 : FontWeight.w500,
                          color: ativo ? _TemaNav.texto : _TemaNav.textoMuted,
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
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              child: Row(
                children: [
                  Icon(
                    icon,
                    size: 18,
                    color: ativo ? _TemaNav.ativoCor : _TemaNav.textoMuted,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: ativo ? FontWeight.w600 : FontWeight.w500,
                        color: ativo ? _TemaNav.texto : _TemaNav.textoMuted,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ),
                  if (ativo)
                    const Icon(Icons.circle, size: 6, color: _TemaNav.accent),
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
                    color: ativo ? _TemaNav.ativoCor : _TemaNav.textoMuted,
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

// ——— Grupo expansível: Gestão Comercial ———

class _GrupoGestaoComercial extends StatefulWidget {
  const _GrupoGestaoComercial({
    required this.rotaAtual,
    required this.collapsed,
    required this.onTapItem,
  });

  final String rotaAtual;
  final bool collapsed;
  final void Function(BuildContext, String, bool) onTapItem;

  @override
  State<_GrupoGestaoComercial> createState() => _GrupoGestaoComercialState();
}

class _GrupoGestaoComercialState extends State<_GrupoGestaoComercial> {
  late bool _aberto;
  late bool _abertoFinanceiro;
  bool _temPlano = false;
  bool _suspensoAdmin = false;
  bool _carregandoPlano = true;

  static const _rotas = [
    '/comercial_dashboard',
    '/minha_loja',
    '/pdv',
    '/comercial_clientes',
    '/comercial_credito',
    '/comercial_pendencias',
    '/comercial_recebimentos',
    '/comercial_historico',
    '/comercial_relatorios',
    '/comercial_configuracoes',
    '/modulo_fiscal',
  ];

  static const _rotasFinanceiro = [
    '/comercial_credito',
    '/comercial_pendencias',
    '/comercial_recebimentos',
    '/comercial_historico',
    '/comercial_relatorios',
  ];

  bool get _qualquerAtivo => _rotas.contains(widget.rotaAtual);
  bool get _qualquerAtivoFinanceiro =>
      _rotasFinanceiro.contains(widget.rotaAtual);

  /// A rota `/comercial_dashboard` sempre existe (é a tela de upsell).
  /// As demais rotas (submenus) só existem se tiver plano.
  bool get _temSubmenus => _temPlano;

  @override
  void initState() {
    super.initState();
    _aberto = _qualquerAtivo;
    _abertoFinanceiro = _qualquerAtivoFinanceiro;
    AssinaturaGestaoComercialRefresh.instance.addListener(_onPlanoAtualizado);
    _verificarPlano();
  }

  @override
  void dispose() {
    AssinaturaGestaoComercialRefresh.instance.removeListener(_onPlanoAtualizado);
    super.dispose();
  }

  void _onPlanoAtualizado() {
    _verificarPlano();
  }

  @override
  void didUpdateWidget(_GrupoGestaoComercial old) {
    super.didUpdateWidget(old);
    if (_qualquerAtivo && !_aberto) setState(() => _aberto = true);
    if (_qualquerAtivoFinanceiro && !_abertoFinanceiro) {
      setState(() => _abertoFinanceiro = true);
    }
    // Re-verifica se o uid mudou (ex.: recarregou o painel)
    _verificarPlano();
  }

  Future<void> _verificarPlano() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    try {
      final subSnap = await FirebaseFirestore.instance
          .collection('assinaturas_clientes')
          .where('store_id', isEqualTo: uid)
          .get();

      if (subSnap.docs.isEmpty) {
        if (mounted) {
          setState(() {
            _temPlano = false;
            _suspensoAdmin = false;
            _carregandoPlano = false;
          });
        }
        return;
      }

      final ctx = await AssinaturaGestaoComercialService.carregarContexto();

      bool tem = false;
      bool suspensoAdmin = false;
      for (final doc in subSnap.docs) {
        final assinatura = ClienteAssinaturaModel.fromFirestore(doc);
        if (!AssinaturaGestaoComercialService.assinaturaEhGestaoComercial(
          assinatura,
          ctx,
        )) {
          continue;
        }
        if (AssinaturaGestaoComercialService.assinaturaBloqueadaPeloAdmin(
          assinatura,
        )) {
          suspensoAdmin = true;
          continue;
        }
        if (AssinaturaGestaoComercialService.assinaturaTemAcessoGestao(
          assinatura,
        )) {
          tem = true;
          break;
        }
      }

      if (mounted) {
        setState(() {
          _temPlano = tem;
          _suspensoAdmin = suspensoAdmin;
          _carregandoPlano = false;
        });
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[Sidebar] erro verificar plano: $e');
      if (mounted) setState(() { _temPlano = false; _carregandoPlano = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ativo = _qualquerAtivo;

    if (widget.collapsed) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _iconColapsado(
            Icons.dashboard_rounded,
            '/comercial_dashboard',
            'Dashboard Comercial',
          ),
          _iconColapsado(
            Icons.store_rounded,
            '/minha_loja',
            'Minha Loja',
          ),
          if (_temSubmenus) ...[
            _iconColapsado(
              Icons.point_of_sale_rounded,
              '/pdv',
              'Frente de Caixa (PDV)',
            ),
            _iconColapsado(
              Icons.people_alt_rounded,
              '/comercial_clientes',
              'Clientes',
            ),
            _iconColapsado(
              Icons.receipt_long_rounded,
              '/modulo_fiscal',
              'Módulo Fiscal',
            ),
            _iconColapsado(
              Icons.account_balance_rounded,
              '/comercial_credito',
              'Financeiro',
            ),
            _iconColapsado(
              Icons.settings_outlined,
              '/comercial_configuracoes',
              'Configurações Comerciais',
            ),
          ],
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
                  widget.onTapItem(context, '/comercial_dashboard', ativo);
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
                      Icons.business_center_outlined,
                      size: 22,
                      color: ativo ? _TemaNav.ativoCor : _TemaNav.textoMuted,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Gestão Comercial',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: ativo ? FontWeight.w600 : FontWeight.w500,
                          color: ativo ? _TemaNav.texto : _TemaNav.textoMuted,
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
                  rota: '/comercial_dashboard',
                  icon: Icons.dashboard_rounded,
                  label: 'Dashboard Comercial',
                ),
                _subItem(
                  context,
                  rota: '/minha_loja',
                  icon: Icons.store_rounded,
                  label: 'Minha Loja',
                ),
                if (_temSubmenus) ...[
                  _subItem(
                    context,
                    rota: '/pdv',
                    icon: Icons.point_of_sale_rounded,
                    label: 'PDV',
                  ),
                  _subItem(
                    context,
                    rota: '/comercial_clientes',
                    icon: Icons.people_alt_rounded,
                    label: 'Cadastro de Clientes',
                  ),
                  _subItem(
                    context,
                    rota: '/modulo_fiscal',
                    icon: Icons.receipt_long_rounded,
                    label: 'Módulo Fiscal',
                  ),
                  // ── sub-accordion Financeiro ──
                  _buildFinanceiroSubAccordion(),
                  _subItem(
                    context,
                    rota: '/comercial_configuracoes',
                    icon: Icons.settings_outlined,
                    label: 'Configurações Comerciais',
                  ),
                ],
                if (!_temSubmenus && !_carregandoPlano && !_suspensoAdmin)
                  _buildSemPlanoMensagem(),
                if (_suspensoAdmin && !_carregandoPlano)
                  _buildSuspensoAdminMensagem(),
              ],
            ),
          ),
          secondChild: const SizedBox.shrink(),
        ),
      ],
    );
  }

  Widget _buildSemPlanoMensagem() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _TemaNav.ativoBg.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: _TemaNav.accent.withValues(alpha: 0.2),
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.lock_outline_rounded,
              size: 16,
              color: _TemaNav.accent.withValues(alpha: 0.7),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Contrate um plano para desbloquear',
                style: TextStyle(
                  fontSize: 11,
                  color: _TemaNav.textoMuted.withValues(alpha: 0.8),
                  decoration: TextDecoration.none,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSuspensoAdminMensagem() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => widget.onTapItem(
            context,
            '/comercial_dashboard',
            widget.rotaAtual == '/comercial_dashboard',
          ),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF2F2).withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: const Color(0xFFF04438).withValues(alpha: 0.25),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.admin_panel_settings_outlined,
                  size: 16,
                  color: const Color(0xFFF04438).withValues(alpha: 0.85),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Acesso suspenso pela equipe — toque para ver detalhes',
                    style: TextStyle(
                      fontSize: 11,
                      color: _TemaNav.textoMuted.withValues(alpha: 0.9),
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFinanceiroSubAccordion() {
    final ativoFinanceiro = _qualquerAtivoFinanceiro;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () {
                if (!_abertoFinanceiro) {
                  setState(() => _abertoFinanceiro = true);
                  widget.onTapItem(
                    context,
                    '/comercial_credito',
                    widget.rotaAtual == '/comercial_credito',
                  );
                } else {
                  setState(() => _abertoFinanceiro = !_abertoFinanceiro);
                }
              },
              hoverColor: _TemaNav.hover,
              focusColor: Colors.transparent,
              highlightColor: Colors.transparent,
              splashColor: _TemaNav.accent.withValues(alpha: 0.10),
              child: Ink(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: ativoFinanceiro ? _TemaNav.accentSoft : null,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 10,
                    horizontal: 12,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.account_balance_rounded,
                        size: 18,
                        color: ativoFinanceiro
                            ? _TemaNav.ativoCor
                            : _TemaNav.textoMuted,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Financeiro',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: ativoFinanceiro
                                ? FontWeight.w600
                                : FontWeight.w500,
                            color: ativoFinanceiro
                                ? _TemaNav.texto
                                : _TemaNav.textoMuted,
                          ),
                        ),
                      ),
                      AnimatedRotation(
                        turns: _abertoFinanceiro ? 0.5 : 0,
                        duration: const Duration(milliseconds: 200),
                        child: const Icon(
                          Icons.expand_more_rounded,
                          size: 16,
                          color: _TemaNav.textoMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        AnimatedCrossFade(
          duration: const Duration(milliseconds: 200),
          crossFadeState: _abertoFinanceiro
              ? CrossFadeState.showFirst
              : CrossFadeState.showSecond,
          firstChild: Padding(
            padding: const EdgeInsets.only(left: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _subItem(
                  context,
                  rota: '/comercial_credito',
                  icon: Icons.credit_card_rounded,
                  label: 'Crédito de Cliente',
                  badge: 'Novo',
                ),
                _subItem(
                  context,
                  rota: '/comercial_pendencias',
                  icon: Icons.warning_amber_rounded,
                  label: 'Pendência Financeira',
                ),
                _subItem(
                  context,
                  rota: '/comercial_recebimentos',
                  icon: Icons.payments_rounded,
                  label: 'Recebimentos',
                ),
                _subItem(
                  context,
                  rota: '/comercial_historico',
                  icon: Icons.history_rounded,
                  label: 'Histórico de Vendas',
                ),
                _subItem(
                  context,
                  rota: '/comercial_relatorios',
                  icon: Icons.analytics_rounded,
                  label: 'Relatório Comercial',
                ),
              ],
            ),
          ),
          secondChild: const SizedBox.shrink(),
        ),
      ],
    );
  }

  Widget _iconColapsado(IconData icon, String rota, String tooltip) {
    final ativo = widget.rotaAtual == rota;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => widget.onTapItem(context, rota, ativo),
          child: Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            child: Icon(
              icon,
              color: ativo ? _TemaNav.ativoCor : _TemaNav.textoMuted,
              size: 22,
            ),
          ),
        ),
      ),
    );
  }

  Widget _subItem(
    BuildContext context, {
    required String rota,
    required IconData icon,
    required String label,
    bool enabled = true,
    String? badge,
  }) {
    final ativo = widget.rotaAtual == rota;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: enabled ? () => widget.onTapItem(context, rota, ativo) : null,
          hoverColor: enabled ? _TemaNav.hover : Colors.transparent,
          child: Ink(
            height: 38,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: (enabled && ativo) ? _TemaNav.ativoBg : null,
            ),
            child: Row(
              children: [
                const SizedBox(width: 12),
                Icon(
                  icon,
                  size: 18,
                  color: (enabled && ativo) ? _TemaNav.ativoCor : _TemaNav.textoMuted.withOpacity(enabled ? 1.0 : 0.6),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: (enabled && ativo) ? FontWeight.w600 : FontWeight.w500,
                      color: (enabled && ativo) ? _TemaNav.texto : _TemaNav.textoMuted.withOpacity(enabled ? 1.0 : 0.7),
                    ),
                  ),
                ),
                if (badge != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: _TemaNav.accent.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        badge,
                        style: const TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: _TemaNav.accent,
                        ),
                      ),
                    ),
                  )
                else if (!enabled)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.grey.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'Breve',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: _TemaNav.textoMuted.withOpacity(0.6),
                        ),
                      ),
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

// ——— Grupo expansível: Gestão de Assinaturas ———

class _GrupoAssinaturas extends StatefulWidget {
  const _GrupoAssinaturas({
    required this.rotaAtual,
    required this.collapsed,
    required this.onTapItem,
  });

  final String rotaAtual;
  final bool collapsed;
  final void Function(BuildContext, String, bool) onTapItem;

  @override
  State<_GrupoAssinaturas> createState() => _GrupoAssinaturasState();
}

class _GrupoAssinaturasState extends State<_GrupoAssinaturas> {
  late bool _aberto;

  static const _rotas = PainelRoutes.assinaturasRotas;

  bool get _qualquerAtivo => _rotas.contains(widget.rotaAtual);

  @override
  void initState() {
    super.initState();
    _aberto = _qualquerAtivo;
  }

  @override
  void didUpdateWidget(_GrupoAssinaturas old) {
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
            Icons.card_membership_outlined,
            '/assinaturas_dashboard',
            'Assinaturas',
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
                  widget.onTapItem(
                    context,
                    '/assinaturas_dashboard',
                    ativo,
                  );
                } else {
                  setState(() => _aberto = !_aberto);
                }
              },
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
                      Icons.card_membership_outlined,
                      size: 22,
                      color: ativo ? _TemaNav.ativoCor : _TemaNav.textoMuted,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Gestão de Assinaturas',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: ativo ? FontWeight.w600 : FontWeight.w500,
                          color: ativo ? _TemaNav.texto : _TemaNav.textoMuted,
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
                _subItem(
                  rota: '/assinaturas_dashboard',
                  icon: Icons.dashboard_rounded,
                  label: 'Dashboard de Assinaturas',
                ),
                _subItem(
                  rota: '/assinaturas_clientes',
                  icon: Icons.people_alt_rounded,
                  label: 'Clientes e Assinaturas',
                ),
                _subItem(
                  rota: '/assinaturas_planos',
                  icon: Icons.widgets_outlined,
                  label: 'Planos e Módulos',
                ),
                _subItem(
                  rota: '/assinaturas_cobrancas',
                  icon: Icons.receipt_long_outlined,
                  label: 'Cobranças',
                ),
                _subItem(
                  rota: '/assinaturas_inadimplencia',
                  icon: Icons.warning_amber_rounded,
                  label: 'Inadimplência',
                ),
                _subItem(
                  rota: '/assinaturas_relatorios',
                  icon: Icons.analytics_outlined,
                  label: 'Relatórios Financeiros',
                ),
                _subItem(
                  rota: '/assinaturas_fiscal',
                  icon: Icons.receipt_rounded,
                  label: 'Fiscal',
                ),
                _subItem(
                  rota: '/assinaturas_configuracoes',
                  icon: Icons.settings_rounded,
                  label: 'Configurações',
                ),
              ],
            ),
          ),
          secondChild: const SizedBox.shrink(),
        ),
      ],
    );
  }

  Widget _iconColapsado(IconData icon, String rota, String tooltip) {
    final ativo = widget.rotaAtual == rota;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => widget.onTapItem(context, rota, ativo),
          child: Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            child: Icon(
              icon,
              color: ativo ? _TemaNav.ativoCor : _TemaNav.textoMuted,
              size: 22,
            ),
          ),
        ),
      ),
    );
  }

  Widget _subItem({
    required String rota,
    required IconData icon,
    required String label,
    bool enabled = true,
    String? badge,
  }) {
    final ativo = widget.rotaAtual == rota;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: enabled ? () => widget.onTapItem(context, rota, ativo) : null,
          hoverColor: enabled ? _TemaNav.hover : Colors.transparent,
          child: Ink(
            height: 38,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: (enabled && ativo) ? _TemaNav.ativoBg : null,
            ),
            child: Row(
              children: [
                const SizedBox(width: 12),
                Icon(
                  icon,
                  size: 18,
                  color: (enabled && ativo)
                      ? _TemaNav.ativoCor
                      : _TemaNav.textoMuted,
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
                          (enabled && ativo) ? FontWeight.w600 : FontWeight.w500,
                      color: (enabled && ativo)
                          ? _TemaNav.texto
                          : _TemaNav.textoMuted,
                    ),
                  ),
                ),
                if (badge != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: _TemaNav.accent.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        badge,
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: _TemaNav.accent,
                        ),
                      ),
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
                      color: ativo ? _TemaNav.ativoCor : _TemaNav.textoMuted,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Minha carteira',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: ativo ? FontWeight.w600 : FontWeight.w500,
                          color: ativo ? _TemaNav.texto : _TemaNav.textoMuted,
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
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              child: Row(
                children: [
                  Icon(
                    icon,
                    size: 18,
                    color: ativo ? _TemaNav.ativoCor : _TemaNav.textoMuted,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: ativo ? FontWeight.w600 : FontWeight.w500,
                        color: ativo ? _TemaNav.texto : _TemaNav.textoMuted,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ),
                  if (ativo)
                    const Icon(Icons.circle, size: 6, color: _TemaNav.accent),
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
                    color: ativo ? _TemaNav.ativoCor : _TemaNav.textoMuted,
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

// ——— Rodapé / usuário logado ———

class _RodapeUsuario extends StatelessWidget {
  const _RodapeUsuario({
    required this.perfil,
    required this.collapsed,
    this.nomeLoja,
  });

  final String perfil;
  final bool collapsed;
  final String? nomeLoja;

  String _iniciais(String email, String? nome) {
    if (nome != null && nome.trim().isNotEmpty) {
      final partes = nome.trim().split(' ');
      if (partes.length >= 2) {
        return (partes[0].substring(0, 1) + partes[1].substring(0, 1)).toUpperCase();
      }
      if (nome.trim().length >= 2) {
        return nome.trim().substring(0, 2).toUpperCase();
      }
    }
    final parte = email.split('@').first.trim();
    if (parte.length >= 2) return parte.substring(0, 2).toUpperCase();
    if (parte.isNotEmpty) return parte[0].toUpperCase();
    return '?';
  }

  @override
  Widget build(BuildContext context) {
    final email = FirebaseAuth.instance.currentUser?.email?.trim() ?? 'loja@dipertin.com.br';
    final exibirNomeLoja = nomeLoja ?? 'Loja Exemplo';

    final avatar = Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            _TemaNav.accent.withValues(alpha: 0.9),
            _TemaNav.ativoCor.withValues(alpha: 0.6),
          ],
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      alignment: Alignment.center,
      child: Text(
        _iniciais(email, exibirNomeLoja),
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: 12,
          decoration: TextDecoration.none,
        ),
      ),
    );

    if (collapsed) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(0, 8, 0, 4),
        child: Tooltip(
          message: '$exibirNomeLoja\n$email',
          preferBelow: false,
          child: Center(child: avatar),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: _TemaNav.fundoElevado,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _TemaNav.borda),
        ),
        child: Row(
          children: [
            avatar,
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    exibirNomeLoja,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: _TemaNav.texto,
                      decoration: TextDecoration.none,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    email,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      color: _TemaNav.textoMuted,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ],
              ),
            ),
          ],
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
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
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
                      color: ativo ? _TemaNav.ativoCor : _TemaNav.textoMuted,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'AdminCity',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: ativo ? FontWeight.w600 : FontWeight.w500,
                          color: ativo ? _TemaNav.texto : _TemaNav.textoMuted,
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
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              child: Row(
                children: [
                  Icon(
                    icon,
                    size: 18,
                    color: ativo ? _TemaNav.ativoCor : _TemaNav.textoMuted,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: ativo ? FontWeight.w600 : FontWeight.w500,
                        color: ativo ? _TemaNav.texto : _TemaNav.textoMuted,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ),
                  if (ativo)
                    const Icon(Icons.circle, size: 6, color: _TemaNav.accent),
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
                color: ativo ? _TemaNav.ativoCor : _TemaNav.textoMuted,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ——— Seção Plano / Upgrade ———

class _SeccaoPlano extends StatefulWidget {
  const _SeccaoPlano({required this.collapsed});

  final bool collapsed;

  @override
  State<_SeccaoPlano> createState() => _SeccaoPlanoState();
}

class _SeccaoPlanoState extends State<_SeccaoPlano> {
  ClienteAssinaturaModel? _assinatura;
  bool _carregando = true;

  @override
  void initState() {
    super.initState();
    AssinaturaGestaoComercialRefresh.instance.addListener(_onPlanoAtualizado);
    _carregarAssinatura();
  }

  @override
  void dispose() {
    AssinaturaGestaoComercialRefresh.instance.removeListener(_onPlanoAtualizado);
    super.dispose();
  }

  void _onPlanoAtualizado() {
    _carregarAssinatura();
  }

  Future<void> _carregarAssinatura() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      if (mounted) setState(() => _carregando = false);
      return;
    }

    if (mounted) setState(() => _carregando = true);

    try {
      final subSnap = await FirebaseFirestore.instance
          .collection('assinaturas_clientes')
          .where('store_id', isEqualTo: uid)
          .get();
      final assinaturas =
          subSnap.docs.map(ClienteAssinaturaModel.fromFirestore).toList();
      final ctx = await AssinaturaGestaoComercialService.carregarContexto();
      final ativa = AssinaturaGestaoComercialService.assinaturaAtivaGestao(
        assinaturas,
        ctx,
      );
      if (mounted) {
        setState(() {
          _assinatura = ativa;
          _carregando = false;
        });
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[Sidebar] erro carregar plano: $e');
      if (mounted) setState(() => _carregando = false);
    }
  }

  void _abrirPlanos(BuildContext context) {
    context.navegarPainel('/comercial_dashboard');
  }

  @override
  Widget build(BuildContext context) {
    if (widget.collapsed) {
      final tooltip = _assinatura == null
          ? 'Contratar plano Gestão Comercial'
          : '${_assinatura!.planName}\nVence em ${_assinatura!.nextBillingDateExibir}';
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0),
        child: Tooltip(
          message: tooltip,
          child: Icon(
            Icons.workspace_premium_rounded,
            color: _assinatura == null
                ? Colors.white38
                : const Color(0xFFF59E0B),
            size: 20,
          ),
        ),
      );
    }

    if (_carregando) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(12, 12, 12, 8),
        child: SizedBox(
          height: 72,
          child: Center(
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
      );
    }

    final assinatura = _assinatura;
    final nomePlano = assinatura?.planName.trim().isNotEmpty == true
        ? assinatura!.planName
        : 'Sem plano ativo';
    final vencimento = assinatura?.nextBillingDateExibir ?? '—';

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1B4B),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white10),
          gradient: const LinearGradient(
            colors: [Color(0xFF2E1A47), Color(0xFF1E1B4B)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.workspace_premium_rounded,
                  color: assinatura == null
                      ? Colors.white38
                      : const Color(0xFFF59E0B),
                  size: 14,
                ),
                const SizedBox(width: 6),
                const Text(
                  'Seu plano',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.white60,
                    letterSpacing: 0.5,
                    decoration: TextDecoration.none,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              nomePlano,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                decoration: TextDecoration.none,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              assinatura == null ? 'Contrate para desbloquear' : 'Vence em $vencimento',
              style: const TextStyle(
                fontSize: 10,
                color: Colors.white70,
                fontWeight: FontWeight.w500,
                decoration: TextDecoration.none,
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 28,
              child: ElevatedButton(
                onPressed: () => _abrirPlanos(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6A1B9A),
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.zero,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                child: Text(
                  assinatura == null ? 'Ver planos' : 'Gerenciar plano',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
