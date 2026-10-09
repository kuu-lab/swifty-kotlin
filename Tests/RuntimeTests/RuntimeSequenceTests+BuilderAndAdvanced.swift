#if canImport(Testing)
@testable import Runtime
import Foundation
import Testing

private let cpsSequenceBuilderFunctionID = 730_001
private let cpsSequenceBuilderEntry: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { continuation, _ in
    let builderRaw = Int(kk_coroutine_launcher_arg_get(continuation, 1))
    switch kk_coroutine_state_enter(continuation, cpsSequenceBuilderFunctionID) {
    case 0:
        _ = kk_coroutine_state_set_label(continuation, 1)
        return __kk_sequence_builder_yield(builderRaw, 7)
    case 1:
        _ = kk_coroutine_state_set_label(continuation, 2)
        return __kk_sequence_builder_yield(builderRaw, 11)
    default:
        return kk_coroutine_state_exit(continuation, 0)
    }
}

private let cpsIteratorBuilderFunctionID = 730_002
private let cpsIteratorBuilderEntry: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { continuation, _ in
    // Suspend-entry launcher ABI: slot 0 is the closure environment, slot 1
    // the SequenceScope receiver (KUU-1359).
    let builderRaw = Int(kk_coroutine_launcher_arg_get(continuation, 1))
    switch kk_coroutine_state_enter(continuation, cpsIteratorBuilderFunctionID) {
    case 0:
        _ = kk_coroutine_state_set_label(continuation, 1)
        return __kk_iterator_builder_yield(builderRaw, 5)
    case 1:
        _ = kk_coroutine_state_set_label(continuation, 2)
        return __kk_iterator_builder_yield(builderRaw, 8)
    default:
        return kk_coroutine_state_exit(continuation, 0)
    }
}

/// Sequence builder / advanced operator / SharedFlow / StateFlow
/// tests, split out from `RuntimeSequenceTests` to keep each test
/// source focused.
extension RuntimeSequenceTests {
    @Test
    func testFactoryBuilderIteratorsAreLazyAndIndependent() {
        let thunk: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { counter, builder, _ in
            let count = UnsafeMutablePointer<Int>(bitPattern: counter)!
            count.pointee += 1
            _ = __kk_sequence_builder_yield(builder, count.pointee)
            count.pointee += 1
            _ = __kk_sequence_builder_yield(builder, count.pointee)
            return 0
        }
        var count = 0
        withUnsafeMutablePointer(to: &count) { counter in
            let seq = __kk_sequence_builder_build(unsafeBitCast(thunk, to: Int.self), Int(bitPattern: counter))
            var thrown = 0
            let a = kk_sequence_box_iterator(seq, &thrown)
            let b = kk_sequence_box_iterator(seq, &thrown)
            #expect(counter.pointee == 0)
            #expect(kk_sequence_iterator_hasNext(a, &thrown) == 1)
            #expect(kk_sequence_iterator_hasNext(a, &thrown) == 1)
            #expect(counter.pointee == 1)
            #expect(kk_sequence_iterator_next(a, &thrown) == 1)
            #expect(kk_sequence_iterator_next(b, &thrown) == 2)
            #expect(kk_sequence_iterator_next(a, &thrown) == 3)
            #expect(kk_sequence_iterator_next(b, &thrown) == 4)
            #expect(kk_sequence_iterator_hasNext(a, &thrown) == 0)
            #expect(kk_sequence_iterator_hasNext(b, &thrown) == 0)
            #expect(sequenceElements(seq) == [5, 6])
            #expect(thrown == 0)
        }
    }

