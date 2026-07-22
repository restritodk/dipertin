import 'package:flutter_test/flutter_test.dart';
import 'package:depertin_web/services/fiscal/fiscal_validator.dart';
import 'package:depertin_web/services/fiscal/fiscal_payload.dart';

void main() {
  group('FiscalValidator — Validação de payload NF-e', () {
    late FiscalEmitente emitenteValido;
    late FiscalDestinatario destinatarioValido;
    late FiscalItem itemValido;
    late FiscalTotais totaisValidos;
    late FiscalPagamento pagamentoValido;

    setUp(() {
      emitenteValido = FiscalEmitente(
        razaoSocial: 'Loja Teste LTDA',
        nomeFantasia: 'Loja Teste',
        cnpj: '11222333000181',
        ie: '123456789',
        crt: '3',
        regimeTributario: 'Regime Normal',
        logradouro: 'Rua Teste',
        numero: '123',
        bairro: 'Centro',
        cidade: 'São Paulo',
        uf: 'SP',
        cep: '01001000',
      );
      destinatarioValido = FiscalDestinatario(
        nome: 'Cliente Teste',
        cpfCnpj: '52998224725',
        logradouro: 'Av Teste',
        numero: '456',
        bairro: 'Jardim',
        cidade: 'São Paulo',
        uf: 'SP',
        cep: '02002000',
      );
      itemValido = FiscalItem(
        descricao: 'Produto Teste',
        ncm: '84713012',
        cfop: '5102',
        cstIcms: '00',
        quantidade: 1.0,
        valorUnitario: 100.0,
        valorTotal: 100.0,
        unidade: 'UN',
      );
      totaisValidos = FiscalTotais(
        baseCalculoIcms: 100.0,
        valorIcms: 18.0,
        valorProdutos: 100.0,
        valorFrete: 0,
        valorDesconto: 0,
        valorTotal: 100.0,
      );
      pagamentoValido = FiscalPagamento(
        formaPagamento: '01',
        valorPago: 100.0,
      );
    });

    test('deve validar payload completo e válido', () {
      final payload = FiscalPayload(
        tipoDocumento: TipoDocumentoFiscal.nfe,
        emitente: emitenteValido,
        destinatario: destinatarioValido,
        itens: [itemValido],
        totais: totaisValidos,
        pagamento: pagamentoValido,
        naturezaOperacao: 'Venda de mercadoria',
      );
      final result = FiscalValidator.validarParaEmissao(payload);
      expect(result.valido, isTrue);
      expect(result.erros, isEmpty);
    });

    test('deve rejeitar emitente sem CNPJ (vazio)', () {
      final payload = FiscalPayload(
        tipoDocumento: TipoDocumentoFiscal.nfe,
        emitente: FiscalEmitente(
          razaoSocial: 'Loja Teste',
          nomeFantasia: 'Loja',
          cnpj: '', // CNPJ vazio
          ie: '123456789',
          logradouro: 'Rua',
          numero: '1',
          bairro: 'Centro',
          cidade: 'SP',
          uf: 'SP',
          cep: '01001000',
        ),
        destinatario: destinatarioValido,
        itens: [itemValido],
        totais: totaisValidos,
        pagamento: pagamentoValido,
      );
      final result = FiscalValidator.validarParaEmissao(payload);
      expect(result.valido, isFalse);
      expect(result.erros.length, greaterThanOrEqualTo(1));
    });

    test('deve rejeitar payload sem itens', () {
      final payload = FiscalPayload(
        tipoDocumento: TipoDocumentoFiscal.nfe,
        emitente: emitenteValido,
        destinatario: destinatarioValido,
        itens: [],
        totais: totaisValidos,
        pagamento: pagamentoValido,
      );
      final result = FiscalValidator.validarParaEmissao(payload);
      expect(result.valido, isFalse);
    });

    test('deve rejeitar natureza operação vazia', () {
      final payload = FiscalPayload(
        tipoDocumento: TipoDocumentoFiscal.nfe,
        emitente: emitenteValido,
        destinatario: destinatarioValido,
        itens: [itemValido],
        totais: totaisValidos,
        pagamento: pagamentoValido,
        naturezaOperacao: '',
      );
      final result = FiscalValidator.validarParaEmissao(payload);
      expect(result.valido, isFalse);
      expect(result.erros.any((e) => e.campo.contains('natureza_operacao')), isTrue);
    });

    test('deve aceitar emitente MEI com IE isenta (ie vazia)', () {
      final payload = FiscalPayload(
        tipoDocumento: TipoDocumentoFiscal.nfe,
        emitente: FiscalEmitente(
          razaoSocial: 'Fran Artesanatos MEI',
          nomeFantasia: 'Fran Artesanatos',
          cnpj: '66918730000184',
          ie: '',
          ieIsento: true,
          crt: '1',
          regimeTributario: 'MEI',
          logradouro: 'Avenida das Andorinhas',
          numero: '10',
          bairro: 'Parque Residencial Universitário',
          cidade: 'Rondonópolis',
          uf: 'MT',
          cep: '78750235',
          codigoCidade: '5107602',
        ),
        destinatario: destinatarioValido,
        itens: [itemValido],
        totais: totaisValidos,
        pagamento: pagamentoValido,
        naturezaOperacao: 'Venda de mercadoria',
      );
      final result = FiscalValidator.validarParaEmissao(payload);
      expect(result.valido, isTrue);
      expect(
        result.erros.where((e) => e.campo == 'emitente.ie'),
        isEmpty,
      );
    });

    test('deve aceitar emitente sem nome fantasia (só razão social)', () {
      final payload = FiscalPayload(
        tipoDocumento: TipoDocumentoFiscal.nfe,
        emitente: FiscalEmitente(
          razaoSocial: 'Eurico dos Santos Mota',
          nomeFantasia: '',
          cnpj: '66918730000184',
          ie: '',
          ieIsento: true,
          crt: '1',
          regimeTributario: 'MEI',
          logradouro: 'Avenida das Andorinhas',
          numero: '10',
          bairro: 'Parque Residencial Universitário',
          cidade: 'Rondonópolis',
          uf: 'MT',
          cep: '78750235',
          codigoCidade: '5107602',
        ),
        destinatario: destinatarioValido,
        itens: [itemValido],
        totais: totaisValidos,
        pagamento: pagamentoValido,
        naturezaOperacao: 'Venda de mercadoria',
      );
      final result = FiscalValidator.validarParaEmissao(payload);
      expect(result.valido, isTrue);
      expect(
        result.erros.where((e) => e.campo.contains('fantasia')),
        isEmpty,
      );
    });

    test('resolverIeIsentoEmitente detecta MEI sem IE', () {
      expect(
        resolverIeIsentoEmitente({
          'regime_tributario': 'MEI',
          'ie': '',
        }),
        isTrue,
      );
      expect(
        resolverIeIsentoEmitente({
          'ie_isento': true,
          'ie': '',
        }),
        isTrue,
      );
      expect(
        resolverIeIsentoEmitente({
          'regime_tributario': 'Regime Normal',
          'ie': '',
        }),
        isFalse,
      );
    });
  });
}
