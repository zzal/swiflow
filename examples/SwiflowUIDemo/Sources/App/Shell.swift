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

    private static let accents: [String: String] = [
        "Crimson": "#dc2626", "Violet": "#7c3aed", "Emerald": "#059669",
    ]

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
                embed { Link("/", "Overview") }
                for category in StoryCategory.allCases
                where !Catalog.entries(in: category).isEmpty {
                    h2(category.rawValue).style("font-size", "0.75rem")
                        .style("text-transform", "uppercase")
                        .style("opacity", "0.6")
                        .style("margin", "var(--sw-space-md) 0 0")
                    for entry in Catalog.entries(in: category) {
                        embed { Link(Catalog.path(entry.slug), entry.title) }
                    }
                }
            }
            .padding(.md)
        }
        .style("flex", "0 0 220px")
        .style("overflow-y", "auto")
        .style("border-right", "\(Token.borderWidth.css) solid \(Token.border.css)")
    }

    private var outlet: VNode {
        embed {
            RouterRoot {
                Route("/") { IndexStory() }
                Route("/component/stacks") { StacksStory() }
                Route("/component/grid") { GridStory() }
                Route("/component/spacer") { SpacerStory() }
                Route("/component/button") { ButtonStory() }
                Route("/component/forms") { FormControlsStory() }
                Route("/component/textarea") { TextAreaStory() }
                Route("/component/numberfield") { NumberFieldStory() }
                Route("/component/slider") { SliderStory() }
                Route("/component/feedback") { FeedbackStory() }
                Route("/component/callout") { CalloutStory() }
                Route("/component/tooltip") { TooltipStory() }
                Route("/component/overlays") { OverlaysStory() }
                Route("/component/modal") { ModalStory() }
                Route("/component/popover") { PopoverStory() }
                Route("/component/textlink") { TextLinkStory() }
                Route("/component/breadcrumbs") { BreadcrumbsStory() }
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
        }
        if radiusChoice != "Default" {
            node = node.style(Token.radius.name, radiusChoice)
        }
        return node
    }

    // Dark-mode must sync at the document root (see Global Constraints).
    func onAppear() { syncColorScheme() }
    func onChange() { syncColorScheme() }

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
