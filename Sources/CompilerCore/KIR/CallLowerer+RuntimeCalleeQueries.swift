extension CallLowerer {
    func runtimeCallableInvokeCallee(
        callableValueCallBinding: CallableValueCallBinding?,
        sema: SemaModule,
        interner: StringInterner
    ) -> InternedString? {
        guard let callableValueCallBinding else {
            return nil
        }
        let nonNullFunctionType = sema.types.makeNonNullable(callableValueCallBinding.functionType)
        guard case let .functionType(functionType) = sema.types.kind(of: nonNullFunctionType) else {
            return nil
        }

        let valueArity = functionType.contextReceivers.count
            + functionType.params.count
            + (functionType.receiver == nil ? 0 : 1)

        if functionType.isSuspend {
            switch valueArity {
            case 0:
                return interner.intern("kk_suspend_function_invoke_0")
            case 1:
                return interner.intern("kk_suspend_function_invoke")
            case 2:
                return interner.intern("kk_suspend_function_invoke_2")
            case 3:
                return interner.intern("kk_suspend_function_invoke_3")
            case 4:
                return interner.intern("kk_suspend_function_invoke_4")
            case 5:
                return interner.intern("kk_suspend_function_invoke_5")
            case 6:
                return interner.intern("kk_suspend_function_invoke_6")
            default:
                return nil
            }
        }

        switch valueArity {
        case 0:
            return interner.intern("kk_function_invoke_0")
        case 1:
            return interner.intern("kk_function_invoke")
        case 2...22:
            return interner.intern("kk_function_invoke_\(valueArity)")
        default:
            return nil
        }
    }

    /// Runtime callees whose ABI carries a thrown channel (outThrown) slot.
    private static let thrownChannelCalleeNames: Set<String> = [
        "kk_runtime_result_get_or_else",
        "kk_runtime_result_get_or_throw",
        "kk_runtime_result_map",
        "kk_runtime_result_fold",
        "kk_runtime_result_on_success",
        "kk_runtime_result_on_failure",
        "kk_runtime_result_recover",
        "kk_runtime_result_recover_catching",
        "kk_runtime_result_run_catching",
        "__kk_channel_result_get_or_throw",
        "__kk_synchronized",
        "__kk_cancellable_continuation_resume",
        "__kk_cancellable_continuation_invoke_on_cancellation",
        "__kk_cancellable_continuation_complete_resume",
        "__kk_cancellable_continuation_get_result",
        "kk_job_get_child_cancellation_cause",
        "kk_job_parent_cancelled",
        "__kk_string_builder_new_capacity_checked",
        "__kk_mutable_list_add",
        "__kk_mutable_list_addAll_checked",
        "__kk_mutable_list_add_at",
        "__kk_mutable_list_remove_checked",
        "__kk_mutable_list_removeAll_checked",
        "__kk_mutable_list_removeAt",
        "__kk_mutable_list_set",
        "__kk_list_get",
        "__kk_mutable_set_add",
        "__kk_mutable_collection_add_throwing",
        "__kk_mutable_collection_addAll_throwing",
        "__kk_mutable_set_remove",
        "__kk_mutable_set_removeAll",
        "__kk_mutable_set_clear",
        "__kk_mutable_map_put",
        "__kk_mutable_map_remove",
        "__kk_mutable_map_clear",
        "__kk_mutable_map_putAll",
        "__kk_enum_entries_get",
        "__kk_regex_replace_lambda",
        "__kk_sequence_builder_yieldAll_checked",
        "kk_sequence_elementAt",
        "kk_iterable_iterator",
        // KUU-1404: channel send/receive surface terminal status
        // (closed/cancelled) through the outThrown channel as Kotlin
        // exceptions (ClosedSendChannelException /
        // ClosedReceiveChannelException / CancellationException).
        "kk_channel_send",
        "kk_channel_receive",
        "kk_mutex_unlock",
        "__kk_mutex_lock_owner",
        "__kk_mutex_unlock_owner",
        "kk_semaphore_release",
        "__kk_file_readText",
        "__kk_buffered_reader_useLines",
        "__kk_buffered_reader_forEachLine",
        "__kk_buffered_writer_write",
        "__kk_buffered_writer_new_line",
        "__kk_buffered_writer_flush",
        "__kk_writer_buffered_default",
        "__kk_writer_buffered",
        "__kk_bytearrayinputstream_new",
        "__kk_any_to_string_throwing",
        "__kk_io_stream_to_string",
        "__kk_sequence_input_stream_available_throwing",
        "__kk_sequence_input_stream_close_throwing",
        "__kk_native_filechannel_open",
        "__kk_native_filechannel_write",
        "__kk_native_nio_create_file",
        "__kk_bytearray_output_stream_new",
        "__kk_input_stream_read_range",
        "__kk_output_stream_write_range",
        "__kk_input_stream_available_throwing",
        "__kk_input_stream_close_throwing",
        "__kk_output_stream_close_throwing",
        "__kk_buffered_writer_close_throwing",
        "__kk_bytearray_inputStream",
        "__kk_bytearray_inputStream_range",
        "__kk_input_stream_read",
        "__kk_input_stream_skip",
        "__kk_input_stream_read_bytes",
        "__kk_input_stream_readAllBytes",
        "__kk_input_stream_reset",
        "__kk_input_stream_buffered_default",
        "__kk_input_stream_buffered",
        "__kk_input_stream_copyTo",
        "__kk_input_stream_bufferedReader",
        "__kk_output_stream_write_byte",
        "__kk_output_stream_write_bytes",
        "__kk_output_stream_flush",
        "__kk_reader_copyTo",
        "__kk_reader_copyTo_default",
        "__kk_reader_read_range",
        "kk_iterator_next",
        "kk_list_iterator_next",
        "kk_array_of_nulls",
    ]

    /// Thrown-channel callees whose results must NOT be rethrown: they surface
    /// failure through their return value rather than the exception channel.
    private static let nonRethrowingThrownChannelCalleeNames: Set<String> = [
        "kk_runtime_result_recover_catching",
        "kk_runtime_result_run_catching",
        "__kk_string_builder_new_capacity_checked",
    ]

    // Function values may throw from their target even though Kotlin's
    // FunctionN.invoke declaration has no checked-throws annotation.
    private func isThrowingRuntimeCallee(_ name: String) -> Bool {
        name == "kk_function_invoke" || name.hasPrefix("kk_function_invoke_")
            || name == "kk_suspend_function_invoke" || name.hasPrefix("kk_suspend_function_invoke_")
            || Self.thrownChannelCalleeNames.contains(name)
    }

    /// Returns true if the callee is a runtime function that requires a thrown
    /// channel (outThrown) parameter in its ABI. This ensures the codegen
    /// appends the extra `intptr_t * _Nullable` slot.
    func needsThrownChannel(calleeName: InternedString, interner: StringInterner) -> Bool {
        isThrowingRuntimeCallee(interner.resolve(calleeName))
    }

    func isIteratorNextName(_ name: String) -> Bool {
        switch name {
        case "next", "kk_iterator_next", "kk_list_iterator_next":
            true
        default:
            false
        }
    }

    // Function-value invocation forwards exceptions from the runtime
    // callback through its outThrown slot, so unhandled exceptions must
    // escape the current Kotlin function just like other throwing calls.
    func shouldRethrowThrownChannelResult(calleeName: InternedString, interner: StringInterner) -> Bool {
        let name = interner.resolve(calleeName)
        return isThrowingRuntimeCallee(name)
            && !Self.nonRethrowingThrownChannelCalleeNames.contains(name)
    }

    func callableRequiresThrownChannel(_ lambdaSymbol: SymbolID, arena: KIRArena) -> Bool {
        guard let function = arena.function(for: lambdaSymbol) else {
            return false
        }
        for instruction in function.body {
            switch instruction {
            case let .call(_, _, _, _, canThrow, _, _, _),
                 let .virtualCall(_, _, _, _, _, canThrow, _, _):
                if canThrow {
                    return true
                }
            case .rethrow:
                return true
            default:
                continue
            }
        }
        return false
    }
}
