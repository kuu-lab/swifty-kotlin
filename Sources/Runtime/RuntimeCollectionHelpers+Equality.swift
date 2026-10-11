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
    // Recognize string/sequence boxes first so unrelated primitive casts do
    // not trip on object pointers whose class metadata lives in libswiftCore.
    if let stringBox = tryCast(ptr, to: RuntimeStringBox.self) {
        _ = stringBox
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
    if let ulongBox = tryCast(ptr, to: RuntimeULongBox.self) {
        return ulongBox.value
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
    // `raw` is a transform's return value, already boxed by KIR's ABILoweringPass
    // for its Any-typed return. Callers store or
    // forward this verbatim into a generically-typed collection/result, so it
    // must stay boxed here too — unboxing would strip the type tag a later
    // Boolean/Char render depends on.
    return raw
}

/// IEEE754 bit pattern of a boxed `Double`/`Float`, or nil when `raw` is not
/// one of those boxes. Unlike `maybeUnbox`, which leaves floating-point boxes
/// as pointers, this exposes the payload so a box can be compared against a
/// raw (never-boxed) floating-point word — the representation a `Double`
/// argument still has when it reaches a generic `T` parameter.
func runtimeFloatingBoxBitPattern(_ raw: Int) -> Int? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else {
        return nil
    }
    let isObjectPointer = runtimeStorage.withGCLock { state in
        state.objectPointers.contains(UInt(bitPattern: ptr))
    }
    guard isObjectPointer else {
        return nil
    }
    if let doubleBox = tryCast(ptr, to: RuntimeDoubleBox.self) {
        return Int(bitPattern: UInt(truncatingIfNeeded: doubleBox.value.bitPattern))
    }
    if let floatBox = tryCast(ptr, to: RuntimeFloatBox.self) {
        return Int(floatBox.value.bitPattern)
    }
    return nil
}

private func runtimeKTypeDescriptor(_ box: RuntimeKTypeBox) -> String? {
    guard box.typeNameRaw != 0,
          box.typeNameRaw != runtimeNullSentinelInt,
          let descriptor = extractString(from: UnsafeMutableRawPointer(bitPattern: box.typeNameRaw))
    else {
        return nil
    }
    return descriptor.hasSuffix("?") ? String(descriptor.dropLast()) : descriptor
}

private func runtimeKTypeClassifierEquals(_ lhs: RuntimeKTypeBox, _ rhs: RuntimeKTypeBox) -> Bool {
    if let lhsDescriptor = runtimeKTypeDescriptor(lhs) {
        return runtimeKTypeDescriptor(rhs) == lhsDescriptor
    }
    if runtimeKTypeDescriptor(rhs) != nil {
        return false
    }
    if let lhsClass = runtimeKClassBox(from: lhs.classifierRaw),
       let rhsClass = runtimeKClassBox(from: rhs.classifierRaw) {
        return lhsClass.typeToken == rhsClass.typeToken
    }
    return lhs.classifierRaw == rhs.classifierRaw
}

private func runtimeKTypeProjectionEquals(_ lhs: RuntimeKTypeProjectionBox, _ rhs: RuntimeKTypeProjectionBox) -> Bool {
    guard lhs.variance == rhs.variance else {
        return false
    }
    guard lhs.variance != nil else {
        return true
    }
    return runtimeValuesEqual(lhs.typeRaw, rhs.typeRaw)
}

private func runtimeKTypeEquals(_ lhs: RuntimeKTypeBox, _ rhs: RuntimeKTypeBox) -> Bool {
    guard lhs.isMarkedNullable == rhs.isMarkedNullable,
          runtimeKTypeClassifierEquals(lhs, rhs),
          lhs.argumentRaws.count == rhs.argumentRaws.count
    else {
        return false
    }
    for index in lhs.argumentRaws.indices {
        guard let lhsProjection = runtimeReflectionObject(
                  from: lhs.argumentRaws[index], as: RuntimeKTypeProjectionBox.self
              ),
              let rhsProjection = runtimeReflectionObject(
                  from: rhs.argumentRaws[index], as: RuntimeKTypeProjectionBox.self
              ),
              runtimeKTypeProjectionEquals(lhsProjection, rhsProjection)
        else {
            return false
        }
    }
    return true
}

func runtimeValuesEqual(_ lhs: Int, _ rhs: Int) -> Bool {
    if lhs == rhs {
        return true
    }
    if lhs == runtimeNullSentinelInt || rhs == runtimeNullSentinelInt {
        return lhs == rhs
    }
    return runtimeNonNullValuesEqual(lhs, rhs)
}

