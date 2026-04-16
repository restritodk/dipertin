import 'package:flutter/material.dart';

import 'policy_scroll_page.dart';

/// Termos gerais de uso da plataforma DiPertin.
class PoliticaUsoScreen extends StatelessWidget {
  const PoliticaUsoScreen({super.key});

  static const List<PolicySection> _secoes = [
    PolicySection(
      titulo: 'I — Objeto, natureza jurídica e aceitação',
      corpo:
          'O presente instrumento constitui a Política de Uso (doravante apenas '
          '"Política") do ecossistema digital DiPertin, compreendendo aplicativo '
          'móvel e serviços associados, caracterizado como plataforma de '
          'intermediação de marketplace e delivery local, mediante tecnologia '
          'própria ou de terceiros integrados.\n\n'
          'O cadastro, o acesso ou o uso continuado implicam ciência e '
          'concordância tácita ou expressa com esta Política, com a Política de '
          'Privacidade e com a Política de Compra, as quais integram um único '
          'conjunto normativo para todos os efeitos jurídicos cabíveis, '
          'inclusive para interpretação conjunta em caso de lacuna ou conflito '
          'aparente entre instrumentos, devendo prevalecer a solução mais '
          'favorável à transparência e ao cumprimento da legislação consumerista '
          'e de proteção de dados, quando aplicável.',
    ),
    PolicySection(
      titulo: 'II — Tratamento, vigência e forma dos documentos jurídicos',
      corpo:
          'Os documentos legais do DiPertin são disponibilizados em meio '
          'eletrônico exclusivamente por intermédio do aplicativo oficial, '
          'podendo ser atualizados a qualquer tempo. A data da última revisão '
          'consta expressamente em cada documento.\n\n'
          'A versão vigente é considerada publicada e oposta a todos os '
          'usuários no momento em que disponibilizada na interface; o uso '
          'subsequente dos serviços importa anuência às condições então em '
          'vigor, ressalvadas as hipóteses em que a lei exigir consentimento '
          'específico ou informação prévia destacada.\n\n'
          'Eventuais comunicações acessórias (notificações push, avisos em tela '
          'ou e-mail) têm caráter meramente informativo e não substituem a '
          'integralidade dos documentos aqui referidos, devendo o usuário '
          'consultar sempre o texto completo no aplicativo.',
    ),
    PolicySection(
      titulo: 'III — Natureza do serviço e limitação de responsabilidade',
      corpo:
          'O DiPertin atua na qualidade de intermediador tecnológico, '
          'facilitando o contato entre usuários e estabelecimentos comerciais '
          'parceiros, bem como, quando aplicável, a logística de entrega por '
          'meio de entregadores cadastrados. A oferta de produtos e serviços, '
          'bem como preços, estoques, qualidade, prazos de preparo, garantias '
          'e políticas comerciais específicas são de exclusiva responsabilidade '
          'dos lojistas, salvo disposição legal em contrário.\n\n'
          'O DiPertin não se substitui aos fornecedores finais de produtos ou '
          'serviços, não garantindo resultados específicos além da adequada '
          'disponibilização da plataforma, nos limites da legislação aplicável.',
    ),
    PolicySection(
      titulo: 'IV — Perfis de acesso e elegibilidade',
      corpo:
          'A plataforma admite, conforme habilitação: perfil de cliente '
          '(navegação, pedidos e pagamentos); perfil de lojista (gestão de loja, '
          'cardápio e pedidos); perfil de entregador (aceite de corridas e '
          'entregas, quando habilitado); e perfis administrativos (gestão '
          'central ou regional), observadas as permissões atribuídas a cada conta.\n\n'
          'O usuário declara possuir capacidade civil para contratar ou estar '
          'adequadamente representado, comprometendo-se a fornecer dados '
          'verídicos e mantê-los atualizados.',
    ),
    PolicySection(
      titulo: 'V — Deveres do usuário e uso lícito da plataforma',
      corpo:
          'É vedado ao usuário utilizar o aplicativo de forma ilícita, '
          'fraudulenta, abusiva ou que importe violação de direitos de '
          'terceiros, comprometimento da segurança da informação, sobrecarga '
          'indevida de infraestrutura, engenharia reversa não autorizada ou '
          'extração automatizada de dados em desacordo com a lei ou com estes termos.\n\n'
          'Conteúdos enviados (textos, imagens, áudios, documentos) devem '
          'observar a legislação brasileira e os bons costumes. O DiPertin '
          'poderá remover conteúdos, suspender ou encerrar contas, bem como '
          'adotar medidas administrativas e jurídicas cabíveis, conforme a '
          'gravidade da infração.',
    ),
    PolicySection(
      titulo: 'VI — Propriedade intelectual, notificações e permissões',
      corpo:
          'Marcas, layout, software, bases de dados e demais elementos '
          'protegidos relativos ao DiPertin permanecem sob titularidade legítima '
          'dos respectivos detentores, sendo vedada a reprodução ou uso não '
          'autorizado além do estritamente necessário ao acesso ao serviço.\n\n'
          'Notificações push, geolocalização e demais permissões de dispositivo '
          'serão utilizadas conforme finalidades informadas na Política de '
          'Privacidade e nas configurações do aplicativo e do sistema operacional.',
    ),
    PolicySection(
      titulo: 'VII — Alteração desta Política',
      corpo:
          'O DiPertin poderá alterar esta Política, publicando a versão revisada '
          'no aplicativo. Alterações relevantes poderão ser destacadas por meios '
          'razoáveis à disposição da plataforma. O prosseguimento do uso após a '
          'publicação poderá ser interpretado como aceitação, observada a '
          'legislação aplicável, inclusive o Código de Defesa do Consumidor.',
    ),
    PolicySection(
      titulo: 'VIII — Legislação aplicável e foro',
      corpo:
          'Este instrumento rege-se pelas leis da República Federativa do Brasil.\n\n'
          'Para dirimir quaisquer controvérsias oriundas desta Política ou dos '
          'demais documentos integrantes, fica eleito o foro da Comarca de '
          'Rondonópolis, Estado de Mato Grosso, com renúncia expressa a '
          'qualquer outro, por mais privilegiado que seja, ressalvadas as '
          'hipóteses de competência absoluta, de defesa do consumidor ou de '
          'outra norma imperativa que atribua competência a juízo diverso.',
    ),
  ];

  static const String _rodape =
      'As partes reconhecem que a leitura deste documento não substitui '
      'consultoria jurídica personalizada. Em caso de conflito entre o texto '
      'aqui exibido e dispositivo legal imperativo, prevalecerá a legislação '
      'vigente. Dúvidas operacionais poderão ser encaminhadas ao suporte '
      'disponível no aplicativo.';

  @override
  Widget build(BuildContext context) {
    return const PolicyScrollPage(
      title: 'Política de uso',
      sections: _secoes,
      rodape: _rodape,
    );
  }
}
