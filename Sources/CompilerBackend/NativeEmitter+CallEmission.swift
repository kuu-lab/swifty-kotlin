// swiftlint:disable function_body_length

import CompilerCore

extension NativeEmitter.FunctionEmissionState {

    // swiftlint:disable:next cyclomatic_complexity
    func emitCallInstruction(
        symbol: SymbolID?,
        callee: InternedString,
        arguments: [KIRExprID],
        result: KIRExprID?,
        canThrow usesThrownChannel: Bool,
        thrownResult: KIRExprID?,
        isSuperCall: Bool,
        qualifiedSuperType: SymbolID?,
        instructionIndex: Int
    ) {
        _ = (isSuperCall, qualifiedSuperType)
        guard !bindings.hasTerminator(currentBlock) else {
            return
        }

        let calleeName = interner.resolve(callee)
        let argumentValues = arguments.map(resolveValue)

        if NativeEmitter.knownVoidNoArgCallees.contains(calleeName) {
            if let runtimeFunction = declareExternalFunction(
                named: calleeName,
                argumentCount: 0,
                appendThrownChannel: false
            ) {
                _ = bindings.buildCall(
                    builder,
                    functionType: runtimeFunction.type,
                    callee: runtimeFunction.value,
                    arguments: [],
                    name: "\(calleeName)_\(instructionIndex)"
                )
            }
            if usesThrownChannel, let thrownResult {
                if let alloca = copyTargetAllocas[thrownResult.rawValue] {
                    _ = bindings.buildStore(builder, value: zeroValue, pointer: alloca)
                } else {
                    storeResult(thrownResult, zeroValue)
                }
            }
            storeResult(result, zeroValue)
            return
        }

        if calleeName == "kk_println_float" || calleeName == "kk_println_double"
            || calleeName == "kk_println_long" || calleeName == "kk_println_char"
            || calleeName == "kk_println_bool" || calleeName == "kk_println_ulong"
        {
            let printValue = argumentValues.first ?? zeroValue
            if let printFunction = declareExternalFunction(
                named: calleeName,
                argumentCount: 1,
                appendThrownChannel: false
            ) {
                _ = bindings.buildCall(
                    builder,
                    functionType: printFunction.type,
                    callee: printFunction.value,
                    arguments: [printValue],
                    name: "println_\(calleeName)_\(instructionIndex)"
                )
            }
            if usesThrownChannel, let thrownResult {
                if let alloca = copyTargetAllocas[thrownResult.rawValue] {
                    _ = bindings.buildStore(builder, value: zeroValue, pointer: alloca)
                } else {
                    storeResult(thrownResult, zeroValue)
                }
            }
            storeResult(result, zeroValue)
            return
        }

        if calleeName == "println", argumentValues.isEmpty {
            if let printFunction = declareExternalFunction(
                named: "kk_println_newline",
                argumentCount: 0,
                appendThrownChannel: false
            ) {
                _ = bindings.buildCall(
                    builder,
                    functionType: printFunction.type,
                    callee: printFunction.value,
                    arguments: [],
                    name: "println_newline_\(instructionIndex)"
                )
            }
            if usesThrownChannel, let thrownResult {
                if let alloca = copyTargetAllocas[thrownResult.rawValue] {
                    _ = bindings.buildStore(builder, value: zeroValue, pointer: alloca)
                } else {
                    storeResult(thrownResult, zeroValue)
                }
            }
            storeResult(result, zeroValue)
            return
        }

        if calleeName == "println" || calleeName == "kk_println_any" {
            let printValue = argumentValues.first ?? zeroValue
            if let printFunction = declareExternalFunction(
                named: "kk_println_any",
                argumentCount: 1,
                appendThrownChannel: false
            ) {
                _ = bindings.buildCall(
                    builder,
                    functionType: printFunction.type,
                    callee: printFunction.value,
                    arguments: [printValue],
                    name: "println_\(instructionIndex)"
                )
            }
            if usesThrownChannel, let thrownResult {
                if let alloca = copyTargetAllocas[thrownResult.rawValue] {
                    _ = bindings.buildStore(builder, value: zeroValue, pointer: alloca)
                } else {
                    storeResult(thrownResult, zeroValue)
                }
            }
            storeResult(result, zeroValue)
            return
        }

        if emitBuiltinCall(
            calleeName: calleeName,
            argumentValues: argumentValues,
            result: result,
            instructionIndex: instructionIndex
        ) {
            return
        }

        // CORO-001: kk_channel_receive returns status out-of-band; payload via outValue.
        if calleeName == "kk_channel_receive" {
            let outValueSlot = bindings.buildAlloca(
                builder,
                type: int64Type,
                name: "channel_out_value_\(instructionIndex)"
            )
            if let outValueSlot {
                _ = bindings.buildStore(builder, value: zeroValue, pointer: outValueSlot)
            }
            if let receiveFunction = declareExternalFunction(
                named: "kk_channel_receive",
                argumentCount: 3,
                appendThrownChannel: false
            ) {
                var receiveArgs = argumentValues
                receiveArgs.append(outValueSlot ?? nullThrownPointer)
                _ = bindings.buildCall(
                    builder,
                    functionType: receiveFunction.type,
                    callee: receiveFunction.value,
                    arguments: receiveArgs,
                    name: "channel_receive_\(instructionIndex)"
                )
                if let outValueSlot,
                   let loadedValue = bindings.buildLoad(
                       builder,
                       type: int64Type,
                       pointer: outValueSlot,
                       name: "channel_recv_val_\(instructionIndex)"
                   )
                {
                    storeResult(result, loadedValue)
                } else {
                    storeResult(result, zeroValue)
                }
            } else {
                storeResult(result, zeroValue)
            }
            return
        }

        let normalizedSymbol: SymbolID? = if let symbol, symbol != .invalid {
            symbol
        } else {
            SymbolID?.none
        }
        let fallbackInternal: (symbol: SymbolID, function: NativeEmitter.LLVMFunction)? = if normalizedSymbol == nil {
            resolveUnnamedInternalFunction(
                named: calleeName,
                argumentCount: argumentValues.count,
                appendThrownChannel: usesThrownChannel
            )
        } else {
            nil
        }
        let effectiveSymbol = normalizedSymbol ?? fallbackInternal?.symbol
        let calleeFunction: NativeEmitter.LLVMFunction?
        let isInternalCall = effectiveSymbol.flatMap { internalFunctions[$0] } != nil
        let shouldAppendThrownChannel = usesThrownChannel || isInternalCall

        if let effectiveSymbol,
           let internalFunction = internalFunctions[effectiveSymbol]
        {
            calleeFunction = internalFunction
        } else if let fallbackInternal {
            calleeFunction = fallbackInternal.function
        } else if calleeName.isEmpty {
            calleeFunction = nil
        } else if calleeName == "length", argumentValues.count == 1 {
            calleeFunction = declareExternalFunction(
                named: "kk_string_length",
                argumentCount: 1,
                appendThrownChannel: false
            )
        } else {
            calleeFunction = declareExternalFunction(
                named: calleeName,
                argumentCount: argumentValues.count,
                appendThrownChannel: shouldAppendThrownChannel
            )
        }

        guard let calleeFunction else {
            storeResult(result, nil)
            return
        }

        var callArguments = argumentValues
        var thrownSlotPointer: LLVMCAPIBindings.LLVMValueRef?
        if shouldAppendThrownChannel {
            if usesThrownChannel {
                let thrownSlot = bindings.buildAlloca(
                    builder,
                    type: int64Type,
                    name: "thrown_slot_\(instructionIndex)"
                )
                if let thrownSlot {
                    _ = bindings.buildStore(builder, value: zeroValue, pointer: thrownSlot)
                    callArguments.append(thrownSlot)
                    thrownSlotPointer = thrownSlot
                } else {
                    callArguments.append(nullThrownPointer)
                }
            } else {
                callArguments.append(nullThrownPointer)
            }
        }

        let callValue = bindings.buildCall(
            builder,
            functionType: calleeFunction.type,
            callee: calleeFunction.value,
            arguments: callArguments,
            name: "call_\(instructionIndex)"
        )
        if let result, let callValue {
            rawResultValues[result.rawValue] = callValue
        }
        storeResult(result, callValue)
        if calleeName == "kk_coroutine_continuation_new",
           let coroutineRegisterRootFunction
        {
            _ = bindings.buildCall(
                builder,
                functionType: coroutineRegisterRootFunction.type,
                callee: coroutineRegisterRootFunction.value,
                arguments: [callValue ?? zeroValue],
                name: "coroutine_root_register_\(instructionIndex)"
            )
        }
        if calleeName == "kk_coroutine_state_exit",
           let coroutineUnregisterRootFunction
        {
            _ = bindings.buildCall(
                builder,
                functionType: coroutineUnregisterRootFunction.type,
                callee: coroutineUnregisterRootFunction.value,
                arguments: [argumentValues.first ?? zeroValue],
                name: "coroutine_root_unregister_\(instructionIndex)"
            )
        }
        if usesThrownChannel,
           let thrownSlotPointer,
           let thrownValue = bindings.buildLoad(
               builder,
               type: int64Type,
               pointer: thrownSlotPointer,
               name: "thrown_val_\(instructionIndex)"
           )
        {
            if let thrownResult {
                if let alloca = copyTargetAllocas[thrownResult.rawValue] {
                    _ = bindings.buildStore(builder, value: thrownValue, pointer: alloca)
                } else {
                    storeResult(thrownResult, thrownValue)
                }
            } else if let hasThrown = buildThrownSlotCondition(
                from: thrownValue,
                name: "has_thrown_\(instructionIndex)"
            ),
                let thrownBlock = bindings.appendBasicBlock(
                    context: context,
                    function: llvmFunction.value,
                    name: "thrown_\(instructionIndex)"
                ),
                let continueBlock = bindings.appendBasicBlock(
                    context: context,
                    function: llvmFunction.value,
                    name: "call_cont_\(instructionIndex)"
                )
            {
                _ = bindings.buildCondBr(
                    builder,
                    condition: hasThrown,
                    thenBlock: thrownBlock,
                    elseBlock: continueBlock
                )

                bindings.positionBuilder(builder, at: thrownBlock)
                storeOutThrownIfNonNull(thrownValue, suffix: "throw_\(instructionIndex)")
                emitFramePop("throw_\(instructionIndex)")
                _ = bindings.buildRet(builder, value: zeroValue)

                currentBlock = continueBlock
                bindings.positionBuilder(builder, at: continueBlock)
            }
        }
    }

