import Foundation

// MARK: - Uuid Runtime Support (kotlin.uuid.Uuid)

/// Internal box holding a UUID value as two 64-bit integers (most significant, least significant).
final class RuntimeUuidBox {
    let mostSignificantBits: Int64
    let leastSignificantBits: Int64

    init(mostSignificantBits: Int64, leastSignificantBits: Int64) {
        self.mostSignificantBits = mostSignificantBits
        self.leastSignificantBits = leastSignificantBits
    }

    /// Format as standard UUID string: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
    var uuidString: String {
        let msb = UInt64(bitPattern: mostSignificantBits)
        let lsb = UInt64(bitPattern: leastSignificantBits)

        let p1 = String(format: "%08x", UInt32(msb >> 32))
        let p2 = String(format: "%04x", UInt16((msb >> 16) & 0xFFFF))
        let p3 = String(format: "%04x", UInt16(msb & 0xFFFF))
        let p4 = String(format: "%04x", UInt16(lsb >> 48))
        let p5 = String(format: "%012llx", lsb & 0x0000_FFFF_FFFF_FFFF)

        return "\(p1)-\(p2)-\(p3)-\(p4)-\(p5)"
    }

    /// Format as hex string without dashes: xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
    var hexString: String {
        let msb = UInt64(bitPattern: mostSignificantBits)
        let lsb = UInt64(bitPattern: leastSignificantBits)
        return String(format: "%016llx%016llx", msb, lsb)
    }

    /// Convert to 16-byte array (big-endian)
    var byteArray: [UInt8] {
        let msb = UInt64(bitPattern: mostSignificantBits)
        let lsb = UInt64(bitPattern: leastSignificantBits)
        var bytes = [UInt8](repeating: 0, count: 16)
        for i in 0..<8 {
            bytes[i] = UInt8((msb >> (56 - i * 8)) & 0xFF)
        }
        for i in 0..<8 {
            bytes[8 + i] = UInt8((lsb >> (56 - i * 8)) & 0xFF)
        }
        return bytes
    }

    var version: Int {
        let msb = UInt64(bitPattern: mostSignificantBits)
        return Int((msb >> 12) & 0xF)
    }

