import Foundation

@_cdecl("__kk_identity_hash_map_init")
public func kk_identity_hash_map_init(_ mapRaw: Int) -> Int {
    guard let objectBox = resolveRuntimeHandle(mapRaw, as: RuntimeObjectBox.self) else { return 0 }
    objectBox.backingMapBox = RuntimeMapBox(keys: [], values: [], usesReferenceEquality: true)
    return 0
}


/// HashMap's inherited source bodies operate on this native storage handle.
/// Keeping it separate from the Kotlin receiver lets interface bridges dispatch
/// to user overrides without re-entering those bridges from the base body.
@_cdecl("__kk_hash_map_storage")
public func kk_hash_map_storage(_ mapRaw: Int) -> Int {
    guard let objectBox = runtimeHashMapObject(from: mapRaw) else {
        return mapRaw
    }
    if objectBox.backingMapRaw != 0 {
        return objectBox.backingMapRaw
    }
    let backing = objectBox.backingMapBox ?? RuntimeMapBox(keys: [], values: [])
    objectBox.backingMapBox = backing
    let storageRaw = registerRuntimeObject(backing, typeID: hashMapRuntimeTypeID)
    objectBox.backingMapRaw = storageRaw
    return storageRaw
}

@_cdecl("__kk_set_of")
public func kk_set_of(_ arrayRaw: Int, _ count: Int) -> Int {
    var elements: [Int] = []
    if count > 0, let array = runtimeArrayBox(from: arrayRaw) {
        elements = Array(array.elements.prefix(count))
    }
    // JVM `setOf` family: 0 elements is the shared immutable `EmptySet`,
    // exactly 1 supplied element is the unmodifiable `Collections.singleton`,
    // and 2+ is a `LinkedHashSet` (mutable under the read-only `Set` type).
    // The singleton keeps the read-only `Set` tag + freeze; the erased-check
    // helper in `kk_op_is` still answers `is MutableSet` true for it, the way
    // `Collections$SingletonSet` does on the JVM. KUU-3962, KUU-4144.
    if count == 0 {
        return emptySetSingletonRaw
    }
    let set = RuntimeSetBox(elements: runtimeDeduplicatePreservingOrder(elements))
    if count == 1 {
        set.freeze()
        return registerRuntimeObject(set)
    }
    return registerRuntimeObject(set, typeID: linkedHashSetRuntimeTypeID)
}

/// HashSet constructor storage. Keep ordinary Set factories on the shared Set
/// identity; HashSet constructors need their own nominal tag for `is` checks.
@_cdecl("__kk_hash_set_of")
public func kk_hash_set_of(_ arrayRaw: Int, _ count: Int) -> Int {
    var elements: [Int] = []
    if count > 0, let array = runtimeArrayBox(from: arrayRaw) {
        elements = Array(array.elements.prefix(count))
    }
    return registerRuntimeObject(
        RuntimeSetBox(elements: runtimeDeduplicatePreservingOrder(elements)),
        typeID: hashSetRuntimeTypeID
    )
}

/// HashSet's capacity is a storage hint. Validate constructor arguments before
/// allocating the same nominally tagged set used by the zero-argument form.
@_cdecl("__kk_hash_set_new_checked")
public func kk_hash_set_new_checked(
    _ capacity: Int,
    _ loadFactorBits: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    // The compiler's runtime ABI transports Float arguments as raw Int words.
    let loadFactor = Float(bitPattern: UInt32(truncatingIfNeeded: loadFactorBits))
    guard capacity >= 0 else {
        runtimeSetThrown(outThrown, runtimeAllocateIllegalArgumentException(message: "Illegal Capacity: \(capacity)"))
        return 0
    }
    guard loadFactor > 0, !loadFactor.isNaN else {
        runtimeSetThrown(outThrown, runtimeAllocateIllegalArgumentException(message: "Illegal Load: \(loadFactor)"))
        return 0
    }
    return kk_hash_set_of(0, 0)
}

/// BUG-254: storage for the mutable set factories (`mutableSetOf`,
/// `linkedSetOf`) and the `LinkedHashSet()` / `LinkedHashSet(capacity)`
/// constructors. `__kk_set_of` stays on the read-only `Set` identity because it
/// is shared with `setOf`, so these callers need their own nominal tag for
/// `is MutableSet<*>` / `is LinkedHashSet<*>` to answer true.
@_cdecl("__kk_linked_hash_set_of")
public func kk_linked_hash_set_of(_ arrayRaw: Int, _ count: Int) -> Int {
    var elements: [Int] = []
    if count > 0, let array = runtimeArrayBox(from: arrayRaw) {
        elements = Array(array.elements.prefix(count))
    }
    return registerRuntimeObject(
        RuntimeSetBox(elements: runtimeDeduplicatePreservingOrder(elements)),
        typeID: linkedHashSetRuntimeTypeID
    )
}

/// `setOfNotNull(*elements)` — the vararg overload. JVM `filterNotNullTo`
/// targets a fresh `LinkedHashSet` for any supplied count, so `is MutableSet`
/// answers true even when filtering leaves zero or one element (KUU-4144).
@_cdecl("__kk_set_of_not_null")
public func kk_set_of_not_null(_ arrayRaw: Int, _ count: Int) -> Int {
    var elements: [Int] = []
    if count > 0, let array = runtimeArrayBox(from: arrayRaw) {
        for element in array.elements.prefix(count) where element != runtimeNullSentinelInt {
            elements.append(element)
        }
    }
    return registerRuntimeObject(
        RuntimeSetBox(elements: runtimeDeduplicatePreservingOrder(elements)),
        typeID: linkedHashSetRuntimeTypeID
    )
}

