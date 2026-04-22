# Build do painel web (base /sistema/) + upload FTP para a subpasta no HostGator.

# Credenciais: mesmas do site — site/.env.deploy (FTP_HOST, FTP_USER, FTP_PASS).

#

# Uso:

#   .\deploy_sistema_ftp.ps1

#   .\deploy_sistema_ftp.ps1 -RemoteBase "/dipertin.com.br/sistema"

#   .\deploy_sistema_ftp.ps1 -PublishBoth

#     → sobe para /public_html/sistema E /dipertin.com.br/sistema (recomendado se o

#       domínio ainda mostra versão antiga: cobre os dois roots comuns na HostGator)

#

#   .\deploy_sistema_ftp.ps1 -PublishAll

#     → os dois acima + /home/microh94/public_html/sistema (cobre FTP com path absoluto)

#

#   cd c:\Projeto\DiPertin\depertin_web

#   .\deploy_sistema_ftp.ps1



param(

    [Parameter(Mandatory = $false)]

    [string]$RemoteBase = "",

    [Parameter(Mandatory = $false)]

    [string[]]$AlsoRemote = @(),

    [Parameter(Mandatory = $false)]

    [switch]$PublishBoth,

    [Parameter(Mandatory = $false)]

    [switch]$PublishAll,

    [Parameter(Mandatory = $false)]

    [switch]$SkipBuild,

    [Parameter(Mandatory = $false)]

    [switch]$SkipHttpVerify

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

} elseif ($RemoteBase -ne "") {

    [void]$targets.Add($RemoteBase.TrimEnd('/'))

    foreach ($a in $AlsoRemote) {

        $t = $a.Trim().TrimEnd('/')

        if ($t -ne "") { [void]$targets.Add($t) }

    }

} elseif ($env:FTP_SISTEMA_REMOTE_BASE) {

    [void]$targets.Add($env:FTP_SISTEMA_REMOTE_BASE.TrimEnd('/'))

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

Write-Host "========== DESTINO(S) DO UPLOAD (FTP) ==========" -ForegroundColor Yellow

Write-Host "  Host: $($ftpHost)"

foreach ($p in $targets) {

    Write-Host "  -> ${p}/"

}

Write-Host ""

Write-Host "Tela antiga? Use -PublishAll ou -PublishBoth; no Cloudflare: Purge Cache (tudo ou /sistema/*)." -ForegroundColor Yellow

Write-Host "================================================" -ForegroundColor Yellow

Write-Host ""



Set-Location $PSScriptRoot



if (-not $SkipBuild) {

    Write-Host "=== Flutter build web (base-href /sistema/, PWA off) ===" -ForegroundColor Cyan

    flutter pub get

    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }



    flutter build web --release --base-href /sistema/ --pwa-strategy=none --no-tree-shake-icons

    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

} else {

    Write-Host "=== SkipBuild: usando build\web existente ===" -ForegroundColor DarkYellow

}



$buildRoot = Join-Path $PSScriptRoot "build\web"

if (-not (Test-Path -LiteralPath $buildRoot)) {

    Write-Host "Pasta build\web nao encontrada." -ForegroundColor Red

    exit 1

}



# Força navegador/CDN a buscar novo bootstrap e main.dart.js a cada deploy.

$ver = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()

# 1) index.html: cache-bust flutter_bootstrap.js
$buildIndexHtml = Join-Path $buildRoot "index.html"

if (Test-Path -LiteralPath $buildIndexHtml) {

    $idx = [System.IO.File]::ReadAllText($buildIndexHtml)

    if ($idx -match "flutter_bootstrap\.js\?v=\d+") {

        $idx = $idx -replace "flutter_bootstrap\.js\?v=\d+", "flutter_bootstrap.js?v=$ver"

    } else {

        $idx = $idx -replace "flutter_bootstrap\.js'", "flutter_bootstrap.js?v=$ver'"

    }

    [System.IO.File]::WriteAllText($buildIndexHtml, $idx, [System.Text.UTF8Encoding]::new($false))

    Write-Host "index.html: flutter_bootstrap.js?v=$ver (cache-bust)" -ForegroundColor DarkGray

}

# 2) flutter_bootstrap.js: cache-bust main.dart.js
#    O Cloudflare/CDN pode cachear main.dart.js por nome fixo mesmo com no-cache no .htaccess.
#    Substituindo "main.dart.js" por "main.dart.js?v=TIMESTAMP" dentro do bootstrap,
#    o browser e o CDN são forçados a buscar o JS compilado novo.
$buildBootstrap = Join-Path $buildRoot "flutter_bootstrap.js"

