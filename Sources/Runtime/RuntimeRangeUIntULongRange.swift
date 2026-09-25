// swiftlint:disable file_length

// UIntProgression / UIntRange / ULongProgression / ULongRange
// runtime entry points (STDLIB-RANGE-036/037/039, STDLIB-524).
//
// HOF logic and range-handle validation live in RuntimeRangeSharedHOF.swift.
// These @_cdecl functions are thin ABI entry points.

// MARK: - UIntProgression operations (STDLIB-RANGE-039)

@_cdecl("__kk_uint_rangeTo")
public func __kk_uint_rangeTo(_ lhs: Int, _ rhs: Int) -> Int {
    registerRuntimeObject(RuntimeRangeBox(first: lhs, last: rhs, step: 1, kind: .uintRange))
}

@_cdecl("__kk_uint_rangeUntil")
public func __kk_uint_rangeUntil(_ lhs: Int, _ rhs: Int) -> Int {
    let lhsUnsigned = UInt(bitPattern: lhs)
    let rhsUnsigned = UInt(bitPattern: rhs)
    let last = rhs &- 1
    let step = rhsUnsigned <= lhsUnsigned ? 0 : 1
    return registerRuntimeObject(RuntimeRangeBox(first: lhs, last: last, step: step, kind: .uintRange))
}

@_cdecl("__kk_uint_downTo")
public func __kk_uint_downTo(_ lhs: Int, _ rhs: Int) -> Int {
    registerRuntimeObject(RuntimeRangeBox(first: lhs, last: rhs, step: -1, kind: .uintProgression))
}

@_cdecl("__kk_uint_step")
public func __kk_uint_step(_ rangeRaw: Int, _ stepValue: Int) -> Int {
    runtimeUnsignedStep(rangeRaw, stepValue)
}

@_cdecl("__kk_uint_range_iterator")
public func __kk_uint_range_iterator(_ rangeRaw: Int) -> Int {
    let object = resolveRuntimeObjectHandle(rangeRaw)
    if object is RuntimeIteratorBuilderBox { return rangeRaw }
    guard let range = object as? RuntimeRangeBox else { return 0 }
    return registerRuntimeObject(
        RuntimeRangeIteratorBox(current: range.first, last: range.last, step: range.step)
    )
}

@_cdecl("__kk_uint_range_hasNext")
public func __kk_uint_range_hasNext(_ iterRaw: Int) -> Int {
    let object = resolveRuntimeObjectHandle(iterRaw)
    if object is RuntimeIteratorBuilderBox { return __kk_iterator_builder_hasNext(iterRaw) }
    guard let iterator = object as? RuntimeRangeIteratorBox else { return 0 }
    let current = UInt(bitPattern: iterator.current)
    let last = UInt(bitPattern: iterator.last)
    if iterator.step > 0 { return current <= last ? 1 : 0 }
    if iterator.step < 0 { return current >= last ? 1 : 0 }
    return 0
}

@_cdecl("__kk_uint_range_next")
public func __kk_uint_range_next(_ iterRaw: Int) -> Int {
    let object = resolveRuntimeObjectHandle(iterRaw)
    if object is RuntimeIteratorBuilderBox { return __kk_iterator_builder_next(iterRaw) }
    guard let iterator = object as? RuntimeRangeIteratorBox else { return 0 }
    let current = iterator.current
    let uCurrent = UInt(bitPattern: current)
    if iterator.step > 0 {
        let uStep = UInt(bitPattern: iterator.step)
        let (next, overflow) = uCurrent.addingReportingOverflow(uStep)
        iterator.current = overflow ? iterator.last : Int(bitPattern: next)
        if overflow { iterator.step = 0 }
    } else if iterator.step < 0 {
        let uStep = UInt(iterator.step.magnitude)
        let (next, overflow) = uCurrent.subtractingReportingOverflow(uStep)
        iterator.current = overflow ? iterator.last : Int(bitPattern: next)
        if overflow { iterator.step = 0 }
    }
    return current
}

// MARK: - UIntRange properties and HOFs (STDLIB-RANGE-036)

@_cdecl("kk_uint_range_step")
public func kk_uint_range_step(_ rangeRaw: Int) -> Int {
    runtimeRangeEntry(RuntimeUnsignedRangeHOFKind.self, rangeRaw, functionName: "kk_uint_range_step") { range in
        range.step
    }
}

