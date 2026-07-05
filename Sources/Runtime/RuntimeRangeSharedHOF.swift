// Shared HOF implementations for signed (Int/Long) and unsigned (UInt/ULong) ranges.
// The @_cdecl entry points in the type-specific files are thin wrappers over these.

private typealias RuntimeRangeUnaryLambda = @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int
private typealias RuntimeRangeIndexedLambda = @convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int
private typealias RuntimeRangeFoldLambda = @convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int
private typealias RuntimeRangeIndexedFoldLambda = @convention(c) (Int, Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int

private protocol RuntimeRangeHOFKind {
    static func traverse(_ range: RuntimeRangeBox, _ body: (_ value: Int, _ index: Int) -> Bool) -> Bool
    static func isEmpty(_ range: RuntimeRangeBox) -> Bool
    static func count(_ range: RuntimeRangeBox) -> Int
    static func doubleValue(_ value: Int) -> Double
    static func sortValues(_ values: inout [Int])
}

private enum RuntimeSignedRangeHOFKind: RuntimeRangeHOFKind {
    static func traverse(_ range: RuntimeRangeBox, _ body: (Int, Int) -> Bool) -> Bool {
        runtimeSignedRangeTraverse(range, body)
    }

    static func isEmpty(_ range: RuntimeRangeBox) -> Bool {
        runtimeSignedRangeIsEmpty(range)
    }

    static func count(_ range: RuntimeRangeBox) -> Int {
        runtimeSignedRangeCount(range)
    }

    static func doubleValue(_ value: Int) -> Double {
        Double(value)
    }

    static func sortValues(_ values: inout [Int]) {
        values.sort()
    }
}

private enum RuntimeUnsignedRangeHOFKind: RuntimeRangeHOFKind {
    static func traverse(_ range: RuntimeRangeBox, _ body: (Int, Int) -> Bool) -> Bool {
        runtimeUnsignedRangeTraverse(range) { current, index in
            body(Int(bitPattern: current), index)
        }
    }

    static func isEmpty(_ range: RuntimeRangeBox) -> Bool {
        runtimeUnsignedRangeIsEmpty(range)
    }

    static func count(_ range: RuntimeRangeBox) -> Int {
        runtimeUnsignedRangeCount(range)
    }

    static func doubleValue(_ value: Int) -> Double {
        Double(UInt(bitPattern: value))
    }

    static func sortValues(_ values: inout [Int]) {
        values.sort { UInt(bitPattern: $0) < UInt(bitPattern: $1) }
    }
}

private func runtimeRangeList(_ elements: [Int]) -> Int {
    registerRuntimeObject(RuntimeListBox(elements: elements))
}

private func runtimeRangeValues<Kind: RuntimeRangeHOFKind>(_: Kind.Type, _ range: RuntimeRangeBox) -> [Int] {
    var elements: [Int] = []
    _ = Kind.traverse(range) { value, _ in
        elements.append(value)
        return true
    }
    return elements
}

private func runtimeRangeToList<Kind: RuntimeRangeHOFKind>(_: Kind.Type, _ range: RuntimeRangeBox) -> Int {
    runtimeRangeList(runtimeRangeValues(Kind.self, range))
}

private func runtimeRangeForEach<Kind: RuntimeRangeHOFKind>(
    _: Kind.Type,
    _ range: RuntimeRangeBox,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    let lambda = unsafeBitCast(fnPtr, to: RuntimeRangeUnaryLambda.self)
    _ = Kind.traverse(range) { value, _ in
        var thrown = 0
        _ = lambda(closureRaw, value, &thrown)
        if thrown != 0 {
            outThrown?.pointee = thrown
            return false
        }
        return true
    }
    return 0
}

private func runtimeRangeMap<Kind: RuntimeRangeHOFKind>(
    _: Kind.Type,
    _ range: RuntimeRangeBox,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    let lambda = unsafeBitCast(fnPtr, to: RuntimeRangeUnaryLambda.self)
    var mapped: [Int] = []
    _ = Kind.traverse(range) { value, _ in
        var thrown = 0
        let result = lambda(closureRaw, value, &thrown)
        if thrown != 0 {
            outThrown?.pointee = thrown
            return false
        }
        mapped.append(result)
        return true
    }
    return runtimeRangeList(mapped)
}

private func runtimeRangeMapIndexed<Kind: RuntimeRangeHOFKind>(
    _: Kind.Type,
    _ range: RuntimeRangeBox,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    let lambda = unsafeBitCast(fnPtr, to: RuntimeRangeIndexedLambda.self)
    var mapped: [Int] = []
    _ = Kind.traverse(range) { value, index in
        var thrown = 0
        let result = lambda(closureRaw, index, value, &thrown)
        if thrown != 0 {
            outThrown?.pointee = thrown
            return false
        }
        mapped.append(result)
        return true
    }
    return runtimeRangeList(mapped)
}

private func runtimeRangeMapNotNull<Kind: RuntimeRangeHOFKind>(
    _: Kind.Type,
    _ range: RuntimeRangeBox,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    let lambda = unsafeBitCast(fnPtr, to: RuntimeRangeUnaryLambda.self)
    var mapped: [Int] = []
    _ = Kind.traverse(range) { value, _ in
        var thrown = 0
        let result = lambda(closureRaw, value, &thrown)
        if thrown != 0 {
            outThrown?.pointee = thrown
            return false
        }
        if result != runtimeNullSentinelInt {
            mapped.append(result)
        }
        return true
    }
    return runtimeRangeList(mapped)
}

private func runtimeRangeFilter<Kind: RuntimeRangeHOFKind>(
    _: Kind.Type,
    _ range: RuntimeRangeBox,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?,
    keepOnTrue: Bool
) -> Int {
    let lambda = unsafeBitCast(fnPtr, to: RuntimeRangeUnaryLambda.self)
    var filtered: [Int] = []
    _ = Kind.traverse(range) { value, _ in
        var thrown = 0
        let result = lambda(closureRaw, value, &thrown)
        if thrown != 0 {
            outThrown?.pointee = thrown
            return false
        }
        if (result != 0) == keepOnTrue {
            filtered.append(value)
        }
        return true
    }
    return runtimeRangeList(filtered)
}

private func runtimeRangeFilterIndexed<Kind: RuntimeRangeHOFKind>(
    _: Kind.Type,
    _ range: RuntimeRangeBox,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    let lambda = unsafeBitCast(fnPtr, to: RuntimeRangeIndexedLambda.self)
    var filtered: [Int] = []
    _ = Kind.traverse(range) { value, index in
        var thrown = 0
        let result = lambda(closureRaw, index, value, &thrown)
        if thrown != 0 {
            outThrown?.pointee = thrown
            return false
        }
        if result != 0 {
            filtered.append(value)
        }
        return true
    }
    return runtimeRangeList(filtered)
}

private func runtimeRangeReduce<Kind: RuntimeRangeHOFKind>(
    _: Kind.Type,
    _ range: RuntimeRangeBox,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard !Kind.isEmpty(range) else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "Empty collection can't be reduced.")
        return 0
    }
    let lambda = unsafeBitCast(fnPtr, to: RuntimeRangeFoldLambda.self)
    var accumulator = 0
    var hasAccumulator = false
    _ = Kind.traverse(range) { value, _ in
        if !hasAccumulator {
            accumulator = value
            hasAccumulator = true
            return true
        }
        var thrown = 0
        accumulator = lambda(closureRaw, accumulator, value, &thrown)
        if thrown != 0 {
            outThrown?.pointee = thrown
            return false
        }
        return true
    }
    return accumulator
}

