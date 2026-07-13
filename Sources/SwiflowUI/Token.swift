// Sources/SwiflowUI/Token.swift
import Swiflow

/// A typed reference to a `--sw-*` design token (audit V Wave-2 #5). `.css`
/// renders the `var()` reference for style values, and `Theme` overrides
/// route through the same constants (`ThemeToken`), so the read and write
/// vocabularies cannot drift — a stringly `var(--sw-surfce)` typo fails
/// SILENT in CSS; `Token.surface` fails at compile time.
///
///     div(.style("background", .surface), .style("border-radius", .radius))
///     Theme(.set(.warning, "#b45309")) { … }
///
/// The vocabulary mirrors everything `baseStyleSheet`'s `:root` sets; the
/// TokenTests anti-drift sweep is the authority (a Token static naming a
/// token the sheet doesn't set fails CI). App-custom properties stay on the
/// stringly doors (`.style(_:_: String)` / `ThemeToken.token(_:_:)`).
public struct Token: Sendable, Equatable {
    public let name: String
    public var css: String { "var(\(name))" }

    init(_ name: String) { self.name = name }

    // Surfaces & text
    public static let bg = Token("--sw-bg")
    public static let surface = Token("--sw-surface")
    public static let surface2 = Token("--sw-surface-2")
    public static let text = Token("--sw-text")
    public static let textMuted = Token("--sw-text-muted")

    // Accent family
    public static let accent = Token("--sw-accent")
    public static let accentHover = Token("--sw-accent-hover")
    public static let accentActive = Token("--sw-accent-active")
    public static let accentText = Token("--sw-accent-text")
    public static let accentStrong = Token("--sw-accent-strong")

    // Danger family
    public static let danger = Token("--sw-danger")
    public static let dangerHover = Token("--sw-danger-hover")
    public static let dangerActive = Token("--sw-danger-active")
    public static let dangerText = Token("--sw-danger-text")
    public static let dangerStrong = Token("--sw-danger-strong")

    // Semantic status
    public static let success = Token("--sw-success")
    public static let successStrong = Token("--sw-success-strong")
    public static let warning = Token("--sw-warning")
    public static let warningStrong = Token("--sw-warning-strong")
    public static let info = Token("--sw-info")
    public static let infoStrong = Token("--sw-info-strong")

    // Chrome
    public static let border = Token("--sw-border")
    public static let borderWidth = Token("--sw-border-width")
    public static let focusRing = Token("--sw-focus-ring")
    public static let focusRingWidth = Token("--sw-focus-ring-width")
    public static let radiusSm = Token("--sw-radius-sm")
    public static let radius = Token("--sw-radius")
    public static let shadow = Token("--sw-shadow")
    public static let overlayBg = Token("--sw-overlay-bg")
    public static let backdrop = Token("--sw-backdrop")
    public static let disabledOpacity = Token("--sw-disabled-opacity")

    // Spacing scale
    public static let spaceXs = Token("--sw-space-xs")
    public static let spaceSm = Token("--sw-space-sm")
    public static let spaceMd = Token("--sw-space-md")
    public static let spaceLg = Token("--sw-space-lg")
    public static let spaceXl = Token("--sw-space-xl")

    // Motion
    public static let duration = Token("--sw-duration")
    public static let ease = Token("--sw-ease")
    public static let animPlay = Token("--sw-anim-play")

    // Typography
    public static let fontSizeXs = Token("--sw-font-size-xs")
    public static let fontSizeSm = Token("--sw-font-size-sm")
    public static let fontSizeMd = Token("--sw-font-size-md")
    public static let fontSizeLg = Token("--sw-font-size-lg")
    public static let fontSizeXl = Token("--sw-font-size-xl")
    public static let fontSize2xl = Token("--sw-font-size-2xl")
    public static let fontWeightRegular = Token("--sw-font-weight-regular")
    public static let fontWeightMedium = Token("--sw-font-weight-medium")
    public static let fontWeightSemibold = Token("--sw-font-weight-semibold")
    public static let lineHeight = Token("--sw-line-height")
    public static let lineHeightTight = Token("--sw-line-height-tight")

    // Structure
    public static let containerSm = Token("--sw-container-sm")
    public static let containerMd = Token("--sw-container-md")
    public static let containerLg = Token("--sw-container-lg")
    public static let containerXl = Token("--sw-container-xl")

    /// The whole vocabulary — powers the TokenTests anti-drift sweep.
    static let all: [Token] = [
        .bg, .surface, .surface2, .text, .textMuted,
        .accent, .accentHover, .accentActive, .accentText, .accentStrong,
        .danger, .dangerHover, .dangerActive, .dangerText, .dangerStrong,
        .success, .successStrong, .warning, .warningStrong, .info, .infoStrong,
        .border, .borderWidth, .focusRing, .focusRingWidth,
        .radiusSm, .radius, .shadow, .overlayBg, .backdrop, .disabledOpacity,
        .spaceXs, .spaceSm, .spaceMd, .spaceLg, .spaceXl,
        .duration, .ease, .animPlay,
        .fontSizeXs, .fontSizeSm, .fontSizeMd, .fontSizeLg, .fontSizeXl, .fontSize2xl,
        .fontWeightRegular, .fontWeightMedium, .fontWeightSemibold,
        .lineHeight, .lineHeightTight,
        .containerSm, .containerMd, .containerLg, .containerXl,
    ]
}

public extension Attribute {
    /// `.style("background", .surface)` — the token half of a style
    /// declaration, typed. (The CSS property stays a string: properties are
    /// an open set; the TOKEN was the silent-typo hazard.)
    static func style(_ property: String, _ token: Token) -> Attribute {
        .style(property, token.css)
    }
}

public extension VNode {
    /// The modifier twin of the typed `Attribute.style` overload:
    /// `div { … }.style("background", .surface)`.
    func style(_ property: String, _ token: Token) -> VNode {
        style(property, token.css)
    }
}

#if DEBUG
/// Installs the `.style` value validator (audit V Wave-3): every stringly
/// style VALUE is scanned for `var(--sw-…)` references; a name outside the
/// typed vocabulary warns — the silent-typo half the typed overloads can't
/// reach (composite values, existing string spellings). App-custom props
/// (non-`--sw-` names) are never checked. Called from `ensureBaseStyles()`,
/// so any SwiflowUI usage arms it; idempotent.
@MainActor
func installStyleTokenValidator() {
    guard _swiflowStyleValueValidator == nil else { return }
    let known = Set(Token.all.map(\.name))
    _swiflowStyleValueValidator = { value in
        guard value.contains("var(--sw-") else { return }
        // Extract each var(--sw-…) reference: after "var(", up to ')' , ',' or whitespace.
        var rest = Substring(value)
        while let open = rest.firstRange(of: "var(--sw-") {   // stdlib (SE-0343), Foundation-free
            let nameStart = rest.index(open.lowerBound, offsetBy: 4)   // skip "var("
            let tail = rest[nameStart...]
            let nameEnd = tail.firstIndex(where: { $0 == ")" || $0 == "," || $0 == " " }) ?? tail.endIndex
            let name = String(tail[..<nameEnd])
            if !known.contains(name) {
                swiflowWarn(
                    "Unknown design token '\(name)' in a .style value — a typo'd var() "
                        + "fails silently in CSS. Use the typed Token spelling "
                        + "(.style(_:, .surface)) or check the name against the --sw- vocabulary."
                )
            }
            rest = tail[nameEnd...]
        }
    }
}
#endif
