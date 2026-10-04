// Number.toDouble()/toFloat()/toLong()/toInt()/toShort()/toByte() dispatch for
// an erased/abstract receiver (a `Number`-typed variable, or a `T : Number`
// type parameter) — see KSP-1540 / DEBT-DIFF-008 and
// CallLowerer+NumberConversionMemberCalls.swift for the KIR-side lowering
// that routes calls here.

/// Mirrors `CallLowerer.NumberConversionTargetKind` (KIR side) by raw value —
/// the two enums live in separate modules linked only through the C ABI, so
/// they must be kept in sync manually.
private enum RuntimeNumberConversionTargetKind: Int32 {
    case double = 0
    case float = 1
    case long = 2
    case int = 3
    case short = 4
    case byte = 5
}

/// Runtime dispatch for `Number.to*()` called through an erased/abstract
/// receiver. None of the built-in primitive types (Int/Long/Double/Float/
/// Short/Byte) register a real overriding *class* in the symbol table (they
/// conform to `Number` only via a hardcoded subtyping rule), so a boxed
/// primitive reaching this call has no vtable slot to dispatch through.
/// Recognize the box directly and perform the native conversion, reusing the
/// exact intrinsics the statically-typed fast path already uses (see
/// CallLowerer+LegacyMemberLikeCalls.swift's primitive conversion switch).
/// A receiver that isn't one of those boxes is a genuine user-defined
/// `Number` subclass instance (e.g. `class Money(...) : Number()`), which
/// *does* have a real vtable — fall back to `kk_vtable_lookup` for that case,
/// mirroring how `kk_compare_any`/`runtimeCompareComparableValues` handle the
/// analogous erased-`Comparable` dispatch problem (BUG-170).
@_cdecl("kk_number_to_primitive")
public func kk_number_to_primitive(_ receiver: Int, _ slot: Int, _ targetKindRaw: Int32) -> Int {
    guard let targetKind = RuntimeNumberConversionTargetKind(rawValue: targetKindRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_number_to_primitive got an unknown target kind \(targetKindRaw)")
    }

    if let pointer = UnsafeMutableRawPointer(bitPattern: receiver) {
        let isObjectPointer = runtimeStorage.withGCLock { state in
            state.objectPointers.contains(UInt(bitPattern: pointer))
        }
        if isObjectPointer {
            if let intBox = tryCast(pointer, to: RuntimeIntBox.self) {
                return runtimeConvertBoxedNumberInt(intBox.value, to: targetKind)
            }
            if let longBox = tryCast(pointer, to: RuntimeLongBox.self) {
                return runtimeConvertBoxedNumberLong(longBox.value, to: targetKind)
            }
            if let doubleBox = tryCast(pointer, to: RuntimeDoubleBox.self) {
                return runtimeConvertBoxedNumberDouble(doubleBox.value, to: targetKind)
            }
            if let floatBox = tryCast(pointer, to: RuntimeFloatBox.self) {
                return runtimeConvertBoxedNumberFloat(floatBox.value, to: targetKind)
            }
        }
    }

    // Not a recognized primitive box: a real Number subclass instance.
    // Dispatch through its own vtable slot instead.
    let fnPtrRaw = kk_vtable_lookup(receiver, slot)
    guard let fnPtr = UnsafeRawPointer(bitPattern: fnPtrRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: Number.to*() has no vtable entry for slot \(slot)")
    }
    let conversionFn = unsafeBitCast(
        fnPtr, to: (@convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int).self
    )
    var thrown = 0
    let result = conversionFn(receiver, &thrown)
    if thrown != 0 {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: Number.to*() threw during a runtime dispatch")
    }
    return result
}

private func runtimeConvertBoxedNumberInt(_ value: Int, to targetKind: RuntimeNumberConversionTargetKind) -> Int {
    switch targetKind {
    case .double: kk_int_to_double_bits(value)
    case .float: kk_int_to_float(value)
    case .long: kk_int_to_long(value)
    case .int: value
    case .short: kk_int_to_short(value)
    case .byte: kk_int_to_byte(value)
    }
}

private func runtimeConvertBoxedNumberLong(_ value: Int, to targetKind: RuntimeNumberConversionTargetKind) -> Int {
    switch targetKind {
    case .double: kk_long_to_double(value)
    case .float: kk_long_to_float(value)
    case .long: value
    case .int: kk_long_to_int(value)
    case .short: kk_long_to_short(value)
    case .byte: kk_long_to_byte(value)
    }
}

private func runtimeConvertBoxedNumberDouble(_ value: Double, to targetKind: RuntimeNumberConversionTargetKind) -> Int {
    let bits = kk_double_to_bits(value)
    return switch targetKind {
    case .double: bits
    case .float: kk_double_to_float(bits)
    case .long: __kk_double_to_long(bits)
    case .int: __kk_double_to_int(bits)
    // Double.toShort()/toByte() are documented as toInt().toShort()/toByte().
    case .short: kk_int_to_short(__kk_double_to_int(bits))
    case .byte: kk_int_to_byte(__kk_double_to_int(bits))
    }
}

private func runtimeConvertBoxedNumberFloat(_ value: Float, to targetKind: RuntimeNumberConversionTargetKind) -> Int {
    let bits = kk_float_to_bits(value)
    return switch targetKind {
    case .double: __kk_float_to_double_bits(bits)
    case .float: bits
    case .long: __kk_float_to_long(bits)
    case .int: __kk_float_to_int(bits)
    // Float.toShort()/toByte() are documented as toInt().toShort()/toByte().
    case .short: kk_int_to_short(__kk_float_to_int(bits))
    case .byte: kk_int_to_byte(__kk_float_to_int(bits))
    }
}
