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
      if (table.dataset.ouroPrintSplit === "true") { return; }
      var parent = table.parentElement;
      if (parent && parent.classList && parent.classList.contains("ouro-print-keep-together")) { return; }
      var wrapper = document.createElement("div");
      wrapper.className = "ouro-print-keep-together";
      table.parentNode.insertBefore(wrapper, table);
      wrapper.appendChild(table);
    });
  }

  function cloneTableFragment(table, rows) {
    var clone = table.cloneNode(false);
    Array.prototype.forEach.call(table.children, function (child) {
      var tag = child.tagName && child.tagName.toLowerCase();
      if (tag === "colgroup" || tag === "caption") {
        clone.appendChild(child.cloneNode(true));
      }
    });
    var head = table.querySelector("thead");
    if (head) { clone.appendChild(head.cloneNode(true)); }
    var body = document.createElement("tbody");
    rows.forEach(function (row) { body.appendChild(row.cloneNode(true)); });
    clone.appendChild(body);
    clone.dataset.ouroPrintSplit = "true";
    return clone;
  }

  function splitTablesForPages() {
    var contentHeight = toFiniteNumber(Number(config.pageContentHeight), 684);
    Array.prototype.forEach.call(article().querySelectorAll("table"), function (table) {
      if (table.dataset.ouroPrintSplit === "true") { return; }
      var rows = Array.prototype.slice.call(table.querySelectorAll("tbody > tr"));
      if (!rows.length) { return; }
      var headerHeight = 0;
      var head = table.querySelector("thead");
      if (head) { headerHeight = head.getBoundingClientRect().height; }
      var groups = [];
      var current = [];
      var currentHeight = headerHeight;
      rows.forEach(function (row) {
        var rowHeight = row.getBoundingClientRect().height || 0;
        if (current.length && currentHeight + rowHeight > contentHeight) {
          groups.push(current);
          current = [];
          currentHeight = headerHeight;
        }
        current.push(row);
        currentHeight += rowHeight;
      });
      if (current.length) { groups.push(current); }
      if (groups.length <= 1) { return; }
      var container = document.createElement("div");
      container.className = "ouro-print-split-table-group";
      groups.forEach(function (group) {
        var wrapper = document.createElement("div");
        wrapper.className = "ouro-print-keep-together";
        wrapper.appendChild(cloneTableFragment(table, group));
        container.appendChild(wrapper);
      });
      table.parentNode.insertBefore(container, table);
      table.remove();
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
    var stride = contentWidth + pageGap;
    var rootRect = root.getBoundingClientRect();
    var usedPages = new Set([0]);
    var fragmentedProofIDs = [];
    Array.prototype.forEach.call(root.querySelectorAll("*"), function (node, index) {
      if (!node.getBoundingClientRect) { return; }
      var fragments = Array.prototype.filter.call(node.getClientRects(), function (rect) { return rect.width > 0 && rect.height > 0; });
      if (!fragments.length) { return; }
      var pages = Array.from(new Set(fragments.map(function (rect) {
        return Math.max(0, Math.floor((rect.left - rootRect.left + 0.5) / stride));
      }))).sort(function (a, b) { return a - b; });
      pages.forEach(function (page) { usedPages.add(page); });
      if (pages.length > 1) {
        fragmentedProofIDs.push(node.getAttribute("data-proof-id") || (node.tagName.toLowerCase() + "-" + index));
      }
    });
    var sortedPages = Array.from(usedPages).sort(function (a, b) { return a - b; });
    var pageCount = (sortedPages.length ? sortedPages[sortedPages.length - 1] : 0) + 1;
    cachedMetrics = {
      contentWidth: contentWidth,
      contentHeight: contentHeight,
      pageGap: pageGap,
      pageStride: stride,
      totalWidth: root.scrollWidth,
      pageCount: pageCount,
      fragmentedProofIDs: fragmentedProofIDs,
      endnoteLinks: []
    };
    return cachedMetrics;
  }

  function applyLayout() {
    cachedMetrics = null;
    document.documentElement.style.setProperty("--ouro-active-page-offset", "0px");
    splitTablesForPages();
    wrapTablesForPagination();
    applyReferences();
    return pageMetrics();
  }

  function showPage(index) {
    var metrics = pageMetrics();
    var normalizedIndex = Math.max(0, Math.min(metrics.pageCount - 1, index || 0));
    document.documentElement.style.setProperty("--ouro-active-page-offset", String(normalizedIndex * metrics.pageStride) + "px");
    var root = article();
    var frame = document.querySelector(".ouro-print-content-frame");
    var frameRect = frame ? frame.getBoundingClientRect() : root.getBoundingClientRect();
    metrics.endnoteLinks = Array.prototype.map.call(root.querySelectorAll(".ouro-print-external-links a.ouro-print-reference-url"), function (anchor) {
      var rect = anchor.getBoundingClientRect();
      var x = rect.left - frameRect.left;
      var y = rect.top - frameRect.top;
      if (x + rect.width < 0 || x > metrics.contentWidth || y + rect.height < 0 || y > metrics.contentHeight) {
        return null;
      }
      return {
        url: anchor.href,
        pageIndex: normalizedIndex,
        x: Math.max(0, x),
        y: Math.max(0, y),
        width: rect.width,
        height: rect.height
      };
    }).filter(Boolean);
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
