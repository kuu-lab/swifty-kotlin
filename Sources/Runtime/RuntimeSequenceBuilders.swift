import Foundation

// `sequence { yield(...) }` / `iterator { yield(...) }` builders
// (STDLIB-331/553/564).
//
// Split out from `RuntimeSequence.swift`.

// MARK: - Sequence Builder (sequence { yield(x) })

/// Resolve a raw handle to a RuntimeSequenceCoroutineBuilderProxy, or nil.
private func runtimeCoroutineBuilderProxy(from rawValue: Int) -> RuntimeSequenceCoroutineBuilderProxy? {
    resolveRuntimeHandle(rawValue, as: RuntimeSequenceCoroutineBuilderProxy.self)
}

@_cdecl("__kk_sequence_builder_yield")
public func __kk_sequence_builder_yield(_ builderRaw: Int, _ value: Int) -> Int {
    // STDLIB-563: If the handle is a coroutine builder proxy, yield lazily.
    if let proxy = runtimeCoroutineBuilderProxy(from: builderRaw) {
        return proxy.coroutine.yieldValue(value)
    }
    if let builder = runtimeSequenceBuilderBox(from: builderRaw) {
        builder.elements.append(value)
        return 0
    }
    // STDLIB-331/564: yield() is shared across sequence/iterator builders.
    // When the builder handle is a RuntimeIteratorBuilderBox, delegate to
    // the continuation-based yield. CPS producers return COROUTINE_SUSPENDED;
    // legacy producers block until the consumer requests the next element.
    if runtimeIteratorBuilderBox(from: builderRaw) != nil {
        return __kk_iterator_builder_yield(builderRaw, value)
    }
    fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_sequence_builder_yield received invalid builder handle")
}

// MARK: - yieldAll(iterable) (STDLIB-553)

@_cdecl("__kk_sequence_builder_yieldAll")
public func __kk_sequence_builder_yieldAll(_ builderRaw: Int, _ collectionRaw: Int) -> Int {
    // STDLIB-563: If the handle is a coroutine builder proxy, yield each element lazily.
    if let proxy = runtimeCoroutineBuilderProxy(from: builderRaw) {
        if let seq = runtimeSequenceBox(from: collectionRaw) {
            // Preserve outer lazy semantics: traverse nested sequence elements
            // on demand instead of materializing them first.
            runtimeTraverseSequence(seq, outThrown: nil) { elem in
                _ = proxy.coroutine.yieldValue(elem)
                return true
            }
        } else if let list = runtimeListBox(from: collectionRaw) {
            for elem in list.elements {
                _ = proxy.coroutine.yieldValue(elem)
            }
        } else if let array = runtimeArrayBox(from: collectionRaw) {
            for elem in array.elements {
                _ = proxy.coroutine.yieldValue(elem)
            }
        } else if let set = runtimeSetBox(from: collectionRaw) {
            for elem in set.elements {
                _ = proxy.coroutine.yieldValue(elem)
            }
        } else if runtimeIteratorBuilderBox(from: collectionRaw) != nil
               || runtimeListIteratorBox(from: collectionRaw) != nil {
            while __kk_iterator_builder_hasNext(collectionRaw) != 0 {
                _ = proxy.coroutine.yieldValue(__kk_iterator_builder_next(collectionRaw))
            }
        } else {
            fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_sequence_builder_yieldAll received invalid collection handle (expected List, Array, Set, Sequence, or Iterator)")
        }
        return 0
    }
    guard let builder = runtimeSequenceBuilderBox(from: builderRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_sequence_builder_yieldAll received invalid builder handle")
    }
    // Accept List, Array, Set, Sequence, or Iterator as the iterable source.
    if let elements = runtimeSequenceSourceElements(from: collectionRaw) {
        builder.elements.append(contentsOf: elements)
    } else if let set = runtimeSetBox(from: collectionRaw) {
        builder.elements.append(contentsOf: set.elements)
    } else if runtimeIteratorBuilderBox(from: collectionRaw) != nil
           || runtimeListIteratorBox(from: collectionRaw) != nil {
        while __kk_iterator_builder_hasNext(collectionRaw) != 0 {
            builder.elements.append(__kk_iterator_builder_next(collectionRaw))
        }
    } else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_sequence_builder_yieldAll received invalid collection handle (expected List, Array, Set, Sequence, or Iterator)")
    }
    return 0
}

