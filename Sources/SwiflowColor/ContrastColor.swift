import Foundation

/// A color in linear-light sRGB. Components are nominally 0...1 but may fall
/// outside during intermediate math (clamp before using as a rendered color).
public struct LinRGB: Equatable, Sendable {
    public var r: Double, g: Double, b: Double
    /// WCAG relative luminance.
    public var luminance: Double { 0.2126 * r + 0.7152 * g + 0.0722 * b }
    public static let black = LinRGB(r: 0, g: 0, b: 0)
    public static let white = LinRGB(r: 1, g: 1, b: 1)
}

/// Test-only color pipeline that replicates the browser math the base stylesheet
/// relies on, so `ThemeContrastTests` can prove the shipped defaults meet WCAG.
/// Nothing here ships in the SwiflowUI module.
public enum Color {
    /// sRGB gamma-encoded channel (0...1) → linear-light.
    static func gammaToLinear(_ c: Double) -> Double {
        c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }
    /// "#rrggbb" → linear-light sRGB. Expects a valid 6-digit hex (e.g. as produced by
    /// `normalizeHex`); traps on malformed input — gate user input through `normalizeHex` first.
    public static func hex(_ hex: String) -> LinRGB {
        let h = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        let v = UInt32(h, radix: 16)!
        let r = Double((v >> 16) & 0xff) / 255.0
        let g = Double((v >> 8) & 0xff) / 255.0
        let b = Double(v & 0xff) / 255.0
        return LinRGB(r: gammaToLinear(r), g: gammaToLinear(g), b: gammaToLinear(b))
    }
    /// WCAG 2.x contrast ratio between two colors (order-independent).
    public static func wcagContrast(_ x: LinRGB, _ y: LinRGB) -> Double {
        let hi = max(x.luminance, y.luminance), lo = min(x.luminance, y.luminance)
        return (hi + 0.05) / (lo + 0.05)
    }
}

/// OKLab (L, a, b) — Björn Ottosson's perceptual space.
public struct OKLab: Equatable, Sendable { public var L: Double, a: Double, b: Double }
/// OKLCH (L, C, H in radians).
public struct OKLCH: Equatable, Sendable { public var L: Double, C: Double, H: Double }

extension Color {
    public static func linRGBToOKLab(_ c: LinRGB) -> OKLab {
        let l = 0.4122214708 * c.r + 0.5363325363 * c.g + 0.0514459929 * c.b
        let m = 0.2119034982 * c.r + 0.6806995451 * c.g + 0.1073969566 * c.b
        let s = 0.0883024619 * c.r + 0.2817188376 * c.g + 0.6299787005 * c.b
        let l_ = cbrt(l), m_ = cbrt(m), s_ = cbrt(s)
        return OKLab(
            L: 0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_,
            a: 1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_,
            b: 0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_)
    }
    public static func okLabToLinRGB(_ c: OKLab) -> LinRGB {
        let l_ = c.L + 0.3963377774 * c.a + 0.2158037573 * c.b
        let m_ = c.L - 0.1055613458 * c.a - 0.0638541728 * c.b
        let s_ = c.L - 0.0894841775 * c.a - 1.2914855480 * c.b
        let l = l_ * l_ * l_, m = m_ * m_ * m_, s = s_ * s_ * s_
        return LinRGB(
            r:  4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
            g: -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
            b: -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s)
    }
    public static func okLabToOKLCH(_ c: OKLab) -> OKLCH {
        OKLCH(L: c.L, C: (c.a * c.a + c.b * c.b).squareRoot(), H: atan2(c.b, c.a))
    }
    static func okLCHToOKLab(_ c: OKLCH) -> OKLab {
        OKLab(L: c.L, a: c.C * cos(c.H), b: c.C * sin(c.H))
    }
    /// Per-channel clamp into the sRGB gamut. The browser does CSS Color 4 chroma-
    /// reduction; a per-channel clamp is a close-enough approximation for a luminance
    /// assertion, and barely triggers for our in-gamut hues at the chosen lightnesses.
    static func clampGamut(_ c: LinRGB) -> LinRGB {
        LinRGB(r: min(max(c.r, 0), 1), g: min(max(c.g, 0), 1), b: min(max(c.b, 0), 1))
    }
    /// CSS `color-mix(in oklab, base <weightBase·100>%, other)`: lerp in OKLab.
    public static func mixOKLab(_ base: LinRGB, _ other: LinRGB, weightBase w: Double) -> LinRGB {
        let a = linRGBToOKLab(base), b = linRGBToOKLab(other)
        return clampGamut(okLabToLinRGB(OKLab(
            L: w * a.L + (1 - w) * b.L,
            a: w * a.a + (1 - w) * b.a,
            b: w * a.b + (1 - w) * b.b)))
    }
    /// CSS `oklch(from <source> <lightness> c h)`: source chroma+hue, replaced lightness.
    public static func oklchFrom(_ source: LinRGB, lightness: Double) -> LinRGB {
        let lch = okLabToOKLCH(linRGBToOKLab(source))
        return clampGamut(okLabToLinRGB(okLCHToOKLab(OKLCH(L: lightness, C: lch.C, H: lch.H))))
    }
    /// CSS `contrast-color(<bg>)`: black or white, whichever maximizes WCAG contrast.
    public static func contrastColor(against bg: LinRGB) -> LinRGB {
        wcagContrast(.black, bg) >= wcagContrast(.white, bg) ? .black : .white
    }
}

