// Sources/SwiflowCLI/Commands/DoctorCommand.swift
//
// `swiflow doctor` — standalone toolchain audit. Checks that every tool
// Swiflow needs is on PATH and prints install hints for anything missing.
// Exits non-zero when any tool is absent. Does NOT preflight build or dev;
// those commands continue to check their own requirements at invocation time.

import Foundation
import ArgumentParser

// MARK: - ToolStatus

internal enum ToolStatus {
    case found(String)  // detail: version string or identifier; opaque to callers
    case missing
    /// Present on disk but unusable as-is — e.g. a WASM SDK whose version
    /// doesn't match the compiler (the `.swiftmodule` ABI is patch-strict, so
    /// a 6.3 SDK can't be imported by a 6.3.2 compiler). `detail` says what's
    /// wrong; `hint` is the remediation. Counts as a failure, like `.missing`.
    case incompatible(detail: String, hint: String)
}

// MARK: - DoctorReport

struct DoctorReport {
    let swift: ToolStatus
    let wasmSDK: ToolStatus
    /// nil = not applicable on this OS (Linux builds don't need the
    /// swift.org macOS toolchain workaround).
    let macToolchain: ToolStatus?
    let wasmOpt: ToolStatus

    private var applicable: [ToolStatus] {
        [swift, wasmSDK, wasmOpt] + (macToolchain.map { [$0] } ?? [])
    }

    var exitCode: Int32 {
        // Only a clean `.found` passes; both `.missing` and `.incompatible`
        // are failures the user must act on before `swiflow dev`/`build` works.
        let allOK = applicable.allSatisfy {
            if case .found = $0 { return true }
            return false
        }
        return allOK ? 0 : 1
    }

    var summary: String {
        var lines: [String] = ["swiflow doctor", ""]
        lines.append(row(name: "swift", status: swift,
                         hint: "Install Swift 6.3 from https://swift.org/install/"))
        lines.append(row(name: "wasm-sdk", status: wasmSDK,
                         hint: "Install the WebAssembly Swift SDK 6.3. See README.md → Prerequisites for the current `swift sdk install …` command (the checksum changes per release)."))
        if let macToolchain {
            lines.append(row(name: "mac-toolchain", status: macToolchain,
                             hint: "Install the swift.org toolchain (https://swift.org/install/) — Xcode's default clang has no WASM backend, so `swiflow build` fails with \"No available targets are compatible with triple 'wasm32-unknown-wasip1'\" without it."))
        }
        lines.append(row(name: "wasm-opt", status: wasmOpt,
                         hint: "Install binaryen (`brew install binaryen`) — the PackageToJS plugin invokes wasm-opt for release builds."))
        lines.append("")
        if exitCode == 0 {
            lines.append("All checks passed.")
        } else {
            lines.append("Some checks failed. Install the missing tools above and run `swiflow doctor` again.")
        }
        return lines.joined(separator: "\n")
    }

    private func row(name: String, status: ToolStatus, hint: String) -> String {
        switch status {
        case .found(let detail):
            return "  ✓ \(name)  (\(detail))"
        case .missing:
            return "  ✗ \(name)\n\(Self.indent(hint))"
        case .incompatible(let detail, let incompatibleHint):
            // The carried hint wins over the call-site one — it's computed from
            // the actual mismatch (which SDK, which compiler).
            return "  ✗ \(name)  (\(detail))\n\(Self.indent(incompatibleHint))"
        }
    }

    /// Indent every line of a (possibly multi-line) hint block so it nests
    /// cleanly under its `✗` row.
    private static func indent(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { "      \($0)" }
            .joined(separator: "\n")
    }
}

// MARK: - DoctorCommand

