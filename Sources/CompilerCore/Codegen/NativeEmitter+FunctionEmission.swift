extension NativeEmitter {
    // swiftlint:disable:next function_body_length
    func emitFunctionBody(
        function: KIRFunction,
        llvmFunction: LLVMFunction,
        llvmModule: LLVMCAPIBindings.LLVMModuleRef,
        context: LLVMCAPIBindings.LLVMContextRef,
        int64Type: LLVMCAPIBindings.LLVMTypeRef,
        outThrownPointerType: LLVMCAPIBindings.LLVMTypeRef,
        internalFunctions: [SymbolID: LLVMFunction],
        globalVariables: [SymbolID: LLVMCAPIBindings.LLVMValueRef] = [:],
        diContext: DebugInfoContext? = nil
    ) throws {
        guard let builder = bindings.createBuilder(context: context) else {
            throw LLVMBackendError.nativeEmissionFailed("LLVMCreateBuilderInContext returned null")
        }
        defer {
            if diContext != nil {
                bindings.clearCurrentDebugLocation(builder)
            }
            bindings.disposeBuilder(builder)
        }

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

        var labelBlocks: [Int32: LLVMCAPIBindings.LLVMBasicBlockRef] = [:]
        for instruction in function.body {
            guard case let .label(id) = instruction else {
                continue
            }
            if labelBlocks[id] != nil {
                continue
            }
            if let block = bindings.appendBasicBlock(context: context, function: llvmFunction.value, name: "L\(id)") {
                labelBlocks[id] = block
            }
        }

        var parameterValues: [SymbolID: LLVMCAPIBindings.LLVMValueRef] = [:]
        for (index, parameter) in function.params.enumerated() {
            guard let value = bindings.getParam(function: llvmFunction.value, index: UInt32(index)) else {
                continue
            }
            parameterValues[parameter.symbol] = value
        }

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
                let paramAlloca = bindings.buildAlloca(builder, type: int64Type, name: "dbg_\(paramName)")
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
        let outThrownParameter = bindings.getParam(
            function: llvmFunction.value,
            index: UInt32(function.params.count)
        )

        guard let zeroValue = bindings.constInt(int64Type, value: 0) else {
            throw LLVMBackendError.nativeEmissionFailed("LLVMConstInt returned null")
        }
        guard let undefThrownPointer = bindings.getUndef(type: outThrownPointerType) else {
            throw LLVMBackendError.nativeEmissionFailed("LLVMGetUndef for outThrown pointer returned null")
        }
        let nullThrownPointer = bindings.constPointerNull(outThrownPointerType) ?? undefThrownPointer

        bindings.positionBuilder(builder, at: entryBlock)
        let maxKIRArgCount = Self.maxKIRArgumentCountByExternalCallee(
            body: function.body,
            interner: interner
        )
        let builderState = EmissionBuilderState(builder: builder, int64Type: int64Type, zeroValue: zeroValue, context: context, module: llvmModule)

        var assignmentTargetCounts: [Int32: Int] = [:]
        for instruction in function.body {
            for target in FunctionEmissionState.assignmentTargets(for: instruction) {
                assignmentTargetCounts[target.rawValue, default: 0] += 1
            }
        }

        let shouldSpillID = Set(assignmentTargetCounts.filter { $0.value > 1 }.map(\.key))

        var copyTargetAllocas: [Int32: LLVMCAPIBindings.LLVMValueRef] = [:]
        for instruction in function.body {
            for target in FunctionEmissionState.assignmentTargets(for: instruction) where shouldSpillID.contains(target.rawValue) {
                if copyTargetAllocas[target.rawValue] == nil,
                   let alloca = bindings.buildAlloca(builder, type: int64Type, name: "copy_slot_\(target.rawValue)")
                {
                    _ = bindings.buildStore(builder, value: zeroValue, pointer: alloca)
                    copyTargetAllocas[target.rawValue] = alloca
                }
            }
        }

        let state = FunctionEmissionState(
            emitter: self,
            builder: builder,
            int64Type: int64Type,
            zeroValue: zeroValue,
            context: context,
            llvmModule: llvmModule,
            llvmFunction: llvmFunction,
            outThrownPointerType: outThrownPointerType,
            outThrownParameter: outThrownParameter,
            nullThrownPointer: nullThrownPointer,
            parameterValues: parameterValues,
            internalFunctions: internalFunctions,
            globalVariables: globalVariables,
            maxKIRArgumentCountByExternalCallee: maxKIRArgCount,
            builderState: builderState,
            copyTargetAllocas: copyTargetAllocas,
            currentBlock: entryBlock,
            labelBlocks: labelBlocks
        )

        state.setupFrame(function: function)

        for (instructionIndex, instruction) in function.body.enumerated() {
            state.emitInstruction(instruction, instructionIndex: instructionIndex, function: function, diContext: diContext)
        }

        if !bindings.hasTerminator(state.currentBlock) {
            state.emitFramePop("ret_fallthrough")
            _ = bindings.buildRet(builder, value: zeroValue)
        }
    }

    fileprivate static func maxKIRArgumentCountByExternalCallee(
        body: [KIRInstruction],
        interner: StringInterner
    ) -> [String: Int] {
        var maxCount: [String: Int] = [:]
        for instruction in body {
            switch instruction {
            case let .call(_, callee, arguments, _, _, _, _, _):
                let raw = interner.resolve(callee)
                guard !raw.isEmpty else { continue }
                let effective = effectiveExternalCalleeNameForArity(raw, argumentCount: arguments.count)
                maxCount[effective, default: 0] = max(maxCount[effective, default: 0], arguments.count)
            case let .virtualCall(_, callee, _, arguments, _, _, _, _):
                let name = interner.resolve(callee)
                guard !name.isEmpty else { continue }
                let receiverPlusArgs = 1 + arguments.count
                maxCount[name, default: 0] = max(maxCount[name, default: 0], receiverPlusArgs)
            default:
                break
            }
        }
        return maxCount
    }

    private static func effectiveExternalCalleeNameForArity(_ calleeName: String, argumentCount: Int) -> String {
        if calleeName == "length", argumentCount == 1 {
            "kk_string_length"
        } else {
            calleeName
        }
    }
}
