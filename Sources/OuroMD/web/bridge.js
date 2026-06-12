// Bridge between the native app and the Vditor instant-rendering editor.
// Native -> JS: window.ouro.{setValue,getValue,getHTML,setTheme,setMode,setOutline,exec,markSaved,focus}
// JS -> Native: window.webkit.messageHandlers.ouro.postMessage({type,...})
(function () {
  "use strict";

  var vditor = null;
  var ready = false;
  var dirty = false;
  var state = { mode: "ir", value: "", outline: false, uiTheme: "classic" };

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

  function create() {
    ready = false;
    vditor = new Vditor("editor", {
      cdn: "vditor",
      mode: state.mode,
      value: state.value,
      theme: state.uiTheme,
      cache: { enable: false },
      toolbar: [],
      counter: { enable: true, type: "markdown" },
      outline: { enable: state.outline, position: "left" },
      preview: {
        delay: 80,
        hljs: { enable: true, lineNumber: false },
        math: { engine: "KaTeX", inlineDigit: true }
      },
      input: function (value) {
        state.value = value;
        setDirty(true);
      },
      after: function () {
        ready = true;
        attachImageHandlers();
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
    if (!dt || !dt.files || dt.files.length === 0) { return; }
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

  window.ouro = {
    setValue: function (md) {
      state.value = (md == null) ? "" : md;
      if (vditor && ready) { vditor.setValue(state.value, true); }
      dirty = false;
    },
    getValue: function () {
      try { return vditor ? vditor.getValue() : state.value; } catch (e) { return state.value; }
    },
    getHTML: function () {
      try { return vditor ? vditor.getHTML() : ""; } catch (e) { return ""; }
    },
    setTheme: function (uiMode, css) {
      if (uiMode) { state.uiTheme = uiMode; }
      var tag = document.getElementById("ouro-theme");
      if (tag) { tag.textContent = css || ""; }
      if (vditor && uiMode) { try { vditor.setTheme(uiMode); } catch (e) { /* ignore */ } }
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
    exec: function (cmd) {
      if (cmd === "bold") { wrapSelection("**", "**"); }
      else if (cmd === "italic") { wrapSelection("*", "*"); }
      else if (cmd === "strike") { wrapSelection("~~", "~~"); }
      else if (cmd === "code") { wrapSelection("`", "`"); }
      else if (cmd === "link") {
        var sel = window.getSelection();
        var t = sel ? sel.toString() : "";
        document.execCommand("insertText", false, "[" + (t || "text") + "](url)");
      }
    },
    markSaved: function () { dirty = false; },
    focus: function () { if (vditor) { try { vditor.focus(); } catch (e) { /* ignore */ } } }
  };

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", create);
  } else {
    create();
  }
})();
