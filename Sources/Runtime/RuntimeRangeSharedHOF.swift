
// Shared HOF implementations for signed (Int/Long) and unsigned (UInt/ULong) ranges.
// The @_cdecl entry points in the type-specific files are thin wrappers over these.

// MARK: - Signed HOF implementations

func runtimeSignedRangeToList(_ range: RuntimeRangeBox) -> Int {
    var elements: [Int] = []
    _ = runtimeSignedRangeTraverse(range) { current, _ in elements.append(current); return true }
    return registerRuntimeObject(RuntimeListBox(elements: elements))
}

func runtimeSignedRangeForEach(
    _ range: RuntimeRangeBox, _ fnPtr: Int, _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    _ = runtimeSignedRangeTraverse(range) { current, _ in
        var thrown = 0
        _ = lambda(closureRaw, current, &thrown)
        if thrown != 0 { outThrown?.pointee = thrown; return false }
        return true
    }
    return 0
}

func runtimeSignedRangeMap(
    _ range: RuntimeRangeBox, _ fnPtr: Int, _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var mapped: [Int] = []
    mapped.reserveCapacity(runtimeSignedRangeCount(range))
    _ = runtimeSignedRangeTraverse(range) { current, _ in
        var thrown = 0
        let result = lambda(closureRaw, current, &thrown)
        if thrown != 0 { outThrown?.pointee = thrown; return false }
        mapped.append(result)
        return true
    }
    return registerRuntimeObject(RuntimeListBox(elements: mapped))
}

func runtimeSignedRangeMapIndexed(
    _ range: RuntimeRangeBox, _ fnPtr: Int, _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var mapped: [Int] = []
    mapped.reserveCapacity(runtimeSignedRangeCount(range))
    _ = runtimeSignedRangeTraverse(range) { current, index in
        var thrown = 0
        let result = lambda(closureRaw, index, current, &thrown)
        if thrown != 0 { outThrown?.pointee = thrown; return false }
        mapped.append(result)
        return true
    }
    return registerRuntimeObject(RuntimeListBox(elements: mapped))
}

func runtimeSignedRangeMapNotNull(
    _ range: RuntimeRangeBox, _ fnPtr: Int, _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var mapped: [Int] = []
    _ = runtimeSignedRangeTraverse(range) { current, _ in
        var thrown = 0
        let result = lambda(closureRaw, current, &thrown)
        if thrown != 0 { outThrown?.pointee = thrown; return false }
        if result != runtimeNullSentinelInt { mapped.append(result) }
        return true
    }
    return registerRuntimeObject(RuntimeListBox(elements: mapped))
}

func runtimeSignedRangeFilter(
    _ range: RuntimeRangeBox, _ fnPtr: Int, _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var filtered: [Int] = []
    filtered.reserveCapacity(runtimeSignedRangeCount(range))
    _ = runtimeSignedRangeTraverse(range) { current, _ in
        var thrown = 0
        let result = lambda(closureRaw, current, &thrown)
        if thrown != 0 { outThrown?.pointee = thrown; return false }
        if result != 0 { filtered.append(current) }
        return true
    }
    return registerRuntimeObject(RuntimeListBox(elements: filtered))
}

func runtimeSignedRangeFilterIndexed(
    _ range: RuntimeRangeBox, _ fnPtr: Int, _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var filtered: [Int] = []
    _ = runtimeSignedRangeTraverse(range) { current, index in
        var thrown = 0
        let result = lambda(closureRaw, index, current, &thrown)
        if thrown != 0 { outThrown?.pointee = thrown; return false }
        if result != 0 { filtered.append(current) }
        return true
    }
    return registerRuntimeObject(RuntimeListBox(elements: filtered))
}

func runtimeSignedRangeFilterNot(
    _ range: RuntimeRangeBox, _ fnPtr: Int, _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var filtered: [Int] = []
    _ = runtimeSignedRangeTraverse(range) { current, _ in
        var thrown = 0
        let result = lambda(closureRaw, current, &thrown)
        if thrown != 0 { outThrown?.pointee = thrown; return false }
        if result == 0 { filtered.append(current) }
        return true
    }
    return registerRuntimeObject(RuntimeListBox(elements: filtered))
}

