import RuntimeABI
import CompilerCore

extension NativeEmitter.FunctionEmissionContext {

    func assignmentTargets(for instruction: KIRInstruction) -> [KIRExprID] {
        switch instruction {
        case let .constValue(result, _):
            return [result]
        case let .binary(_, _, _, result):
            return [result]
        case let .unary(_, _, result):
            return [result]
        case let .nullAssert(_, result):
            return [result]
        case let .call(_, _, _, result, _, thrownResult, _, _):
            let directTargets = result.map { [$0] } ?? []
            let thrownTargets = thrownResult.map { [$0] } ?? []
            return directTargets + thrownTargets
        case let .virtualCall(_, _, _, _, result, _, thrownResult, _):
            let directTargets = result.map { [$0] } ?? []
            let thrownTargets = thrownResult.map { [$0] } ?? []
            return directTargets + thrownTargets
        case let .copy(_, to):
            return [to]
        case let .loadGlobal(result, _):
            return [result]
        case .jump, .label, .jumpIfEqual, .jumpIfNotNull,
             .storeGlobal, .rethrow, .returnIfEqual, .returnUnit, .returnValue,
             .beginBlock, .endBlock, .nop, .nonLocalReturn,
             .beginFinallyGuard, .endFinallyGuard,
             .beginNonLocalReturnScope, .endNonLocalReturnScope, .resumeNonLocalReturn,
             .beginFinallyCleanup, .endFinallyCleanup:
            return []
        }
    }

    func isStringAggregateExpr(_ id: KIRExprID) -> Bool {
        stringAggregateBridge.isStringAggregateType(module.arena.exprType(id))
    }

    func isPrimitiveType(_ type: TypeID?) -> Bool {
        guard let type, let typeSystem,
              case .primitive = typeSystem.kind(of: type)
        else { return false }
        return true
    }

    /// Raw scalar values use Int64.min as the nullable sentinel, so zero
    /// remains a valid value for nullable primitives, enum ordinals, and Charset tags.
    /// Reference-like values still use zero as the null representation.
    func nullableRawScalarPreservesZero(_ type: TypeID?) -> Bool {
        guard let type, let typeSystem else { return false }
        switch typeSystem.kind(of: type) {
        case .primitive(_, let nullability):
            return nullability != .nonNull
        case let .classType(classType):
            guard let symbol = symbols?.symbol(classType.classSymbol) else { return false }
            return symbol.kind == .enumClass
                || symbol.fqName.map(interner.resolve) == ["kotlin", "text", "Charset"]
        case .unit, .nullableUnit, .platformUnit:
            // Safe calls returning Unit use the Int64.min sentinel for
            // null, while the valid Unit value is raw zero.
            return true
        default:
            return false
        }
    }

    func isCharSequenceRuntimeStringType(_ type: TypeID?) -> Bool {
        guard let type,
              let typeSystem,
              let charSequenceSymbol = typeSystem.charSequenceInterfaceSymbol
        else {
            return false
        }
        let nonNullType = typeSystem.makeNonNullable(type)
        guard case let .classType(classType) = typeSystem.kind(of: nonNullType) else {
            return false
        }
        return classType.classSymbol == charSequenceSymbol
    }

    func coerceStringValueForType(
        _ value: LLVMCAPIBindings.LLVMValueRef,
        from fromType: TypeID?,
        to toType: TypeID?,
        suffix: String
    ) -> LLVMCAPIBindings.LLVMValueRef {
        if stringAggregateBridge.isStringAggregateType(fromType), !stringAggregateBridge.isStringAggregateType(toType) {
            return stringAggregateBridge.bridgeStringAggregateToRuntimeRaw(value, suffix: suffix) ?? value
        }
        if !stringAggregateBridge.isStringAggregateType(fromType), stringAggregateBridge.isStringAggregateType(toType) {
            return stringAggregateBridge.bridgeRuntimeRawToStringAggregate(value, suffix: suffix) ?? value
        }
        return value
    }

    func allocateI64Slot(name: String) -> LLVMCAPIBindings.LLVMValueRef? {
        guard let slot = stringAggregateBridge.buildEntrySlot(name: name) else {
            return nil
        }
        _ = bindings.buildStore(builder, value: zeroValue, pointer: slot)
        return slot
    }

    func loweredLLVMTypes(for types: [TypeID]) -> [LLVMCAPIBindings.LLVMTypeRef?] {
        types.map {
            loweredLLVMType(for: $0, lowering: typeLowering, defaultType: int64Type)
        }
    }

    func isZeroConstant(_ id: KIRExprID) -> Bool {
        guard let expression = module.arena.expr(id) else {
            return false
        }
        switch expression {
        case .intLiteral(0), .longLiteral(0), .uintLiteral(0), .ulongLiteral(0), .null:
            return true
        default:
            return false
        }
    }

