let listRuntimeTypeID: Int64 = {
    var hash: UInt64 = 0xCBF2_9CE4_8422_2325
    for byte in "kotlin.collections.List".utf8 {
        hash ^= UInt64(byte)
        hash &*= 0x100_0000_01B3
    }
    let payloadMask: Int64 = (1 << 55) - 1
    let payload = Int64(bitPattern: hash) & payloadMask
    return payload == 0 ? 1 : payload
}()

private let mapEntryRuntimeTypeID: Int64 = {
    var hash: UInt64 = 0xCBF2_9CE4_8422_2325
    for byte in "kotlin.collections.Map.Entry".utf8 {
        hash ^= UInt64(byte)
        hash &*= 0x100_0000_01B3
    }
    let payloadMask: Int64 = (1 << 55) - 1
    let payload = Int64(bitPattern: hash) & payloadMask
    return payload == 0 ? 1 : payload
}()

private let comparableRuntimeTypeID: Int64 = runtimeStableNominalTypeID(fqName: "kotlin.Comparable")

@inline(__always)
func runtimeMapEntryNew(key: Int, value: Int) -> Int {
    let raw = kk_pair_new(key, value)
    runtimeRegisterObjectType(rawValue: raw, classID: mapEntryRuntimeTypeID)
    return raw
}

@inline(__always)
func runtimeIsMapEntry(rawValue: Int) -> Bool {
    runtimeObjectTypeID(rawValue: rawValue) == mapEntryRuntimeTypeID
}

func runtimeListBox(from rawValue: Int) -> RuntimeListBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: rawValue) else {
        return nil
    }
    let isObjectPointer = runtimeStorage.withGCLock { state in
        state.objectPointers.contains(UInt(bitPattern: ptr))
    }
    guard isObjectPointer else {
        return nil
    }
    return tryCast(ptr, to: RuntimeListBox.self)
}

func runtimeMapBox(from rawValue: Int) -> RuntimeMapBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: rawValue) else {
        return nil
    }
    let isObjectPointer = runtimeStorage.withGCLock { state in
        state.objectPointers.contains(UInt(bitPattern: ptr))
    }
    guard isObjectPointer else {
        return nil
    }
    return tryCast(ptr, to: RuntimeMapBox.self)
}

func runtimeSetBox(from rawValue: Int) -> RuntimeSetBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: rawValue) else {
        return nil
    }
    let isObjectPointer = runtimeStorage.withGCLock { state in
        state.objectPointers.contains(UInt(bitPattern: ptr))
    }
    guard isObjectPointer else {
        return nil
    }
    return tryCast(ptr, to: RuntimeSetBox.self)
}

func runtimeArrayDequeBox(from rawValue: Int) -> RuntimeArrayDequeBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: rawValue) else {
        return nil
    }
    let isObjectPointer = runtimeStorage.withGCLock { state in
        state.objectPointers.contains(UInt(bitPattern: ptr))
    }
    guard isObjectPointer else {
        return nil
    }
    return tryCast(ptr, to: RuntimeArrayDequeBox.self)
}

func runtimeCollectionElements(from rawValue: Int) -> [Int]? {
    if let listBox = runtimeListBox(from: rawValue) {
        return listBox.elements
    }
    if let setBox = runtimeSetBox(from: rawValue) {
        return setBox.elements
    }
    return nil
}

func runtimeCollectionValues(from rawValue: Int) -> [RuntimeValue]? {
    if let listBox = runtimeListBox(from: rawValue) {
        return listBox.values
    }
    if let setBox = runtimeSetBox(from: rawValue) {
        return setBox.values
    }
    return nil
}

func runtimeCollectionOrArrayElements(from rawValue: Int) -> [Int]? {
    if let elements = runtimeCollectionElements(from: rawValue) {
        return elements
    }
    if let arrayBox = runtimeArrayBox(from: rawValue) {
        return arrayBox.elements
    }
    return nil
}

func runtimeCollectionOrArrayValues(from rawValue: Int) -> [RuntimeValue]? {
    if let values = runtimeCollectionValues(from: rawValue) {
        return values
    }
    if let arrayBox = runtimeArrayBox(from: rawValue) {
        return arrayBox.values
    }
    return nil
}

