// Shared HOF implementations for signed (Int/Long) and unsigned (UInt/ULong) ranges.
// The @_cdecl entry points in the type-specific files are thin wrappers over these.

private typealias RuntimeRangeUnaryLambda = @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int
private typealias RuntimeRangeIndexedLambda = @convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int
private typealias RuntimeRangeFoldLambda = @convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int
private typealias RuntimeRangeIndexedFoldLambda = @convention(c) (Int, Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int

protocol RuntimeRangeHOFKind {
    static func traverse(_ range: RuntimeRangeBox, _ body: (_ value: Int, _ index: Int) -> Bool) -> Bool
    static func isEmpty(_ range: RuntimeRangeBox) -> Bool
    static func count(_ range: RuntimeRangeBox) -> Int
    static func doubleValue(_ value: Int) -> Double
    static func sortValues(_ values: inout [Int])
    static func firstMatch(
        _ range: RuntimeRangeBox,
        _ fnPtr: Int,
        _ closureRaw: Int,
        _ outThrown: UnsafeMutablePointer<Int>?,
        orNull: Bool
    ) -> Int
    static func lastMatch(
        _ range: RuntimeRangeBox,
        _ fnPtr: Int,
        _ closureRaw: Int,
        _ outThrown: UnsafeMutablePointer<Int>?,
        orNull: Bool
    ) -> Int
    static func randomOrNull(_ range: RuntimeRangeBox, randomRaw: Int?) -> Int
    static func random(_ range: RuntimeRangeBox, randomRaw: Int, outThrown: UnsafeMutablePointer<Int>?) -> Int
}

enum RuntimeSignedRangeHOFKind: RuntimeRangeHOFKind {
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

    static func firstMatch(
        _ range: RuntimeRangeBox,
        _ fnPtr: Int,
        _ closureRaw: Int,
        _ outThrown: UnsafeMutablePointer<Int>?,
        orNull: Bool
    ) -> Int {
        runtimeSignedRangeFirstMatch(range, fnPtr, closureRaw, outThrown, orNull: orNull)
    }

    static func lastMatch(
        _ range: RuntimeRangeBox,
        _ fnPtr: Int,
        _ closureRaw: Int,
        _ outThrown: UnsafeMutablePointer<Int>?,
        orNull: Bool
    ) -> Int {
        runtimeSignedRangeLastMatch(range, fnPtr, closureRaw, outThrown, orNull: orNull)
    }

    static func randomOrNull(_ range: RuntimeRangeBox, randomRaw: Int?) -> Int {
        runtimeSignedRangeRandomOrNull(range, randomRaw: randomRaw)
    }

    static func random(_ range: RuntimeRangeBox, randomRaw: Int, outThrown: UnsafeMutablePointer<Int>?) -> Int {
        runtimeSignedRangeRandom(first: range.first, last: range.last, step: range.step,
                                 randomRaw: randomRaw, outThrown: outThrown)
    }
}

enum RuntimeUnsignedRangeHOFKind: RuntimeRangeHOFKind {
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

    static func firstMatch(
        _ range: RuntimeRangeBox,
        _ fnPtr: Int,
        _ closureRaw: Int,
        _ outThrown: UnsafeMutablePointer<Int>?,
        orNull: Bool
    ) -> Int {
        runtimeUnsignedRangeFirstMatch(range, fnPtr, closureRaw, outThrown, orNull: orNull)
    }

    static func lastMatch(
        _ range: RuntimeRangeBox,
        _ fnPtr: Int,
        _ closureRaw: Int,
        _ outThrown: UnsafeMutablePointer<Int>?,
        orNull: Bool
    ) -> Int {
        runtimeUnsignedRangeLastMatch(range, fnPtr, closureRaw, outThrown, orNull: orNull)
    }

    static func randomOrNull(_ range: RuntimeRangeBox, randomRaw: Int?) -> Int {
        runtimeUnsignedRangeRandomOrNull(range, randomRaw: randomRaw)
    }

    static func random(_ range: RuntimeRangeBox, randomRaw: Int, outThrown: UnsafeMutablePointer<Int>?) -> Int {
        runtimeUnsignedRangeRandom(first: UInt(bitPattern: range.first),
                                   last: UInt(bitPattern: range.last),
                                   step: range.step,
                                   randomRaw: randomRaw,
                                   outThrown: outThrown)
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
        outThrown?.pointee = runtimeAllocateUnsupportedOperationException(message: "Empty collection can't be reduced.")
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
        outThrown?.pointee = runtimeAllocateUnsupportedOperationException(message: "Empty collection can't be reduced.")
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

extension RuntimeRangeHOFKind {
    static func toList(_ range: RuntimeRangeBox) -> Int {
        runtimeRangeToList(Self.self, range)
    }

    static func forEach(
        _ range: RuntimeRangeBox,
        _ fnPtr: Int,
        _ closureRaw: Int,
        _ outThrown: UnsafeMutablePointer<Int>?
    ) -> Int {
        runtimeRangeForEach(Self.self, range, fnPtr, closureRaw, outThrown)
    }

    static func map(
        _ range: RuntimeRangeBox,
        _ fnPtr: Int,
        _ closureRaw: Int,
        _ outThrown: UnsafeMutablePointer<Int>?
    ) -> Int {
        runtimeRangeMap(Self.self, range, fnPtr, closureRaw, outThrown)
    }

    static func mapIndexed(
        _ range: RuntimeRangeBox,
        _ fnPtr: Int,
        _ closureRaw: Int,
        _ outThrown: UnsafeMutablePointer<Int>?
    ) -> Int {
        runtimeRangeMapIndexed(Self.self, range, fnPtr, closureRaw, outThrown)
    }

    static func mapNotNull(
        _ range: RuntimeRangeBox,
        _ fnPtr: Int,
        _ closureRaw: Int,
        _ outThrown: UnsafeMutablePointer<Int>?
    ) -> Int {
        runtimeRangeMapNotNull(Self.self, range, fnPtr, closureRaw, outThrown)
    }

    static func filter(
        _ range: RuntimeRangeBox,
        _ fnPtr: Int,
        _ closureRaw: Int,
        _ outThrown: UnsafeMutablePointer<Int>?
    ) -> Int {
        runtimeRangeFilter(Self.self, range, fnPtr, closureRaw, outThrown, keepOnTrue: true)
    }

    static func filterIndexed(
        _ range: RuntimeRangeBox,
        _ fnPtr: Int,
        _ closureRaw: Int,
        _ outThrown: UnsafeMutablePointer<Int>?
    ) -> Int {
        runtimeRangeFilterIndexed(Self.self, range, fnPtr, closureRaw, outThrown)
    }

    static func filterNot(
        _ range: RuntimeRangeBox,
        _ fnPtr: Int,
        _ closureRaw: Int,
        _ outThrown: UnsafeMutablePointer<Int>?
    ) -> Int {
        runtimeRangeFilter(Self.self, range, fnPtr, closureRaw, outThrown, keepOnTrue: false)
    }

    static func reduce(
        _ range: RuntimeRangeBox,
        _ fnPtr: Int,
        _ closureRaw: Int,
        _ outThrown: UnsafeMutablePointer<Int>?
    ) -> Int {
        runtimeRangeReduce(Self.self, range, fnPtr, closureRaw, outThrown)
    }

    static func reduceIndexed(
        _ range: RuntimeRangeBox,
        _ fnPtr: Int,
        _ closureRaw: Int,
        _ outThrown: UnsafeMutablePointer<Int>?
    ) -> Int {
        runtimeRangeReduceIndexed(Self.self, range, fnPtr, closureRaw, outThrown)
    }

    static func fold(
        _ range: RuntimeRangeBox,
        _ initialValue: Int,
        _ fnPtr: Int,
        _ closureRaw: Int,
        _ outThrown: UnsafeMutablePointer<Int>?
    ) -> Int {
        runtimeRangeFold(Self.self, range, initialValue, fnPtr, closureRaw, outThrown)
    }

    static func foldIndexed(
        _ range: RuntimeRangeBox,
        _ initialValue: Int,
        _ fnPtr: Int,
        _ closureRaw: Int,
        _ outThrown: UnsafeMutablePointer<Int>?
    ) -> Int {
        runtimeRangeFoldIndexed(Self.self, range, initialValue, fnPtr, closureRaw, outThrown)
    }

    static func firstOrNull(_ range: RuntimeRangeBox) -> Int {
        isEmpty(range) ? runtimeNullSentinelInt : range.first
    }

    static func lastOrNull(_ range: RuntimeRangeBox) -> Int {
        isEmpty(range) ? runtimeNullSentinelInt : range.last
    }

    static func any(
        _ range: RuntimeRangeBox,
        _ fnPtr: Int,
        _ closureRaw: Int,
        _ outThrown: UnsafeMutablePointer<Int>?
    ) -> Int {
        runtimeRangePredicate(Self.self, range, fnPtr, closureRaw, outThrown,
                              initialResult: 0, stopWhen: { $0 != 0 }, finalResultForStop: 1)
    }

    static func all(
        _ range: RuntimeRangeBox,
        _ fnPtr: Int,
        _ closureRaw: Int,
        _ outThrown: UnsafeMutablePointer<Int>?
    ) -> Int {
        runtimeRangePredicate(Self.self, range, fnPtr, closureRaw, outThrown,
                              initialResult: 1, stopWhen: { $0 == 0 }, finalResultForStop: 0)
    }

    static func none(
        _ range: RuntimeRangeBox,
        _ fnPtr: Int,
        _ closureRaw: Int,
        _ outThrown: UnsafeMutablePointer<Int>?
    ) -> Int {
        runtimeRangePredicate(Self.self, range, fnPtr, closureRaw, outThrown,
                              initialResult: 1, stopWhen: { $0 != 0 }, finalResultForStop: 0)
    }

    static func chunked(_ range: RuntimeRangeBox, _ size: Int) -> Int {
        runtimeRangeChunked(Self.self, range, size)
    }

    static func windowed(_ range: RuntimeRangeBox, _ size: Int, _ step: Int, _ partialWindows: Int) -> Int {
        runtimeRangeWindowed(Self.self, range, size, step, partialWindows)
    }

    static func take(_ range: RuntimeRangeBox, _ n: Int) -> Int {
        runtimeRangeTake(Self.self, range, n)
    }

    static func drop(_ range: RuntimeRangeBox, _ n: Int) -> Int {
        runtimeRangeDrop(Self.self, range, n)
    }

    static func average(_ range: RuntimeRangeBox) -> Int {
        runtimeRangeAverage(Self.self, range)
    }

    static func sorted(_ range: RuntimeRangeBox) -> Int {
        runtimeRangeSorted(Self.self, range)
    }
}

@inline(__always)
func runtimeRangeEntry<Kind: RuntimeRangeHOFKind>(
    _: Kind.Type,
    _ rangeRaw: Int,
    functionName: String,
    _ body: (RuntimeRangeBox) -> Int
) -> Int {
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in \(functionName)")
    }
    return body(range)
}

@inline(__always)
func runtimeRangeHOFEntry<Kind: RuntimeRangeHOFKind>(
    _ kind: Kind.Type,
    _ rangeRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?,
    functionName: String,
    operation: (RuntimeRangeBox, Int, Int, UnsafeMutablePointer<Int>?) -> Int
) -> Int {
    runtimeRangeEntry(kind, rangeRaw, functionName: functionName) { range in
        operation(range, fnPtr, closureRaw, outThrown)
    }
}

@inline(__always)
func runtimeRangeFoldHOFEntry<Kind: RuntimeRangeHOFKind>(
    _ kind: Kind.Type,
    _ rangeRaw: Int,
    _ initialValue: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?,
    functionName: String,
    operation: (RuntimeRangeBox, Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int
) -> Int {
    runtimeRangeEntry(kind, rangeRaw, functionName: functionName) { range in
        operation(range, initialValue, fnPtr, closureRaw, outThrown)
    }
}

@inline(__always)
func runtimeRangeFirstMatchEntry<Kind: RuntimeRangeHOFKind>(
    _ kind: Kind.Type,
    _ rangeRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?,
    functionName: String,
    orNull: Bool
) -> Int {
    runtimeRangeEntry(kind, rangeRaw, functionName: functionName) { range in
        Kind.firstMatch(range, fnPtr, closureRaw, outThrown, orNull: orNull)
    }
}

@inline(__always)
func runtimeRangeLastMatchEntry<Kind: RuntimeRangeHOFKind>(
    _ kind: Kind.Type,
    _ rangeRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?,
    functionName: String,
    orNull: Bool
) -> Int {
    runtimeRangeEntry(kind, rangeRaw, functionName: functionName) { range in
        Kind.lastMatch(range, fnPtr, closureRaw, outThrown, orNull: orNull)
    }
}

@inline(__always)
func runtimeRangeRandomOrNullEntry<Kind: RuntimeRangeHOFKind>(
    _ kind: Kind.Type,
    _ rangeRaw: Int,
    randomRaw: Int?,
    functionName: String
) -> Int {
    runtimeRangeEntry(kind, rangeRaw, functionName: functionName) { range in
        Kind.randomOrNull(range, randomRaw: randomRaw)
    }
}

@inline(__always)
func runtimeRangeRandomEntry<Kind: RuntimeRangeHOFKind>(
    _ kind: Kind.Type,
    _ rangeRaw: Int,
    _ randomRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?,
    functionName: String
) -> Int {
    outThrown?.pointee = 0
    return runtimeRangeEntry(kind, rangeRaw, functionName: functionName) { range in
        Kind.random(range, randomRaw: randomRaw, outThrown: outThrown)
    }
}