private func runtimeRangeReduceIndexed<Kind: RuntimeRangeHOFKind>(
    _: Kind.Type,
    _ range: RuntimeRangeBox,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard !Kind.isEmpty(range) else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "Empty collection can't be reduced.")
        return 0
    }
    let lambda = unsafeBitCast(fnPtr, to: RuntimeRangeIndexedFoldLambda.self)
    var accumulator = 0
    var hasAccumulator = false
    _ = Kind.traverse(range) { value, index in
        if !hasAccumulator {
            accumulator = value
            hasAccumulator = true
            return true
        }
        var thrown = 0
        accumulator = lambda(closureRaw, index, accumulator, value, &thrown)
        if thrown != 0 {
            outThrown?.pointee = thrown
            return false
        }
        return true
    }
    return accumulator
}

private func runtimeRangeFold<Kind: RuntimeRangeHOFKind>(
    _: Kind.Type,
    _ range: RuntimeRangeBox,
    _ initialValue: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    let lambda = unsafeBitCast(fnPtr, to: RuntimeRangeFoldLambda.self)
    var accumulator = initialValue
    _ = Kind.traverse(range) { value, _ in
        var thrown = 0
        accumulator = lambda(closureRaw, accumulator, value, &thrown)
        if thrown != 0 {
            outThrown?.pointee = thrown
            return false
        }
        return true
    }
    return accumulator
}

