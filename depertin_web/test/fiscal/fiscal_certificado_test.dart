import 'package:flutter_test/flutter_test.dart';

// Simula a lógica de verificação de certificado A1

enum CertStatus { valido, expirado, proximoVencimento, semCertificado }

class _CertResult {
  final bool podeEmitir;
  final String? motivo;
  final CertStatus status;
  final int diasRestantes;

  const _CertResult({
    required this.podeEmitir,
    this.motivo,
    required this.status,
    this.diasRestantes = 0,
  });
}

_CertResult _verificarCertificado({
  required DateTime? expiresAt,
  required bool temCertificado,
  int alertaDias = 30,
}) {
  if (!temCertificado || expiresAt == null) {
    return _CertResult(
      podeEmitir: false,
      motivo: 'Nenhum certificado digital A1 cadastrado',
      status: CertStatus.semCertificado,
    );
  }

  final now = DateTime.now();
  if (expiresAt.isBefore(now)) {
    return _CertResult(
      podeEmitir: false,
      motivo: 'Certificado digital vencido em ${expiresAt.toIso8601String().split('T')[0]}',
      status: CertStatus.expirado,
      diasRestantes: -now.difference(expiresAt).inDays,
    );
  }

  final diasRestantes = expiresAt.difference(now).inDays;
  if (diasRestantes <= alertaDias) {
    return _CertResult(
      podeEmitir: true,
      motivo: 'Certificado vence em $diasRestantes dias',
      status: CertStatus.proximoVencimento,
      diasRestantes: diasRestantes,
    );
  }

  return _CertResult(
    podeEmitir: true,
    status: CertStatus.valido,
    diasRestantes: diasRestantes,
  );
}

void main() {
  group('Bloqueio por Certificado Vencido', () {
    test('deve permitir emissão com certificado válido', () {
      final expiresAt = DateTime.now().add(const Duration(days: 365));
      final result = _verificarCertificado(
        expiresAt: expiresAt,
        temCertificado: true,
      );
      expect(result.podeEmitir, isTrue);
      expect(result.status, equals(CertStatus.valido));
    });

    test('deve bloquear emissão com certificado vencido', () {
      final expiresAt = DateTime.now().subtract(const Duration(days: 1));
      final result = _verificarCertificado(
        expiresAt: expiresAt,
        temCertificado: true,
      );
      expect(result.podeEmitir, isFalse);
      expect(result.status, equals(CertStatus.expirado));
    });

    test('deve bloquear emissão sem certificado', () {
      final result = _verificarCertificado(
        expiresAt: null,
        temCertificado: false,
      );
      expect(result.podeEmitir, isFalse);
      expect(result.status, equals(CertStatus.semCertificado));
    });

    test('deve alertar quando certificado está próximo do vencimento', () {
      final expiresAt = DateTime.now().add(const Duration(days: 15));
      final result = _verificarCertificado(
        expiresAt: expiresAt,
        temCertificado: true,
        alertaDias: 30,
      );
      expect(result.podeEmitir, isTrue);
      expect(result.status, equals(CertStatus.proximoVencimento));
      expect(result.diasRestantes, equals(15));
    });

    test('deve permitir emissão com certificado válido mesmo próximo do fim', () {
      final expiresAt = DateTime.now().add(const Duration(days: 5));
      final result = _verificarCertificado(
        expiresAt: expiresAt,
        temCertificado: true,
        alertaDias: 30,
      );
      expect(result.podeEmitir, isTrue); // Ainda não venceu
      expect(result.status, equals(CertStatus.proximoVencimento));
    });

    test('deve bloquear certificado vencido há muitos dias', () {
      final expiresAt = DateTime.now().subtract(const Duration(days: 365));
      final result = _verificarCertificado(
        expiresAt: expiresAt,
        temCertificado: true,
      );
      expect(result.podeEmitir, isFalse);
      expect(result.status, equals(CertStatus.expirado));
      expect(result.diasRestantes, equals(-365));
    });
  });
}
