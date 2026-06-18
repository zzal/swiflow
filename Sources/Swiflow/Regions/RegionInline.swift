// Sources/Swiflow/Regions/RegionInline.swift

/// The untyped face of a region, for quick/dynamic guests that skip a
/// `RegionGuest` declaration. Sizing comes from `RegionModifiable`; `.onEvent`
/// is generic over the event type, so call sites must annotate the closure.
public struct AnyRegionView: RegionModifiable {
    public var data: ElementData
    public init(data: ElementData) { self.data = data }
}

/// Inline region: no guest type, so the event type is supplied by the
/// `.onEvent` closure annotation rather than inferred.
@MainActor
public func region(
    source: String,
    key: String,
    props: some Encodable
) -> AnyRegionView {
    let json: String
    do {
        json = try JSONValueEncoder().encode(props).jsonString
    } catch {
        swiflowDiagnostic("region props encoding failed for \(type(of: props)): \(error). Sending \"null\".")
        json = "null"
    }
    let data = ElementData(
        tag: RegionWire.tag,
        key: key,
        attributes: [RegionWire.sourceAttr: source],
        properties: [RegionWire.propsKey: .string(json)]
    )
    return AnyRegionView(data: data)
}

public extension AnyRegionView {
    @MainActor
    func onEvent<E: RegionEvent>(_ action: @escaping @MainActor (E) -> Void) -> AnyRegionView {
        var d = data
        let handler = _registerAmbientHandler { info in
            guard let detail = info.detail, let decoder = RegionDecoder.current else { return }
            guard let decoded = try? decoder.decode(E.self, from: detail) else { return }
            action(decoded)
        }
        d.handlers[RegionWire.eventName] = handler
        return AnyRegionView(data: d)
    }

    @MainActor
    func onError(_ action: @escaping @MainActor (RegionError) -> Void) -> AnyRegionView {
        var d = data
        let handler = _registerAmbientHandler { info in
            guard let detail = info.detail, let decoder = RegionDecoder.current else { return }
            guard let decoded = try? decoder.decode(RegionError.self, from: detail) else { return }
            action(decoded)
        }
        d.handlers[RegionWire.errorName] = handler
        return AnyRegionView(data: d)
    }
}
