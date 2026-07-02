// Sources/Swiflow/Regions/RegionView.swift

/// Shared building state + sizing modifiers for the typed and inline region
/// faces. Conformers expose a mutable `ElementData` and rebuild from it.
public protocol RegionModifiable {
    var data: ElementData { get set }
    init(data: ElementData)
}

public extension RegionModifiable {
    /// Fill the parent slot (the default sizing when none is given).
    func fill() -> Self {
        var d = data; d.style["width"] = "100%"; d.style["height"] = "100%"
        return Self(data: d)
    }
    /// Fixed CSS pixel size.
    func frame(width: Int, height: Int) -> Self {
        var d = data; d.style["width"] = "\(width)px"; d.style["height"] = "\(height)px"
        return Self(data: d)
    }
    /// Self-sufficient aspect ratio: fills available width, height derives.
    /// Two ints, not `16/9` — a bare ratio would be Swift integer division.
    func aspectRatio(_ w: Int, _ h: Int) -> Self {
        var d = data; d.style["aspect-ratio"] = "\(w) / \(h)"; d.style["width"] = "100%"
        return Self(data: d)
    }
    func asVNode() -> VNode { .element(data) }
}

/// The typed face of a region, parameterized by its guest. Carries `G.Event`
/// so `.onEvent`'s closure parameter is inferred with no annotation.
public struct RegionView<G: RegionGuest>: RegionModifiable {
    public var data: ElementData
    public init(data: ElementData) { self.data = data }
}

public extension RegionView {
    /// Handle a guest event. The closure parameter type is inferred as
    /// `G.Event` — no annotation. The raw `sf:event` JSON payload is decoded
    /// through the installed `RegionDecoder`; if none is installed or decoding
    /// fails, the event is dropped.
    @MainActor
    func onEvent(_ action: @escaping @MainActor (G.Event) -> Void) -> RegionView<G> {
        var d = data
        let handler = _registerAmbientHandler { info in
            guard let detail = info.detail else {
                swiflowDiagnostic("Region '\(RegionWire.eventName)' handler fired with no detail payload; dropping event for \(G.Event.self) (guest: \(G.source)).")
                return
            }
            guard let decoder = RegionDecoder.current else {
                swiflowDiagnostic("Region event received for \(G.Event.self) (guest: \(G.source)) but no RegionDecoder is installed (RegionDecoder.current is nil); dropping event.")
                return
            }
            guard let decoded = try? decoder.decode(G.Event.self, from: detail) else {
                swiflowDiagnostic("Region event decode failed for \(G.Event.self) (guest: \(G.source)) from payload: \(detail). Dropping event.")
                return
            }
            action(decoded)
        }
        d.handlers[RegionWire.eventName] = handler
        return RegionView<G>(data: d)
    }

    /// Handle a region failure (load/instantiate/trap/protocol-mismatch). The
    /// app typically flips state here to render a sibling fallback.
    @MainActor
    func onError(_ action: @escaping @MainActor (RegionError) -> Void) -> RegionView<G> {
        var d = data
        let handler = _registerAmbientHandler { info in
            guard let detail = info.detail else {
                swiflowDiagnostic("Region '\(RegionWire.errorName)' handler fired with no detail payload (guest: \(G.source)); dropping error.")
                return
            }
            guard let decoder = RegionDecoder.current else {
                swiflowDiagnostic("Region error received (guest: \(G.source)) but no RegionDecoder is installed (RegionDecoder.current is nil); dropping error.")
                return
            }
            guard let decoded = try? decoder.decode(RegionError.self, from: detail) else {
                swiflowDiagnostic("Region error decode failed (guest: \(G.source)) from payload: \(detail). Dropping error.")
                return
            }
            action(decoded)
        }
        d.handlers[RegionWire.errorName] = handler
        return RegionView<G>(data: d)
    }
}

/// Build a region for guest `G`. Props are encoded to a JSON string at build
/// time (so the diff compares them as one opaque value) and carried as the
/// `sfProps` property; the guest source rides as the `data-source` attribute.
@MainActor
public func region<G: RegionGuest>(
    _ guest: G.Type,
    key: String,
    props: G.Props
) -> RegionView<G> {
    let json: String
    do {
        json = try JSONValueEncoder().encode(props).jsonString
    } catch {
        swiflowDiagnostic("region props encoding failed for \(type(of: props)) (source: \(G.source)): \(error). Sending \"null\".")
        json = "null"
    }
    let data = ElementData(
        tag: RegionWire.tag,
        key: key,
        attributes: [RegionWire.sourceAttr: G.source],
        properties: [RegionWire.propsKey: .string(json)]
    )
    return RegionView<G>(data: data)
}
