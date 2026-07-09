/// Motivos padronizados para cancelamento de plano (admin).
class AssinaturaCancelamentoMotivo {
  const AssinaturaCancelamentoMotivo({
    required this.codigo,
    required this.rotulo,
  });

  final String codigo;
  final String rotulo;

  static const String codigoOutro = 'outro';

  static const List<AssinaturaCancelamentoMotivo> opcoes = [
    AssinaturaCancelamentoMotivo(
      codigo: 'solicitacao_lojista',
      rotulo: 'Solicitação do lojista',
    ),
    AssinaturaCancelamentoMotivo(
      codigo: 'falta_pagamento',
      rotulo: 'Falta de pagamento',
    ),
    AssinaturaCancelamentoMotivo(
      codigo: 'uso_indevido',
      rotulo: 'Uso indevido do sistema',
    ),
    AssinaturaCancelamentoMotivo(
      codigo: 'troca_plano',
      rotulo: 'Troca de plano',
    ),
    AssinaturaCancelamentoMotivo(
      codigo: 'encerramento_loja',
      rotulo: 'Encerramento da loja',
    ),
    AssinaturaCancelamentoMotivo(
      codigo: 'problemas_cadastrais',
      rotulo: 'Problemas cadastrais',
    ),
    AssinaturaCancelamentoMotivo(
      codigo: 'decisao_administrativa',
      rotulo: 'Decisão administrativa',
    ),
    AssinaturaCancelamentoMotivo(
      codigo: codigoOutro,
      rotulo: 'Outro motivo',
    ),
  ];

  static String? rotuloPorCodigo(String? codigo) {
    if (codigo == null || codigo.isEmpty) return null;
    for (final m in opcoes) {
      if (m.codigo == codigo) return m.rotulo;
    }
    return null;
  }
}
