
@_cdecl("kk_box_int")
public func kk_box_int(_ value: Int) -> Int {
    if value == runtimeNullSentinelInt { return value }
    // If the value is already a registered runtime object (e.g. RuntimeRangeBox
    // produced by kk_op_rangeTo, or an already-boxed RuntimeIntBox), pass it
    // through without double-boxing.
    if let objPointer = UnsafeMutableRawPointer(bitPattern: value) {
        let isObjectPointer = runtimeStorage.withGCLock { state in
            state.objectPointers.contains(UInt(bitPattern: objPointer))
        }
        if isObjectPointer {
            return value
        }
    }
    let box = RuntimeIntBox(value)
    let opaque = UnsafeMutableRawPointer(Unmanaged.passRetained(box).toOpaque())
    runtimeStorage.withGCLock { state in
        state.objectPointers.insert(UInt(bitPattern: opaque))
    }
    return Int(bitPattern: opaque)
}

@_cdecl("kk_box_bool")
public func kk_box_bool(_ value: Int) -> Int {
    if value == runtimeNullSentinelInt { return value }
    let box = RuntimeBoolBox(value != 0)
    let opaque = UnsafeMutableRawPointer(Unmanaged.passRetained(box).toOpaque())
    runtimeStorage.withGCLock { state in
        state.objectPointers.insert(UInt(bitPattern: opaque))
    }
    return Int(bitPattern: opaque)
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
    // flowing into an Any?-typed argument) rely on this early-return to
    // preserve the null sentinel — see kk_box_long_nonnull below for the
    // counterpart used when the source's static type is provably non-null.
    if value == runtimeNullSentinelInt { return value }
    // If the value is already a registered runtime object (e.g. RuntimeRangeBox
    // produced by kk_op_rangeTo for LongRange), pass it through without
    // double-boxing so that kk_println_any / runtimeElementToString can
    // recognise the original object type.
    if let objPointer = UnsafeMutableRawPointer(bitPattern: value) {
        let isObjectPointer = runtimeStorage.withGCLock { state in
            state.objectPointers.contains(UInt(bitPattern: objPointer))
        }
        if isObjectPointer {
            return value
        }
    }
    let box = RuntimeLongBox(value)
    let opaque = UnsafeMutableRawPointer(Unmanaged.passRetained(box).toOpaque())
    runtimeStorage.withGCLock { state in
        state.objectPointers.insert(UInt(bitPattern: opaque))
    }
    return Int(bitPattern: opaque)
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
    if let objPointer = UnsafeMutableRawPointer(bitPattern: value) {
        let isObjectPointer = runtimeStorage.withGCLock { state in
            state.objectPointers.contains(UInt(bitPattern: objPointer))
        }
        if isObjectPointer {
            return value
        }
    }
    let box = RuntimeLongBox(value)
    let opaque = UnsafeMutableRawPointer(Unmanaged.passRetained(box).toOpaque())
    runtimeStorage.withGCLock { state in
        state.objectPointers.insert(UInt(bitPattern: opaque))
    }
    return Int(bitPattern: opaque)
}

@_cdecl("kk_unbox_long")
public func kk_unbox_long(_ obj: Int) -> Int {
    // NOTE: no early-return for runtimeNullSentinelInt (Int64.min == Long.MIN_VALUE).
    // runtimeNullSentinelInt is never a valid heap pointer, so it reaches the
    // passthrough branch below and returns Int.min (= Long.MIN_VALUE) correctly.
    // Returning 0 here was wrong: it caused Double.NEGATIVE_INFINITY.roundToLong()
    // to produce 0 instead of Long.MIN_VALUE (kk_double_roundToLong returns Int.min
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
    // this early-return. kk_box_ulong_nonnull is the counterpart used when
    // the source's static type is provably non-null.
    if value == runtimeNullSentinelInt { return value }
    // If the value is already a registered runtime object, pass it through
    // without double-boxing (mirrors kk_box_long).
    if let objPointer = UnsafeMutableRawPointer(bitPattern: value) {
        let isObjectPointer = runtimeStorage.withGCLock { state in
            state.objectPointers.contains(UInt(bitPattern: objPointer))
        }
        if isObjectPointer {
            return value
        }
    }
    let box = RuntimeULongBox(value)
    let opaque = UnsafeMutableRawPointer(Unmanaged.passRetained(box).toOpaque())
    runtimeStorage.withGCLock { state in
        state.objectPointers.insert(UInt(bitPattern: opaque))
    }
    return Int(bitPattern: opaque)
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
    if let objPointer = UnsafeMutableRawPointer(bitPattern: value) {
        let isObjectPointer = runtimeStorage.withGCLock { state in
            state.objectPointers.contains(UInt(bitPattern: objPointer))
        }
        if isObjectPointer {
            return value
        }
    }
    let box = RuntimeULongBox(value)
    let opaque = UnsafeMutableRawPointer(Unmanaged.passRetained(box).toOpaque())
    runtimeStorage.withGCLock { state in
        state.objectPointers.insert(UInt(bitPattern: opaque))
    }
    return Int(bitPattern: opaque)
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
    if value == runtimeNullSentinelInt { return value }
    let floatBits = Float(bitPattern: UInt32(truncatingIfNeeded: value))
    let box = RuntimeFloatBox(floatBits)
    let opaque = UnsafeMutableRawPointer(Unmanaged.passRetained(box).toOpaque())
    runtimeStorage.withGCLock { state in
        state.objectPointers.insert(UInt(bitPattern: opaque))
    }
    return Int(bitPattern: opaque)
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
    if value == runtimeNullSentinelInt { return value }
    let doubleBits = Double(bitPattern: UInt64(bitPattern: Int64(value)))
    let box = RuntimeDoubleBox(doubleBits)
    let opaque = UnsafeMutableRawPointer(Unmanaged.passRetained(box).toOpaque())
    runtimeStorage.withGCLock { state in
        state.objectPointers.insert(UInt(bitPattern: opaque))
    }
    return Int(bitPattern: opaque)
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
    if value == runtimeNullSentinelInt { return value }
    // If the value is already a registered runtime object, pass it through
    // without double-boxing.
    if let objPointer = UnsafeMutableRawPointer(bitPattern: value) {
        let isObjectPointer = runtimeStorage.withGCLock { state in
            state.objectPointers.contains(UInt(bitPattern: objPointer))
        }
        if isObjectPointer {
            return value
        }
    }
    let box = RuntimeCharBox(value)
    let opaque = UnsafeMutableRawPointer(Unmanaged.passRetained(box).toOpaque())
    runtimeStorage.withGCLock { state in
        state.objectPointers.insert(UInt(bitPattern: opaque))
    }
    return Int(bitPattern: opaque)
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
