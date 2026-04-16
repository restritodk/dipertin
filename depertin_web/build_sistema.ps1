# Build do painel web para publicar em https://www.dipertin.com.br/sistema/
# Uso (PowerShell, na pasta depertin_web):
#   .\build_sistema.ps1
#
# Depois envie TODO o conteúdo de build\web\ para o FTP:
#   pasta remota: .../dipertin.com.br/sistema/  (ou public_html/sistema/)
#
# Não suba a pasta build inteira — só os arquivos DENTRO de build\web\

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

Write-Host "=== DiPertin — flutter build web (base-href /sistema/) ===" -ForegroundColor Cyan

flutter pub get
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

flutter build web --release --base-href /sistema/ --pwa-strategy=none --no-tree-shake-icons

if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host ""
Write-Host "Pronto. Saída em: $PSScriptRoot\build\web\" -ForegroundColor Green
Write-Host "Envie esses arquivos para a pasta 'sistema' no servidor (substituindo os antigos)." -ForegroundColor Yellow
