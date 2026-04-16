/// Tipos e constantes de bloqueio de conta (lojista) — alinhado ao painel master.
class ContaBloqueioLojista {
  ContaBloqueioLojista._();

  static const String blockFull = 'BLOCK_FULL';
  static const String blockTemporary = 'BLOCK_TEMPORARY';

  static const String motivoInadimplencia = 'INADIMPLENCIA';
  static const String motivoOutros = 'OUTROS';

  static const String statusContaActive = 'ACTIVE';
  static const String statusContaBlocked = 'BLOCKED';
  static const String statusContaSuspended = 'SUSPENDED';

  /// `status_loja` — operação da loja (painel / vitrine).
  static const String statusLojaAtivo = 'ativo';
  static const String statusLojaBloqueado = 'bloqueado';
  static const String statusLojaBloqueioTemporario = 'bloqueio_temporario';

  /// WhatsApp institucional (mesmo padrão da vitrine — suporte ao lojista).
  static const String suporteWhatsAppDigits = '5566992244000';

  static const String mensagemWhatsAppPadrao =
      'Olá, preciso de suporte referente ao bloqueio da minha conta.';
}
