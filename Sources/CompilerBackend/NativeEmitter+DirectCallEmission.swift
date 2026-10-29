// swiftlint:disable file_length
import RuntimeABI
import CompilerCore

extension NativeEmitter.FunctionEmissionContext {

    /// BUG-B: `.length` on a String must throw `NullPointerException`
    /// when the value is *actually* null at runtime, regardless of its
    /// statically-declared non-null type -- exactly like calling any
    /// method on a null reference. This can genuinely happen: an
    /// overridden non-null `String` property read during superclass
    /// construction observes the not-yet-run subclass initializer's
    /// zero-filled backing field, which `stringAggregateFields` bridges
    /// to a null data pointer (mirroring `kk_string_to_flat`'s existing
    /// raw-handle-zero-means-null convention). `lowerBuiltinCall`'s
    /// ordinary fast path for this accessor has no way to signal a
    /// thrown exception, so this handles it here instead, before that
    /// fast path runs, with direct access to the thrown-channel
    /// plumbing (`storeOutThrownIfNonNull`, `currentBlock`) that
    /// `lowerBuiltinCall` does not have.
    func emitThrowingStringLength(
        receiverValue: LLVMCAPIBindings.LLVMValueRef,
        result: KIRExprID?,
        usesThrownChannel: Bool,
        thrownResult: KIRExprID?,
        instructionIndex: Int
    ) -> Bool {
        guard let typeLowering,
              let fields = stringAggregateBridge.stringAggregateFields(receiverValue, suffix: "len_npe_\(instructionIndex)"),
              let nullData = bindings.constPointerNull(typeLowering.dataPointerType),
              let isNull = bindings.buildICmpEqual(
                  builder, lhs: fields[0], rhs: nullData, name: "len_npe_isnull_\(instructionIndex)"
              ),
              let npeFunction = declareExternalFunction(
                  named: "__kk_null_pointer_exception_new", argumentCount: 0, appendThrownChannel: false
              ),
              let throwBlock = bindings.appendBasicBlock(
                  context: context, function: llvmFunction.value, name: "len_npe_throw_\(instructionIndex)"
              ),
              let okBlock = bindings.appendBasicBlock(
                  context: context, function: llvmFunction.value, name: "len_npe_ok_\(instructionIndex)"
              )
        else {
            return false
        }
        let continueBlock = usesThrownChannel
            ? bindings.appendBasicBlock(context: context, function: llvmFunction.value, name: "len_npe_cont_\(instructionIndex)")
            : nil
        _ = bindings.buildCondBr(builder, condition: isNull, thenBlock: throwBlock, elseBlock: okBlock)

        currentBlock = throwBlock
        bindings.positionBuilder(builder, at: throwBlock)
        let exceptionHandle: LLVMCAPIBindings.LLVMValueRef = bindings.buildCall(
            builder, functionType: npeFunction.type, callee: npeFunction.value, arguments: [],
            name: "len_npe_exc_\(instructionIndex)"
        ) ?? zeroValue
        storeResult(result, zeroValue)
        if usesThrownChannel, let thrownResult, let continueBlock {
            storeResult(thrownResult, exceptionHandle)
            _ = bindings.buildBr(builder, destination: continueBlock)
        } else {
            storeOutThrownIfNonNull(exceptionHandle, suffix: "len_npe_\(instructionIndex)")
            emitGCFrameLeave(returning: exceptionHandle)
            _ = bindings.buildRet(builder, value: zeroReturnValue)
        }

        currentBlock = okBlock
        bindings.positionBuilder(builder, at: okBlock)
        storeResult(result, fields[1])
        if usesThrownChannel, let thrownResult {
            storeResult(thrownResult, zeroValue)
        }
        if let continueBlock {
            _ = bindings.buildBr(builder, destination: continueBlock)
            currentBlock = continueBlock
            bindings.positionBuilder(builder, at: continueBlock)
        } else {
            currentBlock = okBlock
        }
        return true
    }

