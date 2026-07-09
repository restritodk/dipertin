import 'package:cloud_firestore/cloud_firestore.dart';

/// Máscara exibida quando a senha/API key já está salva no servidor.
const kEmailSecretMask = '••••••••';

/// Slugs e rótulos dos templates transacionais.
class EmailTemplateCatalogo {
  static const items = <({String slug, String rotulo})>[
    (slug: 'cobranca', rotulo: 'Cobrança'),
    (slug: 'pagamento_recebido', rotulo: 'Pagamento recebido'),
    (slug: 'pix_gerado', rotulo: 'PIX gerado'),
    (slug: 'pedido_confirmado', rotulo: 'Pedido confirmado'),
    (slug: 'pedido_enviado', rotulo: 'Pedido enviado'),
    (slug: 'pedido_entregue', rotulo: 'Pedido entregue'),
    (slug: 'bem_vindo', rotulo: 'Bem-vindo'),
    (slug: 'recuperacao_senha', rotulo: 'Recuperação de senha'),
    (slug: 'alteracao_senha', rotulo: 'Alteração de senha'),
    (slug: 'cadastro_aprovado', rotulo: 'Cadastro aprovado'),
    (slug: 'cliente_bloqueado', rotulo: 'Cliente bloqueado'),
    (slug: 'cliente_desbloqueado', rotulo: 'Cliente desbloqueado'),
    (slug: 'promocao', rotulo: 'Promoção'),
    (slug: 'aniversario', rotulo: 'Aniversário'),
    (slug: 'lembrete_vencimento', rotulo: 'Lembrete de vencimento'),
    (slug: 'parcela_vencida', rotulo: 'Parcela vencida'),
  ];
}

/// Variáveis disponíveis nos templates.
const kEmailVariaveis = [
  '{cliente}',
  '{cpf}',
  '{email}',
  '{telefone}',
  '{loja}',
  '{cnpj}',
  '{pedido}',
  '{valor}',
  '{desconto}',
  '{juros}',
  '{multa}',
  '{dias_atraso}',
  '{vencimento}',
  '{pix}',
  '{linha_digitavel}',
  '{codigo_barras}',
  '{link}',
  '{numero_parcela}',
  '{quantidade_parcelas}',
  '{data}',
  '{hora}',
  '{cidade}',
  '{estado}',
];

/// Chaves de automação (dias relativos ao vencimento).
const kEmailAutomacaoOpcoes = <({String chave, String rotulo})>[
  (chave: 'd_30_antes', rotulo: '30 dias antes'),
  (chave: 'd_15_antes', rotulo: '15 dias antes'),
  (chave: 'd_7_antes', rotulo: '7 dias antes'),
  (chave: 'd_3_antes', rotulo: '3 dias antes'),
  (chave: 'd_1_antes', rotulo: '1 dia antes'),
  (chave: 'dia_vencimento', rotulo: 'No vencimento'),
  (chave: 'd_1_apos', rotulo: '1 dia após'),
  (chave: 'd_3_apos', rotulo: '3 dias após'),
  (chave: 'd_7_apos', rotulo: '7 dias após'),
  (chave: 'd_15_apos', rotulo: '15 dias após'),
  (chave: 'd_30_apos', rotulo: '30 dias após'),
];

class EmailIdentidadeVisual {
  String logoUrl;
  String corPrincipal;
  String corSecundaria;
  String corBotao;
  String nomeLoja;
  String telefone;
  String whatsapp;
  String instagram;
  String facebook;
  String site;
  String endereco;

  EmailIdentidadeVisual({
    this.logoUrl = '',
    this.corPrincipal = '#6A1B9A',
    this.corSecundaria = '#FF8F00',
    this.corBotao = '#6A1B9A',
    this.nomeLoja = '',
    this.telefone = '',
    this.whatsapp = '',
    this.instagram = '',
    this.facebook = '',
    this.site = '',
    this.endereco = '',
  });

