
// MARK: - Seeded Random (STDLIB-516)
//
// KSP-466: kotlin.random.Random itself is now implemented in Kotlin source
// (Sources/CompilerCore/Stdlib/kotlin/random/Random.kt) with real x/y/z/w/v/addend
// fields and the actual XorWow algorithm, so kotlin.random.Random(seed) no longer
// constructs this box, and neither does java.util.Random(seed) (it now wraps a
// real kotlin.random.Random — see Sources/CompilerCore/Stdlib/kotlin/random/
// JavaUtilRandom.kt). This box survives only as SecureRandom's internal
// deterministic-mode PRNG (STDLIB-101 below, still native, KSP-467 scope).

/// A deterministic PRNG using the xorshift64* algorithm.
/// Each `Random(seed)` call creates a new instance whose state evolves
/// independently so that two instances with the same seed produce identical
/// sequences.
final class SeededRandomBox {
    /// Internal PRNG state (xorshift64*).
    var state: UInt64

    init(seed: Int) {
        // Kotlin's Random(seed) internally mixes the seed.  We use the same
        // initial-state derivation so that behaviour is deterministic and
        // consistent across runs.  A seed of 0 would stall xorshift, so we
        // mix it first.
        var s = UInt64(bitPattern: Int64(seed))
        // Murmur-style finaliser to spread bits.
        s = s &+ 0x9E3779B97F4A7C15
        s = (s ^ (s >> 30)) &* 0xBF58476D1CE4E5B9
        s = (s ^ (s >> 27)) &* 0x94D049BB133111EB
        s = s ^ (s >> 31)
        if s == 0 { s = 1 }          // xorshift must never be 0
        self.state = s
    }

    /// Returns the next pseudo-random UInt64.
    func nextBits() -> UInt64 {
        var s = state
        s ^= s >> 12
        s ^= s << 25
        s ^= s >> 27
        state = s
        return s &* 0x2545F4914F6CDD1D
    }

    /// Returns a random Int in [0, bound).
    func nextInt(bound: Int) -> Int {
        precondition(bound > 0)
        let b = UInt64(bound)
        return Int(nextBits() % b)
    }

    /// Returns a random Int in [from, until).
    func nextIntRange(from: Int, until: Int) -> Int {
        precondition(until > from)
        let range = UInt64(bitPattern: Int64(until) &- Int64(from))
        return from &+ Int(Int64(bitPattern: nextBits() % range))
    }

    /// Returns a random Int (full range).
    func nextFullInt() -> Int {
        Int(bitPattern: UInt(truncatingIfNeeded: nextBits()))
    }

    /// Returns a random Double in [0.0, 1.0).
    func nextDouble() -> Double {
        // Use 53 bits of randomness (IEEE-754 double significand width).
        let bits = nextBits() >> 11
        return Double(bits) / Double(1 << 53)
    }

    /// Returns a random Float in [0.0, 1.0).
    func nextFloat() -> Float {
        let bits = nextBits() >> 40
        return Float(bits) / Float(1 << 24)
    }

    /// Returns a random Bool.
    func nextBoolean() -> Bool {
        (nextBits() & 1) != 0
    }

}

// MARK: - SecureRandom (STDLIB-101)

final class SecureRandomBox {
    private var seeded: SeededRandomBox?

    func setSeed(_ seed: Int) {
        seeded = SeededRandomBox(seed: seed)
    }

    private func nextBits() -> UInt64 {
        if let seeded {
            return seeded.nextBits()
        }
        var rng = SystemRandomNumberGenerator()
        return rng.next()
    }

    func nextByte() -> Int {
        Int(Int8(truncatingIfNeeded: nextBits()))
    }
}

private func secureRandomBox(from raw: Int) -> SecureRandomBox? {
    guard raw != 0, let ptr = UnsafeMutableRawPointer(bitPattern: raw) else {
        return nil
    }
    let isObjectPointer = runtimeStorage.withGCLock { state in
        state.objectPointers.contains(UInt(bitPattern: ptr))
    }
    guard isObjectPointer else {
        return nil
    }
    return Unmanaged<SecureRandomBox>.fromOpaque(ptr).takeUnretainedValue()
}

// MARK: - SecureRandom Constructor / Factory

@_cdecl("__kk_secure_random_get_instance")
public func __kk_secure_random_get_instance() -> Int {
    let box = SecureRandomBox()
    let ptr = UnsafeMutableRawPointer(Unmanaged.passRetained(box).toOpaque())
    runtimeStorage.withGCLock { state in
        state.objectPointers.insert(UInt(bitPattern: ptr))
    }
    return Int(bitPattern: ptr)
}

@_cdecl("__kk_secure_random_set_seed")
public func __kk_secure_random_set_seed(_ receiver: Int, _ seed: Int) -> Int {
    guard let box = secureRandomBox(from: receiver) else {
        return receiver
    }
    box.setSeed(seed)
    return receiver
}

@_cdecl("__kk_secure_random_generate_seed")
public func __kk_secure_random_generate_seed(_ receiver: Int, _ size: Int) -> Int {
    // ByteArray.size (kk_byteArray_size) reads a RuntimeArrayBox, not a
    // RuntimeListBox, so the result must be constructed as one to match the
    // kotlin.ByteArray return type registered in HeaderHelpers+SyntheticRandomStubs.swift.
    let result = RuntimeArrayBox(length: max(0, size))
    guard let box = secureRandomBox(from: receiver), size > 0 else {
        return registerRuntimeObject(result)
    }
    var bytes: [Int] = []
    bytes.reserveCapacity(size)
    for _ in 0 ..< size {
        bytes.append(box.nextByte())
    }
    result.elements = bytes
    return registerRuntimeObject(result)
}

