
// ArrayDeque runtime (STDLIB-240) plus generic Array utility functions
// (STDLIB-089).
//
// Split out from `RuntimeCollections.swift`.

// MARK: - ArrayDeque ring-buffer bridges (KSP-625)
//
// `first` / `last` / `isEmpty` / `toString` and the emptiness checks that guard
// `removeFirst` / `removeLast` now live in
// `Sources/CompilerCore/Stdlib/kotlin/collections/ArrayDeque.kt`; only the
// allocation, construction, and element-storage mutation primitives remain
// here.

@_cdecl("__kk_arraydeque_new")
public func __kk_arraydeque_new() -> Int {
    registerRuntimeObject(RuntimeArrayDequeBox(capacity: 0))
}

@_cdecl("__kk_arraydeque_new_with_capacity")
public func __kk_arraydeque_new_with_capacity(
    _ capacity: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard capacity >= 0 else {
        runtimeSetThrown(
            outThrown,
            runtimeAllocateIllegalArgumentException(message: "Illegal Capacity: \(capacity)")
        )
        return 0
    }
    return registerRuntimeObject(RuntimeArrayDequeBox(capacity: capacity))
}

@_cdecl("__kk_arraydeque_new_from_collection")
public func __kk_arraydeque_new_from_collection(_ collectionRaw: Int) -> Int {
    let values = runtimeIterableValues(from: collectionRaw) ?? []
    return registerRuntimeObject(RuntimeArrayDequeBox(values: values))
}

@_cdecl("__kk_arraydeque_addFirst")
public func __kk_arraydeque_addFirst(_ dequeRaw: Int, _ element: Int) -> Int {
    guard let deque = runtimeArrayDequeBox(from: dequeRaw) else {
        return 0
    }
    deque.pushFirst(RuntimeValue(raw: element))
    return 0
}

@_cdecl("__kk_arraydeque_addLast")
public func __kk_arraydeque_addLast(_ dequeRaw: Int, _ element: Int) -> Int {
    guard let deque = runtimeArrayDequeBox(from: dequeRaw) else {
        return 0
    }
    deque.pushLast(RuntimeValue(raw: element))
    return 0
}

@_cdecl("__kk_arraydeque_removeFirst")
public func __kk_arraydeque_removeFirst(_ dequeRaw: Int) -> Int {
    guard let deque = runtimeArrayDequeBox(from: dequeRaw),
          let value = deque.popFirst()
    else {
        return 0
    }
    return value.legacyRawValue
}

@_cdecl("__kk_arraydeque_removeLast")
public func __kk_arraydeque_removeLast(_ dequeRaw: Int) -> Int {
    guard let deque = runtimeArrayDequeBox(from: dequeRaw),
          let value = deque.popLast()
    else {
        return 0
    }
    return value.legacyRawValue
}

@_cdecl("__kk_arraydeque_get")
public func __kk_arraydeque_get(_ dequeRaw: Int, _ index: Int) -> Int {
    guard let deque = runtimeArrayDequeBox(from: dequeRaw),
          let value = deque.element(at: index)
    else {
        return 0
    }
    return value.legacyRawValue
}

@_cdecl("__kk_arraydeque_size")
public func __kk_arraydeque_size(_ dequeRaw: Int) -> Int {
    guard let deque = runtimeArrayDequeBox(from: dequeRaw) else {
        return 0
    }
    return deque.count
}

// MARK: - Array utility functions (STDLIB-089)

@_cdecl("__kk_array_copyOf")
public func __kk_array_copyOf(_ arrayRaw: Int) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid array handle in __kk_array_copyOf")
    }
    // Copy storage wholesale so element anyFallbackTags survive; routing
    // through `elements` would drop them (and cost O(n²) per-element writes).
    let box = RuntimeArrayBox(length: array.count)
    box.values = array.values
    let copiedRaw = registerRuntimeObject(box)
    for typeID in runtimeArrayTypeIDs(rawValue: arrayRaw) {
        runtimeRegisterArrayType(rawValue: copiedRaw, typeID: typeID)
    }
    return copiedRaw
}

