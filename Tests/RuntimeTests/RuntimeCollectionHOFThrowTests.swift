#if canImport(Testing)
import Foundation
import Testing
@testable import Runtime

private let exceptionID = 12345
private let closeExceptionMessage = "close failure"

private final class CloseableTestState: @unchecked Sendable {
    private let lock = NSLock()
    private var closeCallCount = 0
    private var closeThrowableHandle = 0

    func reset() {
        lock.lock()
        closeCallCount = 0
        closeThrowableHandle = 0
        lock.unlock()
    }

    func configureCloseThrowable(_ handle: Int) {
        lock.lock()
        closeThrowableHandle = handle
        lock.unlock()
    }

    func recordCloseCall() -> Int {
        lock.lock()
        defer { lock.unlock() }
        closeCallCount += 1
        return closeThrowableHandle
    }

    func closeCallCountSnapshot() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return closeCallCount
    }
}

private let closeableTestState = CloseableTestState()

private let lambdaThatThrows: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, _, outThrown in
    outThrown?.pointee = exceptionID
    return 0
}

private let lambdaThatThrows2: @convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, _, _, outThrown in
    outThrown?.pointee = exceptionID
    return 0
}

private let throwingGroupByParity: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, value, _ in
    value % 2
}

private let blockThrowableMessage = "block failure"

private let closeableBlockThrows: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, _, outThrown in
    outThrown?.pointee = runtimeAllocateThrowable(message: blockThrowableMessage)
    return 0
}

private let closeableBlockReturnsValue: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, _, _ in
    77
}

private let closeableCloseThunk: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { _, outThrown in
    let closeThrowable = closeableTestState.recordCloseCall()
    if closeThrowable != 0 {
        outThrown?.pointee = closeThrowable
    }
    return 0
}

private func withCloseableResource(_ body: (Int) -> Void) {
    let typeName = Array("RuntimeTests.CloseableResource\0".utf8).map(CChar.init)
    let fieldOffsets = [UInt32(0)]
    var closeFnRaw = UnsafeRawPointer(bitPattern: unsafeBitCast(closeableCloseThunk, to: Int.self))!

    typeName.withUnsafeBufferPointer { nameBuffer in
        fieldOffsets.withUnsafeBufferPointer { offsetBuffer in
            withUnsafePointer(to: &closeFnRaw) { vtablePointer in
                var typeInfo = KTypeInfo(
                    fqName: nameBuffer.baseAddress!,
                    instanceSize: 0,
                    fieldCount: 0,
                    fieldOffsets: offsetBuffer.baseAddress!,
                    vtableSize: 1,
                    vtable: vtablePointer,
                    itable: nil,
                    gcDescriptor: nil
                )
                withUnsafePointer(to: &typeInfo) { typeInfoPtr in
                    let object = kk_alloc(UInt32(MemoryLayout<KKObjHeader>.size), UnsafeRawPointer(typeInfoPtr))
                    body(Int(bitPattern: object))
                }
            }
        }
    }
}

private func throwableBox(from handle: Int) -> RuntimeThrowableBox? {
    guard handle != 0,
          handle != runtimeNullSentinelInt,
          let ptr = UnsafeMutableRawPointer(bitPattern: handle)
    else {
        return nil
    }
    return tryCast(ptr, to: RuntimeThrowableBox.self)
}

private func makeList(_ elements: [Int]) -> Int {
    let array = kk_array_new(elements.count)
    var thrown = 0
    for (index, element) in elements.enumerated() {
        _ = kk_array_set(array, index, element, &thrown)
        #expect(thrown == 0)
    }
    return kk_list_of(array, elements.count)
}

private let groupingByParity: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, value, _ in
    value % 2
}

private let groupingByThrowingLambda: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, _, outThrown in
    outThrown?.pointee = exceptionID
    return 0
}

private let groupingReduceToThrowingLambda: @convention(c) (Int, Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, _, _, _, outThrown in
    outThrown?.pointee = exceptionID
    return 0
}

