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
