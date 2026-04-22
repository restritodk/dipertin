# Alertas de Segurança (DiPertin)

Este documento lista **riscos concretos** observados no repositório e as ações recomendadas.

## 1) Segredo OAuth versionado no frontend (crítico)

- **Arquivo encontrado**: `depertin_web/web/client_secret_939151024179-fnessl0debfhjh3gvq8a7n9paepdgc6l.apps.googleusercontent.com.json`
- **Problema**: contém `client_secret` (segredo), que **não deve** estar em frontend nem em controle de versão.
- **Risco**: comprometimento do OAuth client; uso indevido por terceiros.
- **Ação recomendada**:
  - Rotacionar/revogar o segredo no Google Cloud Console.
  - Remover o arquivo do repositório e garantir que segredos não sejam reintroduzidos.
  - No web, manter somente `client_id` (e configurar origens/redirect URIs corretamente).

## 2) Firestore Rules de `users` (resolvido — Fase 3G, abr/2026)

- **Regra atual**:
  ```
  allow read: if signedIn() && (
    request.auth.uid == userId
    || isStaff()
    || colaboradorLeDono(userId)
    || donoLeColaborador()
  );
  ```
- **Status**: fechada. Anônimo não lê nada; autenticado só vê próprio doc, docs de staff, ou relacionamentos dono⇄colaborador.
- **Fases executadas**:
  - **3G.1 (abr/2026)**: criada coleção pública `lojas_public` alimentada por trigger (`sincronizarLojaPublicOnWrite`) com allowlist de campos de fachada. Vitrine, busca, perfil da loja e carrinho migrados.
  - **3G.2 (abr/2026)**: migradas todas as queries do app mobile/painel que liam lojistas via `users.where(role=lojista)` para `lojas_public`.
  - **3G.3 (abr/2026)**:
    - Denormalizados `cliente_nome`, `cliente_foto_perfil`, `loja_nome`, `loja_foto` em `pedidos` (criação no `cart_screen.dart` + backfill em pedidos ativos).
    - Trigger `sincronizarIdentidadePedidosOnUpdate` mantém snapshot atualizado em pedidos em aberto.
    - Callable `lojistaConfirmarRetiradaNaLojaComEstorno` substitui `users.saldo` update direto do app lojista.
    - Rule final fechada (ver acima).
- **Backlog defesa em profundidade**:
  - Avaliar mover `saldo` e `fcm_token` de `users` pra subcoleções (ou docs privados) com rules ainda mais restritas.
  - Testar se `entregador_status`, `entregador_operacao_status` e `block_*` deveriam viver em `users/{uid}/operacional/state` com rule própria.

## 3) Tokens de gateway em `gateways_pagamento` (resolvido — abr/2026)

- **Regra atual**: `match /gateways_pagamento/{id} { allow read: if isStaff(); allow write: if isStaff(); }`
- **Status**: leitura e escrita restritas a staff (master/master_city). Cliente, lojista e entregador não conseguem ler.
- **Fase 3H (abr/2026)**: adicionado hardening de UI no painel web — access_token agora exibido como campo de senha (obscureText + toggle visibilidade) e não é zerado se o master salvar com campo em branco.
- **Defesa em profundidade (backlog futuro)**:
  - Migrar tokens pra **Google Secret Manager**, lido exclusivamente pelas Functions via Admin SDK.
  - Atualmente Functions lê `gateways_pagamento/mercado_pago` via Admin SDK (bypass rules). Ao migrar, rules podem passar a `allow read: if false`.

## 4) Arquivos `.env` / credenciais (atenção)

- O `git status` inicial mostra `depertin_cliente/functions/.env` modificado.
- **Ação recomendada**:
  - Garantir que `.env` esteja no `.gitignore` (e que nunca seja commitado).
  - Usar exemplos (`env.*.example`) como já existe no projeto.

