// MARK: - Sequence Factory Functions

public func kk_sequence_from_list(_ listRaw: Int) -> Int {
    guard let list = runtimeListBox(from: listRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_sequence_from_list received invalid list handle")
    }
    let seq = RuntimeSequenceBox(steps: [.source(elements: list.elements)])
    return registerRuntimeObject(seq)
}

// MARK: - emptySequence (STDLIB-277)

@_cdecl("__kk_empty_sequence")
public func __kk_empty_sequence() -> Int {
    let seq = RuntimeSequenceBox(steps: [.source(elements: [])])
    return registerRuntimeObject(seq)
}

// MARK: - Sequence.ifEmpty (STDLIB-277)

@_cdecl("kk_sequence_ifEmpty")
public func kk_sequence_ifEmpty(
    _ seqRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    let elements = runtimeSequenceSourceElements(from: seqRaw) ?? []
    if elements.isEmpty {
        var thrown = 0
        let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int).self)
        let result = lambda(closureRaw, &thrown)
        if thrown != 0 {
            outThrown?.pointee = thrown
            return registerRuntimeObject(RuntimeSequenceBox(steps: [.source(elements: [])]))
        }
        return result
    }
    return seqRaw
}

@_cdecl("__kk_sequence_of")
public func __kk_sequence_of(_ arrayRaw: Int) -> Int {
    let elements: [Int]
    if let arr = runtimeArrayBox(from: arrayRaw) {
        elements = Array(arr.elements)
    } else if let list = runtimeListBox(from: arrayRaw) {
        // Source-backed vararg functions are normalized to a list at their
        // public call boundary; accept that representation while preserving
        // the packed-array ABI used by direct bridge calls.
        elements = Array(list.elements)
    } else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_sequence_of expected RuntimeArrayBox or RuntimeListBox")
    }
    let seq = RuntimeSequenceBox(steps: [.source(elements: elements)])
    return registerRuntimeObject(seq)
}

/// Wrap a single element value in a one-element sequence.
/// Used by the compiler to ensure `Sequence + element` always passes a
/// collection handle to `kk_sequence_plus`, avoiding the ambiguity where
/// a raw element value could collide with a live runtime object handle.
@_cdecl("kk_sequence_of_single")
public func kk_sequence_of_single(_ element: Int) -> Int {
    let seq = RuntimeSequenceBox(steps: [.source(elements: [element])])
    return registerRuntimeObject(seq)
}

@_cdecl("__kk_sequence_generate")
public func __kk_sequence_generate(_ seed: Int, _ fnPtr: Int, _ closureRaw: Int) -> Int {
    let seq = RuntimeSequenceBox(steps: [.generator(seed: seed, fnPtr: fnPtr, closureRaw: closureRaw)])
    return registerRuntimeObject(seq)
}

/// STDLIB-SEQ-002: 1-arg form `generateSequence(nextFunction: () -> T?)`.
/// Calls `nextFunction` (no-arg closure) repeatedly; stops when null is returned.
@_cdecl("__kk_sequence_generate_noarg")
public func __kk_sequence_generate_noarg(_ fnPtr: Int, _ closureRaw: Int) -> Int {
    let seq = RuntimeSequenceBox(steps: [.nullableGenerator(fnPtr: fnPtr, closureRaw: closureRaw)])
    return registerRuntimeObject(seq)
}

@_cdecl("kk_sequence_constrainOnce")
public func kk_sequence_constrainOnce(_ seqRaw: Int) -> Int {
    guard let seq = runtimeSequenceBox(from: seqRaw) else {
        let sourceElements = runtimeSequenceSourceElementsOrPanic(from: seqRaw, caller: #function)
        let constrained = RuntimeSequenceBox(
            steps: [.source(elements: sourceElements)],
            constrainOnceState: RuntimeSequenceConstrainOnceState()
        )
        return registerRuntimeObject(constrained)
    }
    let constrained = RuntimeSequenceBox(
        steps: seq.steps,
        constrainOnceState: seq.constrainOnceState ?? RuntimeSequenceConstrainOnceState()
    )
    return registerRuntimeObject(constrained)
}