private let groupingInitialValueSelectorThrowingLambda: @convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, _, _, outThrown in
    outThrown?.pointee = exceptionID
    return 0
}

private let groupingFoldOperationThrowingLambda: @convention(c) (Int, Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, _, _, _, outThrown in
    outThrown?.pointee = exceptionID
    return 0
}

private let groupingAggregateThrowingLambda: @convention(c) (Int, Int, Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, _, _, _, _, outThrown in
    outThrown?.pointee = exceptionID
    return 0
}

@Suite(.serialized)
struct RuntimeCollectionHOFThrowTests {
    init() {
        closeableTestState.reset()
    }

    @Test
    func testListMapThrows() {
        let array = kk_array_new(3)
        var thrown = 0
        _ = kk_array_set(array, 0, 1, &thrown)
        _ = kk_array_set(array, 1, 2, &thrown)
        _ = kk_array_set(array, 2, 3, &thrown)
        let listWithData = kk_list_of(array, 3)

        var outThrown = 0
        let result = kk_list_map(listWithData, unsafeBitCast(lambdaThatThrows, to: Int.self), 0, &outThrown)

        #expect(outThrown == exceptionID)
        #expect(result == runtimeExceptionCaughtSentinel)
    }

    @Test
    func testListForEachThrows() {
        let array = kk_array_new(1)
        var thrown = 0
        _ = kk_array_set(array, 0, 1, &thrown)
        let list = kk_list_of(array, 1)

        var outThrown = 0
        let result = kk_list_forEach(list, unsafeBitCast(lambdaThatThrows, to: Int.self), 0, &outThrown)

        #expect(outThrown == exceptionID)
        #expect(result == runtimeExceptionCaughtSentinel)
    }

    @Test
    func testArrayMapThrows() {
        let array = kk_array_new(1)
        var thrown = 0
        _ = kk_array_set(array, 0, 1, &thrown)

        var outThrown = 0
        let result = kk_array_map(array, unsafeBitCast(lambdaThatThrows, to: Int.self), 0, &outThrown)

        #expect(outThrown == exceptionID)
        #expect(result == runtimeExceptionCaughtSentinel)
    }

    @Test
    func testMapForEachThrows() {
        let map = kk_map_of(kk_array_new(0), kk_array_new(0), 0)
        _ = kk_mutable_map_put(map, 1, 10)

        var outThrown = 0
        let result = kk_map_forEach(map, unsafeBitCast(lambdaThatThrows, to: Int.self), 0, &outThrown)

        #expect(outThrown == exceptionID)
        #expect(result == runtimeExceptionCaughtSentinel)
    }

    @Test
    func testListReduceEmptyThrows() {
        let list = kk_list_of(kk_array_new(0), 0)
        var outThrown = 0
        let result = kk_list_reduce(list, 0, 0, &outThrown)

        #expect(outThrown != 0)
        #expect(result == runtimeExceptionCaughtSentinel)
    }

    @Test
    func testListFirstEmptyThrows() {
        let list = kk_list_of(kk_array_new(0), 0)
        var outThrown = 0
        let result = kk_list_first(list, 0, 0, &outThrown)

        #expect(outThrown != 0)
        #expect(result == runtimeExceptionCaughtSentinel)
    }

    @Test
    func testListLastEmptyThrows() {
        let list = kk_list_of(kk_array_new(0), 0)
        var outThrown = 0
        let result = kk_list_last(list, 0, 0, &outThrown)

        #expect(outThrown != 0)
        #expect(result == runtimeExceptionCaughtSentinel)
    }

    @Test
    func testListSingleEmptyThrows() {
        let list = kk_list_of(kk_array_new(0), 0)
        var outThrown = 0
        let result = kk_list_single(list, &outThrown)

        #expect(outThrown != 0)
        #expect(result == 0)
    }

