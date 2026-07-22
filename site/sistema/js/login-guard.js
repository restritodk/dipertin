/**
 * DiPertin — Guard de Proteção da Tela de Login
 *
 * Incluir este script na página de LOGIN para verificar
 * se o usuário passou pela tela de proteção.
 *
 * Este script é 100% local, sem Firebase.
 */

(function() {
  'use strict';

  // ═══════════════════════════════════════════════════════════════
  // CONSTANTES
  // ═══════════════════════════════════════════════════════════════

  const STORAGE_KEY = 'dipertin_admin_access';
  const PROTECTION_PATH = '/sistema/';
  const CHECK_DELAY = 100; // ms

  // ═══════════════════════════════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════════════════════════════

  /**
   * Verifica se o usuário tem acesso válido
   */
  function hasValidAccess() {
    try {
      const access = sessionStorage.getItem(STORAGE_KEY);
      if (!access) return false;

      const data = JSON.parse(access);
      const now = Date.now();

      // Token válido por 8 horas
      const isValid = data.token === '03091025' &&
                      data.verified === true &&
                      data.expiresAt > now;

      return isValid;
    } catch {
      return false;
    }
  }

  /**
   * Redireciona para a tela de proteção
   */
  function redirectToProtection() {
    // Salva a URL atual para voltar depois
    const currentUrl = window.location.href;
    sessionStorage.setItem('dipertin_redirect_back', currentUrl);

    // Redireciona para proteção
    window.location.href = PROTECTION_PATH;
  }

  /**
   * Verifica o acesso e age apropriadamente
   */
  function checkAccess() {
    if (!hasValidAccess()) {
      redirectToProtection();
      return false;
    }
    return true;
  }

  // ═══════════════════════════════════════════════════════════════
  // INICIALIZAÇÃO
  // ═══════════════════════════════════════════════════════════════

  /**
   * Inicializa a proteção
   */
  function init() {
    // Pequeno delay para garantir que o DOM carregou
    setTimeout(function() {
      checkAccess();
    }, CHECK_DELAY);
  }

  // Executa imediatamente
  init();

})();
