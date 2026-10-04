
@_cdecl("kk_box_unit")
public func kk_box_unit(_ value: Int) -> Int {
    _ = value
    return runtimeStorage.withGCLock { state in
        if let pointer = state.unitBoxPointer {
            return Int(bitPattern: pointer)
        }

        // Boxed Unit is a singleton at every Any/reference boundary.
        let box = RuntimeUnitBox()
        let opaque = UnsafeMutableRawPointer(Unmanaged.passRetained(box).toOpaque())
        let pointer = UInt(bitPattern: opaque)
        state.objectPointers.insert(pointer)
        state.unitBoxPointer = pointer
        return Int(bitPattern: pointer)
    }
}

/// Boxes a primitive under a single `withGCLock` critical section: the
/// already-registered pass-through probe and the fresh box's registration
/// share one acquisition. Boxing is a hot ABI path, so paying two GC-lock
/// round trips per call would double contention on the global lock.
///
/// `registeredPassThrough` refines the pass-through condition once the value
/// is known to be a registered object pointer (e.g. Float only passes through
/// a RuntimeFloatBox, not an unrelated registered handle).
///
/// Fresh boxes are registered under a tagged primitive-box handle (the same
/// representation `runtimeStaticBox` emits), not their raw object pointer.
/// The pass-through probe cannot distinguish "an already-boxed handle" from
/// "a raw scalar that happens to equal a live object's address": if a scalar
/// ever collided with a registered box's raw address, the raw scalar would be
/// passed through and the paired unbox would then read the *other* box's
/// payload as the value (KUU-857 — intermittent wrong sums in DeepRecursive
/// on Linux, where a sum of 41582640 equalled a live RuntimeIntBox address).
/// Tagged handles live in a reserved high-bit domain that real scalar values
/// and raw object addresses cannot reach, so the collision class is closed.
@inline(__always)
private func runtimeBoxPrimitive<T: AnyObject>(
    _ value: Int,
    preservesNullSentinel: Bool = true,
    registeredPassThrough: (UnsafeMutableRawPointer) -> Bool = { _ in true },
    makeBox: () -> T
) -> Int {
    if preservesNullSentinel, value == runtimeNullSentinelInt {
        return value
    }
    return runtimeStorage.withGCLock { state in
        if let objectPointer = UnsafeMutableRawPointer(bitPattern: value),
           state.objectPointers.contains(UInt(bitPattern: objectPointer)),
           registeredPassThrough(objectPointer)
        {
            return value
        }
        return registerTaggedPrimitiveBox(makeBox(), inLockedState: &state)
    }
}

private func runtimeBoxInt(_ value: Int, anyFallbackTag: Int32) -> Int {
    // If the value is already a registered runtime object (e.g. RuntimeRangeBox
    // produced by kk_op_rangeTo, or an already-boxed RuntimeIntBox), pass it
    // through without double-boxing.
    runtimeBoxPrimitive(value) {
        RuntimeIntBox(value, anyFallbackTag: anyFallbackTag)
    }
}

@inline(__always)
private func runtimeStaticBox<T: AnyObject>(
    _ value: Int,
    preservesNullSentinel: Bool,
    makeBox: () -> T
) -> Int {
    if preservesNullSentinel, value == runtimeNullSentinelInt {
        return value
    }
    return runtimeStorage.withGCLock { state in
        // Some runtime values use a primitive ABI type while carrying a registered
        // object handle at runtime (for example RuntimeRangeBox and coroutine
        // handles). Preserve those handles exactly as the legacy boxing entry
        // points do; wrapping them in a primitive box would make the downstream
        // object-specific runtime entry point reject the value.
        if let objectPointer = UnsafeMutableRawPointer(bitPattern: value),
           state.objectPointers.contains(UInt(bitPattern: objectPointer))
        {
            return value
        }
        // A tagged handle is already the result of this fast path. Keeping this
        // check makes the helper idempotent for compiler-generated value flows
        // without reintroducing the object registry lookup used by the legacy ABI.
        if runtimePrimitiveBoxBasePointer(from: value) != nil {
            return value
        }
        return registerTaggedPrimitiveBox(makeBox(), inLockedState: &state)
    }
}

