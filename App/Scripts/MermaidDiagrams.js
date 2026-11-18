// Peep mermaid diagrams (#117): draws each mermaid code block of the loaded page as an SVG.
//
// Runs only in the diagrams content world ("peep-diagrams", see DiagramScripts.swift), right
// after the vendored mermaid.min.js, and only in pages that have mermaid blocks. That world has
// no message handlers and is separate from the app's bridge world ("peep"), so nothing mermaid
// does can reach the app. Page JavaScript stays disabled; the page cannot see `mermaid` or
// `peepDiagrams`. Swift calls `peepDiagrams.render(dark)` with callAsyncJavaScript and passes
// values as arguments, never as script source.
//
// A block's source is its code element's `textContent` (a value handed to mermaid, never run).
// mermaid renders with `securityLevel: "strict"` (labels sanitized with DOMPurify, no click
// handlers, no HTML in text), and the SVG is inserted in a `figure.peep-diagram` right after the
// block; event attributes and scripts are stripped from it again, belt and braces. The `pre`
// stays in the DOM, hidden by ThemeBase's `pre[data-peep-diagram="rendered"]` rule, and its
// `data-source-line` moves to the figure while it's hidden, so reading positions, scrolling to a
// line, and change marks use the diagram. A block mermaid can't draw stays visible with a short
// note after it. Re-rendering (a theme or appearance change) replaces each figure's SVG in place.
"use strict";

(() => {
  const STATE = "data-peep-diagram";
  const SOURCE_LINE = "data-source-line";
  // The pre's source line while its figure holds it.
  const HIDDEN_SOURCE_LINE = "data-peep-diagram-line";
  const FOLDED = "data-peep-folded";
  // The renderer's diagram figure classes (PeepCore `HTMLRenderer+Diagrams`), so ThemeBase's
  // `.peep-diagram` styles apply.
  const FIGURE_CLASS = "peep-diagram peep-diagram-mermaid";
  const NOTE_CLASS = "peep-diagram-error";
  const MAXIMUM_NOTE_LENGTH = 200;

  let queue = Promise.resolve();
  let generation = 0;
  let counter = 0;

  function article() {
    return document.querySelector("article.markdown-body") ?? document.body;
  }

  function isMermaid(code) {
    return [...code.classList].some((name) => name.toLowerCase() === "language-mermaid");
  }

  // Code elements of mermaid blocks, in document order.
  function blocks() {
    return [...article().querySelectorAll("pre > code")].filter(isMermaid);
  }

  // This script's figure or note right after `pre`, if any.
  function sibling(pre, kind) {
    const next = pre.nextElementSibling;
    return next !== null && next.getAttribute(STATE) === kind ? next : null;
  }

  function hideSourceLine(pre, figure) {
    const line = pre.getAttribute(SOURCE_LINE) ?? pre.getAttribute(HIDDEN_SOURCE_LINE);
    if (line !== null) {
      pre.setAttribute(HIDDEN_SOURCE_LINE, line);
      pre.removeAttribute(SOURCE_LINE);
      figure.setAttribute(SOURCE_LINE, line);
    }
  }

  function restoreSourceLine(pre) {
    const line = pre.getAttribute(HIDDEN_SOURCE_LINE);
    if (line !== null) {
      pre.setAttribute(SOURCE_LINE, line);
      pre.removeAttribute(HIDDEN_SOURCE_LINE);
    }
  }

  // Removes anything that could run or load script from mermaid's output: `script` and
  // `foreignObject` scripts, every `on*` attribute, and `javascript:` links.
  function scrub(root) {
    for (const element of root.querySelectorAll("script")) {
      element.remove();
    }
    for (const element of root.querySelectorAll("*")) {
      for (const attribute of [...element.attributes]) {
        const name = attribute.name.toLowerCase();
        const isLink = name === "href" || name === "xlink:href" || name === "src";
        if (name.startsWith("on") || (isLink && /^\s*javascript:/i.test(attribute.value))) {
          element.removeAttribute(attribute.name);
        }
      }
    }
  }

  function removeNote(pre) {
    sibling(pre, "note")?.remove();
  }

  function removeFigure(pre) {
    sibling(pre, "figure")?.remove();
    restoreSourceLine(pre);
  }

  function show(pre, svg) {
    removeNote(pre);
    let figure = sibling(pre, "figure");
    if (figure === null) {
      figure = document.createElement("figure");
      figure.className = FIGURE_CLASS;
      figure.setAttribute(STATE, "figure");
      pre.after(figure);
    }
    const template = document.createElement("template");
    template.innerHTML = svg;
    scrub(template.content);
    figure.replaceChildren(template.content);
    // A block in a folded section (CollapsibleSections.js) stays folded with its figure.
    figure.toggleAttribute(FOLDED, pre.hasAttribute(FOLDED));
    hideSourceLine(pre, figure);
    pre.setAttribute(STATE, "rendered");
  }

  function fail(pre, error) {
    removeFigure(pre);
    pre.setAttribute(STATE, "error");
    const message = String(error?.message ?? error ?? "").split("\n")[0].trim();
    let text = message === "" ? "This Mermaid diagram couldn't be drawn." : `Mermaid: ${message}`;
    if (text.length > MAXIMUM_NOTE_LENGTH) {
      text = `${text.slice(0, MAXIMUM_NOTE_LENGTH - 1)}…`;
    }
    let note = sibling(pre, "note");
    if (note === null) {
      note = document.createElement("p");
      note.className = NOTE_CLASS;
      note.setAttribute(STATE, "note");
      note.setAttribute("role", "note");
      pre.after(note);
    }
    note.toggleAttribute(FOLDED, pre.hasAttribute(FOLDED));
    note.textContent = text;
  }

  // mermaid leaves its scratch element (`#d<id>`) in the body when a render fails.
  function removeScratch(id) {
    for (const scratchID of [`d${id}`, id]) {
      const element = document.getElementById(scratchID);
      if (element !== null && element.closest(`[${STATE}]`) === null) {
        element.remove();
      }
    }
  }

  async function renderAll(dark, run) {
    const result = { rendered: 0, failed: 0 };
    if (run !== generation) {
      return result;
    }
    mermaid.initialize({
      startOnLoad: false,
      securityLevel: "strict",
      theme: dark ? "dark" : "default",
      suppressErrorRendering: true,
    });
    for (const code of blocks()) {
      // A newer render (a content swap or theme change) supersedes this one.
      if (run !== generation) {
        break;
      }
      const pre = code.parentElement;
      const source = code.textContent;
      counter += 1;
      const id = `peep-diagram-${counter}`;
      try {
        const { svg } = await mermaid.render(id, source);
        if (pre.isConnected && run === generation) {
          show(pre, svg);
          result.rendered += 1;
        }
      } catch (error) {
        removeScratch(id);
        if (pre.isConnected && run === generation) {
          fail(pre, error);
          result.failed += 1;
        }
      }
    }
    return result;
  }

  // Draws every mermaid block in the page, with mermaid's dark theme when `dark`. Runs one at
  // a time; returns `{ rendered, failed }`.
  function render(dark) {
    generation += 1;
    const run = generation;
    const next = queue.then(() => renderAll(dark === true, run));
    queue = next.catch(() => {});
    return next;
  }

  globalThis.peepDiagrams = Object.freeze({ render });
})();
