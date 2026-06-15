
// swiftlint:disable file_length

// UIntProgression / UIntRange / ULongProgression / ULongRange
// runtime entry points (STDLIB-RANGE-036/037/039, STDLIB-524).
//
// Shared HOF logic lives in RuntimeRangeSharedHOF.swift (runtimeUnsignedRange* helpers).
// These @_cdecl functions are thin ABI entry points.

// MARK: - UIntProgression operations (STDLIB-RANGE-039)

@_cdecl("kk_uint_rangeTo")
public func kk_uint_rangeTo(_ lhs: Int, _ rhs: Int) -> Int {
    registerRuntimeObject(RuntimeRangeBox(first: lhs, last: rhs, step: 1))
}

@_cdecl("kk_uint_downTo")
public func kk_uint_downTo(_ lhs: Int, _ rhs: Int) -> Int {
    registerRuntimeObject(RuntimeRangeBox(first: lhs, last: rhs, step: -1))
}

@_cdecl("kk_uint_step")
public func kk_uint_step(_ rangeRaw: Int, _ stepValue: Int) -> Int {
    guard stepValue > 0 else { return rangeRaw }
    guard stepValue != Int.min else { return rangeRaw }
    guard let range = runtimeRangeBox(from: rangeRaw) else { return rangeRaw }
    if range.step == 0 { return rangeRaw }
    let nextStep = range.step < 0 ? (0 &- stepValue) : stepValue
    let firstUnsigned = UInt(bitPattern: range.first)
    let lastUnsigned = UInt(bitPattern: range.last)
    let alignedLast: Int
    if nextStep > 0 {
        guard firstUnsigned <= lastUnsigned else {
            return registerRuntimeObject(RuntimeRangeBox(first: range.first, last: range.last, step: nextStep))
        }
        let diff = range.last &- range.first
        let remainder = diff % nextStep
        alignedLast = range.last &- remainder
    } else {
        guard firstUnsigned >= lastUnsigned else {
            return registerRuntimeObject(RuntimeRangeBox(first: range.first, last: range.last, step: nextStep))
        }
        let diff = range.first &- range.last
        let remainder = diff % (0 &- nextStep)
        alignedLast = range.last &+ remainder
    }
    return registerRuntimeObject(RuntimeRangeBox(first: range.first, last: alignedLast, step: nextStep))
}

@_cdecl("kk_uint_range_reversed")
public func kk_uint_range_reversed(_ rangeRaw: Int) -> Int {
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_uint_range_reversed")
    }
    return registerRuntimeObject(RuntimeRangeBox(first: range.last, last: range.first, step: 0 &- range.step))
}

@_cdecl("kk_uint_range_toList")
public func kk_uint_range_toList(_ rangeRaw: Int) -> Int {
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_uint_range_toList")
    }
    return runtimeUnsignedRangeToList(range)
}

@_cdecl("kk_uint_range_iterator")
public func kk_uint_range_iterator(_ rangeRaw: Int) -> Int {
    if runtimeIteratorBuilderBox(from: rangeRaw) != nil { return rangeRaw }
    guard let range = runtimeRangeBox(from: rangeRaw) else { return 0 }
    return registerRuntimeObject(
        RuntimeRangeIteratorBox(current: range.first, last: range.last, step: range.step)
    )
}

@_cdecl("kk_uint_range_hasNext")
public func kk_uint_range_hasNext(_ iterRaw: Int) -> Int {
    if runtimeIteratorBuilderBox(from: iterRaw) != nil { return kk_iterator_builder_hasNext(iterRaw) }
    guard let iterator = runtimeRangeIteratorBox(from: iterRaw) else { return 0 }
    let current = UInt(bitPattern: iterator.current)
    let last = UInt(bitPattern: iterator.last)
    if iterator.step > 0 { return current <= last ? 1 : 0 }
    if iterator.step < 0 { return current >= last ? 1 : 0 }
    return 0
}

