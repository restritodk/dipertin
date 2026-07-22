# DiPertin — Documentação Completa do Projeto

> Documento canônico gerado em **21/jul/2026** a partir do inventário factual do working tree.  
> Serve como memória operacional: configuração, páginas, redirecionamentos, banco, Functions, rules, skills e regras de negócio.

---

## 1. Visão geral

| Item | Valor |
|---|---|
| Produto | Marketplace + delivery local (cliente compra; lojista vende; entregador entrega; admin opera) |
| Projeto Firebase | `depertin-f940f` |
| Domínio público | https://www.dipertin.com.br/ |
| Painel web | https://www.dipertin.com.br/sistema/#/login |
| Região Functions (marketplace) | `us-central1` |
| Região Functions (Gestão Comercial e-mail) | `southamerica-east1` |
| Node runtime | **20** |
| App mobile | Flutter `1.2.8+24` · SDK `^3.11.1` · `com.dipertin.app` |
| Painel web | Flutter `1.0.0+1` · SDK `^3.11.3` |
| Stack | Flutter (mobile + web) + Firebase (Auth, Firestore, Storage, FCM, App Check, Functions) + Mercado Pago + SMTP + provedores NF-e |

### Pacotes do repositório

```
DiPertin/
├── depertin_cliente/     # App Flutter mobile (cliente, lojista, entregador) + Cloud Functions
├── depertin_web/         # Painel admin / lojista (Flutter Web)
├── site/                 # Site institucional estático (SEO)
├── docs/                 # Documentação modular (mapas, fiscal, GC, segurança, encomenda)
├── .cursor/              # Rules + skills de design obrigatórias
├── ui-ux-pro-max-skill/  # Engine de busca UI UX Pro Max (opcional/local)
└── projetoDiPertin.md    # Este documento
```

---

## 2. Regras invioláveis do projeto

1. **NÃO mexer no FCM / notificações** — payloads, chaves, canais, collapseKeys, pipeline nativo Android (`IncomingDelivery*`, `CorridaIncomingNotifier`, etc.) e `notification_dispatcher.js` devem ser preservados 100%. Alterar só lógica de negócio antes/depois do envio.
2. **Modal premium obrigatório** (jul/2026) — feedback de sucesso/erro/confirmação/carregamento no painel e app: `showDialog` premium (gradiente, ícone circular, botão roxo). Proibido SnackBar/toast para mensagens importantes. Auto-save de switches = silencioso. Exceção: ações triviais (“URL copiada!”).
3. **Paleta DiPertin** — roxo `#6A1B9A`, laranja `#FF8F00`, fundo `#F5F4F8`, texto `#1A1A2E` / muted `#64748B`. Sem dourado/prata/bronze/cores aleatórias.
4. **Fiscal** — credenciais/XML/DANFE nunca no client; saldo/cota via `fiscal_saldo_helper` + coleção `lojista_integracao`; Storage `fiscal/**` negado ao client.
5. **Skills de design** — UI UX Pro Max para refinar UI existente; `frontend-design` para telas novas.

### Alerta in-app sem push (padrão abr/2026)

Persistir mapa `alerta_*` em `users/{uid}` e consumir via `StreamBuilder`. Dispensar gravando `dispensado_em` (UI esconde se `dispensado_em >= ultimo_em`). Não cria callable/push novo.

---

## 3. Skills e rules Cursor (obrigatórias)

### 3.1 Skills de design

| Skill | Caminho | Quando usar |
|---|---|---|
| **UI UX Pro Max** | `.cursor/skills/ui-ux-pro-max/` (+ comando `.cursor/commands/ui-ux-pro-max/`) | Refinar / estilizar UI existente (cores, tipografia, espaçamento, estados, acessibilidade) |
| **frontend-design** | `.cursor/skills/frontend-design/SKILL.md` | Criar telas/componentes **do zero** |

Consulta Pro Max (quando Python disponível):

```bash
python .cursor/skills/ui-ux-pro-max/scripts/search.py "<contexto>" --design-system -f markdown
python .cursor/skills/ui-ux-pro-max/scripts/search.py "<keyword>" --domain color   # style|typography|ux|chart
python .cursor/skills/ui-ux-pro-max/scripts/search.py "<keyword>" --stack flutter
```

### 3.2 Skills auxiliares (agents)

Em `.cursor/.agents/skills/`: `3d-web-experience`, `gsap-core`, `gsap-performance`, `gsap-plugins`, `gsap-scrolltrigger`, `gsap-timeline`, `gsap-utils`, `threejs-skills` — uso pontual (animações/3D no site), não no fluxo padrão do painel Flutter.

### 3.3 Rules `.cursor/rules/`

| Arquivo | Papel |
|---|---|
| `projeto-dipertin.mdc` | Mapa completo do projeto |
| `analise-profunda-projeto.mdc` | Inventário detalhado (precedência §49 → §48 → §47…) |
| `paleta-cores-dipertin.mdc` | Tokens de cor obrigatórios |
| `modal-premium-obrigatorio.mdc` | Sem SnackBar para feedback importante |
| `ui-ux-pro-max-obrigatorio.mdc` | Pro Max em todo pedido com UI |
| `skills-design-obrigatorias.mdc` | Pro Max + frontend-design |
| `producao-deploy.mdc` | Checklist deploy produção |
| `project-context.mdc` | Contexto adicional |

### 3.4 Design system (tokens)

```dart
const Color diPertinRoxo = Color(0xFF6A1B9A);
const Color diPertinLaranja = Color(0xFFFF8F00);
// Fundo #F5F4F8 · texto #1A1A2E · muted #64748B
```

- Fonte web: **Plus Jakarta Sans** (Google Fonts) — `painel_admin_theme.dart`
- Safe area mobile: `DiPertinSafeMediaQuery`, `DiPertinScrollBody`, `diPertinScrollPaddingTabShell`, `DiPertinSafeBottomPanel`
- Touch ≥ 44–48 dp; tipografia ≥ 12 px; debounce em buscas; skeleton no loading

---

## 4. Configuração Firebase

### 4.1 Arquivos principais

