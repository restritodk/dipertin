import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/audit_filtros_model.dart';
import '../models/audit_log_model.dart';
import '../services/auditoria_service.dart';
import '../theme/painel_admin_theme.dart';
import '../utils/admin_perfil.dart';
import '../widgets/auditoria/auditoria_categoria_tabs.dart';
import '../widgets/auditoria/auditoria_detalhes_modal.dart';
import '../widgets/auditoria/auditoria_empty_state.dart';
import '../widgets/auditoria/auditoria_filtros_bar.dart';
import '../widgets/auditoria/auditoria_kpi_cards.dart';
import '../widgets/auditoria/auditoria_tabela.dart';
import '../widgets/auditoria/auditoria_usuario_search.dart';

/// Tela principal de Auditoria do Sistema (apenas staff).
class AuditoriaScreen extends StatefulWidget {
  const AuditoriaScreen({super.key});

  @override
  State<AuditoriaScreen> createState() => _AuditoriaScreenState();
}

class _AuditoriaScreenState extends State<AuditoriaScreen> {
  // ── Estado de carregamento
  bool _carregando = true;
  String? _erro;
  bool _semPermissao = false;

  // ── Perfil do usuário logado
  String _perfil = 'cliente';

  // ── Filtros
  AuditFiltros _filtros = AuditFiltros.empty;
  AuditUser? _usuarioSelecionado;

  // ── Dados
  List<AuditLog> _eventos = const [];
  AuditStats _stats = const AuditStats();
  bool _statsCarregando = true;

  // ── Paginação
  static const int _pageSize = 25;
  String? _cursorDocId;
  bool _temMais = false;
  bool _carregandoMais = false;

  // ── Tempo real
  StreamSubscription<QuerySnapshot>? _realtimeSub;
  DateTime? _ultimaRenderizacao;
  int _novosEventos = 0;

  // ── Exportação
  bool _exportando = false;

  // ── Throttle de refresh
  DateTime _ultimoRefresh = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _refreshThrottle = Duration(seconds: 5);

  // ── Debug
  String _dbgUid = '?';
  String _dbgPerfil = '?';
  String? _dbgUltimoErro;
  int _dbgEventosCarregados = 0;
  bool _dbgMostrarDebug = true;

  @override
  void initState() {
    super.initState();
    _verificarPermissaoEIniciar();
    // Loga acesso (best-effort)
    unawaited(AuditoriaService.logAcessoTela());
  }

  @override
  void dispose() {
    _realtimeSub?.cancel();
    super.dispose();
  }

