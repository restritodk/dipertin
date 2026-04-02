#Requires -Version 5.1
<#
.SYNOPSIS
  Deploy de regras Firestore, índices, Storage e (opcional) Cloud Functions — projeto DiPertin.

.DESCRIPTION
  NÃO coloque email, palavra-passe ou tokens neste ficheiro.
  Autenticação: execute uma vez `firebase login` no browser (OAuth Google).

  Pré-requisito: Node.js + Firebase CLI
    npm install -g firebase-tools

.EXAMPLE
  .\firebase_deploy.ps1              # regras + índices + storage + functions
  .\firebase_deploy.ps1 rules        # só Firestore rules + Storage rules
  .\firebase_deploy.ps1 indexes      # só índices Firestore
  .\firebase_deploy.ps1 functions    # só Cloud Functions
#>

$ErrorActionPreference = "Stop"
$Root = $PSScriptRoot
Set-Location $Root

Write-Host ""
Write-Host "=== DiPertin — Firebase deploy ===" -ForegroundColor Cyan
Write-Host "Pasta: $Root"
Write-Host ""

try {
    $null = Get-Command firebase -ErrorAction Stop
} catch {
    Write-Host "Instale o Firebase CLI: npm install -g firebase-tools" -ForegroundColor Red
    exit 1
}

$opcao = if ($args.Count -ge 1) { $args[0].ToLower() } else { "all" }

switch ($opcao) {
    "rules" {
        Write-Host "A publicar: firestore:rules, storage ..." -ForegroundColor Yellow
        firebase deploy --only firestore:rules,storage
    }
    "indexes" {
        Write-Host "A publicar: firestore:indexes (pode demorar a criar índices na consola) ..." -ForegroundColor Yellow
        firebase deploy --only firestore:indexes
    }
    "functions" {
        Write-Host "A publicar: functions ..." -ForegroundColor Yellow
        firebase deploy --only functions
    }
    "firestore" {
        Write-Host "A publicar: firestore (rules + indexes) ..." -ForegroundColor Yellow
        firebase deploy --only firestore
    }
    default {
        Write-Host "A publicar: firestore (rules+indexes), storage, functions ..." -ForegroundColor Yellow
        firebase deploy --only firestore,storage,functions
    }
}

if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "Deploy falhou. Confirma: firebase login  e  projeto em .firebaserc" -ForegroundColor Red
    exit $LASTEXITCODE
}

Write-Host ""
Write-Host "Concluído." -ForegroundColor Green
