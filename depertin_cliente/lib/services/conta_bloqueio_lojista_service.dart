import 'package:cloud_firestore/cloud_firestore.dart';

import '../constants/conta_bloqueio_lojista.dart';

/// Bloqueio **operacional** (financeiro/admin) — distinto de recusa cadastral com [motivo_recusa].
class ContaBloqueioLojistaService {
  ContaBloqueioLojistaService._();

  static String _roleOf(Map<String, dynamic> data) =>
      (data['role'] ?? data['tipoUsuario'] ?? '').toString().toLowerCase();

  /// Lojista com bloqueio que **impede o painel** (não envia para correção de cadastro).
  static bool estaBloqueadoParaOperacoes(Map<String, dynamic> data) {
    if (_roleOf(data) != 'lojista') return false;
    return _bloqueioOperacionalEfetivo(data);
  }

  /// Texto que o lojista vê no overlay (mensagem administrativa ou legado em [motivo_recusa]).
  static String? textoMotivoBloqueio(Map<String, dynamic> d) {
    final m = d['motivo_bloqueio'];
    if (m != null && m.toString().trim().isNotEmpty) return m.toString().trim();
    if (!estaBloqueadoParaOperacoes(d)) return null;
    final mr = d['motivo_recusa']?.toString().trim() ?? '';
    if (mr.isEmpty) return null;
    return mr;
  }

  /// Recusa de cadastro (admin recusou pendência): correção no formulário — **não** é bloqueio operacional.
  /// Docs antigos sem [recusa_cadastro]: usa heurística em [motivo_recusa] (ex.: inadimplência ≠ recusa cadastral).
  static bool lojaRecusadaSomenteCorrecaoCadastro(Map<String, dynamic> d) {
    if (d['recusa_cadastro'] == true) return true;
    final sl = (d['status_loja'] ?? '').toString();
    if (sl != 'bloqueada' && sl != 'bloqueado') return false;
    if (d.containsKey('block_active')) return false;
    final motivo = d['motivo_recusa']?.toString().trim() ?? '';
    if (motivo.isEmpty) return false;
    if (_motivoPareceBloqueioOperacional(motivo)) return false;
    return true;
  }

  static bool _motivoPareceBloqueioOperacional(String motivo) {
    final s = motivo.toLowerCase();
    const keys = <String>[
      'pagamento',
      'inadimpl',
      'financeir',
      'suspens',
      'falta de pagamento',
      'produtos suspens',
      'cobrança',
      'cobranca',
      'mensalidade',
      'plano',
      'pendência financeira',
      'pendencia financeira',
      'regulariz',
      'débito',
      'debito',
    ];
    return keys.any((k) => s.contains(k));
  }

  static bool _bloqueioOperacionalEfetivo(Map<String, dynamic> d) {
    final sl = (d['status_loja'] ?? '').toString();

    if (lojaRecusadaSomenteCorrecaoCadastro(d)) {
      return false;
    }

    if (sl == ContaBloqueioLojista.statusLojaBloqueado) {
      return true;
    }

    if (sl == ContaBloqueioLojista.statusLojaBloqueioTemporario) {
      final end = d['block_end_at'];
      if (end is Timestamp && DateTime.now().isAfter(end.toDate())) {
        return false;
      }
      return true;
    }

    if (sl == 'bloqueada' || sl == 'bloqueado') {
      if (!d.containsKey('block_active')) {
        return true;
      }
    }

    if (d['block_active'] != true) return false;

    if (d['block_type']?.toString() == ContaBloqueioLojista.blockTemporary) {
      final end = d['block_end_at'];
      if (end is Timestamp && DateTime.now().isAfter(end.toDate())) {
        return false;
      }
    }
    return true;
  }

  /// Expira bloqueio temporário no Firestore.
  static Future<void> sincronizarLiberacaoSeExpirado(String uid) async {
    final ref = FirebaseFirestore.instance.collection('users').doc(uid);
    final snap = await ref.get();
    if (!snap.exists) return;
    final d = snap.data()!;
    if (_roleOf(d) != 'lojista') return;

    final sl = (d['status_loja'] ?? '').toString();
    final end = d['block_end_at'];
    final endTs = end is Timestamp ? end : null;
    final expirado =
        endTs != null && DateTime.now().isAfter(endTs.toDate());

    if (sl == ContaBloqueioLojista.statusLojaBloqueioTemporario && expirado) {
      await ref.update({
        'block_active': false,
        'status_conta': ContaBloqueioLojista.statusContaActive,
        'status_loja': ContaBloqueioLojista.statusLojaAtivo,
        'block_type': FieldValue.delete(),
        'block_reason': FieldValue.delete(),
        'block_start_at': FieldValue.delete(),
        'block_end_at': FieldValue.delete(),
        'motivo_bloqueio': FieldValue.delete(),
      });
      return;
    }

    if (d['block_active'] != true) return;
    if (d['block_type']?.toString() != ContaBloqueioLojista.blockTemporary) {
      return;
    }
    if (endTs == null || !expirado) return;

    await ref.update({
      'block_active': false,
      'status_conta': ContaBloqueioLojista.statusContaActive,
      'status_loja': ContaBloqueioLojista.statusLojaAtivo,
      'block_type': FieldValue.delete(),
      'block_reason': FieldValue.delete(),
      'block_start_at': FieldValue.delete(),
      'block_end_at': FieldValue.delete(),
      'motivo_bloqueio': FieldValue.delete(),
    });
  }

  /// Mensagem financeira vs administrativa (UI).
  static bool isBloqueioFinanceiro(Map<String, dynamic> d) {
    return d['block_type']?.toString() == ContaBloqueioLojista.blockFull &&
        d['block_reason']?.toString() ==
            ContaBloqueioLojista.motivoInadimplencia;
  }

  static bool isBloqueioTemporarioTipo(Map<String, dynamic> d) {
    return d['block_type']?.toString() == ContaBloqueioLojista.blockTemporary ||
        (d['status_loja'] ?? '').toString() ==
            ContaBloqueioLojista.statusLojaBloqueioTemporario;
  }

  static DateTime? dataFimBloqueio(Map<String, dynamic> d) {
    final end = d['block_end_at'] ?? d['data_fim_bloqueio'];
    if (end is Timestamp) return end.toDate();
    return null;
  }

}
