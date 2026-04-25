// Arquivo: test/constants/tipos_entrega_test.dart (painel web)
//
// Espelho do teste do app mobile. O arquivo
// `depertin_web/lib/constants/tipos_entrega.dart` é uma cópia literal de
// `depertin_cliente/lib/constants/tipos_entrega.dart` — os dois precisam
// se manter sincronizados, e este teste é a rede de segurança.
//
// Se algum teste falhar aqui mas passar no mobile (ou vice-versa) é sinal
// forte de que os constants divergiram e precisam ser realinhados. O mesmo
// vale para o helper Node `depertin_cliente/functions/tipos_entrega.js` —
// qualquer mudança de regra de negócio aqui precisa ser replicada lá.

import 'package:flutter_test/flutter_test.dart';
import 'package:depertin_web/constants/tipos_entrega.dart';

void main() {
  group('TiposEntrega.normalizarLista', () {
    test('descarta valores fora do set canônico', () {
      final r = TiposEntrega.normalizarLista(
        <dynamic>['moto', 'drone', 'carro', null, 123, 'BICICLETA'],
      );
      expect(r, <String>['bicicleta', 'moto', 'carro']);
    });

    test('ordena por hierarquia ascendente', () {
      final r = TiposEntrega.normalizarLista(
        <dynamic>['carro_frete', 'bicicleta', 'carro', 'moto'],
      );
      expect(r, <String>['bicicleta', 'moto', 'carro', 'carro_frete']);
    });

    test('lista vazia para null ou não-iterável', () {
      expect(TiposEntrega.normalizarLista(null), const <String>[]);
      expect(TiposEntrega.normalizarLista(42), const <String>[]);
    });
  });

  group('TiposEntrega.maiorTipoDaLista', () {
    test('null para lista vazia', () {
      expect(TiposEntrega.maiorTipoDaLista(const <String>[]), isNull);
    });

    test('retorna o tipo de maior hierarquia', () {
      expect(
        TiposEntrega.maiorTipoDaLista(const ['moto', 'carro']),
        'carro',
      );
      expect(
        TiposEntrega.maiorTipoDaLista(
          const ['bicicleta', 'moto', 'carro', 'carro_frete'],
        ),
        'carro_frete',
      );
    });
  });

  group('TiposEntrega.compativel', () {
    test('loja sem config aceita qualquer entregador', () {
      expect(TiposEntrega.compativel('moto', const <String>[]), isTrue);
    });

    test('loja só carro_frete filtra motoboy', () {
      expect(
        TiposEntrega.compativel('moto', const ['carro_frete']),
        isFalse,
      );
      expect(
        TiposEntrega.compativel('carro_frete', const ['carro_frete']),
        isTrue,
      );
    });
  });

  group('TiposEntrega.defaultLegado (Opção B)', () {
    test('sem volumoso → [moto]', () {
      expect(
        TiposEntrega.defaultLegado(temProdutoRequerVeiculoGrande: false),
        const <String>['moto'],
      );
    });

    test('com volumoso → [carro, carro_frete]', () {
      expect(
        TiposEntrega.defaultLegado(temProdutoRequerVeiculoGrande: true),
        const <String>['carro', 'carro_frete'],
      );
    });

    test('bike nunca entra em default', () {
      expect(
        TiposEntrega.defaultLegado(temProdutoRequerVeiculoGrande: false),
        isNot(contains('bicicleta')),
      );
      expect(
        TiposEntrega.defaultLegado(temProdutoRequerVeiculoGrande: true),
        isNot(contains('bicicleta')),
      );
    });
  });

  group('Hierarquia e tabelas', () {
    test('bike(1)<moto(2)<carro(3)<frete(4)', () {
      expect(TiposEntrega.hierarquia['bicicleta'], 1);
      expect(TiposEntrega.hierarquia['moto'], 2);
      expect(TiposEntrega.hierarquia['carro'], 3);
      expect(TiposEntrega.hierarquia['carro_frete'], 4);
    });

    test('cadeiaFallbackTabela carro_frete cobre 3 níveis', () {
      expect(
        TiposEntrega.cadeiaFallbackTabela[TiposEntrega.codCarroFrete],
        const <String>['carro_frete', 'carro', 'padrao'],
      );
    });

    test('moto e bike usam tabela `padrao`', () {
      expect(TiposEntrega.tabelaFretePorTipo['moto'], 'padrao');
      expect(TiposEntrega.tabelaFretePorTipo['bicicleta'], 'padrao');
    });
  });

  group('TiposEntrega.lerDeDoc', () {
    test('null → lista vazia', () {
      expect(TiposEntrega.lerDeDoc(null), const <String>[]);
    });

    test('lê e normaliza', () {
      final r = TiposEntrega.lerDeDoc(<String, dynamic>{
        'tipos_entrega_permitidos': <dynamic>['CARRO', 'moto'],
      });
      expect(r, const <String>['moto', 'carro']);
    });
  });
}
