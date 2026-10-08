#if canImport(Testing)
import Foundation
@testable import Runtime
import Testing

private let sequenceYieldAllInnerFunctionID = 734_402
private let sequenceYieldAllOuterFunctionID = 734_403
private let sequenceYieldAllTraceLock = NSLock()
nonisolated(unsafe) private var sequenceYieldAllTrace: [String] = []

private func appendSequenceYieldAllTrace(_ event: String) {
    sequenceYieldAllTraceLock.lock()
    defer { sequenceYieldAllTraceLock.unlock() }
    sequenceYieldAllTrace.append(event)
}

private func resetSequenceYieldAllTrace() {
    sequenceYieldAllTraceLock.lock()
    defer { sequenceYieldAllTraceLock.unlock() }
    sequenceYieldAllTrace = []
}

private func readSequenceYieldAllTrace() -> [String] {
    sequenceYieldAllTraceLock.lock()
    defer { sequenceYieldAllTraceLock.unlock() }
    return sequenceYieldAllTrace
}

private let sequenceYieldAllInnerLegacyEntry: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, builder, _ in
    appendSequenceYieldAllTrace("inner:1")
    _ = __kk_sequence_builder_yield(builder, 1)
    appendSequenceYieldAllTrace("inner:2")
    _ = __kk_sequence_builder_yield(builder, 2)
    appendSequenceYieldAllTrace("inner:3")
    _ = __kk_sequence_builder_yield(builder, 3)
    return 0
}

private let sequenceYieldAllInnerCpsEntry: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { continuation, _ in
    let builder = Int(kk_coroutine_launcher_arg_get(continuation, 1))
    switch kk_coroutine_state_enter(continuation, sequenceYieldAllInnerFunctionID) {
    case 0:
        appendSequenceYieldAllTrace("inner:1")
        _ = kk_coroutine_state_set_label(continuation, 1)
        return __kk_sequence_builder_yield(builder, 1)
    case 1:
        appendSequenceYieldAllTrace("inner:2")
        _ = kk_coroutine_state_set_label(continuation, 2)
        return __kk_sequence_builder_yield(builder, 2)
    case 2:
        appendSequenceYieldAllTrace("inner:3")
        _ = kk_coroutine_state_set_label(continuation, 3)
        return __kk_sequence_builder_yield(builder, 3)
    default:
        return kk_coroutine_state_exit(continuation, 0)
    }
}

private let sequenceYieldAllOuterLegacyEntry: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { source, builder, thrown in
    appendSequenceYieldAllTrace("outer:before")
    _ = __kk_sequence_builder_yieldAll_checked(builder, source, thrown)
    guard (thrown?.pointee ?? 0) == 0 else { return 0 }
    appendSequenceYieldAllTrace("outer:after")
    _ = __kk_sequence_builder_yield(builder, 99)
    return 0
}

private let sequenceYieldAllOuterCpsEntry: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { continuation, thrown in
    let source = Int(kk_coroutine_launcher_arg_get(continuation, 0))
    let builder = Int(kk_coroutine_launcher_arg_get(continuation, 1))
    switch kk_coroutine_state_enter(continuation, sequenceYieldAllOuterFunctionID) {
    case 0:
        appendSequenceYieldAllTrace("outer:before")
        _ = kk_coroutine_state_set_label(continuation, 1)
        let result = __kk_sequence_builder_yieldAll_checked(builder, source, thrown)
        if result == Int(bitPattern: kk_coroutine_suspended()) { return result }
        fallthrough
    case 1:
        appendSequenceYieldAllTrace("outer:after")
        _ = kk_coroutine_state_set_label(continuation, 2)
        return __kk_sequence_builder_yield(builder, 99)
    default:
        return kk_coroutine_state_exit(continuation, 0)
    }
}

extension RuntimeSequenceTests {
    @Test(arguments: [false, true], [false, true])
    func sequenceYieldAllPullsNestedBuilderOneElementAtATime(
        outerUsesCPS: Bool,
        innerUsesCPS: Bool
    ) {
        resetSequenceYieldAllTrace()

        let inner = innerUsesCPS
            ? __kk_sequence_builder_build_coro(
                unsafeBitCast(sequenceYieldAllInnerCpsEntry, to: Int.self),
                sequenceYieldAllInnerFunctionID,
                0
            )
            : __kk_sequence_builder_build(
                unsafeBitCast(sequenceYieldAllInnerLegacyEntry, to: Int.self)
            )
        let outer = outerUsesCPS
            ? __kk_sequence_builder_build_coro(
                unsafeBitCast(sequenceYieldAllOuterCpsEntry, to: Int.self),
                sequenceYieldAllOuterFunctionID,
                inner
            )
            : __kk_sequence_builder_build(
                unsafeBitCast(sequenceYieldAllOuterLegacyEntry, to: Int.self),
                inner
            )

        var thrown = 0
        let iterator = kk_sequence_box_iterator(outer, &thrown)
        #expect(thrown == 0)
        #expect(kk_sequence_iterator_next(iterator, &thrown) == 1)
        #expect(readSequenceYieldAllTrace() == ["outer:before", "inner:1"])
        #expect(kk_sequence_iterator_next(iterator, &thrown) == 2)
        #expect(readSequenceYieldAllTrace() == ["outer:before", "inner:1", "inner:2"])
        #expect(kk_sequence_iterator_next(iterator, &thrown) == 3)
        #expect(readSequenceYieldAllTrace() == ["outer:before", "inner:1", "inner:2", "inner:3"])
        #expect(kk_sequence_iterator_next(iterator, &thrown) == 99)
        #expect(readSequenceYieldAllTrace() == ["outer:before", "inner:1", "inner:2", "inner:3", "outer:after"])
        #expect(kk_sequence_iterator_hasNext(iterator, &thrown) == 0)
        #expect(thrown == 0)
    }
}
#endif