| Arquivo | Conteúdo |
|---|---|
| `depertin_cliente/firebase.json` | Firestore rules/indexes, Storage rules, Functions, emulators |
| `depertin_cliente/firestore.rules` | Segurança Firestore |
| `depertin_cliente/firestore.indexes.json` | ~**60** índices compostos |
| `depertin_cliente/storage.rules` | Segurança Storage |
| `depertin_cliente/lib/firebase_options.dart` | FlutterFire (Android + Web; iOS → `UnsupportedError`) |
| `depertin_web/firebase.json` | Config FlutterFire (painel) |
| `site/firebase.json` | Hosting site (opcional) |

### 4.2 Emulators (`firebase.json`)

| Serviço | Porta |
|---|---|
| Functions | 5001 |
| Firestore | 8080 |
| Auth | 9099 |
| Storage | 9199 |
| Hosting | 5000 |
| UI | 4000 |

### 4.3 Variáveis de ambiente Functions (`.env` — NÃO commitar)

Modelo: `depertin_cliente/functions/.env.example`

| Variável | Uso |
|---|---|
| `SMTP_*` | Host, porta, user, from, candidatura, site dest, delete account |
| `OTP_RECUPERACAO_PEPPER` | Hash OTP recuperação senha |
| `COMTELE_AUTH_KEY` | SMS verificação telefone |
| `FISCAL_MASTER_KEY` | AES-256-GCM tokens fiscais (64 hex; Secret Manager) |
| `FISCAL_WEBHOOK_SECRET` | HMAC webhook NF-e |
| `MP_WEBHOOK_SECRET` | HMAC webhook Mercado Pago |
| `MP_WEBHOOK_ALLOW_UNSIGNED` | Debug (evitar em produção) |
| `GC_EMAIL_CONFIG_SECRET` | Criptografia config e-mail Gestão Comercial |
| `EXIGIR_KYC_SAQUE` | Flag opcional saque |

---

## 5. Perfis, permissões e gates

### Roles (`users.role`)

`cliente` · `lojista` · `entregador` · `master` · `master_city`

### Níveis lojista (colaborador)

| Nível | Capacidade |
|---|---|
| I | Básico |
| II | + cardápio / cupons |
| III | + carteira, config, colaboradores |

Helpers: `lojista_acesso_app.dart` (mobile), `lojista_painel_context.dart` / `admin_perfil.dart` (web).

### Gates do painel web

| Gate | Escopo |
|---|---|
| Perfil staff / master | Rotas admin (lojas, financeiro, auditoria, etc.) |
| `sanearRotaPainelLojista` | Lojista não acessa rotas staff; Centro Ops → `/dashboard` |
| `GestaoComercialAccessGate` | Rotas GC + PDV + módulo fiscal — exige assinatura GC |
| `ModuloFiscalAccessGate` | `/modulo_fiscal` — exige módulo `emissao_nfe` |
| Upsell | Sem plano → `ComercialUpsellScreen`; sem NF-e → `ComercialUpgradeFiscalScreen` |

### AppGuard (mobile)

Overlay: offline · GPS · bloqueio lojista/entregador · sessão 24h / permission-denied → modal sessão expirada.

---

## 6. App mobile (`depertin_cliente`)

### 6.1 Entrada e providers

- `lib/main.dart` — Firebase + App Check (só mobile) + FCM + canais Android + `MultiProvider` (`CartProvider`, `ConnectivityService`, `LocationService`)
- Splash → online + location → `/home`
- Bottom nav: Buscar | Vitrine | Perfil

### 6.2 Rotas nomeadas (`main.dart`)

| Rota | Tela |
|---|---|
| `/home` | MainNavigator |
| `/pedidos` | LojistaPedidosScreen |
| `/meus-pedidos` | OrdersScreen |
| `/entregador` | EntregadorHomeScreen |
| `/entregador-pos-entrega` | EntregadorHomeScreen |
| `/suporte` | ChatSuporteScreen |
| `/lojista-cadastro` | LojistaFormScreen |
| `/lojista-painel` | LojistaPainelRoteador |
| `/entregador-cadastro` | EntregadorFormScreen |
| `/todas-categorias` | TodasCategoriasScreen |

Rotas via `MaterialPageRoute` (FCM encomenda): `/cliente-encomenda`, `/loja-encomenda`.

### 6.3 Redirecionamento FCM (`fcm_rota.dart`)

| Payload / tipo | Destino |
|---|---|
| `nova_entrega` | `/entregador` |
| `LOJISTA_CADASTRO_APROVADO` | `/lojista-painel` |
| `LOJISTA_CADASTRO_RECUSADO` | `/lojista-cadastro` |
| `ENTREGADOR_CADASTRO_APROVADO` | `/entregador` |
| `ENTREGADOR_CADASTRO_RECUSADO` | `/entregador-cadastro` |
| `encomenda_cliente_*` | Detalhe encomenda cliente |
| `encomenda_loja_*` | Detalhe encomenda loja |
| `chat_pedido_cliente_para_loja` | `/pedidos` |
| `chat_pedido_loja_para_cliente` | `/meus-pedidos` |
| suporte / atendimento | `/suporte` |
| demais status pedido | `/meus-pedidos` ou `/home` |

**Canais Android:** `high_importance_channel`, `corrida_chamada`, `loja_novo_pedido`.

### 6.4 Telas por pasta (~80 screens)

| Pasta | Conteúdo |
|---|---|
| `auth/` | Login, register, recuperar senha, aceite termos Google, ativação biometria |
| `cliente/` | Vitrine, search, cart, checkout, pedidos, chat, endereços, favoritos, encomendas, produto |
| `lojista/` | Dashboard, pedidos, produtos, cupons, config, form, encomendas, tipos entrega |
| `entregador/` | Home/dashboard/mapa, carteira, histórico, área de perigo, config (veículos, docs, fiscal, acessibilidade) |
| `comum/` | Perfil, segurança, sobre, comunicados, notificações, políticas |
| `guards/` | AppGuard, no internet, no GPS |
| `utilidades/` | Vagas, achados, eventos |

### 6.5 Services principais (~39)