    // swiftlint:disable:next cyclomatic_complexity
    func emitVirtualCallInstruction(
        symbol: SymbolID?,
        callee: InternedString,
        receiver: KIRExprID,
        arguments: [KIRExprID],
        result: KIRExprID?,
        canThrow usesThrownChannel: Bool,
        thrownResult: KIRExprID?,
        dispatch: KIRDispatchKind,
        instructionIndex: Int
    ) {
        guard !bindings.hasTerminator(currentBlock) else {
            return
        }

        let calleeName = interner.resolve(callee)
        let argumentValues = [resolveValue(receiver)] + arguments.map(resolveValue)

        let normalizedSymbol: SymbolID? = if let symbol, symbol != .invalid {
            symbol
        } else {
            SymbolID?.none
        }
        let fallbackInternal: (symbol: SymbolID, function: NativeEmitter.LLVMFunction)? = if normalizedSymbol == nil {
            resolveUnnamedInternalFunction(
                named: calleeName,
                argumentCount: argumentValues.count,
                appendThrownChannel: usesThrownChannel
            )
        } else {
            nil
        }
        let effectiveSymbol = normalizedSymbol ?? fallbackInternal?.symbol
        let isInternalCall = effectiveSymbol.flatMap { internalFunctions[$0] } != nil
        let shouldAppendThrownChannel = usesThrownChannel || isInternalCall

        let calleeFunction: NativeEmitter.LLVMFunction? = if let effectiveSymbol,
                                                   let internalFunction = internalFunctions[effectiveSymbol]
        {
            internalFunction
        } else if let fallbackInternal {
            fallbackInternal.function
        } else if calleeName.isEmpty {
            nil
        } else if calleeName == "length", argumentValues.count == 1 {
            declareExternalFunction(
                named: "kk_string_length",
                argumentCount: 1,
                appendThrownChannel: false
            )
        } else {
            declareExternalFunction(
                named: calleeName,
                argumentCount: argumentValues.count,
                appendThrownChannel: shouldAppendThrownChannel
            )
        }

        guard let calleeFunction else {
            storeResult(result, nil)
            return
        }

        let lookupFunction: NativeEmitter.LLVMFunction?
        var lookupArgs: [LLVMCAPIBindings.LLVMValueRef] = []
        switch dispatch {
        case let .vtable(slot):
            lookupFunction = declareExternalFunction(named: "kk_vtable_lookup", argumentCount: 2, appendThrownChannel: false)
            lookupArgs = [
                resolveValue(receiver),
                bindings.constInt(int64Type, value: UInt64(slot)) ?? bindings.constInt(int64Type, value: 0)!,
            ]
        case let .itable(interfaceSlot, methodSlot):
            lookupFunction = declareExternalFunction(named: "kk_itable_lookup", argumentCount: 3, appendThrownChannel: false)
            lookupArgs = [
                resolveValue(receiver),
                bindings.constInt(int64Type, value: UInt64(interfaceSlot)) ?? bindings.constInt(int64Type, value: 0)!,
                bindings.constInt(int64Type, value: UInt64(methodSlot)) ?? bindings.constInt(int64Type, value: 0)!,
            ]
        case let .itableDynamic(interfaceTypeID, methodSlot):
            lookupFunction = declareExternalFunction(named: "kk_itable_lookup_dynamic", argumentCount: 3, appendThrownChannel: false)
            lookupArgs = [
                resolveValue(receiver),
                bindings.constInt(int64Type, value: UInt64(bitPattern: interfaceTypeID)) ?? bindings.constInt(int64Type, value: 0)!,
                bindings.constInt(int64Type, value: UInt64(methodSlot)) ?? bindings.constInt(int64Type, value: 0)!,
            ]
        }

        guard let lookupFn = lookupFunction else { return }
        guard let fptrRaw = bindings.buildCall(
            builder,
            functionType: lookupFn.type,
            callee: lookupFn.value,
            arguments: lookupArgs,
            name: "lookup_raw_\(instructionIndex)"
        ) else { return }

        guard let isNonNull = bindings.buildICmpNotEqual(
            builder,
            lhs: fptrRaw,
            rhs: zeroValue,
            name: "lookup_nonnull_\(instructionIndex)"
        ),
            let useVirtualBlock = bindings.appendBasicBlock(
                context: context,
                function: llvmFunction.value,
                name: "lookup_ok_\(instructionIndex)"
            ),
            let fallbackBlock = bindings.appendBasicBlock(
                context: context,
                function: llvmFunction.value,
                name: "lookup_fallback_\(instructionIndex)"
            ),
            let mergeBlock = bindings.appendBasicBlock(
                context: context,
                function: llvmFunction.value,
                name: "vcall_merge_\(instructionIndex)"
            )
        else {
            return
        }

        _ = bindings.buildCondBr(
            builder,
            condition: isNonNull,
            thenBlock: useVirtualBlock,
            elseBlock: fallbackBlock
        )
        bindings.positionBuilder(builder, at: useVirtualBlock)
        let functionPointerType = bindings.pointerType(calleeFunction.type)
        let fptr = bindings.buildIntToPtr(
            builder,
            value: fptrRaw,
            type: functionPointerType,
            name: "lookup_fptr_\(instructionIndex)"
        )

        var callArguments = argumentValues
        var thrownSlotPointer: LLVMCAPIBindings.LLVMValueRef?
        if shouldAppendThrownChannel {
            if usesThrownChannel {
                let thrownSlot = bindings.buildAlloca(
                    builder,
                    type: int64Type,
                    name: "vthrown_slot_\(instructionIndex)"
                )
                if let thrownSlot {
                    _ = bindings.buildStore(builder, value: zeroValue, pointer: thrownSlot)
                    callArguments.append(thrownSlot)
                    thrownSlotPointer = thrownSlot
                } else {
                    callArguments.append(nullThrownPointer)
                }
            } else {
                callArguments.append(nullThrownPointer)
            }
        }

        let vCallValue = bindings.buildCall(
            builder,
            functionType: calleeFunction.type,
            callee: fptr ?? calleeFunction.value,
            arguments: callArguments,
            name: "vcall_\(instructionIndex)"
        )
        if let result, let vCallValue {
            rawResultValues[result.rawValue] = vCallValue
        }
        _ = bindings.buildBr(builder, destination: mergeBlock)

        // Fallback path: trap on dispatch failure (GEN-002).
        bindings.positionBuilder(builder, at: fallbackBlock)
        if let trapFn = declareExternalFunction(named: "kk_dispatch_error", argumentCount: 0, appendThrownChannel: false) {
            _ = bindings.buildCall(builder, functionType: trapFn.type, callee: trapFn.value, arguments: [], name: "trap_\(instructionIndex)")
        }
        _ = bindings.buildBr(builder, destination: mergeBlock)

        bindings.positionBuilder(builder, at: mergeBlock)
        currentBlock = mergeBlock
        let mergedValue = vCallValue ?? zeroValue
        storeResult(result, mergedValue)

        if usesThrownChannel,
           let thrownSlotPointer,
           let thrownValue = bindings.buildLoad(
               builder,
               type: int64Type,
               pointer: thrownSlotPointer,
               name: "vthrown_val_\(instructionIndex)"
           )
        {
            if let thrownResult {
                if let alloca = copyTargetAllocas[thrownResult.rawValue] {
                    _ = bindings.buildStore(builder, value: thrownValue, pointer: alloca)
                } else {
                    storeResult(thrownResult, thrownValue)
                }
            } else if let hasThrown = buildThrownSlotCondition(
                from: thrownValue,
                name: "vhas_thrown_\(instructionIndex)"
            ),
                let thrownBlock = bindings.appendBasicBlock(
                    context: context,
                    function: llvmFunction.value,
                    name: "vthrown_\(instructionIndex)"
                ),
                let continueBlock = bindings.appendBasicBlock(
                    context: context,
                    function: llvmFunction.value,
                    name: "vcall_cont_\(instructionIndex)"
                )
            {
                _ = bindings.buildCondBr(
                    builder,
                    condition: hasThrown,
                    thenBlock: thrownBlock,
                    elseBlock: continueBlock
                )

                bindings.positionBuilder(builder, at: thrownBlock)
                storeOutThrownIfNonNull(thrownValue, suffix: "vthrow_\(instructionIndex)")
                emitFramePop("vthrow_\(instructionIndex)")
                _ = bindings.buildRet(builder, value: zeroValue)

                currentBlock = continueBlock
                bindings.positionBuilder(builder, at: continueBlock)
            }
        }
    }
}

// swiftlint:enable function_body_length
