# DiPertin — MEMÓRIA COMPLETA DO PROJETO

> Data da análise: 02/07/2026
> Última análise profunda: 02/07/2026 — incluindo working tree não commitado
> Versão mobile: **1.2.7+23** (pubspec.yaml)
> Versão painel web: **1.0.0+1**
> Node runtime: 20 | Flutter SDK mobile: ^3.11.1 | Flutter SDK web: ^3.11.3

---

## 1. VISÃO GERAL

**DiPertin** é um marketplace + delivery local Brasileiro. Clientes compram em lojas da região, lojistas gerenciam cardápio e pedidos, entregadores realizam entregas, e operações/admin são feitas via painel web.

- **Projeto Firebase:** `depertin-f940f`
- **Região Functions:** `us-central1` (marketplace) + `southamerica-east1` (Gestão Comercial)
- **Domínio público:** `https://www.dipertin.com.br/`
- **Painel web:** `https://www.dipertin.com.br/sistema/#/login`
- **ApplicationId:** `com.dipertin.app`
- **Signing:** `upload-keystore.jks` (alias `upload`)
- **Cidades atuais:** Rondonópolis-MT e Toledo-PR

---

## 2. ARQUITETURA — 4 MÓDULOS PRINCIPAIS

### 2.1 App Mobile (`depertin_cliente/`)
- **Stack:** Flutter (Android) + Kotlin nativo + Firebase
- **~155 arquivos Dart, 39 services, 68 telas, 18 widgets, 14 utils**
- **16 arquivos Kotlin nativos** para corrida do entregador (Activity fullscreen, FCM service, ícone flutuante)

### 2.2 Painel Web (`depertin_web/`)
- **Stack:** Flutter Web + Firebase
- **~95 arquivos Dart, 28 services, 55 telas, 52 widgets, 17 utils**
- **51 rotas shell no total** (PainelRoutes.ordem, índices 0–50), incluindo 7 de Assinaturas, 9 de Gestão Comercial, 6 de Centro de Operações
- Depende do `depertin_cliente` como path dependency (pubspec.yaml)
- ⚠️ Erro de sintaxe conhecido em `cobrancas_assinatura_service.dart` linha 63: `?canal` em vez de `canal`

### 2.3 Cloud Functions (`depertin_cliente/functions/`)
- **51 módulos JS, ~26 scripts CLI, 2+ exports no index.js**
- **Mistura v1 e v2** (onCall, onRequest, onCreate, onUpdate, onWrite, Scheduled)
- **Helpers compartilhados:** notification_dispatcher.js, repasse_financeiro.js, smtp_transport.js, cupom_helpers.js, codigo_pedido.js, tipos_entrega.js, audit_log_helper.js

### 2.4 Site Institucional (`site/`)
- HTML/CSS/JS estático com SEO (JSON-LD), landing pages por cidade, demo SEO
- Deep link de produto em `/p/` (Android App Links + deferred deep link)
- Firebase Hosting + Apache (.htaccess)

---

## 3. STACK TECNOLÓGICO

| Camada | Tecnologia |
|--------|-----------|
| **Mobile** | Flutter 3.11.1+, Dart, Kotlin (nativo Android) |
| **Web** | Flutter 3.11.3+, Dart |
| **Backend** | Firebase (Auth, Firestore, Storage, FCM, App Check, Cloud Functions) |
| **Pagamentos** | Mercado Pago (PIX + cartão) |
| **E-mail** | SMTP/Nodemailer + Comtele SMS (verificação telefone) |
| **Auth** | Email/senha + Google Sign-In + Biometria (LocalAuth + SecureStorage) |
| **Notificações** | FCM + Android nativo (IncomingDeliveryFirebaseService) |
| **State** | Provider (ChangeNotifier) |
| **Charts** | fl_chart |
| **PDF** | pdf + printing |

---

## 4. DESIGN SYSTEM DiPertin (OBRIGATÓRIO)

### Cores Primárias (INALTERÁVEIS)
| Token | Cor | Hex |
|---|---|---|
| `diPertinRoxo` / `primaryRoxo` | Roxo principal | `#6A1B9A` |
| `primaryRoxoEscuro` | Roxo escuro | `#4A148C` |
| `primaryRoxoMedio` | Roxo médio | `#7B1FA2` |
| `primaryRoxoClaro` | Roxo claro | `#8E24AA` |
| `diPertinLaranja` / `secondaryLaranja` | Laranja | `#FF8F00` |
| `secondaryLaranjaSuave` | Laranja suave | `#FFB74D` |

### Neutros
| Token | Cor | Hex |
|---|---|---|
| `backgroundFundo` | Fundo telas | `#F5F4F8` |
| `textPrimary` | Texto primário | `#1A1A2E` |
| `textSecondary` / `_textoMuted` | Texto secundário | `#64748B` |
| `surfaceCard` | Fundo cards | `#FFFFFF` |

### Sidebar (web)
| Token | Cor |
|---|---|
| sidebarBackground | `#2D1B4E` (gradient start) |
| sidebarBackgroundEnd | `#1A0F2E` (gradient end) |
| sidebarHover | `0x1A6A1B9A` |
| sidebarAtivoBackground | `0x336A1B9A` |

### Regras de Design
- **NUNCA** usar dourado, prata, bronze, vermelho genérico, azul aleatório
- **Rankings/pódios:** roxo (1º), laranja (2º), roxo 50% opacity (3º)
- **Gradientes:** sempre roxo como base → `#8E24AA`
- **Status "Aberta":** verde `#22C55E` / fundo `#E8F5E9`
- **Status "Fechada":** vermelho `#EF4444` / fundo `#FEF2F2`
- **Fonte web:** Plus Jakarta Sans (Google Fonts)
- **Skeleton:** usar `_textoMuted` com alpha reduzido

---

## 5. FIREBASE — COLEÇÕES PRINCIPAIS

