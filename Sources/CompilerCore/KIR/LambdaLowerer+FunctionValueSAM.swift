extension LambdaLowerer {
    func lowerFunctionValueSamWrapper(
        _ exprID: ExprID,
        value: KIRExprID,
        functionType: FunctionType,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID? {
        guard let interfaceID = sema.bindings.samInterfaceType(for: exprID),
              case let .classType(interface) = sema.types.kind(of: interfaceID),
              let samType = sema.bindings.samUnderlyingFunctionType(for: exprID),
              case let .functionType(samFunction) = sema.types.kind(of: samType)
        else { return nil }
        if functionType.nullability != .nonNull {
            guard interface.nullability != .nonNull else { return nil }
            let result = arena.appendTemporary(type: interfaceID)
            let nonNullLabel = driver.ctx.makeLoopLabel()
            let endLabel = driver.ctx.makeLoopLabel()
            instructions.append(.jumpIfNotNull(value: value, target: nonNullLabel))
            let nullValue = arena.appendExpr(.null, type: interfaceID)
            instructions.append(.constValue(result: nullValue, value: .null))
            instructions.append(.copy(from: nullValue, to: result))
            instructions.append(.jump(endLabel))
            instructions.append(.label(nonNullLabel))

            let nonNullSourceType = sema.types.makeNonNullable(sema.types.make(.functionType(functionType)))
            guard case let .functionType(nonNullFunctionType) = sema.types.kind(of: nonNullSourceType) else {
                return nil
            }
            let nonNullValue = arena.appendTemporary(type: nonNullSourceType)
            instructions.append(.copy(from: value, to: nonNullValue))
            guard let wrapper = lowerNonNullFunctionValueSamWrapper(
                exprID, value: nonNullValue, functionType: nonNullFunctionType,
                interface: interface, samFunction: samFunction, sema: sema,
                arena: arena, interner: interner, instructions: &instructions
            ) else { return nil }
            instructions.append(.copy(from: wrapper, to: result))
            instructions.append(.label(endLabel))
            return result
        }

        return lowerNonNullFunctionValueSamWrapper(
            exprID, value: value, functionType: functionType,
            interface: interface, samFunction: samFunction, sema: sema,
            arena: arena, interner: interner, instructions: &instructions
        )
    }

    private func lowerNonNullFunctionValueSamWrapper(
        _ exprID: ExprID,
        value: KIRExprID,
        functionType: FunctionType,
        interface: ClassType,
        samFunction: FunctionType,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID? {
        let sourceType = sema.types.make(.functionType(functionType))
        let binding = CallableValueCallBinding(target: nil, functionType: sourceType, parameterMapping: [:])
        guard let invoke = driver.callLowerer.runtimeCallableInvokeCallee(
            callableValueCallBinding: binding, sema: sema, interner: interner
        ) else { return nil }
        let boxedValue = driver.callLowerer.materializeFunctionValueArgument(
            loweredArgID: value, argExprID: exprID, functionType: functionType,
            sema: sema, arena: arena, interner: interner, instructions: &instructions
        )
        let name = interner.intern("kk_sam_value_thunk_\(exprID.rawValue)")
        let symbol = sema.symbols.define(
            kind: .function, name: name, fqName: [name], declSite: nil,
            visibility: .private, flags: [.synthetic]
        )
        let capture = KIRParameter(
            symbol: syntheticLambdaCaptureParamSymbol(lambdaExprID: exprID, captureIndex: 0),
            type: sourceType
        )
        // The thunk's value parameters mirror the SAM member's full input
        // shape — context receivers, then the extension receiver, then value
        // parameters — so `lowerSamWrapperValue` can forward every argument
        // it synthesizes and `kk_function_invoke_N` sees its declared arity.
        let samInputTypes = samFunction.contextReceivers
            + (samFunction.receiver.map { [$0] } ?? [])
            + samFunction.params
        let params = samInputTypes.enumerated().map { index, type in
            KIRParameter(symbol: syntheticLambdaParamSymbol(lambdaExprID: exprID, paramIndex: index), type: type)
        }
        var body: [KIRInstruction] = [.beginBlock]
        var arguments = ([capture] + params).map { param in
            let value = arena.appendExpr(.symbolRef(param.symbol), type: param.type)
            body.append(.constValue(result: value, value: .symbolRef(param.symbol)))
            return value
        }
        // Contravariant inputs and covariant results can cross boxed/unboxed
        // boundaries. Typed copies let ABI lowering apply those conversions.
        let sourceParams = functionType.contextReceivers
            + (functionType.receiver.map { [$0] } ?? [])
            + functionType.params
        for (index, type) in sourceParams.enumerated() {
            let adapted = arena.appendTemporary(type: type)
            body.append(.copy(from: arguments[index + 1], to: adapted))
            arguments[index + 1] = adapted
        }
        let result = arena.appendTemporary(type: functionType.returnType)
        body.append(.call(callee: invoke, arguments: arguments, result: result, canThrow: true))
        if samFunction.returnType == sema.types.unitType {
            body.append(.returnUnit)
        } else {
            let adapted = arena.appendTemporary(type: samFunction.returnType)
            body.append(.copy(from: result, to: adapted))
            body.append(.returnValue(adapted))
        }
        body.append(.endBlock)
        let declaration = arena.appendDecl(.function(KIRFunction(
            symbol: symbol, name: name, params: [capture] + params,
            returnType: samFunction.returnType, body: body,
            isSuspend: samFunction.isSuspend, isInline: false
        )))
        driver.ctx.appendGeneratedCallableDecl(declaration)
        return lowerSamWrapperValue(
            exprID, interfaceType: interface, lambdaSymbol: symbol, lambdaName: name,
            lambdaReturnType: samFunction.returnType,
            captureBindings: [(capturedSymbol: capture.symbol, param: capture, valueExpr: boxedValue, declaredType: sourceType)],
            samMethodReceiverType: samFunction.receiver,
            samMethodContextParameterTypes: samFunction.contextReceivers,
            samMethodParamTypes: samFunction.params, sema: sema, arena: arena,
            interner: interner, instructions: &instructions
        )
    }
}
