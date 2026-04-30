/**
 * GUIA: Sistema Transacional de Reserva de Saldo
 * 
 * ========================================
 * FLUXO CORRETO (NOVO - IMPLEMENTADO)
 * ========================================
 * 
 * ANTES (INCORRETO - BUGADO):
 * 1. Cria pedido com status "aguardando_pagamento"
 * 2. DEBITA saldo IMEDIATAMENTE ❌ BUG
 * 3. Abre tela de PIX/Cartão
 * 4. Cliente processa pagamento
 * 5. Se falhar → Saldo já foi perdido! ❌
 * 
 * DEPOIS (CORRETO - IMPLEMENTADO):
 * 1. Cria pedido com status "aguardando_pagamento"
 * 2. Chamar walletReservarSaldo() → RESERVA (não debita) ✅
 * 3. Armazena reservaId no pedido
 * 4. Abre tela de PIX/Cartão
 * 5. Cliente processa pagamento
 *    5a. SUCESSO → walletConfirmarDebito() → DEBITA ✅
 *    5b. FALHA → walletCancelarReserva() → LIBERA ✅
 * 
 * ========================================
 * LOCALIZAÇÕES NO CÓDIGO
 * ========================================
 * 
 * [Dart] cart_screen.dart
 * - Linha ~1268-1272 (ANTES): Debitava saldo imediatamente
 * - Agora (~1268-1318): Cria reserva para PIX/Cartão
 * 
 * [Dart] checkout_pagamento_screen.dart
 * - Imports: Adicionado "import 'wallet_reserva_service.dart'"
 * - _confirmarReservaDeSaldo(): Chama após sucesso de pagamento
 * - _cancelarReservaDeSaldo(): Chama em caso de erro/recusa
 * 
 * [Cloud Function] wallet_reservas.js
 * - walletReservarSaldo: Etapa 1 (reserva)
 * - walletConfirmarDebito: Etapa 2 (debita após sucesso)
 * - walletCancelarReserva: Etapa 3 (cancela se falha)
 * - walletLimparReservasExpiradas: Limpeza (executa a cada 15 min)
 * 
 * ========================================
 * TESTES OBRIGATÓRIOS
 * ========================================
 * 
 * TEST 1: Wallet Total (Saldo: 50, Compra: 40)
 * ─────────────────────────────────────────
 * 1. Cliente tem saldo: R$ 50
 * 2. Compra no valor: R$ 40
 * 3. Usa saldo completo: R$ 40
 * 4. Pagamento externo: R$ 0
 * 5. Espera: Saldo debitado imediatamente = R$ 10
 *    ✓ Status: FINAL (pagamento não necessário)
 * 
 * TEST 2: Wallet Parcial + PIX (Saldo: 50, Usa: 20, Compra: 50) - SUCESSO
 * ─────────────────────────────────────────────────────────────────────
 * 1. Cliente tem saldo: R$ 50
 * 2. Compra no valor: R$ 50
 * 3. Usa saldo: R$ 20 (parcial)
 * 4. Precisa pagar externo: R$ 30
 * 5. Fluxo:
 *    - walletReservarSaldo(20) → Saldo: R$ 50, Reservado: R$ 20 ✓
 *    - Abre PIX → Cliente paga R$ 30
 *    - PIX confirmado
 *    - walletConfirmarDebito(reserva) → Saldo: R$ 30, Reservado: R$ 0 ✓
 * 6. Final: Saldo = R$ 30 ✓
 * 
 * TEST 3: Wallet Parcial + PIX (Saldo: 50, Usa: 20, Compra: 50) - FALHA
 * ─────────────────────────────────────────────────────────────────────
 * 1. Cliente tem saldo: R$ 50
 * 2. Compra no valor: R$ 50
 * 3. Usa saldo: R$ 20 (parcial)
 * 4. Precisa pagar externo: R$ 30
 * 5. Fluxo:
 *    - walletReservarSaldo(20) → Saldo: R$ 50, Reservado: R$ 20 ✓
 *    - Abre PIX → Cliente não paga / PIX expira
 *    - Pagamento falhou
 *    - walletCancelarReserva(reserva) → Saldo: R$ 50, Reservado: R$ 0 ✓
 * 6. Final: Saldo = R$ 50 (inalterado!) ✓
 * 
 * TEST 4: Timeout/Erro de API
 * ──────────────────────────
 * 1. Cliente tem saldo: R$ 50
 * 2. Compra: R$ 30
 * 3. Usa saldo: R$ 30
 * 4. Fluxo:
 *    - walletReservarSaldo(30) → Saldo: R$ 50, Reservado: R$ 30 ✓
 *    - App crash / timeout / erro de rede
 *    - Reserva fica PENDENTE por 1 hora
 *    - walletLimparReservasExpiradas() executa
 *    - Reserva > 1h → Status: CANCELADO automático ✓
 *    - Saldo: R$ 50 (restaurado!) ✓
 * 
 * ========================================
 * COMO EXECUTAR TESTES
 * ========================================
 * 
 * 1. Reconstruir APK com código novo:
 *    cd depertin_cliente
 *    flutter clean
 *    flutter pub get
 *    flutter build apk --release
 * 
 * 2. Deploy das Cloud Functions:
 *    cd depertin_cliente/functions
 *    firebase deploy --only functions:walletReservarSaldo,functions:walletConfirmarDebito,functions:walletCancelarReserva,functions:walletLimparReservasExpiradas
 * 
 * 3. Executar testes manualmente no app:
 *    - Testar cada cenário de TEST 1-4
 *    - Validar saldo em tempo real no Firestore
 *    - Verificar logs em wallet_transaction_logs
 * 
 * ========================================
 * VALIDAÇÃO NO FIRESTORE
 * ========================================
 * 
 * Collection: users/{uid}
 * {
 *   "saldo": 50,
 *   "saldo_reservado": 0  // Campo novo! Criado automaticamente
 * }
 * 
 * Collection: users/{uid}/wallet_reservas
 * {
 *   "pedido_id": "...pedido123",
 *   "valor_reservado": 20,
 *   "status": "PENDENTE" | "CONFIRMADO" | "CANCELADO",
 *   "criado_em": Timestamp,
 *   "confirmado_em": Timestamp (null se não confirmado)
 * }
 * 
 * Collection: wallet_transaction_logs
 * {
 *   "usuario_id": "...uid",
 *   "pedido_id": "...pedido123",
 *   "tipo": "RESERVA" | "CONFIRMADO" | "CANCELADO" | "CANCELADO_AUTO",
 *   "valor": 20,
 *   "status": "PENDENTE" | "SUCESSO" | "FALHA" | "EXPIRADA",
 *   "motivo": "...",
 *   "criado_em": Timestamp
 * }
 * 
 * ========================================
 * MONITORAMENTO
 * ========================================
 * 
 * Monitor a limpeza automática de reservas expiradas:
 * 1. Firebase Console → Cloud Functions → walletLimparReservasExpiradas
 * 2. Procurar por logs contendo "[wallet_reservas]"
 * 3. Verificar se executa a cada 15 minutos sem erros
 * 
 * Monitor transações:
 * 1. Firebase Console → Firestore → wallet_transaction_logs
 * 2. Filtrar por usuario_id para auditoria
 * 3. Validar sequência: RESERVA → CONFIRMADO/CANCELADO
 * 
 * ========================================
 * ROLLBACK (Se necessário desabilitar)
 * ========================================
 * 
 * Se encontrar bugs críticos:
 * 1. Voltar ao debit imediato em cart_screen.dart (linhas 1268-1318)
 * 2. Comentar chamadas de _confirmarReservaDeSaldo() em checkout_pagamento_screen.dart
 * 3. Redeployar Cloud Functions sem wallet_reservas.js
 * 4. Rebuild APK
 * 
 * ========================================
 * NOTAS IMPORTANTES
 * ========================================
 * 
 * - Saldo negativo NUNCA é permitido (validação em Cloud Function)
 * - Reserva com valor > saldo disponível é rejeitada
 * - Reserva expira automaticamente em 1 hora (via scheduler)
 * - Transações são ACID (atomicidade garantida por Firestore)
 * - Logs completos para auditoria em wallet_transaction_logs
 * - Implementação ready para 24/7 production
 */
