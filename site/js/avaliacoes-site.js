/**
 * Depoimentos: GET na Cloud Function (Admin SDK — não depende de App Check no browser).
 */
(function () {
  "use strict";

  var MSG_VAZIO =
    "Ainda não há avaliações de 4 ou 5 estrelas no app para exibir aqui. Quando os clientes avaliarem após a entrega, os depoimentos aparecem automaticamente.";
  var MSG_ERRO =
    "Não foi possível carregar as avaliações agora. Atualize a página ou tente mais tarde.";

  function inicialNome(nome) {
    if (!nome || typeof nome !== "string") return "C";
    var t = nome.trim();
    if (!t) return "C";
    return t.charAt(0).toUpperCase();
  }

  function labelExibicao(nome) {
    if (!nome || typeof nome !== "string") return "Cliente";
    var p = nome.trim().split(/\s+/);
    if (p.length <= 1) return p[0] || "Cliente";
    return p[0] + " " + p[p.length - 1].charAt(0) + ".";
  }

  function estrelasHtml(nota) {
    var n = parseInt(nota, 10);
    if (isNaN(n) || n < 1) n = 5;
    if (n > 5) n = 5;
    var out = "";
    for (var i = 0; i < 5; i++) {
      out += i < n ? "&#9733;" : "&#9734;";
    }
    return out;
  }

  function montarCard(item) {
    var comentario = String(item.comentario || "").trim();
    var nome = String(item.cliente_nome_exibicao || "").trim();
    var nota = parseInt(item.nota, 10);
    if (isNaN(nota) || nota < 1) nota = 5;
    if (nota > 5) nota = 5;
    var ariaEstrelas = nota + " de 5 estrelas";
    var fotoUrl = String(item.cliente_foto_url || "").trim();

    var fig = document.createElement("figure");
    fig.className = "testimonial";

    var bq = document.createElement("blockquote");
    var pq = document.createElement("p");
    pq.textContent = "\u201c" + comentario + "\u201d";
    bq.appendChild(pq);
    fig.appendChild(bq);

    var cap = document.createElement("figcaption");

    var av = document.createElement("div");
    av.className = "testimonial__avatar";
    av.setAttribute("aria-hidden", "true");
    if (/^https:\/\//i.test(fotoUrl)) {
      var img = document.createElement("img");
      img.src = fotoUrl;
      img.alt = "";
      img.loading = "lazy";
      img.decoding = "async";
      img.referrerPolicy = "no-referrer-when-downgrade";
      img.addEventListener("error", function onImgErr() {
        img.removeEventListener("error", onImgErr);
        av.textContent = "";
        av.appendChild(document.createTextNode(inicialNome(nome)));
      });
      av.appendChild(img);
    } else {
      av.textContent = inicialNome(nome);
    }
    cap.appendChild(av);

    var info = document.createElement("div");
    info.className = "testimonial__info";
    var strong = document.createElement("strong");
    strong.textContent = labelExibicao(nome);
    var span = document.createElement("span");
    span.className = "testimonial__stars";
    span.setAttribute("aria-label", ariaEstrelas);
    span.innerHTML = estrelasHtml(nota);
    info.appendChild(strong);
    info.appendChild(span);
    cap.appendChild(info);
    fig.appendChild(cap);

    return fig;
  }

  function mostrarVazio(vazioEl, root, mensagem) {
    if (root) root.innerHTML = "";
    if (vazioEl) {
      vazioEl.textContent = mensagem;
      vazioEl.hidden = false;
    }
  }

  function init() {
    var root = document.querySelector("[data-depoimentos-root]");
    var statusEl = document.querySelector("[data-depoimentos-status]");
    var vazioEl = document.querySelector("[data-depoimentos-vazio]");
    var cfg = window.DIPERTIN_SITE || {};
    var url = cfg.avaliacoesSiteUrl;

    if (!root) return;

    function esconderStatus() {
      if (statusEl) statusEl.hidden = true;
    }

    function esconderVazio() {
      if (vazioEl) vazioEl.hidden = true;
    }

    if (!url || typeof url !== "string") {
      esconderStatus();
      mostrarVazio(vazioEl, root, MSG_ERRO);
      return;
    }

    var u = url + (url.indexOf("?") >= 0 ? "&" : "?") + "t=" + Date.now();

    fetch(u, { method: "GET", credentials: "omit", cache: "no-store" })
      .then(function (r) {
        if (!r.ok) throw new Error("http");
        return r.json();
      })
      .then(function (data) {
        esconderStatus();
        if (!data || !data.ok || !Array.isArray(data.avaliacoes)) {
          mostrarVazio(vazioEl, root, MSG_ERRO);
          return;
        }
        if (data.avaliacoes.length === 0) {
          mostrarVazio(vazioEl, root, MSG_VAZIO);
          return;
        }
        esconderVazio();
        root.innerHTML = "";
        data.avaliacoes.forEach(function (item) {
          root.appendChild(montarCard(item));
        });
      })
      .catch(function () {
        esconderStatus();
        mostrarVazio(vazioEl, root, MSG_ERRO);
      });
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})();
