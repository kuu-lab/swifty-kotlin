
@inline(__always)
private func runtimeRegisterComparatorCompareMethod(
    _ objectRaw: Int,
    _ method: @convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int
) {
    _ = kk_object_register_itable_method(objectRaw, 0, 0, unsafeBitCast(method, to: Int.self))
}

@inline(__always)
func runtimePrimitiveCompareKind(from raw: Int32) -> RuntimePrimitiveCompareKind {
    switch raw {
    case 1: return .long
    case 2: return .uint
    case 3: return .ulong
    case 4: return .boolean
    case 5: return .char
    case 6: return .float
    case 7: return .double
    default: return .int
    }
}

// MARK: - Multi-selector compareBy (STDLIB-613)

@_cdecl("kk_comparator_from_multi_selectors")
public func kk_comparator_from_multi_selectors(
    _ sel1Fn: Int, _ sel1Closure: Int,
    _ sel2Fn: Int, _ sel2Closure: Int
) -> Int {
    let box = RuntimeListBox(elements: [sel1Fn, sel1Closure, sel2Fn, sel2Closure])
    let raw = registerRuntimeObject(box)
    runtimeRegisterComparatorCompareMethod(raw, kk_comparator_from_multi_selectors_trampoline)
    return raw
}

@_cdecl("kk_comparator_from_multi_selectors3")
public func kk_comparator_from_multi_selectors3(
    _ sel1Fn: Int, _ sel1Closure: Int,
    _ sel2Fn: Int, _ sel2Closure: Int,
    _ sel3Fn: Int, _ sel3Closure: Int
) -> Int {
    let box = RuntimeListBox(elements: [sel1Fn, sel1Closure, sel2Fn, sel2Closure, sel3Fn, sel3Closure])
    let raw = registerRuntimeObject(box)
    runtimeRegisterComparatorCompareMethod(raw, kk_comparator_from_multi_selectors_trampoline)
    return raw
}

@_cdecl("kk_comparator_from_multi_selectors_vararg")
public func kk_comparator_from_multi_selectors_vararg(_ selectorsRaw: Int) -> Int {
    let elements = runtimeArrayBox(from: selectorsRaw)?.elements ?? []
    let box = RuntimeListBox(elements: elements)
    let raw = registerRuntimeObject(box)
    runtimeRegisterComparatorCompareMethod(raw, kk_comparator_from_multi_selectors_trampoline)
    return raw
}

@_cdecl("kk_comparator_from_multi_selectors_trampoline")
public func kk_comparator_from_multi_selectors_trampoline(
    _ closureRaw: Int,
    _ a: Int,
    _ b: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: closureRaw),
          runtimeStorage.withGCLock({ state in state.objectPointers.contains(UInt(bitPattern: ptr)) }),
          let listBox = tryCast(ptr, to: RuntimeListBox.self)
    else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "Invalid comparator closure")
        return 0
    }
    let elements = listBox.elements
    // Elements are packed as [fn1, closure1, fn2, closure2, ...]
    guard elements.count % 2 == 0, elements.count >= 4 else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: malformed multi-selector comparator: expected even element count >= 4, got \(elements.count)")
    }
    let selectorCount = elements.count / 2
    var thrown = 0
    for i in 0..<selectorCount {
        let selectorFn = elements[i * 2]
        let selectorClosure = elements[i * 2 + 1]
        let keyA = runtimeInvokeCollectionLambda1(fnPtr: selectorFn, closureRaw: selectorClosure, value: a, outThrown: &thrown)
        if thrown != 0 { outThrown?.pointee = thrown; return 0 }
        let keyB = runtimeInvokeCollectionLambda1(fnPtr: selectorFn, closureRaw: selectorClosure, value: b, outThrown: &thrown)
        if thrown != 0 { outThrown?.pointee = thrown; return 0 }
        let cmp = runtimeCompareValues(keyA, keyB)
        if cmp != 0 { return cmp }
    }
    return 0
}

@_cdecl("kk_comparator_nulls_first")
public func kk_comparator_nulls_first(_ cFn: Int, _ cClosure: Int) -> Int {
    let pair = RuntimePairBox(first: cFn, second: cClosure)
    let raw = registerRuntimeObject(pair)
    runtimeRegisterComparatorCompareMethod(raw, kk_comparator_nulls_first_trampoline)
    return raw
}

@_cdecl("kk_comparator_nulls_first_of")
public func kk_comparator_nulls_first_of(_ cFn: Int, _ cClosure: Int) -> Int {
    let pair = RuntimePairBox(first: cFn, second: cClosure)
    let raw = registerRuntimeObject(pair)
    runtimeRegisterComparatorCompareMethod(raw, kk_comparator_nulls_first_trampoline)
    return raw
}

