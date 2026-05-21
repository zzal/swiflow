import Swiflow

/// The runtime context injected into route factory closures.
/// Carries the matched path, extracted `:param` captures, and
/// parsed `?key=value` query parameters.
public struct RouterContext: Sendable {
    public let path: String
    public let params: [String: String]
    public let query: [String: String]

    public init(
        path: String,
        params: [String: String] = [:],
        query: [String: String] = [:]
    ) {
        self.path = path
        self.params = params
        self.query = query
    }
}
