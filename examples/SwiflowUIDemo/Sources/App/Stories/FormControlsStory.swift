import Swiflow
import SwiflowUI

@Component
final class FormControlsStory {
    @State var name: String = ""
    @State var email: String = ""
    @State var subscribed: Bool = false
    @State var color: String = ""
    @State var plan: String = "Free"
    @State var accepted: Bool = false
    @State var ctrl: FormController = FormController()
    @State var element: String = ""
    @State var asyncElement: String = ""

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

        return storyPage("Form controls",
                          blurb: "Text entry, selection, and choice controls, wired with Field(...) "
                            + "validators where a value needs to be required/typed.") {
            variantSection("Text & selection", snippet: """
            TextField("Name", text: $name, placeholder: "Ada Lovelace")
            TextField("Email", field: emailField, type: .email, placeholder: "you@example.com")
            Select("Favorite color", selection: $color, options: ["Red", "Green", "Blue"], placeholder: "Choose…")
            Autocomplete("Element", selection: $element, options: periodicElements.map { SelectOption($0) })
            Autocomplete("Element (async)", selection: $asyncElement, loader: { query in … })
            """) {
                Card(variant: .plain) {
                    VStack(spacing: .md, align: .stretch) {
                        TextField("Name", text: $name, placeholder: "Ada Lovelace")
                        TextField("Email", field: emailField, type: .email, placeholder: "you@example.com")
                        Select("Favorite color", selection: $color, options: ["Red", "Green", "Blue"], placeholder: "Choose…")
                        // A non-address domain on purpose: Chrome forces address autofill onto
                        // anything it reads as a "Country" field (ignoring autocomplete="off"),
                        // and that overlay covers the custom listbox.
                        Autocomplete("Element", selection: $element,
                                     options: FormControlsStory.periodicElements.map { SelectOption($0) },
                                     placeholder: "Type to search…")
                        // Async/remote variant: the loader filters behind a simulated 350ms delay,
                        // so you see the Searching… state, then results. Debounced (rapid typing
                        // fires one request) and cancellation-safe via .task(rerunOn:).
                        Autocomplete("Element (async)", selection: $asyncElement, loader: { query in
                            try await Task.sleep(nanoseconds: 350_000_000)
                            return FormControlsStory.periodicElements
                                .filter { $0.lowercased().contains(query.lowercased()) }
                                .map { SelectOption($0) }
                        }, placeholder: "Search the periodic table…")
                        if !name.isEmpty { p("Hello, \(name)!\(subscribed ? " (subscribed)" : "")") }
                    }
                }
            }
            variantSection("Choice", snippet: """
            RadioGroup("Plan", selection: $plan, options: ["Free", "Pro", "Team"], size: .sm)
            Toggle("Subscribe to updates", isOn: $subscribed)
            Checkbox("I accept the terms", field: termsField)
            """) {
                Card(variant: .plain) {
                    VStack(spacing: .md, align: .stretch) {
                        RadioGroup("Plan", selection: $plan, options: ["Free", "Pro", "Team"], size: .sm)
                        Toggle("Subscribe to updates", isOn: $subscribed)   // switch: an immediate on/off setting
                        Checkbox("I accept the terms", field: termsField)   // checkbox: confirmation, submitted with a form
                    }
                }
                p("Toggle is a switch (an immediate setting — like Dark mode, top-right); Checkbox is for "
                  + "confirmation. The email + terms fields use Field(...) + validators — interact then blur "
                  + "to see the role=alert error and aria-invalid.")
            }
        }
    }
}
