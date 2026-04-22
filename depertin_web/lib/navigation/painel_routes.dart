/// Rotas exibidas dentro do [PainelShellScreen] (menu persistente + IndexedStack).
abstract final class PainelRoutes {
  static const List<String> ordem = [
    '/dashboard',
    '/lojas',
    '/entregadores',
    '/clientes',
    '/banners',
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
    '/avaliacoes_painel',
    '/comunicados',
    '/conteudo_legal',
    '/meus_pedidos',
    '/meu_cardapio',
    '/carteira_loja',
    '/carteira_financeiro',
    '/carteira_relatorio',
    '/carteira_configuracao',
  ];

  static bool isShellRoute(String route) => ordem.contains(route);

  static String normalize(String route) {
    if (ordem.contains(route)) return route;
    return '/dashboard';
  }

  static int indexOf(String route) {
    final r = normalize(route);
    final i = ordem.indexOf(r);
    return i >= 0 ? i : 0;
  }
}
