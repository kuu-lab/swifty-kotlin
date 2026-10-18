

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

    /// Returns a random Int (full range).
    func nextFullInt() -> Int {
        Int(bitPattern: UInt(truncatingIfNeeded: nextBits()))
    }

}

private let randomSourceInterfaceTypeID: Int64 = runtimeStableNominalTypeID(fqName: "kotlin.random.RandomSource")
private let randomLongSourceInterfaceTypeID: Int64 = runtimeStableNominalTypeID(fqName: "kotlin.random.RandomLongSource")
private let randomIntBitsSourceInterfaceTypeID: Int64 = runtimeStableNominalTypeID(fqName: "kotlin.random.RandomIntBitsSource")
private let randomIntRangeSourceInterfaceTypeID: Int64 = runtimeStableNominalTypeID(fqName: "kotlin.random.RandomIntRangeSource")
private let randomLongRangeSourceInterfaceTypeID: Int64 = runtimeStableNominalTypeID(fqName: "kotlin.random.RandomLongRangeSource")

private typealias RandomNextIntFn = @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int
private typealias RandomNextIntBitsFn = @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int
private typealias RandomNextIntRangeFn = @convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int
private typealias RandomNextLongFn = @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int
private typealias RandomNextLongRangeFn = @convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int

func runtimeRandomNextIntBelow(_ receiver: Int, _ until: Int) -> Int {
    guard receiver != 0 else {
        return Int.random(in: 0 ..< until)
    }
    let fnPtr = kk_itable_lookup_dynamic(receiver, Int(randomSourceInterfaceTypeID), 0)
    guard fnPtr != 0 else {
        return Int.random(in: 0 ..< until)
    }
    let fn = unsafeBitCast(fnPtr, to: RandomNextIntFn.self)
    return fn(receiver, until, nil)
}

func runtimeRandomNextIntBits(_ receiver: Int) -> Int {
    guard receiver != 0 else {
        return Int(Int32.random(in: Int32.min ... Int32.max))
    }
    let fnPtr = kk_itable_lookup_dynamic(
        receiver,
        Int(randomIntBitsSourceInterfaceTypeID),
        0
    )
    guard fnPtr != 0 else {
        return Int(Int32.random(in: Int32.min ... Int32.max))
    }
    let fn = unsafeBitCast(fnPtr, to: RandomNextIntBitsFn.self)
    return fn(receiver, nil)
}

func runtimeRandomNextIntRange(
    _ receiver: Int,
    from: Int,
    until: Int,
    outThrown: UnsafeMutablePointer<Int>? = nil
) -> Int {
    outThrown?.pointee = 0
    if receiver == 0 {
        guard until > from else {
            outThrown?.pointee = runtimeAllocateIllegalArgumentException(message: "bound must be greater than origin")
            return 0
        }
        return Int.random(in: from ..< until)
    }
    let fnPtr = kk_itable_lookup_dynamic(
        receiver,
        Int(randomIntRangeSourceInterfaceTypeID),
        0
    )
    guard fnPtr != 0 else {
        guard until > from else {
            outThrown?.pointee = runtimeAllocateIllegalArgumentException(
                message: "Random range is empty: [\(from), \(until))."
            )
            return 0
        }
        return Int.random(in: from ..< until)
    }
    let fn = unsafeBitCast(fnPtr, to: RandomNextIntRangeFn.self)
    return fn(receiver, from, until, outThrown)
}

func runtimeRandomNextBits64(_ receiver: Int) -> UInt64 {
    guard receiver != 0 else {
        var rng = SystemRandomNumberGenerator()
        return rng.next()
    }
    let fnPtr = kk_itable_lookup_dynamic(receiver, Int(randomLongSourceInterfaceTypeID), 0)
    guard fnPtr != 0 else {
        var rng = SystemRandomNumberGenerator()
        return rng.next()
    }
    let fn = unsafeBitCast(fnPtr, to: RandomNextLongFn.self)
    let longHandle = fn(receiver, nil)
    let longValue = kk_unbox_long(longHandle)
    return UInt64(bitPattern: Int64(longValue))
}

func runtimeRandomNextLongRange(_ receiver: Int, from: Int, until: Int) -> Int {
    guard until > from else {
        return from
    }
    if receiver == 0 {
        return Int.random(in: from ..< until)
    }
    let fnPtr = kk_itable_lookup_dynamic(
        receiver,
        Int(randomLongRangeSourceInterfaceTypeID),
        0
    )
    guard fnPtr != 0 else {
        return Int.random(in: from ..< until)
    }
    let fn = unsafeBitCast(fnPtr, to: RandomNextLongRangeFn.self)
    return kk_unbox_long(fn(receiver, from, until, nil))
}

