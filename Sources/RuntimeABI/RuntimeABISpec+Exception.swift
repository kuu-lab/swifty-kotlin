// swiftlint:disable file_length

/// `RuntimeABISpec.exceptionFunctions` extracted from `RuntimeABISpec.swift`.
public extension RuntimeABISpec {

    static let exceptionFunctions: [RuntimeABIFunctionSpec] = [
        RuntimeABIFunctionSpec(
            name: "kk_throwable_new",
            parameters: [
                RuntimeABIParameter(name: "message", type: .nullableOpaquePointer),
            ],
            returnType: .opaquePointer,
            section: "Exception"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_throwable_new_with_cause",
            parameters: [
                RuntimeABIParameter(name: "message", type: .nullableOpaquePointer),
                RuntimeABIParameter(name: "causeRaw", type: .intptr),
            ],
            returnType: .opaquePointer,
            section: "Exception",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_throwable_new_cause",
            parameters: [
                RuntimeABIParameter(name: "causeRaw", type: .intptr),
            ],
            returnType: .opaquePointer,
            section: "Exception",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_no_when_branch_matched_exception_new",
            parameters: [],
            returnType: .intptr,
            section: "Exception",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_no_when_branch_matched_exception_new_message",
            parameters: [
                RuntimeABIParameter(name: "messageRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Exception",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_no_when_branch_matched_exception_new_message_cause",
            parameters: [
                RuntimeABIParameter(name: "messageRaw", type: .intptr),
                RuntimeABIParameter(name: "causeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Exception",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_no_when_branch_matched_exception_new_cause",
            parameters: [
                RuntimeABIParameter(name: "causeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Exception",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_concurrent_modification_exception_new",
            parameters: [],
            returnType: .intptr,
            section: "Exception",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_concurrent_modification_exception_new_message",
            parameters: [
                RuntimeABIParameter(name: "messageRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Exception",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_concurrent_modification_exception_new_message_cause",
            parameters: [
                RuntimeABIParameter(name: "messageRaw", type: .intptr),
                RuntimeABIParameter(name: "causeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Exception",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_concurrent_modification_exception_new_cause",
            parameters: [
                RuntimeABIParameter(name: "causeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Exception",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_array_index_out_of_bounds_exception_new",
            parameters: [],
            returnType: .intptr,
            section: "Exception"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_array_index_out_of_bounds_exception_new_message",
            parameters: [
                RuntimeABIParameter(name: "messageRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Exception"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_throwable_is_cancellation",
            parameters: [
                RuntimeABIParameter(name: "throwableRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Exception",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_abort_unreachable",
            parameters: [
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Exception",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_require",
            parameters: [
                RuntimeABIParameter(name: "condition", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Exception"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_check",
            parameters: [
                RuntimeABIParameter(name: "condition", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Exception"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_require_lazy",
            parameters: [
                RuntimeABIParameter(name: "condition", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Exception"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_synchronized",
            parameters: [
                RuntimeABIParameter(name: "lock", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Exception"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_reentrant_read_write_lock_read",
            parameters: [
                RuntimeABIParameter(name: "lock", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Exception"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_check_lazy",
            parameters: [
                RuntimeABIParameter(name: "condition", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Exception"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_precondition_assert",
            parameters: [
                RuntimeABIParameter(name: "condition", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Exception"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_precondition_assert_lazy",
            parameters: [
                RuntimeABIParameter(name: "condition", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Exception"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_assertions_enabled",
            parameters: [],
            returnType: .intptr,
            section: "Exception"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_assertions_set_enabled",
            parameters: [
                RuntimeABIParameter(name: "enabled", type: .intptr),
            ],
            returnType: .intptr,
            section: "Exception"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_assertions_reset",
            parameters: [],
            returnType: .intptr,
            section: "Exception"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_error",
            parameters: [
                RuntimeABIParameter(name: "message", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Exception"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_todo",
            parameters: [
                RuntimeABIParameter(name: "reason", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Exception"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_todo_noarg",
            parameters: [
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Exception"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_dispatch_error",
            parameters: [],
            returnType: .intptr,
            section: "Exception"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_throwable_message",
            parameters: [
                RuntimeABIParameter(name: "throwableRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Exception",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_throwable_cause",
            parameters: [
                RuntimeABIParameter(name: "throwableRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Exception",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_throwable_stackTraceToString",
            parameters: [
                RuntimeABIParameter(name: "throwableRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Exception",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_throwable_printStackTrace",
            parameters: [
                RuntimeABIParameter(name: "throwableRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Exception",
            isThrowing: false
        ),
        // STDLIB-EXCEPT-105: Advanced exception handling
        RuntimeABIFunctionSpec(
            name: "kk_throwable_initCause",
            parameters: [
                RuntimeABIParameter(name: "throwableRaw", type: .intptr),
                RuntimeABIParameter(name: "causeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Exception",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_throwable_addSuppressed",
            parameters: [
                RuntimeABIParameter(name: "throwableRaw", type: .intptr),
                RuntimeABIParameter(name: "suppressedRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Exception",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_throwable_getSuppressed",
            parameters: [
                RuntimeABIParameter(name: "throwableRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Exception",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_throwable_suppressedExceptions",
            parameters: [
                RuntimeABIParameter(name: "throwableRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Exception",
            isThrowing: false
        ),
    ]
}
