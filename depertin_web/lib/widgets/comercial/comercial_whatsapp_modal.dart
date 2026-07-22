import 'package:depertin_web/services/firebase_functions_config.dart';
import 'package:depertin_web/theme/painel_admin_theme.dart';
import 'package:depertin_web/widgets/comercial/comercial_modal_ui.dart';
import 'package:depertin_web/widgets/dipertin_feedback_premium_modal.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

const _kSecretMask = '••••••••';
const _kVzapsApiBase = 'https://api.vzaps.com';
const _kTemplatePadrao =
    'Olá, {cliente}, sua parcela no valor de {valor} vence em {vencimento}. Link de pagamento: {link}';

/// Dados serializáveis do canal WhatsApp (espelha Firestore `cobranca.whatsapp`).
class WhatsAppCanalConfig {
  String nome;
  String provedor;
  String apiUrl;
  String token;
  String clientToken;
  String clientSecret;
  String instanceId;
  String remetente;
  String authMethod;
  String endpointEnvio;
  String templateMensagem;
  bool ativo;
  bool conexaoOk;
  String telefoneConectado;

  WhatsAppCanalConfig({
    this.nome = '',
    this.provedor = '',
    this.apiUrl = '',
    this.token = '',
    this.clientToken = '',
    this.clientSecret = '',
    this.instanceId = '',
    this.remetente = '',
    this.authMethod = 'bearer',
    this.endpointEnvio = '',
    this.templateMensagem = _kTemplatePadrao,
    this.ativo = false,
    this.conexaoOk = false,
    this.telefoneConectado = '',
  });

