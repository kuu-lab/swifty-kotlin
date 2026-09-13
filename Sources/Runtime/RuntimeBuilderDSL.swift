// Source-backed collection builders allocate a mutable builder, run the
// receiver lambda, and freeze that same box before returning it as read-only.
// The capacity is a reservation hint; the Kotlin layer validates negatives.

@_cdecl("__kk_builder_list_new")
public func __kk_builder_list_new(_ capacity: Int) -> Int {
    registerRuntimeObject(RuntimeListBox(capacity: capacity), typeID: listRuntimeTypeID)
}

@_cdecl("__kk_builder_set_new")
public func __kk_builder_set_new(_ capacity: Int) -> Int {
    registerRuntimeObject(RuntimeSetBox(capacity: capacity))
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

// The `__kk_build_list` / `__kk_build_set` / `__kk_build_map` entry points (and
// their `_with_capacity` variants) were removed together with their lowering
// rewrites: RF-LOWER-CALL-004 (list), -005 (set), -006 (map).  `buildList` /
// `buildSet` / `buildMap` are implemented in `CollectionBuilders.kt` on top of
// the `__kk_builder_*_new` / `__kk_builder_*_freeze` bridges above, which own
// the capacity validation (`require(capacity >= 0)`) the removed helpers had.
