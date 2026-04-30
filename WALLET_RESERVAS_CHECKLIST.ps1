#!/usr/bin/env pwsh
# Checklist de Validação - Sistema de Reserva de Saldo
# Uso: .\WALLET_RESERVAS_CHECKLIST.ps1

param(
    [switch]$Verbose = $false
)

$ErrorActionPreference = "Continue"
$script:passedChecks = 0
$script:failedChecks = 0
$script:warningChecks = 0

function Write-Check {
    param([string]$Message, [ValidateSet("PASS", "FAIL", "WARN", "INFO")]$Status = "INFO")
    
    $symbol = @{
        "PASS" = "✓"
        "FAIL" = "❌"
        "WARN" = "⚠"
        "INFO" = "ℹ"
    }[$Status]
    
    $color = @{
        "PASS" = "Green"
        "FAIL" = "Red"
        "WARN" = "Yellow"
        "INFO" = "Cyan"
    }[$Status]
    
    Write-Host "$symbol $Message" -ForegroundColor $color
    
    switch ($Status) {
        "PASS" { $script:passedChecks++ }
        "FAIL" { $script:failedChecks++ }
        "WARN" { $script:warningChecks++ }
    }
}

Write-Host @"
╔════════════════════════════════════════════════════════════════════════════╗
║          CHECKLIST DE VALIDAÇÃO - SISTEMA DE RESERVA DE SALDO              ║
║                                                                            ║
║  Versão: 1.0                                                              ║
║  Data: $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')                                       ║
╚════════════════════════════════════════════════════════════════════════════╝
"@

# ============================================================================
# 1. VALIDAÇÃO DE ARQUIVOS
# ============================================================================

Write-Host "`n[1] Validando Arquivos..." -ForegroundColor Cyan

$files = @(
    "depertin_cliente\functions\wallet_reservas.js",
    "depertin_cliente\lib\services\wallet_reserva_service.dart",
    "depertin_cliente\lib\services\WALLET_RESERVAS_GUIA.dart",
    "depertin_cliente\lib\screens\cliente\cart_screen.dart",
    "depertin_cliente\lib\screens\cliente\checkout_pagamento_screen.dart",
    "WALLET_RESERVAS_README.md",
    "deploy_wallet_reservas.ps1"
)

foreach ($file in $files) {
    $fullPath = Join-Path $PSScriptRoot $file
    if (Test-Path $fullPath) {
        Write-Check "$file" -Status "PASS"
    } else {
        Write-Check "$file (NÃO ENCONTRADO)" -Status "FAIL"
    }
}

# ============================================================================
# 2. VALIDAÇÃO DE CÓDIGO DART
# ============================================================================

Write-Host "`n[2] Validando Código Dart..." -ForegroundColor Cyan

$cartScreenPath = Join-Path $PSScriptRoot "depertin_cliente\lib\screens\cliente\cart_screen.dart"
$cartContent = Get-Content $cartScreenPath -Raw -ErrorAction SilentlyContinue

if ($cartContent -match "import.*wallet_reserva_service") {
    Write-Check "Import de wallet_reserva_service em cart_screen.dart" -Status "PASS"
} else {
    Write-Check "Import de wallet_reserva_service em cart_screen.dart (NÃO ENCONTRADO)" -Status "FAIL"
}

if ($cartContent -match "WalletReservaService\.reservarSaldo") {
    Write-Check "Chamada de WalletReservaService.reservarSaldo em cart_screen.dart" -Status "PASS"
} else {
    Write-Check "Chamada de WalletReservaService.reservarSaldo em cart_screen.dart (NÃO ENCONTRADO)" -Status "FAIL"
}

$checkoutPath = Join-Path $PSScriptRoot "depertin_cliente\lib\screens\cliente\checkout_pagamento_screen.dart"
$checkoutContent = Get-Content $checkoutPath -Raw -ErrorAction SilentlyContinue

if ($checkoutContent -match "import.*wallet_reserva_service") {
    Write-Check "Import de wallet_reserva_service em checkout_pagamento_screen.dart" -Status "PASS"
} else {
    Write-Check "Import de wallet_reserva_service em checkout_pagamento_screen.dart (NÃO ENCONTRADO)" -Status "FAIL"
}

if ($checkoutContent -match "_confirmarReservaDeSaldo") {
    Write-Check "Método _confirmarReservaDeSaldo em checkout_pagamento_screen.dart" -Status "PASS"
} else {
    Write-Check "Método _confirmarReservaDeSaldo em checkout_pagamento_screen.dart (NÃO ENCONTRADO)" -Status "FAIL"
}

if ($checkoutContent -match "_cancelarReservaDeSaldo") {
    Write-Check "Método _cancelarReservaDeSaldo em checkout_pagamento_screen.dart" -Status "PASS"
} else {
    Write-Check "Método _cancelarReservaDeSaldo em checkout_pagamento_screen.dart (NÃO ENCONTRADO)" -Status "FAIL"
}

# ============================================================================
# 3. VALIDAÇÃO DE CLOUD FUNCTIONS
# ============================================================================

Write-Host "`n[3] Validando Cloud Functions..." -ForegroundColor Cyan

$walletReservasPath = Join-Path $PSScriptRoot "depertin_cliente\functions\wallet_reservas.js"
$walletContent = Get-Content $walletReservasPath -Raw -ErrorAction SilentlyContinue

@("walletReservarSaldo", "walletConfirmarDebito", "walletCancelarReserva", "walletLimparReservasExpiradas") | ForEach-Object {
    if ($walletContent -match "exports\.$_") {
        Write-Check "Função exports.$_ em wallet_reservas.js" -Status "PASS"
    } else {
        Write-Check "Função exports.$_ em wallet_reservas.js (NÃO ENCONTRADA)" -Status "FAIL"
    }
}