func runtimeSignedRangeReduce(
    _ range: RuntimeRangeBox, _ fnPtr: Int, _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard !runtimeSignedRangeIsEmpty(range) else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "Empty collection can't be reduced.")
        return 0
    }
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var accumulator = 0
    var hasAccumulator = false
    _ = runtimeSignedRangeTraverse(range) { current, _ in
        if !hasAccumulator { accumulator = current; hasAccumulator = true; return true }
        var thrown = 0
        accumulator = lambda(closureRaw, accumulator, current, &thrown)
        if thrown != 0 { outThrown?.pointee = thrown; return false }
        return true
    }
    return accumulator
}

func runtimeSignedRangeReduceIndexed(
    _ range: RuntimeRangeBox, _ fnPtr: Int, _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard !runtimeSignedRangeIsEmpty(range) else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "Empty collection can't be reduced.")
        return 0
    }
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var accumulator = 0
    var hasAccumulator = false
    _ = runtimeSignedRangeTraverse(range) { current, index in
        if !hasAccumulator { accumulator = current; hasAccumulator = true; return true }
        var thrown = 0
        accumulator = lambda(closureRaw, index, accumulator, current, &thrown)
        if thrown != 0 { outThrown?.pointee = thrown; return false }
        return true
    }
    return accumulator
}

func runtimeSignedRangeFold(
    _ range: RuntimeRangeBox, _ initialValue: Int, _ fnPtr: Int, _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var accumulator = initialValue
    _ = runtimeSignedRangeTraverse(range) { current, _ in
        var thrown = 0
        accumulator = lambda(closureRaw, accumulator, current, &thrown)
        if thrown != 0 { outThrown?.pointee = thrown; return false }
        return true
    }
    return accumulator
}

func runtimeSignedRangeFoldIndexed(
    _ range: RuntimeRangeBox, _ initialValue: Int, _ fnPtr: Int, _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var accumulator = initialValue
    _ = runtimeSignedRangeTraverse(range) { current, index in
        var thrown = 0
        accumulator = lambda(closureRaw, index, accumulator, current, &thrown)
        if thrown != 0 { outThrown?.pointee = thrown; return false }
        return true
    }
    return accumulator
}

func runtimeSignedRangeAny(
    _ range: RuntimeRangeBox, _ fnPtr: Int, _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var result = 0
    var didThrow = false
    _ = runtimeSignedRangeTraverse(range) { current, _ in
        var thrown = 0
        let value = lambda(closureRaw, current, &thrown)
        if thrown != 0 { outThrown?.pointee = thrown; didThrow = true; return false }
        if value != 0 { result = 1; return false }
        return true
    }
    return didThrow ? 0 : result
}

func runtimeSignedRangeAll(
    _ range: RuntimeRangeBox, _ fnPtr: Int, _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var result = 1
    var didThrow = false
    _ = runtimeSignedRangeTraverse(range) { current, _ in
        var thrown = 0
        let value = lambda(closureRaw, current, &thrown)
        if thrown != 0 { outThrown?.pointee = thrown; didThrow = true; return false }
        if value == 0 { result = 0; return false }
        return true
    }
    return didThrow ? 0 : result
}

func runtimeSignedRangeNone(
    _ range: RuntimeRangeBox, _ fnPtr: Int, _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var result = 1
    var didThrow = false
    _ = runtimeSignedRangeTraverse(range) { current, _ in
        var thrown = 0
        let value = lambda(closureRaw, current, &thrown)
        if thrown != 0 { outThrown?.pointee = thrown; didThrow = true; return false }
        if value != 0 { result = 0; return false }
        return true
    }
    return didThrow ? 0 : result
}

func runtimeSignedRangeChunked(_ range: RuntimeRangeBox, _ size: Int) -> Int {
    guard size > 0 else { return registerRuntimeObject(RuntimeListBox(elements: [])) }
    var chunks: [Int] = []
    var current = range.first
    if range.step > 0 {
        while current <= range.last {
            var chunkElements: [Int] = []
            var chunkSize = 0
            while chunkSize < size && current <= range.last {
                chunkElements.append(current)
                current &+= range.step
                chunkSize &+= 1
            }
            chunks.append(registerRuntimeObject(RuntimeListBox(elements: chunkElements)))
        }
    } else if range.step < 0 {
        while current >= range.last {
            var chunkElements: [Int] = []
            var chunkSize = 0
            while chunkSize < size && current >= range.last {
                chunkElements.append(current)
                current &+= range.step
                chunkSize &+= 1
            }
            chunks.append(registerRuntimeObject(RuntimeListBox(elements: chunkElements)))
        }
    }
    return registerRuntimeObject(RuntimeListBox(elements: chunks))
}