@_cdecl("__kk_sequence_builder_build")
public func __kk_sequence_builder_build(_ fnPtr: Int, _ closureRaw: Int = 0) -> Int {
    // STDLIB-563: Legacy direct ABI path. Non-CPS callbacks still run on a
    // dedicated producer thread; compiler-generated builders use
    // __kk_sequence_builder_build_coro instead.
    let coroutine = RuntimeSequenceCoroutine(fnPtr: fnPtr, closureRaw: closureRaw)
    let seq = RuntimeSequenceBox(steps: [.lazyBuilder(coroutine: coroutine)])
    return registerRuntimeObject(seq)
}

@_cdecl("__kk_sequence_builder_build_coro")
public func __kk_sequence_builder_build_coro(_ entryPointRaw: Int, _ functionID: Int, _ closureRaw: Int) -> Int {
    let coroutine = RuntimeSequenceCoroutine(
        fnPtr: entryPointRaw,
        closureRaw: closureRaw,
        functionID: functionID,
        usesCPSProducer: true
    )
    let seq = RuntimeSequenceBox(steps: [.lazyBuilder(coroutine: coroutine)])
    return registerRuntimeObject(seq)
}

// MARK: - Iterator Builder (iterator { yield(x) }) (STDLIB-331/564)
// Continuation-based lazy iteration. The legacy direct ABI path uses a
// dedicated producer thread; compiler-generated builders use the CPS entry
// point below.

private func runtimeIteratorBuilderBox(from rawValue: Int) -> RuntimeIteratorBuilderBox? {
    resolveRuntimeHandle(rawValue, as: RuntimeIteratorBuilderBox.self)
}

@_cdecl("__kk_iterator_builder_build")
public func __kk_iterator_builder_build(_ fnPtr: Int) -> Int {
    let builder = RuntimeIteratorBuilderBox(fnPtr: fnPtr)
    let builderHandle = registerRuntimeObject(builder)
    builder.bindRegisteredHandle(builderHandle)
    return builderHandle
}

@_cdecl("__kk_iterator_builder_build_coro")
public func __kk_iterator_builder_build_coro(_ entryPointRaw: Int, _ functionID: Int, _ closureRaw: Int) -> Int {
    let builder = RuntimeIteratorBuilderBox(
        fnPtr: entryPointRaw,
        closureRaw: closureRaw,
        functionID: functionID,
        usesCPSProducer: true
    )
    let builderHandle = registerRuntimeObject(builder)
    builder.bindRegisteredHandle(builderHandle)
    return builderHandle
}

@_cdecl("__kk_iterator_builder_yield")
public func __kk_iterator_builder_yield(_ builderRaw: Int, _ value: Int) -> Int {
    guard let builder = runtimeIteratorBuilderBox(from: builderRaw) else {
        // Fall back: the handle might be a RuntimeSequenceBuilderBox when yield
        // is shared between sequence/iterator builders in older lowering paths.
        if let seqBuilder = runtimeSequenceBuilderBox(from: builderRaw) {
            seqBuilder.elements.append(value)
            return 0
        }
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_iterator_builder_yield received invalid builder handle")
    }
    return builder.yieldValue(value)
}

@_cdecl("__kk_iterator_builder_hasNext")
public func __kk_iterator_builder_hasNext(_ iterRaw: Int) -> Int {
    // Support both RuntimeIteratorBuilderBox and RuntimeListIteratorBox
    // for backwards compatibility with older lowering paths.
    if let iter = runtimeIteratorBuilderBox(from: iterRaw) {
        return iter.probeHasNext() ? 1 : 0
    }
    if let iter = runtimeListIteratorBox(from: iterRaw) {
        return iter.index < iter.elements.count ? 1 : 0
    }
    fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_iterator_builder_hasNext received invalid iterator handle")
}

