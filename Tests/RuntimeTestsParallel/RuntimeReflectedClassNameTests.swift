@testable import Runtime
import Testing

/// KUU-3963: bound `::class` on stdlib-produced collections/iterators must
/// reflect the JVM implementation class names (`java.util.Arrays.ArrayItr`,
/// `java.util.LinkedHashMap.LinkedKeySet`, JVM-anonymous iterators → null)
/// instead of the erased `List`/`Iterator` interface tags.
@Suite
struct RuntimeReflectedClassNameTests {
    private func kclassSimpleName(ofObjectRaw raw: Int) -> String? {
        let kclass = __kk_kclass_of(raw, 0, 0)
        let nameRaw = __kk_kclass_simple_name(kclass)
        #expect(runtimeReleaseObject(kclass))
        guard nameRaw != runtimeNullSentinelInt else { return nil }
        return extractString(from: UnsafeMutableRawPointer(bitPattern: nameRaw))
    }

    private func kclassQualifiedName(ofObjectRaw raw: Int) -> String? {
        let kclass = __kk_kclass_of(raw, 0, 0)
        let nameRaw = __kk_kclass_qualified_name(kclass)
        #expect(runtimeReleaseObject(kclass))
        guard nameRaw != runtimeNullSentinelInt else { return nil }
        return extractString(from: UnsafeMutableRawPointer(bitPattern: nameRaw))
    }

    private func kclassNames(ofObjectRaw raw: Int) -> (simple: String?, qualified: String?) {
        (kclassSimpleName(ofObjectRaw: raw), kclassQualifiedName(ofObjectRaw: raw))
    }

    private func makeList(count: Int, typeID: Int64) -> Int {
        let elements = (0..<count).map { kk_box_int($0) }
        return registerRuntimeObject(RuntimeListBox(elements: elements), typeID: typeID)
    }

    private func makeSet(count: Int, readOnly: Bool = false, typeID: Int64 = setRuntimeTypeID) -> Int {
        let elements = (0..<count).map { kk_box_int($0) }
        let raw = registerRuntimeObject(RuntimeSetBox(elements: elements), typeID: typeID)
        if readOnly {
            runtimeSetBox(from: raw)?.freeze()
        }
        return raw
    }

    private func makeMap(count: Int, readOnly: Bool = false, typeID: Int64 = mapRuntimeTypeID) -> Int {
        let keys = (0..<count).map { kk_box_int($0) }
        let values = (0..<count).map { kk_box_int($0) }
        let raw = registerRuntimeObject(RuntimeMapBox(keys: keys, values: values), typeID: typeID)
        if readOnly {
            runtimeMapBox(from: raw)?.freeze()
        }
        return raw
    }

    @Test
    func singletonAndArraysBackedListReflectImplClasses() {
        let singleton = makeList(count: 1, typeID: singletonListRuntimeTypeID)
        #expect(kclassNames(ofObjectRaw: singleton)
            == ("SingletonList", "java.util.Collections.SingletonList"))

