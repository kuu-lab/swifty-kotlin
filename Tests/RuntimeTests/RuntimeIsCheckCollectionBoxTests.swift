import Foundation
@testable import Runtime
import Testing

@Suite(.runtimeIsolation(.gcAndMetadata))
struct RuntimeIsCheckCollectionBoxTests {
    @Test
    func hashSetSubclassesAttachBackingStorage() throws {
        let subclassID = runtimeStableNominalTypeID(fqName: "test.HashSetSubclass")
        runtimeRegisterTypeEdge(childTypeID: subclassID, parentTypeID: hashSetRuntimeTypeID)
        let raw = kk_object_new(0, Int(subclassID))
        let storage = try #require(runtimeSetBox(from: raw))
        #expect(storage.count == 0)
        var thrown = 0
        #expect(kk_mutable_set_add(raw, 7, &thrown) == 1)
        #expect(thrown == 0)
        #expect(kk_set_size(raw) == 1)
        #expect(kk_set_contains(raw, 7) == 1)
        #expect(kk_op_is(raw, token("kotlin.collections.HashSet")) == 1)
        #expect(kk_op_is(raw, token("kotlin.collections.LinkedHashSet")) == 0)
    }

    @Test(arguments: [false, true])
    func mutableMapEntriesDispatchSetValueWithoutChangingReadOnlyGetters(useTypedValues: Bool) throws {
        let map = registerRuntimeObject(RuntimeMapBox(keys: [1], values: [2]))
        let entry = useTypedValues
            ? runtimeMutableMapEntryNew(mapRaw: map, key: RuntimeValue(raw: 1), value: RuntimeValue(raw: 2))
            : runtimeMutableMapEntryNew(mapRaw: map, key: 1, value: 2)
        let mutableEntryID = Int(runtimeStableNominalTypeID(fqName: "kotlin.collections.MutableMap.MutableEntry"))
        let entryID = Int(runtimeStableNominalTypeID(fqName: "kotlin.collections.Map.Entry"))
        #expect(runtimeObjectTypeID(rawValue: entry) == Int64(mutableEntryID))
        #expect(kk_op_is(entry, token("kotlin.collections.MutableMap.MutableEntry")) == 1)
        #expect(kk_op_is(entry, token("kotlin.collections.Map.Entry")) == 1)
        #expect(runtimeMapEntryValues(rawValue: entry)?.key == 1)
        #expect(runtimeMapEntryValues(rawValue: entry)?.value == 2)
        var thrown = 0
        #expect(kk_op_cast(entry, token("kotlin.collections.MutableMap.MutableEntry"), &thrown) == entry)
        #expect(thrown == 0)
        let pointer = kk_itable_lookup_dynamic(entry, mutableEntryID, 0)
        try #require(pointer != 0)
        let setValue = unsafeBitCast(pointer, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
        #expect(setValue(entry, 4, &thrown) == 2)
        #expect(thrown == 0)
        #expect(kk_map_get(map, 1) == 4)
        #expect(setValue(entry, 7, &thrown) == 4)
        #expect(thrown == 0)
        #expect(kk_map_get(map, 1) == 7)
        for (slot, expected) in [(0, 1), (1, 7)] {
            let getterPointer = kk_itable_lookup_dynamic(entry, entryID, slot)
            try #require(getterPointer != 0)
            let getter = unsafeBitCast(getterPointer, to: (@convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int).self)
            #expect(getter(entry, &thrown) == expected)
            #expect(thrown == 0)
        }
        let readonly = runtimeMapEntryNew(key: 1, value: 2)
        #expect(kk_op_is(readonly, token("kotlin.collections.Map.Entry")) == 1)
        #expect(kk_op_is(readonly, token("kotlin.collections.MutableMap.MutableEntry")) == 0)
        #expect(kk_itable_lookup_dynamic(readonly, mutableEntryID, 0) == 0)
        #expect(kk_itable_lookup_dynamic(readonly, entryID, 0) != 0)

        let sourceEntryID = runtimeStableNominalTypeID(fqName: "test.ReadOnlyMapEntry")
        runtimeRegisterTypeEdge(childTypeID: sourceEntryID, parentTypeID: Int64(entryID))
        let sourceReadOnly = kk_object_new(0, Int(sourceEntryID))
        #expect(kk_op_is(sourceReadOnly, token("kotlin.collections.Map.Entry")) == 1)
        #expect(kk_op_is(sourceReadOnly, token("kotlin.collections.MutableMap.MutableEntry")) == 0)
        #expect(kk_itable_lookup_dynamic(sourceReadOnly, mutableEntryID, 0) == 0)
    }

    private func token(_ name: String) -> Int {
        let typeID = runtimeStableNominalTypeID(fqName: name)
        return Int(6 | (typeID << 9))
    }

    private func iteratorMethod(_ raw: Int, slot: Int) throws -> @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int {
        let pointer = kk_itable_lookup_dynamic(raw, Int(runtimeStableNominalTypeID(fqName: "kotlin.collections.Iterator")), slot)
        try #require(pointer != 0)
        return unsafeBitCast(pointer, to: (@convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int).self)
    }

    @Test
    func erasedIteratorBoxesHaveIdentityAndCallableTables() throws {
        let map = registerRuntimeObject(RuntimeMapBox(keys: [1], values: [2]))
        let boxes: [AnyObject] = [
            RuntimeListIteratorBox(elements: [7]),
            RuntimeMapIteratorBox(mapRaw: map, keys: [1]),
            RuntimeMutableMapIteratorBox(mapRaw: map, keys: [1], keyValues: [RuntimeValue(raw: 1)]),
            RuntimeSequenceIteratorBox(seq: RuntimeSequenceBox(steps: [.source(elements: [7])])),
            RuntimeIndexingIteratorBox(values: [runtimeValueFromCollectionABI(7)]),
            RuntimeRangeIteratorBox(current: 7, last: 7, step: 1, kind: .intRange),
        ]
        for box in boxes {
            let raw = registerRuntimeObject(box)
            #expect(runtimeObjectTypeID(rawValue: raw) != nil)
            #expect(kk_op_is(raw, token("kotlin.collections.Iterator")) == 1)
            #expect(kk_op_is(raw, token("kotlin.collections.Iterable")) == 0)
            #expect(kk_op_is(raw, token("kotlin.collections.List")) == 0)
            #expect(kk_op_is(raw, token("kotlin.sequences.Sequence")) == 0)
            var thrown = 0
            let hasNext = try iteratorMethod(raw, slot: 0)
            let next = try iteratorMethod(raw, slot: 1)
            #expect(hasNext(raw, &thrown) == 1)
            #expect(thrown == 0)
            _ = next(raw, &thrown)
            #expect(thrown == 0)
            #expect(hasNext(raw, &thrown) == 0)
            _ = next(raw, &thrown)
            #expect(thrown != 0)
        }
    }

    @Test
    func factoryIteratorCastsUseRegisteredIdentity() {
        let list = registerRuntimeObject(RuntimeListBox(elements: [1, 2, 3]))
        let raw = kk_list_iterator(list)
        let iteratorToken = token("kotlin.collections.Iterator")
        #expect(kk_op_is(raw, iteratorToken) == 1)
        #expect(kk_op_safe_cast(raw, iteratorToken) == raw)
        var thrown = 0
        #expect(kk_op_cast(raw, iteratorToken, &thrown) == raw)
        #expect(thrown == 0)
        let listToken = token("kotlin.collections.List")
        #expect(kk_op_safe_cast(raw, listToken) == runtimeNullSentinelInt)
        _ = kk_op_cast(raw, listToken, &thrown)
        #expect(thrown != 0)
        #expect(kk_op_is(thrown, token("kotlin.ClassCastException")) == 1)
    }

    @Test
    func mutableIdentityIncludesIteratorAndRemoveDispatch() throws {
        let list = registerRuntimeObject(RuntimeListBox(elements: [1, 2]))
        let raw = kk_list_iterator(list)
        #expect(kk_op_is(raw, token("kotlin.collections.MutableIterator")) == 1)
        #expect(kk_op_is(raw, token("kotlin.collections.Iterator")) == 1)
        var thrown = 0
        #expect(kk_iterator_next(raw, &thrown) == 1)
        let removePointer = kk_itable_lookup_dynamic(raw, Int(runtimeStableNominalTypeID(fqName: "kotlin.collections.MutableIterator")), 0)
        try #require(removePointer != 0)
        let remove = unsafeBitCast(removePointer, to: (@convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int).self)
        _ = remove(raw, &thrown)
        #expect(thrown == 0)
        #expect(runtimeListBox(from: list)?.elements == [2])
        let readonly = registerRuntimeObject(RuntimeListIteratorBox(elements: [1]))
        #expect(kk_op_is(readonly, token("kotlin.collections.MutableIterator")) == 0)
    }

    @Test
    func erasedSequenceHasIdentityAndIteratorDispatch() throws {
        let box: AnyObject = RuntimeSequenceBox(steps: [.source(elements: [4])])
        let raw = registerRuntimeObject(box)
        #expect(kk_op_is(raw, token("kotlin.sequences.Sequence")) == 1)
        #expect(kk_op_is(raw, token("kotlin.collections.Iterable")) == 0)
        let pointer = kk_itable_lookup_dynamic(raw, Int(runtimeStableNominalTypeID(fqName: "kotlin.sequences.Sequence")), 0)
        try #require(pointer != 0)
        let iterator = unsafeBitCast(pointer, to: (@convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int).self)
        var thrown = 0
        let iter = iterator(raw, &thrown)
        #expect(thrown == 0)
        #expect(kk_op_is(iter, token("kotlin.collections.Iterator")) == 1)
        #expect(try iteratorMethod(iter, slot: 1)(iter, &thrown) == 4)
    }

    @Test
    func arraysExposeIterableAndSequenceIteratorTables() throws {
        let array = kk_array_new(1)
        var thrown = 0
        _ = kk_array_set(array, 0, 42, &thrown)
        #expect(thrown == 0)

        for interfaceName in ["kotlin.collections.Iterable", "kotlin.sequences.Sequence"] {
            let interfaceID = Int(runtimeStableNominalTypeID(fqName: interfaceName))
            let pointer = kk_itable_lookup_dynamic(array, interfaceID, 0)
            try #require(pointer != 0, "Array must expose (interfaceName).iterator()")
            let iterator = unsafeBitCast(
                pointer,
                to: (@convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int).self
            )
            let rawIterator = iterator(array, &thrown)
            #expect(thrown == 0)
            #expect(kk_iterator_hasNext(rawIterator, &thrown) == 1)
            #expect(kk_iterator_next(rawIterator, &thrown) == 42)
            #expect(kk_iterator_hasNext(rawIterator, &thrown) == 0)
            #expect(thrown == 0)
        }
    }

    @Test
    func indexingIterableHasIdentityAndIteratorDispatch() throws {
        let list = registerRuntimeObject(RuntimeListBox(elements: [9]))
        let raw = registerRuntimeObject(RuntimeIndexingIterableBox(listRaw: list) as AnyObject)
        #expect(kk_op_is(raw, token("kotlin.collections.Iterable")) == 1)
        #expect(kk_op_is(raw, token("kotlin.collections.Collection")) == 0)
        let pointer = kk_itable_lookup_dynamic(raw, Int(runtimeStableNominalTypeID(fqName: "kotlin.collections.Iterable")), 0)
        try #require(pointer != 0)
        let iterator = unsafeBitCast(pointer, to: (@convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int).self)
        var thrown = 0
        let iter = iterator(raw, &thrown)
        #expect(kk_op_is(iter, token("kotlin.collections.Iterator")) == 1)
        #expect(try iteratorMethod(iter, slot: 0)(iter, &thrown) == 1)
        let value = try iteratorMethod(iter, slot: 1)(iter, &thrown)
        // `next()` yields an `IndexedValue` object (index@2, value@3) matching
        // the source-backed data class layout, not a `Pair` box — read the
        // fields like compiled component calls do.
        #expect(kk_op_is(value, token("kotlin.collections.IndexedValue")) == 1)
        #expect(kk_array_get(value, 2, &thrown) == 0) // index
        #expect(kk_array_get(value, 3, &thrown) == 9) // element
        #expect(thrown == 0)
    }

    // KUU-4144: JVM `setOf`/`mapOf` results carry their impl identity under
    // the read-only type — `LinkedHashSet`/`LinkedHashMap` for 2+, frozen
    // `Collections$Singleton*` for 1, shared `Empty*` for 0. The erased
    // `java.util.Set`/`Map` shared by the read-only and mutable interfaces
    // makes `is MutableSet`/`is MutableMap` answer true for every impl except
    // the canonical `Empty*` singletons.
    private func intArray(_ elements: [Int]) -> Int {
        let raw = kk_array_new(elements.count)
        var thrown = 0
        for (index, element) in elements.enumerated() {
            _ = kk_array_set(raw, index, element, &thrown)
        }
        return raw
    }

    @Test
    func readOnlySetOfMatchesJvmImplementationIdentity() throws {
        restoreCollectionHierarchyMetadata()
        var thrown = 0
        let empty = kk_set_of(0, 0)
        #expect(empty == kk_emptySet())
        #expect(kk_op_is(empty, token("kotlin.collections.Set")) == 1)
        #expect(kk_op_is(empty, token("kotlin.collections.MutableSet")) == 0)
        #expect(kk_op_is(empty, token("kotlin.collections.LinkedHashSet")) == 0)

        let singleton = kk_set_of(intArray([1]), 1)
        #expect(kk_op_is(singleton, token("kotlin.collections.Set")) == 1)
        // `Collections$SingletonSet` implements `java.util.Set` — the erased
        // MutableSet — but is not a LinkedHashSet and rejects mutation.
        #expect(kk_op_is(singleton, token("kotlin.collections.MutableSet")) == 1)
        #expect(kk_op_is(singleton, token("kotlin.collections.LinkedHashSet")) == 0)
        #expect(kk_op_is(singleton, token("kotlin.collections.HashSet")) == 0)
        _ = kk_mutable_set_add(singleton, 2, &thrown)
        #expect(thrown != 0)

        thrown = 0
        let multi = kk_set_of(intArray([1, 2]), 2)
        #expect(kk_op_is(multi, token("kotlin.collections.Set")) == 1)
        #expect(kk_op_is(multi, token("kotlin.collections.MutableSet")) == 1)
        #expect(kk_op_is(multi, token("kotlin.collections.LinkedHashSet")) == 1)
        // java.util.LinkedHashSet extends HashSet.
        #expect(kk_op_is(multi, token("kotlin.collections.HashSet")) == 1)
        // The mutable cast succeeds and mutates, matching the JVM.
        #expect(kk_mutable_set_add(multi, 3, &thrown) == 1)
        #expect(thrown == 0)
        #expect(kk_set_size(multi) == 3)
    }

    /// `kk_runtime_reset_metadata` wipes `typeParents`/`objectTypeByPointer`
    /// between isolated cases, but the lazy type-ID initializers that normally
    /// register the collection hierarchy only run once per process. Rebuild
    /// the invariant production has: the `Set`/`Map` impl parent edges plus
    /// the canonical `EmptySet`/`EmptyMap` singleton tags.
    private func restoreCollectionHierarchyMetadata() {
        let fq = { runtimeStableNominalTypeID(fqName: $0) }
        let collection = fq("kotlin.collections.Collection")
        let iterable = fq("kotlin.collections.Iterable")
        let mutableIterable = fq("kotlin.collections.MutableIterable")
        let mutableCollection = fq("kotlin.collections.MutableCollection")
        let mutableSet = fq("kotlin.collections.MutableSet")
        let edges: [(Int64, Int64)] = [
            (collection, iterable),
            (mutableIterable, iterable),
            (mutableCollection, collection),
            (mutableCollection, mutableIterable),
            (listRuntimeTypeID, collection),
            (mutableListRuntimeTypeID, listRuntimeTypeID),
            (mutableListRuntimeTypeID, mutableCollection),
            (setRuntimeTypeID, collection),
            (mutableSet, mutableCollection),
            (hashSetRuntimeTypeID, mutableSet),
            (hashSetRuntimeTypeID, fq("kotlin.collections.AbstractMutableSet")),
            (hashSetRuntimeTypeID, setRuntimeTypeID),
            (linkedHashSetRuntimeTypeID, hashSetRuntimeTypeID),
            (linkedHashSetRuntimeTypeID, mutableSet),
            (linkedHashSetRuntimeTypeID, setRuntimeTypeID),
            (mutableMapViewSetRuntimeTypeID, mutableSet),
            (mutableMapViewSetRuntimeTypeID, setRuntimeTypeID),
            (mutableMapViewCollectionRuntimeTypeID, mutableCollection),
            (mutableMapRuntimeTypeID, mapRuntimeTypeID),
            (hashMapRuntimeTypeID, mutableMapRuntimeTypeID),
            (linkedHashMapRuntimeTypeID, hashMapRuntimeTypeID),
        ]
        for (child, parent) in edges {
            runtimeRegisterTypeEdge(childTypeID: child, parentTypeID: parent)
        }
        runtimeRegisterObjectType(rawValue: emptySetSingletonRaw, classID: setRuntimeTypeID)
        runtimeRegisterObjectType(rawValue: emptyMapSingletonRaw, classID: mapRuntimeTypeID)
    }

    @Test
    func readOnlyMapOfMatchesJvmImplementationIdentity() throws {
        restoreCollectionHierarchyMetadata()
        var thrown = 0
        let empty = kk_map_of(0, 0, 0)
        #expect(empty == kk_emptyMap())
        #expect(kk_op_is(empty, token("kotlin.collections.Map")) == 1)
        #expect(kk_op_is(empty, token("kotlin.collections.MutableMap")) == 0)
        #expect(kk_op_is(empty, token("kotlin.collections.LinkedHashMap")) == 0)

        let singleton = kk_map_of(intArray([1]), intArray([2]), 1)
        #expect(kk_op_is(singleton, token("kotlin.collections.Map")) == 1)
        // `Collections$SingletonMap` is a `java.util.Map` — the erased
        // MutableMap — but not a LinkedHashMap, and rejects writes.
        #expect(kk_op_is(singleton, token("kotlin.collections.MutableMap")) == 1)
        #expect(kk_op_is(singleton, token("kotlin.collections.LinkedHashMap")) == 0)
        #expect(kk_op_is(singleton, token("kotlin.collections.HashMap")) == 0)
        _ = kk_mutable_map_put(singleton, 3, 4, &thrown)
        #expect(thrown != 0)

        thrown = 0
        let multi = kk_map_of(intArray([1, 3]), intArray([2, 4]), 2)
        #expect(kk_op_is(multi, token("kotlin.collections.Map")) == 1)
        #expect(kk_op_is(multi, token("kotlin.collections.MutableMap")) == 1)
        #expect(kk_op_is(multi, token("kotlin.collections.LinkedHashMap")) == 1)
        // java.util.LinkedHashMap extends HashMap.
        #expect(kk_op_is(multi, token("kotlin.collections.HashMap")) == 1)
        _ = kk_mutable_map_put(multi, 5, 6, &thrown)
        #expect(thrown == 0)
        #expect(kk_map_get(multi, 5) == 6)
    }

    @Test
    func mapViewIdentitiesMatchJvmViewImplementations() throws {
        restoreCollectionHierarchyMetadata()
        let map = kk_map_of(intArray([1, 3]), intArray([2, 4]), 2)
        let keys = kk_map_keys(map)
        let entries = kk_map_entries(map)
        let values = kk_map_values(map)
        // `LinkedHashMap$LinkedKeySet`/`LinkedEntrySet` are mutable Set impls.
        for view in [keys, entries] {
            #expect(kk_op_is(view, token("kotlin.collections.Set")) == 1)
            #expect(kk_op_is(view, token("kotlin.collections.MutableSet")) == 1)
        }
        // `LinkedHashMap$LinkedValues` is an AbstractCollection — mutable,
        // but neither a Set nor a List.
        #expect(kk_op_is(values, token("kotlin.collections.MutableCollection")) == 1)
        #expect(kk_op_is(values, token("kotlin.collections.List")) == 0)
        #expect(kk_op_is(values, token("kotlin.collections.MutableList")) == 0)
        #expect(kk_op_is(values, token("kotlin.collections.Set")) == 0)

        // `Collections$SingletonMap.values` is a `Collections$SingletonSet` —
        // a real Set impl on the JVM, not a List/collection view.
        let singletonMap = kk_map_of(intArray([1]), intArray([2]), 1)
        let singletonValues = kk_map_values(singletonMap)
        #expect(kk_op_is(singletonValues, token("kotlin.collections.Set")) == 1)
        #expect(kk_op_is(singletonValues, token("kotlin.collections.MutableSet")) == 1)
        #expect(kk_op_is(singletonValues, token("kotlin.collections.Collection")) == 1)
        #expect(kk_op_is(singletonValues, token("kotlin.collections.List")) == 0)
        #expect(kk_op_is(singletonValues, token("kotlin.collections.MutableList")) == 0)
        #expect(
            runtimeJavaClassToStringText(__kk_any_javaClass(singletonValues))
                == "class java.util.Collections$SingletonSet"
        )

        // `emptyMap()`'s views share the canonical `EmptySet`/`EmptyList`.
        let emptyMap = kk_emptyMap()
        let emptyKeys = kk_map_keys(emptyMap)
        #expect(kk_op_is(emptyKeys, token("kotlin.collections.Set")) == 1)
        #expect(kk_op_is(emptyKeys, token("kotlin.collections.MutableSet")) == 0)
        let emptyValues = kk_map_values(emptyMap)
        #expect(kk_op_is(emptyValues, token("kotlin.collections.List")) == 1)
        #expect(kk_op_is(emptyValues, token("kotlin.collections.MutableList")) == 0)
        #expect(kk_op_is(emptyValues, token("kotlin.collections.MutableCollection")) == 0)
    }

