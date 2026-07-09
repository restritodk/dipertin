import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:depertin_web/services/firebase_functions_config.dart';
import 'package:depertin_web/theme/painel_admin_theme.dart';
import 'package:depertin_web/utils/lojista_painel_context.dart';
import 'package:depertin_web/widgets/comercial/comercial_email_transacional_modal.dart';
import 'package:depertin_web/widgets/dipertin_feedback_premium_modal.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

// =============================================================================
// INTEGRAÇÕES DE PAGAMENTO — WEBHOOK DIpertin + PROVEDORES
// =============================================================================

const _kWebhookBasePlanos =
    'https://southamerica-east1-depertin-f940f.cloudfunctions.net';

const _tiposIntegracaoPagamento = [
  'mercado_pago',
  'asaas',
  'cora',
  'banco_itaú',
  'banco_bradesco',
  'banco_santander',
  'banco_do_brasil',
  'sicoob',
  'sicredi',
  'stone',
  'pagseguro',
  'api_personalizada',
];

String webhookUrlIntegracao(String tipo) =>
    '$_kWebhookBasePlanos/gestaoComercialConfirmarPagamentoMpToken';

String _nomeTipoIntegracao(String tipo) {
  const nomes = {
    'mercado_pago': 'Mercado Pago',
    'asaas': 'Asaas',
    'cora': 'Banco Cora',
    'banco_itaú': 'Banco Itaú',
    'banco_itau': 'Banco Itaú',
    'banco_bradesco': 'Banco Bradesco',
    'banco_santander': 'Banco Santander',
    'banco_do_brasil': 'Banco do Brasil',
    'sicoob': 'Sicoob',
    'sicredi': 'Sicredi',
    'stone': 'Stone',
    'pagseguro': 'PagSeguro',
    'api_personalizada': 'API Personalizada',
  };
  return nomes[tipo] ?? tipo;
}

String? _chavePorNomeIntegracao(String nome) {
  for (final t in _tiposIntegracaoPagamento) {
    if (_nomeTipoIntegracao(t) == nome) return t;
  }
  return null;
}

void _aplicarDefaultsIntegracao(_IntegracaoPagamento edit, String chave) {
  edit.tipo = chave;
  edit.provedor = chave;
  edit.nome = _nomeTipoIntegracao(chave);
  edit.webhookUrl = webhookUrlIntegracao(chave);
  if (edit.token.trim().isNotEmpty) {
    edit.ativo = true;
  }
}

/// Aplica defaults ao iniciar uma nova integração (sempre sobrescreve nome).
/// Usado no botão "Continuar" do modal de nova integração.
void _iniciarDefaultsIntegracao(_IntegracaoPagamento edit, String chave) {
  edit.tipo = chave;
  edit.provedor = chave;
  edit.nome = _nomeTipoIntegracao(chave);
  edit.webhookUrl = webhookUrlIntegracao(chave);
  edit.ambiente = 'producao';
  edit.apiUrl = '';
  edit.clientId = '';
  edit.clientSecret = '';
  edit.token = '';
  edit.ativo = false;
}

bool _integracaoUsaCredenciaisPadrao(String tipo) => tipo != 'api_personalizada';

// =============================================================================
// MODELOS DE DADOS
// =============================================================================

class _ConfigComercial {
  _JurosMultas jurosMultas;
  Map<String, _IntegracaoPagamento> pagamentos;
  Map<String, _CanalCobranca> cobranca;
  _RegrasAutomaticas regrasAutomaticas;
  DateTime? updatedAt;

  _ConfigComercial({
    _JurosMultas? jurosMultas,
    Map<String, _IntegracaoPagamento>? pagamentos,
    Map<String, _CanalCobranca>? cobranca,
    _RegrasAutomaticas? regrasAutomaticas,
    this.updatedAt,
  })  : jurosMultas = jurosMultas ?? _JurosMultas(),
        pagamentos = pagamentos ?? {},
        cobranca = cobranca ?? {},
        regrasAutomaticas = regrasAutomaticas ?? _RegrasAutomaticas();

  factory _ConfigComercial.fromMap(Map<String, dynamic>? m) {
    if (m == null) return _ConfigComercial();
    final jm = m['jurosMultas'] as Map<String, dynamic>?;
    final pgs = m['pagamentos'] as Map<String, dynamic>?;
    final cob = m['cobranca'] as Map<String, dynamic>?;
    final ra = m['regrasAutomaticas'] as Map<String, dynamic>?;
    return _ConfigComercial(
      jurosMultas: _JurosMultas.fromMap(jm),
      pagamentos: _parsePagamentos(pgs),
      cobranca: _parseCobranca(cob),
      regrasAutomaticas: _RegrasAutomaticas.fromMap(ra),
      updatedAt: _parseDt(m['updatedAt']),
    );
  }

  Map<String, dynamic> toMap(String lojaId) => {
        'loja_id': lojaId,
        'jurosMultas': jurosMultas.toMap(),
        'pagamentos': _mapPagamentosToJson(pagamentos),
        'cobranca': _mapCanaisToJson(cobranca),
        'regrasAutomaticas': regrasAutomaticas.toMap(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

  static DateTime? _parseDt(dynamic v) {
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    return null;
  }

  static Map<String, _IntegracaoPagamento> _parsePagamentos(
      Map<String, dynamic>? m) {
    final r = <String, _IntegracaoPagamento>{};
    if (m == null) return r;
    for (final e in m.entries) {
      if (e.value is Map) {
        r[e.key] = _IntegracaoPagamento.fromMap(
            Map<String, dynamic>.from(e.value as Map));
      }
    }
    return r;
  }

  static Map<String, dynamic> _mapPagamentosToJson(
      Map<String, _IntegracaoPagamento> m) {
    return m.map((k, v) => MapEntry(k, v.toMap()));
  }

  static Map<String, _CanalCobranca> _parseCobranca(
      Map<String, dynamic>? m) {
    final r = <String, _CanalCobranca>{};
    if (m == null) return r;
    for (final e in m.entries) {
      if (e.value is Map) {
        r[e.key] = _CanalCobranca.fromMap(
            Map<String, dynamic>.from(e.value as Map));
      }
    }
    return r;
  }

  static Map<String, dynamic> _mapCanaisToJson(
      Map<String, _CanalCobranca> m) {
    return m.map((k, v) => MapEntry(k, v.toMap()));
  }
}

class _JurosMultas {
  bool cobrarMulta;
  double percentualMulta;
  bool cobrarJuros;
  double percentualJurosDia;
  int diasTolerancia;
  bool aplicarMultaUnica;
  bool aplicarJurosAoDia;

  _JurosMultas({
    this.cobrarMulta = false,
    this.percentualMulta = 2.0,
    this.cobrarJuros = false,
    this.percentualJurosDia = 0.033,
    this.diasTolerancia = 0,
    this.aplicarMultaUnica = true,
    this.aplicarJurosAoDia = true,
  });

  factory _JurosMultas.fromMap(Map<String, dynamic>? m) {
    if (m == null) return _JurosMultas();
    return _JurosMultas(
      cobrarMulta: m['cobrarMulta'] == true,
      percentualMulta: (m['percentualMulta'] as num?)?.toDouble() ?? 2.0,
      cobrarJuros: m['cobrarJuros'] == true,
      percentualJurosDia:
          (m['percentualJurosDia'] as num?)?.toDouble() ?? 0.033,
      diasTolerancia: (m['diasTolerancia'] as num?)?.toInt() ?? 0,
      aplicarMultaUnica: m['aplicarMultaUnica'] != false,
      aplicarJurosAoDia: m['aplicarJurosAoDia'] != false,
    );
  }

  Map<String, dynamic> toMap() => {
        'cobrarMulta': cobrarMulta,
        'percentualMulta': percentualMulta,
        'cobrarJuros': cobrarJuros,
        'percentualJurosDia': percentualJurosDia,
        'diasTolerancia': diasTolerancia,
        'aplicarMultaUnica': aplicarMultaUnica,
        'aplicarJurosAoDia': aplicarJurosAoDia,
      };
}

class _IntegracaoPagamento {
  String nome;
  String provedor;
  String tipo;
  String ambiente;
  String apiUrl;
  String clientId;
  String clientSecret;
  String token;
  String webhookUrl;
  bool ativo;

  _IntegracaoPagamento({
    this.nome = '',
    this.provedor = '',
    this.tipo = 'PIX',
    this.ambiente = 'producao',
    this.apiUrl = '',
    this.clientId = '',
    this.clientSecret = '',
    this.token = '',
    this.webhookUrl = '',
    this.ativo = false,
  });

  bool get configurado =>
      token.trim().isNotEmpty ||
      nome.isNotEmpty ||
      apiUrl.isNotEmpty;

  factory _IntegracaoPagamento.fromMap(Map<String, dynamic>? m) {
    if (m == null) return _IntegracaoPagamento();
    return _IntegracaoPagamento(
      nome: m['nome']?.toString() ?? '',
      provedor: m['provedor']?.toString() ?? '',
      tipo: m['tipo']?.toString() ?? 'PIX',
      ambiente: m['ambiente']?.toString() ?? 'producao',
      apiUrl: m['apiUrl']?.toString() ?? '',
      clientId: m['clientId']?.toString() ?? '',
      clientSecret: m['clientSecret']?.toString() ?? '',
      token: m['token']?.toString() ?? '',
      webhookUrl: m['webhookUrl']?.toString() ?? '',
      ativo: m['ativo'] == true,
    );
  }

  Map<String, dynamic> toMap() => {
        'nome': nome,
        'provedor': provedor,
        'tipo': tipo,
        'ambiente': ambiente,
        'apiUrl': apiUrl,
        'clientId': clientId,
        'clientSecret': clientSecret,
        'token': token,
        'webhookUrl': webhookUrl,
        'ativo': ativo,
      };
}

class _CanalCobranca {
  String nome;
  String tipo;
  String apiUrl;
  String token;
  String remetente;
  String emailRemetente;
  String templateMensagem;
  bool ativo;
  Map<String, dynamic>? emailTransacional;

  _CanalCobranca({
    this.nome = '',
    this.tipo = 'whatsapp',
    this.apiUrl = '',
    this.token = '',
    this.remetente = '',
    this.emailRemetente = '',
    this.templateMensagem = '',
    this.ativo = false,
    this.emailTransacional,
  });

  bool get configurado => nome.isNotEmpty || apiUrl.isNotEmpty || token.isNotEmpty;

  bool estaConfigurado(String chave) {
    switch (chave) {
      case 'whatsapp':
        return apiUrl.trim().isNotEmpty && token.trim().isNotEmpty;
      case 'email':
        final et = emailTransacional;
        if (et != null) {
          final modo = et['modoIntegracao']?.toString() ?? 'smtp';
          if (modo == 'api') {
            final api = et['api'] as Map<String, dynamic>?;
            return (api?['apiKeyEnc']?.toString().isNotEmpty == true ||
                    token.trim().isNotEmpty) &&
                (api?['fromEmail']?.toString().trim().isNotEmpty == true ||
                    emailRemetente.trim().isNotEmpty);
          }
          final smtp = et['smtp'] as Map<String, dynamic>?;
          return smtp?['host']?.toString().trim().isNotEmpty == true &&
              (smtp?['senhaEnc']?.toString().isNotEmpty == true ||
                  token.trim().isNotEmpty) &&
              (smtp?['fromEmail']?.toString().trim().isNotEmpty == true ||
                  emailRemetente.trim().isNotEmpty);
        }
        return apiUrl.trim().isNotEmpty &&
            token.trim().isNotEmpty &&
            emailRemetente.trim().isNotEmpty;
      case 'sms':
        return token.trim().isNotEmpty;
      case 'api_externa':
        return apiUrl.trim().isNotEmpty && token.trim().isNotEmpty;
      default:
        return configurado;
    }
  }

  factory _CanalCobranca.fromMap(Map<String, dynamic>? m) {
    if (m == null) return _CanalCobranca();
    return _CanalCobranca(
      nome: m['nome']?.toString() ?? '',
      tipo: _CanalCobranca.normalizarTipo(m['tipo']?.toString()),
      apiUrl: m['apiUrl']?.toString() ?? '',
      token: m['token']?.toString() ?? '',
      remetente: m['remetente']?.toString() ?? '',
      emailRemetente: m['emailRemetente']?.toString() ?? '',
      templateMensagem: m['templateMensagem']?.toString() ?? '',
      ativo: m['ativo'] == true,
      emailTransacional: m['emailTransacional'] is Map
          ? Map<String, dynamic>.from(m['emailTransacional'] as Map)
          : null,
    );
  }

  static String normalizarTipo(String? raw) {
    final t = (raw ?? 'whatsapp').trim();
    const mapa = {
      'whatsapp': 'whatsapp',
      'WhatsApp': 'whatsapp',
      'email': 'email',
      'E-mail': 'email',
      'e-mail': 'email',
      'sms': 'sms',
      'SMS': 'sms',
      'webhook': 'webhook',
      'Webhook': 'webhook',
      'api_externa': 'api_externa',
      'API Externa': 'api_externa',
    };
    return mapa[t] ?? t.toLowerCase().replaceAll(' ', '_');
  }

  Map<String, dynamic> toMap() => {
        'nome': nome,
        'tipo': tipo,
        'apiUrl': apiUrl,
        'token': token,
        'remetente': remetente,
        'emailRemetente': emailRemetente,
        'templateMensagem': templateMensagem,
        'ativo': ativo,
        if (emailTransacional != null) 'emailTransacional': emailTransacional,
      };
}

class _RegrasAutomaticas {
  bool lembreteAntes;
  int diasAntes;
  bool lembreteNoVencimento;
  bool lembreteApos;
  int diasApos;
  int repetirACadaDias;
  bool bloquearCreditoAutomaticamente;
  int bloquearAposDias;
  bool enviarAvisoBloqueio;

  _RegrasAutomaticas({
    this.lembreteAntes = false,
    this.diasAntes = 3,
    this.lembreteNoVencimento = false,
    this.lembreteApos = false,
    this.diasApos = 1,
    this.repetirACadaDias = 3,
    this.bloquearCreditoAutomaticamente = false,
    this.bloquearAposDias = 15,
    this.enviarAvisoBloqueio = false,
  });

  factory _RegrasAutomaticas.fromMap(Map<String, dynamic>? m) {
    if (m == null) return _RegrasAutomaticas();
    return _RegrasAutomaticas(
      lembreteAntes: m['lembreteAntes'] == true,
      diasAntes: (m['diasAntes'] as num?)?.toInt() ?? 3,
      lembreteNoVencimento: m['lembreteNoVencimento'] == true,
      lembreteApos: m['lembreteApos'] == true,
      diasApos: (m['diasApos'] as num?)?.toInt() ?? 1,
      repetirACadaDias: (m['repetirACadaDias'] as num?)?.toInt() ?? 3,
      bloquearCreditoAutomaticamente:
          m['bloquearCreditoAutomaticamente'] == true,
      bloquearAposDias: (m['bloquearAposDias'] as num?)?.toInt() ?? 15,
      enviarAvisoBloqueio: m['enviarAvisoBloqueio'] == true,
    );
  }

  Map<String, dynamic> toMap() => {
        'lembreteAntes': lembreteAntes,
        'diasAntes': diasAntes,
        'lembreteNoVencimento': lembreteNoVencimento,
        'lembreteApos': lembreteApos,
        'diasApos': diasApos,
        'repetirACadaDias': repetirACadaDias,
        'bloquearCreditoAutomaticamente': bloquearCreditoAutomaticamente,
        'bloquearAposDias': bloquearAposDias,
        'enviarAvisoBloqueio': enviarAvisoBloqueio,
      };
}

// =============================================================================
// FORMATTERS
// =============================================================================

/// Máscara de telefone: (XX) XXXXX-XXXX
class _TelefoneInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return newValue.copyWith(text: '');
    final buf = StringBuffer();
    for (int i = 0; i < digits.length; i++) {
      if (i == 0) {
        buf.write('(${digits[i]}');
      } else if (i == 2) {
        buf.write(') ${digits[i]}');
      } else if (i == 7 && digits.length > 10) {
        buf.write('-${digits[i]}');
      } else if (i == 6 && digits.length <= 10) {
        buf.write('-${digits[i]}');
      } else {
        buf.write(digits[i]);
      }
    }
    // Limita a 15 caracteres (11 dígitos com máscara)
    final masked = buf.toString().substring(0, buf.length.clamp(0, 16));
    return TextEditingValue(
      text: masked,
      selection: TextSelection.collapsed(offset: masked.length),
    );
  }
}

