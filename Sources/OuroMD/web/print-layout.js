(function () {
  function shouldSkipReference(anchor) {
    if (!anchor) { return true; }
    if (anchor.closest("pre, code")) { return true; }
    var href = (anchor.getAttribute("href") || "").trim();
    if (!href || href.charAt(0) === "#") { return true; }
    var visibleChildren = Array.prototype.filter.call(anchor.childNodes || [], function (node) {
      if (node.nodeType === Node.TEXT_NODE) { return (node.textContent || "").trim().length > 0; }
      return node.nodeType === Node.ELEMENT_NODE;
    });
    if (!visibleChildren.length) { return false; }
    var onlyCodeOrImages = visibleChildren.every(function (node) {
      return node.nodeType === Node.TEXT_NODE
        ? false
        : ["CODE", "IMG", "PICTURE", "SVG"].indexOf(node.nodeName) >= 0;
    });
    if (onlyCodeOrImages) { return true; }
    var visibleText = (anchor.textContent || "").replace(/\s+/g, " ").trim();
    return !visibleText && !!anchor.querySelector("img, picture, svg");
  }

  function normalizedExternalURL(anchor) {
    if (!anchor || shouldSkipReference(anchor)) { return null; }
    try {
      var url = new URL(anchor.getAttribute("href"), document.baseURI || window.location.href);
      if (!["http:", "https:"].includes(url.protocol)) { return null; }
      return url.href;
    } catch (error) {
      return null;
    }
  }

  function removeExistingReferences(root) {
    Array.prototype.forEach.call(root.querySelectorAll(".ouro-print-reference-marker, .ouro-print-external-links"), function (node) {
      node.remove();
    });
  }

  function ensureSection(article, references) {
    if (!references.length) { return; }
    var section = document.createElement("section");
    section.className = "ouro-print-external-links";
    section.setAttribute("aria-labelledby", "ouro-print-external-links-heading");

    var rule = document.createElement("hr");
    section.appendChild(rule);

    var heading = document.createElement("h2");
    heading.id = "ouro-print-external-links-heading";
    heading.textContent = "External links";
    section.appendChild(heading);

    var list = document.createElement("ol");
    references.forEach(function (reference) {
      var item = document.createElement("li");
      item.id = "ouro-print-reference-" + reference.number;
      var link = document.createElement("a");
      link.className = "ouro-print-reference-url";
      link.href = reference.url;
      link.textContent = reference.url;
      item.appendChild(link);
      list.appendChild(item);
    });
    section.appendChild(list);
    article.appendChild(section);
  }

  function addMarkers(article) {
    var config = window.__ouroPrintLayoutConfig || {};
    if (!config.includeExternalLinkReferences) { return; }

    var references = [];
    var numbersByURL = Object.create(null);
    Array.prototype.forEach.call(article.querySelectorAll("a[href]"), function (anchor) {
      var url = normalizedExternalURL(anchor);
      if (!url) { return; }
      var number = numbersByURL[url];
      if (!number) {
        number = references.length + 1;
        numbersByURL[url] = number;
        references.push({ number: number, url: url });
      }
      var marker = document.createElement("sup");
      marker.className = "ouro-print-reference-marker";
      marker.setAttribute("data-ouro-print-reference", String(number));
      var jump = document.createElement("a");
      jump.href = "#ouro-print-reference-" + number;
      jump.textContent = "[" + number + "]";
      marker.appendChild(jump);
      anchor.insertAdjacentElement("afterend", marker);
    });

    ensureSection(article, references);
  }

  function applyLayout() {
    var article = document.querySelector(".markdown-body") || document.body;
    if (!article) { return; }
    removeExistingReferences(article);
    addMarkers(article);
  }

  window.OuroPrintLayout = {
    apply: applyLayout
  };

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", applyLayout, { once: true });
  } else {
    applyLayout();
  }
})();
