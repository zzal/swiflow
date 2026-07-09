// Sources/SwiflowTesting/Queries.swift
//
// Audit VI Wave-2 #1: the find(role:)/find(class:)/find(label:) query
// vocabulary — the RTL getByRole bar. Tag+text-only queries are why the
// SwiflowUI suites hand-rolled VNode walkers instead of adopting the
// harness: component tests want to speak the ACCESSIBILITY tree ("the
// textbox labelled Email"), not CSS-selector positions.
import Swiflow

/// The implicit WAI-ARIA role for an element — the practical subset of the
/// HTML-AAM mapping the harness understands. An explicit `role` attribute
/// always wins (see `role(of:)`); this table only answers "what role does
/// the bare tag imply". Returns nil for tags with no (useful) implicit role.
func implicitRole(tag: String, attributes: [String: String]) -> String? {
    switch tag {
    case "a": return attributes["href"] != nil ? "link" : nil
    case "button": return "button"
    case "input":
        switch attributes["type"] ?? "text" {
        case "checkbox": return "checkbox"
        case "radio": return "radio"
        case "range": return "slider"
        case "number": return "spinbutton"
        case "search": return "searchbox"
        case "button", "submit", "reset": return "button"
        case "hidden": return nil
        default: return "textbox"   // text/email/password/tel/url/…
        }
    case "textarea": return "textbox"
    case "select": return "combobox"
    case "option": return "option"
    case "h1", "h2", "h3", "h4", "h5", "h6": return "heading"
    case "img": return "img"
    case "nav": return "navigation"
    case "main": return "main"
    case "header": return "banner"
    case "footer": return "contentinfo"
    case "aside": return "complementary"
    case "article": return "article"
    case "section": return "region"
    case "form": return "form"
    case "table": return "table"
    case "thead", "tbody", "tfoot": return "rowgroup"
    case "tr": return "row"
    case "th": return "columnheader"
    case "td": return "cell"
    case "ul", "ol": return "list"
    case "li": return "listitem"
    case "dialog": return "dialog"
    case "progress": return "progressbar"
    case "hr": return "separator"
    case "fieldset": return "group"
    default: return nil
    }
}

/// The element's effective role: explicit `role` attribute, else implicit.
func role(of data: ElementData) -> String? {
    data.attributes["role"] ?? implicitRole(tag: data.tag, attributes: data.attributes)
}

extension TestRenderer {

    /// Generic walk — the ONE traversal every query is expressed over
    /// (document order, descends through components/env overrides/fragments).
    func findElements(
        in node: MountNode,
        where predicate: (MountNode, ElementData) -> Bool
    ) -> [(MountNode, ElementData)] {
        var results: [(MountNode, ElementData)] = []
        switch node.vnode {
        case .element(let data):
            if predicate(node, data) { results.append((node, data)) }
            for child in node.children {
                results += findElements(in: child, where: predicate)
            }
        case .fragment:
            for child in node.children {
                results += findElements(in: child, where: predicate)
            }
        case .component, .environmentOverride:
            if let body = node.componentBody {
                results += findElements(in: body, where: predicate)
            }
        default:
            break
        }
        return results
    }

    /// The accessible label of an element, resolved in precedence order:
    /// `aria-label` → `<label for=id>` → wrapping ancestor `<label>` → the
    /// element's own subtree text (a button/link/heading names itself).
    /// Deliberately NOT full accname computation (`aria-labelledby` is not
    /// resolved) — documented in the guide.
    func accessibleLabel(of node: MountNode, _ data: ElementData) -> String {
        if let aria = data.attributes["aria-label"] { return aria }
        if let id = data.attributes["id"] {
            let linked = findElements(in: mountTree) { _, d in
                d.tag == "label" && d.attributes["for"] == id
            }
            if let (labelNode, _) = linked.first { return textContent(of: labelNode) }
        }
        var ancestor = node.parent
        while let current = ancestor {
            if case .element(let d) = current.vnode, d.tag == "label" {
                return textContent(of: current)
            }
            ancestor = current.parent
        }
        return textContent(of: node)
    }

    /// Elements whose effective role is `role`, optionally filtered by
    /// accessible label (contains-match, like `text:`).
    func findByRole(_ roleName: String, label: String?) -> [(MountNode, ElementData)] {
        findElements(in: mountTree) { node, data in
            guard role(of: data) == roleName else { return false }
            guard let label else { return true }
            return accessibleLabel(of: node, data).contains(label)
        }
    }

    /// Elements whose accessible label contains `label`, any role.
    func findByLabel(_ label: String) -> [(MountNode, ElementData)] {
        findElements(in: mountTree) { node, data in
            accessibleLabel(of: node, data).contains(label)
        }
    }

    /// Elements whose class LIST contains the token `className` (token
    /// match, not substring — `sw-err` never matches `sw-error`).
    func findByClass(_ className: String) -> [(MountNode, ElementData)] {
        findElements(in: mountTree) { _, data in
            guard let classes = data.attributes["class"] else { return false }
            return classes.split(separator: " ").contains(Substring(className))
        }
    }

    /// Whether `node` is still part of the committed tree. Detached subtrees
    /// have their `parent` pointer cleared at the detach point, so climbing
    /// to the top either reaches the current root (live) or an orphan (stale).
    func isAttached(_ node: MountNode) -> Bool {
        var current = node
        while let parent = current.parent { current = parent }
        return current === mountTree
    }
}
