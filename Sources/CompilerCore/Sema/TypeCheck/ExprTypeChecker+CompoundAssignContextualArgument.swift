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
        // KUU-4493: a bare generic factory can also collapse to errorType when
        // the call resolves against a precompiled stdlib artifact (no bundled
        // source factory path runs), so accept that shape for recovery too.
        let originalIsError = originalType == sema.types.errorType
        guard checker.isInferableNestedCallExpr(valueExpr, ast: ctx.ast),
              originalIsError || checker.typeContainsNothingType(originalType, sema: sema)
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
            ) else { continue }
            let expectedType: TypeID
            if originalIsError {
                // Without a first-pass nominal head there is nothing to
                // re-parameterize; the operator's own parameter type is the
                // best concrete expectation available.
                expectedType = parameterType
            } else {
                guard let concreteExpectedType = checker.concreteNestedCallExpectedType(
                    originalArgumentType: originalType, boundType: parameterType, sema: sema
                ), case let .classType(originalClass) = sema.types.kind(of: originalType),
                   case let .classType(expectedClass) = sema.types.kind(of: concreteExpectedType),
                   zip(originalClass.args, expectedClass.args).allSatisfy({ original, expected in
                       switch original {
                       case let .invariant(type), let .in(type), let .out(type):
                           checker.typeContainsNothingType(type, sema: sema) || original == expected
                       case .star:
                           original == expected
                       }
                   })
                else { continue }
                expectedType = concreteExpectedType
            }
            expectedTypes.insert(expectedType)
        }
        // Nominal compatibility distinguishes element and iterable overloads;
        // conflicting concrete element expectations must remain unresolved.
        guard expectedTypes.count == 1, let expectedType = expectedTypes.first else {
            return originalType
        }
        // The eager first pass already reported SEMA-INFER (or a resolution
        // failure) inside the value expression; that diagnostic is stale once
        // a concrete operator-derived expectation exists, so drop it before
        // re-inferring — the same recovery the nested-call argument machinery
        // performs for call arguments (KUU-3750).
        let valueRange = ctx.ast.arena.exprRange(valueExpr)
        let removedDiagnostics = valueRange.map {
            sema.diagnostics.removeErrorDiagnostics(containedIn: $0)
        } ?? []
        let diagnosticsCheckpoint = sema.diagnostics.checkpoint()
        let recoveredType = driver.inferExpr(
            valueExpr, ctx: ctx, locals: &locals, expectedType: expectedType
        )
        let retryEmittedError = sema.diagnostics.diagnostics
            .dropFirst(diagnosticsCheckpoint)
            .contains { $0.severity == .error }
        if !retryEmittedError,
           recoveredType == sema.types.errorType || checker.typeContainsErrorType(recoveredType, sema: sema),
           !removedDiagnostics.isEmpty
        {
            // The retry left the expression in the error state without
            // explaining why; restore the first pass's genuine failures.
            for diagnostic in removedDiagnostics {
                sema.diagnostics.emit(diagnostic)
            }
        }
        return recoveredType
    }
}
