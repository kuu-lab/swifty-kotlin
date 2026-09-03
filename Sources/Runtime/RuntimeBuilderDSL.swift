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

@_cdecl("__kk_build_list")
public func __kk_build_list(_ fnRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    __kkBuildList(capacity: 0, fnRaw: fnRaw, outThrown: outThrown)
}

private func __kkBuildList(
    capacity: Int,
    fnRaw: Int,
    outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard fnRaw != 0 else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_build_list called with null function pointer")
    }
    let listPtr = registerRuntimeObject(RuntimeListBox(capacity: capacity), typeID: listRuntimeTypeID)
    var thrown = 0
    _ = kk_function_invoke(fnRaw, listPtr, &thrown)
    if thrown != 0 {
        outThrown?.pointee = thrown
    }
    runtimeListBox(from: listPtr)?.freeze()
    return listPtr
}

@_cdecl("__kk_build_list_with_capacity")
public func __kk_build_list_with_capacity(
    _ capacity: Int,
    _ fnRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    if capacity < 0 {
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(message: "capacity must be non-negative.")
        return 0
    }
    return __kkBuildList(capacity: capacity, fnRaw: fnRaw, outThrown: outThrown)
}

@_cdecl("__kk_build_set")
public func __kk_build_set(_ fnPtr: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    __kkBuildSet(capacity: 0, fnPtr: fnPtr, outThrown: outThrown)
}

private func __kkBuildSet(
    capacity: Int,
    fnPtr: Int,
    outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard fnPtr != 0 else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_build_set called with null function pointer")
    }
    let setPtr = registerRuntimeObject(RuntimeSetBox(capacity: capacity))
    var thrown = 0
    _ = kk_function_invoke(fnPtr, setPtr, &thrown)

    if thrown != 0 {
        outThrown?.pointee = thrown
    }
    runtimeSetBox(from: setPtr)?.freeze()
    return setPtr
}

@_cdecl("__kk_build_set_with_capacity")
public func __kk_build_set_with_capacity(
    _ capacity: Int,
    _ fnPtr: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    if capacity < 0 {
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(message: "capacity must be non-negative.")
        return 0
    }
    return __kkBuildSet(capacity: capacity, fnPtr: fnPtr, outThrown: outThrown)
}

@_cdecl("__kk_build_map")
public func __kk_build_map(_ fnPtr: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    __kkBuildMap(capacity: 0, fnPtr: fnPtr, outThrown: outThrown)
}

private func __kkBuildMap(
    capacity: Int,
    fnPtr: Int,
    outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard fnPtr != 0 else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_build_map called with null function pointer")
    }
    let mapPtr = registerRuntimeObject(RuntimeMapBox(capacity: capacity), typeID: mutableMapRuntimeTypeID)
    var thrown = 0
    _ = kk_function_invoke(fnPtr, mapPtr, &thrown)

    if thrown != 0 {
        outThrown?.pointee = thrown
    }
    runtimeMapBox(from: mapPtr)?.freeze()
    return mapPtr
}

@_cdecl("__kk_build_map_with_capacity")
public func __kk_build_map_with_capacity(
    _ capacity: Int,
    _ fnPtr: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    if capacity < 0 {
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(message: "capacity must be non-negative.")
        return 0
    }
    return __kkBuildMap(capacity: capacity, fnPtr: fnPtr, outThrown: outThrown)
}
