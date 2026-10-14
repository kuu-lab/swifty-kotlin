extension CallTypeChecker {
    /// A constructor's self-constrained owner parameter is not inference
    /// evidence. Preserve it only with evidence for a lexical parameter or
    /// a variable whose enclosing builder inference session is still open.
    func validateConstructorTypeInference(
        _ resolved: ResolvedCall,
        args: [CallArgument],
        argTypes: [TypeID],
        explicitTypeArgs: [TypeID],
        expectedType: TypeID?,
        range: SourceRange,
        ctx: TypeInferenceContext
    ) -> ResolvedCall {
        let sema = ctx.sema
        guard resolved.diagnostic == nil,
              let chosen = resolved.chosenCallee,
              sema.symbols.symbol(chosen)?.kind == .constructor,
              let signature = sema.symbols.functionSignature(for: chosen)
        else { return resolved }
        let lexicalParameters = driver.helpers.lexicalTypeParameterSymbols(in: ctx)
        let variables = sema.types.makeTypeVarBySymbol(signature.typeParameterSymbols)
        for (parameterIndex, symbol) in signature.typeParameterSymbols.prefix(signature.classTypeParameterCount).enumerated() {
            guard let variable = variables[symbol],
                  let inferred = resolved.substitutedTypeArguments[variable],
                  case let .typeParam(parameter) = sema.types.kind(of: inferred),
                  parameter.capture == nil,
                  parameter.symbol == symbol
            else { continue }
            if let session = ctx.builderInference,
               !session.isFinalized,
               session.typeVarBySymbol[symbol] != nil
            { continue }
            if lexicalParameters.contains(symbol) {
                let hasExpectedEvidence = expectedType.map { expected in
                    ctx.resolver.decomposeSubtypeConstraint(
                        subtype: signature.returnType, supertype: expected,
                        typeVarBySymbol: variables, typeSystem: sema.types, blameRange: range
                    ).contains { constraint in
                        switch (constraint.left, constraint.right) {
                        case let (.variable(left), .variable(right)):
                            return left == variable && right == variable
                        case let (.variable(constrained), .type(bound)),
                             let (.type(bound), .variable(constrained)):
                            return constrained == variable && sema.types.typeContainsTypeParam(bound, symbol: symbol)
                        default:
                            return false
                        }
                    }
                } ?? false
                let hasExplicitEvidence = explicitTypeArgs.indices.contains(parameterIndex)
                    && sema.types.typeContainsTypeParam(explicitTypeArgs[parameterIndex], symbol: symbol)
                let hasArgumentEvidence = args.indices.contains { argumentIndex in
                    guard let parameterIndex = resolved.parameterMapping[argumentIndex],
                          signature.parameterTypes.indices.contains(parameterIndex),
                          sema.types.typeContainsTypeParam(signature.parameterTypes[parameterIndex], symbol: symbol),
                          argTypes.indices.contains(argumentIndex)
                    else { return false }
                    let argument = args[argumentIndex]
                    let type = argTypes[argumentIndex]
                    if case let .lambdaLiteral(params, _, _, _) = ctx.ast.arena.expr(argument.expr) {
                        let annotations = driver.exprChecker.resolveLambdaParamAnnotations(
                            argument.expr, ctx: ctx, paramCount: params.count
                        )
                        return annotations?.contains { annotation in
                            annotation.map { sema.types.typeContainsTypeParam($0, symbol: symbol) } ?? false
                        } ?? false
                    }
                    return sema.types.typeContainsTypeParam(type, symbol: symbol)
                }
                // The owner and its fresh constructor variable share a symbol.
                // Lexical visibility alone cannot infer an unannotated callback.
                if hasExpectedEvidence || hasExplicitEvidence || hasArgumentEvidence { continue }
            }
            return ResolvedCall(
                chosenCallee: nil,
                substitutedTypeArguments: [:],
                parameterMapping: [:],
                diagnostic: Diagnostic(
                    severity: .error,
                    code: "KSWIFTK-SEMA-INFER",
                    message: "Cannot infer type argument from the call arguments and expected type; provide explicit type arguments or an explicit expected type.",
                    primaryRange: range,
                    secondaryRanges: []
                )
            )
        }
        return resolved
    }
}
