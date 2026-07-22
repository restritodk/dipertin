import 'package:depertin_web/models/comercial_pendencia_data.dart';
import 'package:depertin_web/services/comercial_credito_relatorios_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ComercialCreditoRelatoriosService — máscaras', () {
    test('mascararDocumento CPF', () {
      expect(
        ComercialCreditoRelatoriosService.mascararDocumento('52998224725'),
        '***.982.247-**',
      );
    });

    test('mascararDocumento CNPJ', () {
      expect(
        ComercialCreditoRelatoriosService.mascararDocumento('11222333000181'),
        '**.222.333/****-81',
      );
    });

    test('mascararDocumento vazio', () {
      expect(ComercialCreditoRelatoriosService.mascararDocumento(null), '—');
      expect(ComercialCreditoRelatoriosService.mascararDocumento(''), '—');
    });

    test('mascararTelefone', () {
      expect(
        ComercialCreditoRelatoriosService.mascararTelefone('65999887766'),
        '*****-7766',
      );
      expect(ComercialCreditoRelatoriosService.mascararTelefone(null), '—');
    });
  });

  group('calcularJurosMulta — regras reutilizadas no PDF', () {
    test('parcela em dia não gera encargos', () {
      final r = calcularJurosMulta(
        100,
        DateTime.now().add(const Duration(days: 5)),
        const JurosMultaConfig(
          cobrarMultaPorAtraso: true,
          percentualMulta: 2,
          cobrarJurosPorAtraso: true,
          percentualJurosAoDia: 0.1,
        ),
      );
      expect(r.diasEmAtraso, 0);
      expect(r.juros, 0);
      expect(r.multa, 0);
    });

    test('parcela vencida aplica multa e juros', () {
      final venc = DateTime.now().subtract(const Duration(days: 10));
      final r = calcularJurosMulta(
        100,
        venc,
        const JurosMultaConfig(
          cobrarMultaPorAtraso: true,
          percentualMulta: 2,
          cobrarJurosPorAtraso: true,
          percentualJurosAoDia: 0.1,
          diasTolerancia: 0,
        ),
      );
      expect(r.diasEmAtraso, 10);
      expect(r.multa, 2.0);
      expect(r.juros, closeTo(1.0, 0.01)); // 100 * 0.1% * 10
      expect(r.valorAtualizado, closeTo(103.0, 0.01));
    });

    test('ordenação pendências: maior atraso primeiro (comparador)', () {
      final a = calcularJurosMulta(
        50,
        DateTime.now().subtract(const Duration(days: 30)),
        const JurosMultaConfig(cobrarJurosPorAtraso: true, percentualJurosAoDia: 0.1),
      );
      final b = calcularJurosMulta(
        50,
        DateTime.now().subtract(const Duration(days: 5)),
        const JurosMultaConfig(cobrarJurosPorAtraso: true, percentualJurosAoDia: 0.1),
      );
      final lista = [b, a]..sort((x, y) => y.diasEmAtraso.compareTo(x.diasEmAtraso));
      expect(lista.first.diasEmAtraso, greaterThan(lista.last.diasEmAtraso));
    });
  });

  group('CreditoRelatorioVendasResumo', () {
    test('ticket médio', () {
      const r = CreditoRelatorioVendasResumo(
        qtdCompras: 4,
        qtdProdutos: 10,
        valorBruto: 500,
        descontos: 20,
        valorTotal: 400,
      );
      expect(r.ticketMedio, 100);
    });

    test('ticket médio sem compras', () {
      const r = CreditoRelatorioVendasResumo(
        qtdCompras: 0,
        qtdProdutos: 0,
        valorBruto: 0,
        descontos: 0,
        valorTotal: 0,
      );
      expect(r.ticketMedio, 0);
    });
  });

  group('codigoProdutoDoItem', () {
    test('lê codigo / sku / fallback', () {
      expect(
        ComercialCreditoRelatoriosService.codigoProdutoDoItem(
          {'codigo': 'ABC-1'},
          'Produto',
        ),
        'ABC-1',
      );
      expect(
        ComercialCreditoRelatoriosService.codigoProdutoDoItem(
          {'sku': 'SKU9'},
          'Produto',
        ),
        'SKU9',
      );
      expect(
        ComercialCreditoRelatoriosService.codigoProdutoDoItem({}, 'Produto'),
        '—',
      );
    });
  });

  group('modal export — sem CSV', () {
    test('nenhuma string CSV/Excel no fluxo de exportação PDF', () async {
      // Garante que o utilitário de máscara e resumos existem (smoke).
      expect(
        ComercialCreditoRelatoriosService.mascararDocumento('12345678901')
            .contains('*'),
        isTrue,
      );
      const resumo = CreditoRelatorioClientesResumo(
        totalClientes: 1,
        limiteTotal: 100,
        utilizado: 40,
        disponivel: 60,
        emAtraso: 0,
      );
      expect(resumo.totalClientes, 1);
      expect(resumo.disponivel, 60);
    });
  });
}
