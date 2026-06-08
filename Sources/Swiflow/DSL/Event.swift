// Sources/Swiflow/DSL/Event.swift

/// Catalog of DOM event names used by `.on(_:perform:)` modifiers.
///
/// Each case maps 1:1 to its DOM name through an explicit `switch` in
/// `domName`. The `.custom(_:)` case is the escape hatch for events not in
/// the catalog (custom DOM events, library events, future additions before
/// this enum is updated).
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
    ///
    /// These are spelled out explicitly rather than derived via
    /// `String(describing: self)`. That shortcut reads the enum *case* name
    /// from reflection metadata, which release builds strip with
    /// `-Xswiftc -disable-reflection-metadata` (see BuildCommand) — there
    /// `String(describing:)` collapses to the *type* name "Event", so every
    /// listener bound to `addEventListener("Event", …)` and no DOM event
    /// ever fired it (dead buttons in `swiflow build`, fine in `swiflow dev`
    /// which keeps the metadata). An exhaustive switch is reflection-free and
    /// behaves identically in debug and release.
    package var domName: String {
        switch self {
        case .click: return "click"
        case .input: return "input"
        case .change: return "change"
        case .submit: return "submit"
        case .keydown: return "keydown"
        case .keyup: return "keyup"
        case .keypress: return "keypress"
        case .focus: return "focus"
        case .blur: return "blur"
        case .mousedown: return "mousedown"
        case .mouseup: return "mouseup"
        case .mousemove: return "mousemove"
        case .mouseenter: return "mouseenter"
        case .mouseleave: return "mouseleave"
        case .custom(let name): return name
        }
    }
}