Biometria, FCM rota/histórico/prefs, location, connectivity, deep link + install referrer, cupom (via callable), recuperação senha, suporte, favoritos, sessão 24h, Comtele SMS consent Android, wallet reserva, etc.

### 6.6 Android nativo (corrida)

Pacote `com.dipertin.app`:

- `IncomingDeliveryFirebaseService` — intercepta FCM `nova_entrega`
- `IncomingDeliveryActivity` — fullscreen aceitar/recusar
- `CorridaIncomingNotifier` — heads-up + som
- `IncomingDeliveryActionReceiver` — ações da notificação
- `FloatingIconService` — ícone flutuante
- `MainActivity` = `FlutterFragmentActivity` (biometria) + MethodChannel `dipertin.android/nav`
- App Links: `https://www.dipertin.com.br/p` + scheme `dipertin://produto`

### 6.7 Deep link produto

URL canônica: `https://www.dipertin.com.br/p/?produto={id}`  
Landing site: `site/p/` + `assetlinks.json`. Deferred: Play Install Referrer.

---

## 7. Painel web (`depertin_web`)

### 7.1 Entrada

- `lib/main.dart` — Firebase (sem App Check), `getRedirectResult` Google, rotas `/login` e `/painel`
- Shell: `PainelShellScreen` → `IndexedStack` lazy + `SidebarMenu` + `PainelNavController`
- Tema: `PainelAdminTheme` (Material 3, Plus Jakarta Sans)
- Callables: `callFirebaseFunctionSafe` (Web = HTTP POST; demais = httpsCallable)

### 7.2 Rotas shell — **56** (`PainelRoutes.ordem`, índices 0–55)

| # | Rota | Tela | Público |
|---|---|---|---|
| 0 | `/dashboard` | DashboardScreen | ambos |
| 1 | `/lojas` | LojasScreen | staff |
| 2 | `/lojas_financeiro` | LojasFinanceiroDashboardScreen | staff |
| 3 | `/entregadores` | EntregadoresScreen | staff |
| 4 | `/clientes` | CentralClientesScreen | staff |
| 5 | `/banners` | BannersScreen | staff |
| 6 | `/categorias` | CategoriasScreen | staff |
| 7 | `/admincity` | AdminCityUsuariosScreen | master |
| 8 | `/admincity_cidades` | AdminCityCidadesScreen | master |
| 9 | `/utilidades` | UtilidadesScreen | staff |
| 10 | `/financeiro` | FinanceiroScreen | staff |
| 11 | `/financeiro_saques` | SolicitacoesSaquesPainelScreen | staff |
| 12 | `/configuracoes` | Configurações (master/staff ou lojista slot) | perfil |
| 13 | `/configuracao_cadastro_acesso` | CadastroAcessoColaboradoresScreen | lojista III / staff |
| 14 | `/atendimento_suporte` | AtendimentoSuporteScreen | staff |
| 15 | `/notificacoes` | NotificacoesScreen | staff |
| 16 | `/cupons` | CuponsScreen (global) | staff |
| 17 | `/monitor_pedidos` | MonitorPedidosScreen | staff |
| 18 | `/centro_operacoes_crm` | CentroOperacoesCrmScreen | staff |
| 19 | `/centro_operacoes_marketing` | PainelMarketingDashboard | staff |
| 20 | `/centro_operacoes_leads_lojistas` | PainelLeadsLojistas | staff |
| 21 | `/centro_operacoes_leads_entregadores` | PainelLeadsEntregadores | staff |
| 22 | `/centro_operacoes_agenda` | PainelCentroOpsAgenda | staff |
| 23 | `/centro_operacoes_frete` | CentroOperacoesFreteScreen | staff |
| 24 | `/avaliacoes_painel` | AvaliacoesPainelScreen | staff |
| 25 | `/comunicados` | ComunicadosScreen | staff |
| 26 | `/conteudo_legal` | ConteudoLegalScreen | staff |
| 27 | `/auditoria` | AuditoriaScreen | staff |
| 28 | `/pdv` | LojistaPdvScreen (+ gate GC) | lojista |
| 29 | `/meus_pedidos` | LojistaPedidosTabelaScreen | lojista |
| 30 | `/negociacoes_encomenda` | LojistaNegociacoesEncomendaScreen | lojista |
| 31 | `/meu_cardapio` | LojistaMeuCardapioScreen | lojista |
| 32 | `/meus_cupons` | LojistaCuponsScreen (≥II) | lojista |
| 33–36 | `/carteira_*` | Carteira loja / financeiro / relatório / config | lojista III |
| 37 | `/comercial_dashboard` | LojistaComercialDashboardScreen | GC |
| 38 | `/minha_loja` | LojistaMinhaLojaScreen | GC |
| 39 | `/comercial_clientes` | LojistaComercialClientesScreen | GC |
| 40 | `/comercial_credito` | LojistaComercialCreditoScreen | GC |
| 41 | `/comercial_pendencias` | ComercialPendenciasScreen | GC |
| 42 | `/comercial_recebimentos` | ComercialRecebimentosScreen | GC |
| 43 | `/comercial_historico` | ComercialHistoricoVendasScreen | GC |
| 44 | `/comercial_relatorios` | ComercialRelatorioScreen | GC |
| 45 | `/comercial_configuracoes` | ComercialConfiguracoesScreen | GC |
| 46–53 | `/assinaturas_*` | Dashboard, clientes, planos, cobranças, inadimplência, relatórios, fiscal, config | staff |
| 54 | `/modulo_fiscal` | LojistaModuloFiscalScreen (GC + módulo NF-e) | lojista |
| 55 | `/admin_fiscal` | AdminFiscalScreen | staff |

### 7.3 Aliases e redirecionamentos

| Entrada | Resolve para |
|---|---|
| `/centro_operacoes` | `/centro_operacoes_crm` |
| `/assinaturas` | `/assinaturas_dashboard` |
| Rota desconhecida no shell | `/dashboard` |
| Lojista em rota Centro Ops / staff | `/dashboard` (sanear) |
| Sem assinatura GC em rota GC | Upsell |
| Sem módulo `emissao_nfe` em `/modulo_fiscal` | Upgrade fiscal |
| Conta bloqueada lojista | Overlay + sign-out → `/login` |
| Sessão inválida / permission-denied | Modal → `/login` |

