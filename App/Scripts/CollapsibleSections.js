// Peep collapsible sections: clicking a heading folds its section, everything after it up to the
// next heading of the same or a higher level (`#` folds the document, `##` its subsections too).
// Off until the app turns it on (Settings > General, `CollapsibleSectionsSettings`).
//
// Runs only in the app's isolated content world ("peep", see AppScripts.swift); page JavaScript
// is disabled. The page cannot see or call `peepSections`. Swift calls these functions with
// callAsyncJavaScript and passes values as arguments, never as script source. The other app
// scripts in this world (DocumentBridge.js, FindInPage.js) use `reveal` and `isFolded`.
//
// Sections are the direct children of the article: headings inside lists, quotes, or raw HTML
// don't fold, and the footnotes section never does. Folded blocks get `data-peep-folded`, which
// the base layer (PeepCore `ThemeBase`) hides; collapsed headings get `data-peep-collapsed` (the
// chevron). The sanitizer allows no `data-` attributes, so a document can't set either.
"use strict";

(() => {
  const FOLDED = "data-peep-folded";
  const COLLAPSED = "data-peep-collapsed";
  const ENABLED = "data-peep-sections";
  const HEADINGS = new Map([["H1", 1], ["H2", 2], ["H3", 3], ["H4", 4], ["H5", 5], ["H6", 6]]);

  let enabled = false;
  // Collapsed headings (direct children of the article).
  const collapsed = new Set();
  // Headings this script gave a `tabindex` (raw HTML headings may bring their own).
  let focusable = new WeakSet();
  // The heading the last single click toggled, so the second click of a double-click (which
  // selects a word) can undo it.
  let clickToggled = null;

  function article() {
    return document.querySelector("article.markdown-body");
  }

  function level(element) {
    return HEADINGS.get(element.tagName) ?? 0;
  }

  function sectionHeadings(root) {
    return [...root.children].filter((element) => level(element) > 0);
  }

  // The top-level heading `target` is in, or null.
  function headingFor(target) {
    const root = article();
    let element = target instanceof Element ? target : target?.parentElement ?? null;
    if (root === null || element === null || !root.contains(element)) {
      return null;
    }
    while (element.parentElement !== root) {
      element = element.parentElement;
    }
    return level(element) > 0 ? element : null;
  }

  // Sets each block's folded state from `collapsed`, in one pass over the article.
  function recompute() {
    const root = article();
    if (root === null) {
      return;
    }
    for (const heading of [...collapsed]) {
      if (heading.parentElement !== root) {
        collapsed.delete(heading);
      }
    }
    // The level of the collapsed heading being folded under, or 0.
    let foldLevel = 0;
    for (const child of root.children) {
      const childLevel = level(child);
      if (childLevel > 0 && foldLevel > 0 && childLevel <= foldLevel) {
        foldLevel = 0;
      }
      child.toggleAttribute(FOLDED, foldLevel > 0 && !child.classList.contains("footnotes"));
      if (childLevel > 0) {
        const isCollapsed = collapsed.has(child);
        child.toggleAttribute(COLLAPSED, isCollapsed);
        child.setAttribute("aria-expanded", String(!isCollapsed));
        if (!child.hasAttribute("tabindex")) {
          child.setAttribute("tabindex", "0");
          focusable.add(child);
        }
        if (foldLevel === 0 && isCollapsed) {
          foldLevel = childLevel;
        }
      }
    }
  }

  // Removes everything this script added to the article.
  function strip() {
    const root = article();
    if (root === null) {
      return;
    }
    for (const child of root.children) {
      child.removeAttribute(FOLDED);
      if (level(child) > 0) {
        child.removeAttribute(COLLAPSED);
        child.removeAttribute("aria-expanded");
        if (focusable.has(child)) {
          child.removeAttribute("tabindex");
        }
      }
    }
    focusable = new WeakSet();
  }

  // Folds or unfolds `heading`'s section, keeping the heading where it is on screen.
  function toggle(heading) {
    const top = heading.getBoundingClientRect().top;
    if (!collapsed.delete(heading)) {
      collapsed.add(heading);
    }
    recompute();
    const moved = heading.getBoundingClientRect().top - top;
    if (moved !== 0) {
      window.scrollBy(0, moved);
    }
  }

  // Turns the feature on or off. Turning it off unfolds everything; turning it on (again) keeps
  // what is collapsed.
  function setEnabled(on) {
    const wasEnabled = enabled;
    enabled = on === true;
    document.documentElement.toggleAttribute(ENABLED, enabled);
    if (enabled && wasEnabled) {
      recompute();
      return true;
    }
    collapsed.clear();
    clickToggled = null;
    if (enabled) {
      recompute();
    } else {
      strip();
    }
    return true;
  }

  function collapseAll() {
    const root = article();
    if (!enabled || root === null) {
      return false;
    }
    for (const heading of sectionHeadings(root)) {
      collapsed.add(heading);
    }
    recompute();
    return true;
  }

  function expandAll() {
    if (!enabled) {
      return false;
    }
    collapsed.clear();
    recompute();
    return true;
  }

  // Unfolds every section that hides `node` (the headings above it, by level). The node's own
  // heading keeps its state: revealing a heading shows the heading, not its section. Returns
  // whether anything unfolded.
  function reveal(node) {
    const root = article();
    let block = node instanceof Element ? node : node?.parentElement ?? null;
    if (!enabled || collapsed.size === 0 || root === null || block === null || !root.contains(block)
      || block === root) {
      return false;
    }
    while (block.parentElement !== root) {
      block = block.parentElement;
    }
    let changed = false;
    let limit = level(block) || 7;
    for (let element = block.previousElementSibling; element !== null && limit > 1;
      element = element.previousElementSibling) {
      const elementLevel = level(element);
      if (elementLevel > 0 && elementLevel < limit) {
        changed = collapsed.delete(element) || changed;
        limit = elementLevel;
      }
    }
    if (changed) {
      recompute();
    }
    return changed;
  }

  function isFolded(element) {
    return element instanceof Element && element.closest(`[${FOLDED}]`) !== null;
  }

  // A key per heading that survives re-rendering: its id, else its level and text, plus how many
  // headings before it had the same one.
  function headingKeys(root) {
    const counts = new Map();
    return sectionHeadings(root).map((heading) => {
      const base = heading.id === "" ? `h${level(heading)}:${heading.textContent.trim()}` : `#${heading.id}`;
      const count = counts.get(base) ?? 0;
      counts.set(base, count + 1);
      return { heading, key: `${base}\u0000${count}` };
    });
  }

  // The keys of the collapsed headings, before the article's content is replaced.
  function capture() {
    const root = article();
    if (!enabled || collapsed.size === 0 || root === null) {
      return [];
    }
    return headingKeys(root).filter(({ heading }) => collapsed.has(heading)).map(({ key }) => key);
  }

  // Collapses the headings of the new content whose keys `capture()` returned.
  function restore(keys) {
    collapsed.clear();
    clickToggled = null;
    const root = article();
    if (!enabled || root === null) {
      return false;
    }
    const wanted = new Set(Array.isArray(keys) ? keys.filter((key) => typeof key === "string") : []);
    if (wanted.size > 0) {
      for (const { heading, key } of headingKeys(root)) {
        if (wanted.has(key)) {
          collapsed.add(heading);
        }
      }
    }
    recompute();
    return true;
  }

  // Listeners on the document survive in-place content swaps (`peep.replaceContent`).
  document.addEventListener("click", (event) => {
    if (!enabled || event.button !== 0 || event.metaKey || event.ctrlKey || event.altKey || event.shiftKey) {
      return;
    }
    const target = event.target instanceof Element ? event.target : event.target?.parentElement ?? null;
    if (target === null || target.closest("a[href]") !== null) {
      return;
    }
    const heading = headingFor(target);
    if (heading === null) {
      return;
    }
    // Detail 0 is a click without a pointer (accessibility actions, `element.click()`).
    if (event.detail <= 1) {
      // A drag that selected text in the heading isn't a click on it.
      const selection = document.getSelection();
      if (selection !== null && !selection.isCollapsed && heading.contains(selection.anchorNode)) {
        clickToggled = null;
        return;
      }
      clickToggled = heading;
      toggle(heading);
    } else if (event.detail === 2 && clickToggled === heading) {
      clickToggled = null;
      toggle(heading);
    }
  });

  document.addEventListener("keydown", (event) => {
    if (!enabled || (event.key !== "Enter" && event.key !== " ")
      || event.metaKey || event.ctrlKey || event.altKey || event.shiftKey) {
      return;
    }
    const heading = event.target instanceof Element ? headingFor(event.target) : null;
    if (heading === null || heading !== event.target) {
      return;
    }
    event.preventDefault();
    toggle(heading);
  });

  globalThis.peepSections = Object.freeze({
    setEnabled, collapseAll, expandAll, reveal, isFolded, capture, restore,
  });
})();