extension Color {
    /// Linear channel → sRGB gamma-encoded (inverse of `gammaToLinear`).
    static func linearToGamma(_ c: Double) -> Double {
        c <= 0.0031308 ? 12.92 * c : 1.055 * pow(c, 1.0 / 2.4) - 0.055
    }
    /// Linear-light sRGB → "#rrggbb" (gamut-clamped, 8-bit).
    public static func hexString(_ c: LinRGB) -> String {
        func channel(_ v: Double) -> Int { Int((min(max(linearToGamma(v), 0), 1) * 255).rounded()) }
        return String(format: "#%02x%02x%02x", channel(c.r), channel(c.g), channel(c.b))
    }
    /// Derive a dark-mode accent from a light-mode seed: raise OKLCH lightness into the
    /// dark-mode band and modestly reduce chroma, preserving hue. NOTE: this does not exactly
    /// reproduce the shipped `#3b82f6 → #60a5fa` default pair (that was hand-tuned); a user
    /// running `theme --primary "#3b82f6"` gets a near-but-different dark arm. Roughly reproduces the
    /// shipped #3b82f6 → #60a5fa pairing. Constants tunable; validation is the safety net.
    public static func darkAccent(from hex: String) -> String {
        let lch = okLabToOKLCH(linRGBToOKLab(Color.hex(hex)))
        let darkL = min(max(lch.L + 0.10, 0.68), 0.76)
        let darkC = lch.C * 0.78
        let lin = clampGamut(okLabToLinRGB(okLCHToOKLab(OKLCH(L: darkL, C: darkC, H: lch.H))))
        return hexString(lin)
    }
}

extension Color {
    /// One WCAG shortfall for a generated token, in one color scheme.
    public struct PaletteFailure: Equatable, Sendable, CustomStringConvertible {
        public let token: String
        public let mode: String        // "light" | "dark"
        public let ratio: Double
        public let target: Double
        public var description: String {
            String(format: "%@ (%@): %.2f:1 < %.1f:1 required", token, mode, ratio, target)
        }
    }

    public enum PaletteError: Error, CustomStringConvertible {
        case invalidHex(String)
        case contrastFailures([PaletteFailure])
        public var description: String {
            switch self {
            case .invalidHex(let s):
                return "invalid theme color hex: \(s) (expected #rgb or #rrggbb)"
            case .contrastFailures(let fs):
                return "brand color fails WCAG for the derived accent family:\n  "
                    + fs.map(\.description).joined(separator: "\n  ")
            }
        }
    }

    /// Validate "#rgb"/"#rrggbb" and normalize to lowercase "#rrggbb".
    static func normalizeHex(_ raw: String) throws -> String {
        let h = raw.hasPrefix("#") ? String(raw.dropFirst()) : raw
        let ok = h.allSatisfy { "0123456789abcdefABCDEF".contains($0) }
        guard ok, h.count == 3 || h.count == 6 else { throw PaletteError.invalidHex(raw) }
        let full = h.count == 3 ? h.map { "\($0)\($0)" }.joined() : h
        return "#" + full.lowercased()
    }

