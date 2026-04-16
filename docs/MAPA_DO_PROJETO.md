# Mapa do Projeto DiPertin

Este documento serve como “memória” do repositório: estrutura, pontos de entrada, fluxos principais e integrações.

## Visão geral (alto nível)

- **`depertin_cliente/`**: app Flutter mobile (Android/iOS) para **cliente**, **lojista** e **entregador**.
- **`depertin_web/`**: painel Flutter (principalmente **Web**) para operações/admin e também modo **painel lojista**.
- **`site/`**: site institucional estático (SEO) com integração via **Cloud Functions HTTP**.
- **Backend**: **Firebase** (Auth, Firestore, Storage, FCM, Functions). Projeto: **`depertin-f940f`**.

## `depertin_web/` (Painel)

### Entradas e navegação
- **Entrada**: `depertin_web/lib/main.dart`
  - Inicializa Firebase
  - No Web, processa `FirebaseAuth.instance.getRedirectResult()` para concluir login Google (redirect)
  - Rotas principais do `MaterialApp`: `/login` e `/painel`
  - Rotas internas do shell reconhecidas por `PainelRoutes.isShellRoute(route)`
- **Rotas do painel (shell)**: `depertin_web/lib/navigation/painel_routes.dart`
- **Controlador de navegação (state)**: `depertin_web/lib/navigation/painel_nav_controller.dart` (`ChangeNotifier`)
- **Scope de navegação**: `depertin_web/lib/navigation/painel_navigation_scope.dart` (`InheritedNotifier`)

### Shell + menu
- **Shell**: `depertin_web/lib/widgets/painel_shell_screen.dart`
  - Layout: sidebar + conteúdo
  - Usa **`IndexedStack` com lazy materialization** (telas são instanciadas na primeira visita e ficam cacheadas)
  - Aplica “saneamento” de rota para lojista colaborador (`sanearRotaPainelLojista`)
  - Overlay de **conta bloqueada** para lojista e sign-out → `/login`
- **Menu lateral**: `depertin_web/lib/widgets/sidebar_menu.dart`
  - Monta itens conforme **perfil** (`users/{uid}`) e nível de colaborador (`painel_colaborador_nivel`)
  - Badge de “saques” via `SaquesSolicitacoesMenuContagem`

### Login (fluxo)
- Tela: `depertin_web/lib/screens/login_admin_screen.dart`
  - **Email/senha**: `FirebaseAuth.signInWithEmailAndPassword()` → lê `users/{uid}` → decide rota
  - **Google (lojista)**:
    - Web tenta popup; fallback para redirect
    - Pós-redirect é finalizado com Callable Function `painelValidarPosLoginGoogle`

### Cloud Functions (Callable) no painel
- Config/região: `depertin_web/lib/services/firebase_functions_config.dart` (região `us-central1`)
- Callables identificadas no código:
  - `painelValidarPosLoginGoogle`
  - `cadastrarColaboradorPainelLojista`
  - `atualizarColaboradorPainelLojista`
  - `removerColaboradorPainelLojista`

### Scripts de build/deploy (painel)
- Build: `depertin_web/build_sistema.ps1`
  - `flutter build web --release --base-href /sistema/ --pwa-strategy=none --no-tree-shake-icons`
- Deploy FTP: `depertin_web/deploy_sistema_ftp.ps1`
  - Cache-bust em `index.html`/`flutter_bootstrap.js`/`main.dart.js`
  - Sobe para `/sistema` (com variações de docroot), usando credenciais de `site/.env.deploy`

## `depertin_cliente/` (App mobile)

### Entrada e providers globais
- **Entrada**: `depertin_cliente/lib/main.dart`
  - Inicializa Firebase + **Firebase App Check**
  - Configura FCM (foreground/background/initial message)
  - Cria canais de notificação Android (incluindo sons em `res/raw`)
  - Sobe o app com `MultiProvider`:
    - `CartProvider`
    - `ConnectivityService`
    - `LocationService`

### Guard global (conectividade/GPS/bloqueio)
- **Guard**: `depertin_cliente/lib/screens/guards/app_guard.dart`
  - Overlay de **sem internet** e **sem GPS**
  - Overlay de **conta bloqueada** (lojista/entregador) baseado em `users/{uid}` no Firestore

