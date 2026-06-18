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
            guard let detail = info.detail, let decoder = RegionDecoder.current else { return }
            guard let decoded = try? decoder.decode(G.Event.self, from: detail) else { return }
            action(decoded)
        }
        d.handlers["sf:event"] = handler
        return RegionView<G>(data: d)
    }

    /// Handle a region failure (load/instantiate/trap/protocol-mismatch). The
    /// app typically flips state here to render a sibling fallback.
    @MainActor
    func onError(_ action: @escaping @MainActor (RegionError) -> Void) -> RegionView<G> {
        var d = data
        let handler = _registerAmbientHandler { info in
            guard let detail = info.detail, let decoder = RegionDecoder.current else { return }
            guard let decoded = try? decoder.decode(RegionError.self, from: detail) else { return }
            action(decoded)
        }
        d.handlers["sf:error"] = handler
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
    let json = (try? JSONValueEncoder().encode(props).jsonString) ?? "null"
    let data = ElementData(
        tag: "sf-region",
        key: key,
        attributes: ["data-source": G.source],
        properties: ["sfProps": .string(json)]
    )
    return RegionView<G>(data: data)
}