/// The comparison body of `runtimeValuesEqual`, minus its two callers-facing
/// shortcuts (bit-identical fast path, and the sentinel-implies-null guess).
/// Callers that have already established — via means other than guessing
/// from the raw bits, e.g. `kk_nullable_primitive_eq`'s object-pointer-registry
/// check — that neither operand is genuinely null should call this directly:
/// `runtimeValuesEqual`'s sentinel shortcut cannot tell a real null from a
/// raw (never-boxed) `Long`/`ULong` value that happens to equal the sentinel's
/// bit pattern (`Long.MIN_VALUE`, `ULong` `2^63`), so routing through it would
/// reintroduce exactly the ambiguity the caller already resolved.
func runtimeNonNullValuesEqual(_ lhs: Int, _ rhs: Int) -> Bool {
    if lhs == rhs {
        return true
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
        // Boxed Double/Float vs a raw floating-point word: compare bit
        // patterns, matching Kotlin's boxed `equals` (NaN equals NaN,
        // -0.0 does not equal 0.0). maybeUnbox leaves those boxes as
        // pointers, so it would report every such pair unequal.
        let boxedSide = lhsIsObjectPointer ? lhs : rhs
        let rawSide = lhsIsObjectPointer ? rhs : lhs
        if let bitPattern = runtimeFloatingBoxBitPattern(boxedSide) {
            return bitPattern == rawSide
        }
        return maybeUnbox(lhs) == maybeUnbox(rhs)
    }
    let lhsRange = lhsIsObjectPointer ? runtimeRangeBox(from: lhs) : nil
    let rhsRange = rhsIsObjectPointer ? runtimeRangeBox(from: rhs) : nil
    if lhsRange != nil || rhsRange != nil {
        guard let lhsRange, let rhsRange else {
            return false
        }
        return runtimeRangesEqual(lhsRange, rhsRange)
    }
    if runtimeIsUnitBox(lhs) || runtimeIsUnitBox(rhs) {
        return runtimeIsUnitBox(lhs) && runtimeIsUnitBox(rhs)
    }
    if !lhsIsObjectPointer, !rhsIsObjectPointer {
        return lhs == rhs
    }
    guard let lhsPtr, let rhsPtr else {
        return lhs == rhs
    }
    if let lhsType = tryCast(lhsPtr, to: RuntimeKTypeBox.self),
       let rhsType = tryCast(rhsPtr, to: RuntimeKTypeBox.self) {
        return runtimeKTypeEquals(lhsType, rhsType)
    }
    if let lhsProjection = tryCast(lhsPtr, to: RuntimeKTypeProjectionBox.self),
       let rhsProjection = tryCast(rhsPtr, to: RuntimeKTypeProjectionBox.self) {
        return runtimeKTypeProjectionEquals(lhsProjection, rhsProjection)
    }
    if let lhsString = tryCast(lhsPtr, to: RuntimeStringBox.self),
       let rhsString = tryCast(rhsPtr, to: RuntimeStringBox.self)
    {
        return runtimeStringsEqual(lhsString.value, rhsString.value)
    }
    if let lhsInt = tryCast(lhsPtr, to: RuntimeIntBox.self),
       let rhsInt = tryCast(rhsPtr, to: RuntimeIntBox.self)
    {
        // Enum values are represented as boxed ordinals at Any boundaries.
        // Their nominal class is part of equals semantics: Direction.NORTH
        // must not equal Color.RED merely because both have ordinal zero.
        if lhsInt.enumClassID != nil || rhsInt.enumClassID != nil {
            return lhsInt.enumClassID == rhsInt.enumClassID
                && lhsInt.value == rhsInt.value
        }
        return lhsInt.primitiveTypeBase == rhsInt.primitiveTypeBase
            && lhsInt.value == rhsInt.value
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
    if let lhsULong = tryCast(lhsPtr, to: RuntimeULongBox.self),
       let rhsULong = tryCast(rhsPtr, to: RuntimeULongBox.self)
    {
        return lhsULong.value == rhsULong.value
    }
    // Boxed floating-point equality follows Kotlin's `Double.equals`/
    // `Float.equals` (bit pattern), not IEEE `==`: NaN equals NaN and
    // -0.0 does not equal 0.0.
    if let lhsFloat = tryCast(lhsPtr, to: RuntimeFloatBox.self),
       let rhsFloat = tryCast(rhsPtr, to: RuntimeFloatBox.self)
    {
        return lhsFloat.value.bitPattern == rhsFloat.value.bitPattern
    }
    if let lhsDouble = tryCast(lhsPtr, to: RuntimeDoubleBox.self),
       let rhsDouble = tryCast(rhsPtr, to: RuntimeDoubleBox.self)
    {
        return lhsDouble.value.bitPattern == rhsDouble.value.bitPattern
    }
    if let lhsChar = tryCast(lhsPtr, to: RuntimeCharBox.self),
       let rhsChar = tryCast(rhsPtr, to: RuntimeCharBox.self)
    {
        return lhsChar.value == rhsChar.value
    }
    if let lhsDuration = tryCast(lhsPtr, to: RuntimeDurationBox.self),
       let rhsDuration = tryCast(rhsPtr, to: RuntimeDurationBox.self)
    {
        return lhsDuration.rawValue == rhsDuration.rawValue
    }
    if let lhsInstant = tryCast(lhsPtr, to: RuntimeInstantBox.self),
       let rhsInstant = tryCast(rhsPtr, to: RuntimeInstantBox.self)
    {
        return lhsInstant.epochSeconds == rhsInstant.epochSeconds
            && lhsInstant.nanoOfSecond == rhsInstant.nanoOfSecond
    }
    if let lhsList = runtimeListBox(from: lhs),
       let rhsList = runtimeListBox(from: rhs)
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
            if !rhsSet.contains(rawValue: elem) {
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
            guard let rhsIdx = rhsMap.index(ofRawKey: lhsKey),
                  let lhsValue = lhsMap.rawValue(at: i),
                  let rhsValue = rhsMap.rawValue(at: rhsIdx)
            else {
                return false
            }
            if !runtimeValuesEqual(lhsValue, rhsValue) {
                return false
            }
        }
        return true
    }
    // Only boxes tagged as kotlin.Pair/kotlin.Triple compare structurally:
    // RuntimePairBox also backs untyped internal 2-tuples (see kk_pair_new),
    // which keep reference equality.
    if runtimeObjectTypeID(rawValue: lhs) == runtimePairNominalTypeID,
       runtimeObjectTypeID(rawValue: rhs) == runtimePairNominalTypeID,
       let lhsPair = tryCast(lhsPtr, to: RuntimePairBox.self),
       let rhsPair = tryCast(rhsPtr, to: RuntimePairBox.self)
    {
        return runtimeValuesEqual(lhsPair.firstValue, rhsPair.firstValue)
            && runtimeValuesEqual(lhsPair.secondValue, rhsPair.secondValue)
    }
    if runtimeObjectTypeID(rawValue: lhs) == runtimeTripleNominalTypeID,
       runtimeObjectTypeID(rawValue: rhs) == runtimeTripleNominalTypeID,
       let lhsTriple = tryCast(lhsPtr, to: RuntimeTripleBox.self),
       let rhsTriple = tryCast(rhsPtr, to: RuntimeTripleBox.self)
    {
        return runtimeValuesEqual(lhsTriple.firstValue, rhsTriple.firstValue)
            && runtimeValuesEqual(lhsTriple.secondValue, rhsTriple.secondValue)
            && runtimeValuesEqual(lhsTriple.thirdValue, rhsTriple.thirdValue)
    }
    if let lhsLocale = tryCast(lhsPtr, to: RuntimeLocaleBox.self),
       let rhsLocale = tryCast(rhsPtr, to: RuntimeLocaleBox.self)
    {
        return lhsLocale.language == rhsLocale.language &&
            lhsLocale.country == rhsLocale.country &&
            lhsLocale.variant == rhsLocale.variant
    }
    // Nominal objects follow Any.equals: a user `equals` override wins, data
    // classes compare structurally, and plain classes compare by identity.
    if let lhsObj = tryCast(lhsPtr, to: RuntimeObjectBox.self),
       let rhsObj = tryCast(rhsPtr, to: RuntimeObjectBox.self)
    {
        if lhsObj.backingSetBox == nil, rhsObj.backingSetBox == nil {
            if let overridden = runtimeObjectEqualsOverride(lhs, rhs) {
                return overridden
            }
            guard lhsObj.classID == rhsObj.classID else { return false }
            guard runtimeIsDataClass(classID: lhsObj.classID) else { return lhs == rhs }
        }
        guard lhsObj.classID == rhsObj.classID else { return false }
        let lhsElems = lhsObj.elements
        let rhsElems = rhsObj.elements
        guard lhsElems.count == rhsElems.count else { return false }
        let fieldMask = runtimeDataClassFieldMask(classID: lhsObj.classID)
        for i in lhsElems.indices {
            if let fieldMask, i < 63, fieldMask & (1 << Int64(i)) == 0 { continue }
            // swiftlint:disable:next for_where
            if !runtimeValuesEqual(lhsElems[i], rhsElems[i]) {
                return false
            }
        }
        return true
    }
    return lhs == rhs
}

