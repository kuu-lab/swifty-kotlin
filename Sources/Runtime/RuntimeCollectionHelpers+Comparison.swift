private let comparableRuntimeTypeID: Int64 = runtimeStableNominalTypeID(fqName: "kotlin.Comparable")

private let comparatorRuntimeTypeID: Int64 = runtimeStableNominalTypeID(fqName: "kotlin.Comparator")

func runtimeCompareValues(_ lhs: Int, _ rhs: Int) -> Int {
    if lhs == rhs {
        return 0
    }
    if let lhsString = runtimeStringFromRawValue(lhs),
       let rhsString = runtimeStringFromRawValue(rhs)
    {
        return runtimeCompareStrings(lhsString, rhsString)
    }
    if let lhsScalar = runtimeComparableScalarValue(from: lhs),
       let rhsScalar = runtimeComparableScalarValue(from: rhs)
    {
        switch (lhsScalar, rhsScalar) {
        case let (.floating(lhsValue), .floating(rhsValue)):
            return runtimeCompareFloatingValues(lhsValue, rhsValue)
        case let (.floating(lhsValue), .integer(rhsValue)):
            return runtimeCompareFloatingValues(lhsValue, Double(rhsValue))
        case let (.floating(lhsValue), .unsignedInteger(rhsValue)):
            return runtimeCompareFloatingValues(lhsValue, Double(rhsValue))
        case let (.integer(lhsValue), .floating(rhsValue)):
            return runtimeCompareFloatingValues(Double(lhsValue), rhsValue)
        case let (.unsignedInteger(lhsValue), .floating(rhsValue)):
            return runtimeCompareFloatingValues(Double(lhsValue), rhsValue)
        case let (.integer(lhsValue), .integer(rhsValue)):
            if lhsValue == rhsValue {
                return 0
            }
            return lhsValue < rhsValue ? -1 : 1
        case let (.unsignedInteger(lhsValue), .unsignedInteger(rhsValue)):
            if lhsValue == rhsValue {
                return 0
            }
            return lhsValue < rhsValue ? -1 : 1
        // Mixed signed/unsigned integers only arise when comparing values of
        // statically-incompatible Kotlin types (e.g. Long vs ULong through a
        // type-erased Comparable); there is no principled ordering, so fall
        // back to a Double approximation rather than crashing.
        case let (.integer(lhsValue), .unsignedInteger(rhsValue)):
            return runtimeCompareFloatingValues(Double(lhsValue), Double(rhsValue))
        case let (.unsignedInteger(lhsValue), .integer(rhsValue)):
            return runtimeCompareFloatingValues(Double(lhsValue), Double(rhsValue))
        }
    }
    if let comparableResult = runtimeCompareComparableValues(lhs: lhs, rhs: rhs) {
        return comparableResult
    }
    let lhsRendered = runtimeElementToString(lhs)
    let rhsRendered = runtimeElementToString(rhs)
    if lhsRendered == rhsRendered {
        return 0
    }
    return lhsRendered < rhsRendered ? -1 : 1
}

func runtimeCompareValues(_ lhs: RuntimeValue, _ rhs: RuntimeValue) -> Int {
    if lhs.tag == RuntimeValue.rawTag, rhs.tag == RuntimeValue.rawTag {
        return runtimeCompareValues(lhs.payload0, rhs.payload0)
    }
    if let lhsString = runtimeStringFromRuntimeValue(lhs),
       let rhsString = runtimeStringFromRuntimeValue(rhs)
    {
        return runtimeCompareStrings(lhsString, rhsString)
    }
    if lhs.tag == RuntimeValue.charTag, rhs.tag == RuntimeValue.charTag {
        return runtimeCompareIntegers(lhs.payload0, rhs.payload0)
    }
    if lhs.tag != RuntimeValue.stringTag, rhs.tag != RuntimeValue.stringTag {
        return runtimeCompareValues(lhs.legacyRawValue, rhs.legacyRawValue)
    }
    return runtimeCompareStrings(
        runtimeElementToString(lhs),
        runtimeElementToString(rhs)
    )
}

