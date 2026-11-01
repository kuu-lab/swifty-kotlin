/// `Collection` -> `Iterable` supertype edge, registered once so that boxes
/// tagged as `List`/`Set` answer `is Collection<*>` / `is Iterable<*>` (and the
/// erased `as Iterable<T>` cast) through the ordinary assignability walk.
private let collectionRuntimeTypeID: Int64 = {
    let id = runtimeStableNominalTypeID(fqName: "kotlin.collections.Collection")
    runtimeRegisterTypeEdge(
        childTypeID: id,
        parentTypeID: runtimeStableNominalTypeID(fqName: "kotlin.collections.Iterable")
    )
    return id
}()

/// `MutableIterable` -> `Iterable` and `MutableCollection` -> `Collection` /
/// `MutableIterable` edges, so mutable boxes answer `is MutableIterable<*>` and
/// `is MutableCollection<*>` through the ordinary assignability walk.
private let mutableCollectionRuntimeTypeID: Int64 = {
    let mutableIterable = runtimeStableNominalTypeID(fqName: "kotlin.collections.MutableIterable")
    runtimeRegisterTypeEdge(
        childTypeID: mutableIterable,
        parentTypeID: runtimeStableNominalTypeID(fqName: "kotlin.collections.Iterable")
    )
    let id = runtimeStableNominalTypeID(fqName: "kotlin.collections.MutableCollection")
    runtimeRegisterTypeEdge(childTypeID: id, parentTypeID: collectionRuntimeTypeID)
    runtimeRegisterTypeEdge(childTypeID: id, parentTypeID: mutableIterable)
    return id
}()

let listRuntimeTypeID: Int64 = {
    let id = runtimeStableNominalTypeID(fqName: "kotlin.collections.List")
    runtimeRegisterTypeEdge(childTypeID: id, parentTypeID: collectionRuntimeTypeID)
    return id
}()

let mutableListRuntimeTypeID: Int64 = {
    let id = runtimeStableNominalTypeID(fqName: "kotlin.collections.MutableList")
    runtimeRegisterTypeEdge(childTypeID: id, parentTypeID: listRuntimeTypeID)
    runtimeRegisterTypeEdge(childTypeID: id, parentTypeID: mutableCollectionRuntimeTypeID)
    return id
}()

/// Kotlin/JVM erases `List` and `MutableList` to the same runtime interface.
/// Built-in frozen list boxes therefore pass mutable collection type checks
/// even though source-defined `List` implementations retain their own identity.
func runtimeIsJvmErasedListAssignable(
    rawValue: Int,
    sourceTypeID: Int64,
    targetTypeID: Int64
) -> Bool {
    guard sourceTypeID == listRuntimeTypeID
            || sourceTypeID == singletonListRuntimeTypeID
            || sourceTypeID == arraysBackedListRuntimeTypeID,
          runtimeListBox(from: rawValue)?.isEffectivelyReadOnly == true
    else { return false }
    return runtimeIsAssignable(sourceTypeID: mutableListRuntimeTypeID, targetTypeID: targetTypeID)
}

private let abstractMutableListRuntimeTypeID = runtimeStableNominalTypeID(
    fqName: "kotlin.collections.AbstractMutableList"
)
private let randomAccessRuntimeTypeID = runtimeStableNominalTypeID(
    fqName: "kotlin.collections.RandomAccess"
)

// View identities preserve interface conformance without claiming ArrayList identity.
private let listViewRuntimeTypeIDs: [Int64] = (0..<4).map { flags in
    let mutable = flags & 1 != 0
    let randomAccess = flags & 2 != 0
    let id = runtimeStableNominalTypeID(fqName: "kotlin.collections.__KSwiftKListView\(flags)")
    runtimeRegisterTypeEdge(childTypeID: id, parentTypeID: mutable ? mutableListRuntimeTypeID : listRuntimeTypeID)
    if mutable {
        runtimeRegisterTypeEdge(childTypeID: id, parentTypeID: runtimeMutableCollectionInterfaceTypeID)
    }
    if randomAccess {
        runtimeRegisterTypeEdge(childTypeID: id, parentTypeID: randomAccessRuntimeTypeID)
    }
    return id
}

