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

        guard request.ast.arena.isExplicitCall(request.id),
              let target = nestedClassifierCompanionInvokeTarget(
                  classifierSymbol: classifierSymbol,
                  ctx: request.ctx
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
                name: request.interner.resolve(request.calleeName),
                range: request.range,
                diagnostics: request.sema.diagnostics
            )
            return driver.helpers.bindAndReturnErrorType(request.id, sema: request.sema)
        }

        var preInferredNonLambdaArgTypes: [Int: TypeID] = [:]
        for (index, argument) in request.args.enumerated() {
            switch request.ast.arena.expr(argument.expr) {
            case .lambdaLiteral, .callableRef:
                continue
            case .blockExpr where request.ast.arena.isAnonymousFunction(argument.expr):
                continue
            default:
                preInferredNonLambdaArgTypes[index] = argTypes[index]
            }
        }

        var expectedTypeOverrides: [Int: TypeID] = [:]
        var lambdaContextOverrides: [Int: TypeInferenceContext] = [:]
        let expectedTypeHintIndices = prepareCallExprArgumentContexts(
            args: request.args,
            callRange: request.range,
            ctx: request.ctx,
            expectedType: request.expectedType,
            explicitTypeArgs: request.explicitTypeArgs,
            calleeName: request.calleeName,
            candidates: candidates,
            locals: locals,
            withContextExpectedLambdaType: nil,
            receiverType: target.receiverType,
            expectedTypeOverrides: &expectedTypeOverrides,
            lambdaContextOverrides: &lambdaContextOverrides
        )
        let preparedArgs = prepareCallArguments(
            args: request.args,
            callRange: request.range,
            candidates: candidates,
            preInferredNonLambdaArgTypes: preInferredNonLambdaArgTypes,
            expectedTypeOverrides: expectedTypeOverrides,
            expectedTypeHintIndices: expectedTypeHintIndices,
            contextualCallResultType: request.ctx.isCallResultDiscarded && request.ctx.isUnitCoercionContext
                ? request.sema.types.unitType : request.expectedType,
            explicitTypeArgs: request.explicitTypeArgs,
            receiverType: target.receiverType,
            boundObjectDispatchReceiverCandidates: Set(candidates),
            lambdaContextOverrides: lambdaContextOverrides,
            ctx: request.ctx,
            locals: &locals
        )
        let resolved = resolveCallRespectingLambdaReturnType(
            candidates: candidates,
            args: request.args,
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
            ctx: request.ctx
        )
        if let diagnostic = resolved.diagnostic {
            request.sema.diagnostics.emit(diagnostic)
            return driver.helpers.bindAndReturnErrorType(request.id, sema: request.sema)
        }
        guard let chosen = resolved.chosenCallee else {
            return nil
        }

        contextualizeResolvedIntegerArguments(args: request.args, resolved: resolved, ctx: request.ctx, locals: &locals)
        let contextParameterReceiverSymbols = contextParameterReceiverSymbols(
            for: chosen,
            substitution: resolved.substitutedTypeArguments,
            ctx: request.ctx
        )
        let resultType = bindCallAndResolveReturnType(
            request.id,
            chosen: chosen,
            resolved: resolved,
            sema: request.sema,
            dispatchReceiverSymbol: target.companionSymbol,
            contextParameterReceiverSymbols: contextParameterReceiverSymbols
        )
        request.sema.bindings.bindIdentifier(request.id, symbol: chosen)
        request.sema.bindings.bindIdentifier(request.receiverID, symbol: target.companionSymbol)
        request.sema.bindings.bindExprType(request.receiverID, type: target.receiverType)
        request.sema.bindings.markInvokeOperatorCall(request.id)
        applyContractEffects(id: request.id, chosen: chosen, args: request.args, ctx: request.ctx, locals: &locals)
        driver.helpers.checkDeprecation(
            for: chosen,
            sema: request.sema,
            interner: request.interner,
            range: request.range,
            diagnostics: request.sema.diagnostics
        )
        driver.helpers.checkOptIn(
            for: chosen,
            ctx: request.ctx,
            range: request.range,
            diagnostics: request.sema.diagnostics
        )
        request.sema.bindings.bindExprType(request.id, type: resultType)
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