@_cdecl("kk_comparator_nulls_last")
public func kk_comparator_nulls_last(_ cFn: Int, _ cClosure: Int) -> Int {
    let pair = RuntimePairBox(first: cFn, second: cClosure)
    let raw = registerRuntimeObject(pair)
    runtimeRegisterComparatorCompareMethod(raw, kk_comparator_nulls_last_trampoline)
    return raw
}

@_cdecl("kk_comparator_nulls_last_of")
public func kk_comparator_nulls_last_of(_ cFn: Int, _ cClosure: Int) -> Int {
    let pair = RuntimePairBox(first: cFn, second: cClosure)
    let raw = registerRuntimeObject(pair)
    runtimeRegisterComparatorCompareMethod(raw, kk_comparator_nulls_last_trampoline)
    return raw
}

// MARK: - nullsLast (Comparable版 -- STDLIB-COMP-FN-061)

@_cdecl("kk_comparator_nulls_last_natural_trampoline")
public func kk_comparator_nulls_last_natural_trampoline(
    _ closureRaw: Int,
    _ a: Int,
    _ b: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    _ = closureRaw
    _ = outThrown
    if let nullableResult = runtimeCompareNullableOrder(a: a, b: b, nullsFirst: false) {
        return nullableResult
    }
    return runtimeCompareValues(a, b)
}

@_cdecl("kk_comparator_nulls_last_natural")
public func kk_comparator_nulls_last_natural() -> Int {
    0
}

@inline(__always)
private func runtimeCompareNullableOrder(
    a: Int,
    b: Int,
    nullsFirst: Bool
) -> Int? {
    let aIsNull = (a == runtimeNullSentinelInt || a == 0)
    let bIsNull = (b == runtimeNullSentinelInt || b == 0)
    if aIsNull && bIsNull { return 0 }
    if aIsNull { return nullsFirst ? -1 : 1 }
    if bIsNull { return nullsFirst ? 1 : -1 }
    return nil
}

@_cdecl("kk_comparator_nulls_first_trampoline")
public func kk_comparator_nulls_first_trampoline(
    _ closureRaw: Int,
    _ a: Int,
    _ b: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: closureRaw),
          runtimeStorage.withGCLock({ state in state.objectPointers.contains(UInt(bitPattern: ptr)) }),
          let pairBox = tryCast(ptr, to: RuntimePairBox.self)
    else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "Invalid comparator closure")
        return 0
    }
    if let nullableResult = runtimeCompareNullableOrder(a: a, b: b, nullsFirst: true) {
        return nullableResult
    }
    var thrown = 0
    let comparatorInvoke = runtimeSortedWithComparatorInvoke(fnPtr: pairBox.first, closureRaw: pairBox.second)
    let result = comparatorInvoke(a, b, &thrown)
    if thrown != 0 {
        outThrown?.pointee = thrown
        return 0
    }
    return result
}

@_cdecl("kk_comparator_nulls_last_trampoline")
public func kk_comparator_nulls_last_trampoline(
    _ closureRaw: Int,
    _ a: Int,
    _ b: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: closureRaw),
          runtimeStorage.withGCLock({ state in state.objectPointers.contains(UInt(bitPattern: ptr)) }),
          let pairBox = tryCast(ptr, to: RuntimePairBox.self)
    else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "Invalid comparator closure")
        return 0
    }
    if let nullableResult = runtimeCompareNullableOrder(a: a, b: b, nullsFirst: false) {
        return nullableResult
    }
    var thrown = 0
    let comparatorInvoke = runtimeSortedWithComparatorInvoke(fnPtr: pairBox.first, closureRaw: pairBox.second)
    let result = comparatorInvoke(a, b, &thrown)
    if thrown != 0 {
        outThrown?.pointee = thrown
        return 0
    }
    return result
}

// MARK: - nullsFirst Comparable (STDLIB-COMP-FN-059)

@_cdecl("kk_comparator_nulls_first_comparable_trampoline")
public func kk_comparator_nulls_first_comparable_trampoline(
    _ closureRaw: Int,
    _ a: Int,
    _ b: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    _ = closureRaw
    _ = outThrown
    if let r = runtimeCompareNullableOrder(a: a, b: b, nullsFirst: true) { return r }
    return runtimeCompareValues(a, b)
}

@_cdecl("kk_comparator_nulls_first_comparable")
public func kk_comparator_nulls_first_comparable() -> Int {
    0
}

// MARK: - kotlin.text.CASE_INSENSITIVE_ORDER (STDLIB-TEXT-TYPE-004)

private final class RuntimeCaseInsensitiveStringComparatorBox {}

