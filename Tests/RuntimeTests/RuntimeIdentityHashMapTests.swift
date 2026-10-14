@testable import Runtime
import Testing

@Suite(.runtimeIsolation(.gcAndMetadata))
struct RuntimeIdentityHashMapTests {
    @Test
    func referenceKeysAndLiveViewsDoNotUseStructuralEquality() throws {
        // Equal runtime strings independently pin the native indexing policy;
        // the end-to-end Kotlin fixture uses equal nominal source objects.
        let a = registerRuntimeObject(RuntimeStringBox("key"))
        let b = registerRuntimeObject(RuntimeStringBox("key"))
        let v = registerRuntimeObject(RuntimeStringBox("value"))
        let equalV = registerRuntimeObject(RuntimeStringBox("value"))
        #expect(runtimeValuesEqual(a, b) && a != b)
        let raw = kk_object_new(0, Int(runtimeStableNominalTypeID(fqName: "java.util.IdentityHashMap")))
        _ = kk_identity_hash_map_init(raw)
        let map = try #require(runtimeMapBox(from: raw))
        var thrown = 0
        #expect(kk_mutable_map_put(raw, a, v, &thrown) == runtimeNullSentinelInt)
        #expect(kk_map_get(raw, b) == runtimeNullSentinelInt)
        #expect(kk_mutable_map_put(raw, b, equalV, &thrown) == runtimeNullSentinelInt)
        #expect(map.count == 2 && thrown == 0)
        #expect(kk_mutable_map_put(raw, a, equalV, &thrown) == v)
        #expect(kk_map_get(raw, a) == equalV)
        let keys = try #require(runtimeSetBox(from: kk_map_keys(raw)))
        let values = kk_map_values(raw)
        #expect(keys.contains(rawValue: a) && keys.contains(rawValue: b))
        #expect(kk_op_contains(values, v) == 0)
        #expect(kk_op_contains(values, equalV) == 1)
        #expect(kk_unbox_bool(kk_mutable_collection_remove_throwing(values, v, &thrown)) == 0)
        #expect(keys.remove(rawValue: b) && map.count == 1)
        #expect(kk_unbox_bool(kk_mutable_collection_remove_throwing(values, equalV, &thrown)) == 1)
        #expect(map.isEmpty && keys.isEmpty && thrown == 0)

        let ordinary = RuntimeMapBox(keys: [], values: [])
        ordinary.put(key: a, value: v)
        #expect(ordinary.put(key: b, value: equalV) == v)
        #expect(ordinary.count == 1)
    }
}
