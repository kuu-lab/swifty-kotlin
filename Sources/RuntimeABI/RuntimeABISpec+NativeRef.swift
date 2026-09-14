public extension RuntimeABISpec {
    static let nativeRefFunctions: [RuntimeABIFunctionSpec] = [
        RuntimeABIFunctionSpec(
            name: "kk_weak_ref_create",
            parameters: [
                RuntimeABIParameter(name: "objectRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "NativeRef",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_weak_ref_get",
            parameters: [
                RuntimeABIParameter(name: "weakRefRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "NativeRef",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_weak_ref_clear",
            parameters: [
                RuntimeABIParameter(name: "weakRefRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "NativeRef",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_cleaner_create",
            parameters: [
                RuntimeABIParameter(name: "valueRaw", type: .intptr),
                RuntimeABIParameter(name: "blockRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "NativeRef",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_cleaner_clean",
            parameters: [
                RuntimeABIParameter(name: "cleanerRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "NativeRef"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_cleaner_dispose",
            parameters: [
                RuntimeABIParameter(name: "cleanerRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "NativeRef",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_gc_schedule",
            parameters: [],
            returnType: .intptr,
            section: "NativeRef",
            isThrowing: false,
        ),
        RuntimeABIFunctionSpec(
            name: "kk_gc_target_heap_bytes",
            parameters: [],
            returnType: .intptr,
            section: "NativeRef",
            isThrowing: false,
        ),
        RuntimeABIFunctionSpec(
            name: "kk_gc_target_heap_utilization",
            parameters: [],
            returnType: .double,
            section: "NativeRef",
            isThrowing: false,
        ),
        RuntimeABIFunctionSpec(
            name: "kk_gc_max_heap_bytes",
            parameters: [],
            returnType: .intptr,
            section: "NativeRef",
            isThrowing: false,
        ),
        // KSP-1263: kotlin.native.runtime.GC.MainThreadFinalizerProcessor bridges.
        RuntimeABIFunctionSpec(
            name: "kk_gc_main_thread_finalizer_processor_available",
            parameters: [
                RuntimeABIParameter(name: "receiverRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "NativeRef",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_gc_main_thread_finalizer_processor_batch_size_load",
            parameters: [
                RuntimeABIParameter(name: "receiverRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "NativeRef",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_gc_main_thread_finalizer_processor_batch_size_store",
            parameters: [
                RuntimeABIParameter(name: "receiverRaw", type: .intptr),
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "NativeRef",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_gc_main_thread_finalizer_processor_max_time_in_task_load",
            parameters: [
                RuntimeABIParameter(name: "receiverRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "NativeRef",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_gc_main_thread_finalizer_processor_max_time_in_task_store",
            parameters: [
                RuntimeABIParameter(name: "receiverRaw", type: .intptr),
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "NativeRef",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_gc_main_thread_finalizer_processor_min_time_between_tasks_load",
            parameters: [
                RuntimeABIParameter(name: "receiverRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "NativeRef",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_gc_main_thread_finalizer_processor_min_time_between_tasks_store",
            parameters: [
                RuntimeABIParameter(name: "receiverRaw", type: .intptr),
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "NativeRef",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_debugging_is_thread_state_runnable",
            parameters: [],
            returnType: .intptr,
            section: "NativeRef",
            isThrowing: false,
        ),
        RuntimeABIFunctionSpec(
            name: "kk_debugging_gc_suspend_count",
            parameters: [],
            returnType: .intptr,
            section: "NativeRef",
            isThrowing: false,
        ),
        RuntimeABIFunctionSpec(
            name: "kk_debugging_thread_count",
            parameters: [],
            returnType: .intptr,
            section: "NativeRef",
            isThrowing: false,
        ),
        RuntimeABIFunctionSpec(
            name: "kk_debugging_global_object_count",
            parameters: [],
            returnType: .intptr,
            section: "NativeRef",
            isThrowing: false,
        ),
    ]
}
