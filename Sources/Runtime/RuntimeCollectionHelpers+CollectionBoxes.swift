private let mapEntryRuntimeTypeID: Int64 = {
    var hash: UInt64 = 0xCBF2_9CE4_8422_2325
    for byte in "kotlin.collections.Map.Entry".utf8 {
        hash ^= UInt64(byte)
        hash &*= 0x100_0000_01B3
    }
    let payloadMask: Int64 = (1 << 55) - 1
    let payload = Int64(bitPattern: hash) & payloadMask
    return payload == 0 ? 1 : payload
}()

private let mutableMapEntryRuntimeTypeID = runtimeStableNominalTypeID(
    fqName: "kotlin.collections.MutableMap.MutableEntry"
)

@inline(__always)
func runtimeMapEntryNew(key: Int, value: Int) -> Int {
    let raw = kk_pair_new(key, value)
    runtimeRegisterObjectType(rawValue: raw, classID: mapEntryRuntimeTypeID)
    runtimeRegisterMapEntryGetters(raw)
    return raw
}

@inline(__always)
func runtimeMapEntryNew(key: RuntimeValue, value: RuntimeValue) -> Int {
    let raw = runtimePairNew(firstValue: key, secondValue: value)
    runtimeRegisterObjectType(rawValue: raw, classID: mapEntryRuntimeTypeID)
    runtimeRegisterMapEntryGetters(raw)
    return raw
}

@inline(__always)
func runtimeMutableMapEntryNew(mapRaw: Int, key: Int, value: Int) -> Int {
    let raw = registerRuntimeObject(RuntimePairBox(first: key, second: value))
    if let pointer = UnsafeMutableRawPointer(bitPattern: raw),
       let pairBox = tryCast(pointer, to: RuntimePairBox.self) {
        pairBox.mutableMapRaw = mapRaw
        pairBox.mutableMapKey = key
    }
    runtimeRegisterObjectType(rawValue: raw, classID: mapEntryRuntimeTypeID)
    runtimeRegisterMapEntryGetters(raw)
    runtimeRegisterMutableMapEntryMethods(raw)
    return raw
}

@inline(__always)
func runtimeMutableMapEntryNew(mapRaw: Int, key: RuntimeValue, value: RuntimeValue) -> Int {
    let raw = registerRuntimeObject(RuntimePairBox(firstValue: key, secondValue: value))
    if let pointer = UnsafeMutableRawPointer(bitPattern: raw),
       let pairBox = tryCast(pointer, to: RuntimePairBox.self) {
        pairBox.mutableMapRaw = mapRaw
        pairBox.mutableMapKey = key.legacyRawValue
    }
    runtimeRegisterObjectType(rawValue: raw, classID: mapEntryRuntimeTypeID)
    runtimeRegisterMapEntryGetters(raw)
    runtimeRegisterMutableMapEntryMethods(raw)
    return raw
}

// Map.Entry has no methods; its source-declared key/value property getters
// occupy slots 0/1. Runtime-backed entries participate in the same interface
// dispatch as user implementations without changing Pair's public ABI.
private let runtimeMapEntryKeyGetter: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { raw, outThrown in
    outThrown?.pointee = 0
    return kk_pair_first(raw)
}

private let runtimeMapEntryValueGetter: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { raw, outThrown in
    outThrown?.pointee = 0
    return kk_pair_second(raw)
}

private func runtimeRegisterMapEntryGetters(_ raw: Int) {
    _ = kk_object_register_itable_iface(raw, Int(mapEntryRuntimeTypeID), 0)
    _ = kk_object_register_itable_method(raw, 0, 0, unsafeBitCast(runtimeMapEntryKeyGetter, to: Int.self))
    _ = kk_object_register_itable_method(raw, 0, 1, unsafeBitCast(runtimeMapEntryValueGetter, to: Int.self))
}

private let runtimeMutableMapEntrySetValue: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { raw, value, outThrown in
    kk_mutable_map_entry_setValue(raw, value, outThrown)
}

private func runtimeRegisterMutableMapEntryMethods(_ raw: Int) {
    // MutableEntry owns setValue (slot 0); inherited getters stay on Map.Entry.
    _ = kk_object_register_itable_iface(raw, Int(mutableMapEntryRuntimeTypeID), 1)
    _ = kk_object_register_itable_method(raw, 1, 0, unsafeBitCast(runtimeMutableMapEntrySetValue, to: Int.self))
}

@inline(__always)
func runtimeIsMapEntry(rawValue: Int) -> Bool {
    runtimeObjectTypeID(rawValue: rawValue) == mapEntryRuntimeTypeID
}

func runtimeListBox(from rawValue: Int) -> RuntimeListBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: rawValue), runtimeIsObjectPointer(ptr) else {
        return nil
    }
    if let box = tryCast(ptr, to: RuntimeListBox.self) {
        return box
    }
    if let deque = tryCast(ptr, to: RuntimeArrayDequeBox.self) {
        return RuntimeListBox(dequeViewOf: deque)
    }
    if let objectBox = tryCast(ptr, to: RuntimeObjectBox.self) {
        if let backingListBox = objectBox.backingListBox {
            return backingListBox
        }
        if let objectTypeID = runtimeObjectTypeID(rawValue: rawValue),
           runtimeIsAssignable(
               sourceTypeID: objectTypeID,
               targetTypeID: arrayListRuntimeTypeID
           )
        {
            let backingListBox = RuntimeListBox(elements: [])
            objectBox.backingListBox = backingListBox
            return backingListBox
        }
    }
    return nil
}

