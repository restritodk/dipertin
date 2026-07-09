/// Tradutor de erros/rejeições fiscais para mensagens amigáveis.
///
/// Converte códigos de rejeição da SEFAZ e respostas de provedores
/// em mensagens claras que o lojista entende.
abstract final class FiscalErroTranslator {
  FiscalErroTranslator._();

  static final _errosConhecidos = <String, _ErroInfo>{
    // ─── SEFAZ - Rejeições 110-999 ───
    '110': _ErroInfo('CNPJ do emitente inválido',
        'O CNPJ da sua empresa não foi reconhecido pela SEFAZ. Verifique os dados fiscais em Configurações.'),
    '115': _ErroInfo('IE do emitente não cadastrada',
        'Sua Inscrição Estadual não está cadastrada na SEFAZ. Entre em contato com a SEFAZ do seu estado.'),
    '201': _ErroInfo('IE do destinatário inválida',
        'A Inscrição Estadual do cliente está incorreta. Verifique o campo IE do cliente.'),
    '202': _ErroInfo('CNPJ do destinatário inválido',
        'O CNPJ/CPF do cliente está incorreto. Verifique os dados do cliente.'),
    '203': _ErroInfo('CPF do destinatário inválido',
        'O CPF do cliente informado não é válido. Verifique os dígitos.'),
    '204': _ErroInfo('CEP inválido',
        'O CEP informado não é válido. Verifique o endereço.'),
    '205': _ErroInfo('UF do destinatário diferente da IE',
        'A UF informada não corresponde à Inscrição Estadual do destinatário.'),
    '208': _ErroInfo('CNPJ do emitente不一致',
        'O CNPJ informado não corresponde ao certificado digital.'),
    '210': _ErroInfo('IE do destinatário obrigatória',
        'Para operações interestaduais com contribuinte, a IE do destinatário é obrigatória.'),
    '220': _ErroInfo('NCM inválido',
        'O código NCM de um dos produtos não é válido (deve ter 8 dígitos). Revise os produtos.'),
    '221': _ErroInfo('CFOP inválido',
        'O CFOP informado não é válido para esta operação. Verifique o CFOP.'),
    '222': _ErroInfo('CST inválido',
        'O CST informado para o ICMS não é válido. Revise os impostos dos produtos.'),
    '223': _ErroInfo('CSOSN inválido',
        'O CSOSN informado não é válido para o Simples Nacional.'),
    '225': _ErroInfo('CEST inválido',
        'O código CEST informado não é válido (deve ter 7 dígitos).'),
    '230': _ErroInfo('Valor total diverge dos itens',
        'A soma dos produtos não confere com o total da nota. Verifique os valores.'),
    '231': _ErroInfo('Base de cálculo do ICMS incorreta',
        'A base de cálculo do ICMS não confere com o valor dos produtos. Verifique os impostos.'),
    '232': _ErroInfo('Valor do ICMS incorreto',
        'O valor do ICMS calculado não confere com a base de cálculo e alíquota.'),
    '240': _ErroInfo('Prazo de cancelamento expirado',
        'O prazo legal de 24 horas para cancelamento foi excedido. Não é mais possível cancelar esta NF-e.'),
    '241': _ErroInfo('NF-e já cancelada',
        'Esta NF-e já foi cancelada anteriormente.'),
    '242': _ErroInfo('NF-e já está em contingência',
        'Esta NF-e já foi emitida em contingência.'),
    '250': _ErroInfo('Número de NF-e já utilizado',
        'O número desta NF-e já foi utilizado. O sistema irá gerar um novo número automaticamente.'),
    '251': _ErroInfo('Série inválida',
        'A série informada não está autorizada para uso. Verifique a série fiscal.'),
    '255': _ErroInfo('Chave de acesso inválida',
        'A chave de acesso da NF-e está incorreta. Verifique os dados da nota.'),
    '260': _ErroInfo('CNPJ do destinatario obrigatorio',
        'Para operacoes com valor acima de R 200,00, o CPF/CNPJ do cliente e obrigatorio.'),
    '270': _ErroInfo('CEP do destinatário não informado',
        'O CEP do cliente não foi informado. Inclua o CEP no endereço de entrega.'),
    '280': _ErroInfo('Natureza da operação obrigatória',
        'Informe a natureza da operação (ex: "Venda de mercadoria", "Prestação de serviço").'),
    '290': _ErroInfo('Informações adicionais muito longas',
        'As informações complementares excedem o limite de 2.000 caracteres.'),
    '301': _ErroInfo('IE do emitente não informada',
        'Sua Inscrição Estadual não foi informada. Complete os dados fiscais.'),
    '302': _ErroInfo('Regime Tributário não informado',
        'Informe o Regime Tributário (CRT) nos dados fiscais da empresa.'),
    '303': _ErroInfo('Endereço do emitente incompleto',
        'Complete o endereço da empresa: logradouro, número, bairro, cidade, UF e CEP são obrigatórios.'),
    '304': _ErroInfo('CNPJ da empresa não informado',
        'O CNPJ da sua empresa não foi configurado. Acesse Configurações Fiscais.'),
    '310': _ErroInfo('XML da NF-e mal formatado',
        'O XML gerado apresentou problemas de formatação. Tente novamente ou contate o suporte.'),
    '311': _ErroInfo('Assinatura digital inválida',
        'O certificado digital A1 pode estar expirado ou ser inválido. Verifique seu certificado.'),
    '320': _ErroInfo('Certificado digital expirado',
        'Seu certificado digital A1 está vencido. Renove-o para continuar emitindo NF-e.'),
    '330': _ErroInfo('Limite de emissões excedido',
        'Você atingiu o limite mensal de emissões. Contrate um plano superior ou aguarde o próximo ciclo.'),
    '340': _ErroInfo('Empresa sem cadastro na SEFAZ',
        'Sua empresa não está cadastrada como emissor de NF-e na SEFAZ. Verifique seu credenciamento.'),
    '350': _ErroInfo('XML da CC-e inválido',
        'O XML da Carta de Correção apresentou erro. Verifique o texto da correção.'),
    '360': _ErroInfo('Limite de CC-e excedido',
        'O limite de 20 Cartas de Correção para esta NF-e foi atingido.'),
    '390': _ErroInfo('SEFAZ indisponível',
        'A SEFAZ está temporariamente indisponível. A nota será emitida em contingência.'),
    '395': _ErroInfo('Timeout na comunicação',
        'A SEFAZ não respondeu dentro do prazo. Tente novamente ou use a contingência.'),
    '396': _ErroInfo('Erro de conexão com a SEFAZ',
        'Não foi possível conectar à SEFAZ. Verifique sua conexão de internet.'),
    '400': _ErroInfo('Requisição inválida',
        'A API fiscal retornou uma requisição inválida. Tente novamente.'),
    '401': _ErroInfo('Credenciais inválidas',
        'As credenciais de acesso à API fiscal estão incorretas. Verifique a integração.'),
    '403': _ErroInfo('Acesso não autorizado',
        'Você não tem permissão para realizar esta operação no provedor fiscal.'),
    '404': _ErroInfo('Nota fiscal não encontrada',
        'A NF-e informada não foi encontrada no sistema do provedor.'),
    '409': _ErroInfo('Conflito - NF-e já existe',
        'Já existe uma NF-e com este número no sistema. O número será ajustado automaticamente.'),
    '422': _ErroInfo('Dados inválidos',
        'Alguns dados enviados para a API fiscal são inválidos. Revise as informações.'),
    '429': _ErroInfo('Muitas requisições',
        'Muitas requisições foram feitas em pouco tempo. Aguarde alguns segundos e tente novamente.'),
    '500': _ErroInfo('Erro interno do provedor',
        'O provedor fiscal apresentou um erro interno. Tente novamente em alguns minutos.'),
    '502': _ErroInfo('Gateway inválido',
        'O gateway do provedor fiscal retornou erro. Tente novamente.'),
    '503': _ErroInfo('Serviço temporariamente indisponível',
        'O serviço do provedor fiscal está temporariamente fora do ar. Tente mais tarde.'),
    '504': _ErroInfo('Tempo limite excedido',
        'O provedor fiscal não respondeu a tempo. A nota pode ter sido emitida — consulte o status.'),
  };

