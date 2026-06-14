// Sources/SwiflowUI/Tokens.swift

/// A spacing value drawn from the `--sw-space-*` scale (or an arbitrary length).
/// `.css` is the CSS value written inline (token-var or raw literal); reskinning
/// happens by overriding the var at `:root`, even for inline uses.
public enum Spacing: Equatable {
    case none, xs, sm, md, lg, xl
    case custom(String)

    public var css: String {
        switch self {
        case .none:          return "0"
        case .xs:            return "var(--sw-space-xs)"
        case .sm:            return "var(--sw-space-sm)"
        case .md:            return "var(--sw-space-md)"
        case .lg:            return "var(--sw-space-lg)"
        case .xl:            return "var(--sw-space-xl)"
        case .custom(let v): return v
        }
    }
}

/// Cross-axis alignment → `align-items`.
public enum CrossAlign: Equatable {
    case start, center, end, stretch, baseline
    public var css: String {
        switch self {
        case .start:    return "flex-start"
        case .center:   return "center"
        case .end:      return "flex-end"
        case .stretch:  return "stretch"
        case .baseline: return "baseline"
        }
    }
}

/// Control sizing scale, shared across skinned controls (`Button` now, the M4
/// form controls next). Maps to a `--<control>--<size>` modifier class; the
/// concrete padding / font-size live in each control's stylesheet, so sizing
/// stays token-driven and reskinnable.
public enum ControlSize: Equatable {
    case sm, md, lg
    /// The `--<control>--<size>` modifier-class token (e.g. `sw-btn--sm`).
    public var modifierClass: String {
        switch self {
        case .sm: return "sm"
        case .md: return "md"
        case .lg: return "lg"
        }
    }
}

/// Main-axis distribution → `justify-content`.
public enum MainAlign: Equatable {
    case start, center, end, between, around, evenly
    public var css: String {
        switch self {
        case .start:   return "flex-start"
        case .center:  return "center"
        case .end:     return "flex-end"
        case .between: return "space-between"
        case .around:  return "space-around"
        case .evenly:  return "space-evenly"
        }
    }
}
