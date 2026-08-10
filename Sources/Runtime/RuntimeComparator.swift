import Foundation

// The hand-built comparator objects below implement `Comparator<T>` at a fixed
// itable slot (0, 0) but are constructed directly in Swift rather than
// through compiler-emitted class construction, so they never go through the
// normal per-class kk_object_register_itable_iface emission (see
// KIRVtableRegistrationLowering.swift). Call sites that only see the static
// interface type (e.g. a `Comparator<T>` parameter) resolve the slot
// dynamically via kk_itable_lookup_dynamic -> runtimeRegisteredInterfaceSlot,
// which reads this registration; without it, dispatch fails with
// "method not found in vtable/itable" (e.g. `sortedWith(CASE_INSENSITIVE_ORDER)`).
private let runtimeComparatorInterfaceTypeID: Int64 = runtimeStableNominalTypeID(fqName: "kotlin.Comparator")

@inline(__always)
private func runtimeRegisterComparatorCompareMethod(
    _ objectRaw: Int,
    _ method: @convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int
) {
    _ = kk_object_register_itable_method(objectRaw, 0, 0, unsafeBitCast(method, to: Int.self))
    _ = kk_object_register_itable_iface(objectRaw, Int(runtimeComparatorInterfaceTypeID), 0)
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

// MARK: - kotlin.text.CASE_INSENSITIVE_ORDER (STDLIB-TEXT-TYPE-004)

private final class RuntimeCaseInsensitiveStringComparatorBox {}

// BUG-036/BUG-154: `String.CASE_INSENSITIVE_ORDER` is a companion `val` in real
// Kotlin, so every read must observe the same instance. The synthetic companion
// property is backed by a module-init global that calls this once (see
// `registerSyntheticCompanionExternalProperty`); cache the singleton handle here
// as well so any direct call also observes the same instance -- cleared by
// `kk_runtime_reset_gc` since a runtime reset drops GC tracking for the handle
// it points at.
private let caseInsensitiveOrderCacheLock = NSLock()
nonisolated(unsafe) private var cachedCaseInsensitiveOrderHandle = 0

func resetCaseInsensitiveOrderCache() {
    caseInsensitiveOrderCacheLock.lock()
    cachedCaseInsensitiveOrderHandle = 0
    caseInsensitiveOrderCacheLock.unlock()
}

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
    caseInsensitiveOrderCacheLock.lock()
    defer { caseInsensitiveOrderCacheLock.unlock() }
    if cachedCaseInsensitiveOrderHandle != 0 {
        return cachedCaseInsensitiveOrderHandle
    }
    let raw = registerRuntimeObject(RuntimeCaseInsensitiveStringComparatorBox())
    runtimeRegisterComparatorCompareMethod(raw, kk_string_case_insensitive_order_trampoline)
    cachedCaseInsensitiveOrderHandle = raw
    return raw
}

// MARK: - Generic comparison core

func runtimeCompareNullableValues(_ a: Int, _ b: Int) -> Int {
    let aIsNull = (a == runtimeNullSentinelInt)
    let bIsNull = (b == runtimeNullSentinelInt)
    if aIsNull && bIsNull { return 0 }
    if aIsNull { return -1 }
    if bIsNull { return 1 }
    return runtimeCompareValues(a, b)
}

/// Comparable<T>.compareTo(other: T): Int -- generic interface dispatch for bundled stdlib bodies.
/// Emitted when a generic `T : Comparable<T>` receiver calls `.compareTo(other)` and no
/// concrete primitive or synthetic-stub handler matches (e.g. inside `sorted()` or
/// `kotlin.comparisons.compareValues`).
@_cdecl("__kk_comparable_compareTo")
public func __kk_comparable_compareTo(_ lhsRaw: Int, _ rhsRaw: Int) -> Int {
    return runtimeCompareNullableValues(lhsRaw, rhsRaw)
}

/// Invokes a `Comparator<T>` object through its itable compare slot. Emitted for
/// `maxOf`/`minOf` with an explicit comparator argument.
@_cdecl("__kk_compare_with_comparator")
public func __kk_compare_with_comparator(
    _ comparatorRaw: Int,
    _ a: Int,
    _ b: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    let comparatorInvoke = runtimeSortedWithComparatorInvoke(fnPtr: comparatorRaw, closureRaw: 0)
    return comparatorInvoke(a, b, outThrown)
}
