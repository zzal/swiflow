// Sources/SwiflowUI/NumberField.swift
import Swiflow

/// A labelled, token-styled numeric field: a native `<input type="number">`
/// plus the same label/error chrome as `TextField`, over a `Binding<Double>`
/// or `Binding<Int>`. `min`/`max`/`step` lower to the matching HTML attributes
/// (formatted — a `Double` that's a whole number, like `0`, emits `"0"` not
/// `"0.0"`) and are omitted entirely when `nil`, so the browser's native
/// number-input behavior (spinners, range clamping) stays un-opinionated by
/// default. As with `TextField`'s `.value`, a failed parse of the user's typed
/// text leaves the binding unchanged — the malformed text stays in the DOM
/// until they fix it. There's no `Field`-integrated overload: `Field`'s
/// validators are string-typed today, so a numeric `Field` has no natural
/// home here yet — drive validation by hand until that lands.
///
///     NumberField("Quantity", value: $quantity, min: 0, max: 10, step: 0.5)
///     NumberField("Age", value: $age, min: 0, max: 120)
@MainActor
public func NumberField(
    _ label: String,
    value: Binding<Double>,
    min: Double? = nil,
    max: Double? = nil,
    step: Double? = nil,
    placeholder: String = "",
    error: String? = nil,
    size: ControlSize = .md,
    required: Bool = false,
    disabled: Bool = false,
    layout: FieldLayout = .vertical,
    labelPrefix: VNode? = nil,
    labelSuffix: VNode? = nil,
    _ attributes: Attribute...,
    onBlur: (@MainActor () -> Void)? = nil
) -> VNode {
    numberFieldControl(label: label, valueAttribute: .value(value),
                       min: min.map(formatControlNumber), max: max.map(formatControlNumber), step: step.map(formatControlNumber),
                       placeholder: placeholder, error: error, size: size, required: required,
                       disabled: disabled, layout: layout, labelPrefix: labelPrefix, labelSuffix: labelSuffix,
                       attributes: attributes, onBlur: onBlur)
}

/// `Int`-valued overload, mirroring the `Double` one above.
///
///     NumberField("Age", value: $age, min: 0, max: 120, step: 1)
@MainActor
public func NumberField(
    _ label: String,
    value: Binding<Int>,
    min: Int? = nil,
    max: Int? = nil,
    step: Int? = nil,
    placeholder: String = "",
    error: String? = nil,
    size: ControlSize = .md,
    required: Bool = false,
    disabled: Bool = false,
    layout: FieldLayout = .vertical,
    labelPrefix: VNode? = nil,
    labelSuffix: VNode? = nil,
    _ attributes: Attribute...,
    onBlur: (@MainActor () -> Void)? = nil
) -> VNode {
    numberFieldControl(label: label, valueAttribute: .value(value),
                       min: min.map(String.init), max: max.map(String.init), step: step.map(String.init),
                       placeholder: placeholder, error: error, size: size, required: required,
                       disabled: disabled, layout: layout, labelPrefix: labelPrefix, labelSuffix: labelSuffix,
                       attributes: attributes, onBlur: onBlur)
}

/// Shared field-chrome lowering for both overloads: takes the pre-built
/// `.value` attribute and pre-formatted `min`/`max`/`step` strings so the two
/// public entry points stay thin without a generic core.
@MainActor
private func numberFieldControl(
    label labelText: String,
    valueAttribute: Attribute,
    min: String?,
    max: String?,
    step: String?,
    placeholder: String,
    error: String?,
    size: ControlSize,
    required: Bool,
    disabled: Bool,
    layout: FieldLayout,
    labelPrefix: VNode?,
    labelSuffix: VNode?,
    attributes: [Attribute],
    onBlur: (@MainActor () -> Void)?
) -> VNode {
    var base: [Attribute] = [.attr("type", "number"), valueAttribute]
    if let min { base.append(.attr("min", min)) }
    if let max { base.append(.attr("max", max)) }
    if let step { base.append(.attr("step", step)) }
    if !placeholder.isEmpty { base.append(.placeholder(placeholder)) }
    return fieldChromeLowering(label: labelText, layout: layout, error: error, size: size,
                               required: required, disabled: disabled,
                               labelPrefix: labelPrefix, labelSuffix: labelSuffix,
                               base: base, caller: attributes, onBlur: onBlur,
                               makeControl: { element("input", attributes: $0) })
}