    // The shipped contract these tokens must satisfy (mirrors Theme.swift):
    private static let surfaceLight = "#ffffff", surfaceDark = "#1a1a1a"
    private static let tintWeight = 0.15
    // -strong lightnesses: (normal 4.5 → light/dark), (more-contrast 7 → light/dark)
    private static let strongAA: (Double, Double) = (0.40, 0.80)
    private static let strongAAA: (Double, Double) = (0.30, 0.88)

    /// Recompute the accent-derived tokens (-strong at 4.5 + 7, -text, and --sw-accent used
    /// as text/links) for the given light/dark accents and return every WCAG shortfall.
    public static func validateAccentFamily(lightAccentHex: String, darkAccentHex: String) -> [PaletteFailure] {
        var out: [PaletteFailure] = []
        let modes: [(String, String, String, Double, Double)] = [
            // mode, accentHex, surfaceHex, strongL(AA), strongL(AAA)
            ("light", lightAccentHex, surfaceLight, strongAA.0, strongAAA.0),
            ("dark",  darkAccentHex,  surfaceDark,  strongAA.1, strongAAA.1),
        ]
        for (mode, accentHex, surfaceHex, lAA, lAAA) in modes {
            let accent = hex(accentHex)
            let tint = mixOKLab(accent, hex(surfaceHex), weightBase: tintWeight)
            // --sw-accent used as TEXT (ghost buttons, links) on the surface. UI/large-text
            // bar (3:1): catches washed-out brand colors while allowing conventional
            // blue-on-white links (the default #3b82f6 is 3.68:1).
            let rAccentText = wcagContrast(accent, hex(surfaceHex))
            if rAccentText < 3.0 { out.append(.init(token: "--sw-accent (as text/links)", mode: mode, ratio: rAccentText, target: 3.0)) }
            // -strong on the tint: 4.5 normal, 7 under prefers-contrast: more.
            let rAA = wcagContrast(oklchFrom(accent, lightness: lAA), tint)
            if rAA < 4.5 { out.append(.init(token: "--sw-accent-strong", mode: mode, ratio: rAA, target: 4.5)) }
            let rAAA = wcagContrast(oklchFrom(accent, lightness: lAAA), tint)
            if rAAA < 7.0 { out.append(.init(token: "--sw-accent-strong (more-contrast)", mode: mode, ratio: rAAA, target: 7.0)) }
            // -text on the solid accent: the Baseline contrast-color() result. We do NOT
            // validate the static #0b1220 fallback — it's tuned for the default (light) accent
            // and is sub-AA on medium-dark custom accents (violet/indigo) where contrast-color
            // correctly flips to white. contrast-color is Baseline 2026, so the fallback is a
            // pre-Baseline-only courtesy; gating on it would reject common brand colors. See
            // the palette-generator spec's "legacy fallback gap" note.
            let rText = wcagContrast(contrastColor(against: accent), accent)
            if rText < 4.5 { out.append(.init(token: "--sw-accent-text", mode: mode, ratio: rText, target: 4.5)) }
        }
        return out
    }