### Marketplace
| Coleção | Uso | Regra |
|---|---|---|
| `users` | Perfis (role, saldo, loja_id, fcm_token, bloqueio, selfie_bloqueada) | Fechada: dono + staff + colaborador |
| `users/{uid}/veiculos/{vid}` | Veículos do entregador (moto/carro/bike) | Dono + staff |
| `users/{uid}/documentos/{tipo}` | CNH do entregador | Dono + staff |
| `users/{uid}/enderecos` | Endereços do cliente | Dono + staff |
| `users/{uid}/clientes_comercial` | Gestão Comercial — clientes da loja | Lojista + staff |
| `lojas_public/{uid}` | Espelho público (vitrine) | Read público, write false |
| `pedidos` | Pedidos + mensagens subcoleção | Participantes + entregador |
| `produtos` | Produtos das lojas | Read público |
| `avaliacoes` | Avaliações de pedidos | Read público |
| `avaliacoes_produto` | Avaliações por produto (`{pedidoId}_{produtoId}`) | Read público |
| `encomendas` | Encomendas/negociação | Participantes (write false — só Admin) |
| `encomendas/{id}/mensagens` | Chat encomenda | Participantes |
| `cupons` | Cupons (loja + global) | Staff + lojista própria loja |
| `categorias` | Categorias de produto | Read público, write staff |
| `sugestoes_categorias` | Sugestões de categorias | Staff + lojista cria |
| `banners` | Banners por cidade | Read público |
| `gateways_pagamento` | Config do gateway (MP access_token) | Staff only |
| `planos_taxas` | Taxas e comissões | Read autenticado |
| `tabela_fretes` | Regras de frete | Read autenticado |
| `saques_solicitacoes` | Solicitações de saque | Dono + staff (create false) |
| `estornos` | Estornos de saque | Dono + staff |
| `comunicados` | Comunicados CMS | Read público |
| `notificacoes_campanhas` | Campanhas push | Staff |
| `notificacoes_usuario/{uid}/items` | Histórico in-app de pushes | Próprio uid |
| `support_tickets` | Tickets de suporte | Dono + staff |
| `fiscal/{uid}/**` | Fiscal entregador | Dono + staff (write false) |
| `audit_logs` | Auditoria administrativa | Staff |
| `centro_ops_agenda` | Agenda operacional | Staff |
| `marketing_leads_lojistas` | CRM leads lojistas | Staff |
| `marketing_leads_entregadores` | CRM leads entregadores | Staff |

### Segurança (Coleções com write false — só Admin SDK)
| Coleção | Propósito |
|---|---|
| `password_reset_tokens` | Tokens de recuperação de senha |
| `password_reset_rate_*` | Rate limit de recuperação |
| `cadastro_telefone_verificado_tickets` | Tickets de verificação SMS |
| `comtele_cadastro_rate_*` | Rate limit SMS Comtele |
| `users_cpf_index` | Índice de unicidade CPF |

### Gestão Comercial
| Coleção | Uso |
|---|---|
| `gestao_comercial_configuracoes/{lojaId}` | Config da loja (crediário, e-mail, notificações) |
| `gestao_comercial_recebimentos/{id}` | Recebimentos registrados |
| `gestao_comercial_vendas/{id}` | Histórico de vendas |
| `gestao_comercial_cobrancas/{id}` | Cobranças de pagamento |
| `gestao_comercial_email_templates/{lojaId}/templates/{id}` | Templates de e-mail |
| `gestao_comercial_email_historico/{lojaId}/envios/{id}` | Histórico de envios (write false) |
| `gestao_comercial_integracoes_pagamento/{lojaId}/gateways/{id}` | Integrações de pagamento |
| `sessoes_caixa/{id}` | Sessões de caixa PDV |
| `assinaturas_modulos / _gateways / _bancos / _configuracoes` | Config assinaturas |
| `assinaturas_clientes/{id}` | Assinaturas contratadas |
| `modulos_planos/{id}` | Planos disponíveis |
| `receitas_app / despesas_app` | Financeiro app (staff) |

---

## 6. PERFIS E PERMISSÕES

### Roles do Sistema
| Role | Descrição | Acesso |
|---|---|---|
| `master` | Super admin | Tudo |
| `master_city` | Admin por cidade | Staff (quase tudo) |
| `lojista` | Dono de loja | Própria loja + pedidos |
| `cliente` | Comprador | Próprios dados + pedidos |
| `entregador` | Entregador | Corridas + carteira |

### Níveis de Lojista (painel web)
| Nível | Acesso |
|---|---|
| I (básico) | Dashboard limitado |
| II (+cardápio) | Cardápio + Cupons |
| III (+carteira, config, colaboradores) | Financeiro + Config + Colaboradores |

### Hierarquia de Acesso (Firestore Rules)
1. **Staff** (master / master_city) → acesso total (exceto coleções sensíveis)
2. **Dono** (request.auth.uid == userId) → próprio perfil
3. **Colaborador nível 3** (lojista_owner_uid aponta) → edita dono (exceto campos privilegiados)
4. **Colaborador qualquer nível** → pode ler dono
5. **Dono da loja** → pode ler colaboradores (lojista_owner_uid)
6. **Demais usuários** → só dados públicos (lojas_public, produtos, etc.)

---

## 7. FLUXOS PRINCIPAIS

### 7.1 Fluxo de Pedido
1. Cliente navega na vitrine (`lojas_public`) → adiciona ao carrinho
2. Checkout: endereço + pagamento (PIX/cartão via Mercado Pago)
3. **onCreate pedido:** notifica loja (FCM), calcula financeiro (v2)
4. **onUpdate pedido (pagamento confirmado):** baixa estoque, loja pode iniciar preparo
5. Lojista marca como pronto → **notificarEntregadoresPedidoPronto** (FCM, raio progressivo)
6. Entregador aceita → **Activity nativa** (tela cheia, som, vibração, LED)
7. **onUpdate (entregue):** recalcula financeiro (v3), credita saldo lojista + entregador, FCM cliente

### 7.2 Fluxo de Corrida do Entregador (Android Nativo)
1. Cloud Function envia FCM `tipoNotificacao=nova_entrega`
2. `IncomingDeliveryFirebaseService` intercepta → `IncomingDeliveryActivity` (showWhenLocked)
3. UI nativa: avatar, valores, countdown, botões Aceitar/Recusar
4. `CorridaIncomingNotifier`: heads-up + som + vibração
5. `FloatingIconService`: foreground service com ícone flutuante (background)
6. `flash_alerta_corrida.dart`: fallback Flutter se Activity não abrir