/// Kotlin stdlib bridge for structural equality of raw runtime values.
@_cdecl("__kk_values_equal")
public func __kk_values_equal(_ lhs: Int, _ rhs: Int) -> Int {
    kk_box_bool(runtimeValuesEqual(lhs, rhs) ? 1 : 0)
}

/// Calls the user `Any.equals` override registered for `lhs`, if any.
func runtimeObjectEqualsOverride(_ lhs: Int, _ rhs: Int) -> Bool? {
    guard let lhsPtr = UnsafeMutableRawPointer(bitPattern: lhs),
          let functionRaw = runtimeStorage.withMetadataLock({ state in
              state.objectEqualsOverrides[UInt(bitPattern: lhsPtr)]
          })
    else {
        return nil
    }
    let equals = unsafeBitCast(
        functionRaw,
        to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self
    )
    return equals(lhs, rhs, nil) != 0
}

/// Calls the user `Any.hashCode` override registered for `value`, if any.
func runtimeObjectHashCodeOverride(_ value: Int) -> Int? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: value),
          let functionRaw = runtimeStorage.withMetadataLock({ state in
              state.objectHashCodeOverrides[UInt(bitPattern: ptr)]
          })
    else {
        return nil
    }
    let hashCode = unsafeBitCast(
        functionRaw,
        to: (@convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int).self
    )
    return Int(Int32(truncatingIfNeeded: hashCode(value, nil)))
}

