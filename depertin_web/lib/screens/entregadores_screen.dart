import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shimmer/shimmer.dart';
import 'package:url_launcher/url_launcher.dart';

import '../constants/conta_bloqueio_lojista.dart';
import '../constants/entregador_motivo_bloqueio_admin.dart';
import '../theme/painel_admin_theme.dart';
import '../utils/admin_perfil.dart';
import '../utils/conta_bloqueio_entregador.dart';
import '../services/firebase_functions_config.dart';
import '../services/sessao_painel_service.dart';
import '../widgets/entregador_editar_modal.dart';
import '../widgets/pdf_preview_iframe.dart';

class _StatusVisual {
  final String label;
  final IconData icon;
  final Color color;
  final Color bgColor;
  final Color borderColor;
  const _StatusVisual(
    this.label,
    this.icon,
    this.color,
    this.bgColor,
    this.borderColor,
  );
}

const _kStatus = <String, _StatusVisual>{
  'pendente': _StatusVisual(
    'Pendentes',
    Icons.hourglass_empty_rounded,
    Color(0xFFD97706),
    Color(0xFFFFF7ED),
    Color(0xFFFED7AA),
  ),
  'aprovado': _StatusVisual(
    'Aprovados',
    Icons.check_circle_outline_rounded,
    Color(0xFF059669),
    Color(0xFFECFDF5),
    Color(0xFFA7F3D0),
  ),
  'bloqueado': _StatusVisual(
    'Bloqueados',
    Icons.block_rounded,
    Color(0xFFDC2626),
    Color(0xFFFEF2F2),
    Color(0xFFFECACA),
  ),
  'atualizacoes': _StatusVisual(
    'Atualizações',
    Icons.autorenew_rounded,
    Color(0xFF2563EB),
    Color(0xFFEFF6FF),
    Color(0xFFBFDBFE),
  ),
  'excluidos': _StatusVisual(
    'Excluídos',
    Icons.person_off_rounded,
    Color(0xFF64748B),
    Color(0xFFF1F5F9),
    Color(0xFFE2E8F0),
  ),
};

enum _MaisAcoesEntregador { editar, documentos, planoTaxa, bloquear }

/// Item da fila de documentos (CNH/CRLV) em `status == pendente`.
class _DocPendentePainel {
  _DocPendentePainel({
    required this.uid,
    required this.tipo,
    required this.veiculoId,
    required this.docRef,
    required this.docData,
  });

  final String uid;
  /// `cnh` ou `crlv`.
  final String tipo;
  final String? veiculoId;
  final DocumentReference<Map<String, dynamic>> docRef;
  final Map<String, dynamic> docData;

  String get chaveUnica => docRef.path;
}

class EntregadoresScreen extends StatefulWidget {
  const EntregadoresScreen({super.key});

  @override
  State<EntregadoresScreen> createState() => _EntregadoresScreenState();
}

