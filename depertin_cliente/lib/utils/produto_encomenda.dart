/// Produto vendido por encomenda quando [tipo_venda] == `encomenda`.
bool produtoMapEhEncomenda(Map<String, dynamic>? map) {
  if (map == null) return false;
  final t = (map['tipo_venda'] ?? '').toString().trim().toLowerCase();
  return t == 'encomenda';
}
