// Sources/SwiflowCLI/DevServer/PortAvailability.swift
//
// EADDRINUSE (someone already on :3000, the most common first-run
// failure) previously surfaced as a raw NIO/SwiftNIO error out of
// `server.run()`. Rather than pattern-match on Hummingbird/NIO's
// internal bind-error type (awkward and liable to drift across NIO
// versions), DevCommand pre-flight-probes the configured port itself
// with a plain POSIX bind — same information, no dependency on NIO's
// error shape.

import Foundation
#if canImport(Glibc)
import Glibc
#else
import Darwin
#endif

enum PortAvailability {
    enum ProbeError: Error, Equatable, CustomStringConvertible {
        case inUse(Int)

        var description: String {
            switch self {
            case .inUse(let port):
                return "port \(port) is already in use — pass --port <n> to use a different one."
            }
        }
    }

    /// Binds a throwaway TCP socket to 127.0.0.1:`port` and immediately
    /// releases it. Throws `.inUse` if the bind fails with `EADDRINUSE`,
    /// so the dev server can fail fast with an actionable message instead
    /// of spending time on the initial build first. Non-EADDRINUSE bind
    /// failures (e.g. permission issues on low ports) and socket-creation
    /// failures are ignored here — those will surface naturally when the
    /// real server starts, and this probe's only job is the common case.
    static func checkAvailable(port: Int) throws {
        // Glibc's SOCK_STREAM is a __socket_type enum, Darwin's is Int32 —
        // the classic cross-platform socket portability seam.
        #if canImport(Glibc)
        let streamType = Int32(SOCK_STREAM.rawValue)
        #else
        let streamType = SOCK_STREAM
        #endif
        let fd = socket(AF_INET, streamType, 0)
        guard fd >= 0 else { return }
        defer { close(fd) }

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(truncatingIfNeeded: port).bigEndian
        addr.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

        let bindResult = withUnsafePointer(to: &addr) { ptr -> Int32 in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                bind(fd, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        if bindResult != 0, errno == EADDRINUSE {
            throw ProbeError.inUse(port)
        }
    }
}
