import Swiflow
import SwiflowDOM
import SwiflowUI

@MainActor @Component
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
    @State var toasts: [ToastItem] = []
    @State var country: String = ""

    var body: VNode {
        let emailField = Field("email", $email, $ctrl, .required(), .email)
        let termsField = Field("terms", $accepted, $ctrl, .custom("You must accept the terms") { $0 })

        return VStack(spacing: .lg, align: .stretch) {
            // A Toggle wired to `color-scheme` re-themes the whole demo: every
            // --sw-* token is light-dark(), so flipping the scheme flips them all.
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

            // --- Form controls -------------------------------------------
            h2("Form controls")
            VStack(spacing: .md, align: .stretch) {
                TextField("Name", text: $name, placeholder: "Ada Lovelace")
                TextField("Email", field: emailField, type: .email, placeholder: "you@example.com")
                Select("Favorite color", selection: $color, options: ["Red", "Green", "Blue"], placeholder: "Choose…")
                Autocomplete("Country", selection: $country,
                             options: ["Argentina", "Australia", "Brazil", "Canada", "France",
                                       "Germany", "India", "Japan", "Mexico", "Spain",
                                       "United Kingdom", "United States"],
                             placeholder: "Type to search…")
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
                Button("Toast: success", variant: .ghost) { self.toasts.append(ToastItem("Saved successfully", variant: .success)) }
                Button("Toast: info", variant: .ghost) { self.toasts.append(ToastItem("Heads up — sync running")) }
                Button("Toast: error", variant: .ghost) { self.toasts.append(ToastItem("Couldn't reach the server", variant: .danger)) }
            }
            HStack(spacing: .md, align: .center) {
                // Dropdown: a Popover-API menu anchored to its trigger; items close it on
                // select (popovertargetaction=hide) and fire a toast here.
                Dropdown("Actions") {
                    DropdownItem("Edit") { self.toasts.append(ToastItem("Edit selected")) }
                    DropdownItem("Duplicate") { self.toasts.append(ToastItem("Duplicated", variant: .success)) }
                    DropdownDivider()
                    DropdownItem("Delete", variant: .danger) { self.toasts.append(ToastItem("Deleted", variant: .danger)) }
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
            ToastStack(toasts: $toasts)
        }
        .padding(.xl)
        // Forcing `color-scheme` on the root makes every descendant's light-dark()
        // token resolve to this scheme — overriding the OS preference live.
        .style("color-scheme", isDark ? "dark" : "light")
        .style("background", "var(--sw-bg)")   // page/canvas, so the surface cards lift off it
        .style("color", "var(--sw-text)")
        .style("min-height", "100vh")
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

@main
struct App {
    @MainActor static func main() { Swiflow.render(into: "#app") { Demo() } }
}
