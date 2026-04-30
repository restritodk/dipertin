import 'package:flutter/material.dart';

import 'package:depertin_cliente/constants/conteudo_legal_padrao.dart';
import 'policy_remote_page.dart';

/// Condições de compra, pedido, pagamento e entrega no DiPertin.
class PoliticaCompraScreen extends StatelessWidget {
  const PoliticaCompraScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const PolicyRemotePage(
      docId: 'compra',
      tituloPadrao: ConteudoLegalPadrao.tituloCompraPadrao,
      secoesPadrao: ConteudoLegalPadrao.secoesCompra,
      rodape: ConteudoLegalPadrao.rodapeCompra,
    );
  }
}