@inline(__always)
private func runtimeCompareIntegers(_ lhs: Int, _ rhs: Int) -> Int {
    if lhs == rhs {
        return 0
    }
    return lhs < rhs ? -1 : 1
}

private func runtimeStringFromRuntimeValue(_ value: RuntimeValue) -> String? {
    switch value.tag {
    case RuntimeValue.stringTag:
        guard let data = UnsafePointer<UInt8>(bitPattern: value.payload0) else {
            return nil
        }
        return runtimeStringFromFlatFields(
            data: data,
            length: value.payload1,
            byteCount: value.payload2,
            hash: value.payload3
        )
    case RuntimeValue.rawTag:
        return runtimeStringFromRawValue(value.payload0)
    default:
        return nil
    }
}

@inline(__always)
func runtimeBinarySearch(
    elements: [Int],
    element: Int,
    fromIndex: Int,
    toIndex: Int,
    compare: (Int, Int) -> Int
) -> Int {
    let lowerBound = max(0, min(fromIndex, elements.count))
    let upperBound = max(lowerBound, min(toIndex, elements.count))
    var low = lowerBound
    var high = upperBound - 1
    while low <= high {
        let mid = (low + high) / 2
        let cmp = compare(elements[mid], element)
        if cmp < 0 {
            low = mid + 1
        } else if cmp > 0 {
            high = mid - 1
        } else {
            return mid
        }
    }
    return -(low + 1)
}

@inline(__always)
func runtimeCompareComparableValues(lhs: Int, rhs: Int) -> Int? {
    guard let lhsTypeID = runtimeObjectTypeID(rawValue: lhs),
          let rhsTypeID = runtimeObjectTypeID(rawValue: rhs),
          runtimeIsAssignable(sourceTypeID: lhsTypeID, targetTypeID: comparableRuntimeTypeID),
          runtimeIsAssignable(sourceTypeID: rhsTypeID, targetTypeID: comparableRuntimeTypeID),
          runtimeComparableOperandsAreCompatible(
              lhsTypeID: lhsTypeID,
              rhsTypeID: rhsTypeID,
              comparableTypeID: comparableRuntimeTypeID
          )
    else {
        return nil
    }

    // Comparable has a single compareTo method (method slot 0). Resolve the
    // interface slot from the object's own registration so classes that
    // implement several interfaces dispatch to the right table; hand-built
    // runtime objects without that registration keep using slot 0.
    var compareToFnPtr = kk_itable_lookup_dynamic(lhs, Int(comparableRuntimeTypeID), 0)
    if compareToFnPtr == 0 {
        compareToFnPtr = kk_itable_lookup(lhs, 0, 0)
    }
    guard compareToFnPtr != 0 else {
        return nil
    }
    // Compiler-emitted members follow the (receiver, args..., outThrown) ABI
    // and may return a boxed Int, so pass the thrown channel explicitly and
    // normalize the result instead of treating it as a bare Int.
    let compareToFn = unsafeBitCast(
        compareToFnPtr,
        to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self
    )
    var thrown = 0
    let result = compareToFn(lhs, rhs, &thrown)
    if thrown != 0 {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: Comparable.compareTo threw during a runtime comparison")
    }
    return maybeUnbox(result)
}

