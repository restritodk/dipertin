/**
 * Depoimentos: GET na Cloud Function (Admin SDK — não depende de App Check no browser).
 * Carrossel profissional baseado em transform translateX (sem scrollLeft/snap),
 * com setas, dots, autoplay (pausa em hover/touch/aba oculta), swipe touch e teclado.
 */
(function () {
  "use strict";

  var MSG_VAZIO =
    "Ainda não há avaliações de 4 ou 5 estrelas no app para exibir aqui. Quando os clientes avaliarem após a entrega, os depoimentos aparecem automaticamente.";
  var MSG_ERRO =
    "Não foi possível carregar as avaliações agora. Atualize a página ou tente mais tarde.";

  var AUTOPLAY_MS = 5000;

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
    fig.className = "review-card";
    fig.setAttribute("role", "listitem");

    var quoteIcon = document.createElement("span");
    quoteIcon.className = "review-card__quote";
    quoteIcon.setAttribute("aria-hidden", "true");
    quoteIcon.textContent = "\u201C";
    fig.appendChild(quoteIcon);

    var bq = document.createElement("blockquote");
    bq.className = "review-card__body";
    var pq = document.createElement("p");
    pq.textContent = comentario;
    bq.appendChild(pq);
    fig.appendChild(bq);

    var cap = document.createElement("figcaption");
    cap.className = "review-card__author";

    var av = document.createElement("div");
    av.className = "review-card__avatar";
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
    info.className = "review-card__info";
    var strong = document.createElement("strong");
    strong.textContent = labelExibicao(nome);
    var span = document.createElement("span");
    span.className = "review-card__stars";
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

  /**
   * Carrossel via transform translateX. Cada "página" mostra N cards
   * (calculado a partir da largura do card). Avanço/retrocesso atualiza
   * estado interno e aplica translate3d no track com transition CSS.
   */
  function iniciarCarrossel(refs) {
    var carousel = refs.carousel;
    var viewport = refs.viewport;
    var track = refs.track;
    var prevBtn = refs.prevBtn;
    var nextBtn = refs.nextBtn;
    var dotsEl = refs.dotsEl;

    if (!carousel || !viewport || !track) return;

    var cards = Array.prototype.slice.call(track.children);
    if (cards.length === 0) return;

    carousel.hidden = false;

    // Garante que o viewport NÃO scrolla — movimento é via transform.
    viewport.style.overflow = "hidden";
    viewport.style.touchAction = "pan-y"; // permite scroll vertical da página
    track.style.willChange = "transform";
    track.style.transition = "transform .55s cubic-bezier(.22,.61,.36,1)";

    var paginaIndex = 0;
    var arrastando = false;
    var touchStartX = 0;
    var touchDeltaX = 0;
    var translateAtual = 0;

    function gapTrack() {
      var cs = window.getComputedStyle(track);
      var raw = cs.columnGap;
      if (!raw || raw === "normal") raw = cs.gap;
      var g = parseFloat(raw || "0");
      return isNaN(g) ? 0 : g;
    }

    function passoCard() {
      var first = cards[0];
      if (!first) return 0;
      return first.getBoundingClientRect().width + gapTrack();
    }

    function cardsPorPagina() {
      var p = passoCard();
      if (p <= 0) return 1;
      var n = Math.round(viewport.clientWidth / p);
      return Math.max(1, n);
    }

    function totalPaginas() {
      return Math.max(1, Math.ceil(cards.length / cardsPorPagina()));
    }

    function maxTranslate() {
      // Máximo translate (em pixels positivos) = todos os cards — viewport
      var totalLargura = passoCard() * cards.length - gapTrack();
      var max = totalLargura - viewport.clientWidth;
      return max > 0 ? max : 0;
    }

    function aplicarTranslate(px, comTransicao) {
      translateAtual = px;
      if (!comTransicao) {
        var prev = track.style.transition;
        track.style.transition = "none";
        track.style.transform = "translate3d(" + (-px) + "px,0,0)";
        // força reflow para re-habilitar transição depois
        // eslint-disable-next-line no-unused-expressions
        track.offsetHeight;
        track.style.transition = prev;
      } else {
        track.style.transform = "translate3d(" + (-px) + "px,0,0)";
      }
    }

    function irParaPagina(p) {
      var total = totalPaginas();
      if (total <= 0) return;
      if (p < 0) p = total - 1;
      if (p >= total) p = 0;
      paginaIndex = p;

      var passo = passoCard();
      var perPage = cardsPorPagina();
      var px = p * perPage * passo;
      var max = maxTranslate();
      if (px > max) px = max;
      if (px < 0) px = 0;

      aplicarTranslate(px, true);
      atualizarDotAtivo();
    }

    function renderDots() {
      if (!dotsEl) return;
      dotsEl.innerHTML = "";
      var total = totalPaginas();
      for (var i = 0; i < total; i++) {
        var b = document.createElement("button");
        b.type = "button";
        b.className = "depoimentos-carousel__dot";
        b.setAttribute("role", "tab");
        b.setAttribute("aria-label", "Ir para página " + (i + 1) + " de " + total);
        (function (idx) {
          b.addEventListener("click", function () {
            interromperAutoplayPorInteracao();
            irParaPagina(idx);
          });
        })(i);
        dotsEl.appendChild(b);
      }
      atualizarDotAtivo();
    }

    function atualizarDotAtivo() {
      if (!dotsEl) return;
      var dots = dotsEl.children;
      for (var i = 0; i < dots.length; i++) {
        if (i === paginaIndex) {
          dots[i].classList.add("is-active");
          dots[i].setAttribute("aria-selected", "true");
        } else {
          dots[i].classList.remove("is-active");
          dots[i].setAttribute("aria-selected", "false");
        }
      }
    }

    /* ── Botões ──────────────────────────────────────────────── */
    if (prevBtn) {
      prevBtn.addEventListener("click", function (e) {
        e.preventDefault();
        interromperAutoplayPorInteracao();
        irParaPagina(paginaIndex - 1);
      });
    }
    if (nextBtn) {
      nextBtn.addEventListener("click", function (e) {
        e.preventDefault();
        interromperAutoplayPorInteracao();
        irParaPagina(paginaIndex + 1);
      });
    }

    /* ── Touch swipe ─────────────────────────────────────────── */
    viewport.addEventListener("touchstart", function (e) {
      if (!e.touches || !e.touches.length) return;
      arrastando = true;
      touchStartX = e.touches[0].clientX;
      touchDeltaX = 0;
      pausadoTouch = true;
      pararAutoplay();
      track.style.transition = "none";
    }, { passive: true });

    viewport.addEventListener("touchmove", function (e) {
      if (!arrastando || !e.touches || !e.touches.length) return;
      touchDeltaX = e.touches[0].clientX - touchStartX;
      track.style.transform = "translate3d(" + (-(translateAtual - touchDeltaX)) + "px,0,0)";
    }, { passive: true });

    viewport.addEventListener("touchend", function () {
      if (!arrastando) return;
      arrastando = false;
      track.style.transition = "transform .55s cubic-bezier(.22,.61,.36,1)";
      var limite = viewport.clientWidth * 0.18; // ~18% para considerar swipe
      if (touchDeltaX > limite) {
        irParaPagina(paginaIndex - 1);
      } else if (touchDeltaX < -limite) {
        irParaPagina(paginaIndex + 1);
      } else {
        aplicarTranslate(translateAtual, true); // volta para posição corrente
      }
      setTimeout(function () { pausadoTouch = false; iniciarAutoplay(); }, 1200);
    }, { passive: true });

    /* ── Resize: recalcula posição ───────────────────────────── */
    var resizeDebounce;
    window.addEventListener("resize", function () {
      window.clearTimeout(resizeDebounce);
      resizeDebounce = window.setTimeout(function () {
        renderDots();
        irParaPagina(paginaIndex); // re-aplica transform com tamanho novo
      }, 150);
    });

    /* ── Teclado (carousel focado) ───────────────────────────── */
    carousel.setAttribute("tabindex", "0");
    carousel.addEventListener("keydown", function (e) {
      if (e.key === "ArrowLeft") {
        e.preventDefault(); interromperAutoplayPorInteracao(); irParaPagina(paginaIndex - 1);
      } else if (e.key === "ArrowRight") {
        e.preventDefault(); interromperAutoplayPorInteracao(); irParaPagina(paginaIndex + 1);
      }
    });

    /* ── Autoplay ────────────────────────────────────────────── */
    var reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    var autoplayId = null;
    var pausadoHover = false;
    var pausadoTouch = false;
    var pausadoVisib = false;
    var retomadaTimer = null;

    function podeRodar() {
      return !reduceMotion && !pausadoHover && !pausadoTouch && !pausadoVisib && totalPaginas() > 1;
    }

    function pararAutoplay() {
      if (autoplayId) { clearInterval(autoplayId); autoplayId = null; }
    }

    function iniciarAutoplay() {
      pararAutoplay();
      if (!podeRodar()) return;
      autoplayId = setInterval(function () {
        irParaPagina(paginaIndex + 1);
      }, AUTOPLAY_MS);
    }

    function interromperAutoplayPorInteracao() {
      pararAutoplay();
      if (retomadaTimer) clearTimeout(retomadaTimer);
      retomadaTimer = setTimeout(iniciarAutoplay, AUTOPLAY_MS + 1500);
    }

    carousel.addEventListener("mouseenter", function () { pausadoHover = true; pararAutoplay(); });
    carousel.addEventListener("mouseleave", function () { pausadoHover = false; iniciarAutoplay(); });
    carousel.addEventListener("focusin", function () { pausadoHover = true; pararAutoplay(); });
    carousel.addEventListener("focusout", function () { pausadoHover = false; iniciarAutoplay(); });

    document.addEventListener("visibilitychange", function () {
      pausadoVisib = document.hidden;
      if (pausadoVisib) pararAutoplay();
      else iniciarAutoplay();
    });

    /* ── Boot: aguarda layout estabilizar e inicia ──────────── */
    function bootCarrossel() {
      renderDots();
      aplicarTranslate(0, false);
      iniciarAutoplay();
    }

    // Espera fonts carregarem para medir cards corretamente
    if (document.fonts && document.fonts.ready) {
      document.fonts.ready.then(bootCarrossel).catch(bootCarrossel);
    } else {
      setTimeout(bootCarrossel, 200);
    }

    // Backup: se por algum motivo as métricas zeraram no boot,
    // reinicializa após 800ms.
    setTimeout(function () {
      if (passoCard() > 0 && totalPaginas() > 1 && !autoplayId && !pausadoHover && !pausadoTouch) {
        renderDots();
        iniciarAutoplay();
      }
    }, 800);
  }

  function init() {
    var root = document.querySelector("[data-depoimentos-root]");
    var statusEl = document.querySelector("[data-depoimentos-status]");
    var vazioEl = document.querySelector("[data-depoimentos-vazio]");
    var carousel = document.querySelector("[data-depoimentos-carousel]");
    var viewport = document.querySelector("[data-depoimentos-viewport]");
    var prevBtn = document.querySelector("[data-depoimentos-prev]");
    var nextBtn = document.querySelector("[data-depoimentos-next]");
    var dotsEl = document.querySelector("[data-depoimentos-dots]");
    var cfg = window.DIPERTIN_SITE || {};
    var url = cfg.avaliacoesSiteUrl;

    if (!root) return;

    function esconderStatus() { if (statusEl) statusEl.hidden = true; }
    function esconderVazio() { if (vazioEl) vazioEl.hidden = true; }

    if (!url || typeof url !== "string") {
      esconderStatus();
      if (carousel) carousel.hidden = true;
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
          if (carousel) carousel.hidden = true;
          mostrarVazio(vazioEl, root, MSG_ERRO);
          return;
        }
        if (data.avaliacoes.length === 0) {
          if (carousel) carousel.hidden = true;
          mostrarVazio(vazioEl, root, MSG_VAZIO);
          return;
        }
        esconderVazio();
        root.innerHTML = "";
        data.avaliacoes.forEach(function (item) {
          root.appendChild(montarCard(item));
        });
        iniciarCarrossel({
          carousel: carousel,
          viewport: viewport,
          track: root,
          prevBtn: prevBtn,
          nextBtn: nextBtn,
          dotsEl: dotsEl
        });
      })
      .catch(function () {
        esconderStatus();
        if (carousel) carousel.hidden = true;
        mostrarVazio(vazioEl, root, MSG_ERRO);
      });
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})();
