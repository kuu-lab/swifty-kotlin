
// swiftlint:disable file_length

// IntRange higher-order / aggregation / search / partitioning
// runtime entry points (STDLIB-091, STDLIB-RANGE-038).
//
// All HOF logic lives in RuntimeRangeSharedHOF.swift (runtimeSignedRange* helpers).
// These @_cdecl functions are thin ABI entry points.

// MARK: - IntRange HOFs (STDLIB-091)

@_cdecl("kk_range_toList")
public func kk_range_toList(_ rangeRaw: Int) -> Int {
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_range_toList")
    }
    return runtimeSignedRangeToList(range)
}

@_cdecl("kk_range_forEach")
public func kk_range_forEach(_ rangeRaw: Int, _ fnPtr: Int, _ closureRaw: Int,
                             _ outThrown: UnsafeMutablePointer<Int>?) -> Int
{
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_range_forEach")
    }
    return runtimeSignedRangeForEach(range, fnPtr, closureRaw, outThrown)
}

@_cdecl("kk_range_map")
public func kk_range_map(_ rangeRaw: Int, _ fnPtr: Int, _ closureRaw: Int,
                         _ outThrown: UnsafeMutablePointer<Int>?) -> Int
{
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_range_map")
    }
    return runtimeSignedRangeMap(range, fnPtr, closureRaw, outThrown)
}

@_cdecl("kk_range_mapIndexed")
public func kk_range_mapIndexed(_ rangeRaw: Int, _ fnPtr: Int, _ closureRaw: Int,
                                _ outThrown: UnsafeMutablePointer<Int>?) -> Int
{
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_range_mapIndexed")
    }
    return runtimeSignedRangeMapIndexed(range, fnPtr, closureRaw, outThrown)
}

@_cdecl("kk_range_mapNotNull")
public func kk_range_mapNotNull(_ rangeRaw: Int, _ fnPtr: Int, _ closureRaw: Int,
                                _ outThrown: UnsafeMutablePointer<Int>?) -> Int
{
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_range_mapNotNull")
    }
    return runtimeSignedRangeMapNotNull(range, fnPtr, closureRaw, outThrown)
}

@_cdecl("kk_range_filter")
public func kk_range_filter(_ rangeRaw: Int, _ fnPtr: Int, _ closureRaw: Int,
                            _ outThrown: UnsafeMutablePointer<Int>?) -> Int
{
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_range_filter")
    }
    return runtimeSignedRangeFilter(range, fnPtr, closureRaw, outThrown)
}

@_cdecl("kk_range_filterIndexed")
public func kk_range_filterIndexed(_ rangeRaw: Int, _ fnPtr: Int, _ closureRaw: Int,
                                   _ outThrown: UnsafeMutablePointer<Int>?) -> Int
{
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_range_filterIndexed")
    }
    return runtimeSignedRangeFilterIndexed(range, fnPtr, closureRaw, outThrown)
}

@_cdecl("kk_range_filterNot")
public func kk_range_filterNot(_ rangeRaw: Int, _ fnPtr: Int, _ closureRaw: Int,
                               _ outThrown: UnsafeMutablePointer<Int>?) -> Int
{
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_range_filterNot")
    }
    return runtimeSignedRangeFilterNot(range, fnPtr, closureRaw, outThrown)
}

// MARK: - IntRange Aggregation HOFs (STDLIB-RANGE-038)

@_cdecl("kk_range_reduce")
public func kk_range_reduce(_ rangeRaw: Int, _ fnPtr: Int, _ closureRaw: Int,
                            _ outThrown: UnsafeMutablePointer<Int>?) -> Int
{
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_range_reduce")
    }
    return runtimeSignedRangeReduce(range, fnPtr, closureRaw, outThrown)
}

