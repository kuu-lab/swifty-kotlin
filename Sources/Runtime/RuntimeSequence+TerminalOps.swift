// MARK: - Sequence Terminal Operations: first/firstOrNull/last/count (STDLIB-273)

@_cdecl("kk_sequence_first")
public func kk_sequence_first(_ seqRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    var found = false
    var result = 0
    if let seq = runtimeSequenceBox(from: seqRaw) {
        runtimeTraverseSequence(seq, outThrown: outThrown) { elem in
            result = elem
            found = true
            return false
        }
    } else {
        _ = runtimeTraverseSourceSequenceObject(seqRaw, outThrown: outThrown) { elem in
            result = elem
            found = true
            return false
        }
    }
    if let outThrown, outThrown.pointee != 0 { return 0 }
    if !found {
        outThrown?.pointee = runtimeAllocateNoSuchElementException(message: kEmptySequenceNoSuchElement)
        return 0
    }
    return result
}

@_cdecl("kk_sequence_firstOrNull")
public func kk_sequence_firstOrNull(_ seqRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    var found = false
    var result = 0
    if let seq = runtimeSequenceBox(from: seqRaw) {
        runtimeTraverseSequence(seq, outThrown: outThrown) { elem in
            result = elem
            found = true
            return false
        }
    } else {
        _ = runtimeTraverseSourceSequenceObject(seqRaw, outThrown: outThrown) { elem in
            result = elem
            found = true
            return false
        }
    }
    if let outThrown, outThrown.pointee != 0 { return runtimeNullSentinelInt }
    return found ? result : runtimeNullSentinelInt
}

@_cdecl("kk_sequence_random")
public func kk_sequence_random(_ seqRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let elements = runtimeSequenceSourceElementsOrThrow(
        from: seqRaw,
        caller: #function,
        outThrown: outThrown
    ) else {
        return 0
    }
    if let outThrown, outThrown.pointee != 0 { return 0 }
    guard let element = elements.randomElement() else {
        outThrown?.pointee = runtimeAllocateNoSuchElementException(message: kEmptySequenceNoSuchElement)
        return 0
    }
    return element
}

@_cdecl("kk_sequence_randomOrNull")
public func kk_sequence_randomOrNull(_ seqRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let elements = runtimeSequenceSourceElementsOrThrow(
        from: seqRaw,
        caller: #function,
        outThrown: outThrown
    ) else {
        return runtimeNullSentinelInt
    }
    if let outThrown, outThrown.pointee != 0 { return runtimeNullSentinelInt }
    return elements.randomElement() ?? runtimeNullSentinelInt
}

@_cdecl("kk_sequence_last")
public func kk_sequence_last(_ seqRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    var found = false
    var result = 0
    if let seq = runtimeSequenceBox(from: seqRaw) {
        runtimeTraverseSequence(seq, outThrown: outThrown) { elem in
            result = elem
            found = true
            return true
        }
    } else {
        let elements = runtimeSequenceSourceElements(from: seqRaw) ?? []
        if let last = elements.last {
            result = last
            found = true
        }
    }
    if let outThrown, outThrown.pointee != 0 { return 0 }
    if !found {
        outThrown?.pointee = runtimeAllocateNoSuchElementException(message: kEmptySequenceNoSuchElement)
        return 0
    }
    return result
}

@_cdecl("kk_sequence_lastOrNull")
public func kk_sequence_lastOrNull(_ seqRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    var found = false
    var result = 0
    if let seq = runtimeSequenceBox(from: seqRaw) {
        runtimeTraverseSequence(seq, outThrown: outThrown) { elem in
            result = elem
            found = true
            return true
        }
    } else {
        let elements = runtimeSequenceSourceElements(from: seqRaw) ?? []
        if let last = elements.last {
            result = last
            found = true
        }
    }
    if let outThrown, outThrown.pointee != 0 { return runtimeNullSentinelInt }
    return found ? result : runtimeNullSentinelInt
}

