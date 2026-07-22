# DiPertin — DEV: limpeza total do marketplace

**Não vai para produção.** Ferramenta local na raiz do repositório.

## O que faz

### Lista usuários
- Clientes, lojistas, entregadores e outros (`users` + Firebase Auth).

### Limpeza TOTAL (botão principal)
Apaga **todo o marketplace** e deixa só **`master@teste.com`** (senha `master`, role `master`):

| Apagado | Inclui |
|---------|--------|
| Transações | `pedidos` (+ mensagens), `encomendas` (+ mensagens) |
| Catálogo | `produtos`, `lojas_public` |
| Promoções | `cupons` |
| Avaliações | `avaliacoes`, `avaliacoes_produto` |
| Financeiro | `saques_solicitacoes`, `estornos`, `receitas_app`, `despesas_app`, `fiscal/**` (entregador) |
| Suporte | `support_tickets`, `support_ratings`, `suporte` |
| Marketing | `marketing_leads_lojistas/entregadores` (+ histórico) |
| Notificações | `notificacoes_campanhas`, `notificacoes_usuario/**` |
| Cadastro | `users_cpf_index`, tickets/rate-limit Comtele/SMS |
| Auditoria | `audit_logs`, `audit_exclusoes_clientes` |
| **Gestão Comercial** | configs, vendas, recebimentos, cobranças, sessões caixa, e-mail templates/histórico, integrações pagamento (+ gateways) |
| **Assinaturas** | `modulos_planos` (planos SaaS), `assinaturas_clientes`, `assinaturas_cobrancas`, `contadores` |
| **Fiscal NF-e** | settings loja, documentos, certificados, operações, `lojista_integracao`, séries, logs/webhooks, `notas_fiscais` |
| Usuários | **Todos** Auth + Firestore exceto master (inclui sub `clientes_comercial`, `vendas_credito`, `parcelas_*`, `favoritos`, `wallet_reservas`, …) |

### Preservado (config infra)
`gateways_pagamento`, `planos_taxas`, `tabela_fretes`, `configuracoes`, `categorias`, `cidades`, `conteudo_legal`, catálogo Assinaturas (`assinaturas_modulos`, gateways/bancos/config, `billing_settings`), `fiscal_integrations`, `planos_emissao_nfe`.

### Também apagado (v2+)
`banners`, `comunicados`, `servicos_destaque`, `telefones_premium`, `eventos`, `vagas`, `achados`, `centro_ops_agenda` — zera vitrine CRM.

## Pré-requisitos

1. Node.js 20+
2. Service account JSON do Firebase
3. `npm install` em `depertin_cliente/functions` (firebase-admin)

## Como usar (Windows) — IMPORTANTE

**Não abra o HTML direto.** O erro "Failed to fetch" significa que o servidor Node não está rodando.

### Opção 1 — duplo-clique (recomendado)

1. Coloque `serviceAccount.json` na raiz (`C:\Projeto\DiPertin\`)
2. Duplo-clique em **`dev-iniciar-limpeza.ps1`**
3. Aguarde abrir `http://127.0.0.1:8765`
4. **Não feche** a janela PowerShell

### Opção 2 — manual

```powershell
cd C:\Projeto\DiPertin
$env:GOOGLE_APPLICATION_CREDENTIALS="C:\caminho\para\serviceAccount.json"
$env:GOOGLE_CLOUD_QUOTA_PROJECT="depertin-f940f"
node dev-listar-usuarios-limpeza-server.js
```

### Na tela

1. **Ver o que será apagado** — contagem por coleção  
2. **Simular (dry-run)** — progresso etapa a etapa, sem apagar  
3. **APAGAR MARKETPLACE INTEIRO** — digite `SIM APAGAR MARKETPLACE INTEIRO`

Durante a exclusão você vê barra de progresso, cada etapa (pedidos → produtos → cupons → users → auth…) e log linha a linha.

## Arquivos

| Arquivo | Função |
|---------|--------|
| `dev-iniciar-limpeza.ps1` | Atalho — inicia servidor e abre navegador |
| `dev-listar-usuarios-limpeza.html` | Interface web |
| `dev-limpeza-total-firestore.js` | Lógica de wipe completo |
| `dev-listar-usuarios-limpeza.README.md` | Este guia |

**Não incluir em deploy FTP, Firebase Hosting ou build do painel.**
