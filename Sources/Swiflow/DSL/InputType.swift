// Sources/Swiflow/DSL/InputType.swift

/// Typed values for the `<input>` `type` attribute, used with the `.type(_:)`
/// attribute helper — `input(.type(.email))` instead of the typo-prone
/// `.attr("type", "email")`. `.custom(_:)` is the escape hatch for a type not
/// enumerated here.
public enum InputType: Equatable {
    case text
    case search
    case tel
    case url
    case email
    case password
    case number
    case range
    case color
    case checkbox
    case radio
    case file
    case hidden
    case date
    case time
    /// Renders as `datetime-local`.
    case datetimeLocal
    case month
    case week
    case submit
    case reset
    case button
    /// Any `type` value not covered above (e.g. `"image"`), passed through verbatim.
    case custom(String)

    /// The HTML `type` attribute string.
    public var htmlValue: String {
        switch self {
        case .text:          return "text"
        case .search:        return "search"
        case .tel:           return "tel"
        case .url:           return "url"
        case .email:         return "email"
        case .password:      return "password"
        case .number:        return "number"
        case .range:         return "range"
        case .color:         return "color"
        case .checkbox:      return "checkbox"
        case .radio:         return "radio"
        case .file:          return "file"
        case .hidden:        return "hidden"
        case .date:          return "date"
        case .time:          return "time"
        case .datetimeLocal: return "datetime-local"
        case .month:         return "month"
        case .week:          return "week"
        case .submit:        return "submit"
        case .reset:         return "reset"
        case .button:        return "button"
        case .custom(let value): return value
        }
    }
}
