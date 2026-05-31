/// Bloqueio e exclusão do perfil de entregador (iniciado pelo próprio entregador).
/// Campos Firestore reutilizam [block_*] e [entregador_status] do painel admin.
abstract class EntregadorPerfilOperacional {
  EntregadorPerfilOperacional._();

  static const String blockOriginSelf = 'self';
  static const String blockOriginAdmin = 'admin';

  /// Valores de [block_reason] — distintos de INADIMPLENCIA/OUTROS (admin).
  static const String motivoPausaTemporaria = 'PAUSA_TEMPORARIA_ENTREGADOR';
  static const String motivoPausaDefinitiva = 'PAUSA_DEFINITIVA_ENTREGADOR';
  static const String motivoExclusaoPerfil = 'EXCLUSAO_PERFIL_ENTREGADOR';

  /// Campo [entregador_perfil_operacional] — exibição painel / app.
  static const String perfilAtivo = 'ativo';
  static const String perfilBloqueadoTemporario = 'bloqueado_temporario';
  static const String perfilBloqueadoDefinitivo = 'bloqueado_definitivo';
  static const String perfilExclusaoSolicitada = 'exclusao_solicitada';
  static const String perfilRemovido = 'perfil_removido';

  static const String campoPerfilOperacional = 'entregador_perfil_operacional';
  static const String campoBlockOrigin = 'block_origin';
  static const String campoExclusaoSolicitadaEm = 'entregador_exclusao_perfil_solicitada_em';
  static const String campoExclusaoEfetivaEm = 'entregador_exclusao_perfil_em';
  static const String campoReingressoBloqueadoAte = 'entregador_reingresso_bloqueado_ate';
  static const String campoPerfilRemovidoEm = 'entregador_perfil_removido_em';

  static const int diasCarenciaExclusaoPerfil = 30;
  static const int diasCarenciaReingressoEntregador = 30;

  static bool motivoEhIniciadoPeloEntregador(String? reason) {
    final r = reason?.toString() ?? '';
    return r == motivoPausaTemporaria ||
        r == motivoPausaDefinitiva ||
        r == motivoExclusaoPerfil;
  }

  static bool motivoEhExclusaoPerfil(String? reason) =>
      reason?.toString() == motivoExclusaoPerfil;

  static String rotuloTipoBloqueio(Map<String, dynamic> d) {
    final reason = d['block_reason']?.toString();
    if (motivoEhExclusaoPerfil(reason)) {
      return 'Solicitação de exclusão';
    }
    if (reason == motivoPausaTemporaria) {
      return 'Bloqueio temporário (entregador)';
    }
    if (reason == motivoPausaDefinitiva) {
      return 'Bloqueio definitivo (entregador)';
    }
    final tipo = d['block_type']?.toString();
    if (tipo == 'BLOCK_TEMPORARY' ||
        (d['entregador_status'] ?? '') == 'bloqueio_temporario') {
      return 'Bloqueio temporário';
    }
    if (d['block_reason']?.toString() == 'INADIMPLENCIA') {
      return 'Inadimplência';
    }
    if (d['block_active'] == true) {
      return 'Bloqueio administrativo';
    }
    return 'Bloqueado';
  }
}
