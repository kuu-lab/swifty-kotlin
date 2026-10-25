extension CallTypeChecker {
    func functionValueSamArgumentExpectedType(
        _ exprID: ExprID,
        parameterType: TypeID,
        ctx: TypeInferenceContext
    ) -> TypeID {
        guard let sam = driver.helpers.samFunctionType(for: parameterType, sema: ctx.sema) else {
            return parameterType
        }
        let expectedFunctionType = ctx.sema.types.withNullability(
            ctx.sema.types.nullability(of: parameterType),
            for: ctx.sema.types.make(.functionType(sam))
        )
        if let type = ctx.sema.bindings.exprType(for: exprID),
           case .functionType = ctx.sema.types.kind(of: type)
        {
            return expectedFunctionType
        }
        if case let .call(callee, _, _, _) = ctx.ast.arena.expr(exprID),
           case let .nameRef(name, _) = ctx.ast.arena.expr(callee)
        {
            let candidates = ctx.cachedScopeLookup(name).filter {
                ctx.sema.symbols.functionSignature(for: $0) != nil
            }
            if !candidates.isEmpty, candidates.allSatisfy({ candidate in
                guard let type = ctx.sema.symbols.functionSignature(for: candidate)?.returnType else { return false }
                if case .functionType = ctx.sema.types.kind(of: type) { return true }
                return false
            }) {
                return expectedFunctionType
            }
        }
        return parameterType
    }

    /// Record adaptation only after overload resolution has selected a target.
    /// Preserve the expression's function type for loading the original value.
    func bindResolvedFunctionValueSamArguments(
        _ id: ExprID,
        chosen: SymbolID,
        resolved: ResolvedCall,
        sema: SemaModule
    ) {
        let args: [CallArgument]
        switch driver.ast.arena.expr(id) {
        case let .call(_, _, arguments, _), let .memberCall(_, _, _, arguments, _):
            args = arguments
        default:
            return
        }
        guard let signature = sema.symbols.functionSignature(for: chosen) else { return }
        let typeVars = sema.types.makeTypeVarBySymbol(signature.typeParameterSymbols)
        for (index, argument) in args.enumerated() where !argument.isSpread {
            let wasSamConverted = sema.bindings.isSamConversion(argument.expr)
            guard let expressionType = sema.bindings.exprType(for: argument.expr) else { continue }
            let hasNominalSamType: Bool
            if case .classType = sema.types.kind(of: expressionType),
               case .lambdaLiteral = driver.ast.arena.expr(argument.expr) {
                hasNominalSamType = wasSamConverted
            } else {
                hasNominalSamType = false
            }
            let sourceType = hasNominalSamType
                ? sema.bindings.samUnderlyingFunctionType(for: argument.expr) ?? expressionType
                : expressionType
            guard case .functionType = sema.types.kind(of: sourceType),
                  let parameterIndex = resolved.parameterMapping[index],
                  signature.parameterTypes.indices.contains(parameterIndex)
            else { continue }
            let interfaceType = sema.types.substituteTypeParameters(
                in: signature.parameterTypes[parameterIndex],
                substitution: resolved.substitutedTypeArguments,
                typeVarBySymbol: typeVars
            )
            guard let function = driver.helpers.samFunctionType(for: interfaceType, sema: sema) else { continue }
            let functionType = sema.types.make(.functionType(function))
            // Resolution has already selected this argument through the SAM
            // function signature. Do not repeat the compatibility check after
            // generic substitution: if it suppresses this binding, KIR passes
            // the raw KFunction as a Comparator and its later compare dispatch
            // has no Comparator itable slot.
            sema.bindings.markSamConversion(argument.expr)
            sema.bindings.bindSamUnderlyingFunctionType(argument.expr, type: functionType)
            sema.bindings.bindSamInterfaceType(argument.expr, type: interfaceType)
            if hasNominalSamType { sema.bindings.bindExprType(argument.expr, type: interfaceType) }
        }
    }
}