/// KUU-1361: dynamic `Comparator.compare(a, b)` invocation for sorted
/// collections — same itable mechanism as `runtimeCompareComparableValues`,
/// with `compare` occupying slot 0 of the `kotlin.Comparator` itable. Falls
/// back to natural ordering for objects without a registered Comparator
/// itable (e.g. raw closure boxes), and `comparatorRaw == 0` means no
/// comparator was supplied at all.
func runtimeInvokeComparator(_ comparatorRaw: Int, _ lhs: Int, _ rhs: Int) -> Int {
    guard comparatorRaw != 0 else { return runtimeCompareValues(lhs, rhs) }
    let compareFnPtr = kk_itable_lookup_dynamic(comparatorRaw, Int(comparatorRuntimeTypeID), 0)
    guard compareFnPtr != 0 else {
        return runtimeCompareValues(lhs, rhs)
    }
    let compareFn = unsafeBitCast(
        compareFnPtr,
        to: (@convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int).self
    )
    var thrown = 0
    let result = compareFn(comparatorRaw, lhs, rhs, &thrown)
    if thrown != 0 {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: Comparator.compare threw during a sorted-collection comparison")
    }
    return maybeUnbox(result)
}

enum RuntimePrimitiveCompareKind {
    case int
    case long
    case uint
    case ulong
    case boolean
    case char
    case float
    case double
}

private enum RuntimeComparableScalarValue {
    case integer(Int)
    case unsignedInteger(UInt)
    case floating(Double)
}

/// Kotlin `Double.compare` / `Float.compare` total order: NaN is greater than
/// every non-NaN, and `-0.0` sorts before `0.0`. Shared by collection
/// comparisons and `kk_compare_any` (generic `Comparable` `minOf`/`maxOf`).
func runtimeCompareFloatingValues(_ lhs: Double, _ rhs: Double) -> Int {
    if lhs.isNaN {
        return rhs.isNaN ? 0 : 1
    }
    if rhs.isNaN {
        return -1
    }
    if lhs == rhs {
        // IEEE equality treats -0.0 == 0.0, but Kotlin's `compareTo` follows
        // the `Double.compare` total order where -0.0 sorts before 0.0.
        if lhs.sign == rhs.sign {
            return 0
        }
        return lhs.sign == .minus ? -1 : 1
    }
    return lhs < rhs ? -1 : 1
}

private func runtimeComparableScalarValue(from raw: Int) -> RuntimeComparableScalarValue? {
    guard raw != runtimeNullSentinelInt else {
        return nil
    }
    guard let pointer = UnsafeMutableRawPointer(bitPattern: raw) else {
        return .integer(raw)
    }
    let isObjectPointer = runtimeStorage.withGCLock { state in
        state.objectPointers.contains(UInt(bitPattern: pointer))
    }
    guard isObjectPointer else {
        return .integer(raw)
    }
    if let floatBox = tryCast(pointer, to: RuntimeFloatBox.self) {
        return .floating(Double(floatBox.value))
    }
    if let doubleBox = tryCast(pointer, to: RuntimeDoubleBox.self) {
        return .floating(doubleBox.value)
    }
    if let intBox = tryCast(pointer, to: RuntimeIntBox.self) {
        return .integer(intBox.value)
    }
    if let boolBox = tryCast(pointer, to: RuntimeBoolBox.self) {
        return .integer(boolBox.value ? 1 : 0)
    }
    if let longBox = tryCast(pointer, to: RuntimeLongBox.self) {
        return .integer(longBox.value)
    }
    if let ulongBox = tryCast(pointer, to: RuntimeULongBox.self) {
        return .unsignedInteger(UInt(bitPattern: ulongBox.value))
    }
    if let charBox = tryCast(pointer, to: RuntimeCharBox.self) {
        return .integer(charBox.value)
    }
    return nil
}

@inline(__always)
private func runtimePrimitiveIntValue(_ raw: Int) -> Int {
    guard let pointer = UnsafeMutableRawPointer(bitPattern: raw) else {
        return raw
    }
    let isObjectPointer = runtimeStorage.withGCLock { state in
        state.objectPointers.contains(UInt(bitPattern: pointer))
    }
    guard isObjectPointer else {
        return raw
    }
    if let intBox = tryCast(pointer, to: RuntimeIntBox.self) {
        return intBox.value
    }
    if let longBox = tryCast(pointer, to: RuntimeLongBox.self) {
        return longBox.value
    }
    if let ulongBox = tryCast(pointer, to: RuntimeULongBox.self) {
        return ulongBox.value
    }
    if let boolBox = tryCast(pointer, to: RuntimeBoolBox.self) {
        return boolBox.value ? 1 : 0
    }
    if let charBox = tryCast(pointer, to: RuntimeCharBox.self) {
        return charBox.value
    }
    return raw
}

