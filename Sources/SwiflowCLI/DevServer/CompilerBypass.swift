// Sources/SwiflowCLI/DevServer/CompilerBypass.swift
//
// Dev-only "compiler bypass" (Lever 2): on each save, replay SwiftPM's own
// swiftc + wasm-ld commands directly, skipping the ~9s SwiftPM orchestration
// overhead that `swift build` pays on every invocation. Commands are captured
// once from a verbose build and re-captured when the app's source/import set
// or the package manifest changes. See
// docs/superpowers/specs/2026-06-04-compiler-bypass-dev-loop-design.md.

import Foundation

/// One replayable command: an executable plus its full argv.
struct ResolvedCommand: Sendable, Equatable {
    let executable: URL
    let arguments: [String]
}

/// `swift build --swift-sdk <id> --product App -v` with output captured so the
/// emitted swiftc/wasm-ld lines can be parsed. Sibling of `RawWasmBuildInvocation`;
/// the name signals intent (capturing the commands is the purpose, `-v` the means).
struct CapturingWasmBuildInvocation: Sendable {
    let swiftExecutable: URL
    let projectPath: URL
    let swiftSDK: String
    let toolchainBundleID: String?

    func composeArguments() -> [String] {
        ["build", "--swift-sdk", swiftSDK, "--product", "App", "-v"]
    }

    /// Runs the build (which also produces the wasm) and returns the combined
    /// stdout+stderr — SwiftPM's verbose command lines can appear on either
    /// stream, and the version may vary, so we hand the parser both.
    func run(using runner: ProcessRunner) throws -> String {
        let environment: [String: String]? = toolchainBundleID.map { ["TOOLCHAINS": $0] }
        let result = try runner.run(
            executable: swiftExecutable,
            arguments: composeArguments(),
            workingDirectory: projectPath,
            environment: environment,
            captureOutput: true
        )
        if result.exitCode != 0 {
            throw BuildCommandError.swiftBuildFailed(exitCode: result.exitCode)
        }
        return (result.standardOutput ?? "") + "\n" + (result.standardError ?? "")
    }
}

/// Parses verbose `swift build --product App -v` output into the two commands
/// the bypass replays. Pure and table-free so it's fully unit-testable.
enum BuildCommandParser {

    /// Returns the (compile, link) commands, or nil if either anchor is absent
    /// or the compile job can't be uniquely identified — caller falls back to
    /// a full `swift build`.
    static func parse(verboseOutput: String, appModule: String) -> (compile: ResolvedCommand, link: ResolvedCommand)? {
        let lines = verboseOutput.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)

        // Compile: the swiftc line that compiles the app module's objects for
        // wasm. There can be a separate `-emit-module` job carrying the same
        // `-module-name App … wasm32`; we want the object-emitting (`-c`) one.
        let compileCandidates: [ResolvedCommand] = lines.compactMap { line in
            let argv = shellSplit(line)
            guard argv.first?.hasSuffix("swiftc") == true,
                  hasFlagValue(argv, "-module-name", appModule),
                  argv.contains(where: { $0.contains("wasm32") }),
                  argv.contains("-c")
            else { return nil }
            return ResolvedCommand(executable: URL(fileURLWithPath: argv[0]), arguments: Array(argv.dropFirst()))
        }
        guard compileCandidates.count == 1, let compile = compileCandidates.first else { return nil }

        // Link: the clang driver line whose `-o` output is `App.wasm`. The bare
        // nested `wasm-ld` line is clang's internal spawn — not what we replay.
        let linkCandidates: [ResolvedCommand] = lines.compactMap { line in
            let argv = shellSplit(line)
            guard argv.first?.hasSuffix("clang") == true,
                  let oIndex = argv.firstIndex(of: "-o"),
                  oIndex + 1 < argv.count,
                  argv[oIndex + 1].hasSuffix("/App.wasm")
            else { return nil }
            return ResolvedCommand(executable: URL(fileURLWithPath: argv[0]), arguments: Array(argv.dropFirst()))
        }
        guard linkCandidates.count == 1, let link = linkCandidates.first else { return nil }

        return (compile, link)
    }

    /// True iff `argv` contains `flag` immediately followed by `value`.
    private static func hasFlagValue(_ argv: [String], _ flag: String, _ value: String) -> Bool {
        guard let i = argv.firstIndex(of: flag), i + 1 < argv.count else { return false }
        return argv[i + 1] == value
    }

    /// Minimal shell tokenizer: splits on whitespace, honoring double- and
    /// single-quoted segments (quotes are stripped). Sufficient for the argv
    /// SwiftPM prints (quoted paths-with-spaces); no escape/var expansion.
    static func shellSplit(_ line: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var quote: Character? = nil
        var inToken = false
        for ch in line {
            if let q = quote {
                if ch == q { quote = nil } else { current.append(ch) }
            } else if ch == "\"" || ch == "'" {
                quote = ch; inToken = true
            } else if ch == " " || ch == "\t" {
                if inToken { tokens.append(current); current = ""; inToken = false }
            } else {
                current.append(ch); inToken = true
            }
        }
        if inToken { tokens.append(current) }
        return tokens
    }
}
