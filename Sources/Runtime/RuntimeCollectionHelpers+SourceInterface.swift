private let runtimeCollectionSizeInterfaceTypeID = runtimeStableNominalTypeID(
    fqName: "kotlin.collections.Collection"
)
private let runtimeSetSizeInterfaceTypeID = runtimeStableNominalTypeID(
    fqName: "kotlin.collections.Set"
)
private let runtimeMapInterfaceTypeID = runtimeStableNominalTypeID(
    fqName: "kotlin.collections.Map"
)
private let runtimeSourceMapEntryInterfaceTypeID = runtimeStableNominalTypeID(
    fqName: "kotlin.collections.Map.Entry"
)
// These slots are the generated interface property getter slots in the current
// bundled layout: `size`'s slot is `Collection`/`Map`'s own vtableSize (its
// method-slot count), since KIRInterfacePropertyDispatch.swift lays property
// getters out right after an interface's own method slots.
//
// Collection's own vtable methods are isEmpty/contains/iterator/containsAll
// (4 slots) -- KSP-960 (source-backing Collection.random/randomOrNull as
// top-level extensions in Collections.kt) removed the two synthetic
// Collection.random/randomOrNull member registrations that previously
// contributed 2 more vtable slots here, so this dropped from 6 to 4.
private let runtimeCollectionSizeGetterSlot = 4
private let runtimeSetSizeGetterSlot = 3
private let runtimeCollectionIsEmptyMethodSlot = 0
private let runtimeListIteratorAtMethodSlot = 1
private let runtimeListSubListMethodSlot = 2
private let runtimeListIndexOfMethodSlot = 6
private let runtimeListLastIndexOfMethodSlot = 7
private let runtimeMutableListSubListMethodSlot = 0
private let runtimeMutableListSetMethodSlot = 1
// Map's own methods are isEmpty/get/containsKey/containsValue (slots 0-3).
// Its properties follow, ordered alphabetically: entries, keys, size, values.
let runtimeMapEntriesGetterSlot = 4
private let runtimeMapKeysGetterSlot = 5
private let runtimeMapSizeGetterSlot = 6
private let runtimeMapValuesGetterSlot = 7
private let runtimeMapIsEmptyMethodSlot = 0
private let runtimeMapGetMethodSlot = 1
private let runtimeMapContainsKeyMethodSlot = 2
private let runtimeMapContainsValueMethodSlot = 3
private let runtimeListGetInterfaceTypeID = runtimeStableNominalTypeID(
    fqName: "kotlin.collections.List"
)
let runtimeMutableListInterfaceTypeID = runtimeStableNominalTypeID(
    fqName: "kotlin.collections.MutableList"
)
let runtimeMutableCollectionInterfaceTypeID = runtimeStableNominalTypeID(
    fqName: "kotlin.collections.MutableCollection"
)
private let runtimeMutableSetInterfaceTypeID = runtimeStableNominalTypeID(
    fqName: "kotlin.collections.MutableSet"
)


private let runtimeMutableMapInterfaceTypeID = runtimeStableNominalTypeID(
    fqName: "kotlin.collections.MutableMap"
)
// MutableMap's own method slots are `put`/`putAll`/`remove`/`clear` in vtable
// order. Inherited Map members dispatch through the Map itable instead.
private let runtimeMutableMapPutMethodSlot = 0
private let runtimeMutableMapPutAllMethodSlot = 1
private let runtimeMutableMapRemoveMethodSlot = 2
private let runtimeMutableMapClearMethodSlot = 3

/// Source-defined Collection/Map implementations expose `size` through the
/// same dynamic interface-property getter table used by ordinary Kotlin code.
/// Built-in list/set/map boxes continue to use their direct fast paths.
@inline(__always)
func runtimeSourceCollectionSize(_ rawValue: Int) -> Int? {
    let fnPtr = kk_itable_lookup_dynamic(
        rawValue,
        Int(runtimeCollectionSizeInterfaceTypeID),
        runtimeCollectionSizeGetterSlot
    )
    guard fnPtr != 0 else { return nil }
    let fn = unsafeBitCast(
        fnPtr,
        to: (@convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int).self
    )
    var thrown = 0
    let result = fn(rawValue, &thrown)
    if thrown != 0 {
        runtimeStructuredPanic("Collection.size dispatch threw exception handle \(thrown)")
    }
    return result
}

