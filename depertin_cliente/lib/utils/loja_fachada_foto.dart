// URL da imagem de **fachada da loja** (vitrine, busca, detalhes, pedido).
//
// Separada da foto de perfil **pessoal** do usuário (`foto_perfil` no documento).
// O lojista define a foto da loja na Configuração operacional (`foto`, `foto_logo`, `imagem`).
//
// Ordem: campos de loja primeiro → `foto_perfil` só como legado → `foto_capa` por último
// (capa costuma ser banner largo; logo circular vem dos campos acima).

String urlFachadaLojaCliente(Map<String, dynamic>? dados) {
  if (dados == null || dados.isEmpty) return '';
  const chaves = <String>[
    'foto',
    'foto_logo',
    'imagem',
    'foto_perfil',
    'foto_capa',
  ];
  for (final k in chaves) {
    final v = (dados[k] ?? '').toString().trim();
    if (v.isNotEmpty) return v;
  }
  return '';
}
