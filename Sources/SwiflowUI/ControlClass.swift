// Sources/SwiflowUI/ControlClass.swift
import Swiflow

/// Splits caller-supplied attributes into (their `class` values, everything
/// else) so a skinned control can MERGE its own classes with the caller's
/// rather than be clobbered.
///
/// `applyAttributes` is last-write-wins per attribute key, so a caller
/// `.class("mine")` would otherwise wipe a control's `sw-btn …` skin classes.
/// Skinned controls call this, prepend their own classes to `classes`, and apply
/// `rest` last so the caller still wins on every *other* attribute (e.g.
/// overriding `type`). Shared by all skinned controls (Button, and the M4 form
/// controls).
func splitClasses(_ attributes: [Attribute]) -> (classes: [String], rest: [Attribute]) {
    var classes: [String] = []
    var rest: [Attribute] = []
    for attribute in attributes {
        if case let .attribute(name, value) = attribute, name == "class" {
            classes.append(value)
        } else {
            rest.append(attribute)
        }
    }
    return (classes, rest)
}
