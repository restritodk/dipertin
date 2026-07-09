import 'dart:convert';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../models/modulo_config_model.dart';
import '../services/modulos_config_service.dart';
import '../models/fiscal_integration_model.dart';
import '../services/fiscal_integrations_service.dart';
import '../services/fiscal/fiscal_provider_service.dart';
import '../models/plano_emissao_nfe_model.dart';
import '../models/lojista_integracao_model.dart';
import '../services/lojista_integracao_service.dart';
import '../theme/painel_admin_theme.dart';
import '../models/cliente_assinatura_model.dart';
import '../models/billing_settings_model.dart';
import '../services/billing_settings_service.dart';
import '../services/firebase_functions_config.dart';
import '../widgets/fiscal/fiscal_teste_conexao_modal.dart';
import '../widgets/premium_dialogs.dart';

// ============================================================
// Cores do módulo
// ============================================================
const Color _textoPrimario = Color(0xFF17152A);
const Color _textoSecundario = Color(0xFF6E7894);
const Color _textoDescricao = Color(0xFF65708C);
const Color _fundoPagina = Color(0xFFF8F8FC);
const Color _bordaCard = Color(0xFFEEEAF6);
const Color _bordaInput = Color(0xFFE9E8F0);
const Color _roxoBtn = Color(0xFF7D20E8);
const Color _roxoCard = Color(0xFF6E22D9);
const Color _lilasFundo = Color(0xFFF1E9FF);
const Color _verdeStatus = Color(0xFF16A34A);
const Color _verdeFundo = Color(0xFFE8F5E9);
const Color _vermelhoStatus = Color(0xFFDC2626);
const Color _laranjaStatus = Color(0xFFEA580C);
const Color _cinzaStatus = Color(0xFF9CA3AF);
const Color _cinzaFundo = Color(0xFFF3F4F6);
// ─── Tokens premium ─────────────────────────────────────────
const Color _roxoPrimario = Color(0xFF6A1B9A);
const Color _roxoClaro = Color(0xFF8E24AA);
const Color _laranjaPrimario = Color(0xFFFF8F00);

/// Mapa de cores por nome de módulo (para exibição).
Color _corModulo(String nome) {
  final cores = [
    const Color(0xFF6A1B9A),
    const Color(0xFF2563EB),
    const Color(0xFF16A34A),
    const Color(0xFFEA580C),
    const Color(0xFFD97706),
    const Color(0xFF7C3AED),
    const Color(0xFF0891B2),
    const Color(0xFFBE185D),
    const Color(0xFF4F46E5),
    const Color(0xFF059669),
    const Color(0xFFD946EF),
    const Color(0xFFB45309),
  ];
  return cores[nome.hashCode.abs() % cores.length];
}

IconData _iconeModulo(String? iconeNome) {
  switch (iconeNome) {
    case 'dashboard':
      return Icons.dashboard_rounded;
    case 'store':
      return Icons.store_rounded;
    case 'people':
      return Icons.people_rounded;
    case 'payment':
      return Icons.payments_rounded;
    case 'receipt':
      return Icons.receipt_rounded;
    case 'assessment':
      return Icons.assessment_rounded;
    case 'inventory':
      return Icons.inventory_2_rounded;
    case 'notifications':
      return Icons.notifications_rounded;
    case 'chat':
      return Icons.chat_rounded;
    case 'settings':
      return Icons.settings_rounded;
    case 'security':
      return Icons.security_rounded;
    case 'analytics':
      return Icons.analytics_rounded;
    case 'sell':
      return Icons.sell_rounded;
    case 'widgets':
      return Icons.widgets_rounded;
    case 'qr_code':
      return Icons.qr_code_scanner_rounded;
    case 'description':
      return Icons.description_rounded;
    default:
      return Icons.widgets_rounded;
  }
}

// ============================================================
// TELA PRINCIPAL
// ============================================================
class AssinaturasConfiguracoesScreen extends StatefulWidget {
  const AssinaturasConfiguracoesScreen({super.key});

  @override
  State<AssinaturasConfiguracoesScreen> createState() =>
      _AssinaturasConfiguracoesScreenState();
}