### 7.4 Accordions sidebar (grupos)

- Lojas · Centro de Operações (6) · AdminCity · Assinaturas (8) · Gestão Comercial (+ Financeiro GC) · Carteira · Configurações

### 7.5 Build / deploy painel

```powershell
cd depertin_web
.\build_sistema.ps1
# flutter build web --release --base-href /sistema/ --pwa-strategy=none --no-tree-shake-icons
.\deploy_sistema_ftp.ps1
```

Proteção pré-login client-side: `site/sistema/` (`protection.js`, senha em JS — **não** é segurança real).

---

## 8. Site institucional (`site/`)

- HTML/CSS/JS + SEO (JSON-LD Organization/WebSite/FAQ/City/Product)
- Cidades: Rondonópolis-MT, Toledo-PR
- Contato: callables HTTP `enviarContatoSite`, `avaliacoesSitePublicas`
- Deep link produto: `/p/`
- Deploy: Firebase Hosting **ou** FTP (`deploy-ftp.ps1` + `.env.deploy`)
- Headers: HSTS, CSP, COOP, nosniff, X-Frame-Options

---

## 9. Firestore — coleções e papéis

> Fonte canônica de paths: `depertin_cliente/firestore.rules`. Escrita sensível quase sempre via **Admin SDK** (Cloud Functions).

### 9.1 Marketplace / usuários

| Coleção / path | Uso | Read (resumo) | Write |
|---|---|---|---|
| `users/{uid}` | Perfis, saldo, role, FCM, bloqueios, alertas | dono + staff + colaborador↔dono | dono (campos controlados) / staff / Functions |
| `users/{uid}/enderecos` | Endereços cliente | dono | dono |
| `users/{uid}/favoritos` | Favoritos produto | dono | dono |
| `users/{uid}/veiculos` + `documentos` | Veículos/CRLV entregador | dono + staff | dono + staff |
| `users/{uid}/documentos` | CNH | dono + staff | dono + staff |
| `users/{uid}/chaves_pix` | PIX saque | dono | dono |
| `users/{uid}/bloqueios_auditoria` | Auditoria bloqueio entregador | staff / sistema | Admin |
| `users/{uid}/clientes_comercial` | Clientes GC | loja operacional | loja / Functions |
| `users/{uid}/vendas_credito` | Vendas crediário | loja | Functions / loja controlado |
| `users/{uid}/parcelas_cliente` | Parcelas | loja | Functions |
| `users/{uid}/recebimentos_cliente` | Recebimentos | loja | Functions |
| `users/{uid}/wallet_reservas` | Reservas saldo | dono / Functions | Functions |
| `users/{uid}/notas_fiscais` | Notas (sub) | loja | controlado |
| `lojas_public/{uid}` | Espelho vitrine (sem CPF/email/saldo/token) | público | **false** (trigger) |
| `users_cpf_index/{cpf}` | Unicidade CPF | negado client | Admin |
| `pedidos/{id}` | Pedidos marketplace | participantes + staff | regras finas; Functions |
| `pedidos/{id}/mensagens` | Chat cliente↔loja | participantes | participantes |
| `encomendas/{id}` | Negociação sob encomenda | participantes + staff | **false** client (só Functions) |
| `encomendas/{id}/mensagens` | Chat encomenda | participantes | participantes |
| `produtos/{id}` | Cardápio | autenticado / público conforme tela | lojista da loja + staff |
| `categorias` / `sugestoes_categorias` | Catálogo | público / autenticado | staff (+ sugestão lojista) |
| `banners` | Marketing vitrine | autenticado | staff |
| `avaliacoes/{pedidoId}` | Avaliação loja | autenticado | create cliente pedido entregue |
| `avaliacoes_produto/{pedido_produto}` | Avaliação produto | público | create cliente |
| `cupons` | Cupons loja/global | staff ou loja própria; **cliente NÃO lê** | loja escopo `loja` / staff |
| `tabela_fretes` | Frete por cidade/tipo | autenticado | staff |
| `planos_taxas` | Comissões | autenticado | staff |
| `gateways_pagamento` | Tokens MP etc. | **staff only** | staff |
| `saques_solicitacoes` | Fila saques | staff / dono | create false (callable) |
| `estornos` | Estornos | staff / envolvidos | Admin |
| `receitas_app` / `despesas_app` | Livro caixa app | staff | staff |

### 9.2 Suporte e conteúdo

| Coleção | Uso |
|---|---|
| `support_tickets` (+ `mensagens`) | Central ajuda |
| `support_ratings` | Avaliação atendimento |
| `suporte/{ticketId}` | Legado (ainda nas rules) |
| `comunicados` | CMS app/painel |
| `conteudo_legal` | Termos/políticas |
| `notificacoes_campanhas` | Push campanhas |
| `notificacoes_usuario/{uid}/items` | Histórico in-app |
| `configuracoes/{id}` | Ex.: `atualizacao_app` |
| `vagas` / `achados` / `eventos` / `servicos_destaque` / `telefones_premium` | Utilidades |
| `candidaturas` | Candidatura vaga |
| `cidades` / `cidades_atendidas` | IBGE / cidades atendidas |
| `centro_ops_agenda` | Agenda Centro Ops |
| `marketing_leads_lojistas` (+ `historico`) | CRM leads lojistas |
| `marketing_leads_entregadores` (+ `historico`) | CRM leads entregadores |
| `audit_logs` | Auditoria (read staff; write Admin) |

### 9.3 Assinaturas SaaS

| Coleção | Uso |
|---|---|
| `modulos_planos` | Catálogo planos/módulos |
| `assinaturas_modulos` / `assinaturas_gateways` / `assinaturas_bancos` | Config staff |
| `assinaturas_configuracoes` / `billing_settings` | Billing |
| `assinaturas_clientes` | Assinatura por loja (`store_id`) |
| `assinaturas_cobrancas` | Cobranças (write false client) |
| `contadores` | Contadores agregados |

