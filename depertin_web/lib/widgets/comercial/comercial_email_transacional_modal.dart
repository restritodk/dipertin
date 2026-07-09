import 'dart:async';
import 'dart:math' as math;

import 'package:depertin_web/models/comercial_email_transacional.dart';
import 'package:depertin_web/services/comercial_email_transacional_service.dart';
import 'package:depertin_web/services/firebase_functions_config.dart';
import 'package:depertin_web/theme/painel_admin_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

/// Abre o módulo E-mail Transacional (3 abas).
Future<void> showComercialEmailTransacionalModal(
  BuildContext context, {
  required String lojaId,
  required void Function(bool ativo, bool configurado) onSalvo,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _ComercialEmailTransacionalModal(
      lojaId: lojaId,
      onSalvo: onSalvo,
    ),
  );
}

class _ComercialEmailTransacionalModal extends StatefulWidget {
  const _ComercialEmailTransacionalModal({
    required this.lojaId,
    required this.onSalvo,
  });

  final String lojaId;
  final void Function(bool ativo, bool configurado) onSalvo;

  @override
  State<_ComercialEmailTransacionalModal> createState() =>
      _ComercialEmailTransacionalModalState();
}

class _ComercialEmailTransacionalModalState
    extends State<_ComercialEmailTransacionalModal>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  final _svc = ComercialEmailTransacionalService.instance;

  bool _carregando = true;
  bool _salvando = false;
  bool _conexaoOk = false;
  bool _ocultarSenha = true;
  bool _ocultarApiKey = true;
  bool _previewMobile = false;
  bool _avancadoAberto = false;

  EmailTransacionalConfig _config = EmailTransacionalConfig();
  String _smtpSenha = '';
  String _apiKey = '';
  final _testeDestinoCtrl = TextEditingController();
  final _templateTesteDestinoCtrl = TextEditingController();

  String _slugSelecionado = 'cobranca';
  EmailTemplateModel? _templateAtual;
  late final ValueNotifier<int> _previewVersion;
  Timer? _debounceTimer;
  bool _carregandoTemplate = false;

  @override
  void initState() {
    super.initState();
    _previewVersion = ValueNotifier<int>(0);
    _tabs = TabController(length: 3, vsync: this);
    _iniciar();
  }

  Future<void> _iniciar() async {
    try {
      await _svc.inicializarTemplates(widget.lojaId);
      final cfg = await _svc.carregarConfig(widget.lojaId);
      final idLoja = await _svc.carregarIdentidadeLoja(widget.lojaId);
      if (!mounted) return;
      setState(() {
        _config = cfg;
        _config.identidadeVisual = EmailIdentidadeVisual(
          logoUrl: cfg.identidadeVisual.logoUrl.isNotEmpty
              ? cfg.identidadeVisual.logoUrl
              : idLoja.logoUrl,
          corPrincipal: cfg.identidadeVisual.corPrincipal,
          corSecundaria: cfg.identidadeVisual.corSecundaria,
          corBotao: cfg.identidadeVisual.corBotao,
          nomeLoja: cfg.identidadeVisual.nomeLoja.isNotEmpty
              ? cfg.identidadeVisual.nomeLoja
              : idLoja.nomeLoja,
          telefone: cfg.identidadeVisual.telefone.isNotEmpty
              ? cfg.identidadeVisual.telefone
              : idLoja.telefone,
          whatsapp: cfg.identidadeVisual.whatsapp.isNotEmpty
              ? cfg.identidadeVisual.whatsapp
              : idLoja.whatsapp,
          instagram: cfg.identidadeVisual.instagram,
          facebook: cfg.identidadeVisual.facebook,
          site: cfg.identidadeVisual.site.isNotEmpty
              ? cfg.identidadeVisual.site
              : idLoja.site,
          endereco: cfg.identidadeVisual.endereco.isNotEmpty
              ? cfg.identidadeVisual.endereco
              : idLoja.endereco,
        );
        if (_config.smtp.temSenhaSalva) _smtpSenha = kEmailSecretMask;
        if (_config.api.temApiKeySalva) _apiKey = kEmailSecretMask;
        _conexaoOk = _config.status.ultimoTesteOk;
        _carregando = false;
      });
      await _carregarTemplate(_slugSelecionado);
    } catch (e) {
      if (!mounted) return;
      setState(() => _carregando = false);
      _toast('Erro ao carregar: $e', erro: true);
    }
  }

  Future<void> _carregarTemplate(String slug) async {
    setState(() {
      _carregandoTemplate = true;
      _slugSelecionado = slug;
    });
    try {
      var tpl = await _svc.carregarTemplate(widget.lojaId, slug);
      tpl ??= EmailTemplateModel(
        slug: slug,
        assunto: slug == 'cobranca'
            ? 'Sua cobrança — {loja}'
            : 'Mensagem — {loja}',
        blocks: [
          EmailBlocoTemplate(
            tipo: 'titulo',
            conteudo: 'Olá, {cliente}',
          ),
          EmailBlocoTemplate(
            tipo: 'texto',
            conteudo: slug == 'cobranca'
                ? 'Sua parcela no valor de {valor} vence em {vencimento}.'
                : 'Mensagem automática da {loja}.',
          ),
          EmailBlocoTemplate(
            tipo: 'botao',
            textoBotao: 'Pagar Agora',
            destino: '{link}',
          ),
        ],
        identidadeVisual: _config.identidadeVisual,
      );
      if (tpl.identidadeVisual.nomeLoja.isEmpty) {
        tpl.identidadeVisual = _config.identidadeVisual;
      }
      if (!mounted) return;
      setState(() {
        _templateAtual = tpl;
        _carregandoTemplate = false;
      });
      // Já renderiza o preview com o template recém-carregado
      _atualizarPreview();
    } catch (_) {
      if (!mounted) return;
      setState(() => _carregandoTemplate = false);
    }
  }

  @override
  void dispose() {
    _tabs.dispose();
    _testeDestinoCtrl.dispose();
    _templateTesteDestinoCtrl.dispose();
    _debounceTimer?.cancel();
    _previewVersion.dispose();
    super.dispose();
  }

  /// Toast rápido (validações simples).
  void _toast(String msg, {bool erro = false, bool sucesso = false}) {
    if (!mounted) return;
    try {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: erro
              ? const Color(0xFFDC2626)
              : sucesso
                  ? const Color(0xFF16A34A)
                  : const Color(0xFF6A1B9A),
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    } catch (_) {
      // Ignora se o ScaffoldMessenger não estiver disponível
    }
  }

  /// Modal premium de resultado (teste de conexão / salvamento).
  /// Aparece sobre QUALQUER dialog via rootNavigator.
  Future<void> _showPremiumResult({
    required bool sucesso,
    required String titulo,
    required String mensagem,
    String? detalhe,
    String? botaoLabel,
    VoidCallback? onBotao,
    Widget? iconeCustom,
    List<Widget>? infoExtra,
  }) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      barrierColor: Colors.black54,
      builder: (ctx) => _PremiumResultDialog(
        sucesso: sucesso,
        titulo: titulo,
        mensagem: mensagem,
        detalhe: detalhe,
        botaoLabel: botaoLabel,
        onBotao: onBotao,
        iconeCustom: iconeCustom,
        infoExtra: infoExtra,
      ),
    );
  }

  Future<void> _salvarConfig() async {
    setState(() => _salvando = true);
    try {
      await _svc.salvarConfig(
        widget.lojaId,
        _config,
        smtpSenha: _smtpSenha,
        apiKey: _apiKey,
      );
      if (!mounted) return;
      setState(() => _salvando = false);
      widget.onSalvo(_config.ativo, _config.estaConfigurado);
      await _showPremiumResult(
        sucesso: true,
        titulo: 'Configuração salva!',
        mensagem: _config.estaConfigurado
            ? 'O e-mail transacional está configurado e pronto para uso.'
            : 'Configurações salvas. Complete os dados obrigatórios para ativar.',
        infoExtra: [
          _infoChip('Status', _config.estaConfigurado ? 'Configurado' : 'Incompleto'),
          _infoChip('Modo', _config.modoIntegracao.toUpperCase()),
          _infoChip('Ativo', _config.ativo ? 'Sim' : 'Não'),
        ],
        botaoLabel: 'OK',
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _salvando = false);
      final msg = e is CallableHttpException
          ? mensagemCallableHttpException(e)
          : e.toString();
      await _showPremiumResult(
        sucesso: false,
        titulo: 'Erro ao salvar',
        mensagem: msg,
        detalhe: 'Tente novamente ou verifique sua conexão.',
      );
    }
  }

  Future<void> _testarConexao() async {
    if (!mounted) return;
    final loadingCtx = ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 30),
        content: Row(
          children: [
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              _config.modoIntegracao == 'api'
                  ? 'Testando API...'
                  : 'Testando SMTP...',
            ),
          ],
        ),
        backgroundColor: const Color(0xFF6A1B9A),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );

    try {
      final Map<String, dynamic> r;
      if (_config.modoIntegracao == 'api') {
        r = await _svc.testarApi(
          widget.lojaId,
          _config.api,
          apiKey: _apiKey,
        );
      } else {
        r = await _svc.testarSmtp(
          widget.lojaId,
          _config.smtp,
          senha: _smtpSenha,
        );
      }
      loadingCtx.close();
      if (!mounted) return;
      final ok = r['ok'] == true;
      final msg = r['mensagem']?.toString() ??
          (ok ? 'Conexão realizada com sucesso.' : 'Falha na conexão.');
      setState(() {
        _conexaoOk = ok;
        _config.status.ultimoTesteOk = ok;
        _config.status.ultimoTesteMsg = msg;
        _config.status.ultimoTesteEm = DateTime.now();
      });
      await _showPremiumResult(
        sucesso: ok,
        titulo: ok ? 'Conexão realizada!' : 'Falha na conexão',
        mensagem: msg,
        detalhe: ok ? 'O serviço de e-mail está configurado e respondendo.' : 'Verifique os dados informados e tente novamente.',
        infoExtra: ok
            ? [
                _infoChip('Modo', _config.modoIntegracao.toUpperCase()),
                _infoChip('Provedor',
                    _config.modoIntegracao == 'api' ? _config.api.provider.toUpperCase() : _config.smtp.host),
              ]
            : null,
        botaoLabel: ok ? 'Continuar' : 'Fechar',
      );
    } catch (e) {
      loadingCtx.close();
      if (!mounted) return;
      final msg = e is CallableHttpException
          ? mensagemCallableHttpException(e)
          : e.toString();
      await _showPremiumResult(
        sucesso: false,
        titulo: 'Erro no teste',
        mensagem: msg,
        detalhe: 'O servidor não respondeu conforme esperado.',
      );
    }
  }

  Widget _infoChip(String label, String valor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F4F8),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Text(
            '$label: ',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              color: const Color(0xFF64748B),
            ),
          ),
          Expanded(
            child: Text(
              valor,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF1A1A2E),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _enviarEmailTeste() async {
    final dest = _testeDestinoCtrl.text.trim();
    if (dest.isEmpty) {
      _toast('Informe o e-mail destino.', erro: true);
      return;
    }
    if (!_conexaoOk) {
      _toast('Teste a conexão antes de enviar.', erro: true);
      return;
    }

    if (!mounted) return;

    // Abre loading animado (não await para não bloquear)
    final loadingFuture = showDialog<void>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      barrierColor: Colors.black54,
      builder: (_) => _LoadingEnvioOverlay(
        mensagem: 'Enviando e-mail de teste para\n$dest',
      ),
    );

    try {
      // Salva a config primeiro para a Cloud Function encontrar os dados
      await _svc.salvarConfig(
        widget.lojaId,
        _config,
        smtpSenha: _smtpSenha,
        apiKey: _apiKey,
      );
      if (!mounted) return;

      final r = await _svc.enviarTeste(widget.lojaId, dest);
      // Fecha loading
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
      await loadingFuture;
      if (!mounted) return;

      final msg = r['mensagem']?.toString() ?? 'E-mail de teste enviado.';
      final protocolo = r['protocolo']?.toString() ?? '';
      final tempoMs = r['tempoMs'];

      await _showPremiumResult(
        sucesso: true,
        titulo: 'E-mail enviado!',
        mensagem: msg,
        detalhe: 'Verifique a caixa de entrada de $dest.',
        infoExtra: [
          _infoChip('Destino', dest),
          if (protocolo.isNotEmpty) _infoChip('Protocolo', protocolo),
          if (tempoMs != null) _infoChip('Tempo', '${tempoMs}ms'),
        ],
        botaoLabel: 'OK',
      );
    } catch (e) {
      // Fecha loading em caso de erro
      try {
        if (mounted) Navigator.of(context, rootNavigator: true).pop();
      } catch (_) {}
      await loadingFuture;
      if (!mounted) return;

      final msg = e is CallableHttpException
          ? mensagemCallableHttpException(e)
          : e.toString();
      await _showPremiumResult(
        sucesso: false,
        titulo: 'Falha no envio',
        mensagem: msg,
        detalhe: 'Verifique a configuração e tente novamente.',
        infoExtra: [_infoChip('Destino', dest)],
      );
    }
  }

  Future<void> _salvarTemplate() async {
    final tpl = _templateAtual;
    if (tpl == null) return;

    if (!mounted) return;

    final loadingFuture = showDialog<void>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      barrierColor: Colors.black54,
      builder: (_) => _LoadingEnvioOverlay(
        titulo: 'Salvando...',
        icone: Icons.save_rounded,
        mensagem: 'Salvando template "${_slugSelecionado}"…',
      ),
    );

    try {
      await _svc.salvarTemplate(widget.lojaId, tpl);
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
      await loadingFuture;
      if (!mounted) return;
      final nomeFormatado = _formatarSlug(_slugSelecionado);
      await _showPremiumResult(
        sucesso: true,
        titulo: 'Template salvo!',
        mensagem: 'O template "$nomeFormatado" foi salvo com sucesso.',
        botaoLabel: 'OK',
      );
    } catch (e) {
      try {
        if (mounted) Navigator.of(context, rootNavigator: true).pop();
      } catch (_) {}
      await loadingFuture;
      if (!mounted) return;
      final msg = e is CallableHttpException
          ? mensagemCallableHttpException(e)
          : e.toString();
      await _showPremiumResult(
        sucesso: false,
        titulo: 'Erro ao salvar template',
        mensagem: msg,
      );
    }
  }

  /// Formata slug como "pagamento_recebido" → "Pagamento Recebido".
  String _formatarSlug(String slug) {
    return slug
        .replaceAll('_', ' ')
        .split(' ')
        .map((w) => w.isEmpty ? '' : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }

  /// Notifica o preview para se atualizar com os dados mais recentes do template.
  void _atualizarPreview() {
    _previewVersion.value = _previewVersion.value + 1;
  }

  /// Versão com debounce de 150ms para campos de texto grandes.
  void _atualizarPreviewDebounced() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 150), () {
      if (mounted) _previewVersion.value = _previewVersion.value + 1;
    });
  }

  Future<void> _enviarTemplateTeste() async {
    final tpl = _templateAtual;
    if (tpl == null) return;
    final dest = _templateTesteDestinoCtrl.text.trim();
    if (dest.isEmpty) {
      _toast('Informe o e-mail destino.', erro: true);
      return;
    }

    if (!mounted) return;

    // Abre loading animado
    final loadingFuture = showDialog<void>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      barrierColor: Colors.black54,
      builder: (_) => _LoadingEnvioOverlay(
        mensagem: 'Enviando template "${_slugSelecionado}" para\n$dest',
      ),
    );

    try {
      // Salva a config primeiro para a Cloud Function encontrar os dados
      await _svc.salvarConfig(
        widget.lojaId,
        _config,
        smtpSenha: _smtpSenha,
        apiKey: _apiKey,
      );
      if (!mounted) return;

      final r = await _svc.enviarTemplateTeste(
        lojaId: widget.lojaId,
        destino: dest,
        template: tpl,
      );
      // Fecha loading
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
      await loadingFuture;
      if (!mounted) return;

      final msg = r['mensagem']?.toString() ?? 'Template enviado.';
      final protocolo = r['protocolo']?.toString() ?? '';
      final tempoMs = r['tempoMs'];

      await _showPremiumResult(
        sucesso: true,
        titulo: 'Template enviado!',
        mensagem: msg,
        detalhe: 'E-mail com o template "${_slugSelecionado}" enviado para $dest.',
        infoExtra: [
          _infoChip('Destino', dest),
          if (protocolo.isNotEmpty) _infoChip('Protocolo', protocolo),
          if (tempoMs != null) _infoChip('Tempo', '${tempoMs}ms'),
        ],
        botaoLabel: 'OK',
      );
    } catch (e) {
      // Fecha loading em caso de erro
      try {
        if (mounted) Navigator.of(context, rootNavigator: true).pop();
      } catch (_) {}
      await loadingFuture;
      if (!mounted) return;

      final msg = e is CallableHttpException
          ? mensagemCallableHttpException(e)
          : e.toString();
      await _showPremiumResult(
        sucesso: false,
        titulo: 'Falha no envio',
        mensagem: msg,
        detalhe: 'Verifique o destino e a configuração.',
        infoExtra: [_infoChip('Destino', dest)],
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final dialogW = w > 1200 ? 1100.0 : w * 0.92;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: SizedBox(
        width: dialogW,
        height: MediaQuery.sizeOf(context).height * 0.9,
        child: Column(
          children: [
            _buildHeader(),
            Material(
              color: const Color(0xFFF5F4F8),
              child: TabBar(
                controller: _tabs,
                labelColor: PainelAdminTheme.roxo,
                unselectedLabelColor: PainelAdminTheme.textoSecundario,
                indicatorColor: PainelAdminTheme.roxo,
                tabs: const [
                  Tab(text: 'Configuração'),
                  Tab(text: 'Templates'),
                  Tab(text: 'Histórico'),
                ],
              ),
            ),
            Expanded(
              child: _carregando
                  ? const Center(child: CircularProgressIndicator())
                  : TabBarView(
                      controller: _tabs,
                      children: [
                        _buildTabConfiguracao(),
                        _buildTabTemplates(),
                        _buildTabHistorico(),
                      ],
                    ),
            ),
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 12, 12),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: PainelAdminTheme.roxo.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.email_rounded, color: PainelAdminTheme.roxo),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'E-mail Transacional',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF1A1A2E),
                  ),
                ),
                Text(
                  'SMTP, API, templates e histórico por loja',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    color: PainelAdminTheme.textoSecundario,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFFEEEAF6))),
        color: Colors.white,
      ),
      child: Row(
        children: [
          Switch(
            value: _config.ativo,
            activeThumbColor: PainelAdminTheme.roxo,
            onChanged: (v) => setState(() => _config.ativo = v),
          ),
          Text('Ativo',
              style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600)),
          const Spacer(),
          TextButton(
            onPressed: _salvando ? null : () => Navigator.pop(context),
            child: const Text('Fechar'),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: _salvando ? null : _salvarConfig,
            style: FilledButton.styleFrom(
              backgroundColor: PainelAdminTheme.roxo,
              minimumSize: const Size(120, 44),
            ),
            child: _salvando
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Text('Salvar'),
          ),
        ],
      ),
    );
  }

  Widget _buildTabConfiguracao() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildStatusCard(),
          const SizedBox(height: 20),
          Text('Tipo de integração',
              style: GoogleFonts.plusJakartaSans(
                  fontWeight: FontWeight.w600, fontSize: 14)),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'smtp', label: Text('SMTP')),
              ButtonSegment(value: 'api', label: Text('API')),
            ],
            selected: {_config.modoIntegracao},
            onSelectionChanged: (s) =>
                setState(() => _config.modoIntegracao = s.first),
            style: ButtonStyle(
              visualDensity: VisualDensity.compact,
            ),
          ),
          const SizedBox(height: 20),
          if (_config.modoIntegracao == 'smtp') _buildFormSmtp() else _buildFormApi(),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _testarConexao,
            icon: const Icon(Icons.link_rounded, size: 18),
            label: Text(_config.modoIntegracao == 'api'
                ? 'Testar API'
                : 'Testar conexão'),
          ),
          if (_conexaoOk) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _testeDestinoCtrl,
                    decoration: _dec('E-mail destino (teste)'),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton(
                  onPressed: _enviarEmailTeste,
                  style: FilledButton.styleFrom(
                      backgroundColor: PainelAdminTheme.laranja),
                  child: const Text('Enviar'),
                ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          ExpansionTile(
            initiallyExpanded: _avancadoAberto,
            onExpansionChanged: (v) => setState(() => _avancadoAberto = v),
            title: Text('Configurações avançadas',
                style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600)),
            children: [_buildAvancado()],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusCard() {
    final cfg = _config.estaConfigurado;
    final fmt = DateFormat('dd/MM/yyyy HH:mm', 'pt_BR');
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFEEEAF6)),
      ),
      child: Wrap(
        spacing: 24,
        runSpacing: 12,
        children: [
          _statusItem(
            'Status',
            cfg ? 'Configurado' : 'Não configurado',
            cfg ? const Color(0xFF16A34A) : const Color(0xFF94A3B8),
          ),
          _statusItem(
            'Último teste',
            _config.status.ultimoTesteEm != null
                ? fmt.format(_config.status.ultimoTesteEm!)
                : '—',
            _config.status.ultimoTesteOk
                ? const Color(0xFF16A34A)
                : PainelAdminTheme.textoSecundario,
          ),
          _statusItem(
            'Último envio',
            _config.status.ultimoEnvioEm != null
                ? fmt.format(_config.status.ultimoEnvioEm!)
                : '—',
            PainelAdminTheme.roxo,
          ),
          _statusItem(
            'Enviados hoje',
            '${_config.status.enviadosHoje}',
            PainelAdminTheme.laranja,
          ),
        ],
      ),
    );
  }

  Widget _statusItem(String label, String valor, Color cor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: GoogleFonts.plusJakartaSans(
                fontSize: 12, color: PainelAdminTheme.textoSecundario)),
        const SizedBox(height: 4),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.circle, size: 8, color: cor),
            const SizedBox(width: 6),
            Text(valor,
                style: GoogleFonts.plusJakartaSans(
                    fontWeight: FontWeight.w600, fontSize: 14)),
          ],
        ),
      ],
    );
  }

  Widget _buildFormSmtp() {
    final s = _config.smtp;
    return Column(
      children: [
        _field('Nome da integração', _config.nome,
            (v) => setState(() => _config.nome = v)),
        _field('Servidor SMTP', s.host, (v) => setState(() => s.host = v)),
        Row(
          children: [
            Expanded(
              child: _field('Porta', s.port.toString(),
                  (v) => setState(() => s.port = int.tryParse(v) ?? 587),
                  keyboard: TextInputType.number),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButtonFormField<String>(
                value: s.encryption,
                decoration: _dec('Criptografia'),
                items: const [
                  DropdownMenuItem(value: 'tls', child: Text('TLS')),
                  DropdownMenuItem(value: 'ssl', child: Text('SSL')),
                  DropdownMenuItem(value: 'none', child: Text('Nenhuma')),
                ],
                onChanged: (v) =>
                    setState(() => s.encryption = v ?? 'tls'),
              ),
            ),
          ],
        ),
        _field('Usuário SMTP', s.user, (v) => setState(() => s.user = v)),
        _fieldSecret(
          'Senha SMTP',
          _smtpSenha,
          oculto: _ocultarSenha,
          onChanged: (v) => setState(() => _smtpSenha = v),
          onToggle: () => setState(() => _ocultarSenha = !_ocultarSenha),
        ),
        _field('E-mail remetente', s.fromEmail,
            (v) => setState(() => s.fromEmail = v)),
        _field('Nome exibido', s.fromName, (v) => setState(() => s.fromName = v)),
        _field('Responder para (opcional)', s.replyTo,
            (v) => setState(() => s.replyTo = v)),
      ],
    );
  }

  Widget _buildFormApi() {
    final a = _config.api;
    const providers = {
      'sendgrid': 'SendGrid',
      'amazon_ses': 'Amazon SES',
      'mailgun': 'Mailgun',
      'resend': 'Resend',
      'postmark': 'Postmark',
      'personalizado': 'Personalizado',
    };
    return Column(
      children: [
        _field('Nome da integração', _config.nome,
            (v) => setState(() => _config.nome = v)),
        DropdownButtonFormField<String>(
          value: providers.containsKey(a.provider) ? a.provider : 'sendgrid',
          decoration: _dec('Provedor'),
          items: providers.entries
              .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
              .toList(),
          onChanged: (v) => setState(() {
            a.provider = v ?? 'sendgrid';
            if (v == 'sendgrid') a.baseUrl = 'https://api.sendgrid.com';
            if (v == 'mailgun') a.baseUrl = 'https://api.mailgun.net';
            if (v == 'resend') a.baseUrl = 'https://api.resend.com';
            if (v == 'postmark') a.baseUrl = 'https://api.postmarkapp.com';
          }),
        ),
        _field('Base URL', a.baseUrl, (v) => setState(() => a.baseUrl = v)),
        _fieldSecret(
          'API Key',
          _apiKey,
          oculto: _ocultarApiKey,
          onChanged: (v) => setState(() => _apiKey = v),
          onToggle: () => setState(() => _ocultarApiKey = !_ocultarApiKey),
        ),
        _field('E-mail remetente', a.fromEmail,
            (v) => setState(() => a.fromEmail = v)),
        _field('Nome exibido', a.fromName, (v) => setState(() => a.fromName = v)),
        _field('Responder para (opcional)', a.replyTo,
            (v) => setState(() => a.replyTo = v)),
      ],
    );
  }

  Widget _buildAvancado() {
    final av = _config.avancado;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                  child: _field('Limite envio/min', av.limitePorMinuto.toString(),
                      (v) => av.limitePorMinuto = int.tryParse(v) ?? 30,
                      keyboard: TextInputType.number)),
              const SizedBox(width: 12),
              Expanded(
                  child: _field('Timeout (s)', av.timeoutSegundos.toString(),
                      (v) => av.timeoutSegundos = int.tryParse(v) ?? 30,
                      keyboard: TextInputType.number)),
            ],
          ),
          Row(
            children: [
              Expanded(
                  child: _field('Tentativas', av.tentativas.toString(),
                      (v) => av.tentativas = int.tryParse(v) ?? 3,
                      keyboard: TextInputType.number)),
              const SizedBox(width: 12),
              Expanded(
                  child: _field(
                      'Delay entre tentativas (s)',
                      av.delayEntreTentativas.toString(),
                      (v) => av.delayEntreTentativas = int.tryParse(v) ?? 5,
                      keyboard: TextInputType.number)),
            ],
          ),
          SwitchListTile(
            title: const Text('Ativar log'),
            value: av.ativarLog,
            activeThumbColor: PainelAdminTheme.roxo,
            onChanged: (v) => setState(() => av.ativarLog = v),
          ),
          SwitchListTile(
            title: const Text('Ativar rastreamento'),
            value: av.ativarRastreamento,
            activeThumbColor: PainelAdminTheme.roxo,
            onChanged: (v) => setState(() => av.ativarRastreamento = v),
          ),
          SwitchListTile(
            title: const Text('Open tracking'),
            value: av.openTracking,
            activeThumbColor: PainelAdminTheme.roxo,
            onChanged: (v) => setState(() => av.openTracking = v),
          ),
          SwitchListTile(
            title: const Text('Click tracking'),
            value: av.clickTracking,
            activeThumbColor: PainelAdminTheme.roxo,
            onChanged: (v) => setState(() => av.clickTracking = v),
          ),
        ],
      ),
    );
  }

  Widget _buildTabTemplates() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 220,
          child: ColoredBox(
            color: Colors.white,
            child: ListView(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text('Templates',
                      style: GoogleFonts.plusJakartaSans(
                          fontWeight: FontWeight.w700)),
                ),
                ...EmailTemplateCatalogo.items.map((item) {
                  final sel = item.slug == _slugSelecionado;
                  return ListTile(
                    dense: true,
                    selected: sel,
                    selectedTileColor:
                        PainelAdminTheme.roxo.withValues(alpha: 0.08),
                    title: Text(item.rotulo,
                        style: GoogleFonts.plusJakartaSans(fontSize: 13)),
                    onTap: () => _carregarTemplate(item.slug),
                  );
                }),
                const Divider(),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text('Automação',
                      style: GoogleFonts.plusJakartaSans(
                          fontWeight: FontWeight.w700, fontSize: 13)),
                ),
                ...kEmailAutomacaoOpcoes.map((op) {
                  return CheckboxListTile(
                    dense: true,
                    title: Text(op.rotulo,
                        style: GoogleFonts.plusJakartaSans(fontSize: 12)),
                    value: _config.automacao[op.chave] == true,
                    activeColor: PainelAdminTheme.roxo,
                    onChanged: (v) => setState(
                        () => _config.automacao[op.chave] = v == true),
                  );
                }),
              ],
            ),
          ),
        ),
        Expanded(
          child: _carregandoTemplate || _templateAtual == null
              ? const Center(child: CircularProgressIndicator())
              : _buildEditorTemplate(),
        ),
      ],
    );
  }

  Widget _buildEditorTemplate() {
    final tpl = _templateAtual!;
    final id = tpl.identidadeVisual;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 3,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Identidade visual',
                    style: GoogleFonts.plusJakartaSans(
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                _field('Nome da loja', id.nomeLoja, (v) {
                  id.nomeLoja = v;
                  _atualizarPreview();
                }, key: ValueKey('${_slugSelecionado}_nomeLoja')),
                Row(
                  children: [
                    Expanded(
                        child: _field('Cor principal', id.corPrincipal, (v) {
                      id.corPrincipal = v;
                      _atualizarPreview();
                    }, key: ValueKey('${_slugSelecionado}_corP'))),
                    const SizedBox(width: 8),
                    Expanded(
                        child: _field('Cor secundária', id.corSecundaria, (v) {
                      id.corSecundaria = v;
                      _atualizarPreview();
                    }, key: ValueKey('${_slugSelecionado}_corS'))),
                    const SizedBox(width: 8),
                    Expanded(
                        child: _field('Cor botão', id.corBotao, (v) {
                      id.corBotao = v;
                      _atualizarPreview();
                    }, key: ValueKey('${_slugSelecionado}_corB'))),
                  ],
                ),
                _fieldTelefone('Telefone', id.telefone, (v) {
                  id.telefone = v;
                  _atualizarPreview();
                }, ValueKey('${_slugSelecionado}_tel')),
                _fieldTelefone('WhatsApp', id.whatsapp, (v) {
                  id.whatsapp = v;
                  _atualizarPreview();
                }, ValueKey('${_slugSelecionado}_wpp')),
                _field('Site', id.site, (v) {
                  id.site = v;
                  _atualizarPreview();
                }, key: ValueKey('${_slugSelecionado}_site')),
                const SizedBox(height: 12),
                _field('Assunto', tpl.assunto, (v) {
                  tpl.assunto = v;
                  _atualizarPreview();
                }, key: ValueKey('${_slugSelecionado}_assunto')),
                Row(
                  children: [
                    Text('Corpo (blocos)',
                        style: GoogleFonts.plusJakartaSans(
                            fontWeight: FontWeight.w600)),
                    const Spacer(),
                    PopupMenuButton<String>(
                      onSelected: (t) {
                        setState(() {
                          tpl.blocks.add(EmailBlocoTemplate(
                            tipo: t,
                            conteudo: t == 'titulo' ? 'Título' : '',
                            textoBotao: t == 'botao' ? 'Pagar Agora' : null,
                            destino: t == 'botao' ? '{link}' : null,
                          ));
                        });
                        _atualizarPreview();
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'titulo', child: Text('Título')),
                        PopupMenuItem(value: 'texto', child: Text('Texto')),
                        PopupMenuItem(value: 'imagem', child: Text('Imagem')),
                        PopupMenuItem(value: 'botao', child: Text('Botão')),
                        PopupMenuItem(
                            value: 'divisor', child: Text('Linha divisória')),
                      ],
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.add, size: 16),
                            const SizedBox(width: 4),
                            Text('Bloco',
                                style: GoogleFonts.plusJakartaSans(fontSize: 13)),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    PopupMenuButton<String>(
                      onSelected: (v) {
                        if (tpl.blocks.isEmpty) {
                          tpl.blocks.add(EmailBlocoTemplate(
                              tipo: 'texto', conteudo: v));
                        } else {
                          final b = tpl.blocks.last;
                          b.conteudo = '${b.conteudo}$v';
                        }
                        _atualizarPreview();
                      },
                      itemBuilder: (_) => kEmailVariaveis
                          .map((v) => PopupMenuItem(value: v, child: Text(v)))
                          .toList(),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.data_object_outlined, size: 16),
                            const SizedBox(width: 4),
                            Text('Variável',
                                style: GoogleFonts.plusJakartaSans(fontSize: 13)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ...tpl.blocks.asMap().entries.map((e) {
                  final i = e.key;
                  final b = e.value;
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Chip(
                                  label: Text(b.tipo,
                                      style: const TextStyle(fontSize: 11))),
                              const Spacer(),
                              IconButton(
                                icon: const Icon(Icons.delete_outline, size: 18),
                                onPressed: () {
                                  setState(() => tpl.blocks.removeAt(i));
                                  _atualizarPreview();
                                },
                              ),
                            ],
                          ),
                          if (b.tipo == 'botao') ...[
                            _field('Texto botão', b.textoBotao ?? '', (v) {
                              b.textoBotao = v;
                              _atualizarPreview();
                            }),
                            _field('Destino', b.destino ?? '', (v) {
                              b.destino = v;
                              _atualizarPreview();
                            }),
                          ] else if (b.tipo == 'imagem')
                            _field('URL imagem', b.url ?? b.conteudo, (v) {
                              b.url = v;
                              b.conteudo = v;
                              _atualizarPreview();
                            })
                          else
                            TextFormField(
                              key: ValueKey('blk-$i-${b.tipo}-${_slugSelecionado}'),
                              maxLines: b.tipo == 'texto' ? 4 : 1,
                              initialValue: b.conteudo,
                              onChanged: (v) {
                                b.conteudo = v;
                                if (b.tipo == 'texto') {
                                  _atualizarPreviewDebounced();
                                } else {
                                  _atualizarPreview();
                                }
                              },
                              onEditingComplete: () {
                                _atualizarPreview();
                              },
                              decoration: _dec('Conteúdo'),
                            ),
                        ],
                      ),
                    ),
                  );
                }),
                Row(
                  children: [
                    FilledButton(
                      onPressed: _salvarTemplate,
                      style: FilledButton.styleFrom(
                          backgroundColor: PainelAdminTheme.roxo),
                      child: const Text('Salvar template'),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _templateTesteDestinoCtrl,
                        decoration: _dec('Enviar teste para'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _enviarTemplateTeste,
                      style: FilledButton.styleFrom(
                          backgroundColor: PainelAdminTheme.laranja),
                      child: const Text('Enviar'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        Expanded(
          flex: 2,
          child: Container(
            color: const Color(0xFFE8E6EF),
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('Preview',
                        style: GoogleFonts.plusJakartaSans(
                            fontWeight: FontWeight.w700)),
                    const Spacer(),
                    SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(value: false, label: Text('Desktop')),
                        ButtonSegment(value: true, label: Text('Mobile')),
                      ],
                      selected: {_previewMobile},
                      onSelectionChanged: (s) {
                        setState(() => _previewMobile = s.first);
                        _atualizarPreview();
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: Center(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: _previewMobile ? 320 : double.infinity,
                      constraints: const BoxConstraints(maxWidth: 560),
                      child: ValueListenableBuilder<int>(
                        valueListenable: _previewVersion,
                        builder: (ctx, _, __) {
                          final previewTpl = _templateAtual;
                          if (previewTpl == null) {
                            return const SizedBox.shrink();
                          }
                          return _EmailPreviewPanel(
                            template: previewTpl,
                            mobile: _previewMobile,
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTabHistorico() {
    return StreamBuilder<List<EmailHistoricoItem>>(
      stream: _svc.streamHistorico(widget.lojaId),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final items = snap.data ?? [];
        if (items.isEmpty) {
          return Center(
            child: Text('Nenhum envio registrado ainda.',
                style: GoogleFonts.plusJakartaSans(
                    color: PainelAdminTheme.textoSecundario)),
          );
        }
        final fmt = DateFormat('dd/MM/yy HH:mm', 'pt_BR');
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowColor:
                WidgetStateProperty.all(const Color(0xFFF5F4F8)),
            columns: const [
              DataColumn(label: Text('Status')),
              DataColumn(label: Text('Data')),
              DataColumn(label: Text('Cliente')),
              DataColumn(label: Text('Assunto')),
              DataColumn(label: Text('Tipo')),
              DataColumn(label: Text('E-mail')),
              DataColumn(label: Text('Provedor')),
              DataColumn(label: Text('Tempo')),
              DataColumn(label: Text('Ações')),
            ],
            rows: items.map((item) {
              return DataRow(cells: [
                DataCell(_badgeStatus(item.status)),
                DataCell(Text(item.criadoEm != null
                    ? fmt.format(item.criadoEm!)
                    : '—')),
                DataCell(Text(item.cliente,
                    overflow: TextOverflow.ellipsis)),
                DataCell(Text(item.assunto,
                    overflow: TextOverflow.ellipsis)),
                DataCell(Text(item.tipo)),
                DataCell(Text(item.email)),
                DataCell(Text(item.provedor)),
                DataCell(Text('${item.tempoMs} ms')),
                DataCell(
                  TextButton(
                    onPressed: () => _mostrarDetalheHistorico(item),
                    child: const Text('Detalhes'),
                  ),
                ),
              ]);
            }).toList(),
          ),
        );
      },
    );
  }

  Widget _badgeStatus(String status) {
    Color cor;
    switch (status) {
      case 'enviado':
      case 'entregue':
        cor = const Color(0xFF16A34A);
        break;
      case 'aberto':
      case 'clicado':
        cor = PainelAdminTheme.laranja;
        break;
      case 'erro':
        cor = const Color(0xFFDC2626);
        break;
      default:
        cor = PainelAdminTheme.textoSecundario;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(status,
          style: GoogleFonts.plusJakartaSans(
              fontSize: 11, fontWeight: FontWeight.w600, color: cor)),
    );
  }

  void _mostrarDetalheHistorico(EmailHistoricoItem item) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Detalhes do envio'),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('ID: ${item.messageId.isNotEmpty ? item.messageId : item.id}'),
                Text('Log: ${item.logTecnico}'),
                Text('Resposta: ${item.respostaTecnica}'),
                if (item.corpoHtml != null) ...[
                  const SizedBox(height: 12),
                  const Text('Mensagem:', style: TextStyle(fontWeight: FontWeight.bold)),
                  Text(item.corpoHtml!),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Fechar')),
        ],
      ),
    );
  }

  InputDecoration _dec(String label) => InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.plusJakartaSans(fontSize: 13),
        filled: true,
        fillColor: Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFEEEAF6)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFEEEAF6)),
        ),
      );

  Widget _field(
    String label,
    String value,
    ValueChanged<String> onChanged, {
    TextInputType keyboard = TextInputType.text,
    Key? key,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        key: key,
        initialValue: value,
        keyboardType: keyboard,
        onChanged: onChanged,
        decoration: _dec(label),
      ),
    );
  }

  Widget _fieldTelefone(
    String label,
    String value,
    ValueChanged<String> onChanged,
    Key key,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        key: key,
        initialValue: value,
        keyboardType: TextInputType.phone,
        inputFormatters: [_TelefoneInputFormatter()],
        onChanged: onChanged,
        decoration: _dec(label),
      ),
    );
  }

  Widget _fieldSecret(
    String label,
    String value, {
    required bool oculto,
    required ValueChanged<String> onChanged,
    required VoidCallback onToggle,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        initialValue: value,
        obscureText: oculto,
        onChanged: onChanged,
        decoration: _dec(label).copyWith(
          suffixIcon: IconButton(
            icon: Icon(oculto ? Icons.visibility_off : Icons.visibility),
            onPressed: onToggle,
          ),
        ),
      ),
    );
  }
}