private func runtimeRangeFoldIndexed<Kind: RuntimeRangeHOFKind>(
    _: Kind.Type,
    _ range: RuntimeRangeBox,
    _ initialValue: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    let lambda = unsafeBitCast(fnPtr, to: RuntimeRangeIndexedFoldLambda.self)
    var accumulator = initialValue
    _ = Kind.traverse(range) { value, index in
        var thrown = 0
        accumulator = lambda(closureRaw, index, accumulator, value, &thrown)
        if thrown != 0 {
            outThrown?.pointee = thrown
            return false
        }
        return true
    }
    return accumulator
}

private func runtimeRangePredicate<Kind: RuntimeRangeHOFKind>(
    _: Kind.Type,
    _ range: RuntimeRangeBox,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?,
    initialResult: Int,
    stopWhen predicate: @escaping (_ lambdaValue: Int) -> Bool,
    finalResultForStop: Int
) -> Int {
    let lambda = unsafeBitCast(fnPtr, to: RuntimeRangeUnaryLambda.self)
    var result = initialResult
    var didThrow = false
    _ = Kind.traverse(range) { value, _ in
        var thrown = 0
        let lambdaValue = lambda(closureRaw, value, &thrown)
        if thrown != 0 {
            outThrown?.pointee = thrown
            didThrow = true
            return false
        }
        if predicate(lambdaValue) {
            result = finalResultForStop
            return false
        }
        return true
    }
    return didThrow ? 0 : result
}

private func runtimeRangeChunked<Kind: RuntimeRangeHOFKind>(_: Kind.Type, _ range: RuntimeRangeBox, _ size: Int) -> Int {
    guard size > 0 else { return runtimeRangeList([]) }
    var chunks: [Int] = []
    var currentChunk: [Int] = []
    _ = Kind.traverse(range) { value, _ in
        currentChunk.append(value)
        if currentChunk.count == size {
            chunks.append(runtimeRangeList(currentChunk))
            currentChunk.removeAll(keepingCapacity: true)
        }
        return true
    }
    if !currentChunk.isEmpty {
        chunks.append(runtimeRangeList(currentChunk))
    }
    return runtimeRangeList(chunks)
}

private func runtimeRangeWindowed<Kind: RuntimeRangeHOFKind>(
    _: Kind.Type,
    _ range: RuntimeRangeBox,
    _ size: Int,
    _ step: Int,
    _ partialWindows: Int
) -> Int {
    guard size > 0, step > 0 else { return runtimeRangeList([]) }
    let values = runtimeRangeValues(Kind.self, range)
    var windows: [Int] = []
    var start = 0
    while start < values.count {
        let end = Swift.min(start + size, values.count)
        let window = Array(values[start..<end])
        if window.count == size || (partialWindows != 0 && !window.isEmpty) {
            windows.append(runtimeRangeList(window))
        }
        start += step
    }
    return runtimeRangeList(windows)
}

private func runtimeRangeTake<Kind: RuntimeRangeHOFKind>(_: Kind.Type, _ range: RuntimeRangeBox, _ n: Int) -> Int {
    guard n > 0 else { return runtimeRangeList([]) }
    var elements: [Int] = []
    var taken = 0
    _ = Kind.traverse(range) { value, _ in
        guard taken < n else { return false }
        elements.append(value)
        taken += 1
        return true
    }
    return runtimeRangeList(elements)
}