@_cdecl("__kk_random_seed_entropy")
public func __kk_random_seed_entropy() -> Int {
    var rng = SystemRandomNumberGenerator()
    return Int(bitPattern: UInt(truncatingIfNeeded: rng.next()))
}


final class SecureRandomBox {
    // java.security.SecureRandom.setSeed only supplements a CSPRNG's entropy
    // and must never make output reproducible. SystemRandomNumberGenerator
    // accepts no seed input, so the compatibility entry point is a no-op
    // rather than a switch onto a deterministic stream.
    func setSeed(_: Int) {}

    private func nextBits() -> UInt64 {
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

private func ulongPayload(_ raw: Int) -> UInt64 {
    UInt64(UInt(bitPattern: raw))
}

private func runtimeRandomULongBits(receiver: Int) -> UInt64 {
    return runtimeRandomNextBits64(receiver)
}

private func runtimeRandomULongBelow(_ upperBound: UInt64, receiver: Int) -> UInt64 {
    precondition(upperBound > 0)
    if upperBound == 1 {
        return 0
    }
    let rejectionLimit = UInt64.max - (UInt64.max % upperBound)
    var candidate = runtimeRandomULongBits(receiver: receiver)
    while candidate >= rejectionLimit {
        candidate = runtimeRandomULongBits(receiver: receiver)
    }
    return candidate % upperBound
}

private func uint32Payload(_ raw: Int) -> UInt64 {
    UInt64(UInt(bitPattern: raw) & UInt(UInt32.max))
}

private func runtimeRandomUInt32Bits(receiver: Int) -> UInt64 {
    // Kotlin Random instances, including source-backed XorWowRandom, expose
    // their state through RandomLongSource. Falling back directly to system
    // entropy here would make UInt range overloads ignore an explicit seed.
    return runtimeRandomNextBits64(receiver) & UInt64(UInt32.max)
}

private func runtimeRandomUIntBelow(_ upperBound: UInt64, receiver: Int) -> UInt64 {
    precondition(upperBound > 0 && upperBound <= (UInt64(UInt32.max) + 1))
    if upperBound == 1 {
        return 0
    }
    let space = UInt64(UInt32.max) + 1
    let rejectionLimit = space - (space % upperBound)
    var candidate = runtimeRandomUInt32Bits(receiver: receiver)
    while candidate >= rejectionLimit {
        candidate = runtimeRandomUInt32Bits(receiver: receiver)
    }
    return candidate % upperBound
}

private func runtimeRandomUIntRange(receiver: Int, from: UInt64, until: UInt64) -> UInt64 {
    from + runtimeRandomUIntBelow(until - from, receiver: receiver)
}

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
    guard let box = secureRandomBox(from: receiver), size > 0 else {
        return registerRuntimeObject(RuntimeArrayBox(length: 0))
    }
    let array = RuntimeArrayBox(length: size)
    array.elements = (0 ..< size).map { _ in box.nextByte() }
    return registerRuntimeObject(array)
}

@_cdecl("__kk_secure_random_next_bytes")
public func __kk_secure_random_next_bytes(_ receiver: Int, _ arrayRaw: Int) -> Int {
    guard let box = secureRandomBox(from: receiver),
          let array = runtimeArrayBox(from: arrayRaw) else {
        return registerRuntimeObject(RuntimeArrayBox(length: 0))
    }
    array.elements = array.elements.map { _ in box.nextByte() }
    return arrayRaw
}

@_cdecl("__kk_random_nextULong_ulongRange")
public func __kk_random_nextULong_ulongRange(_ receiver: Int, _ rangeRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(
            message: "Random range is empty."
        )
        return 0
    }
    let first = ulongPayload(range.first)
    let last = ulongPayload(range.last)
    guard last >= first else {
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(
            message: "Random range is empty: \(first)..\(last)."
        )
        return 0
    }
    let width = last &- first &+ 1
    let value = width == 0
        ? runtimeRandomULongBits(receiver: receiver)
        : first &+ runtimeRandomULongBelow(width, receiver: receiver)
    return Int(bitPattern: UInt(truncatingIfNeeded: value))
}

@_cdecl("__kk_random_nextUInt_uintRange")
public func __kk_random_nextUInt_uintRange(_ receiver: Int, _ rangeRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(message: "Random.nextUInt expected a UIntRange.")
        return 0
    }
    let first = uint32Payload(range.first)
    let last = uint32Payload(range.last)
    guard range.step != 0, first <= last else {
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(message: "Range is empty.")
        return Int(first)
    }
    let exclusiveUpper = last == UInt64(UInt32.max) ? UInt64(UInt32.max) + 1 : last + 1
    return Int(runtimeRandomUIntRange(receiver: receiver, from: first, until: exclusiveUpper))
}
