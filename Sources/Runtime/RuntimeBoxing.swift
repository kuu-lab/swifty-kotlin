
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
