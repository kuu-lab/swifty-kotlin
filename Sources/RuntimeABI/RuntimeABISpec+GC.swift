private let abi = RuntimeABISectionBuilder("GC")

public extension RuntimeABISpec {
    static let gcFunctions: [RuntimeABIFunctionSpec] = [
        abi.th("kk_register_frame_map", "functionID:uint32 mapPtr:nullableConstRawPointer", ret: .void),
        abi.th("kk_push_frame", "functionID:uint32 frameBase:nullableOpaquePointer", ret: .void),
        abi.th("kk_pop_frame", ret: .void),
        abi.th("kk_register_coroutine_root", "value:nullableOpaquePointer", ret: .void),
        abi.th("kk_unregister_coroutine_root", "value:nullableOpaquePointer", ret: .void),
        abi.th("kk_runtime_heap_object_count", ret: .uint32),
        abi.th("kk_runtime_force_reset", ret: .void),
    ]
}