/// Single-element `setOfNotNull(element)` overload: null maps to the shared
/// `EmptySet`, a non-null element to the unmodifiable `Collections.singleton`
/// identity — the same shape `__kk_set_of` produces for `count == 1`.
/// Keeping the two JVM overloads on separate callees preserves the
/// singleton/empty-vs-LinkedHashSet identity split (KUU-4144).
@_cdecl("__kk_set_of_not_null_single")
public func kk_set_of_not_null_single(_ arrayRaw: Int, _ count: Int) -> Int {
    var elements: [Int] = []
    if count > 0, let array = runtimeArrayBox(from: arrayRaw) {
        for element in array.elements.prefix(count) where element != runtimeNullSentinelInt {
            elements.append(element)
        }
    }
    guard !elements.isEmpty else {
        return emptySetSingletonRaw
    }
    let set = RuntimeSetBox(elements: runtimeDeduplicatePreservingOrder(elements))
    set.freeze()
    return registerRuntimeObject(set)
}

// Kotlin exposes emptySet() as a shared immutable instance.
let emptySetSingletonRaw: Int = {
    let raw = registerRuntimeObject(RuntimeSetBox(elements: []))
    runtimeSetBox(from: raw)?.freeze()
    return raw
}()

@_cdecl("__kk_emptySet")
public func kk_emptySet() -> Int {
    return emptySetSingletonRaw
}

// BUG-196: Source-backed LinkedHashSet instances (and user subclasses) are
// allocated as ordinary RuntimeObjectBox objects. Attach a backing RuntimeSetBox
// during construction so MutableSet member calls operate on real storage.
@_cdecl("__kk_linked_hash_set_init")
public func kk_linked_hash_set_init(_ setRaw: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: setRaw),
          let objectBox = tryCast(ptr, to: RuntimeObjectBox.self)
    else {
        return 0
    }
    objectBox.backingSetBox = RuntimeSetBox(elements: [])
    return 0
}

@_cdecl("__kk_set_size")
public func kk_set_size(_ setRaw: Int) -> Int {
    if let pointer = UnsafeMutableRawPointer(bitPattern: setRaw),
       runtimeIsObjectPointer(pointer),
       let set = tryCast(pointer, to: RuntimeSetBox.self)
    {
        return set.count
    }

    // Source-allocated HashSet subclasses keep their elements in a backing
    // RuntimeSetBox, but their Set.size itable getter must remain observable.
    // The inherited HashSet getter re-enters this bridge; on that recursive
    // call, use the backing storage as the base implementation.
    let threadDictionary = Thread.current.threadDictionary
    let dispatchKey = "KSwiftK.RuntimeSetSizeDispatch.\(setRaw)"
    if threadDictionary[dispatchKey] != nil {
        return runtimeSetBox(from: setRaw)?.count ?? 0
    }
    threadDictionary[dispatchKey] = true
    defer { threadDictionary.removeObject(forKey: dispatchKey) }

    return runtimeSourceSetSize(setRaw)
        ?? runtimeSourceCollectionSize(setRaw)
        ?? runtimeSetBox(from: setRaw)?.count
        ?? 0
}

@_cdecl("__kk_set_contains")
public func kk_set_contains(_ setRaw: Int, _ element: Int) -> Int {
    guard let set = runtimeSetBox(from: setRaw) else {
        return runtimeSourceInterfaceCall1(
            setRaw,
            element,
            interfaceTypeID: runtimeStableNominalTypeID(fqName: "kotlin.collections.Set"),
            methodSlot: 1,
            context: "Set.contains dispatch"
        ) ?? 0
    }
    return set.contains(rawValue: element) ? 1 : 0
}

@_cdecl("__kk_set_is_empty")
public func kk_set_is_empty(_ setRaw: Int) -> Int {
    guard let set = runtimeSetBox(from: setRaw) else {
        if let result = runtimeSourceInterfaceCall0(
            setRaw,
            interfaceTypeID: runtimeStableNominalTypeID(fqName: "kotlin.collections.Set"),
            methodSlot: 0,
            context: "Set.isEmpty dispatch"
        ) {
            return result
        }
        return (runtimeSourceCollectionSize(setRaw) ?? 0) == 0 ? 1 : 0
    }
    return set.isEmpty ? 1 : 0
}

@_cdecl("__kk_set_to_string")
public func kk_set_to_string(_ setRaw: Int) -> UnsafeMutableRawPointer {
    guard let set = runtimeSetBox(from: setRaw) else {
        let str = "[]"
        let utf8 = Array(str.utf8)
        return utf8.withUnsafeBufferPointer { buf in
            kk_string_from_utf8(buf.baseAddress!, Int32(buf.count))
        }
    }
    let parts = set.values.map(runtimeElementToString)
    let str = "[" + parts.joined(separator: ", ") + "]"
    return runtimeMakeStringPointer(str)
}

@_cdecl("__kk_collection_toList")
public func kk_collection_toList(_ collRaw: Int) -> Int {
    if let list = runtimeListBox(from: collRaw) {
        return registerRuntimeObject(RuntimeListBox(values: list.values))
    }
    if let set = runtimeSetBox(from: collRaw) {
        return registerRuntimeObject(RuntimeListBox(values: set.values))
    }
    if let array = runtimeArrayBoxExcludingObjects(from: collRaw) {
        return registerRuntimeObject(RuntimeListBox(values: Array(array.values)))
    }
    // Delegate to sequence collection when the handle is a runtime-backed or
    // source-implemented Sequence box. This can happen when Collection.toList()
    // is resolved on a sequence receiver via the synthetic Collection stub.
    if let elements = runtimeSequenceSourceElements(from: collRaw) {
        return registerRuntimeObject(RuntimeListBox(elements: elements))
    }
    return registerRuntimeObject(RuntimeListBox(elements: []))
}

@_cdecl("__kk_collection_size")
public func kk_collection_size(_ collRaw: Int) -> Int {
    if let list = runtimeListBox(from: collRaw) {
        return list.count
    }
    if let set = runtimeSetBox(from: collRaw) {
        return set.count
    }
    if let sourceSize = runtimeSourceCollectionSize(collRaw) {
        return sourceSize
    }
    return 0
}

