// The explicit story registry — drives the navbar and the landing index.
// No reflection on wasm: adding a story = 1 file + 1 entry here + 1 Route in Shell.
import Swiflow

enum StoryCategory: String, CaseIterable {
    case layout = "Layout"
    case controls = "Controls"
    case feedback = "Feedback"
    case overlays = "Overlays"
    case data = "Data"
    case theming = "Theming"
    case patterns = "Patterns"
}

struct StoryEntry {
    let slug: String
    let title: String
    let category: StoryCategory
}

enum Catalog {
    static func path(_ slug: String) -> String { "/component/\(slug)" }

    /// Sidebar/index order is array order within each category.
    static let stories: [StoryEntry] = [
        StoryEntry(slug: "stacks", title: "Stacks", category: .layout),
        StoryEntry(slug: "grid", title: "Grid", category: .layout),
        StoryEntry(slug: "spacer", title: "Spacer", category: .layout),
        StoryEntry(slug: "button", title: "Button", category: .controls),
        StoryEntry(slug: "forms", title: "Form controls", category: .controls),
        StoryEntry(slug: "feedback", title: "Feedback & display", category: .feedback),
        StoryEntry(slug: "tooltip", title: "Tooltip", category: .feedback),
        StoryEntry(slug: "theming", title: "Scoped theming", category: .theming),
    ]

    static func entries(in category: StoryCategory) -> [StoryEntry] {
        stories.filter { $0.category == category }
    }
}