/// Dispatch a source-defined Set.size override through Set's property getter
/// slot. This differs from Collection.size because Set redeclares the property.
@inline(__always)
func runtimeSourceSetSize(_ rawValue: Int) -> Int? {
    let fnPtr = kk_itable_lookup_dynamic(
        rawValue,
        Int(runtimeSetSizeInterfaceTypeID),
        runtimeSetSizeGetterSlot
    )
    guard fnPtr != 0 else { return nil }
    let fn = unsafeBitCast(
        fnPtr,
        to: (@convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int).self
    )
    var thrown = 0
    let result = fn(rawValue, &thrown)
    if thrown != 0 {
        runtimeStructuredPanic("Set.size dispatch threw exception handle \(thrown)")
    }
    return result
}

/// Dispatch a source-defined Collection.isEmpty override. A custom List may
/// implement this independently of size, so deriving it from size is not
/// equivalent to calling the member.
@inline(__always)
func runtimeSourceCollectionIsEmpty(_ rawValue: Int) -> Int? {
    runtimeSourceInterfaceCall0(
        rawValue,
        interfaceTypeID: runtimeCollectionSizeInterfaceTypeID,
        methodSlot: runtimeCollectionIsEmptyMethodSlot,
        context: "Collection.isEmpty dispatch"
    )
}

/// `List.get` occupies the first method slot in List's own interface table.
@inline(__always)
func runtimeSourceListGet(
    _ rawValue: Int,
    _ index: Int,
    outThrown: UnsafeMutablePointer<Int>?
) -> Int? {
    let fnPtr = kk_itable_lookup_dynamic(rawValue, Int(runtimeListGetInterfaceTypeID), 0)
    guard fnPtr != 0 else { return nil }
    let fn = unsafeBitCast(
        fnPtr,
        to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self
    )
    var thrown = 0
    let result = fn(rawValue, index, &thrown)
    if thrown != 0 {
        runtimePropagateThrownOrTrap(
            thrown,
            outThrown: outThrown,
            context: "List.get dispatch"
        )
    }
    return result
}

/// List.listIterator(index) is slot 1 of List's own methods.
@inline(__always)
func runtimeSourceListIteratorAt(
    _ rawValue: Int,
    index: Int,
    outThrown: UnsafeMutablePointer<Int>?
) -> Int? {
    runtimeSourceInterfaceCall1(
        rawValue,
        index,
        interfaceTypeID: runtimeListGetInterfaceTypeID,
        methodSlot: runtimeListIteratorAtMethodSlot,
        context: "List.listIterator(index) dispatch",
        outThrown: outThrown
    )
}

/// MutableList.subList(fromIndex, toIndex) delegates to the source method to
/// preserve the implementation's live view.
@inline(__always)
func runtimeSourceMutableListSubList(
    _ rawValue: Int,
    fromIndex: Int,
    toIndex: Int,
    outThrown: UnsafeMutablePointer<Int>?
) -> Int? {
    let fnPtr = kk_itable_lookup_dynamic(
        rawValue,
        Int(runtimeMutableListInterfaceTypeID),
        runtimeMutableListSubListMethodSlot
    )
    guard fnPtr != 0 else { return nil }
    let fn = unsafeBitCast(
        fnPtr,
        to: (@convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int).self
    )
    return fn(rawValue, fromIndex, toIndex, outThrown)
}

@inline(__always)
func runtimeSourceListSubList(
    _ rawValue: Int,
    fromIndex: Int,
    toIndex: Int,
    outThrown: UnsafeMutablePointer<Int>?
) -> Int? {
    let fnPtr = kk_itable_lookup_dynamic(
        rawValue,
        Int(runtimeListGetInterfaceTypeID),
        runtimeListSubListMethodSlot
    )
    guard fnPtr != 0 else { return nil }
    let fn = unsafeBitCast(
        fnPtr,
        to: (@convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int).self
    )
    return fn(rawValue, fromIndex, toIndex, outThrown)
}

