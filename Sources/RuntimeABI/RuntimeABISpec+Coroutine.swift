// swiftlint:disable file_length

/// `RuntimeABISpec.coroutineFunctions` extracted from `RuntimeABISpec.swift`.
public extension RuntimeABISpec {
    static let coroutineFunctions: [RuntimeABIFunctionSpec] = [
        RuntimeABIFunctionSpec(
            name: "kk_coroutine_suspended",
            parameters: [],
            returnType: .opaquePointer,
            section: "Coroutine",
            isThrowing: false,
        ),
        RuntimeABIFunctionSpec(
            name: "kk_coroutine_continuation_new",
            parameters: [
                RuntimeABIParameter(name: "functionID", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_coroutine_current_context",
            parameters: [],
            returnType: .intptr,
            section: "Coroutine",
            isThrowing: false,
        ),
        RuntimeABIFunctionSpec(
            name: "kk_coroutine_call_direct_suspend",
            parameters: [
                RuntimeABIParameter(name: "entryPointRaw", type: .intptr),
                RuntimeABIParameter(name: "childContinuation", type: .intptr),
                RuntimeABIParameter(name: "callerContinuationRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_coroutine_continuation_factory",
            parameters: [
                RuntimeABIParameter(name: "contextRaw", type: .intptr),
                RuntimeABIParameter(name: "resumeWithRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_create_coroutine_unintercepted",
            parameters: [
                RuntimeABIParameter(name: "entryPointRaw", type: .intptr),
                RuntimeABIParameter(name: "completionContinuation", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_start_coroutine_unintercepted_or_return",
            parameters: [
                RuntimeABIParameter(name: "entryPointRaw", type: .intptr),
                RuntimeABIParameter(name: "continuation", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        // Link-time markers for the source-backed receiver-less intrinsics. The
        // coroutine lowering pass rewrites calls to them into the entry-point ABI
        // above; the runtime only exports stubs so the standalone inline copies link.
        RuntimeABIFunctionSpec(
            name: "kk_create_coroutine_unintercepted_no_receiver",
            parameters: [
                RuntimeABIParameter(name: "functionRaw", type: .intptr),
                RuntimeABIParameter(name: "functionContextRaw", type: .intptr),
                RuntimeABIParameter(name: "completionContinuation", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_start_coroutine_unintercepted_or_return_no_receiver",
            parameters: [
                RuntimeABIParameter(name: "functionRaw", type: .intptr),
                RuntimeABIParameter(name: "functionContextRaw", type: .intptr),
                RuntimeABIParameter(name: "completionContinuation", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        // Link-time markers for the source-backed receiver-bearing intrinsics. The
        // coroutine lowering pass rewrites calls to them into the entry-point ABI
        // above; the runtime only exports stubs so the standalone inline copies link.
        RuntimeABIFunctionSpec(
            name: "kk_create_coroutine_unintercepted_with_receiver",
            parameters: [
                RuntimeABIParameter(name: "functionRaw", type: .intptr),
                RuntimeABIParameter(name: "functionContextRaw", type: .intptr),
                RuntimeABIParameter(name: "receiverRaw", type: .intptr),
                RuntimeABIParameter(name: "completionContinuation", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_start_coroutine_unintercepted_or_return_with_receiver",
            parameters: [
                RuntimeABIParameter(name: "functionRaw", type: .intptr),
                RuntimeABIParameter(name: "functionContextRaw", type: .intptr),
                RuntimeABIParameter(name: "receiverRaw", type: .intptr),
                RuntimeABIParameter(name: "completionContinuation", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_coroutine_state_enter",
            parameters: [
                RuntimeABIParameter(name: "continuation", type: .intptr),
                RuntimeABIParameter(name: "functionID", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_coroutine_state_set_label",
            parameters: [
                RuntimeABIParameter(name: "continuation", type: .intptr),
                RuntimeABIParameter(name: "label", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_coroutine_state_exit",
            parameters: [
                RuntimeABIParameter(name: "continuation", type: .intptr),
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_coroutine_state_set_spill",
            parameters: [
                RuntimeABIParameter(name: "continuation", type: .intptr),
                RuntimeABIParameter(name: "slot", type: .intptr),
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_coroutine_state_get_spill",
            parameters: [
                RuntimeABIParameter(name: "continuation", type: .intptr),
                RuntimeABIParameter(name: "slot", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_coroutine_state_set_completion",
            parameters: [
                RuntimeABIParameter(name: "continuation", type: .intptr),
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_coroutine_state_get_completion",
            parameters: [
                RuntimeABIParameter(name: "continuation", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_coroutine_state_get_thrown_exception",
            parameters: [
                RuntimeABIParameter(name: "continuation", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_kxmini_run_blocking",
            parameters: [
                RuntimeABIParameter(name: "entryPointRaw", type: .intptr),
                RuntimeABIParameter(name: "functionID", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_kxmini_launch",
            parameters: [
                RuntimeABIParameter(name: "entryPointRaw", type: .intptr),
                RuntimeABIParameter(name: "functionID", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_kxmini_async",
            parameters: [
                RuntimeABIParameter(name: "entryPointRaw", type: .intptr),
                RuntimeABIParameter(name: "functionID", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_kxmini_async_await",
            parameters: [
                RuntimeABIParameter(name: "handle", type: .intptr),
                RuntimeABIParameter(name: "continuation", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_kxmini_delay",
            parameters: [
                RuntimeABIParameter(name: "milliseconds", type: .intptr),
                RuntimeABIParameter(name: "continuation", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_coroutine_yield",
            parameters: [
                RuntimeABIParameter(name: "continuation", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_coroutine_launcher_arg_set",
            parameters: [
                RuntimeABIParameter(name: "continuation", type: .intptr),
                RuntimeABIParameter(name: "index", type: .int64),
                RuntimeABIParameter(name: "value", type: .int64),
            ],
            returnType: .int64,
            section: "Coroutine",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_coroutine_launcher_arg_get",
            parameters: [
                RuntimeABIParameter(name: "continuation", type: .intptr),
                RuntimeABIParameter(name: "index", type: .int64),
            ],
            returnType: .int64,
            section: "Coroutine",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_kxmini_run_blocking_with_cont",
            parameters: [
                RuntimeABIParameter(name: "entryPointRaw", type: .intptr),
                RuntimeABIParameter(name: "continuation", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_kxmini_launch_with_cont",
            parameters: [
                RuntimeABIParameter(name: "entryPointRaw", type: .intptr),
                RuntimeABIParameter(name: "continuation", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_kxmini_async_with_cont",
            parameters: [
                RuntimeABIParameter(name: "entryPointRaw", type: .intptr),
                RuntimeABIParameter(name: "continuation", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_produce",
            parameters: [
                RuntimeABIParameter(name: "entryPointRaw", type: .intptr),
                RuntimeABIParameter(name: "capture0", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_kxmini_produce_with_cont",
            parameters: [
                RuntimeABIParameter(name: "entryPointRaw", type: .intptr),
                RuntimeABIParameter(name: "continuation", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        // Dispatcher-aware launch (STDLIB-CORO-072)
        RuntimeABIFunctionSpec(
            name: "kk_kxmini_launch_with_dispatcher",
            parameters: [
                RuntimeABIParameter(name: "entryPointRaw", type: .intptr),
                RuntimeABIParameter(name: "functionID", type: .intptr),
                RuntimeABIParameter(name: "dispatcherRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_kxmini_launch_with_dispatcher_and_cont",
            parameters: [
                RuntimeABIParameter(name: "entryPointRaw", type: .intptr),
                RuntimeABIParameter(name: "continuation", type: .intptr),
                RuntimeABIParameter(name: "dispatcherRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine",
            isThrowing: false
        ),
        // CoroutineStart.LAZY launch (STDLIB-CORO-001)
        RuntimeABIFunctionSpec(
            name: "kk_kxmini_launch_lazy",
            parameters: [
                RuntimeABIParameter(name: "entryPointRaw", type: .intptr),
                RuntimeABIParameter(name: "functionID", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_kxmini_launch_lazy_with_cont",
            parameters: [
                RuntimeABIParameter(name: "entryPointRaw", type: .intptr),
                RuntimeABIParameter(name: "continuation", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine",
            isThrowing: false
        ),
        // CoroutineStart.UNDISPATCHED launch
        RuntimeABIFunctionSpec(
            name: "kk_kxmini_launch_undispatched",
            parameters: [
                RuntimeABIParameter(name: "entryPointRaw", type: .intptr),
                RuntimeABIParameter(name: "functionID", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_kxmini_launch_undispatched_with_cont",
            parameters: [
                RuntimeABIParameter(name: "entryPointRaw", type: .intptr),
                RuntimeABIParameter(name: "continuation", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine",
            isThrowing: false
        ),
        // CoroutineStart.LAZY / UNDISPATCHED async (STDLIB-CORO-001).
        // The launch family above returns a Job handle; these return a Deferred
        // one carrying the block's result, so each start mode needs its own
        // entry point rather than sharing launch's.
        RuntimeABIFunctionSpec(
            name: "kk_kxmini_async_lazy",
            parameters: [
                RuntimeABIParameter(name: "entryPointRaw", type: .intptr),
                RuntimeABIParameter(name: "functionID", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_kxmini_async_lazy_with_cont",
            parameters: [
                RuntimeABIParameter(name: "entryPointRaw", type: .intptr),
                RuntimeABIParameter(name: "continuation", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_kxmini_async_undispatched",
            parameters: [
                RuntimeABIParameter(name: "entryPointRaw", type: .intptr),
                RuntimeABIParameter(name: "functionID", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_kxmini_async_undispatched_with_cont",
            parameters: [
                RuntimeABIParameter(name: "entryPointRaw", type: .intptr),
                RuntimeABIParameter(name: "continuation", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine",
            isThrowing: false
        ),
        // CoroutineExceptionHandler (STDLIB-CORO-072)
        RuntimeABIFunctionSpec(
            name: "kk_exception_handler_new",
            parameters: [],
            returnType: .intptr,
            section: "Coroutine",
            isThrowing: false,
        ),
        RuntimeABIFunctionSpec(
            name: "kk_kxmini_launch_with_exception_handler",
            parameters: [
                RuntimeABIParameter(name: "entryPointRaw", type: .intptr),
                RuntimeABIParameter(name: "functionID", type: .intptr),
                RuntimeABIParameter(name: "handlerRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine",
            isThrowing: false
        ),
        // Flow (P5-88)
        RuntimeABIFunctionSpec(
            name: "kk_flow_create",
            parameters: [
                RuntimeABIParameter(name: "emitterFnPtr", type: .intptr),
                RuntimeABIParameter(name: "continuation", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_channel_flow_create",
            parameters: [
                RuntimeABIParameter(name: "emitterFnPtr", type: .intptr),
                RuntimeABIParameter(name: "continuation", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_callback_flow_create",
            parameters: [
                RuntimeABIParameter(name: "emitterFnPtr", type: .intptr),
                RuntimeABIParameter(name: "continuation", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_flow_emit",
            parameters: [
                RuntimeABIParameter(name: "flowHandle", type: .intptr),
                RuntimeABIParameter(name: "value", type: .intptr),
                RuntimeABIParameter(name: "tag", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_flow_collect",
            parameters: [
                RuntimeABIParameter(name: "flowHandle", type: .intptr),
                RuntimeABIParameter(name: "collectorFnPtr", type: .intptr),
                RuntimeABIParameter(name: "collectorEnvPtr", type: .intptr),
                RuntimeABIParameter(name: "continuation", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Coroutine",
            isThrowing: true
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_flow_collectLatest",
            parameters: [
                RuntimeABIParameter(name: "flowHandle", type: .intptr),
                RuntimeABIParameter(name: "collectorFnPtr", type: .intptr),
                RuntimeABIParameter(name: "collectorEnvPtr", type: .intptr),
                RuntimeABIParameter(name: "continuation", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Coroutine",
            isThrowing: true
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_flow_retain",
            parameters: [
                RuntimeABIParameter(name: "flowHandle", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_flow_release",
            parameters: [
                RuntimeABIParameter(name: "flowHandle", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine",
            isThrowing: false
        ),
        // Flow terminal operators & builders (STDLIB-088 / STDLIB-FLOW-178)
        // KSP-674: kk_flow_of / kk_flow_empty / kk_flow_as_flow removed —
        // flowOf / emptyFlow / Iterable.asFlow are now Kotlin source composed
        // from kk_flow_create + kk_flow_emit.
        RuntimeABIFunctionSpec(
            name: "__kk_flow_to_list",
            parameters: [
                RuntimeABIParameter(name: "flowHandle", type: .intptr),
                RuntimeABIParameter(name: "continuation", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_flow_first",
            parameters: [
                RuntimeABIParameter(name: "flowHandle", type: .intptr),
                RuntimeABIParameter(name: "continuation", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_flow_single",
            parameters: [
                RuntimeABIParameter(name: "flowHandle", type: .intptr),
                RuntimeABIParameter(name: "continuation", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_flow_zip",
            parameters: [
                RuntimeABIParameter(name: "lhsHandle", type: .intptr),
                RuntimeABIParameter(name: "rhsHandle", type: .intptr),
                RuntimeABIParameter(name: "transformFnPtr", type: .intptr),
                RuntimeABIParameter(name: "continuation", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_flow_combine",
            parameters: [
                RuntimeABIParameter(name: "lhsHandle", type: .intptr),
                RuntimeABIParameter(name: "rhsHandle", type: .intptr),
                RuntimeABIParameter(name: "transformFnPtr", type: .intptr),
                RuntimeABIParameter(name: "continuation", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_flow_merge",
            parameters: [
                RuntimeABIParameter(name: "lhsHandle", type: .intptr),
                RuntimeABIParameter(name: "rhsHandle", type: .intptr),
                RuntimeABIParameter(name: "continuation", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_flow_flat_map_concat",
            parameters: [
                RuntimeABIParameter(name: "flowHandle", type: .intptr),
                RuntimeABIParameter(name: "transformFnPtr", type: .intptr),
                RuntimeABIParameter(name: "continuation", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_flow_flat_map_merge",
            parameters: [
                RuntimeABIParameter(name: "flowHandle", type: .intptr),
                RuntimeABIParameter(name: "transformFnPtr", type: .intptr),
                RuntimeABIParameter(name: "continuation", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_flow_flat_map_latest",
            parameters: [
                RuntimeABIParameter(name: "flowHandle", type: .intptr),
                RuntimeABIParameter(name: "transformFnPtr", type: .intptr),
                RuntimeABIParameter(name: "continuation", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_flow_count",
            parameters: [
                RuntimeABIParameter(name: "flowHandle", type: .intptr),
                RuntimeABIParameter(name: "continuation", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_flow_fold",
            parameters: [
                RuntimeABIParameter(name: "flowHandle", type: .intptr),
                RuntimeABIParameter(name: "initial", type: .intptr),
                RuntimeABIParameter(name: "operationFnPtr", type: .intptr),
                RuntimeABIParameter(name: "continuation", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_flow_reduce",
            parameters: [
                RuntimeABIParameter(name: "flowHandle", type: .intptr),
                RuntimeABIParameter(name: "operationFnPtr", type: .intptr),
                RuntimeABIParameter(name: "continuation", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        // Dispatchers / withContext (P5-133)
        RuntimeABIFunctionSpec(
            name: "kk_dispatcher_default",
            parameters: [],
            returnType: .intptr,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_dispatcher_io",
            parameters: [],
            returnType: .intptr,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_dispatcher_main",
            parameters: [],
            returnType: .intptr,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_with_context",
            parameters: [
                RuntimeABIParameter(name: "dispatcher", type: .intptr),
                RuntimeABIParameter(name: "blockFnPtr", type: .intptr),
                RuntimeABIParameter(name: "continuation", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        // STDLIB-CORO-077: CoroutineName, CoroutineExceptionHandler, CoroutineContext
        RuntimeABIFunctionSpec(
            name: "kk_coroutine_name_create",
            parameters: [
                RuntimeABIParameter(name: "nameRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_coroutine_name_get",
            parameters: [
                RuntimeABIParameter(name: "handleRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_exception_handler_create",
            parameters: [
                RuntimeABIParameter(name: "handlerFnPtr", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_exception_handler_invoke",
            parameters: [
                RuntimeABIParameter(name: "handlerRaw", type: .intptr),
                RuntimeABIParameter(name: "contextRaw", type: .intptr),
                RuntimeABIParameter(name: "exceptionRaw", type: .intptr),
            ],
            returnType: .void,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_context_plus",
            parameters: [
                RuntimeABIParameter(name: "leftRaw", type: .intptr),
                RuntimeABIParameter(name: "rightRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_context_get",
            parameters: [
                RuntimeABIParameter(name: "contextRaw", type: .intptr),
                RuntimeABIParameter(name: "keyRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_context_fold",
            parameters: [
                RuntimeABIParameter(name: "contextRaw", type: .intptr),
                RuntimeABIParameter(name: "initial", type: .intptr),
                RuntimeABIParameter(name: "operationFnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_context_minusKey",
            parameters: [
                RuntimeABIParameter(name: "contextRaw", type: .intptr),
                RuntimeABIParameter(name: "keyRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_context_get_dispatcher",
            parameters: [
                RuntimeABIParameter(name: "contextRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_continuation_intercepted",
            parameters: [
                RuntimeABIParameter(name: "continuationRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_continuation_interceptor_intercept_continuation",
            parameters: [
                RuntimeABIParameter(name: "interceptorRaw", type: .intptr),
                RuntimeABIParameter(name: "continuationRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_context_get_name",
            parameters: [
                RuntimeABIParameter(name: "contextRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_context_release",
            parameters: [
                RuntimeABIParameter(name: "contextRaw", type: .intptr),
            ],
            returnType: .void,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_with_context_full",
            parameters: [
                RuntimeABIParameter(name: "contextRaw", type: .intptr),
                RuntimeABIParameter(name: "blockFnPtr", type: .intptr),
                RuntimeABIParameter(name: "continuation", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        // Channel (CORO-001)
        RuntimeABIFunctionSpec(
            name: "__kk_channel_await_close",
            parameters: [
                RuntimeABIParameter(name: "handle", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_channel_create",
            parameters: [
                RuntimeABIParameter(name: "capacity", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_channel_send",
            parameters: [
                RuntimeABIParameter(name: "handle", type: .intptr),
                RuntimeABIParameter(name: "value", type: .intptr),
                RuntimeABIParameter(name: "continuation", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_select_try_receive",
            parameters: [RuntimeABIParameter(name: "handle", type: .intptr)],
            returnType: .intptr,
            section: "Coroutine",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_select_builder_exchange",
            parameters: [RuntimeABIParameter(name: "builder", type: .intptr)],
            returnType: .intptr,
            section: "Coroutine",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_select_start_job",
            parameters: [RuntimeABIParameter(name: "job", type: .intptr)],
            returnType: .intptr,
            section: "Coroutine",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_select_builder_current",
            parameters: [],
            returnType: .intptr,
            section: "Coroutine",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_select_receive_value",
            parameters: [RuntimeABIParameter(name: "token", type: .intptr)],
            returnType: .intptr,
            section: "Coroutine",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_channel_try_send",
            parameters: [
                RuntimeABIParameter(name: "handle", type: .intptr),
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_channel_receive",
            parameters: [
                RuntimeABIParameter(name: "handle", type: .intptr),
                RuntimeABIParameter(name: "continuation", type: .intptr),
                RuntimeABIParameter(name: "outValue", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_channel_close",
            parameters: [
                RuntimeABIParameter(name: "handle", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine",
            // KSP-678: bridged from bundled Kotlin (Channels.kt) as a plain
            // Int-returning residual; it does not use the outThrown ABI path.
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_channel_is_closed_token",
            parameters: [
                RuntimeABIParameter(name: "status", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        // Channel capacity/overflow-policy factory and invokeOnClose handler
        // registration (KSP-1573).
        RuntimeABIFunctionSpec(
            name: "__kk_channel_create_with_policy",
            parameters: [
                RuntimeABIParameter(name: "capacity", type: .intptr),
                RuntimeABIParameter(name: "onBufferOverflow", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_channel_invoke_on_close",
            parameters: [
                RuntimeABIParameter(name: "handle", type: .intptr),
                RuntimeABIParameter(name: "handlerFnPtr", type: .intptr),
                RuntimeABIParameter(name: "handlerClosureRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine",
            isThrowing: false
        ),
        // ChannelResult-boxed send/receive bridges and box accessors
        // (KSP-1572). `kk_channel_try_send` keeps its bare-status contract;
        // the `__kk_` variants return a `RuntimeChannelResultBox` handle.
        RuntimeABIFunctionSpec(
            name: "__kk_channel_try_receive",
            parameters: [
                RuntimeABIParameter(name: "handle", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_channel_try_send",
            parameters: [
                RuntimeABIParameter(name: "handle", type: .intptr),
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_channel_receive_catching",
            parameters: [
                RuntimeABIParameter(name: "handle", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_channel_send_blocking",
            parameters: [
                RuntimeABIParameter(name: "handle", type: .intptr),
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_channel_result_status",
            parameters: [
                RuntimeABIParameter(name: "boxRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_channel_result_value_or_null",
            parameters: [
                RuntimeABIParameter(name: "boxRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_channel_result_get_or_throw",
            parameters: [
                RuntimeABIParameter(name: "boxRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Coroutine",
            isThrowing: true
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_identity",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine",
            isThrowing: false
        ),
        // Scope-launch used by the bundled produce/actor builders; a suspend
        // block value arrives as the (fnPtr, closureRaw) pair suspend
        // function values use at the ABI boundary (KSP-1573).
        RuntimeABIFunctionSpec(
            name: "__kk_produce_launch",
            parameters: [
                RuntimeABIParameter(name: "channelHandle", type: .intptr),
                RuntimeABIParameter(name: "entryPointRaw", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine",
            isThrowing: false
        ),
        // Launcher-continuation counterpart for a suspend literal block:
        // `(channel, launcherThunk, continuation)` mirroring
        // `kk_kxmini_produce_with_cont` (KSP-1573).
        RuntimeABIFunctionSpec(
            name: "__kk_produce_launch_with_cont",
            parameters: [
                RuntimeABIParameter(name: "channelHandle", type: .intptr),
                RuntimeABIParameter(name: "entryPointRaw", type: .intptr),
                RuntimeABIParameter(name: "continuation", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine",
            isThrowing: false
        ),
        // Structured Concurrency (P5-89)
        RuntimeABIFunctionSpec(
            name: "kk_coroutine_scope_async",
            parameters: [
                RuntimeABIParameter(name: "scope", type: .intptr),
                RuntimeABIParameter(name: "context", type: .intptr),
                RuntimeABIParameter(name: "start", type: .intptr),
                RuntimeABIParameter(name: "entryPointRaw", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
            ],
            returnType: .intptr, section: "Coroutine", isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_coroutine_scope_async_with_cont",
            parameters: [
                RuntimeABIParameter(name: "scope", type: .intptr),
                RuntimeABIParameter(name: "context", type: .intptr),
                RuntimeABIParameter(name: "start", type: .intptr),
                RuntimeABIParameter(name: "entryPointRaw", type: .intptr),
                RuntimeABIParameter(name: "continuation", type: .intptr),
            ],
            returnType: .intptr, section: "Coroutine", isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_coroutine_scope_new",
            parameters: [],
            returnType: .intptr,
            section: "Coroutine",
            isThrowing: false,
        ),
        RuntimeABIFunctionSpec(
            name: "kk_coroutine_scope_cancel",
            parameters: [
                RuntimeABIParameter(name: "scopeHandle", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_coroutine_scope_wait",
            parameters: [
                RuntimeABIParameter(name: "scopeHandle", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_coroutine_scope_register_child",
            parameters: [
                RuntimeABIParameter(name: "scopeHandle", type: .intptr),
                RuntimeABIParameter(name: "childHandle", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine",
            isThrowing: false
        ),
        // CoroutineScope(context) / Job() / SupervisorJob() / NonCancellable / ensureActive
        // (STDLIB-CORO-090)
        RuntimeABIFunctionSpec(
            name: "kk_coroutine_scope_new_with_context",
            parameters: [
                RuntimeABIParameter(name: "contextRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine",
            isThrowing: false
        ),
        // KSP-1583: kotlinx.coroutines.test — runTest mints a TestScope over
        // the context and invokes the test body with `this` bound to it.
        // The suspend block value crosses as the (entryPointRaw, closureRaw)
        // pair function-typed parameters use at the ABI boundary; resolvable
        // suspend literals route to the _with_cont launcher variant instead
        // (scope in launcherArgs[0]). outThrown forwards a body-thrown
        // exception to the runTest caller.
        RuntimeABIFunctionSpec(
            name: "kk_test_run_blocking",
            parameters: [
                RuntimeABIParameter(name: "contextRaw", type: .intptr),
                RuntimeABIParameter(name: "timeoutRaw", type: .intptr),
                RuntimeABIParameter(name: "entryPointRaw", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_test_run_blocking_with_cont",
            parameters: [
                RuntimeABIParameter(name: "contextRaw", type: .intptr),
                RuntimeABIParameter(name: "entryPointRaw", type: .intptr),
                RuntimeABIParameter(name: "continuation", type: .intptr),
                RuntimeABIParameter(name: "scopeSlotRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        // Lazily minted per-scope TestCoroutineScheduler handle.
        RuntimeABIFunctionSpec(
            name: "kk_test_scope_scheduler",
            parameters: [
                RuntimeABIParameter(name: "scopeHandle", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine",
            isThrowing: false
        ),
        // `TestScope.currentTime` — the scope scheduler's virtual clock.
        RuntimeABIFunctionSpec(
            name: "kk_test_scope_current_time",
            parameters: [
                RuntimeABIParameter(name: "scopeHandle", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_test_scheduler_new",
            parameters: [],
            returnType: .intptr,
            section: "Coroutine",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_test_scheduler_current_time",
            parameters: [
                RuntimeABIParameter(name: "schedulerHandle", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_test_scheduler_advance_time_by",
            parameters: [
                RuntimeABIParameter(name: "schedulerHandle", type: .intptr),
                RuntimeABIParameter(name: "delayTimeMillis", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_test_scheduler_advance_until_idle",
            parameters: [
                RuntimeABIParameter(name: "schedulerHandle", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_test_scheduler_run_current",
            parameters: [
                RuntimeABIParameter(name: "schedulerHandle", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine",
            isThrowing: false
        ),
        // `CoroutineScope.launch { }` (receiver-aware launcher): fire-and-forget like
        // kk_kxmini_launch, so no outThrown parameter -- it returns a Job immediately
        // rather than blocking for the body's result.
        RuntimeABIFunctionSpec(
            name: "kk_coroutine_scope_launch",
            parameters: [
                RuntimeABIParameter(name: "scopeHandle", type: .intptr),
                RuntimeABIParameter(name: "entryPointRaw", type: .intptr),
                RuntimeABIParameter(name: "functionID", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine",
            isThrowing: false
        ),
        // Variant of kk_coroutine_scope_launch that accepts a pre-built continuation
        // carrying the launched suspend lambda's captured outer variables (BUG-049).
        RuntimeABIFunctionSpec(
            name: "kk_coroutine_scope_launch_with_cont",
            parameters: [
                RuntimeABIParameter(name: "scopeHandle", type: .intptr),
                RuntimeABIParameter(name: "entryPointRaw", type: .intptr),
                RuntimeABIParameter(name: "continuation", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_job_new",
            parameters: [],
            returnType: .intptr,
            section: "Coroutine",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_job_bind_wrapper",
            parameters: [
                RuntimeABIParameter(name: "wrapper", type: .intptr),
                RuntimeABIParameter(name: "job", type: .intptr),
                RuntimeABIParameter(name: "parent", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_deferred_get_completed",
            parameters: [
                RuntimeABIParameter(name: "handle", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Coroutine",
            isThrowing: true
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_deferred_completion_exception",
            parameters: [
                RuntimeABIParameter(name: "handle", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Coroutine",
            isThrowing: true
        ),
        RuntimeABIFunctionSpec(
            name: "kk_supervisor_job_new",
            parameters: [],
            returnType: .intptr,
            section: "Coroutine",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_non_cancellable_instance",
            parameters: [],
            returnType: .intptr,
            section: "Coroutine",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_context_is_active",
            parameters: [
                RuntimeABIParameter(name: "contextRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_ensure_active",
            parameters: [
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_job_join",
            parameters: [
                RuntimeABIParameter(name: "jobHandle", type: .intptr),
                RuntimeABIParameter(name: "continuation", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_await_cancellation",
            parameters: [
                RuntimeABIParameter(name: "continuation", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_job_await_completion",
            parameters: [
                RuntimeABIParameter(name: "jobHandle", type: .intptr),
                RuntimeABIParameter(name: "continuation", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine",
            isThrowing: false
        ),
        // CoroutineScope hierarchy / lifecycle (STDLIB-CORO-069)
        RuntimeABIFunctionSpec(
            name: "kk_coroutine_scope_is_active",
            parameters: [
                RuntimeABIParameter(name: "scopeHandle", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        // STDLIB-CORO-BUG-04: ABI backing for a bare `isActive` reference
        // (no explicit CoroutineScope receiver) inside a coroutine builder body.
        RuntimeABIFunctionSpec(
            name: "kk_coroutine_current_is_active",
            parameters: [],
            returnType: .intptr,
            section: "Coroutine",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_coroutine_current_scope",
            parameters: [],
            returnType: .intptr,
            section: "Coroutine",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_coroutine_scope_is_cancelled",
            parameters: [
                RuntimeABIParameter(name: "scopeHandle", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        // Cancellation (CORO-002)
        RuntimeABIFunctionSpec(
            name: "kk_coroutine_check_cancellation",
            parameters: [
                RuntimeABIParameter(name: "continuation", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_is_cancellation_exception",
            parameters: [
                RuntimeABIParameter(name: "throwableRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_job_cancel",
            parameters: [
                RuntimeABIParameter(name: "jobHandle", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_job_cancel_with_cause",
            parameters: [
                RuntimeABIParameter(name: "jobHandle", type: .intptr),
                RuntimeABIParameter(name: "cause", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_context_cancel",
            parameters: [
                RuntimeABIParameter(name: "contextRaw", type: .intptr),
                RuntimeABIParameter(name: "causeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_context_cancel_no_cause",
            parameters: [
                RuntimeABIParameter(name: "contextRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_job_complete",
            parameters: [
                RuntimeABIParameter(name: "jobHandle", type: .intptr),
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_job_complete_exceptionally",
            parameters: [
                RuntimeABIParameter(name: "jobHandle", type: .intptr),
                RuntimeABIParameter(name: "exception", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine",
            isThrowing: false
        ),
        // Job State Queries (STDLIB-CORO-070)
        RuntimeABIFunctionSpec(
            name: "kk_job_is_active",
            parameters: [
                RuntimeABIParameter(name: "jobHandle", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_job_is_completed",
            parameters: [
                RuntimeABIParameter(name: "jobHandle", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_job_is_cancelled",
            parameters: [
                RuntimeABIParameter(name: "jobHandle", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_job_is_failed",
            parameters: [
                RuntimeABIParameter(name: "jobHandle", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_job_get_cancellation_exception",
            parameters: [
                RuntimeABIParameter(name: "jobHandle", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_job_invoke_on_completion",
            parameters: [
                RuntimeABIParameter(name: "jobHandle", type: .intptr),
                RuntimeABIParameter(name: "onCancelling", type: .intptr),
                RuntimeABIParameter(name: "handlerFnPtr", type: .intptr),
                RuntimeABIParameter(name: "handlerClosureRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_job_invoke_on_completion",
            parameters: [
                RuntimeABIParameter(name: "jobHandle", type: .intptr),
                RuntimeABIParameter(name: "onCancelling", type: .intptr),
                RuntimeABIParameter(name: "invokeImmediately", type: .intptr),
                RuntimeABIParameter(name: "handlerFnPtr", type: .intptr),
                RuntimeABIParameter(name: "handlerClosureRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_job_children",
            parameters: [
                RuntimeABIParameter(name: "jobHandle", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_job_parent",
            parameters: [
                RuntimeABIParameter(name: "jobHandle", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_job_dispose_handle",
            parameters: [
                RuntimeABIParameter(name: "jobHandle", type: .intptr),
                RuntimeABIParameter(name: "handlerID", type: .intptr),
            ],
            returnType: .void,
            section: "Coroutine",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_job_dispose_completion_handler",
            parameters: [
                RuntimeABIParameter(name: "jobHandle", type: .intptr),
                RuntimeABIParameter(name: "handlerID", type: .intptr),
            ],
            returnType: .void,
            section: "Coroutine",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_context_get_job",
            parameters: [
                RuntimeABIParameter(name: "contextRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_coroutine_cancel",
            parameters: [
                RuntimeABIParameter(name: "continuation", type: .intptr),
            ],
            returnType: .void,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_coroutine_cancel_current",
            parameters: [
                RuntimeABIParameter(name: "message", type: .intptr),
                RuntimeABIParameter(name: "causeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        // Mutex / Semaphore (sync primitives)
        RuntimeABIFunctionSpec(
            name: "__kk_mutex_create",
            parameters: [],
            returnType: .intptr,
            section: "Coroutine"
        ),

        RuntimeABIFunctionSpec(
            name: "kk_mutex_lock",
            parameters: [
                RuntimeABIParameter(name: "handle", type: .intptr),
                RuntimeABIParameter(name: "continuation", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_mutex_unlock",
            parameters: [
                RuntimeABIParameter(name: "handle", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_mutex_tryLock",
            parameters: [
                RuntimeABIParameter(name: "handle", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_mutex_isLocked",
            parameters: [
                RuntimeABIParameter(name: "handle", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        // KSP-677: Lock.withLock is Kotlin source delegating to this demoted
        // __kk_lock_withLock bridge; the action is passed via the general
        // closure-taking ABI (function pointer + closure environment + outThrown).
        RuntimeABIFunctionSpec(
            name: "__kk_lock_withLock",
            parameters: [
                RuntimeABIParameter(name: "handle", type: .intptr),
                RuntimeABIParameter(name: "actionFnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_semaphore_create",
            parameters: [
                RuntimeABIParameter(name: "permits", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_semaphore_acquire",
            parameters: [
                RuntimeABIParameter(name: "handle", type: .intptr),
                RuntimeABIParameter(name: "continuation", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_semaphore_release",
            parameters: [
                RuntimeABIParameter(name: "handle", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_semaphore_tryAcquire",
            parameters: [
                RuntimeABIParameter(name: "handle", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_semaphore_availablePermits",
            parameters: [
                RuntimeABIParameter(name: "handle", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        // KSP-677: kk_semaphore_withPermit removed — Semaphore.withPermit is Kotlin source.
    ]
}