class _AssinaturasConfiguracoesScreenState
    extends State<AssinaturasConfiguracoesScreen> {
  int _tabIndex = 0;

  void _exibirSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        backgroundColor: _roxoBtn,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _fundoPagina,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFF3E5F5), Color(0xFFF5F4F8), Color(0xFFF5F4F8)],
            stops: [0.0, 0.3, 1.0],
          ),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
          child: _buildConteudo(),
        ),
      ),
    );
  }

  Widget _buildConteudo() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildHeader(),
        const SizedBox(height: 24),
        _buildTabs(),
        const SizedBox(height: 24),
        if (_tabIndex == 0) ...[
          _buildSummaryCards(),
          const SizedBox(height: 28),
          _buildSecaoModulos(),
        ] else if (_tabIndex == 1) ...[
          _buildSecaoIntegracoes(),
        ] else if (_tabIndex == 2) ...[
          _buildSecaoIntegracoesLojistas(),
        ] else ...[
          _buildSecaoConfiguracoesCobrancas(),
        ],
        const SizedBox(height: 32),
      ],
    );
  }

  // ─── ABAS ─────────────────────────────────────────────────
  Widget _buildTabs() {
    final tabs = ['Módulos', 'Integrações', 'Integrações Lojistas', 'Config. Cobranças'];
    final icons = [
      Icons.widgets_rounded,
      Icons.integration_instructions_rounded,
      Icons.store_rounded,
      Icons.receipt_long_rounded,
    ];
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: _roxoPrimario.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
          BoxShadow(
            color: _roxoPrimario.withValues(alpha: 0.03),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        children: List.generate(tabs.length, (i) {
          final selecionado = _tabIndex == i;
          return Expanded(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => setState(() => _tabIndex = i),
                borderRadius: BorderRadius.circular(14),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOut,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    gradient: selecionado
                        ? const LinearGradient(
                            colors: [_roxoPrimario, _roxoClaro],
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                          )
                        : null,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: selecionado
                        ? [
                            BoxShadow(
                              color: _roxoPrimario.withValues(alpha: 0.25),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ]
                        : null,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        icons[i],
                        size: 18,
                        color: selecionado ? Colors.white : _textoSecundario,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        tabs[i],
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: selecionado ? Colors.white : _textoSecundario,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  // ─── SEÇÃO INTEGRAÇÕES ────────────────────────────────────
  Widget _buildSecaoIntegracoes() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Header da seção ──
        _buildIntegracoesHeader(),
        const SizedBox(height: 24),
        // ── Stream de integrações ──
        StreamBuilder<List<FiscalIntegrationModel>>(
          stream: FiscalIntegrationsService.streamIntegracoes(),
          builder: (context, snap) {
            if (snap.hasError) {
              return _buildErroCard(snap.error.toString());
            }
            final integracoes = snap.data ?? [];
            return _buildIntegracoesGrid(integracoes, snap.connectionState);
          },
        ),
      ],
    );
  }

  Widget _buildIntegracoesHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: _roxoPrimario.withValues(alpha: 0.06),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
          BoxShadow(
            color: _roxoPrimario.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: _lilasFundo,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.integration_instructions_rounded,
              color: _roxoPrimario,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Integrações',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: _textoPrimario,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Configure conexões fiscais, financeiras e operacionais do sistema.',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    color: _textoSecundario,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          _btnPrimarioGradiente(
            icone: Icons.add_rounded,
            label: 'Nova integração',
            onTap: _abrirNovaIntegracao,
          ),
        ],
      ),
    );
  }

  Widget _buildIntegracoesGrid(
    List<FiscalIntegrationModel> integracoes,
    ConnectionState estado,
  ) {
    if (estado == ConnectionState.waiting) {
      return _buildCardContainer(
        child: const Padding(
          padding: EdgeInsets.all(48),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final colCount = w > 1100 ? 2 : 1;
        const gap = 16.0;
        final todosOsCards = <Widget>[
          // Cards das integrações cadastradas
          ...integracoes.map((i) => _buildIntegrationCardFromModel(i)),
        ];

        // Se não houver integrações cadastradas e já carregou, exibe card vazio
        if (integracoes.isEmpty && estado == ConnectionState.done) {
          // Já temos o card Nota Fiscal, que é o principal
        }

        final linhas = <Widget>[];
        for (int i = 0; i < todosOsCards.length; i += colCount) {
          final fim = (i + colCount).clamp(0, todosOsCards.length);
          linhas.add(
            Padding(
              padding: EdgeInsets.only(
                bottom: fim < todosOsCards.length ? gap : 0,
              ),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (int j = i; j < fim; j++)
                      Expanded(
                        flex: 1,
                        child: Padding(
                          padding: EdgeInsets.only(
                            left: j > i ? gap / 2 : 0,
                            right: j < fim - 1 ? gap / 2 : 0,
                          ),
                          child: todosOsCards[j],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        }
        return _buildCardContainer(child: Column(children: linhas));
      },
    );
  }

  Widget _buildCardContainer({required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: _roxoPrimario.withValues(alpha: 0.06),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
          BoxShadow(
            color: _roxoPrimario.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
  }

  // ─── Integration Card ─────────────────────────────────────
  Widget _buildIntegrationCard({
    required IconData icone,
    required Color cor,
    required String titulo,
    required String subtitulo,
    required _StatusIntegracao statusIntegracao,
    VoidCallback? onConfigurar,
    VoidCallback? onTestar,
    VoidCallback? onDetalhes,
    VoidCallback? onExcluir,
  }) {
    final (statusLabel, statusCor, statusFundo) = switch (statusIntegracao) {
      _StatusIntegracao.configurado => (
        'Configurado',
        _verdeStatus,
        _verdeFundo,
      ),
      _StatusIntegracao.erro => (
        'Erro na conexão',
        _vermelhoStatus,
        const Color(0xFFFEF2F2),
      ),
      _StatusIntegracao.naoConfigurado => (
        'Não configurado',
        _cinzaStatus,
        _cinzaFundo,
      ),
    };

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cor.withValues(alpha: 0.12)),
        boxShadow: [
          BoxShadow(
            color: cor.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [cor, cor.withValues(alpha: 0.7)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icone, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titulo,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: _textoPrimario,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitulo,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11,
                        color: _textoSecundario,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Badge de status
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: statusFundo,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: statusCor.withValues(alpha: 0.25)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: statusCor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  statusLabel,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: statusCor,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          const Divider(height: 1, color: Color(0xFFEEEAF6)),
          const SizedBox(height: 12),
          // Botões de ação
          Row(
            children: [
              _btnAcao('Configurar', _roxoPrimario, onConfigurar),
              const SizedBox(width: 8),
              _btnAcao('Testar', _roxoPrimario, onTestar, outline: true),
              const Spacer(),
              if (onExcluir != null) ...[
                InkWell(
                  onTap: onExcluir,
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: _vermelhoStatus.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Icon(
                      Icons.delete_outline_rounded,
                      size: 16,
                      color: _vermelhoStatus,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
              ],
              InkWell(
                onTap: onDetalhes,
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  child: Row(
                    children: [
                      Text(
                        'Detalhes',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 11,
                          color: _textoSecundario,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 14,
                        color: _textoSecundario,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildIntegrationCardFromModel(FiscalIntegrationModel model) {
    final cor = _corModulo(model.provider);
    final _StatusIntegracao status = switch (model.status) {
      'active' => _StatusIntegracao.configurado,
      'error' => _StatusIntegracao.erro,
      _ => _StatusIntegracao.naoConfigurado,
    };
    return _buildIntegrationCard(
      icone: Icons.cloud_rounded,
      cor: cor,
      titulo: model.nomeExibicao,
      subtitulo:
          '${model.nomeIntegracao != null ? '${model.providerName} · ' : ''}${model.environment == 'production' ? 'Produção' : 'Homologação'} · ${model.supportedDocuments.join(", ").toUpperCase()}',
      statusIntegracao: status,
      onConfigurar: () => _abrirEditarIntegracao(model),
      onTestar: () => _testarConexaoFiscal(model.provider, model.nomeExibicao),
      onDetalhes: () => _exibirSnack('Detalhes: ${model.nomeExibicao}'),
      onExcluir: () => _confirmarExclusaoIntegracao(model),
    );
  }

  Future<void> _abrirEditarIntegracao(
    FiscalIntegrationModel model,
  ) async {
    if (!mounted) return;
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => _EditarIntegracaoDialog(integracao: model),
    );
    if (result == true && mounted) {
      _exibirSnack('Integração "${model.providerName}" atualizada com sucesso!');
    }
  }

  Future<void> _confirmarExclusaoIntegracao(
    FiscalIntegrationModel model,
  ) async {
    final confirmou = await _confirmarAcao(
      context: context,
      icone: Icons.delete_forever_rounded,
      corIcone: _vermelhoStatus,
      titulo: 'Excluir integração?',
      mensagem:
          'Tem certeza que deseja excluir "${model.nomeExibicao}" permanentemente? Esta ação não pode ser desfeita.',
      textoConfirmar: 'Sim, excluir',
    );
    if (!confirmou || !mounted) return;
    await FiscalIntegrationsService.removerIntegracao(model.id);
    if (mounted) _exibirSnack('Integração "${model.nomeExibicao}" excluída.');
  }

  Future<void> _testarConexaoFiscal(
    String providerId,
    String providerNome,
  ) async {
    if (!mounted) return;
    await mostrarTesteConexaoPremium(
      context,
      provedor: providerNome,
      testar: () async {
        // ─── Teste REAL na API Focus NFe via Cloud Function ───
        // Chama o provider real que faz uma requisição GET autêntica
        // para a Focus NFe (https://homologacao.focusnfe.com.br/v2/empresas
        // ou https://api.focusnfe.com.br/v2/empresas) com Basic Auth.
        //
        // Se o token for inválido, a Focus retorna HTTP 401/403.
        // Se a URL estiver errada, retorna 404.
        // Só considera sucesso se HTTP 200/201/202.
        // NUNCA retorna sucesso por mock, catch genérico ou validação local.
        try {
          final providerService = FiscalProviderService.instance;
          final provider = providerService.obterProvider(providerId);
          if (provider == null) {
            return TestConexaoResultado(
              sucesso: false,
              provedor: providerNome,
              mensagem: 'Provedor fiscal não encontrado.',
              errosDetalhados: ['Provider "$providerId" não está registrado.'],
            );
          }

          // Busca a primeira integração ativa deste provider
          final integracoes = await FiscalIntegrationsService.streamIntegracoes()
            .first;
          final integracao = integracoes.firstWhere(
            (i) => i.provider == providerId && i.isAtivo,
            orElse: () => integracoes.isNotEmpty &&
                integracoes.any((i) => i.provider == providerId)
                ? integracoes.firstWhere((i) => i.provider == providerId)
                : integracoes.isNotEmpty
                    ? integracoes.first
                    : FiscalIntegrationModel(
                        id: '',
                        provider: providerId,
                        providerName: providerNome,
                        status: 'inactive',
                      ),
          );

          if (integracao.id.isEmpty) {
            return TestConexaoResultado(
              sucesso: false,
              provedor: providerNome,
              mensagem: 'Nenhuma integração fiscal encontrada para $providerNome.',
              errosDetalhados: ['Crie uma integração antes de testar.'],
            );
          }

          final config = providerService.extrairConfig(
            integracao.toMap(),
            integrationId: integracao.id,
          );

          final sucesso = await provider.testarConexao(config);

          if (sucesso) {
            return TestConexaoResultado(
              sucesso: true,
              provedor: providerNome,
              mensagem: 'Credenciais validadas com sucesso no ambiente '
                  '${integracao.environment == 'production' ? 'Produção' : 'Homologação'}.',
              ambiente: integracao.environment == 'production' ? 'Produção' : 'Homologação',
            );
          }

          return TestConexaoResultado(
            sucesso: false,
            provedor: providerNome,
            mensagem: 'Token Focus NFe inválido ou sem permissão para este ambiente.',
            errosDetalhados: [
              'A API Focus NFe rejeitou as credenciais.',
              'Ambiente: ${integracao.environment == 'production' ? 'Produção' : 'Homologação'}',
            ],
          );
        } catch (e) {
          return TestConexaoResultado(
            sucesso: false,
            provedor: providerNome,
            mensagem: 'Não foi possível conectar à Focus NFe no momento.',
            errosDetalhados: [e.toString()],
          );
        }
      },
    );
  }

  Widget _btnAcao(
    String label,
    Color cor,
    VoidCallback? onTap, {
    bool outline = false,
  }) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            gradient: outline
                ? null
                : LinearGradient(colors: [cor, cor.withValues(alpha: 0.8)]),
            color: outline ? Colors.white : null,
            borderRadius: BorderRadius.circular(8),
            border: outline
                ? Border.all(color: cor.withValues(alpha: 0.3))
                : null,
          ),
          child: Text(
            label,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: outline ? cor : Colors.white,
            ),
          ),
        ),
      ),
    );
  }

  Widget _btnPrimarioGradiente({
    required IconData icone,
    required String label,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [_roxoPrimario, _roxoClaro],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(
                color: _roxoPrimario.withValues(alpha: 0.25),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icone, size: 16, color: Colors.white),
              const SizedBox(width: 6),
              Text(
                label,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErroCard(String erro) {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: _roxoPrimario.withValues(alpha: 0.06),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Center(
        child: Column(
          children: [
            Icon(Icons.error_outline_rounded, size: 48, color: _vermelhoStatus),
            const SizedBox(height: 16),
            Text(
              'Erro ao carregar integrações',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: _textoPrimario,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              erro,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                color: _textoSecundario,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── SEÇÃO INTEGRAÇÕES LOJISTAS ─────────────────────────
  Widget _buildSecaoIntegracoesLojistas() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildIntegracoesLojistasHeader(),
        const SizedBox(height: 24),
        StreamBuilder<List<LojistaIntegracaoModel>>(
          stream: LojistaIntegracaoService.streamIntegracoes(),
          builder: (context, snap) {
            if (snap.hasError) return _buildErroCard(snap.error.toString());
            final lista = snap.data ?? [];
            return _buildLojistasDashboard(lista, snap.connectionState);
          },
        ),
      ],
    );
  }

  Widget _buildIntegracoesLojistasHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: _roxoPrimario.withValues(alpha: 0.06),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
          BoxShadow(
            color: _roxoPrimario.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: _lilasFundo,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.store_rounded,
              color: _roxoPrimario,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Integrações Lojistas',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: _textoPrimario,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Destinada aos lojistas que desejam emitir NF-e utilizando a infraestrutura do DiPertin.',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    color: _textoSecundario,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          _btnPrimarioGradiente(
            icone: Icons.add_rounded,
            label: 'Nova Integração',
            onTap: _abrirNovaIntegracaoLojista,
          ),
        ],
      ),
    );
  }

  Widget _buildLojistasDashboard(
    List<LojistaIntegracaoModel> lista,
    ConnectionState estado,
  ) {
    if (estado == ConnectionState.waiting) {
      return _buildCardContainer(
        child: const Padding(
          padding: EdgeInsets.all(64),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    final ativas = lista.where((i) => i.estaAtiva).length;
    final suspensas = lista.where((i) => i.estaSuspensa).length;
    final bloqueadas = lista.where((i) => i.estaBloqueada).length;
    final totalEmitidas = lista.fold<int>(0, (s, i) => s + i.notasEmitidas);
    final fmt = NumberFormat.decimalPattern('pt_BR');

    return Column(
      children: [
        // KPIs
        LayoutBuilder(
          builder: (context, constraints) {
            final w = constraints.maxWidth;
            final cellW = w > 900
                ? (w - 48) / 4
                : w > 600
                ? (w - 16) / 2
                : w;
            return Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                SizedBox(
                  width: cellW,
                  child: _kpiCard(
                    'Total',
                    fmt.format(lista.length),
                    Icons.store_rounded,
                    _roxoPrimario,
                    'integrações',
                  ),
                ),
                SizedBox(
                  width: cellW,
                  child: _kpiCard(
                    'Ativas',
                    fmt.format(ativas),
                    Icons.check_circle_rounded,
                    _verdeStatus,
                    'lojistas',
                  ),
                ),
                SizedBox(
                  width: cellW,
                  child: _kpiCard(
                    'Suspensas/Bloq.',
                    fmt.format(suspensas + bloqueadas),
                    Icons.warning_amber_rounded,
                    _laranjaStatus,
                    'lojistas',
                  ),
                ),
                SizedBox(
                  width: cellW,
                  child: _kpiCard(
                    'Notas emitidas',
                    fmt.format(totalEmitidas),
                    Icons.description_rounded,
                    _roxoPrimario,
                    'no mês atual',
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 20),
        // Tabela
        _buildLojistasTabela(lista),
      ],
    );
  }

  Widget _kpiCard(
    String label,
    String valor,
    IconData icone,
    Color cor,
    String rodape,
  ) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _roxoPrimario.withValues(alpha: 0.06)),
        boxShadow: [
          BoxShadow(
            color: _roxoPrimario.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: cor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icone, color: cor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  valor,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: _textoPrimario,
                  ),
                ),
                Text(
                  label,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    color: _textoSecundario,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLojistasTabela(List<LojistaIntegracaoModel> lista) {
    if (lista.isEmpty) {
      return _buildCardContainer(
        child: Padding(
          padding: const EdgeInsets.all(48),
          child: Center(
            child: Column(
              children: [
                Icon(
                  Icons.store_mall_directory_rounded,
                  size: 56,
                  color: _roxoPrimario.withValues(alpha: 0.3),
                ),
                const SizedBox(height: 16),
                Text(
                  'Nenhuma integração cadastrada',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: _textoPrimario,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Clique em "Nova Integração" para começar.',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    color: _textoSecundario,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return _buildCardContainer(
      child: Column(
        children: [
          // Header da tabela
          Container(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
            decoration: const BoxDecoration(
              color: _roxoPrimario,
              borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
            ),
            child: Row(
              children: [
                _th('Lojista', 22),
                _th('Plano', 14),
                _th('Utilização', 18),
                _th('Status', 12),
                _th('Renovação', 16),
                _th('Ações', 14),
              ],
            ),
          ),
          // Linhas
          ...List.generate(lista.length, (i) {
            final item = lista[i];
            final fmtData = DateFormat('dd/MM/yyyy', 'pt_BR');
            return Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: const Color(0xFFEEEAF6),
                    width: i < lista.length - 1 ? 1 : 0,
                  ),
                ),
              ),
              child: Row(
                children: [
                  _td(item.storeNome, 22, fontWeight: FontWeight.w600),
                  _td(item.planoNome, 14),
                  // Barra de progresso
                  Expanded(
                    flex: 18,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              '${item.emitidasExibir}/${item.limiteExibir}',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 11,
                                color: _textoPrimario,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              '${item.percentualUtilizado.toStringAsFixed(0)}%',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 10,
                                color: item.atingiuLimite
                                    ? _vermelhoStatus
                                    : _textoSecundario,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: LinearProgressIndicator(
                            value: item.limiteMensal > 0
                                ? (item.notasEmitidas / item.limiteMensal)
                                      .clamp(0, 1)
                                : 0,
                            backgroundColor: const Color(0xFFEEEAF6),
                            valueColor: AlwaysStoppedAnimation<Color>(
                              item.atingiuLimite
                                  ? _vermelhoStatus
                                  : _roxoPrimario,
                            ),
                            minHeight: 5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Status
                  Expanded(
                    flex: 12,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: item.statusFundo,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: item.statusCor.withValues(alpha: 0.25),
                          ),
                        ),
                        child: Text(
                          item.statusLabel,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: item.statusCor,
                          ),
                        ),
                      ),
                    ),
                  ),
                  _td(
                    item.proximaRenovacao != null
                        ? fmtData.format(item.proximaRenovacao!.toDate())
                        : '—',
                    16,
                  ),
                  // Ações
                  Expanded(
                    flex: 14,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _btnIcon(
                          Icons.visibility_rounded,
                          _roxoPrimario,
                          () => _abrirDetalheIntegracao(item),
                        ),
                        const SizedBox(width: 4),
                        _btnIcon(
                          Icons.delete_outline_rounded,
                          _vermelhoStatus,
                          () => _confirmarExclusaoLojista(item),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _th(String label, int flex) {
    return Expanded(
      flex: flex,
      child: Text(
        label,
        style: GoogleFonts.plusJakartaSans(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: Colors.white,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _td(
    String texto,
    int flex, {
    FontWeight fontWeight = FontWeight.w400,
  }) {
    return Expanded(
      flex: flex,
      child: Text(
        texto,
        style: GoogleFonts.plusJakartaSans(
          fontSize: 12,
          color: _textoPrimario,
          fontWeight: fontWeight,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _btnIcon(IconData icone, Color cor, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: cor.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(icone, size: 15, color: cor),
      ),
    );
  }

  // ─── Ações de Integração Lojista ─────────────────────────
  void _abrirNovaIntegracaoLojista() {
    showDialog(
      context: context,
      useRootNavigator: true,
      builder: (_) => _NovaIntegracaoLojistaDialog(
        onSalvar: () => _exibirSnack('Integração criada com sucesso!'),
      ),
    );
  }

  void _abrirDetalheIntegracao(LojistaIntegracaoModel model) {
    showDialog(
      context: context,
      useRootNavigator: true,
      builder: (_) => _DetalheIntegracaoLojistaDialog(
        integracao: model,
        onAtualizar: () => setState(() {}),
        onExcluir: () {
          if (mounted) _exibirSnack('Integração excluída.');
        },
      ),
    );
  }

  Future<void> _confirmarExclusaoLojista(LojistaIntegracaoModel model) async {
    final confirmou = await _confirmarAcao(
      context: context,
      icone: Icons.delete_forever_rounded,
      corIcone: _vermelhoStatus,
      titulo: 'Excluir integração?',
      mensagem:
          'Tem certeza que deseja excluir a integração de "${model.storeNome}"? Esta ação não pode ser desfeita.',
      textoConfirmar: 'Sim, excluir',
    );
    if (!confirmou || !mounted) return;
    await LojistaIntegracaoService.excluirIntegracao(model.id);
    if (mounted) _exibirSnack('Integração de "${model.storeNome}" excluída.');
  }

  // ─── Ações ─────────────────────────────────────────────────
  void _abrirNovaIntegracao() {
    showDialog(
      context: context,
      useRootNavigator: true,
      builder: (_) => _NovaIntegracaoDialog(
        onSalvar: (providerId, nome, dados) {
          _exibirSnack('Integração $nome cadastrada com sucesso!');
        },
      ),
    );
  }

  // ─── HEADER ────────────────────────────────────────────────
  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 22),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [_roxoPrimario.withValues(alpha: 0.04), Colors.white],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _roxoPrimario.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [_roxoPrimario, _roxoClaro],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: _roxoPrimario.withValues(alpha: 0.25),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.widgets_rounded,
              color: Colors.white,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Configurações Gerais',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: _textoPrimario,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Gerencie todas as configurações relacionadas ao menu Gestão de Assinaturas.',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    color: _textoSecundario,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Container(
            width: 4,
            height: 48,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [_roxoPrimario, _laranjaPrimario],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ],
      ),
    );
  }

  // ─── SUMMARY CARDS (MÓDULOS) ──────────────────────────────
  Widget _buildSummaryCards() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: ModulosConfigService.stream(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const SizedBox(
            height: 120,
            child: Center(child: CircularProgressIndicator(strokeWidth: 3)),
          );
        }
        final modulos = snap.data!.docs
            .map((d) => ModuloConfigModel.fromFirestore(d))
            .toList();
        final total = modulos.length;
        final ativos = modulos.where((m) => m.ativo).length;
        final contrataveis = modulos.where((m) => m.contratavel).length;
        final fmtInt = NumberFormat.decimalPattern('pt_BR');

        return LayoutBuilder(
          builder: (context, constraints) {
            final w = constraints.maxWidth;
            final colW = w > 1200
                ? (w - 64) / 5
                : w > 900
                ? (w - 48) / 3
                : w > 600
                ? (w - 16) / 2
                : w;
            return Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                SizedBox(
                  width: colW,
                  child: _ModuloSummaryCard(
                    icone: Icons.widgets_rounded,
                    cor: const Color(0xFF6A1B9A),
                    titulo: 'Total de módulos',
                    valor: fmtInt.format(total),
                    variacao:
                        '$total módulo${total == 1 ? '' : 's'} cadastrado${total == 1 ? '' : 's'}',
                    sparklineDados: [1, 2, 3, 3, 4, total.toDouble()],
                  ),
                ),
                SizedBox(
                  width: colW,
                  child: _ModuloSummaryCard(
                    icone: Icons.check_circle_rounded,
                    cor: const Color(0xFF16A34A),
                    titulo: 'Módulos ativos',
                    valor: fmtInt.format(ativos),
                    variacao: ativos == 1
                        ? '1 módulo ativo'
                        : '$ativos módulos ativos',
                    sparklineDados: [1, 2, 2, 3, 3, ativos.toDouble()],
                  ),
                ),
                SizedBox(
                  width: colW,
                  child: _ModuloSummaryCard(
                    icone: Icons.thumb_up_alt_rounded,
                    cor: const Color(0xFF2563EB),
                    titulo: 'Disponíveis para contratação',
                    valor: fmtInt.format(contrataveis),
                    variacao: contrataveis == 1
                        ? '1 módulo contratável'
                        : '$contrataveis módulos contratáveis',
                    sparklineDados: [1, 1, 2, 2, 3, contrataveis.toDouble()],
                  ),
                ),
                SizedBox(
                  width: colW,
                  child: _ModuloSummaryCard(
                    icone: Icons.store_rounded,
                    cor: const Color(0xFFFF8F00),
                    titulo: 'Lojistas utilizando',
                    valor: '—',
                    variacao: 'Disponível em breve',
                    sparklineDados: [0, 0, 0, 0, 0, 0],
                  ),
                ),
                SizedBox(
                  width: colW,
                  child: _ModuloSummaryCard(
                    icone: Icons.trending_up_rounded,
                    cor: const Color(0xFF7C3AED),
                    titulo: 'Receita gerada',
                    valor: 'R\$ —',
                    variacao: 'Disponível em breve',
                    sparklineDados: [0, 0, 0, 0, 0, 0],
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ─── SEÇÃO MÓDULOS ────────────────────────────────────────
  final TextEditingController _searchModCtrl = TextEditingController();
  String _filtroStatus = 'todos';
  String _filtroContratavel = 'todos';
  bool _mostrarFiltros = false;

  @override
  void initState() {
    super.initState();
    _searchModCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _searchModCtrl.dispose();
    super.dispose();
  }

  Widget _buildSecaoModulos() {
    return _SecaoCard(
      titulo: 'Módulos',
      descricao: 'Cadastre e gerencie todos os módulos disponíveis do sistema.',
      action: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: () => _abrirModalNovoModulo(),
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [_roxoPrimario, _roxoClaro],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(
                  color: _roxoPrimario.withValues(alpha: 0.25),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.add_rounded, size: 16, color: Colors.white),
                const SizedBox(width: 6),
                Text(
                  '+ Novo módulo',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildFiltrosLinha(),
          const SizedBox(height: 20),
          _buildGridModulos(),
        ],
      ),
    );
  }

  Widget _buildFiltrosLinha() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 700;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 42,
                    child: TextField(
                      controller: _searchModCtrl,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        color: _textoPrimario,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Pesquisar módulo...',
                        hintStyle: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          color: _textoSecundario.withValues(alpha: 0.6),
                        ),
                        prefixIcon: const Icon(
                          Icons.search_rounded,
                          size: 20,
                          color: _textoSecundario,
                        ),
                        suffixIcon: _searchModCtrl.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear_rounded, size: 18),
                                onPressed: () => _searchModCtrl.clear(),
                              )
                            : null,
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 10,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: _bordaInput),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: _bordaInput),
                        ),
                      ),
                    ),
                  ),
                ),
                if (!compact) ...[
                  const SizedBox(width: 10),
                  _buildFiltroDropdown(
                    valor: _filtroStatus,
                    itens: const ['todos', 'ativos', 'inativos'],
                    rotulos: const ['Status', 'Ativos', 'Inativos'],
                    onChanged: (v) => setState(() => _filtroStatus = v!),
                  ),
                  const SizedBox(width: 10),
                  _buildFiltroDropdown(
                    valor: _filtroContratavel,
                    itens: const ['todos', 'sim', 'nao'],
                    rotulos: const ['Contratável', 'Sim', 'Não'],
                    onChanged: (v) => setState(() => _filtroContratavel = v!),
                  ),
                  const SizedBox(width: 10),
                  _buildBotaoFiltros(),
                ],
              ],
            ),
            if (compact) ...[
              const SizedBox(height: 10),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildFiltroDropdown(
                      valor: _filtroStatus,
                      itens: const ['todos', 'ativos', 'inativos'],
                      rotulos: const ['Status', 'Ativos', 'Inativos'],
                      onChanged: (v) => setState(() => _filtroStatus = v!),
                    ),
                    const SizedBox(width: 8),
                    _buildFiltroDropdown(
                      valor: _filtroContratavel,
                      itens: const ['todos', 'sim', 'nao'],
                      rotulos: const ['Contratável', 'Sim', 'Não'],
                      onChanged: (v) => setState(() => _filtroContratavel = v!),
                    ),
                    const SizedBox(width: 8),
                    _buildBotaoFiltros(),
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _buildFiltroDropdown({
    required String valor,
    required List<String> itens,
    required List<String> rotulos,
    required ValueChanged<String?> onChanged,
  }) {
    return Container(
      height: 42,
      constraints: const BoxConstraints(minWidth: 140),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _bordaInput),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: valor,
          isDense: true,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 13,
            color: _textoPrimario,
          ),
          icon: const Icon(
            Icons.expand_more_rounded,
            size: 18,
            color: _textoSecundario,
          ),
          items: List.generate(
            itens.length,
            (i) => DropdownMenuItem(
              value: itens[i],
              child: Text(
                rotulos[i],
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  fontWeight: itens[i] == valor
                      ? FontWeight.w600
                      : FontWeight.w400,
                ),
              ),
            ),
          ),
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _buildBotaoFiltros() {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: () => setState(() => _mostrarFiltros = !_mostrarFiltros),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          height: 42,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: _roxoPrimario.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _roxoPrimario.withValues(alpha: 0.15)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _mostrarFiltros
                    ? Icons.filter_alt_off_rounded
                    : Icons.filter_list_rounded,
                size: 18,
                color: _roxoPrimario,
              ),
              const SizedBox(width: 6),
              Text(
                'Filtros',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: _roxoPrimario,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<ModuloConfigModel> _filtrarModulos(List<ModuloConfigModel> modulos) {
    var resultado = modulos.toList();
    final query = _searchModCtrl.text.trim().toLowerCase();
    if (query.isNotEmpty) {
      resultado = resultado
          .where(
            (m) =>
                m.nome.toLowerCase().contains(query) ||
                m.codigo.toLowerCase().contains(query) ||
                m.descricao.toLowerCase().contains(query),
          )
          .toList();
    }
    if (_filtroStatus == 'ativos') {
      resultado = resultado.where((m) => m.ativo).toList();
    } else if (_filtroStatus == 'inativos') {
      resultado = resultado.where((m) => !m.ativo).toList();
    }
    if (_filtroContratavel == 'sim') {
      resultado = resultado.where((m) => m.contratavel).toList();
    } else if (_filtroContratavel == 'nao') {
      resultado = resultado.where((m) => !m.contratavel).toList();
    }
    return resultado;
  }

  Widget _buildGridModulos() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: ModulosConfigService.stream(),
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Text(
                'Erro ao carregar módulos.',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  color: _vermelhoStatus,
                ),
              ),
            ),
          );
        }
        if (!snap.hasData) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 60),
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
          );
        }
        final todosModulos = snap.data!.docs
            .map((d) => ModuloConfigModel.fromFirestore(d))
            .toList();
        final modulos = _filtrarModulos(todosModulos);

        if (modulos.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 48),
              child: Column(
                children: [
                  Icon(
                    Icons.widgets_rounded,
                    size: 48,
                    color: _textoSecundario.withValues(alpha: 0.4),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    todosModulos.isEmpty
                        ? 'Nenhum módulo cadastrado'
                        : 'Nenhum módulo encontrado para os filtros atuais.',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      color: _textoSecundario,
                    ),
                  ),
                  if (todosModulos.isEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Clique em "+ Novo módulo" para começar.',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        color: _textoDescricao,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        }

        final children = <Widget>[];
        if (modulos.isNotEmpty) {
          children.add(const SizedBox(height: 4));
          children.add(Container(height: 1, color: _bordaCard));
        }
        for (int i = 0; i < modulos.length; i++) {
          final m = modulos[i];
          children.add(
            _ModuloLinha(
              modulo: m,
              par: i.isOdd,
              onVisualizar: () => _abrirDetalheModulo(m),
              onEditar: () => _abrirModalEditarModulo(m),
              onDuplicar: () => _duplicarModulo(m),
              onToggleStatus: () => _confirmarToggleModulo(m),
              onExcluir: () => _confirmarExcluirModulo(m),
            ),
          );
        }
        return Column(children: children);
      },
    );
  }

  // ─── Ações de Módulo ──────────────────────────────────────
  Future<void> _abrirModalNovoModulo() async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (_) => const _NovoModuloFullDialog(),
    );
    if (result == true && mounted)
      _exibirSnack('Módulo cadastrado com sucesso!');
  }

  Future<void> _abrirModalEditarModulo(ModuloConfigModel modulo) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (_) => _EditarModuloFullDialog(modulo: modulo),
    );
    if (result == true && mounted)
      _exibirSnack('Módulo atualizado com sucesso!');
  }

  Future<void> _abrirDetalheModulo(ModuloConfigModel modulo) async {
    await showDialog(
      context: context,
      barrierDismissible: true,
      useRootNavigator: true,
      builder: (_) => _DetalheModuloModal(modulo: modulo),
    );
  }

  Future<void> _duplicarModulo(ModuloConfigModel modulo) async {
    try {
      await ModulosConfigService.criar(
        nome: '${modulo.nome} (cópia)',
        codigo: '${modulo.codigo}-CP',
        descricao: modulo.descricao,
        ativo: false,
        contratavel: false,
        icone: modulo.icone,
      );
      if (mounted) _exibirSnack('Módulo duplicado como inativo.');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao duplicar: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _confirmarToggleModulo(ModuloConfigModel modulo) async {
    final confirmou = await _confirmarAcao(
      context: context,
      icone: modulo.ativo ? Icons.block_flipped : Icons.check_circle_outline,
      corIcone: modulo.ativo ? _laranjaStatus : _verdeStatus,
      titulo: modulo.ativo ? 'Desativar módulo?' : 'Ativar módulo?',
      mensagem: modulo.ativo
          ? 'Ao desativar, este módulo deixará de ficar disponível para uso nos planos.'
          : 'Ao ativar, o módulo voltará a ficar disponível para uso nos planos.',
      textoConfirmar: modulo.ativo ? 'Sim, desativar' : 'Sim, ativar',
    );
    if (!confirmou || !mounted) return;
    await ModulosConfigService.toggleAtivo(modulo.id, !modulo.ativo);
    if (mounted)
      _exibirSnack(modulo.ativo ? 'Módulo desativado.' : 'Módulo ativado.');
  }

  Future<void> _confirmarExcluirModulo(ModuloConfigModel modulo) async {
    final confirmou = await _confirmarAcao(
      context: context,
      icone: Icons.delete_outline_rounded,
      corIcone: _vermelhoStatus,
      titulo: 'Excluir módulo?',
      mensagem:
          'Tem certeza que deseja excluir "${modulo.nome}" permanentemente? Esta ação não pode ser desfeita.',
      textoConfirmar: 'Sim, excluir',
    );
    if (!confirmou || !mounted) return;
    await ModulosConfigService.excluir(modulo.id);
    if (mounted) _exibirSnack('Módulo "${modulo.nome}" excluído.');
  }

  // ─── SEÇÃO CONFIGURAÇÕES DE COBRANÇAS ─────────────────────
  Widget _buildSecaoConfiguracoesCobrancas() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildBillingHeader(),
        const SizedBox(height: 24),
        StreamBuilder<BillingSettings?>(
          stream: BillingSettingsService.stream(),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(48),
                  child: CircularProgressIndicator(color: _roxoPrimario),
                ),
              );
            }
            if (snap.hasError) {
              return _buildErroCard(snap.error.toString());
            }
            final settings = snap.data ?? const BillingSettings();
            return _buildBillingContent(settings);
          },
        ),
      ],
    );
  }

  Widget _buildBillingHeader() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [_roxoPrimario, _roxoClaro],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: _roxoPrimario.withValues(alpha: 0.25),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.receipt_long_rounded,
              color: Colors.white,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Configurações de Cobranças',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Configure regras automáticas de cobrança, envio de e-mails e notificações para lojistas.',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    color: Colors.white.withValues(alpha: 0.85),
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── Billing Content ───────────────────────────────────────
  Widget _buildBillingContent(BillingSettings settings) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. Cobrança Automática
        _buildAutoCobrancaCard(settings),
        const SizedBox(height: 20),

        // 2. Pagamento Confirmado
        _buildPagamentoConfirmadoCard(settings),
        const SizedBox(height: 20),

        // 3. Cobrança em Atraso
        _buildAtrasoCard(settings),
        const SizedBox(height: 20),

        // 4. Templates de E-mail
        _buildTemplatesCard(settings),
        const SizedBox(height: 20),

        // 5. Botão Salvar + Gerar agora
        _buildBillingActions(settings),
      ],
    );
  }

  // ─── Card: Cobrança Automática ────────────────────────────
  Widget _buildAutoCobrancaCard(BillingSettings settings) {
    return _SurfaceCard(
      titulo: 'Cobrança Automática',
      icone: Icons.schedule_rounded,
      corIcone: _roxoPrimario,
      children: [
        _SwitchTile(
          titulo: 'Ativar cobrança automática',
          descricao: 'Gerar cobranças automaticamente no dia configurado.',
          valor: settings.autoCobrancaAtivo,
          onChanged: (v) async {
            await _atualizar(settings.copyWith(autoCobrancaAtivo: v), tituloConfiguracao: 'Cobrança automática');
          },
        ),
        const _DividerCard(),
        _buildPlanosDropdown(settings),
        const _DividerCard(),
        _buildDiaGeracao(settings),
        const _DividerCard(),
        _buildDiasAntesVencimento(settings),
        const _DividerCard(),
        _SwitchTile(
          titulo: 'Enviar cobrança automaticamente para o e-mail do lojista',
          descricao: 'O e-mail será enviado de ${settings.remetente}.',
          valor: settings.autoEnviarEmail,
          onChanged: (v) async {
            await _atualizar(settings.copyWith(autoEnviarEmail: v), tituloConfiguracao: 'Envio automático de e-mail');
          },
        ),
      ],
    );
  }

  Widget _buildPlanosDropdown(BillingSettings settings) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _Label('Plano / Módulo vinculado'),
          const SizedBox(height: 8),
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('assinaturas_planos')
                .orderBy('nome')
                .snapshots(),
            builder: (context, snap) {
              // ── Monta lista de planos disponíveis (não selecionados) ──
              final todosPlanos = snap.data?.docs ?? [];
              final planosDisponiveis = todosPlanos.where((doc) {
                if (settings.allPlans) return false;
                return !settings.selectedPlanIds.contains(doc.id);
              }).toList();

              // ── Dropdown para adicionar planos ──────────────────
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Dropdown
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      border: Border.all(color: _bordaInput),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: null,
                        hint: Text(
                          settings.allPlans
                              ? 'Todos os planos/módulos (regra global)'
                              : 'Selecionar plano/módulo para adicionar...',
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 13, color: _textoSecundario),
                        ),
                        isExpanded: true,
                        isDense: true,
                        items: [
                          // Opção "Todos os planos"
                          DropdownMenuItem(
                            value: '__all__',
                            child: Row(
                              children: [
                                Icon(Icons.public_rounded,
                                    size: 16,
                                    color: settings.allPlans
                                        ? _roxoPrimario
                                        : _textoSecundario),
                                const SizedBox(width: 8),
                                Text('Todos os planos/módulos',
                                    style: GoogleFonts.plusJakartaSans(
                                        fontSize: 13,
                                        fontWeight: settings.allPlans
                                            ? FontWeight.w700
                                            : FontWeight.w500,
                                        color: settings.allPlans
                                            ? _roxoPrimario
                                            : _textoPrimario)),
                                if (settings.allPlans)
                                  Padding(
                                    padding: const EdgeInsets.only(left: 6),
                                    child: Icon(Icons.check_rounded,
                                        size: 16, color: _roxoPrimario),
                                  ),
                              ],
                            ),
                          ),
                          // Divisor visual
                          if (todosPlanos.isNotEmpty)
                            DropdownMenuItem(
                              enabled: false,
                              child: Divider(height: 1, color: _bordaInput),
                            ),
                          // Planos disponíveis para adicionar
                          ...planosDisponiveis.map((doc) {
                            final d = doc.data() as Map<String, dynamic>;
                            final nome = d['nome'] as String? ?? doc.id;
                            final valor =
                                (d['valor'] as num?)?.toDouble() ?? 0;
                            final ativo = d['ativo'] as bool? ?? true;
                            final fmt = NumberFormat.currency(
                                locale: 'pt_BR', symbol: 'R\$');
                            return DropdownMenuItem(
                              value: doc.id,
                              child: Row(
                                children: [
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: ativo
                                          ? const Color(0xFF16A34A)
                                          : const Color(0xFF9CA3AF),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      nome,
                                      style: GoogleFonts.plusJakartaSans(
                                          fontSize: 13,
                                          color: _textoPrimario),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  Text(
                                    fmt.format(valor),
                                    style: GoogleFonts.plusJakartaSans(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: _roxoPrimario),
                                  ),
                                ],
                              ),
                            );
                          }),
                        ],
                        onChanged: (v) {
                          if (v == '__all__') {
                            // Ativar regra global
                            _salvarSilenciosamente(settings.copyWith(
                              allPlans: true,
                              selectedPlanIds: const [],
                              selectedPlansSnapshot: const [],
                            ));
                          } else if (v != null) {
                            // Adicionar plano específico
                            final doc = todosPlanos.firstWhere(
                                (d) => d.id == v,
                                orElse: () => v as dynamic);
                            final d = doc.data() as Map<String, dynamic>;
                            final novoSnapshot = PlanoVinculadoSnapshot(
                              id: v,
                              nome: d['nome'] as String? ?? v,
                              valor:
                                  (d['valor'] as num?)?.toDouble() ?? 0,
                              ativo: d['ativo'] as bool? ?? true,
                            );
                            _salvarSilenciosamente(settings.copyWith(
                              allPlans: false,
                              selectedPlanIds: [
                                ...settings.selectedPlanIds,
                                v
                              ],
                              selectedPlansSnapshot: [
                                ...settings.selectedPlansSnapshot,
                                novoSnapshot,
                              ],
                            ));
                          }
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // ── Chips dos planos selecionados ────────────────
                  if (!settings.allPlans &&
                      settings.selectedPlansSnapshot.isNotEmpty) ...[
                    Text(
                      'Planos vinculados à cobrança automática',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _textoSecundario),
                    ),
                    const SizedBox(height: 8),
                    ...settings.selectedPlansSnapshot.asMap().entries.map(
                          (entry) => _buildPlanoChip(
                            entry.value,
                            onRemover: () {
                              final novosIds =
                                  settings.selectedPlanIds.toList()
                                    ..remove(entry.value.id);
                              final novosSnapshots =
                                  settings.selectedPlansSnapshot.toList()
                                    ..removeAt(entry.key);
                              _salvarSilenciosamente(settings.copyWith(
                                allPlans: novosIds.isEmpty,
                                selectedPlanIds: novosIds,
                                selectedPlansSnapshot: novosSnapshots,
                              ));
                            },
                          ),
                        ),
                    const SizedBox(height: 8),
                  ],

                  // ── Estado vazio ────────────────────────────────
                  if (settings.allPlans ||
                      settings.selectedPlansSnapshot.isEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: _roxoPrimario.withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: _roxoPrimario.withValues(alpha: 0.08)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline_rounded,
                              size: 16,
                              color: _roxoPrimario.withValues(alpha: 0.6)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              settings.allPlans
                                  ? 'Regra global. A cobrança será aplicada para todos os planos ativos.'
                                  : 'Nenhum plano específico selecionado. A regra será aplicada para todos os planos ativos.',
                              style: GoogleFonts.plusJakartaSans(
                                  fontSize: 12,
                                  color: _textoSecundario,
                                  height: 1.4),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  /// Card/chip premium de um plano vinculado.
  Widget _buildPlanoChip(
    PlanoVinculadoSnapshot plano, {
    required VoidCallback onRemover,
  }) {
    final fmt = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _roxoPrimario.withValues(alpha: 0.12)),
        boxShadow: [
          BoxShadow(
            color: _roxoPrimario.withValues(alpha: 0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Indicador ativo/inativo
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: plano.ativo
                  ? const Color(0xFF16A34A)
                  : const Color(0xFF9CA3AF),
            ),
          ),
          const SizedBox(width: 12),
          // Nome + valor
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  plano.nome,
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: _textoPrimario),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text(
                      fmt.format(plano.valor),
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _roxoPrimario),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: plano.ativo
                            ? const Color(0xFFE8F5E9)
                            : const Color(0xFFF3F4F6),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        plano.ativo ? 'Ativo' : 'Inativo',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: plano.ativo
                              ? const Color(0xFF16A34A)
                              : const Color(0xFF9CA3AF),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Botão Remover
          InkWell(
            onTap: onRemover,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFFDC2626).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.close_rounded,
                  size: 16, color: Color(0xFFDC2626)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDiaGeracao(BillingSettings settings) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Label('Dia do mês para gerar cobrança'),
                const SizedBox(height: 6),
                Text('As cobranças serão geradas automaticamente no dia ${settings.diaGeracao} de cada mês.',
                    style: GoogleFonts.plusJakartaSans(fontSize: 12, color: _textoDescricao)),
              ],
            ),
          ),
          const SizedBox(width: 16),
          SizedBox(
            width: 80,
            child: TextFormField(
              initialValue: settings.diaGeracao.toString(),
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              decoration: _inputDeco('Dia'),
              style: GoogleFonts.plusJakartaSans(fontSize: 15, fontWeight: FontWeight.w700, color: _roxoPrimario),
              onChanged: (v) {
                final dia = int.tryParse(v) ?? 1;
                _salvarSilenciosamente(settings.copyWith(diaGeracao: dia.clamp(1, 28)));
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDiasAntesVencimento(BillingSettings settings) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Label('Dias antes do vencimento para enviar aviso'),
                const SizedBox(height: 6),
                Text('O e-mail será enviado ${settings.diasAntesVencimento} dia(s) antes do vencimento.',
                    style: GoogleFonts.plusJakartaSans(fontSize: 12, color: _textoDescricao)),
              ],
            ),
          ),
          const SizedBox(width: 16),
          SizedBox(
            width: 80,
            child: TextFormField(
              initialValue: settings.diasAntesVencimento.toString(),
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              decoration: _inputDeco('Dias'),
              style: GoogleFonts.plusJakartaSans(fontSize: 15, fontWeight: FontWeight.w700, color: _roxoPrimario),
              onChanged: (v) {
                final d = int.tryParse(v) ?? 5;
                _salvarSilenciosamente(settings.copyWith(diasAntesVencimento: d.clamp(0, 30)));
              },
            ),
          ),
        ],
      ),
    );
  }

  // ─── Card: Pagamento Confirmado ───────────────────────────
  Widget _buildPagamentoConfirmadoCard(BillingSettings settings) {
    return _SurfaceCard(
      titulo: 'Pagamento Confirmado',
      icone: Icons.check_circle_outline_rounded,
      corIcone: _verdeStatus,
      children: [
        _SwitchTile(
          titulo: 'Ativar e-mail de pagamento confirmado',
          descricao: 'Enviar e-mail automático quando a cobrança for marcada como paga.',
          valor: settings.pagamentoConfirmadoAtivo,
          onChanged: (v) async {
            await _atualizar(settings.copyWith(pagamentoConfirmadoAtivo: v), tituloConfiguracao: 'E-mail de pagamento confirmado');
          },
        ),
        if (settings.pagamentoConfirmadoAtivo) ...[
          const _DividerCard(),
          _SwitchTile(
            titulo: 'Enviar e-mail automaticamente',
            descricao: 'Disparar e-mail imediatamente após a confirmação do pagamento.',
            valor: settings.pagamentoConfirmadoEmail,
            onChanged: (v) async {
            await _atualizar(settings.copyWith(pagamentoConfirmadoEmail: v), tituloConfiguracao: 'Envio automático de pagamento');
          },
          ),
          const _DividerCard(),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _verdeFundo,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(Icons.receipt_rounded, size: 20, color: _verdeStatus),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Conteúdo do e-mail: Nome do lojista, plano/módulo, nº da fatura, valor pago, data de pagamento e status "Pagamento confirmado".',
                      style: GoogleFonts.plusJakartaSans(fontSize: 12, color: _textoSecundario, height: 1.45),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  // ─── Card: Cobrança em Atraso ─────────────────────────────
  Widget _buildAtrasoCard(BillingSettings settings) {
    return _SurfaceCard(
      titulo: 'Cobrança em Atraso',
      icone: Icons.warning_amber_rounded,
      corIcone: _vermelhoStatus,
      children: [
        _SwitchTile(
          titulo: 'Ativar aviso de atraso',
          descricao: 'Enviar e-mail automático para cobranças vencidas.',
          valor: settings.atrasoAtivo,
          onChanged: (v) async {
            await _atualizar(settings.copyWith(atrasoAtivo: v), tituloConfiguracao: 'Aviso de cobrança em atraso');
          },
        ),
        if (settings.atrasoAtivo) ...[
          const _DividerCard(),
          _buildAtrasoRegras(settings),
        ],
      ],
    );
  }

  Widget _buildAtrasoRegras(BillingSettings settings) {
    final regras = settings.atrasoRegras.isEmpty
        ? const [AtrasoRegra(diasAposVencimento: 1)]
        : settings.atrasoRegras;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Label('Dias após o vencimento para enviar aviso'),
          const SizedBox(height: 12),
          ...regras.map((regra) {
            final idx = settings.atrasoRegras.indexOf(regra);
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: _vermelhoStatus.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: Text(
                        '${regra.diasAposVencimento}d',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: _vermelhoStatus,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Aviso com ${regra.diasAposVencimento} dia(s) de atraso',
                      style: GoogleFonts.plusJakartaSans(fontSize: 13, color: _textoPrimario),
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      regra.ativo ? Icons.visibility_rounded : Icons.visibility_off_rounded,
                      size: 18,
                      color: regra.ativo ? _roxoPrimario : _cinzaStatus,
                    ),
                    tooltip: regra.ativo ? 'Desativar regra' : 'Ativar regra',
                    onPressed: () {
                      final novas = settings.atrasoRegras.toList();
                      novas[idx] = AtrasoRegra(
                        diasAposVencimento: regra.diasAposVencimento,
                        ativo: !regra.ativo,
                      );
                      _salvarSilenciosamente(settings.copyWith(atrasoRegras: novas));
                    },
                    visualDensity: VisualDensity.compact,
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline_rounded, size: 18, color: _vermelhoStatus),
                    tooltip: 'Remover regra',
                    onPressed: () {
                      final novas = settings.atrasoRegras.toList()
                        ..removeAt(idx);
                      _salvarSilenciosamente(settings.copyWith(atrasoRegras: novas));
                    },
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: 8),
          OutlinedButton.icon(
              onPressed: () => _adicionarRegraAtraso(settings),
              icon: const Icon(Icons.add_rounded, size: 16),
              label: Text('Adicionar aviso',
                  style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w600)),
              style: OutlinedButton.styleFrom(
                foregroundColor: _roxoPrimario,
                side: BorderSide(color: _roxoPrimario.withValues(alpha: 0.3)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                minimumSize: const Size(0, 36),
              ),
            ),
        ],
      ),
    );
  }

  void _adicionarRegraAtraso(BillingSettings settings) async {
    final novosDias = <int>{};
    for (final r in settings.atrasoRegras) {
      novosDias.add(r.diasAposVencimento);
    }
    // Sugerir próximo número não utilizado na sequência padrão
    final sugestoes = [1, 3, 7, 14, 21, 30];
    int sugerido = 1;
    for (final s in sugestoes) {
      if (!novosDias.contains(s)) {
        sugerido = s;
        break;
      }
    }

    final ctrl = TextEditingController(text: sugerido.toString());
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Novo aviso de atraso',
            style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w700, color: _roxoPrimario)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Dias após o vencimento:',
                style: GoogleFonts.plusJakartaSans(fontSize: 13, color: _textoSecundario)),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w700, color: _roxoPrimario),
              decoration: InputDecoration(
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                hintText: 'Ex: 5',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancelar',
                style: GoogleFonts.plusJakartaSans(fontSize: 13, color: _textoSecundario)),
          ),
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () {
                final v = int.tryParse(ctrl.text);
                if (v != null && v > 0) {
                  Navigator.pop(ctx, v);
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [_roxoPrimario, _roxoClaro]),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text('Adicionar',
                    style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white)),
              ),
            ),
          ),
        ],
      ),
    );

    if (result != null && result > 0) {
      final novas = settings.atrasoRegras.toList()
        ..add(AtrasoRegra(diasAposVencimento: result));
      _salvarSilenciosamente(settings.copyWith(atrasoRegras: novas));
    }
  }

  // ─── Card: Templates de E-mail ────────────────────────────
  Widget _buildTemplatesCard(BillingSettings settings) {
    return _SurfaceCard(
      titulo: 'Templates de E-mail',
      icone: Icons.email_rounded,
      corIcone: _laranjaPrimario,
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 16),
          child: Text(
            'Os templates abaixo são usados nos envios automáticos e manuais de cobranças. '
            'Todos os e-mails utilizam o remetente naoresponder@dipertin.com.br.',
            style: TextStyle(fontSize: 13, color: _textoSecundario, height: 1.45),
          ),
        ),
        _buildTemplateLinha(
          icone: Icons.receipt_long_rounded,
          cor: _roxoPrimario,
          titulo: 'Cobrança enviada',
          descricao: 'Template para envio de fatura ao lojista.',
          ativo: settings.cobrancaTemplateAtivo,
          onToggle: (v) async {
            await _atualizar(settings.copyWith(cobrancaTemplateAtivo: v), tituloConfiguracao: 'Template de cobrança');
          },
        ),
        const SizedBox(height: 8),
        _buildTemplateLinha(
          icone: Icons.check_circle_rounded,
          cor: _verdeStatus,
          titulo: 'Pagamento confirmado',
          descricao: 'Template para confirmação de pagamento recebido.',
          ativo: settings.pagamentoTemplateAtivo,
          onToggle: (v) async {
            await _atualizar(settings.copyWith(pagamentoTemplateAtivo: v), tituloConfiguracao: 'Template de pagamento');
          },
        ),
        const SizedBox(height: 8),
        _buildTemplateLinha(
          icone: Icons.warning_rounded,
          cor: _vermelhoStatus,
          titulo: 'Cobrança em atraso',
          descricao: 'Template para aviso de fatura vencida.',
          ativo: settings.atrasoTemplateAtivo,
          onToggle: (v) async {
            await _atualizar(settings.copyWith(atrasoTemplateAtivo: v), tituloConfiguracao: 'Template de atraso');
          },
        ),
      ],
    );
  }

  Widget _buildTemplateLinha({
    required IconData icone,
    required Color cor,
    required String titulo,
    required String descricao,
    required bool ativo,
    required ValueChanged<bool> onToggle,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: ativo ? _lilasFundo : _cinzaFundo,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ativo ? cor.withValues(alpha: 0.2) : _bordaInput),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: cor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icone, size: 20, color: cor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titulo,
                    style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w700, color: _textoPrimario)),
                const SizedBox(height: 2),
                Text(descricao,
                    style: GoogleFonts.plusJakartaSans(fontSize: 12, color: _textoDescricao)),
              ],
            ),
          ),
          Switch.adaptive(
            value: ativo,
            activeColor: _roxoPrimario,
            onChanged: onToggle,
          ),
        ],
      ),
    );
  }

  // ─── Botões de ação ───────────────────────────────────────
  Widget _buildBillingActions(BillingSettings settings) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: _roxoPrimario.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Ações',
              style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w800, color: _textoPrimario)),
          const SizedBox(height: 16),
          // Botão Salvar com gradiente
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => _salvarConfiguracoes(settings),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [_roxoPrimario, _roxoClaro]),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: _roxoPrimario.withValues(alpha: 0.25),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Text('Salvar configurações',
                    style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Salva configurações e exibe modal premium de resultado.
  Future<void> _salvarConfiguracoes(BillingSettings settings) async {
    PremiumLoadingDialog.mostrar(context, mensagem: 'Salvando configurações...');
    try {
      await BillingSettingsService.salvar(settings);
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
      if (mounted) {
        PremiumResultDialog.mostrarSucesso(
          context,
          titulo: 'Configurações salvas!',
          mensagem: 'As configurações de cobranças foram salvas com sucesso.',
        );
      }
    } catch (e) {
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
      if (mounted) {
        PremiumResultDialog.mostrarErro(
          context,
          titulo: 'Erro ao salvar',
          mensagem: e is CallableHttpException
              ? mensagemCallableHttpException(e)
              : 'Falha ao salvar configurações: $e',
        );
      }
    }
  }

  /// Salva silenciosamente sem confirmação ou modal (para campos de texto, dropdowns, etc.).
  /// Usa escrita direta no Firestore (não via Cloud Function) para evitar latência e falhas
  /// de serialização HTTP. As regras de segurança já permitem escrita para staff.
  Future<void> _salvarSilenciosamente(BillingSettings settings) async {
    try {
      final dados = settings.toJson();
      dados['updated_at'] = FieldValue.serverTimestamp();
      await FirebaseFirestore.instance
          .collection('billing_settings')
          .doc('global')
          .set(dados, SetOptions(merge: true));
    } catch (_) {
      // Falhas silenciosas em auto-save de campos auxiliares — sem feedback visual
    }
  }

  /// Confirma com modal premium, salva e exibe resultado.
  Future<void> _atualizar(BillingSettings settings, {required String tituloConfiguracao}) async {
    final confirmou = await PremiumConfirmDialog.mostrar(
      context,
      tituloConfiguracao: tituloConfiguracao,
    );
    if (!confirmou) return;
    if (!mounted) return;

    PremiumLoadingDialog.mostrar(context, mensagem: 'Salvando configurações...');
    try {
      await BillingSettingsService.salvar(settings);
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
      if (mounted) {
        PremiumResultDialog.mostrarSucesso(
          context,
          titulo: 'Configurações salvas!',
          mensagem: 'As configurações de cobranças foram salvas com sucesso.',
        );
      }
    } catch (e) {
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
      if (mounted) {
        PremiumResultDialog.mostrarErro(
          context,
          titulo: 'Erro ao salvar',
          mensagem: e is CallableHttpException
              ? mensagemCallableHttpException(e)
              : 'Falha ao salvar configurações: $e',
        );
      }
    }
  }

  // ─── Modal Premium (substituído por premium_dialogs.dart) ──
}

