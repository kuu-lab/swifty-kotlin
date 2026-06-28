import CompilerCore

extension NativeEmitter {
    final class FunctionEmissionState {
        let emitter: NativeEmitter
        let builder: LLVMCAPIBindings.LLVMBuilderRef
        let int64Type: LLVMCAPIBindings.LLVMTypeRef
        let zeroValue: LLVMCAPIBindings.LLVMValueRef
        let context: LLVMCAPIBindings.LLVMContextRef
        let llvmModule: LLVMCAPIBindings.LLVMModuleRef
        let llvmFunction: LLVMFunction
        let outThrownPointerType: LLVMCAPIBindings.LLVMTypeRef
        let outThrownParameter: LLVMCAPIBindings.LLVMValueRef?
        let nullThrownPointer: LLVMCAPIBindings.LLVMValueRef
        let parameterValues: [SymbolID: LLVMCAPIBindings.LLVMValueRef]
        let internalFunctions: [SymbolID: LLVMFunction]
        let globalVariables: [SymbolID: LLVMCAPIBindings.LLVMValueRef]
        let maxKIRArgumentCountByExternalCallee: [String: Int]
        let builderState: EmissionBuilderState
        let copyTargetAllocas: [Int32: LLVMCAPIBindings.LLVMValueRef]

        var framePopFunction: LLVMFunction?
        var coroutineRegisterRootFunction: LLVMFunction?
        var coroutineUnregisterRootFunction: LLVMFunction?
        var functionIDValue: LLVMCAPIBindings.LLVMValueRef

        var currentBlock: LLVMCAPIBindings.LLVMBasicBlockRef
        var values: [Int32: LLVMCAPIBindings.LLVMValueRef] = [:]
        var externalFunctions: [String: LLVMFunction] = [:]
        var labelBlocks: [Int32: LLVMCAPIBindings.LLVMBasicBlockRef]
        var generatedStringLiteralCount: Int32 = 0

        var bindings: LLVMCAPIBindings { emitter.bindings }
        var module: KIRModule { emitter.module }
        var interner: StringInterner { emitter.interner }
        var sourceManager: SourceManager? { emitter.sourceManager }

        init(
            emitter: NativeEmitter,
            builder: LLVMCAPIBindings.LLVMBuilderRef,
            int64Type: LLVMCAPIBindings.LLVMTypeRef,
            zeroValue: LLVMCAPIBindings.LLVMValueRef,
            context: LLVMCAPIBindings.LLVMContextRef,
            llvmModule: LLVMCAPIBindings.LLVMModuleRef,
            llvmFunction: LLVMFunction,
            outThrownPointerType: LLVMCAPIBindings.LLVMTypeRef,
            outThrownParameter: LLVMCAPIBindings.LLVMValueRef?,
            nullThrownPointer: LLVMCAPIBindings.LLVMValueRef,
            parameterValues: [SymbolID: LLVMCAPIBindings.LLVMValueRef],
            internalFunctions: [SymbolID: LLVMFunction],
            globalVariables: [SymbolID: LLVMCAPIBindings.LLVMValueRef],
            maxKIRArgumentCountByExternalCallee: [String: Int],
            builderState: EmissionBuilderState,
            copyTargetAllocas: [Int32: LLVMCAPIBindings.LLVMValueRef],
            currentBlock: LLVMCAPIBindings.LLVMBasicBlockRef,
            labelBlocks: [Int32: LLVMCAPIBindings.LLVMBasicBlockRef]
        ) {
            self.emitter = emitter
            self.builder = builder
            self.int64Type = int64Type
            self.zeroValue = zeroValue
            self.context = context
            self.llvmModule = llvmModule
            self.llvmFunction = llvmFunction
            self.outThrownPointerType = outThrownPointerType
            self.outThrownParameter = outThrownParameter
            self.nullThrownPointer = nullThrownPointer
            self.parameterValues = parameterValues
            self.internalFunctions = internalFunctions
            self.globalVariables = globalVariables
            self.maxKIRArgumentCountByExternalCallee = maxKIRArgumentCountByExternalCallee
            self.builderState = builderState
            self.copyTargetAllocas = copyTargetAllocas
            self.currentBlock = currentBlock
            self.labelBlocks = labelBlocks
            self.functionIDValue = zeroValue
        }
    }
}

