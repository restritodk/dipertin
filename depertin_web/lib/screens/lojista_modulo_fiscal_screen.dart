import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:depertin_web/models/comercial_cliente.dart';
import 'package:depertin_web/models/lojista_integracao_model.dart';
import 'package:depertin_web/services/comercial_clientes_service.dart';
import 'package:depertin_web/services/fiscal/fiscal_payload.dart';
import 'package:depertin_web/services/lojista_integracao_service.dart';
import 'package:depertin_web/utils/lojista_painel_context.dart';
import 'package:depertin_web/widgets/fiscal/fiscal_emissao_modal.dart';
import 'package:depertin_web/services/fiscal/fiscal_cancelamento_service.dart';
import 'package:depertin_web/services/fiscal/fiscal_carta_correcao_service.dart';
import 'package:depertin_web/services/fiscal/fiscal_inutilizacao_service.dart';
import 'package:depertin_web/services/fiscal/fiscal_contingencia_service.dart';
import 'package:depertin_web/services/fiscal/fiscal_erro_translator.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:depertin_web/services/cidades_brasil_service.dart';
import 'package:depertin_web/services/firebase_functions_config.dart';

// =============================================================================
// CONSTANTES DE COR (design system DiPertin)
// =============================================================================
const Color _roxo = Color(0xFF6A1B9A);
const Color _roxoClaro = Color(0xFF8E24AA);
const Color _laranja = Color(0xFFFF8F00);
const Color _textoPrimario = Color(0xFF1A1A2E);
const Color _textoSecundario = Color(0xFF64748B);
const Color _verde = Color(0xFF16A34A);
const Color _verdeFundo = Color(0xFFE8F5E9);
const Color _vermelho = Color(0xFFDC2626);
const Color _vermelhoFundo = Color(0xFFFEF2F2);
const Color _amarelo = Color(0xFFD97706);
const Color _amareloFundo = Color(0xFFFFF8E1);
const Color _azul = Color(0xFF2563EB);
const Color _azulFundo = Color(0xFFEFF6FF);
const Color _lilas = Color(0xFFF1E9FF);
const Color _cinzaClaro = Color(0xFFF8F8FC);
const Color _borda = Color(0xFFEEEAF6);

// =============================================================================
// TELA PRINCIPAL
// =============================================================================

class LojistaModuloFiscalScreen extends StatefulWidget {
  const LojistaModuloFiscalScreen({super.key});

  @override
  State<LojistaModuloFiscalScreen> createState() =>
      _LojistaModuloFiscalScreenState();
}

