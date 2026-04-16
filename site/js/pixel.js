/**
 * Meta Pixel (Facebook): PageView automático + API de eventos para e-commerce.
 * Requer DIPERTIN_SITE.metaPixelId em config.js
 */
(function () {
  "use strict";

  var cfg = window.DIPERTIN_SITE || {};
  var pixelId = (cfg.metaPixelId || "").trim();
  if (!pixelId) {
    window.dipertinPixel = {
      isEnabled: false,
      pageView: function () {},
      viewContent: function () {},
      addToCart: function () {},
      initiateCheckout: function () {},
      purchase: function () {},
    };
    return;
  }

  !(function (f, b, e, v, n, t, s) {
    if (f.fbq) return;
    n = f.fbq = function () {
      n.callMethod ? n.callMethod.apply(n, arguments) : n.queue.push(arguments);
    };
    if (!f._fbq) f._fbq = n;
    n.push = n;
    n.loaded = !0;
    n.version = "2.0";
    n.queue = [];
    t = b.createElement(e);
    t.async = !0;
    t.src = "https://connect.facebook.net/en_US/fbevents.js";
    s = b.getElementsByTagName(e)[0];
    s.parentNode.insertBefore(t, s);
  })(window, document, "script");

  window.fbq("init", pixelId);
  window.fbq("track", "PageView");

  function track(eventName, params) {
    if (typeof window.fbq === "function") {
      window.fbq("track", eventName, params || {});
    }
  }

  window.dipertinPixel = {
    isEnabled: true,
    pageView: function () {
      track("PageView");
    },
    viewContent: function (data) {
      track("ViewContent", data || {});
    },
    addToCart: function (data) {
      track("AddToCart", data || {});
    },
    initiateCheckout: function (data) {
      track("InitiateCheckout", data || {});
    },
    purchase: function (data) {
      track("Purchase", data || {});
    },
  };
})();
