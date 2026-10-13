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

        let valueArity = functionType.params.count + (functionType.receiver == nil ? 0 : 1)

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
        case 2:
            return interner.intern("kk_function_invoke_2")
        case 3:
            return interner.intern("kk_function_invoke_3")
        case 4:
            return interner.intern("kk_function_invoke_4")
        case 5:
            return interner.intern("kk_function_invoke_5")
        case 6:
            return interner.intern("kk_function_invoke_6")
        default:
            return nil
        }
    }

    /// Returns true if the callee is a runtime function that requires a thrown
    /// channel (outThrown) parameter in its ABI. This ensures the codegen
    /// appends the extra `intptr_t * _Nullable` slot.
    func needsThrownChannel(calleeName: InternedString, interner: StringInterner) -> Bool {
        let name = interner.resolve(calleeName)
        return [
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
            "__kk_mutable_list_add_at",
            "__kk_mutable_list_removeAt",
            "__kk_mutable_list_set",
            "__kk_list_get",
            "__kk_mutable_set_add",
            "__kk_mutable_set_remove",
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
            "kk_iterator_next",
            "kk_list_iterator_next",
            "kk_array_of_nulls",
        ].contains(name)
    }

    func isIteratorNextName(_ name: String) -> Bool {
        switch name {
        case "next", "kk_iterator_next", "kk_list_iterator_next":
            true
        default:
            false
        }
    }

    func shouldRethrowThrownChannelResult(calleeName: InternedString, interner: StringInterner) -> Bool {
        [
            "__kk_channel_result_get_or_throw",
            "kk_runtime_result_get_or_else",
            "kk_runtime_result_get_or_throw",
            "kk_runtime_result_map",
            "kk_runtime_result_fold",
            "kk_runtime_result_on_success",
            "kk_runtime_result_on_failure",
            "kk_runtime_result_recover",
            "__kk_synchronized",
            "__kk_cancellable_continuation_resume",
            "__kk_cancellable_continuation_invoke_on_cancellation",
            "__kk_cancellable_continuation_complete_resume",
            "__kk_cancellable_continuation_get_result",
            "kk_job_get_child_cancellation_cause",
            "kk_job_parent_cancelled",
            "__kk_enum_entries_get",
            "__kk_regex_replace_lambda",
            "__kk_mutable_list_removeAt",
            "__kk_sequence_builder_yieldAll_checked",
            "__kk_mutable_list_add",
            "__kk_mutable_list_add_at",
            "__kk_mutable_list_set",
            "kk_iterable_iterator",
            "__kk_mutable_set_add",
            // KUU-1404: thrown terminal statuses propagate through the regular
            // exception channel so try/catch can observe them.
            "kk_channel_send",
            "kk_channel_receive",
            "__kk_file_readText",
            "__kk_buffered_reader_useLines",
            "__kk_buffered_reader_forEachLine",
            "__kk_buffered_writer_write",
            "__kk_buffered_writer_new_line",
            "__kk_buffered_writer_flush",
            "__kk_writer_buffered_default",
            "__kk_writer_buffered",
            "__kk_bytearrayinputstream_new",
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
            "__kk_mutable_set_remove",
            "__kk_mutable_set_clear",
            "__kk_mutable_map_put",
            "__kk_mutable_map_remove",
            "__kk_mutable_map_clear",
            "__kk_mutable_map_putAll",
            "__kk_list_get",
            "kk_mutex_unlock",
            "__kk_mutex_lock_owner",
            "__kk_mutex_unlock_owner",
            "kk_semaphore_release",
            "kk_sequence_elementAt",
            "kk_iterator_next",
            "kk_list_iterator_next",
            "kk_array_of_nulls",
        ].contains(interner.resolve(calleeName))
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
