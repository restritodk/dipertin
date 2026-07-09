<#
.SYNOPSIS
    Deploy das Cloud Functions do Módulo Fiscal NF-e
.DESCRIPTION
    Publica as Cloud Functions do módulo fiscal de forma seletiva.
    Executar antes de ativar integrações fiscais em produção.

    Modos:
      .\deploy_fiscal_functions.ps1              # Deploy de todas as funções fiscais
      .\deploy_fiscal_functions.ps1 -DryRun       # Apenas simular
      .\deploy_fiscal_functions.ps1 -Functions    # Deploy do marketplace (todas)
      .\deploy_fiscal_functions.ps1 -All          # Deploy do fiscal + rules + indexes

.PARAMETER DryRun
    Simula o deploy sem publicar.

.PARAMETER All
    Deploy de todas as funções fiscais + regras + índices.

.PARAMETER Functions
    Deploy de todas as funções do marketplace (não apenas fiscal).
#>

param(
    [switch]$DryRun,
    [switch]$All,
    [switch]$Functions
)

$ErrorActionPreference = "Stop"
$PROJECT = "depertin-f940f"
$REGION = "us-central1"
$ROOT = "C:\Projeto\DiPertin\depertin_cliente"

Write-Host "╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║       DEPLOY — Cloud Functions Módulo Fiscal NF-e          ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host "Projeto: $PROJECT"
Write-Host "Região:  $REGION"
if ($DryRun) { Write-Host "Modo:    DRY-RUN (simulação)" -ForegroundColor Yellow }

# ─── 1. Verificar .env ─────────────────────────────────────────────────
Write-Host "`n📋 Verificando .env..." -ForegroundColor Green
$envFile = "$ROOT\.env"
if (-not (Test-Path $envFile)) {
    Write-Warning ".env não encontrado em $envFile"
    Write-Host "Crie o .env a partir de env.fiscal.example" -ForegroundColor Yellow
} else {
    $envContent = Get-Content $envFile -Raw
    if ($envContent -notmatch "FISCAL_MASTER_KEY" -or $envContent -notmatch "FISCAL_WEBHOOK_SECRET") {
        Write-Warning "Variáveis FISCAL_MASTER_KEY e/ou FISCAL_WEBHOOK_SECRET não encontradas no .env"
        Write-Host "Adicione as variáveis fiscais ao .env manualmente" -ForegroundColor Yellow
    } else {
        Write-Host "✅ .env contém as variáveis fiscais necessárias" -ForegroundColor Green
    }
}

# ─── 2. Verificar Node.js ─────────────────────────────────────────────
Write-Host "`n📋 Verificando Node.js..." -ForegroundColor Green
$nodeVersion = node --version
Write-Host "Node: $nodeVersion"

# ─── 3. npm install ──────────────────────────────────────────────────
Write-Host "`n📦 npm install..." -ForegroundColor Green
if (-not $DryRun) {
    Push-Location $ROOT
    try {
        npm install 2>&1 | Out-Null
        Write-Host "✅ npm install concluído" -ForegroundColor Green
    } finally {
        Pop-Location
    }
}

# ─── 4. Deploy ────────────────────────────────────────────────────────
if ($Functions) {
    # Deploy de todas as functions do marketplace
    Write-Host "`n🚀 Deploy de TODAS as Cloud Functions..." -ForegroundColor Cyan
    if (-not $DryRun) {
        Push-Location $ROOT
        try {
            npx firebase-tools@latest deploy --only functions --project $PROJECT
        } finally {
            Pop-Location
        }
    } else {
        Write-Host "   (dry-run) npx firebase-tools@latest deploy --only functions --project $PROJECT" -ForegroundColor Yellow
    }
} elseif ($All) {
    # Deploy das funções fiscais + regras + índices
    Write-Host "`n🚀 Deploy das funções fiscais + regras + índices..." -ForegroundColor Cyan
    if (-not $DryRun) {
        Push-Location $ROOT
        try {
            # Functions fiscais
            npx firebase-tools@latest deploy --only functions:fiscalWebhookNFe,functions:proxyWebmaniaEmitirNota,functions:proxyWebmaniaCancelarNota,functions:proxyWebmaniaCartaCorrecao,functions:proxyWebmaniaInutilizar,functions:proxyWebmaniaTestarConexao,functions:fiscalRotinaMensalReset --project $PROJECT

            # Regras Firestore
            npx firebase-tools@latest deploy --only firestore:rules --project $PROJECT

            # Índices
            npx firebase-tools@latest deploy --only firestore:indexes --project $PROJECT
        } finally {
            Pop-Location
        }
    } else {
        Write-Host "   (dry-run) Deploy fiscal functions + rules + indexes" -ForegroundColor Yellow
    }
} else {
    # Deploy seletivo das funções fiscais
    Write-Host "`n🚀 Deploy seletivo das funções fiscais..." -ForegroundColor Cyan
    if (-not $DryRun) {
        Push-Location $ROOT
        try {
            npx firebase-tools@latest deploy `
                --only functions:fiscalWebhookNFe `
                --only functions:proxyWebmaniaEmitirNota `
                --only functions:proxyWebmaniaCancelarNota `
                --only functions:proxyWebmaniaCartaCorrecao `
                --only functions:proxyWebmaniaInutilizar `
                --only functions:proxyWebmaniaTestarConexao `
                --only functions:fiscalRotinaMensalReset `
                --project $PROJECT
        } finally {
            Pop-Location
        }
    } else {
        Write-Host "   (dry-run) Deploy seletivo das 7 funções fiscais" -ForegroundColor Yellow
    }
}

# ─── 5. Verificar URLs ──────────────────────────────────────────────
Write-Host "`n🔗 URLs das funções fiscais (após deploy):" -ForegroundColor Green
Write-Host "   Webhook NF-e:       https://$REGION-$PROJECT.cloudfunctions.net/fiscalWebhookNFe"
Write-Host "   Proxy Webmania:     https://$REGION-$PROJECT.cloudfunctions.net/proxyWebmania* (onCall)"
Write-Host "   Rotina Mensal:      https://$REGION-$PROJECT.cloudfunctions.net/fiscalRotinaMensalReset (scheduled)"

Write-Host "`n✅ Deploy concluído!" -ForegroundColor Green
Write-Host ""
Write-Host "Próximos passos:" -ForegroundColor Cyan
Write-Host "  1. Configurar webhook nos provedores fiscais" -ForegroundColor White
Write-Host "     URL: https://$REGION-$PROJECT.cloudfunctions.net/fiscalWebhookNFe?provider={provedor}" -ForegroundColor White
Write-Host "  2. Executar migração de dados: node functions/scripts/migrar_dados_fiscais.js --dry-run" -ForegroundColor White
Write-Host "  3. Emitir NF-e de teste em homologação" -ForegroundColor White
