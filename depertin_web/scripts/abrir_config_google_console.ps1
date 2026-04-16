#Requires -Version 5.1
<#
.SYNOPSIS
  DiPertin — abre no navegador as páginas do Firebase / Google Cloud para conferir
  login Google (domínios autorizados, OAuth, chaves de API).

.DESCRIPTION
  IMPORTANTE — O que isto NÃO faz:
  - Não concede acesso remoto a terceiros (incluindo assistentes de IA) à tua conta Google.
  - Não envia credenciais para lugar nenhum; corre só no teu PC.

  O que isto FAZ:
  - Pede confirmação antes de abrir URLs.
  - Abre o browser nas secções certas do teu projeto (IDs abaixo).
  - Opcionalmente, se tiveres o Google Cloud SDK (gcloud) instalado e sessão ativa,
    mostra o projeto ativo e se a Identity Toolkit API está ativa (só leitura local).

  Projeto Firebase / GCP: depertin-f940f
#>

$ErrorActionPreference = "Stop"

$ProjectId = "depertin-f940f"

function Write-Banner {
    Write-Host ""
    Write-Host "================================================================" -ForegroundColor Cyan
    Write-Host "  DiPertin — Configuração Google / Firebase (login com Google)" -ForegroundColor Cyan
    Write-Host "================================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Nenhum script pode dar acesso à tua consola Google a outra pessoa" -ForegroundColor Yellow
    Write-Host "  ou a um assistente de IA. Só TU vês a consola no teu browser." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  Este script apenas:" -ForegroundColor Gray
    Write-Host "    • Pede permissão para ABRIR páginas no teu navegador" -ForegroundColor Gray
    Write-Host "    • (Opcional) Corre comandos gcloud locais, se instalados" -ForegroundColor Gray
    Write-Host ""
}

function Test-GcloudAvailable {
    $g = Get-Command gcloud -ErrorAction SilentlyContinue
    return $null -ne $g
}

function Show-GcloudHints {
    if (-not (Test-GcloudAvailable)) {
        Write-Host "  [gcloud] Não encontrado. Opcional: instala Google Cloud SDK e faz" -ForegroundColor DarkGray
        Write-Host "           https://cloud.google.com/sdk/docs/install" -ForegroundColor DarkGray
        return
    }
    Write-Host "  [gcloud] Encontrado — verificação local (só leitura):" -ForegroundColor DarkCyan
    try {
        $active = & gcloud config get-value project 2>$null
        Write-Host "           Projeto ativo: $active" -ForegroundColor Gray
        $enabled = & gcloud services list --enabled --filter="config.name:identitytoolkit.googleapis.com" --format="value(config.name)" --project=$ProjectId 2>$null
        if ($enabled) {
            Write-Host "           Identity Toolkit API: ativa" -ForegroundColor Green
        } else {
            Write-Host "           Identity Toolkit API: (não listada ou sem permissão para ler)" -ForegroundColor DarkYellow
        }
    } catch {
        Write-Host "           Não foi possível correr gcloud (faz login: gcloud auth login)" -ForegroundColor DarkYellow
    }
    Write-Host ""
}

Write-Banner

Write-Host "Deseja abrir no navegador as páginas de configuração do projeto " -NoNewline
Write-Host "$ProjectId" -ForegroundColor White -NoNewline
Write-Host " ? (S/N): " -NoNewline
$resposta = Read-Host
if ($resposta -notmatch '^[sSyY]') {
    Write-Host "Cancelado." -ForegroundColor DarkGray
    exit 0
}

$urls = @(
    @{
        Nome = "Firebase — Authentication (domínios e métodos de login)"
        Uri  = "https://console.firebase.google.com/project/$ProjectId/authentication/providers"
    },
    @{
        Nome = "Firebase — Authentication — Configurações (domínios autorizados)"
        Uri  = "https://console.firebase.google.com/project/$ProjectId/authentication/settings"
    },
    @{
        Nome = "Google Cloud — Credenciais (OAuth + chaves de API)"
        Uri  = "https://console.cloud.google.com/apis/credentials?project=$ProjectId"
    },
    @{
        Nome = "Google Cloud — Identity Platform (se usares)"
        Uri  = "https://console.cloud.google.com/customer-identity/providers?project=$ProjectId"
    },
    @{
        Nome = "Google Cloud — APIs ativadas (Identity Toolkit)"
        Uri  = "https://console.cloud.google.com/apis/library/identitytoolkit.googleapis.com?project=$ProjectId"
    }
)

Write-Host ""
Write-Host "A abrir $($urls.Count) separadores no browser predefinido..." -ForegroundColor Green
foreach ($item in $urls) {
    Write-Host "  - $($item.Nome)" -ForegroundColor Gray
    Start-Process $item.Uri
    Start-Sleep -Milliseconds 400
}

Write-Host ""
Write-Host "Checklist rápida (confirma no browser):" -ForegroundColor Cyan
Write-Host "  [ ] Firebase → Authentication → Domínios: dipertin.com.br E www.dipertin.com.br" -ForegroundColor White
Write-Host "  [ ] Credenciais → Cliente OAuth Web → Origens JS: https://dipertin.com.br e https://www.dipertin.com.br" -ForegroundColor White
Write-Host "  [ ] Chave API browser: restrições HTTP ou sem restrição para teste" -ForegroundColor White
Write-Host ""

Show-GcloudHints

Write-Host "Concluído." -ForegroundColor Green
Write-Host ""
