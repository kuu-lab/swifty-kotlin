@testable import Runtime
import Testing

private let finiteSequenceNext: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { count, value, _ in
    value + 1 < count ? value + 1 : runtimeNullSentinelInt
}

private let countingSequenceNext: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { context, value, _ in
    let calls = UnsafeMutablePointer<Int>(bitPattern: context)!
    calls.pointee += 1
    return value + 1
}

private let nullableSequenceNext: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { context, _ in
    let state = UnsafeMutablePointer<Int>(bitPattern: context)!
    let value = state.pointee
    guard value < state[1] else { return runtimeNullSentinelInt }
    state.pointee += 1
    return value
}

extension RuntimeSequenceTests {
    @Test(arguments: [99_999, 100_000, 100_001, 150_000])
    func seededGeneratorTraversesAndMaterializesWithoutTruncation(count: Int) {
        let seq = __kk_sequence_generate(0, unsafeBitCast(finiteSequenceNext, to: Int.self), count)
        var thrown = 0
        #expect(kk_sequence_last(seq, &thrown) == count - 1)
        #expect(thrown == 0)
        #expect(kk_sequence_count(seq, &thrown) == count)
        #expect(thrown == 0)
        let list = kk_sequence_to_list(seq, &thrown)
        #expect(thrown == 0)
        #expect(kk_list_size(list) == count)
        #expect(kk_list_get(list, count - 1) == count - 1)
    }

    @Test(arguments: [99_999, 100_000, 100_001, 150_000])
    func nullableGeneratorTraversesAndMaterializesWithoutTruncation(count: Int) {
        var state = [0, count]
        state.withUnsafeMutableBufferPointer { buffer in
            let context = Int(bitPattern: buffer.baseAddress!)
            let fn = unsafeBitCast(nullableSequenceNext, to: Int.self)
            var thrown = 0
            #expect(kk_sequence_count(__kk_sequence_generate_noarg(fn, context), &thrown) == count)
            #expect(thrown == 0)
            buffer[0] = 0
            let list = kk_sequence_to_list(__kk_sequence_generate_noarg(fn, context), &thrown)
            #expect(thrown == 0)
            #expect(kk_list_size(list) == count)
            #expect(kk_list_get(list, count - 1) == count - 1)
        }
    }

    @Test(arguments: [false, true])
    func generatorIteratorPullsBeyondFormerLimit(nullable: Bool) {
        let count = 150_000
        var state = [0, count]
        state.withUnsafeMutableBufferPointer { buffer in
            let seq = nullable
                ? __kk_sequence_generate_noarg(unsafeBitCast(nullableSequenceNext, to: Int.self), Int(bitPattern: buffer.baseAddress!))
                : __kk_sequence_generate(0, unsafeBitCast(finiteSequenceNext, to: Int.self), count)
            var thrown = 0
            let iterator = kk_sequence_box_iterator(seq, &thrown)
            var seen = 0
            var last = -1
            while kk_sequence_iterator_hasNext(iterator, &thrown) != 0 {
                last = kk_sequence_iterator_next(iterator, &thrown)
                seen += 1
            }
            #expect(thrown == 0)
            #expect(seen == count)
            #expect(last == count - 1)
        }
    }

    @Test(arguments: [0, 1, 150_000])
    func infiniteGeneratorTakeStopsWithoutExtraCalls(count: Int) {
        var calls = 0
        withUnsafeMutablePointer(to: &calls) { pointer in
            let seq = __kk_sequence_generate(0, unsafeBitCast(countingSequenceNext, to: Int.self), Int(bitPattern: pointer))
            var thrown = 0
            let taken = kk_sequence_take(seq, count)
            #expect(kk_sequence_count(taken, &thrown) == count)
            #expect(thrown == 0)
        }
        #expect(calls == max(0, count - 1))
    }

    @Test
    func builderIteratorPullsLazilyBeyondFormerLimit() {
        let builder: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { context, builderRaw, _ in
            let calls = UnsafeMutablePointer<Int>(bitPattern: context)!
            for value in 0 ..< 150_000 {
                calls.pointee += 1
                _ = __kk_sequence_builder_yield(builderRaw, value)
            }
            return 0
        }
        var calls = 0
        withUnsafeMutablePointer(to: &calls) { pointer in
            let seq = __kk_sequence_builder_build(unsafeBitCast(builder, to: Int.self), Int(bitPattern: pointer))
            var thrown = 0
            let iterator = kk_sequence_box_iterator(seq, &thrown)
            #expect(pointer.pointee == 0)
            #expect(kk_sequence_iterator_hasNext(iterator, &thrown) == 1)
            #expect(kk_sequence_iterator_hasNext(iterator, &thrown) == 1)
            #expect(pointer.pointee == 1)
            var seen = 0
            var last = -1
            while kk_sequence_iterator_hasNext(iterator, &thrown) != 0 {
                last = kk_sequence_iterator_next(iterator, &thrown)
                seen += 1
            }
            #expect(thrown == 0)
            #expect(seen == 150_000)
            #expect(last == 149_999)
        }
        #expect(calls == 150_000)
    }

    @Test(arguments: [false, true])
    func generatorMaterializationPropagatesExceptions(nullable: Bool) {
        let seededThrow: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { error, _, thrown in
            thrown?.pointee = error
            return 0
        }
        let nullableThrow: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { error, thrown in
            thrown?.pointee = error
            return 0
        }
        let error = runtimeAllocateIllegalStateException(message: "generator failed")
        let seq = nullable
            ? __kk_sequence_generate_noarg(unsafeBitCast(nullableThrow, to: Int.self), error)
            : __kk_sequence_generate(0, unsafeBitCast(seededThrow, to: Int.self), error)
        var thrown = 0
        _ = kk_sequence_to_list(seq, &thrown)
        #expect(thrown == error)
    }
}
