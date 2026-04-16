/**
 * Eventos Meta Pixel — página produto demonstração
 */
document.addEventListener("DOMContentLoaded", function () {
  if (window.dipertinPixel && window.dipertinPixel.viewContent) {
    window.dipertinPixel.viewContent({
      content_ids: ["DEMO-PRD-001"],
      content_type: "product",
      content_name: "Produto demonstração DiPertin",
      content_category: "demonstracao",
      value: 29.9,
      currency: "BRL",
    });
  }
  var addBtn = document.querySelector("[data-pixel-addtocart]");
  var chkBtn = document.querySelector("[data-pixel-checkout]");
  var purBtn = document.querySelector("[data-pixel-purchase]");
  if (addBtn && window.dipertinPixel) {
    addBtn.addEventListener("click", function () {
      window.dipertinPixel.addToCart({
        content_ids: ["DEMO-PRD-001"],
        content_type: "product",
        value: 29.9,
        currency: "BRL",
      });
    });
  }
  if (chkBtn && window.dipertinPixel) {
    chkBtn.addEventListener("click", function () {
      window.dipertinPixel.initiateCheckout({
        content_ids: ["DEMO-PRD-001"],
        value: 29.9,
        currency: "BRL",
        num_items: 1,
      });
    });
  }
  if (purBtn && window.dipertinPixel) {
    purBtn.addEventListener("click", function () {
      window.dipertinPixel.purchase({
        content_ids: ["DEMO-PRD-001"],
        value: 29.9,
        currency: "BRL",
        num_items: 1,
      });
    });
  }
});
