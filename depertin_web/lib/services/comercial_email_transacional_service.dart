import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'package:depertin_web/models/comercial_email_transacional.dart';
import 'package:depertin_web/services/firebase_functions_config.dart';

class ComercialEmailTransacionalService {
  ComercialEmailTransacionalService._();
  static final instance = ComercialEmailTransacionalService._();

  Future<EmailTransacionalConfig> carregarConfig(String lojaId) async {
    final doc = await FirebaseFirestore.instance
        .collection('gestao_comercial_configuracoes')
        .doc(lojaId)
        .get();
    final cobranca = (doc.data() ?? {})['cobranca'] as Map<String, dynamic>?;
    final email = cobranca?['email'] as Map<String, dynamic>?;
    final et = email?['emailTransacional'] as Map<String, dynamic>?;
    return EmailTransacionalConfig.fromLegacyAndMap(
      legacyEmail: email,
      etMap: et,
    );
  }

  Future<EmailIdentidadeVisual> carregarIdentidadeLoja(String lojaId) async {
    final snap = await FirebaseFirestore.instance.collection('users').doc(lojaId).get();
    final d = snap.data() ?? {};
    final nome = d['loja_nome']?.toString() ??
        d['nome_loja']?.toString() ??
        d['nome_fantasia']?.toString() ??
        d['nome']?.toString() ??
        '';
    return EmailIdentidadeVisual(
      nomeLoja: nome,
      telefone: d['telefone']?.toString() ?? '',
      whatsapp: d['whatsapp']?.toString() ?? d['telefone']?.toString() ?? '',
      site: d['site']?.toString() ?? '',
      endereco: d['endereco']?.toString() ?? '',
      logoUrl: d['foto_logo']?.toString() ??
          d['foto_perfil']?.toString() ??
          d['foto']?.toString() ??
          '',
    );
  }

  Future<Map<String, dynamic>> salvarConfig(
    String lojaId,
    EmailTransacionalConfig config, {
    required String smtpSenha,
    required String apiKey,
  }) async {
    return callFirebaseFunctionSafe(
      'gestaoComercialEmailSalvarConfig',
      region: kFirebaseFunctionsRegionEmailGc,
      parameters: {
        'lojaId': lojaId,
        'config': config.toSalvarPayload(smtpSenha: smtpSenha, apiKey: apiKey),
      },
    );
  }

  Future<Map<String, dynamic>> testarSmtp(
    String lojaId,
    EmailConfigSmtp smtp, {
    required String senha,
  }) async {
    return callFirebaseFunctionSafe(
      'gestaoComercialEmailTestarSmtp',
      region: kFirebaseFunctionsRegionEmailGc,
      parameters: {
        'lojaId': lojaId,
        'smtp': smtp.toPayload(senhaDigitada: senha),
      },
    );
  }

  Future<Map<String, dynamic>> testarApi(
    String lojaId,
    EmailConfigApi api, {
    required String apiKey,
  }) async {
    return callFirebaseFunctionSafe(
      'gestaoComercialEmailTestarApi',
      region: kFirebaseFunctionsRegionEmailGc,
      parameters: {
        'lojaId': lojaId,
        'api': api.toPayload(apiKeyDigitada: apiKey),
      },
    );
  }

  Future<Map<String, dynamic>> enviarTeste(
    String lojaId,
    String destino,
  ) async {
    return callFirebaseFunctionSafe(
      'gestaoComercialEmailEnviarTeste',
      region: kFirebaseFunctionsRegionEmailGc,
      parameters: {'lojaId': lojaId, 'destino': destino},
    );
  }

  Future<void> inicializarTemplates(String lojaId) async {
    await callFirebaseFunctionSafe(
      'gestaoComercialEmailInicializarTemplates',
      region: kFirebaseFunctionsRegionEmailGc,
      parameters: {'lojaId': lojaId},
    );
  }

  Future<EmailTemplateModel?> carregarTemplate(String lojaId, String slug) async {
    final snap = await FirebaseFirestore.instance
        .collection('gestao_comercial_email_templates')
        .doc(lojaId)
        .collection('templates')
        .doc(slug)
        .get();
    if (!snap.exists) return null;
    return EmailTemplateModel.fromFirestore(slug, snap.data());
  }

  Stream<List<EmailHistoricoItem>> streamHistorico(String lojaId, {int limite = 100}) {
    return FirebaseFirestore.instance
        .collection('gestao_comercial_email_historico')
        .doc(lojaId)
        .collection('envios')
        .orderBy('criado_em', descending: true)
        .limit(limite)
        .snapshots()
        .map((s) => s.docs
            .map((d) => EmailHistoricoItem.fromMap(d.id, d.data()))
            .toList());
  }

  Future<Map<String, dynamic>> salvarTemplate(
    String lojaId,
    EmailTemplateModel template,
  ) async {
    return callFirebaseFunctionSafe(
      'gestaoComercialEmailSalvarTemplate',
      region: kFirebaseFunctionsRegionEmailGc,
      parameters: {
        'lojaId': lojaId,
        ...template.toPayload(),
      },
    );
  }

  Future<Map<String, dynamic>> enviarTemplateTeste({
    required String lojaId,
    required String destino,
    required EmailTemplateModel template,
  }) async {
    return callFirebaseFunctionSafe(
      'gestaoComercialEmailEnviarTemplateTeste',
      region: kFirebaseFunctionsRegionEmailGc,
      parameters: {
        'lojaId': lojaId,
        'destino': destino,
        ...template.toPayload(),
      },
    );
  }
}

/// Dados fictícios para preview local.
const kEmailPreviewVars = <String, String>{
  'cliente': 'Maria Silva',
  'cpf': '123.456.789-00',
  'email': 'maria@email.com',
  'telefone': '(44) 99999-0000',
  'loja': 'Loja Exemplo',
  'cnpj': '12.345.678/0001-90',
  'pedido': 'PED-000042',
  'valor': 'R\$ 150,00',
  'desconto': 'R\$ 10,00',
  'juros': 'R\$ 2,50',
  'multa': 'R\$ 5,00',
  'dias_atraso': '3',
  'vencimento': '15/07/2026',
  'pix': '00020126580014BR.GOV.BCB.PIX...',
  'linha_digitavel': '23793.38128 60000.000000 00000.000000 1 84370000015000',
  'codigo_barras': '23793381286000000000000000000000000000001500',
  'link': 'https://www.dipertin.com.br/pagar/exemplo',
  'numero_parcela': '2',
  'quantidade_parcelas': '6',
  'data': '27/06/2026',
  'hora': '14:30',
  'cidade': 'Toledo',
  'estado': 'PR',
};

String substituirVariaveisEmail(String texto, Map<String, String> vars) {
  var out = texto;
  for (final e in vars.entries) {
    out = out.replaceAll('{${e.key}}', e.value);
  }
  return out;
}

Color? parseHexColor(String hex) {
  var h = hex.replaceAll('#', '').trim();
  if (h.length == 6) h = 'FF$h';
  if (h.length != 8) return null;
  return Color(int.parse(h, radix: 16));
}
