import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../constants/conta_bloqueio_lojista.dart';
import '../theme/painel_admin_theme.dart';
import '../utils/admin_perfil.dart';
import '../utils/conta_bloqueio_entregador.dart';
import '../services/firebase_functions_config.dart';
import '../widgets/botao_suporte_flutuante.dart';
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

  static const int _debounceBuscaMs = 350;
  static const int _itensPorPagina = 10;

  final Map<String, int> _paginaPorStatus = {
    'pendente': 0,
    'aprovado': 0,
    'bloqueado': 0,
    'atualizacoes': 0,
  };

  static const _statusTabs = [
    'pendente',
    'aprovado',
    'bloqueado',
    'atualizacoes',
  ];

  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _campoBuscaController = TextEditingController();
    _tabController = TabController(length: _statusTabs.length, vsync: this);
    _tabController.addListener(_onTabEntregadoresChanged);
    _buscarDadosDoGestor();
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
      setState(() {
        _atualizacoesDocsCache = list;
        _atualizacoesCarregando = false;
        _atualizacoesFetchErro = null;
      });
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
    _debounceBusca?.cancel();
    _campoBuscaController.dispose();
    _tabController.dispose();
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
      }
    } catch (e) {
      debugPrint('Erro ao carregar permissão: $e');
    }
  }

  Query<Map<String, dynamic>> _queryPorStatus(String status) {
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

  Future<void> _desbloquearEntregador(String id, String nome) async {
    final admin = FirebaseAuth.instance.currentUser;
    if (admin == null) return;
    final ref = FirebaseFirestore.instance.collection('users').doc(id);
    final batch = FirebaseFirestore.instance.batch();
    batch.update(ref, {
      'entregador_status': 'aprovado',
      'status_conta': ContaBloqueioLojista.statusContaActive,
      'motivo_recusa': FieldValue.delete(),
      'motivo_bloqueio': FieldValue.delete(),
      'recusa_cadastro': FieldValue.delete(),
      'block_active': false,
      'block_type': FieldValue.delete(),
      'block_reason': FieldValue.delete(),
      'block_start_at': FieldValue.delete(),
      'block_end_at': FieldValue.delete(),
    });
    batch.set(ref.collection('bloqueios_auditoria').doc(), {
      'admin_id': admin.uid,
      'admin_email': admin.email,
      'applied_at': FieldValue.serverTimestamp(),
      'action': 'unblock',
      'entregador_nome': nome,
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

  Future<void> _aplicarBloqueioEntregador({
    required String id,
    required String nomeEntregador,
    required String blockType,
    required String blockReason,
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
    final textoMotivoPainel = blockType == ContaBloqueioLojista.blockFull
        ? 'Pendências financeiras'
        : 'Bloqueio administrativo temporário';
    batch.update(ref, {
      'entregador_status': statusPainel,
      'status_conta': ContaBloqueioLojista.statusContaBlocked,
      'motivo_bloqueio': textoMotivoPainel,
      'recusa_cadastro': FieldValue.delete(),
      'block_type': blockType,
      'block_reason': blockReason,
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
                        'Motivo: inadimplência — acesso total suspenso',
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
                        'Bloqueio por dias (ex.: falta de pagamento pontual) — após o prazo, a conta pode ser reativada automaticamente.',
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
                        onPressed: () => Navigator.pop(ctx),
                        child: Text('Cancelar',
                            style: GoogleFonts.plusJakartaSans(
                                fontWeight: FontWeight.w600))),
                    const SizedBox(width: 12),
                    FilledButton.icon(
                      onPressed: salvando
                          ? null
                          : () async {
                              int? dur;
                              if (modo ==
                                  ContaBloqueioLojista.blockTemporary) {
                                dur = int.tryParse(diasC.text.trim());
                                if (dur == null || dur < 1) {
                                  mostrarSnackPainel(ctx,
                                      erro: true,
                                      mensagem:
                                          'Informe a duração em dias (número ≥ 1).');
                                  return;
                                }
                              }
                              setS(() => salvando = true);
                              await _aplicarBloqueioEntregador(
                                id: id,
                                nomeEntregador: nomeEntregador,
                                blockType: modo,
                                blockReason: modo ==
                                        ContaBloqueioLojista.blockFull
                                    ? ContaBloqueioLojista.motivoInadimplencia
                                    : ContaBloqueioLojista.motivoOutros,
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
                          : const Icon(Icons.block_rounded, size: 18),
                      label: const Text('Confirmar bloqueio'),
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
      floatingActionButton: const BotaoSuporteFlutuante(),
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
                  child: TextField(
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
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            TabBar(
              controller: _tabController,
              labelPadding: const EdgeInsets.symmetric(horizontal: 4),
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

  Widget _buildTab(String status) {
    final info = _kStatus[status]!;
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
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Erro ao carregar entregadores.\n${snapshot.error}',
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
          return Center(
              child: CircularProgressIndicator(
                  color: PainelAdminTheme.roxo, strokeWidth: 2.5));
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

        if (filtrados.isEmpty) return _buildEmptyState(status, info);

        final totalItens = filtrados.length;
        final totalPaginas = math.max(
          1,
          ((totalItens - 1) ~/ _itensPorPagina) + 1,
        );
        final paginaArmazenada = _paginaPorStatus[status] ?? 0;
        final paginaAtual = paginaArmazenada.clamp(0, totalPaginas - 1);
        final inicio = paginaAtual * _itensPorPagina;
        final fim = math.min(inicio + _itensPorPagina, totalItens);
        final paginaItens = filtrados.sublist(inicio, fim);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(32, 24, 32, 16),
                itemCount: paginaItens.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (_, i) =>
                    _buildEntregadorCard(paginaItens[i], status, info),
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

  Widget _buildEmptyState(String status, _StatusVisual info) {
    final hasSearch = _busca.isNotEmpty;
    final titulo = hasSearch
        ? 'Nenhum resultado para "$_busca"'
        : status == 'atualizacoes'
            ? 'Nada na fila de atualizações.'
            : 'Nenhum entregador ${info.label.toLowerCase()} encontrado.';
    final subtitulo = hasSearch
        ? 'Tente outro termo de busca.'
        : status == 'pendente'
            ? 'Novos entregadores aparecerão aqui ao solicitar cadastro.'
            : status == 'atualizacoes'
                ? 'CNH ou CRLV enviados por entregadores já aprovados aparecem aqui quando estiverem em análise.'
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
            style: GoogleFonts.plusJakartaSans(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: PainelAdminTheme.textoSecundario),
          ),
          const SizedBox(height: 8),
          Text(
            subtitulo,
            style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                color: PainelAdminTheme.textoSecundario
                    .withValues(alpha: 0.7)),
          ),
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
      if (mounted) setState(() => _docPendenteSalvandoPath = null);
    }
  }

  Future<void> _reprovarDocumentoPendente(
    _DocPendentePainel row,
    String motivo,
  ) async {
    final admin = FirebaseAuth.instance.currentUser;
    if (admin == null) return;
    setState(() => _docPendenteSalvandoPath = row.chaveUnica);
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
      if (mounted) setState(() => _docPendenteSalvandoPath = null);
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

        final vis = brutos
            .where((row) => users[row.uid] != null)
            .toList();

        final filtrados = _busca.isEmpty
            ? vis
            : vis.where((row) {
                final u = users[row.uid];
                if (u == null) return false;
                final nome = _str(u['nome']).toLowerCase();
                final cidade = _str(u['cidade']).toLowerCase();
                final tipoDoc = row.tipo == 'cnh' ? 'cnh' : 'crlv';
                final rv = row.tipo == 'crlv' && row.veiculoId != null
                    ? _str(rotulosVeiculo['${row.uid}|${row.veiculoId}'])
                        .toLowerCase()
                    : '';
                return nome.contains(_busca) ||
                    cidade.contains(_busca) ||
                    tipoDoc.contains(_busca) ||
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
                padding: const EdgeInsets.fromLTRB(32, 16, 32, 16),
                itemCount: paginaItens.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (_, i) => _buildCardAtualizacaoDocumento(
                  paginaItens[i],
                  users[paginaItens[i].uid] ?? {},
                  rotulosVeiculo,
                ),
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
    final urlFuture = _resolverUrlDocumento(rawUrl);

    return Material(
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        nome,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: PainelAdminTheme.dashboardInk,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$cidade · $tipoLabel · $subt',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
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
                    color: const Color(0xFFFFF7ED),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFFED7AA)),
                  ),
                  child: Text(
                    'Em análise',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFFD97706),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            FutureBuilder<String>(
              future: urlFuture,
              builder: (context, snap) {
                final url = (snap.data ?? '').trim();
                if (snap.connectionState == ConnectionState.waiting) {
                  return const SizedBox(
                    height: 120,
                    child: Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  );
                }
                if (url.isEmpty) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'URL ausente.',
                        style: GoogleFonts.plusJakartaSans(
                            fontStyle: FontStyle.italic,
                            color: PainelAdminTheme.textoSecundario),
                      ),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 10,
                        runSpacing: 8,
                        children: [
                          FilledButton.icon(
                            onPressed: salvando
                                ? null
                                : () => _aprovarDocumentoPendente(row),
                            icon: salvando
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white))
                                : const Icon(Icons.check_rounded, size: 18),
                            label: const Text('Aprovar'),
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF059669),
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed: salvando
                                ? null
                                : () =>
                                    _mostrarDialogoReprovarDocumento(row),
                            icon: const Icon(Icons.close_rounded, size: 18),
                            label: const Text('Reprovar'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFFDC2626),
                              side: const BorderSide(color: Color(0xFFFECACA)),
                            ),
                          ),
                        ],
                      ),
                    ],
                  );
                }
                Widget preview;
                if (_ehPdf(url)) {
                  preview = ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(
                      height: 220,
                      child: buildPdfPreview(url, height: 220),
                    ),
                  );
                } else {
                  preview = ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Material(
                      color: const Color(0xFFF8FAFC),
                      child: InkWell(
                        onTap: () =>
                            _mostrarImagemAmpliada(url, '$tipoLabel — $nome'),
                        child: Image.network(
                          url,
                          height: 200,
                          fit: BoxFit.contain,
                          webHtmlElementStrategy: kIsWeb
                              ? WebHtmlElementStrategy.prefer
                              : WebHtmlElementStrategy.never,
                          loadingBuilder: (_, child, p) => p == null
                              ? child
                              : const SizedBox(
                                  height: 200,
                                  child: Center(
                                      child: CircularProgressIndicator()),
                                ),
                          errorBuilder: (context, error, stackTrace) =>
                              const Padding(
                            padding: EdgeInsets.all(24),
                            child: Text('Não foi possível carregar a imagem.'),
                          ),
                        ),
                      ),
                    ),
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    preview,
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 10,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: salvando
                              ? null
                              : () async {
                                  final u = Uri.tryParse(url);
                                  if (u == null) return;
                                  if (!await launchUrl(u,
                                      mode:
                                          LaunchMode.externalApplication)) {
                                    if (context.mounted) {
                                      mostrarSnackPainel(context,
                                          erro: true,
                                          mensagem:
                                              'Não foi possível abrir o link.');
                                    }
                                  }
                                },
                          icon:
                              const Icon(Icons.open_in_new_rounded, size: 18),
                          label: const Text('Abrir em nova aba'),
                        ),
                        FilledButton.icon(
                          onPressed: salvando
                              ? null
                              : () => _aprovarDocumentoPendente(row),
                          icon: salvando
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.check_rounded, size: 18),
                          label: const Text('Aprovar'),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF059669),
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: salvando
                              ? null
                              : () =>
                                  _mostrarDialogoReprovarDocumento(row),
                          icon: const Icon(Icons.close_rounded, size: 18),
                          label: const Text('Reprovar'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFFDC2626),
                            side: const BorderSide(color: Color(0xFFFECACA)),
                          ),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
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
    final slPainel = _str(dados['entregador_status']);
    final bloqOp =
        ContaBloqueioEntregadorHelper.estaBloqueadoParaOperacoes(dados);
    final fimTemp = ContaBloqueioEntregadorHelper.dataFimBloqueio(dados);
    final chipBloqueio = slPainel == ContaBloqueioLojista.statusLojaBloqueioTemporario
        ? 'Bloqueio temporário'
        : (ContaBloqueioEntregadorHelper.isBloqueioFinanceiro(dados)
            ? 'Inadimplência'
            : null);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 12,
              offset: const Offset(0, 4)),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: info.bgColor,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: info.borderColor),
                image: fotoUrl.isNotEmpty
                    ? DecorationImage(
                        image: NetworkImage(fotoUrl), fit: BoxFit.cover)
                    : null,
              ),
              child: fotoUrl.isEmpty
                  ? Icon(Icons.delivery_dining_rounded,
                      color: info.color, size: 26)
                  : null,
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(
                      child: Text(nome,
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: PainelAdminTheme.dashboardInk),
                          overflow: TextOverflow.ellipsis),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                          color: info.bgColor,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: info.borderColor)),
                      child: Text(info.label,
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: info.color)),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  Wrap(spacing: 16, runSpacing: 6, children: [
                    _metaChip(Icons.location_on_outlined, cidade.toUpperCase()),
                    _metaChip(
                        Icons.two_wheeler_outlined, '$veiculo ($placa)'),
                    if (status == 'aprovado')
                      _metaChip(
                          Icons.receipt_long_outlined,
                          planoId != null ? 'Plano ativo' : 'Sem plano',
                          highlight: planoId == null),
                    if (chipBloqueio != null)
                      _metaChip(Icons.schedule_rounded, chipBloqueio,
                          highlight: true),
                    if (fimTemp != null &&
                        slPainel ==
                            ContaBloqueioLojista.statusLojaBloqueioTemporario)
                      _metaChip(
                        Icons.event_outlined,
                        'Até ${fimTemp.day.toString().padLeft(2, '0')}/${fimTemp.month.toString().padLeft(2, '0')}/${fimTemp.year}',
                      ),
                  ]),
                  if (motivoRecusa.isNotEmpty &&
                      (status == 'bloqueado' ||
                          ContaBloqueioEntregadorHelper
                              .entregadorRecusadoSomenteCorrecaoCadastro(
                                  dados))) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                          color: const Color(0xFFFEF2F2),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: const Color(0xFFFECACA))),
                      child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.info_outline_rounded,
                                size: 16, color: Color(0xFFDC2626)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(motivoRecusa,
                                  style: GoogleFonts.plusJakartaSans(
                                      fontSize: 12,
                                      color: const Color(0xFF991B1B),
                                      height: 1.4)),
                            ),
                          ]),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if ((status == 'bloqueado' || status == 'aprovado') &&
                    bloqOp) ...[
                  _actionBtn(Icons.lock_open_rounded, 'Desbloquear',
                      const Color(0xFF059669),
                      filled: true,
                      onTap: () => _desbloquearEntregador(doc.id, nome)),
                  const SizedBox(height: 8),
                ],
                if (status == 'pendente') ...[
                  _actionBtn(Icons.description_outlined, 'Documentos',
                      const Color(0xFF3B82F6),
                      onTap: () => _mostrarDocumentosModal(dados)),
                  const SizedBox(height: 8),
                  _actionBtn(
                      Icons.check_circle_outline_rounded,
                      'Aprovar',
                      const Color(0xFF059669),
                      filled: true,
                      onTap: () =>
                          _alterarStatusEntregador(doc.id, 'aprovado')),
                  const SizedBox(height: 8),
                  _actionBtn(Icons.close_rounded, 'Recusar',
                      const Color(0xFFDC2626),
                      onTap: () =>
                          _mostrarModalRecusaEntregador(doc.id, nome)),
                ] else ...[
                  _buildMaisAcoesEntregadorMenu(
                    doc: doc,
                    dados: dados,
                    nomeEntregador: nome,
                    planoId: planoId,
                    cidade: cidade,
                    veiculo: veiculo,
                    incluirPlanoTaxaEBloquear:
                        status == 'aprovado' && !bloqOp,
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
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
        width: 42,
        height: 42,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: const Icon(
          Icons.more_vert_rounded,
          size: 22,
          color: Color(0xFF64748B),
        ),
      ),
    );
  }

  Widget _metaChip(IconData icon, String text, {bool highlight = false}) {
    final c = highlight
        ? const Color(0xFFD97706)
        : PainelAdminTheme.textoSecundario;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 15, color: c),
      const SizedBox(width: 5),
      Text(text,
          style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              color: c,
              fontWeight: highlight ? FontWeight.w600 : FontWeight.w500)),
    ]);
  }

  Widget _actionBtn(IconData icon, String label, Color color,
      {required VoidCallback onTap, bool filled = false}) {
    return SizedBox(
      width: 130,
      height: 34,
      child: filled
          ? FilledButton.icon(
              onPressed: onTap,
              icon: Icon(icon, size: 16),
              label: Text(label, style: const TextStyle(fontSize: 12)),
              style: FilledButton.styleFrom(
                  backgroundColor: color,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10))))
          : OutlinedButton.icon(
              onPressed: onTap,
              icon: Icon(icon, size: 16),
              label: Text(label, style: const TextStyle(fontSize: 12)),
              style: OutlinedButton.styleFrom(
                  foregroundColor: color,
                  side: BorderSide(color: color.withValues(alpha: 0.35)),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)))),
    );
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
    String veiculoTipo,
  ) {
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
                          color: PainelAdminTheme.roxo.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: PainelAdminTheme.roxo.withValues(alpha: 0.15),
                          ),
                        ),
                        child: Icon(
                          Icons.tune_rounded,
                          color: PainelAdminTheme.roxo,
                          size: 26,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Definir plano',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 19,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.3,
                                color: PainelAdminTheme.dashboardInk,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              nomeEntregador,
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
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    Icons.info_outline_rounded,
                                    size: 22,
                                    color: const Color(0xFFD97706),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      'Não há planos para esta cidade e tipo de veículo. Cadastre em Configurações → planos (público: entregador) ou ajuste o cadastro.',
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 13,
                                        height: 1.45,
                                        color: const Color(0xFF92400E),
                                      ),
                                    ),
                                  ),
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
                        'A taxa passa a valer para novas corridas conforme regras do plano.',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 11.5,
                          height: 1.4,
                          color: PainelAdminTheme.textoSecundario,
                        ),
                      ),
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
                                        await FirebaseFirestore.instance
                                            .collection('users')
                                            .doc(entregadorId)
                                            .update({
                                          'plano_entregador_id': planoSelecionado,
                                        });
                                        if (ctx.mounted) {
                                          Navigator.pop(ctx);
                                        }
                                        if (!mounted) return;
                                        mostrarSnackPainel(
                                          context,
                                          mensagem:
                                              'Plano atribuído com sucesso!',
                                        );
                                      } catch (e) {
                                        if (!mounted) return;
                                        mostrarSnackPainel(
                                          context,
                                          erro: true,
                                          mensagem: 'Erro: $e',
                                        );
                                      } finally {
                                        setS(() => isLoading = false);
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
                                  : const Icon(Icons.check_rounded, size: 20),
                              label: Text(
                                isLoading ? 'Salvando…' : 'Salvar plano',
                                style: GoogleFonts.plusJakartaSans(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                ),
                              ),
                              style: FilledButton.styleFrom(
                                backgroundColor: PainelAdminTheme.roxo,
                                foregroundColor: Colors.white,
                                disabledBackgroundColor:
                                    PainelAdminTheme.roxo.withValues(
                                        alpha: 0.4),
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
