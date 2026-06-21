import 'package:flutter/material.dart';

import '../constants/marketing_leads_status.dart';
import '../services/marketing_leads_service.dart';
import 'centro_operacoes_leads_base_panel.dart';

/// CRM de captação de LOJISTAS (dentro do Centro de operações).
class PainelLeadsLojistas extends StatelessWidget {
  const PainelLeadsLojistas({super.key});

  @override
  Widget build(BuildContext context) {
    return LeadsBasePanel(
      config: LeadConfig(
        colecao: MarketingLeadsService.colecaoLojistas,
        titulo: 'Leads de lojistas',
        descricao:
            'Funil de captação de novos lojistas: do primeiro contato à conversão.',
        icon: Icons.storefront_rounded,
        chaveTitulo: 'nome_fantasia',
        chaveWhatsapp: 'whatsapp',
        statusOrdem: MarketingLeadLojistaStatus.ordem,
        statusInfo: MarketingLeadLojistaStatus.info,
        campos: const [
          LeadCampo(chave: 'razao_social', label: 'Razão social'),
          LeadCampo(
            chave: 'nome_fantasia',
            label: 'Nome fantasia',
            obrigatorio: true,
          ),
          LeadCampo(
            chave: 'responsavel',
            label: 'Responsável',
            exibirNaLista: true,
          ),
          LeadCampo(
            chave: 'whatsapp',
            label: 'WhatsApp',
            telefone: true,
            exibirNaLista: true,
          ),
          LeadCampo(chave: 'email', label: 'E-mail', email: true),
          LeadCampo(chave: 'cidade', label: 'Cidade', exibirNaLista: true),
          LeadCampo(chave: 'estado', label: 'Estado (UF)'),
          LeadCampo(chave: 'categoria', label: 'Categoria'),
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