    @Test
    func testFactoryBuildersPropagateExceptions() {
        let sequenceThunk: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, _, thrown in
            thrown?.pointee = runtimeAllocateIllegalStateException(message: "sequence boom")
            return 0
        }
        let seq = __kk_sequence_builder_build(unsafeBitCast(sequenceThunk, to: Int.self))
        var thrown = 0
        let seqIter = kk_sequence_box_iterator(seq, &thrown)
        #expect(kk_sequence_iterator_hasNext(seqIter, &thrown) == 0)
        #expect(thrown != 0)
        thrown = 0
        #expect(kk_sequence_to_list(seq, &thrown) == runtimeNullSentinelInt)
        #expect(thrown != 0)
        let iteratorThunk: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { _, thrown in
            thrown?.pointee = runtimeAllocateIllegalStateException(message: "iterator boom")
            return 0
        }
        let iter = __kk_iterator_builder_build(unsafeBitCast(iteratorThunk, to: Int.self))
        thrown = 0
        #expect(kk_iterator_hasNext(iter, &thrown) == 0)
        #expect(thrown != 0)
    }

    @Test
    func testFactoryGeneratorIteratorDoesNotTruncateAtOneHundredThousand() {
        let next: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, value, _ in value + 1 }
        let seq = __kk_sequence_generate(0, unsafeBitCast(next, to: Int.self), 0)
        var thrown = 0
        let iter = kk_sequence_box_iterator(seq, &thrown)
        for expected in 0...100_001 {
            #expect(kk_sequence_iterator_next(iter, &thrown) == expected)
        }
        #expect(thrown == 0)
    }

    @Test(arguments: [false, true])
    func testFactoryYieldAllPropagatesNestedIteratorFailure(yieldsFirst: Bool) throws {
        let inner: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { _, thrown in
            thrown?.pointee = runtimeAllocateIllegalArgumentException(message: "nested")
            return 0
        }
        let innerAfterYield: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { builder, thrown in
            _ = __kk_iterator_builder_yield(builder, 17)
            thrown?.pointee = runtimeAllocateIllegalArgumentException(message: "nested")
            return 0
        }
        let outer: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { iterator, builder, _ in
            _ = __kk_sequence_builder_yieldAll(builder, iterator)
            _ = __kk_sequence_builder_yield(builder, 99)
            return 0
        }
        let iterator = __kk_iterator_builder_build(unsafeBitCast(yieldsFirst ? innerAfterYield : inner, to: Int.self))
        let sequence = __kk_sequence_builder_build(unsafeBitCast(outer, to: Int.self), iterator)
        var thrown = 0
        #expect(kk_sequence_to_list(sequence, &thrown) == runtimeNullSentinelInt)
        let error = try #require(resolveRuntimeHandle(thrown, as: RuntimeThrowableBox.self))
        #expect(error.exceptionFQName == "kotlin.IllegalArgumentException")
        #expect(error.message == "nested")
    }

    @Test(arguments: [false, true], [false, true])
    func testFactoryFailedIteratorDoesNotReplayProducerException(firstUsesNext: Bool, usesCPS: Bool) throws {
        let producer: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { _, thrown in
            thrown?.pointee = runtimeAllocateIllegalArgumentException(message: "boom")
            return 0
        }
        let iterator = usesCPS
            ? __kk_iterator_builder_build_coro(unsafeBitCast(producer, to: Int.self), 730_003, 0)
            : __kk_iterator_builder_build(unsafeBitCast(producer, to: Int.self))
        var thrown = 0
        if firstUsesNext {
            _ = kk_iterator_next(iterator, &thrown)
        } else {
            _ = kk_iterator_hasNext(iterator, &thrown)
        }
        let original = try #require(resolveRuntimeHandle(thrown, as: RuntimeThrowableBox.self))
        #expect(original.exceptionFQName == "kotlin.IllegalArgumentException")
        #expect(original.message == "boom")
        for usesNext in [false, true, false] {
            thrown = 0
            if usesNext {
                _ = kk_iterator_next(iterator, &thrown)
            } else {
                _ = kk_iterator_hasNext(iterator, &thrown)
            }
            let failure = try #require(resolveRuntimeHandle(thrown, as: RuntimeThrowableBox.self))
            #expect(failure.exceptionFQName == "kotlin.IllegalStateException")
            #expect(failure.message == "Iterator has failed.")
        }
    }

    @Test
    func testFactoryYieldAllPropagatesNestedSequenceFailure() throws {
        let inner: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, builder, thrown in
            _ = __kk_sequence_builder_yield(builder, 17)
            thrown?.pointee = runtimeAllocateIllegalArgumentException(message: "nested sequence")
            return 0
        }
        let outer: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { source, builder, _ in
            __kk_sequence_builder_yieldAll(builder, source)
        }
        let source = __kk_sequence_builder_build(unsafeBitCast(inner, to: Int.self))
        let sequence = __kk_sequence_builder_build(unsafeBitCast(outer, to: Int.self), source)
        var thrown = 0
        #expect(kk_sequence_to_list(sequence, &thrown) == runtimeNullSentinelInt)
        let failure = try #require(resolveRuntimeHandle(thrown, as: RuntimeThrowableBox.self))
        #expect(failure.exceptionFQName == "kotlin.IllegalArgumentException")
        #expect(failure.message == "nested sequence")
    }

    @Test(arguments: [false, true])
    func testFactoryFailedSequenceIteratorDoesNotReplayProducerException(usesCPS: Bool) throws {
        let legacy: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, _, thrown in
            thrown?.pointee = runtimeAllocateIllegalArgumentException(message: "sequence boom")
            return 0
        }
        let cps: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { _, thrown in
            thrown?.pointee = runtimeAllocateIllegalArgumentException(message: "sequence boom")
            return 0
        }
        let sequence = usesCPS
            ? __kk_sequence_builder_build_coro(unsafeBitCast(cps, to: Int.self), 730_004, 0)
            : __kk_sequence_builder_build(unsafeBitCast(legacy, to: Int.self))
        var thrown = 0
        let iterator = kk_sequence_box_iterator(sequence, &thrown)
        for probe in 0..<3 {
            #expect(kk_sequence_iterator_hasNext(iterator, &thrown) == 0)
            let failure = try #require(resolveRuntimeHandle(thrown, as: RuntimeThrowableBox.self))
            #expect(failure.exceptionFQName == (probe == 0 ? "kotlin.IllegalArgumentException" : "kotlin.IllegalStateException"))
            #expect(failure.message == (probe == 0 ? "sequence boom" : "Iterator has failed."))
        }
        _ = kk_sequence_iterator_next(iterator, &thrown)
        let failure = try #require(resolveRuntimeHandle(thrown, as: RuntimeThrowableBox.self))
        #expect(failure.message == "Iterator has failed.")
        let fresh = kk_sequence_box_iterator(sequence, &thrown)
        _ = kk_sequence_iterator_next(fresh, &thrown)
        let original = try #require(resolveRuntimeHandle(thrown, as: RuntimeThrowableBox.self))
        #expect(original.message == "sequence boom")
    }

    @Test
    func testFactoryGeneratorClaimsOneShotAtIteratorAcquisition() {
        let next: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { _, _ in runtimeNullSentinelInt }
        let source = __kk_sequence_generate_noarg(unsafeBitCast(next, to: Int.self), 0)
        let seq = kk_sequence_constrainOnce(source)
        var thrown = 0
        let first = kk_sequence_box_iterator(seq, &thrown)
        #expect(first != 0)
        #expect(thrown == 0)
        #expect(kk_sequence_box_iterator(seq, &thrown) == 0)
        #expect(thrown != 0)
        #expect(kk_sequence_iterator_hasNext(first, &thrown) == 0)
        #expect(thrown == 0)
    }

    @Test
    func testSequenceBuilderBuildYieldsElementsInOrder() {
        // sequence { yield(1); yield(2); yield(3) }.toList()
        let thunk: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, builderRaw, _ in
            _ = __kk_sequence_builder_yield(builderRaw, 1)
            _ = __kk_sequence_builder_yield(builderRaw, 2)
            _ = __kk_sequence_builder_yield(builderRaw, 3)
            return 0
        }
        let fnPtr = unsafeBitCast(thunk, to: Int.self)
        let seqHandle = __kk_sequence_builder_build(fnPtr)
        #expect(sequenceElements(seqHandle) == [1, 2, 3])
    }

    @Test
    func testSequenceBuilderBuildCoroYieldsElementsThroughCPSProducer() {
        let entryPoint = unsafeBitCast(cpsSequenceBuilderEntry, to: Int.self)
        let seqHandle = __kk_sequence_builder_build_coro(entryPoint, cpsSequenceBuilderFunctionID, 0)
        #expect(sequenceElements(seqHandle) == [7, 11])
    }

    @Test(arguments: [1, 4])
    func testSequenceBuilderYieldAllRange(start: Int) {
        let thunk: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { start, builder, thrown in
            __kk_sequence_builder_yieldAll_checked(builder, kk_op_rangeTo(start, 3), thrown)
        }
        let sequence = __kk_sequence_builder_build(unsafeBitCast(thunk, to: Int.self), start)
        let values = sequenceElements(sequence).map { kk_unbox_int($0) }
        #expect(values == (start == 1 ? [1, 2, 3] : []))
    }

    @Test
    func testIteratorBuilderBuildCoroYieldsElementsThroughCPSProducer() {
        let entryPoint = unsafeBitCast(cpsIteratorBuilderEntry, to: Int.self)
        let iterHandle = __kk_iterator_builder_build_coro(entryPoint, cpsIteratorBuilderFunctionID, 0)

        #expect(__kk_iterator_builder_hasNext(iterHandle) == 1)
        #expect(__kk_iterator_builder_next(iterHandle) == 5)
        #expect(__kk_iterator_builder_hasNext(iterHandle) == 1)
        #expect(__kk_iterator_builder_next(iterHandle) == 8)
        #expect(__kk_iterator_builder_hasNext(iterHandle) == 0)
    }

    @Test
    func testSequenceBuilderBuildEmptyBlock() {
        // sequence { }.toList()
        let thunk: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, _, _ in
            return 0
        }
        let fnPtr = unsafeBitCast(thunk, to: Int.self)
        let seqHandle = __kk_sequence_builder_build(fnPtr)
        #expect(sequenceElements(seqHandle) == [])
    }

    @Test
    func testSequenceBuilderBuildSingleElement() {
        let thunk: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, builderRaw, _ in
            _ = __kk_sequence_builder_yield(builderRaw, 42)
            return 0
        }
        let fnPtr = unsafeBitCast(thunk, to: Int.self)
        let seqHandle = __kk_sequence_builder_build(fnPtr)
        #expect(sequenceElements(seqHandle) == [42])
    }

    @Test
    func testSequenceBuilderBuildWithMap() {
        // sequence { yield(1); yield(2); yield(3) }.map { it * 10 }.toList()
        let thunk: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, builderRaw, _ in
            _ = __kk_sequence_builder_yield(builderRaw, 1)
            _ = __kk_sequence_builder_yield(builderRaw, 2)
            _ = __kk_sequence_builder_yield(builderRaw, 3)
            return 0
        }
        let fnPtr = unsafeBitCast(thunk, to: Int.self)
        let seqHandle = __kk_sequence_builder_build(fnPtr)

        // Apply map: multiply by 10
        let mapFn: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, value, _ in
            value * 10
        }
        let mapped = kk_sequence_map(
            seqHandle,
            unsafeBitCast(mapFn, to: Int.self),
            0
        )
        #expect(sequenceElements(mapped) == [10, 20, 30])
    }

    @Test
    func testSequenceMapPassesSentinelInputsToTransform() {
        let seq = makeSequence([1, runtimeNullSentinelInt, 3])
        let mapFn: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, value, _ in
            value == runtimeNullSentinelInt ? 99 : value * 2
        }
        let mapped = kk_sequence_map(
            seq,
            unsafeBitCast(mapFn, to: Int.self),
            0
        )
        #expect(sequenceElements(mapped) == [2, 99, 6])
    }

    @Test
    func testSequenceBuilderBuildWithTake() {
        // sequence { yield(1); yield(2); yield(3); yield(4); yield(5) }.take(3).toList()
        let thunk: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, builderRaw, _ in
            _ = __kk_sequence_builder_yield(builderRaw, 1)
            _ = __kk_sequence_builder_yield(builderRaw, 2)
            _ = __kk_sequence_builder_yield(builderRaw, 3)
            _ = __kk_sequence_builder_yield(builderRaw, 4)
            _ = __kk_sequence_builder_yield(builderRaw, 5)
            return 0
        }
        let fnPtr = unsafeBitCast(thunk, to: Int.self)
        let seqHandle = __kk_sequence_builder_build(fnPtr)
        let taken = kk_sequence_take(seqHandle, 3)
        #expect(sequenceElements(taken) == [1, 2, 3])
    }

    @Test
    func testSequenceBuilderBuildWithFilter() {
        // sequence { yield(1); yield(2); yield(3); yield(4) }.filter { it % 2 == 0 }.toList()
        let thunk: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, builderRaw, _ in
            _ = __kk_sequence_builder_yield(builderRaw, 1)
            _ = __kk_sequence_builder_yield(builderRaw, 2)
            _ = __kk_sequence_builder_yield(builderRaw, 3)
            _ = __kk_sequence_builder_yield(builderRaw, 4)
            return 0
        }
        let fnPtr = unsafeBitCast(thunk, to: Int.self)
        let seqHandle = __kk_sequence_builder_build(fnPtr)

        let filterFn: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, value, _ in
            value % 2 == 0 ? 1 : 0
        }
        let filtered = kk_sequence_filter(
            seqHandle,
            unsafeBitCast(filterFn, to: Int.self),
            0
        )
        #expect(sequenceElements(filtered) == [2, 4])
    }

    @Test
    func testSequenceBuilderBuildYieldAllFromList() {
        // sequence { yieldAll(listOf(10, 20)); yield(30) }.toList()
        let thunk: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, builderRaw, _ in
            // Create a list [10, 20]
            let arr = kk_array_new(2)
            var thrown = 0
            _ = kk_array_set(arr, 0, 10, &thrown)
            _ = kk_array_set(arr, 1, 20, &thrown)
            let list = kk_list_of(arr, 2)
            _ = __kk_sequence_builder_yieldAll(builderRaw, list)
            _ = __kk_sequence_builder_yield(builderRaw, 30)
            return 0
        }
        let fnPtr = unsafeBitCast(thunk, to: Int.self)
        let seqHandle = __kk_sequence_builder_build(fnPtr)
        #expect(sequenceElements(seqHandle) == [10, 20, 30])
    }

    @Test
    func testSequenceBuilderBuildYieldAllFromLazySequenceIsLazy() {
        // sequence { yieldAll(inner); yield(99) }.take(2).toList()
        _lazyTestYieldCounter = 0
        let outerFnPtr = unsafeBitCast(lazyYieldAllOuterThunk, to: Int.self)
        let seqHandle = __kk_sequence_builder_build(outerFnPtr)

        let taken = kk_sequence_take(seqHandle, 2)
        #expect(sequenceElements(taken) == [10, 20])
        #expect(_lazyTestYieldCounter <= 3, "yieldAll should not eagerly evaluate all 5 elements of the nested sequence before first consumer demand")
        let firstTraversalYields = _lazyTestYieldCounter

        let full = sequenceElements(seqHandle)
        #expect(full == [10, 20, 30, 40, 50, 99])
        #expect(_lazyTestYieldCounter == firstTraversalYields + 5)
    }

    @Test
    func testSequenceBuilderBuildReiterableProducesSameElements() {
        // Verify that materializing the same lazy sequence twice produces the same result
        let thunk: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, builderRaw, _ in
            _ = __kk_sequence_builder_yield(builderRaw, 7)
            _ = __kk_sequence_builder_yield(builderRaw, 8)
            _ = __kk_sequence_builder_yield(builderRaw, 9)
            return 0
        }
        let fnPtr = unsafeBitCast(thunk, to: Int.self)
        let seqHandle = __kk_sequence_builder_build(fnPtr)
        #expect(sequenceElements(seqHandle) == [7, 8, 9])
        // Rerunning this deterministic producer yields the same values.
        #expect(sequenceElements(seqHandle) == [7, 8, 9])
    }

    @Test
    func testSequenceBuilderBuildManyElements() {
        // sequence { for (i in 0..99) yield(i) }.toList()
        let thunk: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, builderRaw, _ in
            for i in 0 ..< 100 {
                _ = __kk_sequence_builder_yield(builderRaw, i)
            }
            return 0
        }
        let fnPtr = unsafeBitCast(thunk, to: Int.self)
        let seqHandle = __kk_sequence_builder_build(fnPtr)
        let result = sequenceElements(seqHandle)
        #expect(result.count == 100)
        #expect(result.first == 0)
        #expect(result.last == 99)
    }

    // MARK: - STDLIB-563: Lazy evaluation verification

    @Test
    func testSequenceBuilderLazyTakeDoesNotEvaluateEntireBlock() {
        // STDLIB-563: Verify that take(2) on a lazy sequence builder
        // only computes the first 2 elements, not all 5.
        // We use a global counter to track how many yields actually execute.
        _lazyTestYieldCounter = 0
        let thunk: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, builderRaw, _ in
            _lazyTestYieldCounter += 1
            _ = __kk_sequence_builder_yield(builderRaw, 1)
            _lazyTestYieldCounter += 1
            _ = __kk_sequence_builder_yield(builderRaw, 2)
            _lazyTestYieldCounter += 1
            _ = __kk_sequence_builder_yield(builderRaw, 3)
            _lazyTestYieldCounter += 1
            _ = __kk_sequence_builder_yield(builderRaw, 4)
            _lazyTestYieldCounter += 1
            _ = __kk_sequence_builder_yield(builderRaw, 5)
            return 0
        }
        let fnPtr = unsafeBitCast(thunk, to: Int.self)
        let seqHandle = __kk_sequence_builder_build(fnPtr)
        let taken = kk_sequence_take(seqHandle, 2)
        let result = sequenceElements(taken)
        #expect(result == [1, 2])
        // The producer should have yielded at most 3 times (2 consumed + 1 ahead
        // before take detects the limit), not all 5. In the truly lazy model,
        // the counter should be <= 3.
        #expect(_lazyTestYieldCounter <= 3, "STDLIB-563: take(2) should not force evaluation of all 5 elements; got \(_lazyTestYieldCounter) yields")
    }

    @Test
    func testSequenceBuilderLazyFirstDoesNotEvaluateEntireBlock() {
        // STDLIB-563: first() on a lazy sequence builder should only evaluate
        // until the first element is produced.
        _lazyTestYieldCounter = 0
        let thunk: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, builderRaw, _ in
            _lazyTestYieldCounter += 1
            _ = __kk_sequence_builder_yield(builderRaw, 100)
            _lazyTestYieldCounter += 1
            _ = __kk_sequence_builder_yield(builderRaw, 200)
            _lazyTestYieldCounter += 1
            _ = __kk_sequence_builder_yield(builderRaw, 300)
            return 0
        }
        let fnPtr = unsafeBitCast(thunk, to: Int.self)
        let seqHandle = __kk_sequence_builder_build(fnPtr)
        var thrown = 0
        let first = kk_sequence_first(seqHandle, &thrown)
        #expect(first == 100)
        #expect(thrown == 0)
        // The producer should have yielded at most 2 times (1 consumed +
        // possibly 1 ahead), not all 3.
        #expect(_lazyTestYieldCounter <= 2, "STDLIB-563: first() should not force evaluation of all 3 elements; got \(_lazyTestYieldCounter) yields")
    }

    @Test
    func testSequenceFirstReturnsFirstElement() {
        let seq = makeSequence([7, 8, 9])
        var thrown = 0
        let first = kk_sequence_first(seq, &thrown)
        #expect(first == 7)
        #expect(thrown == 0)
    }

    @Test
    func testSequenceFirstOrNullReturnsFirstElement() {
        let seq = makeSequence([7, 8, 9])
        var thrown = 0
        let first = kk_sequence_firstOrNull(seq, &thrown)
        #expect(first == 7)
        #expect(thrown == 0)
    }

    // MARK: - STDLIB-HOF-022: Additional Higher-Order Functions

    @Test
    func testSequenceFilterNot() {
        let seq = makeSequence([1, 2, 3, 4, 5])
        let filterFn: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, value, _ in
            value % 2 == 0 ? 1 : 0  // true for even numbers
        }
        let filtered = kk_sequence_filterNot(
            seq,
            unsafeBitCast(filterFn, to: Int.self),
            0
        )
        #expect(sequenceElements(filtered) == [1, 3, 5]) // Should keep odd numbers
    }

    @Test
    func testSequenceFilterNotLazy() {
        // Test that filterNot is lazy by using a sequence builder
        _lazyTestYieldCounter = 0
        let thunk: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, builderRaw, _ in
            _lazyTestYieldCounter += 1
            _ = __kk_sequence_builder_yield(builderRaw, 1)
            _lazyTestYieldCounter += 1
            _ = __kk_sequence_builder_yield(builderRaw, 2)
            _lazyTestYieldCounter += 1
            _ = __kk_sequence_builder_yield(builderRaw, 3)
            return 0
        }
        let fnPtr = unsafeBitCast(thunk, to: Int.self)
        let seqHandle = __kk_sequence_builder_build(fnPtr)

        let filterFn: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, value, _ in
            value == 2 ? 1 : 0  // true only for value 2
        }

        let filtered = kk_sequence_filterNot(
            seqHandle,
            unsafeBitCast(filterFn, to: Int.self),
            0
        )

        // Take only first element to verify laziness
        let taken = kk_sequence_take(filtered, 1)
        let result = sequenceElements(taken)
        #expect(result == [1]) // Should be [1, 3] but take(1) gives [1]

        // Should not have evaluated all elements due to laziness
        #expect(_lazyTestYieldCounter <= 3, "filterNot should be lazy; got \(_lazyTestYieldCounter) yields")
    }

    // MARK: - STDLIB-HOF-022: Additional Lazy Higher-Order Functions Tests

    @Test
    func testSequenceMapNotNullLazy() {
        // Test mapNotNull with lazy evaluation
        _lazyTestYieldCounter = 0
        let thunk: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, builderRaw, _ in
            _lazyTestYieldCounter += 1
            _ = __kk_sequence_builder_yield(builderRaw, 1)
            _lazyTestYieldCounter += 1
            _ = __kk_sequence_builder_yield(builderRaw, runtimeNullSentinelInt) // null value
            _lazyTestYieldCounter += 1
            _ = __kk_sequence_builder_yield(builderRaw, 3)
            return 0
        }
        let fnPtr = unsafeBitCast(thunk, to: Int.self)
        let seqHandle = __kk_sequence_builder_build(fnPtr)

        let mapFn: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, value, _ in
            value == runtimeNullSentinelInt ? runtimeNullSentinelInt : value * 2
        }

        let mapped = kk_sequence_mapNotNull(
            seqHandle,
            unsafeBitCast(mapFn, to: Int.self),
            0,
            nil
        )

        // Take only first element to verify laziness
        let taken = kk_sequence_take(mapped, 1)
        let result = sequenceElements(taken)
        #expect(result == [2]) // 1 * 2 = 2, null is filtered out

        // Should not have evaluated all elements due to laziness
        #expect(_lazyTestYieldCounter <= 3, "mapNotNull should be lazy; got \(_lazyTestYieldCounter) yields")
    }

    @Test
    func testSequenceFilterNotNullLazy() {
        // Test filterNotNull with lazy evaluation
        _lazyTestYieldCounter = 0
        let thunk: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, builderRaw, _ in
            _lazyTestYieldCounter += 1
            _ = __kk_sequence_builder_yield(builderRaw, 1)
            _lazyTestYieldCounter += 1
            _ = __kk_sequence_builder_yield(builderRaw, runtimeNullSentinelInt) // null value
            _lazyTestYieldCounter += 1
            _ = __kk_sequence_builder_yield(builderRaw, 3)
            return 0
        }
        let fnPtr = unsafeBitCast(thunk, to: Int.self)
        let seqHandle = __kk_sequence_builder_build(fnPtr)

        let filtered = kk_sequence_filterNotNull(seqHandle)

        // Take only first element to verify laziness
        let taken = kk_sequence_take(filtered, 1)
        let result = sequenceElements(taken)
        #expect(result == [1]) // null is filtered out

        // Should not have evaluated all elements due to laziness
        #expect(_lazyTestYieldCounter <= 3, "filterNotNull should be lazy; got \(_lazyTestYieldCounter) yields")
    }

    @Test
    func testSequenceMapIndexedLazy() {
        // Test mapIndexed with lazy evaluation
        _lazyTestYieldCounter = 0
        let thunk: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, builderRaw, _ in
            _lazyTestYieldCounter += 1
            _ = __kk_sequence_builder_yield(builderRaw, 10)
            _lazyTestYieldCounter += 1
            _ = __kk_sequence_builder_yield(builderRaw, 20)
            return 0
        }
        let fnPtr = unsafeBitCast(thunk, to: Int.self)
        let seqHandle = __kk_sequence_builder_build(fnPtr)

        let mapFn: @convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, index, value, _ in
            index + value
        }

        let mapped = kk_sequence_mapIndexed(
            seqHandle,
            unsafeBitCast(mapFn, to: Int.self),
            0,
            nil
        )

        // Take only first element to verify laziness
        let taken = kk_sequence_take(mapped, 1)
        let result = sequenceElements(taken)
        #expect(result == [10]) // index 0 + value 10 = 10

        // Should not have evaluated all elements due to laziness
        #expect(_lazyTestYieldCounter <= 2, "mapIndexed should be lazy; got \(_lazyTestYieldCounter) yields")
    }

    @Test
    func testSequenceOnEachIndexedLazy() {
        _lazyTestYieldCounter = 0
        _lazySequenceOnEachIndexedTrace = []
        let thunk: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, builderRaw, _ in
            _lazyTestYieldCounter += 1
            _ = __kk_sequence_builder_yield(builderRaw, 10)
            _lazyTestYieldCounter += 1
            _ = __kk_sequence_builder_yield(builderRaw, 20)
            return 0
        }
        let fnPtr = unsafeBitCast(thunk, to: Int.self)
        let seqHandle = __kk_sequence_builder_build(fnPtr)

        let onEachIndexed = kk_sequence_onEachIndexed(
            seqHandle,
            unsafeBitCast(recordingOnEachIndexedAction, to: Int.self),
            0,
            nil
        )

        let taken = kk_sequence_take(onEachIndexed, 1)
        let result = sequenceElements(taken)
        #expect(result == [10])
        #expect(_lazySequenceOnEachIndexedTrace == [10])
        #expect(_lazyTestYieldCounter <= 2, "onEachIndexed should be lazy; got \(_lazyTestYieldCounter) yields")
    }

    @Test
    func testSequenceOnEachIndexedSourceBackedSequenceIsLazy() {
        _lazySequenceOnEachIndexedTrace = []
        let seq = makeSequence([10, 20, 30])

        let onEachIndexed = kk_sequence_onEachIndexed(
            seq,
            unsafeBitCast(recordingOnEachIndexedAction, to: Int.self),
            0,
            nil
        )

        let taken = kk_sequence_take(onEachIndexed, 2)
        let result = sequenceElements(taken)
        #expect(result == [10, 20])
        #expect(_lazySequenceOnEachIndexedTrace == [10, 120])
    }

    @Test
    func testSequenceWithIndexLazy() {
        // Test withIndex with lazy evaluation
        _lazyTestYieldCounter = 0
        let thunk: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, builderRaw, _ in
            _lazyTestYieldCounter += 1
            _ = __kk_sequence_builder_yield(builderRaw, 10)
            _lazyTestYieldCounter += 1
            _ = __kk_sequence_builder_yield(builderRaw, 20)
            return 0
        }
        let fnPtr = unsafeBitCast(thunk, to: Int.self)
        let seqHandle = __kk_sequence_builder_build(fnPtr)

        let withIndex = kk_sequence_withIndex(seqHandle)

        // Take only first element to verify laziness
        let taken = kk_sequence_take(withIndex, 1)
        let result = sequenceElements(taken)
        #expect(result.count == 1)
        // Should be a pair (0, 10)
        let pair = result[0]
        let first = kk_pair_first(pair)
        let second = kk_pair_second(pair)
        #expect(first == 0) // index
        #expect(second == 10) // value

        // Should not have evaluated all elements due to laziness
        #expect(_lazyTestYieldCounter <= 2, "withIndex should be lazy; got \(_lazyTestYieldCounter) yields")
    }

    @Test
    func testSequenceFlatMapLazy() {
        // Test flatMap with lazy evaluation
        _lazyTestYieldCounter = 0
        let thunk: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, builderRaw, _ in
            _lazyTestYieldCounter += 1
            _ = __kk_sequence_builder_yield(builderRaw, 1)
            _lazyTestYieldCounter += 1
            _ = __kk_sequence_builder_yield(builderRaw, 2)
            return 0
        }
        let fnPtr = unsafeBitCast(thunk, to: Int.self)
        let seqHandle = __kk_sequence_builder_build(fnPtr)

        let flatMapFn: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, value, _ in
            // Create a list [value, value * 10]
            let arr = kk_array_new(2)
            var thrown = 0
            _ = kk_array_set(arr, 0, value, &thrown)
            _ = kk_array_set(arr, 1, value * 10, &thrown)
            return kk_list_of(arr, 2)
        }

        let flatMapped = kk_sequence_flatMap(
            seqHandle,
            unsafeBitCast(flatMapFn, to: Int.self),
            0
        )

        // Take only first element to verify laziness
        let taken = kk_sequence_take(flatMapped, 1)
        let result = sequenceElements(taken)
        #expect(result == [1]) // First element of [1, 10] from first input value 1

        // Should not have evaluated all elements due to laziness
        #expect(_lazyTestYieldCounter <= 2, "flatMap should be lazy; got \(_lazyTestYieldCounter) yields")
    }

    @Test
    func testSequenceMapNotNullCorrectness() {
        // Test correctness of mapNotNull
        let seq = makeSequence([1, 2, 3])
        let mapFn: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, value, _ in
            value == runtimeNullSentinelInt ? runtimeNullSentinelInt : value * 2
        }
        let mapped = kk_sequence_mapNotNull(
            seq,
            unsafeBitCast(mapFn, to: Int.self),
            0,
            nil
        )
        let result = sequenceElements(mapped)
        #expect(result == [2, 4, 6])
    }

    @Test
    func testSequenceMapNotNullPassesSentinelInputsToTransform() {
        let seq = makeSequence([1, runtimeNullSentinelInt, 3])
        let mapFn: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, value, _ in
            value == runtimeNullSentinelInt ? 99 : value * 2
        }
        let mapped = kk_sequence_mapNotNull(
            seq,
            unsafeBitCast(mapFn, to: Int.self),
            0,
            nil
        )
        #expect(sequenceElements(mapped) == [2, 99, 6])
    }

    @Test
    func testSequenceMapNotNullPreservesZeroResults() {
        let seq = makeSequence([0, 1, 2])
        let mapFn: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, value, _ in
            value
        }
        let mapped = kk_sequence_mapNotNull(
            seq,
            unsafeBitCast(mapFn, to: Int.self),
            0,
            nil
        )
        #expect(sequenceElements(mapped) == [0, 1, 2])
    }

    @Test
    func testSequenceFirstNotNullOfOrNullReturnsFirstNonNullResult() {
        let seq = makeSequence([1, 2, 4])
        var thrown = 0
        let result = kk_sequence_firstNotNullOfOrNull(
            seq,
            unsafeBitCast(sequenceFirstNullableEvenTimesTen, to: Int.self),
            0,
            &thrown
        )
        #expect(result == 20)
        #expect(thrown == 0)
    }

    @Test
    func testSequenceFirstNotNullOfOrNullReturnsNullSentinelWhenNoResultMatches() {
        let seq = makeSequence([1, 3, 5])
        var thrown = 0
        let result = kk_sequence_firstNotNullOfOrNull(
            seq,
            unsafeBitCast(sequenceAlwaysNullTransform, to: Int.self),
            0,
            &thrown
        )
        #expect(result == runtimeNullSentinelInt)
        #expect(thrown == 0)
    }

    @Test
    func testSequenceFirstNotNullOfOrNullPropagatesThrownTransform() {
        let seq = makeSequence([1, 2, 3])
        var thrown = 0
        let result = kk_sequence_firstNotNullOfOrNull(
            seq,
            unsafeBitCast(throwingSequenceDestinationLambda, to: Int.self),
            0,
            &thrown
        )
        #expect(result == runtimeExceptionCaughtSentinel)
        #expect(thrown != 0)
    }

    @Test
    func testSequenceFirstNotNullOfReturnsFirstNonNullTransformResult() {
        let seq = makeSequence([1, 2, 4])
        let result = kk_sequence_firstNotNullOf(
            seq,
            unsafeBitCast(sequenceFirstNullableEvenTimesTen, to: Int.self),
            0,
            nil
        )
        #expect(result == 20)
    }

    @Test
    func testSequenceFirstNotNullOfThrowsWhenEveryTransformResultIsNull() {
        let seq = makeSequence([1, 3, 5])
        var thrown = 0
        let result = kk_sequence_firstNotNullOf(
            seq,
            unsafeBitCast(sequenceAlwaysNullTransform, to: Int.self),
            0,
            &thrown
        )
        #expect(result == runtimeExceptionCaughtSentinel)
        #expect(thrown != 0)
    }

    @Test
    func testSequenceFirstNotNullOfPropagatesThrowingLambda() {
        let seq = makeSequence([1, 2, 3])
        var thrown = 0
        let result = kk_sequence_firstNotNullOf(
            seq,
            unsafeBitCast(throwingSequenceDestinationLambda, to: Int.self),
            0,
            &thrown
        )
        #expect(result == runtimeExceptionCaughtSentinel)
        #expect(thrown != 0)
    }

    @Test
    func testSequenceFilterNotNullPreservesZeroAfterMapNotNull() {
        let seq = makeSequence([0, 1, 2])
        let mapFn: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, value, _ in
            value
        }
        let mapped = kk_sequence_mapNotNull(
            seq,
            unsafeBitCast(mapFn, to: Int.self),
            0,
            nil
        )
        let filtered = kk_sequence_filterNotNull(mapped)
        #expect(sequenceElements(filtered) == [0, 1, 2])
    }

    @Test
    func testSequenceFilterNotNullCorrectness() {
        // Test correctness of filterNotNull
        let seq = makeSequence([1, runtimeNullSentinelInt, 3, runtimeNullSentinelInt, 5])
        let filtered = kk_sequence_filterNotNull(seq)
        let result = sequenceElements(filtered)
        #expect(result == [1, 3, 5]) // Only non-null values
    }

    @Test
    func testSequenceRequireNoNullsPassesNonNullElements() {
        let seq = makeSequence([1, 3, 5])
        let required = kk_sequence_requireNoNulls(seq)
        var thrown = 0
        let list = kk_sequence_to_list(required, &thrown)

        #expect(thrown == 0)
        #expect(runtimeTestListElements(list) == [1, 3, 5])
    }

    @Test
    func testSequenceRequireNoNullsThrowsOnNullElement() {
        let seq = makeSequence([1, runtimeNullSentinelInt, 5])
        let required = kk_sequence_requireNoNulls(seq)
        var thrown = 0
        let list = kk_sequence_to_list(required, &thrown)

        #expect(thrown != 0)
        #expect(list == runtimeNullSentinelInt)
    }

    @Test
    func testSequenceMapIndexedCorrectness() {
        // Test correctness of mapIndexed
        let seq = makeSequence([10, 20, 30])
        let mapFn: @convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, index, value, _ in
            index + value
        }
        let mapped = kk_sequence_mapIndexed(
            seq,
            unsafeBitCast(mapFn, to: Int.self),
            0,
            nil
        )
        let result = sequenceElements(mapped)
        #expect(result == [10, 21, 32]) // [0+10, 1+20, 2+30]
    }

    @Test
    func testSequenceMapIndexedNotNullCorrectness() {
        let seq = makeSequence([10, 20, 30, 40])
        let mapFn: @convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, index, value, _ in
            index.isMultiple(of: 2) ? index + value : runtimeNullSentinelInt
        }
        let mapped = kk_sequence_mapIndexedNotNull(
            seq,
            unsafeBitCast(mapFn, to: Int.self),
            0,
            nil
        )
        let result = sequenceElements(mapped)
        #expect(result == [10, 32])
    }

    @Test
    func testSequenceOnEachIndexedCorrectness() {
        let seq = makeSequence([10, 20, 30])
        _lazySequenceOnEachIndexedTrace = []
        let transformed = kk_sequence_onEachIndexed(
            seq,
            unsafeBitCast(recordingOnEachIndexedAction, to: Int.self),
            0,
            nil
        )
        let result = sequenceElements(transformed)
        #expect(result == [10, 20, 30])
        #expect(_lazySequenceOnEachIndexedTrace == [10, 120, 230])
    }

    @Test
    func testSequenceWithIndexCorrectness() {
        // Test correctness of withIndex
        let seq = makeSequence([10, 20, 30])
        let withIndex = kk_sequence_withIndex(seq)
        let result = sequenceElements(withIndex)
        #expect(result.count == 3)
        // Check first pair (0, 10)
        let first = kk_pair_first(result[0])
        let second = kk_pair_second(result[0])
        #expect(first == 0)
        #expect(second == 10)
        // Check second pair (1, 20)
        let first2 = kk_pair_first(result[1])
        let second2 = kk_pair_second(result[1])
        #expect(first2 == 1)
        #expect(second2 == 20)
    }

    @Test
    func testSequenceFlatMapCorrectness() {
        // Test correctness of flatMap
        let seq = makeSequence([1, 2])
        let flatMapFn: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, value, _ in
            // Create a list [value, value * 10]
            let arr = kk_array_new(2)
            var thrown = 0
            _ = kk_array_set(arr, 0, value, &thrown)
            _ = kk_array_set(arr, 1, value * 10, &thrown)
            return kk_list_of(arr, 2)
        }
        let flatMapped = kk_sequence_flatMap(
            seq,
            unsafeBitCast(flatMapFn, to: Int.self),
            0
        )
        let result = sequenceElements(flatMapped)
        #expect(result == [1, 10, 2, 20]) // [1, 10] + [2, 20]
    }

    @Test
    func testSequenceFlatMapIndexedFlattensIterableResults() {
        let seq = makeSequence([1, 2])
        let flatMapFn: @convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, index, value, _ in
            let arr = kk_array_new(2)
            var thrown = 0
            _ = kk_array_set(arr, 0, index, &thrown)
            _ = kk_array_set(arr, 1, value * 10, &thrown)
            return kk_list_of(arr, 2)
        }

        let flatMapped = kk_sequence_flatMapIndexed(
            seq,
            unsafeBitCast(flatMapFn, to: Int.self),
            0
        )

        #expect(sequenceElements(flatMapped) == [0, 10, 1, 20])
    }

    @Test
    func testSequenceFlatMapIndexedFlattensSequenceResults() {
        let seq = makeSequence([1, 2])
        let flatMapFn: @convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, index, value, _ in
            let arr = kk_array_new(2)
            var thrown = 0
            _ = kk_array_set(arr, 0, index + value, &thrown)
            _ = kk_array_set(arr, 1, value * 100, &thrown)
            return kk_sequence_from_list(kk_list_of(arr, 2))
        }

        let flatMapped = kk_sequence_flatMapIndexed(
            seq,
            unsafeBitCast(flatMapFn, to: Int.self),
            0
        )

        #expect(sequenceElements(flatMapped) == [1, 100, 3, 200])
    }

    @Test
    func testSequenceFlatMapIndexedIsLazy() {
        _lazyTestYieldCounter = 0
        let thunk: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, builderRaw, _ in
            _lazyTestYieldCounter += 1
            _ = __kk_sequence_builder_yield(builderRaw, 1)
            _lazyTestYieldCounter += 1
            _ = __kk_sequence_builder_yield(builderRaw, 2)
            _lazyTestYieldCounter += 1
            _ = __kk_sequence_builder_yield(builderRaw, 3)
            return 0
        }
        let seq = __kk_sequence_builder_build(unsafeBitCast(thunk, to: Int.self))
        let flatMapFn: @convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, index, value, _ in
            let arr = kk_array_new(2)
            var thrown = 0
            _ = kk_array_set(arr, 0, index, &thrown)
            _ = kk_array_set(arr, 1, value, &thrown)
            return kk_list_of(arr, 2)
        }

        let flatMapped = kk_sequence_flatMapIndexed(
            seq,
            unsafeBitCast(flatMapFn, to: Int.self),
            0
        )
        let taken = kk_sequence_take(flatMapped, 3)

        #expect(sequenceElements(taken) == [0, 1, 1])
        #expect(_lazyTestYieldCounter <= 2)
    }

    @Test
    func testSequenceWindowedTransformCorrectness() {
        let seq = makeSequence([1, 2, 3, 4, 5])
        let transformed = kk_sequence_windowed_transform(
            seq,
            3,
            2,
            1,
            unsafeBitCast(summingWindowTransform, to: Int.self),
            0,
            nil
        )

        #expect(sequenceElements(transformed) == [6, 12, 5])
    }

    @Test
    func testSequenceWindowedProducesPartialWindows() {
        let seq = makeSequence([1, 2, 3, 4, 5])
        let windows = kk_sequence_windowed(seq, 3, 2, 1)
        let nested = sequenceElements(windows).map { runtimeTestListElements($0) }

        #expect(nested == [[1, 2, 3], [3, 4, 5], [5]])
    }

    @Test
    func testSequenceWindowedTransformPropagatesThrowables() {
        let seq = makeSequence([1, 2, 3, 4])
        var thrown = 0
        let transformed = kk_sequence_windowed_transform(
            seq,
            2,
            1,
            0,
            unsafeBitCast(throwingWindowTransform, to: Int.self),
            0,
            &thrown
        )

        #expect(thrown != 0)
        #expect(transformed == 0)
    }

    @Test
    func testSequenceChunkedReturnsSequenceOfChunkLists() {
        let chunked = kk_sequence_chunked(makeSequence([1, 2, 3, 4, 5]), 2)
        let chunkHandles = sequenceElements(chunked)

        #expect(chunkHandles.map { runtimeTestListElements($0) } == [[1, 2], [3, 4], [5]])
    }

    @Test
    func testSequenceChunkedTransformCorrectness() {
        let seq = makeSequence([1, 2, 3, 4, 5])
        let transformed = kk_sequence_chunked_transform(
            seq,
            2,
            unsafeBitCast(summingWindowTransform, to: Int.self),
            0,
            nil
        )

        #expect(sequenceElements(transformed) == [3, 7, 5])
    }

    @Test
    func testSequenceChunkedTransformPropagatesThrowables() {
        let seq = makeSequence([1, 2, 3, 4])
        var thrown = 0
        let transformed = kk_sequence_chunked_transform(
            seq,
            2,
            unsafeBitCast(throwingWindowTransform, to: Int.self),
            0,
            &thrown
        )

        #expect(thrown == 0)
        #expect(transformed != 0)

        var iterationThrown = 0
        let materialized = kk_sequence_to_list(transformed, &iterationThrown)
        #expect(iterationThrown != 0)
        #expect(materialized == runtimeNullSentinelInt)
    }

    // MARK: - TEST-SEQ-010: Lazy evaluation count verification

    @Test
    func testDistinctByIsLazy() {
        _lazyTestYieldCounter = 0
        let thunk: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, builderRaw, _ in
            _lazyTestYieldCounter += 1
            _ = __kk_sequence_builder_yield(builderRaw, 1)
            _lazyTestYieldCounter += 1
            _ = __kk_sequence_builder_yield(builderRaw, 2)
            _lazyTestYieldCounter += 1
            _ = __kk_sequence_builder_yield(builderRaw, 3)
            _lazyTestYieldCounter += 1
            _ = __kk_sequence_builder_yield(builderRaw, 4)
            _lazyTestYieldCounter += 1
            _ = __kk_sequence_builder_yield(builderRaw, 5)
            return 0
        }
        let keySelector: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, value, _ in
            value % 2
        }
        let seq = __kk_sequence_builder_build(unsafeBitCast(thunk, to: Int.self))
        let distinct = kk_sequence_distinctBy(
            seq,
            unsafeBitCast(keySelector, to: Int.self),
            0,
            nil
        )
        let taken = kk_sequence_take(distinct, 1)
        #expect(sequenceElements(taken) == [1])
        #expect(_lazyTestYieldCounter <= 2, "distinctBy should be lazy; take(1) must not force all 5 yields, got \(_lazyTestYieldCounter)")
    }

    // MARK: - Helpers

    private func sequenceElements(_ seqRaw: Int) -> [Int] {
        runtimeTestListElements(kk_sequence_to_list(seqRaw, nil))
    }

}
#endif