// =============================================================================
// TELA PRINCIPAL
// =============================================================================

class ComercialConfiguracoesScreen extends StatefulWidget {
  const ComercialConfiguracoesScreen({super.key});

  @override
  State<ComercialConfiguracoesScreen> createState() =>
      _ComercialConfiguracoesScreenState();
}

class _ComercialConfiguracoesScreenState
    extends State<ComercialConfiguracoesScreen> {
  int _abaAtual = 0;
  bool _carregando = true;
  bool _salvando = false;
  bool _erro = false;
  String _lojaId = '';
  _ConfigComercial _config = _ConfigComercial();
  final _moedaFmt = NumberFormat.currency(locale: 'pt_BR', symbol: r'R$');

  // Controladores para pré-visualização
  final _prevValorCtrl = TextEditingController(text: '100');
  final _prevDiasCtrl = TextEditingController(text: '5');

  @override
  void dispose() {
    _prevValorCtrl.dispose();
    _prevDiasCtrl.dispose();
    super.dispose();
  }

  Future<void> _carregar(String uidLoja) async {
    setState(() {
      _carregando = true;
      _erro = false;
    });
    try {
      final doc = await FirebaseFirestore.instance
          .collection('gestao_comercial_configuracoes')
          .doc(uidLoja)
          .get();
      if (!mounted) return;
      final data = doc.data();
      setState(() {
        _config = _ConfigComercial.fromMap(data);
        _carregando = false;
      });
    } catch (e) {
      if (!mounted) return;
      debugPrint('Erro ao carregar config comercial: $e');
      setState(() {
        _erro = true;
        _carregando = false;
      });
    }
  }

  Future<void> _salvar({
    String? tituloSucesso,
    String? mensagemSucesso,
  }) async {
    if (_lojaId.isEmpty) return;
    setState(() => _salvando = true);
    try {
      await FirebaseFirestore.instance
          .collection('gestao_comercial_configuracoes')
          .doc(_lojaId)
          .set(_config.toMap(_lojaId), SetOptions(merge: true));

      if (!mounted) return;
      setState(() => _salvando = false);
      await mostrarDiPertinFeedbackPremium(
        context,
        sucesso: true,
        titulo: tituloSucesso ?? 'Configurações salvas',
        mensagem: mensagemSucesso ??
            'Suas preferências comerciais foram gravadas com sucesso.',
        botaoTexto: 'Perfeito',
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _salvando = false);
      await mostrarDiPertinFeedbackPremium(
        context,
        sucesso: false,
        titulo: 'Não foi possível salvar',
        mensagem:
            'Ocorreu um erro ao gravar as configurações. Verifique sua conexão e tente novamente.',
        botaoTexto: 'Tentar depois',
      );
    }
  }

  List<DiPertinFeedbackDetalhe> _detalhesResultadoTesteMp(
    Map<String, dynamic> result,
  ) {
    final detalhes = <DiPertinFeedbackDetalhe>[];
    final liveMode = result['live_mode'];
    if (liveMode != null) {
      detalhes.add(DiPertinFeedbackDetalhe(
        rotulo: 'Ambiente',
        valor: liveMode == true ? 'Produção (live)' : 'Sandbox / teste',
        icone: Icons.public_rounded,
      ));
    }
    final chaveTipo = result['chave_tipo']?.toString();
    if (chaveTipo != null && chaveTipo.isNotEmpty) {
      detalhes.add(DiPertinFeedbackDetalhe(
        rotulo: 'Chave PIX no QR',
        valor: chaveTipo,
        icone: Icons.qr_code_2_rounded,
      ));
    }
    final collectorId = result['collector_id']?.toString();
    if (collectorId != null && collectorId.isNotEmpty) {
      detalhes.add(DiPertinFeedbackDetalhe(
        rotulo: 'Conta Mercado Pago',
        valor: collectorId,
        icone: Icons.account_balance_wallet_outlined,
      ));
    }
    return detalhes;
  }

  double _calcularMultaPreview() {
    if (!_config.jurosMultas.cobrarMulta) return 0;
    final valor =
        double.tryParse(_prevValorCtrl.text.replaceAll(',', '.')) ?? 0;
    return valor * (_config.jurosMultas.percentualMulta / 100);
  }

  double _calcularJurosPreview() {
    if (!_config.jurosMultas.cobrarJuros) return 0;
    final valor =
        double.tryParse(_prevValorCtrl.text.replaceAll(',', '.')) ?? 0;
    final dias = _prevDiasCtrl.text.isEmpty
        ? 0
        : int.tryParse(_prevDiasCtrl.text) ?? 0;
    final diasEfetivos = (dias - _config.jurosMultas.diasTolerancia).clamp(0, 999);
    return valor * (_config.jurosMultas.percentualJurosDia / 100) * diasEfetivos;
  }

  void _atualizarPreview() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return LojistaUidLojaBuilder(
      builder: (context, authUid, uidLoja, dadosUsuario) {
        if (uidLoja.isEmpty) {
          return const Scaffold(
            backgroundColor: Color(0xFFF5F7FA),
            body: Center(
              child: CircularProgressIndicator(color: PainelAdminTheme.roxo),
            ),
          );
        }
        if (_lojaId != uidLoja) {
          _lojaId = uidLoja;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _carregar(uidLoja);
          });
        }
        return Scaffold(
          backgroundColor: const Color(0xFFF5F7FA),
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(),
                  const SizedBox(height: 24),
                  if (_carregando)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(60),
                        child: CircularProgressIndicator(
                            color: PainelAdminTheme.roxo),
                      ),
                    )
                  else if (_erro)
                    _buildErro()
                  else ...[
                    _buildStatusCards(),
                    const SizedBox(height: 24),
                    _buildAbas(),
                    const SizedBox(height: 24),
                    _buildConteudoAba(),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Configurações Comercial',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF1A1A2E))),
              const SizedBox(height: 6),
              Text(
                'Defina regras financeiras, integrações bancárias e canais de cobrança do seu negócio.',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 14, color: const Color(0xFF64748B)),
              ),
            ],
          ),
        ),
        FilledButton.icon(
          onPressed: _salvando ? null : _salvar,
          icon: _salvando
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.save_rounded, size: 18),
          label: Text(_salvando ? 'Salvando...' : 'Salvar alterações'),
          style: FilledButton.styleFrom(
            backgroundColor: PainelAdminTheme.roxo,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          ),
        ),
      ],
    );
  }

  Widget _buildErro() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(60),
        child: Column(
          children: [
            const Icon(Icons.cloud_off_rounded,
                size: 48, color: Color(0xFF94A3B8)),
            const SizedBox(height: 16),
            Text('Erro ao carregar configurações',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF1A1A2E))),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => _carregar(_lojaId),
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Tentar novamente'),
              style: FilledButton.styleFrom(
                  backgroundColor: PainelAdminTheme.roxo),
            ),
          ],
        ),
      ),
    );
  }

  // ── STATUS CARDS ──
  Widget _buildStatusCards() {
    final jurosAtivo = _config.jurosMultas.cobrarMulta ||
        _config.jurosMultas.cobrarJuros;
    final pagConfigurado = _config.pagamentos.entries
        .any((e) => e.value.configurado && e.value.ativo);
    final cobAtiva = _config.regrasAutomaticas.lembreteAntes ||
        _config.regrasAutomaticas.lembreteNoVencimento ||
        _config.regrasAutomaticas.lembreteApos;

    final cards = [
      _statusCard(
        icone: Icons.monetization_on_outlined,
        corIcone: PainelAdminTheme.roxo,
        corFundo: const Color(0xFFF1E9FF),
        titulo: 'Juros e multa',
        status: jurosAtivo ? 'Ativo' : 'Inativo',
        corStatus: jurosAtivo ? const Color(0xFF16A34A) : const Color(0xFF94A3B8),
        fundoStatus: jurosAtivo
            ? const Color(0xFFE8F5E9)
            : const Color(0xFFF1F5F9),
      ),
      _statusCard(
        icone: Icons.account_balance_rounded,
        corIcone: const Color(0xFF3B82F6),
        corFundo: const Color(0xFFEFF6FF),
        titulo: 'Banco/API',
        status: pagConfigurado ? 'Configurado' : 'Não configurado',
        corStatus: pagConfigurado
            ? const Color(0xFF16A34A)
            : const Color(0xFFFF8F00),
        fundoStatus: pagConfigurado
            ? const Color(0xFFE8F5E9)
            : const Color(0xFFFFF8E1),
      ),
      _statusCard(
        icone: Icons.autorenew_rounded,
        corIcone: const Color(0xFFFF8F00),
        corFundo: const Color(0xFFFFF8E1),
        titulo: 'Cobrança automática',
        status: cobAtiva ? 'Ativa' : 'Inativa',
        corStatus: cobAtiva ? const Color(0xFF16A34A) : const Color(0xFF94A3B8),
        fundoStatus: cobAtiva
            ? const Color(0xFFE8F5E9)
            : const Color(0xFFF1F5F9),
      ),
      _statusCard(
        icone: Icons.schedule_rounded,
        corIcone: const Color(0xFF64748B),
        corFundo: const Color(0xFFF1F5F9),
        titulo: 'Última atualização',
        status: _config.updatedAt != null
            ? DateFormat('dd/MM/yyyy HH:mm').format(_config.updatedAt!)
            : 'Nunca',
        corStatus: const Color(0xFF64748B),
        fundoStatus: const Color(0xFFF1F5F9),
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final cols = constraints.maxWidth > 900
            ? 4
            : constraints.maxWidth > 600
                ? 2
                : 1;
        final gaps = 12.0 * (cols - 1);
        final cardWidth = (constraints.maxWidth - gaps) / cols;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: cards
              .map((c) => SizedBox(width: cardWidth, child: c))
              .toList(),
        );
      },
    );
  }

  Widget _statusCard({
    required IconData icone,
    required Color corIcone,
    required Color corFundo,
    required String titulo,
    required String status,
    required Color corStatus,
    required Color fundoStatus,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEEEAF6)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1A1A2E).withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: corFundo,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icone, color: corIcone, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titulo,
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF64748B))),
                const SizedBox(height: 4),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: fundoStatus,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(status,
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: corStatus)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── ABAS ──
  Widget _buildAbas() {
    final labels = [
      'Juros e Multas',
      'Banco e Pagamentos',
      'Envio de Cobrança',
      'Regras Automáticas',
    ];
    final icons = [
      Icons.monetization_on_outlined,
      Icons.account_balance_rounded,
      Icons.send_rounded,
      Icons.auto_awesome_rounded,
    ];

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFEEEAF6)),
      ),
      padding: const EdgeInsets.all(4),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isLargo = constraints.maxWidth > 700;
          if (isLargo) {
            return Row(
              children: List.generate(labels.length, (i) {
                final ativa = _abaAtual == i;
                return Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _abaAtual = i),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          vertical: 12, horizontal: 8),
                      decoration: BoxDecoration(
                        color: ativa ? Colors.white : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: ativa
                            ? [
                                BoxShadow(
                                  color: const Color(0xFF1A1A2E)
                                      .withValues(alpha: 0.04),
                                  blurRadius: 4,
                                  offset: const Offset(0, 1),
                                ),
                              ]
                            : null,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(icons[i],
                              size: 16,
                              color: ativa
                                  ? PainelAdminTheme.roxo
                                  : const Color(0xFF94A3B8)),
                          const SizedBox(width: 8),
                          Text(labels[i],
                              style: GoogleFonts.plusJakartaSans(
                                  fontSize: 13,
                                  fontWeight:
                                      ativa ? FontWeight.w700 : FontWeight.w500,
                                  color: ativa
                                      ? PainelAdminTheme.roxo
                                      : const Color(0xFF64748B))),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            );
          }
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: List.generate(labels.length, (i) {
                final ativa = _abaAtual == i;
                return Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: GestureDetector(
                    onTap: () => setState(() => _abaAtual = i),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          vertical: 10, horizontal: 16),
                      decoration: BoxDecoration(
                        color: ativa ? Colors.white : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          Icon(icons[i],
                              size: 14,
                              color: ativa
                                  ? PainelAdminTheme.roxo
                                  : const Color(0xFF94A3B8)),
                          const SizedBox(width: 6),
                          Text(labels[i],
                              style: GoogleFonts.plusJakartaSans(
                                  fontSize: 12,
                                  fontWeight:
                                      ativa ? FontWeight.w700 : FontWeight.w500,
                                  color: ativa
                                      ? PainelAdminTheme.roxo
                                      : const Color(0xFF64748B))),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ),
          );
        },
      ),
    );
  }

  // ── CONTEÚDO DA ABA ──
  Widget _buildConteudoAba() {
    switch (_abaAtual) {
      case 0:
        return _buildAbaJurosMultas();
      case 1:
        return _buildAbaBancoPagamentos();
      case 2:
        return _buildAbaEnvioCobranca();
      case 3:
        return _buildAbaRegrasAutomaticas();
      default:
        return const SizedBox();
    }
  }

  // ==========================================================================
  // ABA 1: JUROS E MULTAS
  // ==========================================================================
  Widget _buildAbaJurosMultas() {
    final multa = _calcularMultaPreview();
    final juros = _calcularJurosPreview();
    final valor =
        double.tryParse(_prevValorCtrl.text.replaceAll(',', '.')) ?? 0;
    final total = valor + multa + juros;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isLargo = constraints.maxWidth > 900;
        if (isLargo) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 3, child: _buildFormJurosMultas()),
              const SizedBox(width: 24),
              SizedBox(
                width: 340,
                child: _buildPreviewCalculo(
                    valor, multa, juros, total),
              ),
            ],
          );
        }
        return Column(
          children: [
            _buildFormJurosMultas(),
            const SizedBox(height: 24),
            _buildPreviewCalculo(valor, multa, juros, total),
          ],
        );
      },
    );
  }

  Widget _buildFormJurosMultas() {
    final jm = _config.jurosMultas;
    return _CardConfig(
      titulo: 'Regras de atraso',
      descricao:
          'Configure como o sistema deve calcular multas e juros para parcelas vencidas.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _switchRow(
            label: 'Cobrar multa após vencimento',
            value: jm.cobrarMulta,
            onChanged: (v) => setState(() => jm.cobrarMulta = v),
          ),
          if (jm.cobrarMulta) ...[
            const SizedBox(height: 20),
            Text('Percentual da multa',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFF374151))),
            const SizedBox(height: 8),
            SizedBox(
              width: 280,
              child: _PercentFieldWidget(
                value: jm.percentualMulta,
                onChanged: (v) => setState(() => jm.percentualMulta = v),
              ),
            ),
            const SizedBox(height: 6),
            _infoLinha(
              'Aplicar multa',
              jm.aplicarMultaUnica ? 'Uma única vez' : 'Por período',
            ),
          ],
          const Divider(height: 28),
          _switchRow(
            label: 'Cobrar juros por atraso',
            value: jm.cobrarJuros,
            onChanged: (v) => setState(() => jm.cobrarJuros = v),
          ),
          if (jm.cobrarJuros) ...[
            const SizedBox(height: 20),
            Text('Percentual de juros ao dia',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFF374151))),
            const SizedBox(height: 8),
            SizedBox(
              width: 280,
              child: _PercentFieldWidget(
                value: jm.percentualJurosDia,
                onChanged: (v) => setState(() => jm.percentualJurosDia = v),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                SizedBox(
                  width: 140,
                  child: _IntFieldWidget(
                    value: jm.diasTolerancia,
                    onChanged: (v) => setState(() => jm.diasTolerancia = v),
                  ),
                ),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text('dias',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          color: const Color(0xFF94A3B8))),
                ),
              ],
            ),
            const SizedBox(height: 6),
            _infoLinha(
              'Aplicar juros',
              jm.aplicarJurosAoDia ? 'Ao dia após vencimento' : 'Uma única vez',
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPreviewCalculo(
      double valor, double multa, double juros, double total) {
    return _CardConfig(
      titulo: 'Prévia do cálculo',
      descricao: 'Simule o cálculo com base nos valores abaixo.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CampoPreviewWidget(
            label: 'Valor da parcela',
            controller: _prevValorCtrl,
            prefix: 'R\$ ',
            onChanged: _atualizarPreview,
          ),
          const SizedBox(height: 12),
          _CampoPreviewWidget(
            label: 'Dias em atraso',
            controller: _prevDiasCtrl,
            onChanged: _atualizarPreview,
          ),
          const Divider(height: 24),
          _previewLinha('Valor da parcela', _moedaFmt.format(valor),
              const Color(0xFF1F2937)),
          const SizedBox(height: 6),
          _previewLinha(
              'Multa (${_config.jurosMultas.percentualMulta.toStringAsFixed(1)}%)',
              multa > 0 ? _moedaFmt.format(multa) : 'R\$ 0,00',
              const Color(0xFFDC2626)),
          const SizedBox(height: 6),
          _previewLinha(
              'Juros (${_config.jurosMultas.percentualJurosDia.toStringAsFixed(3)}% ao dia)',
              juros > 0 ? _moedaFmt.format(juros) : 'R\$ 0,00',
              const Color(0xFFFF8F00)),
          const Divider(height: 16),
          _previewLinha('Total atualizado', _moedaFmt.format(total),
              PainelAdminTheme.roxo,
              bold: true),
        ],
      ),
    );
  }

  Widget _previewLinha(String label, String valor, Color cor,
      {bool bold = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: const Color(0xFF6B7280))),
        Text(valor,
            style: GoogleFonts.plusJakartaSans(
                fontSize: 14,
                fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
                color: cor)),
      ],
    );
  }

  // ==========================================================================
  // ABA 2: BANCO E PAGAMENTOS
  // ==========================================================================
  // ──────────────────────────────────────────────────────────────
  // ABA 2: BANCO E PAGAMENTOS (REFATORADO)
  // ──────────────────────────────────────────────────────────────
  Widget _buildAbaBancoPagamentos() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildGatewayPadraoCard(),
        const SizedBox(height: 24),
        _buildIntegracoesLista(),
      ],
    );
  }

  // ── CARD 1: GATEWAY PADRÃO ──
  Widget _buildGatewayPadraoCard() {
    final configuradas = _config.pagamentos.entries
        .where((e) =>
            e.key != 'gatewayPadrao' &&
            (e.value.token.trim().isNotEmpty || e.value.configurado))
        .toList();

    final chaveAtual = () {
      final gp = _config.pagamentos['gatewayPadrao'];
      if (gp == null) return '';
      if (gp.tipo.isNotEmpty && gp.tipo != 'PIX') return gp.tipo;
      if (gp.provedor.isNotEmpty) return gp.provedor;
      return _chavePorNomeIntegracao(gp.nome) ?? '';
    }();

    final chavesConfig = configuradas.map((e) => e.key).toSet();
    final valorDropdown =
        chaveAtual.isNotEmpty && chavesConfig.contains(chaveAtual)
            ? chaveAtual
            : '';

    return _CardConfig(
      titulo: 'Gateway padrão',
      descricao:
          'Escolha qual integração será utilizada pelo sistema para receber pagamentos.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 360,
            child: DropdownButtonFormField<String>(
              initialValue: valorDropdown,
              decoration: InputDecoration(
                labelText: 'Gateway padrão',
                labelStyle: GoogleFonts.plusJakartaSans(fontSize: 13),
                filled: true,
                fillColor: const Color(0xFFF8F9FB),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
              items: [
                const DropdownMenuItem(
                  value: '',
                  child: Text('Nenhuma integração cadastrada',
                      style: TextStyle(fontSize: 13, color: Color(0xFF94A3B8))),
                ),
                ...configuradas.map((e) => DropdownMenuItem(
                      value: e.key,
                      child: Text(
                        e.value.nome.isNotEmpty
                            ? e.value.nome
                            : _nomeTipoIntegracao(e.key),
                        style: const TextStyle(fontSize: 13),
                      ),
                    )),
              ],
              onChanged: (v) {
                if (v == null || v.isEmpty) return;
                setState(() {
                  _config.pagamentos['gatewayPadrao'] = _IntegracaoPagamento(
                    nome: _nomeTipoIntegracao(v),
                    tipo: v,
                    provedor: v,
                    ativo: true,
                  );
                });
                _salvar();
              },
            ),
          ),
        ],
      ),
    );
  }

  // ── CARD 2: INTEGRAÇÕES BANCÁRIAS ──
  Widget _buildIntegracoesLista() {
    final integracoes = _config.pagamentos.entries
        .where((e) => e.key != 'gatewayPadrao')
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Integrações Bancárias',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF1A1A2E))),
                  const SizedBox(height: 4),
                  Text(
                    'Gerencie todas as integrações disponíveis para sua loja.',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 13, color: const Color(0xFF6B7280)),
                  ),
                ],
              ),
            ),
            FilledButton.icon(
              onPressed: _abrirModalNovaIntegracao,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Nova Integração'),
              style: FilledButton.styleFrom(
                backgroundColor: PainelAdminTheme.roxo,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        LayoutBuilder(
          builder: (context, constraints) {
            final cols = constraints.maxWidth > 1000
                ? 3
                : constraints.maxWidth > 700
                    ? 2
                    : 1;
            final gaps = 16.0 * (cols - 1);
            final cardWidth = (constraints.maxWidth - gaps) / cols;
            if (integracoes.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 48),
                  child: Column(
                    children: [
                      Icon(Icons.account_balance_rounded,
                          size: 48, color: Colors.grey.shade300),
                      const SizedBox(height: 12),
                      Text('Nenhuma integração cadastrada',
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 15,
                              color: const Color(0xFF94A3B8))),
                      const SizedBox(height: 4),
                      Text(
                          'Clique em "Nova Integração" para começar.',
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 12,
                              color: const Color(0xFFCBD5E1))),
                    ],
                  ),
                ),
              );
            }
            return Wrap(
              spacing: 16,
              runSpacing: 16,
              children: integracoes.map((e) {
                return SizedBox(
                  width: cardWidth,
                  child: _buildIntegracaoCardItem(e.key, e.value),
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }

  // ── CARD DE INTEGRAÇÃO COMPACTO ──
  Widget _buildIntegracaoCardItem(
      String chave, _IntegracaoPagamento integ) {
    final configurado = integ.configurado;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Container(
        height: 140,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFEEEAF6)),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF1A1A2E).withValues(alpha: 0.04),
              blurRadius: 12,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: configurado
                        ? const Color(0xFFE8F5E9)
                        : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    _iconePorTipo(integ.tipo),
                    color: configurado
                        ? const Color(0xFF16A34A)
                        : const Color(0xFF94A3B8),
                    size: 16,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(integ.nome.isNotEmpty ? integ.nome : _nomeTipoIntegracao(chave),
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF1F2937))),
                ),
                _badgeStatus(integ.ativo),
              ],
            ),
            const SizedBox(height: 6),
            // Recursos
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: _recursosPorTipo(integ.tipo).map((r) {
                return Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.check_rounded,
                          size: 10, color: Color(0xFF16A34A)),
                      const SizedBox(width: 2),
                      Text(r,
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 9,
                              color: const Color(0xFF374151))),
                    ],
                  ),
                );
              }).toList(),
            ),
            const Spacer(),
            Row(
              children: [
                SizedBox(
                  height: 32,
                  child: OutlinedButton.icon(
                    onPressed: () =>
                        _abrirModalEditarIntegracao(chave, integ),
                    icon: const Icon(Icons.edit_rounded, size: 13),
                    label: const Text('Editar',
                        style: TextStyle(fontSize: 11)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: PainelAdminTheme.roxo,
                      side: const BorderSide(color: PainelAdminTheme.roxo),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 4),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                SizedBox(
                  height: 32,
                  child: OutlinedButton(
                    onPressed: () =>
                        _testarConexaoIntegracao(chave, integ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF64748B),
                      backgroundColor: const Color(0xFFF1F5F9),
                      side: BorderSide.none,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                    ),
                    child: const Text('Testar',
                        style: TextStyle(fontSize: 11)),
                  ),
                ),
                const Spacer(),
                _menuIntegracao(chave, integ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  IconData _iconePorTipo(String tipo) {
    switch (tipo) {
      case 'mercado_pago':
      case 'asaas':
        return Icons.account_balance_rounded;
      case 'cora':
      case 'banco_itaú':
      case 'banco_bradesco':
      case 'banco_santander':
      case 'banco_do_brasil':
      case 'sicoob':
      case 'sicredi':
        return Icons.account_balance_rounded;
      case 'stone':
      case 'pagseguro':
        return Icons.credit_card_rounded;
      default:
        return Icons.api_rounded;
    }
  }

  List<String> _recursosPorTipo(String tipo) {
    switch (tipo) {
      case 'mercado_pago':
        return ['PIX', 'Cartão', 'Checkout', 'Webhook'];
      case 'asaas':
        return ['PIX', 'Cartão', 'Cobrança', 'Webhook'];
      case 'cora':
        return ['PIX', 'Cobrança', 'Webhook'];
      case 'stone':
      case 'pagseguro':
        return ['Cartão', 'PIX', 'Webhook'];
      case 'api_personalizada':
        return ['API', 'Webhook'];
      default:
        return ['PIX', 'Cartão', 'Webhook'];
    }
  }

  Widget _badgeStatus(bool ativo) {
    final cor = ativo ? const Color(0xFF16A34A) : const Color(0xFF94A3B8);
    final fundo = ativo ? const Color(0xFFE8F5E9) : const Color(0xFFF1F5F9);
    final texto = ativo ? 'Ativo' : 'Inativo';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: fundo,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                  color: cor, shape: BoxShape.circle)),
          const SizedBox(width: 4),
          Text(texto,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: cor)),
        ],
      ),
    );
  }

  Widget _menuIntegracao(String chave, _IntegracaoPagamento integ) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_horiz_rounded,
          size: 18, color: Color(0xFF94A3B8)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      onSelected: (v) {
        switch (v) {
          case 'editar':
            _abrirModalEditarIntegracao(chave, integ);
            break;
          case 'duplicar':
            setState(() {
              _config.pagamentos['${chave}_copia'] = _IntegracaoPagamento(
                nome: '${integ.nome} (cópia)',
                tipo: integ.tipo,
                apiUrl: integ.apiUrl,
                token: integ.token,
                ativo: false,
              );
            });
            _salvar();
            break;
          case 'desativar':
            setState(() {
              integ.ativo = !integ.ativo;
              _config.pagamentos[chave] = integ;
            });
            _salvar();
            break;
          case 'excluir':
            showDialog(
              context: context,
              builder: (ctx) => AlertDialog(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                title: const Text('Excluir integração'),
                content: Text(
                    'Tem certeza que deseja excluir "${integ.nome}"?'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Cancelar'),
                  ),
                  FilledButton(
                    onPressed: () {
                      setState(() {
                        _config.pagamentos.remove(chave);
                      });
                      Navigator.pop(ctx);
                      _salvar();
                    },
                    style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFDC2626)),
                    child: const Text('Excluir'),
                  ),
                ],
              ),
            );
            break;
        }
      },
      itemBuilder: (_) => [
        const PopupMenuItem(
            value: 'editar',
            child: ListTile(
                leading: Icon(Icons.edit_rounded, size: 18),
                title: Text('Editar', style: TextStyle(fontSize: 13)),
                dense: true)),
        const PopupMenuItem(
            value: 'duplicar',
            child: ListTile(
                leading: Icon(Icons.copy_rounded, size: 18),
                title: Text('Duplicar', style: TextStyle(fontSize: 13)),
                dense: true)),
        PopupMenuItem(
            value: 'desativar',
            child: ListTile(
                leading: Icon(
                    integ.ativo
                        ? Icons.toggle_off_rounded
                        : Icons.toggle_on_rounded,
                    size: 18),
                title: Text(integ.ativo ? 'Desativar' : 'Ativar',
                    style: const TextStyle(fontSize: 13)),
                dense: true)),
        const PopupMenuItem(
            value: 'excluir',
            child: ListTile(
                leading: Icon(Icons.delete_outline_rounded,
                    size: 18, color: Color(0xFFDC2626)),
                title: Text('Excluir',
                    style: TextStyle(
                        fontSize: 13, color: Color(0xFFDC2626))),
                dense: true)),
      ],
    );
  }

  // ── MODAL: NOVA INTEGRAÇÃO ──
  void _abrirModalNovaIntegracao() {
    String? tipoSelecionado;
    String? passo = 'selecionar';
    final edit = _IntegracaoPagamento();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18)),
            titlePadding:
                const EdgeInsets.fromLTRB(24, 20, 24, 0),
            title: Row(
              children: [
                const Icon(Icons.add_card_rounded,
                    size: 20, color: PainelAdminTheme.roxo),
                const SizedBox(width: 10),
                Text(passo == 'selecionar'
                        ? 'Nova Integração'
                        : 'Configurar ${_nomeTipoIntegracao(tipoSelecionado!)}',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF1F2937))),
              ],
            ),
            content: SizedBox(
              width: 480,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (passo == 'selecionar')
                      _buildSeletorTipo(ctx, setModalState, tipoSelecionado,
                          (v) {
                        tipoSelecionado = v;
                        setModalState(() {});
                      })
                    else ...[
                      _buildFormGateway(
                          ctx, setModalState, tipoSelecionado!, edit),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  if (passo == 'selecionar') {
                    Navigator.pop(ctx);
                  } else {
                    passo = 'selecionar';
                    setModalState(() {});
                  }
                },
                child: Text(passo == 'selecionar' ? 'Cancelar' : 'Voltar'),
              ),
              if (passo == 'selecionar')
                FilledButton(
                  onPressed: tipoSelecionado == null
                      ? null
                      : () {
                          _iniciarDefaultsIntegracao(edit, tipoSelecionado!);
                          passo = 'formulario';
                          setModalState(() {});
                        },
                  style: FilledButton.styleFrom(
                      backgroundColor: PainelAdminTheme.roxo),
                  child: const Text('Continuar'),
                )
              else
                FilledButton(
                  onPressed: () {
                    final chave = edit.tipo;
                    final nomeSalvo = edit.nome;
                    _aplicarDefaultsIntegracao(edit, chave);
                    edit.nome = nomeSalvo;
                    setState(() {
                      _config.pagamentos[chave] = edit;
                      final gp = _config.pagamentos['gatewayPadrao'];
                      if (gp == null ||
                          gp.tipo.isEmpty ||
                          gp.tipo == 'PIX' ||
                          !_config.pagamentos.containsKey(gp.tipo)) {
                        _config.pagamentos['gatewayPadrao'] =
                            _IntegracaoPagamento(
                          nome: edit.nome,
                          tipo: chave,
                          provedor: chave,
                          ativo: true,
                        );
                      }
                    });
                    Navigator.pop(ctx);
                    _salvar(
                      tituloSucesso: 'Integração configurada',
                      mensagemSucesso:
                          '${edit.nome} foi salva e já pode receber pagamentos.',
                    );
                  },
                  style: FilledButton.styleFrom(
                      backgroundColor: PainelAdminTheme.roxo),
                  child: const Text('Salvar'),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSeletorTipo(
    BuildContext ctx,
    void Function(void Function()) setModalState,
    String? selecionado,
    ValueChanged<String> onChanged,
  ) {
    final tipos = _tiposIntegracaoPagamento;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Tipo da Integração',
            style: GoogleFonts.plusJakartaSans(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF374151))),
        const SizedBox(height: 12),
        ...tipos.map((t) {
          final sel = selecionado == t;
          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: InkWell(
              onTap: () => onChanged(t),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: sel
                      ? const Color(0xFFF1E9FF)
                      : const Color(0xFFF8F9FB),
                  borderRadius: BorderRadius.circular(12),
                  border: sel
                      ? Border.all(
                          color: PainelAdminTheme.roxo, width: 1.5)
                      : Border.all(color: const Color(0xFFEEEAF6)),
                ),
                child: Row(
                  children: [
                    Icon(
                      sel
                          ? Icons.radio_button_checked_rounded
                          : Icons.radio_button_off_rounded,
                      size: 18,
                      color: sel
                          ? PainelAdminTheme.roxo
                          : const Color(0xFF94A3B8),
                    ),
                    const SizedBox(width: 12),
                    Text(_nomeTipoIntegracao(t),
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 13,
                            fontWeight:
                                sel ? FontWeight.w600 : FontWeight.w400,
                            color: sel
                                ? PainelAdminTheme.roxo
                                : const Color(0xFF374151))),
                  ],
                ),
              ),
            ),
          );
        }),
      ],
    );
  }

  // ── FORMULÁRIO UNIFICADO POR GATEWAY ──
  Widget _buildFormGateway(
    BuildContext ctx,
    void Function(void Function()) setModalState,
    String tipo,
    _IntegracaoPagamento edit,
  ) {
    final credenciaisPadrao = _integracaoUsaCredenciaisPadrao(tipo);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _formField(
          label: 'Nome da integração',
          value: edit.nome,
          onChanged: (v) => setModalState(() => edit.nome = v),
        ),
        const SizedBox(height: 14),
        if (!credenciaisPadrao) ...[
          _formField(
            label: 'Base URL da API',
            value: edit.apiUrl,
            onChanged: (v) => setModalState(() => edit.apiUrl = v),
          ),
          const SizedBox(height: 14),
        ],
        _formFieldSecret(
          label: 'Access Token',
          value: edit.token,
          onChanged: (v) => setModalState(() => edit.token = v),
        ),
        const SizedBox(height: 14),
        _formField(
          label: 'Public Key',
          value: edit.clientId,
          onChanged: (v) => setModalState(() => edit.clientId = v),
        ),
        const SizedBox(height: 14),
        _modalDropdown(
          label: 'Ambiente',
          value: edit.ambiente,
          items: const ['producao', 'sandbox'],
          onChanged: (v) {
            if (v != null) setModalState(() => edit.ambiente = v);
          },
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          height: 40,
          child: OutlinedButton.icon(
            onPressed: edit.token.isEmpty
                ? null
                : () => _testarConexaoIntegracao(tipo, edit, dialogCtx: ctx),
            icon: const Icon(Icons.wifi_find_rounded, size: 16),
            label: const Text('Testar conexão', style: TextStyle(fontSize: 12)),
            style: OutlinedButton.styleFrom(
              foregroundColor: PainelAdminTheme.roxo,
              side: const BorderSide(color: PainelAdminTheme.roxo),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Text('Ativo:',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFF6B7280))),
            const SizedBox(width: 12),
            Switch(
              value: edit.ativo,
              activeThumbColor: PainelAdminTheme.roxo,
              onChanged: (v) => setModalState(() => edit.ativo = v),
            ),
          ],
        ),
        const SizedBox(height: 16),
        // Configuração avançada — colapsada por padrão
        _buildAdvancedSection(tipo),
      ],
    );
  }

  /// Seção "Configuração avançada" colapsada, com webhook e instruções.
  Widget _buildAdvancedSection(String tipo) {
    final url = webhookUrlIntegracao(tipo);
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFE5E7EB)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
        shape: const Border(),
        collapsedShape: const Border(),
        collapsedBackgroundColor: const Color(0xFFF9FAFB),
        childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.tune_rounded,
                size: 16, color: PainelAdminTheme.roxo.withValues(alpha: 0.6)),
            const SizedBox(width: 8),
            Text('Configuração avançada',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF6B7280))),
          ],
        ),
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF0F9FF),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFBAE6FD)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.webhook_rounded,
                        size: 14, color: Color(0xFF0284C7)),
                    const SizedBox(width: 6),
                    Text('Webhook',
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF0369A1))),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Se o seu provedor exigir, cadastre esta URL no painel de '
                  'webhooks/configurações da API.',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 11, color: const Color(0xFF475569)),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: SelectableText(
                          url,
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF1A1A2E)),
                        ),
                      ),
                      const SizedBox(width: 4),
                      InkWell(
                        onTap: () {
                          Clipboard.setData(ClipboardData(text: url));
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: const Text('URL do webhook copiada.'),
                              behavior: SnackBarBehavior.floating,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                            ),
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: PainelAdminTheme.roxo.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Icon(Icons.copy_rounded,
                              size: 14, color: PainelAdminTheme.roxo),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── MODAL: EDITAR INTEGRAÇÃO ──
  void _abrirModalEditarIntegracao(
      String chave, _IntegracaoPagamento integ) {
    final tipoChave = integ.tipo.isNotEmpty && integ.tipo != 'PIX'
        ? integ.tipo
        : chave;
    final edit = _IntegracaoPagamento(
      nome: integ.nome,
      provedor: integ.provedor.isNotEmpty ? integ.provedor : tipoChave,
      tipo: tipoChave,
      ambiente: integ.ambiente,
      apiUrl: integ.apiUrl,
      clientId: integ.clientId,
      clientSecret: integ.clientSecret,
      token: integ.token,
      webhookUrl: integ.webhookUrl.isNotEmpty
          ? integ.webhookUrl
          : webhookUrlIntegracao(tipoChave),
      ativo: integ.ativo,
    );

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18)),
            titlePadding:
                const EdgeInsets.fromLTRB(24, 20, 24, 0),
            title: Row(
              children: [
                const Icon(Icons.edit_rounded,
                    size: 20, color: PainelAdminTheme.roxo),
                const SizedBox(width: 10),
                Text('Editar ${integ.nome}',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF1F2937))),
              ],
            ),
            content: SizedBox(
              width: 480,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildFormGateway(
                        ctx, setModalState, tipoChave, edit),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () {
                  final nomeSalvo = edit.nome;
                  _aplicarDefaultsIntegracao(edit, tipoChave);
                  edit.nome = nomeSalvo;
                  setState(() {
                    _config.pagamentos[chave] = edit;
                  });
                  Navigator.pop(ctx);
                  _salvar(
                    tituloSucesso: 'Integração atualizada',
                    mensagemSucesso:
                        '${edit.nome} foi atualizada com sucesso.',
                  );
                },
                style: FilledButton.styleFrom(
                    backgroundColor: PainelAdminTheme.roxo),
                child: const Text('Salvar'),
              ),
            ],
          );
        },
      ),
    );
  }

  // ── TESTAR CONEXÃO ──
  /// Testa o Access Token do Mercado Pago via Cloud Function (evita CORS).
  void _testarTokenMercadoPago(
    BuildContext dialogCtx,
    _IntegracaoPagamento integ,
  ) {
    mostrarDiPertinLoadingPremium(
      dialogCtx,
      titulo: 'Validando Mercado Pago',
      subtitulo: 'Token, ambiente, PIX e QR Code...',
    );
    callFirebaseFunctionSafe(
      'gestaoComercialTestarConexaoMercadoPago',
      region: 'southamerica-east1',
      parameters: {
        'accessToken': integ.token.trim(),
        'ambiente': integ.ambiente,
        'lojaId': _lojaId,
      },
    ).then((result) async {
      if (!mounted) return;
      if (Navigator.canPop(dialogCtx)) Navigator.pop(dialogCtx);
      final valido = result['valido'] == true;
      final mensagem = result['mensagem']?.toString() ?? '';
      await mostrarDiPertinFeedbackPremium(
        context,
        sucesso: valido,
        titulo: valido ? 'Conexão validada' : 'Falha na conexão',
        mensagem: mensagem.isNotEmpty
            ? mensagem
            : (valido
                ? 'A integração Mercado Pago está pronta para receber pagamentos.'
                : 'Não foi possível validar a integração. Revise o token e o cadastro PIX no Mercado Pago.'),
        detalhes: valido ? _detalhesResultadoTesteMp(result) : const [],
        botaoTexto: valido ? 'Ótimo' : 'Entendi',
      );
    }).catchError((err) async {
      if (!mounted) return;
      if (Navigator.canPop(dialogCtx)) Navigator.pop(dialogCtx);
      await mostrarDiPertinFeedbackPremium(
        context,
        sucesso: false,
        titulo: 'Erro ao testar',
        mensagem:
            'Não foi possível concluir a validação: ${err.toString()}',
        botaoTexto: 'Fechar',
      );
    });
  }

  void _testarConexaoIntegracao(
    String chave,
    _IntegracaoPagamento integ, {
    BuildContext? dialogCtx,
  }) {
    final nome = integ.nome.isNotEmpty
        ? integ.nome
        : _nomeTipoIntegracao(chave);
    if (integ.token.trim().isEmpty) {
      mostrarDiPertinFeedbackPremium(
        context,
        sucesso: false,
        titulo: 'Token obrigatório',
        mensagem:
            'Informe o Access Token da integração antes de testar a conexão.',
        botaoTexto: 'Entendi',
      );
      return;
    }

    if (chave == 'mercado_pago') {
      _testarTokenMercadoPago(dialogCtx ?? context, integ);
      return;
    }

    final ctxLoader = dialogCtx ?? context;
    mostrarDiPertinLoadingPremium(
      ctxLoader,
      titulo: 'Validando $nome',
      subtitulo: 'Verificando credenciais da integração...',
    );

    callFirebaseFunctionSafe(
      'gestaoComercialTestarConexaoGateway',
      region: 'southamerica-east1',
      parameters: {
        'provedor': chave,
        'accessToken': integ.token.trim(),
        'publicKey': integ.clientId.trim(),
        'ambiente': integ.ambiente,
        'lojaId': _lojaId,
      },
    ).then((result) async {
      if (!mounted) return;
      if (Navigator.canPop(ctxLoader)) Navigator.pop(ctxLoader);
      final valido = result['valido'] == true;
      final mensagem = result['mensagem']?.toString() ??
          (valido
              ? 'Credenciais validadas com sucesso.'
              : 'Não foi possível validar as credenciais.');
      await mostrarDiPertinFeedbackPremium(
        context,
        sucesso: valido,
        titulo: valido ? 'Conexão validada' : 'Falha na conexão',
        mensagem: mensagem,
        detalhes: chave == 'mercado_pago' && valido
            ? _detalhesResultadoTesteMp(result)
            : const [],
        botaoTexto: valido ? 'Ótimo' : 'Entendi',
      );
    }).catchError((err) async {
      if (!mounted) return;
      if (Navigator.canPop(ctxLoader)) Navigator.pop(ctxLoader);
      await mostrarDiPertinFeedbackPremium(
        context,
        sucesso: false,
        titulo: 'Erro ao testar',
        mensagem: 'Não foi possível concluir a validação: ${err.toString()}',
        botaoTexto: 'Fechar',
      );
    });
  }

  // ── CAMPOS DE FORMULÁRIO REUTILIZÁVEIS ──
  Widget _formField({
    required String label,
    required String value,
    required ValueChanged<String> onChanged,
    String? hint,
  }) {
    final ctrl = TextEditingController(text: value);
    ctrl.addListener(() => onChanged(ctrl.text));
    return TextField(
      controller: ctrl,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        hintStyle: GoogleFonts.plusJakartaSans(fontSize: 12, color: const Color(0xFF9CA3AF)),
        labelStyle: GoogleFonts.plusJakartaSans(fontSize: 13),
        filled: true,
        fillColor: const Color(0xFFF8F9FB),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  Widget _formFieldSecret({
    required String label,
    required String value,
    required ValueChanged<String> onChanged,
  }) {
    final ctrl = TextEditingController(text: value);
    ctrl.addListener(() => onChanged(ctrl.text));
    bool oculto = true;
    return StatefulBuilder(
      builder: (ctx, setLocal) => TextField(
        controller: ctrl,
        obscureText: oculto,
        decoration: InputDecoration(
          labelText: label,
          labelStyle: GoogleFonts.plusJakartaSans(fontSize: 13),
          filled: true,
          fillColor: const Color(0xFFF8F9FB),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          suffixIcon: IconButton(
            icon: Icon(
                oculto
                    ? Icons.visibility_off_rounded
                    : Icons.visibility_rounded,
                size: 18),
            onPressed: () => setLocal(() => oculto = !oculto),
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }
  // ==========================================================================
  // ABA 3: ENVIO DE COBRANÇA
  // ==========================================================================

  static const _kComteleSmsApiUrl = 'https://sms.comtele.com.br/api/v2';

  static const _canaisCobranca = [
    ('WhatsApp', Icons.chat_rounded, 'whatsapp'),
    ('E-mail', Icons.email_rounded, 'email'),
    ('SMS Comtele', Icons.sms_rounded, 'sms'),
    ('API Externa', Icons.api_rounded, 'api_externa'),
  ];

  Widget _buildAbaEnvioCobranca() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Canais de envio',
            style: GoogleFonts.plusJakartaSans(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF1A1A2E))),
        const SizedBox(height: 4),
        Text(
          'Configure cada canal com os campos do provedor. SMS disponível apenas via Comtele.',
          style: GoogleFonts.plusJakartaSans(
              fontSize: 13, color: const Color(0xFF6B7280)),
        ),
        const SizedBox(height: 20),
        LayoutBuilder(
          builder: (context, constraints) {
            final cols = constraints.maxWidth > 900
                ? 2
                : constraints.maxWidth > 560
                    ? 2
                    : 1;
            final gaps = 16.0 * (cols - 1);
            final cardWidth = (constraints.maxWidth - gaps) / cols;
            return Wrap(
              spacing: 16,
              runSpacing: 16,
              children: _canaisCobranca.map((c) {
                final canal = _config.cobranca[c.$3] ??
                    _CanalCobranca(tipo: c.$3, nome: c.$1);
                return SizedBox(
                  width: cardWidth,
                  child: _buildCanalCard(c.$1, c.$2, c.$3, canal),
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }

  List<String> _recursosCanalCobranca(String chave) {
    switch (chave) {
      case 'whatsapp':
        return ['WhatsApp', 'Lembrete', 'Template'];
      case 'email':
        return ['E-mail', 'Lembrete', 'Template'];
      case 'sms':
        return ['Comtele', 'SMS', 'Lembrete'];
      case 'api_externa':
        return ['HTTP', 'Custom', 'Template'];
      default:
        return ['Cobrança'];
    }
  }

  String _subtituloCanalCobranca(String chave) {
    switch (chave) {
      case 'whatsapp':
        return 'API WhatsApp Business';
      case 'email':
        return 'SMTP ou API de e-mail';
      case 'sms':
        return 'Provedor Comtele';
      case 'api_externa':
        return 'Integração personalizada';
      default:
        return '';
    }
  }

  Widget _buildCanalCard(
      String nome, IconData icone, String chave, _CanalCobranca canal) {
    final configurado = canal.estaConfigurado(chave);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Container(
        height: 168,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFEEEAF6)),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF1A1A2E).withValues(alpha: 0.04),
              blurRadius: 12,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: configurado
                        ? const Color(0xFFE8F5E9)
                        : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icone,
                      color: configurado
                          ? const Color(0xFF16A34A)
                          : const Color(0xFF94A3B8),
                      size: 16),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(nome,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF1F2937))),
                      Text(_subtituloCanalCobranca(chave),
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 10,
                              color: const Color(0xFF94A3B8))),
                    ],
                  ),
                ),
                _badgeStatus(canal.ativo && configurado),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: _recursosCanalCobranca(chave).map((r) {
                return Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.check_rounded,
                          size: 10, color: Color(0xFF16A34A)),
                      const SizedBox(width: 2),
                      Text(r,
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 9, color: const Color(0xFF374151))),
                    ],
                  ),
                );
              }).toList(),
            ),
            const Spacer(),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 36,
                    child: OutlinedButton.icon(
                      onPressed: () => _abrirModalCanal(chave, nome, canal),
                      icon: const Icon(Icons.edit_rounded, size: 14),
                      label: Text(configurado ? 'Editar' : 'Configurar',
                          style: const TextStyle(fontSize: 12)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: PainelAdminTheme.roxo,
                        side: const BorderSide(color: PainelAdminTheme.roxo),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  height: 36,
                  child: OutlinedButton(
                    onPressed: configurado
                        ? () => _testarEnvio(nome, chave)
                        : null,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF374151),
                      backgroundColor: const Color(0xFFF8F9FB),
                      side: const BorderSide(color: Color(0xFFE8E4F0)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                    child: const Text('Testar', style: TextStyle(fontSize: 11)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _testarEnvio(String nome, String chave) {
    final msg = chave == 'sms'
        ? 'Teste Comtele SMS será enviado quando o backend estiver ativo.'
        : 'Enviando teste via $nome...';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: const Color(0xFFFF8F00),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _abrirModalCanal(String chave, String nome, _CanalCobranca canal) {
    if (chave == 'email') {
      showComercialEmailTransacionalModal(
        context,
        lojaId: _lojaId,
        onSalvo: (ativo, configurado) {
          setState(() {
            final atual = _config.cobranca['email'] ?? _CanalCobranca(tipo: 'email', nome: nome);
            atual.ativo = ativo;
            if (configurado) atual.ativo = true;
            _config.cobranca['email'] = atual;
          });
          _carregar(_lojaId);
        },
      );
      return;
    }

    final edit = _CanalCobranca(
      nome: canal.nome.isNotEmpty ? canal.nome : nome,
      tipo: chave,
      apiUrl: canal.apiUrl,
      token: canal.token,
      remetente: canal.remetente,
      emailRemetente: canal.emailRemetente,
      templateMensagem: canal.templateMensagem.isEmpty
          ? _templatePadraoCanal(chave)
          : canal.templateMensagem,
      ativo: canal.ativo,
    );
    _aplicarDefaultsCanalCobranca(edit, chave);

    final templateCtrl = TextEditingController(text: edit.templateMensagem);
    bool ocultarToken = true;

    // Estado local do teste de conexão (genérico para qualquer canal)
    bool testando = false;
    String testMsg = '';
    bool testOk = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          // Determina se o canal tem suporte a teste+preview
          final hasTestPreview = chave == 'whatsapp' || chave == 'sms' || chave == 'api_externa';
          // Nome da função de teste por canal
          String testFunctionName(String c) {
            switch (c) {
              case 'whatsapp': return 'gestaoComercialWhatsAppTestarConexao';
              case 'sms': return 'gestaoComercialSmsTestarConexao';
              case 'api_externa': return 'gestaoComercialApiExternaTestarConexao';
              default: return '';
            }
          }

          return AlertDialog(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18)),
            titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
            title: Row(
              children: [
                Icon(_iconeCanalCobranca(chave),
                    size: 20, color: PainelAdminTheme.roxo),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Configurar $nome',
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF1F2937))),
                      Text(_subtituloCanalCobranca(chave),
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 12,
                              color: PainelAdminTheme.textoSecundario)),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(ctx),
                  icon: const Icon(Icons.close_rounded,
                      color: PainelAdminTheme.textoSecundario),
                ),
              ],
            ),
            content: SizedBox(
              width: hasTestPreview ? 560 : 520,
              child: SingleChildScrollView(
                child: hasTestPreview
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildFormCanalCobranca(
                            chave: chave,
                            edit: edit,
                            templateCtrl: templateCtrl,
                            ocultarToken: ocultarToken,
                            setModalState: setModalState,
                            onToggleToken: () =>
                                setModalState(() => ocultarToken = !ocultarToken),
                          ),
                          const SizedBox(height: 16),

                          // Botão Testar Conexão (WhatsApp / SMS / API Externa)
                          _buildCanalTestButton(
                            testando: testando,
                            testOk: testOk,
                            testMsg: testMsg,
                            onTestar: () async {
                              setModalState(() {
                                testando = true;
                                testMsg = '';
                                testOk = false;
                              });
                              try {
                                final result = await callFirebaseFunctionSafe(
                                  testFunctionName(chave),
                                  parameters: {'lojaId': _lojaId},
                                  region: 'southamerica-east1',
                                );
                                if (ctx.mounted) {
                                  setModalState(() {
                                    testando = false;
                                    testOk = result['ok'] == true;
                                    testMsg = result['mensagem'] ?? 'Resposta inesperada.';
                                  });
                                }
                              } catch (e) {
                                if (ctx.mounted) {
                                  setModalState(() {
                                    testando = false;
                                    testOk = false;
                                    testMsg = e.toString();
                                  });
                                }
                              }
                            },
                          ),

                          const SizedBox(height: 20),

                          // Preview do Template (WhatsApp / SMS / API Externa)
                          _buildCanalPreview(
                            edit: edit,
                            templateCtrl: templateCtrl,
                          ),
                        ],
                      )
                    : _buildFormCanalCobranca(
                        chave: chave,
                        edit: edit,
                        templateCtrl: templateCtrl,
                        ocultarToken: ocultarToken,
                        setModalState: setModalState,
                        onToggleToken: () =>
                            setModalState(() => ocultarToken = !ocultarToken),
                      ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () {
                  edit.templateMensagem = templateCtrl.text;
                  _aplicarDefaultsCanalCobranca(edit, chave);
                  setState(() {
                    _config.cobranca[chave] = edit;
                  });
                  Navigator.pop(ctx);
                  _salvar();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('$nome configurado com sucesso.'),
                      backgroundColor: const Color(0xFF16A34A),
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  );
                },
                style: FilledButton.styleFrom(
                    backgroundColor: PainelAdminTheme.roxo),
                child: const Text('Salvar'),
              ),
            ],
          );
        },
      ),
    ).then((_) => templateCtrl.dispose());
  }

  String _templatePadraoCanal(String chave) {
    return 'Olá, {cliente}, sua parcela no valor de {valor} vence em {vencimento}. Link de pagamento: {link}';
  }

  void _aplicarDefaultsCanalCobranca(_CanalCobranca edit, String chave) {
    edit.tipo = chave;
    if (chave == 'sms') {
      edit.apiUrl = _kComteleSmsApiUrl;
      if (edit.nome.trim().isEmpty) edit.nome = 'Comtele SMS';
    }
    if (edit.token.trim().isNotEmpty && edit.estaConfigurado(chave)) {
      edit.ativo = true;
    }
  }

  IconData _iconeCanalCobranca(String chave) {
    switch (chave) {
      case 'whatsapp':
        return Icons.chat_rounded;
      case 'email':
        return Icons.email_rounded;
      case 'sms':
        return Icons.sms_rounded;
      case 'api_externa':
        return Icons.api_rounded;
      default:
        return Icons.settings_rounded;
    }
  }

  Widget _buildCanalInfoBox(String titulo, String texto) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F9FF),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFBAE6FD)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, size: 16, color: Color(0xFF0284C7)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titulo,
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF0369A1))),
                const SizedBox(height: 4),
                Text(texto,
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 11, color: const Color(0xFF475569))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTemplateCobrancaField(TextEditingController controller) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Template da mensagem',
            style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: const Color(0xFF6B7280))),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          maxLines: 4,
          decoration: InputDecoration(
            filled: true,
            fillColor: const Color(0xFFF8F9FB),
            contentPadding: const EdgeInsets.all(14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Variáveis: {cliente}, {valor}, {vencimento}, {loja}, {link}, {dias_atraso}',
          style: GoogleFonts.plusJakartaSans(
              fontSize: 10, color: const Color(0xFF94A3B8)),
        ),
      ],
    );
  }

  Widget _buildCanalAtivoSwitch(
    _CanalCobranca edit,
    void Function(void Function()) setModalState,
  ) {
    return Row(
      children: [
        Text('Ativo:',
            style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: const Color(0xFF6B7280))),
        const SizedBox(width: 12),
        Switch(
          value: edit.ativo,
          activeThumbColor: PainelAdminTheme.roxo,
          onChanged: (v) => setModalState(() => edit.ativo = v),
        ),
      ],
    );
  }

  /// Botão de teste de conexão para WhatsApp, SMS e API Externa
  Widget _buildCanalTestButton({
    required bool testando,
    required bool testOk,
    required String testMsg,
    required VoidCallback onTestar,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FB),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.wifi_tethering_rounded,
                  size: 18, color: PainelAdminTheme.roxo),
              const SizedBox(width: 8),
              Text('Testar Conexão',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF1F2937))),
            ],
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: testando ? null : onTestar,
            icon: testando
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.send_rounded, size: 16),
            label: Text(testando ? 'Testando...' : 'Testar Conexão'),
            style: FilledButton.styleFrom(
              backgroundColor: PainelAdminTheme.roxo,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
          ),
          if (testMsg.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: testOk ? const Color(0xFFF0FDF4) : const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: testOk ? const Color(0xFFBBF7D0) : const Color(0xFFFECACA)),
              ),
              child: Row(
                children: [
                  Icon(
                    testOk ? Icons.check_circle_rounded : Icons.error_rounded,
                    size: 16,
                    color: testOk ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(testMsg,
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            color: testOk ? const Color(0xFF166534) : const Color(0xFF991B1B))),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Preview da mensagem com substituição de variáveis
  Widget _buildCanalPreview({
    required _CanalCobranca edit,
    required TextEditingController templateCtrl,
  }) {
    final msg = templateCtrl.text;
    final preview = msg
        .replaceAll('{cliente}', 'Maria Silva')
        .replaceAll('{valor}', 'R\$ 150,00')
        .replaceAll('{vencimento}', '15/07/2026')
        .replaceAll('{loja}', edit.nome.isNotEmpty ? edit.nome : 'Minha Loja')
        .replaceAll('{link}', 'https://dipertin.com.br/pagar/123456')
        .replaceAll('{dias_atraso}', '5')
        .replaceAll('{multa}', 'R\$ 7,50')
        .replaceAll('{juros}', 'R\$ 3,25');

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFBBF7D0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.preview_rounded,
                  size: 18, color: PainelAdminTheme.roxo),
              const SizedBox(width: 8),
              Text('Pré-visualização da mensagem',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF1F2937))),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: Text(
              preview.isNotEmpty ? preview : '(Mensagem vazia)',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  height: 1.4,
                  color: preview.isNotEmpty
                      ? const Color(0xFF1F2937)
                      : const Color(0xFF94A3B8)),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Variáveis disponíveis: {cliente}, {valor}, {vencimento}, {loja}, {link}, {dias_atraso}',
            style: GoogleFonts.plusJakartaSans(
                fontSize: 10, color: const Color(0xFF94A3B8)),
          ),
        ],
      ),
    );
  }

  Widget _buildFormCanalCobranca({
    required String chave,
    required _CanalCobranca edit,
    required TextEditingController templateCtrl,
    required bool ocultarToken,
    required void Function(void Function()) setModalState,
    required VoidCallback onToggleToken,
  }) {
    switch (chave) {
      case 'whatsapp':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildCanalInfoBox(
              'WhatsApp Business',
              'Informe a URL e o token da sua API (Meta Cloud, Evolution API, Z-API, etc.).',
            ),
            const SizedBox(height: 14),
            _modalField(
              label: 'Nome da integração',
              value: edit.nome,
              onChanged: (v) => edit.nome = v,
            ),
            const SizedBox(height: 12),
            _modalField(
              label: 'URL da API WhatsApp',
              value: edit.apiUrl,
              onChanged: (v) => edit.apiUrl = v,
            ),
            const SizedBox(height: 12),
            _modalFieldSecret(
              label: 'Token / API Key',
              value: edit.token,
              oculto: ocultarToken,
              onChanged: (v) => edit.token = v,
              onToggle: onToggleToken,
            ),
            const SizedBox(height: 12),
            _buildPhoneField(
              label: 'Número remetente (WhatsApp)',
              value: edit.remetente,
              onChanged: (v) => edit.remetente = v,
              hint: '(45) 99999-8888',
            ),
            const SizedBox(height: 12),
            _buildTemplateCobrancaField(templateCtrl),
            const SizedBox(height: 12),
            _buildCanalAtivoSwitch(edit, setModalState),
          ],
        );

      case 'email':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildCanalInfoBox(
              'E-mail transacional',
              'Configure SMTP ou API (SendGrid, Amazon SES, Mailgun, etc.).',
            ),
            const SizedBox(height: 14),
            _modalField(
              label: 'Nome da integração',
              value: edit.nome,
              onChanged: (v) => edit.nome = v,
            ),
            const SizedBox(height: 12),
            _modalField(
              label: 'URL da API / SMTP',
              value: edit.apiUrl,
              onChanged: (v) => edit.apiUrl = v,
            ),
            const SizedBox(height: 12),
            _modalFieldSecret(
              label: 'Token / Senha API',
              value: edit.token,
              oculto: ocultarToken,
              onChanged: (v) => edit.token = v,
              onToggle: onToggleToken,
            ),
            const SizedBox(height: 12),
            _modalField(
              label: 'E-mail remetente',
              value: edit.emailRemetente,
              onChanged: (v) => edit.emailRemetente = v,
            ),
            const SizedBox(height: 12),
            _modalField(
              label: 'Nome exibido (remetente)',
              value: edit.remetente,
              onChanged: (v) => edit.remetente = v,
            ),
            const SizedBox(height: 12),
            _buildTemplateCobrancaField(templateCtrl),
            const SizedBox(height: 12),
            _buildCanalAtivoSwitch(edit, setModalState),
          ],
        );

      case 'sms':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildCanalInfoBox(
              'Comtele SMS',
              'Envio de cobrança por SMS exclusivamente via Comtele. '
              'Use a Auth Key disponível em sms.comtele.com.br.',
            ),
            const SizedBox(height: 14),
            _modalField(
              label: 'Nome da integração',
              value: edit.nome,
              onChanged: (v) => edit.nome = v,
            ),
            const SizedBox(height: 12),
            InputDecorator(
              decoration: InputDecoration(
                labelText: 'URL da API (Comtele)',
                labelStyle: GoogleFonts.plusJakartaSans(fontSize: 13),
                filled: true,
                fillColor: const Color(0xFFF1F5F9),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
              child: SelectableText(
                _kComteleSmsApiUrl,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 13, color: const Color(0xFF64748B)),
              ),
            ),
            const SizedBox(height: 12),
            _modalFieldSecret(
              label: 'Auth Key (Comtele)',
              value: edit.token,
              oculto: ocultarToken,
              onChanged: (v) => edit.token = v,
              onToggle: onToggleToken,
            ),
            const SizedBox(height: 12),
            _modalField(
              label: 'Prefixo do remetente (nome curto)',
              value: edit.remetente,
              onChanged: (v) => edit.remetente = v,
            ),
            const SizedBox(height: 12),
            _buildTemplateCobrancaField(templateCtrl),
            const SizedBox(height: 8),
            Text(
              'SMS curto: evite acentos e mantenha a mensagem objetiva.',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 10, color: const Color(0xFF94A3B8)),
            ),
            const SizedBox(height: 12),
            _buildCanalAtivoSwitch(edit, setModalState),
          ],
        );

      case 'api_externa':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildCanalInfoBox(
              'API personalizada',
              'Conecte qualquer provedor HTTP. Defina endpoint, credenciais e template conforme a documentação do parceiro.',
            ),
            const SizedBox(height: 14),
            _modalField(
              label: 'Nome da integração',
              value: edit.nome,
              onChanged: (v) => edit.nome = v,
            ),
            const SizedBox(height: 12),
            _modalField(
              label: 'URL do endpoint',
              value: edit.apiUrl,
              onChanged: (v) => edit.apiUrl = v,
            ),
            const SizedBox(height: 12),
            _modalFieldSecret(
              label: 'Token / Bearer / API Key',
              value: edit.token,
              oculto: ocultarToken,
              onChanged: (v) => edit.token = v,
              onToggle: onToggleToken,
            ),
            const SizedBox(height: 12),
            _modalField(
              label: 'Identificador extra (header/param)',
              value: edit.remetente,
              onChanged: (v) => edit.remetente = v,
            ),
            const SizedBox(height: 12),
            _modalField(
              label: 'URL da documentação (opcional)',
              value: edit.emailRemetente,
              onChanged: (v) => edit.emailRemetente = v,
            ),
            const SizedBox(height: 12),
            _buildTemplateCobrancaField(templateCtrl),
            const SizedBox(height: 12),
            _buildCanalAtivoSwitch(edit, setModalState),
          ],
        );

      default:
        return const SizedBox.shrink();
    }
  }

  // ==========================================================================
  // ABA 4: REGRAS AUTOMÁTICAS
  // ==========================================================================
  Widget _buildAbaRegrasAutomaticas() {
    final ra = _config.regrasAutomaticas;
    return _CardConfig(
      titulo: 'Automação de cobrança',
      descricao:
          'Configure lembretes automáticos e regras de bloqueio de crédito.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _switchRow(
            label: 'Enviar lembrete antes do vencimento',
            value: ra.lembreteAntes,
            onChanged: (v) => setState(() => ra.lembreteAntes = v),
          ),
          if (ra.lembreteAntes) ...[
            const SizedBox(height: 6),
            SizedBox(
              width: 140,
              child: _IntFieldWidget(
                value: ra.diasAntes,
                onChanged: (v) => setState(() => ra.diasAntes = v),
              ),
            ),
          ],
          const Divider(height: 24),
          _switchRow(
            label: 'Enviar lembrete no dia do vencimento',
            value: ra.lembreteNoVencimento,
            onChanged: (v) => setState(() => ra.lembreteNoVencimento = v),
          ),
          const Divider(height: 24),
          _switchRow(
            label: 'Enviar lembrete após vencimento',
            value: ra.lembreteApos,
            onChanged: (v) => setState(() => ra.lembreteApos = v),
          ),
          if (ra.lembreteApos) ...[
            const SizedBox(height: 6),
            SizedBox(
              width: 140,
              child: _IntFieldWidget(
                value: ra.diasApos,
                onChanged: (v) => setState(() => ra.diasApos = v),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: 140,
              child: _IntFieldWidget(
                value: ra.repetirACadaDias,
                onChanged: (v) => setState(() => ra.repetirACadaDias = v),
              ),
            ),
          ],
          const Divider(height: 24),
          _switchRow(
            label: 'Bloquear crédito automaticamente após atraso',
            subtitle:
                'Apenas impede novas compras no crédito. Não bloqueia o cadastro do cliente.',
            value: ra.bloquearCreditoAutomaticamente,
            onChanged: (v) =>
                setState(() => ra.bloquearCreditoAutomaticamente = v),
          ),
          if (ra.bloquearCreditoAutomaticamente) ...[
            const SizedBox(height: 6),
            SizedBox(
              width: 140,
              child: _IntFieldWidget(
                value: ra.bloquearAposDias,
                onChanged: (v) => setState(() => ra.bloquearAposDias = v),
              ),
            ),
            const SizedBox(height: 12),
            _switchRow(
              label: 'Enviar aviso ao bloquear crédito',
              value: ra.enviarAvisoBloqueio,
              onChanged: (v) => setState(() => ra.enviarAvisoBloqueio = v),
            ),
          ],
          const SizedBox(height: 24),
          _buildBotaoProcessarAutomacao(),
        ],
      ),
    );
  }

  bool _processandoAutomacao = false;

  Widget _buildBotaoProcessarAutomacao() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 1),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Processar automação agora',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF1F2937))),
                  const SizedBox(height: 2),
                  Text(
                      'Executa manualmente as regras configuradas acima. A automação também roda automaticamente todos os dias às 08:00.',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 12, color: const Color(0xFF64748B))),
                ],
              ),
            ),
            const SizedBox(width: 16),
            FilledButton.icon(
              onPressed: _processandoAutomacao
                  ? null
                  : () => _processarAutomacaoAgora(),
              icon: _processandoAutomacao
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.play_arrow_rounded, size: 20),
              label: Text(_processandoAutomacao
                  ? 'Processando...'
                  : 'Processar Agora'),
              style: FilledButton.styleFrom(
                  backgroundColor: PainelAdminTheme.roxo,
                  disabledBackgroundColor:
                      PainelAdminTheme.roxo.withValues(alpha: 0.6)),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _processarAutomacaoAgora() async {
    setState(() => _processandoAutomacao = true);
    try {
      final result = await callFirebaseFunctionSafe(
        'gestaoComercialAutomacaoProcessarLoja',
        region: 'southamerica-east1',
        parameters: {'lojaId': _lojaId},
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Processado: ${result['processados'] ?? 0} notificações enviadas, ${result['erros'] ?? 0} erros.'),
          backgroundColor: const Color(0xFF16A34A),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro: ${e.toString()}'),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _processandoAutomacao = false);
    }
  }

  // ==========================================================================
  // WIDGETS AUXILIARES
  // ==========================================================================

  Widget _switchRow({
    required String label,
    String? subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(label,
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: const Color(0xFF1F2937))),
            ),
            Switch(
              value: value,
              activeThumbColor: PainelAdminTheme.roxo,
              onChanged: onChanged,
            ),
          ],
        ),
        if (subtitle != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(subtitle,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 11, color: const Color(0xFF94A3B8))),
          ),
      ],
    );
  }

  Widget _infoLinha(String label, String valor) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text('$label: $valor',
          style: GoogleFonts.plusJakartaSans(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: const Color(0xFF94A3B8))),
    );
  }

  Widget _modalField({
    required String label,
    required String value,
    required ValueChanged<String> onChanged,
  }) {
    final ctrl = TextEditingController(text: value);
    return TextField(
      controller: ctrl,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.plusJakartaSans(fontSize: 13),
        filled: true,
        fillColor: const Color(0xFFF8F9FB),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
      ),
      onChanged: onChanged,
    );
  }

  Widget _modalFieldSecret({
    required String label,
    required String value,
    required bool oculto,
    required ValueChanged<String> onChanged,
    required VoidCallback onToggle,
  }) {
    final ctrl = TextEditingController(text: value);
    return TextField(
      controller: ctrl,
      obscureText: oculto,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.plusJakartaSans(fontSize: 13),
        filled: true,
        fillColor: const Color(0xFFF8F9FB),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        suffixIcon: IconButton(
          icon: Icon(oculto ? Icons.visibility_off_rounded : Icons.visibility_rounded,
              size: 18),
          onPressed: onToggle,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
      ),
      onChanged: onChanged,
    );
  }

  Widget _buildPhoneField({
    required String label,
    required String value,
    required ValueChanged<String> onChanged,
    String? hint,
  }) {
    final ctrl = TextEditingController(text: value);
    return TextField(
      controller: ctrl,
      inputFormatters: [_TelefoneInputFormatter()],
      keyboardType: TextInputType.phone,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint ?? '(00) 00000-0000',
        hintStyle: GoogleFonts.plusJakartaSans(fontSize: 12, color: const Color(0xFF94A3B8)),
        labelStyle: GoogleFonts.plusJakartaSans(fontSize: 13),
        filled: true,
        fillColor: const Color(0xFFF8F9FB),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
      ),
      onChanged: onChanged,
    );
  }

  Widget _modalDropdown({
    required String label,
    required String value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    final valorEfetivo =
        items.contains(value) ? value : (items.isNotEmpty ? items.first : value);
    return DropdownButtonFormField<String>(
      initialValue: valorEfetivo,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.plusJakartaSans(fontSize: 13),
        filled: true,
        fillColor: const Color(0xFFF8F9FB),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
      ),
      items: items
          .map((s) => DropdownMenuItem(
              value: s, child: Text(s, style: const TextStyle(fontSize: 13))))
          .toList(),
      onChanged: onChanged,
    );
  }
}