@inline(__always)
func runtimeSourceMutableListSet(
    _ rawValue: Int,
    index: Int,
    element: Int,
    outThrown: UnsafeMutablePointer<Int>?
) -> Int? {
    let fnPtr = kk_itable_lookup_dynamic(
        rawValue,
        Int(runtimeMutableListInterfaceTypeID),
        runtimeMutableListSetMethodSlot
    )
    guard fnPtr != 0 else { return nil }
    let fn = unsafeBitCast(
        fnPtr,
        to: (@convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int).self
    )
    return fn(rawValue, index, element, outThrown)
}

/// Calls the source `MutableCollection.add` implementation through its own
/// interface table, whose methods start at slot zero.
@inline(__always)
func runtimeSourceMutableCollectionAdd(
    _ rawValue: Int,
    _ element: Int,
    outThrown: UnsafeMutablePointer<Int>? = nil
) -> Int? {
    let fnPtr = kk_itable_lookup_dynamic(
        rawValue,
        Int(runtimeMutableCollectionInterfaceTypeID),
        0
    )
    guard fnPtr != 0 else { return nil }
    let fn = unsafeBitCast(
        fnPtr,
        to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self
    )
    var thrown = 0
    let result = fn(rawValue, element, &thrown)
    if thrown != 0 {
        runtimePropagateThrownOrTrap(
            thrown,
            outThrown: outThrown,
            context: "MutableCollection.add dispatch"
        )
    }
    return result
}

@inline(__always)
func runtimeSourceMutableSetAdd(
    _ rawValue: Int,
    _ element: Int,
    outThrown: UnsafeMutablePointer<Int>?
) -> Int? {
    let fnPtr = kk_itable_lookup_dynamic(rawValue, Int(runtimeMutableSetInterfaceTypeID), 0)
    guard fnPtr != 0 else { return nil }
    let fn = unsafeBitCast(
        fnPtr,
        to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self
    )
    var thrown = 0
    let result = fn(rawValue, element, &thrown)
    if thrown != 0 {
        runtimePropagateThrownOrTrap(
            thrown,
            outThrown: outThrown,
            context: "MutableSet.add dispatch"
        )
    }
    return result
}

@inline(__always)
func runtimeSourceInterfaceCall0(
    _ rawValue: Int,
    interfaceTypeID: Int64,
    methodSlot: Int,
    context: String,
    outThrown: UnsafeMutablePointer<Int>? = nil
) -> Int? {
    let fnPtr = kk_itable_lookup_dynamic(rawValue, Int(interfaceTypeID), methodSlot)
    guard fnPtr != 0 else { return nil }
    let fn = unsafeBitCast(
        fnPtr,
        to: (@convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int).self
    )
    var thrown = 0
    let result = fn(rawValue, &thrown)
    if thrown != 0 {
        runtimePropagateThrownOrTrap(thrown, outThrown: outThrown, context: context)
    }
    return result
}

@inline(__always)
func runtimeSourceInterfaceCall1(
    _ rawValue: Int,
    _ argument: Int,
    interfaceTypeID: Int64,
    methodSlot: Int,
    context: String,
    outThrown: UnsafeMutablePointer<Int>? = nil
) -> Int? {
    let fnPtr = kk_itable_lookup_dynamic(rawValue, Int(interfaceTypeID), methodSlot)
    guard fnPtr != 0 else { return nil }
    let fn = unsafeBitCast(
        fnPtr,
        to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self
    )
    var thrown = 0
    let result = fn(rawValue, argument, &thrown)
    if thrown != 0 {
        runtimePropagateThrownOrTrap(thrown, outThrown: outThrown, context: context)
    }
    return result
}

@inline(__always)
func runtimeSourceMapSize(_ rawValue: Int) -> Int? {
    guard let result = runtimeSourceMapProperty(
        rawValue,
        methodSlot: runtimeMapSizeGetterSlot
    ) else {
        return nil
    }
    return result
}

@inline(__always)
func runtimeSourceMapProperty(_ rawValue: Int, methodSlot: Int) -> Int? {
    let fnPtr = kk_itable_lookup_dynamic(rawValue, Int(runtimeMapInterfaceTypeID), methodSlot)
    guard fnPtr != 0 else { return nil }
    let fn = unsafeBitCast(
        fnPtr,
        to: (@convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int).self
    )
    var thrown = 0
    let result = fn(rawValue, &thrown)
    if thrown != 0 {
        runtimeStructuredPanic("Map property dispatch threw exception handle \(thrown)")
    }
    return result
}

