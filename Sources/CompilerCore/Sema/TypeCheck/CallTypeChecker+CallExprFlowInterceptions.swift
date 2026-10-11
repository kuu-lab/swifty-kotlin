// swiftlint:disable file_length function_body_length cyclomatic_complexity

/// Flow-builder call interceptions from the `inferCallExpr` dispatch chain:
/// the `flow { }` cold-stream factory plus the `FlowCollector.emit` shortcuts
/// that apply while checking a flow-builder lambda.
/// Extracted from `CallTypeChecker+CallExprInference.swift`.
extension CallTypeChecker {
    func inferFlowBuilderCall(
        _ id: ExprID,
        args: [CallArgument],
        range: SourceRange,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings,
        expectedType: TypeID?,
        explicitTypeArgs: [TypeID],
        calleeName: InternedString?
    ) -> TypeID? {
        let ast = ctx.ast
        let sema = ctx.sema
        let interner = ctx.interner
        let knownNames = KnownCompilerNames(interner: interner)


        // --- Flow builder function (CORO-003) ---
        // `flow { emit(...) }` is treated as a builtin cold stream factory.
        // We infer the lambda with a flow-builder scope so unqualified `emit`
        // resolves in Sema fallback.
        let flowFactoryNames: Set<InternedString> = [
            knownNames.flow,
        ]
        if let calleeName,
           flowFactoryNames.contains(calleeName),
           args.count == 1,
           shouldUseBuiltinFlowFactorySpecialHandling(calleeName: calleeName, ctx: ctx, locals: locals)
        {
            let flowLambdaExprID = args[0].expr
            guard isValidBuilderLambdaArgument(flowLambdaExprID, ast: ast) else {
                ctx.semaCtx.diagnostics.error(
                    "KSWIFTK-SEMA-0002",
                    "No viable overload found for call.",
                    range: range
                )
                sema.bindings.bindExprType(id, type: sema.types.errorType)
                return sema.types.errorType
            }
            var flowBuilderCtx = ctx.with(implicitReceiverType: sema.types.anyType)
            flowBuilderCtx.isFlowBuilderLambdaScope = true
            let flowInference = FlowBuilderInferenceSession(
                expectedElementType: explicitTypeArgs.first ?? flowBuilderElementType(expectedType, ctx: ctx)
            )
            flowBuilderCtx.flowBuilderInference = flowInference
            let flowLambdaExpectedType = sema.types.make(.functionType(FunctionType(
                params: [],
                returnType: sema.types.unitType,
                isSuspend: true,
                nullability: .nonNull
            )))
            _ = driver.inferExpr(
                flowLambdaExprID,
                ctx: flowBuilderCtx,
                locals: &locals,
                expectedType: flowLambdaExpectedType
            )
            sema.bindings.markFlowExpr(id)
            let flowElementType = flowInference.elementType(types: sema.types)
            sema.bindings.bindFlowElementType(flowElementType, forExpr: id)
            let flowExprType = driver.helpers.makeFlowType(
                elementType: flowElementType, sema: sema, interner: interner
            ) ?? sema.types.anyType
            sema.bindings.bindExprType(id, type: flowExprType)
            return flowExprType
        }
        return nil
    }

    func postponeFlowEmitAsConstraint(
        _ id: ExprID,
        args: [CallArgument],
        ctx: TypeInferenceContext,
        locals: inout LocalBindings,
        expectedType: TypeID?,
        calleeName: InternedString?
    ) -> TypeID? {
        let ast = ctx.ast
        let sema = ctx.sema
        let interner = ctx.interner
        let knownNames = KnownCompilerNames(interner: interner)

        // KSP-674: flowOf / emptyFlow are Kotlin source (kotlinx.coroutines.flow),
        // so they resolve through normal overload resolution to their bundled
        // declarations. The former builtin fixed-flow special-casing (which only
        // bound a Flow type without a callable target) was removed; missing the
        // import now yields a proper unresolved-reference diagnostic, matching
        // kotlinx.coroutines.

        // --- Flow builder lambda calls (CORO-003) ---
        // During generic receiver-builder inference, postpone an unqualified
        // FlowCollector.emit argument as a constraint on the enclosing type
        // variables. The regular member-call path cannot resolve `R` until
        // these emissions have contributed evidence for it.
        if let builderInference = ctx.builderInference,
           let calleeName,
           calleeName == knownNames.emit,
           args.count == 1,
           locals[calleeName] == nil,
           let receiverType = ctx.implicitReceiverType,
           isFlowCollectorType(receiverType, ctx: ctx),
           let collectorType = resolveClassType(receiverType, sema: sema),
           let elementProjection = collectorType.args.first
        {
            let elementType: TypeID? = switch elementProjection {
            case let .invariant(type), let .in(type), let .out(type): type
            case .star: nil
            }
            if let elementType {
                let emittedType = driver.inferExpr(
                    args[0].expr, ctx: ctx, locals: &locals, expectedType: elementType
                )
                builderInference.constraints.append(contentsOf: ctx.resolver.decomposeSubtypeConstraint(
                    subtype: emittedType, supertype: elementType,
                    typeVarBySymbol: builderInference.typeVarBySymbol,
                    typeSystem: sema.types, blameRange: ast.arena.exprRange(args[0].expr)
                ))
                sema.bindings.bindExprType(id, type: sema.types.unitType)
                return sema.types.unitType
            }
        }
        return nil
    }

    // Inside `flow { ... }`, unqualified `emit` resolves as a builtin
    // effect call and returns Unit.
    func inferEmitInFlowScopeCall(
        _ id: ExprID,
        args: [CallArgument],
        range: SourceRange,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings,
        expectedType: TypeID?,
        calleeName: InternedString?
    ) -> TypeID? {
        let ast = ctx.ast
        let sema = ctx.sema
        let interner = ctx.interner
        let knownNames = KnownCompilerNames(interner: interner)
        if ctx.isFlowBuilderLambdaScope,
           let calleeName,
           calleeName == knownNames.emit,
           args.count == 1,
           locals[calleeName] == nil,
           !flowBuilderEmitHasReceiverMember(ctx: ctx)
        {
            let emittedType = driver.inferExpr(
                args[0].expr, ctx: ctx, locals: &locals,
                expectedType: ctx.flowBuilderInference?.expectedElementType
            )
            recordFlowBuilderEmission(emittedType, range: ast.arena.exprRange(args[0].expr), ctx: ctx)
            sema.bindings.bindExprType(id, type: sema.types.unitType)
            return sema.types.unitType
        }
        return nil
    }
}