// =============================================================================
// WIDGET: Campo de preview estável
// =============================================================================

class _CampoPreviewWidget extends StatefulWidget {
  final String label;
  final TextEditingController controller;
  final String? prefix;
  final VoidCallback onChanged;

  const _CampoPreviewWidget({
    required this.label,
    required this.controller,
    this.prefix,
    required this.onChanged,
  });

  @override
  State<_CampoPreviewWidget> createState() => _CampoPreviewWidgetState();
}

class _CampoPreviewWidgetState extends State<_CampoPreviewWidget> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(widget.onChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(widget.onChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.controller,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(
        labelText: widget.label,
        labelStyle: GoogleFonts.plusJakartaSans(fontSize: 13),
        prefixText: widget.prefix,
        filled: true,
        fillColor: const Color(0xFFF8F9FB),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}
// =============================================================================

class _CardConfig extends StatelessWidget {
  const _CardConfig({
    required this.titulo,
    required this.descricao,
    required this.child,
  });

  final String titulo;
  final String descricao;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEEEAF6)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1A1A2E).withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(titulo,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF1A1A2E))),
          const SizedBox(height: 6),
          Text(descricao,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                  color: const Color(0xFF6B7280))),
          const SizedBox(height: 20),
          child,
        ],
      ),
    );
  }
}

