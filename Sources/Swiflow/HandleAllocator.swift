// Sources/Swiflow/HandleAllocator.swift

/// Monotonically allocates integer node handles. Handles are never recycled
/// (see Swiflow refined spec § 4.3 — "Handle lifetime contract"). Swift `Int`
/// is 64-bit on every Swiflow target platform, so practical exhaustion is
/// ~292,000 years at one million allocations per second.
public final class HandleAllocator {
    private var counter: Int

    /// Creates an allocator that starts handing out handles at `start`
    /// (default `0`). Custom starts are useful in tests that need to assert
    /// patches against known handle values.
    public init(start: Int = 0) {
        self.counter = start
    }

    /// Returns the next handle, then increments.
    public func next() -> Int {
        defer { counter += 1 }
        return counter
    }
}
