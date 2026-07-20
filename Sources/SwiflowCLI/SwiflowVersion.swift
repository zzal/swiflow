// Sources/SwiflowCLI/SwiflowVersion.swift
//
// Single source of truth for the CLI's semantic version. Two consumers:
//   1. `Swiflow.configuration.version` — printed by `swiflow --version`.
//   2. `InitCommand`'s default `--swiflow-version` — when the user runs
//      `swiflow init` without flags, the generated `Package.swift` pins
//      to this exact tag on the official repo.
//
// Bump in lockstep with a GitHub release. The tag pushed for a release
// (e.g. `v0.1.3`) must match this string (without the `v` prefix).

enum SwiflowVersion {
    /// Current CLI semantic version. Matches the tag of the most recent
    /// GitHub release (or the upcoming one being prepared).
    static let current = "0.5.4"
}
