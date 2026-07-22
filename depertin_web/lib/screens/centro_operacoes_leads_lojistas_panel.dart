import 'package:flutter/material.dart';

import '../constants/marketing_leads_status.dart';
import '../services/marketing_leads_service.dart';
import 'centro_operacoes_leads_base_panel.dart';

/// CRM de captação de LOJISTAS (dentro do Centro de operações).
///
/// Campos do modal (sem Veículo/CNH — exclusivos do funil de entregadores):
/// Nome *, CPF, Telefone, Cidade, Observações + Status no funil.
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
        chaveTitulo: 'nome',
        chaveWhatsapp: 'telefone',
        statusOrdem: MarketingLeadLojistaStatus.ordem,
        statusInfo: MarketingLeadLojistaStatus.info,
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