func runtimeMapBox(from rawValue: Int) -> RuntimeMapBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: rawValue), runtimeIsObjectPointer(ptr) else {
        return nil
    }
    if let mapBox = tryCast(ptr, to: RuntimeMapBox.self) {
        return mapBox
    }
    if let objectBox = tryCast(ptr, to: RuntimeObjectBox.self) {
        if let backingMapBox = objectBox.backingMapBox {
            return backingMapBox
        }
        if let objectTypeID = runtimeObjectTypeID(rawValue: rawValue) {
            registerSortedCollectionTypeEdgesOnce()
            if runtimeIsAssignable(
                sourceTypeID: objectTypeID,
                targetTypeID: treeMapRuntimeTypeID
            ) {
                // KUU-1361: TreeMap subclasses attach a naturally-ordered
                // backing on first access (treeSetRuntimeTypeID precedent).
                let backingMapBox = RuntimeMapBox(keys: [], values: [])
                backingMapBox.enableSorted(comparatorRaw: 0)
                objectBox.backingMapBox = backingMapBox
                return backingMapBox
            }
        }
    }
    return nil
}

func runtimeSetBox(from rawValue: Int) -> RuntimeSetBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: rawValue), runtimeIsObjectPointer(ptr) else {
        return nil
    }
    if let setBox = tryCast(ptr, to: RuntimeSetBox.self) {
        return setBox
    }
    if let objectBox = tryCast(ptr, to: RuntimeObjectBox.self) {
        if let backingSetBox = objectBox.backingSetBox {
            return backingSetBox
        }
        if let objectTypeID = runtimeObjectTypeID(rawValue: rawValue) {
            registerSortedCollectionTypeEdgesOnce()
            if runtimeIsAssignable(
                sourceTypeID: objectTypeID,
                targetTypeID: linkedHashSetRuntimeTypeID
            ) {
                let backingSetBox = RuntimeSetBox(elements: [])
                objectBox.backingSetBox = backingSetBox
                return backingSetBox
            }
            if runtimeIsAssignable(
                sourceTypeID: objectTypeID,
                targetTypeID: treeSetRuntimeTypeID
            ) {
                // KUU-1361: TreeSet subclasses whose init interception didn't
                // run attach a naturally-ordered backing on first access.
                let backingSetBox = RuntimeSetBox(elements: [])
                backingSetBox.enableSorted(comparatorRaw: 0)
                objectBox.backingSetBox = backingSetBox
                return backingSetBox
            }
        }
    }
    return nil
}

func runtimeArrayDequeBox(from rawValue: Int) -> RuntimeArrayDequeBox? {
    resolveRuntimeHandle(rawValue, as: RuntimeArrayDequeBox.self)
}

func runtimeCollectionElements(from rawValue: Int) -> [Int]? {
    if let listBox = runtimeListBox(from: rawValue) {
        return listBox.elements
    }
    if let setBox = runtimeSetBox(from: rawValue) {
        return setBox.elements
    }
    return nil
}

func runtimeCollectionValues(from rawValue: Int) -> [RuntimeValue]? {
    if let listBox = runtimeListBox(from: rawValue) {
        return listBox.values
    }
    if let setBox = runtimeSetBox(from: rawValue) {
        return setBox.values
    }
    return nil
}

func runtimeCollectionOrArrayElements(from rawValue: Int) -> [Int]? {
    if let elements = runtimeCollectionElements(from: rawValue) {
        return elements
    }
    // runtimeSequenceSourceElements covers RuntimeSequenceBox, source Sequence
    // objects (RuntimeObjectBox), List, Set, and arrays, while excluding
    // RuntimeObjectBox instances that are not actually arrays.
    if let elements = runtimeSequenceSourceElements(from: rawValue) {
        return elements
    }
    return nil
}

func runtimeCollectionOrArrayValues(from rawValue: Int) -> [RuntimeValue]? {
    if let values = runtimeCollectionValues(from: rawValue) {
        return values
    }
    if let values = runtimeSequenceSourceValues(from: rawValue) {
        return values
    }
    return nil
}

func runtimeIterableValues(from rawValue: Int) -> [RuntimeValue]? {
    if let values = runtimeCollectionValues(from: rawValue) {
        return values
    }
    if let indexingIterable = runtimeIndexingIterableBox(from: rawValue),
       let list = runtimeListBox(from: indexingIterable.listRaw)
    {
        return list.values.enumerated().map { index, element in
            RuntimeValue(raw: runtimeIndexedValueNew(index: index, value: element))
        }
    }
    // runtimeSequenceSourceValues handles RuntimeSequenceBox, source Sequence
    // objects, List, Set, and arrays without misclassifying RuntimeObjectBox.
    if let values = runtimeSequenceSourceValues(from: rawValue) {
        return values
    }
    // Kotlin source implementations of Iterable (for example
    // `String.asIterable()`) are ordinary objects with an Iterable itable, not
    // runtime collection boxes or Sequence objects. Drive their iterator
    // through the same dynamic interface used by generic for-loops.
    if let iteratorRaw = runtimeSourceIterableIterator(rawValue) {
        var values: [RuntimeValue] = []
        while kk_iterator_hasNext(iteratorRaw, nil) != 0 {
            let element = kk_iterator_next(iteratorRaw, nil)
            values.append(runtimeSourceIteratorValue(element, iteratorRaw: iteratorRaw))
        }
        return values
    }
    return nil
}
