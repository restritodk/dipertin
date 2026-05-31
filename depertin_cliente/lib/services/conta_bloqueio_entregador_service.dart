import 'package:cloud_firestore/cloud_firestore.dart';

import '../constants/conta_bloqueio_lojista.dart';
import '../constants/entregador_perfil_operacional.dart';

/// Bloqueio operacional do entregador — campos [block_*] e [entregador_status].
class ContaBloqueioEntregadorService {
  ContaBloqueioEntregadorService._();

  static String _roleOf(Map<String, dynamic> data) =>
      (data['role'] ?? data['tipoUsuario'] ?? '').toString().toLowerCase();

  static bool estaBloqueadoParaOperacoes(Map<String, dynamic> data) {
    if (_roleOf(data) != 'entregador') return false;
    return _bloqueioOperacionalEfetivo(data);
  }

  /// Overlay em tela cheia (AppGuard, login) — bloqueio administrativo/financeiro.
  /// Bloqueios iniciados pelo entregador (pausa) usam UI no Radar / Área de Perigo.
  static bool deveExibirOverlayBloqueioEntregador(Map<String, dynamic> data) {
    if (!estaBloqueadoParaOperacoes(data)) return false;
    final reason = data['block_reason']?.toString();
    if (EntregadorPerfilOperacional.motivoEhIniciadoPeloEntregador(reason)) {
      return false;
    }
    return true;
  }

  static bool ehBloqueioIniciadoPeloEntregador(Map<String, dynamic> data) {
    final reason = data['block_reason']?.toString();
    return EntregadorPerfilOperacional.motivoEhIniciadoPeloEntregador(reason) &&
        data['block_origin']?.toString() == EntregadorPerfilOperacional.blockOriginSelf;
  }

  static bool ehExclusaoPerfilSolicitada(Map<String, dynamic> data) =>
      EntregadorPerfilOperacional.motivoEhExclusaoPerfil(
        data['block_reason']?.toString(),
      );

  static bool podeDesbloquearPeloProprioEntregador(Map<String, dynamic> data) {
    if (!estaBloqueadoParaOperacoes(data)) return false;
    if (ehExclusaoPerfilSolicitada(data)) return false;
    final reason = data['block_reason']?.toString();
    return data['block_origin']?.toString() ==
            EntregadorPerfilOperacional.blockOriginSelf &&
        (reason == EntregadorPerfilOperacional.motivoPausaTemporaria ||
            reason == EntregadorPerfilOperacional.motivoPausaDefinitiva);
  }

  static DateTime? dataExclusaoPerfilEfetiva(Map<String, dynamic> d) {
    final ts = d[EntregadorPerfilOperacional.campoExclusaoEfetivaEm];
    if (ts is Timestamp) return ts.toDate();
    return null;
  }

  static int? diasRestantesExclusaoPerfil(Map<String, dynamic> d) {
    final fim = dataExclusaoPerfilEfetiva(d);
    if (fim == null) return null;
    final diff = fim.difference(DateTime.now());
    if (diff.isNegative) return 0;
    return diff.inDays + (diff.inHours % 24 > 0 ? 1 : 0);
  }

  static String rotuloTipoBloqueio(Map<String, dynamic> d) =>
      EntregadorPerfilOperacional.rotuloTipoBloqueio(d);

  /// Após solicitar exclusão do perfil — impede novo cadastro de entregador no prazo.
  static bool reingressoEntregadorBloqueado(Map<String, dynamic> d) {
    final ate = d[EntregadorPerfilOperacional.campoReingressoBloqueadoAte];
    if (ate is Timestamp && DateTime.now().isBefore(ate.toDate())) {
      return true;
    }
    return false;
  }

  static DateTime? dataReingressoEntregadorLiberado(Map<String, dynamic> d) {
    final ate = d[EntregadorPerfilOperacional.campoReingressoBloqueadoAte];
    if (ate is Timestamp) return ate.toDate();
    return null;
  }

  static String? textoMotivoBloqueio(Map<String, dynamic> d) {
    final m = d['motivo_bloqueio'];
    if (m != null && m.toString().trim().isNotEmpty) return m.toString().trim();
    if (!estaBloqueadoParaOperacoes(d)) return null;
    final mr = d['motivo_recusa']?.toString().trim() ?? '';
    if (mr.isEmpty) return null;
    return mr;
  }

  static bool entregadorRecusadoSomenteCorrecaoCadastro(Map<String, dynamic> d) {
    if (d['recusa_cadastro'] == true) return true;
    final sl = (d['entregador_status'] ?? '').toString();
    if (sl != 'bloqueado' && sl != 'bloqueada') return false;
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
    final sl = (d['entregador_status'] ?? '').toString();

    if (entregadorRecusadoSomenteCorrecaoCadastro(d)) {
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

    if (sl == 'bloqueado' || sl == 'bloqueada') {
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

  static Future<void> sincronizarLiberacaoSeExpirado(String uid) async {
    final ref = FirebaseFirestore.instance.collection('users').doc(uid);
    final snap = await ref.get();
    if (!snap.exists) return;
    final d = snap.data()!;
    if (_roleOf(d) != 'entregador') return;

    final sl = (d['entregador_status'] ?? '').toString();
    final end = d['block_end_at'];
    final endTs = end is Timestamp ? end : null;
    final expirado =
        endTs != null && DateTime.now().isAfter(endTs.toDate());

    if (EntregadorPerfilOperacional.motivoEhExclusaoPerfil(
      d['block_reason']?.toString(),
    )) {
      return;
    }

    if (sl == ContaBloqueioLojista.statusLojaBloqueioTemporario && expirado) {
      await ref.update({
        'block_active': false,
        'status_conta': ContaBloqueioLojista.statusContaActive,
        'entregador_status': 'aprovado',
        EntregadorPerfilOperacional.campoPerfilOperacional:
            EntregadorPerfilOperacional.perfilAtivo,
        'block_type': FieldValue.delete(),
        'block_reason': FieldValue.delete(),
        EntregadorPerfilOperacional.campoBlockOrigin: FieldValue.delete(),
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
      'entregador_status': 'aprovado',
      EntregadorPerfilOperacional.campoPerfilOperacional:
          EntregadorPerfilOperacional.perfilAtivo,
      'block_type': FieldValue.delete(),
      'block_reason': FieldValue.delete(),
      EntregadorPerfilOperacional.campoBlockOrigin: FieldValue.delete(),
      'block_start_at': FieldValue.delete(),
      'block_end_at': FieldValue.delete(),
      'motivo_bloqueio': FieldValue.delete(),
    });
  }

  static bool isBloqueioFinanceiro(Map<String, dynamic> d) {
    return d['block_type']?.toString() == ContaBloqueioLojista.blockFull &&
        d['block_reason']?.toString() ==
            ContaBloqueioLojista.motivoInadimplencia;
  }

  static bool isBloqueioTemporarioTipo(Map<String, dynamic> d) {
    return d['block_type']?.toString() == ContaBloqueioLojista.blockTemporary ||
        (d['entregador_status'] ?? '').toString() ==
            ContaBloqueioLojista.statusLojaBloqueioTemporario;
  }

  static DateTime? dataFimBloqueio(Map<String, dynamic> d) {
    final end = d['block_end_at'] ?? d['data_fim_bloqueio'];
    if (end is Timestamp) return end.toDate();
    return null;
  }

  static DateTime? dataInicioBloqueio(Map<String, dynamic> d) {
    final s = d['block_start_at'];
    if (s is Timestamp) return s.toDate();
    return null;
  }
}
