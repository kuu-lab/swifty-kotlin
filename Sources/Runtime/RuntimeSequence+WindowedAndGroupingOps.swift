// MARK: - Sequence Operations: chunked/windowed/onEach (STDLIB-276)

public func kk_sequence_chunked(_ seqRaw: Int, _ size: Int) -> Int {
    let chunkSize = max(1, size)
    // Lazily traverse upstream to build chunks on the fly
    var chunks: [Int] = []
    var currentChunk: [Int] = []
    if let seq = runtimeSequenceBox(from: seqRaw) {
        runtimeTraverseSequence(seq, outThrown: nil) { elem in
            currentChunk.append(elem)
            if currentChunk.count == chunkSize {
                let chunkList = RuntimeListBox(elements: currentChunk)
                chunks.append(registerRuntimeObject(chunkList))
                currentChunk = []
            }
            return true
        }
    } else {
        let elements = runtimeSequenceSourceElements(from: seqRaw) ?? []
        for elem in elements {
            currentChunk.append(elem)
            if currentChunk.count == chunkSize {
                let chunkList = RuntimeListBox(elements: currentChunk)
                chunks.append(registerRuntimeObject(chunkList))
                currentChunk = []
            }
        }
    }
    if !currentChunk.isEmpty {
        let chunkList = RuntimeListBox(elements: currentChunk)
        chunks.append(registerRuntimeObject(chunkList))
    }
    let resultSeq = RuntimeSequenceBox(steps: [.source(elements: chunks)])
    return registerRuntimeObject(resultSeq)
}

public func kk_sequence_chunked_transform(
    _ seqRaw: Int,
    _ size: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard let seq = runtimeSequenceBox(from: seqRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid sequence in kk_sequence_chunked_transform")
    }

    let chunkedTransform = SequenceStepKind.chunkedTransformStep(
        size: max(1, size),
        fnPtr: fnPtr,
        closureRaw: closureRaw
    )
    let resultSeq = RuntimeSequenceBox(steps: seq.steps + [chunkedTransform])
    return registerRuntimeObject(resultSeq)
}

public func kk_sequence_windowed(_ seqRaw: Int, _ size: Int, _ step: Int, _ partialWindows: Int) -> Int {
    let clampedSize = max(1, size)
    let clampedStep = max(1, step)
    let includePartial = partialWindows != 0
    // Lazily traverse upstream to build windows on the fly
    var buffer: [Int] = []
    var windows: [Int] = []
    var elementIndex = 0
    var nextWindowStart = 0
    if let seq = runtimeSequenceBox(from: seqRaw) {
        runtimeTraverseSequence(seq, outThrown: nil) { elem in
            buffer.append(elem)
            elementIndex += 1
            // Emit windows whose start position we've passed
            while nextWindowStart <= elementIndex - clampedSize {
                let window = Array(buffer[nextWindowStart..<(nextWindowStart + clampedSize)])
                let windowList = RuntimeListBox(elements: window)
                windows.append(registerRuntimeObject(windowList))
                let (advancedStart, overflow) = nextWindowStart.addingReportingOverflow(clampedStep)
                nextWindowStart = overflow ? Int.max : advancedStart
            }
            return true
        }
    } else {
        let elements = runtimeSequenceSourceElements(from: seqRaw) ?? []
        buffer = elements
        elementIndex = elements.count
        while nextWindowStart <= elementIndex - clampedSize {
            let window = Array(buffer[nextWindowStart..<(nextWindowStart + clampedSize)])
            let windowList = RuntimeListBox(elements: window)
            windows.append(registerRuntimeObject(windowList))
            let (advancedStart, overflow) = nextWindowStart.addingReportingOverflow(clampedStep)
            nextWindowStart = overflow ? Int.max : advancedStart
        }
    }
    // Handle partial windows at the end
    if includePartial {
        while nextWindowStart < elementIndex {
            let end = nextWindowStart + min(clampedSize, elementIndex - nextWindowStart)
            let window = Array(buffer[nextWindowStart..<end])
            let windowList = RuntimeListBox(elements: window)
            windows.append(registerRuntimeObject(windowList))
            let (advancedStart, overflow) = nextWindowStart.addingReportingOverflow(clampedStep)
            nextWindowStart = overflow ? Int.max : advancedStart
        }
    }
    let resultSeq = RuntimeSequenceBox(steps: [.source(elements: windows)])
    return registerRuntimeObject(resultSeq)
}

