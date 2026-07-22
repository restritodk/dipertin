import 'package:depertin_web/constants/modulo_codigos.dart';
import 'package:depertin_web/models/modulo_config_model.dart';
import 'package:depertin_web/services/assinatura_gestao_comercial_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('textoIndicaEmissaoNfe', () {
    test('reconhece código canônico', () {
      expect(
        AssinaturaGestaoComercialService.textoIndicaEmissaoNfe(
          ModuloCodigos.emissaoNfe,
        ),
        isTrue,
      );
    });

    test('reconhece nome visível do admin', () {
      expect(
        AssinaturaGestaoComercialService.textoIndicaEmissaoNfe('Emissão de NF-e'),
        isTrue,
      );
    });

    test('não confunde com Gestão Comercial', () {
      expect(
        AssinaturaGestaoComercialService.textoIndicaEmissaoNfe(
          'Gestão Comercial',
        ),
        isFalse,
      );
      expect(
        AssinaturaGestaoComercialService.textoIndicaEmissaoNfe('PDV'),
        isFalse,
      );
    });
  });

  group('planoDocTemEmissaoNfe', () {
    AssinaturaGestaoComercialContexto ctxComCatalogo() {
      final mod = ModuloConfigModel(
        id: 'm1',
        nome: 'Emissão de NF-e',
        codigo: ModuloCodigos.emissaoNfe,
      );
      return AssinaturaGestaoComercialContexto(
        planosPorId: const {},
        planosGestaoIds: const {},
        modulosPorNome: {
          'Emissão de NF-e': mod,
          ModuloCodigos.emissaoNfe: mod,
        },
        modulosPorId: {'m1': mod},
      );
    }

    test('detecta módulo por nome na lista do plano', () {
      final ok = AssinaturaGestaoComercialService.planoDocTemEmissaoNfe(
        {
          'modulos': ['Dashboard Completo', 'Emissão de NF-e', 'PDV'],
        },
        ctx: ctxComCatalogo(),
      );
      expect(ok, isTrue);
    });

    test('plano sem NF-e retorna false', () {
      final ok = AssinaturaGestaoComercialService.planoDocTemEmissaoNfe(
        {
          'modulos': ['Dashboard Completo', 'PDV', 'Gestão Financeiro'],
        },
        ctx: ctxComCatalogo(),
      );
      expect(ok, isFalse);
    });
  });
}