func runtimeSignedRangeWindowed(_ range: RuntimeRangeBox, _ size: Int, _ step: Int, _ partialWindows: Int) -> Int {
    guard size > 0, step > 0 else { return registerRuntimeObject(RuntimeListBox(elements: [])) }
    var windows: [Int] = []
    var current = range.first
    if range.step > 0 {
        while current <= range.last {
            var windowElements: [Int] = []
            var windowCurrent = current
            var windowSize = 0
            while windowSize < size && windowCurrent <= range.last {
                windowElements.append(windowCurrent)
                windowCurrent &+= range.step
                windowSize &+= 1
            }
            if windowSize == size || (partialWindows != 0 && windowSize > 0) {
                windows.append(registerRuntimeObject(RuntimeListBox(elements: windowElements)))
            }
            current &+= (range.step &* step)
        }
    } else if range.step < 0 {
        while current >= range.last {
            var windowElements: [Int] = []
            var windowCurrent = current
            var windowSize = 0
            while windowSize < size && windowCurrent >= range.last {
                windowElements.append(windowCurrent)
                windowCurrent &+= range.step
                windowSize &+= 1
            }
            if windowSize == size || (partialWindows != 0 && windowSize > 0) {
                windows.append(registerRuntimeObject(RuntimeListBox(elements: windowElements)))
            }
            current &+= (range.step &* step)
        }
    }
    return registerRuntimeObject(RuntimeListBox(elements: windows))
}

func runtimeSignedRangeTake(_ range: RuntimeRangeBox, _ n: Int) -> Int {
    guard n > 0 else { return registerRuntimeObject(RuntimeListBox(elements: [])) }
    var elements: [Int] = []
    var taken = 0
    _ = runtimeSignedRangeTraverse(range) { current, _ in
        guard taken < n else { return false }
        elements.append(current)
        taken += 1
        return true
    }
    return registerRuntimeObject(RuntimeListBox(elements: elements))
}

func runtimeSignedRangeDrop(_ range: RuntimeRangeBox, _ n: Int) -> Int {
    var elements: [Int] = []
    var skipped = 0
    _ = runtimeSignedRangeTraverse(range) { current, _ in
        if skipped < n { skipped += 1 } else { elements.append(current) }
        return true
    }
    return registerRuntimeObject(RuntimeListBox(elements: elements))
}

func runtimeSignedRangeAverage(_ range: RuntimeRangeBox) -> Int {
    var sum: Double = 0.0
    var count: Double = 0.0
    _ = runtimeSignedRangeTraverse(range) { current, _ in
        sum += Double(current); count += 1.0; return true
    }
    let result: Double = count > 0 ? sum / count : Double.nan
    return Int(bitPattern: UInt(truncatingIfNeeded: result.bitPattern))
}

func runtimeSignedRangeSorted(_ range: RuntimeRangeBox) -> Int {
    var elements: [Int] = []
    _ = runtimeSignedRangeTraverse(range) { current, _ in elements.append(current); return true }
    elements.sort()
    return registerRuntimeObject(RuntimeListBox(elements: elements))
}

// MARK: - Unsigned HOF implementations

func runtimeUnsignedRangeToList(_ range: RuntimeRangeBox) -> Int {
    var elements: [Int] = []
    _ = runtimeUnsignedRangeTraverse(range) { current, _ in
        elements.append(Int(bitPattern: current)); return true
    }
    return registerRuntimeObject(RuntimeListBox(elements: elements))
}

func runtimeUnsignedRangeForEach(
    _ range: RuntimeRangeBox, _ fnPtr: Int, _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    _ = runtimeUnsignedRangeTraverse(range) { current, _ in
        var thrown = 0
        _ = lambda(closureRaw, Int(bitPattern: current), &thrown)
        if thrown != 0 { outThrown?.pointee = thrown; return false }
        return true
    }
    return 0
}

