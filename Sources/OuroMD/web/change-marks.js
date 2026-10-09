(function () {
  "use strict";

  function matches(before, after) {
    var pairs = [], first = 0, oldEnd = before.length, newEnd = after.length;
    while (first < oldEnd && first < newEnd && before[first].signature === after[first]) {
      pairs.push([first, first]); first++;
    }
    while (oldEnd > first && newEnd > first && before[oldEnd - 1].signature === after[newEnd - 1]) {
      oldEnd--; newEnd--;
    }
    var m = oldEnd - first, n = newEnd - first;
    // Bound quadratic work; large rewrites use increasing passage matches.
    if (m * n <= 250000) {
      var width = n + 1, table = new Uint32Array((m + 1) * width);
      for (var i = m - 1; i >= 0; i--) {
        for (var j = n - 1; j >= 0; j--) {
          table[i * width + j] = before[first + i].signature === after[first + j]
            ? 1 + table[(i + 1) * width + j + 1]
            : Math.max(table[(i + 1) * width + j], table[i * width + j + 1]);
        }
      }
      var a = 0, b = 0;
      while (a < m && b < n) {
        if (before[first + a].signature === after[first + b]) {
          pairs.push([first + a++, first + b++]);
        } else if (table[(a + 1) * width + b] >= table[a * width + b + 1]) { a++; }
        else { b++; }
      }
    } else {
      var positions = new Map();
      for (var p = first; p < newEnd; p++) {
        if (!positions.has(after[p])) { positions.set(after[p], []); }
        positions.get(after[p]).push(p);
      }
      var oldCounts = new Map(), candidatesCount = 0;
      for (var q = first; q < oldEnd; q++) {
        var key = before[q].signature;
        oldCounts.set(key, (oldCounts.get(key) || 0) + 1);
        candidatesCount += (positions.get(key) || []).length;
      }
      var tails = [], links = [];
      for (var q = first; q < oldEnd; q++) {
        var candidates = positions.get(before[q].signature);
        if (!candidates) { continue; }
        // Highly repetitive rewrites use only unique anchors, keeping the
        // candidate budget bounded instead of allocating an unbounded diff.
        if (candidatesCount > 250000 && (candidates.length !== 1 || oldCounts.get(before[q].signature) !== 1)) { continue; }
        for (var c = candidates.length - 1; c >= 0; c--) {
          var nextIndex = candidates[c], lo = 0, hi = tails.length;
          while (lo < hi) {
            var mid = (lo + hi) >>> 1;
            if (links[tails[mid]].next < nextIndex) { lo = mid + 1; } else { hi = mid; }
          }
          links.push({ old: q, next: nextIndex, previous: lo ? tails[lo - 1] : -1 });
          tails[lo] = links.length - 1;
        }
      }
      var chain = [], link = tails.length ? tails[tails.length - 1] : -1;
      while (link >= 0) {
        chain.push([links[link].old, links[link].next]);
        link = links[link].previous;
      }
      pairs = pairs.concat(chain.reverse());
    }
    while (oldEnd < before.length) { pairs.push([oldEnd++, newEnd++]); }
    return pairs;
  }

  function similarity(a, b) {
    var prefix = 0, suffix = 0, max = Math.min(a.length, b.length);
    while (prefix < max && a[prefix] === b[prefix]) { prefix++; }
    while (suffix < max - prefix && a[a.length - 1 - suffix] === b[b.length - 1 - suffix]) { suffix++; }
    return (prefix + suffix) / Math.max(1, a.length, b.length);
  }

  function reconcile(before, after, external) {
    var result = after.map(function (signature) {
      return { signature: signature, marked: false, deletion: false, seen: false, atEnd: false };
    });
    var pairs = matches(before, after), oldStart = 0, newStart = 0;
    pairs.concat([[before.length, after.length]]).forEach(function (pair) {
      var oldStop = pair[0], newStop = pair[1];
      if (external) {
        for (var j = newStart; j < newStop; j++) { result[j].marked = true; }
        if (oldStop > oldStart && newStop === newStart) {
          var gap = Math.min(newStop, result.length - 1);
          if (gap < 0) {
            result.push({ signature: "", marked: true, deletion: true, seen: false, atEnd: false });
          } else {
            result[gap].marked = true; result[gap].deletion = true;
            result[gap].seen = false; result[gap].atEnd = newStop === after.length;
          }
        }
      } else {
        for (var k = oldStart; k < oldStop; k++) {
          if (!before[k].marked) { continue; }
          var target = Math.min(newStart + k - oldStart, newStop - 1), score = -1;
          for (var t = newStart; t < newStop; t++) {
            var s = similarity(before[k].signature, after[t]);
            if (s > score) { score = s; target = t; }
          }
          if (target < newStart) { target = Math.min(newStop, result.length - 1); }
          if (target >= 0) {
            result[target] = Object.assign({}, before[k], { signature: after[target] });
          } else if (!after.length) {
            result.push(Object.assign({}, before[k], { signature: "" }));
          }
        }
      }
      if (oldStop < before.length && newStop < after.length) {
        var gapMark = result[newStop];
        result[newStop] = Object.assign({}, before[oldStop], { signature: after[newStop] });
        if (gapMark.marked) {
          result[newStop].marked = true; result[newStop].deletion = gapMark.deletion;
          result[newStop].seen = false; result[newStop].atEnd = gapMark.atEnd;
        }
      }
      oldStart = oldStop + 1; newStart = newStop + 1;
    });
    return result;
  }

  function passed(mark, rect, viewport) {
    return mark.seen && (rect.bottom <= 48 || rect.top >= viewport - 32);
  }

  function create(options) {
    var rows = [], generation = 0, pending = false, queued = false, scrollPending = false;
    var activeTicket = null, snapshotMarkdown = null, snapshotSignatures = [];
    var observedRoot = null, observedNodes = [], resizeObserver = null;
    var overlay = document.getElementById("ouro-change-marks");
    var nextButton = document.getElementById("ouro-next-change");
    var offscreen = [];

    function passageNodes(root) {
      return Array.from(root.children).filter(function (node) {
        return !node.matches("script, style, .vditor-ir__preview");
      });
    }

    function signatures(nodes) {
      return nodes.map(function (node) {
        var formatting = Array.from(node.querySelectorAll("strong, em, del, a, code, img")).map(function (el) {
          var destination = el.tagName === "A" ? el.getAttribute("href")
            : el.tagName === "IMG" ? el.getAttribute("src") + "|" + el.getAttribute("alt") : "";
          return el.tagName + ":" + destination;
        }).join(",");
        return node.tagName + "|" + options.text(node) + "|" + formatting;
      });
    }

    function markdownSignatures(md) {
      var html = options.renderMarkdown(md);
      if (html === null) { return null; }
      var template = document.createElement("template");
      template.innerHTML = html;
      return md.trim() ? signatures(passageNodes(template.content)) : [];
    }

    function passages() {
      var root = options.root(), nodes = root ? passageNodes(root) : [];
      // Parse only when Markdown changes. The same canonical snapshots in
      // source and rendered modes keep local typing out of external edits.
      if (options.markdown && options.renderMarkdown) {
        var md = options.markdown();
        if (md !== snapshotMarkdown) {
          var next = markdownSignatures(md);
          if (next === null) { return null; }
          snapshotSignatures = next;
          snapshotMarkdown = md;
        }
        return { nodes: nodes, signatures: snapshotSignatures };
      }
      return {
        nodes: nodes,
        signatures: signatures(nodes)
      };
    }

    function update(scrolled) {
      if (!overlay || !nextButton || pending) { return; }
      var current = passages();
      if (!current) {
        overlay.replaceChildren(); nextButton.hidden = true; return;
      }
      rows = reconcile(rows, current.signatures, false);
      overlay.replaceChildren();
      offscreen = [];
      if (options.mode() === "sv" || !options.root()) { nextButton.hidden = true; return; }
      var root = options.root();
      if (resizeObserver && (observedRoot !== root || observedNodes.length !== current.nodes.length
          || current.nodes.some(function (node, index) { return node !== observedNodes[index]; }))) {
        resizeObserver.disconnect(); resizeObserver.observe(root); observedRoot = root;
        observedNodes = current.nodes.slice();
        observedNodes.forEach(function (node) { resizeObserver.observe(node); });
      }
      rows.forEach(function (mark, index) {
        if (!mark.marked) { return; }
        var node = current.nodes[index] || options.root();
        if (!node) { return; }
        var rect = node.getBoundingClientRect();
        if (rect.height <= 0) { return; }
        var bounds = mark.deletion
          ? { top: mark.atEnd ? rect.bottom - 3 : rect.top, bottom: mark.atEnd ? rect.bottom : rect.top + 3 }
          : rect;
        var visible = bounds.bottom > 48 && bounds.top < window.innerHeight - 32;
        if (scrolled && passed(mark, bounds, window.innerHeight)) { mark.marked = false; return; }
        if (visible) { mark.seen = true; }
        else { offscreen.push({ node: node, rect: bounds }); }
        var bar = document.createElement("span");
        bar.className = "ouro-change-mark" + (mark.deletion ? " ouro-change-deletion" : "");
        bar.style.left = Math.max(3, rect.left - 10) + "px";
        bar.style.top = bounds.top - 48 + "px";
        bar.style.height = Math.max(3, bounds.bottom - bounds.top) + "px";
        overlay.appendChild(bar);
      });
      nextButton.hidden = offscreen.length === 0;
    }

    function schedule(scrolled) {
      scrollPending = scrollPending || scrolled;
      if (queued) { return; }
      queued = true;
      setTimeout(function () {
        queued = false;
        var scroll = scrollPending; scrollPending = false;
        update(scroll);
      }, 16);
    }

    nextButton.addEventListener("click", function () {
      update(false);
      var next = offscreen.find(function (item) { return item.rect.top >= window.innerHeight - 32; }) || offscreen[0];
      if (!next) { return; }
      var scroller = document.scrollingElement || document.documentElement;
      window.scrollBy({ top: next.rect.top - 80, behavior: "auto" });
      // Source/preview panes can have their own scroll container.
      if (scroller.scrollTop === 0 && next.rect.top > window.innerHeight) {
        next.node.scrollIntoView({ block: "center", behavior: "auto" });
      }
      update(false);
    });
    window.addEventListener("scroll", function () { schedule(true); }, true);
    window.addEventListener("resize", function () { schedule(false); });
    document.getElementById("editor").addEventListener("load", function () { schedule(false); }, true);
    if (window.ResizeObserver) {
      resizeObserver = new ResizeObserver(function () { schedule(false); });
    }
    return {
      update: function () { schedule(false); },
      begin: function (md) {
        if (pending && activeTicket) {
          var current = passages();
          if (current && activeTicket.target !== null) {
            rows = reconcile(activeTicket.rows, activeTicket.target, true);
            rows = reconcile(rows, current.signatures, false);
          }
          pending = false;
        }
        update(false);
        pending = true;
        activeTicket = {
          generation: ++generation,
          rows: rows.map(function (row) { return Object.assign({}, row); }),
          target: options.renderMarkdown ? markdownSignatures(md) : null
        };
        return activeTicket;
      },
      finish: function (ticket) {
        if (ticket.generation !== generation) { return; }
        var current = passages();
        if (current && ticket.target !== null) {
          rows = reconcile(ticket.rows, ticket.target, true);
          rows = reconcile(rows, current.signatures, false);
        }
        pending = false;
        scrollPending = false;
        update(false);
      },
      reset: function () {
        generation++; pending = false; rows = []; activeTicket = null; scrollPending = false;
        snapshotMarkdown = null; snapshotSignatures = [];
        overlay.replaceChildren(); nextButton.hidden = true;
      }
    };
  }

  window.OuroChangeMarks = { reconcile: reconcile, passed: passed, create: create };
})();