func runtimeIterableValues(from rawValue: Int) -> [RuntimeValue]? {
    if let values = runtimeCollectionValues(from: rawValue) {
        return values
    }
    if let stringIterable = runtimeStringIterableBox(from: rawValue) {
        return stringIterable.source.utf16.map { RuntimeValue(charScalar: Int($0)) }
    }
    if let indexingIterable = runtimeIndexingIterableBox(from: rawValue),
       let list = runtimeListBox(from: indexingIterable.listRaw)
    {
        return list.values.enumerated().map { index, element in
            RuntimeValue(raw: runtimeIndexedValueNew(index: index, value: element))
        }
    }
    if let arrayBox = runtimeArrayBox(from: rawValue) {
        return arrayBox.values
    }
    if runtimeSequenceBox(from: rawValue) != nil {
        return runtimeSequenceSourceValues(from: rawValue)
    }
    return nil
}

func runtimeIterableElements(from rawValue: Int) -> [Int]? {
    runtimeIterableValues(from: rawValue)?.map(\.legacyRawValue)
}

func runtimeListIteratorBox(from rawValue: Int) -> RuntimeListIteratorBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: rawValue) else {
        return nil
    }
    let isObjectPointer = runtimeStorage.withGCLock { state in
        state.objectPointers.contains(UInt(bitPattern: ptr))
    }
    guard isObjectPointer else {
        return nil
    }
    return tryCast(ptr, to: RuntimeListIteratorBox.self)
}

func runtimeStringIteratorBox(from rawValue: Int) -> RuntimeStringIteratorBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: rawValue) else {
        return nil
    }
    let isObjectPointer = runtimeStorage.withGCLock { state in
        state.objectPointers.contains(UInt(bitPattern: ptr))
    }
    guard isObjectPointer else {
        return nil
    }
    return tryCast(ptr, to: RuntimeStringIteratorBox.self)
}

func runtimeStringIterableBox(from rawValue: Int) -> RuntimeStringIterableBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: rawValue) else {
        return nil
    }
    let isObjectPointer = runtimeStorage.withGCLock { state in
        state.objectPointers.contains(UInt(bitPattern: ptr))
    }
    guard isObjectPointer else {
        return nil
    }
    return tryCast(ptr, to: RuntimeStringIterableBox.self)
}

func runtimeIndexingIterableBox(from rawValue: Int) -> RuntimeIndexingIterableBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: rawValue) else {
        return nil
    }
    let isObjectPointer = runtimeStorage.withGCLock { state in
        state.objectPointers.contains(UInt(bitPattern: ptr))
    }
    guard isObjectPointer else {
        return nil
    }
    return tryCast(ptr, to: RuntimeIndexingIterableBox.self)
}

func runtimeMapIteratorBox(from rawValue: Int) -> RuntimeMapIteratorBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: rawValue) else {
        return nil
    }
    let isObjectPointer = runtimeStorage.withGCLock { state in
        state.objectPointers.contains(UInt(bitPattern: ptr))
    }
    guard isObjectPointer else {
        return nil
    }
    return tryCast(ptr, to: RuntimeMapIteratorBox.self)
}

func runtimeIndexingIteratorBox(from rawValue: Int) -> RuntimeIndexingIteratorBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: rawValue) else {
        return nil
    }
    let isObjectPointer = runtimeStorage.withGCLock { state in
        state.objectPointers.contains(UInt(bitPattern: ptr))
    }
    guard isObjectPointer else {
        return nil
    }
    return tryCast(ptr, to: RuntimeIndexingIteratorBox.self)
}

func runtimeMapArrayPair(
    keysRaw: Int,
    valuesRaw: Int
) -> (keys: [Int], values: [Int])? {
    guard let keysArray = runtimeArrayBox(from: keysRaw),
          let valuesArray = runtimeArrayBox(from: valuesRaw)
    else {
        return nil
    }
    return (keysArray.elements, valuesArray.elements)
}