Módulo fiscal típico: código ~`emissao_nfe`.

### 9.4 Gestão Comercial

| Coleção | Uso |
|---|---|
| `gestao_comercial_configuracoes/{lojaId}` | Config GC |
| `gestao_comercial_vendas` / `recebimentos` / `cobrancas` | Operação |
| `gestao_comercial_integracoes_pagamento/{lojaId}/gateways` | Gateways loja |
| `gestao_comercial_email_templates/{lojaId}/templates` | Templates e-mail |
| `gestao_comercial_email_historico/{lojaId}/envios` | Histórico envios |
| `sessoes_caixa` | PDV caixa |

### 9.5 Fiscal NF-e (lojista)

| Coleção | Uso |
|---|---|
| `fiscal_integrations` | Provedor global (`credentials_encrypted`) — staff |
| `store_fiscal_settings` | Config loja (NFe/NFCe/NFSe, company_tax_data) |
| `lojista_integracao` | **Cota**: limite_mensal, notas_emitidas, notas_reservadas, ciclo_ref |
| `fiscal_documents` | Docs emitidos — write false client |
| `fiscal_certificates` | Metadados A1 — callables |
| `fiscal_emission_operations` | Idempotência emissão |
| `planos_emissao_nfe` | Catálogo cota |
| `fiscal_series` | Séries |
| `notas_fiscais` | Paralela UI Assinaturas Fiscal |
| `fiscal_audit_logs` / `fiscal_logs` / `fiscal_webhooks` / `fiscal_status_history` | Observabilidade staff |

### 9.6 Fiscal entregador (agregado)

`fiscal/{uid}` → `anos/{ano}` → `meses/{mm}` — ganhos/taxas/líquido/corridas (trigger na entrega).

### 9.7 Auth / rate limit (negado client)

`password_reset_tokens`, `password_reset_rate_*`, `password_recovery_sessions` (se existir), `cadastro_telefone_verificado_tickets`, `comtele_cadastro_rate_ip`, `comtele_cadastro_rate_phone`, `wallet_transaction_logs`.

### 9.8 Helpers importantes nas rules

- `isStaff()`, `signedIn()`, colaborador↔dono
- Proteção transição `role→entregador` (só callable `entregadorAbrirCadastro`)
- Lojista **não** marca `status=entregue` direto em pedidos de entrega
- Catch-all staff em `/{document=**}` (exceto recuperação senha)

---

## 10. Storage — paths e rules

| Path | Read | Write |
|---|---|---|
| `produtos/{uidLoja}/**` / `produtos/{file}` | público / autenticado | autenticado (tipo/tamanho) |
| `banners_vitrine/**` | público | autenticado |
| `fotos_perfil/{uid}.jpg` | autenticado | dono |
| `documentos_lojistas/{userId}/**` | autenticado | dono |
| `documentos_entregadores/{userId}/**` | autenticado | dono |
| `utilidades/**` | autenticado | autenticado |
| `candidaturas/**` | autenticado | autenticado |
| `suporte_anexos/{ticketId}/**` | autenticado | create até ~20 MB |
| `chat_anexos/{colecao}/{docId}/{userId}/{file}` | participantes | dono |
| `fiscal/**` | **deny client** | **deny client** (só Functions) |

---

## 11. Cloud Functions

- Entry: `depertin_cliente/functions/index.js`
- Módulos raiz `.js`: **74**
- Exports: **~238**
- Testes: **27** `test/*.test.js`
- Deps: `firebase-admin ^13.6.0`, `firebase-functions ^7.0.0`, `nodemailer`, `dotenv`, `node-forge`, `qrcode`

### 11.1 Módulos por domínio

| Domínio | Arquivos |
|---|---|
| Pedidos / financeiro | `repasse_financeiro`, `estoque_pedido`, `mercadopago_webhook`, `lojista_estorno_frete`, `codigo_pedido`, `validar_cupom`, `cupom_helpers` |
| Logística | `logistica_entregador`, `tipos_entrega`, `notification_dispatcher` |
| Encomendas | `encomendas_negociacao`, chat encomenda |
| Auth / perfil | `recuperacao_senha`, `boas_vindas`, `cadastro_cliente_perfil`, `comtele_verificacao_telefone`, `painel_google_login`, exclusão conta |
| Lojista / entregador status | `lojista_status_notificacao`, `entregador_status_notificacao`, `entregador_selfie_aprovacao`, `veiculos_entregador`, `entregador_perfil_operacional*` |
| Sync | `sincronizar_lojas_public`, `sincronizar_identidade_pedidos` |
| Saques | `saque_solicitar`, `saque_notificacao_pago` |
| Wallet | `wallet_reservas` |
| AdminCity | `admincity_usuarios`, `admincity_cidades_ibge` |
| Avaliações | `avaliacao_pedido`, `avaliacao_produto`, `avaliacoes_site_publico` |
| Auditoria | `audit_log_helper`, `audit_logs_pipeline`, `audit_logs_extras`, `audit_logs_query` |
| Assinaturas | `assinatura_pagamento`, `assinatura_cobrancas`, `assinatura_cartao_recorrente` (+ webhook), `assinatura_avisos`, `assinatura_emails_templates`, `assinatura_admin`, `assinatura_contador_trigger` |
| Gestão Comercial | `gestao_comercial_functions`, `gestao_comercial_email`, `gestao_comercial_pagamento`, `pagamento_crediario`, `mercado_pago_gestao_comercial`, `payment_gateway_provider`, `renegociacao_divida`, `pix_emv_validacao` |
| Fiscal NF-e | `fiscal_nfe_proxy`, `fiscal_proxy`, `fiscal_webhook`, `fiscal_pos_emissao`, `fiscal_certificado`, `fiscal_integration_sync`, `fiscal_monthly_reset`, `fiscal_saldo_helper`, `fiscal_payload_validator`, `fiscal_logger`, `fiscal_security_guard` |
| Fiscal entregador | `fiscal_entregador` |
| Outros | `contato_site`, `candidatura_vaga`, `excluir_cliente_admin`, `painel_entregadores_atualizacoes`, `pedido_operacao_timeline`, `smtp_transport` |

