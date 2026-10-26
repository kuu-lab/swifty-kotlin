extension LambdaLowerer {
    func emitFunctionValueTypeTag(
        _ callableExpr: KIRExprID,
        functionType: FunctionType,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) {
        let arity = Int64(functionType.contextReceivers.count
            + (functionType.receiver == nil ? 0 : 1) + functionType.params.count)
        let functionTypePayload = arity | (functionType.isSuspend ? 0x100 : 0)
        let payloadExpr = arena.appendExpr(.intLiteral(functionTypePayload), type: sema.types.intType)
        instructions.append(.constValue(result: payloadExpr, value: .intLiteral(functionTypePayload)))
        // Preserve the raw symbol and capture ABI for inline/HOF/coroutine lowering.
        instructions.append(.call(
            callee: interner.intern("kk_function_value_tag_arity"),
            arguments: [callableExpr, payloadExpr],
            result: nil,
            canThrow: false
        ))
    }

    func materializeEscapingCallableValue(
        exprID: ExprID? = nil,
        lambdaSymbol: SymbolID,
        lambdaName: InternedString,
        lambdaReturnType: TypeID,
        functionType: FunctionType,
        captureArguments: [KIRExprID],
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID? {
        if let exprID, functionType.receiver != nil, !functionType.isSuspend {
            // Generic receiver callbacks already use the callee's erased return ABI.
            guard lambdaReturnType == functionType.returnType else { return nil }
            let callable = arena.appendExpr(.symbolRef(lambdaSymbol), type: sema.types.make(.functionType(functionType)))
            instructions.append(.constValue(result: callable, value: .symbolRef(lambdaSymbol)))
            driver.ctx.registerCallableValue(
                callable,
                symbol: lambdaSymbol,
                callee: lambdaName,
                captureArguments: captureArguments,
                hasClosureParam: false
            )
            return driver.callLowerer.materializeFunctionValueArgument(
                loweredArgID: callable,
                argExprID: exprID,
                functionType: functionType,
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions
            )
        }
        // Suspend values count the receiver as the first invocation argument.
        // Context receivers are leading runtime invocation inputs for a
        // context-function value, before its extension receiver and parameters.
        let invocationTypes = functionType.contextReceivers
            + (functionType.receiver.map { [$0] } ?? [])
            + functionType.params
        let createCallee: InternedString
        switch invocationTypes.count {
        case 0:
            createCallee = interner.intern("kk_function_create_0")
        case 1:
            createCallee = interner.intern("kk_function_create_1")
        case 2:
            createCallee = interner.intern("kk_function_create_2")
        case 3:
            createCallee = interner.intern("kk_function_create_3")
        case 4:
            createCallee = interner.intern("kk_function_create_4")
        case 5:
            createCallee = interner.intern("kk_function_create_5")
        case 6:
            createCallee = interner.intern("kk_function_create_6")
        default:
            return nil
        }

        let adapterSymbol = driver.ctx.allocateSyntheticGeneratedSymbol()
        let adapterName = interner.intern("kk_function_value_adapter_\(exprID?.rawValue ?? -1)_\(adapterSymbol.rawValue)")
        let closureParam = KIRParameter(
            symbol: driver.ctx.allocateSyntheticGeneratedSymbol(),
            type: sema.types.intType
        )
        let valueParams: [KIRParameter] = invocationTypes.enumerated().map { index, type in
            KIRParameter(
                symbol: exprID.map { syntheticLambdaParamSymbol(lambdaExprID: $0, paramIndex: 100 + index) }
                    ?? driver.ctx.allocateSyntheticGeneratedSymbol(),
                type: type
            )
        }

        var body: [KIRInstruction] = [.beginBlock]
        let closureExpr = arena.appendExpr(.symbolRef(closureParam.symbol), type: closureParam.type)
        body.append(.constValue(result: closureExpr, value: .symbolRef(closureParam.symbol)))

        let arrayGet = interner.intern("kk_array_get_inbounds")
        var callArguments: [KIRExprID] = []
        for (captureIndex, captureExpr) in captureArguments.enumerated() {
            let captureType = arena.exprType(captureExpr) ?? sema.types.anyType
            let offsetExpr = arena.appendExpr(.intLiteral(Int64(captureIndex + 2)), type: sema.types.intType)
            body.append(.constValue(result: offsetExpr, value: .intLiteral(Int64(captureIndex + 2))))
            let loadedExpr = arena.appendTemporary(type: captureType)
            body.append(.call(callee: arrayGet, arguments: [closureExpr, offsetExpr], result: loadedExpr, canThrow: false))
            let normalizedLoadedExpr = normalizeHOFPrimitiveParameter(
                loadedExpr,
                type: captureType,
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &body,
                isRawCallbackParameter: true
            )
            callArguments.append(normalizedLoadedExpr)
        }

        for param in valueParams {
            let paramExpr = arena.appendExpr(.symbolRef(param.symbol), type: param.type)
            body.append(.constValue(result: paramExpr, value: .symbolRef(param.symbol)))
            let normalizedParamExpr = normalizeHOFPrimitiveParameter(
                paramExpr,
                type: param.type,
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &body,
                isRawCallbackParameter: true
            )
            callArguments.append(normalizedParamExpr)
        }

        if let signature = sema.symbols.functionSignature(for: lambdaSymbol) {
            callArguments = packOrdinaryCallableVarargValues(
                callArguments, targetSymbol: lambdaSymbol,
                parameterOffset: callArguments.count - signature.parameterTypes.count, resultType: lambdaReturnType,
                sema: sema, arena: arena, interner: interner, instructions: &body
            )
        }

        let concreteReturnType = arena.function(for: lambdaSymbol)?.returnType ?? lambdaReturnType
        let boxedReturnType = driver.callLowerer.functionValueBoxedReturnType(
            concreteReturnType: concreteReturnType,
            expectedReturnType: functionType.returnType,
            sema: sema
        )
        let adapterReturnType = boxedReturnType ?? lambdaReturnType

        let callResult = arena.appendTemporary(type: concreteReturnType)
        let thrownResult = arena.appendTemporary(type: sema.types.nullableAnyType)
        body.append(.constValue(result: thrownResult, value: .null))
        body.append(.call(
            symbol: lambdaSymbol,
            callee: lambdaName,
            arguments: callArguments,
            result: callResult,
            canThrow: true,
            thrownResult: thrownResult
        ))
        let continueLabel = driver.ctx.makeLoopLabel()
        let rethrowLabel = driver.ctx.makeLoopLabel()
        body.append(.jumpIfNotNull(value: thrownResult, target: rethrowLabel))
        body.append(.jump(continueLabel))
        body.append(.label(rethrowLabel))
        body.append(.rethrow(value: thrownResult))
        body.append(.label(continueLabel))
        var returnValue = callResult
        if let boxedReturnType {
            returnValue = boxValueForAnySlot(
                callResult,
                sourceType: concreteReturnType,
                types: sema.types,
                symbols: sema.symbols,
                interner: interner,
                arena: arena,
                resultType: boxedReturnType,
                requireNonNull: true,
                sema: sema,
                into: &body
            )
        }
        switch sema.types.kind(of: adapterReturnType) {
        case .unit, .nothing(.nonNull), .nothing(.nullable):
            body.append(.returnUnit)
        default:
            body.append(.returnValue(returnValue))
        }
        body.append(.endBlock)

        let adapterDecl = arena.appendDecl(
            .function(
                KIRFunction(
                    symbol: adapterSymbol,
                    name: adapterName,
                    params: [closureParam] + valueParams,
                    returnType: adapterReturnType,
                    body: body,
                    isSuspend: functionType.isSuspend,
                    isInline: false
                )
            )
        )
        driver.ctx.appendGeneratedCallableDecl(adapterDecl)

        let slotCountExpr = arena.appendExpr(.intLiteral(Int64(2 + captureArguments.count)), type: sema.types.intType)
        instructions.append(.constValue(result: slotCountExpr, value: .intLiteral(Int64(2 + captureArguments.count))))
        let classIDExpr = arena.appendExpr(.intLiteral(0), type: sema.types.intType)
        instructions.append(.constValue(result: classIDExpr, value: .intLiteral(0)))
        let closureObj = arena.appendTemporary(type: sema.types.intType)
        instructions.append(.call(
            callee: interner.intern("kk_object_new"),
            arguments: [slotCountExpr, classIDExpr],
            result: closureObj,
            canThrow: false
        ))
        for (captureIndex, captureExpr) in captureArguments.enumerated() {
            let offsetExpr = arena.appendExpr(.intLiteral(Int64(captureIndex + 2)), type: sema.types.intType)
            instructions.append(.constValue(result: offsetExpr, value: .intLiteral(Int64(captureIndex + 2))))
            let setResult = arena.appendTemporary(type: sema.types.anyType)
            instructions.append(.call(
                callee: interner.intern("kk_array_set"),
                arguments: [closureObj, offsetExpr, captureExpr],
                result: setResult,
                canThrow: true
            ))
        }

        let adapterExpr = arena.appendExpr(.symbolRef(adapterSymbol), type: sema.types.intType)
        instructions.append(.constValue(result: adapterExpr, value: .symbolRef(adapterSymbol)))
        let materializedExpr = arena.appendTemporary(type: sema.types.make(.functionType(functionType)))
        instructions.append(.call(callee: createCallee, arguments: [adapterExpr, closureObj], result: materializedExpr, canThrow: false))
        if functionType.isSuspend {
            emitFunctionValueTypeTag(
                materializedExpr,
                functionType: functionType,
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions
            )
        }
        driver.ctx.registerCallableValue(
            materializedExpr,
            symbol: adapterSymbol,
            callee: adapterName,
            captureArguments: [closureObj],
            hasClosureParam: true,
            unboxedSymbol: lambdaSymbol
        )
        emitFunctionDescription(
            value: materializedExpr,
            description: "kotlin.Function\(invocationTypes.count)",
            identity: true,
            sema: sema, arena: arena, interner: interner, instructions: &instructions
        )
        return materializedExpr
    }
}
