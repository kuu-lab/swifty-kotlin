extension CallLowerer {
    func adaptSuspendFunctionValueArgument(
        _ argument: KIRExprID,
        sourceExpr: ExprID,
        parameterType: TypeID,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        guard let sourceType = sema.bindings.exprTypes[sourceExpr],
              let convertedType = sema.types.suspendConversionType(from: sourceType, to: parameterType),
              case let .functionType(sourceFunction) = sema.types.kind(of: sourceType),
              case let .functionType(targetFunction) = sema.types.kind(of: parameterType),
              sourceFunction.contextReceivers.isEmpty
        else {
            return argument
        }

        let originalValue = materializeFunctionValueArgument(
            loweredArgID: argument, argExprID: sourceExpr,
            functionType: sourceFunction, sema: sema, arena: arena,
            interner: interner, instructions: &instructions
        )
        let symbol = driver.ctx.allocateSyntheticGeneratedSymbol()
        let name = interner.intern("kk_suspend_conversion_\(symbol.rawValue)")
        let closureParam = KIRParameter(
            symbol: driver.ctx.allocateSyntheticGeneratedSymbol(), type: sourceType
        )
        let valueTypes = (sourceFunction.receiver.map { [$0] } ?? []) + sourceFunction.params
        let valueParams = valueTypes.map { type in
            KIRParameter(symbol: driver.ctx.allocateSyntheticGeneratedSymbol(), type: type)
        }
        var body: [KIRInstruction] = [.beginBlock]
        let callArguments = ([closureParam] + valueParams).map { parameter in
            let ref = arena.appendExpr(.symbolRef(parameter.symbol), type: parameter.type)
            body.append(.constValue(result: ref, value: .symbolRef(parameter.symbol)))
            return ref
        }
        let binding = CallableValueCallBinding(target: nil, functionType: sourceType, parameterMapping: [:])
        guard let invoke = runtimeCallableInvokeCallee(
            callableValueCallBinding: binding, sema: sema, interner: interner
        ) else {
            return argument
        }
        let result = arena.appendTemporary(type: sourceFunction.returnType)
        let thrown = arena.appendTemporary(type: sema.types.nullableAnyType)
        body.append(.call(
            symbol: nil, callee: invoke, arguments: callArguments,
            result: result, canThrow: true, thrownResult: thrown
        ))
        let success = driver.ctx.makeLoopLabel()
        let failure = driver.ctx.makeLoopLabel()
        body.append(.jumpIfNotNull(value: thrown, target: failure))
        body.append(.jump(success))
        body.append(.label(failure))
        body.append(.rethrow(value: thrown))
        body.append(.label(success))
        if sourceFunction.returnType == sema.types.unitType {
            body.append(.returnUnit)
        } else {
            body.append(.returnValue(result))
        }
        body.append(.endBlock)
        let decl = arena.appendDecl(.function(KIRFunction(
            symbol: symbol, name: name, params: [closureParam] + valueParams,
            returnType: sourceFunction.returnType, body: body,
            isSuspend: true, isInline: false
        )))
        driver.ctx.appendGeneratedCallableDecl(decl)
        let ref = arena.appendExpr(.symbolRef(symbol), type: convertedType)
        instructions.append(.constValue(result: ref, value: .symbolRef(symbol)))
        driver.ctx.registerCallableValue(
            ref, symbol: symbol, callee: name,
            captureArguments: [originalValue], hasClosureParam: true
        )
        return materializeFunctionValueArgument(
            loweredArgID: ref, argExprID: sourceExpr,
            functionType: targetFunction, sema: sema, arena: arena,
            interner: interner, instructions: &instructions
        )
    }
}