@_cdecl("__kk_collection_isEmpty")
public func kk_collection_isEmpty(_ collRaw: Int) -> Int {
    if let list = runtimeListBox(from: collRaw) {
        return list.count == 0 ? 1 : 0
    }
    if let set = runtimeSetBox(from: collRaw) {
        return set.isEmpty ? 1 : 0
    }
    if let sourceResult = runtimeSourceCollectionIsEmpty(collRaw) {
        return sourceResult != 0 ? 1 : 0
    }
    if let sourceSize = runtimeSourceCollectionSize(collRaw) {
        return sourceSize == 0 ? 1 : 0
    }
    return 1
}

@_cdecl("__kk_collection_containsAll")
public func kk_collection_containsAll(_ collRaw: Int, _ elementsRaw: Int) -> Int {
    // Resolve the receiver once: calling kk_op_contains per argument element
    // would re-run the range/list/set/array handle resolution chain (each
    // taking the GC lock) m times. List/Array receivers are additionally
    // hashed once into a Set so each probe is O(1) instead of an O(n)
    // linear scan — same equality as kk_op_contains via RuntimeElementKey.
    let contains: (Int) -> Int
    if let range = runtimeRangeBox(from: collRaw) {
        contains = { runtimeRangeContains(range, $0) }
    } else if let list = runtimeListBox(from: collRaw) {
        let membership = runtimeCollectionMembership(collRaw, values: list.values)
        contains = { membership($0) ? 1 : 0 }
    } else if let set = runtimeSetBox(from: collRaw) {
        contains = { set.contains(rawValue: $0) ? 1 : 0 }
    } else if let array = runtimeArrayBox(from: collRaw) {
        let elementSet = Set(array.values.lazy.map { RuntimeElementKey(value: $0.legacyRawValue) })
        contains = { elementSet.contains(RuntimeElementKey(value: $0)) ? 1 : 0 }
    } else {
        contains = { _ in 0 }
    }
    let iteratorRaw = kk_list_iterator(elementsRaw)
    while kk_list_iterator_hasNext(iteratorRaw) != 0 {
        if contains(kk_list_iterator_next(iteratorRaw)) == 0 {
            return 0
        }
    }
    return 1
}


@_cdecl("__kk_mutable_set_add")
public func kk_mutable_set_add(
    _ setRaw: Int,
    _ elem: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let set = runtimeSetBox(from: setRaw) else {
        if let sourceResult = runtimeSourceMutableSetAdd(setRaw, elem, outThrown: outThrown) {
            return sourceResult
        }
        return 0
    }
    if runtimeThrowIfReadOnlySet(set, outThrown) {
        return 0
    }
    let value = runtimeValueFromCollectionABI(elem)
    guard set.acceptsInsertion(rawValue: value.legacyRawValue) else {
        runtimeSetThrown(outThrown, runtimeAllocateIllegalArgumentException(message: "Element outside range view"))
        return 0
    }
    return set.insert(value: value) ? 1 : 0
}

@_cdecl("__kk_mutable_set_remove")
public func kk_mutable_set_remove(
    _ setRaw: Int,
    _ elem: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let set = runtimeSetBox(from: setRaw) else {
        if let sourceResult = runtimeSourceInterfaceCall1(
            setRaw,
            elem,
            interfaceTypeID: runtimeStableNominalTypeID(fqName: "kotlin.collections.MutableSet"),
            methodSlot: 1,
            context: "MutableSet.remove dispatch",
            outThrown: outThrown
        ) {
            return sourceResult
        }
        return 0
    }
    if runtimeThrowIfReadOnlySet(set, outThrown) {
        return 0
    }
    return set.remove(rawValue: elem) ? 1 : 0
}

@_cdecl("__kk_mutable_set_clear")
public func kk_mutable_set_clear(
    _ setRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let set = runtimeSetBox(from: setRaw) else {
        if let sourceResult = runtimeSourceInterfaceCall0(
            setRaw,
            interfaceTypeID: runtimeStableNominalTypeID(fqName: "kotlin.collections.MutableSet"),
            methodSlot: 2,
            context: "MutableSet.clear dispatch",
            outThrown: outThrown
        ) {
            return sourceResult
        }
        return 0
    }
    if runtimeThrowIfReadOnlySet(set, outThrown) {
        return 0
    }
    _ = set.removeAll(keepingCapacity: false)
    return 0
}

@_cdecl("__kk_mutable_set_addAll")
public func kk_mutable_set_addAll(_ setRaw: Int, _ collectionRaw: Int) -> Int {
    kk_mutable_collection_addAll(setRaw, collectionRaw)
}

@_cdecl("__kk_mutable_set_addAll_sequence")
public func kk_mutable_set_addAll_sequence(_ setRaw: Int, _ sequenceRaw: Int) -> Int {
    return runtimeMutableSetAddAllSequence(setRaw: setRaw, sequenceRaw: sequenceRaw)
}

@_cdecl("__kk_mutable_set_addAll_iterable")
public func kk_mutable_set_addAll_iterable(_ setRaw: Int, _ iterableRaw: Int) -> Int {
    kk_mutable_collection_addAll_iterable(setRaw, iterableRaw)
}

@_cdecl("__kk_mutable_set_removeAll")
public func kk_mutable_set_removeAll(
    _ setRaw: Int,
    _ collectionRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let set = runtimeSetBox(from: setRaw) else {
        if let result = runtimeSourceInterfaceCall1(
            setRaw, collectionRaw,
            interfaceTypeID: runtimeStableNominalTypeID(fqName: "kotlin.collections.MutableSet"),
            methodSlot: 4,
            context: "MutableSet.removeAll dispatch",
            outThrown: outThrown
        ) {
            return result
        }
        return 0
    }
    if runtimeThrowIfReadOnlySet(set, outThrown) {
        return 0
    }
    guard let collectionValues = runtimeCollectionValues(from: collectionRaw) else {
        return 0
    }
    let contains = runtimeCollectionMembership(collectionRaw, values: collectionValues)
    let originalCount = set.count
    _ = set.removeAll { elem in
        contains(elem.legacyRawValue)
    }
    return set.count != originalCount ? 1 : 0
}