// =============================================================================
// WIDGET: Campo percentual com TextEditingController estável
// =============================================================================

class _PercentFieldWidget extends StatefulWidget {
  final double value;
  final ValueChanged<double> onChanged;

  const _PercentFieldWidget({
    required this.value,
    required this.onChanged,
  });

  @override
  State<_PercentFieldWidget> createState() => _PercentFieldWidgetState();
}

class _PercentFieldWidgetState extends State<_PercentFieldWidget> {
  late TextEditingController _ctrl;
  late FocusNode _focus;
  bool _isUserEditing = false;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: _fmt(widget.value));
    _focus = FocusNode();
    _focus.addListener(() {
      if (!_focus.hasFocus) {
        _isUserEditing = false;
        _syncFromParent();
      }
    });
  }

  @override
  void didUpdateWidget(_PercentFieldWidget old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value && !_isUserEditing && !_focus.hasFocus) {
      _ctrl.text = _fmt(widget.value);
    }
  }

  @override
  void dispose() {
    _focus.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  void _syncFromParent() {
    if (_ctrl.text.isNotEmpty) {
      final parsed = _parse(_ctrl.text);
      if (parsed != widget.value) {
        _ctrl.text = _fmt(widget.value);
      }
    } else {
      _ctrl.text = _fmt(widget.value);
    }
  }

  static String _fmt(double v) => v.toStringAsFixed(2);
  static double _parse(String t) => double.tryParse(t.replaceAll(',', '.')) ?? 0;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _ctrl,
      focusNode: _focus,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      textAlign: TextAlign.right,
      decoration: InputDecoration(
        labelText: 'Percentual',
        labelStyle: GoogleFonts.plusJakartaSans(fontSize: 13),
        suffixText: '%',
        suffixStyle: GoogleFonts.plusJakartaSans(
            fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFF374151)),
        filled: true,
        fillColor: const Color(0xFFF8F9FB),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
      ),
      onChanged: (v) {
        final cleaned = v.replaceAll(RegExp(r'[^0-9,.]'), '');
        if (cleaned != v) {
          _ctrl.text = cleaned;
          _ctrl.selection = TextSelection.collapsed(offset: cleaned.length);
        }
        _isUserEditing = cleaned.isNotEmpty;
        widget.onChanged(_parse(cleaned));
      },
    );
  }
}

