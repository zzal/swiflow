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
        //
        // NOTE: SwiftPM emits exactly ONE object-emitting (`-c`) driver swiftc
        // invocation per module regardless of source-file count (sources are
        // passed via an `@…/sources` response file + `-output-file-map`, not
        // inline / not `-primary-file`). Verified against the 8-file HelloWorld
        // example. So `compileCandidates.count == 1` is correct for multi-file
        // apps; ≥2 means genuine ambiguity → fall back to a full build.
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
                  argv[oIndex + 1].hasSuffix("/\(appModule).wasm")
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

/// The "is a replay still correct?" key. A replay is safe iff the frozen
/// swiftc/link argv is still the *correct* argv: file-body edits don't change
/// it (swiftc incremental + the stable LinkFileList cover those), but a
/// different source list, import surface, or manifest does. These four fields
/// detect exactly those. Compared in-process within one dev session only
/// (never persisted), so `importHash` may use a per-process hash.
struct StalenessKey: Sendable, Equatable {
    let sourceSet: Set<String>
    let importHash: Int
    let manifestMTime: Date?
    let resolvedMTime: Date?

    static func compute(appSourcesDir: URL, manifestURL: URL, resolvedURL: URL) -> StalenessKey {
        let fm = FileManager.default

        // Walk *.swift under the app sources (recursive).
        var paths: Set<String> = []
        var imports: Set<String> = []
        if let en = fm.enumerator(at: appSourcesDir, includingPropertiesForKeys: nil) {
            for case let url as URL in en where url.pathExtension == "swift" {
                paths.insert(url.standardizedFileURL.path)
                if let text = try? String(contentsOf: url, encoding: .utf8) {
                    for raw in text.split(separator: "\n") {
                        let line = raw.trimmingCharacters(in: .whitespaces)
                        // Catch `import X` and any attribute-prefixed form
                        // (@testable/@_exported/@preconcurrency/@_implementationOnly/@_spi(...) import X),
                        // while excluding comments and identifiers like `importer`.
                        // " import " (with surrounding spaces) only appears in real
                        // import declarations, not in `importer`/`canImport`.
                        let isImport = !line.hasPrefix("//") && !line.hasPrefix("/*")
                            && (line.hasPrefix("import ") || line.contains(" import "))
                        if isImport {
                            imports.insert(line)
                        }
                    }
                }
            }
        }
        let importHash = imports.sorted().joined(separator: "\n").hashValue

        return StalenessKey(
            sourceSet: paths,
            importHash: importHash,
            manifestMTime: Self.mtime(manifestURL, fm),
            resolvedMTime: Self.mtime(resolvedURL, fm)
        )
    }

    private static func mtime(_ url: URL, _ fm: FileManager) -> Date? {
        (try? fm.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }
}

/// The two replayable commands plus the staleness key they were captured under.
struct CapturedBuildCommands: Sendable, Equatable {
    let compile: ResolvedCommand
    let link: ResolvedCommand
    let key: StalenessKey
}

/// Runs the captured compile then link, streaming output to the user
/// (captureOutput: false). A non-zero exit throws `swiftBuildFailed` — for a
/// real compile error that surfaces the diagnostics and the dev loop skips the
/// HMR broadcast, exactly like today's failed rebuild. Stale-replay "no such
/// module" cases are prevented up front by StalenessKey's importHash, so we do
/// NOT auto-recapture on failure (that would make every mid-edit compile error
/// pay a ~12s rebuild — fast failure feedback is worth more).
enum CommandReplayer {
    static func replay(_ commands: CapturedBuildCommands, using runner: ProcessRunner, workingDirectory: URL) throws {
        for command in [commands.compile, commands.link] {
            let result = try runner.run(
                executable: command.executable,
                arguments: command.arguments,
                workingDirectory: workingDirectory,
                environment: nil,
                captureOutput: false
            )
            if result.exitCode != 0 {
                throw BuildCommandError.swiftBuildFailed(exitCode: result.exitCode)
            }
        }
    }
}

/// Loop-owned, single-task state. One value keeps the `rebuild` signature
/// stable as the staleness key grows.
struct BypassState: Sendable {
    var captured: CapturedBuildCommands?
    var bypassDisabled: Bool = false
}

/// Orchestrates one save: decide replay-vs-capture, run it, copy the fresh wasm
/// over the served output. Stays a Sendable value type; the non-Sendable
/// ProcessRunner and the mutable `state` are passed per call (the watcher loop
/// owns `state` and runs serially, so there's no cross-task sharing).
struct BypassRebuilder: Sendable {
    let capturingBuild: CapturingWasmBuildInvocation
    let fallback: RawWasmBuildInvocation
    let appModule: String
    let projectPath: URL
    let appSourcesDir: URL
    let manifestURL: URL
    let resolvedURL: URL
    let artifactURL: URL
    let outputWasmURL: URL

    func rebuild(using runner: ProcessRunner, state: inout BypassState) throws {
        // Permanent fallback once capture has proven unparseable this session.
        if state.bypassDisabled {
            try fallback.run(using: runner)
            try WasmArtifactCopier.copy(from: artifactURL, to: outputWasmURL)
            return
        }

        let key = StalenessKey.compute(appSourcesDir: appSourcesDir, manifestURL: manifestURL, resolvedURL: resolvedURL)

        if let captured = state.captured, captured.key == key {
            try CommandReplayer.replay(captured, using: runner, workingDirectory: projectPath)
        } else {
            print(captureReason(old: state.captured?.key, new: key))
            let output = try capturingBuild.run(using: runner)
            if let cmds = BuildCommandParser.parse(verboseOutput: output, appModule: appModule) {
                state.captured = CapturedBuildCommands(compile: cmds.compile, link: cmds.link, key: key)
            } else {
                state.bypassDisabled = true
                print("swiflow: could not capture compile commands; using full builds this session.")
            }
        }

        // Both branches wrote `artifactURL`; publish it to the served output.
        try WasmArtifactCopier.copy(from: artifactURL, to: outputWasmURL)
    }

    /// Human-readable reason for a (re)capture, for the dev console.
    private func captureReason(old: StalenessKey?, new: StalenessKey) -> String {
        guard let old else { return "swiflow: capturing compile commands (one-time)…" }
        if old.sourceSet != new.sourceSet { return "swiflow: app file set changed — re-capturing…" }
        if old.importHash != new.importHash { return "swiflow: imports changed — re-capturing…" }
        return "swiflow: Package.swift changed — re-capturing… (if you added/changed a dependency, restart swiflow dev)"
    }
}