@_cdecl("kk_uint_range_next")
public func kk_uint_range_next(_ iterRaw: Int) -> Int {
    if runtimeIteratorBuilderBox(from: iterRaw) != nil { return kk_iterator_builder_next(iterRaw) }
    guard let iterator = runtimeRangeIteratorBox(from: iterRaw) else { return 0 }
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

@_cdecl("kk_uint_range_contains")
public func kk_uint_range_contains(_ rangeRaw: Int, _ value: Int) -> Int {
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_uint_range_contains")
    }
    let first = UInt(bitPattern: range.first)
    let last = UInt(bitPattern: range.last)
    let uValue = UInt(bitPattern: value)
    let rawStep = range.step
    if rawStep > 0 {
        let uStep = UInt(bitPattern: rawStep)
        guard first <= uValue && uValue <= last else { return 0 }
        return (uValue - first) % uStep == 0 ? 1 : 0
    } else if rawStep < 0 {
        let uStep = UInt(bitPattern: -rawStep)
        guard last <= uValue && uValue <= first else { return 0 }
        return (first - uValue) % uStep == 0 ? 1 : 0
    }
    return 0
}

@_cdecl("kk_uint_range_isEmpty")
public func kk_uint_range_isEmpty(_ rangeRaw: Int) -> Int {
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_uint_range_isEmpty")
    }
    return runtimeUnsignedRangeIsEmpty(range) ? 1 : 0
}

@_cdecl("kk_uint_range_first")
public func kk_uint_range_first(_ rangeRaw: Int) -> Int {
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_uint_range_first")
    }
    return range.first
}

@_cdecl("kk_uint_range_last")
public func kk_uint_range_last(_ rangeRaw: Int) -> Int {
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_uint_range_last")
    }
    return range.last
}

@_cdecl("kk_uint_range_step")
public func kk_uint_range_step(_ rangeRaw: Int) -> Int {
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_uint_range_step")
    }
    return range.step
}

@_cdecl("kk_uint_range_count")
public func kk_uint_range_count(_ rangeRaw: Int) -> Int {
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_uint_range_count")
    }
    return runtimeUnsignedRangeCount(range)
}

@_cdecl("kk_uint_range_sum")
public func kk_uint_range_sum(_ rangeRaw: Int) -> Int {
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_uint_range_sum")
    }
    var sum = UInt(0)
    var current = UInt(bitPattern: range.first)
    let last = UInt(bitPattern: range.last)
    if range.step > 0 {
        let uStep = UInt(bitPattern: range.step)
        while current <= last {
            sum &+= current
            let (next, overflow) = current.addingReportingOverflow(uStep)
            if overflow { break }
            current = next
        }
    } else if range.step < 0 {
        let uStep = UInt(range.step.magnitude)
        while current >= last {
            sum &+= current
            let (next, overflow) = current.subtractingReportingOverflow(uStep)
            if overflow { break }
            current = next
        }
    }
    return Int(bitPattern: sum)
}

@_cdecl("kk_uint_range_toUIntArray")
public func kk_uint_range_toUIntArray(_ rangeRaw: Int) -> Int {
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_uint_range_toUIntArray")
    }
    return runtimeUnsignedRangeToList(range)
}

@_cdecl("kk_uint_range_forEach")
public func kk_uint_range_forEach(_ rangeRaw: Int, _ fnPtr: Int, _ closureRaw: Int,
                                  _ outThrown: UnsafeMutablePointer<Int>?) -> Int
{
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_uint_range_forEach")
    }
    return runtimeUnsignedRangeForEach(range, fnPtr, closureRaw, outThrown)
}

@_cdecl("kk_uint_range_map")
public func kk_uint_range_map(_ rangeRaw: Int, _ fnPtr: Int, _ closureRaw: Int,
                              _ outThrown: UnsafeMutablePointer<Int>?) -> Int
{
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_uint_range_map")
    }
    return runtimeUnsignedRangeMap(range, fnPtr, closureRaw, outThrown)
}

@_cdecl("kk_uint_range_mapIndexed")
public func kk_uint_range_mapIndexed(_ rangeRaw: Int, _ fnPtr: Int, _ closureRaw: Int,
                                     _ outThrown: UnsafeMutablePointer<Int>?) -> Int
{
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_uint_range_mapIndexed")
    }
    return runtimeUnsignedRangeMapIndexed(range, fnPtr, closureRaw, outThrown)
}

