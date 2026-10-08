// Residual ABI specs not yet assigned to a categorized RuntimeABISpec section.
// Runtime-backed entries below are generated from Sources/Runtime exported C symbols.

public extension RuntimeABISpec {
    static let intToIntSpec: RuntimeABIFunctionSpec = abiParitySpec("kk_int_to_int", parameters: [
        p("value", .intptr),
    ])

    static let callableRefCall0Spec: RuntimeABIFunctionSpec = abiParitySpec("kk_callable_ref_call_0", parameters: [
        p("tagged", .intptr),
        p("outThrown", .nullableIntptrPointer),
    ])

    static let callableRefCall1Spec: RuntimeABIFunctionSpec = abiParitySpec("kk_callable_ref_call_1", parameters: [
        p("tagged", .intptr),
        p("arg", .intptr),
        p("outThrown", .nullableIntptrPointer),
    ])

    static let callableRefCall2Spec: RuntimeABIFunctionSpec = abiParitySpec("kk_callable_ref_call_2", parameters: [
        p("tagged", .intptr),
        p("arg1", .intptr),
        p("arg2", .intptr),
        p("outThrown", .nullableIntptrPointer),
    ])

    static let callableRefCall3Spec: RuntimeABIFunctionSpec = abiParitySpec("kk_callable_ref_call_3", parameters: [
        p("tagged", .intptr),
        p("arg1", .intptr),
        p("arg2", .intptr),
        p("arg3", .intptr),
        p("outThrown", .nullableIntptrPointer),
    ])

    static let channelSendSuspendingSpec: RuntimeABIFunctionSpec = abiParitySpec("kk_channel_send_suspending", parameters: [
        p("handle", .intptr),
        p("value", .intptr),
        p("continuation", .intptr),
    ])

    static let flowCatchSpec: RuntimeABIFunctionSpec = abiParitySpec("kk_flow_catch", parameters: [
        p("flowHandle", .intptr),
        p("handlerFnPtr", .intptr),
        p("arg2", .intptr),
    ])

    static let flowOnCompletionSpec: RuntimeABIFunctionSpec = abiParitySpec("kk_flow_on_completion", parameters: [
        p("flowHandle", .intptr),
        p("handlerFnPtr", .intptr),
        p("arg2", .intptr),
    ])

    static let flowOnErrorResumeSpec: RuntimeABIFunctionSpec = abiParitySpec("kk_flow_on_error_resume", parameters: [
        p("flowHandle", .intptr),
        p("fallbackFlowHandle", .intptr),
        p("arg2", .intptr),
    ])

    static let flowOnErrorReturnSpec: RuntimeABIFunctionSpec = abiParitySpec("kk_flow_on_error_return", parameters: [
        p("flowHandle", .intptr),
        p("fallbackValue", .intptr),
        p("arg2", .intptr),
    ])

    static let flowRetrySpec: RuntimeABIFunctionSpec = abiParitySpec("kk_flow_retry", parameters: [
        p("flowHandle", .intptr),
        p("retries", .intptr),
        p("arg2", .intptr),
    ])

    static let flowRetryWhenSpec: RuntimeABIFunctionSpec = abiParitySpec("kk_flow_retry_when", parameters: [
        p("flowHandle", .intptr),
        p("predicateFnPtr", .intptr),
        p("arg2", .intptr),
    ])

    static let iteratorNextSpec: RuntimeABIFunctionSpec = abiParitySpec("kk_iterator_next", parameters: [
        p("iterRaw", .intptr),
        p("outThrown", .nullableIntptrPointer),
    ])

    static let mathESpec: RuntimeABIFunctionSpec = abiParitySpec("kk_math_e")

    static let mathPiSpec: RuntimeABIFunctionSpec = abiParitySpec("kk_math_pi")

    static let memScopeAllocSpec: RuntimeABIFunctionSpec = abiParitySpec("kk_mem_scope_alloc", parameters: [
        p("scopeHandle", .intptr),
        p("byteCount", .intptr),
    ])

    static let memScopeEnterSpec: RuntimeABIFunctionSpec = abiParitySpec("kk_mem_scope_enter")

    static let memScopeExitSpec: RuntimeABIFunctionSpec = abiParitySpec("kk_mem_scope_exit", parameters: [
        p("handle", .intptr),
    ])

    static let nativeAllocBytesSpec: RuntimeABIFunctionSpec = abiParitySpec("kk_native_alloc_bytes", parameters: [
        p("byteCount", .intptr),
    ])