    func valueForConstant(_ expression: KIRExprKind, expressionRawID: Int32?) -> LLVMCAPIBindings.LLVMValueRef {
        let expectedType = expressionRawID.map { KIRExprID(rawValue: $0) }.flatMap(module.arena.exprType)
        return emitConstantValue(
            expression,
            expectedType: expectedType,
            state: builderState,
            parameterValues: parameterValues,
            internalFunctions: internalFunctions,
            globalVariables: globalVariables,
            nameCounter: nameCounter,
            declareExternalFunction: { name, argCount, appendThrown in
                // Runtime calls use raw handles rather than Kotlin aggregate types.
                if let spec = NativeEmitter.runtimeABIFunctionByName[name] {
                    let valueParameters = spec.parameters.filter {
                        !(spec.isThrowing && $0.name == "outThrown" && $0.type == .nullableIntptrPointer)
                    }
                    return declareExternalFunction(
                        named: name,
                        argumentCount: valueParameters.count,
                        appendThrownChannel: spec.isThrowing
                    )
                }
                // Source-backed addresses must use the same typed ABI as calls,
                // including aggregate Strings and the hidden thrown channel.
                if let symbol = externalFunctionSymbolsByLinkName[name],
                   let signature = symbols?.functionSignature(for: symbol)
                {
                    if let internalFunction = internalFunctions[symbol] {
                        return internalFunction
                    }
                    let parameterCount = sourceReceiverTypes(for: symbol, signature: signature).count
                        + signature.contextParameterTypes.count
                        + signature.parameterTypes.count
                    if let sourceSignature = sourceExternalSignature(
                        for: symbol,
                        argumentCount: parameterCount
                    ) {
                        var parameterTypes = loweredLLVMTypes(for: sourceSignature.parameters)
                        parameterTypes.append(outThrownPointerType)
                        return declareExternalFunction(
                            named: name,
                            parameterTypes: parameterTypes,
                            returnType: loweredLLVMType(
                                for: sourceSignature.returnType,
                                lowering: typeLowering,
                                defaultType: int64Type
                            )
                        )
                    }
                }
                // Function-address constants use a conservative four-word
                // prototype when no call-site signature is available. If
                // this body also calls the symbol directly, prefer that
                // observed arity so the address materialization cannot
                // poison the module's declaration before the direct call.
                let observedArgumentCount = maxKIRArgumentCountByExternalCallee[name]
                    ?? argCount
                return declareExternalFunction(
                    named: name,
                    argumentCount: observedArgumentCount,
                    // Private adapters referenced by imported inline bodies
                    // have no exported signature, but retain the mandatory
                    // thrown parameter of every compiler-generated function.
                    appendThrownChannel: appendThrown
                        || name.hasPrefix(RuntimeABISpec.compilerGeneratedLinkNamePrefix)
                )
            },
            declareExternalSymbolFunction: { symbol in
                guard let signature = symbols?.functionSignature(for: symbol),
                      let linkName = symbols?.externalLinkName(for: symbol),
                      !linkName.isEmpty
                else {
                    return nil
                }
                let runtimeSpec = NativeEmitter.runtimeABIFunctionByName[linkName]
                let argumentCount = sourceReceiverTypes(for: symbol, signature: signature).count
                    + signature.contextParameterTypes.count
                    + signature.parameterTypes.count
                let appendThrown = runtimeSpec?.isThrowing ?? true
                // Runtime aliases retain their raw-handle declaration path.
                if runtimeSpec == nil,
                   let sourceSignature = sourceExternalSignature(for: symbol, argumentCount: argumentCount)
                {
                    var parameterTypes = loweredLLVMTypes(for: sourceSignature.parameters)
                    if appendThrown {
                        parameterTypes.append(outThrownPointerType)
                    }
                    return declareExternalFunction(
                        named: linkName,
                        parameterTypes: parameterTypes,
                        returnType: loweredLLVMType(
                            for: sourceSignature.returnType,
                            lowering: typeLowering,
                            defaultType: int64Type
                        )
                    )
                }
                return declareExternalFunction(
                    named: linkName,
                    argumentCount: argumentCount,
                    appendThrownChannel: appendThrown
                )
            },
            interner: interner
        )
    }

