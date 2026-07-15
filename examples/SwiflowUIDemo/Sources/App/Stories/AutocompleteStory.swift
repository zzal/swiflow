import Swiflow
import SwiflowUI

@Component
final class AutocompleteStory {
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
        storyPage("Autocomplete",
                  blurb: "A type-to-filter combobox over a Binding<String> — static options, or an "
                       + "async loader for remote data (debounced, cancellation-safe, with a "
                       + "Searching… state).") {
            variantSection("Static options", snippet: """
            Autocomplete("Element", selection: $element, options: periodicElements.map { SelectOption($0) })
            """) {
                Card(variant: .plain) {
                    // A non-address domain on purpose: Chrome forces address autofill onto
                    // anything it reads as a "Country" field (ignoring autocomplete="off"),
                    // and that overlay covers the custom listbox.
                    Autocomplete("Element", selection: $element,
                                 options: AutocompleteStory.periodicElements.map { SelectOption($0) },
                                 placeholder: "Type to search…")
                }
            }
            variantSection("Async loader", snippet: """
            Autocomplete("Element (async)", selection: $asyncElement, loader: { query in
                try await Task.sleep(nanoseconds: 350_000_000)   // simulated network
                return periodicElements
                    .filter { $0.lowercased().contains(query.lowercased()) }
                    .map { SelectOption($0) }
            })
            """) {
                Card(variant: .plain) {
                    // Async/remote variant: the loader filters behind a simulated 350ms delay,
                    // so you see the Searching… state, then results. Debounced (rapid typing
                    // fires one request) and cancellation-safe via .task(rerunOn:).
                    Autocomplete("Element (async)", selection: $asyncElement, loader: { query in
                        try await Task.sleep(nanoseconds: 350_000_000)
                        return AutocompleteStory.periodicElements
                            .filter { $0.lowercased().contains(query.lowercased()) }
                            .map { SelectOption($0) }
                    }, placeholder: "Search the periodic table…")
                }
            }
        }
    }
}