@_cdecl("kk_uint_range_mapNotNull")
public func kk_uint_range_mapNotNull(_ rangeRaw: Int, _ fnPtr: Int, _ closureRaw: Int,
                                     _ outThrown: UnsafeMutablePointer<Int>?) -> Int
{
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_uint_range_mapNotNull")
    }
    return runtimeUnsignedRangeMapNotNull(range, fnPtr, closureRaw, outThrown)
}

@_cdecl("kk_uint_range_filter")
public func kk_uint_range_filter(_ rangeRaw: Int, _ fnPtr: Int, _ closureRaw: Int,
                                 _ outThrown: UnsafeMutablePointer<Int>?) -> Int
{
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_uint_range_filter")
    }
    return runtimeUnsignedRangeFilter(range, fnPtr, closureRaw, outThrown)
}

@_cdecl("kk_uint_range_filterIndexed")
public func kk_uint_range_filterIndexed(_ rangeRaw: Int, _ fnPtr: Int, _ closureRaw: Int,
                                        _ outThrown: UnsafeMutablePointer<Int>?) -> Int
{
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_uint_range_filterIndexed")
    }
    return runtimeUnsignedRangeFilterIndexed(range, fnPtr, closureRaw, outThrown)
}

@_cdecl("kk_uint_range_filterNot")
public func kk_uint_range_filterNot(_ rangeRaw: Int, _ fnPtr: Int, _ closureRaw: Int,
                                    _ outThrown: UnsafeMutablePointer<Int>?) -> Int
{
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_uint_range_filterNot")
    }
    return runtimeUnsignedRangeFilterNot(range, fnPtr, closureRaw, outThrown)
}

@_cdecl("kk_uint_range_reduce")
public func kk_uint_range_reduce(_ rangeRaw: Int, _ fnPtr: Int, _ closureRaw: Int,
                                 _ outThrown: UnsafeMutablePointer<Int>?) -> Int
{
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_uint_range_reduce")
    }
    return runtimeUnsignedRangeReduce(range, fnPtr, closureRaw, outThrown)
}

@_cdecl("kk_uint_range_reduceIndexed")
public func kk_uint_range_reduceIndexed(_ rangeRaw: Int, _ fnPtr: Int, _ closureRaw: Int,
                                        _ outThrown: UnsafeMutablePointer<Int>?) -> Int
{
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_uint_range_reduceIndexed")
    }
    return runtimeUnsignedRangeReduceIndexed(range, fnPtr, closureRaw, outThrown)
}

@_cdecl("kk_uint_range_fold")
public func kk_uint_range_fold(_ rangeRaw: Int, _ initialValue: Int, _ fnPtr: Int, _ closureRaw: Int,
                               _ outThrown: UnsafeMutablePointer<Int>?) -> Int
{
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_uint_range_fold")
    }
    return runtimeUnsignedRangeFold(range, initialValue, fnPtr, closureRaw, outThrown)
}

@_cdecl("kk_uint_range_foldIndexed")
public func kk_uint_range_foldIndexed(_ rangeRaw: Int, _ initialValue: Int, _ fnPtr: Int, _ closureRaw: Int,
                                      _ outThrown: UnsafeMutablePointer<Int>?) -> Int
{
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_uint_range_foldIndexed")
    }
    return runtimeUnsignedRangeFoldIndexed(range, initialValue, fnPtr, closureRaw, outThrown)
}

@_cdecl("kk_uint_range_find")
public func kk_uint_range_find(_ rangeRaw: Int, _ fnPtr: Int, _ closureRaw: Int,
                               _ outThrown: UnsafeMutablePointer<Int>?) -> Int
{
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_uint_range_find")
    }
    return runtimeUnsignedRangeFirstMatch(range, fnPtr, closureRaw, outThrown, orNull: true)
}

@_cdecl("kk_uint_range_findLast")
public func kk_uint_range_findLast(_ rangeRaw: Int, _ fnPtr: Int, _ closureRaw: Int,
                                   _ outThrown: UnsafeMutablePointer<Int>?) -> Int
{
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_uint_range_findLast")
    }
    return runtimeUnsignedRangeLastMatch(range, fnPtr, closureRaw, outThrown, orNull: true)
}

