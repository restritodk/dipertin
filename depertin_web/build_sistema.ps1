# Build do painel web para publicar em https://www.dipertin.com.br/sistema/
# Uso (PowerShell, na pasta depertin_web):
#   .\build_sistema.ps1
#
# Depois envie TODO o conteúdo de build\web\ para o FTP:
#   pasta remota: .../dipertin.com.br/sistema/  (ou public_html/sistema/)
#
# Gestão Comercial / E-mail transacional — antes do go-live:
#   docs/GESTAO_COMERCIAL_CHECKLIST_PRODUCAO.md
#   (GC_EMAIL_CONFIG_SECRET em depertin_cliente/functions/.env + redeploy functions)
#
# Não suba a pasta build inteira — só os arquivos DENTRO de build\web\
#
# App Check: DESATIVADO no painel (main.dart não ativa reCAPTCHA).
# Callables usam enforceAppCheck:false — não passe RECAPTCHA_V3_SITE_KEY.

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

Write-Host "=== DiPertin — flutter build web (base-href /sistema/) ===" -ForegroundColor Cyan
Write-Host "App Check: desativado no painel (Auth Bearer apenas)." -ForegroundColor DarkGray

flutter pub get
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

flutter build web --release --base-href /sistema/ --pwa-strategy=none

if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host ""
Write-Host "Pronto. Saída em: $PSScriptRoot\build\web\" -ForegroundColor Green
Write-Host "Envie esses arquivos para a pasta 'sistema' no servidor (substituindo os antigos)." -ForegroundColor Yellow
Write-Host ""
Write-Host "Lembrete Gestão Comercial (e-mail transacional):" -ForegroundColor Magenta
Write-Host "  docs/GESTAO_COMERCIAL_CHECKLIST_PRODUCAO.md" -ForegroundColor Magenta
Write-Host "  GC_EMAIL_CONFIG_SECRET + redeploy functions antes de produção." -ForegroundColor Magenta