// ============================================================
// SPARKLINE
// ============================================================
class _Sparkline extends StatelessWidget {
  final List<double> dados;
  final Color cor;
  const _Sparkline({required this.dados, required this.cor});

  @override
  Widget build(BuildContext context) {
    if (dados.isEmpty) return const SizedBox(height: 28);
    final min = dados.reduce(math.min);
    final max = dados.reduce(math.max);
    final range = (max - min).clamp(0.1, double.infinity);
    return SizedBox(
      height: 28,
      child: CustomPaint(painter: _SparklinePainter(dados, cor, min, range)),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  final List<double> dados;
  final Color cor;
  final double min;
  final double range;
  _SparklinePainter(this.dados, this.cor, this.min, this.range);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = cor.withValues(alpha: 0.3)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [cor.withValues(alpha: 0.15), cor.withValues(alpha: 0.0)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    if (dados.length < 2) return;
    final stepX = size.width / (dados.length - 1);
    final path = Path();
    final fillPath = Path();
    for (int i = 0; i < dados.length; i++) {
      final x = i * stepX;
      final y =
          size.height - ((dados[i] - min) / range) * (size.height - 4) - 2;
      if (i == 0) {
        path.moveTo(x, y);
        fillPath.moveTo(x, size.height);
        fillPath.lineTo(x, y);
      } else {
        path.lineTo(x, y);
        fillPath.lineTo(x, y);
      }
    }
    fillPath.lineTo(size.width, size.height);
    fillPath.close();
    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_SparklinePainter old) => old.dados != dados;
}

// ============================================================
// _ModuloSummaryCard
// ============================================================
class _ModuloSummaryCard extends StatelessWidget {
  final IconData icone;
  final Color cor;
  final String titulo;
  final String valor;
  final String variacao;
  final List<double> sparklineDados;
  const _ModuloSummaryCard({
    required this.icone,
    required this.cor,
    required this.titulo,
    required this.valor,
    required this.variacao,
    this.sparklineDados = const [],
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOut,
      builder: (context, anim, _) => Transform.translate(
        offset: Offset(0, 20 * (1 - anim)),
        child: Opacity(
          opacity: anim,
          child: Container(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: cor.withValues(alpha: 0.08),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
                BoxShadow(
                  color: cor.withValues(alpha: 0.04),
                  blurRadius: 4,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [cor, cor.withValues(alpha: 0.7)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: cor.withValues(alpha: 0.25),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Icon(icone, color: Colors.white, size: 20),
                    ),
                    const Spacer(),
                    SizedBox(
                      width: 56,
                      height: 28,
                      child: _Sparkline(dados: sparklineDados, cor: cor),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  titulo,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: _textoSecundario,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  valor,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: _textoPrimario,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  variacao,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 10,
                    color: _textoDescricao,
                    height: 1.2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================
// LINHA COMPACTA DE MÓDULO
// ============================================================
class _ModuloLinha extends StatefulWidget {
  final ModuloConfigModel modulo;
  final bool par;
  final VoidCallback onVisualizar,
      onEditar,
      onDuplicar,
      onToggleStatus,
      onExcluir;
  const _ModuloLinha({
    required this.modulo,
    required this.par,
    required this.onVisualizar,
    required this.onEditar,
    required this.onDuplicar,
    required this.onToggleStatus,
    required this.onExcluir,
  });
  @override
  State<_ModuloLinha> createState() => _ModuloLinhaState();
}

class _ModuloLinhaState extends State<_ModuloLinha> {
  bool _hover = false;
  final _fmtData = DateFormat('dd/MM/yyyy', 'pt_BR');

  @override
  Widget build(BuildContext context) {
    final m = widget.modulo;
    final cor = _corModulo(m.nome);

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          color: _hover
              ? _lilasFundo
              : (widget.par ? _fundoPagina : Colors.white),
          border: Border(
            bottom: BorderSide(color: _bordaCard, width: 1),
            left: _hover
                ? const BorderSide(color: _roxoPrimario, width: 3)
                : BorderSide(color: Colors.transparent, width: 3),
          ),
        ),
        child: InkWell(
          onTap: widget.onVisualizar,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compacto = constraints.maxWidth < 800;
                if (compacto) {
                  return _buildLinhaCompacta(m, cor);
                }
                return _buildLinhaCompleta(m, cor);
              },
            ),
          ),
        ),
      ),
    );
  }

  /// Linha completa para desktop.
  Widget _buildLinhaCompleta(ModuloConfigModel m, Color cor) {
    return Row(
      children: [
        // Ícone + Nome + Código
        SizedBox(
          width: 220,
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [cor, cor.withValues(alpha: 0.7)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: cor.withValues(alpha: 0.2),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Icon(
                  _iconeModulo(m.icone),
                  color: Colors.white,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      m.nome,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: _textoPrimario,
                        height: 1.2,
                      ),
                    ),
                    Text(
                      m.codigo,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11,
                        color: _textoSecundario,
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // Descrição
        SizedBox(
          width: 200,
          child: Text(
            m.descricao.isNotEmpty ? m.descricao : '—',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              color: _textoDescricao,
              height: 1.3,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),

        const SizedBox(width: 16),

        // Badges: Status + Contratável (auto-width)
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _badge(
              m.ativo ? 'Ativo' : 'Inativo',
              m.ativo ? _verdeStatus : _cinzaStatus,
              m.ativo ? _verdeFundo : _cinzaFundo,
            ),
            const SizedBox(width: 8),
            _badge(
              m.contratavel ? 'Contratável' : 'Não contratável',
              m.contratavel ? _verdeStatus : _cinzaStatus,
              m.contratavel ? _verdeFundo : _cinzaFundo,
            ),
          ],
        ),

        // Lojas utilizando
        SizedBox(
          width: 80,
          child: Text(
            '—',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: _textoSecundario,
            ),
          ),
        ),

        const Spacer(),

        // Data atualização
        SizedBox(
          width: 90,
          child: Text(
            m.updatedAt != null ? _fmtData.format(m.updatedAt!.toDate()) : '—',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11,
              color: _textoSecundario,
            ),
          ),
        ),

        const SizedBox(width: 8),

        // Botão Editar
        SizedBox(
          height: 32,
          child: Material(
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              onTap: widget.onEditar,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [_roxoPrimario, _roxoClaro],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: _roxoPrimario.withValues(alpha: 0.15),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                alignment: Alignment.center,
                child: Text(
                  'Editar',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ),

        const SizedBox(width: 4),

        // Menu três pontos
        _buildMenuTresPontos(),
      ],
    );
  }

  /// Linha compacta para mobile/tablet.
  Widget _buildLinhaCompacta(ModuloConfigModel m, Color cor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [cor, cor.withValues(alpha: 0.7)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: cor.withValues(alpha: 0.2),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: Icon(_iconeModulo(m.icone), color: Colors.white, size: 16),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                m.nome,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: _textoPrimario,
                ),
              ),
            ),
            const SizedBox(width: 6),
            _badge(
              m.ativo ? 'Ativo' : 'Inativo',
              m.ativo ? _verdeStatus : _cinzaStatus,
              m.ativo ? _verdeFundo : _cinzaFundo,
            ),
            const SizedBox(width: 6),
            _buildMenuTresPontos(),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Text(
              '${m.codigo} · ',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 11,
                color: _textoSecundario,
              ),
            ),
            if (m.descricao.isNotEmpty)
              Expanded(
                child: Text(
                  m.descricao,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    color: _textoDescricao,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            const SizedBox(width: 8),
            SizedBox(
              height: 28,
              child: Material(
                borderRadius: BorderRadius.circular(6),
                child: InkWell(
                  onTap: widget.onEditar,
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [_roxoPrimario, _roxoClaro],
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                      ),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      'Editar',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _badge(String texto, Color cor, Color fundo) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: fundo,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: cor.withValues(alpha: 0.2)),
      ),
      child: Text(
        texto,
        style: GoogleFonts.plusJakartaSans(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: cor,
          height: 1.2,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _buildMenuTresPontos() {
    final m = widget.modulo;
    return PopupMenuButton<String>(
      onSelected: (value) {
        switch (value) {
          case 'visualizar':
            widget.onVisualizar();
            break;
          case 'editar':
            widget.onEditar();
            break;
          case 'duplicar':
            widget.onDuplicar();
            break;
          case 'toggle':
            widget.onToggleStatus();
            break;
          case 'excluir':
            widget.onExcluir();
            break;
        }
      },
      offset: const Offset(0, 36),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 6,
      color: Colors.white,
      surfaceTintColor: Colors.white,
      padding: EdgeInsets.zero,
      icon: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: _hover ? _roxoPrimario.withValues(alpha: 0.3) : _bordaCard,
          ),
        ),
        child: Icon(
          Icons.more_horiz_rounded,
          size: 18,
          color: _hover ? _roxoPrimario : _textoSecundario,
        ),
      ),
      itemBuilder: (_) => [
        _popItem(
          Icons.visibility_outlined,
          _roxoCard,
          'Visualizar',
          'Ver detalhes completos',
          'visualizar',
        ),
        const PopupMenuDivider(height: 1),
        _popItem(
          Icons.edit_outlined,
          _roxoCard,
          'Editar',
          'Alterar informações do módulo',
          'editar',
        ),
        const PopupMenuDivider(height: 1),
        _popItem(
          Icons.copy_rounded,
          const Color(0xFF7C3AED),
          'Duplicar',
          'Criar cópia como inativo',
          'duplicar',
        ),
        const PopupMenuDivider(height: 1),
        _popItem(
          m.ativo ? Icons.block_flipped : Icons.check_circle_outline,
          m.ativo ? _laranjaStatus : _verdeStatus,
          m.ativo ? 'Desativar' : 'Ativar',
          m.ativo ? 'Desativar este módulo' : 'Reativar este módulo',
          'toggle',
        ),
        const PopupMenuDivider(height: 1),
        _popItem(
          Icons.delete_outline_rounded,
          _vermelhoStatus,
          'Excluir',
          'Remover permanentemente',
          'excluir',
        ),
      ],
    );
  }

  PopupMenuItem<String> _popItem(
    IconData icone,
    Color cor,
    String titulo,
    String desc,
    String val,
  ) {
    return PopupMenuItem(
      value: val,
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: cor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icone, size: 15, color: cor),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                titulo,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: _textoPrimario,
                ),
              ),
              Text(
                desc,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 10,
                  color: _textoSecundario,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ============================================================
// WIDGETS REUTILIZÁVEIS
// ============================================================
class _SecaoCard extends StatelessWidget {
  final String titulo, descricao;
  final Widget child;
  final Widget? action;
  const _SecaoCard({
    required this.titulo,
    required this.descricao,
    required this.child,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: _roxoPrimario.withValues(alpha: 0.06),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
          BoxShadow(
            color: _roxoPrimario.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 4,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [_roxoPrimario, _roxoClaro, _laranjaPrimario],
                stops: [0.0, 0.5, 1.0],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 22, 24, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 3,
                  height: 36,
                  margin: const EdgeInsets.only(top: 2, right: 14),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [_roxoPrimario, _laranjaPrimario],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        titulo,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: _textoPrimario,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        descricao,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          color: _textoSecundario,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                if (action != null) ...[const SizedBox(width: 16), action!],
              ],
            ),
          ),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: child,
          ),
        ],
      ),
    );
  }
}

// ============================================================
// DIÁLOGO DE CONFIRMAÇÃO PREMIUM
// ============================================================
Future<bool> _confirmarAcao({
  required BuildContext context,
  required IconData icone,
  required Color corIcone,
  required String titulo,
  required String mensagem,
  required String textoConfirmar,
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black.withValues(alpha: 0.5),
    useRootNavigator: true,
    builder: (ctx) => Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 80),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Container(
        width: 400,
        padding: const EdgeInsets.fromLTRB(32, 32, 32, 24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: corIcone.withValues(alpha: 0.12),
              ),
              child: Icon(icone, size: 36, color: corIcone),
            ),
            const SizedBox(height: 20),
            Text(
              titulo,
              textAlign: TextAlign.center,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: _textoPrimario,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              mensagem,
              textAlign: TextAlign.center,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 14,
                color: _textoSecundario,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 28),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 46,
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(ctx).pop(false),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: _bordaCard),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        'Cancelar',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: _textoSecundario,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SizedBox(
                    height: 46,
                    child: Material(
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        onTap: () => Navigator.of(ctx).pop(true),
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [
                                Color(0xFF7D20E8),
                                Color(0xFFD62BDB),
                                Color(0xFFFF7A17),
                              ],
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                            ),
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(
                                  0xFF7D20E8,
                                ).withValues(alpha: 0.3),
                                blurRadius: 10,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            textoConfirmar,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
  return result ?? false;
}

