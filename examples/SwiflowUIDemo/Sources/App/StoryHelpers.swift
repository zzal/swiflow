// Shared page/variant chrome for story pages: a titled page, and per-variant
// sections showing live output above a collapsible hand-maintained code snippet.
import Swiflow
import SwiflowUI

/// A story page: h1 + optional blurb + content.
@MainActor
func storyPage(_ title: String, blurb: String? = nil,
               @ChildrenBuilder content: () -> [VNode]) -> VNode {
    VStack(spacing: .lg, align: .stretch) {
        h1(title)
        if let blurb { p(blurb) }
        for node in content() { node }
    }
}

/// A variant section: titled live output, with the Swift snippet underneath
/// in a native <details> (collapsed by default).
///
/// Parameter named `snippet` (not `code`): the DSL's `<code>` element factory
/// is literally named `code`, so `code` would collide with the parameter name.
@MainActor
func variantSection(_ title: String, snippet: String? = nil,
                    @ChildrenBuilder content: () -> [VNode]) -> VNode {
    VStack(spacing: .md, align: .stretch) {
        h2(title)
        for node in content() { node }
        if let snippet {
            details(.class("story-code")) {
                summary("Swift")
                pre { code(snippet) }
            }
        }
        Divider()
    }
}
