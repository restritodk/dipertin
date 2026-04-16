/**
 * Configuração pública do site (exposta no cliente).
 * Nunca coloque chaves secretas, tokens de API ou credenciais aqui.
 */
window.DIPERTIN_SITE = {
  siteBaseUrl: "https://www.dipertin.com.br",

  emailContato: "site@dipertin.com.br",

  /** Endpoint da Cloud Function para envio do formulário de contato */
  formEndpoint: "https://us-central1-depertin-f940f.cloudfunctions.net/enviarContatoSite",

  /** GET JSON — avaliações 5★ para a seção do site (sem App Check no browser) */
  avaliacoesSiteUrl:
    "https://us-central1-depertin-f940f.cloudfunctions.net/avaliacoesSitePublicas",

  /**
   * Painel em /sistema/ — build: `flutter build web --base-href /sistema/`; enviar conteúdo de build/web.
   * Rota inicial do painel (Flutter web usa hash): #/login
   */
  loginPainelUrl: "https://www.dipertin.com.br/sistema/#/login",

  /** Imagem para Open Graph / redes sociais (1200×630 recomendado) */
  defaultOgImagePath: "/assets/og-dipertin.png",

  /**
   * Links oficiais das lojas — atualize ao publicar o app.
   * Android: applicationId em android/app/build.gradle.kts
   * iOS: URL da App Store quando a app estiver publicada (ou deixe vazio)
   */
  googlePlayUrl: "",
  appStoreUrl: "",

  /** Meta Pixel (Facebook) — vazio desativa o script */
  metaPixelId: "",

  /** Google Search Console — cole o content aqui */
  googleSiteVerification: "",

};