@_cdecl("__kk_secure_random_next_bytes")
public func __kk_secure_random_next_bytes(_ receiver: Int, _ arrayRaw: Int) -> Int {
    // Fills the caller's ByteArray (a RuntimeArrayBox, see kk_secure_random_generate_seed)
    // in place and returns the same reference, matching java.security.SecureRandom's
    // nextBytes(bytes: ByteArray): ByteArray contract.
    guard let box = secureRandomBox(from: receiver),
          let array = runtimeArrayBox(from: arrayRaw) else {
        return registerRuntimeObject(RuntimeArrayBox(length: 0))
    }
    for index in array.elements.indices {
        array.elements[index] = box.nextByte()
    }
    return arrayRaw
}

// MARK: - nextUInt(range: UIntRange) / nextULong(range: ULongRange) — KSP-457 scope
//
// Symmetric with kk_random_nextInt_rangeObject/kk_random_nextLong_rangeObject
// (RuntimeRangeIntRangeHOF.swift / RuntimeRangeLongRange.swift): range-typed
// nextUInt/nextULong overloads stay native pending KSP-457's own range-random
// Kotlin migration. The receiver is always a real compiled Kotlin Random object
// now (see the "Legacy Random-receiver bridging" note below), so its seeded
// state can't safely be read here — these produce a uniformly random value
// within the given range without consulting the receiver.

@_cdecl("kk_random_nextUInt_uintRange")
public func kk_random_nextUInt_uintRange(_ receiver: Int, _ rangeRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IllegalArgumentException: Random.nextUInt expected a UIntRange.")
        return 0
    }
    let first = UInt32(truncatingIfNeeded: UInt(bitPattern: range.first))
    let last = UInt32(truncatingIfNeeded: UInt(bitPattern: range.last))
    guard range.step != 0, first <= last else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "NoSuchElementException: Range is empty.")
        return Int(first)
    }
    return Int(UInt32.random(in: first ... last))
}

@_cdecl("kk_random_nextULong_ulongRange")
public func kk_random_nextULong_ulongRange(_ receiver: Int, _ rangeRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IllegalArgumentException: Random range is empty.")
        return 0
    }
    let first = UInt64(UInt(bitPattern: range.first))
    let last = UInt64(UInt(bitPattern: range.last))
    guard last >= first else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IllegalArgumentException: Random range is empty: \(first)..\(last).")
        return 0
    }
    return Int(bitPattern: UInt(truncatingIfNeeded: UInt64.random(in: first ... last)))
}

// MARK: - Random.Default seed entropy (KSP-466)
//
// The only bridge kotlin.random.Random's Kotlin implementation needs: a source
// of non-deterministic entropy to seed the lazily-constructed Random.Default
// instance. Everything else (state, algorithm, derived nextX() methods) is
// pure Kotlin.

@_cdecl("__kk_random_seed_entropy")
public func __kk_random_seed_entropy() -> Int {
    var rng = SystemRandomNumberGenerator()
    return Int(bitPattern: UInt(truncatingIfNeeded: rng.next() as UInt64))
}

// MARK: - Legacy Random-receiver bridging (KSP-466)
//
// Sequence.shuffled(random)/List.shuffled(random)/String.random(random)/
// Range.random(random) are native Swift entry points that only ever hold an
// opaque `Random`-typed receiver handle passed in from already-compiled
// Kotlin code — they never construct a Random themselves. Now that
// Random(seed) constructs a genuine compiled Kotlin object (real x/y/z/w/v/
// addend fields, see Sources/CompilerCore/Stdlib/kotlin/random/Random.kt)
// rather than the SeededRandomBox above, these call sites can no longer
// reinterpret the handle as a SeededRandomBox — that would misread a
// compiled Kotlin object's memory as a different Swift class's layout.
//
// A `kk_vtable_lookup`-based dispatch to the receiver's `nextBits(bitCount)`
// was attempted (the same mechanism used for Comparator/Closeable callbacks
// elsewhere in Runtime) but proved unreliable in practice: the vtable slot
// for `nextBits` is an emergent property of declaration order across
// Sources/CompilerCore/Stdlib/kotlin/random/{Random,URandom}.kt and shifted
// twice during this same change (3 -> 6 -> 8) as sibling methods moved
// between files, and even after pinning the empirically-observed slot, calls
// through it produced out-of-range values for `Random.nextInt(IntRange)` and
// hung indefinitely for `IntRange.random(Random)` — symptoms consistent with
// the vtable slot for a class mixing synthetic-stub members (the KSP-457
// range-object bridges) and real Kotlin members not being as stable as the
// Sema-level layout dump suggested. Root-causing that is out of scope here.
//
// Given shuffled(random)/range.random(random)/string.random(random)'s own
// Kotlin migration is separate, deferred work (see TODO.md — e.g.
// `kk_list_shuffled(_random)` is explicitly called out as waiting until
// *after* KSP-466), this bridge instead falls back to system entropy,
// intentionally NOT reading the given Random receiver's seeded state. This
// trades away determinism-per-seed for these 4 call sites only (safe,
// memory-correct, always-in-range output) until their own migration lands
// and can address the underlying dispatch question directly.
func runtimeRandomNextIntBelow(_ receiver: Int, _ until: Int) -> Int {
    Int.random(in: 0 ..< until)
}

/// Raw 64-bit value; see `runtimeRandomNextIntBelow` above for why this does
/// not read the given Random receiver's seeded state.
func runtimeRandomNextBits64(_ receiver: Int) -> UInt64 {
    var rng = SystemRandomNumberGenerator()
    return rng.next()
}
