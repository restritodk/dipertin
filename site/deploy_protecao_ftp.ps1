# Deploy da Tela de Proteção (/sistema/) via FTP
#
# Credenciais: use as mesmas do site — site/.env.deploy (FTP_HOST, FTP_USER, FTP_PASS).
#
# Uso:
#   .\deploy_protecao_ftp.ps1
#   .\deploy_protecao_ftp.ps1 -PublishBoth
#   .\deploy_protecao_ftp.ps1 -PublishAll

param(
    [Parameter(Mandatory = $false)]
    [switch]$PublishBoth,
    [Parameter(Mandatory = $false)]
    [switch]$PublishAll
)

$ErrorActionPreference = "Stop"

function Import-DotEnvDeploy {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return }
    Get-Content -LiteralPath $Path -Encoding UTF8 | ForEach-Object {
        $line = $_.Trim()
        if ($line -match '^\s*#' -or $line -eq '') { return }
        if ($line -match '^([A-Za-z_][A-Za-z0-9_]*)=(.*)$') {
            $key = $Matches[1]
            $val = $Matches[2].Trim()
            if ($val.Length -ge 2 -and $val.StartsWith('"') -and $val.EndsWith('"')) {
                $val = $val.Substring(1, $val.Length - 2)
            }
            $existing = [Environment]::GetEnvironmentVariable($key, "Process")
            if (-not [string]::IsNullOrEmpty($existing)) { return }
            Set-Item -Path "Env:$key" -Value $val
        }
    }
}

$repoRoot = Split-Path $PSScriptRoot -Parent
$envFile = Join-Path $repoRoot "site\.env.deploy"
Import-DotEnvDeploy -Path $envFile

$ftpHost = $env:FTP_HOST
$ftpUser = $env:FTP_USER
$ftpPass = $env:FTP_PASS

$targets = [System.Collections.Generic.List[string]]::new()

if ($PublishAll) {
    [void]$targets.Add("/public_html/sistema")
    [void]$targets.Add("/dipertin.com.br/sistema")
    [void]$targets.Add("/home/microh94/public_html/sistema")
} elseif ($PublishBoth) {
    [void]$targets.Add("/public_html/sistema")
    [void]$targets.Add("/dipertin.com.br/sistema")
} else {
    [void]$targets.Add("/public_html/sistema")
}

$seen = @{}
$uniqueTargets = [System.Collections.Generic.List[string]]::new()
foreach ($p in $targets) {
    if (-not $seen.ContainsKey($p)) {
        $seen[$p] = $true
        [void]$uniqueTargets.Add($p)
    }
}
$targets = $uniqueTargets

if (-not $ftpHost -or -not $ftpUser -or -not $ftpPass) {
    Write-Host "Defina credenciais em site\.env.deploy (FTP_HOST, FTP_USER, FTP_PASS)." -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "=== DEPLOY BLOQUEADO: Tela de Protecao DESATIVADA ===" -ForegroundColor Red
Write-Host "A barreira 'Estamos preparando grandes novidades' foi removida." -ForegroundColor Yellow
Write-Host "Use: cd depertin_web; .\deploy_sistema_ftp.ps1" -ForegroundColor Cyan
Write-Host ""
exit 1

$siteRoot = Join-Path $repoRoot "site\sistema"
$excludeFiles = @("deploy_protecao_ftp.ps1")

$files = Get-ChildItem -Path $siteRoot -Recurse -File | Where-Object {
    $name = $_.Name
    $excluded = $false
    foreach ($ex in $excludeFiles) {
        if ($name -eq $ex) { $excluded = $true; break }
    }
    -not $excluded
}

$total = @($files).Count
if ($total -eq 0) {
    Write-Host "Nenhum arquivo para enviar." -ForegroundColor Yellow
    exit 0
}

Write-Host "Enviando $total arquivo(s)..." -ForegroundColor Green

$userColonPass = $ftpUser + ':' + $ftpPass

foreach ($remoteBase in $targets) {
    Write-Host ""
    Write-Host "=== FTP para $remoteBase ===" -ForegroundColor Yellow

    $i = 0
    foreach ($f in $files) {
        $i++
        $rel = $f.FullName.Substring($siteRoot.Length).TrimStart([char[]]@('\', '/')) -replace "\\", "/"
        $remotePath = "$remoteBase/$rel" -replace "//+", "/"
        $uri = "ftp://${ftpHost}${remotePath}"

        Write-Host "[$i/$total] $rel" -ForegroundColor Gray

        $curlArgs = @(
            '-sS', '--fail', '--connect-timeout', '45', '--ftp-pasv',
            '--upload-file', $f.FullName,
            '--user', $userColonPass,
            $uri,
            '--ftp-create-dirs'
        )

        & curl.exe @curlArgs
        if ($LASTEXITCODE -ne 0) {
            Write-Host "Falha no upload. curl exit $LASTEXITCODE" -ForegroundColor Red
            exit $LASTEXITCODE
        }
    }

    Write-Host "OK: $remoteBase" -ForegroundColor Green
}

Write-Host ""
Write-Host "=== Deploy Concluido ===" -ForegroundColor Green
Write-Host ""
Write-Host "Acesse: https://dipertin.com.br/sistema/" -ForegroundColor Cyan
Write-Host "Senha: 03091025" -ForegroundColor Yellow
Write-Host ""
Write-Host "Importante: Limpe o cache do navegador ou use Ctrl+Shift+R" -ForegroundColor DarkGray
