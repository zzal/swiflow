/// Encodes a `Patch` into a `PatchPayload` for transport across the WASM↔JS
/// bridge.
///
/// The op-name strings are part of the wire format: the JS driver dispatches
/// on `payload.op`, so any rename here MUST be coordinated with
/// `js-driver/swiflow-driver.js`. Field names are case-sensitive and match
/// the JS driver's switch arms.
package enum PatchSerializer {
    package static func encode(_ patch: Patch) -> PatchPayload {
        switch patch {
        // MARK: Lifecycle
        case .createElement(let handle, let tag):
            return PatchPayload(op: "createElement", fields: [
                "handle": .int(handle),
                "tag": .string(tag),
            ])
        case .createText(let handle, let text):
            return PatchPayload(op: "createText", fields: [
                "handle": .int(handle),
                "text": .string(text),
            ])
        case .createRawHTML(let handle, let html):
            return PatchPayload(op: "createRawHTML", fields: [
                "handle": .int(handle),
                "html": .string(html),
            ])
        case .destroyNode(let handle):
            return PatchPayload(op: "destroyNode", fields: [
                "handle": .int(handle),
            ])
        case .animateExit(let handle, let parentHandle, let animation, let durationMs):
            return PatchPayload(op: "animateExit", fields: [
                "handle":       .int(handle),
                "parentHandle": .int(parentHandle),
                "animation":    .string(animation),
                "durationMs":   .double(durationMs),
            ])

        // MARK: Tree structure
        case .appendChild(let parent, let child):
            return PatchPayload(op: "appendChild", fields: [
                "parent": .int(parent),
                "child": .int(child),
            ])
        case .insertBefore(let parent, let child, let beforeChild):
            return PatchPayload(op: "insertBefore", fields: [
                "parent": .int(parent),
                "child": .int(child),
                "beforeChild": .int(beforeChild),
            ])
        case .removeChild(let parent, let child):
            return PatchPayload(op: "removeChild", fields: [
                "parent": .int(parent),
                "child": .int(child),
            ])

        // MARK: Mutations
        case .setAttribute(let handle, let name, let value):
            return PatchPayload(op: "setAttribute", fields: [
                "handle": .int(handle),
                "name": .string(name),
                "value": .string(value),
            ])
        case .removeAttribute(let handle, let name):
            return PatchPayload(op: "removeAttribute", fields: [
                "handle": .int(handle),
                "name": .string(name),
            ])
        case .setProperty(let handle, let name, let value):
            return PatchPayload(op: "setProperty", fields: [
                "handle": .int(handle),
                "name": .string(name),
                "value": .property(value),
            ])
        case .removeProperty(let handle, let name):
            return PatchPayload(op: "removeProperty", fields: [
                "handle": .int(handle),
                "name": .string(name),
            ])
        case .setStyle(let handle, let name, let value):
            return PatchPayload(op: "setStyle", fields: [
                "handle": .int(handle),
                "name": .string(name),
                "value": .string(value),
            ])
        case .removeStyle(let handle, let name):
            return PatchPayload(op: "removeStyle", fields: [
                "handle": .int(handle),
                "name": .string(name),
            ])
        case .setText(let handle, let text):
            return PatchPayload(op: "setText", fields: [
                "handle": .int(handle),
                "text": .string(text),
            ])
        case .setRawHTML(let handle, let html):
            return PatchPayload(op: "setRawHTML", fields: [
                "handle": .int(handle),
                "html": .string(html),
            ])

        // MARK: Events
        case .addHandler(let handle, let event, let handlerId):
            return PatchPayload(op: "addHandler", fields: [
                "handle": .int(handle),
                "event": .string(event),
                "handlerId": .int(handlerId),
            ])
        case .removeHandler(let handle, let event):
            return PatchPayload(op: "removeHandler", fields: [
                "handle": .int(handle),
                "event": .string(event),
            ])

        // MARK: Mount target
        case .replaceMount(let selector, let newHandle):
            return PatchPayload(op: "replaceMount", fields: [
                "selector":  .string(selector),
                "newHandle": .int(newHandle),
            ])
        }
    }
}