    var variant: Int {
        let lsb = UInt64(bitPattern: leastSignificantBits)
        let topThreeBits = (lsb >> 61) & 0x7
        switch topThreeBits {
        case 0b000, 0b001, 0b010, 0b011:
            return 0 // NCS backward compatibility
        case 0b100, 0b101:
            return 2 // RFC 4122 / IETF
        case 0b110:
            return 6 // Microsoft compatibility bucket
        default:
            return 7 // future reserved bucket
        }
    }
}

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
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(
            message: "Uuid.LEXICAL_ORDER.compare expected Uuid arguments"
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
public func __kk_uuid_lexicalOrder() -> Int {
    let raw = registerRuntimeObject(RuntimeUuidLexicalOrderComparatorBox())
    _ = kk_object_register_itable_method(raw, 0, 0, unsafeBitCast(kkUuidLexicalOrderComparator, to: Int.self))
    // Needed for itableDynamic dispatch (e.g. `sortedWith(Uuid.lexicalOrder())`)
    // — see the identical Comparator gap fixed in RuntimeComparator.swift.
    _ = kk_object_register_itable_iface(raw, Int(runtimeStableNominalTypeID("kotlin.Comparator")), 0)
    return raw
}

/// Extract a RuntimeUuidBox from a raw receiver value.
private func runtimeUuidBox(from rawValue: Int) -> RuntimeUuidBox? {
    if let legacyBox = resolveRuntimeHandle(rawValue, as: RuntimeUuidBox.self) {
        return legacyBox
    }
    guard let arrayBox = runtimeArrayBox(from: rawValue) else {
        return nil
    }
    let elements = arrayBox.elements
    if elements.count >= 4 {
        return RuntimeUuidBox(
            mostSignificantBits: Int64(elements[2]),
            leastSignificantBits: Int64(elements[3])
        )
    }
    if elements.count >= 2 {
        return RuntimeUuidBox(
            mostSignificantBits: Int64(elements[0]),
            leastSignificantBits: Int64(elements[1])
        )
    }
    return nil
}

private let runtimeUuidClassID: Int64 = runtimeStableNominalTypeID("kotlin.uuid.Uuid")

private func runtimeStableNominalTypeID(_ fqName: String) -> Int64 {
    let payloadMask: Int64 = (1 << 55) - 1
    var hash: UInt64 = 0xCBF2_9CE4_8422_2325
    for byte in fqName.utf8 {
        hash ^= UInt64(byte)
        hash &*= 0x100_0000_01B3
    }
    let payload = Int64(bitPattern: hash) & payloadMask
    return payload == 0 ? 1 : payload
}

private func runtimeUuidObjectRaw(mostSignificantBits: Int64, leastSignificantBits: Int64) -> Int {
    let raw = kk_object_new(4, Int(runtimeUuidClassID))
    guard let box = runtimeArrayBox(from: raw), box.elements.count >= 4 else {
        return raw
    }
    box.elements[2] = Int(mostSignificantBits)
    box.elements[3] = Int(leastSignificantBits)
    return raw
}

/// Helper to create a runtime string from a Swift String, returning Int.
private func uuidMakeStringRaw(_ value: String) -> Int {
    Int(bitPattern: value.withCString { cstr in
        cstr.withMemoryRebound(to: UInt8.self, capacity: value.utf8.count) { pointer in
            kk_string_from_utf8(pointer, Int32(value.utf8.count))
        }
    })
}

// MARK: - Uuid.random()

@_cdecl("__kk_uuid_random")
public func __kk_uuid_random() -> Int {
    // Generate a version-4 (random) UUID
    var rng = SystemRandomNumberGenerator()
    var msb = Int64(bitPattern: rng.next() as UInt64)
    var lsb = Int64(bitPattern: rng.next() as UInt64)

    // Set version to 4 (bits 12-15 of time_hi_and_version)
    msb = msb & ~(0xF << 12) | (4 << 12)
    // Set variant to IETF (bits 62-63 of clock_seq)
    lsb = lsb & ~(0x3 << 62) | (Int64(2) << 62)

    return runtimeUuidObjectRaw(mostSignificantBits: msb, leastSignificantBits: lsb)
}

@_cdecl("__kk_uuid_fromLongs")
public func __kk_uuid_fromLongs(_ msbRaw: Int, _ lsbRaw: Int) -> Int {
    return runtimeUuidObjectRaw(
        mostSignificantBits: Int64(kk_unbox_long(msbRaw)),
        leastSignificantBits: Int64(kk_unbox_long(lsbRaw))
    )
}

// MARK: - java.util.UUID.toKotlinUuid()

// Copy UUID bits from a java.util.UUID-style value into the Kotlin source Uuid
// object shape (object header slots plus most/least significant bits).
func kk_uuid_toKotlinUuid(_ receiver: Int) -> Int {
    guard let box = runtimeUuidBox(from: receiver) else {
        return runtimeUuidObjectRaw(mostSignificantBits: 0, leastSignificantBits: 0)
    }
    return runtimeUuidObjectRaw(
        mostSignificantBits: box.mostSignificantBits,
        leastSignificantBits: box.leastSignificantBits
    )
}

// Keep the private bridge name used by the Kotlin source implementation and
// ABI inventory while retaining the public compatibility entry point above.
@_cdecl("__kk_uuid_toKotlinUuid")
func __kk_uuid_toKotlinUuid(_ receiver: Int) -> Int {
    kk_uuid_toKotlinUuid(receiver)
}

// MARK: - ByteArray.putUuid(at: Int, uuid: Uuid)

public func kk_byteArray_putUuid(
    _ arrayRaw: Int,
    _ at: Int,
    _ uuidRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0

    guard let arrayPtr = UnsafeMutableRawPointer(bitPattern: arrayRaw),
          let arrayBox = tryCast(arrayPtr, to: RuntimeArrayBox.self)
    else {
        outThrown?.pointee = runtimeAllocateIndexOutOfBoundsException(
            message: "at (\(at)) is out of bounds for array of size 0"
        )
        return 0
    }

    let size = arrayBox.elements.count
    if at < 0 {
        outThrown?.pointee = runtimeAllocateIndexOutOfBoundsException(
            message: "at (\(at)) < 0"
        )
        return 0
    }
    if at + 16 > size {
        outThrown?.pointee = runtimeAllocateIndexOutOfBoundsException(
            message: "at (\(at)) + 16 > size (\(size))"
        )
        return 0
    }

    guard let uuidBox = runtimeUuidBox(from: uuidRaw) else {
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(
            message: "uuid must not be null"
        )
        return 0
    }

    let bytes = uuidBox.byteArray
    for i in 0..<16 {
        arrayBox.elements[at + i] = Int(bytes[i])
    }
    return 0
}

// MARK: - ByteArray.uuid(at: Int): Uuid

public func kk_byteArray_uuid(
    _ arrayRaw: Int,
    _ at: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0

    guard let arrayPtr = UnsafeMutableRawPointer(bitPattern: arrayRaw),
          let arrayBox = tryCast(arrayPtr, to: RuntimeArrayBox.self)
    else {
        outThrown?.pointee = runtimeAllocateIndexOutOfBoundsException(
            message: "at (\(at)) is out of bounds for array of size 0"
        )
        return 0
    }

    let size = arrayBox.elements.count
    if at < 0 {
        outThrown?.pointee = runtimeAllocateIndexOutOfBoundsException(
            message: "at (\(at)) < 0"
        )
        return 0
    }
    if at + 16 > size {
        outThrown?.pointee = runtimeAllocateIndexOutOfBoundsException(
            message: "at (\(at)) + 16 > size (\(size))"
        )
        return 0
    }

    var msb: UInt64 = 0
    var lsb: UInt64 = 0
    for i in 0..<8 {
        msb = (msb << 8) | UInt64(arrayBox.elements[at + i] & 0xFF)
    }
    for i in 8..<16 {
        lsb = (lsb << 8) | UInt64(arrayBox.elements[at + i] & 0xFF)
    }

    return runtimeUuidObjectRaw(
        mostSignificantBits: Int64(bitPattern: msb),
        leastSignificantBits: Int64(bitPattern: lsb)
    )
}

// MARK: - ByteArray.getUuid(offset: Int)

/// Read a UUID from 16 bytes at [offset, offset+16) of the ByteArray.
/// Throws IndexOutOfBoundsException when offset < 0 or offset + 16 > size.
public func kk_uuid_getUuid(_ arrayRaw: Int, _ offset: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0

    guard let ptr = UnsafeMutableRawPointer(bitPattern: arrayRaw),
          let arrayBox = tryCast(ptr, to: RuntimeArrayBox.self)
    else {
        outThrown?.pointee = runtimeAllocateIndexOutOfBoundsException(
            message: "offset out of bounds for empty reference"
        )
        return 0
    }

    let size = arrayBox.elements.count
    guard offset >= 0, offset + 16 <= size else {
        outThrown?.pointee = runtimeAllocateIndexOutOfBoundsException(
            message: "offset \(offset) out of bounds for array of size \(size)"
        )
        return 0
    }

    var msb: UInt64 = 0
    var lsb: UInt64 = 0
    for i in 0..<8 {
        msb = (msb << 8) | UInt64(arrayBox.elements[offset + i] & 0xFF)
    }
    for i in 8..<16 {
        lsb = (lsb << 8) | UInt64(arrayBox.elements[offset + i] & 0xFF)
    }

    return runtimeUuidObjectRaw(
        mostSignificantBits: Int64(bitPattern: msb),
        leastSignificantBits: Int64(bitPattern: lsb)
    )
}