  factory EmailIdentidadeVisual.fromMap(Map<String, dynamic>? m) {
    if (m == null) return EmailIdentidadeVisual();
    return EmailIdentidadeVisual(
      logoUrl: m['logoUrl']?.toString() ?? '',
      corPrincipal: m['corPrincipal']?.toString() ?? '#6A1B9A',
      corSecundaria: m['corSecundaria']?.toString() ?? '#FF8F00',
      corBotao: m['corBotao']?.toString() ?? '#6A1B9A',
      nomeLoja: m['nomeLoja']?.toString() ?? '',
      telefone: m['telefone']?.toString() ?? '',
      whatsapp: m['whatsapp']?.toString() ?? '',
      instagram: m['instagram']?.toString() ?? '',
      facebook: m['facebook']?.toString() ?? '',
      site: m['site']?.toString() ?? '',
      endereco: m['endereco']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toMap() => {
        'logoUrl': logoUrl,
        'corPrincipal': corPrincipal,
        'corSecundaria': corSecundaria,
        'corBotao': corBotao,
        'nomeLoja': nomeLoja,
        'telefone': telefone,
        'whatsapp': whatsapp,
        'instagram': instagram,
        'facebook': facebook,
        'site': site,
        'endereco': endereco,
      };
}

class EmailBlocoTemplate {
  String tipo;
  String conteudo;
  String? url;
  String? textoBotao;
  String? destino;

  EmailBlocoTemplate({
    required this.tipo,
    this.conteudo = '',
    this.url,
    this.textoBotao,
    this.destino,
  });

  factory EmailBlocoTemplate.fromMap(Map<String, dynamic> m) {
    return EmailBlocoTemplate(
      tipo: m['tipo']?.toString() ?? m['type']?.toString() ?? 'texto',
      conteudo: m['conteudo']?.toString() ?? m['text']?.toString() ?? '',
      url: m['url']?.toString(),
      textoBotao: m['textoBotao']?.toString() ?? m['texto']?.toString(),
      destino: m['destino']?.toString() ?? m['link']?.toString(),
    );
  }

  Map<String, dynamic> toMap() {
    final m = <String, dynamic>{'tipo': tipo, 'conteudo': conteudo};
    if (url != null && url!.isNotEmpty) m['url'] = url;
    if (textoBotao != null && textoBotao!.isNotEmpty) {
      m['textoBotao'] = textoBotao;
    }
    if (destino != null && destino!.isNotEmpty) m['destino'] = destino;
    return m;
  }
}

class EmailTemplateModel {
  String slug;
  String assunto;
  List<EmailBlocoTemplate> blocks;
  EmailIdentidadeVisual identidadeVisual;

  EmailTemplateModel({
    required this.slug,
    this.assunto = '',
    List<EmailBlocoTemplate>? blocks,
    EmailIdentidadeVisual? identidadeVisual,
  })  : blocks = blocks ?? [],
        identidadeVisual = identidadeVisual ?? EmailIdentidadeVisual();

  factory EmailTemplateModel.fromFirestore(String slug, Map<String, dynamic>? m) {
    if (m == null) {
      return EmailTemplateModel(slug: slug);
    }
    final bl = <EmailBlocoTemplate>[];
    final raw = m['blocks'];
    if (raw is List) {
      for (final item in raw) {
        if (item is Map) {
          bl.add(EmailBlocoTemplate.fromMap(Map<String, dynamic>.from(item)));
        }
      }
    }
    return EmailTemplateModel(
      slug: slug,
      assunto: m['assunto']?.toString() ?? '',
      blocks: bl,
      identidadeVisual:
          EmailIdentidadeVisual.fromMap(m['identidadeVisual'] as Map<String, dynamic>?),
    );
  }

  Map<String, dynamic> toPayload() => {
        'slug': slug,
        'assunto': assunto,
        'blocks': blocks.map((b) => b.toMap()).toList(),
        'identidadeVisual': identidadeVisual.toMap(),
      };
}

class EmailStatusConfig {
  bool configurado;
  DateTime? ultimoTesteEm;
  bool ultimoTesteOk;
  String ultimoTesteMsg;
  DateTime? ultimoEnvioEm;
  int enviadosHoje;

  EmailStatusConfig({
    this.configurado = false,
    this.ultimoTesteEm,
    this.ultimoTesteOk = false,
    this.ultimoTesteMsg = '',
    this.ultimoEnvioEm,
    this.enviadosHoje = 0,
  });

  factory EmailStatusConfig.fromMap(Map<String, dynamic>? m) {
    if (m == null) return EmailStatusConfig();
    return EmailStatusConfig(
      configurado: m['configurado'] == true,
      ultimoTesteEm: _parseTs(m['ultimoTesteEm']),
      ultimoTesteOk: m['ultimoTesteOk'] == true,
      ultimoTesteMsg: m['ultimoTesteMsg']?.toString() ?? '',
      ultimoEnvioEm: _parseTs(m['ultimoEnvioEm']),
      enviadosHoje: (m['enviadosHoje'] as num?)?.toInt() ?? 0,
    );
  }

  static DateTime? _parseTs(dynamic v) {
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    return null;
  }
}

class EmailConfigAvancada {
  int limitePorMinuto;
  int timeoutSegundos;
  int tentativas;
  int delayEntreTentativas;
  bool ativarLog;
  bool ativarRastreamento;
  bool openTracking;
  bool clickTracking;

  EmailConfigAvancada({
    this.limitePorMinuto = 30,
    this.timeoutSegundos = 30,
    this.tentativas = 3,
    this.delayEntreTentativas = 5,
    this.ativarLog = true,
    this.ativarRastreamento = false,
    this.openTracking = false,
    this.clickTracking = false,
  });

  factory EmailConfigAvancada.fromMap(Map<String, dynamic>? m) {
    if (m == null) return EmailConfigAvancada();
    return EmailConfigAvancada(
      limitePorMinuto: (m['limitePorMinuto'] as num?)?.toInt() ?? 30,
      timeoutSegundos: (m['timeoutSegundos'] as num?)?.toInt() ?? 30,
      tentativas: (m['tentativas'] as num?)?.toInt() ?? 3,
      delayEntreTentativas: (m['delayEntreTentativas'] as num?)?.toInt() ?? 5,
      ativarLog: m['ativarLog'] != false,
      ativarRastreamento: m['ativarRastreamento'] == true,
      openTracking: m['openTracking'] == true,
      clickTracking: m['clickTracking'] == true,
    );
  }

  Map<String, dynamic> toMap() => {
        'limitePorMinuto': limitePorMinuto,
        'timeoutSegundos': timeoutSegundos,
        'tentativas': tentativas,
        'delayEntreTentativas': delayEntreTentativas,
        'ativarLog': ativarLog,
        'ativarRastreamento': ativarRastreamento,
        'openTracking': openTracking,
        'clickTracking': clickTracking,
      };
}

class EmailConfigSmtp {
  String host;
  int port;
  String encryption;
  String user;
  String senha;
  bool temSenhaSalva;
  String fromEmail;
  String fromName;
  String replyTo;

  EmailConfigSmtp({
    this.host = '',
    this.port = 587,
    this.encryption = 'tls',
    this.user = '',
    this.senha = '',
    this.temSenhaSalva = false,
    this.fromEmail = '',
    this.fromName = '',
    this.replyTo = '',
  });

  factory EmailConfigSmtp.fromMap(Map<String, dynamic>? m) {
    if (m == null) return EmailConfigSmtp();
    return EmailConfigSmtp(
      host: m['host']?.toString() ?? '',
      port: (m['port'] as num?)?.toInt() ?? 587,
      encryption: m['encryption']?.toString() ?? 'tls',
      user: m['user']?.toString() ?? '',
      temSenhaSalva: m['temSenha'] == true || (m['senhaEnc']?.toString().isNotEmpty == true),
      fromEmail: m['fromEmail']?.toString() ?? '',
      fromName: m['fromName']?.toString() ?? '',
      replyTo: m['replyTo']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toPayload({required String senhaDigitada}) => {
        'host': host,
        'port': port,
        'encryption': encryption,
        'user': user,
        if (senhaDigitada.isNotEmpty && senhaDigitada != kEmailSecretMask)
          'senha': senhaDigitada,
        'fromEmail': fromEmail,
        'fromName': fromName,
        'replyTo': replyTo,
      };
}

class EmailConfigApi {
  String provider;
  String baseUrl;
  String apiKey;
  bool temApiKeySalva;
  String fromEmail;
  String fromName;
  String replyTo;

  EmailConfigApi({
    this.provider = 'sendgrid',
    this.baseUrl = 'https://api.sendgrid.com',
    this.apiKey = '',
    this.temApiKeySalva = false,
    this.fromEmail = '',
    this.fromName = '',
    this.replyTo = '',
  });

  factory EmailConfigApi.fromMap(Map<String, dynamic>? m) {
    if (m == null) return EmailConfigApi();
    return EmailConfigApi(
      provider: m['provider']?.toString() ?? 'sendgrid',
      baseUrl: m['baseUrl']?.toString() ?? 'https://api.sendgrid.com',
      temApiKeySalva: m['temApiKey'] == true || (m['apiKeyEnc']?.toString().isNotEmpty == true),
      fromEmail: m['fromEmail']?.toString() ?? '',
      fromName: m['fromName']?.toString() ?? '',
      replyTo: m['replyTo']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toPayload({required String apiKeyDigitada}) => {
        'provider': provider,
        'baseUrl': baseUrl,
        if (apiKeyDigitada.isNotEmpty && apiKeyDigitada != kEmailSecretMask)
          'apiKey': apiKeyDigitada,
        'fromEmail': fromEmail,
        'fromName': fromName,
        'replyTo': replyTo,
      };
}

class EmailTransacionalConfig {
  String nome;
  bool ativo;
  String modoIntegracao;
  EmailConfigSmtp smtp;
  EmailConfigApi api;
  EmailConfigAvancada avancado;
  EmailStatusConfig status;
  EmailIdentidadeVisual identidadeVisual;
  Map<String, bool> automacao;

  EmailTransacionalConfig({
    this.nome = 'E-mail',
    this.ativo = false,
    this.modoIntegracao = 'smtp',
    EmailConfigSmtp? smtp,
    EmailConfigApi? api,
    EmailConfigAvancada? avancado,
    EmailStatusConfig? status,
    EmailIdentidadeVisual? identidadeVisual,
    Map<String, bool>? automacao,
  })  : smtp = smtp ?? EmailConfigSmtp(),
        api = api ?? EmailConfigApi(),
        avancado = avancado ?? EmailConfigAvancada(),
        status = status ?? EmailStatusConfig(),
        identidadeVisual = identidadeVisual ?? EmailIdentidadeVisual(),
        automacao = automacao ?? {};

  bool get estaConfigurado {
    if (modoIntegracao == 'api') {
      return (api.temApiKeySalva || api.apiKey.isNotEmpty) &&
          api.fromEmail.trim().isNotEmpty;
    }
    return smtp.host.trim().isNotEmpty &&
        (smtp.temSenhaSalva || smtp.senha.isNotEmpty) &&
        smtp.fromEmail.trim().isNotEmpty;
  }

  factory EmailTransacionalConfig.fromLegacyAndMap({
    required Map<String, dynamic>? legacyEmail,
    required Map<String, dynamic>? etMap,
  }) {
    final legacy = legacyEmail ?? {};
    final et = etMap ?? {};
    final modo = et['modoIntegracao']?.toString() ?? 'smtp';

    var smtp = EmailConfigSmtp.fromMap(et['smtp'] as Map<String, dynamic>?);
    var api = EmailConfigApi.fromMap(et['api'] as Map<String, dynamic>?);

    if (smtp.host.isEmpty && legacy['apiUrl'] != null) {
      final url = legacy['apiUrl'].toString();
      if (modo != 'api' && url.isNotEmpty && !url.startsWith('http')) {
        final parts = url.split(':');
        smtp.host = parts.first;
        if (parts.length > 1) {
          smtp.port = int.tryParse(parts[1]) ?? 587;
        }
      }
    }
    if (smtp.fromEmail.isEmpty) {
      smtp.fromEmail = legacy['emailRemetente']?.toString() ?? '';
    }
    if (smtp.fromName.isEmpty) {
      smtp.fromName = legacy['remetente']?.toString() ?? '';
    }
    if (!smtp.temSenhaSalva && legacy['token']?.toString().isNotEmpty == true) {
      final t = legacy['token'].toString();
      if (t != kEmailSecretMask && t != '••••••••') {
        smtp.senha = t;
      } else {
        smtp.temSenhaSalva = true;
      }
    }
    if (api.fromEmail.isEmpty) {
      api.fromEmail = legacy['emailRemetente']?.toString() ?? '';
    }
    if (api.fromName.isEmpty) {
      api.fromName = legacy['remetente']?.toString() ?? '';
    }
    if (modo == 'api' && api.baseUrl.isEmpty) {
      api.baseUrl = legacy['apiUrl']?.toString() ?? api.baseUrl;
    }

    final autoRaw = et['automacao'] as Map<String, dynamic>?;
    final automacao = <String, bool>{};
    for (final op in kEmailAutomacaoOpcoes) {
      automacao[op.chave] = autoRaw?[op.chave] == true;
    }

    return EmailTransacionalConfig(
      nome: legacy['nome']?.toString() ?? et['nome']?.toString() ?? 'E-mail',
      ativo: legacy['ativo'] == true,
      modoIntegracao: modo,
      smtp: smtp,
      api: api,
      avancado: EmailConfigAvancada.fromMap(et['avancado'] as Map<String, dynamic>?),
      status: EmailStatusConfig.fromMap(et['status'] as Map<String, dynamic>?),
      identidadeVisual: EmailIdentidadeVisual.fromMap(
          et['identidadeVisual'] as Map<String, dynamic>?),
      automacao: automacao,
    );
  }

  Map<String, dynamic> toSalvarPayload({
    required String smtpSenha,
    required String apiKey,
  }) =>
      {
        'nome': nome,
        'ativo': ativo,
        'modoIntegracao': modoIntegracao,
        'smtp': smtp.toPayload(senhaDigitada: smtpSenha),
        'api': api.toPayload(apiKeyDigitada: apiKey),
        'avancado': avancado.toMap(),
        'automacao': automacao,
        'identidadeVisual': identidadeVisual.toMap(),
      };
}

class EmailHistoricoItem {
  final String id;
  final String status;
  final DateTime? criadoEm;
  final String cliente;
  final String assunto;
  final String tipo;
  final String email;
  final String provedor;
  final int tempoMs;
  final String messageId;
  final String respostaTecnica;
  final String logTecnico;
  final String? corpoHtml;

  EmailHistoricoItem({
    required this.id,
    required this.status,
    this.criadoEm,
    this.cliente = '',
    this.assunto = '',
    this.tipo = '',
    this.email = '',
    this.provedor = '',
    this.tempoMs = 0,
    this.messageId = '',
    this.respostaTecnica = '',
    this.logTecnico = '',
    this.corpoHtml,
  });

  factory EmailHistoricoItem.fromMap(String id, Map<String, dynamic> m) {
    DateTime? dt;
    final c = m['criado_em'];
    if (c is Timestamp) dt = c.toDate();
    return EmailHistoricoItem(
      id: id,
      status: m['status']?.toString() ?? '',
      criadoEm: dt,
      cliente: m['cliente']?.toString() ?? m['destinatario']?.toString() ?? '',
      assunto: m['assunto']?.toString() ?? '',
      tipo: m['tipo']?.toString() ?? '',
      email: m['destinatario']?.toString() ?? '',
      provedor: m['provedor']?.toString() ?? '',
      tempoMs: (m['tempo_ms'] as num?)?.toInt() ?? 0,
      messageId: m['message_id']?.toString() ?? '',
      respostaTecnica: m['resposta_tecnica']?.toString() ?? '',
      logTecnico: m['log_tecnico']?.toString() ?? '',
      corpoHtml: m['corpo_html']?.toString(),
    );
  }
}
