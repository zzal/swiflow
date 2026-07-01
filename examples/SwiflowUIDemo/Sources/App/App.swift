import Swiflow
import SwiflowDOM
import SwiflowUI
#if canImport(JavaScriptKit)
import JavaScriptKit
#endif

@Component
final class Demo {
    @State var name: String = ""
    @State var email: String = ""
    @State var subscribed: Bool = false
    @State var color: String = ""
    @State var plan: String = "Free"
    @State var isDark: Bool = false
    @State var accepted: Bool = false
    @State var ctrl: FormController = FormController()
    @State var confirmDelete: Bool = false
    @State var deleteResult: String = ""
    @State var showRename: Bool = false
    @State var fileName: String = "untitled"
    @ReducerState var toasts: ToastQueue
    @State var element: String = ""
    @State var asyncElement: String = ""
    @State var selectedPeople: Set<Int> = []
    @State var peoplePage: Int = 0
    @State var roleFilter: String = "All"

    /// Shared by the sync Autocomplete (static options) and the async one (a loader that
    /// filters the same list behind a simulated network delay).
    static let periodicElements: [String] = [
        "Hydrogen", "Helium", "Lithium", "Beryllium", "Boron", "Carbon", "Nitrogen", "Oxygen",
        "Fluorine", "Neon", "Sodium", "Magnesium", "Aluminium", "Silicon", "Phosphorus", "Sulfur",
        "Chlorine", "Argon", "Potassium", "Calcium", "Titanium", "Chromium", "Iron", "Cobalt",
        "Nickel", "Copper", "Zinc", "Silver", "Tin", "Iodine", "Gold", "Mercury", "Lead",
        "Radon", "Uranium", "Plutonium",
    ]

