/// Estados da negociação de encomenda (`encomendas.status_negociacao`).
/// Mantidos em snake_case para coincidir com Firestore (espelho do app mobile).
abstract class EncomendaNegociacaoStatus {
  static const aguardandoNegociacao = 'aguardando_negociacao';
  static const negociacaoEmAndamento = 'negociacao_em_andamento';
  static const propostaEnviada = 'proposta_enviada';
  static const aguardandoRespostaLojaContraproposta =
      'aguardando_resposta_loja_contraproposta';
  static const propostaAceitaPendenteEntrada =
      'proposta_aceita_pendente_entrada';
  static const entradaAguardandoPagamento = 'entrada_aguardando_pagamento';
  static const entradaPagaEmProducao = 'entrada_paga_em_producao';
  static const saldoFinalAguardandoPgto = 'saldo_final_aguardando_pgto';
  static const emExecucaoLogistica = 'em_execucao_logistica';
  static const encerradaRecusadaLoja = 'encerrada_recusada_loja';
  static const encerradaCanceladaCliente = 'encerrada_cancelada_cliente';
  static const encerradaCanceladaLoja = 'encerrada_cancelada_loja';

  static bool podeCancelarNegociacaoAntesPagamentoEntrada(String st) {
    switch (st) {
      case aguardandoNegociacao:
      case negociacaoEmAndamento:
      case propostaEnviada:
      case aguardandoRespostaLojaContraproposta:
      case propostaAceitaPendenteEntrada:
      case entradaAguardandoPagamento:
        return true;
      default:
        return false;
    }
  }

  static bool encerradaDefinitivamente(String st) {
    return st == encerradaRecusadaLoja ||
        st == encerradaCanceladaCliente ||
        st == encerradaCanceladaLoja;
  }

  static String rotuloPt(String status) {
    switch (status) {
      case aguardandoNegociacao:
        return 'Aguardando a loja';
      case negociacaoEmAndamento:
        return 'Em negociação';
      case propostaEnviada:
        return 'Proposta da loja enviada';
      case aguardandoRespostaLojaContraproposta:
        return 'Aguardando resposta da loja';
      case propostaAceitaPendenteEntrada:
        return 'Proposta aceita — cliente deve pagar entrada';
      case entradaAguardandoPagamento:
        return 'Aguardando pagamento da entrada';
      case entradaPagaEmProducao:
        return 'Entrada paga — em produção';
      case saldoFinalAguardandoPgto:
        return 'Aguardando pagamento do saldo';
      case emExecucaoLogistica:
        return 'Em execução (entrega)';
      case encerradaRecusadaLoja:
        return 'Encerrada pela loja';
      case encerradaCanceladaCliente:
        return 'Cancelada pelo cliente';
      case encerradaCanceladaLoja:
        return 'Cancelada pela loja';
      default:
        return status;
    }
  }
}