/// Diálogo de sucesso premium (após ação concluída).
Future<void> _sucessoDialog({
  required BuildContext context,
  required String titulo,
  required String subtitulo,
  String? destaque,
}) async {
  await showDialog(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black.withValues(alpha: 0.5),
    useRootNavigator: true,
    builder: (ctx) => Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 80),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Container(
        width: 400,
        padding: const EdgeInsets.fromLTRB(32, 32, 32, 24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [Color(0xFF7D20E8), Color(0xFFD62BDB)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF7D20E8).withValues(alpha: 0.35),
                    blurRadius: 20,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Icon(
                Icons.check_rounded,
                size: 38,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 22),
            Text(
              titulo,
              textAlign: TextAlign.center,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: _textoPrimario,
              ),
            ),
            if (destaque != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: _lilasFundo,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  destaque,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: _roxoCard,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 10),
            Text(
              subtitulo,
              textAlign: TextAlign.center,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                color: _textoSecundario,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 46,
              child: Material(
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  onTap: () => Navigator.of(ctx).pop(),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [
                          Color(0xFF7D20E8),
                          Color(0xFFD62BDB),
                          Color(0xFFFF7A17),
                        ],
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                      ),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF7D20E8).withValues(alpha: 0.3),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      'OK',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

// ============================================================
// MODAL — NOVO MÓDULO (completo)
// ============================================================
class _NovoModuloFullDialog extends StatefulWidget {
  const _NovoModuloFullDialog();
  @override
  State<_NovoModuloFullDialog> createState() => _NovoModuloFullDialogState();
}

class _NovoModuloFullDialogState extends State<_NovoModuloFullDialog> {
  final _nomeCtrl = TextEditingController();
  final _codigoCtrl = TextEditingController();
  final _descricaoCtrl = TextEditingController();
  final _observacoesCtrl = TextEditingController();
  final _ordemCtrl = TextEditingController(text: '0');
  String _iconeSelecionado = 'widgets';
  bool _statusAtivo = true;
  bool _permitirContratacao = true;
  bool _salvando = false;

  final _iconesDisponiveis = [
    'widgets',
    'dashboard',
    'store',
    'people',
    'payment',
    'receipt',
    'assessment',
    'inventory',
    'notifications',
    'chat',
    'settings',
    'security',
    'analytics',
    'sell',
    'qr_code',
    'description',
  ];

  @override
  void dispose() {
    _nomeCtrl.dispose();
    _codigoCtrl.dispose();
    _descricaoCtrl.dispose();
    _observacoesCtrl.dispose();
    _ordemCtrl.dispose();
    super.dispose();
  }

  Future<void> _salvar() async {
    if (_nomeCtrl.text.trim().isEmpty || _codigoCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Preencha nome e código interno.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    setState(() => _salvando = true);
    try {
      await ModulosConfigService.criar(
        nome: _nomeCtrl.text.trim(),
        codigo: _codigoCtrl.text.trim().toUpperCase(),
        descricao: _descricaoCtrl.text.trim(),
        ativo: _statusAtivo,
        contratavel: _permitirContratacao,
        icone: _iconeSelecionado,
      );
      if (mounted) {
        await _sucessoDialog(
          context: context,
          titulo: 'Módulo criado!',
          subtitulo:
              'O módulo já está disponível para ser vinculado a planos de assinatura.',
          destaque: _nomeCtrl.text.trim(),
        );
        if (mounted) Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _salvando = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao salvar: $e'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 40),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: 620,
        constraints: const BoxConstraints(maxHeight: 700),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          children: [
            _dialogHeader(
              'Novo módulo',
              'Cadastre um novo módulo para ser vinculado a planos.',
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _campoForm(
                            'Nome do módulo *',
                            _nomeCtrl,
                            'Ex.: PDV Completo',
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _campoForm(
                            'Código interno *',
                            _codigoCtrl,
                            'Ex.: MD-001',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _campoForm(
                      'Descrição',
                      _descricaoCtrl,
                      'Breve descrição do módulo',
                      maxLines: 2,
                    ),
                    const SizedBox(height: 16),

                    // Ícone
                    Text(
                      'Ícone do módulo',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _textoSecundario,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: _fundoPagina,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: _bordaInput),
                      ),
                      child: Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: _iconesDisponiveis.map((ic) {
                          final sel = _iconeSelecionado == ic;
                          return GestureDetector(
                            onTap: () => setState(() => _iconeSelecionado = ic),
                            child: Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: sel ? _roxoPrimario : Colors.white,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: sel ? _roxoPrimario : _bordaCard,
                                ),
                              ),
                              child: Icon(
                                _iconeModulo(ic),
                                size: 22,
                                color: sel ? Colors.white : _textoSecundario,
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Switches
                    Row(
                      children: [
                        Expanded(
                          child: _switchForm(
                            'Ativo',
                            _statusAtivo,
                            (v) => setState(() => _statusAtivo = v),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _switchForm(
                            'Contratável',
                            _permitirContratacao,
                            (v) => setState(() => _permitirContratacao = v),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    Row(
                      children: [
                        Expanded(
                          child: _campoForm(
                            'Ordem de exibição',
                            _ordemCtrl,
                            '0',
                            keyboardType: TextInputType.number,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Cor do módulo',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: _textoSecundario,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Container(
                                height: 44,
                                decoration: BoxDecoration(
                                  color: _corModulo(
                                    _nomeCtrl.text.isNotEmpty
                                        ? _nomeCtrl.text
                                        : 'padrao',
                                  ).withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: _bordaInput),
                                ),
                                alignment: Alignment.center,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Container(
                                      width: 20,
                                      height: 20,
                                      decoration: BoxDecoration(
                                        color: _corModulo(
                                          _nomeCtrl.text.isNotEmpty
                                              ? _nomeCtrl.text
                                              : 'padrao',
                                        ),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Automática',
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 12,
                                        color: _textoSecundario,
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
                    const SizedBox(height: 16),
                    _campoForm(
                      'Observações',
                      _observacoesCtrl,
                      'Informações adicionais (uso interno)',
                      maxLines: 2,
                    ),
                    const SizedBox(height: 28),
                    _botaoSalvar(),
                    const SizedBox(height: 4),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dialogHeader(String titulo, String subtitulo) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFEEEAF6))),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titulo,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: _textoPrimario,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitulo,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    color: _textoSecundario,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded, color: _textoSecundario),
          ),
        ],
      ),
    );
  }

  Widget _campoForm(
    String label,
    TextEditingController ctrl,
    String dica, {
    int? maxLines,
    TextInputType? keyboardType,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: _textoSecundario,
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: ctrl,
          maxLines: maxLines ?? 1,
          keyboardType: keyboardType,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 14,
            color: _textoPrimario,
          ),
          decoration: InputDecoration(
            hintText: dica,
            hintStyle: GoogleFonts.plusJakartaSans(
              fontSize: 14,
              color: _textoSecundario.withValues(alpha: 0.6),
            ),
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(
              vertical: 12,
              horizontal: 14,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: _bordaInput),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: _bordaInput),
            ),
          ),
        ),
      ],
    );
  }

  Widget _switchForm(String label, bool valor, ValueChanged<bool> onChanged) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _bordaInput),
      ),
      child: Row(
        children: [
          Text(
            label,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              color: _textoPrimario,
            ),
          ),
          const Spacer(),
          Switch.adaptive(
            value: valor,
            onChanged: onChanged,
            activeTrackColor: _roxoBtn,
            activeThumbColor: Colors.white,
          ),
        ],
      ),
    );
  }

  Widget _botaoSalvar() {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: Material(
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: _salvando ? null : _salvar,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [
                  Color(0xFF7D20E8),
                  Color(0xFFD62BDB),
                  Color(0xFFFF7A17),
                ],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF7D20E8).withValues(alpha: 0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            alignment: Alignment.center,
            child: _salvando
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.rocket_launch_outlined,
                        size: 18,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Salvar módulo',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

// ============================================================
// MODAL — EDITAR MÓDULO (completo)
// ============================================================
class _EditarModuloFullDialog extends StatefulWidget {
  final ModuloConfigModel modulo;
  const _EditarModuloFullDialog({required this.modulo});
  @override
  State<_EditarModuloFullDialog> createState() =>
      _EditarModuloFullDialogState();
}

class _EditarModuloFullDialogState extends State<_EditarModuloFullDialog> {
  late final TextEditingController _nomeCtrl,
      _codigoCtrl,
      _descricaoCtrl,
      _observacoesCtrl,
      _ordemCtrl;
  late String _iconeSelecionado;
  late bool _statusAtivo, _permitirContratacao;
  bool _salvando = false;

  final _iconesDisponiveis = [
    'widgets',
    'dashboard',
    'store',
    'people',
    'payment',
    'receipt',
    'assessment',
    'inventory',
    'notifications',
    'chat',
    'settings',
    'security',
    'analytics',
    'sell',
    'qr_code',
    'description',
  ];

  @override
  void initState() {
    super.initState();
    final m = widget.modulo;
    _nomeCtrl = TextEditingController(text: m.nome);
    _codigoCtrl = TextEditingController(text: m.codigo);
    _descricaoCtrl = TextEditingController(text: m.descricao);
    _observacoesCtrl = TextEditingController();
    _ordemCtrl = TextEditingController(text: '0');
    _iconeSelecionado = m.icone;
    _statusAtivo = m.ativo;
    _permitirContratacao = m.contratavel;
  }

  @override
  void dispose() {
    _nomeCtrl.dispose();
    _codigoCtrl.dispose();
    _descricaoCtrl.dispose();
    _observacoesCtrl.dispose();
    _ordemCtrl.dispose();
    super.dispose();
  }

  Future<void> _salvar() async {
    if (_nomeCtrl.text.trim().isEmpty || _codigoCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Preencha nome e código interno.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    setState(() => _salvando = true);
    try {
      await ModulosConfigService.atualizar(
        id: widget.modulo.id,
        nome: _nomeCtrl.text.trim(),
        codigo: _codigoCtrl.text.trim().toUpperCase(),
        descricao: _descricaoCtrl.text.trim(),
        ativo: _statusAtivo,
        contratavel: _permitirContratacao,
        icone: _iconeSelecionado,
      );
      if (mounted) {
        await _sucessoDialog(
          context: context,
          titulo: 'Módulo atualizado!',
          subtitulo: 'As alterações foram salvas com sucesso.',
          destaque: widget.modulo.nome,
        );
        if (mounted) Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _salvando = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao salvar: $e'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 40),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: 620,
        constraints: const BoxConstraints(maxHeight: 700),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Color(0xFFEEEAF6))),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: _lilasFundo,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.edit_outlined,
                      color: _roxoCard,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Editar módulo',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: _textoPrimario,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${widget.modulo.nome} · ${widget.modulo.codigo}',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 13,
                            color: _textoSecundario,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(
                      Icons.close_rounded,
                      color: _textoSecundario,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _campoForm(
                            'Nome do módulo *',
                            _nomeCtrl,
                            'Ex.: PDV Completo',
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _campoForm(
                            'Código interno *',
                            _codigoCtrl,
                            'Ex.: MD-001',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _campoForm(
                      'Descrição',
                      _descricaoCtrl,
                      'Breve descrição do módulo',
                      maxLines: 2,
                    ),
                    const SizedBox(height: 16),

                    // Ícone
                    Text(
                      'Ícone do módulo',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _textoSecundario,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: _fundoPagina,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: _bordaInput),
                      ),
                      child: Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: _iconesDisponiveis.map((ic) {
                          final sel = _iconeSelecionado == ic;
                          return GestureDetector(
                            onTap: () => setState(() => _iconeSelecionado = ic),
                            child: Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: sel ? _roxoPrimario : Colors.white,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: sel ? _roxoPrimario : _bordaCard,
                                ),
                              ),
                              child: Icon(
                                _iconeModulo(ic),
                                size: 22,
                                color: sel ? Colors.white : _textoSecundario,
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 16),

                    Row(
                      children: [
                        Expanded(
                          child: _switchForm(
                            'Ativo',
                            _statusAtivo,
                            (v) => setState(() => _statusAtivo = v),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _switchForm(
                            'Contratável',
                            _permitirContratacao,
                            (v) => setState(() => _permitirContratacao = v),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    Row(
                      children: [
                        Expanded(
                          child: _campoForm(
                            'Ordem de exibição',
                            _ordemCtrl,
                            '0',
                            keyboardType: TextInputType.number,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Cor do módulo',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: _textoSecundario,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Container(
                                height: 44,
                                decoration: BoxDecoration(
                                  color: _corModulo(
                                    _nomeCtrl.text.isNotEmpty
                                        ? _nomeCtrl.text
                                        : 'padrao',
                                  ).withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: _bordaInput),
                                ),
                                alignment: Alignment.center,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Container(
                                      width: 20,
                                      height: 20,
                                      decoration: BoxDecoration(
                                        color: _corModulo(
                                          _nomeCtrl.text.isNotEmpty
                                              ? _nomeCtrl.text
                                              : 'padrao',
                                        ),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Automática',
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 12,
                                        color: _textoSecundario,
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
                    const SizedBox(height: 16),
                    _campoForm(
                      'Observações',
                      _observacoesCtrl,
                      'Informações adicionais (uso interno)',
                      maxLines: 2,
                    ),
                    const SizedBox(height: 28),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: Material(
                        borderRadius: BorderRadius.circular(12),
                        child: InkWell(
                          onTap: _salvando ? null : _salvar,
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [
                                  Color(0xFF7D20E8),
                                  Color(0xFFD62BDB),
                                  Color(0xFFFF7A17),
                                ],
                                begin: Alignment.centerLeft,
                                end: Alignment.centerRight,
                              ),
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(
                                    0xFF7D20E8,
                                  ).withValues(alpha: 0.3),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            alignment: Alignment.center,
                            child: _salvando
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(
                                        Icons.save_outlined,
                                        size: 18,
                                        color: Colors.white,
                                      ),
                                      const SizedBox(width: 10),
                                      Text(
                                        'Salvar alterações',
                                        style: GoogleFonts.plusJakartaSans(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ],
                                  ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _campoForm(
    String label,
    TextEditingController ctrl,
    String dica, {
    int? maxLines,
    TextInputType? keyboardType,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: _textoSecundario,
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: ctrl,
          maxLines: maxLines ?? 1,
          keyboardType: keyboardType,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 14,
            color: _textoPrimario,
          ),
          decoration: InputDecoration(
            hintText: dica,
            hintStyle: GoogleFonts.plusJakartaSans(
              fontSize: 14,
              color: _textoSecundario.withValues(alpha: 0.6),
            ),
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(
              vertical: 12,
              horizontal: 14,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: _bordaInput),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: _bordaInput),
            ),
          ),
        ),
      ],
    );
  }

  Widget _switchForm(String label, bool valor, ValueChanged<bool> onChanged) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _bordaInput),
      ),
      child: Row(
        children: [
          Text(
            label,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              color: _textoPrimario,
            ),
          ),
          const Spacer(),
          Switch.adaptive(
            value: valor,
            onChanged: onChanged,
            activeTrackColor: _roxoBtn,
            activeThumbColor: Colors.white,
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// ENUM _StatusIntegracao
// ═══════════════════════════════════════════════════════════════
enum _StatusIntegracao { configurado, erro, naoConfigurado }

// ============================================================
// MODAL — DETALHES DO MÓDULO
// ============================================================
class _DetalheModuloModal extends StatelessWidget {
  final ModuloConfigModel modulo;
  const _DetalheModuloModal({required this.modulo});

  @override
  Widget build(BuildContext context) {
    final m = modulo;
    final cor = _corModulo(m.nome);
    final fmtData = DateFormat('dd/MM/yyyy \'às\' HH:mm', 'pt_BR');

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 60, vertical: 60),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: 640,
        constraints: const BoxConstraints(maxHeight: 680),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(28, 20, 20, 12),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Color(0xFFEEEAF6))),
              ),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [cor, cor.withValues(alpha: 0.7)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: cor.withValues(alpha: 0.25),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Icon(
                      _iconeModulo(m.icone),
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          m.nome,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: _textoPrimario,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          m.codigo,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 13,
                            color: _textoSecundario,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(
                      Icons.close_rounded,
                      color: _textoSecundario,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Banner de status
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            cor.withValues(alpha: 0.05),
                            cor.withValues(alpha: 0.02),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: cor.withValues(alpha: 0.1)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: m.ativo ? _verdeFundo : _cinzaFundo,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: (m.ativo ? _verdeStatus : _cinzaStatus)
                                    .withValues(alpha: 0.25),
                              ),
                            ),
                            child: Text(
                              m.ativo ? 'Ativo' : 'Inativo',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: m.ativo ? _verdeStatus : _cinzaStatus,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: m.contratavel ? _verdeFundo : _cinzaFundo,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color:
                                    (m.contratavel
                                            ? _verdeStatus
                                            : _cinzaStatus)
                                        .withValues(alpha: 0.25),
                              ),
                            ),
                            child: Text(
                              m.contratavel ? 'Contratável' : 'Não contratável',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: m.contratavel
                                    ? _verdeStatus
                                    : _cinzaStatus,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Informações do módulo
                    Text(
                      'Informações do módulo',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: _textoPrimario,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        _infoBloco('Nome', m.nome),
                        _infoBloco('Código', m.codigo),
                        _infoBloco('Ícone', m.icone),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (m.descricao.isNotEmpty) ...[
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Descrição',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 11,
                              color: _textoDescricao,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            m.descricao,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 13,
                              color: _textoPrimario,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                    ],
                    Row(
                      children: [
                        _infoBloco(
                          'Criado em',
                          m.createdAt != null
                              ? fmtData.format(m.createdAt!.toDate())
                              : '—',
                        ),
                        _infoBloco(
                          'Atualizado em',
                          m.updatedAt != null
                              ? fmtData.format(m.updatedAt!.toDate())
                              : '—',
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Planos vinculados
                    Text(
                      'Planos vinculados',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: _textoPrimario,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: _fundoPagina,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: _bordaInput),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.info_outline_rounded,
                            size: 18,
                            color: _roxoPrimario,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Consulte a tela "Planos e Módulos" para gerenciar os planos que utilizam este módulo.',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 12,
                                color: _textoSecundario,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Histórico de alterações
                    Text(
                      'Histórico de alterações',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: _textoPrimario,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: _fundoPagina,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: _bordaInput),
                      ),
                      child: Column(
                        children: [
                          _historicoItem(
                            Icons.add_circle_outline,
                            _roxoCard,
                            'Módulo criado',
                            m.createdAt != null
                                ? fmtData.format(m.createdAt!.toDate())
                                : '—',
                          ),
                          if (m.updatedAt != null &&
                              m.createdAt != null &&
                              m.updatedAt != m.createdAt)
                            _historicoItem(
                              Icons.edit_outlined,
                              const Color(0xFF2563EB),
                              'Informações atualizadas',
                              fmtData.format(m.updatedAt!.toDate()),
                            ),
                          _historicoItem(
                            m.ativo
                                ? Icons.check_circle_outline
                                : Icons.block_flipped,
                            m.ativo ? _verdeStatus : _laranjaStatus,
                            m.ativo ? 'Módulo ativado' : 'Módulo desativado',
                            m.updatedAt != null
                                ? fmtData.format(m.updatedAt!.toDate())
                                : '—',
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoBloco(String label, String valor) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 11,
                color: _textoDescricao,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              valor,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: _textoPrimario,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _historicoItem(IconData icone, Color cor, String texto, String data) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: cor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icone, size: 14, color: cor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              texto,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: _textoPrimario,
              ),
            ),
          ),
          Text(
            data,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11,
              color: _textoSecundario,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// MODAL — NOVA INTEGRAÇÃO
// ═══════════════════════════════════════════════════════════════
class _NovaIntegracaoDialog extends StatefulWidget {
  final void Function(
    String providerId,
    String nome,
    Map<String, dynamic> dados,
  )?
  onSalvar;
  const _NovaIntegracaoDialog({this.onSalvar});

  @override
  State<_NovaIntegracaoDialog> createState() => _NovaIntegracaoDialogState();
}

class _NovaIntegracaoDialogState extends State<_NovaIntegracaoDialog> {
  ProvedorFiscal? _selecionado;
  final _formKey = GlobalKey<FormState>();
  final _camposCtrl = <String, TextEditingController>{};
  final _nomeIntegracaoCtrl = TextEditingController();
  String _ambiente = 'Homologação';
  bool _salvando = false;

  @override
  void dispose() {
    for (final c in _camposCtrl.values) {
      c.dispose();
    }
    _nomeIntegracaoCtrl.dispose();
    super.dispose();
  }

  void _inicializarCampos(ProvedorFiscal prov) {
    _camposCtrl.clear();
    for (final campo in _camposDoProvedor(prov)) {
      _camposCtrl[campo.chave] = TextEditingController();
    }
  }

  List<CampoIntegracao> _camposDoProvedor(ProvedorFiscal prov) {
    return ProvedorFiscalInfo.provedores
        .firstWhere(
          (p) => p.id == prov.info.id,
          orElse: () => ProvedorFiscalInfo.provedores.last,
        )
        .campos;
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 60, vertical: 40),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: 680,
        constraints: const BoxConstraints(maxHeight: 720),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(28, 24, 20, 14),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Color(0xFFEEEAF6))),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Nova integração',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: _textoPrimario,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Escolha a plataforma que deseja conectar ao DiPertin.',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 13,
                            color: _textoSecundario,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(
                      Icons.close_rounded,
                      color: _textoSecundario,
                    ),
                  ),
                ],
              ),
            ),
            // Body
            Expanded(
              child: Form(
                key: _formKey,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Lista de provedores
                      if (_selecionado == null) ...[
                        Text(
                          'Provedores disponíveis',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: _textoSecundario,
                          ),
                        ),
                        const SizedBox(height: 12),
                        ...ProvedorFiscal.values.map(
                          (prov) => _buildProvedorCard(prov),
                        ),
                      ] else ...[
                        // Campos do provedor selecionado
                        _buildProvedorSelecionadoHeader(),
                        const SizedBox(height: 20),
                        // ── Campo: Nome da integração ──
                        _campoText(
                          label: 'Nome da integração',
                          controller: _nomeIntegracaoCtrl,
                          hint: 'Ex: Focus NFe - Loja do João',
                        ),
                        const SizedBox(height: 16),
                        if (_selecionado != ProvedorFiscal.personalizado) ...[
                          _campoInfo(
                            'Base URL homologação',
                            (_selecionado!.info.baseUrlSandbox),
                          ),
                          _campoInfo(
                            'Base URL produção',
                            (_selecionado!.info.baseUrlProducao ?? '—'),
                          ),
                          _campoInfo(
                            'Documentos suportados',
                            _selecionado!.info.documentosSuportados
                                .join(', ')
                                .toUpperCase(),
                          ),
                          _campoInfo(
                            'Tipo de autenticação',
                            _camposDoProvedor(_selecionado!).any(
                                  (c) => c.tipo == CampoIntegracaoTipo.senha,
                                )
                                ? 'API Key / Token'
                                : 'OAuth 2.0',
                          ),
                          const SizedBox(height: 16),
                        ],
                        // Campos editáveis
                        ...(_camposDoProvedor(_selecionado!).map((campo) {
                          if (campo.tipo == CampoIntegracaoTipo.selecao &&
                              campo.chave == 'environment') {
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _campoDropdown(
                                'Ambiente',
                                ['Homologação', 'Produção'],
                                _ambiente,
                                (v) => setState(() => _ambiente = v!),
                              ),
                            );
                          }
                          if (campo.tipo == CampoIntegracaoTipo.selecao &&
                              campo.chave == 'status')
                            return const SizedBox.shrink();
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _campoText(
                              label: campo.label,
                              controller: _camposCtrl[campo.chave]!,
                              isSenha: campo.tipo == CampoIntegracaoTipo.senha,
                              hint: campo.chave == 'api_key'
                                  ? 'Insira sua chave de API'
                                  : null,
                            ),
                          );
                        })),
                        const SizedBox(height: 8),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            // Footer
            Container(
              padding: const EdgeInsets.fromLTRB(24, 14, 24, 18),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Color(0xFFEEEAF6))),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _salvando
                        ? null
                        : () {
                            if (_selecionado != null) {
                              setState(() => _selecionado = null);
                            } else {
                              Navigator.of(context).pop();
                            }
                          },
                    child: Text(
                      _selecionado != null ? 'Voltar' : 'Cancelar',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        color: _textoSecundario,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  if (_selecionado != null)
                    Material(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                      child: InkWell(
                        onTap: _salvando ? null : _salvar,
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 11,
                          ),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [_roxoPrimario, _roxoClaro],
                            ),
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: [
                              BoxShadow(
                                color: _roxoPrimario.withValues(alpha: 0.25),
                                blurRadius: 8,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: _salvando
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Text(
                                  'Salvar integração',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                  ),
                                ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProvedorCard(ProvedorFiscal prov) {
    final sel = _selecionado == prov;
    final info = prov.info;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: () {
          setState(() {
            _selecionado = prov;
            _inicializarCampos(prov);
          });
        },
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: sel ? _lilasFundo : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: sel ? _roxoPrimario : const Color(0xFFEEEAF6),
              width: sel ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: sel
                      ? _roxoPrimario.withValues(alpha: 0.1)
                      : const Color(0xFFF5F4F8),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  info.icone,
                  color: sel ? _roxoPrimario : _textoSecundario,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      info.nome,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: _textoPrimario,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      info.descricao,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11,
                        color: _textoSecundario,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (sel)
                const Icon(
                  Icons.check_circle_rounded,
                  color: _roxoPrimario,
                  size: 22,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProvedorSelecionadoHeader() {
    final info = _selecionado!.info;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            _roxoPrimario.withValues(alpha: 0.05),
            _roxoPrimario.withValues(alpha: 0.02),
          ],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _roxoPrimario.withValues(alpha: 0.1)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [_roxoPrimario, _roxoClaro],
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(info.icone, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  info.nome,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: _textoPrimario,
                  ),
                ),
                Text(
                  info.descricao,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    color: _textoSecundario,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _campoInfo(String label, String valor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 160,
            child: Text(
              label,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: _textoSecundario,
              ),
            ),
          ),
          Expanded(
            child: Text(
              valor,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: _textoPrimario,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _campoText({
    required String label,
    required TextEditingController controller,
    bool isSenha = false,
    String? hint,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: _textoSecundario,
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          obscureText: isSenha,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 13,
            color: _textoPrimario,
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              color: _textoDescricao,
            ),
            filled: true,
            fillColor: const Color(0xFFF8F8FC),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFFE9E8F0)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFFE9E8F0)),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
          ),
        ),
      ],
    );
  }

  Widget _campoDropdown(
    String label,
    List<String> opcoes,
    String valor,
    ValueChanged<String?> onChanged,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: _textoSecundario,
          ),
        ),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          value: valor,
          items: opcoes
              .map(
                (o) => DropdownMenuItem(
                  value: o,
                  child: Text(
                    o,
                    style: GoogleFonts.plusJakartaSans(fontSize: 13),
                  ),
                ),
              )
              .toList(),
          onChanged: onChanged,
          decoration: InputDecoration(
            filled: true,
            fillColor: const Color(0xFFF8F8FC),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFFE9E8F0)),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _salvar() async {
    setState(() => _salvando = true);
    final dados = <String, dynamic>{};
    for (final e in _camposCtrl.entries) {
      dados[e.key] = e.value.text;
    }
    final nomeInt = _nomeIntegracaoCtrl.text.trim();
    dados['environment'] = _ambiente == 'Produção' ? 'production' : 'sandbox';
    dados['provider'] = _selecionado!.info.id;
    dados['provider_name'] = _selecionado!.info.nome;
    dados['base_url_sandbox'] = _selecionado!.info.baseUrlSandbox;
    dados['base_url_production'] = _selecionado!.info.baseUrlProducao;
    dados['supported_documents'] = _selecionado!.info.documentosSuportados;
    if (nomeInt.isNotEmpty) dados['nome_integracao'] = nomeInt;
    await FiscalIntegrationsService.salvarIntegracao(
      FiscalIntegrationModel(
        id: '',
        provider: _selecionado!.info.id,
        providerName: _selecionado!.info.nome,
        nomeIntegracao: nomeInt.isNotEmpty ? nomeInt : null,
        environment: dados['environment'] as String,
        baseUrlSandbox: _selecionado!.info.baseUrlSandbox,
        baseUrlProduction: _selecionado!.info.baseUrlProducao,
        supportedDocuments: _selecionado!.info.documentosSuportados,
        status: 'active',
      ),
      dados,
    );
    widget.onSalvar?.call(
      _selecionado!.info.id,
      nomeInt.isNotEmpty ? nomeInt : _selecionado!.info.nome,
      dados,
    );
    if (mounted) Navigator.of(context).pop();
    setState(() => _salvando = false);
  }
}

// ═══════════════════════════════════════════════════════════════
// MODAL — EDITAR INTEGRAÇÃO
// ═══════════════════════════════════════════════════════════════
class _EditarIntegracaoDialog extends StatefulWidget {
  final FiscalIntegrationModel integracao;
  const _EditarIntegracaoDialog({required this.integracao});

  @override
  State<_EditarIntegracaoDialog> createState() => _EditarIntegracaoDialogState();
}

class _EditarIntegracaoDialogState extends State<_EditarIntegracaoDialog> {
  final _formKey = GlobalKey<FormState>();
  final _camposCtrl = <String, TextEditingController>{};
  final _nomeIntegracaoCtrl = TextEditingController();
  String _ambiente = 'Homologação';
  String _statusSelecionado = 'Ativo';
  bool _salvando = false;

  @override
  void initState() {
    super.initState();
    final integ = widget.integracao;
    _ambiente = integ.environment == 'production' ? 'Produção' : 'Homologação';
    _statusSelecionado = integ.status == 'active' ? 'Ativo' : 'Inativo';
    _nomeIntegracaoCtrl.text = integ.nomeIntegracao ?? '';

    final provedorInfo = ProvedorFiscalInfo.provedores
        .firstWhere(
          (p) => p.id == integ.provider,
          orElse: () => ProvedorFiscalInfo.provedores.last,
        );

    for (final campo in provedorInfo.campos) {
      if (campo.chave == 'environment' || campo.chave == 'status') continue;
      _camposCtrl[campo.chave] = TextEditingController();
    }
  }

  @override
  void dispose() {
    for (final c in _camposCtrl.values) {
      c.dispose();
    }
    _nomeIntegracaoCtrl.dispose();
    super.dispose();
  }

  Future<void> _salvar() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _salvando = true);

    try {
      final dados = <String, dynamic>{};
      for (final e in _camposCtrl.entries) {
        dados[e.key] = e.value.text;
      }
      final nomeInt = _nomeIntegracaoCtrl.text.trim();
      dados['environment'] = _ambiente == 'Produção' ? 'production' : 'sandbox';
      dados['status'] = _statusSelecionado == 'Ativo' ? 'active' : 'inactive';
      if (nomeInt.isNotEmpty) dados['nome_integracao'] = nomeInt;

      final model = FiscalIntegrationModel(
        id: widget.integracao.id,
        provider: widget.integracao.provider,
        providerName: widget.integracao.providerName,
        nomeIntegracao: nomeInt.isNotEmpty ? nomeInt : null,
        environment: dados['environment'] as String,
        baseUrlSandbox: widget.integracao.baseUrlSandbox,
        baseUrlProduction: widget.integracao.baseUrlProduction,
        supportedDocuments: widget.integracao.supportedDocuments,
        status: dados['status'] as String,
      );

      await FiscalIntegrationsService.atualizarIntegracao(
        widget.integracao.id,
        model,
        dados,
      );

      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        _exibirSnack('Erro ao atualizar: $e');
      }
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  void _exibirSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        backgroundColor: _roxoPrimario,
      ),
    );
  }

  // ─── Helpers de formulário ─────────────────────────────────
  Widget _campoText(
    String label,
    TextEditingController controller, {
    bool isSenha = false,
    String? hint,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: _textoSecundario,
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          obscureText: isSenha,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 13,
            color: _textoPrimario,
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              color: _textoDescricao,
            ),
            filled: true,
            fillColor: const Color(0xFFF8F8FC),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFFE9E8F0)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFFE9E8F0)),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
          ),
        ),
      ],
    );
  }

  Widget _campoDropdown(
    String label,
    List<String> opcoes,
    String valor,
    ValueChanged<String?> onChanged,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: _textoSecundario,
          ),
        ),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          value: valor,
          items: opcoes
              .map((o) => DropdownMenuItem(value: o, child: Text(o)))
              .toList(),
          onChanged: onChanged,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 13,
            color: _textoPrimario,
          ),
          decoration: InputDecoration(
            filled: true,
            fillColor: const Color(0xFFF8F8FC),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFFE9E8F0)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFFE9E8F0)),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
          ),
        ),
      ],
    );
  }

  List<CampoIntegracao> _camposDoProvedor() {
    return ProvedorFiscalInfo.provedores
        .firstWhere(
          (p) => p.id == widget.integracao.provider,
          orElse: () => ProvedorFiscalInfo.provedores.last,
        )
        .campos;
  }

  @override
  Widget build(BuildContext context) {
    final provedorInfo = ProvedorFiscalInfo.provedores
        .firstWhere(
          (p) => p.id == widget.integracao.provider,
          orElse: () => ProvedorFiscalInfo.provedores.last,
        );

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 60, vertical: 40),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: 680,
        constraints: const BoxConstraints(maxHeight: 720),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(28, 24, 20, 14),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Color(0xFFEEEAF6))),
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [_roxoPrimario, _roxoClaro],
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(provedorInfo.icone, color: Colors.white, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Editar integração',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: _textoPrimario,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          provedorInfo.nome,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 13,
                            color: _textoSecundario,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, color: _textoSecundario),
                  ),
                ],
              ),
            ),
            // Body
            Expanded(
              child: Form(
                key: _formKey,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Informações do provedor (só leitura)
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: _lilasFundo,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: _roxoPrimario.withValues(alpha: 0.1)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(
                                  width: 130,
                                  child: Text('Provedor',
                                      style: TextStyle(
                                          fontWeight: FontWeight.w500, color: _textoSecundario, fontSize: 12)),
                                ),
                                Expanded(
                                  child: Text(widget.integracao.providerName,
                                      style: const TextStyle(color: Color(0xFF1A1A2E), fontSize: 12)),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(
                                  width: 130,
                                  child: Text('Documentos',
                                      style: TextStyle(
                                          fontWeight: FontWeight.w500, color: _textoSecundario, fontSize: 12)),
                                ),
                                Expanded(
                                  child: Text(
                                      widget.integracao.supportedDocuments.join(', ').toUpperCase(),
                                      style: const TextStyle(color: Color(0xFF1A1A2E), fontSize: 12)),
                                ),
                              ],
                            ),
                            if (widget.integracao.baseUrlSandbox.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SizedBox(
                                    width: 130,
                                    child: Text('URL Sandbox',
                                        style: TextStyle(
                                            fontWeight: FontWeight.w500, color: _textoSecundario, fontSize: 12)),
                                  ),
                                  Expanded(
                                    child: Text(widget.integracao.baseUrlSandbox,
                                        style: const TextStyle(color: Color(0xFF1A1A2E), fontSize: 12)),
                                  ),
                                ],
                              ),
                            ],
                            if (widget.integracao.baseUrlProduction != null &&
                                widget.integracao.baseUrlProduction!.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SizedBox(
                                    width: 130,
                                    child: Text('URL Produção',
                                        style: TextStyle(
                                            fontWeight: FontWeight.w500, color: _textoSecundario, fontSize: 12)),
                                  ),
                                  Expanded(
                                    child: Text(widget.integracao.baseUrlProduction!,
                                        style: const TextStyle(color: Color(0xFF1A1A2E), fontSize: 12)),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      // ── Campo: Nome da integração ──
                      _campoText(
                        'Nome da integração',
                        _nomeIntegracaoCtrl,
                        hint: 'Ex: Focus NFe - Loja do João',
                      ),
                      const SizedBox(height: 20),

                      // Campos editáveis
                      Text(
                        'Configurações da integração',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: _textoPrimario,
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Ambiente
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _campoDropdown(
                          'Ambiente',
                          ['Homologação', 'Produção'],
                          _ambiente,
                          (v) => setState(() => _ambiente = v!),
                        ),
                      ),

                      // Status
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _campoDropdown(
                          'Status',
                          ['Ativo', 'Inativo'],
                          _statusSelecionado,
                          (v) => setState(() => _statusSelecionado = v!),
                        ),
                      ),

                      // Campos de credenciais
                      ...(_camposDoProvedor().map((campo) {
                        if (campo.tipo == CampoIntegracaoTipo.selecao) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _campoText(
                            campo.label,
                            _camposCtrl[campo.chave]!,
                            isSenha: campo.tipo == CampoIntegracaoTipo.senha,
                            hint: campo.tipo == CampoIntegracaoTipo.senha
                                ? 'Deixe vazio para manter o atual'
                                : null,
                          ),
                        );
                      })),
                    ],
                  ),
                ),
              ),
            ),
            // Footer
            Container(
              padding: const EdgeInsets.fromLTRB(24, 14, 24, 18),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Color(0xFFEEEAF6))),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _salvando ? null : () => Navigator.of(context).pop(),
                    child: Text(
                      'Cancelar',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        color: _textoSecundario,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Material(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                    child: InkWell(
                      onTap: _salvando ? null : _salvar,
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 11),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [_roxoPrimario, _roxoClaro],
                          ),
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: [
                            BoxShadow(
                              color: _roxoPrimario.withValues(alpha: 0.25),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: _salvando
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : Text(
                                'Salvar alterações',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

extension on ProvedorFiscal {
  _ProvedorInfo get info {
    switch (this) {
      case ProvedorFiscal.focusNfe:
        return _ProvedorInfo(
          id: 'focus_nfe',
          nome: 'Focus NFe',
          icone: Icons.description_rounded,
          descricao:
              'API fiscal para emissão de NF-e, NFC-e, NFS-e, CT-e e MDF-e.',
          baseUrlSandbox: 'https://homologacao.focusnfe.com.br/v2',
          baseUrlProducao: 'https://api.focusnfe.com.br/v2',
          documentosSuportados: ['nfe', 'nfce', 'nfse', 'cte', 'mdfe'],
        );
      case ProvedorFiscal.nuvemFiscal:
        return _ProvedorInfo(
          id: 'nuvem_fiscal',
          nome: 'Nuvem Fiscal',
          icone: Icons.cloud_rounded,
          descricao: 'API REST para automação comercial e documentos fiscais.',
          baseUrlSandbox: 'https://sandbox-api.nuvemfiscal.com.br',
          baseUrlProducao: 'https://api.nuvemfiscal.com.br',
          documentosSuportados: ['nfe', 'nfce', 'nfse', 'cte', 'mdfe'],
        );
      case ProvedorFiscal.plugNotas:
        return _ProvedorInfo(
          id: 'plug_notas',
          nome: 'PlugNotas / TecnoSpeed',
          icone: Icons.electric_bolt_rounded,
          descricao: 'API para emissão de NF-e, NFC-e e NFS-e.',
          baseUrlSandbox: 'https://sandbox.plugnotas.com.br/api/v1',
          baseUrlProducao: 'https://api.plugnotas.com.br/v1',
          documentosSuportados: ['nfe', 'nfce', 'nfse'],
        );
      case ProvedorFiscal.webmaniaBr:
        return _ProvedorInfo(
          id: 'webmania_br',
          nome: 'WebmaniaBR',
          icone: Icons.web_rounded,
          descricao: 'API REST para emissão de NF-e e NFC-e.',
          baseUrlSandbox: 'https://sandbox.webmaniabr.com/api/1',
          baseUrlProducao: 'https://webmaniabr.com/api/1',
          documentosSuportados: ['nfe', 'nfce'],
        );
      case ProvedorFiscal.enotas:
        return _ProvedorInfo(
          id: 'enotas',
          nome: 'Enotas',
          icone: Icons.receipt_long_rounded,
          descricao: 'Plataforma para emissão de notas fiscais de serviço.',
          baseUrlSandbox: 'https://sandbox.enotas.com.br/api/v1',
          baseUrlProducao: 'https://api.enotas.com.br/v1',
          documentosSuportados: ['nfse'],
        );
      case ProvedorFiscal.arquivei:
        return _ProvedorInfo(
          id: 'arquivei',
          nome: 'Arquivei',
          icone: Icons.archive_rounded,
          descricao: 'Consulta, armazenamento e gestão de documentos fiscais.',
          baseUrlSandbox: 'https://sandbox.arquivei.com.br/api/v1',
          baseUrlProducao: 'https://api.arquivei.com.br/v1',
          documentosSuportados: ['nfe', 'nfce', 'nfse'],
        );
      case ProvedorFiscal.personalizado:
        return _ProvedorInfo(
          id: 'personalizado',
          nome: 'Outro / Conexão personalizada',
          icone: Icons.settings_ethernet_rounded,
          descricao: 'Configure manualmente qualquer outro provedor fiscal.',
          baseUrlSandbox: '',
          baseUrlProducao: null,
          documentosSuportados: ['nfe', 'nfce', 'nfse', 'cte', 'mdfe'],
        );
    }
  }
}

class _ProvedorInfo {
  final String id;
  final String nome;
  final IconData icone;
  final String descricao;
  final String baseUrlSandbox;
  final String? baseUrlProducao;
  final List<String> documentosSuportados;

  const _ProvedorInfo({
    required this.id,
    required this.nome,
    required this.icone,
    required this.descricao,
    required this.baseUrlSandbox,
    this.baseUrlProducao,
    this.documentosSuportados = const [],
  });
}

// ═══════════════════════════════════════════════════════════════
// MODAL — CONFIGURAR NOTA FISCAL (9 etapas)
// ═══════════════════════════════════════════════════════════════
class _ConfigurarNotaFiscalDialog extends StatefulWidget {
  final List<FiscalIntegrationModel> integracoes;
  final VoidCallback? onSalvar;
  const _ConfigurarNotaFiscalDialog({required this.integracoes, this.onSalvar});

  @override
  State<_ConfigurarNotaFiscalDialog> createState() =>
      _ConfigurarNotaFiscalDialogState();
}

class _ConfigurarNotaFiscalDialogState
    extends State<_ConfigurarNotaFiscalDialog> {
  int _etapa = 0;
  bool _salvando = false;

  // Etapa 1
  String? _provedorSelecionado;
  String _ambiente = 'Homologação';

  // Etapa 2
  bool _emitirNfe = false;
  bool _emitirNfce = false;
  bool _emitirNfse = false;

  // Etapa 3 — Dados fiscais
  final _razaoCtrl = TextEditingController();
  final _fantasiaCtrl = TextEditingController();
  final _cnpjCtrl = TextEditingController();
  final _ieCtrl = TextEditingController();
  final _imCtrl = TextEditingController();
  String _regimeTributario = 'Simples Nacional';
  final _cnaeCtrl = TextEditingController();
  String _crt = 'CRT 1';
  final _enderecoCtrl = TextEditingController();
  final _ufCtrl = TextEditingController();
  final _municipioCtrl = TextEditingController();
  final _cepCtrl = TextEditingController();
  final _telefoneCtrl = TextEditingController();
  final _emailFiscalCtrl = TextEditingController();

  // Etapa 4 — Certificado
  final _certificadoSenhaCtrl = TextEditingController();

  // Etapa 5 — NF-e
  final _serieNfeCtrl = TextEditingController(text: '1');
  final _proximoNumeroNfeCtrl = TextEditingController(text: '1');
  final _naturezaNfeCtrl = TextEditingController(text: 'Venda de mercadoria');
  String _cfopNfe = '5102';
  String _finalidadeNfe = '1';
  String _tipoOperacaoNfe = '1';
  String _indicadorPresenca = '1';
  bool _enviarDanfeEmail = true;

  // Etapa 6 — NFC-e
  final _serieNfceCtrl = TextEditingController(text: '1');
  final _proximoNumeroNfceCtrl = TextEditingController(text: '1');
  final _cscIdCtrl = TextEditingController();
  final _cscTokenCtrl = TextEditingController();
  final _qrCodeTokenCtrl = TextEditingController();
  String _ufAutorizadora = 'MT';
  bool _enviarComprovante = true;

  // Etapa 7 — NFS-e
  final _municipioPrestadorCtrl = TextEditingController();
  final _inscricaoMunicipalCtrl = TextEditingController();
  final _codigoServicoCtrl = TextEditingController();
  final _itemListaServicoCtrl = TextEditingController(text: '1.01');
  final _cnaeServicoCtrl = TextEditingController();
  final _aliquotaIssCtrl = TextEditingController(text: '5,0');
  String _naturezaOperacaoNfse = '1';
  String _regimeEspecial = '0';
  bool _retencaoIss = false;

  // Etapa 8 — Webhook

  // Etapa 9 — Resumo

  final List<String> _etapasNomes = [
    'Provedor Fiscal',
    'Documentos',
    'Dados da Empresa',
    'Certificado Digital',
    'Configuração NF-e',
    'Configuração NFC-e',
    'Configuração NFS-e',
    'Webhooks',
    'Resumo e Salvar',
  ];

  @override
  void dispose() {
    _razaoCtrl.dispose();
    _fantasiaCtrl.dispose();
    _cnpjCtrl.dispose();
    _ieCtrl.dispose();
    _imCtrl.dispose();
    _cnaeCtrl.dispose();
    _enderecoCtrl.dispose();
    _ufCtrl.dispose();
    _municipioCtrl.dispose();
    _cepCtrl.dispose();
    _telefoneCtrl.dispose();
    _emailFiscalCtrl.dispose();
    _certificadoSenhaCtrl.dispose();
    _serieNfeCtrl.dispose();
    _proximoNumeroNfeCtrl.dispose();
    _naturezaNfeCtrl.dispose();
    _serieNfceCtrl.dispose();
    _proximoNumeroNfceCtrl.dispose();
    _cscIdCtrl.dispose();
    _cscTokenCtrl.dispose();
    _qrCodeTokenCtrl.dispose();
    _municipioPrestadorCtrl.dispose();
    _inscricaoMunicipalCtrl.dispose();
    _codigoServicoCtrl.dispose();
    _itemListaServicoCtrl.dispose();
    _cnaeServicoCtrl.dispose();
    _aliquotaIssCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 60, vertical: 30),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: 720,
        constraints: const BoxConstraints(maxHeight: 760),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          children: [
            // Header com progresso
            _buildHeader(),
            // Body
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(28),
                child: _buildEtapa(),
              ),
            ),
            // Footer
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(28, 22, 20, 14),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFEEEAF6))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Configurar Nota Fiscal',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: _textoPrimario,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Etapa ${_etapa + 1} de 9: ${_etapasNomes[_etapa]}',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        color: _roxoPrimario,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded, color: _textoSecundario),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: (_etapa + 1) / 9,
              backgroundColor: const Color(0xFFEEEAF6),
              valueColor: const AlwaysStoppedAnimation<Color>(_roxoPrimario),
              minHeight: 4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEtapa() {
    switch (_etapa) {
      case 0:
        return _etapaProvedor();
      case 1:
        return _etapaDocumentos();
      case 2:
        return _etapaDadosEmpresa();
      case 3:
        return _etapaCertificado();
      case 4:
        return _etapaNfe();
      case 5:
        return _etapaNfce();
      case 6:
        return _etapaNfse();
      case 7:
        return _etapaWebhooks();
      case 8:
        return _etapaResumo();
      default:
        return const SizedBox.shrink();
    }
  }

  // ─── Etapa 1: Provedor Fiscal ──────────────────────────────
  Widget _etapaProvedor() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Selecione uma integração fiscal',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: _textoPrimario,
          ),
        ),
        const SizedBox(height: 12),
        ...widget.integracoes.map(
          (i) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: InkWell(
              onTap: () => setState(() => _provedorSelecionado = i.id),
              borderRadius: BorderRadius.circular(12),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _provedorSelecionado == i.id
                      ? _lilasFundo
                      : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _provedorSelecionado == i.id
                        ? _roxoPrimario
                        : const Color(0xFFEEEAF6),
                    width: _provedorSelecionado == i.id ? 1.5 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            i.nomeExibicao,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: _textoPrimario,
                            ),
                          ),
                          Text(
                            '${i.nomeIntegracao != null ? '${i.providerName} · ' : ''}${i.environment == 'production' ? 'Produção' : 'Homologação'} · ${i.supportedDocuments.join(", ").toUpperCase()}',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 11,
                              color: _textoSecundario,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_provedorSelecionado == i.id)
                      const Icon(
                        Icons.check_circle_rounded,
                        color: _roxoPrimario,
                        size: 20,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (widget.integracoes.isEmpty)
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF2F2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                const Icon(
                  Icons.warning_amber_rounded,
                  color: _laranjaStatus,
                  size: 36,
                ),
                const SizedBox(height: 12),
                Text(
                  'Nenhuma integração cadastrada. Crie uma integração fiscal primeiro.',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    color: _textoSecundario,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        if (_provedorSelecionado != null) ...[
          const SizedBox(height: 20),
          _campoDropdown(
            'Ambiente',
            ['Homologação', 'Produção'],
            _ambiente,
            (v) => setState(() => _ambiente = v!),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _verdeFundo,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _verdeStatus.withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.check_circle_rounded,
                  color: _verdeStatus,
                  size: 18,
                ),
                const SizedBox(width: 10),
                Text(
                  'Conexão com o provedor verificada.',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    color: _verdeStatus,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  // ─── Etapa 2: Documentos fiscais ───────────────────────────
  Widget _etapaDocumentos() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Habilitar documentos fiscais',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: _textoPrimario,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Selecione os tipos de nota fiscal que deseja emitir.',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 12,
            color: _textoSecundario,
          ),
        ),
        const SizedBox(height: 16),
        _checkboxDoc(
          Icons.description_rounded,
          'NF-e',
          'Nota Fiscal Eletrônica (modelo 55)',
          _emitirNfe,
          (v) => setState(() => _emitirNfe = v!),
        ),
        const SizedBox(height: 10),
        _checkboxDoc(
          Icons.qr_code_scanner_rounded,
          'NFC-e',
          'Nota Fiscal de Consumidor Eletrônica (modelo 65)',
          _emitirNfce,
          (v) => setState(() => _emitirNfce = v!),
        ),
        const SizedBox(height: 10),
        _checkboxDoc(
          Icons.miscellaneous_services_rounded,
          'NFS-e',
          'Nota Fiscal de Serviço Eletrônica',
          _emitirNfse,
          (v) => setState(() => _emitirNfse = v!),
        ),
      ],
    );
  }

  Widget _checkboxDoc(
    IconData icone,
    String titulo,
    String descricao,
    bool valor,
    ValueChanged<bool?> onChanged,
  ) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: valor ? _lilasFundo : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: valor
              ? _roxoPrimario.withValues(alpha: 0.3)
              : const Color(0xFFEEEAF6),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: valor
                  ? _roxoPrimario.withValues(alpha: 0.1)
                  : const Color(0xFFF5F4F8),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icone,
              color: valor ? _roxoPrimario : _textoSecundario,
              size: 20,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titulo,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: _textoPrimario,
                  ),
                ),
                Text(
                  descricao,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    color: _textoSecundario,
                  ),
                ),
              ],
            ),
          ),
          Checkbox(
            value: valor,
            onChanged: onChanged,
            activeColor: _roxoPrimario,
          ),
        ],
      ),
    );
  }

  // ─── Etapa 3: Dados fiscais da empresa ─────────────────────
  Widget _etapaDadosEmpresa() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Dados fiscais da empresa',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: _textoPrimario,
          ),
        ),
        const SizedBox(height: 16),
        _campoText('Razão social', _razaoCtrl),
        const SizedBox(height: 12),
        _campoText('Nome fantasia', _fantasiaCtrl),
        const SizedBox(height: 12),
        _campoText('CNPJ', _cnpjCtrl, hint: '00.000.000/0000-00'),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _campoText('Inscrição estadual', _ieCtrl)),
            const SizedBox(width: 12),
            Expanded(child: _campoText('Inscrição municipal', _imCtrl)),
          ],
        ),
        const SizedBox(height: 12),
        _campoDropdown(
          'Regime tributário',
          ['Simples Nacional', 'Lucro Presumido', 'Lucro Real', 'MEI'],
          _regimeTributario,
          (v) => setState(() => _regimeTributario = v!),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _campoText('CNAE', _cnaeCtrl)),
            const SizedBox(width: 12),
            Expanded(
              child: _campoDropdown(
                'CRT',
                ['CRT 1', 'CRT 2', 'CRT 3', 'CRT 4'],
                _crt,
                (v) => setState(() => _crt = v!),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _campoText('Endereço fiscal', _enderecoCtrl),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _campoText('UF', _ufCtrl)),
            const SizedBox(width: 12),
            Expanded(flex: 2, child: _campoText('Município', _municipioCtrl)),
            const SizedBox(width: 12),
            Expanded(child: _campoText('CEP', _cepCtrl, hint: '00000-000')),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _campoText(
                'Telefone',
                _telefoneCtrl,
                hint: '(00) 0000-0000',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _campoText(
                'E-mail fiscal',
                _emailFiscalCtrl,
                hint: 'fiscal@empresa.com',
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ─── Etapa 4: Certificado digital ──────────────────────────
  Widget _etapaCertificado() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Certificado digital A1',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: _textoPrimario,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Faça upload do certificado digital modelo A1 (.pfx ou .p12).',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 12,
            color: _textoSecundario,
          ),
        ),
        const SizedBox(height: 16),
        // Upload
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 32),
          decoration: BoxDecoration(
            color: _lilasFundo,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _roxoPrimario.withValues(alpha: 0.2),
              width: 1.5,
            ),
          ),
          child: Column(
            children: [
              Icon(
                Icons.cloud_upload_rounded,
                size: 40,
                color: _roxoPrimario.withValues(alpha: 0.5),
              ),
              const SizedBox(height: 10),
              Text(
                'Clique para selecionar o certificado',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: _roxoPrimario,
                ),
              ),
              Text(
                'Formatos aceitos: .pfx, .p12',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 11,
                  color: _textoSecundario,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _campoText(
          'Senha do certificado',
          _certificadoSenhaCtrl,
          isSenha: true,
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF8E1),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _laranjaStatus.withValues(alpha: 0.2)),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.info_outline_rounded,
                color: _laranjaStatus,
                size: 18,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'A senha e o certificado são criptografados. Nunca armazenamos em texto puro.',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    color: _textoSecundario,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ─── Etapa 5: Configuração NF-e ────────────────────────────
  Widget _etapaNfe() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildEtapaHeader(
          'Configuração NF-e',
          'Nota Fiscal Eletrônica (modelo 55)',
        ),
        const SizedBox(height: 16),
        _switchForm(
          'Ativar NF-e',
          _emitirNfe,
          (v) => setState(() => _emitirNfe = v),
        ),
        if (_emitirNfe) ...[
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _campoText('Série', _serieNfeCtrl)),
              const SizedBox(width: 12),
              Expanded(
                child: _campoText('Próximo número', _proximoNumeroNfeCtrl),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _campoText('Natureza da operação', _naturezaNfeCtrl),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _campoDropdown(
                  'CFOP padrão',
                  ['5102', '5405', '6102', '6404', '5910', '5949', '6903'],
                  _cfopNfe,
                  (v) => setState(() => _cfopNfe = v!),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _campoDropdown(
                  'Finalidade',
                  [
                    '1-NFe normal',
                    '2-NFe complementar',
                    '3-NFe ajuste',
                    '4-Devolução',
                  ],
                  _finalidadeNfe,
                  (v) => setState(() => _finalidadeNfe = v!),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _campoDropdown(
                  'Tipo operação',
                  ['1-Entrada', '0-Saída'],
                  _tipoOperacaoNfe,
                  (v) => setState(() => _tipoOperacaoNfe = v!),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _campoDropdown(
                  'Indicador presença',
                  [
                    '1-Operação presencial',
                    '2-Internet',
                    '3-Teleatendimento',
                    '4-NFC-e',
                    '5-Presencial fora',
                  ],
                  _indicadorPresenca,
                  (v) => setState(() => _indicadorPresenca = v!),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _switchForm(
            'Enviar DANFE/XML por e-mail',
            _enviarDanfeEmail,
            (v) => setState(() => _enviarDanfeEmail = v),
          ),
        ],
      ],
    );
  }

  // ─── Etapa 6: Configuração NFC-e ───────────────────────────
  Widget _etapaNfce() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildEtapaHeader(
          'Configuração NFC-e',
          'Nota Fiscal de Consumidor Eletrônica (modelo 65)',
        ),
        const SizedBox(height: 16),
        _switchForm(
          'Ativar NFC-e',
          _emitirNfce,
          (v) => setState(() => _emitirNfce = v),
        ),
        if (_emitirNfce) ...[
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _campoText('Série', _serieNfceCtrl)),
              const SizedBox(width: 12),
              Expanded(
                child: _campoText('Próximo número', _proximoNumeroNfceCtrl),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _campoText('CSC ID', _cscIdCtrl)),
              const SizedBox(width: 12),
              Expanded(
                child: _campoText('CSC Token', _cscTokenCtrl, isSenha: true),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _campoText('QR Code Token', _qrCodeTokenCtrl, isSenha: true),
          const SizedBox(height: 12),
          _campoDropdown(
            'UF autorizadora',
            [
              'MT',
              'PR',
              'SP',
              'RJ',
              'MG',
              'RS',
              'SC',
              'BA',
              'GO',
              'DF',
              'PE',
              'CE',
              'MA',
              'PA',
              'AM',
              'ES',
              'MS',
              'TO',
            ],
            _ufAutorizadora,
            (v) => setState(() => _ufAutorizadora = v!),
          ),
          const SizedBox(height: 12),
          _switchForm(
            'Enviar comprovante ao cliente',
            _enviarComprovante,
            (v) => setState(() => _enviarComprovante = v),
          ),
        ],
      ],
    );
  }

  // ─── Etapa 7: Configuração NFS-e ───────────────────────────
  Widget _etapaNfse() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildEtapaHeader(
          'Configuração NFS-e',
          'Nota Fiscal de Serviço Eletrônica',
        ),
        const SizedBox(height: 16),
        _switchForm(
          'Ativar NFS-e',
          _emitirNfse,
          (v) => setState(() => _emitirNfse = v),
        ),
        if (_emitirNfse) ...[
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _campoText(
                  'Município prestador',
                  _municipioPrestadorCtrl,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _campoText(
                  'Inscrição municipal',
                  _inscricaoMunicipalCtrl,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _campoText('Código de serviço', _codigoServicoCtrl),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _campoText('Item lista serviço', _itemListaServicoCtrl),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _campoText('CNAE serviço', _cnaeServicoCtrl)),
              const SizedBox(width: 12),
              Expanded(child: _campoText('Alíquota ISS (%)', _aliquotaIssCtrl)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _campoDropdown(
                  'Natureza operação',
                  [
                    '1-Tributação no município',
                    '2-Tributação fora do município',
                    '3-Isenção',
                    '4-Imune',
                    '5-Exigibilidade suspensa',
                  ],
                  _naturezaOperacaoNfse,
                  (v) => setState(() => _naturezaOperacaoNfse = v!),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _campoDropdown(
                  'Regime especial',
                  [
                    '0-Nenhum',
                    '1-Microempresa',
                    '2-Estimativa',
                    '3-Sociedade profissionais',
                    '4-Cooperativa',
                    '5-MEI',
                  ],
                  _regimeEspecial,
                  (v) => setState(() => _regimeEspecial = v!),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _switchForm(
            'Retenção ISS',
            _retencaoIss,
            (v) => setState(() => _retencaoIss = v),
          ),
        ],
      ],
    );
  }

  // ─── Etapa 8: Webhooks ─────────────────────────────────────
  Widget _etapaWebhooks() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildEtapaHeader(
          'Webhooks',
          'Receba notificações em tempo real sobre as notas fiscais.',
        ),
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _lilasFundo,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _roxoPrimario.withValues(alpha: 0.15)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.link_rounded,
                    size: 18,
                    color: _roxoPrimario,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Webhook URL gerada pelo DiPertin',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _roxoPrimario,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFE9E8F0)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'https://api.dipertin.com.br/fiscal/webhook/{id}',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          color: _textoSecundario,
                        ),
                        maxLines: 1,
                      ),
                    ),
                    const SizedBox(width: 8),
                    InkWell(
                      onTap: () => _exibirSnack('URL copiada!'),
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: _roxoPrimario.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Icon(
                          Icons.copy_rounded,
                          size: 14,
                          color: _roxoPrimario,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Eventos recebidos:',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: _textoSecundario,
          ),
        ),
        const SizedBox(height: 8),
        _eventoWebhook(
          Icons.check_circle_rounded,
          _verdeStatus,
          'nota_autorizada',
          'Nota fiscal autorizada pela SEFAZ',
        ),
        _eventoWebhook(
          Icons.cancel_rounded,
          _vermelhoStatus,
          'nota_rejeitada',
          'Nota fiscal rejeitada pela SEFAZ',
        ),
        _eventoWebhook(
          Icons.block_rounded,
          _laranjaStatus,
          'nota_cancelada',
          'Nota fiscal cancelada',
        ),
        _eventoWebhook(
          Icons.hourglass_top_rounded,
          _roxoPrimario,
          'nota_em_processamento',
          'Nota fiscal em processamento',
        ),
      ],
    );
  }

  Widget _eventoWebhook(
    IconData icone,
    Color cor,
    String codigo,
    String descricao,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: cor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icone, size: 16, color: cor),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                codigo,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: _textoPrimario,
                ),
              ),
              Text(
                descricao,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 11,
                  color: _textoSecundario,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─── Etapa 9: Resumo ───────────────────────────────────────
  Widget _etapaResumo() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildEtapaHeader(
          'Resumo da configuração',
          'Revise os dados antes de salvar.',
        ),
        const SizedBox(height: 20),
        _resumoBloco('Provedor Fiscal', [
          _resumoItem(
            'Provedor',
            widget.integracoes.any((i) => i.id == _provedorSelecionado)
                ? widget.integracoes
                      .firstWhere((i) => i.id == _provedorSelecionado)
                      .providerName
                : '—',
          ),
          _resumoItem('Ambiente', _ambiente),
        ]),
        const SizedBox(height: 12),
        _resumoBloco('Documentos habilitados', [
          _resumoItem('NF-e', _emitirNfe ? 'Sim' : 'Não'),
          _resumoItem('NFC-e', _emitirNfce ? 'Sim' : 'Não'),
          _resumoItem('NFS-e', _emitirNfse ? 'Sim' : 'Não'),
        ]),
        const SizedBox(height: 12),
        _resumoBloco('Empresa', [
          _resumoItem(
            'Razão social',
            _razaoCtrl.text.isEmpty ? '—' : _razaoCtrl.text,
          ),
          _resumoItem('CNPJ', _cnpjCtrl.text.isEmpty ? '—' : _cnpjCtrl.text),
        ]),
      ],
    );
  }

  Widget _resumoBloco(String titulo, List<Widget> itens) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFEEEAF6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            titulo,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: _roxoPrimario,
            ),
          ),
          const SizedBox(height: 10),
          ...itens,
        ],
      ),
    );
  }

  Widget _resumoItem(String label, String valor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                color: _textoSecundario,
              ),
            ),
          ),
          Expanded(
            child: Text(
              valor,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: _textoPrimario,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEtapaHeader(String titulo, String subtitulo) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          titulo,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: _textoPrimario,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitulo,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 12,
            color: _textoSecundario,
          ),
        ),
      ],
    );
  }

  // ─── Footer ────────────────────────────────────────────────
  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 14, 24, 18),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFFEEEAF6))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Botão voltar
          if (_etapa > 0)
            TextButton(
              onPressed: () => setState(() => _etapa--),
              child: Row(
                children: [
                  const Icon(
                    Icons.arrow_back_rounded,
                    size: 14,
                    color: _textoSecundario,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Anterior',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      color: _textoSecundario,
                    ),
                  ),
                ],
              ),
            )
          else
            const SizedBox.shrink(),
          // Botão avançar/salvar
          Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              onTap: _salvando ? null : _avancarOuSalvar,
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 11,
                ),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [_roxoPrimario, _roxoClaro],
                  ),
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: _roxoPrimario.withValues(alpha: 0.25),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: _salvando
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        _etapa == 8 ? 'Salvar configuração' : 'Próximo',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _avancarOuSalvar() async {
    if (_etapa < 8) {
      setState(() => _etapa++);
    } else {
      setState(() => _salvando = true);
      await Future.delayed(const Duration(seconds: 1));
      widget.onSalvar?.call();
      if (mounted) Navigator.of(context).pop();
      setState(() => _salvando = false);
    }
  }

  void _exibirSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        backgroundColor: _roxoBtn,
      ),
    );
  }

  // ─── Helpers de formulário ─────────────────────────────────
  Widget _campoText(
    String label,
    TextEditingController controller, {
    bool isSenha = false,
    String? hint,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: _textoSecundario,
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          obscureText: isSenha,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 13,
            color: _textoPrimario,
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              color: _textoDescricao,
            ),
            filled: true,
            fillColor: const Color(0xFFF8F8FC),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFFE9E8F0)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFFE9E8F0)),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
          ),
        ),
      ],
    );
  }

  Widget _campoDropdown(
    String label,
    List<String> opcoes,
    String valor,
    ValueChanged<String?> onChanged,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: _textoSecundario,
          ),
        ),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          value: valor,
          items: opcoes
              .map(
                (o) => DropdownMenuItem(
                  value: o,
                  child: Text(
                    o,
                    style: GoogleFonts.plusJakartaSans(fontSize: 12),
                  ),
                ),
              )
              .toList(),
          onChanged: onChanged,
          decoration: InputDecoration(
            filled: true,
            fillColor: const Color(0xFFF8F8FC),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFFE9E8F0)),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
          ),
        ),
      ],
    );
  }

  Widget _switchForm(String label, bool valor, ValueChanged<bool> onChanged) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE9E8F0)),
      ),
      child: Row(
        children: [
          Text(
            label,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              color: _textoPrimario,
            ),
          ),
          const Spacer(),
          Switch.adaptive(
            value: valor,
            onChanged: onChanged,
            activeTrackColor: _roxoBtn,
            activeThumbColor: Colors.white,
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// MODAL — NOVA INTEGRAÇÃO LOJISTA
// ═══════════════════════════════════════════════════════════════
class _NovaIntegracaoLojistaDialog extends StatefulWidget {
  final VoidCallback? onSalvar;
  const _NovaIntegracaoLojistaDialog({this.onSalvar});

  @override
  State<_NovaIntegracaoLojistaDialog> createState() =>
      _NovaIntegracaoLojistaDialogState();
}

class _NovaIntegracaoLojistaDialogState
    extends State<_NovaIntegracaoLojistaDialog> {
  int _passo = 0;
  bool _carregando = true;
  bool _salvando = false;

  // Lojistas disponíveis (filtrados) e busca
  List<_LojistaOption> _lojistasDisponiveis = [];
  _LojistaOption? _lojistaSelecionado;
  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  List<_LojistaOption> _filteredLojistas = [];

  // Integrações já existentes
  Set<String> _lojistasComIntegracao = {};

  // Provedor selecionado (da coleção fiscal_integrations)
  FiscalIntegrationModel? _provedorSelecionado;

  // Controllers do formulário de configuração
  final _limiteCtrl = TextEditingController(text: '100');
  final _razaoSocialCtrl = TextEditingController();
  final _nomeFantasiaCtrl = TextEditingController();
  final _cnpjCtrl = TextEditingController();
  final _ieCtrl = TextEditingController();
  final _cepCtrl = TextEditingController();
  final _logradouroCtrl = TextEditingController();
  final _numeroCtrl = TextEditingController();
  final _complementoCtrl = TextEditingController();
  final _bairroCtrl = TextEditingController();
  final _cidadeCtrl = TextEditingController();
  final _codigoCidadeCtrl = TextEditingController();
  final _ufCtrl = TextEditingController();
  final _cnaeCtrl = TextEditingController();
  final _senhaCertCtrl = TextEditingController();
  String _regimeTributario = 'Simples Nacional';
  bool _ieIsento = false;
  bool _certificadoAnexado = false;
  String? _nomeCertificado;
  Uint8List? _certificadoBytes;

  static const _regimes = [
    'MEI',
    'Simples Nacional',
    'Simples Nacional – Excesso Sublimite',
    'Lucro Presumido',
    'Lucro Real',
  ];

  /// Mapeia regime tributário → código CRT da NF-e.
  ///
  /// MEI                        → CRT=1 (Simples Nacional)
  /// Simples Nacional           → CRT=1
  /// Excesso Sublimite          → CRT=2
  /// Lucro Presumido            → CRT=3
  /// Lucro Real                 → CRT=3
  static String _crtDoRegime(String regime) {
    switch (regime) {
      case 'MEI':
      case 'Simples Nacional':
        return '1';
      case 'Simples Nacional – Excesso Sublimite':
        return '2';
      case 'Lucro Presumido':
      case 'Lucro Real':
        return '3';
      default:
        return '1';
    }
  }

  static const _ufs = [
    'AC', 'AL', 'AP', 'AM', 'BA', 'CE', 'DF', 'ES', 'GO',
    'MA', 'MT', 'MS', 'MG', 'PA', 'PB', 'PR', 'PE', 'PI',
    'RJ', 'RN', 'RS', 'RO', 'RR', 'SC', 'SP', 'SE', 'TO',
  ];

  @override
  void initState() {
    super.initState();
    _carregarDados();
  }

  Future<void> _carregarDados() async {
    setState(() => _carregando = true);
    try {
      // Carrega integrações existentes, planos do sistema e assinaturas
      final results = await Future.wait([
        FirebaseFirestore.instance
            .collection('lojista_integracao')
            .get()
            .then(
              (snap) =>
                  snap.docs.map((d) => d['store_id'] as String? ?? '').toSet(),
            ),
        FirebaseFirestore.instance
            .collection('modulos_planos')
            .where('ativo', isEqualTo: true)
            .get()
            .then((snap) {
              // Retorna MAPA POR ID: planId → lista de nomes de módulos habilitados
              // E MAPA POR NOME: planName normalizado → id
              final mapPorId = <String, List<String>>{};
              final mapPorNome = <String, String>{};
              for (final d in snap.docs) {
                final data = d.data();
                final modulos =
                    List<String>.from(data['modulos'] as List? ?? []);
                mapPorId[d.id] = modulos;

                final nome = (data['nome'] as String? ?? '').trim().toLowerCase();
                if (nome.isNotEmpty) {
                  mapPorNome[nome] = d.id;
                }
              }
              debugPrint(
                '[NovaIntegracaoLojista] Planos ativos carregados: '
                '${mapPorId.length} por ID, ${mapPorNome.length} por nome',
              );
              return [mapPorId, mapPorNome];
            }),
        FirebaseFirestore.instance
            .collection('assinaturas_clientes')
            .get()
            .then(
              (snap) =>
                  snap.docs.map(ClienteAssinaturaModel.fromFirestore).toList(),
            ),
      ]);

      _lojistasComIntegracao = results[0] as Set<String>;
      final planosData = results[1] as List;
      final planosPorId = planosData[0] as Map<String, List<String>>;
      final planosPorNome = planosData[1] as Map<String, String>;
      final assinaturas = results[2] as List<ClienteAssinaturaModel>;

      debugPrint(
        '[NovaIntegracaoLojista] Assinaturas carregadas: ${assinaturas.length}',
      );
      for (final a in assinaturas) {
        debugPrint(
          '[NovaIntegracaoLojista]   assinatura: planId="${a.planId}" '
          'planName="${a.planName}" store="${a.storeName}" status="${a.status}"',
        );
      }

      // Função auxiliar: resolve o ID do doc do plano a partir da assinatura
      String? resolverPlanoId(ClienteAssinaturaModel c) {
        // Tenta 1: planId como document ID
        if (planosPorId.containsKey(c.planId)) return c.planId;
        // Tenta 2: planId pode ser o nome do módulo (não o doc ID)
        debugPrint(
          '[NovaIntegracaoLojista] planId="${c.planId}" não encontrado como doc ID. '
          'Tentando por nome do plano: "${c.planName}"',
        );
        // Tenta 3: planName normalizado como fallback
        final nomeKey = c.planName.trim().toLowerCase();
        if (nomeKey.isNotEmpty && planosPorNome.containsKey(nomeKey)) {
          return planosPorNome[nomeKey];
        }
        // Tenta 4: o próprio planId pode ser o nome do plano
        final planIdKey = c.planId.trim().toLowerCase();
        if (planIdKey.isNotEmpty && planosPorNome.containsKey(planIdKey)) {
          return planosPorNome[planIdKey];
        }
        debugPrint(
          '[NovaIntegracaoLojista] NÃO foi possível resolver plano para '
          'planId="${c.planId}" planName="${c.planName}"',
        );
        return null;
      }

      // Filtra: apenas assinaturas ativas que tenham módulo de NF-e
      final vistos = <String>{};
      final lista = <_LojistaOption>[];
      for (final c in assinaturas) {
        if (c.status == 'cancelado' ||
            c.status == 'suspenso' ||
            c.status == 'pagamento_pendente') {
          continue;
        }

        // Resolve o doc ID do plano
        final resolvedPlanId = resolverPlanoId(c);
        if (resolvedPlanId == null) continue;

        // Verifica os módulos do plano
        // (modulos_planos.modulos armazena o NOME do módulo, ex: "Emissão de NF-e",
        // não o código interno como "ENF-68" ou "emissao_nfe")
        final modulosDoPlano = planosPorId[resolvedPlanId]!;
        final temModuloNfe = modulosDoPlano.any((mod) {
          final nomeLower = mod.toLowerCase();
          return nomeLower.contains('nfe') ||
              nomeLower.contains('nf-e') ||
              nomeLower.contains('emissão') ||
              nomeLower.contains('gestao') && nomeLower.contains('comercial') ||
              nomeLower.contains('gestão') && nomeLower.contains('comercial');
        });
        if (!temModuloNfe) {
          debugPrint(
            '[NovaIntegracaoLojista] Plano "${c.planName}" NÃO tem módulo NF-e. '
            'Módulos: $modulosDoPlano',
          );
          continue;
        }

        final storeId = c.storeId.isNotEmpty ? c.storeId : c.id;
        if (!vistos.add(storeId)) {
          debugPrint(
            '[NovaIntegracaoLojista] Duplicata ignorada: $storeId',
          );
          continue;
        }
        if (_lojistasComIntegracao.contains(storeId)) {
          debugPrint(
            '[NovaIntegracaoLojista] Já tem integração: $storeId',
          );
          continue;
        }
        lista.add(
          _LojistaOption(
            storeId: storeId,
            nome: c.storeName.isNotEmpty ? c.storeName : c.ownerName,
            email: c.email,
            avatar: null,
            cpfCnpj: c.cpfCnpj,
            planoNome: c.planName,
          ),
        );
      }
      debugPrint(
        '[NovaIntegracaoLojista] Lojistas disponíveis: ${lista.length}',
      );
      for (final l in lista) {
        debugPrint(
          '[NovaIntegracaoLojista]   -> storeId="${l.storeId}" nome="${l.nome}"',
        );
      }
      _lojistasDisponiveis = lista;
      _filteredLojistas = List.from(lista);
    } catch (e, st) {
      debugPrint('[NovaIntegracaoLojista] Erro ao carregar dados: $e\n$st');
    }
    if (mounted) setState(() => _carregando = false);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _searchFocus.dispose();
    _limiteCtrl.dispose();
    _razaoSocialCtrl.dispose();
    _nomeFantasiaCtrl.dispose();
    _cnpjCtrl.dispose();
    _ieCtrl.dispose();
    _cepCtrl.dispose();
    _logradouroCtrl.dispose();
    _numeroCtrl.dispose();
    _complementoCtrl.dispose();
    _bairroCtrl.dispose();
    _cidadeCtrl.dispose();
    _codigoCidadeCtrl.dispose();
    _ufCtrl.dispose();
    _cnaeCtrl.dispose();
    _senhaCertCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 60, vertical: 50),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: 600,
        constraints: const BoxConstraints(maxHeight: 680),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          children: [
            _dialogHeader(),
            Expanded(
              child: _carregando
                  ? const Center(child: CircularProgressIndicator())
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: _buildPasso(),
                    ),
            ),
            _dialogFooter(),
          ],
        ),
      ),
    );
  }

  Widget _dialogHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(28, 22, 20, 14),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFEEEAF6))),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Nova Integração Lojista',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: _textoPrimario,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _passo == 0
                      ? 'Pesquise e selecione o lojista.'
                      : _provedorSelecionado == null
                          ? 'Escolha o provedor fiscal.'
                          : 'Configure os dados fiscais e finalize.',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    color: _textoSecundario,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded, color: _textoSecundario),
          ),
        ],
      ),
    );
  }

  Widget _buildPasso() {
    if (_passo == 0) return _passoSelecao();
    return _passoResumo();
  }

  Widget _passoSelecao() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Lojista',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: _textoSecundario,
          ),
        ),
        const SizedBox(height: 8),
        _buildSearchField(),
        const SizedBox(height: 6),
        if (_lojistaSelecionado == null) _buildSearchDropdown(),
        if (_lojistaSelecionado != null) _buildLojistaSelecionado(),
      ],
    );
  }

  Widget _buildSearchField() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _searchFocus.hasFocus
              ? _roxoPrimario
              : const Color(0xFFE9E8F0),
          width: _searchFocus.hasFocus ? 1.5 : 1,
        ),
        boxShadow: _searchFocus.hasFocus
            ? [
                BoxShadow(
                  color: _roxoPrimario.withValues(alpha: 0.08),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: TextField(
        controller: _searchCtrl,
        focusNode: _searchFocus,
        onChanged: _filtrarLojistas,
        decoration: InputDecoration(
          hintText: 'Pesquisar lojista...',
          hintStyle: GoogleFonts.plusJakartaSans(
            fontSize: 13,
            color: _textoSecundario.withValues(alpha: 0.5),
          ),
          prefixIcon: Icon(
            Icons.search_rounded,
            color: _searchFocus.hasFocus ? _roxoPrimario : _textoSecundario,
            size: 20,
          ),
          suffixIcon: _lojistaSelecionado != null
              ? IconButton(
                  icon: const Icon(
                    Icons.close_rounded,
                    size: 18,
                    color: _textoSecundario,
                  ),
                  onPressed: _limparSelecao,
                )
              : null,
          filled: true,
          fillColor: const Color(0xFFF8F8FC),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 13,
          ),
        ),
        style: GoogleFonts.plusJakartaSans(fontSize: 13, color: _textoPrimario),
      ),
    );
  }

  Widget _buildSearchDropdown() {
    if (!_searchFocus.hasFocus && _searchCtrl.text.trim().isEmpty) {
      return const SizedBox.shrink();
    }
    if (_filteredLojistas.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFEEEAF6)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            Icon(
              Icons.search_off_rounded,
              size: 32,
              color: _textoSecundario.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 8),
            Text(
              'Nenhum lojista encontrado',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                color: _textoSecundario,
              ),
            ),
          ],
        ),
      );
    }
    return Container(
      constraints: const BoxConstraints(maxHeight: 220),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFEEEAF6)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ListView.separated(
        shrinkWrap: true,
        padding: const EdgeInsets.all(6),
        itemCount: _filteredLojistas.length,
        separatorBuilder: (_, _) =>
            const Divider(height: 1, indent: 12, endIndent: 12),
        itemBuilder: (context, i) =>
            _buildSearchResultCard(_filteredLojistas[i]),
      ),
    );
  }

  Widget _buildSearchResultCard(_LojistaOption l) {
    final query = _searchCtrl.text.trim().toLowerCase();
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _selecionarLojista(l),
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: _lilasFundo,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.store_rounded,
                  color: _roxoPrimario,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _textoDestacado(
                      l.nome,
                      query,
                      13,
                      FontWeight.w600,
                      _textoPrimario,
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        if (l.cpfCnpj != null && l.cpfCnpj!.isNotEmpty)
                          Text(
                            'CNPJ: ${l.cpfCnpj}  ·  ',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 10,
                              color: _textoSecundario,
                            ),
                          ),
                        Expanded(
                          child: Text(
                            l.planoNome,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                              color: _roxoBtn,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _verdeFundo,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'Ativo',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    color: _verdeStatus,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLojistaSelecionado() {
    final l = _lojistaSelecionado!;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _lilasFundo,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _roxoPrimario.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: _roxoPrimario.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.store_rounded,
              color: _roxoPrimario,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.nome,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: _textoPrimario,
                  ),
                ),
                Text(
                  '${l.cpfCnpj ?? ''}  ·  ${l.planoNome}',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    color: _textoSecundario,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const Icon(Icons.check_circle_rounded, color: _verdeStatus, size: 20),
        ],
      ),
    );
  }

  /// Destaca o texto pesquisado dentro do nome
  Widget _textoDestacado(
    String texto,
    String query,
    double size,
    FontWeight weight,
    Color cor,
  ) {
    if (query.isEmpty) {
      return Text(
        texto,
        style: GoogleFonts.plusJakartaSans(
          fontSize: size,
          fontWeight: weight,
          color: cor,
        ),
      );
    }
    final lower = texto.toLowerCase();
    final idx = lower.indexOf(query);
    if (idx < 0) {
      return Text(
        texto,
        style: GoogleFonts.plusJakartaSans(
          fontSize: size,
          fontWeight: weight,
          color: cor,
        ),
      );
    }
    return RichText(
      text: TextSpan(
        children: [
          TextSpan(
            text: texto.substring(0, idx),
            style: GoogleFonts.plusJakartaSans(
              fontSize: size,
              fontWeight: weight,
              color: cor,
            ),
          ),
          TextSpan(
            text: texto.substring(idx, idx + query.length),
            style: GoogleFonts.plusJakartaSans(
              fontSize: size,
              fontWeight: FontWeight.w700,
              color: _roxoPrimario,
            ),
          ),
          TextSpan(
            text: texto.substring(idx + query.length),
            style: GoogleFonts.plusJakartaSans(
              fontSize: size,
              fontWeight: weight,
              color: cor,
            ),
          ),
        ],
      ),
    );
  }

  void _filtrarLojistas(String query) {
    final q = query.trim().toLowerCase();
    setState(() {
      if (q.isEmpty) {
        _filteredLojistas = List.from(_lojistasDisponiveis);
      } else {
        _filteredLojistas = _lojistasDisponiveis.where((l) {
          final nome = l.nome.toLowerCase();
          final cpf = (l.cpfCnpj ?? '').toLowerCase();
          final email = l.email.toLowerCase();
          final plano = l.planoNome.toLowerCase();
          return nome.contains(q) ||
              cpf.contains(q) ||
              email.contains(q) ||
              plano.contains(q);
        }).toList();
      }
    });
  }

  void _selecionarLojista(_LojistaOption l) {
    setState(() {
      _lojistaSelecionado = l;
      _searchCtrl.text = l.nome;
    });
    _searchFocus.unfocus();
  }

  void _limparSelecao() {
    _searchCtrl.clear();
    setState(() {
      _lojistaSelecionado = null;
      _filteredLojistas = List.from(_lojistasDisponiveis);
    });
    _searchFocus.requestFocus();
  }

  Widget _passoResumo() {
    final l = _lojistaSelecionado;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Resumo do lojista ──
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFFAFAFC),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFEEEAF6)),
          ),
          child: Column(
            children: [
              _linhaResumo('Lojista', l?.nome ?? '—'),
              _linhaResumo('E-mail', l?.email ?? '—'),
              _linhaResumo('CPF/CNPJ', l?.cpfCnpj ?? '—'),
              _linhaResumo('Plano', l?.planoNome ?? '—'),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // ── Provedor Fiscal ──
        Text(
          'Provedor Fiscal',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: _textoSecundario,
          ),
        ),
        const SizedBox(height: 8),
        if (_provedorSelecionado != null)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _lilasFundo,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _roxoBtn.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: _roxoPrimario.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.cloud_done_rounded,
                      color: _roxoPrimario, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _provedorSelecionado!.nomeExibicao,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: _textoPrimario,
                        ),
                      ),
                      Text(
                        '${_provedorSelecionado!.nomeIntegracao != null ? '${_provedorSelecionado!.providerName} · ' : ''}${_provedorSelecionado!.environment == 'production' ? 'Produção' : 'Homologação'} · ${_provedorSelecionado!.supportedDocuments.join(', ')}',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 11,
                          color: _textoSecundario,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.swap_horiz_rounded,
                      size: 18, color: _roxoPrimario),
                  tooltip: 'Trocar provedor',
                  onPressed: _mostrarSelecionarProvedor,
                ),
              ],
            ),
          )
        else
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _mostrarSelecionarProvedor,
              icon: const Icon(Icons.add_circle_outline_rounded, size: 18),
              label: Text('Escolher Provedor',
                  style: GoogleFonts.plusJakartaSans(fontSize: 13)),
              style: OutlinedButton.styleFrom(
                foregroundColor: _roxoPrimario,
                side: const BorderSide(color: _roxoPrimario),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        const SizedBox(height: 20),

        // ── Formulário de configuração (só exibe após escolher provedor) ──
        if (_provedorSelecionado != null) ...[
          _buildFormularioConfig(),
          const SizedBox(height: 16),
          // Aviso informativo
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _verdeFundo,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _verdeStatus.withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_rounded,
                    color: _verdeStatus, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Sem certificado digital válido e dados fiscais completos, '
                    'a emissão de NF-e será bloqueada.',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11, color: _textoSecundario),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildFormularioConfig() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Limite mensal ──
        Text(
          'Limite mensal de NF-e',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: _textoSecundario,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _limiteCtrl,
          keyboardType: TextInputType.number,
          decoration: _inputDec(
            'Quantidade de notas fiscais por mês',
            Icons.numbers_rounded,
          ),
        ),
        const SizedBox(height: 20),

        // ── Dados fiscais da empresa ──
        Text(
          'Dados fiscais da empresa',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: _textoSecundario,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFFAFAFC),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFEEEAF6)),
          ),
          child: Column(
            children: [
              _campoForm('Razão Social', _razaoSocialCtrl, 'Razão social da empresa'),
              const SizedBox(height: 12),
              _campoForm('Nome Fantasia', _nomeFantasiaCtrl, 'Nome fantasia'),
              const SizedBox(height: 12),
              _campoCnpj('CNPJ', _cnpjCtrl),
              const SizedBox(height: 12),
              _campoForm('Inscrição Estadual', _ieCtrl, 'IE'),
              const SizedBox(height: 4),
              SwitchListTile.adaptive(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(
                  'IE Isenta (Dispensada)',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: _ieIsento ? DiPertinTheme.primaryRoxo : DiPertinTheme.textSecondary,
                  ),
                ),
                subtitle: _ieIsento
                    ? Text(
                        'Inscrição Estadual não será enviada na NF-e.',
                        style: TextStyle(fontSize: 11, color: DiPertinTheme.secondaryLaranja),
                      )
                    : null,
                value: _ieIsento,
                activeColor: DiPertinTheme.primaryRoxo,
                onChanged: (v) => setState(() => _ieIsento = v),
              ),
              const SizedBox(height: 12),

              // ── Endereço fiscal (campos individuais) ──
              _campoForm('CEP', _cepCtrl, '00000-000'),
              const SizedBox(height: 12),
              _campoForm('Logradouro', _logradouroCtrl, 'Rua, Avenida...'),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(flex: 2, child: _campoForm('Número', _numeroCtrl, 'Nº')),
                  const SizedBox(width: 12),
                  Expanded(flex: 3, child: _campoForm('Complemento', _complementoCtrl, 'Apto, Bloco (opcional)')),
                ],
              ),
              const SizedBox(height: 12),
              _campoForm('Bairro', _bairroCtrl, 'Bairro'),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(flex: 3, child: _campoForm('Cidade', _cidadeCtrl, 'Município')),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 1,
                    child: DropdownButtonFormField<String>(
                      value: _ufCtrl.text.isNotEmpty && _ufs.contains(_ufCtrl.text) ? _ufCtrl.text : null,
                      decoration: _inputDecRegime(),
                      hint: const Text('UF', style: TextStyle(fontSize: 13)),
                      items: _ufs.map((uf) => DropdownMenuItem(
                        value: uf,
                        child: Text(uf, style: const TextStyle(fontSize: 13)),
                      )).toList(),
                      onChanged: (v) {
                        if (v != null) { setState(() { _ufCtrl.text = v; }); }
                      },
                      style: GoogleFonts.plusJakartaSans(fontSize: 13, color: _textoPrimario),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _campoForm('Código IBGE do Município', _codigoCidadeCtrl, '7 dígitos'),
              const SizedBox(height: 12),
              _campoForm('CNAE', _cnaeCtrl, 'Código CNAE de 7 dígitos'),
              const SizedBox(height: 12),
              Text(
                'Regime Tributário',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: _textoSecundario,
                ),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: _regimeTributario,
                decoration: _inputDecRegime(),
                items: _regimes.map((r) => DropdownMenuItem(
                  value: r,
                  child: Text(r, style: const TextStyle(fontSize: 13)),
                )).toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _regimeTributario = v);
                },
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13, color: _textoPrimario),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // ── Certificado Digital A1 ──
        Text(
          'Certificado Digital A1',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: _textoSecundario,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFFAFAFC),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFEEEAF6)),
          ),
          child: Column(
            children: [
              // Upload cert
              InkWell(
                onTap: _anexarCertificado,
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  decoration: BoxDecoration(
                    color: _certificadoAnexado
                        ? _verdeFundo
                        : const Color(0xFFF8F8FC),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: _certificadoAnexado
                          ? _verdeStatus.withValues(alpha: 0.3)
                          : const Color(0xFFE9E8F0),
                      style: _certificadoAnexado
                          ? BorderStyle.solid
                          : BorderStyle.solid,
                    ),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        _certificadoAnexado
                            ? Icons.description_rounded
                            : Icons.upload_file_rounded,
                        size: 28,
                        color: _certificadoAnexado
                            ? _verdeStatus
                            : _roxoPrimario,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _certificadoAnexado
                            ? _nomeCertificado ?? 'Certificado anexado'
                            : 'Clique para anexar certificado digital (.pfx)',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          color: _certificadoAnexado
                              ? _verdeStatus
                              : _textoSecundario,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_certificadoAnexado) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _senhaCertCtrl,
                  obscureText: true,
                  decoration: _inputDec(
                    'Senha do certificado digital',
                    Icons.lock_rounded,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _campoForm(String label, TextEditingController ctrl, String hint) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: GoogleFonts.plusJakartaSans(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: _textoSecundario)),
        const SizedBox(height: 4),
        TextField(
          controller: ctrl,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: GoogleFonts.plusJakartaSans(
                fontSize: 12, color: _textoSecundario.withValues(alpha: 0.5)),
            filled: true,
            fillColor: Colors.white,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFFE9E8F0)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFFE9E8F0)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide:
                  const BorderSide(color: _roxoPrimario, width: 1.5),
            ),
          ),
          style: GoogleFonts.plusJakartaSans(
              fontSize: 13, color: _textoPrimario),
        ),
      ],
    );
  }

  Widget _campoCnpj(String label, TextEditingController ctrl) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: GoogleFonts.plusJakartaSans(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: _textoSecundario)),
        const SizedBox(height: 4),
        TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            _CnpjInputFormatter(),
          ],
          decoration: InputDecoration(
            hintText: '00.000.000/0000-00',
            hintStyle: GoogleFonts.plusJakartaSans(
                fontSize: 12, color: _textoSecundario.withValues(alpha: 0.5)),
            prefixIcon: const Icon(Icons.badge_rounded,
                size: 18, color: _roxoPrimario),
            filled: true,
            fillColor: Colors.white,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFFE9E8F0)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFFE9E8F0)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide:
                  const BorderSide(color: _roxoPrimario, width: 1.5),
            ),
          ),
          style: GoogleFonts.plusJakartaSans(
              fontSize: 13, color: _textoPrimario),
        ),
      ],
    );
  }

  InputDecoration _inputDec(String hint, IconData icon) {
    return InputDecoration(
      hintText: hint,
      hintStyle: GoogleFonts.plusJakartaSans(
          fontSize: 12, color: _textoSecundario.withValues(alpha: 0.5)),
      prefixIcon: Icon(icon, size: 18, color: _roxoPrimario),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFFE9E8F0)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFFE9E8F0)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: _roxoPrimario, width: 1.5),
      ),
    );
  }

  InputDecoration _inputDecRegime() {
    return InputDecoration(
      hintText: 'Regime tributário',
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      prefixIcon:
          const Icon(Icons.account_balance_rounded, size: 18, color: _roxoPrimario),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFFE9E8F0)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFFE9E8F0)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: _roxoPrimario, width: 1.5),
      ),
    );
  }

  Future<void> _anexarCertificado() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pfx', 'p12'],
        allowMultiple: false,
      );
      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        setState(() {
          _certificadoAnexado = true;
          _nomeCertificado = file.name;
          _certificadoBytes = file.bytes;
        });
      }
    } catch (e) {
      debugPrint('[NovaIntegracaoLojista] Erro ao selecionar certificado: $e');
    }
  }

  Future<void> _mostrarSelecionarProvedor() async {
    final provedor = await showDialog<FiscalIntegrationModel>(
      context: context,
      barrierDismissible: true,
      builder: (_) => const _SelecionarProvedorDialog(),
    );
    if (provedor != null) {
      setState(() => _provedorSelecionado = provedor);
    }
  }

  Future<void> _mostrarConfirmacao() async {
    final l = _lojistaSelecionado;
    if (l == null || _provedorSelecionado == null) return;

    // ─── Validação de todos os campos obrigatórios ───
    final erros = <String>[];
    if (_razaoSocialCtrl.text.trim().isEmpty) erros.add('Razão Social');
    if (_cnpjCtrl.text.replaceAll(RegExp(r'\D'), '').length < 14) erros.add('CNPJ');
    if (!_ieIsento && _ieCtrl.text.trim().isEmpty) erros.add('Inscrição Estadual');
    if (_cepCtrl.text.trim().isEmpty) erros.add('CEP');
    if (_logradouroCtrl.text.trim().isEmpty) erros.add('Logradouro');
    if (_numeroCtrl.text.trim().isEmpty) erros.add('Número');
    if (_bairroCtrl.text.trim().isEmpty) erros.add('Bairro');
    if (_cidadeCtrl.text.trim().isEmpty) erros.add('Cidade');
    if (_ufCtrl.text.trim().isEmpty) erros.add('UF');
    if (_regimeTributario.isEmpty) erros.add('Regime Tributário');
    final cnae = _cnaeCtrl.text.trim();
    if (cnae.length < 7 || !RegExp(r'^\d{7}$').hasMatch(cnae)) erros.add('CNAE (7 dígitos)');
    final codCidade = _codigoCidadeCtrl.text.trim();
    if (codCidade.length < 7 || !RegExp(r'^\d{7}$').hasMatch(codCidade)) erros.add('Código IBGE (7 dígitos)');

    if (erros.isNotEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Campos obrigatórios pendentes: ${erros.join(', ')}.\n'
            'Preencha todos os campos antes de continuar.',
          ),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 6),
        ),
      );
      return;
    }

    final confirmou = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (_) => _ConfirmarIntegracaoDialog(
        lojistaNome: l.nome,
        lojistaCpfCnpj: l.cpfCnpj ?? '—',
        planoNome: l.planoNome,
        provedorNome: _provedorSelecionado!.nomeExibicao,
        limiteMensal: int.tryParse(_limiteCtrl.text.trim()) ?? 0,
        temCertificado: _certificadoAnexado,
      ),
    );
    if (confirmou == true) {
      await _salvarIntegracao();
    }
  }

  Future<void> _salvarIntegracao() async {
    setState(() => _salvando = true);
    try {
      final agora = DateTime.now();
      final proxMes = DateTime(agora.year, agora.month + 1, agora.day);
      final l = _lojistaSelecionado!;
      final limite = int.tryParse(_limiteCtrl.text.trim()) ?? 0;

      await LojistaIntegracaoService.criarIntegracao(
        LojistaIntegracaoModel(
          id: '',
          storeId: l.storeId,
          storeNome: l.nome,
          storeEmail: l.email,
          planoId: '',
          planoNome: l.planoNome,
          limiteMensal: limite,
          notasEmitidas: 0,
          cicloRef: DateFormat('yyyy-MM').format(agora),
          proximaRenovacao: Timestamp.fromDate(proxMes),
          status: 'ativa',
          observacao:
              'Provedor: ${_provedorSelecionado!.nomeExibicao} (${_provedorSelecionado!.id})',
        ),
      );

      // Monta company_tax_data do formulário
      final razao = _razaoSocialCtrl.text.trim();
      final fantasia = _nomeFantasiaCtrl.text.trim();
      final cnpj = _cnpjCtrl.text.replaceAll(RegExp(r'\D'), '');
      final ie = _ieCtrl.text.trim();
      final cep = _cepCtrl.text.trim();
      final logradouro = _logradouroCtrl.text.trim();
      final numero = _numeroCtrl.text.trim();
      final complemento = _complementoCtrl.text.trim();
      final bairro = _bairroCtrl.text.trim();
      final cidade = _cidadeCtrl.text.trim();
      final codigoCidade = _codigoCidadeCtrl.text.trim();
      final uf = _ufCtrl.text.trim();
      final cnae = _cnaeCtrl.text.trim();
      final regime = _regimeTributario;
      final crt = _crtDoRegime(regime);

      final companyTaxData = <String, dynamic>{
        'razao_social': razao,
        'nome_fantasia': fantasia,
        'cnpj': cnpj,
        'ie': ie,
        if (_ieIsento) 'ie_isento': true,
        'cep': cep,
        'logradouro': logradouro,
        'numero': numero,
        if (complemento.isNotEmpty) 'complemento': complemento,
        'bairro': bairro,
        'cidade': cidade,
        'uf': uf,
        if (codigoCidade.isNotEmpty) 'codigo_cidade': codigoCidade,
        'cnae': cnae,
        'regime_tributario': regime,
        'crt': crt,
      };

      // Monta nfe_settings com ambiente
      final envProvedor = _provedorSelecionado!.environment;
      final nfeSettings = <String, dynamic>{
        'environment': envProvedor == 'production' ? 'production' : 'sandbox',
      };

      // Certificado (base64 + senha)
      String? certEncrypted;
      if (_certificadoBytes != null && _certificadoBytes!.isNotEmpty) {
        final senha = _senhaCertCtrl.text.trim();
        certEncrypted = '${base64Encode(_certificadoBytes!)}::$senha';
      }

      // Sincroniza configurações fiscais com todos os dados
      await FiscalIntegrationsService.salvarOuAtualizarSettings(
        storeId: l.storeId,
        integrationId: _provedorSelecionado!.id,
        enableNfe: true,
        status: 'active',
        companyTaxData: razao.isNotEmpty || cnpj.isNotEmpty
            ? companyTaxData
            : null,
        nfeSettings: nfeSettings,
        certificateDataEncrypted: certEncrypted,
      );

      widget.onSalvar?.call();
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      debugPrint('[NovaIntegracaoLojista] Erro ao salvar: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao criar integração: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  Widget _linhaResumo(String label, String valor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                color: _textoSecundario,
              ),
            ),
          ),
          Expanded(
            child: Text(
              valor,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: _textoPrimario,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dialogFooter() {
    final passo0 = _passo == 0;
    final podeAvancar = passo0
        ? _lojistaSelecionado != null
        : _provedorSelecionado != null &&
            _razaoSocialCtrl.text.trim().isNotEmpty &&
            _cnpjCtrl.text.trim().isNotEmpty;
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 14, 24, 18),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFFEEEAF6))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          if (_passo > 0)
            TextButton(
              onPressed: () {
                setState(() {
                  _passo--;
                  _provedorSelecionado = null;
                });
              },
              child: Row(
                children: [
                  const Icon(
                    Icons.arrow_back_rounded,
                    size: 14,
                    color: _textoSecundario,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Voltar',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      color: _textoSecundario,
                    ),
                  ),
                ],
              ),
            )
          else
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                'Cancelar',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  color: _textoSecundario,
                ),
              ),
            ),
          Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              onTap: !podeAvancar || _salvando
                  ? null
                  : passo0
                      ? _avancar
                      : _mostrarConfirmacao,
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 11,
                ),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [_roxoPrimario, _roxoClaro],
                  ),
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: _roxoPrimario.withValues(alpha: 0.25),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: _salvando
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        passo0 ? 'Continuar' : 'Criar Integração',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _avancar() async {
    if (_passo == 0) {
      setState(() => _passo++);
      return;
    }
  }
}

