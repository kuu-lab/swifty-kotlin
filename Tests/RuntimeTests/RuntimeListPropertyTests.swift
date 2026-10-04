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
    func testListFirstOrNullReturnsHeadOrNullSentinel() {
        #expect(kk_list_firstOrNull(makeList([10, 20])) == 10)
        #expect(kk_list_firstOrNull(makeList([])) == runtimeNullSentinelInt)
    }
}
#endif
