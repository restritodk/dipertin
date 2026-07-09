# DiPertin — Guia para Agentes

## Antes de qualquer tarefa

1. **LEIA** `.kilo/MEMORY.md` — contém a memória completa do projeto.
2. **Respeite as REGRAS INVIOLÁVEIS** (seção 9 do MEMORY.md):
   - NUNCA alterar o pipeline FCM/notificações
   - Preservar a paleta de cores DiPertin (roxo `#6A1B9A` + laranja `#FF8F00`)
   - Contratos triplicados (mobile + web + functions) devem ser mantidos em sincronia
3. **Sempre use o UI UX Pro Max** em tarefas de UI (consultar skills de design primeiro)

## Estrutura do Projeto

- **Mobile:** `depertin_cliente/` — Flutter + Kotlin nativo
- **Web:** `depertin_web/` — Flutter Web (depende de depertin_cliente como path)
- **Functions:** `depertin_cliente/functions/` — Node.js 20
- **Site:** `site/` — HTML/CSS/JS estático

## Regras Obrigatórias do Cursor

As regras estão em `.cursor/rules/`:
- `projeto-dipertin.mdc` — Mapa completo
- `analise-profunda-projeto.mdc` — Análise detalhada v1.2.7+23
- `paleta-cores-dipertin.mdc` — Paleta de cores
- `producao-deploy.mdc` — Procedimento de deploy
- `skills-design-obrigatorias.mdc` — Skills de design
- `ui-ux-pro-max-obrigatorio.mdc` — UI UX Pro Max obrigatório

## Skills Instaladas

- **UI UX Pro Max:** `.cursor/skills/ui-ux-pro-max/` — refinamento de UI
- **Frontend Design:** `.cursor/skills/frontend-design/` — criação de telas novas
- **Raiz:** `ui-ux-pro-max-skill/` — engine de busca de guidelines

## Contatos Triplicados (sincronizar sempre)

1. Código do Pedido (`PED-XXXXXX`): 3 arquivos
2. Tipos de Entrega (bicicleta/moto/carro/carro_frete): 3 arquivos + testes
3. Cupons (tipos/modalidades): 3 arquivos + testes

## Principais Caminhos

| O que é | Onde está |
|---|---|
| Pubspec mobile | `depertin_cliente/pubspec.yaml` |
| Pubspec web | `depertin_web/pubspec.yaml` |
| Main mobile | `depertin_cliente/lib/main.dart` |
| Index Functions | `depertin_cliente/functions/index.js` |
| Firestore Rules | `depertin_cliente/firestore.rules` |
| Rotas web | `depertin_web/lib/navigation/painel_routes.dart` |
| Theme web | `depertin_web/lib/theme/painel_admin_theme.dart` |
| Logística entregador | `depertin_cliente/functions/logistica_entregador.js` |
| Mercado Pago | `depertin_cliente/functions/mercadopago_webhook.js` |

## Deploy

Seguir `.cursor/rules/producao-deploy.mdc` — NUNCA pular etapas.