class _LojistaModuloFiscalScreenState
    extends State<LojistaModuloFiscalScreen> with TickerProviderStateMixin {
  int _abaIndex = 0;
  bool _carregando = true;
  String _storeId = '';

  // Stream da integração
  StreamSubscription<LojistaIntegracaoModel?>? _integSub;
  LojistaIntegracaoModel? _integracao;

  // Stream das notas fiscais (tempo real)
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _notasSub;
  List<Map<String, dynamic>> _notas = [];
  List<Map<String, dynamic>> _notasFiltradas = [];

  // Retorna apenas os itens da página atual para uma lista filtrada
  List<Map<String, dynamic>> _paginarLista(List<Map<String, dynamic>> lista, int pagina) {
    final inicio = (pagina - 1) * _itensPorPagina;
    if (inicio >= lista.length) return [];
    final fim = (inicio + _itensPorPagina).clamp(0, lista.length);
    return lista.sublist(inicio, fim);
  }

  List<Map<String, dynamic>> get _notasFiltradasPagina =>
      _paginarLista(_notasFiltradas, _paginaClientes);

  // Stats
  int _emitidas = 0;
  int _pendentes = 0;
  int _autorizadas = 0;
  int _rejeitadas = 0;
  int _canceladas = 0;
  int _cces = 0;
  double _valorTotalFaturado = 0;

  // Filtros
  final _buscaCtrl = TextEditingController();
  String _filtroStatusNfe = 'Todas';
  String _filtroStatusHistorico = 'Todas';

  // Filtros do Histórico
  final _filtroHistoricoCtrl = TextEditingController();
  final _filtroNumeroCtrl = TextEditingController();
  final _filtroCpfCnpjCtrl = TextEditingController();
  final _filtroDataInicialCtrl = TextEditingController();
  final _filtroDataFinalCtrl = TextEditingController();
  final _filtroMunicipioCtrl = TextEditingController();
  final _filtroValorCtrl = TextEditingController();
  final _filtroFormaPagamentoCtrl = TextEditingController();

  // Clientes GC (cache da aba Clientes)
  List<ComercialCliente> _clientesGc = [];

  // Dados fiscais do emitente (companyTaxData do store_fiscal_settings)
  Map<String, dynamic> _companyTaxData = {};
  Map<String, dynamic> _storeSettingsFullData = {};
  String _integrationId = '';
  bool _companyTaxLoading = false;
  bool _ambienteHomologacaoNfe = true; // default seguro = homologação

  // Paginação
  static const int _itensPorPagina = 10;
  int _paginaClientes = 1;
  int _paginaEmitidas = 1;
  int _paginaPendentes = 1;
  int _paginaRejeitadas = 1;
  int _paginaCanceladas = 1;
  int _paginaHistorico = 1;

  // Estado de contingência
  bool _emContingencia = false;
  String? _motivoContingencia;
  StreamSubscription<EstadoContingencia>? _contSub;

  late TabController _tabController;

  // Formatação
  static final _moeda =
      NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
  static final _data = DateFormat('dd/MM/yyyy', 'pt_BR');
  static final _dataHora = DateFormat('dd/MM/yyyy HH:mm', 'pt_BR');

  static const _rotulosAbas = [
    'Clientes',
    'Notas Emitidas',
    'Pendentes',
    'Rejeitadas',
    'Canceladas',
    'Histórico',
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 6, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {
          _abaIndex = _tabController.index;
          // Resetar página ao trocar de aba
          _paginaClientes = 1;
          _paginaEmitidas = 1;
          _paginaPendentes = 1;
          _paginaRejeitadas = 1;
          _paginaCanceladas = 1;
          _paginaHistorico = 1;
        });
      }
    });
    _iniciarStreams();
  }

  Future<void> _iniciarStreams() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final docUser =
        await FirebaseFirestore.instance.collection('users').doc(uid).get();
    final dadosUser = docUser.data() ?? {};
    final storeId = uidLojaEfetivo(dadosUser, uid);

    _storeId = storeId;

    // Stream da integração
    _integSub = LojistaIntegracaoService.streamIntegracaoPorStore(storeId)
        .listen((integ) {
      if (mounted) setState(() => _integracao = integ);
    });

    // Stream de contingência
    _contSub = FiscalContingenciaService.streamEstado(storeId).listen((estado) {
      if (mounted) {
        setState(() {
          _emContingencia = estado.emContingencia;
          _motivoContingencia = estado.motivo;
        });
      }
    });

    // Stream das notas fiscais — usa subcoleção da loja p/ regras Firestore
    _notasSub = FirebaseFirestore.instance
        .collection('users')
        .doc(storeId)
        .collection('notas_fiscais')
        .orderBy('data_criacao', descending: true)
        .snapshots()
        .listen((snap) {
      _notas = snap.docs.map((d) {
        final data = d.data();
        data['__docId'] = d.id;
        return data;
      }).toList();
      _aplicarFiltros();
      _calcularStats();
      if (_carregando && mounted) setState(() => _carregando = false);
    });

    // Carrega clientes do Gestão Comercial uma vez
    await _carregarClientesGc();

    // Carrega dados fiscais do emitente
    await _carregarCompanyTaxData(storeId);

    if (_carregando && mounted) setState(() => _carregando = false);
  }

  Future<void> _carregarCompanyTaxData(String storeId) async {
    if (_companyTaxLoading) return;
    _companyTaxLoading = true;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('store_fiscal_settings')
          .where('store_id', isEqualTo: storeId)
          .limit(1)
          .get();
      if (snap.docs.isNotEmpty) {
        final data = snap.docs.first.data();
        if (mounted) {
          setState(() {
            _storeSettingsFullData = Map<String, dynamic>.from(data);
            _integrationId = (data['integration_id'] as String?) ?? '';
          });
        }
        debugPrint('[ModuloFiscal] store_fiscal_settings ENCONTRADO para storeId=$storeId');
        debugPrint('[ModuloFiscal] Campos do documento: ${data.keys.join(', ')}');

        // Estratégia: tenta company_tax_data primeiro, depois campos top-level
        Map<String, dynamic> taxData = {};
        final rawTax = data['company_tax_data'];
        if (rawTax is Map<String, dynamic> && rawTax.isNotEmpty) {
          taxData = rawTax;
          debugPrint('[ModuloFiscal] company_tax_data CARREGADO (submap)');
        } else {
          // Fallback: tenta campos fiscais no top-level do documento store_fiscal_settings
          debugPrint('[ModuloFiscal] company_tax_data NÃO encontrado como submap. Tentando campos top-level...');
          final topLevelTax = <String, dynamic>{};
          for (final chave in ['cnpj', 'razao_social', 'nome_fantasia', 'ie',
              'inscricao_estadual', 'regime_tributario', 'cnae', 'crt',
              'logradouro', 'numero', 'bairro', 'cidade', 'uf', 'cep',
              'codigo_cidade', 'telefone', 'email_fiscal']) {
            if (data[chave] is String && (data[chave] as String).isNotEmpty) {
              topLevelTax[chave] = data[chave];
            }
          }
          if (topLevelTax.isNotEmpty) {
            taxData = topLevelTax;
            debugPrint('[ModuloFiscal] ⚠️ Fallback: usando campos FISCAIS do TOP-LEVEL do documento');
            debugPrint('[ModuloFiscal] Campos top-level encontrados: ${topLevelTax.keys.join(', ')}');
          } else {
            debugPrint('[ModuloFiscal] ❌ NENHUM dado fiscal encontrado (nem submap, nem top-level)');
          }
        }

        if (taxData.isNotEmpty) {
          // Normaliza chaves: garante que campos como razao_social existam
          // mesmo que o Admin tenha salvo como razaoSocial, nome, etc.
          _normalizarChavesFiscais(taxData);
          if (mounted) setState(() => _companyTaxData = taxData);
          debugPrint('[ModuloFiscal] ═══ company_tax_data COMPLETO ═══');
        } else {
          // Garante que _companyTaxData esteja vazio (não usa dados antigos)
          if (mounted) setState(() => _companyTaxData = {});
        }
        // Log de todos os campos (mesmo se vazio, para diagnóstico)
        debugPrint('[ModuloFiscal] cnpj="${taxData['cnpj']}"');
        debugPrint('[ModuloFiscal] razao_social="${taxData['razao_social']}"');
        debugPrint('[ModuloFiscal] nome_fantasia="${taxData['nome_fantasia']}"');
        debugPrint('[ModuloFiscal] ie="${taxData['ie']}"');
        debugPrint('[ModuloFiscal] regime_tributario="${taxData['regime_tributario']}"');
        debugPrint('[ModuloFiscal] cnae="${taxData['cnae']}"');
        debugPrint('[ModuloFiscal] logradouro="${taxData['logradouro']}"');
        debugPrint('[ModuloFiscal] numero="${taxData['numero']}"');
        debugPrint('[ModuloFiscal] bairro="${taxData['bairro']}"');
        debugPrint('[ModuloFiscal] cep="${taxData['cep']}"');
        debugPrint('[ModuloFiscal] cidade="${taxData['cidade']}"');
        debugPrint('[ModuloFiscal] uf="${taxData['uf']}"');
        debugPrint('[ModuloFiscal] codigo_cidade="${taxData['codigo_cidade']}"');
        debugPrint('[ModuloFiscal] crt="${taxData['crt']}"');
        debugPrint('[ModuloFiscal] ════════════════════════════════');

        // Extrai ambiente das settings de NF-e ou NFC-e
        final nfe = data['nfe_settings'] as Map<String, dynamic>?;
        final nfce = data['nfce_settings'] as Map<String, dynamic>?;
        // Fallback: se nfe_settings não tem environment, tenta top-level
        String env = nfe?['environment'] as String? ??
            nfce?['environment'] as String? ??
            data['environment'] as String? ??
            'sandbox';
        if (mounted) setState(() => _ambienteHomologacaoNfe = env == 'sandbox');
        debugPrint('[ModuloFiscal] integration_id=${data['integration_id']}');
        debugPrint('[ModuloFiscal] environment=$env');
        debugPrint('[ModuloFiscal] tem certificate=${data['certificate_data_encrypted'] != null}');
      } else {
        debugPrint('[ModuloFiscal] ⚠️ store_fiscal_settings NÃO ENCONTRADO para storeId=$storeId');
        debugPrint('[ModuloFiscal] ⚠️ Verifique se o Admin salvou os dados com este mesmo storeId');
        if (mounted) {
          setState(() {
            _storeSettingsFullData = <String, dynamic>{};
            _companyTaxData = {};
            _integrationId = '';
          });
        }
      }
    } catch (e) {
      debugPrint('[ModuloFiscal] ❌ Erro ao carregar company_tax_data: $e');
    } finally {
      _companyTaxLoading = false;
    }
  }

  Future<void> _carregarClientesGc() async {
    if (_storeId.isEmpty) return;
    try {
      final clientes = await ComercialClientesService.listar(_storeId);
      if (mounted) setState(() => _clientesGc = clientes);
    } catch (_) {}
  }

  @override
  void dispose() {
    _buscaCtrl.dispose();
    _filtroHistoricoCtrl.dispose();
    _filtroNumeroCtrl.dispose();
    _filtroCpfCnpjCtrl.dispose();
    _filtroDataInicialCtrl.dispose();
    _filtroDataFinalCtrl.dispose();
    _filtroMunicipioCtrl.dispose();
    _filtroValorCtrl.dispose();
    _filtroFormaPagamentoCtrl.dispose();
    _tabController.dispose();
    _integSub?.cancel();
    _notasSub?.cancel();
    _contSub?.cancel();
    super.dispose();
  }

  // ─── Stats ────────────────────────────────────────────────

  void _calcularStats() {
    int emitidas = 0, pendentes = 0, autorizadas = 0;
    int rejeitadas = 0, canceladas = 0, cces = 0;
    double valorTotal = 0;

    for (final n in _notas) {
      final sit = (n['situacao'] ?? '').toString();
      final v = (n['valor_total'] as num?)?.toDouble() ?? 0;
      valorTotal += v;
      if (sit == 'emitida' || sit == 'enviada') emitidas++;
      if (sit == 'aguardando_emissao' || sit == 'processando') pendentes++;
      if (sit == 'autorizada') autorizadas++;
      if (sit == 'rejeitada') rejeitadas++;
      if (sit == 'cancelada') canceladas++;
      if (n['cce_emitida'] == true) cces++;
    }

    setState(() {
      _emitidas = emitidas;
      _pendentes = pendentes;
      _autorizadas = autorizadas;
      _rejeitadas = rejeitadas;
      _canceladas = canceladas;
      _cces = cces;
      _valorTotalFaturado = valorTotal;
    });
  }

  void _aplicarFiltros() {
    // Resetar paginação ao aplicar filtros
    _paginaClientes = 1;
    _paginaEmitidas = 1;
    _paginaPendentes = 1;
    _paginaRejeitadas = 1;
    _paginaCanceladas = 1;
    _paginaHistorico = 1;
    final busca = _buscaCtrl.text.trim().toLowerCase();
    final filtroHistorico = _filtroHistoricoCtrl.text.trim().toLowerCase();
    final filtroNumero = _filtroNumeroCtrl.text.trim().toLowerCase();
    final filtroCpfCnpj =
        _filtroCpfCnpjCtrl.text.trim().replaceAll(RegExp(r'\D'), '');
    final dataInicialTexto = _filtroDataInicialCtrl.text.trim();
    final dataFinalTexto = _filtroDataFinalCtrl.text.trim();
    final filtroMunicipio = _filtroMunicipioCtrl.text.trim().toLowerCase();
    final filtroValorTexto = _filtroValorCtrl.text.trim();
    final filtroFormaPag = _filtroFormaPagamentoCtrl.text.trim().toLowerCase();

    DateTime? dataInicial;
    DateTime? dataFinal;
    if (dataInicialTexto.isNotEmpty) {
      try {
        dataInicial = DateFormat('dd/MM/yyyy').parse(dataInicialTexto);
      } catch (_) {}
    }
    if (dataFinalTexto.isNotEmpty) {
      try {
        dataFinal = DateFormat('dd/MM/yyyy').parse(dataFinalTexto);
        dataFinal = dataFinal.add(const Duration(hours: 23, minutes: 59, seconds: 59));
      } catch (_) {}
    }

    setState(() {
      _notasFiltradas = _notas.where((n) {
        // Filtro global de busca (Clientes tab)
        if (busca.isNotEmpty) {
          final nome = (n['cliente_nome'] ?? '').toString().toLowerCase();
          final cpf = (n['cliente_cpf_cnpj'] ?? '').toString().toLowerCase();
          final numNfe = (n['numero_nfe'] ?? '').toString().toLowerCase();
          if (!nome.contains(busca) &&
              !cpf.contains(busca) &&
              !numNfe.contains(busca)) {
            return false;
          }
        }
        // Filtro de status (Cliente/NFC-e)
        if (_filtroStatusNfe != 'Todas') {
          final sit = (n['situacao'] ?? '').toString();
          if (sit != _filtroStatusNfe.toLowerCase().replaceAll(' ', '_')) {
            return false;
          }
        }
        // Filtros do Histórico
        if (filtroHistorico.isNotEmpty) {
          final nomeCli =
              (n['cliente_nome'] ?? '').toString().toLowerCase();
          if (!nomeCli.contains(filtroHistorico)) return false;
        }
        if (filtroNumero.isNotEmpty) {
          final numNfe = (n['numero_nfe'] ?? '').toString().toLowerCase();
          if (!numNfe.contains(filtroNumero)) return false;
        }
        if (filtroCpfCnpj.isNotEmpty) {
          final cpfDoc =
              (n['cliente_cpf_cnpj'] ?? '').toString().replaceAll(RegExp(r'\D'), '');
          if (!cpfDoc.contains(filtroCpfCnpj)) return false;
        }
        if (dataInicial != null) {
          final dataCriacao = (n['data_criacao'] is Timestamp)
              ? (n['data_criacao'] as Timestamp).toDate()
              : null;
          if (dataCriacao != null && dataCriacao.isBefore(dataInicial)) {
            return false;
          }
        }
        if (dataFinal != null) {
          final dataCriacao = (n['data_criacao'] is Timestamp)
              ? (n['data_criacao'] as Timestamp).toDate()
              : null;
          if (dataCriacao != null && dataCriacao.isAfter(dataFinal)) {
            return false;
          }
        }
        if (filtroMunicipio.isNotEmpty) {
          final municipio =
              (n['municipio_emissor'] ?? '').toString().toLowerCase();
          if (!municipio.contains(filtroMunicipio)) return false;
        }
        if (filtroValorTexto.isNotEmpty) {
          final valorFiltro =
              double.tryParse(filtroValorTexto.replaceAll(',', '.')) ?? 0;
          final valorDoc = (n['valor_total'] as num?)?.toDouble() ?? 0;
          if (valorDoc != valorFiltro) return false;
        }
        if (filtroFormaPag.isNotEmpty) {
          final forma =
              (n['forma_pagamento'] ?? '').toString().toLowerCase();
          if (!forma.contains(filtroFormaPag)) return false;
        }
        return true;
      }).toList();
    });
  }

  // ─── Helpers de campo ─────────────────────────────────────

  static String _str(Map<String, dynamic> m, String k, [String fb = '']) =>
      (m[k] ?? fb).toString();

  /// Normaliza chaves do mapa de company_tax_data para garantir que campos
  /// canônicos existam, independentemente de como foram salvos pelo Admin.
  /// Ex.: se só existe 'razaoSocial', copia para 'razao_social'.
  static void _normalizarChavesFiscais(Map<String, dynamic> m) {
    const aliasMap = {
      'razao_social': ['razaoSocial', 'razaosocial', 'nome', 'name', 'razao_social_sistema'],
      'nome_fantasia': ['nomeFantasia', 'nome_fantasia_sistema', 'fantasia'],
      'cnpj': ['cpf_cnpj', 'documento', 'cnpj_cpf', 'num_cnpj'],
      'ie': ['inscricao_estadual', 'inscricaoEstadual', 'ie_estadual', 'num_ie', 'documento_ie'],
      'crt': ['regime_tributario_codigo', 'codigoRegimeTributario', 'codigo_regime_tributario', 'crt_codigo'],
      'cnae': ['codigo_cnae', 'cnae_fiscal', 'cnae_codigo', 'codCnae'],
      'codigo_cidade': ['ibge_cidade', 'codigoMunicipio', 'codigo_municipio', 'ibge_codigo_cidade'],
      'regime_tributario': ['regimeTributario', 'regime'],
      'logradouro': ['endereco_logradouro', 'endereco', 'rua', 'endereco_fiscal', 'logradouro_fiscal'],
      'numero': ['endereco_numero', 'num', 'numero_fiscal'],
      'bairro': ['endereco_bairro', 'bairro_fiscal'],
      'cidade': ['endereco_cidade', 'cidade_fiscal', 'municipio'],
      'uf': ['endereco_uf', 'estado', 'uf_fiscal', 'sigla_uf'],
      'cep': ['endereco_cep', 'cep_fiscal', 'codigo_postal'],
    };
    for (final entry in aliasMap.entries) {
      final chaveCanonica = entry.key;
      if (m.containsKey(chaveCanonica) && m[chaveCanonica] != null && m[chaveCanonica].toString().isNotEmpty) {
        continue; // já existe, não precisa normalizar
      }
      for (final alias in entry.value) {
        if (m.containsKey(alias) && m[alias] != null && m[alias].toString().isNotEmpty) {
          m[chaveCanonica] = m[alias];
          debugPrint('[ModuloFiscal] Normalizado: $alias → $chaveCanonica = "${m[alias]}"');
          break;
        }
      }
    }
  }

  static double _num(Map<String, dynamic> m, String k, [double fb = 0]) =>
      (m[k] as num?)?.toDouble() ?? fb;

  String _fmtData(dynamic ts) {
    if (ts is Timestamp) return _data.format(ts.toDate());
    return '—';
  }

  String _fmtDataHora(dynamic ts) {
    if (ts is Timestamp) return _dataHora.format(ts.toDate());
    return '—';
  }

  @override
  Widget build(BuildContext context) {
    if (_carregando) {
      return const Center(child: CircularProgressIndicator());
    }

    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          _buildDashboardCards(),
          _buildTabBar(),
          Expanded(child: _buildTabContent()),
        ],
      ),
    );
  }

  // ─── HEADER ───────────────────────────────────────────────

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(32, 24, 32, 16),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              gradient:
                  const LinearGradient(colors: [_roxo, _roxoClaro]),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.receipt_long_rounded,
                color: Colors.white, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Módulo Fiscal',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: _textoPrimario,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Gestão de notas fiscais eletrônicas',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    color: _textoSecundario,
                  ),
                ),
              ],
            ),
          ),
          if (_integracao != null) _buildIntegracaoStatus(),
          const SizedBox(width: 6),
          // Botão recarregar dados fiscais
          _buildRefreshFiscalButton(),
          const SizedBox(width: 6),
          if (_emContingencia) _buildContingenciaBadge(),
        ],
      ),
    );
  }

  Widget _buildContingenciaBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3E0),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: _laranja.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.warning_amber_rounded, size: 14, color: _laranja),
          const SizedBox(width: 6),
          Text(
            'Contingência',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: _laranja,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIntegracaoStatus() {
    final integ = _integracao!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: integ.estaAtiva ? _verdeFundo : _vermelhoFundo,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: integ.estaAtiva
              ? _verde.withValues(alpha: 0.3)
              : _vermelho.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            integ.estaAtiva
                ? Icons.check_circle_rounded
                : Icons.warning_amber_rounded,
            size: 14,
            color: integ.estaAtiva ? _verde : _vermelho,
          ),
          const SizedBox(width: 6),
          Text(
            integ.estaAtiva ? 'Integração Ativa' : 'Integração Inativa',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: integ.estaAtiva ? _verde : _vermelho,
            ),
          ),
        ],
      ),
    );
  }

  /// Botão para recarregar dados fiscais do Firebase.
  /// Garante que a emissão sempre use dados frescos, nunca cacheados.
  Widget _buildRefreshFiscalButton() {
    return Tooltip(
      message: 'Recarregar dados fiscais do Firebase',
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () {
            if (_storeId.isNotEmpty) {
              _carregarCompanyTaxData(_storeId);
            }
          },
          child: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: const Color(0xFFF5F0FF),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFD4C9F0)),
            ),
            child: const Icon(
              Icons.refresh_rounded,
              size: 18,
              color: Color(0xFF6A1B9A),
            ),
          ),
        ),
      ),
    );
  }

  // ─── DASHBOARD CARDS ──────────────────────────────────────

  Widget _buildDashboardCards() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _statCard('Emitidas', _emitidas.toString(),
                  Icons.check_circle_rounded, _verde, _verdeFundo),
              const SizedBox(width: 12),
              _statCard('Pendentes', _pendentes.toString(),
                  Icons.schedule_rounded, _amarelo, _amareloFundo),
              const SizedBox(width: 12),
              _statCard('Autorizadas', _autorizadas.toString(),
                  Icons.verified_rounded, _azul, _azulFundo),
              const SizedBox(width: 12),
              _statCard('Rejeitadas', _rejeitadas.toString(),
                  Icons.cancel_rounded, _vermelho, _vermelhoFundo),
              const SizedBox(width: 12),
              _statCard('Canceladas', _canceladas.toString(),
                  Icons.block_rounded, _laranja, _amareloFundo),
              const SizedBox(width: 12),
              _statCard('CC-e', _cces.toString(),
                  Icons.edit_note_rounded, _roxo, _lilas),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _valueCard(
                'Valor total faturado',
                _moeda.format(_valorTotalFaturado),
                Icons.trending_up_rounded,
                _roxo,
                flex: 3,
              ),
              const SizedBox(width: 12),
              Expanded(flex: 2, child: _buildLimiteCard()),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statCard(
      String label, String valor, IconData icon, Color cor, Color fundo) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: fundo),
          boxShadow: [
            BoxShadow(
              color: cor.withValues(alpha: 0.06),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: fundo,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: cor, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    valor,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: _textoPrimario,
                    ),
                  ),
                  Text(
                    label,
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 10, color: _textoSecundario),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _valueCard(
    String label,
    String valor,
    IconData icon,
    Color cor, {
    int flex = 1,
  }) {
    return Expanded(
      flex: flex,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [cor.withValues(alpha: 0.08), cor.withValues(alpha: 0.02)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cor.withValues(alpha: 0.15)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: cor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: cor, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    valor,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: _textoPrimario,
                    ),
                  ),
                  Text(
                    label,
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 11, color: _textoSecundario),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLimiteCard() {
    final integ = _integracao;
    final limite = integ?.limiteMensal ?? 0;
    final emitidas = integ?.notasEmitidas ?? 0;
    final ehIlimitado = integ?.ehIlimitado ?? true;
    final pct = ehIlimitado ? 0.0 : (emitidas / limite).clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _borda),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.inventory_rounded, size: 16, color: _roxo),
              const SizedBox(width: 8),
              Text(
                'Limite do plano',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 11, color: _textoSecundario),
              ),
              const Spacer(),
              Text(
                ehIlimitado
                    ? 'Ilimitado'
                    : '$emitidas de $limite utilizadas',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: pct >= 0.9 ? _vermelho : _textoPrimario,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (!ehIlimitado)
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: pct,
                backgroundColor: const Color(0xFFEEEAF6),
                valueColor: AlwaysStoppedAnimation<Color>(
                  pct >= 0.9 ? _vermelho : _roxo,
                ),
                minHeight: 6,
              ),
            ),
        ],
      ),
    );
  }

  // ─── TAB BAR ──────────────────────────────────────────────

  Widget _buildTabBar() {
    return Container(
      margin: const EdgeInsets.fromLTRB(32, 16, 32, 0),
      decoration: BoxDecoration(
        color: _cinzaClaro,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _borda),
      ),
      child: TabBar(
        controller: _tabController,
        isScrollable: true,
        indicator: BoxDecoration(
          color: _roxo,
          borderRadius: BorderRadius.circular(10),
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        labelColor: Colors.white,
        unselectedLabelColor: _textoSecundario,
        labelStyle: GoogleFonts.plusJakartaSans(
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelStyle: GoogleFonts.plusJakartaSans(
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
        dividerColor: Colors.transparent,
        padding: const EdgeInsets.all(4),
        onTap: (i) => setState(() => _abaIndex = i),
        tabs: _rotulosAbas.map((r) {
          final badgeMap = {
            'Pendentes': _pendentes,
            'Rejeitadas': _rejeitadas,
            'Canceladas': _canceladas,
          };
          final badge = badgeMap[r];
          return Tab(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(r),
                if (badge != null && badge > 0) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: r == 'Pendentes'
                          ? _amarelo
                          : r == 'Rejeitadas'
                              ? _vermelho
                              : _laranja,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      badge.toString(),
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  // ─── CONTEÚDO DA ABA ──────────────────────────────────────

  Widget _buildTabContent() {
    switch (_abaIndex) {
      case 0:
        return _buildAbaClientes();
      case 1:
        return _buildAbaNotas(_notasFiltradas
            .where((n) =>
                _str(n, 'situacao') == 'emitida' ||
                _str(n, 'situacao') == 'enviada' ||
                _str(n, 'situacao') == 'autorizada')
            .toList(), 'notas emitidas',
            pagina: _paginaEmitidas, onPageChanged: (p) => setState(() => _paginaEmitidas = p));
      case 2:
        return _buildAbaNotas(
            _notasFiltradas
                .where((n) =>
                    _str(n, 'situacao') == 'aguardando_emissao' ||
                    _str(n, 'situacao') == 'processando' ||
                    _str(n, 'situacao') == 'falha_temporaria')
                .toList(),
            'notas pendentes',
            pagina: _paginaPendentes, onPageChanged: (p) => setState(() => _paginaPendentes = p));
      case 3:
        return _buildAbaRejeitadas();
      case 4:
        return _buildAbaCanceladas();
      case 5:
        return _buildAbaHistorico();
      default:
        return const SizedBox.shrink();
    }
  }

  // ===========================================================================
  // ABA CLIENTES
  // ===========================================================================

  Widget _buildAbaClientes() {
    return Column(
      children: [
        // Filtros
        Container(
          padding: const EdgeInsets.fromLTRB(32, 16, 32, 8),
          child: Row(
            children: [
              // Busca inteligente de clientes GC
              Expanded(
                flex: 2,
                child: _buildBuscaClienteGc(),
              ),
              const SizedBox(width: 12),
              _buildFiltroDropdown(
                'Status NF-e',
                [
                  'Todas',
                  'Aguardando emissão',
                  'Emitida',
                  'Enviada',
                  'Autorizada',
                  'Rejeitada',
                  'Cancelada'
                ],
                _filtroStatusNfe,
                (v) => setState(() {
                  _filtroStatusNfe = v;
                  _aplicarFiltros();
                }),
              ),
            ],
          ),
        ),
        // Tabela premium
        Expanded(child: _buildTabelaNotas()),
      ],
    );
  }

  /// Campo de busca inteligente que pesquisa apenas clientes do Gestão Comercial.
  Widget _buildBuscaClienteGc() {
    return Autocomplete<ComercialCliente>(
      optionsBuilder: (textEditingValue) {
        final termo = textEditingValue.text.trim().toLowerCase();
        if (termo.isEmpty) return const Iterable.empty();
        final cpfBusca = termo.replaceAll(RegExp(r'\D'), '');
        return _clientesGc.where((c) {
          if (c.status == 'bloqueado') return false;
          if (c.nome.toLowerCase().contains(termo)) return true;
          if (cpfBusca.length >= 3) {
            final cpf = (c.cpf ?? '').replaceAll(RegExp(r'\D'), '');
            if (cpf.contains(cpfBusca)) return true;
          }
          if (cpfBusca.length >= 4) {
            final tel = (c.telefone ?? '').replaceAll(RegExp(r'\D'), '');
            if (tel.contains(cpfBusca)) return true;
          }
          return false;
        }).take(15);
      },
      displayStringForOption: (c) => c.nome,
      fieldViewBuilder:
          (context, ctrl, focusNode, onSubmitted) {
        return TextField(
          controller: ctrl,
          focusNode: focusNode,
          decoration: InputDecoration(
            hintText: 'Buscar cliente (nome, CPF, CNPJ, telefone, e-mail)...',
            hintStyle: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                color: _textoSecundario.withValues(alpha: 0.5)),
            prefixIcon: const Icon(Icons.search_rounded,
                size: 20, color: _textoSecundario),
            filled: true,
            fillColor: _cinzaClaro,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: _borda),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: _borda),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: _roxo, width: 1.5),
            ),
          ),
          style: GoogleFonts.plusJakartaSans(
              fontSize: 13, color: _textoPrimario),
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              constraints: const BoxConstraints(maxHeight: 300, maxWidth: 600),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _borda),
              ),
              child: ListView.separated(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: options.length,
                separatorBuilder: (_, _) =>
                    const Divider(height: 1, indent: 16, endIndent: 16),
                itemBuilder: (context, i) {
                  final c = options.elementAt(i);
                  return InkWell(
                    onTap: () => onSelected(c),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: _lilas,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.person_rounded,
                                size: 16, color: _roxo),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  c.nome,
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: _textoPrimario,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Row(
                                  children: [
                                    if (c.cpf != null &&
                                        c.cpf!.isNotEmpty)
                                      Text(
                                        ComercialClientesService
                                            .formatarCpfExibicao(c.cpf),
                                        style: GoogleFonts.plusJakartaSans(
                                          fontSize: 11,
                                          color: _textoSecundario,
                                        ),
                                      ),
                                    if (c.cpf != null &&
                                        c.cpf!.isNotEmpty &&
                                        c.telefone != null &&
                                        c.telefone!.isNotEmpty)
                                      const Text(' · ',
                                          style: TextStyle(
                                              fontSize: 11,
                                              color: _textoSecundario)),
                                    if (c.telefone != null &&
                                        c.telefone!.isNotEmpty)
                                      Text(
                                        c.telefone!,
                                        style: GoogleFonts.plusJakartaSans(
                                          fontSize: 11,
                                          color: _textoSecundario,
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: _roxo.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'Criar NF-e',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: _roxo,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
      onSelected: (cliente) {
        _buscaCtrl.text = cliente.nome;
        _abrirModalCriarNota(cliente);
      },
    );
  }

  // ─── TABELA PREMIUM (95% largura, badges, hover, seleção) ───

  Widget _buildTabelaNotas() {
    if (_notasFiltradas.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96, height: 96,
              decoration: BoxDecoration(
                color: _lilas,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Icon(Icons.receipt_long_outlined,
                  size: 44, color: _roxo.withValues(alpha: 0.4)),
            ),
            const SizedBox(height: 20),
            Text(
              'Nenhuma Nota Fiscal encontrada',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: _textoPrimario,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Selecione um cliente acima para criar uma NF-e',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                color: _textoSecundario,
              ),
            ),
            const SizedBox(height: 24),
            Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                onTap: null,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [_roxo, _roxoClaro]),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: _roxo.withValues(alpha: 0.3),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.add_rounded, color: Colors.white, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        'Criar primeira nota',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 8, 32, 16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final tableWidth = constraints.maxWidth;
          final colFlex = [1.2, 2.0, 1.2, 1.2, 0.9, 1.0, 1.0, 1.5];
          final totalFlex = colFlex.fold<double>(0, (a, b) => a + b);
          return ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Container(
              width: tableWidth,
              decoration: BoxDecoration(
                border: Border.all(color: _borda),
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: _roxo.withValues(alpha: 0.04),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SizedBox(
                        width: tableWidth > 600 ? tableWidth : null,
                        child: Column(
                          mainAxisSize: MainAxisSize.max,
                          children: [
                            // Header row
                            _buildTableHeader(
                              ['Nº NF-e', 'Cliente', 'CPF/CNPJ', 'Município', 'Valor', 'Status', 'Atualização', 'Ações'],
                              colFlex,
                              totalFlex,
                              tableWidth,
                            ),
                            // Data rows com rolagem vertical própria
                            Expanded(
                              child: SingleChildScrollView(
                                scrollDirection: Axis.vertical,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    ..._notasFiltradasPagina.asMap().entries.map((e) => _buildTableRow(e.value, e.key, colFlex, totalFlex, tableWidth)),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  // Paginação fixa fora do scroll
                  _buildPaginacao(
                    _notasFiltradas.length,
                    _paginaClientes,
                    (p) => setState(() => _paginaClientes = p),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildTableHeader(
    List<String> labels,
    List<double> flex,
    double totalFlex,
    double totalWidth,
  ) {
    return Container(
      decoration: const BoxDecoration(
        color: _roxo,
        border: Border(bottom: BorderSide(color: _laranja, width: 2)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: List.generate(labels.length, (i) {
          final width = (flex[i] / totalFlex) * (totalWidth - 32);
          return SizedBox(
            width: width,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (i == 0) ...[
                  const Icon(Icons.check_box_outline_blank, size: 14, color: Colors.white70),
                  const SizedBox(width: 6),
                ],
                Text(
                  labels[i],
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          );
        }),
      ),
    );
  }

  Widget _buildTableRow(
    Map<String, dynamic> n,
    int rowIndex,
    List<double> flex,
    double totalFlex,
    double totalWidth,
  ) {
    final cells = [
      _buildTableCell(
        width: (flex[0] / totalFlex) * (totalWidth - 32),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_box_outline_blank, size: 16, color: _borda),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                _str(n, 'numero_nfe').isNotEmpty ? _str(n, 'numero_nfe') : '—',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 11, fontWeight: FontWeight.w600, color: _textoPrimario,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
      _buildTableCell(
        width: (flex[1] / totalFlex) * (totalWidth - 32),
        child: _buildClienteCell(n),
      ),
      _buildTableCell(
        width: (flex[2] / totalFlex) * (totalWidth - 32),
        child: Text(
          _str(n, 'cliente_cpf_cnpj', '—'),
          style: GoogleFonts.plusJakartaSans(fontSize: 11, color: _textoSecundario),
          overflow: TextOverflow.ellipsis,
        ),
      ),
      _buildTableCell(
        width: (flex[3] / totalFlex) * (totalWidth - 32),
        child: Text(
          _str(n, 'municipio_emissor', '—'),
          style: GoogleFonts.plusJakartaSans(fontSize: 11, color: _textoPrimario),
          maxLines: 1, overflow: TextOverflow.ellipsis,
        ),
      ),
      _buildTableCell(
        width: (flex[4] / totalFlex) * (totalWidth - 32),
        child: Text(
          _moeda.format(_num(n, 'valor_total')),
          style: GoogleFonts.plusJakartaSans(
            fontSize: 12, fontWeight: FontWeight.w700, color: _textoPrimario,
          ),
        ),
      ),
      _buildTableCell(
        width: (flex[5] / totalFlex) * (totalWidth - 32),
        child: _buildStatusBadge(_str(n, 'situacao')),
      ),
      _buildTableCell(
        width: (flex[6] / totalFlex) * (totalWidth - 32),
        child: Text(
          _fmtData(n['data_emissao'] ?? n['data_criacao']),
          style: GoogleFonts.plusJakartaSans(fontSize: 10, color: _textoSecundario),
        ),
      ),
      _buildTableCell(
        width: (flex[7] / totalFlex) * (totalWidth - 32),
        child: _buildActionsForSituation(n),
      ),
    ];

    return InkWell(
      onTap: () {},
      hoverColor: _lilas.withValues(alpha: 0.3),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: rowIndex.isEven ? Colors.white : _cinzaClaro.withValues(alpha: 0.3),
          border: const Border(bottom: BorderSide(color: _borda, width: 0.5)),
        ),
        child: Row(
          children: List.generate(cells.length, (i) => cells[i]),
        ),
      ),
    );
  }

  Widget _buildTableCell({required double width, required Widget child}) {
    return SizedBox(
      width: width,
      child: child,
    );
  }

  Widget _buildClienteCell(Map<String, dynamic> n) {
    final nome = _str(n, 'cliente_nome', '—');
    final cpf = _str(n, 'cliente_cpf_cnpj', '');
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircleAvatar(
          radius: 14,
          backgroundColor: _lilas,
          child: Text(
            nome.isNotEmpty ? nome[0].toUpperCase() : '?',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: _roxo,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              nome,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: _textoPrimario,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (cpf.isNotEmpty)
              Text(
                cpf,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 10,
                  color: _textoSecundario,
                ),
              ),
          ],
        ),
      ],
    );
  }

  // ─── AÇÕES POR SITUAÇÃO (compactas) ──────────────────────

  Widget _buildActionsForSituation(Map<String, dynamic> n) {
    final sit = _str(n, 'situacao');
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (sit == 'aguardando_emissao')
          _compactBtn('Emitir', Icons.rocket_launch_rounded, _roxo,
              () => _abrirModalEmitirNota(n))
        else if (sit == 'processando' || sit == 'falha_temporaria')
          _compactBtn(
              sit == 'processando'
                  ? 'Processando...'
                  : 'Falha temporária',
              sit == 'processando'
                  ? Icons.hourglass_top_rounded
                  : Icons.error_outline_rounded,
              _amarelo, null)
        else if (sit == 'emitida')
          _compactBtn('Enviar', Icons.send_rounded, _azul,
              () => _abrirModalEnviarNota(n))
        else if (sit == 'contingencia')
          _compactBtn('Contingência', Icons.warning_amber_rounded, _laranja,
              () => _mostrarDetalhesContingencia(n))
        else if (sit == 'cancelada' || sit == 'numeracao_inutilizada')
          _compactBtn(sit == 'cancelada' ? 'Cancelada' : 'Inutilizada',
              Icons.block_rounded, _vermelho, null)
        else ...[
          _compactBtn('Visualizar', Icons.visibility_rounded, _roxoClaro,
              () => _visualizarDanfe(n)),
        ],
        const SizedBox(width: 4),
        _buildThreeDotsMenu(n),
      ],
    );
  }

  Widget _compactBtn(String label, IconData icon, Color cor, VoidCallback? onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: onTap != null ? cor.withValues(alpha: 0.1) : _cinzaClaro,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: onTap != null ? cor.withValues(alpha: 0.2) : _borda),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: onTap != null ? cor : _textoSecundario),
            const SizedBox(width: 3),
            Text(
              label,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 9,
                fontWeight: FontWeight.w600,
                color: onTap != null ? cor : _textoSecundario,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── MENU TRÊS PONTINHOS (compacto) ──────────────────────

  Widget _buildThreeDotsMenu(Map<String, dynamic> n) {
    final sit = _str(n, 'situacao');
    final emitidaEnviadaAutorizada =
        (sit == 'emitida' || sit == 'enviada' || sit == 'autorizada');
    final podeReenviar = (sit == 'emitida' || sit == 'enviada' ||
        sit == 'autorizada' || sit == 'cc_e_enviada');
    final podeConsultar = (sit == 'emitida' || sit == 'enviada' ||
        sit == 'autorizada' || sit == 'rejeitada' || sit == 'cancelada');

    return PopupMenuButton<String>(
      offset: const Offset(0, 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 4,
      onSelected: (value) => _executarAcao(value, n),
      itemBuilder: (_) {
        final items = <PopupMenuEntry<String>>[];

        items.add(const PopupMenuItem(
          value: 'visualizar_danfe',
          child: _AcaoMenuItem(Icons.picture_as_pdf_rounded, 'Visualizar DANFE', _roxoClaro),
        ));
        items.add(const PopupMenuItem(
          value: 'visualizar_xml',
          child: _AcaoMenuItem(Icons.code_rounded, 'Visualizar XML', _roxo),
        ));
        items.add(const PopupMenuItem(
          value: 'baixar_xml',
          child: _AcaoMenuItem(Icons.download_rounded, 'Download XML', _verde),
        ));
        items.add(const PopupMenuItem(
          value: 'baixar_pdf',
          child: _AcaoMenuItem(Icons.picture_as_pdf_rounded, 'Download DANFE', _laranja),
        ));

        // Reenviar e-mail (apenas notas que já foram enviadas/processadas)
        if (podeReenviar) {
          items.add(const PopupMenuItem(
            value: 'reenviar_email',
            child: _AcaoMenuItem(Icons.email_rounded, 'Reenviar por e-mail', _azul),
          ));
        }

        // Cancelamento (apenas notas autorizadas dentro do prazo)
        if (emitidaEnviadaAutorizada) {
          final podeCancelar = _podeCancelarNfe(n);
          items.add(PopupMenuItem(
            value: 'cancelar',
            enabled: podeCancelar,
            child: _AcaoMenuItem(
              Icons.block_rounded,
              podeCancelar ? 'Cancelar NF-e' : 'Prazo expirado (24h)',
              podeCancelar ? _vermelho : _textoSecundario,
            ),
          ));
        }

        // Carta de Correção (CC-e) — apenas notas autorizadas
        if (emitidaEnviadaAutorizada) {
          final cceAtual = (n['cartas_correcao'] as List?)?.length ?? 0;
          final podeCce = cceAtual < FiscalCartaCorrecaoService.maxCartasPorNfe;
          items.add(PopupMenuItem(
            value: 'cce',
            enabled: podeCce,
            child: _AcaoMenuItem(
              Icons.edit_note_rounded,
              podeCce
                  ? 'Carta de Correção (CC-e)'
                  : 'Limite de CC-e atingido (${FiscalCartaCorrecaoService.maxCartasPorNfe})',
              podeCce ? _laranja : _textoSecundario,
            ),
          ));
        }

        // Inutilizar numeração
        if (!emitidaEnviadaAutorizada &&
            sit != 'processando' &&
            sit != 'numeracao_inutilizada') {
          items.add(const PopupMenuItem(
            value: 'inutilizar',
            child: _AcaoMenuItem(Icons.numbers_rounded, 'Inutilizar Numeração', _vermelho),
          ));
        }

        // Consultar SEFAZ
        if (podeConsultar) {
          items.add(const PopupMenuItem(
            value: 'consultar_sefaz',
            child: _AcaoMenuItem(Icons.search_rounded, 'Consultar Situação no SEFAZ', _roxo),
          ));
        }

        // Histórico
        items.add(const PopupMenuItem(
          value: 'historico',
          child: _AcaoMenuItem(Icons.history_rounded, 'Histórico Completo', _textoSecundario),
        ));

        // Separador antes de ações destrutivas
        items.add(const PopupMenuDivider(height: 1));

        // Deletar documento (disponível para todas as situações)
        items.add(const PopupMenuItem(
          value: 'deletar',
          child: _AcaoMenuItem(Icons.delete_forever_rounded, 'Deletar NF-e', _vermelho),
        ));

        return items;
      },
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: _cinzaClaro,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: _borda),
        ),
        child: const Icon(Icons.more_horiz_rounded, size: 14, color: _textoSecundario),
      ),
    );
  }

  bool _podeCancelarNfe(Map<String, dynamic> n) {
    // Prazo legal: 24h após autorização ou 7 dias (depende do estado)
    // Simplificação: até 24h após autorização
    final dataAutorizacao = n['data_autorizacao'];
    if (dataAutorizacao is Timestamp) {
      final diff = DateTime.now().difference(dataAutorizacao.toDate());
      return diff.inHours < 24;
    }
    final dataEmissao = n['data_emissao'];
    if (dataEmissao is Timestamp) {
      final diff = DateTime.now().difference(dataEmissao.toDate());
      return diff.inHours < 24;
    }
    return false;
  }

  Future<void> _executarAcao(String acao, Map<String, dynamic> n) async {
    switch (acao) {
      case 'visualizar_danfe':
        _visualizarDanfe(n);
        break;
      case 'visualizar_xml':
        _visualizarXml(n);
        break;
      case 'baixar_xml':
        _baixarXml(n);
        break;
      case 'baixar_pdf':
        _baixarPdf(n);
        break;
      case 'reenviar_email':
        await _abrirModalEnviarNota(n);
        break;
      case 'cancelar':
        await _cancelarNfe(n);
        break;
      case 'cce':
        await _emitirCce(n);
        break;
      case 'inutilizar':
        await _inutilizarNumeracao(n);
        break;
      case 'consultar_sefaz':
        await _consultarSefaz(n);
        break;
      case 'historico':
        _mostrarHistorico(n);
        break;
      case 'deletar':
        await _deletarDocumento(n);
        break;
    }
  }

  // ===========================================================================
  // ABA NOTAS (genérica)
  // ===========================================================================

  Widget _buildAbaNotas(List<Map<String, dynamic>> notas, String tipo, {int pagina = 1, ValueChanged<int>? onPageChanged}) {
    if (notas.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox_rounded,
                size: 48,
                color: _textoSecundario.withValues(alpha: 0.3)),
            const SizedBox(height: 12),
            Text(
              'Nenhuma $tipo',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: _textoSecundario,
              ),
            ),
          ],
        ),
      );
    }

    return _buildTabelaGenericaNotas(notas, pagina: pagina, onPageChanged: onPageChanged);
  }

  // Action button reutilizado (uso em filtros da aba historico)
  Widget _actionButton(
      String label, IconData icon, Color cor, VoidCallback? onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: onTap != null ? cor.withValues(alpha: 0.1) : _cinzaClaro,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: onTap != null ? cor.withValues(alpha: 0.3) : _borda),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: onTap != null ? cor : _textoSecundario),
            const SizedBox(width: 4),
            Text(
              label,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: onTap != null ? cor : _textoSecundario,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabelaGenericaNotas(
    List<Map<String, dynamic>> notas, {
    int pagina = 1,
    ValueChanged<int>? onPageChanged,
  }) {
    if (notas.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80, height: 80,
              decoration: BoxDecoration(
                color: _lilas,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(Icons.inbox_rounded,
                  size: 36, color: _roxo.withValues(alpha: 0.4)),
            ),
            const SizedBox(height: 12),
            Text(
              'Nenhum resultado encontrado',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: _textoSecundario,
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 16, 32, 16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final tableWidth = constraints.maxWidth;
          final colFlex = [1.5, 2.5, 1.2, 1.2, 1.2, 1.5];
          final totalFlex = colFlex.fold<double>(0, (a, b) => a + b);
          return ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Container(
              width: tableWidth,
              decoration: BoxDecoration(
                border: Border.all(color: _borda),
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: _roxo.withValues(alpha: 0.04),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SizedBox(
                        width: tableWidth > 600 ? tableWidth : null,
                        child: Column(
                          mainAxisSize: MainAxisSize.max,
                          children: [
                            _buildGenericHeader(colFlex, totalFlex, tableWidth),
                            // Data rows com rolagem vertical própria
                            Expanded(
                              child: SingleChildScrollView(
                                scrollDirection: Axis.vertical,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: _paginarLista(notas, pagina).map((n) => _buildGenericRow(n, colFlex, totalFlex, tableWidth)).toList(),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  onPageChanged != null
                      ? _buildPaginacao(notas.length, pagina, onPageChanged)
                      : const SizedBox.shrink(),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildGenericHeader(List<double> flex, double totalFlex, double totalWidth) {
    const labels = ['Nº NF-e', 'Cliente', 'Valor', 'Emissão', 'Situação', 'Ações'];
    return Container(
      decoration: const BoxDecoration(
        color: _roxo,
        border: Border(bottom: BorderSide(color: _laranja, width: 2)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: List.generate(labels.length, (i) {
          final width = (flex[i] / totalFlex) * (totalWidth - 32);
          return SizedBox(
            width: width,
            child: Text(
              labels[i],
              style: GoogleFonts.plusJakartaSans(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          );
        }),
      ),
    );
  }

  Widget _buildGenericRow(Map<String, dynamic> n, List<double> flex, double totalFlex, double totalWidth) {
    final cells = [
      SizedBox(
        width: (flex[0] / totalFlex) * (totalWidth - 32),
        child: Text(
          _str(n, 'numero_nfe').isNotEmpty ? _str(n, 'numero_nfe') : '—',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 11, fontWeight: FontWeight.w600, color: _textoPrimario,
          ),
          overflow: TextOverflow.ellipsis,
        ),
      ),
      SizedBox(
        width: (flex[1] / totalFlex) * (totalWidth - 32),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 12, backgroundColor: _lilas,
              child: Text(
                _str(n, 'cliente_nome', '?')[0].toUpperCase(),
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 10, fontWeight: FontWeight.w700, color: _roxo,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                _str(n, 'cliente_nome'),
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: GoogleFonts.plusJakartaSans(fontSize: 11, color: _textoPrimario),
              ),
            ),
          ],
        ),
      ),
      SizedBox(
        width: (flex[2] / totalFlex) * (totalWidth - 32),
        child: Text(
          _moeda.format(_num(n, 'valor_total')),
          style: GoogleFonts.plusJakartaSans(
            fontSize: 12, fontWeight: FontWeight.w700, color: _textoPrimario,
          ),
        ),
      ),
      SizedBox(
        width: (flex[3] / totalFlex) * (totalWidth - 32),
        child: Text(
          _fmtData(n['data_emissao'] ?? n['data_criacao']),
          style: GoogleFonts.plusJakartaSans(fontSize: 10, color: _textoSecundario),
        ),
      ),
      SizedBox(
        width: (flex[4] / totalFlex) * (totalWidth - 32),
        child: _buildStatusBadge(_str(n, 'situacao')),
      ),
      SizedBox(
        width: (flex[5] / totalFlex) * (totalWidth - 32),
        child: _buildActionsForSituation(n),
      ),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _borda, width: 0.5)),
      ),
      child: Row(
        children: List.generate(cells.length, (i) => cells[i]),
      ),
    );
  }

  // ===========================================================================
  // PAGINAÇÃO — rodapé premium reutilizável
  // ===========================================================================

  Widget _buildPaginacao(int total, int paginaAtual, ValueChanged<int> onPageChanged) {
    if (total <= _itensPorPagina) return const SizedBox.shrink();

    final totalPaginas = (total / _itensPorPagina).ceil();
    final inicio = ((paginaAtual - 1) * _itensPorPagina) + 1;
    final fim = (paginaAtual * _itensPorPagina).clamp(0, total);

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: _borda.withValues(alpha: 0.6))),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(14),
          bottomRight: Radius.circular(14),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isMobile = constraints.maxWidth < 500;
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Info "Exibindo X–Y de Z registros" com Flexible p/ não overflow
              Flexible(
                child: Text(
                'Exibindo $inicio–$fim de $total registros',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  color: _textoSecundario,
                  fontWeight: FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 12),
              // Botões de página
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Anterior
                  _pagBtn(
                    Icons.chevron_left_rounded,
                    paginaAtual <= 1,
                    () => onPageChanged(paginaAtual - 1),
                  ),
                  if (!isMobile) ...[
                    const SizedBox(width: 4),
                    // Números das páginas
                    ..._buildPaginaNumeros(totalPaginas, paginaAtual, onPageChanged),
                    const SizedBox(width: 4),
                  ] else ...[
                    const SizedBox(width: 8),
                    Text(
                      '$paginaAtual / $totalPaginas',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _textoPrimario,
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  // Próximo
                  _pagBtn(
                    Icons.chevron_right_rounded,
                    paginaAtual >= totalPaginas,
                    () => onPageChanged(paginaAtual + 1),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  List<Widget> _buildPaginaNumeros(int totalPaginas, int paginaAtual, ValueChanged<int> onPageChanged) {
    final botoes = <Widget>[];
    final inicio = [1, 2, 3].contains(paginaAtual) ? 1 : paginaAtual - 1;
    final fim = (inicio + 2).clamp(1, totalPaginas);
    final exibirPaginas = List.generate(fim - inicio + 1, (i) => inicio + i);

    // Primeira página + reticências
    if (exibirPaginas.first > 2) {
      botoes.add(_pagBtnNum(1, paginaAtual == 1, () => onPageChanged(1)));
      if (exibirPaginas.first > 2) {
        botoes.add(Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text('...', style: GoogleFonts.plusJakartaSans(
            fontSize: 12, color: _textoSecundario)),
        ));
      }
    } else if (exibirPaginas.first == 2) {
      botoes.add(_pagBtnNum(1, paginaAtual == 1, () => onPageChanged(1)));
    } else if (exibirPaginas.first == 1) {
      // Já está na primeira, não adiciona extra
    }

    // Páginas do bloco
    for (final p in exibirPaginas) {
      botoes.add(_pagBtnNum(p, p == paginaAtual, () => onPageChanged(p)));
    }

    // Última página + reticências
    if (exibirPaginas.last < totalPaginas - 1) {
      botoes.add(Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Text('...', style: GoogleFonts.plusJakartaSans(
          fontSize: 12, color: _textoSecundario)),
      ));
      botoes.add(_pagBtnNum(totalPaginas, paginaAtual == totalPaginas, () => onPageChanged(totalPaginas)));
    } else if (exibirPaginas.last < totalPaginas) {
      botoes.add(_pagBtnNum(totalPaginas, paginaAtual == totalPaginas, () => onPageChanged(totalPaginas)));
    }

    return botoes;
  }

  Widget _pagBtn(IconData icon, bool desabilitado, VoidCallback onTap) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: desabilitado ? null : onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: desabilitado ? _cinzaClaro : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: desabilitado ? _borda : _borda,
            ),
          ),
          child: Icon(icon, size: 18,
            color: desabilitado ? _textoSecundario.withValues(alpha: 0.4) : _textoPrimario),
        ),
      ),
    );
  }

  Widget _pagBtnNum(int num, bool ativo, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Material(
        color: ativo ? _roxo : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: ativo ? null : onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: ativo ? _roxo : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: ativo ? _roxo : _borda,
              ),
            ),
            child: Text(
              num.toString(),
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: ativo ? Colors.white : _textoPrimario,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // ABA REJEITADAS (com motivo + código + botões corrigir/emitir novamente)
  // ===========================================================================

  Widget _buildAbaRejeitadas() {
    final rejeitadas = _notasFiltradas
        .where((n) => _str(n, 'situacao') == 'rejeitada')
        .toList();
    if (rejeitadas.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_outline,
                size: 48,
                color: _textoSecundario.withValues(alpha: 0.3)),
            const SizedBox(height: 12),
            Text(
              'Nenhuma nota rejeitada',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: _textoSecundario,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(32, 16, 32, 16),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: _borda),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: SingleChildScrollView(
                  scrollDirection: Axis.vertical,
                  child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    headingRowColor: WidgetStateProperty.all(_roxo),
                    headingTextStyle: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                    dataTextStyle: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      color: _textoPrimario,
                    ),
                    horizontalMargin: 16,
                    columnSpacing: 24,
                    dataRowMinHeight: 40,
                    dataRowMaxHeight: 52,
                    columns: const [
                      DataColumn(label: Text('Nº NF-e')),
                      DataColumn(label: Text('Cliente')),
                      DataColumn(label: Text('Motivo')),
                      DataColumn(label: Text('Cód. Rejeição')),
                      DataColumn(label: Text('Data')),
                      DataColumn(label: Text('Valor')),
                      DataColumn(label: Text('Ações')),
                    ],
                    rows: _paginarLista(rejeitadas, _paginaRejeitadas).map((n) {
                final motivo =
                    _str(n, 'motivo_rejeicao', _str(n, 'rejeicao_motivo', '—'));
                final codRej = _str(
                    n, 'codigo_rejeicao', _str(n, 'rejeicao_codigo', '—'));
                return DataRow(cells: [
                  DataCell(Text(_str(n, 'numero_nfe').isNotEmpty
                      ? _str(n, 'numero_nfe')
                      : '—')),
                  DataCell(Text(_str(n, 'cliente_nome'),
                      maxLines: 1, overflow: TextOverflow.ellipsis)),
                  DataCell(SizedBox(
                    width: 200,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          motivo,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 11, color: _vermelho),
                        ),
                      ],
                    ),
                  )),
                  DataCell(Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: _vermelhoFundo,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      codRej,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: _vermelho,
                      ),
                    ),
                  )),
                  DataCell(Text(_fmtData(n['data_emissao'] ??
                      n['data_criacao']))),
                  DataCell(Text(_moeda.format(_num(n, 'valor_total')))),
                  DataCell(Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _actionButton(
                        'Corrigir',
                        Icons.edit_rounded,
                        _laranja,
                        () => _corrigirNotaRejeitada(n),
                      ),
                      const SizedBox(width: 4),
                      _actionButton(
                        'Emitir',
                        Icons.refresh_rounded,
                        _roxo,
                        () => _abrirModalEmitirNota(n),
                      ),
                    ],
                  )),
                ]);
              }).toList(),
            ),
          ),
        ),
      ),
    ),
    ),
    ),
    _buildPaginacao(rejeitadas.length, _paginaRejeitadas, (p) =>
        setState(() => _paginaRejeitadas = p)),
  ],
);
  }

  Future<void> _corrigirNotaRejeitada(Map<String, dynamic> n) async {
    if (!mounted) return;
    // Reabre o wizard de criação com os dados existentes para correção
    final cliente =
        _clientesGc.where((c) => c.id == _str(n, 'cliente_id')).firstOrNull;
    if (cliente == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Cliente não encontrado para correção.'),
            backgroundColor: _vermelho,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }
    // Cria nova nota corrigida (a rejeitada permanece para histórico)
    await _abrirModalCriarNota(cliente);
  }

  // ===========================================================================
  // ABA CANCELADAS (com motivo + data + hora + usuário)
  // ===========================================================================

  Widget _buildAbaCanceladas() {
    final canceladas = _notasFiltradas
        .where((n) => _str(n, 'situacao') == 'cancelada')
        .toList();
    if (canceladas.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.block_rounded,
                size: 48,
                color: _textoSecundario.withValues(alpha: 0.3)),
            const SizedBox(height: 12),
            Text(
              'Nenhuma nota cancelada',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: _textoSecundario,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(32, 16, 32, 16),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: _borda),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: SingleChildScrollView(
                  scrollDirection: Axis.vertical,
                  child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    headingRowColor: WidgetStateProperty.all(_roxo),
                    headingTextStyle: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                    dataTextStyle: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      color: _textoPrimario,
                    ),
                    horizontalMargin: 16,
                    columnSpacing: 24,
                    dataRowMinHeight: 40,
                    dataRowMaxHeight: 52,
                    columns: const [
                      DataColumn(label: Text('Nº NF-e')),
                      DataColumn(label: Text('Cliente')),
                      DataColumn(label: Text('Motivo')),
                      DataColumn(label: Text('Data/Hora')),
                      DataColumn(label: Text('Usuário')),
                      DataColumn(label: Text('Valor')),
                      DataColumn(label: Text('Ações')),
                    ],
                    rows: _paginarLista(canceladas, _paginaCanceladas).map((n) {
                final dataCanc = n['data_cancelamento'] ?? n['data_criacao'];
                return DataRow(cells: [
                  DataCell(Text(_str(n, 'numero_nfe').isNotEmpty
                      ? _str(n, 'numero_nfe')
                      : '—')),
                  DataCell(Text(_str(n, 'cliente_nome'),
                      maxLines: 1, overflow: TextOverflow.ellipsis)),
                  DataCell(SizedBox(
                    width: 200,
                    child: Text(
                      _str(n, 'cancelamento_motivo',
                          _str(n, 'rejeicao_motivo', '—')),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 11, color: _vermelho),
                    ),
                  )),
                  DataCell(Text(_fmtDataHora(dataCanc))),
                  DataCell(Text(
                    _str(n, 'cancelamento_usuario_nome', '—'),
                    style: GoogleFonts.plusJakartaSans(fontSize: 11),
                  )),
                  DataCell(Text(_moeda.format(_num(n, 'valor_total')))),
                  DataCell(_buildThreeDotsMenu(n)),
                ]);
              }).toList(),
            ),
          ),
        ),
      ),
    ),
    ),
    ),
    _buildPaginacao(canceladas.length, _paginaCanceladas, (p) =>
        setState(() => _paginaCanceladas = p)),
  ],
);
  }

  // ===========================================================================
  // ABA HISTÓRICO (com filtros completos)
  // ===========================================================================

  Widget _buildAbaHistorico() {
    // Filtros avançados para o histórico
    return Column(
      children: [
        // Filtros avançados
        Container(
          padding: const EdgeInsets.fromLTRB(32, 16, 32, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Linha 1: filtros principais
              Wrap(
                spacing: 12,
                runSpacing: 10,
                children: [
                  // Cliente
                  SizedBox(
                    width: 180,
                    child: TextField(
                      controller: _filtroHistoricoCtrl,
                      onChanged: (_) => _aplicarFiltros(),
                      decoration: _inputDecor(
                        hint: 'Cliente',
                        icon: Icons.person_rounded,
                      ),
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 12, color: _textoPrimario),
                    ),
                  ),
                  // Número NF-e
                  SizedBox(
                    width: 140,
                    child: TextField(
                      controller: _filtroNumeroCtrl,
                      onChanged: (_) => _aplicarFiltros(),
                      decoration: _inputDecor(
                        hint: 'Nº NF-e',
                        icon: Icons.tag_rounded,
                      ),
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 12, color: _textoPrimario),
                    ),
                  ),
                  // CPF/CNPJ
                  SizedBox(
                    width: 160,
                    child: TextField(
                      controller: _filtroCpfCnpjCtrl,
                      onChanged: (_) => _aplicarFiltros(),
                      decoration: _inputDecor(
                        hint: 'CPF/CNPJ',
                        icon: Icons.badge_rounded,
                      ),
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 12, color: _textoPrimario),
                    ),
                  ),
                  // Data inicial
                  SizedBox(
                    width: 130,
                    child: TextField(
                      controller: _filtroDataInicialCtrl,
                      onChanged: (_) => _aplicarFiltros(),
                      decoration: _inputDecor(
                        hint: 'Data inicial',
                        icon: Icons.calendar_today_rounded,
                      ),
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 12, color: _textoPrimario),
                    ),
                  ),
                  // Data final
                  SizedBox(
                    width: 130,
                    child: TextField(
                      controller: _filtroDataFinalCtrl,
                      onChanged: (_) => _aplicarFiltros(),
                      decoration: _inputDecor(
                        hint: 'Data final',
                        icon: Icons.calendar_today_rounded,
                      ),
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 12, color: _textoPrimario),
                    ),
                  ),
                  // Status
                  _buildFiltroDropdown(
                    'Status',
                    [
                      'Todas',
                      'Aguardando emissão',
                      'Emitida',
                      'Enviada',
                      'Autorizada',
                      'Rejeitada',
                      'Cancelada',
                    ],
                    _filtroStatusHistorico,
                    (v) {
                      setState(() {
                        _filtroStatusHistorico = v;
                        // Sincroniza com filtro global
                        _filtroStatusNfe = v;
                      });
                      _aplicarFiltros();
                    },
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // Linha 2: filtros secundários + ações
              Wrap(
                spacing: 12,
                runSpacing: 10,
                children: [
                  // Município emissor
                  SizedBox(
                    width: 160,
                    child: TextField(
                      controller: _filtroMunicipioCtrl,
                      onChanged: (_) => _aplicarFiltros(),
                      decoration: _inputDecor(
                        hint: 'Município',
                        icon: Icons.location_city_rounded,
                      ),
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 12, color: _textoPrimario),
                    ),
                  ),
                  // Valor
                  SizedBox(
                    width: 120,
                    child: TextField(
                      controller: _filtroValorCtrl,
                      onChanged: (_) => _aplicarFiltros(),
                      decoration: _inputDecor(
                        hint: 'Valor R\$',
                        icon: Icons.attach_money_rounded,
                        isCompact: true,
                      ),
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 12, color: _textoPrimario),
                    ),
                  ),
                  // Forma de pagamento
                  SizedBox(
                    width: 150,
                    child: TextField(
                      controller: _filtroFormaPagamentoCtrl,
                      onChanged: (_) => _aplicarFiltros(),
                      decoration: _inputDecor(
                        hint: 'Forma pagamento',
                        icon: Icons.credit_card_rounded,
                      ),
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 12, color: _textoPrimario),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _actionButton(
                    'Exportar Excel',
                    Icons.table_chart_rounded,
                    _verde,
                    () => _exportarExcel(),
                  ),
                  _actionButton(
                    'Exportar PDF',
                    Icons.picture_as_pdf_rounded,
                    _vermelho,
                    () => _exportarPdf(),
                  ),
                  _actionButton(
                    'Imprimir',
                    Icons.print_rounded,
                    _roxo,
                    () => _imprimir(),
                  ),
                ],
              ),
            ],
          ),
        ),
        Expanded(child: _buildTabelaGenericaNotas(_notasFiltradas,
            pagina: _paginaHistorico, onPageChanged: (p) => setState(() => _paginaHistorico = p))),
      ],
    );
  }

  InputDecoration _inputDecor({
    required String hint,
    required IconData icon,
    bool isCompact = false,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: GoogleFonts.plusJakartaSans(
          fontSize: 12,
          color: _textoSecundario.withValues(alpha: 0.5)),
      prefixIcon: Icon(icon, size: 18, color: _textoSecundario),
      filled: true,
      fillColor: _cinzaClaro,
      contentPadding: EdgeInsets.symmetric(
          horizontal: 12, vertical: isCompact ? 6 : 10),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: _borda),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: _borda),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: _roxo, width: 1.5),
      ),
    );
  }

  // ===========================================================================
  // FILTROS
  // ===========================================================================

  Widget _buildFiltroDropdown(String label, List<String> opcoes,
      String valor, ValueChanged<String> onChange) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 200),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: _cinzaClaro,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _borda),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          isExpanded: true,
          value: opcoes.contains(valor) ? valor : opcoes.first,
          icon: const Icon(Icons.arrow_drop_down_rounded,
              size: 20, color: _textoSecundario),
          style: GoogleFonts.plusJakartaSans(
              fontSize: 12, color: _textoPrimario),
          items: opcoes
              .map((o) => DropdownMenuItem(
                  value: o,
                  child:
                      Text(o, style: GoogleFonts.plusJakartaSans(fontSize: 12))))
              .toList(),
          onChanged: (v) {
            if (v != null) onChange(v);
          },
        ),
      ),
    );
  }

  // ===========================================================================
  // STATUS BADGE
  // ===========================================================================

  Widget _buildStatusBadge(String situacao) {
    final info = _statusInfo(situacao);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: info.fundo,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: info.cor.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
            color: info.cor.withValues(alpha: 0.08),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: info.cor,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: info.cor.withValues(alpha: 0.4),
                  blurRadius: 3,
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              info.label,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: info.cor,
                letterSpacing: 0.2,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
        ],
      ),
    );
  }

  _StatusInfo _statusInfo(String situacao) {
    switch (situacao) {
      case 'aguardando_emissao':
        return _StatusInfo('Aguardando emissão', const Color(0xFFE67E22),
            const Color(0xFFFEF3EC));
      case 'emitida':
        return _StatusInfo('Emitida', _azul, _azulFundo);
      case 'enviada':
        return _StatusInfo('Enviada', _roxo, _lilas);
      case 'autorizada':
        return _StatusInfo('Autorizada', _verde, _verdeFundo);
      case 'processando':
        return _StatusInfo('Processando', _amarelo, _amareloFundo);
      case 'falha_temporaria':
        return _StatusInfo(
            'Falha temporária', _laranja, _amareloFundo);
      case 'contingencia':
        return _StatusInfo(
            'Contingência', _laranja, const Color(0xFFFFF3E0));
      case 'rejeitada':
        return _StatusInfo('Rejeitada', _vermelho, _vermelhoFundo);
      case 'cancelada':
        return _StatusInfo('Cancelada', const Color(0xFF636363), const Color(0xFFF0F0F0));
      case 'cc_enviada':
        return _StatusInfo('CC-e enviada', _laranja, _amareloFundo);
      case 'numeracao_inutilizada':
        return _StatusInfo('Numeração inutilizada', const Color(0xFF636363), const Color(0xFFF0F0F0));
      default:
        return _StatusInfo(
            'Não emitida', _textoSecundario, const Color(0xFFF3F4F6));
    }
  }

  // ===========================================================================
  // MODAL — CRIAR NOTA FISCAL (WIZARD 3 ETAPAS)
  // ===========================================================================

  Future<void> _abrirModalCriarNota(ComercialCliente cliente) async {
    if (_storeId.isEmpty) return;
    if (!mounted) return;
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _CriarNotaFiscalWizard(
        storeId: _storeId,
        cliente: cliente,
      ),
    );
    if (result == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nota fiscal criada com sucesso!'),
          backgroundColor: _verde,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  // MODAL — EMITIR NOTA (com animação de transmissão)
  // ===========================================================================

  Future<void> _abrirModalEmitirNota(Map<String, dynamic> n) async {
    if (!mounted) return;

    // ═══ FORÇA RECARGA DOS DADOS FISCAIS DO FIREBASE ═══
    // Garante que a emissão sempre use dados frescos, nunca cacheados
    debugPrint('[ModuloFiscal] Recarregando dados fiscais do Firebase antes da emissão...');
    final oldTaxKeys = Map<String, dynamic>.from(_companyTaxData);
    await _carregarCompanyTaxData(_storeId);
    debugPrint('[ModuloFiscal] Dados fiscais recarregados. company_tax_data: ${_companyTaxData.isNotEmpty ? "OK" : "VAZIO"}');
    if (!_companyTaxData.isNotEmpty) {
      debugPrint('[ModuloFiscal] ⚠️ company_tax_data VAZIO após recarga! Dados antigos: $oldTaxKeys');
    } else {
      debugPrint('[ModuloFiscal] company_tax_data após recarga: ${jsonEncode(_companyTaxData)}');
    }

    // ═══ DIAGNÓSTICO COMPLETO ═══
    debugPrint('');
    debugPrint('═══════════════════════════════════════════════');
    debugPrint(' DIAGNÓSTICO — EMISSÃO NF-e');
    debugPrint('═══════════════════════════════════════════════');
    debugPrint(' storeId: $_storeId');
    debugPrint('');
    debugPrint(' — Integração (lojista_integracao) —');
    debugPrint(' encontrada: ${_integracao != null}');
    debugPrint(' storeId: ${_integracao?.storeId}');
    debugPrint(' status: ${_integracao?.status}');
    debugPrint(' estaAtiva: ${_integracao?.estaAtiva}');
    debugPrint(' limiteMensal: ${_integracao?.limiteMensal}');
    debugPrint(' notasEmitidas: ${_integracao?.notasEmitidas}');
    debugPrint(' ehIlimitado: ${_integracao?.ehIlimitado}');
    debugPrint('');
    debugPrint(' — Dados Fiscais (store_fiscal_settings) —');
    debugPrint(' companyTaxData encontrado: ${_companyTaxData.isNotEmpty}');
    debugPrint(' companyTaxData keys: ${_companyTaxData.keys.join(', ')}');
    debugPrint(' razaoSocial: ${_str(_companyTaxData, 'razao_social')}');
    debugPrint(' cnpj: ${_str(_companyTaxData, 'cnpj')}');
    debugPrint(' ie: ${_str(_companyTaxData, 'ie')}');
    debugPrint(' regime: ${_str(_companyTaxData, 'regime_tributario')}');
    debugPrint(' crt: ${_str(_companyTaxData, 'crt')}');
    debugPrint(' endereco: ${_str(_companyTaxData, 'endereco_fiscal')}');
    debugPrint('');
    debugPrint(' — Ambiente —');
    debugPrint(' homologacao: $_ambienteHomologacaoNfe');
    debugPrint('');
    debugPrint(' — Contingência —');
    debugPrint(' emContingencia: $_emContingencia');
    debugPrint(' motivo: $_motivoContingencia');
    debugPrint('═══════════════════════════════════════════════');
    debugPrint('');

    final notaId = _str(n, '__docId');
    final clienteNome = _str(n, 'cliente_nome');
    final clienteCpfCnpj = _str(n, 'cliente_cpf_cnpj');
    final clienteEmail = _str(n, 'cliente_email');
    final clienteTelefone = _str(n, 'cliente_telefone');
    final clienteRua = _str(n, 'cliente_rua');
    final clienteNumero = _str(n, 'cliente_numero');
    final clienteBairro = _str(n, 'cliente_bairro');
    final clienteCidade = _str(n, 'cliente_cidade');
    final clienteEstado = _str(n, 'cliente_estado');
    final clienteCep = _str(n, 'cliente_cep');
    final clienteCodigoIbge = _str(n, 'cliente_codigo_ibge');
    final clienteIe = _str(n, 'cliente_ie');
    final natureza = _str(n, 'natureza_operacao');
    final cfop = _str(n, 'cfop');
    final formaPagto = _str(n, 'forma_pagamento');
    final observacoes = _str(n, 'observacoes');
    final subtotal = _num(n, 'subtotal');
    final descontoGeral = _num(n, 'desconto_geral');
    final frete = _num(n, 'frete');
    final valorTotal = _num(n, 'valor_total');
    final baseIcms = _num(n, 'base_icms');
    final produtosRaw = (n['produtos'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];

    // Busca dados fiscais do emitente
    final emitenteData = _companyTaxData;
    final razaoSocial = _str(emitenteData, 'razao_social');
    final nomeFantasia = _str(emitenteData, 'nome_fantasia');
    final emitenteCnpj = _str(emitenteData, 'cnpj');
    final emitenteIe = _str(emitenteData, 'ie');
    final emitenteCrt = _str(emitenteData, 'crt');
    final emitenteLogradouro = _str(emitenteData, 'logradouro');
    final emitenteNumero = _str(emitenteData, 'numero');
    final emitenteBairro = _str(emitenteData, 'bairro');
    final emitenteCidade = _str(emitenteData, 'cidade');
    final emitenteUf = _str(emitenteData, 'uf');
    final emitenteCep = _str(emitenteData, 'cep');
    // Fallback: se não há campos individuais, usa endereco_fiscal completo como logradouro
    final enderecoFiscalFallback = _str(emitenteData, 'endereco_fiscal');
    final logradouroFinal = emitenteLogradouro.isNotEmpty
        ? emitenteLogradouro
        : enderecoFiscalFallback;

    if (razaoSocial.isEmpty || emitenteCnpj.isEmpty) {
      if (!mounted) return;
      debugPrint('[ModuloFiscal] ⚠️ VALIDAÇÃO PRÉ-EMISSÃO FALHOU');
      debugPrint('[ModuloFiscal] razaoSocial="$razaoSocial" vazio=${razaoSocial.isEmpty}');
      debugPrint('[ModuloFiscal] emitenteCnpj="$emitenteCnpj" vazio=${emitenteCnpj.isEmpty}');
      debugPrint('[ModuloFiscal] companyTaxData keys=${emitenteData.keys.join(', ')}');
      debugPrint('[ModuloFiscal] Doc store_fiscal_settings lido: storeId=$_storeId');
      final camposVazios = <String>[];
      if (razaoSocial.isEmpty) camposVazios.add('razao_social');
      if (emitenteCnpj.isEmpty) camposVazios.add('cnpj');
      if (emitenteIe.isEmpty) camposVazios.add('ie (inscricao estadual)');
      if (emitenteLogradouro.isEmpty) camposVazios.add('logradouro');
      if (emitenteNumero.isEmpty) camposVazios.add('numero');
      if (emitenteBairro.isEmpty) camposVazios.add('bairro');
      if (emitenteCidade.isEmpty) camposVazios.add('cidade');
      if (emitenteUf.isEmpty) camposVazios.add('uf');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Configure os dados fiscais da empresa antes de emitir. Campos vazios: ${camposVazios.join(", ")}. '
              'Verifique company_tax_data em store_fiscal_settings.'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 10),
        ),
      );
      return;
    }

    // Constrói itens
    final itens = produtosRaw.map((p) => FiscalItem(
      descricao: _str(p, 'nome'),
      quantidade: _num(p, 'quantidade'),
      valorUnitario: _num(p, 'valor_unitario'),
      valorTotal: _num(p, 'total'),
      // NCM: se vazio usa fallback 99999999 (o provider também normaliza)
      ncm: _str(p, 'ncm').isNotEmpty ? _str(p, 'ncm') : null,
      cfop: cfop.isNotEmpty ? cfop : (_str(n, 'cfop')),
      codigoProduto: _str(p, 'codigo'),
      desconto: _num(p, 'desconto'),
      cstIcms: _str(p, 'cst_icms').isNotEmpty ? _str(p, 'cst_icms') : null,
    )).toList();

    final payload = FiscalPayload(
      tipoDocumento: TipoDocumentoFiscal.nfe,
      emitente: FiscalEmitente(
        razaoSocial: razaoSocial,
        nomeFantasia: nomeFantasia,
        cnpj: emitenteCnpj,
        ie: emitenteIe,
        crt: emitenteCrt.isNotEmpty ? emitenteCrt : null,
        logradouro: logradouroFinal,
        numero: emitenteNumero,
        bairro: emitenteBairro,
        cidade: emitenteCidade,
        uf: emitenteUf,
        cep: emitenteCep,
        codigoCidade: _str(emitenteData, 'codigo_cidade').isNotEmpty
            ? _str(emitenteData, 'codigo_cidade') : null,
        // ⚠️ CRÍTICO: regime_tributario precisa ser passado para o provider normalizar
        regimeTributario: _str(emitenteData, 'regime_tributario').isNotEmpty
            ? _str(emitenteData, 'regime_tributario') : null,
      ),
      destinatario: FiscalDestinatario(
        nome: clienteNome,
        cpfCnpj: clienteCpfCnpj,
        ie: clienteIe,
        email: clienteEmail,
        telefone: clienteTelefone,
        logradouro: clienteRua,
        numero: clienteNumero,
        bairro: clienteBairro,
        cidade: clienteCidade,
        uf: clienteEstado,
        cep: clienteCep,
        indicadorContribuinte: _str(n, 'indicador_ie'),
        // Código IBGE do cliente
        codigoCidade: clienteCodigoIbge.isNotEmpty
            ? clienteCodigoIbge : null,
      ),
      itens: itens,
      totais: FiscalTotais(
        baseCalculoIcms: baseIcms,
        valorIcms: 0,
        valorProdutos: subtotal,
        valorFrete: frete,
        valorDesconto: descontoGeral,
        valorTotal: valorTotal,
      ),
      pagamento: FiscalPagamento(
        formaPagamento: formaPagto.isNotEmpty ? formaPagto : 'pix',
        valorPago: valorTotal,
      ),
      naturezaOperacao: natureza,
      cfop: cfop,
      informacoesAdicionais: observacoes,
      clienteId: _str(n, 'cliente_id'),
    );

    if (!mounted) return;

    // Adiciona dados da integração lojista e certificado ao storeSettingsData
    final storeDataComIntegracao = Map<String, dynamic>.from(_storeSettingsFullData);
    if (_integracao != null) {
      storeDataComIntegracao['lojista_integration_id'] = _integracao!.id;
    }
    // Certificado digital vindo dos dados fiscais ou da integração
    final certId = _str(_storeSettingsFullData, 'certificate_id');
    if (certId.isNotEmpty) {
      storeDataComIntegracao['certificate_id'] = certId;
    }

    final resultado = await FiscalEmissaoModal.mostrar(
      context: context,
      lojaId: _storeId,
      payload: payload,
      homologacao: _ambienteHomologacaoNfe,
      emitirNfce: false,
      integrationId: _integrationId,
      storeSettingsData: storeDataComIntegracao,
    );

    // Atualiza Firestore com resultado
    if (resultado != null && notaId.isNotEmpty) {
      final now = DateTime.now();
      final status = resultado.sucesso ? 'emitida' : 'rejeitada';
      final logs = List<Map<String, dynamic>>.from(n['logs'] as List? ?? []);
      logs.add({
        'evento': resultado.sucesso ? 'emitida' : 'rejeitada',
        'data': Timestamp.fromDate(now),
        'usuario': FirebaseAuth.instance.currentUser?.uid ?? '',
        'descricao': resultado.sucesso
            ? 'NF-e emitida — Chave: ${resultado.chaveAcesso ?? "N/A"}'
            : 'Rejeitada: ${resultado.erro ?? "Erro desconhecido"}',
      });

      try {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(_storeId)
            .collection('notas_fiscais')
            .doc(notaId)
            .update({
          'situacao': status,
          'numero_nfe': resultado.numero ?? '',
          'chave_acesso': resultado.chaveAcesso ?? '',
          'serie': resultado.serie ?? '',
          'protocolo': resultado.protocolo ?? '',
          'xml_url': resultado.xmlUrl ?? '',
          'pdf_url': resultado.pdfUrl ?? '',
          'data_emissao': resultado.sucesso ? Timestamp.fromDate(now) : null,
          'logs': logs,
          'ultima_atualizacao': Timestamp.fromDate(now),
        });
      } catch (_) {}
    }
  }

  // ===========================================================================
  // MODAL — ENVIAR NOTA (com animação de envio)
  // ===========================================================================

  Future<void> _abrirModalEnviarNota(Map<String, dynamic> n) async {
    if (!mounted) return;
    final confirmou = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _EnviarNotaModal(
        storeId: _storeId,
        notaId: _str(n, '__docId'),
        clienteNome: _str(n, 'cliente_nome'),
        clienteEmail: _str(n, 'cliente_email'),
        numeroNfe: _str(n, 'numero_nfe'),
      ),
    );
    if (confirmou == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('NF-e enviada ao cliente com sucesso.'),
          backgroundColor: _verde,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  // ===========================================================================
  // AÇÕES
  // ===========================================================================

  void _visualizarDanfe(Map<String, dynamic> n) {
    showDialog(
      context: context,
      builder: (_) => _DanfePreviewDialog(
        chaveAcesso: _str(n, 'chave_acesso'),
        numeroNfe: _str(n, 'numero_nfe'),
      ),
    );
  }

  void _visualizarXml(Map<String, dynamic> n) {
    showDialog(
      context: context,
      builder: (_) => _XmlPreviewDialog(
        numeroNfe: _str(n, 'numero_nfe'),
        xmlConteudo: _str(n, 'xml_conteudo'),
      ),
    );
  }

  void _baixarXml(Map<String, dynamic> n) {
    final xmlUrl = _str(n, 'xml_url');
    if (xmlUrl.isNotEmpty) {
      try {
        launchUrl(Uri.parse(xmlUrl), mode: LaunchMode.externalApplication);
      } catch (_) {
        _mostrarDownloadManual(xmlUrl, 'XML', n);
      }
    } else if (n['xml_conteudo'] != null &&
        (n['xml_conteudo'] as String).isNotEmpty) {
      _baixarConteudoComoArquivo(
        n['xml_conteudo'] as String,
        'NF-e_${_str(n, 'numero_nfe', 'sem_numero')}.xml',
        'application/xml',
      );
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'XML da NF-e ${_str(n, 'numero_nfe')} não disponível para download.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _baixarPdf(Map<String, dynamic> n) {
    final pdfUrl = _str(n, 'pdf_url');
    if (pdfUrl.isNotEmpty) {
      try {
        launchUrl(Uri.parse(pdfUrl), mode: LaunchMode.externalApplication);
      } catch (_) {
        _mostrarDownloadManual(pdfUrl, 'DANFE', n);
      }
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'DANFE da NF-e ${_str(n, 'numero_nfe')} não disponível para download.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _mostrarDownloadManual(String url, String tipo, Map<String, dynamic> n) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Download $tipo'),
        content: Text(
          'Clique no link abaixo para baixar o $tipo da NF-e ${_str(n, 'numero_nfe')}:\n\n$url',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }

  void _baixarConteudoComoArquivo(String conteudo, String nome, String mime) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Preparando download de $nome...'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _cancelarNfe(Map<String, dynamic> n) async {
    final fiscalDocumentId = _str(n, '__docId');
    if (fiscalDocumentId.isEmpty) return;

    // Verifica prazo legal manualmente (24h após autorização)
    final dataAutorizacao = n['data_autorizacao'] ?? n['data_emissao'];
    if (dataAutorizacao is Timestamp) {
      final diff = DateTime.now().difference(dataAutorizacao.toDate());
      if (diff.inHours >= 24) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Prazo legal para cancelamento expirado (24h após autorização).'),
            backgroundColor: _vermelho,
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
    }

    // Dialog de confirmação com justificativa premium
    if (!mounted) return;
    final resultado = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _CancelamentoDialog(
        numeroNfe: _str(n, 'numero_nfe'),
        clienteNome: _str(n, 'cliente_nome'),
      ),
    );
    if (resultado == null) return;

    try {
      final chaveAcesso = n['chave_acesso'] as String?;
      final protocolo = n['protocolo'] as String?;

      // Executa cancelamento via service
      final cancelResult = await FiscalCancelamentoService.cancelarNota(
        storeId: _storeId,
        fiscalDocumentId: fiscalDocumentId,
        justificativa: resultado['justificativa'] as String,
        accessKey: chaveAcesso,
        protocol: protocolo,
      );

      if (!mounted) return;

      if (cancelResult.sucesso) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('NF-e cancelada com sucesso!'),
            backgroundColor: _verde,
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        final traducao = FiscalErroTranslator.traduzir(
          FiscalErroTranslator.extrairCodigoRejeicao(cancelResult.erro),
          mensagemOriginal: cancelResult.erro,
        );
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${traducao.titulo}: ${traducao.descricao}'),
            backgroundColor: _vermelho,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 6),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      final traducao = FiscalErroTranslator.traduzir(null,
          mensagemOriginal: e.toString());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${traducao.titulo}: ${traducao.descricao}'),
          backgroundColor: _vermelho,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 6),
        ),
      );
    }
  }

  Future<void> _emitirCce(Map<String, dynamic> n) async {
    final fiscalDocumentId = _str(n, '__docId');
    if (fiscalDocumentId.isEmpty) return;

    // Verifica limite de CC-e
    final cceAtual = (n['cartas_correcao'] as List?)?.length ?? 0;
    if (cceAtual >= FiscalCartaCorrecaoService.maxCartasPorNfe) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Limite máximo de ${FiscalCartaCorrecaoService.maxCartasPorNfe} cartas de correção atingido.'),
          backgroundColor: _vermelho,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (!mounted) return;
    final resultado = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _CartaCorrecaoDialog(
        numeroNfe: _str(n, 'numero_nfe'),
        sequencia: cceAtual + 1,
      ),
    );
    if (resultado == null) return;

    try {
      final cceResult = await FiscalCartaCorrecaoService.enviarCartaCorrecao(
        storeId: _storeId,
        fiscalDocumentId: fiscalDocumentId,
        textoCorrecao: resultado['correcao'] as String,
      );

      if (!mounted) return;

      if (cceResult.sucesso) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Carta de Correção (CC-e) emitida com sucesso.'),
            backgroundColor: _verde,
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        final traducao = FiscalErroTranslator.traduzir(
          FiscalErroTranslator.extrairCodigoRejeicao(cceResult.erro),
          mensagemOriginal: cceResult.erro,
        );
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${traducao.titulo}: ${traducao.descricao}'),
            backgroundColor: _vermelho,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 6),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      final traducao = FiscalErroTranslator.traduzir(null,
          mensagemOriginal: e.toString());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${traducao.titulo}: ${traducao.descricao}'),
          backgroundColor: _vermelho,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 6),
        ),
      );
    }
  }

  Future<void> _consultarSefaz(Map<String, dynamic> n) async {
    if (!mounted) return;
    final numero = _str(n, 'numero_nfe', '—');

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Consultando situação da NF-e $numero...'),
        behavior: SnackBarBehavior.floating,
        backgroundColor: _roxo,
      ),
    );

    try {
      // Simula consulta ao provedor
      await Future.delayed(const Duration(seconds: 2));

      // Em produção, chamaria o provider real:
      // final provider = FiscalProviderService.obterProvider(_storeId);
      // final resultado = await provider.consultarStatus(chaveAcesso: ...);

      final statusAtual = _statusInfo(_str(n, 'situacao'));
      final chave = _str(n, 'chave_acesso', 'Não disponível');

      if (!mounted) return;

      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: statusAtual.fundo,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.search_rounded,
                    color: statusAtual.cor, size: 20),
              ),
              const SizedBox(width: 12),
              const Text('Consulta SEFAZ'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _infoLinha('NF-e', numero),
              const SizedBox(height: 4),
              _infoLinha('Status', statusAtual.label),
              const SizedBox(height: 4),
              _infoLinha('Chave de acesso', chave),
              if (n['protocolo'] != null) ...[
                const SizedBox(height: 4),
                _infoLinha('Protocolo', _str(n, 'protocolo')),
              ],
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: statusAtual.fundo,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_rounded,
                        size: 16, color: statusAtual.cor),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Última consulta: ${_fmtDataHora(DateTime.now())}',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 11,
                          color: statusAtual.cor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                'Fechar',
                style: GoogleFonts.plusJakartaSans(color: _roxo),
              ),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      final traducao = FiscalErroTranslator.traduzir(null,
          mensagemOriginal: e.toString());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${traducao.titulo}: ${traducao.descricao}'),
          backgroundColor: _vermelho,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 6),
        ),
      );
    }
  }

  Widget _infoLinha(String label, String valor) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 120,
          child: Text(
            label,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11,
              fontWeight: FontWeight.w600,
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
    );
  }

  // ─── DETALHES DA CONTINGÊNCIA ──────────────────────────

  void _mostrarDetalhesContingencia(Map<String, dynamic> n) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF3E0),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.warning_amber_rounded,
                  color: _laranja, size: 20),
            ),
            const SizedBox(width: 12),
            const Text('Nota em Contingência'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Esta NF-e foi emitida em regime de contingência devido à '
              'indisponibilidade temporária do ambiente autorizador da SEFAZ.',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                color: _textoPrimario,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 16),
            if (_motivoContingencia != null) ...[
              _detalheContingencia('Motivo', _motivoContingencia!),
              const SizedBox(height: 8),
            ],
            _detalheContingencia('Data', _fmtDataHora(DateTime.now())),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFE8F5E9),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle_rounded,
                      size: 16, color: _verde),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Assim que o ambiente for restabelecido, a nota será '
                      'transmitida automaticamente.',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11,
                        color: _verde,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              'Fechar',
              style: GoogleFonts.plusJakartaSans(color: _roxo),
            ),
          ),
        ],
      ),
    );
  }

  Widget _detalheContingencia(String label, String valor) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 80,
          child: Text(
            label,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11,
              fontWeight: FontWeight.w600,
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
    );
  }

  // ─── INUTILIZAR NUMERAÇÃO ──────────────────────────────

  Future<void> _inutilizarNumeracao(Map<String, dynamic> n) async {
    final notaId = _str(n, '__docId');
    if (notaId.isEmpty) return;

    final numero = _str(n, 'numero_nfe');
    final serie = _str(n, 'serie', '1');

    if (!mounted) return;
    final resultado = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _InutilizacaoDialog(
        numeroNfe: numero.isNotEmpty ? numero : 'próximo disponível',
        serie: serie,
        storeId: _storeId,
      ),
    );
    if (resultado == null) return;

    try {
      final inuResult = await FiscalInutilizacaoService.inutilizar(
        storeId: _storeId,
        serie: serie,
        numeroInicial: resultado['numero_inicial'] as int? ?? 0,
        numeroFinal: resultado['numero_final'] as int? ?? 0,
        justificativa: resultado['justificativa'] as String,
      );

      if (!mounted) return;

      if (inuResult.sucesso) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Numeração inutilizada com sucesso.'),
            backgroundColor: _verde,
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        final traducao = FiscalErroTranslator.traduzir(
          FiscalErroTranslator.extrairCodigoRejeicao(inuResult.erro),
          mensagemOriginal: inuResult.erro,
        );
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${traducao.titulo}: ${traducao.descricao}'),
            backgroundColor: _vermelho,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 6),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      final traducao = FiscalErroTranslator.traduzir(null,
          mensagemOriginal: e.toString());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${traducao.titulo}: ${traducao.descricao}'),
          backgroundColor: _vermelho,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 6),
        ),
      );
    }
  }

  void _mostrarHistorico(Map<String, dynamic> n) {
    showDialog(
      context: context,
      builder: (_) => _HistoricoNfeDialog(
        nota: n,
        fmtData: _fmtDataHora,
        moeda: _moeda,
      ),
    );
  }

  /// Deleta o documento fiscal do Firestore (fiscal_documents).
  Future<void> _deletarDocumento(Map<String, dynamic> n) async {
    final docId = _str(n, '__docId');
    final numeroNfe = _str(n, 'numero_nfe');
    if (numeroNfe.isEmpty) {
      _mostrarSnack('Número da NF-e não encontrado no documento.', _vermelho);
      return;
    }

    final numero = _str(n, 'numero');
    final cliente = _str(n, 'cliente_nome').isNotEmpty
        ? _str(n, 'cliente_nome')
        : _str(n, 'razao_social_destinatario');
    final ref = _str(n, 'ref');
    final valor = _str(n, 'valor_total');
    final serie = _str(n, 'serie', '1');

    // Modal premium de confirmação
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (ctx) => _DialogConfirmacaoExclusao(
        numero: numero.isNotEmpty ? numero : numeroNfe,
        cliente: cliente,
        ref: ref,
        valor: valor,
      ),
    );

    if (confirmado != true || !mounted) return;

    try {
      final storeId = _str(n, 'store_id');
      if (storeId.isEmpty) {
        _mostrarSnack('ID da loja não encontrado no documento.', _vermelho);
        return;
      }

      final result = await callFirebaseFunctionSafe(
        'fiscalDeletarDocumento',
        parameters: {
          'store_id': storeId,
          'numero_nfe': numeroNfe,
          'serie': serie,
        },
        timeout: const Duration(seconds: 30),
        region: 'southamerica-east1',
      );

      if (!mounted) return;

      final sucesso = result['sucesso'] == true;
      if (!sucesso) {
        _mostrarSnack(result['erro'] as String? ?? 'Erro ao deletar.', _vermelho);
        return;
      }

      // Atualiza a lista local removendo o item (usa docId se disponível, senão numero_nfe)
      setState(() {
        if (docId.isNotEmpty) {
          _notas.removeWhere((item) => _str(item, '__docId') == docId);
          _notasFiltradas.removeWhere((item) => _str(item, '__docId') == docId);
        } else {
          _notas.removeWhere((item) => _str(item, 'numero_nfe') == numeroNfe);
          _notasFiltradas.removeWhere((item) => _str(item, 'numero_nfe') == numeroNfe);
        }
      });

      // Modal premium de sucesso
      if (!mounted) return;
      _mostrarDialogoExclusaoSucesso(numero.isNotEmpty ? numero : numeroNfe);
    } catch (e) {
      if (!mounted) return;
      _mostrarSnack('Erro ao deletar documento: $e', _vermelho);
    }
  }

  void _mostrarDialogoExclusaoSucesso(String numero) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _verdeFundo,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_circle_rounded,
                    size: 48, color: _verde),
              ),
              const SizedBox(height: 16),
              const Text(
                'Documento Deletado',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: _textoPrimario,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Nº $numero removido permanentemente.',
                style: const TextStyle(fontSize: 13, color: _textoSecundario),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        actions: [
          Center(
            child: FilledButton(
              onPressed: () => Navigator.of(ctx).pop(),
              style: FilledButton.styleFrom(
                backgroundColor: _roxo,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Concluir',
                  style: TextStyle(fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }

  void _mostrarSnack(String msg, Color cor) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: cor,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _exportarExcel() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Exportando Excel...'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _exportarPdf() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Exportando PDF...'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _imprimir() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Preparando impressão...'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

// =============================================================================
// HELPERS
// =============================================================================

class _StatusInfo {
  final String label;
  final Color cor;
  final Color fundo;
  const _StatusInfo(this.label, this.cor, this.fundo);
}

class _AcaoMenuItem extends StatelessWidget {
  final IconData icone;
  final String texto;
  final Color cor;
  const _AcaoMenuItem(this.icone, this.texto, this.cor);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icone, size: 18, color: cor),
        const SizedBox(width: 8),
        Text(
          texto,
          style: GoogleFonts.plusJakartaSans(
              fontSize: 12, color: cor, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }
}

// =============================================================================
// MODAL PREMIUM — CONFIRMAÇÃO DE EXCLUSÃO NF-e
// =============================================================================

class _DialogConfirmacaoExclusao extends StatefulWidget {
  final String numero;
  final String cliente;
  final String ref;
  final String valor;
  const _DialogConfirmacaoExclusao({
    required this.numero,
    required this.cliente,
    this.ref = '',
    this.valor = '',
  });

  @override
  State<_DialogConfirmacaoExclusao> createState() => _DialogConfirmacaoExclusaoState();
}

class _DialogConfirmacaoExclusaoState extends State<_DialogConfirmacaoExclusao>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.92, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Container(
        width: 420,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Header gradiente ──
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFFDC2626), Color(0xFFB91C1C)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Column(
                children: [
                  ScaleTransition(
                    scale: _pulseAnim,
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.delete_forever_rounded,
                        size: 36,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Deletar NF-e',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Nº ${widget.numero}',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.white.withValues(alpha: 0.85),
                    ),
                  ),
                ],
              ),
            ),

            // ── Corpo ──
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Tem certeza que deseja deletar permanentemente este documento?',
                    style: const TextStyle(
                      fontSize: 13,
                      color: _textoPrimario,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 14),

                  // ── Card do documento ──
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: Colors.red.withValues(alpha: 0.12)),
                    ),
                    child: Column(
                      children: [
                        _linhaInfo('Nº NF-e', widget.numero),
                        const SizedBox(height: 4),
                        _linhaInfo('Cliente', widget.cliente),
                        if (widget.ref.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          _linhaInfo('Ref', widget.ref),
                        ],
                        if (widget.valor.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          _linhaInfo('Valor', widget.valor),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // ── Aviso ──
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.warning_amber_rounded,
                          size: 14, color: Colors.orange[700]),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Esta ação é irreversível. '
                          'O documento e todos os seus dados associados '
                          'serão removidos permanentemente do sistema.',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.orange[700],
                            height: 1.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                ],
              ),
            ),

            // ── Ações ──
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 14, 24, 20),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        side: BorderSide(color: Colors.grey[300]!),
                        foregroundColor: _textoSecundario,
                      ),
                      child: const Text('Cancelar',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed: () => Navigator.of(context).pop(true),
                      icon: const Icon(Icons.delete_forever, size: 16),
                      label: const Text('Sim, Deletar'),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFDC2626),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        textStyle: const TextStyle(
                            fontWeight: FontWeight.w600),
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

  Widget _linhaInfo(String label, String valor) {
    return Row(
      children: [
        SizedBox(
          width: 60,
          child: Text(label,
              style: TextStyle(fontSize: 11, color: Colors.grey[600])),
        ),
        Expanded(
          child: Text(valor.isNotEmpty ? valor : '—',
              style: const TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }
}

// =============================================================================
// MODAL — WIZARD DE CRIAÇÃO DE NF-e (3 ETAPAS)
// =============================================================================

class _CriarNotaFiscalWizard extends StatefulWidget {
  final String storeId;
  final ComercialCliente cliente;

  const _CriarNotaFiscalWizard({
    required this.storeId,
    required this.cliente,
  });

  @override
  State<_CriarNotaFiscalWizard> createState() => _CriarNotaFiscalWizardState();
}

class _CriarNotaFiscalWizardState extends State<_CriarNotaFiscalWizard>
    with TickerProviderStateMixin {
  int _step = 0;
  bool _criando = false;

  late AnimationController _animCtrl;
  late Animation<double> _fadeAnim;

  late final NumberFormat _moeda;

  // Step 1 — Dados do Cliente
  late final TextEditingController _nomeCtrl;
  late final TextEditingController _cpfCnpjCtrl;
  late final TextEditingController _ieCtrl;
  late final TextEditingController _enderecoCtrl;
  late final TextEditingController _numeroCtrl;
  late final TextEditingController _bairroCtrl;
  late final TextEditingController _cidadeCtrl;
  late final TextEditingController _estadoCtrl;
  late final TextEditingController _cepCtrl;
  late final TextEditingController _codigoIbgeCtrl;
  late final TextEditingController _telefoneCtrl;
  late final TextEditingController _emailCtrl;
  late final TextEditingController _municipioEmissorCtrl;
  late final TextEditingController _naturezaCtrl;
  late final TextEditingController _cfopCtrl;
  late final TextEditingController _formaPagamentoCtrl;
  String _consumidorFinal = 'Sim';
  String _indicadorIe = 'Contribuinte';

  // Step 2 — Produtos
  final List<_ProdutoLinha> _produtos = [];
  List<_ProdutoSearchItem> _produtosLoja = [];
  bool _carregandoProdutos = true;
  double _subtotal = 0;

  // Step 3 — Totais
  late final TextEditingController _descontoGeralCtrl;
  late final TextEditingController _freteCtrl;
  late final TextEditingController _seguroCtrl;
  late final TextEditingController _outrasDespesasCtrl;
  late final TextEditingController _observacoesCtrl;
  late final TextEditingController _transportadoraCtrl;
  late final TextEditingController _pesoCtrl;
  late final TextEditingController _volumesCtrl;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeInOut);
    _animCtrl.forward();
    _moeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

    final c = widget.cliente;
    _nomeCtrl = TextEditingController(text: c.nome);
    _cpfCnpjCtrl = TextEditingController(text: c.cpf ?? '');
    _ieCtrl = TextEditingController();
    _enderecoCtrl = TextEditingController(text: c.rua ?? '');
    _numeroCtrl = TextEditingController(text: c.numero ?? '');
    _bairroCtrl = TextEditingController(text: c.bairro ?? '');
    _cidadeCtrl = TextEditingController(text: c.cidade ?? '');
    _estadoCtrl = TextEditingController(text: c.estado ?? '');
    _cepCtrl = TextEditingController(text: c.cep ?? '');
    // Tenta carregar codigo_ibge do cliente ou resolve pela cidade/UF da loja
    final ibgeInicial = c.codigoIbge ?? '';
    _codigoIbgeCtrl = TextEditingController(text: ibgeInicial);
    _telefoneCtrl = TextEditingController(text: c.telefone ?? '');
    _emailCtrl = TextEditingController(text: c.email ?? '');
    _municipioEmissorCtrl = TextEditingController(text: c.cidade ?? '');
    _naturezaCtrl = TextEditingController(text: 'Venda de mercadoria');
    _cfopCtrl = TextEditingController(text: '5102');
    _formaPagamentoCtrl = TextEditingController(text: 'À vista');

    _descontoGeralCtrl = TextEditingController();
    _freteCtrl = TextEditingController();
    _seguroCtrl = TextEditingController();
    _outrasDespesasCtrl = TextEditingController();
    _observacoesCtrl = TextEditingController();
    _transportadoraCtrl = TextEditingController();
    _pesoCtrl = TextEditingController();
    _volumesCtrl = TextEditingController();

    _carregarProdutos();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    _nomeCtrl.dispose();
    _cpfCnpjCtrl.dispose();
    _ieCtrl.dispose();
    _enderecoCtrl.dispose();
    _numeroCtrl.dispose();
    _bairroCtrl.dispose();
    _cidadeCtrl.dispose();
    _estadoCtrl.dispose();
    _cepCtrl.dispose();
    _codigoIbgeCtrl.dispose();
    _telefoneCtrl.dispose();
    _emailCtrl.dispose();
    _municipioEmissorCtrl.dispose();
    _naturezaCtrl.dispose();
    _cfopCtrl.dispose();
    _formaPagamentoCtrl.dispose();
    _descontoGeralCtrl.dispose();
    _freteCtrl.dispose();
    _seguroCtrl.dispose();
    _outrasDespesasCtrl.dispose();
    _observacoesCtrl.dispose();
    _transportadoraCtrl.dispose();
    _pesoCtrl.dispose();
    _volumesCtrl.dispose();
    for (final p in _produtos) {
      p.dispose();
    }
    super.dispose();
  }

  Future<void> _carregarProdutos() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('produtos')
          .where('loja_id', isEqualTo: widget.storeId)
          .where('ativo', isEqualTo: true)
          .get();
      if (mounted) {
        setState(() {
          _produtosLoja = snap.docs
              .map((d) => _ProdutoSearchItem.fromDoc(d.id, d.data()))
              .toList();
          _carregandoProdutos = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _carregandoProdutos = false);
    }
  }

  void _avancar() {
    _animCtrl.reverse().then((_) {
      if (mounted) {
        setState(() => _step++);
        _animCtrl.forward();
      }
    });
  }

  void _voltar() {
    _animCtrl.reverse().then((_) {
      if (mounted) {
        setState(() => _step--);
        _animCtrl.forward();
      }
    });
  }

  void _calcularSubtotal() {
    double total = 0;
    for (final p in _produtos) {
      total += p.total;
    }
    setState(() => _subtotal = total);
  }

  double get _totalProdutos {
    double total = 0;
    for (final p in _produtos) {
      total += p.quantidade * p.valorUnitario;
    }
    return total;
  }

  double get _descontoValor =>
      double.tryParse(_descontoGeralCtrl.text.replaceAll(',', '.')) ?? 0;
  double get _freteValor =>
      double.tryParse(_freteCtrl.text.replaceAll(',', '.')) ?? 0;
  double get _seguroValor =>
      double.tryParse(_seguroCtrl.text.replaceAll(',', '.')) ?? 0;
  double get _outrasValor =>
      double.tryParse(_outrasDespesasCtrl.text.replaceAll(',', '.')) ?? 0;
  double get _valorTotalNota =>
      _subtotal - _descontoValor + _freteValor + _seguroValor + _outrasValor;

  Future<void> _abrirModalBuscaCidadeIbge() async {
    if (!mounted) return;
    final resultado = await showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (_) => const _CidadesIbgeSearchModal(),
    );
    if (resultado != null && resultado.isNotEmpty && mounted) {
      setState(() {
        _codigoIbgeCtrl.text = resultado;
      });
    }
  }

  Future<void> _criarNota() async {
    setState(() => _criando = true);

    final cliente = widget.cliente;
    final now = DateTime.now();
    final produtosMap = _produtos
        .map((p) => {
              'nome': p.nome,
              'codigo': p.codigo,
              'ncm': p.ncm,
              'cest': p.cest,
              'sku': p.sku,
              'cst_icms': p.cstCtrl.text.trim().isNotEmpty
                  ? p.cstCtrl.text.trim()
                  : '400',
              'quantidade': p.quantidade,
              'valor_unitario': p.valorUnitario,
              'desconto': p.desconto,
              'total': p.total,
            })
        .toList();

    await FirebaseFirestore.instance
        .collection('users')
        .doc(widget.storeId)
        .collection('notas_fiscais')
        .add({
      'cliente_id': cliente.id,
      'cliente_nome': cliente.nome,
      'cliente_cpf_cnpj': cliente.cpf ?? '',
      'cliente_rg': cliente.rg ?? '',
      'cliente_email': cliente.email ?? '',
      'cliente_telefone': cliente.telefone ?? '',
      'cliente_cep': cliente.cep ?? '',
      'cliente_rua': cliente.rua ?? '',
      'cliente_numero': cliente.numero ?? '',
      'cliente_bairro': cliente.bairro ?? '',
      'cliente_cidade': cliente.cidade ?? '',
      'cliente_estado': cliente.estado ?? '',
      'cliente_ie': _ieCtrl.text.trim(),
      'cliente_codigo_ibge': _codigoIbgeCtrl.text.trim(),
      'municipio_emissor': _municipioEmissorCtrl.text.trim(),
      'natureza_operacao': _naturezaCtrl.text.trim(),
      'consumidor_final': _consumidorFinal,
      'indicador_ie': _indicadorIe,
      'cfop': _cfopCtrl.text.trim(),
      'forma_pagamento': _formaPagamentoCtrl.text.trim(),
      'produtos': produtosMap,
      'subtotal': _subtotal,
      'desconto_geral': _descontoValor,
      'frete': _freteValor,
      'seguro': _seguroValor,
      'outras_despesas': _outrasValor,
      'total_produtos': _totalProdutos,
      'valor_total': _valorTotalNota,
      'base_icms': _subtotal - _descontoValor,
      'base_ipi': 0,
      'base_pis': 0,
      'base_cofins': 0,
      'observacoes': _observacoesCtrl.text.trim(),
      'transportadora': _transportadoraCtrl.text.trim(),
      'peso': double.tryParse(_pesoCtrl.text.replaceAll(',', '.')) ?? 0,
      'volumes': int.tryParse(_volumesCtrl.text) ?? 0,
      'situacao': 'aguardando_emissao',
      'data_criacao': Timestamp.fromDate(now),
      'data_emissao': null,
      'numero_nfe': '',
      'chave_acesso': '',
      'serie': '',
      'usuario_responsavel': FirebaseAuth.instance.currentUser?.uid ?? '',
      'cce_emitida': false,
      'logs': [
        {
          'evento': 'criada',
          'data': Timestamp.fromDate(now),
          'usuario': FirebaseAuth.instance.currentUser?.uid ?? '',
          'descricao': 'Nota fiscal criada',
        }
      ],
    });

    // Salva o código IBGE no documento do cliente para reutilização
    final ibge = _codigoIbgeCtrl.text.trim();
    if (ibge.isNotEmpty && cliente.id.isNotEmpty) {
      try {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(widget.storeId)
            .collection('clientes_comercial')
            .doc(cliente.id)
            .update({'codigo_ibge': ibge});
      } catch (_) {
        // Falha silenciosa — o dado principal (nota) já foi salvo
      }
    }

    if (mounted) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 80, vertical: 30),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: 820,
        constraints: const BoxConstraints(maxHeight: 800),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          children: [
            // Header
            _buildHeader(),
            // Stepper indicador
            _buildStepperIndicator(),
            // Conteúdo
            Expanded(
              child: FadeTransition(
                opacity: _fadeAnim,
                child: _step == 0
                    ? _buildStep1()
                    : _step == 1
                        ? _buildStep2()
                        : _buildStep3(),
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
      padding: const EdgeInsets.fromLTRB(28, 20, 20, 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _borda)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [_roxo, _roxoClaro]),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.receipt_long_rounded,
                color: Colors.white, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Criar Nota Fiscal',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: _textoPrimario,
                  ),
                ),
                Text(
                  'Preencha os dados para emissão da NF-e',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 11, color: _textoSecundario),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon:
                const Icon(Icons.close_rounded, color: _textoSecundario),
          ),
        ],
      ),
    );
  }

  Widget _buildStepperIndicator() {
    final labels = ['Dados do Cliente', 'Produtos', 'Totais'];
    return Container(
      padding: const EdgeInsets.fromLTRB(28, 16, 28, 12),
      child: Row(
        children: List.generate(labels.length, (i) {
          final ativo = i == _step;
          final completo = i < _step;
          return Expanded(
            child: Row(
              children: [
                if (i > 0)
                  Expanded(
                    child: Container(
                      height: 2,
                      color: completo || ativo ? _roxo : _borda,
                    ),
                  ),
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: completo
                        ? _verde
                        : ativo
                            ? _roxo
                            : _cinzaClaro,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: completo || ativo ? Colors.transparent : _borda,
                    ),
                  ),
                  child: Center(
                    child: completo
                        ? const Icon(Icons.check_rounded,
                            size: 16, color: Colors.white)
                        : Text(
                            '${i + 1}',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: ativo ? Colors.white : _textoSecundario,
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  labels[i],
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 10,
                    fontWeight: ativo ? FontWeight.w700 : FontWeight.w500,
                    color: ativo ? _roxo : _textoSecundario,
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }

  // ─── STEP 1: DADOS DO CLIENTE ────────────────────────────

  Widget _buildStep1() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _secaoLabel('Dados do Cliente'),
          const SizedBox(height: 12),
          _campoLinha([
            _campoFlex('Nome', _nomeCtrl, flex: 3),
            _campoFlex('CPF/CNPJ', _cpfCnpjCtrl, flex: 2),
            _campoFlex('Inscrição Estadual', _ieCtrl, flex: 2),
          ]),
          const SizedBox(height: 10),
          _campoLinha([
            _campoFlex('Endereço', _enderecoCtrl, flex: 3),
            _campoFlex('Número', _numeroCtrl, flex: 1),
            _campoFlex('Bairro', _bairroCtrl, flex: 2),
          ]),
          const SizedBox(height: 10),
          _campoLinha([
            _campoFlex('Cidade', _cidadeCtrl, flex: 3),
            _campoFlex('Estado', _estadoCtrl, flex: 1),
            _campoFlex('CEP', _cepCtrl, flex: 2),
            _campoFlex('Cód. IBGE', _codigoIbgeCtrl, flex: 2),
            // Botão lupa para buscar código IBGE
            GestureDetector(
              onTap: () => _abrirModalBuscaCidadeIbge(),
              child: Container(
                width: 38,
                height: 38,
                margin: const EdgeInsets.only(top: 20),
                decoration: BoxDecoration(
                  color: _roxo.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.search_rounded,
                    color: _roxo, size: 20),
              ),
            ),
          ]),
          const SizedBox(height: 10),
          _campoLinha([
            _campoFlex('Telefone', _telefoneCtrl, flex: 2),
            _campoFlex('E-mail', _emailCtrl, flex: 3),
          ]),
          const SizedBox(height: 16),
          _secaoLabel('Configuração da NF-e'),
          const SizedBox(height: 12),
          _campoLinha([
            _campoFlex('Município emissor', _municipioEmissorCtrl, flex: 3),
            _campoDropdown(
              'Consumidor Final',
              ['Sim', 'Não'],
              _consumidorFinal,
              (v) => setState(() => _consumidorFinal = v),
              flex: 2,
            ),
          ]),
          const SizedBox(height: 10),
          _campoLinha([
            _campoDropdown(
              'Indicador IE',
              ['Contribuinte', 'Não contribuinte', 'Isento'],
              _indicadorIe,
              (v) => setState(() => _indicadorIe = v),
              flex: 2,
            ),
            _campoFlex('CFOP sugerido', _cfopCtrl, flex: 2),
            _campoFlex('Forma de pagamento', _formaPagamentoCtrl, flex: 2),
          ]),
          const SizedBox(height: 10),
          _campoLinha([
            _campoFlex('Natureza da operação', _naturezaCtrl, flex: 4),
          ]),
        ],
      ),
    );
  }

  // ─── STEP 2: PRODUTOS (Cards Premium) ─────────────────────

  Widget _buildStep2() {
    return Column(
      children: [
        // Busca de produto
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
          child: _buildBuscaProduto(),
        ),
        // Lista de cards de produtos
        Expanded(
          child: _produtos.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 80, height: 80,
                        decoration: BoxDecoration(
                          color: _lilas,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Icon(Icons.inventory_2_outlined,
                            size: 36, color: _roxo.withValues(alpha: 0.5)),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Nenhum produto adicionado',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: _textoPrimario,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Busque e adicione produtos à nota fiscal',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          color: _textoSecundario,
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 100),
                  itemCount: _produtos.length,
                  itemBuilder: (context, i) => _buildProdutoCard(i),
                ),
        ),
        // Card de resumo fixo no final
        if (_produtos.isNotEmpty) _buildResumoCard(),
      ],
    );
  }

  Widget _buildProdutoCard(int index) {
    final p = _produtos[index];
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _borda),
          boxShadow: [
            BoxShadow(
              color: _roxo.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Linha superior: ícone + info + total + remover
              Row(
                children: [
                  Container(
                    width: 42, height: 42,
                    decoration: BoxDecoration(
                      color: _lilas,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.inventory_2_rounded,
                        size: 20, color: _roxo),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          p.nome,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: _textoPrimario,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            _miniTag('Cód: ${p.codigo}'),
                            if (p.sku.isNotEmpty) ...[
                              const SizedBox(width: 8),
                              _miniTag('SKU: ${p.sku}'),
                            ],
                            if (p.ncm.isNotEmpty) ...[
                              const SizedBox(width: 8),
                              _miniTag('NCM: ${p.ncm}'),
                            ],
                            const SizedBox(width: 8),
                            _miniTag('CST: ${p.cstIcms}'),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Text(
                      'R\$ ${p.total.toStringAsFixed(2)}',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: _roxo,
                      ),
                    ),
                  ),
                  InkWell(
                    onTap: () {
                      setState(() {
                        _produtos.removeAt(index);
                        _calcularSubtotal();
                      });
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: _vermelhoFundo,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.delete_rounded,
                          size: 16, color: _vermelho),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Linha inferior: controles de quantidade, valor, desconto
              Row(
                children: [
                  // Quantidade
                  _buildQtdControl(p),
                  const SizedBox(width: 16),
                  // Valor unitário
                  _buildFieldControl(
                    label: 'Valor Unit.',
                    controller: p.valorCtrl,
                    width: 100,
                    onChanged: () {
                      p.recalcular();
                      _calcularSubtotal();
                    },
                  ),
                  const SizedBox(width: 12),
                  // Desconto
                  _buildFieldControl(
                    label: 'Desconto (R\$)',
                    controller: p.descCtrl,
                    width: 80,
                    onChanged: () {
                      p.recalcular();
                      _calcularSubtotal();
                    },
                  ),
                  const SizedBox(width: 6),
                  // CST ICMS / CSOSN
                  _buildFieldControl(
                    label: 'CST',
                    controller: p.cstCtrl,
                    width: 70,
                    onChanged: () {},
                  ),
                  const Spacer(),
                  // Subtotal do item
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'Subtotal',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 9,
                          color: _textoSecundario,
                        ),
                      ),
                      Text(
                        'R\$ ${p.total.toStringAsFixed(2)}',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: _textoPrimario,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _miniTag(String texto) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: _cinzaClaro,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        texto,
        style: GoogleFonts.plusJakartaSans(
          fontSize: 9,
          color: _textoSecundario,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildQtdControl(_ProdutoLinha p) {
    return Container(
      height: 36,
      decoration: BoxDecoration(
        color: _cinzaClaro,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _borda),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: () {
              final q = p.quantidade;
              if (q > 1) {
                p.qtdCtrl.text = (q - 1).toStringAsFixed(0);
                p.recalcular();
                _calcularSubtotal();
              }
            },
            borderRadius: BorderRadius.circular(6),
            child: Container(
              width: 32, height: 36,
              alignment: Alignment.center,
              child: Icon(Icons.remove_rounded, size: 16, color: p.quantidade > 1 ? _roxo : _textoSecundario),
            ),
          ),
          SizedBox(
            width: 40,
            child: TextField(
              controller: p.qtdCtrl,
              textAlign: TextAlign.center,
              keyboardType: TextInputType.number,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 12, fontWeight: FontWeight.w700, color: _textoPrimario),
              decoration: const InputDecoration(
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
              onChanged: (_) {
                p.recalcular();
                _calcularSubtotal();
              },
            ),
          ),
          InkWell(
            onTap: () {
              p.qtdCtrl.text = (p.quantidade + 1).toStringAsFixed(0);
              p.recalcular();
              _calcularSubtotal();
            },
            borderRadius: BorderRadius.circular(6),
            child: Container(
              width: 32, height: 36,
              alignment: Alignment.center,
              child: const Icon(Icons.add_rounded, size: 16, color: _roxo),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFieldControl({
    required String label,
    required TextEditingController controller,
    required double width,
    required VoidCallback onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 9,
            color: _textoSecundario,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 4),
        SizedBox(
          width: width,
          height: 36,
          child: TextField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: GoogleFonts.plusJakartaSans(
                fontSize: 12, fontWeight: FontWeight.w600, color: _textoPrimario),
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              filled: true,
              fillColor: _cinzaClaro,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: _borda),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: _borda),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: _roxo, width: 1.5),
              ),
            ),
            onChanged: (_) => onChanged(),
          ),
        ),
      ],
    );
  }

  Widget _buildResumoCard() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 10, 24, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: _borda, width: 2)),
        boxShadow: [
          BoxShadow(
            color: _roxo.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Resumo da Nota',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: _textoPrimario,
                  ),
                ),
                const SizedBox(height: 6),
                _resumoLinha('Subtotal', _moeda.format(_subtotal)),
                _resumoLinha('Desconto', _moeda.format(_descontoValor)),
                _resumoLinha('Impostos (ICMS/PIS/COFINS)', _moeda.format(_subtotal * 0.12)),
                const Divider(height: 12),
                _resumoLinha(
                  'Total',
                  _moeda.format(_subtotal - _descontoValor),
                  destaque: true,
                ),
              ],
            ),
          ),
          const SizedBox(width: 24),
          Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              onTap: _produtos.isEmpty ? null : _avancar,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: _produtos.isEmpty
                        ? [_textoSecundario.withValues(alpha: 0.3), _textoSecundario.withValues(alpha: 0.3)]
                        : [_roxo, _roxoClaro],
                  ),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: _produtos.isEmpty
                      ? []
                      : [BoxShadow(color: _roxo.withValues(alpha: 0.3), blurRadius: 12, offset: const Offset(0, 4))],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Avançar',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 18),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _resumoLinha(String label, String valor, {bool destaque = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label: ',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11,
              color: _textoSecundario,
            ),
          ),
          Text(
            valor,
            style: GoogleFonts.plusJakartaSans(
              fontSize: destaque ? 14 : 11,
              fontWeight: destaque ? FontWeight.w800 : FontWeight.w600,
              color: destaque ? _roxo : _textoPrimario,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBuscaProduto() {
    if (_carregandoProdutos) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: LinearProgressIndicator(),
      );
    }

    return Autocomplete<_ProdutoSearchItem>(
      optionsBuilder: (textEditingValue) {
        final termo = textEditingValue.text.trim().toLowerCase();
        if (termo.isEmpty || _produtosLoja.isEmpty) {
          return const Iterable.empty();
        }
        final termoNums = termo.replaceAll(RegExp(r'\D'), '');
        return _produtosLoja.where((p) {
          if (p.nome.toLowerCase().contains(termo)) {
            return true;
          }
          if (p.codigo.toLowerCase().contains(termo)) {
            return true;
          }
          if (p.codigoBarras.isNotEmpty &&
              p.codigoBarras.contains(termoNums)) {
            return true;
          }
          if (p.sku.isNotEmpty && p.sku.toLowerCase().contains(termo)) {
            return true;
          }
          return false;
        }).take(15);
      },
      displayStringForOption: (p) => p.nome,
      fieldViewBuilder: (context, ctrl, focusNode, onSubmitted) {
        return TextField(
          controller: ctrl,
          focusNode: focusNode,
          decoration: InputDecoration(
            hintText: 'Buscar produto por nome, código, barras, SKU...',
            hintStyle: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                color: _textoSecundario.withValues(alpha: 0.5)),
            prefixIcon: const Icon(Icons.search_rounded,
                size: 20, color: _textoSecundario),
            filled: true,
            fillColor: _cinzaClaro,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: _borda),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: _borda),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: _roxo, width: 1.5),
            ),
          ),
          style: GoogleFonts.plusJakartaSans(
              fontSize: 13, color: _textoPrimario),
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              constraints: const BoxConstraints(maxHeight: 320, maxWidth: 560),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _borda),
              ),
              child: ListView.separated(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: options.length,
                separatorBuilder: (_, _) =>
                    const Divider(height: 1, indent: 16, endIndent: 16),
                itemBuilder: (context, i) {
                  final p = options.elementAt(i);
                  return InkWell(
                    onTap: () => onSelected(p),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      child: Row(
                        children: [
                          Container(
                            width: 44, height: 44,
                            decoration: BoxDecoration(
                              color: _lilas,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(Icons.inventory_2_rounded,
                                size: 22, color: _roxo),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  p.nome,
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: _textoPrimario,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Row(
                                  children: [
                                    if (p.codigo.isNotEmpty)
                                      _miniTag('Cód: ${p.codigo}'),
                                    if (p.sku.isNotEmpty) ...[
                                      const SizedBox(width: 6),
                                      _miniTag('SKU: ${p.sku}'),
                                    ],
                                    if (p.ncm.isNotEmpty) ...[
                                      const SizedBox(width: 6),
                                      _miniTag('NCM: ${p.ncm}'),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                'R\$ ${p.preco.toStringAsFixed(2)}',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                  color: _roxo,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(width: 12),
                          Container(
                            width: 32, height: 32,
                            decoration: BoxDecoration(
                              color: _roxo.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.add_rounded,
                                size: 18, color: _roxo),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
      onSelected: (produto) {
        setState(() {
          _produtos.add(_ProdutoLinha(
            nome: produto.nome,
            codigo: produto.codigo,
            sku: produto.sku,
            ncm: produto.ncm,
            cest: produto.cest,
            cstIcms: produto.cstIcms.isNotEmpty ? produto.cstIcms : '400',
            valorUnitario: produto.preco,
          ));
          _calcularSubtotal();
        });
      },
    );
  }

  // ─── STEP 3: TOTAIS ───────────────────────────────────────

  Widget _buildStep3() {
    final totalProd = _totalProdutos;
    final baseIcms = _subtotal - _descontoValor;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _secaoLabel('Totais da Nota'),
          const SizedBox(height: 12),
          // Cards de valores
          _cardValor('Subtotal', _subtotal),
          const SizedBox(height: 8),
          _campoLinha([
            _campoNumero('Desconto Geral', _descontoGeralCtrl, flex: 2),
            _campoNumero('Frete', _freteCtrl, flex: 2),
            _campoNumero('Seguro', _seguroCtrl, flex: 2),
            _campoNumero('Outras despesas', _outrasDespesasCtrl, flex: 2),
          ]),
          const SizedBox(height: 12),
          _cardValor('Total dos Produtos', totalProd),
          const SizedBox(height: 12),
          _secaoLabel('Bases de Cálculo'),
          const SizedBox(height: 8),
          _campoLinha([
            _cardInfo('Base ICMS', baseIcms),
            _cardInfo('Base IPI', 0),
          ]),
          const SizedBox(height: 8),
          _campoLinha([
            _cardInfo('Base PIS', baseIcms * 0.0165),
            _cardInfo('Base COFINS', baseIcms * 0.076),
          ]),
          const SizedBox(height: 16),
          _cardValor('Valor Total da Nota', _valorTotalNota,
              cor: _roxo, grande: true),
          const SizedBox(height: 16),
          _secaoLabel('Informações Adicionais'),
          const SizedBox(height: 8),
          TextField(
            controller: _observacoesCtrl,
            maxLines: 3,
            decoration: _inDec(titulo: 'Observações'),
            style:
                GoogleFonts.plusJakartaSans(fontSize: 13, color: _textoPrimario),
          ),
          const SizedBox(height: 10),
          _campoLinha([
            _campoFlex('Transportadora', _transportadoraCtrl, flex: 2),
            _campoNumero('Peso (kg)', _pesoCtrl, flex: 1),
            _campoNumeroInt('Volumes', _volumesCtrl, flex: 1),
          ]),
        ],
      ),
    );
  }

  Widget _cardValor(String label, double valor,
      {Color cor = _textoPrimario, bool grande = false}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cor.withValues(alpha: 0.15)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: GoogleFonts.plusJakartaSans(
              fontSize: grande ? 14 : 12,
              fontWeight: FontWeight.w600,
              color: _textoPrimario,
            ),
          ),
          Text(
            'R\$ ${valor.toStringAsFixed(2)}',
            style: GoogleFonts.plusJakartaSans(
              fontSize: grande ? 20 : 14,
              fontWeight: FontWeight.w800,
              color: cor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _cardInfo(String label, double valor) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _cinzaClaro,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 10, color: _textoSecundario),
            ),
            const SizedBox(height: 4),
            Text(
              'R\$ ${valor.toStringAsFixed(2)}',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: _textoPrimario,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── FOOTER ───────────────────────────────────────────────

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 14, 24, 18),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: _borda)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          if (_step > 0)
            TextButton(
              onPressed: _criando ? null : _voltar,
              child: Text(
                'Voltar',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  color: _textoSecundario,
                ),
              ),
            )
          else
            const SizedBox.shrink(),
          Row(
            children: [
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
              const SizedBox(width: 12),
              Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(10),
                child: InkWell(
                  onTap: _criando
                      ? null
                      : () {
                          if (_step < 2) {
                            _avancar();
                          } else {
                            _criarNota();
                          }
                        },
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 11),
                    decoration: BoxDecoration(
                      gradient: _criando
                          ? null
                          : const LinearGradient(
                              colors: [_roxo, _roxoClaro]),
                      color: _criando ? _borda : null,
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: _criando
                          ? null
                          : [
                              BoxShadow(
                                color: _roxo.withValues(alpha: 0.25),
                                blurRadius: 8,
                                offset: const Offset(0, 3),
                              ),
                            ],
                    ),
                    child: _criando
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: _roxo,
                            ),
                          )
                        : Text(
                            _step < 2 ? 'Avançar' : 'Criar Nota',
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
        ],
      ),
    );
  }

  // ─── HELPERS DE UI ────────────────────────────────────────

  Widget _secaoLabel(String texto) {
    return Text(
      texto,
      style: GoogleFonts.plusJakartaSans(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: _roxo,
      ),
    );
  }

  Widget _campoLinha(List<Widget> filhos) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: filhos
          .expand((w) => [w, const SizedBox(width: 10)])
          .toList()
        ..removeLast(),
    );
  }

  Widget _campoFlex(
      String label, TextEditingController ctrl, {int flex = 1}) {
    return Expanded(
      flex: flex,
      child: Column(
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
            style: GoogleFonts.plusJakartaSans(
                fontSize: 13, color: _textoPrimario),
            decoration: _inDec(),
          ),
        ],
      ),
    );
  }

  Widget _campoDropdown(
    String label,
    List<String> opcoes,
    String valor,
    ValueChanged<String> onChange, {
    int flex = 1,
  }) {
    return Expanded(
      flex: flex,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: _textoSecundario)),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: _cinzaClaro,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _borda),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                isExpanded: true,
                value: valor,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 13, color: _textoPrimario),
                items: opcoes
                    .map((o) => DropdownMenuItem(
                        value: o,
                        child: Text(o,
                            style: GoogleFonts.plusJakartaSans(
                                fontSize: 13))))
                    .toList(),
                onChanged: (v) {
                  if (v != null) onChange(v);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _campoNumero(
      String label, TextEditingController ctrl, {int flex = 1}) {
    return Expanded(
      flex: flex,
      child: Column(
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
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            style: GoogleFonts.plusJakartaSans(
                fontSize: 13, color: _textoPrimario),
            decoration: _inDec(),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
    );
  }

  Widget _campoNumeroInt(
      String label, TextEditingController ctrl, {int flex = 1}) {
    return Expanded(
      flex: flex,
      child: Column(
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
            style: GoogleFonts.plusJakartaSans(
                fontSize: 13, color: _textoPrimario),
            decoration: _inDec(),
          ),
        ],
      ),
    );
  }

  InputDecoration _inDec({String? titulo}) {
    return InputDecoration(
      hintText: titulo,
      hintStyle: GoogleFonts.plusJakartaSans(
          fontSize: 12,
          color: _textoSecundario.withValues(alpha: 0.5)),
      filled: true,
      fillColor: _cinzaClaro,
      contentPadding: const EdgeInsets.all(10),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: _borda),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: _borda),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: _roxo, width: 1.5),
      ),
    );
  }
}

