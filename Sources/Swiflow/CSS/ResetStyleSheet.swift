// Sources/Swiflow/CSS/ResetStyleSheet.swift
//
// A small, modern CSS reset shipped to EVERY Swiflow app through the core
// StyleInjectionRegistry — so even a bare `Swiflow.render` app that never
// imports SwiflowUI gets sane defaults. It is wrapped in `@layer reset`:
// unlayered rules (every SwiflowUI sheet, every component `scopedStyles`, and
// anything in the app's own index.html) always win the cascade over a layer,
// regardless of source order or specificity — so the reset never fights
// authored styles and the "inject it first" ordering dance is unnecessary.

/// The reset, as one CSS string. SwiflowDOM emits it verbatim into a `<head>`
/// `<style id="swiflow-reset">`; `@layer reset` keeps every rule overridable.
public let swiflowResetCSS = """
@layer reset {

  /* 1. Predictable box model on every element and pseudo-element. */
  *, *::before, *::after {
    box-sizing: border-box;
  }

  /* 2. Stop iOS from inflating text on orientation change. */
  html {
    -webkit-text-size-adjust: 100%;
    text-size-adjust: 100%;
  }

  /* 3. Drop the UA body margin and fill the viewport. 100dvh matches the value
        the scaffold index.html ships, so the framework agrees with its own
        template (svh would be steadier on mobile but contradict every example). */
  body {
    margin: 0;
    min-block-size: 100dvh;
    line-height: 1.5;
  }

  /* 4. Responsive media: block-level, never overflow the container, keep ratio. */
  img, picture, video, canvas, svg {
    display: block;
    max-width: 100%;
    height: auto;
  }

  /* 5. Form controls inherit typography instead of the UA's tiny default;
        unsized textareas grow with their content where supported (else no-op). */
  input, button, textarea, select {
    font: inherit;
  }

  textarea:not([rows]) {
    field-sizing: content;
  }

  /* 6. Headings, paragraphs & lists: drop the UA block margins so vertical
        spacing is owned by layout (stacks / gap), not inherited UA defaults;
        wrap long words, balance headings, trim orphans. text-wrap balance/pretty
        are progressive — ignored where unsupported. */
  p, h1, h2, h3, h4, h5, h6 {
    margin-block: 0;
    overflow-wrap: break-word;
  }

  /* Zero list block margins too; the inline padding (bullet/number indent) is
     left untouched, so lists still read as lists. */
  ul, ol {
    margin-block: 0;
  }

  h1, h2, h3, h4, h5, h6 {
    text-wrap: balance;
  }

  p {
    text-wrap: pretty;
  }

  /* 7. Reduced-motion floor for EVERY app. SwiflowUI layers its own
        token-based handling on top (--sw-duration / --sw-anim-play); this also
        covers apps that don't use SwiflowUI at all. The `!important` here wins
        even over unlayered rules (important declarations invert layer order),
        which is the intent: accessibility settings should not be overridable. */
  @media (prefers-reduced-motion: reduce) {
    html:focus-within {
      scroll-behavior: auto;
    }
    *, *::before, *::after {
      animation-duration: 0.01ms !important;
      animation-iteration-count: 1 !important;
      transition-duration: 0.01ms !important;
      scroll-behavior: auto !important;
    }
  }
}
"""

/// Registers `swiflowResetCSS` under the id `"swiflow-reset"` exactly once.
/// Called by SwiflowDOM as it wires the `<head>` style sink (see CSSInjector),
/// so the reset is the earliest `<style>` in the document. Host-testable: the
/// registry buffers the emit until a sink is installed, so this is safe to call
/// before `Swiflow.render` and assertable without a DOM.
@MainActor
public func installResetStyles() {
    StyleInjectionRegistry.injectOnce(id: "swiflow-reset") { swiflowResetCSS }
}