@inline(__always)
func runtimeSourceMapIsEmpty(_ rawValue: Int) -> Int? {
    let fnPtr = kk_itable_lookup_dynamic(
        rawValue,
        Int(runtimeMapInterfaceTypeID),
        runtimeMapIsEmptyMethodSlot
    )
    guard fnPtr != 0 else { return nil }
    let fn = unsafeBitCast(
        fnPtr,
        to: (@convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int).self
    )
    var thrown = 0
    let result = fn(rawValue, &thrown)
    if thrown != 0 {
        runtimeStructuredPanic("Map.isEmpty dispatch threw exception handle \(thrown)")
    }
    return result
}

@inline(__always)
func runtimeSourceMapGet(_ rawValue: Int, key: Int) -> Int? {
    let fnPtr = kk_itable_lookup_dynamic(
        rawValue,
        Int(runtimeMapInterfaceTypeID),
        runtimeMapGetMethodSlot
    )
    guard fnPtr != 0 else { return nil }
    let fn = unsafeBitCast(
        fnPtr,
        to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self
    )
    var thrown = 0
    let result = fn(rawValue, key, &thrown)
    if thrown != 0 {
        runtimeStructuredPanic("Map.get dispatch threw exception handle \(thrown)")
    }
    return result
}

/// Map.containsKey occupies the third method slot in Map's own interface
/// table, after isEmpty/get.
@inline(__always)
func runtimeSourceMapContainsKey(_ rawValue: Int, key: Int) -> Int? {
    let fnPtr = kk_itable_lookup_dynamic(
        rawValue,
        Int(runtimeMapInterfaceTypeID),
        runtimeMapContainsKeyMethodSlot
    )
    guard fnPtr != 0 else { return nil }
    let fn = unsafeBitCast(
        fnPtr,
        to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self
    )
    var thrown = 0
    let result = fn(rawValue, key, &thrown)
    if thrown != 0 {
        runtimeStructuredPanic("Map.containsKey dispatch threw exception handle \(thrown)")
    }
    return result
}

/// Map.containsValue occupies the fourth method slot in Map's own interface
/// table, after isEmpty/get/containsKey.
@inline(__always)
func runtimeSourceMapContainsValue(_ rawValue: Int, value: Int) -> Int? {
    let fnPtr = kk_itable_lookup_dynamic(
        rawValue,
        Int(runtimeMapInterfaceTypeID),
        runtimeMapContainsValueMethodSlot
    )
    guard fnPtr != 0 else { return nil }
    let fn = unsafeBitCast(
        fnPtr,
        to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self
    )
    var thrown = 0
    let result = fn(rawValue, value, &thrown)
    if thrown != 0 {
        runtimeStructuredPanic("Map.containsValue dispatch threw exception handle \(thrown)")
    }
    return result
}

/// List.indexOf occupies slot 6 in List's own interface table; the override's
/// bridge answers the JVM default (-1) for arguments its parameter rejects.
@inline(__always)
func runtimeSourceListIndexOf(
    _ rawValue: Int,
    element: Int,
    outThrown: UnsafeMutablePointer<Int>?
) -> Int? {
    runtimeSourceInterfaceCall1(
        rawValue,
        element,
        interfaceTypeID: runtimeListGetInterfaceTypeID,
        methodSlot: runtimeListIndexOfMethodSlot,
        context: "List.indexOf dispatch",
        outThrown: outThrown
    )
}

/// List.lastIndexOf occupies slot 7 in List's own interface table.
@inline(__always)
func runtimeSourceListLastIndexOf(
    _ rawValue: Int,
    element: Int,
    outThrown: UnsafeMutablePointer<Int>?
) -> Int? {
    runtimeSourceInterfaceCall1(
        rawValue,
        element,
        interfaceTypeID: runtimeListGetInterfaceTypeID,
        methodSlot: runtimeListLastIndexOfMethodSlot,
        context: "List.lastIndexOf dispatch",
        outThrown: outThrown
    )
}

@inline(__always)
func runtimeSourceMapEntries(_ rawValue: Int) -> Int? {
    runtimeSourceMapProperty(rawValue, methodSlot: runtimeMapEntriesGetterSlot)
}

