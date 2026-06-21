/// Tipos de cupom — espelho de `functions/cupom_helpers.js`.
abstract class CupomTipos {
  static const porcentagem = 'porcentagem';
  static const fixo = 'fixo';
  static const freteGratis = 'frete_gratis';

  static const freteSemLimite = 'sem_limite';
  static const freteRaioKm = 'raio_km';

  static const escopoLoja = 'loja';
  static const escopoGlobal = 'global';

  static String rotuloTipo(String? tipo) {
    switch (tipo) {
      case porcentagem:
        return 'Percentual';
      case fixo:
        return 'Valor fixo';
      case freteGratis:
        return 'Frete grátis';
      default:
        return 'Cupom';
    }
  }

  static String resumoValor(Map<String, dynamic> c) {
    final tipo = (c['tipo'] ?? porcentagem).toString();
    final valor = (c['valor'] as num?)?.toDouble() ?? 0;
    if (tipo == porcentagem) return '${valor.toStringAsFixed(0)}%';
    if (tipo == fixo) return 'R\$ ${valor.toStringAsFixed(2)}';
    if (tipo == freteGratis) {
      final mod = (c['frete_gratis_modalidade'] ?? freteSemLimite).toString();
      if (mod == freteRaioKm) {
        final km = (c['frete_gratis_raio_km'] as num?)?.toDouble();
        return km != null ? 'Até ${km.toStringAsFixed(0)} km' : 'Por raio';
      }
      return 'Sem limite de distância';
    }
    return '—';
  }
}