  /// Retorna mensagem amigável para um código de erro/rejeição.
  static ({String titulo, String descricao}) traduzir(
    String? codigo, {
    String? mensagemOriginal,
  }) {
    // Tenta pelo código
    if (codigo != null && _errosConhecidos.containsKey(codigo)) {
      final info = _errosConhecidos[codigo]!;
      return (titulo: info.titulo, descricao: info.descricao);
    }

    // Tenta inferir pela mensagem original
    if (mensagemOriginal != null) {
      final lower = mensagemOriginal.toLowerCase();
      if (lower.contains('certificate') || lower.contains('certificado')) {
        return (titulo: 'Problema com certificado digital',
            descricao: 'Verifique se o certificado digital A1 está válido e instalado corretamente.');
      }
      if (lower.contains('expir') || lower.contains('venc') || lower.contains('expirado')) {
        return (titulo: 'Certificado ou credencial expirada',
            descricao: 'Seu certificado digital ou token de acesso pode estar vencido. Renove-o.'); 
      }
      if (lower.contains('timeout') || lower.contains('time out')) {
        return (titulo: 'Tempo limite excedido',
            descricao: 'A comunicação com a SEFAZ/API excedeu o tempo limite. Verifique sua internet e tente novamente.');
      }
      if (lower.contains('network') || lower.contains('connection') || lower.contains('conex')) {
        return (titulo: 'Erro de conexão',
            descricao: 'Não foi possível conectar ao serviço fiscal. Verifique sua conexão de internet.');
      }
      if (lower.contains('invalid') || lower.contains('invalido') || lower.contains('inválido')) {
        return (titulo: 'Dados inválidos',
            descricao: 'Alguns dados enviados são inválidos. Revise as informações e tente novamente.');
      }
      if (lower.contains('unauthorized') || lower.contains('auth') || lower.contains('credencial')) {
        return (titulo: 'Credenciais inválidas',
            descricao: 'As credenciais de acesso ao provedor fiscal estão incorretas. Verifique a integração.');
      }
      if (lower.contains('not found') || lower.contains('não encontrado') || lower.contains('nao encontrado')) {
        return (titulo: 'NF-e não encontrada',
            descricao: 'A NF-e informada não foi encontrada no sistema do provedor. Verifique os dados.');
      }
    }

    // Fallback genérico
    return (titulo: 'Erro na operação fiscal',
        descricao: mensagemOriginal ?? 'Ocorreu um erro inesperado. Tente novamente ou contate o suporte.');
  }

