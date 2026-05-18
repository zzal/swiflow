import Testing
@testable import Swiflow

@Suite("PatchSerializer")
struct PatchSerializerTests {

    // MARK: - Lifecycle

    @Test("createElement encodes op + handle + tag")
    func createElement() {
        let p = Patch.createElement(handle: 7, tag: "div")
        #expect(PatchSerializer.encode(p) == PatchPayload(
            op: "createElement",
            fields: ["handle": .int(7), "tag": .string("div")]
        ))
    }

    @Test("createText encodes op + handle + text")
    func createText() {
        let p = Patch.createText(handle: 7, text: "hi")
        #expect(PatchSerializer.encode(p) == PatchPayload(
            op: "createText",
            fields: ["handle": .int(7), "text": .string("hi")]
        ))
    }

    @Test("createRawHTML encodes op + handle + html")
    func createRawHTML() {
        let p = Patch.createRawHTML(handle: 7, html: "<b/>")
        #expect(PatchSerializer.encode(p) == PatchPayload(
            op: "createRawHTML",
            fields: ["handle": .int(7), "html": .string("<b/>")]
        ))
    }

    @Test("destroyNode encodes op + handle")
    func destroyNode() {
        let p = Patch.destroyNode(handle: 7)
        #expect(PatchSerializer.encode(p) == PatchPayload(
            op: "destroyNode",
            fields: ["handle": .int(7)]
        ))
    }

    // MARK: - Tree structure

    @Test("appendChild encodes op + parent + child")
    func appendChild() {
        let p = Patch.appendChild(parent: 1, child: 2)
        #expect(PatchSerializer.encode(p) == PatchPayload(
            op: "appendChild",
            fields: ["parent": .int(1), "child": .int(2)]
        ))
    }

    @Test("insertBefore encodes op + parent + child + beforeChild")
    func insertBefore() {
        let p = Patch.insertBefore(parent: 1, child: 2, beforeChild: 3)
        #expect(PatchSerializer.encode(p) == PatchPayload(
            op: "insertBefore",
            fields: [
                "parent": .int(1),
                "child": .int(2),
                "beforeChild": .int(3),
            ]
        ))
    }

    @Test("removeChild encodes op + parent + child")
    func removeChild() {
        let p = Patch.removeChild(parent: 1, child: 2)
        #expect(PatchSerializer.encode(p) == PatchPayload(
            op: "removeChild",
            fields: ["parent": .int(1), "child": .int(2)]
        ))
    }

    // MARK: - Mutations

    @Test("setAttribute encodes op + handle + name + value")
    func setAttribute() {
        let p = Patch.setAttribute(handle: 1, name: "class", value: "row")
        #expect(PatchSerializer.encode(p) == PatchPayload(
            op: "setAttribute",
            fields: [
                "handle": .int(1),
                "name": .string("class"),
                "value": .string("row"),
            ]
        ))
    }

    @Test("removeAttribute encodes op + handle + name")
    func removeAttribute() {
        let p = Patch.removeAttribute(handle: 1, name: "class")
        #expect(PatchSerializer.encode(p) == PatchPayload(
            op: "removeAttribute",
            fields: ["handle": .int(1), "name": .string("class")]
        ))
    }

    @Test("setProperty encodes op + handle + name + property value")
    func setProperty() {
        let p = Patch.setProperty(handle: 1, name: "value", value: .string("x"))
        #expect(PatchSerializer.encode(p) == PatchPayload(
            op: "setProperty",
            fields: [
                "handle": .int(1),
                "name": .string("value"),
                "value": .property(.string("x")),
            ]
        ))
    }

    @Test("removeProperty encodes op + handle + name")
    func removeProperty() {
        let p = Patch.removeProperty(handle: 1, name: "value")
        #expect(PatchSerializer.encode(p) == PatchPayload(
            op: "removeProperty",
            fields: ["handle": .int(1), "name": .string("value")]
        ))
    }

    @Test("setStyle encodes op + handle + name + value")
    func setStyle() {
        let p = Patch.setStyle(handle: 1, name: "color", value: "red")
        #expect(PatchSerializer.encode(p) == PatchPayload(
            op: "setStyle",
            fields: [
                "handle": .int(1),
                "name": .string("color"),
                "value": .string("red"),
            ]
        ))
    }

    @Test("removeStyle encodes op + handle + name")
    func removeStyle() {
        let p = Patch.removeStyle(handle: 1, name: "color")
        #expect(PatchSerializer.encode(p) == PatchPayload(
            op: "removeStyle",
            fields: ["handle": .int(1), "name": .string("color")]
        ))
    }

    @Test("setText encodes op + handle + text")
    func setText() {
        let p = Patch.setText(handle: 1, text: "hi")
        #expect(PatchSerializer.encode(p) == PatchPayload(
            op: "setText",
            fields: ["handle": .int(1), "text": .string("hi")]
        ))
    }

    @Test("setRawHTML encodes op + handle + html")
    func setRawHTML() {
        let p = Patch.setRawHTML(handle: 7, html: "<b>hi</b>")
        #expect(PatchSerializer.encode(p) == PatchPayload(
            op: "setRawHTML",
            fields: ["handle": .int(7), "html": .string("<b>hi</b>")]
        ))
    }

    // MARK: - Events

    @Test("addHandler encodes op + handle + event + handlerId")
    func addHandler() {
        let p = Patch.addHandler(handle: 1, event: "click", handlerId: 7)
        #expect(PatchSerializer.encode(p) == PatchPayload(
            op: "addHandler",
            fields: [
                "handle": .int(1),
                "event": .string("click"),
                "handlerId": .int(7),
            ]
        ))
    }

    @Test("removeHandler encodes op + handle + event")
    func removeHandler() {
        let p = Patch.removeHandler(handle: 1, event: "click")
        #expect(PatchSerializer.encode(p) == PatchPayload(
            op: "removeHandler",
            fields: ["handle": .int(1), "event": .string("click")]
        ))
    }
}