// =============================================================================
// MODELO — ProdutoLinha (para o Wizard)
// =============================================================================

class _ProdutoLinha {
  final String nome;
  final String codigo;
  final String ncm;
  final String cest;
  final String sku;
  final String cstIcms;
  double valorUnitario;
  double quantidade = 1;
  double desconto = 0;
  late final TextEditingController qtdCtrl;
  late final TextEditingController valorCtrl;
  late final TextEditingController descCtrl;
  late final TextEditingController cstCtrl;

  _ProdutoLinha({
    required this.nome,
    required this.codigo,
    this.ncm = '',
    this.cest = '',
    this.sku = '',
    this.cstIcms = '400',
    this.valorUnitario = 0,
  }) {
    qtdCtrl = TextEditingController(text: '1');
    valorCtrl = TextEditingController(text: valorUnitario.toStringAsFixed(2));
    descCtrl = TextEditingController();
    cstCtrl = TextEditingController(text: cstIcms);
  }

  double get total => (quantidade * valorUnitario) - desconto;

  void recalcular() {
    quantidade =
        double.tryParse(qtdCtrl.text.replaceAll(',', '.')) ?? 1;
    valorUnitario = double.tryParse(valorCtrl.text.replaceAll(',', '.')) ??
        valorUnitario;
    desconto =
        double.tryParse(descCtrl.text.replaceAll(',', '.')) ?? 0;
  }