func registerRuntimeObject(_ box: AnyObject) -> Int {
    let opaque = UnsafeMutableRawPointer(Unmanaged.passRetained(box).toOpaque())
    runtimeStorage.withGCLock { state in
        state.objectPointers.insert(UInt(bitPattern: opaque))
    }
    return Int(bitPattern: opaque)
}

func registerRuntimeObject(_ box: AnyObject, typeID: Int64) -> Int {
    let raw = registerRuntimeObject(box)
    runtimeRegisterObjectType(rawValue: raw, classID: typeID)
    return raw
}

func maybeUnbox(_ value: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: value) else {
        return value
    }
    let isObjectPointer = runtimeStorage.withGCLock { state in
        state.objectPointers.contains(UInt(bitPattern: ptr))
    }
    guard isObjectPointer else {
        return value
    }
    if let intBox = tryCast(ptr, to: RuntimeIntBox.self) {
        return intBox.value
    }
    if let boolBox = tryCast(ptr, to: RuntimeBoolBox.self) {
        return boolBox.value ? 1 : 0
    }
    if let longBox = tryCast(ptr, to: RuntimeLongBox.self) {
        return longBox.value
    }
    if let charBox = tryCast(ptr, to: RuntimeCharBox.self) {
        return charBox.value
    }
    return value
}

func runtimeNormalizeNullableCollectionValue(_ raw: Int) -> Int? {
    if raw == runtimeNullSentinelInt {
        return nil
    }
    return maybeUnbox(raw)
}

func runtimeMapNotNullResultValue(_ raw: Int) -> Int? {
    if raw == runtimeNullSentinelInt {
        return nil
    }
    return maybeUnbox(raw)
}