    @Test
    func testListSingleMultipleElementsThrows() {
        let list = makeList([1, 2])
        var outThrown = 0
        let result = kk_list_single(list, &outThrown)

        #expect(outThrown != 0)
        #expect(result == 0)
    }

    @Test
    func testListReduceOrNullEmptyDoesNotThrow() {
        let list = kk_list_of(kk_array_new(0), 0)
        var outThrown = 0
        let result = kk_list_reduceOrNull(list, 0, 0, &outThrown)

        #expect(outThrown == 0)
        #expect(result == runtimeNullSentinelInt)
    }

    @Test
    func testListScanReduceEmptyDoesNotThrow() {
        let list = kk_list_of(kk_array_new(0), 0)
        var outThrown = 0
        let result = kk_list_scanReduce(list, 0, 0, &outThrown)

        #expect(outThrown == 0)
        #expect(runtimeListBox(from: result)?.elements ?? [] == [])
    }

    @Test
    func testListRunningReduceEmptyDoesNotThrow() {
        let list = kk_list_of(kk_array_new(0), 0)
        var outThrown = 0
        let result = kk_list_runningReduce(list, 0, 0, &outThrown)

        #expect(outThrown == 0)
        #expect(runtimeListBox(from: result)?.elements ?? [] == [])
    }

    @Test
    func testListFoldThrows() {
        let array = kk_array_new(1)
        var thrown = 0
        _ = kk_array_set(array, 0, 1, &thrown)
        let list = kk_list_of(array, 1)

        var outThrown = 0
        let result = kk_list_fold(list, 0, unsafeBitCast(lambdaThatThrows2, to: Int.self), 0, &outThrown)

        #expect(outThrown == exceptionID)
        #expect(result == runtimeExceptionCaughtSentinel)
    }

    @Test
    func testUseSuppressesCloseThrowableWhenBlockThrows() {
        let closeThrowable = runtimeAllocateThrowable(message: closeExceptionMessage)
        closeableTestState.configureCloseThrowable(closeThrowable)

        withCloseableResource { resource in
            var outThrown = 0
            let result = kk_use(resource, unsafeBitCast(closeableBlockThrows, to: Int.self), 0, &outThrown)

            #expect(result == runtimeExceptionCaughtSentinel)
            #expect(closeableTestState.closeCallCountSnapshot() == 1)

            guard let blockThrowable = throwableBox(from: outThrown) else {
                Issue.record("Expected block throwable")
                return
            }
            #expect(blockThrowable.message == blockThrowableMessage)
            #expect(blockThrowable.suppressed == [closeThrowable])

            let suppressed = kk_throwable_getSuppressed(outThrown)
            #expect(kk_array_size(suppressed) == 1)
            var thrown = 0
            #expect(kk_array_get(suppressed, 0, &thrown) == closeThrowable)
            #expect(thrown == 0)
        }
    }

    @Test
    func testUsePropagatesCloseThrowableWhenBlockSucceeds() {
        let closeThrowable = runtimeAllocateThrowable(message: closeExceptionMessage)
        closeableTestState.configureCloseThrowable(closeThrowable)

        withCloseableResource { resource in
            var outThrown = 0
            let result = kk_use(resource, unsafeBitCast(closeableBlockReturnsValue, to: Int.self), 0, &outThrown)

            #expect(result == runtimeExceptionCaughtSentinel)
            #expect(outThrown == closeThrowable)
            #expect(closeableTestState.closeCallCountSnapshot() == 1)
            guard let closeThrowableBox = throwableBox(from: outThrown) else {
                Issue.record("Expected close throwable")
                return
            }
            #expect(closeThrowableBox.suppressed == [])
        }
    }