extension NativeEmitter.FunctionEmissionState {

    static func assignmentTargets(for instruction: KIRInstruction) -> [KIRExprID] {
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
             .beginFinallyGuard, .endFinallyGuard:
            return []
        }
    }

    func declareExternalFunction(
        named calleeName: String,
        argumentCount: Int,
        appendThrownChannel: Bool
    ) -> NativeEmitter.LLVMFunction? {
        let effectiveName: String = if calleeName == "length", argumentCount == 1, !appendThrownChannel {
            "kk_string_length"
        } else {
            calleeName
        }
        if let existing = externalFunctions[effectiveName] {
            return existing
        }
        let maxArgsSeenInBody = maxKIRArgumentCountByExternalCallee[effectiveName] ?? 0
        let effectiveArgumentCount = max(argumentCount, maxArgsSeenInBody)
        var callParameterTypes = Array(repeating: int64Type, count: effectiveArgumentCount)
        if appendThrownChannel {
            callParameterTypes.append(outThrownPointerType)
        }
        guard let externalType = bindings.functionType(
            returnType: int64Type,
            parameters: callParameterTypes,
            isVarArg: false
        ) else {
            return nil
        }
        let externalValue = bindings.getNamedFunction(module: llvmModule, name: effectiveName)
            ?? bindings.addFunction(module: llvmModule, name: effectiveName, functionType: externalType)
        guard let externalValue else {
            return nil
        }
        let declared = NativeEmitter.LLVMFunction(value: externalValue, type: externalType)
        externalFunctions[effectiveName] = declared
        return declared
    }

    func resolveUnnamedInternalFunction(
        named calleeName: String,
        argumentCount: Int,
        appendThrownChannel _: Bool
    ) -> (symbol: SymbolID, function: NativeEmitter.LLVMFunction)? {
        var match: (symbol: SymbolID, function: NativeEmitter.LLVMFunction)?
        let expectedParameterCount = argumentCount
        for declaration in module.arena.declarations {
            guard case let .function(candidate) = declaration,
                  interner.resolve(candidate.name) == calleeName,
                  candidate.params.count == expectedParameterCount,
                  let llvmFunc = internalFunctions[candidate.symbol]
            else {
                continue
            }
            if match != nil {
                return nil
            }
            match = (candidate.symbol, llvmFunc)
        }
        return match
    }

    func valueForConstant(_ expression: KIRExprKind, expressionRawID: Int32?) -> LLVMCAPIBindings.LLVMValueRef {
        emitter.emitConstantValue(
            expression,
            expressionRawID: expressionRawID,
            state: builderState,
            parameterValues: parameterValues,
            internalFunctions: internalFunctions,
            globalVariables: globalVariables,
            generatedStringLiteralCount: &generatedStringLiteralCount,
            declareExternalFunction: { name, argCount, appendThrown in
                self.declareExternalFunction(named: name, argumentCount: argCount, appendThrownChannel: appendThrown)
            },
            interner: interner
        )
    }

    func resolveValue(_ id: KIRExprID) -> LLVMCAPIBindings.LLVMValueRef {
        if let alloca = copyTargetAllocas[id.rawValue] {
            return bindings.buildLoad(builder, type: int64Type, pointer: alloca, name: "load_\(id.rawValue)") ?? zeroValue
        }
        if let value = values[id.rawValue] {
            return value
        }
        if let expression = module.arena.expr(id) {
            let constant = valueForConstant(expression, expressionRawID: id.rawValue)
            values[id.rawValue] = constant
            return constant
        }
        return zeroValue
    }

    func storeResult(_ result: KIRExprID?, _ value: LLVMCAPIBindings.LLVMValueRef?) {
        guard let result else {
            return
        }
        let storedValue = value ?? zeroValue
        if let resultExpr = module.arena.expr(result),
           case let .symbolRef(targetSymbol) = resultExpr,
           let globalPointer = globalVariables[targetSymbol]
        {
            _ = bindings.buildStore(builder, value: storedValue, pointer: globalPointer)
        }
        if let alloca = copyTargetAllocas[result.rawValue] {
            _ = bindings.buildStore(builder, value: storedValue, pointer: alloca)
        }
        values[result.rawValue] = storedValue
    }

    func blockForLabel(_ label: Int32) -> LLVMCAPIBindings.LLVMBasicBlockRef? {
        if let block = labelBlocks[label] {
            return block
        }
        let block = bindings.appendBasicBlock(context: context, function: llvmFunction.value, name: "L\(label)")
        if let block {
            labelBlocks[label] = block
        }
        return block
    }

    func buildThrownSlotCondition(
        from value: LLVMCAPIBindings.LLVMValueRef,
        name: String
    ) -> LLVMCAPIBindings.LLVMValueRef? {
        bindings.buildICmpNotEqual(builder, lhs: value, rhs: zeroValue, name: name)
    }

    func storeOutThrownIfNonNull(
        _ value: LLVMCAPIBindings.LLVMValueRef,
        suffix: String
    ) {
        guard let outThrownParameter,
              let pointerIsNonNull = bindings.buildICmpNotEqual(
                  builder,
                  lhs: outThrownParameter,
                  rhs: nullThrownPointer,
                  name: "out_nonnull_\(suffix)"
              ),
              let storeBlock = bindings.appendBasicBlock(
                  context: context,
                  function: llvmFunction.value,
                  name: "out_store_\(suffix)"
              ),
              let continueBlock = bindings.appendBasicBlock(
                  context: context,
                  function: llvmFunction.value,
                  name: "out_cont_\(suffix)"
              )
        else {
            return
        }

        _ = bindings.buildCondBr(
            builder,
            condition: pointerIsNonNull,
            thenBlock: storeBlock,
            elseBlock: continueBlock
        )

        bindings.positionBuilder(builder, at: storeBlock)
        _ = bindings.buildStore(builder, value: value, pointer: outThrownParameter)
        _ = bindings.buildBr(builder, destination: continueBlock)

        currentBlock = continueBlock
        bindings.positionBuilder(builder, at: continueBlock)
    }

    func emitFramePop(_ suffix: String) {
        guard let framePopFunction else {
            return
        }
        _ = bindings.buildCall(
            builder,
            functionType: framePopFunction.type,
            callee: framePopFunction.value,
            arguments: [],
            name: "frame_pop_\(suffix)"
        )
    }

    func emitBuiltinCall(
        calleeName: String,
        argumentValues: [LLVMCAPIBindings.LLVMValueRef],
        result: KIRExprID?,
        instructionIndex: Int
    ) -> Bool {
        let builtinResult = emitter.lowerBuiltinCall(
            calleeName: calleeName,
            argumentValues: argumentValues,
            state: builderState,
            instructionIndex: instructionIndex
        )
        guard builtinResult.handled else {
            return false
        }
        storeResult(result, builtinResult.value)
        return true
    }

    func setupFrame(function: KIRFunction) {
        let frameRegisterFunction = declareExternalFunction(
            named: "kk_register_frame_map",
            argumentCount: 2,
            appendThrownChannel: false
        )
        let framePushFunction = declareExternalFunction(
            named: "kk_push_frame",
            argumentCount: 2,
            appendThrownChannel: false
        )
        framePopFunction = declareExternalFunction(
            named: "kk_pop_frame",
            argumentCount: 0,
            appendThrownChannel: false
        )
        coroutineRegisterRootFunction = declareExternalFunction(
            named: "kk_register_coroutine_root",
            argumentCount: 1,
            appendThrownChannel: false
        )
        coroutineUnregisterRootFunction = declareExternalFunction(
            named: "kk_unregister_coroutine_root",
            argumentCount: 1,
            appendThrownChannel: false
        )
        functionIDValue = bindings.constInt(
            int64Type,
            value: UInt64(bitPattern: Int64(max(0, function.symbol.rawValue))),
            signExtend: false
        ) ?? zeroValue

        if let frameRegisterFunction {
            _ = bindings.buildCall(
                builder,
                functionType: frameRegisterFunction.type,
                callee: frameRegisterFunction.value,
                arguments: [functionIDValue, zeroValue],
                name: "frame_register"
            )
        }
        if let framePushFunction {
            _ = bindings.buildCall(
                builder,
                functionType: framePushFunction.type,
                callee: framePushFunction.value,
                arguments: [functionIDValue, zeroValue],
                name: "frame_push"
            )
        }
        storeOutThrownIfNonNull(zeroValue, suffix: "entry")
    }
}