    /// Validate one fixed-hue status token (danger/success) against how it is actually used:
    /// the RAW token on the surface at `rawBar` (danger renders as error text → pass 4.5;
    /// success is borders/tints only → pass 3.0), and the base-sheet-derived `-strong`
    /// (L 0.40/0.80 normal, 0.30/0.88 more-contrast) on the 15% tint at 4.5 / 7. No `-text`
    /// check — there are no solid-fill status buttons. Mirrors `validateAccentFamily`'s machinery.
    public static func validateStatusFamily(name: String,
                                            lightHex: String,
                                            darkHex: String,
                                            rawBar: Double) -> [PaletteFailure] {
        var out: [PaletteFailure] = []
        let modes: [(String, String, String, Double, Double)] = [
            ("light", lightHex, surfaceLight, strongAA.0, strongAAA.0),
            ("dark",  darkHex,  surfaceDark,  strongAA.1, strongAAA.1),
        ]
        for (mode, seedHex, surfaceHex, lAA, lAAA) in modes {
            let seed = hex(seedHex)
            let surface = hex(surfaceHex)
            let tint = mixOKLab(seed, surface, weightBase: tintWeight)
            // RAW token used directly on the surface (error text / borders / tints).
            let rRaw = wcagContrast(seed, surface)
            if rRaw < rawBar { out.append(.init(token: name, mode: mode, ratio: rRaw, target: rawBar)) }
            // -strong on the tint: 4.5 normal, 7 under prefers-contrast: more.
            let rAA = wcagContrast(oklchFrom(seed, lightness: lAA), tint)
            if rAA < 4.5 { out.append(.init(token: "\(name)-strong", mode: mode, ratio: rAA, target: 4.5)) }
            let rAAA = wcagContrast(oklchFrom(seed, lightness: lAAA), tint)
            if rAAA < 7.0 { out.append(.init(token: "\(name)-strong (more-contrast)", mode: mode, ratio: rAAA, target: 7.0)) }
        }
        return out
    }

    /// Full generator: normalize the seed, derive the dark accent, validate, and return the
    /// override CSS. Optional `dangerHex`/`successHex` add contrast-validated raw status
    /// overrides (their dark arms derived like the accent; the base sheet re-derives `-strong`,
    /// more-contrast, and P3 from the raw token). With `includeNeutrals`, also derives the
    /// accent-tinted neutral ramp + a prefers-contrast: more block. With no status seeds and
    /// `includeNeutrals: false`, the output is byte-for-byte the original accent-only block.
    public static func accentThemeCSS(primaryHex: String,
                                      dangerHex: String? = nil,
                                      successHex: String? = nil,
                                      includeNeutrals: Bool = false) throws -> String {
        let light = try normalizeHex(primaryHex)
        let dark = darkAccent(from: light)
        var failures = validateAccentFamily(lightAccentHex: light, darkAccentHex: dark)

        // Optional status seeds: normalize, dark-derive, validate, emit a raw line. Each appends
        // its flag to the header's command echo so the generated comment is reproducible.
        var statusLines: [String] = []
        var flagEcho = ""
        if let dangerHex {
            let dl = try normalizeHex(dangerHex)
            let dd = darkAccent(from: dl)
            failures += validateStatusFamily(name: "--sw-danger", lightHex: dl, darkHex: dd, rawBar: 4.5)
            statusLines.append("  --sw-danger: light-dark(\(dl), \(dd));")
            flagEcho += " --danger \(dl)"
        }
        if let successHex {
            let sl = try normalizeHex(successHex)
            let sd = darkAccent(from: sl)
            failures += validateStatusFamily(name: "--sw-success", lightHex: sl, darkHex: sd, rawBar: 3.0)
            statusLines.append("  --sw-success: light-dark(\(sl), \(sd));")
            flagEcho += " --success \(sl)"
        }

        if !includeNeutrals {
            guard failures.isEmpty else { throw PaletteError.contrastFailures(failures) }
            let rootBody = (["  --sw-accent: light-dark(\(light), \(dark));"] + statusLines)
                .joined(separator: "\n")
            return """
            /* Generated by `swiflow theme --primary \(light)\(flagEcho)`. Include after SwiflowUI's styles.
               Re-points --sw-accent; hover/active/text/strong derive from it automatically. */
            :root {
            \(rootBody)
            }
            """ + "\n"
        }

        let neutrals = neutralPalette(accentHex: light)
        failures += validateNeutrals(neutrals)
        guard failures.isEmpty else { throw PaletteError.contrastFailures(failures) }

        let rootLines = (["  --sw-accent: light-dark(\(light), \(dark));"]
            + statusLines
            + neutrals.map { "  \($0.name): light-dark(\($0.light), \($0.dark));" })
            .joined(separator: "\n")
        let moreLines = neutralContrastMore(accentHex: light)
            .map { "    \($0.name): light-dark(\($0.light), \($0.dark));" }
            .joined(separator: "\n")
        return """
        /* Generated by `swiflow theme --primary \(light)\(flagEcho) --neutrals`. Include after SwiflowUI's styles.
           Re-points --sw-accent (family cascades) + the accent-tinted neutral ramp. */
        :root {
        \(rootLines)
        }
        @media (prefers-contrast: more) {
          :root {
        \(moreLines)
          }
        }
        """ + "\n"
    }
}