if (Test-Path -LiteralPath $buildBootstrap) {

    $boot = [System.IO.File]::ReadAllText($buildBootstrap)

    # Remove versão anterior se já existir, depois insere a nova
    $boot = $boot -replace '"main\.dart\.js\?v=\d+"', '"main.dart.js"'
    $boot = $boot -replace '"main\.dart\.js"', "`"main.dart.js?v=$ver`""

    [System.IO.File]::WriteAllText($buildBootstrap, $boot, [System.Text.UTF8Encoding]::new($false))

    Write-Host "flutter_bootstrap.js: main.dart.js?v=$ver (cache-bust)" -ForegroundColor DarkGray

}

# 3) Versiona nome fisico das fontes de icones no FontManifest.
#    Isso evita cache antigo de CDN mesmo sem purge.
$fontDir = Join-Path $buildRoot "assets\fonts"
$cupertinoDir = Join-Path $buildRoot "assets\packages\cupertino_icons\assets"
$buildFontManifest = Join-Path $buildRoot "assets\FontManifest.json"

if (Test-Path -LiteralPath $buildFontManifest) {

    $fontManifest = [System.IO.File]::ReadAllText($buildFontManifest)

    $materialSrc = Join-Path $fontDir "MaterialIcons-Regular.otf"
    if (Test-Path -LiteralPath $materialSrc) {
        $materialVersioned = "MaterialIcons-Regular-$ver.otf"
        $materialDst = Join-Path $fontDir $materialVersioned
        Copy-Item -LiteralPath $materialSrc -Destination $materialDst -Force
        $fontManifest = $fontManifest -replace "fonts/MaterialIcons-Regular\.otf", "fonts/$materialVersioned"
    }

    $cupertinoSrc = Join-Path $cupertinoDir "CupertinoIcons.ttf"
    if (Test-Path -LiteralPath $cupertinoSrc) {
        $cupertinoVersioned = "CupertinoIcons-$ver.ttf"
        $cupertinoDst = Join-Path $cupertinoDir $cupertinoVersioned
        Copy-Item -LiteralPath $cupertinoSrc -Destination $cupertinoDst -Force
        $fontManifest = $fontManifest -replace "packages/cupertino_icons/assets/CupertinoIcons\.ttf", "packages/cupertino_icons/assets/$cupertinoVersioned"
    }

    [System.IO.File]::WriteAllText($buildFontManifest, $fontManifest, [System.Text.UTF8Encoding]::new($false))

    Write-Host "FontManifest.json: fontes versionadas por nome ($ver)" -ForegroundColor DarkGray

}

# .htaccess: sem mod_rewrite (hash routes). mod_headers reduz cache agressivo em JS/WASM/JSON.

$htPath = Join-Path $buildRoot ".htaccess"

$htSafe = @"

# DiPertin painel web (Flutter /sistema/) — sem rewrite (#/login).

# Cloudflare pode ignorar origem: use Purge Cache após deploy.



<IfModule mod_headers.c>

  <FilesMatch "\.(html|js|wasm|frag|json|otf|ttf|woff|woff2)$">

    Header set Cache-Control "no-cache, no-store, must-revalidate"

    Header set Pragma "no-cache"

  </FilesMatch>

  # CSP para Flutter Web — sobrescreve a CSP do .htaccess raiz (site estatico).
  # script-src: accounts.google.com = GSI (gsi/client). www.google.com + recaptcha.net = reCAPTCHA v3 (App Check).
  # connect-src: Firebase (Functions/Firestore/Auth/Storage) + firebaseappcheck (token exchange).
  Header always set Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline' 'wasm-unsafe-eval' https://www.gstatic.com https://apis.google.com https://accounts.google.com https://www.google.com https://www.recaptcha.net; style-src 'self' 'unsafe-inline' https://fonts.googleapis.com https://accounts.google.com; font-src 'self' https://fonts.gstatic.com data:; img-src 'self' data: https: blob:; connect-src 'self' blob: https://us-central1-depertin-f940f.cloudfunctions.net https://*.cloudfunctions.net https://*.run.app https://firestore.googleapis.com https://firebase.googleapis.com https://firebaseinstallations.googleapis.com https://firebaseappcheck.googleapis.com https://identitytoolkit.googleapis.com https://securetoken.googleapis.com https://www.googleapis.com https://fonts.googleapis.com https://fonts.gstatic.com https://*.gstatic.com https://accounts.google.com https://apis.google.com https://firebasestorage.googleapis.com https://storage.googleapis.com https://www.google.com https://www.recaptcha.net; frame-src 'self' https://accounts.google.com https://www.google.com https://www.recaptcha.net https://www.gstatic.com https://depertin-f940f.firebaseapp.com https://*.firebaseapp.com https://firebasestorage.googleapis.com https://storage.googleapis.com https://docs.google.com; worker-src 'self' blob:; object-src 'none'; base-uri 'self'; frame-ancestors 'self'"
  Header always set Cross-Origin-Opener-Policy "same-origin-allow-popups"
  Header always set X-Content-Type-Options "nosniff"
  Header always set X-Frame-Options "SAMEORIGIN"

</IfModule>

"@

[System.IO.File]::WriteAllText($htPath, $htSafe.Trim() + "`n", [System.Text.UTF8Encoding]::new($false))



$files = Get-ChildItem -Path $buildRoot -Recurse -File | Where-Object {

    $_.Name -ne ".DS_Store"

}



$fileCount = @($files).Count

if ($fileCount -eq 0) {

    Write-Host "Nenhum arquivo em build\web." -ForegroundColor Red

    exit 1

}

Write-Host "Build local: $fileCount arquivo(s) (inclui assets/, canvaskit/, icons/)." -ForegroundColor DarkGray

Write-Host "No cPanel a DATA DAS PASTAS costuma ficar antiga ao sobrescrever arquivos; confira a data DENTRO de cada pasta." -ForegroundColor DarkGray



$userColonPass = $ftpUser + ':' + $ftpPass



foreach ($remoteSistema in $targets) {

    Write-Host "=== FTP: $fileCount arquivo(s) -> ${remoteSistema}/ ===" -ForegroundColor Cyan

    $i = 0

    foreach ($f in $files) {

        $i++

        $rel = $f.FullName.Substring($buildRoot.Length).TrimStart([char[]]@('\', '/')) -replace "\\", "/"

        $remotePath = "$remoteSistema/$rel" -replace "//+", "/"

        $uri = "ftp://${ftpHost}${remotePath}"

        Write-Host "[$i/$fileCount] $rel" -ForegroundColor Gray

        $curlArgs = @(

            '-sS', '--fail', '--connect-timeout', '120', '--max-time', '0', '--ftp-pasv',

            '--upload-file', $f.FullName,

            '--user', $userColonPass,

            $uri,

            '--ftp-create-dirs'

        )

        & curl.exe @curlArgs

        if ($LASTEXITCODE -ne 0) {

            Write-Host "Falha no upload para $remoteSistema. curl exit $LASTEXITCODE" -ForegroundColor Red

            exit $LASTEXITCODE

        }

    }

    Write-Host "OK: $remoteSistema" -ForegroundColor Green

}

Write-Host ""

Write-Host "flutter_service_worker.js com 0 bytes: normal com --pwa-strategy=none (sem PWA/cache agressivo)." -ForegroundColor DarkGray

Write-Host ""

if (-not $SkipHttpVerify) {

    $verifyBase = $env:FTP_SISTEMA_VERIFY_BASE

    if ([string]::IsNullOrWhiteSpace($verifyBase)) { $verifyBase = "https://dipertin.com.br" }

    $verifyBase = $verifyBase.TrimEnd('/')

    Write-Host "Verificacao HTTP (prova que subpastas estao no servidor):" -ForegroundColor Cyan

    $probePaths = @(

        "/sistema/canvaskit/canvaskit.wasm",

        "/sistema/assets/shaders/ink_sparkle.frag",

        "/sistema/icons/Icon-192.png"

    )

    foreach ($pp in $probePaths) {

        $u = "$verifyBase$pp"

        $httpCode = (& curl.exe -s -o NUL -w "%{http_code}" -L --max-time 25 $u 2>&1).Trim()

        if ($httpCode -eq "200") {

            Write-Host "  OK $pp (HTTP $httpCode)" -ForegroundColor Green

        } else {

            Write-Host "  Falha $pp (HTTP $httpCode) — verifique URL ou Cloudflare." -ForegroundColor Yellow

        }

    }

    Write-Host "(Opcional: env FTP_SISTEMA_VERIFY_BASE=https://seu-dominio para outro host.)" -ForegroundColor DarkGray

    Write-Host ""

}



Write-Host "Painel publicado. Teste: https://dipertin.com.br/sistema/#/login" -ForegroundColor Green

Write-Host "(Se usar Cloudflare, faca Purge Cache no painel.)" -ForegroundColor DarkGray