@_cdecl("__kk_mutable_set_retainAll")
public func kk_mutable_set_retainAll(
    _ setRaw: Int,
    _ collectionRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let set = runtimeSetBox(from: setRaw) else {
        if let result = runtimeSourceInterfaceCall1(
            setRaw, collectionRaw,
            interfaceTypeID: runtimeStableNominalTypeID(fqName: "kotlin.collections.MutableSet"),
            methodSlot: 5,
            context: "MutableSet.retainAll dispatch",
            outThrown: outThrown
        ) {
            return result
        }
        return 0
    }
    if runtimeThrowIfReadOnlySet(set, outThrown) {
        return 0
    }
    guard let collectionValues = runtimeCollectionValues(from: collectionRaw) else {
        return 0
    }
    let contains = runtimeCollectionMembership(collectionRaw, values: collectionValues)
    let originalCount = set.count
    _ = set.removeAll { elem in
        !contains(elem.legacyRawValue)
    }
    return set.count != originalCount ? 1 : 0
}


private func runtimeMapOf(
    keysArrayRaw: Int,
    valuesArrayRaw: Int,
    count: Int,
    typeID: Int64
) -> Int {
    var keys: [Int] = []
    var values: [Int] = []
    if count > 0, let arrays = runtimeMapArrayPair(keysRaw: keysArrayRaw, valuesRaw: valuesArrayRaw) {
        let effectiveCount = min(count, arrays.keys.count, arrays.values.count)
        if effectiveCount > 0 {
            keys = Array(arrays.keys.prefix(effectiveCount))
            values = Array(arrays.values.prefix(effectiveCount))
        }
    }
    (keys, values) = runtimeNormalizeMapEntries(keys: keys, values: values)
    return registerRuntimeObject(RuntimeMapBox(keys: keys, values: values), typeID: typeID)
}

private func runtimeMapOfPairs(pairsArrayRaw: Int, count: Int, typeID: Int64) -> Int {
    var keys: [Int] = []
    var values: [Int] = []
    if count > 0, let pairs = runtimeArrayBox(from: pairsArrayRaw) {
        for pairRaw in pairs.elements.prefix(count) {
            guard let pointer = UnsafeMutableRawPointer(bitPattern: pairRaw),
                  let pairBox = tryCast(pointer, to: RuntimePairBox.self)
            else {
                fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid Pair handle in map-of-pairs factory")
            }
            keys.append(pairBox.first)
            values.append(pairBox.second)
        }
    }
    (keys, values) = runtimeNormalizeMapEntries(keys: keys, values: values)
    return registerRuntimeObject(RuntimeMapBox(keys: keys, values: values), typeID: typeID)
}

