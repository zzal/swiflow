// Sources/SwiflowUI/Theme.swift
import Swiflow

/// Namespace for SwiflowUI's module-level theme surface.
public enum SwiflowUI {
    /// The design-token contract: the full `--sw-*` vocabulary at `:root`.
    /// v0 primitives consume only the spacing scale + alignment; the rest is
    /// the forward contract that skinned components will read. Authored as a
    /// `CSSSheet` so it's one source of truth; `:root` is left unscoped by
    /// `CSSSheet`'s scoping rules.
    public static let baseStyleSheet: CSSSheet = css {
        raw("""
        :root {
          --sw-space-xs: 0.25rem;
          --sw-space-sm: 0.5rem;
          --sw-space-md: 0.75rem;
          --sw-space-lg: 1.25rem;
          --sw-space-xl: 2rem;
          --sw-radius: 8px;
          --sw-accent: light-dark(#3b82f6, #60a5fa);
          --sw-surface: light-dark(#ffffff, #1a1a1a);
          --sw-text: light-dark(#111111, #f5f5f5);
          --sw-border: light-dark(#e5e7eb, #333333);
          --sw-border-width: 1px;
        }
        """)
    }

    /// Injects `baseStyleSheet` into `<head>` exactly once. Called automatically
    /// the first time any SwiflowUI primitive renders; also public so apps/tests
    /// can install deterministically up front (safe even before `Swiflow.render`
    /// — the registry buffers until the DOM sink is installed).
    @MainActor
    public static func installBaseStyles() {
        StyleInjectionRegistry.injectOnce(id: "swiflow-ui-base") {
            baseStyleSheet.cssString(scopeClass: "")
        }
    }
}

/// Internal trigger called by every primitive constructor. Idempotent.
@MainActor
func ensureBaseStyles() { SwiflowUI.installBaseStyles() }