### 11.2 Lista de exports (alfabética)

<details>
<summary>Clique para expandir ~238 exports</summary>

```
aceitarOfertaCorrida
adminAtualizarCobranca
adminCancelarPlanoAssinatura
adminCityAtualizarUsuario
adminCityBloquearUsuario
adminCityCadastrarUsuario
adminCityExcluirUsuario
adminCityImportarCidadesIbge
adminCriarCobrancaAvulsa
adminEnviarEmailCobrancaAtraso
adminEnviarEmailPagamentoConfirmado
adminGerarCobrancasAssinaturas
adminGerarCobrancasPorConfig
adminRecalcularContadoresAssinaturas
adminSalvarBillingSettings
agregarFiscalEntregadorOnEntrega
assinarPlanoConsultarStatusPix
assinarPlanoCriarCartaoRecorrente
assinarPlanoCriarPagamentoPix
assinarPlanoProcessarCartao
assinarPlanoRenovarCartao
assinarPlanoRenovarConsultarStatusPix
assinarPlanoRenovarPix
assinaturaAvisosTentativasScheduled
assinaturaCobrancaAtrasoScheduled
assinaturaCobrancaAutoScheduled
assinaturaCobrancaConsultarStatusPix
assinaturaCobrancaGerarPix
assinaturaEnviarCobrancaEmail
assinaturaEnviarReciboEmail
assinaturaVerificarSuspensaoScheduled
atualizarColaboradorPainelLojista
atualizarContadorAssinaturasOnWrite
atualizarRatingLojaAposAvaliacao
atualizarRatingProdutoOnCreate
atualizarRatingProdutoOnDelete
atualizarRatingProdutoOnUpdate
auditLogAcessoTelaAuditoria
auditLogCupomOnCreate
auditLogCupomOnDelete
auditLogCupomOnUpdate
auditLogEncomendaStatusOnUpdate
auditLogEstornoOnCreate
auditLogExportacao
auditLogFiscalIntegrationOnWrite
auditLogGatewayPagamentoOnWrite
auditLogNotificacaoUsuarioItemOnCreate
auditLogPedidoOnCreate
auditLogPedidoOnUpdate
auditLogPlanoAssinaturaOnCreate
auditLogPlanoAssinaturaOnUpdate
auditLogPurgarAntigos
auditLogRegistrarLogin
auditLogSaqueOnCreate
auditLogSaqueOnUpdate
auditLogsEstatisticas
auditLogsExportar
auditLogsListarEventos
auditLogsPesquisarUsuarios
auditLogSupportTicketOnCreate
auditLogSupportTicketOnUpdate
auditLogUserDeleted
auditLogUserStatusOnUpdate
auditLogUsuarioCriticoOnUpdate
avaliacoesSitePublicas
baixarEstoquePedidoOnCreate
cadastrarColaboradorPainelLojista
cadastroClienteSalvarPerfilInicial
cadastroConfirmarTelefoneVerificadoSms
cancelarAssinaturaCartaoRecorrente
cancelarPedidoPixExpirado
cancelarPedidosPixExpirados
checkPdvPixPaymentStatus
comteleCadastroTelefoneEnviarCodigo
comteleCadastroTelefoneValidarCodigo
consultarCobrancaPixCrediario
createPdvPixPayment
debugListarEncomendasRecentes
desativarPublicacoesVencidas
efetuarPagamentoCrediario
encomendaClienteAceitarPropostaECriarPedidoEntrada
encomendaClienteCancelarNegociacao
encomendaClienteCriar
encomendaClienteEnviarContraproposta
encomendaLojaAceitarNegociacao
encomendaLojaCancelarNegociacao
encomendaLojaCriarPedidoSaldoFinal
encomendaLojaEnviarProposta
encomendaLojaResponderContraproposta
entregadorAbrirCadastro
entregadorAutoBloquearDefinitivo
entregadorAutoBloquearTemporario
entregadorAutoDesbloquearConta
entregadorCancelarCorridaERedespachar
entregadorCancelarPorIncompatibilidade
entregadorSolicitarExclusaoPerfil
entregadorValidarCodigoEntrega
enviarCampanhaNotificacao
enviarCandidaturaVaga
enviarContatoSite
estornarPagamentoPedidoCancelado
excluirClienteAdminMaster
expandirBuscaEntregador
fiscalBaixarDanfe
fiscalBaixarXml
fiscalCancelarNFe
fiscalCartaCorrecaoNFe
fiscalConsultarEAtualizarStatus
fiscalConsultarNFe
fiscalDeletarDocumento
fiscalDownloadArquivo
fiscalEmitirNFe
fiscalInutilizarNFe
fiscalLimparCertificadosPendentes
fiscalListarNotas
fiscalRemoverCertificado
fiscalRepararVinculoIntegracao
fiscalRotinaMensalReset
fiscalSalvarIntegracao
fiscalTestarConexaoFocus
fiscalUploadCertificado
fiscalVincularIntegracaoLoja
fiscalWebhookNFe
gerarCobrancaPixCrediario
gestaoComercialAbrirCaixa
gestaoComercialApiExternaEncryptTokenOnWrite
gestaoComercialApiExternaEnviar
gestaoComercialApiExternaTestarConexao
gestaoComercialAutomacaoProcessar
gestaoComercialAutomacaoProcessarLoja
gestaoComercialConcederCredito
gestaoComercialConfirmarPagamentoMpToken
gestaoComercialConsultarCobrancaPorToken
gestaoComercialConsultarParcelas
gestaoComercialConsultarPendencias
gestaoComercialConsultarStatusPagamentoToken
gestaoComercialConsultarStatusPix
gestaoComercialCriarPagamentoPix
gestaoComercialEmailEnviarTemplateTeste
gestaoComercialEmailEnviarTeste
gestaoComercialEmailInicializarTemplates
gestaoComercialEmailListarHistorico
gestaoComercialEmailSalvarConfig
gestaoComercialEmailSalvarTemplate
gestaoComercialEmailTestarApi
gestaoComercialEmailTestarSmtp
gestaoComercialEnviarComunicacao
gestaoComercialFecharCaixa
gestaoComercialFinanceiroCliente
gestaoComercialHistoricoVendas
gestaoComercialProcessarPagamentoToken
gestaoComercialReceberPagamento
gestaoComercialRelatorio
gestaoComercialSmsEncryptTokenOnWrite
gestaoComercialSmsEnviar
gestaoComercialSmsTestarConexao
gestaoComercialTestarConexaoGateway
gestaoComercialTestarConexaoMercadoPago
gestaoComercialValidarCpfToken
gestaoComercialWebhookMercadoPago
gestaoComercialWhatsAppEncryptTokenOnWrite
gestaoComercialWhatsAppEnviar
gestaoComercialWhatsAppTestarConexao
gravarOperacaoStatusEmPedidoOnCreate
gravarOperacaoStatusEmPedidoOnUpdate
lojistaCancelarChamadaEntregador
lojistaCancelarPedidoComEstorno
lojistaConfirmarRetiradaBalcao
lojistaConfirmarRetiradaNaLojaComEstorno
lojistaContinuarBuscaEntregadores
lojistaRedespacharEntregador
lojistaSolicitarDespachoEntregador
marcarContasElegiveisExclusaoDefinitiva
mpConsultarParcelamentosCartao
mpCriarPagamentoPix
mpProcessarPagamentoCartao
mpVincularPagamentoPix
notificarChatMensagemEncomenda
notificarChatMensagemPedido
notificarClienteConfirmacaoCancelamento
notificarClienteStatusPedido
notificarEntregadoresPedidoPronto
notificarEstornoCreditoSaqueRecusado
notificarLojaClienteCancelouPedido
notificarNovoPedido
notificarSuporteAtendimentoIniciadoPeloPainel
notificarSuporteCategoriaEscolhida
notificarSuporteEncerradoPeloPainel
notificarSuporteMensagemAgente
onEntregadorAprovadoPromoverSelfie
onEntregadorPerfilOperacionalAtualizado
onEntregadorStatusCadastroAtualizado
onFiscalIntegrationWrite
onLojistaStatusCadastroAtualizado
onSaqueSolicitacaoAtualizado
onUsuarioCriadoBoasVindas
painelEntregadoresAtualizacoesPendentes
painelValidarPosLoginGoogle
perfilAtualizarTelefoneVerificadoSms
perfilClienteReservarCpf
processarEntregaConcluida
processarEstornoPainel
processarExclusoesPerfilEntregador
processarFinanceiroPedidoOnCreate
processarPagamentoCartaoCrediario
proxyWebmaniaCancelarNota
proxyWebmaniaCartaCorrecao
proxyWebmaniaEmitirNota
proxyWebmaniaInutilizar
proxyWebmaniaTestarConexao
recuperacaoSenhaDefinirNovaSenha
recuperacaoSenhaPosAlteracao
recuperacaoSenhaSolicitar
recuperacaoSenhaVerificarOtp
recusarOfertaCorrida
registrarEventoAuditoriaApp
removerColaboradorPainelLojista
renegociarDividaCallable
reverterRenegociacaoCallable
sincronizarCrlvVeiculoAtivo
sincronizarEstoqueGestaoComercialVendaOnUpdate
sincronizarEstoquePedidoOnUpdate
sincronizarIdentidadePedidosOnUpdate
sincronizarLojaPublicOnWrite
sincronizarVeiculoAtivoCampoPlano
solicitarExclusaoConta
solicitarSaque
testarConexaoMercadoPago
usersInicializarSaldoOnCreate
validarCupom
validarLojistaOperacional
walletCancelarReserva
walletConfirmarDebito
walletLimparReservasExpiradas
walletReservarSaldo
webhookCartaoRecorrente
webhookMercadoPago
webhookMercadoPagoGestaoComercial
```