func runtimeListViewTypeID(mutable: Bool, randomAccess: Bool) -> Int64 {
    listViewRuntimeTypeIDs[(mutable ? 1 : 0) | (randomAccess ? 2 : 0)]
}

/// Decodes a view tag back into its conformance flags (KUU-3963): reflection
/// names `subList`/`asReversed` views after the JVM implementation class the
/// flags describe (`java.util.AbstractList$RandomAccessSubList`,
/// `kotlin.collections.ReversedList`, ...).
func runtimeListViewTypeIDFlags(_ typeID: Int64) -> (mutable: Bool, randomAccess: Bool)? {
    guard let flags = listViewRuntimeTypeIDs.firstIndex(of: typeID) else { return nil }
    return (flags & 1 != 0, flags & 2 != 0)
}

private func runtimeListHasConformance(_ raw: Int, to typeID: Int64) -> Bool {
    guard let sourceTypeID = runtimeObjectTypeID(rawValue: raw) else { return false }
    return runtimeIsAssignable(sourceTypeID: sourceTypeID, targetTypeID: typeID)
}

func runtimeSubListTypeID(_ raw: Int) -> Int64 {
    runtimeListViewTypeID(
        mutable: runtimeListHasConformance(raw, to: mutableListRuntimeTypeID),
        randomAccess: runtimeListHasConformance(raw, to: randomAccessRuntimeTypeID)
    )
}

let arrayListRuntimeTypeID: Int64 = {
    let id = runtimeStableNominalTypeID(fqName: "kotlin.collections.ArrayList")
    runtimeRegisterTypeEdge(childTypeID: id, parentTypeID: mutableListRuntimeTypeID)
    runtimeRegisterTypeEdge(childTypeID: id, parentTypeID: abstractMutableListRuntimeTypeID)
    runtimeRegisterTypeEdge(childTypeID: id, parentTypeID: randomAccessRuntimeTypeID)
    return id
}()

let arrayDequeRuntimeTypeID: Int64 = {
    let id = runtimeStableNominalTypeID(fqName: "kotlin.collections.ArrayDeque")
    runtimeRegisterTypeEdge(childTypeID: id, parentTypeID: mutableListRuntimeTypeID)
    runtimeRegisterTypeEdge(childTypeID: id, parentTypeID: abstractMutableListRuntimeTypeID)
    runtimeRegisterTypeEdge(
        childTypeID: id,
        parentTypeID: runtimeStableNominalTypeID(fqName: "kotlin.collections.MutableCollection")
    )
    return id
}()

/// `listOf(element)` maps to `java.util.Collections$SingletonList` on the JVM:
/// its `get` throws `IndexOutOfBoundsException("Index: i, Size: n")` and its
/// `subList`/`listIterator` bounds errors differ from both `ArrayList` and the
/// generic `AbstractList` paths, so it needs its own nominal tag.
let singletonListRuntimeTypeID: Int64 = {
    let id = runtimeStableNominalTypeID(fqName: "java.util.Collections.SingletonList")
    runtimeRegisterTypeEdge(childTypeID: id, parentTypeID: listRuntimeTypeID)
    runtimeRegisterTypeEdge(childTypeID: id, parentTypeID: randomAccessRuntimeTypeID)
    return id
}()

/// `listOf(e1, e2, ...)` maps to `java.util.Arrays$ArrayList`: `get` and
/// indexed `slice` fail with `ArrayIndexOutOfBoundsException` instead of the
/// `IndexOutOfBoundsException` a plain `List` produces.
let arraysBackedListRuntimeTypeID: Int64 = {
    let id = runtimeStableNominalTypeID(fqName: "java.util.Arrays.ArrayList")
    runtimeRegisterTypeEdge(childTypeID: id, parentTypeID: listRuntimeTypeID)
    runtimeRegisterTypeEdge(childTypeID: id, parentTypeID: randomAccessRuntimeTypeID)
    return id
}()

