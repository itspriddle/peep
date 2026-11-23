// Peep diagram controls: zoom, pan, and Open in Window for every diagram figure
// (`figure.peep-diagram`: the renderer's maps and STL models, and MermaidDiagrams.js's mermaid
// figures).
//
// Runs only in the app's isolated content world ("peep", see AppScripts.swift); page JavaScript
// is disabled. Not in the diagrams world: mermaid's world never gets a message handler. The
// `diagramWindow` message handler is registered in this world only; its message is the figure's
// index (a number), and the app reads the SVG back with `peepDiagramControls.markup(index)`.
//
// Each figure's SVG moves into a `div.peep-diagram-viewport` that keeps the SVG's unzoomed size
// (`overflow: hidden`), and zoom and pan are a CSS transform on the SVG, so zooming never moves
// the page or the reading position. The controls are buttons built with DOM calls (Octicon path
// data from primer/octicons, MIT, as constants), never markup strings. A MutationObserver
// attaches them to new figures: a load, an in-place content swap, or a mermaid re-render (which
// replaces the figure's children, dropping the viewport). ThemeBase never prints them.
"use strict";

(() => {
  const CONTROLS = "data-peep-diagram-controls";
  const ZOOMED = "data-peep-zoomed";
  const DRAGGING = "data-peep-dragging";
  const VIEWPORT_CLASS = "peep-diagram-viewport";
  const SVG_NS = "http://www.w3.org/2000/svg";
  const MINIMUM_SCALE = 1;
  const MAXIMUM_SCALE = 8;
  const ZOOM_STEP = 1.25;
  // A pan button moves a tenth of the diagram.
  const PAN_STEP = 0.1;

  // Octicons, 16px (primer/octicons 68ec2de, MIT; see Acknowledgements).
  const ICONS = Object.freeze({
    zoomIn: [
      "M3.75 7.5a.75.75 0 0 1 .75-.75h2.25V4.5a.75.75 0 0 1 1.5 0v2.25h2.25a.75.75 0 0 1 0 1.5H8.25v2.25a.75.75 0 0 1-1.5 0V8.25H4.5a.75.75 0 0 1-.75-.75Z",
      "M7.5 0a7.5 7.5 0 0 1 5.807 12.247l2.473 2.473a.749.749 0 1 1-1.06 1.06l-2.473-2.473A7.5 7.5 0 1 1 7.5 0Zm-6 7.5a6 6 0 1 0 12 0 6 6 0 0 0-12 0Z",
    ],
    zoomOut: [
      "M4.5 6.75h6a.75.75 0 0 1 0 1.5h-6a.75.75 0 0 1 0-1.5Z",
      "M0 7.5a7.5 7.5 0 1 1 13.307 4.747l2.473 2.473a.749.749 0 1 1-1.06 1.06l-2.473-2.473A7.5 7.5 0 0 1 0 7.5Zm7.5-6a6 6 0 1 0 0 12 6 6 0 0 0 0-12Z",
    ],
    reset: [
      "M1.705 8.005a.75.75 0 0 1 .834.656 5.5 5.5 0 0 0 9.592 2.97l-1.204-1.204a.25.25 0 0 1 .177-.427h3.646a.25.25 0 0 1 .25.25v3.646a.25.25 0 0 1-.427.177l-1.38-1.38A7.002 7.002 0 0 1 1.05 8.84a.75.75 0 0 1 .656-.834ZM8 2.5a5.487 5.487 0 0 0-4.131 1.869l1.204 1.204A.25.25 0 0 1 4.896 6H1.25A.25.25 0 0 1 1 5.75V2.104a.25.25 0 0 1 .427-.177l1.38 1.38A7.002 7.002 0 0 1 14.95 7.16a.75.75 0 0 1-1.49.178A5.5 5.5 0 0 0 8 2.5Z",
    ],
    up: [
      "M3.22 10.53a.749.749 0 0 1 0-1.06l4.25-4.25a.749.749 0 0 1 1.06 0l4.25 4.25a.749.749 0 1 1-1.06 1.06L8 6.811 4.28 10.53a.749.749 0 0 1-1.06 0Z",
    ],
    down: [
      "M12.78 5.22a.749.749 0 0 1 0 1.06l-4.25 4.25a.749.749 0 0 1-1.06 0L3.22 6.28a.749.749 0 1 1 1.06-1.06L8 8.939l3.72-3.719a.749.749 0 0 1 1.06 0Z",
    ],
    left: [
      "M9.78 12.78a.75.75 0 0 1-1.06 0L4.47 8.53a.75.75 0 0 1 0-1.06l4.25-4.25a.751.751 0 0 1 1.042.018.751.751 0 0 1 .018 1.042L6.06 8l3.72 3.72a.75.75 0 0 1 0 1.06Z",
    ],
    right: [
      "M6.22 3.22a.75.75 0 0 1 1.06 0l4.25 4.25a.75.75 0 0 1 0 1.06l-4.25 4.25a.751.751 0 0 1-1.042-.018.751.751 0 0 1-.018-1.042L9.94 8 6.22 4.28a.75.75 0 0 1 0-1.06Z",
    ],
    open: [
      "M1.75 10a.75.75 0 0 1 .75.75v2.5c0 .138.112.25.25.25h2.5a.75.75 0 0 1 0 1.5h-2.5A1.75 1.75 0 0 1 1 13.25v-2.5a.75.75 0 0 1 .75-.75Zm12.5 0a.75.75 0 0 1 .75.75v2.5A1.75 1.75 0 0 1 13.25 15h-2.5a.75.75 0 0 1 0-1.5h2.5a.25.25 0 0 0 .25-.25v-2.5a.75.75 0 0 1 .75-.75ZM2.75 2.5a.25.25 0 0 0-.25.25v2.5a.75.75 0 0 1-1.5 0v-2.5C1 1.784 1.784 1 2.75 1h2.5a.75.75 0 0 1 0 1.5ZM10 1.75a.75.75 0 0 1 .75-.75h2.5c.966 0 1.75.784 1.75 1.75v2.5a.75.75 0 0 1-1.5 0v-2.5a.25.25 0 0 0-.25-.25h-2.5a.75.75 0 0 1-.75-.75Z",
    ],
  });

  // Each viewport's zoom: `{ scale, x, y }`, x and y the SVG's offset in CSS pixels (≤ 0).
  const zooms = new WeakMap();

  function article() {
    return document.querySelector("article.markdown-body") ?? document.body;
  }

  function figures() {
    const root = article();
    return root === null ? [] : [...root.querySelectorAll("figure.peep-diagram")];
  }

  // The figure's diagram: its own SVG (in the viewport once attached).
  function diagramSVG(figure) {
    return figure.querySelector(`:scope > svg, :scope > .${VIEWPORT_CLASS} > svg`);
  }

  function icon(paths) {
    const svg = document.createElementNS(SVG_NS, "svg");
    svg.setAttribute("viewBox", "0 0 16 16");
    svg.setAttribute("aria-hidden", "true");
    for (const data of paths) {
      const path = document.createElementNS(SVG_NS, "path");
      path.setAttribute("d", data);
      svg.append(path);
    }
    return svg;
  }

  function button(label, paths, action) {
    const element = document.createElement("button");
    element.type = "button";
    element.title = label;
    element.setAttribute("aria-label", label);
    element.dataset.peepDiagramAction = action;
    element.append(icon(paths));
    return element;
  }

  function spacer() {
    return document.createElement("span");
  }

  function controls() {
    const container = document.createElement("div");
    container.setAttribute(CONTROLS, "");
    container.setAttribute("role", "toolbar");
    container.setAttribute("aria-label", "Diagram");
    container.append(button("Open in Window", ICONS.open, "open"));
    const pad = document.createElement("div");
    pad.className = "peep-diagram-pad";
    pad.append(
      spacer(), button("Pan Up", ICONS.up, "up"), button("Zoom In", ICONS.zoomIn, "zoom-in"),
      button("Pan Left", ICONS.left, "left"), button("Reset Zoom", ICONS.reset, "reset"),
      button("Pan Right", ICONS.right, "right"),
      spacer(), button("Pan Down", ICONS.down, "down"), button("Zoom Out", ICONS.zoomOut, "zoom-out"),
    );
    container.append(pad);
    return container;
  }

  // Wraps the figure's SVG in a viewport and adds the controls, unless it has both already.
  function attachTo(figure) {
    const svg = diagramSVG(figure);
    if (svg === null) {
      return;
    }
    let viewport = svg.parentElement;
    if (!viewport.classList.contains(VIEWPORT_CLASS)) {
      viewport = document.createElement("div");
      viewport.className = VIEWPORT_CLASS;
      svg.before(viewport);
      viewport.append(svg);
      zooms.delete(viewport);
    }
    if (figure.querySelector(`:scope > [${CONTROLS}]`) === null) {
      figure.append(controls());
    }
    apply(viewport);
  }

  function attach() {
    for (const figure of figures()) {
      attachTo(figure);
    }
  }

  function zoomOf(viewport) {
    return zooms.get(viewport) ?? { scale: 1, x: 0, y: 0 };
  }

  // The SVG's unzoomed size (a mermaid SVG can be narrower than the viewport, centered in it;
  // the transform's origin is the SVG's own corner).
  function sizeOf(viewport) {
    const svg = viewport.querySelector(":scope > svg");
    return { width: svg?.clientWidth ?? 0, height: svg?.clientHeight ?? 0 };
  }

  // Keeps the scaled SVG covering its own box (no empty space pulled in from an edge).
  function clamp(viewport, zoom) {
    const { width, height } = sizeOf(viewport);
    const scale = Math.min(MAXIMUM_SCALE, Math.max(MINIMUM_SCALE, zoom.scale));
    const x = Math.min(0, Math.max(width - width * scale, zoom.x));
    const y = Math.min(0, Math.max(height - height * scale, zoom.y));
    return { scale, x, y };
  }

  function apply(viewport, zoom = zoomOf(viewport)) {
    const svg = viewport.querySelector(":scope > svg");
    if (svg === null) {
      return;
    }
    const clamped = clamp(viewport, zoom);
    zooms.set(viewport, clamped);
    const zoomed = clamped.scale > MINIMUM_SCALE;
    svg.style.transform = zoomed ? `translate(${clamped.x}px, ${clamped.y}px) scale(${clamped.scale})` : "";
    viewport.toggleAttribute(ZOOMED, zoomed);
  }

  // Scales by `factor` around the SVG's center.
  function zoomBy(viewport, factor) {
    const { width, height } = sizeOf(viewport);
    const cx = width / 2;
    const cy = height / 2;
    const zoom = zoomOf(viewport);
    const scale = Math.min(MAXIMUM_SCALE, Math.max(MINIMUM_SCALE, zoom.scale * factor));
    const ratio = scale / zoom.scale;
    apply(viewport, { scale, x: cx - (cx - zoom.x) * ratio, y: cy - (cy - zoom.y) * ratio });
  }

  function panBy(viewport, dx, dy) {
    const zoom = zoomOf(viewport);
    apply(viewport, { scale: zoom.scale, x: zoom.x + dx, y: zoom.y + dy });
  }

  function reset(viewport) {
    apply(viewport, { scale: 1, x: 0, y: 0 });
  }

  function viewportOf(figure) {
    return figure.querySelector(`:scope > .${VIEWPORT_CLASS}`);
  }

  function perform(figure, action) {
    if (action === "open") {
      const index = figures().indexOf(figure);
      if (index >= 0) {
        globalThis.webkit?.messageHandlers?.diagramWindow?.postMessage(index);
      }
      return;
    }
    const viewport = viewportOf(figure);
    if (viewport === null) {
      return;
    }
    const size = sizeOf(viewport);
    const width = size.width * PAN_STEP;
    const height = size.height * PAN_STEP;
    switch (action) {
      case "zoom-in": zoomBy(viewport, ZOOM_STEP); break;
      case "zoom-out": zoomBy(viewport, 1 / ZOOM_STEP); break;
      case "reset": reset(viewport); break;
      // Panning up shows what's above: the SVG moves down.
      case "up": panBy(viewport, 0, height); break;
      case "down": panBy(viewport, 0, -height); break;
      case "left": panBy(viewport, width, 0); break;
      case "right": panBy(viewport, -width, 0); break;
      default: break;
    }
  }

  // The SVG's markup and label for the app's diagram window, without the zoom; null when there
  // is no such figure.
  function markup(index) {
    const figure = figures()[index];
    const svg = figure === undefined ? null : diagramSVG(figure);
    if (svg === null) {
      return null;
    }
    const clone = svg.cloneNode(true);
    clone.style.removeProperty("transform");
    if (clone.getAttribute("style") === "") {
      clone.removeAttribute("style");
    }
    const caption = figure.querySelector(":scope > figcaption")?.textContent?.trim() ?? "";
    return { svg: clone.outerHTML, label: caption === "" ? "Diagram" : caption };
  }

  // Listeners on the document survive in-place content swaps (`peep.replaceContent`).
  document.addEventListener("click", (event) => {
    const target = event.target instanceof Element ? event.target : null;
    const control = target?.closest(`[${CONTROLS}] button[data-peep-diagram-action]`) ?? null;
    const figure = control?.closest("figure.peep-diagram") ?? null;
    if (control === null || figure === null) {
      return;
    }
    event.preventDefault();
    event.stopPropagation();
    perform(figure, control.dataset.peepDiagramAction);
  });

  document.addEventListener("dblclick", (event) => {
    const target = event.target instanceof Element ? event.target : null;
    const viewport = target?.closest(`.${VIEWPORT_CLASS}[${ZOOMED}]`) ?? null;
    if (viewport !== null) {
      event.preventDefault();
      reset(viewport);
    }
  });

  // Dragging a zoomed diagram pans it.
  let drag = null;
  document.addEventListener("pointerdown", (event) => {
    const target = event.target instanceof Element ? event.target : null;
    const viewport = target?.closest(`.${VIEWPORT_CLASS}[${ZOOMED}]`) ?? null;
    if (viewport === null || event.button !== 0) {
      return;
    }
    event.preventDefault();
    const zoom = zoomOf(viewport);
    drag = { viewport, pointer: event.pointerId, startX: event.clientX, startY: event.clientY, zoom };
    viewport.setAttribute(DRAGGING, "");
    viewport.setPointerCapture(event.pointerId);
  });
  document.addEventListener("pointermove", (event) => {
    if (drag === null || event.pointerId !== drag.pointer) {
      return;
    }
    apply(drag.viewport, {
      scale: drag.zoom.scale,
      x: drag.zoom.x + event.clientX - drag.startX,
      y: drag.zoom.y + event.clientY - drag.startY,
    });
  });
  function endDrag(event) {
    if (drag === null || event.pointerId !== drag.pointer) {
      return;
    }
    drag.viewport.removeAttribute(DRAGGING);
    drag = null;
  }
  document.addEventListener("pointerup", endDrag);
  document.addEventListener("pointercancel", endDrag);

  // New figures (a load, a swap, a mermaid draw) get controls once the DOM settles.
  let scheduled = false;
  function schedule() {
    if (!scheduled) {
      scheduled = true;
      queueMicrotask(() => {
        scheduled = false;
        attach();
      });
    }
  }
  function observe() {
    new MutationObserver(schedule).observe(document.documentElement, { childList: true, subtree: true });
    attach();
  }
  if (document.documentElement === null) {
    document.addEventListener("DOMContentLoaded", observe, { once: true });
  } else {
    observe();
  }

  globalThis.peepDiagramControls = Object.freeze({
    attach,
    markup,
    // For tests: the figure's zoom, and the actions the buttons perform.
    zoom: (index) => {
      const figure = figures()[index];
      const viewport = figure === undefined ? null : viewportOf(figure);
      return viewport === null ? null : { ...zoomOf(viewport) };
    },
    perform: (index, action) => {
      const figure = figures()[index];
      if (figure !== undefined) {
        perform(figure, action);
      }
    },
  });
})();
