/**
 * DiPertin — Tela de Proteção Premium
 * Script de validação de senha administrativa
 *
 * SENHA: 03091025
 * Validação 100% local - sem Firebase, sem banco de dados
 *
 * Este script funciona em duas páginas:
 *   index.html (proteção) — exibe formulário de senha
 *   app.html   (painel)   — verifica sessão antes de carregar o Flutter
 */

(function() {
  'use strict';

  // ═══════════════════════════════════════════════════════════════
  // CONSTANTES
  // ═══════════════════════════════════════════════════════════════

  const ADMIN_PASSWORD = '03091025';
  const STORAGE_KEY = 'dipertin_admin_access';
  const APP_PATH = '/sistema/app.html#/login';

  // ═══════════════════════════════════════════════════════════════
  // ESTADO
  // ═══════════════════════════════════════════════════════════════

  let isProcessing = false;

  // ═══════════════════════════════════════════════════════════════
  // HELPERS — exportados para window (usados pelo app.html)
  // ═══════════════════════════════════════════════════════════════

  /**
   * Verifica se o usuário já tem acesso válido
   */
  function hasValidAccess() {
    try {
      const access = sessionStorage.getItem(STORAGE_KEY);
      if (!access) return false;

      const data = JSON.parse(access);
      const now = Date.now();

      // Token válido por 8 horas
      const isValid = data.token === ADMIN_PASSWORD &&
                      data.expiresAt > now &&
                      data.verified === true;

      return isValid;
    } catch {
      return false;
    }
  }

  /**
   * Redireciona para o login do painel (app.html)
   */
  function redirectToLogin() {
    window.location.replace('/sistema/app.html#/login');
  }

  /**
   * Redireciona para a página de proteção
   */
  function redirectToProtection() {
    window.location.href = '/sistema/';
  }

  // Expõe funções globalmente para uso no app.html
  window.dipertinProtecao = {
    hasValidAccess: hasValidAccess,
    redirectToLogin: redirectToLogin,
    redirectToProtection: redirectToProtection,
  };

  // ═══════════════════════════════════════════════════════════════
  // HELPERS INTERNOS
  // ═══════════════════════════════════════════════════════════════

  /**
   * Detecta se está na página app.html (painel)
   */
  function isOnAppPage() {
    return window.location.pathname.includes('app.html');
  }

  /**
   * Salva token de acesso válido
   */
  function grantAccess() {
    const data = {
      token: ADMIN_PASSWORD,
      verified: true,
      expiresAt: Date.now() + (8 * 60 * 60 * 1000) // 8 horas
    };
    sessionStorage.setItem(STORAGE_KEY, JSON.stringify(data));
  }

  /**
   * Mostra mensagem de erro
   */
  function showError(inputId, errorId) {
    const input = document.getElementById(inputId);
    const error = document.getElementById(errorId);

    if (input) input.classList.add('error');
    if (error) {
      error.classList.add('show');
      setTimeout(function() {
        error.classList.remove('show');
      }, 3000);
    }
  }

  /**
   * Esconde mensagem de erro
   */
  function hideError(inputId, errorId) {
    const input = document.getElementById(inputId);
    const error = document.getElementById(errorId);

    if (input) input.classList.remove('error');
    if (error) error.classList.remove('show');
  }

  /**
   * Define estado de loading no botão
   */
  function setLoading(buttonId, loading) {
    const btn = document.getElementById(buttonId);
    if (!btn) return;

    if (loading) {
      btn.classList.add('loading');
      btn.disabled = true;
    } else {
      btn.classList.remove('loading');
      btn.disabled = false;
    }
  }

  /**
   * Toggle visibility da senha
   */
  function togglePasswordVisibility(inputId, buttonId) {
    const input = document.getElementById(inputId);
    const button = document.getElementById(buttonId);

    if (!input || !button) return;

    const isPassword = input.type === 'password';
    input.type = isPassword ? 'text' : 'password';
    button.classList.toggle('active', isPassword);
  }

  // ═══════════════════════════════════════════════════════════════
  // VALIDAÇÃO
  // ═══════════════════════════════════════════════════════════════

  /**
   * Valida a senha informada
   */
  function validatePassword(password) {
    if (!password || typeof password !== 'string') {
      return false;
    }

    const trimmed = password.trim();

    // Validação exata da senha
    return trimmed === ADMIN_PASSWORD;
  }

  /**
   * Processa o formulário de senha
   */
  async function processPassword(formId, inputId, errorId, buttonId) {
    if (isProcessing) return;

    const form = document.getElementById(formId);
    const input = document.getElementById(inputId);

    if (!form || !input) return;

    const password = input.value;

    // Validação básica
    if (!password) {
      showError(inputId, errorId);
      input.focus();
      return;
    }

    isProcessing = true;
    setLoading(buttonId, true);
    hideError(inputId, errorId);

    try {
      // Simula um pequeno delay para feedback visual
      await new Promise(function(resolve) {
        setTimeout(resolve, 400);
      });

      if (validatePassword(password)) {
        // Senha correta
        grantAccess();
        redirectToLogin();
      } else {
        // Senha incorreta
        showError(inputId, errorId);
        input.value = '';
        input.focus();

        // Feedback visual de erro
        const card = document.getElementById('mainCard');
        if (card) {
          card.classList.add('success-animation');
          setTimeout(function() {
            card.classList.remove('success-animation');
          }, 500);
        }
      }
    } catch (error) {
      console.error('Erro na validação:', error);
      showError(inputId, errorId);
    } finally {
      isProcessing = false;
      setLoading(buttonId, false);
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // INICIALIZAÇÃO
  // ═══════════════════════════════════════════════════════════════

  function init() {
    // Se está na página app.html, não faz nada aqui (o app.html gerencia)
    // O script é carregado no app.html apenas para expor hasValidAccess()
    if (isOnAppPage()) {
      return;
    }

    // Estamos na index.html (página de proteção)
    // Se já tem acesso válido, redireciona direto para o painel
    if (hasValidAccess()) {
      redirectToLogin();
      return;
    }

    // Desktop Form
    const desktopForm = document.getElementById('passwordForm');
    const desktopInput = document.getElementById('adminPassword');
    const desktopButton = document.getElementById('submitButton');
    const toggleBtn = document.getElementById('togglePassword');

    if (desktopForm) {
      desktopForm.addEventListener('submit', function(e) {
        e.preventDefault();
        processPassword('passwordForm', 'adminPassword', 'errorMessage', 'submitButton');
      });
    }

    if (toggleBtn) {
      toggleBtn.addEventListener('click', function() {
        togglePasswordVisibility('adminPassword', 'togglePassword');
      });
    }

    // Mobile Form
    const mobileForm = document.getElementById('passwordFormMobile');
    const mobileInput = document.getElementById('adminPasswordMobile');
    const mobileButton = document.getElementById('submitButtonMobile');

    if (mobileForm) {
      mobileForm.addEventListener('submit', function(e) {
        e.preventDefault();
        processPassword('passwordFormMobile', 'adminPasswordMobile', 'errorMessageMobile', 'submitButtonMobile');
      });
    }

    // Limpa erros ao digitar
    if (desktopInput) {
      desktopInput.addEventListener('input', function() {
        hideError('adminPassword', 'errorMessage');
      });
    }

    if (mobileInput) {
      mobileInput.addEventListener('input', function() {
        hideError('adminPasswordMobile', 'errorMessageMobile');
      });
    }

    // Tecla Enter nos inputs
    document.addEventListener('keydown', function(e) {
      if (e.key === 'Enter') {
        const activeEl = document.activeElement;

        if (activeEl && activeEl.id === 'adminPassword') {
          e.preventDefault();
          processPassword('passwordForm', 'adminPassword', 'errorMessage', 'submitButton');
        }

        if (activeEl && activeEl.id === 'adminPasswordMobile') {
          e.preventDefault();
          processPassword('passwordFormMobile', 'adminPasswordMobile', 'errorMessageMobile', 'submitButtonMobile');
        }
      }
    });

    // Adiciona classe ao body para indicar que está pronto
    document.body.classList.add('ready');
  }

  // Inicializa quando o DOM estiver pronto
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }

})();