@_cdecl("kk_uint_range_forEach")
public func kk_uint_range_forEach(_ rangeRaw: Int, _ fnPtr: Int, _ closureRaw: Int,
                                  _ outThrown: UnsafeMutablePointer<Int>?) -> Int
{
    runtimeRangeHOFEntry(RuntimeUnsignedRangeHOFKind.self, rangeRaw, fnPtr, closureRaw, outThrown,
                         functionName: "kk_uint_range_forEach", operation: RuntimeUnsignedRangeHOFKind.forEach)
}

@_cdecl("kk_uint_range_reduce")
public func kk_uint_range_reduce(_ rangeRaw: Int, _ fnPtr: Int, _ closureRaw: Int,
                                 _ outThrown: UnsafeMutablePointer<Int>?) -> Int
{
    runtimeRangeHOFEntry(RuntimeUnsignedRangeHOFKind.self, rangeRaw, fnPtr, closureRaw, outThrown,
                         functionName: "kk_uint_range_reduce", operation: RuntimeUnsignedRangeHOFKind.reduce)
}

@_cdecl("kk_uint_range_reduceIndexed")
public func kk_uint_range_reduceIndexed(_ rangeRaw: Int, _ fnPtr: Int, _ closureRaw: Int,
                                        _ outThrown: UnsafeMutablePointer<Int>?) -> Int
{
    runtimeRangeHOFEntry(RuntimeUnsignedRangeHOFKind.self, rangeRaw, fnPtr, closureRaw, outThrown,
                         functionName: "kk_uint_range_reduceIndexed", operation: RuntimeUnsignedRangeHOFKind.reduceIndexed)
}

@_cdecl("kk_uint_range_fold")
public func kk_uint_range_fold(_ rangeRaw: Int, _ initialValue: Int, _ fnPtr: Int, _ closureRaw: Int,
                               _ outThrown: UnsafeMutablePointer<Int>?) -> Int
{
    runtimeRangeFoldHOFEntry(RuntimeUnsignedRangeHOFKind.self, rangeRaw, initialValue, fnPtr, closureRaw, outThrown,
                             functionName: "kk_uint_range_fold", operation: RuntimeUnsignedRangeHOFKind.fold)
}

@_cdecl("kk_uint_range_foldIndexed")
public func kk_uint_range_foldIndexed(_ rangeRaw: Int, _ initialValue: Int, _ fnPtr: Int, _ closureRaw: Int,
                                      _ outThrown: UnsafeMutablePointer<Int>?) -> Int
{
    runtimeRangeFoldHOFEntry(RuntimeUnsignedRangeHOFKind.self, rangeRaw, initialValue, fnPtr, closureRaw, outThrown,
                             functionName: "kk_uint_range_foldIndexed", operation: RuntimeUnsignedRangeHOFKind.foldIndexed)
}

@_cdecl("kk_uint_range_find")
public func kk_uint_range_find(_ rangeRaw: Int, _ fnPtr: Int, _ closureRaw: Int,
                               _ outThrown: UnsafeMutablePointer<Int>?) -> Int
{
    runtimeRangeFirstMatchEntry(RuntimeUnsignedRangeHOFKind.self, rangeRaw, fnPtr, closureRaw, outThrown,
                                functionName: "kk_uint_range_find", orNull: true)
}

@_cdecl("kk_uint_range_findLast")
public func kk_uint_range_findLast(_ rangeRaw: Int, _ fnPtr: Int, _ closureRaw: Int,
                                   _ outThrown: UnsafeMutablePointer<Int>?) -> Int
{
    runtimeRangeLastMatchEntry(RuntimeUnsignedRangeHOFKind.self, rangeRaw, fnPtr, closureRaw, outThrown,
                               functionName: "kk_uint_range_findLast", orNull: true)
}

@_cdecl("kk_uint_range_first_orThrow")
public func kk_uint_range_first_orThrow(_ rangeRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeRangeFirstOrLastOrThrow(
        RuntimeUnsignedRangeHOFKind.self,
        rangeRaw,
        wantLast: false,
        outThrown,
        functionName: "kk_uint_range_first_orThrow"
    )
}

@_cdecl("kk_uint_range_last_orThrow")
public func kk_uint_range_last_orThrow(_ rangeRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeRangeFirstOrLastOrThrow(
        RuntimeUnsignedRangeHOFKind.self,
        rangeRaw,
        wantLast: true,
        outThrown,
        functionName: "kk_uint_range_last_orThrow"
    )
}