// =============================================================================
// WIDGET: Campo inteiro — estável, sem bugs
// =============================================================================

class _IntFieldWidget extends StatefulWidget {
  final int value;
  final ValueChanged<int> onChanged;

  const _IntFieldWidget({
    required this.value,
    required this.onChanged,
  });

  @override
  State<_IntFieldWidget> createState() => _IntFieldWidgetState();
}

class _IntFieldWidgetState extends State<_IntFieldWidget> {
  late TextEditingController _ctrl;
  late FocusNode _focus;
  bool _isUserEditing = false;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.value.toString());
    _focus = FocusNode();
    _focus.addListener(() {
      if (!_focus.hasFocus) {
        _isUserEditing = false;
        if (_ctrl.text.isEmpty || int.tryParse(_ctrl.text) == null) {
          _ctrl.text = widget.value.toString();
        }
      }
    });
  }

  @override
  void didUpdateWidget(_IntFieldWidget old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value && !_isUserEditing && !_focus.hasFocus) {
      _ctrl.text = widget.value.toString();
    }
  }

  @override
  void dispose() {
    _focus.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _ctrl,
      focusNode: _focus,
      keyboardType: TextInputType.number,
      textAlign: TextAlign.right,
      decoration: InputDecoration(
        labelText: 'Dias',
        labelStyle: GoogleFonts.plusJakartaSans(fontSize: 13),
        filled: true,
        fillColor: const Color(0xFFF8F9FB),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
      ),
      onChanged: (v) {
        final cleaned = v.replaceAll(RegExp(r'[^0-9]'), '');
        if (cleaned != v) {
          _ctrl.text = cleaned;
          _ctrl.selection = TextSelection.collapsed(offset: cleaned.length);
        }
        _isUserEditing = cleaned.isNotEmpty;
        widget.onChanged(int.tryParse(cleaned) ?? 0);
      },
    );
  }
}