### 7.3 Fluxo de Cupons
1. Lojista cria cupom (escopo loja) ou admin cria (escopo global)
2. Cliente aplica no carrinho → `validarCupom` (callable) valida código, vigência, limite, escopo
3. Desconto aplicado: split `desconto_cupom_produto` + `desconto_cupom_frete`
4. `processarFinanceiroPedidoOnCreate` incrementa `usos_atual` (idempotente)

### 7.4 Fluxo de Encomendas
1. Cliente monta sacola só com produtos `tipo_venda=encomenda`
2. `encomendaClienteCriar` → loja aceita negociar → proposta (valor, entrada, formas pgto)
3. Cliente aceita → pedido de entrada (PIX/cartão) → MP confirma → loja produz
4. Gera pedido de saldo final → cliente paga → logística normal

### 7.5 Fluxo de Tipos de Entrega
- 4 tipos canônicos: `bicicleta` < `moto` < `carro` < `carro_frete`
- Loja configura tipos permitidos, espelhado em `lojas_public`
- Carrinho calcula frete pelo `maiorTipo` entre produtos
- Despacho filtra entregadores por compatibilidade de veículo

### 7.6 Fluxo de Cadastro com SMS
1. Cliente digita celular (11 dígitos, 9º=9)
2. Comtele envia SMS com OTP 6 dígitos
3. Android SMS User Consent auto-preenche OTP
4. Valida → cria ticket → cadastro cria `users` + reserva CPF

---

## 8. ARQUITETURA DO CÓDIGO

### 8.1 Mobile — Camadas
```
screens/     → Telas (StatefulWidget, ~68 telas)
services/    → Lógica de negócio + Firebase (39 services)
providers/   → ChangeNotifier (CartProvider)
models/      → Data classes (UserModel, ProductModel, CartItemModel)
widgets/     → Componentes reutilizáveis (18 widgets)
utils/       → Helpers (14 utils)
constants/   → Constantes e enums (9 arquivos)
config/      → Config (Google Sign-In)
auth/        → Auth helpers (Google signIn)
```

### 8.2 Web — Camadas
```
screens/     → Telas (~55 telas)
services/    → Lógica de negócio (28 services, +7 da Gestão Comercial/Assinaturas)
models/      → Data classes (14 modelos: GC + Assinaturas + Vendas)
widgets/     → Componentes (~52 widgets, incluindo 19 do módulo Comercial + 5 de Assinaturas)
utils/       → Helpers (17 utils, incluindo vendas_historico_pdf, csv_download)
navigation/  → PainelRoutes (51 rotas shell, índices 0–50), PainelNavController, PainelNavigationScope
theme/       → DiPertinTheme (design system completo, 40+ tokens de cor, 4 gradientes)
```

### 8.3 Funções — Categorias
```
Marketplace:       pedidos, logística, notificações, cupons, avaliações, estoque
Auth/Cadastro:     recuperação senha, SMS, boas-vindas, exclusão conta
Gestão Admin:      AdminCity, marketing leads, auditoria, agenda, campanhas
Pagamentos:        Mercado Pago (PIX, cartão, estorno), crediário
Entregador:        perfil operacional, selfie, veículos, fiscal
Lojista:           status cadastro, estorno frete, encomendas
Sincronização:     lojas_public, identidade pedidos, veículo ativo
Gestão Comercial:  e-mail transacional, configurações, cobranças
```

---

## 9. REGRAS INVIOLÁVEIS DO PROJETO

1. **NÃO MEXER NO FCM / Notificações.** Pipeline de push (IncomingDelivery*, fcm_rota, notification_dispatcher, chat_pedido_notificacao, corrida_chamada_entregador_audio, CorridaIncomingNotifier, IncomingDeliveryFirebaseService, NotificacoesHistoricoService) está funcionando. Preservar 100% payloads, chaves, canais, collapseKeys.

2. **Padrão de alerta sem push:** persistir mapa `alerta_*` no doc users (ex.: `alerta_tipos_entrega_incompat`) e consumir via StreamBuilder. Permite dispensar com `dispensado_em >= ultimo_em`.

3. **Paleta de cores DiPertin:** roxo `#6A1B9A` + laranja `#FF8F00`. NUNCA usar cores fora da paleta.

4. **Safe area:** `DiPertinSafeMediaQuery`, `DiPertinScrollBody`, `DiPertinSafeBottomPanel`, `diPertinScrollPaddingTabShell`.

5. **Contratos triplicados:** código pedido, tipos de entrega, cupons — sempre 3 versões (mobile, web, functions). Testes em 2 versões (Dart + JS).

6. **NÃO commitar .env** com secrets (SMTP, MP, Comtele).

---

## 10. INTEGRAÇÕES EXTERNAS

| Integração | Uso | Chaves/Config |
|---|---|---|
| **Mercado Pago** | PIX + cartão (webhook HMAC) | `MP_WEBHOOK_SECRET`, `gateways_pagamento/mercado_pago.access_token` |
| **FCM** | Notificações push (Firebase Cloud Messaging) | Built-in Firebase |
| **SMTP (nodemailer)** | E-mails transacionais | `.env` (SMTP_HOST, SMTP_USER, etc.) |
| **Comtele** | Verificação telefone por SMS | `COMTELE_AUTH_KEY` no `.env` |
| **Google Sign-In** | Login social | `google_sign_in_config.dart` (serverClientId) |
| **IBGE API** | Autocomplete cidades + importação massa | Pública |
| **ViaCEP** | Autocomplete CEP (address_screen) | Pública |
| **Nominatim/OSM** | Reverse geocoding web | Pública |
| **Meta Pixel** | Rastreamento site | `metaPixelId` em config.js |

---

## 11. FERRAMENTAS DE DESENVOLVIMENTO

| Ferramenta | Localização | Uso |
|---|---|---|
| `bump_version.dart` | `depertin_cliente/tool/` | Bump versionCode + versionName |
| `build_sistema.ps1` | `depertin_web/` | Build do painel web |
| `deploy_sistema_ftp.ps1` | `depertin_web/` | Deploy FTP do painel |
| `dev-*` (limpeza) | Raiz do repo | Wipe do Firestore para testes (NÃO usar em prod) |
| `DiPertin.code-workspace` | Raiz | Workspace multi-root VS Code |

---

## 12. PONTOS DE ATENÇÃO (RISCOS CONHECIDOS)

