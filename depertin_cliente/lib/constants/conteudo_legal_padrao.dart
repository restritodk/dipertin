import 'package:depertin_cliente/screens/comum/politicas/policy_scroll_page.dart';

/// Texto jurídico padrão (espelho do app). Usado como fallback e para pré-preencher o painel.
abstract final class ConteudoLegalPadrao {
  static const List<PolicySection> secoesUso = [
    PolicySection(
      titulo: 'Identificação da empresa',
      corpo:
          'DiPertin\n'
          'CNPJ: 66.040.998/0001-66\n'
          'Telefone: (66) 3180-0107\n'
          'E-mail: contato@dipertin.com.br',
    ),
    PolicySection(
      titulo: 'I — Objeto, natureza jurídica e aceitação',
      corpo:
          'O presente instrumento constitui a Política de Uso (doravante apenas '
          '"Política") do ecossistema digital DiPertin, compreendendo aplicativo '
          'móvel e serviços associados, caracterizado como plataforma de '
          'intermediação de marketplace local, mediante tecnologia '
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

  static const List<PolicySection> secoesCompra = [
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

  static const List<PolicySection> secoesPrivacidade = [
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

  static String textoFirestoreUso() => secoesParaCampoConteudo(secoesUso);
  static String textoFirestoreCompra() => secoesParaCampoConteudo(secoesCompra);
  static String textoFirestorePrivacidade() =>
      secoesParaCampoConteudo(secoesPrivacidade);

  /// Formato aceito pelo app (parse ## no painel / PolicyRemotePage).
  static String secoesParaCampoConteudo(List<PolicySection> secoes) {
    final buf = StringBuffer();
    for (final s in secoes) {
      if (buf.isNotEmpty) buf.writeln();
      if (s.titulo != null && s.titulo!.trim().isNotEmpty) {
        buf.writeln('## ${s.titulo!.trim()}');
        buf.writeln();
      }
      buf.writeln(s.corpo.trim());
    }
    return buf.toString().trim();
  }

  static const String tituloUsoPadrao = 'Política de uso';
  static const String tituloCompraPadrao = 'Política de compra';
  static const String tituloPrivacidadePadrao = 'Política de privacidade';

  static const String rodapeUso =
      'As partes reconhecem que a leitura deste documento não substitui '
      'consultoria jurídica personalizada. Em caso de conflito entre o texto '
      'aqui exibido e dispositivo legal imperativo, prevalecerá a legislação '
      'vigente. Dúvidas operacionais poderão ser encaminhadas ao suporte '
      'disponível no aplicativo.';

  static const String rodapeCompra =
      'Promoções, combos, garantias específicas de produto ou condições '
      'comerciais adicionais podem ser estabelecidas pelo lojista e devem ser '
      'observadas no momento da contratação, sem prejuízo de direitos do '
      'consumidor previstos em lei.';

  static const String rodapePrivacidade =
      'Este documento tem finalidade de transparência e conformidade com a LGPD '
      'e não substitui parecer jurídico individualizado. Em caso de dúvida sobre '
      'direitos ou tratamentos, utilize o suporte no aplicativo.';
}
