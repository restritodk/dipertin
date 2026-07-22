/**
 * Runner que importa todas as suites de teste integrado.
 * Necessário porque node --test com múltiplos arquivos explícitos
 * no Windows + emulators:exec só executa o primeiro arquivo.
 *
 * Uso:
 *   firebase emulators:exec "cd functions && node test/create-fixtures.js && node --test-concurrency=1 test/_run_all_integrated.js" --project demo-depertin-teste
 */
require('./assinatura_rules.integration.test.js');
require('./fiscal_emissao.integration.test.js');
require('./nfe_fluxo_completo.integration.test.js');
require('./saldo_transacional.integration.test.js');
require('./seguranca.integration.test.js');
require('./storage_fiscal.integration.test.js');
// Nota: isolamento.integration.test.js não existe como arquivo separado.
// O isolamento de dados é garantido pelo criarTodasFixtures + before hooks.