extension Color {
    /// A derived token as `(name, lightHex, darkHex)`. Ordered arrays keep emitted CSS
    /// deterministic (a dict would not).
    public typealias TokenPair = (name: String, light: String, dark: String)

    // Faint accent cast — small enough to read as gray, large enough to survive 8-bit hex.
    private static let neutralTintChroma = 0.01
    // (token, L_light, L_dark) — lightness targets lifted from the shipped defaults; the muted
    // light target (0.46) is conservatively pinned to clear AA with headroom on near-white
    // backgrounds (validateNeutrals is the gate that actually enforces it).
    private static let neutralRamp: [(String, Double, Double)] = [
        ("--sw-bg",         0.97, 0.15),
        ("--sw-surface",    1.00, 0.20),
        ("--sw-surface-2",  0.96, 0.24),
        ("--sw-text",       0.18, 0.96),
        ("--sw-text-muted", 0.46, 0.72),
        ("--sw-border",     0.92, 0.30),
    ]
    // prefers-contrast: more overrides (text/text-muted/border pushed toward the extremes).
    private static let neutralRampMore: [(String, Double, Double)] = [
        ("--sw-text",       0.10, 0.99),
        ("--sw-text-muted", 0.25, 0.90),
        ("--sw-border",     0.10, 0.99),
    ]

    /// OKLCH(L, C, H) → gamut-clamped "#rrggbb".
    private static func oklchHex(_ L: Double, _ C: Double, _ H: Double) -> String {
        hexString(clampGamut(okLabToLinRGB(okLCHToOKLab(OKLCH(L: L, C: C, H: H)))))
    }

    private static func ramp(_ rows: [(String, Double, Double)], accentHex: String) -> [TokenPair] {
        let hue = okLabToOKLCH(linRGBToOKLab(hex(accentHex))).H
        return rows.map { (name, ll, ld) in
            (name: name, light: oklchHex(ll, neutralTintChroma, hue), dark: oklchHex(ld, neutralTintChroma, hue))
        }
    }

    /// The six neutral tokens, tinted to the accent hue, as light/dark hex pairs (ordered).
    public static func neutralPalette(accentHex: String) -> [TokenPair] { ramp(neutralRamp, accentHex: accentHex) }

    /// The text/text-muted/border overrides for `@media (prefers-contrast: more)`.
    public static func neutralContrastMore(accentHex: String) -> [TokenPair] { ramp(neutralRampMore, accentHex: accentHex) }
}

extension Color {
    /// WCAG check on a neutral palette: body and secondary text must clear 4.5 on both the
    /// card surface and the page background, in both schemes. (Border is intentionally not
    /// gated — see the spec.) Returns every shortfall.
    public static func validateNeutrals(_ palette: [TokenPair]) -> [PaletteFailure] {
        func find(_ n: String) -> (light: String, dark: String)? {
            palette.first { $0.name == n }.map { ($0.light, $0.dark) }
        }
        guard let surface = find("--sw-surface"), let bg = find("--sw-bg"),
              let text = find("--sw-text"), let muted = find("--sw-text-muted") else { return [] }
        var out: [PaletteFailure] = []
        let checks: [(String, (light: String, dark: String), (light: String, dark: String))] = [
            ("--sw-text on --sw-surface",       text,  surface),
            ("--sw-text on --sw-bg",            text,  bg),
            ("--sw-text-muted on --sw-surface", muted, surface),
            ("--sw-text-muted on --sw-bg",      muted, bg),
        ]
        for (label, fg, bgc) in checks {
            for (mode, f, b) in [("light", fg.light, bgc.light), ("dark", fg.dark, bgc.dark)] {
                let r = wcagContrast(hex(f), hex(b))
                if r < 4.5 { out.append(.init(token: label, mode: mode, ratio: r, target: 4.5)) }
            }
        }
        return out
    }
}
