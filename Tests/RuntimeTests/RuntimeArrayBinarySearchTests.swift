#if canImport(Testing)
@testable import Runtime
import Testing

@Suite
struct RuntimeArrayBinarySearchTests {
    private func makeArray(_ elements: [Int]) -> Int {
        let array = kk_array_new(elements.count)
        var thrown = -1
        for (index, element) in elements.enumerated() {
            let setResult = kk_array_set(array, index, element, &thrown)
            #expect(setResult == element)
            #expect(thrown == 0)
        }
        return array
    }

    @Test
    func testArrayBinarySearchUsesExplicitRangeBounds() {
        let array = makeArray([1, 3, 4, 7, 9])

        #expect(kk_array_binarySearch(array, 4, 1, 4) == 2)
        #expect(kk_array_binarySearch(array, 1, 1, 4) == -2)
    }

    @Test
    func testULongArrayBinarySearchUsesUnsignedOrdering() {
        let high = Int(bitPattern: UInt(0x8000_0000_0000_0000))
        let array = makeArray([0, 1, high])

        #expect(kk_uLongArray_binarySearch(array, high, 0, 3) == 2)
        #expect(kk_uLongArray_binarySearch(array, 1, 0, 3) == 1)
    }
}
#endif
