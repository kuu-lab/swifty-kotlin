private let abi = RuntimeABISectionBuilder("Exception")

public extension RuntimeABISpec {
    static let bridgeThrowableNewSpec: RuntimeABIFunctionSpec = abi.th("__kk_throwable_new", "message:nullableOpaquePointer", ret: .opaquePointer)
    static let bridgeThrowableNewCauseSpec: RuntimeABIFunctionSpec = abi.nt("__kk_throwable_new_cause", "causeRaw", ret: .opaquePointer)
    static let bridgeThrowableSetOptionsSpec: RuntimeABIFunctionSpec = abi.nt("__kk_throwable_set_options", "throwableRaw suppressionEnabledRaw writableStackTraceRaw")
    static let bridgeNoWhenBranchMatchedExceptionNewSpec: RuntimeABIFunctionSpec = abi.nt("__kk_no_when_branch_matched_exception_new")
    static let bridgeNoWhenBranchMatchedExceptionNewMessageSpec: RuntimeABIFunctionSpec = abi.nt("__kk_no_when_branch_matched_exception_new_message", "messageRaw")
    static let bridgeNoWhenBranchMatchedExceptionNewMessageCauseSpec: RuntimeABIFunctionSpec = abi.nt("__kk_no_when_branch_matched_exception_new_message_cause", "messageRaw causeRaw")
    static let bridgeNoWhenBranchMatchedExceptionNewCauseSpec: RuntimeABIFunctionSpec = abi.nt("__kk_no_when_branch_matched_exception_new_cause", "causeRaw")
    static let bridgeConcurrentModificationExceptionNewSpec: RuntimeABIFunctionSpec = abi.nt("__kk_concurrent_modification_exception_new")
    static let bridgeConcurrentModificationExceptionNewMessageSpec: RuntimeABIFunctionSpec = abi.nt("__kk_concurrent_modification_exception_new_message", "messageRaw")
    static let bridgeConcurrentModificationExceptionNewMessageCauseSpec: RuntimeABIFunctionSpec = abi.nt("__kk_concurrent_modification_exception_new_message_cause", "messageRaw causeRaw")
    static let bridgeConcurrentModificationExceptionNewCauseSpec: RuntimeABIFunctionSpec = abi.nt("__kk_concurrent_modification_exception_new_cause", "causeRaw")
    static let bridgeArrayIndexOutOfBoundsExceptionNewSpec: RuntimeABIFunctionSpec = abi.nt("__kk_array_index_out_of_bounds_exception_new")
    static let bridgeArrayIndexOutOfBoundsExceptionNewMessageSpec: RuntimeABIFunctionSpec = abi.nt("__kk_array_index_out_of_bounds_exception_new_message", "messageRaw")
    static let throwableIsCancellationSpec: RuntimeABIFunctionSpec = abi.nt("kk_throwable_is_cancellation", "throwableRaw")
    static let bridgeSynchronizedSpec: RuntimeABIFunctionSpec = abi.th("__kk_synchronized", "lock fnPtr closureRaw outThrown")
    static let bridgeThrowableRawStackFramesSpec: RuntimeABIFunctionSpec = abi.th("__kk_throwable_rawStackFrames", "throwableRaw outThrown")
    static let bridgeThrowableToStringSpec: RuntimeABIFunctionSpec = abi.th("__kk_throwable_toString", "throwableRaw outThrown")
    static let bridgePrintStderrSpec: RuntimeABIFunctionSpec = abi.nt("__kk_printStderr", "messageRaw")
    static let bridgeThrowableSuppressedRawSpec: RuntimeABIFunctionSpec = abi.nt("__kk_throwable_suppressedRaw", "throwableRaw")