  void dispose() {
    qtdCtrl.dispose();
    valorCtrl.dispose();
    descCtrl.dispose();
    cstCtrl.dispose();
  }
}

class _ProdutoSearchItem {
  final String id;
  final String nome;
  final String codigo;
  final String codigoBarras;
  final String sku;
  final String ncm;
  final String cest;
  final String cstIcms;
  final double preco;

  const _ProdutoSearchItem({
    required this.id,
    required this.nome,
    this.codigo = '',
    this.codigoBarras = '',
    this.sku = '',
    this.ncm = '',
    this.cest = '',
    this.cstIcms = '',
    this.preco = 0,
  });

  factory _ProdutoSearchItem.fromDoc(String id, Map<String, dynamic> doc) {
    return _ProdutoSearchItem(
      id: id,
      nome: (doc['nome'] ?? doc['titulo'] ?? 'Produto').toString(),
      codigo: (doc['codigo'] ?? '').toString(),
      codigoBarras: (doc['codigo_barras'] ?? doc['barras'] ?? '').toString(),
      sku: (doc['sku'] ?? '').toString(),
      ncm: (doc['ncm'] ?? '').toString(),
      cest: (doc['cest'] ?? '').toString(),
      cstIcms: (doc['cst_icms'] ?? doc['csosn'] ?? '').toString(),
      preco: (doc['preco'] as num?)?.toDouble() ??
          (doc['valor'] as num?)?.toDouble() ??
          0,
    );
  }
}