  factory WhatsAppCanalConfig.fromMap(Map<String, dynamic>? m) {
    if (m == null) return WhatsAppCanalConfig();
    return WhatsAppCanalConfig(
      nome: m['nome']?.toString() ?? '',
      provedor: m['provedor']?.toString() ?? '',
      apiUrl: m['apiUrl']?.toString() ?? '',
      token: m['token']?.toString() ?? '',
      clientToken: m['clientToken']?.toString() ?? '',
      clientSecret: m['clientSecret']?.toString() ?? '',
      instanceId: m['instanceId']?.toString() ?? '',
      remetente: m['remetente']?.toString() ?? '',
      authMethod: m['authMethod']?.toString() ?? 'bearer',
      endpointEnvio: m['endpointEnvio']?.toString() ?? '',
      templateMensagem: (m['templateMensagem']?.toString().trim().isNotEmpty == true)
          ? m['templateMensagem'].toString()
          : _kTemplatePadrao,
      ativo: m['ativo'] == true,
      conexaoOk: m['conexaoOk'] == true,
      telefoneConectado: m['telefoneConectado']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toMap() => {
        'nome': nome,
        'tipo': 'whatsapp',
        'provedor': provedor,
        'apiUrl': apiUrl,
        'token': token,
        'clientToken': clientToken,
        'clientSecret': clientSecret,
        'instanceId': instanceId,
        'remetente': remetente,
        'authMethod': authMethod,
        'endpointEnvio': endpointEnvio,
        'templateMensagem': templateMensagem,
        'ativo': ativo,
        'conexaoOk': conexaoOk,
        'telefoneConectado': telefoneConectado,
      };

  String get provedorRotulo {
    switch (provedor) {
      case 'vzaps':
        return 'VZaps';
      case 'meta':
        return 'Meta Cloud';
      case 'evolution':
        return 'Evolution API';
      case 'zapi':
        return 'Z-API';
      case 'custom':
        return 'Outro provedor';
      default:
        return provedor.isEmpty ? 'Não definido' : provedor;
    }
  }

  bool get estaConfigurado {
    switch (provedor) {
      case 'vzaps':
        return instanceId.trim().isNotEmpty &&
            (clientToken.trim().isNotEmpty || clientToken == _kSecretMask) &&
            (token.trim().isNotEmpty || token == _kSecretMask);
      case 'meta':
      case 'evolution':
      case 'zapi':
      case 'custom':
        return apiUrl.trim().isNotEmpty &&
            (token.trim().isNotEmpty || token == _kSecretMask);
      default:
        return apiUrl.trim().isNotEmpty && token.trim().isNotEmpty;
    }
  }
}

class _ProvedorOpcao {
  final String id;
  final String nome;
  final String descricao;
  final IconData icone;
  final bool destaque;

  const _ProvedorOpcao({
    required this.id,
    required this.nome,
    required this.descricao,
    required this.icone,
    this.destaque = false,
  });
}

const _provedores = <_ProvedorOpcao>[
  _ProvedorOpcao(
    id: 'vzaps',
    nome: 'VZaps',
    descricao:
        'API oficial com instâncias isoladas, QR Code e tokens por instância.',
    icone: Icons.bolt_rounded,
    destaque: true,
  ),
  _ProvedorOpcao(
    id: 'meta',
    nome: 'Meta Cloud API',
    descricao: 'WhatsApp Business oficial via Graph API da Meta.',
    icone: Icons.cloud_rounded,
  ),
  _ProvedorOpcao(
    id: 'evolution',
    nome: 'Evolution API',
    descricao: 'API open-source popular para envio de mensagens WhatsApp.',
    icone: Icons.hub_rounded,
  ),
  _ProvedorOpcao(
    id: 'zapi',
    nome: 'Z-API',
    descricao: 'Provedor brasileiro com Client-Token e envio por telefone.',
    icone: Icons.smartphone_rounded,
  ),
  _ProvedorOpcao(
    id: 'custom',
    nome: 'Outro provedor / API personalizada',
    descricao:
        'Configure URL, endpoint, autenticação e template para qualquer API.',
    icone: Icons.tune_rounded,
  ),
];

Future<void> showComercialWhatsAppModal(
  BuildContext context, {
  required String lojaId,
  required Map<String, dynamic> canalAtual,
  required void Function(WhatsAppCanalConfig config) onSalvo,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    useRootNavigator: true,
    builder: (_) => _ComercialWhatsAppModal(
      lojaId: lojaId,
      inicial: WhatsAppCanalConfig.fromMap(canalAtual),
      onSalvo: onSalvo,
    ),
  );
}

class _ComercialWhatsAppModal extends StatefulWidget {
  const _ComercialWhatsAppModal({
    required this.lojaId,
    required this.inicial,
    required this.onSalvo,
  });

  final String lojaId;
  final WhatsAppCanalConfig inicial;
  final void Function(WhatsAppCanalConfig config) onSalvo;

  @override
  State<_ComercialWhatsAppModal> createState() =>
      _ComercialWhatsAppModalState();
}

class _ComercialWhatsAppModalState extends State<_ComercialWhatsAppModal> {
  late int _etapa; // 1 provedor · 2 credenciais · 3 teste/salvar
  late String _provedor;
  late final TextEditingController _nomeCtrl;
  late final TextEditingController _apiUrlCtrl;
  late final TextEditingController _tokenCtrl;
  late final TextEditingController _clientTokenCtrl;
  late final TextEditingController _clientSecretCtrl;
  late final TextEditingController _instanceIdCtrl;
  late final TextEditingController _remetenteCtrl;
  late final TextEditingController _endpointCtrl;
  late final TextEditingController _templateCtrl;
  String _authMethod = 'bearer';
  bool _ativo = false;
  bool _ocultarToken = true;
  bool _ocultarClientToken = true;
  bool _ocultarClientSecret = true;
  bool _tokenSalvo = false;
  bool _clientTokenSalvo = false;
  bool _clientSecretSalvo = false;
  bool _testando = false;
  bool _salvando = false;
  bool _testeOk = false;
  String _testeMsg = '';
  String _telefoneConectado = '';

  @override
  void initState() {
    super.initState();
    final i = widget.inicial;
    _provedor = i.provedor.isNotEmpty ? i.provedor : '';
    _etapa = _provedor.isNotEmpty ? 2 : 1;
    _nomeCtrl = TextEditingController(
        text: i.nome.isNotEmpty ? i.nome : 'WhatsApp');
    _apiUrlCtrl = TextEditingController(
        text: i.apiUrl.isNotEmpty
            ? i.apiUrl
            : (_provedor == 'vzaps' ? _kVzapsApiBase : ''));
    _tokenSalvo = i.token.trim().isNotEmpty;
    _clientTokenSalvo = i.clientToken.trim().isNotEmpty;
    _clientSecretSalvo = i.clientSecret.trim().isNotEmpty;
    _tokenCtrl =
        TextEditingController(text: _tokenSalvo ? _kSecretMask : '');
    _clientTokenCtrl =
        TextEditingController(text: _clientTokenSalvo ? _kSecretMask : '');
    _clientSecretCtrl =
        TextEditingController(text: _clientSecretSalvo ? _kSecretMask : '');
    _instanceIdCtrl = TextEditingController(text: i.instanceId);
    _remetenteCtrl = TextEditingController(text: i.remetente);
    _endpointCtrl = TextEditingController(text: i.endpointEnvio);
    _templateCtrl = TextEditingController(
        text: i.templateMensagem.isNotEmpty
            ? i.templateMensagem
            : _kTemplatePadrao);
    _authMethod = i.authMethod.isNotEmpty ? i.authMethod : 'bearer';
    _ativo = i.ativo;
    _testeOk = i.conexaoOk;
    _telefoneConectado = i.telefoneConectado;
  }

  @override
  void dispose() {
    _nomeCtrl.dispose();
    _apiUrlCtrl.dispose();
    _tokenCtrl.dispose();
    _clientTokenCtrl.dispose();
    _clientSecretCtrl.dispose();
    _instanceIdCtrl.dispose();
    _remetenteCtrl.dispose();
    _endpointCtrl.dispose();
    _templateCtrl.dispose();
    super.dispose();
  }

  String _valorSegredo(TextEditingController ctrl, bool salvo) {
    final v = ctrl.text.trim();
    if (v.isEmpty || v == _kSecretMask) {
      return salvo ? _kSecretMask : '';
    }
    return v;
  }

  Map<String, dynamic> _credenciaisParaTeste() {
    final map = <String, dynamic>{
      'provedor': _provedor,
      'nome': _nomeCtrl.text.trim(),
      'apiUrl': _provedor == 'vzaps'
          ? (_apiUrlCtrl.text.trim().isEmpty
              ? _kVzapsApiBase
              : _apiUrlCtrl.text.trim())
          : _apiUrlCtrl.text.trim(),
      'instanceId': _instanceIdCtrl.text.trim(),
      'remetente': _remetenteCtrl.text.trim(),
      'authMethod': _authMethod,
      'endpointEnvio': _endpointCtrl.text.trim(),
      'templateMensagem': _templateCtrl.text.trim(),
    };
    final token = _valorSegredo(_tokenCtrl, _tokenSalvo);
    final clientToken = _valorSegredo(_clientTokenCtrl, _clientTokenSalvo);
    final clientSecret = _valorSegredo(_clientSecretCtrl, _clientSecretSalvo);
    if (token.isNotEmpty) map['token'] = token;
    if (clientToken.isNotEmpty) map['clientToken'] = clientToken;
    if (clientSecret.isNotEmpty) map['clientSecret'] = clientSecret;
    return map;
  }

  bool _validarCredenciais() {
    if (_provedor == 'vzaps') {
      if (_instanceIdCtrl.text.trim().isEmpty) {
        _avisar('Informe o ID da instância VZaps (começa com VZ...).');
        return false;
      }
      if (_valorSegredo(_tokenCtrl, _tokenSalvo).isEmpty) {
        _avisar(
          'Informe o Token da instância (coluna Token no painel VZaps).',
        );
        return false;
      }
      if (_valorSegredo(_clientTokenCtrl, _clientTokenSalvo).isEmpty) {
        _avisar(
          'Informe o Client Token da conta (menu Segurança / API na VZaps).',
        );
        return false;
      }
      return true;
    }
    if (_apiUrlCtrl.text.trim().isEmpty) {
      _avisar('Informe a URL da API do provedor.');
      return false;
    }
    if (_valorSegredo(_tokenCtrl, _tokenSalvo).isEmpty) {
      _avisar('Informe o Token / API Key.');
      return false;
    }
    if (_provedor == 'custom' && _endpointCtrl.text.trim().isEmpty) {
      _avisar('Informe o endpoint de envio da API personalizada.');
      return false;
    }
    if (_templateCtrl.text.trim().isEmpty) {
      _avisar('Informe o template da mensagem de cobrança.');
      return false;
    }
    return true;
  }

  Future<void> _avisar(String msg) {
    return mostrarDiPertinFeedbackPremium(
      context,
      sucesso: false,
      titulo: 'Dados incompletos',
      mensagem: msg,
      botaoTexto: 'OK',
    );
  }

  Future<void> _testarConexao() async {
    if (!_validarCredenciais()) return;
    setState(() {
      _testando = true;
      _testeOk = false;
      _testeMsg = '';
      _telefoneConectado = '';
    });
    try {
      final result = await callFirebaseFunctionSafe(
        'gestaoComercialWhatsAppTestarConexao',
        parameters: {
          'lojaId': widget.lojaId,
          'credenciais': _credenciaisParaTeste(),
        },
        region: 'southamerica-east1',
      );
      if (!mounted) return;
      final ok = result['ok'] == true;
      setState(() {
        _testando = false;
        _testeOk = ok;
        _testeMsg = (result['mensagem'] ?? '').toString();
        _telefoneConectado =
            (result['telefoneConectado'] ?? '').toString();
        if (ok) _ativo = true;
      });
    } on CallableHttpException catch (e) {
      if (!mounted) return;
      setState(() {
        _testando = false;
        _testeOk = false;
        _testeMsg = mensagemCallableHttpException(e);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _testando = false;
        _testeOk = false;
        _testeMsg = e.toString();
      });
    }
  }

  Future<void> _salvar() async {
    if (!_testeOk) {
      await _avisar(
          'Teste a conexão com sucesso antes de salvar a integração.');
      return;
    }
    if (!_validarCredenciais()) return;

    setState(() => _salvando = true);
    final cfg = WhatsAppCanalConfig(
      nome: _nomeCtrl.text.trim().isEmpty ? 'WhatsApp' : _nomeCtrl.text.trim(),
      provedor: _provedor,
      apiUrl: _provedor == 'vzaps'
          ? (_apiUrlCtrl.text.trim().isEmpty
              ? _kVzapsApiBase
              : _apiUrlCtrl.text.trim())
          : _apiUrlCtrl.text.trim(),
      token: _valorSegredo(_tokenCtrl, _tokenSalvo),
      clientToken: _valorSegredo(_clientTokenCtrl, _clientTokenSalvo),
      clientSecret: _valorSegredo(_clientSecretCtrl, _clientSecretSalvo),
      instanceId: _instanceIdCtrl.text.trim(),
      remetente: _remetenteCtrl.text.trim().isNotEmpty
          ? _remetenteCtrl.text.trim()
          : _telefoneConectado,
      authMethod: _authMethod,
      endpointEnvio: _endpointCtrl.text.trim(),
      templateMensagem: _templateCtrl.text.trim(),
      ativo: _ativo,
      conexaoOk: true,
      telefoneConectado: _telefoneConectado,
    );

    // Se segredo veio mascarado, preserva o valor já criptografado no Firestore
    // passando a máscara — o backend/tela pai não sobrescreve com vazio.
    // A tela pai grava o mapa; o trigger de encrypt só age em texto puro.
    if (cfg.token == _kSecretMask) {
      cfg.token = widget.inicial.token;
    }
    if (cfg.clientToken == _kSecretMask) {
      cfg.clientToken = widget.inicial.clientToken;
    }
    if (cfg.clientSecret == _kSecretMask) {
      cfg.clientSecret = widget.inicial.clientSecret;
    }

    widget.onSalvo(cfg);
    if (!mounted) return;
    setState(() => _salvando = false);
    Navigator.of(context, rootNavigator: true).pop();
  }

  void _selecionarProvedor(String id) {
    setState(() {
      _provedor = id;
      _testeOk = false;
      _testeMsg = '';
      if (id == 'vzaps' && _apiUrlCtrl.text.trim().isEmpty) {
        _apiUrlCtrl.text = _kVzapsApiBase;
      }
      if (_nomeCtrl.text.trim().isEmpty || _nomeCtrl.text == 'WhatsApp') {
        _nomeCtrl.text = id == 'vzaps'
            ? 'VZaps'
            : id == 'custom'
                ? 'API personalizada'
                : 'WhatsApp';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final maxH = MediaQuery.sizeOf(context).height * 0.88;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 640, maxHeight: maxH),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ComercialModalHeader(
              titulo: 'Configurar WhatsApp',
              subtitulo: _subtituloEtapa(),
              icone: Icons.chat_rounded,
              onFechar: () => Navigator.of(context, rootNavigator: true).pop(),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
              child: _buildStepper(),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
                child: _buildEtapaConteudo(),
              ),
            ),
            const Divider(height: 1, color: Color(0xFFE8E4F0)),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              child: _buildRodape(),
            ),
          ],
        ),
      ),
    );
  }

  String _subtituloEtapa() {
    switch (_etapa) {
      case 1:
        return 'Etapa 1 · Escolha o provedor de envio';
      case 2:
        return 'Etapa 2 · Credenciais ${_provedorRotuloCurto()}';
      default:
        return 'Etapa 3 · Testar conexão e salvar';
    }
  }

  String _provedorRotuloCurto() {
    final p = _provedores.where((e) => e.id == _provedor).toList();
    return p.isEmpty ? '' : '· ${p.first.nome}';
  }

  Widget _buildStepper() {
    Widget step(int n, String label) {
      final ativo = _etapa == n;
      final feito = _etapa > n;
      final cor = feito || ativo
          ? PainelAdminTheme.roxo
          : const Color(0xFF94A3B8);
      return Expanded(
        child: Column(
          children: [
            Row(
              children: [
                if (n > 1)
                  Expanded(
                    child: Container(
                      height: 2,
                      color: _etapa >= n
                          ? PainelAdminTheme.roxo.withValues(alpha: 0.35)
                          : const Color(0xFFE2E8F0),
                    ),
                  ),
                Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: feito || ativo
                        ? PainelAdminTheme.roxo
                        : const Color(0xFFF1F5F9),
                    shape: BoxShape.circle,
                    border: Border.all(color: cor, width: 1.5),
                  ),
                  child: feito
                      ? const Icon(Icons.check_rounded,
                          size: 14, color: Colors.white)
                      : Text('$n',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: ativo ? Colors.white : cor,
                          )),
                ),
                if (n < 3)
                  Expanded(
                    child: Container(
                      height: 2,
                      color: _etapa > n
                          ? PainelAdminTheme.roxo.withValues(alpha: 0.35)
                          : const Color(0xFFE2E8F0),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(label,
                textAlign: TextAlign.center,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 11,
                  fontWeight: ativo ? FontWeight.w700 : FontWeight.w500,
                  color: cor,
                )),
          ],
        ),
      );
    }

    return Row(
      children: [
        step(1, 'Provedor'),
        step(2, 'Credenciais'),
        step(3, 'Teste'),
      ],
    );
  }

  Widget _buildEtapaConteudo() {
    switch (_etapa) {
      case 1:
        return _buildEtapaProvedor();
      case 2:
        return _buildEtapaCredenciais();
      default:
        return _buildEtapaTeste();
    }
  }

  Widget _buildEtapaProvedor() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Selecione a plataforma que você usa para enviar WhatsApp. '
          'O fluxo de configuração muda conforme o provedor.',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 13,
            color: const Color(0xFF64748B),
            height: 1.4,
          ),
        ),
        const SizedBox(height: 14),
        ..._provedores.map((p) {
          final sel = _provedor == p.id;
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => _selecionarProvedor(p.id),
                borderRadius: BorderRadius.circular(14),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: sel
                        ? const Color(0xFFF3E8FF)
                        : Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: sel
                          ? PainelAdminTheme.roxo
                          : const Color(0xFFE8E4F0),
                      width: sel ? 1.6 : 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          gradient: sel
                              ? const LinearGradient(
                                  colors: [
                                    Color(0xFF6A1B9A),
                                    Color(0xFF8E24AA),
                                  ],
                                )
                              : null,
                          color: sel ? null : const Color(0xFFF8F6FF),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(p.icone,
                            color: sel
                                ? Colors.white
                                : PainelAdminTheme.roxo,
                            size: 22),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(p.nome,
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w800,
                                        color: const Color(0xFF1A1A2E),
                                      )),
                                ),
                                if (p.destaque) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFFF3E0),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text('Recomendado',
                                        style: GoogleFonts.plusJakartaSans(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                          color: PainelAdminTheme.laranja,
                                        )),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(p.descricao,
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 12,
                                  color: const Color(0xFF64748B),
                                )),
                          ],
                        ),
                      ),
                      Icon(
                        sel
                            ? Icons.radio_button_checked_rounded
                            : Icons.radio_button_off_rounded,
                        color: sel
                            ? PainelAdminTheme.roxo
                            : const Color(0xFF94A3B8),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildEtapaCredenciais() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_provedor == 'vzaps')
          _infoBox(
            'VZaps — o que copiar do painel',
            '1) ID da instância = coluna ID (ex.: VZP0Z...)\n'
                '2) Token da instância = coluna Token da tabela de Instâncias '
                '(vai em X-Instance-Token)\n'
                '3) Client Token = em Segurança / API da conta VZaps '
                '(X-Client-Token)\n'
                'Client Secret é opcional. Docs: docs.vzaps.com',
          )
        else if (_provedor == 'custom')
          _infoBox(
            'API personalizada',
            'Informe URL base, endpoint de envio, método de autenticação e '
                'template. Variáveis: {cliente}, {valor}, {vencimento}, {loja}, {link}, {dias_atraso}.',
          )
        else
          _infoBox(
            'Credenciais do provedor',
            'Preencha URL e token conforme a documentação do ${_provedorRotuloCurto().replaceAll('· ', '')}.',
          ),
        const SizedBox(height: 14),
        _campo('Nome da integração', _nomeCtrl),
        const SizedBox(height: 12),
        if (_provedor == 'vzaps') ...[
          _campo('ID da instância (coluna ID no painel VZaps)', _instanceIdCtrl,
              hint: 'VZP0ZPNQJ5IY4F2DJPMTALJSJUPTWHLPGV'),
          const SizedBox(height: 12),
          _campoSegredo(
            'Token da instância (coluna Token → X-Instance-Token)',
            _tokenCtrl,
            oculto: _ocultarToken,
            onToggle: () => setState(() => _ocultarToken = !_ocultarToken),
          ),
          const SizedBox(height: 4),
          Text(
            'Cole aqui o Token da linha da instância (ex.: b3om6EAA...).',
            style: GoogleFonts.plusJakartaSans(
                fontSize: 11, color: const Color(0xFF94A3B8)),
          ),
          const SizedBox(height: 12),
          _campoSegredo(
            'Client Token da conta (Segurança → X-Client-Token)',
            _clientTokenCtrl,
            oculto: _ocultarClientToken,
            onToggle: () =>
                setState(() => _ocultarClientToken = !_ocultarClientToken),
          ),
          const SizedBox(height: 12),
          _campoSegredo(
            'Client Secret (opcional)',
            _clientSecretCtrl,
            oculto: _ocultarClientSecret,
            onToggle: () =>
                setState(() => _ocultarClientSecret = !_ocultarClientSecret),
          ),
          const SizedBox(height: 12),
          _campo('URL da API (padrão VZaps)', _apiUrlCtrl,
              hint: _kVzapsApiBase),
        ] else ...[
          _campo('URL da API', _apiUrlCtrl,
              hint: _provedor == 'meta'
                  ? 'https://graph.facebook.com'
                  : 'https://sua-api.com'),
          const SizedBox(height: 12),
          _campoSegredo(
            'Token / API Key',
            _tokenCtrl,
            oculto: _ocultarToken,
            onToggle: () => setState(() => _ocultarToken = !_ocultarToken),
          ),
          if (_provedor == 'meta' || _provedor == 'evolution') ...[
            const SizedBox(height: 12),
            _campo(
              _provedor == 'meta'
                  ? 'Phone Number ID (remetente)'
                  : 'Nome da instância / remetente',
              _remetenteCtrl,
            ),
          ],
          if (_provedor == 'custom') ...[
            const SizedBox(height: 12),
            _campo('Endpoint de envio', _endpointCtrl,
                hint: '/messages ou URL completa'),
            const SizedBox(height: 12),
            Text('Método de autenticação',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFF6B7280))),
            const SizedBox(height: 6),
            DropdownButtonFormField<String>(
              initialValue: _authMethod,
              items: const [
                DropdownMenuItem(value: 'bearer', child: Text('Bearer Token')),
                DropdownMenuItem(
                    value: 'apikey', child: Text('Header apikey')),
                DropdownMenuItem(
                    value: 'x_api_key', child: Text('Header X-API-Key')),
                DropdownMenuItem(
                    value: 'client_token', child: Text('Client-Token')),
              ],
              onChanged: (v) {
                if (v != null) setState(() => _authMethod = v);
              },
              decoration: _decoCampo(),
            ),
            const SizedBox(height: 12),
            _campo('Número remetente (opcional)', _remetenteCtrl),
          ],
        ],
        const SizedBox(height: 12),
        Text('Template da mensagem',
            style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: const Color(0xFF6B7280))),
        const SizedBox(height: 6),
        TextField(
          controller: _templateCtrl,
          maxLines: 4,
          onChanged: (_) => setState(() {
            _testeOk = false;
          }),
          decoration: _decoCampo(),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            '{cliente}',
            '{valor}',
            '{vencimento}',
            '{loja}',
            '{link}',
            '{dias_atraso}',
          ]
              .map((t) => ActionChip(
                    label: Text(t,
                        style: GoogleFonts.plusJakartaSans(fontSize: 11)),
                    onPressed: () {
                      final c = _templateCtrl;
                      final text = c.text;
                      final sel = c.selection;
                      final start =
                          sel.isValid ? sel.start : text.length;
                      final end = sel.isValid ? sel.end : text.length;
                      final novo = text.replaceRange(start, end, t);
                      c.value = TextEditingValue(
                        text: novo,
                        selection:
                            TextSelection.collapsed(offset: start + t.length),
                      );
                      setState(() => _testeOk = false);
                    },
                    backgroundColor: const Color(0xFFF8F6FF),
                    side: const BorderSide(color: Color(0xFFE8E4F0)),
                    visualDensity: VisualDensity.compact,
                  ))
              .toList(),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Text('Ativar após salvar:',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFF6B7280))),
            const SizedBox(width: 10),
            Switch(
              value: _ativo,
              activeThumbColor: PainelAdminTheme.roxo,
              onChanged: (v) => setState(() => _ativo = v),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildEtapaTeste() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _infoBox(
          'Validação obrigatória',
          _provedor == 'vzaps'
              ? 'O teste consulta GET /instances/{id}/session/status na VZaps. '
                  'Só é possível salvar se a instância estiver conectada (QR pareado).'
              : 'Testamos a conexão com o provedor selecionado. '
                  'O botão Salvar só aparece após o teste bem-sucedido.',
        ),
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFF8F9FB),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Resumo',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF1A1A2E))),
              const SizedBox(height: 8),
              _linhaResumo('Provedor',
                  _provedores.firstWhere((e) => e.id == _provedor).nome),
              if (_provedor == 'vzaps')
                _linhaResumo('Instância', _instanceIdCtrl.text.trim()),
              if (_provedor != 'vzaps')
                _linhaResumo('URL', _apiUrlCtrl.text.trim()),
              if (_telefoneConectado.isNotEmpty)
                _linhaResumo('WhatsApp conectado', _telefoneConectado),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          height: 46,
          child: FilledButton.icon(
            onPressed: _testando ? null : _testarConexao,
            icon: _testando
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.wifi_tethering_rounded, size: 18),
            label: Text(_testando ? 'Testando...' : 'Testar conexão'),
            style: FilledButton.styleFrom(
              backgroundColor: PainelAdminTheme.roxo,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
        if (_testeMsg.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _testeOk
                  ? const Color(0xFFE8F5E9)
                  : const Color(0xFFFEF2F2),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _testeOk
                    ? const Color(0xFF86EFAC)
                    : const Color(0xFFFECACA),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  _testeOk
                      ? Icons.check_circle_rounded
                      : Icons.error_outline_rounded,
                  size: 18,
                  color: _testeOk
                      ? const Color(0xFF16A34A)
                      : const Color(0xFFDC2626),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(_testeMsg,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        color: _testeOk
                            ? const Color(0xFF166534)
                            : const Color(0xFF991B1B),
                      )),
                ),
              ],
            ),
          ),
        ],
        if (!_testeOk && _testeMsg.isEmpty) ...[
          const SizedBox(height: 12),
          Text(
            'Corrija as credenciais na etapa 2 se o teste falhar.',
            style: GoogleFonts.plusJakartaSans(
                fontSize: 12, color: const Color(0xFF94A3B8)),
          ),
        ],
      ],
    );
  }

  Widget _buildRodape() {
    return Row(
      children: [
        if (_etapa > 1)
          TextButton(
            onPressed: _testando || _salvando
                ? null
                : () => setState(() {
                      _etapa -= 1;
                      if (_etapa < 3) {
                        // voltar invalida teste para obrigar revalidação
                        if (_etapa == 2) {
                          _testeOk = false;
                          _testeMsg = '';
                        }
                      }
                    }),
            child: const Text('Voltar'),
          ),
        const Spacer(),
        TextButton(
          onPressed: _testando || _salvando
              ? null
              : () => Navigator.of(context, rootNavigator: true).pop(),
          child: const Text('Cancelar'),
        ),
        const SizedBox(width: 8),
        if (_etapa < 3)
          FilledButton(
            onPressed: () {
              if (_etapa == 1 && _provedor.isEmpty) {
                _avisar('Selecione um provedor para continuar.');
                return;
              }
              if (_etapa == 2 && !_validarCredenciais()) return;
              setState(() => _etapa += 1);
            },
            style: FilledButton.styleFrom(
              backgroundColor: PainelAdminTheme.roxo,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Continuar'),
          )
        else if (_testeOk)
          FilledButton.icon(
            onPressed: _salvando ? null : _salvar,
            icon: _salvando
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.save_rounded, size: 18),
            label: Text(_salvando ? 'Salvando...' : 'Salvar integração'),
            style: FilledButton.styleFrom(
              backgroundColor: PainelAdminTheme.roxo,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          )
        else
          OutlinedButton(
            onPressed: null,
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF94A3B8),
              side: const BorderSide(color: Color(0xFFE2E8F0)),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Salvar (teste pendente)'),
          ),
      ],
    );
  }

  Widget _infoBox(String titulo, String texto) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F6FF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE9D5FF)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded,
              size: 18, color: Color(0xFF6A1B9A)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titulo,
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF6A1B9A))),
                const SizedBox(height: 4),
                Text(texto,
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 11,
                        color: const Color(0xFF475569),
                        height: 1.35)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _linhaResumo(String k, String v) {
    if (v.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(k,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 12, color: const Color(0xFF94A3B8))),
          ),
          Expanded(
            child: Text(v,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF1A1A2E))),
          ),
        ],
      ),
    );
  }

  InputDecoration _decoCampo({String? hint}) {
    return InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: const Color(0xFFF8F9FB),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFFE8E4F0)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFF6A1B9A), width: 1.4),
      ),
    );
  }

  Widget _campo(String label, TextEditingController ctrl, {String? hint}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: const Color(0xFF6B7280))),
        const SizedBox(height: 6),
        TextField(
          controller: ctrl,
          onChanged: (_) => setState(() {
            _testeOk = false;
            _testeMsg = '';
          }),
          decoration: _decoCampo(hint: hint),
        ),
      ],
    );
  }

  Widget _campoSegredo(
    String label,
    TextEditingController ctrl, {
    required bool oculto,
    required VoidCallback onToggle,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: const Color(0xFF6B7280))),
        const SizedBox(height: 6),
        TextField(
          controller: ctrl,
          obscureText: oculto,
          onChanged: (_) => setState(() {
            _testeOk = false;
            _testeMsg = '';
          }),
          decoration: _decoCampo().copyWith(
            suffixIcon: IconButton(
              onPressed: onToggle,
              icon: Icon(
                oculto
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                size: 18,
                color: const Color(0xFF94A3B8),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
