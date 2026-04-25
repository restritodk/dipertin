// Arquivo: test/constants/tipos_entrega_test.dart
//
// Testes unitários puros da classe `TiposEntrega` (sem Firebase). Cobre:
//  - normalização de lista vinda do Firestore
//  - cálculo do maior tipo (base de frete)
//  - compatibilidade entrega × loja (usada no filtro de despacho)
//  - default conservador para lojas legado
//  - cadeia de fallback de tabela de frete
//  - leitura direta de mapa (lerDeDoc)
//
// Estes testes protegem o contrato compartilhado entre client, painel web e
// Cloud Functions: os 3 builds implementam a mesma lógica em linguagens
// diferentes (Dart × Dart × Node). Qualquer mudança aqui precisa ser
// replicada em `depertin_web/lib/constants/tipos_entrega.dart` e
// `depertin_cliente/functions/tipos_entrega.js`.

import 'package:flutter_test/flutter_test.dart';
import 'package:depertin_cliente/constants/tipos_entrega.dart';

void main() {
  group('TiposEntrega.normalizarLista', () {
    test('descarta valores fora do set canônico', () {
      final r = TiposEntrega.normalizarLista(
        <dynamic>['moto', 'drone', 'carro', null, 123, 'BICICLETA'],
      );
      expect(r, <String>['bicicleta', 'moto', 'carro']);
    });

    test('remove duplicatas e aplica lower-case', () {
      final r = TiposEntrega.normalizarLista(
        <dynamic>['MOTO', 'moto', 'Moto', 'carro', 'carro'],
      );
      expect(r, <String>['moto', 'carro']);
    });

    test('ordena por hierarquia ascendente (bike→moto→carro→frete)', () {
      final r = TiposEntrega.normalizarLista(
        <dynamic>['carro_frete', 'bicicleta', 'carro', 'moto'],
      );
      expect(r, <String>['bicicleta', 'moto', 'carro', 'carro_frete']);
    });

    test('retorna lista vazia para null ou não-iterável', () {
      expect(TiposEntrega.normalizarLista(null), const <String>[]);
      expect(TiposEntrega.normalizarLista(42), const <String>[]);
      expect(TiposEntrega.normalizarLista('moto'), const <String>[]);
    });
  });

  group('TiposEntrega.maiorTipoDaLista', () {
    test('retorna null para lista vazia', () {
      expect(TiposEntrega.maiorTipoDaLista(const <String>[]), isNull);
    });

    test('moto < carro < carro_frete', () {
      expect(
        TiposEntrega.maiorTipoDaLista(const ['bicicleta', 'moto']),
        'moto',
      );
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

    test('retorna o único item quando a lista tem tamanho 1', () {
      expect(
        TiposEntrega.maiorTipoDaLista(const ['bicicleta']),
        'bicicleta',
      );
    });
  });

  group('TiposEntrega.compativel (filtro de despacho)', () {
    test('loja sem config (legado) aceita qualquer entregador', () {
      expect(TiposEntrega.compativel('moto', const <String>[]), isTrue);
      expect(TiposEntrega.compativel('bicicleta', const <String>[]), isTrue);
      expect(TiposEntrega.compativel('', const <String>[]), isTrue);
    });

    test('loja que só aceita carro_frete filtra motoboy', () {
      expect(
        TiposEntrega.compativel('moto', const ['carro_frete']),
        isFalse,
      );
      expect(
        TiposEntrega.compativel('carro_frete', const ['carro_frete']),
        isTrue,
      );
    });

    test('loja com múltiplos tipos aceita qualquer um da lista', () {
      const aceitos = ['bicicleta', 'moto', 'carro'];
      expect(TiposEntrega.compativel('bicicleta', aceitos), isTrue);
      expect(TiposEntrega.compativel('moto', aceitos), isTrue);
      expect(TiposEntrega.compativel('carro', aceitos), isTrue);
      expect(TiposEntrega.compativel('carro_frete', aceitos), isFalse);
    });
  });

  group('TiposEntrega.defaultLegado (Opção B — conservador)', () {
    test('sem produto volumoso → apenas [moto] (preserva pré-migração)', () {
      expect(
        TiposEntrega.defaultLegado(temProdutoRequerVeiculoGrande: false),
        const <String>['moto'],
      );
    });

    test('com produto volumoso → [carro, carro_frete]', () {
      expect(
        TiposEntrega.defaultLegado(temProdutoRequerVeiculoGrande: true),
        const <String>['carro', 'carro_frete'],
      );
    });

    test('bicicleta NÃO entra em default (opt-in explícito do lojista)', () {
      final sem = TiposEntrega.defaultLegado(
        temProdutoRequerVeiculoGrande: false,
      );
      final com = TiposEntrega.defaultLegado(
        temProdutoRequerVeiculoGrande: true,
      );
      expect(sem, isNot(contains('bicicleta')));
      expect(com, isNot(contains('bicicleta')));
    });
  });

  group('TiposEntrega.cadeiaFallbackTabela', () {
    test('carro_frete → carro_frete → carro → padrao', () {
      expect(
        TiposEntrega.cadeiaFallbackTabela[TiposEntrega.codCarroFrete],
        const <String>['carro_frete', 'carro', 'padrao'],
      );
    });

    test('carro → carro → padrao', () {
      expect(
        TiposEntrega.cadeiaFallbackTabela[TiposEntrega.codCarro],
        const <String>['carro', 'padrao'],
      );
    });

    test('moto e bicicleta caem em padrao diretamente', () {
      expect(
        TiposEntrega.cadeiaFallbackTabela[TiposEntrega.codMoto],
        const <String>['padrao'],
      );
      expect(
        TiposEntrega.cadeiaFallbackTabela[TiposEntrega.codBicicleta],
        const <String>['padrao'],
      );
    });
  });

  group('TiposEntrega.lerDeDoc', () {
    test('retorna vazio para null', () {
      expect(TiposEntrega.lerDeDoc(null), const <String>[]);
    });

    test('retorna vazio se o campo não existir', () {
      expect(
        TiposEntrega.lerDeDoc(<String, dynamic>{'outra_coisa': true}),
        const <String>[],
      );
    });

    test('lê e normaliza quando campo existe', () {
      final r = TiposEntrega.lerDeDoc(<String, dynamic>{
        'tipos_entrega_permitidos': <dynamic>['CARRO', 'moto', 'bicicleta'],
      });
      expect(r, const <String>['bicicleta', 'moto', 'carro']);
    });

    test('respeita o parâmetro `campo` customizado', () {
      final r = TiposEntrega.lerDeDoc(
        <String, dynamic>{'meu_campo': <dynamic>['moto']},
        campo: 'meu_campo',
      );
      expect(r, const <String>['moto']);
    });
  });

  group('TiposEntrega.paraFirestore', () {
    test('normaliza antes de persistir (evita lixo no Firestore)', () {
      final r = TiposEntrega.paraFirestore(
        const <String>['CARRO', 'moto', 'moto', 'drone'],
      );
      expect(r, const <String>['moto', 'carro']);
    });
  });

  group('TiposEntrega.normalizarTipoVeiculo (paridade com backend)', () {
    test('retorna vazio para null, string vazia e lixo', () {
      expect(TiposEntrega.normalizarTipoVeiculo(null), '');
      expect(TiposEntrega.normalizarTipoVeiculo(''), '');
      expect(TiposEntrega.normalizarTipoVeiculo('   '), '');
      expect(TiposEntrega.normalizarTipoVeiculo('drone'), '');
      expect(TiposEntrega.normalizarTipoVeiculo(42), '');
    });

    test('reconhece códigos canônicos exatos', () {
      expect(TiposEntrega.normalizarTipoVeiculo('bicicleta'), 'bicicleta');
      expect(TiposEntrega.normalizarTipoVeiculo('moto'), 'moto');
      expect(TiposEntrega.normalizarTipoVeiculo('carro'), 'carro');
      expect(
        TiposEntrega.normalizarTipoVeiculo('carro_frete'),
        'carro_frete',
      );
    });

    test('normaliza variações com maiúsculas e espaços', () {
      expect(TiposEntrega.normalizarTipoVeiculo('MOTO'), 'moto');
      expect(TiposEntrega.normalizarTipoVeiculo(' Carro '), 'carro');
      expect(TiposEntrega.normalizarTipoVeiculo('Bicicleta'), 'bicicleta');
    });

    test('frete tem prioridade sobre carro (Fiorino, Kombi, pick-up, van)', () {
      expect(
        TiposEntrega.normalizarTipoVeiculo('Fiorino'),
        'carro_frete',
      );
      expect(TiposEntrega.normalizarTipoVeiculo('Kombi'), 'carro_frete');
      expect(
        TiposEntrega.normalizarTipoVeiculo('Pick-up'),
        'carro_frete',
      );
      expect(
        TiposEntrega.normalizarTipoVeiculo('Van de carga'),
        'carro_frete',
      );
      expect(
        TiposEntrega.normalizarTipoVeiculo('carro de frete'),
        'carro_frete',
      );
      expect(
        TiposEntrega.normalizarTipoVeiculo('Utilitário'),
        'carro_frete',
      );
      expect(
        TiposEntrega.normalizarTipoVeiculo('utilitario'),
        'carro_frete',
      );
    });

    test('bike / bicy / bicicleta viram bicicleta', () {
      expect(TiposEntrega.normalizarTipoVeiculo('Bike'), 'bicicleta');
      expect(TiposEntrega.normalizarTipoVeiculo('bicy'), 'bicicleta');
      expect(
        TiposEntrega.normalizarTipoVeiculo('Bicicleta elétrica'),
        'bicicleta',
      );
    });

    test('moto / scooter / motocicleta viram moto', () {
      expect(TiposEntrega.normalizarTipoVeiculo('Scooter'), 'moto');
      expect(
        TiposEntrega.normalizarTipoVeiculo('Motocicleta'),
        'moto',
      );
      expect(TiposEntrega.normalizarTipoVeiculo('Motoboy'), 'moto');
    });
  });

  group('Hierarquia canônica (regra de negócio)', () {
    test('bicicleta(1) < moto(2) < carro(3) < carro_frete(4)', () {
      expect(TiposEntrega.hierarquia['bicicleta'], 1);
      expect(TiposEntrega.hierarquia['moto'], 2);
      expect(TiposEntrega.hierarquia['carro'], 3);
      expect(TiposEntrega.hierarquia['carro_frete'], 4);
    });

    test('tabela de frete mapeia corretamente', () {
      expect(TiposEntrega.tabelaFretePorTipo['bicicleta'], 'padrao');
      expect(TiposEntrega.tabelaFretePorTipo['moto'], 'padrao');
      expect(TiposEntrega.tabelaFretePorTipo['carro'], 'carro');
      expect(TiposEntrega.tabelaFretePorTipo['carro_frete'], 'carro_frete');
    });

    test('raio recomendado bicicleta ≤ 2km (limite operacional)', () {
      final raioBike = TiposEntrega.raioKmRecomendado['bicicleta'];
      expect(raioBike, isNotNull);
      expect(raioBike, lessThanOrEqualTo(2.0));
    });
  });
}