@_cdecl("kk_array_fill")
public func kk_array_fill(_ arrayRaw: Int, _ value: Int) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid array handle in kk_array_fill")
    }
    for i in 0 ..< array.count {
        array[i] = value
    }
    return 0
}

private struct RuntimeArrayDeepEqualityPair: Hashable {
    let lhs: Int
    let rhs: Int
}

private func runtimePlainArrayBox(from rawValue: Int) -> RuntimeArrayBox? {
    guard let pointer = UnsafeMutableRawPointer(bitPattern: rawValue) else {
        return nil
    }
    let isObjectPointer = runtimeStorage.withGCLock { state in
        state.objectPointers.contains(UInt(bitPattern: pointer))
    }
    guard isObjectPointer,
          let box = tryCast(pointer, to: RuntimeArrayBox.self),
          type(of: box) == RuntimeArrayBox.self
    else {
        return nil
    }
    return box
}

/// Renders one element of a tagged primitive array as its Kotlin value.
/// Elements are raw machine words — IEEE 754 bit patterns for Double/Float,
/// UTF-16 code units for Char, 0/1 for Boolean — so they must be decoded
/// with the array's declared element kind instead of going through the
/// generic (boxed/Any) element renderer, which can only print the raw word.
private func runtimePrimitiveArrayElementToString(
    _ raw: Int,
    kind: RuntimePrimitiveArrayElementKind
) -> String {
    switch kind {
    case .boolean:
        return raw != 0 ? "true" : "false"
    case .byte:
        return "\(Int8(truncatingIfNeeded: raw))"
    case .char:
        return runtimeCharacterFromRaw(raw)
    case .double:
        return runtimeFormatFloatingPoint(kk_bits_to_double(raw))
    case .float:
        return runtimeFormatFloatingPoint(kk_bits_to_float(raw))
    case .int:
        return "\(Int32(truncatingIfNeeded: raw))"
    case .long:
        return "\(Int64(raw))"
    case .short:
        return "\(Int16(truncatingIfNeeded: raw))"
    case .uByte:
        return "\(UInt8(truncatingIfNeeded: raw))"
    case .uShort:
        return "\(UInt16(truncatingIfNeeded: raw))"
    case .uInt:
        return "\(UInt32(truncatingIfNeeded: raw))"
    case .uLong:
        return "\(UInt64(bitPattern: Int64(raw)))"
    }
}

/// The canonical IEEE 754 bit pattern for a raw DoubleArray element:
/// every NaN payload folds to `doubleToLongBits`' canonical NaN, matching
/// `Arrays.equals(double[], double[])` / `Double.hashCode`.
private func runtimeCanonicalDoubleBits(_ raw: Int) -> UInt64 {
    let bits = UInt64(bitPattern: Int64(raw))
    return Double(bitPattern: bits).isNaN ? 0x7FF8_0000_0000_0000 : bits
}

/// The canonical bit pattern for a raw FloatArray element, matching
/// `floatToIntBits`' canonical NaN folding.
private func runtimeCanonicalFloatBits(_ raw: Int) -> UInt32 {
    let value = kk_bits_to_float(raw)
    return value.isNaN ? 0x7FC0_0000 : value.bitPattern
}