@_cdecl("kk_uint_range_first_predicate")
public func kk_uint_range_first_predicate(_ rangeRaw: Int, _ fnPtr: Int, _ closureRaw: Int,
                                          _ outThrown: UnsafeMutablePointer<Int>?) -> Int
{
    runtimeRangeFirstMatchEntry(RuntimeUnsignedRangeHOFKind.self, rangeRaw, fnPtr, closureRaw, outThrown,
                                functionName: "kk_uint_range_first_predicate", orNull: false)
}

@_cdecl("kk_uint_range_firstOrNull_predicate")
public func kk_uint_range_firstOrNull_predicate(_ rangeRaw: Int, _ fnPtr: Int, _ closureRaw: Int,
                                                _ outThrown: UnsafeMutablePointer<Int>?) -> Int
{
    runtimeRangeFirstMatchEntry(RuntimeUnsignedRangeHOFKind.self, rangeRaw, fnPtr, closureRaw, outThrown,
                                functionName: "kk_uint_range_firstOrNull_predicate", orNull: true)
}

@_cdecl("kk_uint_range_last_predicate")
public func kk_uint_range_last_predicate(_ rangeRaw: Int, _ fnPtr: Int, _ closureRaw: Int,
                                         _ outThrown: UnsafeMutablePointer<Int>?) -> Int
{
    runtimeRangeLastMatchEntry(RuntimeUnsignedRangeHOFKind.self, rangeRaw, fnPtr, closureRaw, outThrown,
                               functionName: "kk_uint_range_last_predicate", orNull: false)
}

@_cdecl("kk_uint_range_lastOrNull_predicate")
public func kk_uint_range_lastOrNull_predicate(_ rangeRaw: Int, _ fnPtr: Int, _ closureRaw: Int,
                                               _ outThrown: UnsafeMutablePointer<Int>?) -> Int
{
    runtimeRangeLastMatchEntry(RuntimeUnsignedRangeHOFKind.self, rangeRaw, fnPtr, closureRaw, outThrown,
                               functionName: "kk_uint_range_lastOrNull_predicate", orNull: true)
}

@_cdecl("__kk_uint_range_randomOrNull")
public func __kk_uint_range_randomOrNull(_ rangeRaw: Int) -> Int {
    runtimeRangeRandomOrNullEntry(RuntimeUnsignedRangeHOFKind.self, rangeRaw, randomRaw: nil,
                                  functionName: "__kk_uint_range_randomOrNull")
}

@_cdecl("__kk_uint_range_randomOrNull_random")
public func __kk_uint_range_randomOrNull_random(_ rangeRaw: Int, _ randomRaw: Int) -> Int {
    runtimeRangeRandomOrNullEntry(RuntimeUnsignedRangeHOFKind.self, rangeRaw, randomRaw: randomRaw,
                                  functionName: "__kk_uint_range_randomOrNull_random")
}

@_cdecl("__kk_uint_range_random")
public func __kk_uint_range_random(_ rangeRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeRangeRandomEntry(RuntimeUnsignedRangeHOFKind.self, rangeRaw, 0, outThrown,
                            functionName: "__kk_uint_range_random")
}

@_cdecl("__kk_uint_range_random_random")
public func __kk_uint_range_random_random(_ rangeRaw: Int, _ randomRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeRangeRandomEntry(RuntimeUnsignedRangeHOFKind.self, rangeRaw, randomRaw, outThrown,
                            functionName: "__kk_uint_range_random_random")
}

@_cdecl("kk_uint_range_any")
public func kk_uint_range_any(_ rangeRaw: Int, _ fnPtr: Int, _ closureRaw: Int,
                              _ outThrown: UnsafeMutablePointer<Int>?) -> Int
{
    runtimeRangeHOFEntry(RuntimeUnsignedRangeHOFKind.self, rangeRaw, fnPtr, closureRaw, outThrown,
                         functionName: "kk_uint_range_any", operation: RuntimeUnsignedRangeHOFKind.any)
}

@_cdecl("kk_uint_range_all")
public func kk_uint_range_all(_ rangeRaw: Int, _ fnPtr: Int, _ closureRaw: Int,
                              _ outThrown: UnsafeMutablePointer<Int>?) -> Int
{
    runtimeRangeHOFEntry(RuntimeUnsignedRangeHOFKind.self, rangeRaw, fnPtr, closureRaw, outThrown,
                         functionName: "kk_uint_range_all", operation: RuntimeUnsignedRangeHOFKind.all)
}