@_cdecl("kk_sequence_singleOrNull")
public func kk_sequence_singleOrNull(_ seqRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    var result = runtimeNullSentinelInt
    var count = 0
    if let seq = runtimeSequenceBox(from: seqRaw) {
        runtimeTraverseSequence(seq, outThrown: outThrown) { elem in
            count += 1
            if count == 1 {
                result = elem
                return true
            }
            result = runtimeNullSentinelInt
            return false
        }
    } else {
        let elements = runtimeSequenceSourceElements(from: seqRaw) ?? []
        if elements.count == 1 {
            result = elements[0]
            count = 1
        } else {
            count = elements.count
        }
    }
    if let outThrown, outThrown.pointee != 0 { return runtimeNullSentinelInt }
    return count == 1 ? result : runtimeNullSentinelInt
}

@_cdecl("kk_sequence_single")
public func kk_sequence_single(_ seqRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    var result = 0
    var count = 0
    if let seq = runtimeSequenceBox(from: seqRaw) {
        runtimeTraverseSequence(seq, outThrown: outThrown) { elem in
            count += 1
            if count == 1 {
                result = elem
                return true
            }
            return false
        }
    } else {
        let elements = runtimeSequenceSourceElements(from: seqRaw) ?? []
        count = elements.count
        if count == 1 {
            result = elements[0]
        }
    }
    if let outThrown, outThrown.pointee != 0 { return 0 }
    guard count == 1 else {
        if count == 0 {
            outThrown?.pointee = runtimeAllocateNoSuchElementException(
                message: kEmptySequenceNoSuchElement
            )
        } else {
            outThrown?.pointee = runtimeAllocateIllegalArgumentException(
                message: "Sequence has more than one element."
            )
        }
        return 0
    }
    return result
}

@_cdecl("kk_sequence_count")
public func kk_sequence_count(_ seqRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    var count = 0
    if let seq = runtimeSequenceBox(from: seqRaw) {
        runtimeTraverseSequence(seq, outThrown: outThrown) { _ in
            count += 1
            return true
        }
    } else {
        let elements = runtimeSequenceSourceElements(from: seqRaw) ?? []
        count = elements.count
    }
    if let outThrown, outThrown.pointee != 0 { return 0 }
    return count
}

// MARK: - Sequence Terminal Operations: contains/indexOf/elementAt/sum/average/toMutableList/toMutableSet/unzip