func runtimeUnsignedRangeMap(
    _ range: RuntimeRangeBox, _ fnPtr: Int, _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var mapped: [Int] = []
    _ = runtimeUnsignedRangeTraverse(range) { current, _ in
        var thrown = 0
        let result = lambda(closureRaw, Int(bitPattern: current), &thrown)
        if thrown != 0 { outThrown?.pointee = thrown; return false }
        mapped.append(result)
        return true
    }
    return registerRuntimeObject(RuntimeListBox(elements: mapped))
}

func runtimeUnsignedRangeMapIndexed(
    _ range: RuntimeRangeBox, _ fnPtr: Int, _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var mapped: [Int] = []
    _ = runtimeUnsignedRangeTraverse(range) { current, index in
        var thrown = 0
        let result = lambda(closureRaw, index, Int(bitPattern: current), &thrown)
        if thrown != 0 { outThrown?.pointee = thrown; return false }
        mapped.append(result)
        return true
    }
    return registerRuntimeObject(RuntimeListBox(elements: mapped))
}

func runtimeUnsignedRangeMapNotNull(
    _ range: RuntimeRangeBox, _ fnPtr: Int, _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var mapped: [Int] = []
    _ = runtimeUnsignedRangeTraverse(range) { current, _ in
        var thrown = 0
        let result = lambda(closureRaw, Int(bitPattern: current), &thrown)
        if thrown != 0 { outThrown?.pointee = thrown; return false }
        if result != runtimeNullSentinelInt { mapped.append(result) }
        return true
    }
    return registerRuntimeObject(RuntimeListBox(elements: mapped))
}

func runtimeUnsignedRangeFilter(
    _ range: RuntimeRangeBox, _ fnPtr: Int, _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var filtered: [Int] = []
    _ = runtimeUnsignedRangeTraverse(range) { current, _ in
        var thrown = 0
        let result = lambda(closureRaw, Int(bitPattern: current), &thrown)
        if thrown != 0 { outThrown?.pointee = thrown; return false }
        if result != 0 { filtered.append(Int(bitPattern: current)) }
        return true
    }
    return registerRuntimeObject(RuntimeListBox(elements: filtered))
}

func runtimeUnsignedRangeFilterIndexed(
    _ range: RuntimeRangeBox, _ fnPtr: Int, _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var filtered: [Int] = []
    _ = runtimeUnsignedRangeTraverse(range) { current, index in
        var thrown = 0
        let result = lambda(closureRaw, index, Int(bitPattern: current), &thrown)
        if thrown != 0 { outThrown?.pointee = thrown; return false }
        if result != 0 { filtered.append(Int(bitPattern: current)) }
        return true
    }
    return registerRuntimeObject(RuntimeListBox(elements: filtered))
}

func runtimeUnsignedRangeFilterNot(
    _ range: RuntimeRangeBox, _ fnPtr: Int, _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var filtered: [Int] = []
    _ = runtimeUnsignedRangeTraverse(range) { current, _ in
        var thrown = 0
        let result = lambda(closureRaw, Int(bitPattern: current), &thrown)
        if thrown != 0 { outThrown?.pointee = thrown; return false }
        if result == 0 { filtered.append(Int(bitPattern: current)) }
        return true
    }
    return registerRuntimeObject(RuntimeListBox(elements: filtered))
}

func runtimeUnsignedRangeReduce(
    _ range: RuntimeRangeBox, _ fnPtr: Int, _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard !runtimeUnsignedRangeIsEmpty(range) else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "Empty collection can't be reduced.")
        return 0
    }
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var accumulator = 0
    var hasAccumulator = false
    _ = runtimeUnsignedRangeTraverse(range) { current, _ in
        let value = Int(bitPattern: current)
        if !hasAccumulator { accumulator = value; hasAccumulator = true; return true }
        var thrown = 0
        accumulator = lambda(closureRaw, accumulator, value, &thrown)
        if thrown != 0 { outThrown?.pointee = thrown; return false }
        return true
    }
    return accumulator
}