private let mutableSetRuntimeTypeID: Int64 = {
    let id = runtimeStableNominalTypeID(fqName: "kotlin.collections.MutableSet")
    runtimeRegisterTypeEdge(childTypeID: id, parentTypeID: mutableCollectionRuntimeTypeID)
    return id
}()

let setRuntimeTypeID: Int64 = {
    let id = runtimeStableNominalTypeID(fqName: "kotlin.collections.Set")
    runtimeRegisterTypeEdge(childTypeID: id, parentTypeID: collectionRuntimeTypeID)
    return id
}()

/// Ordinary Set factories keep using `setRuntimeTypeID`; only HashSet
/// constructors opt into this more specific identity.
let hashSetRuntimeTypeID: Int64 = {
    let id = runtimeStableNominalTypeID(fqName: "kotlin.collections.HashSet")
    runtimeRegisterTypeEdge(childTypeID: id, parentTypeID: mutableSetRuntimeTypeID)
    runtimeRegisterTypeEdge(
        childTypeID: id,
        parentTypeID: runtimeStableNominalTypeID(fqName: "kotlin.collections.AbstractMutableSet")
    )
    runtimeRegisterTypeEdge(childTypeID: id, parentTypeID: setRuntimeTypeID)
    return id
}()

/// User-defined subclasses are allocated as RuntimeObjectBox instances.
/// The HashSet parent identity lets runtimeSetBox lazily attach their storage
/// even when library superclass initializers are not emitted.
///
/// BUG-254: the mutable set factories and the LinkedHashSet constructors now tag
/// their box with this ID, so it needs parent edges the way
/// `hashSetRuntimeTypeID` has them -- without them `is MutableSet<*>` and
/// `is Set<*>` would answer false on a box carrying this tag.
/// KUU-1940: the distinct LinkedHashSet identity inherits HashSet's nominal
/// hierarchy, matching `LinkedHashSet.kt` for erased `is` and cast operations.
let linkedHashSetRuntimeTypeID: Int64 = {
    let id = runtimeStableNominalTypeID(fqName: "kotlin.collections.LinkedHashSet")
    runtimeRegisterTypeEdge(childTypeID: id, parentTypeID: hashSetRuntimeTypeID)
    runtimeRegisterTypeEdge(childTypeID: id, parentTypeID: mutableSetRuntimeTypeID)
    runtimeRegisterTypeEdge(childTypeID: id, parentTypeID: setRuntimeTypeID)
    return id
}()

/// Boxes are tagged `treeSetRuntimeTypeID`/`treeMapRuntimeTypeID`; the
/// interface IDs carry the assignability edges that let `is SortedSet<*>` /
/// `is NavigableMap<*, *>` answer true on those tags.
let sortedSetRuntimeTypeID: Int64 = runtimeStableNominalTypeID(fqName: "java.util.SortedSet")

let navigableSetRuntimeTypeID: Int64 = runtimeStableNominalTypeID(fqName: "java.util.NavigableSet")

/// Source-allocated subclasses arrive as RuntimeObjectBox instances;
/// runtimeSetBox lazily attaches a sorted backing box the same way
/// LinkedHashSet subclasses attach theirs.
let treeSetRuntimeTypeID: Int64 = runtimeStableNominalTypeID(fqName: "java.util.TreeSet")

let sortedMapRuntimeTypeID: Int64 = runtimeStableNominalTypeID(fqName: "java.util.SortedMap")

let navigableMapRuntimeTypeID: Int64 = runtimeStableNominalTypeID(fqName: "java.util.NavigableMap")

/// See `treeSetRuntimeTypeID` for the lazy-attach path that relies on this ID.
let treeMapRuntimeTypeID: Int64 = runtimeStableNominalTypeID(fqName: "java.util.TreeMap")

