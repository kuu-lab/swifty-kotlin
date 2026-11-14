// Residual ABI specs not yet assigned to a categorized RuntimeABISpec section.
// Runtime-backed entries below are generated from Sources/Runtime exported C symbols.

private let abiParity = RuntimeABISectionBuilder("ABIParity")

public extension RuntimeABISpec {
    static let intToIntSpec: RuntimeABIFunctionSpec = abiParity.th("kk_int_to_int", "value")

    static let callableRefCall0Spec: RuntimeABIFunctionSpec = abiParity.th("kk_callable_ref_call_0", "tagged outThrown")

    static let callableRefCall1Spec: RuntimeABIFunctionSpec = abiParity.th("kk_callable_ref_call_1", "tagged arg outThrown")

    static let callableRefCall2Spec: RuntimeABIFunctionSpec = abiParity.th("kk_callable_ref_call_2", "tagged arg1 arg2 outThrown")

    static let callableRefCall3Spec: RuntimeABIFunctionSpec = abiParity.th("kk_callable_ref_call_3", "tagged arg1 arg2 arg3 outThrown")

    static let channelSendSuspendingSpec: RuntimeABIFunctionSpec = abiParity.th("kk_channel_send_suspending", "handle value continuation")

    static let flowCatchSpec: RuntimeABIFunctionSpec = abiParity.th("kk_flow_catch", "flowHandle handlerFnPtr arg2")

    static let flowOnCompletionSpec: RuntimeABIFunctionSpec = abiParity.th("kk_flow_on_completion", "flowHandle handlerFnPtr arg2")

    static let flowOnErrorResumeSpec: RuntimeABIFunctionSpec = abiParity.th("kk_flow_on_error_resume", "flowHandle fallbackFlowHandle arg2")

    static let flowOnErrorReturnSpec: RuntimeABIFunctionSpec = abiParity.th("kk_flow_on_error_return", "flowHandle fallbackValue arg2")

    static let flowRetrySpec: RuntimeABIFunctionSpec = abiParity.th("kk_flow_retry", "flowHandle retries arg2")

    static let flowRetryWhenSpec: RuntimeABIFunctionSpec = abiParity.th("kk_flow_retry_when", "flowHandle predicateFnPtr arg2")

    static let iteratorNextSpec: RuntimeABIFunctionSpec = abiParity.th("kk_iterator_next", "iterRaw outThrown")

    static let mathESpec: RuntimeABIFunctionSpec = abiParity.th("kk_math_e")

    static let mathPiSpec: RuntimeABIFunctionSpec = abiParity.th("kk_math_pi")

    static let memScopeAllocSpec: RuntimeABIFunctionSpec = abiParity.th("kk_mem_scope_alloc", "scopeHandle byteCount")

    static let memScopeEnterSpec: RuntimeABIFunctionSpec = abiParity.th("kk_mem_scope_enter")

    static let memScopeExitSpec: RuntimeABIFunctionSpec = abiParity.th("kk_mem_scope_exit", "handle")

    static let nativeAllocBytesSpec: RuntimeABIFunctionSpec = abiParity.th("kk_native_alloc_bytes", "byteCount")