  /// Extrai código de rejeição de uma string de erro.
  static String? extrairCodigoRejeicao(String? erro) {
    if (erro == null) return null;
    // "Rejeição 220: NCM inválido"
    final regex = RegExp(r'(?:Rejei[cç][aã]o|Erro)\s*[:\-]?\s*(\d{3})');
    final match = regex.firstMatch(erro);
    if (match != null) return match.group(1);

    // Códigos JSON (em providerResponse)
    final regex2 = RegExp(r'"codigo"\s*:\s*"(\d{3})"');
    final match2 = regex2.firstMatch(erro);
    if (match2 != null) return match2.group(1);

    return null;
  }

  /// Retorna true se o erro indica que a SEFAZ está indisponível.
  static bool isIndisponibilidadeSefaz(String? erro) {
    if (erro == null) return false;
    final lower = erro.toLowerCase();
    return lower.contains('offline') ||
        lower.contains('indispon') ||
        lower.contains('503') ||
        lower.contains('396') ||
        lower.contains('395') ||
        lower.contains('390') ||
        (lower.contains('timeout') && lower.contains('sefaz'));
  }

  /// Retorna true se o erro é de credenciais/configuração.
  static bool isErroConfiguracao(String? erro) {
    if (erro == null) return false;
    final lower = erro.toLowerCase();
    return lower.contains('401') ||
        lower.contains('403') ||
        lower.contains('credencial') ||
        lower.contains('auth') ||
        lower.contains('certificate') ||
        lower.contains('certificado') ||
        lower.contains('token');
  }
}

class _ErroInfo {
  final String titulo;
  final String descricao;
  const _ErroInfo(this.titulo, this.descricao);
}