@_cdecl("kk_uint_range_first_predicate")
public func kk_uint_range_first_predicate(_ rangeRaw: Int, _ fnPtr: Int, _ closureRaw: Int,
                                          _ outThrown: UnsafeMutablePointer<Int>?) -> Int
{
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_uint_range_first_predicate")
    }
    return runtimeUnsignedRangeFirstMatch(range, fnPtr, closureRaw, outThrown, orNull: false)
}

@_cdecl("kk_uint_range_firstOrNull_predicate")
public func kk_uint_range_firstOrNull_predicate(_ rangeRaw: Int, _ fnPtr: Int, _ closureRaw: Int,
                                                _ outThrown: UnsafeMutablePointer<Int>?) -> Int
{
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_uint_range_firstOrNull_predicate")
    }
    return runtimeUnsignedRangeFirstMatch(range, fnPtr, closureRaw, outThrown, orNull: true)
}

@_cdecl("kk_uint_range_firstOrNull")
public func kk_uint_range_firstOrNull(_ rangeRaw: Int) -> Int {
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_uint_range_firstOrNull")
    }
    return runtimeUnsignedRangeIsEmpty(range) ? runtimeNullSentinelInt : range.first
}

@_cdecl("kk_uint_range_last_predicate")
public func kk_uint_range_last_predicate(_ rangeRaw: Int, _ fnPtr: Int, _ closureRaw: Int,
                                         _ outThrown: UnsafeMutablePointer<Int>?) -> Int
{
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_uint_range_last_predicate")
    }
    return runtimeUnsignedRangeLastMatch(range, fnPtr, closureRaw, outThrown, orNull: false)
}

@_cdecl("kk_uint_range_lastOrNull_predicate")
public func kk_uint_range_lastOrNull_predicate(_ rangeRaw: Int, _ fnPtr: Int, _ closureRaw: Int,
                                               _ outThrown: UnsafeMutablePointer<Int>?) -> Int
{
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_uint_range_lastOrNull_predicate")
    }
    return runtimeUnsignedRangeLastMatch(range, fnPtr, closureRaw, outThrown, orNull: true)
}

@_cdecl("kk_uint_range_lastOrNull")
public func kk_uint_range_lastOrNull(_ rangeRaw: Int) -> Int {
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_uint_range_lastOrNull")
    }
    return runtimeUnsignedRangeIsEmpty(range) ? runtimeNullSentinelInt : range.last
}

@_cdecl("kk_uint_range_randomOrNull")
public func kk_uint_range_randomOrNull(_ rangeRaw: Int) -> Int {
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_uint_range_randomOrNull")
    }
    return runtimeUnsignedRangeRandomOrNull(range, randomRaw: nil)
}

@_cdecl("kk_uint_range_randomOrNull_random")
public func kk_uint_range_randomOrNull_random(_ rangeRaw: Int, _ randomRaw: Int) -> Int {
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_uint_range_randomOrNull_random")
    }
    return runtimeUnsignedRangeRandomOrNull(range, randomRaw: randomRaw)
}

@_cdecl("kk_uint_range_random")
public func kk_uint_range_random(_ rangeRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_uint_range_random")
    }
    return runtimeUnsignedRangeRandom(first: UInt(bitPattern: range.first),
                                      last: UInt(bitPattern: range.last),
                                      step: range.step, randomRaw: 0, outThrown: outThrown)
}

@_cdecl("kk_uint_range_random_random")
public func kk_uint_range_random_random(_ rangeRaw: Int, _ randomRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_uint_range_random_random")
    }
    return runtimeUnsignedRangeRandom(first: UInt(bitPattern: range.first),
                                      last: UInt(bitPattern: range.last),
                                      step: range.step, randomRaw: randomRaw, outThrown: outThrown)
}

@_cdecl("kk_uint_range_any")
public func kk_uint_range_any(_ rangeRaw: Int, _ fnPtr: Int, _ closureRaw: Int,
                              _ outThrown: UnsafeMutablePointer<Int>?) -> Int
{
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_uint_range_any")
    }
    return runtimeUnsignedRangeAny(range, fnPtr, closureRaw, outThrown)
}

@_cdecl("kk_uint_range_all")
public func kk_uint_range_all(_ rangeRaw: Int, _ fnPtr: Int, _ closureRaw: Int,
                              _ outThrown: UnsafeMutablePointer<Int>?) -> Int
{
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_uint_range_all")
    }
    return runtimeUnsignedRangeAll(range, fnPtr, closureRaw, outThrown)
}