    static let abiParityFunctions: [RuntimeABIFunctionSpec] = [
        abiParitySpec("__kk_any_javaClass", parameters: [
            p("receiverRaw", .intptr),
        ], isThrowing: false),
        abiParitySpec("kk_future_getState", parameters: [
            p("futureRaw", .intptr),
        ]),
        abiParitySpec("kk_future_invoke", parameters: [
            p("fnPtr", .intptr),
            p("closureRaw", .intptr),
            p("valueRaw", .intptr),
            p("outThrown", .nullableIntptrPointer),
        ]),
        intToIntSpec,
        // Runtime @_cdecl entries awaiting a dedicated RuntimeABISpec category.
        abiParitySpec("component1", parameters: [
            p("pairRaw", .intptr),
        ]),
        abiParitySpec("component2", parameters: [
            p("pairRaw", .intptr),
        ]),
        abiParitySpec("kk_atomic_ref_array_compareAndExchangeAt", parameters: [
            p("receiver", .intptr),
            p("index", .intptr),
            p("expect", .intptr),
            p("update", .intptr),
        ]),
        abiParitySpec("kk_atomic_ref_array_loadAt", parameters: [
            p("receiver", .intptr),
            p("index", .intptr),
        ]),
        abiParitySpec("kk_atomic_ref_array_new", parameters: [
            p("size", .intptr),
        ]),
        abiParitySpec("kk_atomic_ref_array_size", parameters: [
            p("receiver", .intptr),
        ]),
        abiParitySpec("kk_atomic_ref_array_storeAt", parameters: [
            p("receiver", .intptr),
            p("index", .intptr),
            p("value", .intptr),
        ]),
        callableRefCall0Spec,
        callableRefCall1Spec,
        callableRefCall2Spec,
        callableRefCall3Spec,
        // KSP-678: these Channel residuals are bridged from bundled Kotlin
        // (Channels.kt) and return a plain Int handle/flag; they do not use the
        // outThrown ABI lowering path.
        abiParitySpec("kk_channel_is_closed_for_receive", parameters: [
            p("handle", .intptr),
        ], isThrowing: false),
        abiParitySpec("kk_channel_is_closed_for_send", parameters: [
            p("handle", .intptr),
        ], isThrowing: false),
        abiParitySpec("kk_channel_iterator", parameters: [
            p("handle", .intptr),
        ], isThrowing: false),
        // KUU-1404: hasNext on a cancelled channel throws CancellationException
        // through the outThrown channel (JVM parity); plain close still
        // terminates iteration with a 0 return.
        abiParitySpec("kk_channel_iterator_hasNext", parameters: [
            p("iterHandle", .intptr),
            p("outThrown", .nullableIntptrPointer),
        ]),
        abiParitySpec("kk_channel_iterator_next", parameters: [
            p("iterHandle", .intptr),
        ], isThrowing: false),
        // KSP-1571: same KSP-678 pattern — close-cause retention, isEmpty, and
        // cancel are bridged from bundled Kotlin (Channel.kt /
        // ChannelResult.kt) as plain Int-token residuals; they do not use the
        // outThrown ABI lowering path.
        abiParitySpec("kk_channel_is_empty", parameters: [
            p("handle", .intptr),
        ], isThrowing: false),
        abiParitySpec("kk_channel_close_cause", parameters: [
            p("handle", .intptr),
        ], isThrowing: false),
        abiParitySpec("__kk_channel_close_cause", parameters: [
            p("handle", .intptr),
            p("cause", .intptr),
        ], isThrowing: false),
        abiParitySpec("__kk_channel_cancel", parameters: [
            p("handle", .intptr),
            p("cause", .intptr),
        ], isThrowing: false),
        // KSP-1571: ChannelResult box accessors added on top of KSP-1572's
        // box-returning `__kk_channel_*` bridges (registered in the Coroutine
        // section): `cause` reads the retained close cause and `create` backs
        // the companion `success`/`failure`/`closed` factories.
        abiParitySpec("__kk_channel_result_cause", parameters: [
            p("boxRaw", .intptr),
        ], isThrowing: false),
        abiParitySpec("__kk_channel_result_create", parameters: [
            p("status", .intptr),
            p("value", .intptr),
            p("cause", .intptr),
        ], isThrowing: false),
        channelSendSuspendingSpec,
        abiParitySpec("kk_char_isISOControl", parameters: [
            p("value", .intptr),
        ]),
        abiParitySpec("kk_char_isTitleCase", parameters: [
            p("value", .intptr),
        ]),

        abiParitySpec("kk_cname_lookup", parameters: [
            p("externNameRaw", .intptr),
        ]),
        abiParitySpec("kk_cname_register", parameters: [
            p("externNameRaw", .intptr),
            p("fnPtr", .intptr),
        ]),
        abiParitySpec("kk_copaque_pointer_address", parameters: [
            p("handle", .intptr),
        ]),
        abiParitySpec("kk_copaque_pointer_new", parameters: [
            p("address", .intptr),
        ]),
        abiParitySpec("__kk_cancellable_continuation_new", parameters: [p("delegate", .intptr)]),
        abiParitySpec("__kk_cancellable_continuation_state", parameters: [p("handle", .intptr)]),
        abiParitySpec("__kk_cancellable_continuation_resume", parameters: [
            p("handle", .intptr), p("result", .intptr), p("callback", .intptr),
            p("outThrown", .nullableIntptrPointer),
        ], returnType: .void),
        abiParitySpec("__kk_cancellable_continuation_cancel", parameters: [p("handle", .intptr), p("cause", .intptr)]),
        abiParitySpec("__kk_cancellable_continuation_invoke_on_cancellation", parameters: [
            p("handle", .intptr), p("handler", .intptr), p("outThrown", .nullableIntptrPointer),
        ], returnType: .void),
        abiParitySpec("__kk_cancellable_continuation_try_resume", parameters: [
            p("handle", .intptr), p("result", .intptr), p("idempotent", .intptr),
        ]),
        abiParitySpec("__kk_cancellable_continuation_complete_resume", parameters: [
            p("handle", .intptr), p("token", .intptr), p("outThrown", .nullableIntptrPointer),
        ], returnType: .void),
        abiParitySpec("__kk_cancellable_continuation_get_result", parameters: [
            p("handle", .intptr), p("outThrown", .nullableIntptrPointer),
        ]),
        abiParitySpec("__kk_coroutine_continuation_context", parameters: [
            p("continuation", .intptr),
            p("outThrown", .nullableIntptrPointer),
        ]),
        abiParitySpec("__kk_coroutine_continuation_resume_with", parameters: [
            p("continuation", .intptr),
            p("resultRaw", .intptr),
            p("outThrown", .nullableIntptrPointer),
        ], returnType: .void),
        abiParitySpec("kk_coroutine_continuation_context", parameters: [
            p("continuation", .intptr),
        ]),
        abiParitySpec("kk_coroutine_continuation_resume", parameters: [
            p("continuation", .intptr),
            p("value", .intptr),
        ], returnType: .void),
        abiParitySpec("kk_coroutine_continuation_resume_with", parameters: [
            p("continuation", .intptr),
            p("resultRaw", .intptr),
        ], returnType: .void),
        abiParitySpec("kk_coroutine_continuation_resume_with_exception", parameters: [
            p("continuation", .intptr),
            p("exception", .intptr),
        ], returnType: .void),
        abiParitySpec("kk_cpointer_address", parameters: [
            p("handle", .intptr),
        ]),
        abiParitySpec("kk_cpointer_new", parameters: [
            p("address", .intptr),
        ]),
        abiParitySpec("kk_cpointer_toLong", parameters: [
            p("handle", .intptr),
        ]),
        abiParitySpec("kk_cpointer_toKStringFromUtf32", parameters: [
            p("handle", .intptr),
        ]),
        abiParitySpec("kk_cpointer_toKStringFromUtf16", parameters: [
            p("handle", .intptr),
        ]),
        abiParitySpec("kk_byteArray_toCValues", parameters: [
            p("arrayRaw", .intptr),
        ],
            isThrowing: false),
        // STDLIB-CINTEROP-FN-029: ByteArray.toKString(startIndex, endIndex, throwOnInvalidSequence)
        abiParitySpec("__kk_byteArray_toKString", parameters: [
            p("arrRaw", .intptr),
            p("startIndex", .intptr),
            p("endIndex", .intptr),
            p("throwOnInvalidSequence", .intptr),
            p("outThrown", .nullableIntptrPointer),
        ]),
        abiParitySpec("kk_cinterop_writeBits", parameters: [
            p("ptr", .intptr),
            p("offset", .intptr),
            p("size", .intptr),
            p("value", .intptr),
        ],
            returnType: .void,
            isThrowing: false),
        abiParitySpec("kk_uLongArray_toCValues", parameters: [
            p("arrayRaw", .intptr),
        ],
            isThrowing: false),
        abiParitySpec("kk_uIntArray_toCValues", parameters: [
            p("arrayRaw", .intptr),
        ],
            isThrowing: false),
        abiParitySpec("kk_uByteArray_toCValues", parameters: [
            p("arrayRaw", .intptr),
        ],
            isThrowing: false),
        // KUU-1375: kotlinx.cinterop arena / variable / pointer bridges.
        abiParitySpec("kk_memscope_new", isThrowing: false),
        abiParitySpec("kk_arena_new", isThrowing: false),
        abiParitySpec("kk_native_heap_get", isThrowing: false),
        abiParitySpec("kk_arena_alloc_raw", parameters: [
            p("scope", .intptr),
            p("size", .intptr),
            p("align", .intptr),
        ], isThrowing: false),
        abiParitySpec("kk_arena_alloc_var", parameters: [
            p("scope", .intptr),
            p("typeToken", .intptr),
        ], isThrowing: false),
        abiParitySpec("kk_arena_alloc_array", parameters: [
            p("scope", .intptr),
            p("count", .intptr),
            p("typeToken", .intptr),
        ], isThrowing: false),
        abiParitySpec("kk_native_placement_free", parameters: [
            p("scope", .intptr),
            p("pointerHandle", .intptr),
        ], isThrowing: false),
        abiParitySpec("kk_defer_scope_defer", parameters: [
            p("scope", .intptr),
            p("block", .intptr),
        ], isThrowing: false),
        abiParitySpec("kk_arena_clear", parameters: [
            p("scope", .intptr),
            p("outThrown", .nullableIntptrPointer),
        ]),
        abiParitySpec("kk_cvar_ptr", parameters: [
            p("varHandle", .intptr),
        ], isThrowing: false),
        abiParitySpec("kk_cvar_raw_ptr", parameters: [
            p("varHandle", .intptr),
        ], isThrowing: false),
        abiParitySpec("kk_cvar_bool_load", parameters: [
            p("varHandle", .intptr),
        ], isThrowing: false),
        abiParitySpec("kk_cvar_bool_store", parameters: [
            p("varHandle", .intptr),
            p("value", .intptr),
        ], isThrowing: false),
        abiParitySpec("kk_cvar_byte_load", parameters: [
            p("varHandle", .intptr),
        ], isThrowing: false),
        abiParitySpec("kk_cvar_byte_store", parameters: [
            p("varHandle", .intptr),
            p("value", .intptr),
        ], isThrowing: false),
        abiParitySpec("kk_cvar_ubyte_load", parameters: [
            p("varHandle", .intptr),
        ], isThrowing: false),
        abiParitySpec("kk_cvar_ubyte_store", parameters: [
            p("varHandle", .intptr),
            p("value", .intptr),
        ], isThrowing: false),
        abiParitySpec("kk_cvar_short_load", parameters: [
            p("varHandle", .intptr),
        ], isThrowing: false),
        abiParitySpec("kk_cvar_short_store", parameters: [
            p("varHandle", .intptr),
            p("value", .intptr),
        ], isThrowing: false),
        abiParitySpec("kk_cvar_ushort_load", parameters: [
            p("varHandle", .intptr),
        ], isThrowing: false),
        abiParitySpec("kk_cvar_ushort_store", parameters: [
            p("varHandle", .intptr),
            p("value", .intptr),
        ], isThrowing: false),
        abiParitySpec("kk_cvar_int_load", parameters: [
            p("varHandle", .intptr),
        ], isThrowing: false),
        abiParitySpec("kk_cvar_int_store", parameters: [
            p("varHandle", .intptr),
            p("value", .intptr),
        ], isThrowing: false),
        abiParitySpec("kk_cvar_uint_load", parameters: [
            p("varHandle", .intptr),
        ], isThrowing: false),
        abiParitySpec("kk_cvar_uint_store", parameters: [
            p("varHandle", .intptr),
            p("value", .intptr),
        ], isThrowing: false),
        abiParitySpec("kk_cvar_long_load", parameters: [
            p("varHandle", .intptr),
        ], isThrowing: false),
        abiParitySpec("kk_cvar_long_store", parameters: [
            p("varHandle", .intptr),
            p("value", .intptr),
        ], isThrowing: false),
        abiParitySpec("kk_cvar_ulong_load", parameters: [
            p("varHandle", .intptr),
        ], isThrowing: false),
        abiParitySpec("kk_cvar_ulong_store", parameters: [
            p("varHandle", .intptr),
            p("value", .intptr),
        ], isThrowing: false),
        abiParitySpec("kk_cvar_float_load", parameters: [
            p("varHandle", .intptr),
        ], isThrowing: false),
        abiParitySpec("kk_cvar_float_store", parameters: [
            p("varHandle", .intptr),
            p("value", .intptr),
        ], isThrowing: false),
        abiParitySpec("kk_cvar_double_load", parameters: [
            p("varHandle", .intptr),
        ], isThrowing: false),
        abiParitySpec("kk_cvar_double_store", parameters: [
            p("varHandle", .intptr),
            p("value", .intptr),
        ], isThrowing: false),
        abiParitySpec("kk_cvar_cpointer_load", parameters: [
            p("varHandle", .intptr),
        ], isThrowing: false),
        abiParitySpec("kk_cvar_cpointer_store", parameters: [
            p("varHandle", .intptr),
            p("value", .intptr),
        ], isThrowing: false),
        abiParitySpec("kk_cpointer_pointed", parameters: [
            p("handle", .intptr),
        ], isThrowing: false),
        abiParitySpec("kk_cpointer_get", parameters: [
            p("handle", .intptr),
            p("index", .intptr),
        ], isThrowing: false),
        abiParitySpec("kk_cpointer_reinterpret", parameters: [
            p("handle", .intptr),
            p("typeToken", .intptr),
        ], isThrowing: false),
        abiParitySpec("kk_interpret_cpointer", parameters: [
            p("nativePtrHandle", .intptr),
            p("typeToken", .intptr),
        ], isThrowing: false),
        abiParitySpec("kk_long_to_cpointer", parameters: [
            p("value", .intptr),
            p("typeToken", .intptr),
        ], isThrowing: false),
        abiParitySpec("kk_cpointer_toKString", parameters: [
            p("handle", .intptr),
        ], isThrowing: false),
        abiParitySpec("kk_string_to_cptr", parameters: [
            p("scope", .intptr),
            p("stringHandle", .intptr),
        ], isThrowing: false),
        abiParitySpec("kk_cvalues_get_pointer", parameters: [
            p("cvaluesHandle", .intptr),
            p("scope", .intptr),
        ], isThrowing: false),
        abiParitySpec("kk_native_ptr_of", parameters: [
            p("value", .intptr),
        ], isThrowing: false),
        abiParitySpec("kk_native_ptr_toLong", parameters: [
            p("handle", .intptr),
        ], isThrowing: false),
        abiParitySpec("kk_native_null_ptr", isThrowing: false),
        abiParitySpec("kk_cinterop_sizeof", parameters: [
            p("typeToken", .intptr),
        ], isThrowing: false),
        abiParitySpec("kk_cinterop_alignof", parameters: [
            p("typeToken", .intptr),
        ], isThrowing: false),
        flowCatchSpec,
        abiParitySpec("__kk_flow_emit_with_timestamp", parameters: [
            p("flowHandle", .intptr),
            p("value", .intptr),
            p("tag", .intptr),
            p("timestamp", .uint64),
        ]),
        flowOnCompletionSpec,
        flowOnErrorResumeSpec,
        flowOnErrorReturnSpec,
        flowRetrySpec,
        flowRetryWhenSpec,
        // KSP-676: kk_flow_state_in removed — Flow.stateIn is bundled Kotlin source.
        abiParitySpec("kk_freeze_object", parameters: [
            p("objectRaw", .intptr),
        ]),
        abiParitySpec("kk_future_complete", parameters: [
            p("futureHandle", .intptr),
            p("valueRaw", .intptr),
        ]),
        abiParitySpec("kk_future_consume", parameters: [
            p("futureHandle", .intptr),
        ]),
        abiParitySpec("kk_future_is_ready", parameters: [
            p("futureHandle", .intptr),
        ]),
        abiParitySpec("kk_future_new"),
        abiParitySpec("kk_future_result", parameters: [
            p("futureHandle", .intptr),
        ]),
        abiParitySpec("kk_http_body_handlers_ofString", parameters: [
            p("bodyHandlersRaw", .intptr),
        ],
            isThrowing: false),
        abiParitySpec("kk_http_body_publishers_noBody", parameters: [
            p("bodyPublishersRaw", .intptr),
        ],
            isThrowing: false),
        abiParitySpec("kk_http_body_publishers_ofString", parameters: [
            p("bodyPublishersRaw", .intptr),
            p("bodyRaw", .intptr),
        ],
            isThrowing: false),
        abiParitySpec("kk_http_client_newHttpClient",
            isThrowing: false),
        abiParitySpec("kk_http_client_send", parameters: [
            p("clientRaw", .intptr),
            p("requestRaw", .intptr),
            p("bodyHandlerRaw", .intptr),
            p("outThrown", .nullableIntptrPointer),
        ]),
        abiParitySpec("kk_http_headers_firstValue", parameters: [
            p("headersRaw", .intptr),
            p("nameRaw", .intptr),
        ],
            isThrowing: false),
        abiParitySpec("kk_http_headers_map", parameters: [
            p("headersRaw", .intptr),
        ],
            isThrowing: false),
        abiParitySpec("kk_http_request_builder_build", parameters: [
            p("builderRaw", .intptr),
            p("outThrown", .nullableIntptrPointer),
        ]),
        abiParitySpec("kk_http_request_builder_GET", parameters: [
            p("builderRaw", .intptr),
        ],
            isThrowing: false),
        abiParitySpec("kk_http_request_builder_header", parameters: [
            p("builderRaw", .intptr),
            p("nameRaw", .intptr),
            p("valueRaw", .intptr),
        ],
            isThrowing: false),
        abiParitySpec("kk_http_request_builder_POST", parameters: [
            p("builderRaw", .intptr),
            p("publisherRaw", .intptr),
        ],
            isThrowing: false),
        abiParitySpec("kk_http_request_builder_uri", parameters: [
            p("builderRaw", .intptr),
            p("uriRaw", .intptr),
        ],
            isThrowing: false),
        abiParitySpec("kk_http_request_newBuilder",
            isThrowing: false),
        abiParitySpec("kk_http_request_newBuilder_uri", parameters: [
            p("uriRaw", .intptr),
        ],
            isThrowing: false),
        abiParitySpec("kk_http_response_headers", parameters: [
            p("responseRaw", .intptr),
        ],
            isThrowing: false),
        abiParitySpec("__kk_input_stream_mark", parameters: [
            p("streamRaw", .intptr),
            p("readLimitRaw", .intptr),
        ]),
        abiParitySpec("__kk_input_stream_mark_supported", parameters: [
            p("streamRaw", .intptr),
        ]),
        abiParitySpec("__kk_input_stream_reset", parameters: [
            p("streamRaw", .intptr),
            p("outThrown", .nullableIntptrPointer),
        ]),
        // kotlin.io.createTempDir/createTempFile (Deprecated(level=ERROR)):
        // real stdlib functions, not File's own facade. Restored after being
        // dropped as an unintended side effect of CLEANUP-STUB-107.
        abiParitySpec("__kk_io_createTempDir", parameters: [
            p("prefixRaw", .intptr),
            p("suffixRaw", .intptr),
            p("directoryRaw", .intptr),
            p("outThrown", .nullableIntptrPointer),
        ]),
        abiParitySpec("__kk_io_createTempDir_default", parameters: [
            p("outThrown", .nullableIntptrPointer),
        ]),
        abiParitySpec("__kk_io_createTempDir_prefix", parameters: [
            p("prefixRaw", .intptr),
            p("outThrown", .nullableIntptrPointer),
        ]),
        abiParitySpec("__kk_io_createTempDir_prefix_suffix", parameters: [
            p("prefixRaw", .intptr),
            p("suffixRaw", .intptr),
            p("outThrown", .nullableIntptrPointer),
        ]),
        abiParitySpec("__kk_io_createTempFile", parameters: [
            p("prefixRaw", .intptr),
            p("suffixRaw", .intptr),
            p("directoryRaw", .intptr),
            p("outThrown", .nullableIntptrPointer),
        ]),
        abiParitySpec("__kk_io_createTempFile_default", parameters: [
            p("outThrown", .nullableIntptrPointer),
        ]),
        abiParitySpec("__kk_io_createTempFile_prefix", parameters: [
            p("prefixRaw", .intptr),
            p("outThrown", .nullableIntptrPointer),
        ]),
        abiParitySpec("__kk_io_createTempFile_prefix_suffix", parameters: [
            p("prefixRaw", .intptr),
            p("suffixRaw", .intptr),
            p("outThrown", .nullableIntptrPointer),
        ]),
        abiParitySpec("kk_is_frozen", parameters: [
            p("objectRaw", .intptr),
        ]),
        abiParitySpec("kk_iterator_hasNext", parameters: [
            p("iterRaw", .intptr),
            p("outThrown", .nullableIntptrPointer),
        ]),
        iteratorNextSpec,
        abiParitySpec("__kk_kclass_is_final", parameters: [
            p("kclassRaw", .intptr),
        ],
            isThrowing: false),
        abiParitySpec("__kk_kclass_is_open", parameters: [
            p("kclassRaw", .intptr),
        ],
            isThrowing: false),
        abiParitySpec("__kk_kclass_register_member", parameters: [
            p("kclassRaw", .intptr),
            p("memberRaw", .intptr),
        ]),
        abiParitySpec("__kk_kclass_register_metadata_v2", parameters: [
            p("typeToken", .intptr),
            p("qualifiedNameRaw", .intptr),
            p("simpleNameRaw", .intptr),
            p("supertypeNameRaw", .intptr),
            p("flags", .intptr),
            p("fieldCount", .intptr),
            p("memberCount", .intptr),
            p("constructorCount", .intptr),
            p("visibilityRaw", .intptr),
            p("typeParameterCount", .intptr),
        ]),
        abiParitySpec("__kk_kclass_supertypes", parameters: [
            p("kclassRaw", .intptr),
        ],
            isThrowing: false),
        abiParitySpec("__kk_kclass_type_parameters", parameters: [
            p("kclassRaw", .intptr),
        ],
            isThrowing: false),
        abiParitySpec("__kk_kclass_visibility", parameters: [
            p("kclassRaw", .intptr),
        ],
            isThrowing: false),
        abiParitySpec("__kk_long_range_average", parameters: [
            p("rangeRaw", .intptr),
        ],
            isThrowing: false),
        abiParitySpec("__kk_long_range_drop", parameters: [
            p("rangeRaw", .intptr),
            p("n", .intptr),
            p("outThrown", .nullableIntptrPointer),
        ]),
        abiParitySpec("__kk_long_range_sorted", parameters: [
            p("rangeRaw", .intptr),
        ],
            isThrowing: false),
        abiParitySpec("__kk_long_range_take", parameters: [
            p("rangeRaw", .intptr),
            p("n", .intptr),
            p("outThrown", .nullableIntptrPointer),
        ]),
        // KSP-486: MatchResult iteration / destructuring bridges
        abiParitySpec("__kk_match_result_next", parameters: [
            p("matchRaw", .intptr),
        ],
            isThrowing: false),
        // STDLIB-TEXT-TYPE-010: MatchResult.Destructured
        abiParitySpec("__kk_match_result_destructured", parameters: [
            p("matchRaw", .intptr),
        ]),
        abiParitySpec("__kk_match_result_destructured_match", parameters: [
            p("destructuredRaw", .intptr),
        ]),
        mathESpec,
        mathPiSpec,
        memScopeAllocSpec,
        memScopeEnterSpec,
        memScopeExitSpec,
        // KSP-676: MutableStateFlow is bundled Kotlin source; these C bridges are gone.
        nativeAllocBytesSpec,
        // KSP-717: __kk_normalization_form_nfc/nfd/nfkc/nfkd removed. Their
        // tag values are plain Kotlin constants now (StringNormalize.kt).
        abiParitySpec("kk_pin_object", parameters: [
            p("objectRaw", .intptr),
        ]),
        abiParitySpec("kk_pinned_get", parameters: [
            p("pinnedHandle", .intptr),
        ]),
        abiParitySpec("kk_range_average", parameters: [
            p("rangeRaw", .intptr),
        ],
            isThrowing: false),
        abiParitySpec("kk_range_drop", parameters: [
            p("rangeRaw", .intptr),
            p("n", .intptr),
            p("outThrown", .nullableIntptrPointer),
        ]),
        abiParitySpec("kk_range_sorted", parameters: [
            p("rangeRaw", .intptr),
        ],
            isThrowing: false),
        abiParitySpec("kk_range_take", parameters: [
            p("rangeRaw", .intptr),
            p("n", .intptr),
            p("outThrown", .nullableIntptrPointer),
        ]),
        abiParitySpec("kk_regex_matches_flat", parameters: [
            p("regexRaw", .intptr),
            p("data", .nullableConstUInt8Pointer),
            p("length", .intptr),
            p("byteCount", .intptr),
            p("hash", .intptr),
        ]),

        abiParitySpec("__kk_sequence_input_stream_available", parameters: [
            p("streamRaw", .intptr),
        ]),
        abiParitySpec("__kk_sequence_input_stream_close", parameters: [
            p("streamRaw", .intptr),
        ]),
        abiParitySpec("__kk_sequence_input_stream_new", parameters: [
            p("firstRaw", .intptr),
            p("secondRaw", .intptr),
        ]),
        abiParitySpec("__kk_sequence_input_stream_read", parameters: [
            p("streamRaw", .intptr),
            p("outThrown", .nullableIntptrPointer),
        ]),
        abiParitySpec("kk_stable_ref_create", parameters: [
            p("objectRaw", .intptr),
        ], isThrowing: false),
        abiParitySpec("kk_stable_ref_deref", parameters: [
            p("pointerHandle", .intptr),
        ], isThrowing: false),
        abiParitySpec("kk_stable_ref_dispose", parameters: [
            p("pointerHandle", .intptr),
        ], isThrowing: false),
        // KSP-413: kk_string_contentEquals_flat / kk_string_contentEquals_ignoreCase_flat
        // removed; contentEquals is bundled Kotlin source (StringComparison.kt).
        // KSP-717: both bridges are plain (non-throwing) flat-string helpers
        // in RuntimeStringStdlib.swift (no outThrown parameter) — explicit
        // isThrowing: false overrides abiParitySpec's throwing-by-default,
        // matching the real Swift signature (found via
        // RuntimeABIExternalLinkValidationTests once these gained a Kotlin
        // `@KsSymbolName` declaration in StringNormalize.kt).
        abiParitySpec("__kk_string_isNormalized_flat", parameters: [
            p("receiverData", .nullableConstUInt8Pointer),
            p("receiverLength", .intptr),
            p("receiverByteCount", .intptr),
            p("receiverHash", .intptr),
            p("formTagRaw", .intptr),
        ], isThrowing: false),
        abiParitySpec("__kk_string_normalize_flat", parameters: [
            p("receiverData", .nullableConstUInt8Pointer),
            p("receiverLength", .intptr),
            p("receiverByteCount", .intptr),
            p("receiverHash", .intptr),
            p("formTagRaw", .intptr),
            p("outLength", .nullableIntptrPointer),
            p("outByteCount", .nullableIntptrPointer),
            p("outHash", .nullableIntptrPointer),
        ], returnType: .nullableUInt8Pointer, isThrowing: false),
        abiParitySpec("__kk_string_toBooleanStrictOrNull_flat", parameters: [
            p("data", .nullableConstUInt8Pointer),
            p("length", .intptr),
            p("byteCount", .intptr),
            p("hash", .intptr),
        ], isThrowing: false),
        abiParitySpec("__kk_string_toByte_flat", parameters: [
            p("data", .nullableConstUInt8Pointer),
            p("length", .intptr),
            p("byteCount", .intptr),
            p("hash", .intptr),
            p("outThrown", .nullableIntptrPointer),
        ]),
        abiParitySpec("__kk_string_toByte", parameters: [
            p("strRaw", .intptr),
            p("outThrown", .nullableIntptrPointer),
        ]),
        abiParitySpec("__kk_string_toByte_radix_flat", parameters: [
            p("data", .nullableConstUInt8Pointer),
            p("length", .intptr),
            p("byteCount", .intptr),
            p("hash", .intptr),
            p("radix", .intptr),
            p("outThrown", .nullableIntptrPointer),
        ]),
        abiParitySpec("__kk_string_toByte_radix", parameters: [
            p("strRaw", .intptr),
            p("radix", .intptr),
            p("outThrown", .nullableIntptrPointer),
        ]),
        abiParitySpec("__kk_string_toByteOrNull_flat", parameters: [
            p("data", .nullableConstUInt8Pointer),
            p("length", .intptr),
            p("byteCount", .intptr),
            p("hash", .intptr),
        ], isThrowing: false),
        abiParitySpec("__kk_string_toShortOrNull_flat", parameters: [
            p("data", .nullableConstUInt8Pointer),
            p("length", .intptr),
            p("byteCount", .intptr),
            p("hash", .intptr),
        ], isThrowing: false),
        abiParitySpec("__kk_string_toShort_flat", parameters: [
            p("data", .nullableConstUInt8Pointer),
            p("length", .intptr),
            p("byteCount", .intptr),
            p("hash", .intptr),
            p("outThrown", .nullableIntptrPointer),
        ]),
        abiParitySpec("__kk_string_toShort", parameters: [
            p("strRaw", .intptr),
            p("outThrown", .nullableIntptrPointer),
        ]),
        abiParitySpec("kk_suspend_coroutine", parameters: [
            p("fnPtr", .intptr),
            p("closureRaw", .intptr),
            p("continuation", .intptr),
            p("outThrown", .nullableIntptrPointer),
        ]),
        abiParitySpec("kk_transfer_object", parameters: [
            p("objectRaw", .intptr),
            p("modeRaw", .intptr),
        ]),
        abiParitySpec("__kk_uint_range_drop", parameters: [
            p("rangeRaw", .intptr),
            p("n", .intptr),
            p("outThrown", .nullableIntptrPointer),
        ]),
        abiParitySpec("__kk_uint_range_take", parameters: [
            p("rangeRaw", .intptr),
            p("n", .intptr),
            p("outThrown", .nullableIntptrPointer),
        ]),
        abiParitySpec("__kk_ulong_range_drop", parameters: [
            p("rangeRaw", .intptr),
            p("n", .intptr),
            p("outThrown", .nullableIntptrPointer),
        ]),
        abiParitySpec("__kk_ulong_range_take", parameters: [
            p("rangeRaw", .intptr),
            p("n", .intptr),
            p("outThrown", .nullableIntptrPointer),
        ]),
        abiParitySpec("kk_unpin_object", parameters: [
            p("pinnedHandle", .intptr),
        ]),
        abiParitySpec("kk_worker_execute", parameters: [
            p("workerHandle", .intptr),
            p("modeRaw", .intptr),
            p("producerFnPtr", .intptr),
            p("producerClosureRaw", .intptr),
            p("jobFnPtr", .intptr),
            p("jobClosureRaw", .intptr),
        ], isThrowing: false),
        abiParitySpec("kk_worker_as_cpointer", parameters: [
            p("workerHandle", .intptr),
        ], isThrowing: false),
        abiParitySpec("kk_worker_execute_after", parameters: [
            p("workerHandle", .intptr),
            p("afterMicroseconds", .intptr),
            p("fnPtr", .intptr),
            p("closureRaw", .intptr),
        ], isThrowing: false),
        abiParitySpec("kk_worker_id", parameters: [
            p("workerHandle", .intptr),
        ], isThrowing: false),
        abiParitySpec("kk_worker_is_terminated", parameters: [
            p("workerHandle", .intptr),
        ]),
        abiParitySpec("kk_worker_name", parameters: [
            p("workerHandle", .intptr),
        ], isThrowing: false),
        abiParitySpec("kk_worker_new", parameters: [
            p("nameRaw", .intptr),
        ]),
        abiParitySpec("kk_worker_park", parameters: [
            p("workerHandle", .intptr),
            p("timeoutMicroseconds", .intptr),
            p("processRaw", .intptr),
        ], isThrowing: false),
        abiParitySpec("kk_worker_platform_thread_id", parameters: [
            p("workerHandle", .intptr),
        ], isThrowing: false),
        abiParitySpec("kk_worker_process_queue", parameters: [
            p("workerHandle", .intptr),
        ], isThrowing: false),
        abiParitySpec("kk_worker_request_termination", parameters: [
            p("workerHandle", .intptr),
            p("processScheduledRaw", .intptr),
        ], isThrowing: false),
    ]
}

private func abiParitySpec(
    _ name: String,
    parameters: [RuntimeABIParameter] = [],
    returnType: RuntimeABICType = .intptr,
    isThrowing: Bool = true
) -> RuntimeABIFunctionSpec {
    RuntimeABIFunctionSpec(
        name: name,
        parameters: parameters,
        returnType: returnType,
        section: "ABIParity",
        isThrowing: isThrowing
    )
}

private func p(_ name: String, _ type: RuntimeABICType) -> RuntimeABIParameter {
    RuntimeABIParameter(name: name, type: type)
}