1. **OAuth client_secret** versionado no repo → documentado em `docs/SEGURANCA_ALERTAS.md`
2. **contato_site:** cooldown IP só em memória (múltiplas instâncias); CORS `*`
3. **candidatura_vaga:** callable sem auth explícita
4. **campanhas:** `publico_alvo=todos` pode carregar até 200K docs users
5. **`expandirBuscaEntregador`:** scheduled stub (return null)
6. **iOS não configurado** no firebase_options (UnsupportedError)
7. **App Check desativado na Web** (painel) — removido para evitar reCAPTCHA error
8. **App Check mobile:** `firebase_app_check_token_auto_refresh=false` (evita loop Play Integrity)
9. **Índice `pedidos(cliente_id, cupom_codigo)` pode ser necessário** em produção para `limite_por_usuario`
10. **Painel web ainda lê campos planos** (`veiculoTipo`, `url_crlv`) em users; compat via trigger

---

## 13. FUNCTIONS — EXPORTS PRINCIPAIS (index.js)

### Triggers Firestore
- `notificarNovoPedido` (onCreate pedidos)
- `notificarLojaClienteCancelouPedido` (onUpdate)
- `notificarClienteStatusPedido` (onUpdate)
- `notificarClienteConfirmacaoCancelamento` (onUpdate)
- `processarEntregaConcluida` (onUpdate — crédito saldos)
- `processarFinanceiroPedidoOnCreate` (onCreate — financeiro v2)
- `notificarEntregadoresPedidoPronto` (onUpdate — logística)
- `atualizarRatingLojaAposAvaliacao` (onCreate avaliacoes)
- `atualizarRatingProdutoOnCreate/OnUpdate/OnDelete` (avaliacoes_produto)
- `baixarEstoquePedidoOnCreate` + `sincronizarEstoquePedidoOnUpdate`
- `gravarOperacaoStatusEmPedidoOnCreate/OnUpdate` (timeline)
- `auditLogPedidoOnCreate/OnUpdate` (auditoria)
- `sincronizarLojaPublicOnWrite` (users → lojas_public)
- `sincronizarIdentidadePedidosOnUpdate` (denormalização pedidos)
- `sincronizarVeiculoAtivoCampoPlano` (veiculos → users)
- `onLojistaStatusCadastroAtualizado` (users)
- `onEntregadorStatusCadastroAtualizado` (users)
- `onEntregadorAprovadoPromoverSelfie` (users)
- `notificarChatMensagemPedido` (pedidos/mensagens)
- `onSaqueSolicitacaoAtualizado` (saques_solicitacoes)
- `enviarCampanhaNotificacao` (notificacoes_campanhas)

### Callables v1
- `validarCupom`, `aceitarOfertaCorrida`, `recusarOfertaCorrida`
- `entregadorValidarCodigoEntrega`, `entregadorCancelarCorridaERedespachar`
- `entregadorCancelarPorIncompatibilidade`
- `lojistaRedespacharEntregador`, `lojistaCancelarChamadaEntregador`
- `lojistaContinuarBuscaEntregadores`, `lojistaSolicitarDespachoEntregador`
- `lojistaConfirmarRetiradaNaLojaComEstorno`
- `lojistaConfirmarRetiradaBalcao` (NOVO)
- `lojistaCancelarPedidoComEstorno` (NOVO)
- `solicitarExclusaoConta`, `validarLojistaOperacional`
- `painelValidarPosLoginGoogle`, `excluirClienteAdminMaster`
- `adminCityCadastrarUsuario/AtualizarUsuario/BloquearUsuario/ExcluirUsuario`
- `adminCityImportarCidadesIbge`
- `painelEntregadoresAtualizacoesPendentes`
- `cadastrarColaboradorPainelLojista/.../Remover...`
- `enviarCandidaturaVaga`
- `registrarEventoAuditoriaApp`

### Callables v2
- `recuperacaoSenhaSolicitar/VerificarOtp/DefinirNovaSenha/PosAlteracao`
- `mpCriarPagamentoPix`, `mpVincularPagamentoPix`, `mpProcessarPagamentoCartao`
- `mpConsultarParcelamentosCartao`
- `estornarPagamentoPedidoCancelado`, `processarEstornoPainel`
- `cancelarPedidoPixExpirado`
- `solicitarSaque`
- `comteleCadastroTelefoneEnviarCodigo/ValidarCodigo`
- `cadastroConfirmarTelefoneVerificadoSms`, `perfilAtualizarTelefoneVerificadoSms`
- `cadastroClienteSalvarPerfilInicial`, `perfilClienteReservarCpf`
- `encomendaClienteCriar`, `encomendaLojaAceitarNegociacao`, etc.
- `entregadorAbrirCadastro`, `entregadorAutoBloquearTemporario/Definitivo`
- `entregadorSolicitarExclusaoPerfil`, `entregadorAutoDesbloquearConta`
- Gestão Comercial: `gestaoComercialEmailSalvarConfig`, etc.

### Scheduled
- `marcarContasElegiveisExclusaoDefinitiva` (diário 03:00 SP)
- `cancelarPedidosPixExpirados` (1 min)
- `expandirBuscaEntregador` (1 min — stub)
- `desativarPublicacoesVencidas` (diário 04:00 SP)
- `processarExclusoesPerfilEntregador`

### HTTP
- `avaliacoesSitePublicas` (GET, avaliações públicas)
- `enviarContatoSite` (POST, formulário contato)
- `webhookMercadoPago` (POST, webhook MP)

---

## 14. TELAS E ROTAS MOBILE

### Auth
- `login_screen.dart` — Email/senha + Google + Biometria ("Acessar por Digital")
- `register_screen.dart` — Cadastro (CPF, SMS, endereço onboarding)
- `recuperar_senha_screen.dart` — OTP 4 dígitos
- `ativacao_biometria_screen.dart` — Modal premium pós-login