@inline(__always)
private func runtimeStaticUnbox<T: AnyObject>(
    _ value: Int,
    fallback: () -> Int,
    as type: T.Type,
    extract: (T) -> Int
) -> Int {
    guard let pointer = runtimePrimitiveBoxBasePointer(from: value) else {
        return fallback()
    }
    // `runtimePrimitiveBoxBasePointer` only checks the tag bit pattern, which
    // an unrelated Int (a hash code, uninitialized memory, ...) can
    // coincidentally match. Unlike `tryCast`'s other callers, this entry
    // point receives a raw handle straight from the ABI boundary with no
    // prior verification, so it must confirm registry membership itself
    // before treating `pointer` as a live object — otherwise a collision
    // reinterprets unrelated bits as an `Unmanaged<AnyObject>` and crashes.
    let isRegisteredHandle = runtimeStorage.withGCLock { state in
        state.objectPointers.contains(UInt(bitPattern: value))
    }
    guard isRegisteredHandle else {
        return fallback()
    }
    // The tag is emitted only for a statically-known primitive box. If a
    // malformed or mismatched handle reaches this helper, retain the legacy
    // registry-checked behavior as a safe fallback.
    guard let box = tryCast(pointer, to: type) else {
        return fallback()
    }
    return extract(box)
}

@_cdecl("kk_box_int")
public func kk_box_int(_ value: Int) -> Int {
    runtimeBoxInt(value, anyFallbackTag: 1)
}

@_cdecl("kk_box_uint")
public func kk_box_uint(_ value: Int) -> Int {
    runtimeBoxInt(value, anyFallbackTag: 9)
}

@_cdecl("kk_box_ubyte")
public func kk_box_ubyte(_ value: Int) -> Int {
    runtimeBoxInt(value, anyFallbackTag: 10)
}

@_cdecl("kk_box_ushort")
public func kk_box_ushort(_ value: Int) -> Int {
    runtimeBoxInt(value, anyFallbackTag: 11)
}

@_cdecl("kk_box_bool")
public func kk_box_bool(_ value: Int) -> Int {
    // If the value is already a registered runtime object (e.g. a Boolean
    // returned by a runtime helper that already boxed it), pass it through
    // without double-boxing so source-level println() preserves the value.
    runtimeBoxPrimitive(value) {
        RuntimeBoolBox(value != 0)
    }
}

@_cdecl("kk_lateinit_is_initialized")
public func kk_lateinit_is_initialized(_ value: Int) -> Int {
    kk_box_bool(value != runtimeNullSentinelInt ? 1 : 0)
}

@_cdecl("kk_lateinit_get_or_throw")
public func kk_lateinit_get_or_throw(
    _ value: Int,
    _ propertyName: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard value == runtimeNullSentinelInt else {
        return value
    }
    let name = extractString(from: UnsafeMutableRawPointer(bitPattern: propertyName)) ?? "<unknown>"
    outThrown?.pointee = runtimeAllocateUninitializedPropertyAccessException(
        message: "lateinit property \(name) has not been initialized"
    )
    return runtimeNullSentinelInt
}

@_cdecl("kk_unbox_int")
public func kk_unbox_int(_ obj: Int) -> Int {
    if obj == runtimeNullSentinelInt {
        return 0
    }
    guard let objPointer = UnsafeMutableRawPointer(bitPattern: obj) else {
        return obj
    }
    let isObjectPointer = runtimeStorage.withGCLock { state in
        state.objectPointers.contains(UInt(bitPattern: objPointer))
    }
    guard isObjectPointer else {
        return obj
    }
    if let intBox = tryCast(objPointer, to: RuntimeIntBox.self) {
        return intBox.value
    }
    return obj
}

@_cdecl("kk_unbox_bool")
public func kk_unbox_bool(_ obj: Int) -> Int {
    if obj == runtimeNullSentinelInt {
        return 0
    }
    guard let objPointer = UnsafeMutableRawPointer(bitPattern: obj) else {
        return obj != 0 ? 1 : 0
    }
    let isObjectPointer = runtimeStorage.withGCLock { state in
        state.objectPointers.contains(UInt(bitPattern: objPointer))
    }
    guard isObjectPointer else {
        return obj != 0 ? 1 : 0
    }
    if let boolBox = tryCast(objPointer, to: RuntimeBoolBox.self) {
        return boolBox.value ? 1 : 0
    }
    return obj != 0 ? 1 : 0
}