func runtimeUnsignedRangeReduceIndexed(
    _ range: RuntimeRangeBox, _ fnPtr: Int, _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard !runtimeUnsignedRangeIsEmpty(range) else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "Empty collection can't be reduced.")
        return 0
    }
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var accumulator = 0
    var hasAccumulator = false
    _ = runtimeUnsignedRangeTraverse(range) { current, index in
        let value = Int(bitPattern: current)
        if !hasAccumulator { accumulator = value; hasAccumulator = true; return true }
        var thrown = 0
        accumulator = lambda(closureRaw, index, accumulator, value, &thrown)
        if thrown != 0 { outThrown?.pointee = thrown; return false }
        return true
    }
    return accumulator
}

func runtimeUnsignedRangeFold(
    _ range: RuntimeRangeBox, _ initialValue: Int, _ fnPtr: Int, _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var accumulator = initialValue
    _ = runtimeUnsignedRangeTraverse(range) { current, _ in
        var thrown = 0
        accumulator = lambda(closureRaw, accumulator, Int(bitPattern: current), &thrown)
        if thrown != 0 { outThrown?.pointee = thrown; return false }
        return true
    }
    return accumulator
}

func runtimeUnsignedRangeFoldIndexed(
    _ range: RuntimeRangeBox, _ initialValue: Int, _ fnPtr: Int, _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var accumulator = initialValue
    _ = runtimeUnsignedRangeTraverse(range) { current, index in
        var thrown = 0
        accumulator = lambda(closureRaw, index, accumulator, Int(bitPattern: current), &thrown)
        if thrown != 0 { outThrown?.pointee = thrown; return false }
        return true
    }
    return accumulator
}

func runtimeUnsignedRangeAny(
    _ range: RuntimeRangeBox, _ fnPtr: Int, _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var result = 0
    var didThrow = false
    _ = runtimeUnsignedRangeTraverse(range) { current, _ in
        var thrown = 0
        let value = lambda(closureRaw, Int(bitPattern: current), &thrown)
        if thrown != 0 { outThrown?.pointee = thrown; didThrow = true; return false }
        if value != 0 { result = 1; return false }
        return true
    }
    return didThrow ? 0 : result
}

func runtimeUnsignedRangeAll(
    _ range: RuntimeRangeBox, _ fnPtr: Int, _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var result = 1
    var didThrow = false
    _ = runtimeUnsignedRangeTraverse(range) { current, _ in
        var thrown = 0
        let value = lambda(closureRaw, Int(bitPattern: current), &thrown)
        if thrown != 0 { outThrown?.pointee = thrown; didThrow = true; return false }
        if value == 0 { result = 0; return false }
        return true
    }
    return didThrow ? 0 : result
}

func runtimeUnsignedRangeNone(
    _ range: RuntimeRangeBox, _ fnPtr: Int, _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var result = 1
    var didThrow = false
    _ = runtimeUnsignedRangeTraverse(range) { current, _ in
        var thrown = 0
        let value = lambda(closureRaw, Int(bitPattern: current), &thrown)
        if thrown != 0 { outThrown?.pointee = thrown; didThrow = true; return false }
        if value != 0 { result = 0; return false }
        return true
    }
    return didThrow ? 0 : result
}

func runtimeUnsignedRangeChunked(_ range: RuntimeRangeBox, _ size: Int) -> Int {
    guard size > 0 else { return registerRuntimeObject(RuntimeListBox(elements: [])) }
    let first = UInt(bitPattern: range.first)
    let last = UInt(bitPattern: range.last)
    var chunks: [Int] = []
    var current = first
    if range.step > 0 {
        let uStep = UInt(bitPattern: range.step)
        while current <= last {
            var chunkElements: [Int] = []
            var chunkSize = 0
            while chunkSize < size && current <= last {
                chunkElements.append(Int(bitPattern: current))
                let (next, overflow) = current.addingReportingOverflow(uStep)
                if overflow { break }
                current = next
                chunkSize &+= 1
            }
            chunks.append(registerRuntimeObject(RuntimeListBox(elements: chunkElements)))
        }
    } else if range.step < 0 {
        let uStep = UInt(range.step.magnitude)
        while current >= last {
            var chunkElements: [Int] = []
            var chunkSize = 0
            while chunkSize < size && current >= last {
                chunkElements.append(Int(bitPattern: current))
                let (next, overflow) = current.subtractingReportingOverflow(uStep)
                if overflow { break }
                current = next
                chunkSize &+= 1
            }
            chunks.append(registerRuntimeObject(RuntimeListBox(elements: chunkElements)))
        }
    }
    return registerRuntimeObject(RuntimeListBox(elements: chunks))
}