struct DoctorCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "doctor",
        abstract: "Check that the toolchain pieces Swiflow needs are installed."
    )

    func run() async throws {
        let swift = probeSwift()
        // The compiler version gates the wasm-sdk version check below; if swift
        // itself is missing, the SDK row falls back to a presence-only check.
        let compilerVersion: String? = {
            if case .found(let line) = swift {
                return ToolchainVersion.compilerVersion(fromVersionLine: line)
            }
            return nil
        }()
        let report = DoctorReport(
            swift: swift,
            wasmSDK: probeWasmSDK(compilerVersion: compilerVersion),
            macToolchain: probeMacToolchain(),
            wasmOpt: probeWasmOpt()
        )
        print(report.summary)
        if report.exitCode != 0 {
            throw ExitCode(report.exitCode)
        }
    }

    /// macOS only: `swiflow build` needs the swift.org toolchain's clang for
    /// the wasm triple (see MacToolchainProbe's header comment). On Linux
    /// the row is not applicable.
    private func probeMacToolchain() -> ToolStatus? {
        #if os(macOS)
        if let bundleID = MacToolchainProbe.swiftLatestBundleIdentifier() {
            return .found(bundleID)
        }
        return .missing
        #else
        return nil
        #endif
    }

    private func probeWasmOpt() -> ToolStatus {
        guard let out = try? captureOutput("wasm-opt", ["--version"]) else { return .missing }
        let firstLine = out.split(separator: "\n").first.map(String.init) ?? ""
        return .found(firstLine)
    }

    private func probeSwift() -> ToolStatus {
        guard let out = try? captureOutput("swift", ["--version"]) else { return .missing }
        let firstLine = out.split(separator: "\n").first.map(String.init) ?? ""
        return .found(firstLine)
    }

    /// Lists installed WASM SDKs and, when the compiler version is known,
    /// requires one whose version matches it exactly. A version mismatch is the
    /// silent failure this hardening targets: `swift sdk list` is happy, but
    /// `swiflow dev` later dies with "module compiled with Swift X cannot be
    /// imported by the Swift Y compiler".
    private func probeWasmSDK(compilerVersion: String?) -> ToolStatus {
        guard let out = try? captureOutput("swift", ["sdk", "list"]) else { return .missing }
        let wasmIDs = out
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.contains("wasm") }
        guard !wasmIDs.isEmpty else { return .missing }

        // No parseable compiler version (swift missing/odd output): fall back to
        // the old presence-only behaviour rather than guess.
        guard let compilerVersion else { return .found(wasmIDs[0]) }

        // Prefer an SDK whose version matches the compiler exactly.
        if let match = wasmIDs.first(where: {
            guard let v = ToolchainVersion.sdkVersion(fromID: $0) else { return false }
            return ToolchainVersion.versionsMatch(compilerVersion, v)
        }) {
            return .found(match)
        }

        // SDKs are installed but none match — the mismatch case.
        let stale = wasmIDs[0]
        let staleVersion = ToolchainVersion.sdkVersion(fromID: stale)
        let detail = staleVersion.map {
            "\(stale) is built for Swift \($0), but your compiler is \(compilerVersion)"
        } ?? "installed (\(wasmIDs.joined(separator: ", "))) but none match compiler \(compilerVersion)"
        let hint = """
            The WASM SDK must match your compiler exactly. Reinstall the matching one:
              swift sdk remove \(stale)
              swift sdk install \\
                https://download.swift.org/swift-\(compilerVersion)-release/wasm-sdk/swift-\(compilerVersion)-RELEASE/swift-\(compilerVersion)-RELEASE_wasm.artifactbundle.tar.gz \\
                --checksum <see swift.org download page / README.md → Quick start>
            """
        return .incompatible(detail: detail, hint: hint)
    }

    private func captureOutput(_ executable: String, _ args: [String]) throws -> String {
        let proc = Process()
        proc.launchPath = "/usr/bin/env"
        proc.arguments = [executable] + args
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle(forWritingAtPath: "/dev/null")  // discard stderr without buffering
        try proc.run()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else {
            throw NSError(domain: "DoctorCommand", code: Int(proc.terminationStatus))
        }
        return String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    }
}

// MARK: - ToolchainVersion

/// Pure version parsing/matching for the wasm-sdk ↔ compiler check. Kept
/// `internal` and side-effect-free so the parsing rules are unit-tested
/// directly, without shelling out to a real toolchain.
internal enum ToolchainVersion {
    /// Extracts the version from a `swift --version` first line, e.g.
    /// "Apple Swift version 6.3.2 (…)" or Linux's "Swift version 6.3.2 (…)"
    /// → "6.3.2". Returns nil if no "swift version <semver>" is found.
    static func compilerVersion(fromVersionLine line: String) -> String? {
        semver(after: "swift version ", in: line)
    }

    /// Extracts the version embedded in a WASM SDK identifier, e.g.
    /// "swift-6.3.2-RELEASE_wasm" → "6.3.2", "swift-6.3-RELEASE_wasm" → "6.3".
    /// Development snapshots ("swift-DEVELOPMENT-SNAPSHOT-…_wasm") have no
    /// semver → nil, which callers treat as "can't compare, don't flag".
    static func sdkVersion(fromID id: String) -> String? {
        semver(after: "swift-", in: id)
    }

    /// Patch-level equality with zero-padding, so "6.3" == "6.3.0" but
    /// "6.3" != "6.3.2". The `.swiftmodule` ABI is strict to the patch, which
    /// is exactly the mismatch this guards against.
    static func versionsMatch(_ a: String, _ b: String) -> Bool {
        normalized(a) == normalized(b)
    }

    private static func normalized(_ v: String) -> [Int] {
        var parts = v.split(separator: ".").map { Int($0) ?? 0 }
        while parts.count < 3 { parts.append(0) }
        return Array(parts.prefix(3))
    }

    /// Returns the first `[0-9.]+` run immediately following `marker`
    /// (case-insensitive), trimmed of stray dots. nil if the marker is absent
    /// or isn't followed by a digit.
    private static func semver(after marker: String, in text: String) -> String? {
        guard let r = text.range(of: marker, options: .caseInsensitive) else { return nil }
        let token = text[r.upperBound...].prefix { $0.isNumber || $0 == "." }
        let trimmed = token.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return trimmed.isEmpty ? nil : trimmed
    }
}
