import 'package:flutter/material.dart';

import 'package:depertin_cliente/constants/conteudo_legal_padrao.dart';
import 'policy_remote_page.dart';

/// Tratamento de dados pessoais no ecossistema DiPertin (LGPD).
class PoliticaPrivacidadeScreen extends StatelessWidget {
  const PoliticaPrivacidadeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const PolicyRemotePage(
      docId: 'privacidade',
      tituloPadrao: ConteudoLegalPadrao.tituloPrivacidadePadrao,
      secoesPadrao: ConteudoLegalPadrao.secoesPrivacidade,
      rodape: ConteudoLegalPadrao.rodapePrivacidade,
    );
  }
}