@_cdecl("kk_box_long")
public func kk_box_long(_ value: Int) -> Int {
    // Callers whose source may genuinely be null (e.g. a nullable Long?
    // flowing into an Any?-typed argument) rely on the sentinel pass-through
    // to preserve null — see kk_box_long_nonnull below for the
    // counterpart used when the source's static type is provably non-null.
    // If the value is already a registered runtime object (e.g. RuntimeRangeBox
    // produced by kk_op_rangeTo for LongRange), pass it through without
    // double-boxing so that __kk_print_raw / runtimeElementToString can
    // recognise the original object type.
    return runtimeBoxPrimitive(value) {
        RuntimeLongBox(value)
    }
}

/// Boxes a Long known (via static typing) to be non-null. Unlike kk_box_long,
/// this does NOT special-case runtimeNullSentinelInt (Int64.min): for a
/// non-null Long source, that bit pattern is the legitimate value
/// Long.MIN_VALUE, not null, so short-circuiting it would silently corrupt
/// that one value (wrong toString/equals/`is`). BoxingCalleeTable selects
/// this callee only when the source type's nullability is provably
/// `.nonNull`, so a genuine null can never reach this function.
@_cdecl("kk_box_long_nonnull")
public func kk_box_long_nonnull(_ value: Int) -> Int {
    runtimeBoxPrimitive(value, preservesNullSentinel: false) {
        RuntimeLongBox(value)
    }
}

@_cdecl("kk_unbox_long")
public func kk_unbox_long(_ obj: Int) -> Int {
    // NOTE: no early-return for runtimeNullSentinelInt (Int64.min == Long.MIN_VALUE).
    // runtimeNullSentinelInt is never a valid heap pointer, so it reaches the
    // passthrough branch below and returns Int.min (= Long.MIN_VALUE) correctly.
    // Returning 0 here was wrong: it caused Double.NEGATIVE_INFINITY.roundToLong()
    // to produce 0 instead of Long.MIN_VALUE (__kk_double_roundToLong returns Int.min
    // raw, which the KIR passes through kk_unbox_long).
    guard let objPointer = UnsafeMutableRawPointer(bitPattern: obj) else { return 0 }
    let isObjectPointer = runtimeStorage.withGCLock { state in
        state.objectPointers.contains(UInt(bitPattern: objPointer))
    }
    // Passthrough: value is not a heap object — treat as raw int (implicit widening)
    guard isObjectPointer else { return obj }
    if let longBox = tryCast(objPointer, to: RuntimeLongBox.self) {
        return longBox.value
    }
    // Object pointer that isn't a LongBox — box/unbox type mismatch
    #if DEBUG
    print("KSwiftK warning [\(runtimePanicDiagnosticCode)]: kk_unbox_long called on non-LongBox object (0x\(String(obj, radix: 16)))")
    #endif
    return obj
}

@_cdecl("kk_box_ulong")
public func kk_box_ulong(_ value: Int) -> Int {
    // See kk_box_long: callers whose source may genuinely be null rely on
    // the sentinel pass-through. kk_box_ulong_nonnull is the counterpart used
    // when the source's static type is provably non-null.
    // If the value is already a registered runtime object, pass it through
    // without double-boxing (mirrors kk_box_long).
    return runtimeBoxPrimitive(value) {
        RuntimeULongBox(value)
    }
}

/// Boxes a ULong known (via static typing) to be non-null. Unlike
/// kk_box_ulong, this does NOT special-case runtimeNullSentinelInt
/// (Int64.min): for a non-null ULong source, that bit pattern is the
/// legitimate value 2^63 — an ordinary value in the middle of the valid
/// range, not null — so short-circuiting it would silently corrupt that one
/// value (wrong toString/equals/`is`). BoxingCalleeTable selects this callee
/// only when the source type's nullability is provably `.nonNull`, so a
/// genuine null can never reach this function.
@_cdecl("kk_box_ulong_nonnull")
public func kk_box_ulong_nonnull(_ value: Int) -> Int {
    runtimeBoxPrimitive(value, preservesNullSentinel: false) {
        RuntimeULongBox(value)
    }
}