    @Test
    func emptiedCollectionsKeepJvmImplementationReflection() throws {
        restoreCollectionHierarchyMetadata()
        var thrown = 0
        let set = kk_set_of(intArray([1, 2]), 2)
        _ = kk_mutable_set_remove(set, 1, &thrown)
        _ = kk_mutable_set_remove(set, 2, &thrown)
        #expect(thrown == 0)
        #expect(kk_set_size(set) == 0)
        // Once a LinkedHashSet, always a LinkedHashSet — draining the
        // contents must not flip reflection to EmptySet (KUU-4144).
        #expect(runtimeJavaClassToStringText(__kk_any_javaClass(set)) == "class java.util.LinkedHashSet")
        #expect(kk_op_is(set, token("kotlin.collections.MutableSet")) == 1)

        let map = kk_map_of(intArray([1, 3]), intArray([2, 4]), 2)
        _ = kk_mutable_map_remove(map, 1, &thrown)
        _ = kk_mutable_map_remove(map, 3, &thrown)
        #expect(thrown == 0)
        #expect(runtimeJavaClassToStringText(__kk_any_javaClass(map)) == "class java.util.LinkedHashMap")
        #expect(kk_op_is(map, token("kotlin.collections.MutableMap")) == 1)

        // The canonical singletons still reflect Empty*/Singleton* by raw
        // identity, never by element count.
        #expect(runtimeJavaClassToStringText(__kk_any_javaClass(kk_emptySet())) == "class kotlin.collections.EmptySet")
        #expect(runtimeJavaClassToStringText(__kk_any_javaClass(kk_emptyMap())) == "class kotlin.collections.EmptyMap")
        #expect(runtimeJavaClassToStringText(__kk_any_javaClass(kk_set_of(intArray([9]), 1))) == "class java.util.Collections$SingletonSet")
        #expect(runtimeJavaClassToStringText(__kk_any_javaClass(kk_map_of(intArray([9]), intArray([8]), 1))) == "class java.util.Collections$SingletonMap")
    }