func runtimeValuesEqual(_ lhs: Int, _ rhs: Int) -> Bool {
    if lhs == rhs {
        return true
    }
    if lhs == runtimeNullSentinelInt || rhs == runtimeNullSentinelInt {
        return lhs == rhs
    }
    let lhsPtr = UnsafeMutableRawPointer(bitPattern: lhs)
    let rhsPtr = UnsafeMutableRawPointer(bitPattern: rhs)
    let lhsIsObjectPointer = runtimeStorage.withGCLock { state in
        lhsPtr.map { state.objectPointers.contains(UInt(bitPattern: $0)) } ?? false
    }
    let rhsIsObjectPointer = runtimeStorage.withGCLock { state in
        rhsPtr.map { state.objectPointers.contains(UInt(bitPattern: $0)) } ?? false
    }
    if lhsIsObjectPointer != rhsIsObjectPointer {
        return maybeUnbox(lhs) == maybeUnbox(rhs)
    }
    if !lhsIsObjectPointer, !rhsIsObjectPointer {
        return lhs == rhs
    }
    guard let lhsPtr, let rhsPtr else {
        return lhs == rhs
    }
    if let lhsString = tryCast(lhsPtr, to: RuntimeStringBox.self),
       let rhsString = tryCast(rhsPtr, to: RuntimeStringBox.self)
    {
        return lhsString.value == rhsString.value
    }
    if let lhsInt = tryCast(lhsPtr, to: RuntimeIntBox.self),
       let rhsInt = tryCast(rhsPtr, to: RuntimeIntBox.self)
    {
        return lhsInt.value == rhsInt.value
    }
    if let lhsBool = tryCast(lhsPtr, to: RuntimeBoolBox.self),
       let rhsBool = tryCast(rhsPtr, to: RuntimeBoolBox.self)
    {
        return lhsBool.value == rhsBool.value
    }
    if let lhsLong = tryCast(lhsPtr, to: RuntimeLongBox.self),
       let rhsLong = tryCast(rhsPtr, to: RuntimeLongBox.self)
    {
        return lhsLong.value == rhsLong.value
    }
    if let lhsFloat = tryCast(lhsPtr, to: RuntimeFloatBox.self),
       let rhsFloat = tryCast(rhsPtr, to: RuntimeFloatBox.self)
    {
        return lhsFloat.value == rhsFloat.value
    }
    if let lhsDouble = tryCast(lhsPtr, to: RuntimeDoubleBox.self),
       let rhsDouble = tryCast(rhsPtr, to: RuntimeDoubleBox.self)
    {
        return lhsDouble.value == rhsDouble.value
    }
    if let lhsChar = tryCast(lhsPtr, to: RuntimeCharBox.self),
       let rhsChar = tryCast(rhsPtr, to: RuntimeCharBox.self)
    {
        return lhsChar.value == rhsChar.value
    }
    if let lhsDuration = tryCast(lhsPtr, to: RuntimeDurationBox.self),
       let rhsDuration = tryCast(rhsPtr, to: RuntimeDurationBox.self)
    {
        return lhsDuration.nanoseconds == rhsDuration.nanoseconds
    }
    if let lhsInstant = tryCast(lhsPtr, to: RuntimeInstantBox.self),
       let rhsInstant = tryCast(rhsPtr, to: RuntimeInstantBox.self)
    {
        return lhsInstant.epochSeconds == rhsInstant.epochSeconds
            && lhsInstant.nanoOfSecond == rhsInstant.nanoOfSecond
    }
    if let lhsList = tryCast(lhsPtr, to: RuntimeListBox.self),
       let rhsList = tryCast(rhsPtr, to: RuntimeListBox.self)
    {
        let lhsElems = lhsList.elements
        let rhsElems = rhsList.elements
        guard lhsElems.count == rhsElems.count else { return false }
        for i in lhsElems.indices {
            // swiftlint:disable:next for_where
            if !runtimeValuesEqual(lhsElems[i], rhsElems[i]) {
                return false
            }
        }
        return true
    }
    if let lhsSet = tryCast(lhsPtr, to: RuntimeSetBox.self),
       let rhsSet = tryCast(rhsPtr, to: RuntimeSetBox.self)
    {
        let lhsElems = lhsSet.elements
        let rhsElems = rhsSet.elements
        guard lhsElems.count == rhsElems.count else { return false }
        for elem in lhsElems {
            // swiftlint:disable:next for_where
            if !rhsElems.contains(where: { runtimeValuesEqual($0, elem) }) {
                return false
            }
        }
        return true
    }
    if let lhsMap = tryCast(lhsPtr, to: RuntimeMapBox.self),
       let rhsMap = tryCast(rhsPtr, to: RuntimeMapBox.self)
    {
        guard lhsMap.keys.count == rhsMap.keys.count else { return false }
        for (i, lhsKey) in lhsMap.keys.enumerated() {
            guard let rhsIdx = rhsMap.keys.firstIndex(where: { runtimeValuesEqual($0, lhsKey) }) else {
                return false
            }
            if !runtimeValuesEqual(lhsMap.values[i], rhsMap.values[rhsIdx]) {
                return false
            }
        }
        return true
    }
    if let lhsLocale = tryCast(lhsPtr, to: RuntimeLocaleBox.self),
       let rhsLocale = tryCast(rhsPtr, to: RuntimeLocaleBox.self)
    {
        return lhsLocale.language == rhsLocale.language &&
            lhsLocale.country == rhsLocale.country &&
            lhsLocale.variant == rhsLocale.variant
    }
    // Data class / user-defined object structural equality: compare classID and elements.
    if let lhsObj = tryCast(lhsPtr, to: RuntimeObjectBox.self),
       let rhsObj = tryCast(rhsPtr, to: RuntimeObjectBox.self)
    {
        guard lhsObj.classID == rhsObj.classID else { return false }
        let lhsElems = lhsObj.elements
        let rhsElems = rhsObj.elements
        guard lhsElems.count == rhsElems.count else { return false }
        for i in lhsElems.indices {
            // swiftlint:disable:next for_where
            if !runtimeValuesEqual(lhsElems[i], rhsElems[i]) {
                return false
            }
        }
        return true
    }
    return lhs == rhs
}

