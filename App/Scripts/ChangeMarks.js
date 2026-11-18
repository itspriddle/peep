// Peep change marks: after a live reload, a bar in the left margin beside each changed block
// (and a short rule where text was deleted), while Settings > Reading's "Highlight changes when
// a file is saved" is on. A mark fades out once it has been on screen for a few seconds; marks
// out of view are counted for the status bar. With "Scroll to the first change" on, Swift then
// calls `peepChanges.scrollToFirst` (which stays put when a mark is already on screen).
//
// Runs only in the app's isolated content world ("peep", see AppScripts.swift); page JavaScript
// is disabled. Swift calls `peepChanges.mark` with the changed lines (`SourceChanges`) as
// arguments, never as script source. Counts go to the `changeMarks` message handler, which is
// registered in this world only; the app validates them.
//
// Lines map to blocks through the renderer's `data-source-line` attributes (block start lines).
// A block spans from its line to the line before the next annotated block that isn't inside it.
// The deepest block a change touches gets the bar. The bars live in their own layer outside the
// article (so a content swap removes nothing it doesn't own) and are positioned relative to
// that layer, following layout changes (zoom, width, folding) through a ResizeObserver.
"use strict";

(() => {
  const ATTRIBUTE = "data-source-line";
  const LAYER = "data-peep-changes";
  const BAR = "data-peep-change";
  const FADING = "data-peep-fading";
  // How long a mark stays once it has been on screen, then how long it takes to fade (the
  // transition in ThemeBase).
  const HOLD_MS = 4000;
  const FADE_MS = 800;
  // The gap between a bar and the text, in CSS pixels.
  const GUTTER = 12;

  const handler = globalThis.webkit?.messageHandlers?.changeMarks;

  // { element, kind: "changed" | "before" | "after", bar, timer }
  let marks = [];
  let layer = null;
  let intersection = null;
  let resize = null;
  let lastReport = "0,0";
  let scrollPending = false;

  function sections() {
    return globalThis.peepSections ?? null;
  }

  function article() {
    return document.querySelector("article.markdown-body");
  }

  function isNumberPair(value) {
    return (
      Array.isArray(value) &&
      value.length === 2 &&
      Number.isInteger(value[0]) &&
      Number.isInteger(value[1]) &&
      value[0] <= value[1]
    );
  }

  // Annotated blocks in document order, each with the last line it spans (`end`).
  function annotatedBlocks(root) {
    const blocks = [];
    for (const element of root.querySelectorAll(`[${ATTRIBUTE}]`)) {
      const line = Number.parseInt(element.getAttribute(ATTRIBUTE), 10);
      if (Number.isFinite(line)) {
        blocks.push({ element, line, end: Infinity });
      }
    }
    for (let index = 0; index < blocks.length; index += 1) {
      const block = blocks[index];
      // The first following block that isn't inside this one and starts after it. Footnote
      // items come last in number order, so their lines can go back; those are skipped.
      for (let next = index + 1; next < blocks.length; next += 1) {
        const candidate = blocks[next];
        if (!block.element.contains(candidate.element) && candidate.line > block.line) {
          block.end = candidate.line - 1;
          break;
        }
      }
    }
    return blocks;
  }

  // The first range (sorted, as Swift sends them) that ends at or after `line`.
  function firstRangeEndingFrom(ranges, line) {
    let low = 0;
    let high = ranges.length;
    while (low < high) {
      const middle = (low + high) >> 1;
      if (ranges[middle][1] < line) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return low < ranges.length ? ranges[low] : null;
  }

  function intersects(block, ranges) {
    const range = firstRangeEndingFrom(ranges, block.line);
    return range !== null && range[0] <= block.end;
  }

  // The deepest blocks a change touches: touched blocks with no touched block inside them.
  function changedBlocks(blocks, ranges) {
    const touched = new Set(blocks.filter((block) => intersects(block, ranges)).map((block) => block.element));
    const withTouchedChild = new Set();
    for (const element of touched) {
      const parent = element.parentElement?.closest(`[${ATTRIBUTE}]`);
      if (parent) {
        withTouchedChild.add(parent);
      }
    }
    return [...touched].filter((element) => !withTouchedChild.has(element));
  }

  // Where a deletion before `line` is shown: a rule above the block that starts there, or the
  // block itself when the line is inside it (text removed from within a block). Nothing for a
  // line before the first block (frontmatter).
  function deletionMark(blocks, line) {
    const starting = blocks.find((block) => block.line === line);
    if (starting) {
      return { element: starting.element, kind: "before" };
    }
    let containing = null;
    for (const block of blocks) {
      if (block.line <= line && line <= block.end) {
        containing = block;
      }
    }
    return containing ? { element: containing.element, kind: "changed" } : null;
  }

  // Replaces any marks with marks for `changed` (line ranges, `[start, end]`), `deleted`
  // (lines a removal sits before), and `deletedAtEnd` (a rule below the last block). Returns
  // the number of marks.
  function mark(changed, deleted, deletedAtEnd) {
    clear();
    const root = article();
    if (root === null || !Array.isArray(changed) || !Array.isArray(deleted)) {
      return 0;
    }
    const ranges = changed.filter(isNumberPair);
    const deletions = deleted.filter((line) => Number.isInteger(line));
    const atEnd = deletedAtEnd === true;
    if (ranges.length === 0 && deletions.length === 0 && !atEnd) {
      return 0;
    }
    const blocks = annotatedBlocks(root);
    const found = changedBlocks(blocks, ranges).map((element) => ({ element, kind: "changed" }));
    const changedElements = new Set(found.map((entry) => entry.element));
    const deletionEntries = deletions.map((line) => deletionMark(blocks, line));
    if (atEnd && root.lastElementChild !== null) {
      deletionEntries.push({ element: root.lastElementChild, kind: "after" });
    }
    for (const entry of deletionEntries) {
      if (entry !== null && !changedElements.has(entry.element)) {
        found.push(entry);
        if (entry.kind === "changed") {
          changedElements.add(entry.element);
        }
      }
    }
    if (found.length === 0) {
      return 0;
    }
    layer = document.createElement("div");
    layer.setAttribute(LAYER, "");
    layer.setAttribute("aria-hidden", "true");
    document.body.append(layer);
    intersection = new IntersectionObserver(onIntersection);
    for (const entry of found) {
      const bar = document.createElement("div");
      bar.setAttribute(BAR, entry.kind);
      layer.append(bar);
      marks.push({ element: entry.element, kind: entry.kind, bar, timer: null });
      intersection.observe(entry.element);
    }
    resize = new ResizeObserver(() => requestAnimationFrame(layout));
    resize.observe(root);
    resize.observe(document.documentElement);
    layout();
    return marks.length;
  }

  // Removes every mark.
  function clear() {
    for (const entry of marks) {
      clearTimeout(entry.timer);
    }
    marks = [];
    intersection?.disconnect();
    intersection = null;
    resize?.disconnect();
    resize = null;
    layer?.remove();
    layer = null;
    report();
    return true;
  }

  // An element with no layout (in a folded section) is shown at its section: the closest
  // top-level block before it that has one.
  function visibleStandIn(element) {
    if (element.getClientRects().length > 0) {
      return element;
    }
    const root = article();
    let topLevel = element;
    while (topLevel.parentElement !== null && topLevel.parentElement !== root) {
      topLevel = topLevel.parentElement;
    }
    let candidate = topLevel.previousElementSibling;
    while (candidate !== null && candidate.getClientRects().length === 0) {
      candidate = candidate.previousElementSibling;
    }
    return candidate;
  }

  function isHidden(element) {
    return element.getClientRects().length === 0;
  }

  // Positions each bar beside its block, in document coordinates.
  function layout() {
    const root = article();
    if (layer === null || root === null) {
      return;
    }
    // Relative to the layer itself, wherever a theme's positioned body puts it.
    const origin = layer.getBoundingClientRect();
    const rootRect = root.getBoundingClientRect();
    const padding = Number.parseFloat(getComputedStyle(root).paddingLeft) || 0;
    const x = Math.max(2, rootRect.left + padding - GUTTER) - origin.left;
    for (const entry of marks) {
      const style = entry.bar.style;
      if (isHidden(entry.element)) {
        style.display = "none";
        continue;
      }
      const rect = entry.element.getBoundingClientRect();
      const top = rect.top - origin.top;
      style.display = "";
      style.left = `${x}px`;
      if (entry.kind === "changed") {
        style.top = `${top}px`;
        style.height = `${Math.max(rect.height, 4)}px`;
      } else {
        style.top = `${entry.kind === "before" ? top - 4 : top + rect.height + 2}px`;
        style.height = "";
      }
    }
    report();
  }

  // A mark on screen fades after `HOLD_MS`; one scrolled away first keeps going.
  function onIntersection(entries) {
    for (const change of entries) {
      if (!change.isIntersecting) {
        continue;
      }
      for (const entry of marks) {
        if (entry.element === change.target && entry.timer === null) {
          entry.timer = setTimeout(() => fade(entry), HOLD_MS);
        }
      }
    }
    report();
  }

  function fade(entry) {
    entry.bar.setAttribute(FADING, "");
    entry.timer = setTimeout(() => remove(entry), FADE_MS);
  }

  function remove(entry) {
    intersection?.unobserve(entry.element);
    entry.bar.remove();
    marks = marks.filter((other) => other !== entry);
    if (marks.length === 0) {
      clear();
    } else {
      report();
    }
  }

  // The top and bottom of a mark in viewport coordinates, or null without a stand-in.
  function viewportSpan(entry) {
    const element = visibleStandIn(entry.element);
    if (element === null) {
      return null;
    }
    const rect = element.getBoundingClientRect();
    return { top: rect.top, bottom: Math.max(rect.bottom, rect.top + 1) };
  }

  // Marks above and below the viewport that haven't started fading.
  function offScreen() {
    let above = 0;
    let below = 0;
    for (const entry of marks) {
      if (entry.timer !== null) {
        continue;
      }
      const span = viewportSpan(entry);
      if (span === null) {
        continue;
      }
      if (span.bottom <= 0) {
        above += 1;
      } else if (span.top >= window.innerHeight || isHidden(entry.element)) {
        below += 1;
      }
    }
    return { above, below };
  }

  // Tells the app the off-screen counts when they changed.
  function report() {
    const counts = offScreen();
    const key = `${counts.above},${counts.below}`;
    if (key === lastReport) {
      return;
    }
    lastReport = key;
    handler?.postMessage(counts);
  }

  // Scrolls the next mark out of view (below first, then from the top) a third of the way
  // down the viewport, unfolding its section. Returns whether there was one.
  function scrollToNext() {
    const pending = marks.filter((entry) => entry.timer === null);
    const withSpans = pending
      .map((entry) => ({ entry, span: viewportSpan(entry) }))
      .filter((item) => item.span !== null);
    const below = withSpans.filter(
      (item) => item.span.top >= window.innerHeight || isHidden(item.entry.element),
    );
    const above = withSpans.filter((item) => item.span.bottom <= 0);
    const byTop = (first, second) => first.span.top - second.span.top;
    const target = (below.length > 0 ? below.sort(byTop) : above.sort(byTop))[0];
    if (target === undefined) {
      return false;
    }
    scrollToEntry(target.entry);
    return true;
  }

  // Scrolls the first mark in the document into view, as `scrollToNext` does, unless a mark is
  // already on screen (the reader sees a change). Returns whether it scrolled.
  function scrollToFirst() {
    const withSpans = marks
      .map((entry) => ({ entry, span: viewportSpan(entry) }))
      .filter((item) => item.span !== null);
    const onScreen = withSpans.some(
      (item) =>
        !isHidden(item.entry.element) && item.span.bottom > 0 && item.span.top < window.innerHeight,
    );
    if (onScreen || withSpans.length === 0) {
      return false;
    }
    // Deletion marks are appended after changed blocks, so order by position, not by `marks`.
    const first = withSpans.reduce((best, item) => (item.span.top < best.span.top ? item : best));
    scrollToEntry(first.entry);
    return true;
  }

  // Unfolds `entry`'s section and puts its block a third of the way down the viewport.
  function scrollToEntry(entry) {
    sections()?.reveal(entry.element);
    const rect = entry.element.getBoundingClientRect();
    window.scrollTo(0, Math.max(0, rect.top + window.scrollY - window.innerHeight / 3));
    layout();
  }

  window.addEventListener(
    "scroll",
    () => {
      if (marks.length > 0 && !scrollPending) {
        scrollPending = true;
        requestAnimationFrame(() => {
          scrollPending = false;
          report();
        });
      }
    },
    { passive: true },
  );

  globalThis.peepChanges = Object.freeze({ mark, clear, scrollToNext, scrollToFirst });
})();