// =============================================================================
// MODAL — BUSCA CÓDIGO IBGE DE MUNICÍPIOS (premium com pesquisa)
// =============================================================================

class _CidadesIbgeSearchModal extends StatefulWidget {
  const _CidadesIbgeSearchModal();

  @override
  State<_CidadesIbgeSearchModal> createState() =>
      _CidadesIbgeSearchModalState();
}

class _CidadesIbgeSearchModalState extends State<_CidadesIbgeSearchModal> {
  final _buscaCtrl = TextEditingController();
  List<CidadeSugestao> _cidades = [];
  List<CidadeSugestao> _filtradas = [];
  bool _carregando = true;
  String _erro = '';

  @override
  void initState() {
    super.initState();
    _carregarCidades();
    _buscaCtrl.addListener(_filtrar);
  }

  @override
  void dispose() {
    _buscaCtrl.dispose();
    super.dispose();
  }

  Future<void> _carregarCidades() async {
    try {
      final cidades = await CidadesBrasilService.todasCidades();
      if (mounted) {
        setState(() {
          _cidades = cidades;
          _filtradas = cidades;
          _carregando = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _erro = 'Erro ao carregar municípios: $e';
          _carregando = false;
        });
      }
    }
  }

  void _filtrar() {
    final termo = _buscaCtrl.text.trim().toLowerCase();
    setState(() {
      if (termo.isEmpty) {
        _filtradas = List.from(_cidades);
      } else {
        _filtradas = _cidades.where((c) {
          final nome = c.nome.toLowerCase();
          final uf = c.ufSigla.toLowerCase();
          return nome.contains(termo) || uf.contains(termo);
        }).toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
      child: Container(
        width: 560,
        constraints: const BoxConstraints(maxHeight: 640),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: Colors.white,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(24, 20, 16, 16),
              decoration: const BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: Color(0xFFF0EEF4)),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: const Color(0xFF6A1B9A).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.map_rounded,
                        color: Color(0xFF6A1B9A), size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      'Buscar Código IBGE',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF1A1A2E),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(context),
                    color: const Color(0xFF64748B),
                    tooltip: 'Fechar',
                  ),
                ],
              ),
            ),
            // Campo de busca
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 14, 24, 8),
              child: TextField(
                controller: _buscaCtrl,
                decoration: InputDecoration(
                  hintText: 'Digite o nome da cidade ou UF (ex: Rondonópolis, MT)',
                  prefixIcon: const Icon(Icons.search_rounded,
                      color: Color(0xFF64748B)),
                  filled: true,
                  fillColor: const Color(0xFFF5F4F8),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 14),
                ),
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 14, color: const Color(0xFF1A1A2E)),
              ),
            ),
            // Contagem
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: [
                  Text(
                    '${_filtradas.length} município(s)',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            // Lista
            Flexible(
              child: _carregando
                  ? const Center(child: CircularProgressIndicator())
                  : _erro.isNotEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(_erro,
                                style: GoogleFonts.plusJakartaSans(
                                    color: Colors.red)),
                          ),
                        )
                      : _filtradas.isEmpty
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(32),
                                child: Text(
                                  'Nenhuma cidade encontrada',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 14,
                                    color: const Color(0xFF64748B),
                                  ),
                                ),
                              ),
                            )
                          : ListView.builder(
                              shrinkWrap: true,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16),
                              itemCount: _filtradas.length,
                              itemBuilder: (_, i) {
                                final c = _filtradas[i];
                                final selecionado =
                                    c.codigoIbge.isNotEmpty;
                                return Container(
                                  margin:
                                      const EdgeInsets.only(bottom: 4),
                                  decoration: BoxDecoration(
                                    borderRadius:
                                        BorderRadius.circular(10),
                                    border: Border.all(
                                      color: const Color(0xFFF0EEF4),
                                    ),
                                  ),
                                  child: Material(
                                    color: Colors.transparent,
                                    borderRadius:
                                        BorderRadius.circular(10),
                                    child: InkWell(
                                      borderRadius:
                                          BorderRadius.circular(10),
                                      onTap: () {
                                        Navigator.pop(
                                            context, c.codigoIbge);
                                      },
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 14,
                                            vertical: 12),
                                        child: Row(
                                          children: [
                                            Container(
                                              width: 36,
                                              height: 36,
                                              decoration: BoxDecoration(
                                                color: const Color(
                                                        0xFF6A1B9A)
                                                    .withValues(alpha: 0.08),
                                                borderRadius:
                                                    BorderRadius.circular(9),
                                              ),
                                              child: Center(
                                                child: Text(
                                                  c.ufSigla,
                                                  style: GoogleFonts
                                                      .plusJakartaSans(
                                                    fontSize: 11,
                                                    fontWeight:
                                                        FontWeight.w800,
                                                    color: const Color(
                                                        0xFF6A1B9A),
                                                  ),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment
                                                        .start,
                                                children: [
                                                  Text(
                                                    c.nome,
                                                    style: GoogleFonts
                                                        .plusJakartaSans(
                                                      fontSize: 13,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      color: const Color(
                                                          0xFF1A1A2E),
                                                    ),
                                                  ),
                                                  Text(
                                                    c.ufNome,
                                                    style: GoogleFonts
                                                        .plusJakartaSans(
                                                      fontSize: 11,
                                                      color: const Color(
                                                          0xFF64748B),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            if (selecionado)
                                              Container(
                                                padding:
                                                    const EdgeInsets
                                                        .symmetric(
                                                  horizontal: 10,
                                                  vertical: 4,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: const Color(
                                                          0xFF6A1B9A)
                                                      .withValues(alpha: 0.08),
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                          8),
                                                ),
                                                child: Text(
                                                  c.codigoIbge,
                                                  style: GoogleFonts
                                                      .plusJakartaSans(
                                                    fontSize: 12,
                                                    fontWeight:
                                                        FontWeight.w700,
                                                    color: const Color(
                                                        0xFF6A1B9A),
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
            ),
            // Footer
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                border: Border(
                  top: BorderSide(color: Color(0xFFF0EEF4)),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(
                      'Cancelar',
                      style: GoogleFonts.plusJakartaSans(
                        color: const Color(0xFF64748B),
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

// =============================================================================
// MODAL — EMITIR NOTA (animação de transmissão profissional)
// =============================================================================

class _EmitirNotaModal extends StatefulWidget {
  final String storeId;
  final String notaId;
  final String clienteNome;
  final double valorTotal;

  const _EmitirNotaModal({
    required this.storeId,
    required this.notaId,
    required this.clienteNome,
    required this.valorTotal,
  });

  @override
  State<_EmitirNotaModal> createState() => _EmitirNotaModalState();
}

class _EmitirNotaModalState extends State<_EmitirNotaModal>
    with TickerProviderStateMixin {
  int _etapaAtual = 0;
  bool _concluido = false;
  bool _erro = false;

  late AnimationController _progressCtrl;
  late Animation<double> _progressAnim;
  Timer? _etapaTimer;

  Map<String, dynamic>? _resultado;

  static const _etapas = [
    'Preparando XML',
    'Validando informações',
    'Assinando Digitalmente',
    'Transmitindo ao SEFAZ',
    'Aguardando retorno',
    'Recebendo protocolo',
  ];

  @override
  void initState() {
    super.initState();
    _progressCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _progressAnim = CurvedAnimation(
      parent: _progressCtrl,
      curve: Curves.easeInOut,
    );
    _iniciarEmissao();
  }

  @override
  void dispose() {
    _progressCtrl.dispose();
    _etapaTimer?.cancel();
    super.dispose();
  }

  void _iniciarEmissao() {
    _avancarEtapa();
  }

  void _avancarEtapa() {
    if (_etapaAtual >= _etapas.length) {
      _finalizar();
      return;
    }

    _progressCtrl.forward(from: 0).then((_) {
      _etapaTimer = Timer(const Duration(milliseconds: 800), () {
        if (mounted) {
          setState(() => _etapaAtual++);
          _avancarEtapa();
        }
      });
    });
  }

  Future<void> _finalizar() async {
    // Simula transmissão — em produção, chama API do provedor
    try {
      await Future.delayed(const Duration(milliseconds: 500));

      final now = DateTime.now();
      // Gera número e chave simulados
      final serie = '1';
      final numero = '${now.year % 100}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
      final chave = '${now.year}${now.month.toString().padLeft(2, '0')}${_gerarChaveAleatoria()}';

      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.storeId)
          .collection('notas_fiscais')
          .doc(widget.notaId)
          .update({
        'situacao': 'emitida',
        'numero_nfe': numero,
        'serie': serie,
        'chave_acesso': chave,
        'data_emissao': Timestamp.fromDate(now),
        'usuario_responsavel':
            FirebaseAuth.instance.currentUser?.uid ?? '',
        'logs': FieldValue.arrayUnion([
          {
            'evento': 'emitida',
            'data': Timestamp.fromDate(now),
            'usuario': FirebaseAuth.instance.currentUser?.uid ?? '',
            'descricao': 'NF-e emitida com sucesso (protocolo: $chave)',
          }
        ]),
      });

      // Atualiza contagem na integração
      await LojistaIntegracaoService.registrarEmissao(widget.storeId);

      if (mounted) {
        setState(() {
          _concluido = true;
          _resultado = {
            'numero': numero,
            'protocolo': chave.substring(0, 15),
            'chave': chave,
            'data': DateFormat('dd/MM/yyyy').format(now),
            'hora': DateFormat('HH:mm:ss').format(now),
          };
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _erro = true);
      }
    }
  }

  String _gerarChaveAleatoria() {
    final rng = Random();
    final sb = StringBuffer();
    for (var i = 0; i < 30; i++) {
      sb.write(rng.nextInt(10));
    }
    return sb.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 80, vertical: 60),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: 480,
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: _concluido
            ? _buildSucesso()
            : _erro
                ? _buildErro()
                : _buildTransmitindo(),
      ),
    );
  }

  Widget _buildTransmitindo() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Título
        Text(
          'Emitindo Nota Fiscal',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: _textoPrimario,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Cliente: ${widget.clienteNome}',
          style: GoogleFonts.plusJakartaSans(
              fontSize: 12, color: _textoSecundario),
        ),
        const SizedBox(height: 24),
        // Animação SVG-like (círculo pulsante)
        SizedBox(
          width: 100,
          height: 100,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Anel externo
              SizedBox(
                width: 100,
                height: 100,
                child: RotationTransition(
                  turns: _progressAnim,
                  child: const CircularProgressIndicator(
                    strokeWidth: 4,
                    valueColor: AlwaysStoppedAnimation<Color>(_roxo),
                  ),
                ),
              ),
              // Ícone central
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: _lilas,
                  borderRadius: BorderRadius.circular(36),
                ),
                child: Icon(
                  _etapaAtual < 3
                      ? Icons.cloud_upload_rounded
                      : Icons.cloud_done_rounded,
                  size: 32,
                  color: _roxo,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        // Etapas
        ...List.generate(_etapas.length, (i) {
          final ativa = i == _etapaAtual;
          final concluida = i < _etapaAtual;
          return Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                Icon(
                  concluida
                      ? Icons.check_circle_rounded
                      : ativa
                          ? Icons.hourglass_top_rounded
                          : Icons.circle_outlined,
                  size: 18,
                  color: concluida
                      ? _verde
                      : ativa
                          ? _roxo
                          : _borda,
                ),
                const SizedBox(width: 10),
                Text(
                  _etapas[i],
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    fontWeight:
                        ativa ? FontWeight.w700 : FontWeight.w500,
                    color: concluida
                        ? _textoSecundario
                        : ativa
                            ? _roxo
                            : _borda,
                  ),
                ),
                const Spacer(),
                if (ativa)
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
          );
        }),
        const SizedBox(height: 24),
        Text(
          'Aguarde enquanto processamos sua solicitação...',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 11,
            color: _textoSecundario,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildSucesso() {
    final r = _resultado!;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Ícone de sucesso
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: _verdeFundo,
            borderRadius: BorderRadius.circular(40),
          ),
          child: const Icon(Icons.check_circle_rounded,
              size: 48, color: _verde),
        ),
        const SizedBox(height: 16),
        Text(
          'Nota emitida com sucesso!',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: _textoPrimario,
          ),
        ),
        const SizedBox(height: 20),
        _resultadoLinha('Número', r['numero']),
        _resultadoLinha('Protocolo', r['protocolo']),
        _resultadoLinha('Chave de acesso', r['chave']),
        _resultadoLinha('Data', r['data']),
        _resultadoLinha('Hora', r['hora']),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              onTap: () => Navigator.of(context).pop(),
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                      colors: [_roxo, _roxoClaro]),
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: _roxo.withValues(alpha: 0.25),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Center(
                  child: Text(
                    'Fechar',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildErro() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: _vermelhoFundo,
            borderRadius: BorderRadius.circular(40),
          ),
          child: const Icon(Icons.error_rounded,
              size: 48, color: _vermelho),
        ),
        const SizedBox(height: 16),
        Text(
          'Erro ao emitir NF-e',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: _textoPrimario,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Ocorreu um erro durante a transmissão.\nTente novamente mais tarde.',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 12,
            color: _textoSecundario,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: () => Navigator.of(context).pop(),
            style: OutlinedButton.styleFrom(
              foregroundColor: _roxo,
              side: const BorderSide(color: _roxo),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text('Fechar'),
          ),
        ),
      ],
    );
  }

  Widget _resultadoLinha(String label, String valor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: GoogleFonts.plusJakartaSans(
                fontSize: 11, color: _textoSecundario),
          ),
          Text(
            valor,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: _textoPrimario,
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// MODAL — ENVIAR NOTA (com animação de envio por e-mail)
// =============================================================================

class _EnviarNotaModal extends StatefulWidget {
  final String storeId;
  final String notaId;
  final String clienteNome;
  final String clienteEmail;
  final String numeroNfe;

  const _EnviarNotaModal({
    required this.storeId,
    required this.notaId,
    required this.clienteNome,
    this.clienteEmail = '',
    this.numeroNfe = '',
  });

  @override
  State<_EnviarNotaModal> createState() => _EnviarNotaModalState();
}

class _EnviarNotaModalState extends State<_EnviarNotaModal>
    with TickerProviderStateMixin {
  bool _enviando = false;
  bool _concluido = false;
  late AnimationController _animCtrl;

  static const _etapas = [
    'Preparando XML',
    'Preparando DANFE',
    'Anexando PDF',
    'Enviando Email',
    'Aguardando confirmação',
  ];

  int _etapaAtual = 0;
  Timer? _etapaTimer;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    _etapaTimer?.cancel();
    super.dispose();
  }

  void _iniciarEnvio() {
    setState(() => _enviando = true);
    _animCtrl.forward();
    _avancarEtapa();
  }

  void _avancarEtapa() {
    if (_etapaAtual >= _etapas.length) {
      _finalizar();
      return;
    }

    Future.delayed(const Duration(milliseconds: 700), () {
      if (mounted) {
        setState(() => _etapaAtual++);
        _avancarEtapa();
      }
    });
  }

  Future<void> _finalizar() async {
    try {
      final now = DateTime.now();

      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.storeId)
          .collection('notas_fiscais')
          .doc(widget.notaId)
          .update({
        'situacao': 'enviada',
        'data_envio': Timestamp.fromDate(now),
        'email_destinatario': widget.clienteEmail,
        'logs': FieldValue.arrayUnion([
          {
            'evento': 'enviada',
            'data': Timestamp.fromDate(now),
            'usuario': FirebaseAuth.instance.currentUser?.uid ?? '',
            'descricao':
                'NF-e enviada por e-mail para ${widget.clienteEmail}',
          }
        ]),
      });

      if (mounted) {
        setState(() => _concluido = true);
      }
    } catch (_) {
      if (mounted) {
        Navigator.of(context).pop(false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 80, vertical: 80),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: 420,
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: _concluido
            ? _buildSucesso()
            : _enviando
                ? _buildEnviando()
                : _buildConfirmacao(),
      ),
    );
  }

  Widget _buildConfirmacao() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: _lilas,
            borderRadius: BorderRadius.circular(36),
          ),
          child: const Icon(Icons.email_rounded, size: 36, color: _roxo),
        ),
        const SizedBox(height: 16),
        Text(
          'Enviar NF-e por E-mail',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: _textoPrimario,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Deseja enviar esta NF-e ${widget.numeroNfe.isNotEmpty ? '(${widget.numeroNfe}) ' : ''}para o e-mail do cliente?',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 13,
            color: _textoSecundario,
          ),
          textAlign: TextAlign.center,
        ),
        if (widget.clienteEmail.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: _cinzaClaro,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              widget.clienteEmail,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: _roxo,
              ),
            ),
          ),
        ],
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
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
                onTap: _iniciarEnvio,
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24, vertical: 11),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                        colors: [_roxo, _roxoClaro]),
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [
                      BoxShadow(
                        color: _roxo.withValues(alpha: 0.25),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Text(
                    'Enviar',
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
      ],
    );
  }

  Widget _buildEnviando() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Enviando Nota Fiscal',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: _textoPrimario,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'NF-e ${widget.numeroNfe}',
          style: GoogleFonts.plusJakartaSans(
              fontSize: 12, color: _textoSecundario),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: 100,
          height: 100,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 100,
                height: 100,
                child: CircularProgressIndicator(
                  strokeWidth: 4,
                  valueColor:
                      const AlwaysStoppedAnimation<Color>(_roxo),
                ),
              ),
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: _lilas,
                  borderRadius: BorderRadius.circular(36),
                ),
                child: const Icon(Icons.email_rounded,
                    size: 32, color: _roxo),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        ...List.generate(_etapas.length, (i) {
          final ativa = i == _etapaAtual;
          final concluida = i < _etapaAtual;
          return Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                Icon(
                  concluida
                      ? Icons.check_circle_rounded
                      : ativa
                          ? Icons.hourglass_top_rounded
                          : Icons.circle_outlined,
                  size: 18,
                  color: concluida
                      ? _verde
                      : ativa
                          ? _roxo
                          : _borda,
                ),
                const SizedBox(width: 10),
                Text(
                  _etapas[i],
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    fontWeight:
                        ativa ? FontWeight.w700 : FontWeight.w500,
                    color: concluida
                        ? _textoSecundario
                        : ativa
                            ? _roxo
                            : _borda,
                  ),
                ),
              ],
            ),
          );
        }),
        const SizedBox(height: 16),
        Text(
          'Aguarde...',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 11,
            color: _textoSecundario,
          ),
        ),
      ],
    );
  }

  Widget _buildSucesso() {
    final now = DateTime.now();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: _verdeFundo,
            borderRadius: BorderRadius.circular(40),
          ),
          child: const Icon(Icons.check_circle_rounded,
              size: 48, color: _verde),
        ),
        const SizedBox(height: 16),
        Text(
          'Nota Fiscal enviada com sucesso!',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: _textoPrimario,
          ),
        ),
        const SizedBox(height: 16),
        _infoLinha('E-mail destinatário', widget.clienteEmail),
        _infoLinha(
            'Data', DateFormat('dd/MM/yyyy').format(now)),
        _infoLinha(
            'Hora', DateFormat('HH:mm:ss').format(now)),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              onTap: () => Navigator.of(context).pop(true),
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                      colors: [_roxo, _roxoClaro]),
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: _roxo.withValues(alpha: 0.25),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Center(
                  child: Text(
                    'Fechar',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _infoLinha(String label, String valor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: GoogleFonts.plusJakartaSans(
                fontSize: 11, color: _textoSecundario),
          ),
          Text(
            valor,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: _textoPrimario,
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// MODAL — JUSTIFICATIVA (genérico)
// =============================================================================

class _JustificativaDialog extends StatefulWidget {
  final String titulo;
  final String hint;

  const _JustificativaDialog({
    required this.titulo,
    required this.hint,
  });

  @override
  State<_JustificativaDialog> createState() => _JustificativaDialogState();
}

class _JustificativaDialogState extends State<_JustificativaDialog> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: 420,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.titulo,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: _textoPrimario,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Informe o motivo',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 12, color: _textoSecundario),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _ctrl,
              maxLines: 4,
              decoration: InputDecoration(
                hintText: widget.hint,
                hintStyle: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    color: _textoSecundario.withValues(alpha: 0.5)),
                filled: true,
                fillColor: _cinzaClaro,
                contentPadding: const EdgeInsets.all(12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: _borda),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: _borda),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: _roxo, width: 1.5),
                ),
              ),
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 13, color: _textoPrimario),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(
                    'Cancelar',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 13, color: _textoSecundario),
                  ),
                ),
                const SizedBox(width: 12),
                Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  child: InkWell(
                    onTap: _ctrl.text.trim().isEmpty
                        ? null
                        : () =>
                            Navigator.of(context).pop(_ctrl.text.trim()),
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 10),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                            colors: [_roxo, _roxoClaro]),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        'Confirmar',
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
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// MODAL — VISUALIZAR DANFE
// =============================================================================