private func runtimeRangeDrop<Kind: RuntimeRangeHOFKind>(_: Kind.Type, _ range: RuntimeRangeBox, _ n: Int) -> Int {
    var elements: [Int] = []
    var skipped = 0
    _ = Kind.traverse(range) { value, _ in
        if skipped < n {
            skipped += 1
        } else {
            elements.append(value)
        }
        return true
    }
    return runtimeRangeList(elements)
}

private func runtimeRangeAverage<Kind: RuntimeRangeHOFKind>(_: Kind.Type, _ range: RuntimeRangeBox) -> Int {
    var sum: Double = 0.0
    var count: Double = 0.0
    _ = Kind.traverse(range) { value, _ in
        sum += Kind.doubleValue(value)
        count += 1.0
        return true
    }
    let result = count > 0 ? sum / count : Double.nan
    return Int(bitPattern: UInt(truncatingIfNeeded: result.bitPattern))
}

private func runtimeRangeSorted<Kind: RuntimeRangeHOFKind>(_: Kind.Type, _ range: RuntimeRangeBox) -> Int {
    var elements = runtimeRangeValues(Kind.self, range)
    Kind.sortValues(&elements)
    return runtimeRangeList(elements)
}

// MARK: - Signed HOF entry helpers

func runtimeSignedRangeToList(_ range: RuntimeRangeBox) -> Int {
    runtimeRangeToList(RuntimeSignedRangeHOFKind.self, range)
}

func runtimeSignedRangeForEach(
    _ range: RuntimeRangeBox, _ fnPtr: Int, _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    runtimeRangeForEach(RuntimeSignedRangeHOFKind.self, range, fnPtr, closureRaw, outThrown)
}

func runtimeSignedRangeMap(
    _ range: RuntimeRangeBox, _ fnPtr: Int, _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    runtimeRangeMap(RuntimeSignedRangeHOFKind.self, range, fnPtr, closureRaw, outThrown)
}

func runtimeSignedRangeMapIndexed(
    _ range: RuntimeRangeBox, _ fnPtr: Int, _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    runtimeRangeMapIndexed(RuntimeSignedRangeHOFKind.self, range, fnPtr, closureRaw, outThrown)
}

func runtimeSignedRangeMapNotNull(
    _ range: RuntimeRangeBox, _ fnPtr: Int, _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    runtimeRangeMapNotNull(RuntimeSignedRangeHOFKind.self, range, fnPtr, closureRaw, outThrown)
}

func runtimeSignedRangeFilter(
    _ range: RuntimeRangeBox, _ fnPtr: Int, _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    runtimeRangeFilter(RuntimeSignedRangeHOFKind.self, range, fnPtr, closureRaw, outThrown, keepOnTrue: true)
}

func runtimeSignedRangeFilterIndexed(
    _ range: RuntimeRangeBox, _ fnPtr: Int, _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    runtimeRangeFilterIndexed(RuntimeSignedRangeHOFKind.self, range, fnPtr, closureRaw, outThrown)
}

func runtimeSignedRangeFilterNot(
    _ range: RuntimeRangeBox, _ fnPtr: Int, _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    runtimeRangeFilter(RuntimeSignedRangeHOFKind.self, range, fnPtr, closureRaw, outThrown, keepOnTrue: false)
}

func runtimeSignedRangeReduce(
    _ range: RuntimeRangeBox, _ fnPtr: Int, _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    runtimeRangeReduce(RuntimeSignedRangeHOFKind.self, range, fnPtr, closureRaw, outThrown)
}

func runtimeSignedRangeReduceIndexed(
    _ range: RuntimeRangeBox, _ fnPtr: Int, _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    runtimeRangeReduceIndexed(RuntimeSignedRangeHOFKind.self, range, fnPtr, closureRaw, outThrown)
}

func runtimeSignedRangeFold(
    _ range: RuntimeRangeBox, _ initialValue: Int, _ fnPtr: Int, _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    runtimeRangeFold(RuntimeSignedRangeHOFKind.self, range, initialValue, fnPtr, closureRaw, outThrown)
}

