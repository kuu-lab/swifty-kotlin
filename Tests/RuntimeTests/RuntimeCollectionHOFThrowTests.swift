#if canImport(Testing)
import Foundation
import Testing
@testable import Runtime

private let exceptionID = 12345

private let lambdaThatThrows: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, _, outThrown in
    outThrown?.pointee = exceptionID
    return 0
}

private let throwingGroupByParity: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, value, _ in
    value % 2
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

@Suite(.serialized)
struct RuntimeCollectionHOFThrowTests {
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

}
#endif
