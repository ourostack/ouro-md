// Bridge between the native app and the Vditor instant-rendering editor.
// Native -> JS: window.ouro.{setValue,getValue,getHTML,setTheme,setMode,setOutline,exec,markSaved,focus}
// JS -> Native: window.webkit.messageHandlers.ouro.postMessage({type,...})
(function () {
  "use strict";

  var vditor = null;
  var ready = false;
  var dirty = false;
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
    }, 250);
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
        math: { engine: "KaTeX", inlineDigit: true }
      },
      input: function (value) {
        state.value = value;
        setDirty(true);
        postCount(value);
      },
      after: function () {
        ready = true;
        attachImageHandlers();
        postCount(state.value);
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
      dirty = false;
      postCount(state.value);
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
    focus: function () { if (vditor) { try { vditor.focus(); } catch (e) { /* ignore */ } } }
  };

  document.addEventListener("selectionchange", function () {
    if (state.focus) { updateActiveBlock(); }
  });

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", create);
  } else {
    create();
  }
})();
