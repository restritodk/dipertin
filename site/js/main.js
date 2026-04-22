/**
 * DiPertin — site: navegação, reveal, FAQ, contato (Cloud Function SMTP)
 */
(function () {
  "use strict";

  var SUBMIT_COOLDOWN_MS = 10000;
  var lastSubmitAt = 0;

  function stripControlChars(s, allowNewlines) {
    if (!s || typeof s !== "string") return "";
    var re = allowNewlines ? /[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/g : /[\x00-\x1F\x7F]/g;
    return s.replace(re, "");
  }
  function stripHtml(s) { return s.replace(/[<>]/g, ""); }
  function sanitizeNome(s) { return stripControlChars(s, false).trim().slice(0, 120); }
  function sanitizeEmail(s) { return stripControlChars(s, false).trim().slice(0, 120); }
  function sanitizeAssunto(s) { return stripControlChars(s, false).trim().slice(0, 200); }
  function sanitizeMensagem(s) { return stripHtml(stripControlChars(s, true)).trim().slice(0, 4000); }

  var cfg = window.DIPERTIN_SITE || {};
  var nav = document.querySelector("[data-nav]");
  var toggle = document.querySelector("[data-nav-toggle]");
  var header = document.querySelector("[data-header]");
  var headerScrollTarget = header && (header.closest(".site-header") || header);

  function setNavOpen(open) {
    if (!nav || !toggle) return;
    nav.classList.toggle("is-open", open);
    toggle.setAttribute("aria-expanded", open ? "true" : "false");
    document.body.classList.toggle("nav-open", open);
  }

  if (toggle && nav) {
    toggle.addEventListener("click", function (e) {
      e.preventDefault();
      setNavOpen(!nav.classList.contains("is-open"));
    });
    nav.querySelectorAll('a[href^="#"]').forEach(function (link) {
      link.addEventListener("click", function () { setNavOpen(false); });
    });
  }

  var loginNav = document.querySelector("[data-login-nav]");
  if (loginNav) {
    var loginUrl = typeof cfg.loginPainelUrl === "string" ? cfg.loginPainelUrl.trim() : "";
    if (loginUrl) {
      loginNav.href = loginUrl;
      loginNav.setAttribute("target", "_self");
      loginNav.removeAttribute("rel");
      loginNav.removeAttribute("title");
      loginNav.addEventListener("click", function (e) {
        e.preventDefault();
        setNavOpen(false);
        window.location.assign(loginUrl);
      });
    } else {
      loginNav.addEventListener("click", function (e) {
        e.preventDefault();
        setNavOpen(false);
      });
    }
  }

  document.addEventListener("keydown", function (e) {
    if (e.key === "Escape") setNavOpen(false);
  });

  if (headerScrollTarget) {
    window.addEventListener("scroll", function () {
      headerScrollTarget.style.boxShadow = window.scrollY > 10 ? "0 1px 16px rgba(0,0,0,.06)" : "none";
    }, { passive: true });
  }

  var yearEl = document.querySelector("[data-year]");
  if (yearEl) yearEl.textContent = String(new Date().getFullYear());

  function wireStoreLink(selector, cfgKey) {
    var el = document.querySelector(selector);
    if (!el) return;
    var url = typeof cfg[cfgKey] === "string" ? cfg[cfgKey].trim() : "";
    if (url) {
      el.href = url;
      el.removeAttribute("data-placeholder-store");
      el.setAttribute("target", "_blank");
      el.setAttribute("rel", "noopener noreferrer");
    } else {
      el.addEventListener("click", function (e) { e.preventDefault(); });
    }
  }
  wireStoreLink("[data-store-google]", "googlePlayUrl");
  wireStoreLink("[data-store-apple]", "appStoreUrl");

  /* ── Reveal on scroll ───────────────────────────────────────── */
  var reveals = document.querySelectorAll(".reveal");
  if (reveals.length && "IntersectionObserver" in window) {
    var obs = new IntersectionObserver(function (entries) {
      entries.forEach(function (entry) {
        if (entry.isIntersecting) {
          entry.target.classList.add("is-visible");
          obs.unobserve(entry.target);
        }
      });
    }, { threshold: 0.1 });
    reveals.forEach(function (el) { obs.observe(el); });
  } else {
    reveals.forEach(function (el) { el.classList.add("is-visible"); });
  }

  /* ── Nav active on scroll ────────────────────────────────────── */
  var navLinks = document.querySelectorAll('.nav a[href^="#"]');
  var sections = [];
  navLinks.forEach(function (link) {
    var id = link.getAttribute("href").slice(1);
    var sec = document.getElementById(id);
    if (sec) sections.push({ el: sec, link: link });
  });

  if (sections.length && "IntersectionObserver" in window) {
    var navObs = new IntersectionObserver(function (entries) {
      entries.forEach(function (entry) {
        var match = sections.find(function (s) { return s.el === entry.target; });
        if (match) match.link.classList.toggle("is-active", entry.isIntersecting);
      });
    }, { rootMargin: "-40% 0px -55% 0px" });
    sections.forEach(function (s) { navObs.observe(s.el); });
  }

  /* ── Contact ────────────────────────────────────────────────── */
  var destEmail = typeof cfg.emailContato === "string" ? cfg.emailContato.trim() : "";
  var formEndpoint = typeof cfg.formEndpoint === "string" ? cfg.formEndpoint.trim() : "";

  // Atualiza apenas o display do e-mail principal vindo do config (não sobrescreve telefone)
  var emailDisplay = document.querySelector("[data-copy-email] [data-contact-email-display]");
  if (emailDisplay && destEmail) {
    emailDisplay.textContent = destEmail;
    var emailBtn = emailDisplay.closest("[data-copy-email]");
    if (emailBtn) emailBtn.setAttribute("data-copy-text", destEmail);
  }

  /* Suporta N botões de copiar: cada botão usa seu próprio data-copy-text
     e exibe feedback no <p data-copy-feedback> irmão (mesmo wrap). */
  function copiarTexto(texto) {
    if (!texto) return Promise.reject(new Error("vazio"));
    if (navigator.clipboard && navigator.clipboard.writeText && window.isSecureContext) {
      return navigator.clipboard.writeText(texto);
    }
    return new Promise(function (resolve, reject) {
      try {
        var ta = document.createElement("textarea");
        ta.value = texto;
        ta.setAttribute("readonly", "");
        ta.style.position = "fixed";
        ta.style.left = "-9999px";
        ta.style.top = "0";
        document.body.appendChild(ta);
        ta.focus();
        ta.select();
        ta.setSelectionRange(0, ta.value.length);
        var ok = document.execCommand && document.execCommand("copy");
        document.body.removeChild(ta);
        ok ? resolve() : reject(new Error("execCommand falhou"));
      } catch (e) { reject(e); }
    });
  }

  function bindCopyBtn(btn) {
    btn.addEventListener("click", function () {
      var texto = btn.getAttribute("data-copy-text");
      if (!texto) {
        var span = btn.querySelector("span:not(.contact__copy-hint):not(.contact__copy-ok)");
        if (span) texto = (span.textContent || "").trim();
      }
      if (!texto) return;

      var wrap = btn.closest(".contact__email-wrap") || btn.parentElement;
      var feedback = wrap ? wrap.querySelector("[data-copy-feedback]") : null;

      copiarTexto(texto).then(function () {
        if (feedback) {
          feedback.hidden = false;
          clearTimeout(btn.__copyTimer);
          btn.__copyTimer = setTimeout(function () { feedback.hidden = true; }, 2500);
        }
      }).catch(function () {
        try { window.prompt("Copie manualmente:", texto); } catch (_) {}
      });
    });
  }

  var copyButtons = document.querySelectorAll("[data-copy-text], [data-copy-email]");
  Array.prototype.forEach.call(copyButtons, bindCopyBtn);

  var form = document.querySelector("[data-contact-form]");
  if (form && (destEmail || formEndpoint)) {

  var submitBtn = form.querySelector("[data-contact-submit]");
  var submitLabel = form.querySelector("[data-submit-label]");
  var submitSpinner = form.querySelector("[data-submit-spinner]");
  var successEl = form.querySelector("[data-form-success]");
  var errorEl = form.querySelector("[data-form-error]");

  function setLoading(on) {
    if (submitBtn) submitBtn.disabled = on;
    if (submitSpinner) submitSpinner.hidden = !on;
    if (submitLabel) submitLabel.textContent = on ? "Enviando…" : "Enviar mensagem";
  }

  function setFieldError(id, msg) {
    var el = form.querySelector('[data-error-for="' + id + '"]');
    var input = document.getElementById(id);
    if (el) el.textContent = msg || "";
    if (input) {
      var w = input.closest(".form__field");
      if (w) w.classList.toggle("form__field--invalid", !!msg);
    }
  }

  function clearErrors() {
    form.querySelectorAll(".form__error").forEach(function (el) { el.textContent = ""; });
    form.querySelectorAll(".form__field--invalid").forEach(function (el) { el.classList.remove("form__field--invalid"); });
    if (errorEl) { errorEl.hidden = true; errorEl.textContent = ""; }
  }

  function validate() {
    clearErrors();
    var ok = true;
    var n = document.getElementById("contato-nome");
    var e = document.getElementById("contato-email");
    var a = document.getElementById("contato-assunto");
    var m = document.getElementById("contato-mensagem");
    var p = document.getElementById("contato-privacidade");
    var hp = document.getElementById("contato-website");

    if (hp && hp.value.trim()) return false;

    if (!n || sanitizeNome(n.value).length < 2) { setFieldError("contato-nome", "Informe seu nome (mínimo 2 caracteres)."); ok = false; }
    if (e && (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(sanitizeEmail(e.value)))) { setFieldError("contato-email", "Informe um e-mail válido."); ok = false; }
    if (!a || !sanitizeAssunto(a.value)) { setFieldError("contato-assunto", "Selecione um assunto."); ok = false; }
    if (!m || sanitizeMensagem(m.value).length < 10) { setFieldError("contato-mensagem", "Escreva uma mensagem (mínimo 10 caracteres)."); ok = false; }
    if (!p || !p.checked) { setFieldError("contato-privacidade", "Aceite o tratamento dos dados para continuar."); ok = false; }
    return ok;
  }

  form.addEventListener("submit", function (ev) {
    ev.preventDefault();
    if (successEl) successEl.hidden = true;
    if (!validate()) return;

    var now = Date.now();
    if (now - lastSubmitAt < SUBMIT_COOLDOWN_MS) {
      if (errorEl) { errorEl.textContent = "Aguarde alguns segundos antes de enviar novamente."; errorEl.hidden = false; }
      return;
    }

    setLoading(true);

    var payload = {
      nome: sanitizeNome(document.getElementById("contato-nome").value),
      email: sanitizeEmail(document.getElementById("contato-email").value),
      assunto: sanitizeAssunto(document.getElementById("contato-assunto").value),
      mensagem: sanitizeMensagem(document.getElementById("contato-mensagem").value),
      website: "",
      lat: null,
      lng: null
    };

    function enviar() {
      fetch(formEndpoint, {
        method: "POST",
        body: JSON.stringify(payload),
        headers: { "Content-Type": "application/json", Accept: "application/json" },
        mode: "cors",
        credentials: "omit",
        referrerPolicy: "strict-origin-when-cross-origin"
      })
        .then(function (r) {
          if (!r.ok) return r.json().then(function (d) { throw new Error(d.error || "Erro " + r.status); });
          return r.json();
        })
        .then(function () {
          lastSubmitAt = Date.now();
          form.reset();
          if (successEl) { successEl.textContent = "Mensagem enviada com sucesso! Responderemos em breve."; successEl.hidden = false; }
        })
        .catch(function (err) {
          var msg = err.message || "";
          if (msg === "Failed to fetch" || msg.indexOf("NetworkError") !== -1) {
            msg = "Servidor indisponível. Verifique sua conexão ou tente novamente em instantes.";
          }
          if (errorEl) { errorEl.textContent = msg || "Não foi possível enviar. Tente novamente."; errorEl.hidden = false; }
        })
        .finally(function () { setLoading(false); });
    }

    if (navigator.geolocation) {
      navigator.geolocation.getCurrentPosition(
        function (pos) { payload.lat = pos.coords.latitude; payload.lng = pos.coords.longitude; enviar(); },
        function () { enviar(); },
        { timeout: 5000, maximumAge: 60000 }
      );
    } else {
      enviar();
    }
    return;
  });

  ["contato-nome", "contato-email", "contato-assunto", "contato-mensagem", "contato-privacidade"].forEach(function (id) {
    var el = document.getElementById(id);
    if (el) {
      el.addEventListener("input", function () { setFieldError(id, ""); });
      el.addEventListener("change", function () { setFieldError(id, ""); });
    }
  });
  }
})();