func runtimeSignedRangeFoldIndexed(
    _ range: RuntimeRangeBox, _ initialValue: Int, _ fnPtr: Int, _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    runtimeRangeFoldIndexed(RuntimeSignedRangeHOFKind.self, range, initialValue, fnPtr, closureRaw, outThrown)
}

func runtimeSignedRangeAny(
    _ range: RuntimeRangeBox, _ fnPtr: Int, _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    runtimeRangePredicate(RuntimeSignedRangeHOFKind.self, range, fnPtr, closureRaw, outThrown,
                          initialResult: 0, stopWhen: { $0 != 0 }, finalResultForStop: 1)
}

func runtimeSignedRangeAll(
    _ range: RuntimeRangeBox, _ fnPtr: Int, _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    runtimeRangePredicate(RuntimeSignedRangeHOFKind.self, range, fnPtr, closureRaw, outThrown,
                          initialResult: 1, stopWhen: { $0 == 0 }, finalResultForStop: 0)
}

func runtimeSignedRangeNone(
    _ range: RuntimeRangeBox, _ fnPtr: Int, _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    runtimeRangePredicate(RuntimeSignedRangeHOFKind.self, range, fnPtr, closureRaw, outThrown,
                          initialResult: 1, stopWhen: { $0 != 0 }, finalResultForStop: 0)
}

func runtimeSignedRangeChunked(_ range: RuntimeRangeBox, _ size: Int) -> Int {
    runtimeRangeChunked(RuntimeSignedRangeHOFKind.self, range, size)
}

func runtimeSignedRangeWindowed(_ range: RuntimeRangeBox, _ size: Int, _ step: Int, _ partialWindows: Int) -> Int {
    runtimeRangeWindowed(RuntimeSignedRangeHOFKind.self, range, size, step, partialWindows)
}

func runtimeSignedRangeTake(_ range: RuntimeRangeBox, _ n: Int) -> Int {
    runtimeRangeTake(RuntimeSignedRangeHOFKind.self, range, n)
}

func runtimeSignedRangeDrop(_ range: RuntimeRangeBox, _ n: Int) -> Int {
    runtimeRangeDrop(RuntimeSignedRangeHOFKind.self, range, n)
}

func runtimeSignedRangeAverage(_ range: RuntimeRangeBox) -> Int {
    runtimeRangeAverage(RuntimeSignedRangeHOFKind.self, range)
}

func runtimeSignedRangeSorted(_ range: RuntimeRangeBox) -> Int {
    runtimeRangeSorted(RuntimeSignedRangeHOFKind.self, range)
}

// MARK: - Unsigned HOF entry helpers

func runtimeUnsignedRangeToList(_ range: RuntimeRangeBox) -> Int {
    runtimeRangeToList(RuntimeUnsignedRangeHOFKind.self, range)
}

func runtimeUnsignedRangeForEach(
    _ range: RuntimeRangeBox, _ fnPtr: Int, _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    runtimeRangeForEach(RuntimeUnsignedRangeHOFKind.self, range, fnPtr, closureRaw, outThrown)
}

func runtimeUnsignedRangeMap(
    _ range: RuntimeRangeBox, _ fnPtr: Int, _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    runtimeRangeMap(RuntimeUnsignedRangeHOFKind.self, range, fnPtr, closureRaw, outThrown)
}

func runtimeUnsignedRangeMapIndexed(
    _ range: RuntimeRangeBox, _ fnPtr: Int, _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    runtimeRangeMapIndexed(RuntimeUnsignedRangeHOFKind.self, range, fnPtr, closureRaw, outThrown)
}

func runtimeUnsignedRangeMapNotNull(
    _ range: RuntimeRangeBox, _ fnPtr: Int, _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    runtimeRangeMapNotNull(RuntimeUnsignedRangeHOFKind.self, range, fnPtr, closureRaw, outThrown)
}

func runtimeUnsignedRangeFilter(
    _ range: RuntimeRangeBox, _ fnPtr: Int, _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    runtimeRangeFilter(RuntimeUnsignedRangeHOFKind.self, range, fnPtr, closureRaw, outThrown, keepOnTrue: true)
}