/// Applies Kotlin's reference-equality default to RuntimeObjectBox values while
/// retaining structural equality for data classes and collection/value boxes.
/// Returns nil when either operand is not a nominal runtime object, allowing
/// callers to fall back to `runtimeValuesEqual` for the other runtime types.
func runtimeAnyObjectEquality(_ lhs: Int, _ rhs: Int) -> Bool? {
    guard let lhsPtr = UnsafeMutableRawPointer(bitPattern: lhs)
    else {
        return nil
    }
    let lhsIsRegisteredObject = runtimeStorage.withGCLock { state in
        state.objectPointers.contains(UInt(bitPattern: lhsPtr))
    }
    guard lhsIsRegisteredObject,
          let lhsObject = tryCast(lhsPtr, to: RuntimeObjectBox.self)
    else {
        return nil
    }

    if let overridden = runtimeObjectEqualsOverride(lhs, rhs) {
        return overridden
    }

    guard let rhsPtr = UnsafeMutableRawPointer(bitPattern: rhs),
          runtimeStorage.withGCLock({ state in
              state.objectPointers.contains(UInt(bitPattern: rhsPtr))
          }),
          let rhsObject = tryCast(rhsPtr, to: RuntimeObjectBox.self)
    else {
        return false
    }

    guard lhsObject.classID == rhsObject.classID else {
        return false
    }
    guard runtimeIsDataClass(classID: lhsObject.classID) else {
        return lhs == rhs
    }
    return runtimeValuesEqual(lhs, rhs)
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
            return runtimeStringsEqual(
                runtimeStringFromFlatFields(
                    data: lhsData,
                    length: lhs.payload1,
                    byteCount: lhs.payload2,
                    hash: lhs.payload3
                ),
                runtimeStringFromFlatFields(
                    data: rhsData,
                    length: rhs.payload1,
                    byteCount: rhs.payload2,
                    hash: rhs.payload3
                )
            )
        default:
            return runtimeValuesEqual(lhs.payload0, rhs.payload0)
        }
    }
    return runtimeValuesEqual(lhs.legacyRawValue, rhs.legacyRawValue)
}

/// Equality for `==` on runtime reference values.
/// Collection/value boxes remain structural, while ordinary nominal objects use Any.equals semantics.
/// Returns a boxed Bool (via kk_box_bool) so it matches the ABI of other kk_op_* functions.
@_cdecl("kk_structural_eq")
public func kk_structural_eq(_ lhs: Int, _ rhs: Int) -> Int {
    (runtimeAnyObjectEquality(lhs, rhs) ?? runtimeValuesEqual(lhs, rhs)) ? 1 : 0
}

/// Inequality for `!=` on runtime reference values.
@_cdecl("kk_structural_ne")
public func kk_structural_ne(_ lhs: Int, _ rhs: Int) -> Int {
    (runtimeAnyObjectEquality(lhs, rhs) ?? runtimeValuesEqual(lhs, rhs)) ? 0 : 1
}

