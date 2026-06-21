# DiPertin — Iniciar ferramenta DEV de limpeza
# Duplo-clique ou: powershell -ExecutionPolicy Bypass -File dev-iniciar-limpeza.ps1

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

Write-Host ""
Write-Host "DiPertin — Ferramenta DEV de limpeza" -ForegroundColor Magenta
Write-Host "=====================================" -ForegroundColor Magenta
Write-Host ""

function Test-AdcGcloud {
    $adc = Join-Path $env:APPDATA "gcloud\application_default_credentials.json"
    return Test-Path $adc
}

function Escolher-ServiceAccount {
    Add-Type -AssemblyName System.Windows.Forms | Out-Null
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Title = "Selecione o serviceAccount.json do Firebase"
    $dlg.Filter = "JSON (*.json)|*.json"
    $dlg.InitialDirectory = $PSScriptRoot
    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        return $dlg.FileName
    }
    return $null
}

# 1) serviceAccount.json na raiz do projeto
$destinoRaiz = Join-Path $PSScriptRoot "serviceAccount.json"

if (-not $env:GOOGLE_APPLICATION_CREDENTIALS) {
    $candidatos = @(
        $destinoRaiz,
        "$PSScriptRoot\depertin_cliente\functions\serviceAccount.json",
        "$PSScriptRoot\depertin-f940f-firebase-adminsdk.json"
    )
    foreach ($c in $candidatos) {
        if (Test-Path $c) {
            $env:GOOGLE_APPLICATION_CREDENTIALS = $c
            Write-Host "Credenciais: $c" -ForegroundColor Green
            break
        }
    }
}

# 2) Se não achou, tenta gcloud ADC (login firebase/gcloud já feito)
if (-not $env:GOOGLE_APPLICATION_CREDENTIALS -and (Test-AdcGcloud)) {
    Write-Host "Credenciais: gcloud Application Default (sem serviceAccount.json)" -ForegroundColor Green
}

# 3) Se ainda não tem, abre seletor de arquivo
if (-not $env:GOOGLE_APPLICATION_CREDENTIALS -and -not (Test-AdcGcloud)) {
    Write-Host ""
    Write-Host "serviceAccount.json nao encontrado na raiz." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Como obter:" -ForegroundColor Cyan
    Write-Host "  Firebase Console > Configuracoes > Contas de servico > Gerar nova chave privada"
    Write-Host "  Salve como: $destinoRaiz"
    Write-Host ""
    Write-Host "Ou selecione o arquivo .json agora..." -ForegroundColor Yellow
    $escolhido = Escolher-ServiceAccount
    if ($escolhido) {
        Copy-Item -Path $escolhido -Destination $destinoRaiz -Force
        $env:GOOGLE_APPLICATION_CREDENTIALS = $destinoRaiz
        Write-Host "Copiado para: $destinoRaiz" -ForegroundColor Green
    }
}

if (-not $env:GOOGLE_APPLICATION_CREDENTIALS -and -not (Test-AdcGcloud)) {
    Write-Host ""
    Write-Host "ERRO: nenhuma credencial Firebase disponivel." -ForegroundColor Red
    Write-Host 'Coloque serviceAccount.json em C:\Projeto\DiPertin\ e rode de novo.' -ForegroundColor Yellow
    Read-Host "Pressione Enter para sair"
    exit 1
}

$env:GOOGLE_CLOUD_QUOTA_PROJECT = "depertin-f940f"
$env:GCLOUD_PROJECT = "depertin-f940f"

$adminPath = "$PSScriptRoot\depertin_cliente\functions\node_modules\firebase-admin"
if (-not (Test-Path $adminPath)) {
    Write-Host "Instalando dependencias..." -ForegroundColor Yellow
    Push-Location "$PSScriptRoot\depertin_cliente\functions"
    npm install --silent
    Pop-Location
}

$porta = if ($env:DEV_LIMPEZA_PORT) { $env:DEV_LIMPEZA_PORT } else { "8765" }
$url = "http://127.0.0.1:$porta"

Write-Host ""
Write-Host "Iniciando servidor: $url" -ForegroundColor Green
Write-Host "Mantenha esta janela ABERTA." -ForegroundColor Yellow
Write-Host ""

Start-Process $url
node "$PSScriptRoot\dev-listar-usuarios-limpeza-server.js"