@inline(__always)
func runtimeSourceMapKeys(_ rawValue: Int) -> Int? {
    runtimeSourceMapProperty(rawValue, methodSlot: runtimeMapKeysGetterSlot)
}

@inline(__always)
func runtimeSourceMapValues(_ rawValue: Int) -> Int? {
    runtimeSourceMapProperty(rawValue, methodSlot: runtimeMapValuesGetterSlot)
}

@inline(__always)
func runtimeSourceInterfaceCall2(
    _ rawValue: Int,
    _ argument1: Int,
    _ argument2: Int,
    interfaceTypeID: Int64,
    methodSlot: Int,
    context: String,
    outThrown: UnsafeMutablePointer<Int>? = nil
) -> Int? {
    let fnPtr = kk_itable_lookup_dynamic(rawValue, Int(interfaceTypeID), methodSlot)
    guard fnPtr != 0 else { return nil }
    let fn = unsafeBitCast(
        fnPtr,
        to: (@convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int).self
    )
    var thrown = 0
    let result = fn(rawValue, argument1, argument2, &thrown)
    if thrown != 0 {
        runtimePropagateThrownOrTrap(thrown, outThrown: outThrown, context: context)
    }
    return result
}

@inline(__always)
func runtimeSourceMutableMapPut(
    _ rawValue: Int,
    key: Int,
    value: Int,
    outThrown: UnsafeMutablePointer<Int>?
) -> Int? {
    runtimeSourceInterfaceCall2(
        rawValue,
        key,
        value,
        interfaceTypeID: runtimeMutableMapInterfaceTypeID,
        methodSlot: runtimeMutableMapPutMethodSlot,
        context: "MutableMap.put dispatch",
        outThrown: outThrown
    )
}

@inline(__always)
func runtimeSourceMutableMapPutAll(
    _ rawValue: Int,
    otherMapRaw: Int,
    outThrown: UnsafeMutablePointer<Int>?
) -> Int? {
    runtimeSourceInterfaceCall1(
        rawValue,
        otherMapRaw,
        interfaceTypeID: runtimeMutableMapInterfaceTypeID,
        methodSlot: runtimeMutableMapPutAllMethodSlot,
        context: "MutableMap.putAll dispatch",
        outThrown: outThrown
    )
}

@inline(__always)
func runtimeSourceMutableMapRemove(
    _ rawValue: Int,
    key: Int,
    outThrown: UnsafeMutablePointer<Int>?
) -> Int? {
    runtimeSourceInterfaceCall1(
        rawValue,
        key,
        interfaceTypeID: runtimeMutableMapInterfaceTypeID,
        methodSlot: runtimeMutableMapRemoveMethodSlot,
        context: "MutableMap.remove dispatch",
        outThrown: outThrown
    )
}

@inline(__always)
func runtimeSourceMutableMapClear(
    _ rawValue: Int,
    outThrown: UnsafeMutablePointer<Int>?
) -> Int? {
    runtimeSourceInterfaceCall0(
        rawValue,
        interfaceTypeID: runtimeMutableMapInterfaceTypeID,
        methodSlot: runtimeMutableMapClearMethodSlot,
        context: "MutableMap.clear dispatch",
        outThrown: outThrown
    )
}


/// Map.Entry declares no methods of its own; key/value getters occupy slots
/// zero and one. Reading through the interface preserves equality symmetry
/// between runtime-backed entries and source-backed unmodifiable wrappers.
func runtimeSourceMapEntryValues(_ rawValue: Int) -> (key: Int, value: Int)? {
    guard let pointer = UnsafeMutableRawPointer(bitPattern: rawValue),
          runtimeIsObjectPointer(pointer), tryCast(pointer, to: RuntimeObjectBox.self) != nil,
          let key = runtimeSourceInterfaceCall0(
            rawValue, interfaceTypeID: runtimeSourceMapEntryInterfaceTypeID, methodSlot: 0,
            context: "Map.Entry.key dispatch"
          ),
          let value = runtimeSourceInterfaceCall0(
            rawValue, interfaceTypeID: runtimeSourceMapEntryInterfaceTypeID, methodSlot: 1,
            context: "Map.Entry.value dispatch"
          ) else { return nil }
    return (key, value)
}
