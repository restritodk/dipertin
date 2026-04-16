# Checklist de Homologacao - Alertas de Corrida (Android)

Objetivo: validar de forma consistente o comportamento de nova solicitacao de corrida no Android moderno, aceitando que full-screen e tentativa opcional e heads-up e o fallback principal.

## Escopo e premissas

- App: `depertin_cliente`
- Fluxo: recebimento de oferta de corrida via FCM data-only
- Canal esperado: `corrida_chamada`
- Regras atuais do Android:
  - Android 10+ restringe abertura de Activity em background
  - Android 14+ restringe ainda mais full-screen intent para casos de chamada/alarme
  - OEM pode bloquear mesmo com permissao concedida

## Criterio de sucesso (aceite)

- **Obrigatorio (confiavel):**
  - Notificacao de alta prioridade aparece sempre (heads-up ou notificacao destacada)
  - Acoes `Aceitar`, `Recusar`, `Abrir` funcionam
  - Toque na notificacao abre imediatamente a tela de corrida
- **Opcional (best effort):**
  - Full-screen abre automaticamente quando o sistema permitir
- **Nao-conformidade:**
  - Push chega, mas notificacao nao aparece
  - Acoes da notificacao nao executam
  - Toque nao abre tela

## Pre-check tecnico (antes dos testes)

- [ ] Notificacoes do app ativas no sistema
- [ ] Permissao `POST_NOTIFICATIONS` concedida (Android 13+)
- [ ] Permissao de tela cheia ativa (Android 14+, quando aplicavel)
- [ ] Sem restricao critica de bateria para o app
- [ ] Categoria de lockscreen ativa (notificacoes visiveis na tela bloqueada)
- [ ] Canal `Chamadas de corrida` com som/vibracao habilitados
- [ ] Conta entregador logada e apta a receber corrida

## Matriz de teste por cenario

Executar no minimo 3 envios por cenario para reduzir falso negativo intermitente.

### Cenario A - App em foreground

- [ ] Push recebido
- [ ] Notificacao exibida (ou UI equivalente no app)
- [ ] Som/vibracao
- [ ] Acoes funcionam

### Cenario B - App em segundo plano (recentes)

- [ ] Push recebido
- [ ] Heads-up/notificacao destacada aparece
- [ ] Tentativa full-screen registrada em log
- [ ] Toque abre tela de corrida
- [ ] Acoes `Aceitar/Recusar` funcionam

### Cenario C - App fechado (task removida)

- [ ] Push recebido
- [ ] Notificacao aparece
- [ ] Toque abre tela de corrida
- [ ] Acoes funcionam sem abrir app manualmente antes

### Cenario D - Tela bloqueada / AOD / tela apagada

- [ ] Push recebido com tela bloqueada
- [ ] Alerta visivel na lockscreen (heads-up/lista)
- [ ] Full-screen abre quando permitido pelo device/politica
- [ ] Se nao abrir full-screen, toque na notificacao abre tela imediatamente

## Logs obrigatorios para evidenciar resultado

Filtrar por tag: `IncomingDeliveryFlow`

Eventos minimos esperados:

- `Receiver C2DM: isIncoming=... orderId=...`
- `Push recebido ... dataKeys=... hasNotificationPayload=...`
- `Payload parseado: ... isIncoming=true`
- `canUseFullScreenIntent=true/false`
- `Notificacao de corrida publicada ... canal=corrida_chamada`
- `fullScreenIntent configurado ...` (quando permitido)
- `Sistema bloqueou fullScreenIntent ...` (quando negado)

Campos para registrar por teste:

- Fabricante/modelo
- Android SDK
- Estado do app (foreground/background/fechado/bloqueado)
- Resultado visual (full-screen, heads-up, somente notificacao)
- Resultado funcional (acoes/toque)
- Trecho do log

## Matriz por fabricante (minimo recomendado)

### Xiaomi / POCO / HyperOS / MIUI

- [ ] Auto start ativo
- [ ] Sem restricao de bateria para o app
- [ ] Notificacao em tela bloqueada ativa
- [ ] Notificacoes flutuantes ativas
- [ ] Resultado conforme criterio de sucesso

### Samsung (One UI)

- [ ] Notificacao pop-up ativa para o canal
- [ ] Sem economia agressiva de bateria para o app
- [ ] Lock screen details habilitado
- [ ] Resultado conforme criterio de sucesso

### Oppo / Realme / OnePlus

- [ ] Auto-launch / startup manager liberado
- [ ] Execucao em segundo plano permitida
- [ ] Lock screen notification ativa
- [ ] Resultado conforme criterio de sucesso

### Vivo

- [ ] Auto start liberado
- [ ] Background activity management sem restricao critica
- [ ] Lock screen notification ativa
- [ ] Resultado conforme criterio de sucesso

## Regressao backend/FCM (obrigatorio)

- [ ] Payload enviado como data-only (sem dependencia de `notification`)
- [ ] `android.priority = high`
- [ ] Campos minimos enviados:
  - `type` ou `tipoNotificacao`
  - `evento=dispatch_request`
  - `orderId`/`order_id`
- [ ] `onMessageReceived` executado nos cenarios esperados

## Relatorio final de homologacao (template)

Preencher ao fim:

- Device:
- Android:
- OEM:
- Build do app:
- Cenarios aprovados:
- Cenarios com degradacao aceitavel (heads-up em vez de full-screen):
- Falhas criticas:
- Evidencias (log + video/screenshot):
- Acao corretiva sugerida:

## Decisao de produto recomendada

- Tratar full-screen como **best effort**.
- Tratar heads-up + acoes da notificacao + toque para abrir como **fluxo principal confiavel**.
- Manter orientacao no app para configuracoes OEM e bateria.
