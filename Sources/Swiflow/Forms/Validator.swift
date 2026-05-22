public struct Validator<Value> {
    let validate: (Value) -> String?
}

extension Validator where Value == String {
    public static func required(message: String = "Required") -> Validator<String> {
        Validator { $0.isEmpty ? message : nil }
    }

    public static func minLength(_ n: Int, message: String? = nil) -> Validator<String> {
        Validator { v in
            v.count < n ? (message ?? "Must be at least \(n) characters") : nil
        }
    }

    public static func maxLength(_ n: Int, message: String? = nil) -> Validator<String> {
        Validator { v in
            v.count > n ? (message ?? "Must be at most \(n) characters") : nil
        }
    }

    public static var email: Validator<String> {
        Validator { v in
            v.wholeMatch(of: /^[^@\s]+@[^@\s]+\.[^@\s]+$/) == nil ? "Invalid email address" : nil
        }
    }

    public static func regex(_ pattern: some RegexComponent, message: String) -> Validator<String> {
        Validator { v in
            v.wholeMatch(of: pattern) == nil ? message : nil
        }
    }
}

extension Validator {
    public static func custom(_ message: String, _ check: @escaping (Value) -> Bool) -> Validator<Value> {
        Validator { v in check(v) ? nil : message }
    }
}
