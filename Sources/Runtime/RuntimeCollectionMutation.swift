// Keep the legacy nonthrowing symbols ABI-compatible. New source declarations
// use these entry points so frozen boxes and throwing overrides reach Kotlin catches.

func runtimeThrowIfReadOnlyList(_ list: RuntimeListBox, _ outThrown: UnsafeMutablePointer<Int>?) -> Bool {
    guard list.isEffectivelyReadOnly else { return false }
    runtimeSetThrown(outThrown, runtimeAllocateUnsupportedOperationException(message: nil))
    return true
}

private func runtimeThrowIfReadOnlyCollection(_ raw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Bool {
    if let list = runtimeListBox(from: raw) {
        return runtimeThrowIfReadOnlyList(list, outThrown)
    }
    guard runtimeSetBox(from: raw)?.isEffectivelyReadOnly == true else { return false }
    runtimeSetThrown(outThrown, runtimeAllocateUnsupportedOperationException(message: nil))
    return true
}

@_cdecl("__kk_mutable_collection_add_checked")
public func kk_mutable_collection_add_checked(_ raw: Int, _ argument: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard !runtimeThrowIfReadOnlyCollection(raw, outThrown) else { return 0 }
    if runtimeListBox(from: raw) == nil, runtimeSetBox(from: raw) == nil {
        return runtimeSourceInterfaceCall1(
            raw, argument,
            interfaceTypeID: runtimeMutableCollectionInterfaceTypeID,
            methodSlot: 0,
            context: "MutableCollection.add dispatch",
            outThrown: outThrown
        ) ?? kk_box_bool(0)
    }
    return kk_mutable_collection_add(raw, argument)
}

@_cdecl("__kk_mutable_collection_addAll_checked")
public func kk_mutable_collection_addAll_checked(_ raw: Int, _ argument: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard !runtimeThrowIfReadOnlyCollection(raw, outThrown) else { return 0 }
    if runtimeListBox(from: raw) == nil, runtimeSetBox(from: raw) == nil {
        return runtimeSourceInterfaceCall1(
            raw, argument,
            interfaceTypeID: runtimeMutableCollectionInterfaceTypeID,
            methodSlot: 1,
            context: "MutableCollection.addAll dispatch",
            outThrown: outThrown
        ) ?? kk_box_bool(0)
    }
    return kk_mutable_collection_addAll(raw, argument)
}

@_cdecl("__kk_mutable_collection_clear_checked")
public func kk_mutable_collection_clear_checked(_ raw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard !runtimeThrowIfReadOnlyCollection(raw, outThrown) else { return 0 }
    if runtimeListBox(from: raw) == nil, runtimeSetBox(from: raw) == nil {
        return runtimeSourceInterfaceCall0(
            raw,
            interfaceTypeID: runtimeMutableCollectionInterfaceTypeID,
            methodSlot: 2,
            context: "MutableCollection.clear dispatch",
            outThrown: outThrown
        ) ?? 0
    }
    return kk_mutable_collection_clear(raw)
}

@_cdecl("__kk_mutable_collection_remove_checked")
public func kk_mutable_collection_remove_checked(_ raw: Int, _ argument: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard !runtimeThrowIfReadOnlyCollection(raw, outThrown) else { return 0 }
    if runtimeListBox(from: raw) == nil, runtimeSetBox(from: raw) == nil {
        return runtimeSourceInterfaceCall1(
            raw, argument,
            interfaceTypeID: runtimeMutableCollectionInterfaceTypeID,
            methodSlot: 3,
            context: "MutableCollection.remove dispatch",
            outThrown: outThrown
        ) ?? kk_box_bool(0)
    }
    return kk_mutable_collection_remove(raw, argument)
}

@_cdecl("__kk_mutable_collection_removeAll_checked")
public func kk_mutable_collection_removeAll_checked(_ raw: Int, _ argument: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard !runtimeThrowIfReadOnlyCollection(raw, outThrown) else { return 0 }
    if runtimeListBox(from: raw) == nil, runtimeSetBox(from: raw) == nil {
        return runtimeSourceInterfaceCall1(
            raw, argument,
            interfaceTypeID: runtimeMutableCollectionInterfaceTypeID,
            methodSlot: 4,
            context: "MutableCollection.removeAll dispatch",
            outThrown: outThrown
        ) ?? kk_box_bool(0)
    }
    return kk_mutable_collection_removeAll(raw, argument)
}

@_cdecl("__kk_mutable_collection_retainAll_checked")
public func kk_mutable_collection_retainAll_checked(_ raw: Int, _ argument: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard !runtimeThrowIfReadOnlyCollection(raw, outThrown) else { return 0 }
    if runtimeListBox(from: raw) == nil, runtimeSetBox(from: raw) == nil {
        return runtimeSourceInterfaceCall1(
            raw, argument,
            interfaceTypeID: runtimeMutableCollectionInterfaceTypeID,
            methodSlot: 5,
            context: "MutableCollection.retainAll dispatch",
            outThrown: outThrown
        ) ?? kk_box_bool(0)
    }
    return kk_mutable_collection_retainAll(raw, argument)
}

@_cdecl("__kk_mutable_list_addAll_checked")
public func kk_mutable_list_addAll_checked(_ raw: Int, _ argument: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard !runtimeThrowIfReadOnlyCollection(raw, outThrown) else { return 0 }
    if runtimeListBox(from: raw) == nil {
        return runtimeSourceInterfaceCall1(
            raw, argument,
            interfaceTypeID: runtimeMutableListInterfaceTypeID,
            methodSlot: 4,
            context: "MutableList.addAll dispatch",
            outThrown: outThrown
        ) ?? kk_box_bool(0)
    }
    return kk_mutable_list_addAll(raw, argument)
}

@_cdecl("__kk_mutable_list_remove_checked")
public func kk_mutable_list_remove_checked(_ raw: Int, _ argument: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard !runtimeThrowIfReadOnlyCollection(raw, outThrown) else { return 0 }
    if runtimeListBox(from: raw) == nil {
        return runtimeSourceInterfaceCall1(
            raw, argument,
            interfaceTypeID: runtimeMutableListInterfaceTypeID,
            methodSlot: 7,
            context: "MutableList.remove dispatch",
            outThrown: outThrown
        ) ?? kk_box_bool(0)
    }
    return kk_mutable_list_remove(raw, argument)
}

@_cdecl("__kk_mutable_list_clear_checked")
public func kk_mutable_list_clear_checked(_ raw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard !runtimeThrowIfReadOnlyCollection(raw, outThrown) else { return 0 }
    if runtimeListBox(from: raw) == nil {
        return runtimeSourceInterfaceCall0(
            raw,
            interfaceTypeID: runtimeMutableListInterfaceTypeID,
            methodSlot: 8,
            context: "MutableList.clear dispatch",
            outThrown: outThrown
        ) ?? 0
    }
    return kk_mutable_list_clear(raw)
}

@_cdecl("__kk_mutable_list_removeAll_checked")
public func kk_mutable_list_removeAll_checked(_ raw: Int, _ argument: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard !runtimeThrowIfReadOnlyCollection(raw, outThrown) else { return 0 }
    if runtimeListBox(from: raw) == nil {
        return runtimeSourceInterfaceCall1(
            raw, argument,
            interfaceTypeID: runtimeMutableListInterfaceTypeID,
            methodSlot: 9,
            context: "MutableList.removeAll dispatch",
            outThrown: outThrown
        ) ?? kk_box_bool(0)
    }
    return kk_mutable_list_removeAll(raw, argument)
}

@_cdecl("__kk_mutable_list_retainAll_checked")
public func kk_mutable_list_retainAll_checked(_ raw: Int, _ argument: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard !runtimeThrowIfReadOnlyCollection(raw, outThrown) else { return 0 }
    if runtimeListBox(from: raw) == nil {
        return runtimeSourceInterfaceCall1(
            raw, argument,
            interfaceTypeID: runtimeMutableListInterfaceTypeID,
            methodSlot: 10,
            context: "MutableList.retainAll dispatch",
            outThrown: outThrown
        ) ?? kk_box_bool(0)
    }
    return kk_mutable_list_retainAll(raw, argument)
}