/// Mirrors `registerRangeTypeEdgesOnce`, including its resettability:
/// `kk_runtime_reset_metadata` clears `typeParents` and
/// `sortedCollectionTypeEdgesRegistered` together, so the edges re-register
/// on the next `is` check or lazy-attach after a metadata reset.
func registerSortedCollectionTypeEdgesOnce() {
    // Resolve every type-ID global *before* taking the metadata lock: the
    // collection ID initializers (setRuntimeTypeID, mapRuntimeTypeIDs) call
    // runtimeRegisterTypeEdge, which acquires the same non-recursive lock.
    // Referencing them inside the closure deadlocks on first use.
    let sortedSet = sortedSetRuntimeTypeID
    let navigableSet = navigableSetRuntimeTypeID
    let treeSet = treeSetRuntimeTypeID
    let sortedMap = sortedMapRuntimeTypeID
    let navigableMap = navigableMapRuntimeTypeID
    let treeMap = treeMapRuntimeTypeID
    let mutableSet = runtimeStableNominalTypeID(fqName: "kotlin.collections.MutableSet")
    let abstractMutableSet = runtimeStableNominalTypeID(fqName: "kotlin.collections.AbstractMutableSet")
    let abstractMutableMap = runtimeStableNominalTypeID(fqName: "kotlin.collections.AbstractMutableMap")
    let set = setRuntimeTypeID
    let mutableMap = mutableMapRuntimeTypeID
    runtimeStorage.withMetadataLock { state in
        if state.sortedCollectionTypeEdgesRegistered {
            return
        }
        state.typeParents[sortedSet, default: []].insert(mutableSet)
        state.typeParents[sortedSet, default: []].insert(set)
        state.typeParents[navigableSet, default: []].insert(sortedSet)
        state.typeParents[treeSet, default: []].insert(navigableSet)
        state.typeParents[treeSet, default: []].insert(abstractMutableSet)
        state.typeParents[sortedMap, default: []].insert(mutableMap)
        state.typeParents[navigableMap, default: []].insert(sortedMap)
        state.typeParents[treeMap, default: []].insert(navigableMap)
        state.typeParents[treeMap, default: []].insert(abstractMutableMap)
        state.sortedCollectionTypeEdgesRegistered = true
    }
}

private let mapRuntimeTypeIDs: (map: Int64, mutableMap: Int64, hashMap: Int64, linkedHashMap: Int64) = {
    let mapID = runtimeStableNominalTypeID(fqName: "kotlin.collections.Map")
    let mutableMapID = runtimeStableNominalTypeID(fqName: "kotlin.collections.MutableMap")
    let hashMapID = runtimeStableNominalTypeID(fqName: "kotlin.collections.HashMap")
    // KUU-556: LinkedHashMap is a real HashMap subclass (`LinkedHashMap.kt`),
    // matching the diff oracle (kotlinc-jvm: java.util.LinkedHashMap extends
    // java.util.HashMap), just as LinkedHashSet inherits HashSet.
    let linkedHashMapID = runtimeStableNominalTypeID(fqName: "kotlin.collections.LinkedHashMap")
    runtimeRegisterTypeEdge(childTypeID: mutableMapID, parentTypeID: mapID)
    runtimeRegisterTypeEdge(childTypeID: hashMapID, parentTypeID: mutableMapID)
    runtimeRegisterTypeEdge(childTypeID: linkedHashMapID, parentTypeID: hashMapID)
    return (mapID, mutableMapID, hashMapID, linkedHashMapID)
}()

let mapRuntimeTypeID: Int64 = mapRuntimeTypeIDs.map
let mutableMapRuntimeTypeID: Int64 = mapRuntimeTypeIDs.mutableMap
let hashMapRuntimeTypeID: Int64 = mapRuntimeTypeIDs.hashMap
let linkedHashMapRuntimeTypeID: Int64 = mapRuntimeTypeIDs.linkedHashMap
