// Sources/SwiflowColor/ThemeGenerator.swift

/// Inputs for a generated theme (mirror the `swiflow theme` flags).
/// Each color is `oklch(L C H)` or hex (`#rgb`/`#rrggbb`) — see `Color.parseColor`.
public struct ThemeOptions: Equatable, Sendable {
    public var primary: String                 // brand color, oklch() or hex (required)
    public var danger: String?
    public var success: String?
    public var warning: String?
    public var info: String?                   // defaults to the accent when nil
    public var includeNeutrals: Bool
    public init(primary: String, danger: String? = nil, success: String? = nil,
                warning: String? = nil, info: String? = nil, includeNeutrals: Bool = false) {
        self.primary = primary; self.danger = danger; self.success = success
        self.warning = warning; self.info = info; self.includeNeutrals = includeNeutrals
    }
}

/// The outcome of a generation: `css` is always produced; `failures` lists every contrast
/// shortfall (empty == all pass). The caller decides whether failures are fatal.
public struct ThemeResult: Equatable, Sendable {
    public let css: String
    public let failures: [PaletteFailure]
    public var isValid: Bool { failures.isEmpty }
    public init(css: String, failures: [PaletteFailure]) {
        self.css = css; self.failures = failures
    }
}

public enum ThemeGenerator {
    /// Generate a Swiflow `:root` theme override. Throws `ThemeError.invalidHex` ONLY for
    /// malformed hex input; contrast shortfalls are returned in `result.failures`, not thrown.
    public static func generate(_ options: ThemeOptions) throws -> ThemeResult {
        let r = try Color.accentThemeCSS(primaryHex: options.primary,
                                         dangerHex: options.danger,
                                         successHex: options.success,
                                         warningHex: options.warning,
                                         infoHex: options.info,
                                         includeNeutrals: options.includeNeutrals)
        return ThemeResult(css: r.css, failures: r.failures)
    }
}