@_cdecl("kk_uint_range_none")
public func kk_uint_range_none(_ rangeRaw: Int, _ fnPtr: Int, _ closureRaw: Int,
                               _ outThrown: UnsafeMutablePointer<Int>?) -> Int
{
    runtimeRangeHOFEntry(RuntimeUnsignedRangeHOFKind.self, rangeRaw, fnPtr, closureRaw, outThrown,
                         functionName: "kk_uint_range_none", operation: RuntimeUnsignedRangeHOFKind.none)
}

@_cdecl("__kk_uint_range_chunked")
public func __kk_uint_range_chunked(_ rangeRaw: Int, _ size: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    if size <= 0 {
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(
            message: "size \(size) must be greater than zero."
        )
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }
    return runtimeRangeEntry(RuntimeUnsignedRangeHOFKind.self, rangeRaw, functionName: "__kk_uint_range_chunked") { range in
        RuntimeUnsignedRangeHOFKind.chunked(range, size)
    }
}

@_cdecl("__kk_uint_range_windowed")
public func __kk_uint_range_windowed(_ rangeRaw: Int, _ size: Int, _ step: Int, _ partialWindows: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    if size <= 0 || step <= 0 {
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(
            message: "Both size \(size) and step \(step) must be greater than zero."
        )
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }
    return runtimeRangeEntry(RuntimeUnsignedRangeHOFKind.self, rangeRaw, functionName: "__kk_uint_range_windowed") { range in
        RuntimeUnsignedRangeHOFKind.windowed(range, size, step, partialWindows)
    }
}

@_cdecl("__kk_uint_range_take")
public func __kk_uint_range_take(_ rangeRaw: Int, _ n: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    if n < 0 {
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(
            message: "Requested element count \(n) is less than zero."
        )
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }
    return runtimeRangeEntry(RuntimeUnsignedRangeHOFKind.self, rangeRaw, functionName: "__kk_uint_range_take") { range in
        RuntimeUnsignedRangeHOFKind.take(range, n)
    }
}

@_cdecl("__kk_uint_range_drop")
public func __kk_uint_range_drop(_ rangeRaw: Int, _ n: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    if n < 0 {
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(
            message: "Requested element count \(n) is less than zero."
        )
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }
    return runtimeRangeEntry(RuntimeUnsignedRangeHOFKind.self, rangeRaw, functionName: "__kk_uint_range_drop") { range in
        RuntimeUnsignedRangeHOFKind.drop(range, n)
    }
}

// MARK: - ULong HOFs (STDLIB-RANGE-037/039)

@_cdecl("__kk_ulong_range_randomOrNull")
public func __kk_ulong_range_randomOrNull(_ rangeRaw: Int) -> Int {
    runtimeRangeRandomOrNullEntry(RuntimeUnsignedRangeHOFKind.self, rangeRaw, randomRaw: nil,
                                  functionName: "__kk_ulong_range_randomOrNull")
}

@_cdecl("__kk_ulong_range_randomOrNull_random")
public func __kk_ulong_range_randomOrNull_random(_ rangeRaw: Int, _ randomRaw: Int) -> Int {
    runtimeRangeRandomOrNullEntry(RuntimeUnsignedRangeHOFKind.self, rangeRaw, randomRaw: randomRaw,
                                  functionName: "__kk_ulong_range_randomOrNull_random")
}

@_cdecl("__kk_ulong_range_random")
public func __kk_ulong_range_random(_ rangeRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeRangeRandomEntry(RuntimeUnsignedRangeHOFKind.self, rangeRaw, 0, outThrown,
                            functionName: "__kk_ulong_range_random")
}

@_cdecl("__kk_ulong_range_random_random")
public func __kk_ulong_range_random_random(_ rangeRaw: Int, _ randomRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeRangeRandomEntry(RuntimeUnsignedRangeHOFKind.self, rangeRaw, randomRaw, outThrown,
                            functionName: "__kk_ulong_range_random_random")
}

@_cdecl("__kk_ulong_range_chunked")
public func __kk_ulong_range_chunked(_ rangeRaw: Int, _ size: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    if size <= 0 {
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(
            message: "size \(size) must be greater than zero."
        )
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }
    return runtimeRangeEntry(RuntimeUnsignedRangeHOFKind.self, rangeRaw, functionName: "__kk_ulong_range_chunked") { range in
        RuntimeUnsignedRangeHOFKind.chunked(range, size)
    }
}

