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
        let allPresent = applicable.allSatisfy {
            if case .missing = $0 { return false }
            return true
        }
        return allPresent ? 0 : 1
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
            return "  ✗ \(name)\n      \(hint)"
        }
    }
}

// MARK: - DoctorCommand

struct DoctorCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "doctor",
        abstract: "Check that the toolchain pieces Swiflow needs are installed."
    )

    func run() async throws {
        let report = DoctorReport(
            swift: probeSwift(),
            wasmSDK: probeWasmSDK(),
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

    private func probeWasmSDK() -> ToolStatus {
        guard let out = try? captureOutput("swift", ["sdk", "list"]) else { return .missing }
        guard let line = out.split(separator: "\n").first(where: { $0.contains("wasm") }) else {
            return .missing
        }
        return .found(String(line).trimmingCharacters(in: .whitespaces))
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
