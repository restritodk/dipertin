# Gestão Comercial — Checklist antes de subir para produção

> Use este documento **sempre** antes de publicar o painel web (`depertin_web`) ou alterar o backend do módulo Gestão Comercial em produção.
>
> Projeto Firebase: `depertin-f940f` | Região GC: `southamerica-east1`

---

## 1. E-mail transacional (não esquecer)

### 1.1 Segredo de criptografia (obrigatório)

Senhas SMTP e API Keys das lojas são criptografadas com **AES-256-GCM** no backend (`gestao_comercial_email.js`).

| Item | Ação |
|------|------|
| Variável | `GC_EMAIL_CONFIG_SECRET` em `depertin_cliente/functions/.env` |
| Exemplo | Ver `depertin_cliente/functions/env.gestao_comercial_email.example` |
| Gerar chave | `node -e "console.log(require('crypto').randomBytes(32).toString('hex'))"` |
| Nunca | Commitar `.env`, reutilizar chave de dev, deixar fallback em produção |

**Se a chave mudar depois de lojas já configuradas:** senhas/API keys salvas deixam de descriptografar — lojistas precisarão **salvar de novo** a senha SMTP ou API Key no modal.

### 1.2 Redeploy das functions de e-mail (após alterar `.env`)

```powershell
cd C:\Projeto\DiPertin\depertin_cliente
npx firebase-tools@latest deploy --only functions:gestaoComercialEmailSalvarConfig,functions:gestaoComercialEmailTestarSmtp,functions:gestaoComercialEmailTestarApi,functions:gestaoComercialEmailEnviarTeste,functions:gestaoComercialEmailSalvarTemplate,functions:gestaoComercialEmailEnviarTemplateTeste,functions:gestaoComercialEmailListarHistorico,functions:gestaoComercialEmailInicializarTemplates --project depertin-f940f
```

### 1.3 Firestore (já deployado jun/2026 — conferir se houve mudança local)

```powershell
npx firebase-tools@latest deploy --only firestore:rules --project depertin-f940f
```

Coleções novas: `gestao_comercial_email_templates/{lojaId}/templates/*`, `gestao_comercial_email_historico/{lojaId}/envios/*`.

### 1.4 Smoke test pós-deploy (1 loja piloto)

- [ ] Abrir **Configurações Comerciais → Envio de Cobrança → E-mail → Configurar**
- [ ] Aba **Configuração**: SMTP (Gmail/Titan/Hostinger) ou API (SendGrid/Resend) → **Testar conexão**
- [ ] Enviar **e-mail de teste** para caixa real
- [ ] Aba **Templates**: salvar template **Cobrança** → **Enviar teste**
- [ ] Aba **Histórico**: confirmar registro com status `enviado` ou mensagem de erro clara

---

## 2. Painel web (Flutter)

```powershell
cd C:\Projeto\DiPertin\depertin_web
.\build_sistema.ps1
# ou deploy FTP / Firebase Hosting conforme rotina DiPertin
```

- [ ] Build com `--base-href /sistema/` (padrão do projeto)
- [ ] Hot restart / cache-bust no FTP se aplicável
- [ ] Testar modal **E-mail Transacional** em Chrome produção

Arquivos principais do módulo e-mail:

- `lib/widgets/comercial/comercial_email_transacional_modal.dart`
- `lib/services/comercial_email_transacional_service.dart`
- `lib/models/comercial_email_transacional.dart`
- `lib/screens/comercial_configuracoes_screen.dart`

---

## 3. Outras integrações Gestão Comercial (revisão rápida)

| Integração | Onde configurar | Backend |
|------------|-----------------|---------|
| Mercado Pago / gateways PDV | Configurações → Pagamentos | `gestaoComercialTestarConexaoGateway`, webhook `planos.dipertin.com.br` |
| SMS Comtele | Configurações → SMS | `COMTELE_AUTH_KEY` no `.env` |
| PIX PDV | PDV | `gestaoComercialCriarPagamentoPix` |

---

## 4. Ordem sugerida no dia do go-live

1. Configurar `GC_EMAIL_CONFIG_SECRET` no `.env` das Functions  
2. Redeploy functions de e-mail (+ demais GC se houver diff)  
3. Deploy Firestore rules (se alteradas)  
4. Smoke test e-mail em loja piloto  
5. Build e deploy do painel web  
6. Comunicar lojistas: configurar **E-mail Transacional** antes de automações de cobrança  

---

> **Referência técnica:** `docs/GESTAO_COMERCIAL.md` — seções 9 (config) e 12 (e-mail transacional).
