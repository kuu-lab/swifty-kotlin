// The capacity is a reservation hint; the Kotlin layer validates negatives.

// A frozen builder keeps the same mutable interface identity but rejects writes.
private let runtimeListBuilderTypeID: Int64 = {
    let id = runtimeStableNominalTypeID(fqName: "kotlin.collections.__KSwiftKListBuilder")
    runtimeRegisterTypeEdge(childTypeID: id, parentTypeID: mutableListRuntimeTypeID)
    runtimeRegisterTypeEdge(
        childTypeID: id,
        parentTypeID: runtimeStableNominalTypeID(fqName: "kotlin.collections.RandomAccess")
    )
    return id
}()

// A frozen builder still implements MutableSet and rejects writes at runtime.
// Keep that conformance without claiming HashSet or LinkedHashSet identity.
private let runtimeSetBuilderTypeID: Int64 = {
    let id = runtimeStableNominalTypeID(fqName: "kotlin.collections.__KSwiftKSetBuilder")
    runtimeRegisterTypeEdge(
        childTypeID: id,
        parentTypeID: runtimeStableNominalTypeID(fqName: "kotlin.collections.MutableSet")
    )
    runtimeRegisterTypeEdge(childTypeID: id, parentTypeID: setRuntimeTypeID)
    return id
}()

@_cdecl("__kk_builder_list_new")
public func __kk_builder_list_new(_ capacity: Int) -> Int {
    registerRuntimeObject(RuntimeListBox(capacity: capacity), typeID: runtimeListBuilderTypeID)
}

@_cdecl("__kk_builder_set_new")
public func __kk_builder_set_new(_ capacity: Int) -> Int {
    registerRuntimeObject(RuntimeSetBox(capacity: capacity), typeID: runtimeSetBuilderTypeID)
}

@_cdecl("__kk_builder_map_new")
public func __kk_builder_map_new(_ capacity: Int) -> Int {
    registerRuntimeObject(RuntimeMapBox(capacity: capacity), typeID: mutableMapRuntimeTypeID)
}

@_cdecl("__kk_builder_list_freeze")
public func __kk_builder_list_freeze(_ raw: Int) -> Int {
    runtimeListBox(from: raw)?.freeze()
    return raw
}

@_cdecl("__kk_builder_set_freeze")
public func __kk_builder_set_freeze(_ raw: Int) -> Int {
    runtimeSetBox(from: raw)?.freeze()
    return raw
}

@_cdecl("__kk_builder_map_freeze")
public func __kk_builder_map_freeze(_ raw: Int) -> Int {
    runtimeMapBox(from: raw)?.freeze()
    return raw
}
