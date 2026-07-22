@echo off
cd /d C:\Projeto\DiPertin\depertin_cliente
npx firebase-tools@latest emulators:exec --project demo-depertin-teste --only functions,firestore,auth,storage "cd functions && node --test --test-concurrency=1 test/nfe_fluxo_completo.integration.test.js" 2>&1
