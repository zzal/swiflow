// Root shell: theme-playground header (Task 10 fills it in — starts with just
// the Dark-mode toggle), left vertical navbar, story outlet. The navbar is a
// fixed-width, full-height, vertically-scrollable left column; the outlet
// scrolls independently and fills the remaining width.
import Swiflow
import SwiflowDOM
import SwiflowUI
import SwiflowRouter
#if canImport(JavaScriptKit)
import JavaScriptKit
#endif

@Component
final class Shell {
    @State var isDark: Bool = false
    @State var accentChoice: String = "Default"
    @State var radiusChoice: String = "Default"
    /// The current hash route, mirrored from `location.hash` so the sidebar can
    /// mark the active link. The Shell sits ABOVE `RouterRoot`, so it doesn't
    /// re-render on navigation on its own — a `hashchange` listener drives this.
    @State var currentPath: String = "/"

    private static let accents: [String: String] = [
        "Crimson": "#dc2626", "Violet": "#7c3aed", "Emerald": "#059669",
    ]

    #if canImport(JavaScriptKit)
    private var hashListener: JSClosure? = nil
    #endif

    var body: VNode {
        VStack(spacing: .none, align: .stretch) {
            // --- header -------------------------------------------------
            HStack(align: .center) {
                h1("SwiflowUI Catalog").style("font-size", "1.1rem")
                Spacer()
                Select("Accent", selection: $accentChoice,
                       options: ["Default", "Crimson", "Violet", "Emerald"], size: .sm)
                Select("Radius", selection: $radiusChoice,
                       options: ["Default", "2px", "8px", "16px"], size: .sm)
                Toggle("Dark mode", isOn: $isDark)
            }
            .padding(.md)
            .style("border-bottom", "\(Token.borderWidth.css) solid \(Token.border.css)")

            // --- navbar + outlet -----------------------------------------
            HStack(spacing: .none, align: .stretch) {
                sidebar
                storyOutlet
            }
            .style("flex", "1 1 auto")
            .style("min-height", "0")
        }
        .style("height", "100vh")
        .style("background", "var(--sw-bg)")
        .style("color", "var(--sw-text)")
    }

    private var sidebar: VNode {
        nav(.class("catalog-nav"), .attr("aria-label", "Components")) {
            VStack(spacing: .sm, align: .stretch) {
                navLink("/", "Overview")
                for category in StoryCategory.allCases
                where !Catalog.entries(in: category).isEmpty {
                    h2(category.rawValue).style("font-size", "0.75rem")
                        .style("text-transform", "uppercase")
                        .style("opacity", "0.6")
                        .style("margin", "var(--sw-space-md) 0 0")
                    for entry in Catalog.entries(in: category) {
                        navLink(Catalog.path(entry.slug), entry.title)
                    }
                }
            }
            .padding(.md)
        }
        .style("flex", "0 0 220px")
        .style("overflow-y", "auto")
        .style("border-right", "\(Token.borderWidth.css) solid \(Token.border.css)")
    }

    /// A sidebar nav link. A PLAIN hash anchor, deliberately NOT `SwiflowRouter.Link`:
    /// the sidebar sits outside `RouterRoot` (a sibling of the outlet), so a Router
    /// `Link` here would capture the no-op default router — its click handler would
    /// `preventDefault()` the native hash navigation and then no-op, giving dead links.
    /// A plain `#/…` anchor navigates natively; `RouterRoot`'s own `hashchange` listener
    /// picks it up. Active state is marked from `currentPath` (mirrored via the listener).
    private func navLink(_ path: String, _ label: String) -> VNode {
        let active = currentPath == path
        var attrs: [Attribute] = [
            .href("#" + path),
            .style("display", "block"),
            .style("padding", "var(--sw-space-xs) var(--sw-space-sm)"),
            .style("border-radius", "var(--sw-radius-sm)"),
            .style("text-decoration", "none"),
            .style("font-size", "0.875rem"),
            .style("color", active ? "var(--sw-accent-strong)" : "var(--sw-text)"),
            .style("background", active
                ? "color-mix(in oklab, var(--sw-accent) 12%, transparent)" : "transparent"),
            .style("font-weight", active ? "600" : "400"),
        ]
        if active { attrs.append(.attr("aria-current", "page")) }
        return element("a", attributes: attrs, children: [text(label)])
    }

