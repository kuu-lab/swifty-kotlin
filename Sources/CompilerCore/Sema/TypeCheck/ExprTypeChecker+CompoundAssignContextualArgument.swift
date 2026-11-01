extension ExprTypeChecker {
    /// Recover an eagerly inferred nested factory without changing concrete
    /// arguments or selecting an arbitrary expected type from competing overloads.
    func contextualCompoundAssignmentValueType(
        op: CompoundAssignOp,
        receiverType: TypeID,
        valueExpr: ExprID,
        originalType: TypeID,
        range: SourceRange,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings
    ) -> TypeID {
        let sema = ctx.sema
        let checker = driver.callChecker
        guard checker.isInferableNestedCallExpr(valueExpr, ast: ctx.ast),
              checker.typeContainsNothingType(originalType, sema: sema)
        else { return originalType }

        let names = operatorFunctionNames(for: op, interner: ctx.interner)
        let call = CallExpr(
            range: range, calleeName: names[0], args: [CallArg(type: originalType)],
            isOperatorCall: true
        )
        let candidates = collectOperatorCandidates(
            names: names, receiverType: receiverType, call: call, locals: locals, ctx: ctx
        )
        guard !candidates.isEmpty else { return originalType }
        let originalResolution = ctx.resolver.resolveCall(
            candidates: candidates,
            call: call,
            expectedType: nil,
            implicitReceiverType: receiverType,
            ctx: sema
        )
        // Preserve overload priority whenever the argument already resolves.
        if originalResolution.chosenCallee != nil, originalResolution.diagnostic == nil {
            return originalType
        }

        var expectedTypes: Set<TypeID> = []
        for candidate in candidates {
            guard let signature = sema.symbols.functionSignature(for: candidate),
                  signature.parameterTypes.count == 1
            else { continue }
            guard let parameterType = checker.lambdaLiteralExpectedType(
                at: 0, args: [CallArgument(expr: valueExpr)], callRange: range,
                candidates: [candidate], receiverType: receiverType,
                resolver: ctx.resolver, sema: sema, ctx: ctx
            ).type, !ctx.resolver.containsTypeVariable(
                parameterType,
                typeVarBySymbol: sema.types.makeTypeVarBySymbol(signature.typeParameterSymbols),
                typeSystem: sema.types
            ), let expectedType = checker.concreteNestedCallExpectedType(
                originalArgumentType: originalType, boundType: parameterType, sema: sema
            ) else { continue }
            guard case let .classType(originalClass) = sema.types.kind(of: originalType),
                  case let .classType(expectedClass) = sema.types.kind(of: expectedType),
                  zip(originalClass.args, expectedClass.args).allSatisfy({ original, expected in
                      switch original {
                      case let .invariant(type), let .in(type), let .out(type):
                          checker.typeContainsNothingType(type, sema: sema) || original == expected
                      case .star:
                          original == expected
                      }
                  })
            else { continue }
            expectedTypes.insert(expectedType)
        }
        // Nominal compatibility distinguishes element and iterable overloads;
        // conflicting concrete element expectations must remain unresolved.
        guard expectedTypes.count == 1, let expectedType = expectedTypes.first else {
            return originalType
        }
        return driver.inferExpr(valueExpr, ctx: ctx, locals: &locals, expectedType: expectedType)
    }
}
