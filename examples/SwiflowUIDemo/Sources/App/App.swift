import Swiflow
import SwiflowDOM
import SwiflowUI
#if canImport(JavaScriptKit)
import JavaScriptKit
#endif

@Component
final class Demo {
    @State var isDark: Bool = false
    // Kept here (not moved with the rest of the Overlays state to OverlaysStory) because
    // dataTableSection below still fires toasts; it gets its own queue when the DataTable
    // sections move out to their own stories (Task 8), and this class is retired in Task 9.
    @ReducerState var toasts: ToastQueue
    @State var selectedPeople: Set<Int> = []
    @State var peoplePage: Int = 0
    @State var roleFilter: String = "All"

    var body: VNode {
        VStack(spacing: .lg, align: .stretch) {
            // A Toggle wired to `color-scheme` (synced to <html> in onChange) re-themes the
            // whole demo: every --sw-* token is light-dark(), so flipping the scheme flips them all.
            HStack(align: .center) {
                h1("SwiflowUI — primitives, controls & feedback")
                Spacer()
                Toggle("Dark mode", isOn: $isDark)
            }

            Divider()

            // --- Reducer wizard ------------------------------------------
            reducerWizardSection

            Divider()

            // --- DataTable -----------------------------------------------
            dataTableSection
            virtualTableSection
        }
        .padding(.xl)
        .style("background", "var(--sw-bg)")   // page/canvas, so the surface cards lift off it
        .style("color", "var(--sw-text)")
        .style("min-height", "100vh")
    }

    // The "Dark mode" Toggle re-themes the demo by forcing `color-scheme` on the *document
    // root* (`<html>`). It must be `:root`, not a mounted element: the `--sw-*` color tokens are
    // registered via `@property { syntax: "<color>" }`, so their `light-dark()` resolves at the
    // element where they're declared (`:root`) — forcing `color-scheme` on an inner div has no
    // effect on them. Synced imperatively (idempotent read-diff-write) because the app tree can't
    // style `<html>`. JS-interop is `#if`-gated so the demo still builds on host.
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

    /// The DataTable showcase. Extracted from `body` to keep that single result-builder
    /// expression within the Swift type-checker's budget. Demonstrates the dynamic-data
    /// `key:` contract: the role filter changes `rows`, and the `key:` (encoding the filter)
    /// remounts the reused table so it re-reads fresh rows.
    var dataTableSection: VNode {
        let shown = roleFilter == "All"
            ? Demo.samplePeople
            : Demo.samplePeople.filter { $0.role == roleFilter }
        let note = "DataTable with sortable: true, pageSize: 5, and multi-select checkboxes. "
            + "Click a header to cycle ascending → descending → unsorted. The header stays "
            + "pinned inside the 360 px scroll container (maxHeight). The role filter changes "
            + "rows, so a key: encoding the filter remounts the table with fresh data — embedded "
            + "components freeze rows at first mount. Clicking a row \"opens\" it (onRowClick), "
            + "while the row checkbox and the in-cell \"Edit\" button do NOT trigger the row "
            + "click — container clicks ignore interactive descendants (fromInteractiveDescendant)."
        return VStack(spacing: .md, align: .stretch) {
            h2("DataTable")
            Select("Filter by role", selection: $roleFilter,
                   options: ["All", "Engineer", "Researcher", "Inventor", "Designer"])
            // A keyed component can't share a parent with unkeyed siblings (Swiflow's
            // all-or-none keyed-children rule), so the keyed table lives in its own
            // single-child container rather than directly beside the h2/Select/p.
            VStack(spacing: .none, align: .stretch) {
                DataTable(shown,
                          selection: $selectedPeople,
                          sortable: true,
                          pageSize: 5,
                          page: $peoplePage,
                          onRowClick: { p in
                              self.$toasts.show("Opening \(p.name)", .success)
                          },
                          maxHeight: "360px",
                          key: "people-\(roleFilter)-\(shown.count)") {
                    Column("Name", value: \.name)
                    Column("Age", value: \.age).align(.trailing)
                    Column("Role") { p in Badge(p.role, variant: .accent) }
                    Column("") { p in
                        Button("Edit", variant: .secondary, size: .sm) {
                            self.$toasts.show("Editing \(p.name)", .info)
                        }
                    }
                }
            }
            p(note)
        }
    }

