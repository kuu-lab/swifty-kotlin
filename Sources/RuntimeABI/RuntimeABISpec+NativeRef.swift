private let abi = RuntimeABISectionBuilder("NativeRef")

public extension RuntimeABISpec {
    static let nativeRefFunctions: [RuntimeABIFunctionSpec] = [
        abi.nt("kk_weak_ref_create", "objectRaw"),
        abi.nt("kk_weak_ref_get", "weakRefRaw"),
        abi.nt("kk_weak_ref_get_rooted", "weakRefRaw slot"),
        abi.nt("kk_weak_ref_clear", "weakRefRaw"),
        abi.nt("kk_cleaner_create", "valueRaw blockRaw"),
        abi.nt("kk_gc_schedule", "gcRaw"),
        abi.nt("kk_gc_last_gc_info", "gcRaw"),
        abi.nt("kk_gc_target_heap_bytes", "gcRaw"),
        abi.nt("kk_gc_target_heap_bytes_set", "gcRaw value"),
        abi.nt("kk_gc_target_heap_utilization", "gcRaw"),
        abi.nt("kk_gc_target_heap_utilization_set", "gcRaw value"),
        abi.nt("kk_gc_max_heap_bytes", "gcRaw"),
        abi.nt("kk_gc_max_heap_bytes_set", "gcRaw value"),
        abi.nt("kk_gc_main_thread_finalizer_processor_available", "receiverRaw"),
        abi.nt("kk_gc_main_thread_finalizer_processor_batch_size_load", "receiverRaw"),
        abi.nt("kk_gc_main_thread_finalizer_processor_batch_size_store", "receiverRaw value"),
        abi.nt("kk_gc_main_thread_finalizer_processor_max_time_in_task_load", "receiverRaw"),
        abi.nt("kk_gc_main_thread_finalizer_processor_max_time_in_task_store", "receiverRaw value"),
        abi.nt("kk_gc_main_thread_finalizer_processor_min_time_between_tasks_load", "receiverRaw"),
        abi.nt("kk_gc_main_thread_finalizer_processor_min_time_between_tasks_store", "receiverRaw value"),
        abi.nt("__kk_debugging_is_thread_state_runnable"),
        abi.nt("__kk_debugging_force_checked_shutdown_get"),
        abi.nt("__kk_debugging_force_checked_shutdown_set", "value"),
        abi.nt("__kk_debugging_dump_memory", "fd"),
        abi.nt("kk_debugging_gc_suspend_count"),
        abi.nt("kk_debugging_thread_count"),
        abi.nt("kk_debugging_global_object_count"),
    ]
}
