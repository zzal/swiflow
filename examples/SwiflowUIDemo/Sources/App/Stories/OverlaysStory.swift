import Swiflow
import SwiflowUI

@Component
final class OverlaysStory {
    @State var confirmDelete: Bool = false
    @State var deleteResult: String = ""
    @State var showRename: Bool = false
    @State var fileName: String = "untitled"
    @ReducerState var toasts: ToastQueue

    var body: VNode {
        storyPage("Overlays",
                  blurb: "Alert and Prompt are native <dialog>.showModal() modals — top layer, backdrop, "
                       + "focus trap and ESC-to-close all native, sharing one .sw-dialog chrome. Prompt "
                       + "wraps a <form method=\"dialog\">, so Enter submits. The Delete alert demands a "
                       + "deliberate choice (no backdrop dismiss); Rename opts into dismissOnBackdrop, so "
                       + "clicking outside cancels it. Backdrop solidifies under prefers-reduced-transparency "
                       + "and the open animation collapses under prefers-reduced-motion, both via tokens.") {
            variantSection("Modal dialogs", snippet: """
            Alert("Delete this item?", isPresented: $confirmDelete,
                  message: "This can't be undone.") {
                Button("Cancel", variant: .secondary) { self.confirmDelete = false }
                Button("Delete", variant: .danger) { self.deleteResult = "Item deleted"; self.confirmDelete = false }
            }
            Prompt("Rename file", isPresented: $showRename, text: $fileName,
                   message: "Enter a new name", placeholder: "untitled",
                   confirmTitle: "Rename", dismissOnBackdrop: true) { newName in
                self.fileName = newName.isEmpty ? "untitled" : newName
            }
            """) {
                HStack(spacing: .md, align: .center) {
                    Button("Delete item…", variant: .secondary) { self.confirmDelete = true }
                    Button("Rename \(fileName)…", variant: .secondary) { self.showRename = true }
                    if !deleteResult.isEmpty { Badge(deleteResult, variant: .success) }
                }
                // A destructive confirm: backdrop dismiss left OFF (the default) so it's not
                // closed by accident.
                Alert("Delete this item?", isPresented: $confirmDelete,
                      message: "This can't be undone.") {
                    Button("Cancel", variant: .secondary) { self.confirmDelete = false }
                    Button("Delete", variant: .danger) { self.deleteResult = "Item deleted"; self.confirmDelete = false }
                }
                // Rename opts into backdrop-to-cancel (clicking outside closes without renaming).
                Prompt("Rename file", isPresented: $showRename, text: $fileName,
                       message: "Enter a new name", placeholder: "untitled",
                       confirmTitle: "Rename", dismissOnBackdrop: true) { newName in
                    // fileName is already bound; this is where an app would persist the change.
                    self.fileName = newName.isEmpty ? "untitled" : newName
                }
            }
            variantSection("Toasts", snippet: """
            Button("Toast: success", variant: .ghost) { self.$toasts.show("Saved successfully", .success) }
            Button("Toast: info", variant: .ghost) { self.$toasts.show("Heads up — sync running") }
            Button("Toast: warning", variant: .ghost) { self.$toasts.show("Low disk space", .warning) }
            Button("Toast: error", variant: .ghost) { self.$toasts.show("Couldn't reach the server", .danger) }
            Button("Clear all", variant: .ghost) { self.$toasts.send(.dismissAll) }
            """) {
                HStack(spacing: .md, align: .center) {
                    Button("Toast: success", variant: .ghost) { self.$toasts.show("Saved successfully", .success) }
                    Button("Toast: info", variant: .ghost) { self.$toasts.show("Heads up — sync running") }
                    Button("Toast: warning", variant: .ghost) { self.$toasts.show("Low disk space", .warning) }
                    Button("Toast: error", variant: .ghost) { self.$toasts.show("Couldn't reach the server", .danger) }
                    Button("Clear all", variant: .ghost) { self.$toasts.send(.dismissAll) }
                }
            }
            variantSection("Dropdown menu", snippet: """
            Dropdown("Actions") {
                DropdownItem("Edit") { self.$toasts.show("Edit selected") }
                DropdownItem("Duplicate") { self.$toasts.show("Duplicated", .success) }
                DropdownItem("Archive", disabled: true) {}
                DropdownDivider()
                DropdownItem("Delete", variant: .danger) { self.$toasts.show("Deleted", .danger) }
            }
            """) {
                HStack(spacing: .md, align: .center) {
                    // Dropdown: a Popover-API menu anchored to its trigger; items close it on
                    // select (popovertargetaction=hide) and fire a toast here.
                    Dropdown("Actions") {
                        DropdownItem("Edit") { self.$toasts.show("Edit selected") }
                        DropdownItem("Duplicate") { self.$toasts.show("Duplicated", .success) }
                        DropdownItem("Archive", disabled: true) {}
                        DropdownDivider()
                        DropdownItem("Delete", variant: .danger) { self.$toasts.show("Deleted", .danger) }
                    }
                }
            }
            // Mounted once; toasts are an app-owned queue ($toasts). They auto-dismiss
            // (4s) or via ✕, removing themselves. Danger toasts announce assertively.
            ToastStack(queue: $toasts)
        }
    }
}
