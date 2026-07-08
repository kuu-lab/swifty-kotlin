// IntRange higher-order / aggregation / search / partitioning
// runtime entry points (STDLIB-091, STDLIB-RANGE-038).
//
// HOF logic and range-handle validation live in RuntimeRangeSharedHOF.swift.
// These @_cdecl functions are thin ABI entry points.

// MARK: - IntRange HOFs (STDLIB-091)

@_cdecl("kk_range_toList")
public func kk_range_toList(_ rangeRaw: Int) -> Int {
    runtimeRangeEntry(RuntimeSignedRangeHOFKind.self, rangeRaw, functionName: "kk_range_toList") { range in
        RuntimeSignedRangeHOFKind.toList(range)
    }
}

@_cdecl("kk_range_forEach")
public func kk_range_forEach(_ rangeRaw: Int, _ fnPtr: Int, _ closureRaw: Int,
                             _ outThrown: UnsafeMutablePointer<Int>?) -> Int
{
    runtimeRangeHOFEntry(RuntimeSignedRangeHOFKind.self, rangeRaw, fnPtr, closureRaw, outThrown,
                         functionName: "kk_range_forEach", operation: RuntimeSignedRangeHOFKind.forEach)
}

@_cdecl("kk_range_map")
public func kk_range_map(_ rangeRaw: Int, _ fnPtr: Int, _ closureRaw: Int,
                         _ outThrown: UnsafeMutablePointer<Int>?) -> Int
{
    runtimeRangeHOFEntry(RuntimeSignedRangeHOFKind.self, rangeRaw, fnPtr, closureRaw, outThrown,
                         functionName: "kk_range_map", operation: RuntimeSignedRangeHOFKind.map)
}

@_cdecl("kk_range_mapIndexed")
public func kk_range_mapIndexed(_ rangeRaw: Int, _ fnPtr: Int, _ closureRaw: Int,
                                _ outThrown: UnsafeMutablePointer<Int>?) -> Int
{
    runtimeRangeHOFEntry(RuntimeSignedRangeHOFKind.self, rangeRaw, fnPtr, closureRaw, outThrown,
                         functionName: "kk_range_mapIndexed", operation: RuntimeSignedRangeHOFKind.mapIndexed)
}

@_cdecl("kk_range_mapNotNull")
public func kk_range_mapNotNull(_ rangeRaw: Int, _ fnPtr: Int, _ closureRaw: Int,
                                _ outThrown: UnsafeMutablePointer<Int>?) -> Int
{
    runtimeRangeHOFEntry(RuntimeSignedRangeHOFKind.self, rangeRaw, fnPtr, closureRaw, outThrown,
                         functionName: "kk_range_mapNotNull", operation: RuntimeSignedRangeHOFKind.mapNotNull)
}

@_cdecl("kk_range_filter")
public func kk_range_filter(_ rangeRaw: Int, _ fnPtr: Int, _ closureRaw: Int,
                            _ outThrown: UnsafeMutablePointer<Int>?) -> Int
{
    runtimeRangeHOFEntry(RuntimeSignedRangeHOFKind.self, rangeRaw, fnPtr, closureRaw, outThrown,
                         functionName: "kk_range_filter", operation: RuntimeSignedRangeHOFKind.filter)
}

@_cdecl("kk_range_filterIndexed")
public func kk_range_filterIndexed(_ rangeRaw: Int, _ fnPtr: Int, _ closureRaw: Int,
                                   _ outThrown: UnsafeMutablePointer<Int>?) -> Int
{
    runtimeRangeHOFEntry(RuntimeSignedRangeHOFKind.self, rangeRaw, fnPtr, closureRaw, outThrown,
                         functionName: "kk_range_filterIndexed", operation: RuntimeSignedRangeHOFKind.filterIndexed)
}

@_cdecl("kk_range_filterNot")
public func kk_range_filterNot(_ rangeRaw: Int, _ fnPtr: Int, _ closureRaw: Int,
                               _ outThrown: UnsafeMutablePointer<Int>?) -> Int
{
    runtimeRangeHOFEntry(RuntimeSignedRangeHOFKind.self, rangeRaw, fnPtr, closureRaw, outThrown,
                         functionName: "kk_range_filterNot", operation: RuntimeSignedRangeHOFKind.filterNot)
}

// MARK: - IntRange Aggregation HOFs (STDLIB-RANGE-038)

@_cdecl("kk_range_reduce")
public func kk_range_reduce(_ rangeRaw: Int, _ fnPtr: Int, _ closureRaw: Int,
                            _ outThrown: UnsafeMutablePointer<Int>?) -> Int
{
    runtimeRangeHOFEntry(RuntimeSignedRangeHOFKind.self, rangeRaw, fnPtr, closureRaw, outThrown,
                         functionName: "kk_range_reduce", operation: RuntimeSignedRangeHOFKind.reduce)
}