@_cdecl("kk_range_reduceIndexed")
public func kk_range_reduceIndexed(_ rangeRaw: Int, _ fnPtr: Int, _ closureRaw: Int,
                                   _ outThrown: UnsafeMutablePointer<Int>?) -> Int
{
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_range_reduceIndexed")
    }
    return runtimeSignedRangeReduceIndexed(range, fnPtr, closureRaw, outThrown)
}

@_cdecl("kk_range_fold")
public func kk_range_fold(_ rangeRaw: Int, _ initialValue: Int, _ fnPtr: Int, _ closureRaw: Int,
                          _ outThrown: UnsafeMutablePointer<Int>?) -> Int
{
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_range_fold")
    }
    return runtimeSignedRangeFold(range, initialValue, fnPtr, closureRaw, outThrown)
}

@_cdecl("kk_range_foldIndexed")
public func kk_range_foldIndexed(_ rangeRaw: Int, _ initialValue: Int, _ fnPtr: Int, _ closureRaw: Int,
                                 _ outThrown: UnsafeMutablePointer<Int>?) -> Int
{
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_range_foldIndexed")
    }
    return runtimeSignedRangeFoldIndexed(range, initialValue, fnPtr, closureRaw, outThrown)
}

// MARK: - IntRange Search and Predicate HOFs (STDLIB-RANGE-038)

@_cdecl("kk_range_find")
public func kk_range_find(_ rangeRaw: Int, _ fnPtr: Int, _ closureRaw: Int,
                          _ outThrown: UnsafeMutablePointer<Int>?) -> Int
{
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_range_find")
    }
    return runtimeSignedRangeFirstMatch(range, fnPtr, closureRaw, outThrown, orNull: true)
}

@_cdecl("kk_range_findLast")
public func kk_range_findLast(_ rangeRaw: Int, _ fnPtr: Int, _ closureRaw: Int,
                              _ outThrown: UnsafeMutablePointer<Int>?) -> Int
{
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_range_findLast")
    }
    return runtimeSignedRangeLastMatch(range, fnPtr, closureRaw, outThrown, orNull: true)
}

@_cdecl("kk_range_first_predicate")
public func kk_range_first_predicate(_ rangeRaw: Int, _ fnPtr: Int, _ closureRaw: Int,
                                     _ outThrown: UnsafeMutablePointer<Int>?) -> Int
{
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_range_first_predicate")
    }
    return runtimeSignedRangeFirstMatch(range, fnPtr, closureRaw, outThrown, orNull: false)
}

@_cdecl("kk_range_firstOrNull_predicate")
public func kk_range_firstOrNull_predicate(_ rangeRaw: Int, _ fnPtr: Int, _ closureRaw: Int,
                                           _ outThrown: UnsafeMutablePointer<Int>?) -> Int
{
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_range_firstOrNull_predicate")
    }
    return runtimeSignedRangeFirstMatch(range, fnPtr, closureRaw, outThrown, orNull: true)
}

@_cdecl("kk_range_firstOrNull")
public func kk_range_firstOrNull(_ rangeRaw: Int) -> Int {
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_range_firstOrNull")
    }
    if range.step == 0 { return runtimeNullSentinelInt }
    if range.step > 0 { return range.first <= range.last ? range.first : runtimeNullSentinelInt }
    return range.first >= range.last ? range.first : runtimeNullSentinelInt
}

@_cdecl("kk_range_randomOrNull")
public func kk_range_randomOrNull(_ rangeRaw: Int) -> Int {
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_range_randomOrNull")
    }
    return runtimeSignedRangeRandomOrNull(range, randomRaw: nil)
}

@_cdecl("kk_range_randomOrNull_random")
public func kk_range_randomOrNull_random(_ rangeRaw: Int, _ randomRaw: Int) -> Int {
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_range_randomOrNull_random")
    }
    return runtimeSignedRangeRandomOrNull(range, randomRaw: randomRaw)
}

