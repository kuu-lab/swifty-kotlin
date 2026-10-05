@testable import Runtime
import Testing

@Suite(.serialized, .runtimeIsolation(.gcOnly))
struct RuntimeArrayListMutabilityTests {
    @Test
    func queryTracksFreezeWithoutChangingListContents() {
        let list = kk_array_list_of(0, 0)
        var thrown = 0
        _ = kk_mutable_list_add(list, kk_box_int(42), &thrown)
        #expect(thrown == 0)
        #expect(kk_unbox_bool(kk_array_list_is_read_only(list)) == 0)

        let built = __kk_builder_list_freeze(list)
        #expect(kk_unbox_bool(kk_array_list_is_read_only(list)) == 1)
        #expect(kk_unbox_bool(kk_array_list_is_read_only(built)) == 1)
        #expect(kk_list_size(list) == 1)
        #expect(kk_unbox_int(kk_list_get(built, 0, &thrown)) == 42)
        #expect(thrown == 0)
    }

    @Test
    func emptyListStartsMutableAndFreezeIsObservable() {
        let list = kk_array_list_of(0, 0)
        #expect(kk_unbox_bool(kk_array_list_is_read_only(list)) == 0)
        _ = __kk_builder_list_freeze(list)
        #expect(kk_unbox_bool(kk_array_list_is_read_only(list)) == 1)
        #expect(kk_list_size(list) == 0)
    }
}