    static let exceptionFunctions: [RuntimeABIFunctionSpec] = [
        bridgeThrowableNewSpec,
        abi.nt("__kk_throwable_new_with_cause", "message:nullableOpaquePointer causeRaw", ret: .opaquePointer),
        bridgeThrowableNewCauseSpec,
        bridgeThrowableSetOptionsSpec,
        abi.nt("kk_throwable_new_cause", "causeRaw", ret: .opaquePointer),
        abi.nt("__kk_freezing_exception_new", "toFreezeRaw blockerRaw"),
        bridgeNoWhenBranchMatchedExceptionNewSpec,
        bridgeNoWhenBranchMatchedExceptionNewMessageSpec,
        bridgeNoWhenBranchMatchedExceptionNewMessageCauseSpec,
        bridgeNoWhenBranchMatchedExceptionNewCauseSpec,
        bridgeConcurrentModificationExceptionNewSpec,
        bridgeConcurrentModificationExceptionNewMessageSpec,
        abi.nt("__kk_invalid_mutability_exception_new_message", "messageRaw"),
        bridgeConcurrentModificationExceptionNewMessageCauseSpec,
        bridgeConcurrentModificationExceptionNewCauseSpec,
        bridgeArrayIndexOutOfBoundsExceptionNewSpec,
        bridgeArrayIndexOutOfBoundsExceptionNewMessageSpec,
        abi.nt("__kk_array_store_exception_new"),
        abi.nt("__kk_array_store_exception_new_message", "messageRaw"),
        abi.nt("__kk_string_index_out_of_bounds_exception_new"),
        abi.nt("__kk_string_index_out_of_bounds_exception_new_message", "messageRaw"),
        // Per-type explicit constructor entry points (catch-clause sibling-type
        // discrimination fix). Each built-in exception class below gets its own
        // direct `__kk_*` constructor bridge instead of sharing
        // the type-erased __kk_throwable_new/__kk_throwable_new_with_cause, so the
        // allocated RuntimeThrowableBox subclass carries the correct runtime type
        // identity for kk_op_is / catch-clause dispatch.
        abi.nt("__kk_exception_new"),
        abi.nt("__kk_exception_new_message", "messageRaw"),
        abi.nt("__kk_exception_new_message_cause", "messageRaw causeRaw"),
        abi.nt("__kk_exception_new_cause", "causeRaw"),
        abi.nt("__kk_character_coding_exception_new"),
        abi.nt("__kk_character_coding_exception_new_message", "messageRaw"),
        abi.nt("__kk_kotlin_nothing_value_exception_new"),
        abi.nt("__kk_kotlin_nothing_value_exception_new_message", "messageRaw"),
        abi.nt("__kk_kotlin_nothing_value_exception_new_message_cause", "messageRaw causeRaw"),
        abi.nt("__kk_kotlin_nothing_value_exception_new_cause", "causeRaw"),
        abi.nt("__kk_error_new"),
        abi.nt("__kk_error_new_message", "messageRaw"),
        abi.nt("__kk_error_new_message_cause", "messageRaw causeRaw"),
        abi.nt("__kk_error_new_cause", "causeRaw"),
        abi.nt("__kk_not_implemented_error_new"),
        abi.nt("__kk_not_implemented_error_new_message", "messageRaw"),
        abi.nt("__kk_out_of_memory_error_new"),
        abi.nt("__kk_out_of_memory_error_new_message", "messageRaw"),
        abi.nt("__kk_stack_overflow_error_new"),
        abi.nt("__kk_stack_overflow_error_new_message", "messageRaw"),
        abi.nt("__kk_stack_overflow_error_new_message_cause", "messageRaw causeRaw"),
        abi.nt("__kk_stack_overflow_error_new_cause", "causeRaw"),
        // Per-frame stack guard invoked by generated function prologues:
        // returns 0 while the caller's stack marker sits above the current
        // thread's overflow bound, or a StackOverflowError handle once it
        // drops below it (KUU-1384).
        abi.nt("kk_stack_overflow_check", "marker"),
        abi.nt("__kk_assertion_error_new"),
        abi.nt("__kk_assertion_error_new_message", "messageRaw"),
        abi.nt("__kk_assertion_error_new_message_cause", "messageRaw causeRaw"),
        abi.nt("__kk_illegal_state_exception_new"),
        abi.nt("__kk_null_pointer_exception_new"),
        abi.nt("__kk_illegal_state_exception_new_message", "messageRaw"),
        abi.nt("__kk_illegal_state_exception_new_message_cause", "messageRaw causeRaw"),
        abi.nt("__kk_illegal_state_exception_new_cause", "causeRaw"),
        abi.nt("__kk_cancellation_exception_new"),
        abi.nt("__kk_cancellation_exception_new_message", "messageRaw"),
        abi.nt("__kk_cancellation_exception_new_message_cause", "messageRaw causeRaw"),
        abi.nt("__kk_cancellation_exception_new_cause", "causeRaw"),
        // KUU-1404: kotlinx.coroutines.channels closed-channel exception ctor
        // (JVM kotlinx exposes only the `message: String?` constructor).
        abi.nt("__kk_closed_receive_channel_exception_new_message", "messageRaw"),
        abi.nt("__kk_closed_send_channel_exception_new_message", "messageRaw"),
        abi.nt("__kk_illegal_argument_exception_new"),
        abi.nt("__kk_illegal_argument_exception_new_message", "messageRaw"),
        abi.nt("__kk_illegal_argument_exception_new_message_cause", "messageRaw causeRaw"),
        abi.nt("__kk_illegal_argument_exception_new_cause", "causeRaw"),
        abi.nt("__kk_invalid_parameter_exception_new"),
        abi.nt("__kk_invalid_parameter_exception_new_message", "messageRaw"),
        abi.nt("__kk_invalid_parameter_exception_new_message_cause", "messageRaw causeRaw"),
        abi.nt("__kk_invalid_parameter_exception_new_cause", "causeRaw"),
        abi.nt("__kk_unsupported_operation_exception_new"),
        abi.nt("__kk_unsupported_operation_exception_new_message", "messageRaw"),
        abi.nt("__kk_unsupported_operation_exception_new_message_cause", "messageRaw causeRaw"),
        abi.nt("__kk_unsupported_operation_exception_new_cause", "causeRaw"),
        abi.nt("__kk_no_such_element_exception_new"),
        abi.nt("__kk_no_such_element_exception_new_message", "messageRaw"),
        abi.nt("__kk_arithmetic_exception_new"),
        abi.nt("__kk_arithmetic_exception_new_message", "messageRaw"),
        abi.nt("__kk_class_cast_exception_new"),
        abi.nt("__kk_class_cast_exception_new_message", "messageRaw"),
        abi.nt("__kk_type_cast_exception_new"),
        abi.nt("__kk_type_cast_exception_new_message", "messageRaw"),
        abi.nt("__kk_uninitialized_property_access_exception_new"),
        abi.nt("__kk_uninitialized_property_access_exception_new_message", "messageRaw"),
        abi.nt("__kk_uninitialized_property_access_exception_new_message_cause", "messageRaw causeRaw"),
        abi.nt("__kk_uninitialized_property_access_exception_new_cause", "causeRaw"),
        abi.th("kk_negative_array_size_exception_new"),
        abi.th("kk_negative_array_size_exception_new_message", "messageRaw"),
        throwableIsCancellationSpec,
        abi.nt("kk_abort_unreachable", "outThrown"),
        // KSP-618: synchronized(lock) { } is Kotlin source delegating to this
        // demoted bridge; the block arrives as a function pointer + closure
        // environment pair with the usual outThrown channel.
        bridgeSynchronizedSpec,
        abi.th("__kk_assertions_enabled"),
        abi.th("kk_assertions_set_enabled", "enabled"),
        abi.th("kk_assertions_reset"),
        abi.th("kk_dispatch_error"),
        abi.nt("__kk_throwable_message", "throwableRaw"),
        abi.nt("__kk_throwable_setMessage", "throwableRaw messageRaw"),
        abi.nt("__kk_throwable_cause", "throwableRaw"),
        bridgeThrowableRawStackFramesSpec,
        bridgeThrowableToStringSpec,
        bridgePrintStderrSpec,
        abi.nt("__kk_throwable_setCause", "throwableRaw causeRaw"),
        abi.nt("__kk_throwable_appendSuppressed", "throwableRaw suppressedRaw"),
        bridgeThrowableSuppressedRawSpec,
        abi.nt("__kk_throwable_captureStackTrace", "throwableRaw"),
    ]
}
