// Sources/SwiflowCLI/Toolchain/MacToolchainProbe.swift
//
// On macOS, the Xcode-default `swift` invokes the system clang, which has
// no WASM backend. PackageToJS then fails with "No available targets are
// compatible with triple 'wasm32-unknown-wasip1'". The workaround is to
// set TOOLCHAINS=<bundle-id-of-swift-org-toolchain> so the SwiftPM driver
// finds a clang that knows about WASM.
//
// This probe extracts that bundle ID from the standard install location
// at ~/Library/Developer/Toolchains/swift-latest.xctoolchain. We do NOT
// mutate the parent process's environment — BuildCommand merges the value
// into the child Process's environment dictionary only.

import Foundation

enum MacToolchainProbe {

    /// Standard install path for the swift.org toolchain on macOS.
    static var swiftLatestInfoPlist: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home
            .appendingPathComponent("Library/Developer/Toolchains/swift-latest.xctoolchain/Info.plist")
    }

    /// Convenience: returns the bundle ID for swift-latest, or nil if not
    /// installed / not on macOS (since the path won't exist on Linux).
    static func swiftLatestBundleIdentifier() -> String? {
        return bundleIdentifier(atInfoPlist: swiftLatestInfoPlist)
    }

    /// Reads `CFBundleIdentifier` from the plist at the given URL.
    /// Returns nil if the file doesn't exist, isn't a valid plist, or
    /// doesn't contain the key.
    static func bundleIdentifier(atInfoPlist url: URL) -> String? {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }
        let plist: Any
        do {
            plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        } catch {
            return nil
        }
        guard let dict = plist as? [String: Any],
              let bundleID = dict["CFBundleIdentifier"] as? String else {
            return nil
        }
        return bundleID
    }
}
