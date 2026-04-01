# Cria o repositorio "DiPertin" na conta GitHub do token e faz push do ramo main.
# Uso (PowerShell):
#   $env:GITHUB_TOKEN = "ghp_xxxxxxxx"   # Token: GitHub > Settings > Developer settings > PAT (scope: repo)
#   Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
#   .\criar_repo_e_push.ps1
#
# Criar token: https://github.com/settings/tokens/new (classic) — marcar "repo"

param(
    [string]$NomeRepo = "DiPertin",
    [string]$Token = $env:GITHUB_TOKEN
)

$ErrorActionPreference = "Stop"
$Raiz = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $Raiz

if (-not $Token) {
    Write-Host ""
    Write-Host "ERRO: Defina a variavel de ambiente GITHUB_TOKEN com um Personal Access Token." -ForegroundColor Red
    Write-Host "  GitHub > Settings > Developer settings > Personal access tokens > Tokens (classic) > repo" -ForegroundColor Yellow
    Write-Host "  Depois: `$env:GITHUB_TOKEN = 'ghp_...'" -ForegroundColor Yellow
    Write-Host ""
    exit 1
}

$headers = @{
    Authorization = "Bearer $Token"
    Accept        = "application/vnd.github+json"
}

Write-Host "A obter utilizador GitHub..."
$user = Invoke-RestMethod -Uri "https://api.github.com/user" -Headers $headers -Method Get
$login = $user.login
Write-Host "Conta: $login"

$apiRepo = "https://api.github.com/repos/$login/$NomeRepo"
$jaExiste = $false

try {
    $null = Invoke-RestMethod -Uri $apiRepo -Headers $headers -Method Get -ErrorAction Stop
    $jaExiste = $true
} catch {
    $resp = $_.Exception.Response
    if ($resp -and $resp.StatusCode -eq 404) {
        $jaExiste = $false
    } else {
        throw
    }
}

if (-not $jaExiste) {
    Write-Host "A criar repositorio $NomeRepo..."
    $body = @{
        name        = $NomeRepo
        description = "DiPertin - apps Flutter (depertin_cliente e depertin_web)"
        private     = $false
    } | ConvertTo-Json
    $null = Invoke-RestMethod -Uri "https://api.github.com/user/repos" -Headers $headers -Method Post -Body $body -ContentType "application/json; charset=utf-8"
    Write-Host "Repositorio criado: https://github.com/$login/$NomeRepo" -ForegroundColor Green
} else {
    Write-Host "Repositorio ja existe: https://github.com/$login/$NomeRepo" -ForegroundColor Cyan
}

$remoteUrl = "https://github.com/$login/$NomeRepo.git"
Write-Host "A configurar remote origin -> $remoteUrl"
git remote remove origin 2>$null
git remote add origin $remoteUrl

Write-Host "A fazer push (main)..."
# Autenticacao HTTPS: Git pede credenciais ou usa Credential Manager; username = token user, password = PAT
$env:GIT_TERMINAL_PROMPT = "1"
git push -u origin main

if ($LASTEXITCODE -eq 0) {
    Write-Host ""
    Write-Host "Concluido: https://github.com/$login/$NomeRepo" -ForegroundColor Green
} else {
    Write-Host ""
    Write-Host "Push falhou. Se pedir credenciais: username = $login ; password = o mesmo GITHUB_TOKEN (PAT)." -ForegroundColor Yellow
    exit $LASTEXITCODE
}