class _EntregadoresScreenState extends State<EntregadoresScreen>
    with SingleTickerProviderStateMixin {
  String _tipoUsuarioLogado = 'master';
  List<String> _cidadesDoGerente = [];
  String _busca = '';

  late final TextEditingController _campoBuscaController;
  Timer? _debounceBusca;
  /// Evita clique duplo em aprovar/reprovar na aba Atualizações.
  String? _docPendenteSalvandoPath;

  /// Lista da aba Atualizações vem da Cloud Function (Admin SDK) — evita
  /// `permission-denied` em `collectionGroup` no cliente em produção.
  List<_DocPendentePainel>? _atualizacoesDocsCache;
  String? _atualizacoesFetchErro;
  bool _atualizacoesCarregando = false;
  Timer? _atualizacoesPoll;
  /// Incrementado a cada refresh do cache para notificar o diálogo aberto
  /// (evita polling interno que causava piscar de cards).
  final ValueNotifier<int> _atualizacoesVersao = ValueNotifier<int>(0);
  /// Cache do Future de resolução de URL de documento por `documentPath`.
  /// Evita que rebuilds disparem nova leitura (efeito "piscando" na preview).
  final Map<String, Future<String>> _urlDocResolvidaCache = {};

  static const int _debounceBuscaMs = 350;
  static const int _itensPorPagina = 10;

  final Map<String, int> _paginaPorStatus = {
    'pendente': 0,
    'aprovado': 0,
    'bloqueado': 0,
    'atualizacoes': 0,
    'excluidos': 0,
  };

  static const _statusTabs = [
    'pendente',
    'aprovado',
    'bloqueado',
    'atualizacoes',
    'excluidos',
  ];

  /// Sub-filtro da aba "Bloqueados": todos | admin | pausados | exclusao.
  String _filtroBloqueado = 'todos';

  late final TabController _tabController;

  /// Contagens ao vivo por status (badge nas abas + faixa de KPIs).
  /// `null` = ainda carregando.
  final Map<String, int?> _contagemStatus = {
    'pendente': null,
    'aprovado': null,
    'bloqueado': null,
    'excluidos': null,
  };
  int? _contagemOnline;
  final List<StreamSubscription<dynamic>> _subsContagem = [];

  @override
  void initState() {
    super.initState();
    _campoBuscaController = TextEditingController();
    _tabController = TabController(length: _statusTabs.length, vsync: this);
    _tabController.addListener(_onTabEntregadoresChanged);
    _buscarDadosDoGestor();
    _assinarContagens();
  }

  /// Mantém as contagens por status e a de "online agora" sincronizadas.
  /// Fonte única usada tanto pelos badges das abas quanto pela faixa de KPIs,
  /// evitando abrir streams redundantes em cada widget.
  void _assinarContagens() {
    for (final s in _subsContagem) {
      s.cancel();
    }
    _subsContagem.clear();
    for (final status in const ['pendente', 'aprovado', 'bloqueado', 'excluidos']) {
      final sub = _queryPorStatus(status).snapshots().listen(
        (snap) {
          if (!mounted) return;
          setState(() => _contagemStatus[status] = snap.size);
        },
        onError: (_) {},
      );
      _subsContagem.add(sub);
    }
    Query<Map<String, dynamic>> qOnline = FirebaseFirestore.instance
        .collection('users')
        .where('role', isEqualTo: 'entregador')
        .where('is_online', isEqualTo: true);
    if (_tipoUsuarioLogado == 'master_city' && _cidadesDoGerente.isNotEmpty) {
      qOnline = qOnline.where('cidade', whereIn: _cidadesDoGerente);
    }
    final subOnline = qOnline.snapshots().listen(
      (snap) {
        if (!mounted) return;
        setState(() => _contagemOnline = snap.size);
      },
      onError: (_) {},
    );
    _subsContagem.add(subOnline);
  }

  int get _abaAtualizacoesIndex => _statusTabs.indexOf('atualizacoes');

  void _onTabEntregadoresChanged() {
    if (!mounted) return;
    if (_tabController.index == _abaAtualizacoesIndex) {
      _iniciarPollAtualizacoesPainel();
    } else {
      _pararPollAtualizacoesPainel();
    }
  }

  void _iniciarPollAtualizacoesPainel() {
    _atualizacoesPoll?.cancel();
    _fetchAtualizacoesPendentesPainel();
    _atualizacoesPoll = Timer.periodic(const Duration(seconds: 25), (_) {
      if (mounted && _tabController.index == _abaAtualizacoesIndex) {
        _fetchAtualizacoesPendentesPainel();
      }
    });
  }

  void _pararPollAtualizacoesPainel() {
    _atualizacoesPoll?.cancel();
    _atualizacoesPoll = null;
  }

  Future<void> _fetchAtualizacoesPendentesPainel() async {
    if (!mounted) return;
    setState(() {
      _atualizacoesCarregando = true;
      _atualizacoesFetchErro = null;
    });
    try {
      final r = await callFirebaseFunctionSafe(
        'painelEntregadoresAtualizacoesPendentes',
        timeout: const Duration(seconds: 120),
      );
      final raw = r['items'];
      final list = <_DocPendentePainel>[];
      if (raw is List) {
        for (final e in raw) {
          if (e is! Map) continue;
          final m = Map<String, dynamic>.from(e);
          final path = _str(m['documentPath']).trim();
          final tipo = _str(m['tipoDoc']).trim().toLowerCase();
          final uid = _str(m['uid']).trim();
          final vid = (m['veiculoId'] ?? '').toString().trim();
          final dataRaw = m['data'];
          final data = dataRaw is Map
              ? Map<String, dynamic>.from(dataRaw)
              : <String, dynamic>{};
          if (path.isEmpty || uid.isEmpty) continue;
          if (tipo != 'cnh' && tipo != 'crlv') continue;
          list.add(
            _DocPendentePainel(
              uid: uid,
              tipo: tipo,
              veiculoId: tipo == 'crlv' && vid.isNotEmpty ? vid : null,
              docRef:
                  FirebaseFirestore.instance.doc(path),
              docData: data,
            ),
          );
        }
      }
      if (!mounted) return;
      // Limpa do cache de URL apenas os paths que sumiram (já não precisam
      // mais ser re-resolvidos); mantém os que continuam pendentes para
      // que o FutureBuilder não dispare nova leitura em rebuilds.
      final pathsAtuais = list.map((e) => e.docRef.path).toSet();
      _urlDocResolvidaCache.removeWhere((k, _) => !pathsAtuais.contains(k));
      setState(() {
        _atualizacoesDocsCache = list;
        _atualizacoesCarregando = false;
        _atualizacoesFetchErro = null;
      });
      _atualizacoesVersao.value = _atualizacoesVersao.value + 1;
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _atualizacoesCarregando = false;
        _atualizacoesFetchErro = e.toString();
      });
    }
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabEntregadoresChanged);
    _pararPollAtualizacoesPainel();
    for (final s in _subsContagem) {
      s.cancel();
    }
    _subsContagem.clear();
    _debounceBusca?.cancel();
    _campoBuscaController.dispose();
    _tabController.dispose();
    _atualizacoesVersao.dispose();
    super.dispose();
  }

  void _agendarAtualizacaoBusca() {
    _debounceBusca?.cancel();
    _debounceBusca = Timer(const Duration(milliseconds: _debounceBuscaMs), () {
      if (!mounted) return;
      _aplicarBuscaDoCampo();
    });
  }

  void _aplicarBuscaDoCampo() {
    final t = _campoBuscaController.text.trim().toLowerCase();
    if (_busca == t) return;
    setState(() {
      _busca = t;
      for (final s in _statusTabs) {
        _paginaPorStatus[s] = 0;
      }
    });
  }

  void _limparBusca() {
    _debounceBusca?.cancel();
    _campoBuscaController.clear();
    _aplicarBuscaDoCampo();
  }

  Future<void> _buscarDadosDoGestor() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (doc.exists && mounted) {
        final dados = doc.data()!;
        setState(() {
          _tipoUsuarioLogado = perfilAdministrativo(dados);
          final raw = dados['cidades_gerenciadas'];
          if (raw is List) {
            _cidadesDoGerente = raw
                .map((e) => e == null ? '' : '$e')
                .where((s) => s.isNotEmpty)
                .toList();
          } else {
            _cidadesDoGerente = [];
          }
        });
        // Reassina com o escopo de cidades do gestor já resolvido.
        _assinarContagens();
      }
    } catch (e) {
      debugPrint('Erro ao carregar permissão: $e');
    }
  }

  Query<Map<String, dynamic>> _queryPorStatus(String status) {
    // Excluídos já viraram role=cliente; filtramos pelo marcador de perfil.
    if (status == 'excluidos') {
      Query<Map<String, dynamic>> qx = FirebaseFirestore.instance
          .collection('users')
          .where('entregador_perfil_operacional', isEqualTo: 'perfil_removido');
      if (_tipoUsuarioLogado == 'master_city' && _cidadesDoGerente.isNotEmpty) {
        qx = qx.where('cidade', whereIn: _cidadesDoGerente);
      }
      return qx;
    }
    Query<Map<String, dynamic>> q = FirebaseFirestore.instance
        .collection('users')
        .where('role', isEqualTo: 'entregador');
    if (status == 'bloqueado') {
      q = q.where(
        'entregador_status',
        whereIn: [
          ContaBloqueioLojista.statusLojaBloqueado,
          ContaBloqueioLojista.statusLojaBloqueioTemporario,
        ],
      );
    } else {
      q = q.where('entregador_status', isEqualTo: status);
    }
    if (_tipoUsuarioLogado == 'master_city' && _cidadesDoGerente.isNotEmpty) {
      q = q.where('cidade', whereIn: _cidadesDoGerente);
    }
    return q;
  }

  /// Aplica aprovação do cadastro do entregador — usado pelo fluxo novo em
  /// que clicar em "Aprovar" já abre o modal de plano/taxa e salva tudo de
  /// uma vez. Quando `planoId` é passado, também grava `plano_entregador_id`
  /// junto com a mudança de status, para evitar que o admin esqueça de
  /// configurar a taxa depois.
  Future<void> _aplicarAprovacaoEntregador(
    String entregadorId, {
    String? planoId,
  }) async {
    final update = <String, dynamic>{
      'entregador_status': 'aprovado',
      'motivo_recusa': FieldValue.delete(),
      'motivo_bloqueio': FieldValue.delete(),
      'recusa_cadastro': FieldValue.delete(),
      'status_conta': ContaBloqueioLojista.statusContaActive,
      'block_active': false,
      'block_type': FieldValue.delete(),
      'block_reason': FieldValue.delete(),
      'block_start_at': FieldValue.delete(),
      'block_end_at': FieldValue.delete(),
    };
    if (planoId != null && planoId.trim().isNotEmpty) {
      update['plano_entregador_id'] = planoId.trim();
    }
    await FirebaseFirestore.instance
        .collection('users')
        .doc(entregadorId)
        .update(update);
  }

  Future<void> _alterarStatusEntregador(
    String id,
    String novoStatus, {
    String? motivo,
  }) async {
    final update = <String, dynamic>{'entregador_status': novoStatus};
    if (motivo != null && motivo.isNotEmpty) {
      update['motivo_recusa'] = motivo;
      update['recusa_cadastro'] = true;
    } else if (novoStatus == 'aprovado') {
      update['motivo_recusa'] = FieldValue.delete();
      update['motivo_bloqueio'] = FieldValue.delete();
      update['recusa_cadastro'] = FieldValue.delete();
      update['status_conta'] = ContaBloqueioLojista.statusContaActive;
      update['block_active'] = false;
      update['block_type'] = FieldValue.delete();
      update['block_reason'] = FieldValue.delete();
      update['block_start_at'] = FieldValue.delete();
      update['block_end_at'] = FieldValue.delete();
    }
    try {
      await FirebaseFirestore.instance.collection('users').doc(id).update(update);
      if (!mounted) return;
      mostrarSnackPainel(context,
          mensagem: 'Status alterado para $novoStatus!');
    } on FirebaseException catch (e) {
      if (!mounted) return;
      mostrarSnackPainel(context,
          erro: true,
          mensagem: e.code == 'permission-denied'
              ? 'Sem permissão para esta ação.'
              : 'Erro: ${e.message ?? e.code}');
    } catch (e) {
      if (!mounted) return;
      mostrarSnackPainel(context, erro: true, mensagem: 'Erro: $e');
    }
  }

  Future<void> _desbloquearEntregador({
    required String id,
    required String nome,
    required String motivoDesbloqueioTexto,
    required String motivoDesbloqueioCodigo,
  }) async {
    final admin = FirebaseAuth.instance.currentUser;
    if (admin == null) return;
    final ref = FirebaseFirestore.instance.collection('users').doc(id);
    final batch = FirebaseFirestore.instance.batch();
    batch.update(ref, {
      'entregador_status': 'aprovado',
      'entregador_perfil_operacional': 'ativo',
      'status_conta': ContaBloqueioLojista.statusContaActive,
      'motivo_recusa': FieldValue.delete(),
      'motivo_bloqueio': FieldValue.delete(),
      'motivo_bloqueio_admin_codigo': FieldValue.delete(),
      'recusa_cadastro': FieldValue.delete(),
      'block_active': false,
      'block_type': FieldValue.delete(),
      'block_reason': FieldValue.delete(),
      'block_origin': FieldValue.delete(),
      'block_start_at': FieldValue.delete(),
      'block_end_at': FieldValue.delete(),
      'entregador_exclusao_perfil_solicitada_em': FieldValue.delete(),
      'entregador_exclusao_perfil_em': FieldValue.delete(),
      'entregador_reingresso_bloqueado_ate': FieldValue.delete(),
    });
    batch.set(ref.collection('bloqueios_auditoria').doc(), {
      'admin_id': admin.uid,
      'admin_email': admin.email,
      'applied_at': FieldValue.serverTimestamp(),
      'action': 'unblock',
      'entregador_nome': nome,
      'motivo_desbloqueio': motivoDesbloqueioTexto,
      'motivo_desbloqueio_codigo': motivoDesbloqueioCodigo,
    });
    try {
      await batch.commit();
      if (!mounted) return;
      mostrarSnackPainel(context,
          mensagem: 'Entregador desbloqueado. Auditoria registrada.');
    } on FirebaseException catch (e) {
      if (!mounted) return;
      mostrarSnackPainel(context,
          erro: true,
          mensagem: e.code == 'permission-denied'
              ? 'Sem permissão para esta ação.'
              : 'Erro: ${e.message ?? e.code}');
    } catch (e) {
      if (!mounted) return;
      mostrarSnackPainel(context, erro: true, mensagem: 'Erro: $e');
    }
  }

  void _mostrarModalDesbloqueioEntregador({
    required String id,
    required String nome,
    required Map<String, dynamic> dados,
  }) {
    String? motivoSelecionado;
    final descricaoC = TextEditingController();
    bool salvando = false;

    final motivoBloqueioAtual =
        ContaBloqueioEntregadorHelper.textoMotivoBloqueio(dados);
    final tipoBloqueio =
        ContaBloqueioEntregadorHelper.rotuloTipoBloqueio(dados);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          final opcoes = EntregadorMotivoDesbloqueioAdmin.opcoes;
          final opcaoAtual =
              EntregadorMotivoDesbloqueioAdmin.opcaoPorCodigo(motivoSelecionado);
          final exigeDescricao = opcaoAtual?.exigeDescricao == true;

          return Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 540),
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFECFDF5),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.lock_open_rounded,
                            color: Color(0xFF059669),
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Desbloquear entregador',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFF065F46),
                                ),
                              ),
                              Text(
                                nome,
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 14,
                                  color: PainelAdminTheme.textoSecundario,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Bloqueio atual: $tipoBloqueio',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (motivoBloqueioAtual != null &&
                              motivoBloqueioAtual.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(
                              motivoBloqueioAtual,
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 12,
                                color: PainelAdminTheme.textoSecundario,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Confirme o desbloqueio e informe o motivo. O entregador '
                      'será reativado e receberá notificação no aplicativo.',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        color: PainelAdminTheme.textoSecundario,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Motivo do desbloqueio',
                      style: GoogleFonts.plusJakartaSans(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 280),
                      child: SingleChildScrollView(
                        child: Column(
                          children: [
                            for (final op in opcoes)
                              RadioListTile<String>(
                                value: op.codigo,
                                groupValue: motivoSelecionado,
                                onChanged: salvando
                                    ? null
                                    : (v) => setS(() => motivoSelecionado = v),
                                title: Text(
                                  op.titulo,
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                subtitle: Text(
                                  op.subtitulo,
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 12,
                                    color: PainelAdminTheme.textoSecundario,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    if (exigeDescricao) ...[
                      const SizedBox(height: 8),
                      TextField(
                        controller: descricaoC,
                        maxLines: 3,
                        maxLength: 280,
                        enabled: !salvando,
                        style: GoogleFonts.plusJakartaSans(fontSize: 14),
                        decoration: InputDecoration(
                          labelText: 'Descreva o motivo *',
                          hintText: 'Registro interno e auditoria do painel.',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                              color: Color(0xFF059669),
                              width: 1.5,
                            ),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed:
                              salvando ? null : () => Navigator.pop(ctx),
                          child: Text(
                            'Cancelar',
                            style: GoogleFonts.plusJakartaSans(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        FilledButton.icon(
                          onPressed: salvando
                              ? null
                              : () async {
                                  final codigo = motivoSelecionado;
                                  if (codigo == null) {
                                    mostrarSnackPainel(
                                      ctx,
                                      erro: true,
                                      mensagem:
                                          'Selecione o motivo do desbloqueio.',
                                    );
                                    return;
                                  }
                                  final op =
                                      EntregadorMotivoDesbloqueioAdmin
                                          .opcaoPorCodigo(codigo);
                                  if (op == null) return;
                                  if (op.exigeDescricao &&
                                      descricaoC.text.trim().length < 8) {
                                    mostrarSnackPainel(
                                      ctx,
                                      erro: true,
                                      mensagem:
                                          'Descreva o motivo (mínimo 8 caracteres).',
                                    );
                                    return;
                                  }
                                  final textoMotivo =
                                      EntregadorMotivoDesbloqueioAdmin
                                          .textoMotivoParaAuditoria(
                                    codigo: codigo,
                                    descricaoOutros: descricaoC.text,
                                  );
                                  setS(() => salvando = true);
                                  await _desbloquearEntregador(
                                    id: id,
                                    nome: nome,
                                    motivoDesbloqueioTexto: textoMotivo,
                                    motivoDesbloqueioCodigo: codigo,
                                  );
                                  if (ctx.mounted) Navigator.pop(ctx);
                                },
                          icon: salvando
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.lock_open_rounded, size: 18),
                          label: const Text('Confirmar desbloqueio'),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF059669),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 14,
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
        },
      ),
    ).then((_) => descricaoC.dispose());
  }

  Future<void> _aplicarBloqueioEntregador({
    required String id,
    required String nomeEntregador,
    required String blockType,
    required String blockReason,
    required String motivoBloqueioTexto,
    String? motivoBloqueioCodigoAdmin,
    int? durationDays,
  }) async {
    final admin = FirebaseAuth.instance.currentUser;
    if (admin == null) return;

    Timestamp? endTs;
    if (blockType == ContaBloqueioLojista.blockTemporary &&
        durationDays != null &&
        durationDays > 0) {
      endTs = Timestamp.fromDate(
        DateTime.now().add(Duration(days: durationDays)),
      );
    }

    final ref = FirebaseFirestore.instance.collection('users').doc(id);
    final batch = FirebaseFirestore.instance.batch();
    final statusPainel =
        blockType == ContaBloqueioLojista.blockTemporary
            ? ContaBloqueioLojista.statusLojaBloqueioTemporario
            : ContaBloqueioLojista.statusLojaBloqueado;
    final textoMotivoPainel = motivoBloqueioTexto.trim().isNotEmpty
        ? motivoBloqueioTexto.trim()
        : (blockType == ContaBloqueioLojista.blockFull
            ? 'Pendências financeiras'
            : 'Bloqueio administrativo temporário');
    batch.update(ref, {
      'entregador_status': statusPainel,
      'entregador_perfil_operacional':
          blockType == ContaBloqueioLojista.blockTemporary
              ? 'bloqueado_temporario'
              : 'bloqueado_definitivo',
      'status_conta': ContaBloqueioLojista.statusContaBlocked,
      'motivo_bloqueio': textoMotivoPainel,
      if (motivoBloqueioCodigoAdmin != null &&
          motivoBloqueioCodigoAdmin.trim().isNotEmpty)
        'motivo_bloqueio_admin_codigo': motivoBloqueioCodigoAdmin.trim(),
      'recusa_cadastro': FieldValue.delete(),
      'block_type': blockType,
      'block_reason': blockReason,
      'block_origin': 'admin',
      'block_start_at': FieldValue.serverTimestamp(),
      'block_end_at': endTs,
      'block_active': true,
    });
    batch.set(ref.collection('bloqueios_auditoria').doc(), {
      'admin_id': admin.uid,
      'admin_email': admin.email,
      'applied_at': FieldValue.serverTimestamp(),
      'action': 'block',
      'block_type': blockType,
      'block_reason': blockReason,
      'motivo_bloqueio_texto': textoMotivoPainel,
      if (motivoBloqueioCodigoAdmin != null)
        'motivo_bloqueio_admin_codigo': motivoBloqueioCodigoAdmin,
      'duration_days': durationDays,
      'entregador_nome': nomeEntregador,
    });
    try {
      await batch.commit();
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_tabController.index != 2) {
          _tabController.animateTo(2);
        }
      });
      mostrarSnackPainel(context,
          mensagem:
              'Bloqueio aplicado. O entregador está na aba Bloqueados — use Desbloquear para reverter.');
    } on FirebaseException catch (e) {
      if (!mounted) return;
      mostrarSnackPainel(context,
          erro: true,
          mensagem: e.code == 'permission-denied'
              ? 'Sem permissão para esta ação.'
              : 'Erro: ${e.message ?? e.code}');
    } catch (e) {
      if (!mounted) return;
      mostrarSnackPainel(context, erro: true, mensagem: 'Erro: $e');
    }
  }

  void _mostrarModalBloqueioEntregador(String id, String nomeEntregador) {
    String modo = ContaBloqueioLojista.blockFull;
    final diasC = TextEditingController(text: '7');
    bool salvando = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Dialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF2F2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.block_rounded,
                          color: Color(0xFFDC2626), size: 24),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Bloquear entregador',
                                style: GoogleFonts.plusJakartaSans(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                    color: const Color(0xFF991B1B))),
                            Text(nomeEntregador,
                                style: GoogleFonts.plusJakartaSans(
                                    fontSize: 14,
                                    color: PainelAdminTheme.textoSecundario),
                                overflow: TextOverflow.ellipsis),
                          ]),
                    ),
                  ]),
                  const SizedBox(height: 20),
                  Text('Tipo de bloqueio',
                      style: GoogleFonts.plusJakartaSans(
                          fontWeight: FontWeight.w700, fontSize: 14)),
                  const SizedBox(height: 10),
                  RadioListTile<String>(
                    title: Text('Inadimplência (bloqueio total)',
                        style: GoogleFonts.plusJakartaSans(fontSize: 14)),
                    subtitle: Text(
                        'Na próxima etapa você escolhe o motivo detalhado do bloqueio.',
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            color: PainelAdminTheme.textoSecundario)),
                    value: ContaBloqueioLojista.blockFull,
                    groupValue: modo,
                    onChanged: (v) => setS(() => modo = v ?? modo),
                  ),
                  RadioListTile<String>(
                    title: Text('Temporário',
                        style: GoogleFonts.plusJakartaSans(fontSize: 14)),
                    subtitle: Text(
                        'Bloqueio por dias — após o prazo, a conta pode ser reativada automaticamente.',
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            color: PainelAdminTheme.textoSecundario)),
                    value: ContaBloqueioLojista.blockTemporary,
                    groupValue: modo,
                    onChanged: (v) => setS(() => modo = v ?? modo),
                  ),
                  if (modo == ContaBloqueioLojista.blockTemporary) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: diasC,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'Duração (dias)',
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                    TextButton(
                        onPressed: salvando ? null : () => Navigator.pop(ctx),
                        child: Text('Cancelar',
                            style: GoogleFonts.plusJakartaSans(
                                fontWeight: FontWeight.w600))),
                    const SizedBox(width: 12),
                    FilledButton.icon(
                      onPressed: salvando
                          ? null
                          : () async {
                              if (modo == ContaBloqueioLojista.blockFull) {
                                Navigator.pop(ctx);
                                _mostrarModalMotivoBloqueioEntregador(
                                  id: id,
                                  nomeEntregador: nomeEntregador,
                                );
                                return;
                              }
                              int? dur;
                              dur = int.tryParse(diasC.text.trim());
                              if (dur == null || dur < 1) {
                                mostrarSnackPainel(ctx,
                                    erro: true,
                                    mensagem:
                                        'Informe a duração em dias (número ≥ 1).');
                                return;
                              }
                              setS(() => salvando = true);
                              await _aplicarBloqueioEntregador(
                                id: id,
                                nomeEntregador: nomeEntregador,
                                blockType: modo,
                                blockReason: ContaBloqueioLojista.motivoOutros,
                                motivoBloqueioTexto:
                                    'Bloqueio administrativo temporário ($dur dia${dur == 1 ? '' : 's'}).',
                                durationDays: dur,
                              );
                              if (ctx.mounted) Navigator.pop(ctx);
                            },
                      icon: salvando
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : Icon(
                              modo == ContaBloqueioLojista.blockFull
                                  ? Icons.arrow_forward_rounded
                                  : Icons.block_rounded,
                              size: 18,
                            ),
                      label: Text(
                        modo == ContaBloqueioLojista.blockFull
                            ? 'Continuar'
                            : 'Confirmar bloqueio',
                      ),
                      style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFDC2626),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 14)),
                    ),
                  ]),
                ],
              ),
            ),
          ),
        ),
      ),
    ).then((_) => diasC.dispose());
  }

  void _mostrarModalMotivoBloqueioEntregador({
    required String id,
    required String nomeEntregador,
  }) {
    String? motivoSelecionado;
    final descricaoC = TextEditingController();
    bool salvando = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          final opcoes = EntregadorMotivoBloqueioAdmin.opcoesBloqueioTotal;
          final opcaoAtual = EntregadorMotivoBloqueioAdmin.opcaoPorCodigo(
            motivoSelecionado,
          );
          final exigeDescricao = opcaoAtual?.exigeDescricao == true;

          return Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 540),
              child: Padding(
                padding: const EdgeInsets.all(28),
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
                          child: const Icon(
                            Icons.report_gmailerrorred_outlined,
                            color: Color(0xFFDC2626),
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Motivo do bloqueio',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFF991B1B),
                                ),
                              ),
                              Text(
                                nomeEntregador,
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 14,
                                  color: PainelAdminTheme.textoSecundario,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Selecione o motivo. O entregador verá esta informação no '
                      'painel de entregas e receberá notificação no aplicativo.',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        color: PainelAdminTheme.textoSecundario,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 16),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 340),
                      child: SingleChildScrollView(
                        child: Column(
                          children: [
                            for (final op in opcoes)
                              RadioListTile<String>(
                                value: op.codigo,
                                groupValue: motivoSelecionado,
                                onChanged: salvando
                                    ? null
                                    : (v) => setS(() => motivoSelecionado = v),
                                title: Text(
                                  op.titulo,
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                subtitle: Text(
                                  op.subtitulo,
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 12,
                                    color: PainelAdminTheme.textoSecundario,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    if (exigeDescricao) ...[
                      const SizedBox(height: 8),
                      TextField(
                        controller: descricaoC,
                        maxLines: 3,
                        maxLength: 280,
                        enabled: !salvando,
                        style: GoogleFonts.plusJakartaSans(fontSize: 14),
                        decoration: InputDecoration(
                          labelText: 'Descreva o motivo *',
                          hintText:
                              'Esta mensagem será exibida ao entregador no app.',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                              color: Color(0xFFDC2626),
                              width: 1.5,
                            ),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: salvando
                              ? null
                              : () => Navigator.pop(ctx),
                          child: Text(
                            'Voltar',
                            style: GoogleFonts.plusJakartaSans(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        FilledButton.icon(
                          onPressed: salvando
                              ? null
                              : () async {
                                  final codigo = motivoSelecionado;
                                  if (codigo == null) {
                                    mostrarSnackPainel(
                                      ctx,
                                      erro: true,
                                      mensagem: 'Selecione o motivo do bloqueio.',
                                    );
                                    return;
                                  }
                                  final op = EntregadorMotivoBloqueioAdmin
                                      .opcaoPorCodigo(codigo);
                                  if (op == null) return;
                                  if (op.exigeDescricao &&
                                      descricaoC.text.trim().length < 8) {
                                    mostrarSnackPainel(
                                      ctx,
                                      erro: true,
                                      mensagem:
                                          'Descreva o motivo (mínimo 8 caracteres).',
                                    );
                                    return;
                                  }
                                  final textoMotivo =
                                      EntregadorMotivoBloqueioAdmin
                                          .textoMotivoParaFirestore(
                                    codigo: codigo,
                                    descricaoOutros: descricaoC.text,
                                  );
                                  setS(() => salvando = true);
                                  await _aplicarBloqueioEntregador(
                                    id: id,
                                    nomeEntregador: nomeEntregador,
                                    blockType: ContaBloqueioLojista.blockFull,
                                    blockReason:
                                        EntregadorMotivoBloqueioAdmin
                                            .blockReasonParaFirestore(codigo),
                                    motivoBloqueioTexto: textoMotivo,
                                    motivoBloqueioCodigoAdmin: codigo,
                                  );
                                  if (ctx.mounted) Navigator.pop(ctx);
                                },
                          icon: salvando
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.block_rounded, size: 18),
                          label: const Text('Confirmar bloqueio'),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFFDC2626),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 14,
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
        },
      ),
    ).then((_) => descricaoC.dispose());
  }

  void _mostrarModalRecusaEntregador(String id, String nomeEntregador) {
    final motivoC = TextEditingController();
    bool isSalvando = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Dialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                          color: const Color(0xFFFEF2F2),
                          borderRadius: BorderRadius.circular(12)),
                      child: const Icon(Icons.block_rounded,
                          color: Color(0xFFDC2626), size: 24),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Recusar cadastro',
                                style: GoogleFonts.plusJakartaSans(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                    color: const Color(0xFF991B1B))),
                            Text(nomeEntregador,
                                style: GoogleFonts.plusJakartaSans(
                                    fontSize: 14,
                                    color: PainelAdminTheme.textoSecundario),
                                overflow: TextOverflow.ellipsis),
                          ]),
                    ),
                  ]),
                  const SizedBox(height: 20),
                  Text(
                      'O entregador verá esta mensagem no aplicativo para poder corrigir.',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          color: PainelAdminTheme.textoSecundario,
                          height: 1.4)),
                  const SizedBox(height: 16),
                  TextField(
                    controller: motivoC,
                    maxLines: 3,
                    style: GoogleFonts.plusJakartaSans(fontSize: 14),
                    decoration: InputDecoration(
                      labelText: 'Motivo da recusa',
                      hintText: 'Ex: CNH ilegível, foto do veículo ausente…',
                      hintStyle: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          color: PainelAdminTheme.textoSecundario),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                      focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                              color: Color(0xFFDC2626), width: 1.5)),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: Text('Cancelar',
                            style: GoogleFonts.plusJakartaSans(
                                fontWeight: FontWeight.w600))),
                    const SizedBox(width: 12),
                    FilledButton.icon(
                      onPressed: isSalvando
                          ? null
                          : () async {
                              if (motivoC.text.trim().isEmpty) {
                                mostrarSnackPainel(ctx,
                                    erro: true,
                                    mensagem:
                                        'Você precisa digitar um motivo.');
                                return;
                              }
                              setS(() => isSalvando = true);
                              await _alterarStatusEntregador(id, 'bloqueado',
                                  motivo: motivoC.text.trim());
                              if (ctx.mounted) Navigator.pop(ctx);
                            },
                      icon: isSalvando
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.block_rounded, size: 18),
                      label: const Text('Confirmar recusa'),
                      style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFDC2626),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 14)),
                    ),
                  ]),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PainelAdminTheme.fundoCanvas,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [for (final s in _statusTabs) _buildListaEntregadores(s)],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(32, 28, 32, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: PainelAdminTheme.roxo.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(Icons.delivery_dining_rounded,
                      color: PainelAdminTheme.roxo, size: 28),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Gestão de Entregadores',
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              color: PainelAdminTheme.dashboardInk,
                              letterSpacing: -0.5)),
                      const SizedBox(height: 4),
                      Text(
                          'Aprove motoboys, defina planos e revise CNH/CRLV enviados por entregadores já aprovados (aba Atualizações).',
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 14,
                              color: PainelAdminTheme.textoSecundario,
                              height: 1.4)),
                    ],
                  ),
                ),
                SizedBox(
                  width: 260,
                  height: 42,
                  child: ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _campoBuscaController,
                    builder: (context, value, _) {
                      final temTexto = value.text.isNotEmpty;
                      return TextField(
                        controller: _campoBuscaController,
                        onChanged: (_) => _agendarAtualizacaoBusca(),
                        onSubmitted: (_) {
                          _debounceBusca?.cancel();
                          _aplicarBuscaDoCampo();
                        },
                        style: GoogleFonts.plusJakartaSans(fontSize: 14),
                        decoration: InputDecoration(
                          hintText: 'Buscar nome, cidade ou veículo…',
                          hintStyle: GoogleFonts.plusJakartaSans(
                              fontSize: 13,
                              color: PainelAdminTheme.textoSecundario),
                          prefixIcon: Icon(Icons.search_rounded,
                              size: 20,
                              color: PainelAdminTheme.textoSecundario),
                          suffixIcon: temTexto
                              ? IconButton(
                                  tooltip: 'Limpar busca',
                                  icon: Icon(Icons.close_rounded,
                                      size: 18,
                                      color: PainelAdminTheme.textoSecundario),
                                  splashRadius: 18,
                                  onPressed: _limparBusca,
                                )
                              : null,
                          filled: true,
                          fillColor: const Color(0xFFF8FAFC),
                          contentPadding: EdgeInsets.zero,
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide:
                                  const BorderSide(color: Color(0xFFE2E8F0))),
                          enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide:
                                  const BorderSide(color: Color(0xFFE2E8F0))),
                          focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                  color: PainelAdminTheme.roxo, width: 1.5)),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            _buildKpisStrip(),
            const SizedBox(height: 18),
            TabBar(
              controller: _tabController,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              labelPadding: const EdgeInsets.symmetric(horizontal: 16),
              indicatorColor: PainelAdminTheme.laranja,
              indicatorWeight: 3,
              dividerColor: Colors.transparent,
              labelStyle: GoogleFonts.plusJakartaSans(
                  fontWeight: FontWeight.w700, fontSize: 13),
              unselectedLabelStyle: GoogleFonts.plusJakartaSans(
                  fontWeight: FontWeight.w500, fontSize: 13),
              labelColor: PainelAdminTheme.roxo,
              unselectedLabelColor: PainelAdminTheme.textoSecundario,
              tabs: [for (final s in _statusTabs) _buildTab(s)],
            ),
          ],
        ),
      ),
    );
  }

  /// Faixa de KPIs operacionais no topo (padrão "Data-Dense Dashboard").
  Widget _buildKpisStrip() {
    return Row(
      children: [
        _kpiCard(
          'Pendentes',
          _contagemStatus['pendente'],
          Icons.hourglass_empty_rounded,
          const Color(0xFFD97706),
          const Color(0xFFFFF7ED),
        ),
        const SizedBox(width: 12),
        _kpiCard(
          'Aprovados',
          _contagemStatus['aprovado'],
          Icons.check_circle_outline_rounded,
          const Color(0xFF059669),
          const Color(0xFFECFDF5),
        ),
        const SizedBox(width: 12),
        _kpiCard(
          'Online agora',
          _contagemOnline,
          Icons.bolt_rounded,
          PainelAdminTheme.roxo,
          const Color(0xFFF3E8FD),
          destaque: true,
        ),
        const SizedBox(width: 12),
        _kpiCard(
          'Bloqueados',
          _contagemStatus['bloqueado'],
          Icons.block_rounded,
          const Color(0xFFDC2626),
          const Color(0xFFFEF2F2),
        ),
        const SizedBox(width: 12),
        _kpiCard(
          'Excluídos',
          _contagemStatus['excluidos'],
          Icons.person_off_rounded,
          const Color(0xFF64748B),
          const Color(0xFFF1F5F9),
        ),
      ],
    );
  }

  Widget _kpiCard(
    String label,
    int? valor,
    IconData icon,
    Color cor,
    Color bg, {
    bool destaque = false,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: destaque ? bg : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: destaque
                ? cor.withValues(alpha: 0.25)
                : PainelAdminTheme.dashboardBorder,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(icon, size: 21, color: cor),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    valor == null ? '—' : '$valor',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: PainelAdminTheme.dashboardInk,
                      height: 1.05,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: PainelAdminTheme.textoSecundario,
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

  Widget _buildTab(String status) {
    final info = _kStatus[status]!;
    final int? contagem = status == 'atualizacoes'
        ? _atualizacoesDocsCache?.length
        : _contagemStatus[status];
    return Tab(
      height: 52,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(info.icon, size: 18),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              info.label,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
          if (contagem != null && contagem > 0) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: info.bgColor,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: info.borderColor),
              ),
              child: Text(
                contagem > 99 ? '99+' : '$contagem',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: info.color,
                  height: 1.1,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildListaEntregadores(String status) {
    if (status == 'atualizacoes') {
      return _buildAtualizacoesPendentes();
    }
    final info = _kStatus[status]!;
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _queryPorStatus(status).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          // Sessão expirada: aciona o fluxo profissional global e não mostra
          // o erro técnico cru ([cloud_firestore/permission-denied]).
          if (SessaoPainelService.ehErroSessaoExpirada(snapshot.error)) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              SessaoPainelService.tratarSessaoExpirada();
            });
            return Center(
              child: CircularProgressIndicator(
                  color: PainelAdminTheme.roxo, strokeWidth: 2.5),
            );
          }
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Não foi possível carregar os entregadores.\n'
                'Verifique sua conexão e tente novamente.',
                textAlign: TextAlign.center,
                style: GoogleFonts.plusJakartaSans(
                  color: const Color(0xFFDC2626),
                  fontSize: 14,
                ),
              ),
            ),
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildListaSkeleton();
        }
        final docs = snapshot.data?.docs ?? [];
        final filtrados = _busca.isEmpty
            ? docs
            : docs.where((d) {
                try {
                  final data = d.data();
                  final nome = _str(data['nome']).toLowerCase();
                  final cidade = _str(data['cidade']).toLowerCase();
                  final veiculo = _str(data['veiculoTipo']).toLowerCase();
                  final placa = _placaExibicao(data).toLowerCase();
                  return nome.contains(_busca) ||
                      cidade.contains(_busca) ||
                      veiculo.contains(_busca) ||
                      placa.contains(_busca);
                } catch (_) {
                  return false;
                }
              }).toList();

        // Sub-filtro da aba Bloqueados (Pausados / Exclusão / Admin).
        final subFiltrados = status == 'bloqueado'
            ? filtrados.where((d) => _passaFiltroBloqueado(d.data())).toList()
            : filtrados;

        final Widget? barraFiltros =
            status == 'bloqueado' ? _buildFiltrosBloqueado(docs) : null;

        if (subFiltrados.isEmpty) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (barraFiltros != null) barraFiltros,
              Expanded(child: _buildEmptyState(status, info)),
            ],
          );
        }

        final totalItens = subFiltrados.length;
        final totalPaginas = math.max(
          1,
          ((totalItens - 1) ~/ _itensPorPagina) + 1,
        );
        final paginaArmazenada = _paginaPorStatus[status] ?? 0;
        final paginaAtual = paginaArmazenada.clamp(0, totalPaginas - 1);
        final inicio = paginaAtual * _itensPorPagina;
        final fim = math.min(inicio + _itensPorPagina, totalItens);
        final paginaItens = subFiltrados.sublist(inicio, fim);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (barraFiltros != null) barraFiltros,
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(32, 24, 32, 16),
                itemCount: paginaItens.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (_, i) => status == 'excluidos'
                    ? _buildEntregadorExcluidoCard(paginaItens[i], info)
                    : _buildEntregadorCard(paginaItens[i], status, info),
              ),
            ),
            _buildBarraPaginacaoEntregadores(
              status: status,
              totalItens: totalItens,
              paginaAtual: paginaAtual,
              totalPaginas: totalPaginas,
            ),
          ],
        );
      },
    );
  }

  bool _passaFiltroBloqueado(Map<String, dynamic> d) {
    switch (_filtroBloqueado) {
      case 'pausados':
        return ContaBloqueioEntregadorHelper.ehPausaIniciadaPeloEntregador(d);
      case 'exclusao':
        return ContaBloqueioEntregadorHelper.ehExclusaoPerfilSolicitada(d);
      case 'admin':
        return !ContaBloqueioEntregadorHelper.ehPausaIniciadaPeloEntregador(d) &&
            !ContaBloqueioEntregadorHelper.ehExclusaoPerfilSolicitada(d);
      default:
        return true;
    }
  }

  Widget _buildFiltrosBloqueado(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    int nPausados = 0;
    int nExclusao = 0;
    int nAdmin = 0;
    for (final d in docs) {
      final m = d.data();
      if (ContaBloqueioEntregadorHelper.ehExclusaoPerfilSolicitada(m)) {
        nExclusao++;
      } else if (ContaBloqueioEntregadorHelper
          .ehPausaIniciadaPeloEntregador(m)) {
        nPausados++;
      } else {
        nAdmin++;
      }
    }
    final opcoes = <List<dynamic>>[
      ['todos', 'Todos', docs.length],
      ['admin', 'Bloqueio admin', nAdmin],
      ['pausados', 'Pausados', nPausados],
      ['exclusao', 'Exclusão solicitada', nExclusao],
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 16, 32, 0),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final o in opcoes)
            _chipFiltroBloqueado(
              valor: o[0] as String,
              rotulo: o[1] as String,
              contagem: o[2] as int,
            ),
        ],
      ),
    );
  }

  Widget _chipFiltroBloqueado({
    required String valor,
    required String rotulo,
    required int contagem,
  }) {
    final selecionado = _filtroBloqueado == valor;
    return ChoiceChip(
      selected: selecionado,
      onSelected: (_) {
        setState(() {
          _filtroBloqueado = valor;
          _paginaPorStatus['bloqueado'] = 0;
        });
      },
      showCheckmark: false,
      label: Text('$rotulo ($contagem)'),
      labelStyle: GoogleFonts.plusJakartaSans(
        fontSize: 12.5,
        fontWeight: FontWeight.w600,
        color: selecionado
            ? PainelAdminTheme.roxo
            : PainelAdminTheme.textoSecundario,
      ),
      selectedColor: PainelAdminTheme.roxo.withValues(alpha: 0.12),
      backgroundColor: const Color(0xFFF1F5F9),
      side: BorderSide(
        color: selecionado
            ? PainelAdminTheme.roxo.withValues(alpha: 0.45)
            : const Color(0xFFE2E8F0),
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    );
  }

  /// Card read-only para entregadores cujo perfil já foi removido (viram cliente).
  Widget _buildEntregadorExcluidoCard(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
    _StatusVisual info,
  ) {
    final dados = doc.data();
    final nome = _str(dados['nome'], 'Entregador sem nome');
    final cidade = _str(dados['cidade'], '—');
    final removidoRaw = dados['entregador_perfil_removido_em'];
    final DateTime? removido =
        removidoRaw is Timestamp ? removidoRaw.toDate() : null;
    final removidoTxt = removido == null
        ? 'Data não registrada'
        : 'Perfil removido em ${removido.day.toString().padLeft(2, '0')}/${removido.month.toString().padLeft(2, '0')}/${removido.year}';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE6EAF0)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: info.bgColor,
                borderRadius: BorderRadius.circular(11),
                border: Border.all(color: info.borderColor),
              ),
              child: Icon(info.icon, color: info.color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    nome,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      color: PainelAdminTheme.dashboardInk,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$cidade · Conta segue ativa como cliente',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12.5,
                      color: PainelAdminTheme.textoSecundario,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: info.bgColor,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: info.borderColor),
              ),
              child: Text(
                removidoTxt,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: info.color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _definirPaginaEntregador(String status, int novaPagina, int totalPaginas) {
    final maxP = totalPaginas > 0 ? totalPaginas - 1 : 0;
    setState(() => _paginaPorStatus[status] = novaPagina.clamp(0, maxP));
  }

  Widget _buildBarraPaginacaoEntregadores({
    required String status,
    required int totalItens,
    required int paginaAtual,
    required int totalPaginas,
  }) {
    final inicioExib = totalItens == 0 ? 0 : paginaAtual * _itensPorPagina + 1;
    final fimExib = math.min(
      (paginaAtual + 1) * _itensPorPagina,
      totalItens,
    );

    return Material(
      color: Colors.white,
      elevation: 0,
      child: Container(
        padding: const EdgeInsets.fromLTRB(32, 14, 88, 20),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(
            top: BorderSide(color: Color(0xFFE2E8F0)),
          ),
          boxShadow: [
            BoxShadow(
              color: Color(0x0D000000),
              blurRadius: 10,
              offset: Offset(0, -2),
            ),
          ],
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final narrow = constraints.maxWidth < 720;
            final botoesNumeros = _buildBotoesNumerosPagina(
              paginaAtual: paginaAtual,
              totalPaginas: totalPaginas,
              onSelecionar: (p) =>
                  _definirPaginaEntregador(status, p, totalPaginas),
            );

            final resumo = Text(
              totalItens == 0
                  ? 'Nenhum registro'
                  : status == 'atualizacoes'
                      ? 'Mostrando $inicioExib–$fimExib de $totalItens ${totalItens == 1 ? 'solicitação' : 'solicitações'}'
                      : 'Mostrando $inicioExib–$fimExib de $totalItens ${totalItens == 1 ? 'entregador' : 'entregadores'}',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: PainelAdminTheme.textoSecundario,
              ),
            );

            final controles = Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _pagIconBtn(
                  tooltip: 'Primeira página',
                  icon: Icons.first_page_rounded,
                  enabled: paginaAtual > 0,
                  onTap: () => _definirPaginaEntregador(status, 0, totalPaginas),
                ),
                _pagIconBtn(
                  tooltip: 'Página anterior',
                  icon: Icons.chevron_left_rounded,
                  enabled: paginaAtual > 0,
                  onTap: () => _definirPaginaEntregador(
                      status, paginaAtual - 1, totalPaginas),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: botoesNumeros,
                  ),
                ),
                _pagIconBtn(
                  tooltip: 'Próxima página',
                  icon: Icons.chevron_right_rounded,
                  enabled: paginaAtual < totalPaginas - 1,
                  onTap: () => _definirPaginaEntregador(
                      status, paginaAtual + 1, totalPaginas),
                ),
                _pagIconBtn(
                  tooltip: 'Última página',
                  icon: Icons.last_page_rounded,
                  enabled: paginaAtual < totalPaginas - 1,
                  onTap: () => _definirPaginaEntregador(
                    status,
                    totalPaginas - 1,
                    totalPaginas,
                  ),
                ),
              ],
            );

            final chipPagina = Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Text(
                'Página ${paginaAtual + 1} de $totalPaginas',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: PainelAdminTheme.dashboardInk,
                  letterSpacing: 0.2,
                ),
              ),
            );

            if (narrow) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  resumo,
                  const SizedBox(height: 12),
                  Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      chipPagina,
                      controles,
                    ],
                  ),
                ],
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(child: resumo),
                chipPagina,
                const SizedBox(width: 20),
                controles,
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _pagIconBtn({
    required String tooltip,
    required IconData icon,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(
            icon,
            size: 22,
            color: enabled
                ? PainelAdminTheme.roxo
                : PainelAdminTheme.textoSecundario.withValues(alpha: 0.35),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildBotoesNumerosPagina({
    required int paginaAtual,
    required int totalPaginas,
    required ValueChanged<int> onSelecionar,
  }) {
    if (totalPaginas <= 1) {
      return [];
    }

    final List<int?> sequencia;
    if (totalPaginas <= 7) {
      sequencia = List<int?>.generate(totalPaginas, (i) => i);
    } else {
      final set = <int>{
        0,
        totalPaginas - 1,
        paginaAtual,
        paginaAtual - 1,
        paginaAtual + 1,
      };
      set.removeWhere((e) => e < 0 || e >= totalPaginas);
      final sorted = set.toList()..sort();
      sequencia = [];
      for (var i = 0; i < sorted.length; i++) {
        if (i > 0 && sorted[i] - sorted[i - 1] > 1) {
          sequencia.add(null);
        }
        sequencia.add(sorted[i]);
      }
    }

    final out = <Widget>[];
    for (final idx in sequencia) {
      if (idx == null) {
        out.add(
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              '…',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: PainelAdminTheme.textoSecundario,
              ),
            ),
          ),
        );
        continue;
      }
      final selecionada = idx == paginaAtual;
      out.add(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Material(
            color: selecionada
                ? PainelAdminTheme.roxo.withValues(alpha: 0.12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              onTap: selecionada ? null : () => onSelecionar(idx),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                constraints: const BoxConstraints(minWidth: 36),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                alignment: Alignment.center,
                child: Text(
                  '${idx + 1}',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    fontWeight:
                        selecionada ? FontWeight.w800 : FontWeight.w600,
                    color: selecionada
                        ? PainelAdminTheme.roxo
                        : PainelAdminTheme.dashboardInk,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }
    return out;
  }

  /// Skeleton (shimmer) de cards enquanto a lista carrega — substitui o
  /// spinner solto por uma prévia que mantém a estrutura visual da tela.
  Widget _buildListaSkeleton() {
    return Shimmer.fromColors(
      baseColor: const Color(0xFFE2E8F0),
      highlightColor: const Color(0xFFF1F5F9),
      period: const Duration(milliseconds: 1200),
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(28, 24, 28, 28),
        physics: const NeverScrollableScrollPhysics(),
        itemCount: 5,
        separatorBuilder: (_, __) => const SizedBox(height: 14),
        itemBuilder: (_, __) => Container(
          height: 96,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        height: 16,
                        width: 200,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Container(
                        height: 12,
                        width: 140,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Container(
                  height: 32,
                  width: 96,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(String status, _StatusVisual info) {
    final hasSearch = _busca.isNotEmpty;
    final titulo = hasSearch
        ? 'Nenhum resultado para "$_busca"'
        : status == 'atualizacoes'
            ? 'Nada na fila de atualizações.'
            : status == 'excluidos'
                ? 'Nenhum perfil de entregador excluído.'
                : status == 'bloqueado'
                    ? 'Nenhum entregador nesta categoria.'
                    : 'Nenhum entregador ${info.label.toLowerCase()} encontrado.';
    final subtitulo = hasSearch
        ? 'Tente outro termo de busca.'
        : status == 'pendente'
            ? 'Novos entregadores aparecerão aqui ao solicitar cadastro.'
            : status == 'atualizacoes'
                ? 'CNH ou CRLV enviados por entregadores já aprovados aparecem aqui quando estiverem em análise.'
                : status == 'excluidos'
                    ? 'Quando um perfil de entregador é removido após o prazo de 30 dias, ele aparece aqui (a conta segue ativa como cliente).'
                    : 'Nenhum registro nesta categoria no momento.';
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration:
                BoxDecoration(color: info.bgColor, shape: BoxShape.circle),
            child: Icon(hasSearch ? Icons.search_off_rounded : info.icon,
                size: 48, color: info.color.withValues(alpha: 0.6)),
          ),
          const SizedBox(height: 20),
          Text(
            titulo,
            textAlign: TextAlign.center,
            style: GoogleFonts.plusJakartaSans(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: PainelAdminTheme.dashboardInk),
          ),
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Text(
              subtitulo,
              textAlign: TextAlign.center,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  height: 1.45,
                  color: PainelAdminTheme.textoSecundario),
            ),
          ),
          if (hasSearch) ...[
            const SizedBox(height: 18),
            OutlinedButton.icon(
              onPressed: _limparBusca,
              icon: const Icon(Icons.close_rounded, size: 18),
              label: Text(
                'Limpar busca',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 13, fontWeight: FontWeight.w700),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: PainelAdminTheme.roxo,
                side: BorderSide(
                    color: PainelAdminTheme.roxo.withValues(alpha: 0.4)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  int _millisFirestore(dynamic t) {
    if (t is Timestamp) return t.millisecondsSinceEpoch;
    if (t is int) return t;
    if (t is num) return t.toInt();
    if (t is String) {
      final d = DateTime.tryParse(t);
      if (d != null) return d.millisecondsSinceEpoch;
    }
    if (t is Map) {
      final s = t['_seconds'];
      if (s is int) return s * 1000;
    }
    return 0;
  }

  String _rotuloTipoVeiculoCodigo(dynamic codigo) {
    final v = _str(codigo).toLowerCase();
    if (v == 'moto') return 'Moto';
    if (v == 'carro') return 'Carro';
    if (v == 'bike') return 'Bicicleta';
    final s = _str(codigo);
    return s.isEmpty ? '' : s;
  }

  Future<
      ({
        Map<String, Map<String, dynamic>> users,
        Map<String, String> rotulosVeiculo,
      })> _carregarContextoDocsPendentes(List<_DocPendentePainel> rows) async {
    final uids = rows.map((e) => e.uid).toSet();
    final users = <String, Map<String, dynamic>>{};
    await Future.wait(uids.map((uid) async {
      final s =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();
      if (s.exists && s.data() != null) users[uid] = s.data()!;
    }));

    final veiculoKeys = <String>{};
    for (final r in rows) {
      if (r.tipo == 'crlv' && (r.veiculoId ?? '').isNotEmpty) {
        veiculoKeys.add('${r.uid}|${r.veiculoId}');
      }
    }
    final rotulosVeiculo = <String, String>{};
    await Future.wait(veiculoKeys.map((k) async {
      final seg = k.split('|');
      if (seg.length != 2) return;
      final uid = seg[0];
      final vid = seg[1];
      final vs = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('veiculos')
          .doc(vid)
          .get();
      if (!vs.exists || vs.data() == null) return;
      final d = vs.data()!;
      final partes = <String>[
        _rotuloTipoVeiculoCodigo(d['tipo']),
        _str(d['modelo']),
        _str(d['placa']).toUpperCase(),
      ].where((e) => e.trim().isNotEmpty).toList();
      rotulosVeiculo[k] = partes.isEmpty ? 'Veículo $vid' : partes.join(' · ');
    }));

    return (users: users, rotulosVeiculo: rotulosVeiculo);
  }

  Future<void> _aprovarDocumentoPendente(_DocPendentePainel row) async {
    final url = _str(row.docData['url']).trim();
    if (url.isEmpty) {
      mostrarSnackPainel(context,
          erro: true, mensagem: 'Documento sem URL — não é possível aprovar.');
      return;
    }
    final admin = FirebaseAuth.instance.currentUser;
    if (admin == null) return;

    setState(() => _docPendenteSalvandoPath = row.chaveUnica);
    _atualizacoesVersao.value = _atualizacoesVersao.value + 1;
    try {
      final batch = FirebaseFirestore.instance.batch();
      batch.update(row.docRef, {
        'status': 'aprovado',
        'motivo_reprovacao': FieldValue.delete(),
        'atualizado_em': FieldValue.serverTimestamp(),
        'revisado_por_uid': admin.uid,
        'revisado_por_email': admin.email,
      });

      final userRef =
          FirebaseFirestore.instance.collection('users').doc(row.uid);
      if (row.tipo == 'cnh') {
        batch.update(userRef, {'url_doc_pessoal': url});
      } else if (row.tipo == 'crlv' && (row.veiculoId ?? '').isNotEmpty) {
        final userSnap = await userRef.get();
        final ativoId = _str(userSnap.data()?['veiculo_ativo_id']);
        if (ativoId.isNotEmpty && ativoId == row.veiculoId) {
          batch.update(userRef, {'url_crlv': url});
        }
      }

      await batch.commit();
      if (!mounted) return;
      mostrarSnackPainel(context, mensagem: 'Documento aprovado.');
      await _fetchAtualizacoesPendentesPainel();
    } on FirebaseException catch (e) {
      if (!mounted) return;
      mostrarSnackPainel(context,
          erro: true,
          mensagem: e.code == 'permission-denied'
              ? 'Sem permissão para esta ação.'
              : 'Erro: ${e.message ?? e.code}');
    } catch (e) {
      if (!mounted) return;
      mostrarSnackPainel(context, erro: true, mensagem: 'Erro: $e');
    } finally {
      if (mounted) {
        setState(() => _docPendenteSalvandoPath = null);
        _atualizacoesVersao.value = _atualizacoesVersao.value + 1;
      }
    }
  }

  Future<void> _reprovarDocumentoPendente(
    _DocPendentePainel row,
    String motivo,
  ) async {
    final admin = FirebaseAuth.instance.currentUser;
    if (admin == null) return;
    setState(() => _docPendenteSalvandoPath = row.chaveUnica);
    _atualizacoesVersao.value = _atualizacoesVersao.value + 1;
    try {
      await row.docRef.update({
        'status': 'reprovado',
        'motivo_reprovacao': motivo.trim(),
        'atualizado_em': FieldValue.serverTimestamp(),
        'revisado_por_uid': admin.uid,
        'revisado_por_email': admin.email,
      });
      if (!mounted) return;
      mostrarSnackPainel(context, mensagem: 'Documento reprovado.');
      await _fetchAtualizacoesPendentesPainel();
    } on FirebaseException catch (e) {
      if (!mounted) return;
      mostrarSnackPainel(context,
          erro: true,
          mensagem: e.code == 'permission-denied'
              ? 'Sem permissão para esta ação.'
              : 'Erro: ${e.message ?? e.code}');
    } catch (e) {
      if (!mounted) return;
      mostrarSnackPainel(context, erro: true, mensagem: 'Erro: $e');
    } finally {
      if (mounted) {
        setState(() => _docPendenteSalvandoPath = null);
        _atualizacoesVersao.value = _atualizacoesVersao.value + 1;
      }
    }
  }

  void _mostrarDialogoReprovarDocumento(_DocPendentePainel row) {
    final motivoC = TextEditingController();
    var salvando = false;

    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text('Reprovar documento',
              style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'O entregador verá o motivo no aplicativo.',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 13, color: PainelAdminTheme.textoSecundario),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: motivoC,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: 'Motivo',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: salvando ? null : () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: salvando
                  ? null
                  : () async {
                      if (motivoC.text.trim().isEmpty) {
                        mostrarSnackPainel(ctx,
                            erro: true, mensagem: 'Informe o motivo.');
                        return;
                      }
                      setS(() => salvando = true);
                      await _reprovarDocumentoPendente(row, motivoC.text);
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
              child: salvando
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Confirmar'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAtualizacoesPendentes() {
    final info = _kStatus['atualizacoes']!;
    if (_atualizacoesFetchErro != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Erro ao carregar atualizações.\n$_atualizacoesFetchErro',
                textAlign: TextAlign.center,
                style: GoogleFonts.plusJakartaSans(
                  color: const Color(0xFFDC2626),
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _atualizacoesCarregando
                    ? null
                    : () => _fetchAtualizacoesPendentesPainel(),
                icon: const Icon(Icons.refresh_rounded, size: 20),
                label: const Text('Tentar novamente'),
              ),
            ],
          ),
        ),
      );
    }
    if (_atualizacoesDocsCache == null && _atualizacoesCarregando) {
      return Center(
        child: CircularProgressIndicator(
            color: PainelAdminTheme.roxo, strokeWidth: 2.5),
      );
    }

    final brutos = List<_DocPendentePainel>.from(_atualizacoesDocsCache ?? []);
    brutos.sort((a, b) => _millisFirestore(b.docData['atualizado_em'])
        .compareTo(_millisFirestore(a.docData['atualizado_em'])));

    final keyVal = brutos.map((e) => e.chaveUnica).join('|');
    return FutureBuilder<
        ({
          Map<String, Map<String, dynamic>> users,
          Map<String, String> rotulosVeiculo,
        })>(
      key: ValueKey(keyVal),
      future: brutos.isEmpty
          ? Future.value((
              users: <String, Map<String, dynamic>>{},
              rotulosVeiculo: <String, String>{},
            ))
          : _carregarContextoDocsPendentes(brutos),
      builder: (context, fut) {
        if (fut.connectionState == ConnectionState.waiting && !fut.hasData) {
          return Center(
            child: CircularProgressIndicator(
                color: PainelAdminTheme.roxo, strokeWidth: 2.5),
          );
        }
        final ctxData = fut.data;
        final users = ctxData?.users ?? {};
        final rotulosVeiculo = ctxData?.rotulosVeiculo ?? {};

        // Agrupa docs pendentes por entregador (1 card por pessoa).
        final agrupado = <String, List<_DocPendentePainel>>{};
        for (final row in brutos) {
          if (users[row.uid] == null) continue;
          (agrupado[row.uid] ??= []).add(row);
        }

        final entregadores = agrupado.entries.toList()
          ..sort((a, b) {
            final ta = a.value
                .map((d) => _millisFirestore(d.docData['atualizado_em']))
                .fold<int>(0, (p, e) => e > p ? e : p);
            final tb = b.value
                .map((d) => _millisFirestore(d.docData['atualizado_em']))
                .fold<int>(0, (p, e) => e > p ? e : p);
            return tb.compareTo(ta);
          });

        final filtrados = _busca.isEmpty
            ? entregadores
            : entregadores.where((e) {
                final u = users[e.key];
                if (u == null) return false;
                final nome = _str(u['nome']).toLowerCase();
                final cidade = _str(u['cidade']).toLowerCase();
                final tiposDoc = e.value
                    .map((d) => d.tipo.toLowerCase())
                    .join(' ');
                final rv = e.value
                    .where((d) =>
                        d.tipo == 'crlv' && (d.veiculoId ?? '').isNotEmpty)
                    .map((d) =>
                        _str(rotulosVeiculo['${d.uid}|${d.veiculoId}'])
                            .toLowerCase())
                    .join(' ');
                return nome.contains(_busca) ||
                    cidade.contains(_busca) ||
                    tiposDoc.contains(_busca) ||
                    rv.contains(_busca);
              }).toList();

        if (filtrados.isEmpty) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(32, 12, 32, 0),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: _atualizacoesCarregando
                        ? null
                        : () => _fetchAtualizacoesPendentesPainel(),
                    icon: _atualizacoesCarregando
                        ? SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: PainelAdminTheme.roxo,
                            ),
                          )
                        : const Icon(Icons.refresh_rounded, size: 20),
                    label: const Text('Atualizar lista'),
                  ),
                ),
              ),
              Expanded(child: _buildEmptyState('atualizacoes', info)),
            ],
          );
        }

        final totalItens = filtrados.length;
        final totalPaginas = math.max(
          1,
          ((totalItens - 1) ~/ _itensPorPagina) + 1,
        );
        final paginaArmazenada = _paginaPorStatus['atualizacoes'] ?? 0;
        final paginaAtual = paginaArmazenada.clamp(0, totalPaginas - 1);
        final inicio = paginaAtual * _itensPorPagina;
        final fim = math.min(inicio + _itensPorPagina, totalItens);
        final paginaItens = filtrados.sublist(inicio, fim);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(32, 12, 32, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: info.bgColor,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: info.borderColor),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.info_outline_rounded,
                              color: info.color, size: 22),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Somente entregadores com cadastro já aprovado. '
                              'Novos cadastros continuam na aba Pendentes. '
                              'Lista atualizada pelo servidor a cada ~25 s ou ao tocar em Atualizar.',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 13,
                                height: 1.45,
                                color: PainelAdminTheme.dashboardInk,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  TextButton.icon(
                    onPressed: _atualizacoesCarregando
                        ? null
                        : () => _fetchAtualizacoesPendentesPainel(),
                    icon: _atualizacoesCarregando
                        ? SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: PainelAdminTheme.roxo,
                            ),
                          )
                        : const Icon(Icons.refresh_rounded, size: 20),
                    label: const Text('Atualizar'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(32, 12, 32, 16),
                itemCount: paginaItens.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) {
                  final entry = paginaItens[i];
                  return _buildCardEntregadorAtualizacao(
                    uid: entry.key,
                    docs: entry.value,
                    userData: users[entry.key] ?? {},
                    rotulosVeiculo: rotulosVeiculo,
                  );
                },
              ),
            ),
            _buildBarraPaginacaoEntregadores(
              status: 'atualizacoes',
              totalItens: totalItens,
              paginaAtual: paginaAtual,
              totalPaginas: totalPaginas,
            ),
          ],
        );
      },
    );
  }

  Widget _buildCardEntregadorAtualizacao({
    required String uid,
    required List<_DocPendentePainel> docs,
    required Map<String, dynamic> userData,
    required Map<String, String> rotulosVeiculo,
  }) {
    final nome = _str(userData['nome'], 'Sem nome');
    final cidade = _str(userData['cidade']);
    final fotoUrl = _str(userData['foto_url']);
    final veiculoTipo = _str(userData['veiculoTipo']).trim();
    final placa = _placaExibicao(userData);

    final tipos = <String>{};
    for (final d in docs) {
      tipos.add(d.tipo == 'cnh' ? 'CNH' : 'CRLV');
    }
    final resumoTipos = tipos.toList()..sort();

    final metaParts = <String>[
      if (cidade.isNotEmpty) cidade,
      if (veiculoTipo.isNotEmpty) veiculoTipo,
      if (placa != 'S/ Placa') placa,
    ];

    final salvandoAqui = docs.any(
      (d) => _docPendenteSalvandoPath == d.chaveUnica,
    );

    return Material(
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: salvandoAqui
            ? null
            : () => _abrirDialogoAtualizacoesEntregador(
                  uid: uid,
                  userData: userData,
                  rotulosVeiculo: rotulosVeiculo,
                ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                  image: fotoUrl.isNotEmpty
                      ? DecorationImage(
                          image: NetworkImage(fotoUrl),
                          fit: BoxFit.cover,
                        )
                      : null,
                ),
                alignment: Alignment.center,
                child: fotoUrl.isEmpty
                    ? Icon(
                        Icons.delivery_dining_rounded,
                        size: 22,
                        color: PainelAdminTheme.textoSecundario,
                      )
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      nome,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: PainelAdminTheme.dashboardInk,
                      ),
                    ),
                    if (metaParts.isNotEmpty) const SizedBox(height: 2),
                    if (metaParts.isNotEmpty)
                      Text(
                        metaParts.join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          color: PainelAdminTheme.textoSecundario,
                          height: 1.3,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              _chipContagemPendencias(
                total: docs.length,
                tipos: resumoTipos,
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right_rounded,
                size: 22,
                color: PainelAdminTheme.textoSecundario,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chipContagemPendencias({
    required int total,
    required List<String> tipos,
  }) {
    final rotulo = total == 1
        ? '1 documento · ${tipos.join(' + ')}'
        : '$total documentos · ${tipos.join(' + ')}';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFFED7AA)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              color: Color(0xFFF59E0B),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            rotulo,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: const Color(0xFFB45309),
              height: 1.1,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _abrirDialogoAtualizacoesEntregador({
    required String uid,
    required Map<String, dynamic> userData,
    required Map<String, String> rotulosVeiculo,
  }) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogCtx) {
        return _DialogoAtualizacoesEntregador(
          uid: uid,
          userData: userData,
          rotulosVeiculo: rotulosVeiculo,
          versao: _atualizacoesVersao,
          buildCardDoc: (row) => _buildCardAtualizacaoDocumento(
            row,
            userData,
            rotulosVeiculo,
          ),
          lerPendenciasAtuais: () {
            return (_atualizacoesDocsCache ?? [])
                .where((d) => d.uid == uid)
                .toList()
              ..sort((a, b) => _millisFirestore(b.docData['atualizado_em'])
                  .compareTo(_millisFirestore(a.docData['atualizado_em'])));
          },
        );
      },
    );
  }

  Widget _buildCardAtualizacaoDocumento(
    _DocPendentePainel row,
    Map<String, dynamic> user,
    Map<String, String> rotulosVeiculo,
  ) {
    final nome = _str(user['nome'], 'Sem nome');
    final cidade = _str(user['cidade']);
    final salvando = _docPendenteSalvandoPath == row.chaveUnica;
    final tipoLabel = row.tipo == 'cnh' ? 'CNH' : 'CRLV';
    String subt;
    if (row.tipo == 'crlv' && row.veiculoId != null) {
      subt = rotulosVeiculo['${row.uid}|${row.veiculoId}'] ??
          'Veículo ${row.veiculoId}';
    } else {
      subt = 'Documento pessoal';
    }
    final rawUrl = _str(row.docData['url']);
    final urlFuture = _urlDocResolvidaCache.putIfAbsent(
      row.docRef.path,
      () => _resolverUrlDocumento(rawUrl),
    );

    final metaParts = <String>[
      if (cidade.isNotEmpty) cidade,
      tipoLabel,
      subt,
    ];

    return Material(
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: FutureBuilder<String>(
          future: urlFuture,
          builder: (context, snap) {
            final url = (snap.data ?? '').trim();
            final carregando = snap.connectionState == ConnectionState.waiting;
            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _buildThumbAtualizacao(
                  url: url,
                  carregando: carregando,
                  tipoLabel: tipoLabel,
                  nome: nome,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Text(
                              nome,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w700,
                                color: PainelAdminTheme.dashboardInk,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          _pillEmAnalise(),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        metaParts.join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          color: PainelAdminTheme.textoSecundario,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 10),
                      _buildAcoesAtualizacao(
                        row: row,
                        url: url,
                        salvando: salvando,
                        carregando: carregando,
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _pillEmAnalise() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFFED7AA)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              color: Color(0xFFF59E0B),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            'Em análise',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: const Color(0xFFB45309),
              height: 1.1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThumbAtualizacao({
    required String url,
    required bool carregando,
    required String tipoLabel,
    required String nome,
  }) {
    const double w = 84;
    const double h = 84;

    BoxDecoration frame() => BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        );

    if (carregando) {
      return Container(
        width: w,
        height: h,
        decoration: frame(),
        alignment: Alignment.center,
        child: const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    if (url.isEmpty) {
      return Container(
        width: w,
        height: h,
        decoration: frame(),
        alignment: Alignment.center,
        child: Icon(
          Icons.image_not_supported_outlined,
          size: 26,
          color: PainelAdminTheme.textoSecundario,
        ),
      );
    }

    if (_ehPdf(url)) {
      return InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () async {
          final u = Uri.tryParse(url);
          if (u == null) return;
          await launchUrl(u, mode: LaunchMode.externalApplication);
        },
        child: Container(
          width: w,
          height: h,
          decoration: frame(),
          alignment: Alignment.center,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.picture_as_pdf_rounded,
                size: 30,
                color: const Color(0xFFDC2626),
              ),
              const SizedBox(height: 2),
              Text(
                'PDF',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: PainelAdminTheme.textoSecundario,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => _mostrarImagemAmpliada(url, '$tipoLabel — $nome'),
      child: Container(
        width: w,
        height: h,
        decoration: frame(),
        clipBehavior: Clip.antiAlias,
        child: Image.network(
          url,
          fit: BoxFit.cover,
          webHtmlElementStrategy:
              kIsWeb ? WebHtmlElementStrategy.prefer : WebHtmlElementStrategy.never,
          loadingBuilder: (_, child, p) => p == null
              ? child
              : const Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
          errorBuilder: (_, __, ___) => Icon(
            Icons.broken_image_outlined,
            size: 26,
            color: PainelAdminTheme.textoSecundario,
          ),
        ),
      ),
    );
  }

  Widget _buildAcoesAtualizacao({
    required _DocPendentePainel row,
    required String url,
    required bool salvando,
    required bool carregando,
  }) {
    final temUrl = url.isNotEmpty;
    final desabilitado = salvando || carregando;
    final verde = const Color(0xFF059669);
    final vermelho = const Color(0xFFDC2626);

    ButtonStyle styleBase({required Color fg, Color? border}) =>
        OutlinedButton.styleFrom(
          foregroundColor: fg,
          side: BorderSide(color: border ?? fg.withValues(alpha: 0.25)),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          minimumSize: const Size(0, 32),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
          textStyle: GoogleFonts.plusJakartaSans(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        );

    return Wrap(
      spacing: 8,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        OutlinedButton.icon(
          onPressed: !temUrl || desabilitado
              ? null
              : () async {
                  final u = Uri.tryParse(url);
                  if (u == null) return;
                  if (!await launchUrl(u,
                      mode: LaunchMode.externalApplication)) {
                    if (context.mounted) {
                      mostrarSnackPainel(context,
                          erro: true,
                          mensagem: 'Não foi possível abrir o link.');
                    }
                  }
                },
          icon: const Icon(Icons.open_in_new_rounded, size: 15),
          label: const Text('Abrir em nova aba'),
          style: styleBase(
            fg: PainelAdminTheme.dashboardInk,
            border: const Color(0xFFCBD5E1),
          ),
        ),
        FilledButton.icon(
          onPressed:
              desabilitado ? null : () => _aprovarDocumentoPendente(row),
          icon: salvando
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.check_rounded, size: 15),
          label: const Text('Aprovar'),
          style: FilledButton.styleFrom(
            backgroundColor: verde,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            minimumSize: const Size(0, 32),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
            textStyle: GoogleFonts.plusJakartaSans(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
        OutlinedButton.icon(
          onPressed: desabilitado
              ? null
              : () => _mostrarDialogoReprovarDocumento(row),
          icon: const Icon(Icons.close_rounded, size: 15),
          label: const Text('Reprovar'),
          style: styleBase(fg: vermelho, border: const Color(0xFFFECACA)),
        ),
      ],
    );
  }

  String _str(dynamic v, [String fallback = '']) {
    if (v == null) return fallback;
    if (v is String) return v;
    try {
      return v.toString();
    } catch (_) {
      return fallback;
    }
  }

  String _urlFotoVeiculo(Map<String, dynamic> d) {
    final a = _str(d['url_foto_veículo']);
    if (a.isNotEmpty) return a;
    return _str(d['url_foto_veiculo']);
  }

  /// Placa salva no app como `placa_veiculo`; painel antigo lia só `placa`.
  String _placaExibicao(Map<String, dynamic> dados) {
    for (final key in ['placa_veiculo', 'placa', 'placaVeiculo']) {
      final s = _str(dados[key]).trim();
      if (s.isNotEmpty) return s.toUpperCase();
    }
    return 'S/ Placa';
  }

  Future<String> _resolverUrlDocumento(String rawUrl) async {
    final url = rawUrl.trim();
    if (url.isEmpty) return '';
    if (url.startsWith('http://') || url.startsWith('https://')) return url;
    try {
      if (url.startsWith('gs://')) {
        return await FirebaseStorage.instance.refFromURL(url).getDownloadURL();
      }
      final path = url.startsWith('/') ? url.substring(1) : url;
      return await FirebaseStorage.instance.ref(path).getDownloadURL();
    } catch (_) {
      // Mantém o valor original para o fallback de erro visual no card.
      return url;
    }
  }

  Widget _buildEntregadorCard(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
    String status,
    _StatusVisual info,
  ) {
    final dados = doc.data();
    final nome = _str(dados['nome'], 'Entregador sem nome');
    final cidade = _str(dados['cidade'], '—');
    final veiculo = _str(dados['veiculoTipo'], 'Moto');
    final placa = _placaExibicao(dados);
    final planoId = dados['plano_entregador_id'];
    final fotoUrl = _str(dados['foto_url']);
    final motivoRecusa = _str(dados['motivo_recusa']);
    final motivoBloqueio = _str(dados['motivo_bloqueio']);
    final bloqOp =
        ContaBloqueioEntregadorHelper.estaBloqueadoParaOperacoes(dados);
    final fimTemp = ContaBloqueioEntregadorHelper.dataFimBloqueio(dados);
    final chipBloqueio = ContaBloqueioEntregadorHelper.rotuloTipoBloqueio(dados);
    final inicioBloq = ContaBloqueioEntregadorHelper.dataInicioBloqueio(dados);
    final diasExclusao =
        ContaBloqueioEntregadorHelper.diasRestantesExclusaoPerfil(dados);
    final exclusaoPerfil =
        ContaBloqueioEntregadorHelper.ehExclusaoPerfilSolicitada(dados);

    final bool temMotivoRecusa = motivoRecusa.isNotEmpty &&
        (status == 'bloqueado' ||
            ContaBloqueioEntregadorHelper
                .entregadorRecusadoSomenteCorrecaoCadastro(dados));

    final List<Widget> acoes = <Widget>[];
    if ((status == 'bloqueado' || status == 'aprovado') &&
        bloqOp &&
        ContaBloqueioEntregadorHelper.adminPodeDesbloquear(dados)) {
      acoes.add(_acaoCompacta(
        icone: Icons.lock_open_rounded,
        rotulo: 'Desbloquear',
        cor: const Color(0xFF059669),
        preenchido: true,
        onTap: () => _mostrarModalDesbloqueioEntregador(
          id: doc.id,
          nome: nome,
          dados: dados,
        ),
      ));
    }
    if (status == 'pendente') {
      acoes.addAll([
        _acaoCompacta(
          icone: Icons.description_outlined,
          rotulo: 'Documentos',
          cor: const Color(0xFF3B82F6),
          onTap: () => _mostrarDocumentosModal(dados),
        ),
        _acaoCompacta(
          icone: Icons.check_circle_outline_rounded,
          rotulo: 'Aprovar',
          cor: const Color(0xFF059669),
          preenchido: true,
          onTap: () => _atribuirPlanoModal(
            doc.id,
            nome,
            planoId?.toString(),
            cidade,
            veiculo,
            modoAprovar: true,
          ),
        ),
        _acaoCompacta(
          icone: Icons.close_rounded,
          rotulo: 'Recusar',
          cor: const Color(0xFFDC2626),
          onTap: () => _mostrarModalRecusaEntregador(doc.id, nome),
        ),
      ]);
    } else {
      acoes.add(_buildMaisAcoesEntregadorMenu(
        doc: doc,
        dados: dados,
        nomeEntregador: nome,
        planoId: planoId,
        cidade: cidade,
        veiculo: veiculo,
        incluirPlanoTaxaEBloquear: status == 'aprovado' && !bloqOp,
      ));
    }

    final Color borderHighlight = status == 'pendente'
        ? info.borderColor.withValues(alpha: 0.75)
        : const Color(0xFFE6EAF0);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderHighlight),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.025),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: LayoutBuilder(
          builder: (ctx, c) {
            final bool compacto = c.maxWidth < 780;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: info.bgColor,
                        borderRadius: BorderRadius.circular(11),
                        border: Border.all(color: info.borderColor),
                        image: fotoUrl.isNotEmpty
                            ? DecorationImage(
                                image: NetworkImage(fotoUrl),
                                fit: BoxFit.cover,
                              )
                            : null,
                      ),
                      child: fotoUrl.isEmpty
                          ? Icon(
                              Icons.delivery_dining_rounded,
                              color: info.color,
                              size: 20,
                            )
                          : null,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  nome,
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 14.5,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: -0.1,
                                    color: PainelAdminTheme.dashboardInk,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                ),
                              ),
                              const SizedBox(width: 8),
                              _statusPillCompacto(info),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 12,
                            runSpacing: 2,
                            children: [
                              _metaChip(
                                Icons.location_on_outlined,
                                cidade.toUpperCase(),
                              ),
                              _metaChip(
                                Icons.two_wheeler_outlined,
                                '$veiculo · $placa',
                              ),
                              if (status == 'aprovado')
                                _metaChip(
                                  Icons.receipt_long_outlined,
                                  planoId != null ? 'Plano ativo' : 'Sem plano',
                                  highlight: planoId == null,
                                ),
                              if (bloqOp)
                                _metaChip(
                                  Icons.block_rounded,
                                  'Bloqueado',
                                  highlight: true,
                                ),
                              _metaChip(
                                Icons.info_outline_rounded,
                                chipBloqueio,
                                highlight: exclusaoPerfil,
                              ),
                              if (inicioBloq != null)
                                _metaChip(
                                  Icons.play_arrow_outlined,
                                  'Início ${inicioBloq.day.toString().padLeft(2, '0')}/${inicioBloq.month.toString().padLeft(2, '0')}/${inicioBloq.year}',
                                ),
                              if (fimTemp != null)
                                _metaChip(
                                  Icons.event_outlined,
                                  'Até ${fimTemp.day.toString().padLeft(2, '0')}/${fimTemp.month.toString().padLeft(2, '0')}/${fimTemp.year}',
                                ),
                              if (exclusaoPerfil && diasExclusao != null)
                                _metaChip(
                                  Icons.timer_outlined,
                                  diasExclusao > 0
                                      ? '$diasExclusao dia${diasExclusao == 1 ? '' : 's'} p/ exclusão'
                                      : 'Exclusão pendente',
                                  highlight: true,
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (!compacto) ...[
                      const SizedBox(width: 12),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: _intercalar(acoes, const SizedBox(width: 6)),
                      ),
                    ],
                  ],
                ),
                if (compacto) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: acoes,
                  ),
                ],
                if (temMotivoRecusa) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF2F2),
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(color: const Color(0xFFFECACA)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.info_outline_rounded,
                            size: 14, color: Color(0xFFDC2626)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            motivoRecusa,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 11.5,
                              color: const Color(0xFF991B1B),
                              height: 1.35,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (bloqOp &&
                    motivoBloqueio.isNotEmpty &&
                    !temMotivoRecusa) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF7ED),
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(color: const Color(0xFFFDE68A)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.notes_rounded,
                            size: 14, color: Color(0xFFB45309)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            motivoBloqueio,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 11.5,
                              color: const Color(0xFF92400E),
                              height: 1.35,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  /// Pill de status compacto (substitui a pill maior do card antigo).
  Widget _statusPillCompacto(_StatusVisual info) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
      decoration: BoxDecoration(
        color: info.bgColor,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: info.borderColor),
      ),
      child: Text(
        info.label,
        style: GoogleFonts.plusJakartaSans(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.15,
          color: info.color,
        ),
      ),
    );
  }

  /// Botão de ação compacto usado na linha do card de entregador.
  /// Substitui as pílulas de 130x34 por um botão denso (altura 30).
  Widget _acaoCompacta({
    required IconData icone,
    required String rotulo,
    required Color cor,
    required VoidCallback onTap,
    bool preenchido = false,
  }) {
    final estiloBase = ButtonStyle(
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 11),
      ),
      visualDensity: VisualDensity.compact,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
      ),
      minimumSize: const WidgetStatePropertyAll(Size(0, 30)),
      textStyle: WidgetStatePropertyAll(
        GoogleFonts.plusJakartaSans(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.1,
        ),
      ),
    );
    final icone16 = Icon(icone, size: 14);
    return SizedBox(
      height: 30,
      child: preenchido
          ? FilledButton.icon(
              onPressed: onTap,
              icon: icone16,
              label: Text(rotulo),
              style: estiloBase.copyWith(
                backgroundColor: WidgetStatePropertyAll(cor),
                foregroundColor: const WidgetStatePropertyAll(Colors.white),
              ),
            )
          : OutlinedButton.icon(
              onPressed: onTap,
              icon: icone16,
              label: Text(rotulo),
              style: estiloBase.copyWith(
                foregroundColor: WidgetStatePropertyAll(cor),
                side: WidgetStatePropertyAll(
                  BorderSide(color: cor.withValues(alpha: 0.38)),
                ),
              ),
            ),
    );
  }

  List<Widget> _intercalar(List<Widget> items, Widget separator) {
    if (items.length <= 1) return items;
    final out = <Widget>[];
    for (var i = 0; i < items.length; i++) {
      out.add(items[i]);
      if (i < items.length - 1) out.add(separator);
    }
    return out;
  }

  Widget _buildMaisAcoesEntregadorMenu({
    required QueryDocumentSnapshot doc,
    required Map<String, dynamic> dados,
    required String nomeEntregador,
    required dynamic planoId,
    required String cidade,
    required String veiculo,
    required bool incluirPlanoTaxaEBloquear,
  }) {
    final textStyle = GoogleFonts.plusJakartaSans(
      fontSize: 14,
      fontWeight: FontWeight.w600,
      color: PainelAdminTheme.dashboardInk,
    );
    return PopupMenuButton<_MaisAcoesEntregador>(
      tooltip: 'Mais ações',
      offset: const Offset(0, 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      color: Colors.white,
      elevation: 10,
      shadowColor: Colors.black.withValues(alpha: 0.12),
      surfaceTintColor: Colors.transparent,
      onSelected: (acao) {
        switch (acao) {
          case _MaisAcoesEntregador.editar:
            showEntregadorEditarDialog(context, entregadorId: doc.id);
            break;
          case _MaisAcoesEntregador.documentos:
            _mostrarDocumentosModal(dados);
            break;
          case _MaisAcoesEntregador.planoTaxa:
            _atribuirPlanoModal(
              doc.id,
              nomeEntregador,
              planoId?.toString(),
              cidade,
              veiculo,
            );
            break;
          case _MaisAcoesEntregador.bloquear:
            _mostrarModalBloqueioEntregador(doc.id, nomeEntregador);
            break;
        }
      },
      itemBuilder: (context) {
        final entries = <PopupMenuEntry<_MaisAcoesEntregador>>[
          PopupMenuItem<_MaisAcoesEntregador>(
            value: _MaisAcoesEntregador.editar,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                Icon(Icons.edit_rounded,
                    size: 20, color: PainelAdminTheme.roxo),
                const SizedBox(width: 12),
                Text('Editar', style: textStyle),
              ],
            ),
          ),
          PopupMenuItem<_MaisAcoesEntregador>(
            value: _MaisAcoesEntregador.documentos,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                const Icon(Icons.description_outlined,
                    size: 20, color: Color(0xFF3B82F6)),
                const SizedBox(width: 12),
                Text('Documentos', style: textStyle),
              ],
            ),
          ),
        ];
        if (incluirPlanoTaxaEBloquear) {
          entries.add(const PopupMenuDivider(height: 1));
          entries.add(
            PopupMenuItem<_MaisAcoesEntregador>(
              value: _MaisAcoesEntregador.planoTaxa,
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  Icon(Icons.tune_rounded,
                      size: 20, color: PainelAdminTheme.roxo),
                  const SizedBox(width: 12),
                  Text('Plano/Taxa', style: textStyle),
                ],
              ),
            ),
          );
          entries.add(
            PopupMenuItem<_MaisAcoesEntregador>(
              value: _MaisAcoesEntregador.bloquear,
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  const Icon(Icons.block_rounded,
                      size: 20, color: Color(0xFFDC2626)),
                  const SizedBox(width: 12),
                  Text('Bloquear', style: textStyle),
                ],
              ),
            ),
          );
        }
        return entries;
      },
      child: Container(
        width: 30,
        height: 30,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: const Icon(
          Icons.more_horiz_rounded,
          size: 18,
          color: Color(0xFF475569),
        ),
      ),
    );
  }

  Widget _metaChip(IconData icon, String text, {bool highlight = false}) {
    final c = highlight
        ? const Color(0xFFD97706)
        : PainelAdminTheme.textoSecundario;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 13, color: c),
      const SizedBox(width: 4),
      Text(text,
          style: GoogleFonts.plusJakartaSans(
              fontSize: 11.5,
              color: c,
              letterSpacing: 0.1,
              fontWeight: highlight ? FontWeight.w700 : FontWeight.w600)),
    ]);
  }

  bool _ehPdf(String url) {
    final u = url.trim().toLowerCase();
    if (u.isEmpty) return false;
    // URLs do Firebase Storage costumam ter `.pdf` antes de `?alt=media`.
    if (u.contains('.pdf')) return true;
    final path = Uri.tryParse(url)?.path.toLowerCase() ?? '';
    return path.endsWith('.pdf');
  }

  void _mostrarImagemAmpliada(String url, String titulo) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog.fullscreen(
        backgroundColor: Colors.black.withValues(alpha: 0.92),
        child: Stack(children: [
          InteractiveViewer(
            panEnabled: true,
            scaleEnabled: true,
            minScale: 0.1,
            maxScale: 8,
            boundaryMargin: const EdgeInsets.all(500),
            child: Center(
              child: Image.network(url,
                  fit: BoxFit.contain,
                  webHtmlElementStrategy: kIsWeb
                      ? WebHtmlElementStrategy.prefer
                      : WebHtmlElementStrategy.never,
                  loadingBuilder: (_, child, p) => p == null
                      ? child
                      : const Center(
                          child: CircularProgressIndicator(
                              color: Colors.white))),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 24, vertical: 16),
              color: Colors.black54,
              child: Row(children: [
                Expanded(
                    child: Text(titulo,
                        style: GoogleFonts.plusJakartaSans(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 16))),
                IconButton(
                    icon: const Icon(Icons.close_rounded,
                        color: Colors.white, size: 26),
                    onPressed: () => Navigator.pop(ctx)),
              ]),
            ),
          ),
          Positioned(
            bottom: 20,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(20)),
                child: Text(
                    'Roda do mouse ou pinça para zoom — arraste para mover',
                    style: GoogleFonts.plusJakartaSans(
                        color: Colors.white70, fontSize: 12)),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  static const _docPreviewAltura = 200.0;

  void _mostrarDocumentosModal(Map<String, dynamic> dados) {
    final nome = _str(dados['nome'], 'Entregador sem nome');
    final docPessoalFuture =
        _resolverUrlDocumento(_str(dados['url_doc_pessoal']));
    final crlvFuture = _resolverUrlDocumento(_str(dados['url_crlv']));
    final fotoVeiculoFuture = _resolverUrlDocumento(_urlFotoVeiculo(dados));
    final selfieFuture =
        _resolverUrlDocumento(_str(dados['url_selfie_entregador']));
    final selfieTravada = dados['selfie_bloqueada'] == true;

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720, maxHeight: 650),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(28, 24, 16, 16),
                child: Row(children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                        color: const Color(0xFFEFF6FF),
                        borderRadius: BorderRadius.circular(12)),
                    child: const Icon(Icons.folder_open_rounded,
                        color: Color(0xFF3B82F6), size: 24),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Documentos',
                              style: GoogleFonts.plusJakartaSans(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: PainelAdminTheme.dashboardInk)),
                          Text(nome,
                              style: GoogleFonts.plusJakartaSans(
                                  fontSize: 13,
                                  color:
                                      PainelAdminTheme.textoSecundario)),
                        ]),
                  ),
                  IconButton(
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close_rounded),
                      tooltip: 'Fechar'),
                ]),
              ),
              const Divider(height: 1),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(28, 20, 28, 28),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.touch_app_outlined,
                                size: 18,
                                color: PainelAdminTheme.roxo.withValues(alpha: 0.85),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Imagens: clique para ampliar. PDFs: pré-visualização abaixo ou nova aba / tela cheia.',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 12.5,
                                    height: 1.45,
                                    color: PainelAdminTheme.textoSecundario,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                        _buildDocAsync(
                          selfieTravada
                              ? 'Selfie de verificação (travada — foto de perfil)'
                              : 'Selfie de verificação (câmera do entregador)',
                          selfieFuture,
                        ),
                        _buildDocAsync(
                          'Documento pessoal (CNH/RG)',
                          docPessoalFuture,
                        ),
                        _buildDocAsync(
                          'CRLV / documento do veículo',
                          crlvFuture,
                        ),
                        _buildDocAsync('Foto do veículo', fotoVeiculoFuture),
                      ]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDocAsync(String titulo, Future<String> urlFuture) {
    return FutureBuilder<String>(
      future: urlFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titulo,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                    color: PainelAdminTheme.dashboardInk,
                  ),
                ),
                const SizedBox(height: 10),
                _docCardShell(
                  child: SizedBox(
                    height: _docPreviewAltura,
                    child: Center(
                      child: SizedBox(
                        width: 26,
                        height: 26,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: PainelAdminTheme.roxo,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        }
        return _buildDoc(titulo, snapshot.data?.trim() ?? '');
      },
    );
  }

  Widget _buildDoc(String titulo, String url) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            titulo,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
              color: PainelAdminTheme.dashboardInk,
            ),
          ),
          const SizedBox(height: 10),
          if (url.isEmpty)
            _docCardShell(
              child: Row(
                children: [
                  Icon(
                    Icons.hide_image_outlined,
                    size: 22,
                    color: PainelAdminTheme.textoSecundario.withValues(alpha: 0.9),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Documento não enviado.',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        fontStyle: FontStyle.italic,
                        color: PainelAdminTheme.textoSecundario,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else if (_ehPdf(url))
            _docCardShell(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: PainelAdminTheme.roxo.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.picture_as_pdf_rounded,
                          size: 32,
                          color: PainelAdminTheme.roxo,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Arquivo PDF',
                              style: GoogleFonts.plusJakartaSans(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                                color: PainelAdminTheme.dashboardInk,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Pré-visualização embutida (navegador). Use nova aba ou tela cheia se preferir.',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 12,
                                height: 1.4,
                                color: PainelAdminTheme.textoSecundario,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Tela cheia',
                        icon: Icon(
                          Icons.fullscreen_rounded,
                          color: PainelAdminTheme.roxo,
                        ),
                        onPressed: () => showPdfFullscreenDialog(
                          context,
                          url,
                          titulo,
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () async {
                          if (!await launchUrl(
                            Uri.parse(url),
                            mode: LaunchMode.externalApplication,
                          )) {
                            if (mounted) {
                              mostrarSnackPainel(
                                context,
                                erro: true,
                                mensagem: 'Não foi possível abrir o PDF.',
                              );
                            }
                          }
                        },
                        icon: Icon(
                          Icons.open_in_new_rounded,
                          size: 18,
                          color: PainelAdminTheme.roxo,
                        ),
                        label: Text(
                          'Nova aba',
                          style: GoogleFonts.plusJakartaSans(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            color: PainelAdminTheme.roxo,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  buildPdfPreview(url, height: 360),
                  Align(
                    alignment: Alignment.center,
                    child: TextButton(
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.only(top: 6),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: () async {
                        final uri = Uri.parse(
                          'https://docs.google.com/viewer?url=${Uri.encodeComponent(url)}&embedded=true',
                        );
                        if (!await launchUrl(
                          uri,
                          mode: LaunchMode.externalApplication,
                        )) {
                          if (mounted) {
                            mostrarSnackPainel(
                              context,
                              erro: true,
                              mensagem: 'Não foi possível abrir o visualizador.',
                            );
                          }
                        }
                      },
                      child: Text(
                        'Se não carregar, abrir com visualizador Google',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 11.5,
                          color: PainelAdminTheme.textoSecundario,
                          decoration: TextDecoration.underline,
                          decorationColor: PainelAdminTheme.textoSecundario,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => _mostrarImagemAmpliada(url, titulo),
                borderRadius: BorderRadius.circular(14),
                child: MouseRegion(
                  cursor: SystemMouseCursors.zoomIn,
                  child: _docCardShell(
                    padding: EdgeInsets.zero,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(13),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Container(
                            width: double.infinity,
                            height: _docPreviewAltura,
                            color: const Color(0xFFF1F5F9),
                            alignment: Alignment.center,
                            child: Image.network(
                              url,
                              fit: BoxFit.contain,
                              webHtmlElementStrategy: kIsWeb
                                  ? WebHtmlElementStrategy.prefer
                                  : WebHtmlElementStrategy.never,
                              filterQuality: FilterQuality.medium,
                              loadingBuilder: (_, child, progress) {
                                if (progress == null) return child;
                                return SizedBox(
                                  height: _docPreviewAltura,
                                  child: Center(
                                    child: SizedBox(
                                      width: 28,
                                      height: 28,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.5,
                                        color: PainelAdminTheme.roxo,
                                      ),
                                    ),
                                  ),
                                );
                              },
                              errorBuilder: (_, _, _) => SizedBox(
                                height: _docPreviewAltura,
                                child: Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.broken_image_outlined,
                                        color: PainelAdminTheme.textoSecundario,
                                        size: 36,
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        'Erro ao carregar imagem',
                                        style: GoogleFonts.plusJakartaSans(
                                          fontSize: 12,
                                          color: PainelAdminTheme.textoSecundario,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            bottom: 10,
                            right: 10,
                            child: Material(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(20),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.zoom_in_rounded,
                                      color: Colors.white,
                                      size: 16,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Ampliar',
                                      style: GoogleFonts.plusJakartaSans(
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
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
            ),
        ],
      ),
    );
  }

  Widget _docCardShell({
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(18),
  }) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }

  void _atribuirPlanoModal(
    String entregadorId,
    String nomeEntregador,
    String? planoAtualId,
    String cidadeOrigem,
    String veiculoTipo, {
    // Quando `true`, o diálogo é usado no fluxo de APROVAÇÃO do cadastro:
    // salvar aplica `entregador_status: aprovado` + faxina dos campos de
    // recusa/bloqueio + `plano_entregador_id`. Também muda textos e botões.
    bool modoAprovar = false,
  }) {
    String? planoSelecionado = planoAtualId;
    bool isLoading = false;

    String cidadeFiltro = cidadeOrigem.trim().toLowerCase();
    if (cidadeFiltro.isEmpty) cidadeFiltro = 'todas';
    final cidadesBusca = <String>['todas'];
    if (cidadeFiltro != 'todas' && !cidadesBusca.contains(cidadeFiltro)) {
      cidadesBusca.add(cidadeFiltro);
    }

    final veiculoTrim = veiculoTipo.trim();
    final veiculoFormatado = veiculoTrim.isEmpty
        ? 'Moto'
        : (veiculoTrim[0].toUpperCase() +
            veiculoTrim.substring(1).toLowerCase());

    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Dialog(
          backgroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 22, 12, 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: (modoAprovar
                                  ? const Color(0xFF059669)
                                  : PainelAdminTheme.roxo)
                              .withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: (modoAprovar
                                    ? const Color(0xFF059669)
                                    : PainelAdminTheme.roxo)
                                .withValues(alpha: 0.2),
                          ),
                        ),
                        child: Icon(
                          modoAprovar
                              ? Icons.verified_rounded
                              : Icons.tune_rounded,
                          color: modoAprovar
                              ? const Color(0xFF059669)
                              : PainelAdminTheme.roxo,
                          size: 26,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              modoAprovar
                                  ? 'Aprovar entregador'
                                  : 'Definir plano',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 19,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.3,
                                color: PainelAdminTheme.dashboardInk,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              modoAprovar
                                  ? '$nomeEntregador · escolha o plano de comissão'
                                  : nomeEntregador,
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 13.5,
                                height: 1.35,
                                fontWeight: FontWeight.w500,
                                color: PainelAdminTheme.textoSecundario,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Fechar',
                        onPressed: () => Navigator.pop(ctx),
                        icon: Icon(
                          Icons.close_rounded,
                          color: PainelAdminTheme.textoSecundario,
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: Color(0xFFE2E8F0)),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 11,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.location_on_outlined,
                              size: 18,
                              color: PainelAdminTheme.roxo.withValues(alpha: 0.9),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                cidadeOrigem.isNotEmpty
                                    ? cidadeOrigem.toUpperCase()
                                    : 'Todas as cidades',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  height: 1.35,
                                  color: PainelAdminTheme.dashboardInk,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 11,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.two_wheeler_outlined,
                              size: 18,
                              color: const Color(0xFF059669),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              'Veículo: $veiculoFormatado',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: PainelAdminTheme.dashboardInk,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                        stream: FirebaseFirestore.instance
                            .collection('planos_taxas')
                            .where('publico', isEqualTo: 'entregador')
                            .where('cidade', whereIn: cidadesBusca)
                            .snapshots(),
                        builder: (_, snap) {
                          if (snap.connectionState ==
                              ConnectionState.waiting) {
                            return Container(
                              height: 120,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: const Color(0xFFE2E8F0),
                                ),
                              ),
                              child: SizedBox(
                                width: 28,
                                height: 28,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: PainelAdminTheme.roxo,
                                ),
                              ),
                            );
                          }
                          final planosDocs = snap.data?.docs ?? [];
                          final planosValidos = planosDocs.where((doc) {
                            final p = doc.data();
                            final vPlano = _str(p['veiculo'], 'Todos');
                            return vPlano == veiculoFormatado || vPlano == 'Todos';
                          }).toList();

                          if (planosValidos.isEmpty) {
                            return Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(18),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFFBEB),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: const Color(0xFFFDE68A),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.stretch,
                                children: [
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Icon(
                                        Icons.info_outline_rounded,
                                        size: 22,
                                        color: const Color(0xFFD97706),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          modoAprovar
                                              ? 'Nenhum plano de comissão disponível para esta cidade e veículo. Você pode aprovar o cadastro agora e configurar o plano depois em Aprovados → Plano/Taxa, ou cadastrar o plano antes em Configurações → Planos.'
                                              : 'Não há planos para esta cidade e tipo de veículo. Cadastre em Configurações → planos (público: entregador) ou ajuste o cadastro.',
                                          style: GoogleFonts.plusJakartaSans(
                                            fontSize: 13,
                                            height: 1.45,
                                            color: const Color(0xFF92400E),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (modoAprovar) ...[
                                    const SizedBox(height: 14),
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: FilledButton.icon(
                                        onPressed: isLoading
                                            ? null
                                            : () async {
                                                setS(() => isLoading = true);
                                                try {
                                                  await _aplicarAprovacaoEntregador(
                                                    entregadorId,
                                                    planoId: null,
                                                  );
                                                  if (ctx.mounted) {
                                                    Navigator.pop(ctx);
                                                  }
                                                  if (!mounted) return;
                                                  mostrarSnackPainel(
                                                    context,
                                                    mensagem:
                                                        'Entregador aprovado. Configure o plano depois em Aprovados.',
                                                  );
                                                } catch (e) {
                                                  if (!mounted) return;
                                                  mostrarSnackPainel(
                                                    context,
                                                    erro: true,
                                                    mensagem: 'Erro: $e',
                                                  );
                                                } finally {
                                                  if (ctx.mounted) {
                                                    setS(() => isLoading =
                                                        false);
                                                  }
                                                }
                                              },
                                        icon: const Icon(
                                          Icons.verified_rounded,
                                          size: 18,
                                        ),
                                        label: Text(
                                          'Aprovar sem plano',
                                          style:
                                              GoogleFonts.plusJakartaSans(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 13,
                                          ),
                                        ),
                                        style: FilledButton.styleFrom(
                                          backgroundColor:
                                              const Color(0xFF059669),
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 16,
                                            vertical: 10,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(10),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            );
                          }
                          if (planoSelecionado != null &&
                              !planosValidos.any((p) => p.id == planoSelecionado)) {
                            planoSelecionado = null;
                          }
                          return DropdownButtonFormField<String>(
                            value: planoSelecionado,
                            isExpanded: true,
                            decoration: InputDecoration(
                              labelText: 'Plano de comissão',
                              hintText: 'Selecione…',
                              labelStyle: GoogleFonts.plusJakartaSans(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                                color: PainelAdminTheme.textoSecundario,
                              ),
                              floatingLabelStyle: GoogleFonts.plusJakartaSans(
                                fontWeight: FontWeight.w700,
                                color: PainelAdminTheme.roxo,
                              ),
                              filled: true,
                              fillColor: const Color(0xFFF8FAFC),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 16,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: const BorderSide(
                                  color: Color(0xFFE2E8F0),
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: const BorderSide(
                                  color: Color(0xFFE2E8F0),
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide(
                                  color: PainelAdminTheme.roxo,
                                  width: 1.8,
                                ),
                              ),
                            ),
                            dropdownColor: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            items: planosValidos.map((doc) {
                              final p = doc.data();
                              final nome = _str(p['nome'], 'Sem nome');
                              final valor = '${p['valor'] ?? 0}';
                              final tipo = p['tipo_cobranca'] == 'fixo'
                                  ? 'R\$'
                                  : '%';
                              final freq = _str(p['frequencia'], 'venda');
                              final vPlano = _str(p['veiculo'], 'Todos');
                              return DropdownMenuItem<String>(
                                value: doc.id,
                                child: Text(
                                  '$nome · $valor$tipo / $freq · $vPlano',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              );
                            }).toList(),
                            onChanged: (v) => setS(() => planoSelecionado = v),
                          );
                        },
                      ),
                      const SizedBox(height: 8),
                      Text(
                        modoAprovar
                            ? 'Ao aprovar, o entregador é ativado e o plano passa a valer para novas corridas.'
                            : 'A taxa passa a valer para novas corridas conforme regras do plano.',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 11.5,
                          height: 1.4,
                          color: PainelAdminTheme.textoSecundario,
                        ),
                      ),
                      if (modoAprovar) ...[
                        const SizedBox(height: 10),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            onPressed: isLoading
                                ? null
                                : () async {
                                    setS(() => isLoading = true);
                                    try {
                                      await _aplicarAprovacaoEntregador(
                                        entregadorId,
                                        planoId: null,
                                      );
                                      if (ctx.mounted) Navigator.pop(ctx);
                                      if (!mounted) return;
                                      mostrarSnackPainel(
                                        context,
                                        mensagem:
                                            'Entregador aprovado. Configure o plano depois em Aprovados.',
                                      );
                                    } catch (e) {
                                      if (!mounted) return;
                                      mostrarSnackPainel(
                                        context,
                                        erro: true,
                                        mensagem: 'Erro: $e',
                                      );
                                    } finally {
                                      if (ctx.mounted) {
                                        setS(() => isLoading = false);
                                      }
                                    }
                                  },
                            icon: Icon(
                              Icons.flash_on_rounded,
                              size: 16,
                              color: PainelAdminTheme.textoSecundario,
                            ),
                            label: Text(
                              'Aprovar sem plano (configurar depois)',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: PainelAdminTheme.textoSecundario,
                              ),
                            ),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 4,
                              ),
                              visualDensity: VisualDensity.compact,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 22),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: isLoading
                                  ? null
                                  : () => Navigator.pop(ctx),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: PainelAdminTheme.roxo,
                                side: BorderSide(
                                  color: PainelAdminTheme.roxo
                                      .withValues(alpha: 0.35),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: Text(
                                'Cancelar',
                                style: GoogleFonts.plusJakartaSans(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: FilledButton.icon(
                              onPressed: (isLoading ||
                                      planoSelecionado == null)
                                  ? null
                                  : () async {
                                      setS(() => isLoading = true);
                                      try {
                                        if (modoAprovar) {
                                          await _aplicarAprovacaoEntregador(
                                            entregadorId,
                                            planoId: planoSelecionado,
                                          );
                                        } else {
                                          await FirebaseFirestore.instance
                                              .collection('users')
                                              .doc(entregadorId)
                                              .update({
                                            'plano_entregador_id':
                                                planoSelecionado,
                                          });
                                        }
                                        if (ctx.mounted) {
                                          Navigator.pop(ctx);
                                        }
                                        if (!mounted) return;
                                        mostrarSnackPainel(
                                          context,
                                          mensagem: modoAprovar
                                              ? 'Entregador aprovado e plano aplicado!'
                                              : 'Plano atribuído com sucesso!',
                                        );
                                      } catch (e) {
                                        if (!mounted) return;
                                        mostrarSnackPainel(
                                          context,
                                          erro: true,
                                          mensagem: 'Erro: $e',
                                        );
                                      } finally {
                                        if (ctx.mounted) {
                                          setS(() => isLoading = false);
                                        }
                                      }
                                    },
                              icon: isLoading
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : Icon(
                                      modoAprovar
                                          ? Icons.verified_rounded
                                          : Icons.check_rounded,
                                      size: 20,
                                    ),
                              label: Text(
                                isLoading
                                    ? 'Salvando…'
                                    : (modoAprovar
                                        ? 'Aprovar e aplicar plano'
                                        : 'Salvar plano'),
                                style: GoogleFonts.plusJakartaSans(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                ),
                              ),
                              style: FilledButton.styleFrom(
                                backgroundColor: modoAprovar
                                    ? const Color(0xFF059669)
                                    : PainelAdminTheme.roxo,
                                foregroundColor: Colors.white,
                                disabledBackgroundColor: (modoAprovar
                                        ? const Color(0xFF059669)
                                        : PainelAdminTheme.roxo)
                                    .withValues(alpha: 0.4),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 14,
                                ),
                              ),
                            ),
                          ),
                        ],
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

/// Diálogo que lista os documentos pendentes de **um** entregador para
/// aprovação/recusa. Usa o card compacto existente do parent
/// ([`_buildCardAtualizacaoDocumento`]) e se autofecha quando a última
/// pendência é resolvida.
///
/// Só rebuilda quando o `versao` (ValueNotifier) do parent é incrementado,
/// evitando piscar dos previews ao aprovar/reprovar.
class _DialogoAtualizacoesEntregador extends StatefulWidget {
  const _DialogoAtualizacoesEntregador({
    required this.uid,
    required this.userData,
    required this.rotulosVeiculo,
    required this.versao,
    required this.buildCardDoc,
    required this.lerPendenciasAtuais,
  });

  final String uid;
  final Map<String, dynamic> userData;
  final Map<String, String> rotulosVeiculo;
  final ValueNotifier<int> versao;
  final Widget Function(_DocPendentePainel row) buildCardDoc;
  final List<_DocPendentePainel> Function() lerPendenciasAtuais;

  @override
  State<_DialogoAtualizacoesEntregador> createState() =>
      _DialogoAtualizacoesEntregadorState();
}

class _DialogoAtualizacoesEntregadorState
    extends State<_DialogoAtualizacoesEntregador> {
  @override
  void initState() {
    super.initState();
    widget.versao.addListener(_onVersaoChanged);
  }

  @override
  void dispose() {
    widget.versao.removeListener(_onVersaoChanged);
    super.dispose();
  }

  void _onVersaoChanged() {
    if (!mounted) return;
    final pendencias = widget.lerPendenciasAtuais();
    if (pendencias.isEmpty) {
      // Agenda fechamento no próximo frame para não pop() durante build.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      });
    } else {
      setState(() {});
    }
  }

  String _str(dynamic v, [String fallback = '']) {
    if (v == null) return fallback;
    if (v is String) return v;
    try {
      return v.toString();
    } catch (_) {
      return fallback;
    }
  }

  @override
  Widget build(BuildContext context) {
    final pendencias = widget.lerPendenciasAtuais();
    final nome = _str(widget.userData['nome'], 'Sem nome');
    final cidade = _str(widget.userData['cidade']);
    final veiculoTipo = _str(widget.userData['veiculoTipo']).trim();
    final placa = () {
      for (final key in ['placa_veiculo', 'placa', 'placaVeiculo']) {
        final s = _str(widget.userData[key]).trim();
        if (s.isNotEmpty) return s.toUpperCase();
      }
      return '';
    }();

    final metaParts = <String>[
      if (cidade.isNotEmpty) cidade,
      if (veiculoTipo.isNotEmpty) veiculoTipo,
      if (placa.isNotEmpty) placa,
    ];

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      backgroundColor: Colors.white,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 680),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: PainelAdminTheme.roxo.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.fact_check_outlined,
                      color: PainelAdminTheme.roxo,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Atualizações · $nome',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: PainelAdminTheme.dashboardInk,
                          ),
                        ),
                        if (metaParts.isNotEmpty) const SizedBox(height: 2),
                        if (metaParts.isNotEmpty)
                          Text(
                            metaParts.join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 12.5,
                              color: PainelAdminTheme.textoSecundario,
                            ),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Fechar',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Color(0xFFE2E8F0)),
            Flexible(
              child: pendencias.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.check_circle_outline_rounded,
                            size: 40,
                            color: const Color(0xFF059669),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'Nenhum documento pendente para este entregador.',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 13,
                              color: PainelAdminTheme.textoSecundario,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
                      itemCount: pendencias.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (_, i) => widget.buildCardDoc(pendencias[i]),
                    ),
            ),
            const Divider(height: 1, color: Color(0xFFE2E8F0)),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Fechar'),
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
