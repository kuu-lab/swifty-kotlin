@testable import Runtime
import Testing

extension RuntimeSequenceTests {
    @Test(arguments: [false, true])
    func factoryGeneratorRetriesProducerAfterException(seeded: Bool) throws {
        let nullable: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { context, thrown in
            let calls = UnsafeMutablePointer<Int>(bitPattern: context)!
            calls.pointee += 1
            if calls.pointee == 1 {
                thrown?.pointee = runtimeAllocateIllegalStateException(message: "retry")
                return 0
            }
            return calls.pointee == 2 ? 7 : runtimeNullSentinelInt
        }
        let next: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { context, value, thrown in
            let calls = UnsafeMutablePointer<Int>(bitPattern: context)!
            calls.pointee += 1
            if calls.pointee == 1 {
                thrown?.pointee = runtimeAllocateIllegalStateException(message: "retry")
                return 0
            }
            return calls.pointee == 2 ? value + 1 : runtimeNullSentinelInt
        }
        var calls = 0
        try withUnsafeMutablePointer(to: &calls) { pointer in
            let context = Int(bitPattern: pointer)
            let sequence = seeded
                ? __kk_sequence_generate(6, unsafeBitCast(next, to: Int.self), context)
                : __kk_sequence_generate_noarg(unsafeBitCast(nullable, to: Int.self), context)
            var thrown = 0
            let iterator = kk_sequence_box_iterator(sequence, &thrown)
            if seeded { #expect(kk_sequence_iterator_next(iterator, &thrown) == 6) }
            #expect(kk_sequence_iterator_hasNext(iterator, &thrown) == 0)
            let error = try #require(resolveRuntimeHandle(thrown, as: RuntimeThrowableBox.self))
            #expect(error.exceptionFQName == "kotlin.IllegalStateException")
            #expect(kk_sequence_iterator_hasNext(iterator, &thrown) == 1)
            #expect(thrown == 0)
            #expect(kk_sequence_iterator_hasNext(iterator, &thrown) == 1)
            #expect(pointer.pointee == 2)
            #expect(kk_sequence_iterator_next(iterator, &thrown) == 7)
            #expect(kk_sequence_iterator_hasNext(iterator, &thrown) == 0)
            #expect(thrown == 0)
            #expect(pointer.pointee == 3)
        }
    }

    @Test(arguments: [false, true])
    func factoryYieldAllInitialProbeIsCatchableButLaterFailureIsNot(yieldsFirst: Bool) throws {
        let inner: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { _, thrown in
            thrown?.pointee = runtimeAllocateIllegalArgumentException(message: "nested")
            return 0
        }
        let innerAfterYield: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { builder, thrown in
            _ = __kk_iterator_builder_yield(builder, 9)
            thrown?.pointee = runtimeAllocateIllegalArgumentException(message: "nested")
            return 0
        }
        let outer: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { iterator, builder, _ in
            _ = __kk_sequence_builder_yield(builder, 1)
            var nested = 0
            _ = __kk_sequence_builder_yieldAll_checked(builder, iterator, &nested)
            if nested != 0 { _ = __kk_sequence_builder_yield(builder, 2) }
            return 0
        }
        let nested = __kk_iterator_builder_build(unsafeBitCast(yieldsFirst ? innerAfterYield : inner, to: Int.self))
        let sequence = __kk_sequence_builder_build(unsafeBitCast(outer, to: Int.self), nested)
        var thrown = 0
        let iterator = kk_sequence_box_iterator(sequence, &thrown)
        #expect(kk_sequence_iterator_next(iterator, &thrown) == 1)
        #expect(kk_sequence_iterator_next(iterator, &thrown) == (yieldsFirst ? 9 : 2))
        #expect(thrown == 0)
        #expect(kk_sequence_iterator_hasNext(iterator, &thrown) == 0)
        if yieldsFirst {
            let error = try #require(resolveRuntimeHandle(thrown, as: RuntimeThrowableBox.self))
            #expect(error.exceptionFQName == "kotlin.IllegalArgumentException")
            #expect(error.message == "nested")
            #expect(kk_sequence_iterator_hasNext(iterator, &thrown) == 0)
            let failed = try #require(resolveRuntimeHandle(thrown, as: RuntimeThrowableBox.self))
            #expect(failed.exceptionFQName == "kotlin.IllegalStateException")
        } else {
            #expect(thrown == 0)
        }
    }

    @Test(arguments: [0, 1, 3, 4])
    func factoryBuilderChunkedIteratorFlushesPartialChunkOnce(count: Int) {
        let producer: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { count, builder, _ in
            for value in 1..<(count + 1) { _ = __kk_sequence_builder_yield(builder, value) }
            return 0
        }
        let transform: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { context, chunk, _ in
            UnsafeMutablePointer<Int>(bitPattern: context)!.pointee += 1
            return kk_box_int(kk_list_size(chunk))
        }
        var calls = 0
        withUnsafeMutablePointer(to: &calls) { pointer in
            let sequence = __kk_sequence_builder_build(unsafeBitCast(producer, to: Int.self), count)
            var thrown = 0
            let chunks = kk_sequence_chunked_transform(sequence, 2, unsafeBitCast(transform, to: Int.self), Int(bitPattern: pointer), &thrown)
            let iterator = kk_sequence_box_iterator(chunks, &thrown)
            var sizes: [Int] = []
            while kk_sequence_iterator_hasNext(iterator, &thrown) != 0 {
                #expect(kk_sequence_iterator_hasNext(iterator, &thrown) == 1)
                sizes.append(kk_sequence_iterator_next(iterator, &thrown))
            }
            #expect(sizes == Array(repeating: 2, count: count / 2) + (count % 2 == 0 ? [] : [1]))
            #expect(pointer.pointee == sizes.count)
            #expect(kk_sequence_iterator_hasNext(iterator, &thrown) == 0)
            #expect(pointer.pointee == sizes.count)
            #expect(thrown == 0)
        }
    }

    @Test
    func factoryBuilderPartialChunkTransformPropagatesException() throws {
        let producer: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, builder, _ in
            _ = __kk_sequence_builder_yield(builder, 1)
            return 0
        }
        let transform: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, _, thrown in
            thrown?.pointee = runtimeAllocateIllegalArgumentException(message: "partial")
            return 0
        }
        var thrown = 0
        let sequence = __kk_sequence_builder_build(unsafeBitCast(producer, to: Int.self))
        let chunks = kk_sequence_chunked_transform(sequence, 2, unsafeBitCast(transform, to: Int.self), 0, &thrown)
        let iterator = kk_sequence_box_iterator(chunks, &thrown)
        #expect(kk_sequence_iterator_hasNext(iterator, &thrown) == 0)
        let error = try #require(resolveRuntimeHandle(thrown, as: RuntimeThrowableBox.self))
        #expect(error.message == "partial")
    }

    @Test
    func factoryBuilderChunkedTakeDoesNotFlushOrAdvanceAfterLimit() {
        let producer: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { context, builder, _ in
            let calls = UnsafeMutablePointer<Int>(bitPattern: context)!
            for value in 1...3 {
                calls.pointee += 1
                _ = __kk_sequence_builder_yield(builder, value)
            }
            return 0
        }
        let transform: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, chunk, _ in
            kk_box_int(kk_list_size(chunk))
        }
        var calls = 0
        withUnsafeMutablePointer(to: &calls) { pointer in
            let sequence = __kk_sequence_builder_build(unsafeBitCast(producer, to: Int.self), Int(bitPattern: pointer))
            var thrown = 0
            let chunks = kk_sequence_chunked_transform(sequence, 2, unsafeBitCast(transform, to: Int.self), 0, &thrown)
            let limited = kk_sequence_take(chunks, 1)
            let iterator = kk_sequence_box_iterator(limited, &thrown)
            #expect(pointer.pointee == 0)
            #expect(kk_sequence_iterator_next(iterator, &thrown) == 2)
            #expect(pointer.pointee == 2)
            #expect(kk_sequence_iterator_hasNext(iterator, &thrown) == 0)
            #expect(pointer.pointee == 2)
            #expect(thrown == 0)
        }
    }
}
