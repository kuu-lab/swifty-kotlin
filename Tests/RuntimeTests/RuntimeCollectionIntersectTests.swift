#if canImport(Testing)
@testable import Runtime
import Testing

@Suite
struct RuntimeCollectionIntersectTests {
    @Test
    func testListIntersectReturnsDeduplicatedSetInReceiverOrder() {
        let left = registerRuntimeObject(RuntimeListBox(elements: [1, 2, 2, 3, 4]))
        let right = registerRuntimeObject(RuntimeListBox(elements: [2, 4, 5]))

        let result = kk_list_intersect(left, right)

        #expect(runtimeSetBox(from: result)?.elements == [2, 4])
    }
}
#endif
