// swiftlint:disable file_length
import CompilerCore

extension NativeEmitter {

    /// Emits the body of one KIR function. The shared per-function emission
    /// state lives in `FunctionEmissionContext`; `emitBody` is the
    /// prologue-plus-dispatch driver and the extracted helpers live in the
    /// `NativeEmitter+*Emission*` sibling files.
    func emitFunctionBody(
        function: KIRFunction,
        llvmFunction: NativeEmitter.LLVMFunction,
        llvmModule: LLVMCAPIBindings.LLVMModuleRef,
        context: LLVMCAPIBindings.LLVMContextRef,
        int64Type: LLVMCAPIBindings.LLVMTypeRef,
        typeLowering: LLVMTypeLowering?,
        outThrownPointerType: LLVMCAPIBindings.LLVMTypeRef,
        internalFunctions: [SymbolID: NativeEmitter.LLVMFunction],
        internalSignatures: [SymbolID: (parameters: [TypeID], returnType: TypeID)],
        internalFunctionsByLookupKey: [NativeEmitter.FunctionLookupKey: [KIRFunction]],
        globalVariables: [SymbolID: LLVMCAPIBindings.LLVMValueRef] = [:],
        runtimeCallbackRawReturnSymbols: Set<SymbolID> = [],
        usesRuntimeCallbackRawABI: Bool = false,
        returnsRawStringRuntimeCallback: Bool = false,
        nameCounter: GeneratedNameCounter,
        diContext: DebugInfoContext? = nil
    ) throws {
        let emission = FunctionEmissionContext(
            emitter: self,
            function: function,
            llvmFunction: llvmFunction,
            llvmModule: llvmModule,
            context: context,
            int64Type: int64Type,
            typeLowering: typeLowering,
            outThrownPointerType: outThrownPointerType,
            internalFunctions: internalFunctions,
            internalSignatures: internalSignatures,
            internalFunctionsByLookupKey: internalFunctionsByLookupKey,
            globalVariables: globalVariables,
            runtimeCallbackRawReturnSymbols: runtimeCallbackRawReturnSymbols,
            usesRuntimeCallbackRawABI: usesRuntimeCallbackRawABI,
            returnsRawStringRuntimeCallback: returnsRawStringRuntimeCallback,
            nameCounter: nameCounter,
            diContext: diContext
        )
        try emission.emitBody()
    }

}