@_cdecl("kk_range_reduceIndexed")
public func kk_range_reduceIndexed(_ rangeRaw: Int, _ fnPtr: Int, _ closureRaw: Int,
                                   _ outThrown: UnsafeMutablePointer<Int>?) -> Int
{
    runtimeRangeHOFEntry(RuntimeSignedRangeHOFKind.self, rangeRaw, fnPtr, closureRaw, outThrown,
                         functionName: "kk_range_reduceIndexed", operation: RuntimeSignedRangeHOFKind.reduceIndexed)
}

@_cdecl("kk_range_fold")
public func kk_range_fold(_ rangeRaw: Int, _ initialValue: Int, _ fnPtr: Int, _ closureRaw: Int,
                          _ outThrown: UnsafeMutablePointer<Int>?) -> Int
{
    runtimeRangeFoldHOFEntry(RuntimeSignedRangeHOFKind.self, rangeRaw, initialValue, fnPtr, closureRaw, outThrown,
                             functionName: "kk_range_fold", operation: RuntimeSignedRangeHOFKind.fold)
}

@_cdecl("kk_range_foldIndexed")
public func kk_range_foldIndexed(_ rangeRaw: Int, _ initialValue: Int, _ fnPtr: Int, _ closureRaw: Int,
                                 _ outThrown: UnsafeMutablePointer<Int>?) -> Int
{
    runtimeRangeFoldHOFEntry(RuntimeSignedRangeHOFKind.self, rangeRaw, initialValue, fnPtr, closureRaw, outThrown,
                             functionName: "kk_range_foldIndexed", operation: RuntimeSignedRangeHOFKind.foldIndexed)
}

// MARK: - IntRange Search and Predicate HOFs (STDLIB-RANGE-038)

@_cdecl("kk_range_find")
public func kk_range_find(_ rangeRaw: Int, _ fnPtr: Int, _ closureRaw: Int,
                          _ outThrown: UnsafeMutablePointer<Int>?) -> Int
{
    runtimeRangeFirstMatchEntry(RuntimeSignedRangeHOFKind.self, rangeRaw, fnPtr, closureRaw, outThrown,
                                functionName: "kk_range_find", orNull: true)
}

@_cdecl("kk_range_findLast")
public func kk_range_findLast(_ rangeRaw: Int, _ fnPtr: Int, _ closureRaw: Int,
                              _ outThrown: UnsafeMutablePointer<Int>?) -> Int
{
    runtimeRangeLastMatchEntry(RuntimeSignedRangeHOFKind.self, rangeRaw, fnPtr, closureRaw, outThrown,
                               functionName: "kk_range_findLast", orNull: true)
}

@_cdecl("kk_range_first_predicate")
public func kk_range_first_predicate(_ rangeRaw: Int, _ fnPtr: Int, _ closureRaw: Int,
                                     _ outThrown: UnsafeMutablePointer<Int>?) -> Int
{
    runtimeRangeFirstMatchEntry(RuntimeSignedRangeHOFKind.self, rangeRaw, fnPtr, closureRaw, outThrown,
                                functionName: "kk_range_first_predicate", orNull: false)
}

@_cdecl("kk_range_firstOrNull_predicate")
public func kk_range_firstOrNull_predicate(_ rangeRaw: Int, _ fnPtr: Int, _ closureRaw: Int,
                                           _ outThrown: UnsafeMutablePointer<Int>?) -> Int
{
    runtimeRangeFirstMatchEntry(RuntimeSignedRangeHOFKind.self, rangeRaw, fnPtr, closureRaw, outThrown,
                                functionName: "kk_range_firstOrNull_predicate", orNull: true)
}

@_cdecl("kk_range_firstOrNull")
public func kk_range_firstOrNull(_ rangeRaw: Int) -> Int {
    runtimeRangeEntry(RuntimeSignedRangeHOFKind.self, rangeRaw, functionName: "kk_range_firstOrNull") { range in
        RuntimeSignedRangeHOFKind.firstOrNull(range)
    }
}

@_cdecl("kk_range_randomOrNull")
public func kk_range_randomOrNull(_ rangeRaw: Int) -> Int {
    runtimeRangeRandomOrNullEntry(RuntimeSignedRangeHOFKind.self, rangeRaw, randomRaw: nil,
                                  functionName: "kk_range_randomOrNull")
}

@_cdecl("kk_range_randomOrNull_random")
public func kk_range_randomOrNull_random(_ rangeRaw: Int, _ randomRaw: Int) -> Int {
    runtimeRangeRandomOrNullEntry(RuntimeSignedRangeHOFKind.self, rangeRaw, randomRaw: randomRaw,
                                  functionName: "kk_range_randomOrNull_random")
}

