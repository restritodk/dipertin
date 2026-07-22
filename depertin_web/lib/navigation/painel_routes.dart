/// Rotas exibidas dentro do [PainelShellScreen] (menu persistente + IndexedStack).
abstract final class PainelRoutes {
  static const List<String> ordem = [
    '/dashboard',
    '/lojas',
    '/lojas_financeiro',
    '/entregadores',
    '/clientes',
    '/banners',
    '/categorias',
    '/admincity',
    '/admincity_cidades',
    '/utilidades',
    '/financeiro',
    '/financeiro_saques',
    '/configuracoes',
    '/configuracao_cadastro_acesso',
    '/atendimento_suporte',
    '/notificacoes',
    '/cupons',
    '/monitor_pedidos',
    '/centro_operacoes_crm',
    '/centro_operacoes_marketing',
    '/centro_operacoes_leads_lojistas',
    '/centro_operacoes_leads_entregadores',
    '/centro_operacoes_agenda',
    '/centro_operacoes_frete',
    '/avaliacoes_painel',
    '/comunicados',
    '/conteudo_legal',
    '/auditoria',
    '/pdv',
    '/meus_pedidos',
    '/negociacoes_encomenda',
    '/meu_cardapio',
    '/meus_cupons',
    '/carteira_loja',
    '/carteira_financeiro',
    '/carteira_relatorio',
    '/carteira_configuracao',
    '/comercial_dashboard',
    '/minha_loja',
    '/comercial_clientes',
    '/comercial_credito',
    '/comercial_pendencias',
    '/comercial_recebimentos',
    '/comercial_historico',
    '/comercial_relatorios',
    '/comercial_configuracoes',
    '/assinaturas_dashboard',
    '/assinaturas_clientes',
    '/assinaturas_planos',
    '/assinaturas_cobrancas',
    '/assinaturas_inadimplencia',
    '/assinaturas_relatorios',
    '/assinaturas_fiscal',
    '/assinaturas_configuracoes',
    '/modulo_fiscal',
    '/admin_fiscal',
  ];

  static bool isShellRoute(String route) => ordem.contains(route);

  static String normalize(String route) {
    if (route == '/centro_operacoes') return '/centro_operacoes_crm';
    if (route == '/assinaturas') return '/assinaturas_dashboard';
    if (ordem.contains(route)) return route;
    return '/dashboard';
  }

  /// Rotas filhas do accordion Centro de operações (sidebar principal).
  static const List<String> centroOperacoesRotas = [
    '/centro_operacoes_crm',
    '/centro_operacoes_marketing',
    '/centro_operacoes_leads_lojistas',
    '/centro_operacoes_leads_entregadores',
    '/centro_operacoes_agenda',
    '/centro_operacoes_frete',
  ];

  static bool ehRotaCentroOperacoes(String route) =>
      centroOperacoesRotas.contains(route) || route == '/centro_operacoes';

  /// Rotas filhas do accordion Gestão de Assinaturas.
  static const List<String> assinaturasRotas = [
    '/assinaturas_dashboard',
    '/assinaturas_clientes',
    '/assinaturas_planos',
    '/assinaturas_cobrancas',
    '/assinaturas_inadimplencia',
    '/assinaturas_relatorios',
    '/assinaturas_fiscal',
    '/assinaturas_configuracoes',
  ];

  static bool ehRotaAssinaturas(String route) =>
      assinaturasRotas.contains(route) || route == '/assinaturas';

  /// Rotas filhas do submenu Financeiro (dentro de Gestão Comercial).
  static const List<String> comercialFinanceiroRotas = [
    '/comercial_credito',
    '/comercial_pendencias',
    '/comercial_recebimentos',
    '/comercial_historico',
    '/comercial_relatorios',
  ];

  static bool ehRotaComercialFinanceiro(String route) =>
      comercialFinanceiroRotas.contains(route);

  /// Rotas do módulo Gestão Comercial (lojista) — exigem gate de assinatura.
  static const List<String> gestaoComercialRotas = [
    '/pdv',
    '/comercial_dashboard',
    '/minha_loja',
    '/comercial_clientes',
    '/comercial_credito',
    '/comercial_pendencias',
    '/comercial_recebimentos',
    '/comercial_historico',
    '/comercial_relatorios',
    '/comercial_configuracoes',
    '/modulo_fiscal',
  ];

  static bool ehRotaGestaoComercial(String route) =>
      gestaoComercialRotas.contains(route);

  static int indexOf(String route) {
    final r = normalize(route);
    final i = ordem.indexOf(r);
    return i >= 0 ? i : 0;
  }
}