/// Null-aware equality for `==`/`!=` where at least one operand is a
/// nullable `Long`/`ULong`/`Double`/`Float`. Those are the only primitives
/// whose full raw (unboxed) value range coincides with the runtime null
/// sentinel (`Long.MIN_VALUE`, `ULong` `2^63`, `-0.0`'s bit pattern), so
/// `kk_structural_eq`/`ne`'s "raw value equals the sentinel implies null"
/// guess (in `runtimeValuesEqual`) cannot tell a genuine null apart from a
/// genuine value that happens to share that bit pattern.
///
/// `nullableRaw` is the operand statically known to be nullable. Its slot
/// holds the null sentinel, a registered box, or a raw value (external
/// `Long?`-returning entries such as `__kk_long_range_randomOrNull_random`
/// pass raw bits through unchanged), so only the sentinel itself marks
/// null — a registry membership test would misclassify every raw non-null
/// value as null. A raw value that equals the sentinel's bit pattern
/// (e.g. a `Long?` slot holding `Long.MIN_VALUE` unboxed) stays
/// indistinguishable from null at the bit level; preserving its non-null
/// identity is the boxing side's job, not this comparison's.  `peerRaw` is
/// the other operand — a provably non-null value if `peerIsNullable == 0`
/// (its raw bits are never treated as a possible null, so a peer holding
/// raw `Long.MIN_VALUE` still compares by value), otherwise checked for
/// the sentinel the same way as `nullableRaw`. Once neither side is null,
/// the comparison defers to `runtimeNonNullValuesEqual`, which already
/// normalizes boxed-vs-raw pairs (e.g. a boxed `Long.MIN_VALUE` against
/// the raw literal `Long.MIN_VALUE`).
private func runtimeNullablePrimitiveEqualityCheck(
    nullableRaw: Int,
    peerRaw: Int,
    peerIsNullable: Int
) -> Bool {
    if peerIsNullable >= 2 {
        // Kotlin `P? == P` on floating point is IEEE-754 once nullness is
        // ruled out (`-0.0 == 0.0`, `NaN != NaN`) — not the boxed `equals`
        // bit-pattern compare runtimeNonNullValuesEqual uses. Flags 2/3 mark
        // a provably non-null raw Double/Float peer; 4/5 mark a Double?/
        // Float? slot whose sentinel still means null. The operands may be
        // raw words or registered (possibly tagged) boxes;
        // runtimeFloatingBoxBitPattern exposes a box's payload and a raw
        // non-null word passes through as its own bit pattern.
        let nullableIsNull = nullableRaw == runtimeNullSentinelInt
        let peerIsNull = (peerIsNullable == 4 || peerIsNullable == 5)
            && peerRaw == runtimeNullSentinelInt
        if nullableIsNull || peerIsNull {
            return nullableIsNull && peerIsNull
        }
        let lhsBits = runtimeFloatingBoxBitPattern(nullableRaw) ?? nullableRaw
        let rhsBits = runtimeFloatingBoxBitPattern(peerRaw) ?? peerRaw
        if peerIsNullable == 2 || peerIsNullable == 4 {
            return Double(bitPattern: UInt64(bitPattern: Int64(lhsBits)))
                == Double(bitPattern: UInt64(bitPattern: Int64(rhsBits)))
        }
        return Float(bitPattern: UInt32(truncatingIfNeeded: lhsBits))
            == Float(bitPattern: UInt32(truncatingIfNeeded: rhsBits))
    }
    let nullableIsNull = nullableRaw == runtimeNullSentinelInt
    let peerIsNull = peerIsNullable != 0 && peerRaw == runtimeNullSentinelInt
    if nullableIsNull || peerIsNull {
        return nullableIsNull && peerIsNull
    }
    return runtimeNonNullValuesEqual(nullableRaw, peerRaw)
}

@_cdecl("kk_nullable_primitive_eq")
public func kk_nullable_primitive_eq(_ nullableRaw: Int, _ peerRaw: Int, _ peerIsNullable: Int) -> Int {
    runtimeNullablePrimitiveEqualityCheck(nullableRaw: nullableRaw, peerRaw: peerRaw, peerIsNullable: peerIsNullable) ? 1 : 0
}

@_cdecl("kk_nullable_primitive_ne")
public func kk_nullable_primitive_ne(_ nullableRaw: Int, _ peerRaw: Int, _ peerIsNullable: Int) -> Int {
    runtimeNullablePrimitiveEqualityCheck(nullableRaw: nullableRaw, peerRaw: peerRaw, peerIsNullable: peerIsNullable) ? 0 : 1
}