/// Máscara de telefone BR: (99) 99999-9999
class _TelefoneInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return TextEditingValue.empty;

    // Máximo 11 dígitos (celular BR)
    final trimmed = digits.length > 11 ? digits.substring(0, 11) : digits;

    if (trimmed.length == 1) {
      return TextEditingValue(
        text: '($trimmed',
        selection: const TextSelection.collapsed(offset: 3),
      );
    }

    // Monta formatado
    final buf = StringBuffer();
    buf.write('(${trimmed.substring(0, 2)}) ');
    if (trimmed.length <= 7) {
      buf.write(trimmed.substring(2));
    } else {
      buf.write('${trimmed.substring(2, 7)}-${trimmed.substring(7)}');
    }
    final formatted = buf.toString();

    // Calcula quantos dígitos estavam antes do cursor no texto digitado
    final prefix = newValue.text.substring(0, newValue.selection.baseOffset);
    final digitsBeforeCursor = prefix.replaceAll(RegExp(r'\D'), '').length;

    // Encontra a posição equivalente no texto formatado
    int cursorPos = formatted.length;
    int seen = 0;
    for (int i = 0; i < formatted.length; i++) {
      if (RegExp(r'\d').hasMatch(formatted[i])) {
        seen++;
        if (seen > digitsBeforeCursor) {
          cursorPos = i;
          break;
        }
      }
    }

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: cursorPos),
    );
  }
}

