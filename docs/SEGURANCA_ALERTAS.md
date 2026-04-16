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

## 2) Firestore Rules permissivas para `users` (crítico)

- **Regra atual** (trecho): `match /users/{userId} { allow read: if true; }` em `depertin_cliente/firestore.rules`
- **Problema**: permite leitura **pública** de todos os documentos `users/*`.
- **Risco**: vazamento de dados pessoais (telefone, e-mail, endereços, chaves PIX, etc.), dependendo do que está armazenado em `users`.
- **Ação recomendada**:
  - Trocar para leitura restrita (ex.: apenas dono, staff e/ou campos públicos em coleção separada).
  - Se o app/painel precisa de “catálogo público” de lojas, criar coleção/visão pública (ex.: `lojas_publicas`) com dados mínimos.

## 3) Tokens de gateway em `gateways_pagamento` com read amplo (crítico)

- **Regra atual**: `match /gateways_pagamento/{id} { allow read: if signedIn(); allow write: if isStaff(); }`
- **Problema**: qualquer usuário autenticado consegue ler documentos do gateway.
- **Risco**: se esses docs incluem tokens (ex.: Mercado Pago), isso é vazamento grave.
- **Ação recomendada**:
  - Restringir `read` a `isStaff()` (ou a um service account via Functions).
  - Preferir armazenar tokens em **Secret Manager** e acessá-los apenas por Functions/Admin SDK.

## 4) Arquivos `.env` / credenciais (atenção)

- O `git status` inicial mostra `depertin_cliente/functions/.env` modificado.
- **Ação recomendada**:
  - Garantir que `.env` esteja no `.gitignore` (e que nunca seja commitado).
  - Usar exemplos (`env.*.example`) como já existe no projeto.