@_cdecl("kk_range_last_predicate")
public func kk_range_last_predicate(_ rangeRaw: Int, _ fnPtr: Int, _ closureRaw: Int,
                                    _ outThrown: UnsafeMutablePointer<Int>?) -> Int
{
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_range_last_predicate")
    }
    return runtimeSignedRangeLastMatch(range, fnPtr, closureRaw, outThrown, orNull: false)
}

@_cdecl("kk_range_lastOrNull_predicate")
public func kk_range_lastOrNull_predicate(_ rangeRaw: Int, _ fnPtr: Int, _ closureRaw: Int,
                                          _ outThrown: UnsafeMutablePointer<Int>?) -> Int
{
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_range_lastOrNull_predicate")
    }
    return runtimeSignedRangeLastMatch(range, fnPtr, closureRaw, outThrown, orNull: true)
}

@_cdecl("kk_range_lastOrNull")
public func kk_range_lastOrNull(_ rangeRaw: Int) -> Int {
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_range_lastOrNull")
    }
    if range.step == 0 { return runtimeNullSentinelInt }
    if range.step > 0 { return range.first <= range.last ? range.last : runtimeNullSentinelInt }
    return range.first >= range.last ? range.last : runtimeNullSentinelInt
}

@_cdecl("kk_range_random")
public func kk_range_random(_ rangeRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_range_random")
    }
    return runtimeSignedRangeRandom(first: range.first, last: range.last, step: range.step,
                                    randomRaw: 0, outThrown: outThrown)
}

@_cdecl("kk_range_random_random")
public func kk_range_random_random(_ rangeRaw: Int, _ randomRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_range_random_random")
    }
    return runtimeSignedRangeRandom(first: range.first, last: range.last, step: range.step,
                                    randomRaw: randomRaw, outThrown: outThrown)
}

@_cdecl("kk_random_nextInt_rangeObject")
public func kk_random_nextInt_rangeObject(_ randomRaw: Int, _ rangeRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_random_nextInt_rangeObject")
    }
    let isEmpty = range.step == 0
        || (range.step > 0 ? range.first > range.last : range.first < range.last)
    if isEmpty {
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(
            message: "Random range is empty: \(range.first)..\(range.last)."
        )
        return 0
    }
    return runtimeSignedRangeRandom(first: range.first, last: range.last, step: range.step,
                                    randomRaw: randomRaw, outThrown: outThrown)
}

@_cdecl("kk_range_any")
public func kk_range_any(_ rangeRaw: Int, _ fnPtr: Int, _ closureRaw: Int,
                         _ outThrown: UnsafeMutablePointer<Int>?) -> Int
{
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_range_any")
    }
    return runtimeSignedRangeAny(range, fnPtr, closureRaw, outThrown)
}

@_cdecl("kk_range_all")
public func kk_range_all(_ rangeRaw: Int, _ fnPtr: Int, _ closureRaw: Int,
                         _ outThrown: UnsafeMutablePointer<Int>?) -> Int
{
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_range_all")
    }
    return runtimeSignedRangeAll(range, fnPtr, closureRaw, outThrown)
}

@_cdecl("kk_range_none")
public func kk_range_none(_ rangeRaw: Int, _ fnPtr: Int, _ closureRaw: Int,
                          _ outThrown: UnsafeMutablePointer<Int>?) -> Int
{
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_range_none")
    }
    return runtimeSignedRangeNone(range, fnPtr, closureRaw, outThrown)
}

// MARK: - IntRange Partitioning HOFs (STDLIB-RANGE-038)

@_cdecl("kk_range_chunked")
public func kk_range_chunked(_ rangeRaw: Int, _ size: Int) -> Int {
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_range_chunked")
    }
    return runtimeSignedRangeChunked(range, size)
}

@_cdecl("kk_range_windowed")
public func kk_range_windowed(_ rangeRaw: Int, _ size: Int, _ step: Int, _ partialWindows: Int) -> Int {
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_range_windowed")
    }
    return runtimeSignedRangeWindowed(range, size, step, partialWindows)
}