@_cdecl("kk_uint_range_none")
public func kk_uint_range_none(_ rangeRaw: Int, _ fnPtr: Int, _ closureRaw: Int,
                               _ outThrown: UnsafeMutablePointer<Int>?) -> Int
{
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_uint_range_none")
    }
    return runtimeUnsignedRangeNone(range, fnPtr, closureRaw, outThrown)
}

@_cdecl("kk_uint_range_chunked")
public func kk_uint_range_chunked(_ rangeRaw: Int, _ size: Int) -> Int {
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_uint_range_chunked")
    }
    return runtimeUnsignedRangeChunked(range, size)
}

@_cdecl("kk_uint_range_windowed")
public func kk_uint_range_windowed(_ rangeRaw: Int, _ size: Int, _ step: Int, _ partialWindows: Int) -> Int {
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_uint_range_windowed")
    }
    return runtimeUnsignedRangeWindowed(range, size, step, partialWindows)
}

@_cdecl("kk_uint_range_take")
public func kk_uint_range_take(_ rangeRaw: Int, _ n: Int) -> Int {
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_uint_range_take")
    }
    return runtimeUnsignedRangeTake(range, n)
}

@_cdecl("kk_uint_range_drop")
public func kk_uint_range_drop(_ rangeRaw: Int, _ n: Int) -> Int {
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_uint_range_drop")
    }
    return runtimeUnsignedRangeDrop(range, n)
}

@_cdecl("kk_uint_range_average")
public func kk_uint_range_average(_ rangeRaw: Int) -> Int {
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_uint_range_average")
    }
    return runtimeUnsignedRangeAverage(range)
}

@_cdecl("kk_uint_range_sorted")
public func kk_uint_range_sorted(_ rangeRaw: Int) -> Int {
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_uint_range_sorted")
    }
    return runtimeUnsignedRangeSorted(range)
}

// MARK: - ULong HOFs (STDLIB-RANGE-037/039) — identical logic to UInt, different @_cdecl names

@_cdecl("kk_ulong_range_mapIndexed")
public func kk_ulong_range_mapIndexed(_ rangeRaw: Int, _ fnPtr: Int, _ closureRaw: Int,
                                      _ outThrown: UnsafeMutablePointer<Int>?) -> Int
{
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_ulong_range_mapIndexed")
    }
    return runtimeUnsignedRangeMapIndexed(range, fnPtr, closureRaw, outThrown)
}

@_cdecl("kk_ulong_range_mapNotNull")
public func kk_ulong_range_mapNotNull(_ rangeRaw: Int, _ fnPtr: Int, _ closureRaw: Int,
                                      _ outThrown: UnsafeMutablePointer<Int>?) -> Int
{
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_ulong_range_mapNotNull")
    }
    return runtimeUnsignedRangeMapNotNull(range, fnPtr, closureRaw, outThrown)
}

@_cdecl("kk_ulong_range_filter")
public func kk_ulong_range_filter(_ rangeRaw: Int, _ fnPtr: Int, _ closureRaw: Int,
                                  _ outThrown: UnsafeMutablePointer<Int>?) -> Int
{
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_ulong_range_filter")
    }
    return runtimeUnsignedRangeFilter(range, fnPtr, closureRaw, outThrown)
}

@_cdecl("kk_ulong_range_filterIndexed")
public func kk_ulong_range_filterIndexed(_ rangeRaw: Int, _ fnPtr: Int, _ closureRaw: Int,
                                         _ outThrown: UnsafeMutablePointer<Int>?) -> Int
{
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_ulong_range_filterIndexed")
    }
    return runtimeUnsignedRangeFilterIndexed(range, fnPtr, closureRaw, outThrown)
}

@_cdecl("kk_ulong_range_filterNot")
public func kk_ulong_range_filterNot(_ rangeRaw: Int, _ fnPtr: Int, _ closureRaw: Int,
                                     _ outThrown: UnsafeMutablePointer<Int>?) -> Int
{
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_ulong_range_filterNot")
    }
    return runtimeUnsignedRangeFilterNot(range, fnPtr, closureRaw, outThrown)
}

