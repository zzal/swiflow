// Sources/SwiflowRouter/Core/PercentDecoding.swift

/// RFC 3986 percent-decoder for URL path segments and query keys/values.
///
/// Returns `nil` for any malformed `%XX` sequence or for byte sequences that do
/// not form valid UTF-8 — matches `String.removingPercentEncoding` semantics,
/// so callers' `?? original` fallback preserves prior behavior on invalid input.
///
/// `+` is left literal (RFC 3986 query semantics; WHATWG URLSearchParams maps
/// `+` to space — a separate choice, tracked by `queryPlusStaysLiteral`).
func percentDecode(_ s: String) -> String? {
    guard s.contains("%") else { return s }     // fast path
    var bytes: [UInt8] = []
    bytes.reserveCapacity(s.utf8.count)
    var it = s.utf8.makeIterator()
    while let b = it.next() {
        if b == 0x25 {  // '%'
            guard let h1 = it.next(), let h2 = it.next(),
                  let hi = hexDigit(h1), let lo = hexDigit(h2)
            else { return nil }
            bytes.append((hi << 4) | lo)
        } else {
            bytes.append(b)
        }
    }
    // Validate UTF-8 strictly: `String(validating:as:)` would do this
    // in one call, but it's gated on macOS 15+ and the package targets
    // macOS 14. `Unicode.UTF8.ForwardParser` is stdlib, has no platform
    // gate, and gives the same nil-on-invalid semantics.
    var validator = Unicode.UTF8.ForwardParser()
    var byteIter = bytes.makeIterator()
    while true {
        switch validator.parseScalar(from: &byteIter) {
        case .valid: continue
        case .emptyInput:
            return String(decoding: bytes, as: UTF8.self)
        case .error:
            return nil
        }
    }
}

/// ASCII hex-digit nibble. `nil` for any non-hex byte.
/// `&+` is overflow-trapping arithmetic disabled: the case ranges
/// pre-validate the inputs, so overflow is impossible by construction.
private func hexDigit(_ b: UInt8) -> UInt8? {
    switch b {
    case 0x30...0x39: return b - 0x30           // '0'-'9'
    case 0x41...0x46: return b - 0x41 &+ 10     // 'A'-'F'
    case 0x61...0x66: return b - 0x61 &+ 10     // 'a'-'f'
    default: return nil
    }
}