func runtimeUnsignedRangeFilterIndexed(
    _ range: RuntimeRangeBox, _ fnPtr: Int, _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    runtimeRangeFilterIndexed(RuntimeUnsignedRangeHOFKind.self, range, fnPtr, closureRaw, outThrown)
}

func runtimeUnsignedRangeFilterNot(
    _ range: RuntimeRangeBox, _ fnPtr: Int, _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    runtimeRangeFilter(RuntimeUnsignedRangeHOFKind.self, range, fnPtr, closureRaw, outThrown, keepOnTrue: false)
}

func runtimeUnsignedRangeReduce(
    _ range: RuntimeRangeBox, _ fnPtr: Int, _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    runtimeRangeReduce(RuntimeUnsignedRangeHOFKind.self, range, fnPtr, closureRaw, outThrown)
}

func runtimeUnsignedRangeReduceIndexed(
    _ range: RuntimeRangeBox, _ fnPtr: Int, _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    runtimeRangeReduceIndexed(RuntimeUnsignedRangeHOFKind.self, range, fnPtr, closureRaw, outThrown)
}

func runtimeUnsignedRangeFold(
    _ range: RuntimeRangeBox, _ initialValue: Int, _ fnPtr: Int, _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    runtimeRangeFold(RuntimeUnsignedRangeHOFKind.self, range, initialValue, fnPtr, closureRaw, outThrown)
}

func runtimeUnsignedRangeFoldIndexed(
    _ range: RuntimeRangeBox, _ initialValue: Int, _ fnPtr: Int, _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    runtimeRangeFoldIndexed(RuntimeUnsignedRangeHOFKind.self, range, initialValue, fnPtr, closureRaw, outThrown)
}

func runtimeUnsignedRangeAny(
    _ range: RuntimeRangeBox, _ fnPtr: Int, _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    runtimeRangePredicate(RuntimeUnsignedRangeHOFKind.self, range, fnPtr, closureRaw, outThrown,
                          initialResult: 0, stopWhen: { $0 != 0 }, finalResultForStop: 1)
}

func runtimeUnsignedRangeAll(
    _ range: RuntimeRangeBox, _ fnPtr: Int, _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    runtimeRangePredicate(RuntimeUnsignedRangeHOFKind.self, range, fnPtr, closureRaw, outThrown,
                          initialResult: 1, stopWhen: { $0 == 0 }, finalResultForStop: 0)
}

func runtimeUnsignedRangeNone(
    _ range: RuntimeRangeBox, _ fnPtr: Int, _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    runtimeRangePredicate(RuntimeUnsignedRangeHOFKind.self, range, fnPtr, closureRaw, outThrown,
                          initialResult: 1, stopWhen: { $0 != 0 }, finalResultForStop: 0)
}

func runtimeUnsignedRangeChunked(_ range: RuntimeRangeBox, _ size: Int) -> Int {
    runtimeRangeChunked(RuntimeUnsignedRangeHOFKind.self, range, size)
}

func runtimeUnsignedRangeWindowed(_ range: RuntimeRangeBox, _ size: Int, _ step: Int, _ partialWindows: Int) -> Int {
    runtimeRangeWindowed(RuntimeUnsignedRangeHOFKind.self, range, size, step, partialWindows)
}

func runtimeUnsignedRangeTake(_ range: RuntimeRangeBox, _ n: Int) -> Int {
    runtimeRangeTake(RuntimeUnsignedRangeHOFKind.self, range, n)
}

func runtimeUnsignedRangeDrop(_ range: RuntimeRangeBox, _ n: Int) -> Int {
    runtimeRangeDrop(RuntimeUnsignedRangeHOFKind.self, range, n)
}

func runtimeUnsignedRangeAverage(_ range: RuntimeRangeBox) -> Int {
    runtimeRangeAverage(RuntimeUnsignedRangeHOFKind.self, range)
}

func runtimeUnsignedRangeSorted(_ range: RuntimeRangeBox) -> Int {
    runtimeRangeSorted(RuntimeUnsignedRangeHOFKind.self, range)
}