extension NativeEmitter.FunctionEmissionContext {
    // swiftlint:disable:next cyclomatic_complexity function_body_length
    func emitBody() throws {
        guard let builder = bindings.createBuilder(context: context) else {
            throw LLVMBackendError.nativeEmissionFailed("LLVMCreateBuilderInContext returned null")
        }
        self.builder = builder
        defer {
            if diContext != nil {
                bindings.clearCurrentDebugLocation(builder)
            }
            bindings.disposeBuilder(builder)
        }

        // When debug info is active and the function has a subprogram,
        // set the function-level debug location so the LLVM verifier accepts
        // all instructions emitted under this builder.
        if let diContext,
           let subprogram = diContext.subprograms[function.symbol],
           bindings.debugLocationAvailable
        {
            var funcLine: UInt32 = 0
            var funcCol: UInt32 = 0
            if let sourceRange = function.sourceRange, let sm = sourceManager {
                let lc = sm.lineColumn(of: sourceRange.start)
                funcLine = UInt32(lc.line)
                funcCol = UInt32(lc.column)
            }
            if let loc = bindings.createDebugLocation(
                context: context,
                line: funcLine,
                column: funcCol,
                scope: subprogram
            ) {
                bindings.setCurrentDebugLocation(builder, location: loc)
            }
        }

        guard let entryBlock = bindings.appendBasicBlock(context: context, function: llvmFunction.value, name: "entry") else {
            throw LLVMBackendError.nativeEmissionFailed("failed to create entry block")
        }

        // Dedicated builder for stack slots. Slots requested while a loop body is
        // being emitted must be allocated in the entry block, otherwise every
        // iteration allocates a fresh slot and long loops overflow the stack.
        let allocaBuilder = bindings.createBuilder(context: context)
        defer {
            if let allocaBuilder {
                bindings.disposeBuilder(allocaBuilder)
            }
        }

        for instruction in function.body {
            guard case let .label(id) = instruction else {
                continue
            }
            if labelBlocks[id] != nil {
                continue
            }
            if let block = bindings.appendBasicBlock(context: context, function: llvmFunction.value, name: nameCounter.nextName("L")) {
                labelBlocks[id] = block
            }
        }

        for (index, parameter) in function.params.enumerated() {
            guard let value = bindings.getParam(function: llvmFunction.value, index: UInt32(index)) else {
                continue
            }
            parameterValues[parameter.symbol] = value
        }

        // Position builder at the entry block before emitting parameter debug
        // info (alloca/store require a valid insert point).
        bindings.positionBuilder(builder, at: entryBlock)

        if let diContext,
           let subprogram = diContext.subprograms[function.symbol],
           let int64DIType = diContext.int64DIType,
           bindings.localVariableAvailable,
           bindings.debugLocationAvailable
        {
            var funcLine: UInt32 = 0
            if let sourceRange = function.sourceRange, let sm = sourceManager {
                funcLine = UInt32(sm.lineColumn(of: sourceRange.start).line)
            }
            let funcDIFile: LLVMCAPIBindings.LLVMMetadataRef? = {
                if let sourceRange = function.sourceRange {
                    return diContext.diFiles[sourceRange.start.file] ?? diContext.file
                }
                return diContext.file
            }()
            let emptyExpr = bindings.diBuilderCreateExpression(diContext.diBuilder)
            for (index, parameter) in function.params.enumerated() {
                guard let paramValue = parameterValues[parameter.symbol] else {
                    continue
                }
                let paramName = "arg\(index)"
                guard let diVar = bindings.diBuilderCreateParameterVariable(
                    diContext.diBuilder,
                    scope: subprogram,
                    name: paramName,
                    argNo: UInt32(index + 1),
                    file: funcDIFile,
                    lineNo: funcLine,
                    type: int64DIType
                ) else {
                    continue
                }
                // Create an alloca for the parameter so dbg.declare can reference it.
                let parameterType = usesRuntimeCallbackRawABI
                    ? int64Type
                    : loweredLLVMType(
                        for: parameter.type,
                        lowering: typeLowering,
                        defaultType: int64Type
                    )
                let paramAlloca = bindings.buildAlloca(builder, type: parameterType, name: "dbg_\(paramName)")
                if let paramAlloca {
                    _ = bindings.buildStore(builder, value: paramValue, pointer: paramAlloca)
                    if let debugLoc = bindings.createDebugLocation(
                        context: context, line: funcLine, column: 0, scope: subprogram
                    ) {
                        _ = bindings.diBuilderInsertDeclareAtEnd(
                            diContext.diBuilder,
                            storage: paramAlloca,
                            varInfo: diVar,
                            expr: emptyExpr,
                            debugLoc: debugLoc,
                            block: entryBlock
                        )
                    }
                }
            }
        }
        outThrownParameter = bindings.getParam(
            function: llvmFunction.value,
            index: UInt32(function.params.count)
        )

        guard let zeroValue = bindings.constInt(int64Type, value: 0) else {
            throw LLVMBackendError.nativeEmissionFailed("LLVMConstInt returned null")
        }
        self.zeroValue = zeroValue
        zeroReturnValue = if returnsRawStringRuntimeCallback {
            zeroValue
        } else {
            zeroLLVMValue(
                for: function.returnType,
                lowering: typeLowering,
                int64Type: int64Type,
                context: context
            ) ?? zeroValue
        }
        guard let undefThrownPointer = bindings.getUndef(type: outThrownPointerType) else {
            throw LLVMBackendError.nativeEmissionFailed("LLVMGetUndef for outThrown pointer returned null")
        }
        nullThrownPointer = bindings.constPointerNull(outThrownPointerType) ?? undefThrownPointer

        bindings.positionBuilder(builder, at: entryBlock)
        currentBlock = entryBlock
        builderState = NativeEmitter.EmissionBuilderState(
            builder: builder,
            int64Type: int64Type,
            zeroValue: zeroValue,
            context: context,
            module: llvmModule,
            typeLowering: typeLowering,
            entryBlock: entryBlock,
            allocaBuilder: allocaBuilder
        )


        var assignmentTargetCounts: [Int32: Int] = [:]
        for instruction in function.body {
            for target in assignmentTargets(for: instruction) {
                assignmentTargetCounts[target.rawValue, default: 0] += 1
            }
        }

        // KIR temporaries are not strict SSA values: inline expansion and
        // throw-aware control flow can route multiple predecessor blocks to a
        // later use even when the temporary has only one syntactic assignment.
        // Keeping such a result as an LLVM SSA value produces invalid IR when
        // its defining block does not dominate the merge block. Materialize
        // assignment targets in entry-block slots; optimized pipelines promote
        // the safe cases back to SSA with mem2reg.
        let shouldSpillID = Set(assignmentTargetCounts.keys)

        for instruction in function.body {
            for target in assignmentTargets(for: instruction) where shouldSpillID.contains(target.rawValue) {
                if copyTargetAllocas[target.rawValue] == nil,
                   let alloca = bindings.buildAlloca(
                       builder,
                       type: loweredLLVMType(
                           for: module.arena.exprType(target),
                           lowering: typeLowering,
                           defaultType: int64Type
                       ),
                       name: nameCounter.nextName("copy_slot_")
                   )
                {
                    let initialValue = zeroLLVMValue(
                        for: module.arena.exprType(target),
                        lowering: typeLowering,
                        int64Type: int64Type,
                        context: context
                    ) ?? zeroValue
                    _ = bindings.buildStore(builder, value: initialValue, pointer: alloca)
                    copyTargetAllocas[target.rawValue] = alloca
                }
            }
        }

        stringAggregateBridge = NativeEmitter.StringAggregateBridgeContext(
            emitter: emitter,
            state: builderState,
            typeSystem: typeSystem,
            outParameterPointerType: outThrownPointerType,
            declareTypedExternalFunction: { [weak self] name, parameterTypes, returnType in
                self?.declareExternalFunction(
                    named: name,
                    parameterTypes: parameterTypes,
                    returnType: returnType
                )
            }
        )

        storeOutThrownIfNonNull(zeroValue, suffix: "entry")
        emitStackOverflowGuard()
        try prepareGCRootFrame(allocaBuilder: allocaBuilder)

        if usesRuntimeCallbackRawABI {
            for (index, parameter) in function.params.enumerated() where stringAggregateBridge.isStringAggregateType(parameter.type) {
                guard let rawValue = parameterValues[parameter.symbol] else {
                    continue
                }
                parameterValues[parameter.symbol] = stringAggregateBridge.bridgeRuntimeRawToStringAggregate(
                    rawValue,
                    suffix: "runtime_callback_param_\(index)"
                ) ?? rawValue
            }
        }

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
        emitGCShadowPush()

        for (instructionIndex, instruction) in function.body.enumerated() {
            // Lowering may leave dead expression tails after an unconditional
            // terminator (for example, a synthesized Unit return after rethrow).
            // Only a label can start a new reachable insertion block; emitting any
            // other instruction here would place LLVM instructions after the
            // current block's terminator.
            if bindings.hasTerminator(currentBlock) {
                guard case .label = instruction else {
                    continue
                }
            }

            if let diContext,
               let subprogram = diContext.subprograms[function.symbol],
               bindings.debugLocationAvailable
            {
                var instrLine: UInt32 = 0
                var instrCol: UInt32 = 0
                // Only use per-instruction locations
                // when the parallel array is in sync with body (same count).
                if function.instructionLocations.count == function.body.count,
                   instructionIndex < function.instructionLocations.count,
                   let instrRange = function.instructionLocations[instructionIndex],
                   let sm = sourceManager
                {
                    let lc = sm.lineColumn(of: instrRange.start)
                    instrLine = UInt32(lc.line)
                    instrCol = UInt32(lc.column)
                } else if let sourceRange = function.sourceRange, let sm = sourceManager {
                    let lc = sm.lineColumn(of: sourceRange.start)
                    instrLine = UInt32(lc.line)
                    instrCol = UInt32(lc.column)
                }
                if instrLine > 0,
                   let loc = bindings.createDebugLocation(
                       context: context,
                       line: instrLine,
                       column: instrCol,
                       scope: subprogram
                   )
                {
                    bindings.setCurrentDebugLocation(builder, location: loc)
                }
            }

            switch instruction {
            case .nop, .beginBlock, .endBlock, .beginFinallyGuard, .endFinallyGuard,
                 .beginNonLocalReturnScope, .endNonLocalReturnScope, .beginFinallyCleanup, .endFinallyCleanup:
                continue

            case let .label(id):
                guard let destination = blockForLabel(id) else {
                    continue
                }
                if !bindings.hasTerminator(currentBlock) {
                    _ = bindings.buildBr(builder, destination: destination)
                }
                currentBlock = destination
                bindings.positionBuilder(builder, at: destination)

            case let .jump(target):
                guard !bindings.hasTerminator(currentBlock),
                      let destination = blockForLabel(target)
                else {
                    continue
                }
                _ = bindings.buildBr(builder, destination: destination)

            case let .jumpIfEqual(lhs, rhs, target):
                guard !bindings.hasTerminator(currentBlock),
                      let thenBlock = blockForLabel(target),
                      let continueBlock = bindings.appendBasicBlock(
                          context: context,
                          function: llvmFunction.value,
                          name: "if_cont_\(instructionIndex)"
                      )
                else {
                    continue
                }
                let (lhsValue, rhsValue) = rawComparableValues(lhs: lhs, rhs: rhs)
                let condition = bindings.buildICmpEqual(
                    builder,
                    lhs: lhsValue,
                    rhs: rhsValue,
                    name: "if_cmp_\(instructionIndex)"
                )
                _ = bindings.buildCondBr(
                    builder,
                    condition: condition,
                    thenBlock: thenBlock,
                    elseBlock: continueBlock
                )
                currentBlock = continueBlock
                bindings.positionBuilder(builder, at: continueBlock)

            case let .constValue(result, value):
                // Constants can emit runtime calls (for example, String
                // literals), so they must respect block termination too.
                guard !bindings.hasTerminator(currentBlock) else {
                    continue
                }
                let constLLVMValue = valueForConstant(value, expressionRawID: result.rawValue)
                storeResult(result, constLLVMValue)

                if let diContext,
                   let subprogram = diContext.subprograms[function.symbol],
                   let int64DIType = diContext.int64DIType,
                   bindings.localVariableAvailable,
                   bindings.debugLocationAvailable,
                   case let .symbolRef(localSymbol) = value,
                   !parameterValues.keys.contains(localSymbol)
                {
                    let varName = nameCounter.nextName("local_")
                    var varLine: UInt32 = 0
                    if function.instructionLocations.count == function.body.count,
                       instructionIndex < function.instructionLocations.count,
                       let instrRange = function.instructionLocations[instructionIndex],
                       let srcMgr = sourceManager
                    {
                        varLine = UInt32(srcMgr.lineColumn(of: instrRange.start).line)
                    } else if let sourceRange = function.sourceRange, let srcMgr = sourceManager {
                        varLine = UInt32(srcMgr.lineColumn(of: sourceRange.start).line)
                    }
                    let varDIFile: LLVMCAPIBindings.LLVMMetadataRef? = {
                        if function.instructionLocations.count == function.body.count,
                           instructionIndex < function.instructionLocations.count,
                           let instrRange = function.instructionLocations[instructionIndex]
                        {
                            return diContext.diFiles[instrRange.start.file] ?? diContext.file
                        }
                        return diContext.file
                    }()
                    if let diVar = bindings.diBuilderCreateAutoVariable(
                        diContext.diBuilder,
                        scope: subprogram,
                        name: varName,
                        file: varDIFile,
                        lineNo: varLine,
                        type: int64DIType
                    ) {
                        let emptyExpr = bindings.diBuilderCreateExpression(diContext.diBuilder)
                        // Use the copy-target alloca if one exists (the copy instruction
                        // will store the real value there), otherwise fall back to a
                        // dedicated debug alloca with the current (possibly zero) value.
                        let debugStorageType = loweredLLVMType(
                            for: module.arena.exprType(result),
                            lowering: typeLowering,
                            defaultType: int64Type
                        )
                        let localAlloca = copyTargetAllocas[result.rawValue]
                            ?? stringAggregateBridge.buildEntrySlot(name: "dbg_\(varName)", type: debugStorageType)
                        if let localAlloca {
                            if copyTargetAllocas[result.rawValue] == nil {
                                _ = bindings.buildStore(builder, value: constLLVMValue, pointer: localAlloca)
                            }
                            if let debugLoc = bindings.createDebugLocation(
                                context: context, line: varLine, column: 0, scope: subprogram
                            ) {
                                _ = bindings.diBuilderInsertDeclareAtEnd(
                                    diContext.diBuilder,
                                    storage: localAlloca,
                                    varInfo: diVar,
                                    expr: emptyExpr,
                                    debugLoc: debugLoc,
                                    block: currentBlock
                                )
                            }
                        }
                    }
                }

            case let .binary(op, lhs, rhs, result):
                guard !bindings.hasTerminator(currentBlock) else {
                    continue
                }
                let lhsValue = resolveValue(lhs)
                let rhsValue = resolveValue(rhs)
                let lowered: LLVMCAPIBindings.LLVMValueRef? = switch op {
                case .add:
                    bindings.buildAdd(builder, lhs: lhsValue, rhs: rhsValue, name: "bin_add_\(instructionIndex)")
                case .subtract:
                    bindings.buildSub(builder, lhs: lhsValue, rhs: rhsValue, name: "bin_sub_\(instructionIndex)")
                case .multiply:
                    bindings.buildMul(builder, lhs: lhsValue, rhs: rhsValue, name: "bin_mul_\(instructionIndex)")
                case .divide:
                    bindings.buildSDiv(builder, lhs: lhsValue, rhs: rhsValue, name: "bin_div_\(instructionIndex)")
                case .modulo:
                    if let quotient = bindings.buildSDiv(builder, lhs: lhsValue, rhs: rhsValue, name: "bin_mod_q_\(instructionIndex)"),
                       let product = bindings.buildMul(builder, lhs: quotient, rhs: rhsValue, name: "bin_mod_p_\(instructionIndex)")
                    {
                        bindings.buildSub(builder, lhs: lhsValue, rhs: product, name: "bin_mod_\(instructionIndex)")
                    } else {
                        nil
                    }
                case .equal:
                    if let compared = bindings.buildICmpEqual(
                        builder,
                        lhs: lhsValue,
                        rhs: rhsValue,
                        name: "bin_eq_\(instructionIndex)"
                    ) {
                        bindings.buildZExt(builder, value: compared, type: int64Type, name: "bin_eq64_\(instructionIndex)")
                    } else {
                        nil
                    }
                case .notEqual, .lessThan, .lessOrEqual, .greaterThan, .greaterOrEqual:
                    nil
                case .logicalAnd, .logicalOr:
                    nil
                }
                storeResult(result, lowered)

            case let .unary(_, operand, result):
                guard !bindings.hasTerminator(currentBlock) else {
                    continue
                }
                storeResult(result, resolveValue(operand))

            case let .nullAssert(operand, result):
                guard !bindings.hasTerminator(currentBlock) else {
                    continue
                }
                let operandValue = resolveValue(operand)
                if let notNullFunc = declareExternalFunction(
                    named: "kk_op_notnull",
                    argumentCount: 1,
                    appendThrownChannel: true
                ) {
                    let thrownSlot = stringAggregateBridge.buildEntrySlot(name: "notnull_thrown_\(instructionIndex)")
                    if let thrownSlot {
                        _ = bindings.buildStore(builder, value: zeroValue, pointer: thrownSlot)
                        let callValue = bindings.buildCall(
                            builder,
                            functionType: notNullFunc.type,
                            callee: notNullFunc.value,
                            arguments: [operandValue, thrownSlot],
                            name: "notnull_\(instructionIndex)"
                        )
                        storeResult(result, callValue)
                        if let thrownValue = bindings.buildLoad(
                            builder,
                            type: int64Type,
                            pointer: thrownSlot,
                            name: "notnull_thrown_val_\(instructionIndex)"
                        ),
                            let hasThrown = buildThrownSlotCondition(
                                from: thrownValue,
                                name: "notnull_has_thrown_\(instructionIndex)"
                            ),
                            let thrownBlock = bindings.appendBasicBlock(
                                context: context,
                                function: llvmFunction.value,
                                name: "notnull_thrown_\(instructionIndex)"
                            ),
                            let continueBlock = bindings.appendBasicBlock(
                                context: context,
                                function: llvmFunction.value,
                                name: "notnull_cont_\(instructionIndex)"
                            )
                        {
                            _ = bindings.buildCondBr(
                                builder,
                                condition: hasThrown,
                                thenBlock: thrownBlock,
                                elseBlock: continueBlock
                            )
                            bindings.positionBuilder(builder, at: thrownBlock)
                            storeOutThrownIfNonNull(thrownValue, suffix: "notnull_throw_\(instructionIndex)")
                            emitGCFrameLeave(returning: thrownValue)
                            emitGCShadowPop(thrown: thrownValue)
                            _ = bindings.buildRet(builder, value: zeroReturnValue)
                            currentBlock = continueBlock
                            bindings.positionBuilder(builder, at: continueBlock)
                        }
                    } else {
                        storeResult(result, operandValue)
                    }
                } else {
                    storeResult(result, operandValue)
                }

            case let .call(symbol, callee, arguments, result, usesThrownChannel, thrownResult, isSuperCall, qualifiedSuperType):
                emitDirectCall(
                    symbol: symbol,
                    callee: callee,
                    arguments: arguments,
                    result: result,
                    usesThrownChannel: usesThrownChannel,
                    thrownResult: thrownResult,
                    isSuperCall: isSuperCall,
                    qualifiedSuperType: qualifiedSuperType,
                    instructionIndex: instructionIndex
                )

            case let .virtualCall(symbol, callee, receiver, arguments, result, usesThrownChannel, thrownResult, dispatch):
                emitVirtualCall(
                    symbol: symbol,
                    callee: callee,
                    receiver: receiver,
                    arguments: arguments,
                    result: result,
                    usesThrownChannel: usesThrownChannel,
                    thrownResult: thrownResult,
                    dispatch: dispatch,
                    instructionIndex: instructionIndex
                )

            case let .jumpIfNotNull(value, target):
                guard !bindings.hasTerminator(currentBlock) else {
                    continue
                }
                let resolved = resolveValue(value)
                let valueType = module.arena.exprType(value)
                if let valueType,
                   let typeLowering,
                   let typeSystem,
                   case .stringStruct = typeSystem.kind(of: valueType),
                   let dataPointer = bindings.buildExtractValue(
                       builder,
                       aggregate: resolved,
                       index: 0,
                       name: "jnn_string_data_\(instructionIndex)"
                   ),
                   let nullPointer = bindings.constPointerNull(typeLowering.dataPointerType),
                   let condition = bindings.buildICmpNotEqual(
                       builder,
                       lhs: dataPointer,
                       rhs: nullPointer,
                       name: "jnn_string_nonnull_\(instructionIndex)"
                   ),
                   let targetBlock = blockForLabel(target),
                   let fallthroughBlock = bindings.appendBasicBlock(
                       context: context,
                       function: llvmFunction.value,
                       name: "jnn_cont_\(instructionIndex)"
                   )
                {
                    _ = bindings.buildCondBr(builder, condition: condition, thenBlock: targetBlock, elseBlock: fallthroughBlock)
                    currentBlock = fallthroughBlock
                    bindings.positionBuilder(builder, at: fallthroughBlock)
                    continue
                }
                let nullSentinel = bindings.constInt(
                    int64Type,
                    value: UInt64(bitPattern: Int64.min),
                    signExtend: true
                ) ?? zeroValue
                let isNonZero = bindings.buildICmpNotEqual(
                    builder,
                    lhs: resolved,
                    rhs: zeroValue,
                    name: "jnn_nonzero_\(instructionIndex)"
                )
                let isNotSentinel = bindings.buildICmpNotEqual(
                    builder,
                    lhs: resolved,
                    rhs: nullSentinel,
                    name: "jnn_nonsentinel_\(instructionIndex)"
                )
                let condition: LLVMCAPIBindings.LLVMValueRef? = if nullableRawScalarPreservesZero(valueType) {
                    isNotSentinel
                } else if let isNonZero,
                          let isNotSentinel
                {
                    bindings.buildAnd(
                        builder,
                        lhs: isNonZero,
                        rhs: isNotSentinel,
                        name: "jnn_cond_\(instructionIndex)"
                    )
                } else {
                    nil
                }
                if let condition,
                   let targetBlock = blockForLabel(target),
                   let fallthroughBlock = bindings.appendBasicBlock(
                       context: context,
                       function: llvmFunction.value,
                       name: "jnn_cont_\(instructionIndex)"
                   )
                {
                    _ = bindings.buildCondBr(builder, condition: condition, thenBlock: targetBlock, elseBlock: fallthroughBlock)
                    currentBlock = fallthroughBlock
                    bindings.positionBuilder(builder, at: fallthroughBlock)
                }

            case let .copy(from, to):
                guard !bindings.hasTerminator(currentBlock) else {
                    continue
                }
                var copySource = resolveValue(from)
                let fromType = module.arena.exprType(from)
                let toType = module.arena.exprType(to)
                // If the copy target is a global symbolRef, store to the
                // LLVM global variable so the write persists across reads.
                if let targetExpr = module.arena.expr(to),
                   case let .symbolRef(targetSymbol) = targetExpr,
                   let globalPtr = globalVariables[targetSymbol]
                {
                    if stringAggregateBridge.isStringAggregateType(fromType) {
                        copySource = stringAggregateBridge.bridgeStringAggregateToRuntimeRaw(
                            copySource,
                            suffix: "copy_global_\(instructionIndex)"
                        ) ?? copySource
                    }
                    emitGCGlobalStore(symbol: targetSymbol, pointer: globalPtr, value: copySource)
                } else {
                    if stringAggregateBridge.isStringAggregateType(fromType), !stringAggregateBridge.isStringAggregateType(toType) {
                        copySource = stringAggregateBridge.bridgeStringAggregateToRuntimeRaw(
                            copySource,
                            suffix: "copy_\(instructionIndex)"
                        ) ?? copySource
                    } else if !stringAggregateBridge.isStringAggregateType(fromType), stringAggregateBridge.isStringAggregateType(toType) {
                        copySource = stringAggregateBridge.bridgeRuntimeRawToStringAggregate(
                            copySource,
                            suffix: "copy_\(instructionIndex)"
                        ) ?? copySource
                    }
                    if let alloca = copyTargetAllocas[to.rawValue] {
                        _ = bindings.buildStore(builder, value: copySource, pointer: alloca)
                        emitGCShadowSet(to, value: copySource)
                        storeGCRoot(for: to, value: copySource)
                    } else {
                        storeResult(to, copySource)
                    }
                }

            case let .storeGlobal(value, symbol):
                guard !bindings.hasTerminator(currentBlock) else {
                    continue
                }
                var resolved = resolveValue(value)
                if stringAggregateBridge.isStringAggregateType(module.arena.exprType(value)) {
                    resolved = stringAggregateBridge.bridgeStringAggregateToRuntimeRaw(
                        resolved,
                        suffix: "store_global_\(instructionIndex)"
                    ) ?? resolved
                }
                if let globalPtr = globalVariables[symbol] {
                    registerGCRootForGlobal(symbol, slot: globalPtr)
                    emitGCGlobalStore(symbol: symbol, pointer: globalPtr, value: resolved)
                }

            case let .loadGlobal(result, symbol):
                guard !bindings.hasTerminator(currentBlock) else {
                    continue
                }
                if let globalPtr = globalVariables[symbol] {
                    registerGCRootForGlobal(symbol, slot: globalPtr)
                    if let loaded = bindings.buildLoad(
                        builder, type: int64Type, pointer: globalPtr,
                        name: nameCounter.nextName("load_global_")
                    ) {
                        let loadedValue = if stringAggregateBridge.isStringAggregateType(module.arena.exprType(result)) {
                            stringAggregateBridge.bridgeRuntimeRawToStringAggregate(
                                loaded,
                                suffix: "load_global_\(instructionIndex)"
                            ) ?? loaded
                        } else {
                            loaded
                        }
                        storeResult(result, loadedValue)
                    }
                } else {
                    let missingValue = if stringAggregateBridge.isStringAggregateType(module.arena.exprType(result)) {
                        stringAggregateBridge.bridgeRuntimeRawToStringAggregate(
                            zeroValue,
                            suffix: "load_global_missing_\(instructionIndex)"
                        ) ?? zeroValue
                    } else {
                        zeroValue
                    }
                    storeResult(result, missingValue)
                }

            case let .rethrow(value):
                guard !bindings.hasTerminator(currentBlock) else {
                    continue
                }
                let resolved = resolveValue(value)
                storeOutThrownIfNonNull(resolved, suffix: "rethrow_\(instructionIndex)")
                emitGCFrameLeave(returning: resolved)
                emitGCShadowPop(thrown: resolved)
                _ = bindings.buildRet(builder, value: zeroReturnValue)

            case let .returnIfEqual(lhs, rhs):
                guard !bindings.hasTerminator(currentBlock),
                      let trueBlock = bindings.appendBasicBlock(
                          context: context,
                          function: llvmFunction.value,
                          name: "ret_if_true_\(instructionIndex)"
                      ),
                      let falseBlock = bindings.appendBasicBlock(
                          context: context,
                          function: llvmFunction.value,
                          name: "ret_if_false_\(instructionIndex)"
                      )
                else {
                    continue
                }

                let (lhsValue, rhsValue) = rawComparableValues(lhs: lhs, rhs: rhs)
                let condition = bindings.buildICmpEqual(builder, lhs: lhsValue, rhs: rhsValue, name: "ret_if_cmp_\(instructionIndex)")
                _ = bindings.buildCondBr(builder, condition: condition, thenBlock: trueBlock, elseBlock: falseBlock)

                bindings.positionBuilder(builder, at: trueBlock)
                emitGCFrameLeave(returning: lhsValue)
                emitGCShadowPop(result: lhsValue)
                _ = bindings.buildRet(builder, value: lhsValue)

                currentBlock = falseBlock
                bindings.positionBuilder(builder, at: falseBlock)

            case .returnUnit:
                guard !bindings.hasTerminator(currentBlock) else {
                    continue
                }
                emitGCFrameLeave(returning: nil)
                emitGCShadowPop()
                _ = bindings.buildRet(builder, value: zeroReturnValue)

            case let .returnValue(value):
                guard !bindings.hasTerminator(currentBlock) else {
                    continue
                }
                let resolvedReturnValue = resolveValue(value)
                let returnValue: LLVMCAPIBindings.LLVMValueRef = if returnsRawStringRuntimeCallback {
                    stringAggregateBridge.bridgeStringAggregateToRuntimeRaw(
                        resolvedReturnValue,
                        suffix: "return_\(instructionIndex)"
                    ) ?? resolvedReturnValue
                } else {
                    coerceStringValueForType(
                        resolvedReturnValue,
                        from: module.arena.exprType(value),
                        to: function.returnType,
                        suffix: "return_\(instructionIndex)"
                    )
                }
                emitGCFrameLeave(returning: returnValue)
                emitGCShadowPop(result: returnValue)
                _ = bindings.buildRet(builder, value: returnValue)

            case .resumeNonLocalReturn:
                assertionFailure("resumeNonLocalReturn reached codegen -- InlineLoweringPass should have converted it")
                continue

            case let .nonLocalReturn(value, _):
                // Non-local returns should have been lowered by InlineLoweringPass.
                // If one reaches codegen, it indicates a lowering bug. Emit a
                // trap in debug builds; in release builds fall back to a return
                // to avoid crashing the compiler, but the output is incorrect.
                assertionFailure("nonLocalReturn reached codegen -- InlineLoweringPass should have converted it")
                guard !bindings.hasTerminator(currentBlock) else {
                    continue
                }
                if let value {
                    let resolvedReturnValue = resolveValue(value)
                    let returnValue: LLVMCAPIBindings.LLVMValueRef = if returnsRawStringRuntimeCallback {
                        stringAggregateBridge.bridgeStringAggregateToRuntimeRaw(
                            resolvedReturnValue,
                            suffix: "nonlocal_return_\(instructionIndex)"
                        ) ?? resolvedReturnValue
                    } else {
                        coerceStringValueForType(
                            resolvedReturnValue,
                            from: module.arena.exprType(value),
                            to: function.returnType,
                            suffix: "nonlocal_return_\(instructionIndex)"
                        )
                    }
                    emitGCFrameLeave(returning: returnValue)
                    emitGCShadowPop(result: returnValue)
                    _ = bindings.buildRet(builder, value: returnValue)
                } else {
                    emitGCFrameLeave(returning: nil)
                    emitGCShadowPop()
                    _ = bindings.buildRet(builder, value: zeroReturnValue)
                }
            }
        }

        if !bindings.hasTerminator(currentBlock) {
            emitGCFrameLeave(returning: nil)
            emitGCShadowPop()
            _ = bindings.buildRet(builder, value: zeroReturnValue)
        }
    }

}