class _DanfePreviewDialog extends StatelessWidget {
  final String chaveAcesso;
  final String numeroNfe;

  const _DanfePreviewDialog({
    required this.chaveAcesso,
    this.numeroNfe = '',
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 120, vertical: 60),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: 500,
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _lilas,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.picture_as_pdf_rounded,
                      color: _roxo, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'DANFE${numeroNfe.isNotEmpty ? ' — NF-e $numeroNfe' : ''}',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: _textoPrimario,
                        ),
                      ),
                      Text(
                        'Documento Auxiliar da NF-e',
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 11, color: _textoSecundario),
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
            const SizedBox(height: 20),
            Center(
              child: Column(
                children: [
                  Icon(Icons.picture_as_pdf_rounded,
                      size: 64,
                      color: _roxo.withValues(alpha: 0.3)),
                  const SizedBox(height: 12),
                  Text(
                    'Pré-visualização do DANFE',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: _textoSecundario,
                    ),
                  ),
                  if (chaveAcesso.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Chave: $chaveAcesso',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 11, color: _textoSecundario),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.download_rounded, size: 16),
                label: const Text('Baixar PDF'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _roxo,
                  side: const BorderSide(color: _roxo),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// MODAL — VISUALIZAR XML
// =============================================================================

class _XmlPreviewDialog extends StatelessWidget {
  final String numeroNfe;
  final String xmlConteudo;

  const _XmlPreviewDialog({
    this.numeroNfe = '',
    this.xmlConteudo = '',
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 120, vertical: 60),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: 600,
        constraints: const BoxConstraints(maxHeight: 500),
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _lilas,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.code_rounded,
                      color: _roxo, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'XML da NF-e${numeroNfe.isNotEmpty ? ' $numeroNfe' : ''}',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: _textoPrimario,
                        ),
                      ),
                      Text(
                        'Arquivo XML da NF-e',
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 11, color: _textoSecundario),
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
            const SizedBox(height: 16),
            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E2E),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: SingleChildScrollView(
                  child: SelectableText(
                    xmlConteudo.isNotEmpty
                        ? xmlConteudo
                        : '<?xml version="1.0" encoding="UTF-8"?>\n'
                            '<nfeProc xmlns="http://www.portalfiscal.inf.br/nfe">\n'
                            '  <!-- XML da NF-e será exibido aqui -->\n'
                            '</nfeProc>',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 11,
                      color: const Color(0xFFD4D4D4),
                      height: 1.5,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.download_rounded, size: 16),
                label: const Text('Download XML'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _roxo,
                  side: const BorderSide(color: _roxo),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// MODAL — HISTÓRICO DA NF-e
// =============================================================================

class _HistoricoNfeDialog extends StatelessWidget {
  final Map<String, dynamic> nota;
  final String Function(dynamic) fmtData;
  final NumberFormat moeda;

  const _HistoricoNfeDialog({
    required this.nota,
    required this.fmtData,
    required this.moeda,
  });

  @override
  Widget build(BuildContext context) {
    final logs = (nota['logs'] as List<dynamic>?) ?? [];
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 100, vertical: 60),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: 520,
        constraints: const BoxConstraints(maxHeight: 500),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(24, 20, 16, 14),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: _borda)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _lilas,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.history_rounded,
                        color: _roxo, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Histórico da NF-e',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: _textoPrimario,
                          ),
                        ),
                        Text(
                          '${nota['numero_nfe'] ?? '—'} — ${nota['cliente_nome'] ?? '—'}',
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 11, color: _textoSecundario),
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
            Expanded(
              child: logs.isEmpty
                  ? Center(
                      child: Text(
                        'Nenhum evento registrado',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          color: _textoSecundario,
                        ),
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.all(20),
                      children: logs.reversed.map((log) {
                        final m = log as Map<String, dynamic>;
                        final evento =
                            (m['evento'] ?? '').toString();
                        final descricao =
                            (m['descricao'] ?? '').toString();
                        final ts = m['data'];
                        final data = ts is Timestamp
                            ? DateFormat('dd/MM/yyyy HH:mm:ss')
                                .format(ts.toDate())
                            : '—';

                        IconData icone;
                        Color cor;
                        switch (evento) {
                          case 'criada':
                            icone = Icons.add_circle_rounded;
                            cor = _roxo;
                            break;
                          case 'emitida':
                            icone = Icons.cloud_done_rounded;
                            cor = _verde;
                            break;
                          case 'enviada':
                            icone = Icons.send_rounded;
                            cor = _azul;
                            break;
                          case 'cancelada':
                            icone = Icons.block_rounded;
                            cor = _vermelho;
                            break;
                          case 'cce':
                            icone = Icons.edit_note_rounded;
                            cor = _laranja;
                            break;
                          default:
                            icone = Icons.info_rounded;
                            cor = _textoSecundario;
                        }

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: cor.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(icone, size: 14, color: cor),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      evento.toUpperCase(),
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 12,
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
                              Text(
                                data,
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 10,
                                  color: _textoSecundario,
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// MODAL — CANCELAMENTO DE NF-e (PREMIUM)
// =============================================================================

class _CancelamentoDialog extends StatefulWidget {
  final String numeroNfe;
  final String clienteNome;

  const _CancelamentoDialog({
    required this.numeroNfe,
    required this.clienteNome,
  });

  @override
  State<_CancelamentoDialog> createState() => _CancelamentoDialogState();
}

class _CancelamentoDialogState extends State<_CancelamentoDialog> {
  final _justificativaCtrl = TextEditingController();
  final bool _enviando = false;

  @override
  void dispose() {
    _justificativaCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: 480,
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.block_rounded,
                      color: _vermelho, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Cancelar NF-e',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: _textoPrimario,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'NF-e ${widget.numeroNfe} — ${widget.clienteNome}',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          color: _textoSecundario,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed:
                      _enviando ? null : () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded,
                      color: _textoSecundario),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF8E1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: const Color(0xFFD97706).withValues(alpha: 0.3)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_rounded,
                      size: 16, color: Color(0xFFD97706)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'O cancelamento só é permitido dentro do prazo legal '
                      '(24h após autorização da SEFAZ). Esta ação não pode '
                      'ser desfeita.',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11,
                        color: const Color(0xFF92400E),
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Justificativa do cancelamento',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: _textoPrimario,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Descreva o motivo detalhado para o cancelamento.',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 11,
                color: _textoSecundario,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _justificativaCtrl,
              maxLines: 4,
              maxLength: 500,
              decoration: InputDecoration(
                hintText: 'Ex.: Cliente solicitou cancelamento...',
                hintStyle: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    color: _textoSecundario.withValues(alpha: 0.5)),
                filled: true,
                fillColor: _cinzaClaro,
                contentPadding: const EdgeInsets.all(12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: _borda),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: _borda),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: _roxo, width: 1.5),
                ),
              ),
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 13, color: _textoPrimario),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed:
                      _enviando ? null : () => Navigator.of(context).pop(),
                  child: Text(
                    'Voltar',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 13, color: _textoSecundario),
                  ),
                ),
                const SizedBox(width: 12),
                Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  child: InkWell(
                    onTap: _enviando ||
                            _justificativaCtrl.text.trim().length < 10
                        ? null
                        : _confirmarCancelamento,
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 10),
                      decoration: BoxDecoration(
                        color: _enviando ? _textoSecundario : _vermelho,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: _enviando
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              'Confirmar Cancelamento',
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
          ],
        ),
      ),
    );
  }

  void _confirmarCancelamento() {
    Navigator.of(context).pop({
      'justificativa': _justificativaCtrl.text.trim(),
      'usuario_nome': 'Administrador',
    });
  }
}