### Cliente
- `vitrine_screen.dart` — Home (lojas por cidade)
- `search_screen.dart` — Busca
- `cart_screen.dart` (~132KB) — Carrinho (frete por veículo, cupons)
- `checkout_pagamento_screen.dart` — Checkout PIX/cartão
- `orders_screen.dart` (~90KB) — Meus pedidos + chat + avaliação
- `product_details_screen.dart` — Detalhe produto
- `address_screen.dart` — Endereço (GPS + ViaCEP)
- `meus_enderecos_screen.dart` — Gerenciar endereços
- `chat_pedido_screen.dart` — Chat do pedido
- `chat_suporte_screen.dart` — Central de ajuda
- `avaliar_pedido_sheet.dart` — Avaliação pós-entrega
- `cliente_encomendas_list_screen.dart` / `_detalhe_screen.dart` — Encomendas

### Lojista
- `lojista_dashboard_screen.dart` — Hub premium
- `lojista_pedidos_screen.dart` (~80KB) — Abas coloridas por status
- `lojista_produtos_screen.dart` / `lojista_edit_produto_screen.dart`
- `lojista_cupons_screen.dart` (~918 linhas) — CRUD cupons
- `lojista_encomendas_screen.dart` — Encomendas (4 abas)
- `lojista_config_screen.dart` / `lojista_form_screen.dart` (bloqueio 30 dias)
- `tipos_entrega_loja_screen.dart` — Config tipos de entrega

### Entregador
- `entregador_dashboard_screen.dart` (~150KB) — Radar/ofertas
- `entregador_carteira_screen.dart` — Carteira + biometria saque
- `configuracoes/` — Hub, acessibilidade, veículos, documentos, fiscal

### Comum
- `profile_screen.dart` (~65KB) — Perfil central + sino notificações
- `conta_seguranca_screen.dart` — Toggle biometria
- `minhas_notificacoes_screen.dart` — Histórico in-app

---

## 15. TELAS E ROTAS WEB (55 no shell)

### Staff (master/master_city)
| Rota | Tela |
|---|---|
| `/dashboard` | `dashboard_screen.dart` (KPIs, charts) |
| `/lojas` | `lojas_screen.dart` |
| `/lojas_financeiro` | `lojas_financeiro_dashboard_screen.dart` |
| `/entregadores` | `entregadores_screen.dart` (~161KB, 4 abas) |
| `/clientes` | `central_clientes_screen.dart` |
| `/banners` | `banners_screen.dart` |
| `/categorias` | `categorias_screen.dart` |
| `/admincity` | `admincity_usuarios_screen.dart` |
| `/admincity_cidades` | `admincity_cidades_screen.dart` |
| `/utilidades` | `utilidades_screen.dart` (~100KB) |
| `/financeiro` | `financeiro_screen.dart` (~142KB) |
| `/financeiro_saques` | `solicitacoes_saques_painel_screen.dart` |
| `/configuracoes` | `configuracoes_screen.dart` |
| `/configuracao_cadastro_acesso` | `cadastro_acesso_colaboradores_screen.dart` |
| `/atendimento_suporte` | `atendimento_suporte_screen.dart` |
| `/notificacoes` | `notificacoes_screen.dart` (campanhas) |
| `/cupons` | `cupons_screen.dart` (globais) |
| `/monitor_pedidos` | `monitor_pedidos_screen.dart` |
| `/centro_operacoes_crm` | `CentroOperacoesCrmScreen` (hub CRM) |
| `/centro_operacoes_marketing` | `PainelMarketingDashboard` |
| `/centro_operacoes_leads_lojistas` | `PainelLeadsLojistas` (Kanban CRM) |
| `/centro_operacoes_leads_entregadores` | `PainelLeadsEntregadores` (Kanban CRM) |
| `/centro_operacoes_agenda` | `PainelCentroOpsAgenda` |
| `/centro_operacoes_frete` | `CentroOperacoesFreteScreen` (simulador) |
| `/avaliacoes_painel` | `avaliacoes_painel_screen.dart` |
| `/comunicados` | `comunicados_screen.dart` |
| `/conteudo_legal` | `conteudo_legal_screen.dart` |
| `/pdv` | `lojista_pdv_screen.dart` |

### Lojista
| Rota | Tela | Gate |
|---|---|---|
| `/meus_pedidos` | `lojista_meus_pedidos_screen.dart` | Lojista |
| `/negociacoes_encomenda` | `lojista_negociacoes_encomenda_screen.dart` | Lojista |
| `/meu_cardapio` | `lojista_meu_cardapio_screen.dart` | Lojista |
| `/meus_cupons` | `lojista_cupons_screen.dart` | Nível ≥II |
| `/carteira_loja` | `lojista_minha_carteira_screen.dart` | Nível ≥III |
| `/carteira_financeiro` | `lojista_carteira_financeiro_screen.dart` | Nível ≥III |
| `/carteira_relatorio` | `lojista_carteira_relatorio_screen.dart` | Nível ≥III |
| `/carteira_configuracao` | `lojista_carteira_configuracao_screen.dart` | Nível ≥III |
| `/configuracoes_lojista` | `configuracoes_lojista_screen.dart` | Nível ≥III |
| `/comercial_dashboard` | `lojista_comercial_dashboard_screen.dart` | Lojista |
| `/comercial_clientes` | `lojista_comercial_clientes_screen.dart` | Lojista |
| `/comercial_credito` | `lojista_comercial_credito_screen.dart` | Lojista |

### Assinaturas (Staff)
| Rota | Tela |
|---|---|
| `/assinaturas_dashboard` | `assinaturas_dashboard_screen.dart` |
| `/assinaturas_clientes` | `assinaturas_clientes_screen.dart` |
| `/assinaturas_planos` | `assinaturas_planos_screen.dart` |
| `/assinaturas_configuracoes` | `assinaturas_configuracoes_screen.dart` |

### Gestão Comercial (Staff)
| Rota | Tela |
|---|---|
| `/comercial_pendencias` | `comercial_pendencias_screen.dart` |
| `/comercial_recebimentos` | `comercial_recebimentos_screen.dart` |
| `/comercial_historico` | `comercial_historico_vendas_screen.dart` |
| `/comercial_relatorios` | `comercial_relatorio_screen.dart` |
| `/comercial_configuracoes` | `comercial_configuracoes_screen.dart` |

---

## 16. GESTÃO COMERCIAL (Módulo Completo)

Módulo SaaS para lojistas administrarem crédito/fiado, PDV, e-mail transacional, cobranças e recebimentos de clientes da própria loja. Functions rodam em **`southamerica-east1`**.