</details>

### 11.3 Schedulers principais

| Função | Frequência / papel |
|---|---|
| `cancelarPedidosPixExpirados` | ~1 min |
| `expandirBuscaEntregador` | ~1 min (stub) |
| `marcarContasElegiveisExclusaoDefinitiva` | daily 03:00 America/Sao_Paulo |
| `desativarPublicacoesVencidas` | daily 04:00 |
| `assinaturaCobrancaAtrasoScheduled` / `Auto` | cobranças assinatura |
| `assinaturaAvisosTentativasScheduled` | régua avisos 3×/24h |
| `assinaturaVerificarSuspensaoScheduled` | suspensão |
| `fiscalRotinaMensalReset` | reset cota mensal |

---

## 12. Fluxos de negócio (resumo)

### 12.1 Checkout marketplace

Carrinho → cupom (`validarCupom`) → PIX/cartão MP → webhook confirma → financeiro `processarFinanceiroPedidoOnCreate` (v2) → estoque → FCM loja → preparo → despacho entregador → entrega → crédito lojista/entregador + fiscal entregador + FCM.

Código pedido: `PED-XXXXXX` (determinístico do ID).

### 12.2 Tipos de entrega

Códigos: `bicicleta` < `moto` < `carro` < `carro_frete`  
Contrato triplicado: mobile / web / `functions/tipos_entrega.js`.  
Campo loja: `tipos_entrega_permitidos` (espelho `lojas_public`).

### 12.3 Encomendas

Escrita só Functions. Dois pedidos financeiros (entrada + saldo). Status em `encomenda_negociacao_status`. Docs: `docs/ENCOMENDA_ARQUITETURA.md`.

### 12.4 Gestão Comercial / PDV / Crediário

Assinatura ativa → PDV + clientes + crédito + cobranças PIX/cartão + caixa + e-mail/WhatsApp/SMS. Região e-mail: `southamerica-east1`.

### 12.5 Assinaturas

Planos/módulos → PIX ou cartão recorrente → cobranças/inadimplência → avisos (não controlam bloqueio sozinhos) → suspensão scheduled.

### 12.6 Fiscal NF-e

Gate GC + módulo → config empresa/certificado → emitir via proxy Functions → reserva/confirma/estorno saldo em `lojista_integracao` → webhook status → download XML/DANFE só server-side.