// =============================================================================
// MODAL — CARTA DE CORREÇÃO (CC-e)
// =============================================================================

class _CartaCorrecaoDialog extends StatefulWidget {
  final String numeroNfe;
  final int sequencia;

  const _CartaCorrecaoDialog({
    required this.numeroNfe,
    required this.sequencia,
  });

  @override
  State<_CartaCorrecaoDialog> createState() => _CartaCorrecaoDialogState();
}

class _CartaCorrecaoDialogState extends State<_CartaCorrecaoDialog> {
  final _correcaoCtr = TextEditingController();
  final _maxCaracteres = FiscalCartaCorrecaoService.maxTextoCorrecao;

  @override
  void dispose() {
    _correcaoCtr.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final restante = _maxCaracteres - _correcaoCtr.text.length;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: 520,
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _amareloFundo,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.edit_note_rounded,
                      color: _laranja, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Carta de Correção (CC-e)',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: _textoPrimario,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'NF-e ${widget.numeroNfe} — Correção #${widget.sequencia}',
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
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _lilas,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_rounded,
                      size: 16, color: _roxo),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'A CC-e permite corrigir informações como dados do '
                      'produto, valores, CFOP, NCM e observações. Não é '
                      'permitido alterar destinatário, data de emissão e '
                      'natureza da operação.',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11,
                        color: _roxoClaro,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Descrição da correção',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: _textoPrimario,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Informe detalhadamente o que está sendo corrigido.',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 11,
                color: _textoSecundario,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _correcaoCtr,
              maxLines: 5,
              maxLength: _maxCaracteres,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Ex.: Correção do valor unitário do produto X...',
                hintStyle: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    color: _textoSecundario.withValues(alpha: 0.5)),
                filled: true,
                fillColor: _cinzaClaro,
                contentPadding: const EdgeInsets.all(12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: _borda),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: _borda),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: _roxo, width: 1.5),
                ),
              ),
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 13, color: _textoPrimario),
            ),
            if (restante <= 50)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '$restante caracteres restantes',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 10,
                    color: restante <= 10 ? _vermelho : _laranja,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Limite: 5 CC-e por NF-e',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 10,
                    color: _textoSecundario,
                  ),
                ),
                Row(
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(
                        'Cancelar',
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 13, color: _textoSecundario),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Material(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                      child: InkWell(
                        onTap: _correcaoCtr.text.trim().length < 15
                            ? null
                            : _confirmarCce,
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 10),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                                colors: [_roxo, _roxoClaro]),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            'Emitir CC-e',
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
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _confirmarCce() {
    Navigator.of(context).pop({
      'correcao': _correcaoCtr.text.trim(),
      'usuario_nome': 'Administrador',
    });
  }
}

