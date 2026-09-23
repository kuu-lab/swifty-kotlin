#if canImport(Testing)
import Testing
@testable import Runtime

@Suite(.serialized, .runtimeIsolation(.gcOnly))
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

        var removeThrown = 0
        _ = kk_mutable_map_remove(map, 1, &removeThrown)
        #expect(removeThrown != 0)
        #expect(kk_map_size(map) == 1)

        var clearThrown = 0
        _ = kk_mutable_map_clear(map, &clearThrown)
        #expect(clearThrown != 0)
        #expect(kk_map_size(map) == 1)

        var setThrownAfterFreeze = 0
        _ = kk_mutable_set_remove(set, 1, &setThrownAfterFreeze)
        #expect(setThrownAfterFreeze != 0)
        #expect(kk_collection_size(set) == 1)

        var setClearThrown = 0
        _ = kk_mutable_set_clear(set, &setClearThrown)
        #expect(setClearThrown != 0)
        #expect(kk_collection_size(set) == 1)
    }

    @Test
    func testMapOfUsesReadOnlyMapTagAndRejectsMutation() {
        let keys = kk_array_new(1)
        let values = kk_array_new(1)
        var thrown = 0
        _ = kk_array_set(keys, 0, 1, &thrown)
        _ = kk_array_set(values, 0, 10, &thrown)
        let map = kk_map_of(keys, values, 1)

        #expect(runtimeObjectTypeID(rawValue: map) == mapRuntimeTypeID)
        #expect(runtimeObjectTypeID(rawValue: map) != mutableMapRuntimeTypeID)

        var putThrown = 0
        _ = kk_mutable_map_put(map, 2, 20, &putThrown)
        #expect(putThrown != 0)
        #expect(kk_map_size(map) == 1)

        var removeThrown = 0
        _ = kk_mutable_map_remove(map, 1, &removeThrown)
        #expect(removeThrown != 0)
        #expect(kk_map_size(map) == 1)

        let empty = kk_emptyMap()
        #expect(runtimeObjectTypeID(rawValue: empty) == mapRuntimeTypeID)
        var emptyClearThrown = 0
        _ = kk_mutable_map_clear(empty, &emptyClearThrown)
        #expect(emptyClearThrown != 0)

        let mutable = kk_linked_hash_map_of(0, 0, 0)
        #expect(runtimeObjectTypeID(rawValue: mutable) == linkedHashMapRuntimeTypeID)
        var mutableThrown = 0
        _ = kk_mutable_map_put(mutable, 1, 10, &mutableThrown)
        #expect(mutableThrown == 0)
        #expect(kk_map_size(mutable) == 1)
    }
}
#endif