    private var outlet: VNode {
        embed {
            RouterRoot {
                Route("/") { IndexStory() }
                Route("/component/stacks") { StacksStory() }
                Route("/component/grid") { GridStory() }
                Route("/component/spacer") { SpacerStory() }
                Route("/component/container") { ContainerStory() }
                Route("/component/accordion") { AccordionStory() }
                Route("/component/text") { TextStory() }
                Route("/component/button") { ButtonStory() }
                Route("/component/textfield") { TextFieldStory() }
                Route("/component/select") { SelectStory() }
                Route("/component/autocomplete") { AutocompleteStory() }
                Route("/component/checkbox") { CheckboxStory() }
                Route("/component/radiogroup") { RadioGroupStory() }
                Route("/component/toggle") { ToggleStory() }
                Route("/component/toggle-button-group") { ToggleButtonGroupStory() }
                Route("/component/textarea") { TextAreaStory() }
                Route("/component/numberfield") { NumberFieldStory() }
                Route("/component/slider") { SliderStory() }
                Route("/component/labeledfield") { LabeledFieldStory() }
                Route("/component/feedback") { FeedbackStory() }
                Route("/component/skeleton") { SkeletonStory() }
                Route("/component/avatar") { AvatarStory() }
                Route("/component/icon") { IconStory() }
                Route("/component/callout") { CalloutStory() }
                Route("/component/tooltip") { TooltipStory() }
                Route("/component/overlays") { OverlaysStory() }
                Route("/component/modal") { ModalStory() }
                Route("/component/popover") { PopoverStory() }
                Route("/component/textlink") { TextLinkStory() }
                Route("/component/breadcrumbs") { BreadcrumbsStory() }
                Route("/component/tabs") { TabsStory() }
                Route("/component/pagination") { PaginationStory() }
                Route("/component/datatable") { DataTableStory() }
                Route("/component/datatable-virtual") { DataTableVirtualStory() }
                Route("/component/theming") { ThemingStory() }
                Route("/component/reducer-wizard") { ReducerWizardStory() }
                // One Route per story:
            } notFound: { ctx in
                NotFoundStory(path: ctx.path)
            }
        }
    }

    /// The always-present outlet wrapper. Playground overrides ride as inline
    /// `--sw-*` custom properties on THIS div rather than a conditionally
    /// present `Theme(...)` wrapper: the old approach changed the VNode tree
    /// shape (outlet vs. Theme-wrapped outlet) whenever an override toggled,
    /// which remounted the RouterRoot subtree underneath and reset story
    /// `@State`. Keeping the div itself constant and only diffing its style
    /// dict is safe — `diffStyle` (Sources/Swiflow/Diff/Diff.swift) emits a
    /// `removeStyle` patch for any key present in the old render but absent
    /// from the new one, and the js-driver applies it via
    /// `style.removeProperty` (swiflow-driver.js, `removeStyle` case), which
    /// correctly clears `--sw-*` custom properties. So simply omitting the
    /// key when the choice is "Default" reverts it cleanly — no need for an
    /// explicit revert value.
    private var storyOutlet: VNode {
        var node = div(.class("story-outlet")) { outlet }
            .padding(.xl)
            .style("flex", "1 1 auto")
            .style("min-width", "0")
            .style("overflow-y", "auto")
        if let accent = Shell.accents[accentChoice] {
            node = node.style(Token.accent.name, accent)
            // Re-derive the accent family (focus ring, focused borders, hover/active)
            // from the overridden accent. Those tokens are declared at :root, so a
            // scoped --sw-accent override doesn't re-resolve them without this — same
            // set Theme(.accent:) applies. (Inline here, not a Theme wrapper, to keep
            // the stable-div structure that avoids remounting the routed subtree.)
            for d in swAccentFamilyDerivations { node = node.style(d.name, d.value) }
        }
        if radiusChoice != "Default" {
            node = node.style(Token.radius.name, radiusChoice)
        }
        return node
    }

    // Dark-mode must sync at the document root (see Global Constraints).
    func onAppear() {
        syncColorScheme()
        syncCurrentPath()
        startHashListener()
    }
    func onChange() { syncColorScheme() }
    func onDisappear() { stopHashListener() }

    /// Read `location.hash` (`"#/component/x"`) into `currentPath` (`"/component/x"`);
    /// empty hash → `"/"`. Idempotent read-diff-write, so it's cheap to call often.
    private func syncCurrentPath() {
        #if canImport(JavaScriptKit)
        // Subscript access (not `.location`/`.hash` dot-members, which collide with
        // Swift's own `hash`), mirroring SwiflowRouter's BrowserNavigator.
        guard let window = JSObject.global.window.object,
              let location = window["location"].object else { return }
        let raw = location["hash"].string ?? ""
        let stripped = raw.hasPrefix("#") ? String(raw.dropFirst()) : raw
        let next = stripped.isEmpty ? "/" : stripped
        if currentPath != next { currentPath = next }
        #endif
    }

    /// Mirror hash navigations into `currentPath` so the active nav link updates.
    /// The Shell is above `RouterRoot`, so it doesn't re-render on route change by
    /// itself — this window listener (the same mechanism `RouterRoot` uses) drives it.
    private func startHashListener() {
        #if canImport(JavaScriptKit)
        guard hashListener == nil, let window = JSObject.global.window.object else { return }
        let closure = JSClosure { [weak self] _ in
            MainActor.assumeIsolated { self?.syncCurrentPath() }
            return .undefined
        }
        _ = window.addEventListener!("hashchange", closure)
        hashListener = closure
        #endif
    }

    private func stopHashListener() {
        #if canImport(JavaScriptKit)
        if let window = JSObject.global.window.object, let closure = hashListener {
            _ = window.removeEventListener!("hashchange", closure)
        }
        hashListener = nil
        #endif
    }

    private func syncColorScheme() {
        #if canImport(JavaScriptKit)
        guard let html = JSObject.global.document.object?.documentElement.object,
              let style = html.style.object else { return }
        let want = isDark ? "dark" : "light"
        if style.colorScheme.string != want { style.colorScheme = .string(want) }
        #endif
    }
}

@Component
final class NotFoundStory {
    var path: String

    init(path: String) {
        self.path = path
    }

    var body: VNode {
        storyPage("Not found", blurb: "No story at \(path).") {
            embed { Link("/", "Back to overview") }
        }
    }
}
