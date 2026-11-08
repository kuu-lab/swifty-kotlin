extension CallTypeChecker {
    /// Reject only call shapes that cannot become applicable during contextual
    /// inference. Do not inspect lambda bodies here: scope priority and receiver
    /// specificity must be decided before checking those bodies.
    func extensionCandidateMatchesCallShape(
        _ candidate: SymbolID,
        request: MemberCallInferenceRequest,
        argumentTypes: [TypeID],
        receiverType: TypeID
    ) -> Bool {
        guard let signature = request.sema.symbols.functionSignature(for: candidate) else { return false }
        if !request.explicitTypeArgs.isEmpty {
            let count = request.sema.symbols.symbol(candidate)?.kind == .constructor
                ? signature.classTypeParameterCount
                : signature.typeParameterSymbols.count - signature.classTypeParameterCount
            guard count == request.explicitTypeArgs.count else { return false }
        }
        guard let mapping = parameterMappingForCallArguments(
            request.args, in: signature, callRange: request.range, ctx: request.ctx
        ) else { return false }
        for (index, argument) in request.args.enumerated() {
            guard let parameterIndex = mapping[index],
                  let rawType = contextualCallArgumentType(
                      argument, parameterIndex: parameterIndex, in: signature, ctx: request.ctx
                  )
            else { return false }
            let explicitType = applyExplicitTypeArgs(
                to: rawType, signature: signature, candidate: candidate,
                explicitTypeArgs: request.explicitTypeArgs, sema: request.sema
            )
            let parameterType = applyReceiverClassTypeArgs(
                to: explicitType, signature: signature, candidate: candidate,
                receiverType: receiverType, sema: request.sema
            )
            let expected = request.sema.types.makeNonNullable(parameterType)
            switch request.ctx.ast.arena.expr(argument.expr) {
            case let .lambdaLiteral(parameters, _, _, _):
                let functionType: FunctionType?
                if case let .functionType(function) = request.sema.types.kind(of: expected) {
                    functionType = function
                } else {
                    functionType = driver.helpers.samFunctionType(for: expected, sema: request.sema)
                }
                if let functionType {
                    if parameters.isEmpty {
                        guard functionType.params.count <= 1 else { return false }
                    } else {
                        guard functionType.params.count == parameters.count else { return false }
                    }
                } else if expected != request.sema.types.anyType,
                          expected != request.sema.types.errorType,
                          !request.sema.types.typeContainsAnyTypeParam(expected) {
                    return false
                }
            case .callableRef:
                // Callable-reference adaptation needs its contextual signature.
                continue
            default:
                guard argumentTypes.indices.contains(index) else { continue }
                let actual = argumentTypes[index]
                if actual == request.sema.types.errorType || actual == request.sema.types.anyType
                    || expected == request.sema.types.errorType
                    || request.sema.types.typeContainsAnyTypeParam(actual)
                    || request.sema.types.typeContainsAnyTypeParam(parameterType)
                    || argument.isSpread {
                    continue
                }
                if request.sema.types.isSubtype(actual, parameterType)
                    || request.sema.types.functionArgumentConversionType(from: actual, to: parameterType) != nil
                    || integerLiteralFitsParameter(argument.expr, parameterType: parameterType, ctx: request.ctx) {
                    continue
                }
                if case .functionType = request.sema.types.kind(of: request.sema.types.makeNonNullable(actual)),
                   driver.helpers.samFunctionType(for: parameterType, sema: request.sema) != nil {
                    continue
                }
                return false
            }
        }
        return true
    }
}
