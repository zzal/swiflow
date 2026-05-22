package struct AnyInitialValue: @unchecked Sendable {
    package let isDirtyCheck: () -> Bool
    package let reset: () -> Void
}

public struct FormController: @unchecked Sendable {
    public internal(set) var touched: Set<String>
    package var initialSnapshots: [String: AnyInitialValue]

    public init() {
        touched = []
        initialSnapshots = [:]
    }
}