### Telas Web (9 rotas: 36–43 + PDV rota 27)
- `/pdv` → `lojista_pdv_screen.dart` (**5.037 linhas**, maior tela do sistema)
- `/comercial_dashboard` → `lojista_comercial_dashboard_screen.dart` (1.570 linhas, CustomPainter gráficos)
- `/comercial_clientes` → `lojista_comercial_clientes_screen.dart` (1.397 linhas)
- `/comercial_credito` → `lojista_comercial_credito_screen.dart` (1.956 linhas, 5 abas)
- `/comercial_pendencias` → `comercial_pendencias_screen.dart`
- `/comercial_recebimentos` → `comercial_recebimentos_screen.dart`
- `/comercial_historico` → `comercial_historico_vendas_screen.dart` (com export PDF)
- `/comercial_relatorios` → `comercial_relatorio_screen.dart` (fl_chart)
- `/comercial_configuracoes` → `comercial_configuracoes_screen.dart` (**3.727 linhas**, 4 abas)

### Services (8)
- `comercial_dashboard_service.dart` (751 linhas, agrega métricas pedidos+produtos+clientes)
- `comercial_clientes_service.dart` (597 linhas, CRUD + resumo pedidos)
- `comercial_credito_service.dart` (587 linhas, venda em transação atômica)
- `comercial_recebimentos_service.dart` (503 linhas)
- `comercial_pendencias_service.dart` (239 linhas, juros/multa)
- `comercial_email_transacional_service.dart` (190 linhas, singleton, region southamerica-east1)
- `comercial_config_service.dart` (62 linhas, JurosMultaConfig)
- `vendas_historico_service.dart` (116 linhas)

### Widgets (19 + gates)
- `gestao_comercial_access_gate.dart` (216 linhas, gate de acesso com 3 estados)
- `gestao_comercial_bloqueio_admin_screen.dart` (bloqueio admin)
- `gestao_bloqueada_screen.dart` (inadimplência)
- Modais: `comercial_email_transacional_modal` (2.171 linhas), `comercial_enviar_comunicacao_modal` (1.283 linhas)
- **Maior widget:** `comercial_renegociar_divida_modal.dart` (**5.057 linhas**)
- Financeiros: `comercial_financial_table.dart` (485), `comercial_historico_financeiro_modal` (1.900), `comercial_credito_modal` (1.017), `comercial_remover_credito_modal` (1.000)
- Dashboard: `comercial_dashboard_acoes` (70), `comercial_debt_chart_card` (172), `comercial_quick_actions_card` (96), `comercial_top_debtors_card` (147)
- Utilitários: `comercial_financial_action_menu` (139), `comercial_financial_filters` (228), `comercial_financial_status_badge` (62), `comercial_financial_summary_card` (116), `comercial_pendencias_modal` (231), `comercial_bloquear_credito_modal` (618)
- `comercial_cliente_recebimento_modal.dart` (885 linhas)

### Functions (8 módulos, ~52 exports no index.js)
| Arquivo | Linhas | Exports | Função |
|---------|--------|---------|--------|
| `gestao_comercial_functions.js` | **4.188** | **32** | PIX, caixa, crédito, WhatsApp, SMS, API externa, automação, token de cobrança |
| `gestao_comercial_email.js` | **1.069** | **9** | E-mail transacional (SMTP + API), 16 templates, AES-256-GCM |
| `gestao_comercial_pagamento.js` | **471** | **13 helpers** | Camada unificada PIX/cartão |
| `mercado_pago_gestao_comercial.js` | **903** | **4** | Webhook MP dedicado GC + PDV PIX |
| `payment_gateway_provider.js` | **670** | **6** | Abstração multi-gateway (MP, Asaas, REST) |
| `pix_emv_validacao.js` | **226** | **7** | Validação CPF/CNPJ Mod 11, parse EMV BR Code |
| `renegociacao_divida.js` | **757** | **2** | Renegociação + reversão, juros/multa server-side |
| `pagamento_crediario.js` | **955** | **5** | Pagamento crediário, PIX, cartão, baixa em lote |

### Coleções
- `gestao_comercial_configuracoes/{lojaId}` — config crediário, e-mail, notificações
- `gestao_comercial_vendas/{id}` — histórico de vendas
- `gestao_comercial_recebimentos/{id}` — recebimentos
- `gestao_comercial_cobrancas/{id}` — cobranças PIX (com `processed` para idempotência)
- `gestao_comercial_email_templates/{lojaId}/templates/{slug}` — 16 templates
- `gestao_comercial_email_historico/{lojaId}/envios/{id}` — write false (só Admin)
- `gestao_comercial_integracoes_pagamento/{lojaId}/gateways/{id}` — credenciais criptografadas
- `sessoes_caixa/{id}` — sessões de caixa do PDV
- `users/{lojaId}/clientes_comercial`, `vendas_credito`, `parcelas_cliente`, `recebimentos_cliente` — subcoleções
- `cobrancas_pix_crediario` — cobranças PIX do crediário

---

## 17. ASSINATURAS (Módulo Novo — 7 telas)

Sistema de planos de assinatura (módulos vendidos avulsos para lojistas). Usa credenciais **globais da plataforma** (`gateways_pagamento/mercado_pago`), não por lojista.

### Telas Web (7 rotas: 44–50)
- `/assinaturas_dashboard` → `assinaturas_dashboard_screen.dart` (1.329 linhas, KPIs + gráficos)
- `/assinaturas_clientes` → `assinaturas_clientes_screen.dart` (**2.723 linhas**, ações: bloquear/desbloquear/cancelar)
- `/assinaturas_planos` → `assinaturas_planos_screen.dart` (**3.028 linhas**, CRUD planos + módulos)
- `/assinaturas_cobrancas` → `assinaturas_cobrancas_screen.dart` (2.276 linhas, gerar/avulsa/marcar paga/reembolsar)
- `/assinaturas_inadimplencia` → placeholder (não implementado)
- `/assinaturas_relatorios` → placeholder (não implementado)
- `/assinaturas_configuracoes` → `assinaturas_configuracoes_screen.dart` (**3.662 linhas**, 4 abas CRUD)

