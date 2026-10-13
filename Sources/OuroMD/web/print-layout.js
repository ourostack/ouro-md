(function () {
  var config = window.__ouroPrintLayoutConfig || {};
  var DEFAULT_GAP = Number(config.pageGap || 24);
  var GENERATED_PREFIX = "ouro-print-generated";
  var cachedMetrics = null;

  function article() {
    return document.querySelector(".markdown-body") || document.body;
  }

  function toFiniteNumber(value, fallback) {
    return Number.isFinite(value) ? value : fallback;
  }

  function reserveID(base) {
    var candidate = base;
    var suffix = 1;
    while (document.getElementById(candidate)) {
      candidate = base + "-" + suffix;
      suffix += 1;
    }
    return candidate;
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

  function shouldSkipReference(anchor) {
    if (!anchor) { return true; }
    if (anchor.closest("pre")) { return true; }
    var href = (anchor.getAttribute("href") || "").trim();
    if (!href || href.charAt(0) === "#") { return true; }
    var visibleChildren = Array.prototype.filter.call(anchor.childNodes || [], function (node) {
      if (node.nodeType === Node.TEXT_NODE) {
        return (node.textContent || "").trim().length > 0;
      }
      return node.nodeType === Node.ELEMENT_NODE;
    });
    if (!visibleChildren.length) { return false; }
    var hasMeaningfulText = (anchor.textContent || "").replace(/\s+/g, " ").trim().length > 0;
    var onlyImages = visibleChildren.every(function (node) {
      return node.nodeType !== Node.TEXT_NODE && ["IMG", "PICTURE", "SVG"].indexOf(node.nodeName) >= 0;
    });
    return onlyImages || !hasMeaningfulText;
  }

  function removeExistingReferences(root) {
    Array.prototype.forEach.call(root.querySelectorAll("[data-ouro-print-generated='true']"), function (node) {
      node.remove();
    });
  }

  function applyReferences() {
    var root = article();
    removeExistingReferences(root);
    if (!config.includeExternalLinkReferences) { return; }

    var referenceRecords = [];
    var numbersByURL = Object.create(null);
    Array.prototype.forEach.call(root.querySelectorAll("a[href]"), function (anchor) {
      var url = normalizedExternalURL(anchor);
      if (!url) { return; }
      var number = numbersByURL[url];
      if (!number) {
        number = referenceRecords.length + 1;
        numbersByURL[url] = number;
        referenceRecords.push({ number: number, url: url });
      }
      var marker = document.createElement("sup");
      marker.className = "ouro-print-reference-marker";
      marker.dataset.ouroPrintGenerated = "true";
      marker.setAttribute("aria-label", "Reference " + number);
      marker.textContent = "[" + number + "]";
      anchor.insertAdjacentElement("afterend", marker);
    });

    if (!referenceRecords.length) { return; }

    var section = document.createElement("section");
    section.className = "ouro-print-external-links";
    section.dataset.ouroPrintGenerated = "true";

    var headingID = reserveID(GENERATED_PREFIX + "-external-links-heading");
    section.setAttribute("aria-labelledby", headingID);

    var rule = document.createElement("hr");
    rule.dataset.ouroPrintGenerated = "true";
    section.appendChild(rule);

    var heading = document.createElement("h2");
    heading.id = headingID;
    heading.dataset.ouroPrintGenerated = "true";
    heading.textContent = "External links";
    section.appendChild(heading);

    var list = document.createElement("ol");
    list.dataset.ouroPrintGenerated = "true";
    referenceRecords.forEach(function (reference) {
      var item = document.createElement("li");
      item.id = reserveID(GENERATED_PREFIX + "-reference-" + reference.number);
      item.dataset.ouroPrintGenerated = "true";
      var link = document.createElement("a");
      link.className = "ouro-print-reference-url";
      link.href = reference.url;
      link.textContent = reference.url;
      link.dataset.ouroPrintGenerated = "true";
      item.appendChild(link);
      list.appendChild(item);
    });
    section.appendChild(list);
    root.appendChild(section);
  }

  function wrapTablesForPagination() {
    Array.prototype.forEach.call(article().querySelectorAll("table"), function (table) {
      var parent = table.parentElement;
      if (parent && parent.classList && parent.classList.contains("ouro-print-keep-together")) { return; }
      var wrapper = document.createElement("div");
      wrapper.className = "ouro-print-keep-together";
      table.parentNode.insertBefore(wrapper, table);
      wrapper.appendChild(table);
    });
  }

  function pageMetrics() {
    var root = article();
    if (cachedMetrics) { return cachedMetrics; }
    var pageWidth = toFiniteNumber(Number(config.pageWidth), root.clientWidth || 1);
    var pageHeight = toFiniteNumber(Number(config.pageHeight), root.clientHeight || 1);
    var contentWidth = toFiniteNumber(Number(config.pageContentWidth), pageWidth);
    var contentHeight = toFiniteNumber(Number(config.pageContentHeight), pageHeight);
    var pageGap = toFiniteNumber(Number(config.pageGap), DEFAULT_GAP);
    var rootRect = root.getBoundingClientRect();
    var stride = contentWidth + pageGap;
    var totalWidth = Math.max(root.scrollWidth, pageWidth);
    var pageCount = Math.max(1, Math.ceil((totalWidth + 1) / stride));
    var pageOffsets = Array.apply(null, Array(pageCount)).map(function (_, index) { return index * stride; });
    var fragmentedProofIDs = Array.prototype.map.call(root.querySelectorAll("[data-proof-id]"), function (node) {
      var fragments = Array.prototype.filter.call(node.getClientRects(), function (rect) { return rect.width > 0 && rect.height > 0; });
      return fragments.length > 1 ? node.getAttribute("data-proof-id") : null;
    }).filter(Boolean);
    var endnoteLinks = Array.prototype.map.call(root.querySelectorAll(".ouro-print-external-links a.ouro-print-reference-url"), function (anchor) {
      var rect = anchor.getBoundingClientRect();
      var localX = rect.left - rootRect.left;
      var localY = rect.top - rootRect.top;
      var pageIndex = pageOffsets.findIndex(function (offset, index) {
        var nextOffset = index + 1 < pageOffsets.length ? pageOffsets[index + 1] : Number.POSITIVE_INFINITY;
        return localX >= offset && localX < nextOffset;
      });
      if (pageIndex < 0) { pageIndex = Math.max(0, pageCount - 1); }
      return {
        url: anchor.href,
        pageIndex: pageIndex,
        x: localX - pageOffsets[pageIndex],
        y: ((localY % pageHeight) + pageHeight) % pageHeight,
        width: rect.width,
        height: rect.height
      };
    });
    cachedMetrics = {
      contentWidth: contentWidth,
      contentHeight: contentHeight,
      pageGap: pageGap,
      pageStride: stride,
      totalWidth: totalWidth,
      pageCount: pageCount,
      pageOffsets: pageOffsets,
      fragmentedProofIDs: fragmentedProofIDs,
      endnoteLinks: endnoteLinks
    };
    return cachedMetrics;
  }

  function applyLayout() {
    cachedMetrics = null;
    document.documentElement.style.setProperty("--ouro-active-page-offset", "0px");
    wrapTablesForPagination();
    applyReferences();
    return pageMetrics();
  }

  function showPage(index) {
    var metrics = pageMetrics();
    var normalizedIndex = Math.max(0, Math.min(metrics.pageCount - 1, index || 0));
    document.documentElement.style.setProperty("--ouro-active-page-offset", String(metrics.pageOffsets[normalizedIndex] || 0) + "px");
    return metrics;
  }

  window.OuroPrintLayout = {
    apply: applyLayout,
    metrics: pageMetrics,
    showPage: showPage
  };

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", applyLayout, { once: true });
  } else {
    applyLayout();
  }
})();
