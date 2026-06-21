import 'package:flutter/material.dart';

import '../constants/marketing_leads_status.dart';
import '../services/marketing_leads_service.dart';
import 'centro_operacoes_leads_base_panel.dart';

/// CRM de captação de ENTREGADORES (dentro do Centro de operações).
class PainelLeadsEntregadores extends StatelessWidget {
  const PainelLeadsEntregadores({super.key});

  @override
  Widget build(BuildContext context) {
    return LeadsBasePanel(
      config: LeadConfig(
        colecao: MarketingLeadsService.colecaoEntregadores,
        titulo: 'Leads de entregadores',
        descricao:
            'Funil de captação de novos entregadores: triagem, análise e conversão.',
        icon: Icons.delivery_dining_rounded,
        chaveTitulo: 'nome',
        chaveWhatsapp: 'telefone',
        statusOrdem: MarketingLeadEntregadorStatus.ordem,
        statusInfo: MarketingLeadEntregadorStatus.info,
        campos: const [
          LeadCampo(chave: 'nome', label: 'Nome', obrigatorio: true),
          LeadCampo(chave: 'cpf', label: 'CPF', telefone: true),
          LeadCampo(
            chave: 'telefone',
            label: 'Telefone',
            telefone: true,
            exibirNaLista: true,
          ),
          LeadCampo(chave: 'cidade', label: 'Cidade', exibirNaLista: true),
          LeadCampo(chave: 'veiculo', label: 'Veículo', exibirNaLista: true),
          LeadCampo(chave: 'cnh', label: 'CNH'),
          LeadCampo(
            chave: 'observacoes',
            label: 'Observações',
            multiline: true,
          ),
        ],
      ),
    );
  }
}
