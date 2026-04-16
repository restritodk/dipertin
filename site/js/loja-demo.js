/**
 * Meta Pixel ViewContent — página loja demonstração
 */
document.addEventListener("DOMContentLoaded", function () {
  if (window.dipertinPixel && window.dipertinPixel.viewContent) {
    window.dipertinPixel.viewContent({
      content_ids: ["DEMO-LOJA-001"],
      content_type: "store",
      content_name: "Loja demonstração DiPertin",
      value: 0,
      currency: "BRL",
    });
  }
});