    func resolveValue(_ id: KIRExprID) -> LLVMCAPIBindings.LLVMValueRef {
        if let alloca = copyTargetAllocas[id.rawValue] {
            let loadType = loweredLLVMType(
                for: module.arena.exprType(id),
                lowering: typeLowering,
                defaultType: int64Type
            )
            return bindings.buildLoad(builder, type: loadType, pointer: alloca, name: nameCounter.nextName("load_"))
                ?? (zeroLLVMValue(
                    for: module.arena.exprType(id),
                    lowering: typeLowering,
                    int64Type: int64Type,
                    context: context
                ) ?? zeroValue)
        }
        if let value = values[id.rawValue] {
            return value
        }
        if let expression = module.arena.expr(id) {
            if case let .symbolRef(symbol) = expression,
               let globalPointer = globalVariables[symbol]
            {
                registerGCRootForGlobal(symbol, slot: globalPointer)
            }
            let constant = valueForConstant(expression, expressionRawID: id.rawValue)
            values[id.rawValue] = constant
            storeGCRoot(for: id, value: constant)
            return constant
        }
        return zeroValue
    }

    func rawComparableValues(
        lhs: KIRExprID,
        rhs: KIRExprID
    ) -> (LLVMCAPIBindings.LLVMValueRef, LLVMCAPIBindings.LLVMValueRef) {
        let lhsValue = resolveValue(lhs)
        let rhsValue = resolveValue(rhs)
        let lhsIsAggregate = bindings.isAggregateStructValue(lhsValue)
        let rhsIsAggregate = bindings.isAggregateStructValue(rhsValue)

        if lhsIsAggregate, !rhsIsAggregate,
           let raw = rawResultValues[lhs.rawValue],
           !bindings.isAggregateStructValue(raw)
        {
            return (raw, rhsValue)
        }
        if rhsIsAggregate, !lhsIsAggregate,
           let raw = rawResultValues[rhs.rawValue],
           !bindings.isAggregateStructValue(raw)
        {
            return (lhsValue, raw)
        }
        return (lhsValue, rhsValue)
    }

    func storeResult(_ result: KIRExprID?, _ value: LLVMCAPIBindings.LLVMValueRef?) {
        guard let result else {
            return
        }
        var storedValue: LLVMCAPIBindings.LLVMValueRef = value ?? zeroLLVMValue(
            for: module.arena.exprType(result),
            lowering: typeLowering,
            int64Type: int64Type,
            context: context
        ) ?? zeroValue
        // The stored representation must match what `loweredLLVMType` yields
        // for the result expression: copy-slot allocas and `resolveValue`
        // loads both derive from it. A flat string aggregate leaking into an
        // i64-typed slot (e.g. a source-backed itable getter result with an
        // erased type) is read back as its data pointer, and a raw handle
        // stored where aggregate fields are expected is read as garbage.
        if let value,
           bindings.isAggregateStructValue(value) != stringAggregateBridge.isStringAggregateType(module.arena.exprType(result))
        {
            if stringAggregateBridge.isStringAggregateType(module.arena.exprType(result)) {
                storedValue = stringAggregateBridge.bridgeRuntimeRawToStringAggregate(
                    value,
                    suffix: nameCounter.nextName("store_result_raw_")
                ) ?? value
            } else {
                storedValue = stringAggregateBridge.bridgeStringAggregateToRuntimeRaw(
                    value,
                    suffix: nameCounter.nextName("store_result_flat_")
                ) ?? value
            }
        }
        if let resultExpr = module.arena.expr(result),
           case let .symbolRef(targetSymbol) = resultExpr,
           let globalPointer = globalVariables[targetSymbol]
        {
            // Global slots hold the runtime's raw i64 handle.  A flat
            // string aggregate has to be bridged back first, otherwise the
            // 32-byte struct is written over the slot and its neighbours.
            var globalValue = storedValue
            if stringAggregateBridge.isStringAggregateType(module.arena.exprType(result)),
               bindings.isAggregateStructValue(storedValue)
            {
                globalValue = stringAggregateBridge.bridgeStringAggregateToRuntimeRaw(
                    storedValue,
                    suffix: nameCounter.nextName("store_result_global_")
                ) ?? storedValue
            }
            registerGCRootForGlobal(targetSymbol, slot: globalPointer)
            emitGCGlobalStore(symbol: targetSymbol, pointer: globalPointer, value: globalValue)
        }
        if let alloca = copyTargetAllocas[result.rawValue],
           !bindings.hasTerminator(currentBlock)
        {
            _ = bindings.buildStore(builder, value: storedValue, pointer: alloca)
        }
        emitGCShadowSet(result, value: storedValue)
        values[result.rawValue] = storedValue
        storeGCRoot(for: result, value: storedValue)
    }

    func blockForLabel(_ label: Int32) -> LLVMCAPIBindings.LLVMBasicBlockRef? {
        if let block = labelBlocks[label] {
            return block
        }
        let block = bindings.appendBasicBlock(context: context, function: llvmFunction.value, name: nameCounter.nextName("L"))
        if let block {
            labelBlocks[label] = block
        }
        return block
    }

}