        let backed = makeList(count: 2, typeID: arraysBackedListRuntimeTypeID)
        #expect(kclassNames(ofObjectRaw: backed)
            == ("ArrayList", "java.util.Arrays.ArrayList"))
    }

    @Test
    func setAndMapReflectImplClassesByCount() {
        // KUU-3962: `Collections$Singleton*` only applies to the unmodifiable
        // singletons; the same element count under a mutable backing is a
        // `LinkedHash*` like the JVM (`setOf(1, 1)` dedup, `mutableSetOf(1)`).
        #expect(kclassNames(ofObjectRaw: makeSet(count: 1, readOnly: true))
            == ("SingletonSet", "java.util.Collections.SingletonSet"))
        #expect(kclassNames(ofObjectRaw: makeSet(count: 1))
            == ("LinkedHashSet", "java.util.LinkedHashSet"))
        #expect(kclassNames(ofObjectRaw: makeSet(count: 2))
            == ("LinkedHashSet", "java.util.LinkedHashSet"))
        #expect(kclassNames(ofObjectRaw: makeMap(count: 1, readOnly: true))
            == ("SingletonMap", "java.util.Collections.SingletonMap"))
        #expect(kclassNames(ofObjectRaw: makeMap(count: 1))
            == ("LinkedHashMap", "java.util.LinkedHashMap"))
        #expect(kclassNames(ofObjectRaw: makeMap(count: 2))
            == ("LinkedHashMap", "java.util.LinkedHashMap"))
    }

    @Test
    func listIteratorsReflectIteratorImplClasses() {
        let singleton = makeList(count: 1, typeID: singletonListRuntimeTypeID)
        // `Collections$SingletonList.iterator()` is anonymous on the JVM.
        #expect(kclassNames(ofObjectRaw: kk_list_iterator(singleton)) == (nil, nil))
        // ...but its `listIterator()` inherits `AbstractList$ListItr`.
        #expect(kclassNames(ofObjectRaw: kk_list_listIterator(singleton))
            == ("ListItr", "java.util.AbstractList.ListItr"))

        let backed = makeList(count: 2, typeID: arraysBackedListRuntimeTypeID)
        #expect(kclassNames(ofObjectRaw: kk_list_iterator(backed))
            == ("ArrayItr", "java.util.Arrays.ArrayItr"))
        #expect(kclassNames(ofObjectRaw: kk_list_listIterator(backed))
            == ("ListItr", "java.util.AbstractList.ListItr"))
        #expect(kclassNames(ofObjectRaw: kk_list_iterator_at(backed, 1, nil))
            == ("ListItr", "java.util.AbstractList.ListItr"))
    }

    @Test
    func mutableListIteratorsReflectArrayListItrClasses() {
        let arrayList = makeList(count: 2, typeID: arrayListRuntimeTypeID)
        #expect(kclassNames(ofObjectRaw: kk_list_iterator(arrayList))
            == ("Itr", "java.util.ArrayList.Itr"))
        #expect(kclassNames(ofObjectRaw: kk_mutable_list_listIterator(arrayList))
            == ("ListItr", "java.util.ArrayList.ListItr"))
    }

    @Test
    func setIteratorsFollowBackingMapImplClasses() {
        // Read-only `setOf` singletons iterate with an anonymous
        // `Collections` iterator; mutable one-element and larger sets use
        // LinkedHashMap's (KUU-3962).
        #expect(kclassNames(ofObjectRaw: kk_list_iterator(makeSet(count: 1, readOnly: true))) == (nil, nil))
        #expect(kclassNames(ofObjectRaw: kk_list_iterator(makeSet(count: 1)))
            == ("LinkedKeyIterator", "java.util.LinkedHashMap.LinkedKeyIterator"))
        #expect(kclassNames(ofObjectRaw: kk_list_iterator(makeSet(count: 2)))
            == ("LinkedKeyIterator", "java.util.LinkedHashMap.LinkedKeyIterator"))
        #expect(kclassNames(ofObjectRaw: kk_list_iterator(makeSet(count: 2, typeID: hashSetRuntimeTypeID)))
            == ("KeyIterator", "java.util.HashMap.KeyIterator"))
    }

    @Test
    func mapViewsAndIteratorsReflectLinkedHashMapClasses() {
        let map = makeMap(count: 2)
        #expect(kclassNames(ofObjectRaw: kk_map_keys(map))
            == ("LinkedKeySet", "java.util.LinkedHashMap.LinkedKeySet"))
        #expect(kclassNames(ofObjectRaw: kk_map_values(map))
            == ("LinkedValues", "java.util.LinkedHashMap.LinkedValues"))
        #expect(kclassNames(ofObjectRaw: kk_map_entries(map))
            == ("LinkedEntrySet", "java.util.LinkedHashMap.LinkedEntrySet"))
        #expect(kclassNames(ofObjectRaw: kk_list_iterator(kk_map_keys(map)))
            == ("LinkedKeyIterator", "java.util.LinkedHashMap.LinkedKeyIterator"))
        #expect(kclassNames(ofObjectRaw: kk_list_iterator(kk_map_values(map)))
            == ("LinkedValueIterator", "java.util.LinkedHashMap.LinkedValueIterator"))
        #expect(kclassNames(ofObjectRaw: kk_list_iterator(kk_map_entries(map)))
            == ("LinkedEntryIterator", "java.util.LinkedHashMap.LinkedEntryIterator"))
    }

    @Test
    func singletonMapIteratorIsAnonymous() {
        // Only the unmodifiable `mapOf(k to v)` singleton iterates
        // anonymously; a mutable one-entry map keeps LinkedHashMap's
        // entry iterator (KUU-3962).
        let map = makeMap(count: 1, readOnly: true)
        #expect(kclassNames(ofObjectRaw: kk_list_iterator(kk_map_entries(map))) == (nil, nil))
        let mutableMap = makeMap(count: 1)
        #expect(kclassNames(ofObjectRaw: kk_list_iterator(kk_map_entries(mutableMap)))
            == ("LinkedEntryIterator", "java.util.LinkedHashMap.LinkedEntryIterator"))
    }
}
