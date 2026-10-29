import Foundation

final class RuntimeUuidBox {
    let mostSignificantBits: Int64
    let leastSignificantBits: Int64

    init(mostSignificantBits: Int64, leastSignificantBits: Int64) {
        self.mostSignificantBits = mostSignificantBits
        self.leastSignificantBits = leastSignificantBits
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
    // Uuid values are created here rather than by the Kotlin constructor, so its
    // equals/hashCode overrides are never registered per object. Value equality
    // is structural over the two bit slots.
    runtimeRegisterDataClass(classID: runtimeUuidClassID)
    let raw = kk_object_new(4, Int(runtimeUuidClassID))
    guard let box = runtimeArrayBox(from: raw), box.count >= 4 else {
        return raw
    }
    box[2] = Int(mostSignificantBits)
    box[3] = Int(leastSignificantBits)
    return raw
}

@_cdecl("__kk_uuid_random")
public func __kk_uuid_random() -> Int {
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

@_cdecl("__kk_uuid_toKotlinUuid")
public func __kk_uuid_toKotlinUuid(_ receiver: Int) -> Int {
    kk_uuid_toKotlinUuid(receiver)
}