@_cdecl("kk_unbox_ulong")
public func kk_unbox_ulong(_ obj: Int) -> Int {
    // NOTE: no early-return for runtimeNullSentinelInt — see kk_unbox_long.
    guard let objPointer = UnsafeMutableRawPointer(bitPattern: obj) else { return 0 }
    let isObjectPointer = runtimeStorage.withGCLock { state in
        state.objectPointers.contains(UInt(bitPattern: objPointer))
    }
    // Passthrough: value is not a heap object — treat as raw int (implicit widening)
    guard isObjectPointer else { return obj }
    if let ulongBox = tryCast(objPointer, to: RuntimeULongBox.self) {
        return ulongBox.value
    }
    // Object pointer that isn't a ULongBox — box/unbox type mismatch
    #if DEBUG
    print("KSwiftK warning [\(runtimePanicDiagnosticCode)]: kk_unbox_ulong called on non-ULongBox object (0x\(String(obj, radix: 16)))")
    #endif
    return obj
}

@_cdecl("kk_box_float")
public func kk_box_float(_ value: Int) -> Int {
    // Preserve an already boxed Float, but do not treat an unrelated runtime
    // object handle as a boxed Float. Primitive Float values use raw IEEE-754
    // bits, so pass-through must be type-specific at this boundary.
    let floatBits = Float(bitPattern: UInt32(truncatingIfNeeded: value))
    return runtimeBoxPrimitive(
        value,
        registeredPassThrough: { tryCast($0, to: RuntimeFloatBox.self) != nil }
    ) {
        RuntimeFloatBox(floatBits)
    }
}

@_cdecl("kk_unbox_float")
public func kk_unbox_float(_ obj: Int) -> Int {
    if obj == runtimeNullSentinelInt { return 0 }
    guard let objPointer = UnsafeMutableRawPointer(bitPattern: obj) else { return obj }
    let isObjectPointer = runtimeStorage.withGCLock { state in
        state.objectPointers.contains(UInt(bitPattern: objPointer))
    }
    guard isObjectPointer else { return obj }
    if let floatBox = tryCast(objPointer, to: RuntimeFloatBox.self) {
        return Int(floatBox.value.bitPattern)
    }
    #if DEBUG
    print("KSwiftK warning [\(runtimePanicDiagnosticCode)]: kk_unbox_float called on non-FloatBox object (0x\(String(obj, radix: 16)))")
    #endif
    return obj
}

@_cdecl("kk_box_double")
public func kk_box_double(_ value: Int) -> Int {
    // Callers whose source may genuinely be null rely on the sentinel
    // pass-through — see kk_box_double_nonnull below for the counterpart used
    // when the source's static type is provably non-null.
    // A nullable Double? read out of a generic container is already a
    // RuntimeDoubleBox pointer; re-boxing it would reinterpret the pointer
    // as an IEEE754 payload (mirrors kk_box_int / kk_box_long).
    let doubleBits = Double(bitPattern: UInt64(bitPattern: Int64(value)))
    return runtimeBoxPrimitive(value) {
        RuntimeDoubleBox(doubleBits)
    }
}

/// Boxes a Double known (via static typing) to be non-null. Unlike
/// kk_box_double, this does NOT special-case runtimeNullSentinelInt
/// (Int64.min): that bit pattern is the IEEE754 encoding of -0.0, a
/// legitimate Double value, so short-circuiting it would make every boxed
/// -0.0 indistinguishable from null (wrong toString/equals/`is`).
/// BoxingCalleeTable selects this callee only when the source type's
/// nullability is provably `.nonNull`, so a genuine null can never reach
/// this function.
@_cdecl("kk_box_double_nonnull")
public func kk_box_double_nonnull(_ value: Int) -> Int {
    let doubleBits = Double(bitPattern: UInt64(bitPattern: Int64(value)))
    return runtimeBoxPrimitive(value, preservesNullSentinel: false) {
        RuntimeDoubleBox(doubleBits)
    }
}

