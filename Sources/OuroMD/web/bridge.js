// Bridge between the native app and the Vditor instant-rendering editor.
// Native -> JS: window.ouro.{setValue,getValue,getHTML,setTheme,setMode,setOutline,exec,markSaved,focus}
// JS -> Native: window.webkit.messageHandlers.ouro.postMessage({type,...})
(function () {
  "use strict";

  var vditor = null;
  var ready = false;
  var dirty = false;
  var qolInstalled = false;
  var referenceLinkCache = null;
  var referenceLinkError = "";
  var footnoteReservationCache = null;
  var anchorRequestGeneration = 0;
  var resetTableScrollPending = false;
  var resetTablesSeen = (typeof WeakSet === "function") ? new WeakSet() : null;
  var initialTheme = window.__ouroInitialTheme || {};
  var state = { mode: "ir", value: "", outline: false, uiTheme: initialTheme.uiMode || "classic", focus: false, typewriter: false, codeTheme: initialTheme.codeTheme || "github" };

  function post(type, extra) {
    try {
      var msg = { type: type };
      if (extra) { for (var k in extra) { msg[k] = extra[k]; } }
      window.webkit.messageHandlers.ouro.postMessage(msg);
    } catch (e) { /* not running inside the app */ }
  }

  function themeBackgroundCSS(background) {
    return "html,body,#editor,.vditor,.vditor-content{background:" + background + " !important;background-color:" + background + " !important;}";
  }

  function setImportantBackground(el, background) {
    if (!el || !el.style || !background) { return; }
    el.style.setProperty("background", background, "important");
    el.style.setProperty("background-color", background, "important");
  }

  function applyThemeBackground(background) {
    if (!background) { return; }
    var target = document.head || document.documentElement;
    var tag = document.getElementById("ouro-initial-background");
    if (!tag && target) {
      tag = document.createElement("style");
      tag.id = "ouro-initial-background";
      target.appendChild(tag);
    }
    if (tag) { tag.textContent = themeBackgroundCSS(background); }
    setImportantBackground(document.documentElement, background);
    setImportantBackground(document.body, background);
    setImportantBackground(document.getElementById("editor"), background);
  }

  applyThemeBackground(initialTheme.background || "");

  function setDirty(d) {
    if (d === dirty) { return; }
    dirty = d;
    post("dirty", { dirty: d });
  }

  var countTimer = null;
  function postCount(value) {
    if (countTimer) { clearTimeout(countTimer); }
    countTimer = setTimeout(function () {
      var text = (value || "").trim();
      var words = text ? text.split(/\s+/).length : 0;
      post("count", { words: words, chars: (value || "").length });
      postOutline();
    }, 250);
  }

  function postOutline() {
    var hs = document.querySelectorAll(".vditor-reset h1, .vditor-reset h2, .vditor-reset h3, .vditor-reset h4, .vditor-reset h5, .vditor-reset h6");
    var items = [];
    for (var i = 0; i < hs.length; i++) {
      items.push({ index: i, level: parseInt(hs[i].tagName.slice(1), 10), text: (hs[i].textContent || "").trim() });
    }
    post("outline", { items: items });
  }

  // --- Editor quality-of-life: wrap-the-selection behaviours --------------
  // Typing a paired character (or pasting a URL) while text is selected should
  // *wrap* the selection rather than replace it, like familiar code editors.

  var WRAP_PAIRS = { '"': '"', "'": "'", "`": "`", "(": ")", "[": "]", "{": "}", "*": "*", "_": "_" };

  // Auto-pair on an empty caret is a narrower, opt-out set: brackets and double
  // quotes only. ' and ` are excluded (apostrophes / inline-code collide), and
  // emphasis markers shouldn't silently self-close.
  var autoPair = true;
  var AUTO_OPEN = { "(": ")", "[": "]", "{": "}", '"': '"' };
  var AUTO_CLOSE = { ")": true, "]": true, "}": true, '"': true };

  // True only when the caret/selection lives inside the Vditor editable area, so
  // we never hijack typing in the find bar, rename popover, or other fields.
  function selectionInEditor() {
    var sel = window.getSelection();
    if (!sel || !sel.anchorNode) { return false; }
    var node = sel.anchorNode;
    var el = node.nodeType === 1 ? node : node.parentElement;
    return !!(el && el.closest && el.closest("#editor"));
  }

  function selectedText() {
    var sel = window.getSelection();
    if (!sel || sel.rangeCount === 0 || sel.isCollapsed) { return ""; }
    return sel.toString();
  }

  // A bare, single-token URL (or mailto target) — the thing you'd paste onto a
  // word to linkify it. Multi-word clipboard text pastes normally.
  function looksLikeURL(text) {
    var t = (text || "").trim();
    if (!t || /\s/.test(t)) { return false; }
    return /^(https?|ftp|mailto):/i.test(t) || /^www\.[^\s]+\.[^\s]+$/i.test(t);
  }

  function wrapSelection(open, close, selected) {
    document.execCommand("insertText", false, open + selected + close);
    // Re-select the inner text so the selection survives the wrap (lets you
    // stack wraps, e.g. * then * for bold). Best-effort: only the literal pairs
    // stay in one text node; emphasis markers re-render, so we bail gracefully.
    try {
      var sel = window.getSelection();
      if (!sel || sel.rangeCount === 0) { return; }
      var range = sel.getRangeAt(0);
      var node = range.endContainer;
      if (node.nodeType !== 3) { return; }
      var innerEnd = range.endOffset - close.length;
      var innerStart = innerEnd - selected.length;
      if (innerStart < 0 || innerEnd > node.length) { return; }
      var inner = document.createRange();
      inner.setStart(node, innerStart);
      inner.setEnd(node, innerEnd);
      sel.removeAllRanges();
      sel.addRange(inner);
    } catch (e) { /* leave the caret where the insert left it */ }
  }

  // Caret neighbours for auto-pairing. Null unless the caret is a collapsed
  // selection sitting in a text node.
  function caretContext() {
    var sel = window.getSelection();
    if (!sel || sel.rangeCount === 0 || !sel.isCollapsed) { return null; }
    var range = sel.getRangeAt(0);
    var node = range.startContainer;
    if (node.nodeType !== 3) { return null; }
    var text = node.nodeValue || "";
    return {
      sel: sel, node: node, offset: range.startOffset,
      before: range.startOffset > 0 ? text.charAt(range.startOffset - 1) : "",
      after: range.startOffset < text.length ? text.charAt(range.startOffset) : ""
    };
  }

  // Returns true if it handled the key (caller should stop). Implements
  // auto-close, skip-over a just-typed closer, and delete-the-empty-pair.
  function handleAutoPair(e) {
    if (!autoPair) { return false; }
    var ctx = caretContext();
    if (!ctx) { return false; }

    if (e.key === "Backspace") {
      if (ctx.before && AUTO_OPEN[ctx.before] === ctx.after) {
        var del = document.createRange();
        del.setStart(ctx.node, ctx.offset - 1);
        del.setEnd(ctx.node, ctx.offset + 1);
        ctx.sel.removeAllRanges();
        ctx.sel.addRange(del);
        document.execCommand("insertText", false, "");
        return true;
      }
      return false;
    }

    // Skip over a just-typed closer instead of inserting a duplicate. For the
    // double quote we also skip when the char ahead is a *curly* variant (“ ”),
    // because macOS smart-quote substitution can replace the straight closer we
    // inserted — without this tolerance the user gets a doubled quote and has to
    // arrow past it. (We also disable that substitution natively, but this keeps
    // the behaviour correct even if it's re-enabled or already in the document.)
    var aheadIsCloser = AUTO_CLOSE[e.key] && ctx.after === e.key;
    var aheadIsCurlyQuote = e.key === '"' && (ctx.after === "“" || ctx.after === "”");
    if (aheadIsCloser || aheadIsCurlyQuote) {
      ctx.sel.modify("move", "forward", "character");
      return true;
    }

    var close = AUTO_OPEN[e.key];
    if (close !== undefined) {
      // Don't auto-close a quote that's hugging a word (closing quote, not opening).
      if (e.key === '"' && /\w/.test(ctx.before)) { return false; }
      document.execCommand("insertText", false, e.key + close);
      ctx.sel.modify("move", "backward", "character");
      return true;
    }
    return false;
  }

  function installEditorQOL() {
    if (qolInstalled) { return; }
    qolInstalled = true;

    // Capture phase so we decide before Vditor's own key handling replaces the
    // selection with the typed character.
    document.addEventListener("keydown", function (e) {
      if (e.metaKey || e.ctrlKey || e.altKey || e.isComposing) { return; }
      if (!selectionInEditor()) { return; }
      var selected = selectedText();
      if (selected) {
        var close = WRAP_PAIRS[e.key];
        if (close === undefined) { return; }
        e.preventDefault();
        e.stopImmediatePropagation();
        wrapSelection(e.key, close, selected);
        return;
      }
      // No selection: auto-pairing on the empty caret.
      if (handleAutoPair(e)) {
        e.preventDefault();
        e.stopImmediatePropagation();
      }
    }, true);

    // Paste a URL onto a selection -> [selection](url).
    document.addEventListener("paste", function (e) {
      if (!selectionInEditor()) { return; }
      var selected = selectedText();
      if (!selected) { return; }
      var clip = e.clipboardData || window.clipboardData;
      if (!clip) { return; }
      var text = clip.getData("text/plain");
      if (!looksLikeURL(text)) { return; }
      e.preventDefault();
      e.stopImmediatePropagation();
      document.execCommand("insertText", false, "[" + selected + "](" + text.trim() + ")");
    }, true);

    // Deterministic diagnostic hook for the shipped headless harnesses. It calls
    // the same QOL helpers as the real key/paste listeners without depending on
    // WebKit synthetic key-event delivery, which can hang under off-screen tests.
    window.__ouroQOLTest = {
      key: function (key) {
        if (!selectionInEditor()) { return false; }
        var selected = selectedText();
        if (selected) {
          var close = WRAP_PAIRS[key];
          if (close === undefined) { return false; }
          wrapSelection(key, close, selected);
          return true;
        }
        return handleAutoPair({
          key: key,
          metaKey: false,
          ctrlKey: false,
          altKey: false,
          isComposing: false
        });
      },
      pastePlainText: function (text) {
        if (!selectionInEditor()) { return false; }
        var selected = selectedText();
        text = (text || "").trim();
        if (!selected || !looksLikeURL(text)) { return false; }
        document.execCommand("insertText", false, "[" + selected + "](" + text + ")");
        return true;
      }
    };

    // ⌘-click a link to open it in the default browser. A contenteditable
    // surface never fires WebKit's .linkActivated navigation, and Vditor's own
    // window.open is dropped because the app installs no WKUIDelegate — so
    // without this, links are dead. We require ⌘ (not a plain click) so plain
    // clicks stay free for editing.
    //
    // We handle the gesture on BOTH `mousedown` and `click`, de-duped to fire
    // once. macOS WKWebView does not reliably synthesize a `click` for a
    // ⌘-click inside contenteditable (the mousedown often just places the caret
    // and no click follows), so a click-only handler silently does nothing on
    // the real app even though it works under synthetic dispatch. `mousedown` is
    // delivered reliably; `click` stays as a belt-and-suspenders fallback.
    function urlTokenAtPoint(x, y) {
      // Bare GFM autolinks (https://… or www.…) render as plain text in IR mode
      // — no <a> or link span to hit — so pull the URL token sitting under the
      // click point out of the text node.
      if (x == null || y == null || !document.caretRangeFromPoint) { return ""; }
      var r;
      try { r = document.caretRangeFromPoint(x, y); } catch (err) { return ""; }
      if (!r || !r.startContainer || r.startContainer.nodeType !== 3) { return ""; }
      var text = r.startContainer.nodeValue || "";
      var start = r.startOffset, end = r.startOffset;
      while (start > 0 && !/\s/.test(text.charAt(start - 1))) { start--; }
      while (end < text.length && !/\s/.test(text.charAt(end))) { end++; }
      var tok = text.slice(start, end).trim();
      // GFM autolinks exclude trailing punctuation and an unbalanced ")".
      tok = tok.replace(/[.,;:!?'"\u201c\u201d]+$/, "");
      if (/\)$/.test(tok) && tok.split("(").length <= tok.split(")").length) {
        tok = tok.replace(/\)+$/, "");
      }
      if (/^https?:\/\/\S+$/i.test(tok)) { return tok; }
      if (/^www\.[^\s]+\.[^\s]+$/i.test(tok)) { return "https://" + tok; }
      return "";
    }

    function resolveEditorLinkURL(target, e) {
      if (!target || !target.closest || !target.closest("#editor")) { return ""; }
      // WYSIWYG mode and the Split/preview pane render a real <a href>.
      var a = target.closest("a[href]");
      // Preserve the authored relative target. `a.href` resolves it against the
      // bundled editor HTML, which would point native code at the app resources
      // instead of beside the open Markdown document.
      if (a) { return a.getAttribute("href") || a.href || ""; }
      var reference = target.closest('span[data-type="link-ref"]');
      if (reference) { return resolveReferenceLinkURL(reference); }
      // IR (live-preview) mode renders a [text](url) / <url> link as a
      // <span data-type="a"> with no href — the URL is the text of its
      // .vditor-ir__marker--link child.
      var node = target.closest('span[data-type="a"]');
      var marker = node && node.querySelector(".vditor-ir__marker--link");
      if (marker) { return (marker.textContent || "").trim(); }
      // Bare autolink fallback: resolve a URL token under the click.
      if (e) { return urlTokenAtPoint(e.clientX, e.clientY); }
      return "";
    }

    function isLocalMarkdownTarget(url) {
      var target = (url || "").trim();
      if (target.charAt(0) === "<" && target.charAt(target.length - 1) === ">") {
        target = target.slice(1, -1).trim();
      }
      if (!target || target.charAt(0) === "#") { return false; }
      if (/^(https?|mailto|javascript|data):/i.test(target)) { return false; }
      var path = target.split("#", 1)[0].split("?", 1)[0];
      return /\.(md|markdown|mdown|mkd|mdtext)$/i.test(path);
    }

    var lastLinkOpenAt = 0;
    function maybeOpenEditorLink(e) {
      if (window.__ouroCaptureAnchorDiagnostics) { post("linkphase", { name: "link: resolving " + e.type }); }
      var url = resolveEditorLinkURL(e.target, e);
      if (window.__ouroCaptureAnchorDiagnostics) { post("linkphase", { name: "link: resolved " + (url || "<empty>") }); }
      if (!url) { return; }
      if (url.charAt(0) === "#") {
        if (e.type !== "click") { return; }
        e.preventDefault();
        e.stopImmediatePropagation();
        var root = e.target.closest(".vditor-reset") || renderedAnchorRoot();
        scrollToAnchorTarget(url.slice(1), root);
        return;
      }
      var localMarkdown = isLocalMarkdownTarget(url);
      // External links keep the established ⌘-click gesture so ordinary clicks
      // remain available for editing. A rendered local Markdown link opens on a
      // normal click: it stays inside Ouro MD, in another document window.
      if (!e.metaKey && !(localMarkdown && e.type === "click")) { return; }
      // Swallow the whole gesture (caret placement, Vditor handlers, the
      // synthesized click) so the link opens instead of editing/navigating.
      e.preventDefault();
      e.stopImmediatePropagation();
      // One open per gesture: mousedown fires first; the click ~ms later is
      // suppressed here without re-opening.
      var now = Date.now();
      if (now - lastLinkOpenAt < 700) { return; }
      lastLinkOpenAt = now;
      if (window.__ouroCaptureAnchorDiagnostics) { post("linkphase", { name: "link: posting " + url }); }
      post("openURL", { url: url });
    }
    document.addEventListener("mousedown", maybeOpenEditorLink, true);
    document.addEventListener("click", maybeOpenEditorLink, true);
  }

  function invalidateReferenceLinkCache() {
    referenceLinkCache = null;
    referenceLinkError = "";
    footnoteReservationCache = null;
  }

  function cancelAnchorRequests() {
    anchorRequestGeneration += 1;
  }

  function semanticNodeText(node) {
    var clone = node.cloneNode(true);
    Array.from(clone.querySelectorAll(".vditor-ir__marker")).forEach(function (child) { child.remove(); });
    Array.from(clone.querySelectorAll("img")).forEach(function (image) {
      image.replaceWith(document.createTextNode(image.getAttribute("alt") || ""));
    });
    Array.from(clone.querySelectorAll("br")).forEach(function (lineBreak) {
      lineBreak.replaceWith(document.createTextNode(" "));
    });
    return (clone.textContent || "").replace(/[ \t\r\n]+/g, " ").trim();
  }

  function normalizeReferenceDefinitionLabel(label) {
    var normalized = (label || "")
      .replace(/\\([\x21-\x2F\x3A-\x40\x5B-\x60\x7B-\x7E])/g, "$1")
      .replace(/^[ \t\r\n]+|[ \t\r\n]+$/g, "")
      .replace(/[ \t\r\n]+/g, " ");
    return window.__ouroUnicodeCaseFold(normalized);
  }

  function parseReferenceDefinitionLine(line) {
    var index = 0;
    while (line.charAt(index) === " " && index < 4) { index += 1; }
    if (index > 3 || line.charAt(index) === "\t" || line.charAt(index) !== "[") { return null; }
    index += 1;
    var rawLabel = "";
    var closed = false;
    while (index < line.length) {
      var ch = line.charAt(index);
      if (ch === "\\" && index + 1 < line.length) {
        rawLabel += ch + line.charAt(index + 1);
        index += 2;
        continue;
      }
      if (ch === "]" && line.charAt(index + 1) === ":") {
        index += 2;
        closed = true;
        break;
      }
      rawLabel += ch;
      index += 1;
    }
    if (!closed) { return null; }
    while (/[ \t\r\n]/.test(line.charAt(index))) { index += 1; }

    var destination = "";
    if (line.charAt(index) === "<") {
      index += 1;
      while (index < line.length) {
        var angle = line.charAt(index);
        if (angle === "\\" && index + 1 < line.length) {
          destination += angle + line.charAt(index + 1);
          index += 2;
          continue;
        }
        if (angle === ">") { break; }
        destination += angle;
        index += 1;
      }
      if (line.charAt(index) !== ">") { return null; }
    } else {
      while (index < line.length && !/[ \t\r\n]/.test(line.charAt(index))) {
        if (line.charAt(index) === "\\" && index + 1 < line.length) {
          destination += line.charAt(index) + line.charAt(index + 1);
          index += 2;
        } else {
          destination += line.charAt(index);
          index += 1;
        }
      }
    }

    var label = normalizeReferenceDefinitionLabel(rawLabel);
    destination = destination.replace(/\\([\x21-\x2F\x3A-\x40\x5B-\x60\x7B-\x7E])/g, "$1");
    return label && destination ? { label: label, destination: destination } : null;
  }

  function referenceLabelFromDOM(node) {
    var marker = Array.from(node.children).find(function (child) {
      return child.classList && child.classList.contains("vditor-ir__marker--link");
    });
    if (marker) {
      return normalizeReferenceDefinitionLabel(
        (marker.textContent || "").replace(/^\[/, "").replace(/\]$/, "")
      );
    }
    return normalizeReferenceDefinitionLabel(semanticNodeText(node));
  }

  function referenceLinkDestinations(root) {
    var markdown = state.value;
    var mode = vditor && vditor.vditor ? vditor.vditor.currentMode : state.mode;
    if (referenceLinkCache &&
        referenceLinkCache.markdown === markdown &&
        referenceLinkCache.mode === mode &&
        referenceLinkCache.root === root) {
      return referenceLinkCache.destinations;
    }

    var destinations = [];
    try {
      var references = Array.from(root.querySelectorAll('span[data-type="link-ref"]'));
      var definitions = Object.create(null);
      Array.from(root.querySelectorAll('[data-type="link-ref-defs-block"]')).forEach(function (block) {
        (block.textContent || "").split(/\r?\n/).forEach(function (line) {
          var definition = parseReferenceDefinitionLine(line);
          if (definition &&
              !Object.prototype.hasOwnProperty.call(definitions, definition.label)) {
            definitions[definition.label] = definition.destination;
          }
        });
      });
      destinations = references.map(function (reference) {
        var label = referenceLabelFromDOM(reference);
        return label && Object.prototype.hasOwnProperty.call(definitions, label)
          ? definitions[label]
          : "";
      });
    } catch (error) {
      referenceLinkError = error
        ? "name=" + (error.name || "") + " message=" + (error.message || "") + " stack=" + (error.stack || "")
        : "unknown reference-link error";
      destinations = [];
    }
    referenceLinkCache = { markdown: markdown, mode: mode, root: root, destinations: destinations };
    return destinations;
  }

  function resolveReferenceLinkURL(node) {
    var root = node.closest(".vditor-reset");
    if (!root) { return ""; }
    var references = Array.from(root.querySelectorAll('span[data-type="link-ref"]'));
    var index = references.indexOf(node);
    return index >= 0 ? (referenceLinkDestinations(root)[index] || "") : "";
  }

  function headingBaseSlug(text) {
    var normalized = (text || "").normalize("NFC").toLowerCase().normalize("NFC");
    var out = "";
    for (var ch of normalized) {
      if (/[\p{L}\p{N}]/u.test(ch)) {
        out += ch;
      } else if (ch === " " || ch === "-" || ch === "_") {
        out += "-";
      }
    }
    while (out.indexOf("--") !== -1) { out = out.replace(/--/g, "-"); }
    out = out.replace(/^-+|-+$/g, "");
    return out || "section";
  }

  function nextUniqueHeadingSlug(base, counts, used) {
    var occurrence = counts[base] || 0;
    var candidate = occurrence === 0 ? base : base + "-" + occurrence;
    while (used[candidate]) {
      occurrence += 1;
      candidate = base + "-" + occurrence;
    }
    counts[base] = occurrence + 1;
    used[candidate] = true;
    return candidate;
  }

  function headingText(heading) {
    var clone = heading.cloneNode(true);
    var markers = clone.querySelectorAll(".vditor-ir__marker");
    for (var i = 0; i < markers.length; i++) { markers[i].remove(); }
    var images = clone.querySelectorAll("img");
    for (var j = 0; j < images.length; j++) {
      images[j].replaceWith(document.createTextNode(images[j].getAttribute("alt") || ""));
    }
    var breaks = clone.querySelectorAll("br");
    for (var k = 0; k < breaks.length; k++) {
      breaks[k].replaceWith(document.createTextNode(" "));
    }
    return (clone.textContent || "").replace(/\r\n?|\n/g, " ").trim();
  }

  function isHTMLHeading(node) {
    return !!node &&
      node.namespaceURI === "http://www.w3.org/1999/xhtml" &&
      /^H[1-6]$/.test(node.tagName || "");
  }

  function reserveNonHeadingIDs(root, used) {
    Array.from(root.querySelectorAll("[id]")).forEach(function (node) {
      if (!isHTMLHeading(node) && node.id) { used[node.id] = true; }
    });
  }

  function legacyFootnoteSlug(label, index) {
    var lower = (label || "").toLowerCase();
    var segments = typeof Intl !== "undefined" && Intl.Segmenter
      ? Array.from(new Intl.Segmenter(undefined, { granularity: "grapheme" }).segment(lower), function (item) {
          return item.segment;
        })
      : Array.from(lower);
    var out = "";
    for (var i = 0; i < segments.length; i++) {
      var segment = segments[i];
      if (/[\p{L}\p{N}]/u.test(segment)) {
        out += segment;
      } else if (segment === " " || segment === "-" || segment === "_") {
        out += "-";
      }
    }
    while (out.indexOf("--") !== -1) { out = out.replace(/--/g, "-"); }
    out = out.replace(/^-+|-+$/g, "");
    return out || "footnote-" + index;
  }

  function footnoteIndentWidth(line) {
    var width = 0;
    for (var i = 0; i < line.length; i++) {
      if (line.charAt(i) === " ") {
        width += 1;
      } else if (line.charAt(i) === "\t") {
        width += 4;
      } else {
        break;
      }
    }
    return width;
  }

  function footnoteFence(line) {
    if (footnoteIndentWidth(line) > 3) { return null; }
    var trimmed = line.trim();
    var marker = trimmed.charAt(0);
    if (marker !== "`" && marker !== "~") { return null; }
    var length = 0;
    while (trimmed.charAt(length) === marker) { length += 1; }
    return length >= 3 ? { marker: marker, length: length } : null;
  }

  function footnoteDefinitionLabel(line) {
    if (footnoteIndentWidth(line) > 3) { return ""; }
    var trimmed = line.trim();
    if (trimmed.slice(0, 2) !== "[^") { return ""; }
    var close = trimmed.indexOf("]:", 2);
    if (close < 0) { return ""; }
    return trimmed.slice(2, close);
  }

  function footnoteSource(markdown) {
    var lines = (markdown || "").split("\n");
    var body = [];
    var definitions = [];
    var seen = Object.create(null);
    var activeDefinition = -1;
    var activeFence = null;

    lines.forEach(function (line) {
      var fence = footnoteFence(line);
      if (fence) {
        activeDefinition = -1;
        if (activeFence) {
          if (fence.marker === activeFence.marker && fence.length >= activeFence.length) {
            activeFence = null;
          }
        } else {
          activeFence = fence;
        }
        body.push(line);
        return;
      }
      if (activeFence) {
        body.push(line);
        return;
      }

      var label = footnoteDefinitionLabel(line);
      if (label) {
        if (!Object.prototype.hasOwnProperty.call(seen, label)) {
          seen[label] = true;
          definitions.push(label);
          activeDefinition = definitions.length - 1;
        } else {
          activeDefinition = -1;
        }
        return;
      }
      if (activeDefinition >= 0 && line.trim() === "") { return; }
      if (activeDefinition >= 0 && (line.slice(0, 4) === "    " || line.charAt(0) === "\t")) {
        return;
      }
      activeDefinition = -1;
      body.push(line);
    });

    return { definitions: definitions, body: body.join("\n") };
  }

  function footnoteReferenceCounts(markdown, defined) {
    var counts = Object.create(null);
    var activeFence = null;
    (markdown || "").split("\n").forEach(function (line) {
      var fence = footnoteFence(line);
      if (fence) {
        if (activeFence) {
          if (fence.marker === activeFence.marker && fence.length >= activeFence.length) {
            activeFence = null;
          }
        } else {
          activeFence = fence;
        }
        return;
      }
      if (activeFence || footnoteIndentWidth(line) >= 4) { return; }

      var index = 0;
      var backtickRun = 0;
      while (index < line.length) {
        var ch = line.charAt(index);
        if (ch === "\\") {
          index += 2;
          continue;
        }
        if (ch === "`") {
          var run = 1;
          while (line.charAt(index + run) === "`") { run += 1; }
          backtickRun = backtickRun === run ? 0 : (backtickRun === 0 ? run : backtickRun);
          index += run;
          continue;
        }
        if (backtickRun === 0 && line.slice(index, index + 2) === "[^") {
          var close = line.indexOf("]", index + 2);
          if (close >= 0) {
            var label = line.slice(index + 2, close);
            if (Object.prototype.hasOwnProperty.call(defined, label)) {
              counts[label] = (counts[label] || 0) + 1;
            }
            index = close + 1;
            continue;
          }
        }
        index += 1;
      }
    });
    return counts;
  }

  function footnoteReservationsForMarkdown(markdown) {
    var source = footnoteSource(markdown);
    var idsByLabel = Object.create(null);
    var used = Object.create(null);
    source.definitions.forEach(function (label, offset) {
      var base = legacyFootnoteSlug(label, offset + 1);
      var candidate = base;
      var suffix = 1;
      while (used[candidate]) {
        candidate = base + "-" + suffix;
        suffix += 1;
      }
      used[candidate] = true;
      idsByLabel[label] = candidate;
    });
    var counts = footnoteReferenceCounts(source.body, idsByLabel);
    var reservations = [];
    source.definitions.forEach(function (label, offset) {
      var number = offset + 1;
      var custom = idsByLabel[label];
      var referenceCount = Math.max(1, counts[label] || 0);
      reservations.push("fn-" + custom, "footnotes-def-" + number);
      for (var i = 1; i <= referenceCount; i++) {
        reservations.push(i === 1 ? "fnref-" + custom : "fnref-" + custom + "-" + i);
        reservations.push(i === 1 ? "footnotes-ref-" + number : "footnotes-ref-" + number + ":" + i);
      }
    });
    return reservations;
  }

  function reserveCrossRendererFootnoteIDs(used) {
    try {
      var markdown = state.value;
      var reservations;
      if (footnoteReservationCache && footnoteReservationCache.markdown === markdown) {
        reservations = footnoteReservationCache.ids;
      } else {
        reservations = markdown.indexOf("[^") === -1 ? [] : footnoteReservationsForMarkdown(markdown);
        footnoteReservationCache = { markdown: markdown, ids: reservations };
      }
      reservations.forEach(function (id) { used[id] = true; });
    } catch (error) {
      // Existing rendered IDs are still reserved by reserveNonHeadingIDs.
    }
  }

  function headingAnchorMap(root) {
    var counts = Object.create(null);
    var used = Object.create(null);
    reserveNonHeadingIDs(root, used);
    reserveCrossRendererFootnoteIDs(used);
    var anchors = Object.create(null);
    var headings = Array.from(root.querySelectorAll("h1,h2,h3,h4,h5,h6")).filter(isHTMLHeading);
    for (var i = 0; i < headings.length; i++) {
      var base = headingBaseSlug(headingText(headings[i]));
      var slug = nextUniqueHeadingSlug(base, counts, used);
      anchors[slug] = headings[i];
    }
    return anchors;
  }

  function headingIDsForHTML(html) {
    var parsed = new DOMParser().parseFromString(html || "", "text/html");
    var counts = Object.create(null);
    var used = Object.create(null);
    reserveNonHeadingIDs(parsed, used);
    reserveCrossRendererFootnoteIDs(used);
    return Array.from(parsed.querySelectorAll("h1,h2,h3,h4,h5,h6")).filter(isHTMLHeading).map(function (heading) {
      var base = headingBaseSlug(headingText(heading));
      return nextUniqueHeadingSlug(base, counts, used);
    });
  }

  function headingOpeningTagEnd(html, start) {
    var state = "tag-name";
    var quote = "";
    for (var i = start + 1; i < html.length; i++) {
      var ch = html.charAt(i);
      if (quote) {
        if (ch === quote) { quote = ""; }
      } else if (ch === ">") {
        return i;
      } else if (state === "tag-name") {
        if (/\s/.test(ch)) { state = "before-attribute"; }
      } else if (state === "before-attribute") {
        if (/\s/.test(ch) || ch === "/") { continue; }
        state = "attribute-name";
      } else if (state === "attribute-name") {
        if (ch === "=") {
          state = "before-value";
        } else if (/\s/.test(ch)) {
          state = "after-attribute";
        }
      } else if (state === "after-attribute") {
        if (ch === "=") {
          state = "before-value";
        } else if (!/\s/.test(ch)) {
          state = ch === "/" ? "before-attribute" : "attribute-name";
        }
      } else if (state === "before-value") {
        if (/\s/.test(ch)) { continue; }
        if (ch === '"' || ch === "'") {
          quote = ch;
          state = "before-attribute";
        } else {
          state = "unquoted-value";
        }
      } else if (state === "unquoted-value" && /\s/.test(ch)) {
        state = "before-attribute";
      }
    }
    return -1;
  }

  function openingTagAttributes(tag) {
    var attributes = Object.create(null);
    var nameEnd = 1;
    while (nameEnd < tag.length && /[A-Za-z0-9:-]/.test(tag.charAt(nameEnd))) { nameEnd += 1; }
    var i = nameEnd;
    while (i < tag.length - 1) {
      while (i < tag.length - 1 && /\s/.test(tag.charAt(i))) { i += 1; }
      if (tag.charAt(i) === ">" || tag.charAt(i) === "/") { break; }
      var attributeStart = i;
      while (i < tag.length - 1 && !/[\s=/>]/.test(tag.charAt(i))) { i += 1; }
      var attributeName = tag.slice(attributeStart, i).toLowerCase();
      while (i < tag.length - 1 && /\s/.test(tag.charAt(i))) { i += 1; }
      var value = "";
      if (tag.charAt(i) === "=") {
        i += 1;
        while (i < tag.length - 1 && /\s/.test(tag.charAt(i))) { i += 1; }
        var quote = tag.charAt(i);
        if (quote === '"' || quote === "'") {
          var valueStart = i + 1;
          var valueEnd = tag.indexOf(quote, valueStart);
          if (valueEnd < 0) { valueEnd = tag.length - 1; }
          value = tag.slice(valueStart, valueEnd);
          i = valueEnd + 1;
        } else {
          var unquotedStart = i;
          while (i < tag.length - 1 && !/[\s>]/.test(tag.charAt(i))) { i += 1; }
          value = tag.slice(unquotedStart, i);
        }
      }
      if (attributeName && !Object.prototype.hasOwnProperty.call(attributes, attributeName)) {
        attributes[attributeName] = value;
      }
    }
    return attributes;
  }

  function decodedHTMLAttributeValue(value) {
    var textarea = document.createElement("textarea");
    textarea.innerHTML = value || "";
    return textarea.value;
  }

  function escapeHeadingID(id) {
    return (id || "").replace(/&/g, "&amp;").replace(/"/g, "&quot;");
  }

  function replaceHeadingIDInTag(tag, id) {
    var desired = escapeHeadingID(id);
    var nameEnd = 1;
    while (nameEnd < tag.length && /[A-Za-z0-9:-]/.test(tag.charAt(nameEnd))) { nameEnd += 1; }
    var i = nameEnd;
    while (i < tag.length - 1) {
      while (i < tag.length - 1 && /\s/.test(tag.charAt(i))) { i += 1; }
      if (tag.charAt(i) === ">" || tag.charAt(i) === "/") { break; }
      var attributeStart = i;
      while (i < tag.length - 1 && !/[\s=/>]/.test(tag.charAt(i))) { i += 1; }
      var attributeName = tag.slice(attributeStart, i).toLowerCase();
      while (i < tag.length - 1 && /\s/.test(tag.charAt(i))) { i += 1; }
      if (tag.charAt(i) !== "=") {
        if (attributeName === "id") {
          return tag.slice(0, i) + '="' + desired + '"' + tag.slice(i);
        }
        continue;
      }
      i += 1;
      while (i < tag.length - 1 && /\s/.test(tag.charAt(i))) { i += 1; }
      var quote = tag.charAt(i);
      if (quote === '"' || quote === "'") {
        var valueStart = i + 1;
        var valueEnd = tag.indexOf(quote, valueStart);
        if (valueEnd < 0) { return tag; }
        if (attributeName === "id") {
          return tag.slice(0, valueStart) + desired + tag.slice(valueEnd);
        }
        i = valueEnd + 1;
      } else {
        var unquotedStart = i;
        while (i < tag.length - 1 && !/[\s>]/.test(tag.charAt(i))) { i += 1; }
        if (attributeName === "id") {
          return tag.slice(0, unquotedStart) + desired + tag.slice(i);
        }
      }
    }
    var insertion = tag.length - 1;
    if (tag.charAt(insertion - 1) === "/") { insertion -= 1; }
    return tag.slice(0, insertion) + ' id="' + desired + '"' + tag.slice(insertion);
  }

  function normalizeHeadingIDsInHTML(html) {
    var ids = headingIDsForHTML(html);
    if (ids.length === 0) { return html; }

    var output = "";
    var cursor = 0;
    var search = 0;
    var headingIndex = 0;
    var rawText = "";
    var templateDepth = 0;
    var foreignScopes = [];
    var openHTMLHeading = false;
    function inHTMLNamespace() {
      return foreignScopes.length === 0 ||
        foreignScopes[foreignScopes.length - 1].namespace === "html" ||
        foreignScopes[foreignScopes.length - 1].integratesHTML;
    }
    function foreignNamespace() {
      return foreignScopes.length === 0 ? "" : foreignScopes[foreignScopes.length - 1].namespace;
    }
    function closeForeignScope(tagName) {
      for (var i = foreignScopes.length - 1; i >= 0; i--) {
        if (foreignScopes[i].tagName === tagName) {
          foreignScopes.length = i;
          return;
        }
      }
    }
    var foreignBreakoutTags = {
      b: true, big: true, blockquote: true, body: true, br: true, center: true,
      code: true, dd: true, div: true, dl: true, dt: true, em: true, embed: true,
      h1: true, h2: true, h3: true, h4: true, h5: true, h6: true, head: true,
      hr: true, i: true, img: true, li: true, listing: true, menu: true, meta: true,
      nobr: true, ol: true, p: true, pre: true, ruby: true, s: true, small: true,
      span: true, strong: true, strike: true, sub: true, sup: true, table: true,
      tt: true, u: true, ul: true, var: true
    };
    var svgHTMLIntegrationPoints = { desc: true, foreignobject: true, title: true };
    var mathMLTextIntegrationPoints = { mi: true, mo: true, mn: true, ms: true, mtext: true };
    var mathMLTextExceptions = { malignmark: true, mglyph: true };
    var htmlVoidTags = {
      area: true, base: true, br: true, col: true, embed: true, hr: true, img: true,
      input: true, link: true, meta: true, param: true, source: true, track: true, wbr: true
    };
    while (search < html.length && headingIndex < ids.length) {
      if (rawText) {
        var rawClosing = new RegExp("</" + rawText + "(?=[\\s/>])", "ig");
        rawClosing.lastIndex = search;
        var close = rawClosing.exec(html);
        if (!close) { return html; }
        var rawEnd = headingOpeningTagEnd(html, close.index);
        if (rawEnd < 0) { return html; }
        closeForeignScope(rawText);
        search = rawEnd + 1;
        rawText = "";
        continue;
      }

      var start = html.indexOf("<", search);
      if (start < 0) { break; }
      if (html.slice(start, start + 4) === "<!--") {
        var commentEnd = html.indexOf("-->", start + 4);
        if (commentEnd < 0) { return html; }
        search = commentEnd + 3;
        continue;
      }
      if (html.slice(start, start + 9) === "<![CDATA[") {
        var cdataEnd = html.indexOf("]]>", start + 9);
        if (cdataEnd < 0) { return html; }
        search = cdataEnd + 3;
        continue;
      }
      if (html.charAt(start + 1) === "!" || html.charAt(start + 1) === "?") {
        var declarationEnd = headingOpeningTagEnd(html, start);
        if (declarationEnd < 0) { return html; }
        search = declarationEnd + 1;
        continue;
      }
      if (html.charAt(start + 1) === "/") {
        var closingNameStart = start + 2;
        var closingNameEnd = closingNameStart;
        while (closingNameEnd < html.length && /[A-Za-z0-9:-]/.test(html.charAt(closingNameEnd))) {
          closingNameEnd += 1;
        }
        var closingName = html.slice(closingNameStart, closingNameEnd).toLowerCase();
        var closingEnd = headingOpeningTagEnd(html, start);
        if (closingEnd < 0) { return html; }
        if (/^h[1-6]$/.test(closingName) && openHTMLHeading && !inHTMLNamespace()) {
          while (foreignScopes.length > 0 && !foreignScopes[foreignScopes.length - 1].integratesHTML) {
            foreignScopes.pop();
          }
        }
        if (/^h[1-6]$/.test(closingName) && inHTMLNamespace()) {
          openHTMLHeading = false;
        }
        if (closingName === "template" && inHTMLNamespace() && templateDepth > 0) {
          templateDepth -= 1;
        }
        closeForeignScope(closingName);
        search = closingEnd + 1;
        continue;
      }

      var nameStart = start + 1;
      var nameEnd = nameStart;
      while (nameEnd < html.length && /[A-Za-z0-9:-]/.test(html.charAt(nameEnd))) { nameEnd += 1; }
      if (nameEnd === nameStart) {
        search = start + 1;
        continue;
      }
      var tagName = html.slice(nameStart, nameEnd).toLowerCase();
      var end = headingOpeningTagEnd(html, start);
      if (end < 0) { return html; }
      var tag = html.slice(start, end + 1);
      var parsedAttributes = null;
      var fontBreakout = false;
      if (!inHTMLNamespace() && tagName === "font") {
        parsedAttributes = openingTagAttributes(tag);
        fontBreakout = Object.prototype.hasOwnProperty.call(parsedAttributes, "color") ||
          Object.prototype.hasOwnProperty.call(parsedAttributes, "face") ||
          Object.prototype.hasOwnProperty.call(parsedAttributes, "size");
      }
      if (!inHTMLNamespace() && (foreignBreakoutTags[tagName] || fontBreakout)) {
        while (foreignScopes.length > 0 && !foreignScopes[foreignScopes.length - 1].integratesHTML) {
          foreignScopes.pop();
        }
      }
      var integrationParent = foreignScopes.length > 0 ? foreignScopes[foreignScopes.length - 1] : null;
      var mathMLTextException = !!(integrationParent && integrationParent.integratesHTML &&
        integrationParent.namespace === "math" &&
        mathMLTextIntegrationPoints[integrationParent.tagName] && mathMLTextExceptions[tagName]);
      var htmlNamespace = inHTMLNamespace() && !mathMLTextException;
      var activeForeignNamespace = foreignNamespace();
      var selfClosing = /\/\s*>$/.test(tag);
      if (tagName === "template" && htmlNamespace) {
        templateDepth += 1;
      }
      if (htmlNamespace &&
          (tagName === "script" || tagName === "style" || tagName === "textarea" ||
           tagName === "title" || tagName === "xmp" || tagName === "iframe" ||
           tagName === "noembed" || tagName === "noframes")) {
        rawText = tagName;
      } else if (!htmlNamespace && !selfClosing && (tagName === "script" || tagName === "style")) {
        rawText = tagName;
      }
      if (htmlNamespace && templateDepth === 0 && /^h[1-6]$/.test(tagName)) {
        output += html.slice(cursor, start) + replaceHeadingIDInTag(tag, ids[headingIndex]);
        cursor = end + 1;
        headingIndex += 1;
        openHTMLHeading = true;
      }
      if (htmlNamespace && (tagName === "svg" || tagName === "math")) {
        if (!selfClosing) {
          foreignScopes.push({ tagName: tagName, namespace: tagName, integratesHTML: false });
        }
      } else if (!htmlNamespace && activeForeignNamespace === "svg" &&
                 svgHTMLIntegrationPoints[tagName]) {
        if (!selfClosing) {
          foreignScopes.push({ tagName: tagName, namespace: "svg", integratesHTML: true });
        }
      } else if (!htmlNamespace && activeForeignNamespace === "math" &&
                 mathMLTextIntegrationPoints[tagName]) {
        if (!selfClosing) {
          foreignScopes.push({ tagName: tagName, namespace: "math", integratesHTML: true });
        }
      } else if (mathMLTextException) {
        if (!selfClosing) {
          foreignScopes.push({ tagName: tagName, namespace: "math", integratesHTML: false });
        }
      } else if (!htmlNamespace && activeForeignNamespace === "math" &&
                 tagName === "annotation-xml") {
        parsedAttributes = parsedAttributes || openingTagAttributes(tag);
        var encoding = decodedHTMLAttributeValue(parsedAttributes.encoding || "").toLowerCase();
        if (!selfClosing && (encoding === "text/html" || encoding === "application/xhtml+xml")) {
            foreignScopes.push({ tagName: tagName, namespace: "math", integratesHTML: true });
        }
      } else if (htmlNamespace && foreignScopes.length > 0 && !htmlVoidTags[tagName]) {
        // HTML self-closing syntax is ignored for non-void elements.
        foreignScopes.push({ tagName: tagName, namespace: "html", integratesHTML: false });
      }
      search = end + 1;
    }
    if (headingIndex !== ids.length) { return html; }
    return output + html.slice(cursor);
  }

  function decodedFragment(fragment) {
    try { return decodeURIComponent(fragment || ""); } catch (error) { return fragment || ""; }
  }

  function scrollElementWithinRoot(target, root) {
    var container = target.parentElement;
    while (container && container !== document.body && container !== document.documentElement) {
      var style = getComputedStyle(container);
      var scrollable = (style.overflowY === "auto" || style.overflowY === "scroll") &&
        container.scrollHeight > container.clientHeight + 1;
      if (scrollable) {
        var toolbar = container.matches(".vditor-preview")
          ? container.querySelector(".vditor-preview__action")
          : null;
        var offset = toolbar ? toolbar.getBoundingClientRect().height : 0;
        container.scrollTop += target.getBoundingClientRect().top -
          container.getBoundingClientRect().top - offset;
        return;
      }
      container = container.parentElement;
    }

    var page = document.scrollingElement || document.documentElement;
    var before = page.scrollTop;
    target.scrollIntoView({ behavior: "auto", block: "start", inline: "nearest" });
    if (state.mode === "sv" && page.scrollTop !== before) {
      var preview = target.closest(".vditor-preview");
      var action = preview && preview.querySelector(".vditor-preview__action");
      if (action) { page.scrollTop = Math.max(0, page.scrollTop - action.getBoundingClientRect().height); }
    }
  }

  function scrollToAnchorTarget(fragment, root) {
    if (window.__ouroCaptureAnchorDiagnostics) { post("linkphase", { name: "anchor: lookup start " + fragment }); }
    if (!root) { return false; }
    var targetID = decodedFragment(fragment);
    if (!targetID) { return false; }

    var anchors = headingAnchorMap(root);
    if (window.__ouroCaptureAnchorDiagnostics) { post("linkphase", { name: "anchor: map complete " + fragment }); }
    var heading = anchors[targetID];
    if (heading) {
      scrollElementWithinRoot(heading, root);
      if (window.__ouroCaptureAnchorDiagnostics) { window.__ouroLastAnchor = targetID; }
      if (window.__ouroCaptureAnchorDiagnostics) { post("linkphase", { name: "anchor: heading scrolled " + fragment }); }
      return true;
    }

    var exact = document.getElementById(targetID);
    if (exact && root.contains(exact) && !/^H[1-6]$/.test(exact.tagName || "")) {
      scrollElementWithinRoot(exact, root);
      if (window.__ouroCaptureAnchorDiagnostics) { window.__ouroLastAnchor = targetID; }
      return true;
    }
    return false;
  }

  function renderedAnchorRoot() {
    if (state.mode === "sv") {
      return document.querySelector("#editor .vditor-preview .vditor-reset") ||
        document.querySelector("#editor .vditor-preview.vditor-reset");
    }
    return activeEditorRoot();
  }

  function scrollToAnchorWhenReady(fragment) {
    var requestGeneration = ++anchorRequestGeneration;
    var attempts = 0;
    var finished = false;
    var attempt = function () {
      if (finished || requestGeneration !== anchorRequestGeneration) { return; }
      if (scrollToAnchorTarget(fragment, renderedAnchorRoot())) {
        finished = true;
        return;
      }
      attempts += 1;
      if (attempts >= 24) { return; }
      requestAnimationFrame(function () { setTimeout(attempt, 20); });
    };
    attempt();
  }

  function create() {
    ready = false;
    document.body.classList.toggle("ouro-source-mode", state.mode === "sv");
    vditor = new Vditor("editor", {
      cdn: "vditor",
      mode: state.mode,
      value: state.value,
      placeholder: "Start writing — Markdown renders as you type.",
      theme: state.uiTheme,
      cache: { enable: false },
      toolbar: [],
      counter: { enable: false },
      outline: { enable: state.outline, position: "left" },
      typewriterMode: state.typewriter,
      preview: {
        delay: 80,
        hljs: { enable: true, lineNumber: false, style: state.codeTheme },
        math: { engine: "KaTeX", inlineDigit: true },
        markdown: {
          footnotes: true,
          gfmAutoLink: true,
          toc: false,
          autoSpace: false,
          fixTermTypo: false,
          listStyle: false,
          sanitize: false
        }
      },
      input: function (value) {
        state.value = value;
        invalidateReferenceLinkCache();
        cancelAnchorRequests();
        setDirty(true);
        postCount(value);
        schedulePostRender();
      },
      after: function () {
        ready = true;
        attachImageHandlers();
        installEditorQOL();
        postCount(state.value);
        window.__ouroEditor = vditor;   // exposed for headless undo/redo verification
        post("ready", {});
      }
    });
  }

  // Vditor has no live mode switch; recreate while preserving content.
  function rebuild() {
    if (vditor) {
      try { state.value = vditor.getValue(); } catch (e) { /* ignore */ }
      try { vditor.destroy(); } catch (e) { /* ignore */ }
      vditor = null;
    }
    var el = document.getElementById("editor");
    if (el) { el.innerHTML = ""; }
    invalidateReferenceLinkCache();
    cancelAnchorRequests();
    create();
  }

  // Inline pasted / dropped images as base64 data URIs so they display without
  // any web-view file-access permissions or an upload server.
  function attachImageHandlers() {
    var el = document.getElementById("editor");
    if (!el || el.__ouroImg) { return; }
    el.__ouroImg = true;
    el.addEventListener("paste", onTransfer, true);
    el.addEventListener("drop", onTransfer, true);
    // Mute the text selection when focus leaves the editor for the sidebar /
    // app chrome (the window-inactive case is handled in CSS via :window-inactive).
    // relatedTarget inside #editor means focus only moved between blocks — ignore.
    el.addEventListener("focusout", function (e) {
      if (e.relatedTarget && el.contains(e.relatedTarget)) { return; }
      document.body.classList.add("ouro-editor-blurred");
    });
    el.addEventListener("focusin", function () {
      document.body.classList.remove("ouro-editor-blurred");
    });
    attachCopyEnrichment();
    // Resolve relative image paths against the open document's folder so
    // images an agent referenced relatively actually display; style alerts.
    postRender();
    var observer = new MutationObserver(function () { postRender(); });
    observer.observe(el, { childList: true, characterData: true, subtree: true });
    // The body uses Open Sans, a web font loaded with font-display:swap. The
    // first postRender measures table widths against the fallback font; when Open
    // Sans swaps in, prose-cell metrics change and a borderline table can cross
    // its scroll threshold. Font loading doesn't mutate the DOM, so the observer
    // above won't catch it — re-run postRender on each font load so the scroll
    // affordance reflects the final (swapped-in) layout, not the fallback one.
    if (document.fonts && typeof document.fonts.addEventListener === "function") {
      document.fonts.addEventListener("loadingdone", function () { postRender(); });
    }
  }

  // Copy behavior. A single capture-phase handler serves both the default
  // Cmd+C / Edit ▸ Copy and the explicit Edit ▸ Copy as ▸ {Markdown, Plain
  // Text, Rendered HTML} commands (the latter set `pendingCopyMode` then fire a
  // synthetic copy). The paste TARGET picks the flavor it understands — we don't
  // sniff it:
  //   default  -> BOTH text/plain (Markdown) + text/html (rendered). Rich
  //               targets (Teams, Word, mail) paste formatted; plain targets
  //               (code, PRs, other markdown) take the Markdown.
  //   markdown -> text/plain = Markdown only.
  //   plain    -> text/plain = the visible text, Markdown symbols stripped.
  //   html     -> text/html = rendered HTML (formatted paste) + a plain-text
  //               fallback of the visible text.
  // Markdown is produced the way Vditor would (selection -> VditorIRDOM2Md) so
  // text/plain never regresses; the HTML is rendered from that Markdown
  // (Md2HTML) so no IR editor markup leaks in. Explicit modes fall back to the
  // whole document when there is no selection (matching the old menu's intent).
  var pendingCopyMode = null;
  function attachCopyEnrichment() {
    if (document.__ouroCopy) { return; }
    document.__ouroCopy = true;
    document.addEventListener("copy", function (e) {
      var mode = pendingCopyMode;
      pendingCopyMode = null;
      try {
        if (!vditor || !vditor.vditor || vditor.vditor.currentMode !== "ir") { return; }
        var lute = vditor.vditor.lute;
        if (!lute || !lute.VditorIRDOM2Md || !lute.Md2HTML) { return; }
        var sel = window.getSelection();
        var editorEl = document.getElementById("editor");
        var hasSelection = sel && sel.rangeCount > 0 && !sel.isCollapsed &&
          sel.toString() !== "" && editorEl && editorEl.contains(sel.anchorNode);
        var md, plain;
        if (hasSelection) {
          var temp = document.createElement("div");
          temp.appendChild(sel.getRangeAt(0).cloneContents());
          md = lute.VditorIRDOM2Md(temp.innerHTML).trim();
          plain = sel.toString();
        } else if (mode) {
          // Explicit Copy-as with no selection: operate on the whole document.
          md = (typeof vditor.getValue === "function" ? vditor.getValue() : "").trim();
          var content = document.querySelector("#editor .vditor-reset") || editorEl;
          plain = content ? (content.innerText || content.textContent || md) : md;
        } else {
          // Default copy with nothing selected in the editor — let the default run.
          return;
        }
        if (!md && !plain) { return; }
        var html = "";
        try { html = lute.Md2HTML(md); } catch (err) { html = ""; }

        if (mode === "markdown") {
          e.clipboardData.setData("text/plain", md);
        } else if (mode === "plain") {
          e.clipboardData.setData("text/plain", plain || md);
        } else if (mode === "html") {
          e.clipboardData.setData("text/plain", plain || md);
          if (html) { e.clipboardData.setData("text/html", html); }
        } else {
          e.clipboardData.setData("text/plain", md);
          if (html) { e.clipboardData.setData("text/html", html); }
        }
        e.preventDefault();
        e.stopImmediatePropagation();
      } catch (err) {
        // Any failure: fall through to the editor's default copy behavior.
      }
    }, true);
  }

  var docBase = "";

  // GitHub-style alerts (> [!NOTE] ...). Vditor has no native support, so we
  // decorate the editable DOM while keeping the marker text in place. The span
  // is display-only: Vditor can still round-trip the original Markdown marker.
  var ALERT_TYPES = {
    NOTE: { className: "note", label: "Note" },
    TIP: { className: "tip", label: "Tip" },
    IMPORTANT: { className: "important", label: "Important" },
    WARNING: { className: "warning", label: "Warning" },
    CAUTION: { className: "caution", label: "Caution" }
  };
  var ALERT_RE = /^(\s*)\[!(NOTE|TIP|IMPORTANT|WARNING|CAUTION)\](\s*)/i;
  var ALERT_MARKER_LINE_RE = /^\s*\[!(NOTE|TIP|IMPORTANT|WARNING|CAUTION)\]\s*$/i;
  var editingAlert = null;

  function removeAlertClasses(bq) {
    bq.className = bq.className.replace(/\bouro-alert(-\w+)?\b/g, "").replace(/\s+/g, " ").trim();
    bq.removeAttribute("data-ouro-alert-label");
  }

  function existingAlertMarker(bq) {
    var marker = bq.querySelector(".ouro-alert-marker");
    if (!marker) { return null; }
    var m = (marker.textContent || "").match(ALERT_RE);
    return m ? { type: m[2].toUpperCase(), marker: marker } : null;
  }

  function wrapAlertMarkerText(textNode, match) {
    var value = textNode.nodeValue || "";
    var matched = match[0] || "";
    var leading = match[1] || "";
    var type = match[2].toUpperCase();
    var trailing = match[3] || "";
    var markerText = matched.slice(leading.length, matched.length - trailing.length);
    var parent = textNode.parentNode;
    if (!parent) { return null; }

    var frag = document.createDocumentFragment();
    if (leading) { frag.appendChild(document.createTextNode(leading)); }
    var marker = document.createElement("span");
    marker.className = "ouro-alert-marker";
    marker.setAttribute("data-ouro-alert-type", type);
    marker.setAttribute("spellcheck", "false");
    marker.textContent = markerText;
    frag.appendChild(marker);
    if (trailing) { frag.appendChild(document.createTextNode(trailing)); }
    var suffix = value.slice(matched.length);
    if (suffix) { frag.appendChild(document.createTextNode(suffix)); }
    parent.replaceChild(frag, textNode);
    return marker;
  }

  function currentMarkdown() {
    try { return vditor ? vditor.getValue() : state.value; } catch (e) { return state.value; }
  }

  function alertEntriesFromMarkdown(markdown) {
    var lines = (markdown || "").replace(/\r\n?/g, "\n").split("\n");
    var entries = [];
    var inFence = null;
    function fence(line) {
      var m = line.match(/^ {0,3}(`{3,}|~{3,})/);
      return m ? { ch: m[1].charAt(0), len: m[1].length } : null;
    }
    function closesFence(line, f) {
      if (!f) { return false; }
      var m = line.match(/^ {0,3}(`{3,}|~{3,})/);
      return !!(m && m[1].charAt(0) === f.ch && m[1].length >= f.len);
    }
    var listStack = [];
    function leadingSpaces(line) {
      var m = line.match(/^ */);
      return m ? m[0].length : 0;
    }
    function listMarker(line) {
      var m = line.match(/^( {0,3})(?:[-+*]|\d{1,9}[.)])([ \t]+)/);
      return m ? { contentIndent: m[0].length } : null;
    }
    function updateListContext(line) {
      if (!line.trim()) { return; }
      var indent = leadingSpaces(line);
      while (listStack.length && indent < listStack[listStack.length - 1].contentIndent) {
        listStack.pop();
      }
      var marker = listMarker(line);
      if (marker) {
        while (listStack.length && marker.contentIndent <= listStack[listStack.length - 1].contentIndent) {
          listStack.pop();
        }
        listStack.push(marker);
      }
    }
    function insideList(line) {
      if (!listStack.length) { return false; }
      return leadingSpaces(line) >= listStack[listStack.length - 1].contentIndent;
    }
    // CommonMark allows 0-3 leading spaces before a top-level blockquote.
    // Quote lines indented into an active list item are list content instead,
    // and must not shift pairing against top-level rendered blockquotes.
    function isTopLevelQuote(line) {
      return /^ {0,3}>/.test(line) && !insideList(line);
    }
    function quoteContent(line) {
      return line.replace(/^ {0,3}> ?/, "");
    }
    function markerEntry(content) {
      var m = (content || "").match(ALERT_MARKER_LINE_RE);
      return m ? { type: m[1].toUpperCase() } : null;
    }
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i];
      updateListContext(line);
      if (inFence) {
        if (closesFence(line, inFence)) { inFence = null; }
        continue;
      }
      var f = fence(line);
      if (f) {
        inFence = f;
        continue;
      }
      if (!isTopLevelQuote(line)) { continue; }
      var firstContent = "";
      var foundFirst = false;
      while (i < lines.length) {
        line = lines[i];
        if (isTopLevelQuote(line)) {
          var content = quoteContent(line);
          if (!foundFirst && content.trim()) {
            firstContent = content;
            foundFirst = true;
          }
          i++;
          continue;
        }
        if (!line.trim()) { break; }
        i++;
      }
      entries.push(markerEntry(firstContent));
    }
    return entries;
  }

  function topLevelBlockquotes() {
    var root = document.querySelector(".vditor-reset");
    var bqs = document.querySelectorAll(".vditor-reset blockquote");
    var out = [];
    for (var i = 0; i < bqs.length; i++) {
      var bq = bqs[i];
      var parent = bq.parentElement;
      var nested = false;
      while (parent && parent !== root) {
        if (parent.matches && parent.matches("blockquote, li, td, th")) {
          nested = true;
          break;
        }
        parent = parent.parentElement;
      }
      if (!nested) { out.push(bq); }
    }
    return out;
  }

  function findAlertMarkerText(node) {
    for (var child = node.firstChild; child; child = child.nextSibling) {
      if (child.nodeType === 3) {
        var m = (child.nodeValue || "").match(ALERT_RE);
        if (m) { return { type: m[2].toUpperCase(), marker: wrapAlertMarkerText(child, m) }; }
        continue;
      }
      if (child.nodeType !== 1) { continue; }
      if (child.matches && child.matches(".ouro-alert-marker")) { continue; }
      if (child.matches && child.matches("code, pre, blockquote")) { continue; }
      var found = findAlertMarkerText(child);
      if (found) { return found; }
    }
    return null;
  }

  function styleAlerts() {
    var all = document.querySelectorAll(".vditor-reset blockquote");
    for (var i = 0; i < all.length; i++) { removeAlertClasses(all[i]); }
    var entries = alertEntriesFromMarkdown(currentMarkdown());
    var bqs = topLevelBlockquotes();
    for (var j = 0; j < bqs.length; j++) {
      var entry = entries[j];
      if (!entry || !ALERT_TYPES[entry.type]) { continue; }
      var bq = bqs[j];
      var alert = existingAlertMarker(bq) || findAlertMarkerText(bq);
      if (!alert || alert.type !== entry.type) { continue; }
      var meta = ALERT_TYPES[entry.type];
      bq.classList.add("ouro-alert");
      bq.classList.add("ouro-alert-" + meta.className);
      bq.setAttribute("data-ouro-alert-label", meta.label);
    }
  }

  function updateAlertEditing() {
    if (editingAlert && !editingAlert.isConnected) { editingAlert = null; }
    var sel = window.getSelection();
    var node = sel && sel.anchorNode;
    var el = node && (node.nodeType === 1 ? node : node.parentElement);
    var next = el && el.closest ? el.closest(".vditor-reset blockquote.ouro-alert") : null;
    if (editingAlert && editingAlert !== next) { editingAlert.classList.remove("ouro-callout-editing"); }
    if (next) { next.classList.add("ouro-callout-editing"); }
    editingAlert = next;
  }

  function postRender() {
    try { restoreTableCellSpaces(true); } catch (e) { /* never block a render */ }
    rewriteRelativeImages();
    styleAlerts();
    updateAlertEditing();
    annotateTableCellSizing();
    annotateNoOrphanGlue();
    annotateScrollableTables();
    resetTableScrollIfNeeded();
    resetNewTableScroll(document);
  }

  // Tables are centered and capped at the reading column in pure CSS
  // (margin:auto + max-width:100% in the theme), so JS only needs to flag tables
  // that overflow their own box, to paint the right-edge scroll affordance.
  function annotateScrollableTables() {
    var tables = document.querySelectorAll(".vditor-reset table");
    for (var i = 0; i < tables.length; i++) {
      var t = tables[i];
      t.classList.toggle("ouro-table-scrollable", t.scrollWidth - t.clientWidth > 2);
    }
  }

  // Per-cell sizing, mirroring MarkdownRenderer.cellSizingClass for the live
  // editor (Vditor builds the table DOM itself, so the Swift renderer's classes
  // aren't present here). Short cells get nothing and shrink, so a narrow table
  // stays thin and flush-left. Two kinds of cell keep a readable floor instead
  // of collapsing when a wide table is compressed: a code-only cell sizes to the
  // code's natural width, and a cell with substantial text keeps a minimum width.
  function annotateTableCellSizing() {
    var cells = document.querySelectorAll(".vditor-reset th,.vditor-reset td");
    for (var i = 0; i < cells.length; i++) {
      var cell = cells[i];
      cell.classList.remove("ouro-code-only-cell");
      cell.classList.remove("ouro-long-cell");
      var codes = cell.querySelectorAll("code");
      // A cell that is exactly one inline-code span (ignoring Vditor's backtick
      // markers) sizes to the code's natural width. querySelectorAll + the
      // backtick strip make this robust to Vditor's IR marker spans, which a
      // firstElementChild === <code> check would miss.
      if (codes.length === 1 &&
          (cell.textContent || "").replace(/`/g, "").trim() === (codes[0].textContent || "").trim()) {
        cell.classList.add("ouro-code-only-cell");
        continue;
      }
      // Substantial text, or any inline code (code can't wrap, so a squeezed
      // column would clip it into a ribbon), keeps a readable minimum width.
      if ((cell.textContent || "").trim().length >= 24 || codes.length > 0) {
        cell.classList.add("ouro-long-cell");
      }
    }
  }

  // Keep a line wrap from orphaning a leading list-style enumerator from its
  // word ("3.⏎Instructions") or a bracket from the inline code/link it hugs
  // ("(code⏎)"). We surround the run with a white-space:nowrap span. This is a
  // render-only decoration: it provably does not change getValue (the Markdown
  // round-trips byte-identically — see --wrapgluetest), and Vditor regenerates
  // the DOM on every render, so these spans are transient and re-applied.
  var ENUM_RE = /^(\s*)((?:\d{1,3}|[a-zA-Z]|[ivxlcdm]{1,6}|[IVXLCDM]{1,6})[.)])(\s+)(\S+)/;

  function annotateNoOrphanGlue() {
    var blocks = document.querySelectorAll(
      "#editor p,#editor li,#editor td,#editor th,#editor h1,#editor h2,#editor h3,#editor h4,#editor h5,#editor h6");
    for (var i = 0; i < blocks.length; i++) { glueLeadingEnumerator(blocks[i]); }
    var atoms = document.querySelectorAll('#editor span[data-type="code"],#editor span[data-type="a"]');
    for (var j = 0; j < atoms.length; j++) { glueBracketedAtom(atoms[j]); }
  }

  function glueLeadingEnumerator(block) {
    var walker = document.createTreeWalker(block, NodeFilter.SHOW_TEXT, {
      acceptNode: function (n) {
        if (!n.nodeValue || !n.nodeValue.trim()) { return NodeFilter.FILTER_REJECT; }
        if (n.parentNode && n.parentNode.closest(".vditor-ir__marker,.ouro-nowrap")) {
          return NodeFilter.FILTER_REJECT;
        }
        return NodeFilter.FILTER_ACCEPT;
      }
    });
    var node = walker.nextNode();
    if (!node) { return; }
    var m = ENUM_RE.exec(node.nodeValue);
    if (!m) { return; }
    var end = m[1].length + m[2].length + m[3].length + m[4].length;
    if (end > node.nodeValue.length) { return; }
    wrapRange(node, m[1].length, node, end);
  }

  function glueBracketedAtom(atom) {
    if (atom.parentNode && atom.parentNode.closest(".ouro-nowrap")) { return; }
    var prev = atom.previousSibling, next = atom.nextSibling;
    if (!prev || prev.nodeType !== 3 || !next || next.nodeType !== 3) { return; }
    var open = /([(\[{])(\s?)$/.exec(prev.nodeValue);
    var close = /^(\s?)([)\]}])/.exec(next.nodeValue);
    if (!open || !close) { return; }
    wrapRange(prev, prev.nodeValue.length - open[0].length, next, close[0].length);
  }

  function wrapRange(startNode, startOff, endNode, endOff) {
    try {
      var r = document.createRange();
      r.setStart(startNode, startOff);
      r.setEnd(endNode, endOff);
      var span = document.createElement("span");
      span.className = "ouro-nowrap";
      r.surroundContents(span);
    } catch (e) { /* leave the run as-is if the range can't be surrounded */ }
  }

  function schedulePostRender() {
    requestAnimationFrame(function () {
      postRender();
      requestAnimationFrame(postRender);
    });
  }

  function queueTableScrollReset() {
    resetTableScrollPending = true;
  }

  function resetTableScrollIfNeeded() {
    if (!resetTableScrollPending) { return; }
    resetTableScrollPending = false;
    resetTablesSeen = (typeof WeakSet === "function") ? new WeakSet() : null;
    resetAllTableScroll();
    requestAnimationFrame(resetAllTableScroll);
  }

  function tableWasReset(table) {
    return resetTablesSeen ? resetTablesSeen.has(table) : !!table.__ouroTableScrollReset;
  }

  function markTableReset(table) {
    if (resetTablesSeen) { resetTablesSeen.add(table); }
    table.__ouroTableScrollReset = true;
  }

  function resetAllTableScroll() {
    var tables = document.querySelectorAll(".vditor-reset table");
    for (var i = 0; i < tables.length; i++) {
      tables[i].scrollLeft = 0;
      markTableReset(tables[i]);
    }
  }

  function resetNewTableScroll(root) {
    var tables = [];
    if (root && root.matches && root.matches(".vditor-reset table")) {
      tables.push(root);
    }
    if (root && root.querySelectorAll) {
      var nested = root.querySelectorAll(".vditor-reset table");
      for (var i = 0; i < nested.length; i++) { tables.push(nested[i]); }
    }
    for (var j = 0; j < tables.length; j++) {
      if (tableWasReset(tables[j])) { continue; }
      tables[j].scrollLeft = 0;
      markTableReset(tables[j]);
    }
  }

  function rewriteRelativeImages() {
    if (!docBase) { return; }
    var imgs = document.querySelectorAll(".vditor-reset img");
    for (var i = 0; i < imgs.length; i++) {
      var src = imgs[i].getAttribute("src") || "";
      if (!src || /^(https?:|data:|file:|blob:)/i.test(src)) { continue; }
      var resolved = (src.charAt(0) === "/") ? ("file://" + src) : ("file://" + docBase + "/" + src);
      if (imgs[i].src !== resolved) { imgs[i].src = resolved; }
    }
  }

  function onTransfer(e) {
    var dt = e.clipboardData || e.dataTransfer;
    if (!dt) { return; }
    // Smart link: pasting a URL over a selection wraps it as a Markdown link.
    if (e.type === "paste" && dt.getData) {
      var text = dt.getData("text/plain");
      var sel = window.getSelection();
      if (text && /^https?:\/\/\S+$/.test(text.trim()) && sel && sel.toString().length > 0) {
        e.preventDefault();
        e.stopPropagation();
        insertAtCursor("[" + sel.toString() + "](" + text.trim() + ")");
        return;
      }
    }
    if (!dt.files || dt.files.length === 0) { return; }
    var imgs = [];
    for (var i = 0; i < dt.files.length; i++) {
      var f = dt.files[i];
      if (f.type && f.type.indexOf("image/") === 0) { imgs.push(f); }
    }
    if (imgs.length === 0) { return; }
    e.preventDefault();
    e.stopPropagation();
    imgs.forEach(function (file) {
      var reader = new FileReader();
      reader.onload = function () {
        if (vditor) {
          vditor.insertValue("\n![" + (file.name || "image") + "](" + reader.result + ")\n");
        }
      };
      reader.readAsDataURL(file);
    });
  }

  function wrapSelection(prefix, suffix) {
    var sel = window.getSelection();
    var selected = sel ? sel.toString() : "";
    document.execCommand("insertText", false, prefix + selected + suffix);
  }

  function insertAtCursor(text) {
    document.execCommand("insertText", false, text);
  }

  function textNodesUnder(root) {
    if (!root) { return []; }
    var walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, {
      acceptNode: function (node) {
        if (!node.nodeValue || !node.nodeValue.trim()) { return NodeFilter.FILTER_REJECT; }
        var parent = node.parentElement;
        if (parent && parent.closest && parent.closest("script,style")) { return NodeFilter.FILTER_REJECT; }
        return NodeFilter.FILTER_ACCEPT;
      }
    });
    var nodes = [];
    while (walker.nextNode()) { nodes.push(walker.currentNode); }
    return nodes;
  }

  function activeEditorRoot() {
    var roots = document.querySelectorAll("#editor .vditor-reset");
    for (var i = 0; i < roots.length; i++) {
      if (isVisibleTextRoot(roots[i])) { return roots[i]; }
    }
    for (var j = 0; j < roots.length; j++) {
      if ((roots[j].textContent || "").trim()) { return roots[j]; }
    }
    if (vditor && vditor.vditor) {
      var mode = vditor.vditor.currentMode || state.mode;
      var surface = vditor.vditor[mode] && vditor.vditor[mode].element;
      if (surface) { return surface; }
    }
    return document.querySelector(".vditor-reset") || document.getElementById("editor") || document.body;
  }

  function isVisibleTextRoot(root) {
    if (!root || !(root.textContent || "").trim()) { return false; }
    var style = window.getComputedStyle ? window.getComputedStyle(root) : null;
    if (style && (style.display === "none" || style.visibility === "hidden")) { return false; }
    var rect = root.getBoundingClientRect ? root.getBoundingClientRect() : null;
    return !!(rect && rect.width > 0 && rect.height > 0);
  }

  function selectTextRange(node, start, length) {
    if (!node || length <= 0) { return false; }
    recordRevealDiagnostic({
      phase: "selectTextRange",
      requested: node.nodeValue || "",
      start: start,
      length: length
    });
    var range = document.createRange();
    range.setStart(node, start);
    range.setEnd(node, start + length);
    var sel = window.getSelection();
    if (!sel) { return false; }
    sel.removeAllRanges();
    sel.addRange(range);
    var rect = range.getBoundingClientRect();
    var el = node.parentElement || node.parentNode;
    if (el && el.scrollIntoView) {
      el.scrollIntoView({ behavior: "smooth", block: "center", inline: "nearest" });
    } else if (rect && rect.top) {
      window.scrollTo({ top: Math.max(0, window.scrollY + rect.top - 120), behavior: "smooth" });
    }
    recordRevealDiagnostic({
      phase: "selected",
      requested: node.nodeValue || "",
      start: start,
      length: length,
      selection: String(sel),
      rangeCount: sel.rangeCount,
      anchorNode: sel.anchorNode ? sel.anchorNode.nodeName : ""
    });
    return true;
  }

  function recordRevealDiagnostic(payload) {
    if (window.__ouroCaptureRevealDiagnostics) { window.__ouroLastReveal = payload; }
  }

  function revealTextOccurrence(text, ordinal, caseSensitive) {
    if (!text) { return false; }
    var root = activeEditorRoot();
    var needle = caseSensitive ? text : text.toLowerCase();
    var seen = 0;
    var nodes = textNodesUnder(root);
    recordRevealDiagnostic({ phase: "text", needle: needle, ordinal: ordinal, nodes: nodes.length, root: root && root.className });
    for (var n = 0; n < nodes.length; n++) {
      var raw = nodes[n].nodeValue || "";
      var haystack = caseSensitive ? raw : raw.toLowerCase();
      var index = haystack.indexOf(needle);
      while (index !== -1) {
        if (seen === ordinal) { return selectTextRange(nodes[n], index, text.length); }
        seen += 1;
        index = haystack.indexOf(needle, index + Math.max(1, needle.length));
      }
    }
    return false;
  }

  function revealSearchOccurrence(query, opts, ordinal) {
    if (!query) { return false; }
    var re = buildSearchRegex(query, opts, true);
    if (!re) { return false; }
    var root = activeEditorRoot();
    var seen = 0;
    var nodes = textNodesUnder(root);
    recordRevealDiagnostic({ phase: "search", query: query, pattern: re.source, ordinal: ordinal, nodes: nodes.length, root: root && root.className });
    for (var n = 0; n < nodes.length; n++) {
      var raw = nodes[n].nodeValue || "";
      re.lastIndex = 0;
      var match;
      while ((match = re.exec(raw)) !== null) {
        var value = match[0] || "";
        if (value.length > 0) {
          if (seen === ordinal) { return selectTextRange(nodes[n], match.index, value.length); }
          seen += 1;
        }
        if (match.index === re.lastIndex) { re.lastIndex += 1; }
      }
    }
    return false;
  }

  // Replaces the current line's text via fn(oldLine) -> newLine.
  function transformLine(fn) {
    var sel = window.getSelection();
    if (!sel || sel.rangeCount === 0) { return; }
    sel.modify("move", "backward", "lineboundary");
    sel.modify("extend", "forward", "lineboundary");
    var line = sel.toString();
    insertAtCursor(fn(line));
  }

  function stripBlockMarkers(t) {
    return t.replace(/^\s*#{1,6}\s+/, "")
            .replace(/^\s*>\s?/, "")
            .replace(/^\s*- \[[ xX]\]\s+/, "")
            .replace(/^\s*[-*+]\s+/, "")
            .replace(/^\s*\d+\.\s+/, "");
  }

  // Focus mode: mark the top-level block containing the caret as .ouro-active.
  function updateActiveBlock() {
    var reset = document.querySelector(".vditor-reset");
    if (!reset) { return; }
    var sel = window.getSelection();
    if (!sel || !sel.anchorNode) { return; }
    var node = sel.anchorNode;
    while (node && node.parentNode !== reset) { node = node.parentNode; }
    var prev = reset.querySelector(".ouro-active");
    if (prev && prev !== node) { prev.classList.remove("ouro-active"); }
    if (node && node.nodeType === 1) { node.classList.add("ouro-active"); }
  }

  // Vditor/lute's editor-DOM builder drops the single space before an inline-
  // format run (**bold**, `code`, [text](url)) INSIDE A TABLE CELL — a silent,
  // repeatable round-trip corruption (`see the **bold**` -> `see the**bold**`).
  // lute's own Md2HTML keeps the space; only the Vditor-DOM path drops it, and
  // only in table cells (prose is unaffected). lute is GopherJS-compiled and not
  // patchable, so we restore the space at the DOM level right before
  // serialization. Working on the DOM (not the Markdown string) keeps it
  // precise: we only touch a text-node -> inline-format-element boundary, so a
  // closing `**`, an array index like `arr[0]` (plain text, not an inline node),
  // or `2*3` are never affected.
  function isInlineFormatEl(el) {
    if (!el || el.nodeType !== 1) { return false; }
    var dt = el.getAttribute && el.getAttribute("data-type");   // IR-mode spans
    if (dt && /^(strong|em|s|del|mark|code|a|u|sub|sup|inline-)/.test(dt)) { return true; }
    var tag = el.nodeName;                                       // WYSIWYG / preview
    return tag === "STRONG" || tag === "EM" || tag === "CODE" || tag === "A" ||
           tag === "DEL" || tag === "S" || tag === "MARK" || tag === "U" ||
           tag === "SUB" || tag === "SUP" || tag === "B" || tag === "I";
  }
  function restoreTableCellSpaces(skipFocusedCell) {
    var editorEl = document.getElementById("editor");
    if (!editorEl) { return; }
    // While a cell is being actively edited, leave it alone so a mid-word caret
    // is never nudged; getValue() (and the next render after the caret leaves)
    // still repairs it. Only matters for the render-time pass.
    var focusedCell = null;
    if (skipFocusedCell) {
      var sel = window.getSelection();
      var anchor = sel && sel.anchorNode;
      var el = anchor && (anchor.nodeType === 1 ? anchor : anchor.parentElement);
      focusedCell = (el && el.closest) ? el.closest("td, th") : null;
    }
    var cells = editorEl.querySelectorAll("table td, table th");
    for (var i = 0; i < cells.length; i++) {
      if (cells[i] === focusedCell) { continue; }
      var child = cells[i].firstChild;
      while (child) {
        var next = child.nextSibling;
        // A text node butting directly against an inline-format element is where
        // the boundary space was dropped. Restore it unless the text already
        // ends in whitespace or an opening delimiter (where no space belonged).
        if (child.nodeType === 3 && isInlineFormatEl(next)) {
          var t = child.nodeValue || "";
          if (t && !/[\s([{<"'\u201c\u2018\u00ab]$/.test(t)) { child.nodeValue = t + " "; }
        }
        child = next;
      }
    }
  }

  window.__ouroAnchorTest = {
    slugs: function (texts) {
      var counts = Object.create(null);
      var used = Object.create(null);
      return (texts || []).map(function (text) {
        var base = headingBaseSlug((text || "").replace(/\r\n?|\n/g, " "));
        return nextUniqueHeadingSlug(base, counts, used);
      });
    },
    normalizeHTML: normalizeHeadingIDsInHTML,
    footnoteReservations: footnoteReservationsForMarkdown,
    anchorGeneration: function () { return anchorRequestGeneration; },
    referenceDestinations: function () {
      return referenceLinkDestinations(activeEditorRoot());
    },
    referenceError: function () { return referenceLinkError; }
  };

  window.ouro = {
    setValue: function (md) {
      state.value = (md == null) ? "" : md;
      invalidateReferenceLinkCache();
      cancelAnchorRequests();
      if (vditor && ready) { vditor.setValue(state.value, true); }
      queueTableScrollReset();
      schedulePostRender();
      dirty = false;
      postCount(state.value);
    },
    // Synchronously recompute the layout-derived decorations (table cell sizing
    // and the scroll affordance) against the CURRENT layout. Decorations are
    // normally applied on a render frame, so a caller that measures immediately
    // after a late layout change (font swap, etc.) can call this first to avoid
    // reading a stale affordance. Used by the headless table-wrap probe.
    refreshDecorations: function () { postRender(); },
    reloadValue: function (md) {
      // Like setValue, but preserves the reader's scroll position — used when
      // the open file is rewritten externally (agent edit) and we live-reload.
      var scroller = document.scrollingElement || document.documentElement;
      var prevY = scroller ? scroller.scrollTop : window.scrollY;
      state.value = (md == null) ? "" : md;
      invalidateReferenceLinkCache();
      cancelAnchorRequests();
      if (vditor && ready) { vditor.setValue(state.value, true); }
      queueTableScrollReset();
      schedulePostRender();
      dirty = false;
      postCount(state.value);
      var restore = function () {
        if (scroller) { scroller.scrollTop = prevY; } else { window.scrollTo(0, prevY); }
      };
      requestAnimationFrame(function () { restore(); requestAnimationFrame(restore); });
    },
    getValue: function () {
      // Repair lute's dropped table-cell boundary spaces before serializing, so
      // a save never writes `word**bold**` for the author's `word **bold**`.
      try { restoreTableCellSpaces(); } catch (e) { /* never block a save */ }
      try { return vditor ? vditor.getValue() : state.value; } catch (e) { return state.value; }
    },
    getHTML: function () {
      try { return vditor ? normalizeHeadingIDsInHTML(vditor.getHTML()) : ""; } catch (e) { return ""; }
    },
    setTheme: function (uiMode, css, codeTheme, background) {
      var prevMode = state.uiTheme;
      if (uiMode) { state.uiTheme = uiMode; }
      if (codeTheme) { state.codeTheme = codeTheme; }
      background = background || (window.__ouroInitialTheme && window.__ouroInitialTheme.background) || "";
      if (!window.__ouroInitialTheme) { window.__ouroInitialTheme = {}; }
      window.__ouroInitialTheme.uiMode = state.uiTheme;
      window.__ouroInitialTheme.codeTheme = state.codeTheme;
      window.__ouroInitialTheme.background = background;
      window.__ouroInitialTheme.css = css || "";
      applyThemeBackground(background);
      var tag = document.getElementById("ouro-theme");
      if (tag) { tag.textContent = css || ""; }
      if (vditor) { try { vditor.setTheme(state.uiTheme, undefined, state.codeTheme); } catch (e) { /* ignore */ } }
      // Vditor.setTheme updates options.theme but does NOT re-render already-processed
      // Mermaid diagrams — Mermaid bakes light/dark colors into the SVG at render time
      // (the block is cached via data-processed). So a light↔dark switch would otherwise
      // strand a light diagram in a dark page (or vice versa). When the mode actually
      // flips and diagrams are on screen, re-render from source (preserving the reader's
      // scroll) so the diagrams pick up the new Mermaid theme.
      var modeFlipped = (prevMode === "dark") !== (state.uiTheme === "dark");
      if (vditor && ready && modeFlipped && document.querySelector(".language-mermaid")) {
        var scroller = document.scrollingElement || document.documentElement;
        var prevY = scroller ? scroller.scrollTop : window.scrollY;
        vditor.setValue(state.value, true);
        queueTableScrollReset();
        schedulePostRender();
        var restore = function () {
          if (scroller) { scroller.scrollTop = prevY; } else { window.scrollTo(0, prevY); }
        };
        requestAnimationFrame(function () { restore(); requestAnimationFrame(restore); });
      }
    },
    setMode: function (mode) {
      if (!mode || mode === state.mode) { return; }
      state.mode = mode;
      rebuild();
    },
    setOutline: function (on) {
      on = !!on;
      if (on === state.outline) { return; }
      state.outline = on;
      rebuild();
    },
    setFocusMode: function (on) {
      state.focus = !!on;
      document.body.classList.toggle("ouro-focus", state.focus);
      if (state.focus) { updateActiveBlock(); }
    },
    setTypewriter: function (on) {
      on = !!on;
      if (on === state.typewriter) { return; }
      state.typewriter = on;
      rebuild();
    },
    setAutoPair: function (on) { autoPair = !!on; },
    exec: function (cmd) {
      switch (cmd) {
        case "bold": wrapSelection("**", "**"); break;
        case "italic": wrapSelection("*", "*"); break;
        case "strike": wrapSelection("~~", "~~"); break;
        case "code": wrapSelection("`", "`"); break;
        case "link": {
          var sel = window.getSelection();
          var t = sel ? sel.toString() : "";
          insertAtCursor("[" + (t || "text") + "](url)");
          break;
        }
        case "h1": case "h2": case "h3": case "h4": case "h5": case "h6": {
          var n = parseInt(cmd.slice(1), 10);
          transformLine(function (line) {
            return new Array(n + 1).join("#") + " " + stripBlockMarkers(line);
          });
          break;
        }
        case "paragraph": transformLine(stripBlockMarkers); break;
        case "quote": transformLine(function (l) { return "> " + stripBlockMarkers(l); }); break;
        case "ul": transformLine(function (l) { return "- " + stripBlockMarkers(l); }); break;
        case "ol": transformLine(function (l) { return "1. " + stripBlockMarkers(l); }); break;
        case "task": transformLine(function (l) { return "- [ ] " + stripBlockMarkers(l); }); break;
        case "codeblock": insertAtCursor("\n```\n\n```\n"); break;
        case "table": insertAtCursor("\n| Column | Column |\n| --- | --- |\n| Cell | Cell |\n"); break;
        case "math": insertAtCursor("\n$$\n\n$$\n"); break;
        case "hr": insertAtCursor("\n\n---\n\n"); break;
        default: break;
      }
    },
    markSaved: function () { dirty = false; },
    undo: function () {
      if (!vditor || !vditor.vditor || !vditor.vditor.undo) { return; }
      try {
        var undoState = vditor.vditor.undo[vditor.vditor.currentMode || state.mode];
        if (!undoState || !undoState.undoStack || undoState.undoStack.length < 2) { return; }
        vditor.vditor.undo.undo(vditor.vditor);
        state.value = vditor.getValue();
        setDirty(true);
        postCount(state.value);
      } catch (e) { /* ignore */ }
    },
    redo: function () {
      if (!vditor || !vditor.vditor || !vditor.vditor.undo) { return; }
      try {
        var undoState = vditor.vditor.undo[vditor.vditor.currentMode || state.mode];
        if (!undoState || !undoState.redoStack || undoState.redoStack.length === 0) { return; }
        vditor.vditor.undo.redo(vditor.vditor);
        state.value = vditor.getValue();
        setDirty(true);
        postCount(state.value);
      } catch (e) { /* ignore */ }
    },
    focus: function () { if (vditor) { try { vditor.focus(); } catch (e) { /* ignore */ } } },
    insertText: function (text) { if (text) { insertAtCursor(text); } },
    // Explicit Edit ▸ Copy as ▸ {markdown, plain, html}. Sets the mode for the
    // unified copy handler above, then fires a synthetic copy so that handler
    // writes the requested flavor to the clipboard.
    copyAs: function (mode) {
      pendingCopyMode = (mode === "markdown" || mode === "plain" || mode === "html") ? mode : null;
      if (!pendingCopyMode) { return; }
      try { document.execCommand("copy"); } catch (e) { /* ignore */ }
      pendingCopyMode = null;
    },
    setDocBase: function (dir) { docBase = dir || ""; rewriteRelativeImages(); },
    scrollToHeading: function (index) {
      var hs = document.querySelectorAll(".vditor-reset h1, .vditor-reset h2, .vditor-reset h3, .vditor-reset h4, .vditor-reset h5, .vditor-reset h6");
      if (hs[index]) { hs[index].scrollIntoView({ behavior: "smooth", block: "start" }); }
    },
    scrollToAnchor: function (fragment) {
      return scrollToAnchorTarget(fragment, renderedAnchorRoot());
    },
    scrollToAnchorWhenReady: function (fragment) {
      scrollToAnchorWhenReady(fragment);
    },
    find: function (query, opts) {
      if (!query) { return; }
      opts = opts || {};
      try {
        window.find(query, !!opts.caseSensitive, !!opts.backward, true, !!opts.wholeWord, false, false);
      } catch (e) { /* ignore */ }
    },
    revealSearchMatch: function (opts) {
      opts = opts || {};
      var ordinal = Math.max(0, opts.matchOrdinal || 0);
      var text = opts.matchedText || "";
      var query = opts.query || text;
      var reveal = function () {
        if (query && revealSearchOccurrence(query, opts, ordinal)) { return; }
        if (text && revealTextOccurrence(text, 0, !!opts.caseSensitive)) { return; }
        if (query) {
          try { window.find(query, !!opts.caseSensitive, false, true, !!opts.wholeWord, false, false); } catch (e) { /* ignore */ }
        }
      };
      var didReveal = false;
      var runReveal = function () {
        if (didReveal) { return; }
        didReveal = true;
        reveal();
      };
      requestAnimationFrame(function () { requestAnimationFrame(runReveal); });
      setTimeout(runReveal, 80);
    },
    replaceNext: function (query, replacement, opts) { return doReplace(query, replacement, opts, false); },
    replaceAll: function (query, replacement, opts) { return doReplace(query, replacement, opts, true); },
    clearFind: function () { try { window.getSelection().removeAllRanges(); } catch (e) { /* ignore */ } }
  };

  function buildSearchRegex(query, opts, global) {
    opts = opts || {};
    var pattern = opts.regexp ? query : query.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    if (opts.wholeWord) { pattern = "\\b" + pattern + "\\b"; }
    var flags = global ? "g" : "";
    if (!opts.caseSensitive) { flags += "i"; }
    try { return new RegExp(pattern, flags); } catch (e) { return null; }
  }

  // Replace on the markdown source (correct for a markdown editor), preserving
  // scroll and marking the buffer dirty so auto-save picks it up. Returns count.
  function doReplace(query, replacement, opts, all) {
    if (!query || !vditor) { return 0; }
    var re = buildSearchRegex(query, opts, all);
    if (!re) { return 0; }
    var md = vditor.getValue();
    var count = 0;
    var out = md.replace(re, function () { count++; return replacement; });
    if (count > 0 && out !== md) {
      var scroller = document.scrollingElement || document.documentElement;
      var y = scroller ? scroller.scrollTop : 0;
      state.value = out;
      if (ready) { vditor.setValue(out, true); }
      setDirty(true);
      postCount(out);
      requestAnimationFrame(function () { if (scroller) { scroller.scrollTop = y; } });
    }
    return count;
  }

  document.addEventListener("selectionchange", function () {
    if (state.focus) { updateActiveBlock(); }
    updateAlertEditing();
  });

  // Track the heading nearest the top of the viewport so the outline can
  // highlight the section you're reading.
  var activeHeadingIndex = -1;
  function updateActiveHeading() {
    var hs = document.querySelectorAll(".vditor-reset h1, .vditor-reset h2, .vditor-reset h3, .vditor-reset h4, .vditor-reset h5, .vditor-reset h6");
    var idx = hs.length ? 0 : -1;
    for (var i = 0; i < hs.length; i++) {
      if (hs[i].getBoundingClientRect().top <= 90) { idx = i; } else { break; }
    }
    if (idx !== activeHeadingIndex) { activeHeadingIndex = idx; post("activeHeading", { index: idx }); }
  }
  var headingScrollTimer = null;
  window.addEventListener("scroll", function () {
    if (headingScrollTimer) { return; }
    headingScrollTimer = setTimeout(function () { headingScrollTimer = null; updateActiveHeading(); }, 120);
  }, true);

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", create);
  } else {
    create();
  }
})();
