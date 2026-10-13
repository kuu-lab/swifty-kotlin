extension LambdaLowerer {
    /// Hidden type tokens are values of the reference's environment. The thunk
    /// takes them before logical arguments and forwards them last to the target.
    func reifiedCallableReferenceThunk(
        _ exprID: ExprID,
        targetSymbol: SymbolID,
        functionType: FunctionType,
        captures: inout [KIRExprID],
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> (symbol: SymbolID, name: InternedString)? {
        guard let signature = sema.symbols.functionSignature(for: targetSymbol),
              !signature.reifiedTypeParameterIndices.isEmpty,
              let binding = sema.bindings.callableReferenceBinding(for: exprID),
              binding.chosenCallee == targetSymbol,
              signature.reifiedTypeParameterIndices.allSatisfy({ $0 < binding.substitutedTypeArguments.count })
        else { return nil }

        let ordinaryCaptureCount = captures.count
        var tokens: [KIRExprID] = []
        driver.callLowerer.appendReifiedTypeTokens(
            chosenCallee: targetSymbol, callBinding: binding, sema: sema,
            interner: interner, arena: arena, instructions: &instructions,
            arguments: &tokens
        )
        captures += tokens
        let symbol = driver.ctx.allocateSyntheticGeneratedSymbol()
        let name = interner.intern("kk_reified_ref_thunk_\(exprID.rawValue)_\(symbol.rawValue)")
        let captureParams = captures.map {
            KIRParameter(symbol: driver.ctx.allocateSyntheticGeneratedSymbol(), type: arena.exprType($0) ?? sema.types.anyType)
        }
        let valueTypes = (functionType.receiver.map { [$0] } ?? []) + functionType.params
        let valueParams = valueTypes.map {
            KIRParameter(symbol: driver.ctx.allocateSyntheticGeneratedSymbol(), type: $0)
        }
        var body: [KIRInstruction] = [.beginBlock]
        func reference(_ parameter: KIRParameter) -> KIRExprID {
            let value = arena.appendExpr(.symbolRef(parameter.symbol), type: parameter.type)
            body.append(.constValue(result: value, value: .symbolRef(parameter.symbol)))
            return value
        }
        let captureRefs = captureParams.map(reference)
        let arguments = Array(captureRefs.prefix(ordinaryCaptureCount))
            + valueParams.map(reference) + Array(captureRefs.dropFirst(ordinaryCaptureCount))
        let result = arena.appendTemporary(type: functionType.returnType)
        body.append(.call(
            symbol: targetSymbol,
            callee: callableTargetName(for: targetSymbol, sema: sema, interner: interner),
            arguments: arguments, result: result, canThrow: true, thrownResult: nil
        ))
        switch sema.types.kind(of: functionType.returnType) {
        case .unit, .nothing(.nonNull), .nothing(.nullable): body.append(.returnUnit)
        default: body.append(.returnValue(result))
        }
        body.append(.endBlock)
        driver.ctx.appendGeneratedCallableDecl(arena.appendDecl(.function(KIRFunction(
            symbol: symbol, name: name, params: captureParams + valueParams,
            returnType: functionType.returnType, body: body,
            isSuspend: functionType.isSuspend, isInline: false
        ))))
        return (symbol, name)
    }
}