func runtimeUnsignedRangeWindowed(_ range: RuntimeRangeBox, _ size: Int, _ step: Int, _ partialWindows: Int) -> Int {
    guard size > 0, step > 0 else { return registerRuntimeObject(RuntimeListBox(elements: [])) }
    let first = UInt(bitPattern: range.first)
    let last = UInt(bitPattern: range.last)
    var windows: [Int] = []
    var current = first
    if range.step > 0 {
        let uStep = UInt(bitPattern: range.step)
        let advance = uStep &* UInt(step)
        while current <= last {
            var windowElements: [Int] = []
            var windowCurrent = current
            var windowSize = 0
            while windowSize < size && windowCurrent <= last {
                windowElements.append(Int(bitPattern: windowCurrent))
                let (next, overflow) = windowCurrent.addingReportingOverflow(uStep)
                if overflow { break }
                windowCurrent = next
                windowSize &+= 1
            }
            if windowSize == size || (partialWindows != 0 && windowSize > 0) {
                windows.append(registerRuntimeObject(RuntimeListBox(elements: windowElements)))
            }
            let (next, overflow) = current.addingReportingOverflow(advance)
            if overflow { break }
            current = next
        }
    } else if range.step < 0 {
        let uStep = UInt(range.step.magnitude)
        let advance = uStep &* UInt(step)
        while current >= last {
            var windowElements: [Int] = []
            var windowCurrent = current
            var windowSize = 0
            while windowSize < size && windowCurrent >= last {
                windowElements.append(Int(bitPattern: windowCurrent))
                let (next, overflow) = windowCurrent.subtractingReportingOverflow(uStep)
                if overflow { break }
                windowCurrent = next
                windowSize &+= 1
            }
            if windowSize == size || (partialWindows != 0 && windowSize > 0) {
                windows.append(registerRuntimeObject(RuntimeListBox(elements: windowElements)))
            }
            let (next, overflow) = current.subtractingReportingOverflow(advance)
            if overflow { break }
            current = next
        }
    }
    return registerRuntimeObject(RuntimeListBox(elements: windows))
}

func runtimeUnsignedRangeTake(_ range: RuntimeRangeBox, _ n: Int) -> Int {
    guard n > 0 else { return registerRuntimeObject(RuntimeListBox(elements: [])) }
    var elements: [Int] = []
    var taken = 0
    _ = runtimeUnsignedRangeTraverse(range) { current, _ in
        guard taken < n else { return false }
        elements.append(Int(bitPattern: current))
        taken += 1
        return true
    }
    return registerRuntimeObject(RuntimeListBox(elements: elements))
}

func runtimeUnsignedRangeDrop(_ range: RuntimeRangeBox, _ n: Int) -> Int {
    var elements: [Int] = []
    var skipped = 0
    _ = runtimeUnsignedRangeTraverse(range) { current, _ in
        if skipped < n { skipped += 1 } else { elements.append(Int(bitPattern: current)) }
        return true
    }
    return registerRuntimeObject(RuntimeListBox(elements: elements))
}

func runtimeUnsignedRangeAverage(_ range: RuntimeRangeBox) -> Int {
    var sum: Double = 0.0
    var count: Double = 0.0
    _ = runtimeUnsignedRangeTraverse(range) { current, _ in
        sum += Double(current); count += 1.0; return true
    }
    let result: Double = count > 0 ? sum / count : Double.nan
    return Int(bitPattern: UInt(truncatingIfNeeded: result.bitPattern))
}

func runtimeUnsignedRangeSorted(_ range: RuntimeRangeBox) -> Int {
    var elements: [Int] = []
    _ = runtimeUnsignedRangeTraverse(range) { current, _ in
        elements.append(Int(bitPattern: current)); return true
    }
    elements.sort { UInt(bitPattern: $0) < UInt(bitPattern: $1) }
    return registerRuntimeObject(RuntimeListBox(elements: elements))
}
