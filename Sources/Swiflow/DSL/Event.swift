// Sources/Swiflow/DSL/Event.swift

/// Catalog of DOM event names used by `.on(_:perform:)` modifiers.
///
/// Most events are simple cases that map 1:1 to their DOM name via
/// `String(describing:)`. The `.custom(_:)` case is the escape hatch for
/// events not in the catalog (custom DOM events, library events, future
/// additions before this enum is updated).
///
/// Usage:
/// ```swift
/// button("Save").on(.click) { save() }
/// input(.prop("type", "text")).on(.input) { event in
///     name = event.targetValue ?? ""
/// }
/// ```
public enum Event: Sendable, Hashable {
    case click
    case input, change, submit
    case keydown, keyup, keypress
    case focus, blur
    case mousedown, mouseup, mousemove, mouseenter, mouseleave
    case custom(String)

    /// The raw DOM event name (`"click"`, `"input"`, etc.). Read by the
    /// renderer when registering the listener on the host element.
    package var domName: String {
        switch self {
        case .custom(let name): return name
        default: return String(describing: self)
        }
    }
}