### Services (9)
- `assinaturas_dashboard_service.dart` (87 linhas, stream combinada)
- `assinaturas_clientes_service.dart` (137 linhas, + callable cancelar)
- `assinatura_gestao_comercial_service.dart` (**538 linhas**, regras de acesso GC)
- `assinatura_gestao_comercial_refresh.dart` (14 linhas, ChangeNotifier singleton)
- `assinatura_pagamento_service.dart` (206 linhas, PIX + cartão, 6 callables)
- `cobrancas_assinatura_service.dart` (69 linhas, ⚠️ erro sintaxe linha 63)
- `modulos_planos_service.dart` (146 linhas, CRUD + contagem)
- `modulos_config_service.dart` (74 linhas)
- `gateways_config_service.dart` (100 linhas), `bancos_config_service.dart` (76 linhas)
- `regras_gerais_config_service.dart` (57 linhas)

### Widgets (5)
- `assinatura_cancelar_plano_modal.dart` (550 linhas, motivo + observação)
- `assinatura_confirmacao_pagamento.dart` (225 linhas, QR Code + copia e cola)
- `assinatura_pagamento_modal.dart` (1.218 linhas, abas PIX + Cartão)
- `dipertin_confirmacao_premium_modal.dart` (462 linhas, efeitos visuais)
- `dipertin_feedback_premium_modal.dart` (356 linhas)

### Functions (3 módulos, 10 exports)
| Arquivo | Linhas | Exports |
|---------|--------|---------|
| `assinatura_pagamento.js` | **1.194** | **6** (assinarPlanoCriarPagamentoPix/ConsultarStatusPix/ProcessarCartao + RenovarPix/ConsultarRenovacao/RenovarCartao) |
| `assinatura_admin.js` | **352** | **1** (adminCancelarPlanoAssinatura — staff only, e-mail + audit log) |
| `assinatura_cobrancas.js` | **455** | **3** (adminGerarCobrancasAssinaturas/AdminCriarCobrancaAvulsa/AdminAtualizarCobranca) |

### Coleções
- `modulos_planos` — Planos (nome, valor, duracaoDias, modulos[], tolerancia, multa, juros)
- `assinaturas_modulos` — Módulos configuráveis (codigo, descricao, contratavel)
- `assinaturas_gateways` — Gateways (chavePublica, clientId, webhookUrl, status)
- `assinaturas_bancos` — Config bancária (tokenApi, contaBanco, agencia)
- `assinaturas_configuracoes/regras_gerais` — Documento único (tolerancia, suspensão, lembretes)
- `assinaturas_clientes` — Assinaturas contratadas (storeId, planId, status, modulosExtras, historico[])
- `assinaturas_cobrancas` — Cobranças geradas (fatura, modulo, vencimento, valor, status)
- `contadores` — IDs sequenciais para fatura

---

## 18. DEPENDÊNCIAS PRINCIPAIS

### Mobile (pubspec.yaml)
`firebase_core`, `cloud_firestore`, `firebase_auth`, `cloud_functions`, `firebase_messaging`, `firebase_storage`, `firebase_app_check`, `provider`, `shared_preferences`, `intl`, `connectivity_plus`, `geolocator`, `geocoding`, `google_sign_in`, `image_picker`, `file_picker`, `permission_handler`, `http`, `audioplayers`, `carousel_slider`, `photo_view`, `url_launcher`, `share_plus`, `flutter_multi_formatter`, `flutter_local_notifications`, `local_auth`, `local_auth_android`, `flutter_secure_storage`, `video_player`, `app_links`, `play_install_referrer`

### Web (pubspec.yaml)
`firebase_core`, `cloud_firestore`, `firebase_auth`, `cloud_functions`, `firebase_storage`, `google_fonts`, `intl`, `shimmer`, `fl_chart`, `file_picker`, `image_picker`, `url_launcher`, `http`, `google_sign_in`, `pdf`, `printing`, `table_calendar`, `qr_flutter`

---

## 19. ARQUIVOS CRÍTICOS (LOCALIZAÇÃO)

| Arquivo | Caminho |
|---|---|
| Pubspec mobile | `depertin_cliente/pubspec.yaml` |
| Pubspec web | `depertin_web/pubspec.yaml` |
| Main mobile | `depertin_cliente/lib/main.dart` (~1.2K linhas) |
| Main web | `depertin_web/lib/main.dart` |
| Index Functions | `depertin_cliente/functions/index.js` (~1.7K linhas) |
| Firestore Rules | `depertin_cliente/firestore.rules` (~1.5K linhas) |
| Firestore Indexes | `depertin_cliente/firestore.indexes.json` |
| Theme web | `depertin_web/lib/theme/painel_admin_theme.dart` |
| Sidebar web | `depertin_web/lib/widgets/sidebar_menu.dart` (~62KB) |
| Shell web | `depertin_web/lib/widgets/painel_shell_screen.dart` |
| Rotas web | `depertin_web/lib/navigation/painel_routes.dart` |
| Logística | `depertin_cliente/functions/logistica_entregador.js` (~77KB) |
| Repasse financeiro | `depertin_cliente/functions/repasse_financeiro.js` |
| Notification dispatcher | `depertin_cliente/functions/notification_dispatcher.js` |
| Mercado Pago | `depertin_cliente/functions/mercadopago_webhook.js` |
| AndroidManifest | `depertin_cliente/android/app/src/main/AndroidManifest.xml` |
| MainActivity Kotlin | `depertin_cliente/android/app/src/main/kotlin/com/dipertin/app/MainActivity.kt` |
| Config Google Sign-In mobile | `depertin_cliente/lib/config/google_sign_in_config.dart` |
| Config Google Sign-In web | `depertin_web/lib/config/google_sign_in_config.dart` |
| Deep link service | `depertin_cliente/lib/services/deep_link_service.dart` |
| Cart provider | `depertin_cliente/lib/providers/cart_provider.dart` |
| App Guard | `depertin_cliente/lib/screens/guards/app_guard.dart` |
| Código pedido (triplicado) | `functions/codigo_pedido.js` + `lib/utils/codigo_pedido.dart` + `depertin_web/lib/utils/codigo_pedido.dart` |
| Tipos entrega (triplicado) | `functions/tipos_entrega.js` + `lib/constants/tipos_entrega.dart` + `depertin_web/lib/constants/tipos_entrega.dart` |
| Cupom tipos (triplicado) | `functions/cupom_helpers.js` + `lib/constants/cupom_tipos.dart` + `depertin_web/lib/constants/cupom_tipos.dart` |
| .env.example | `depertin_cliente/functions/.env.example` |
| .env Comtele example | `depertin_cliente/functions/env.comtele.example` |
| .env GC Email example | `depertin_cliente/functions/env.gestao_comercial_email.example` |

