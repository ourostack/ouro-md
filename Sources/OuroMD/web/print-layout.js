(function () {
  var config = window.__ouroPrintLayoutConfig || {};
  var DEFAULT_GAP = Number(config.pageGap || 24);
  var GENERATED_PREFIX = "ouro-print-generated";
  var cachedMetrics = null;
  var applied = false;
  var noteDefinitions = Object.create(null);
  var sources = Object.create(null);
  var noteLayer = null;
  var pageLinks = [];
  var profile = window.__ouroPrintProfiling ? {steps: {}, rectReads: 0, anchorRectReads: 0, anchorQueries: 0} : null;
  if (profile) {
    window.__ouroPrintLayoutProfile = profile;
    var originalRects = Element.prototype.getClientRects;
    Element.prototype.getClientRects = function () {
      profile.rectReads += 1;
      if (this.tagName === "A") { profile.anchorRectReads += 1; }
      return originalRects.call(this);
    };
    var originalQuery = Element.prototype.querySelectorAll;
    Element.prototype.querySelectorAll = function (selector) {
      if (selector === "a[href]") { profile.anchorQueries += 1; }
      return originalQuery.call(this, selector);
    };
  }

  function measuredStep(code, operation) {
    if (!profile) { return operation(); }
    var start = performance.now();
    try { return operation(); } finally { profile.steps[code] = (profile.steps[code] || 0) + performance.now() - start; }
  }

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

  function uniquifyClonedIDs(root) {
    var seen = new Set();
    Array.prototype.forEach.call(root.querySelectorAll("[id]"), function (node) {
      var id = node.id;
      if (seen.has(id)) {
        node.id = reserveID(id + "-ouro-copy");
      }
      seen.add(node.id);
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
      marker.textContent = "[S" + number + "]";
      anchor.insertAdjacentElement("afterend", marker);
    });
    if (!referenceRecords.length) { return; }
    var section = document.createElement("section");
    section.className = "ouro-print-external-links";
    section.dataset.ouroPrintGenerated = "true";
    var heading = document.createElement("h2");
    heading.id = reserveID(GENERATED_PREFIX + "-external-links-heading");
    heading.textContent = "Link sources (endnotes)";
    section.setAttribute("aria-labelledby", heading.id);
    section.appendChild(heading);
    var list = document.createElement("ol");
    referenceRecords.forEach(function (reference) {
      var item = document.createElement("li");
      item.id = reserveID(GENERATED_PREFIX + "-reference-" + reference.number);
      var link = document.createElement("a");
      link.className = "ouro-print-reference-url";
      link.href = reference.url;
      link.textContent = "[S" + reference.number + "] " + reference.url;
      item.appendChild(link);
      list.appendChild(item);
    });
    section.appendChild(list);
    root.appendChild(section);
  }

  function applySectionBreaks() {
    var root = article();
    var walker = document.createTreeWalker(root, NodeFilter.SHOW_COMMENT);
    var comments = [];
    while (walker.nextNode()) {
      if (/^\s*pagebreak\s*$/i.test(walker.currentNode.nodeValue)) { comments.push(walker.currentNode); }
    }
    comments.forEach(function (comment) {
      var marker = document.createElement("div");
      marker.className = "page-break";
      comment.parentNode.replaceChild(marker, comment);
    });
    var selector = ".page-break";
    var level = Number(config.headingBreakLevel);
    if (level >= 1 && level <= 6) { selector += ", h" + level; }
    var first = root.firstElementChild;
    Array.prototype.forEach.call(root.querySelectorAll(selector), function (node) {
      if (node.closest(".footnotes, .footnotes-defs-div, .ouro-print-external-links") || node.dataset.ouroPrintGenerated) { return; }
      if (node === first) { return; }
      if (node.classList.contains("page-break")) {
        var next = node.nextElementSibling;
        if (next) { next.classList.add("ouro-print-section-break"); }
        node.style.display = "none";
      } else {
        node.classList.add("ouro-print-section-break");
      }
    });
  }

  function preparePageFootnotes() {
    var root = article();
    var numbers = Object.create(null);
    var next = 1;
    Array.prototype.forEach.call(root.querySelectorAll("a[href]"), function (anchor) {
      var url = normalizedExternalURL(anchor);
      if (!url) { return; }
      var key = numbers[url];
      if (!key) {
        key = "S" + next++;
        numbers[url] = key;
        sources[key] = url;
      }
      var marker = document.createElement("sup");
      marker.className = "ouro-print-reference-marker";
      marker.dataset.ouroSource = key;
      marker.textContent = "[" + key + "]";
      anchor.dataset.ouroSource = key;
      anchor.insertAdjacentElement("afterend", marker);
    });
    Array.prototype.forEach.call(root.querySelectorAll(".footnotes li[id], .footnotes-defs-div li[id]"), function (note) {
      var id = note.id;
      var refs = Array.prototype.filter.call(root.querySelectorAll("a[href]"), function (anchor) {
        return anchor.getAttribute("href") === "#" + id && !anchor.closest(".footnotes, .footnotes-defs-div");
      });
      if (!refs.length) { return; } // Unreferenced authored definitions remain in the body.
      refs.forEach(function (ref) { ref.dataset.ouroNote = id; });
      noteDefinitions[id] = note.cloneNode(true);
      note.remove();
    });
    Array.prototype.forEach.call(root.querySelectorAll(".footnotes, .footnotes-defs-div"), function (section) {
      if (!section.querySelector("li")) { section.remove(); }
    });
  }

  function buildPageFootnotes() {
    var root = article();
    var fullHeight = Number(config.pageContentHeight);
    var stride = Number(config.pageContentWidth) + Number(config.pageGap || DEFAULT_GAP);
    var reserved = 0;
    noteLayer = document.createElement("div");
    noteLayer.className = "ouro-print-note-layer";
    root.parentNode.appendChild(noteLayer);
    for (var round = 0; round < 16; round++) {
      noteLayer.replaceChildren();
      root.style.height = (fullHeight - reserved) + "px";
      var rootRect = root.getBoundingClientRect();
      var pages = Object.create(null);
      // Batch geometry reads before attaching any of the footer DOM.
      Array.prototype.forEach.call(root.querySelectorAll("[data-ouro-source], [data-ouro-note]"), function (marker) {
        Array.prototype.forEach.call(marker.getClientRects(), function (rect) {
          if (rect.width <= 0 || rect.height <= 0) { return; }
          var page = pageIndexForRect(rect, rootRect, stride);
          if (!pages[page]) { pages[page] = { sources: new Set(), notes: new Set(), references: Object.create(null) }; }
          var record = pages[page];
          if (marker.dataset.ouroSource) { record.sources.add(marker.dataset.ouroSource); }
          if (marker.dataset.ouroNote) {
            var noteID = marker.dataset.ouroNote;
            record.notes.add(noteID);
            if (!record.references[noteID]) { record.references[noteID] = []; }
            if (!record.references[noteID].includes(marker)) { record.references[noteID].push(marker); }
            Array.prototype.forEach.call(noteDefinitions[noteID].querySelectorAll("[data-ouro-source]"), function (nested) {
              record.sources.add(nested.dataset.ouroSource);
            });
          }
        });
      });
      var footers = [];
      Object.keys(pages).forEach(function (page) {
        var record = pages[page];
        var footer = document.createElement("aside");
        footer.className = "ouro-print-page-notes";
        footer.style.left = (Number(page) * stride) + "px";
        footer.style.top = "0px";
        footer.dataset.ouroNotePage = page;
        record.notes.forEach(function (id) {
          var entry = document.createElement("div");
          entry.className = "ouro-print-authored-note";
          var definition = noteDefinitions[id];
          entry.innerHTML = definition.innerHTML;
          entry.id = id + "-ouro-page-" + page;
          var label = document.createElement("span");
          var ref = root.querySelector('[data-ouro-note="' + CSS.escape(id) + '"]');
          label.textContent = "Note " + (ref ? ref.textContent : id) + ". ";
          entry.prepend(label);
          Array.prototype.forEach.call(entry.querySelectorAll("[id]"), function (node) {
            node.id += "-ouro-page-" + page;
          });
          Array.prototype.forEach.call(entry.querySelectorAll("a[href]"), function (backlink) {
            var isBacklink = backlink.matches(".footnote-backref, .vditor-footnotes__goto-ref, [role='doc-backlink']") || /^[↩↵][\uFE0E\uFE0F]?$/.test(backlink.textContent.trim());
            var href = backlink.getAttribute("href") || "";
            if (!isBacklink || href.charAt(0) !== "#") { return; }
            var target = document.getElementById(href.slice(1));
            var references = record.references[id];
            if (target && references.some(function (reference) { return target === reference || target.contains(reference); })) { return; }
            var localReference = references[0];
            if (!localReference.id) { localReference.id = reserveID(GENERATED_PREFIX + "-note-reference"); }
            backlink.setAttribute("href", "#" + localReference.id);
          });
          footer.appendChild(entry);
        });
        record.sources.forEach(function (key) {
          var entry = document.createElement("p");
          entry.appendChild(document.createTextNode("[" + key + "] "));
          var link = document.createElement("a");
          link.href = sources[key];
          link.textContent = sources[key];
          entry.appendChild(link);
          footer.appendChild(entry);
        });
        footers.push(footer);
      });
      footers.forEach(function (footer) { noteLayer.appendChild(footer); });
      var heights = footers.map(function (footer) { return Math.ceil(footer.getBoundingClientRect().height); });
      var required = heights.reduce(function (max, height) { return Math.max(max, height + 12); }, 0);
      if (required > fullHeight - 96) {
        throw new Error("Page footnotes leave less than 96 pt for body text. Choose Endnotes or Original links, reduce text size, or use wider paper/margins.");
      }
      if (required <= reserved || required === 0) {
        footers.forEach(function (footer, index) {
          footer.style.top = (fullHeight - heights[index]) + "px";
        });
        Array.prototype.forEach.call(root.querySelectorAll("[data-ouro-note]"), function (ref) {
          var page = pageIndexForRect(ref.getBoundingClientRect(), rootRect, stride);
          ref.setAttribute("href", "#" + ref.dataset.ouroNote + "-ouro-page-" + page);
        });
        return;
      }
      reserved = required;
    }
    throw new Error("Page footnote layout did not converge. Choose Endnotes or Original links, or adjust the page geometry.");
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

  function maximumFragmentHeight(node) {
    return Array.prototype.reduce.call(node.getClientRects(), function (height, rect) {
      return Math.max(height, rect.height || 0);
    }, 0);
  }

  function splitTablesForPages() {
    var replacements = [];
    Array.prototype.forEach.call(article().querySelectorAll("table"), function (table) {
      if (table.dataset.ouroPrintSplit === "true") { return; }
      if (table.querySelector("table") || table.querySelector("tbody [rowspan], tbody [colspan], thead [rowspan], thead [colspan]")) { return; }
      var rows = Array.prototype.slice.call(table.querySelectorAll("tbody > tr"));
      if (!rows.length) { return; }
      var contentHeight = toFiniteNumber(Number(config.pageContentHeight), 684);
      var headerHeight = 0;
      var footerHeight = 0;
      Array.prototype.forEach.call(table.children, function (child) {
        var tag = child.tagName && child.tagName.toLowerCase();
        if (tag === "tfoot") {
          footerHeight += maximumFragmentHeight(child);
        } else if (tag === "thead" || tag === "caption") {
          headerHeight += maximumFragmentHeight(child);
        }
      });
      var rowHeights = rows.map(maximumFragmentHeight);
      var safeHeight = Math.max(1, contentHeight - headerHeight - footerHeight - 18);
      var groups = [];
      var current = [];
      var currentHeight = 0;
      rows.forEach(function (row, index) {
        if (current.length && currentHeight + rowHeights[index] > safeHeight) {
          groups.push(current);
          current = [];
          currentHeight = 0;
        }
        current.push(row);
        currentHeight += rowHeights[index];
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
    var geometryRoot = root.parentNode;
    Array.prototype.forEach.call(geometryRoot.querySelectorAll("[id]"), function (node) {
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
    Array.prototype.forEach.call(geometryRoot.querySelectorAll("*"), function (node, index) {
      if (node === root || node === noteLayer) { return; }
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
    Array.prototype.forEach.call(geometryRoot.querySelectorAll("a[href]"), function (anchor) {
      var href = (anchor.getAttribute("href") || "").trim();
      var destination = href.charAt(0) === "#" ? destinations[href.slice(1)] : null;
      if (href.charAt(0) === "#" && !destination) { return; }
      Array.prototype.forEach.call(anchor.getClientRects(), function (rect) {
        var page = pageIndexForRect(rect, rootRect, stride);
        var local = pageLocationForRect(rect, page, rootRect, stride);
        if (rect.width <= 0 || rect.height <= 0 || local.x + rect.width < 0 || local.x > contentWidth || local.y + rect.height < 0 || local.y > contentHeight) { return; }
        if (!pageLinks[page]) { pageLinks[page] = []; }
        pageLinks[page].push({
          x: Math.max(0, local.x),
          y: Math.max(0, local.y),
          width: rect.width,
          height: rect.height,
          url: destination ? null : anchor.href,
          destinationPageIndex: destination ? destination.pageIndex : null,
          destinationX: destination ? destination.x : null,
          destinationY: destination ? destination.y : null
        });
      });
    });
    return cachedMetrics;
  }

  function applyLayout() {
    if (applied) { return pageMetrics(); }
    cachedMetrics = null;
    article().style.transform = "translateX(0px)";
    Array.prototype.forEach.call(article().querySelectorAll("details"), function (details) { details.open = true; });
    if (config.pageFootnotes) { measuredStep("prepare_footnotes", preparePageFootnotes); }
    measuredStep("split_tables", splitTablesForPages);
    measuredStep("wrap_tables", wrapTablesForPagination);
    measuredStep("unique_ids", function () { uniquifyClonedIDs(article()); });
    if (!config.pageFootnotes) { measuredStep("references", applyReferences); }
    measuredStep("section_breaks", applySectionBreaks);
    if (config.pageFootnotes) { measuredStep("build_footnotes", buildPageFootnotes); }
    applied = true;
    return measuredStep("geometry", pageMetrics);
  }

  function showPage(index) {
    var metrics = pageMetrics();
    var normalizedIndex = Math.max(0, Math.min(metrics.pageCount - 1, index || 0));
    var root = article();
    var transform = "translateX(-" + (normalizedIndex * metrics.pageStride) + "px)";
    root.style.transform = transform;
    if (noteLayer) {
      Array.prototype.forEach.call(noteLayer.children, function (footer) {
        footer.style.transform = transform;
        footer.style.visibility = Number(footer.dataset.ouroNotePage) === normalizedIndex ? "visible" : "hidden";
      });
    }
    metrics.links = pageLinks[normalizedIndex] || [];
    return metrics;
  }

  window.OuroPrintLayout = {
    apply: applyLayout,
    metrics: pageMetrics,
    showPage: showPage
  };

})();
