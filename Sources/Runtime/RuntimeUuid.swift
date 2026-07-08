import Foundation

// MARK: - Uuid Runtime Support (kotlin.uuid.Uuid)
//
// KSP-476: only the operations that genuinely require native support remain
// here (entropy, MD5, and the opaque-box allocate/read primitives). Parsing,
// formatting, bit extraction, comparison, and ByteArray packing are pure
// Kotlin (Sources/CompilerCore/Stdlib/kotlin/uuid/Uuid.kt), built on top of
// these bridges.

/// Internal box holding a UUID value as two 64-bit integers (most significant, least significant).
final class RuntimeUuidBox {
    let mostSignificantBits: Int64
    let leastSignificantBits: Int64

    init(mostSignificantBits: Int64, leastSignificantBits: Int64) {
        self.mostSignificantBits = mostSignificantBits
        self.leastSignificantBits = leastSignificantBits
    }
}

/// Extract a RuntimeUuidBox from a raw receiver value.
private func runtimeUuidBox(from rawValue: Int) -> RuntimeUuidBox? {
    resolveRuntimeHandle(rawValue, as: RuntimeUuidBox.self)
}

// MARK: - Uuid.random()

@_cdecl("__kk_uuid_random")
func __kk_uuid_random() -> Int {
    // Generate a version-4 (random) UUID
    var rng = SystemRandomNumberGenerator()
    var msb = Int64(bitPattern: rng.next() as UInt64)
    var lsb = Int64(bitPattern: rng.next() as UInt64)

    // Set version to 4 (bits 12-15 of time_hi_and_version)
    msb = msb & ~(0xF << 12) | (4 << 12)
    // Set variant to IETF (bits 62-63 of clock_seq)
    lsb = lsb & ~(0x3 << 62) | (Int64(2) << 62)

    let box = RuntimeUuidBox(mostSignificantBits: msb, leastSignificantBits: lsb)
    return registerRuntimeObject(box)
}

// MARK: - Uuid.fromLongs(mostSignificantBits, leastSignificantBits)

/// Create a Uuid from two Long values (MSB and LSB).
/// Maps directly to kotlin.uuid.Uuid.fromLongs().
@_cdecl("__kk_uuid_fromLongs")
func __kk_uuid_fromLongs(_ msb: Int, _ lsb: Int) -> Int {
    let box = RuntimeUuidBox(
        mostSignificantBits: Int64(bitPattern: UInt64(bitPattern: Int64(msb))),
        leastSignificantBits: Int64(bitPattern: UInt64(bitPattern: Int64(lsb)))
    )
    return registerRuntimeObject(box)
}

// MARK: - Uuid.mostSignificantBits / leastSignificantBits

@_cdecl("__kk_uuid_mostSignificantBits")
func __kk_uuid_mostSignificantBits(_ receiver: Int) -> Int {
    guard let box = runtimeUuidBox(from: receiver) else {
        return 0
    }
    return Int(box.mostSignificantBits)
}

@_cdecl("__kk_uuid_leastSignificantBits")
func __kk_uuid_leastSignificantBits(_ receiver: Int) -> Int {
    guard let box = runtimeUuidBox(from: receiver) else {
        return 0
    }
    return Int(box.leastSignificantBits)
}

// MARK: - Uuid.nameUUIDFromBytes(name: ByteArray)