@_cdecl("kk_unbox_double")
public func kk_unbox_double(_ obj: Int) -> Int {
    if obj == runtimeNullSentinelInt { return 0 }
    guard let objPointer = UnsafeMutableRawPointer(bitPattern: obj) else { return obj }
    let isObjectPointer = runtimeStorage.withGCLock { state in
        state.objectPointers.contains(UInt(bitPattern: objPointer))
    }
    guard isObjectPointer else { return obj }
    if let doubleBox = tryCast(objPointer, to: RuntimeDoubleBox.self) {
        return Int(bitPattern: UInt(truncatingIfNeeded: doubleBox.value.bitPattern))
    }
    #if DEBUG
    print("KSwiftK warning [\(runtimePanicDiagnosticCode)]: kk_unbox_double called on non-DoubleBox object (0x\(String(obj, radix: 16)))")
    #endif
    return obj
}

@_cdecl("kk_box_char")
public func kk_box_char(_ value: Int) -> Int {
    // If the value is already a registered runtime object, pass it through
    // without double-boxing.
    return runtimeBoxPrimitive(value) {
        RuntimeCharBox(value)
    }
}

@_cdecl("kk_unbox_char")
public func kk_unbox_char(_ obj: Int) -> Int {
    if obj == runtimeNullSentinelInt { return 0 }
    guard let objPointer = UnsafeMutableRawPointer(bitPattern: obj) else { return obj }
    let isObjectPointer = runtimeStorage.withGCLock { state in
        state.objectPointers.contains(UInt(bitPattern: objPointer))
    }
    guard isObjectPointer else { return obj }
    if let charBox = tryCast(objPointer, to: RuntimeCharBox.self) {
        return charBox.value
    }
    #if DEBUG
    print("KSwiftK warning [\(runtimePanicDiagnosticCode)]: kk_unbox_char called on non-CharBox object (0x\(String(obj, radix: 16)))")
    #endif
    return obj
}

// MARK: - Statically-known primitive ABI fast paths
//
// These entry points are selected by ABILoweringPass only when the source or
// target primitive type is known at compile time. They preserve the canonical
// Swift ARC box and objectPointers registration from ARCH-015, but tag the
// handle so the paired unbox can avoid the registry lock. The legacy entry
// points above remain the compatibility path for ambiguous runtime values.

@_cdecl("kk_box_int_static")
public func kk_box_int_static(_ value: Int) -> Int {
    runtimeStaticBox(value, preservesNullSentinel: true) {
        RuntimeIntBox(value, anyFallbackTag: 1)
    }
}

@_cdecl("kk_box_uint_static")
public func kk_box_uint_static(_ value: Int) -> Int {
    runtimeStaticBox(value, preservesNullSentinel: true) {
        RuntimeIntBox(value, anyFallbackTag: 9)
    }
}

@_cdecl("kk_box_ubyte_static")
public func kk_box_ubyte_static(_ value: Int) -> Int {
    runtimeStaticBox(value, preservesNullSentinel: true) {
        RuntimeIntBox(value, anyFallbackTag: 10)
    }
}

@_cdecl("kk_box_ushort_static")
public func kk_box_ushort_static(_ value: Int) -> Int {
    runtimeStaticBox(value, preservesNullSentinel: true) {
        RuntimeIntBox(value, anyFallbackTag: 11)
    }
}

@_cdecl("kk_box_bool_static")
public func kk_box_bool_static(_ value: Int) -> Int {
    runtimeStaticBox(value, preservesNullSentinel: true) {
        RuntimeBoolBox(value != 0)
    }
}

@_cdecl("kk_box_long_static")
public func kk_box_long_static(_ value: Int) -> Int {
    runtimeStaticBox(value, preservesNullSentinel: true) {
        RuntimeLongBox(value)
    }
}

@_cdecl("kk_box_long_nonnull_static")
public func kk_box_long_nonnull_static(_ value: Int) -> Int {
    runtimeStaticBox(value, preservesNullSentinel: false) {
        RuntimeLongBox(value)
    }
}

@_cdecl("kk_box_ulong_static")
public func kk_box_ulong_static(_ value: Int) -> Int {
    runtimeStaticBox(value, preservesNullSentinel: true) {
        RuntimeULongBox(value)
    }
}

@_cdecl("kk_box_ulong_nonnull_static")
public func kk_box_ulong_nonnull_static(_ value: Int) -> Int {
    runtimeStaticBox(value, preservesNullSentinel: false) {
        RuntimeULongBox(value)
    }
}