@_cdecl("kk_string_case_insensitive_order_trampoline")
public func kk_string_case_insensitive_order_trampoline(
    _ closureRaw: Int,
    _ a: Int,
    _ b: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    _ = closureRaw
    _ = outThrown
    let lhs = runtimeStringFromRawOrPanic(a, caller: #function)
    let rhs = runtimeStringFromRawOrPanic(b, caller: #function)
    switch lhs.caseInsensitiveCompare(rhs) {
    case .orderedAscending:
        return -1
    case .orderedDescending:
        return 1
    case .orderedSame:
        return 0
    }
}

@_cdecl("kk_string_case_insensitive_order")
public func kk_string_case_insensitive_order() -> Int {
    let raw = registerRuntimeObject(RuntimeCaseInsensitiveStringComparatorBox())
    runtimeRegisterComparatorCompareMethod(raw, kk_string_case_insensitive_order_trampoline)
    return raw
}

// MARK: - compareValues / compareValuesBy

func runtimeCompareNullableValues(_ a: Int, _ b: Int) -> Int {
    let aIsNull = (a == runtimeNullSentinelInt || a == 0)
    let bIsNull = (b == runtimeNullSentinelInt || b == 0)
    if aIsNull && bIsNull { return 0 }
    if aIsNull { return -1 }
    if bIsNull { return 1 }
    return runtimeCompareValues(a, b)
}

@_cdecl("kk_compareValues")
public func kk_compareValues(_ a: Int, _ b: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    _ = outThrown
    return kk_box_int(runtimeCompareNullableValues(a, b))
}

/// Comparable<T>.compareTo(other: T): Int — generic interface dispatch for bundled stdlib bodies.
/// Emitted when a generic `T : Comparable<T>` receiver calls `.compareTo(other)` and no
/// concrete primitive or synthetic-stub handler matches (e.g. inside `sorted()`).
@_cdecl("kk_comparable_compareTo")
public func kk_comparable_compareTo(_ lhsRaw: Int, _ rhsRaw: Int) -> Int {
    return runtimeCompareNullableValues(lhsRaw, rhsRaw)
}

@inline(__always)
private func runtimeInvokeCompareValuesSelector(
    fnPtr: Int,
    closureRaw: Int,
    value: Int,
    outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    runtimeInvokeCollectionLambda1(fnPtr: fnPtr, closureRaw: closureRaw, value: value, outThrown: outThrown)
}

@_cdecl("kk_compareValuesBy1")
public func kk_compareValuesBy1(
    _ a: Int,
    _ b: Int,
    _ selectorFn: Int,
    _ selectorClosure: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    var thrown = 0
    let keyA = runtimeInvokeCompareValuesSelector(
        fnPtr: selectorFn,
        closureRaw: selectorClosure,
        value: a,
        outThrown: &thrown
    )
    if thrown != 0 { outThrown?.pointee = thrown; return 0 }
    let keyB = runtimeInvokeCompareValuesSelector(
        fnPtr: selectorFn,
        closureRaw: selectorClosure,
        value: b,
        outThrown: &thrown
    )
    if thrown != 0 { outThrown?.pointee = thrown; return 0 }
    return kk_box_int(runtimeCompareNullableValues(keyA, keyB))
}

@_cdecl("kk_compareValuesBy")
public func kk_compareValuesBy(
    _ a: Int,
    _ b: Int,
    _ sel1Fn: Int,
    _ sel1Closure: Int,
    _ sel2Fn: Int,
    _ sel2Closure: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    var thrown = 0
    let keyA1 = runtimeInvokeCompareValuesSelector(
        fnPtr: sel1Fn,
        closureRaw: sel1Closure,
        value: a,
        outThrown: &thrown
    )
    if thrown != 0 { outThrown?.pointee = thrown; return 0 }
    let keyB1 = runtimeInvokeCompareValuesSelector(
        fnPtr: sel1Fn,
        closureRaw: sel1Closure,
        value: b,
        outThrown: &thrown
    )
    if thrown != 0 { outThrown?.pointee = thrown; return 0 }
    let cmp1 = runtimeCompareNullableValues(keyA1, keyB1)
    if cmp1 != 0 { return kk_box_int(cmp1) }

    let keyA2 = runtimeInvokeCompareValuesSelector(
        fnPtr: sel2Fn,
        closureRaw: sel2Closure,
        value: a,
        outThrown: &thrown
    )
    if thrown != 0 { outThrown?.pointee = thrown; return 0 }
    let keyB2 = runtimeInvokeCompareValuesSelector(
        fnPtr: sel2Fn,
        closureRaw: sel2Closure,
        value: b,
        outThrown: &thrown
    )
    if thrown != 0 { outThrown?.pointee = thrown; return 0 }
    return kk_box_int(runtimeCompareNullableValues(keyA2, keyB2))
}

@_cdecl("kk_compareValuesBy3")
public func kk_compareValuesBy3(
    _ a: Int,
    _ b: Int,
    _ sel1Fn: Int,
    _ sel1Closure: Int,
    _ sel2Fn: Int,
    _ sel2Closure: Int,
    _ sel3Fn: Int,
    _ sel3Closure: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    var thrown = 0
    let keyA1 = runtimeInvokeCompareValuesSelector(
        fnPtr: sel1Fn,
        closureRaw: sel1Closure,
        value: a,
        outThrown: &thrown
    )
    if thrown != 0 { outThrown?.pointee = thrown; return 0 }
    let keyB1 = runtimeInvokeCompareValuesSelector(
        fnPtr: sel1Fn,
        closureRaw: sel1Closure,
        value: b,
        outThrown: &thrown
    )
    if thrown != 0 { outThrown?.pointee = thrown; return 0 }
    let cmp1 = runtimeCompareNullableValues(keyA1, keyB1)
    if cmp1 != 0 { return kk_box_int(cmp1) }

    let keyA2 = runtimeInvokeCompareValuesSelector(
        fnPtr: sel2Fn,
        closureRaw: sel2Closure,
        value: a,
        outThrown: &thrown
    )
    if thrown != 0 { outThrown?.pointee = thrown; return 0 }
    let keyB2 = runtimeInvokeCompareValuesSelector(
        fnPtr: sel2Fn,
        closureRaw: sel2Closure,
        value: b,
        outThrown: &thrown
    )
    if thrown != 0 { outThrown?.pointee = thrown; return 0 }
    let cmp2 = runtimeCompareNullableValues(keyA2, keyB2)
    if cmp2 != 0 { return kk_box_int(cmp2) }

    let keyA3 = runtimeInvokeCompareValuesSelector(
        fnPtr: sel3Fn,
        closureRaw: sel3Closure,
        value: a,
        outThrown: &thrown
    )
    if thrown != 0 { outThrown?.pointee = thrown; return 0 }
    let keyB3 = runtimeInvokeCompareValuesSelector(
        fnPtr: sel3Fn,
        closureRaw: sel3Closure,
        value: b,
        outThrown: &thrown
    )
    if thrown != 0 { outThrown?.pointee = thrown; return 0 }
    return kk_box_int(runtimeCompareNullableValues(keyA3, keyB3))
}

@_cdecl("kk_compareValuesByVararg")
public func kk_compareValuesByVararg(
    _ a: Int,
    _ b: Int,
    _ selectorsRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard let selectors = runtimeArrayBox(from: selectorsRaw)?.elements,
          selectors.count % 2 == 0,
          selectors.count >= 2
    else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: malformed compareValuesBy selectors")
    }

    var thrown = 0
    for index in stride(from: 0, to: selectors.count, by: 2) {
        let selectorFn = selectors[index]
        let selectorClosure = selectors[index + 1]
        let keyA = runtimeInvokeCompareValuesSelector(
            fnPtr: selectorFn,
            closureRaw: selectorClosure,
            value: a,
            outThrown: &thrown
        )
        if thrown != 0 { outThrown?.pointee = thrown; return 0 }
        let keyB = runtimeInvokeCompareValuesSelector(
            fnPtr: selectorFn,
            closureRaw: selectorClosure,
            value: b,
            outThrown: &thrown
        )
        if thrown != 0 { outThrown?.pointee = thrown; return 0 }
        let cmp = runtimeCompareNullableValues(keyA, keyB)
        if cmp != 0 {
            return kk_box_int(cmp)
        }
    }
    return kk_box_int(0)
}

@_cdecl("kk_compareValuesByComparator")
public func kk_compareValuesByComparator(
    _ a: Int,
    _ b: Int,
    _ comparatorRaw: Int,
    _ selectorFn: Int,
    _ selectorClosure: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    var thrown = 0
    let keyA = runtimeInvokeCompareValuesSelector(
        fnPtr: selectorFn,
        closureRaw: selectorClosure,
        value: a,
        outThrown: &thrown
    )
    if thrown != 0 { outThrown?.pointee = thrown; return 0 }
    let keyB = runtimeInvokeCompareValuesSelector(
        fnPtr: selectorFn,
        closureRaw: selectorClosure,
        value: b,
        outThrown: &thrown
    )
    if thrown != 0 { outThrown?.pointee = thrown; return 0 }

    let comparatorInvoke = runtimeSortedWithComparatorInvoke(fnPtr: comparatorRaw, closureRaw: 0)
    let result = comparatorInvoke(keyA, keyB, outThrown)
    if outThrown?.pointee != 0 { return 0 }
    return kk_box_int(result)
}

@_cdecl("kk_compare_with_comparator")
public func kk_compare_with_comparator(
    _ comparatorRaw: Int,
    _ a: Int,
    _ b: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    let comparatorInvoke = runtimeSortedWithComparatorInvoke(fnPtr: comparatorRaw, closureRaw: 0)
    return comparatorInvoke(a, b, outThrown)
}