    func emitFlatStringRuntimeCall(
        calleeName: String,
        arguments: [KIRExprID],
        argumentValues: [LLVMCAPIBindings.LLVMValueRef],
        result: KIRExprID?,
        usesThrownChannel: Bool,
        thrownResult: KIRExprID?,
        instructionIndex: Int
    ) -> Bool {
        guard let typeLowering else {
            return false
        }
        let argumentTypes = arguments.map(module.arena.exprType)

        let flatStringReturnCallSpecs = NativeEmitter.flatStringReturnCallSpecs
        let flatScalarReturnCallSpecs = NativeEmitter.flatScalarReturnCallSpecs

        func emitFlatStringReturnCall(_ spec: NativeEmitter.FlatStringReturnCallSpec) -> Bool {
            let requiredArgumentCount = spec.stringArgumentCount + spec.extraArgumentCount
            guard let result,
                  argumentValues.count >= requiredArgumentCount,
                  spec.stringArgumentPositions.count == spec.stringArgumentCount,
                  let flattenedArgs = flattenedRuntimeArguments(
                      values: argumentValues,
                      types: argumentTypes,
                      ids: arguments.map(Optional.some),
                      argumentCount: requiredArgumentCount,
                      stringArgumentPositions: spec.stringArgumentPositions,
                      suffix: "\(spec.flatName)_\(instructionIndex)"
                  ),
                  var parameterTypes = flattenedRuntimeParameterTypes(
                      argumentCount: requiredArgumentCount,
                      stringArgumentPositions: spec.stringArgumentPositions
                  ),
                  let lengthSlot = allocateI64Slot(name: "\(spec.flatName)_length_\(instructionIndex)"),
                  let byteCountSlot = allocateI64Slot(name: "\(spec.flatName)_bytes_\(instructionIndex)"),
                  let hashSlot = allocateI64Slot(name: "\(spec.flatName)_hash_\(instructionIndex)")
            else {
                return false
            }

            parameterTypes.append(contentsOf: [
                outThrownPointerType,
                outThrownPointerType,
                outThrownPointerType,
            ])

            let thrownSlot = spec.canThrow && usesThrownChannel
                ? allocateI64Slot(name: "\(spec.flatName)_thrown_\(instructionIndex)")
                : nil
            if spec.canThrow {
                parameterTypes.append(outThrownPointerType)
            }
            guard let runtimeFunction = declareExternalFunction(
                named: spec.flatName,
                parameterTypes: parameterTypes,
                returnType: typeLowering.dataPointerType
            )
            else {
                return false
            }

            let thrownPointer = thrownSlot ?? nullThrownPointer
            let callArguments = flattenedArgs
                + [lengthSlot, byteCountSlot, hashSlot]
                + (spec.canThrow ? [thrownPointer] : [])
            guard let data = bindings.buildCall(
                builder,
                functionType: runtimeFunction.type,
                callee: runtimeFunction.value,
                arguments: callArguments,
                name: "\(spec.flatName)_data_\(instructionIndex)"
            ),
                let length = bindings.buildLoad(
                    builder,
                    type: int64Type,
                    pointer: lengthSlot,
                    name: "\(spec.flatName)_length_val_\(instructionIndex)"
                ),
                let byteCount = bindings.buildLoad(
                    builder,
                    type: int64Type,
                    pointer: byteCountSlot,
                    name: "\(spec.flatName)_bytes_val_\(instructionIndex)"
                ),
                let hash = bindings.buildLoad(
                    builder,
                    type: int64Type,
                    pointer: hashSlot,
                    name: "\(spec.flatName)_hash_val_\(instructionIndex)"
                )
            else {
                return false
            }
            guard let aggregate = buildStringAggregate(
                builder: builder,
                lowering: typeLowering,
                data: data,
                length: length,
                byteCount: byteCount,
                hash: hash,
                name: "\(spec.flatName)_result_\(instructionIndex)"
            ) else {
                return false
            }
            let storedValue: LLVMCAPIBindings.LLVMValueRef
            if stringAggregateBridge.isStringAggregateType(module.arena.exprType(result)) {
                storedValue = aggregate
            } else if let raw = stringAggregateBridge.bridgeStringAggregateToRuntimeRaw(
                aggregate,
                suffix: "\(spec.flatName)_result_\(instructionIndex)"
            ) {
                storedValue = raw
            } else {
                return false
            }
            storeResult(result, storedValue)
            if spec.canThrow {
                if usesThrownChannel {
                    handleThrownSlot(thrownSlot, thrownResult: thrownResult, instructionIndex: instructionIndex)
                }
            } else if usesThrownChannel {
                storeThrownResultZero(thrownResult)
            }
            return true
        }

        func emitFlatScalarReturnCall(_ spec: NativeEmitter.FlatScalarReturnCallSpec) -> Bool {
            let requiredArgumentCount = spec.stringArgumentCount + spec.extraArgumentCount
            var effectiveArgumentValues = argumentValues
            var effectiveArgumentTypes = argumentTypes
            if spec.defaultMissingClosureRaw,
               effectiveArgumentValues.count == requiredArgumentCount - 1 {
                effectiveArgumentValues.append(zeroValue)
                effectiveArgumentTypes.append(nil)
            }
            guard effectiveArgumentValues.count >= requiredArgumentCount,
                  spec.stringArgumentPositions.count == spec.stringArgumentCount,
                  let flattenedArgs = flattenedRuntimeArguments(
                      values: effectiveArgumentValues,
                      types: effectiveArgumentTypes,
                      ids: Array(arguments.map(Optional.some).prefix(effectiveArgumentValues.count))
                          + Array(
                              repeating: nil,
                              count: max(0, effectiveArgumentValues.count - arguments.count)
                          ),
                      argumentCount: requiredArgumentCount,
                      stringArgumentPositions: spec.stringArgumentPositions,
                      suffix: "\(spec.flatName)_\(instructionIndex)"
                  ),
                  var parameterTypes = flattenedRuntimeParameterTypes(
                      argumentCount: requiredArgumentCount,
                      stringArgumentPositions: spec.stringArgumentPositions
                  )
            else {
                return false
            }

            let thrownSlot = spec.canThrow && usesThrownChannel
                ? allocateI64Slot(name: "\(spec.flatName)_thrown_\(instructionIndex)")
                : nil
            if spec.canThrow {
                parameterTypes.append(outThrownPointerType)
            }

            guard let runtimeFunction = declareExternalFunction(
                named: spec.flatName,
                parameterTypes: parameterTypes,
                returnType: int64Type
            )
            else {
                return false
            }
            let scalarValue = bindings.buildCall(
                builder,
                functionType: runtimeFunction.type,
                callee: runtimeFunction.value,
                arguments: flattenedArgs
                    + (spec.canThrow ? [thrownSlot ?? nullThrownPointer] : []),
                name: "\(spec.flatName)_value_\(instructionIndex)"
            )
            let storedScalarValue: LLVMCAPIBindings.LLVMValueRef?
            if let result,
               isStringAggregateExpr(result),
               let scalarValue
            {
                storedScalarValue = stringAggregateBridge.bridgeRuntimeRawToStringAggregate(
                    scalarValue,
                    suffix: "\(spec.flatName)_result_\(instructionIndex)"
                ) ?? scalarValue
            } else {
                storedScalarValue = scalarValue
            }
            storeResult(result, storedScalarValue)
            if spec.canThrow {
                if usesThrownChannel {
                    handleThrownSlot(thrownSlot, thrownResult: thrownResult, instructionIndex: instructionIndex)
                }
            } else if usesThrownChannel {
                storeThrownResultZero(thrownResult)
            }
            return true
        }

        if let spec = flatStringReturnCallSpecs[calleeName],
           emitFlatStringReturnCall(spec)
        {
            return true
        }
        if let spec = flatScalarReturnCallSpecs[calleeName],
           emitFlatScalarReturnCall(spec)
        {
            return true
        }

        return false
    }

