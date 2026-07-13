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

/// A set of box edges for directional spacing modifiers (e.g. `.padding(.lg, .horizontal)`).
/// Logical / writing-mode & RTL aware: `leading`/`trailing` follow text direction
/// (inline-start/-end), `top`/`bottom` are block-start/-end.
public struct Edge: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let top      = Edge(rawValue: 1 << 0)   // block-start
    public static let bottom   = Edge(rawValue: 1 << 1)   // block-end
    public static let leading  = Edge(rawValue: 1 << 2)   // inline-start
    public static let trailing = Edge(rawValue: 1 << 3)   // inline-end

    public static let horizontal: Edge = [.leading, .trailing]
    public static let vertical:   Edge = [.top, .bottom]
    public static let all:        Edge = [.top, .bottom, .leading, .trailing]

    /// The atomic logical box-side suffixes this set covers (`block-start`, `inline-end`, …), in a
    /// stable order. Atomic only — never the `inline`/`block` axis shorthands — so directional
    /// spacing composes deterministically across chained modifiers over the unordered style dict.
    var logicalSides: [String] {
        var sides: [String] = []
        if contains(.top)      { sides.append("block-start") }
        if contains(.bottom)   { sides.append("block-end") }
        if contains(.leading)  { sides.append("inline-start") }
        if contains(.trailing) { sides.append("inline-end") }
        return sides
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
    case xs, sm, md, lg
    /// The `--<control>--<size>` modifier-class token (e.g. `sw-btn--sm`).
    /// Internal: an implementation detail of the `.sw-*` stylesheet, not API.
    var modifierClass: String {
        switch self {
        case .xs: return "xs"
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
