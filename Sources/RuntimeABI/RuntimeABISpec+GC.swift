private let abi = RuntimeABISectionBuilder("GC")

public extension RuntimeABISpec {
    static let gcFunctions: [RuntimeABIFunctionSpec] = [
        abi.th("kk_register_frame_map", "functionID:uint32 mapPtr:nullableConstRawPointer", ret: .void),
        abi.th("kk_push_frame", "functionID:uint32 frameBase:nullableOpaquePointer", ret: .void),
        abi.th("kk_pop_frame", ret: .void),
        abi.nt("kk_store_frame_root", "slot:nullableRawPointerPointer value:nullableOpaquePointer", ret: .void),
        abi.nt("kk_gc_store_global", "slot:nullableIntptrPointer value", ret: .intptr),
        abi.nt("kk_gc_store_thread_local_global", "slot:nullableIntptrPointer value", ret: .intptr),
        abi.nt("kk_gc_shadow_push", ret: .intptr),
        abi.nt("kk_gc_shadow_set", "slot value", ret: .intptr),
        abi.nt("kk_gc_shadow_pop", "result thrown", ret: .intptr),
        abi.nt("kk_gc_shadow_depth", ret: .intptr),
        abi.nt("__kk_gc_mutator_enter", ret: .void),
        abi.nt("__kk_gc_mutator_leave", ret: .void),
        abi.nt("__kk_gc_safepoint", ret: .void),
        abi.nt("__kk_gc_mutator_blocking_begin", ret: .void),
        abi.nt("__kk_gc_mutator_blocking_end", ret: .void),
        abi.th("kk_register_coroutine_root", "value:nullableOpaquePointer", ret: .void),
        abi.th("kk_unregister_coroutine_root", "value:nullableOpaquePointer", ret: .void),
        abi.th("kk_runtime_heap_object_count", ret: .uint32),
        abi.th("kk_runtime_force_reset", ret: .void),
    ]
}