    @Test
    func compatibilitySequenceTableDoesNotChangeListIdentity() {
        let raw = registerRuntimeObject(RuntimeListBox(elements: [1]))
        #expect(kk_op_is(raw, token("kotlin.collections.List")) == 1)
        #expect(kk_op_is(raw, token("kotlin.sequences.Sequence")) == 0)
    }

    @Test
    func erasedCollectionBoxesKeepCollectionIdentity() {
        let list = registerRuntimeObject(RuntimeListBox(elements: [1]) as AnyObject)
        let set = registerRuntimeObject(RuntimeSetBox(elements: [1]) as AnyObject)
        let map = registerRuntimeObject(RuntimeMapBox(keys: [1], values: [2]) as AnyObject)
        #expect(kk_op_is(list, token("kotlin.collections.List")) == 1)
        #expect(kk_op_is(set, token("kotlin.collections.Set")) == 1)
        #expect(kk_op_is(map, token("kotlin.collections.Map")) == 1)
        for raw in [list, set, map] {
            #expect(kk_op_is(raw, token("kotlin.sequences.Sequence")) == 0)
            #expect(kk_op_is(raw, token("kotlin.collections.Iterator")) == 0)
        }
        #expect(kk_op_is(map, token("kotlin.collections.Iterable")) == 0)
    }