func runtimeValuesEqual(_ lhs: RuntimeValue, _ rhs: RuntimeValue) -> Bool {
    if lhs.tag == rhs.tag {
        switch lhs.tag {
        case RuntimeValue.charTag:
            return lhs.payload0 == rhs.payload0
        case RuntimeValue.stringTag:
            guard let lhsData = UnsafePointer<UInt8>(bitPattern: lhs.payload0),
                  let rhsData = UnsafePointer<UInt8>(bitPattern: rhs.payload0)
            else {
                return lhs.payload0 == rhs.payload0
            }
            return runtimeStringFromFlatFields(
                data: lhsData,
                length: lhs.payload1,
                byteCount: lhs.payload2,
                hash: lhs.payload3
            ) == runtimeStringFromFlatFields(
                data: rhsData,
                length: rhs.payload1,
                byteCount: rhs.payload2,
                hash: rhs.payload3
            )
        default:
            return runtimeValuesEqual(lhs.payload0, rhs.payload0)
        }
    }
    return runtimeValuesEqual(lhs.legacyRawValue, rhs.legacyRawValue)
}

/// Structural equality for `==` on reference types (lists, sets, maps, boxed values).
/// Returns a boxed Bool (via kk_box_bool) so it matches the ABI of other kk_op_* functions.
@_cdecl("kk_structural_eq")
public func kk_structural_eq(_ lhs: Int, _ rhs: Int) -> Int {
    runtimeValuesEqual(lhs, rhs) ? 1 : 0
}

/// Structural inequality for `!=` on reference types.
@_cdecl("kk_structural_ne")
public func kk_structural_ne(_ lhs: Int, _ rhs: Int) -> Int {
    runtimeValuesEqual(lhs, rhs) ? 0 : 1
}

func runtimeElementToString(_ elem: Int) -> String {
    if elem == runtimeNullSentinelInt {
        return "null"
    }
    guard let ptr = UnsafeMutableRawPointer(bitPattern: elem) else {
        return "\(elem)"
    }
    let isObjectPointer = runtimeStorage.withGCLock { state in
        state.objectPointers.contains(UInt(bitPattern: ptr))
    }
    guard isObjectPointer else {
        return "\(elem)"
    }
    if let stringBox = tryCast(ptr, to: RuntimeStringBox.self) {
        return stringBox.value
    }
    if let intBox = tryCast(ptr, to: RuntimeIntBox.self) {
        return "\(intBox.value)"
    }
    if let boolBox = tryCast(ptr, to: RuntimeBoolBox.self) {
        return boolBox.value ? "true" : "false"
    }
    if let longBox = tryCast(ptr, to: RuntimeLongBox.self) {
        return "\(longBox.value)"
    }
    if let floatBox = tryCast(ptr, to: RuntimeFloatBox.self) {
        return String(floatBox.value)
    }
    if let doubleBox = tryCast(ptr, to: RuntimeDoubleBox.self) {
        return String(doubleBox.value)
    }
    if let charBox = tryCast(ptr, to: RuntimeCharBox.self) {
        return UnicodeScalar(charBox.value).map(String.init) ?? "?"
    }
    if let listBox = tryCast(ptr, to: RuntimeListBox.self) {
        let parts = listBox.values.map { runtimeElementToString($0) }
        return "[" + parts.joined(separator: ", ") + "]"
    }
    if let setBox = tryCast(ptr, to: RuntimeSetBox.self) {
        let parts = setBox.values.map { runtimeElementToString($0) }
        return "[" + parts.joined(separator: ", ") + "]"
    }
    if let mapBox = tryCast(ptr, to: RuntimeMapBox.self) {
        let parts = zip(mapBox.keyValues, mapBox.entryValues).map { key, value in
            "\(runtimeElementToString(key))=\(runtimeElementToString(value))"
        }
        return "{" + parts.joined(separator: ", ") + "}"
    }
    if let pairBox = tryCast(ptr, to: RuntimePairBox.self) {
        let first = runtimeElementToString(pairBox.firstValue)
        let second = runtimeElementToString(pairBox.secondValue)
        if runtimeIsMapEntry(rawValue: elem) {
            return "\(first)=\(second)"
        }
        if runtimeObjectTypeID(rawValue: elem) == indexedValueRuntimeTypeID {
            return "IndexedValue(index=\(first), value=\(second))"
        }
        return "(\(first), \(second))"
    }
    if let tripleBox = tryCast(ptr, to: RuntimeTripleBox.self) {
        let first = runtimeElementToString(tripleBox.first)
        let second = runtimeElementToString(tripleBox.second)
        let third = runtimeElementToString(tripleBox.third)
        return "(\(first), \(second), \(third))"
    }
    if let rangeBox = tryCast(ptr, to: RuntimeRangeBox.self) {
        let first = runtimeElementToString(rangeBox.first)
        let last = runtimeElementToString(rangeBox.last)
        if rangeBox.step == 1 {
            return "\(first)..\(last)"
        } else if rangeBox.step == -1 {
            return "\(first) downTo \(last) step 1"
        } else if rangeBox.step < 0 {
            return "\(first) downTo \(last) step \(-rangeBox.step)"
        } else {
            return "\(first)..\(last) step \(rangeBox.step)"
        }
    }
    if let arrayBox = tryCast(ptr, to: RuntimeArrayBox.self), type(of: arrayBox) == RuntimeArrayBox.self {
        let parts = arrayBox.values.map { runtimeElementToString($0) }
        return "[" + parts.joined(separator: ", ") + "]"
    }
    if let sbBox = tryCast(ptr, to: RuntimeStringBuilderBox.self) {
        return sbBox.value
    }
    if let ktypeProjectionBox = tryCast(ptr, to: RuntimeKTypeProjectionBox.self) {
        return runtimeKTypeProjectionToString(ktypeProjectionBox)
    }
    if let ktypeBox = tryCast(ptr, to: RuntimeKTypeBox.self) {
        return runtimeKTypeToString(ktypeBox)
    }
    return "\(elem)"
}