/// Overlay animado de envio/salvamento.
/// Aparece com fade+scale, ícone pulsando e barra de progresso.
class _LoadingEnvioOverlay extends StatefulWidget {
  const _LoadingEnvioOverlay({
    required this.mensagem,
    this.titulo = 'Enviando...',
    this.icone = Icons.send_rounded,
  });

  final String mensagem;
  final String titulo;
  final IconData icone;

  @override
  State<_LoadingEnvioOverlay> createState() => _LoadingEnvioOverlayState();
}

class _LoadingEnvioOverlayState extends State<_LoadingEnvioOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animCtrl;
  late final Animation<double> _fadeAnim;
  late final Animation<double> _scaleAnim;
  late final Animation<double> _pulseAnim;
  late final Animation<double> _progressAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    );
    _fadeAnim = CurvedAnimation(
      parent: _animCtrl,
      curve: const Interval(0.0, 0.35, curve: Curves.easeOut),
    );
    _scaleAnim = CurvedAnimation(
      parent: _animCtrl,
      curve: const Interval(0.0, 0.4, curve: ElasticOutCurve(0.6)),
    );
    _pulseAnim = Tween<double>(begin: 1.0, end: 0.85).animate(
      CurvedAnimation(
        parent: _animCtrl,
        curve: const Interval(0.3, 1.0, curve: Curves.easeInOutSine),
      ),
    );
    _progressAnim = Tween<double>(begin: 0.0, end: 0.95).animate(
      CurvedAnimation(
        parent: _animCtrl,
        curve: const Interval(0.2, 1.0, curve: Curves.easeInOut),
      ),
    );
    _animCtrl.forward();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: FadeTransition(
        opacity: _fadeAnim,
        child: ScaleTransition(
          scale: _scaleAnim,
          child: AlertDialog(
            insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            contentPadding: EdgeInsets.zero,
            clipBehavior: Clip.antiAlias,
            content: SizedBox(
              width: 380,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // --- Header gradiente roxo ---
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(24, 36, 24, 24),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Color(0xFF6A1B9A),
                          Color(0xFF8E24AA),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: Column(
                      children: [
                        // Ícone de envio animado
                        AnimatedBuilder(
                          animation: _pulseAnim,
                          builder: (context, child) {
                            return Transform.scale(
                              scale: _pulseAnim.value,
                              child: Container(
                                width: 80,
                                height: 80,
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.2),
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.white.withValues(alpha: 0.1),
                                      blurRadius: 20,
                                      spreadRadius: 2,
                                    ),
                                  ],
                                ),
                                child: Icon(
                                  widget.icone,
                                  size: 38,
                                  color: Colors.white,
                                ),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 20),
                        Text(
                          widget.titulo,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // --- Corpo ---
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
                    child: Column(
                      children: [
                        Text(
                          widget.mensagem,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 14,
                            color: const Color(0xFF1A1A2E),
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 24),
                        // Barra de progresso animada
                        AnimatedBuilder(
                          animation: _progressAnim,
                          builder: (context, child) {
                            return ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: _progressAnim.value,
                                minHeight: 6,
                                backgroundColor: const Color(0xFFF5F4F8),
                                color: const Color(0xFF6A1B9A),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 12),
                        // Dots pulando
                        AnimatedBuilder(
                          animation: _animCtrl,
                          builder: (context, child) {
                            final dotPhase = _animCtrl.value * 6 % 3;
                            return Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: List.generate(3, (i) {
                                final active =
                                    (i + dotPhase).floor() % 3 == 0;
                                return Container(
                                  margin:
                                      const EdgeInsets.symmetric(horizontal: 4),
                                  width: active ? 8 : 6,
                                  height: active ? 8 : 6,
                                  decoration: BoxDecoration(
                                    color: active
                                        ? const Color(0xFF6A1B9A)
                                        : const Color(0xFFCCC8D4),
                                    shape: BoxShape.circle,
                                  ),
                                );
                              }),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Modal premium de resultado (teste conexão / salvamento / envio).
/// Aparece sobre QUALQUER dialog via rootNavigator.
class _PremiumResultDialog extends StatefulWidget {
  const _PremiumResultDialog({
    required this.sucesso,
    required this.titulo,
    required this.mensagem,
    this.detalhe,
    this.botaoLabel,
    this.onBotao,
    this.iconeCustom,
    this.infoExtra,
  });

  final bool sucesso;
  final String titulo;
  final String mensagem;
  final String? detalhe;
  final String? botaoLabel;
  final VoidCallback? onBotao;
  final Widget? iconeCustom;
  final List<Widget>? infoExtra;

  @override
  State<_PremiumResultDialog> createState() => _PremiumResultDialogState();
}

class _PremiumResultDialogState extends State<_PremiumResultDialog>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animCtrl;
  late final Animation<double> _scaleAnim;
  late final Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _scaleAnim = CurvedAnimation(
      parent: _animCtrl,
      curve: const ElasticOutCurve(0.6),
    );
    _fadeAnim = CurvedAnimation(
      parent: _animCtrl,
      curve: const Interval(0.0, 0.5, curve: Curves.easeOut),
    );
    _animCtrl.forward();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  Color get _corPrimaria =>
      widget.sucesso ? const Color(0xFF16A34A) : const Color(0xFFDC2626);

  IconData get _icone =>
      widget.sucesso ? Icons.check_circle_rounded : Icons.cancel_rounded;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: FadeTransition(
        opacity: _fadeAnim,
        child: ScaleTransition(
          scale: _scaleAnim,
          child: AlertDialog(
            insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            contentPadding: EdgeInsets.zero,
            clipBehavior: Clip.antiAlias,
            content: SizedBox(
              width: 440,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // --- Header com gradiente ---
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          _corPrimaria,
                          _corPrimaria.withValues(alpha: 0.85),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: Column(
                      children: [
                        // Ícone animado pulsando
                        AnimatedBuilder(
                          animation: _animCtrl,
                          builder: (context, child) {
                            final pulse =
                                1.0 + 0.06 * math.sin(_animCtrl.value * math.pi * 2);
                            return Transform.scale(
                              scale: pulse,
                              child: widget.iconeCustom ??
                                  Container(
                                    width: 72,
                                    height: 72,
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(alpha: 0.2),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      _icone,
                                      size: 40,
                                      color: Colors.white,
                                    ),
                                  ),
                            );
                          },
                        ),
                        const SizedBox(height: 16),
                        Text(
                          widget.titulo,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // --- Corpo ---
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.mensagem,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: const Color(0xFF1A1A2E),
                            height: 1.45,
                          ),
                        ),
                        if (widget.detalhe != null) ...[
                          const SizedBox(height: 8),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.info_outline,
                                size: 14,
                                color: PainelAdminTheme.textoSecundario,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  widget.detalhe!,
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 13,
                                    color: PainelAdminTheme.textoSecundario,
                                    height: 1.4,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                        if (widget.infoExtra != null &&
                            widget.infoExtra!.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: widget.infoExtra!,
                          ),
                        ],
                      ],
                    ),
                  ),

                  // --- Footer ---
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 4, 24, 20),
                    child: SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: FilledButton(
                        onPressed: () {
                          widget.onBotao?.call();
                          Navigator.pop(context);
                        },
                        style: FilledButton.styleFrom(
                          backgroundColor: _corPrimaria,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          elevation: 0,
                        ),
                        child: Text(
                          widget.botaoLabel ?? 'Fechar',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EmailPreviewPanel extends StatelessWidget {
  const _EmailPreviewPanel({
    required this.template,
    required this.mobile,
  });

  final EmailTemplateModel template;
  final bool mobile;

  /// Constrói vars combinando as fictícias com os dados da identidade visual.
  Map<String, String> _buildVars(EmailIdentidadeVisual id) {
    return <String, String>{
      ...kEmailPreviewVars,
      'loja': id.nomeLoja.isNotEmpty ? id.nomeLoja : kEmailPreviewVars['loja']!,
      'telefone':
          id.telefone.isNotEmpty ? id.telefone : kEmailPreviewVars['telefone']!,
      'whatsapp':
          id.whatsapp.isNotEmpty ? id.whatsapp : kEmailPreviewVars['telefone']!,
      'site': id.site,
      'link_pagamento': kEmailPreviewVars['link'] ?? 'https://dipertin.com.br/pagar',
    };
  }

  @override
  Widget build(BuildContext context) {
    final id = template.identidadeVisual;
    final corP = parseHexColor(id.corPrincipal) ?? PainelAdminTheme.roxo;
    final corS = parseHexColor(id.corSecundaria) ?? PainelAdminTheme.laranja;
    final corB = parseHexColor(id.corBotao) ?? corP;
    final vars = _buildVars(id);

    return Material(
      elevation: 2,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: EdgeInsets.all(mobile ? 16 : 24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            // --- Logo ---
            if (id.logoUrl.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Image.network(
                  substituirVariaveisEmail(id.logoUrl, vars),
                  height: 44,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),

            // --- Assunto (opcional) ---
            if (template.assunto.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  substituirVariaveisEmail(template.assunto, vars),
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: PainelAdminTheme.textoSecundario,
                  ),
                ),
              ),

            // --- Blocos ---
            ...template.blocks.map((b) {
              final c = substituirVariaveisEmail(b.conteudo, vars);
              switch (b.tipo) {
                case 'titulo':
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(c,
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: corP)),
                  );
                case 'texto':
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(c,
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 14, height: 1.5)),
                  );
                case 'divisor':
                  return const Divider(height: 24);
                case 'botao':
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Align(
                      alignment: Alignment.center,
                      child: FilledButton(
                        onPressed: () {},
                        style: FilledButton.styleFrom(backgroundColor: corB),
                        child: Text(substituirVariaveisEmail(
                            b.textoBotao ?? 'Pagar Agora', vars)),
                      ),
                    ),
                  );
                case 'imagem':
                  final url = substituirVariaveisEmail(b.url ?? c, vars);
                  if (url.isEmpty) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Image.network(
                      url,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                    ),
                  );
                default:
                  return const SizedBox.shrink();
              }
            }),

            // --- Rodapé ---
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.only(top: 12),
              decoration: const BoxDecoration(
                border: Border(
                  top: BorderSide(color: Color(0xFFE5E7EB)),
                ),
              ),
              child: Text(
                'Recebeu este e-mail porque possui cadastro na loja.',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 11,
                  color: PainelAdminTheme.textoSecundario,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              substituirVariaveisEmail(id.nomeLoja, vars),
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF1A1A2E),
              ),
            ),
            if (id.telefone.isNotEmpty || id.whatsapp.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                [
                  if (id.telefone.isNotEmpty) 'Tel: ${substituirVariaveisEmail(id.telefone, vars)}',
                  if (id.whatsapp.isNotEmpty) 'WhatsApp: ${substituirVariaveisEmail(id.whatsapp, vars)}',
                ].join(' · '),
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 11,
                  color: PainelAdminTheme.textoSecundario,
                ),
              ),
            ],
            if (id.site.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                substituirVariaveisEmail(id.site, vars),
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 11,
                  color: corS,
                ),
              ),
            ],
            if (id.instagram.isNotEmpty || id.facebook.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                [id.instagram, id.facebook].where((s) => s.isNotEmpty).join(' · '),
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 11,
                  color: PainelAdminTheme.textoSecundario,
                ),
              ),
            ],
            if (id.endereco.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                substituirVariaveisEmail(id.endereco, vars),
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 11,
                  color: PainelAdminTheme.textoSecundario,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
