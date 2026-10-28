(function () {
  "use strict";

  function normalized(value) { return value.replace(/\r\n?/g, "\n"); }

  function difference(before, after) {
    var start = 0, end = 0, max = Math.min(before.length, after.length);
    while (start < max && before[start] === after[start]) { start++; }
    while (end < max - start && before[before.length - end - 1] === after[after.length - end - 1]) { end++; }
    return { start: start, removed: before.slice(start, before.length - end), inserted: after.slice(start, after.length - end) };
  }

  function buffer(initial) {
    var value = initial, undo = [], redo = [], editable = true;
    function sourceOffset(offset) {
      if (value.indexOf("\r") < 0) { return offset; }
      var display = 0, source = 0;
      while (display < offset && source < value.length) {
        if (value[source] === "\r" && value[source + 1] === "\n") { source++; }
        source++; display++;
      }
      return source;
    }
    function apply(delta, backwards) {
      var removed = backwards ? delta.inserted : delta.removed;
      var inserted = backwards ? delta.removed : delta.inserted;
      value = value.slice(0, delta.start) + inserted + value.slice(delta.start + removed.length);
    }
    function splice(start, length, inserted) {
      if (!editable) { return false; }
      var delta = { start: start, removed: value.slice(start, start + length), inserted: inserted };
      if (delta.removed === inserted) { return false; }
      apply(delta, false);
      undo.push(delta);
      // Retain bounded edit deltas, not a full-document snapshot for every key.
      if (undo.length > 128) { undo.shift(); }
      redo = [];
      return true;
    }
    return {
      value: function () { return value; },
      display: function () { return normalized(value); },
      sourceOffset: sourceOffset,
      displayOffset: function (offset) { return normalized(value.slice(0, offset)).length; },
      editable: function (on) { editable = !!on; },
      load: function (next) { value = next; undo = []; redo = []; },
      splice: splice,
      replace: function (next) {
        var delta = difference(value, next);
        return splice(delta.start, delta.removed.length, delta.inserted);
      },
      input: function (next) {
        var delta = difference(normalized(value), next);
        return splice(sourceOffset(delta.start), sourceOffset(delta.start + delta.removed.length) - sourceOffset(delta.start), delta.inserted);
      },
      undo: function () {
        if (!editable || !undo.length) { return false; }
        var delta = undo.pop(); apply(delta, true); redo.push(delta); return true;
      },
      redo: function () {
        if (!editable || !redo.length) { return false; }
        var delta = redo.pop(); apply(delta, false); undo.push(delta); return true;
      }
    };
  }

  function create(options) {
    var model = buffer(options.value), sourceMode = false, editable = options.editable;
    var cachedSource = null, cachedHTML = "", renderedSource = null;
    var container = document.getElementById("editor");
    container.innerHTML = "";
    var note = document.createElement("div");
    note.id = "ouro-large-note";
    note.setAttribute("role", "status");
    var button = document.createElement("button");
    button.type = "button";
    button.textContent = "Edit full source";
    button.addEventListener("click", function () { window.ouro.setMode("sv"); });
    var label = document.createElement("span");
    label.textContent = "Large document reading mode. Use Source Code Mode to edit the full Markdown. Rich editing, Writing Tools, focus and typewriter effects are unavailable here. ";
    note.appendChild(label); note.appendChild(button);
    var reading = document.createElement("div");
    reading.id = "ouro-large-reading";
    reading.className = "vditor-reset";
    var source = document.createElement("textarea");
    source.id = "ouro-large-source";
    source.setAttribute("aria-label", "Full Markdown source");
    source.spellcheck = false;
    source.wrap = "off";
    container.appendChild(note); container.appendChild(reading); container.appendChild(source);
    model.editable(editable);
    source.readOnly = !editable;

    function html() {
      if (cachedSource !== model.value()) {
        cachedHTML = options.render(model.value());
        cachedSource = model.value();
      }
      return cachedHTML;
    }
    function show() {
      reading.hidden = sourceMode;
      source.hidden = !sourceMode;
      button.hidden = sourceMode || !editable;
      document.body.classList.toggle("ouro-source-mode", sourceMode);
      document.body.classList.add("ouro-large-document");
      if (sourceMode) {
        if (source.value !== model.display()) { source.value = model.display(); }
      } else if (renderedSource !== model.value()) {
        reading.innerHTML = html();
        options.event("large.dom");
        renderedSource = model.value();
        options.rendered();
        options.event("large.ready");
      }
    }
    function changed(sync) {
      if (sync) {
        var start = source.selectionStart, end = source.selectionEnd, y = source.scrollTop;
        source.value = model.display();
        source.setSelectionRange(Math.min(start, source.value.length), Math.min(end, source.value.length));
        source.scrollTop = y;
      }
      options.changed(model.value());
      if (!sourceMode) { show(); }
    }
    function selection() {
      return { start: model.sourceOffset(source.selectionStart), end: model.sourceOffset(source.selectionEnd) };
    }
    function insert(text) {
      if (!editable) { return false; }
      if (!sourceMode) { options.requestSource(); return false; }
      var sel = selection();
      if (!model.splice(sel.start, sel.end - sel.start, text)) { return false; }
      source.value = model.display();
      var caret = model.displayOffset(sel.start + text.length);
      source.focus(); source.setSelectionRange(caret, caret);
      changed(false);
      return true;
    }
    function reveal(start, length) {
      if (!sourceMode) { options.requestSource(); }
      source.focus();
      var a = model.displayOffset(start), b = model.displayOffset(start + length);
      source.setSelectionRange(a, b);
      // Textarea selection alone does not scroll offscreen matches into view in WebKit.
      var line = source.value.slice(0, a).split("\n").length - 1;
      source.scrollTop = Math.max(0, line * parseFloat(getComputedStyle(source).lineHeight) - source.clientHeight / 2);
    }
    source.addEventListener("input", function () {
      if (model.input(source.value)) { changed(false); }
      else if (!editable) { source.value = model.display(); }
    });
    source.addEventListener("beforeinput", function (event) {
      if (event.inputType === "historyUndo" || event.inputType === "historyRedo") {
        event.preventDefault();
        if (event.inputType === "historyUndo" ? model.undo() : model.redo()) { changed(true); }
      }
    });
    source.addEventListener("keydown", function (event) {
      if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === "z") {
        event.preventDefault();
        if (event.shiftKey ? model.redo() : model.undo()) { changed(true); }
      }
    });
    source.addEventListener("copy", function (event) {
      if (!event.clipboardData) { return; }
      var sel = selection(), text = model.value().slice(sel.start, sel.end);
      if (!text) { return; }
      event.clipboardData.setData("text/plain", text);
      event.preventDefault();
    });
    return {
      value: model.value,
      html: html,
      renderMarkdown: options.render,
      root: function () { return reading; },
      source: source,
      mode: function (mode) { sourceMode = mode === "sv"; show(); },
      load: function (next) {
        var y = source.scrollTop, start = source.selectionStart, end = source.selectionEnd;
        model.load(next); show();
        source.setSelectionRange(Math.min(start, source.value.length), Math.min(end, source.value.length));
        source.scrollTop = y;
      },
      edit: function (next) {
        if (model.replace(next)) { changed(true); return true; }
        return false;
      },
      undo: function () { if (model.undo()) { changed(true); } },
      redo: function () { if (model.redo()) { changed(true); } },
      editable: function (on) { editable = !!on; model.editable(on); source.readOnly = !on; button.hidden = sourceMode || !on; },
      focus: function () { if (sourceMode) { source.focus(); } },
      insert: insert,
      exec: function (cmd) {
        if (!editable) { return; }
        if (!sourceMode) { options.requestSource(); return; }
        var sel = selection(), selected = model.value().slice(sel.start, sel.end);
        var wraps = { bold: ["**", "**"], italic: ["*", "*"], strike: ["~~", "~~"], code: ["`", "`"], link: ["[", "](url)"] };
        var inserts = { codeblock: "\n```\n\n```\n", table: "\n| Column | Column |\n| --- | --- |\n| Cell | Cell |\n", math: "\n$$\n\n$$\n", hr: "\n\n---\n\n" };
        if (wraps[cmd]) { insert(wraps[cmd][0] + (selected || (cmd === "link" ? "text" : "")) + wraps[cmd][1]); return; }
        if (inserts[cmd]) { insert(inserts[cmd]); return; }
        var prefixes = { paragraph: "", quote: "> ", ul: "- ", ol: "1. ", task: "- [ ] " };
        if (/^h[1-6]$/.test(cmd)) { prefixes[cmd] = "#".repeat(Number(cmd.slice(1))) + " "; }
        if (Object.prototype.hasOwnProperty.call(prefixes, cmd)) {
          var value = model.value(), a = value.lastIndexOf("\n", sel.start - 1) + 1, b = value.indexOf("\n", sel.end);
          if (b < 0) { b = value.length; }
          var lines = value.slice(a, b).replace(/^(?:#{1,6}\s+|>\s*|[-*+]\s+(?:\[[ xX]\]\s+)?|\d+\.\s+)/gm, "");
          model.splice(a, b - a, lines.replace(/^/gm, prefixes[cmd]));
          changed(true);
        }
      },
      reveal: reveal,
      find: function (regex, ordinal, backward) {
        if (!regex) { return false; }
        var text = model.value(), matches = Array.from(text.matchAll(regex));
        if (!matches.length) { return false; }
        var match;
        if (ordinal != null) { match = matches[Math.min(ordinal, matches.length - 1)]; }
        else {
          var sel = selection();
          match = backward ? matches.filter(function (m) { return m.index < sel.start; }).pop()
            : matches.find(function (m) { return m.index >= sel.end; });
          match = match || matches[backward ? matches.length - 1 : 0];
        }
        reveal(match.index, match[0].length);
        return true;
      },
      replace: function (regex, replacement, all) {
        if (!editable || !regex) { return 0; }
        var text = model.value(), matches = Array.from(text.matchAll(regex));
        if (!matches.length) { return 0; }
        if (!all) {
          var sel = selection();
          var next = matches.find(function (match) { return match.index >= sel.start; }) || matches[0];
          model.splice(next.index, next[0].length, replacement);
          changed(true); reveal(next.index, replacement.length); return 1;
        }
        var next = text.replace(regex, function () { return replacement; });
        if (model.replace(next)) { changed(true); }
        return matches.length;
      },
      destroy: function () { container.innerHTML = ""; document.body.classList.remove("ouro-large-document"); }
    };
  }

  window.OuroLargeDocument = {
    accepts: function (value) {
      if (value.length >= 524288) { return true; }
      return new TextEncoder().encode(value).length >= 524288;
    },
    buffer: buffer,
    create: create
  };
})();
