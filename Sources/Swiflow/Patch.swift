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

    /// Creates an element node with the given tag, bound to `handle`.
    case createElement(handle: Int, tag: String)
    /// Creates a text node. Always set via `textContent` for XSS safety.
    case createText(handle: Int, text: String)
    /// Creates a node from a raw HTML string, set via `innerHTML`. Caller is
    /// responsible for trusting / sanitizing the markup.
    case createRawHTML(handle: Int, html: String)
    /// Detaches `handle` from the driver's node map and lets the DOM GC it.
    case destroyNode(handle: Int)

    // MARK: - Tree structure

    /// Appends `child` as the last child of `parent`.
    case appendChild(parent: Int, child: Int)
    /// Inserts `child` immediately before `beforeChild` under `parent`.
    case insertBefore(parent: Int, child: Int, beforeChild: Int)
    /// Removes `child` from `parent` without destroying it.
    case removeChild(parent: Int, child: Int)

    // MARK: - Per-bag mutations

    /// Sets an HTML attribute via `element.setAttribute(name, value)`.
    case setAttribute(handle: Int, name: String, value: String)
    /// Removes an HTML attribute via `element.removeAttribute(name)`.
    case removeAttribute(handle: Int, name: String)
    /// Assigns a DOM property via `element[name] = value` (typed).
    case setProperty(handle: Int, name: String, value: PropertyValue)
    /// Restores a DOM property to its default by deleting the own-property.
    case removeProperty(handle: Int, name: String)
    /// Sets an inline style declaration via `element.style[name] = value`.
    case setStyle(handle: Int, name: String, value: String)
    /// Removes an inline style declaration.
    case removeStyle(handle: Int, name: String)
    /// Updates a text node's content via `textContent`.
    case setText(handle: Int, text: String)

    // MARK: - Events

    /// Adds a DOM event listener wired to the Swift dispatcher under
    /// `handlerId`.
    case addHandler(handle: Int, event: String, handlerId: Int)
    /// Removes the listener previously registered for `event` on `handle`.
    case removeHandler(handle: Int, event: String)
}