    static let abiParityFunctions: [RuntimeABIFunctionSpec] = [
        abiParity.nt("__kk_class_toString", "classRaw"),
        abiParity.nt("__kk_class_kotlin", "classRaw"),
        abiParity.nt("__kk_class_declared_constructors", "classRaw"),
        abiParity.nt("__kk_class_declared_constructor", "classRaw parameterTypesRaw"),
        abiParity.nt("__kk_class_for_name", "classNameRaw"),
        abiParity.nt("__kk_class_canonical_name", "classRaw"),
        abiParity.nt("__kk_kclass_java_class", "kclassRaw"),
        abiParity.nt("__kk_kclass_java_primitive_type", "kclassRaw"),
        abiParity.nt("__kk_kclass_java_object_type", "kclassRaw"),
        abiParity.nt("__kk_any_javaClass", "receiverRaw"),
        abiParity.nt("__kk_class_get_name", "classRaw"),
        abiParity.nt("__kk_class_get_enclosing_class", "classRaw"),
        abiParity.nt("__kk_class_get_enclosing_constructor", "classRaw"),
        abiParity.nt("__kk_class_get_enclosing_method", "classRaw"),
        abiParity.nt("__kk_class_get_declaring_class", "classRaw"),
        abiParity.nt("__kk_function_set_enclosing_class", "value enclosingClassNameRaw", ret: .void),
        abiParity.th("kk_future_getState", "futureRaw"),
        abiParity.th("kk_future_invoke", "fnPtr closureRaw valueRaw outThrown"),
        intToIntSpec,
        abiParity.th("component1", "pairRaw"),
        abiParity.th("component2", "pairRaw"),
        abiParity.th("kk_atomic_ref_array_compareAndExchangeAt", "receiver index expect update"),
        abiParity.th("kk_atomic_ref_array_loadAt", "receiver index"),
        abiParity.th("kk_atomic_ref_array_new", "size"),
        abiParity.th("kk_atomic_ref_array_size", "receiver"),
        abiParity.th("kk_atomic_ref_array_storeAt", "receiver index value"),
        callableRefCall0Spec,
        callableRefCall1Spec,
        callableRefCall2Spec,
        callableRefCall3Spec,
        // KSP-678: these Channel residuals are bridged from bundled Kotlin
        // (Channels.kt) and return a plain Int handle/flag; they do not use the
        // outThrown ABI lowering path.
        abiParity.nt("kk_channel_is_closed_for_receive", "handle"),
        abiParity.nt("kk_channel_is_closed_for_send", "handle"),
        abiParity.nt("kk_channel_iterator", "handle"),
        // KUU-1404: hasNext on a cancelled channel throws CancellationException
        // through the outThrown channel (JVM parity); plain close still
        // terminates iteration with a 0 return.
        abiParity.th("kk_channel_iterator_hasNext", "iterHandle outThrown"),
        abiParity.nt("kk_channel_iterator_next", "iterHandle"),
        // KSP-1571: same KSP-678 pattern — close-cause retention, isEmpty, and
        // cancel are bridged from bundled Kotlin (Channel.kt /
        // ChannelResult.kt) as plain Int-token residuals; they do not use the
        // outThrown ABI lowering path.
        abiParity.nt("kk_channel_is_empty", "handle"),
        abiParity.nt("__kk_channel_close_cause", "handle cause"),
        abiParity.nt("__kk_channel_cancel", "handle cause"),
        abiParity.nt("__kk_channel_result_cause", "boxRaw"),
        abiParity.nt("__kk_channel_result_create", "status value cause"),
        channelSendSuspendingSpec,
        abiParity.th("kk_char_isISOControl", "value"),
        abiParity.th("kk_char_isTitleCase", "value"),

        abiParity.th("kk_copaque_pointer_address", "handle"),
        abiParity.th("kk_copaque_pointer_new", "address"),
        abiParity.th("__kk_cancellable_continuation_new", "delegate"),
        abiParity.th("__kk_cancellable_continuation_state", "handle"),
        abiParity.th("__kk_cancellable_continuation_resume", "handle result callback outThrown", ret: .void),
        abiParity.th("__kk_cancellable_continuation_cancel", "handle cause"),
        abiParity.th("__kk_cancellable_continuation_invoke_on_cancellation", "handle handler outThrown", ret: .void),
        abiParity.th("__kk_cancellable_continuation_try_resume", "handle result idempotent"),
        abiParity.th("__kk_cancellable_continuation_complete_resume", "handle token outThrown", ret: .void),
        abiParity.th("__kk_cancellable_continuation_get_result", "handle outThrown"),
        abiParity.th("__kk_coroutine_continuation_context", "continuation outThrown"),
        abiParity.th("__kk_coroutine_continuation_resume_with", "continuation resultRaw outThrown", ret: .void),
        abiParity.th("kk_coroutine_continuation_context", "continuation"),
        abiParity.th("kk_coroutine_continuation_resume", "continuation value", ret: .void),
        abiParity.th("kk_coroutine_continuation_resume_with", "continuation resultRaw", ret: .void),
        abiParity.th("kk_coroutine_continuation_resume_with_exception", "continuation exception", ret: .void),
        abiParity.th("kk_cpointer_address", "handle"),
        abiParity.th("kk_cpointer_new", "address"),
        abiParity.th("kk_cpointer_toLong", "handle"),
        abiParity.th("kk_cpointer_toKStringFromUtf32", "handle"),
        abiParity.th("kk_cpointer_toKStringFromUtf16", "handle"),
        abiParity.nt("kk_byteArray_toCValues", "arrayRaw"),
        abiParity.th("__kk_byteArray_toKString", "arrRaw startIndex endIndex throwOnInvalidSequence outThrown"),
        abiParity.nt("kk_uLongArray_toCValues", "arrayRaw"),
        abiParity.nt("kk_uIntArray_toCValues", "arrayRaw"),
        abiParity.nt("kk_uByteArray_toCValues", "arrayRaw"),
        abiParity.nt("kk_memscope_new"),
        abiParity.nt("kk_arena_new"),
        abiParity.nt("kk_native_heap_get"),
        abiParity.nt("kk_arena_alloc_raw", "scope size align"),
        abiParity.nt("kk_arena_alloc_var", "scope typeToken"),
        abiParity.nt("kk_arena_alloc_array", "scope count typeToken"),
        abiParity.nt("kk_native_placement_free", "scope pointerHandle"),
        abiParity.nt("kk_defer_scope_defer", "scope block"),
        abiParity.th("kk_arena_clear", "scope outThrown"),
        abiParity.nt("kk_cvar_ptr", "varHandle"),
        abiParity.nt("kk_cvar_raw_ptr", "varHandle"),
        abiParity.nt("kk_cvar_bool_load", "varHandle"),
        abiParity.nt("kk_cvar_bool_store", "varHandle value"),
        abiParity.nt("kk_cvar_byte_load", "varHandle"),
        abiParity.nt("kk_cvar_byte_store", "varHandle value"),
        abiParity.nt("kk_cvar_ubyte_load", "varHandle"),
        abiParity.nt("kk_cvar_ubyte_store", "varHandle value"),
        abiParity.nt("kk_cvar_short_load", "varHandle"),
        abiParity.nt("kk_cvar_short_store", "varHandle value"),
        abiParity.nt("kk_cvar_ushort_load", "varHandle"),
        abiParity.nt("kk_cvar_ushort_store", "varHandle value"),
        abiParity.nt("kk_cvar_int_load", "varHandle"),
        abiParity.nt("kk_cvar_int_store", "varHandle value"),
        abiParity.nt("kk_cvar_uint_load", "varHandle"),
        abiParity.nt("kk_cvar_uint_store", "varHandle value"),
        abiParity.nt("kk_cvar_long_load", "varHandle"),
        abiParity.nt("kk_cvar_long_store", "varHandle value"),
        abiParity.nt("kk_cvar_ulong_load", "varHandle"),
        abiParity.nt("kk_cvar_ulong_store", "varHandle value"),
        abiParity.nt("kk_cvar_float_load", "varHandle"),
        abiParity.nt("kk_cvar_float_store", "varHandle value"),
        abiParity.nt("kk_cvar_double_load", "varHandle"),
        abiParity.nt("kk_cvar_double_store", "varHandle value"),
        abiParity.nt("kk_cvar_cpointer_load", "varHandle pointeeTypeToken"),
        abiParity.nt("kk_cvar_cpointer_store", "varHandle value"),
        abiParity.nt("kk_cpointer_pointed", "handle"),
        abiParity.nt("kk_cpointer_get", "handle index"),
        abiParity.nt("kk_cpointer_reinterpret", "handle typeToken"),
        abiParity.nt("kk_cpointer_get_pointer", "handle scope"),
        abiParity.nt("kk_cpointer_raw_ptr", "handle"),
        abiParity.nt("kk_cpointer_plus", "handle index"),
        abiParity.nt("kk_cpointer_set_bool", "handle index value"),
        abiParity.nt("kk_cpointer_set_byte", "handle index value"),
        abiParity.nt("kk_cpointer_set_ubyte", "handle index value"),
        abiParity.nt("kk_cpointer_set_short", "handle index value"),
        abiParity.nt("kk_cpointer_set_ushort", "handle index value"),
        abiParity.nt("kk_cpointer_set_int", "handle index value"),
        abiParity.nt("kk_cpointer_set_uint", "handle index value"),
        abiParity.nt("kk_cpointer_set_long", "handle index value"),
        abiParity.nt("kk_cpointer_set_ulong", "handle index value"),
        abiParity.nt("kk_cpointer_set_float", "handle index value"),
        abiParity.nt("kk_cpointer_set_double", "handle index value"),
        abiParity.nt("kk_cpointer_set_cpointer", "handle index value"),
        abiParity.nt("kk_interpret_cpointer", "nativePtrHandle typeToken"),
        abiParity.nt("kk_long_to_cpointer", "value typeToken"),
        abiParity.nt("kk_cpointer_toKString", "handle"),
        abiParity.nt("kk_string_to_cptr", "scope stringHandle"),
        abiParity.nt("kk_cvalues_get_pointer", "cvaluesHandle scope"),
        abiParity.nt("kk_native_ptr_toLong", "handle"),
        abiParity.nt("kk_native_null_ptr"),
        abiParity.nt("kk_cinterop_sizeof", "typeToken"),
        abiParity.nt("kk_cinterop_alignof", "typeToken"),
        flowCatchSpec,
        flowOnCompletionSpec,
        flowOnErrorResumeSpec,
        flowOnErrorReturnSpec,
        flowRetrySpec,
        flowRetryWhenSpec,
        // KSP-676: kk_flow_state_in removed — Flow.stateIn is bundled Kotlin source.
        abiParity.th("kk_freeze_object", "objectRaw"),
        abiParity.th("kk_future_complete", "futureHandle valueRaw"),
        abiParity.th("kk_future_consume", "futureHandle"),
        abiParity.th("kk_future_new"),
        abiParity.th("kk_future_result", "futureHandle"),
        abiParity.th("__kk_input_stream_mark", "streamRaw readLimitRaw"),
        abiParity.th("__kk_input_stream_mark_supported", "streamRaw"),
        abiParity.th("__kk_input_stream_reset", "streamRaw outThrown"),
        // kotlin.io.createTempDir/createTempFile (Deprecated(level=ERROR)):
        // real stdlib functions, not File's own facade. Restored after being
        // dropped as an unintended side effect of CLEANUP-STUB-107.
        abiParity.th("__kk_io_createTempDir", "prefixRaw suffixRaw directoryRaw outThrown"),
        abiParity.th("__kk_io_createTempDir_default", "outThrown"),
        abiParity.th("__kk_io_createTempDir_prefix", "prefixRaw outThrown"),
        abiParity.th("__kk_io_createTempDir_prefix_suffix", "prefixRaw suffixRaw outThrown"),
        abiParity.th("__kk_io_createTempFile", "prefixRaw suffixRaw directoryRaw outThrown"),
        abiParity.th("__kk_io_createTempFile_default", "outThrown"),
        abiParity.th("__kk_io_createTempFile_prefix", "prefixRaw outThrown"),
        abiParity.th("__kk_io_createTempFile_prefix_suffix", "prefixRaw suffixRaw outThrown"),
        abiParity.th("kk_iterator_hasNext", "iterRaw outThrown"),
        iteratorNextSpec,
        abiParity.nt("__kk_kclass_is_final", "kclassRaw"),
        abiParity.nt("__kk_kclass_is_open", "kclassRaw"),
        abiParity.th("__kk_kclass_register_member", "kclassRaw memberRaw"),
        abiParity.nt("__kk_kclass_supertypes", "kclassRaw"),
        abiParity.nt("__kk_kclass_type_parameters", "kclassRaw"),
        abiParity.nt("__kk_kclass_visibility", "kclassRaw"),
        abiParity.nt("__kk_long_range_average", "rangeRaw"),
        abiParity.th("__kk_long_range_drop", "rangeRaw n outThrown"),
        abiParity.nt("__kk_long_range_sorted", "rangeRaw"),
        abiParity.th("__kk_long_range_take", "rangeRaw n outThrown"),
        abiParity.nt("__kk_match_result_next", "matchRaw"),
        abiParity.th("__kk_match_result_destructured", "matchRaw"),
        abiParity.th("__kk_match_result_destructured_match", "destructuredRaw"),
        mathESpec,
        mathPiSpec,
        memScopeAllocSpec,
        memScopeEnterSpec,
        memScopeExitSpec,
        // KSP-676: MutableStateFlow is bundled Kotlin source; these C bridges are gone.
        nativeAllocBytesSpec,
        // KSP-717: __kk_normalization_form_nfc/nfd/nfkc/nfkd removed. Their
        // tag values are plain Kotlin constants now (StringNormalize.kt).
        abiParity.th("kk_pin_object", "objectRaw"),
        abiParity.th("kk_pinned_get", "pinnedHandle"),
        abiParity.nt("__kk_range_average", "rangeRaw"),
        abiParity.th("__kk_range_drop", "rangeRaw n outThrown"),
        abiParity.nt("__kk_range_sorted", "rangeRaw"),
        abiParity.th("__kk_range_take", "rangeRaw n outThrown"),
        abiParity.th("kk_regex_matches_flat", "regexRaw data:nullableConstUInt8Pointer length byteCount hash"),

        abiParity.th("__kk_sequence_input_stream_new", "firstRaw secondRaw"),
        abiParity.th("__kk_sequence_input_stream_read", "streamRaw outThrown"),
        abiParity.nt("kk_stable_ref_create", "objectRaw"),
        abiParity.nt("kk_stable_ref_deref", "pointerHandle"),
        abiParity.nt("kk_stable_ref_dispose", "pointerHandle"),
        // KSP-413: kk_string_contentEquals_flat / kk_string_contentEquals_ignoreCase_flat
        // removed; contentEquals is bundled Kotlin source (StringComparison.kt).
        // KSP-717: both bridges are plain (non-throwing) flat-string helpers
        // in RuntimeStringStdlib.swift (no outThrown parameter) — explicit
        // isThrowing: false overrides abiParitySpec's throwing-by-default,
        // matching the real Swift signature (found via
        // RuntimeABIExternalLinkValidationTests once these gained a Kotlin
        // `@KsSymbolName` declaration in StringNormalize.kt).
        abiParity.nt("__kk_string_isNormalized_flat", "receiverData:nullableConstUInt8Pointer receiverLength receiverByteCount receiverHash formTagRaw"),
        abiParity.nt("__kk_string_normalize_flat", "receiverData:nullableConstUInt8Pointer receiverLength receiverByteCount receiverHash formTagRaw outLength:nullableIntptrPointer outByteCount:nullableIntptrPointer outHash:nullableIntptrPointer", ret: .nullableUInt8Pointer),
        abiParity.th("__kk_string_toByte_flat", "data:nullableConstUInt8Pointer length byteCount hash outThrown"),
        abiParity.th("__kk_string_toByte", "strRaw outThrown"),
        abiParity.th("__kk_string_toByte_radix_flat", "data:nullableConstUInt8Pointer length byteCount hash radix outThrown"),
        abiParity.th("__kk_string_toByte_radix", "strRaw radix outThrown"),
        abiParity.nt("__kk_string_toByteOrNull_flat", "data:nullableConstUInt8Pointer length byteCount hash"),
        abiParity.nt("__kk_string_toShortOrNull_flat", "data:nullableConstUInt8Pointer length byteCount hash"),
        abiParity.th("__kk_string_toShort_flat", "data:nullableConstUInt8Pointer length byteCount hash outThrown"),
        abiParity.th("__kk_string_toShort", "strRaw outThrown"),
        abiParity.th("kk_suspend_coroutine", "fnPtr closureRaw continuation outThrown"),
        abiParity.th("kk_transfer_object", "objectRaw modeRaw"),
        abiParity.th("__kk_uint_range_drop", "rangeRaw n outThrown"),
        abiParity.th("__kk_uint_range_take", "rangeRaw n outThrown"),
        abiParity.th("__kk_ulong_range_drop", "rangeRaw n outThrown"),
        abiParity.th("__kk_ulong_range_take", "rangeRaw n outThrown"),
        abiParity.th("kk_unpin_object", "pinnedHandle"),
        abiParity.nt("kk_worker_execute", "workerHandle modeRaw producerFnPtr producerClosureRaw jobFnPtr jobClosureRaw"),
        abiParity.nt("kk_worker_as_cpointer", "workerHandle"),
        abiParity.nt("kk_worker_execute_after", "workerHandle afterMicroseconds fnPtr closureRaw"),
        abiParity.nt("kk_worker_id", "workerHandle"),
        abiParity.th("kk_worker_is_terminated", "workerHandle"),
        abiParity.nt("kk_worker_name", "workerHandle"),
        abiParity.th("kk_worker_new", "nameRaw"),
        abiParity.nt("kk_worker_park", "workerHandle timeoutMicroseconds processRaw"),
        abiParity.nt("kk_worker_platform_thread_id", "workerHandle"),
        abiParity.nt("kk_worker_process_queue", "workerHandle"),
        abiParity.nt("kk_worker_request_termination", "workerHandle processScheduledRaw"),
    ]
}
