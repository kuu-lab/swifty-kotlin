#if canImport(Testing)
import Testing
@testable import Runtime

@Suite(.serialized)
struct RuntimeCollectionBuildersKSP950Tests {
    @Test
    func testBuilderCapacityFactoriesReturnFreshReadOnlyCollections() {
        let list = __kk_builder_list_new(4)
        let secondList = __kk_builder_list_new(4)
        #expect(list != secondList)

        _ = kk_mutable_list_add(list, 1, nil)
        _ = __kk_builder_list_freeze(list)
        var listThrown = 0
        _ = kk_mutable_list_add(list, 2, &listThrown)
        #expect(listThrown != 0)
        #expect(kk_list_size(list) == 1)

        let set = __kk_builder_set_new(4)
        _ = kk_mutable_set_add(set, 1, nil)
        _ = __kk_builder_set_freeze(set)
        var setThrown = 0
        _ = kk_mutable_set_add(set, 2, &setThrown)
        #expect(setThrown != 0)
        #expect(kk_collection_size(set) == 1)

        let map = __kk_builder_map_new(4)
        _ = kk_mutable_map_put(map, 1, 10, nil)
        _ = __kk_builder_map_freeze(map)
        var mapThrown = 0
        _ = kk_mutable_map_put(map, 2, 20, &mapThrown)
        #expect(mapThrown != 0)
        #expect(kk_map_size(map) == 1)
    }
}
#endif