    @Test
    func testGroupingByEachCountThrows() {
        let array = kk_array_new(3)
        var thrown = 0
        _ = kk_array_set(array, 0, 1, &thrown)
        _ = kk_array_set(array, 1, 2, &thrown)
        _ = kk_array_set(array, 2, 3, &thrown)
        let list = kk_list_of(array, 3)
        let grouping = kk_list_groupingBy(list, unsafeBitCast(groupingByThrowingLambda, to: Int.self), 0)

        var outThrown = 0
        let result = kk_grouping_eachCount(grouping, &outThrown)

        #expect(outThrown == exceptionID)
        #expect(result == runtimeExceptionCaughtSentinel)
    }

    @Test
    func testGroupingReduceToThrows() {
        let array = kk_array_new(3)
        var thrown = 0
        _ = kk_array_set(array, 0, 1, &thrown)
        _ = kk_array_set(array, 1, 2, &thrown)
        _ = kk_array_set(array, 2, 3, &thrown)
        let list = kk_list_of(array, 3)
        let grouping = kk_list_groupingBy(list, unsafeBitCast(throwingGroupByParity, to: Int.self), 0)
        let dest = registerRuntimeObject(RuntimeMapBox(keys: [], values: []))

        var outThrown = 0
        let result = kk_grouping_reduceTo(grouping, dest, unsafeBitCast(groupingReduceToThrowingLambda, to: Int.self), 0, &outThrown)

        #expect(outThrown == exceptionID)
        #expect(result == runtimeExceptionCaughtSentinel)
    }

    @Test
    func testGroupingFoldInitialValueSelectorThrows() {
        let grouping = kk_list_groupingBy(
            makeList([1, 2]),
            unsafeBitCast(groupingByParity, to: Int.self),
            0
        )

        var outThrown = 0
        let result = kk_grouping_fold_initialValueSelector(
            grouping,
            unsafeBitCast(groupingInitialValueSelectorThrowingLambda, to: Int.self),
            0,
            unsafeBitCast(groupingFoldOperationThrowingLambda, to: Int.self),
            0,
            &outThrown
        )

        #expect(outThrown == exceptionID)
        #expect(result == runtimeExceptionCaughtSentinel)
    }

    @Test
    func testGroupingFoldOperationThrows() {
        let grouping = kk_list_groupingBy(
            makeList([1, 3]),
            unsafeBitCast(groupingByParity, to: Int.self),
            0
        )

        var outThrown = 0
        let result = kk_grouping_fold_initialValueSelector(
            grouping,
            unsafeBitCast(groupingInitialValueSelectorThrowingLambda, to: Int.self),
            0,
            unsafeBitCast(groupingFoldOperationThrowingLambda, to: Int.self),
            0,
            &outThrown
        )

        #expect(outThrown == exceptionID)
        #expect(result == runtimeExceptionCaughtSentinel)
    }

    @Test
    func testGroupingAggregateThrows() {
        let grouping = kk_list_groupingBy(
            makeList([1, 2, 3]),
            unsafeBitCast(groupingByParity, to: Int.self),
            0
        )

        var outThrown = 0
        let result = kk_grouping_aggregate(
            grouping,
            unsafeBitCast(groupingAggregateThrowingLambda, to: Int.self),
            0,
            &outThrown
        )

        #expect(outThrown == exceptionID)
        #expect(result == runtimeExceptionCaughtSentinel)
    }

    @Test
    func testGroupingByEachCountToThrows() {
        let array = kk_array_new(3)
        var thrown = 0
        _ = kk_array_set(array, 0, 1, &thrown)
        _ = kk_array_set(array, 1, 2, &thrown)
        _ = kk_array_set(array, 2, 3, &thrown)
        let list = kk_list_of(array, 3)
        let grouping = kk_list_groupingBy(list, unsafeBitCast(groupingByThrowingLambda, to: Int.self), 0)
        let dest = registerRuntimeObject(RuntimeMapBox(keys: [], values: []))

        var outThrown = 0
        let result = kk_grouping_eachCountTo(grouping, dest, &outThrown)

        #expect(outThrown == exceptionID)
        #expect(result == runtimeExceptionCaughtSentinel)
    }
}
#endif
