#if canImport(Testing)
@testable import Runtime
import Testing

@Suite
struct RuntimeCollectionIsNullOrEmptyTests {
    @Test
    func testExistingIsEmptyHelpersTreatNullHandlesAsEmpty() {
        #expect(kk_unbox_bool(kk_list_is_empty(0)) == 1)
        #expect(kk_unbox_bool(kk_set_is_empty(0)) == 1)
        #expect(kk_unbox_bool(kk_map_is_empty(0)) == 1)
        #expect(kk_unbox_bool(kk_array_is_empty(0)) == 1)
    }
}
#endif