    func emitBuiltinCall(
        calleeName: String,
        argumentValues: [LLVMCAPIBindings.LLVMValueRef],
        argumentTypes: [TypeID?],
        result: KIRExprID?,
        instructionIndex: Int
    ) -> Bool {
        let builtinResult = lowerBuiltinCall(
            calleeName: calleeName,
            argumentValues: argumentValues,
            argumentTypes: argumentTypes,
            resultType: result.flatMap(module.arena.exprType),
            state: builderState,
            instructionIndex: instructionIndex
        )
        guard builtinResult.handled else {
            return false
        }
        storeResult(result, builtinResult.value)
        return true
    }

    func emitDirectCall(
        symbol: SymbolID?,
        callee: InternedString,
        arguments: [KIRExprID],
        result: KIRExprID?,
        usesThrownChannel: Bool,
        thrownResult: KIRExprID?,
        isSuperCall: Bool,
        qualifiedSuperType: SymbolID?,
        instructionIndex: Int
    ) {
        // super calls always use direct dispatch – when virtual dispatch
        // is introduced the isSuperCall flag will bypass vtable lookup.
        // qualifiedSuperType provides additional context for super<Interface> calls
        _ = (isSuperCall, qualifiedSuperType)
        guard !bindings.hasTerminator(currentBlock) else {
            return
        }

        let calleeName = interner.resolve(callee)
        // Reified enum intrinsics survive only in unspecialized template
        // bodies. Their serialized KIR is expanded by consumers, while
        // the native fallback must not reference a bodyless stdlib stub.
        if calleeName == "$reifiedEnumValues", let symbol,
           symbols?.symbol(symbol)?.fqName.map(interner.resolve) == ["kotlin", "enumValues"] {
            if let trap = declareExternalFunction(named: "kk_abort_unreachable", argumentCount: 1, appendThrownChannel: false) {
                _ = bindings.buildCall(builder, functionType: trap.type, callee: trap.value, arguments: [nullThrownPointer], name: "reified_enum_template")
            }
            storeResult(result, zeroValue)
            return
        }
        var argumentValues = arguments.map(resolveValue)
        var argumentTypes = arguments.map(module.arena.exprType)
        let externalCalleeName = NativeEmitter.runtimePrimitiveAlias(
            for: calleeName,
            resolvedSymbol: symbol
        ) ?? calleeName

        if emitFlatStringRuntimeCall(
            calleeName: externalCalleeName,
            arguments: arguments,
            argumentValues: argumentValues,
            result: result,
            usesThrownChannel: usesThrownChannel,
            thrownResult: thrownResult,
            instructionIndex: instructionIndex
        ) {
            return
        }

        // Keep this collection empty: all print/println calls are lowered
        // through the bundled Kotlin source and the raw print bridge.
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

        // BUG-B: must run before `emitBuiltinCall`'s ordinary fast
        // path for this accessor, which has no way to signal a
        // thrown exception. Gated on the receiver's KIR-level type
        // actually being String -- not merely "an aggregate struct
        // value" -- so a CharSequence/StringBuilder handle bridged
        // through the same struct shape never starts throwing.
        if NativeEmitter.isStringLengthAggregateAccessorName(externalCalleeName),
           argumentValues.count == 1,
           stringAggregateBridge.isStringAggregateType(argumentTypes.first ?? nil),
           emitThrowingStringLength(
               receiverValue: argumentValues[0],
               result: result,
               usesThrownChannel: usesThrownChannel,
               thrownResult: thrownResult,
               instructionIndex: instructionIndex
           )
        {
            return
        }

        if emitBuiltinCall(
            calleeName: externalCalleeName,
            argumentValues: argumentValues,
            argumentTypes: argumentTypes,
            result: result,
            instructionIndex: instructionIndex
        ) {
            return
        }

        // CORO-001: kk_channel_receive returns status out-of-band; payload via outValue.
        // KUU-1404: terminal statuses (closed/cancelled) are converted to
        // Kotlin throwables inside the runtime and reported through the
        // outThrown channel, so the call now appends a thrown slot like
        // every other throwing runtime entry point.
        if calleeName == "kk_channel_receive" {
            let outValueSlot = stringAggregateBridge.buildEntrySlot(name: "channel_out_value_\(instructionIndex)")
            if let outValueSlot {
                _ = bindings.buildStore(builder, value: zeroValue, pointer: outValueSlot)
            }
            var receiveArgs = argumentValues
            // Some unresolved explicit `Channel.receive()` calls reach this
            // bridge with only the channel handle. The runtime ABI always
            // reserves its second argument for a continuation, so preserve
            // the null placeholder used by the ordinary member-call path.
            if receiveArgs.count == 1 {
                receiveArgs.append(zeroValue)
            }
            receiveArgs.append(outValueSlot ?? nullThrownPointer)
            var thrownSlotPointer: LLVMCAPIBindings.LLVMValueRef?
            if usesThrownChannel {
                if let thrownSlot = stringAggregateBridge.buildEntrySlot(name: "thrown_slot_\(instructionIndex)") {
                    _ = bindings.buildStore(builder, value: zeroValue, pointer: thrownSlot)
                    receiveArgs.append(thrownSlot)
                    thrownSlotPointer = thrownSlot
                } else {
                    receiveArgs.append(nullThrownPointer)
                }
            } else {
                receiveArgs.append(nullThrownPointer)
            }
            if let receiveFunction = declareExternalFunction(
                named: "kk_channel_receive",
                argumentCount: 3,
                appendThrownChannel: true
            ) {
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
            if usesThrownChannel {
                handleThrownSlot(thrownSlotPointer, thrownResult: thrownResult, instructionIndex: instructionIndex)
            }
            return
        }

        // Function-value invokes carry the callable value as their first
        // argument.  The KIR symbol is intentionally retained for
        // InlineLoweringPass to match an inline function parameter, but
        // it must not be treated as a direct callee here: doing so turns
        // a captured parameter such as `transform` into an undefined
        // external `_transform` symbol (KSP-499 compiler regression).
        let isFunctionValueInvoke = NativeEmitter.functionValueInvokeCallees.contains(calleeName)
        // SequenceScope symbols retain generic parameter types for ABI
        // boxing, but their source bodies do not implement the runtime
        // builder. Honor the remapped bridge after boxing is complete.
        let isSequenceBuilderRuntimeCall = calleeName == "__kk_sequence_builder_yield"
            || calleeName == "__kk_sequence_builder_yieldAll"
            || calleeName == "__kk_sequence_builder_yieldAll_checked"
        // A `kk_`/`__kk_` callee spelling is a lowered runtime name, not
        // a source-level identifier. When such a call still carries a
        // KIR symbol that the callee text does not actually name (not the
        // declared name, not the symbol's own `kk_fn_*` link name, and
        // not the emitted entry in the internal lookup table), the
        // symbol is stale bookkeeping: CallLowerer retargeted the call
        // to a runtime bridge (e.g. `__kk_iterable_firstNotNullOf`) while
        // keeping the source symbol for inline-expansion bookkeeping.
        // Binding that call through `internalFunctions[symbol]` would
        // invoke the source body with bridge-shaped arguments, so the
        // callee text must win.
        let calleeIsRuntimeName = calleeName.hasPrefix("kk_")
            || calleeName.hasPrefix("__kk_")
        let calleeLookupKey = NativeEmitter.FunctionLookupKey(
            name: calleeName,
            parameterCount: argumentValues.count
        )
        // Lowering also writes synthetic `kk_`/`__kk_` labels that name
        // no real function (e.g. `__kk_kproperty_impl_<id>` wraps the
        // property implementation symbol, and lambda sites spell
        // `kk_lambda_<id>` while retaining the callee's symbol). Those
        // spellings resolve to nothing the emitter can reach by name —
        // no emitted internal entry, no runtime ABI spec, no declared
        // LLVM function — so the retained symbol remains the binding.
        let calleeResolvesToRealTarget = internalFunctionsByLookupKey[calleeLookupKey] != nil
            || NativeEmitter.runtimeABIFunctionByName[calleeName] != nil
            || externalFunctions[calleeName] != nil
            || bindings.getNamedFunction(module: llvmModule, name: calleeName) != nil
        let calleeNamesSymbol: Bool = if !calleeIsRuntimeName {
            true
        } else if let symbol, symbol != .invalid {
            symbols?.symbol(symbol)?.name == callee
                || symbols?.externalLinkName(for: symbol)
                    .map({ $0.hasPrefix("kk_fn_") && $0 == calleeName }) == true
                || internalFunctionsByLookupKey[calleeLookupKey]?
                    .contains(where: { $0.symbol == symbol }) == true
                || !calleeResolvesToRealTarget
        } else {
            false
        }
        let normalizedSymbol: SymbolID? = if !isFunctionValueInvoke,
                                               !isSequenceBuilderRuntimeCall,
                                               let symbol,
                                               symbol != .invalid,
                                               calleeNamesSymbol
        {
            symbol
        } else {
            SymbolID?.none
        }
        let fallbackInternal: (symbol: SymbolID, function: NativeEmitter.LLVMFunction)? = if normalizedSymbol == nil {
            resolveUnnamedInternalFunction(
                named: calleeName,
                argumentCount: argumentValues.count,
                argumentTypes: argumentTypes,
                appendThrownChannel: usesThrownChannel
            )
        } else {
            nil
        }
        let effectiveSymbol = normalizedSymbol ?? fallbackInternal?.symbol
        let calleeFunction: NativeEmitter.LLVMFunction?
        let isInternalCall = effectiveSymbol.flatMap { internalFunctions[$0] } != nil
        let effectiveExternalName = effectiveSymbol.flatMap { symbols?.externalLinkName(for: $0) } ?? externalCalleeName
        // Default stubs can forward boxed callbacks without passing through CallLowerer's expansion.
        if !isInternalCall,
           let spec = NativeEmitter.runtimeABIFunctionByName[effectiveExternalName]
        {
            let valueParameters = spec.parameters.filter { $0.name != "outThrown" }
            if argumentValues.count + 1 == valueParameters.count,
               let callbackIndex = valueParameters.firstIndex(where: {
                   $0.name == "fnPtr" || $0.name.hasSuffix("FnPtr")
               }),
               callbackIndex + 1 < valueParameters.count,
               valueParameters[callbackIndex + 1].name == (valueParameters[callbackIndex].name == "fnPtr"
                   ? "closureRaw" : String(valueParameters[callbackIndex].name.dropLast(5)) + "ClosureRaw"),
               argumentTypes.indices.contains(callbackIndex),
               let callbackType = argumentTypes[callbackIndex],
               let typeSystem,
               case .functionType = typeSystem.kind(of: typeSystem.makeNonNullable(callbackType))
            {
                let callback = argumentValues[callbackIndex]
                var expandedCallback: [LLVMCAPIBindings.LLVMValueRef] = []
                for getter in ["kk_function_value_fn_ptr", "kk_function_value_closure_raw"] {
                    if let function = declareExternalFunction(named: getter, argumentCount: 1, appendThrownChannel: false),
                       let value = bindings.buildCall(
                           builder, functionType: function.type, callee: function.value,
                           arguments: [callback], name: "\(getter)_\(instructionIndex)"
                       )
                    {
                        expandedCallback.append(value)
                    }
                }
                if expandedCallback.count == 2 {
                    argumentValues.replaceSubrange(callbackIndex...callbackIndex, with: expandedCallback)
                    argumentTypes.replaceSubrange(callbackIndex...callbackIndex, with: [nil, nil])
                }
            }
        }
        let sourceExternalCallSignature = !isInternalCall
            ? sourceExternalSignature(
                for: effectiveSymbol,
                argumentCount: argumentValues.count
            )
            : nil
        let shouldAppendThrownChannel = isInternalCall
            || (NativeEmitter.runtimeABIFunctionByName[effectiveExternalName].map { spec in
                spec.parameters.contains { $0.name == "outThrown" && $0.type == .nullableIntptrPointer }
            }
                ?? (usesThrownChannel || sourceExternalCallSignature != nil))

        if let effectiveSymbol,
           let internalFunction = internalFunctions[effectiveSymbol]
        {
            calleeFunction = internalFunction
        } else if let fallbackInternal {
            calleeFunction = fallbackInternal.function
        } else if calleeName.isEmpty {
            calleeFunction = nil
        } else if NativeEmitter.isStringLengthAggregateAccessorName(calleeName), argumentValues.count == 1 {
            calleeFunction = declareExternalFunction(
                named: "__kk_string_struct_get_length",
                argumentCount: 1,
                appendThrownChannel: false
            )
        } else if let sourceExternalCallSignature {
            var parameterTypes = loweredLLVMTypes(for: sourceExternalCallSignature.parameters)
            if shouldAppendThrownChannel {
                parameterTypes.append(outThrownPointerType)
            }
            calleeFunction = declareExternalFunction(
                named: effectiveExternalName,
                parameterTypes: parameterTypes,
                returnType: loweredLLVMType(
                    for: sourceExternalCallSignature.returnType,
                    lowering: typeLowering,
                    defaultType: int64Type
                )
            )
        } else {
            // Honor the callee symbol's recorded external link name
            // (e.g. an imported `name$default` stub carrying its
            // `kk_fn_*` link) even without a source-level signature —
            // falling back to the raw KIR callee name here emits an
            // unresolvable `foo$default` reference.
            calleeFunction = declareExternalFunction(
                named: effectiveExternalName,
                argumentCount: argumentValues.count,
                appendThrownChannel: shouldAppendThrownChannel
            )
        }

        guard let calleeFunction else {
            storeResult(result, nil)
            return
        }

        var callArguments = argumentValues
        let internalSignature = internalSignature(for: effectiveSymbol)
        let typedSignature = isInternalCall ? internalSignature : sourceExternalCallSignature
        let callVarargFlags: [Bool] = effectiveSymbol.flatMap {
            symbols?.functionSignature(for: $0)?.valueParameterIsVararg
        } ?? []
        let callReceiverOffset: Int = effectiveSymbol.flatMap {
            guard let signature = symbols?.functionSignature(for: $0) else { return nil }
            if let sourceExternalCallSignature {
                // Externally declared signatures flatten receivers and context
                // parameters before their value parameters.
                return max(0, sourceExternalCallSignature.parameters.count - signature.parameterTypes.count)
            }
            return sourceReceiverTypes(for: $0, signature: signature).count + signature.contextParameterTypes.count
        } ?? 0
        let isRuntimeCallbackRawABIInternalCall = isInternalCall
            && effectiveSymbol.map { runtimeCallbackRawReturnSymbols.contains($0) } == true
        if let parameterTypes = typedSignature?.parameters {
            callArguments = zip(argumentValues, parameterTypes).enumerated().map { index, pair in
                let (argumentValue, parameterType) = pair
                let argumentType = argumentTypes.indices.contains(index) ? argumentTypes[index] : nil
                let varargIndex = index - callReceiverOffset
                if callVarargFlags.indices.contains(varargIndex),
                   callVarargFlags[varargIndex]
                {
                    // A normalized vararg is carried as an erased array/list
                    // handle even though metadata records its element type.
                    return argumentValue
                }
                if isRuntimeCallbackRawABIInternalCall {
                    guard stringAggregateBridge.isStringAggregateType(argumentType) else {
                        return argumentValue
                    }
                    return stringAggregateBridge.bridgeStringAggregateToRuntimeRaw(
                        argumentValue,
                        suffix: "\(instructionIndex)_runtime_callback_arg\(index)"
                    ) ?? argumentValue
                }
                if stringAggregateBridge.isStringAggregateType(argumentType), !stringAggregateBridge.isStringAggregateType(parameterType) {
                    return stringAggregateBridge.bridgeStringAggregateToRuntimeRaw(
                        argumentValue,
                        suffix: "\(instructionIndex)_internal_arg\(index)"
                    ) ?? argumentValue
                }
                if !stringAggregateBridge.isStringAggregateType(argumentType), stringAggregateBridge.isStringAggregateType(parameterType) {
                    if arguments.indices.contains(index),
                       isZeroConstant(arguments[index]),
                       let typeLowering,
                       let nullString = buildNullStringAggregate(
                           builder: builder,
                           lowering: typeLowering,
                           name: "string_null_internal_arg\(instructionIndex)_\(index)"
                       )
                    {
                        return nullString
                    }
                    return stringAggregateBridge.bridgeRuntimeRawToStringAggregate(
                        argumentValue,
                        suffix: "\(instructionIndex)_internal_arg\(index)"
                    ) ?? argumentValue
                }
                return argumentValue
            }
        }
        let shouldBridgeExternalStringABI = !isInternalCall && sourceExternalCallSignature == nil && typeLowering != nil
        if shouldBridgeExternalStringABI {
            callArguments = zip(argumentValues, argumentTypes).enumerated().map { index, pair in
                let (argumentValue, argumentType) = pair
                guard stringAggregateBridge.isStringAggregateType(argumentType) else {
                    return argumentValue
                }
                return stringAggregateBridge.bridgeStringAggregateToRuntimeRaw(
                    argumentValue,
                    suffix: "\(instructionIndex)_arg\(index)"
                ) ?? argumentValue
            }
        }
        var thrownSlotPointer: LLVMCAPIBindings.LLVMValueRef?
        if shouldAppendThrownChannel {
            if usesThrownChannel {
                let thrownSlot = stringAggregateBridge.buildEntrySlot(name: "thrown_slot_\(instructionIndex)")
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
        let storedCallValue: LLVMCAPIBindings.LLVMValueRef?
        if isInternalCall,
           let effectiveSymbol,
           runtimeCallbackRawReturnSymbols.contains(effectiveSymbol),
           let result,
           isStringAggregateExpr(result),
           let callValue
        {
            storedCallValue = stringAggregateBridge.bridgeRuntimeRawToStringAggregate(
                callValue,
                suffix: "\(instructionIndex)_runtime_callback_result"
            ) ?? callValue
        } else if isInternalCall,
                  let effectiveSymbol,
                  runtimeCallbackRawReturnSymbols.contains(effectiveSymbol)
        {
            storedCallValue = callValue
        } else if isInternalCall,
           let result,
           let returnType = internalSignature?.returnType,
           stringAggregateBridge.isStringAggregateType(returnType),
           !isStringAggregateExpr(result),
           let callValue
        {
            storedCallValue = stringAggregateBridge.bridgeStringAggregateToRuntimeRaw(
                callValue,
                suffix: "\(instructionIndex)_internal_result"
            ) ?? callValue
        } else if isInternalCall,
                  let result,
                  let returnType = internalSignature?.returnType,
                  !stringAggregateBridge.isStringAggregateType(returnType),
                  isStringAggregateExpr(result),
                  let callValue
        {
            storedCallValue = stringAggregateBridge.bridgeRuntimeRawToStringAggregate(
                callValue,
                suffix: "\(instructionIndex)_internal_result"
            ) ?? callValue
        } else if sourceExternalCallSignature != nil,
                  let result,
                  let returnType = sourceExternalCallSignature?.returnType,
                  stringAggregateBridge.isStringAggregateType(returnType),
                  !isStringAggregateExpr(result),
                  let callValue
        {
            storedCallValue = stringAggregateBridge.bridgeStringAggregateToRuntimeRaw(
                callValue,
                suffix: "\(instructionIndex)_source_external_result"
            ) ?? callValue
        } else if sourceExternalCallSignature != nil,
                  let result,
                  let returnType = sourceExternalCallSignature?.returnType,
                  !stringAggregateBridge.isStringAggregateType(returnType),
                  isStringAggregateExpr(result),
                  let callValue
        {
            storedCallValue = stringAggregateBridge.bridgeRuntimeRawToStringAggregate(
                callValue,
                suffix: "\(instructionIndex)_source_external_result"
            ) ?? callValue
        } else if shouldBridgeExternalStringABI,
           let result,
           isStringAggregateExpr(result),
           let callValue
        {
            storedCallValue = stringAggregateBridge.bridgeRuntimeRawToStringAggregate(
                callValue,
                suffix: "\(instructionIndex)_result"
            ) ?? callValue
        } else {
            storedCallValue = callValue
        }
        storeResult(result, storedCallValue)
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
           !handleThrownSlot(thrownSlotPointer, thrownResult: thrownResult, instructionIndex: instructionIndex)
        {
            storeResult(thrownResult, zeroValue)
        }
    }

}