    var body: VNode {
        let emailField = Field("email", $email, $ctrl, .required(), .email)
        let termsField = Field("terms", $accepted, $ctrl, .custom("You must accept the terms") { $0 })

        return VStack(spacing: .lg, align: .stretch) {
            // A Toggle wired to `color-scheme` (synced to <html> in onChange) re-themes the
            // whole demo: every --sw-* token is light-dark(), so flipping the scheme flips them all.
            HStack(align: .center) {
                h1("SwiflowUI — primitives, controls & feedback")
                Spacer()
                Toggle("Dark mode", isOn: $isDark)
            }

            // --- Stacks --------------------------------------------------
            h2("Stacks")
            HStack(spacing: .md, align: .center) {
                Button("One") {}; Button("Two") {}; Button("Three") {}
            }
            .padding(.md)
            .style("background", "var(--sw-surface)")
            .style("border-radius", "var(--sw-radius)")

            p("The row above uses HStack(spacing: .md). Change --sw-space-md "
              + "in index.html's <style> to reskin every gap at once.")

            Divider()

            // --- Grid ----------------------------------------------------
            h2("Grid")
            Grid(columns: 3, spacing: .md) {
                for n in 1...6 { card("Cell \(n)") }
            }
            p("Grid(columns: 3, spacing: .md) — equal columns via "
              + "repeat(3, minmax(0, 1fr)).")

            Divider()

            // --- Spacer --------------------------------------------------
            h2("Spacer")
            HStack(align: .center) {
                Button("Leading", variant: .secondary) {}
                Spacer()
                Button("Trailing", variant: .secondary) {}
            }
            .padding(.md)
            .style("background", "var(--sw-surface)")
            .style("border-radius", "var(--sw-radius)")
            p("A Spacer() between the buttons pushes them to opposite ends.")

            Divider()

            // --- Buttons -------------------------------------------------
            h2("Buttons")
            HStack(spacing: .md, align: .center) {
                Button("Primary") {}
                Button("Secondary", variant: .secondary) {}
                Button("Ghost", variant: .ghost) {}
                Button("Disabled", disabled: true) {}
            }
            HStack(spacing: .md, align: .center) {
                Button("Small", size: .sm) {}
                Button("Medium", size: .md) {}
                Button("Large", size: .lg) {}
            }
            p("Variants and sizes are skinned entirely by --sw-* tokens. Toggle your "
              + "system dark mode / increased contrast / reduced motion to see the "
              + "@media token layers re-skin them with no code change.")

            Divider()

            // --- Tooltip -------------------------------------------------
            h2("Tooltip")
            HStack(spacing: .md, align: .center) {
                Tooltip("Saved to your library") { Button("Hover or focus me", variant: .secondary) {} }
                Tooltip("Appears below the trigger", placement: .bottom) { Button("Below") {} }
            }
            p("Tooltip wraps any trigger — hover or focus to reveal. Placement defaults to .top; "
              + "pass placement: .bottom (or .leading / .trailing) to anchor it on another side. "
              + "Pure CSS — no JS, no z-index juggling.")

            Divider()

            // --- Scoped theming ------------------------------------------
            h2("Scoped theming")
            HStack(spacing: .md, align: .center) {
                Button("Default accent") {}
                Theme(.accent("#dc2626"), .radius("2px")) {
                    HStack(spacing: .md, align: .center) {
                        Button("Branded primary") {}
                        Button("Branded ghost", variant: .ghost) {}
                        Badge("Tagged", variant: .accent)
                    }
                }
            }
            p("The right-hand group is wrapped in Theme(.accent(\"#dc2626\"), .radius(\"2px\")). "
              + "One override re-points --sw-accent; the whole family (fill, ghost text, badge "
              + "tint, focus ring) and the radius follow — scoped to that subtree only. The "
              + "wrapper uses display:contents, so it sits inline in the row with no layout shift.")

            Divider()

            // --- Form controls -------------------------------------------
            h2("Form controls")
            VStack(spacing: .md, align: .stretch) {
                TextField("Name", text: $name, placeholder: "Ada Lovelace")
                TextField("Email", field: emailField, type: .email, placeholder: "you@example.com")
                Select("Favorite color", selection: $color, options: ["Red", "Green", "Blue"], placeholder: "Choose…")
                // A non-address domain on purpose: Chrome forces address autofill onto
                // anything it reads as a "Country" field (ignoring autocomplete="off"),
                // and that overlay covers the custom listbox.
                Autocomplete("Element", selection: $element,
                             options: Demo.periodicElements.map { SelectOption($0) },
                             placeholder: "Type to search…")
                // Async/remote variant: the loader filters behind a simulated 350ms delay,
                // so you see the Searching… state, then results. Debounced (rapid typing
                // fires one request) and cancellation-safe via .task(rerunOn:).
                Autocomplete("Element (async)", selection: $asyncElement, loader: { query in
                    try await Task.sleep(nanoseconds: 350_000_000)
                    return Demo.periodicElements
                        .filter { $0.lowercased().contains(query.lowercased()) }
                        .map { SelectOption($0) }
                }, placeholder: "Search the periodic table…")
                RadioGroup("Plan", selection: $plan, options: ["Free", "Pro", "Team"])
                Toggle("Subscribe to updates", isOn: $subscribed)   // switch: an immediate on/off setting
                Checkbox("I accept the terms", field: termsField)   // checkbox: confirmation, submitted with a form
            }
            if !name.isEmpty { p("Hello, \(name)!\(subscribed ? " (subscribed)" : "")") }
            p("Toggle is a switch (an immediate setting — like Dark mode, top-right); Checkbox is for "
              + "confirmation. The email + terms fields use Field(...) + validators — interact then blur "
              + "to see the role=alert error and aria-invalid.")

            Divider()

            // --- Feedback & display --------------------------------------
            h2("Feedback & display")
            Grid(columns: 2, spacing: .md) {
                Card {
                    h3("Elevated Card")
                    p("A surfaced container with a token shadow.")
                    HStack(spacing: .sm, align: .center) {
                        Spinner()
                        Badge("New", variant: .accent)
                        Badge("3")
                    }
                }
                Card(variant: .outlined) {
                    h3("Outlined Card")
                    p("Bordered instead of shadowed.")
                    HStack(spacing: .sm, align: .center) {
                        Badge("Error", variant: .danger)
                        Badge("Done", variant: .success)
                        Badge("Warn", variant: .warning)
                        Badge("Info", variant: .info)
                        Badge("Muted")
                    }
                }
            }
            ProgressView(value: 0.6)
            p("The Spinner pauses under prefers-reduced-motion (via --sw-anim-play); "
              + "cards/badges/progress re-skin with the theme — flip Dark mode to see it.")

            Divider()

            // --- Overlays ------------------------------------------------
            h2("Overlays")
            HStack(spacing: .md, align: .center) {
                Button("Delete item…", variant: .secondary) { self.confirmDelete = true }
                Button("Rename \(fileName)…", variant: .secondary) { self.showRename = true }
                if !deleteResult.isEmpty { Badge(deleteResult, variant: .success) }
            }
            HStack(spacing: .md, align: .center) {
                Button("Toast: success", variant: .ghost) { self.$toasts.send(.show(ToastItem("Saved successfully", variant: .success))) }
                Button("Toast: info", variant: .ghost) { self.$toasts.send(.show(ToastItem("Heads up — sync running"))) }
                Button("Toast: warning", variant: .ghost) { self.$toasts.send(.show(ToastItem("Low disk space", variant: .warning))) }
                Button("Toast: error", variant: .ghost) { self.$toasts.send(.show(ToastItem("Couldn't reach the server", variant: .danger))) }
                Button("Clear all", variant: .ghost) { self.$toasts.send(.dismissAll) }
            }
            HStack(spacing: .md, align: .center) {
                // Dropdown: a Popover-API menu anchored to its trigger; items close it on
                // select (popovertargetaction=hide) and fire a toast here.
                Dropdown("Actions") {
                    DropdownItem("Edit") { self.$toasts.send(.show(ToastItem("Edit selected"))) }
                    DropdownItem("Duplicate") { self.$toasts.send(.show(ToastItem("Duplicated", variant: .success))) }
                    DropdownItem("Archive", disabled: true) {}
                    DropdownDivider()
                    DropdownItem("Delete", variant: .danger) { self.$toasts.send(.show(ToastItem("Deleted", variant: .danger))) }
                }
            }
            p("Alert and Prompt are native <dialog>.showModal() modals — top layer, backdrop, "
              + "focus trap and ESC-to-close all native, sharing one .sw-dialog chrome. Prompt "
              + "wraps a <form method=\"dialog\">, so Enter submits. The Delete alert demands a "
              + "deliberate choice (no backdrop dismiss); Rename opts into dismissOnBackdrop, so "
              + "clicking outside cancels it. Backdrop solidifies under prefers-reduced-transparency "
              + "and the open animation collapses under prefers-reduced-motion, both via tokens.")
            // A destructive confirm: backdrop dismiss left OFF (the default) so it's not
            // closed by accident.
            Alert("Delete this item?", isPresented: $confirmDelete,
                  message: "This can't be undone.") {
                Button("Cancel", variant: .secondary) { self.confirmDelete = false }
                Button("Delete") { self.deleteResult = "Item deleted"; self.confirmDelete = false }
            }
            // Rename opts into backdrop-to-cancel (clicking outside closes without renaming).
            Prompt("Rename file", isPresented: $showRename, text: $fileName,
                   message: "Enter a new name", placeholder: "untitled",
                   confirmTitle: "Rename", dismissOnBackdrop: true) { newName in
                // fileName is already bound; this is where an app would persist the change.
                self.fileName = newName.isEmpty ? "untitled" : newName
            }
            // Mounted once; toasts are an app-owned queue ($toasts). They auto-dismiss
            // (4s) or via ✕, removing themselves. Danger toasts announce assertively.
            ToastStack(queue: $toasts)

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
            + "components freeze rows at first mount. \"Edit\" fires a toast so the in-cell action "
            + "is visible without mixing onRowClick with in-cell buttons (they share click events)."
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
                          maxHeight: .custom("360px"),
                          key: "people-\(roleFilter)-\(shown.count)") {
                    Column("Name", value: \.name)
                    Column("Age", value: \.age).align(.trailing)
                    Column("Role") { p in Badge(p.role, variant: .accent) }
                    Column("") { p in
                        Button("Edit", variant: .secondary, size: .sm) {
                            self.$toasts.send(.show(ToastItem("Editing \(p.name)", variant: .info)))
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
                          maxHeight: .custom("440px"),
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

    /// A small surfaced tile used to fill the grid demo.
    private func card(_ title: String) -> VNode {
        div { text(title) }
            .padding(.md)
            .style("background", "var(--sw-surface)")
            .style("border", "var(--sw-border-width) solid var(--sw-border)")
            .style("border-radius", "var(--sw-radius)")
            .style("text-align", "center")
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
        .style("background", "var(--sw-surface)")
        .style("border-radius", "var(--sw-radius)")
    }
}

@main
struct App {
    @MainActor static func main() { Swiflow.render(into: "#app") { Demo() } }
}