@_cdecl("kk_ulong_range_reduce")
public func kk_ulong_range_reduce(_ rangeRaw: Int, _ fnPtr: Int, _ closureRaw: Int,
                                  _ outThrown: UnsafeMutablePointer<Int>?) -> Int
{
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_ulong_range_reduce")
    }
    return runtimeUnsignedRangeReduce(range, fnPtr, closureRaw, outThrown)
}

@_cdecl("kk_ulong_range_reduceIndexed")
public func kk_ulong_range_reduceIndexed(_ rangeRaw: Int, _ fnPtr: Int, _ closureRaw: Int,
                                         _ outThrown: UnsafeMutablePointer<Int>?) -> Int
{
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_ulong_range_reduceIndexed")
    }
    return runtimeUnsignedRangeReduceIndexed(range, fnPtr, closureRaw, outThrown)
}

@_cdecl("kk_ulong_range_fold")
public func kk_ulong_range_fold(_ rangeRaw: Int, _ initialValue: Int, _ fnPtr: Int, _ closureRaw: Int,
                                _ outThrown: UnsafeMutablePointer<Int>?) -> Int
{
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_ulong_range_fold")
    }
    return runtimeUnsignedRangeFold(range, initialValue, fnPtr, closureRaw, outThrown)
}

@_cdecl("kk_ulong_range_foldIndexed")
public func kk_ulong_range_foldIndexed(_ rangeRaw: Int, _ initialValue: Int, _ fnPtr: Int, _ closureRaw: Int,
                                       _ outThrown: UnsafeMutablePointer<Int>?) -> Int
{
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_ulong_range_foldIndexed")
    }
    return runtimeUnsignedRangeFoldIndexed(range, initialValue, fnPtr, closureRaw, outThrown)
}

@_cdecl("kk_ulong_range_find")
public func kk_ulong_range_find(_ rangeRaw: Int, _ fnPtr: Int, _ closureRaw: Int,
                                _ outThrown: UnsafeMutablePointer<Int>?) -> Int
{
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_ulong_range_find")
    }
    return runtimeUnsignedRangeFirstMatch(range, fnPtr, closureRaw, outThrown, orNull: true)
}

@_cdecl("kk_ulong_range_findLast")
public func kk_ulong_range_findLast(_ rangeRaw: Int, _ fnPtr: Int, _ closureRaw: Int,
                                    _ outThrown: UnsafeMutablePointer<Int>?) -> Int
{
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_ulong_range_findLast")
    }
    return runtimeUnsignedRangeLastMatch(range, fnPtr, closureRaw, outThrown, orNull: true)
}

@_cdecl("kk_ulong_range_first_predicate")
public func kk_ulong_range_first_predicate(_ rangeRaw: Int, _ fnPtr: Int, _ closureRaw: Int,
                                           _ outThrown: UnsafeMutablePointer<Int>?) -> Int
{
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_ulong_range_first_predicate")
    }
    return runtimeUnsignedRangeFirstMatch(range, fnPtr, closureRaw, outThrown, orNull: false)
}

@_cdecl("kk_ulong_range_firstOrNull_predicate")
public func kk_ulong_range_firstOrNull_predicate(_ rangeRaw: Int, _ fnPtr: Int, _ closureRaw: Int,
                                                 _ outThrown: UnsafeMutablePointer<Int>?) -> Int
{
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_ulong_range_firstOrNull_predicate")
    }
    return runtimeUnsignedRangeFirstMatch(range, fnPtr, closureRaw, outThrown, orNull: true)
}

@_cdecl("kk_ulong_range_firstOrNull")
public func kk_ulong_range_firstOrNull(_ rangeRaw: Int) -> Int {
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_ulong_range_firstOrNull")
    }
    return runtimeUnsignedRangeIsEmpty(range) ? runtimeNullSentinelInt : range.first
}

@_cdecl("kk_ulong_range_last_predicate")
public func kk_ulong_range_last_predicate(_ rangeRaw: Int, _ fnPtr: Int, _ closureRaw: Int,
                                          _ outThrown: UnsafeMutablePointer<Int>?) -> Int
{
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_ulong_range_last_predicate")
    }
    return runtimeUnsignedRangeLastMatch(range, fnPtr, closureRaw, outThrown, orNull: false)
}

