extension CallTypeChecker {
    private struct NestedClassifierCompanionInvokeTarget {
        let companionSymbol: SymbolID
        let receiverType: TypeID
        let candidates: [SymbolID]
        let invisibleCandidates: [SemanticSymbol]
    }

    func inferQualifiedNestedClassifierCompanionInvoke(
        _ request: MemberCallInferenceRequest,
        classifierSymbol: SymbolID,
        argTypes: [TypeID],
        locals: inout LocalBindings
    ) -> TypeID? {
        let id = request.id
        let args = request.args
        let ctx = request.ctx
        let sema = ctx.sema
        let ast = ctx.ast
        let interner = ctx.interner

        guard ast.arena.isExplicitCall(id),
              let target = nestedClassifierCompanionInvokeTarget(
                  classifierSymbol: classifierSymbol,
                  ctx: ctx
              )
        else {
            return nil
        }

        let candidates = target.candidates
        if candidates.isEmpty {
            guard let firstInvisible = target.invisibleCandidates.first else {
                return nil
            }
            driver.helpers.emitVisibilityError(
                for: firstInvisible,
                name: interner.resolve(request.calleeName),
                range: request.range,
                diagnostics: sema.diagnostics
            )
            return driver.helpers.bindAndReturnErrorType(id, sema: sema)
        }

        var preInferredNonLambdaArgTypes: [Int: TypeID] = [:]
        for (index, argument) in args.enumerated() {
            switch ast.arena.expr(argument.expr) {
            case .lambdaLiteral, .callableRef:
                continue
            case .blockExpr where ast.arena.isAnonymousFunction(argument.expr):
                continue
            default:
                preInferredNonLambdaArgTypes[index] = argTypes[index]
            }
        }

        var expectedTypeOverrides: [Int: TypeID] = [:]
        var lambdaContextOverrides: [Int: TypeInferenceContext] = [:]
        let expectedTypeHintIndices = prepareCallExprArgumentContexts(
            args: args,
            callRange: request.range,
            ctx: ctx,
            expectedType: request.expectedType,
            explicitTypeArgs: request.explicitTypeArgs,
            calleeName: request.calleeName,
            candidates: candidates,
            locals: locals,
            withContextExpectedLambdaType: nil,
            expectedTypeOverrides: &expectedTypeOverrides,
            lambdaContextOverrides: &lambdaContextOverrides
        )
        let preparedArgs = prepareCallArguments(
            args: args,
            callRange: request.range,
            candidates: candidates,
            preInferredNonLambdaArgTypes: preInferredNonLambdaArgTypes,
            expectedTypeOverrides: expectedTypeOverrides,
            expectedTypeHintIndices: expectedTypeHintIndices,
            contextualCallResultType: ctx.isCallResultDiscarded && ctx.isUnitCoercionContext
                ? sema.types.unitType : request.expectedType,
            explicitTypeArgs: request.explicitTypeArgs,
            receiverType: target.receiverType,
            boundObjectDispatchReceiverCandidates: Set(candidates),
            lambdaContextOverrides: lambdaContextOverrides,
            ctx: ctx,
            locals: &locals
        )
        let resolved = resolveCallRespectingLambdaReturnType(
            candidates: candidates,
            args: args,
            argTypes: preparedArgs.argTypes,
            range: request.range,
            calleeName: request.calleeName,
            explicitTypeArgs: request.explicitTypeArgs,
            expectedType: request.expectedType,
            implicitReceiverType: nil,
            additionalDispatchReceiverTypes: [target.receiverType],
            additionalBoundObjectDispatchReceiverCandidates: Set(candidates),
            lambdaLiteralIndices: preparedArgs.lambdaLiteralIndices,
            inputOnlyLambdaIndices: preparedArgs.inputOnlyLambdaIndices,
            blockedLambdaRefinement: preparedArgs.blockedLambdaRefinement,
            hasUnresolvableImplicitLambdaParameter: preparedArgs.hasUnresolvableImplicitLambdaParameter,
            ctx: ctx
        )
        if let diagnostic = resolved.diagnostic {
            sema.diagnostics.emit(diagnostic)
            return driver.helpers.bindAndReturnErrorType(id, sema: sema)
        }
        guard let chosen = resolved.chosenCallee else {
            return nil
        }

        contextualizeResolvedIntegerArguments(args: args, resolved: resolved, ctx: ctx, locals: &locals)
        let contextParameterReceiverSymbols = contextParameterReceiverSymbols(
            for: chosen,
            substitution: resolved.substitutedTypeArguments,
            ctx: ctx
        )
        let resultType = bindCallAndResolveReturnType(
            id,
            chosen: chosen,
            resolved: resolved,
            sema: sema,
            dispatchReceiverSymbol: target.companionSymbol,
            contextParameterReceiverSymbols: contextParameterReceiverSymbols
        )
        sema.bindings.bindIdentifier(id, symbol: chosen)
        sema.bindings.bindIdentifier(request.receiverID, symbol: target.companionSymbol)
        sema.bindings.bindExprType(request.receiverID, type: target.receiverType)
        sema.bindings.markInvokeOperatorCall(id)
        applyContractEffects(id: id, chosen: chosen, args: args, ctx: ctx, locals: &locals)
        driver.helpers.checkDeprecation(
            for: chosen,
            sema: sema,
            interner: interner,
            range: request.range,
            diagnostics: sema.diagnostics
        )
        driver.helpers.checkOptIn(
            for: chosen,
            ctx: ctx,
            range: request.range,
            diagnostics: sema.diagnostics
        )
        sema.bindings.bindExprType(id, type: resultType)
        return resultType
    }

    private func nestedClassifierCompanionInvokeTarget(
        classifierSymbol: SymbolID,
        ctx: TypeInferenceContext
    ) -> NestedClassifierCompanionInvokeTarget? {
        let sema = ctx.sema
        let invokeName = ctx.interner.intern("invoke")
        // A nested `object` is already the dispatch instance — `Owner.Obj(x)`
        // invokes `Obj`'s own members — while other classifiers dispatch
        // through their companion object. The object itself is checked first
        // so its own `invoke` wins (KUU-3662).
        let companionSymbols = [
            sema.symbols.symbol(classifierSymbol)?.kind == .object ? classifierSymbol : nil,
            sema.symbols.companionBlockObjectSymbol(
                for: classifierSymbol,
                interner: ctx.interner
            ),
            sema.symbols.companionObjectSymbol(for: classifierSymbol),
        ].compactMap { $0 }

        for companionSymbol in companionSymbols {
            let receiverType = sema.symbols.propertyType(for: companionSymbol)
                ?? sema.types.make(.classType(ClassType(
                    classSymbol: companionSymbol,
                    args: [],
                    nullability: .nonNull
                )))
            let invokeCandidates = driver.helpers.collectMemberFunctionCandidates(
                named: invokeName,
                receiverType: receiverType,
                sema: sema,
                interner: ctx.interner
            ).filter { candidate in
                sema.symbols.symbol(candidate)?.flags.contains(.operatorFunction) == true
            }
            guard !invokeCandidates.isEmpty else { continue }
            let (visible, invisible) = ctx.filterByVisibility(invokeCandidates)
            return NestedClassifierCompanionInvokeTarget(
                companionSymbol: companionSymbol,
                receiverType: receiverType,
                candidates: visible,
                invisibleCandidates: invisible
            )
        }
        return nil
    }
}