/// `Arrays.hashCode(x[])` element hash for a primitive element word.
/// Unsigned arrays hash their signed storage value (e.g. UByte(-56) -> -56),
/// matching the JVM's signed primitive storage, while toString renders the
/// unsigned value.
private func runtimePrimitiveArrayElementHash(
    _ raw: Int,
    kind: RuntimePrimitiveArrayElementKind
) -> Int {
    switch kind {
    case .boolean:
        return raw != 0 ? 1231 : 1237
    case .byte, .uByte:
        return Int(Int8(truncatingIfNeeded: raw))
    case .char:
        return Int(UInt16(truncatingIfNeeded: raw))
    case .double:
        return runtimeXorFoldHashCode(Int64(bitPattern: runtimeCanonicalDoubleBits(raw)))
    case .float:
        return Int(Int32(bitPattern: runtimeCanonicalFloatBits(raw)))
    case .int, .uInt:
        return Int(Int32(truncatingIfNeeded: raw))
    case .long, .uLong:
        return runtimeXorFoldHashCode(Int64(raw))
    case .short, .uShort:
        return Int(Int16(truncatingIfNeeded: raw))
    }
}

/// `Arrays.equals(x[], x[])` element equality for a primitive element word.
/// Floating-point elements compare canonical-NaN bitwise so different NaN
/// payloads are equal while -0.0 != 0.0, matching `Double.equals`.
private func runtimePrimitiveArrayElementsEqual(
    _ lhsRaw: Int,
    _ rhsRaw: Int,
    kind: RuntimePrimitiveArrayElementKind
) -> Bool {
    switch kind {
    case .double:
        return runtimeCanonicalDoubleBits(lhsRaw) == runtimeCanonicalDoubleBits(rhsRaw)
    case .float:
        return runtimeCanonicalFloatBits(lhsRaw) == runtimeCanonicalFloatBits(rhsRaw)
    default:
        return lhsRaw == rhsRaw
    }
}

private func runtimeArrayBoxesDeepEqual(
    lhsRaw: Int,
    rhsRaw: Int,
    lhs: RuntimeArrayBox,
    rhs: RuntimeArrayBox,
    visited: inout Set<RuntimeArrayDeepEqualityPair>
) -> Bool {
    guard lhs.count == rhs.count else {
        return false
    }
    // `Arrays.deepEquals0` requires the same array kind on both sides:
    // a DoubleArray is never deep-equal to a LongArray even when every
    // element word is bit-identical, and a primitive array is never equal
    // to a generic Array holding the same boxed values.
    let lhsKind = runtimePrimitiveArrayElementKind(rawValue: lhsRaw)
    let rhsKind = runtimePrimitiveArrayElementKind(rawValue: rhsRaw)
    guard lhsKind == rhsKind else {
        return false
    }
    let pair = RuntimeArrayDeepEqualityPair(lhs: lhsRaw, rhs: rhsRaw)
    guard visited.insert(pair).inserted else {
        return true
    }
    defer { visited.remove(pair) }

    let lhsElements = lhs.elements
    let rhsElements = rhs.elements
    for index in lhsElements.indices {
        if let kind = lhsKind {
            guard runtimePrimitiveArrayElementsEqual(
                lhsElements[index], rhsElements[index], kind: kind
            ) else {
                return false
            }
        } else if !runtimeValuesDeepEqual(lhsElements[index], rhsElements[index], visited: &visited) {
            return false
        }
    }
    return true
}

private func runtimeValuesDeepEqual(
    _ lhsRaw: Int,
    _ rhsRaw: Int,
    visited: inout Set<RuntimeArrayDeepEqualityPair>
) -> Bool {
    if lhsRaw == rhsRaw {
        return true
    }
    if let lhs = runtimePlainArrayBox(from: lhsRaw),
       let rhs = runtimePlainArrayBox(from: rhsRaw)
    {
        return runtimeArrayBoxesDeepEqual(
            lhsRaw: lhsRaw,
            rhsRaw: rhsRaw,
            lhs: lhs,
            rhs: rhs,
            visited: &visited
        )
    }
    return runtimeValuesEqual(lhsRaw, rhsRaw)
}

