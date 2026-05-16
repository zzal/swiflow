// Sources/Swiflow/Patch.swift

/// A single mutation instruction emitted by the diff engine and consumed by
/// the JS driver (in Phase 2). Patches reference DOM nodes by integer handles
/// pre-allocated on the Swift side; the driver maintains a `Map<int, Node>`.
///
/// The 16 opcodes are grouped:
/// - **Lifecycle**: create / destroy DOM nodes.
/// - **Tree structure**: parent/child wiring.
/// - **Per-bag mutations**: attribute / property / style / text.
/// - **Events**: add / remove DOM event listeners (handlerId points into
///   `HandlerRegistry`).
public enum Patch: Equatable, Sendable {
    // MARK: - Lifecycle
    case createElement(handle: Int, tag: String)
    case createText(handle: Int, text: String)
    case createRawHTML(handle: Int, html: String)
    case destroyNode(handle: Int)

    // MARK: - Tree structure
    case appendChild(parent: Int, child: Int)
    case insertBefore(parent: Int, child: Int, beforeChild: Int)
    case removeChild(parent: Int, child: Int)

    // MARK: - Per-bag mutations
    case setAttribute(handle: Int, name: String, value: String)
    case removeAttribute(handle: Int, name: String)
    case setProperty(handle: Int, name: String, value: PropertyValue)
    case removeProperty(handle: Int, name: String)
    case setStyle(handle: Int, name: String, value: String)
    case removeStyle(handle: Int, name: String)
    case setText(handle: Int, text: String)

    // MARK: - Events
    case addHandler(handle: Int, event: String, handlerId: Int)
    case removeHandler(handle: Int, event: String)
}