  Future<void> _verificarPermissaoEIniciar() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      setState(() {
        _semPermissao = true;
        _carregando = false;
      });
      return;
    }
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      if (!doc.exists) {
        setState(() {
          _semPermissao = true;
          _carregando = false;
        });
        return;
      }
      final dados = doc.data() ?? {};
      final perfil = perfilAdministrativoPainel(dados);
      _perfil = perfil;
      if (perfil != 'master' &&
          perfil != 'master_city' &&
          perfil != 'superadmin' &&
          perfil != 'super_admin') {
        setState(() {
          _semPermissao = true;
          _carregando = false;
        });
        return;
      }
    } catch (e) {
      setState(() {
        _erro = 'Erro ao verificar permissões: $e';
        _carregando = false;
      });
      return;
    }
    await _carregarTudo();
  }

  Future<void> _carregarTudo() async {
    await Future.wait([
      _carregarEventos(reset: true),
      _carregarStats(),
    ]);
    if (mounted) {
      setState(() => _carregando = false);
    }
    _iniciarRealtime();
  }

  Future<void> _carregarStats() async {
    if (!mounted) return;
    setState(() => _statsCarregando = true);
    try {
      final s = await AuditoriaService.estatisticas(filtros: _filtros);
      if (mounted) setState(() => _stats = s);
    } catch (e) {
      debugPrint('[_AuditoriaScreen] stats falhou: $e');
    } finally {
      if (mounted) setState(() => _statsCarregando = false);
    }
  }

  Future<void> _carregarEventos({bool reset = false}) async {
    if (reset) {
      _cursorDocId = null;
      _temMais = false;
    }
    try {
      final filtros = _filtros.copyWith(atorUid: _usuarioSelecionado?.uid);
      final page = await AuditoriaService.listarEventos(
        filtros: filtros,
        cursorDocId: reset ? null : _cursorDocId,
        direction: 'next',
        pageSize: _pageSize,
      );
      if (!mounted) return;
      setState(() {
        if (reset) {
          _eventos = page.items;
        } else {
          _eventos = [..._eventos, ...page.items];
        }
        _cursorDocId = page.lastDocId;
        _temMais = page.hasMore;
        _dbgEventosCarregados = _eventos.length;
      });
    } catch (e) {
      if (!mounted) return;
      _dbgUltimoErro = 'eventos: $e';
      setState(() => _erro = 'Erro ao carregar eventos: $e');
    }
  }

  void _iniciarRealtime() {
    _realtimeSub?.cancel();
    // Stream direto no Firestore para o usuário/filtro atual (limit 50, ordenação desc).
    // Não reposiciona a tabela: apenas atualiza o contador "novos registros".
    final firestore = FirebaseFirestore.instance;
    // Encadeia .where()/.orderBy() numa única expressão para preservar o tipo.
    final r = AuditPeriodo.range(_filtros.periodo);
    final tsInicio = r.inicio != null
        ? Timestamp.fromMillisecondsSinceEpoch(r.inicio!)
        : null;
    final tsFim = r.fim != null
        ? Timestamp.fromMillisecondsSinceEpoch(r.fim!)
        : null;
    final seletor = _usuarioSelecionado;
    final cat = _filtros.categoria;
    final mod = _filtros.modulo;
    final res = _filtros.resultado;
    final sev = _filtros.severidade;
    Query<Map<String, dynamic>> base =
        firestore.collection('audit_logs') as Query<Map<String, dynamic>>;
    if (seletor != null) {
      base = base.where('ator_uid', isEqualTo: seletor.uid);
    }
    if (cat != null && cat.isNotEmpty) {
      base = base.where('categoria', isEqualTo: cat);
    }
    if (mod != null && mod.isNotEmpty) {
      base = base.where('modulo', isEqualTo: mod);
    }
    if (res != null && res.isNotEmpty) {
      base = base.where('resultado', isEqualTo: res);
    }
    if (sev != null && sev.isNotEmpty) {
      base = base.where('detalhe.severidade', isEqualTo: sev);
    }
    if (tsInicio != null) {
      base = base.where('criado_em', isGreaterThanOrEqualTo: tsInicio);
    }
    if (tsFim != null) {
      base = base.where('criado_em', isLessThanOrEqualTo: tsFim);
    }
    final q = base.orderBy('criado_em', descending: true).limit(50);

    _realtimeSub = q.snapshots().listen((snap) {
      if (!mounted) return;
      // Só conta como "novo" se a última renderização é anterior.
      if (_ultimaRenderizacao != null) {
        final novos = snap.docs.where((d) {
          final t = (d.data()['criado_em'] as Timestamp?)?.toDate();
          return t != null && t.isAfter(_ultimaRenderizacao!);
        }).length;
        if (novos > 0) {
          setState(() => _novosEventos = novos);
        }
      }
      _ultimaRenderizacao = DateTime.now();
    }, onError: (e) {
      debugPrint('[_AuditoriaScreen] realtime error: $e');
    });
  }

  Future<void> _atualizarManual() async {
    final agora = DateTime.now();
    if (agora.difference(_ultimoRefresh) < _refreshThrottle) {
      _mostrarSnack('Aguarde alguns segundos antes de atualizar novamente.');
      return;
    }
    _ultimoRefresh = agora;
    setState(() => _novosEventos = 0);
    await _carregarTudo();
  }

  void _onAlterarFiltros(AuditFiltros novo) {
    setState(() {
      _filtros = novo;
      _carregando = true;
    });
    _carregarTudo();
  }

  void _onSelecionarCategoria(String? cat) {
    setState(() {
      // Mapear categoria da UI para categoria do Firestore
      _filtros = _filtros.copyWith(categoriaAtor: cat);
    });
    _carregarTudo();
  }

  void _onSelecionarUsuario(AuditUser? user) {
    setState(() {
      _usuarioSelecionado = user;
      _carregando = true;
    });
    _carregarTudo();
  }

  void _onLimparUsuario() {
    setState(() {
      _usuarioSelecionado = null;
      _carregando = true;
    });
    _carregarTudo();
  }

  void _onLimparFiltros() {
    setState(() {
      _filtros = AuditFiltros.empty;
      _carregando = true;
    });
    _carregarTudo();
  }

  Future<void> _onExportar() async {
    if (_perfil != 'master' && _perfil != 'superadmin' && _perfil != 'super_admin') {
      _mostrarSnack('Apenas master pode exportar a auditoria.');
      return;
    }
    setState(() => _exportando = true);
    try {
      final filtros = _filtros.copyWith(atorUid: _usuarioSelecionado?.uid);
      final r = await AuditoriaService.exportarCsv(filtros: filtros);
      if (!mounted) return;
      _mostrarSnack('Exportação gerada: ${r.totalRegistros} registros. Link válido até ${r.expiraEm}');
      // Tenta abrir em nova aba
      try {
        if (kIsWeb) {
          // ignore: avoid_print
          print('URL export: ${r.url}');
        }
      } catch (_) {}
    } catch (e) {
      _mostrarSnack('Falha na exportação: $e');
    } finally {
      if (mounted) setState(() => _exportando = false);
    }
  }

  void _mostrarSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_semPermissao) {
      return const AuditoriaSemPermissao();
    }
    if (_carregando) {
      return _loadingCompleto();
    }
    if (_erro != null && _eventos.isEmpty) {
      // Mostra erro + debug overlay para diagnóstico.
      return Stack(
        children: [
          AuditoriaErro(
            mensagem: _erro!,
            onTentarNovamente: () {
              setState(() => _erro = null);
              _carregarTudo();
            },
          ),
          _debugOverlay(),
        ],
      );
    }
    return Stack(
      children: [
        _buildBody(),
        if (_novosEventos > 0)
          Positioned(
            top: 12,
            right: 12,
            child: Material(
              color: PainelAdminTheme.roxo,
              borderRadius: BorderRadius.circular(20),
              elevation: 4,
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: _atualizarManual,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.fiber_new_rounded,
                          color: Colors.white, size: 16),
                      const SizedBox(width: 6),
                      Text(
                        '$_novosEventos novo(s) registro(s)',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Icon(Icons.refresh_rounded,
                          color: Colors.white, size: 14),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _loadingCompleto() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: const [
          SizedBox(
            width: 36,
            height: 36,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
          SizedBox(height: 12),
          Text('Carregando auditoria…',
              style: TextStyle(
                fontSize: 14,
                color: PainelAdminTheme.textoSecundario,
                fontWeight: FontWeight.w600,
              )),
        ],
      ),
    );
  }

  Widget _buildBody() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 80),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1280),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(),
              const SizedBox(height: 20),
              AuditoriaKpiCards(
                stats: _stats,
                carregando: _statsCarregando,
              ),
              const SizedBox(height: 24),
              AuditoriaCategoriaTabs(
                categoriaSelecionada: _filtros.categoriaAtor,
                onSelecionar: _onSelecionarCategoria,
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: AuditoriaUsuarioSearch(
                      categoriaAtor: _filtros.categoriaAtor,
                      usuarioSelecionado: _usuarioSelecionado?.nome,
                      onSelecionar: _onSelecionarUsuario,
                      onLimpar: _onLimparUsuario,
                    ),
                  ),
                  const SizedBox(width: 12),
                  if (_usuarioSelecionado != null)
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: _onLimparUsuario,
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 14),
                          decoration: BoxDecoration(
                            color: PainelAdminTheme.laranja.withValues(alpha: 0.10),
                            border: Border.all(
                                color: PainelAdminTheme.laranja
                                    .withValues(alpha: 0.4)),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: const [
                              Icon(Icons.person_off_outlined,
                                  color: PainelAdminTheme.laranja, size: 18),
                              SizedBox(width: 6),
                              Text(
                                'Limpar usuário',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: PainelAdminTheme.laranja,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 18),
              AuditoriaFiltrosBar(
                filtros: _filtros,
                onAlterar: _onAlterarFiltros,
                onLimpar: _onLimparFiltros,
                onExportar: _onExportar,
                exportando: _exportando,
                podeExportar: _perfil == 'master' ||
                    _perfil == 'superadmin' ||
                    _perfil == 'super_admin',
              ),
              const SizedBox(height: 18),
              AuditoriaTabela(
                eventos: _eventos,
                onDetalhes: (log) {
                  AuditoriaDetalhesModal.show(context, log);
                },
              ),
              if (_temMais) ...[
                const SizedBox(height: 16),
                Center(
                  child: _carregandoMais
                      ? const SizedBox(
                          width: 26,
                          height: 26,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        )
                      : OutlinedButton.icon(
                          onPressed: () {
                            setState(() => _carregandoMais = true);
                            _carregarEventos().whenComplete(() {
                              if (mounted) {
                                setState(() => _carregandoMais = false);
                              }
                            });
                          },
                          icon: const Icon(Icons.expand_more_rounded),
                          label: const Text('Carregar mais'),
                        ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF4A148C), Color(0xFF6A1B9A), Color(0xFF7B1FA2)],
          stops: [0.0, 0.5, 1.0],
        ),
        boxShadow: [
          BoxShadow(
            color: PainelAdminTheme.roxo.withValues(alpha: 0.25),
            blurRadius: 28,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(14),
              border:
                  Border.all(color: Colors.white.withValues(alpha: 0.25)),
            ),
            child: const Icon(Icons.fact_check_outlined,
                color: Colors.white, size: 26),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Auditoria do Sistema',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Acompanhe todas as ações realizadas por clientes, lojistas, '
                  'entregadores e administradores.',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 13.5,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _PequenoChip(
                      icon: Icons.update_rounded,
                      label: _ultimaRenderizacao != null
                          ? 'Atualizado ${DateFormat('HH:mm:ss').format(_ultimaRenderizacao!)}'
                          : 'Tempo real ativo',
                    ),
                    const SizedBox(width: 8),
                    _PequenoChip(
                      icon: Icons.filter_alt_rounded,
                      label: '${_eventos.length} visíveis',
                    ),
                  ],
                ),
              ],
            ),
          ),
          Material(
            color: Colors.white.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              onTap: _atualizarManual,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 10),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.refresh_rounded,
                        color: Colors.white, size: 18),
                    SizedBox(width: 6),
                    Text('Atualizar dados',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        )),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Overlay de diagnóstico — mostra estado atual em qualquer ponto da tela.
  Widget _debugOverlay() {
    if (!_dbgMostrarDebug) {
      return Positioned(
        right: 12,
        bottom: 12,
        child: Material(
          color: Colors.black.withValues(alpha: 0.7),
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: () => setState(() => _dbgMostrarDebug = true),
            child: const Padding(
              padding: EdgeInsets.all(8),
              child: Icon(Icons.bug_report_outlined,
                  color: Colors.white, size: 18),
            ),
          ),
        ),
      );
    }
    return Positioned(
      right: 12,
      bottom: 12,
      child: Material(
        color: const Color(0xCC000000),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Icon(Icons.bug_report_outlined,
                        color: Colors.amber, size: 16),
                    const SizedBox(width: 6),
                    const Text(
                      'Debug Auditoria',
                      style: TextStyle(
                        color: Colors.amber,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    InkWell(
                      onTap: () => setState(() => _dbgMostrarDebug = false),
                      child: const Icon(Icons.close,
                          color: Colors.white, size: 14),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                _dbgLine('uid', _dbgUid),
                _dbgLine('perfil', _dbgPerfil),
                _dbgLine('sem permissão', '$_semPermissao'),
                _dbgLine('carregando', '$_carregando'),
                _dbgLine('eventos', '$_dbgEventosCarregados'),
                _dbgLine('stats ok',
                    _stats.total >= 0 ? 'sim (${_stats.total})' : 'não'),
                if (_dbgUltimoErro != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.red.shade900,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'erro: $_dbgUltimoErro',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.amber.shade700,
                        foregroundColor: Colors.black,
                        minimumSize: const Size(0, 28),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        textStyle: const TextStyle(fontSize: 11),
                      ),
                      onPressed: _carregarTudo,
                      icon: const Icon(Icons.refresh, size: 14),
                      label: const Text('Recarregar'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _dbgLine(String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(
              '$k:',
              style: const TextStyle(
                color: Colors.white60,
                fontSize: 11,
                fontFamily: 'monospace',
              ),
            ),
          ),
          Expanded(
            child: Text(
              v,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontFamily: 'monospace',
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 3,
            ),
          ),
        ],
      ),
    );
  }
}

class _PequenoChip extends StatelessWidget {
  const _PequenoChip({required this.icon, required this.label});
  final IconData icon;
  final String label;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white.withValues(alpha: 0.85), size: 13),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.95),
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