@inline(__always)
private func runtimePrimitiveFloatValue(_ raw: Int, kind: RuntimePrimitiveCompareKind) -> Double {
    guard let pointer = UnsafeMutableRawPointer(bitPattern: raw) else {
        return kind == .float ? Double(kk_bits_to_float(raw)) : kk_bits_to_double(raw)
    }
    let isObjectPointer = runtimeStorage.withGCLock { state in
        state.objectPointers.contains(UInt(bitPattern: pointer))
    }
    guard isObjectPointer else {
        return kind == .float ? Double(kk_bits_to_float(raw)) : kk_bits_to_double(raw)
    }
    if let floatBox = tryCast(pointer, to: RuntimeFloatBox.self) {
        return Double(floatBox.value)
    }
    if let doubleBox = tryCast(pointer, to: RuntimeDoubleBox.self) {
        return doubleBox.value
    }
    return kind == .float ? Double(kk_bits_to_float(raw)) : kk_bits_to_double(raw)
}

@inline(__always)
func runtimeComparePrimitiveValues(_ lhs: Int, _ rhs: Int, kind: RuntimePrimitiveCompareKind) -> Int {
    switch kind {
    case .int, .long, .boolean, .char:
        let lhsValue = runtimePrimitiveIntValue(lhs)
        let rhsValue = runtimePrimitiveIntValue(rhs)
        if lhsValue == rhsValue { return 0 }
        return lhsValue < rhsValue ? -1 : 1
    case .uint, .ulong:
        let lhsValue = UInt(bitPattern: runtimePrimitiveIntValue(lhs))
        let rhsValue = UInt(bitPattern: runtimePrimitiveIntValue(rhs))
        if lhsValue == rhsValue { return 0 }
        return lhsValue < rhsValue ? -1 : 1
    case .float, .double:
        return runtimeCompareFloatingValues(
            runtimePrimitiveFloatValue(lhs, kind: kind),
            runtimePrimitiveFloatValue(rhs, kind: kind)
        )
    }
}

/// Explicit `T.compareTo(other)` member call on a primitive `Comparable`
/// receiver (Int/Long/UInt/ULong/Boolean/Float/Double — and the signed
/// Byte/Short and unsigned UByte/UShort that share the Int ABI).
///
/// The desugared comparison operators (`<`, `>`, …) compute the comparison
/// directly via machine compare in lowering, but the *explicit* member call
/// has no per-type runtime mapping, so this entry point routes it to the same
/// `runtimeComparePrimitiveValues` helper used by primitive comparators.
/// `kindRaw` is a `PrimitiveCompareABIKind` raw value (which aligns with the
/// `RuntimePrimitiveCompareKind` ordering) selecting signed / unsigned / IEEE
/// floating semantics. The result is the sign of the comparison (-1/0/1),
/// matching `Integer.compare` / `Long.compare` / `Double.compare` — i.e.
/// Kotlin's primitive `compareTo` behavior. Char keeps its own
/// `kk_char_compareTo` entry point with the same sign-normalized result.
@_cdecl("kk_primitive_compareTo")
public func kk_primitive_compareTo(_ lhsRaw: Int, _ rhsRaw: Int, _ kindRaw: Int32) -> Int {
    runtimeComparePrimitiveValues(lhsRaw, rhsRaw, kind: runtimePrimitiveCompareKind(from: kindRaw))
}

private func runtimeStringFromRawValue(_ raw: Int) -> String? {
    if raw == runtimeNullSentinelInt {
        return nil
    }
    guard let pointer = UnsafeMutableRawPointer(bitPattern: raw) else {
        return nil
    }
    return extractString(from: pointer)
}
