import 'dart:math' show max, min;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../theme/painel_admin_theme.dart';
import '../utils/admin_perfil.dart';
import '../widgets/botao_suporte_flutuante.dart';

class _MotivoRecusaEscolhido {
  const _MotivoRecusaEscolhido({
    required this.codigo,
    required this.textoMotivo,
  });
  final String codigo;
  final String textoMotivo;
}

class _CacheUsuariosSaques {
  const _CacheUsuariosSaques({
    required this.rolePorUid,
    required this.nomePorUid,
  });
  final Map<String, String> rolePorUid;
  final Map<String, String> nomePorUid;
}

/// Painel master — solicitações de saque PIX (lojistas e entregadores).
class SolicitacoesSaquesPainelScreen extends StatefulWidget {
  const SolicitacoesSaquesPainelScreen({super.key});

  @override
  State<SolicitacoesSaquesPainelScreen> createState() =>
      _SolicitacoesSaquesPainelScreenState();
}

class _SolicitacoesSaquesPainelScreenState
    extends State<SolicitacoesSaquesPainelScreen> {
  String _filtroTipo = 'todos';

  static const int _kItensPorPagina = 10;

  final TextEditingController _pesquisaController = TextEditingController();
  int _paginaAtual = 0;
  DateTime? _filtroDataDe;
  DateTime? _filtroDataAte;

  String? _idsSaquesMetadadosKey;
  Future<_CacheUsuariosSaques>? _futureMetadadosUsuarios;

  static final _brl = NumberFormat.currency(locale: 'pt_BR', symbol: r'R$');
  static final _fmtDataHora = DateFormat('dd/MM/yyyy · HH:mm', 'pt_BR');

  /// Número sempre com 2 casas decimais (pt_BR); prefixo literal `R$ ` (espaço único).
  static final _fmtDuasCasasPt = NumberFormat('#,##0.00', 'pt_BR');

  /// Formato estável: `R$ 10,00` (nunca `R$5` / `R$ 5` sem decimais).
  static String _formatarValorColunaTabela(double v) {
    return 'R\$ ${_fmtDuasCasasPt.format(v)}';
  }

  static TextStyle _estiloValorColunaTabela() {
    return GoogleFonts.plusJakartaSans(
      fontSize: 13,
      fontWeight: FontWeight.w800,
      color: PainelAdminTheme.dashboardInk,
      height: 1.2,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
  }

  static String _tipoPerfilSaque(Map<String, dynamic> d) {
    for (final key in [
      'tipo_usuario',
      'tipoUsuario',
      'tipo',
      'perfil_saque',
    ]) {
      final raw = d[key];
      if (raw == null) continue;
      var t = raw.toString().toLowerCase().trim();
      if (t.isEmpty) continue;
      if (t == 'loja' || t == 'lojas' || t == 'lojistas') t = 'lojista';
      if (t.contains('lojis')) t = 'lojista';
      if (t == 'entregadores') t = 'entregador';
      return t;
    }
    return '';
  }

  static String _tipoEfetivo(
    Map<String, dynamic> d,
    Map<String, String> rolePorUid,
  ) {
    final fromDoc = _tipoPerfilSaque(d);
    if (fromDoc == 'lojista' || fromDoc == 'entregador') return fromDoc;

    final uid = d['user_id']?.toString().trim() ?? '';
    if (uid.isEmpty) return fromDoc;

    final r = (rolePorUid[uid] ?? '').toLowerCase().trim();
    if (r == 'lojista' || r == 'entregador') return r;

    return fromDoc.isNotEmpty ? fromDoc : r;
  }

  bool _passaFiltroTipo(
    Map<String, dynamic> d,
    Map<String, String> rolePorUid,
  ) {
    if (_filtroTipo == 'todos') return true;
    return _tipoEfetivo(d, rolePorUid) == _filtroTipo;
  }

  static String _rotuloTipoAmigavel(String tipo) {
    if (tipo == 'entregador') return 'Entregador';
    if (tipo == 'lojista') return 'Lojista';
    return tipo.isEmpty ? '' : tipo;
  }

  /// Pesquisa no nome do solicitante e no perfil; intervalo de datas em [data_solicitacao].
  bool _passaPesquisaEData(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
    Map<String, String> rolePorUid,
    Map<String, String> nomePorUid,
  ) {
    final m = doc.data();
    final q = _pesquisaController.text.trim().toLowerCase();
    if (q.isNotEmpty) {
      final uid = m['user_id']?.toString().trim() ?? '';
      final nome = uid.isNotEmpty ? (nomePorUid[uid] ?? '').toLowerCase() : '';
      final tipo = _tipoEfetivo(m, rolePorUid);
      final amig = _rotuloTipoAmigavel(tipo).toLowerCase();
      final blob = '$nome $tipo $amig lojista loja entregador entrega'.toLowerCase();
      if (!blob.contains(q)) return false;
    }

    final ts = m['data_solicitacao'];
    if (ts is! Timestamp) {
      return _filtroDataDe == null && _filtroDataAte == null;
    }
    final dt = ts.toDate();
    final dia = DateTime(dt.year, dt.month, dt.day);
    if (_filtroDataDe != null) {
      final de = DateTime(
        _filtroDataDe!.year,
        _filtroDataDe!.month,
        _filtroDataDe!.day,
      );
      if (dia.isBefore(de)) return false;
    }
    if (_filtroDataAte != null) {
      final ate = DateTime(
        _filtroDataAte!.year,
        _filtroDataAte!.month,
        _filtroDataAte!.day,
      );
      if (dia.isAfter(ate)) return false;
    }
    return true;
  }

  @override
  void dispose() {
    _pesquisaController.dispose();
    super.dispose();
  }

  static String _statusSaqueNormalizado(Map<String, dynamic> m) {
    final raw = m['status'];
    if (raw == null) return 'pendente';
    final s = raw.toString().trim().toLowerCase();
    if (s.isEmpty) return 'pendente';
    if (s == 'pago' || s == 'recusado' || s == 'pendente') return s;
    if (s.contains('pago') || s == 'paid') return 'pago';
    if (s.contains('recus')) return 'recusado';
    if (s.contains('pend')) return 'pendente';
    return s;
  }

  Future<_CacheUsuariosSaques> _obterMetadadosUsuarios(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) async {
    final uids = <String>{};
    for (final doc in docs) {
      final u = doc.data()['user_id']?.toString().trim();
      if (u != null && u.isNotEmpty) uids.add(u);
    }
    if (uids.isEmpty) {
      return const _CacheUsuariosSaques(rolePorUid: {}, nomePorUid: {});
    }
    final rolePorUid = <String, String>{};
    final nomePorUid = <String, String>{};
    await Future.wait(uids.map((uid) async {
      try {
        final s = await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .get();
        if (!s.exists || s.data() == null) return;
        final d = s.data()!;
        rolePorUid[uid] = perfilAdministrativoPainel(d);
        for (final k in ['nome', 'nome_completo', 'display_name']) {
          final n = d[k]?.toString().trim() ?? '';
          if (n.isNotEmpty) {
            nomePorUid[uid] = n;
            break;
          }
        }
      } catch (_) {}
    }));
    return _CacheUsuariosSaques(
      rolePorUid: rolePorUid,
      nomePorUid: nomePorUid,
    );
  }

  Future<void> _marcarPago(String docId, double valor) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar pagamento'),
        content: Text(
          'Confirma que o PIX de ${_brl.format(valor)} foi enviado?\n\n'
          'O lojista ou entregador receberá e-mail e notificação no app.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF15803D),
            ),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    try {
      final payload = <String, dynamic>{
        'status': 'pago',
        'data_pago': FieldValue.serverTimestamp(),
      };
      if (uid != null) payload['pago_por_uid'] = uid;
      await FirebaseFirestore.instance
          .collection('saques_solicitacoes')
          .doc(docId)
          .update(payload);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Marcado como pago. Notificação será enviada.'),
            backgroundColor: Color(0xFF15803D),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  static const Map<String, String> _kMotivosRecusaPadrao = {
    'titular_incompativel':
        'O titular da conta informada não é o mesmo responsável pela loja.',
    'saque_indisponivel_momento': 'Solicitação de saque indisponível no momento.',
    'banco_recusou': 'O seu banco recusou o recebimento do saque.',
  };

  Future<_MotivoRecusaEscolhido?> _dialogMotivoRecusa() async {
    String codigo = 'titular_incompativel';
    final outrosC = TextEditingController();
    return showDialog<_MotivoRecusaEscolhido>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx2, setSt) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: Text(
                'Recusar saque',
                style: GoogleFonts.plusJakartaSans(
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                ),
              ),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'O valor foi reservado na carteira ao solicitar. Ao recusar, '
                        'o valor será devolvido automaticamente e registado no extrato.',
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.35,
                          color: Colors.grey.shade700,
                        ),
                      ),
                      const SizedBox(height: 16),
                      ..._kMotivosRecusaPadrao.entries.map((e) {
                        return RadioListTile<String>(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          value: e.key,
                          groupValue: codigo,
                          title: Text(
                            e.value,
                            style: const TextStyle(fontSize: 13),
                          ),
                          onChanged: (v) {
                            if (v != null) setSt(() => codigo = v);
                          },
                        );
                      }),
                      RadioListTile<String>(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        value: 'outros',
                        groupValue: codigo,
                        title: const Text(
                          'Outros (descreva o motivo)',
                          style: TextStyle(fontSize: 13),
                        ),
                        onChanged: (v) {
                          if (v != null) setSt(() => codigo = v);
                        },
                      ),
                      if (codigo == 'outros') ...[
                        const SizedBox(height: 6),
                        TextField(
                          controller: outrosC,
                          maxLines: 3,
                          decoration: InputDecoration(
                            hintText: 'Motivo da recusa…',
                            filled: true,
                            fillColor: Colors.grey.shade50,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ],
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
                    if (codigo == 'outros' && outrosC.text.trim().isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Descreva o motivo em "Outros".'),
                          backgroundColor: Color(0xFFB91C1C),
                        ),
                      );
                      return;
                    }
                    final texto = codigo == 'outros'
                        ? outrosC.text.trim()
                        : (_kMotivosRecusaPadrao[codigo] ?? '');
                    Navigator.pop(
                      ctx,
                      _MotivoRecusaEscolhido(
                        codigo: codigo,
                        textoMotivo: texto,
                      ),
                    );
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFB91C1C),
                  ),
                  child: const Text('Confirmar recusa'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _marcarRecusado(String docId) async {
    final motivo = await _dialogMotivoRecusa();
    if (motivo == null || !mounted) return;

    final masterUid = FirebaseAuth.instance.currentUser?.uid;
    final db = FirebaseFirestore.instance;

    try {
      await db.runTransaction((transaction) async {
        final ref = db.collection('saques_solicitacoes').doc(docId);
        final snap = await transaction.get(ref);
        if (!snap.exists) {
          throw Exception('Solicitação não encontrada.');
        }
        final d = snap.data()!;
        final st = (d['status'] ?? '').toString();
        if (st != 'pendente') {
          throw Exception('Este saque já não está pendente.');
        }
        final uid = d['user_id']?.toString().trim() ?? '';
        final v = (d['valor'] is num)
            ? (d['valor'] as num).toDouble()
            : double.tryParse('${d['valor']}') ?? 0;
        if (uid.isEmpty || v <= 0) {
          throw Exception('Dados do saque inválidos.');
        }

        final estornoRef = db.collection('estornos').doc();
        transaction.set(estornoRef, {
          'loja_id': uid,
          'tipo_operacao': 'credito_saque_recusado',
          'saque_solicitacao_id': docId,
          'pedido_id': '',
          'valor': v,
          'motivo': motivo.textoMotivo,
          'motivo_codigo': motivo.codigo,
          'status': 'processado',
          'feito_por': masterUid,
          'data_estorno': FieldValue.serverTimestamp(),
        });

        transaction.update(ref, {
          'status': 'recusado',
          'data_recusa': FieldValue.serverTimestamp(),
          'motivo_recusa_codigo': motivo.codigo,
          'motivo_recusa_texto': motivo.textoMotivo,
          'recusado_por_uid': masterUid,
          'estorno_credito_id': estornoRef.id,
        });

        transaction.update(db.collection('users').doc(uid), {
          'saldo': FieldValue.increment(v),
        });
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Saque recusado. Valor devolvido à carteira do usuário.',
            ),
            backgroundColor: Color(0xFF15803D),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _copiar(
    BuildContext context,
    String texto,
    String msgOk,
  ) async {
    await Clipboard.setData(ClipboardData(text: texto));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msgOk),
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF15803D),
      ),
    );
  }

  static String _rotuloStatusSaque(String status) {
    switch (status) {
      case 'pago':
        return 'Pago';
      case 'recusado':
        return 'Recusado';
      case 'pendente':
      default:
        return 'Pendente';
    }
  }

  Widget _badgeStatus(String status) {
    Color bg;
    Color fg;
    switch (status) {
      case 'pago':
        bg = const Color(0xFFDCFCE7);
        fg = const Color(0xFF166534);
        break;
      case 'recusado':
        bg = const Color(0xFFFEE2E2);
        fg = const Color(0xFF991B1B);
        break;
      default:
        bg = const Color(0xFFFFEDD5);
        fg = const Color(0xFFC2410C);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        _rotuloStatusSaque(status).toUpperCase(),
        style: GoogleFonts.plusJakartaSans(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.5,
          color: fg,
        ),
      ),
    );
  }

  void _abrirDetalhesSaque(
    BuildContext context, {
    required QueryDocumentSnapshot<Map<String, dynamic>> doc,
    required Map<String, String> rolePorUid,
    required Map<String, String> nomePorUid,
    required Color roxo,
  }) {
    final d = doc.data();
    final valor = (d['valor'] as num?)?.toDouble() ?? 0;
    final status = _statusSaqueNormalizado(d);
    final tipo = _tipoEfetivo(d, rolePorUid);
    final tipoLabel = tipo == 'entregador'
        ? 'Entregador'
        : tipo == 'lojista'
            ? 'Lojista'
            : (tipo.isEmpty ? '—' : tipo);
    final chave = d['chave_pix']?.toString().trim() ?? '';
    final titular = d['titular_conta']?.toString().trim() ?? '';
    final banco = d['banco']?.toString().trim() ?? '';
    final uid = d['user_id']?.toString().trim() ?? '';
    final nomeSolic = uid.isNotEmpty ? (nomePorUid[uid] ?? '') : '';
    final ts = d['data_solicitacao'] as Timestamp?;
    final dataStr = ts != null ? _fmtDataHora.format(ts.toDate()) : '—';
    final motivoRecusa = d['motivo_recusa_texto']?.toString().trim() ?? '';

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Expanded(
              child: Text(
                'Solicitação de saque',
                style: GoogleFonts.plusJakartaSans(
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                ),
              ),
            ),
            _badgeStatus(status),
          ],
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _brl.format(valor),
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: PainelAdminTheme.dashboardInk,
                  ),
                ),
                const SizedBox(height: 16),
                _detLinhaDialog('Perfil', tipoLabel),
                _detLinhaDialog('Solicitado em', dataStr),
                if (nomeSolic.isNotEmpty) _detLinhaDialog('Solicitante', nomeSolic),
                _detLinhaDialog(
                  'Chave PIX',
                  chave.isEmpty ? '—' : chave,
                  trailing: chave.isNotEmpty
                      ? IconButton(
                          icon: Icon(Icons.copy_rounded, size: 20, color: roxo),
                          onPressed: () => _copiar(ctx, chave, 'Chave copiada.'),
                        )
                      : null,
                ),
                if (titular.isNotEmpty) _detLinhaDialog('Titular', titular),
                if (banco.isNotEmpty) _detLinhaDialog('Banco', banco),
                if (uid.isNotEmpty)
                  _detLinhaDialog(
                    'ID usuário',
                    uid,
                    trailing: IconButton(
                      icon: Icon(Icons.copy_rounded, size: 20, color: roxo),
                      onPressed: () =>
                          _copiar(ctx, uid, 'ID copiado.'),
                    ),
                  ),
                if (status == 'recusado' && motivoRecusa.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF2F2),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFFECACA)),
                    ),
                    child: Text(
                      'Motivo da recusa: $motivoRecusa',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        height: 1.35,
                        color: const Color(0xFF991B1B),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Fechar'),
          ),
          if (status == 'pendente') ...[
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                _marcarPago(doc.id, valor);
              },
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF15803D),
              ),
              child: const Text('Confirmar PIX'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                _marcarRecusado(doc.id);
              },
              style: TextButton.styleFrom(foregroundColor: const Color(0xFFB91C1C)),
              child: const Text('Recusar'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _detLinhaDialog(
    String rotulo,
    String valor, {
    Widget? trailing,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              rotulo,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade600,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              valor,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 14,
                height: 1.35,
                color: PainelAdminTheme.dashboardInk,
              ),
            ),
          ),
          if (trailing != null) trailing,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return Scaffold(
        backgroundColor: PainelAdminTheme.fundoCanvas,
        body: const Center(child: Text('Sessão inválida.')),
      );
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .snapshots(),
      builder: (context, userSnap) {
        if (userSnap.connectionState == ConnectionState.waiting &&
            !userSnap.hasData) {
          return const Scaffold(
            backgroundColor: PainelAdminTheme.fundoCanvas,
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final dados = userSnap.data?.data();
        if (dados == null) {
          return Scaffold(
            backgroundColor: PainelAdminTheme.fundoCanvas,
            body: const Center(child: Text('Perfil não encontrado.')),
          );
        }
        final perfil = perfilAdministrativoPainel(dados);
        if (!perfilPodeVerSolicitacoesSaque(perfil)) {
          return Scaffold(
            backgroundColor: PainelAdminTheme.fundoCanvas,
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'A fila de solicitações de saque PIX é visível apenas para '
                  'usuários Master (não inclui AdminCity).',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 15,
                    height: 1.4,
                    color: PainelAdminTheme.textoSecundario,
                  ),
                ),
              ),
            ),
          );
        }

        return _buildCorpoListaSaques(context);
      },
    );
  }

  Widget _cabecalhoPagina({
    required Color roxo,
    required int totalRegistos,
    required int pendentes,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: roxo.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(Icons.payments_outlined, color: roxo, size: 26),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    'Saques PIX',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: PainelAdminTheme.dashboardInk,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: PainelAdminTheme.dashboardBorder),
                    ),
                    child: Text(
                      '$totalRegistos registos',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: PainelAdminTheme.textoSecundario,
                      ),
                    ),
                  ),
                  if (pendentes > 0) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: PainelAdminTheme.laranja.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '$pendentes pendentes',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: PainelAdminTheme.laranja,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Controle de solicitações de saque PIX.',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  height: 1.45,
                  color: PainelAdminTheme.textoSecundario,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _kpiTile({
    required String valor,
    required String titulo,
    required String subtitulo,
    required Color accent,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: PainelAdminTheme.dashboardCard(
        borderColor: PainelAdminTheme.dashboardBorder,
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.insights_outlined, size: 22, color: accent),
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
                    color: PainelAdminTheme.dashboardInk,
                  ),
                ),
                Text(
                  titulo,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: PainelAdminTheme.textoSecundario,
                  ),
                ),
                Text(
                  subtitulo,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade500,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _faixaKpis({
    required int nPend,
    required int nPago,
    required int nRec,
    required double volume,
    required Color roxo,
  }) {
    return LayoutBuilder(
      builder: (context, c) {
        final wide = c.maxWidth >= 900;
        final tiles = [
          _kpiTile(
            valor: '$nPend',
            titulo: 'Pendentes',
            subtitulo: 'Respeitam o filtro de perfil',
            accent: PainelAdminTheme.laranja,
          ),
          _kpiTile(
            valor: '$nPago',
            titulo: 'Pagos',
            subtitulo: 'PIX confirmado',
            accent: const Color(0xFF15803D),
          ),
          _kpiTile(
            valor: '$nRec',
            titulo: 'Recusados',
            subtitulo: 'Com estorno',
            accent: const Color(0xFFB91C1C),
          ),
          _kpiTile(
            valor: _brl.format(volume),
            titulo: 'Volume (perfil)',
            subtitulo: 'Soma só dos pagos (filtro perfil)',
            accent: roxo,
          ),
        ];
        if (wide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < 4; i++) ...[
                if (i > 0) const SizedBox(width: 12),
                Expanded(child: tiles[i]),
              ],
            ],
          );
        }
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (var i = 0; i < 4; i++)
              SizedBox(
                width: (c.maxWidth - 12) / 2 > 160
                    ? (c.maxWidth - 12) / 2
                    : c.maxWidth,
                child: tiles[i],
              ),
          ],
        );
      },
    );
  }

  Widget _painelFiltroBloco({
    required String titulo,
    required Widget child,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          titulo,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
            color: PainelAdminTheme.textoSecundario,
          ),
        ),
        const SizedBox(height: 8),
        child,
      ],
    );
  }

  Widget _painelFiltros(Color roxo) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: PainelAdminTheme.dashboardCard(),
      child: _painelFiltroBloco(
        titulo: 'PERFIL',
        child: Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final e in [
              ('todos', 'Todos'),
              ('lojista', 'Lojistas'),
              ('entregador', 'Entregadores'),
            ])
              FilterChip(
                label: Text(e.$2),
                selected: _filtroTipo == e.$1,
                onSelected: (_) => setState(() {
                  _filtroTipo = e.$1;
                  _paginaAtual = 0;
                }),
                selectedColor: roxo.withValues(alpha: 0.15),
                checkmarkColor: roxo,
                labelStyle: GoogleFonts.plusJakartaSans(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide(
                    color: _filtroTipo == e.$1
                        ? roxo
                        : PainelAdminTheme.dashboardBorder,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  static final _fmtSoData = DateFormat('dd/MM/yyyy', 'pt_BR');

  Future<void> _pickData(BuildContext context, {required bool dataInicial}) async {
    final agora = DateTime.now();
    final primeiro = DateTime(2020);
    final ultimo = DateTime(agora.year + 2, 12, 31);
    final inicial = dataInicial
        ? (_filtroDataDe ?? agora)
        : (_filtroDataAte ?? agora);
    final r = await showDatePicker(
      context: context,
      initialDate: inicial,
      firstDate: primeiro,
      lastDate: ultimo,
      locale: const Locale('pt', 'BR'),
    );
    if (r == null || !mounted) return;
    setState(() {
      if (dataInicial) {
        _filtroDataDe = r;
      } else {
        _filtroDataAte = r;
      }
      _paginaAtual = 0;
    });
  }

  Widget _painelPesquisaEDatas(Color roxo) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: PainelAdminTheme.dashboardCard(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _pesquisaController,
            onChanged: (_) => setState(() => _paginaAtual = 0),
            decoration: InputDecoration(
              hintText:
                  'Pesquisar por nome do solicitante ou perfil (ex.: Lojista, Entregador)…',
              prefixIcon: Icon(Icons.search_rounded, color: roxo.withValues(alpha: 0.85)),
              suffixIcon: _pesquisaController.text.isNotEmpty
                  ? IconButton(
                      tooltip: 'Limpar',
                      icon: const Icon(Icons.clear_rounded),
                      onPressed: () {
                        _pesquisaController.clear();
                        setState(() => _paginaAtual = 0);
                      },
                    )
                  : null,
              filled: true,
              fillColor: const Color(0xFFF8FAFC),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: PainelAdminTheme.dashboardBorder),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: PainelAdminTheme.dashboardBorder),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: roxo, width: 1.5),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'Data da solicitação:',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: PainelAdminTheme.textoSecundario,
                ),
              ),
              OutlinedButton.icon(
                onPressed: () => _pickData(context, dataInicial: true),
                icon: const Icon(Icons.calendar_today_outlined, size: 18),
                label: Text(
                  _filtroDataDe == null
                      ? 'De (opcional)'
                      : 'De: ${_fmtSoData.format(_filtroDataDe!)}',
                ),
              ),
              OutlinedButton.icon(
                onPressed: () => _pickData(context, dataInicial: false),
                icon: const Icon(Icons.event_outlined, size: 18),
                label: Text(
                  _filtroDataAte == null
                      ? 'Até (opcional)'
                      : 'Até: ${_fmtSoData.format(_filtroDataAte!)}',
                ),
              ),
              if (_filtroDataDe != null || _filtroDataAte != null)
                TextButton(
                  onPressed: () => setState(() {
                    _filtroDataDe = null;
                    _filtroDataAte = null;
                    _paginaAtual = 0;
                  }),
                  child: const Text('Limpar datas'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _estadoSemResultadoPesquisa() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      decoration: PainelAdminTheme.dashboardCard(),
      child: Column(
        children: [
          Icon(
            Icons.search_off_rounded,
            size: 48,
            color: Colors.grey.shade400,
          ),
          const SizedBox(height: 16),
          Text(
            'Nenhum resultado para a pesquisa ou datas',
            textAlign: TextAlign.center,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: PainelAdminTheme.dashboardInk,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Ajuste o texto, limpe o campo ou altere o intervalo de datas.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: PainelAdminTheme.textoSecundario,
              fontSize: 14,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }

  Widget _barraPaginacao({
    required int totalItens,
    required int paginaZeroBased,
  }) {
    if (totalItens <= 0) return const SizedBox.shrink();
    final totalPaginas = (totalItens + _kItensPorPagina - 1) ~/ _kItensPorPagina;
    final p = min(paginaZeroBased, max(0, totalPaginas - 1));
    final ini = p * _kItensPorPagina + 1;
    final fim = min((p + 1) * _kItensPorPagina, totalItens);

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'Mostrando $ini–$fim de $totalItens',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              color: PainelAdminTheme.textoSecundario,
            ),
          ),
          const SizedBox(width: 16),
          IconButton.filledTonal(
            onPressed: p > 0
                ? () => setState(() => _paginaAtual = p - 1)
                : null,
            icon: const Icon(Icons.chevron_left_rounded),
            tooltip: 'Página anterior',
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              'Página ${p + 1} de $totalPaginas',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: PainelAdminTheme.dashboardInk,
              ),
            ),
          ),
          IconButton.filledTonal(
            onPressed: p < totalPaginas - 1
                ? () => setState(() => _paginaAtual = p + 1)
                : null,
            icon: const Icon(Icons.chevron_right_rounded),
            tooltip: 'Próxima página',
          ),
        ],
      ),
    );
  }

  Widget _estadoVazio({required bool baseVazia}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 56, horizontal: 24),
      decoration: PainelAdminTheme.dashboardCard(),
      child: Column(
        children: [
          Icon(
            Icons.folder_open_outlined,
            size: 48,
            color: Colors.grey.shade400,
          ),
          const SizedBox(height: 16),
          Text(
            baseVazia
                ? 'Sem solicitações de saque'
                : 'Nenhum resultado com estes filtros',
            textAlign: TextAlign.center,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: PainelAdminTheme.dashboardInk,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            baseVazia
                ? 'Novos pedidos de repasse PIX aparecerão nesta lista.'
                : 'Altere o filtro de perfil ou escolha "Todos".',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: PainelAdminTheme.textoSecundario,
              fontSize: 14,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }

  Widget _avisoFiltroVazio(int totalBase) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFED7AA)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.filter_alt_outlined, color: PainelAdminTheme.laranja, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Há $totalBase solicitações na base, mas nenhuma coincide com o filtro de perfil. '
              'Experimente "Todos".',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                height: 1.45,
                color: PainelAdminTheme.dashboardInk,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _celulaCabecalho(String t) {
    final w = Text(
      t.toUpperCase(),
      style: GoogleFonts.plusJakartaSans(
        fontSize: 10,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.9,
        color: PainelAdminTheme.textoSecundario,
      ),
    );
    return w;
  }

  Widget _linhaTabela({
    required BuildContext context,
    required QueryDocumentSnapshot<Map<String, dynamic>> doc,
    required Map<String, String> rolePorUid,
    required Map<String, String> nomePorUid,
    required Color roxo,
  }) {
    final d = doc.data();
    final valor = (d['valor'] as num?)?.toDouble() ?? 0;
    final status = _statusSaqueNormalizado(d);
    final tipo = _tipoEfetivo(d, rolePorUid);
    final tipoLabel = tipo == 'entregador'
        ? 'Entreg.'
        : tipo == 'lojista'
            ? 'Loja'
            : '—';
    final chave = d['chave_pix']?.toString().trim() ?? '';
    final uid = d['user_id']?.toString().trim() ?? '';
    final nomeSolic = uid.isNotEmpty ? (nomePorUid[uid] ?? '') : '';
    final ts = d['data_solicitacao'] as Timestamp?;
    final dataStr = ts != null ? _fmtDataHora.format(ts.toDate()) : '—';
    final chaveCurta = chave.length > 28 ? '${chave.substring(0, 26)}…' : chave;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _abrirDetalhesSaque(
          context,
          doc: doc,
          rolePorUid: rolePorUid,
          nomePorUid: nomePorUid,
          roxo: roxo,
        ),
        hoverColor: roxo.withValues(alpha: 0.04),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                flex: 3,
                child: Text(
                  dataStr,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: PainelAdminTheme.dashboardInk,
                  ),
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  tipoLabel,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    color: PainelAdminTheme.textoSecundario,
                  ),
                ),
              ),
              Expanded(
                flex: 3,
                child: Text(
                  nomeSolic.isEmpty ? '—' : nomeSolic,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    color: PainelAdminTheme.dashboardInk,
                  ),
                ),
              ),
              Expanded(
                flex: 2,
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text(
                    _formatarValorColunaTabela(valor),
                    textAlign: TextAlign.start,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                    style: _estiloValorColunaTabela(),
                  ),
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                flex: 2,
                child: Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: _badgeStatus(status),
                  ),
                ),
              ),
              Expanded(
                flex: 3,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        chaveCurta.isEmpty ? '—' : chaveCurta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          color: PainelAdminTheme.textoSecundario,
                        ),
                      ),
                    ),
                    if (chave.isNotEmpty)
                      IconButton(
                        tooltip: 'Copiar chave',
                        icon: Icon(Icons.copy_rounded, size: 18, color: roxo),
                        onPressed: () => _copiar(
                          context,
                          chave,
                          'Chave PIX copiada.',
                        ),
                      ),
                  ],
                ),
              ),
              SizedBox(
                width: 200,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (status == 'pendente') ...[
                      TextButton(
                        onPressed: () => _marcarPago(doc.id, valor),
                        style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFF15803D),
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                        child: const Text('Confirmar'),
                      ),
                      TextButton(
                        onPressed: () => _marcarRecusado(doc.id),
                        style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFFB91C1C),
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                        child: const Text('Recusar'),
                      ),
                    ] else
                      TextButton(
                        onPressed: () => _abrirDetalhesSaque(
                          context,
                          doc: doc,
                          rolePorUid: rolePorUid,
                          nomePorUid: nomePorUid,
                          roxo: roxo,
                        ),
                        child: const Text('Detalhes'),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _cardMobile({
    required BuildContext context,
    required QueryDocumentSnapshot<Map<String, dynamic>> doc,
    required Map<String, String> rolePorUid,
    required Map<String, String> nomePorUid,
    required Color roxo,
  }) {
    final d = doc.data();
    final valor = (d['valor'] as num?)?.toDouble() ?? 0;
    final status = _statusSaqueNormalizado(d);
    final tipo = _tipoEfetivo(d, rolePorUid);
    final tipoLabel = tipo == 'entregador'
        ? 'Entregador'
        : tipo == 'lojista'
            ? 'Lojista'
            : 'Perfil';
    final chave = d['chave_pix']?.toString().trim() ?? '';
    final ts = d['data_solicitacao'] as Timestamp?;
    final dataStr = ts != null ? _fmtDataHora.format(ts.toDate()) : '—';
    final uid = d['user_id']?.toString().trim() ?? '';
    final nomeSolic = uid.isNotEmpty ? (nomePorUid[uid] ?? '') : '';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: PainelAdminTheme.dashboardCard(),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _brl.format(valor),
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: PainelAdminTheme.dashboardInk,
                    ),
                  ),
                ),
                _badgeStatus(status),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '$dataStr · $tipoLabel',
              style: TextStyle(
                fontSize: 12,
                color: PainelAdminTheme.textoSecundario,
              ),
            ),
            if (nomeSolic.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                nomeSolic,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            if (chave.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      chave,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        color: PainelAdminTheme.textoSecundario,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.copy_rounded, size: 20, color: roxo),
                    onPressed: () =>
                        _copiar(context, chave, 'Chave PIX copiada.'),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.end,
              children: [
                OutlinedButton(
                  onPressed: () => _abrirDetalhesSaque(
                    context,
                    doc: doc,
                    rolePorUid: rolePorUid,
                    nomePorUid: nomePorUid,
                    roxo: roxo,
                  ),
                  child: const Text('Ver detalhes'),
                ),
                if (status == 'pendente') ...[
                  FilledButton(
                    onPressed: () => _marcarPago(doc.id, valor),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF15803D),
                    ),
                    child: const Text('Confirmar PIX'),
                  ),
                  OutlinedButton(
                    onPressed: () => _marcarRecusado(doc.id),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFB91C1C),
                    ),
                    child: const Text('Recusar'),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _tabelaOuCards({
    required BuildContext context,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    required Map<String, String> rolePorUid,
    required Map<String, String> nomePorUid,
    required Color roxo,
  }) {
    return LayoutBuilder(
      builder: (context, c) {
        final useTable = c.maxWidth >= 1000;
        if (!useTable) {
          return Column(
            children: [
              for (final doc in docs)
                _cardMobile(
                  context: context,
                  doc: doc,
                  rolePorUid: rolePorUid,
                  nomePorUid: nomePorUid,
                  roxo: roxo,
                ),
            ],
          );
        }
        return Container(
          decoration: PainelAdminTheme.dashboardCard(),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                color: const Color(0xFFF8FAFC),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  children: [
                    Expanded(flex: 3, child: _celulaCabecalho('Data / hora')),
                    Expanded(flex: 2, child: _celulaCabecalho('Perfil')),
                    Expanded(flex: 3, child: _celulaCabecalho('Solicitante')),
                    Expanded(flex: 2, child: _celulaCabecalho('Valor')),
                    const SizedBox(width: 20),
                    Expanded(
                      flex: 2,
                      child: Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: _celulaCabecalho('Estado'),
                      ),
                    ),
                    Expanded(flex: 3, child: _celulaCabecalho('Chave PIX')),
                    SizedBox(
                      width: 200,
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: _celulaCabecalho('Ações'),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, thickness: 1),
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: docs.length,
                separatorBuilder: (context, index) => const Divider(height: 1),
                itemBuilder: (_, i) => _linhaTabela(
                  context: context,
                  doc: docs[i],
                  rolePorUid: rolePorUid,
                  nomePorUid: nomePorUid,
                  roxo: roxo,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCorpoListaSaques(BuildContext context) {
    final roxo = PainelAdminTheme.roxo;

    return Scaffold(
      backgroundColor: PainelAdminTheme.fundoCanvas,
      floatingActionButton: const BotaoSuporteFlutuante(),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('saques_solicitacoes')
            .limit(500)
            .snapshots(),
        builder: (context, snap) {
          if (snap.hasError) {
            final err = snap.error.toString();
            final isPerm = err.contains('permission') ||
                err.contains('PERMISSION_DENIED');
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.error_outline, size: 48, color: Colors.red.shade700),
                    const SizedBox(height: 16),
                    SelectableText(
                      'Erro ao ler solicitações: $err',
                      textAlign: TextAlign.center,
                    ),
                    if (isPerm) ...[
                      const SizedBox(height: 16),
                      Text(
                        'Confirma em users/{uid} que role, tipo ou tipoUsuario é '
                        'master ou superadmin. AdminCity não vê esta fila.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey.shade700, height: 1.4),
                      ),
                    ],
                  ],
                ),
              ),
            );
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final ordenados = List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(
            snap.data!.docs,
          )..sort((a, b) {
              final ta = a.data()['data_solicitacao'];
              final tb = b.data()['data_solicitacao'];
              if (ta is! Timestamp) return 1;
              if (tb is! Timestamp) return -1;
              return tb.compareTo(ta);
            });

          final idsKey = ordenados.map((e) => e.id).join('|');
          if (_idsSaquesMetadadosKey != idsKey) {
            _idsSaquesMetadadosKey = idsKey;
            _futureMetadadosUsuarios = ordenados.isEmpty
                ? Future.value(
                    const _CacheUsuariosSaques(
                      rolePorUid: {},
                      nomePorUid: {},
                    ),
                  )
                : _obterMetadadosUsuarios(ordenados);
          }

          return FutureBuilder<_CacheUsuariosSaques>(
            future: _futureMetadadosUsuarios ??
                Future.value(
                  const _CacheUsuariosSaques(
                    rolePorUid: {},
                    nomePorUid: {},
                  ),
                ),
            builder: (context, roleSnap) {
              if (roleSnap.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (roleSnap.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: SelectableText(
                      'Erro ao carregar dados dos usuários: ${roleSnap.error}',
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              }
              final cache = roleSnap.data ??
                  const _CacheUsuariosSaques(
                    rolePorUid: {},
                    nomePorUid: {},
                  );
              final rolePorUid = cache.rolePorUid;
              final nomePorUid = cache.nomePorUid;

              final docs = ordenados.where((doc) {
                final m = doc.data();
                return _passaFiltroTipo(m, rolePorUid);
              }).toList();

              final docsFiltrados = docs
                  .where(
                    (doc) => _passaPesquisaEData(doc, rolePorUid, nomePorUid),
                  )
                  .toList();

              final tf = docsFiltrados.length;
              final totalPaginas =
                  tf == 0 ? 1 : (tf + _kItensPorPagina - 1) ~/ _kItensPorPagina;
              final pSafe = tf == 0 ? 0 : min(_paginaAtual, totalPaginas - 1);
              if (pSafe != _paginaAtual) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) {
                    setState(() => _paginaAtual = pSafe);
                  }
                });
              }
              final iniSlice = pSafe * _kItensPorPagina;
              final docsPagina = tf == 0
                  ? <QueryDocumentSnapshot<Map<String, dynamic>>>[]
                  : docsFiltrados.sublist(
                      iniSlice,
                      min(iniSlice + _kItensPorPagina, tf),
                    );

              var pendentes = 0;
              var nPago = 0;
              var nRec = 0;
              var totalVol = 0.0;
              for (final doc in ordenados) {
                final m = doc.data();
                if (!_passaFiltroTipo(m, rolePorUid)) continue;
                final st = _statusSaqueNormalizado(m);
                final v = (m['valor'] as num?)?.toDouble() ?? 0;
                if (st == 'pendente') {
                  pendentes++;
                } else if (st == 'pago') {
                  nPago++;
                  totalVol += v;
                } else if (st == 'recusado') {
                  nRec++;
                }
              }

              return SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1200),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _cabecalhoPagina(
                          roxo: roxo,
                          totalRegistos: ordenados.length,
                          pendentes: pendentes,
                        ),
                        const SizedBox(height: 24),
                        _faixaKpis(
                          nPend: pendentes,
                          nPago: nPago,
                          nRec: nRec,
                          volume: totalVol,
                          roxo: roxo,
                        ),
                        const SizedBox(height: 16),
                        _painelFiltros(roxo),
                        const SizedBox(height: 12),
                        _painelPesquisaEDatas(roxo),
                        const SizedBox(height: 16),
                        if (docs.isEmpty &&
                            ordenados.isNotEmpty &&
                            _filtroTipo != 'todos')
                          _avisoFiltroVazio(ordenados.length),
                        if (docs.isEmpty)
                          _estadoVazio(baseVazia: ordenados.isEmpty)
                        else if (docsFiltrados.isEmpty)
                          _estadoSemResultadoPesquisa()
                        else ...[
                          _tabelaOuCards(
                            context: context,
                            docs: docsPagina,
                            rolePorUid: rolePorUid,
                            nomePorUid: nomePorUid,
                            roxo: roxo,
                          ),
                          _barraPaginacao(
                            totalItens: tf,
                            paginaZeroBased: pSafe,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
