import 'package:flutter/material.dart';

import 'policy_scroll_page.dart';

/// Tratamento de dados pessoais no ecossistema DiPertin (LGPD).
class PoliticaPrivacidadeScreen extends StatelessWidget {
  const PoliticaPrivacidadeScreen({super.key});

  static const List<PolicySection> _secoes = [
    PolicySection(
      titulo: 'Identificação do controlador',
      corpo:
          'DiPertin\n'
          'CNPJ: 66.040.998/0001-66\n'
          'Telefone: (66) 3180-0107\n'
          'E-mail: contato@dipertin.com.br\n\n'
          'Em matéria de proteção de dados pessoais, dúvidas, solicitações de '
          'titulares e exercício de direitos previstos na LGPD podem ser '
          'enviados para o e-mail acima.',
    ),
    PolicySection(
      titulo: 'I — Controlador, escopo e base legal',
      corpo:
          'O presente documento constitui a Política de Privacidade do DiPertin, '
          'aplicável aos titulares de dados pessoais que utilizam o aplicativo '
          'e serviços associados, em conformidade com a Lei Geral de Proteção '
          'de Dados Pessoais (Lei nº 13.709/2018 — LGPD) e demais normas '
          'aplicáveis.\n\n'
          'O tratamento de dados pessoais observará as bases legais previstas '
          'no art. 7º e art. 11 da LGPD, incluindo, conforme o caso, execução '
          'de contrato ou procedimentos preliminares, cumprimento de obrigação '
          'legal, legítimo interesse (com avaliação de expectativa do titular e '
          'mitigação de riscos), estudo por órgão de pesquisa e consentimento, '
          'quando exigido.',
    ),
    PolicySection(
      titulo: 'II — Natureza eletrônica, transparência e documentos correlatos',
      corpo:
          'Esta Política é disponibilizada em meio eletrônico no aplicativo '
          'oficial e integra o conjunto de documentos jurídicos do DiPertin, '
          'devendo ser lida em conjunto com a Política de Uso e a Política de '
          'Compra, sem prejuízo da autonomia de cada instrumento quanto ao '
          'objeto específico.\n\n'
          'A versão autêntica e atualizada é a constante na interface, com data '
          'de revisão indicada. Comunicações acessórias não substituem o texto '
          'integral aqui publicado.',
    ),
    PolicySection(
      titulo: 'III — Dados pessoais tratados e finalidades',
      corpo:
          'Podem ser tratados, entre outros: dados de identificação e contato '
          '(nome, e-mail, telefone, CPF quando informado); dados de perfil e '
          'preferências; endereços de entrega; geolocalização, quando autorizada, '
          'para fins de exibição de conteúdo regional e logística; dados de uso '
          'do aplicativo; identificadores de dispositivo e token para '
          'notificações push (Firebase Cloud Messaging); histórico de pedidos; '
          'registros de atendimento e mensagens de suporte; e documentos '
          'enviados para cadastro ou verificação de lojista e entregador, '
          'conforme fluxos aplicáveis.\n\n'
          'As finalidades incluem viabilizar cadastro, autenticação, pedidos, '
          'pagamentos, entregas, suporte, segurança, prevenção a fraudes, '
          'cumprimento de obrigações legais e melhoria do serviço, sempre '
          'compatíveis com a base legal aplicável.',
    ),
    PolicySection(
      titulo: 'IV — Operadores, subprocessadores e infraestrutura em nuvem',
      corpo:
          'O aplicativo utiliza serviços Google Firebase (incluindo, '
          'exemplificativamente, Authentication, Firestore, Storage, Cloud '
          'Functions e Cloud Messaging), o que pode implicar armazenamento e '
          'processamento em infraestrutura de terceiros, nos termos contratuais '
          'do Google e das configurações de segurança aplicadas ao projeto.\n\n'
          'Transações de pagamento podem envolver provedores como Mercado Pago, '
          'sob suas políticas e termos. Recomenda-se a leitura dos documentos '
          'dos respectivos fornecedores quando utilizados.',
    ),
    PolicySection(
      titulo: 'V — Compartilhamento e comunicação de dados',
      corpo:
          'Os dados poderão ser compartilhados com lojistas e entregadores na '
          'medida necessária ao cumprimento do pedido (por exemplo, nome, '
          'endereço e telefone para entrega); com instituições de pagamento; '
          'com prestadores de serviços essenciais (hospedagem, envio de '
          'mensagens); e com autoridades públicas quando exigido por lei ou '
          'ordem judicial fundamentada, observados os limites legais.',
    ),
    PolicySection(
      titulo: 'VI — Prazo de retenção e exclusão de conta',
      corpo:
          'Os dados serão mantidos pelo período necessário ao cumprimento das '
          'finalidades informadas, ao exercício regular de direitos, ao '
          'cumprimento de obrigações legais ou regulatórias e à resolução de '
          'controvérsias. A exclusão de conta poderá ser solicitada conforme '
          'fluxo disponível no aplicativo, observados prazos legais de guarda '
          'quando impostos.',
    ),
    PolicySection(
      titulo: 'VII — Direitos do titular',
      corpo:
          'Nos termos da LGPD, o titular poderá solicitar confirmação de '
          'existência de tratamento; acesso; correção de dados incompletos, '
          'inexatos ou desatualizados; anonimização, bloqueio ou eliminação de '
          'dados desnecessários ou tratados em desconformidade; portabilidade, '
          'quando aplicável; informação sobre compartilhamentos; informação '
          'sobre a possibilidade de não fornecer consentimento e suas '
          'consequências; revogação de consentimento, quando a base for o '
          'consentimento; e oposição a tratamento fundado em legítimo interesse, '
          'quando cabível.\n\n'
          'Pedidos poderão ser formulados pelo canal de suporte no aplicativo, '
          'podendo ser exigida comprovação razoável de identidade para proteção '
          'do titular.',
    ),
    PolicySection(
      titulo: 'VIII — Segurança da informação e cookies/tecnologias',
      corpo:
          'São adotadas medidas técnicas e organizacionais compatíveis com o '
          'risco e o contexto do tratamento. Não obstante, nenhum sistema é '
          'isento de riscos; recomenda-se o uso de senha robusta e a não '
          'divulgação de credenciais.\n\n'
          'Em ambiente móvel, podem ser empregados identificadores e '
          'armazenamento local para sessão e preferências, nos limites da '
          'plataforma e das permissões concedidas.',
    ),
    PolicySection(
      titulo: 'IX — Encarregado de dados (DPO) e alterações',
      corpo:
          'Solicitações relacionadas ao tratamento de dados pessoais poderão ser '
          'encaminhadas ao canal indicado no aplicativo, para atendimento pelo '
          'responsável ou encarregado, conforme estrutura organizacional vigente.\n\n'
          'Esta Política poderá ser atualizada; a data da última revisão constará '
          'no documento publicado na interface.',
    ),
    PolicySection(
      titulo: 'X — Legislação aplicável e foro',
      corpo:
          'Aplica-se a legislação brasileira. Para controvérsias decorrentes '
          'desta Política de Privacidade, inclusive quanto ao tratamento de '
          'dados pessoais, fica eleito o foro da Comarca de Rondonópolis, Estado '
          'de Mato Grosso, com renúncia a qualquer outro, por mais privilegiado '
          'que seja, ressalvadas a competência absoluta e as normas imperativas '
          'sobre consumo ou proteção de dados que atribuam foro diverso.',
    ),
  ];

  static const String _rodape =
      'Este documento tem finalidade de transparência e conformidade com a LGPD '
      'e não substitui parecer jurídico individualizado. Em caso de dúvida sobre '
      'direitos ou tratamentos, utilize o suporte no aplicativo.';

  @override
  Widget build(BuildContext context) {
    return const PolicyScrollPage(
      title: 'Política de privacidade',
      sections: _secoes,
      rodape: _rodape,
    );
  }
}