@inline(__always)
private func runtimeThrowIfReadOnlySet(
    _ set: RuntimeSetBox,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Bool {
    guard set.isEffectivelyReadOnly else { return false }
    runtimeSetThrown(outThrown, runtimeAllocateUnsupportedOperationException(message: nil))
    return true
}

@inline(__always)
private func runtimeThrowIfReadOnlyMap(
    _ map: RuntimeMapBox,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Bool {
    guard map.isEffectivelyReadOnly else { return false }
    runtimeSetThrown(outThrown, runtimeAllocateUnsupportedOperationException(message: nil))
    return true
}

@_cdecl("__kk_map_of")
public func kk_map_of(_ keysArrayRaw: Int, _ valuesArrayRaw: Int, _ count: Int) -> Int {
    // JVM `mapOf`: 0 pairs is the shared `EmptyMap`, 1 is the unmodifiable
    // `Collections.singletonMap`, and 2+ is a `LinkedHashMap` (mutable under
    // the read-only `Map` type). The singleton keeps the read-only `Map` tag
    // + freeze; `kk_op_is`'s erased check answers `is MutableMap` true for it
    // the way `Collections$SingletonMap` does on the JVM. KUU-3962, KUU-4144.
    if count == 0 {
        return emptyMapSingletonRaw
    }
    if count == 1 {
        let raw = runtimeMapOf(
            keysArrayRaw: keysArrayRaw,
            valuesArrayRaw: valuesArrayRaw,
            count: count,
            typeID: mapRuntimeTypeID
        )
        runtimeMapBox(from: raw)?.freeze()
        return raw
    }
    return runtimeMapOf(
        keysArrayRaw: keysArrayRaw,
        valuesArrayRaw: valuesArrayRaw,
        count: count,
        typeID: linkedHashMapRuntimeTypeID
    )
}

@_cdecl("__kk_hash_map_of")
public func kk_hash_map_of(_ keysArrayRaw: Int, _ valuesArrayRaw: Int, _ count: Int) -> Int {
    runtimeMapOf(
        keysArrayRaw: keysArrayRaw,
        valuesArrayRaw: valuesArrayRaw,
        count: count,
        typeID: hashMapRuntimeTypeID
    )
}

/// KUU-556: storage for the `LinkedHashMap()` constructor family and
/// `linkedMapOf`, both of which are declared to return `LinkedHashMap`.
/// `LinkedHashMap` is now a real `HashMap` subclass, so it needs its own
/// nominal tag for `is LinkedHashMap<*, *>` to answer true and `is HashMap<*,
/// *>` to also answer true via the `linkedHashMapRuntimeTypeID` -> `hashMapRuntimeTypeID`
/// edge (mirrors `__kk_linked_hash_set_of` / BUG-254, except Map's runtime
/// hierarchy makes LinkedHashMap a child of HashMap instead of a sibling).
@_cdecl("__kk_linked_hash_map_of")
public func kk_linked_hash_map_of(_ keysArrayRaw: Int, _ valuesArrayRaw: Int, _ count: Int) -> Int {
    runtimeMapOf(
        keysArrayRaw: keysArrayRaw,
        valuesArrayRaw: valuesArrayRaw,
        count: count,
        typeID: linkedHashMapRuntimeTypeID
    )
}

/// The compiler packs spread varargs before calling this bridge.
/// KUU-646: this is the read-only `mapOf(*pairs)` tag; mutable factories use
/// the HashMap / LinkedHashMap pair variants below.
@_cdecl("__kk_map_of_pairs")
public func kk_map_of_pairs(_ pairsArrayRaw: Int, _ count: Int) -> Int {
    // JVM `mapOf(vararg pairs)` is a `LinkedHashMap` for every non-empty
    // spread — including a single pair, unlike the fixed `mapOf(pair)`
    // overload's `Collections.singletonMap`. No freeze: the box stays
    // mutable under the read-only `Map` type, so `is MutableMap` and
    // post-cast writes match the JVM. KUU-4144.
    if count == 0 {
        return emptyMapSingletonRaw
    }
    return runtimeMapOfPairs(pairsArrayRaw: pairsArrayRaw, count: count, typeID: linkedHashMapRuntimeTypeID)
}

@_cdecl("__kk_hash_map_of_pairs")
public func kk_hash_map_of_pairs(_ pairsArrayRaw: Int, _ count: Int) -> Int {
    runtimeMapOfPairs(pairsArrayRaw: pairsArrayRaw, count: count, typeID: hashMapRuntimeTypeID)
}

@_cdecl("__kk_linked_hash_map_of_pairs")
public func kk_linked_hash_map_of_pairs(_ pairsArrayRaw: Int, _ count: Int) -> Int {
    runtimeMapOfPairs(pairsArrayRaw: pairsArrayRaw, count: count, typeID: linkedHashMapRuntimeTypeID)
}

// Kotlin exposes emptyMap() as a shared immutable instance. Keep the
// read-only `Map` tag so `as MutableMap` fails the way listOf/setOf casts do.
let emptyMapSingletonRaw: Int = {
    let raw = registerRuntimeObject(RuntimeMapBox(keys: [], values: []), typeID: mapRuntimeTypeID)
    runtimeMapBox(from: raw)?.freeze()
    return raw
}()

@_cdecl("__kk_emptyMap")
public func kk_emptyMap() -> Int {
    return emptyMapSingletonRaw
}

@_cdecl("__kk_mutable_map_put")
public func kk_mutable_map_put(
    _ mapRaw: Int,
    _ key: Int,
    _ value: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    runtimeMutableMapPut(mapRaw: mapRaw, key: key, value: value,
                         countAsAccess: true, outThrown: outThrown)
}

/// Shared put body. `MutableEntry.setValue` passes `countAsAccess: false`:
/// the JDK writes `HashMap.Node.value` directly and never triggers
/// `LinkedHashMap.afterNodeAccess` for it, even in access-order mode.
private func runtimeMutableMapPut(
    mapRaw: Int,
    key: Int,
    value: Int,
    countAsAccess: Bool,
    outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let map = runtimeMapBox(from: mapRaw) else {
        return runtimeSourceMutableMapPut(mapRaw, key: key, value: value, outThrown: outThrown)
            ?? runtimeNullSentinelInt
    }
    if runtimeThrowIfReadOnlyMap(map, outThrown) {
        return runtimeNullSentinelInt
    }
    // Identity maps retain boxed reference handles, including boxed Char.
    let runtimeKey = map.usesReferenceEquality ? RuntimeValue(raw: key) : runtimeValueFromCollectionABI(key)
    let runtimeValue = map.usesReferenceEquality ? RuntimeValue(raw: value) : runtimeValueFromCollectionABI(value)
    guard map.acceptsInsertion(rawKey: runtimeKey.legacyRawValue) else {
        runtimeSetThrown(outThrown, runtimeAllocateIllegalArgumentException(message: "Key outside range view"))
        return runtimeNullSentinelInt
    }
    return map.put(key: runtimeKey, value: runtimeValue, countAsAccess: countAsAccess)
        .map(runtimeCollectionABIValue)
        ?? runtimeNullSentinelInt
}

@_cdecl("__kk_mutable_map_remove")
public func kk_mutable_map_remove(
    _ mapRaw: Int,
    _ key: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let map = runtimeMapBox(from: mapRaw) else {
        return runtimeSourceMutableMapRemove(mapRaw, key: key, outThrown: outThrown)
            ?? runtimeNullSentinelInt
    }
    if runtimeThrowIfReadOnlyMap(map, outThrown) {
        return runtimeNullSentinelInt
    }
    return map.remove(key: key) ?? runtimeNullSentinelInt
}

@_cdecl("__kk_mutable_map_clear")
public func kk_mutable_map_clear(
    _ mapRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let map = runtimeMapBox(from: mapRaw) else {
        return runtimeSourceMutableMapClear(mapRaw, outThrown: outThrown) ?? 0
    }
    if runtimeThrowIfReadOnlyMap(map, outThrown) {
        return 0
    }
    map.removeAll()
    return 0
}

@_cdecl("__kk_mutable_map_putAll")
public func kk_mutable_map_putAll(
    _ mapRaw: Int,
    _ otherMapRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let map = runtimeMapBox(from: mapRaw) else {
        return runtimeSourceMutableMapPutAll(mapRaw, otherMapRaw: otherMapRaw, outThrown: outThrown) ?? 0
    }
    if runtimeThrowIfReadOnlyMap(map, outThrown) {
        return 0
    }
    guard let other = runtimeMapBox(from: otherMapRaw) else {
        runtimeCopySourceMapEntries(map, from: otherMapRaw, outThrown: outThrown)
        return 0
    }
    let otherKeys = other.keyValues
    let otherValues = other.entryValues
    for key in otherKeys where !map.acceptsInsertion(rawKey: key.legacyRawValue) {
        runtimeSetThrown(outThrown, runtimeAllocateIllegalArgumentException(message: "Key outside range view"))
        return 0
    }
    for (idx, key) in otherKeys.enumerated() {
        guard idx < otherValues.count else { break }
        _ = map.put(key: key, value: otherValues[idx])
    }
    return 0
}

private func runtimeCopySourceMapEntries(
    _ map: RuntimeMapBox,
    from source: Int,
    outThrown: UnsafeMutablePointer<Int>?
) {
    var thrown = 0
    defer {
        if thrown != 0 {
            runtimePropagateThrownOrTrap(thrown, outThrown: outThrown, context: "MutableMap.putAll dispatch")
        }
    }
    // Runtime map boxes have no Kotlin itable. Source Map/Entry inputs do;
    // use their getter slots instead of assuming entries are runtime pairs.
    guard let entries = runtimeSourceInterfaceCall0(
        source,
        interfaceTypeID: runtimeStableNominalTypeID(fqName: "kotlin.collections.Map"),
        methodSlot: runtimeMapEntriesGetterSlot,
        context: "Map.entries dispatch",
        outThrown: &thrown
    ), thrown == 0 else { return }
    let iterator = kk_iterable_iterator(entries, &thrown)
    guard thrown == 0 else { return }
    let entryTypeID = runtimeStableNominalTypeID(fqName: "kotlin.collections.Map.Entry")
    while kk_iterator_hasNext(iterator, &thrown) != 0 {
        guard thrown == 0 else { return }
        let entry = kk_iterator_next(iterator, &thrown)
        guard thrown == 0,
              let key = runtimeSourceInterfaceCall0(
                  entry, interfaceTypeID: entryTypeID, methodSlot: 0,
                  context: "Map.Entry.key dispatch", outThrown: &thrown
              ), thrown == 0,
              let value = runtimeSourceInterfaceCall0(
                  entry, interfaceTypeID: entryTypeID, methodSlot: 1,
                  context: "Map.Entry.value dispatch", outThrown: &thrown
              ), thrown == 0
        else { return }
        if !map.acceptsInsertion(rawKey: key) {
            thrown = runtimeAllocateIllegalArgumentException(message: "Key outside range view")
            return
        }
        _ = map.put(key: key, value: value)
    }
}

@_cdecl("__kk_mutable_map_plusAssign_pair")
public func kk_mutable_map_plusAssign_pair(_ mapRaw: Int, _ pairRaw: Int) -> Int {
    guard let pointer = UnsafeMutableRawPointer(bitPattern: pairRaw),
          let pairBox = tryCast(pointer, to: RuntimePairBox.self)
    else {
        return 0
    }
    _ = kk_mutable_map_put(
        mapRaw,
        runtimeCollectionABIValue(pairBox.firstValue),
        runtimeCollectionABIValue(pairBox.secondValue),
        nil
    )
    return 0
}

@_cdecl("__kk_map_size")
public func kk_map_size(_ mapRaw: Int) -> Int {
    guard let map = runtimeMapBox(from: mapRaw) else {
        return runtimeSourceMapSize(mapRaw) ?? 0
    }
    return map.count
}

@_cdecl("__kk_map_get")
public func kk_map_get(_ mapRaw: Int, _ key: Int) -> Int {
    guard let map = runtimeMapBox(from: mapRaw) else {
        return runtimeSourceMapGet(mapRaw, key: key) ?? runtimeNullSentinelInt
    }
    guard let index = map.index(ofRawKey: key) else {
        return runtimeNullSentinelInt
    }
    guard let value = map.runtimeValue(at: index) else {
        return runtimeNullSentinelInt
    }
    // KUU-4500: an access-order LinkedHashMap moves the touched entry to the
    // tail, like the JDK's afterNodeAccess. No-op for ordinary boxes.
    map.recordAccess(at: index)
    return runtimeCollectionABIValue(value)
}

/// Marks a LinkedHashMap box as access-ordered (`LinkedHashMap(capacity,
/// loadFactor, accessOrder=true)`). A separate setter keeps the existing
/// `__kk_linked_hash_map_of` factory signature unchanged.
@_cdecl("__kk_map_set_access_order")
public func kk_map_set_access_order(_ mapRaw: Int, _ accessOrder: Int) -> Int {
    if accessOrder != 0 {
        runtimeMapBox(from: mapRaw)?.enableAccessOrder()
    }
    return 0
}

@_cdecl("__kk_map_contains_key")
public func kk_map_contains_key(_ mapRaw: Int, _ key: Int) -> Int {
    guard let map = runtimeMapBox(from: mapRaw) else {
        if let sourceResult = runtimeSourceMapContainsKey(mapRaw, key: key) {
            return sourceResult
        }
        // The implementation left containsKey on its interface default: fall
        // back to `keys.contains(key)`, matching the stdlib extension.
        return kk_op_contains(kk_map_keys(mapRaw), key)
    }
    return map.index(ofRawKey: key) != nil ? 1 : 0
}

@_cdecl("__kk_map_contains_value")
public func kk_map_contains_value(_ mapRaw: Int, _ value: Int) -> Int {
    guard let map = runtimeMapBox(from: mapRaw) else {
        if let sourceResult = runtimeSourceMapContainsValue(mapRaw, value: value) {
            return sourceResult
        }
        // Mirror the stdlib extension's `values.contains(value)` fallback when
        // the implementation does not override containsValue.
        return kk_op_contains(kk_map_values(mapRaw), value)
    }
    return map.values.contains(where: { map.valuesEqual($0, value) }) ? 1 : 0
}

@inline(__always)
private func runtimeMapDefaultValue(_ map: RuntimeMapBox, key: Int, outThrown: UnsafeMutablePointer<Int>?) -> Int? {
    guard map.defaultValueFnPtr != 0 else {
        return nil
    }
    var thrown = 0
    let result = runtimeInvokeCollectionLambda1MaybeWrapped(
        fnPtr: map.defaultValueFnPtr,
        closureRaw: map.defaultValueClosureRaw,
        value: key,
        outThrown: &thrown
    )
    if thrown != 0 {
        return handleCollectionLambdaThrow(thrown, outThrown)
    }
    return result
}

/// Returns the `withDefault` value for `key`, or the null sentinel when the map
/// carries no default. Kotlin's `Map.getValue` consults this after a plain
/// lookup miss (KSP-431).
@_cdecl("__kk_map_implicit_default")
public func kk_map_implicit_default(_ mapRaw: Int, _ key: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let map = runtimeMapBox(from: mapRaw),
          let defaultValue = runtimeMapDefaultValue(map, key: key, outThrown: outThrown)
    else {
        return runtimeNullSentinelInt
    }
    return defaultValue
}

@_cdecl("__kk_map_has_default")
public func kk_map_has_default(_ mapRaw: Int) -> Int {
    guard let map = runtimeMapBox(from: mapRaw) else {
        return 0
    }
    return map.defaultValueFnPtr == 0 ? 0 : 1
}
@_cdecl("__kk_map_withDefault")
public func kk_map_withDefault(_ mapRaw: Int, _ fnPtr: Int, _ closureRaw: Int) -> Int {
    guard let map = runtimeMapBox(from: mapRaw) else {
        return registerRuntimeObject(RuntimeMapBox(
            keys: [],
            values: [],
            defaultValueFnPtr: fnPtr,
            defaultValueClosureRaw: closureRaw
        ))
    }
    return registerRuntimeObject(RuntimeMapBox(
        keys: map.keys,
        values: map.values,
        defaultValueFnPtr: fnPtr,
        defaultValueClosureRaw: closureRaw,
        backingMap: map
    ))
}

@_cdecl("__kk_mutable_map_withDefault")
public func kk_mutable_map_withDefault(_ mapRaw: Int, _ fnPtr: Int, _ closureRaw: Int) -> Int {
    guard let map = runtimeMapBox(from: mapRaw) else {
        return registerRuntimeObject(
            RuntimeMapBox(
                keys: [],
                values: [],
                defaultValueFnPtr: fnPtr,
                defaultValueClosureRaw: closureRaw
            ),
            typeID: mutableMapRuntimeTypeID
        )
    }
    return registerRuntimeObject(
        RuntimeMapBox(
            keys: map.keys,
            values: map.values,
            defaultValueFnPtr: fnPtr,
            defaultValueClosureRaw: closureRaw,
            backingMap: map
        ),
        typeID: mutableMapRuntimeTypeID
    )
}

@_cdecl("__kk_map_is_empty")
public func kk_map_is_empty(_ mapRaw: Int) -> Int {
    guard let map = runtimeMapBox(from: mapRaw) else {
        if let sourceResult = runtimeSourceMapIsEmpty(mapRaw) {
            return sourceResult
        }
        if let sourceSize = runtimeSourceMapSize(mapRaw) {
            return sourceSize == 0 ? 1 : 0
        }
        return 1
    }
    return map.isEmpty ? 1 : 0
}

@_cdecl("__kk_map_entries")
public func kk_map_entries(_ mapRaw: Int) -> Int {
    guard runtimeMapBox(from: mapRaw) != nil else {
        return runtimeSourceMapEntries(mapRaw)
            ?? registerRuntimeObject(RuntimeSetBox(elements: []))
    }
    // MutableMap.entries is a mutable view. Keep this set handle connected to
    // the map so MutableIterable.removeAll/retainAll can remove through its
    // iterator rather than mutating a detached entry snapshot.
    // JVM entry-set impls (`java.util.*Map$EntrySet`, `Collections$SingletonSet`)
    // all answer `is MutableSet` true — except `emptyMap()`'s `EmptySet` view,
    // which keeps the read-only `Set` tag (KUU-4144).
    return registerRuntimeObject(
        RuntimeSetBox(mapEntriesOf: mapRaw),
        typeID: mapRaw == emptyMapSingletonRaw ? setRuntimeTypeID : mutableMapViewSetRuntimeTypeID
    )
}

@_cdecl("__kk_map_keys")
public func kk_map_keys(_ mapRaw: Int) -> Int {
    guard let map = runtimeMapBox(from: mapRaw) else {
        return runtimeSourceMapKeys(mapRaw)
            ?? registerRuntimeObject(RuntimeSetBox(elements: []))
    }
    // MutableMap.keys is a mutable, write-through view (mirrors .entries
    // above): removing through it removes the key from the map, and later
    // map mutations are visible through this same set handle.
    let view = RuntimeSetBox(mapKeysOf: mapRaw)
    if map.sorted {
        // KUU-1361: java.util.TreeMap.keySet() is a NavigableSet — the view
        // already iterates in key order, so enabling sorted state makes the
        // navigable members correct too.
        view.enableSorted(comparatorRaw: map.comparatorRaw, invertCompare: map.invertCompare)
        return registerRuntimeObject(view, typeID: navigableSetRuntimeTypeID)
    }
    // Same `is MutableSet` split as `.entries` above: `java.util.*Map$KeySet`
    // views are mutable impls, `emptyMap().keys` is `EmptySet` (KUU-4144).
    return registerRuntimeObject(
        view,
        typeID: mapRaw == emptyMapSingletonRaw ? setRuntimeTypeID : mutableMapViewSetRuntimeTypeID
    )
}

@_cdecl("__kk_map_values")
public func kk_map_values(_ mapRaw: Int) -> Int {
    guard let map = runtimeMapBox(from: mapRaw) else {
        return runtimeSourceMapValues(mapRaw)
            ?? registerRuntimeObject(RuntimeListBox(elements: []))
    }
    // JDK `Collections$SingletonMap.values` is a `Collections$SingletonSet` —
    // a Set impl answering `is Set` true. A frozen snapshot keeps the same
    // shape as `setOf(v)` since the singleton map can never change (KUU-4144).
    if map.count == 1,
       runtimeObjectTypeID(rawValue: mapRaw) == mapRuntimeTypeID,
       map.isEffectivelyReadOnly,
       let value = map.values.first
    {
        let view = RuntimeSetBox(elements: [value])
        view.freeze()
        return registerRuntimeObject(view)
    }
    // MutableMap.values is a mutable, write-through view (mirrors .entries
    // / .keys above): removing through it removes the corresponding
    // key/value pair from the map. JVM `*Map$*Values` impls are
    // `AbstractCollection`s — mutable collections, not lists — while
    // `emptyMap().values` shares `EmptyList` (KUU-4144).
    return registerRuntimeObject(
        RuntimeListBox(mapValuesOf: mapRaw),
        typeID: mapRaw == emptyMapSingletonRaw ? listRuntimeTypeID : mutableMapViewCollectionRuntimeTypeID
    )
}

@_cdecl("__kk_map_iterator")
public func kk_map_iterator(_ mapRaw: Int) -> Int {
    let keys = runtimeMapBox(from: mapRaw)?.keys ?? []
    return registerRuntimeObject(RuntimeMapIteratorBox(mapRaw: mapRaw, keys: keys))
}

@_cdecl("__kk_map_iterator_hasNext")
public func kk_map_iterator_hasNext(_ iterRaw: Int) -> Int {
    guard let iter = runtimeMapIteratorBox(from: iterRaw) else {
        return 0
    }
    return iter.index < iter.keys.count ? 1 : 0
}

/// Returns the key at the current position, matching the C preamble behavior.
@_cdecl("__kk_map_iterator_next")
public func kk_map_iterator_next(
    _ iterRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>? = nil
) -> Int {
    outThrown?.pointee = 0
    guard let iter = runtimeMapIteratorBox(from: iterRaw),
          iter.index < iter.keys.count
    else {
        return runtimeThrowIteratorExhausted(outThrown)
    }
    guard iter.isInSyncWithBackingMap() else {
        runtimeSetThrown(outThrown, runtimeAllocateConcurrentModificationException(message: nil))
        return runtimeExceptionCaughtSentinel
    }
    let key = iter.keys[iter.index]
    iter.index += 1
    return key
}

@_cdecl("__kk_mutable_map_iterator")
public func kk_mutable_map_iterator(_ mapRaw: Int) -> Int {
    let mapBox = runtimeMapBox(from: mapRaw)
    let keyValues = mapBox?.keyValues ?? []
    let keys = keyValues.map(\.legacyRawValue)
    return registerRuntimeObject(RuntimeMutableMapIteratorBox(mapRaw: mapRaw, keys: keys, keyValues: keyValues))
}

@_cdecl("__kk_mutable_map_iterator_hasNext")
public func kk_mutable_map_iterator_hasNext(_ iterRaw: Int) -> Int {
    guard let iter = runtimeMutableMapIteratorBox(from: iterRaw) else {
        return 0
    }
    return iter.index < iter.keys.count ? 1 : 0
}

@_cdecl("__kk_mutable_map_iterator_next")
public func kk_mutable_map_iterator_next(
    _ iterRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>? = nil
) -> Int {
    outThrown?.pointee = 0
    guard let iter = runtimeMutableMapIteratorBox(from: iterRaw),
          iter.index < iter.keys.count
    else {
        return runtimeThrowIteratorExhausted(outThrown)
    }
    guard iter.isInSyncWithBackingMap() else {
        runtimeSetThrown(outThrown, runtimeAllocateConcurrentModificationException(message: nil))
        return runtimeExceptionCaughtSentinel
    }
    let key = iter.keys[iter.index]
    iter.index += 1
    iter.lastKey = key
    guard let map = runtimeMapBox(from: iter.mapRaw),
          let storageIndex = map.index(ofRawKey: key),
          let value = map.runtimeValue(at: storageIndex)
    else {
        return runtimeMutableMapEntryNew(
            mapRaw: iter.mapRaw,
            key: RuntimeValue(raw: key),
            value: RuntimeValue(raw: kk_map_get(iter.mapRaw, key))
        )
    }
    return runtimeMutableMapEntryNew(
        mapRaw: iter.mapRaw,
        // `keyValues` is the view's projected order, while `storageIndex`
        // may refer to the backing map's storage position. The iterator
        // snapshot preserves the corresponding view index.
        key: iter.keyValues[iter.index - 1],
        value: value
    )
}

@_cdecl("__kk_mutable_map_iterator_remove")
public func kk_mutable_map_iterator_remove(
    _ iterRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let iter = runtimeMutableMapIteratorBox(from: iterRaw),
          let key = iter.lastKey
    else {
        runtimeSetThrown(outThrown, runtimeAllocateIllegalStateException(message: nil))
        return runtimeExceptionCaughtSentinel
    }
    _ = kk_mutable_map_remove(iter.mapRaw, key, outThrown)
    if outThrown?.pointee != 0 {
        return runtimeExceptionCaughtSentinel
    }
    iter.lastKey = nil
    // The removal above just bumped the backing map's modCount through this
    // same iterator — resync so the next `next()` call does not see this
    // iterator's own change as a concurrent modification.
    iter.expectedModCount = runtimeMapBox(from: iter.mapRaw)?.modCount ?? iter.expectedModCount
    return 0
}

@_cdecl("__kk_mutable_map_entry_setValue")
public func kk_mutable_map_entry_setValue(
    _ entryRaw: Int,
    _ value: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let pointer = UnsafeMutableRawPointer(bitPattern: entryRaw),
          let pairBox = tryCast(pointer, to: RuntimePairBox.self),
          pairBox.mutableMapRaw != 0
    else {
        return runtimeNullSentinelInt
    }
    var thrown = 0
    let previous = runtimeMutableMapPut(mapRaw: pairBox.mutableMapRaw, key: pairBox.mutableMapKey,
                                        value: value, countAsAccess: false, outThrown: &thrown)
    if thrown != 0 {
        outThrown?.pointee = thrown
        return runtimeNullSentinelInt
    }
    pairBox.setSecondValue(runtimeValueFromCollectionABI(value), returning: previous)
    return previous
}