    @Test
    func iteratorBuilderHasIdentityAndIteratorDispatch() throws {
        let thunk: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { builderRaw, _ in
            _ = __kk_iterator_builder_yield(builderRaw, 8)
            return 0
        }
        let raw = __kk_iterator_builder_build(unsafeBitCast(thunk, to: Int.self))
        #expect(kk_op_is(raw, token("kotlin.collections.Iterator")) == 1)
        #expect(kk_op_is(raw, token("kotlin.collections.MutableIterator")) == 0)
        var thrown = 0
        let hasNext = try iteratorMethod(raw, slot: 0)
        #expect(hasNext(raw, &thrown) == 1)
        #expect(try iteratorMethod(raw, slot: 1)(raw, &thrown) == 8)
        #expect(hasNext(raw, &thrown) == 0)
        #expect(thrown == 0)
    }

    @Test
    func bufferedLineIteratorHasIdentityAndIteratorDispatch() throws {
        let reader = RuntimeBufferedReaderBox(data: Data("line\n".utf8))
        let raw = registerRuntimeObject(RuntimeBufferedLineIteratorBox(reader: reader) as AnyObject)
        #expect(kk_op_is(raw, token("kotlin.collections.Iterator")) == 1)
        #expect(kk_op_is(raw, token("kotlin.collections.MutableIterator")) == 0)
        var thrown = 0
        let hasNext = try iteratorMethod(raw, slot: 0)
        let next = try iteratorMethod(raw, slot: 1)
        #expect(hasNext(raw, &thrown) == 1)
        #expect(runtimeStringFromRaw(next(raw, &thrown)) == "line")
        #expect(hasNext(raw, &thrown) == 0)
        _ = next(raw, &thrown)
        #expect(thrown != 0)
    }
}