if ($walletContent -match "runTransaction") {
    Write-Check "Transações ACID (runTransaction) em wallet_reservas.js" -Status "PASS"
} else {
    Write-Check "Transações ACID (runTransaction) em wallet_reservas.js (NÃO ENCONTRADAS)" -Status "WARN"
}

if ($walletContent -match "onSchedule") {
    Write-Check "Scheduler (onSchedule) em wallet_reservas.js" -Status "PASS"
} else {
    Write-Check "Scheduler (onSchedule) em wallet_reservas.js (NÃO ENCONTRADO)" -Status "FAIL"
}

# ============================================================================
# 4. VALIDAÇÃO DE DOCUMENTAÇÃO
# ============================================================================

Write-Host "`n[4] Validando Documentação..." -ForegroundColor Cyan

$readmePath = Join-Path $PSScriptRoot "WALLET_RESERVAS_README.md"
$readmeContent = Get-Content $readmePath -Raw -ErrorAction SilentlyContinue

@("Problema Crítico", "Solução Implementada", "3 Etapas", "Cenário") | ForEach-Object {
    if ($readmeContent -match $_) {
        Write-Check "Seção '$_' em WALLET_RESERVAS_README.md" -Status "PASS"
    } else {
        Write-Check "Seção '$_' em WALLET_RESERVAS_README.md (NÃO ENCONTRADA)" -Status "FAIL"
    }
}

$guiaPath = Join-Path $PSScriptRoot "depertin_cliente\lib\services\WALLET_RESERVAS_GUIA.dart"
$guiaContent = Get-Content $guiaPath -Raw -ErrorAction SilentlyContinue

@("TEST 1", "TEST 2", "TEST 3", "TEST 4") | ForEach-Object {
    if ($guiaContent -match $_) {
        Write-Check "Teste '$_' em WALLET_RESERVAS_GUIA.dart" -Status "PASS"
    } else {
        Write-Check "Teste '$_' em WALLET_RESERVAS_GUIA.dart (NÃO ENCONTRADO)" -Status "FAIL"
    }
}

# ============================================================================
# 5. VALIDAÇÃO DE SEGURANÇA
# ============================================================================

Write-Host "`n[5] Validando Segurança..." -ForegroundColor Cyan

if ($walletContent -match "permission-denied|request\.auth\.uid") {
    Write-Check "Validação de autenticação em Cloud Functions" -Status "PASS"
} else {
    Write-Check "Validação de autenticação em Cloud Functions (NÃO ENCONTRADA)" -Status "WARN"
}

if ($walletContent -match "FieldValue\.increment|transaction\.update") {
    Write-Check "Operações atômicas (FieldValue.increment/transaction)" -Status "PASS"
} else {
    Write-Check "Operações atômicas (FieldValue.increment/transaction) (NÃO ENCONTRADAS)" -Status "FAIL"
}

if ($cartContent -match "saldo_reservado|PENDENTE|CONFIRMADO|CANCELADO") {
    Write-Check "Estados de reserva (PENDENTE/CONFIRMADO/CANCELADO)" -Status "PASS"
} else {
    Write-Check "Estados de reserva (PENDENTE/CONFIRMADO/CANCELADO) (NÃO ENCONTRADOS)" -Status "WARN"
}

# ============================================================================
# 6. VALIDAÇÃO DE DEPLOY
# ============================================================================

Write-Host "`n[6] Validando Script de Deploy..." -ForegroundColor Cyan

$deployPath = Join-Path $PSScriptRoot "deploy_wallet_reservas.ps1"
$deployContent = Get-Content $deployPath -Raw -ErrorAction SilentlyContinue

@("firebase deploy", "walletReservarSaldo", "walletConfirmarDebito", "walletCancelarReserva") | ForEach-Object {
    if ($deployContent -match [regex]::Escape($_)) {
        Write-Check "Referência a '$_' em deploy_wallet_reservas.ps1" -Status "PASS"
    } else {
        Write-Check "Referência a '$_' em deploy_wallet_reservas.ps1 (NÃO ENCONTRADA)" -Status "FAIL"
    }
}

# ============================================================================
# 7. RESUMO FINAL
# ============================================================================

Write-Host @"

╔════════════════════════════════════════════════════════════════════════════╗
║                           RESUMO DOS TESTES                               ║
╚════════════════════════════════════════════════════════════════════════════╝

  ✓ Passou:   $script:passedChecks
  ❌ Falhou:  $script:failedChecks
  ⚠ Alertas:  $script:warningChecks

"@

if ($script:failedChecks -eq 0) {
    Write-Host "✅ VALIDAÇÃO COMPLETA - Pronto para Deploy!" -ForegroundColor Green
    Write-Host @"

Próximos passos:
1. Execute: .\deploy_wallet_reservas.ps1
2. Aguarde o deploy das Cloud Functions
3. Reconstrua o APK:
   cd depertin_cliente
   flutter clean
   flutter pub get
   flutter build apk --release
4. Execute os 4 testes em WALLET_RESERVAS_GUIA.dart
5. Monitore wallet_transaction_logs no Firestore

"@
} else {
    Write-Host "⚠ VALIDAÇÃO COM PROBLEMAS - Corrija os itens acima antes de fazer deploy" -ForegroundColor Yellow
}

Write-Host "`n[Tempo total] $(Get-Date -Format 'HH:mm:ss')" -ForegroundColor Cyan