@_cdecl("kk_sequence_contains")
public func kk_sequence_contains(_ seqRaw: Int, _ element: Int) -> Int {
    var found = false
    if let seq = runtimeSequenceBox(from: seqRaw) {
        runtimeTraverseSequence(seq, outThrown: nil) { elem in
            if runtimeValuesEqual(elem, element) {
                found = true
                return false
            }
            return true
        }
    } else {
        let elements = runtimeSequenceSourceElementsOrPanic(from: seqRaw, caller: #function)
        found = elements.contains { runtimeValuesEqual($0, element) }
    }
    return found ? 1 : 0
}

@_cdecl("kk_sequence_indexOf")
public func kk_sequence_indexOf(_ seqRaw: Int, _ element: Int) -> Int {
    var index = -1
    var currentIndex = 0
    if let seq = runtimeSequenceBox(from: seqRaw) {
        runtimeTraverseSequence(seq, outThrown: nil) { elem in
            if runtimeValuesEqual(elem, element) {
                index = currentIndex
                return false
            }
            currentIndex += 1
            return true
        }
    } else {
        for elem in runtimeSequenceSourceElementsOrPanic(from: seqRaw, caller: #function) {
            if runtimeValuesEqual(elem, element) {
                index = currentIndex
                break
            }
            currentIndex += 1
        }
    }
    return index
}

@_cdecl("kk_sequence_indexOfFirst")
public func kk_sequence_indexOfFirst(
    _ seqRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var matchIndex = -1
    var currentIndex = 0
    if let seq = runtimeSequenceBox(from: seqRaw) {
        runtimeTraverseSequence(seq, outThrown: outThrown) { elem in
            var thrown = 0
            let result = lambda(closureRaw, elem, &thrown)
            if thrown != 0 {
                outThrown?.pointee = thrown
                return false
            }
            if maybeUnbox(result) != 0 {
                matchIndex = currentIndex
                return false
            }
            currentIndex += 1
            return true
        }
    } else {
        for elem in runtimeSequenceSourceElementsOrPanic(from: seqRaw, caller: #function) {
            var thrown = 0
            let result = lambda(closureRaw, elem, &thrown)
            if thrown != 0 {
                return handleCollectionLambdaThrow(thrown, outThrown)
            }
            if maybeUnbox(result) != 0 {
                matchIndex = currentIndex
                break
            }
            currentIndex += 1
        }
    }
    if let outThrown, outThrown.pointee != 0 {
        return runtimeExceptionCaughtSentinel
    }
    return matchIndex
}

@_cdecl("kk_sequence_lastIndexOf")
public func kk_sequence_lastIndexOf(_ seqRaw: Int, _ element: Int) -> Int {
    var index = -1
    var currentIndex = 0
    if let seq = runtimeSequenceBox(from: seqRaw) {
        runtimeTraverseSequence(seq, outThrown: nil) { elem in
            if runtimeValuesEqual(elem, element) {
                index = currentIndex
            }
            currentIndex += 1
            return true
        }
    } else {
        for elem in runtimeSequenceSourceElementsOrPanic(from: seqRaw, caller: #function) {
            if runtimeValuesEqual(elem, element) {
                index = currentIndex
            }
            currentIndex += 1
        }
    }
    return index
}

@_cdecl("kk_sequence_indexOfLast")
public func kk_sequence_indexOfLast(
    _ seqRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var matchIndex = -1
    var currentIndex = 0
    if let seq = runtimeSequenceBox(from: seqRaw) {
        runtimeTraverseSequence(seq, outThrown: outThrown) { elem in
            var thrown = 0
            let result = lambda(closureRaw, elem, &thrown)
            if thrown != 0 {
                outThrown?.pointee = thrown
                return false
            }
            if maybeUnbox(result) != 0 {
                matchIndex = currentIndex
            }
            currentIndex += 1
            return true
        }
    } else {
        for elem in runtimeSequenceSourceElementsOrPanic(from: seqRaw, caller: #function) {
            var thrown = 0
            let result = lambda(closureRaw, elem, &thrown)
            if thrown != 0 {
                return handleCollectionLambdaThrow(thrown, outThrown)
            }
            if maybeUnbox(result) != 0 {
                matchIndex = currentIndex
            }
            currentIndex += 1
        }
    }
    if let outThrown, outThrown.pointee != 0 {
        return runtimeExceptionCaughtSentinel
    }
    return matchIndex
}

@_cdecl("kk_sequence_intersect")
public func kk_sequence_intersect(_ seqRaw: Int, _ otherRaw: Int) -> Int {
    guard let otherElements = runtimeIterableElements(from: otherRaw) else {
        invalidContainerPanic(#function, "iterable")
    }
    var otherKeys = Set<RuntimeElementKey>()
    otherKeys.reserveCapacity(otherElements.count)
    for elem in otherElements {
        otherKeys.insert(RuntimeElementKey(value: elem))
    }

    var sourceElements: [Int] = []
    if let seq = runtimeSequenceBox(from: seqRaw) {
        runtimeTraverseSequence(seq, outThrown: nil) { elem in
            sourceElements.append(elem)
            return true
        }
    } else {
        sourceElements = runtimeSequenceSourceElementsOrPanic(from: seqRaw, caller: #function)
    }

    let result = runtimeDeduplicatePreservingOrder(sourceElements).filter { elem in
        otherKeys.contains(RuntimeElementKey(value: elem))
    }
    return registerRuntimeObject(RuntimeSetBox(elements: result))
}

@_cdecl("kk_sequence_elementAtOrNull")
public func kk_sequence_elementAtOrNull(_ seqRaw: Int, _ index: Int) -> Int {
    let elements = runtimeSequenceSourceElementsOrPanic(from: seqRaw, caller: #function)
    guard elements.indices.contains(index) else {
        return runtimeNullSentinelInt
    }
    return elements[index]
}

@_cdecl("kk_sequence_elementAt")
public func kk_sequence_elementAt(_ seqRaw: Int, _ index: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    let elements = runtimeSequenceSourceElementsOrPanic(from: seqRaw, caller: #function)
    guard elements.indices.contains(index) else {
        outThrown?.pointee = runtimeAllocateIndexOutOfBoundsException(
            message: "Sequence index \(index) out of bounds for length \(elements.count)."
        )
        return runtimeNullSentinelInt
    }
    return elements[index]
}

@_cdecl("kk_sequence_elementAtOrElse")
public func kk_sequence_elementAtOrElse(
    _ seqRaw: Int,
    _ index: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    let elements = runtimeSequenceSourceElementsOrPanic(from: seqRaw, caller: #function)
    if elements.indices.contains(index) {
        return elements[index]
    }
    let defaultValue = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var thrown = 0
    let result = defaultValue(closureRaw, index, &thrown)
    if thrown != 0 {
        outThrown?.pointee = thrown
        return runtimeNullSentinelInt
    }
    return result
}

@_cdecl("kk_sequence_sum")
public func kk_sequence_sum(_ seqRaw: Int) -> Int {
    let elements = runtimeSequenceSourceElementsOrPanic(from: seqRaw, caller: #function)
    var total = 0
    for element in elements { total &+= maybeUnbox(element) }
    return total
}

@_cdecl("kk_sequence_average")
public func kk_sequence_average(_ seqRaw: Int) -> Int {
    let elements = runtimeSequenceSourceElementsOrPanic(from: seqRaw, caller: #function)
    guard !elements.isEmpty else { return kk_double_to_bits(Double.nan) }
    var total = 0.0
    for element in elements { total += Double(maybeUnbox(element)) }
    return kk_double_to_bits(total / Double(elements.count))
}

@_cdecl("kk_sequence_toMutableList")
public func kk_sequence_toMutableList(_ seqRaw: Int) -> Int {
    let values = runtimeSequenceSourceValuesOrPanic(from: seqRaw, caller: #function)
    return registerRuntimeObject(RuntimeListBox(values: values))
}

// BUG-254: keep these on the same nominal tags as the Iterable terminals
// (`__kk_iterable_toMutableSet` / `__kk_iterable_toHashSet`) so the declared
// return type answers `is` the same way on both receivers.
@_cdecl("kk_sequence_toMutableSet")
public func kk_sequence_toMutableSet(_ seqRaw: Int) -> Int {
    let values = runtimeSequenceSourceValuesOrPanic(from: seqRaw, caller: #function)
    return registerRuntimeObject(
        RuntimeSetBox(values: runtimeDeduplicatePreservingOrder(values)),
        typeID: linkedHashSetRuntimeTypeID
    )
}

@_cdecl("kk_sequence_toHashSet")
public func kk_sequence_toHashSet(_ seqRaw: Int) -> Int {
    let values = runtimeSequenceSourceValuesOrPanic(from: seqRaw, caller: #function)
    return registerRuntimeObject(
        RuntimeSetBox(values: runtimeDeduplicatePreservingOrder(values)),
        typeID: hashSetRuntimeTypeID
    )
}

@_cdecl("kk_sequence_toCollection")
public func kk_sequence_toCollection(_ seqRaw: Int, _ destRaw: Int) -> Int {
    guard runtimeMutableCollectionExists(destRaw) else {
        invalidContainerPanic(#function, "mutable collection")
    }
    let values = runtimeSequenceSourceValuesOrPanic(from: seqRaw, caller: #function)
    for value in values {
        runtimeAppendToMutableCollection(destRaw, value)
    }
    return destRaw
}

@_cdecl("kk_sequence_unzip")
public func kk_sequence_unzip(_ seqRaw: Int) -> Int {
    let elements = runtimeSequenceSourceValuesOrPanic(from: seqRaw, caller: #function)
    var firstValues: [RuntimeValue] = []
    var secondValues: [RuntimeValue] = []
    firstValues.reserveCapacity(elements.count)
    secondValues.reserveCapacity(elements.count)
    for pairValue in elements {
        let pairRaw = pairValue.legacyRawValue
        guard let ptr = UnsafeMutableRawPointer(bitPattern: pairRaw),
              let pairBox = tryCast(ptr, to: RuntimePairBox.self)
        else {
            fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid Pair handle in \(#function)")
        }
        firstValues.append(pairBox.firstValue)
        secondValues.append(pairBox.secondValue)
    }
    let firstList = registerRuntimeObject(RuntimeListBox(values: firstValues))
    let secondList = registerRuntimeObject(RuntimeListBox(values: secondValues))
    return runtimePairNew(
        firstValue: RuntimeValue(raw: firstList),
        secondValue: RuntimeValue(raw: secondList)
    )
}

// MARK: - Sequence Terminal Operations: any/all/none/reduce (STDLIB-274)

@_cdecl("kk_sequence_any")
public func kk_sequence_any(
    _ seqRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    if fnPtr == 0 {
        let elements = runtimeSequenceSourceElementsOrPanic(from: seqRaw, caller: #function)
        return kk_box_bool(elements.isEmpty ? 0 : 1)
    }
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var matched = false
    if let seq = runtimeSequenceBox(from: seqRaw) {
        runtimeTraverseSequence(seq, outThrown: outThrown) { elem in
            var thrown = 0
            let result = lambda(closureRaw, elem, &thrown)
            if thrown != 0 {
                outThrown?.pointee = thrown
                return false
            }
            matched = maybeUnbox(result) != 0
            return !matched
        }
    } else {
        for elem in runtimeSequenceSourceElementsOrPanic(from: seqRaw, caller: #function) {
            var thrown = 0
            let result = lambda(closureRaw, elem, &thrown)
            if thrown != 0 {
                outThrown?.pointee = thrown
                return kk_box_bool(0)
            }
            if maybeUnbox(result) != 0 {
                matched = true
                break
            }
        }
    }
    if let outThrown, outThrown.pointee != 0 {
        return kk_box_bool(0)
    }
    return kk_box_bool(matched ? 1 : 0)
}

@_cdecl("kk_sequence_all")
public func kk_sequence_all(
    _ seqRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var allMatched = true
    if let seq = runtimeSequenceBox(from: seqRaw) {
        runtimeTraverseSequence(seq, outThrown: outThrown) { elem in
            var thrown = 0
            let result = lambda(closureRaw, elem, &thrown)
            if thrown != 0 {
                outThrown?.pointee = thrown
                return false
            }
            if maybeUnbox(result) == 0 {
                allMatched = false
                return false
            }
            return true
        }
    } else {
        for elem in runtimeSequenceSourceElementsOrPanic(from: seqRaw, caller: #function) {
            var thrown = 0
            let result = lambda(closureRaw, elem, &thrown)
            if thrown != 0 {
                outThrown?.pointee = thrown
                return kk_box_bool(0)
            }
            if maybeUnbox(result) == 0 {
                allMatched = false
                break
            }
        }
    }
    if let outThrown, outThrown.pointee != 0 {
        return kk_box_bool(0)
    }
    return kk_box_bool(allMatched ? 1 : 0)
}

@_cdecl("kk_sequence_none")
public func kk_sequence_none(
    _ seqRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    if fnPtr == 0 {
        let elements = runtimeSequenceSourceElementsOrPanic(from: seqRaw, caller: #function)
        return kk_box_bool(elements.isEmpty ? 1 : 0)
    }
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var foundMatch = false
    if let seq = runtimeSequenceBox(from: seqRaw) {
        runtimeTraverseSequence(seq, outThrown: outThrown) { elem in
            var thrown = 0
            let result = lambda(closureRaw, elem, &thrown)
            if thrown != 0 {
                outThrown?.pointee = thrown
                return false
            }
            foundMatch = maybeUnbox(result) != 0
            return !foundMatch
        }
    } else {
        for elem in runtimeSequenceSourceElementsOrPanic(from: seqRaw, caller: #function) {
            var thrown = 0
            let result = lambda(closureRaw, elem, &thrown)
            if thrown != 0 {
                outThrown?.pointee = thrown
                return kk_box_bool(1)
            }
            if maybeUnbox(result) != 0 {
                foundMatch = true
                break
            }
        }
    }
    if let outThrown, outThrown.pointee != 0 {
        return kk_box_bool(1)
    }
    return kk_box_bool(foundMatch ? 0 : 1)
}

@_cdecl("kk_sequence_reduce")
public func kk_sequence_reduce(
    _ seqRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    var hasAccumulator = false
    var acc = 0
    let visit: (Int) -> Bool = { elem in
        if !hasAccumulator {
            hasAccumulator = true
            acc = elem
            return true
        }
        let step = runtimeApplyFoldStep(accumulator: acc, element: elem, fnPtr: fnPtr, closureRaw: closureRaw, outThrown: outThrown)
        if step.thrown != 0 { return false }
        acc = step.accumulator
        return true
    }

    if let seq = runtimeSequenceBox(from: seqRaw) {
        runtimeTraverseSequence(seq, outThrown: outThrown, yield: visit)
    } else {
        for elem in runtimeSequenceSourceElementsOrPanic(from: seqRaw, caller: #function) {
            // swiftlint:disable:next for_where
            if !visit(elem) { break }
        }
    }

    if let outThrown, outThrown.pointee != 0 { return 0 }
    if !hasAccumulator {
        outThrown?.pointee = runtimeAllocateUnsupportedOperationException(message: kEmptySequenceCannotReduce)
        return 0
    }
    return acc
}

@_cdecl("kk_sequence_reduceOrNull")
public func kk_sequence_reduceOrNull(
    _ seqRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    var hasAccumulator = false
    var acc = 0
    let visit: (Int) -> Bool = { elem in
        if !hasAccumulator {
            hasAccumulator = true
            acc = maybeUnbox(elem)
            return true
        }
        let step = runtimeApplyFoldStep(accumulator: acc, element: elem, fnPtr: fnPtr, closureRaw: closureRaw, outThrown: outThrown)
        if step.thrown != 0 { return false }
        acc = step.accumulator
        return true
    }

    runtimeTraverseSequenceSource(seqRaw, caller: #function, outThrown: outThrown, yield: visit)
    if let outThrown, outThrown.pointee != 0 { return 0 }
    return hasAccumulator ? acc : runtimeNullSentinelInt
}

@_cdecl("kk_sequence_reduceRight")
public func kk_sequence_reduceRight(
    _ seqRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    var elements: [Int] = []
    runtimeTraverseSequenceSource(seqRaw, caller: #function, outThrown: outThrown) { elem in
        elements.append(elem)
        return true
    }
    if let outThrown, outThrown.pointee != 0 { return 0 }
    return runtimeReduceRightElements(
        elements,
        fnPtr: fnPtr,
        closureRaw: closureRaw,
        emptyResult: 0,
        throwResult: 0,
        emptyMessage: kEmptySequenceCannotReduce,
        outThrown: outThrown
    )
}

@_cdecl("kk_sequence_reduceRightIndexedOrNull")
public func kk_sequence_reduceRightIndexedOrNull(
    _ seqRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    var elements: [Int] = []
    runtimeTraverseSequenceSource(seqRaw, caller: #function, outThrown: outThrown) { elem in
        elements.append(elem)
        return true
    }
    if let outThrown, outThrown.pointee != 0 { return 0 }
    return runtimeReduceRightIndexedElements(
        elements,
        fnPtr: fnPtr,
        closureRaw: closureRaw,
        emptyResult: runtimeNullSentinelInt,
        throwResult: 0,
        emptyMessage: nil,
        outThrown: outThrown
    )
}

@_cdecl("kk_sequence_reduceRightOrNull")
public func kk_sequence_reduceRightOrNull(
    _ seqRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    var elements: [Int] = []
    runtimeTraverseSequenceSource(seqRaw, caller: #function, outThrown: outThrown) { elem in
        elements.append(elem)
        return true
    }
    if let outThrown, outThrown.pointee != 0 { return 0 }
    return runtimeReduceRightElements(
        elements,
        fnPtr: fnPtr,
        closureRaw: closureRaw,
        emptyResult: runtimeNullSentinelInt,
        throwResult: 0,
        emptyMessage: nil,
        outThrown: outThrown
    )
}

@_cdecl("kk_sequence_reduceRightIndexed")
public func kk_sequence_reduceRightIndexed(
    _ seqRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    var elements: [Int] = []
    runtimeTraverseSequenceSource(seqRaw, caller: #function, outThrown: outThrown) { elem in
        elements.append(elem)
        return true
    }
    if let outThrown, outThrown.pointee != 0 { return 0 }
    return runtimeReduceRightIndexedElements(
        elements,
        fnPtr: fnPtr,
        closureRaw: closureRaw,
        emptyResult: 0,
        throwResult: 0,
        emptyMessage: kEmptySequenceCannotReduce,
        outThrown: outThrown
    )
}