Provedores: Focus NFe, Nuvem Fiscal, Webmania, PlugNotas, eNotas, Custom.

### 12.7 Auditoria

Triggers + callables query (`auditLogsListarEventos`, `PesquisarUsuarios`, `Exportar`, `Estatisticas`) → tela `/auditoria`.

---

## 13. Integrações externas

| Integração | Uso |
|---|---|
| Mercado Pago | PIX/cartão marketplace, GC/PDV, assinatura recorrente |
| Provedores NF-e | Emissão/consulta/cancelamento/CC-e/inutilização |
| FCM | Pedidos, logística, chat, suporte, campanhas, cadastros, saques |
| SMTP (nodemailer) | Boas-vindas, OTP, contato, saque, AdminCity, assinaturas, GC |
| Google Sign-In | App + painel (popup/redirect) |
| IBGE | Autocomplete cidades + import AdminCity |
| Comtele SMS | Verificação telefone cadastro |
| ViaCEP / Nominatim | CEP e geocode web |
| Meta Pixel | Site (`config.js`) |
| LocalAuth + SecureStorage | Biometria login/saque |

---

## 14. Índices Firestore

Arquivo: `depertin_cliente/firestore.indexes.json` — **~60** índices compostos.  
Exemplos críticos: `cupons(loja_id, escopo, codigo)`, `avaliacoes_produto(produto_id, data)`, leads marketing, encomendas por cliente/loja, pedidos por loja/status, etc.

Deploy:

```powershell
npx firebase-tools@latest deploy --only firestore:indexes --project depertin-f940f
```

---

## 15. Testes

| Pacote | Qtd / localização |
|---|---|
| Functions | 27 `*.test.js` em `functions/test/` (+ integration com emulator) |
| Web | ~9 em `depertin_web/test/` (fiscal, App Check, crédito, módulo fiscal) |
| Mobile | testes pontuais (ex. tipos_entrega) |

Scripts Functions: `npm test`, `npm run test:unit`, `npm run test:integrated`.

---

## 16. Deploy produção (checklist)

Acionado por frases como “enviar para produção” (rule `producao-deploy.mdc`):

1. Garantir `GC_EMAIL_CONFIG_SECRET` no `.env`
2. Redeploy Functions e-mail GC (lista seletiva ou full)
3. `firestore:rules` (+ indexes se mudou)
4. Functions marketplace alteradas
5. Build + FTP painel web
6. Smoke: e-mail GC, templates, histórico, console painel

**Nunca:** commitar `.env`; force-push main; alterar pipeline FCM.

---

## 17. Ferramentas DEV (NÃO deployar)

| Arquivo | Uso |
|---|---|
| `dev-iniciar-limpeza.ps1` | Sobe UI limpeza localhost |
| `dev-limpeza-total-firestore.js` | Wipe ambiente testes (preserva master/config/planos/fretes/categorias/cidades) |
| `dev-listar-usuarios-limpeza-*` | Server + HTML seleção usuários |
| Scripts em `functions/scripts/` | seed master, credit saldo, backfill lojas_public, etc. |

---

## 18. Documentação modular existente (`docs/`)

| Arquivo | Tema |
|---|---|
| `MAPA_DO_PROJETO.md` | Mapa alto nível |
| `ENCOMENDA_ARQUITETURA.md` | Encomendas |
| `GESTAO_COMERCIAL.md` / checklist | GC |
| `MODULO_FISCAL_NF_E.md` / `FINALIZACAO_*` / `AUDITORIA_*` | Fiscal |
| `SEGURANCA_ALERTAS.md` / `ANALISE_SEGURANCA_COMPLETA.md` | Segurança |
| `CHECKLIST_ALERTAS_CORRIDA_ANDROID.md` | Corrida Android |
| `AUDITORIA_PIX_*` | PIX GC/crediário |

Memória Cursor (rules): `analise-profunda-projeto.mdc` §49 (21/jul/2026) tem precedência sobre snapshots anteriores.

---

## 19. Contagens inventário (21/jul/2026)

| Métrica | Valor |
|---|---|
| Versão mobile | 1.2.8+24 |
| Versão web | 1.0.0+1 |
| Rotas shell web | **56** |
| Functions módulos `.js` | **74** |
| Exports | **238** |
| Testes Functions | **27** |
| Índices Firestore | **~60** |
| Screens mobile (arquivos) | **~80** |
| Screens web | **~65** |
| Services mobile / web | **39 / ~67** |
| Docs `docs/*.md` | **12** |

---

## 20. Status de pedido (referência)

Arquivos: `depertin_cliente/lib/constants/pedido_status.dart` (+ espelho web).

Inclui (não exaustivo): `aguardando_pagamento`, `pendente`, `aceito`, `em_preparo`, `pronto`, `aguardando_entregador`, `entregador_indo_loja`, `saiu_entrega` / `a_caminho` / `em_rota`, `entregue`, cancelamentos, `encomenda_entrada_paga`, etc.

---

## 21. Convenções de código

- Idioma: **português** (arquivos, classes UI, mensagens)
- State: Provider (mobile cart/connectivity/location; web nav)
- Arquitetura: screens + services + widgets + utils + constants + models
- Versionamento mobile: `dart run tool/bump_version.dart`
- Diff mínimo; preservar FCM; validar com `dart analyze` nos arquivos tocados
- Respostas do agente: sempre em português

---

## 22. Riscos conhecidos (monitorar)

1. Segredos OAuth / `.env` — nunca versionar; rotacionar se vazou
2. App Check desativado no painel web; iOS Firebase options ausente
3. Proteção `site/sistema/` é client-side (não substitui Auth)
4. Gap possível: índice `pedidos(cliente_id, cupom_codigo)` na 1ª execução `limite_por_usuario`
5. Proposta encomenda no painel web pode omitir `formas_pagamento_entrada_loja` (gap conhecido)
6. `expandirBuscaEntregador` ainda stub

---

*Fim do documento. Para detalhes de implementação linha a linha, usar as rules Cursor e os módulos citados em `depertin_cliente/functions/` e `docs/`.*