@_cdecl("kk_ulong_range_lastOrNull_predicate")
public func kk_ulong_range_lastOrNull_predicate(_ rangeRaw: Int, _ fnPtr: Int, _ closureRaw: Int,
                                                _ outThrown: UnsafeMutablePointer<Int>?) -> Int
{
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_ulong_range_lastOrNull_predicate")
    }
    return runtimeUnsignedRangeLastMatch(range, fnPtr, closureRaw, outThrown, orNull: true)
}

@_cdecl("kk_ulong_range_lastOrNull")
public func kk_ulong_range_lastOrNull(_ rangeRaw: Int) -> Int {
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_ulong_range_lastOrNull")
    }
    return runtimeUnsignedRangeIsEmpty(range) ? runtimeNullSentinelInt : range.last
}

@_cdecl("kk_ulong_range_randomOrNull")
public func kk_ulong_range_randomOrNull(_ rangeRaw: Int) -> Int {
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_ulong_range_randomOrNull")
    }
    return runtimeUnsignedRangeRandomOrNull(range, randomRaw: nil)
}

@_cdecl("kk_ulong_range_randomOrNull_random")
public func kk_ulong_range_randomOrNull_random(_ rangeRaw: Int, _ randomRaw: Int) -> Int {
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_ulong_range_randomOrNull_random")
    }
    return runtimeUnsignedRangeRandomOrNull(range, randomRaw: randomRaw)
}

@_cdecl("kk_ulong_range_random")
public func kk_ulong_range_random(_ rangeRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_ulong_range_random")
    }
    return runtimeUnsignedRangeRandom(first: UInt(bitPattern: range.first),
                                      last: UInt(bitPattern: range.last),
                                      step: range.step, randomRaw: 0, outThrown: outThrown)
}

@_cdecl("kk_ulong_range_random_random")
public func kk_ulong_range_random_random(_ rangeRaw: Int, _ randomRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_ulong_range_random_random")
    }
    return runtimeUnsignedRangeRandom(first: UInt(bitPattern: range.first),
                                      last: UInt(bitPattern: range.last),
                                      step: range.step, randomRaw: randomRaw, outThrown: outThrown)
}

@_cdecl("kk_ulong_range_any")
public func kk_ulong_range_any(_ rangeRaw: Int, _ fnPtr: Int, _ closureRaw: Int,
                               _ outThrown: UnsafeMutablePointer<Int>?) -> Int
{
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_ulong_range_any")
    }
    return runtimeUnsignedRangeAny(range, fnPtr, closureRaw, outThrown)
}

@_cdecl("kk_ulong_range_all")
public func kk_ulong_range_all(_ rangeRaw: Int, _ fnPtr: Int, _ closureRaw: Int,
                               _ outThrown: UnsafeMutablePointer<Int>?) -> Int
{
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_ulong_range_all")
    }
    return runtimeUnsignedRangeAll(range, fnPtr, closureRaw, outThrown)
}

@_cdecl("kk_ulong_range_none")
public func kk_ulong_range_none(_ rangeRaw: Int, _ fnPtr: Int, _ closureRaw: Int,
                                _ outThrown: UnsafeMutablePointer<Int>?) -> Int
{
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_ulong_range_none")
    }
    return runtimeUnsignedRangeNone(range, fnPtr, closureRaw, outThrown)
}

@_cdecl("kk_ulong_range_chunked")
public func kk_ulong_range_chunked(_ rangeRaw: Int, _ size: Int) -> Int {
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_ulong_range_chunked")
    }
    return runtimeUnsignedRangeChunked(range, size)
}

@_cdecl("kk_ulong_range_windowed")
public func kk_ulong_range_windowed(_ rangeRaw: Int, _ size: Int, _ step: Int, _ partialWindows: Int) -> Int {
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_ulong_range_windowed")
    }
    return runtimeUnsignedRangeWindowed(range, size, step, partialWindows)
}

@_cdecl("kk_ulong_range_take")
public func kk_ulong_range_take(_ rangeRaw: Int, _ n: Int) -> Int {
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_ulong_range_take")
    }
    return runtimeUnsignedRangeTake(range, n)
}

@_cdecl("kk_ulong_range_drop")
public func kk_ulong_range_drop(_ rangeRaw: Int, _ n: Int) -> Int {
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_ulong_range_drop")
    }
    return runtimeUnsignedRangeDrop(range, n)
}