public func kk_sequence_windowed_transform(
    _ seqRaw: Int,
    _ size: Int,
    _ step: Int,
    _ partialWindows: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    let windowsRaw = kk_sequence_windowed(seqRaw, size, step, partialWindows)
    let windows = runtimeSequenceSourceElementsOrPanic(from: windowsRaw, caller: #function)
    var results: [Int] = []
    results.reserveCapacity(windows.count)
    for windowRaw in windows {
        var thrown = 0
        let transformed = runtimeInvokeCollectionLambda1MaybeWrapped(
            fnPtr: fnPtr,
            closureRaw: closureRaw,
            value: windowRaw,
            outThrown: &thrown
        )
        if thrown != 0 {
            outThrown?.pointee = thrown
            return 0
        }
        results.append(maybeUnbox(transformed))
    }
    let resultSeq = RuntimeSequenceBox(steps: [.source(elements: results)])
    return registerRuntimeObject(resultSeq)
}

@_cdecl("kk_sequence_onEach")
public func kk_sequence_onEach(
    _ seqRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard let seq = runtimeSequenceBox(from: seqRaw) else {
        let sourceElements = runtimeSequenceSourceElements(from: seqRaw) ?? []
        let newSeq = RuntimeSequenceBox(steps: [
            .source(elements: sourceElements),
            .onEachStep(fnPtr: fnPtr, closureRaw: closureRaw),
        ])
        return registerRuntimeObject(newSeq)
    }
    var newSteps = seq.steps
    newSteps.append(.onEachStep(fnPtr: fnPtr, closureRaw: closureRaw))
    let newSeq = RuntimeSequenceBox(steps: newSteps, constrainOnceState: seq.constrainOnceState)
    return registerRuntimeObject(newSeq)
}

// MARK: - Sequence Terminal Operations: toSet/toMap/groupBy/maxOrNull/minOrNull/flatten (STDLIB-470)

@_cdecl("kk_sequence_toSet")
public func kk_sequence_toSet(_ seqRaw: Int) -> Int {
    let values = runtimeSequenceSourceValuesOrPanic(from: seqRaw, caller: #function)
    return registerRuntimeObject(RuntimeSetBox(values: runtimeDeduplicatePreservingOrder(values)))
}

@_cdecl("kk_sequence_toSortedSet")
public func kk_sequence_toSortedSet(_ seqRaw: Int) -> Int {
    let values = runtimeSequenceSourceValuesOrPanic(from: seqRaw, caller: #function)
    let sorted = values.enumerated().sorted { lhs, rhs in
        let comparison = runtimeCompareValues(lhs.element, rhs.element)
        if comparison != 0 {
            return comparison < 0
        }
        return lhs.offset < rhs.offset
    }.map(\.element)
    // KUU-1361: the result is a real sorted box so SortedSet members
    // (first/last/comparator) work on it; `SortedSet` remains the declared
    // Kotlin return type.
    let box = RuntimeSetBox(values: runtimeDeduplicatePreservingOrder(sorted))
    box.enableSorted(comparatorRaw: 0)
    return registerRuntimeObject(box, typeID: treeSetRuntimeTypeID)
}

@_cdecl("kk_sequence_toMap")
public func kk_sequence_toMap(_ seqRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let collected = runtimeSequenceSourceElementsOrThrow(
        from: seqRaw,
        caller: #function,
        outThrown: outThrown
    ) else {
        return runtimeNullSentinelInt
    }
    var keys: [Int] = []
    var values: [Int] = []
    // Dictionary mapping key index in `keys` for O(1) duplicate-key lookup.
    // Uses RuntimeElementKey to respect runtimeValuesEqual semantics (e.g. String content equality).
    var keyIndexByRuntimeKey: [RuntimeElementKey: Int] = [:]
    for element in collected {
        guard let pointer = UnsafeMutableRawPointer(bitPattern: element) else {
            fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_sequence_toMap element is not a valid Pair handle")
        }
        let isObjectPointer = runtimeStorage.withGCLock { state in
            state.objectPointers.contains(UInt(bitPattern: pointer))
        }
        guard isObjectPointer, let pair = tryCast(pointer, to: RuntimePairBox.self) else {
            fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_sequence_toMap element is not a valid Pair handle")
        }
        let runtimeKey = RuntimeElementKey(value: pair.first)
        if let idx = keyIndexByRuntimeKey[runtimeKey] {
            values[idx] = pair.second
        } else {
            let newIndex = keys.count
            keyIndexByRuntimeKey[runtimeKey] = newIndex
            keys.append(pair.first)
            values.append(pair.second)
        }
    }
    return registerRuntimeObject(RuntimeMapBox(keys: keys, values: values))
}

@_cdecl("kk_sequence_groupBy")
public func kk_sequence_groupBy(
    _ seqRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var groupKeys: [Int] = []
    var groupElements: [[Int]] = []
    // Uses RuntimeElementKey to respect runtimeValuesEqual semantics (e.g. String content equality).
    var keyToIndex: [RuntimeElementKey: Int] = [:]
    if let seq = runtimeSequenceBox(from: seqRaw) {
        runtimeTraverseSequence(seq, outThrown: outThrown) { elem in
            var thrown = 0
            let key = lambda(closureRaw, elem, &thrown)
            if thrown != 0 {
                outThrown?.pointee = thrown
                return false
            }
            let runtimeKey = RuntimeElementKey(value: key)
            if let grpIdx = keyToIndex[runtimeKey] {
                groupElements[grpIdx].append(elem)
            } else {
                let newIndex = groupKeys.count
                keyToIndex[runtimeKey] = newIndex
                groupKeys.append(key)
                groupElements.append([elem])
            }
            return true
        }
    } else {
        for elem in runtimeSequenceSourceElementsOrPanic(from: seqRaw, caller: #function) {
            var thrown = 0
            let key = lambda(closureRaw, elem, &thrown)
            if thrown != 0 {
                outThrown?.pointee = thrown
                return registerRuntimeObject(RuntimeMapBox(keys: [], values: []))
            }
            let runtimeKey = RuntimeElementKey(value: key)
            if let grpIdx = keyToIndex[runtimeKey] {
                groupElements[grpIdx].append(elem)
            } else {
                let newIndex = groupKeys.count
                keyToIndex[runtimeKey] = newIndex
                groupKeys.append(key)
                groupElements.append([elem])
            }
        }
    }
    if let outThrown, outThrown.pointee != 0 {
        return registerRuntimeObject(RuntimeMapBox(keys: [], values: []))
    }
    let values = groupElements.map { registerRuntimeObject(RuntimeListBox(elements: $0)) }
    return registerRuntimeObject(RuntimeMapBox(keys: groupKeys, values: values))
}

@_cdecl("kk_sequence_maxOrNull")
public func kk_sequence_maxOrNull(_ seqRaw: Int) -> Int {
    var best: Int?
    if let seq = runtimeSequenceBox(from: seqRaw) {
        runtimeTraverseSequence(seq, outThrown: nil) { elem in
            if let current = best {
                if runtimeCompareValues(elem, current) > 0 {
                    best = elem
                }
            } else {
                best = elem
            }
            return true
        }
    } else {
        let elements = runtimeSequenceSourceElementsOrPanic(from: seqRaw, caller: #function)
        guard let first = elements.first else {
            return runtimeNullSentinelInt
        }
        best = first
        for elem in elements.dropFirst() where runtimeCompareValues(elem, best!) > 0 {
            best = elem
        }
    }
    return best ?? runtimeNullSentinelInt
}

/// Sequence<T : Comparable>.max(): T (throws NoSuchElementException if empty)
@_cdecl("kk_sequence_max")
public func kk_sequence_max(_ seqRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    let result = kk_sequence_maxOrNull(seqRaw)
    guard result != runtimeNullSentinelInt else {
        return handleCollectionLambdaThrow(runtimeAllocateNoSuchElementException(message: kEmptySequenceNoSuchElement), outThrown)
    }
    return result
}

@_cdecl("kk_sequence_minOrNull")
public func kk_sequence_minOrNull(_ seqRaw: Int) -> Int {
    var best: Int?
    if let seq = runtimeSequenceBox(from: seqRaw) {
        runtimeTraverseSequence(seq, outThrown: nil) { elem in
            if let current = best {
                if runtimeCompareValues(elem, current) < 0 {
                    best = elem
                }
            } else {
                best = elem
            }
            return true
        }
    } else {
        let elements = runtimeSequenceSourceElementsOrPanic(from: seqRaw, caller: #function)
        guard let first = elements.first else {
            return runtimeNullSentinelInt
        }
        best = first
        for elem in elements.dropFirst() where runtimeCompareValues(elem, best!) < 0 {
            best = elem
        }
    }
    return best ?? runtimeNullSentinelInt
}

@_cdecl("kk_sequence_min")
public func kk_sequence_min(_ seqRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    var best: Int?
    runtimeTraverseSequenceSource(seqRaw, caller: #function, outThrown: outThrown) { elem in
        if let current = best {
            if runtimeCompareValues(elem, current) < 0 {
                best = elem
            }
        } else {
            best = elem
        }
        return true
    }
    if (outThrown?.pointee ?? 0) != 0 {
        return runtimeExceptionCaughtSentinel
    }
    guard let best else {
        return handleCollectionLambdaThrow(runtimeAllocateNoSuchElementException(message: kEmptySequenceNoSuchElement), outThrown)
    }
    return best
}

@_cdecl("kk_sequence_flatten")
public func kk_sequence_flatten(_ seqRaw: Int) -> Int {
    var outerElements: [Int] = []
    if let seq = runtimeSequenceBox(from: seqRaw) {
        runtimeTraverseSequence(seq, outThrown: nil) { elem in
            outerElements.append(elem)
            return true
        }
    } else {
        outerElements = runtimeSequenceSourceElementsOrPanic(from: seqRaw, caller: #function)
    }
    var result: [Int] = []
    for subRaw in outerElements {
        if let subList = runtimeListBox(from: subRaw) {
            result.append(contentsOf: subList.elements)
        } else if let subSeq = runtimeSequenceBox(from: subRaw) {
            result.append(contentsOf: evaluateSequence(subSeq))
        }
    }
    let newSeq = RuntimeSequenceBox(steps: [.source(elements: result)])
    return registerRuntimeObject(newSeq)
}

// MARK: - Sequence plus/minus Operations (STDLIB-561, STDLIB-562)
//
// IMPORTANT: Both plus and minus eagerly materialize the entire input
// sequence via evaluateSequence.  Unlike Kotlin's stdlib (which returns
// a lazy sequence), our implementation is eager.  This is an intentional
// simplification -- eager evaluation is correct for finite sequences and
// keeps the implementation simple.  A future optimisation can add
// .concat / .minus step kinds to RuntimeSequenceBox for lazy evaluation
// without changing the public ABI.
//
// ABI CONTRACT:
// - kk_sequence_plus(seqRaw, otherRaw): `otherRaw` MUST be a collection
//   handle (sequence, list, or array).  The compiler wraps single-element
//   operands via kk_sequence_of_single before calling this function, so
//   the runtime never needs to guess whether otherRaw is an element or a
//   collection.
// - kk_sequence_minus(seqRaw, element): `element` is always a single
//   value (not a collection handle).  The compiler only emits this call
//   when the RHS is known to be a non-collection expression.

@_cdecl("kk_sequence_plus")
public func kk_sequence_plus(_ seqRaw: Int, _ otherRaw: Int) -> Int {
    let lhsElements = runtimeSequenceSourceElementsOrPanic(from: seqRaw, caller: #function)
    let rhsElements = runtimeSequenceSourceElementsOrPanic(from: otherRaw, caller: #function)
    // Single-allocation concatenation: create an array with the exact
    // final capacity up front so there are no intermediate reallocations
    // or copy-on-write copies.
    let totalCount = lhsElements.count + rhsElements.count
    let combined = [Int](unsafeUninitializedCapacity: totalCount) { buffer, initializedCount in
        var idx = 0
        for e in lhsElements { buffer[idx] = e; idx += 1 }
        for e in rhsElements { buffer[idx] = e; idx += 1 }
        initializedCount = idx
    }
    let newSeq = RuntimeSequenceBox(steps: [.source(elements: combined)])
    return registerRuntimeObject(newSeq)
}

@_cdecl("kk_sequence_plus_element")
public func kk_sequence_plus_element(_ seqRaw: Int, _ element: Int) -> Int {
    let wrappedElement = kk_sequence_of_single(element)
    return kk_sequence_plus(seqRaw, wrappedElement)
}

@_cdecl("kk_sequence_minus")
public func kk_sequence_minus(_ seqRaw: Int, _ element: Int) -> Int {
    let elements = runtimeSequenceSourceElementsOrPanic(from: seqRaw, caller: #function)
    var result = elements
    // NOTE: runtimeValuesEqual compares primitives (Int, String, Bool, etc.)
    // by value but falls back to pointer identity for collection types
    // (List, Set, Map).  This means `minus` cannot remove collection
    // elements by structural equality (e.g., two distinct `listOf(1)`
    // instances).  This is a known limitation; fixing it requires adding
    // recursive structural comparison to runtimeValuesEqual, which is
    // tracked separately.
    if let index = result.firstIndex(where: { runtimeValuesEqual($0, element) }) {
        result.remove(at: index)
    }
    let newSeq = RuntimeSequenceBox(steps: [.source(elements: result)])
    return registerRuntimeObject(newSeq)
}

@_cdecl("kk_sequence_union")
public func kk_sequence_union(_ seqRaw: Int, _ otherRaw: Int) -> Int {
    let selfElements = runtimeSequenceSourceElementsOrPanic(from: seqRaw, caller: #function)
    let otherElements = runtimeUnboxCollectionElements(otherRaw)
    return registerRuntimeObject(RuntimeSetBox(elements: runtimeDeduplicatePreservingOrder(selfElements + otherElements)))
}

@_cdecl("kk_sequence_subtract")
public func kk_sequence_subtract(_ seqRaw: Int, _ otherRaw: Int) -> Int {
    let selfElements = runtimeSequenceSourceElementsOrPanic(from: seqRaw, caller: #function)
    let otherElements = runtimeUnboxCollectionElements(otherRaw)
    var otherKeys = Set<RuntimeElementKey>()
    otherKeys.reserveCapacity(otherElements.count)
    for elem in otherElements {
        otherKeys.insert(RuntimeElementKey(value: elem))
    }
    let result = runtimeDeduplicatePreservingOrder(selfElements).filter { elem in
        !otherKeys.contains(RuntimeElementKey(value: elem))
    }
    return registerRuntimeObject(RuntimeSetBox(elements: result))
}