@_cdecl("__kk_iterator_builder_next")
public func __kk_iterator_builder_next(_ iterRaw: Int) -> Int {
    if let iter = runtimeIteratorBuilderBox(from: iterRaw) {
        return iter.consumeNext()
    }
    // Backwards compatibility: older lowering paths may pass a RuntimeListIteratorBox.
    if let iter = runtimeListIteratorBox(from: iterRaw) {
        guard iter.index < iter.elements.count else {
            fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: NoSuchElementException: Iterator has no more elements.")
        }
        let value = iter.elements[iter.index]
        iter.index += 1
        return value
    }
    fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_iterator_builder_next received invalid iterator handle")
}

// MARK: - CORO-004 Phase 2: suspension-aware iterator builder consumer API
//
// These entry points are for future compiler use when the for-loop lowering is
// updated to handle COROUTINE_SUSPENDED returns from hasNext/next.  They must
// NOT replace __kk_iterator_builder_hasNext / __kk_iterator_builder_next because
// existing callers do not check for the COROUTINE_SUSPENDED sentinel.
//
// Calling convention for __kk_iterator_builder_hasNext_coro:
//   - Returns 1  → hasNext == true  (element ready; call __kk_iterator_builder_next)
//   - Returns 0  → hasNext == false (iterator exhausted)
//   - Returns kk_coroutine_suspended() → caller must propagate COROUTINE_SUSPENDED
//     and re-enter after the coroutine is resumed; the resumed value carries the
//     1 / 0 boolean result.

/// Suspend-capable hasNext for coroutine callers.
///
/// `continuationRaw` must be the raw handle of the CURRENT caller continuation
/// (i.e. the value of the `continuation` parameter passed into the enclosing
/// suspend entry point).  When 0, falls back to the blocking path.
@_cdecl("__kk_iterator_builder_hasNext_coro")
public func __kk_iterator_builder_hasNext_coro(_ iterRaw: Int, _ continuationRaw: Int) -> Int {
    guard let iter = runtimeIteratorBuilderBox(from: iterRaw) else {
        if let iter = runtimeListIteratorBox(from: iterRaw) {
            return iter.index < iter.elements.count ? 1 : 0
        }
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_iterator_builder_hasNext_coro received invalid iterator handle")
    }
    if continuationRaw != 0,
       let callerState = runtimeContinuationState(from: continuationRaw)
    {
        return iter.probeHasNextAsync(callerState: callerState)
    }
    return iter.probeHasNext() ? 1 : 0
}

/// Consume the current element after a successful hasNext.
///
/// This variant mirrors `__kk_iterator_builder_next` but is named separately so
/// the compiler can emit it alongside `__kk_iterator_builder_hasNext_coro`
/// without confusion.  The consumer-side read is always synchronous (state is
/// already `.hasValue` when hasNext returned 1), so no continuation is needed.
@_cdecl("__kk_iterator_builder_next_coro")
public func __kk_iterator_builder_next_coro(_ iterRaw: Int) -> Int {
    if let iter = runtimeIteratorBuilderBox(from: iterRaw) {
        return iter.consumeNext()
    }
    if let iter = runtimeListIteratorBox(from: iterRaw) {
        guard iter.index < iter.elements.count else {
            fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: NoSuchElementException: Iterator has no more elements.")
        }
        let value = iter.elements[iter.index]
        iter.index += 1
        return value
    }
    fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_iterator_builder_next_coro received invalid iterator handle")
}

/// Sentinel value used by kk_sequence_builder (lazy coroutine) to signal
/// end-of-sequence via `callerState.resume(with:)` (CORO-004 Phase 2).
/// The caller compares the resume value against this sentinel to distinguish
/// a real element from the done signal.
@_cdecl("kk_sequence_completed_sentinel")
public func kk_sequence_completed_sentinel() -> Int {
    Int(bitPattern:
        UnsafeMutableRawPointer(
            Unmanaged.passUnretained(runtimeStorage.sequenceCompletedBox).toOpaque()
        )
    )
}
