@testable import Runtime
import Testing

private let iteratorYieldAllFunctionID = 734_400
private let iteratorYieldAllEntry: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { continuation, thrown in
    let builder = Int(kk_coroutine_launcher_arg_get(continuation, 0))
    let source = Int(kk_coroutine_launcher_arg_get(continuation, 1))
    switch kk_coroutine_state_enter(continuation, iteratorYieldAllFunctionID) {
    case 0:
        _ = kk_coroutine_state_set_label(continuation, 1)
        let result = __kk_sequence_builder_yieldAll_checked(builder, source, thrown)
        if result == Int(bitPattern: kk_coroutine_suspended()) { return result }
        fallthrough
    case 1:
        _ = kk_coroutine_state_set_label(continuation, 2)
        return __kk_sequence_builder_yield(builder, 99)
    default:
        return kk_coroutine_state_exit(continuation, 0)
    }
}

extension RuntimeSequenceTests {
    @Test
    func iteratorYieldAllLegacyResumesAfterDelegate() {
        let producer: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { builder, thrown in
            let source = registerRuntimeObject(RuntimeListBox(elements: [1, 2, 3]))
            _ = __kk_sequence_builder_yieldAll_checked(builder, source, thrown)
            _ = __kk_sequence_builder_yield(builder, 4)
            return 0
        }
        let iterator = __kk_iterator_builder_build(unsafeBitCast(producer, to: Int.self))
        var thrown = 0
        for value in 1...4 {
            #expect(kk_iterator_next(iterator, &thrown) == value)
        }
        #expect(kk_iterator_hasNext(iterator, &thrown) == 0)
        #expect(thrown == 0)
    }

    @Test(arguments: [false, true])
    func iteratorYieldAllCPSResumesAfterEntireDelegate(empty: Bool) {
        let source = registerRuntimeObject(RuntimeListBox(elements: empty ? [] : [1, 2, 3]))
        let iterator = __kk_iterator_builder_build_coro(
            unsafeBitCast(iteratorYieldAllEntry, to: Int.self), iteratorYieldAllFunctionID, source
        )
        var thrown = 0
        for value in (empty ? [] : [1, 2, 3]) + [99] {
            #expect(kk_iterator_hasNext(iterator, &thrown) == 1)
            #expect(kk_iterator_hasNext(iterator, &thrown) == 1)
            #expect(kk_iterator_next(iterator, &thrown) == value)
            #expect(thrown == 0)
        }
        #expect(kk_iterator_hasNext(iterator, &thrown) == 0)
        #expect(kk_iterator_hasNext(iterator, &thrown) == 0)
        #expect(thrown == 0)
    }

    @Test
    func iteratorYieldAllCPSAcceptsRuntimeRange() {
        let source = kk_op_rangeTo(1, 3)
        let iterator = __kk_iterator_builder_build_coro(
            unsafeBitCast(iteratorYieldAllEntry, to: Int.self), iteratorYieldAllFunctionID, source
        )
        var thrown = 0
        for value in 1...3 {
            #expect(kk_unbox_int(kk_iterator_next(iterator, &thrown)) == value)
        }
        #expect(kk_iterator_next(iterator, &thrown) == 99)
        #expect(kk_iterator_hasNext(iterator, &thrown) == 0)
        #expect(thrown == 0)
    }

    @Test
    func iteratorYieldAllCPSKeepsNestedIteratorLazyAndPropagatesFailure() throws {
        let inner: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { builder, thrown in
            _ = __kk_sequence_builder_yield(builder, 7)
            thrown?.pointee = runtimeAllocateIllegalArgumentException(message: "delegate failed")
            return 0
        }
        let source = __kk_iterator_builder_build(unsafeBitCast(inner, to: Int.self))
        let iterator = __kk_iterator_builder_build_coro(
            unsafeBitCast(iteratorYieldAllEntry, to: Int.self), iteratorYieldAllFunctionID, source
        )
        var thrown = 0
        #expect(kk_iterator_next(iterator, &thrown) == 7)
        #expect(thrown == 0)
        #expect(kk_iterator_hasNext(iterator, &thrown) == 0)
        let error = try #require(resolveRuntimeHandle(thrown, as: RuntimeThrowableBox.self))
        #expect(error.message == "delegate failed")
        #expect(kk_iterator_hasNext(iterator, &thrown) == 0)
        let failed = try #require(resolveRuntimeHandle(thrown, as: RuntimeThrowableBox.self))
        #expect(failed.exceptionFQName == "kotlin.IllegalStateException")
    }
}
