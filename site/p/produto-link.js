(function () {
  var ANDROID_PACKAGE = 'com.dipertin.app';
  var PLAY_BASE = 'https://play.google.com/store/apps/details?id=' + ANDROID_PACKAGE;
  var APP_STORE_URL = ''; // preencher quando houver versão iOS publicada
  var SITE = 'https://www.dipertin.com.br/';

  function getProdutoId() {
    var params = new URLSearchParams(window.location.search);
    var id = params.get('produto') || params.get('id') || params.get('produto_id');
    if (id) return id.trim();
    // Caminho /p/{id}
    var partes = window.location.pathname.split('/').filter(Boolean);
    var idx = partes.indexOf('p');
    if (idx >= 0 && partes[idx + 1]) return decodeURIComponent(partes[idx + 1]).trim();
    return '';
  }

  var produtoId = getProdutoId();
  document.getElementById('pid').textContent = produtoId || 'não informado';

  var ua = navigator.userAgent || '';
  var isAndroid = /android/i.test(ua);
  var isIOS = /iphone|ipad|ipod/i.test(ua);

  // Link da loja com referrer (deferred deep link: app captura após instalar).
  var referrer = encodeURIComponent('produto=' + produtoId);
  var playUrl = PLAY_BASE + '&referrer=' + referrer;
  var lojaUrl = isIOS ? (APP_STORE_URL || SITE) : playUrl;
  document.getElementById('btnLoja').href = lojaUrl;

  // Esquema interno do app.
  var appScheme = 'dipertin://produto?id=' + encodeURIComponent(produtoId);

  // Android: intent:// abre o app e cai na loja se não instalado.
  var androidIntent =
    'intent://produto?id=' + encodeURIComponent(produtoId) +
    '#Intent;scheme=dipertin;package=' + ANDROID_PACKAGE +
    ';S.browser_fallback_url=' + encodeURIComponent(playUrl) + ';end';

  var abrirAppUrl = isAndroid ? androidIntent : appScheme;
  document.getElementById('btnApp').href = abrirAppUrl;

  if (!produtoId) {
    document.getElementById('spin').style.display = 'none';
    document.getElementById('titulo').textContent = 'Link inválido';
    document.getElementById('msg').textContent = 'Não foi possível identificar o produto. Baixe o app para explorar.';
    return;
  }

  // Tenta abrir o app automaticamente.
  function tentarAbrirApp() {
    if (isAndroid) {
      window.location.href = androidIntent;
      return;
    }
    // iOS / outros: tenta o esquema; se falhar, vai para a loja após timeout.
    var iniciou = Date.now();
    window.location.href = appScheme;
    setTimeout(function () {
      if (Date.now() - iniciou < 2200 && (isIOS ? APP_STORE_URL : true)) {
        window.location.href = lojaUrl;
      }
    }, 1500);
  }

  setTimeout(tentarAbrirApp, 350);
})();