// =============================================================================
// MODAL — INUTILIZAÇÃO DE NUMERAÇÃO
// =============================================================================

class _InutilizacaoDialog extends StatefulWidget {
  final String numeroNfe;
  final String serie;
  final String storeId;

  const _InutilizacaoDialog({
    required this.numeroNfe,
    required this.serie,
    required this.storeId,
  });

  @override
  State<_InutilizacaoDialog> createState() => _InutilizacaoDialogState();
}

class _InutilizacaoDialogState extends State<_InutilizacaoDialog> {
  final _justificativaCtrl = TextEditingController();
  int _numeroInicial = 0;
  int _numeroFinal = 0;

  @override
  void dispose() {
    _justificativaCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: 480,
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.numbers_rounded,
                      color: _vermelho, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Inutilizar Numeração',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: _textoPrimario,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Série ${widget.serie} — ${widget.numeroNfe}',
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
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF8E1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: const Color(0xFFD97706).withValues(alpha: 0.3)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_rounded,
                      size: 16, color: Color(0xFFD97706)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Utilize esta função quando houver quebra na sequência '
                      'numérica da NF-e (ex.: nota cancelada antes da '
                      'transmissão). A numeração inutilizada não poderá ser '
                      'recuperada.',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11,
                        color: const Color(0xFF92400E),
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Faixa de numeração a inutilizar',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: _textoPrimario,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: InputDecoration(
                      labelText: 'Nº inicial',
                      labelStyle: GoogleFonts.plusJakartaSans(
                          fontSize: 12, color: _textoSecundario),
                      hintText: 'Ex.: 1',
                      filled: true,
                      fillColor: _cinzaClaro,
                      contentPadding: const EdgeInsets.all(12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: _borda),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: _borda),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide:
                            const BorderSide(color: _roxo, width: 1.5),
                      ),
                    ),
                    keyboardType: TextInputType.number,
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 13, color: _textoPrimario),
                    onChanged: (v) =>
                        setState(() => _numeroInicial = int.tryParse(v) ?? 0),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    'até',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      color: _textoSecundario,
                    ),
                  ),
                ),
                Expanded(
                  child: TextField(
                    decoration: InputDecoration(
                      labelText: 'Nº final',
                      labelStyle: GoogleFonts.plusJakartaSans(
                          fontSize: 12, color: _textoSecundario),
                      hintText: 'Ex.: 5',
                      filled: true,
                      fillColor: _cinzaClaro,
                      contentPadding: const EdgeInsets.all(12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: _borda),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: _borda),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide:
                            const BorderSide(color: _roxo, width: 1.5),
                      ),
                    ),
                    keyboardType: TextInputType.number,
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 13, color: _textoPrimario),
                    onChanged: (v) =>
                        setState(() => _numeroFinal = int.tryParse(v) ?? 0),
                  ),
                ),
              ],
            ),
            if (_numeroInicial > _numeroFinal && _numeroFinal > 0)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Número final deve ser maior ou igual ao inicial.',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 10,
                    color: _vermelho,
                  ),
                ),
              ),
            const SizedBox(height: 16),
            Text(
              'Justificativa',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: _textoPrimario,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _justificativaCtrl,
              maxLines: 3,
              maxLength: 300,
              decoration: InputDecoration(
                hintText: 'Motivo da inutilização...',
                hintStyle: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    color: _textoSecundario.withValues(alpha: 0.5)),
                filled: true,
                fillColor: _cinzaClaro,
                contentPadding: const EdgeInsets.all(12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: _borda),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: _borda),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: _roxo, width: 1.5),
                ),
              ),
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 13, color: _textoPrimario),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(
                    'Cancelar',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 13, color: _textoSecundario),
                  ),
                ),
                const SizedBox(width: 12),
                Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  child: InkWell(
                    onTap: _podeConfirmar ? _confirmarInutilizacao : null,
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 10),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                            colors: [_roxo, _roxoClaro]),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        'Inutilizar',
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
          ],
        ),
      ),
    );
  }

  bool get _podeConfirmar =>
      _numeroInicial > 0 &&
      _numeroFinal >= _numeroInicial &&
      _justificativaCtrl.text.trim().length >= 10;

  void _confirmarInutilizacao() {
    Navigator.of(context).pop({
      'justificativa': _justificativaCtrl.text.trim(),
      'numero_inicial': _numeroInicial,
      'numero_final': _numeroFinal,
      'usuario_nome': 'Administrador',
    });
  }
}