    /// A 2,000-row virtualized DataTable. `virtualized: .fixed(rowHeight:)` keeps only the
    /// visible window in the DOM; `columnsTemplate` gives the grid its (shared, stable) column
    /// tracks; `maxHeight` is the required scroll container. Static dataset ⇒ no `key:` needed.
    var virtualTableSection: VNode {
        let note = "Virtualized DataTable over 2,000 rows: only the rows in (and just around) "
            + "the 440 px viewport are in the DOM. Scroll to stream rows; sorting reorders the "
            + "whole dataset. Columns come from columnsTemplate (per-column .width is ignored "
            + "when virtualized)."
        return VStack(spacing: .md, align: .stretch) {
            h2("DataTable — virtualized")
            VStack(spacing: .none, align: .stretch) {
                DataTable(Demo.bigPeople,
                          sortable: true,
                          maxHeight: "440px",
                          virtualization: .fixed(rowHeight: 44),
                          columnsTemplate: "2fr 80px 1fr") {
                    Column("Name", value: \.name)
                    Column("Age", value: \.age).align(.trailing)
                    Column("Role") { p in Badge(p.role, variant: .accent) }
                }
            }
            p(note)
        }
    }

    static let samplePeople: [DemoPerson] = [
        DemoPerson(id: 1,  name: "Ada Lovelace",      age: 36, role: "Engineer"),
        DemoPerson(id: 2,  name: "Grace Hopper",       age: 85, role: "Admiral"),
        DemoPerson(id: 3,  name: "Alan Turing",        age: 41, role: "Researcher"),
        DemoPerson(id: 4,  name: "Margaret Hamilton",  age: 87, role: "Engineer"),
        DemoPerson(id: 5,  name: "Linus Torvalds",     age: 55, role: "Maintainer"),
        DemoPerson(id: 6,  name: "Vint Cerf",          age: 81, role: "Architect"),
        DemoPerson(id: 7,  name: "Tim Berners-Lee",    age: 70, role: "Inventor"),
        DemoPerson(id: 8,  name: "Guido van Rossum",   age: 69, role: "Designer"),
        DemoPerson(id: 9,  name: "Brendan Eich",       age: 63, role: "Engineer"),
        DemoPerson(id: 10, name: "Barbara Liskov",     age: 83, role: "Researcher"),
        DemoPerson(id: 11, name: "Katherine Johnson",  age: 101, role: "Mathematician"),
        DemoPerson(id: 12, name: "Dennis Ritchie",     age: 70, role: "Inventor"),
        DemoPerson(id: 13, name: "Ken Thompson",       age: 82, role: "Inventor"),
        DemoPerson(id: 14, name: "Bjarne Stroustrup",  age: 74, role: "Designer"),
    ]

    static let bigPeople: [DemoPerson] = (0..<2000).map { i in
        DemoPerson(id: 1000 + i, name: "Person \(i)", age: 18 + (i % 70),
                   role: ["Engineer", "Researcher", "Inventor", "Designer"][i % 4])
    }

    /// A two-step wizard backed by `@ReducerState`. Demonstrates sync dispatch
    /// and a fire-and-forget async effect at the call site (no `async` on the handler).
    var reducerWizardSection: VNode {
        VStack(spacing: .md, align: .stretch) {
            h2("Reducer wizard")
            p("A @ReducerState-backed two-step wizard. \"Next\" and \"Back\" are sync dispatches; "
              + "\"Submit\" fires an async effect (300 ms simulated round-trip) then dispatches "
              + "a second action when it completes. The reducer is pure; all async lives at the call site.")
            embed { SignupWizardView() }
        }
    }

}

struct DemoPerson: Identifiable {
    let id: Int
    let name: String
    let age: Int
    let role: String
}

// MARK: - Reducer wizard demo

struct SignupWizard: Reducer {
    struct State { var step = 0; var submitting = false; var done = false }
    enum Action { case next, back, submitStarted, submitFinished }
    var initialState: State { .init() }
    func reduce(into s: inout State, _ a: Action) {
        switch a {
        case .next where s.step < 1: s.step += 1
        case .back where s.step > 0: s.step -= 1
        case .submitStarted: s.submitting = true
        case .submitFinished: s.submitting = false; s.done = true
        default: break
        }
    }
}

@Component
final class SignupWizardView {
    @ReducerState var wiz: SignupWizard
    var body: VNode {
        let s = $wiz.state
        return VStack(spacing: .md, align: .stretch) {
            if s.done {
                p("Done ✓")
            } else {
                p("Step \(s.step + 1) of 2")
                HStack(spacing: .sm, align: .center) {
                    Button("Back", variant: .secondary, disabled: s.step == 0) { self.$wiz.send(.back) }
                    if s.step < 1 {
                        Button("Next") { self.$wiz.send(.next) }
                    } else {
                        Button("Submit", disabled: s.submitting) {
                            self.$wiz.send(.submitStarted)
                            Task { @MainActor in
                                try? await Task.sleep(for: .milliseconds(300))
                                self.$wiz.send(.submitFinished)
                            }
                        }
                    }
                }
            }
        }
        .padding(.md)
        .style("background", Token.surface)
        .style("border-radius", Token.radius)
    }
}

@main
struct App {
    @MainActor static func main() { Swiflow.render(into: "#app") { Shell() } }
}