---

## 20. SITE INSTITUCIONAL

- **Páginas:** index, rondonopolis-mt, toledo-pr, loja (demo), produto (demo), termos, privacidade, excluir-conta, 404
- **SEO:** JSON-LD (Organization, WebSite, WebPage, FAQPage, City, Store, Product, BreadcrumbList)
- **Deep link:** `/p/index.html` → `intent://` Android + fallback Play Store
- **App Links:** `.well-known/assetlinks.json` (2 SHA-256)
- **Segurança:** HSTS, CSP, COOP, nosniff, X-Frame-Options, Permissions-Policy
- **Deploy:** Firebase Hosting ou Apache/HostGator (.htaccess)

---

## 21. MUDANÇAS RECENTES NO WORKING TREE (não commitadas)

O working tree atual tem **33 arquivos modificados** (+12.537 linhas adicionadas, -3.946 removidas) desde o último commit. Destaques:

### Mudanças Principais
| Arquivo | +/- | Tipo |
|---------|-----|------|
| `depertin_web/lib/screens/dashboard_screen.dart` | +2.958 linhas | **Reescrita massiva** — gradiente premium, KPIs expandidos, glass button upsell |
| `site/css/styles.css` | +3.638 linhas | **Reestilização completa** do site institucional |
| `site/index.html` | +1.312 linhas | **Reestilização completa** |
| `depertin_web/lib/screens/login_admin_screen.dart` | +1.919 linhas | **Redesign completo** — split layout, tema DiPertin |
| `depertin_web/lib/screens/lojista_pdv_screen.dart` | +1.922 linhas | Expansão significativa do PDV |
| `depertin_web/lib/utils/pedido_recibo_pdf.dart` | +1.220 linhas | PDF de recibo totalmente refatorado |
| `depertin_web/lib/widgets/sidebar_menu.dart` | +794 linhas | Sidebar expandida com accordions de Assinaturas + Gestão Comercial |
| `depertin_cliente/firestore.rules` | +216 linhas | Novas regras: avaliacoes_produto, cupons, marketing_leads, users (proteção entregador) |
| `depertin_cliente/firestore.indexes.json` | +298 linhas | Novos índices: marketing_leads, avaliacoes_produto, cupons, users |
| `depertin_web/lib/navigation/painel_routes.dart` | +50 linhas | Rotas expandidas para 51 (assinaturas 44-50, gestão comercial 36-43) |
| `depertin_cliente/functions/index.js` | +91 linhas | Novos exports: assinaturas, GC, renegociação, crediário |
| `depertin_cliente/functions/estoque_pedido.js` | +139 linhas | Novas funções helpers de estoque para GC |

### Telas GC Revisadas
- `lojista_comercial_credito_screen.dart` (+300 linhas)
- `lojista_comercial_clientes_screen.dart` (+91 linhas)
- `comercial_cliente_recebimento_modal.dart` (+885 linhas)

### Serviços Revisados
- `comercial_clientes_service.dart` (+65 linhas)
- `comercial_credito_service.dart` (+58 linhas)
- `firebase_functions_config.dart` (+23 linhas, região southamerica-east1)
- `lojista_painel_context.dart` (+42 linhas)

### Site
- `site/index.html` (+1.312), `site/css/styles.css` (+3.638), `site/js/main.js` (+140), `site/.htaccess` e `firebase.json` com ajustes

---

## 22. CONVENÇÕES DE CÓDIGO

- **Idioma:** Português (nomes de arquivos, classes, variáveis, UI)
- **State management:** Provider (ChangeNotifier)
- **Safe area (mobile):** `DiPertinSafeMediaQuery`, `DiPertinScrollBody`, `DiPertinSafeBottomPanel`, `diPertinScrollPaddingTabShell`
- **Versionamento:** `dart run tool/bump_version.dart` (patch até .9 → minor; versionCode +1)
- **Build web:** `--base-href /sistema/` + `--pwa-strategy=none`
- **Deploy:** FTP com cache-bust ou Firebase Hosting
- **Funções:** mix v1 e v2; região us-central1; dotenv no index.js
- **Cores:** roxo `#6A1B9A` + laranja `#FF8F00`
- **Touch targets:** ≥44-48dp
- **Tipografia:** ≥12px legível
- **Debounce:** em buscas
- **Skeleton/loading:** obrigatório

---

## 23. PONTOS DE ATENÇÃO ADICIONAIS (descobertos em 02/07/2026)

1. **Erro de sintaxe em `cobrancas_assinatura_service.dart` linha 63:** `'canal': ?canal` (o `?` antes de `canal` não é válido em Dart). Corrigir antes do build.

2. **Índice `pedidos(cliente_id, cupom_codigo)` pode ser necessário** para `limite_por_usuario` em produção — não está no `firestore.indexes.json`.

3. **`assinaturas_inadimplencia` e `assinaturas_relatorios`** são placeholders (rotas registradas no shell mas sem implementação).

4. **Função `expandirBuscaEntregador`** é um stub (`return null`) — scheduled a cada 1 minuto em vão.

5. **Módulo Gestão Comercial** tem arquivos muito grandes: `gestao_comercial_functions.js` tem 4.188 linhas, `comercial_configuracoes_screen.dart` tem 3.727 linhas, `lojista_pdv_screen.dart` tem 5.037 linhas.

6. **A versão das assinaturas e GC** precisa da coleção `contadores` (para fatura) e das regras de segurança adequadas nas Rules.

---

## 24. COMO USAR ESTA MEMÓRIA

Sempre que receber uma tarefa sobre o DiPertin:

1. **Identificar o módulo afetado** (mobile, web, functions, site)
2. **Consultar as regras invioláveis** (seção 9) — especialmente a do FCM
3. **Respeitar o design system** (seção 4) — paleta de cores obrigatória
4. **Verificar contratos triplicados** (seção 19) — código pedido, tipos entrega, cupons
5. **Seguir convenções de código** (seção 21)
6. **Atualizar este arquivo** com novas informações relevantes