@_cdecl("kk_box_float_static")
public func kk_box_float_static(_ value: Int) -> Int {
    runtimeStaticBox(value, preservesNullSentinel: true) {
        RuntimeFloatBox(Float(bitPattern: UInt32(truncatingIfNeeded: value)))
    }
}

@_cdecl("kk_box_double_static")
public func kk_box_double_static(_ value: Int) -> Int {
    runtimeStaticBox(value, preservesNullSentinel: true) {
        RuntimeDoubleBox(Double(bitPattern: UInt64(bitPattern: Int64(value))))
    }
}

@_cdecl("kk_box_double_nonnull_static")
public func kk_box_double_nonnull_static(_ value: Int) -> Int {
    runtimeStaticBox(value, preservesNullSentinel: false) {
        RuntimeDoubleBox(Double(bitPattern: UInt64(bitPattern: Int64(value))))
    }
}

@_cdecl("kk_box_char_static")
public func kk_box_char_static(_ value: Int) -> Int {
    runtimeStaticBox(value, preservesNullSentinel: true) {
        RuntimeCharBox(value)
    }
}

@_cdecl("kk_unbox_int_static")
public func kk_unbox_int_static(_ value: Int) -> Int {
    runtimeStaticUnbox(value, fallback: { kk_unbox_int(value) }, as: RuntimeIntBox.self, extract: \.value)
}

@_cdecl("kk_unbox_bool_static")
public func kk_unbox_bool_static(_ value: Int) -> Int {
    runtimeStaticUnbox(value, fallback: { kk_unbox_bool(value) }, as: RuntimeBoolBox.self) { $0.value ? 1 : 0 }
}

@_cdecl("kk_unbox_long_static")
public func kk_unbox_long_static(_ value: Int) -> Int {
    runtimeStaticUnbox(value, fallback: { kk_unbox_long(value) }, as: RuntimeLongBox.self, extract: \.value)
}

@_cdecl("kk_unbox_ulong_static")
public func kk_unbox_ulong_static(_ value: Int) -> Int {
    runtimeStaticUnbox(value, fallback: { kk_unbox_ulong(value) }, as: RuntimeULongBox.self, extract: \.value)
}

@_cdecl("kk_unbox_float_static")
public func kk_unbox_float_static(_ value: Int) -> Int {
    runtimeStaticUnbox(
        value,
        fallback: { kk_unbox_float(value) },
        as: RuntimeFloatBox.self,
        extract: { Int($0.value.bitPattern) }
    )
}

@_cdecl("kk_unbox_double_static")
public func kk_unbox_double_static(_ value: Int) -> Int {
    runtimeStaticUnbox(
        value,
        fallback: { kk_unbox_double(value) },
        as: RuntimeDoubleBox.self,
        extract: { Int(bitPattern: UInt(truncatingIfNeeded: $0.value.bitPattern)) }
    )
}

@_cdecl("kk_unbox_char_static")
public func kk_unbox_char_static(_ value: Int) -> Int {
    runtimeStaticUnbox(value, fallback: { kk_unbox_char(value) }, as: RuntimeCharBox.self, extract: \.value)
}

/// Tags a primitive box (produced by kk_box_int/kk_box_long/kk_box_bool/
/// kk_box_float/kk_box_double/kk_box_char) with the stable nominal type ID of
/// the value class it represents. Value classes are unboxed to their
/// underlying primitive everywhere except at reference-type boundaries
/// (Any, generics, interfaces), where ABILoweringPass emits this call right
/// after the primitive box call. Without this tag the boxed pointer is
/// indistinguishable from a plain boxed primitive, so `is`/`as`/
/// `KClass.isInstance` against the value class name would incorrectly fail
/// (and against the underlying primitive name would incorrectly succeed) —
/// see kk_op_is's nominalBase and primitive-base cases.
@_cdecl("kk_tag_value_class_box")
public func kk_tag_value_class_box(_ boxedRaw: Int, _ classID: Int) -> Int {
    guard boxedRaw != runtimeNullSentinelInt else { return boxedRaw }
    runtimeRegisterObjectType(rawValue: boxedRaw, classID: Int64(classID))
    return boxedRaw
}
