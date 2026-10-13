@testable import Runtime
import Testing

@Suite(.runtimeIsolation(.gcAndMetadata))
struct RuntimeHashMapSubclassTests {
    @Test(arguments: ["kotlin.collections.HashMap", "kotlin.collections.LinkedHashMap"])
    func subclassUsesPersistentMapStorage(parentName: String) throws {
        let parentID = runtimeStableNominalTypeID(fqName: parentName)
        let childID = runtimeStableNominalTypeID(fqName: "test.KUU1941." + parentName)
        // Metadata isolation clears built-in edges; mirror the hierarchy
        // registered by compiled Kotlin modules for LinkedHashMap.
        if parentID != hashMapRuntimeTypeID {
            runtimeRegisterTypeEdge(childTypeID: parentID, parentTypeID: hashMapRuntimeTypeID)
        }
        runtimeRegisterTypeEdge(childTypeID: childID, parentTypeID: parentID)
        let raw = kk_object_new(1, Int(childID))
        _ = kk_array_set(raw, 0, 42, nil)

        let storage = kk_hash_map_storage(raw)
        let backing = try #require(runtimeMapBox(from: storage))
        #expect(storage != raw)
        #expect(kk_object_type_id(raw) == Int(childID))
        #expect(kk_hash_map_storage(raw) == storage)
        #expect(kk_hash_map_storage(storage) == storage)
        #expect(runtimeMapBox(from: raw) == nil)
        #expect(!backing.sorted)
        #expect(runtimeMapBox(from: storage) === backing)
        var thrown = 0
        #expect(kk_mutable_map_put(storage, 7, 9, &thrown) == runtimeNullSentinelInt)
        #expect(thrown == 0)
        #expect(kk_map_get(storage, 7) == 9)
        #expect(kk_map_size(storage) == 1)
        #expect(kk_mutable_map_put(storage, 7, 11, &thrown) == 9)
        #expect(kk_map_get(storage, 7) == 11)
        #expect(kk_array_get(raw, 0, nil) == 42)

        let separate = kk_object_new(0, Int(childID))
        let separateStorage = kk_hash_map_storage(separate)
        #expect(kk_map_size(separateStorage) == 0)
        #expect(runtimeMapBox(from: separateStorage) !== backing)
        #expect(kk_mutable_map_remove(storage, 7, &thrown) == 11)
        #expect(thrown == 0)
        #expect(kk_map_size(storage) == 0)
    }

    @Test
    func freezeTraversesSubclassFieldsAndMapStorage() throws {
        let childID = runtimeStableNominalTypeID(fqName: "test.KUU1941.FrozenMap")
        runtimeRegisterTypeEdge(childTypeID: childID, parentTypeID: hashMapRuntimeTypeID)
        let raw = kk_object_new(1, Int(childID))
        let field = kk_object_new(0, 0)
        let key = registerRuntimeObject(RuntimeStringBox("key"))
        let value = kk_object_new(0, 0)
        let storage = kk_hash_map_storage(raw)
        _ = kk_array_set(raw, 0, field, nil)
        var thrown = 0
        _ = kk_mutable_map_put(storage, key, value, &thrown)
        _ = kk_mutable_map_put(storage, raw, raw, &thrown)
        #expect(thrown == 0)
        _ = kk_freeze_object(raw)
        for reference in [raw, storage, field, key, value] {
            #expect(kk_is_frozen(reference) == 1)
        }
    }

    @Test
    func customMutableMapDoesNotAcquireHashMapStorage() {
        let childID = runtimeStableNominalTypeID(fqName: "test.KUU1941.CustomMap")
        runtimeRegisterTypeEdge(childTypeID: childID, parentTypeID: mutableMapRuntimeTypeID)
        let raw = kk_object_new(0, Int(childID))
        #expect(runtimeMapBox(from: raw) == nil)
    }
}