/// Formatador de CNPJ: 00.000.000/0000-00
class _CnpjInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    if (digits.length > 14) return oldValue;

    final buf = StringBuffer();
    for (int i = 0; i < digits.length; i++) {
      if (i == 2 || i == 5) buf.write('.');
      if (i == 8) buf.write('/');
      if (i == 12) buf.write('-');
      buf.write(digits[i]);
    }
    final formatted = buf.toString();
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

class _LojistaOption {
  final String storeId;
  final String nome;
  final String email;
  final String? avatar;
  final String? cpfCnpj;
  final String planoNome;
  const _LojistaOption({
    required this.storeId,
    required this.nome,
    required this.email,
    this.avatar,
    this.cpfCnpj,
    required this.planoNome,
  });
}

// ═══════════════════════════════════════════════════════════════
// MODAL — SELEÇÃO DE PROVEDOR FISCAL
// ═══════════════════════════════════════════════════════════════
class _SelecionarProvedorDialog extends StatefulWidget {
  const _SelecionarProvedorDialog();

  @override
  State<_SelecionarProvedorDialog> createState() =>
      _SelecionarProvedorDialogState();
}

class _SelecionarProvedorDialogState
    extends State<_SelecionarProvedorDialog> {
  List<FiscalIntegrationModel> _provedores = [];
  bool _carregando = true;

  // ── Busca ──
  final _searchCtrl = TextEditingController();
  final _searchFocus = FocusNode();
  String _searchQuery = '';

  // ── Paginação ──
  int _paginaAtual = 0;
  static const int _itensPorPagina = 5;

  List<FiscalIntegrationModel> get _filtrados {
    if (_searchQuery.isEmpty) return _provedores;
    final q = _searchQuery.toLowerCase();
    return _provedores.where((p) {
      return p.nomeExibicao.toLowerCase().contains(q);
    }).toList();
  }

  List<FiscalIntegrationModel> get _paginaAtualLista {
    final start = _paginaAtual * _itensPorPagina;
    final end = start + _itensPorPagina;
    if (start >= _filtrados.length) return [];
    return _filtrados.sublist(start, end.clamp(0, _filtrados.length));
  }

  int get _totalPaginas =>
      _filtrados.isEmpty
          ? 1
          : (_filtrados.length / _itensPorPagina).ceil();

  bool get _temProxima => _paginaAtual < _totalPaginas - 1;
  bool get _temAnterior => _paginaAtual > 0;

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(_onSearchChanged);
    _carregar();
  }

  void _onSearchChanged() {
    setState(() {
      _searchQuery = _searchCtrl.text;
      _paginaAtual = 0;
    });
  }

  Future<void> _carregar() async {
    try {
      // Busca todos (sem where + orderBy, que exigiria índice composto)
      // e filtra client-side por status == 'active'
      final snap = await FirebaseFirestore.instance
          .collection('fiscal_integrations')
          .orderBy('created_at', descending: true)
          .get();
      if (mounted) {
        setState(() {
          _provedores = snap.docs
              .map(FiscalIntegrationModel.fromFirestore)
              .where((p) => p.status == 'active')
              .toList();
          _carregando = false;
        });
      }
    } catch (e) {
      debugPrint('[SelecionarProvedor] Erro ao carregar: $e');
      if (mounted) setState(() => _carregando = false);
    }
  }

  @override
  void dispose() {
    _searchCtrl.removeListener(_onSearchChanged);
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 80, vertical: 60),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: 520,
        constraints: const BoxConstraints(maxHeight: 620),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          children: [
            // ── Header ──
            Container(
              padding: const EdgeInsets.fromLTRB(28, 22, 20, 14),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Color(0xFFEEEAF6))),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Selecionar Provedor Fiscal',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: _textoPrimario,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Escolha o provedor/API fiscal para este lojista.',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            color: _textoSecundario,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded,
                        color: _textoSecundario),
                  ),
                ],
              ),
            ),
            // ── Campo de busca ──
            if (!_carregando && _provedores.isNotEmpty)
              Container(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                child: TextField(
                  controller: _searchCtrl,
                  focusNode: _searchFocus,
                  style: GoogleFonts.plusJakartaSans(fontSize: 13),
                  decoration: InputDecoration(
                    hintText:
                        'Pesquisar integração pelo nome personalizado...',
                    hintStyle: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      color: _textoSecundario.withValues(alpha: 0.6),
                    ),
                    prefixIcon: Icon(Icons.search_rounded,
                        color: _textoSecundario, size: 20),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded,
                                size: 18, color: _textoSecundario),
                            onPressed: () {
                              _searchCtrl.clear();
                              _searchFocus.unfocus();
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: const Color(0xFFF5F4F8),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(
                          color: _roxoPrimario, width: 1.5),
                    ),
                  ),
                  onChanged: (_) {},
                ),
              ),
            // ── Contador de resultados ──
            if (!_carregando &&
                _provedores.isNotEmpty &&
                _searchQuery.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
                child: Text(
                  '${_filtrados.length} resultado${_filtrados.length == 1 ? '' : 's'} encontrado${_filtrados.length == 1 ? '' : 's'}',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: _textoSecundario,
                  ),
                ),
              ),
            // ── Lista / Estados ──
            Expanded(
              child: _carregando
                  ? const Center(child: CircularProgressIndicator())
                  : _provedores.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(32),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.cloud_off_rounded,
                                    size: 48,
                                    color: _textoSecundario
                                        .withValues(alpha: 0.3)),
                                const SizedBox(height: 12),
                                Text(
                                  'Nenhum provedor ativo encontrado',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: _textoSecundario,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Cadastre uma integração na aba "Integrações" primeiro.',
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 12,
                                    color: _textoSecundario,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      : _filtrados.isEmpty
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(32),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.search_off_rounded,
                                        size: 48,
                                        color: _textoSecundario
                                            .withValues(alpha: 0.3)),
                                    const SizedBox(height: 12),
                                    Text(
                                      'Nenhuma integração encontrada com esse nome.',
                                      textAlign: TextAlign.center,
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: _textoSecundario,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          : ListView.separated(
                              padding:
                                  const EdgeInsets.fromLTRB(12, 8, 12, 4),
                              physics:
                                  const NeverScrollableScrollPhysics(),
                              shrinkWrap: true,
                              itemCount: _paginaAtualLista.length,
                              separatorBuilder: (_, _) => Divider(
                                  height: 1,
                                  indent: 56,
                                  endIndent: 16,
                                  color: const Color(0xFFEEEAF6)),
                              itemBuilder: (_, i) =>
                                  _buildProviderCard(_paginaAtualLista[i]),
                            ),
            ),
            // ── Paginação ──
            if (!_carregando &&
                _provedores.isNotEmpty &&
                _filtrados.length > _itensPorPagina)
              Container(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
                decoration: const BoxDecoration(
                  border:
                      Border(top: BorderSide(color: Color(0xFFEEEAF6))),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Anterior
                    InkWell(
                      onTap: _temAnterior
                          ? () =>
                              setState(() => _paginaAtual--)
                          : null,
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: _temAnterior
                              ? _roxoPrimario.withValues(alpha: 0.08)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(Icons.chevron_left_rounded,
                            size: 20,
                            color: _temAnterior
                                ? _roxoPrimario
                                : _textoSecundario
                                    .withValues(alpha: 0.3)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Páginas
                    ...List.generate(_totalPaginas, (i) {
                      final ativa = i == _paginaAtual;
                      return Padding(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 2),
                        child: InkWell(
                          onTap: () =>
                              setState(() => _paginaAtual = i),
                          borderRadius: BorderRadius.circular(8),
                          child: AnimatedContainer(
                            duration:
                                const Duration(milliseconds: 150),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: ativa
                                  ? _roxoPrimario
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '${i + 1}',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: ativa
                                    ? Colors.white
                                    : _textoSecundario,
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                    const SizedBox(width: 8),
                    // Próxima
                    InkWell(
                      onTap: _temProxima
                          ? () =>
                              setState(() => _paginaAtual++)
                          : null,
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: _temProxima
                              ? _roxoPrimario.withValues(alpha: 0.08)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(Icons.chevron_right_rounded,
                            size: 20,
                            color: _temProxima
                                ? _roxoPrimario
                                : _textoSecundario
                                    .withValues(alpha: 0.3)),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildProviderCard(FiscalIntegrationModel p) {
    final info = ProvedorFiscalInfo.provedores
        .where((x) => x.id == p.provider)
        .toList();
    final infoItem = info.isNotEmpty ? info.first : null;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => Navigator.of(context).pop(p),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      _roxoPrimario.withValues(alpha: 0.1),
                      _roxoClaro.withValues(alpha: 0.05),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  infoItem?.icone ?? Icons.cloud_rounded,
                  color: _roxoPrimario,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.nomeExibicao,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: _textoPrimario,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      p.nomeIntegracao != null
                          ? infoItem?.nome ?? p.providerName
                          : (infoItem?.descricao ?? ''),
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11,
                        color: _textoSecundario,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      p.supportedDocuments
                          .map((d) => d.toUpperCase())
                          .join(', '),
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: _roxoBtn,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: p.environment == 'production'
                      ? const Color(0xFFE8F5E9)
                      : const Color(0xFFFFF8E1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  p.environment == 'production' ? 'Produção' : 'Homologação',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: p.environment == 'production'
                        ? const Color(0xFF16A34A)
                        : const Color(0xFFEA580C),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// MODAL — CONFIRMAÇÃO DE INTEGRAÇÃO LOJISTA
// ═══════════════════════════════════════════════════════════════
class _ConfirmarIntegracaoDialog extends StatelessWidget {
  final String lojistaNome;
  final String lojistaCpfCnpj;
  final String planoNome;
  final String provedorNome;
  final int limiteMensal;
  final bool temCertificado;

  const _ConfirmarIntegracaoDialog({
    required this.lojistaNome,
    required this.lojistaCpfCnpj,
    required this.planoNome,
    required this.provedorNome,
    required this.limiteMensal,
    required this.temCertificado,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 80, vertical: 60),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: 480,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(28, 24, 28, 16),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Color(0xFFEEEAF6))),
              ),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [_roxoPrimario, _roxoClaro],
                      ),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.checklist_rounded,
                        color: Colors.white, size: 24),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Confirmar Integração',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: _textoPrimario,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Revise os dados antes de criar a integração.',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            color: _textoSecundario,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Body
            Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFAFAFC),
                      borderRadius: BorderRadius.circular(14),
                      border:
                          Border.all(color: const Color(0xFFEEEAF6)),
                    ),
                    child: Column(
                      children: [
                        _linhaConfirmacao(
                            'Loja', lojistaNome, Icons.store_rounded),
                        _linhaConfirmacao(
                            'CNPJ', lojistaCpfCnpj, Icons.badge_rounded),
                        _linhaConfirmacao('Plano ativo', planoNome,
                            Icons.workspace_premium_rounded),
                        _linhaConfirmacao(
                            'Provedor',
                            provedorNome,
                            Icons.cloud_rounded),
                        _linhaConfirmacao(
                            'Limite NF-e/mês',
                            limiteMensal > 0
                                ? limiteMensal.toString()
                                : 'Ilimitado',
                            Icons.numbers_rounded),
                        _linhaConfirmacao(
                            'Certificado',
                            temCertificado ? 'Anexado' : 'Pendente',
                            temCertificado
                                ? Icons.check_circle_rounded
                                : Icons.warning_amber_rounded,
                            valorCor: temCertificado
                                ? const Color(0xFF16A34A)
                                : const Color(0xFFEA580C)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF8E1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: const Color(0xFFEA580C)
                              .withValues(alpha: 0.2)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.info_rounded,
                            color: Color(0xFFEA580C), size: 18),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'A NF-e será emitida em nome da empresa do '
                            'lojista usando os dados fiscais e certificado '
                            'cadastrados.',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 11,
                              color: const Color(0xFF92400E),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Footer
            Container(
              padding: const EdgeInsets.fromLTRB(24, 14, 24, 18),
              decoration: const BoxDecoration(
                border:
                    Border(top: BorderSide(color: Color(0xFFEEEAF6))),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: Text(
                      'Cancelar',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        color: _textoSecundario,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Material(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                    child: InkWell(
                      onTap: () =>
                          Navigator.of(context).pop(true),
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 11,
                        ),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [_roxoPrimario, _roxoClaro],
                          ),
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: [
                            BoxShadow(
                              color: _roxoPrimario
                                  .withValues(alpha: 0.25),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Text(
                          'Confirmar e Criar',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Widget _linhaConfirmacao(
      String label, String valor, IconData icone,
      {Color? valorCor}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icone, size: 16, color: _textoSecundario),
          const SizedBox(width: 10),
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                color: _textoSecundario,
              ),
            ),
          ),
          Expanded(
            child: Text(
              valor,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: valorCor ?? _textoPrimario,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// MODAL — DETALHE DA INTEGRAÇÃO LOJISTA
// ═══════════════════════════════════════════════════════════════
class _DetalheIntegracaoLojistaDialog extends StatefulWidget {
  final LojistaIntegracaoModel integracao;
  final VoidCallback? onAtualizar;
  final VoidCallback? onExcluir;
  const _DetalheIntegracaoLojistaDialog({
    required this.integracao,
    this.onAtualizar,
    this.onExcluir,
  });

  @override
  State<_DetalheIntegracaoLojistaDialog> createState() =>
      _DetalheIntegracaoLojistaDialogState();
}

class _DetalheIntegracaoLojistaDialogState
    extends State<_DetalheIntegracaoLojistaDialog> {
  List<PlanoEmissaoNfeModel> _planos = [];
  LojistaIntegracaoModel get _i => widget.integracao;
  final fmt = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
  final fmtData = DateFormat('dd/MM/yyyy', 'pt_BR');

  @override
  void initState() {
    super.initState();
    _carregarPlanos();
  }

  Future<void> _carregarPlanos() async {
    final planos = await LojistaIntegracaoService.listarPlanosAtivos();
    if (mounted) setState(() => _planos = planos);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 60, vertical: 50),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: 600,
        constraints: const BoxConstraints(maxHeight: 700),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: _buildBody(),
              ),
            ),
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(28, 22, 20, 14),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFEEEAF6))),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: _i.statusFundo,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.store_rounded, color: _i.statusCor, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _i.storeNome,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: _textoPrimario,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _i.storeEmail ?? '',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    color: _textoSecundario,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded, color: _textoSecundario),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    return Column(
      children: [
        // Status banner
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _i.statusFundo,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _i.statusCor.withValues(alpha: 0.2)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: _i.statusFundo,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: _i.statusCor.withValues(alpha: 0.3),
                  ),
                ),
                child: Text(
                  _i.statusLabel,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: _i.statusCor,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                'ID: ${_i.id.substring(0, 8)}...',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 10,
                  color: _textoSecundario,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        // Plano
        _cardSecao('Plano de emissão', [
          _linhaInfo('Plano contratado', _i.planoNome),
          _linhaInfo('Limite mensal', _i.limiteExibir),
          _linhaInfo(
            'Valor',
            fmt.format(
              _planos.where((p) => p.id == _i.planoId).firstOrNull?.valor ?? 0,
            ),
          ),
        ]),
        const SizedBox(height: 12),
        // Utilização
        _cardSecao('Utilização', [
          _linhaInfo('Notas emitidas', _i.emitidasExibir),
          _linhaInfo('Notas restantes', _i.restantesExibir),
          _linhaInfo(
            'Percentual',
            '${_i.percentualUtilizado.toStringAsFixed(1)}%',
          ),
          if (_i.limiteMensal > 0) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: (_i.notasEmitidas / _i.limiteMensal).clamp(0, 1),
                backgroundColor: const Color(0xFFEEEAF6),
                valueColor: AlwaysStoppedAnimation<Color>(
                  _i.atingiuLimite ? _vermelhoStatus : _roxoPrimario,
                ),
                minHeight: 8,
              ),
            ),
          ],
        ]),
        const SizedBox(height: 12),
        // Ciclo
        _cardSecao('Ciclo', [
          _linhaInfo('Ciclo atual', _i.cicloRef),
          _linhaInfo(
            'Próxima renovação',
            _i.proximaRenovacao != null
                ? fmtData.format(_i.proximaRenovacao!.toDate())
                : '—',
          ),
        ]),
        if (_i.atingiuLimite) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF2F2),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _vermelhoStatus.withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.warning_amber_rounded,
                  color: _vermelhoStatus,
                  size: 22,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Limite mensal atingido',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: _vermelhoStatus,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Foram utilizadas todas as ${_i.limiteExibir} notas do plano ${_i.planoNome}. Contrate um plano superior para continuar emitindo.',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 11,
                          color: _textoSecundario,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _cardSecao(String titulo, List<Widget> children) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFEEEAF6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            titulo,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: _roxoPrimario,
            ),
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }

  Widget _linhaInfo(String label, String valor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                color: _textoSecundario,
              ),
            ),
          ),
          Expanded(
            child: Text(
              valor,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: _textoPrimario,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 14, 24, 18),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFFEEEAF6))),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _btnFooter('Dados fiscais', _roxoPrimario, () => _editarDadosFiscais()),
          if (_i.estaAtiva)
            _btnFooter('Suspender', _laranjaStatus, () => _suspender()),
          if (_i.estaSuspensa)
            _btnFooter('Reativar', _verdeStatus, () => _reativar()),
          _btnFooter('Testar conexão', _roxoPrimario, () => _testarConexao()),
          _btnFooter('Alterar plano', _roxoPrimario, () => _alterarPlano()),
          _btnFooter('Excluir', _vermelhoStatus, () => _excluir()),
        ],
      ),
    );
  }

  Widget _btnFooter(String label, Color cor, VoidCallback onTap) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: cor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: cor.withValues(alpha: 0.25)),
          ),
          child: Text(
            label,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: cor,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _testarConexao() async {
    if (!mounted) return;
    await mostrarTesteConexaoPremium(
      context,
      provedor: _i.planoNome,
      testar: () async {
        // ─── Teste REAL na API do provedor fiscal ───
        // Busca a store_fiscal_settings da loja para encontrar
        // a integração fiscal real vinculada a este lojista.
        try {
          final db = FirebaseFirestore.instance;
          final providerService = FiscalProviderService.instance;

          // 1. Busca store_fiscal_settings da loja
          final settingsSnap = await db
              .collection('store_fiscal_settings')
              .where('store_id', isEqualTo: _i.storeId)
              .limit(1)
              .get();

          if (settingsSnap.docs.isEmpty) {
            return TestConexaoResultado(
              sucesso: false,
              provedor: _i.planoNome,
              mensagem:
                  'Nenhuma configuração fiscal encontrada para esta loja.',
              errosDetalhados: [
                'store_id=${_i.storeId}',
                'Configure a integração fiscal no Admin.',
              ],
            );
          }

          final settingsData = settingsSnap.docs.first.data();
          final integrationId =
              settingsData['integration_id'] as String? ?? '';

          if (integrationId.isEmpty) {
            return TestConexaoResultado(
              sucesso: false,
              provedor: _i.planoNome,
              mensagem:
                  'Nenhuma integração fiscal vinculada a esta loja.',
              errosDetalhados: [
                'store_id=${_i.storeId}',
                'A loja não possui integration_id em store_fiscal_settings.',
              ],
            );
          }

          // 2. Busca a integração fiscal real pelo ID
          final integracaoDoc = await db
              .collection('fiscal_integrations')
              .doc(integrationId)
              .get();

          if (!integracaoDoc.exists) {
            return TestConexaoResultado(
              sucesso: false,
              provedor: _i.planoNome,
              mensagem: 'Integração fiscal não encontrada.',
              errosDetalhados: ['ID da integração: $integrationId'],
            );
          }

          final integracaoData = integracaoDoc.data()!;
          final providerId =
              integracaoData['provider'] as String? ?? '';

          // 3. Resolve o provider fiscal pelo ID real
          final provider = providerService.obterProvider(providerId);
          if (provider == null) {
            return TestConexaoResultado(
              sucesso: false,
              provedor: _i.planoNome,
              mensagem:
                  'Provedor fiscal "$providerId" não encontrado.',
              errosDetalhados: [
                'Provider ID: $providerId',
                'Nenhum provider registrado com este ID.',
              ],
            );
          }

          // 4. Extrai configuração e testa
          final config = providerService.extrairConfig(
            integracaoData,
            integrationId: integrationId,
          );

          final sucesso = await provider.testarConexao(config);

          if (sucesso) {
            return TestConexaoResultado(
              sucesso: true,
              provedor: _i.planoNome,
              mensagem: 'Credenciais validadas com sucesso no ambiente '
                  '${integracaoData['environment'] == 'production' ? 'Produção' : 'Homologação'}.',
              ambiente: integracaoData['environment'] == 'production'
                  ? 'Produção'
                  : 'Homologação',
            );
          }

          return TestConexaoResultado(
            sucesso: false,
            provedor: _i.planoNome,
            mensagem:
                'Token inválido ou sem permissão para este ambiente.',
            errosDetalhados: [
              'Provider: ${provider.nome}',
              'Ambiente: ${integracaoData['environment'] ?? 'sandbox'}',
            ],
          );
        } catch (e) {
          return TestConexaoResultado(
            sucesso: false,
            provedor: _i.planoNome,
            mensagem:
                'Não foi possível conectar ao provedor fiscal no momento.',
            errosDetalhados: [e.toString()],
          );
        }
      },
    );
  }

  Future<void> _suspender() async {
    await LojistaIntegracaoService.suspenderIntegracao(_i.id);
    widget.onAtualizar?.call();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _reativar() async {
    await LojistaIntegracaoService.reativarIntegracao(_i.id);
    widget.onAtualizar?.call();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _alterarPlano() async {
    final planos = _planos
        .where((p) => p.id != _i.planoId)
        .map(
          (p) => DropdownMenuItem(
            value: p,
            child: Text(
              '${p.nome} · ${p.limiteExibir} notas',
              style: GoogleFonts.plusJakartaSans(fontSize: 13),
            ),
          ),
        )
        .toList();
    if (planos.isEmpty) return;
    final selecionado = await showDialog<PlanoEmissaoNfeModel>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(
          'Alterar plano',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        children: _planos
            .where((p) => p.id != _i.planoId)
            .map(
              (p) => SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, p),
                child: ListTile(
                  dense: true,
                  title: Text(
                    p.nome,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    '${p.limiteExibir} notas/mês',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      color: _textoSecundario,
                    ),
                  ),
                ),
              ),
            )
            .toList(),
      ),
    );
    if (selecionado == null || !mounted) return;
    await LojistaIntegracaoService.alterarPlano(
      _i.id,
      selecionado.id,
      selecionado.nome,
      selecionado.limiteNotas,
    );
    widget.onAtualizar?.call();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _excluir() async {
    final confirmou = await _confirmarAcao(
      context: context,
      icone: Icons.delete_forever_rounded,
      corIcone: _vermelhoStatus,
      titulo: 'Excluir integração?',
      mensagem:
          'Tem certeza que deseja excluir a integração de "${_i.storeNome}"?',
      textoConfirmar: 'Sim, excluir',
    );
    if (confirmou != true || !mounted) return;
    await LojistaIntegracaoService.excluirIntegracao(_i.id);
    widget.onExcluir?.call();
    if (mounted) Navigator.of(context).pop();
  }

  // ─── Helpers de campo para o editor fiscal ────────────────
  Widget _campoEdit(
      String label, TextEditingController ctrl, String hint) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: GoogleFonts.plusJakartaSans(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: _textoSecundario)),
        const SizedBox(height: 4),
        TextField(
          controller: ctrl,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                color: _textoSecundario.withValues(alpha: 0.5)),
            filled: true,
            fillColor: Colors.white,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFFE9E8F0)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFFE9E8F0)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide:
                  const BorderSide(color: _roxoPrimario, width: 1.5),
            ),
          ),
          style: GoogleFonts.plusJakartaSans(
              fontSize: 13, color: _textoPrimario),
        ),
      ],
    );
  }

  Widget _campoEditCnpj(String label, TextEditingController ctrl) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: GoogleFonts.plusJakartaSans(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: _textoSecundario)),
        const SizedBox(height: 4),
        TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            _CnpjInputFormatter(),
          ],
          decoration: InputDecoration(
            hintText: '00.000.000/0000-00',
            hintStyle: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                color: _textoSecundario.withValues(alpha: 0.5)),
            prefixIcon: const Icon(Icons.badge_rounded,
                size: 18, color: _roxoPrimario),
            filled: true,
            fillColor: Colors.white,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFFE9E8F0)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFFE9E8F0)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide:
                  const BorderSide(color: _roxoPrimario, width: 1.5),
            ),
          ),
          style: GoogleFonts.plusJakartaSans(
              fontSize: 13, color: _textoPrimario),
        ),
      ],
    );
  }

  // ─── Editar dados fiscais da integração ───────────────────
  Future<void> _editarDadosFiscais() async {
    final storeId = _i.storeId;

    // Carrega dados existentes
    Map<String, dynamic>? existingSettings;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('store_fiscal_settings')
          .where('store_id', isEqualTo: storeId)
          .limit(1)
          .get();
      if (snap.docs.isNotEmpty) {
        existingSettings = snap.docs.first.data();
      }
    } catch (_) {}

    final existingTax = existingSettings?['company_tax_data']
        as Map<String, dynamic>?;

    // Controllers pré-preenchidos
    final razaoCtrl = TextEditingController(
        text: existingTax?['razao_social'] as String? ?? '');
    final fantasiaCtrl = TextEditingController(
        text: existingTax?['nome_fantasia'] as String? ?? '');
    final cnpjCtrl = TextEditingController(
        text: existingTax?['cnpj'] as String? ?? '');
    final ieCtrl = TextEditingController(
        text: existingTax?['ie'] as String? ?? '');
    final cepCtrl = TextEditingController(
        text: existingTax?['cep'] as String? ?? '');
    final logradouroCtrl = TextEditingController(
        text: existingTax?['logradouro'] as String? ?? '');
    final numeroCtrl = TextEditingController(
        text: existingTax?['numero'] as String? ?? '');
    final complementoCtrl = TextEditingController(
        text: existingTax?['complemento'] as String? ?? '');
    final bairroCtrl = TextEditingController(
        text: existingTax?['bairro'] as String? ?? '');
    final cidadeCtrl = TextEditingController(
        text: existingTax?['cidade'] as String? ?? '');
    final codigoCidadeCtrl = TextEditingController(
        text: existingTax?['codigo_cidade'] as String? ?? '');
    final ufCtrl = TextEditingController(
        text: (existingTax?['uf'] as String? ?? '').toUpperCase());
    final cnaeCtrl = TextEditingController(
        text: existingTax?['cnae'] as String? ?? '');
    String regime = existingTax?['regime_tributario'] as String? ??
        'Simples Nacional';
    bool certificadoAnexado = false;
    String? nomeCertificado;
    Uint8List? certificadoBytes;
    final senhaCertCtrl = TextEditingController();

    if (!mounted) return;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDiaState) => Dialog(
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 60, vertical: 50),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20)),
          child: Container(
            width: 560,
            constraints: const BoxConstraints(maxHeight: 720),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              children: [
                // Header
                Container(
                  padding:
                      const EdgeInsets.fromLTRB(28, 22, 20, 14),
                  decoration: const BoxDecoration(
                    border: Border(
                        bottom:
                            BorderSide(color: Color(0xFFEEEAF6))),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Dados Fiscais — ${_i.storeNome}',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: _textoPrimario,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(ctx),
                        icon: const Icon(Icons.close_rounded,
                            color: _textoSecundario),
                      ),
                    ],
                  ),
                ),
                // Body
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        _campoEdit('Razão Social', razaoCtrl,
                            'Razão social da empresa'),
                        const SizedBox(height: 12),
                        _campoEdit('Nome Fantasia',
                            fantasiaCtrl, 'Nome fantasia'),
                        const SizedBox(height: 12),
                        _campoEditCnpj(
                            'CNPJ', cnpjCtrl),
                        const SizedBox(height: 12),
                        _campoEdit(
                            'Inscrição Estadual', ieCtrl, 'IE'),
                        const SizedBox(height: 12),
                        _campoEdit('CEP', cepCtrl, '00000-000'),
                        const SizedBox(height: 12),
                        _campoEdit('Logradouro', logradouroCtrl, 'Rua, Avenida...'),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(flex: 2, child: _campoEdit('Número', numeroCtrl, 'Nº')),
                            const SizedBox(width: 12),
                            Expanded(flex: 3, child: _campoEdit('Complemento', complementoCtrl, 'Apto, Bloco (opcional)')),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _campoEdit('Bairro', bairroCtrl, 'Bairro'),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(flex: 3, child: _campoEdit('Cidade', cidadeCtrl, 'Município')),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 1,
                              child: DropdownButtonFormField<String>(
                                value: ufCtrl.text.isNotEmpty && _NovaIntegracaoLojistaDialogState._ufs.contains(ufCtrl.text)
                                    ? ufCtrl.text : null,
                                decoration: const InputDecoration(
                                  labelText: 'UF',
                                  filled: true,
                                  fillColor: Color(0xFFF8F8FC),
                                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  border: OutlineInputBorder(),
                                ),
                                items: _NovaIntegracaoLojistaDialogState._ufs.map((uf) => DropdownMenuItem(
                                  value: uf,
                                  child: Text(uf, style: const TextStyle(fontSize: 13)),
                                )).toList(),
                                onChanged: (v) { if (v != null) setDiaState(() => ufCtrl.text = v); },
                                style: GoogleFonts.plusJakartaSans(fontSize: 13, color: _textoPrimario),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _campoEdit('Código IBGE do Município', codigoCidadeCtrl, '7 dígitos'),
                        const SizedBox(height: 12),
                        _campoEdit('CNAE', cnaeCtrl, 'Código CNAE de 7 dígitos'),
                        const SizedBox(height: 12),
                        // Regime
                        DropdownButtonFormField<String>(
                          value: regime,
                          decoration: const InputDecoration(
                            labelText: 'Regime Tributário',
                            filled: true,
                            fillColor: Color(0xFFF8F8FC),
                            contentPadding: EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                            border: OutlineInputBorder(),
                          ),
                          items: _NovaIntegracaoLojistaDialogState._regimes
                              .map((r) => DropdownMenuItem(
                                    value: r,
                                    child: Text(r,
                                        style: const TextStyle(
                                            fontSize: 13)),
                                  ))
                              .toList(),
                          onChanged: (v) {
                            if (v != null) {
                              setDiaState(
                                  () => regime = v);
                            }
                          },
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 13,
                            color: _textoPrimario,
                          ),
                        ),
                        const SizedBox(height: 20),
                        // Certificado
                        Text(
                          'Certificado Digital A1',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: _textoSecundario,
                          ),
                        ),
                        const SizedBox(height: 8),
                        InkWell(
                          onTap: () async {
                            final result =
                                await FilePicker.platform
                                    .pickFiles(
                              type: FileType.custom,
                              allowedExtensions: ['pfx', 'p12'],
                              allowMultiple: false,
                            );
                            if (result != null &&
                                result.files.isNotEmpty) {
                              final file = result.files.first;
                              setDiaState(() {
                                certificadoAnexado = true;
                                nomeCertificado = file.name;
                                certificadoBytes = file.bytes;
                              });
                            }
                          },
                          borderRadius:
                              BorderRadius.circular(10),
                          child: Container(
                            width: double.infinity,
                            padding:
                                const EdgeInsets.symmetric(
                                    vertical: 20),
                            decoration: BoxDecoration(
                              color: certificadoAnexado
                                  ? const Color(0xFFE8F5E9)
                                  : const Color(0xFFF8F8FC),
                              borderRadius:
                                  BorderRadius.circular(10),
                              border: Border.all(
                                color: certificadoAnexado
                                    ? const Color(0xFF22C55E)
                                        .withValues(alpha: 0.3)
                                    : const Color(0xFFE9E8F0),
                              ),
                            ),
                            child: Column(
                              children: [
                                Icon(
                                  certificadoAnexado
                                      ? Icons
                                          .description_rounded
                                      : Icons
                                          .upload_file_rounded,
                                  size: 28,
                                  color: certificadoAnexado
                                      ? const Color(
                                          0xFF22C55E)
                                      : _roxoPrimario,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  certificadoAnexado
                                      ? nomeCertificado ??
                                          'Certificado anexado'
                                      : 'Clique para anexar (.pfx)',
                                  textAlign: TextAlign.center,
                                  style:
                                      GoogleFonts.plusJakartaSans(
                                    fontSize: 12,
                                    color: certificadoAnexado
                                        ? const Color(
                                            0xFF22C55E)
                                        : _textoSecundario,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (certificadoAnexado) ...[
                          const SizedBox(height: 12),
                          TextField(
                            controller: senhaCertCtrl,
                            obscureText: true,
                            decoration: const InputDecoration(
                              labelText:
                                  'Senha do certificado',
                              filled: true,
                              fillColor: Color(0xFFF8F8FC),
                              contentPadding:
                                  EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 10),
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                // Footer com Salvar
                Container(
                  padding:
                      const EdgeInsets.fromLTRB(24, 14, 24, 18),
                  decoration: const BoxDecoration(
                    border: Border(
                        top: BorderSide(
                            color: Color(0xFFEEEAF6))),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: Text('Cancelar'),
                      ),
                      const SizedBox(width: 8),
                      Material(
                        color: Colors.transparent,
                        borderRadius:
                            BorderRadius.circular(10),
                        child: InkWell(
                          onTap: () async {
                            final ie = ieCtrl.text.trim();
                            final cep = cepCtrl.text.trim();
                            final logradouro = logradouroCtrl.text.trim();
                            final numero = numeroCtrl.text.trim();
                            final bairro = bairroCtrl.text.trim();
                            final cidade = cidadeCtrl.text.trim();
                            final uf = ufCtrl.text.trim();
                            final razao =
                                razaoCtrl.text.trim();
                            final cnpj = cnpjCtrl.text
                                .replaceAll(RegExp(r'\D'), '');
                            final erros = <String>[];
                            if (razao.isEmpty) erros.add('Razão Social');
                            if (cnpj.length < 14) erros.add('CNPJ');
                            if (ie.isEmpty) erros.add('IE');
                            if (cep.isEmpty) erros.add('CEP');
                            if (logradouro.isEmpty) erros.add('Logradouro');
                            if (numero.isEmpty) erros.add('Número');
                            if (bairro.isEmpty) erros.add('Bairro');
                            if (cidade.isEmpty) erros.add('Cidade');
                            if (uf.isEmpty) erros.add('UF');
                            final cnae = cnaeCtrl.text.trim();
                            if (cnae.length < 7 || !RegExp(r'^\d{7}$').hasMatch(cnae)) erros.add('CNAE (7 dígitos)');
                            final codCid = codigoCidadeCtrl.text.trim();
                            if (codCid.length < 7 || !RegExp(r'^\d{7}$').hasMatch(codCid)) erros.add('Código IBGE (7 dígitos)');
                            if (erros.isNotEmpty) {
                              ScaffoldMessenger.of(context)
                                  .showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'Campos obrigatórios pendentes: ${erros.join(', ')}.'),
                                  backgroundColor: Colors.red.shade700,
                                  behavior: SnackBarBehavior.floating,
                                  duration: const Duration(seconds: 6),
                                ),
                              );
                              return;
                            }
                            // Monta company_tax_data
                            final companyTaxData = <String, dynamic>{
                              'razao_social': razao,
                              'nome_fantasia': fantasiaCtrl.text.trim(),
                              'cnpj': cnpj,
                              'ie': ieCtrl.text.trim(),
                              'cep': cepCtrl.text.trim(),
                              'logradouro': logradouroCtrl.text.trim(),
                              'numero': numeroCtrl.text.trim(),
                              if (complementoCtrl.text.trim().isNotEmpty) 'complemento': complementoCtrl.text.trim(),
                              'bairro': bairroCtrl.text.trim(),
                              'cidade': cidadeCtrl.text.trim(),
                              'uf': ufCtrl.text.trim(),
                              if (codigoCidadeCtrl.text.trim().isNotEmpty) 'codigo_cidade': codigoCidadeCtrl.text.trim(),
                              'cnae': cnaeCtrl.text.trim(),
                              'regime_tributario': regime,
                              'crt': _NovaIntegracaoLojistaDialogState._crtDoRegime(regime),
                            };
                            // Certificado
                            String? certEncrypted;
                            if (certificadoBytes != null &&
                                certificadoBytes!
                                    .isNotEmpty) {
                              certEncrypted =
                                  '${base64Encode(certificadoBytes!)}::${senhaCertCtrl.text.trim()}';
                            }
                            // Guarda referências antes do await
                            final scaffold =
                                ScaffoldMessenger.of(context);
                            final onAtualizar =
                                widget.onAtualizar;
                            // Preserva nfe_settings existente (environment nunca é perdido)
                            final nfeSettingsExistente = existingSettings?['nfe_settings'] as Map<String, dynamic>?;
                            await FiscalIntegrationsService
                                .salvarOuAtualizarSettings(
                              storeId: storeId,
                              integrationId:
                                  existingSettings?[
                                          'integration_id']
                                      as String?,
                              enableNfe: true,
                              status: 'active',
                              companyTaxData: companyTaxData,
                              nfeSettings: nfeSettingsExistente,
                              certificateDataEncrypted:
                                  certEncrypted,
                            );
                            if (ctx.mounted) {
                              Navigator.pop(ctx);
                              scaffold.showSnackBar(
                                const SnackBar(
                                  content: Text(
                                      'Dados fiscais salvos com sucesso!'),
                                  backgroundColor:
                                      Color(0xFF22C55E),
                                  behavior:
                                      SnackBarBehavior
                                          .floating,
                                ),
                              );
                            }
                            onAtualizar?.call();
                          },
                          borderRadius:
                              BorderRadius.circular(10),
                          child: Container(
                            padding: const EdgeInsets
                                .symmetric(
                              horizontal: 24,
                              vertical: 11,
                            ),
                            decoration: BoxDecoration(
                              gradient:
                                  const LinearGradient(
                                colors: [
                                  _roxoPrimario,
                                  _roxoClaro
                                ],
                              ),
                              borderRadius:
                                  BorderRadius.circular(10),
                            ),
                            child: Text(
                              'Salvar',
                              style:
                                  GoogleFonts.plusJakartaSans(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Helpers de UI para Configurações de Cobranças ──────────

InputDecoration _inputDeco(String hint) {
  return InputDecoration(
    hintText: hint,
    hintStyle: GoogleFonts.plusJakartaSans(fontSize: 13, color: _textoDescricao),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: _bordaInput),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: _bordaInput),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: _roxoPrimario, width: 1.5),
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    isDense: true,
    filled: true,
    fillColor: Colors.white,
  );
}

class _SurfaceCard extends StatelessWidget {
  const _SurfaceCard({
    required this.titulo,
    required this.icone,
    required this.corIcone,
    required this.children,
  });

  final String titulo;
  final IconData icone;
  final Color corIcone;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: _roxoPrimario.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: corIcone.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icone, size: 18, color: corIcone),
              ),
              const SizedBox(width: 12),
              Text(
                titulo,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: _textoPrimario,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }
}

class _SwitchTile extends StatelessWidget {
  const _SwitchTile({
    required this.titulo,
    required this.descricao,
    required this.valor,
    required this.onChanged,
  });

  final String titulo;
  final String descricao;
  final bool valor;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titulo,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: _textoPrimario,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  descricao,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    color: _textoDescricao,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Switch.adaptive(
            value: valor,
            activeColor: _roxoPrimario,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _DividerCard extends StatelessWidget {
  const _DividerCard();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Divider(
        height: 1,
        color: _bordaCard.withValues(alpha: 0.7),
        thickness: 1,
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.texto);

  final String texto;

  @override
  Widget build(BuildContext context) {
    return Text(
      texto,
      style: GoogleFonts.plusJakartaSans(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: _textoPrimario,
      ),
    );
  }
}