/// Generate a version-3 (MD5-based) UUID from a name byte array.
/// Follows RFC 4122 name-based UUID generation.
@_cdecl("__kk_uuid_nameUUIDFromBytes")
func __kk_uuid_nameUUIDFromBytes(_ nameArrayRaw: Int) -> Int {
    var inputBytes: [UInt8]
    if let ptr = UnsafeMutableRawPointer(bitPattern: nameArrayRaw),
       let arrayBox = tryCast(ptr, to: RuntimeArrayBox.self)
    {
        inputBytes = arrayBox.elements.map { UInt8($0 & 0xFF) }
    } else {
        inputBytes = []
    }

    let digest = kk_uuid_md5Digest(inputBytes)

    var msb: UInt64 = 0
    var lsb: UInt64 = 0
    for i in 0..<8 {
        msb = (msb << 8) | UInt64(digest[i])
    }
    for i in 8..<16 {
        lsb = (lsb << 8) | UInt64(digest[i])
    }

    // Set version to 3 (name-based MD5)
    msb = (msb & 0xFFFF_FFFF_FFFF_0FFF) | 0x0000_0000_0000_3000
    // Set variant to IETF RFC 4122
    lsb = (lsb & 0x3FFF_FFFF_FFFF_FFFF) | 0x8000_0000_0000_0000

    let box = RuntimeUuidBox(
        mostSignificantBits: Int64(bitPattern: msb),
        leastSignificantBits: Int64(bitPattern: lsb)
    )
    return registerRuntimeObject(box)
}

// MARK: - java.util.UUID.toKotlinUuid()

// java.util.UUID and kotlin.uuid.Uuid share the same native runtime representation
// (RuntimeUuidBox with mostSignificantBits / leastSignificantBits), so this is an
// identity-style conversion: copy the bits into a fresh Uuid box.
@_cdecl("__kk_uuid_toKotlinUuid")
func __kk_uuid_toKotlinUuid(_ receiver: Int) -> Int {
    guard let box = runtimeUuidBox(from: receiver) else {
        return registerRuntimeObject(RuntimeUuidBox(mostSignificantBits: 0, leastSignificantBits: 0))
    }
    let newBox = RuntimeUuidBox(
        mostSignificantBits: box.mostSignificantBits,
        leastSignificantBits: box.leastSignificantBits
    )
    return registerRuntimeObject(newBox)
}

// MARK: - Uuid.LEXICAL_ORDER
//
// Multi-parameter SAM-conversion lambdas (`Comparator { a, b -> ... }`) don't
// resolve their lambda parameters correctly in Sema yet (KSP-476 finding), so
// LEXICAL_ORDER stays a native bridge that itable-registers a Comparator.compare
// implementation directly, same as the original KSP-310 approach.

private final class RuntimeUuidLexicalOrderComparatorBox {}

private let kkUuidLexicalOrderComparator: @convention(c) (
    Int,
    Int,
    Int,
    UnsafeMutablePointer<Int>?
) -> Int = { _, lhsRaw, rhsRaw, outThrown in
    guard let lhs = runtimeUuidBox(from: lhsRaw),
          let rhs = runtimeUuidBox(from: rhsRaw)
    else {
        outThrown?.pointee = runtimeAllocateThrowable(
            message: "IllegalArgumentException: Uuid.LEXICAL_ORDER.compare expected Uuid arguments"
        )
        return 0
    }
    return runtimeCompareUuidLexically(lhs, rhs)
}

private func runtimeCompareUuidLexically(_ lhs: RuntimeUuidBox, _ rhs: RuntimeUuidBox) -> Int {
    let lhsMsb = UInt64(bitPattern: lhs.mostSignificantBits)
    let rhsMsb = UInt64(bitPattern: rhs.mostSignificantBits)
    if lhsMsb != rhsMsb {
        return lhsMsb < rhsMsb ? -1 : 1
    }
    let lhsLsb = UInt64(bitPattern: lhs.leastSignificantBits)
    let rhsLsb = UInt64(bitPattern: rhs.leastSignificantBits)
    if lhsLsb != rhsLsb {
        return lhsLsb < rhsLsb ? -1 : 1
    }
    return 0
}

@_cdecl("__kk_uuid_lexicalOrder")
func __kk_uuid_lexicalOrder() -> Int {
    let raw = registerRuntimeObject(RuntimeUuidLexicalOrderComparatorBox())
    _ = kk_object_register_itable_method(
        raw,
        0,
        0,
        unsafeBitCast(kkUuidLexicalOrderComparator, to: Int.self)
    )
    return raw
}

