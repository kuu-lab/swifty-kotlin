// swiftlint:disable cyclomatic_complexity function_body_length

extension NativeEmitter.FunctionEmissionState {

    func emitInstruction(
        _ instruction: KIRInstruction,
        instructionIndex: Int,
        function: KIRFunction,
        diContext: NativeEmitter.DebugInfoContext?
    ) {
        updateDebugLocation(instructionIndex: instructionIndex, function: function, diContext: diContext)

        switch instruction {
        case .nop, .beginBlock, .endBlock, .beginFinallyGuard, .endFinallyGuard:
            return

        case let .label(id):
            guard let destination = blockForLabel(id) else {
                return
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
                return
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
                return
            }
            let condition = bindings.buildICmpEqual(
                builder,
                lhs: resolveValue(lhs),
                rhs: resolveValue(rhs),
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
            let constLLVMValue = valueForConstant(value, expressionRawID: result.rawValue)
            storeResult(result, constLLVMValue)
            emitConstValueDebugInfo(result: result, value: value, constLLVMValue: constLLVMValue, instructionIndex: instructionIndex, function: function, diContext: diContext)

        case let .binary(op, lhs, rhs, result):
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
            storeResult(result, resolveValue(operand))

        case let .nullAssert(operand, result):
            emitNullAssert(operand: operand, result: result, instructionIndex: instructionIndex)

        case let .call(symbol, callee, arguments, result, usesThrownChannel, thrownResult, isSuperCall, qualifiedSuperType):
            emitCallInstruction(
                symbol: symbol,
                callee: callee,
                arguments: arguments,
                result: result,
                canThrow: usesThrownChannel,
                thrownResult: thrownResult,
                isSuperCall: isSuperCall,
                qualifiedSuperType: qualifiedSuperType,
                instructionIndex: instructionIndex
            )

        case let .virtualCall(symbol, callee, receiver, arguments, result, usesThrownChannel, thrownResult, dispatch):
            emitVirtualCallInstruction(
                symbol: symbol,
                callee: callee,
                receiver: receiver,
                arguments: arguments,
                result: result,
                canThrow: usesThrownChannel,
                thrownResult: thrownResult,
                dispatch: dispatch,
                instructionIndex: instructionIndex
            )

        case let .jumpIfNotNull(value, target):
            guard !bindings.hasTerminator(currentBlock) else {
                return
            }
            let resolved = resolveValue(value)
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
            if let isNonZero,
               let isNotSentinel,
               let condition = bindings.buildAnd(
                   builder,
                   lhs: isNonZero,
                   rhs: isNotSentinel,
                   name: "jnn_cond_\(instructionIndex)"
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
            }

        case let .copy(from, to):
            guard !bindings.hasTerminator(currentBlock) else {
                return
            }
            let copySource = resolveValue(from)
            if let targetExpr = module.arena.expr(to),
               case let .symbolRef(targetSymbol) = targetExpr,
               let globalPtr = globalVariables[targetSymbol]
            {
                _ = bindings.buildStore(builder, value: copySource, pointer: globalPtr)
            } else if let alloca = copyTargetAllocas[to.rawValue] {
                _ = bindings.buildStore(builder, value: copySource, pointer: alloca)
            } else {
                storeResult(to, copySource)
            }

        case let .storeGlobal(value, symbol):
            guard !bindings.hasTerminator(currentBlock) else {
                return
            }
            let resolved = resolveValue(value)
            if let globalPtr = globalVariables[symbol] {
                _ = bindings.buildStore(builder, value: resolved, pointer: globalPtr)
            }

        case let .loadGlobal(result, symbol):
            guard !bindings.hasTerminator(currentBlock) else {
                return
            }
            if let globalPtr = globalVariables[symbol] {
                if let loaded = bindings.buildLoad(
                    builder, type: int64Type, pointer: globalPtr,
                    name: "load_global_\(symbol.rawValue)"
                ) {
                    storeResult(result, loaded)
                }
            } else {
                storeResult(result, zeroValue)
            }

        case let .rethrow(value):
            guard !bindings.hasTerminator(currentBlock) else {
                return
            }
            let resolved = resolveValue(value)
            storeOutThrownIfNonNull(resolved, suffix: "rethrow_\(instructionIndex)")
            emitFramePop("rethrow_\(instructionIndex)")
            _ = bindings.buildRet(builder, value: zeroValue)

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
                return
            }

            let lhsValue = resolveValue(lhs)
            let rhsValue = resolveValue(rhs)
            let condition = bindings.buildICmpEqual(builder, lhs: lhsValue, rhs: rhsValue, name: "ret_if_cmp_\(instructionIndex)")
            _ = bindings.buildCondBr(builder, condition: condition, thenBlock: trueBlock, elseBlock: falseBlock)

            bindings.positionBuilder(builder, at: trueBlock)
            emitFramePop("ret_if_\(instructionIndex)")
            _ = bindings.buildRet(builder, value: lhsValue)

            currentBlock = falseBlock
            bindings.positionBuilder(builder, at: falseBlock)

        case .returnUnit:
            guard !bindings.hasTerminator(currentBlock) else {
                return
            }
            emitFramePop("ret_unit_\(instructionIndex)")
            _ = bindings.buildRet(builder, value: zeroValue)

        case let .returnValue(value):
            guard !bindings.hasTerminator(currentBlock) else {
                return
            }
            emitFramePop("ret_val_\(instructionIndex)")
            _ = bindings.buildRet(builder, value: resolveValue(value))

        case let .nonLocalReturn(value):
            assertionFailure("nonLocalReturn reached codegen -- InlineLoweringPass should have converted it")
            guard !bindings.hasTerminator(currentBlock) else {
                return
            }
            emitFramePop("ret_nonlocal_\(instructionIndex)")
            if let value {
                _ = bindings.buildRet(builder, value: resolveValue(value))
            } else {
                _ = bindings.buildRet(builder, value: zeroValue)
            }
        }
    }

