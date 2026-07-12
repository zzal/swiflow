// Sources/SwiflowUI/Slider.swift
import Swiflow

/// A labelled, token-styled range slider: a native `<input type="range">` plus
/// the same label/error chrome as `TextField`/`NumberField`, over a
/// `Binding<Double>`. `min`/`max` come from `range` (default `0...1`) and
/// `step` is omitted entirely when `nil`, leaving the browser's native
/// stepping un-opinionated. There's no `required:` (a range input always has
/// a value) and no `Field`-integrated overload, mirroring `NumberField`.
///
///     Slider("Volume", value: $volume)
///     Slider("Rating", value: $rating, in: 0...10, step: 1)
@MainActor
public func Slider(
    _ label: String,
    value: Binding<Double>,
    in range: ClosedRange<Double> = 0...1,
    step: Double? = nil,
    error: String? = nil,
    size: ControlSize = .md,
    disabled: Bool = false,
    _ attributes: Attribute...,
    onBlur: (@MainActor () -> Void)? = nil
) -> VNode {
    ensureBaseStyles()
    installFieldStyles()

    var base: [Attribute] = [
        .attr("type", "range"),
        .attr("min", formatControlNumber(range.lowerBound)),
        .attr("max", formatControlNumber(range.upperBound)),
        .value(value),
    ]
    if let step { base.append(.attr("step", formatControlNumber(step))) }
    let inputAttrs = controlInputAttributes(base, error: error, required: false,
                                            disabled: disabled, onBlur: onBlur, caller: attributes)

    var rootChildren: [VNode] = [
        element("label", attributes: [.class("sw-field__label")], children: [
            element("span", attributes: [.class("sw-field__label-text")], children: [text(label)]),
            element("input", attributes: inputAttrs),
        ]),
    ]
    if let errorNode = fieldErrorNode(error) { rootChildren.append(errorNode) }
    return element("div", attributes: [.class("sw-field sw-field--\(size.modifierClass)")],
                   children: rootChildren)
}