@_cdecl("__kk_ulong_range_windowed")
public func __kk_ulong_range_windowed(_ rangeRaw: Int, _ size: Int, _ step: Int, _ partialWindows: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    if size <= 0 || step <= 0 {
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(
            message: "Both size \(size) and step \(step) must be greater than zero."
        )
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }
    return runtimeRangeEntry(RuntimeUnsignedRangeHOFKind.self, rangeRaw, functionName: "__kk_ulong_range_windowed") { range in
        RuntimeUnsignedRangeHOFKind.windowed(range, size, step, partialWindows)
    }
}

@_cdecl("__kk_ulong_range_take")
public func __kk_ulong_range_take(_ rangeRaw: Int, _ n: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    if n < 0 {
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(
            message: "Requested element count \(n) is less than zero."
        )
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }
    return runtimeRangeEntry(RuntimeUnsignedRangeHOFKind.self, rangeRaw, functionName: "__kk_ulong_range_take") { range in
        RuntimeUnsignedRangeHOFKind.take(range, n)
    }
}

@_cdecl("__kk_ulong_range_drop")
public func __kk_ulong_range_drop(_ rangeRaw: Int, _ n: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    if n < 0 {
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(
            message: "Requested element count \(n) is less than zero."
        )
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }
    return runtimeRangeEntry(RuntimeUnsignedRangeHOFKind.self, rangeRaw, functionName: "__kk_ulong_range_drop") { range in
        RuntimeUnsignedRangeHOFKind.drop(range, n)
    }
}

// MARK: - ULongProgression operations (STDLIB-RANGE-039)

@_cdecl("__kk_ulong_rangeTo")
public func __kk_ulong_rangeTo(_ lhs: Int, _ rhs: Int) -> Int {
    registerRuntimeObject(RuntimeRangeBox(first: lhs, last: rhs, step: 1, kind: .ulongRange))
}

@_cdecl("__kk_ulong_downTo")
public func __kk_ulong_downTo(_ lhs: Int, _ rhs: Int) -> Int {
    registerRuntimeObject(RuntimeRangeBox(first: lhs, last: rhs, step: -1, kind: .ulongProgression))
}

@_cdecl("__kk_ulong_step")
public func __kk_ulong_step(_ rangeRaw: Int, _ stepValue: Int) -> Int {
    runtimeUnsignedStep(rangeRaw, stepValue)
}

@_cdecl("kk_range_step")
public func kk_range_step(_ rangeRaw: Int) -> Int {
    runtimeRangeEntry(RuntimeSignedRangeHOFKind.self, rangeRaw, functionName: "kk_range_step") { range in
        range.step
    }
}

private func runtimeUnsignedStep(_ rangeRaw: Int, _ stepValue: Int) -> Int {
    guard stepValue > 0 else { return rangeRaw }
    guard stepValue != Int.min else { return rangeRaw }
    guard let range = runtimeRangeBox(from: rangeRaw) else { return rangeRaw }
    if range.step == 0 {
        return registerRuntimeObject(RuntimeRangeBox(
            first: range.first,
            last: range.last,
            step: range.step,
            kind: range.kind.progressionKind
        ))
    }
    let nextStep = range.step < 0 ? (0 &- stepValue) : stepValue
    let firstUnsigned = UInt(bitPattern: range.first)
    let lastUnsigned = UInt(bitPattern: range.last)
    let alignedLast: Int
    if nextStep > 0 {
        guard firstUnsigned <= lastUnsigned else {
            return registerRuntimeObject(RuntimeRangeBox(
                first: range.first,
                last: range.last,
                step: nextStep,
                kind: range.kind.progressionKind
            ))
        }
        let diff = range.last &- range.first
        let remainder = diff % nextStep
        alignedLast = range.last &- remainder
    } else {
        guard firstUnsigned >= lastUnsigned else {
            return registerRuntimeObject(RuntimeRangeBox(
                first: range.first,
                last: range.last,
                step: nextStep,
                kind: range.kind.progressionKind
            ))
        }
        let diff = range.first &- range.last
        let remainder = diff % (0 &- nextStep)
        alignedLast = range.last &+ remainder
    }
    return registerRuntimeObject(RuntimeRangeBox(
        first: range.first,
        last: alignedLast,
        step: nextStep,
        kind: range.kind.progressionKind
    ))
}