/// Compute MD5 digest of input bytes, returning 16 bytes.
private func kk_uuid_md5Digest(_ input: [UInt8]) -> [UInt8] {
    let s: [UInt32] = [
        7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22,
        5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20,
        4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23,
        6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21,
    ]
    let k: [UInt32] = [
        0xd76aa478, 0xe8c7b756, 0x242070db, 0xc1bdceee,
        0xf57c0faf, 0x4787c62a, 0xa8304613, 0xfd469501,
        0x698098d8, 0x8b44f7af, 0xffff5bb1, 0x895cd7be,
        0x6b901122, 0xfd987193, 0xa679438e, 0x49b40821,
        0xf61e2562, 0xc040b340, 0x265e5a51, 0xe9b6c7aa,
        0xd62f105d, 0x02441453, 0xd8a1e681, 0xe7d3fbc8,
        0x21e1cde6, 0xc33707d6, 0xf4d50d87, 0x455a14ed,
        0xa9e3e905, 0xfcefa3f8, 0x676f02d9, 0x8d2a4c8a,
        0xfffa3942, 0x8771f681, 0x6d9d6122, 0xfde5380c,
        0xa4beea44, 0x4bdecfa9, 0xf6bb4b60, 0xbebfbc70,
        0x289b7ec6, 0xeaa127fa, 0xd4ef3085, 0x04881d05,
        0xd9d4d039, 0xe6db99e5, 0x1fa27cf8, 0xc4ac5665,
        0xf4292244, 0x432aff97, 0xab9423a7, 0xfc93a039,
        0x655b59c3, 0x8f0ccc92, 0xffeff47d, 0x85845dd1,
        0x6fa87e4f, 0xfe2ce6e0, 0xa3014314, 0x4e0811a1,
        0xf7537e82, 0xbd3af235, 0x2ad7d2bb, 0xeb86d391,
    ]

    var msg = input
    let originalLengthBits = UInt64(input.count) * 8
    msg.append(0x80)
    while msg.count % 64 != 56 {
        msg.append(0x00)
    }
    for i in 0..<8 {
        msg.append(UInt8((originalLengthBits >> (i * 8)) & 0xFF))
    }

    var a0: UInt32 = 0x67452301
    var b0: UInt32 = 0xefcdab89
    var c0: UInt32 = 0x98badcfe
    var d0: UInt32 = 0x10325476

    let chunkCount = msg.count / 64
    for chunkIndex in 0..<chunkCount {
        let offset = chunkIndex * 64
        var m = [UInt32](repeating: 0, count: 16)
        for i in 0..<16 {
            let base = offset + i * 4
            m[i] = UInt32(msg[base])
                | (UInt32(msg[base + 1]) << 8)
                | (UInt32(msg[base + 2]) << 16)
                | (UInt32(msg[base + 3]) << 24)
        }

        var a = a0, b = b0, c = c0, d = d0

        for i in 0..<64 {
            var f: UInt32
            var g: Int
            if i < 16 {
                f = (b & c) | (~b & d)
                g = i
            } else if i < 32 {
                f = (d & b) | (~d & c)
                g = (5 * i + 1) % 16
            } else if i < 48 {
                f = b ^ c ^ d
                g = (3 * i + 5) % 16
            } else {
                f = c ^ (b | ~d)
                g = (7 * i) % 16
            }
            f = f &+ a &+ k[i] &+ m[g]
            a = d
            d = c
            c = b
            b = b &+ ((f << s[i]) | (f >> (32 - s[i])))
        }

        a0 = a0 &+ a
        b0 = b0 &+ b
        c0 = c0 &+ c
        d0 = d0 &+ d
    }

    var digest = [UInt8](repeating: 0, count: 16)
    for (wordIndex, word) in [a0, b0, c0, d0].enumerated() {
        for byteIndex in 0..<4 {
            digest[wordIndex * 4 + byteIndex] = UInt8((word >> (byteIndex * 8)) & 0xFF)
        }
    }
    return digest
}
