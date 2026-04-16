# Deploy do site estático via FTP (ex.: HostGator).
#
# Credenciais: crie site/.env.deploy (veja .env.deploy.example) — arquivo no .gitignore.
# Ou defina no PowerShell: $env:FTP_HOST, FTP_USER, FTP_PASS, opcional FTP_REMOTE_BASE.
#
#   .\deploy-ftp.ps1

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

$envFile = Join-Path $PSScriptRoot ".env.deploy"
Import-DotEnvDeploy -Path $envFile

$ftpHost = $env:FTP_HOST
$ftpUser = $env:FTP_USER
$ftpPass = $env:FTP_PASS
$remoteBase = if ($env:FTP_REMOTE_BASE) { $env:FTP_REMOTE_BASE.TrimEnd('/') } else { "/public_html" }

if (-not $ftpHost -or -not $ftpUser -or -not $ftpPass) {
    Write-Host "Crie site/.env.deploy (copie de .env.deploy.example) ou defina FTP_HOST, FTP_USER, FTP_PASS." -ForegroundColor Red
    exit 1
}

$siteRoot = $PSScriptRoot
$excludeDirNames = @("node_modules", ".git", ".firebase", "scripts")
$excludeFiles = @(
    "package.json", "package-lock.json", "firebase.json", ".firebaserc",
    "deploy-ftp.ps1", ".env.deploy", ".env.deploy.example"
)

function Test-ExcludedPath {
    param([string]$RelativePath)
    $parts = $RelativePath -split "/" | Where-Object { $_ }
    foreach ($d in $excludeDirNames) {
        if ($parts -contains $d) { return $true }
    }
    $name = Split-Path -Leaf $RelativePath
    if ($excludeFiles -contains $name) { return $true }
    return $false
}

$files = Get-ChildItem -Path $siteRoot -Recurse -File | ForEach-Object {
    $rel = $_.FullName.Substring($siteRoot.Length).TrimStart([char[]]@('\', '/')) -replace "\\", "/"
    if (Test-ExcludedPath $rel) { return }
    [PSCustomObject]@{ Full = $_.FullName; Relative = $rel }
} | Where-Object { $_ }

$total = @($files).Count
if ($total -eq 0) { Write-Host "Nenhum arquivo para enviar." -ForegroundColor Yellow; exit 0 }

Write-Host "Enviando $total arquivo(s) para ftp://${ftpHost}${remoteBase}/ ..." -ForegroundColor Cyan

$userColonPass = $ftpUser + ':' + $ftpPass
$i = 0
foreach ($f in $files) {
    $i++
    $remotePath = "$remoteBase/$($f.Relative)" -replace "//+", "/"
    $uri = "ftp://${ftpHost}${remotePath}"
    Write-Host "[$i/$total] $($f.Relative)" -ForegroundColor Gray
    $curlArgs = @(
        '-sS', '--fail', '--connect-timeout', '45', '--ftp-pasv',
        '--upload-file', $f.Full,
        '--user', $userColonPass,
        $uri,
        '--ftp-create-dirs'
    )
    & curl.exe @curlArgs
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Falha no upload. curl exit $LASTEXITCODE" -ForegroundColor Red
        Write-Host "Se o servidor exigir FTPS, avise para ajustar o script (curl --ssl-reqd)." -ForegroundColor Yellow
        exit $LASTEXITCODE
    }
}

Write-Host "Concluído." -ForegroundColor Green
