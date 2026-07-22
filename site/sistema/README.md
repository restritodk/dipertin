# Tela de proteção — DESATIVADA

A barreira **"Estamos preparando grandes novidades"** (senha admin antes do login) foi **removida**.

- O painel volta a abrir direto em `/sistema/#/login` (Flutter).
- O deploy (`depertin_web/deploy_sistema_ftp.ps1`) **não** copia mais `index.html` / `js` / `css` de proteção sobre o build.
- Os arquivos em `site/sistema/` ficam só como arquivo histórico; **não** use `deploy_protecao_ftp.ps1` em produção.

Para publicar o painel sem a tela de manutenção:

```powershell
cd depertin_web
.\deploy_sistema_ftp.ps1
```

Depois, no Cloudflare: **Purge Cache** de `/sistema/*`.