func runtimeElementToString(_ value: RuntimeValue) -> String {
    switch value.tag {
    case RuntimeValue.stringTag:
        guard let data = UnsafePointer<UInt8>(bitPattern: value.payload0) else {
            return "null"
        }
        return runtimeStringFromFlatFields(
            data: data,
            length: value.payload1,
            byteCount: value.payload2,
            hash: value.payload3
        )
    case RuntimeValue.charTag:
        return UnicodeScalar(value.payload0).map(String.init) ?? "?"
    default:
        return runtimeElementToString(value.payload0)
    }
}

// MARK: - Collection HOF Helpers (STDLIB-005)

typealias RuntimeCollectionLambda1 = @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int
typealias RuntimeCollectionLambda2 = @convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int
typealias RuntimeCollectionLambda3 = @convention(c) (Int, Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int
typealias RuntimeCollectionLambda4 = @convention(c) (Int, Int, Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int
typealias RuntimeCollectionLambda5 = @convention(c) (Int, Int, Int, Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int
/// Writes a thrown payload when the caller provided an out-thrown slot.
func runtimeSetThrown(_ outThrown: UnsafeMutablePointer<Int>?, _ value: Int) {
    outThrown?.pointee = value
}

/// Normalizes truthiness for predicates from raw/boxed Boolean values.
func runtimeCollectionBool(_ value: Int) -> Bool {
    kk_unbox_bool(value) != 0
}

@inline(__always)
func runtimeInvokeCollectionLambda1(
    fnPtr: Int,
    closureRaw: Int,
    value: Int,
    outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    let fn = unsafeBitCast(fnPtr, to: RuntimeCollectionLambda1.self)
    return fn(maybeUnbox(closureRaw), maybeUnbox(value), outThrown)
}

@inline(__always)
func runtimeInvokeCollectionLambda2(
    fnPtr: Int,
    closureRaw: Int,
    lhs: Int,
    rhs: Int,
    outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    let fn = unsafeBitCast(fnPtr, to: RuntimeCollectionLambda2.self)
    return fn(maybeUnbox(closureRaw), maybeUnbox(lhs), maybeUnbox(rhs), outThrown)
}

@inline(__always)
func runtimeInvokeCollectionLambda3(
    fnPtr: Int,
    closureRaw: Int,
    arg1: Int,
    arg2: Int,
    arg3: Int,
    outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    let fn = unsafeBitCast(fnPtr, to: RuntimeCollectionLambda3.self)
    return fn(
        maybeUnbox(closureRaw),
        maybeUnbox(arg1),
        maybeUnbox(arg2),
        maybeUnbox(arg3),
        outThrown
    )
}

@inline(__always)
func runtimeInvokeCollectionLambda4(
    fnPtr: Int,
    closureRaw: Int,
    arg1: Int,
    arg2: Int,
    arg3: Int,
    arg4: Int,
    outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    let fn = unsafeBitCast(fnPtr, to: RuntimeCollectionLambda4.self)
    return fn(
        maybeUnbox(closureRaw),
        maybeUnbox(arg1),
        maybeUnbox(arg2),
        maybeUnbox(arg3),
        maybeUnbox(arg4),
        outThrown
    )
}

@inline(__always)
func runtimeInvokeCollectionLambda5(
    fnPtr: Int,
    closureRaw: Int,
    arg1: Int,
    arg2: Int,
    arg3: Int,
    arg4: Int,
    arg5: Int,
    outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    let fn = unsafeBitCast(fnPtr, to: RuntimeCollectionLambda5.self)
    return fn(
        maybeUnbox(closureRaw),
        maybeUnbox(arg1),
        maybeUnbox(arg2),
        maybeUnbox(arg3),
        maybeUnbox(arg4),
        maybeUnbox(arg5),
        outThrown
    )
}

@inline(__always)
func runtimeInvokeClosureThunk(
    fnPtr: Int,
    closureRaw: Int,
    outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    let fn = unsafeBitCast(fnPtr, to: KKClosureThunkEntryPoint.self)
    return fn(closureRaw, outThrown)
}

func runtimeCompareValues(_ lhs: Int, _ rhs: Int) -> Int {
    if lhs == rhs {
        return 0
    }
    if let lhsString = runtimeStringFromRawValue(lhs),
       let rhsString = runtimeStringFromRawValue(rhs)
    {
        if lhsString == rhsString {
            return 0
        }
        return lhsString < rhsString ? -1 : 1
    }
    if let lhsScalar = runtimeComparableScalarValue(from: lhs),
       let rhsScalar = runtimeComparableScalarValue(from: rhs)
    {
        switch (lhsScalar, rhsScalar) {
        case let (.floating(lhsValue), .floating(rhsValue)):
            return runtimeCompareFloatingValues(lhsValue, rhsValue)
        case let (.floating(lhsValue), .integer(rhsValue)):
            return runtimeCompareFloatingValues(lhsValue, Double(rhsValue))
        case let (.integer(lhsValue), .floating(rhsValue)):
            return runtimeCompareFloatingValues(Double(lhsValue), rhsValue)
        case let (.integer(lhsValue), .integer(rhsValue)):
            if lhsValue == rhsValue {
                return 0
            }
            return lhsValue < rhsValue ? -1 : 1
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
private func runtimeCompareComparableValues(lhs: Int, rhs: Int) -> Int? {
    guard let lhsTypeID = runtimeObjectTypeID(rawValue: lhs),
          let rhsTypeID = runtimeObjectTypeID(rawValue: rhs),
          lhsTypeID == rhsTypeID,
          runtimeIsAssignable(sourceTypeID: lhsTypeID, targetTypeID: comparableRuntimeTypeID)
    else {
        return nil
    }

    // Comparable has a single compareTo method, so the first interface slot
    // is enough for direct runtime dispatch when the value's nominal type
    // implements Comparable.
    let compareToFnPtr = kk_itable_lookup(lhs, 0, 0)
    guard compareToFnPtr != 0 else {
        return nil
    }
    let compareToFn = unsafeBitCast(compareToFnPtr, to: (@convention(c) (Int, Int) -> Int).self)
    return compareToFn(lhs, rhs)
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
    case floating(Double)
}

private func runtimeCompareFloatingValues(_ lhs: Double, _ rhs: Double) -> Int {
    if lhs.isNaN {
        return rhs.isNaN ? 0 : 1
    }
    if rhs.isNaN {
        return -1
    }
    if lhs == rhs {
        return 0
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
/// Kotlin's `Comparable<T>.compareTo` contract. (Char keeps its own
/// `kk_char_compareTo` entry point, which returns the raw codepoint
/// difference to mirror `Character.compare`.)
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
