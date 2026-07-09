/// Serviço de envio de e-mail fiscal (DANFE/XML).
///
/// Envia o DANFE e o XML da NF-e para o cliente usando
/// template premium com identidade DiPertin.
///
/// Na versão web, utiliza mailto: como fallback.
/// Em produção, deve ser substituído por Cloud Function com SMTP.
abstract final class FiscalEmailService {
  /// Gera o corpo HTML do e-mail com template premium.
  static String _gerarTemplateHtml({
    required String nomeCliente,
    required String nomeLoja,
    required String numeroNfe,
    required String? chaveAcesso,
    required String? danfeUrl,
    required String? xmlUrl,
    required double valor,
    required String? dataEmissao,
  }) {
    final chave = chaveAcesso ?? '—';
    final danfe = danfeUrl ?? '#';
    final xml = xmlUrl ?? '#';
    final data = dataEmissao ?? '—';
    final valorFormatado = valor.toStringAsFixed(2);

    return '''
<!DOCTYPE html>
<html lang="pt-BR">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body {
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
      background: #F5F4F8; color: #1A1A2E;
    }
    .container {
      max-width: 600px; margin: 24px auto;
      background: #FFFFFF; border-radius: 16px;
      overflow: hidden; box-shadow: 0 1px 3px rgba(0,0,0,0.08);
    }
    .header {
      background: linear-gradient(135deg, #6A1B9A 0%, #8E24AA 100%);
      padding: 32px; text-align: center;
    }
    .header h1 {
      color: #FFFFFF; font-size: 24px; font-weight: 700;
      margin-bottom: 4px;
    }
    .header p {
      color: rgba(255,255,255,0.85); font-size: 14px;
    }
    .body { padding: 24px 32px; }
    .info-row {
      display: flex; justify-content: space-between; padding: 10px 0;
      border-bottom: 1px solid #EEEAF6;
    }
    .info-row:last-child { border-bottom: none; }
    .label { color: #64748B; font-size: 13px; }
    .value { color: #1A1A2E; font-size: 14px; font-weight: 600; }
    .value.destaque { color: #6A1B9A; }
    .acoes {
      padding: 16px 32px 32px; display: flex; gap: 12px;
      justify-content: center;
    }
    .btn {
      display: inline-block; padding: 12px 24px; border-radius: 8px;
      text-decoration: none; font-size: 14px; font-weight: 600;
      transition: all 0.2s;
    }
    .btn-primary {
      background: #6A1B9A; color: #FFFFFF;
    }
    .btn-secondary {
      background: #FFF3E0; color: #FF8F00; border: 1px solid #FFE0B2;
    }
    .footer {
      padding: 16px 32px; background: #F8F7FC; text-align: center;
    }
    .footer p {
      color: #94A3B8; font-size: 12px; line-height: 1.5;
    }
    .chave {
      font-family: 'Courier New', monospace; font-size: 12px;
      color: #64748B; word-break: break-all; margin-top: 12px;
    }
  </style>
</head>
<body>
  <div class="container">
    <div class="header">
      <h1>📄 NF-e Emitida</h1>
      <p>Nota Fiscal Eletrônica — $nomeLoja</p>
    </div>
    <div class="body">
      <p style="margin-bottom:16px;color:#64748B;">
        Olá <strong>$nomeCliente</strong>,
      </p>
      <p style="margin-bottom:20px;color:#64748B;">
        Sua Nota Fiscal Eletrônica foi emitida com sucesso. 
        Abaixo estão os detalhes:
      </p>
      <div style="background:#F8F7FC;border-radius:12px;padding:16px;margin-bottom:20px;">
        <div class="info-row">
          <span class="label">Número NF-e</span>
          <span class="value destaque">$numeroNfe</span>
        </div>
        <div class="info-row">
          <span class="label">Valor</span>
          <span class="value">R\$ $valorFormatado</span>
        </div>
        <div class="info-row">
          <span class="label">Data de Emissão</span>
          <span class="value">$data</span>
        </div>
      </div>
      <div class="chave">
        Chave de Acesso: $chave
      </div>
    </div>
    <div class="acoes">
      <a href="$danfe" class="btn btn-primary" target="_blank">📥 Baixar DANFE</a>
      <a href="$xml" class="btn btn-secondary" target="_blank">📄 Baixar XML</a>
    </div>
    <div class="footer">
      <p>
        Este é um e-mail automático do sistema fiscal DiPertin.<br>
        Em caso de dúvidas, responda a este e-mail ou contate a loja.
      </p>
    </div>
  </div>
</body>
</html>
''';
  }

  /// Gera o link mailto: com o template.
  static String gerarMailTo({
    required String emailCliente,
    required String nomeCliente,
    required String nomeLoja,
    required String numeroNfe,
    required String? chaveAcesso,
    required String? danfeUrl,
    required String? xmlUrl,
    required double valor,
    String? assunto,
  }) {
    final subject = Uri.encodeComponent(
        assunto ?? 'NF-e $numeroNfe - $nomeLoja');
    final body = Uri.encodeComponent(
      'Olá $nomeCliente,\n\n'
      'Sua NF-e $numeroNfe foi emitida por $nomeLoja.\n\n'
      'Chave de Acesso: ${chaveAcesso ?? "—"}\n'
      'Valor: R\$ ${valor.toStringAsFixed(2)}\n\n'
      'DANFE: $danfeUrl\n'
      'XML: $xmlUrl\n\n'
      'Equipe DiPertin',
    );
    return 'mailto:$emailCliente?subject=$subject&body=$body';
  }

  /// Prepara os parâmetros para a Cloud Function de envio (quando disponível).
  static Map<String, dynamic> prepararPayloadCloudFunction({
    required String emailCliente,
    required String nomeCliente,
    required String nomeLoja,
    required String numeroNfe,
    required String? chaveAcesso,
    required String? danfeUrl,
    required String? xmlUrl,
    required double valor,
    String? dataEmissao,
  }) {
    return {
      'to': emailCliente,
      'subject': 'NF-e $numeroNfe - $nomeLoja',
      'html': _gerarTemplateHtml(
        nomeCliente: nomeCliente,
        nomeLoja: nomeLoja,
        numeroNfe: numeroNfe,
        chaveAcesso: chaveAcesso,
        danfeUrl: danfeUrl,
        xmlUrl: xmlUrl,
        valor: valor,
        dataEmissao: dataEmissao,
      ),
      'attachments': [
        if (danfeUrl != null) {'url': danfeUrl, 'filename': 'DANFE_$numeroNfe.pdf'},
        if (xmlUrl != null) {'url': xmlUrl, 'filename': 'NFE_$numeroNfe.xml'},
      ],
    };
  }
}
