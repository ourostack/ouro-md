// Bridge between the native app and the Vditor instant-rendering editor.
// Native -> JS: window.ouro.{setValue,getValue,getHTML,setTheme,setMode,setOutline,exec,markSaved,focus}
// JS -> Native: window.webkit.messageHandlers.ouro.postMessage({type,...})
(function () {
  "use strict";

  var vditor = null;
  var ready = false;
  var dirty = false;
  var qolInstalled = false;
  var resetTableScrollPending = false;
  var resetTablesSeen = (typeof WeakSet === "function") ? new WeakSet() : null;
  var state = { mode: "ir", value: "", outline: false, uiTheme: "classic", focus: false, typewriter: false, codeTheme: "github" };

  function post(type, extra) {
    try {
      var msg = { type: type };
      if (extra) { for (var k in extra) { msg[k] = extra[k]; } }
      window.webkit.messageHandlers.ouro.postMessage(msg);
    } catch (e) { /* not running inside the app */ }
  }

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

    if (AUTO_CLOSE[e.key] && ctx.after === e.key) {
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
  }

  function create() {
    ready = false;
    vditor = new Vditor("editor", {
      cdn: "vditor",
      mode: state.mode,
      value: state.value,
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
    // Resolve relative image paths against the open document's folder so
    // images an agent referenced relatively actually display; style alerts.
    postRender();
    var observer = new MutationObserver(function () { postRender(); });
    observer.observe(el, { childList: true, characterData: true, subtree: true });
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
    rewriteRelativeImages();
    styleAlerts();
    updateAlertEditing();
    resetTableScrollIfNeeded();
    resetNewTableScroll(document);
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

  window.ouro = {
    setValue: function (md) {
      state.value = (md == null) ? "" : md;
      if (vditor && ready) { vditor.setValue(state.value, true); }
      queueTableScrollReset();
      schedulePostRender();
      dirty = false;
      postCount(state.value);
    },
    reloadValue: function (md) {
      // Like setValue, but preserves the reader's scroll position — used when
      // the open file is rewritten externally (agent edit) and we live-reload.
      var scroller = document.scrollingElement || document.documentElement;
      var prevY = scroller ? scroller.scrollTop : window.scrollY;
      state.value = (md == null) ? "" : md;
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
      try { return vditor ? vditor.getValue() : state.value; } catch (e) { return state.value; }
    },
    getHTML: function () {
      try { return vditor ? vditor.getHTML() : ""; } catch (e) { return ""; }
    },
    setTheme: function (uiMode, css, codeTheme) {
      if (uiMode) { state.uiTheme = uiMode; }
      if (codeTheme) { state.codeTheme = codeTheme; }
      var tag = document.getElementById("ouro-theme");
      if (tag) { tag.textContent = css || ""; }
      if (vditor) { try { vditor.setTheme(state.uiTheme, undefined, state.codeTheme); } catch (e) { /* ignore */ } }
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
        vditor.vditor.undo.undo(vditor.vditor);
        state.value = vditor.getValue();
        setDirty(true);
        postCount(state.value);
      } catch (e) { /* ignore */ }
    },
    redo: function () {
      if (!vditor || !vditor.vditor || !vditor.vditor.undo) { return; }
      try {
        vditor.vditor.undo.redo(vditor.vditor);
        state.value = vditor.getValue();
        setDirty(true);
        postCount(state.value);
      } catch (e) { /* ignore */ }
    },
    focus: function () { if (vditor) { try { vditor.focus(); } catch (e) { /* ignore */ } } },
    insertText: function (text) { if (text) { insertAtCursor(text); } },
    setDocBase: function (dir) { docBase = dir || ""; rewriteRelativeImages(); },
    scrollToHeading: function (index) {
      var hs = document.querySelectorAll(".vditor-reset h1, .vditor-reset h2, .vditor-reset h3, .vditor-reset h4, .vditor-reset h5, .vditor-reset h6");
      if (hs[index]) { hs[index].scrollIntoView({ behavior: "smooth", block: "start" }); }
    },
    find: function (query, opts) {
      if (!query) { return; }
      opts = opts || {};
      try {
        window.find(query, !!opts.caseSensitive, !!opts.backward, true, !!opts.wholeWord, false, false);
      } catch (e) { /* ignore */ }
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
