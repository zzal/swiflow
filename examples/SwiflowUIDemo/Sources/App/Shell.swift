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

    var body: VNode {
        VStack(spacing: .none, align: .stretch) {
            // --- header -------------------------------------------------
            HStack(align: .center) {
                h1("SwiflowUI Catalog").style("font-size", "1.1rem")
                Spacer()
                Toggle("Dark mode", isOn: $isDark)
            }
            .padding(.md)
            .style("border-bottom", "\(Token.borderWidth.css) solid \(Token.border.css)")

            // --- navbar + outlet -----------------------------------------
            HStack(spacing: .none, align: .stretch) {
                sidebar
                div(.class("story-outlet")) { outlet }
                    .padding(.xl)
                    .style("flex", "1 1 auto")
                    .style("min-width", "0")
                    .style("overflow-y", "auto")
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
                Route("/component/feedback") { FeedbackStory() }
                Route("/component/tooltip") { TooltipStory() }
                Route("/component/theming") { ThemingStory() }
                // One Route per story, added as each migrates (Tasks 4–9):
            } notFound: { ctx in
                NotFoundStory(path: ctx.path)
            }
        }
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
