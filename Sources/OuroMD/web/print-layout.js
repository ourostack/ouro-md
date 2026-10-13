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

  function pageIndexForRect(rect, rootRect, stride) {
    return Math.max(0, Math.floor((rect.left - rootRect.left + 0.5) / stride));
  }

  function pageLocationForRect(rect, pageIndex, rootRect, stride) {
    return {
      x: rect.left - rootRect.left - (pageIndex * stride),
      y: rect.top - rootRect.top
    };
  }

  function normalizedExternalURL(anchor) {
    if (!anchor || shouldSkipReference(anchor)) { return null; }
    try {
      var url = new URL(anchor.getAttribute("href"), document.baseURI || window.location.href);
      if (!["http:", "https:", "file:", "mailto:", "tel:"].includes(url.protocol)) { return null; }
      return url.href;
    } catch (error) {
      return null;
    }
  }

  function shouldSkipReference(anchor) {
    if (!anchor) { return true; }
    if (anchor.closest("pre, code")) { return true; }
    var href = (anchor.getAttribute("href") || "").trim();
    if (!href || href.charAt(0) === "#") { return true; }
    return false;
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
    heading.textContent = "Link sources (endnotes)";
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

  function cloneTableFragment(table, rows, includeFooter) {
    var clone = table.cloneNode(false);
    Array.prototype.forEach.call(table.children, function (child) {
      var tag = child.tagName && child.tagName.toLowerCase();
      if (tag === "caption" || tag === "colgroup" || tag === "thead" || (includeFooter && tag === "tfoot")) {
        clone.appendChild(child.cloneNode(true));
      }
    });
    var body = document.createElement("tbody");
    rows.forEach(function (row) { body.appendChild(row.cloneNode(true)); });
    clone.appendChild(body);
    clone.dataset.ouroPrintSplit = "true";
    return clone;
  }

  function splitTablesForPages() {
    var replacements = [];
    Array.prototype.forEach.call(article().querySelectorAll("table"), function (table) {
      if (table.dataset.ouroPrintSplit === "true") { return; }
      if (table.querySelector("table") || table.querySelector("tbody [rowspan], tbody [colspan], thead [rowspan], thead [colspan]")) { return; }
      var rows = Array.prototype.slice.call(table.querySelectorAll("tbody > tr"));
      if (!rows.length) { return; }
      var root = article();
      var rootRect = root.getBoundingClientRect();
      var contentHeight = toFiniteNumber(Number(config.pageContentHeight), 684);
      var stride = toFiniteNumber(Number(config.pageContentWidth), root.clientWidth || 1) + toFiniteNumber(Number(config.pageGap), DEFAULT_GAP);
      var headerHeight = 0;
      var footerHeight = 0;
      Array.prototype.forEach.call(table.children, function (child) {
        var tag = child.tagName && child.tagName.toLowerCase();
        if (tag === "tfoot") {
          footerHeight += child.getBoundingClientRect().height || 0;
        } else if (tag === "thead" || tag === "caption") {
          headerHeight += child.getBoundingClientRect().height || 0;
        }
      });
      var maxRowHeight = rows.reduce(function (max, row) {
        return Math.max(max, row.getBoundingClientRect().height || 0);
      }, 0);
      var safeRowsPerPage = Math.max(1, Math.floor((contentHeight - headerHeight - footerHeight) / Math.max(1, maxRowHeight)) - 2);
      var groups = [];
      var current = [];
      var currentPage = 0;
      rows.forEach(function (row) {
        var fragments = Array.prototype.filter.call(row.getClientRects(), function (rect) {
          return rect.width > 0 && rect.height > 0;
        });
        var pages = Array.from(new Set(fragments.map(function (rect) {
          return pageIndexForRect(rect, rootRect, stride);
        }))).sort(function (a, b) { return a - b; });
        if (!pages.length) { return; }
        var rowTargetPage = pages[pages.length - 1];
        var lastRect = fragments[fragments.length - 1];
        var bottomSlack = contentHeight - (lastRect.bottom - rootRect.top);
        if (pages.length === 1 && bottomSlack < 18) {
          rowTargetPage += 1;
        }
        if (!current.length) {
          currentPage = rowTargetPage;
        } else if (pages.length > 1 || rowTargetPage !== currentPage || current.length >= safeRowsPerPage) {
          groups.push(current);
          current = [];
          currentPage = rowTargetPage;
        }
        current.push(row);
      });
      if (current.length) { groups.push(current); }
      if (groups.length <= 1) { return; }
      var container = document.createElement("div");
      container.className = "ouro-print-split-table-group";
      groups.forEach(function (group, index) {
        var wrapper = document.createElement("div");
        wrapper.className = "ouro-print-keep-together";
        wrapper.appendChild(cloneTableFragment(table, group, index === groups.length - 1));
        container.appendChild(wrapper);
      });
      replacements.push({ table: table, container: container });
    });
    replacements.forEach(function (replacement) {
      replacement.table.parentNode.insertBefore(replacement.container, replacement.table);
      replacement.table.remove();
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
    var destinations = {};
    Array.prototype.forEach.call(root.querySelectorAll("[id]"), function (node) {
      if (!node.getBoundingClientRect) { return; }
      var rect = node.getBoundingClientRect();
      if (rect.width <= 0 && rect.height <= 0) { return; }
      var pageIndex = pageIndexForRect(rect, rootRect, stride);
      var local = pageLocationForRect(rect, pageIndex, rootRect, stride);
      destinations[node.id] = {
        pageIndex: pageIndex,
        x: local.x,
        y: local.y
      };
    });
    Array.prototype.forEach.call(root.querySelectorAll("*"), function (node, index) {
      if (!node.getBoundingClientRect) { return; }
      var fragments = Array.prototype.filter.call(node.getClientRects(), function (rect) { return rect.width > 0 && rect.height > 0; });
      if (!fragments.length) { return; }
      var pages = Array.from(new Set(fragments.map(function (rect) {
        return pageIndexForRect(rect, rootRect, stride);
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
      links: [],
      destinations: destinations
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
    metrics.links = Array.prototype.map.call(root.querySelectorAll("a[href]"), function (anchor) {
      var rect = anchor.getBoundingClientRect();
      var x = rect.left - frameRect.left;
      var y = rect.top - frameRect.top;
      if (x + rect.width < 0 || x > metrics.contentWidth || y + rect.height < 0 || y > metrics.contentHeight) {
        return null;
      }
      var href = (anchor.getAttribute("href") || "").trim();
      if (href.charAt(0) === "#") {
        var destination = metrics.destinations[href.slice(1)];
        if (!destination) { return null; }
        return {
          x: Math.max(0, x),
          y: Math.max(0, y),
          width: rect.width,
          height: rect.height,
          url: null,
          destinationPageIndex: destination.pageIndex,
          destinationX: destination.x,
          destinationY: destination.y
        };
      }
      return {
        x: Math.max(0, x),
        y: Math.max(0, y),
        width: rect.width,
        height: rect.height,
        url: anchor.href,
        destinationPageIndex: null,
        destinationX: null,
        destinationY: null
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
