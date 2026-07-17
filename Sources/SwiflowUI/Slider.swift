// Sources/SwiflowUI/Slider.swift
import Swiflow

/// A labelled, token-styled range slider: a native `<input type="range">` plus
/// the same label/error chrome as `TextField`/`NumberField`, over a
/// `Binding<Double>`. `min`/`max` come from `range` (default `0...1`) and
/// `step: nil` (the default) emits `step="any"` — a continuous slider. It must
/// NOT be omitted: a range input's implicit default step is 1, and range inputs
/// SANITIZE their value to the step, so an unstepped `0...1` slider would snap a
/// bound 0.5 to 1 in the DOM while the binding (and the drawn fill) stayed 0.5 —
/// rail at 50%, knob at the end. There's no `required:` (a range input always
/// has a value) and no `Field`-integrated overload, mirroring `NumberField`.
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
    layout: FieldLayout = .vertical,
    labelPrefix: VNode? = nil,
    labelSuffix: VNode? = nil,
    _ attributes: Attribute...,
    onBlur: (@MainActor () -> Void)? = nil
) -> VNode {
    var base: [Attribute] = [
        .attr("type", "range"),
        .attr("min", formatControlNumber(range.lowerBound)),
        .attr("max", formatControlNumber(range.upperBound)),
        .value(value),
    ]
    // step="any" when unspecified — never omit (see the doc comment: the implicit
    // default step of 1 makes the browser SNAP the value, desyncing knob from fill).
    base.append(.attr("step", step.map(formatControlNumber) ?? "any"))

    // Fill fraction for the drawn track (see the range rules in FieldChrome): the
    // webkit track paints its accent fill at this width. Re-computed every render —
    // the .value binding fires per input event, so it tracks the drag live. Clamped
    // (a bound value outside the range shouldn't paint outside the track); a
    // degenerate range (lower == upper) pins the fill to 0.
    let span = range.upperBound - range.lowerBound
    let fraction = span > 0 ? min(max((value.get() - range.lowerBound) / span, 0), 1) : 0
    let fillPercent = "\(formatControlNumber((fraction * 1000).rounded() / 10))%"

    return fieldChromeLowering(label: label, layout: layout, error: error, size: size,
                               required: false, disabled: disabled,
                               labelPrefix: labelPrefix, labelSuffix: labelSuffix,
                               base: base, caller: attributes, onBlur: onBlur,
                               makeControl: { element("input", attributes: $0).style("--sw-slider-fill", fillPercent) })
}