@_cdecl("kk_range_last_predicate")
public func kk_range_last_predicate(_ rangeRaw: Int, _ fnPtr: Int, _ closureRaw: Int,
                                    _ outThrown: UnsafeMutablePointer<Int>?) -> Int
{
    runtimeRangeLastMatchEntry(RuntimeSignedRangeHOFKind.self, rangeRaw, fnPtr, closureRaw, outThrown,
                               functionName: "kk_range_last_predicate", orNull: false)
}

@_cdecl("kk_range_lastOrNull_predicate")
public func kk_range_lastOrNull_predicate(_ rangeRaw: Int, _ fnPtr: Int, _ closureRaw: Int,
                                          _ outThrown: UnsafeMutablePointer<Int>?) -> Int
{
    runtimeRangeLastMatchEntry(RuntimeSignedRangeHOFKind.self, rangeRaw, fnPtr, closureRaw, outThrown,
                               functionName: "kk_range_lastOrNull_predicate", orNull: true)
}

@_cdecl("kk_range_lastOrNull")
public func kk_range_lastOrNull(_ rangeRaw: Int) -> Int {
    runtimeRangeEntry(RuntimeSignedRangeHOFKind.self, rangeRaw, functionName: "kk_range_lastOrNull") { range in
        RuntimeSignedRangeHOFKind.lastOrNull(range)
    }
}

@_cdecl("kk_range_random")
public func kk_range_random(_ rangeRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeRangeRandomEntry(RuntimeSignedRangeHOFKind.self, rangeRaw, 0, outThrown,
                            functionName: "kk_range_random")
}

@_cdecl("kk_range_random_random")
public func kk_range_random_random(_ rangeRaw: Int, _ randomRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeRangeRandomEntry(RuntimeSignedRangeHOFKind.self, rangeRaw, randomRaw, outThrown,
                            functionName: "kk_range_random_random")
}

@_cdecl("kk_random_nextInt_rangeObject")
public func kk_random_nextInt_rangeObject(_ randomRaw: Int, _ rangeRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    return runtimeRangeEntry(RuntimeSignedRangeHOFKind.self, rangeRaw, functionName: "kk_random_nextInt_rangeObject") { range in
        let isEmpty = RuntimeSignedRangeHOFKind.isEmpty(range)
        if isEmpty {
            outThrown?.pointee = runtimeAllocateIllegalArgumentException(
                message: "Random range is empty: \(range.first)..\(range.last)."
            )
            return 0
        }
        return RuntimeSignedRangeHOFKind.random(range, randomRaw: randomRaw, outThrown: outThrown)
    }
}

@_cdecl("kk_range_any")
public func kk_range_any(_ rangeRaw: Int, _ fnPtr: Int, _ closureRaw: Int,
                         _ outThrown: UnsafeMutablePointer<Int>?) -> Int
{
    runtimeRangeHOFEntry(RuntimeSignedRangeHOFKind.self, rangeRaw, fnPtr, closureRaw, outThrown,
                         functionName: "kk_range_any", operation: RuntimeSignedRangeHOFKind.any)
}

@_cdecl("kk_range_all")
public func kk_range_all(_ rangeRaw: Int, _ fnPtr: Int, _ closureRaw: Int,
                         _ outThrown: UnsafeMutablePointer<Int>?) -> Int
{
    runtimeRangeHOFEntry(RuntimeSignedRangeHOFKind.self, rangeRaw, fnPtr, closureRaw, outThrown,
                         functionName: "kk_range_all", operation: RuntimeSignedRangeHOFKind.all)
}

@_cdecl("kk_range_none")
public func kk_range_none(_ rangeRaw: Int, _ fnPtr: Int, _ closureRaw: Int,
                          _ outThrown: UnsafeMutablePointer<Int>?) -> Int
{
    runtimeRangeHOFEntry(RuntimeSignedRangeHOFKind.self, rangeRaw, fnPtr, closureRaw, outThrown,
                         functionName: "kk_range_none", operation: RuntimeSignedRangeHOFKind.none)
}

// MARK: - IntRange Partitioning HOFs (STDLIB-RANGE-038)

@_cdecl("kk_range_chunked")
public func kk_range_chunked(_ rangeRaw: Int, _ size: Int) -> Int {
    runtimeRangeEntry(RuntimeSignedRangeHOFKind.self, rangeRaw, functionName: "kk_range_chunked") { range in
        RuntimeSignedRangeHOFKind.chunked(range, size)
    }
}

@_cdecl("kk_range_windowed")
public func kk_range_windowed(_ rangeRaw: Int, _ size: Int, _ step: Int, _ partialWindows: Int) -> Int {
    runtimeRangeEntry(RuntimeSignedRangeHOFKind.self, rangeRaw, functionName: "kk_range_windowed") { range in
        RuntimeSignedRangeHOFKind.windowed(range, size, step, partialWindows)
    }
}