    private func updateDebugLocation(
        instructionIndex: Int,
        function: KIRFunction,
        diContext: NativeEmitter.DebugInfoContext?
    ) {
        guard let diContext,
              let subprogram = diContext.subprograms[function.symbol],
              bindings.debugLocationAvailable
        else {
            return
        }
        var instrLine: UInt32 = 0
        var instrCol: UInt32 = 0
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

    private func emitConstValueDebugInfo(
        result: KIRExprID,
        value: KIRExprKind,
        constLLVMValue: LLVMCAPIBindings.LLVMValueRef,
        instructionIndex: Int,
        function: KIRFunction,
        diContext: NativeEmitter.DebugInfoContext?
    ) {
        guard let diContext,
              let subprogram = diContext.subprograms[function.symbol],
              let int64DIType = diContext.int64DIType,
              bindings.localVariableAvailable,
              bindings.debugLocationAvailable,
              case let .symbolRef(localSymbol) = value,
              !parameterValues.keys.contains(localSymbol)
        else {
            return
        }
        let varName = "local_\(localSymbol.rawValue)"
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
            let localAlloca = copyTargetAllocas[result.rawValue]
                ?? bindings.buildAlloca(builder, type: int64Type, name: "dbg_\(varName)")
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

    private func emitNullAssert(operand: KIRExprID, result: KIRExprID, instructionIndex: Int) {
        let operandValue = resolveValue(operand)
        if let notNullFunc = declareExternalFunction(
            named: "kk_op_notnull",
            argumentCount: 1,
            appendThrownChannel: true
        ) {
            let thrownSlot = bindings.buildAlloca(
                builder,
                type: int64Type,
                name: "notnull_thrown_\(instructionIndex)"
            )
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
                    emitFramePop("notnull_throw_\(instructionIndex)")
                    _ = bindings.buildRet(builder, value: zeroValue)
                    currentBlock = continueBlock
                    bindings.positionBuilder(builder, at: continueBlock)
                }
            } else {
                storeResult(result, operandValue)
            }
        } else {
            storeResult(result, operandValue)
        }
    }
}

// swiftlint:enable cyclomatic_complexity function_body_length
