import 'package:flutter/material.dart';

import 'package:depertin_cliente/constants/conteudo_legal_padrao.dart';
import 'policy_remote_page.dart';

/// Termos gerais de uso da plataforma DiPertin.
class PoliticaUsoScreen extends StatelessWidget {
  const PoliticaUsoScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const PolicyRemotePage(
      docId: 'termos',
      tituloPadrao: ConteudoLegalPadrao.tituloUsoPadrao,
      secoesPadrao: ConteudoLegalPadrao.secoesUso,
      rodape: ConteudoLegalPadrao.rodapeUso,
    );
  }
}