@_cdecl("kk_ulong_range_average")
public func kk_ulong_range_average(_ rangeRaw: Int) -> Int {
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_ulong_range_average")
    }
    return runtimeUnsignedRangeAverage(range)
}

@_cdecl("kk_ulong_range_sorted")
public func kk_ulong_range_sorted(_ rangeRaw: Int) -> Int {
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_ulong_range_sorted")
    }
    return runtimeUnsignedRangeSorted(range)
}

// MARK: - ULongProgression operations (STDLIB-RANGE-039)

@_cdecl("kk_ulong_rangeTo")
public func kk_ulong_rangeTo(_ lhs: Int, _ rhs: Int) -> Int {
    registerRuntimeObject(RuntimeRangeBox(first: lhs, last: rhs, step: 1))
}

@_cdecl("kk_ulong_downTo")
public func kk_ulong_downTo(_ lhs: Int, _ rhs: Int) -> Int {
    registerRuntimeObject(RuntimeRangeBox(first: lhs, last: rhs, step: -1))
}

@_cdecl("kk_ulong_step")
public func kk_ulong_step(_ rangeRaw: Int, _ stepValue: Int) -> Int {
    guard stepValue > 0 else { return rangeRaw }
    guard stepValue != Int.min else { return rangeRaw }
    guard let range = runtimeRangeBox(from: rangeRaw) else { return rangeRaw }
    if range.step == 0 { return rangeRaw }
    let nextStep = range.step < 0 ? (0 &- stepValue) : stepValue
    let firstUnsigned = UInt(bitPattern: range.first)
    let lastUnsigned = UInt(bitPattern: range.last)
    let alignedLast: Int
    if nextStep > 0 {
        guard firstUnsigned <= lastUnsigned else {
            return registerRuntimeObject(RuntimeRangeBox(first: range.first, last: range.last, step: nextStep))
        }
        let diff = range.last &- range.first
        let remainder = diff % nextStep
        alignedLast = range.last &- remainder
    } else {
        guard firstUnsigned >= lastUnsigned else {
            return registerRuntimeObject(RuntimeRangeBox(first: range.first, last: range.last, step: nextStep))
        }
        let diff = range.first &- range.last
        let remainder = diff % (0 &- nextStep)
        alignedLast = range.last &+ remainder
    }
    return registerRuntimeObject(RuntimeRangeBox(first: range.first, last: alignedLast, step: nextStep))
}

@_cdecl("kk_ulong_range_reversed")
public func kk_ulong_range_reversed(_ rangeRaw: Int) -> Int {
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_ulong_range_reversed")
    }
    return registerRuntimeObject(RuntimeRangeBox(first: range.last, last: range.first, step: 0 &- range.step))
}

// MARK: - ULongRange toList (STDLIB-524)

@_cdecl("kk_ulong_range_toList")
public func kk_ulong_range_toList(_ rangeRaw: Int) -> Int {
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_ulong_range_toList")
    }
    return runtimeUnsignedRangeToList(range)
}

@_cdecl("kk_range_step")
public func kk_range_step(_ rangeRaw: Int) -> Int {
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_range_step")
    }
    return range.step
}

private func runtimeRangeIteratorBox(from rawValue: Int) -> RuntimeRangeIteratorBox? {
    guard let pointer = UnsafeMutableRawPointer(bitPattern: rawValue) else {
        return nil
    }
    let isObjectPointer = runtimeStorage.withGCLock { state in
        state.objectPointers.contains(UInt(bitPattern: pointer))
    }
    guard isObjectPointer else {
        return nil
    }
    return tryCast(pointer, to: RuntimeRangeIteratorBox.self)
}

private func runtimeIteratorBuilderBox(from rawValue: Int) -> RuntimeIteratorBuilderBox? {
    guard let pointer = UnsafeMutableRawPointer(bitPattern: rawValue) else {
        return nil
    }
    let isObjectPointer = runtimeStorage.withGCLock { state in
        state.objectPointers.contains(UInt(bitPattern: pointer))
    }
    guard isObjectPointer else {
        return nil
    }
    return tryCast(pointer, to: RuntimeIteratorBuilderBox.self)
}
