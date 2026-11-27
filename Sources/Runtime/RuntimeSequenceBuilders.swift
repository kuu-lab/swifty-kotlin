import Foundation



private func runtimeCoroutineBuilderProxy(from rawValue: Int) -> RuntimeSequenceCoroutineBuilderProxy? {
    resolveRuntimeHandle(rawValue, as: RuntimeSequenceCoroutineBuilderProxy.self)
}

private func runtimeSequenceBuilderYieldAllIterator(
    from collectionRaw: Int,
    outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    return runtimeThrowingBridge(outThrown) {
        if runtimeSequenceBox(from: collectionRaw) != nil {
            return kk_sequence_box_iterator(collectionRaw, outThrown)
        }

        let isArray = runtimeArrayBox(from: collectionRaw).map { type(of: $0) == RuntimeArrayBox.self } ?? false
        if runtimeListBox(from: collectionRaw) != nil
            || isArray
            || runtimeSetBox(from: collectionRaw) != nil
            || runtimeRangeBox(from: collectionRaw) != nil
        {
            return kk_iterable_iterator(collectionRaw, outThrown)
        }

        if let iterator = runtimeSourceIterableIterator(collectionRaw, outThrown: outThrown) {
            return iterator
        }
        if (outThrown?.pointee ?? 0) != 0 {
            return 0
        }

        let sequenceIterator = kk_itable_lookup_dynamic(
            collectionRaw,
            Int(runtimeStableNominalTypeID(fqName: "kotlin.sequences.Sequence")),
            0
        )
        if sequenceIterator != 0 {
            let acquire = unsafeBitCast(
                sequenceIterator,
                to: (@convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int).self
            )
            return acquire(collectionRaw, outThrown)
        }
        return collectionRaw
    }
}

@_cdecl("__kk_sequence_builder_yield")
public func __kk_sequence_builder_yield(_ builderRaw: Int, _ value: Int) -> Int {
    if let proxy = runtimeCoroutineBuilderProxy(from: builderRaw) {
        return proxy.coroutine.yieldValue(value)
    }
    if let builder = runtimeSequenceBuilderBox(from: builderRaw) {
        builder.elements.append(value)
        return 0
    }
    if runtimeIteratorBuilderBox(from: builderRaw) != nil {
        return __kk_iterator_builder_yield(builderRaw, value)
    }
    fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_sequence_builder_yield received invalid builder handle")
}


@_cdecl("__kk_sequence_builder_yieldAll_checked")
public func __kk_sequence_builder_yieldAll_checked(
    _ builderRaw: Int,
    _ collectionRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    return runtimeThrowingBridge(outThrown) {
        if let builder = runtimeIteratorBuilderBox(from: builderRaw) {
            var thrown = 0
            let iterator = runtimeSequenceBuilderYieldAllIterator(
                from: collectionRaw,
                outThrown: &thrown
            )
            if thrown != 0 {
                outThrown?.pointee = thrown
                return 0
            }
            return builder.yieldAll(iterator, outThrown: outThrown)
        }

        if let proxy = runtimeCoroutineBuilderProxy(from: builderRaw) {
            var thrown = 0
            let iterator = runtimeSequenceBuilderYieldAllIterator(
                from: collectionRaw,
                outThrown: &thrown
            )
            if thrown != 0 {
                outThrown?.pointee = thrown
                return 0
            }
            return proxy.coroutine.yieldAll(iterator, outThrown: outThrown)
        }

        if runtimeRangeBox(from: collectionRaw) != nil,
           runtimeSequenceBuilderBox(from: builderRaw) != nil
        {
            var thrown = 0
            let iterator = kk_iterable_iterator(collectionRaw, &thrown)
            if thrown != 0 {
                outThrown?.pointee = thrown
                return 0
            }
            while kk_iterator_hasNext(iterator, &thrown) != 0, thrown == 0 {
                let value = kk_iterator_next(iterator, &thrown)
                if thrown != 0 { break }
                _ = __kk_sequence_builder_yield(builderRaw, value)
            }
            outThrown?.pointee = thrown
            return 0
        }

        return __kk_sequence_builder_yieldAll(builderRaw, collectionRaw)
    }
}

@_cdecl("__kk_sequence_builder_yieldAll")
public func __kk_sequence_builder_yieldAll(_ builderRaw: Int, _ collectionRaw: Int) -> Int {
    if runtimeIteratorBuilderBox(from: builderRaw) != nil {
        var thrown = 0
        let result = __kk_sequence_builder_yieldAll_checked(builderRaw, collectionRaw, &thrown)
        runtimePropagateThrownOrTrap(thrown, outThrown: nil, context: #function)
        return result
    }
    if let proxy = runtimeCoroutineBuilderProxy(from: builderRaw) {
        var thrown = 0
        let result = __kk_sequence_builder_yieldAll_checked(builderRaw, collectionRaw, &thrown)
        proxy.coroutine.recordFailure(thrown)
        return result
    }
    guard let builder = runtimeSequenceBuilderBox(from: builderRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_sequence_builder_yieldAll received invalid builder handle")
    }
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

func runtimeIteratorBuilderBox(from rawValue: Int) -> RuntimeIteratorBuilderBox? {
    resolveRuntimeHandle(rawValue, as: RuntimeIteratorBuilderBox.self)
}

@_cdecl("__kk_iterator_builder_build")
public func __kk_iterator_builder_build(_ fnPtr: Int, _ closureRaw: Int = 0) -> Int {
    let builder = RuntimeIteratorBuilderBox(fnPtr: fnPtr, closureRaw: closureRaw)
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
    if let iter = runtimeIteratorBuilderBox(from: iterRaw) {
        return iter.probeHasNext() ? 1 : 0
    }
    if let iter = runtimeListIteratorBox(from: iterRaw) {
        return iter.index < iter.values.count ? 1 : 0
    }
    fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_iterator_builder_hasNext received invalid iterator handle")
}

@_cdecl("__kk_iterator_builder_next")
public func __kk_iterator_builder_next(_ iterRaw: Int) -> Int {
    if let iter = runtimeIteratorBuilderBox(from: iterRaw) {
        return iter.consumeNext()
    }
    if let iter = runtimeListIteratorBox(from: iterRaw) {
        guard iter.index < iter.values.count else {
            fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: NoSuchElementException: Iterator has no more elements.")
        }
        let value = iter.values[iter.index].legacyRawValue
        iter.index += 1
        return value
    }
    fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_iterator_builder_next received invalid iterator handle")
}