### FCM → rota
- Mapeamento de payload para rotas: `depertin_cliente/lib/services/fcm_rota.dart`
- Preferências de notificação:
  - `depertin_cliente/lib/services/notificacoes_prefs.dart`
  - `depertin_cliente/lib/services/chat_notificacoes_prefs.dart`
  - Eventos/tipos: `depertin_cliente/lib/services/fcm_notification_eventos.dart`

### Cloud Functions (Callable) no app
- Config/região: `depertin_cliente/lib/services/firebase_functions_config.dart` (região `us-central1`)
- Recuperação de senha (callables): `depertin_cliente/lib/services/recuperacao_senha_service.dart`

### Assets de áudio
- Flutter assets:
  - `depertin_cliente/assets/sond/ChamadaEntregador.mp3`
  - `depertin_cliente/assets/sond/pedido.mp3`
- Android raw (sons de canal do sistema):
  - `depertin_cliente/android/app/src/main/res/raw/chamada_entregador.mp3`
  - `depertin_cliente/android/app/src/main/res/raw/pedido.mp3`

### Plataforma
- Android Manifest: `depertin_cliente/android/app/src/main/AndroidManifest.xml`
  - Permissões relevantes: `POST_NOTIFICATIONS`, `USE_FULL_SCREEN_INTENT`, localização, etc.
  - Meta do FCM: `default_notification_channel_id`
- iOS Info.plist: `depertin_cliente/ios/Runner/Info.plist`
  - Permissões (câmera/fotos/localização) e `UIBackgroundModes` com `remote-notification`

> Observação: `depertin_cliente/lib/firebase_options.dart` indica ausência de configuração iOS (lança `UnsupportedError` em iOS). Se o alvo é rodar em iPhone, precisa gerar options iOS via FlutterFire.

## `site/` (site institucional estático)

### O que é
- HTML/CSS/JS com SEO (Open Graph/Twitter/JSON-LD), `robots.txt`, `sitemap.xml`, e verificação do Google (`googlead...html`).

### Deploy
Dois caminhos coexistentes:
- **Firebase Hosting** (config em `site/firebase.json` + `.firebaserc`)
- **FTP** via `site/deploy-ftp.ps1` (lê `site/.env.deploy`, exclui tooling e sobe para `public_html`)

### Integrações (HTTP Functions)
Config: `site/js/config.js`
- `enviarContatoSite` (POST): `https://us-central1-depertin-f940f.cloudfunctions.net/enviarContatoSite`
- `avaliacoesSitePublicas` (GET): `https://us-central1-depertin-f940f.cloudfunctions.net/avaliacoesSitePublicas`

Backend:
- `depertin_cliente/functions/contato_site.js` → exporta `enviarContatoSite`
- `depertin_cliente/functions/avaliacoes_site_publico.js` → exporta `avaliacoesSitePublicas`
- Reexport em `depertin_cliente/functions/index.js`

## Pontos críticos / riscos (alta prioridade)

- **Segredo OAuth no repositório (crítico)**: existe um arquivo `depertin_web/web/client_secret_*.json` contendo `client_secret`.
  - Ação recomendada: **rotacionar** o segredo no Google Cloud Console e remover do repo; no frontend deve ficar apenas `client_id`.
- **Regras do Firestore potencialmente permissivas (crítico)**:
  - `users/{userId}` com `allow read: if true` expõe dados de usuário para qualquer pessoa.
  - Coleção `gateways_pagamento` aparenta estar legível por qualquer autenticado; se armazena tokens (ex.: Mercado Pago), isso é vazamento grave.
- **`.env` em Functions**: `depertin_cliente/functions/.env` aparece modificado no git status — cuidado para nunca versionar segredos.

## Onde procurar “o que mexe em quê”
- **Coleções Firestore**: referência inicial em `depertin_cliente/README.md` (tabela) + usos nas telas do painel/app.
- **Rotas do painel**: `depertin_web/lib/navigation/painel_routes.dart`
- **Deep-links de notificação**: `depertin_cliente/lib/services/fcm_rota.dart`

