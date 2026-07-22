import 'package:flutter_test/flutter_test.dart';
import 'package:depertin_web/services/fiscal/fiscal_provider_service.dart';

// Teste de mock dos provedores fiscais
// Verifica se o provider service consegue instanciar e rotear corretamente

void main() {
  group('FiscalProviderService — Resolução de Providers', () {
    setUp(() {
      FiscalProviderService.instance.inicializar();
    });

    test('deve resolver Focus NFe pelo ID focus_nfe', () {
      final provider = FiscalProviderService.instance.obterProvider('focus_nfe');
      expect(provider, isNotNull);
      expect(provider!.id, equals('focus_nfe'));
    });

    test('deve resolver Enotas pelo ID enotas', () {
      final provider = FiscalProviderService.instance.obterProvider('enotas');
      expect(provider, isNotNull);
      expect(provider!.id, equals('enotas'));
    });

    test('deve resolver PlugNotas pelo ID plug_notas', () {
      final provider = FiscalProviderService.instance.obterProvider('plug_notas');
      expect(provider, isNotNull);
      expect(provider!.id, equals('plug_notas'));
    });

    test('deve resolver Nuvem Fiscal pelo ID nuvem_fiscal', () {
      final provider = FiscalProviderService.instance.obterProvider('nuvem_fiscal');
      expect(provider, isNotNull);
      expect(provider!.id, equals('nuvem_fiscal'));
    });

    test('deve resolver Webmania pelo ID webmania_br', () {
      final provider = FiscalProviderService.instance.obterProvider('webmania_br');
      expect(provider, isNotNull);
      expect(provider!.id, equals('webmania_br'));
    });

    test('deve resolver Custom Fiscal pelo ID custom', () {
      final provider = FiscalProviderService.instance.obterProvider('custom');
      expect(provider, isNotNull);
      expect(provider!.id, equals('custom'));
    });

    test('deve retornar null para ID de provedor inexistente', () {
      final provider = FiscalProviderService.instance.obterProvider('provedor_inexistente');
      expect(provider, isNull);
    });

    test('deve listar todos os provedores registrados', () {
      final providers = FiscalProviderService.instance.listarProviders();
      expect(providers.length, greaterThanOrEqualTo(6));
      expect(providers.any((p) => p.id == 'focus_nfe'), isTrue);
      expect(providers.any((p) => p.id == 'enotas'), isTrue);
      expect(providers.any((p) => p.id == 'plug_notas'), isTrue);
      expect(providers.any((p) => p.id == 'nuvem_fiscal'), isTrue);
      expect(providers.any((p) => p.id == 'webmania_br'), isTrue);
      expect(providers.any((p) => p.id == 'custom'), isTrue);
    });

    test('deve extrair configuração da integração (apenas campos públicos)', () {
      final config = FiscalProviderService.instance.extrairConfig({
        'provider': 'focus_nfe',
        'environment': 'homologacao',
        'credentials_encrypted': 'encrypted_token',
      });
      expect(config, isNotNull);
      expect(config['environment'], equals('homologacao'));
      // credentials_encrypted NÃO é mais exposto ao frontend
      expect(config, isNot(contains('api_key')));
      expect(config, isNot(contains('credentials_encrypted')));
    });

    test('deve usar homologação como ambiente padrão', () {
      final config = FiscalProviderService.instance.extrairConfig({
        'provider': 'enotas',
      });
      expect(config['environment'], equals('sandbox'));
    });

    test('deve resolver provedor pelo nome', () {
      final provider = FiscalProviderService.instance.resolverPorNome('Focus NFe');
      expect(provider, isNotNull);
      expect(provider!.id, equals('focus_nfe'));
    });

    test('deve resolver provedor pelo nome em lowercase', () {
      final provider = FiscalProviderService.instance.resolverPorNome('enotas');
      expect(provider, isNotNull);
      expect(provider!.id, equals('enotas'));
    });

    test('deve retornar null ao resolver nome inexistente', () {
      final provider = FiscalProviderService.instance.resolverPorNome('Provedor Inexistente');
      expect(provider, isNull);
    });
  });
}
