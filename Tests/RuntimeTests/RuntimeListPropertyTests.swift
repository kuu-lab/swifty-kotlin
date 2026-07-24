#if canImport(Testing)
@testable import Runtime
import Testing

@Suite(.serialized)
struct RuntimeListPropertyTests {
    private func makeList(_ elements: [Int]) -> Int {
        let arrayRaw = kk_array_new(elements.count)
        var thrown = 0
        for (index, element) in elements.enumerated() {
            _ = kk_array_set(arrayRaw, index, element, &thrown)
            #expect(thrown == 0)
        }
        return kk_list_of(arrayRaw, elements.count)
    }

    @Test
    func testListIndicesReturnsZeroBasedRange() {
        let indices = kk_list_indices(makeList([10, 20, 30]))

        #expect(kk_range_first(indices) == 0)
        #expect(kk_range_last(indices) == 2)
        #expect(!RuntimeSignedRangeHOFKind.isEmpty(runtimeRangeBox(from: indices)!))
    }

    @Test
    func testListIndicesReturnsEmptyRangeForEmptyList() {
        let indices = kk_list_indices(makeList([]))

        #expect(kk_range_first(indices) == 0)
        #expect(kk_range_last(indices) == -1)
        #expect(RuntimeSignedRangeHOFKind.isEmpty(runtimeRangeBox(from: indices)!))
    }

    @Test
    func testListFirstOrNullReturnsHeadOrNullSentinel() {
        #expect(kk_list_firstOrNull(makeList([10, 20])) == 10)
        #expect(kk_list_firstOrNull(makeList([])) == runtimeNullSentinelInt)
    }
}
#endif
