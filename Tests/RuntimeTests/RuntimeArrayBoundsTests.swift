#if canImport(Testing)
import Testing
@testable import Runtime

@Suite
struct RuntimeArrayBoundsTests {
    private func makeMutableList(_ elements: [Int]) -> Int {
        let array = kk_array_new(elements.count)
        var thrown = 0
        for (index, element) in elements.enumerated() {
            let setResult = kk_array_set(array, index, element, &thrown)
            #expect(setResult == element)
            #expect(thrown == 0)
        }
        return kk_list_to_mutable_list(kk_list_of(array, elements.count))
    }

    @Test
    func testArrayGetAndSetInBounds() {
        let array = kk_array_new(2)
        #expect(array != 0)

        var outThrown = -1
        #expect(kk_array_set(array, 1, 42, &outThrown) == 42)
        #expect(outThrown == 0)

        outThrown = -1
        #expect(kk_array_get(array, 1, &outThrown) == 42)
        #expect(outThrown == 0)
    }

    /// kk_array_get_inbounds must read a single element, not materialise the
    /// whole backing store per access: it is the hot path for object field
    /// reads, and copying made every read O(size). A quadratic implementation
    /// turns this scan into ~10^10 element copies and never finishes.
    @Test
    func testArrayGetInboundsIsConstantTimePerElement() {
        let count = 100_000
        let array = kk_array_new(count)
        var outThrown = 0
        for index in 0..<count {
            #expect(kk_array_set(array, index, index * 2, &outThrown) == index * 2)
        }

        var sum = 0
        for index in 0..<count {
            sum += kk_array_get_inbounds(array, index)
        }
        #expect(sum == count * (count - 1))
    }

    @Test
    func testArrayOutOfBoundsSetsThrownChannel() {
        let array = kk_array_new(1)
        #expect(array != 0)

        var outThrown = 0
        #expect(kk_array_get(array, 5, &outThrown) == 0)
        #expect(outThrown != 0)
    }

    @Test
    func testMutableListAddAtUsesThrownChannelForBoundsErrors() {
        let list = makeMutableList([10, 20])
        var outThrown = -1

        #expect(kk_mutable_list_add_at(list, 1, 15, &outThrown) == 0)
        #expect(outThrown == 0)
        #expect(runtimeListBox(from: list)?.elements == [10, 15, 20])

        outThrown = -1
        #expect(kk_mutable_list_add_at(list, 99, 30, &outThrown) == 0)
        #expect(outThrown != 0)
        #expect(runtimeListBox(from: list)?.elements == [10, 15, 20])
    }

    @Test
    func testMutableListSetUsesThrownChannelForBoundsErrors() {
        let list = makeMutableList([10, runtimeNullSentinelInt, 30])
        var outThrown = -1

        #expect(kk_mutable_list_set(list, 1, 25, &outThrown) == runtimeNullSentinelInt)
        #expect(outThrown == 0)
        #expect(runtimeListBox(from: list)?.elements == [10, 25, 30])

        outThrown = -1
        #expect(kk_mutable_list_set(list, 99, 40, &outThrown) == 0)
        #expect(outThrown != 0)
        #expect(runtimeListBox(from: list)?.elements == [10, 25, 30])
    }

    @Test
    func testMutableListRemoveFirstOrNullRemovesHeadOrReturnsNull() {
        let list = makeMutableList([10, 20])

        #expect(kk_mutable_list_removeFirstOrNull(list) == 10)
        #expect(runtimeListBox(from: list)?.elements == [20])
        #expect(kk_mutable_list_removeFirstOrNull(list) == 20)
        #expect(runtimeListBox(from: list)?.elements == [])
        #expect(kk_mutable_list_removeFirstOrNull(list) == runtimeNullSentinelInt)
        #expect(runtimeListBox(from: list)?.elements == [])
    }

    @Test
    func testMutableListRemoveLastOrNullRemovesTailOrReturnsNull() {
        let list = makeMutableList([10, 20])

        #expect(kk_mutable_list_removeLastOrNull(list) == 20)
        #expect(runtimeListBox(from: list)?.elements == [10])
        #expect(kk_mutable_list_removeLastOrNull(list) == 10)
        #expect(runtimeListBox(from: list)?.elements == [])
        #expect(kk_mutable_list_removeLastOrNull(list) == runtimeNullSentinelInt)
        #expect(runtimeListBox(from: list)?.elements == [])
    }

    @Test
    func testSharedArrayRuntimePreservesUShortPayloads() {
        let array = kk_array_new(3)
        #expect(array != 0)

        var outThrown = -1
        #expect(kk_array_set(array, 0, 0, &outThrown) == 0)
        #expect(outThrown == 0)

        outThrown = -1
        #expect(kk_array_set(array, 1, 1, &outThrown) == 1)
        #expect(outThrown == 0)

        outThrown = -1
        #expect(kk_array_set(array, 2, 65535, &outThrown) == 65535)
        #expect(outThrown == 0)

        outThrown = -1
        #expect(kk_array_get(array, 0, &outThrown) == 0)
        #expect(outThrown == 0)

        outThrown = -1
        #expect(kk_array_get(array, 1, &outThrown) == 1)
        #expect(outThrown == 0)

        outThrown = -1
        #expect(kk_array_get(array, 2, &outThrown) == 65535)
        #expect(outThrown == 0)
    }
}
#endif
