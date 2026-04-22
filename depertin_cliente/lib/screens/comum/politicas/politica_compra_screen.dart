import 'package:flutter/material.dart';

import 'policy_scroll_page.dart';

/// Condições de compra, pedido, pagamento e entrega no DiPertin.
class PoliticaCompraScreen extends StatelessWidget {
  const PoliticaCompraScreen({super.key});

  static const List<PolicySection> _secoes = [
    PolicySection(
      titulo: 'Identificação da empresa',
      corpo:
          'DiPertin\n'
          'CNPJ: 66.040.998/0001-66\n'
          'Telefone: (66) 3180-0107\n'
          'E-mail: contato@dipertin.com.br',
    ),
    PolicySection(
      titulo: 'I — Âmbito de aplicação e integração normativa',
      corpo:
          'A presente Política de Compra disciplina as condições essenciais '
          'para a formalização de pedidos por meio do aplicativo DiPertin, '
          'incluindo, conforme o caso, preços, meios de pagamento, entrega e '
          'repartição de responsabilidades entre as partes envolvidas na '
          'cadeia de consumo mediada pela plataforma.\n\n'
          'Esta Política deve ser interpretada em conjunto com a Política de '
          'Uso e com a Política de Privacidade, constituindo instrumentos '
          'complementares e harmonizados, sem prejuízo das normas cogentes do '
          'ordenamento jurídico brasileiro, em especial o Código de Defesa do '
          'Consumidor (Lei nº 8.078/1990), quando aplicável.',
    ),
    PolicySection(
      titulo: 'II — Formalização do pedido e natureza da avença',
      corpo:
          'O pedido reputa-se formalizado quando o usuário conclui o fluxo de '
          'checkout no aplicativo, com confirmação dos itens, valores '
          'apresentados (produtos, taxas e totais) e, quando exigido, dados de '
          'entrega e forma de pagamento, observada a disponibilidade técnica '
          'do momento.\n\n'
          'Os valores exibidos antes da confirmação vinculam a proposta '
          'apresentada ao usuário naquele instante, salvo erro manifesto, '
          'impossibilidade técnica ou caso fortuito devidamente comunicado, '
          'nos limites da lei.',
    ),
    PolicySection(
      titulo: 'III — Preços, tributos e condições comerciais da loja',
      corpo:
          'Os preços, descrições, disponibilidade de itens, combos, promoções e '
          'condições específicas de cada estabelecimento são de responsabilidade '
          'do lojista, que atua como fornecedor perante o consumidor final, '
          'quando aplicável. O DiPertin exibe tais informações conforme '
          'cadastro e parametrização da loja, não substituindo a obrigação do '
          'comerciante de cumprir a oferta lícita veiculada.',
    ),
    PolicySection(
      titulo: 'IV — Pagamentos e processamento por terceiros',
      corpo:
          'Os pagamentos podem ser processados por meio de integrações com '
          'gateways de pagamento (como, exemplificativamente, Mercado Pago). '
          'O PIX, quando habilitado em ambiente de produção, poderá ser '
          'processado de forma efetiva; outras modalidades poderão constar da '
          'interface conforme configuração vigente da plataforma, incluindo '
          'modalidades de demonstração ou teste quando assim indicado.\n\n'
          'O usuário declara ciência de que dados necessários à transação '
          'serão tratados nos termos da Política de Privacidade e dos '
          'contratos de adesão do respectivo provedor de pagamento.',
    ),
    PolicySection(
      titulo: 'V — Entrega, taxa de entrega e logística',
      corpo:
          'Quando contratada entrega, poderá incidir taxa de entrega e regras '
          'específicas exibidas no aplicativo no ato do pedido, podendo variar '
          'conforme região, distância, configuração da plataforma ou da loja.\n\n'
          'Prazos e possibilidade de entrega dependem da loja, da disponibilidade '
          'de entregadores e das condições locais. Comprovações ou códigos '
          'exibidos no aplicativo destinam-se à conferência do cumprimento da '
          'entrega conforme fluxo implementado.',
    ),
    PolicySection(
      titulo: 'VI — Cancelamentos, arrependimento e reclamações',
      corpo:
          'Cancelamentos e alterações observam a viabilidade técnica do '
          'aplicativo no momento do pedido e as regras da loja. Pedidos em '
          'preparo ou em rota podem não ser passíveis de cancelamento sem '
          'ônus, conforme o caso e a legislação aplicável.\n\n'
          'O direito de arrependimento em relações de consumo, quando cabível '
          'à hipótese concreta, será observado conforme o Código de Defesa do '
          'Consumidor e a natureza do bem ou serviço contratado.\n\n'
          'Reclamações sobre cobrança, falhas de sistema ou divergências de '
          'pedido deverão ser registradas pelo canal de suporte no aplicativo, '
          'com informações objetivas (número do pedido, data, elementos de prova '
          'razoáveis).',
    ),
    PolicySection(
      titulo: 'VII — Atualização deste documento',
      corpo:
          'O DiPertin poderá revisar esta Política de Compra, mantendo a '
          'publicação da versão vigente no aplicativo, com indicação da data de '
          'atualização, nos termos já previstos na Política de Uso quanto à '
          'forma de divulgação eletrônica.',
    ),
    PolicySection(
      titulo: 'VIII — Foro',
      corpo:
          'Para questões decorrentes desta Política de Compra, inclusive '
          'interpretação, validade e cumprimento, em complemento ao já '
          'estabelecido nos demais instrumentos, fica eleito o foro da Comarca '
          'de Rondonópolis, Estado de Mato Grosso, com renúncia a qualquer '
          'outro, salvo competência legal diversa imperativa.',
    ),
  ];

  static const String _rodape =
      'Promoções, combos, garantias específicas de produto ou condições '
      'comerciais adicionais podem ser estabelecidas pelo lojista e devem ser '
      'observadas no momento da contratação, sem prejuízo de direitos do '
      'consumidor previstos em lei.';

  @override
  Widget build(BuildContext context) {
    return const PolicyScrollPage(
      title: 'Política de compra',
      sections: _secoes,
      rodape: _rodape,
    );
  }
}
