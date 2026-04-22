/**
 * Formulário público de solicitação de exclusão de conta DiPertin.
 *
 * Reaproveita a Cloud Function `enviarContatoSite` (já em produção) com
 * assunto fixo "Solicitação de exclusão de conta" para que o e-mail caia
 * no mesmo destino do contato e seja triado pela equipe.
 *
 * O telefone é incluído no corpo da mensagem porque a CF atual não tem
 * campo dedicado — assim evitamos qualquer alteração no backend.
 */
(function () {
  "use strict";

  var cfg = (window.DIPERTIN_SITE && typeof window.DIPERTIN_SITE === "object") ? window.DIPERTIN_SITE : {};
  var formEndpoint = typeof cfg.formEndpoint === "string" ? cfg.formEndpoint.trim() : "";

  var form = document.querySelector("[data-delete-form]");
  if (!form || !formEndpoint) return;

  var submitBtn = form.querySelector("[data-delete-submit]");
  var submitLabel = form.querySelector("[data-submit-label]");
  var submitSpinner = form.querySelector("[data-submit-spinner]");
  var successEl = form.querySelector("[data-form-success]");
  var errorEl = form.querySelector("[data-form-error]");

  var lastSubmitAt = 0;
  var COOLDOWN_MS = 10000;

  function setLoading(on) {
    if (submitBtn) submitBtn.disabled = on;
    if (submitLabel) submitLabel.textContent = on ? "Enviando…" : "Enviar solicitação de exclusão";
    if (submitSpinner) submitSpinner.hidden = !on;
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
    Array.prototype.forEach.call(form.querySelectorAll(".form__error"), function (el) { el.textContent = ""; });
    Array.prototype.forEach.call(form.querySelectorAll(".form__field--invalid"), function (el) { el.classList.remove("form__field--invalid"); });
    if (errorEl) { errorEl.hidden = true; errorEl.textContent = ""; }
  }

  function sanitize(v, max) {
    var s = (v == null ? "" : String(v)).replace(/\s+/g, " ").trim();
    if (max && s.length > max) s = s.slice(0, max);
    return s;
  }

  function validate() {
    clearErrors();
    var ok = true;

    var nome = document.getElementById("del-nome");
    var email = document.getElementById("del-email");
    var tel = document.getElementById("del-telefone");
    var msg = document.getElementById("del-mensagem");
    var confirmo = document.getElementById("del-confirmo");
    var lgpd = document.getElementById("del-lgpd");
    var hp = document.getElementById("del-website");

    if (hp && hp.value.trim()) return false;

    if (!nome || sanitize(nome.value).length < 2) {
      setFieldError("del-nome", "Informe seu nome completo (mínimo 2 caracteres).");
      ok = false;
    }

    var emailRe = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    if (!email || !emailRe.test(sanitize(email.value))) {
      setFieldError("del-email", "Informe um e-mail válido (o mesmo usado no app).");
      ok = false;
    }

    var telDigits = (tel ? tel.value : "").replace(/\D+/g, "");
    if (telDigits.length < 10 || telDigits.length > 13) {
      setFieldError("del-telefone", "Informe um telefone válido com DDD.");
      ok = false;
    }

    if (!msg || sanitize(msg.value).length < 10) {
      setFieldError("del-mensagem", "Descreva brevemente o motivo (mínimo 10 caracteres).");
      ok = false;
    }

    if (!confirmo || !confirmo.checked) {
      setFieldError("del-confirmo", "Confirme que você é o titular da conta.");
      ok = false;
    }

    if (!lgpd || !lgpd.checked) {
      setFieldError("del-lgpd", "Aceite o tratamento dos dados desta solicitação.");
      ok = false;
    }

    return ok;
  }

  form.addEventListener("submit", function (ev) {
    ev.preventDefault();
    if (successEl) successEl.hidden = true;
    if (!validate()) return;

    var agora = Date.now();
    if (agora - lastSubmitAt < COOLDOWN_MS) {
      if (errorEl) {
        var seg = Math.ceil((COOLDOWN_MS - (agora - lastSubmitAt)) / 1000);
        errorEl.textContent = "Aguarde " + seg + " s antes de reenviar.";
        errorEl.hidden = false;
      }
      return;
    }

    var nome = sanitize(document.getElementById("del-nome").value, 120);
    var email = sanitize(document.getElementById("del-email").value, 120);
    var telefone = sanitize(document.getElementById("del-telefone").value, 30);
    var motivo = sanitize(document.getElementById("del-mensagem").value, 2000);

    var corpoMensagem = [
      "==== SOLICITAÇÃO DE EXCLUSÃO DE CONTA ====",
      "",
      "Telefone: " + telefone,
      "",
      "Motivo informado pelo usuário:",
      motivo,
      "",
      "----",
      "Este pedido foi enviado pelo formulário público em",
      "https://www.dipertin.com.br/excluir-conta.html",
      "Processar em até 30 dias conforme a LGPD."
    ].join("\n");

    var payload = {
      nome: nome,
      email: email,
      assunto: "Solicitação de exclusão de conta — " + nome,
      mensagem: corpoMensagem,
      website: ""
    };

    setLoading(true);

    fetch(formEndpoint, {
      method: "POST",
      body: JSON.stringify(payload),
      headers: { "Content-Type": "application/json", Accept: "application/json" }
    })
      .then(function (r) {
        if (!r.ok) {
          return r.json().then(function (j) {
            throw new Error((j && j.error) || ("Erro " + r.status));
          }).catch(function () {
            throw new Error("Erro " + r.status);
          });
        }
        return r.json().catch(function () { return {}; });
      })
      .then(function () {
        lastSubmitAt = Date.now();
        form.reset();
        if (successEl) {
          successEl.textContent = "Solicitação recebida! Você receberá uma confirmação por e-mail em breve. O processamento da exclusão ocorre em até 30 dias.";
          successEl.hidden = false;
          successEl.scrollIntoView({ behavior: "smooth", block: "center" });
        }
      })
      .catch(function (err) {
        var m = (err && err.message) || "";
        if (m === "Failed to fetch" || m.indexOf("NetworkError") !== -1) {
          m = "Servidor indisponível. Verifique sua conexão ou tente novamente em instantes.";
        }
        if (errorEl) {
          errorEl.textContent = m || "Não foi possível enviar a solicitação. Tente novamente.";
          errorEl.hidden = false;
        }
      })
      .then(function () { setLoading(false); });
  });
})();