@_cdecl("__kk_array_contentDeepEquals")
public func __kk_array_contentDeepEquals(_ arrayRaw: Int, _ otherRaw: Int) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        return kk_box_bool(runtimeArrayBox(from: otherRaw) == nil ? 1 : 0)
    }
    guard let other = runtimeArrayBox(from: otherRaw) else {
        return kk_box_bool(0)
    }
    var visited: Set<RuntimeArrayDeepEqualityPair> = []
    return kk_box_bool(runtimeArrayBoxesDeepEqual(
        lhsRaw: arrayRaw,
        rhsRaw: otherRaw,
        lhs: array,
        rhs: other,
        visited: &visited
    ) ? 1 : 0)
}

private func runtimeArrayBoxDeepToString(
    raw: Int,
    box: RuntimeArrayBox,
    visited: inout Set<Int>
) -> String {
    guard visited.insert(raw).inserted else {
        return "[...]"
    }
    defer { visited.remove(raw) }

    // A tagged primitive array renders its raw element words as Kotlin
    // values (`Arrays.deepToString` recurses into primitive arrays with
    // value semantics), e.g. `arrayOf(doubleArrayOf(1.0))` -> "[[1.0]]",
    // not the raw IEEE 754 bit patterns.
    if let kind = runtimePrimitiveArrayElementKind(rawValue: raw) {
        return "[" + box.elements
            .map { runtimePrimitiveArrayElementToString($0, kind: kind) }
            .joined(separator: ", ") + "]"
    }
    let rendered = box.elements
        .map { runtimeValueDeepToString($0, visited: &visited) }
        .joined(separator: ", ")
    return "[\(rendered)]"
}

private func runtimeValueDeepToString(_ raw: Int, visited: inout Set<Int>) -> String {
    if let array = runtimePlainArrayBox(from: raw) {
        return runtimeArrayBoxDeepToString(raw: raw, box: array, visited: &visited)
    }
    return runtimeElementToString(raw)
}

private func runtimeArrayStringPointer(_ value: String) -> UnsafeMutableRawPointer {
    runtimeMakeStringPointer(value)
}

@_cdecl("__kk_array_contentDeepToString")
public func __kk_array_contentDeepToString(_ arrayRaw: Int) -> UnsafeMutableRawPointer {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        return runtimeArrayStringPointer("null")
    }
    var visited: Set<Int> = []
    return runtimeArrayStringPointer(runtimeArrayBoxDeepToString(raw: arrayRaw, box: array, visited: &visited))
}

private func runtimeArrayBoxDeepHash(
    raw: Int,
    box: RuntimeArrayBox,
    visited: inout Set<Int>
) -> Int {
    guard visited.insert(raw).inserted else {
        return 0
    }
    defer { visited.remove(raw) }

    // Kotlin's Arrays.deepHashCode folds 31*acc + elementHash in 32-bit
    // wrapping Int arithmetic at every step; accumulating in the host's
    // 64-bit Int only agrees while the running total stays inside Int32
    // range and diverges on deep or long arrays.
    var result: Int32 = 1
    if let kind = runtimePrimitiveArrayElementKind(rawValue: raw) {
        for element in box.elements {
            result = 31 &* result &+ Int32(truncatingIfNeeded: runtimePrimitiveArrayElementHash(element, kind: kind))
        }
        return Int(result)
    }
    for element in box.elements {
        result = 31 &* result &+ Int32(truncatingIfNeeded: runtimeValueDeepHash(element, visited: &visited))
    }
    return Int(result)
}

private func runtimeValueDeepHash(_ raw: Int, visited: inout Set<Int>) -> Int {
    if let array = runtimePlainArrayBox(from: raw) {
        return runtimeArrayBoxDeepHash(raw: raw, box: array, visited: &visited)
    }
    return kk_any_hashCode(raw, 0)
}

@_cdecl("__kk_array_contentDeepHashCode")
public func __kk_array_contentDeepHashCode(_ arrayRaw: Int) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        return 0
    }
    var visited: Set<Int> = []
    return runtimeArrayBoxDeepHash(raw: arrayRaw, box: array, visited: &visited)
}
