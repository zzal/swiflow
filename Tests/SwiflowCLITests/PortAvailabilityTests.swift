// Tests/SwiflowCLITests/PortAvailabilityTests.swift
import Foundation
import Testing
@testable import SwiflowCLI

// Glibc's SOCK_STREAM is a __socket_type enum, Darwin's is Int32 (mirrors
// PortAvailability's own seam).
#if canImport(Glibc)
private let swiflowSockStream = Int32(SOCK_STREAM.rawValue)
#else
private let swiflowSockStream = SOCK_STREAM
#endif

#if canImport(Glibc)
import Glibc
#else
import Darwin
#endif

@Suite("PortAvailability")
struct PortAvailabilityTests {

    /// Binds and listens on an ephemeral port (port 0 lets the kernel pick
    /// one), returning the chosen port and the still-open fd so the caller
    /// can hold the port for the duration of the test.
    private static func occupyEphemeralPort() -> (port: Int, fd: Int32)? {
        let fd = socket(AF_INET, swiflowSockStream, 0)
        guard fd >= 0 else { return nil }

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = 0
        addr.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

        let bindResult = withUnsafePointer(to: &addr) { ptr -> Int32 in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                bind(fd, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0, listen(fd, 1) == 0 else {
            close(fd)
            return nil
        }

        var actual = sockaddr_in()
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        let ok = withUnsafeMutablePointer(to: &actual) { ptr -> Int32 in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                getsockname(fd, sockaddrPtr, &len)
            }
        }
        guard ok == 0 else {
            close(fd)
            return nil
        }
        return (Int(UInt16(bigEndian: actual.sin_port)), fd)
    }

    @Test("checkAvailable throws .inUse when the port is already bound")
    func detectsPortInUse() throws {
        guard let occupied = Self.occupyEphemeralPort() else {
            Issue.record("could not occupy an ephemeral port to set up the test")
            return
        }
        defer { close(occupied.fd) }

        #expect(throws: PortAvailability.ProbeError.inUse(occupied.port)) {
            try PortAvailability.checkAvailable(port: occupied.port)
        }
    }

    @Test("checkAvailable succeeds for a free port")
    func succeedsForFreePort() throws {
        // Bind port 0 to get a genuinely free port, then release it — a
        // small TOCTOU window exists but is fine for this smoke test.
        guard let probe = Self.occupyEphemeralPort() else {
            Issue.record("could not find a free ephemeral port to set up the test")
            return
        }
        close(probe.fd)

        try PortAvailability.checkAvailable(port: probe.port)
    }

    @Test("ProbeError.inUse has an actionable description")
    func inUseDescription() {
        let error = PortAvailability.ProbeError.inUse(3000)
        let desc = String(describing: error)
        #expect(desc.contains("3000"))
        #expect(desc.contains("--port"))
    }
}
