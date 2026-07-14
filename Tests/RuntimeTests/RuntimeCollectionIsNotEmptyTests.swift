#if canImport(Testing)
@testable import Runtime
import Testing

@Suite
struct RuntimeCollectionIsNotEmptyTests {
    @Test
    func testListIsNotEmptyReturnsBoxedBoolean() {
        let nonEmpty = registerRuntimeObject(RuntimeListBox(elements: [1]))
        let empty = registerRuntimeObject(RuntimeListBox(elements: []))

        #expect(kk_unbox_bool(kk_list_is_not_empty(nonEmpty)) == 1)
        #expect(kk_unbox_bool(kk_list_is_not_empty(empty)) == 0)
    }
}
#endif
