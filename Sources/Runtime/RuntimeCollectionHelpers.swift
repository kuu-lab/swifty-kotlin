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

let listRuntimeTypeID: Int64 = {
    let id = runtimeStableNominalTypeID(fqName: "kotlin.collections.List")
    runtimeRegisterTypeEdge(childTypeID: id, parentTypeID: collectionRuntimeTypeID)
    return id
}()

private let mutableListRuntimeTypeID: Int64 = {
    let id = runtimeStableNominalTypeID(fqName: "kotlin.collections.MutableList")
    runtimeRegisterTypeEdge(childTypeID: id, parentTypeID: listRuntimeTypeID)
    return id
}()

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

let setRuntimeTypeID: Int64 = {
    let id = runtimeStableNominalTypeID(fqName: "kotlin.collections.Set")
    runtimeRegisterTypeEdge(childTypeID: id, parentTypeID: collectionRuntimeTypeID)
    return id
}()

/// Nominal identity for source-backed `kotlin.collections.HashSet` instances.
/// Ordinary Set factories keep using `setRuntimeTypeID`; only HashSet
/// constructors opt into this more specific identity.
let hashSetRuntimeTypeID: Int64 = {
    let id = runtimeStableNominalTypeID(fqName: "kotlin.collections.HashSet")
    runtimeRegisterTypeEdge(
        childTypeID: id,
        parentTypeID: runtimeStableNominalTypeID(fqName: "kotlin.collections.MutableSet")
    )
    runtimeRegisterTypeEdge(
        childTypeID: id,
        parentTypeID: runtimeStableNominalTypeID(fqName: "kotlin.collections.AbstractMutableSet")
    )
    runtimeRegisterTypeEdge(childTypeID: id, parentTypeID: setRuntimeTypeID)
    return id
}()

/// Nominal identity for `kotlin.collections.LinkedHashSet`.
///
/// User-defined subclasses of LinkedHashSet are allocated as RuntimeObjectBox
/// instances. Keep the nominal ID available so runtimeSetBox can lazily attach
/// their storage even when library superclass initializers are not emitted.
///
/// BUG-254: the mutable set factories and the LinkedHashSet constructors now tag
/// their box with this ID, so it needs parent edges the way
/// `hashSetRuntimeTypeID` has them -- without them `is MutableSet<*>` and
/// `is Set<*>` would answer false on a box carrying this tag.
/// `LinkedHashSet.kt` declares `LinkedHashSet<E> : MutableSet<E>`. The runtime
/// identity follows that source-backed public hierarchy; the concrete class
/// remains separate from `HashSet` because the factory/runtime representation
/// does not expose a nominal HashSet superclass edge.
let linkedHashSetRuntimeTypeID: Int64 = {
    let id = runtimeStableNominalTypeID(fqName: "kotlin.collections.LinkedHashSet")
    runtimeRegisterTypeEdge(
        childTypeID: id,
        parentTypeID: runtimeStableNominalTypeID(fqName: "kotlin.collections.MutableSet")
    )
    runtimeRegisterTypeEdge(childTypeID: id, parentTypeID: setRuntimeTypeID)
    return id
}()

/// KUU-1361: java.util sorted-collection nominal identities. Boxes are
/// tagged `treeSetRuntimeTypeID`/`treeMapRuntimeTypeID`; the interface IDs
/// carry the assignability edges that let `is SortedSet<*>` /
/// `is NavigableMap<*, *>` answer true on those tags.
let sortedSetRuntimeTypeID: Int64 = runtimeStableNominalTypeID(fqName: "java.util.SortedSet")

let navigableSetRuntimeTypeID: Int64 = runtimeStableNominalTypeID(fqName: "java.util.NavigableSet")

/// Nominal identity for `java.util.TreeSet`. Source-allocated subclasses
/// arrive as RuntimeObjectBox instances; runtimeSetBox lazily attaches a
/// sorted backing box the same way LinkedHashSet subclasses attach theirs.
let treeSetRuntimeTypeID: Int64 = runtimeStableNominalTypeID(fqName: "java.util.TreeSet")

let sortedMapRuntimeTypeID: Int64 = runtimeStableNominalTypeID(fqName: "java.util.SortedMap")

let navigableMapRuntimeTypeID: Int64 = runtimeStableNominalTypeID(fqName: "java.util.NavigableMap")

/// Nominal identity for `java.util.TreeMap`; see `treeSetRuntimeTypeID` for
/// the lazy-attach path that relies on this ID.
let treeMapRuntimeTypeID: Int64 = runtimeStableNominalTypeID(fqName: "java.util.TreeMap")

/// Installs the `java.util` sorted-collection supertype edges:
/// `TreeSet : NavigableSet : SortedSet : MutableSet/Set` and
/// `TreeMap : NavigableMap : SortedMap : MutableMap`, plus the
/// AbstractMutableSet/AbstractMutableMap edges Kotlin source declares.
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
    // java.util.HashMap) -- unlike hashSetRuntimeTypeID/linkedHashSetRuntimeTypeID,
    // which are still siblings under Set (docs/stdlib-pipeline.md §13-8).
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
