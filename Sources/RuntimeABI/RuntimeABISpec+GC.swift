private let abi = RuntimeABISectionBuilder("GC")

public extension RuntimeABISpec {
    static let gcFunctions: [RuntimeABIFunctionSpec] = [
        abi.th("kk_register_frame_map", "functionID:uint32 mapPtr:nullableConstRawPointer", ret: .void),
        abi.th("kk_push_frame", "functionID:uint32 frameBase:nullableOpaquePointer", ret: .void),
        abi.th("kk_pop_frame", ret: .void),
        abi.nt("kk_register_global_root", "slot:nullableOpaquePointer"),
        abi.nt("kk_gc_push_root_frame", "rootSlots:nullableOpaquePointer rootCount"),
        abi.nt("kk_gc_root_store", "slot:nullableOpaquePointer value"),
        abi.nt("kk_gc_frame_leave", "returnValue hasRootFrame"),
        abi.th("kk_register_coroutine_root", "value:nullableOpaquePointer", ret: .void),
        abi.th("kk_unregister_coroutine_root", "value:nullableOpaquePointer", ret: .void),
        abi.th("kk_runtime_heap_object_count", ret: .uint32),
        abi.th("kk_runtime_force_reset", ret: .void),
    ]
}
