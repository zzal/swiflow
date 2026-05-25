/// A serialized `Patch`, ready to be ferried across the WASM↔JS bridge.
///
/// `PatchPayload` is the testable intermediate between the typed `Patch`
/// enum and the untyped `JSObject` the JS driver receives. Holding the
/// payload as a plain Swift value lets every encoding decision live under
/// `swift test`; only the final dict→JSObject step depends on JavaScriptKit
/// and so escapes macOS-side testing.
package struct PatchPayload: Equatable, Sendable {
    package let op: String
    package let fields: [String: Field]

    package init(op: String, fields: [String: Field]) {
        self.op = op
        self.fields = fields
    }

    /// A single field value inside a `PatchPayload.fields` dictionary.
    package enum Field: Equatable, Sendable {
        case int(Int)
        case string(String)
        case property(PropertyValue)
        case double(Double)
    }
}
